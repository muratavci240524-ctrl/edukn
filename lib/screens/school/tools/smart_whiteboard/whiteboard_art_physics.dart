import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'whiteboard_art_core.dart';

/// Fizik şekilleri: basit makineler, kuvvet-hareket, akışkanlar, ısı,
/// elektrik, manyetizma, optik, dalgalar ve modern fizik.

const _blue = WbArtColors.blue;
const _lblue = WbArtColors.lightBlue;
const _red = WbArtColors.red;
const _green = WbArtColors.green;
const _yellow = WbArtColors.yellow;
const _orange = WbArtColors.orange;
const _purple = WbArtColors.purple;
const _gray = WbArtColors.gray;
const _brown = WbArtColors.brown;
const _teal = WbArtColors.teal;
const _pink = WbArtColors.pink;

// ───────────────────────── Yardımcılar ─────────────────────────

Offset _o(double x, double y) => Offset(x, y);

void _t(
  Canvas c,
  WbArtPen p,
  String s,
  double x,
  double y, {
  double size = 10,
  Color? col,
  bool bold = false,
  String anchor = 'center',
}) =>
    p.text(c, s, Offset(x, y), size: size, c: col, bold: bold, anchor: anchor);

void _l(Canvas c, WbArtPen p, double x1, double y1, double x2, double y2) =>
    c.drawLine(Offset(x1, y1), Offset(x2, y2), p.line);

void _th(Canvas c, WbArtPen p, double x1, double y1, double x2, double y2) =>
    c.drawLine(Offset(x1, y1), Offset(x2, y2), p.thin());

void _lc(
  Canvas c,
  WbArtPen p,
  Color col,
  double x1,
  double y1,
  double x2,
  double y2, [
  double f = 1,
]) => c.drawLine(Offset(x1, y1), Offset(x2, y2), p.stroke(col, f));

void _ar(
  Canvas c,
  WbArtPen p,
  double x1,
  double y1,
  double x2,
  double y2, {
  Color? col,
  double size = 7,
}) => p.arrow(c, Offset(x1, y1), Offset(x2, y2), c: col, size: size);

void _dar(
  Canvas c,
  WbArtPen p,
  double x1,
  double y1,
  double x2,
  double y2, {
  Color? col,
}) {
  p.arrow(c, Offset(x1, y1), Offset(x2, y2), c: col, size: 5);
  p.arrow(c, Offset(x2, y2), Offset(x1, y1), c: col, size: 5, line: false);
}

void _da(Canvas c, WbArtPen p, double x1, double y1, double x2, double y2) =>
    p.dashed(c, Offset(x1, y1), Offset(x2, y2));

void _circ(
  Canvas c,
  WbArtPen p,
  double x,
  double y,
  double r, {
  Color? fill,
  double a = 0.25,
  bool stroke = true,
}) {
  if (fill != null) c.drawCircle(Offset(x, y), r, p.fill(fill, a));
  if (stroke) c.drawCircle(Offset(x, y), r, p.line);
}

void _rect(
  Canvas c,
  WbArtPen p,
  double x,
  double y,
  double w,
  double h, {
  Color? fill,
  double a = 0.25,
  double rad = 0,
  bool stroke = true,
}) {
  final r = RRect.fromRectAndRadius(
    Rect.fromLTWH(x, y, w, h),
    Radius.circular(rad),
  );
  if (fill != null) c.drawRRect(r, p.fill(fill, a));
  if (stroke) c.drawRRect(r, p.line);
}

void _poly(
  Canvas c,
  WbArtPen p,
  List<Offset> pts, {
  Color? fill,
  double a = 0.25,
  bool close = true,
  bool stroke = true,
}) {
  final path = WbArtPen.poly(pts, close: close);
  if (fill != null) c.drawPath(path, p.fill(fill, a));
  if (stroke) c.drawPath(path, p.line);
}

void _pline(Canvas c, WbArtPen p, List<Offset> pts) =>
    c.drawPath(WbArtPen.poly(pts, close: false), p.line);

void _rot(Canvas c, double x, double y, double deg, VoidCallback f) {
  c.save();
  c.translate(x, y);
  c.rotate(deg * math.pi / 180);
  f();
  c.restore();
}

/// Zemin / tavan çizgisi (taramalı).
void _ground(
  Canvas c,
  WbArtPen p,
  double x1,
  double x2,
  double y, {
  bool ceil = false,
}) {
  _l(c, p, x1, y, x2, y);
  final d = ceil ? -6.0 : 6.0;
  for (double x = x1 + 6; x <= x2; x += 8) {
    _th(c, p, x, y, x - 6, y + d);
  }
}

/// Dikey duvar (taramalı), [left] true ise tarama sola.
void _wall(
  Canvas c,
  WbArtPen p,
  double x,
  double y1,
  double y2, {
  bool left = true,
}) {
  _l(c, p, x, y1, x, y2);
  final d = left ? -6.0 : 6.0;
  for (double y = y1 + 6; y <= y2; y += 8) {
    _th(c, p, x, y, x + d, y - 6);
  }
}

Path _sinePath(
  double x1,
  double x2,
  double y,
  double amp,
  double lam, [
  double ph = 0,
]) {
  final path = Path();
  bool first = true;
  for (double x = x1; x <= x2; x += 2) {
    final yy = y - amp * math.sin(2 * math.pi * (x - x1) / lam + ph);
    if (first) {
      path.moveTo(x, yy);
      first = false;
    } else {
      path.lineTo(x, yy);
    }
  }
  return path;
}

void _spring(
  Canvas c,
  WbArtPen p,
  double x1,
  double x2,
  double y,
  int coils,
  double amp,
) {
  final path = Path()
    ..moveTo(x1, y)
    ..lineTo(x1 + 8, y);
  final xs = x1 + 8, xe = x2 - 8;
  final n = coils * 2;
  for (int i = 1; i <= n; i++) {
    path.lineTo(xs + (xe - xs) * i / n, y + (i.isOdd ? -amp : amp));
  }
  path.lineTo(xe, y);
  path.lineTo(x2, y);
  c.drawPath(path, p.line);
}

void _flame(Canvas c, WbArtPen p, double x, double yBase, double s) {
  Path f(double k) => Path()
    ..moveTo(x, yBase - s * k)
    ..quadraticBezierTo(x + s * 0.6 * k, yBase - s * 0.25 * k, x, yBase)
    ..quadraticBezierTo(
      x - s * 0.6 * k,
      yBase - s * 0.25 * k,
      x,
      yBase - s * k,
    );
  c.drawPath(f(1), p.fill(_orange, 0.75));
  c.drawPath(f(0.6), p.fill(_yellow, 0.9));
}

void _rotArrow(
  Canvas c,
  WbArtPen p,
  double x,
  double y,
  double r,
  double startDeg,
  double sweepDeg,
  Color col,
) {
  c.drawPath(
    WbArtPen.arc(Offset(x, y), r, startDeg, sweepDeg),
    p.stroke(col, 0.8),
  );
  final e = (startDeg + sweepDeg) * math.pi / 180;
  final pt = Offset(x + r * math.cos(e), y + r * math.sin(e));
  final s = sweepDeg >= 0 ? 1.0 : -1.0;
  final tan = Offset(-math.sin(e) * s, math.cos(e) * s);
  p.arrow(c, pt - tan * 4, pt + tan * 2, c: col, size: 6, line: false);
}

void _axes(
  Canvas c,
  WbArtPen p,
  double ox,
  double oy,
  double w,
  double h,
  String xl,
  String yl,
) {
  _ar(c, p, ox, oy, ox + w, oy);
  _ar(c, p, ox, oy, ox, oy - h);
  _t(c, p, xl, ox + w, oy + 10, size: 9, anchor: 'right');
  _t(c, p, yl, ox + 6, oy - h - 5, size: 9, anchor: 'left');
}

void _beaker(
  Canvas c,
  WbArtPen p,
  double x,
  double y,
  double w,
  double h,
  double level,
  Color col,
) {
  c.drawRect(
    Rect.fromLTWH(x, y + h * (1 - level), w, h * level),
    p.fill(col, 0.3),
  );
  _pline(c, p, [_o(x, y), _o(x, y + h), _o(x + w, y + h), _o(x + w, y)]);
  _l(c, p, x, y + h * (1 - level), x + w, y + h * (1 - level));
}

Offset _bez(Offset a, Offset b, Offset cc, Offset d, double t) {
  final u = 1 - t;
  return a * (u * u * u) +
      b * (3 * u * u * t) +
      cc * (3 * u * t * t) +
      d * (t * t * t);
}

void _bezLine(
  Canvas c,
  WbArtPen p,
  Offset a,
  Offset b,
  Offset cc,
  Offset d, {
  Color? col,
}) {
  final path = Path()
    ..moveTo(a.dx, a.dy)
    ..cubicTo(b.dx, b.dy, cc.dx, cc.dy, d.dx, d.dy);
  c.drawPath(path, col == null ? p.thin(0.8) : p.stroke(col, 0.5));
  final m1 = _bez(a, b, cc, d, 0.47), m2 = _bez(a, b, cc, d, 0.53);
  p.arrow(c, m1, m2 + (m2 - m1) * 0.5, c: col, size: 6, line: false);
}

// ───────────────────────── Basit makineler ─────────────────────────

void _fixedPulley(Canvas c, WbArtPen p) {
  _ground(c, p, 80, 160, 18, ceil: true);
  _l(c, p, 120, 18, 120, 40);
  _circ(c, p, 120, 60, 20, fill: _gray, a: 0.3);
  c.drawCircle(const Offset(120, 60), 3, p.solid);
  _l(c, p, 100, 60, 100, 120);
  _l(c, p, 140, 60, 140, 115);
  _ar(c, p, 140, 115, 140, 152, col: _red);
  _rect(c, p, 82, 120, 36, 30, fill: _orange, a: 0.35);
  _t(c, p, 'G', 100, 135, bold: true);
  _ar(c, p, 100, 150, 100, 174, col: _red);
  _t(c, p, 'F', 154, 140, col: _red, bold: true);
  _t(c, p, 'G', 112, 168, col: _red, bold: true);
  _t(c, p, 'F = G', 190, 60, size: 11, bold: true);
  _t(c, p, 'Yön değiştirir', 190, 78, size: 8);
}

void _movingPulley(Canvas c, WbArtPen p) {
  _ground(c, p, 70, 125, 18, ceil: true);
  _l(c, p, 100, 18, 100, 85);
  _circ(c, p, 130, 85, 30, fill: _gray, a: 0.3);
  c.drawCircle(const Offset(130, 85), 3, p.solid);
  _l(c, p, 160, 85, 160, 45);
  _ar(c, p, 160, 48, 160, 22, col: _red);
  _t(c, p, 'F', 172, 32, col: _red, bold: true);
  _l(c, p, 130, 85, 130, 125);
  _rect(c, p, 112, 125, 36, 30, fill: _orange, a: 0.35);
  _t(c, p, 'G', 130, 140, bold: true);
  _ar(c, p, 130, 155, 130, 176, col: _red);
  _t(c, p, 'F = G/2', 196, 110, size: 11, bold: true);
  _t(c, p, 'Kuvvetten kazanç', 190, 128, size: 8);
}

void _blockTackle(Canvas c, WbArtPen p) {
  _ground(c, p, 70, 130, 18, ceil: true);
  _l(c, p, 100, 18, 100, 31);
  _circ(c, p, 100, 45, 14, fill: _gray, a: 0.3);
  c.drawCircle(const Offset(100, 45), 2.5, p.solid);
  _circ(c, p, 100, 95, 22, fill: _gray, a: 0.3);
  c.drawCircle(const Offset(100, 95), 2.5, p.solid);
  _l(c, p, 122, 18, 122, 95);
  _l(c, p, 78, 95, 86, 45);
  _ar(c, p, 114, 45, 158, 150, col: _red);
  _t(c, p, 'F', 166, 150, col: _red, bold: true);
  _l(c, p, 100, 95, 100, 132);
  _rect(c, p, 84, 132, 32, 26, fill: _orange, a: 0.35);
  _t(c, p, 'G', 100, 145, bold: true);
  _ar(c, p, 100, 158, 100, 177, col: _red);
  _t(c, p, 'F = G/2', 190, 60, size: 11, bold: true);
  _t(c, p, 'Palanga', 190, 78, size: 9);
  _t(c, p, 'Sabit + hareketli', 188, 92, size: 8);
}

void _lever(
  Canvas c,
  WbArtPen p, {
  required double fx,
  required double loadX,
  required double effX,
  required bool effUp,
}) {
  _rect(c, p, 20, 95, 200, 8, fill: _brown, a: 0.35);
  _poly(
    c,
    p,
    [_o(fx, 103), _o(fx - 14, 135), _o(fx + 14, 135)],
    fill: _gray,
    a: 0.35,
  );
  _l(c, p, fx - 28, 135, fx + 28, 135);
  _t(c, p, 'Destek noktası', fx, 148, size: 8);
  _rect(c, p, loadX - 15, 70, 30, 25, fill: _orange, a: 0.35);
  _t(c, p, 'Yük', loadX, 82, size: 8, bold: true);
  _ar(c, p, loadX, 103, loadX, 135, col: _red);
  _t(c, p, 'G', loadX + 10, 125, col: _red, bold: true);
  if (effUp) {
    _ar(c, p, effX, 160, effX, 106, col: _blue);
    _t(c, p, 'F (Kuvvet)', effX, 170, col: _blue, bold: true, size: 8);
  } else {
    _ar(c, p, effX, 42, effX, 93, col: _blue);
    _t(c, p, 'F (Kuvvet)', effX, 32, col: _blue, bold: true, size: 8);
  }
}

void _lever1(Canvas c, WbArtPen p) {
  _lever(c, p, fx: 120, loadX: 45, effX: 200, effUp: false);
  _t(c, p, 'Destek ortada', 120, 14, size: 9);
}

void _lever2(Canvas c, WbArtPen p) {
  _lever(c, p, fx: 30, loadX: 110, effX: 205, effUp: true);
  _t(c, p, 'Yük ortada', 120, 14, size: 9);
}

void _lever3(Canvas c, WbArtPen p) {
  _lever(c, p, fx: 30, loadX: 205, effX: 110, effUp: true);
  _t(c, p, 'Kuvvet ortada', 120, 14, size: 9);
}

void _wheelbarrow(Canvas c, WbArtPen p) {
  _l(c, p, 20, 165, 225, 165);
  _circ(c, p, 150, 142, 22, fill: _gray, a: 0.3);
  c.drawCircle(const Offset(150, 142), 3, p.solid);
  _poly(c, p, [_o(110, 75), _o(130, 48), _o(155, 75)], fill: _orange, a: 0.35);
  _poly(
    c,
    p,
    [_o(80, 75), _o(172, 75), _o(155, 112), _o(95, 112)],
    fill: _brown,
    a: 0.3,
  );
  _l(c, p, 20, 96, 105, 114);
  _l(c, p, 50, 105, 46, 165);
  _l(c, p, 150, 142, 138, 112);
  _ar(c, p, 28, 135, 28, 98, col: _blue);
  _t(c, p, 'F', 40, 125, col: _blue, bold: true);
  _ar(c, p, 125, 100, 125, 150, col: _red);
  _t(c, p, 'G', 136, 150, col: _red, bold: true);
  _t(c, p, 'Destek\nnoktası', 196, 135, size: 8);
  _t(c, p, 'Tekerlek', 150, 176, size: 8);
}

void _incline(Canvas c, WbArtPen p) {
  _poly(c, p, [_o(30, 150), _o(210, 150), _o(210, 60)], fill: _gray, a: 0.2);
  c.drawPath(WbArtPen.arc(const Offset(30, 150), 34, 0, -26.57), p.thin());
  _t(c, p, 'α', 70, 142, size: 10);
  _rot(
    c,
    120,
    105,
    -26.57,
    () => _rect(c, p, -22, -26, 44, 26, fill: _orange, a: 0.35),
  );
  const b = Offset(114.6, 94.3);
  p.arrow(c, b, const Offset(114.6, 140), c: _red);
  p.arrow(c, b, const Offset(96.7, 58.5), c: _green);
  p.arrow(c, b, const Offset(150.4, 76.4), c: _blue);
  p.arrow(c, b, const Offset(83.3, 109.9), c: _orange);
  _t(c, p, 'G', 122, 140, col: _red, bold: true);
  _t(c, p, 'N', 90, 52, col: _green, bold: true);
  _t(c, p, 'F', 158, 72, col: _blue, bold: true);
  _t(c, p, 'fs', 72, 114, col: _orange, bold: true);
}

