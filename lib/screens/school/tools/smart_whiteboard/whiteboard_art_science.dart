import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'whiteboard_art_core.dart';

typedef _C = WbArtColors;

const double _pi = math.pi;

// ───────────────────────── Yardımcılar ─────────────────────────

void _t(
  Canvas c,
  WbArtPen p,
  String s,
  double x,
  double y, {
  double size = 9,
  Color? col,
  bool bold = false,
  String a = 'center',
}) => p.text(c, s, Offset(x, y), size: size, c: col, bold: bold, anchor: a);

void _el(
  Canvas c,
  WbArtPen p,
  double cx,
  double cy,
  double rx,
  double ry,
  Color col, [
  double a = .3,
]) {
  final r = Rect.fromCenter(
    center: Offset(cx, cy),
    width: rx * 2,
    height: ry * 2,
  );
  c.drawOval(r, p.fill(col, a));
  c.drawOval(r, p.line);
}

void _ci(
  Canvas c,
  WbArtPen p,
  double cx,
  double cy,
  double r,
  Color col, [
  double a = .3,
]) => _el(c, p, cx, cy, r, r, col, a);

void _dot(
  Canvas c,
  WbArtPen p,
  double x,
  double y,
  double r,
  Color col, [
  double a = 1,
]) => c.drawCircle(Offset(x, y), r, p.fill(col, a));

void _rr(
  Canvas c,
  WbArtPen p,
  double l,
  double t,
  double w,
  double h,
  double rad,
  Color col, [
  double a = .3,
]) {
  final r = RRect.fromRectAndRadius(
    Rect.fromLTWH(l, t, w, h),
    Radius.circular(rad),
  );
  c.drawRRect(r, p.fill(col, a));
  c.drawRRect(r, p.line);
}

void _pg(Canvas c, WbArtPen p, List<Offset> pts, Color col, [double a = .3]) {
  final path = WbArtPen.poly(pts);
  c.drawPath(path, p.fill(col, a));
  c.drawPath(path, p.line);
}

void _pf(
  Canvas c,
  WbArtPen p,
  Path path,
  Color col, [
  double a = .3,
  bool stroke = true,
]) {
  c.drawPath(path, p.fill(col, a));
  if (stroke) c.drawPath(path, p.line);
}

void _ln(Canvas c, Paint paint, double x1, double y1, double x2, double y2) =>
    c.drawLine(Offset(x1, y1), Offset(x2, y2), paint);

void _ar(
  Canvas c,
  WbArtPen p,
  double x1,
  double y1,
  double x2,
  double y2, [
  Color? col,
  double size = 6,
]) => p.arrow(c, Offset(x1, y1), Offset(x2, y2), c: col, size: size);

/// Çizgili etiket: (px,py) şekil üzerindeki nokta, (tx,ty) metin noktası.
void _ld(
  Canvas c,
  WbArtPen p,
  String s,
  double px,
  double py,
  double tx,
  double ty, {
  String a = 'left',
  double size = 8.5,
}) {
  c.drawLine(Offset(px, py), Offset(tx, ty), p.thin(.4));
  c.drawCircle(Offset(px, py), 1.3, p.solid);
  _t(
    c,
    p,
    s,
    tx + (a == 'left' ? 2 : (a == 'right' ? -2 : 0)),
    ty,
    size: size,
    a: a,
  );
}

void _rot(Canvas c, double cx, double cy, double ang, VoidCallback f) {
  c.save();
  c.translate(cx, cy);
  c.rotate(ang);
  c.translate(-cx, -cy);
  f();
  c.restore();
}

void _rel(
  Canvas c,
  WbArtPen p,
  double cx,
  double cy,
  double rx,
  double ry,
  double ang,
  Color col, [
  double a = .3,
]) => _rot(c, cx, cy, ang, () => _el(c, p, cx, cy, rx, ry, col, a));

void _carc(
  Canvas c,
  WbArtPen p,
  double cx,
  double cy,
  double r,
  double s,
  double sw,
  Color col, {
  double w = 1.4,
}) {
  c.drawPath(WbArtPen.arc(Offset(cx, cy), r, s, sw), p.stroke(col, w));
  final e = (s + sw) * _pi / 180;
  final dir = sw > 0 ? 1.0 : -1.0;
  final pt = Offset(cx + r * math.cos(e), cy + r * math.sin(e));
  final tn = Offset(-math.sin(e) * dir, math.cos(e) * dir);
  p.arrow(c, pt - tn * 3, pt + tn * 3, c: col, size: 7, line: false);
}

Path _union(List<Path> parts) {
  Path r = parts.first;
  for (int i = 1; i < parts.length; i++) {
    r = Path.combine(PathOperation.union, r, parts[i]);
  }
  return r;
}

void _cloud(
  Canvas c,
  WbArtPen p,
  double cx,
  double cy,
  double s,
  Color col, [
  double a = .3,
]) {
  final path = _union([
    Path()..addOval(
      Rect.fromCircle(center: Offset(cx - 14 * s, cy + 4 * s), radius: 10 * s),
    ),
    Path()..addOval(
      Rect.fromCircle(center: Offset(cx, cy - 4 * s), radius: 15 * s),
    ),
    Path()..addOval(
      Rect.fromCircle(center: Offset(cx + 15 * s, cy + 3 * s), radius: 11 * s),
    ),
    Path()..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(cx - 22 * s, cy + 2 * s, cx + 25 * s, cy + 14 * s),
        Radius.circular(6 * s),
      ),
    ),
  ]);
  c.drawPath(path, p.fill(col, a));
  c.drawPath(path, p.line);
}

void _sun(
  Canvas c,
  WbArtPen p,
  double cx,
  double cy,
  double r, {
  bool rays = true,
}) {
  if (rays) {
    for (int i = 0; i < 12; i++) {
      final a = i * _pi / 6;
      _ln(
        c,
        p.stroke(_C.orange, .8),
        cx + (r + 3) * math.cos(a),
        cy + (r + 3) * math.sin(a),
        cx + (r + 8) * math.cos(a),
        cy + (r + 8) * math.sin(a),
      );
    }
  }
  _ci(c, p, cx, cy, r, _C.yellow, .6);
}

void _star(Canvas c, WbArtPen p, double cx, double cy, double r, Color col) {
  final pts = <Offset>[];
  for (int i = 0; i < 10; i++) {
    final rr = i.isEven ? r : r * .42;
    final a = -_pi / 2 + i * _pi / 5;
    pts.add(Offset(cx + rr * math.cos(a), cy + rr * math.sin(a)));
  }
  c.drawPath(WbArtPen.poly(pts), p.fill(col, .9));
}

void _mito(Canvas c, WbArtPen p, double cx, double cy, double s, double ang) {
  _rot(c, cx, cy, ang, () {
    _el(c, p, cx, cy, 14 * s, 7 * s, _C.orange, .4);
    final path = Path()
      ..moveTo(cx - 9 * s, cy)
      ..lineTo(cx - 6 * s, cy - 5 * s)
      ..lineTo(cx - 3 * s, cy + 4 * s)
      ..lineTo(cx, cy - 5 * s)
      ..lineTo(cx + 3 * s, cy + 4 * s)
      ..lineTo(cx + 6 * s, cy - 4 * s)
      ..lineTo(cx + 9 * s, cy);
    c.drawPath(path, p.thin(.5));
  });
}

void _chrom(
  Canvas c,
  WbArtPen p,
  double x,
  double y,
  double s,
  double ang,
  Color col,
) {
  _rot(c, x, y, ang, () {
    final pa = p.stroke(col, 1.6);
    _ln(c, pa, x - 5 * s, y - 6 * s, x + 5 * s, y + 6 * s);
    _ln(c, pa, x + 5 * s, y - 6 * s, x - 5 * s, y + 6 * s);
  });
}

// ───────────────────────── BİYOLOJİ ─────────────────────────

void _animalCell(Canvas c, WbArtPen p) {
  _el(c, p, 160, 95, 100, 78, _C.pink, .15);
  _el(c, p, 140, 92, 30, 26, _C.purple, .3);
  _ci(c, p, 136, 90, 7, _C.purple, .6);
  final er = Path()
    ..moveTo(98, 70)
    ..cubicTo(86, 78, 108, 84, 92, 92)
    ..cubicTo(78, 100, 106, 106, 92, 116)
    ..cubicTo(82, 122, 100, 128, 94, 134);
  c.drawPath(er, p.stroke(_C.teal, 1.2));
  _mito(c, p, 210, 62, 1, -.4);
  _mito(c, p, 120, 142, 1, .3);
  for (int i = 0; i < 3; i++) {
    c.drawPath(
      WbArtPen.arc(Offset(205, 118 + i * 6.0), 18 - i * 2.0, 200, 140),
      p.stroke(_C.yellow, 1.3),
    );
  }
  _ci(c, p, 170, 140, 6, _C.red, .4);
  for (final d in [
    const Offset(85, 118),
    const Offset(80, 100),
    const Offset(100, 50),
    const Offset(180, 58),
    const Offset(150, 60),
  ]) {
    _dot(c, p, d.dx, d.dy, 1.6, p.color);
  }
  _rr(c, p, 98, 38, 3, 9, 1, _C.blue, .5);
  _rr(c, p, 103, 44, 9, 3, 1, _C.blue, .5);
  _t(c, p, 'Sitoplazma', 160, 170, size: 8, col: _C.gray);
  _ld(c, p, 'Sentrozom', 104, 44, 44, 24, a: 'right');
  _ld(c, p, 'Çekirdek', 112, 82, 44, 62, a: 'right');
  _ld(c, p, 'Endoplazmik\nretikulum', 90, 108, 44, 106, a: 'right');
  _ld(c, p, 'Ribozom', 85, 118, 44, 146, a: 'right');
  _ld(c, p, 'Hücre zarı', 244, 78, 266, 28);
  _ld(c, p, 'Mitokondri', 218, 59, 266, 60);
  _ld(c, p, 'Çekirdekçik', 138, 90, 266, 92);
  _ld(c, p, 'Golgi', 222, 118, 266, 124);
  _ld(c, p, 'Lizozom', 176, 140, 266, 156);
}

void _plantCell(Canvas c, WbArtPen p) {
  _rr(c, p, 90, 20, 190, 160, 16, _C.green, .12);
  c.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(96, 26, 178, 148),
      const Radius.circular(12),
    ),
    p.thin(.6),
  );
  _el(c, p, 140, 100, 38, 58, _C.lightBlue, .4);
  _t(c, p, 'Koful', 140, 100, size: 8, col: _C.blue);
  _el(c, p, 232, 62, 24, 20, _C.purple, .3);
  _ci(c, p, 229, 60, 6, _C.purple, .6);
  _rel(c, p, 232, 118, 14, 8, .3, _C.green, .55);
  _rel(c, p, 200, 150, 14, 8, -.3, _C.green, .55);
  _rel(c, p, 122, 40, 14, 8, 0, _C.green, .55);
  _mito(c, p, 115, 155, 1, .5);
  _mito(c, p, 245, 150, 1, -.4);
  _ld(c, p, 'Hücre duvarı', 90, 50, 82, 22, a: 'right');
  _ld(c, p, 'Hücre zarı', 96, 90, 82, 78, a: 'right');
  _ld(c, p, 'Mitokondri', 104, 158, 82, 168, a: 'right');
  _ld(c, p, 'Çekirdek', 252, 56, 288, 36);
  _ld(c, p, 'Kloroplast', 244, 120, 288, 100);
  _ld(c, p, 'Sitoplazma', 262, 90, 288, 130);
  _ld(c, p, 'Koful', 150, 150, 170, 188, a: 'center');
}

void _bacteria(Canvas c, WbArtPen p) {
  _rr(c, p, 80, 50, 170, 80, 40, _C.green, .08);
  _rr(c, p, 86, 56, 158, 68, 34, _C.green, .2);
  final dna = Path()
    ..moveTo(150, 80)
    ..cubicTo(130, 60, 180, 62, 190, 82)
    ..cubicTo(200, 104, 150, 110, 140, 96)
    ..cubicTo(130, 84, 160, 78, 168, 90);
  c.drawPath(dna, p.stroke(_C.purple, 1.4));
  _ci(c, p, 215, 90, 6, _C.orange, .2);
  for (final d in [
    const Offset(110, 80),
    const Offset(115, 100),
    const Offset(125, 112),
    const Offset(205, 66),
    const Offset(222, 112),
    const Offset(100, 92),
  ]) {
    _dot(c, p, d.dx, d.dy, 1.8, p.color);
  }
  final fl = Path()
    ..moveTo(250, 90)
    ..cubicTo(270, 70, 280, 110, 300, 90)
    ..cubicTo(315, 76, 325, 100, 335, 88);
  c.drawPath(fl, p.line);
  for (int i = 0; i < 6; i++) {
    final x = 100.0 + i * 25;
    _ln(c, p.thin(.6), x, 52, x - 3, 40);
    _ln(c, p.thin(.6), x, 128, x - 3, 140);
  }
  _ld(c, p, 'Kapsül', 88, 80, 20, 20, a: 'center');
  _ld(c, p, 'Hücre duvarı', 92, 112, 30, 160, a: 'center');
  _ld(c, p, 'Halka DNA\n(nükleoit)', 160, 100, 140, 160, a: 'center');
  _ld(c, p, 'Plazmit', 215, 84, 220, 28, a: 'center');
  _ld(c, p, 'Kamçı\n(flagellum)', 300, 90, 300, 30, a: 'center');
  _ld(c, p, 'Ribozom', 115, 100, 70, 112, a: 'right');
  _ld(c, p, 'Pilus', 150, 41, 168, 20, a: 'center');
  _t(c, p, 'Bakteri hücresi (çekirdeksiz)', 170, 185, size: 9, bold: true);
}

void _virus(Canvas c, WbArtPen p) {
  final head = WbArtPen.regular(const Offset(110, 70), 42, 6, 0);
  _pg(c, p, head, _C.purple, .25);
  for (final h in head) {
    _ln(c, p.thin(.5), 110, 70, h.dx, h.dy);
  }
  _ci(c, p, 110, 70, 14, _C.pink, .3);
  _t(c, p, 'DNA/RNA', 110, 70, size: 7);
  _rr(c, p, 103, 112, 14, 56, 3, _C.blue, .25);
  for (int i = 0; i < 5; i++) {
    _ln(c, p.thin(.6), 103, 120.0 + i * 10, 117, 124.0 + i * 10);
  }
  _pg(
    c,
    p,
    [const Offset(88, 172), const Offset(132, 172), const Offset(110, 184)],
    _C.green,
    .3,
  );
  for (int i = 0; i < 6; i++) {
    final a = _pi / 2 + (i - 2.5) * .55;
    _ln(
      c,
      p.line,
      110,
      176,
      110 + 52 * math.cos(a) * 1.0,
      176 + 40 * math.sin(a) * .9 + 8,
    );
  }
  _ld(c, p, 'Kapsit (protein kılıf)', 150, 50, 168, 20);
  _ld(c, p, 'Genetik madde\n(DNA veya RNA)', 118, 72, 168, 72);
  _ld(c, p, 'Kuyruk kılıfı', 117, 140, 168, 124);
  _ld(c, p, 'Taban plakası', 132, 174, 168, 160);
  _ld(c, p, 'Kuyruk lifleri', 150, 192, 168, 190);
  _t(c, p, 'Virüs (bakteriyofaj)', 110, 212, size: 9, bold: true);
}

void _dna(Canvas c, WbArtPen p) {
  const cx = 90.0;
  const amp = 36.0;
  final s1 = Path();
  final s2 = Path();
  for (int i = 0; i <= 80; i++) {
    final y = 14 + i * 2.7;
    final x1 = cx + amp * math.sin(i * _pi / 20);
    final x2 = cx - amp * math.sin(i * _pi / 20);
    if (i == 0) {
      s1.moveTo(x1, y);
      s2.moveTo(x2, y);
    } else {
      s1.lineTo(x1, y);
      s2.lineTo(x2, y);
    }
  }
  final cols = [
    [_C.red, _C.blue],
    [_C.green, _C.orange],
    [_C.blue, _C.red],
    [_C.orange, _C.green],
  ];
  for (int i = 2; i <= 78; i += 5) {
    final y = 14 + i * 2.7;
    final x1 = cx + amp * math.sin(i * _pi / 20);
    final x2 = cx - amp * math.sin(i * _pi / 20);
    final k = cols[(i ~/ 5) % 4];
    final mid = (x1 + x2) / 2;
    _ln(c, p.stroke(k[0], 1.2), x1, y, mid, y);
    _ln(c, p.stroke(k[1], 1.2), mid, y, x2, y);
  }
  c.drawPath(s1, p.stroke(_C.blue, 1.5));
  c.drawPath(s2, p.stroke(_C.purple, 1.5));
  _ld(c, p, 'Şeker-fosfat\nomurgası', 126, 50, 150, 24);
  _ld(c, p, 'Adenin (A) = Timin (T)\n2 hidrojen bağı', 92, 106, 150, 78);
  _ld(c, p, 'Guanin (G) ≡ Sitozin (C)\n3 hidrojen bağı', 92, 150, 150, 130);
  _ld(c, p, 'Nükleotit', 60, 190, 150, 180);
  _t(c, p, 'DNA çift sarmal', 100, 238, size: 9, bold: true);
}

void _chromosome(Canvas c, WbArtPen p) {
  _rr(c, p, 88, 20, 24, 85, 12, _C.purple, .3);
  _rr(c, p, 118, 20, 24, 85, 12, _C.pink, .3);
  _rr(c, p, 88, 95, 24, 85, 12, _C.purple, .3);
  _rr(c, p, 118, 95, 24, 85, 12, _C.pink, .3);
  _ci(c, p, 115, 100, 8, _C.yellow, .8);
  for (int i = 0; i < 4; i++) {
    _ln(c, p.thin(.5), 90, 36.0 + i * 16, 110, 36.0 + i * 16);
    _ln(c, p.thin(.5), 120, 36.0 + i * 16, 140, 36.0 + i * 16);
  }
  _ld(c, p, 'Kromatit', 100, 50, 40, 40, a: 'right');
  _ld(c, p, 'Kardeş kromatit', 130, 60, 170, 40);
  _ld(c, p, 'Sentromer', 123, 100, 170, 100);
  _ld(c, p, 'Kısa kol', 130, 28, 170, 14);
  _ld(c, p, 'Uzun kol', 130, 165, 170, 150);
  _ld(c, p, 'Telomer', 100, 178, 40, 186, a: 'right');
  _t(c, p, 'Kromozom (eşlenmiş)', 115, 205, size: 9, bold: true);
}

void _mitosis(Canvas c, WbArtPen p) {
  final names = ['İnterfaz', 'Profaz', 'Metafaz', 'Anafaz', 'Telofaz'];
  for (int i = 0; i < 5; i++) {
    final x = 45.0 + i * 85;
    const y = 60.0;
    if (i < 3) {
      _ci(c, p, x, y, 30, _C.green, .12);
    } else if (i == 3) {
      _el(c, p, x, y, 36, 28, _C.green, .12);
    } else {
      _el(c, p, x - 14, y, 20, 26, _C.green, .12);
      _el(c, p, x + 14, y, 20, 26, _C.green, .12);
    }
    switch (i) {
      case 0:
        _ci(c, p, x, y, 15, _C.purple, .25);
        for (int k = 0; k < 6; k++) {
          _dot(
            c,
            p,
            x + 6 * math.cos(k * 1.1),
            y + 6 * math.sin(k * 1.7),
            1.4,
            _C.purple,
          );
        }
        break;
      case 1:
        _ci(c, p, x, y, 18, _C.purple, .08);
        _chrom(c, p, x - 8, y - 6, 1, .3, _C.purple);
        _chrom(c, p, x + 7, y - 2, 1, 1.0, _C.red);
        _chrom(c, p, x - 2, y + 8, 1, -.5, _C.purple);
        _chrom(c, p, x + 8, y + 9, 1, .8, _C.red);
        break;
      case 2:
        _ln(c, p.thin(.4), x, y - 28, x - 4, y);
        _ln(c, p.thin(.4), x, y - 28, x + 4, y);
        _ln(c, p.thin(.4), x, y + 28, x - 4, y);
        _ln(c, p.thin(.4), x, y + 28, x + 4, y);
        for (int k = 0; k < 4; k++) {
          _chrom(c, p, x - 9 + k * 6.0, y, 1, 0, k.isEven ? _C.purple : _C.red);
        }
        break;
      case 3:
        for (int k = 0; k < 4; k++) {
          final yy = y - 6 + k * 4.0;
          _ln(
            c,
            p.stroke(k.isEven ? _C.purple : _C.red, 1.5),
            x - 22,
            yy,
            x - 14,
            yy + 2,
          );
          _ln(
            c,
            p.stroke(k.isEven ? _C.purple : _C.red, 1.5),
            x + 22,
            yy,
            x + 14,
            yy + 2,
          );
        }
        _ar(c, p, x - 8, y - 20, x - 24, y - 20, _C.gray, 4);
        _ar(c, p, x + 8, y - 20, x + 24, y - 20, _C.gray, 4);
        break;
      default:
        _ci(c, p, x - 14, y, 9, _C.purple, .3);
        _ci(c, p, x + 14, y, 9, _C.purple, .3);
    }
    _t(c, p, names[i], x, 108, size: 9, bold: true);
  }
  for (int i = 0; i < 4; i++) {
    _ar(c, p, 45.0 + i * 85 + 34, 60, 45.0 + (i + 1) * 85 - 38, 60, _C.gray, 5);
  }
  _t(c, p, 'Mitoz: 1 hücre → 2 özdeş hücre (2n → 2n)', 215, 135, size: 9);
}

