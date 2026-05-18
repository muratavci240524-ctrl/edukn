import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pdfx/pdfx.dart';
import 'package:image/image.dart' as img;
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../../../../models/assessment/trial_exam_model.dart';
import '../../../../widgets/edukn_logo.dart';

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

  final nw = imgEl.naturalWidth!;
  final nh = imgEl.naturalHeight!;

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
  canvas.context2D
      .drawImageScaledFromSource(imgEl, px, py, pw, ph, 0, 0, pw, ph);

  // 5. Export as JPEG (50% quality for ultra-small size, perfect for text questions)
  final dataUrl = canvas.toDataUrl('image/jpeg', 0.50);
  final base64Str = dataUrl.split(',').last;
  return base64Decode(base64Str);
}
// ───────────────────────────────────────────────────────────────────────────

class ErrorBookletEditorScreen extends StatefulWidget {
  final TrialExam exam;
  const ErrorBookletEditorScreen({super.key, required this.exam});

  @override
  State<ErrorBookletEditorScreen> createState() =>
      _ErrorBookletEditorScreenState();
}

class _ErrorBookletEditorScreenState extends State<ErrorBookletEditorScreen> {
  // ─── Session & PDF data ───────────────────────────────────────────────────
  late List<TrialExamSession> _localSessions;
  int _sessionIdx = 0;

  // Rendered page images per session
  // _pages[sessionIdx] = list of rendered Uint8List per page
  late List<List<Uint8List>> _pages;
  late List<PdfDocument?> _docs;
  late List<int> _totalPages;
  late List<int> _currentPage;

  bool _isLoadingPdf = false;
  bool _isRenderingPage = false;

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
  Map<String, Map<int, Map<String, dynamic>>> _questionStats = {};

  bool _isPublishing = false;
  int _publishCount = 0;
  int _publishTotal = 0;

  String _selectedBooklet = 'A'; // Which booklet does this PDF represent?

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
    if (_subjects.isNotEmpty) {
      _sortSubjects();
      _selectedSubject = _subjects.first;
    }
    
    _loadPublishedCrops();
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
        if (latestCorrectAnswer != null && correctAnswer != latestCorrectAnswer) {
          correctAnswer = latestCorrectAnswer;
          updateMap['correctAnswer'] = correctAnswer;
          needsUpdate = true;
        }

