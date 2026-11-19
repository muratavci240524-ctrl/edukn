import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pdfx/pdfx.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../../../../models/assessment/trial_exam_model.dart';
import '../../../../widgets/edukn_logo.dart';
import '../../../../utils/difficulty_scale.dart';
import 'auto_question_detector.dart';

// ───────────────────────────────────────────────────────────────────────────
// Browser-native canvas crop – GPU-accelerated, truly non-blocking on web.
// No Dart image package, no compute(), no ArrayBuffer detach issues.
Future<Uint8List> _cropNativeCanvas(
  Uint8List srcJpeg,
  double left, double top, double selW, double selH,
  double displayW,
) async {
  // 1. Create a blob URL from the raw JPEG bytes
  final blob = html.Blob([srcJpeg], 'image/jpeg');
  final url  = html.Url.createObjectUrlFromBlob(blob);

  // 2. Load into an <img> element so the browser decodes it (GPU path)
  final imgEl = html.ImageElement();
  final loadedC = Completer<void>();
  imgEl.onLoad.listen((_) => loadedC.complete());
  imgEl.onError.listen((_) => loadedC.completeError('img load error'));
  imgEl.src = url;
  await loadedC.future;
  html.Url.revokeObjectUrl(url); // free memory

  final nw = imgEl.naturalWidth;
  final nh = imgEl.naturalHeight;

  // 3. Map display-space selection → pixel coords
  final scaleX = nw / displayW;
  final displayH = displayW * nh / nw;
  final scaleY = nh / displayH;

  final px = (left * scaleX).round().clamp(0, nw - 1);
  final py = (top  * scaleY).round().clamp(0, nh - 1);
  final pw = (selW * scaleX).round().clamp(1, nw - px);
  final ph = (selH * scaleY).round().clamp(1, nh - py);

  // 4. Draw crop onto an offscreen canvas
  final canvas = html.CanvasElement(width: pw, height: ph);
  final ctx = canvas.context2D;
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, pw, ph);
  ctx.drawImageScaledFromSource(imgEl, px, py, pw, ph, 0, 0, pw, ph);

  // 5. Smart Scanner Paper Whitening: remove gray/blue/yellow scan shadows &
  // backside bleed-through while keeping dark text sharp and preserving colors.
  _whitenCanvasPixels(ctx, pw, ph);

  // 6. Export as clean JPEG
  final dataUrl = canvas.toDataUrl('image/jpeg', 0.72);
  final base64Str = dataUrl.split(',').last;
  return base64Decode(base64Str);
}

/// Whitens scanned paper background (bleed-through, shadows, gray/blue tint)
/// to pure #FFFFFF and deepens dark ink while preserving intentional colors.
void _whitenCanvasPixels(html.CanvasRenderingContext2D ctx, int w, int h) {
  if (w <= 0 || h <= 0) return;
  final imgData = ctx.getImageData(0, 0, w, h);
  final d = imgData.data;

  // Estimate the paper background luminance from low-saturation pixels (75th percentile)
  final hist = List<int>.filled(256, 0);
  int neutralCount = 0;
  for (int i = 0; i < d.length; i += 4) {
    final r = d[i], g = d[i + 1], b = d[i + 2];
    final maxC = r > g ? (r > b ? r : b) : (g > b ? g : b);
    final minC = r < g ? (r < b ? r : b) : (g < b ? g : b);
    if (maxC - minC <= 32) {
      final lum = (r * 77 + g * 151 + b * 28) >> 8;
      hist[lum]++;
      neutralCount++;
    }
  }
  int paperBg = 235;
  if (neutralCount > 0) {
    final target = (neutralCount * 0.70).round();
    int acc = 0;
    for (int v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= target) {
        paperBg = v;
        break;
      }
    }
  }
  // White cutoff: anything within ~22 levels of the paper background (or >= 200)
  // that has low color saturation is scan shadow / backside bleed-through → pure white!
  final whitePoint = (paperBg - 22).clamp(188, 228);
  const blackPoint = 55;
  final range = (whitePoint - blackPoint).clamp(1, 255);

  for (int i = 0; i < d.length; i += 4) {
    final r = d[i], g = d[i + 1], b = d[i + 2];
    final maxC = r > g ? (r > b ? r : b) : (g > b ? g : b);
    final minC = r < g ? (r < b ? r : b) : (g < b ? g : b);
    final sat = maxC - minC;
    final lum = (r * 77 + g * 151 + b * 28) >> 8;

    if (sat <= 32 || (lum >= whitePoint && sat <= 42)) {
      if (lum >= whitePoint) {
        d[i] = 255;
        d[i + 1] = 255;
        d[i + 2] = 255;
      } else if (lum <= blackPoint) {
        final v = (lum * 0.55).round().clamp(0, 255);
        d[i] = v;
        d[i + 1] = v;
        d[i + 2] = v;
      } else {
        final v = (((lum - blackPoint) * 255) ~/ range).clamp(0, 255);
        d[i] = v;
        d[i + 1] = v;
        d[i + 2] = v;
      }
    }
  }
  ctx.putImageData(imgData, 0, 0);
}

/// Whitens an already-cropped JPEG/PNG byte array in the browser.
Future<Uint8List> _whitenExistingImageBytes(Uint8List srcBytes) async {
  try {
    final blob = html.Blob([srcBytes], 'image/jpeg');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final imgEl = html.ImageElement();
    final loadedC = Completer<void>();
    imgEl.onLoad.listen((_) => loadedC.complete());
    imgEl.onError.listen((_) => loadedC.completeError('img load error'));
    imgEl.src = url;
    await loadedC.future;
    html.Url.revokeObjectUrl(url);
    final w = imgEl.naturalWidth;
    final h = imgEl.naturalHeight;
    if (w <= 0 || h <= 0) return srcBytes;
    final canvas = html.CanvasElement(width: w, height: h);
    final ctx = canvas.context2D;
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, w, h);
    ctx.drawImage(imgEl, 0, 0);
    _whitenCanvasPixels(ctx, w, h);
    final dataUrl = canvas.toDataUrl('image/jpeg', 0.72);
    return base64Decode(dataUrl.split(',').last);
  } catch (_) {
    return srcBytes;
  }
}
// ───────────────────────────────────────────────────────────────────────────

class ErrorBookletEditorScreen extends StatefulWidget {
  final TrialExam exam;
  final bool isPoolMode;
  const ErrorBookletEditorScreen({
    super.key,
    required this.exam,
    this.isPoolMode = false,
  });

  factory ErrorBookletEditorScreen.forQuestionPool({
    Key? key,
    required String institutionId,
    String classLevel = '7. Sınıf',
  }) {
    const defaultSubjects = [
      'Türkçe',
      'Matematik',
      'Fen Bilimleri',
      'Sosyal Bilgiler',
      'İngilizce',
      'Din Kültürü ve Ahlak Bilgisi',
      'T.C. İnkılap Tarihi',
      'Fizik',
      'Kimya',
      'Biyoloji',
      'Tarih',
      'Coğrafya',
      'Felsefe',
      'Türk Dili ve Edebiyatı',
    ];
    final virtualExam = TrialExam(
      id: 'pool_$institutionId',
      institutionId: institutionId,
      name: 'Soru Havuzu Stüdyosu',
      classLevel: classLevel,
      examTypeId: '',
      examTypeName: 'Soru Havuzu',
      applicationType: TrialExamApplicationType.optical,
      bookletCount: 1,
      sessionCount: 1,
      sessions: [
        TrialExamSession(
          sessionNumber: 1,
          selectedSubjects: defaultSubjects,
        ),
      ],
      date: DateTime.now(),
      isActive: false,
    );
    return ErrorBookletEditorScreen(
      key: key,
      exam: virtualExam,
      isPoolMode: true,
    );
  }

  @override
  State<ErrorBookletEditorScreen> createState() =>
      _ErrorBookletEditorScreenState();
}

class _ErrorBookletEditorScreenState extends State<ErrorBookletEditorScreen> {
  // ─── Session & PDF data ───────────────────────────────────────────────────
  late List<TrialExamSession> _localSessions;
  int _sessionIdx = 0;
  bool _showMobileSidebar = false;

  // Rendered page images per session
  // _pages[sessionIdx] = list of rendered Uint8List per page
  late List<List<Uint8List>> _pages;
  late List<PdfDocument?> _docs;
  late List<int> _totalPages;
  late List<int> _currentPage;

  bool _isLoadingPdf = false;
  final bool _isRenderingPage = false;

  // ─── Zoom & Pan ───────────────────────────────────────────────────────────
  final TransformationController _tx = TransformationController();
  double _zoom = 1.0;
  Size _vpSize = Size.zero;

  // ─── Selection ────────────────────────────────────────────────────────────
  bool _isSelectionMode = false;
  Offset? _startPt;
  Offset? _endPt;
  final GlobalKey _canvasKey = GlobalKey();

  // ─── Question meta ────────────────────────────────────────────────────────
  String? _selectedSubject;
  int _questionNo = 1;
  List<String> _subjects = [];
  List<Map<String, dynamic>> _localCrops = [];
  
  // Subject -> QuestionNo -> { 'success': 85.0, 'outcome': 'Topic Name', 'correctAnswer': 'A' }
  final Map<String, Map<int, Map<String, dynamic>>> _questionStats = {};

  bool _isPublishing = false;
  int _publishCount = 0;
  int _publishTotal = 0;

  String _selectedBooklet = 'A'; // Which booklet does this PDF represent?

  // ─── Manual metadata defaults (for Soru Havuzu mode & custom edits) ───────
  String _manualAnswer = 'A';
  double _manualDifficulty = 50.0; // 75 = Kolay, 50 = Orta, 25 = Zor
  final TextEditingController _manualOutcomeCtrl = TextEditingController();
  final FocusNode _manualOutcomeFocus = FocusNode();
  String _poolClassLevel = '7. Sınıf';
  List<Map<String, dynamic>> _rawOutcomeListDocs = [];
  List<String> _outcomeSuggestions = [];

  // ─── Auto detection (session -> page(1-based) -> boxes in 800px space) ────
  final Map<int, Map<int, List<Rect>>> _autoBoxes = {};
  bool _isAutoDetecting = false;
  double _gapFactor = 1.0;
  List<Rect> get _curBoxes =>
      _autoBoxes[_sessionIdx]?[_currentPage[_sessionIdx]] ?? const [];
  int get _sessionBoxCount => (_autoBoxes[_sessionIdx]?.values ?? [])
      .fold<int>(0, (a, b) => a + b.length);

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();
    _localSessions = List.from(widget.exam.sessions);
    final n = _localSessions.length;
    _pages = List.generate(n, (_) => []);
    _docs = List.filled(n, null);
    _totalPages = List.filled(n, 0);
    _currentPage = List.filled(n, 1);
    _loadAllPdfs();

    _precalculateStats();

    if (_localSessions.isNotEmpty) {
      _subjects = _getActualSubjectsForSession(0);
    }
    // Fallback if subjects aren't defined in the session
    if (_subjects.isEmpty && widget.exam.answerKeys.isNotEmpty) {
      final bookletKeys = widget.exam.answerKeys['A']?.keys ?? widget.exam.answerKeys.values.first.keys;
      _subjects = bookletKeys.toList();
    }
    if (_subjects.isEmpty && widget.isPoolMode) {
      _subjects = List<String>.from(_localSessions.first.selectedSubjects);
    }
    if (_subjects.isNotEmpty) {
      _sortSubjects();
      _selectedSubject = _subjects.first;
    }
    _poolClassLevel = widget.exam.classLevel.isNotEmpty ? widget.exam.classLevel : '7. Sınıf';
    _loadOutcomeSuggestions();
    