void _meiosis(Canvas c, WbArtPen p) {
  _ci(c, p, 160, 28, 22, _C.green, .12);
  _chrom(c, p, 152, 28, 1, .2, _C.purple);
  _chrom(c, p, 168, 28, 1, -.2, _C.red);
  _t(c, p, '2n', 160, 28 + 36, size: 8, col: _C.gray);
  _t(c, p, 'Ana hücre', 215, 28, size: 8.5, a: 'left');
  _ar(c, p, 160, 54, 160, 70, _C.gray, 5);
  _t(c, p, 'DNA eşlenir', 215, 62, size: 8, a: 'left');
  for (final x in [100.0, 220.0]) {
    _ci(c, p, x, 98, 22, _C.green, .12);
    _chrom(c, p, x - 6, 98, 1, .3, _C.purple);
    _chrom(c, p, x + 6, 98, 1, -.3, _C.red);
  }
  _ln(c, p.stroke(_C.gray, .6), 148, 38, 100, 74);
  _ln(c, p.stroke(_C.gray, .6), 172, 38, 220, 74);
  _t(c, p, 'Mayoz I (n+n)', 160, 98, size: 9, bold: true);
  for (int i = 0; i < 4; i++) {
    final x = 55.0 + i * 70;
    _ci(c, p, x, 172, 18, _C.green, .12);
    _chrom(c, p, x, 172, .8, 0, i.isEven ? _C.purple : _C.red);
    _t(c, p, 'n', x, 198, size: 8, col: _C.gray);
  }
  _ln(c, p.stroke(_C.gray, .6), 94, 120, 65, 152);
  _ln(c, p.stroke(_C.gray, .6), 106, 120, 125, 152);
  _ln(c, p.stroke(_C.gray, .6), 214, 120, 195, 152);
  _ln(c, p.stroke(_C.gray, .6), 226, 120, 255, 152);
  _t(
    c,
    p,
    'Mayoz II → 4 farklı eşey hücresi (gamet)',
    160,
    222,
    size: 9,
    bold: true,
  );
}

void _membrane(Canvas c, WbArtPen p) {
  for (int i = 0; i < 14; i++) {
    final x = 24.0 + i * 15;
    if (i == 4 || i == 5 || i == 10) continue;
    _ci(c, p, x, 60, 5.5, _C.yellow, .6);
    _ln(c, p.thin(.6), x - 2, 66, x - 2, 84);
    _ln(c, p.thin(.6), x + 2, 66, x + 2, 84);
  }
  for (int i = 0; i < 14; i++) {
    final x = 24.0 + i * 15;
    if (i == 4 || i == 5 || i == 11) continue;
    _ci(c, p, x, 136, 5.5, _C.yellow, .6);
    _ln(c, p.thin(.6), x - 2, 130, x - 2, 112);
    _ln(c, p.thin(.6), x + 2, 130, x + 2, 112);
  }
  _rr(c, p, 85, 50, 28, 96, 12, _C.blue, .3);
  _ln(c, p.stroke(_C.blue, .8), 93, 70, 93, 126);
  _rr(c, p, 160, 54, 22, 88, 10, _C.purple, .3);
  _rr(c, p, 168, 54, 6, 88, 3, _C.lightBlue, .8);
  _el(c, p, 234, 70, 9, 22, _C.pink, .3);
  final ch = Path()
    ..moveTo(99, 50)
    ..lineTo(99, 36)
    ..lineTo(106, 28)
    ..lineTo(112, 34)
    ..lineTo(118, 24);
  c.drawPath(ch, p.stroke(_C.green, .9));
  _t(c, p, 'HÜCRE DIŞI', 130, 8, size: 8.5, col: _C.gray, bold: true);
  _t(
    c,
    p,
    'HÜCRE İÇİ (sitoplazma)',
    130,
    166,
    size: 8.5,
    col: _C.gray,
    bold: true,
  );
  _ld(c, p, 'Fosfolipit başı\n(suyu sever)', 276 - 40, 60, 262, 28);
  _ld(c, p, 'Yağ asidi kuyruğu\n(suyu sevmez)', 270, 100, 262, 100);
  _ld(c, p, 'Taşıyıcı protein', 106, 100, 262, 140);
  _ld(c, p, 'Kanal protein', 176, 100, 262, 66, a: 'left');
  _ld(c, p, 'Karbonhidrat\nzinciri', 112, 30, 262, 6);
  _t(c, p, 'Hücre zarı (akıcı mozaik model)', 150, 184, size: 9, bold: true);
}

void _proteinSynthesis(Canvas c, WbArtPen p) {
  _rr(c, p, 10, 10, 270, 80, 14, _C.purple, .08);
  _t(c, p, 'Çekirdek', 250, 20, size: 8, col: _C.purple);
  _ln(c, p.stroke(_C.blue), 30, 34, 150, 34);
  _ln(c, p.stroke(_C.blue), 30, 50, 150, 50);
  for (int i = 0; i < 9; i++) {
    _ln(c, p.thin(.5), 34.0 + i * 13.5, 34, 34.0 + i * 13.5, 50);
  }
  _t(c, p, 'DNA', 18, 42, size: 8.5, bold: true, a: 'right');
  final m = Path()
    ..moveTo(150, 50)
    ..cubicTo(180, 56, 200, 70, 230, 76)
    ..lineTo(290, 80);
  c.drawPath(m, p.stroke(_C.red, 1.6));
  _t(c, p, 'mRNA', 200, 58, size: 8.5, col: _C.red, bold: true);
  _t(c, p, 'Transkripsiyon', 90, 66, size: 8.5, col: _C.purple, bold: true);
  _ar(c, p, 150, 100, 150, 112, _C.gray, 5);
  _t(
    c,
    p,
    'Translasyon',
    175,
    110,
    size: 8.5,
    col: _C.purple,
    bold: true,
    a: 'left',
  );
  _ln(c, p.stroke(_C.red, 1.6), 40, 150, 250, 150);
  _el(c, p, 150, 138, 38, 14, _C.teal, .35);
  _el(c, p, 150, 166, 30, 12, _C.teal, .45);
  _t(c, p, 'Ribozom', 150, 126, size: 8, col: _C.darkGreen, bold: true);
  for (int i = 0; i < 3; i++) {
    final x = 126.0 + i * 24;
    _pg(
      c,
      p,
      [Offset(x - 7, 150), Offset(x + 7, 150), Offset(x, 168)],
      _C.orange,
      .3,
    );
    _t(c, p, ['A', 'U', 'G'][i], x, 158, size: 7);
  }
  for (int i = 0; i < 5; i++) {
    _ci(c, p, 40.0 + i * 15, 178 - i * 6.0, 6, _C.green, .5);
  }
  _ld(c, p, 'Amino asit zinciri\n(protein)', 52, 175, 18, 205, a: 'left');
  _ld(c, p, 'tRNA', 150, 166, 215, 190, a: 'left');
}

void _enzyme(Canvas c, WbArtPen p) {
  List<Offset> enz(double x, double y) => [
    Offset(x - 26, y - 18),
    Offset(x - 9, y - 18),
    Offset(x, y - 6),
    Offset(x + 9, y - 18),
    Offset(x + 26, y - 18),
    Offset(x + 26, y + 20),
    Offset(x - 26, y + 20),
  ];
  void sub(double x, double y) => _pg(
    c,
    p,
    [Offset(x - 9, y - 18), Offset(x + 9, y - 18), Offset(x, y - 6)],
    _C.red,
    .5,
  );
  _pg(c, p, enz(50, 80), _C.blue, .25);
  sub(50, 40);
  _t(c, p, 'Enzim', 50, 112, size: 8.5, bold: true);
  _t(c, p, 'Substrat', 50, 20, size: 8.5, bold: true, col: _C.red);
  _t(c, p, '1) Yaklaşma', 50, 130, size: 9);
  _ar(c, p, 88, 70, 105, 70, _C.gray, 5);
  _pg(c, p, enz(150, 80), _C.blue, .25);
  sub(150, 80);
  _t(c, p, 'Enzim-substrat\nkompleksi', 150, 112, size: 8.5, bold: true);
  _t(c, p, '2) Kilit-anahtar uyumu', 150, 135, size: 9);
  _ar(c, p, 188, 70, 205, 70, _C.gray, 5);
  _pg(c, p, enz(250, 80), _C.blue, .25);
  _pg(
    c,
    p,
    [const Offset(223, 40), const Offset(240, 40), const Offset(240, 58)],
    _C.red,
    .5,
  );
  _pg(
    c,
    p,
    [const Offset(260, 40), const Offset(277, 40), const Offset(260, 58)],
    _C.red,
    .5,
  );
  _t(
    c,
    p,
    'Ürünler + enzim\n(enzim değişmez)',
    250,
    112,
    size: 8.5,
    bold: true,
  );
  _t(c, p, '3) Ayrışma', 250, 135, size: 9);
}

void _osmosis(Canvas c, WbArtPen p) {
  _rr(c, p, 30, 20, 200, 130, 6, _C.lightBlue, .12);
  _ln(c, p.stroke(_C.gray, .9), 130, 20, 130, 150);
  p.dashed(
    c,
    const Offset(130, 20),
    const Offset(130, 150),
    paint: p.stroke(_C.brown, 1.2),
  );
  for (final d in [
    const Offset(50, 40),
    const Offset(80, 70),
    const Offset(60, 110),
    const Offset(100, 50),
    const Offset(105, 120),
    const Offset(45, 85),
    const Offset(90, 95),
    const Offset(110, 85),
  ]) {
    _ci(c, p, d.dx, d.dy, 5, _C.red, .55);
  }
  for (final d in [
    const Offset(160, 40),
    const Offset(190, 60),
    const Offset(170, 100),
    const Offset(205, 120),
    const Offset(150, 130),
    const Offset(215, 45),
    const Offset(185, 90),
    const Offset(155, 70),
    const Offset(200, 90),
    const Offset(170, 125),
  ]) {
    _dot(c, p, d.dx, d.dy, 2.6, _C.blue, .7);
  }
  _ar(c, p, 200, 28, 142, 28, _C.blue, 6);
  _ar(c, p, 190, 142, 142, 142, _C.blue, 6);
  _t(c, p, 'Seyrek çözelti\n(çok su)', 180, 160, size: 8.5);
  _t(c, p, 'Derişik çözelti\n(çok çözünen)', 80, 160, size: 8.5);
  _ld(c, p, 'Yarı geçirgen zar', 130, 120, 240, 80);
  _ld(c, p, 'Çözünen madde', 100, 50, 240, 20, a: 'left');
  _ld(c, p, 'Su molekülü', 215, 45, 240, 44, a: 'left');
  _t(
    c,
    p,
    'Ozmos: su, az derişimden çok derişime geçer',
    130,
    190,
    size: 9,
    bold: true,
  );
}

void _diffusion(Canvas c, WbArtPen p) {
  final pts = [
    [const Offset(34, 60)],
    [
      const Offset(30, 50),
      const Offset(46, 80),
      const Offset(60, 60),
      const Offset(40, 95),
      const Offset(70, 100),
      const Offset(55, 45),
    ],
    [
      const Offset(30, 50),
      const Offset(46, 80),
      const Offset(60, 60),
      const Offset(40, 95),
      const Offset(70, 100),
      const Offset(55, 45),
      const Offset(80, 70),
      const Offset(25, 75),
      const Offset(75, 45),
      const Offset(50, 105),
      const Offset(82, 100),
      const Offset(65, 82),
    ],
  ];
  const labels = ['Başlangıç', 'Yayılıyor', 'Denge'];
  for (int i = 0; i < 3; i++) {
    final ox = 10.0 + i * 120;
    _rr(c, p, ox + 10, 30, 90, 95, 6, _C.lightBlue, .12);
    c.drawRect(Rect.fromLTWH(ox + 10, 30, 90, 95), p.fill(_C.lightBlue, .0));
    for (final d in pts[i]) {
      _dot(c, p, ox + 10 + d.dx * (i == 0 ? 1 : 1), d.dy, 3.2, _C.red, .8);
    }
    _t(c, p, labels[i], ox + 55, 140, size: 9, bold: true);
  }
  _ar(c, p, 108, 78, 128, 78, _C.gray, 5);
  _ar(c, p, 228, 78, 248, 78, _C.gray, 5);
  _t(
    c,
    p,
    'Difüzyon: çok derişikten az derişiğe yayılma',
    180,
    170,
    size: 9,
    bold: true,
  );
}

void _photosynthesis(Canvas c, WbArtPen p) {
  _sun(c, p, 40, 40, 20);
  for (int i = 0; i < 3; i++) {
    _ar(
      c,
      p,
      62.0 + i * 6,
      58.0 + i * 12,
      118.0 + i * 6,
      96.0 + i * 12,
      _C.yellow,
      6,
    );
  }
  _t(c, p, 'Işık enerjisi', 40, 78, size: 8.5);
  final leaf = Path()
    ..moveTo(110, 170)
    ..cubicTo(130, 80, 220, 50, 290, 70)
    ..cubicTo(290, 140, 220, 190, 110, 170);
  _pf(c, p, leaf, _C.green, .35);
  c.drawPath(
    Path()
      ..moveTo(112, 168)
      ..quadraticBezierTo(190, 120, 270, 78),
    p.thin(.7),
  );
  _t(
    c,
    p,
    'Yaprak\n(kloroplast)',
    215,
    128,
    size: 8.5,
    col: _C.darkGreen,
    bold: true,
  );
  _ar(c, p, 80, 135, 128, 135, _C.gray, 6);
  _t(c, p, 'CO₂', 60, 135, size: 10, bold: true);
  _ar(c, p, 280, 80, 322, 56, _C.blue, 6);
  _t(c, p, 'O₂', 336, 52, size: 10, bold: true, col: _C.blue);
  _ar(c, p, 140, 238, 140, 190, _C.blue, 6);
  _t(c, p, 'H₂O (kökten)', 140, 248, size: 9, bold: true);
  _ar(c, p, 250, 160, 300, 186, _C.orange, 6);
  _t(c, p, 'Glikoz', 322, 190, size: 9.5, bold: true, col: _C.orange);
  _rr(c, p, 40, 10, 0, 0, 0, _C.green, 0);
  _t(
    c,
    p,
    '6CO₂ + 6H₂O + ışık → C₆H₁₂O₆ + 6O₂',
    190,
    275,
    size: 9.5,
    bold: true,
  );
}

void _respiration(Canvas c, WbArtPen p) {
  _mito(c, p, 170, 80, 3.2, 0);
  _t(c, p, 'Mitokondri', 170, 128, size: 9, bold: true);
  _ar(c, p, 50, 60, 118, 70, _C.orange, 6);
  _t(c, p, 'Glikoz', 28, 56, size: 9, bold: true, col: _C.orange);
  _ar(c, p, 50, 100, 118, 90, _C.blue, 6);
  _t(c, p, 'O₂', 34, 106, size: 10, bold: true, col: _C.blue);
  _ar(c, p, 222, 60, 285, 40, _C.gray, 6);
  _t(c, p, 'CO₂', 305, 38, size: 10, bold: true);
  _ar(c, p, 222, 80, 285, 80, _C.lightBlue, 6);
  _t(c, p, 'H₂O', 305, 80, size: 10, bold: true, col: _C.blue);
  _ar(c, p, 222, 100, 285, 122, _C.yellow, 6);
  _star(c, p, 306, 126, 9, _C.yellow);
  _t(c, p, 'ATP (enerji)', 306, 146, size: 9, bold: true);
  _t(
    c,
    p,
    'C₆H₁₂O₆ + 6O₂ → 6CO₂ + 6H₂O + enerji (ATP)',
    170,
    175,
    size: 9.5,
    bold: true,
  );
  _t(c, p, 'Hücre solunumu', 170, 195, size: 9, col: _C.gray);
}

void _flower(Canvas c, WbArtPen p) {
  _ln(c, p.stroke(_C.darkGreen, 2), 140, 150, 140, 232);
  _rel(c, p, 112, 205, 20, 7, -.5, _C.green, .4);
  _rel(c, p, 112, 138, 14, 6, .6, _C.green, .5);
  _rel(c, p, 168, 138, 14, 6, -.6, _C.green, .5);
  _rel(c, p, 92, 88, 34, 13, -.85, _C.pink, .35);
  _rel(c, p, 188, 88, 34, 13, .85, _C.pink, .35);
  _rel(c, p, 140, 64, 0.1, 0.1, 0, _C.pink, 0);
  _ln(c, p.stroke(_C.green, 1.2), 128, 118, 108, 66);
  _ln(c, p.stroke(_C.green, 1.2), 152, 118, 174, 66);
  _rel(c, p, 107, 62, 4.5, 8, .3, _C.orange, .7);
  _rel(c, p, 175, 62, 4.5, 8, -.3, _C.orange, .7);
  _ln(c, p.stroke(_C.green, 1.6), 140, 118, 140, 62);
  _ci(c, p, 140, 56, 6, _C.yellow, .8);
  _el(c, p, 140, 130, 14, 18, _C.green, .4);
  for (final d in [
    const Offset(136, 126),
    const Offset(145, 128),
    const Offset(138, 136),
    const Offset(144, 137),
  ]) {
    _dot(c, p, d.dx, d.dy, 1.7, _C.brown);
  }
  _rr(c, p, 128, 146, 24, 7, 3, _C.brown, .35);
  _ld(c, p, 'Taç yaprak', 70, 90, 6, 60, a: 'left');
  _ld(c, p, 'Anter', 105, 58, 40, 24, a: 'left');
  _ld(c, p, 'Filament', 115, 90, 20, 130, a: 'left');
  _ld(c, p, 'Çanak yaprak (sepal)', 112, 138, 6, 170, a: 'left');
  _ld(c, p, 'Tepecik (stigma)', 146, 52, 200, 24);
  _ld(c, p, 'Boyuncuk (stil)', 140, 90, 206, 58, a: 'left');
  _ld(c, p, 'Yumurtalık (ovaryum)', 148, 130, 206, 112);
  _ld(c, p, 'Tohum taslağı', 144, 137, 206, 150);
  _ld(c, p, 'Çiçek tablası', 152, 149, 206, 180);
  _ld(c, p, 'Çiçek sapı', 142, 200, 206, 210);
  _t(
    c,
    p,
    'Erkek organ: stamen · Dişi organ: pistil',
    140,
    250,
    size: 8.5,
    bold: true,
  );
}

