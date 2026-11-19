import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'whiteboard_art.dart';

/// Akıllı beyaz tahta araçları.
enum WbTool { pen, highlighter, eraser, select, laser, hand, shape, text }

/// Hazır geometrik şekiller.
enum WbShapeKind {
  line,
  arrow,
  doubleArrow,
  rect,
  roundRect,
  ellipse,
  triangle,
  rightTriangle,
  diamond,
  pentagon,
  hexagon,
  star,
  trapezoid,
  parallelogram,
  cross,
  heart,
}

/// Tahta arka planları.
enum WbBackground { white, black, green, grid, lined, dotted, graph, axes }

/// Hazır diyagramlar.
enum WbDiagramType { table, axes, numberLine }

double wbDistToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) return (p - a).distance;
  var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2;
  t = t.clamp(0.0, 1.0);
  final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
  return (p - proj).distance;
}

Path wbDashPath(Path source, {double dash = 10, double gap = 7}) {
  final out = Path();
  for (final m in source.computeMetrics()) {
    double d = 0;
    while (d < m.length) {
      out.addPath(m.extractPath(d, math.min(d + dash, m.length)), Offset.zero);
      d += dash + gap;
    }
  }
  return out;
}

Path _smoothPath(List<Offset> pts) {
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  if (pts.length == 1) {
    path.lineTo(pts.first.dx + 0.01, pts.first.dy);
  } else if (pts.length == 2) {
    path.lineTo(pts[1].dx, pts[1].dy);
  } else {
    for (int i = 1; i < pts.length - 1; i++) {
      final mid = (pts[i] + pts[i + 1]) / 2;
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
  }
  return path;
}

void _arrowHead(Canvas c, Offset from, Offset to, Color color, double size) {
  final ang = math.atan2(to.dy - from.dy, to.dx - from.dx);
  final p1 = to - Offset(math.cos(ang - 0.45), math.sin(ang - 0.45)) * size;
  final p2 = to - Offset(math.cos(ang + 0.45), math.sin(ang + 0.45)) * size;
  final path = Path()
    ..moveTo(to.dx, to.dy)
    ..lineTo(p1.dx, p1.dy)
    ..lineTo(p2.dx, p2.dy)
    ..close();
  c.drawPath(
    path,
    Paint()
      ..color = color
      ..style = PaintingStyle.fill,
  );
}

TextPainter wbTextPainter(
  String text,
  double size,
  Color color, {
  bool bold = false,
  double maxWidth = 1600,
}) {
  return TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
        height: 1.2,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);
}

/// Tahtadaki tüm nesnelerin ortak tabanı.
abstract class WbObject {
  WbObject(this.id);
  final int id;

  Rect get bounds;
  bool get uniformScale => true;
  Color get color;
  void setColor(Color c);
  bool hitTest(Offset p, double tol);
  void translate(Offset d);
  void scaleAbout(Offset a, double sx, double sy);
  void paint(Canvas canvas);
  WbObject clone(int newId);
}

/// Serbest çizim (kalem / fosforlu kalem).
class WbStroke extends WbObject {
  WbStroke(
    super.id, {
    required this.points,
    required Color color,
    required this.width,
    this.highlighter = false,
  }) : _color = color;

  List<Offset> points;
  Color _color;
  double width;
  final bool highlighter;
  Rect? _bounds;

  @override
  Color get color => _color;

  @override
  void setColor(Color c) => _color = c;

  @override
  Rect get bounds {
    if (_bounds != null) return _bounds!;
    double minX = points.first.dx, maxX = minX;
    double minY = points.first.dy, maxY = minY;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    _bounds = Rect.fromLTRB(minX, minY, maxX, maxY).inflate(width / 2 + 2);
    return _bounds!;
  }

  void addPoint(Offset p) {
    points.add(p);
    _bounds = null;
  }

  @override
  bool hitTest(Offset p, double tol) {
    if (!bounds.inflate(tol).contains(p)) return false;
    final r = tol + width / 2;
    if (points.length == 1) return (points.first - p).distance <= r;
    for (int i = 0; i < points.length - 1; i++) {
      if (wbDistToSegment(p, points[i], points[i + 1]) <= r) return true;
    }
    return false;
  }

  @override
  void translate(Offset d) {
    points = points.map((e) => e + d).toList();
    _bounds = null;
  }

