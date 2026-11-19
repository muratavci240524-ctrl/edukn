import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'whiteboard_art_core.dart';

// ---------------------------------------------------------------------------
// Yerel yardımcılar
// ---------------------------------------------------------------------------

const _blue = WbArtColors.blue;
const _red = WbArtColors.red;
const _green = WbArtColors.green;
const _orange = WbArtColors.orange;
const _purple = WbArtColors.purple;
const _yellow = WbArtColors.yellow;
const _gray = WbArtColors.gray;
const _teal = WbArtColors.teal;
const _pink = WbArtColors.pink;

Offset _u(Offset a, Offset b) {
  final d = b - a;
  final l = d.distance;
  return l == 0 ? Offset.zero : d / l;
}

void _pg(Canvas c, WbArtPen p, List<Offset> pts, [Color? f, double a = 0.25]) {
  final path = WbArtPen.poly(pts);
  if (f != null) c.drawPath(path, p.fill(f, a));
  c.drawPath(path, p.line);
}

void _t(
  Canvas c,
  WbArtPen p,
  String s,
  Offset at, {
  double size = 10,
  Color? col,
  bool bold = false,
  String anchor = 'center',
}) {
  p.text(c, s, at, size: size, c: col, bold: bold, anchor: anchor);
}

void _dot(Canvas c, WbArtPen p, Offset o, [Color? col, double r = 2.6]) {
  c.drawCircle(o, r, p.fill(col ?? p.color));
}

/// Dik açı işareti.
void _ra(Canvas c, WbArtPen p, Offset v, Offset a, Offset b, [double s = 8]) {
  final ua = _u(v, a) * s;
  final ub = _u(v, b) * s;
  c.drawPath(
    Path()
      ..moveTo(v.dx + ua.dx, v.dy + ua.dy)
      ..lineTo(v.dx + ua.dx + ub.dx, v.dy + ua.dy + ub.dy)
      ..lineTo(v.dx + ub.dx, v.dy + ub.dy),
    p.thin(0.8),
  );
}

/// v köşesinde a ve b yönleri arasında yay.
void _arcAt(Canvas c, Paint paint, Offset v, Offset a, Offset b, double r) {
  final a1 = math.atan2(a.dy - v.dy, a.dx - v.dx);
  final a2 = math.atan2(b.dy - v.dy, b.dx - v.dx);
  var sw = a2 - a1;
  while (sw > math.pi) {
    sw -= 2 * math.pi;
  }
  while (sw < -math.pi) {
    sw += 2 * math.pi;
  }
  c.drawPath(
    Path()..addArc(Rect.fromCircle(center: v, radius: r), a1, sw),
    paint,
  );
}

/// Açı etiket konumu (iç açıortay yönünde).
Offset _bis(Offset v, Offset a, Offset b, double d) {
  final s = _u(v, a) + _u(v, b);
  final l = s.distance;
  if (l < 1e-6) {
    final ua = _u(v, a);
    return v + Offset(-ua.dy, ua.dx) * d;
  }
  return v + s / l * d;
}

/// Eşit kenar işareti.
void _tick(Canvas c, WbArtPen p, Offset a, Offset b, [int n = 1]) {
  final m = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  final u = _u(a, b);
  final nrm = Offset(-u.dy, u.dx);
  for (int i = 0; i < n; i++) {
    final o = m + u * ((i - (n - 1) / 2) * 3.5);
    c.drawLine(o - nrm * 4, o + nrm * 4, p.thin(0.9));
  }
}

Offset _mid(Offset a, Offset b) => Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);

void _axes(
  Canvas c,
  WbArtPen p,
  Offset o, {
  double l = 80,
  double r = 90,
  double u = 80,
  double d = 80,
  bool origin = true,
}) {
  final g = p.thin(0.8);
  c.drawLine(o - Offset(l, 0), o + Offset(r, 0), g);
  c.drawLine(o + Offset(0, d), o - Offset(0, u), g);
  p.arrow(c, o + Offset(r - 8, 0), o + Offset(r, 0), size: 6, line: false);
  p.arrow(c, o - Offset(0, u - 8), o - Offset(0, u), size: 6, line: false);
  _t(c, p, 'x', o + Offset(r - 4, 10), size: 10, bold: true);
  _t(c, p, 'y', o + Offset(9, -u + 2), size: 10, bold: true);
  if (origin) _t(c, p, 'O', o + const Offset(-7, 8), size: 9);
}

void _curve(
  Canvas c,
  Paint paint,
  double Function(double) f,
  double x0,
  double x1,
  Offset o,
  double sx,
  double sy, [
  int n = 160,
]) {
  final path = Path();
  for (int i = 0; i <= n; i++) {
    final x = x0 + (x1 - x0) * i / n;
    final pt = Offset(o.dx + x * sx, o.dy - f(x) * sy);
    if (i == 0) {
      path.moveTo(pt.dx, pt.dy);
    } else {
      path.lineTo(pt.dx, pt.dy);
    }
  }
  c.drawPath(path, paint);
}

Path _sector(Offset ctr, double r, double startRad, double sweepRad) => Path()
  ..moveTo(ctr.dx, ctr.dy)
  ..arcTo(Rect.fromCircle(center: ctr, radius: r), startRad, sweepRad, false)
  ..close();

Offset _pol(Offset ctr, double r, double deg) => Offset(
  ctr.dx + r * math.cos(deg * math.pi / 180),
  ctr.dy + r * math.sin(deg * math.pi / 180),
);

/// Elips: ön yarı sürekli, arka yarı kesikli.
void _ell3(
  Canvas c,
  WbArtPen p,
  Offset ctr,
  double rx,
  double ry, {
  bool backDashed = true,
}) {
  final rect = Rect.fromCenter(center: ctr, width: rx * 2, height: ry * 2);
  c.drawPath(Path()..addArc(rect, 0, math.pi), p.line);
  final back = Path()..addArc(rect, math.pi, math.pi);
  if (backDashed) {
    p.dashedPath(c, back, paint: p.thin());
  } else {
    c.drawPath(back, p.line);
  }
}

// ---------------------------------------------------------------------------
// 3B cisimler
// ---------------------------------------------------------------------------

void _box3(Canvas c, WbArtPen p, Rect f, Offset d, Color col) {
  final b = f.shift(d);
  c.drawPath(
    WbArtPen.poly([f.topLeft, f.topRight, b.topRight, b.topLeft]),
    p.fill(col, 0.12),
  );
  c.drawPath(
    WbArtPen.poly([f.topRight, f.bottomRight, b.bottomRight, b.topRight]),
    p.fill(col, 0.3),
  );
  c.drawRect(f, p.fill(col, 0.06));
  p.dashed(c, b.bottomLeft, f.bottomLeft);
  p.dashed(c, b.bottomLeft, b.topLeft);
  p.dashed(c, b.bottomLeft, b.bottomRight);
  c.drawRect(f, p.line);
  c.drawPath(
    WbArtPen.poly([f.topLeft, f.topRight, b.topRight, b.topLeft]),
    p.line,
  );
  c.drawPath(
    WbArtPen.poly([f.topRight, f.bottomRight, b.bottomRight, b.topRight]),
    p.line,
  );
}

void _dKup(Canvas c, WbArtPen p) {
  const f = Rect.fromLTWH(25, 80, 100, 100);
  _box3(c, p, f, const Offset(45, -45), _blue);
  _t(c, p, 'a', const Offset(75, 192), size: 12, bold: true);
  _t(c, p, 'a', const Offset(13, 130), size: 12, bold: true);
  _t(c, p, 'a', const Offset(160, 150), size: 12, bold: true);
  _t(c, p, 'V = a³', const Offset(150, 20), size: 10, col: _red, bold: true);
}

void _dPrizma(Canvas c, WbArtPen p) {
  const f = Rect.fromLTWH(20, 90, 110, 70);
  _box3(c, p, f, const Offset(50, -40), _teal);
  _t(c, p, 'a', const Offset(75, 174), size: 12, bold: true);
  _t(c, p, 'c', const Offset(9, 125), size: 12, bold: true);
  _t(c, p, 'b', const Offset(167, 134), size: 12, bold: true);
  _t(c, p, 'V = a·b·c', const Offset(110, 22), size: 10, col: _red, bold: true);
}

void _dUcgenPrizma(Canvas c, WbArtPen p) {
  const a = Offset(30, 170), b = Offset(110, 170), t = Offset(70, 100);
  const d = Offset(60, -40);
  final a2 = a + d, b2 = b + d, t2 = t + d;
  c.drawPath(WbArtPen.poly([b, b2, t2, t]), p.fill(_orange, 0.3));
  c.drawPath(
    WbArtPen.poly([t, t2, a2 - const Offset(0, 0), a]),
    p.fill(_orange, 0.1),
  );
  c.drawPath(WbArtPen.poly([a, b, t]), p.fill(_orange, 0.08));
  p.dashed(c, a2, a);
  p.dashed(c, a2, b2);
  _pg(c, p, [a, b, t]);
  c.drawLine(b, b2, p.line);
  c.drawLine(t, t2, p.line);
  c.drawLine(b2, t2, p.line);
  c.drawLine(t2, a2, p.line);
  _t(c, p, 'taban', const Offset(70, 184), size: 9);
  _t(c, p, 'h', const Offset(166, 94), size: 11, bold: true);
  _t(
    c,
    p,
    'V = Taban alanı · h',
    const Offset(100, 20),
    size: 9,
    col: _red,
    bold: true,
  );
}

void _dKarePiramit(Canvas c, WbArtPen p) {
  const a = Offset(30, 155),
      b = Offset(120, 155),
      cc = Offset(170, 120),
      d = Offset(80, 120);
  const apex = Offset(100, 30);
  final base = _mid(a, cc);
  c.drawPath(WbArtPen.poly([a, b, cc, d]), p.fill(_purple, 0.1));
  c.drawPath(WbArtPen.poly([apex, b, cc]), p.fill(_purple, 0.28));
  c.drawPath(WbArtPen.poly([apex, a, b]), p.fill(_purple, 0.12));
  p.dashed(c, d, a);
  p.dashed(c, d, cc);
  p.dashed(c, d, apex);
  c.drawLine(a, b, p.line);
  c.drawLine(b, cc, p.line);
  c.drawLine(apex, a, p.line);
  c.drawLine(apex, b, p.line);
  c.drawLine(apex, cc, p.line);
  p.dashed(c, apex, base, paint: p.stroke(_red, 0.6));
  _dot(c, p, base, _red, 2);
  _t(c, p, 'h', base + const Offset(-8, -44), size: 11, col: _red, bold: true);
  _t(c, p, 'a', const Offset(75, 168), size: 11, bold: true);
  _t(
    c,
    p,
    'V = Taban · h / 3',
    const Offset(100, 192),
    size: 9,
    col: _red,
    bold: true,
  );
}

void _dSilindir(Canvas c, WbArtPen p) {
  const top = Offset(100, 45), bot = Offset(100, 155);
  const rx = 55.0, ry = 16.0;
  c.drawPath(
    Path()
      ..moveTo(top.dx - rx, top.dy)
      ..lineTo(bot.dx - rx, bot.dy)
      ..arcTo(
        Rect.fromCenter(center: bot, width: rx * 2, height: ry * 2),
        math.pi,
        -math.pi,
        false,
      )
      ..lineTo(top.dx + rx, top.dy)
      ..close(),
    p.fill(_blue, 0.15),
  );
  c.drawOval(
    Rect.fromCenter(center: top, width: rx * 2, height: ry * 2),
    p.fill(_blue, 0.25),
  );
  c.drawOval(
    Rect.fromCenter(center: top, width: rx * 2, height: ry * 2),
    p.line,
  );
  c.drawLine(Offset(top.dx - rx, top.dy), Offset(bot.dx - rx, bot.dy), p.line);
  c.drawLine(Offset(top.dx + rx, top.dy), Offset(bot.dx + rx, bot.dy), p.line);
  _ell3(c, p, bot, rx, ry);
  p.dashed(c, top, Offset(top.dx + rx, top.dy), paint: p.stroke(_red, 0.7));
  _t(
    c,
    p,
    'r',
    Offset(top.dx + rx / 2, top.dy - 7),
    size: 11,
    col: _red,
    bold: true,
  );
  p.dashed(
    c,
    Offset(top.dx, top.dy),
    Offset(bot.dx, bot.dy),
    paint: p.stroke(_green, 0.7),
  );
  _t(c, p, 'h', const Offset(108, 100), size: 11, col: _green, bold: true);
  _t(c, p, 'V = πr²h', const Offset(100, 190), size: 10, col: _red, bold: true);
}

void _dKoni(Canvas c, WbArtPen p) {
  const apex = Offset(100, 25), bot = Offset(100, 150);
  const rx = 60.0, ry = 16.0;
  c.drawPath(
    Path()
      ..moveTo(apex.dx, apex.dy)
      ..lineTo(bot.dx - rx, bot.dy)
      ..arcTo(
        Rect.fromCenter(center: bot, width: rx * 2, height: ry * 2),
        math.pi,
        -math.pi,
        false,
      )
      ..close(),
    p.fill(_orange, 0.2),
  );
  c.drawLine(apex, Offset(bot.dx - rx, bot.dy), p.line);
  c.drawLine(apex, Offset(bot.dx + rx, bot.dy), p.line);
  _ell3(c, p, bot, rx, ry);
  p.dashed(c, apex, bot, paint: p.stroke(_green, 0.7));
  p.dashed(c, bot, Offset(bot.dx + rx, bot.dy), paint: p.stroke(_red, 0.7));
  _dot(c, p, bot, _red, 2);
  _t(c, p, 'h', const Offset(92, 88), size: 11, col: _green, bold: true);
  _t(c, p, 'r', const Offset(130, 143), size: 11, col: _red, bold: true);
  _t(c, p, 'l', const Offset(150, 80), size: 11, bold: true);
  _t(
    c,
    p,
    'V = πr²h / 3',
    const Offset(100, 190),
    size: 10,
    col: _red,
    bold: true,
  );
}