void _germination(Canvas c, WbArtPen p) {
  const names = ['Tohum', 'Şişme-çatlama', 'Kökçük çıkışı', 'Fidan'];
  for (int i = 0; i < 4; i++) {
    final x = 55.0 + i * 100;
    c.drawRect(Rect.fromLTWH(x - 40, 80, 80, 60), p.fill(_C.brown, .3));
    _ln(c, p.stroke(_C.brown, .8), x - 40, 80, x + 40, 80);
    _t(c, p, names[i], x, 155, size: 9, bold: true);
    _t(c, p, '${i + 1}', x - 34, 20, size: 12, bold: true, col: _C.gray);
    switch (i) {
      case 0:
        _el(c, p, x, 108, 8, 5.5, _C.orange, .6);
        break;
      case 1:
        _el(c, p, x, 108, 10, 7, _C.orange, .6);
        _ln(c, p.stroke(_C.brown, 1), x - 2, 103, x + 3, 113);
        break;
      case 2:
        _el(c, p, x, 100, 10, 7, _C.orange, .6);
        _ln(c, p.stroke(_C.brown, 1.4), x, 107, x + 4, 130);
        _ln(c, p.thin(.6), x + 4, 120, x + 12, 126);
        break;
      default:
        _ln(c, p.stroke(_C.brown, 1.4), x, 104, x + 2, 136);
        _ln(c, p.thin(.6), x + 2, 120, x - 8, 128);
        _ln(c, p.thin(.6), x + 2, 124, x + 10, 132);
        _ln(c, p.stroke(_C.green, 2), x, 104, x, 50);
        _rel(c, p, x - 10, 56, 11, 5, -.5, _C.green, .5);
        _rel(c, p, x + 10, 50, 11, 5, .5, _C.green, .5);
        _el(c, p, x, 104, 6, 4, _C.orange, .5);
    }
    if (i < 3) _ar(c, p, x + 30, 40, x + 62, 40, _C.gray, 5);
  }
  _t(
    c,
    p,
    'Su, uygun sıcaklık ve oksijen ile çimlenme',
    200,
    180,
    size: 9,
    col: _C.gray,
  );
}

void _rootStem(Canvas c, WbArtPen p) {
  c.drawRect(const Rect.fromLTWH(10, 130, 240, 80), p.fill(_C.brown, .22));
  _ln(c, p.stroke(_C.brown, .8), 10, 130, 250, 130);
  _ln(c, p.stroke(_C.darkGreen, 2.6), 120, 130, 120, 40);
  for (int i = 0; i < 3; i++) {
    final y = 50.0 + i * 24;
    _rel(c, p, 90, y, 22, 8, i.isEven ? -.4 : -.2, _C.green, .45);
    _rel(c, p, 150, y + 10, 22, 8, i.isEven ? .2 : .4, _C.green, .45);
  }
  _el(c, p, 120, 30, 16, 10, _C.green, .5);
  _ln(c, p.stroke(_C.brown, 2.2), 120, 130, 120, 185);
  _ln(c, p.stroke(_C.brown, 1.4), 120, 145, 80, 175);
  _ln(c, p.stroke(_C.brown, 1.4), 120, 150, 165, 180);
  _ln(c, p.stroke(_C.brown, 1.4), 120, 172, 95, 200);
  for (final r in [
    const Offset(95, 158),
    const Offset(100, 166),
    const Offset(146, 163),
    const Offset(142, 170),
    const Offset(80, 175),
  ]) {
    _ln(c, p.thin(.4), r.dx, r.dy, r.dx - 6, r.dy - 3);
    _ln(c, p.thin(.4), r.dx, r.dy, r.dx - 6, r.dy + 3);
  }
  _ld(c, p, 'Yaprak', 70, 52, 8, 24, a: 'left');
  _ld(c, p, 'Gövde', 120, 90, 8, 100, a: 'left');
  _ld(c, p, 'Toprak yüzeyi', 40, 130, 8, 122, a: 'left');
  _ld(c, p, 'Ana kök', 120, 160, 180, 142);
  _ld(c, p, 'Yan kök', 165, 180, 190, 200);
  _ld(c, p, 'Kök tüyleri', 94, 160, 8, 190, a: 'left');
  _ld(c, p, 'Tomurcuk', 128, 28, 180, 18);
  _t(c, p, 'Bitki: kök – gövde – yaprak', 130, 225, size: 9, bold: true);
}

void _leafSection(Canvas c, WbArtPen p) {
  _rr(c, p, 20, 20, 240, 12, 2, _C.lightBlue, .45);
  _rr(c, p, 20, 15, 240, 5, 2, _C.yellow, .5);
  for (int i = 0; i < 12; i++) {
    _rr(c, p, 24.0 + i * 20, 34, 16, 42, 5, _C.green, .5);
    for (int k = 0; k < 3; k++) {
      _dot(c, p, 32.0 + i * 20, 42.0 + k * 11, 1.5, _C.darkGreen);
    }
  }
  for (int i = 0; i < 6; i++) {
    for (int r = 0; r < 2; r++) {
      _el(c, p, 36.0 + i * 40 + (r * 20), 90.0 + r * 16, 14, 9, _C.green, .3);
    }
  }
  _rr(c, p, 20, 126, 240, 12, 2, _C.lightBlue, .45);
  _ci(c, p, 125, 66, 0, _C.green, 0);
  _el(c, p, 150, 92, 14, 13, _C.orange, .25);
  _el(c, p, 150, 92, 7, 6, _C.blue, .4);
  _t(c, p, 'ksilem', 150, 92, size: 5.5);
  _el(c, p, 150, 106, 5, 5, _C.pink, .5);
  _rel(c, p, 100, 132, 9, 5, .4, _C.green, .7);
  _rel(c, p, 118, 132, 9, 5, -.4, _C.green, .7);
  _ln(c, p.stroke(Colors.white, 4), 108, 132, 110, 132);
  _t(c, p, 'GÜNEŞ IŞIĞI ↓', 140, 4, size: 8.5, bold: true, col: _C.orange);
  _ld(c, p, 'Kütikül', 30, 17, 288, 8, a: 'left');
  _ld(c, p, 'Üst epidermis', 250, 26, 288, 30, a: 'left');
  _ld(c, p, 'Palizat parankiması', 250, 55, 288, 56, a: 'left');
  _ld(c, p, 'Sünger parankima', 240, 96, 288, 86, a: 'left');
  _ld(c, p, 'İletim demeti\n(ksilem, floem)', 164, 95, 288, 112, a: 'left');
  _ld(c, p, 'Alt epidermis', 250, 133, 288, 138, a: 'left');
  _ld(c, p, 'Stoma (gözenek)', 109, 133, 70, 168, a: 'center');
  _ld(c, p, 'Koruyucu hücre', 118, 136, 190, 168, a: 'center');
}

void _lifeCycle(Canvas c, WbArtPen p) {
  const cx = 150.0, cy = 125.0, r = 85.0;
  _carc(c, p, cx, cy, r, -80, 55, _C.gray);
  _carc(c, p, cx, cy, r, -8, 60, _C.gray);
  _carc(c, p, cx, cy, r, 64, 65, _C.gray);
  _carc(c, p, cx, cy, r, 140, 60, _C.gray);
  _carc(c, p, cx, cy, r, 208, 60, _C.gray);
  final names = ['Tohum', 'Çimlenme', 'Fidan', 'Çiçekli bitki', 'Meyve'];
  for (int i = 0; i < 5; i++) {
    final a = -_pi / 2 + i * 2 * _pi / 5 + 0.0;
    final x = cx + r * math.cos(a);
    final y = cy + r * math.sin(a);
    _ci(c, p, x, y, 17, Colors.white, .0);
    switch (i) {
      case 0:
        _el(c, p, x, y, 8, 5.5, _C.orange, .6);
        break;
      case 1:
        _ln(c, p.stroke(_C.green, 1.6), x, y + 8, x, y - 6);
        _rel(c, p, x - 6, y - 6, 6, 3, -.5, _C.green, .5);
        _rel(c, p, x + 6, y - 7, 6, 3, .5, _C.green, .5);
        break;
      case 2:
        _ln(c, p.stroke(_C.green, 1.8), x, y + 10, x, y - 8);
        for (int k = 0; k < 2; k++) {
          _rel(c, p, x - 7, y - 2 + k * 5.0, 7, 3, -.4, _C.green, .5);
          _rel(c, p, x + 7, y - 4 + k * 5.0, 7, 3, .4, _C.green, .5);
        }
        break;
      case 3:
        _ln(c, p.stroke(_C.green, 1.8), x, y + 10, x, y);
        for (int k = 0; k < 5; k++) {
          final aa = k * 2 * _pi / 5;
          _ci(
            c,
            p,
            x + 6 * math.cos(aa),
            y - 4 + 6 * math.sin(aa),
            3.5,
            _C.pink,
            .6,
          );
        }
        _dot(c, p, x, y - 4, 2.5, _C.yellow);
        break;
      default:
        _ci(c, p, x, y, 8, _C.red, .55);
        _ln(c, p.stroke(_C.darkGreen, 1.2), x, y - 8, x + 3, y - 13);
    }
    final ox = (x - cx) * 1.0;
    final oy = (y - cy) * 1.0;
    final tx = x + (ox > 1 ? 24 : (ox < -1 ? -24 : 0));
    final ty = y + (oy < -60 ? -22 : (ox.abs() > 1 ? 4 : 22));
    _t(
      c,
      p,
      names[i],
      tx,
      ty,
      size: 9,
      bold: true,
      a: ox > 1 ? 'left' : (ox < -1 ? 'right' : 'center'),
    );
  }
  _t(c, p, 'Bitkinin\nyaşam döngüsü', cx, cy, size: 9, col: _C.gray);
}

void _heart(Canvas c, WbArtPen p) {
  final blue = p.stroke(_C.blue, 6);
  final red = p.stroke(_C.red, 6);
  // damarlar
  c.drawPath(
    Path()
      ..moveTo(100, 14)
      ..lineTo(100, 100),
    blue,
  );
  c.drawPath(
    Path()
      ..moveTo(112, 160)
      ..lineTo(112, 232),
    blue,
  );
  c.drawPath(
    Path()
      ..moveTo(150, 120)
      ..lineTo(150, 50)
      ..quadraticBezierTo(150, 22, 185, 24)
      ..quadraticBezierTo(215, 26, 215, 70)
      ..lineTo(215, 120),
    red,
  );
  c.drawPath(
    Path()
      ..moveTo(128, 124)
      ..lineTo(128, 70),
    blue,
  );
  c.drawPath(
    Path()
      ..moveTo(128, 70)
      ..lineTo(98, 52),
    blue,
  );
  c.drawPath(
    Path()
      ..moveTo(128, 70)
      ..lineTo(152, 50),
    blue,
  );
  c.drawPath(
    Path()
      ..moveTo(180, 112)
      ..lineTo(232, 90),
    red,
  );
  c.drawPath(
    Path()
      ..moveTo(172, 125)
      ..lineTo(232, 130),
    red,
  );
  // odacıklar
  _el(c, p, 105, 122, 28, 24, _C.blue, .3);
  _el(c, p, 172, 112, 26, 22, _C.red, .3);
  final rv = Path()
    ..moveTo(78, 135)
    ..quadraticBezierTo(70, 200, 135, 232)
    ..quadraticBezierTo(150, 180, 148, 135)
    ..close();
  _pf(c, p, rv, _C.blue, .3);
  final lv = Path()
    ..moveTo(148, 130)
    ..quadraticBezierTo(150, 190, 138, 232)
    ..quadraticBezierTo(215, 200, 205, 125)
    ..close();
  _pf(c, p, lv, _C.red, .3);
  _t(c, p, 'SAĞ\nATRİYUM', 105, 120, size: 7);
  _t(c, p, 'SOL\nATRİYUM', 175, 112, size: 7);
  _t(c, p, 'SAĞ\nVENTRİKÜL', 112, 185, size: 7);
  _t(c, p, 'SOL\nVENTRİKÜL', 172, 185, size: 7);
  _ld(c, p, 'Üst ana toplardamar', 100, 40, 90, 8, a: 'right');
  _ld(c, p, 'Alt ana toplardamar', 112, 215, 100, 248, a: 'right');
  _ld(c, p, 'Aort (büyük atardamar)', 205, 40, 225, 8, a: 'right');
  _ld(c, p, 'Akciğer atardamarı', 128, 60, 20, 40, a: 'left');
  _ld(c, p, 'Akciğer\ntoplardamarı', 226, 92, 234, 66, a: 'left');
  _t(
    c,
    p,
    'Mavi: kirli kan · Kırmızı: temiz kan',
    130,
    262,
    size: 8.5,
    bold: true,
  );
}

void _circulation(Canvas c, WbArtPen p) {
  _rr(c, p, 125, 100, 50, 56, 12, _C.red, .15);
  _rr(c, p, 125, 100, 25, 56, 12, _C.blue, .3);
  _t(c, p, 'Sağ\nkalp', 137, 128, size: 7.5);
  _t(c, p, 'Sol\nkalp', 163, 128, size: 7.5);
  _el(c, p, 150, 36, 60, 18, _C.pink, .3);
  _t(c, p, 'AKCİĞERLER (gaz alışverişi)', 150, 36, size: 8.5, bold: true);
  _el(c, p, 150, 222, 80, 18, _C.orange, .25);
  _t(c, p, 'VÜCUT HÜCRELERİ (organlar)', 150, 222, size: 8.5, bold: true);
  final b = p.stroke(_C.blue, 1.6);
  final r = p.stroke(_C.red, 1.6);
  _ln(c, b, 130, 100, 130, 54);
  _ar(c, p, 130, 80, 130, 56, _C.blue, 6);
  _ln(c, r, 170, 54, 170, 100);
  _ar(c, p, 170, 76, 170, 98, _C.red, 6);
  _ln(c, r, 168, 156, 168, 204);
  _ar(c, p, 168, 180, 168, 204, _C.red, 6);
  _ln(c, b, 132, 204, 132, 156);
  _ar(c, p, 132, 180, 132, 158, _C.blue, 6);
  _t(
    c,
    p,
    'Akciğer atardamarı\n(kirli kan)',
    122,
    76,
    size: 7.5,
    a: 'right',
    col: _C.blue,
  );
  _t(
    c,
    p,
    'Akciğer toplardamarı\n(temiz kan)',
    178,
    76,
    size: 7.5,
    a: 'left',
    col: _C.red,
  );
  _t(c, p, 'Aort\n(temiz kan)', 176, 184, size: 7.5, a: 'left', col: _C.red);
  _t(
    c,
    p,
    'Ana toplardamar\n(kirli kan)',
    124,
    184,
    size: 7.5,
    a: 'right',
    col: _C.blue,
  );
  _t(c, p, 'KÜÇÜK DOLAŞIM', 280, 36, size: 9, bold: true, col: _C.purple);
  _t(c, p, 'BÜYÜK DOLAŞIM', 280, 222, size: 9, bold: true, col: _C.purple);
  _t(c, p, 'Kalp → akciğer → kalp', 280, 50, size: 8);
  _t(c, p, 'Kalp → vücut → kalp', 280, 236, size: 8);
}

void _respiratory(Canvas c, WbArtPen p) {
  final lungL = Path()
    ..moveTo(115, 80)
    ..cubicTo(60, 70, 40, 150, 62, 195)
    ..cubicTo(80, 215, 112, 205, 118, 180)
    ..close();
  final lungR = Path()
    ..moveTo(145, 80)
    ..cubicTo(200, 70, 220, 150, 198, 195)
    ..cubicTo(180, 215, 148, 205, 142, 180)
    ..close();
  _pf(c, p, lungL, _C.pink, .35);
  _pf(c, p, lungR, _C.pink, .35);
  _rr(c, p, 124, 30, 12, 55, 4, _C.gray, .5);
  for (int i = 0; i < 5; i++) {
    _ln(c, p.thin(.5), 124, 38.0 + i * 10, 136, 38.0 + i * 10);
  }
  final br = p.stroke(_C.gray, 1.3);
  c.drawPath(
    Path()
      ..moveTo(130, 85)
      ..lineTo(108, 110)
      ..lineTo(88, 140),
    br,
  );
  c.drawPath(
    Path()
      ..moveTo(108, 110)
      ..lineTo(100, 100),
    br,
  );
  c.drawPath(
    Path()
      ..moveTo(98, 126)
      ..lineTo(78, 126),
    br,
  );
  c.drawPath(
    Path()
      ..moveTo(130, 85)
      ..lineTo(152, 110)
      ..lineTo(172, 140),
    br,
  );
  c.drawPath(
    Path()
      ..moveTo(152, 110)
      ..lineTo(160, 100),
    br,
  );
  c.drawPath(
    Path()
      ..moveTo(162, 126)
      ..lineTo(182, 126),
    br,
  );
  for (final d in [
    const Offset(88, 140),
    const Offset(78, 126),
    const Offset(100, 100),
    const Offset(172, 140),
    const Offset(182, 126),
    const Offset(160, 100),
  ]) {
    for (int k = 0; k < 3; k++) {
      _ci(c, p, d.dx + (k - 1) * 4, d.dy + (k == 1 ? 4 : 0), 3.2, _C.red, .45);
    }
  }
  c.drawPath(
    Path()
      ..moveTo(52, 222)
      ..quadraticBezierTo(130, 188, 208, 222),
    p.stroke(_C.brown, 1.8),
  );
  _t(c, p, 'Burun / ağız boşluğu', 130, 8, size: 8.5, bold: true);
  _ld(c, p, 'Gırtlak', 124, 36, 60, 24, a: 'right');
  _ld(c, p, 'Soluk borusu\n(trake)', 124, 66, 60, 56, a: 'right');
  _ld(c, p, 'Bronş', 114, 104, 40, 90, a: 'right');
  _ld(c, p, 'Bronşçuk', 90, 126, 30, 118, a: 'right');
  _ld(c, p, 'Alveol\n(gaz alışverişi)', 82, 144, 36, 160, a: 'right');
  _ld(c, p, 'Akciğer', 190, 150, 222, 140);
  _ld(c, p, 'Diyafram', 205, 215, 224, 232);
}

void _digestive(Canvas c, WbArtPen p) {
  _el(c, p, 130, 10, 14, 6, _C.red, .4);
  _t(c, p, 'Ağız', 160, 10, size: 8.5, a: 'left');
  c.drawPath(
    Path()
      ..moveTo(130, 16)
      ..lineTo(130, 78)
      ..quadraticBezierTo(130, 86, 138, 90),
    p.stroke(_C.orange, 5),
  );
  _el(c, p, 100, 92, 34, 22, _C.brown, .35);
  final st = Path()
    ..moveTo(130, 82)
    ..cubicTo(175, 80, 190, 110, 160, 125)
    ..cubicTo(140, 132, 128, 112, 125, 100)
    ..close();
  _pf(c, p, st, _C.pink, .4);
  _el(c, p, 158, 143, 22, 7, _C.yellow, .5);
  _rr(c, p, 75, 130, 110, 80, 14, _C.orange, .1);
  final si = Path()..moveTo(105, 150);
  for (int i = 0; i < 4; i++) {
    final y = 150.0 + i * 14;
    si.quadraticBezierTo(130, y + 7, 155, y);
    si.quadraticBezierTo(165, y + 7, 155, y + 14);
    si.quadraticBezierTo(130, y + 21, 105, y + 14);
    si.quadraticBezierTo(95, y + 7, 105, y + 14);
  }
  c.drawPath(si, p.stroke(_C.pink, 1.4));
  final li = Path()
    ..moveTo(90, 220)
    ..lineTo(90, 135)
    ..lineTo(175, 135)
    ..lineTo(175, 218)
    ..lineTo(145, 218);
  c.drawPath(li, p.stroke(_C.brown, 4));
  _ld(c, p, 'Yemek borusu', 130, 50, 190, 40);
  _ld(c, p, 'Karaciğer', 95, 88, 40, 66, a: 'right');
  _ld(c, p, 'Mide', 165, 95, 205, 78);
  _ld(c, p, 'Pankreas', 158, 143, 210, 126);
  _ld(c, p, 'İnce bağırsak', 105, 165, 30, 168, a: 'right');
  _ld(c, p, 'Kalın bağırsak', 175, 190, 200, 190);
  _ld(c, p, 'Rektum – anüs', 145, 218, 195, 232);
  _t(c, p, 'Sindirim sistemi', 130, 252, size: 9, bold: true);
}

