import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../services/lesson_notes_service.dart';
import '../../../../utils/fullscreen_helper.dart';
import '../../../../widgets/lesson_note_dialogs.dart';
import 'whiteboard_art.dart';
import 'whiteboard_io.dart';
import 'whiteboard_models.dart';
import 'whiteboard_painters.dart';
import 'whiteboard_student_picker.dart';
import 'whiteboard_widgets.dart';

/// Akıllı Beyaz Tahta — tam ekran, yalnızca sol üstte geri tuşu bulunan tahta.
/// Sağ panel ve alt araç çubuğu gizlenebilir.
class SmartWhiteboardScreen extends StatefulWidget {
  const SmartWhiteboardScreen({
    super.key,
    this.institutionId = '',
    this.schoolTypeId = '',
    this.allowedClassIds,
  });

  /// Not kaydetme / derse ekleme için kurum bilgisi (boşsa bu özellikler kapalıdır).
  final String institutionId;
  final String schoolTypeId;
  final List<String>? allowedClassIds;

  @override
  State<SmartWhiteboardScreen> createState() => _SmartWhiteboardScreenState();
}

enum _Op { none, draw, erase, shape, move, resize, pan, laser }

class _LaserSample {
  _LaserSample(this.p, this.t);
  final Offset p;
  final DateTime t;
}

class _Thumb {
  _Thumb(this.sig, this.img);
  final int sig;
  final ui.Image img;
}

class _Rendered {
  _Rendered(this.png, this.w, this.h);
  final Uint8List png;
  final int w;
  final int h;
}

class _FloatItem {
  _FloatItem(this.id, this.kind);
  final int id;
  final String kind;
}

class _InstItem {
  _InstItem(this.id, this.kind, this.pos, this.angle);
  final int id;
  final WbInstrumentKind kind;
  Offset pos;
  double angle;
}