    _loadPublishedCrops();
  }

  Future<void> _loadOutcomeSuggestions() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('outcome_lists')
          .where('institutionId', isEqualTo: widget.exam.institutionId)
          .where('isActive', isEqualTo: true)
          .get();
      final List<Map<String, dynamic>> rawDocs = [];
      final Set<String> items = {};
      for (final d in snap.docs) {
        final data = d.data();
        rawDocs.add(data);
        final outcomes = data['outcomes'] as List<dynamic>?;
        if (outcomes != null) {
          for (final o in outcomes) {
            if (o is Map) {
              final desc = (o['description'] ?? '').toString().trim();
              if (desc.isNotEmpty) items.add(desc);
            } else {
              final s = o.toString().trim();
              if (s.isNotEmpty) items.add(s);
            }
          }
        }
      }
      if (mounted) {
        setState(() {
          _rawOutcomeListDocs = rawDocs;
          _outcomeSuggestions = items.toList();
        });
      }
    } catch (_) {}
  }

  static String _normTr(String input) {
    return input
        .trim()
        .replaceAll('İ', 'i')
        .replaceAll('I', 'i')
        .replaceAll('ı', 'i')
        .replaceAll('Ş', 's')
        .replaceAll('ş', 's')
        .replaceAll('Ğ', 'g')
        .replaceAll('ğ', 'g')
        .replaceAll('Ü', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('Ö', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('Ç', 'c')
        .replaceAll('ç', 'c')
        .toLowerCase();
  }

  static String _canonicalBranch(String raw) {
    final n = _normTr(raw);
    if (n.contains('turkce')) return 'turkce';
    if (n.contains('matematik')) return 'matematik';
    if (n.contains('fen')) return 'fen';
    if (n.contains('inkilap')) return 'inkilap';
    if (n.contains('sosyal')) return 'sosyal';
    if (n.contains('din')) return 'din';
    if (n.contains('ingilizce') || n.contains('yabanci dil')) return 'ingilizce';
    if (n.contains('fizik')) return 'fizik';
    if (n.contains('kimya')) return 'kimya';
    if (n.contains('biyoloji')) return 'biyoloji';
    if (n.contains('tarih')) return 'tarih';
    if (n.contains('cografya')) return 'cografya';
    if (n.contains('edebiyat')) return 'edebiyat';
    if (n.contains('felsefe')) return 'felsefe';
    return n;
  }

  static bool _classMatches(String docClass, String selectedClass) {
    final dc = _normTr(docClass);
    final sc = _normTr(selectedClass);
    if (dc.isEmpty || sc.isEmpty) return false;
    if (dc == sc) return true;
    final dm = RegExp(r'^(\d+)').firstMatch(dc);
    final sm = RegExp(r'^(\d+)').firstMatch(sc);
    if (dm != null && sm != null) {
      return dm.group(1) == sm.group(1);
    }
    return dc.contains(sc) || sc.contains(dc);
  }

  /// Seçili Sınıf Seviyesi ve Seçili Branş (Ders) için tanımlı Konu (`depth == 1`)
  /// ve Alt Kazanım (`depth == 2`) öğelerini sırasıyla döndürür.
  List<Map<String, dynamic>> _getStructuredOutcomesFor(String classLevel, String? subject) {
    if (subject == null || subject.trim().isEmpty) return const [];
    final targetBranch = _canonicalBranch(subject);
    final List<Map<String, dynamic>> result = [];
    final Set<String> seenKeys = {};

    for (final data in _rawOutcomeListDocs) {
      final docCls = (data['classLevel'] ?? data['name'] ?? '').toString();
      final docBranch = (data['branchName'] ?? '').toString();
      if (!_classMatches(docCls, classLevel)) continue;
      if (_canonicalBranch(docBranch) != targetBranch) continue;

      final outcomes = data['outcomes'] as List<dynamic>?;
      if (outcomes == null) continue;

      String currentTopic = '';
      for (final o in outcomes) {
        if (o is Map) {
          final desc = (o['description'] ?? '').toString().trim();
          final code = (o['code'] ?? '').toString().trim();
          final int depth = (o['depth'] is int) ? (o['depth'] as int) : 2;
          if (desc.isEmpty) continue;
          if (depth == 1) {
            currentTopic = desc;
          }
          final key = '${depth}_${_normTr(code)}_${_normTr(desc)}';
          if (seenKeys.add(key)) {
            result.add({
              'code': code,
              'description': desc,
              'depth': depth,
              'topicTitle': currentTopic,
            });
          }
        } else {
          final s = o.toString().trim();
          if (s.isNotEmpty && seenKeys.add('2__${_normTr(s)}')) {
            result.add({
              'code': '',
              'description': s,
              'depth': 2,
              'topicTitle': currentTopic,
            });
          }
        }
      }
    }
    return result;
  }

  List<String> _getOutcomesForSubject(String? subject) {
    return _getStructuredOutcomesFor(_poolClassLevel, subject)
        .map((e) => e['description'] as String)
        .toList();
  }

  /// Hem yazarken canlı öneri (autocomplete) sunan hem de sağdaki ok butonundan
  /// seçili Sınıf + Branş kazanımlarını açan akıllı Kazanım / Konu kutusu.
  Widget _buildOutcomeAutocompleteBox({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String classLevel,
    required String? subject,
    double maxWidth = 380,
    bool compact = true,
    VoidCallback? onChanged,
  }) {
    final allItems = _getStructuredOutcomesFor(classLevel, subject);

    return RawAutocomplete<Map<String, dynamic>>(
      textEditingController: controller,
      focusNode: focusNode,
      displayStringForOption: (opt) => (opt['description'] ?? '').toString(),
      optionsBuilder: (TextEditingValue tv) {
        if (allItems.isEmpty) return const Iterable<Map<String, dynamic>>.empty();
        final q = _normTr(tv.text);
        if (q.isEmpty) {
          return allItems;
        }
        return allItems.where((item) {
          final desc = _normTr((item['description'] ?? '').toString());
          final code = _normTr((item['code'] ?? '').toString());
          final topic = _normTr((item['topicTitle'] ?? '').toString());
          return desc.contains(q) || code.contains(q) || topic.contains(q);
        });
      },
      onSelected: (Map<String, dynamic> sel) {
        final desc = (sel['description'] ?? '').toString();
        controller.text = desc;
        controller.selection = TextSelection.fromPosition(
          TextPosition(offset: desc.length),
        );
        onChanged?.call();
        if (mounted) setState(() {});
      },
      fieldViewBuilder: (ctx, textCtrl, fNode, onFieldSubmitted) {
        return ConstrainedBox(
          constraints: BoxConstraints(minWidth: 240, maxWidth: maxWidth),
          child: SizedBox(
            height: compact ? 34 : null,
            child: TextField(
              controller: textCtrl,
              focusNode: fNode,
              maxLines: compact ? 1 : 2,
              minLines: 1,
              onChanged: (_) {
                onChanged?.call();
                if (mounted) setState(() {});
              },
              style: TextStyle(fontSize: compact ? 12 : 13),
              decoration: InputDecoration(
                hintText: allItems.isNotEmpty
                    ? '$classLevel ${subject ?? ''} kazanımı yazın veya seçin... (${allItems.length})'
                    : '$classLevel ${subject ?? ''} için kazanım yazın...',
                hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: compact ? 7 : 10,
                ),
                prefixIcon: const Icon(Icons.psychology_outlined, size: 16, color: Colors.indigo),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (textCtrl.text.isNotEmpty)
                      IconButton(
                        tooltip: 'Temizle',
                        icon: const Icon(Icons.clear, size: 14),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        onPressed: () {
                          textCtrl.clear();
                          onChanged?.call();
                          if (mounted) setState(() {});
                        },
                      ),
                    if (allItems.isNotEmpty)
                      PopupMenuButton<String>(
                        tooltip: '$classLevel • ${subject ?? ''} Kazanım Listesinden Seç',
                        icon: const Icon(Icons.arrow_drop_down, size: 20, color: Colors.indigo),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
                        onSelected: (val) {
                          textCtrl.text = val;
                          textCtrl.selection = TextSelection.fromPosition(
                            TextPosition(offset: val.length),
                          );
                          onChanged?.call();
                          if (mounted) setState(() {});
                        },
                        itemBuilder: (ctx) => [
                          PopupMenuItem<String>(
                            enabled: false,
                            height: 30,
                            child: Text(
                              '$classLevel • ${subject ?? ''} Kazanımları (${allItems.length})',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                              ),
                            ),
                          ),
                          const PopupMenuDivider(height: 4),
                          for (final item in allItems)
                            PopupMenuItem<String>(
                              value: (item['description'] ?? '').toString(),
                              child: Text(
                                (item['depth'] == 1)
                                    ? '📁 ${(item['code'] as String).isNotEmpty ? '${item['code']} ' : ''}${item['description']}'
                                    : '   • ${(item['code'] as String).isNotEmpty ? '${item['code']} - ' : ''}${item['description']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: item['depth'] == 1 ? FontWeight.bold : FontWeight.normal,
                                  color: item['depth'] == 1
                                      ? Colors.indigo.shade900
                                      : const Color(0xFF1E293B),
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.indigo.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.indigo.shade200),
                ),
              ),
            ),
          ),
        );
      },
      optionsViewBuilder: (ctx, onSelected, options) {
        final optList = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(10),
            color: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480, maxHeight: 300),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                    ),
                    child: Text(
                      '$classLevel • ${subject ?? ''} Önerilen Kazanımlar (${optList.length})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade900,
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shrinkWrap: true,
                      itemCount: optList.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
                      itemBuilder: (ctx, idx) {
                        final item = optList[idx];
                        final isTopic = item['depth'] == 1;
                        final code = (item['code'] ?? '').toString();
                        final desc = (item['description'] ?? '').toString();
                        final topicTitle = (item['topicTitle'] ?? '').toString();

                        return InkWell(
                          onTap: () => onSelected(item),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!isTopic && topicTitle.isNotEmpty)
                                  Text(
                                    '📁 $topicTitle',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.indigo.shade400,
                                    ),
                                  ),
                                Text(
                                  isTopic
                                      ? '📁 ${code.isNotEmpty ? '$code ' : ''}$desc (Konu Başlığı)'
                                      : '• ${code.isNotEmpty ? '$code - ' : ''}$desc',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isTopic ? FontWeight.bold : FontWeight.w500,
                                    color: isTopic
                                        ? Colors.indigo.shade900
                                        : const Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _sortSubjects() {
    const order = [
      'türkçe',
      't.c. inkılap',
      'inkılap tarihi',
      'sosyal bilgiler',
      'din kültürü',
      'yabancı dil',
      'ingilizce',
      'matematik',
      'fen bilimleri',
      'fen bilgisi'
    ];
    
    _subjects.sort((a, b) {
      int getIdx(String s) {
        final lower = s.toLowerCase();
        for (int i = 0; i < order.length; i++) {
          if (lower.contains(order[i])) return i;
        }
        return 999;
      }
      return getIdx(a).compareTo(getIdx(b));
    });
  }

  String _normalizeSubjectName(String name) {
    String normalized = name.toLowerCase().trim();
    // Replace Turkish characters for robust matching
    normalized = normalized.replaceAll('ı', 'i')
                           .replaceAll('ğ', 'g')
                           .replaceAll('ü', 'u')
                           .replaceAll('ş', 's')
                           .replaceAll('ö', 'o')
                           .replaceAll('ç', 'c');
    // Common aliases mapping
    if (normalized.contains('matematik') || normalized.contains('mat')) {
      return 'matematik';
    }
    if (normalized.contains('fen') || normalized.contains('fizik') || normalized.contains('kimya') || normalized.contains('biyoloji')) {
      return 'fen';
    }
    if (normalized.contains('sosyal') || normalized.contains('inkilap') || normalized.contains('tarih')) {
      return 'sosyal';
    }
    if (normalized.contains('din') || normalized.contains('ahlak')) {
      return 'din';
    }
    if (normalized.contains('ingilizce') || normalized.contains('yabanci') || normalized.contains('dil')) {
      return 'ingilizce';
    }
    if (normalized.contains('turkce') || normalized.contains('edebiyat')) {
      return 'turkce';
    }
    return normalized;
  }

  List<String> _getActualSubjectsForSession(int sessionIdx) {
    if (sessionIdx < 0 || sessionIdx >= _localSessions.length) return [];
    
    final selected = _localSessions[sessionIdx].selectedSubjects;
    final allActualKeys = widget.exam.answerKeys['A']?.keys.toList() 
        ?? widget.exam.answerKeys.values.firstOrNull?.keys.toList() 
        ?? [];
        
    if (selected.isEmpty) {
      return allActualKeys;
    }
    
    final result = <String>{};
    for (final sel in selected) {
      final normalizedSel = _normalizeSubjectName(sel);
      
      bool foundMatch = false;
      for (final actual in allActualKeys) {
        final normalizedActual = _normalizeSubjectName(actual);
        
        if (normalizedActual.contains(normalizedSel) || normalizedSel.contains(normalizedActual)) {
          result.add(actual);
          foundMatch = true;
        }
      }
      
      if (!foundMatch && allActualKeys.contains(sel)) {
        result.add(sel);
      }
    }
    
    return result.toList();
  }

  String? _getOutcomeForQuestion(String subject, int masterQNo) {
    try {
      // Find booklet A or first available booklet that has outcomes for subject
      String refBooklet = '';
      if (widget.exam.outcomes.containsKey('A') &&
          widget.exam.outcomes['A']!.containsKey(subject)) {
        refBooklet = 'A';
      } else {
        refBooklet = widget.exam.outcomes.keys.firstWhere(
          (k) => widget.exam.outcomes[k]!.containsKey(subject),
          orElse: () => '',
        );
      }
      if (refBooklet.isEmpty) return null;
      
      final list = widget.exam.outcomes[refBooklet]?[subject];
      if (list != null && masterQNo > 0 && masterQNo <= list.length) {
        return list[masterQNo - 1];
      }
    } catch (e) {
      debugPrint('Error getting outcome for question: $e');
    }
    return null;
  }

  /// Populate _questionStats from exam.resultsJson and outcomes
  void _precalculateStats() {
    if (widget.exam.resultsJson == null || widget.exam.resultsJson!.isEmpty) return;

    List<dynamic> results = [];
    try {
      results = jsonDecode(widget.exam.resultsJson!);
    } catch (e) {
      debugPrint('Error parsing resultsJson: $e');
      return;
    }
    if (results.isEmpty) return;

    try {
      var subjects = (widget.exam.answerKeys['A']?.keys 
          ?? widget.exam.answerKeys.values.firstOrNull?.keys 
          ?? widget.exam.outcomes['A']?.keys
          ?? widget.exam.outcomes.values.firstOrNull?.keys
          ?? widget.exam.sessions.expand((s) => s.selectedSubjects).toSet())
          .toList();
      for (var subject in subjects) {
        // Find Master Booklet (preferably 'A')
        String refBooklet = '';
        if (widget.exam.outcomes.containsKey('A') &&
            widget.exam.outcomes['A']!.containsKey(subject)) {
          refBooklet = 'A';
        } else {
          refBooklet = widget.exam.outcomes.keys.firstWhere(
            (k) => widget.exam.outcomes[k]!.containsKey(subject),
            orElse: () => '',
          );
        }
        if (refBooklet.isEmpty) continue;

        final String masterKey = widget.exam.answerKeys[refBooklet]?[subject] ?? '';
        final List<String> masterTopics = widget.exam.outcomes[refBooklet]?[subject] ?? [];
        if (masterKey.isEmpty) continue;

        _questionStats[subject] = {};

        final int qCount = masterKey.length;
        for (int i = 0; i < qCount; i++) {
          final String correctAns = masterKey[i];
          final String topic = i < masterTopics.length ? masterTopics[i] : 'Diğer';

          int correctCount = 0;
          int totalCount = 0;

          for (var student in results) {
            totalCount++;
            final String studentBooklet = student['booklet']?.toString() ?? 'A';
            String studentAnswerStr = '';

            final Map<String, dynamic> subMap = (student['subjects'] is Map) ? Map<String, dynamic>.from(student['subjects']) : {};
            if (subMap[subject] != null) {
              final sData = subMap[subject];
              if (sData is Map) {
                studentAnswerStr = (sData['answers'] ?? sData['cevaplar'] ?? sData['cevap_anahtari'] ?? '').toString();
              }
            }
            if (studentAnswerStr.isEmpty && student['answers'] is Map) {
              studentAnswerStr = (student['answers'][subject] ?? '').toString();
            }

            if (studentAnswerStr.isEmpty) continue;

            int targetIndex = i;
            if (studentBooklet != refBooklet) {
              if (widget.exam.outcomes.containsKey(studentBooklet)) {
                final List<String> studTopics = widget.exam.outcomes[studentBooklet]?[subject] ?? [];
                int masterTopicOccurrence = 0;
                for (int m = 0; m < i; m++) {
                  if (m < masterTopics.length && masterTopics[m] == topic) masterTopicOccurrence++;
                }
                int currentOccurrence = 0;
                int foundIdx = -1;
                for (int sIdx = 0; sIdx < studTopics.length; sIdx++) {
                  if (studTopics[sIdx] == topic) {
                    if (currentOccurrence == masterTopicOccurrence) {
                      foundIdx = sIdx;
                      break;
                    }
                    currentOccurrence++;
                  }
                }
                if (foundIdx != -1) targetIndex = foundIdx;
              }
            }

            if (targetIndex < studentAnswerStr.length) {
              if (studentAnswerStr[targetIndex].toUpperCase() == correctAns.toUpperCase()) {
                correctCount++;
              }
            }
          }

          final double success = totalCount > 0 ? (correctCount / totalCount) * 100 : 0;
          _questionStats[subject]![i + 1] = {
            'success': success,
            'outcome': topic,
            'correctAnswer': correctAns,
          };
        }
      }
    } catch (e) {
      debugPrint('_precalculateStats error: $e');
      // Non-fatal – stats map stays empty; crop still works without metadata.
    }
  }

  /// Load already published questions from Firestore subcollection
  Future<void> _loadPublishedCrops() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('trial_exams')
          .doc(widget.exam.id)
          .collection('questions_pool')
          .get();
          
      final loaded = <Map<String, dynamic>>[];
      for (var doc in snap.docs) {
        final data = doc.data();
        final subject = data['subject'];
        final qNo = data['questionNo'];

        var difficulty = data['difficulty'];
        var outcome = data['outcome'];
        var correctAnswer = data['correctAnswer'];

        // Older questions might not have metadata, or results might have been evaluated later.
        // Sync them against the latest computed values!
        final stat = _questionStats[subject]?[qNo];
        final latestDifficulty = stat?['success'];
        final latestOutcome = stat?['outcome'] ?? _getOutcomeForQuestion(subject as String, qNo as int);
        final latestCorrectAnswer = stat?['correctAnswer'] ?? _correctAnswer(subject as String, qNo as int);

        bool needsUpdate = false;
        final updateMap = <String, dynamic>{};

        if (!widget.isPoolMode) {
          if (latestDifficulty != null && difficulty != latestDifficulty) {
            difficulty = latestDifficulty;
            updateMap['difficulty'] = difficulty;
            needsUpdate = true;
          }
          if (latestOutcome != null && outcome != latestOutcome) {
            outcome = latestOutcome;
            updateMap['outcome'] = outcome;
            needsUpdate = true;
          }
          if (latestCorrectAnswer != null &&
              latestCorrectAnswer != '?' &&
              correctAnswer != latestCorrectAnswer) {
            correctAnswer = latestCorrectAnswer;
            updateMap['correctAnswer'] = correctAnswer;
            needsUpdate = true;
          }

          if (outcome == null && latestOutcome != null) {
            outcome = latestOutcome;
            updateMap['outcome'] = outcome;
            needsUpdate = true;
          }
          if (correctAnswer == null &&
              latestCorrectAnswer != null &&
              latestCorrectAnswer != '?') {
            correctAnswer = latestCorrectAnswer;
            updateMap['correctAnswer'] = correctAnswer;
            needsUpdate = true;
          }
        }

        // Fire-and-forget update to persist backfilled metadata to the DB
        if (needsUpdate && doc.id.isNotEmpty) {
          doc.reference.update(updateMap).catchError((_) {});
        }

        loaded.add({
          'bytes': null,
          'imageUrl': data['imageUrl'],
          'base64Image': data['base64Image'], // New Base64 field
          'subject': subject,
          'questionNo': qNo,
          'isWide': data['isWide'] ?? false,
          'isCritical': data['isCritical'] ?? false,
          'correctAnswer': correctAnswer,
          'difficulty': difficulty,
          'outcome': outcome,
          'loading': false,
          'sessionIdx': data['sessionIdx'] ?? 0,
          'docId': doc.id,
          'passageId': data['passageId'],
          'passageBase64': data['passageBase64'],
          'passageBytes': data['passageBase64'] != null
              ? base64Decode(data['passageBase64'] as String)
              : null,
        });
      }
      
      if (mounted) setState(() => _localCrops = loaded);
    } catch (e) {
      debugPrint('Error loading existing crops: $e');
    }
  }

  /// Manual entry for question number
  Future<void> _showManualQuestionNo() async {
    final ctrl = TextEditingController(text: '$_questionNo');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Soru Numarası Girin'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Tamam')),
        ],
      ),
    );
    if (result != null) {
      final val = int.tryParse(result);
      if (val != null) setState(() => _questionNo = val);
    }
  }

  /// Switch active session and sync subjects/questionNo for that session.
  void _switchToSession(int idx) {
    setState(() {
      _sessionIdx = idx;
      _subjects = _getActualSubjectsForSession(idx);
      if (_subjects.isEmpty && widget.exam.answerKeys.isNotEmpty) {
        final bookletKeys = widget.exam.answerKeys['A']?.keys ?? widget.exam.answerKeys.values.first.keys;
        _subjects = bookletKeys.toList();
      }
      _sortSubjects();
      _selectedSubject =
          _subjects.isNotEmpty ? _subjects.first : null;
      _questionNo = 1;
    });
  }

  PdfDocument? get _doc => _docs[_sessionIdx];
  List<Uint8List> get _curPages => _pages[_sessionIdx];
  Uint8List? get _pageImage {
    final idx = _currentPage[_sessionIdx] - 1;
    return (idx >= 0 && idx < _curPages.length) ? _curPages[idx] : null;
  }

  Future<void> _loadAllPdfs() async {
    for (int i = 0; i < _localSessions.length; i++) {
      final url = _localSessions[i].fileUrl;
      if (url == null) continue;
      try {
        final res = await http.get(Uri.parse(url));
        if (res.statusCode == 200) {
          await _openDoc(res.bodyBytes, sessionIdx: i);
        }
      } catch (e) {
        debugPrint('PDF load[$i]: $e');
      }
    }
  }

  Future<void> _openDoc(Uint8List bytes, {required int sessionIdx}) async {
    try {
      final doc = await PdfDocument.openData(bytes);
      _docs[sessionIdx] = doc;
      _totalPages[sessionIdx] = doc.pagesCount;
      _currentPage[sessionIdx] = 1;
      _pages[sessionIdx] = [];
      if (mounted) setState(() {});
      // Render all pages (cached)
      await _renderAllPages(sessionIdx);
    } catch (e) {
      debugPrint('openDoc[$sessionIdx]: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF yüklenirken hata: $e')),
        );
      }
    }
  }

  Future<void> _renderAllPages(int sessionIdx) async {
    final doc = _docs[sessionIdx];
    if (doc == null) return;
    final rendered = <Uint8List>[];
    for (int p = 1; p <= doc.pagesCount; p++) {
      final page = await doc.getPage(p);
      final r = await page.render(
        width: page.width * 2,
        height: page.height * 2,
        quality: 100,
      );
      await page.close();
      if (r != null) {
        rendered.add(r.bytes);
        // Center PDF on first page render
        if (rendered.length == 1 && sessionIdx == _sessionIdx) {
          SchedulerBinding.instance.addPostFrameCallback((_) => _centerPdf());
        }
      }
    }
    if (mounted) {
      setState(() {
        _pages[sessionIdx] = rendered;
      });
    }
  }

  /// Centers the 800-px wide PDF in the current viewport.
  void _centerPdf() {
    if (_vpSize == Size.zero) {
      // Viewport not measured yet — retry next frame
      SchedulerBinding.instance.addPostFrameCallback((_) => _centerPdf());
      return;
    }
    const imageW = 800.0;
    const topPad = 24.0;
    final tx = (_vpSize.width - imageW) / 2;
    setState(() {
      _zoom = 1.0;
      _tx.value = Matrix4.identity()..translate(tx, topPad);
    });
  }

  /// Handles mouse-wheel scroll: zooms centered on the cursor position.
  void _onScroll(PointerScrollEvent event) {
    if (_isSelectionMode) return;
    // Ctrl+scroll or plain scroll → zoom
    final delta = event.scrollDelta.dy;
    if (delta == 0) return;
    // 3% per scroll tick, direction: scroll down = zoom out
    final factor = delta > 0 ? 0.97 : 1.03;
    final newZoom = (_zoom * factor).clamp(0.3, 8.0);
    setState(() {
      final oldZoom = _zoom;
      _zoom = newZoom;
      // Scale around cursor position for natural feel
      final cursor = event.localPosition;
      final m = _tx.value;
      final tx = m.entry(0, 3);
      final ty = m.entry(1, 3);
      final ratio = _zoom / oldZoom;
      _tx.value = Matrix4.identity()
        ..translate(cursor.dx + (tx - cursor.dx) * ratio,
                    cursor.dy + (ty - cursor.dy) * ratio)
        ..scale(_zoom);
    });
  }

  /// Opens a dialog to type zoom % manually.
  Future<void> _showManualZoomDialog() async {
    final ctrl = TextEditingController(text: '${(_zoom * 100).round()}');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zoom Yüzdesi Girin'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            suffixText: '%',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Uygula'),
          ),
        ],
      ),
    );
    if (result != null) {
      final val = double.tryParse(result);
      if (val != null) _applyZoom(val / 100.0);
    }
    ctrl.dispose();
  }

  @override
  void dispose() {
    for (final d in _docs) d?.close();
    _tx.dispose();
    super.dispose();
  }

  // ─── Zoom (centered on viewport) ─────────────────────────────────────────
  void _applyZoom(double newZoom) {
    setState(() {
      final oldZoom = _zoom == 0 ? 1.0 : _zoom;
      _zoom = newZoom.clamp(0.3, 8.0);
      final cx = _vpSize.width / 2;
      final cy = _vpSize.height / 2;
      final m = _tx.value;
      final tx = m.entry(0, 3);
      final ty = m.entry(1, 3);
      final ratio = _zoom / oldZoom;
      _tx.value = Matrix4.identity()
        ..translate(cx + (tx - cx) * ratio, cy + (ty - cy) * ratio)
        ..scale(_zoom);
    });
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  String? _correctAnswer(String subject, int qNoInCurrentBooklet) {
    final int masterQNo = _getMasterQuestionNo(_selectedBooklet, subject, qNoInCurrentBooklet);
    
    // First try pre-calculated stats (usually indexed by Master A)
    final statAns = _questionStats[subject]?[masterQNo]?['correctAnswer'];
    if (statAns != null) return statAns as String;
    
    // Iterate all booklets to find one that has this subject
    for (final booklet in widget.exam.answerKeys.keys) {
      final ansStr = widget.exam.answerKeys[booklet]?[subject];
      // If we are looking in A, use masterQNo. If looking in the current booklet, use qNoInCurrentBooklet.
      final int targetIdx = (booklet == 'A') ? masterQNo - 1 : (booklet == _selectedBooklet ? qNoInCurrentBooklet - 1 : -1);
      
      if (ansStr != null && ansStr.isNotEmpty && targetIdx >= 0 && targetIdx < ansStr.length) {
        return ansStr[targetIdx];
      }
    }
    return null;
  }

  int _getMasterQuestionNo(String booklet, String subject, int qNo) {
    if (booklet == 'A') return qNo;

    final mappingStr = widget.exam.bookletMapping[booklet]?[subject];
    if (mappingStr == null || mappingStr.isEmpty) return qNo;

    // 1. Try to parse "1(4), 2(3)" format
    final RegExp pairRegex = RegExp(r'(\d+)\((\d+)\)');
    final matches = pairRegex.allMatches(mappingStr);
    for (var m in matches) {
      if (int.tryParse(m.group(1)!) == qNo) {
        return int.tryParse(m.group(2)!) ?? qNo;
      }
    }

    // 2. Fallback to comma-separated list "4, 3, 2, 1"
    final RegExp numRegex = RegExp(r'\d+');
    final numbers = numRegex.allMatches(mappingStr).map((m) => int.parse(m.group(0)!)).toList();
    if (qNo > 0 && qNo <= numbers.length) {
      return numbers[qNo - 1];
    }

    return qNo;
  }

  String _getAllBookletMappings(String subject, int masterQNo) {
    List<String> mappings = [];
    for (int i = 0; i < widget.exam.bookletCount; i++) {
      final char = String.fromCharCode(65 + i);
      if (char == 'A') continue;

      final mappingStr = widget.exam.bookletMapping[char]?[subject] ?? '';
      if (mappingStr.isEmpty) continue;

      // 1. Check "1(4)" format
      final RegExp pairRegex = RegExp(r'(\d+)\((\d+)\)');
      final matches = pairRegex.allMatches(mappingStr);
      bool found = false;
      for (var m in matches) {
        if (int.tryParse(m.group(2)!) == masterQNo) {
          mappings.add('$char-${m.group(1)}');
          found = true;
          break;
        }
      }

      // 2. Check "4,3,2,1" format
      if (!found) {
        final RegExp numRegex = RegExp(r'\d+');
        final List<int> numbers = numRegex.allMatches(mappingStr).map((m) => int.parse(m.group(0)!)).toList();
        final int idx = numbers.indexOf(masterQNo);
        if (idx != -1) {
          mappings.add('$char-${idx + 1}');
        }
      }
    }
    return mappings.isEmpty ? '' : ' (${mappings.join(', ')})';
  }

  String _getDifficultyLabel(double success) => DifficultyScale.labelOf(success);

  Color _getDifficultyColor(double success) => DifficultyScale.colorOf(success);

  // ─── Auto question detection (free, rule based) ───────────────────────────
  bool _autoTrim = true;
  Uint8List? _grayFor;
  Uint8List? _grayData;
  int _grayW = 0, _grayH = 0;

  // ─── Shared Passage (Ortak Metin) state ──────────────────────────────────
  String? _activePassageId;
  Uint8List? _activePassageBytes;
  int? _activePassageSession;
  int? _activePassagePage;
  Rect? _activePassageRect;

  void _clearActivePassage() {
    setState(() {
      _activePassageId = null;
      _activePassageBytes = null;
      _activePassageSession = null;
      _activePassagePage = null;
      _activePassageRect = null;
    });
  }

  Future<void> _pinBoxAsPassage(int i) async {
    final session = _sessionIdx;
    final page = _currentPage[session];
    final list = _autoBoxes[session]?[page];
    if (list == null || i < 0 || i >= list.length) return;
    if (page - 1 >= _pages[session].length) return;
    final r = list[i];

    // Toggle off if already pinned to this exact box
    if (_activePassageId != null &&
        _activePassageSession == session &&
        _activePassagePage == page &&
        _activePassageRect == r) {
      _clearActivePassage();
      return;
    }

    final img = _pages[session][page - 1];
    try {
      var trimmed = r;
      if (_autoTrim) {
        trimmed = await _trimPassageRect(img, r);
        list[i] = trimmed;
      }
      final bytes = await _cropNativeCanvas(
        img,
        trimmed.left,
        trimmed.top,
        trimmed.width,
        trimmed.height,
        800.0,
      );
      if (!mounted) return;
      setState(() {
        _activePassageId = 'p_${DateTime.now().millisecondsSinceEpoch}';
        _activePassageBytes = bytes;
        _activePassageSession = session;
        _activePassagePage = page;
        _activePassageRect = trimmed;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: Colors.orange,
        content: Text(
          '📌 Ortak metin sabitlendi! Hata kitapçığında üstüne öğrencinin soru sırasına göre otomatik açıklama yazılacaktır.',
        ),
      ));
    } catch (e) {
      debugPrint('pinBoxAsPassage error: $e');
    }
  }

  /// Decodes a page image to 1200px wide grayscale (cached for the last page).
  Future<void> _ensureGray(Uint8List bytes) async {
    if (identical(_grayFor, bytes) && _grayData != null) return;
    const aw = 1200;
    final blob = html.Blob([bytes], 'image/jpeg');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final img = html.ImageElement();
    final loaded = Completer<void>();
    img.onLoad.listen((_) => loaded.complete());
    img.onError.listen((_) => loaded.completeError('img load error'));
    img.src = url;
    await loaded.future;
    html.Url.revokeObjectUrl(url);
    final nw = img.naturalWidth, nh = img.naturalHeight;
    final ah = (nh * aw / nw).round();
    final canvas = html.CanvasElement(width: aw, height: ah);
    final ctx = canvas.context2D;
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, aw, ah);
    ctx.drawImageScaled(img, 0, 0, aw, ah);
    final data = ctx.getImageData(0, 0, aw, ah).data;
    final gray = Uint8List(aw * ah);
    for (int i = 0, j = 0; i < gray.length; i++, j += 4) {
      gray[i] = (data[j] * 77 + data[j + 1] * 151 + data[j + 2] * 28) >> 8;
    }
    _grayFor = bytes;
    _grayData = gray;
    _grayW = aw;
    _grayH = ah;
  }

  /// Removes white margins from a rect given in 800px display coordinates.
  Future<Rect> _trimRect(Uint8List bytes, Rect r) async {
    await _ensureGray(bytes);
    const s = 1200 / 800;
    final t = AutoQuestionDetector.tighten(
        _grayData!, _grayW, _grayH, r.left * s, r.top * s, r.right * s, r.bottom * s,
        pad: 4);
    if (t == null) return r;
    return Rect.fromLTRB(t.left / s, t.top / s, t.right / s, t.bottom / s);
  }

  /// Removes white margins AND any standalone 1-line leading instruction
  /// (e.g. "4, 5 ve 6. soruları aşağıdaki metne göre cevaplayınız.") from a
  /// shared passage rect so the student's Error Booklet can print its own
  /// dynamic question numbers cleanly at the top.
  Future<Rect> _trimPassageRect(Uint8List bytes, Rect r) async {
    await _ensureGray(bytes);
    const s = 1200 / 800;
    final t = AutoQuestionDetector.stripLeadingInstructionLine(
        _grayData!, _grayW, _grayH, r.left * s, r.top * s, r.right * s, r.bottom * s,
        pad: 4);
    if (t == null) return r;
    return Rect.fromLTRB(t.left / s, t.top / s, t.right / s, t.bottom / s);
  }
  Future<List<Rect>> _detectPage(Uint8List bytes) async {
    const aw = 1200;
    final blob = html.Blob([bytes], 'image/jpeg');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final img = html.ImageElement();
    final loaded = Completer<void>();
    img.onLoad.listen((_) => loaded.complete());
    img.onError.listen((_) => loaded.completeError('img load error'));
    img.src = url;
    await loaded.future;
    html.Url.revokeObjectUrl(url);

    final nw = img.naturalWidth;
    final nh = img.naturalHeight;
    if (nw == 0 || nh == 0) return [];
    final ah = (nh * aw / nw).round();
    final canvas = html.CanvasElement(width: aw, height: ah);
    final ctx = canvas.context2D;
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, aw, ah);
    ctx.drawImageScaled(img, 0, 0, aw, ah);
    final data = ctx.getImageData(0, 0, aw, ah).data;
    final gray = Uint8List(aw * ah);
    for (int i = 0, j = 0; i < gray.length; i++, j += 4) {
      gray[i] = (data[j] * 77 + data[j + 1] * 151 + data[j + 2] * 28) >> 8;
    }
    final textGray = AutoQuestionDetector.textGrayFromRgba(data, aw * ah);
    final boxes = AutoQuestionDetector.detect(gray, aw, ah, gapFactor: _gapFactor, textGray: textGray);
    const s = 800.0 / aw;
    return boxes
        .map((b) => Rect.fromLTRB(b.left * s, b.top * s, b.right * s, b.bottom * s))
        .toList();
  }

  Future<void> _autoDetect({required bool allPages}) async {
    if (_isAutoDetecting) return;
    final session = _sessionIdx;
    final pages = allPages
        ? List<int>.generate(_curPages.length, (i) => i + 1)
        : [_currentPage[session]];
    if (_curPages.isEmpty) return;
    setState(() {
      _isAutoDetecting = true;
      _isSelectionMode = false;
      _startPt = null;
      _endPt = null;
    });
    int found = 0;
    try {
      for (final p in pages) {
        if (p - 1 >= _pages[session].length) continue;
        final boxes = await _detectPage(_pages[session][p - 1]);
        found += boxes.length;
        _autoBoxes.putIfAbsent(session, () => {})[p] = boxes;
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('autoDetect error: $e');
    }
    if (!mounted) return;
    setState(() => _isAutoDetecting = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(found == 0
          ? 'Soru bulunamadı. Elle seçim yapabilirsiniz.'
          : '$found soru algılandı. Yanlışları ✕ ile silin, sonra "HEPSİNİ KES" deyin.'),
    ));
  }

  void _deleteAutoBox(Rect r) {
    setState(() => _autoBoxes[_sessionIdx]?[_currentPage[_sessionIdx]]?.remove(r));
  }

  Future<void> _cutAllAutoBoxes() async {
    final session = _sessionIdx;
    if (_selectedSubject == null) return;
    final pageMap = _autoBoxes[session];
    if (pageMap == null) return;
    final pageNos = pageMap.keys.toList()..sort();
    for (final p in pageNos) {
      if (p - 1 >= _pages[session].length) continue;
      final img = _pages[session][p - 1];
      for (final r in List<Rect>.from(pageMap[p] ?? const [])) {
        // Skip cutting the pinned passage box itself as a standalone question
        if (_activePassageId != null &&
            _activePassageSession == session &&
            _activePassagePage == p &&
            _activePassageRect == r) {
          continue;
        }
        await _cropFromRect(img, r.left, r.top, r.right, r.bottom, applyAutoTrim: false);
      }
    }
    if (mounted) setState(() => _autoBoxes.remove(session));
  }

  bool _draggingBox = false;

  void _updateAutoBox(int i, Rect Function(Rect) f) {
    final list = _autoBoxes[_sessionIdx]?[_currentPage[_sessionIdx]];
    if (list == null || i < 0 || i >= list.length) return;
    final oldR = list[i];
    var r = f(oldR);
    // keep sane size and stay inside the 800px wide page
    if (r.width < 30 || r.height < 20) return;
    if (r.left < 0 || r.top < 0 || r.right > 800) return;
    setState(() {
      list[i] = r;
      if (_activePassageId != null &&
          _activePassageSession == _sessionIdx &&
          _activePassagePage == _currentPage[_sessionIdx] &&
          _activePassageRect == oldR) {
        _activePassageRect = r;
      }
    });
  }

  /// Cuts a single detected box right away (✓ button).
  Future<void> _cutOneAutoBox(int i) async {
    final session = _sessionIdx;
    final page = _currentPage[session];
    final list = _autoBoxes[session]?[page];
    if (list == null || i >= list.length || _selectedSubject == null) return;
    if (page - 1 >= _pages[session].length) return;
    final r = list[i];
    final img = _pages[session][page - 1];
    setState(() => list.removeAt(i));
    await _cropFromRect(img, r.left, r.top, r.right, r.bottom, applyAutoTrim: false);
  }

  /// Drag handle. [onDrag] receives the delta in page coordinates.
  Widget _dragHandle(double left, double top, IconData? icon, MouseCursor cursor,
      void Function(Offset d) onDrag) {
    const size = 18.0;
    return Positioned(
      left: left - size / 2,
      top: top - size / 2,
      child: MouseRegion(
        cursor: cursor,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => setState(() => _draggingBox = true),
          onPointerMove: (e) => onDrag(e.delta / (_zoom == 0 ? 1 : _zoom)),
          onPointerUp: (_) => setState(() => _draggingBox = false),
          onPointerCancel: (_) => setState(() => _draggingBox = false),
          child: Container(
            width: size, height: size,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.indigo, width: 2),
              borderRadius: BorderRadius.circular(icon == null ? 2 : 9),
            ),
            child: icon == null ? null : Icon(icon, size: 12, color: Colors.indigo),
          ),
        ),
      ),
    );
  }

  List<Widget> _autoBoxOverlays() {
    final boxes = List<Rect>.from(_curBoxes);
    return [
      for (int i = 0; i < boxes.length; i++) ...[
        Positioned.fromRect(
          rect: boxes[i],
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: (_activePassageId != null &&
                            _activePassageSession == _sessionIdx &&
                            _activePassagePage == _currentPage[_sessionIdx] &&
                            _activePassageRect == boxes[i]
                        ? Colors.orange
                        : Colors.indigo)
                    .withValues(alpha: 0.10),
                border: Border.all(
                  color: _activePassageId != null &&
                          _activePassageSession == _sessionIdx &&
                          _activePassagePage == _currentPage[_sessionIdx] &&
                          _activePassageRect == boxes[i]
                      ? Colors.orange.shade700
                      : Colors.indigo,
                  width: 2,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: boxes[i].left,
          top: boxes[i].top - 14 < 0 ? 0 : boxes[i].top - 14,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              color: _activePassageId != null &&
                      _activePassageSession == _sessionIdx &&
                      _activePassagePage == _currentPage[_sessionIdx] &&
                      _activePassageRect == boxes[i]
                  ? Colors.orange.shade700
                  : Colors.indigo,
              child: Text(
                  _activePassageId != null &&
                          _activePassageSession == _sessionIdx &&
                          _activePassagePage == _currentPage[_sessionIdx] &&
                          _activePassageRect == boxes[i]
                      ? '📌 ORTAK METİN (AKTİF)'
                      : '${i + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        // ✕ delete
        Positioned(
          left: boxes[i].right - 30,
          top: boxes[i].top,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _deleteAutoBox(boxes[i]),
            child: Container(
              width: 30, height: 30,
              color: Colors.red.shade600,
              child: const Icon(Icons.close, size: 20, color: Colors.white),
            ),
          ),
        ),
        // ✓ cut this one
        Positioned(
          left: boxes[i].right - 62,
          top: boxes[i].top,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _cutOneAutoBox(i),
            child: Container(
              width: 30, height: 30,
              color: Colors.green.shade600,
              child: const Icon(Icons.check, size: 20, color: Colors.white),
            ),
          ),
        ),
        // 📌 pin as shared passage (Ortak Metin)
        Positioned(
          left: boxes[i].right - 94,
          top: boxes[i].top,
          child: Tooltip(
            message: _activePassageId != null &&
                    _activePassageSession == _sessionIdx &&
                    _activePassagePage == _currentPage[_sessionIdx] &&
                    _activePassageRect == boxes[i]
                ? 'Ortak Metni Kaldır'
                : 'Ortak Metin Yap (Bağlı Sorular İçin)',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _pinBoxAsPassage(i),
              child: Container(
                width: 30,
                height: 30,
                color: _activePassageId != null &&
                        _activePassageSession == _sessionIdx &&
                        _activePassagePage == _currentPage[_sessionIdx] &&
                        _activePassageRect == boxes[i]
                    ? Colors.orange.shade800
                    : Colors.amber.shade700,
                child: const Icon(Icons.push_pin, size: 18, color: Colors.white),
              ),
            ),
          ),
        ),
        // corner handles (resize)
        _dragHandle(boxes[i].left, boxes[i].top, null, SystemMouseCursors.resizeUpLeftDownRight,
            (d) => _updateAutoBox(i, (r) => Rect.fromLTRB(r.left + d.dx, r.top + d.dy, r.right, r.bottom))),
        _dragHandle(boxes[i].right, boxes[i].top, null, SystemMouseCursors.resizeUpRightDownLeft,
            (d) => _updateAutoBox(i, (r) => Rect.fromLTRB(r.left, r.top + d.dy, r.right + d.dx, r.bottom))),
        _dragHandle(boxes[i].left, boxes[i].bottom, null, SystemMouseCursors.resizeUpRightDownLeft,
            (d) => _updateAutoBox(i, (r) => Rect.fromLTRB(r.left + d.dx, r.top, r.right, r.bottom + d.dy))),
        _dragHandle(boxes[i].right, boxes[i].bottom, null, SystemMouseCursors.resizeUpLeftDownRight,
            (d) => _updateAutoBox(i, (r) => Rect.fromLTRB(r.left, r.top, r.right + d.dx, r.bottom + d.dy))),
        // edge handles (top / bottom / left / right) for quick vertical & horizontal fixing
        _dragHandle(boxes[i].center.dx, boxes[i].top, null, SystemMouseCursors.resizeUpDown,
            (d) => _updateAutoBox(i, (r) => Rect.fromLTRB(r.left, r.top + d.dy, r.right, r.bottom))),
        _dragHandle(boxes[i].center.dx, boxes[i].bottom, null, SystemMouseCursors.resizeUpDown,
            (d) => _updateAutoBox(i, (r) => Rect.fromLTRB(r.left, r.top, r.right, r.bottom + d.dy))),
        _dragHandle(boxes[i].left, boxes[i].center.dy, null, SystemMouseCursors.resizeLeftRight,
            (d) => _updateAutoBox(i, (r) => Rect.fromLTRB(r.left + d.dx, r.top, r.right, r.bottom))),
        _dragHandle(boxes[i].right, boxes[i].center.dy, null, SystemMouseCursors.resizeLeftRight,
            (d) => _updateAutoBox(i, (r) => Rect.fromLTRB(r.left, r.top, r.right + d.dx, r.bottom))),
        // move whole box
        _dragHandle(boxes[i].center.dx, boxes[i].center.dy, Icons.open_with, SystemMouseCursors.move,
            (d) => _updateAutoBox(i, (r) => r.shift(d))),
        // Floating Answer & Difficulty bar below the active/latest box
        if (i == boxes.length - 1)
          Positioned(
            left: boxes[i].left.clamp(0.0, 900.0),
            top: boxes[i].bottom + 8,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(10),
              color: const Color(0xFF1E293B),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Cevap:', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 4),
                    for (final ans in ['A', 'B', 'C', 'D', 'E'])
                      Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: InkWell(
                          onTap: () => setState(() => _manualAnswer = ans),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _manualAnswer == ans ? Colors.indigoAccent : Colors.white12,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _manualAnswer == ans ? Colors.white : Colors.white24,
                                width: 1,
                              ),
                            ),
                            child: Text(
                              ans,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: _manualAnswer == ans ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Container(width: 1, height: 18, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 6)),
                    for (final diffEntry in [
                      ('Kolay', 80.0, Colors.green),
                      ('Orta', 55.0, Colors.orange),
                      ('Zor', 25.0, Colors.redAccent),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: InkWell(
                          onTap: () => setState(() => _manualDifficulty = diffEntry.$2),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: _getDifficultyLabel(_manualDifficulty) == diffEntry.$1
                                  ? diffEntry.$3
                                  : Colors.white12,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              diffEntry.$1,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => _cutOneAutoBox(i),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade600,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check, size: 13, color: Colors.white),
                            SizedBox(width: 3),
                            Text('Kes', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ];
  }

  /// When the user finishes dragging a rough manual selection (`onPanEnd`),
  /// automatically analyses the pixels inside the rectangle, strips white
  /// margins, column dividers, and any hanging question number ("1.", "10."),
  /// smoothly animates the box onto the tight content bounds, and locks it in
  /// as a persistent box on the page (so clicking an empty spot or selecting
  /// another box never erases it — it only closes when ✕ or ✓ is clicked).
  Future<void> _snapManualSelectionOnPanEnd() async {
    final imgBytes = _pageImage;
    if (imgBytes == null || _startPt == null || _endPt == null) return;
    final fromRect = Rect.fromPoints(_startPt!, _endPt!);
    if (fromRect.width < 20 || fromRect.height < 16) {
      // Just an empty click — clear temporary drag points without touching existing boxes!
      setState(() {
        _startPt = null;
        _endPt = null;
      });
      return;
    }

    try {
      final trimmedPage = await _trimRect(imgBytes, fromRect);
      if (!mounted) return;

      // Smooth ~110ms ease-out snap animation (6 frames)
      const steps = 6;
      for (int step = 1; step <= steps; step++) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
        if (!mounted || _startPt == null || _endPt == null) return;
        final t = 1.0 - ((1.0 - step / steps) * (1.0 - step / steps) * (1.0 - step / steps));
        final cur = Rect.lerp(fromRect, trimmedPage, t)!;
        setState(() {
          _startPt = cur.topLeft;
          _endPt = cur.bottomRight;
        });
      }

      if (!mounted) return;
      final session = _sessionIdx;
      final page = _currentPage[session];
      setState(() {
        final pageList = _autoBoxes.putIfAbsent(session, () => {}).putIfAbsent(page, () => []);
        pageList.add(trimmedPage);
        _startPt = null;
        _endPt = null;
      });
    } catch (e) {
      debugPrint('snapManualSelection error: $e');
      if (mounted) {
        final session = _sessionIdx;
        final page = _currentPage[session];
        setState(() {
          final pageList = _autoBoxes.putIfAbsent(session, () => {}).putIfAbsent(page, () => []);
          pageList.add(fromRect);
          _startPt = null;
          _endPt = null;
        });
      }
    }
  }

  /// Crops a page image (rendered at 800px display width) with a rect given in
  /// display coordinates and adds it to the pool using the current subject /
  /// question number (which then auto-advance).
  Future<void> _cropFromRect(Uint8List imgBytes, double left, double top,
      double right, double bottom, {bool applyAutoTrim = true}) async {
    if (_selectedSubject == null) return;

    if (_autoTrim && applyAutoTrim) {
      try {
        final t = await _trimRect(imgBytes, Rect.fromLTRB(left, top, right, bottom));
        left = t.left;
        top = t.top;
        right = t.right;
        bottom = t.bottom;
      } catch (e) {
        debugPrint('trim error: $e');
      }
    }
    // ── Capture all state NOW (before any await) ──
    try {
      final subject    = _selectedSubject!;
      final qNoInBooklet = _questionNo;
      final masterQNo  = _getMasterQuestionNo(_selectedBooklet, subject, qNoInBooklet);
      
      final stat       = _questionStats[subject]?[masterQNo];
      final rawAns = stat?['correctAnswer'] ?? _correctAnswer(subject, qNoInBooklet);
      final correctAns = (widget.isPoolMode || rawAns == '?' || rawAns.isEmpty)
          ? _manualAnswer
          : rawAns;
      final difficulty = widget.isPoolMode
          ? _manualDifficulty
          : (stat?['success'] ?? _manualDifficulty);
      final rawOutcome = stat?['outcome'] ?? _getOutcomeForQuestion(subject, masterQNo);
      final manualOutText = _manualOutcomeCtrl.text.trim();
      final outcome = (widget.isPoolMode || rawOutcome == null || rawOutcome.isEmpty)
          ? (manualOutText.isNotEmpty ? manualOutText : rawOutcome)
          : rawOutcome;
      final passageId  = _activePassageId;
      Uint8List? passageBytes = _activePassageBytes;
      if (passageId != null &&
          _activePassageSession != null &&
          _activePassagePage != null &&
          _activePassageRect != null &&
          _activePassagePage! - 1 < _pages[_activePassageSession!].length) {
        try {
          final pr = _activePassageRect!;
          passageBytes = await _cropNativeCanvas(
            _pages[_activePassageSession!][_activePassagePage! - 1],
            pr.left,
            pr.top,
            pr.width,
            pr.height,
            800.0,
          );
          _activePassageBytes = passageBytes;
        } catch (_) {}
      }

      const displayW = 800.0;

      // ── Auto-advance: if questionNo exceeds this subject's answer count,
      //    move to the next subject in the list and restart at question 1.
      void _autoAdvanceSubject() {
        try {
          if (_selectedSubject == null) return;
          // Find any booklet that has this subject's answer key, default to A
          String? answers = widget.exam.answerKeys['A']?[_selectedSubject!];
          if (answers == null || answers.isEmpty) {
            for (final booklet in widget.exam.answerKeys.keys) {
              if (widget.exam.answerKeys[booklet]?[_selectedSubject!]?.isNotEmpty == true) {
                answers = widget.exam.answerKeys[booklet]?[_selectedSubject!];
                break;
              }
            }
          }
          if (answers == null || answers.isEmpty) return;
          if (_questionNo > answers.length) {
            final idx = _subjects.indexOf(_selectedSubject!);
            if (idx >= 0 && idx < _subjects.length - 1) {
              _selectedSubject = _subjects[idx + 1];
              _questionNo = 1;
            }
          }
        } catch (e) {
          debugPrint('auto advance error: $e');
        }
      }

      // ── Immediately register a loading placeholder ↔ sidebar stays live ──
      final placeholder = <String, dynamic>{
        'bytes': null, 'subject': subject, 'questionNo': masterQNo,
        'isWide': false, 'isCritical': false, 'correctAnswer': correctAns, 
        'difficulty': difficulty, 'outcome': outcome,
        'loading': true,
        'originalQNo': qNoInBooklet, // Keep track of source
        'sourceBooklet': _selectedBooklet,
        'passageId': passageId,
        'passageBytes': passageBytes,
      };
      setState(() {
        _localCrops.add(placeholder);
        _questionNo++;
        _startPt = null;
        _endPt   = null;
        _autoAdvanceSubject();      // check if we should jump to next subject
      });

      // ── Wait for exactly one frame so placeholder paints before canvas work ──
      await SchedulerBinding.instance.endOfFrame;


      // ── Browser canvas crop: GPU-accelerated, truly non-blocking ──
      // dart:html canvas decode/encode runs in the browser's rendering pipeline.
      // srcBytes are read (not transferred), so the page image stays intact.
      try {
        final cropBytes = await _cropNativeCanvas(
          imgBytes,                                // original stays intact
          left, top, right - left, bottom - top,
          displayW,
        );

        if (mounted) {
          setState(() {
            final idx = _localCrops.indexOf(placeholder);
            if (idx != -1) {
              _localCrops[idx] = {
                'bytes': cropBytes, 'subject': subject, 'questionNo': masterQNo,
                'isWide': false, 'isCritical': false, 'correctAnswer': correctAns, 
                'difficulty': difficulty, 'outcome': outcome,
                'loading': false,
                'originalQNo': qNoInBooklet,
                'sourceBooklet': _selectedBooklet,
                'passageId': passageId,
                'passageBytes': passageBytes,
              };
            }
          });
        }
      } catch (e) {
        debugPrint('crop isolate error: $e');
        if (mounted) setState(() => _localCrops.remove(placeholder));
      }
    } catch (e) {
      debugPrint('Outer saveCrop error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 1000;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: _appBar(isMobile),
      body: isMobile
          ? (_showMobileSidebar 
              ? _sidebar(isMobile: true) 
              : Column(children: [
                  _toolbar(),
                  _poolMetadataBar(),
                  Expanded(child: _canvas()),
                ]))
          : Row(children: [
              _sidebar(isMobile: false),
              Expanded(
                child: Column(children: [
                  _toolbar(),
                  _poolMetadataBar(),
                  Expanded(child: _canvas()),
                ]),
              ),
            ]),
    );
  }

  /// Metadata bar allowing the user to set Default Answer (A-E), Difficulty (Kolay/Orta/Zor),
  /// Class Level, and Outcome/Topic (Kazanım) before/while cropping questions.
  Widget _poolMetadataBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50.withValues(alpha: 0.7),
        border: Border(bottom: BorderSide(color: Colors.indigo.shade100)),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (widget.isPoolMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.indigo.shade200),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _poolClassLevel,
                  isDense: true,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo),
                  items: const [
                    '5. Sınıf',
                    '6. Sınıf',
                    '7. Sınıf',
                    '8. Sınıf',
                    '9. Sınıf',
                    '10. Sınıf',
                    '11. Sınıf',
                    '12. Sınıf',
                    'LGS',
                    'TYT',
                    'AYT',
                  ].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _poolClassLevel = v);
                  },
                ),
              ),
            ),
          // Doğru Cevap seçici
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Doğru Cevap:',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo.shade900)),
              const SizedBox(width: 6),
              for (final ans in ['A', 'B', 'C', 'D', 'E'])
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: InkWell(
                    onTap: () => setState(() => _manualAnswer = ans),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _manualAnswer == ans ? Colors.indigo : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _manualAnswer == ans ? Colors.indigo : Colors.indigo.shade200,
                        ),
                      ),
                      child: Text(
                        ans,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _manualAnswer == ans ? Colors.white : Colors.indigo.shade900,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Zorluk Derecesi seçici
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Zorluk:',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo.shade900)),
              const SizedBox(width: 6),
              for (final diff in [
                ('Kolay', 80.0, Colors.green),
                ('Orta', 55.0, Colors.orange),
                ('Zor', 25.0, Colors.red),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: InkWell(
                    onTap: () => setState(() => _manualDifficulty = diff.$2),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getDifficultyLabel(_manualDifficulty) == diff.$1
                            ? diff.$3
                            : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: diff.$3.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        diff.$1,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _getDifficultyLabel(_manualDifficulty) == diff.$1
                              ? Colors.white
                              : diff.$3.shade700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Kazanım / Konu girişi (Canlı Autocomplete + Seçili Sınıf ve Branşa Göre Liste)
          _buildOutcomeAutocompleteBox(
            controller: _manualOutcomeCtrl,
            focusNode: _manualOutcomeFocus,
            classLevel: _poolClassLevel,
            subject: _selectedSubject,
            maxWidth: 420,
            compact: true,
          ),
        ],
      ),
    );
  }

  // ─── AppBar ──────────────────────────────────────────────────────────────
  AppBar _appBar(bool isMobile) => AppBar(
        toolbarHeight: 64,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.isPoolMode ? 'Soru Havuzu Kırpma Stüdyosu' : 'Hata Kitapçığı Stüdyosu',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17)),
          Text(widget.isPoolMode ? '$_poolClassLevel • ${widget.exam.name}' : widget.exam.name,
              style: GoogleFonts.inter(fontSize: 11, color: Colors.indigo)),
        ]),
        actions: [
          if (isMobile)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _showMobileSidebar = !_showMobileSidebar;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _showMobileSidebar ? Colors.indigo : Colors.indigo.shade50,
                  foregroundColor: _showMobileSidebar ? Colors.white : Colors.indigo,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: Icon(_showMobileSidebar ? Icons.crop_free : Icons.layers_outlined, size: 16),
                label: Text(_showMobileSidebar ? 'Kırpma Ekranı' : 'Soru Havuzu (${_localCrops.length})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
          if (!isMobile) ...[
            ...List.generate(_localSessions.length, (i) {
              final active = i == _sessionIdx;
              return Padding(
                padding: const EdgeInsets.only(right: 8, top: 12, bottom: 12),
                child: ActionChip(
                  label: Text('${i + 1}. Oturum'),
                  onPressed: () => _switchToSession(i),
                  backgroundColor: active ? Colors.indigo : Colors.grey.shade100,
                  labelStyle: TextStyle(
                      color: active ? Colors.white : Colors.indigo, fontSize: 12),
                ),
              );
            }),
            if (widget.exam.bookletCount > 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.indigo.shade100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.menu_book_outlined, size: 12, color: Colors.indigo),
                        const SizedBox(width: 4),
                        DropdownButton<String>(
                          value: _selectedBooklet,
                          isDense: true,
                          underline: const SizedBox.shrink(),
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.indigo, size: 16),
                          style: const TextStyle(fontSize: 12, color: Colors.indigo, fontWeight: FontWeight.bold),
                          items: List.generate(widget.exam.bookletCount, (i) {
                            final char = String.fromCharCode(65 + i);
                            return DropdownMenuItem(value: char, child: Text('$char Kitapçığı'));
                          }),
                          onChanged: (v) {
                            if (v != null) setState(() => _selectedBooklet = v);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
          if (!isMobile || _showMobileSidebar) ...[
            if (_localCrops.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: FilledButton.icon(
                    onPressed: _isPublishing ? null : _publishAll,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      minimumSize: Size.zero,
                    ),
                    icon: _isPublishing
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.cloud_upload_outlined, size: 16),
                    label: Text(
                      _isPublishing
                          ? '($_publishCount/$_publishTotal)'
                          : 'YÜKLE (${_localCrops.where((c) => c['bytes'] != null && c['imageUrl'] == null).length})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ),
              ),
          ],
          if (!isMobile)
            const VerticalDivider(width: 24, indent: 14, endIndent: 14),
          const SizedBox(width: 8),
        ],
      );

  // ─── Toolbar ─────────────────────────────────────────────────────────────
  Widget _toolbar() {
    final isMobile = MediaQuery.of(context).size.width < 1000;

    return Container(
        height: 54,
        color: Colors.white,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            if (isMobile) ...[
              ...List.generate(_localSessions.length, (i) {
                final active = i == _sessionIdx;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: Text('${i + 1}. Oturum', style: const TextStyle(fontSize: 11)),
                    onPressed: () => _switchToSession(i),
                    backgroundColor: active ? Colors.indigo : Colors.grey.shade100,
                    labelStyle: TextStyle(
                        color: active ? Colors.white : Colors.indigo, fontSize: 11),
                  ),
                );
              }),
              if (widget.exam.bookletCount > 1) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.indigo.shade100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.menu_book_outlined, size: 12, color: Colors.indigo),
                        const SizedBox(width: 4),
                        DropdownButton<String>(
                          value: _selectedBooklet,
                          isDense: true,
                          underline: const SizedBox.shrink(),
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.indigo, size: 14),
                          style: const TextStyle(fontSize: 11, color: Colors.indigo, fontWeight: FontWeight.bold),
                          items: List.generate(widget.exam.bookletCount, (i) {
                            final char = String.fromCharCode(65 + i);
                            return DropdownMenuItem(value: char, child: Text('$char Kitapçığı'));
                          }),
                          onChanged: (v) {
                            if (v != null) setState(() => _selectedBooklet = v);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const VerticalDivider(indent: 12, endIndent: 12),
              const SizedBox(width: 8),
            ],

            _modeBtn(Icons.pan_tool_alt_outlined, 'Gezinme', !_isSelectionMode,
                () => setState(() => _isSelectionMode = false)),
            const SizedBox(width: 4),
            _modeBtn(Icons.crop, 'Seçim Yap', _isSelectionMode, () {
              if (_pageImage != null) {
                setState(() { _isSelectionMode = true; _startPt = null; _endPt = null; });
              }
            }),
            const SizedBox(width: 8),
            const VerticalDivider(indent: 12, endIndent: 12, width: 12),
            // ─ Ders & Soru Numarası (her zaman önde ve görünür)
            DropdownButton<String>(
              value: _selectedSubject,
              isDense: true,
              underline: const SizedBox.shrink(),
              items: _subjects
                  .map((s) => DropdownMenuItem(
                      value: s, child: Text(s, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))))
                  .toList(),
              onChanged: (v) => setState(() => _selectedSubject = v),
            ),
            const SizedBox(width: 4),
            IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 17),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () =>
                    setState(() => _questionNo = (_questionNo - 1).clamp(1, 999))),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _showManualQuestionNo,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$_selectedBooklet-$_questionNo. Soru',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo, decoration: TextDecoration.underline)),
                    if (_selectedBooklet != 'A')
                      Text(
                        '➔ A-${_getMasterQuestionNo(_selectedBooklet, _selectedSubject ?? '', _questionNo)}',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 17),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => _questionNo++)),
            if (_activePassageId != null) ...[
              const SizedBox(width: 8),
              InputChip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.push_pin, size: 14, color: Colors.white),
                label: Text(
                  'Ortak Metin (${_localCrops.where((c) => c['passageId'] == _activePassageId).length})',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                backgroundColor: Colors.orange.shade700,
                deleteIconColor: Colors.white,
                onDeleted: _clearActivePassage,
                onPressed: _clearActivePassage,
              ),
            ],
            const SizedBox(width: 8),
            const VerticalDivider(indent: 12, endIndent: 12, width: 12),
            // ─ Auto detect
            FilledButton.tonalIcon(
              onPressed: _isAutoDetecting ? null : () => _autoDetect(allPages: false),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                minimumSize: const Size(0, 34),
              ),
              icon: _isAutoDetecting
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome, size: 15),
              label: const Text('Otomatik Algıla', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 4),
            FilledButton.tonalIcon(
              onPressed: _isAutoDetecting ? null : () => _autoDetect(allPages: true),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                minimumSize: const Size(0, 34),
              ),
              icon: const Icon(Icons.auto_awesome_motion, size: 15),
              label: const Text('Tüm Sayfalar', style: TextStyle(fontSize: 12)),
            ),
            if (_sessionBoxCount > 0) ...[
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: _cutAllAutoBoxes,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  minimumSize: const Size(0, 34),
                ),
                icon: const Icon(Icons.content_cut, size: 14),
                label: Text('Hepsini Kes ($_sessionBoxCount)', style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 2),
              IconButton(
                tooltip: 'Algılanan Kutuları Temizle',
                icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: Colors.redAccent),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: () => setState(() => _autoBoxes.remove(_sessionIdx)),
              ),
            ],
            const SizedBox(width: 6),
            const VerticalDivider(indent: 12, endIndent: 12, width: 12),
            // ─ Compact Zoom Controls
            IconButton(
              tooltip: 'Uzaklaştır (-5%)',
              icon: const Icon(Icons.remove, size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => _applyZoom(_zoom - 0.05),
            ),
            GestureDetector(
              onTap: _showManualZoomDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  '${(_zoom * 100).round()}%',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B)),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Yakınlaştır (+5%)',
              icon: const Icon(Icons.add, size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => _applyZoom(_zoom + 0.05),
            ),
          ]),
        ),
      );
  }

  Widget _modeBtn(IconData icon, String label, bool active, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active ? Colors.indigo : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Icon(icon, size: 14, color: active ? Colors.white : Colors.grey),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    color: active ? Colors.white : Colors.grey.shade700)),
          ]),
        ),
      );

  // ─── Canvas ───────────────────────────────────────────────────────────────
  Widget _canvas() {
    final pageImg = _pageImage;
    final sessionUrl = _localSessions[_sessionIdx].fileUrl;
    final isWaitingForPdf = sessionUrl != null && pageImg == null;

    if (_isLoadingPdf || isWaitingForPdf) {
      return Container(
        color: const Color(0xFFF8FAFC),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EduKnLoader(size: 100),
              const SizedBox(height: 16),
              Text(
                _isLoadingPdf ? 'PDF Hazırlanıyor...' : 'PDF İndiriliyor...',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.indigo.shade900,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (pageImg == null) return _emptyState();

    return LayoutBuilder(builder: (ctx, constraints) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (_vpSize != constraints.biggest) _vpSize = constraints.biggest;
      });

      return Container(
        key: _canvasKey,
        color: const Color(0xFFCBD5E1),
        child: Stack(children: [
          // ── InteractiveViewer with rendered image ──────────────────────────
          Positioned.fill(
            child: InteractiveViewer(
              transformationController: _tx,
              panEnabled: !_isSelectionMode && !_draggingBox,
              scaleEnabled: false,
              // No boundary = drag freely in every direction
              boundaryMargin: const EdgeInsets.all(double.infinity),
              // constrained:false lets the image keep its natural 800px width
              // so InteractiveViewer acts as the viewport for panning
              constrained: false,
              child: Container(
                width: 800,
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: Image.memory(
                  pageImg,
                  width: 800,
                  fit: BoxFit.fitWidth,
                  filterQuality: FilterQuality.high,
                  frameBuilder: (ctx, child, frame, sync) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      child,
                      // ── Selection overlay (below persistent boxes so existing boxes stay interactive)
                      if (_isSelectionMode)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (d) {
                              if (_draggingBox) return;
                              setState(() {
                                _startPt = d.localPosition;
                                _endPt = d.localPosition;
                              });
                            },
                            onPanUpdate: (d) {
                              if (_draggingBox) return;
                              setState(() => _endPt = d.localPosition);
                            },
                            onPanEnd: (_) => _snapManualSelectionOnPanEnd(),
                            child: CustomPaint(
                              painter: _SelectionPainter(_startPt, _endPt),
                            ),
                          ),
                        ),
                      ..._autoBoxOverlays(),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Page nav ────────────────────────────────────────────────────────
          Positioned(
            bottom: 16, right: 16,
            child: Container(
              decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(24)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: Colors.white, size: 20),
                  onPressed: () {
                    final p = _currentPage[_sessionIdx];
                    if (p > 1) setState(() => _currentPage[_sessionIdx] = p - 1);
                  },
                ),
                Text(
                  '${_currentPage[_sessionIdx]} / ${_totalPages[_sessionIdx]}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: Colors.white, size: 20),
                  onPressed: () {
                    final p = _currentPage[_sessionIdx];
                    final total = _totalPages[_sessionIdx];
                    if (p < total) setState(() => _currentPage[_sessionIdx] = p + 1);
                  },
                ),
              ]),
            ),
          ),

          // ── Rendering indicator ─────────────────────────────────────────────
          if (_curPages.length < _totalPages[_sessionIdx])
            Positioned(
              top: 12, right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(width: 12, height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white)),
                  const SizedBox(width: 8),
                  Text('${_curPages.length}/${_totalPages[_sessionIdx]} sayfa hazır',
                      style: const TextStyle(color: Colors.white, fontSize: 11)),
                ]),
              ),
            ),
        ]),
      );
    });
  }

  // ─── Empty state ──────────────────────────────────────────────────────────
  Widget _emptyState() {
    final sessionUrl = _localSessions[_sessionIdx].fileUrl;
    
    // If URL exists but no image, we are still loading (handled in _canvas)
    // but just in case, show loader here too
    if (sessionUrl != null) {
      return Container(
        color: const Color(0xFFF1F5F9),
        child: Center(child: EduKnLoader(size: 80)),
      );
    }

    return Container(
      color: const Color(0xFFCBD5E1),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 24)
              ]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.picture_as_pdf_outlined,
                size: 64, color: Colors.indigo.shade200),
            const SizedBox(height: 16),
            Text('PDF yüklü değil',
                style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            Text('Bu oturum için bir PDF dosyası seçin',
                style:
                    TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _pickPDF,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('PDF YÜKLE'),
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  minimumSize: const Size(180, 48)),
            ),
          ]),
        ),
      ),
    );
  }

  // ─── Sidebar ──────────────────────────────────────────────────────────────
  Widget _sidebar({required bool isMobile}) {
    final criticalCount = _localCrops.where((c) => c['isCritical'] == true).length;
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final s in _subjects) {
      grouped[s] = _localCrops.where((c) => c['subject'] == s).toList()
        ..sort((a, b) => (a['questionNo'] as int).compareTo(b['questionNo']));
    }
    
    final activeSubjects = _subjects.toSet();
    final otherCrops = _localCrops.where((c) => !activeSubjects.contains(c['subject'])).toList()
      ..sort((a, b) {
        final subCompare = (a['subject'] as String? ?? '').compareTo(b['subject'] as String? ?? '');
        if (subCompare != 0) return subCompare;
        return (a['questionNo'] as int? ?? 0).compareTo(b['questionNo'] as int? ?? 0);
      });

    return Container(
      width: isMobile ? double.infinity : 360,
      color: Colors.white,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
          child: Row(children: [
            const Icon(Icons.layers_outlined, color: Colors.indigo, size: 20),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Soru Havuzu',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, size: 13, color: Colors.amber.shade700),
                    const SizedBox(width: 2),
                    Text(
                      '$criticalCount Kritik Soru',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber.shade700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Spacer(),
            if (_localSessions[_sessionIdx].fileUrl == null)
              TextButton.icon(
                  onPressed: _pickPDF,
                  icon: const Icon(Icons.upload_file, size: 16),
                  label: const Text('PDF Yükle', style: TextStyle(fontSize: 12)))
            else if (!isMobile)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                tooltip: 'PDF ve Görsel İşlemleri',
                onSelected: (val) {
                  if (val == 'whiten') _whitenAllExistingCrops();
                  if (val == 'change') _pickPDF();
                  if (val == 'remove') _removePDF();
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'whiten',
                    child: Row(children: [
                      Icon(Icons.auto_fix_high_rounded, size: 18, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text('Tüm Soruların Arka Planını Beyazlat'),
                    ]),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'change',
                    child: Row(children: [
                      Icon(Icons.refresh, size: 18, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('PDF Değiştir'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'remove',
                    child: Row(children: [
                      Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('PDF Kaldır', style: TextStyle(color: Colors.red)),
                    ]),
                  ),
                ],
              ),
          ]),
        ),
        Expanded(
          child: _localCrops.isEmpty
              ? Center(
                  child: Text('Henüz soru eklenmedi',
                      style: TextStyle(
                          color: Colors.grey.shade400, fontSize: 13)))
              : ListView(
                  children: [
                    ..._subjects.map((sub) {
                      final crops = grouped[sub] ?? [];
                      if (crops.isEmpty) return const SizedBox.shrink();
                      return ExpansionTile(
                        initiallyExpanded: true,
                        leading: const Icon(Icons.folder_outlined,
                            color: Colors.indigo, size: 20),
                        title: Text(sub,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold)),
                        trailing: CircleAvatar(
                            radius: 10,
                            backgroundColor: Colors.indigo,
                            child: Text('${crops.length}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 10))),
                        children: crops.map(_cropTile).toList(),
                      );
                    }),
                    if (otherCrops.isNotEmpty) ...[
                      const Divider(),
                      ExpansionTile(
                        initiallyExpanded: false,
                        leading: const Icon(Icons.warning_amber_rounded,
                            color: Colors.orange, size: 20),
                        title: const Text('Diğer / Geçersiz Sorular',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange)),
                        trailing: CircleAvatar(
                            radius: 10,
                            backgroundColor: Colors.orange,
                            child: Text('${otherCrops.length}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 10))),
                        children: otherCrops.map(_cropTile).toList(),
                      ),
                    ],
                  ],
                ),
        ),
      ]),
    );
  }

  Widget _cropTile(Map<String, dynamic> c) {
    final isLoading = c['loading'] == true;
    final hasRemote = c['imageUrl'] != null || c['base64Image'] != null;
    final hasLocal = c['bytes'] != null;
    
    final qNo = c['questionNo'] as int;
    final otherMappings = _getAllBookletMappings(c['subject'], qNo);

    return InkWell(
      onTap: isLoading ? null : () => _showPreview(c),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Image Section
            isLoading
                ? _loadingPlaceholder()
                : ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: hasLocal 
                      ? Image.memory(c['bytes'] as Uint8List, width: 64, height: 64, fit: BoxFit.cover)
                      : (c['base64Image'] != null 
                         ? Image.memory(base64Decode(c['base64Image']), width: 64, height: 64, fit: BoxFit.cover)
                         : (c['imageUrl'] != null ? Image.network(c['imageUrl'], width: 64, height: 64, fit: BoxFit.cover) : const Icon(Icons.image_not_supported))),
                  ),
            const SizedBox(width: 16),
            // Right Content Column
            Expanded(
              child: isLoading
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('A-$qNo. Soru$otherMappings', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 4),
                        const Text('Hazırlanıyor...', style: TextStyle(fontSize: 10, color: Colors.indigo)),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Row 1: A-1. Soru (B-7) + Edit button + Ortak Metin badge
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(4),
                                onTap: () => _showEditCropDialog(c),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        'A-$qNo. Soru$otherMappings',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: hasRemote ? Colors.green.shade700 : Colors.indigo.shade900,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Tooltip(
                                      message: 'Ders veya Soru Numarasını Değiştir',
                                      child: Icon(
                                        Icons.edit_outlined,
                                        size: 14,
                                        color: Colors.indigo.shade400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (c['passageId'] != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.orange.shade300),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.push_pin, size: 10, color: Colors.orange.shade800),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Ortak Metin',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        
                        // Row 2: Difficulty + Star + Passage Pin + Expand + Delete Icons in one Row
                        Row(
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () => _showEditCropDialog(c),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: c['difficulty'] != null
                                      ? _getDifficultyColor((c['difficulty'] as num).toDouble()).withValues(alpha: 0.1)
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: c['difficulty'] != null
                                        ? _getDifficultyColor((c['difficulty'] as num).toDouble()).withValues(alpha: 0.3)
                                        : Colors.grey.shade300,
                                  ),
                                ),
                                child: Text(
                                  c['difficulty'] != null
                                      ? _getDifficultyLabel((c['difficulty'] as num).toDouble())
                                      : 'Zorluk Seç',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: c['difficulty'] != null
                                        ? _getDifficultyColor((c['difficulty'] as num).toDouble())
                                        : Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ),
                            const Spacer(),
                            // Actions Row
                            if (c['passageId'] != null || _activePassageId != null) ...[
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: c['passageId'] != null
                                    ? 'Ortak Metin Bağlantısını Kaldır'
                                    : 'Aktif Ortak Metne Bağla',
                                icon: Icon(
                                  c['passageId'] != null ? Icons.push_pin : Icons.push_pin_outlined,
                                  size: 17,
                                  color: c['passageId'] != null ? Colors.orange.shade700 : Colors.grey,
                                ),
                                onPressed: () async {
                                  final detach = c['passageId'] != null;
                                  setState(() {
                                    if (detach) {
                                      c['passageId'] = null;
                                      c['passageBytes'] = null;
                                      c['passageBase64'] = null;
                                    } else {
                                      c['passageId'] = _activePassageId;
                                      c['passageBytes'] = _activePassageBytes;
                                    }
                                  });
                                  if (c['docId'] != null) {
                                    await FirebaseFirestore.instance
                                        .collection('trial_exams')
                                        .doc(widget.exam.id)
                                        .collection('questions_pool')
                                        .doc(c['docId'] as String)
                                        .update({
                                      'passageId': c['passageId'],
                                      'passageBase64': c['passageBytes'] != null
                                          ? base64Encode(c['passageBytes'] as Uint8List)
                                          : null,
                                    });
                                  }
                                },
                              ),
                              const SizedBox(width: 12),
                            ],
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: c['isCritical'] == true ? 'Kritik Soru' : 'Kritik Olarak İşaretle',
                              icon: Icon(
                                c['isCritical'] == true ? Icons.star_rounded : Icons.star_outline_rounded,
                                size: 18,
                                color: c['isCritical'] == true ? Colors.amber.shade700 : Colors.grey,
                              ),
                              onPressed: () async {
                                final newVal = !(c['isCritical'] == true);
                                setState(() => c['isCritical'] = newVal);
                                if (c['docId'] != null) {
                                  await FirebaseFirestore.instance
                                      .collection('trial_exams')
                                      .doc(widget.exam.id)
                                      .collection('questions_pool')
                                      .doc(c['docId'] as String)
                                      .update({'isCritical': newVal});
                                }
                              },
                            ),
                            const SizedBox(width: 14),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: c['isWide'] ? 'Daralt' : 'Genişlet',
                              icon: Icon(
                                c['isWide'] ? Icons.width_normal_rounded : Icons.width_full_rounded,
                                size: 18,
                                color: c['isWide'] ? Colors.orange : Colors.grey,
                              ),
                              onPressed: () => setState(() => c['isWide'] = !(c['isWide'] as bool)),
                            ),
                            const SizedBox(width: 14),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                              onPressed: () => _deleteCrop(c),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Row 3: Kazanım (outcome) - Clickable to add/edit
                        InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () => _showEditCropDialog(c),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              (c['outcome'] != null && (c['outcome'] as String).trim().isNotEmpty)
                                  ? (c['outcome'] as String)
                                  : '+ Kazanım / Konu eklemek için tıklayın',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                height: 1.3,
                                color: (c['outcome'] != null && (c['outcome'] as String).trim().isNotEmpty)
                                    ? Colors.indigo.shade500
                                    : Colors.indigo.shade300,
                                fontStyle: (c['outcome'] != null && (c['outcome'] as String).trim().isNotEmpty)
                                    ? FontStyle.normal
                                    : FontStyle.italic,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Row 4: Correct answer | wide status | remote publication status
                        InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () => _showEditCropDialog(c),
                          child: Text(
                            'Cevap: ${c['correctAnswer'] ?? '?'} | ${c['isWide'] ? '2 sütun' : '1 sütun'}${hasRemote ? ' (Yayında)' : ''}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.blueGrey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loadingPlaceholder() => Container(
      width: 44, height: 44,
      decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(4)),
      child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.indigo))));

  Future<void> _deleteCrop(Map<String, dynamic> crop) async {
    String? docId = crop['docId'] as String?;
    if (docId == null) {
      final sub = crop['subject'] as String?;
      final qNo = crop['questionNo'] as int?;
      final sIdx = crop['sessionIdx'] as int? ?? _sessionIdx;
      if (sub != null && qNo != null) {
        docId = 's${sIdx + 1}_${sub}_q$qNo'.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      }
    }

    final hasRemote = docId != null || crop['imageUrl'] != null || crop['base64Image'] != null;
    
    if (hasRemote) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Soruyu Sil'),
          content: const Text('Bu soru veri tabanından kalıcı olarak silinecektir. Emin misiniz?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Sil'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      
      // Delete from Firestore record using docId
      if (docId != null) {
        try {
          await FirebaseFirestore.instance
              .collection('trial_exams')
              .doc(widget.exam.id)
              .collection('questions_pool')
              .doc(docId)
              .delete();
          debugPrint('Successfully deleted crop $docId from Firestore');
        } catch (e) {
          debugPrint('Error deleting crop from Firestore: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Veritabanından silinirken hata oluştu: $e')),
            );
          }
        }
      }
    }
    
    setState(() => _localCrops.remove(crop));
  }

  /// Updates a question's subject and/or A-booklet question number (and
  /// optionally shifts all subsequent questions in the same subject by the
  /// same offset), recalculates its answer/difficulty/outcome, and syncs to
  /// Firestore immediately if the question was already published.
  Future<void> _updateCropSubjectAndQuestionNo(
    Map<String, dynamic> crop,
    String newSubject,
    int newMasterQNo, {
    bool shiftSubsequent = false,
  }) async {
    final oldSubject = crop['subject'] as String? ?? newSubject;
    final oldQNo = crop['questionNo'] as int? ?? newMasterQNo;
    if (oldSubject == newSubject && oldQNo == newMasterQNo && !shiftSubsequent) {
      return;
    }

    final delta = newMasterQNo - oldQNo;
    final itemsToUpdate = <MapEntry<Map<String, dynamic>, int>>[];

    if (shiftSubsequent && oldSubject == newSubject && delta != 0) {
      final affected = _localCrops
          .where((c) =>
              c['loading'] != true &&
              c['subject'] == oldSubject &&
              ((c['questionNo'] as int? ?? 0) >= oldQNo))
          .toList();
      // Sort to avoid Firestore docId collisions during sequential updates:
      // if shifting down (delta < 0), update lowest questionNo first;
      // if shifting up (delta > 0), update highest questionNo first.
      affected.sort((a, b) => delta < 0
          ? (a['questionNo'] as int).compareTo(b['questionNo'] as int)
          : (b['questionNo'] as int).compareTo(a['questionNo'] as int));
      for (final item in affected) {
        final targetQ = ((item['questionNo'] as int) + delta).clamp(1, 999);
        itemsToUpdate.add(MapEntry(item, targetQ));
      }
    } else {
      itemsToUpdate.add(MapEntry(crop, newMasterQNo.clamp(1, 999)));
    }

    setState(() {
      for (final entry in itemsToUpdate) {
        final item = entry.key;
        final qNo = entry.value;
        final stat = _questionStats[newSubject]?[qNo];
        final correctAns = stat?['correctAnswer'] ?? _correctAnswer(newSubject, qNo);
        final difficulty = stat?['success'];
        final outcome = stat?['outcome'] ?? _getOutcomeForQuestion(newSubject, qNo);
        item['subject'] = newSubject;
        item['questionNo'] = qNo;
        item['originalQNo'] = qNo;
        item['correctAnswer'] = correctAns;
        item['difficulty'] = difficulty;
        item['outcome'] = outcome;
      }
    });

    // Sync any already-published questions to Firestore
    for (final entry in itemsToUpdate) {
      final item = entry.key;
      final qNo = entry.value;
      final hasRemote = item['docId'] != null ||
          item['base64Image'] != null ||
          item['imageUrl'] != null;
      if (!hasRemote) continue;

      final oldDocId = item['docId'] as String?;
      final sIdx = item['sessionIdx'] as int? ?? _sessionIdx;
      final newDocId = 's${sIdx + 1}_${newSubject}_q$qNo'
          .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final base64Img = (item['base64Image'] as String?) ??
          (item['bytes'] != null ? base64Encode(item['bytes'] as Uint8List) : null);

      try {
        await FirebaseFirestore.instance
            .collection('trial_exams')
            .doc(widget.exam.id)
            .collection('questions_pool')
            .doc(newDocId)
            .set({
          'sessionIdx': sIdx,
          'subject': newSubject,
          'questionNo': qNo,
          if (base64Img != null) 'base64Image': base64Img,
          if (item['imageUrl'] != null) 'imageUrl': item['imageUrl'],
          'isWide': item['isWide'] ?? false,
          'isCritical': item['isCritical'] ?? false,
          'correctAnswer': item['correctAnswer'],
          'difficulty': item['difficulty'],
          'outcome': item['outcome'],
          'passageId': item['passageId'],
          'passageBase64': item['passageBase64'] ??
              (item['passageBytes'] != null
                  ? base64Encode(item['passageBytes'] as Uint8List)
                  : null),
          'createdAt': FieldValue.serverTimestamp(),
        });
        if (oldDocId != null && oldDocId != newDocId) {
          await FirebaseFirestore.instance
              .collection('trial_exams')
              .doc(widget.exam.id)
              .collection('questions_pool')
              .doc(oldDocId)
              .delete();
        }
        if (mounted) {
          setState(() => item['docId'] = newDocId);
        }
      } catch (e) {
        debugPrint('Error updating crop in Firestore: $e');
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.indigo,
          content: Text(
            itemsToUpdate.length > 1
                ? '${itemsToUpdate.length} sorunun numarası otomatik güncellendi.'
                : 'Soru "$newSubject – A-$newMasterQNo. Soru" olarak güncellendi.',
          ),
        ),
      );
    }
  }

  Future<void> _showEditCropDialog(Map<String, dynamic> crop,
      {VoidCallback? onUpdated}) async {
    String selectedSub = (crop['subject'] as String?) ??
        (_subjects.isNotEmpty ? _subjects.first : '');
    if (!_subjects.contains(selectedSub) && _subjects.isNotEmpty) {
      selectedSub = _subjects.first;
    }
    int selectedQNo = (crop['questionNo'] as int?) ?? 1;
    String selectedAnswer = (crop['correctAnswer'] as String?) ?? _manualAnswer;
    if (!['A', 'B', 'C', 'D', 'E'].contains(selectedAnswer)) {
      selectedAnswer = 'A';
    }
    double selectedDiff = (crop['difficulty'] as num?)?.toDouble() ?? _manualDifficulty;
    final outcomeCtrl = TextEditingController(text: (crop['outcome'] as String?) ?? '');
    final outcomeFocus = FocusNode();
    bool shiftSubsequent = false;
    final ctrl = TextEditingController(text: '$selectedQNo');

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final origSub = crop['subject'] as String? ?? '';
          final origQNo = crop['questionNo'] as int? ?? 1;
          final canShift = selectedSub == origSub && selectedQNo != origQNo;
          final delta = selectedQNo - origQNo;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.edit_note_rounded, color: Colors.indigo),
                const SizedBox(width: 8),
                Text('Soruyu Düzenle',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ders',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: selectedSub.isNotEmpty ? selectedSub : null,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      items: _subjects
                          .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(s, style: const TextStyle(fontSize: 13))))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setModal(() => selectedSub = v);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    const Text('Soru Numarası',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        IconButton.outlined(
                          icon: const Icon(Icons.remove, size: 18),
                          onPressed: () {
                            final next = (selectedQNo - 1).clamp(1, 999);
                            setModal(() {
                              selectedQNo = next;
                              ctrl.text = '$next';
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: ctrl,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                            decoration: InputDecoration(
                              isDense: true,
                              suffixText: '. Soru',
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onChanged: (v) {
                              final parsed = int.tryParse(v.trim());
                              if (parsed != null && parsed > 0) {
                                setModal(() => selectedQNo = parsed.clamp(1, 999));
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.outlined(
                          icon: const Icon(Icons.add, size: 18),
                          onPressed: () {
                            final next = (selectedQNo + 1).clamp(1, 999);
                            setModal(() {
                              selectedQNo = next;
                              ctrl.text = '$next';
                            });
                          },
                        ),
                      ],
                    ),
                    if (canShift) ...[
                      const SizedBox(height: 10),
                      CheckboxListTile(
                        value: shiftSubsequent,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          'Bu dersteki sonraki soruları da otomatik kaydır (${delta > 0 ? '+$delta' : '$delta'})',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'Örn. arada soru atladıysanız tümünü silmeden sırayı düzeltir.',
                          style: TextStyle(fontSize: 11),
                        ),
                        onChanged: (v) =>
                            setModal(() => shiftSubsequent = v ?? false),
                      ),
                    ],
                    const SizedBox(height: 14),
                    const Text('Doğru Cevap',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo)),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final ans in ['A', 'B', 'C', 'D', 'E'])
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: InkWell(
                                onTap: () => setModal(() => selectedAnswer = ans),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: selectedAnswer == ans
                                        ? Colors.indigo
                                        : Colors.indigo.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: selectedAnswer == ans
                                          ? Colors.indigo
                                          : Colors.indigo.shade200,
                                    ),
                                  ),
                                  child: Text(
                                    ans,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: selectedAnswer == ans
                                          ? Colors.white
                                          : Colors.indigo.shade900,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text('Zorluk Derecesi',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (final diff in [
                          ('Kolay', 80.0, Colors.green),
                          ('Orta', 55.0, Colors.orange),
                          ('Zor', 25.0, Colors.red),
                        ])
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: InkWell(
                                onTap: () => setModal(() => selectedDiff = diff.$2),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 9),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: _getDifficultyLabel(selectedDiff) == diff.$1
                                        ? diff.$3
                                        : diff.$3.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _getDifficultyLabel(selectedDiff) == diff.$1
                                          ? diff.$3
                                          : diff.$3.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Text(
                                    diff.$1,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _getDifficultyLabel(selectedDiff) == diff.$1
                                          ? Colors.white
                                          : diff.$3.shade800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text('Kazanım / Konu ($_poolClassLevel • $selectedSub)',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo)),
                    const SizedBox(height: 6),
                    _buildOutcomeAutocompleteBox(
                      controller: outcomeCtrl,
                      focusNode: outcomeFocus,
                      classLevel: _poolClassLevel,
                      subject: selectedSub,
                      maxWidth: 400,
                      compact: false,
                      onChanged: () => setModal(() {}),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Vazgeç'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Kaydet'),
                style: FilledButton.styleFrom(backgroundColor: Colors.indigo),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final newOutcome = outcomeCtrl.text.trim();
                  setState(() {
                    crop['correctAnswer'] = selectedAnswer;
                    crop['difficulty'] = selectedDiff;
                    crop['outcome'] = newOutcome.isEmpty ? null : newOutcome;
                    _manualAnswer = selectedAnswer;
                    _manualDifficulty = selectedDiff;
                    if (newOutcome.isNotEmpty) {
                      _manualOutcomeCtrl.text = newOutcome;
                    }
                  });
                  await _updateCropSubjectAndQuestionNo(
                    crop,
                    selectedSub,
                    selectedQNo,
                    shiftSubsequent: shiftSubsequent,
                  );
                  if (crop['docId'] != null) {
                    try {
                      await FirebaseFirestore.instance
                          .collection('trial_exams')
                          .doc(widget.exam.id)
                          .collection('questions_pool')
                          .doc(crop['docId'] as String)
                          .update({
                        'correctAnswer': selectedAnswer,
                        'difficulty': selectedDiff,
                        'outcome': newOutcome.isEmpty ? null : newOutcome,
                      });
                    } catch (e) {
                      debugPrint('Metadata update error: $e');
                    }
                  }
                  onUpdated?.call();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _whitenOneCrop(Map<String, dynamic> crop) async {
    Uint8List? raw = crop['bytes'] as Uint8List?;
    if (raw == null && crop['base64Image'] != null) {
      try {
        raw = base64Decode(crop['base64Image'] as String);
      } catch (_) {}
    }
    if (raw == null) return;

    final whitened = await _whitenExistingImageBytes(raw);
    final b64 = base64Encode(whitened);
    if (!mounted) return;
    setState(() {
      crop['bytes'] = whitened;
      if (crop['base64Image'] != null) {
        crop['base64Image'] = b64;
      }
    });

    if (crop['docId'] != null) {
      try {
        await FirebaseFirestore.instance
            .collection('trial_exams')
            .doc(widget.exam.id)
            .collection('questions_pool')
            .doc(crop['docId'] as String)
            .update({'base64Image': b64});
      } catch (e) {
        debugPrint('whiten update error: $e');
      }
    }
  }

  Future<void> _whitenAllExistingCrops() async {
    if (_localCrops.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.indigo,
        content: Text('✨ Tüm soruların arka planları beyazlatılıyor...'),
      ),
    );
    int count = 0;
    for (final c in List<Map<String, dynamic>>.from(_localCrops)) {
      if (c['loading'] == true) continue;
      await _whitenOneCrop(c);
      count++;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.green.shade700,
        content: Text('✓ $count sorunun arka planı bembeyaz yapıldı ve güncellendi!'),
      ),
    );
  }

  void _showPreview(Map<String, dynamic> initialCrop) {
    // Include both local drafts AND already published/embedded ones
    final viewable = _localCrops
        .where((c) => c['loading'] != true && (c['bytes'] != null || c['base64Image'] != null || c['imageUrl'] != null))
        .toList();
    int idx = viewable.indexOf(initialCrop);
    if (idx == -1) idx = 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final crop = viewable[idx];
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // ─ Header (Interactive Ders & Soru No editor)
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.indigo.shade100),
                          ),
                          child: DropdownButton<String>(
                            value: _subjects.contains(crop['subject'])
                                ? crop['subject'] as String
                                : (_subjects.isNotEmpty ? _subjects.first : null),
                            isDense: true,
                            underline: const SizedBox.shrink(),
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.indigo.shade900,
                            ),
                            items: _subjects
                                .map((s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s),
                                    ))
                                .toList(),
                            onChanged: (newSub) async {
                              if (newSub == null) return;
                              await _updateCropSubjectAndQuestionNo(
                                crop,
                                newSub,
                                crop['questionNo'] as int,
                              );
                              setDlg(() {});
                            },
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.indigo.shade100),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                tooltip: 'Önceki Soru No',
                                icon: const Icon(Icons.remove, size: 15, color: Colors.indigo),
                                onPressed: () async {
                                  final nextQ = ((crop['questionNo'] as int) - 1).clamp(1, 999);
                                  await _updateCropSubjectAndQuestionNo(
                                    crop,
                                    crop['subject'] as String,
                                    nextQ,
                                  );
                                  setDlg(() {});
                                },
                              ),
                              InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () => _showEditCropDialog(
                                  crop,
                                  onUpdated: () => setDlg(() {}),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'A-${crop['questionNo']}. Soru',
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Colors.indigo.shade900,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.edit, size: 13, color: Colors.indigo),
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                tooltip: 'Sonraki Soru No',
                                icon: const Icon(Icons.add, size: 15, color: Colors.indigo),
                                onPressed: () async {
                                  final nextQ = ((crop['questionNo'] as int) + 1).clamp(1, 999);
                                  await _updateCropSubjectAndQuestionNo(
                                    crop,
                                    crop['subject'] as String,
                                    nextQ,
                                  );
                                  setDlg(() {});
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Whiten background button
                  Tooltip(
                    message: 'Arka Planı Beyazlat (Tarama Gölgelerini Temizle)',
                    child: IconButton(
                      icon: const Icon(Icons.auto_fix_high_rounded, color: Colors.teal),
                      onPressed: () async {
                        await _whitenOneCrop(crop);
                        setDlg(() {});
                      },
                    ),
                  ),
                  // Star button for critical toggle
                  Tooltip(
                    message: crop['isCritical'] == true ? 'Kritik Soru' : 'Kritik Olarak İşaretle',
                    child: IconButton(
                      icon: Icon(
                          crop['isCritical'] == true ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: crop['isCritical'] == true ? Colors.amber.shade700 : Colors.grey),
                      onPressed: () async {
                        final newVal = !(crop['isCritical'] == true);
                        setDlg(() => crop['isCritical'] = newVal);
                        setState(() {}); // update sidebar
                        
                        // If already published, sync to cloud immediately
                        if (crop['docId'] != null) {
                          await FirebaseFirestore.instance
                              .collection('trial_exams')
                              .doc(widget.exam.id)
                              .collection('questions_pool')
                              .doc(crop['docId'])
                              .update({'isCritical': newVal});
                        }
                      },
                    ),
                  ),
                  // Wide/Narrow toggle
                  Tooltip(
                    message: crop['isWide'] ? 'Daralt (1 Sütun)' : 'Genişlet (2 Sütun)',
                    child: IconButton(
                      icon: Icon(
                          crop['isWide']
                              ? Icons.width_normal_rounded
                              : Icons.width_full_rounded,
                          color: crop['isWide'] ? Colors.orange : Colors.indigo),
                      onPressed: () async {
                        final newVal = !(crop['isWide'] as bool);
                        setDlg(() => crop['isWide'] = newVal);
                        setState(() {}); // update sidebar
                        
                        // If already published, sync to cloud immediately
                        if (crop['docId'] != null) {
                          await FirebaseFirestore.instance
                              .collection('trial_exams')
                              .doc(widget.exam.id)
                              .collection('questions_pool')
                              .doc(crop['docId'])
                              .update({'isWide': newVal});
                        }
                      },
                    ),
                  ),
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx)),
                ]),
                const SizedBox(height: 12),
                // ─ Image with navigation arrows
                Row(children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, size: 32),
                    color: idx > 0 ? Colors.indigo : Colors.grey.shade300,
                    onPressed: idx > 0 ? () => setDlg(() => idx--) : null,
                  ),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.55),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (crop['passageBytes'] != null || crop['passageBase64'] != null) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.shade50.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.indigo.shade200),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.indigo.shade900,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Row(
                                        children: [
                                          Icon(Icons.menu_book_rounded, size: 14, color: Colors.white),
                                          SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Hata Kitapçığında öğrencinin soru sırasına göre: "... soruları aşağıdaki metne göre cevaplayınız." yazar',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Image.memory(
                                      (crop['passageBytes'] as Uint8List?) ??
                                          base64Decode(crop['passageBase64'] as String),
                                      fit: BoxFit.contain,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            crop['bytes'] != null
                                ? Image.memory(crop['bytes'] as Uint8List, fit: BoxFit.contain)
                                : (crop['base64Image'] != null
                                    ? Image.memory(base64Decode(crop['base64Image']), fit: BoxFit.contain)
                                    : Image.network(crop['imageUrl'] as String, fit: BoxFit.contain)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, size: 32),
                    color: idx < viewable.length - 1
                        ? Colors.indigo
                        : Colors.grey.shade300,
                    onPressed: idx < viewable.length - 1
                        ? () => setDlg(() => idx++)
                        : null,
                  ),
                ]),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    const Text('Doğru Cevap: ',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    for (final ans in ['A', 'B', 'C', 'D', 'E'])
                      InkWell(
                        onTap: () async {
                          setDlg(() => crop['correctAnswer'] = ans);
                          setState(() => _manualAnswer = ans);
                          if (crop['docId'] != null) {
                            await FirebaseFirestore.instance
                                .collection('trial_exams')
                                .doc(widget.exam.id)
                                .collection('questions_pool')
                                .doc(crop['docId'] as String)
                                .update({'correctAnswer': ans});
                          }
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: CircleAvatar(
                          radius: 13,
                          backgroundColor: crop['correctAnswer'] == ans
                              ? Colors.indigo
                              : Colors.indigo.shade50,
                          child: Text(
                            ans,
                            style: TextStyle(
                              fontSize: 12,
                              color: crop['correctAnswer'] == ans
                                  ? Colors.white
                                  : Colors.indigo.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    for (final diff in [
                      ('Kolay', 80.0, Colors.green),
                      ('Orta', 55.0, Colors.orange),
                      ('Zor', 25.0, Colors.red),
                    ])
                      InkWell(
                        onTap: () async {
                          setDlg(() => crop['difficulty'] = diff.$2);
                          setState(() => _manualDifficulty = diff.$2);
                          if (crop['docId'] != null) {
                            await FirebaseFirestore.instance
                                .collection('trial_exams')
                                .doc(widget.exam.id)
                                .collection('questions_pool')
                                .doc(crop['docId'] as String)
                                .update({'difficulty': diff.$2});
                          }
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: crop['difficulty'] != null &&
                                    _getDifficultyLabel((crop['difficulty'] as num).toDouble()) == diff.$1
                                ? diff.$3
                                : diff.$3.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: diff.$3.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            diff.$1,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: crop['difficulty'] != null &&
                                      _getDifficultyLabel((crop['difficulty'] as num).toDouble()) == diff.$1
                                  ? Colors.white
                                  : diff.$3,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Text('${idx + 1} / ${viewable.length}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 10),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _showEditCropDialog(
                    crop,
                    onUpdated: () => setDlg(() {}),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.psychology_outlined, size: 18, color: Colors.indigo),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            (crop['outcome'] != null && (crop['outcome'] as String).trim().isNotEmpty)
                                ? (crop['outcome'] as String)
                                : 'Kazanım / Konu girmek için tıklayın...',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: (crop['outcome'] != null && (crop['outcome'] as String).trim().isNotEmpty)
                                  ? Colors.indigo.shade900
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ),
                        const Icon(Icons.edit_outlined, size: 15, color: Colors.indigo),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickPDF() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.first.bytes;
      
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Dosya verisi okunamadı.')),
          );
        }
        return;
      }

      setState(() => _isLoadingPdf = true);
      
      // IMPORTANT FIX: 
      // PdfDocument.openData transfers the ArrayBuffer to a Web Worker.
      // This detaches the original buffer, causing the subsequent upload to fail!
      // We must pass a COPY of the bytes to the PDF viewer.
      final pdfBytesCopy = Uint8List.fromList(bytes);
      await _openDoc(pdfBytesCopy, sessionIdx: _sessionIdx);
      
      _zoom = 1.0;
      _tx.value = Matrix4.identity();
      
      // Upload background logic using the ORIGINAL bytes
      await _uploadBg(bytes, result.files.first.name);
      
    } catch (e) {
      debugPrint('PickPDF Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dosya seçilirken hata oluştu: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingPdf = false);
    }
  }


  Future<void> _uploadBg(Uint8List bytes, String fileName) async {
    try {
      final path =
          'exam_booklets/${widget.exam.id}/session_${_sessionIdx + 1}.pdf';
      final ref = FirebaseStorage.instance.ref().child(path);
      await ref.putData(bytes, SettableMetadata(contentType: 'application/pdf'));
      final url = await ref.getDownloadURL();
      final updated = List<TrialExamSession>.from(_localSessions);
      updated[_sessionIdx] = updated[_sessionIdx].copyWith(
        fileUrl: url, fileName: fileName);
      await FirebaseFirestore.instance
          .collection('trial_exams')
          .doc(widget.exam.id)
          .set({
        'sessions': updated.map((s) => s.toMap()).toList(),
        'institutionId': widget.exam.institutionId,
        'name': widget.exam.name,
        if (widget.isPoolMode) 'isPoolContainer': true,
        if (widget.isPoolMode) 'isActive': false,
      }, SetOptions(merge: true));
      if (mounted) setState(() => _localSessions = updated);
    } catch (e) {
      debugPrint('upload error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dosya sunucuya yüklenemedi: $e'),
            action: SnackBarAction(
              label: 'CORS Yardımı', 
              onPressed: () => _showCorsHelp(),
            ),
          ),
        );
      }
    }
  }

  void _showCorsHelp() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('CORS Yapılandırması Gerekli'),
        content: const Text(
          'Canlı sistemde dosya yükleyebilmek için Firebase Storage CORS ayarlarının yapılmış olması gerekir. '
          'Lütfen projenizdeki "CORS_FIX_INSTRUCTIONS.md" dosyasındaki adımları takip ederek CORS ayarlarını güncelleyin.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anladım')),
        ],
      ),
    );
  }

  // ─── Publish – Firestore direct (Bypasses Storage Hangs) ────────────────────
  Future<void> _publishAll() async {
    final toUpload = _localCrops
        .where((c) => c['bytes'] != null && c['imageUrl'] == null && c['base64Image'] == null)
        .toList();

    if (toUpload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Yüklenecek yeni soru yok.')));
      return;
    }

    setState(() {
      _isPublishing = true;
      _publishCount = 0;
      _publishTotal = toUpload.length;
    });

    try {
      for (final crop in toUpload) {
        final sub = crop['subject'] as String;
        final qNo = crop['questionNo'] as int;
        final docId = 's${_sessionIdx + 1}_${sub}_q$qNo'.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

        if (!mounted) break;
        
        // Bypass Storage: Store directly in Firestore as Base64 string
        final base64Image = base64Encode(crop['bytes'] as Uint8List);
        
        await FirebaseFirestore.instance
            .collection('trial_exams')
            .doc(widget.exam.id)
            .collection('questions_pool')
            .doc(docId)
            .set({
          'sessionIdx': _sessionIdx,
          'subject': sub,
          'questionNo': qNo,
          'base64Image': base64Image,
          'isWide': crop['isWide'] ?? false,
          'isCritical': crop['isCritical'] ?? false,
          'correctAnswer': crop['correctAnswer'],
          'difficulty': crop['difficulty'],
          'outcome': crop['outcome'],
          'passageId': crop['passageId'],
          'passageBase64': crop['passageBytes'] != null
              ? base64Encode(crop['passageBytes'] as Uint8List)
              : crop['passageBase64'],
          'updatedAt': FieldValue.serverTimestamp(),
          'institutionId': widget.exam.institutionId,
          'examId': widget.exam.id,
          'examName': widget.exam.name,
          'classLevel': _poolClassLevel,
        });
        
        if (mounted) setState(() => _publishCount++);
      }

      await _loadPublishedCrops();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Tüm sorular başarıyla yüklendi ✓'),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      debugPrint('Firestore publish error: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Yükleme Hatası'),
            content: Text('Veritabanına kaydedilirken bir sorun oluştu:\n\n$e'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat'))],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  Future<void> _removePDF() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PDF\'i Kaldır'),
        content: const Text('Bu oturuma ait PDF dosyasını silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Evet, Sil'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      setState(() => _isLoadingPdf = true);
      
      // Update local state
      final updated = List<TrialExamSession>.from(_localSessions);
      updated[_sessionIdx] = updated[_sessionIdx].copyWith(fileUrl: null, fileName: null);
      
      // Update Firestore
      await FirebaseFirestore.instance
          .collection('trial_exams')
          .doc(widget.exam.id)
          .set({
        'sessions': updated.map((s) => s.toMap()).toList(),
        'institutionId': widget.exam.institutionId,
        'name': widget.exam.name,
        if (widget.isPoolMode) 'isPoolContainer': true,
        if (widget.isPoolMode) 'isActive': false,
      }, SetOptions(merge: true));
      
      // Close doc and clear pages
      _docs[_sessionIdx]?.close();
      _docs[_sessionIdx] = null;
      _pages[_sessionIdx] = [];
      _totalPages[_sessionIdx] = 0;
      _currentPage[_sessionIdx] = 1;

      setState(() {
        _localSessions = updated;
        _isLoadingPdf = false;
      });
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF başarıyla kaldırıldı.')));
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingPdf = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }
}

// ─── Selection Painter ────────────────────────────────────────────────────────
class _SelectionPainter extends CustomPainter {
  final Offset? start;
  final Offset? end;
  _SelectionPainter(this.start, this.end);

  @override
  void paint(Canvas canvas, Size size) {
    if (start == null || end == null) return;
    final rect = Rect.fromPoints(start!, end!);
    if (rect.width > 4 && rect.height > 4) {
      final fullPath = Path()..addRect(Offset.zero & size);
      final selPath = Path()..addRect(rect);
      final outsidePath = Path.combine(PathOperation.difference, fullPath, selPath);
      canvas.drawPath(
        outsidePath,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.22)
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawRect(
        rect, Paint()..color = Colors.indigo.withValues(alpha: 0.08)..style = PaintingStyle.fill);
    canvas.drawRect(
        rect, Paint()..color = Colors.indigo..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _SelectionPainter old) =>
      old.start != start || old.end != end;
}