void _windlass(Canvas c, WbArtPen p) {
  _ground(c, p, 70, 130, 18, ceil: true);
  _l(c, p, 100, 18, 100, 70);
  p.dashedPath(
    c,
    Path()..addOval(Rect.fromCircle(center: const Offset(100, 70), radius: 45)),
  );
  _circ(c, p, 100, 70, 18, fill: _brown, a: 0.35);
  _l(c, p, 100, 70, 145, 70);
  _circ(c, p, 145, 70, 4, fill: _gray, a: 0.6);
  _ar(c, p, 145, 74, 145, 125, col: _blue);
  _t(c, p, 'F', 157, 112, col: _blue, bold: true);
  _t(c, p, 'R', 122, 62, size: 10, bold: true);
  _t(c, p, 'r', 90, 62, size: 10, bold: true);
  _l(c, p, 82, 70, 82, 128);
  _rect(c, p, 66, 128, 32, 26, fill: _orange, a: 0.35);
  _t(c, p, 'G', 82, 141, bold: true);
  _ar(c, p, 82, 154, 82, 175, col: _red);
  _t(c, p, 'F·R = G·r', 190, 20, size: 10, bold: true);
  _t(c, p, 'Çıkrık', 192, 150, size: 9);
}

void _gear(
  Canvas c,
  WbArtPen p,
  double x,
  double y,
  double r,
  int n,
  double rotDeg,
  Color col,
) {
  final path = Path();
  final step = 2 * math.pi / n;
  final rot = rotDeg * math.pi / 180;
  Offset pt(double a, double rr) =>
      Offset(x + rr * math.cos(a), y + rr * math.sin(a));
  for (int i = 0; i < n; i++) {
    final a0 = rot + i * step;
    final pts = [
      pt(a0, r - 4),
      pt(a0 + 0.12 * step, r + 4),
      pt(a0 + 0.42 * step, r + 4),
      pt(a0 + 0.54 * step, r - 4),
    ];
    if (i == 0) {
      path.moveTo(pts[0].dx, pts[0].dy);
    } else {
      path.lineTo(pts[0].dx, pts[0].dy);
    }
    for (int k = 1; k < pts.length; k++) {
      path.lineTo(pts[k].dx, pts[k].dy);
    }
  }
  path.close();
  c.drawPath(path, p.fill(col, 0.3));
  c.drawPath(path, p.line);
  _circ(c, p, x, y, r * 0.25, fill: col, a: 0.4);
  c.drawCircle(Offset(x, y), 2, p.solid);
}

void _gears2(Canvas c, WbArtPen p) {
  _gear(c, p, 80, 95, 40, 12, 0, _blue);
  _gear(c, p, 148, 95, 28, 8, 22.5, _orange);
  _rotArrow(c, p, 80, 95, 20, 200, 250, _blue);
  _rotArrow(c, p, 148, 95, 14, 20, -250, _orange);
  _t(c, p, '12 diş', 80, 40, size: 9, bold: true);
  _t(c, p, '8 diş', 148, 58, size: 9, bold: true);
  _t(c, p, 'Zıt yönde döner', 120, 160, size: 9);
  _t(c, p, 'n₁·z₁ = n₂·z₂', 120, 174, size: 9, bold: true);
}

void _gears3(Canvas c, WbArtPen p) {
  _gear(c, p, 50, 90, 30, 10, 0, _blue);
  _gear(c, p, 110, 90, 30, 10, 18, _green);
  _gear(c, p, 160, 90, 20, 7, 12, _orange);
  _rotArrow(c, p, 50, 90, 14, 200, 250, _blue);
  _rotArrow(c, p, 110, 90, 14, 20, -250, _green);
  _rotArrow(c, p, 160, 90, 9, 200, 250, _orange);
  _t(c, p, 'I', 50, 45, bold: true, size: 9);
  _t(c, p, 'II (ara dişli)', 110, 45, bold: true, size: 9);
  _t(c, p, 'III', 160, 62, bold: true, size: 9);
  _t(c, p, 'I ve III aynı yönde, II zıt yönde döner', 120, 150, size: 8);
}

void _beltPulley(Canvas c, WbArtPen p) {
  const c1 = Offset(65, 90), c2 = Offset(175, 90);
  const r1 = 35.0, r2 = 20.0;
  final th = math.acos((r1 - r2) / 110);
  c.drawCircle(c1, r1 - 3, p.fill(_blue, 0.25));
  c.drawCircle(c2, r2 - 3, p.fill(_orange, 0.3));
  final belt = Path()
    ..moveTo(c1.dx + r1 * math.cos(th), c1.dy - r1 * math.sin(th))
    ..lineTo(c2.dx + r2 * math.cos(th), c2.dy - r2 * math.sin(th))
    ..arcTo(Rect.fromCircle(center: c2, radius: r2), -th, 2 * th, false)
    ..lineTo(c1.dx + r1 * math.cos(th), c1.dy + r1 * math.sin(th))
    ..arcTo(
      Rect.fromCircle(center: c1, radius: r1),
      th,
      2 * math.pi - 2 * th,
      false,
    );
  c.drawPath(belt, p.stroke(p.color, 1.6));
  _circ(c, p, 65, 90, r1 - 3, stroke: true);
  _circ(c, p, 175, 90, r2 - 3, stroke: true);
  c.drawCircle(c1, 3, p.solid);
  c.drawCircle(c2, 3, p.solid);
  _th(c, p, 65, 90, 65 - r1 * 0.7, 90 + r1 * 0.7);
  _th(c, p, 175, 90, 175 + r2 * 0.7, 90 - r2 * 0.7);
  _t(c, p, 'r₁', 45, 112, size: 9, bold: true);
  _t(c, p, 'r₂', 188, 74, size: 9, bold: true);
  _rotArrow(c, p, 65, 90, 14, 200, 250, _blue);
  _rotArrow(c, p, 175, 90, 9, 200, 250, _orange);
  _t(c, p, 'Kasnak-kayış: aynı yönde döner', 120, 148, size: 9);
  _t(c, p, 'ω₁·r₁ = ω₂·r₂', 120, 164, size: 10, bold: true);
}

void _screw(Canvas c, WbArtPen p) {
  _rect(c, p, 90, 20, 60, 14, fill: _gray, a: 0.35, rad: 3);
  _l(c, p, 100, 27, 140, 27);
  final shaft = [
    _o(105, 34),
    _o(135, 34),
    _o(135, 130),
    _o(120, 160),
    _o(105, 130),
  ];
  _poly(c, p, shaft, fill: _gray, a: 0.3);
  for (double y = 42; y < 135; y += 12) {
    _l(c, p, 105, y, 135, y + 7);
  }
  _dar(c, p, 160, 54, 160, 66, col: _red);
  _da(c, p, 135, 54, 165, 54);
  _da(c, p, 135, 66, 165, 66);
  _t(c, p, 'Adım (h)', 170, 60, size: 9, anchor: 'left');
  _t(c, p, 'Vida başı', 80, 27, size: 9, anchor: 'right');
  _t(c, p, 'Diş', 95, 90, size: 9, anchor: 'right');
  _t(c, p, 'Uç', 100, 158, size: 9, anchor: 'right');
}

void _wedge(Canvas c, WbArtPen p) {
  _rect(c, p, 40, 95, 160, 65, fill: _brown, a: 0.25);
  _l(c, p, 120, 112, 120, 150);
  _poly(c, p, [_o(105, 40), _o(135, 40), _o(120, 112)], fill: _gray, a: 0.4);
  _ar(c, p, 120, 8, 120, 38, col: _red);
  _t(c, p, 'F', 132, 18, col: _red, bold: true);
  _ar(c, p, 100, 128, 70, 128, col: _blue);
  _ar(c, p, 140, 128, 170, 128, col: _blue);
  _t(c, p, 'N', 85, 118, col: _blue, bold: true);
  _t(c, p, 'N', 155, 118, col: _blue, bold: true);
  _t(c, p, 'Kama', 175, 50, size: 10, bold: true);
  _t(c, p, 'İnce uç → daha çok kazanç', 120, 174, size: 8);
}

// ───────────────────────── Kuvvet ve hareket ─────────────────────────

void _fbdFlat(Canvas c, WbArtPen p) {
  _ground(c, p, 20, 220, 130);
  _rect(c, p, 90, 80, 60, 50, fill: _orange, a: 0.3);
  _t(c, p, 'm', 120, 105, bold: true);
  _ar(c, p, 120, 80, 120, 28, col: _green);
  _ar(c, p, 120, 130, 120, 175, col: _red);
  _ar(c, p, 150, 105, 205, 105, col: _blue);
  _ar(c, p, 90, 105, 40, 105, col: _orange);
  _t(c, p, 'N', 132, 34, col: _green, bold: true);
  _t(c, p, 'G = mg', 148, 168, col: _red, bold: true, anchor: 'left');
  _t(c, p, 'F', 200, 94, col: _blue, bold: true);
  _t(c, p, 'fs', 45, 94, col: _orange, bold: true);
}

void _fbdIncline(Canvas c, WbArtPen p) {
  _poly(c, p, [_o(25, 160), _o(215, 160), _o(215, 60)], fill: _gray, a: 0.2);
  _rot(
    c,
    115,
    112,
    -27.8,
    () => _rect(c, p, -24, -28, 48, 28, fill: _orange, a: 0.3),
  );
  const b = Offset(108.5, 98);
  final nrm = _o(-0.466, -0.885);
  final slp = _o(0.885, -0.466);
  p.arrow(c, b, b + nrm * 50, c: _green);
  p.arrow(c, b, b + _o(0, 1) * 55, c: _red);
  p.arrow(c, b, b - slp * 25, c: _purple, size: 6);
  p.arrow(c, b, b - nrm * 49, c: _teal, size: 6);
  p.dashed(c, b - slp * 25, b + _o(0, 1) * 55);
  p.dashed(c, b - nrm * 49, b + _o(0, 1) * 55);
  _t(c, p, 'N', 85, 45, col: _green, bold: true);
  _t(c, p, 'G', 118, 156, col: _red, bold: true);
  _t(
    c,
    p,
    'G sinα',
    84,
    132,
    col: _purple,
    size: 8,
    bold: true,
    anchor: 'right',
  );
  _t(c, p, 'G cosα', 140, 150, col: _teal, size: 8, bold: true, anchor: 'left');
  _t(c, p, 'α', 60, 152, size: 10);
  c.drawPath(WbArtPen.arc(const Offset(25, 160), 28, 0, -27.8), p.thin());
}

void _frictionSurface(Canvas c, WbArtPen p) {
  final path = Path()..moveTo(15, 130);
  for (double x = 15; x < 225; x += 6) {
    path.lineTo(x + 3, 125);
    path.lineTo(x + 6, 130);
  }
  c.drawPath(path, p.line);
  _ground(c, p, 15, 225, 130);
  _rect(c, p, 80, 78, 70, 46, fill: _brown, a: 0.3);
  _t(c, p, 'm', 115, 101, bold: true);
  _ar(c, p, 150, 101, 210, 101, col: _blue);
  _ar(c, p, 80, 124, 25, 124, col: _orange);
  _t(c, p, 'F', 205, 90, col: _blue, bold: true);
  _t(c, p, 'fs', 40, 112, col: _orange, bold: true);
  _t(c, p, 'Pürüzlü yüzey', 120, 150, size: 9);
  _t(c, p, 'fs = k·N', 120, 166, size: 10, bold: true);
}

void _vecParallelogram(Canvas c, WbArtPen p) {
  const o = Offset(45, 140);
  const a = Offset(150, 100), b = Offset(110, 40);
  final r = a + b - o;
  _poly(c, p, [o, a, r, b], fill: _lblue, a: 0.15, stroke: false);
  p.dashed(c, a, r);
  p.dashed(c, b, r);
  p.arrow(c, o, a, c: _blue);
  p.arrow(c, o, b, c: _green);
  p.arrow(c, o, r, c: _red);
  _t(c, p, 'F₁', 100, 128, col: _blue, bold: true);
  _t(c, p, 'F₂', 62, 80, col: _green, bold: true);
  _t(c, p, 'R', 130, 68, col: _red, bold: true);
  _t(c, p, 'Paralelkenar yöntemi', 150, 165, size: 9);
}

void _vecTipToTail(Canvas c, WbArtPen p) {
  const o = Offset(35, 140);
  const a = Offset(110, 140), r = Offset(190, 70);
  p.arrow(c, o, a, c: _blue);
  p.arrow(c, a, r, c: _green);
  p.arrow(c, o, r, c: _red);
  _t(c, p, 'F₁', 72, 154, col: _blue, bold: true);
  _t(c, p, 'F₂', 160, 115, col: _green, bold: true);
  _t(c, p, 'R = F₁ + F₂', 88, 90, col: _red, bold: true);
  _t(c, p, 'Uç uca ekleme', 120, 14, size: 9);
}

void _graphXt(Canvas c, WbArtPen p) {
  _axes(c, p, 40, 150, 180, 130, 't', 'x');
  _lc(c, p, _red, 40, 150, 200, 60);
  _lc(c, p, _green, 40, 100, 200, 100);
  c.drawPath(
    Path()
      ..moveTo(40, 150)
      ..quadraticBezierTo(120, 150, 200, 30),
    p.stroke(_blue),
  );
  _t(c, p, 'sabit hız', 204, 62, size: 8, col: _red, anchor: 'left');
  _t(c, p, 'duruyor', 204, 100, size: 8, col: _green, anchor: 'left');
  _t(c, p, 'hızlanan', 204, 30, size: 8, col: _blue, anchor: 'left');
  _t(c, p, 'x–t grafiği', 120, 170, size: 9);
}

void _graphVt(Canvas c, WbArtPen p) {
  _axes(c, p, 40, 150, 180, 130, 't', 'v');
  _poly(
    c,
    p,
    [_o(40, 150), _o(40, 100), _o(120, 100), _o(120, 150)],
    fill: _green,
    a: 0.15,
    stroke: false,
  );
  _lc(c, p, _green, 40, 100, 200, 100);
  _lc(c, p, _red, 40, 150, 200, 40);
  _lc(c, p, _blue, 40, 50, 200, 140);
  _da(c, p, 120, 100, 120, 150);
  _t(c, p, 'Yol = alan', 80, 128, size: 8);
  _t(c, p, 'sabit v', 204, 100, size: 8, col: _green, anchor: 'left');
  _t(c, p, 'a > 0', 204, 40, size: 8, col: _red, anchor: 'left');
  _t(c, p, 'a < 0', 204, 140, size: 8, col: _blue, anchor: 'left');
  _t(c, p, 'v–t grafiği', 120, 170, size: 9);
}

void _graphAt(Canvas c, WbArtPen p) {
  _ar(c, p, 40, 95, 220, 95);
  _ar(c, p, 40, 160, 40, 20);
  _t(c, p, 't', 220, 107, size: 9, anchor: 'right');
  _t(c, p, 'a', 46, 15, size: 9, anchor: 'left');
  _rect(c, p, 40, 55, 100, 40, fill: _red, a: 0.15, stroke: false);
  _lc(c, p, _red, 40, 55, 200, 55);
  _lc(c, p, _blue, 40, 135, 200, 135);
  _da(c, p, 140, 55, 140, 95);
  _t(c, p, 'Δv = alan', 90, 75, size: 8);
  _t(c, p, 'a > 0 (sabit)', 204, 55, size: 8, col: _red, anchor: 'left');
  _t(c, p, 'a < 0 (sabit)', 204, 135, size: 8, col: _blue, anchor: 'left');
  _t(c, p, 'a–t grafiği', 120, 172, size: 9);
}

void _projectile(Canvas c, WbArtPen p) {
  _l(c, p, 15, 150, 225, 150);
  c.drawPath(
    Path()
      ..moveTo(30, 150)
      ..quadraticBezierTo(120, -70, 210, 150),
    p.stroke(_purple),
  );
  p.arrow(c, const Offset(30, 150), const Offset(51, 99), c: _red);
  p.arrow(c, const Offset(30, 150), const Offset(55, 150), c: _blue, size: 5);
  _da(c, p, 51, 150, 51, 99);
  _da(c, p, 120, 40, 120, 150);
  p.arrow(c, const Offset(120, 40), const Offset(155, 40), c: _blue, size: 6);
  c.drawPath(WbArtPen.arc(const Offset(30, 150), 24, 0, -67.7), p.thin());
  _t(c, p, 'v₀', 62, 98, col: _red, bold: true);
  _t(c, p, 'α', 46, 136, size: 9);
  _t(c, p, 'vₓ', 165, 40, col: _blue, size: 9, bold: true);
  _t(c, p, 'H', 128, 95, bold: true, anchor: 'left');
  _t(c, p, 'Tepe noktası', 120, 22, size: 8);
  _dar(c, p, 30, 164, 210, 164);
  _t(c, p, 'R (menzil)', 120, 174, size: 9);
}

void _horizontalThrow(Canvas c, WbArtPen p) {
  _rect(c, p, 10, 50, 50, 110, fill: _gray, a: 0.25);
  _ground(c, p, 60, 232, 160);
  c.drawPath(
    Path()
      ..moveTo(60, 50)
      ..quadraticBezierTo(145, 50, 230, 160),
    p.stroke(_purple),
  );
  for (final t in [0.0, 0.25, 0.5, 0.75]) {
    final x = 60 + 170 * t, y = 50 + 110 * t * t;
    c.drawCircle(Offset(x, y), 5, p.fill(_orange, 0.7));
    if (t > 0) _da(c, p, x, y + 5, x, 160);
  }
  p.arrow(c, const Offset(60, 50), const Offset(105, 50), c: _blue);
  const q = Offset(187.5, 111.9);
  p.arrow(c, q, const Offset(217, 111.9), c: _blue, size: 5);
  p.arrow(c, q, const Offset(187.5, 140), c: _green, size: 5);
  p.arrow(c, q, const Offset(217, 140), c: _red, size: 6);
  _t(c, p, 'v₀', 95, 40, col: _blue, bold: true);
  _t(c, p, 'vₓ', 218, 102, col: _blue, size: 9);
  _t(c, p, 'v_y', 180, 142, col: _green, size: 9);
  _t(c, p, 'v', 224, 142, col: _red, bold: true, size: 9);
  _t(c, p, 'Yatay atış', 140, 15, size: 9);
}