  @override
  void scaleAbout(Offset a, double sx, double sy) {
    points = points
        .map(
          (e) => Offset(a.dx + (e.dx - a.dx) * sx, a.dy + (e.dy - a.dy) * sy),
        )
        .toList();
    width = (width * (sx.abs() + sy.abs()) / 2).clamp(1.0, 80.0);
    _bounds = null;
  }

  @override
  void paint(Canvas canvas) {
    final paint = Paint()
      ..color = highlighter ? _color.withValues(alpha: 0.35) : _color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = highlighter ? StrokeCap.butt : StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    if (points.length == 1 && !highlighter) {
      canvas.drawCircle(points.first, width / 2, Paint()..color = _color);
      return;
    }
    canvas.drawPath(_smoothPath(points), paint);
  }

  @override
  WbObject clone(int newId) => WbStroke(
    newId,
    points: List<Offset>.from(points),
    color: _color,
    width: width,
    highlighter: highlighter,
  );
}

/// Çizgi, ok ve geometrik şekiller.
class WbShape extends WbObject {
  WbShape(
    super.id, {
    required this.kind,
    required this.p1,
    required this.p2,
    required Color color,
    required this.width,
    this.fill = false,
    this.dashed = false,
  }) : _color = color;

  final WbShapeKind kind;
  Offset p1;
  Offset p2;
  Color _color;
  double width;
  final bool fill;
  final bool dashed;

  bool get isLinear =>
      kind == WbShapeKind.line ||
      kind == WbShapeKind.arrow ||
      kind == WbShapeKind.doubleArrow;

  Rect get rect => Rect.fromPoints(p1, p2);

  @override
  bool get uniformScale => false;

  @override
  Color get color => _color;

  @override
  void setColor(Color c) => _color = c;

  @override
  Rect get bounds => isLinear
      ? Rect.fromPoints(p1, p2).inflate(width + 10)
      : rect.inflate(width / 2 + 2);

  Path buildPath() {
    final r = rect;
    final l = r.left, t = r.top, rt = r.right, b = r.bottom;
    final w = r.width, h = r.height;
    final cx = r.center.dx, cy = r.center.dy;
    final path = Path();
    Path poly(List<Offset> pts) {
      final p = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final e in pts.skip(1)) {
        p.lineTo(e.dx, e.dy);
      }
      return p..close();
    }