        // As a fallback for older questions/outcomes if latest outcome is still null but we need to check K12 text mappings
        if (outcome == null && latestOutcome != null) {
          outcome = latestOutcome;
          updateMap['outcome'] = outcome;
          needsUpdate = true;
        }
        // Fallback for correctAnswer
        if (correctAnswer == null && latestCorrectAnswer != null) {
          correctAnswer = latestCorrectAnswer;
          updateMap['correctAnswer'] = correctAnswer;
          needsUpdate = true;
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

  String _getDifficultyLabel(double success) {
    if (success <= 20) return 'Çok Zor';
    if (success <= 40) return 'Zor';
    if (success <= 60) return 'Orta';
    if (success <= 80) return 'Kolay';
    return 'Çok Kolay';
  }

  Color _getDifficultyColor(double success) {
    if (success <= 20) return Colors.red.shade700;
    if (success <= 40) return Colors.orange.shade700;
    if (success <= 60) return Colors.amber.shade700;
    if (success <= 80) return Colors.lightGreen.shade700;
    return Colors.green.shade700;
  }

  // ─── Crop – main thread: coords only | isolate: pixel work ─────────────────
  Future<void> _saveCrop() async {
    final imgBytes = _pageImage;
    if (imgBytes == null || _startPt == null || _endPt == null ||
        _selectedSubject == null) return;

    // ── Capture all state NOW (before any await) ──
    try {
      final subject    = _selectedSubject!;
      final qNoInBooklet = _questionNo;
      final masterQNo  = _getMasterQuestionNo(_selectedBooklet, subject, qNoInBooklet);
      
      final stat       = _questionStats[subject]?[masterQNo];
      final correctAns = stat?['correctAnswer'] ?? _correctAnswer(subject, qNoInBooklet);
      final difficulty = stat?['success'];
      final outcome    = stat?['outcome'] ?? _getOutcomeForQuestion(subject, masterQNo);

      final txSnapshot = Matrix4.copy(_tx.value);
      final startPt    = _startPt!;
      final endPt      = _endPt!;

      // ── Compute pixel coordinates on main thread (fast, no allocation) ──
      final inverse  = Matrix4.inverted(txSnapshot);
      final ls = MatrixUtils.transformPoint(inverse, startPt);
      final le = MatrixUtils.transformPoint(inverse, endPt);

      // We need image dimensions to map coords; grab them synchronously from a
      // 1-pixel decode is too slow – use the known display size instead.
      const displayW = 800.0;
      final left   = (ls.dx < le.dx ? ls.dx : le.dx);
      final top    = (ls.dy < le.dy ? ls.dy : le.dy);
      final right  = (ls.dx > le.dx ? ls.dx : le.dx);
      final bottom = (ls.dy > le.dy ? ls.dy : le.dy);

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
      };
      setState(() {
        _localCrops.add(placeholder);
        _questionNo++;
        _startPt = null;
        _endPt   = null;
        _isSelectionMode = false;   // back to navigate immediately
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
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: _appBar(),
      body: Row(children: [
        _sidebar(),
        Expanded(child: Column(children: [_toolbar(), Expanded(child: _canvas())])),
      ]),
    );
  }

  // ─── AppBar ──────────────────────────────────────────────────────────────
  AppBar _appBar() => AppBar(
        toolbarHeight: 64,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Hata Kitapçığı Stüdyosu',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17)),
          Text(widget.exam.name,
              style: GoogleFonts.inter(fontSize: 11, color: Colors.indigo)),
        ]),
        actions: [
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
          const VerticalDivider(width: 24, indent: 14, endIndent: 14),
          if (_localCrops.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: FilledButton.icon(
                  onPressed: _isPublishing ? null : _publishAll,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _isPublishing
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.cloud_upload_outlined, size: 20),
                  label: Text(
                    _isPublishing
                        ? 'YÜKLENİYOR ($_publishCount/$_publishTotal)'
                        : 'YÜKLE (${_localCrops.where((c) => c['bytes'] != null && c['imageUrl'] == null).length})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          if (widget.exam.bookletCount > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.indigo.shade100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.menu_book_outlined, size: 14, color: Colors.indigo),
                      const SizedBox(width: 6),
                      const Text('PDF TÜRÜ:',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo)),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: _selectedBooklet,
                        isDense: true,
                        underline: const SizedBox.shrink(),
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.indigo, size: 18),
                        style: const TextStyle(fontSize: 13, color: Colors.indigo, fontWeight: FontWeight.bold),
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
          const SizedBox(width: 8),
        ],
      );