void _freeFall(Canvas c, WbArtPen p) {
  _ground(c, p, 40, 160, 164);
  _l(c, p, 140, 12, 140, 160);
  for (int t = 0; t <= 4; t++) {
    final y = 18 + 9.2 * t * t;
    _l(c, p, 134, y, 146, y);
    _t(c, p, '$t s', 154, y, size: 8, anchor: 'left');
    c.drawCircle(Offset(90, y), 8, p.fill(_orange, t == 0 ? 0.2 : 0.4));
    c.drawCircle(Offset(90, y), 8, p.thin());
  }
  _ar(c, p, 28, 40, 28, 110, col: _red);
  _t(c, p, 'g', 38, 75, col: _red, bold: true);
  _t(c, p, 'h = ½·g·t²', 205, 70, size: 10, bold: true);
  _t(c, p, 'v = g·t', 205, 90, size: 10, bold: true);
}

void _circularMotion(Canvas c, WbArtPen p) {
  _circ(c, p, 120, 90, 60);
  c.drawCircle(const Offset(120, 90), 3, p.solid);
  const b = Offset(171.96, 60);
  _circ(c, p, b.dx, b.dy, 7, fill: _orange, a: 0.6);
  p.dashed(c, const Offset(120, 90), b);
  p.arrow(c, b, const Offset(152, 25.4), c: _blue);
  p.arrow(c, b, const Offset(140, 78), c: _green);
  _t(c, p, 'O', 120, 102, size: 9);
  _t(c, p, 'r', 138, 66, size: 10, bold: true);
  _t(c, p, 'v', 150, 20, col: _blue, bold: true);
  _t(c, p, 'aₘ', 130, 88, col: _green, bold: true, size: 9);
  _t(c, p, 'aₘ = v²/r', 120, 165, size: 10, bold: true);
}

void _pendulum(Canvas c, WbArtPen p) {
  _ground(c, p, 80, 160, 14, ceil: true);
  _da(c, p, 120, 14, 120, 150);
  p.dashedPath(c, WbArtPen.arc(const Offset(120, 14), 110, 30, 120));
  const b = Offset(175, 109);
  _l(c, p, 120, 14, b.dx, b.dy);
  _circ(c, p, b.dx, b.dy, 11, fill: _orange, a: 0.5);
  c.drawPath(WbArtPen.arc(const Offset(120, 14), 40, 60, 30), p.thin());
  _t(c, p, 'θ', 135, 60, size: 10);
  p.arrow(c, b, _o(b.dx, b.dy + 48), c: _red);
  p.arrow(c, b, _o(b.dx - 20, b.dy - 34.6), c: _green, size: 6);
  p.arrow(c, b, _o(b.dx - 22, b.dy + 13), c: _purple, size: 6);
  _t(c, p, 'mg', b.dx + 6, b.dy + 52, col: _red, bold: true, anchor: 'left');
  _t(c, p, 'T', b.dx - 26, b.dy - 40, col: _green, bold: true);
  _t(
    c,
    p,
    'mg sinθ',
    b.dx - 24,
    b.dy + 22,
    col: _purple,
    size: 8,
    anchor: 'right',
  );
}

void _springMass(Canvas c, WbArtPen p) {
  _wall(c, p, 20, 70, 130);
  _ground(c, p, 20, 225, 130);
  _spring(c, p, 20, 110, 110, 7, 9);
  _rect(c, p, 110, 90, 40, 40, fill: _orange, a: 0.35);
  _t(c, p, 'm', 130, 110, bold: true);
  _da(c, p, 130, 45, 130, 140);
  _da(c, p, 90, 140, 90, 150);
  _da(c, p, 170, 140, 170, 150);
  _dar(c, p, 90, 148, 170, 148);
  _t(c, p, '−A', 90, 162, size: 9);
  _t(c, p, '+A', 170, 162, size: 9);
  _t(c, p, 'x = 0', 130, 36, size: 9);
  _ar(c, p, 130, 75, 98, 75, col: _red);
  _t(c, p, 'F = −k·x', 115, 63, col: _red, size: 9, bold: true);
}

void _newtonCradle(Canvas c, WbArtPen p) {
  _l(c, p, 10, 25, 230, 25);
  _l(c, p, 14, 25, 14, 150);
  _l(c, p, 226, 25, 226, 150);
  _l(c, p, 4, 150, 236, 150);
  for (int i = 1; i < 5; i++) {
    final x = 104.0 + i * 24;
    _l(c, p, x - 8, 25, x, 108);
    _l(c, p, x + 8, 25, x, 108);
    _circ(c, p, x, 120, 12, fill: _gray, a: 0.5);
  }
  const b = Offset(49.5, 102.8);
  _l(c, p, 96, 25, b.dx, b.dy);
  _l(c, p, 112, 25, b.dx, b.dy);
  _circ(c, p, b.dx, b.dy, 12, fill: _gray, a: 0.5);
  p.dashedPath(c, WbArtPen.arc(const Offset(104, 25), 95, 90, -55));
  _rotArrow(c, p, 104, 25, 95, 140, -22, _red);
  _ar(c, p, 218, 120, 236, 120, col: _red);
  _t(c, p, 'Newton beşiği', 120, 12, size: 9);
  _t(c, p, 'Momentum ve enerji korunur', 120, 168, size: 8);
}

void _torqueBalance(Canvas c, WbArtPen p) {
  _rect(c, p, 20, 96, 200, 8, fill: _brown, a: 0.35);
  _poly(c, p, [_o(120, 104), _o(105, 135), _o(135, 135)], fill: _gray, a: 0.35);
  _l(c, p, 95, 135, 145, 135);
  _l(c, p, 40, 104, 40, 125);
  _rect(c, p, 25, 125, 30, 26, fill: _blue, a: 0.3);
  _t(c, p, 'm', 40, 138, bold: true);
  _l(c, p, 160, 104, 160, 125);
  _rect(c, p, 140, 125, 40, 30, fill: _red, a: 0.3);
  _t(c, p, '2m', 160, 140, bold: true);
  _dar(c, p, 40, 78, 120, 78);
  _dar(c, p, 120, 78, 160, 78);
  _da(c, p, 40, 78, 40, 96);
  _da(c, p, 160, 78, 160, 96);
  _t(c, p, 'd₁', 80, 68, size: 10, bold: true);
  _t(c, p, 'd₂', 140, 68, size: 10, bold: true);
  _t(c, p, 'm₁·d₁ = m₂·d₂', 120, 28, size: 10, bold: true);
  _t(c, p, 'Tork dengesi (τ₁ = τ₂)', 120, 168, size: 9);
}

void _gravity(Canvas c, WbArtPen p) {
  _circ(c, p, 65, 90, 40, fill: _blue, a: 0.3);
  _poly(
    c,
    p,
    [_o(50, 70), _o(62, 62), _o(72, 74), _o(60, 86), _o(48, 82)],
    fill: _green,
    a: 0.5,
    stroke: false,
  );
  _circ(c, p, 190, 90, 14, fill: _gray, a: 0.5);
  _t(c, p, 'M', 65, 108, bold: true, size: 9);
  _t(c, p, 'm', 190, 90, bold: true, size: 9);
  _ar(c, p, 108, 90, 142, 90, col: _red);
  _ar(c, p, 174, 90, 146, 90, col: _red);
  _t(c, p, 'F', 125, 80, col: _red, bold: true);
  _t(c, p, 'F', 160, 80, col: _red, bold: true);
  _da(c, p, 65, 90, 65, 138);
  _da(c, p, 190, 104, 190, 138);
  _dar(c, p, 65, 134, 190, 134);
  _t(c, p, 'r', 128, 124, size: 10, bold: true);
  _t(c, p, 'F = G·M·m / r²', 120, 160, size: 11, bold: true);
}

// ───────────────────────── Basınç ve akışkanlar ─────────────────────────

void _uTube(
  Canvas c,
  WbArtPen p,
  double ox,
  double top,
  double lvlL,
  double lvlR,
  Color col, {
  double? gapA,
  double? gapB,
}) {
  final iL = ox + 20, iR = ox + 50, oR = ox + 70;
  const bot = 150.0, ib = 130.0;
  c.drawPath(
    WbArtPen.poly([
      _o(ox, lvlL),
      _o(ox, bot),
      _o(oR, bot),
      _o(oR, lvlR),
      _o(iR + 0, lvlR),
      _o(iR, ib),
      _o(iL, ib),
      _o(iL, lvlL),
    ]),
    p.fill(col, 0.3),
  );
  if (gapA != null && gapB != null) {
    _l(c, p, ox, top, ox, gapA);
    _l(c, p, ox, gapB, ox, bot);
  } else {
    _l(c, p, ox, top, ox, bot);
  }
  _pline(c, p, [_o(oR, top), _o(oR, bot), _o(ox, bot)]);
  _pline(c, p, [_o(iL, top), _o(iL, ib), _o(iR, ib), _o(iR, top)]);
}

void _perforatedCan(Canvas c, WbArtPen p) {
  _ground(c, p, 20, 235, 160);
  c.drawRect(const Rect.fromLTWH(41, 30, 89, 130), p.fill(_blue, 0.25));
  _pline(c, p, [_o(40, 20), _o(40, 160), _o(130, 160), _o(130, 20)]);
  for (final y in [50.0, 85.0, 120.0]) {
    final s = 1.5 * math.sqrt((y - 30) * (160 - y));
    final path = Path()..moveTo(130, y);
    for (double t = 0.05; t <= 1.001; t += 0.05) {
      path.lineTo(130 + s * t, y + (160 - y) * t * t);
    }
    c.drawPath(path, p.stroke(_blue, 1));
    c.drawCircle(Offset(130, y), 2.5, p.solid);
  }
  _t(c, p, 'Derinlik arttıkça\nbasınç artar', 185, 35, size: 8);
}

void _communicating(Canvas c, WbArtPen p) {
  c.drawRect(const Rect.fromLTWH(30, 60, 25, 85), p.fill(_blue, 0.3));
  c.drawRect(const Rect.fromLTWH(90, 60, 60, 85), p.fill(_blue, 0.3));
  c.drawRect(const Rect.fromLTWH(185, 60, 25, 85), p.fill(_blue, 0.3));
  c.drawRect(const Rect.fromLTWH(30, 120, 180, 25), p.fill(_blue, 0.3));
  _pline(c, p, [_o(30, 20), _o(30, 145), _o(210, 145), _o(210, 20)]);
  _pline(c, p, [_o(55, 20), _o(55, 120), _o(90, 120), _o(90, 20)]);
  _pline(c, p, [_o(150, 20), _o(150, 120), _o(185, 120), _o(185, 20)]);
  _p2(c, p);
  p.dashed(
    c,
    const Offset(20, 60),
    const Offset(220, 60),
    paint: p.stroke(_red, 0.5),
  );
  _t(c, p, 'Aynı seviye', 120, 48, size: 9, col: _red, bold: true);
  _t(c, p, 'Birleşik kaplar: sıvı aynı yüksekliğe ulaşır', 120, 165, size: 8);
}

void _p2(Canvas c, WbArtPen p) {
  _t(c, p, 'P₀', 42, 12, size: 8);
  _t(c, p, 'P₀', 120, 12, size: 8);
  _t(c, p, 'P₀', 197, 12, size: 8);
}

void _hydraulicPress(Canvas c, WbArtPen p) {
  c.drawRect(const Rect.fromLTWH(30, 90, 30, 50), p.fill(_blue, 0.3));
  c.drawRect(const Rect.fromLTWH(120, 70, 90, 70), p.fill(_blue, 0.3));
  c.drawRect(const Rect.fromLTWH(60, 115, 60, 25), p.fill(_blue, 0.3));
  _pline(c, p, [_o(30, 50), _o(30, 140), _o(210, 140), _o(210, 50)]);
  _pline(c, p, [_o(60, 50), _o(60, 115), _o(120, 115), _o(120, 50)]);
  _rect(c, p, 31, 76, 28, 14, fill: _gray, a: 0.5);
  _l(c, p, 45, 76, 45, 34);
  _ar(c, p, 45, 12, 45, 34, col: _red);
  _t(c, p, 'F₁', 58, 18, col: _red, bold: true);
  _t(c, p, 'A₁', 45, 108, size: 9, bold: true);
  _rect(c, p, 121, 56, 88, 14, fill: _gray, a: 0.5);
  _rect(c, p, 150, 28, 30, 28, fill: _orange, a: 0.35);
  _t(c, p, 'Yük', 165, 42, size: 8);
  _ar(c, p, 195, 8, 195, 54, col: _red);
  _t(c, p, 'F₂', 208, 22, col: _red, bold: true);
  _t(c, p, 'A₂', 165, 108, size: 9, bold: true);
  _t(c, p, 'F₁/A₁ = F₂/A₂  (Pascal)', 120, 160, size: 9, bold: true);
}

void _archimedes(Canvas c, WbArtPen p) {
  _rect(c, p, 110, 6, 20, 50, fill: _gray, a: 0.3, rad: 3);
  for (double y = 14; y < 52; y += 6) {
    _th(c, p, 110, y, 116, y);
  }
  _l(c, p, 120, 56, 120, 120);
  c.drawRect(const Rect.fromLTWH(70, 112, 100, 56), p.fill(_blue, 0.28));
  _pline(c, p, [_o(70, 90), _o(70, 168), _o(170, 168), _o(170, 90)]);
  _l(c, p, 70, 112, 170, 112);
  _rect(c, p, 100, 120, 40, 34, fill: _orange, a: 0.45);
  _ar(c, p, 108, 120, 108, 90, col: _blue);
  _ar(c, p, 132, 154, 132, 166, col: _red, size: 5);
  _ar(c, p, 150, 128, 150, 158, col: _red);
  _t(c, p, 'Fk', 100, 100, col: _blue, bold: true, size: 9, anchor: 'right');
  _t(c, p, 'G', 158, 150, col: _red, bold: true, anchor: 'left');
  _t(c, p, 'Dinamometre', 140, 22, size: 8, anchor: 'left');
  _t(c, p, 'Fk = ρ·g·V\n(batan hacim)', 176, 135, size: 8, anchor: 'left');
  _t(c, p, 'Su', 150, 105, size: 8);
}

void _floatSink(Canvas c, WbArtPen p) {
  c.drawRect(const Rect.fromLTWH(20, 70, 200, 95), p.fill(_blue, 0.25));
  _pline(c, p, [_o(20, 35), _o(20, 165), _o(220, 165), _o(220, 35)]);
  _l(c, p, 20, 70, 220, 70);
  _rect(c, p, 35, 52, 36, 36, fill: _orange, a: 0.45);
  _rect(c, p, 102, 100, 36, 36, fill: _green, a: 0.45);
  _rect(c, p, 170, 129, 36, 36, fill: _brown, a: 0.45);
  _t(c, p, 'Yüzer', 53, 24, size: 9, bold: true);
  _t(c, p, 'Askıda', 120, 24, size: 9, bold: true);
  _t(c, p, 'Batar', 188, 24, size: 9, bold: true);
  _t(c, p, 'G = Fk', 53, 174, size: 8);
  _t(c, p, 'G = Fk', 120, 174, size: 8);
  _t(c, p, 'G > Fk', 188, 174, size: 8);
  _ar(c, p, 53, 100, 53, 118, col: _red, size: 5);
  _ar(c, p, 120, 136, 120, 154, col: _red, size: 5);
}

void _torricelli(Canvas c, WbArtPen p) {
  c.drawRect(const Rect.fromLTWH(55, 148, 140, 17), p.fill(_gray, 0.45));
  _pline(c, p, [_o(50, 140), _o(60, 165), _o(190, 165), _o(200, 140)]);
  c.drawRect(const Rect.fromLTWH(110, 70, 20, 85), p.fill(_gray, 0.55));
  _pline(c, p, [_o(110, 155), _o(110, 25), _o(130, 25), _o(130, 155)]);
  _t(c, p, 'Boşluk', 120, 48, size: 8);
  _dar(c, p, 152, 70, 152, 148);
  _da(c, p, 130, 70, 156, 70);
  _da(c, p, 130, 148, 156, 148);
  _t(c, p, 'h = 76 cm Hg', 158, 109, size: 9, bold: true, anchor: 'left');
  _ar(c, p, 78, 105, 78, 145, col: _red);
  _ar(c, p, 172, 105, 172, 145, col: _red);
  _t(c, p, 'P₀', 78, 95, col: _red, bold: true);
  _t(c, p, 'P₀', 172, 95, col: _red, bold: true);
  _t(c, p, 'Cıva', 90, 158, size: 8);
}