void _dKure(Canvas c, WbArtPen p) {
  const ctr = Offset(100, 100);
  c.drawCircle(ctr, 70, p.fill(_teal, 0.18));
  c.drawCircle(ctr, 70, p.line);
  _ell3(c, p, ctr, 70, 20);
  c.drawLine(ctr, Offset(ctr.dx + 70, ctr.dy), p.stroke(_red, 0.7));
  _dot(c, p, ctr, _red, 2.5);
  _t(c, p, 'r', const Offset(138, 92), size: 11, col: _red, bold: true);
  _t(
    c,
    p,
    'V = 4πr³ / 3',
    const Offset(100, 190),
    size: 10,
    col: _red,
    bold: true,
  );
  _t(c, p, 'A = 4πr²', const Offset(100, 10), size: 10, col: _red, bold: true);
}

void _dKesikKoni(Canvas c, WbArtPen p) {
  const top = Offset(100, 50), bot = Offset(100, 150);
  const r1 = 35.0, r2 = 70.0;
  c.drawPath(
    Path()
      ..moveTo(top.dx - r1, top.dy)
      ..lineTo(bot.dx - r2, bot.dy)
      ..arcTo(
        Rect.fromCenter(center: bot, width: r2 * 2, height: 36),
        math.pi,
        -math.pi,
        false,
      )
      ..lineTo(top.dx + r1, top.dy)
      ..close(),
    p.fill(_pink, 0.16),
  );
  c.drawOval(
    Rect.fromCenter(center: top, width: r1 * 2, height: 20),
    p.fill(_pink, 0.3),
  );
  c.drawOval(Rect.fromCenter(center: top, width: r1 * 2, height: 20), p.line);
  c.drawLine(Offset(top.dx - r1, top.dy), Offset(bot.dx - r2, bot.dy), p.line);
  c.drawLine(Offset(top.dx + r1, top.dy), Offset(bot.dx + r2, bot.dy), p.line);
  _ell3(c, p, bot, r2, 18);
  p.dashed(c, top, bot, paint: p.stroke(_green, 0.7));
  p.dashed(c, top, Offset(top.dx + r1, top.dy), paint: p.stroke(_red, 0.7));
  p.dashed(c, bot, Offset(bot.dx + r2, bot.dy), paint: p.stroke(_red, 0.7));
  _t(c, p, 'h', const Offset(108, 100), size: 11, col: _green, bold: true);
  _t(c, p, 'r₁', const Offset(120, 44), size: 11, col: _red, bold: true);
  _t(c, p, 'r₂', const Offset(138, 142), size: 11, col: _red, bold: true);
  _t(c, p, 'Kesik koni', const Offset(100, 188), size: 10, bold: true);
}

void _dKesikPiramit(Canvas c, WbArtPen p) {
  const a = Offset(25, 165),
      b = Offset(135, 165),
      cc = Offset(180, 135),
      d = Offset(70, 135);
  final cb = _mid(a, cc);
  final ctop = cb + const Offset(0, -90);
  Offset tp(Offset q) => ctop + (q - cb) * 0.5;
  final a2 = tp(a), b2 = tp(b), c2 = tp(cc), d2 = tp(d);
  c.drawPath(WbArtPen.poly([b, cc, c2, b2]), p.fill(_yellow, 0.3));
  c.drawPath(WbArtPen.poly([a, b, b2, a2]), p.fill(_yellow, 0.15));
  p.dashed(c, d, a);
  p.dashed(c, d, cc);
  p.dashed(c, d, d2);
  c.drawLine(a, b, p.line);
  c.drawLine(b, cc, p.line);
  c.drawLine(a, a2, p.line);
  c.drawLine(b, b2, p.line);
  c.drawLine(cc, c2, p.line);
  _pg(c, p, [a2, b2, c2, d2], _blue, 0.2);
  p.dashed(c, ctop, cb, paint: p.stroke(_green, 0.7));
  _t(c, p, 'h', ctop + const Offset(8, 40), size: 11, col: _green, bold: true);
  _t(c, p, 'Kesik piramit', const Offset(100, 190), size: 10, bold: true);
}

void _dKupAcilim(Canvas c, WbArtPen p) {
  const s = 40.0;
  const off = Offset(20, 20);
  const cells = [
    [1, 0],
    [0, 1],
    [1, 1],
    [2, 1],
    [3, 1],
    [1, 2],
  ];
  final cols = [_blue, _green, _orange, _purple, _red, _teal];
  for (int i = 0; i < cells.length; i++) {
    final r = Rect.fromLTWH(
      off.dx + cells[i][0] * s,
      off.dy + cells[i][1] * s,
      s,
      s,
    );
    c.drawRect(r, p.fill(cols[i], 0.22));
    c.drawRect(r, p.line);
    _t(c, p, '${i + 1}', r.center, size: 12, bold: true);
  }
  _t(c, p, 'a', const Offset(100, 143), size: 11, bold: true);
  _t(
    c,
    p,
    '6 eş kare  ·  A = 6a²',
    const Offset(100, 168),
    size: 10,
    col: _red,
    bold: true,
  );
}

void _dSilindirAcilim(Canvas c, WbArtPen p) {
  const rect = Rect.fromLTWH(20, 62, 160, 76);
  c.drawRect(rect, p.fill(_blue, 0.18));
  c.drawRect(rect, p.line);
  for (final cy in [42.0, 158.0]) {
    c.drawCircle(Offset(60, cy), 20, p.fill(_green, 0.25));
    c.drawCircle(Offset(60, cy), 20, p.line);
    p.dashed(c, Offset(60, cy), Offset(80, cy), paint: p.stroke(_red, 0.6));
    _t(c, p, 'r', Offset(70, cy - 8), size: 9, col: _red, bold: true);
  }
  _t(c, p, '2πr', const Offset(100, 150), size: 11, bold: true, col: _red);
  _t(c, p, 'h', const Offset(190, 100), size: 11, bold: true, col: _green);
  _t(c, p, 'Yanal alan = 2πr·h', const Offset(100, 100), size: 10, bold: true);
  _t(c, p, 'Silindir açılımı', const Offset(135, 178), size: 9);
}

void _dKoniAcilim(Canvas c, WbArtPen p) {
  const ctr = Offset(100, 20);
  const r = 110.0;
  c.drawPath(
    _sector(ctr, r, 30 * math.pi / 180, 120 * math.pi / 180),
    p.fill(_orange, 0.2),
  );
  c.drawPath(_sector(ctr, r, 30 * math.pi / 180, 120 * math.pi / 180), p.line);
  const cc = Offset(100, 174);
  c.drawCircle(cc, 36.6, p.fill(_blue, 0.2));
  c.drawCircle(cc, 36.6, p.line);
  _t(c, p, 'l', const Offset(60, 75), size: 12, bold: true, col: _red);
  _t(c, p, 'daire dilimi', const Offset(100, 70), size: 9);
  _t(c, p, 'r', const Offset(100, 174), size: 11, bold: true, col: _red);
  c.drawLine(cc, Offset(cc.dx + 36.6, cc.dy), p.stroke(_red, 0.6));
  _t(c, p, 'Koni açılımı', const Offset(165, 190), size: 9);
}

// ---------------------------------------------------------------------------
// Düzlem geometri
// ---------------------------------------------------------------------------

void _dPisagor(Canvas c, WbArtPen p) {
  const cc = Offset(75, 125), a = Offset(75, 80), b = Offset(135, 125);
  const n = Offset(45, -60);
  _pg(c, p, [a, b, b + n, a + n], _red, 0.2);
  _pg(c, p, [const Offset(30, 80), a, cc, const Offset(30, 125)], _green, 0.22);
  _pg(c, p, [cc, b, const Offset(135, 185), const Offset(75, 185)], _blue, 0.2);
  _pg(c, p, [a, b, cc], _yellow, 0.3);
  _ra(c, p, cc, a, b, 8);
  _t(c, p, 'a²', const Offset(52, 102), size: 11, bold: true);
  _t(c, p, 'b²', const Offset(105, 155), size: 11, bold: true);
  _t(c, p, 'c²', const Offset(140, 62), size: 11, bold: true);
  _t(c, p, 'a', const Offset(66, 102), size: 9, col: _gray);
  _t(
    c,
    p,
    'a² + b² = c²',
    const Offset(48, 160),
    size: 9,
    col: _red,
    bold: true,
  );
}

void _triBase(Canvas c, WbArtPen p, Offset a, Offset b, Offset cc) {
  _pg(c, p, [a, b, cc], _blue, 0.14);
  _t(c, p, 'A', a + const Offset(-10, 4), size: 11, bold: true);
  _t(c, p, 'B', b + const Offset(10, 4), size: 11, bold: true);
  _t(c, p, 'C', cc + const Offset(0, -10), size: 11, bold: true);
}

void _dYukseklik(Canvas c, WbArtPen p) {
  const a = Offset(30, 160), b = Offset(170, 160), cc = Offset(70, 30);
  _triBase(c, p, a, b, cc);
  const h = Offset(70, 160);
  p.dashed(c, cc, h, paint: p.stroke(_red, 0.9));
  _ra(c, p, h, cc, b, 9);
  _dot(c, p, h, _red);
  _t(c, p, 'H', h + const Offset(0, 12), size: 10, col: _red, bold: true);
  _t(c, p, 'h', const Offset(80, 95), size: 12, col: _red, bold: true);
  _t(
    c,
    p,
    'Yükseklik: köşeden karşı kenara dik',
    const Offset(100, 192),
    size: 8.5,
  );
}

void _dKenarortay(Canvas c, WbArtPen p) {
  const a = Offset(30, 160), b = Offset(170, 160), cc = Offset(70, 30);
  _triBase(c, p, a, b, cc);
  final m = _mid(a, b);
  c.drawLine(cc, m, p.stroke(_green, 0.9));
  _dot(c, p, m, _green);
  _tick(c, p, a, m, 1);
  _tick(c, p, m, b, 1);
  _t(c, p, 'D', m + const Offset(0, 12), size: 10, col: _green, bold: true);
  _t(c, p, 'AD = DB', const Offset(100, 176), size: 8.5);
  _t(
    c,
    p,
    'Kenarortay: karşı kenarın orta noktasına',
    const Offset(100, 194),
    size: 8.5,
  );
}

void _dAciortay(Canvas c, WbArtPen p) {
  const a = Offset(30, 160), b = Offset(170, 160), cc = Offset(70, 30);
  _triBase(c, p, a, b, cc);
  final ac = (cc - a).distance, bc = (cc - b).distance;
  final t = ac / (ac + bc);
  final d = Offset(a.dx + (b.dx - a.dx) * t, 160);
  c.drawLine(cc, d, p.stroke(_orange, 0.9));
  _dot(c, p, d, _orange);
  _t(c, p, 'D', d + const Offset(0, 12), size: 10, col: _orange, bold: true);
  for (final r in [14.0, 18.0]) {
    _arcAt(c, p.stroke(_orange, 0.5), cc, a, d, r);
    _arcAt(c, p.stroke(_orange, 0.5), cc, d, b, r);
  }
  _t(
    c,
    p,
    'Açıortay: açıyı iki eşit parçaya böler',
    const Offset(100, 190),
    size: 8.5,
  );
}

void _dCevrel(Canvas c, WbArtPen p) {
  const o = Offset(100, 100);
  const r = 78.0;
  c.drawCircle(o, r, p.fill(_blue, 0.1));
  c.drawCircle(o, r, p.line);
  final a = _pol(o, r, -100), b = _pol(o, r, 30), d = _pol(o, r, 140);
  _pg(c, p, [a, b, d], _yellow, 0.2);
  for (final v in [a, b, d]) {
    _dot(c, p, v);
  }
  _dot(c, p, o, _red, 3);
  p.dashed(c, o, b, paint: p.stroke(_red, 0.6));
  _t(c, p, 'O', o + const Offset(-8, -8), size: 10, col: _red, bold: true);
  _t(
    c,
    p,
    'R',
    _mid(o, b) + const Offset(2, -9),
    size: 10,
    col: _red,
    bold: true,
  );
  _t(c, p, 'A', a + const Offset(0, -9), size: 10, bold: true);
  _t(c, p, 'B', b + const Offset(10, 4), size: 10, bold: true);
  _t(c, p, 'C', d + const Offset(-10, 4), size: 10, bold: true);
  _t(c, p, 'Çevrel çember', const Offset(100, 192), size: 9);
}

void _dIcTeget(Canvas c, WbArtPen p) {
  const a = Offset(20, 165), b = Offset(180, 165), cc = Offset(60, 30);
  final la = (b - cc).distance, lb = (a - cc).distance, lc = (b - a).distance;
  final per = la + lb + lc;
  final i = Offset(
    (la * a.dx + lb * b.dx + lc * cc.dx) / per,
    (la * a.dy + lb * b.dy + lc * cc.dy) / per,
  );
  final area2 =
      ((b.dx - a.dx) * (cc.dy - a.dy) - (cc.dx - a.dx) * (b.dy - a.dy)).abs();
  final r = area2 / per;
  _pg(c, p, [a, b, cc], _blue, 0.1);
  c.drawCircle(i, r, p.fill(_yellow, 0.25));
  c.drawCircle(i, r, p.stroke(_red, 0.9));
  _dot(c, p, i, _red, 3);
  final f = Offset(i.dx, 165);
  p.dashed(c, i, f, paint: p.stroke(_red, 0.6));
  _ra(c, p, f, i, b, 7);
  _t(c, p, 'I', i + const Offset(8, -6), size: 10, col: _red, bold: true);
  _t(c, p, 'r', i + Offset(-7, r / 2), size: 10, col: _red, bold: true);
  _t(c, p, 'İç teğet çember', const Offset(100, 190), size: 9);
}

void _dDilim(Canvas c, WbArtPen p) {
  const o = Offset(90, 100);
  const r = 70.0;
  c.drawCircle(o, r, p.thin(0.5));
  c.drawPath(
    _sector(o, r, -50 * math.pi / 180, 100 * math.pi / 180),
    p.fill(_orange, 0.3),
  );
  c.drawLine(o, _pol(o, r, -50), p.line);
  c.drawLine(o, _pol(o, r, 50), p.line);
  c.drawPath(WbArtPen.arc(o, r, -50, 100), p.stroke(_red, 1.4));
  _arcAt(c, p.thin(0.8), o, _pol(o, r, -50), _pol(o, r, 50), 16);
  _t(c, p, 'α', o + const Offset(28, 0), size: 11, bold: true);
  _t(
    c,
    p,
    'r',
    _pol(o, r / 2, -50) + const Offset(-4, -8),
    size: 10,
    bold: true,
  );
  _t(c, p, 'yay', const Offset(176, 100), size: 10, col: _red, bold: true);
  _t(c, p, 'Daire dilimi', const Offset(100, 188), size: 10, bold: true);
  _t(
    c,
    p,
    'Alan = πr²·α/360',
    const Offset(100, 10),
    size: 9,
    col: _red,
    bold: true,
  );
}