void _kidney(Canvas c, WbArtPen p) {
  final k = Path()
    ..moveTo(70, 30)
    ..cubicTo(20, 30, 10, 120, 60, 150)
    ..cubicTo(80, 160, 70, 130, 75, 120)
    ..cubicTo(80, 100, 100, 110, 100, 90)
    ..cubicTo(100, 60, 110, 30, 70, 30)
    ..close();
  _pf(c, p, k, _C.red, .3);
  _ci(c, p, 80, 95, 12, _C.yellow, .4);
  c.drawPath(
    Path()
      ..moveTo(78, 150)
      ..quadraticBezierTo(90, 190, 78, 230),
    p.stroke(_C.yellow, 4),
  );
  c.drawPath(
    Path()
      ..moveTo(130, 30)
      ..lineTo(130, 20),
    p.thin(),
  );
  _ld(c, p, 'Böbrek\n(korteks/medulla)', 40, 70, 8, 12, a: 'left');
  _ld(c, p, 'Böbrek\nhavuzcuğu', 82, 97, 8, 182, a: 'left');
  _ld(c, p, 'Üreter', 82, 200, 8, 224, a: 'left');
  _ci(c, p, 220, 55, 14, _C.red, .25);
  c.drawPath(
    WbArtPen.arc(const Offset(220, 55), 20, 140, 260),
    p.stroke(_C.purple, 1.4),
  );
  c.drawPath(
    Path()
      ..moveTo(205, 55)
      ..cubicTo(215, 40, 225, 70, 235, 50),
    p.stroke(_C.red, 1.2),
  );
  final tub = Path()
    ..moveTo(236, 62)
    ..cubicTo(250, 70, 235, 85, 250, 92)
    ..cubicTo(265, 98, 245, 112, 262, 118)
    ..lineTo(262, 195)
    ..quadraticBezierTo(262, 215, 282, 215)
    ..lineTo(282, 130)
    ..cubicTo(282, 118, 300, 110, 305, 90)
    ..cubicTo(310, 70, 330, 60, 320, 40);
  c.drawPath(tub, p.stroke(_C.yellow, 1.6));
  c.drawPath(
    Path()
      ..moveTo(320, 40)
      ..lineTo(320, 215),
    p.stroke(_C.orange, 3),
  );
  _ld(c, p, 'Glomerulus', 215, 52, 160, 24, a: 'center');
  _ld(c, p, 'Bowman kapsülü', 205, 68, 160, 90, a: 'center');
  _ld(c, p, 'Proksimal tüp', 250, 92, 330, 80);
  _ld(c, p, 'Henle kulpu', 272, 215, 220, 232, a: 'center');
  _ld(c, p, 'Distal tüp', 300, 98, 335, 54, a: 'left');
  _ld(c, p, 'Toplama kanalı', 320, 170, 335, 190);
  _t(
    c,
    p,
    'Süzülme · Geri emilim · Salgılama',
    220,
    252,
    size: 8.5,
    bold: true,
  );
}

void _neuron(Canvas c, WbArtPen p) {
  final soma = Path()
    ..addOval(
      Rect.fromCenter(center: const Offset(80, 90), width: 56, height: 50),
    );
  _pf(c, p, soma, _C.purple, .25);
  _ci(c, p, 80, 90, 9, _C.purple, .5);
  for (final a in [-2.6, -2.1, -3.2, 2.5, 2.0, -1.6]) {
    final ex = 80 + 55 * math.cos(a);
    final ey = 90 + 55 * math.sin(a);
    c.drawPath(
      Path()
        ..moveTo(80 + 25 * math.cos(a), 90 + 24 * math.sin(a))
        ..lineTo(ex, ey),
      p.stroke(_C.purple, 1.2),
    );
    c.drawPath(
      Path()
        ..moveTo(ex, ey)
        ..lineTo(ex + 10 * math.cos(a - .5), ey + 10 * math.sin(a - .5)),
      p.thin(),
    );
    c.drawPath(
      Path()
        ..moveTo(ex, ey)
        ..lineTo(ex + 10 * math.cos(a + .5), ey + 10 * math.sin(a + .5)),
      p.thin(),
    );
  }
  _ln(c, p.stroke(_C.purple, 1.3), 108, 90, 345, 90);
  for (int i = 0; i < 5; i++) {
    _rr(c, p, 130.0 + i * 42, 80, 32, 20, 9, _C.yellow, .45);
  }
  for (int i = 0; i < 3; i++) {
    final y = 70.0 + i * 20;
    _ln(c, p.stroke(_C.purple, 1.1), 345, 90, 372, y);
    _ci(c, p, 376, y, 4, _C.orange, .6);
  }
  _ld(c, p, 'Dendrit', 38, 70, 10, 24, a: 'left');
  _ld(c, p, 'Hücre gövdesi', 80, 112, 60, 150, a: 'center');
  _ld(c, p, 'Çekirdek', 80, 90, 80, 24, a: 'center');
  _ld(c, p, 'Akson', 130, 90, 120, 128, a: 'center');
  _ld(c, p, 'Miyelin kılıf\n(Schwann hücresi)', 160, 82, 200, 36, a: 'center');
  _ld(c, p, 'Ranvier\nboğumu', 193, 90, 250, 128, a: 'center');
  _ld(c, p, 'Akson uçları', 376, 70, 340, 40, a: 'center');
  _ar(c, p, 300, 150, 360, 150, _C.gray, 6);
  _t(c, p, 'Uyarı iletimi', 270, 150, size: 8.5, a: 'right');
}

void _eye(Canvas c, WbArtPen p) {
  _ci(c, p, 170, 105, 70, _C.lightBlue, .15);
  final cornea = Path()
    ..moveTo(112, 70)
    ..quadraticBezierTo(70, 105, 112, 140)
    ..quadraticBezierTo(98, 105, 112, 70);
  _pf(c, p, cornea, _C.blue, .35);
  _el(c, p, 130, 105, 7, 22, _C.blue, .45);
  _ln(c, p.stroke(_C.brown, 2.6), 118, 78, 118, 90);
  _ln(c, p.stroke(_C.brown, 2.6), 118, 120, 118, 132);
  c.drawPath(
    WbArtPen.arc(const Offset(170, 105), 66, -55, 110),
    p.stroke(_C.red, 2.4),
  );
  _ln(c, p.stroke(_C.yellow, 4), 232, 118, 285, 135);
  for (int i = -1; i <= 1; i++) {
    _ln(c, p.stroke(_C.orange, .9), 20, 105 + i * 22.0, 125, 105 + i * 8.0);
    _ln(c, p.stroke(_C.orange, .9), 125, 105 + i * 8.0, 224, 110);
  }
  _ld(c, p, 'Kornea', 92, 90, 50, 30, a: 'center');
  _ld(c, p, 'İris', 118, 82, 100, 24, a: 'center');
  _ld(c, p, 'Göz bebeği (pupil)', 118, 105, 40, 190, a: 'left');
  _ld(c, p, 'Mercek (lens)', 130, 90, 150, 28, a: 'center');
  _ld(c, p, 'Sert tabaka (sklera)', 170, 40, 200, 12, a: 'center');
  _ld(c, p, 'Camsı sıvı', 175, 100, 160, 150, a: 'center');
  _ld(c, p, 'Ağ tabaka (retina)', 235, 90, 270, 58, a: 'left');
  _ld(c, p, 'Görme siniri', 280, 133, 285, 165, a: 'center');
  _t(
    c,
    p,
    'Işık ışınları ağ tabakada\nters görüntü oluşturur',
    190,
    195,
    size: 8.5,
  );
}

void _ear(Canvas c, WbArtPen p) {
  final pinna = Path()
    ..moveTo(60, 40)
    ..cubicTo(15, 40, 10, 110, 55, 150)
    ..cubicTo(40, 100, 55, 60, 75, 70);
  _pf(c, p, pinna, _C.pink, .35);
  _rr(c, p, 75, 82, 50, 16, 6, _C.gray, .2);
  _ln(c, p.stroke(_C.red, 2), 125, 70, 125, 110);
  _el(c, p, 144, 76, 5, 3, _C.orange, .7);
  _el(c, p, 158, 80, 5, 4, _C.orange, .7);
  _el(c, p, 170, 86, 4, 3, _C.orange, .7);
  _ln(c, p.thin(.5), 126, 88, 142, 78);
  _ci(c, p, 200, 100, 14, _C.purple, .25);
  for (int i = 0; i < 3; i++) {
    final a = -_pi / 2 + i * 1.7;
    c.drawPath(
      WbArtPen.arc(
        Offset(200 + 14 * math.cos(a), 100 + 14 * math.sin(a)),
        15,
        a * 180 / _pi,
        270,
      ),
      p.stroke(_C.purple, .9),
    );
  }
  final co = Path();
  for (int i = 0; i <= 50; i++) {
    final a = i * .2;
    final r = 4 + a * 3.0;
    final x = 200 + r * math.cos(a + 1);
    final y = 150 + r * math.sin(a + 1);
    if (i == 0) {
      co.moveTo(x, y);
    } else {
      co.lineTo(x, y);
    }
  }
  c.drawPath(co, p.stroke(_C.teal, 1.5));
  c.drawPath(
    Path()
      ..moveTo(170, 160)
      ..lineTo(150, 190)
      ..lineTo(110, 185),
    p.stroke(_C.gray, 3),
  );
  _ln(c, p.stroke(_C.yellow, 2.4), 228, 148, 262, 130);
  _ld(c, p, 'Kulak kepçesi', 30, 70, 6, 20, a: 'left');
  _ld(c, p, 'Kulak yolu', 100, 90, 70, 20, a: 'left');
  _ld(c, p, 'Kulak zarı', 125, 78, 130, 20, a: 'left');
  _ld(c, p, 'Çekiç – örs – üzengi', 158, 80, 190, 30, a: 'left');
  _ld(c, p, 'Yarım daire kanalları', 214, 90, 250, 56, a: 'left');
  _ld(c, p, 'Koklea (salyangoz)', 200, 150, 250, 172, a: 'left');
  _ld(c, p, 'İşitme siniri', 262, 130, 280, 110, a: 'left');
  _ld(c, p, 'Östaki borusu', 110, 185, 60, 200, a: 'center');
  _t(c, p, 'DIŞ KULAK', 50, 8, size: 8, col: _C.gray, bold: true);
  _t(c, p, 'ORTA KULAK', 155, 8, size: 8, col: _C.gray, bold: true);
  _t(c, p, 'İÇ KULAK', 225, 8, size: 8, col: _C.gray, bold: true);
}

void _skin(Canvas c, WbArtPen p) {
  _rr(c, p, 20, 40, 240, 22, 4, _C.pink, .45);
  _rr(c, p, 20, 62, 240, 70, 4, _C.orange, .25);
  _rr(c, p, 20, 132, 240, 60, 4, _C.yellow, .3);
  for (int i = 0; i < 8; i++) {
    _ci(c, p, 40.0 + i * 28, 162.0 + (i.isEven ? 6 : -6), 9, _C.yellow, .5);
  }
  final hair = Path()
    ..moveTo(150, 44)
    ..lineTo(158, 5);
  c.drawPath(hair, p.stroke(Colors.black87, 1.8));
  c.drawPath(
    Path()
      ..moveTo(149, 62)
      ..lineTo(149, 112),
    p.stroke(_C.brown, 3),
  );
  _ci(c, p, 149, 115, 8, _C.brown, .4);
  _el(c, p, 168, 85, 7, 12, _C.yellow, .55);
  final sw = Path()
    ..moveTo(80, 44)
    ..lineTo(80, 80);
  for (int i = 0; i < 6; i++) {
    sw.quadraticBezierTo(70, 86.0 + i * 5, 80, 88.0 + i * 5);
  }
  c.drawPath(sw, p.stroke(_C.blue, 1.3));
  _ci(c, p, 80, 124, 8, _C.blue, .3);
  c.drawPath(
    Path()
      ..moveTo(215, 62)
      ..lineTo(215, 118)
      ..lineTo(200, 140),
    p.stroke(_C.red, 2.5),
  );
  c.drawPath(
    Path()
      ..moveTo(230, 62)
      ..lineTo(230, 130)
      ..lineTo(240, 150),
    p.stroke(_C.blue, 2.5),
  );
  c.drawPath(
    Path()
      ..moveTo(116, 62)
      ..lineTo(116, 120)
      ..lineTo(116, 150),
    p.stroke(_C.green, 1.2),
  );
  _ci(c, p, 116, 74, 4, _C.green, .6);
  _ld(c, p, 'Epidermis', 30, 50, 290, 50);
  _ld(c, p, 'Dermis', 250, 95, 290, 95);
  _ld(c, p, 'Hipodermis\n(yağ dokusu)', 250, 165, 290, 168);
  _ld(c, p, 'Kıl', 156, 18, 200, 14, a: 'left');
  _ld(c, p, 'Yağ bezi', 168, 85, 210, 24, a: 'center');
  _ld(c, p, 'Ter bezi', 80, 124, 30, 214, a: 'center');
  _ld(c, p, 'Kıl kökü', 149, 115, 130, 214, a: 'center');
  _ld(c, p, 'Damar', 215, 100, 250, 214, a: 'center');
  _ld(c, p, 'Duyu reseptörü', 116, 74, 20, 26, a: 'left');
}

void _joints(Canvas c, WbArtPen p) {
  const names = [
    'Küre eklem',
    'Menteşe eklem',
    'Eksen eklem',
    'Kayar eklem',
    'Oynamaz eklem',
  ];
  const ex = [
    '(omuz, kalça)',
    '(dirsek, diz)',
    '(boyun: atlas-eksen)',
    '(bilek, el kemikleri)',
    '(kafatası)',
  ];
  for (int i = 0; i < 5; i++) {
    final x = 45.0 + i * 85;
    switch (i) {
      case 0:
        _rr(c, p, x - 6, 60, 12, 40, 4, _C.gray, .4);
        _ci(c, p, x, 55, 11, _C.gray, .5);
        c.drawPath(
          WbArtPen.arc(Offset(x, 45), 16, 20, 140),
          p.stroke(_C.blue, 1.6),
        );
        _rr(c, p, x - 6, 20, 12, 20, 4, _C.blue, .3);
        break;
      case 1:
        _rr(c, p, x - 6, 20, 12, 38, 4, _C.gray, .4);
        _el(c, p, x, 62, 11, 7, _C.gray, .5);
        _rr(c, p, x - 6, 66, 12, 36, 4, _C.blue, .3);
        _ar(c, p, x + 16, 55, x + 18, 80, _C.red, 4);
        break;
      case 2:
        _rr(c, p, x - 5, 16, 10, 60, 4, _C.gray, .4);
        _ci(c, p, x, 78, 14, _C.blue, .3);
        _rr(c, p, x - 4, 70, 8, 30, 3, _C.gray, .55);
        _carc(c, p, x, 78, 20, -20, 150, _C.red, w: .9);
        break;
      case 3:
        _rr(c, p, x - 20, 55, 40, 12, 3, _C.gray, .4);
        _rr(c, p, x - 20, 68, 40, 12, 3, _C.blue, .3);
        _ar(c, p, x - 22, 60, x - 6, 60, _C.red, 4);
        _ar(c, p, x + 22, 74, x + 6, 74, _C.red, 4);
        break;
      default:
        _rr(c, p, x - 24, 55, 24, 26, 8, _C.gray, .4);
        _rr(c, p, x, 55, 24, 26, 8, _C.blue, .3);
        final z = Path()
          ..moveTo(x, 56)
          ..lineTo(x + 3, 62)
          ..lineTo(x - 3, 68)
          ..lineTo(x + 3, 74)
          ..lineTo(x, 80);
        c.drawPath(z, p.stroke(_C.red, 1.2));
    }
    _t(c, p, names[i], x, 125, size: 8.5, bold: true);
    _t(c, p, ex[i], x, 140, size: 7.5, col: _C.gray);
  }
  _t(c, p, 'Eklem türleri', 220, 175, size: 9, bold: true);
}

void _muscle(Canvas c, WbArtPen p) {
  _rr(c, p, 40, 76, 120, 12, 6, _C.gray, .3);
  _ci(c, p, 165, 82, 10, _C.gray, .3);
  _rel(c, p, 215, 90, 55, 6, .3, _C.gray, .3);
  _rr(c, p, 40, 100, 0, 0, 0, _C.gray, 0);
  final bi = Path()
    ..moveTo(45, 70)
    ..cubicTo(80, 25, 120, 30, 160, 68)
    ..cubicTo(120, 52, 80, 52, 45, 70);
  _pf(c, p, bi, _C.red, .4);
  final tr = Path()
    ..moveTo(45, 92)
    ..cubicTo(80, 140, 130, 140, 166, 94)
    ..cubicTo(120, 112, 80, 110, 45, 92);
  _pf(c, p, tr, _C.blue, .35);
  _ln(c, p.stroke(_C.gray, 1.4), 160, 68, 190, 80);
  _ln(c, p.stroke(_C.gray, 1.4), 166, 94, 160, 94);
  _ld(c, p, 'Pazı kası\n(biseps)', 90, 38, 60, 8, a: 'center');
  _ld(c, p, 'Arka kol kası\n(triseps)', 100, 128, 60, 168, a: 'center');
  _ld(c, p, 'Kemik', 60, 82, 10, 60, a: 'left');
  _ld(c, p, 'Tendon', 178, 74, 220, 46, a: 'left');
  _ld(c, p, 'Dirsek eklemi', 165, 82, 210, 132, a: 'left');
  _ld(c, p, 'Ön kol kemikleri', 240, 98, 230, 160, a: 'center');
  _t(
    c,
    p,
    'Biseps kasılınca triseps gevşer\n(antagonist kaslar)',
    150,
    200,
    size: 8.5,
    bold: true,
  );
}

void _foodChain(Canvas c, WbArtPen p) {
  const names = ['Ot', 'Çekirge', 'Kurbağa', 'Yılan', 'Kartal'];
  const roles = [
    'Üretici',
    '1. tüketici\n(otçul)',
    '2. tüketici\n(etçil)',
    '3. tüketici',
    '4. tüketici',
  ];
  final cols = [_C.green, _C.yellow, _C.teal, _C.orange, _C.brown];
  for (int i = 0; i < 5; i++) {
    final x = 36.0 + i * 82;
    _ci(c, p, x, 55, 24, cols[i], .3);
    switch (i) {
      case 0:
        for (int k = -2; k <= 2; k++) {
          _ln(
            c,
            p.stroke(_C.darkGreen, 1.4),
            x + k * 5.0,
            68,
            x + k * 8.0,
            44 - (k.abs()) * 2.0,
          );
        }
        break;
      case 1:
        _el(c, p, x, 55, 13, 5, _C.green, .6);
        _ln(c, p.thin(), x - 4, 58, x - 12, 70);
        _ln(c, p.thin(), x + 4, 58, x + 12, 70);
        _dot(c, p, x + 11, 52, 1.8, p.color);
        break;
      case 2:
        _el(c, p, x, 58, 14, 9, _C.green, .6);
        _dot(c, p, x - 6, 48, 3, _C.green);
        _dot(c, p, x + 6, 48, 3, _C.green);
        _dot(c, p, x - 6, 48, 1.2, p.color);
        _dot(c, p, x + 6, 48, 1.2, p.color);
        break;
      case 3:
        c.drawPath(
          Path()
            ..moveTo(x - 14, 62)
            ..quadraticBezierTo(x - 6, 40, x, 56)
            ..quadraticBezierTo(x + 6, 72, x + 14, 48),
          p.stroke(_C.green, 3),
        );
        _dot(c, p, x + 15, 47, 2, p.color);
        break;
      default:
        _pg(
          c,
          p,
          [
            Offset(x - 18, 50),
            Offset(x, 60),
            Offset(x + 18, 50),
            Offset(x, 40),
          ],
          _C.brown,
          .5,
        );
        _pg(
          c,
          p,
          [Offset(x + 6, 46), Offset(x + 16, 50), Offset(x + 8, 52)],
          _C.yellow,
          .8,
        );
    }
    _t(c, p, names[i], x, 92, size: 9.5, bold: true);
    _t(c, p, roles[i], x, 116, size: 8, col: _C.gray);
    if (i < 4) _ar(c, p, x + 26, 55, x + 56, 55, _C.red, 6);
  }
  _t(
    c,
    p,
    'Ok yönü: enerji akışı (yenen → yiyen)',
    210,
    150,
    size: 9,
    bold: true,
  );
}

void _foodPyramid(Canvas c, WbArtPen p) {
  const names = [
    '3. tüketici\n(%0,1)',
    '2. tüketici\n(%1)',
    '1. tüketici\n(%10)',
    'Üreticiler\n(%100)',
  ];
  final cols = [_C.red, _C.orange, _C.yellow, _C.green];
  const apexX = 130.0;
  for (int i = 0; i < 4; i++) {
    final top = 20.0 + i * 52;
    final bot = top + 50;
    final wt = (top - 10) * .75;
    final wb = (bot - 10) * .75;
    _pg(
      c,
      p,
      [
        Offset(apexX - wt, top),
        Offset(apexX + wt, top),
        Offset(apexX + wb, bot),
        Offset(apexX - wb, bot),
      ],
      cols[i],
      .4,
    );
    _t(c, p, names[i], apexX, top + 25, size: 8.5, bold: true);
  }
  _ar(c, p, 250, 220, 250, 25, _C.gray, 6);
  _t(c, p, 'Enerji\nazalır', 270, 120, size: 8.5, col: _C.gray, a: 'left');
  _t(
    c,
    p,
    'Her basamakta enerjinin yaklaşık %10\'u bir üst basamağa geçer',
    150,
    240,
    size: 8.5,
  );
}