void _manometer(Canvas c, WbArtPen p) {
  _circ(c, p, 50, 69, 28, fill: _yellow, a: 0.25);
  _t(c, p, 'Gaz', 50, 69, size: 9, bold: true);
  _l(c, p, 76, 60, 110, 60);
  _l(c, p, 76, 78, 110, 78);
  _uTube(c, p, 110, 40, 100, 60, _blue, gapA: 60, gapB: 78);
  _l(c, p, 110, 40, 130, 40);
  _da(c, p, 130, 100, 198, 100);
  _da(c, p, 180, 60, 198, 60);
  _dar(c, p, 194, 60, 194, 100);
  _t(c, p, 'h', 200, 80, size: 10, bold: true, anchor: 'left');
  _ar(c, p, 170, 14, 170, 36, col: _red);
  _t(c, p, 'P₀', 182, 18, col: _red, bold: true, size: 9, anchor: 'left');
  _t(c, p, 'P_gaz = P₀ + ρ·g·h', 120, 168, size: 10, bold: true);
}

void _uTubeOil(Canvas c, WbArtPen p) {
  _uTube(c, p, 85, 30, 100, 68, _blue);
  c.drawRect(const Rect.fromLTWH(85, 60, 20, 40), p.fill(_orange, 0.5));
  _da(c, p, 85, 100, 155, 100);
  _dar(c, p, 72, 60, 72, 100);
  _dar(c, p, 168, 68, 168, 100);
  _t(c, p, 'h₁', 62, 80, size: 9, bold: true);
  _t(c, p, 'h₂', 174, 84, size: 9, bold: true, anchor: 'left');
  _t(c, p, 'Yağ', 95, 20, size: 9, col: _orange, bold: true);
  _t(c, p, 'Su', 145, 20, size: 9, col: _blue, bold: true);
  _t(c, p, 'U borusu: ρ₁·h₁ = ρ₂·h₂', 120, 168, size: 9, bold: true);
}

void _atmExperiment(Canvas c, WbArtPen p) {
  _rect(c, p, 90, 20, 60, 100, fill: _blue, a: 0.3);
  _l(c, p, 80, 120, 160, 120);
  for (final x in [80.0, 100.0, 120.0, 140.0, 160.0]) {
    _ar(
      c,
      p,
      x == 80 ? 85 : (x == 160 ? 155 : x),
      160,
      x == 80 ? 85 : (x == 160 ? 155 : x),
      126,
      col: _red,
      size: 6,
    );
  }
  _t(c, p, 'P₀ (atmosfer basıncı)', 120, 172, size: 8, col: _red, bold: true);
  _t(c, p, 'Su dolu bardak', 100, 70, size: 8);
  _t(c, p, 'Kart', 170, 120, size: 8, anchor: 'left');
  _t(c, p, 'Su dökülmez!', 120, 8, size: 9, bold: true);
}

// ───────────────────────── Isı ─────────────────────────

void _thermometer(Canvas c, WbArtPen p) {
  _rect(c, p, 112, 20, 16, 112, rad: 8, fill: _gray, a: 0.12);
  _circ(c, p, 120, 148, 17, fill: _red, a: 0.6);
  c.drawRect(const Rect.fromLTWH(117, 60, 6, 90), p.fill(_red, 0.8));
  for (int i = 0; i <= 5; i++) {
    final y = 130.0 - i * 20;
    _l(c, p, 128, y, 136, y);
    _t(c, p, '${i * 20}', 140, y, size: 8, anchor: 'left');
  }
  for (int i = 0; i <= 10; i++) {
    final y = 130.0 - i * 10;
    _th(c, p, 112, y, 107, y);
  }
  _t(c, p, '°C', 120, 8, size: 9, bold: true);
  _t(c, p, 'Sıvı sütunu', 100, 70, size: 8, anchor: 'right');
  _t(c, p, 'Hazne', 94, 150, size: 8, anchor: 'right');
}

void _phaseChange(Canvas c, WbArtPen p) {
  _axes(c, p, 40, 150, 185, 135, 'Isı (Q)', 'Sıcaklık');
  _lc(c, p, _blue, 40, 135, 70, 105);
  _lc(c, p, _green, 70, 105, 105, 105);
  _lc(c, p, _orange, 105, 105, 140, 60);
  _lc(c, p, _teal, 140, 60, 185, 60);
  _lc(c, p, _red, 185, 60, 220, 28);
  _da(c, p, 40, 105, 70, 105);
  _da(c, p, 40, 60, 140, 60);
  _t(c, p, 'Te', 36, 105, size: 8, anchor: 'right');
  _t(c, p, 'Tk', 36, 60, size: 8, anchor: 'right');
  _t(c, p, 'Katı', 48, 100, size: 8, col: _blue, bold: true, anchor: 'left');
  _t(c, p, 'Erime', 88, 118, size: 8, col: _green, bold: true);
  _t(c, p, 'Sıvı', 132, 98, size: 8, col: _orange, bold: true);
  _t(c, p, 'Kaynama', 162, 73, size: 8, col: _teal, bold: true);
  _t(c, p, 'Gaz', 208, 50, size: 8, col: _red, bold: true);
}

void _thermalEquilibrium(Canvas c, WbArtPen p) {
  _beaker(c, p, 10, 70, 50, 70, 0.8, _red);
  _beaker(c, p, 80, 70, 50, 70, 0.8, _blue);
  _beaker(c, p, 180, 70, 50, 70, 0.8, _purple);
  _ar(c, p, 62, 105, 78, 105, col: _red, size: 5);
  _ar(c, p, 138, 105, 172, 105, size: 8);
  _t(c, p, 'Q', 70, 95, size: 8, col: _red, bold: true);
  _t(c, p, 'Sıcak', 35, 58, size: 9, bold: true);
  _t(c, p, 'Soğuk', 105, 58, size: 9, bold: true);
  _t(c, p, 'Karışım', 205, 58, size: 9, bold: true);
  _t(c, p, 'T₁ = 80°C', 35, 154, size: 8);
  _t(c, p, 'T₂ = 20°C', 105, 154, size: 8);
  _t(c, p, 'T = 50°C', 205, 154, size: 8);
  _t(c, p, 'Isıl denge', 120, 20, size: 10, bold: true);
}

void _expansion(Canvas c, WbArtPen p) {
  Path ring(double x) => Path()
    ..addOval(Rect.fromCircle(center: Offset(x, 115), radius: 24))
    ..addOval(Rect.fromCircle(center: Offset(x, 115), radius: 15))
    ..fillType = PathFillType.evenOdd;
  for (final x in [60.0, 180.0]) {
    c.drawPath(ring(x), p.fill(_gray, 0.4));
    c.drawCircle(Offset(x, 115), 24, p.line);
    c.drawCircle(Offset(x, 115), 15, p.line);
  }
  _circ(c, p, 60, 50, 12, fill: _blue, a: 0.4);
  _ar(c, p, 60, 66, 60, 100, col: _green, size: 6);
  _circ(c, p, 180, 66, 19, fill: _red, a: 0.4);
  p.dashedPath(
    c,
    Path()..addOval(Rect.fromCircle(center: const Offset(180, 66), radius: 12)),
  );
  _flame(c, p, 150, 100, 18);
  _t(c, p, 'Soğuk küre', 60, 22, size: 9, bold: true);
  _t(c, p, 'Geçer', 60, 155, size: 9, col: _green, bold: true);
  _t(c, p, 'Isıtılmış küre', 180, 22, size: 9, bold: true);
  _t(c, p, 'Geçmez', 180, 155, size: 9, col: _red, bold: true);
  _t(c, p, 'Genleşme', 120, 175, size: 8);
}

void _conduction(Canvas c, WbArtPen p) {
  final rod = const Rect.fromLTWH(50, 80, 150, 24);
  c.drawRect(
    rod,
    Paint()
      ..shader = LinearGradient(
        colors: [
          _red.withValues(alpha: 0.6),
          _orange.withValues(alpha: 0.45),
          _lblue.withValues(alpha: 0.4),
        ],
      ).createShader(rod),
  );
  c.drawRect(rod, p.line);
  for (int i = 0; i < 7; i++) {
    for (int j = 0; j < 2; j++) {
      c.drawCircle(Offset(62 + i * 21.0, 90 + j * 12), 2.5, p.solid);
    }
  }
  _flame(c, p, 68, 128, 26);
  _ar(c, p, 60, 62, 190, 62, col: _red);
  _t(c, p, 'Isı akışı', 125, 50, size: 9, col: _red, bold: true);
  _t(c, p, 'Metal çubuk', 135, 120, size: 9);
  _t(c, p, 'Isı kaynağı', 68, 150, size: 8);
  _t(c, p, 'İletim: madde hareket etmez', 125, 170, size: 8);
}

void _convection(Canvas c, WbArtPen p) {
  _beaker(c, p, 70, 30, 100, 120, 0.85, _blue);
  _flame(c, p, 120, 176, 26);
  _ar(c, p, 120, 138, 120, 66, col: _red);
  _ar(c, p, 115, 56, 86, 56, col: _blue);
  _ar(c, p, 125, 56, 154, 56, col: _blue);
  _ar(c, p, 86, 66, 86, 128, col: _blue);
  _ar(c, p, 154, 66, 154, 128, col: _blue);
  _ar(c, p, 86, 140, 112, 140, col: _red);
  _ar(c, p, 154, 140, 128, 140, col: _red);
  _t(c, p, 'Sıcak su\nyükselir', 232, 70, size: 8, anchor: 'right');
  _t(c, p, 'Soğuk su\ninir', 62, 100, size: 8, anchor: 'right');
}

void _radiation(Canvas c, WbArtPen p) {
  _circ(c, p, 45, 70, 26, fill: _yellow, a: 0.6);
  for (int i = 0; i < 12; i++) {
    final a = i * math.pi / 6;
    _lc(
      c,
      p,
      _orange,
      45 + 31 * math.cos(a),
      70 + 31 * math.sin(a),
      45 + 42 * math.cos(a),
      70 + 42 * math.sin(a),
      0.7,
    );
  }
  for (final y in [45.0, 70.0, 95.0]) {
    c.drawPath(_sinePath(95, 180, y, 5, 17), p.stroke(_orange, 0.6));
    p.arrow(c, _o(176, y), _o(190, y), c: _orange, size: 6, line: false);
  }
  _circ(c, p, 214, 70, 18, fill: _blue, a: 0.35);
  _t(c, p, 'Güneş', 45, 118, size: 9, bold: true);
  _t(c, p, 'Dünya', 214, 100, size: 9, bold: true);
  _t(c, p, 'Işıma: boşlukta da yayılır', 120, 140, size: 9);
  _t(c, p, 'Madde gerekmez', 120, 156, size: 8);
}

// ───────────────────────── Elektrik ─────────────────────────

void _cellPl(Canvas c, WbArtPen p, double x, double y) {
  _l(c, p, x - 3, y - 10, x - 3, y + 10);
  c.drawLine(
    Offset(x + 3, y - 5),
    Offset(x + 3, y + 5),
    p.stroke(p.color, 2.4),
  );
}

void _lamp(Canvas c, WbArtPen p, double x, double y, [double r = 11]) {
  _circ(c, p, x, y, r, fill: _yellow, a: 0.4);
  final d = r * 0.7;
  _th(c, p, x - d, y - d, x + d, y + d);
  _th(c, p, x - d, y + d, x + d, y - d);
}

void _zig(Canvas c, WbArtPen p, double x, double y, [double half = 18]) {
  final pts = <Offset>[_o(x - half, y)];
  const n = 6;
  for (int i = 0; i < n; i++) {
    pts.add(_o(x - half + (i + 0.5) * 2 * half / n, y + (i.isEven ? -6 : 6)));
  }
  pts.add(_o(x + half, y));
  _pline(c, p, pts);
}

void _swt(Canvas c, WbArtPen p, double x, double y, bool open) {
  c.drawCircle(Offset(x - 14, y), 2.5, p.solid);
  c.drawCircle(Offset(x + 14, y), 2.5, p.solid);
  _l(c, p, x - 14, y, open ? x + 9 : x + 14, open ? y - 14 : y);
}

void _meter(Canvas c, WbArtPen p, double x, double y, String s) {
  _circ(c, p, x, y, 11, fill: _lblue, a: 0.25);
  _t(c, p, s, x, y, size: 10, bold: true);
}

void _simpleCircuit(Canvas c, WbArtPen p) {
  _pline(c, p, [_o(112, 40), _o(30, 40), _o(30, 140), _o(108, 140)]);
  _pline(c, p, [_o(128, 40), _o(210, 40), _o(210, 79)]);
  _pline(c, p, [_o(210, 101), _o(210, 140), _o(132, 140)]);
  _cellPl(c, p, 120, 40);
  _lamp(c, p, 210, 90);
  _swt(c, p, 120, 140, true);
  _ar(c, p, 30, 72, 30, 108, col: _red);
  _t(c, p, 'I', 42, 90, col: _red, bold: true);
  _t(c, p, '+', 109, 26, size: 10, bold: true);
  _t(c, p, '−', 132, 26, size: 10, bold: true);
  _t(c, p, 'Pil', 120, 14, size: 9);
  _t(c, p, 'Ampul', 210, 120, size: 8, anchor: 'center');
  _t(c, p, 'Anahtar', 120, 162, size: 8);
}

void _seriesLamps(Canvas c, WbArtPen p) {
  _pline(c, p, [_o(30, 82), _o(30, 40), _o(79, 40)]);
  _pline(c, p, [_o(101, 40), _o(139, 40)]);
  _pline(c, p, [
    _o(161, 40),
    _o(210, 40),
    _o(210, 140),
    _o(30, 140),
    _o(30, 98),
  ]);
  _rot(c, 30, 90, 90, () => _cellPl(c, p, 0, 0));
  _lamp(c, p, 90, 40);
  _lamp(c, p, 150, 40);
  _ar(c, p, 118, 40, 128, 40, col: _red, size: 6);
  _t(c, p, 'L₁', 90, 20, bold: true);
  _t(c, p, 'L₂', 150, 20, bold: true);
  _t(c, p, 'I', 124, 26, col: _red, bold: true, size: 9);
  _t(c, p, 'Akım her yerde aynı', 120, 165, size: 9);
  _t(c, p, 'Pil', 14, 90, size: 8);
}

void _parallelLamps(Canvas c, WbArtPen p) {
  _pline(c, p, [_o(30, 82), _o(30, 40), _o(170, 40), _o(170, 79)]);
  _pline(c, p, [_o(110, 40), _o(110, 79)]);
  _pline(c, p, [_o(30, 98), _o(30, 140), _o(170, 140), _o(170, 101)]);
  _pline(c, p, [_o(110, 140), _o(110, 101)]);
  _rot(c, 30, 90, 90, () => _cellPl(c, p, 0, 0));
  _lamp(c, p, 110, 90);
  _lamp(c, p, 170, 90);
  c.drawCircle(const Offset(110, 40), 3, p.solid);
  c.drawCircle(const Offset(110, 140), 3, p.solid);
  _t(c, p, 'L₁', 130, 90, bold: true, size: 9);
  _t(c, p, 'L₂', 190, 90, bold: true, size: 9);
  _ar(c, p, 50, 40, 70, 40, col: _red, size: 6);
  _t(c, p, 'I', 60, 28, col: _red, bold: true, size: 9);
  _t(c, p, 'I₁', 98, 62, size: 8, col: _red, anchor: 'right');
  _t(c, p, 'I₂', 158, 62, size: 8, col: _red, anchor: 'right');
  _t(c, p, 'I = I₁ + I₂', 120, 165, size: 9, bold: true);
}