    switch (kind) {
      case WbShapeKind.line:
      case WbShapeKind.arrow:
      case WbShapeKind.doubleArrow:
        path
          ..moveTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy);
        return path;
      case WbShapeKind.rect:
        return path..addRect(r);
      case WbShapeKind.roundRect:
        return path..addRRect(
          RRect.fromRectAndRadius(r, Radius.circular(math.min(w, h) * 0.18)),
        );
      case WbShapeKind.ellipse:
        return path..addOval(r);
      case WbShapeKind.triangle:
        return poly([Offset(cx, t), Offset(rt, b), Offset(l, b)]);
      case WbShapeKind.rightTriangle:
        return poly([Offset(l, t), Offset(l, b), Offset(rt, b)]);
      case WbShapeKind.diamond:
        return poly([
          Offset(cx, t),
          Offset(rt, cy),
          Offset(cx, b),
          Offset(l, cy),
        ]);
      case WbShapeKind.pentagon:
      case WbShapeKind.hexagon:
        final n = kind == WbShapeKind.pentagon ? 5 : 6;
        final start = kind == WbShapeKind.pentagon ? -math.pi / 2 : 0.0;
        return poly(
          List.generate(n, (i) {
            final a = start + i * 2 * math.pi / n;
            return Offset(cx + w / 2 * math.cos(a), cy + h / 2 * math.sin(a));
          }),
        );
      case WbShapeKind.star:
        return poly(
          List.generate(10, (i) {
            final a = -math.pi / 2 + i * math.pi / 5;
            final k = i.isEven ? 1.0 : 0.42;
            return Offset(
              cx + w / 2 * k * math.cos(a),
              cy + h / 2 * k * math.sin(a),
            );
          }),
        );
      case WbShapeKind.trapezoid:
        return poly([
          Offset(l + w * 0.2, t),
          Offset(rt - w * 0.2, t),
          Offset(rt, b),
          Offset(l, b),
        ]);
      case WbShapeKind.parallelogram:
        return poly([
          Offset(l + w * 0.25, t),
          Offset(rt, t),
          Offset(rt - w * 0.25, b),
          Offset(l, b),
        ]);
      case WbShapeKind.cross:
        final a = w / 3, bb = h / 3;
        return poly([
          Offset(l + a, t),
          Offset(l + 2 * a, t),
          Offset(l + 2 * a, t + bb),
          Offset(rt, t + bb),
          Offset(rt, t + 2 * bb),
          Offset(l + 2 * a, t + 2 * bb),
          Offset(l + 2 * a, b),
          Offset(l + a, b),
          Offset(l + a, t + 2 * bb),
          Offset(l, t + 2 * bb),
          Offset(l, t + bb),
          Offset(l + a, t + bb),
        ]);
      case WbShapeKind.heart:
        path.moveTo(cx, b);
        path.cubicTo(
          l - w * 0.1,
          t + h * 0.55,
          l + w * 0.05,
          t - h * 0.05,
          cx,
          t + h * 0.3,
        );
        path.cubicTo(
          rt - w * 0.05,
          t - h * 0.05,
          rt + w * 0.1,
          t + h * 0.55,
          cx,
          b,
        );
        return path;
    }
  }

  @override
  bool hitTest(Offset p, double tol) {
    if (!bounds.inflate(tol).contains(p)) return false;
    if (isLinear) return wbDistToSegment(p, p1, p2) <= tol + width;
    final path = buildPath();
    if (fill && path.contains(p)) return true;
    final r = tol + width / 2;
    for (final m in path.computeMetrics()) {
      final step = math.max(4.0, m.length / 240);
      for (double d = 0; d <= m.length; d += step) {
        final pos = m.getTangentForOffset(d)?.position;
        if (pos != null && (pos - p).distance <= r) return true;
      }
    }
    return false;
  }

  @override
  void translate(Offset d) {
    p1 += d;
    p2 += d;
  }

  @override
  void scaleAbout(Offset a, double sx, double sy) {
    Offset s(Offset e) =>
        Offset(a.dx + (e.dx - a.dx) * sx, a.dy + (e.dy - a.dy) * sy);
    p1 = s(p1);
    p2 = s(p2);
  }

  @override
  void paint(Canvas canvas) {
    final stroke = Paint()
      ..color = _color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    var path = buildPath();
    if (!isLinear && fill) {
      canvas.drawPath(
        path,
        Paint()
          ..color = _color.withValues(alpha: 0.22)
          ..style = PaintingStyle.fill,
      );
    }
    if (dashed)
      path = wbDashPath(path, dash: width * 3 + 4, gap: width * 2 + 4);
    canvas.drawPath(path, stroke);
    if (kind == WbShapeKind.arrow || kind == WbShapeKind.doubleArrow) {
      _arrowHead(canvas, p1, p2, _color, 10 + width * 2.2);
    }
    if (kind == WbShapeKind.doubleArrow) {
      _arrowHead(canvas, p2, p1, _color, 10 + width * 2.2);
    }
  }

  @override
  WbObject clone(int newId) => WbShape(
    newId,
    kind: kind,
    p1: p1,
    p2: p2,
    color: _color,
    width: width,
    fill: fill,
    dashed: dashed,
  );
}

/// Metin kutusu.
class WbText extends WbObject {
  WbText(
    super.id, {
    required this.text,
    required this.pos,
    required this.fontSize,
    required Color color,
    this.bold = false,
  }) : _color = color;

  String text;
  Offset pos;
  double fontSize;
  Color _color;
  bool bold;

  @override
  Color get color => _color;

  @override
  void setColor(Color c) => _color = c;

  @override
  Rect get bounds {
    final tp = wbTextPainter(text, fontSize, _color, bold: bold);
    return pos & Size(tp.width, tp.height);
  }

  @override
  bool hitTest(Offset p, double tol) => bounds.inflate(tol).contains(p);

  @override
  void translate(Offset d) => pos += d;

  @override
  void scaleAbout(Offset a, double sx, double sy) {
    pos = Offset(a.dx + (pos.dx - a.dx) * sx, a.dy + (pos.dy - a.dy) * sy);
    fontSize = (fontSize * (sx.abs() + sy.abs()) / 2).clamp(8.0, 400.0);
  }

  @override
  void paint(Canvas canvas) {
    wbTextPainter(text, fontSize, _color, bold: bold).paint(canvas, pos);
  }

  @override
  WbObject clone(int newId) => WbText(
    newId,
    text: text,
    pos: pos,
    fontSize: fontSize,
    color: _color,
    bold: bold,
  );
}

/// Eklenen resim.
class WbImage extends WbObject {
  WbImage(super.id, {required this.image, required this.rect});
  final ui.Image image;
  Rect rect;