void _dKiris(Canvas c, WbArtPen p) {
  const o = Offset(100, 105);
  const r = 70.0;
  c.drawCircle(o, r, p.fill(_blue, 0.1));
  c.drawCircle(o, r, p.line);
  c.drawLine(
    Offset(o.dx - r, o.dy),
    Offset(o.dx + r, o.dy),
    p.stroke(_green, 0.9),
  );
  final a = _pol(o, r, -140), b = _pol(o, r, -40);
  c.drawLine(a, b, p.stroke(_red, 0.9));
  _dot(c, p, a);
  _dot(c, p, b);
  _dot(c, p, o, p.color, 3);
  p.dashed(c, o, _pol(o, r, 70));
  _t(c, p, 'O', o + const Offset(0, -9), size: 10, bold: true);
  _t(c, p, 'çap', const Offset(65, 118), size: 10, col: _green, bold: true);
  _t(c, p, 'kiriş', Offset(100, a.dy - 9), size: 10, col: _red, bold: true);
  _t(c, p, 'r', const Offset(112, 158), size: 10, bold: true);
}

void _dTeget(Canvas c, WbArtPen p) {
  const o = Offset(80, 100);
  const r = 55.0;
  c.drawCircle(o, r, p.fill(_blue, 0.1));
  c.drawCircle(o, r, p.line);
  const tpt = Offset(135, 100);
  c.drawLine(
    const Offset(135, 25),
    const Offset(135, 175),
    p.stroke(_red, 0.9),
  );
  c.drawLine(o, tpt, p.line);
  _ra(c, p, tpt, o, const Offset(135, 25), 9);
  _dot(c, p, o);
  _dot(c, p, tpt, _red, 3);
  _t(c, p, 'O', o + const Offset(-4, -10), size: 10, bold: true);
  _t(c, p, 'T', const Offset(147, 108), size: 10, col: _red, bold: true);
  _t(c, p, 'r', const Offset(108, 90), size: 10, bold: true);
  _t(c, p, 'teğet', const Offset(160, 40), size: 10, col: _red, bold: true);
  _t(c, p, 'Teğet ⟂ yarıçap', const Offset(110, 190), size: 9);
}

void _dKesen(Canvas c, WbArtPen p) {
  const o = Offset(90, 100);
  const r = 55.0;
  c.drawCircle(o, r, p.fill(_blue, 0.1));
  c.drawCircle(o, r, p.line);
  const p1 = Offset(15, 165), p2 = Offset(195, 45);
  final d = _u(p1, p2);
  final f = p1 - o;
  final bq = f.dx * d.dx + f.dy * d.dy;
  final cq = f.dx * f.dx + f.dy * f.dy - r * r;
  final disc = math.sqrt(bq * bq - cq);
  final a = p1 + d * (-bq - disc);
  final b = p1 + d * (-bq + disc);
  c.drawLine(p1, p2, p.stroke(_red, 0.9));
  _dot(c, p, a, _red, 3);
  _dot(c, p, b, _red, 3);
  _dot(c, p, o);
  _t(c, p, 'A', a + const Offset(-4, 11), size: 10, bold: true);
  _t(c, p, 'B', b + const Offset(10, 6), size: 10, bold: true);
  _t(c, p, 'kesen', const Offset(178, 70), size: 10, col: _red, bold: true);
  _t(c, p, 'Çemberi iki noktada keser', const Offset(100, 190), size: 9);
}

void _dMerkezCevre(Canvas c, WbArtPen p) {
  const o = Offset(100, 95);
  const r = 70.0;
  c.drawCircle(o, r, p.fill(_blue, 0.08));
  c.drawCircle(o, r, p.line);
  final a = _pol(o, r, 210), b = _pol(o, r, 330), d = _pol(o, r, 90);
  c.drawPath(WbArtPen.poly([a, o, b]), p.fill(_red, 0.15));
  c.drawLine(o, a, p.stroke(_red, 0.9));
  c.drawLine(o, b, p.stroke(_red, 0.9));
  c.drawLine(d, a, p.stroke(_green, 0.9));
  c.drawLine(d, b, p.stroke(_green, 0.9));
  _arcAt(c, p.stroke(_red, 0.7), o, a, b, 18);
  _arcAt(c, p.stroke(_green, 0.7), d, a, b, 22);
  _t(c, p, '2α', o + const Offset(0, -32), size: 11, col: _red, bold: true);
  _t(c, p, 'α', d + const Offset(0, -30), size: 11, col: _green, bold: true);
  _t(c, p, 'A', a + const Offset(-10, -2), size: 10, bold: true);
  _t(c, p, 'B', b + const Offset(10, -2), size: 10, bold: true);
  _t(c, p, 'C', d + const Offset(0, 11), size: 10, bold: true);
  _t(c, p, 'O', o + const Offset(0, 9), size: 10, bold: true);
  _t(
    c,
    p,
    'Merkez açı = 2 · Çevre açı',
    const Offset(100, 192),
    size: 9,
    bold: true,
  );
}

void _dParalel(Canvas c, WbArtPen p) {
  c.drawLine(const Offset(15, 70), const Offset(205, 70), p.line);
  c.drawLine(const Offset(15, 130), const Offset(205, 130), p.line);
  c.drawLine(const Offset(120, 28), const Offset(50, 172), p.stroke(_purple));
  _t(c, p, 'd₁', const Offset(212, 70), size: 10, bold: true, anchor: 'left');
  _t(c, p, 'd₂', const Offset(212, 130), size: 10, bold: true, anchor: 'left');
  _t(c, p, 'd₁ ∥ d₂', const Offset(30, 16), size: 9, bold: true);
  const p1 = Offset(100, 70), p2 = Offset(70, 130);
  const right = Offset(1, 0), left = Offset(-1, 0);
  const dn = Offset(-0.447, 0.894), up = Offset(0.447, -0.894);
  void ang(Offset v, Offset d1, Offset d2, Color col, String s) {
    _arcAt(c, p.stroke(col, 0.8), v, v + d1 * 20, v + d2 * 20, 14);
    _t(
      c,
      p,
      s,
      _bis(v, v + d1 * 20, v + d2 * 20, 26),
      size: 10,
      col: col,
      bold: true,
    );
  }

  ang(p1, right, dn, _red, 'a');
  ang(p2, left, up, _red, 'b');
  ang(p1, right, up, _green, 'c');
  ang(p2, right, up, _green, 'd');
  _t(
    c,
    p,
    'a = b  (iç ters)',
    const Offset(110, 186),
    size: 9,
    col: _red,
    bold: true,
  );
  _t(
    c,
    p,
    'c = d  (yöndeş)',
    const Offset(110, 200),
    size: 9,
    col: _green,
    bold: true,
  );
}

void _dAciCesit(Canvas c, WbArtPen p) {
  const names = ['Dar açı', 'Dik açı', 'Geniş açı', 'Doğru açı'];
  const degs = ['< 90°', '90°', '90° - 180°', '180°'];
  const angs = [40.0, 90.0, 130.0, 180.0];
  final cols = [_green, _blue, _orange, _purple];
  for (int i = 0; i < 4; i++) {
    final cx = 70.0 * i;
    final a = angs[i];
    final v = i == 3 ? Offset(cx + 35, 85) : Offset(cx + 12, 85);
    final r1 = i == 3 ? v + const Offset(-30, 0) : v + const Offset(50, 0);
    final r2 = i == 3
        ? v + const Offset(30, 0)
        : v +
              Offset(
                50 * math.cos(a * math.pi / 180),
                -50 * math.sin(a * math.pi / 180),
              );
    c.drawLine(v, r1, p.line);
    c.drawLine(v, r2, p.line);
    if (i == 1) {
      _ra(c, p, v, r1, r2, 10);
    } else if (i == 3) {
      c.drawPath(
        Path()
          ..addArc(Rect.fromCircle(center: v, radius: 14), math.pi, math.pi),
        p.stroke(cols[i], 0.8),
      );
    } else {
      _arcAt(c, p.stroke(cols[i], 0.8), v, r1, r2, 16);
    }
    _t(c, p, degs[i], Offset(cx + 35, 22), size: 9, col: cols[i], bold: true);
    _t(c, p, names[i], Offset(cx + 35, 108), size: 9, bold: true);
  }
}

// --- Dörtgenler ---

void _dKare(Canvas c, WbArtPen p) {
  const pts = [
    Offset(50, 25),
    Offset(150, 25),
    Offset(150, 125),
    Offset(50, 125),
  ];
  _pg(c, p, pts, _blue, 0.2);
  p.dashed(c, pts[0], pts[2]);
  p.dashed(c, pts[1], pts[3]);
  for (int i = 0; i < 4; i++) {
    _tick(c, p, pts[i], pts[(i + 1) % 4]);
    _ra(c, p, pts[i], pts[(i + 1) % 4], pts[(i + 3) % 4], 9);
  }
  _t(c, p, 'a', const Offset(100, 14), size: 11, bold: true);
  _t(c, p, 'Kare: 4 eş kenar, 4 dik açı', const Offset(100, 148), size: 9);
  _t(
    c,
    p,
    'Ç = 4a    A = a²',
    const Offset(100, 165),
    size: 9,
    col: _red,
    bold: true,
  );
}

void _dDikdortgen(Canvas c, WbArtPen p) {
  const pts = [
    Offset(30, 35),
    Offset(170, 35),
    Offset(170, 115),
    Offset(30, 115),
  ];
  _pg(c, p, pts, _green, 0.2);
  p.dashed(c, pts[0], pts[2]);
  p.dashed(c, pts[1], pts[3]);
  for (int i = 0; i < 4; i++) {
    _ra(c, p, pts[i], pts[(i + 1) % 4], pts[(i + 3) % 4], 9);
  }
  _tick(c, p, pts[0], pts[1]);
  _tick(c, p, pts[2], pts[3]);
  _tick(c, p, pts[1], pts[2], 2);
  _tick(c, p, pts[3], pts[0], 2);
  _t(c, p, 'a', const Offset(100, 24), size: 11, bold: true);
  _t(c, p, 'b', const Offset(182, 75), size: 11, bold: true);
  _t(
    c,
    p,
    'Dikdörtgen: karşılıklı kenarlar eş',
    const Offset(100, 136),
    size: 9,
  );
  _t(
    c,
    p,
    'Ç = 2(a+b)    A = a·b',
    const Offset(100, 153),
    size: 9,
    col: _red,
    bold: true,
  );
}

void _dParalelkenar(Canvas c, WbArtPen p) {
  const pts = [
    Offset(60, 35),
    Offset(180, 35),
    Offset(140, 115),
    Offset(20, 115),
  ];
  _pg(c, p, pts, _orange, 0.2);
  p.dashed(c, pts[0], const Offset(60, 115), paint: p.stroke(_red, 0.7));
  _ra(c, p, const Offset(60, 115), pts[2], pts[0], 8);
  _tick(c, p, pts[0], pts[1]);
  _tick(c, p, pts[2], pts[3]);
  _tick(c, p, pts[1], pts[2], 2);
  _tick(c, p, pts[3], pts[0], 2);
  _t(c, p, 'a', const Offset(120, 24), size: 11, bold: true);
  _t(c, p, 'b', const Offset(170, 78), size: 11, bold: true);
  _t(c, p, 'h', const Offset(68, 75), size: 11, col: _red, bold: true);
  _t(c, p, 'Paralelkenar', const Offset(100, 136), size: 9);
  _t(c, p, 'A = a·h', const Offset(100, 153), size: 9, col: _red, bold: true);
}

void _dEsDortgen(Canvas c, WbArtPen p) {
  const pts = [
    Offset(100, 20),
    Offset(165, 75),
    Offset(100, 130),
    Offset(35, 75),
  ];
  _pg(c, p, pts, _purple, 0.2);
  p.dashed(c, pts[0], pts[2]);
  p.dashed(c, pts[1], pts[3]);
  _ra(c, p, const Offset(100, 75), pts[1], pts[0], 8);
  for (int i = 0; i < 4; i++) {
    _tick(c, p, pts[i], pts[(i + 1) % 4]);
  }
  _t(c, p, 'e', const Offset(112, 55), size: 10, bold: true);
  _t(c, p, 'f', const Offset(130, 68), size: 10, bold: true);
  _t(c, p, 'Eşkenar dörtgen', const Offset(100, 148), size: 9);
  _t(
    c,
    p,
    'A = e·f / 2',
    const Offset(100, 165),
    size: 9,
    col: _red,
    bold: true,
  );
}

void _dYamuk(Canvas c, WbArtPen p) {
  const pts = [
    Offset(60, 35),
    Offset(140, 35),
    Offset(180, 115),
    Offset(20, 115),
  ];
  _pg(c, p, pts, _teal, 0.2);
  p.dashed(c, pts[0], const Offset(60, 115), paint: p.stroke(_red, 0.7));
  _ra(c, p, const Offset(60, 115), pts[2], pts[0], 8);
  _t(c, p, 'c', const Offset(100, 24), size: 11, bold: true);
  _t(c, p, 'a', const Offset(100, 128), size: 11, bold: true);
  _t(c, p, 'h', const Offset(68, 75), size: 11, col: _red, bold: true);
  _t(c, p, 'Yamuk: iki kenarı paralel', const Offset(100, 146), size: 9);
  _t(
    c,
    p,
    'A = (a+c)·h / 2',
    const Offset(100, 163),
    size: 9,
    col: _red,
    bold: true,
  );
}

void _dDeltoid(Canvas c, WbArtPen p) {
  const pts = [
    Offset(100, 15),
    Offset(155, 65),
    Offset(100, 135),
    Offset(45, 65),
  ];
  _pg(c, p, pts, _pink, 0.2);
  p.dashed(c, pts[0], pts[2]);
  p.dashed(c, pts[1], pts[3]);
  _tick(c, p, pts[0], pts[1]);
  _tick(c, p, pts[3], pts[0]);
  _tick(c, p, pts[1], pts[2], 2);
  _tick(c, p, pts[2], pts[3], 2);
  _ra(c, p, const Offset(100, 65), pts[1], pts[0], 8);
  _t(c, p, 'Deltoid', const Offset(100, 150), size: 9);
  _t(
    c,
    p,
    'A = e·f / 2',
    const Offset(100, 167),
    size: 9,
    col: _red,
    bold: true,
  );
}