void _foodWeb(Canvas c, WbArtPen p) {
  final nodes = <String, Offset>{
    'Ot': const Offset(60, 200),
    'Tohum': const Offset(150, 205),
    'Çekirge': const Offset(50, 130),
    'Fare': const Offset(150, 140),
    'Tavşan': const Offset(235, 150),
    'Kurbağa': const Offset(50, 70),
    'Yılan': const Offset(125, 70),
    'Tilki': const Offset(240, 80),
    'Kartal': const Offset(170, 20),
  };
  const links = [
    ['Ot', 'Çekirge'],
    ['Ot', 'Fare'],
    ['Ot', 'Tavşan'],
    ['Tohum', 'Fare'],
    ['Çekirge', 'Kurbağa'],
    ['Kurbağa', 'Yılan'],
    ['Fare', 'Yılan'],
    ['Fare', 'Tilki'],
    ['Tavşan', 'Tilki'],
    ['Yılan', 'Kartal'],
    ['Tavşan', 'Kartal'],
  ];
  for (final l in links) {
    final a = nodes[l[0]]!;
    final b = nodes[l[1]]!;
    final d = (b - a);
    final u = d / d.distance;
    p.arrow(c, a + u * 16, b - u * 18, c: _C.red, size: 5);
  }
  final cols = {'Ot': _C.green, 'Tohum': _C.green};
  nodes.forEach((k, v) {
    _el(
      c,
      p,
      v.dx,
      v.dy,
      22,
      12,
      cols[k] ??
          (k == 'Kartal' || k == 'Tilki' || k == 'Yılan'
              ? _C.orange
              : _C.yellow),
      .45,
    );
    _t(c, p, k, v.dx, v.dy, size: 8.5, bold: true);
  });
  _t(
    c,
    p,
    'Besin ağı: birden çok besin zinciri birbirine bağlı',
    140,
    240,
    size: 8.5,
    bold: true,
  );
}

void _ecosystem(Canvas c, WbArtPen p) {
  _sun(c, p, 40, 36, 16);
  c.drawRect(const Rect.fromLTWH(10, 140, 320, 60), p.fill(_C.brown, .3));
  _ln(c, p.stroke(_C.darkGreen, 1.2), 10, 140, 330, 140);
  final lake = Path()
    ..moveTo(120, 140)
    ..quadraticBezierTo(170, 175, 230, 140)
    ..close();
  _pf(c, p, lake, _C.blue, .45);
  _el(c, p, 175, 152, 8, 3.5, _C.orange, .6);
  _pg(
    c,
    p,
    [const Offset(183, 152), const Offset(190, 147), const Offset(190, 157)],
    _C.orange,
    .6,
  );
  _rr(c, p, 275, 85, 10, 55, 2, _C.brown, .5);
  _ci(c, p, 280, 70, 28, _C.green, .5);
  for (int i = 0; i < 9; i++) {
    final x = 20.0 + i * 12;
    _ln(c, p.stroke(_C.darkGreen, 1), x, 140, x - 2, 128);
    _ln(c, p.stroke(_C.darkGreen, 1), x, 140, x + 3, 126);
  }
  _el(c, p, 85, 125, 14, 8, _C.gray, .5);
  _dot(c, p, 96, 118, 4, _C.gray, .8);
  _ln(c, p.thin(), 76, 132, 76, 140);
  _ln(c, p.thin(), 92, 132, 92, 140);
  c.drawPath(
    Path()
      ..moveTo(200, 50)
      ..quadraticBezierTo(208, 42, 216, 50)
      ..quadraticBezierTo(224, 42, 232, 50),
    p.line,
  );
  for (int i = 0; i < 4; i++) {
    _el(c, p, 60.0 + i * 55, 178, 6, 2.5, _C.brown, .5);
  }
  _ld(c, p, 'Güneş (abiyotik)', 40, 36, 70, 14, a: 'left');
  _ld(c, p, 'Üretici: ağaç, ot', 282, 60, 300, 12, a: 'right');
  _ld(c, p, 'Tüketici: hayvanlar', 90, 118, 20, 100, a: 'left');
  _ld(c, p, 'Su (abiyotik)', 170, 148, 170, 190, a: 'center');
  _ld(c, p, 'Ayrıştırıcılar (mantar, bakteri)', 60, 178, 200, 215, a: 'center');
  _ld(c, p, 'Toprak (abiyotik)', 290, 165, 270, 190, a: 'center');
  _t(
    c,
    p,
    'Ekosistem = canlılar (biyotik) + cansız çevre (abiyotik)',
    170,
    232,
    size: 8.5,
    bold: true,
  );
}

void _boxNode(
  Canvas c,
  WbArtPen p,
  String s,
  double cx,
  double cy,
  double w,
  double h,
  Color col, {
  double size = 8.5,
}) {
  _rr(c, p, cx - w / 2, cy - h / 2, w, h, 8, col, .3);
  _t(c, p, s, cx, cy, size: size, bold: true);
}

void _carbonCycle(Canvas c, WbArtPen p) {
  _boxNode(c, p, 'Atmosferdeki CO₂', 170, 22, 120, 26, _C.gray);
  _boxNode(c, p, 'Bitkiler', 60, 118, 70, 26, _C.green);
  _boxNode(c, p, 'Hayvanlar', 170, 140, 80, 26, _C.yellow);
  _boxNode(c, p, 'Ölü canlılar\n+ ayrıştırıcılar', 270, 118, 90, 34, _C.brown);
  _boxNode(
    c,
    p,
    'Fosil yakıtlar\n(kömür, petrol)',
    215,
    225,
    110,
    34,
    _C.purple,
  );
  _boxNode(c, p, 'Fabrika / ulaşım\n(yanma)', 80, 225, 100, 34, _C.orange);
  _ar(c, p, 80, 38, 60, 104, _C.green, 6);
  _t(
    c,
    p,
    'Fotosentez',
    40,
    70,
    size: 8.5,
    a: 'right',
    bold: true,
    col: _C.darkGreen,
  );
  _ar(c, p, 150, 108, 70, 130, _C.green, 5);
  _t(c, p, 'Beslenme', 110, 108, size: 8, col: _C.gray);
  _ar(c, p, 170, 127, 170, 40, _C.red, 6);
  _t(c, p, 'Solunum', 176, 84, size: 8.5, a: 'left', bold: true, col: _C.red);
  _ar(c, p, 250, 100, 200, 38, _C.red, 6);
  _t(
    c,
    p,
    'Solunum / çürüme',
    270,
    70,
    size: 8.5,
    a: 'left',
    bold: true,
    col: _C.red,
  );
  _ar(c, p, 75, 132, 105, 205, _C.gray, 5);
  _ar(c, p, 125, 225, 160, 38, _C.red, 4);
  _t(c, p, 'CO₂ salınımı', 105, 160, size: 8, col: _C.red, a: 'right');
  _ar(c, p, 250, 136, 230, 206, _C.gray, 5);
  _t(
    c,
    p,
    'Milyonlarca\nyılda fosilleşme',
    270,
    175,
    size: 8,
    col: _C.gray,
    a: 'left',
  );
  _ar(c, p, 190, 225, 148, 225, _C.orange, 5);
  _t(c, p, 'Karbon döngüsü', 170, 262, size: 9, bold: true);
}

void _nitrogenCycle(Canvas c, WbArtPen p) {
  _boxNode(c, p, 'Atmosferdeki azot (N₂)', 170, 22, 140, 26, _C.gray);
  _boxNode(c, p, 'Bitkiler', 60, 130, 70, 26, _C.green);
  _boxNode(c, p, 'Hayvanlar', 60, 70, 70, 26, _C.yellow);
  _boxNode(c, p, 'Nitrat\n(NO₃⁻)', 180, 130, 70, 32, _C.blue);
  _boxNode(c, p, 'Amonyak\n(NH₃/NH₄⁺)', 290, 130, 80, 32, _C.pink);
  _boxNode(c, p, 'Ayrıştırıcılar', 290, 70, 80, 26, _C.brown);
  _boxNode(
    c,
    p,
    'Azot bağlayan bakteriler\n(baklagil kökleri)',
    120,
    215,
    160,
    34,
    _C.teal,
  );
  _boxNode(c, p, 'Azot gazı salan\nbakteriler', 290, 215, 100, 34, _C.purple);
  _ar(c, p, 110, 144, 70, 128, _C.gray, 0.1);
  _ar(c, p, 144, 130, 98, 130, _C.green, 6);
  _t(c, p, 'Alım', 121, 120, size: 8, col: _C.gray);
  _ar(c, p, 60, 117, 60, 85, _C.green, 6);
  _ar(c, p, 96, 70, 248, 70, _C.red, 4);
  _ar(c, p, 290, 83, 290, 112, _C.gray, 6);
  _ar(c, p, 250, 130, 218, 130, _C.pink, 6);
  _t(c, p, 'Nitrifikasyon', 234, 150, size: 8, col: _C.gray);
  _ar(c, p, 120, 198, 150, 144, _C.teal, 6);
  _ar(c, p, 200, 36, 120, 200, _C.teal, 4);
  _ar(c, p, 210, 142, 262, 200, _C.purple, 5);
  _ar(c, p, 292, 198, 214, 36, _C.purple, 5);
  _t(c, p, 'Azot döngüsü', 170, 252, size: 9, bold: true);
}

void _punnett(Canvas c, WbArtPen p) {
  _t(c, p, 'Anne: Aa × Baba: Aa', 130, 12, size: 9.5, bold: true);
  _t(c, p, 'Anne gametleri', 150, 34, size: 8, col: _C.gray);
  _t(c, p, 'Baba\ngametleri', 28, 112, size: 8, col: _C.gray);
  const gx = 70.0, gy = 58.0, s = 62.0;
  final cols = [_C.green, _C.yellow, _C.yellow, _C.red];
  const gen = ['AA', 'Aa', 'Aa', 'aa'];
  for (int i = 0; i < 4; i++) {
    final x = gx + s * (i % 2);
    final y = gy + s * (i ~/ 2);
    _rr(c, p, x + s + 4 - s, y + 0, 0, 0, 0, cols[i], 0);
  }
  for (int i = 0; i < 4; i++) {
    final x = gx + 14 + s * (i % 2);
    final y = gy + 24 + s * (i ~/ 2);
    c.drawRect(Rect.fromLTWH(x, y, s, s), p.fill(cols[i], .35));
    c.drawRect(Rect.fromLTWH(x, y, s, s), p.line);
    _t(c, p, gen[i], x + s / 2, y + s / 2, size: 15, bold: true);
  }
  _t(c, p, 'A', gx + 14 + s / 2, gy + 12, size: 12, bold: true, col: _C.blue);
  _t(c, p, 'a', gx + 14 + s * 1.5, gy + 12, size: 12, bold: true, col: _C.blue);
  _t(c, p, 'A', gx + 4, gy + 24 + s / 2, size: 12, bold: true, col: _C.pink);
  _t(c, p, 'a', gx + 4, gy + 24 + s * 1.5, size: 12, bold: true, col: _C.pink);
  _t(c, p, 'Genotip: 1 AA : 2 Aa : 1 aa', 130, 210, size: 9, bold: true);
  _t(c, p, 'Fenotip: 3 baskın : 1 çekinik', 130, 226, size: 9, bold: true);
}

void _pedigree(Canvas c, WbArtPen p) {
  void m(double x, double y, bool aff) {
    c.drawRect(
      Rect.fromCenter(center: Offset(x, y), width: 24, height: 24),
      p.fill(aff ? p.color : Colors.white, aff ? .8 : .0),
    );
    c.drawRect(
      Rect.fromCenter(center: Offset(x, y), width: 24, height: 24),
      p.line,
    );
  }

  void f(double x, double y, bool aff) {
    c.drawCircle(
      Offset(x, y),
      12,
      p.fill(aff ? p.color : Colors.white, aff ? .8 : .0),
    );
    c.drawCircle(Offset(x, y), 12, p.line);
  }

  // I. kuşak
  m(80, 30, false);
  f(140, 30, true);
  _ln(c, p.line, 92, 30, 128, 30);
  _ln(c, p.line, 110, 30, 110, 70);
  _ln(c, p.line, 50, 70, 170, 70);
  // II. kuşak
  for (final x in [50.0, 110.0, 170.0]) {
    _ln(c, p.line, x, 70, x, 82);
  }
  f(50, 94, false);
  m(110, 94, true);
  f(170, 94, true);
  m(230, 94, false);
  _ln(c, p.line, 122, 94, 158, 94);
  _ln(c, p.line, 182, 94, 218, 94);
  _ln(c, p.line, 140, 94, 140, 134);
  _ln(c, p.line, 110, 134, 170, 134);
  _ln(c, p.line, 200, 94, 200, 134);
  _ln(c, p.line, 200, 134, 200, 134);
  for (final x in [110.0, 170.0]) {
    _ln(c, p.line, x, 134, x, 146);
  }
  m(110, 158, false);
  f(170, 158, true);
  _ln(c, p.line, 200, 94, 200, 124);
  m(200, 136, false);
  _t(c, p, 'I', 12, 30, size: 10, bold: true, col: _C.gray);
  _t(c, p, 'II', 12, 94, size: 10, bold: true, col: _C.gray);
  _t(c, p, 'III', 12, 158, size: 10, bold: true, col: _C.gray);
  _rr(c, p, 245, 150, 12, 12, 0, _C.gray, .0);
  c.drawRect(const Rect.fromLTWH(245, 20, 12, 12), p.line);
  c.drawCircle(const Offset(251, 48), 6, p.line);
  c.drawRect(const Rect.fromLTWH(245, 62, 12, 12), p.solid);
  _t(c, p, 'Erkek', 262, 26, size: 8, a: 'left');
  _t(c, p, 'Kadın', 262, 48, size: 8, a: 'left');
  _t(c, p, 'Etkilenen\nbireyler (dolu)', 262, 76, size: 8, a: 'left');
  _t(c, p, 'Soy ağacı (pedigri)', 150, 195, size: 9, bold: true);
}

void _classification(Canvas c, WbArtPen p) {
  const tr = ['Âlem', 'Şube', 'Sınıf', 'Takım', 'Aile', 'Cins', 'Tür'];
  const ex = [
    'Hayvanlar',
    'Kordalılar',
    'Memeliler',
    'Etçiller',
    'Kedigiller',
    'Felis',
    'Felis catus (ev kedisi)',
  ];
  final cols = [
    _C.red,
    _C.orange,
    _C.yellow,
    _C.green,
    _C.teal,
    _C.blue,
    _C.purple,
  ];
  for (int i = 0; i < 7; i++) {
    final top = 12.0 + i * 34;
    final w1 = 130 - i * 15.0;
    final w2 = 130 - (i + 1) * 15.0;
    _pg(
      c,
      p,
      [
        Offset(150 - w1, top),
        Offset(150 + w1, top),
        Offset(150 + w2, top + 32),
        Offset(150 - w2, top + 32),
      ],
      cols[i],
      .35,
    );
    _t(c, p, tr[i], 150, top + 16, size: 9.5, bold: true);
    _t(c, p, ex[i], 296, top + 16, size: 8.5, a: 'right', col: _C.gray);
  }
  _ar(c, p, 14, 16, 14, 240, _C.gray, 5);
  _t(c, p, 'Ortak özellik\nartar', 12, 252, size: 7.5, a: 'left', col: _C.gray);
}

void _evolution(Canvas c, WbArtPen p) {
  final pen = p.stroke(_C.brown, 2);
  c.drawPath(
    Path()
      ..moveTo(150, 230)
      ..lineTo(150, 170),
    pen,
  );
  final names = <String>[
    'Balıklar',
    'Amfibiler',
    'Sürüngenler',
    'Kuşlar',
    'Memeliler',
  ];
  c.drawPath(
    Path()
      ..moveTo(150, 190)
      ..lineTo(40, 150)
      ..lineTo(40, 60),
    pen,
  );
  c.drawPath(
    Path()
      ..moveTo(150, 190)
      ..lineTo(260, 150)
      ..lineTo(260, 120),
    pen,
  );
  c.drawPath(
    Path()
      ..moveTo(40, 140)
      ..lineTo(100, 110)
      ..lineTo(100, 60),
    pen,
  );
  c.drawPath(
    Path()
      ..moveTo(100, 110)
      ..lineTo(150, 90)
      ..lineTo(150, 60),
    pen,
  );
  c.drawPath(
    Path()
      ..moveTo(150, 90)
      ..lineTo(200, 100)
      ..lineTo(200, 60),
    pen,
  );
  c.drawPath(
    Path()
      ..moveTo(200, 100)
      ..lineTo(260, 120),
    pen,
  );
  c.drawPath(
    Path()
      ..moveTo(150, 90)
      ..lineTo(110, 78),
    pen,
  );
  final xs = [40.0, 100.0, 150.0, 200.0, 260.0];
  final ys = [60.0, 60.0, 60.0, 60.0, 120.0];
  final cols = [_C.blue, _C.green, _C.orange, _C.pink, _C.purple];
  for (int i = 0; i < 5; i++) {
    _ci(c, p, xs[i], ys[i], 5, cols[i], .8);
    _t(c, p, names[i], xs[i], ys[i] - 14, size: 8.5, bold: true);
  }
  _ci(c, p, 150, 232, 6, _C.red, .8);
  _t(c, p, 'Ortak ata', 150, 246, size: 8.5, bold: true);
  _t(c, p, 'Zaman ↑', 296, 200, size: 8.5, col: _C.gray, a: 'right');
  _t(c, p, 'Evrim ağacı (filogenetik ağaç)', 150, 270, size: 9, bold: true);
}

// ───────────────────────── DÜNYA VE UZAY ─────────────────────────

void _solarSystem(Canvas c, WbArtPen p) {
  const cx = 160.0, cy = 160.0;
  _sun(c, p, cx, cy, 16);
  const names = [
    'Merkür',
    'Venüs',
    'Dünya',
    'Mars',
    'Jüpiter',
    'Satürn',
    'Uranüs',
    'Neptün',
  ];
  const radii = [28.0, 40.0, 54.0, 68.0, 88.0, 108.0, 126.0, 144.0];
  const sizes = [3.0, 4.5, 4.8, 3.8, 10.0, 8.5, 6.0, 6.0];
  const angs = [-0.9, 0.5, 2.2, -2.4, 0.9, -1.5, 2.9, -0.3];
  final cols = [
    _C.gray,
    _C.orange,
    _C.blue,
    _C.red,
    _C.brown,
    _C.yellow,
    _C.teal,
    _C.purple,
  ];
  for (int i = 0; i < 8; i++) {
    c.drawCircle(const Offset(cx, cy), radii[i], p.thin(.35));
    final x = cx + radii[i] * math.cos(angs[i]);
    final y = cy + radii[i] * math.sin(angs[i]);
    _ci(c, p, x, y, sizes[i], cols[i], .75);
    if (i == 5) {
      c.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: 26, height: 7),
        p.stroke(_C.orange, .5),
      );
    }
    final dx = math.cos(angs[i]) >= 0 ? 1.0 : -1.0;
    _t(
      c,
      p,
      names[i],
      x + dx * (sizes[i] + 3),
      y + (i < 4 ? 8 : 0),
      size: 7.5,
      a: dx > 0 ? 'left' : 'right',
      bold: true,
    );
  }
  _t(c, p, 'Güneş', cx, cy + 25, size: 8, bold: true);
  _t(c, p, 'Güneş sistemi (orantılı değil)', 160, 318, size: 9, bold: true);
}