  @override
  Color get color => Colors.white;

  @override
  void setColor(Color c) {}

  @override
  Rect get bounds => rect;

  @override
  bool hitTest(Offset p, double tol) => rect.inflate(tol).contains(p);

  @override
  void translate(Offset d) => rect = rect.shift(d);

  @override
  void scaleAbout(Offset a, double sx, double sy) {
    rect = Rect.fromLTRB(
      a.dx + (rect.left - a.dx) * sx,
      a.dy + (rect.top - a.dy) * sy,
      a.dx + (rect.right - a.dx) * sx,
      a.dy + (rect.bottom - a.dy) * sy,
    );
  }

  @override
  void paint(Canvas canvas) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  WbObject clone(int newId) => WbImage(newId, image: image, rect: rect);
}

/// Tablo, koordinat düzlemi, sayı doğrusu gibi hazır diyagramlar.
class WbDiagram extends WbObject {
  WbDiagram(
    super.id, {
    required this.type,
    required this.rect,
    required Color color,
    required this.width,
    this.rows = 4,
    this.cols = 4,
  }) : _color = color;

  final WbDiagramType type;
  Rect rect;
  Color _color;
  double width;
  final int rows;
  final int cols;

  @override
  bool get uniformScale => false;

  @override
  Color get color => _color;

  @override
  void setColor(Color c) => _color = c;

  @override
  Rect get bounds => rect.inflate(width + 6);

  List<List<Offset>> _segments() {
    final r = rect;
    switch (type) {
      case WbDiagramType.table:
        final segs = <List<Offset>>[
          [r.topLeft, r.topRight],
          [r.topRight, r.bottomRight],
          [r.bottomRight, r.bottomLeft],
          [r.bottomLeft, r.topLeft],
        ];
        for (int i = 1; i < cols; i++) {
          final x = r.left + r.width * i / cols;
          segs.add([Offset(x, r.top), Offset(x, r.bottom)]);
        }
        for (int i = 1; i < rows; i++) {
          final y = r.top + r.height * i / rows;
          segs.add([Offset(r.left, y), Offset(r.right, y)]);
        }
        return segs;
      case WbDiagramType.axes:
        return [
          [Offset(r.left, r.center.dy), Offset(r.right, r.center.dy)],
          [Offset(r.center.dx, r.bottom), Offset(r.center.dx, r.top)],
        ];
      case WbDiagramType.numberLine:
        return [
          [Offset(r.left, r.center.dy), Offset(r.right, r.center.dy)],
        ];
    }
  }

  @override
  bool hitTest(Offset p, double tol) {
    if (!bounds.inflate(tol).contains(p)) return false;
    for (final s in _segments()) {
      if (wbDistToSegment(p, s[0], s[1]) <= tol + width) return true;
    }
    return false;
  }

  @override
  void translate(Offset d) => rect = rect.shift(d);

  @override
  void scaleAbout(Offset a, double sx, double sy) {
    rect = Rect.fromLTRB(
      a.dx + (rect.left - a.dx) * sx,
      a.dy + (rect.top - a.dy) * sy,
      a.dx + (rect.right - a.dx) * sx,
      a.dy + (rect.bottom - a.dy) * sy,
    );
  }