void _dCokgenler(Canvas c, WbArtPen p) {
  const names = [
    'Eşkenar üçgen',
    'Kare',
    'Beşgen',
    'Altıgen',
    'Yedigen',
    'Sekizgen',
  ];
  final cols = [_red, _blue, _green, _orange, _purple, _teal];
  for (int i = 0; i < 6; i++) {
    final ctr = Offset(55 + 95.0 * (i % 3), 50 + 100.0 * (i ~/ 3));
    final n = i + 3;
    final st = n == 4 ? -math.pi / 4 : -math.pi / 2;
    _pg(c, p, WbArtPen.regular(ctr, 38, n, st), cols[i], 0.22);
    _t(
      c,
      p,
      '${names[i]} ($n)',
      ctr + const Offset(0, 50),
      size: 9,
      bold: true,
    );
  }
}

void Function(Canvas, WbArtPen) _dDuzgun(int n, String ad) {
  return (Canvas c, WbArtPen p) {
    const ctr = Offset(100, 85);
    final pts = WbArtPen.regular(
      ctr,
      65,
      n,
      n == 4 ? -math.pi / 4 : -math.pi / 2,
    );
    _pg(c, p, pts, _blue, 0.2);
    for (int i = 0; i < n; i++) {
      c.drawLine(ctr, pts[i], p.thin(0.35));
      _tick(c, p, pts[i], pts[(i + 1) % n]);
    }
    _dot(c, p, ctr, _red, 2.5);
    final ic = (n - 2) * 180 / n;
    _t(c, p, '$ad ($n kenar)', const Offset(100, 170), size: 10, bold: true);
    _t(
      c,
      p,
      'İç açı = ${ic.toStringAsFixed(ic == ic.roundToDouble() ? 0 : 1)}°',
      const Offset(100, 187),
      size: 9,
      col: _red,
      bold: true,
    );
  };
}

void _dKareFormul(Canvas c, WbArtPen p) {
  const r = Rect.fromLTWH(20, 30, 90, 90);
  c.drawRect(r, p.fill(_blue, 0.2));
  c.drawRect(r, p.line);
  for (int i = 1; i < 3; i++) {
    c.drawLine(
      Offset(20 + 30.0 * i, 30),
      Offset(20 + 30.0 * i, 120),
      p.thin(0.3),
    );
    c.drawLine(
      Offset(20, 30 + 30.0 * i),
      Offset(110, 30 + 30.0 * i),
      p.thin(0.3),
    );
  }
  _t(c, p, 'a', const Offset(65, 18), size: 12, bold: true);
  _t(c, p, 'a', const Offset(8, 75), size: 12, bold: true);
  _t(c, p, 'KARE', const Offset(185, 35), size: 11, bold: true);
  _t(c, p, 'Alan', const Offset(135, 65), size: 10, anchor: 'left');
  _t(
    c,
    p,
    'A = a × a',
    const Offset(135, 80),
    size: 11,
    col: _red,
    bold: true,
    anchor: 'left',
  );
  _t(c, p, 'Çevre', const Offset(135, 105), size: 10, anchor: 'left');
  _t(
    c,
    p,
    'Ç = 4 × a',
    const Offset(135, 120),
    size: 11,
    col: _green,
    bold: true,
    anchor: 'left',
  );
}

void _dDikdortgenFormul(Canvas c, WbArtPen p) {
  const r = Rect.fromLTWH(15, 40, 110, 70);
  c.drawRect(r, p.fill(_green, 0.2));
  c.drawRect(r, p.line);
  _t(c, p, 'a', const Offset(70, 28), size: 12, bold: true);
  _t(c, p, 'b', const Offset(3, 75), size: 12, bold: true);
  _t(c, p, 'DİKDÖRTGEN', const Offset(200, 35), size: 11, bold: true);
  _t(c, p, 'Alan', const Offset(145, 65), size: 10, anchor: 'left');
  _t(
    c,
    p,
    'A = a × b',
    const Offset(145, 80),
    size: 11,
    col: _red,
    bold: true,
    anchor: 'left',
  );
  _t(c, p, 'Çevre', const Offset(145, 105), size: 10, anchor: 'left');
  _t(
    c,
    p,
    'Ç = 2(a + b)',
    const Offset(145, 120),
    size: 11,
    col: _green,
    bold: true,
    anchor: 'left',
  );
}

void _dDaireFormul(Canvas c, WbArtPen p) {
  const o = Offset(65, 85);
  c.drawCircle(o, 50, p.fill(_orange, 0.2));
  c.drawCircle(o, 50, p.line);
  c.drawLine(o, o + const Offset(50, 0), p.stroke(_red, 0.8));
  _dot(c, p, o);
  _t(c, p, 'r', const Offset(90, 76), size: 11, col: _red, bold: true);
  _t(c, p, 'DAİRE', const Offset(185, 35), size: 11, bold: true);
  _t(c, p, 'Alan', const Offset(130, 65), size: 10, anchor: 'left');
  _t(
    c,
    p,
    'A = π r²',
    const Offset(130, 80),
    size: 11,
    col: _red,
    bold: true,
    anchor: 'left',
  );
  _t(c, p, 'Çevre', const Offset(130, 105), size: 10, anchor: 'left');
  _t(
    c,
    p,
    'Ç = 2 π r',
    const Offset(130, 120),
    size: 11,
    col: _green,
    bold: true,
    anchor: 'left',
  );
  _t(c, p, 'π ≈ 3,14', const Offset(130, 145), size: 9, anchor: 'left');
}

void _dEsUcgenYuk(Canvas c, WbArtPen p) {
  const a = Offset(100, 37), b = Offset(35, 150), cc = Offset(165, 150);
  _pg(c, p, [a, b, cc], _blue, 0.15);
  const f = Offset(100, 150);
  p.dashed(c, a, f, paint: p.stroke(_red, 0.8));
  _ra(c, p, f, a, cc, 8);
  _tick(c, p, a, b);
  _tick(c, p, a, cc);
  _tick(c, p, b, cc);
  _t(c, p, 'a', const Offset(58, 88), size: 11, bold: true);
  _t(c, p, 'a', const Offset(143, 88), size: 11, bold: true);
  _t(c, p, 'h', const Offset(107, 100), size: 11, col: _red, bold: true);
  _t(c, p, 'a/2', const Offset(68, 162), size: 9, bold: true);
  _t(c, p, 'a/2', const Offset(132, 162), size: 9, bold: true);
  _t(c, p, '60°', const Offset(100, 55), size: 8, col: _green, bold: true);
  _t(
    c,
    p,
    'h = a√3 / 2',
    const Offset(100, 180),
    size: 10,
    col: _red,
    bold: true,
  );
}

void _dBenzer(Canvas c, WbArtPen p) {
  const s = [Offset(15, 150), Offset(70, 150), Offset(50, 100)];
  const o = Offset(110, 150);
  final bg = [for (final q in s) o + (q - const Offset(15, 150)) * 1.8];
  _pg(c, p, s, _blue, 0.22);
  _pg(c, p, bg, _orange, 0.2);
  const lab = ['A', 'B', 'C'];
  for (int i = 0; i < 3; i++) {
    final d1 = _u(_mid(s[0], _mid(s[1], s[2])), s[i]);
    _t(c, p, lab[i], s[i] + d1 * 10, size: 10, bold: true);
    final d2 = _u(_mid(bg[0], _mid(bg[1], bg[2])), bg[i]);
    _t(c, p, "${lab[i]}'", bg[i] + d2 * 11, size: 10, bold: true);
    _arcAt(c, p.stroke(_green, 0.6), s[i], s[(i + 1) % 3], s[(i + 2) % 3], 9);
    _arcAt(
      c,
      p.stroke(_green, 0.6),
      bg[i],
      bg[(i + 1) % 3],
      bg[(i + 2) % 3],
      14,
    );
  }
  _t(
    c,
    p,
    "AB/A'B' = AC/A'C' = BC/B'C'",
    const Offset(115, 175),
    size: 9,
    col: _red,
    bold: true,
  );
  _t(c, p, 'Açılar eş, kenarlar orantılı', const Offset(115, 190), size: 8.5);
}

void _dThales(Canvas c, WbArtPen p) {
  const a = Offset(110, 20), b = Offset(20, 150), cc = Offset(200, 150);
  final d = a + (b - a) * 0.4, e = a + (cc - a) * 0.4;
  _pg(c, p, [a, b, cc], _blue, 0.1);
  c.drawLine(d, e, p.stroke(_red, 0.9));
  _dot(c, p, d, _red);
  _dot(c, p, e, _red);
  _t(c, p, 'A', a + const Offset(0, -9), size: 10, bold: true);
  _t(c, p, 'B', b + const Offset(-8, 6), size: 10, bold: true);
  _t(c, p, 'C', cc + const Offset(8, 6), size: 10, bold: true);
  _t(c, p, 'D', d + const Offset(-10, 0), size: 10, bold: true, col: _red);
  _t(c, p, 'E', e + const Offset(10, 0), size: 10, bold: true, col: _red);
  _t(c, p, 'DE ∥ BC', const Offset(110, 62), size: 9, col: _red, bold: true);
  _t(
    c,
    p,
    'Thales: AD/DB = AE/EC',
    const Offset(110, 172),
    size: 9,
    col: _red,
    bold: true,
  );
}

// ---------------------------------------------------------------------------
// Analitik geometri / fonksiyonlar
// ---------------------------------------------------------------------------

void _dParabol(Canvas c, WbArtPen p) {
  const o = Offset(110, 85);
  const s = 20.0;
  for (int i = -4; i <= 4; i++) {
    c.drawLine(
      Offset(o.dx + i * s, 5),
      Offset(o.dx + i * s, 175),
      p.thin(0.15),
    );
  }
  for (int i = -4; i <= 4; i++) {
    c.drawLine(
      Offset(10, o.dy + i * s),
      Offset(210, o.dy + i * s),
      p.thin(0.15),
    );
  }
  _axes(c, p, o, l: 100, r: 100, u: 80, d: 90);
  c.save();
  c.clipRect(const Rect.fromLTWH(5, 5, 210, 180));
  _curve(c, p.stroke(_red, 1.1), (x) => x * x - 2 * x - 3, -3, 5, o, s, s);
  c.restore();
  _dot(c, p, o + const Offset(s, 4 * s), _blue, 3);
  _dot(c, p, o + const Offset(-s, 0), _green, 3);
  _dot(c, p, o + const Offset(3 * s, 0), _green, 3);
  _t(
    c,
    p,
    'T(1,-4)',
    o + const Offset(s + 6, 4 * s + 10),
    size: 9,
    col: _blue,
    bold: true,
    anchor: 'left',
  );
  _t(
    c,
    p,
    '-1',
    o + const Offset(-s - 2, -9),
    size: 9,
    col: _green,
    bold: true,
  );
  _t(
    c,
    p,
    '3',
    o + const Offset(3 * s + 2, -9),
    size: 9,
    col: _green,
    bold: true,
  );
  _t(
    c,
    p,
    'y = x² - 2x - 3',
    const Offset(165, 12),
    size: 9,
    col: _red,
    bold: true,
  );
}

void _dDogruGrafik(Canvas c, WbArtPen p) {
  const o = Offset(110, 105);
  const s = 20.0;
  for (int i = -5; i <= 5; i++) {
    c.drawLine(
      Offset(o.dx + i * s, 5),
      Offset(o.dx + i * s, 205),
      p.thin(0.15),
    );
    c.drawLine(
      Offset(10, o.dy + i * s),
      Offset(210, o.dy + i * s),
      p.thin(0.15),
    );
  }
  _axes(c, p, o, l: 100, r: 100, u: 100, d: 100);
  c.save();
  c.clipRect(const Rect.fromLTWH(8, 8, 204, 200));
  _curve(c, p.stroke(_red, 1.1), (x) => 2 * x + 1, -5, 5, o, s, s, 2);
  c.restore();
  _dot(c, p, o + const Offset(0, -s), _blue, 3);
  _t(
    c,
    p,
    'n = 1',
    o + const Offset(-6, -s - 2),
    size: 9,
    col: _blue,
    bold: true,
    anchor: 'right',
  );
  c.drawLine(
    o + const Offset(s, -3 * s),
    o + const Offset(2 * s, -3 * s),
    p.stroke(_green, 0.7),
  );
  c.drawLine(
    o + const Offset(2 * s, -3 * s),
    o + const Offset(2 * s, -5 * s),
    p.stroke(_green, 0.7),
  );
  _t(
    c,
    p,
    '1',
    o + const Offset(1.5 * s, -3 * s + 8),
    size: 8,
    col: _green,
    bold: true,
  );
  _t(
    c,
    p,
    'm = 2',
    o + const Offset(2 * s + 3, -4 * s),
    size: 9,
    col: _green,
    bold: true,
    anchor: 'left',
  );
  _t(c, p, 'y = mx + n', const Offset(55, 14), size: 10, col: _red, bold: true);
}

void _dSinCos(Canvas c, WbArtPen p) {
  const o = Offset(30, 80);
  const sx = 36.0, sy = 50.0;
  c.drawLine(const Offset(15, 80), const Offset(285, 80), p.thin(0.8));
  c.drawLine(const Offset(30, 135), const Offset(30, 25), p.thin(0.8));
  p.arrow(
    c,
    const Offset(278, 80),
    const Offset(285, 80),
    size: 6,
    line: false,
  );
  p.arrow(c, const Offset(30, 32), const Offset(30, 25), size: 6, line: false);
  _curve(c, p.stroke(_red, 1.1), math.sin, 0, 2 * math.pi, o, sx, sy);
  _curve(c, p.stroke(_blue, 1.1), math.cos, 0, 2 * math.pi, o, sx, sy);
  const lbl = ['π/2', 'π', '3π/2', '2π'];
  for (int i = 1; i <= 4; i++) {
    final x = o.dx + i * math.pi / 2 * sx;
    c.drawLine(Offset(x, 76), Offset(x, 84), p.thin(0.8));
    _t(c, p, lbl[i - 1], Offset(x, 94), size: 8);
  }
  _t(c, p, '1', const Offset(22, 30), size: 8);
  _t(c, p, '-1', const Offset(21, 130), size: 8);
  _t(c, p, 'y = sin x', const Offset(60, 12), size: 9, col: _red, bold: true);
  _t(c, p, 'y = cos x', const Offset(130, 12), size: 9, col: _blue, bold: true);
  _t(c, p, 'x', const Offset(280, 70), size: 9, bold: true);
}