  // ─── Toolbar ─────────────────────────────────────────────────────────────
  Widget _toolbar() => Container(
        height: 54,
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          _modeBtn(Icons.pan_tool_alt_outlined, 'Gezinme', !_isSelectionMode,
              () => setState(() => _isSelectionMode = false)),
          const SizedBox(width: 4),
          _modeBtn(Icons.crop, 'Seçim Yap', _isSelectionMode, () {
            if (_pageImage != null) {
              setState(() { _isSelectionMode = true; _startPt = null; _endPt = null; });
            }
          }),
          const SizedBox(width: 16),
          // ─ -5% button
          IconButton(
            tooltip: '-5%',
            icon: const Icon(Icons.zoom_out, size: 18),
            onPressed: () => _applyZoom(_zoom - 0.05),
          ),
          // ─ Slider (more compact)
          SizedBox(
            width: 120,
            child: Slider(
              value: _zoom.clamp(0.3, 8.0),
              min: 0.3, max: 8.0, divisions: 77,
              label: '${(_zoom * 100).round()}%',
              onChanged: _applyZoom,
            ),
          ),
          // ─ +5% button
          IconButton(
            tooltip: '+5%',
            icon: const Icon(Icons.zoom_in, size: 18),
            onPressed: () => _applyZoom(_zoom + 0.05),
          ),
          // ─ Clickable % label → manual entry
          GestureDetector(
            onTap: _showManualZoomDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                '${(_zoom * 100).round()}%',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B)),
              ),
            ),
          ),
          if (_isSelectionMode) ...[
            const SizedBox(width: 12),
            const VerticalDivider(indent: 10, endIndent: 10),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _selectedSubject,
              isDense: true,
              underline: const SizedBox.shrink(),
              items: _subjects
                  .map((s) => DropdownMenuItem(
                      value: s, child: Text(s, style: const TextStyle(fontSize: 12))))
                  .toList(),
              onChanged: (v) => setState(() => _selectedSubject = v),
            ),
            const SizedBox(width: 4),
            IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () =>
                    setState(() => _questionNo = (_questionNo - 1).clamp(1, 999))),
            const SizedBox(width: 8),
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
            const SizedBox(width: 8),
            IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => _questionNo++)),
          ],
          const Spacer(),
          if (_isSelectionMode && _startPt != null)
            FilledButton.icon(
              onPressed: _isRenderingPage ? null : _saveCrop,
              icon: _isRenderingPage
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.content_cut, size: 16),
              label: const Text('KES & HAVUZA AT'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.indigo,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
        ]),
      );

  Widget _modeBtn(IconData icon, String label, bool active, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active ? Colors.indigo : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Icon(icon, size: 15, color: active ? Colors.white : Colors.grey),
            const SizedBox(width: 6),
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
              panEnabled: !_isSelectionMode,
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
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: Image.memory(
                  pageImg,
                  width: 800,
                  fit: BoxFit.fitWidth,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),

          // ── Selection overlay ───────────────────────────────────────────────
          if (_isSelectionMode)
            Positioned.fill(
              child: GestureDetector(
                onPanStart: (d) =>
                    setState(() { _startPt = d.localPosition; _endPt = d.localPosition; }),
                onPanUpdate: (d) => setState(() => _endPt = d.localPosition),
                child: CustomPaint(
                    painter: _SelectionPainter(_startPt, _endPt)),
              ),
            ),

          // ── Page nav ────────────────────────────────────────────────────────
          Positioned(
            bottom: 16, right: 16,
            child: Container(
              decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
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
                BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 24)
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
  Widget _sidebar() {
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
      width: 360,
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
            else
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                tooltip: 'PDF İşlemleri',
                onSelected: (val) {
                  if (val == 'change') _pickPDF();
                  if (val == 'remove') _removePDF();
                },
                itemBuilder: (ctx) => [
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

    return ListTile(
      dense: true,
      onTap: isLoading ? null : () => _showPreview(c),
      leading: isLoading
          ? _loadingPlaceholder()
          : ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: hasLocal 
                ? Image.memory(c['bytes'] as Uint8List, width: 44, height: 44, fit: BoxFit.cover)
                : (c['base64Image'] != null 
                   ? Image.memory(base64Decode(c['base64Image']), width: 44, height: 44, fit: BoxFit.cover)
                   : (c['imageUrl'] != null ? Image.network(c['imageUrl'], width: 44, height: 44, fit: BoxFit.cover) : const Icon(Icons.image_not_supported))),
            ),
      title: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text('A-$qNo. Soru$otherMappings',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isLoading ? Colors.grey : (hasRemote ? Colors.green.shade700 : null))),
          if (c['difficulty'] != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getDifficultyColor((c['difficulty'] as num).toDouble()).withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _getDifficultyColor((c['difficulty'] as num).toDouble()).withOpacity(0.3)),
              ),
              child: Text(
                _getDifficultyLabel((c['difficulty'] as num).toDouble()),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: _getDifficultyColor((c['difficulty'] as num).toDouble()),
                ),
              ),
            ),
        ],
      ),
      subtitle: isLoading
          ? const Text('Hazırlanıyor...', style: TextStyle(fontSize: 10, color: Colors.indigo))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c['outcome'] != null)
                  Text(
                    c['outcome'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: Colors.indigo.shade400, fontWeight: FontWeight.w500),
                  ),
                const SizedBox(height: 2),
                Text(
                  '${c['correctAnswer'] ?? '?'} | ${c['isWide'] ? '2 sütun' : '1 sütun'}${hasRemote ? ' (Yayında)' : ''}',
                  style: const TextStyle(fontSize: 10)),
              ],
            ),
      trailing: isLoading
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: c['isCritical'] == true ? 'Kritik Soru' : 'Kritik Olarak İşaretle',
                icon: Icon(
                    c['isCritical'] == true ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 18,
                    color: c['isCritical'] == true ? Colors.amber.shade700 : Colors.grey),
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
              IconButton(
                tooltip: c['isWide'] ? 'Daralt' : 'Genişlet',
                icon: Icon(
                    c['isWide'] ? Icons.width_normal_rounded : Icons.width_full_rounded,
                    size: 18,
                    color: c['isWide'] ? Colors.orange : Colors.grey),
                onPressed: () => setState(() => c['isWide'] = !(c['isWide'] as bool)),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                onPressed: () => _deleteCrop(c),
              ),
            ]),
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
                // ─ Header
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Expanded(
                    child: Text('${crop['subject']} – ${crop['questionNo']}. Soru',
                        style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold, fontSize: 16)),
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
                      child: crop['bytes'] != null 
                        ? Image.memory(crop['bytes'] as Uint8List, fit: BoxFit.contain)
                        : (crop['base64Image'] != null 
                           ? Image.memory(base64Decode(crop['base64Image']), fit: BoxFit.contain)
                           : Image.network(crop['imageUrl'] as String, fit: BoxFit.contain)),
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
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('Doğru Cevap: ',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.indigo,
                      child: Text(crop['correctAnswer'] ?? '?',
                           style: const TextStyle(
                               color: Colors.white, fontWeight: FontWeight.bold))),
                  if (crop['difficulty'] != null) ...[
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getDifficultyColor((crop['difficulty'] as num).toDouble()).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _getDifficultyColor((crop['difficulty'] as num).toDouble()).withOpacity(0.3)),
                      ),
                      child: Text(
                        'Zorluk: ${_getDifficultyLabel((crop['difficulty'] as num).toDouble())}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _getDifficultyColor((crop['difficulty'] as num).toDouble()),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 16),
                  Text('${idx + 1} / ${viewable.length}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey)),
                ]),
                if (crop['outcome'] != null) ...[
                  const SizedBox(height: 12),
                  Container(
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
                            crop['outcome'] as String,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.indigo.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickPDF() async {
    try {
      final result = await FilePicker.platform.pickFiles(
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
          .update({'sessions': updated.map((s) => s.toMap()).toList()});
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
          'updatedAt': FieldValue.serverTimestamp(),
          'institutionId': widget.exam.institutionId,
          'examId': widget.exam.id,
          'examName': widget.exam.name,
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
          .update({'sessions': updated.map((s) => s.toMap()).toList()});
      
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
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF başarıyla kaldırıldı.')));
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
    canvas.drawRect(
        rect, Paint()..color = Colors.indigo.withOpacity(0.18)..style = PaintingStyle.fill);
    canvas.drawRect(
        rect, Paint()..color = Colors.indigo..style = PaintingStyle.stroke..strokeWidth = 2);
    const r = 5.0;
    final p = Paint()..color = Colors.indigo;
    for (final c in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]) {
      canvas.drawCircle(c, r, p);
    }
  }

  @override
  bool shouldRepaint(covariant _SelectionPainter old) =>
      old.start != start || old.end != end;
}