void _moonShape(
  Canvas c,
  WbArtPen p,
  double cx,
  double cy,
  double r,
  double f,
) {
  c.drawCircle(Offset(cx, cy), r, p.fill(_C.gray, .45));
  final s = f < .5 ? 1.0 : -1.0;
  final k = math.cos(2 * _pi * f);
  final pts = <Offset>[];
  for (int i = 0; i <= 24; i++) {
    final t = -_pi / 2 + i * _pi / 24;
    pts.add(Offset(cx + s * r * math.cos(t), cy + r * math.sin(t)));
  }
  for (int i = 24; i >= 0; i--) {
    final t = -_pi / 2 + i * _pi / 24;
    pts.add(Offset(cx + s * r * k * math.cos(t), cy + r * math.sin(t)));
  }
  if (f > .02 && f < .98) c.drawPath(WbArtPen.poly(pts), p.fill(_C.yellow, .9));
  c.drawCircle(Offset(cx, cy), r, p.line);
}

void _moonPhases(Canvas c, WbArtPen p) {
  const names = [
    'Yeni Ay',
    'Hilal\n(büyüyen)',
    'İlk dördün',
    'Şişkin Ay\n(büyüyen)',
    'Dolunay',
    'Şişkin Ay\n(küçülen)',
    'Son dördün',
    'Hilal\n(küçülen)',
  ];
  for (int i = 0; i < 8; i++) {
    final x = 32.0 + i * 52;
    _moonShape(c, p, x, 40, 20, i / 8);
    _t(c, p, names[i], x, 82, size: 7.5, bold: true);
  }
  _ar(c, p, 20, 112, 400, 112, _C.gray, 6);
  _t(
    c,
    p,
    'Ay yaklaşık 29,5 günde evrelerini tamamlar',
    210,
    130,
    size: 9,
    bold: true,
  );
}

void _earthBall(
  Canvas c,
  WbArtPen p,
  double cx,
  double cy,
  double r,
  double sunAng, {
  double tilt = .41,
}) {
  _ci(c, p, cx, cy, r, _C.blue, .3);
  c.drawArc(
    Rect.fromCircle(center: Offset(cx, cy), radius: r),
    sunAng + _pi / 2,
    _pi,
    true,
    p.fill(Colors.black, .28),
  );
  _rot(c, cx, cy, tilt, () {
    _ln(c, p.stroke(_C.red, .9), cx, cy - r - 6, cx, cy + r + 6);
  });
}

void _seasons(Canvas c, WbArtPen p) {
  const cx = 190.0, cy = 125.0;
  _sun(c, p, cx, cy, 20);
  _t(c, p, 'Güneş', cx, cy + 36, size: 8.5, bold: true);
  c.drawOval(
    Rect.fromCenter(center: const Offset(cx, cy), width: 300, height: 170),
    p.thin(.5),
  );
  _earthBall(c, p, cx - 150, cy, 13, 0);
  _earthBall(c, p, cx + 150, cy, 13, _pi);
  _earthBall(c, p, cx, cy - 85, 13, _pi / 2);
  _earthBall(c, p, cx, cy + 85, 13, -_pi / 2);
  _t(
    c,
    p,
    '21 Haziran\nKuzey yarımkürede YAZ',
    cx - 150,
    cy + 40,
    size: 8,
    bold: true,
  );
  _t(
    c,
    p,
    '21 Aralık\nKuzey yarımkürede KIŞ',
    cx + 150,
    cy + 40,
    size: 8,
    bold: true,
  );
  _t(
    c,
    p,
    '21 Mart\nİlkbahar',
    cx + 70,
    cy - 85,
    size: 8,
    bold: true,
    a: 'left',
  );
  _t(
    c,
    p,
    '23 Eylül\nSonbahar',
    cx + 70,
    cy + 85,
    size: 8,
    bold: true,
    a: 'left',
  );
  _t(c, p, 'Eksen eğikliği 23,5°', 190, 235, size: 9, bold: true);
}

void _dayNight(Canvas c, WbArtPen p) {
  _sun(c, p, 40, 90, 24);
  for (int i = -2; i <= 2; i++) {
    _ar(c, p, 75, 90 + i * 22.0, 170, 90 + i * 14.0, _C.yellow, 6);
  }
  _ci(c, p, 240, 90, 62, _C.blue, .3);
  c.drawPath(
    WbArtPen.arc(const Offset(240, 90), 62, -90, 180),
    p.fill(Colors.black, .3),
  );
  _rot(c, 240, 90, .41, () => _ln(c, p.stroke(_C.red, 1), 240, 14, 240, 166));
  _carc(c, p, 240, 90, 74, 200, 60, _C.green, w: 1.2);
  _t(c, p, 'GÜNDÜZ', 215, 90, size: 10, bold: true, col: _C.orange);
  _t(c, p, 'GECE', 270, 90, size: 10, bold: true, col: Colors.white);
  _t(c, p, 'Dünya', 240, 172, size: 8.5);
  _t(c, p, 'Dönme yönü', 160, 20, size: 8.5, col: _C.green);
  _t(
    c,
    p,
    'Dünya kendi ekseni etrafında 24 saatte döner',
    180,
    195,
    size: 9,
    bold: true,
  );
}

void _solarEclipse(Canvas c, WbArtPen p) {
  _sun(c, p, 40, 90, 30, rays: false);
  c.drawPath(
    WbArtPen.poly([
      const Offset(210, 82),
      const Offset(335, 90 - 10),
      const Offset(335, 90 + 10),
      const Offset(210, 98),
    ]),
    p.fill(Colors.black, .4),
  );
  c.drawPath(
    WbArtPen.poly([
      const Offset(210, 80),
      const Offset(335, 40),
      const Offset(335, 140),
      const Offset(210, 100),
    ]),
    p.fill(Colors.black, .12),
  );
  _ci(c, p, 210, 90, 9, _C.gray, .7);
  _ci(c, p, 350, 90, 22, _C.blue, .3);
  _ln(c, p.thin(.5), 70, 70, 335, 40);
  _ln(c, p.thin(.5), 70, 110, 335, 140);
  _ld(c, p, 'Güneş', 40, 62, 40, 30, a: 'center');
  _ld(c, p, 'Ay (Yeni Ay)', 210, 82, 210, 40, a: 'center');
  _ld(c, p, 'Dünya', 350, 70, 345, 30, a: 'center');
  _ld(c, p, 'Tam gölge\n(umbra)', 300, 90, 300, 150, a: 'center');
  _ld(c, p, 'Yarı gölge\n(penumbra)', 290, 55, 250, 20, a: 'center');
  _t(
    c,
    p,
    'Güneş tutulması: Ay, Güneş ile Dünya arasındadır',
    200,
    185,
    size: 9,
    bold: true,
  );
}

void _lunarEclipse(Canvas c, WbArtPen p) {
  _sun(c, p, 36, 90, 28, rays: false);
  _ci(c, p, 150, 90, 20, _C.blue, .3);
  c.drawPath(
    WbArtPen.poly([
      const Offset(150, 70),
      const Offset(330, 80),
      const Offset(330, 100),
      const Offset(150, 110),
    ]),
    p.fill(Colors.black, .35),
  );
  c.drawPath(
    WbArtPen.poly([
      const Offset(150, 68),
      const Offset(330, 52),
      const Offset(330, 128),
      const Offset(150, 112),
    ]),
    p.fill(Colors.black, .1),
  );
  _ci(c, p, 285, 90, 11, _C.orange, .6);
  _ld(c, p, 'Güneş', 36, 62, 36, 30, a: 'center');
  _ld(c, p, 'Dünya', 150, 70, 150, 30, a: 'center');
  _ld(c, p, 'Ay (Dolunay)', 285, 80, 285, 40, a: 'center');
  _ld(c, p, 'Dünya\'nın gölgesi', 230, 90, 215, 150, a: 'center');
  _t(
    c,
    p,
    'Ay tutulması: Dünya, Güneş ile Ay arasındadır',
    190,
    185,
    size: 9,
    bold: true,
  );
}

void _earthLayers(Canvas c, WbArtPen p) {
  const cx = 120.0, cy = 125.0;
  _ci(c, p, cx, cy, 104, _C.green, .5);
  _ci(c, p, cx, cy, 98, _C.orange, .35);
  _ci(c, p, cx, cy, 58, _C.red, .35);
  _ci(c, p, cx, cy, 28, _C.yellow, .7);
  _ld(c, p, 'Yer kabuğu\n(5–70 km)', 120, 21, 240, 10);
  _ld(c, p, 'Manto\n(yaklaşık 2900 km, yarı akışkan)', 190, 85, 240, 60);
  _ld(c, p, 'Dış çekirdek\n(sıvı)', 150, 140, 240, 120);
  _ld(c, p, 'İç çekirdek\n(katı)', 125, 135, 240, 175);
  _t(c, p, 'Dünya\'nın iç yapısı', 120, 245, size: 9, bold: true);
}

void _plates(Canvas c, WbArtPen p) {
  final mantle = p.fill(_C.orange, .25);
  for (int i = 0; i < 3; i++) {
    c.drawRect(Rect.fromLTWH(10.0 + i * 140, 90, 130, 40), mantle);
  }
  _t(c, p, 'UZAKLAŞAN', 75, 12, size: 9, bold: true);
  _pg(
    c,
    p,
    [
      const Offset(10, 70),
      const Offset(60, 70),
      const Offset(60, 90),
      const Offset(10, 90),
    ],
    _C.brown,
    .4,
  );
  _pg(
    c,
    p,
    [
      const Offset(90, 70),
      const Offset(140, 70),
      const Offset(140, 90),
      const Offset(90, 90),
    ],
    _C.brown,
    .4,
  );
  _pg(
    c,
    p,
    [const Offset(60, 90), const Offset(75, 55), const Offset(90, 90)],
    _C.red,
    .5,
  );
  _ar(c, p, 58, 55, 20, 55, _C.blue, 5);
  _ar(c, p, 92, 55, 130, 55, _C.blue, 5);
  _t(c, p, 'Magma yükselir', 75, 140, size: 8);
  _t(c, p, 'Sırt / yarık vadisi', 75, 152, size: 8, col: _C.gray);
  _t(c, p, 'YAKLAŞAN', 215, 12, size: 9, bold: true);
  _pg(
    c,
    p,
    [
      const Offset(150, 70),
      const Offset(230, 70),
      const Offset(250, 100),
      const Offset(150, 90),
    ],
    _C.blue,
    .35,
  );
  _pg(
    c,
    p,
    [
      const Offset(290, 55),
      const Offset(250, 55),
      const Offset(240, 90),
      const Offset(290, 90),
    ],
    _C.brown,
    .4,
  );
  _pg(
    c,
    p,
    [const Offset(250, 55), const Offset(262, 30), const Offset(278, 55)],
    _C.gray,
    .5,
  );
  _ar(c, p, 160, 50, 200, 50, _C.red, 5);
  _ar(c, p, 290, 40, 250, 40, _C.red, 5);
  _t(c, p, 'Okyanus levhası dalar,\ndağ oluşur', 215, 140, size: 8);
  _t(c, p, 'KAYAN', 355, 12, size: 9, bold: true);
  _rr(c, p, 300, 50, 55, 30, 2, _C.brown, .35);
  _rr(c, p, 358, 50, 55, 30, 2, _C.brown, .35);
  _ar(c, p, 328, 90, 328, 120, _C.red, 5);
  _ar(c, p, 386, 40, 386, 20, _C.red, 5);
  _t(c, p, 'Levhalar yan yana\nters yöne kayar', 355, 140, size: 8);
  _t(c, p, '(kuzeyden bakış)', 355, 170, size: 8, col: _C.gray);
}

void _volcano(Canvas c, WbArtPen p) {
  c.drawRect(const Rect.fromLTWH(10, 160, 300, 70), p.fill(_C.brown, .3));
  final cone = Path()
    ..moveTo(40, 160)
    ..lineTo(125, 62)
    ..lineTo(140, 58)
    ..lineTo(155, 58)
    ..lineTo(170, 62)
    ..lineTo(260, 160)
    ..close();
  _pf(c, p, cone, _C.brown, .45);
  _el(c, p, 148, 215, 50, 18, _C.red, .6);
  c.drawPath(
    Path()
      ..moveTo(148, 200)
      ..lineTo(148, 62),
    p.stroke(_C.red, 7),
  );
  c.drawPath(
    Path()
      ..moveTo(148, 160)
      ..lineTo(190, 120)
      ..lineTo(200, 102),
    p.stroke(_C.orange, 3),
  );
  c.drawPath(
    Path()
      ..moveTo(130, 62)
      ..quadraticBezierTo(100, 90, 85, 130)
      ..quadraticBezierTo(70, 150, 50, 158),
    p.stroke(_C.red, 3),
  );
  for (int i = 0; i < 4; i++) {
    _cloud(c, p, 140.0 + i * 10, 30.0 - i * 4, .6 + i * .15, _C.gray, .5);
  }
  _ci(c, p, 130, 48, 2, _C.red, .8);
  _ci(c, p, 170, 40, 2, _C.red, .8);
  _ld(c, p, 'Krater', 148, 58, 60, 14, a: 'right');
  _ld(c, p, 'Kül ve gaz\nbulutu', 175, 22, 230, 14);
  _ld(c, p, 'Lav akıntısı', 90, 125, 20, 100, a: 'left');
  _ld(c, p, 'Ana bacası', 148, 110, 210, 70);
  _ld(c, p, 'Yan baca', 195, 112, 250, 100);
  _ld(c, p, 'Magma odası', 148, 215, 230, 205);
  _ld(c, p, 'Yer kabuğu', 280, 190, 280, 244, a: 'center');
}

void _earthquake(Canvas c, WbArtPen p) {
  c.drawRect(const Rect.fromLTWH(10, 70, 300, 120), p.fill(_C.brown, .28));
  _ln(c, p.stroke(_C.darkGreen, 1.4), 10, 70, 310, 70);
  _ln(c, p.stroke(_C.red, 1.6), 130, 190, 220, 100);
  _ln(c, p.stroke(_C.red, 1.6), 220, 100, 245, 75);
  for (int i = 1; i <= 4; i++) {
    c.drawPath(
      WbArtPen.arc(const Offset(150, 165), i * 22.0, 205, 130),
      p.stroke(_C.red, .8),
    );
  }
  _dot(c, p, 150, 165, 5, _C.red);
  _ln(c, p.thin(.5), 150, 165, 150, 70);
  _dot(c, p, 150, 70, 5, _C.yellow);
  _ci(c, p, 150, 70, 5, _C.yellow, .9);
  c.drawPath(
    Path()
      ..moveTo(195, 70)
      ..quadraticBezierTo(225, 40, 255, 70),
    p.stroke(_C.orange, 1.2),
  );
  c.drawPath(
    Path()
      ..moveTo(205, 70)
      ..quadraticBezierTo(225, 52, 245, 70),
    p.stroke(_C.orange, 1.2),
  );
  _rr(c, p, 255, 40, 14, 30, 1, _C.gray, .3);
  _rr(c, p, 273, 48, 14, 22, 1, _C.gray, .3);
  _ld(c, p, 'Odak (hiposantr)', 150, 165, 20, 210, a: 'left');
  _ld(c, p, 'Merkez üssü\n(episantr)', 150, 70, 70, 20, a: 'center');
  _ld(c, p, 'Deprem dalgaları', 195, 130, 240, 140);
  _ld(c, p, 'Fay hattı', 175, 140, 100, 150, a: 'right');
  _ld(c, p, 'Yüzey dalgaları', 225, 52, 250, 18, a: 'center');
}

void _rockCycle(Canvas c, WbArtPen p) {
  _boxNode(c, p, 'MAGMA', 170, 30, 90, 28, _C.red);
  _boxNode(c, p, 'Magmatik\nkayaç', 55, 120, 90, 38, _C.orange);
  _boxNode(c, p, 'Tortul\nkayaç', 285, 120, 90, 38, _C.yellow);
  _boxNode(c, p, 'Metamorfik\nkayaç', 170, 220, 100, 38, _C.purple);
  _boxNode(c, p, 'Tortul\n(çökel)', 170, 110, 60, 30, _C.gray, size: 8);
  _ar(c, p, 130, 40, 70, 100, _C.red, 6);
  _t(c, p, 'Soğuma,\nkatılaşma', 80, 55, size: 8, a: 'right');
  _ar(c, p, 102, 118, 136, 112, _C.gray, 5);
  _ar(c, p, 204, 112, 238, 118, _C.gray, 5);
  _t(c, p, 'Aşınma · taşınma · çökelme', 170, 90, size: 8, col: _C.gray);
  _ar(c, p, 285, 142, 215, 205, _C.red, 6);
  _t(c, p, 'Isı ve\nbasınç', 280, 188, size: 8, a: 'left');
  _ar(c, p, 70, 142, 125, 205, _C.red, 6);
  _t(c, p, 'Isı ve basınç', 60, 188, size: 8, a: 'right');
  _ar(c, p, 150, 200, 165, 46, _C.red, 5);
  _t(c, p, 'Erime', 160, 150, size: 8.5, bold: true, col: _C.red, a: 'right');
  _t(c, p, 'Kayaç döngüsü', 170, 262, size: 9, bold: true);
}

void _waterCycle(Canvas c, WbArtPen p) {
  _sun(c, p, 40, 36, 18);
  final sea = Path()
    ..moveTo(10, 190)
    ..lineTo(150, 190)
    ..lineTo(150, 230)
    ..lineTo(10, 230)
    ..close();
  _pf(c, p, sea, _C.blue, .35);
  final mt = Path()
    ..moveTo(150, 190)
    ..lineTo(250, 70)
    ..lineTo(290, 110)
    ..lineTo(320, 85)
    ..lineTo(375, 190)
    ..lineTo(375, 230)
    ..lineTo(150, 230)
    ..close();
  _pf(c, p, mt, _C.brown, .35);
  _pg(
    c,
    p,
    [const Offset(250, 70), const Offset(232, 92), const Offset(268, 92)],
    Colors.white,
    .9,
  );
  c.drawPath(
    Path()
      ..moveTo(240, 100)
      ..quadraticBezierTo(210, 150, 150, 188),
    p.stroke(_C.blue, 2),
  );
  _cloud(c, p, 250, 38, 1.1, _C.gray, .4);
  _cloud(c, p, 120, 52, .9, _C.gray, .3);
  for (int i = 0; i < 5; i++) {
    _ln(c, p.stroke(_C.blue, 1), 235.0 + i * 8, 62, 232.0 + i * 8, 72);
  }
  for (int i = 0; i < 3; i++) {
    _ar(c, p, 50.0 + i * 20, 186, 55.0 + i * 20, 110, _C.orange, 5);
  }
  _ar(c, p, 150, 72, 190, 54, _C.gray, 5);
  _ln(c, p.stroke(_C.darkGreen, 1.4), 330, 150, 330, 180);
  _ci(c, p, 330, 140, 12, _C.green, .5);
  _ar(c, p, 330, 128, 330, 80, _C.green, 4);
  c.drawPath(
    Path()
      ..moveTo(200, 205)
      ..lineTo(100, 215),
    p.stroke(_C.blue, 1.5),
  );
  _ar(c, p, 160, 208, 120, 212, _C.blue, 5);
  _ld(c, p, 'Buharlaşma', 75, 150, 20, 90, a: 'left');
  _ld(c, p, 'Yoğuşma\n(bulut oluşumu)', 150, 62, 100, 10, a: 'left');
  _ld(c, p, 'Yağış', 240, 72, 300, 20);
  _ld(c, p, 'Yüzey akışı', 195, 130, 150, 148, a: 'left');
  _ld(c, p, 'Terleme', 330, 100, 345, 60, a: 'center');
  _ld(c, p, 'Yeraltı suyu\n(sızma)', 200, 205, 260, 245, a: 'center');
  _ld(c, p, 'Kar / buzul', 250, 82, 320, 40, a: 'left');
  _t(c, p, 'Deniz, göl, nehir', 80, 215, size: 8);
}