void _dBirimCember(Canvas c, WbArtPen p) {
  const o = Offset(105, 120);
  const r = 90.0;
  c.drawCircle(o, r, p.fill(_blue, 0.06));
  c.drawCircle(o, r, p.line);
  _axes(c, p, o, l: 100, r: 125, u: 105, d: 100, origin: false);
  const th = 20.0;
  final pt = _pol(o, r, -th);
  final f = Offset(pt.dx, o.dy);
  c.drawLine(o, pt, p.stroke(_purple, 0.9));
  c.drawLine(f, pt, p.stroke(_red, 1.1));
  c.drawLine(o, f, p.stroke(_green, 1.1));
  final tanEnd = Offset(o.dx + r, o.dy - r * math.tan(th * math.pi / 180));
  c.drawLine(Offset(o.dx + r, o.dy), tanEnd, p.stroke(_blue, 1.1));
  p.dashed(c, pt, tanEnd, paint: p.thin(0.5));
  _dot(c, p, pt, _purple, 3);
  _arcAt(c, p.thin(0.8), o, o + const Offset(30, 0), pt, 22);
  _t(c, p, 'θ', o + const Offset(34, -5), size: 9, bold: true);
  for (final a in [30.0, 45.0, 60.0]) {
    final q = _pol(o, r, -a);
    _dot(c, p, q, _orange, 2.8);
    _t(
      c,
      p,
      '${a.toInt()}°',
      _pol(o, r + 15, -a),
      size: 8.5,
      col: _orange,
      bold: true,
    );
  }
  _t(c, p, '1', o + const Offset(r + 2, 10), size: 8);
  _t(
    c,
    p,
    'sin',
    Offset(pt.dx + 12, (pt.dy + o.dy) / 2),
    size: 8,
    col: _red,
    bold: true,
  );
  _t(
    c,
    p,
    'cos',
    Offset((pt.dx + o.dx) / 2, o.dy + 10),
    size: 8,
    col: _green,
    bold: true,
  );
  _t(
    c,
    p,
    'tan',
    tanEnd + const Offset(10, 0),
    size: 8,
    col: _blue,
    bold: true,
  );
}

void _dUstelLog(Canvas c, WbArtPen p) {
  const o = Offset(85, 150);
  const s = 25.0;
  _axes(c, p, o, l: 80, r: 150, u: 140, d: 130);
  c.save();
  c.clipRect(const Rect.fromLTWH(3, 3, 234, 284));
  _curve(
    c,
    p.stroke(_red, 1.1),
    (x) => math.pow(2, x).toDouble(),
    -3,
    5,
    o,
    s,
    s,
  );
  _curve(
    c,
    p.stroke(_blue, 1.1),
    (x) => math.log(x) / math.ln2,
    0.06,
    6,
    o,
    s,
    s,
    200,
  );
  p.dashed(
    c,
    o + const Offset(-80, 80),
    o + const Offset(145, -145),
    paint: p.thin(0.5),
  );
  c.restore();
  _dot(c, p, o + const Offset(0, -s), _red, 2.8);
  _dot(c, p, o + const Offset(s, 0), _blue, 2.8);
  _t(c, p, 'y = 2ˣ', const Offset(168, 25), size: 10, col: _red, bold: true);
  _t(
    c,
    p,
    'y = log₂x',
    const Offset(180, 125),
    size: 10,
    col: _blue,
    bold: true,
  );
  _t(c, p, 'y = x', const Offset(35, 185), size: 8, col: _gray, bold: true);
  _t(c, p, '1', o + const Offset(-8, -s), size: 8);
  _t(c, p, '1', o + const Offset(s, 10), size: 8);
}

void _dMutlak(Canvas c, WbArtPen p) {
  const o = Offset(100, 145);
  const s = 22.0;
  _axes(c, p, o, l: 95, r: 105, u: 125, d: 30);
  c.save();
  c.clipRect(const Rect.fromLTWH(5, 15, 195, 170));
  _curve(
    c,
    p.stroke(_red, 1.2),
    (x) => (x - 1).abs(),
    -3.9,
    4.4,
    o,
    s,
    s,
    2 * 80,
  );
  c.restore();
  _dot(c, p, o + const Offset(s, 0), _blue, 3);
  _t(
    c,
    p,
    'y = |x - 1|',
    const Offset(150, 22),
    size: 10,
    col: _red,
    bold: true,
  );
  _t(c, p, '1', o + const Offset(s, 12), size: 8, col: _blue, bold: true);
  _t(c, p, 'Tepe noktası (1, 0)', const Offset(100, 190), size: 9);
}

void _dHiperbolInv(Canvas c, WbArtPen p) {
  const o = Offset(110, 110);
  const s = 30.0;
  _axes(c, p, o, l: 100, r: 100, u: 100, d: 100);
  c.save();
  c.clipRect(const Rect.fromLTWH(8, 8, 204, 204));
  _curve(c, p.stroke(_red, 1.1), (x) => 1 / x, 0.28, 3.4, o, s, s);
  _curve(c, p.stroke(_red, 1.1), (x) => 1 / x, -3.4, -0.28, o, s, s);
  p.dashed(
    c,
    o + const Offset(-90, 90),
    o + const Offset(90, -90),
    paint: p.thin(0.4),
  );
  c.restore();
  _dot(c, p, o + const Offset(s, -s), _blue, 3);
  _t(
    c,
    p,
    '(1,1)',
    o + const Offset(s + 4, -s - 9),
    size: 8,
    col: _blue,
    bold: true,
    anchor: 'left',
  );
  _t(c, p, 'y = 1/x', const Offset(172, 190), size: 10, col: _red, bold: true);
}

void _dElips(Canvas c, WbArtPen p) {
  const o = Offset(120, 100);
  const a = 90.0, b = 55.0;
  final cf = math.sqrt(a * a - b * b);
  _axes(c, p, o, l: 105, r: 105, u: 85, d: 80);
  c.drawOval(
    Rect.fromCenter(center: o, width: 2 * a, height: 2 * b),
    p.fill(_blue, 0.12),
  );
  c.drawOval(
    Rect.fromCenter(center: o, width: 2 * a, height: 2 * b),
    p.stroke(_red, 1.1),
  );
  final f1 = Offset(o.dx - cf, o.dy), f2 = Offset(o.dx + cf, o.dy);
  final pt = Offset(o.dx + a * math.cos(1.0), o.dy - b * math.sin(1.0));
  c.drawLine(f1, pt, p.thin(0.6));
  c.drawLine(f2, pt, p.thin(0.6));
  _dot(c, p, f1, _green, 3);
  _dot(c, p, f2, _green, 3);
  _dot(c, p, pt, _red, 3);
  _t(c, p, 'F₁', f1 + const Offset(0, 11), size: 9, col: _green, bold: true);
  _t(c, p, 'F₂', f2 + const Offset(0, 11), size: 9, col: _green, bold: true);
  _t(c, p, 'P', pt + const Offset(8, -6), size: 9, bold: true);
  _t(c, p, 'a', o + const Offset(a - 10, -9), size: 9, bold: true);
  _t(c, p, 'b', o + const Offset(-8, -b + 8), size: 9, bold: true);
  _t(
    c,
    p,
    'x²/a² + y²/b² = 1',
    const Offset(120, 190),
    size: 10,
    col: _red,
    bold: true,
  );
  _t(c, p, '|PF₁| + |PF₂| = 2a', const Offset(120, 12), size: 9, bold: true);
}

