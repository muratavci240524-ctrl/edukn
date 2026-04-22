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

  bool _isPublishing = false;
  int _publishCount = 0;
  int _publishTotal = 0;

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

    if (_localSessions.isNotEmpty) {
      _subjects = _localSessions[0].selectedSubjects;
      if (_subjects.isNotEmpty) _selectedSubject = _subjects.first;
    }
    _loadPublishedCrops();
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
      for(var doc in snap.docs) {
        final data = doc.data();
        loaded.add({
          'bytes': null,
          'imageUrl': data['imageUrl'],
          'base64Image': data['base64Image'], // New Base64 field
          'subject': data['subject'],
          'questionNo': data['questionNo'],
          'isWide': data['isWide'] ?? false,
          'correctAnswer': data['correctAnswer'],
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
      _subjects = _localSessions[idx].selectedSubjects;
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
  String? _correctAnswer(String subject, int qNo) {
    final answers = widget.exam.answerKeys['A']?[subject];
    if (answers == null || qNo > answers.length) return null;
    return answers[qNo - 1];
  }

  // ─── Crop – main thread: coords only | isolate: pixel work ─────────────────
  Future<void> _saveCrop() async {
    final imgBytes = _pageImage;
    if (imgBytes == null || _startPt == null || _endPt == null ||
        _selectedSubject == null) return;

    // ── Capture all state NOW (before any await) ──
    final subject    = _selectedSubject!;
    final qNo        = _questionNo;
    final correctAns = _correctAnswer(subject, qNo);
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
    // Approximate aspect from first page bytes (decode header only is not
    // available in the image package, so we pass raw pixels to the isolate
    // and let it handle the coordinate math there with the real dimensions).
    final left   = (ls.dx < le.dx ? ls.dx : le.dx);
    final top    = (ls.dy < le.dy ? ls.dy : le.dy);
    final right  = (ls.dx > le.dx ? ls.dx : le.dx);
    final bottom = (ls.dy > le.dy ? ls.dy : le.dy);

    // ── Auto-advance: if questionNo exceeds this subject's answer count,
    //    move to the next subject in the list and restart at question 1.
    void _autoAdvanceSubject() {
      if (_selectedSubject == null) return;
      final answers = widget.exam.answerKeys['A']?[_selectedSubject!];
      if (answers == null) return;
      if (_questionNo > answers.length) {
        final idx = _subjects.indexOf(_selectedSubject!);
        if (idx >= 0 && idx < _subjects.length - 1) {
          _selectedSubject = _subjects[idx + 1];
          _questionNo = 1;
        }
      }
    }

    // ── Immediately register a loading placeholder ↔ sidebar stays live ──
    final placeholder = <String, dynamic>{
      'bytes': null, 'subject': subject, 'questionNo': qNo,
      'isWide': false, 'correctAnswer': correctAns, 'loading': true,
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
              'bytes': cropBytes, 'subject': subject, 'questionNo': qNo,
              'isWide': false, 'correctAnswer': correctAns, 'loading': false,
            };
          }
        });
      }
    } catch (e) {
      debugPrint('crop isolate error: $e');
      if (mounted) setState(() => _localCrops.remove(placeholder));
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
          // ─ Slider (wider)
          SizedBox(
            width: 200,
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
            const SizedBox(width: 16),
            const VerticalDivider(indent: 8, endIndent: 8),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _selectedSubject,
              isDense: true,
              underline: const SizedBox.shrink(),
              items: _subjects
                  .map((s) => DropdownMenuItem(
                      value: s, child: Text(s, style: const TextStyle(fontSize: 13))))
                  .toList(),
              onChanged: (v) => setState(() => _selectedSubject = v),
            ),
            const SizedBox(width: 8),
            IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 18),
                onPressed: () =>
                    setState(() => _questionNo = (_questionNo - 1).clamp(1, 999))),
            GestureDetector(
              onTap: _showManualQuestionNo,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Text('Soru $_questionNo',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo, decoration: TextDecoration.underline)),
              ),
            ),
            IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 18),
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
              style: FilledButton.styleFrom(backgroundColor: Colors.indigo),
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

    if (_isLoadingPdf) {
      return Container(
        color: const Color(0xFFCBD5E1),
        child: const Center(child: CircularProgressIndicator()),
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
  Widget _emptyState() => Container(
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

  // ─── Sidebar ──────────────────────────────────────────────────────────────
  Widget _sidebar() {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final s in _subjects) {
      grouped[s] = _localCrops.where((c) => c['subject'] == s).toList()
        ..sort((a, b) => (a['questionNo'] as int).compareTo(b['questionNo']));
    }
    return Container(
      width: 300,
      color: Colors.white,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
          child: Row(children: [
            const Icon(Icons.layers_outlined, color: Colors.indigo, size: 20),
            const SizedBox(width: 10),
            Text('Soru Havuzu',
                style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            const Spacer(),
            if (_pageImage == null)
              TextButton.icon(
                  onPressed: _pickPDF,
                  icon: const Icon(Icons.upload_file, size: 16),
                  label: const Text('PDF Yükle', style: TextStyle(fontSize: 12))),
          ]),
        ),
        Expanded(
          child: _localCrops.isEmpty
              ? Center(
                  child: Text('Henüz soru eklenmedi',
                      style: TextStyle(
                          color: Colors.grey.shade400, fontSize: 13)))
              : ListView.builder(
                  itemCount: _subjects.length,
                  itemBuilder: (ctx, i) {
                    final sub = _subjects[i];
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
        ),
      ]),
    );
  }

  Widget _cropTile(Map<String, dynamic> c) {
    final isLoading = c['loading'] == true;
    final hasRemote = c['imageUrl'] != null || c['base64Image'] != null;
    final hasLocal = c['bytes'] != null;
    
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
      title: Text('${c['questionNo']}. Soru',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isLoading ? Colors.grey : (hasRemote ? Colors.green.shade700 : null))),
      subtitle: isLoading
          ? const Text('Hazırlanıyor...', style: TextStyle(fontSize: 10, color: Colors.indigo))
          : Text(
              '${c['correctAnswer'] ?? '?'} | ${c['isWide'] ? '2 sütun' : '1 sütun'}${hasRemote ? ' (Yayında)' : ''}',
              style: const TextStyle(fontSize: 10)),
      trailing: isLoading
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: [
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
    if (crop['imageUrl'] != null) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Soruyu Sil'),
          content: const Text('Bu soru yayınlanmış. Kalıcı olarak silmek istiyor musunuz?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sil')),
          ],
        ),
      );
      if (confirm != true) return;
      
      // Delete from Firestore record using docId
      if (crop['docId'] != null) {
        await FirebaseFirestore.instance
            .collection('trial_exams')
            .doc(widget.exam.id)
            .collection('questions_pool')
            .doc(crop['docId'])
            .delete();
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
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.indigo,
                      child: Text(crop['correctAnswer'] ?? '?',
                           style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 16),
                  Text('${idx + 1} / ${viewable.length}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey)),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickPDF() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;

    setState(() => _isLoadingPdf = true);
    try {
      await _openDoc(bytes, sessionIdx: _sessionIdx);
      _zoom = 1.0;
      _tx.value = Matrix4.identity();
    } finally {
      setState(() => _isLoadingPdf = false);
    }
    _uploadBg(bytes, result.files.first.name);
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
      debugPrint('upload: $e');
    }
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
          'correctAnswer': crop['correctAnswer'],
          'updatedAt': FieldValue.serverTimestamp(),
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