void _circuitSymbols(Canvas c, WbArtPen p) {
  final names = [
    'Pil',
    'Ampul',
    'Direnç',
    'Reosta',
    'Anahtar',
    'Ampermetre',
    'Voltmetre',
    'Topraklama',
    'Kondansatör',
    'Diyot',
  ];
  for (int i = 0; i < 10; i++) {
    final col = i ~/ 5;
    final row = i % 5;
    final x = 44.0 + col * 155;
    final y = 26.0 + row * 38;
    _t(c, p, names[i], x + 32, y, size: 9, anchor: 'left');
    switch (i) {
      case 0:
        _l(c, p, x - 24, y, x - 3, y);
        _l(c, p, x + 3, y, x + 24, y);
        _cellPl(c, p, x, y);
        break;
      case 1:
        _l(c, p, x - 24, y, x - 11, y);
        _l(c, p, x + 11, y, x + 24, y);
        _lamp(c, p, x, y);
        break;
      case 2:
        _l(c, p, x - 24, y, x - 16, y);
        _l(c, p, x + 16, y, x + 24, y);
        _zig(c, p, x, y, 16);
        break;
      case 3:
        _l(c, p, x - 24, y, x - 16, y);
        _l(c, p, x + 16, y, x + 24, y);
        _zig(c, p, x, y, 16);
        _ar(c, p, x - 10, y + 12, x + 12, y - 12, col: _red, size: 5);
        break;
      case 4:
        _l(c, p, x - 24, y, x - 14, y);
        _l(c, p, x + 14, y, x + 24, y);
        _swt(c, p, x, y, true);
        break;
      case 5:
        _l(c, p, x - 24, y, x - 11, y);
        _l(c, p, x + 11, y, x + 24, y);
        _meter(c, p, x, y, 'A');
        break;
      case 6:
        _l(c, p, x - 24, y, x - 11, y);
        _l(c, p, x + 11, y, x + 24, y);
        _meter(c, p, x, y, 'V');
        break;
      case 7:
        _l(c, p, x - 24, y, x, y);
        _l(c, p, x, y - 12, x, y + 12);
        _l(c, p, x + 5, y - 8, x + 5, y + 8);
        _l(c, p, x + 10, y - 4, x + 10, y + 4);
        break;
      case 8:
        _l(c, p, x - 24, y, x - 4, y);
        _l(c, p, x + 4, y, x + 24, y);
        _l(c, p, x - 4, y - 11, x - 4, y + 11);
        _l(c, p, x + 4, y - 11, x + 4, y + 11);
        break;
      default:
        _l(c, p, x - 24, y, x - 8, y);
        _l(c, p, x + 8, y, x + 24, y);
        _poly(
          c,
          p,
          [_o(x - 8, y - 9), _o(x - 8, y + 9), _o(x + 8, y)],
          fill: _gray,
          a: 0.4,
        );
        _l(c, p, x + 8, y - 9, x + 8, y + 9);
    }
  }
}

void _ohmTriangle(Canvas c, WbArtPen p) {
  _poly(c, p, [_o(90, 14), _o(20, 140), _o(160, 140)], fill: _blue, a: 0.12);
  _l(c, p, 55, 77, 125, 77);
  _l(c, p, 90, 77, 90, 140);
  _t(c, p, 'V', 90, 52, size: 20, bold: true);
  _t(c, p, 'I', 62, 110, size: 20, bold: true);
  _t(c, p, 'R', 120, 110, size: 20, bold: true);
  _t(c, p, 'V = I·R', 200, 50, size: 10, bold: true);
  _t(c, p, 'I = V/R', 200, 80, size: 10, bold: true);
  _t(c, p, 'R = V/I', 200, 110, size: 10, bold: true);
  _t(c, p, 'Ohm kanunu', 90, 160, size: 10);
}

void _resSeg(Canvas c, WbArtPen p, Offset a, Offset b, String label) {
  final d = b - a;
  final len = d.distance;
  final ang = math.atan2(d.dy, d.dx);
  c.save();
  c.translate(a.dx, a.dy);
  c.rotate(ang);
  _l(c, p, 0, 0, len / 2 - 16, 0);
  _l(c, p, len / 2 + 16, 0, len, 0);
  _zig(c, p, len / 2, 0, 16);
  c.restore();
  final m = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  final n = Offset(-d.dy, d.dx) / len;
  _t(c, p, label, m.dx + n.dx * 16, m.dy + n.dy * 16, size: 9, bold: true);
}

void _wheatstone(Canvas c, WbArtPen p) {
  const a = Offset(120, 28),
      b = Offset(190, 90),
      cc = Offset(120, 152),
      d = Offset(50, 90);
  _resSeg(c, p, d, a, 'R₁');
  _resSeg(c, p, a, b, 'R₂');
  _resSeg(c, p, cc, d, 'R₃');
  _resSeg(c, p, b, cc, 'R₄');
  _l(c, p, 50, 90, 108, 90);
  _l(c, p, 132, 90, 190, 90);
  _meter(c, p, 120, 90, 'G');
  _pline(c, p, [a, _o(228, 28), _o(228, 78)]);
  _pline(c, p, [cc, _o(228, 152), _o(228, 102)]);
  _rot(c, 228, 90, 90, () => _cellPl(c, p, 0, 0));
  for (final q in [a, b, cc, d]) {
    c.drawCircle(q, 3, p.solid);
  }
  _t(c, p, 'A', 120, 16, size: 9, bold: true);
  _t(c, p, 'B', 200, 90, size: 9, bold: true);
  _t(c, p, 'C', 120, 164, size: 9, bold: true);
  _t(c, p, 'D', 40, 90, size: 9, bold: true);
  _t(c, p, 'R₁/R₃ = R₂/R₄ → IG = 0', 120, 176, size: 8);
}

void _chargeSign(
  Canvas c,
  WbArtPen p,
  double x,
  double y,
  bool plus, [
  double r = 14,
]) {
  _circ(c, p, x, y, r, fill: plus ? _red : _blue, a: 0.35);
  _l(c, p, x - r * 0.5, y, x + r * 0.5, y);
  if (plus) _l(c, p, x, y - r * 0.5, x, y + r * 0.5);
}

void _fieldPlus(Canvas c, WbArtPen p) {
  for (int i = 0; i < 8; i++) {
    final a = i * math.pi / 4;
    _ar(
      c,
      p,
      120 + 22 * math.cos(a),
      90 + 22 * math.sin(a),
      120 + 78 * math.cos(a),
      90 + 78 * math.sin(a),
      col: _red,
      size: 7,
    );
  }
  _chargeSign(c, p, 120, 90, true);
  _t(c, p, 'Pozitif yük: alan çizgileri dışa', 120, 175, size: 9);
}

void _fieldMinus(Canvas c, WbArtPen p) {
  for (int i = 0; i < 8; i++) {
    final a = i * math.pi / 4;
    _ar(
      c,
      p,
      120 + 78 * math.cos(a),
      90 + 78 * math.sin(a),
      120 + 22 * math.cos(a),
      90 + 22 * math.sin(a),
      col: _blue,
      size: 7,
    );
  }
  _chargeSign(c, p, 120, 90, false);
  _t(c, p, 'Negatif yük: alan çizgileri içe', 120, 175, size: 9);
}

void _fieldDipole(Canvas c, WbArtPen p) {
  const l = Offset(65, 90), r = Offset(175, 90);
  for (final deg in [-80.0, -55.0, -30.0, 0.0, 30.0, 55.0, 80.0]) {
    final th = deg * math.pi / 180;
    final dir = _o(math.cos(th), math.sin(th));
    final p0 = l + dir * 14;
    final p3 = r + _o(-dir.dx, dir.dy) * 14;
    final k = deg.abs() < 1 ? 0.0 : 70.0 * math.sin(th.abs());
    _bezLine(
      c,
      p,
      p0,
      p0 + dir * (k + 20),
      p3 + _o(-dir.dx, dir.dy) * (k + 20),
      p3,
      col: _red,
    );
  }
  _chargeSign(c, p, 65, 90, true);
  _chargeSign(c, p, 175, 90, false);
}

void _fieldPlates(Canvas c, WbArtPen p) {
  _rect(c, p, 40, 25, 160, 8, fill: _red, a: 0.4);
  _rect(c, p, 40, 147, 160, 8, fill: _blue, a: 0.4);
  for (double x = 55; x <= 185; x += 26) {
    _ar(c, p, x, 36, x, 144, col: _orange, size: 6);
  }
  for (double x = 45; x <= 195; x += 30) {
    _t(c, p, '+', x, 17, size: 10, col: _red, bold: true);
    _t(c, p, '−', x, 166, size: 10, col: _blue, bold: true);
  }
  _t(c, p, 'E', 214, 90, size: 11, bold: true);
}

void _chargedBodies(Canvas c, WbArtPen p) {
  _chargeSign(c, p, 45, 40, true, 16);
  _chargeSign(c, p, 195, 40, false, 16);
  _ar(c, p, 68, 40, 98, 40, col: _green);
  _ar(c, p, 172, 40, 142, 40, col: _green);
  _t(c, p, 'Zıt yükler birbirini çeker', 120, 62, size: 9);
  _chargeSign(c, p, 45, 110, true, 16);
  _chargeSign(c, p, 195, 110, true, 16);
  _ar(c, p, 62, 110, 32, 110, col: _red);
  _ar(c, p, 178, 110, 208, 110, col: _red);
  _chargeSign(c, p, 100, 110, true, 16);
  _chargeSign(c, p, 140, 110, false, 16);
  _ar(c, p, 100 - 18, 110, 100 - 40, 110, col: _red);
  _ar(c, p, 140 + 18, 110, 140 + 40, 110, col: _red);
  _t(c, p, 'Benzer yükler birbirini iter', 120, 140, size: 9);
  _t(c, p, 'F', 120, 100, size: 9, bold: true, col: _green);
  _t(c, p, 'F = k·q₁·q₂ / r²', 120, 168, size: 10, bold: true);
}

void _electroscope(Canvas c, WbArtPen p) {
  _circ(c, p, 120, 28, 12, fill: _gray, a: 0.5);
  _l(c, p, 120, 40, 120, 110);
  _l(c, p, 120, 110, 105, 150);
  _l(c, p, 120, 110, 135, 150);
  c.drawPath(
    Path()
      ..moveTo(70, 80)
      ..quadraticBezierTo(60, 160, 120, 165)
      ..quadraticBezierTo(180, 160, 170, 80),
    p.fill(_lblue, 0.2),
  );
  c.drawPath(
    Path()
      ..moveTo(70, 80)
      ..quadraticBezierTo(60, 160, 120, 165)
      ..quadraticBezierTo(180, 160, 170, 80),
    p.line,
  );
  _l(c, p, 66, 80, 174, 80);
  for (final q in [
    _o(120, 20),
    _o(112, 30),
    _o(128, 30),
    _o(106, 140),
    _o(134, 140),
    _o(112, 128),
    _o(128, 128),
  ]) {
    _t(c, p, '+', q.dx, q.dy, size: 8, col: _red, bold: true);
  }
  _rect(c, p, 18, 16, 12, 50, fill: _pink, a: 0.4, rad: 4);
  _t(c, p, '+', 24, 28, size: 9, col: _red, bold: true);
  _t(c, p, 'Yüklü çubuk', 40, 76, size: 8, anchor: 'left');
  _t(c, p, 'Metal top', 155, 28, size: 8, anchor: 'left');
  _t(c, p, 'Yapraklar açılır', 185, 130, size: 8, anchor: 'right');
}

// ───────────────────────── Manyetizma ─────────────────────────

void _barMagnet(Canvas c, WbArtPen p) {
  _rect(c, p, 80, 75, 40, 30, fill: _blue, a: 0.4);
  _rect(c, p, 120, 75, 40, 30, fill: _red, a: 0.4);
  _t(c, p, 'S', 100, 90, size: 12, bold: true);
  _t(c, p, 'N', 140, 90, size: 12, bold: true);
  for (int i = 0; i < 3; i++) {
    for (final s in [-1.0, 1.0]) {
      final y0 = 90 + s * (5 + 5.0 * i);
      final h = 28.0 + 30 * i;
      _bezLine(
        c,
        p,
        _o(160, y0),
        _o(160 + 38 + 24.0 * i, 90 + s * (5 + h)),
        _o(80 - 38 - 24.0 * i, 90 + s * (5 + h)),
        _o(80, y0),
        col: _teal,
      );
    }
  }
  _l(c, p, 160, 90, 168, 90);
  _t(c, p, 'Alan çizgileri N → S', 120, 175, size: 9);
}

void _electromagnet(Canvas c, WbArtPen p) {
  _rect(c, p, 60, 85, 120, 10, fill: _gray, a: 0.5);
  for (int i = 0; i < 8; i++) {
    c.drawOval(
      Rect.fromCenter(center: Offset(82 + i * 11.0, 90), width: 8, height: 38),
      p.thin(0.9),
    );
  }
  _pline(c, p, [_o(82, 109), _o(82, 150), _o(112, 150)]);
  _pline(c, p, [_o(128, 150), _o(159, 150), _o(159, 109)]);
  _cellPl(c, p, 120, 150);
  _t(c, p, 'S', 48, 90, size: 11, bold: true, col: _blue);
  _t(c, p, 'N', 192, 90, size: 11, bold: true, col: _red);
  _ar(c, p, 85, 135, 85, 122, col: _red, size: 5);
  _t(c, p, 'I', 74, 130, size: 9, col: _red, bold: true);
  _t(c, p, 'Demir çekirdek', 120, 56, size: 9);
  _t(c, p, 'Bobin (sarım)', 120, 128, size: 8);
  _t(c, p, 'Pil', 120, 168, size: 8);
}

void _rightHandRule(Canvas c, WbArtPen p) {
  _l(c, p, 70, 165, 70, 26);
  _ar(c, p, 70, 40, 70, 12, col: _red, size: 7);
  _t(c, p, 'I', 82, 18, col: _red, bold: true);
  for (final y in [60.0, 95.0, 130.0]) {
    c.drawOval(
      Rect.fromCenter(center: Offset(70, y), width: 64, height: 20),
      p.stroke(_blue, 0.6),
    );
    p.arrow(c, _o(66, y + 10), _o(78, y + 10), c: _blue, size: 6, line: false);
  }
  _t(c, p, 'B', 112, 138, col: _blue, bold: true);
  _circ(c, p, 185, 95, 3, fill: _red, a: 1);
  _circ(c, p, 185, 95, 8, stroke: true);
  for (final r in [18.0, 30.0, 42.0]) {
    c.drawCircle(Offset(185, 95), r, p.stroke(_blue, 0.6));
    p.arrow(
      c,
      _o(188, 95 - r),
      _o(180, 95 - r),
      c: _blue,
      size: 6,
      line: false,
    );
  }
  _t(c, p, 'Yukarıdan bakış', 185, 150, size: 8);
  _t(c, p, 'akım dışarı', 185, 163, size: 8, col: _red);
  _t(c, p, 'Sağ el kuralı', 120, 176, size: 8, bold: true);
}

void _transformer(Canvas c, WbArtPen p) {
  _rect(c, p, 80, 30, 80, 110);
  _rect(c, p, 100, 50, 40, 70);
  for (double y = 42; y <= 126; y += 10) {
    c.drawOval(
      Rect.fromCenter(center: Offset(90, y), width: 34, height: 7),
      p.thin(0.9),
    );
  }
  for (double y = 42; y <= 126; y += 10) {
    c.drawOval(
      Rect.fromCenter(center: Offset(150, y), width: 34, height: 7),
      p.thin(0.9),
    );
  }
  _pline(c, p, [_o(73, 42), _o(36, 42), _o(36, 72)]);
  _pline(c, p, [_o(73, 126), _o(36, 126), _o(36, 100)]);
  _circ(c, p, 36, 86, 14, fill: _yellow, a: 0.3);
  c.drawPath(_sinePath(26, 46, 86, 4, 20), p.thin());
  _pline(c, p, [_o(167, 42), _o(204, 42), _o(204, 75)]);
  _pline(c, p, [_o(167, 126), _o(204, 126), _o(204, 97)]);
  _lamp(c, p, 204, 86);
  _t(c, p, 'N₁', 90, 20, size: 10, bold: true);
  _t(c, p, 'N₂', 150, 20, size: 10, bold: true);
  _t(c, p, 'V₁', 20, 62, size: 9, anchor: 'right');
  _t(c, p, 'V₂', 224, 62, size: 9, anchor: 'left');
  _t(c, p, 'Birincil', 90, 152, size: 8);
  _t(c, p, 'İkincil', 150, 152, size: 8);
  _t(c, p, 'V₁/V₂ = N₁/N₂', 120, 172, size: 10, bold: true);
}

void _generator(Canvas c, WbArtPen p) {
  _rect(c, p, 10, 30, 50, 80, fill: _red, a: 0.35);
  _rect(c, p, 180, 30, 50, 80, fill: _blue, a: 0.35);
  _t(c, p, 'N', 35, 70, size: 14, bold: true);
  _t(c, p, 'S', 205, 70, size: 14, bold: true);
  _da(c, p, 120, 20, 120, 120);
  _rect(c, p, 90, 45, 60, 55, fill: _orange, a: 0.2);
  _rotArrow(c, p, 120, 72, 38, 200, 100, _green);
  _pline(c, p, [_o(90, 100), _o(90, 135), _o(108, 135)]);
  _pline(c, p, [_o(150, 100), _o(150, 135), _o(132, 135)]);
  _lamp(c, p, 120, 135, 11);
  _t(c, p, 'Dönen çerçeve', 120, 10, size: 9);
  _t(c, p, 'Fırça', 60, 150, size: 8);
  _t(c, p, 'Hareket enerjisi → elektrik enerjisi', 120, 170, size: 8);
}

// ───────────────────────── Optik ─────────────────────────

void _planeMirror(Canvas c, WbArtPen p) {
  _ground(c, p, 20, 220, 140);
  _da(c, p, 120, 30, 120, 140);
  _ar(c, p, 50, 40, 118, 138, col: _blue);
  _ar(c, p, 120, 140, 190, 40, col: _red);
  c.drawPath(WbArtPen.arc(const Offset(120, 140), 36, -90, -34.5), p.thin());
  c.drawPath(WbArtPen.arc(const Offset(120, 140), 36, -90, 34.5), p.thin());
  _t(c, p, 'i', 102, 98, size: 10, bold: true);
  _t(c, p, 'r', 138, 98, size: 10, bold: true);
  _t(c, p, 'Normal', 120, 22, size: 9);
  _t(c, p, 'Gelen ışın', 40, 62, size: 8, col: _blue, anchor: 'left');
  _t(c, p, 'Yansıyan ışın', 200, 62, size: 8, col: _red, anchor: 'right');
  _t(c, p, 'Düzlem ayna', 120, 164, size: 9);
  _t(c, p, 'i = r', 210, 125, size: 10, bold: true);
}