  @override
  void paint(Canvas canvas) {
    final p = Paint()
      ..color = _color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final r = rect;
    switch (type) {
      case WbDiagramType.table:
        for (final s in _segments()) {
          canvas.drawLine(s[0], s[1], p);
        }
        break;
      case WbDiagramType.axes:
        final cx = r.center.dx, cy = r.center.dy;
        canvas.drawLine(Offset(r.left, cy), Offset(r.right, cy), p);
        canvas.drawLine(Offset(cx, r.bottom), Offset(cx, r.top), p);
        _arrowHead(
          canvas,
          Offset(r.right - 20, cy),
          Offset(r.right, cy),
          _color,
          12,
        );
        _arrowHead(
          canvas,
          Offset(cx, r.top + 20),
          Offset(cx, r.top),
          _color,
          12,
        );
        final n = cols;
        final ux = (r.width / 2 - 18) / n;
        final uy = (r.height / 2 - 18) / n;
        final step = n > 12 ? 2 : 1;
        for (int i = -n; i <= n; i += step) {
          if (i == 0) continue;
          canvas.drawLine(
            Offset(cx + i * ux, cy - 5),
            Offset(cx + i * ux, cy + 5),
            p,
          );
          canvas.drawLine(
            Offset(cx - 5, cy - i * uy),
            Offset(cx + 5, cy - i * uy),
            p,
          );
          final tx = wbTextPainter('$i', 12, _color);
          tx.paint(canvas, Offset(cx + i * ux - tx.width / 2, cy + 7));
          final ty = wbTextPainter('$i', 12, _color);
          ty.paint(
            canvas,
            Offset(cx - ty.width - 8, cy - i * uy - ty.height / 2),
          );
        }
        wbTextPainter(
          'x',
          15,
          _color,
          bold: true,
        ).paint(canvas, Offset(r.right - 12, cy + 8));
        wbTextPainter(
          'y',
          15,
          _color,
          bold: true,
        ).paint(canvas, Offset(cx + 8, r.top));
        wbTextPainter('O', 12, _color).paint(canvas, Offset(cx - 14, cy + 6));
        break;
      case WbDiagramType.numberLine:
        final cy = r.center.dy;
        canvas.drawLine(Offset(r.left, cy), Offset(r.right, cy), p);
        _arrowHead(
          canvas,
          Offset(r.left + 20, cy),
          Offset(r.left, cy),
          _color,
          12,
        );
        _arrowHead(
          canvas,
          Offset(r.right - 20, cy),
          Offset(r.right, cy),
          _color,
          12,
        );
        final n = cols;
        final u = (r.width / 2 - 24) / n;
        for (int i = -n; i <= n; i++) {
          final x = r.center.dx + i * u;
          final h = i == 0 ? 11.0 : 7.0;
          canvas.drawLine(Offset(x, cy - h), Offset(x, cy + h), p);
          final tp = wbTextPainter('$i', 13, _color, bold: i == 0);
          tp.paint(canvas, Offset(x - tp.width / 2, cy + 12));
        }
        break;
    }
  }

  @override
  WbObject clone(int newId) => WbDiagram(
    newId,
    type: type,
    rect: rect,
    color: _color,
    width: width,
    rows: rows,
    cols: cols,
  );
}

/// Şekil kütüphanesinden eklenen hazır çizim (harita, düzenek, kaldıraç vb.).
class WbClipArt extends WbObject {
  WbClipArt(
    super.id, {
    required this.artId,
    required this.rect,
    required Color color,
    required this.width,
  }) : _color = color;

  final String artId;
  Rect rect;
  Color _color;
  double width;

  @override
  Color get color => _color;

  @override
  void setColor(Color c) => _color = c;

  @override
  Rect get bounds => rect.inflate(4);

  @override
  bool hitTest(Offset p, double tol) => rect.inflate(tol).contains(p);

  @override
  void translate(Offset d) => rect = rect.shift(d);

  @override
  void scaleAbout(Offset a, double sx, double sy) {
    rect = Rect.fromLTRB(
      a.dx + (rect.left - a.dx) * sx,
      a.dy + (rect.top - a.dy) * sy,
      a.dx + (rect.right - a.dx) * sx,
      a.dy + (rect.bottom - a.dy) * sy,
    );
  }

  @override
  void paint(Canvas canvas) {
    final item = wbArtById(artId);
    if (item == null) return;
    final sx = rect.width.abs() / item.w;
    final sy = rect.height.abs() / item.h;
    final s = math.min(sx, sy);
    if (s <= 0) return;
    canvas.save();
    canvas.translate(
      rect.left + (rect.width.abs() - item.w * s) / 2,
      rect.top + (rect.height.abs() - item.h * s) / 2,
    );
    canvas.scale(s, s);
    item.draw(canvas, WbArtPen(_color, math.max(0.8, width / s)));
    canvas.restore();
  }

  @override
  WbObject clone(int newId) =>
      WbClipArt(newId, artId: artId, rect: rect, color: _color, width: width);
}

/// Tahtanın bir sayfası (nesneler + geri al / ileri al geçmişi + görünüm).
class WbPage {
  WbPage({this.bg = WbBackground.white});
  List<WbObject> objects = [];
  final List<List<WbObject>> undo = [];
  final List<List<WbObject>> redo = [];
  WbBackground bg;
  double scale = 1;
  Offset offset = Offset.zero;

  /// Dosyadan (PDF / resim) gelen sayfaların kendi kağıt boyutu ve arka plan görüntüsü.
  /// null ise sayfa sonsuz tahtadır.
  Size? paperSize;
  ui.Image? paperImage;
  String? paperName;

  bool get hasPaper => paperSize != null;
}