class _SmartWhiteboardScreenState extends State<SmartWhiteboardScreen>
    with SingleTickerProviderStateMixin {
  static const List<Color> _palette = [
    Color(0xFF111827),
    Color(0xFFFFFFFF),
    Color(0xFFEF4444),
    Color(0xFFF97316),
    Color(0xFFEAB308),
    Color(0xFF22C55E),
    Color(0xFF14B8A6),
    Color(0xFF3B82F6),
    Color(0xFF6366F1),
    Color(0xFFA855F7),
    Color(0xFFEC4899),
    Color(0xFF8B5E3C),
  ];

  static const Map<WbShapeKind, String> _shapeNames = {
    WbShapeKind.line: 'Doğru',
    WbShapeKind.arrow: 'Ok',
    WbShapeKind.doubleArrow: 'Çift Ok',
    WbShapeKind.rect: 'Dikdörtgen',
    WbShapeKind.roundRect: 'Yuvarlak Köşe',
    WbShapeKind.ellipse: 'Elips / Daire',
    WbShapeKind.triangle: 'Üçgen',
    WbShapeKind.rightTriangle: 'Dik Üçgen',
    WbShapeKind.diamond: 'Eşkenar Dörtgen',
    WbShapeKind.pentagon: 'Beşgen',
    WbShapeKind.hexagon: 'Altıgen',
    WbShapeKind.star: 'Yıldız',
    WbShapeKind.trapezoid: 'Yamuk',
    WbShapeKind.parallelogram: 'Paralelkenar',
    WbShapeKind.cross: 'Artı',
    WbShapeKind.heart: 'Kalp',
  };

  static const Map<WbBackground, String> _bgNames = {
    WbBackground.white: 'Beyaz',
    WbBackground.black: 'Siyah Tahta',
    WbBackground.green: 'Yeşil Tahta',
    WbBackground.grid: 'Kareli',
    WbBackground.lined: 'Çizgili',
    WbBackground.dotted: 'Noktalı',
    WbBackground.graph: 'Milimetrik',
    WbBackground.axes: 'Koordinat Düzlemi',
  };

  bool _big = false;
  bool _bigDecided = false;
  LessonNote? _lastSaved;

  final List<WbPage> _pages = [WbPage()];
  int _pi = 0;
  WbPage get _page => _pages[_pi];

  WbTool _tool = WbTool.pen;
  WbShapeKind _shape = WbShapeKind.rect;
  Color _color = const Color(0xFF111827);
  double _width = 4;
  double _eraser = 34;
  double _textSize = 34;
  bool _fill = false;
  bool _dashed = false;
  bool _lockRatio = false;

  int _nextId = 1;
  int _version = 0;
  WbObject? _preview;
  WbObject? _selected;

  bool _dockOpen = true;
  bool _panelOpen = true;
  bool _isFullscreen = false;
  bool _enteredWebFullscreen = false;
  int _tab = 0;
  bool _pagesOpen = true;
  final Map<WbPage, _Thumb> _thumbs = {};
  final Set<WbPage> _thumbBusy = {};
  Timer? _thumbTimer;
  String _artCat = 'mat';
  String _artQuery = '';
  final TextEditingController _artSearchCtrl = TextEditingController();
  final Map<String, int> _artUse = {};
  final ValueNotifier<int> _liveTick = ValueNotifier<int>(0);

  final Map<int, Offset> _ptrs = {};
  _Op _op = _Op.none;
  Offset? _eraserPos;
  final List<_LaserSample> _laser = [];
  Offset _lastCanvas = Offset.zero;
  Offset _downScreen = Offset.zero;
  Offset _lastScreen = Offset.zero;
  bool _tapMoved = false;
  Offset? _textTap;
  bool _prepared = false;
  bool _erasePushed = false;
  WbObject? _origForResize;
  Offset _anchor = Offset.zero;
  Offset _startVec = Offset.zero;
  double _pinchPrevDist = 1;
  Offset _pinchPrevCenter = Offset.zero;

  final GlobalKey _stackKey = GlobalKey();
  Size _viewSize = const Size(1200, 700);
  Ticker? _ticker;

  final List<_FloatItem> _floats = [];
  final List<_InstItem> _insts = [];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _ticker = createTicker(_onTick);
    _loadArtUse();
  }

  @override
  void dispose() {
    _thumbTimer?.cancel();
    for (final t in _thumbs.values) {
      t.img.dispose();
    }
    _ticker?.dispose();
    _artSearchCtrl.dispose();
    _liveTick.dispose();
    if (kIsWeb && _enteredWebFullscreen && isBrowserFullscreen()) {
      toggleBrowserFullscreen(false);
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  bool get _fsActive => kIsWeb ? isBrowserFullscreen() : _isFullscreen;

  void _toggleFullscreen() {
    final next = !_fsActive;
    toggleBrowserFullscreen(next);
    if (kIsWeb && next) _enteredWebFullscreen = true;
    if (!kIsWeb) {
      try {
        SystemChrome.setEnabledSystemUIMode(
          next ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
        );
      } catch (_) {}
    }
    setState(() => _isFullscreen = next);
    if (kIsWeb) {
      Future.delayed(const Duration(milliseconds: 180), () {
        if (mounted) setState(() => _isFullscreen = isBrowserFullscreen());
      });
    }
  }

  void _onTick(Duration _) {
    if (_laser.isEmpty) {
      _ticker?.stop();
      return;
    }
    final now = DateTime.now();
    _laser.removeWhere((s) => now.difference(s.t).inMilliseconds > 1400);
    if (_laser.isEmpty) {
      _ticker?.stop();
    }
    if (mounted) _liveTick.value++;
  }

  // ───────────────────────────── yardımcılar ─────────────────────────────
  Offset _toCanvas(Offset s) => (s - _page.offset) / _page.scale;

  Offset get _viewCenterCanvas =>
      _toCanvas(Offset(_viewSize.width / 2, _viewSize.height / 2));

  void _pushUndo() {
    _page.undo.add(List<WbObject>.of(_page.objects));
    if (_page.undo.length > 80) _page.undo.removeAt(0);
    _page.redo.clear();
  }

  void _commitChange() {
    _version++;
    if (_pages.length > 1 && _pagesOpen) _scheduleThumbs();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: error ? Colors.red : const Color(0xFF1E293B),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  bool get _hasContent => _pages.any((p) => p.objects.isNotEmpty || p.hasPaper);

  // ───────────────────────────── işaretçi olayları ─────────────────────────────
  void _onDown(PointerDownEvent e) {
    _ptrs[e.pointer] = e.localPosition;
    if (_ptrs.length == 2) {
      _abortOp();
      final pts = _ptrs.values.toList();
      _pinchPrevDist = math.max(1.0, (pts[0] - pts[1]).distance);
      _pinchPrevCenter = (pts[0] + pts[1]) / 2;
      return;
    }
    if (_ptrs.length > 2) return;
    if (e.kind == PointerDeviceKind.mouse &&
        (e.buttons & (kMiddleMouseButton | kSecondaryMouseButton)) != 0) {
      _op = _Op.pan;
      _lastScreen = e.localPosition;
      return;
    }
    _begin(e.localPosition);
  }

  void _onMove(PointerMoveEvent e) {
    if (!_ptrs.containsKey(e.pointer)) return;
    _ptrs[e.pointer] = e.localPosition;
    if (_ptrs.length >= 2) {
      _pinch();
      return;
    }
    _update(e.localPosition);
  }

  void _onUp(PointerUpEvent e) {
    final had = _ptrs.containsKey(e.pointer);
    _ptrs.remove(e.pointer);
    if (!had) return;
    if (_ptrs.isNotEmpty) {
      _op = _Op.none;
      return;
    }
    _end(e.localPosition);
  }

  void _onCancel(PointerCancelEvent e) {
    _ptrs.remove(e.pointer);
    if (_ptrs.isEmpty) _abortOp();
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      final page = _page;
      final canvasPt = (e.localPosition - page.offset) / page.scale;
      final ns = wbClampScale(page.scale * math.exp(-e.scrollDelta.dy / 400));
      setState(() {
        page.scale = ns;
        page.offset = e.localPosition - canvasPt * ns;
      });
    }
  }

  void _pinch() {
    final pts = _ptrs.values.toList();
    final center = (pts[0] + pts[1]) / 2;
    final dist = math.max(1.0, (pts[0] - pts[1]).distance);
    final page = _page;
    final canvasPt = (_pinchPrevCenter - page.offset) / page.scale;
    final ns = wbClampScale(page.scale * dist / _pinchPrevDist);
    setState(() {
      page.scale = ns;
      page.offset = center - canvasPt * ns;
    });
    _pinchPrevDist = dist;
    _pinchPrevCenter = center;
  }

  void _abortOp() {
    _preview = null;
    _op = _Op.none;
    _eraserPos = null;
    if (mounted) setState(() {});
  }

  void _begin(Offset pos) {
    final c = _toCanvas(pos);
    _lastCanvas = c;
    _downScreen = pos;
    _lastScreen = pos;
    _tapMoved = false;
    _prepared = false;
    _textTap = null;
    switch (_tool) {
      case WbTool.hand:
        _op = _Op.pan;
        break;
      case WbTool.pen:
      case WbTool.highlighter:
        final hl = _tool == WbTool.highlighter;
        _preview = WbStroke(
          _nextId++,
          points: [c],
          color: _color,
          width: hl ? _width * 3.2 : _width,
          highlighter: hl,
        );
        _op = _Op.draw;
        break;
      case WbTool.eraser:
        _op = _Op.erase;
        _erasePushed = false;
        _eraserPos = c;
        _eraseAt(c);
        break;
      case WbTool.shape:
        _preview = WbShape(
          _nextId++,
          kind: _shape,
          p1: c,
          p2: c,
          color: _color,
          width: _width,
          fill: _fill,
          dashed: _dashed,
        );
        _op = _Op.shape;
        break;
      case WbTool.text:
        _textTap = c;
        _op = _Op.none;
        break;
      case WbTool.laser:
        _op = _Op.laser;
        _addLaser(c);
        break;
      case WbTool.select:
        _beginSelect(pos, c);
        break;
    }
    setState(() {});
  }

  void _beginSelect(Offset pos, Offset c) {
    final page = _page;
    if (_selected != null) {
      final b = _selected!.bounds.inflate(6 / page.scale);
      final handle = page.offset + b.bottomRight * page.scale;
      if ((pos - handle).distance <= 24) {
        _origForResize = _selected!.clone(_selected!.id);
        _anchor = _selected!.bounds.topLeft;
        _startVec = c - _anchor;
        _op = _Op.resize;
        return;
      }
    }
    final tol = 10 / page.scale;
    for (int i = page.objects.length - 1; i >= 0; i--) {
      final o = page.objects[i];
      if (o.hitTest(c, tol)) {
        _selected = o;
        _op = _Op.move;
        return;
      }
    }
    _selected = null;
    _op = _Op.none;
  }

  int _indexOfId(int id) => _page.objects.indexWhere((o) => o.id == id);

  void _prepareModify() {
    if (_prepared || _selected == null) return;
    _prepared = true;
    final idx = _indexOfId(_selected!.id);
    if (idx < 0) return;
    _pushUndo();
    final cl = _selected!.clone(_selected!.id);
    _page.objects[idx] = cl;
    _selected = cl;
    _origForResize ??= null;
  }

  void _update(Offset pos) {
    final prevVersion = _version;
    final c = _toCanvas(pos);
    if ((pos - _downScreen).distance > 6) _tapMoved = true;
    switch (_op) {
      case _Op.pan:
        final d = pos - _lastScreen;
        _page.offset += d;
        _lastScreen = pos;
        break;
      case _Op.draw:
        final s = _preview as WbStroke;
        if ((c - _lastCanvas).distance * _page.scale >= 1.2) {
          s.addPoint(c);
          _lastCanvas = c;
        }
        break;
      case _Op.erase:
        _eraserPos = c;
        final tol = _eraser / 2 / _page.scale;
        final dist = (c - _lastCanvas).distance;
        final steps = math.max(1, (dist / math.max(1.0, tol * 0.6)).ceil());
        for (int i = 1; i <= steps; i++) {
          _eraseAt(Offset.lerp(_lastCanvas, c, i / steps)!);
        }
        _lastCanvas = c;
        break;
      case _Op.shape:
        final sh = _preview as WbShape;
        var p2 = c;
        if (_lockRatio) {
          final d = c - sh.p1;
          if (sh.isLinear) {
            const k = math.pi / 12;
            final ang = (math.atan2(d.dy, d.dx) / k).round() * k;
            p2 = sh.p1 + Offset(math.cos(ang), math.sin(ang)) * d.distance;
          } else {
            final m = math.max(d.dx.abs(), d.dy.abs());
            p2 =
                sh.p1 +
                Offset((d.dx < 0 ? -1 : 1) * m, (d.dy < 0 ? -1 : 1) * m);
          }
        }
        sh.p2 = p2;
        break;
      case _Op.move:
        if (_selected != null && _tapMoved) {
          _prepareModify();
          _selected!.translate(c - _lastCanvas);
          _commitChange();
        }
        _lastCanvas = c;
        break;
      case _Op.resize:
        if (_origForResize != null && _selected != null) {
          if (!_prepared) {
            _prepared = true;
            _pushUndo();
          }
          final vec = c - _anchor;
          var sx = _startVec.dx.abs() < 1e-3 ? 1.0 : vec.dx / _startVec.dx;
          var sy = _startVec.dy.abs() < 1e-3 ? 1.0 : vec.dy / _startVec.dy;
          sx = sx.clamp(0.05, 25.0).toDouble();
          sy = sy.clamp(0.05, 25.0).toDouble();
          if (_origForResize!.uniformScale) {
            final s = (sx + sy) / 2;
            sx = s;
            sy = s;
          }
          final cl = _origForResize!.clone(_origForResize!.id);
          cl.scaleAbout(_anchor, sx, sy);
          final idx = _indexOfId(cl.id);
          if (idx >= 0) {
            _page.objects[idx] = cl;
            _selected = cl;
            _commitChange();
          }
        }
        break;
      case _Op.laser:
        _addLaser(c);
        break;
      case _Op.none:
        break;
    }
    _liveTick.value++;
    if (_op == _Op.pan || _version != prevVersion) {
      setState(() {});
    }
  }

  void _end(Offset pos) {
    switch (_op) {
      case _Op.draw:
        final s = _preview as WbStroke;
        _pushUndo();
        _page.objects.add(s);
        _commitChange();
        _preview = null;
        break;
      case _Op.shape:
        final sh = _preview as WbShape;
        if ((sh.p2 - sh.p1).distance * _page.scale > 4) {
          _pushUndo();
          _page.objects.add(sh);
          _commitChange();
        }
        _preview = null;
        break;
      case _Op.erase:
        _eraserPos = null;
        break;
      case _Op.resize:
        _origForResize = null;
        break;
      default:
        break;
    }
    final tapText = _tool == WbTool.text && !_tapMoved && _textTap != null;
    final tp = _textTap;
    _op = _Op.none;
    _textTap = null;
    setState(() {});
    if (tapText && tp != null) _askText(tp);
  }

  void _addLaser(Offset c) {
    _laser.add(_LaserSample(c, DateTime.now()));
    if (_laser.length > 400) _laser.removeAt(0);
    if (!(_ticker?.isActive ?? false)) {
      _ticker?.start();
    }
  }

  void _eraseAt(Offset c) {
    final tol = _eraser / 2 / _page.scale;
    final hits = _page.objects.where((o) => o.hitTest(c, tol)).toList();
    if (hits.isEmpty) return;
    if (!_erasePushed) {
      _pushUndo();
      _erasePushed = true;
    }
    final ids = hits.map((e) => e.id).toSet();
    _page.objects.removeWhere((o) => ids.contains(o.id));
    if (_selected != null && ids.contains(_selected!.id)) _selected = null;
    _commitChange();
  }

  // ───────────────────────────── eylemler ─────────────────────────────
  void _undo() {
    final p = _page;
    if (p.undo.isEmpty) return;
    p.redo.add(List<WbObject>.of(p.objects));
    p.objects = p.undo.removeLast();
    _selected = null;
    _commitChange();
    setState(() {});
  }

  void _redo() {
    final p = _page;
    if (p.redo.isEmpty) return;
    p.undo.add(List<WbObject>.of(p.objects));
    p.objects = p.redo.removeLast();
    _selected = null;
    _commitChange();
    setState(() {});
  }

  Future<void> _clearPage() async {
    if (_page.objects.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sayfa temizlensin mi?'),
        content: const Text(
          'Bu sayfadaki tüm çizimler silinecek (geri al ile döndürebilirsiniz).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Temizle'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _pushUndo();
    _page.objects = [];
    _selected = null;
    _commitChange();
    setState(() {});
  }

  void _setBackground(WbBackground bg) {
    setState(() {
      _page.bg = bg;
      final dark = wbIsDark(bg);
      if (dark && _color == _palette[0]) _color = Colors.white;
      if (!dark && _color == Colors.white) _color = _palette[0];
      _commitChange();
    });
  }

  void _goPage(int i) {
    if (i < 0 || i >= _pages.length) return;
    setState(() {
      _pi = i;
      _selected = null;
      _preview = null;
      _commitChange();
    });
  }

  void _addPage({bool duplicate = false}) {
    final np = WbPage(bg: _page.bg);
    if (duplicate) {
      np.objects = _page.objects.map((o) => o.clone(_nextId++)).toList();
    }
    setState(() {
      _pages.insert(_pi + 1, np);
      _pi++;
      _selected = null;
      _commitChange();
    });
  }

  void _deletePage() {
    if (_pages.length <= 1) {
      _snack('Son sayfa silinemez; temizleyebilirsiniz.');
      return;
    }
    setState(() {
      _pages.removeAt(_pi);
      _pi = math.min(_pi, _pages.length - 1);
      _selected = null;
      _commitChange();
    });
  }

  void _resetView() {
    setState(() {
      if (_page.hasPaper) {
        _fitPaper(_page);
      } else {
        _page.scale = 1;
        _page.offset = Offset.zero;
      }
    });
  }

  /// Dosyadan gelen sayfayı ekrana sığdırıp ortalar.
  void _fitPaper(WbPage page) {
    final ps = page.paperSize;
    if (ps == null) return;
    final areaW = _viewSize.width - (_panelOpen ? _panelW + 30 : 20);
    final areaH = _viewSize.height - (_dockOpen ? 100 : 20);
    final s = wbClampScale(math.min(areaW / ps.width, areaH / ps.height));
    page.scale = s;
    page.offset = Offset(
      (areaW - ps.width * s) / 2 + 10,
      (areaH - ps.height * s) / 2 + 6,
    );
  }

  double get _panelW => _big ? 380.0 : 300.0;

  // seçili nesne eylemleri
  void _deleteSelected() {
    final s = _selected;
    if (s == null) return;
    _pushUndo();
    _page.objects.removeWhere((o) => o.id == s.id);
    _selected = null;
    _commitChange();
    setState(() {});
  }

  void _duplicateSelected() {
    final s = _selected;
    if (s == null) return;
    _pushUndo();
    final cl = s.clone(_nextId++);
    cl.translate(const Offset(34, 34));
    _page.objects.add(cl);
    _selected = cl;
    _commitChange();
    setState(() {});
  }

  void _reorderSelected(bool toFront) {
    final s = _selected;
    if (s == null) return;
    final idx = _indexOfId(s.id);
    if (idx < 0) return;
    _pushUndo();
    final o = _page.objects.removeAt(idx);
    if (toFront) {
      _page.objects.add(o);
    } else {
      _page.objects.insert(0, o);
    }
    _commitChange();
    setState(() {});
  }

  void _recolorSelected() {
    final s = _selected;
    if (s == null) return;
    final idx = _indexOfId(s.id);
    if (idx < 0) return;
    _pushUndo();
    final cl = s.clone(s.id)..setColor(_color);
    _page.objects[idx] = cl;
    _selected = cl;
    _commitChange();
    setState(() {});
  }

  Future<void> _askText(Offset canvasPos, {WbText? edit}) async {
    final ctrl = TextEditingController(text: edit?.text ?? '');
    double size = edit?.fontSize ?? _textSize;
    bool bold = edit?.bold ?? false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(edit == null ? 'Metin ekle' : 'Metni düzenle'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  maxLines: 4,
                  minLines: 2,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Yazınızı girin...',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('Boyut'),
                    Expanded(
                      child: Slider(
                        min: 14,
                        max: 140,
                        value: size,
                        onChanged: (v) => setD(() => size = v),
                      ),
                    ),
                    Text('${size.round()}'),
                  ],
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: bold,
                  onChanged: (v) => setD(() => bold = v ?? false),
                  title: const Text('Kalın'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tamam'),
            ),
          ],
        ),
      ),
    );
    final text = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || text.isEmpty) return;
    _textSize = size;
    if (edit != null) {
      final idx = _indexOfId(edit.id);
      if (idx < 0) return;
      _pushUndo();
      final cl = (edit.clone(edit.id) as WbText)
        ..text = text
        ..fontSize = size
        ..bold = bold;
      _page.objects[idx] = cl;
      _selected = cl;
    } else {
      _pushUndo();
      final t = WbText(
        _nextId++,
        text: text,
        pos: canvasPos,
        fontSize: size,
        color: _color,
        bold: bold,
      );
      _page.objects.add(t);
    }
    _commitChange();
    if (mounted) setState(() {});
  }

  Future<void> _insertImage() async {
    try {
      final Uint8List? bytes = await wbPickImageBytes();
      if (bytes == null) return;
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final k = math.min(1.0, 520.0 / img.width);
      final rect = Rect.fromCenter(
        center: _viewCenterCanvas,
        width: img.width * k,
        height: img.height * k,
      );
      _pushUndo();
      final o = WbImage(_nextId++, image: img, rect: rect);
      _page.objects.add(o);
      _commitChange();
      setState(() {
        _selected = o;
        _tool = WbTool.select;
      });
    } catch (e) {
      _snack('Resim eklenemedi: $e', error: true);
    }
  }

  Future<void> _insertDiagram(WbDiagramType type) async {
    int rows = 4, cols = 4;
    if (type == WbDiagramType.table) {
      final res = await showDialog<List<int>>(
        context: context,
        builder: (ctx) {
          int r = 4, c = 4;
          return StatefulBuilder(
            builder: (ctx, setD) => AlertDialog(
              title: const Text('Tablo boyutu'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _stepper('Satır', r, (v) => setD(() => r = v)),
                  _stepper('Sütun', c, (v) => setD(() => c = v)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, [r, c]),
                  child: const Text('Ekle'),
                ),
              ],
            ),
          );
        },
      );
      if (res == null) return;
      rows = res[0];
      cols = res[1];
    }
    final center = _viewCenterCanvas;
    Rect rect;
    switch (type) {
      case WbDiagramType.table:
        rect = Rect.fromCenter(
          center: center,
          width: (cols * 120.0).clamp(300.0, 1100.0).toDouble(),
          height: (rows * 64.0).clamp(160.0, 800.0).toDouble(),
        );
        break;
      case WbDiagramType.axes:
        rect = Rect.fromCenter(center: center, width: 560, height: 560);
        cols = 8;
        break;
      case WbDiagramType.numberLine:
        rect = Rect.fromCenter(center: center, width: 760, height: 90);
        cols = 8;
        break;
    }
    _pushUndo();
    final o = WbDiagram(
      _nextId++,
      type: type,
      rect: rect,
      color: _color,
      width: math.max(2.0, math.min(_width, 6.0)),
      rows: rows,
      cols: cols,
    );
    _page.objects.add(o);
    _commitChange();
    setState(() {
      _selected = o;
      _tool = WbTool.select;
    });
  }

  Widget _stepper(String label, int value, void Function(int) onChanged) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline_rounded),
        ),
        SizedBox(
          width: 28,
          child: Center(
            child: Text(
              '$value',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        IconButton(
          onPressed: value < 12 ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
      ],
    );
  }

  // ───────────────────────────── dışa aktarma ─────────────────────────────
  Future<_Rendered> _renderPage(WbPage p) async {
    final ps = p.paperSize;
    if (ps != null) {
      final k = math.min(2.0, 2200 / math.max(ps.width, ps.height));
      final w = (ps.width * k).round();
      final h = (ps.height * k).round();
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      WbCommittedPainter(
        objects: p.objects,
        bg: p.bg,
        scale: k,
        offset: Offset.zero,
        version: 0,
        paperSize: ps,
        paperImage: p.paperImage,
      ).paint(canvas, Size(w.toDouble(), h.toDouble()));
      final img = await rec.endRecording().toImage(w, h);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      return _Rendered(data!.buffer.asUint8List(), w, h);
    }
    const w = 1920.0, h = 1080.0;
    double s = 1;
    Offset off = const Offset(w / 2, h / 2);
    if (p.objects.isNotEmpty) {
      var b = p.objects.first.bounds;
      for (final o in p.objects) {
        b = b.expandToInclude(o.bounds);
      }
      b = b.inflate(60);
      s = math.min(w / b.width, h / b.height).clamp(0.2, 2.0).toDouble();
      off = Offset(
        (w - b.width * s) / 2 - b.left * s,
        (h - b.height * s) / 2 - b.top * s,
      );
    }
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    WbCommittedPainter(
      objects: p.objects,
      bg: p.bg,
      scale: s,
      offset: off,
      version: 0,
    ).paint(canvas, const Size(w, h));
    final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return _Rendered(data!.buffer.asUint8List(), w.toInt(), h.toInt());
  }

  Future<Uint8List> _renderPagePng(WbPage p) async =>
      (await _renderPage(p)).png;

  String get _stamp {
    final n = DateTime.now();
    String t(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${t(n.month)}${t(n.day)}_${t(n.hour)}${t(n.minute)}';
  }

  Future<void> _exportPng() async {
    try {
      final bytes = await _renderPagePng(_page);
      await wbSavePng('Tahta_Sayfa${_pi + 1}_$_stamp', bytes);
      _snack('Sayfa PNG olarak kaydedildi.');
    } catch (e) {
      _snack('Kaydedilemedi: $e', error: true);
    }
  }

  Future<List<WbPdfPage>> _renderAllForPdf() async {
    final list = <WbPdfPage>[];
    for (final p in _pages) {
      final r = await _renderPage(p);
      list.add(WbPdfPage(r.png, r.w.toDouble(), r.h.toDouble()));
    }
    return list;
  }

  Future<void> _exportPdf() async {
    try {
      await wbSavePdf('Tahta_$_stamp', await _renderAllForPdf());
      _snack('Tüm sayfalar PDF olarak kaydedildi (her sayfa kendi boyutunda).');
    } catch (e) {
      _snack('Kaydedilemedi: $e', error: true);
    }
  }

  // ───────────────────────────── ders notu: dosya ekle / kaydet / paylaş ─────────────────────────────
  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<ui.Image> _loadNetworkImage(String url) {
    final c = Completer<ui.Image>();
    final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
    late ImageStreamListener l;
    l = ImageStreamListener(
      (info, _) {
        if (!c.isCompleted) c.complete(info.image);
        stream.removeListener(l);
      },
      onError: (e, s) {
        if (!c.isCompleted) c.completeError(e);
        stream.removeListener(l);
      },
    );
    stream.addListener(l);
    return c.future;
  }

  WbPage _paperPage(ui.Image img, String name) {
    final k = 1400 / math.max(img.width, img.height);
    final page = WbPage(bg: WbBackground.white)
      ..paperSize = Size(img.width * k, img.height * k)
      ..paperImage = img
      ..paperName = name;
    _fitPaper(page);
    return page;
  }

  /// Yeni sayfaları ekler: tek ve boş sayfa varsa onun yerine geçer, yoksa geçerli sayfadan sonra eklenir.
  void _insertPaperPages(List<WbPage> news) {
    if (news.isEmpty) return;
    setState(() {
      final onlyEmpty =
          _pages.length == 1 &&
          _pages.first.objects.isEmpty &&
          !_pages.first.hasPaper;
      if (onlyEmpty) {
        _pages
          ..clear()
          ..addAll(news);
        _pi = 0;
      } else {
        _pages.insertAll(_pi + 1, news);
        _pi = _pi + 1;
      }
      _tool = WbTool.pen;
      _selected = null;
      _commitChange();
    });
  }

  Future<void> _importNoteFiles() async {
    try {
      final files = await wbPickNoteFiles();
      if (files.isEmpty) return;
      _snack('${files.length} dosya işleniyor, lütfen bekleyin...');
      final news = <WbPage>[];
      for (final f in files) {
        if (f.ext == 'pdf') {
          final pages = await wbRasterPdf(f.bytes);
          for (int i = 0; i < pages.length; i++) {
            final img = await _decodeImage(pages[i].png);
            news.add(_paperPage(img, '${f.name} • Sayfa ${i + 1}'));
          }
        } else {
          final img = await _decodeImage(f.bytes);
          news.add(_paperPage(img, f.name));
        }
      }
      _insertPaperPages(news);
      _snack('${news.length} sayfa tahtaya eklendi. Üzerine yazabilirsiniz.');
    } catch (e) {
      _snack('Dosya eklenemedi: $e', error: true);
    }
  }

  Future<void> _openNoteInBoard(LessonNote note) async {
    try {
      _snack('"${note.title}" yükleniyor...');
      final news = <WbPage>[];
      for (int i = 0; i < note.pageUrls.length; i++) {
        final img = await _loadNetworkImage(note.pageUrls[i]);
        news.add(_paperPage(img, '${note.title} • Sayfa ${i + 1}'));
      }
      _insertPaperPages(news);
    } catch (e) {
      _snack('Not açılamadı: $e', error: true);
    }
  }

  Future<void> _saveNote() async {
    if (widget.institutionId.isEmpty) {
      _snack(
        'Not kaydetmek için bu aracı Araçlar menüsünden açın.',
        error: true,
      );
      return;
    }
    if (!_hasContent) {
      _snack('Kaydedilecek içerik yok.');
      return;
    }
    await _refreshThumbs();
    if (!mounted) return;
    final req = await showSaveShareDialog(
      context,
      institutionId: widget.institutionId,
      schoolTypeId: widget.schoolTypeId,
      allowedClassIds: widget.allowedClassIds,
      defaultTitle: 'Ders Notu $_stamp',
      thumbs: [for (final p in _pages) _thumbs[p]?.img],
      labels: [
        for (int i = 0; i < _pages.length; i++)
          _pages[i].paperName != null
              ? '${i + 1} · ${_pages[i].paperName}'
              : 'Sayfa ${i + 1}',
      ],
      currentPage: _pi,
    );
    if (req == null || !mounted) return;

    final msg = ValueNotifier<String>('Sayfalar hazırlanıyor...');
    var progressOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: SizedBox(
            width: 300,
            child: Row(
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: msg,
                    builder: (_, v, __) => Text(v),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    void closeProgress() {
      if (progressOpen && mounted) {
        progressOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    final done = <String>[];
    final errors = <String>[];
    LessonNote? note;
    try {
      final rendered = <_Rendered>[];
      for (final i in req.pages) {
        rendered.add(await _renderPage(_pages[i]));
      }
      final pdfPages = [
        for (final r in rendered)
          WbPdfPage(r.png, r.w.toDouble(), r.h.toDouble()),
      ];
      final safe = req.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

      if (req.pdfFile) {
        msg.value = 'PDF dosyası kaydediliyor...';
        try {
          await wbSavePdf(safe, pdfPages);
          done.add('PDF indirildi');
        } catch (e) {
          errors.add('PDF indirilemedi: $e');
        }
      }
      if (req.pngFiles) {
        msg.value = 'Resimler kaydediliyor...';
        try {
          for (int k = 0; k < rendered.length; k++) {
            await wbSavePng(
              '${safe}_Sayfa${req.pages[k] + 1}',
              rendered[k].png,
            );
          }
          done.add('${rendered.length} resim indirildi');
        } catch (e) {
          errors.add('Resimler indirilemedi: $e');
        }
      }

      if (req.needsCloud) {
        msg.value = 'PDF oluşturuluyor...';
        final pdf = await wbBuildPdf(pdfPages);
        try {
          note = await LessonNotesService.instance.saveNote(
            institutionId: widget.institutionId,
            title: req.title,
            pagePngs: [for (final r in rendered) r.png],
            pdfBytes: pdf,
            onProgress: (m) => msg.value = m,
          );
          _lastSaved = note;
          done.add('Not buluta kaydedildi');
        } catch (e) {
          errors.add(
            'Not buluta yüklenemedi (internet / Firebase Storage izinlerini kontrol edin): $e',
          );
        }
      }

      final t = req.target;
      if (note != null && t != null) {
        if (req.attach) {
          msg.value = 'Ders notu ekleniyor...';
          try {
            await LessonNotesService.instance.attachToClass(
              note: note,
              institutionId: widget.institutionId,
              schoolTypeId: t.schoolTypeId,
              classId: t.classId,
              className: t.className,
              lessonId: t.lessonId,
              lessonName: t.lessonName,
              comment: t.comment,
            );
            done.add('${t.className} • ${t.lessonName} dersine eklendi');
          } catch (e) {
            errors.add('Ders notu eklenemedi: $e');
          }
        }
        if (req.announce) {
          msg.value = 'Duyuru hazırlanıyor...';
          try {
            await LessonNotesService.instance.shareAsAnnouncement(
              title: req.title,
              pdfUrl: note.pdfUrl,
              pageUrls: note.pageUrls,
              classId: t.classId,
              className: t.className,
              schoolTypeId: t.schoolTypeId,
              message: t.comment,
            );
            done.add('${t.className} için duyuru yayınlandı');
          } catch (e) {
            errors.add('Duyuru oluşturulamadı: $e');
          }
        }
      }
    } catch (e) {
      errors.add('İşlem tamamlanamadı: $e');
    }
    closeProgress();
    if (!mounted) return;
    if (errors.isNotEmpty) {
      _snack(errors.join('\n'), error: true);
    } else if (done.isNotEmpty) {
      _snack(done.join(' • '));
    }
    if (note != null && req.message && mounted) {
      await shareNoteAsMessage(context, title: note.title, pdfUrl: note.pdfUrl);
    }
  }

  void _openLibrary() {
    if (widget.institutionId.isEmpty) {
      _snack('Kütüphane için bu aracı Araçlar menüsünden açın.', error: true);
      return;
    }
    showLessonNoteLibrary(
      context,
      institutionId: widget.institutionId,
      schoolTypeId: widget.schoolTypeId,
      allowedClassIds: widget.allowedClassIds,
      onOpenInBoard: _openNoteInBoard,
    );
  }

  Widget _tabNotes() {
    final canSave = widget.institutionId.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Ders notu dosyaları'),
        _tileGrid([
          _actionTile(
            Icons.upload_file_rounded,
            'PDF / Resim Ekle',
            _importNoteFiles,
          ),
          _actionTile(
            Icons.save_rounded,
            'Notu Kaydet',
            _saveNote,
            color: const Color(0xFF059669),
          ),
          _actionTile(
            Icons.folder_special_rounded,
            'Kütüphanem',
            _openLibrary,
            color: const Color(0xFF7C3AED),
          ),
          _actionTile(
            Icons.library_add_rounded,
            'Son Notu Derse Ekle',
            () {
              final n = _lastSaved;
              if (n == null) {
                _snack('Önce notu kaydedin veya Kütüphanem\'den seçin.');
                return;
              }
              attachNoteToClass(
                context,
                n,
                institutionId: widget.institutionId,
                schoolTypeId: widget.schoolTypeId,
                allowedClassIds: widget.allowedClassIds,
              );
            },
            color: const Color(0xFF0EA5E9),
          ),
        ]),
        const SizedBox(height: 10),
        Text(
          '• Birden fazla PDF, PNG veya JPEG seçebilirsiniz. Her dosya ayrı sayfa olur; PDF\'lerin her sayfası kendi boyutuyla açılır.\n'
          '• Sayfanın üzerine kalem, fosforlu kalem, metin ve şekillerle yazabilirsiniz.\n'
          '• "Notu Kaydet" tüm sayfaları PDF + sayfa görselleri olarak kütüphanenize kaydeder; ardından derse ekleyebilir, duyuru veya mesaj olarak paylaşabilirsiniz.\n'
          '• Derse eklenen notlar, ders programında ilgili sınıfa dokununca açılan Ders Sayfası > "Ders Notları" sekmesinde görünür.',
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 12,
            height: 1.4,
          ),
        ),
        if (!canSave)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Kaydetme ve paylaşma için tahtayı Araçlar menüsünden açmanız gerekir.',
              style: TextStyle(
                color: Colors.red.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  // ───────────────────────────── gereçler / yüzen araçlar ─────────────────────────────
  void _openFloat(String kind) {
    setState(() {
      _floats.removeWhere((f) => f.kind == kind);
      _floats.add(_FloatItem(_nextId++, kind));
    });
  }

  void _closeFloat(int id) =>
      setState(() => _floats.removeWhere((f) => f.id == id));

  void _openInstrument(WbInstrumentKind kind) {
    setState(() {
      _insts.removeWhere((i) => i.kind == kind);
      _insts.add(
        _InstItem(
          _nextId++,
          kind,
          Offset(_viewSize.width * 0.4, _viewSize.height * 0.42),
          0,
        ),
      );
    });
  }

  Widget _floatWidget(_FloatItem f, int index) {
    final key = ValueKey('float_${f.id}');
    final initial = Offset(110.0 + index * 34, 80.0 + index * 30);
    switch (f.kind) {
      case 'timer':
        return WbFloatingPanel(
          key: key,
          title: 'Geri Sayım',
          icon: Icons.timer_rounded,
          width: 300,
          initial: initial,
          onClose: () => _closeFloat(f.id),
          child: const WbCountdown(),
        );
      case 'stopwatch':
        return WbFloatingPanel(
          key: key,
          title: 'Kronometre',
          icon: Icons.av_timer_rounded,
          width: 300,
          initial: initial,
          onClose: () => _closeFloat(f.id),
          child: const WbStopwatch(),
        );
      case 'clock':
        return WbFloatingPanel(
          key: key,
          title: 'Saat',
          icon: Icons.access_time_rounded,
          width: 280,
          initial: initial,
          onClose: () => _closeFloat(f.id),
          child: const WbClock(),
        );
      case 'dice':
        return WbFloatingPanel(
          key: key,
          title: 'Zar',
          icon: Icons.casino_rounded,
          width: 290,
          initial: initial,
          onClose: () => _closeFloat(f.id),
          child: const WbDice(),
        );
      case 'coin':
        return WbFloatingPanel(
          key: key,
          title: 'Yazı - Tura',
          icon: Icons.monetization_on_rounded,
          width: 270,
          initial: initial,
          onClose: () => _closeFloat(f.id),
          child: const WbCoin(),
        );
      case 'random':
        return WbFloatingPanel(
          key: key,
          title: 'Rastgele Sayı',
          icon: Icons.shuffle_rounded,
          width: 290,
          initial: initial,
          onClose: () => _closeFloat(f.id),
          child: const WbRandomNumber(),
        );
      case 'student':
        return WbFloatingPanel(
          key: key,
          title: 'Rastgele Öğrenci',
          icon: Icons.person_search_rounded,
          width: 340,
          initial: initial,
          onClose: () => _closeFloat(f.id),
          child: WbStudentPicker(
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
            allowedClassIds: widget.allowedClassIds,
          ),
        );
      case 'calc':
        return WbFloatingPanel(
          key: key,
          title: 'Hesap Makinesi',
          icon: Icons.calculate_rounded,
          width: 330,
          initial: initial,
          onClose: () => _closeFloat(f.id),
          child: const WbCalculator(),
        );
      case 'graph':
        return WbFloatingPanel(
          key: key,
          title: 'Grafik Çizici',
          icon: Icons.show_chart_rounded,
          width: 420,
          initial: initial,
          onClose: () => _closeFloat(f.id),
          child: const WbGrapher(),
        );
    }
    return const SizedBox.shrink();
  }

  Future<void> _exit() async {
    if (!_hasContent) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tahtadan çıkılsın mı?'),
        content: const Text('Kaydetmediğiniz çizimler kaybolur.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'stay'),
            child: const Text('Kal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('PNG kaydet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'exit'),
            child: const Text('Çık'),
          ),
        ],
      ),
    );
    if (res == 'save') {
      await _exportPng();
    }
    if ((res == 'exit' || res == 'save') && mounted)
      Navigator.of(context).pop();
  }

  // ───────────────────────────── arayüz ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    final page = _page;
    final dark = wbIsDark(page.bg);

    return PopScope(
      canPop: !_hasContent,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        backgroundColor: wbBgColor(page.bg),
        body: LayoutBuilder(
          builder: (context, cons) {
            _viewSize = Size(cons.maxWidth, cons.maxHeight);
            if (!_bigDecided) {
              _bigDecided = true;
              _big =
                  cons.maxWidth >=
                  1700; // akıllı tahta / büyük dokunmatik ekran
            }
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(_big ? 1.25 : 1.0)),
              child: Stack(
                key: _stackKey,
                clipBehavior: Clip.hardEdge,
                children: [
                  // ── tahta yüzeyi ──
                  Positioned.fill(
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _onDown,
                      onPointerMove: _onMove,
                      onPointerUp: _onUp,
                      onPointerCancel: _onCancel,
                      onPointerSignal: _onSignal,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: WbCommittedPainter(
                                  objects: page.objects,
                                  bg: page.bg,
                                  scale: page.scale,
                                  offset: page.offset,
                                  version: _version,
                                  paperSize: page.paperSize,
                                  paperImage: page.paperImage,
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: RepaintBoundary(
                              child: ValueListenableBuilder<int>(
                                valueListenable: _liveTick,
                                builder: (_, __, ___) {
                                  final laserPts = <WbLaserPoint>[];
                                  if (_laser.isNotEmpty) {
                                    final now = DateTime.now();
                                    for (final s in _laser) {
                                      laserPts.add(
                                        WbLaserPoint(
                                          s.p,
                                          (now.difference(s.t).inMilliseconds /
                                                  1400)
                                              .clamp(0.0, 1.0)
                                              .toDouble(),
                                        ),
                                      );
                                    }
                                  }
                                  return CustomPaint(
                                    painter: WbLivePainter(
                                      preview: _preview,
                                      selection: _selected?.bounds,
                                      scale: page.scale,
                                      offset: page.offset,
                                      eraserPos: _eraserPos,
                                      eraserRadius: _eraser / 2 / page.scale,
                                      laser: laserPts,
                                      darkBg: dark,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── cetvel / iletki / gönye ──
                  for (final inst in _insts)
                    WbInstrumentView(
                      key: ValueKey('inst_${inst.id}'),
                      kind: inst.kind,
                      pos: inst.pos,
                      angle: inst.angle,
                      stackKey: _stackKey,
                      onChanged: (p, a) => setState(() {
                        inst.pos = p;
                        inst.angle = a;
                      }),
                      onClose: () => setState(() => _insts.remove(inst)),
                    ),

                  // ── yüzen araçlar ──
                  for (int i = 0; i < _floats.length; i++)
                    _floatWidget(_floats[i], i),

                  // ── seçili nesne çubuğu ──
                  if (_selected != null) _buildSelectionBar(),

                  // ── alt araç çubuğu ──
                  _buildDock(),

                  // ── sağ panel ──
                  _buildPanel(),

                  // ── sol sayfa şeridi ──
                  _buildPagesStrip(dark),

                  // ── gizle/göster tutamaçları ──
                  _buildHandles(),

                  // ── geri tuşu (sol üst) ──
                  Positioned(
                    left: 12,
                    top: 12,
                    child: _Block(
                      child: Material(
                        color: dark
                            ? const Color(0xCC0F172A)
                            : const Color(0xE6FFFFFF),
                        elevation: 6,
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Geri',
                          icon: Icon(
                            Icons.arrow_back_rounded,
                            color: dark
                                ? Colors.white
                                : const Color(0xFF111827),
                          ),
                          onPressed: _exit,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSelectionBar() {
    final sel = _selected!;
    return Positioned(
      top: 12,
      left: 0,
      right: 0,
      child: Center(
        child: _Block(
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            color: const Color(0xFF1E293B),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (sel is WbText)
                    _barBtn(
                      Icons.edit_rounded,
                      'Metni düzenle',
                      () => _askText(sel.pos, edit: sel),
                    ),
                  _barBtn(
                    Icons.palette_rounded,
                    'Seçili rengi uygula',
                    _recolorSelected,
                  ),
                  _barBtn(Icons.copy_rounded, 'Çoğalt', _duplicateSelected),
                  _barBtn(
                    Icons.flip_to_front_rounded,
                    'Öne getir',
                    () => _reorderSelected(true),
                  ),
                  _barBtn(
                    Icons.flip_to_back_rounded,
                    'Arkaya gönder',
                    () => _reorderSelected(false),
                  ),
                  _barBtn(
                    Icons.delete_rounded,
                    'Sil',
                    _deleteSelected,
                    color: Colors.redAccent,
                  ),
                  _barBtn(
                    Icons.close_rounded,
                    'Seçimi bırak',
                    () => setState(() => _selected = null),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _barBtn(
    IconData icon,
    String tip,
    VoidCallback onTap, {
    Color color = Colors.white,
  }) {
    return IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, color: color, size: 20),
      onPressed: onTap,
    );
  }

  // ── sol sayfa şeridi (küçük resimler) ──
  int _thumbSig(WbPage p) => Object.hash(
    p.objects.length,
    p.undo.length,
    p.redo.length,
    p.bg,
    p.paperImage,
    p.objects.isEmpty ? 0 : p.objects.last.id,
  );

  void _scheduleThumbs() {
    _thumbTimer?.cancel();
    _thumbTimer = Timer(const Duration(milliseconds: 450), _refreshThumbs);
  }

  Future<void> _refreshThumbs() async {
    if (!mounted) return;
    _thumbs.removeWhere((p, t) {
      if (_pages.contains(p)) return false;
      t.img.dispose();
      return true;
    });
    var changed = false;
    for (final p in List<WbPage>.of(_pages)) {
      final sig = _thumbSig(p);
      final cur = _thumbs[p];
      if ((cur != null && cur.sig == sig) || _thumbBusy.contains(p)) continue;
      _thumbBusy.add(p);
      try {
        final img = await _renderThumb(p);
        if (!mounted) {
          img.dispose();
          return;
        }
        _thumbs[p]?.img.dispose();
        _thumbs[p] = _Thumb(sig, img);
        changed = true;
      } catch (_) {
        // küçük resim üretilemezse sessizce geç
      } finally {
        _thumbBusy.remove(p);
      }
    }
    if (changed && mounted) setState(() {});
  }

  Future<ui.Image> _renderThumb(WbPage p) async {
    const tw = 260;
    final ps = p.paperSize;
    final double bw = ps?.width ?? 1920.0;
    final double bh = ps?.height ?? 1080.0;
    final th = math.max(40, (tw * bh / bw).round());
    double s = 1;
    Offset off = Offset.zero;
    if (ps != null) {
      s = 1;
    } else {
      off = Offset(bw / 2, bh / 2);
      if (p.objects.isNotEmpty) {
        var b = p.objects.first.bounds;
        for (final o in p.objects) {
          b = b.expandToInclude(o.bounds);
        }
        b = b.inflate(60);
        s = math.min(bw / b.width, bh / b.height).clamp(0.2, 2.0).toDouble();
        off = Offset(
          (bw - b.width * s) / 2 - b.left * s,
          (bh - b.height * s) / 2 - b.top * s,
        );
      }
    }
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.scale(tw / bw);
    WbCommittedPainter(
      objects: p.objects,
      bg: p.bg,
      scale: s,
      offset: off,
      version: 0,
      paperSize: ps,
      paperImage: p.paperImage,
    ).paint(canvas, Size(bw, bh));
    return rec.endRecording().toImage(tw, th);
  }

  Widget _buildPagesStrip(bool dark) {
    final w = _big ? 170.0 : 140.0;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: (_pages.length > 1 && _pagesOpen) ? 12 : -(w + 30),
      top: 66,
      bottom: 76,
      width: w,
      child: RepaintBoundary(
        child: _Block(
          child: Material(
            elevation: 12,
            shadowColor: Colors.black54,
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Sayfalar (${_pages.length})',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Yeni sayfa',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.add_circle_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                        onPressed: () => _addPage(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                    itemCount: _pages.length,
                    itemBuilder: (_, i) {
                      final p = _pages[i];
                      final sel = i == _pi;
                      final t = _thumbs[p];
                      final ratio = p.paperSize != null
                          ? p.paperSize!.width / p.paperSize!.height
                          : 16 / 9;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GestureDetector(
                          onTap: () => _goPage(i),
                          child: Column(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: sel
                                        ? const Color(0xFF60A5FA)
                                        : Colors.white24,
                                    width: sel ? 3 : 1,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: Stack(
                                    children: [
                                      AspectRatio(
                                        aspectRatio: ratio,
                                        child: t == null
                                            ? Container(color: wbBgColor(p.bg))
                                            : RawImage(
                                                image: t.img,
                                                fit: BoxFit.fill,
                                              ),
                                      ),
                                      if (sel && _pages.length > 1)
                                        Positioned(
                                          right: 2,
                                          top: 2,
                                          child: InkWell(
                                            onTap: _deletePage,
                                            child: Container(
                                              padding: const EdgeInsets.all(3),
                                              decoration: const BoxDecoration(
                                                color: Color(0xCCDC2626),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.close_rounded,
                                                size: 14,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                p.paperName != null
                                    ? '${i + 1} · ${p.paperName}'
                                    : '${i + 1}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: sel ? Colors.white : Colors.white70,
                                  fontSize: 11,
                                  fontWeight: sel
                                      ? FontWeight.w800
                                      : FontWeight.w600,
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
      ),
    );
  }

  Widget _buildHandles() {
    final stripW = _big ? 170.0 : 140.0;
    return Stack(
      children: [
        if (_pages.length > 1)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            left: _pagesOpen ? stripW + 16 : 8,
            top: _viewSize.height / 2 - 26,
            child: _Block(
              child: Material(
                color: const Color(0xFF1E293B),
                elevation: 8,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    setState(() => _pagesOpen = !_pagesOpen);
                    if (_pagesOpen && _pages.length > 1) _scheduleThumbs();
                  },
                  child: SizedBox(
                    width: 34,
                    height: 52,
                    child: Tooltip(
                      message: _pagesOpen
                          ? 'Sayfaları gizle'
                          : 'Sayfaları göster (${_pages.length})',
                      child: Icon(
                        _pagesOpen
                            ? Icons.chevron_left_rounded
                            : Icons.chevron_right_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          left: 14,
          bottom: 14,
          child: _Block(
            child: Material(
              color: const Color(0xFF1E293B),
              elevation: 8,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: _dockOpen
                    ? 'Alt araç çubuğunu gizle'
                    : 'Alt araç çubuğunu göster',
                icon: Icon(
                  _dockOpen
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_up_rounded,
                  color: Colors.white,
                ),
                onPressed: () => setState(() => _dockOpen = !_dockOpen),
              ),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          right: _panelOpen ? _panelW + 16 : 8,
          top: _viewSize.height / 2 - 26,
          child: _Block(
            child: Material(
              color: const Color(0xFF1E293B),
              elevation: 8,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _panelOpen = !_panelOpen),
                child: SizedBox(
                  width: 34,
                  height: 52,
                  child: Icon(
                    _panelOpen
                        ? Icons.chevron_right_rounded
                        : Icons.chevron_left_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── alt araç çubuğu ──
  Widget _buildDock() {
    final rightInset = _panelOpen ? _panelW + 32 : 16.0;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: 70,
      right: rightInset,
      bottom: _dockOpen ? 14 : -120,
      child: Center(
        child: RepaintBoundary(
          child: _Block(
            child: Material(
              elevation: 14,
              shadowColor: Colors.black54,
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.max(200.0, _viewSize.width - 70 - rightInset),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _dockBtn(
                        Icons.edit_rounded,
                        'Kalem',
                        _tool == WbTool.pen,
                        () => setState(() => _tool = WbTool.pen),
                      ),
                      _dockGlyphBtn(
                        _WbGlyphKind.highlighter,
                        'Fosforlu Kalem',
                        _tool == WbTool.highlighter,
                        () => setState(() => _tool = WbTool.highlighter),
                      ),
                      _dockBtn(
                        Icons.cleaning_services_rounded,
                        'Silgi',
                        _tool == WbTool.eraser,
                        () => setState(() => _tool = WbTool.eraser),
                      ),
                      _dockBtn(
                        Icons.near_me_rounded,
                        'Seç / Taşı / Boyutlandır',
                        _tool == WbTool.select,
                        () => setState(() => _tool = WbTool.select),
                      ),
                      _dockGlyphBtn(
                        _WbGlyphKind.laser,
                        'Lazer İşaretçi',
                        _tool == WbTool.laser,
                        () => setState(() => _tool = WbTool.laser),
                      ),
                      _dockGlyphBtn(
                        _WbGlyphKind.hand,
                        'Kaydır (El)',
                        _tool == WbTool.hand,
                        () => setState(() => _tool = WbTool.hand),
                      ),
                      _dockBtn(
                        Icons.category_rounded,
                        'Şekil: ${_shapeNames[_shape]}',
                        _tool == WbTool.shape,
                        () => setState(() {
                          _tool = WbTool.shape;
                          _panelOpen = true;
                          _tab = 1;
                        }),
                      ),
                      _dockBtn(
                        Icons.title_rounded,
                        'Metin',
                        _tool == WbTool.text,
                        () => setState(() => _tool = WbTool.text),
                      ),
                      _divider(),
                      for (int i = 0; i < 8; i++) _colorDot(_palette[i]),
                      _divider(),
                      _dockGlyphBtn(
                        _WbGlyphKind.undo,
                        'Geri al',
                        false,
                        _page.undo.isEmpty ? null : _undo,
                      ),
                      _dockGlyphBtn(
                        _WbGlyphKind.redo,
                        'İleri al',
                        false,
                        _page.redo.isEmpty ? null : _redo,
                      ),
                      _dockBtn(
                        Icons.delete_sweep_rounded,
                        'Sayfayı temizle',
                        false,
                        _clearPage,
                      ),
                      _divider(),
                      _dockBtn(
                        Icons.chevron_left_rounded,
                        'Önceki sayfa',
                        false,
                        _pi > 0 ? () => _goPage(_pi - 1) : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '${_pi + 1}/${_pages.length}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      _dockBtn(
                        Icons.chevron_right_rounded,
                        'Sonraki sayfa',
                        false,
                        _pi < _pages.length - 1 ? () => _goPage(_pi + 1) : null,
                      ),
                      _dockGlyphBtn(
                        _WbGlyphKind.addPage,
                        'Yeni sayfa',
                        false,
                        () => _addPage(),
                      ),
                      _dockBtn(
                        Icons.upload_file_rounded,
                        'PDF / Resim ekle (ders notu)',
                        false,
                        _importNoteFiles,
                      ),
                      _dockBtn(
                        Icons.save_rounded,
                        'Notu kaydet ve paylaş',
                        false,
                        _saveNote,
                      ),
                      _divider(),
                      Tooltip(
                        message: 'Görünümü sıfırla',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _resetView,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            child: Text(
                              '%${(_page.scale * 100).round()}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                      _dockGlyphBtn(
                        _fsActive
                            ? _WbGlyphKind.fullscreenExit
                            : _WbGlyphKind.fullscreen,
                        _fsActive
                            ? 'Tam ekrandan çık (Esc)'
                            : 'Tam ekran (F11)',
                        _fsActive,
                        _toggleFullscreen,
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Kaydet / Paylaş',
                        icon: const Icon(Icons.ios_share_rounded),
                        onSelected: (v) {
                          if (v == 'png') _exportPng();
                          if (v == 'pdf') _exportPdf();
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'png',
                            child: Text('Bu sayfayı PNG kaydet'),
                          ),
                          PopupMenuItem(
                            value: 'pdf',
                            child: Text('Tüm sayfaları PDF kaydet'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider() => Container(
    width: 1,
    height: 28,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: Colors.grey.shade300,
  );

  Widget _dockBtn(
    IconData icon,
    String tip,
    bool selected,
    VoidCallback? onTap,
  ) {
    return Tooltip(
      message: tip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: selected ? const Color(0xFF2563EB) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: SizedBox(
              width: _big ? 62 : 46,
              height: _big ? 62 : 46,
              child: Icon(
                icon,
                size: _big ? 32 : 24,
                color: onTap == null
                    ? Colors.grey.shade400
                    : (selected ? Colors.white : const Color(0xFF1E293B)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dockGlyphBtn(
    _WbGlyphKind glyph,
    String tip,
    bool selected,
    VoidCallback? onTap,
  ) {
    final iconColor = onTap == null
        ? Colors.grey.shade400
        : (selected ? Colors.white : const Color(0xFF1E293B));
    final iconSize = _big ? 32.0 : 24.0;
    return Tooltip(
      message: tip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: selected ? const Color(0xFF2563EB) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: SizedBox(
              width: _big ? 62 : 46,
              height: _big ? 62 : 46,
              child: Center(
                child: CustomPaint(
                  size: Size.square(iconSize),
                  painter: _WbGlyphPainter(glyph, iconColor),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionGlyphTile(
    _WbGlyphKind glyph,
    String label,
    VoidCallback onTap, {
    Color color = const Color(0xFF2563EB),
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CustomPaint(
              size: const Size.square(26),
              painter: _WbGlyphPainter(glyph, color),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color.withValues(alpha: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorDot(Color c) {
    final sel = _color == c;
    return GestureDetector(
      onTap: () => setState(() => _color = c),
      child: Container(
        width: sel ? 30 : 24,
        height: sel ? 30 : 24,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(
            color: sel ? const Color(0xFF2563EB) : Colors.grey.shade400,
            width: sel ? 3 : 1,
          ),
        ),
      ),
    );
  }

  // ── sağ panel ──
  Widget _buildPanel() {
    const tabs = [
      'Çizim',
      'Şekiller',
      'Kütüphane',
      'Ekle',
      'Gereçler',
      'Sayfa',
      'Notlar',
    ];
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      right: _panelOpen ? 12 : -(_panelW + 30),
      top: 12,
      bottom: 12,
      width: _panelW,
      child: RepaintBoundary(
        child: _Block(
          child: Material(
            elevation: 14,
            shadowColor: Colors.black54,
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  color: const Color(0xFF1E293B),
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (int i = 0; i < tabs.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(
                                tabs[i],
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _tab == i
                                      ? Colors.white
                                      : const Color(0xFF1E293B),
                                ),
                              ),
                              selected: _tab == i,
                              selectedColor: const Color(0xFF2563EB),
                              showCheckmark: false,
                              visualDensity: VisualDensity.compact,
                              onSelected: (_) => setState(() => _tab = i),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(14),
                    child: _panelBody(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _panelBody() {
    switch (_tab) {
      case 0:
        return _tabDraw();
      case 1:
        return _tabShapes();
      case 2:
        return _tabLibrary();
      case 3:
        return _tabInsert();
      case 4:
        return _tabTools();
      case 5:
        return _tabPage();
      default:
        return _tabNotes();
    }
  }

  Widget _title(String t) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 8),
    child: Text(
      t,
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 13,
        color: Color(0xFF334155),
      ),
    ),
  );

  Widget _tabDraw() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Renk'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in _palette)
              GestureDetector(
                onTap: () => setState(() => _color = c),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _color == c
                          ? const Color(0xFF2563EB)
                          : Colors.grey.shade400,
                      width: _color == c ? 3.5 : 1,
                    ),
                  ),
                ),
              ),
            GestureDetector(
              onTap: _pickCustomColor,
              child: Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: [
                      Colors.red,
                      Colors.yellow,
                      Colors.green,
                      Colors.cyan,
                      Colors.blue,
                      Colors.purple,
                      Colors.red,
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _title('Kalınlık: ${_width.round()}'),
        Slider(
          min: 1,
          max: 40,
          value: _width,
          onChanged: (v) => setState(() => _width = v),
        ),
        Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: wbIsDark(_page.bg)
                ? const Color(0xFF14171C)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Container(
            width: 120,
            height: _tool == WbTool.highlighter ? _width * 3.2 : _width,
            decoration: BoxDecoration(
              color: _tool == WbTool.highlighter
                  ? _color.withValues(alpha: 0.4)
                  : _color,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade400, width: 0.5),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _title('Silgi boyutu: ${_eraser.round()}'),
        Slider(
          min: 12,
          max: 120,
          value: _eraser,
          onChanged: (v) => setState(() => _eraser = v),
        ),
        _title('Metin boyutu: ${_textSize.round()}'),
        Slider(
          min: 14,
          max: 140,
          value: _textSize,
          onChanged: (v) => setState(() => _textSize = v),
        ),
        const Divider(),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: _fill,
          onChanged: (v) => setState(() => _fill = v),
          title: const Text('Şekilleri doldur', style: TextStyle(fontSize: 13)),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: _dashed,
          onChanged: (v) => setState(() => _dashed = v),
          title: const Text('Kesikli çizgi', style: TextStyle(fontSize: 13)),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: _lockRatio,
          onChanged: (v) => setState(() => _lockRatio = v),
          title: const Text(
            'Oranı / açıyı kilitle (kare, daire, 15° çizgi)',
            style: TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }

  Future<void> _pickCustomColor() async {
    HSVColor hsv = HSVColor.fromColor(_color);
    final res = await showDialog<Color>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Özel renk'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: hsv.toColor(),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 8),
                Slider(
                  min: 0,
                  max: 360,
                  value: hsv.hue,
                  onChanged: (v) => setD(() => hsv = hsv.withHue(v)),
                ),
                Slider(
                  min: 0,
                  max: 1,
                  value: hsv.saturation,
                  onChanged: (v) => setD(() => hsv = hsv.withSaturation(v)),
                ),
                Slider(
                  min: 0,
                  max: 1,
                  value: hsv.value,
                  onChanged: (v) => setD(() => hsv = hsv.withValue(v)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, hsv.toColor()),
              child: const Text('Seç'),
            ),
          ],
        ),
      ),
    );
    if (res != null) setState(() => _color = res);
  }

  // ── Şekil kütüphanesi (ders başlıklarına göre hazır çizimler) ──
  Future<void> _loadArtUse() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('wb_art_usage');
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _artUse
          ..clear()
          ..addAll(m.map((k, v) => MapEntry(k, (v as num).toInt())));
      });
    } catch (_) {}
  }

  Future<void> _saveArtUse() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('wb_art_usage', jsonEncode(_artUse));
    } catch (_) {}
  }

  int _use(WbArtItem i) => _artUse[i.id] ?? 0;

  /// Çok kullanılan şekiller önce (eşitlikte katalog sırası korunur).
  List<WbArtItem> _byUsage(Iterable<WbArtItem> items) {
    final list = items.toList();
    final idx = {for (int i = 0; i < list.length; i++) list[i].id: i};
    list.sort((a, b) {
      final c = _use(b).compareTo(_use(a));
      return c != 0 ? c : idx[a.id]!.compareTo(idx[b.id]!);
    });
    return list;
  }

  Widget _artGrid(List<WbArtItem> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.05,
      ),
      itemBuilder: (_, i) => _artCard(items[i]),
    );
  }

  Widget _artCard(WbArtItem it) {
    final uses = _use(it);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _insertArt(it),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: uses > 0 ? const Color(0xFFFBBF24) : Colors.grey.shade300,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _ArtThumbPainter(it),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                  if (uses > 0)
                    const Positioned(
                      right: 0,
                      top: 0,
                      child: Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              it.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _insertArt(WbArtItem item) {
    _artUse[item.id] = _use(item) + 1;
    _saveArtUse();
    final center = _viewCenterCanvas;
    final longSide = 520 / _page.scale.clamp(0.3, 3.0);
    final k = longSide / math.max(item.w, item.h);
    final rect = Rect.fromCenter(
      center: center,
      width: item.w * k,
      height: item.h * k,
    );
    _pushUndo();
    final o = WbClipArt(
      _nextId++,
      artId: item.id,
      rect: rect,
      color: _color,
      width: math.max(1.6, math.min(_width, 5.0)),
    );
    _page.objects.add(o);
    _commitChange();
    setState(() {
      _selected = o;
      _tool = WbTool.select;
    });
  }

  Widget _tabLibrary() {
    final q = _artQuery.trim().toLowerCase();
    final List<WbArtItem> items = [];
    for (final c in wbArtCatalog) {
      if (q.isEmpty && c.id != _artCat) continue;
      for (final i in c.items) {
        if (q.isEmpty ||
            i.name.toLowerCase().contains(q) ||
            i.tags.contains(q)) {
          items.add(i);
        }
      }
    }
    final cat = wbArtCatalog.firstWhere(
      (c) => c.id == _artCat,
      orElse: () => wbArtCatalog.first,
    );
    // Kullandıklarınız yukarıda: kategori içinde önce kullanılanlar,
    // ayrıca en üstte "Sık kullandıklarım" bölümü.
    final sorted = _byUsage(items);
    final favs = q.isEmpty
        ? _byUsage([
            for (final c in wbArtCatalog) ...c.items,
          ]).where((i) => _use(i) > 0).take(6).toList()
        : <WbArtItem>[];
    items
      ..clear()
      ..addAll(sorted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Şekil kütüphanesi'),
        if (favs.isNotEmpty) ...[
          const Row(
            children: [
              Icon(Icons.star_rounded, size: 18, color: Color(0xFFF59E0B)),
              SizedBox(width: 4),
              Text(
                'Sık kullandıklarım',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _artGrid(favs),
          const Divider(height: 22),
        ],
        TextField(
          controller: _artSearchCtrl,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Ara: harita, kaldıraç, beher, piramit…',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _artQuery.isEmpty
                ? null
                : IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      _artSearchCtrl.clear();
                      setState(() => _artQuery = '');
                    },
                  ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (v) => setState(() => _artQuery = v),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in wbArtCatalog)
              ChoiceChip(
                avatar: Icon(
                  c.icon,
                  size: 16,
                  color: _artCat == c.id && q.isEmpty ? Colors.white : c.color,
                ),
                label: Text(
                  '${c.name} (${c.items.length})',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: _artCat == c.id && q.isEmpty
                        ? Colors.white
                        : const Color(0xFF1E293B),
                  ),
                ),
                selected: _artCat == c.id && q.isEmpty,
                selectedColor: c.color,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) {
                  _artSearchCtrl.clear();
                  setState(() {
                    _artCat = c.id;
                    _artQuery = '';
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          q.isEmpty
              ? '${cat.name}: ${items.length} şekil'
              : '"$_artQuery" için ${items.length} sonuç',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: Text('Sonuç bulunamadı')),
          )
        else
          _artGrid(items),
        const SizedBox(height: 10),
        Text(
          'Şekle dokununca tahtanın ortasına eklenir. "Seç" aracıyla taşıyın, köşeden büyütün; renk panelinden çizgi rengini değiştirin.',
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _tabShapes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Şekil seçin, tahtada sürükleyerek çizin'),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (final k in WbShapeKind.values)
              Tooltip(
                message: _shapeNames[k] ?? '',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() {
                    _shape = k;
                    _tool = WbTool.shape;
                  }),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _shape == k && _tool == WbTool.shape
                          ? const Color(0xFFDBEAFE)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _shape == k && _tool == WbTool.shape
                            ? const Color(0xFF2563EB)
                            : Colors.grey.shade300,
                        width: _shape == k && _tool == WbTool.shape ? 2 : 1,
                      ),
                    ),
                    child: CustomPaint(painter: _ShapeIconPainter(k)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Seçili: ${_shapeNames[_shape]}',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
        ),
      ],
    );
  }

  Widget _actionTile(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color color = const Color(0xFF2563EB),
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color.withValues(alpha: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tileGrid(List<Widget> tiles) => GridView.count(
    crossAxisCount: 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
    childAspectRatio: 1.45,
    children: tiles,
  );

  Widget _tabInsert() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Tahtaya ekle'),
        _tileGrid([
          _actionTile(
            Icons.title_rounded,
            'Metin',
            () => setState(() => _tool = WbTool.text),
          ),
          _actionTile(Icons.image_rounded, 'Resim', _insertImage),
          _actionTile(
            Icons.table_chart_rounded,
            'Tablo',
            () => _insertDiagram(WbDiagramType.table),
          ),
          _actionTile(
            Icons.timeline_rounded,
            'Koordinat Düzlemi',
            () => _insertDiagram(WbDiagramType.axes),
          ),
          _actionTile(
            Icons.straighten_rounded,
            'Sayı Doğrusu',
            () => _insertDiagram(WbDiagramType.numberLine),
          ),
        ]),
        const SizedBox(height: 10),
        Text(
          'Eklenen nesneleri "Seç" aracıyla taşıyabilir, sağ-alt köşedeki tutamaçla büyütüp küçültebilirsiniz.',
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _tabTools() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Çizim gereçleri'),
        _tileGrid([
          _actionTile(
            Icons.straighten_rounded,
            'Cetvel',
            () => _openInstrument(WbInstrumentKind.ruler),
            color: const Color(0xFFB45309),
          ),
          _actionTile(
            Icons.architecture_rounded,
            'İletki',
            () => _openInstrument(WbInstrumentKind.protractor),
            color: const Color(0xFFB45309),
          ),
          _actionTile(
            Icons.change_history_rounded,
            'Gönye 30°-60°',
            () => _openInstrument(WbInstrumentKind.setSquare),
            color: const Color(0xFFB45309),
          ),
          _actionTile(
            Icons.signal_cellular_alt_rounded,
            'Gönye 45°',
            () => _openInstrument(WbInstrumentKind.setSquare45),
            color: const Color(0xFFB45309),
          ),
        ]),
        const SizedBox(height: 10),
        _title('Sınıf araçları'),
        _tileGrid([
          _actionTile(
            Icons.timer_rounded,
            'Geri Sayım',
            () => _openFloat('timer'),
            color: const Color(0xFF059669),
          ),
          _actionTile(
            Icons.av_timer_rounded,
            'Kronometre',
            () => _openFloat('stopwatch'),
            color: const Color(0xFF059669),
          ),
          _actionTile(
            Icons.access_time_rounded,
            'Saat',
            () => _openFloat('clock'),
            color: const Color(0xFF059669),
          ),
          _actionTile(
            Icons.casino_rounded,
            'Zar',
            () => _openFloat('dice'),
            color: const Color(0xFF7C3AED),
          ),
          _actionTile(
            Icons.monetization_on_rounded,
            'Yazı - Tura',
            () => _openFloat('coin'),
            color: const Color(0xFF7C3AED),
          ),
          _actionTile(
            Icons.shuffle_rounded,
            'Rastgele Sayı',
            () => _openFloat('random'),
            color: const Color(0xFF7C3AED),
          ),
          _actionTile(
            Icons.person_search_rounded,
            'Rastgele Öğrenci',
            () => _openFloat('student'),
            color: const Color(0xFF7C3AED),
          ),
          _actionTile(
            Icons.calculate_rounded,
            'Hesap Makinesi',
            () => _openFloat('calc'),
            color: const Color(0xFFE11D48),
          ),
          _actionTile(
            Icons.show_chart_rounded,
            'Grafik Çizici',
            () => _openFloat('graph'),
            color: const Color(0xFFE11D48),
          ),
        ]),
      ],
    );
  }

  Widget _tabPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: _big,
          onChanged: (v) => setState(() => _big = v),
          title: const Text(
            'Büyük arayüz (akıllı tahta / dokunmatik)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          subtitle: const Text(
            'Düğmeleri ve yazıları büyütür',
            style: TextStyle(fontSize: 11),
          ),
        ),
        const Divider(),
        _title('Arka plan'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final bg in WbBackground.values)
              ChoiceChip(
                label: Text(
                  _bgNames[bg] ?? '',
                  style: const TextStyle(fontSize: 12),
                ),
                selected: _page.bg == bg,
                onSelected: (_) => _setBackground(bg),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _title('Sayfalar (${_pages.length})'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (int i = 0; i < _pages.length; i++)
              ChoiceChip(
                label: Text('${i + 1}'),
                selected: _pi == i,
                onSelected: (_) => _goPage(i),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _tileGrid([
          _actionGlyphTile(
            _WbGlyphKind.addPage,
            'Yeni Sayfa',
            () => _addPage(),
          ),
          _actionTile(
            Icons.copy_all_rounded,
            'Sayfayı Çoğalt',
            () => _addPage(duplicate: true),
          ),
          _actionTile(
            Icons.delete_outline_rounded,
            'Sayfayı Sil',
            _deletePage,
            color: Colors.red,
          ),
          _actionTile(
            Icons.delete_sweep_rounded,
            'Sayfayı Temizle',
            _clearPage,
            color: Colors.red,
          ),
        ]),
        const SizedBox(height: 10),
        _title('Kaydet / Paylaş'),
        _tileGrid([
          _actionTile(
            Icons.image_rounded,
            'PNG (bu sayfa)',
            _exportPng,
            color: const Color(0xFF059669),
          ),
          _actionTile(
            Icons.picture_as_pdf_rounded,
            'PDF (tüm sayfalar)',
            _exportPdf,
            color: const Color(0xFF059669),
          ),
        ]),
        const SizedBox(height: 10),
        _title('Görünüm'),
        _tileGrid([
          _actionGlyphTile(
            _fsActive ? _WbGlyphKind.fullscreenExit : _WbGlyphKind.fullscreen,
            _fsActive ? 'Tam Ekrandan Çık' : 'Tam Ekran (F11)',
            _toggleFullscreen,
            color: _fsActive
                ? const Color(0xFF2563EB)
                : const Color(0xFF475569),
          ),
          _actionTile(
            Icons.center_focus_strong_rounded,
            'Görünümü Sıfırla',
            _resetView,
            color: const Color(0xFF475569),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          'İpucu: İki parmakla kaydırıp yakınlaştırabilir; fare kullanıyorsanız tekerlekle yakınlaştırıp sağ tuşla sürükleyebilirsiniz.',
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

/// Alt çubuk / panelin üstündeki alanların tahtaya dokunuş göndermesini engeller.
class _Block extends StatelessWidget {
  const _Block({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (_) {},
    child: child,
  );
}

/// Kütüphane küçük resmi: şekli alana orantılı sığdırır.
class _ArtThumbPainter extends CustomPainter {
  _ArtThumbPainter(this.item);
  final WbArtItem item;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final s = math.min(size.width / item.w, size.height / item.h);
    canvas.save();
    canvas.translate(
      (size.width - item.w * s) / 2,
      (size.height - item.h * s) / 2,
    );
    canvas.scale(s, s);
    canvas.clipRect(Rect.fromLTWH(0, 0, item.w, item.h).inflate(2));
    item.draw(
      canvas,
      WbArtPen(const Color(0xFF1E293B), math.max(1.0, 1.4 / s)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ArtThumbPainter old) => old.item != item;
}

enum _WbGlyphKind {
  highlighter,
  laser,
  hand,
  undo,
  redo,
  addPage,
  fullscreen,
  fullscreenExit,
}

/// Font önbelleğinden bağımsız, her zaman net görünen vektörel araç simgeleri.
class _WbGlyphPainter extends CustomPainter {
  const _WbGlyphPainter(this.kind, this.color);
  final _WbGlyphKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final sw = math.max(1.9, w * 0.09);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    Offset p(double x, double y) => Offset(x * w, y * h);

    switch (kind) {
      case _WbGlyphKind.highlighter:
        // Alt vurgulama şeridi
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(w * 0.14, h * 0.80, w * 0.86, h * 0.92),
            Radius.circular(w * 0.06),
          ),
          Paint()
            ..color = color.withValues(alpha: 0.45)
            ..style = PaintingStyle.fill,
        );
        // Kesik uçlu fosforlu kalem gövdesi
        final body = Path()
          ..moveTo(w * 0.62, h * 0.14)
          ..lineTo(w * 0.84, h * 0.36)
          ..lineTo(w * 0.46, h * 0.72)
          ..lineTo(w * 0.26, h * 0.52)
          ..close();
        canvas.drawPath(body, stroke);
        // Kalem ucu
        final tip = Path()
          ..moveTo(w * 0.26, h * 0.52)
          ..lineTo(w * 0.46, h * 0.72)
          ..lineTo(w * 0.28, h * 0.74)
          ..lineTo(w * 0.20, h * 0.66)
          ..close();
        canvas.drawPath(tip, fill);
        canvas.drawLine(p(0.52, 0.24), p(0.74, 0.46), stroke);
        break;

      case _WbGlyphKind.laser:
        final c = Offset(w * 0.5, h * 0.5);
        canvas.drawCircle(c, w * 0.15, fill);
        for (int i = 0; i < 8; i++) {
          final ang = i * math.pi / 4;
          final r1 = w * 0.25;
          final r2 = (i.isEven ? 0.44 : 0.37) * w;
          canvas.drawLine(
            c + Offset(math.cos(ang) * r1, math.sin(ang) * r1),
            c + Offset(math.cos(ang) * r2, math.sin(ang) * r2),
            stroke,
          );
        }
        break;

      case _WbGlyphKind.hand:
        // 4 yönlü kaydırma oku
        canvas.drawLine(p(0.14, 0.50), p(0.86, 0.50), stroke);
        canvas.drawLine(p(0.50, 0.14), p(0.50, 0.86), stroke);
        void head(Offset a, Offset tipPt, Offset b) {
          canvas.drawPath(
            Path()
              ..moveTo(a.dx, a.dy)
              ..lineTo(tipPt.dx, tipPt.dy)
              ..lineTo(b.dx, b.dy),
            stroke,
          );
        }
        head(p(0.38, 0.26), p(0.50, 0.13), p(0.62, 0.26));
        head(p(0.38, 0.74), p(0.50, 0.87), p(0.62, 0.74));
        head(p(0.26, 0.38), p(0.13, 0.50), p(0.26, 0.62));
        head(p(0.74, 0.38), p(0.87, 0.50), p(0.74, 0.62));
        break;

      case _WbGlyphKind.undo:
        final path = Path()
          ..moveTo(w * 0.22, h * 0.40)
          ..lineTo(w * 0.60, h * 0.40)
          ..arcToPoint(
            p(0.60, 0.78),
            radius: Radius.circular(w * 0.19),
            clockwise: true,
          )
          ..lineTo(w * 0.34, h * 0.78);
        canvas.drawPath(path, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.38, h * 0.24)
            ..lineTo(w * 0.20, h * 0.40)
            ..lineTo(w * 0.38, h * 0.56),
          stroke,
        );
        break;

      case _WbGlyphKind.redo:
        final path = Path()
          ..moveTo(w * 0.78, h * 0.40)
          ..lineTo(w * 0.40, h * 0.40)
          ..arcToPoint(
            p(0.40, 0.78),
            radius: Radius.circular(w * 0.19),
            clockwise: false,
          )
          ..lineTo(w * 0.66, h * 0.78);
        canvas.drawPath(path, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.62, h * 0.24)
            ..lineTo(w * 0.80, h * 0.40)
            ..lineTo(w * 0.62, h * 0.56),
          stroke,
        );
        break;

      case _WbGlyphKind.addPage:
        final pg = Path()
          ..moveTo(w * 0.22, h * 0.14)
          ..lineTo(w * 0.60, h * 0.14)
          ..lineTo(w * 0.78, h * 0.32)
          ..lineTo(w * 0.78, h * 0.86)
          ..lineTo(w * 0.22, h * 0.86)
          ..close();
        canvas.drawPath(pg, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.58, h * 0.14)
            ..lineTo(w * 0.58, h * 0.33)
            ..lineTo(w * 0.78, h * 0.33),
          stroke,
        );
        canvas.drawLine(p(0.50, 0.46), p(0.50, 0.72), stroke);
        canvas.drawLine(p(0.37, 0.59), p(0.63, 0.59), stroke);
        break;

      case _WbGlyphKind.fullscreen:
        void corner(double x, double y, double dx, double dy) {
          canvas.drawPath(
            Path()
              ..moveTo(w * (x + dx), h * y)
              ..lineTo(w * x, h * y)
              ..lineTo(w * x, h * (y + dy)),
            stroke,
          );
        }
        corner(0.16, 0.16, 0.22, 0.22);
        corner(0.84, 0.16, -0.22, 0.22);
        corner(0.16, 0.84, 0.22, -0.22);
        corner(0.84, 0.84, -0.22, -0.22);
        break;

      case _WbGlyphKind.fullscreenExit:
        void inCorner(double x, double y, double dx, double dy) {
          canvas.drawPath(
            Path()
              ..moveTo(w * (x + dx), h * y)
              ..lineTo(w * x, h * y)
              ..lineTo(w * x, h * (y + dy)),
            stroke,
          );
        }
        inCorner(0.36, 0.36, -0.20, -0.20);
        inCorner(0.64, 0.36, 0.20, -0.20);
        inCorner(0.36, 0.64, -0.20, 0.20);
        inCorner(0.64, 0.64, 0.20, 0.20);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _WbGlyphPainter old) =>
      old.kind != kind || old.color != color;
}

class _ShapeIconPainter extends CustomPainter {
  _ShapeIconPainter(this.kind);
  final WbShapeKind kind;

  @override
  void paint(Canvas canvas, Size s) {
    final pad = s.width * 0.2;
    final linear =
        kind == WbShapeKind.line ||
        kind == WbShapeKind.arrow ||
        kind == WbShapeKind.doubleArrow;
    final shape = WbShape(
      0,
      kind: kind,
      p1: linear ? Offset(pad, s.height - pad) : Offset(pad, pad),
      p2: linear
          ? Offset(s.width - pad, pad)
          : Offset(s.width - pad, s.height - pad),
      color: const Color(0xFF1E293B),
      width: 2.4,
    );
    shape.paint(canvas);
  }

  @override
  bool shouldRepaint(covariant _ShapeIconPainter old) => old.kind != kind;
}