void _atmosphere(Canvas c, WbArtPen p) {
  final names = [
    'Troposfer',
    'Stratosfer',
    'Mezosfer',
    'Termosfer',
    'Ekzosfer',
  ];
  final km = ['0–12 km', '12–50 km', '50–85 km', '85–600 km', '600 km +'];
  final cols = [_C.blue, _C.teal, _C.purple, _C.pink, _C.gray];
  final alts = [
    'hava olayları, bulutlar',
    'ozon tabakası',
    'meteorlar yanar',
    'kutup ışıkları, uydular',
    'uzaya geçiş',
  ];
  for (int i = 0; i < 5; i++) {
    final y = 205.0 - i * 40;
    _rr(c, p, 70, y - 38, 150, 38, 0, cols[i], .15 + .06 * (4 - i));
    _t(c, p, names[i], 145, y - 24, size: 9.5, bold: true);
    _t(c, p, km[i], 145, y - 10, size: 8, col: _C.gray);
    _t(c, p, alts[i], 228, y - 19, size: 8, a: 'left');
  }
  p.dashed(
    c,
    const Offset(70, 130),
    const Offset(220, 130),
    paint: p.stroke(_C.purple, 1.2),
  );
  _cloud(c, p, 40, 175, .8, _C.lightBlue, .4);
  c.drawPath(
    Path()
      ..moveTo(5, 205)
      ..lineTo(70, 205),
    p.stroke(_C.darkGreen, 2.5),
  );
  _ln(c, p.stroke(_C.orange, 1.2), 100, 80, 118, 98);
  _star(c, p, 100, 80, 3.5, _C.orange);
  _ar(c, p, 30, 30, 30, 5, _C.gray, 5);
  _t(c, p, 'Yükseklik', 30, 44, size: 8, col: _C.gray);
  _t(c, p, 'Yer yüzeyi', 40, 215, size: 8, col: _C.darkGreen);
}

void _seaBreeze(Canvas c, WbArtPen p) {
  for (int k = 0; k < 2; k++) {
    final ox = k * 230.0;
    final sea = Path()
      ..moveTo(ox + 10, 110)
      ..lineTo(ox + 110, 110)
      ..lineTo(ox + 110, 150)
      ..lineTo(ox + 10, 150)
      ..close();
    _pf(c, p, sea, _C.blue, .35);
    _pg(
      c,
      p,
      [
        Offset(ox + 110, 110),
        Offset(ox + 215, 110),
        Offset(ox + 215, 150),
        Offset(ox + 110, 150),
      ],
      _C.brown,
      .35,
    );
    if (k == 0) {
      _sun(c, p, ox + 170, 26, 12);
    } else {
      _ci(c, p, ox + 170, 26, 12, _C.gray, .5);
    }
    final dirR = k == 0;
    // yer yakınında akış
    _ar(
      c,
      p,
      dirR ? ox + 40 : ox + 180,
      96,
      dirR ? ox + 100 : ox + 120,
      96,
      _C.blue,
      6,
    );
    // yükselen hava
    final ux = dirR ? ox + 150 : ox + 60;
    _ar(c, p, ux, 100, ux, 56, _C.red, 6);
    // yüksekte akış
    _ar(
      c,
      p,
      dirR ? ox + 150 : ox + 60,
      50,
      dirR ? ox + 60 : ox + 150,
      50,
      _C.red,
      6,
    );
    // alçalan hava
    final dx = dirR ? ox + 60 : ox + 150;
    _ar(c, p, dx, 54, dx, 94, _C.blue, 6);
    _t(
      c,
      p,
      dirR ? 'Alçak basınç (sıcak kara)' : 'Alçak basınç (sıcak deniz)',
      ux,
      120,
      size: 7.5,
      col: _C.red,
    );
    _t(
      c,
      p,
      dirR ? 'Yüksek basınç (soğuk deniz)' : 'Yüksek basınç (soğuk kara)',
      dx,
      135,
      size: 7.5,
      col: _C.blue,
    );
    _t(c, p, 'DENİZ', ox + 40, 143, size: 8, bold: true, col: _C.blue);
    _t(c, p, 'KARA', ox + 190, 143, size: 8, bold: true, col: _C.brown);
    _t(
      c,
      p,
      dirR ? 'GÜNDÜZ: deniz meltemi' : 'GECE: kara meltemi',
      ox + 110,
      172,
      size: 9,
      bold: true,
    );
  }
}

void _precipitation(Canvas c, WbArtPen p) {
  const names = ['Yağmur', 'Kar', 'Dolu', 'Çisenti / sis'];
  for (int i = 0; i < 4; i++) {
    final x = 55.0 + i * 100;
    _cloud(c, p, x, 40, 1.2, _C.gray, .4);
    switch (i) {
      case 0:
        for (int k = 0; k < 6; k++) {
          _ln(
            c,
            p.stroke(_C.blue, 1.1),
            x - 22 + k * 9.0,
            66 + (k.isOdd ? 8 : 0),
            x - 26 + k * 9.0,
            78 + (k.isOdd ? 8 : 0),
          );
        }
        break;
      case 1:
        for (int k = 0; k < 5; k++) {
          final fx = x - 22 + k * 11.0;
          final fy = 72.0 + (k.isOdd ? 12 : 0);
          for (int a = 0; a < 3; a++) {
            final ang = a * _pi / 3;
            _ln(
              c,
              p.stroke(_C.lightBlue, .6),
              fx - 4 * math.cos(ang),
              fy - 4 * math.sin(ang),
              fx + 4 * math.cos(ang),
              fy + 4 * math.sin(ang),
            );
          }
        }
        break;
      case 2:
        for (int k = 0; k < 5; k++) {
          _ci(
            c,
            p,
            x - 22 + k * 11.0,
            72.0 + (k.isOdd ? 14 : 0),
            3.5,
            _C.lightBlue,
            .7,
          );
        }
        break;
      default:
        for (int k = 0; k < 4; k++) {
          _dot(c, p, x - 18 + k * 12.0, 68 + (k.isOdd ? 8 : 0), 1.3, _C.blue);
        }
        for (int k = 0; k < 3; k++) {
          _ln(
            c,
            p.stroke(_C.gray, .8),
            x - 30,
            98.0 + k * 6,
            x + 30,
            98.0 + k * 6,
          );
        }
    }
    _t(c, p, names[i], x, 112, size: 9, bold: true);
  }
  _t(c, p, 'Yağış türleri', 210, 140, size: 9, col: _C.gray);
}

void _clouds(Canvas c, WbArtPen p) {
  _t(c, p, 'Sirrus', 55, 120, size: 9, bold: true);
  _t(c, p, '(yüksek, ince, buz)', 55, 134, size: 7.5, col: _C.gray);
  for (int i = 0; i < 3; i++) {
    c.drawPath(
      Path()
        ..moveTo(15, 30.0 + i * 12)
        ..quadraticBezierTo(40, 15.0 + i * 12, 95, 36.0 + i * 12),
      p.stroke(_C.lightBlue, 1.2),
    );
  }
  _t(c, p, 'Kümülüs', 155, 120, size: 9, bold: true);
  _t(c, p, '(pamuk gibi, iyi hava)', 155, 134, size: 7.5, col: _C.gray);
  _cloud(c, p, 155, 55, 1.5, _C.lightBlue, .35);
  _t(c, p, 'Stratüs', 255, 120, size: 9, bold: true);
  _t(c, p, '(katman, gri, çise)', 255, 134, size: 7.5, col: _C.gray);
  for (int i = 0; i < 3; i++) {
    _rr(c, p, 205 + i * 4.0, 36.0 + i * 12, 90 - i * 8.0, 10, 5, _C.gray, .35);
  }
  _t(c, p, 'Kümülonimbus', 360, 120, size: 9, bold: true);
  _t(c, p, '(fırtına bulutu)', 360, 134, size: 7.5, col: _C.gray);
  final cb = Path()
    ..moveTo(330, 100)
    ..lineTo(335, 40)
    ..quadraticBezierTo(340, 8, 365, 12)
    ..quadraticBezierTo(400, 4, 405, 30)
    ..lineTo(392, 38)
    ..lineTo(388, 100)
    ..close();
  _pf(c, p, cb, _C.gray, .45);
  for (int i = 0; i < 5; i++) {
    _ln(c, p.stroke(_C.blue, 1), 336 + i * 12.0, 102, 333 + i * 12.0, 112);
  }
  _ln(c, p.stroke(_C.yellow, 1.6), 365, 60, 358, 78);
  _ln(c, p.stroke(_C.yellow, 1.6), 358, 78, 368, 76);
  _ln(c, p.stroke(_C.yellow, 1.6), 368, 76, 360, 96);
}

void _weatherSymbols(Canvas c, WbArtPen p) {
  const names = [
    'Güneşli',
    'Parçalı bulutlu',
    'Bulutlu',
    'Yağmurlu',
    'Karlı',
    'Fırtınalı',
    'Rüzgârlı',
    'Sisli',
  ];
  for (int i = 0; i < 8; i++) {
    final x = 50.0 + (i % 4) * 100;
    final y = 38.0 + (i ~/ 4) * 100;
    switch (i) {
      case 0:
        _sun(c, p, x, y, 14);
        break;
      case 1:
        _sun(c, p, x - 10, y - 8, 11);
        _cloud(c, p, x + 4, y + 6, .9, _C.lightBlue, .6);
        break;
      case 2:
        _cloud(c, p, x, y, 1.2, _C.gray, .4);
        break;
      case 3:
        _cloud(c, p, x, y - 6, 1.1, _C.gray, .4);
        for (int k = 0; k < 4; k++) {
          _ln(
            c,
            p.stroke(_C.blue, 1.2),
            x - 14 + k * 9.0,
            y + 14,
            x - 17 + k * 9.0,
            y + 24,
          );
        }
        break;
      case 4:
        _cloud(c, p, x, y - 6, 1.1, _C.gray, .4);
        for (int k = 0; k < 3; k++) {
          _t(
            c,
            p,
            '*',
            x - 12 + k * 12.0,
            y + 20,
            size: 14,
            col: _C.lightBlue,
            bold: true,
          );
        }
        break;
      case 5:
        _cloud(c, p, x, y - 8, 1.1, _C.gray, .55);
        c.drawPath(
          WbArtPen.poly([
            Offset(x + 2, y + 6),
            Offset(x - 6, y + 18),
            Offset(x, y + 18),
            Offset(x - 4, y + 30),
            Offset(x + 8, y + 14),
            Offset(x + 2, y + 14),
          ]),
          p.fill(_C.yellow, 1),
        );
        break;
      case 6:
        for (int k = 0; k < 3; k++) {
          final yy = y - 10 + k * 10.0;
          c.drawPath(
            Path()
              ..moveTo(x - 24, yy)
              ..lineTo(x + 12, yy)
              ..quadraticBezierTo(x + 24, yy - 2, x + 22, yy - 8),
            p.stroke(_C.teal, 1.3),
          );
        }
        break;
      default:
        for (int k = 0; k < 4; k++) {
          _ln(
            c,
            p.stroke(_C.gray, 1.6),
            x - 24,
            y - 12 + k * 9.0,
            x + 24,
            y - 12 + k * 9.0,
          );
        }
    }
    _t(c, p, names[i], x, y + 42, size: 8.5, bold: true);
  }
}

void _landforms(Canvas c, WbArtPen p) {
  final prof = Path()
    ..moveTo(10, 140)
    ..lineTo(70, 140)
    ..lineTo(100, 80)
    ..lineTo(125, 40)
    ..lineTo(150, 80)
    ..lineTo(170, 120)
    ..lineTo(185, 125)
    ..lineTo(200, 95)
    ..lineTo(275, 95)
    ..lineTo(300, 140)
    ..lineTo(340, 142)
    ..lineTo(340, 175)
    ..lineTo(10, 175)
    ..close();
  _pf(c, p, prof, _C.brown, .3);
  _pg(
    c,
    p,
    [const Offset(125, 40), const Offset(113, 58), const Offset(137, 58)],
    Colors.white,
    .9,
  );
  _pg(
    c,
    p,
    [
      const Offset(340, 142),
      const Offset(440, 142),
      const Offset(440, 175),
      const Offset(340, 175),
    ],
    _C.blue,
    .4,
  );
  final delta = Path()
    ..moveTo(335, 142)
    ..quadraticBezierTo(350, 158, 372, 160)
    ..quadraticBezierTo(358, 148, 345, 142)
    ..close();
  _pf(c, p, delta, _C.yellow, .6);
  c.drawPath(
    Path()
      ..moveTo(300, 140)
      ..lineTo(338, 142),
    p.stroke(_C.blue, 1.6),
  );
  _t(c, p, 'Ova', 40, 125, size: 9, bold: true);
  _t(c, p, 'Dağ', 125, 28, size: 9, bold: true);
  _t(c, p, 'Vadi', 185, 112, size: 9, bold: true);
  _t(c, p, 'Plato', 237, 82, size: 9, bold: true);
  _t(c, p, 'Delta', 355, 130, size: 9, bold: true);
  _t(c, p, 'Deniz', 400, 162, size: 9, bold: true, col: _C.blue);
  _t(c, p, 'Alçak, düz', 40, 155, size: 7.5, col: _C.gray);
  _t(c, p, 'Yüksek, düz', 237, 108, size: 7.5, col: _C.gray);
  _t(c, p, 'Nehrin döküldüğü yerde birikim', 345, 192, size: 7.5, col: _C.gray);
}

void _meander(Canvas c, WbArtPen p) {
  final r = Path()..moveTo(10, 100);
  for (int i = 0; i < 5; i++) {
    final x = 10.0 + i * 55;
    final dy = i.isEven ? -50.0 : 50.0;
    r.cubicTo(x + 15, 100 + dy, x + 40, 100 + dy, x + 55, 100);
  }
  c.drawPath(r, p.stroke(_C.blue, 6));
  c.drawPath(r, p.stroke(Colors.white, 2.5));
  _ci(c, p, 60, 190, 0, _C.blue, 0);
  _el(c, p, 300, 175, 38, 8, _C.blue, .35);
  _ld(c, p, 'Dış kıyı\n(aşınma)', 70, 72, 40, 20, a: 'center');
  _ld(c, p, 'İç kıyı\n(birikme)', 70, 98, 20, 135, a: 'center');
  _ld(c, p, 'Menderes', 150, 126, 150, 160, a: 'center');
  _ld(c, p, 'Ox-bow gölü\n(menderes gölü)', 300, 175, 300, 205, a: 'center');
  _ar(c, p, 10, 92, 30, 95, _C.gray, 5);
  _t(c, p, 'Akış yönü', 30, 78, size: 8, col: _C.gray);
}

void _fossil(Canvas c, WbArtPen p) {
  const names = [
    '1) Canlı ölür',
    '2) Gömülür',
    '3) Katmanlar birikir',
    '4) Yüzeye çıkar',
  ];
  for (int i = 0; i < 4; i++) {
    final x = 10.0 + i * 108;
    c.drawRect(
      Rect.fromLTWH(x, 20, 98, 100),
      p.fill(_C.lightBlue, i == 3 ? .0 : .15),
    );
    c.drawRect(Rect.fromLTWH(x, 20, 98, 100), p.thin(.5));
    if (i == 3) {
      c.drawRect(Rect.fromLTWH(x, 20, 98, 100), p.fill(_C.yellow, .12));
    }
    final layers = [0, 1, 3, 3][i];
    for (int k = 0; k < layers; k++) {
      final top = 118 - 22.0 * (k + 1) - (i == 1 ? 0 : 0);
      c.drawRect(
        Rect.fromLTWH(x + 1, top, 96, 22),
        p.fill(k.isEven ? _C.brown : _C.orange, .35),
      );
    }
    final fy = [100.0, 94.0, 78.0, 40.0][i];
    final fc = i < 2 ? _C.blue : _C.gray;
    _el(c, p, x + 45, fy, 16, 6, fc, .55);
    _pg(
      c,
      p,
      [Offset(x + 60, fy), Offset(x + 70, fy - 6), Offset(x + 70, fy + 6)],
      fc,
      .55,
    );
    if (i >= 2) {
      for (int k = 0; k < 5; k++) {
        _ln(c, p.thin(.5), x + 34 + k * 4.0, fy - 4, x + 34 + k * 4.0, fy + 4);
      }
    }
    _t(c, p, names[i], x + 49, 134, size: 8.5, bold: true);
  }
  _t(
    c,
    p,
    'Fosil: geçmiş canlıların kayaçta kalan izi',
    220,
    160,
    size: 9,
    bold: true,
  );
}

void _soilLayers(Canvas c, WbArtPen p) {
  const names = [
    'O – Organik tabaka (hümüs)',
    'A – Üst toprak',
    'B – Alt toprak',
    'C – Ayrışmış ana kaya',
    'R – Ana kaya',
  ];
  final cols = [Colors.black87, _C.brown, _C.orange, _C.yellow, _C.gray];
  final alphas = [.6, .6, .45, .4, .5];
  final hs = [18.0, 40.0, 40.0, 40.0, 42.0];
  double y = 20;
  for (int i = 0; i < 5; i++) {
    c.drawRect(Rect.fromLTWH(20, y, 150, hs[i]), p.fill(cols[i], alphas[i]));
    c.drawRect(Rect.fromLTWH(20, y, 150, hs[i]), p.line);
    _t(c, p, names[i], 180, y + hs[i] / 2, size: 8, a: 'left');
    if (i == 3) {
      for (int k = 0; k < 4; k++) {
        _rel(c, p, 40.0 + k * 34, y + 20, 8, 5, k * .5, _C.gray, .5);
      }
    }
    if (i == 4) {
      _pg(
        c,
        p,
        [Offset(30, y + 30), Offset(60, y + 8), Offset(90, y + 30)],
        _C.gray,
        .3,
      );
      _pg(
        c,
        p,
        [Offset(100, y + 32), Offset(125, y + 12), Offset(155, y + 32)],
        _C.gray,
        .3,
      );
    }
    y += hs[i];
  }
  _ln(c, p.stroke(_C.darkGreen, 2), 70, 20, 70, 6);
  _rel(c, p, 62, 8, 7, 3, -.5, _C.green, .6);
  _rel(c, p, 78, 8, 7, 3, .5, _C.green, .6);
  c.drawPath(
    Path()
      ..moveTo(70, 20)
      ..lineTo(70, 90)
      ..moveTo(70, 50)
      ..lineTo(50, 70)
      ..moveTo(70, 65)
      ..lineTo(92, 82),
    p.stroke(_C.brown, 1.2),
  );
  _ar(c, p, 12, 20, 12, 220, _C.gray, 5);
  _t(c, p, 'Derinlik', 10, 232, size: 8, col: _C.gray, a: 'left');
}

void _energySources(Canvas c, WbArtPen p) {
  // Güneş paneli
  c.save();
  c.translate(0, 0);
  _sun(c, p, 30, 26, 11);
  _pg(
    c,
    p,
    [
      const Offset(60, 105),
      const Offset(150, 105),
      const Offset(165, 70),
      const Offset(75, 70),
    ],
    _C.blue,
    .45,
  );
  for (int i = 1; i < 4; i++) {
    _ln(c, p.thin(.5), 60 + i * 22.5, 105, 75 + i * 22.5, 70);
  }
  _ln(c, p.thin(.5), 67, 87, 157, 87);
  _ln(c, p.stroke(_C.brown, 1.6), 105, 105, 105, 128);
  _ar(c, p, 45, 36, 80, 66, _C.yellow, 5);
  _t(c, p, 'Güneş paneli\n(ışık → elektrik)', 105, 148, size: 8.5, bold: true);
  c.restore();
  // Rüzgar türbini
  c.save();
  c.translate(200, 0);
  _ln(c, p.stroke(_C.gray, 3), 80, 62, 80, 128);
  _ci(c, p, 80, 62, 4, _C.gray, .7);
  for (int i = 0; i < 3; i++) {
    final a = i * 2 * _pi / 3 - _pi / 2 + .2;
    _pg(
      c,
      p,
      [
        Offset(80, 62),
        Offset(80 + 40 * math.cos(a - .1), 62 + 40 * math.sin(a - .1)),
        Offset(80 + 40 * math.cos(a + .1), 62 + 40 * math.sin(a + .1)),
      ],
      _C.lightBlue,
      .6,
    );
  }
  c.drawPath(
    Path()
      ..moveTo(10, 40)
      ..quadraticBezierTo(25, 32, 40, 40),
    p.thin(),
  );
  c.drawPath(
    Path()
      ..moveTo(10, 55)
      ..quadraticBezierTo(25, 47, 40, 55),
    p.thin(),
  );
  _t(
    c,
    p,
    'Rüzgâr türbini\n(rüzgâr → elektrik)',
    90,
    148,
    size: 8.5,
    bold: true,
  );
  c.restore();
  // Baraj
  c.save();
  c.translate(0, 180);
  _pg(
    c,
    p,
    [
      const Offset(10, 10),
      const Offset(90, 10),
      const Offset(100, 100),
      const Offset(60, 100),
      const Offset(60, 105),
      const Offset(10, 105),
    ],
    _C.blue,
    .35,
  );
  _pg(
    c,
    p,
    [
      const Offset(90, 10),
      const Offset(115, 10),
      const Offset(125, 100),
      const Offset(100, 100),
    ],
    _C.gray,
    .55,
  );
  _rr(c, p, 128, 80, 30, 20, 2, _C.yellow, .4);
  _ar(c, p, 75, 70, 126, 90, _C.blue, 5);
  _t(
    c,
    p,
    'Hidroelektrik\nbaraj (su → elektrik)',
    105,
    130,
    size: 8.5,
    bold: true,
  );
  _t(c, p, 'Baraj gölü', 45, 40, size: 8);
  _t(c, p, 'Türbin', 143, 112, size: 7.5);
  c.restore();
  // Jeotermal
  c.save();
  c.translate(200, 180);
  c.drawRect(const Rect.fromLTWH(10, 60, 160, 50), p.fill(_C.brown, .3));
  _el(c, p, 90, 98, 50, 10, _C.red, .5);
  _ln(c, p.stroke(_C.red, 2), 90, 98, 90, 62);
  _rr(c, p, 100, 30, 45, 30, 3, _C.gray, .35);
  for (int i = 0; i < 3; i++) {
    _ln(c, p.stroke(_C.gray, 1.2), 118.0 + i * 8, 28, 118.0 + i * 8, 14);
  }
  _ar(c, p, 90, 90, 98, 52, _C.red, 5);
  _t(c, p, 'Jeotermal\n(yer ısısı → buhar)', 90, 130, size: 8.5, bold: true);
  c.restore();
}