void _mirrorImage(Canvas c, WbArtPen p) {
  _wall(c, p, 120, 15, 165, left: false);
  _ar(c, p, 60, 105, 60, 60, col: _green, size: 7);
  _ar(c, p, 180, 105, 180, 60, col: _gray, size: 7);
  p.dashed(c, const Offset(180, 105), const Offset(180, 60));
  _l(c, p, 60, 60, 120, 95);
  _l(c, p, 120, 95, 50, 136);
  p.dashed(c, const Offset(120, 95), const Offset(180, 60));
  _da(c, p, 60, 120, 180, 120);
  _t(c, p, 'Cisim', 60, 118, size: 8);
  _t(c, p, 'Görüntü', 180, 118, size: 8);
  _t(c, p, 'sanal', 180, 132, size: 8);
  _t(c, p, 'Göz', 40, 150, size: 8);
  _t(c, p, 'Cisim-ayna uzaklığı = görüntü-ayna uzaklığı', 120, 172, size: 8);
}

void _concaveMirror(Canvas c, WbArtPen p) {
  const cc = Offset(60, 90);
  c.drawPath(WbArtPen.arc(cc, 150, -35, 70), p.stroke(p.color, 1.6));
  for (double a = -32; a <= 32; a += 8) {
    final r = a * math.pi / 180;
    _th(
      c,
      p,
      cc.dx + 150 * math.cos(r),
      cc.dy + 150 * math.sin(r),
      cc.dx + 156 * math.cos(r) + 5,
      cc.dy + 156 * math.sin(r),
    );
  }
  _da(c, p, 15, 90, 215, 90);
  const f = Offset(135, 90);
  for (final y in [40.0, 140.0]) {
    final hx = cc.dx + math.sqrt(150 * 150 - (y - 90) * (y - 90));
    final hit = Offset(hx, y);
    _ar(c, p, 20, y, hit.dx, y, col: _blue, size: 6);
    final d = f - hit;
    _lc(c, p, _red, hit.dx, hit.dy, f.dx + d.dx * 0.5, f.dy + d.dy * 0.5);
  }
  _t(c, p, 'F', 135, 102, size: 10, bold: true);
  _t(c, p, 'M', 60, 102, size: 10, bold: true);
  _t(c, p, 'T', 214, 102, size: 10, bold: true);
  c.drawCircle(f, 2.5, p.solid);
  c.drawCircle(cc, 2.5, p.solid);
  _t(c, p, 'Çukur ayna', 120, 14, size: 9);
  _t(c, p, 'f = R/2', 100, 166, size: 9);
}

void _convexMirror(Canvas c, WbArtPen p) {
  const cc = Offset(280, 90);
  c.drawPath(WbArtPen.arc(cc, 150, 145, 70), p.stroke(p.color, 1.6));
  for (double a = 148; a <= 212; a += 8) {
    final r = a * math.pi / 180;
    _th(
      c,
      p,
      cc.dx + 150 * math.cos(r),
      cc.dy + 150 * math.sin(r),
      cc.dx + 156 * math.cos(r) - 5,
      cc.dy + 156 * math.sin(r),
    );
  }
  _da(c, p, 10, 90, 225, 90);
  const f = Offset(205, 90);
  for (final y in [50.0, 130.0]) {
    final hit = Offset(cc.dx - math.sqrt(150 * 150 - (y - 90) * (y - 90)), y);
    _ar(c, p, 12, y, hit.dx, y, col: _blue, size: 6);
    final d = hit - f;
    _lc(c, p, _red, hit.dx, hit.dy, hit.dx + d.dx, hit.dy + d.dy);
    p.dashed(c, hit, f);
  }
  c.drawCircle(f, 2.5, p.solid);
  _t(c, p, 'F (sanal)', 205, 104, size: 9, bold: true);
  _t(c, p, 'Tümsek ayna', 90, 14, size: 9);
  _t(c, p, 'Işınlar dağılır', 70, 166, size: 9);
}

void _convexLens(Canvas c, WbArtPen p) {
  _da(c, p, 5, 100, 235, 100);
  final lens = Path()
    ..moveTo(130, 30)
    ..quadraticBezierTo(150, 100, 130, 170)
    ..quadraticBezierTo(110, 100, 130, 30);
  c.drawPath(lens, p.fill(_lblue, 0.25));
  c.drawPath(lens, p.line);
  _ar(c, p, 10, 100, 10, 60, col: _green, size: 7);
  const tip = Offset(10, 60);
  _lc(c, p, _red, 10, 60, 130, 60);
  _lc(c, p, _red, 130, 60, 202, 124);
  _lc(c, p, _blue, tip.dx, tip.dy, 202, 124);
  _lc(c, p, _orange, 10, 60, 130, 124);
  _lc(c, p, _orange, 130, 124, 202, 124);
  _ar(c, p, 202, 100, 202, 124, col: _green, size: 6);
  c.drawCircle(const Offset(85, 100), 2.5, p.solid);
  c.drawCircle(const Offset(175, 100), 2.5, p.solid);
  _t(c, p, 'F', 85, 112, size: 9, bold: true);
  _t(c, p, "F'", 175, 112, size: 9, bold: true);
  _t(c, p, 'Cisim', 22, 80, size: 8, anchor: 'left');
  _t(c, p, 'Görüntü\n(gerçek, ters)', 212, 150, size: 8, anchor: 'right');
  _t(c, p, 'İnce kenarlı (yakınsak) mercek', 120, 14, size: 9);
}

void _concaveLens(Canvas c, WbArtPen p) {
  _da(c, p, 5, 100, 235, 100);
  final lens = Path()
    ..moveTo(111, 30)
    ..lineTo(129, 30)
    ..quadraticBezierTo(121, 100, 129, 170)
    ..lineTo(111, 170)
    ..quadraticBezierTo(119, 100, 111, 30);
  c.drawPath(lens, p.fill(_lblue, 0.25));
  c.drawPath(lens, p.line);
  _ar(c, p, 20, 100, 20, 60, col: _green, size: 7);
  _lc(c, p, _red, 20, 60, 120, 60);
  _lc(c, p, _red, 120, 60, 185, 8);
  p.dashed(c, const Offset(120, 60), const Offset(70, 100));
  _lc(c, p, _blue, 20, 60, 120, 100);
  _lc(c, p, _blue, 120, 100, 220, 140);
  p.dashed(c, const Offset(120, 100), const Offset(86.7, 86.7));
  p.arrow(
    c,
    const Offset(86.7, 100),
    const Offset(86.7, 86.7),
    c: _gray,
    size: 5,
  );
  c.drawCircle(const Offset(70, 100), 2.5, p.solid);
  c.drawCircle(const Offset(170, 100), 2.5, p.solid);
  _t(c, p, 'F', 70, 112, size: 9, bold: true);
  _t(c, p, "F'", 170, 112, size: 9, bold: true);
  _t(c, p, 'Görüntü (sanal, düz, küçük)', 100, 160, size: 8);
  _t(c, p, 'Kalın kenarlı (ıraksak) mercek', 120, 14, size: 9);
}

void _refraction(Canvas c, WbArtPen p) {
  c.drawRect(const Rect.fromLTWH(20, 90, 200, 80), p.fill(_blue, 0.22));
  _l(c, p, 20, 90, 220, 90);
  _da(c, p, 120, 20, 120, 170);
  _ar(c, p, 50, 20, 118, 88, col: _blue);
  _ar(c, p, 120, 90, 170, 170, col: _blue);
  _lc(c, p, _gray, 120, 90, 190, 20, 0.5);
  c.drawPath(WbArtPen.arc(const Offset(120, 90), 28, -135, 45), p.thin());
  c.drawPath(WbArtPen.arc(const Offset(120, 90), 28, 58, 32), p.thin());
  _t(c, p, 'θ₁', 98, 58, size: 10, bold: true);
  _t(c, p, 'θ₂', 134, 130, size: 10, bold: true);
  _t(c, p, 'Normal', 120, 12, size: 9);
  _t(c, p, 'Hava (n₁ = 1)', 30, 40, size: 8, anchor: 'left');
  _t(c, p, 'Su (n₂ = 1,33)', 210, 150, size: 8, anchor: 'right');
  _t(c, p, 'Gelen', 50, 78, size: 8, col: _blue);
  _t(c, p, 'Kırılan', 170, 112, size: 8, col: _blue, anchor: 'left');
  _t(c, p, 'Normale yaklaşır', 40, 120, size: 8, anchor: 'left');
}

void _prism(Canvas c, WbArtPen p) {
  _poly(c, p, [_o(120, 30), _o(70, 117), _o(170, 117)], fill: _lblue, a: 0.2);
  _ar(c, p, 15, 110, 87.5, 86.5, col: p.color, size: 6);
  _l(c, p, 87.5, 86.5, 155, 91);
  const cols = [_red, _orange, _yellow, _green, _blue, _purple];
  for (int i = 0; i < 6; i++) {
    _lc(c, p, cols[i], 155, 91, 228, 112 + i * 10.0, 1);
  }
  _t(c, p, 'Beyaz ışık', 45, 130, size: 9);
  _t(c, p, 'Prizma', 120, 135, size: 9);
  _t(c, p, 'Kırmızı', 232, 108, size: 7, col: _red, anchor: 'right');
  _t(c, p, 'Mor', 232, 172, size: 7, col: _purple, anchor: 'right');
  _t(c, p, 'Işığın dağılması', 120, 14, size: 9, bold: true);
}

void _totalReflection(Canvas c, WbArtPen p) {
  c.drawRect(const Rect.fromLTWH(15, 90, 210, 80), p.fill(_blue, 0.22));
  _l(c, p, 15, 90, 225, 90);
  _da(c, p, 120, 30, 120, 170);
  _t(c, p, 'Su', 30, 160, size: 9);
  _t(c, p, 'Hava', 30, 40, size: 9);
  final angs = [25.0, 49.0, 65.0];
  final cols = [_green, _orange, _red];
  for (int i = 0; i < 3; i++) {
    final th = angs[i] * math.pi / 180;
    _lc(
      c,
      p,
      cols[i],
      120 - 85 * math.sin(th),
      90 + 85 * math.cos(th),
      120,
      90,
    );
  }
  _lc(c, p, _green, 120, 90, 153.7, 40.3);
  _lc(c, p, _orange, 120, 90, 195, 90);
  _lc(c, p, _red, 120, 90, 197, 165);
  _t(c, p, 'θ < θk', 160, 34, size: 8, col: _green, bold: true, anchor: 'left');
  _t(
    c,
    p,
    'θ = θk',
    200,
    80,
    size: 8,
    col: _orange,
    bold: true,
    anchor: 'left',
  );
  _t(c, p, 'θ > θk', 200, 150, size: 8, col: _red, bold: true, anchor: 'right');
  _t(c, p, 'Tam yansıma', 120, 14, size: 9, bold: true);
}

void _eyeLens(Canvas c, WbArtPen p) {
  _circ(c, p, 130, 90, 50, fill: _lblue, a: 0.12);
  c.drawPath(
    WbArtPen.arc(const Offset(130, 90), 50, -40, 80),
    p.stroke(_red, 1.8),
  );
  c.drawPath(
    Path()..addOval(
      Rect.fromCenter(center: const Offset(92, 90), width: 12, height: 36),
    ),
    p.fill(_blue, 0.35),
  );
  c.drawOval(
    Rect.fromCenter(center: const Offset(92, 90), width: 12, height: 36),
    p.line,
  );
  _l(c, p, 95, 55, 95, 68);
  _l(c, p, 95, 112, 95, 125);
  _l(c, p, 178, 100, 220, 108);
  _ar(c, p, 15, 55, 15, 38, col: _green, size: 6);
  for (final y in [68.0, 90.0, 112.0]) {
    _lc(c, p, _orange, 15, 55, 92, y);
    _lc(c, p, _orange, 92, y, 173, 115);
  }
  _t(c, p, 'Mercek', 92, 142, size: 8);
  _t(c, p, 'Göz bebeği (iris)', 60, 30, size: 8);
  _t(c, p, 'Retina', 195, 60, size: 8, col: _red, bold: true);
  _t(c, p, 'Sinir', 222, 122, size: 8, anchor: 'right');
  _t(c, p, 'Görüntü retinada ters oluşur', 120, 172, size: 8);
}

void _shadow(Canvas c, WbArtPen p) {
  _poly(
    c,
    p,
    [_o(110, 70), _o(215, 24), _o(215, 63), _o(110, 70)],
    fill: _gray,
    a: 0.2,
    stroke: false,
  );
  _poly(
    c,
    p,
    [_o(110, 110), _o(215, 117), _o(215, 156)],
    fill: _gray,
    a: 0.2,
    stroke: false,
  );
  _poly(
    c,
    p,
    [_o(110, 70), _o(215, 63), _o(215, 117), _o(110, 110)],
    fill: _gray,
    a: 0.5,
    stroke: false,
  );
  _circ(c, p, 30, 90, 15, fill: _yellow, a: 0.6);
  _l(c, p, 110, 70, 110, 110);
  _l(c, p, 215, 10, 215, 170);
  for (final seg in [
    [30.0, 75.0, 110.0, 70.0, 215.0, 63.4],
    [30.0, 105.0, 110.0, 70.0, 215.0, 24.1],
    [30.0, 75.0, 110.0, 110.0, 215.0, 155.9],
    [30.0, 105.0, 110.0, 110.0, 215.0, 116.6],
  ]) {
    _lc(c, p, _orange, seg[0], seg[1], seg[4], seg[5], 0.4);
  }
  _t(c, p, 'Geniş ışık\nkaynağı', 30, 125, size: 8);
  _t(c, p, 'Cisim', 110, 125, size: 8);
  _t(c, p, 'Tam gölge', 170, 90, size: 8, bold: true);
  _t(c, p, 'Yarı gölge', 160, 40, size: 8);
  _t(c, p, 'Yarı gölge', 160, 140, size: 8);
  _t(c, p, 'Perde', 215, 178, size: 8);
}

void _solarEclipse(Canvas c, WbArtPen p) {
  _circ(c, p, 30, 90, 30, fill: _yellow, a: 0.55);
  _poly(
    c,
    p,
    [_o(150, 82), _o(215, 61.4), _o(215, 118.6), _o(150, 98)],
    fill: _gray,
    a: 0.18,
    stroke: false,
  );
  _poly(
    c,
    p,
    [_o(150, 82), _o(193.6, 90), _o(150, 98)],
    fill: _gray,
    a: 0.55,
    stroke: false,
  );
  _lc(c, p, _orange, 30, 60, 193.6, 90, 0.35);
  _lc(c, p, _orange, 30, 120, 193.6, 90, 0.35);
  _circ(c, p, 150, 90, 8, fill: _gray, a: 0.7);
  _circ(c, p, 205, 90, 18, fill: _blue, a: 0.4);
  _t(c, p, 'Güneş', 30, 132, size: 9);
  _t(c, p, 'Ay', 150, 112, size: 9);
  _t(c, p, 'Dünya', 205, 120, size: 9);
  _t(c, p, 'Güneş tutulması (Yeni Ay)', 120, 14, size: 9, bold: true);
  _t(c, p, 'Ölçekli değil', 120, 172, size: 8);
}

void _lunarEclipse(Canvas c, WbArtPen p) {
  _circ(c, p, 30, 90, 30, fill: _yellow, a: 0.55);
  _poly(
    c,
    p,
    [_o(110, 70), _o(220, 1.25), _o(220, 178.75), _o(110, 110)],
    fill: _gray,
    a: 0.13,
    stroke: false,
  );
  _poly(
    c,
    p,
    [_o(110, 70), _o(235, 85.6), _o(235, 94.4), _o(110, 110)],
    fill: _gray,
    a: 0.45,
    stroke: false,
  );
  _circ(c, p, 110, 90, 20, fill: _blue, a: 0.4);
  _circ(c, p, 205, 90, 7, fill: _red, a: 0.5);
  _t(c, p, 'Güneş', 30, 132, size: 9);
  _t(c, p, 'Dünya', 110, 122, size: 9);
  _t(c, p, 'Ay', 205, 112, size: 9);
  _t(c, p, 'Ay tutulması (Dolunay)', 120, 14, size: 9, bold: true);
  _t(c, p, 'Ölçekli değil', 120, 172, size: 8);
}

// ───────────────────────── Dalga ve ses ─────────────────────────