void _dHiperbol(Canvas c, WbArtPen p) {
  const o = Offset(120, 110);
  const a = 40.0, b = 30.0;
  _axes(c, p, o, l: 110, r: 110, u: 100, d: 95);
  c.save();
  c.clipRect(const Rect.fromLTWH(5, 8, 230, 204));
  p.dashed(
    c,
    o + const Offset(-110, -82.5),
    o + const Offset(110, 82.5),
    paint: p.thin(0.5),
  );
  p.dashed(
    c,
    o + const Offset(-110, 82.5),
    o + const Offset(110, -82.5),
    paint: p.thin(0.5),
  );
  for (final sign in [1.0, -1.0]) {
    final path = Path();
    for (int i = 0; i <= 80; i++) {
      final t = -1.6 + 3.2 * i / 80;
      final pt = Offset(
        o.dx + sign * a * (math.exp(t) + math.exp(-t)) / 2,
        o.dy - b * (math.exp(t) - math.exp(-t)) / 2,
      );
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    c.drawPath(path, p.stroke(_red, 1.1));
  }
  c.restore();
  _dot(c, p, o + const Offset(a, 0), _blue, 3);
  _dot(c, p, o + const Offset(-a, 0), _blue, 3);
  _dot(c, p, o + const Offset(50, 0), _green, 3);
  _dot(c, p, o + const Offset(-50, 0), _green, 3);
  _t(c, p, 'F₁', o + const Offset(-50, 12), size: 8, col: _green, bold: true);
  _t(c, p, 'F₂', o + const Offset(50, 12), size: 8, col: _green, bold: true);
  _t(
    c,
    p,
    'x²/a² - y²/b² = 1',
    const Offset(120, 214),
    size: 10,
    col: _red,
    bold: true,
  );
  _t(c, p, 'asimptot', const Offset(190, 38), size: 8, col: _gray, bold: true);
}

// ---------------------------------------------------------------------------
// Kümeler
// ---------------------------------------------------------------------------

Path _circ(Offset o, double r) =>
    Path()..addOval(Rect.fromCircle(center: o, radius: r));

void _dVenn2(Canvas c, WbArtPen p) {
  const a = Offset(90, 80), b = Offset(150, 80);
  c.drawCircle(a, 55, p.fill(_blue, 0.2));
  c.drawCircle(b, 55, p.fill(_red, 0.2));
  c.drawCircle(a, 55, p.line);
  c.drawCircle(b, 55, p.line);
  _t(c, p, 'A', const Offset(65, 30), size: 13, bold: true);
  _t(c, p, 'B', const Offset(175, 30), size: 13, bold: true);
  _t(c, p, 'A∩B', const Offset(120, 80), size: 10, bold: true);
  _t(c, p, 'A\\B', const Offset(68, 80), size: 9);
  _t(c, p, 'B\\A', const Offset(172, 80), size: 9);
  _t(c, p, 'A∪B = tüm renkli bölge', const Offset(120, 150), size: 9);
}

void _dVenn3(Canvas c, WbArtPen p) {
  const a = Offset(95, 75), b = Offset(145, 75), d = Offset(120, 118);
  c.drawCircle(a, 52, p.fill(_blue, 0.2));
  c.drawCircle(b, 52, p.fill(_red, 0.2));
  c.drawCircle(d, 52, p.fill(_green, 0.2));
  c.drawCircle(a, 52, p.line);
  c.drawCircle(b, 52, p.line);
  c.drawCircle(d, 52, p.line);
  _t(c, p, 'A', const Offset(60, 35), size: 13, bold: true);
  _t(c, p, 'B', const Offset(180, 35), size: 13, bold: true);
  _t(c, p, 'C', const Offset(120, 178), size: 13, bold: true);
  _t(c, p, 'A∩B∩C', const Offset(120, 90), size: 8, bold: true);
}

void _dAltKume(Canvas c, WbArtPen p) {
  const o = Offset(110, 80);
  c.drawOval(
    Rect.fromCenter(center: o, width: 200, height: 130),
    p.fill(_blue, 0.12),
  );
  c.drawOval(Rect.fromCenter(center: o, width: 200, height: 130), p.line);
  c.drawOval(
    Rect.fromCenter(center: o + const Offset(-10, 0), width: 80, height: 60),
    p.fill(_orange, 0.3),
  );
  c.drawOval(
    Rect.fromCenter(center: o + const Offset(-10, 0), width: 80, height: 60),
    p.line,
  );
  _t(c, p, 'A', o + const Offset(-10, 0), size: 14, bold: true);
  _t(c, p, 'B', const Offset(185, 40), size: 14, bold: true);
  _t(c, p, 'A ⊂ B', const Offset(110, 168), size: 11, col: _red, bold: true);
}

void _vennShade(Canvas c, WbArtPen p, String op, String cap) {
  const a = Offset(90, 75), b = Offset(150, 75);
  final pa = _circ(a, 55), pb = _circ(b, 55);
  Path shade;
  switch (op) {
    case 'i':
      shade = Path.combine(PathOperation.intersect, pa, pb);
      break;
    case 'u':
      shade = Path.combine(PathOperation.union, pa, pb);
      break;
    case 'd':
      shade = Path.combine(PathOperation.difference, pa, pb);
      break;
    default:
      shade = Path.combine(
        PathOperation.difference,
        Path()..addRect(const Rect.fromLTWH(10, 5, 220, 140)),
        pa,
      );
  }
  c.drawPath(shade, p.fill(_red, 0.45));
  c.drawCircle(a, 55, p.line);
  if (op != 'c') c.drawCircle(b, 55, p.line);
  if (op == 'c') c.drawRect(const Rect.fromLTWH(10, 5, 220, 140), p.thin(0.8));
  _t(c, p, 'A', const Offset(65, 28), size: 13, bold: true);
  if (op != 'c') _t(c, p, 'B', const Offset(175, 28), size: 13, bold: true);
  _t(c, p, cap, const Offset(120, 165), size: 11, col: _red, bold: true);
}

// ---------------------------------------------------------------------------
// Kesirler
// ---------------------------------------------------------------------------

void Function(Canvas, WbArtPen) _dPasta(int k, int n) {
  return (Canvas c, WbArtPen p) {
    const o = Offset(90, 85);
    const r = 70.0;
    final st = -math.pi / 2;
    c.drawCircle(o, r, p.fill(_gray, 0.1));
    for (int i = 0; i < k; i++) {
      c.drawPath(
        _sector(o, r, st + 2 * math.pi * i / n, 2 * math.pi / n),
        p.fill(_orange, 0.5),
      );
    }
    c.drawCircle(o, r, p.line);
    if (n > 1) {
      for (int i = 0; i < n; i++) {
        final a = st + 2 * math.pi * i / n;
        c.drawLine(o, o + Offset(math.cos(a), math.sin(a)) * r, p.line);
      }
    }
    _t(c, p, '$k/$n', const Offset(90, 178), size: 14, col: _red, bold: true);
  };
}

void _dKesirCubuk(Canvas c, WbArtPen p) {
  const parts = [1, 2, 3, 4, 5, 6, 8];
  const w = 220.0;
  final cols = [_blue, _red, _green, _orange, _purple, _teal, _pink];
  for (int i = 0; i < parts.length; i++) {
    final n = parts[i];
    final y = 8.0 + i * 24;
    for (int j = 0; j < n; j++) {
      final r = Rect.fromLTWH(48 + w / n * j, y, w / n, 19);
      c.drawRect(r, p.fill(cols[i], j == 0 ? 0.5 : 0.12));
      c.drawRect(r, p.line);
    }
    _t(
      c,
      p,
      n == 1 ? '1' : '1/$n',
      Offset(40, y + 9.5),
      size: 10,
      bold: true,
      anchor: 'right',
    );
  }
}

void _dYuzdeIzgara(Canvas c, WbArtPen p) {
  const cell = 16.0;
  const o = Offset(20, 10);
  for (int i = 0; i < 100; i++) {
    final r = Rect.fromLTWH(
      o.dx + (i % 10) * cell,
      o.dy + (i ~/ 10) * cell,
      cell,
      cell,
    );
    if (i < 35) c.drawRect(r, p.fill(_green, 0.45));
    c.drawRect(r, p.thin(0.4));
  }
  c.drawRect(Rect.fromLTWH(o.dx, o.dy, 160, 160), p.line);
  _t(
    c,
    p,
    '35/100 = 0,35 = %35',
    const Offset(100, 182),
    size: 10,
    col: _red,
    bold: true,
  );
  _t(c, p, '100 kare = 1 bütün', const Offset(100, 198), size: 8.5);
}

// ---------------------------------------------------------------------------
// İstatistik
// ---------------------------------------------------------------------------

void _dSutun(Canvas c, WbArtPen p) {
  const o = Offset(40, 160);
  c.drawLine(o, const Offset(40, 25), p.thin(0.9));
  c.drawLine(o, const Offset(250, 160), p.thin(0.9));
  for (int k = 0; k <= 3; k++) {
    final y = 160 - 40.0 * k;
    c.drawLine(Offset(36, y), Offset(250, y), p.thin(0.2));
    _t(c, p, '${4 * k}', Offset(30, y), size: 8, anchor: 'right');
  }
  const names = ['Mat', 'Fen', 'Türk', 'Sos'];
  const vals = [6, 10, 8, 12];
  final cols = [_blue, _red, _green, _orange];
  for (int i = 0; i < 4; i++) {
    final x = 55.0 + i * 52;
    final h = vals[i] * 10.0;
    final r = Rect.fromLTWH(x, 160 - h, 34, h);
    c.drawRect(r, p.fill(cols[i], 0.5));
    c.drawRect(r, p.line);
    _t(c, p, '${vals[i]}', Offset(x + 17, 160 - h - 8), size: 9, bold: true);
    _t(c, p, names[i], Offset(x + 17, 172), size: 9, bold: true);
  }
  _t(c, p, 'Sütun grafiği', const Offset(145, 10), size: 10, bold: true);
}

void _dDaireGrafik(Canvas c, WbArtPen p) {
  const o = Offset(90, 95);
  const r = 75.0;
  const vals = [40.0, 25.0, 20.0, 15.0];
  const names = ['Mat', 'Fen', 'Türkçe', 'Sosyal'];
  final cols = [_blue, _orange, _green, _purple];
  double a = -math.pi / 2;
  for (int i = 0; i < 4; i++) {
    final sw = vals[i] / 100 * 2 * math.pi;
    c.drawPath(_sector(o, r, a, sw), p.fill(cols[i], 0.5));
    c.drawPath(_sector(o, r, a, sw), p.line);
    final m = a + sw / 2;
    _t(
      c,
      p,
      '%${vals[i].toInt()}',
      o + Offset(math.cos(m), math.sin(m)) * (r * 0.62),
      size: 10,
      bold: true,
    );
    c.drawRect(Rect.fromLTWH(180, 55 + i * 22.0, 12, 12), p.fill(cols[i], 0.6));
    _t(c, p, names[i], Offset(197, 61 + i * 22.0), size: 9, anchor: 'left');
    a += sw;
  }
}

void _dCizgiGrafik(Canvas c, WbArtPen p) {
  const o = Offset(40, 150);
  c.drawLine(o, const Offset(40, 20), p.thin(0.9));
  c.drawLine(o, const Offset(255, 150), p.thin(0.9));
  for (int k = 1; k <= 4; k++) {
    c.drawLine(
      Offset(40, 150 - 30.0 * k),
      Offset(255, 150 - 30.0 * k),
      p.thin(0.15),
    );
    _t(c, p, '${k * 10}', Offset(34, 150 - 30.0 * k), size: 8, anchor: 'right');
  }
  const mon = ['Oca', 'Şub', 'Mar', 'Nis', 'May'];
  const v = [15, 25, 20, 35, 40];
  final pts = [
    for (int i = 0; i < 5; i++) Offset(65 + i * 45.0, 150 - v[i] * 3.0),
  ];
  c.drawPath(WbArtPen.poly(pts, close: false), p.stroke(_red, 1.1));
  for (int i = 0; i < 5; i++) {
    _dot(c, p, pts[i], _red, 3.5);
    _t(c, p, '${v[i]}', pts[i] + const Offset(0, -10), size: 8.5, bold: true);
    _t(c, p, mon[i], Offset(pts[i].dx, 162), size: 9, bold: true);
  }
  _t(c, p, 'Çizgi grafiği', const Offset(148, 8), size: 10, bold: true);
}

void _dHistogram(Canvas c, WbArtPen p) {
  const o = Offset(35, 160);
  c.drawLine(o, const Offset(35, 25), p.thin(0.9));
  c.drawLine(o, const Offset(255, 160), p.thin(0.9));
  const h = [30.0, 60.0, 100.0, 75.0, 40.0];
  const lab = ['0-10', '10-20', '20-30', '30-40', '40-50'];
  for (int i = 0; i < 5; i++) {
    final r = Rect.fromLTWH(40 + i * 42.0, 160 - h[i], 42, h[i]);
    c.drawRect(r, p.fill(_teal, 0.4));
    c.drawRect(r, p.line);
    _t(c, p, lab[i], Offset(61 + i * 42.0, 172), size: 8);
  }
  _t(c, p, 'Histogram', const Offset(145, 10), size: 10, bold: true);
  _t(c, p, 'sıklık', const Offset(20, 28), size: 8);
}

void _dKutuGrafik(Canvas c, WbArtPen p) {
  double x(num v) => 20 + 2.2 * v;
  c.drawLine(const Offset(20, 130), const Offset(240, 130), p.thin(0.9));
  for (int v = 0; v <= 100; v += 20) {
    c.drawLine(Offset(x(v), 126), Offset(x(v), 134), p.thin(0.9));
    _t(c, p, '$v', Offset(x(v), 144), size: 8);
  }
  c.drawLine(Offset(x(10), 95), Offset(x(30), 95), p.line);
  c.drawLine(Offset(x(70), 95), Offset(x(95), 95), p.line);
  c.drawLine(Offset(x(10), 82), Offset(x(10), 108), p.line);
  c.drawLine(Offset(x(95), 82), Offset(x(95), 108), p.line);
  final box = Rect.fromLTRB(x(30), 70, x(70), 120);
  c.drawRect(box, p.fill(_blue, 0.25));
  c.drawRect(box, p.line);
  c.drawLine(Offset(x(45), 70), Offset(x(45), 120), p.stroke(_red, 1.2));
  _t(c, p, 'En küçük', Offset(x(10), 62), size: 8, bold: true);
  _t(c, p, 'Q₁', Offset(x(30), 40), size: 9, bold: true);
  _t(c, p, 'Medyan', Offset(x(45), 58), size: 8, bold: true, col: _red);
  _t(c, p, 'Q₃', Offset(x(70), 40), size: 9, bold: true);
  _t(c, p, 'En büyük', Offset(x(95), 62), size: 8, bold: true);
  _t(c, p, 'Kutu grafiği', const Offset(130, 12), size: 10, bold: true);
}

void _tally(Canvas c, WbArtPen p, Offset s, int n) {
  double x = s.dx;
  int left = n;
  while (left > 0) {
    final k = math.min(left, 5);
    for (int i = 0; i < math.min(k, 4); i++) {
      c.drawLine(
        Offset(x + i * 5, s.dy - 7),
        Offset(x + i * 5, s.dy + 7),
        p.line,
      );
    }
    if (k == 5)
      c.drawLine(Offset(x - 3, s.dy + 5), Offset(x + 18, s.dy - 5), p.line);
    x += 28;
    left -= k;
  }
}

void _dSiklikTablo(Canvas c, WbArtPen p) {
  const xs = [15.0, 70.0, 175.0, 225.0];
  const rh = 26.0;
  const rows = 6;
  c.drawRect(Rect.fromLTWH(xs[0], 10, xs[3] - xs[0], rh), p.fill(_blue, 0.25));
  c.drawRect(Rect.fromLTWH(xs[0], 10, xs[3] - xs[0], rh * rows), p.line);
  for (int i = 1; i < rows; i++) {
    c.drawLine(
      Offset(xs[0], 10 + rh * i),
      Offset(xs[3], 10 + rh * i),
      p.thin(0.7),
    );
  }
  for (int j = 1; j < 3; j++) {
    c.drawLine(Offset(xs[j], 10), Offset(xs[j], 10 + rh * rows), p.thin(0.7));
  }
  _t(c, p, 'Veri', Offset((xs[0] + xs[1]) / 2, 23), size: 10, bold: true);
  _t(c, p, 'Çetele', Offset((xs[1] + xs[2]) / 2, 23), size: 10, bold: true);
  _t(c, p, 'Sıklık', Offset((xs[2] + xs[3]) / 2, 23), size: 10, bold: true);
  const f = [3, 6, 2, 4, 1];
  for (int i = 0; i < 5; i++) {
    final cy = 10 + rh * (i + 1) + rh / 2;
    _t(c, p, '${i + 1}', Offset((xs[0] + xs[1]) / 2, cy), size: 10);
    _tally(c, p, Offset(xs[1] + 10, cy), f[i]);
    _t(
      c,
      p,
      '${f[i]}',
      Offset((xs[2] + xs[3]) / 2, cy),
      size: 10,
      bold: true,
      col: _red,
    );
  }
}

// ---------------------------------------------------------------------------
// Olasılık
// ---------------------------------------------------------------------------

void _dAgac(Canvas c, WbArtPen p) {
  const root = Offset(25, 100);
  const l1 = [Offset(100, 55), Offset(100, 145)];
  const names = ['K', 'M'];
  const pr = ['2/5', '3/5'];
  final l2 = [
    const Offset(165, 28),
    const Offset(165, 82),
    const Offset(165, 118),
    const Offset(165, 172),
  ];
  const res = ['KK  4/25', 'KM  6/25', 'MK  6/25', 'MM  9/25'];
  _dot(c, p, root, p.color, 4);
  for (int i = 0; i < 2; i++) {
    c.drawLine(root, l1[i], p.line);
    _t(
      c,
      p,
      pr[i],
      _mid(root, l1[i]) + Offset(-10, i == 0 ? -6 : 6),
      size: 9,
      col: _red,
      bold: true,
    );
    c.drawCircle(l1[i], 10, p.fill(i == 0 ? _red : _blue, 0.3));
    _t(c, p, names[i], l1[i], size: 10, bold: true);
    for (int j = 0; j < 2; j++) {
      final k = i * 2 + j;
      c.drawLine(l1[i], l2[k], p.line);
      _t(
        c,
        p,
        pr[j],
        _mid(l1[i], l2[k]) + Offset(-4, j == 0 ? -8 : 8),
        size: 8.5,
        col: _red,
        bold: true,
      );
      c.drawCircle(l2[k], 9, p.fill(j == 0 ? _red : _blue, 0.3));
      _t(c, p, names[j], l2[k], size: 9, bold: true);
      _t(
        c,
        p,
        res[k],
        l2[k] + const Offset(15, 0),
        size: 9,
        bold: true,
        anchor: 'left',
      );
    }
  }
  _t(
    c,
    p,
    'Torba: 2 kırmızı (K), 3 mavi (M) – iadeli',
    const Offset(120, 195),
    size: 8,
  );
}

void _die(Canvas c, WbArtPen p, Offset tl, double s, int n) {
  final r = RRect.fromRectAndRadius(
    Rect.fromLTWH(tl.dx, tl.dy, s, s),
    const Radius.circular(8),
  );
  c.drawRRect(r, p.fill(_gray, 0.12));
  c.drawRRect(r, p.line);
  const pips = {
    1: [4],
    2: [0, 8],
    3: [0, 4, 8],
    4: [0, 2, 6, 8],
    5: [0, 2, 4, 6, 8],
    6: [0, 2, 3, 5, 6, 8],
  };
  for (final i in pips[n]!) {
    final o = Offset(
      tl.dx + s * (0.22 + 0.28 * (i % 3)),
      tl.dy + s * (0.22 + 0.28 * (i ~/ 3)),
    );
    c.drawCircle(o, s * 0.075, p.solid);
  }
}

void _dZar(Canvas c, WbArtPen p) {
  for (int i = 0; i < 6; i++) {
    _die(c, p, Offset(16 + (i % 3) * 66.0, 14 + (i ~/ 3) * 66.0), 56, i + 1);
  }
}

void _dMadeni(Canvas c, WbArtPen p) {
  const a = Offset(60, 65), b = Offset(170, 65);
  c.drawCircle(a, 45, p.fill(_yellow, 0.35));
  c.drawCircle(a, 45, p.line);
  c.drawCircle(a, 37, p.thin(0.5));
  _t(c, p, 'YAZI', a + const Offset(0, -8), size: 12, bold: true);
  _t(c, p, '1 TL', a + const Offset(0, 10), size: 10, bold: true, col: _red);
  c.drawCircle(b, 45, p.fill(_gray, 0.3));
  c.drawCircle(b, 45, p.line);
  c.drawCircle(b, 37, p.thin(0.5));
  _pg(c, p, WbArtPen.regular(b, 18, 5), _orange, 0.4);
  _t(c, p, 'TURA', b + const Offset(0, 28), size: 9, bold: true);
  _t(
    c,
    p,
    'P(Yazı) = P(Tura) = 1/2',
    const Offset(115, 125),
    size: 10,
    bold: true,
    col: _red,
  );
}

void _dCarpimTablo(Canvas c, WbArtPen p) {
  const cell = 22.0;
  const o = Offset(4, 4);
  for (int i = 0; i <= 10; i++) {
    for (int j = 0; j <= 10; j++) {
      final r = Rect.fromLTWH(o.dx + j * cell, o.dy + i * cell, cell, cell);
      if (i == 0 || j == 0) {
        c.drawRect(r, p.fill(_blue, 0.3));
      } else if (i == j) {
        c.drawRect(r, p.fill(_yellow, 0.3));
      }
      c.drawRect(r, p.thin(0.4));
      if (i == 0 && j == 0) {
        _t(c, p, '×', r.center, size: 10, bold: true);
      } else if (i == 0) {
        _t(c, p, '$j', r.center, size: 9, bold: true);
      } else if (j == 0) {
        _t(c, p, '$i', r.center, size: 9, bold: true);
      } else {
        _t(c, p, '${i * j}', r.center, size: 8);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Sayılar
// ---------------------------------------------------------------------------

void _dPascal(Canvas c, WbArtPen p) {
  const rows = [
    [1],
    [1, 1],
    [1, 2, 1],
    [1, 3, 3, 1],
    [1, 4, 6, 4, 1],
    [1, 5, 10, 10, 5, 1],
  ];
  for (int i = 0; i < rows.length; i++) {
    for (int j = 0; j < rows[i].length; j++) {
      final o = Offset(110 + (j - i / 2) * 34, 22 + i * 28.0);
      c.drawCircle(o, 12, p.fill(i.isEven ? _blue : _orange, 0.2));
      c.drawCircle(o, 12, p.thin(0.6));
      _t(c, p, '${rows[i][j]}', o, size: 10, bold: true);
    }
  }
  _t(c, p, 'Pascal üçgeni', const Offset(110, 194), size: 10, bold: true);
}

void _dBasamak(Canvas c, WbArtPen p) {
  const names = [
    'Yüzbinler',
    'Onbinler',
    'Binler',
    'Yüzler',
    'Onlar',
    'Birler',
  ];
  const digs = ['3', '4', '7', '2', '5', '8'];
  const w = 46.0;
  for (int i = 0; i < 6; i++) {
    final x = 12 + i * w;
    c.drawRect(
      Rect.fromLTWH(x, 10, w, 28),
      p.fill(i < 3 ? _blue : _green, 0.3),
    );
    c.drawRect(Rect.fromLTWH(x, 10, w, 68), p.thin(0.8));
    _t(c, p, names[i], Offset(x + w / 2, 24), size: 7.5, bold: true);
    _t(c, p, digs[i], Offset(x + w / 2, 58), size: 20, bold: true);
  }
  c.drawRect(const Rect.fromLTWH(12, 10, 276, 68), p.line);
  c.drawLine(const Offset(150, 10), const Offset(150, 78), p.line);
  _t(
    c,
    p,
    'Binler sınıfı',
    const Offset(81, 92),
    size: 8.5,
    col: _blue,
    bold: true,
  );
  _t(
    c,
    p,
    'Birler sınıfı',
    const Offset(219, 92),
    size: 8.5,
    col: _green,
    bold: true,
  );
  _t(c, p, '347 258', const Offset(150, 112), size: 12, bold: true, col: _red);
}

void _dAsalAgac(Canvas c, WbArtPen p) {
  const n60 = Offset(100, 25);
  const pairs = [
    [Offset(100, 25), Offset(60, 70)],
    [Offset(100, 25), Offset(140, 70)],
    [Offset(140, 70), Offset(110, 115)],
    [Offset(140, 70), Offset(170, 115)],
    [Offset(170, 115), Offset(140, 160)],
    [Offset(170, 115), Offset(200, 160)],
  ];
  for (final e in pairs) {
    c.drawLine(e[0], e[1], p.thin(0.8));
  }
  void node(Offset o, String s, bool prime) {
    c.drawCircle(o, 13, p.fill(prime ? _green : _gray, 0.35));
    c.drawCircle(o, 13, p.thin(0.8));
    _t(c, p, s, o, size: 11, bold: true);
  }

  node(n60, '60', false);
  node(const Offset(60, 70), '2', true);
  node(const Offset(140, 70), '30', false);
  node(const Offset(110, 115), '2', true);
  node(const Offset(170, 115), '15', false);
  node(const Offset(140, 160), '3', true);
  node(const Offset(200, 160), '5', true);
  _t(
    c,
    p,
    '60 = 2² × 3 × 5',
    const Offset(60, 185),
    size: 10,
    bold: true,
    col: _red,
  );
}

void _dEbobEkok(Canvas c, WbArtPen p) {
  const a = Offset(90, 80), b = Offset(150, 80);
  c.drawCircle(a, 55, p.fill(_blue, 0.2));
  c.drawCircle(b, 55, p.fill(_red, 0.2));
  c.drawCircle(a, 55, p.line);
  c.drawCircle(b, 55, p.line);
  _t(c, p, '12', const Offset(60, 22), size: 11, bold: true);
  _t(c, p, '18', const Offset(180, 22), size: 11, bold: true);
  _t(c, p, '2', const Offset(68, 80), size: 14, bold: true);
  _t(c, p, '2 · 3', const Offset(120, 80), size: 12, bold: true, col: _red);
  _t(c, p, '3', const Offset(172, 80), size: 14, bold: true);
  _t(
    c,
    p,
    'EBOB = 2·3 = 6',
    const Offset(120, 155),
    size: 10,
    bold: true,
    col: _red,
  );
  _t(
    c,
    p,
    'EKOK = 2·2·3·3 = 36',
    const Offset(120, 172),
    size: 10,
    bold: true,
    col: _green,
  );
}

// ---------------------------------------------------------------------------
// Dönüşüm geometrisi
// ---------------------------------------------------------------------------

void _triImg(Canvas c, WbArtPen p, List<Offset> pts, Color col, bool prime) {
  _pg(c, p, pts, col, 0.25);
  const lab = ['A', 'B', 'C'];
  final ctr = Offset(
    (pts[0].dx + pts[1].dx + pts[2].dx) / 3,
    (pts[0].dy + pts[1].dy + pts[2].dy) / 3,
  );
  for (int i = 0; i < 3; i++) {
    _t(
      c,
      p,
      prime ? "${lab[i]}'" : lab[i],
      pts[i] + _u(ctr, pts[i]) * 11,
      size: 9,
      bold: true,
      col: col,
    );
  }
}

void _dOteleme(Canvas c, WbArtPen p) {
  const t = [Offset(25, 110), Offset(75, 110), Offset(25, 65)];
  const v = Offset(115, 40);
  final t2 = [for (final q in t) q + v];
  _triImg(c, p, t, _blue, false);
  _triImg(c, p, t2, _red, true);
  p.dashed(c, t[0], t2[0], paint: p.thin(0.6));
  p.dashed(c, t[1], t2[1], paint: p.thin(0.6));
  p.dashed(c, t[2], t2[2], paint: p.thin(0.6));
  p.arrow(c, const Offset(60, 160), const Offset(175, 160), c: _green, size: 8);
  _t(
    c,
    p,
    'öteleme vektörü',
    const Offset(118, 174),
    size: 9,
    col: _green,
    bold: true,
  );
}

void _dYansima(Canvas c, WbArtPen p) {
  const t = [Offset(30, 120), Offset(95, 120), Offset(30, 55)];
  final t2 = [for (final q in t) Offset(240 - q.dx, q.dy)];
  p.dashed(
    c,
    const Offset(120, 15),
    const Offset(120, 185),
    paint: p.stroke(_green, 0.9),
  );
  _t(
    c,
    p,
    'yansıma doğrusu',
    const Offset(120, 197),
    size: 9,
    col: _green,
    bold: true,
  );
  _triImg(c, p, t, _blue, false);
  _triImg(c, p, t2, _red, true);
  for (int i = 0; i < 3; i++) {
    p.dashed(c, t[i], t2[i], paint: p.thin(0.4));
  }
}

void _dDonme(Canvas c, WbArtPen p) {
  const o = Offset(120, 100);
  const t = [Offset(150, 110), Offset(200, 110), Offset(150, 60)];
  final t2 = [for (final q in t) o + Offset(-(q.dy - o.dy), q.dx - o.dx)];
  _triImg(c, p, t, _blue, false);
  _triImg(c, p, t2, _red, true);
  _dot(c, p, o, _green, 3.5);
  _t(c, p, 'O', o + const Offset(-10, -8), size: 10, col: _green, bold: true);
  p.dashed(c, o, t[0], paint: p.thin(0.5));
  p.dashed(c, o, t2[0], paint: p.thin(0.5));
  _arcAt(c, p.stroke(_green, 0.8), o, t[0], t2[0], 30);
  _t(c, p, '90°', o + const Offset(38, 36), size: 9, col: _green, bold: true);
  _t(
    c,
    p,
    'Dönme (O merkezli, saat yönü)',
    const Offset(120, 195),
    size: 9,
    bold: true,
  );
}

void _dAralik(Canvas c, WbArtPen p) {
  const rows = [
    [1.0, 4.0, 1.0, 1.0],
    [-1.0, 3.0, 0.0, 0.0],
    [0.0, 3.0, 1.0, 0.0],
    [2.0, 5.0, 0.0, 1.0],
  ];
  const txt = [
    '[1, 4]  →  1 ≤ x ≤ 4',
    '(-1, 3)  →  -1 < x < 3',
    '[0, 3)  →  0 ≤ x < 3',
    '(2, 5]  →  2 < x ≤ 5',
  ];
  double x(double v) => 40 + 28 * (v + 2);
  for (int i = 0; i < 4; i++) {
    final y = 42.0 + i * 50;
    c.drawLine(Offset(20, y), Offset(268, y), p.thin(0.8));
    p.arrow(c, Offset(260, y), Offset(268, y), size: 6, line: false);
    for (int v = -2; v <= 6; v++) {
      c.drawLine(
        Offset(x(v.toDouble()), y - 3),
        Offset(x(v.toDouble()), y + 3),
        p.thin(0.8),
      );
      _t(c, p, '$v', Offset(x(v.toDouble()), y + 11), size: 7.5);
    }
    final r = rows[i];
    c.drawLine(Offset(x(r[0]), y), Offset(x(r[1]), y), p.stroke(_red, 2));
    for (int k = 0; k < 2; k++) {
      final o = Offset(x(r[k]), y);
      final closed = r[2 + k] == 1.0;
      if (closed) {
        c.drawCircle(o, 4, p.fill(_red));
      } else {
        c.drawCircle(o, 4, p.fill(Colors.white));
        c.drawCircle(o, 4, p.stroke(_red, 0.8));
      }
    }
    _t(c, p, txt[i], Offset(20, y - 18), size: 9.5, bold: true, anchor: 'left');
  }
}

// ---------------------------------------------------------------------------
// Kütüphane
// ---------------------------------------------------------------------------

final List<WbArtItem> wbArtMath = [
  // 3B
  WbArtItem(
    'mat_kup',
    'Küp',
    200,
    200,
    _dKup,
    tags: 'küp 3b cisim hacim yüzey alan kenar eş kare',
  ),
  WbArtItem(
    'mat_dikdortgen_prizma',
    'Dikdörtgenler prizması',
    200,
    200,
    _dPrizma,
    tags: 'dikdörtgenler prizması kutu hacim 3b cisim',
  ),
  WbArtItem(
    'mat_ucgen_prizma',
    'Üçgen prizma',
    200,
    200,
    _dUcgenPrizma,
    tags: 'üçgen prizma 3b cisim hacim',
  ),
  WbArtItem(
    'mat_kare_piramit',
    'Kare piramit',
    200,
    200,
    _dKarePiramit,
    tags: 'kare piramit tepe taban hacim 3b cisim',
  ),
  WbArtItem(
    'mat_silindir',
    'Silindir',
    200,
    200,
    _dSilindir,
    tags: 'silindir 3b cisim hacim yarıçap yükseklik',
  ),
  WbArtItem(
    'mat_koni',
    'Koni',
    200,
    200,
    _dKoni,
    tags: 'koni 3b cisim hacim yarıçap yükseklik',
  ),
  WbArtItem(
    'mat_kure',
    'Küre',
    200,
    200,
    _dKure,
    tags: 'küre top 3b cisim ekvator yarıçap hacim',
  ),
  WbArtItem(
    'mat_kesik_koni',
    'Kesik koni',
    200,
    200,
    _dKesikKoni,
    tags: 'kesik koni 3b cisim',
  ),
  WbArtItem(
    'mat_kesik_piramit',
    'Kesik piramit',
    200,
    200,
    _dKesikPiramit,
    tags: 'kesik piramit 3b cisim',
  ),
  WbArtItem(
    'mat_kup_acilim',
    'Küp açılımı',
    200,
    180,
    _dKupAcilim,
    tags: 'küp açılımı ağ yüzey alan',
  ),
  WbArtItem(
    'mat_silindir_acilim',
    'Silindir açılımı',
    200,
    200,
    _dSilindirAcilim,
    tags: 'silindir açılımı yanal alan',
  ),
  WbArtItem(
    'mat_koni_acilim',
    'Koni açılımı',
    200,
    210,
    _dKoniAcilim,
    tags: 'koni açılımı daire dilimi',
  ),

  // Düzlem geometri
  WbArtItem(
    'mat_pisagor',
    'Pisagor teoremi',
    200,
    200,
    _dPisagor,
    tags: 'pisagor dik üçgen hipotenüs kareler a2 b2 c2',
  ),
  WbArtItem(
    'mat_yukseklik',
    'Üçgende yükseklik',
    200,
    200,
    _dYukseklik,
    tags: 'üçgen yükseklik dik inme',
  ),
  WbArtItem(
    'mat_kenarortay',
    'Üçgende kenarortay',
    200,
    200,
    _dKenarortay,
    tags: 'üçgen kenarortay orta nokta',
  ),
  WbArtItem(
    'mat_aciortay',
    'Üçgende açıortay',
    200,
    200,
    _dAciortay,
    tags: 'üçgen açıortay açı',
  ),
  WbArtItem(
    'mat_cevrel_cember',
    'Çevrel çember',
    200,
    200,
    _dCevrel,
    tags: 'çevrel çember üçgen dış teğet merkez',
  ),
  WbArtItem(
    'mat_ic_teget_cember',
    'İç teğet çember',
    200,
    200,
    _dIcTeget,
    tags: 'iç teğet çember üçgen merkez incenter',
  ),
  WbArtItem(
    'mat_daire_dilimi',
    'Daire dilimi ve yay',
    200,
    200,
    _dDilim,
    tags: 'daire dilimi yay açı alan',
  ),
  WbArtItem(
    'mat_kiris',
    'Çap, yarıçap, kiriş',
    200,
    200,
    _dKiris,
    tags: 'kiriş çap yarıçap çember',
  ),
  WbArtItem(
    'mat_teget',
    'Çemberde teğet',
    220,
    200,
    _dTeget,
    tags: 'teğet çember yarıçap dik',
  ),
  WbArtItem(
    'mat_kesen',
    'Çemberde kesen',
    210,
    200,
    _dKesen,
    tags: 'kesen çember doğru',
  ),
  WbArtItem(
    'mat_merkez_cevre_aci',
    'Merkez ve çevre açı',
    200,
    200,
    _dMerkezCevre,
    tags: 'merkez açı çevre açı çember',
  ),
  WbArtItem(
    'mat_paralel_kesen',
    'Paralel doğrular ve kesen',
    240,
    210,
    _dParalel,
    tags: 'paralel doğru kesen iç ters yöndeş açı',
  ),
  WbArtItem(
    'mat_aci_cesitleri',
    'Açı çeşitleri',
    280,
    120,
    _dAciCesit,
    tags: 'açı dar dik geniş doğru çeşitleri',
  ),
  WbArtItem(
    'mat_kare',
    'Kare',
    200,
    175,
    _dKare,
    tags: 'kare dörtgen alan çevre',
  ),
  WbArtItem(
    'mat_dikdortgen',
    'Dikdörtgen',
    200,
    160,
    _dDikdortgen,
    tags: 'dikdörtgen dörtgen alan çevre',
  ),
  WbArtItem(
    'mat_paralelkenar',
    'Paralelkenar',
    200,
    160,
    _dParalelkenar,
    tags: 'paralelkenar dörtgen alan yükseklik',
  ),
  WbArtItem(
    'mat_es_dortgen',
    'Eşkenar dörtgen',
    200,
    170,
    _dEsDortgen,
    tags: 'eşkenar dörtgen dörtgen köşegen',
  ),
  WbArtItem(
    'mat_yamuk',
    'Yamuk',
    200,
    170,
    _dYamuk,
    tags: 'yamuk dörtgen alan taban yükseklik',
  ),
  WbArtItem(
    'mat_deltoid',
    'Deltoid',
    200,
    175,
    _dDeltoid,
    tags: 'deltoid dörtgen uçurtma köşegen',
  ),
  WbArtItem(
    'mat_duzgun_cokgenler',
    'Düzgün çokgenler (3-8)',
    290,
    200,
    _dCokgenler,
    tags: 'düzgün çokgen üçgen kare beşgen altıgen yedigen sekizgen',
  ),
  WbArtItem(
    'mat_duzgun_besgen',
    'Düzgün beşgen',
    200,
    200,
    _dDuzgun(5, 'Düzgün beşgen'),
    tags: 'düzgün beşgen çokgen',
  ),
  WbArtItem(
    'mat_duzgun_altigen',
    'Düzgün altıgen',
    200,
    200,
    _dDuzgun(6, 'Düzgün altıgen'),
    tags: 'düzgün altıgen çokgen petek',
  ),
  WbArtItem(
    'mat_duzgun_yedigen',
    'Düzgün yedigen',
    200,
    200,
    _dDuzgun(7, 'Düzgün yedigen'),
    tags: 'düzgün yedigen çokgen',
  ),
  WbArtItem(
    'mat_duzgun_sekizgen',
    'Düzgün sekizgen',
    200,
    200,
    _dDuzgun(8, 'Düzgün sekizgen'),
    tags: 'düzgün sekizgen çokgen',
  ),
  WbArtItem(
    'mat_kare_formul',
    'Karenin alan ve çevresi',
    220,
    140,
    _dKareFormul,
    tags: 'kare alan çevre formül şablon',
  ),
  WbArtItem(
    'mat_dikdortgen_formul',
    'Dikdörtgenin alan ve çevresi',
    250,
    140,
    _dDikdortgenFormul,
    tags: 'dikdörtgen alan çevre formül şablon',
  ),
  WbArtItem(
    'mat_daire_formul',
    'Dairenin alan ve çevresi',
    240,
    160,
    _dDaireFormul,
    tags: 'daire alan çevre pi formül şablon',
  ),
  WbArtItem(
    'mat_es_ucgen_yukseklik',
    'Eşkenar üçgende yükseklik',
    200,
    190,
    _dEsUcgenYuk,
    tags: 'eşkenar üçgen yükseklik formül',
  ),
  WbArtItem(
    'mat_benzer_ucgenler',
    'Benzer üçgenler',
    230,
    195,
    _dBenzer,
    tags: 'benzer üçgen benzerlik oran',
  ),
  WbArtItem(
    'mat_thales',
    'Thales teoremi',
    220,
    185,
    _dThales,
    tags: 'thales temel orantı teoremi paralel üçgen',
  ),

  // Analitik / fonksiyon
  WbArtItem(
    'mat_parabol',
    'Koordinat düzlemi ve parabol',
    220,
    190,
    _dParabol,
    tags: 'parabol koordinat düzlemi ikinci derece fonksiyon grafik',
  ),
  WbArtItem(
    'mat_dogru_grafik',
    'Doğru grafiği y = mx + n',
    220,
    210,
    _dDogruGrafik,
    tags: 'doğru grafiği eğim doğrusal fonksiyon koordinat',
  ),
  WbArtItem(
    'mat_sin_cos',
    'Sinüs ve kosinüs grafiği',
    295,
    150,
    _dSinCos,
    tags: 'sinüs kosinüs dalga trigonometri grafik',
  ),
  WbArtItem(
    'mat_birim_cember',
    'Birim çember',
    240,
    245,
    _dBirimCember,
    tags: 'birim çember sin cos tan trigonometri 30 45 60',
  ),
  WbArtItem(
    'mat_ustel_log',
    'Üstel ve logaritma grafiği',
    240,
    290,
    _dUstelLog,
    tags: 'üstel logaritma fonksiyon grafik ters fonksiyon',
  ),
  WbArtItem(
    'mat_mutlak_deger',
    'Mutlak değer grafiği',
    205,
    200,
    _dMutlak,
    tags: 'mutlak değer fonksiyon grafik',
  ),
  WbArtItem(
    'mat_hiperbol_ters',
    'Hiperbol y = 1/x',
    220,
    220,
    _dHiperbolInv,
    tags: 'hiperbol ters orantı 1/x grafik',
  ),
  WbArtItem(
    'mat_elips',
    'Elips',
    240,
    200,
    _dElips,
    tags: 'elips odak konik eksen',
  ),
  WbArtItem(
    'mat_hiperbol',
    'Hiperbol (konik)',
    240,
    225,
    _dHiperbol,
    tags: 'hiperbol odak asimptot konik',
  ),

  // Kümeler
  WbArtItem(
    'mat_venn2',
    'Venn şeması (2 küme)',
    240,
    160,
    _dVenn2,
    tags: 'venn şeması küme iki kesişim birleşim',
  ),
  WbArtItem(
    'mat_venn3',
    'Venn şeması (3 küme)',
    240,
    190,
    _dVenn3,
    tags: 'venn şeması küme üç kesişim birleşim',
  ),
  WbArtItem(
    'mat_alt_kume',
    'Alt küme',
    220,
    165,
    _dAltKume,
    tags: 'alt küme kapsama küme',
  ),
  WbArtItem(
    'mat_kesisim',
    'Kesişim (A∩B)',
    240,
    175,
    (c, p) => _vennShade(c, p, 'i', 'A ∩ B'),
    tags: 'kesişim küme venn taralı',
  ),
  WbArtItem(
    'mat_birlesim',
    'Birleşim (A∪B)',
    240,
    175,
    (c, p) => _vennShade(c, p, 'u', 'A ∪ B'),
    tags: 'birleşim küme venn taralı',
  ),
  WbArtItem(
    'mat_fark',
    'Fark (A\\B)',
    240,
    175,
    (c, p) => _vennShade(c, p, 'd', 'A \\ B'),
    tags: 'fark küme venn taralı',
  ),
  WbArtItem(
    'mat_tumleyen',
    'Tümleyen (A\')',
    240,
    175,
    (c, p) => _vennShade(c, p, 'c', "A'"),
    tags: 'tümleyen evrensel küme venn taralı',
  ),

  // Kesirler
  WbArtItem(
    'mat_kesir_1_2',
    'Kesir pastası 1/2',
    180,
    195,
    _dPasta(1, 2),
    tags: 'kesir pasta yarım bir bölü iki',
  ),
  WbArtItem(
    'mat_kesir_1_3',
    'Kesir pastası 1/3',
    180,
    195,
    _dPasta(1, 3),
    tags: 'kesir pasta üçte bir',
  ),
  WbArtItem(
    'mat_kesir_1_4',
    'Kesir pastası 1/4',
    180,
    195,
    _dPasta(1, 4),
    tags: 'kesir pasta çeyrek dörtte bir',
  ),
  WbArtItem(
    'mat_kesir_2_3',
    'Kesir pastası 2/3',
    180,
    195,
    _dPasta(2, 3),
    tags: 'kesir pasta üçte iki',
  ),
  WbArtItem(
    'mat_kesir_3_4',
    'Kesir pastası 3/4',
    180,
    195,
    _dPasta(3, 4),
    tags: 'kesir pasta dörtte üç',
  ),
  WbArtItem(
    'mat_kesir_cubuk',
    'Kesir çubukları',
    280,
    180,
    _dKesirCubuk,
    tags: 'kesir çubuk eşit kesirler karşılaştırma',
  ),
  WbArtItem(
    'mat_yuzde_izgara',
    'Yüzde ızgarası (10x10)',
    200,
    205,
    _dYuzdeIzgara,
    tags: 'yüzde ondalık ızgara 100 kare kesir',
  ),

  // İstatistik
  WbArtItem(
    'mat_sutun_grafik',
    'Sütun grafiği',
    260,
    180,
    _dSutun,
    tags: 'sütun grafik çubuk istatistik veri',
  ),
  WbArtItem(
    'mat_daire_grafik',
    'Daire grafiği',
    260,
    190,
    _dDaireGrafik,
    tags: 'daire grafik pasta istatistik yüzde',
  ),
  WbArtItem(
    'mat_cizgi_grafik',
    'Çizgi grafiği',
    265,
    175,
    _dCizgiGrafik,
    tags: 'çizgi grafik istatistik zaman veri',
  ),
  WbArtItem(
    'mat_histogram',
    'Histogram',
    260,
    180,
    _dHistogram,
    tags: 'histogram sıklık sınıf istatistik',
  ),
  WbArtItem(
    'mat_kutu_grafik',
    'Kutu grafiği',
    260,
    155,
    _dKutuGrafik,
    tags: 'kutu grafiği çeyrek medyan istatistik',
  ),
  WbArtItem(
    'mat_siklik_tablo',
    'Sıklık tablosu',
    240,
    170,
    _dSiklikTablo,
    tags: 'sıklık tablosu çetele veri istatistik',
  ),

  // Olasılık
  WbArtItem(
    'mat_agac_diyagram',
    'Olasılık ağaç diyagramı',
    260,
    205,
    _dAgac,
    tags: 'ağaç diyagramı olasılık torba',
  ),
  WbArtItem(
    'mat_zar_yuzleri',
    'Zar yüzleri',
    210,
    145,
    _dZar,
    tags: 'zar yüzleri olasılık',
  ),
  WbArtItem(
    'mat_madeni_para',
    'Madeni para',
    230,
    135,
    _dMadeni,
    tags: 'madeni para yazı tura olasılık',
  ),
  WbArtItem(
    'mat_carpim_tablosu',
    'Çarpım tablosu şablonu',
    250,
    250,
    _dCarpimTablo,
    tags: 'çarpım tablosu çarpma şablon',
  ),

  // Sayılar
  WbArtItem(
    'mat_pascal',
    'Pascal üçgeni',
    220,
    205,
    _dPascal,
    tags: 'pascal üçgeni binom sayılar',
  ),
  WbArtItem(
    'mat_basamak_deger',
    'Basamak değer tablosu',
    300,
    125,
    _dBasamak,
    tags: 'basamak değer tablosu sınıf binler birler',
  ),
  WbArtItem(
    'mat_asal_carpan_agaci',
    'Asal çarpan ağacı',
    230,
    195,
    _dAsalAgac,
    tags: 'asal çarpanlara ayırma ağaç sayılar',
  ),
  WbArtItem(
    'mat_ebob_ekok',
    'EBOB - EKOK Venn',
    240,
    185,
    _dEbobEkok,
    tags: 'ebob ekok venn bölen kat asal çarpan',
  ),

  // Dönüşüm geometrisi
  WbArtItem(
    'mat_oteleme',
    'Öteleme',
    230,
    185,
    _dOteleme,
    tags: 'öteleme dönüşüm geometrisi vektör',
  ),
  WbArtItem(
    'mat_yansima',
    'Yansıma',
    240,
    205,
    _dYansima,
    tags: 'yansıma simetri dönüşüm geometrisi',
  ),
  WbArtItem(
    'mat_donme',
    'Dönme',
    240,
    205,
    _dDonme,
    tags: 'dönme rotasyon dönüşüm geometrisi',
  ),

  // Sayı doğrusu
  WbArtItem(
    'mat_aralik_sayi_dogrusu',
    'Sayı doğrusunda aralık',
    280,
    210,
    _dAralik,
    tags: 'sayı doğrusu aralık açık kapalı eşitsizlik',
  ),
];