void _recycle(Canvas c, WbArtPen p) {
  const cx = 130.0, cy = 105.0, r = 62.0;
  final cols = [_C.green, _C.blue, _C.orange];
  const names = ['Azalt', 'Yeniden\nkullan', 'Geri\ndönüştür'];
  for (int i = 0; i < 3; i++) {
    final s = -90.0 + i * 120 + 8;
    _carc(c, p, cx, cy, r, s, 98, cols[i], w: 4);
    final mid = (s + 49) * _pi / 180;
    _t(
      c,
      p,
      names[i],
      cx + (r + 28) * math.cos(mid),
      cy + (r + 22) * math.sin(mid),
      size: 9,
      bold: true,
      col: cols[i],
    );
  }
  _t(c, p, '3R', cx, cy, size: 16, bold: true, col: _C.green);
  _t(c, p, 'Geri dönüşüm simgesi', 130, 215, size: 9, bold: true);
}

void _greenhouse(Canvas c, WbArtPen p) {
  _sun(c, p, 40, 30, 16);
  _rr(c, p, 10, 100, 340, 40, 0, _C.purple, .15);
  _t(
    c,
    p,
    'Sera gazları (CO₂, CH₄, su buharı)',
    180,
    120,
    size: 8.5,
    col: _C.purple,
    bold: true,
  );
  c.drawRect(const Rect.fromLTWH(10, 200, 340, 36), p.fill(_C.brown, .35));
  c.drawRect(const Rect.fromLTWH(10, 200, 340, 8), p.fill(_C.green, .4));
  for (int i = 0; i < 3; i++) {
    _ar(c, p, 70.0 + i * 12, 50.0 + i * 8, 130.0 + i * 12, 196.0, _C.yellow, 6);
  }
  _ar(c, p, 215, 100, 265, 30, _C.orange, 5);
  _t(c, p, 'Yansıyan ışık', 275, 22, size: 8, a: 'left');
  _ar(c, p, 160, 196, 160, 142, _C.red, 6);
  _ar(c, p, 200, 196, 200, 142, _C.red, 6);
  _ar(c, p, 160, 100, 180, 142, _C.red, 5);
  c.drawPath(
    Path()
      ..moveTo(240, 196)
      ..lineTo(240, 150),
    p.stroke(_C.red, 1.2),
  );
  _ar(c, p, 240, 150, 250, 142, _C.red, 4);
  _ar(c, p, 280, 196, 280, 20, _C.red, 6);
  _ld(c, p, 'Güneş ışınları', 90, 70, 120, 20);
  _t(
    c,
    p,
    'Yerden yayılan kızılötesi ısı:\nbir kısmı sera gazlarınca tutulur',
    300,
    170,
    size: 8,
  );
  _t(c, p, 'Dünya yüzeyi', 60, 220, size: 8, bold: true);
  _t(c, p, 'Sera etkisi', 180, 252, size: 9, bold: true);
}

void _ozone(Canvas c, WbArtPen p) {
  _sun(c, p, 40, 30, 16);
  c.drawRect(const Rect.fromLTWH(10, 200, 340, 30), p.fill(_C.green, .3));
  _ci(c, p, 0, 0, 0, _C.gray, 0);
  for (int i = 0; i < 30; i++) {
    final x = 10.0 + i * 11.5;
    if (x > 200 && x < 250) continue;
    _ci(c, p, x, 110, 4.5, _C.purple, .35);
  }
  _t(c, p, 'O₃ ozon tabakası', 300, 95, size: 8.5, bold: true, col: _C.purple);
  _t(c, p, 'Ozon\ndelinmesi', 225, 135, size: 8, col: _C.red, bold: true);
  for (final x in [80.0, 120.0]) {
    _ar(c, p, x - 30, 40, x, 106, _C.orange, 5);
    _ln(c, p.stroke(_C.orange, 1.2), x, 106, x + 20, 90);
  }
  _ar(c, p, 190, 40, 225, 196, _C.orange, 6);
  _ar(c, p, 250, 40, 245, 196, _C.orange, 6);
  _t(c, p, 'UV ışınları', 130, 28, size: 8.5, col: _C.orange, bold: true);
  _t(c, p, 'Ozon tabakası UV\'yi\nsüzer', 75, 160, size: 8);
  _t(
    c,
    p,
    'Delikten fazla UV\nyeryüzüne ulaşır',
    300,
    160,
    size: 8,
    col: _C.red,
  );
  _t(c, p, 'CFC gazları ozonu yok eder', 180, 250, size: 9, bold: true);
}

// ───────────────────────── Liste ─────────────────────────

final List<WbArtItem> wbArtScience = [
  const WbArtItem(
    'fen_hayvan_hucresi',
    'Hayvan Hücresi',
    320,
    190,
    _animalCell,
    tags: 'hücre organel çekirdek mitokondri golgi biyoloji hayvan',
  ),
  const WbArtItem(
    'fen_bitki_hucresi',
    'Bitki Hücresi',
    340,
    200,
    _plantCell,
    tags: 'hücre duvarı kloroplast koful bitki biyoloji organel',
  ),
  const WbArtItem(
    'fen_bakteri',
    'Bakteri Hücresi',
    340,
    200,
    _bacteria,
    tags: 'bakteri prokaryot mikrop kamçı plazmit biyoloji',
  ),
  const WbArtItem(
    'fen_virus',
    'Virüs',
    240,
    225,
    _virus,
    tags: 'virus virüs bakteriyofaj kapsit biyoloji',
  ),
  const WbArtItem(
    'fen_dna',
    'DNA Çift Sarmal',
    240,
    250,
    _dna,
    tags: 'dna sarmal baz eşleşmesi adenin timin guanin sitozin genetik',
  ),
  const WbArtItem(
    'fen_kromozom',
    'Kromozom',
    220,
    215,
    _chromosome,
    tags: 'kromozom kromatit sentromer genetik hücre',
  ),
  const WbArtItem(
    'fen_mitoz',
    'Mitoz Bölünme Evreleri',
    430,
    145,
    _mitosis,
    tags: 'mitoz bölünme profaz metafaz anafaz telofaz hücre',
  ),
  const WbArtItem(
    'fen_mayoz',
    'Mayoz Bölünme',
    320,
    235,
    _meiosis,
    tags: 'mayoz bölünme gamet eşey hücresi hücre',
  ),
  const WbArtItem(
    'fen_hucre_zari',
    'Hücre Zarı',
    340,
    195,
    _membrane,
    tags: 'hücre zarı fosfolipit protein akıcı mozaik',
  ),
  const WbArtItem(
    'fen_protein_sentezi',
    'Protein Sentezi',
    300,
    225,
    _proteinSynthesis,
    tags: 'protein sentezi mrna trna ribozom transkripsiyon translasyon',
  ),
  const WbArtItem(
    'fen_enzim',
    'Enzim-Substrat',
    300,
    145,
    _enzyme,
    tags: 'enzim substrat kilit anahtar katalizör',
  ),
  const WbArtItem(
    'fen_ozmos',
    'Ozmos',
    330,
    200,
    _osmosis,
    tags: 'ozmos yarı geçirgen zar su madde geçişi',
  ),
  const WbArtItem(
    'fen_difuzyon',
    'Difüzyon',
    370,
    180,
    _diffusion,
    tags: 'difüzyon yayılma derişim madde geçişi',
  ),
  const WbArtItem(
    'fen_fotosentez',
    'Fotosentez',
    380,
    285,
    _photosynthesis,
    tags: 'fotosentez kloroplast co2 o2 ışık glikoz bitki yaprak',
  ),
  const WbArtItem(
    'fen_hucre_solunumu',
    'Hücre Solunumu',
    340,
    205,
    _respiration,
    tags: 'hücre solunumu mitokondri atp glikoz oksijen enerji',
  ),
  const WbArtItem(
    'fen_cicek',
    'Çiçeğin Kısımları',
    280,
    260,
    _flower,
    tags: 'çiçek taç yaprak çanak anter stigma ovaryum bitki',
  ),
  const WbArtItem(
    'fen_tohum_cimlenme',
    'Tohum Çimlenmesi',
    400,
    190,
    _germination,
    tags: 'tohum çimlenme fidan kök bitki',
  ),
  const WbArtItem(
    'fen_kok_govde_yaprak',
    'Kök - Gövde - Yaprak',
    260,
    235,
    _rootStem,
    tags: 'kök gövde yaprak bitki organları kök tüyü',
  ),
  const WbArtItem(
    'fen_yaprak_kesiti',
    'Yaprak Kesiti (Stoma)',
    340,
    180,
    _leafSection,
    tags: 'yaprak kesiti stoma palizat sünger epidermis',
  ),
  const WbArtItem(
    'fen_bitki_yasam',
    'Bitki Yaşam Döngüsü',
    300,
    250,
    _lifeCycle,
    tags: 'bitki yaşam döngüsü tohum fidan çiçek meyve',
  ),
  const WbArtItem(
    'fen_kalp',
    'Kalp Yapısı',
    260,
    270,
    _heart,
    tags: 'kalp atriyum ventrikül aort toplardamar atardamar dolaşım',
  ),
  const WbArtItem(
    'fen_kan_dolasimi',
    'Kan Dolaşımı',
    340,
    255,
    _circulation,
    tags: 'kan dolaşımı büyük küçük dolaşım kalp akciğer',
  ),
  const WbArtItem(
    'fen_solunum',
    'Solunum Sistemi',
    260,
    245,
    _respiratory,
    tags: 'solunum sistemi akciğer trake bronş alveol diyafram',
  ),
  const WbArtItem(
    'fen_sindirim',
    'Sindirim Sistemi',
    260,
    265,
    _digestive,
    tags: 'sindirim sistemi mide bağırsak karaciğer pankreas yemek borusu',
  ),
  const WbArtItem(
    'fen_bobrek_nefron',
    'Boşaltım: Böbrek ve Nefron',
    360,
    265,
    _kidney,
    tags: 'boşaltım böbrek nefron glomerulus üreter idrar',
  ),
  const WbArtItem(
    'fen_noron',
    'Sinir Hücresi (Nöron)',
    400,
    165,
    _neuron,
    tags: 'nöron sinir hücresi akson dendrit miyelin sinir sistemi',
  ),
  const WbArtItem(
    'fen_goz',
    'Göz Yapısı',
    320,
    215,
    _eye,
    tags: 'göz kornea mercek retina iris duyu organı',
  ),
  const WbArtItem(
    'fen_kulak',
    'Kulak Yapısı',
    340,
    210,
    _ear,
    tags: 'kulak koklea kulak zarı çekiç örs üzengi işitme duyu',
  ),
  const WbArtItem(
    'fen_deri',
    'Deri Katmanları',
    340,
    225,
    _skin,
    tags: 'deri epidermis dermis hipodermis ter bezi kıl duyu',
  ),
  const WbArtItem(
    'fen_eklem_tipleri',
    'Eklem Türleri',
    440,
    190,
    _joints,
    tags: 'iskelet kemik eklem küre menteşe eksen kayar oynamaz',
  ),
  const WbArtItem(
    'fen_kas',
    'Kas ve Kemik (Kol)',
    300,
    215,
    _muscle,
    tags: 'kas biseps triseps tendon kemik hareket sistemi',
  ),
  const WbArtItem(
    'fen_besin_zinciri',
    'Besin Zinciri',
    420,
    165,
    _foodChain,
    tags: 'besin zinciri üretici tüketici enerji akışı ekoloji',
  ),
  const WbArtItem(
    'fen_besin_piramidi',
    'Besin Piramidi',
    320,
    250,
    _foodPyramid,
    tags: 'besin piramidi enerji piramidi üretici tüketici ekoloji',
  ),
  const WbArtItem(
    'fen_besin_agi',
    'Besin Ağı',
    300,
    255,
    _foodWeb,
    tags: 'besin ağı besin zinciri ekoloji tilki yılan',
  ),
  const WbArtItem(
    'fen_ekosistem',
    'Ekosistem',
    340,
    245,
    _ecosystem,
    tags: 'ekosistem biyotik abiyotik ekoloji çevre',
  ),
  const WbArtItem(
    'fen_karbon_dongusu',
    'Karbon Döngüsü',
    340,
    275,
    _carbonCycle,
    tags: 'karbon döngüsü madde döngüsü co2 fotosentez solunum',
  ),
  const WbArtItem(
    'fen_azot_dongusu',
    'Azot Döngüsü',
    340,
    265,
    _nitrogenCycle,
    tags: 'azot döngüsü madde döngüsü nitrat amonyak bakteri',
  ),
  const WbArtItem(
    'fen_punnett',
    'Punnett Karesi',
    260,
    240,
    _punnett,
    tags: 'punnett karesi kalıtım genotip fenotip çaprazlama mendel',
  ),
  const WbArtItem(
    'fen_soy_agaci',
    'Soy Ağacı (Kalıtım)',
    340,
    205,
    _pedigree,
    tags: 'soy ağacı pedigri kalıtım nesil genetik',
  ),
  const WbArtItem(
    'fen_siniflandirma',
    'Canlıların Sınıflandırması',
    300,
    265,
    _classification,
    tags: 'sınıflandırma âlem şube sınıf takım aile cins tür',
  ),
  const WbArtItem(
    'fen_evrim_agaci',
    'Evrim Ağacı',
    300,
    280,
    _evolution,
    tags: 'evrim ağacı filogenetik ortak ata canlılar',
  ),
  const WbArtItem(
    'fen_gunes_sistemi',
    'Güneş Sistemi',
    320,
    330,
    _solarSystem,
    tags:
        'güneş sistemi gezegen yörünge merkür venüs dünya mars jüpiter satürn uranüs neptün uzay',
  ),
  const WbArtItem(
    'fen_ay_evreleri',
    'Ay\'ın Evreleri',
    420,
    140,
    _moonPhases,
    tags: 'ay evreleri hilal dolunay yeni ay dördün uzay',
  ),
  const WbArtItem(
    'fen_mevsimler',
    'Mevsimler',
    380,
    245,
    _seasons,
    tags: 'mevsimler eksen eğikliği güneş dünya yaz kış ilkbahar sonbahar',
  ),
  const WbArtItem(
    'fen_gece_gunduz',
    'Gece ve Gündüz',
    340,
    205,
    _dayNight,
    tags: 'gece gündüz dünya dönme güneş eksen',
  ),
  const WbArtItem(
    'fen_gunes_tutulmasi',
    'Güneş Tutulması',
    380,
    195,
    _solarEclipse,
    tags: 'güneş tutulması ay dünya gölge umbra penumbra',
  ),
  const WbArtItem(
    'fen_ay_tutulmasi',
    'Ay Tutulması',
    350,
    195,
    _lunarEclipse,
    tags: 'ay tutulması dolunay dünya gölge',
  ),
  const WbArtItem(
    'fen_dunya_katmanlari',
    'Dünya\'nın Katmanları',
    340,
    255,
    _earthLayers,
    tags: 'dünya katmanları kabuk manto çekirdek yer',
  ),
  const WbArtItem(
    'fen_levha_sinirlari',
    'Levha Sınırları',
    430,
    180,
    _plates,
    tags: 'levha sınırları tektonik uzaklaşan yaklaşan kayan deprem dağ',
  ),
  const WbArtItem(
    'fen_yanardag',
    'Volkan Kesiti',
    320,
    250,
    _volcano,
    tags: 'volkan yanardağ krater lav magma kül',
  ),
  const WbArtItem(
    'fen_deprem',
    'Deprem',
    320,
    225,
    _earthquake,
    tags: 'deprem odak merkez üssü episantr fay dalga',
  ),
  const WbArtItem(
    'fen_kayac_dongusu',
    'Kayaç Döngüsü',
    340,
    275,
    _rockCycle,
    tags: 'kayaç döngüsü magmatik tortul metamorfik',
  ),
  const WbArtItem(
    'fen_su_dongusu',
    'Su Döngüsü',
    380,
    255,
    _waterCycle,
    tags: 'su döngüsü buharlaşma yoğuşma yağış bulut',
  ),
  const WbArtItem(
    'fen_atmosfer',
    'Atmosfer Katmanları',
    340,
    225,
    _atmosphere,
    tags:
        'atmosfer katmanları troposfer stratosfer mezosfer termosfer ekzosfer',
  ),
  const WbArtItem(
    'fen_deniz_meltemi',
    'Deniz ve Kara Meltemi',
    450,
    185,
    _seaBreeze,
    tags: 'rüzgar oluşumu meltem deniz kara basınç sıcaklık',
  ),
  const WbArtItem(
    'fen_yagis_turleri',
    'Yağış Türleri',
    420,
    150,
    _precipitation,
    tags: 'yağış türleri yağmur kar dolu çisenti',
  ),
  const WbArtItem(
    'fen_bulut_cesitleri',
    'Bulut Çeşitleri',
    440,
    150,
    _clouds,
    tags: 'bulut çeşitleri sirrus kümülüs stratüs kümülonimbus',
  ),
  const WbArtItem(
    'fen_hava_sembolleri',
    'Hava Durumu Sembolleri',
    400,
    235,
    _weatherSymbols,
    tags: 'hava durumu sembolleri güneşli bulutlu yağmurlu karlı rüzgar',
  ),
  const WbArtItem(
    'fen_yer_sekilleri',
    'Yer Şekilleri',
    440,
    205,
    _landforms,
    tags: 'yer şekilleri dağ vadi plato ova delta',
  ),
  const WbArtItem(
    'fen_menderes',
    'Nehir Yatağı (Menderes)',
    360,
    215,
    _meander,
    tags: 'nehir menderes yatak aşınma birikme ox-bow',
  ),
  const WbArtItem(
    'fen_fosil',
    'Fosil Oluşumu',
    440,
    170,
    _fossil,
    tags: 'fosil oluşumu tortul kayaç katman canlı kalıntısı',
  ),
  const WbArtItem(
    'fen_toprak_katmanlari',
    'Toprak Katmanları',
    340,
    245,
    _soilLayers,
    tags: 'toprak katmanları hümüs ana kaya horizon',
  ),
  const WbArtItem(
    'fen_enerji_kaynaklari',
    'Enerji Kaynakları',
    400,
    330,
    _energySources,
    tags:
        'enerji kaynakları güneş paneli rüzgar türbini baraj jeotermal yenilenebilir',
  ),
  const WbArtItem(
    'fen_geri_donusum',
    'Geri Dönüşüm Simgesi',
    260,
    235,
    _recycle,
    tags: 'geri dönüşüm azalt yeniden kullan çevre atık',
  ),
  const WbArtItem(
    'fen_sera_etkisi',
    'Sera Etkisi',
    360,
    265,
    _greenhouse,
    tags: 'sera etkisi küresel ısınma sera gazı iklim',
  ),
  const WbArtItem(
    'fen_ozon',
    'Ozon Tabakası',
    360,
    265,
    _ozone,
    tags: 'ozon tabakası uv cfc atmosfer delik',
  ),
];