void _transverseWave(Canvas c, WbArtPen p) {
  _da(c, p, 15, 90, 225, 90);
  c.drawPath(_sinePath(20, 220, 90, 40, 100), p.stroke(_blue, 1));
  _dar(c, p, 45, 36, 145, 36);
  _da(c, p, 45, 36, 45, 50);
  _da(c, p, 145, 36, 145, 50);
  _t(c, p, 'λ (dalga boyu)', 95, 26, size: 9, bold: true);
  _dar(c, p, 195, 90, 195, 50, col: _red);
  _t(c, p, 'A', 205, 70, size: 10, col: _red, bold: true);
  _t(c, p, 'Tepe', 45, 24, size: 8);
  _t(c, p, 'Çukur', 95, 142, size: 8);
  _t(c, p, 'Genlik', 215, 52, size: 8, col: _red, anchor: 'right');
  _ar(c, p, 160, 160, 215, 160);
  _t(c, p, 'Yayılma yönü', 125, 160, size: 8);
  _t(c, p, 'Enine dalga', 120, 176, size: 9, bold: true);
}

void _longitudinalWave(Canvas c, WbArtPen p) {
  for (double b = 20; b <= 220; b += 6) {
    final x = b + 6 * math.sin(2 * math.pi * (b - 20) / 70);
    _l(c, p, x, 60, x, 100);
  }
  _l(c, p, 20, 80, 220, 80);
  _dar(c, p, 55, 120, 125, 120);
  _da(c, p, 55, 104, 55, 124);
  _da(c, p, 125, 104, 125, 124);
  _t(c, p, 'λ', 90, 132, size: 10, bold: true);
  _t(c, p, 'Sıkışma', 55, 44, size: 8, col: _red);
  _t(c, p, 'Seyrelme', 90, 44, size: 8, col: _blue);
  _t(c, p, 'Sıkışma', 125, 44, size: 8, col: _red);
  _t(c, p, 'Seyrelme', 160, 44, size: 8, col: _blue);
  _ar(c, p, 20, 150, 75, 150);
  _t(c, p, 'Yayılma yönü', 135, 150, size: 8);
  _t(c, p, 'Boyuna dalga (yay / ses)', 120, 172, size: 9, bold: true);
}

void _soundFork(Canvas c, WbArtPen p) {
  final fork = Path()
    ..moveTo(40, 40)
    ..lineTo(40, 100)
    ..quadraticBezierTo(40, 118, 55, 118)
    ..quadraticBezierTo(70, 118, 70, 100)
    ..lineTo(70, 40);
  c.drawPath(fork, p.line);
  _l(c, p, 55, 118, 55, 160);
  for (final r in [30.0, 52.0, 74.0, 96.0]) {
    c.drawPath(
      WbArtPen.arc(const Offset(72, 70), r, -40, 80),
      p.stroke(_blue, 0.6),
    );
  }
  for (final r in [18.0, 36.0]) {
    c.drawPath(
      WbArtPen.arc(const Offset(38, 70), r, 140, 80),
      p.stroke(_blue, 0.6),
    );
  }
  _t(c, p, 'Diyapazon', 55, 172, size: 9);
  _t(c, p, 'Ses dalgası', 150, 26, size: 9, bold: true);
  _t(c, p, 'Hava\nmolekülleri\nsıkışıp\nseyrelir', 190, 125, size: 8);
}

void _emSpectrum(Canvas c, WbArtPen p) {
  const names = [
    'Radyo',
    'Mikrodalga',
    'Kızılötesi',
    'Görünür',
    'Morötesi',
    'X-ışını',
    'Gama',
  ];
  const cols = [_gray, _orange, _red, _green, _purple, _blue, _pink];
  for (int i = 0; i < 7; i++) {
    final x = 10.0 + i * 42;
    if (i == 3) {
      final r = Rect.fromLTWH(x, 40, 42, 30);
      c.drawRect(
        r,
        Paint()
          ..shader = const LinearGradient(
            colors: [
              Color(0xCCEF4444),
              Color(0xCCFACC15),
              Color(0xCC22C55E),
              Color(0xCC3B82F6),
              Color(0xCC8B5CF6),
            ],
          ).createShader(r),
      );
      c.drawRect(r, p.line);
    } else {
      _rect(c, p, x, 40, 42, 30, fill: cols[i], a: 0.4);
    }
    _t(c, p, names[i], x + 21, i.isEven ? 82 : 96, size: 8, bold: true);
  }
  _ar(c, p, 10, 20, 300, 20);
  _t(c, p, 'Frekans ve enerji artar', 155, 10, size: 8);
  _ar(c, p, 300, 125, 10, 125);
  _t(c, p, 'Dalga boyu artar', 155, 136, size: 8);
}

void _doppler(Canvas c, WbArtPen p) {
  for (int k = 1; k <= 5; k++) {
    c.drawCircle(Offset(150.0 - 12 * k, 90), 16.0 * k, p.stroke(_blue, 0.5));
  }
  _circ(c, p, 150, 90, 5, fill: _red, a: 0.9);
  _ar(c, p, 158, 90, 195, 90, col: _red);
  _t(c, p, 'Kaynak', 150, 108, size: 8, col: _red);
  _t(c, p, 'v', 195, 80, size: 9, col: _red, bold: true);
  _t(c, p, 'Gözlemci A\nλ büyük, f küçük', 50, 170, size: 8);
  _t(c, p, 'Gözlemci B\nλ küçük, f büyük', 185, 170, size: 8);
  _t(c, p, 'Doppler olayı', 120, 12, size: 9, bold: true);
}

void _waveInterference(Canvas c, WbArtPen p) {
  const s1 = Offset(80, 165), s2 = Offset(160, 165);
  for (int i = 1; i <= 7; i++) {
    c.drawPath(WbArtPen.arc(s1, 20.0 * i, 180, 180), p.stroke(_blue, 0.4));
    c.drawPath(WbArtPen.arc(s2, 20.0 * i, 180, 180), p.stroke(_blue, 0.4));
  }
  for (int i = 1; i <= 7; i++) {
    for (int j = 1; j <= 7; j++) {
      final r1 = 20.0 * i, r2 = 20.0 * j;
      final x = (r1 * r1 - r2 * r2 + 6400) / 160;
      final yy2 = r1 * r1 - x * x;
      if (yy2 <= 0) continue;
      final y = 165 - math.sqrt(yy2);
      if (y < 5) continue;
      c.drawCircle(Offset(80 + x, y), 2.4, p.fill(_green, 0.9));
    }
  }
  c.drawCircle(s1, 4, p.fill(_red, 1));
  c.drawCircle(s2, 4, p.fill(_red, 1));
  _t(c, p, 'K₁', 80, 176, size: 8);
  _t(c, p, 'K₂', 160, 176, size: 8);
  _t(c, p, 'Yeşil nokta: tepe-tepe (yapıcı girişim)', 120, 8, size: 8);
}

void _waveReflection(Canvas c, WbArtPen p) {
  Path bump(double x, double y, double h) => Path()
    ..moveTo(x - 22, y)
    ..cubicTo(x - 8, y, x - 8, y - h, x, y - h)
    ..cubicTo(x + 8, y - h, x + 8, y, x + 22, y);
  final ys = [30.0, 72.0, 118.0, 160.0];
  for (int i = 0; i < 4; i++) {
    _l(c, p, 20, ys[i], 205, ys[i]);
  }
  _wall(c, p, 205, 8, 82, left: false);
  _l(c, p, 205, 100, 205, 172);
  _circ(c, p, 205, 118, 4);
  _circ(c, p, 205, 160, 4);
  c.drawPath(bump(90, ys[0], 14), p.stroke(_blue, 1));
  c.drawPath(bump(130, ys[1], -14), p.stroke(_red, 1));
  c.drawPath(bump(90, ys[2], 14), p.stroke(_blue, 1));
  c.drawPath(bump(130, ys[3], 14), p.stroke(_red, 1));
  _ar(c, p, 120, ys[0] - 4, 150, ys[0] - 4, col: _blue, size: 5);
  _ar(c, p, 100, ys[1] + 8, 70, ys[1] + 8, col: _red, size: 5);
  _ar(c, p, 120, ys[2] - 4, 150, ys[2] - 4, col: _blue, size: 5);
  _ar(c, p, 100, ys[3] + 8, 70, ys[3] + 8, col: _red, size: 5);
  _t(c, p, 'Gelen', 30, ys[0] - 14, size: 8, anchor: 'left');
  _t(c, p, 'Yansıyan (ters)', 30, ys[1] + 18, size: 8, anchor: 'left');
  _t(c, p, 'Gelen', 30, ys[2] - 14, size: 8, anchor: 'left');
  _t(c, p, 'Yansıyan (düz)', 30, ys[3] + 12, size: 8, anchor: 'left');
  _t(c, p, 'Sabit uç', 215, 45, size: 8, anchor: 'right');
  _t(c, p, 'Serbest uç', 195, 135, size: 8, anchor: 'right');
}

// ───────────────────────── Modern fizik ─────────────────────────

void _nucleus(Canvas c, WbArtPen p, double x, double y, double r) {
  _circ(c, p, x - r * 0.4, y - r * 0.3, r, fill: _red, a: 0.6);
  _circ(c, p, x + r * 0.5, y + r * 0.1, r, fill: _gray, a: 0.6);
  _circ(c, p, x - r * 0.1, y + r * 0.6, r, fill: _red, a: 0.6);
}

void _rutherford(Canvas c, WbArtPen p) {
  _nucleus(c, p, 120, 90, 6);
  for (final a in [0.0, 60.0, 120.0]) {
    _rot(c, 120, 90, a, () {
      c.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 190, height: 70),
        p.stroke(_blue, 0.4),
      );
    });
  }
  for (final e in [_o(215, 90), _o(72, 33), _o(70, 148)]) {
    _circ(c, p, e.dx, e.dy, 5, fill: _blue, a: 0.8);
  }
  _t(c, p, 'Çekirdek (+)', 120, 112, size: 8);
  _t(c, p, 'e⁻', 215, 76, size: 9, col: _blue, bold: true);
  _t(c, p, 'Rutherford atom modeli', 120, 12, size: 9, bold: true);
  _t(c, p, 'Elektronlar çekirdek çevresinde dolanır', 120, 174, size: 8);
}

void _bohr(Canvas c, WbArtPen p) {
  _nucleus(c, p, 90, 90, 6);
  for (final r in [25.0, 50.0, 75.0]) {
    c.drawCircle(Offset(90, 90), r, p.stroke(_blue, 0.5));
  }
  _circ(
    c,
    p,
    90 + 75 * math.cos(-0.6),
    90 + 75 * math.sin(-0.6),
    5,
    fill: _blue,
    a: 0.8,
  );
  _circ(c, p, 90 + 25, 90, 5, fill: _blue, a: 0.8);
  final e3 = Offset(90 + 75 * math.cos(-0.6), 90 + 75 * math.sin(-0.6));
  final e2 = Offset(90 + 50 * math.cos(-0.6), 90 + 50 * math.sin(-0.6));
  p.arrow(
    c,
    e3 + const Offset(-4, 4),
    e2 + const Offset(3, -3),
    c: _red,
    size: 6,
  );
  c.drawPath(_sinePath(160, 215, 40, 6, 14), p.stroke(_orange, 0.7));
  p.arrow(
    c,
    const Offset(210, 40),
    const Offset(222, 40),
    c: _orange,
    size: 6,
    line: false,
  );
  _t(c, p, 'foton (hf)', 190, 22, size: 8, col: _orange, bold: true);
  _t(c, p, 'n=1', 90, 62, size: 8);
  _t(c, p, 'n=2', 60, 134, size: 8);
  _t(c, p, 'n=3', 90, 172, size: 8);
  _t(c, p, 'Bohr atom modeli', 190, 120, size: 9, bold: true);
  _t(c, p, 'ΔE = hf', 190, 140, size: 9);
}

void _photoelectric(Canvas c, WbArtPen p) {
  _rect(c, p, 20, 130, 200, 22, fill: _gray, a: 0.45);
  for (double x = 40; x <= 200; x += 32) {
    _t(c, p, '+', x, 141, size: 10, col: _red, bold: true);
  }
  for (final x in [60.0, 100.0, 140.0]) {
    c.drawPath(_sinePath(x - 30, x + 6, 0, 5, 14), p.stroke(_yellow, 0.7));
  }
  for (final x in [50.0, 90.0, 130.0]) {
    final from = _o(x - 20, 20);
    final to = _o(x + 10, 118);
    c.drawPath(
      Path()
        ..moveTo(from.dx, from.dy)
        ..lineTo(to.dx, to.dy),
      p.stroke(_yellow, 0.7),
    );
    p.arrow(c, to - const Offset(3, 10), to, c: _yellow, size: 7, line: false);
  }
  for (final e in [_o(160, 100), _o(190, 80), _o(210, 110)]) {
    _circ(c, p, e.dx, e.dy, 4, fill: _blue, a: 0.9);
    _ar(c, p, e.dx, e.dy, e.dx + 8, e.dy - 18, col: _blue, size: 5);
  }
  _t(
    c,
    p,
    'Foton (hf)',
    15,
    12,
    size: 9,
    col: _orange,
    bold: true,
    anchor: 'left',
  );
  _t(c, p, 'Metal yüzey', 120, 168, size: 9);
  _t(c, p, 'e⁻', 190, 62, size: 9, col: _blue, bold: true);
  _t(c, p, 'Ek = hf − W', 175, 28, size: 10, bold: true);
  _t(c, p, 'f > f₀ olmalı', 175, 44, size: 8);
}

void _decayGraph(Canvas c, WbArtPen p) {
  _axes(c, p, 40, 150, 180, 130, 'Zaman (t)', 'N');
  final path = Path()..moveTo(40, 30);
  for (double x = 40; x <= 220; x += 3) {
    final t = (x - 40) / 50;
    path.lineTo(x, 150 - 120 * math.pow(0.5, t).toDouble());
  }
  c.drawPath(path, p.stroke(_red));
  for (int k = 1; k <= 3; k++) {
    final x = 40.0 + 50 * k;
    final y = 150 - 120 / math.pow(2, k).toDouble();
    _da(c, p, x, 150, x, y);
    _da(c, p, 40, y, x, y);
    _t(c, p, k == 1 ? 'T½' : '${k}T½', x, 162, size: 8);
  }
  _t(c, p, 'N₀', 34, 30, size: 8, anchor: 'right');
  _t(c, p, 'N₀/2', 34, 90, size: 8, anchor: 'right');
  _t(c, p, 'N₀/4', 34, 120, size: 8, anchor: 'right');
  _t(c, p, 'N₀/8', 34, 135, size: 8, anchor: 'right');
}

void _radiationPenetration(Canvas c, WbArtPen p) {
  _rect(c, p, 12, 70, 28, 40, fill: _gray, a: 0.5);
  _t(c, p, 'Kaynak', 26, 120, size: 8);
  _rect(c, p, 100, 30, 4, 120, fill: _yellow, a: 0.5);
  _rect(c, p, 140, 30, 8, 120, fill: _gray, a: 0.5);
  _rect(c, p, 180, 30, 20, 120, fill: _brown, a: 0.5);
  _t(c, p, 'Kâğıt', 102, 20, size: 8);
  _t(c, p, 'Alüminyum', 144, 20, size: 8);
  _t(c, p, 'Kurşun', 190, 20, size: 8);
  _lc(c, p, _red, 40, 60, 99, 60);
  _lc(c, p, _blue, 40, 90, 139, 90);
  _lc(c, p, _green, 40, 120, 195, 120);
  _t(c, p, 'α', 70, 52, size: 10, col: _red, bold: true);
  _t(c, p, 'β', 90, 82, size: 10, col: _blue, bold: true);
  _t(c, p, 'γ', 120, 112, size: 10, col: _green, bold: true);
  _t(c, p, 'Geçirgenlik: α < β < γ', 120, 170, size: 9, bold: true);
}

// ───────────────────────── Liste ─────────────────────────

final List<WbArtItem> wbArtPhysics = [
  // Basit makineler
  WbArtItem(
    'fiz_sabit_makara',
    'Sabit makara',
    240,
    180,
    _fixedPulley,
    tags: 'makara basit makine sabit kuvvet yön',
  ),
  WbArtItem(
    'fiz_hareketli_makara',
    'Hareketli makara',
    240,
    180,
    _movingPulley,
    tags: 'makara basit makine hareketli kuvvet kazanç',
  ),
  WbArtItem(
    'fiz_palanga',
    'Palanga (bileşik makara)',
    240,
    180,
    _blockTackle,
    tags: 'palanga makara sistemi bileşik basit makine',
  ),
  WbArtItem(
    'fiz_kaldirac_1',
    '1. tür kaldıraç',
    240,
    180,
    _lever1,
    tags: 'kaldıraç destek yük kuvvet basit makine',
  ),
  WbArtItem(
    'fiz_kaldirac_2',
    '2. tür kaldıraç',
    240,
    180,
    _lever2,
    tags: 'kaldıraç destek yük kuvvet basit makine',
  ),
  WbArtItem(
    'fiz_kaldirac_3',
    '3. tür kaldıraç',
    240,
    180,
    _lever3,
    tags: 'kaldıraç destek yük kuvvet basit makine',
  ),
  WbArtItem(
    'fiz_el_arabasi',
    'El arabası',
    240,
    180,
    _wheelbarrow,
    tags: 'el arabası kaldıraç tekerlek',
  ),
  WbArtItem(
    'fiz_egik_duzlem',
    'Eğik düzlem',
    240,
    180,
    _incline,
    tags: 'eğik düzlem rampa kuvvet sürtünme basit makine',
  ),
  WbArtItem(
    'fiz_cikrik',
    'Çıkrık',
    240,
    180,
    _windlass,
    tags: 'çıkrık kuyu basit makine tork',
  ),
  WbArtItem(
    'fiz_disli_2',
    'Dişli çarklar (2)',
    240,
    190,
    _gears2,
    tags: 'dişli çark basit makine',
  ),
  WbArtItem(
    'fiz_disli_3',
    'Dişli çarklar (3)',
    240,
    180,
    _gears3,
    tags: 'dişli çark ara dişli basit makine',
  ),
  WbArtItem(
    'fiz_kasnak_kayis',
    'Kasnak ve kayış',
    240,
    180,
    _beltPulley,
    tags: 'kasnak kayış basit makine',
  ),
  WbArtItem(
    'fiz_vida',
    'Vida',
    240,
    180,
    _screw,
    tags: 'vida adım diş basit makine',
  ),
  WbArtItem(
    'fiz_kama',
    'Kama',
    240,
    180,
    _wedge,
    tags: 'kama basit makine balta',
  ),
  // Kuvvet ve hareket
  WbArtItem(
    'fiz_scd_yatay',
    'Serbest cisim diyagramı (yatay)',
    240,
    180,
    _fbdFlat,
    tags: 'serbest cisim diyagramı kuvvet newton yatay',
  ),
  WbArtItem(
    'fiz_scd_egik',
    'Serbest cisim diyagramı (eğik zemin)',
    240,
    180,
    _fbdIncline,
    tags: 'serbest cisim diyagramı eğik zemin kuvvet bileşen',
  ),
  WbArtItem(
    'fiz_surtunme',
    'Sürtünmeli yüzey',
    240,
    180,
    _frictionSurface,
    tags: 'sürtünme kuvveti yüzey pürüzlü',
  ),
  WbArtItem(
    'fiz_vektor_paralel',
    'Vektör toplama (paralelkenar)',
    240,
    180,
    _vecParallelogram,
    tags: 'vektör toplama paralelkenar bileşke',
  ),
  WbArtItem(
    'fiz_vektor_uc_uca',
    'Vektör toplama (uç uca)',
    240,
    180,
    _vecTipToTail,
    tags: 'vektör toplama uç uca bileşke',
  ),
  WbArtItem(
    'fiz_grafik_xt',
    'Konum-zaman (x-t) grafiği',
    240,
    180,
    _graphXt,
    tags: 'grafik konum zaman x-t hareket',
  ),
  WbArtItem(
    'fiz_grafik_vt',
    'Hız-zaman (v-t) grafiği',
    240,
    180,
    _graphVt,
    tags: 'grafik hız zaman v-t hareket',
  ),
  WbArtItem(
    'fiz_grafik_at',
    'İvme-zaman (a-t) grafiği',
    240,
    180,
    _graphAt,
    tags: 'grafik ivme zaman a-t hareket',
  ),
  WbArtItem(
    'fiz_egik_atis',
    'Eğik atış',
    240,
    180,
    _projectile,
    tags: 'eğik atış parabol menzil hareket',
  ),
  WbArtItem(
    'fiz_yatay_atis',
    'Yatay atış',
    240,
    180,
    _horizontalThrow,
    tags: 'yatay atış parabol hareket',
  ),
  WbArtItem(
    'fiz_serbest_dusme',
    'Serbest düşme',
    240,
    180,
    _freeFall,
    tags: 'serbest düşme yerçekimi ivme',
  ),
  WbArtItem(
    'fiz_dairesel',
    'Düzgün dairesel hareket',
    240,
    180,
    _circularMotion,
    tags: 'dairesel hareket merkezcil ivme çizgisel hız',
  ),
  WbArtItem(
    'fiz_sarkac',
    'Basit sarkaç',
    240,
    180,
    _pendulum,
    tags: 'sarkaç periyot salınım',
  ),
  WbArtItem(
    'fiz_yay_kutle',
    'Yay-kütle sistemi',
    240,
    180,
    _springMass,
    tags: 'yay kütle salınım hooke esneklik',
  ),
  WbArtItem(
    'fiz_newton_besigi',
    'Newton beşiği',
    240,
    180,
    _newtonCradle,
    tags: 'newton beşiği momentum enerji çarpışma',
  ),
  WbArtItem(
    'fiz_tork_denge',
    'Tork ve denge (çubuk-terazi)',
    240,
    180,
    _torqueBalance,
    tags: 'tork denge moment terazi çubuk',
  ),
  WbArtItem(
    'fiz_kutle_cekim',
    'Kütle çekim kuvveti',
    240,
    180,
    _gravity,
    tags: 'kütle çekim gravitasyon newton dünya ay',
  ),
  // Basınç ve akışkan
  WbArtItem(
    'fiz_delikli_kap',
    'Sıvı basıncı (delikli kap)',
    240,
    180,
    _perforatedCan,
    tags: 'sıvı basıncı delikli kap derinlik',
  ),
  WbArtItem(
    'fiz_birlesik_kap',
    'Birleşik kaplar',
    240,
    180,
    _communicating,
    tags: 'birleşik kaplar sıvı seviye basınç',
  ),
  WbArtItem(
    'fiz_hidrolik_pres',
    'Hidrolik pres (Pascal)',
    240,
    180,
    _hydraulicPress,
    tags: 'hidrolik pres pascal basınç',
  ),
  WbArtItem(
    'fiz_arsimet',
    'Arşimet kaldırma kuvveti',
    240,
    180,
    _archimedes,
    tags: 'arşimet kaldırma kuvveti dinamometre batan cisim',
  ),
  WbArtItem(
    'fiz_yuzme_batma',
    'Yüzen, askıda ve batan cisim',
    240,
    180,
    _floatSink,
    tags: 'yüzme batma askıda yoğunluk kaldırma',
  ),
  WbArtItem(
    'fiz_torricelli',
    'Torricelli barometresi',
    240,
    180,
    _torricelli,
    tags: 'torricelli barometre atmosfer basıncı cıva',
  ),
  WbArtItem(
    'fiz_manometre',
    'Açık uçlu manometre',
    240,
    180,
    _manometer,
    tags: 'manometre gaz basıncı açık uçlu',
  ),
  WbArtItem(
    'fiz_u_borusu',
    'U borusu (iki sıvı)',
    240,
    180,
    _uTubeOil,
    tags: 'u borusu sıvı yoğunluk yağ su',
  ),
  WbArtItem(
    'fiz_atmosfer_deney',
    'Atmosfer basıncı deneyi',
    240,
    180,
    _atmExperiment,
    tags: 'atmosfer basıncı deney bardak kart su',
  ),
  // Isı
  WbArtItem(
    'fiz_termometre',
    'Termometre',
    240,
    180,
    _thermometer,
    tags: 'termometre sıcaklık celsius',
  ),
  WbArtItem(
    'fiz_hal_degisimi',
    'Isı-sıcaklık grafiği (hal değişimi)',
    240,
    180,
    _phaseChange,
    tags: 'hal değişimi erime kaynama ısı sıcaklık grafik',
  ),
  WbArtItem(
    'fiz_isil_denge',
    'Isıl denge',
    240,
    180,
    _thermalEquilibrium,
    tags: 'ısıl denge sıcak soğuk kap karışım',
  ),
  WbArtItem(
    'fiz_genlesme',
    'Genleşme (halka-bilye)',
    240,
    180,
    _expansion,
    tags: 'genleşme halka bilye küre ısı',
  ),
  WbArtItem(
    'fiz_iletim',
    'Isı iletimi',
    240,
    180,
    _conduction,
    tags: 'ısı iletimi çubuk metal',
  ),
  WbArtItem(
    'fiz_konveksiyon',
    'Isı taşınımı (konveksiyon)',
    240,
    190,
    _convection,
    tags: 'konveksiyon taşınım ısı su',
  ),
  WbArtItem(
    'fiz_isima',
    'Isı ışıması',
    240,
    180,
    _radiation,
    tags: 'ışıma ısı güneş radyasyon',
  ),
  // Elektrik
  WbArtItem(
    'fiz_basit_devre',
    'Basit elektrik devresi',
    240,
    180,
    _simpleCircuit,
    tags: 'devre pil ampul anahtar elektrik',
  ),
  WbArtItem(
    'fiz_seri_lamba',
    'Seri bağlı lambalar',
    240,
    180,
    _seriesLamps,
    tags: 'seri bağlama lamba devre',
  ),
  WbArtItem(
    'fiz_paralel_lamba',
    'Paralel bağlı lambalar',
    240,
    180,
    _parallelLamps,
    tags: 'paralel bağlama lamba devre',
  ),
  WbArtItem(
    'fiz_devre_sembolleri',
    'Devre elemanı sembolleri',
    300,
    200,
    _circuitSymbols,
    tags:
        'devre elemanları semboller pil ampul direnç reosta anahtar ampermetre voltmetre topraklama kondansatör diyot',
  ),
  WbArtItem(
    'fiz_ohm',
    'Ohm kanunu üçgeni',
    240,
    180,
    _ohmTriangle,
    tags: 'ohm kanunu gerilim akım direnç',
  ),
  WbArtItem(
    'fiz_wheatstone',
    'Wheatstone köprüsü',
    250,
    190,
    _wheatstone,
    tags: 'wheatstone köprü direnç galvanometre',
  ),
  WbArtItem(
    'fiz_alan_arti',
    'Elektrik alanı (+ yük)',
    240,
    180,
    _fieldPlus,
    tags: 'elektrik alan çizgileri pozitif yük',
  ),
  WbArtItem(
    'fiz_alan_eksi',
    'Elektrik alanı (− yük)',
    240,
    180,
    _fieldMinus,
    tags: 'elektrik alan çizgileri negatif yük',
  ),
  WbArtItem(
    'fiz_alan_ikili',
    'Elektrik alanı (ikili yük)',
    240,
    180,
    _fieldDipole,
    tags: 'elektrik alan çizgileri dipol iki yük',
  ),
  WbArtItem(
    'fiz_alan_levha',
    'Düzgün elektrik alan (levhalar)',
    240,
    180,
    _fieldPlates,
    tags: 'düzgün elektrik alan paralel levha',
  ),
  WbArtItem(
    'fiz_yuklu_cisimler',
    'Yüklü cisimler (çekme-itme)',
    240,
    180,
    _chargedBodies,
    tags: 'yüklü cisimler coulomb çekme itme',
  ),
  WbArtItem(
    'fiz_elektroskop',
    'Elektroskop',
    240,
    180,
    _electroscope,
    tags: 'elektroskop yük yaprak',
  ),
  // Manyetizma
  WbArtItem(
    'fiz_miknatis',
    'Çubuk mıknatıs alan çizgileri',
    240,
    180,
    _barMagnet,
    tags: 'mıknatıs manyetik alan çizgileri kutup',
  ),
  WbArtItem(
    'fiz_elektromiknatis',
    'Elektromıknatıs (bobin)',
    240,
    180,
    _electromagnet,
    tags: 'elektromıknatıs bobin sarım demir',
  ),
  WbArtItem(
    'fiz_sag_el',
    'Akım taşıyan telde sağ el kuralı',
    240,
    180,
    _rightHandRule,
    tags: 'sağ el kuralı akım manyetik alan tel',
  ),
  WbArtItem(
    'fiz_transformator',
    'Transformatör',
    240,
    180,
    _transformer,
    tags: 'transformatör trafo bobin gerilim',
  ),
  WbArtItem(
    'fiz_jenerator',
    'Jeneratör',
    240,
    180,
    _generator,
    tags: 'jeneratör dinamo elektrik üretimi',
  ),
  // Optik
  WbArtItem(
    'fiz_duzlem_ayna',
    'Düzlem ayna (yansıma)',
    240,
    180,
    _planeMirror,
    tags: 'düzlem ayna yansıma normal ışın',
  ),
  WbArtItem(
    'fiz_ayna_goruntu',
    'Düzlem aynada görüntü',
    240,
    180,
    _mirrorImage,
    tags: 'düzlem ayna görüntü sanal cisim',
  ),
  WbArtItem(
    'fiz_cukur_ayna',
    'Çukur ayna',
    240,
    180,
    _concaveMirror,
    tags: 'çukur ayna odak merkez ışın',
  ),
  WbArtItem(
    'fiz_tumsek_ayna',
    'Tümsek ayna',
    240,
    180,
    _convexMirror,
    tags: 'tümsek ayna odak ışın',
  ),
  WbArtItem(
    'fiz_yakinsak_mercek',
    'Yakınsak (ince kenarlı) mercek',
    240,
    180,
    _convexLens,
    tags: 'yakınsak mercek ince kenarlı ışın görüntü',
  ),
  WbArtItem(
    'fiz_iraksak_mercek',
    'Iraksak (kalın kenarlı) mercek',
    240,
    180,
    _concaveLens,
    tags: 'ıraksak mercek kalın kenarlı ışın görüntü',
  ),
  WbArtItem(
    'fiz_kirilma',
    'Işığın kırılması (hava-su)',
    240,
    180,
    _refraction,
    tags: 'kırılma ışık hava su normal açı',
  ),
  WbArtItem(
    'fiz_prizma',
    'Prizmada ışık dağılması',
    240,
    180,
    _prism,
    tags: 'prizma ışık dağılması renkler beyaz ışık',
  ),
  WbArtItem(
    'fiz_tam_yansima',
    'Tam yansıma',
    240,
    180,
    _totalReflection,
    tags: 'tam yansıma kritik açı sınır açı',
  ),
  WbArtItem(
    'fiz_goz',
    'Göz ve mercek',
    240,
    180,
    _eyeLens,
    tags: 'göz mercek retina görme',
  ),
  WbArtItem(
    'fiz_golge',
    'Gölge ve yarı gölge',
    240,
    180,
    _shadow,
    tags: 'gölge yarı gölge ışık kaynağı',
  ),
  WbArtItem(
    'fiz_gunes_tutulmasi',
    'Güneş tutulması',
    240,
    180,
    _solarEclipse,
    tags: 'güneş tutulması ay dünya gölge',
  ),
  WbArtItem(
    'fiz_ay_tutulmasi',
    'Ay tutulması',
    240,
    180,
    _lunarEclipse,
    tags: 'ay tutulması dünya güneş gölge',
  ),
  // Dalga ve ses
  WbArtItem(
    'fiz_enine_dalga',
    'Enine dalga',
    240,
    180,
    _transverseWave,
    tags: 'enine dalga dalga boyu genlik tepe çukur',
  ),
  WbArtItem(
    'fiz_boyuna_dalga',
    'Boyuna dalga (yay)',
    240,
    180,
    _longitudinalWave,
    tags: 'boyuna dalga yay sıkışma seyrelme',
  ),
  WbArtItem(
    'fiz_ses_diyapazon',
    'Ses dalgası ve diyapazon',
    240,
    180,
    _soundFork,
    tags: 'ses dalgası diyapazon titreşim',
  ),
  WbArtItem(
    'fiz_em_spektrum',
    'Elektromanyetik spektrum',
    310,
    150,
    _emSpectrum,
    tags:
        'elektromanyetik spektrum radyo mikrodalga kızılötesi görünür morötesi x gama',
  ),
  WbArtItem(
    'fiz_doppler',
    'Doppler olayı',
    240,
    190,
    _doppler,
    tags: 'doppler frekans kaynak gözlemci',
  ),
  WbArtItem(
    'fiz_su_girisim',
    'Su dalgası girişimi',
    240,
    180,
    _waveInterference,
    tags: 'girişim su dalgası iki kaynak',
  ),
  WbArtItem(
    'fiz_yay_yansima',
    'Yaylarda dalga yansıması',
    240,
    180,
    _waveReflection,
    tags: 'yay dalga yansıma sabit uç serbest uç',
  ),
  // Modern fizik
  WbArtItem(
    'fiz_rutherford',
    'Rutherford atom modeli',
    240,
    180,
    _rutherford,
    tags: 'rutherford atom modeli çekirdek elektron',
  ),
  WbArtItem(
    'fiz_bohr',
    'Bohr atom modeli',
    240,
    180,
    _bohr,
    tags: 'bohr atom modeli yörünge foton enerji düzeyi',
  ),
  WbArtItem(
    'fiz_fotoelektrik',
    'Fotoelektrik olay',
    240,
    180,
    _photoelectric,
    tags: 'fotoelektrik olay foton elektron metal',
  ),
  WbArtItem(
    'fiz_bozunma',
    'Radyoaktif bozunma grafiği',
    240,
    180,
    _decayGraph,
    tags: 'radyoaktif bozunma yarı ömür grafik',
  ),
  WbArtItem(
    'fiz_alfa_beta_gama',
    'Alfa, beta, gama geçirgenliği',
    240,
    180,
    _radiationPenetration,
    tags: 'alfa beta gama ışın geçirgenlik radyoaktivite',
  ),
];
