import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'whiteboard_art_core.dart';

// ───────────────────────── Yardımcılar ─────────────────────────

Path _tubePath(double cx, double top, double bot, double hw) => Path()
  ..moveTo(cx - hw, top)
  ..lineTo(cx - hw, bot - hw)
  ..arcToPoint(
    Offset(cx + hw, bot - hw),
    radius: Radius.circular(hw),
    clockwise: false,
  )
  ..lineTo(cx + hw, top);

void _liq(
  Canvas c,
  WbArtPen p,
  Path path,
  double level,
  Color col, [
  double a = 0.35,
]) {
  final b = path.getBounds();
  c.save();
  c.clipPath(path);
  c.drawRect(
    Rect.fromLTRB(b.left - 2, level, b.right + 2, b.bottom + 2),
    p.fill(col, a),
  );
  c.restore();
}

void _glass(
  Canvas c,
  WbArtPen p,
  Path path, {
  Color col = WbArtColors.lightBlue,
}) {
  c.drawPath(path, p.fill(col, 0.15));
  c.drawPath(path, p.line);
}

void _flame(Canvas c, WbArtPen p, Offset b, double s) {
  final o = Path()
    ..moveTo(b.dx, b.dy)
    ..cubicTo(
      b.dx - s * 0.8,
      b.dy - s * 0.4,
      b.dx - s * 0.4,
      b.dy - s * 1.0,
      b.dx,
      b.dy - s * 1.6,
    )
    ..cubicTo(
      b.dx + s * 0.4,
      b.dy - s * 1.0,
      b.dx + s * 0.8,
      b.dy - s * 0.4,
      b.dx,
      b.dy,
    );
  c.drawPath(o, p.fill(WbArtColors.orange, 0.75));
  final i = Path()
    ..moveTo(b.dx, b.dy)
    ..cubicTo(
      b.dx - s * 0.4,
      b.dy - s * 0.2,
      b.dx - s * 0.2,
      b.dy - s * 0.5,
      b.dx,
      b.dy - s * 0.8,
    )
    ..cubicTo(
      b.dx + s * 0.2,
      b.dy - s * 0.5,
      b.dx + s * 0.4,
      b.dy - s * 0.2,
      b.dx,
      b.dy,
    );
  c.drawPath(i, p.fill(WbArtColors.yellow, 0.9));
}

void _ticks(
  Canvas c,
  WbArtPen p,
  double x,
  double y0,
  double y1,
  int n,
  double len, {
  int majorEvery = 5,
  bool right = true,
}) {
  for (int i = 0; i <= n; i++) {
    final y = y0 + (y1 - y0) * i / n;
    final l = i % majorEvery == 0 ? len : len * 0.55;
    c.drawLine(Offset(x, y), Offset(right ? x + l : x - l, y), p.thin());
  }
}

void _bubbles(Canvas c, WbArtPen p, List<Offset> pts, double r, Color col) {
  for (final o in pts) {
    c.drawCircle(o, r, p.stroke(col, 0.4));
  }
}

void _atom(
  Canvas c,
  WbArtPen p,
  Offset o,
  double r,
  Color col,
  String s, {
  double? ts,
}) {
  c.drawCircle(o, r, p.fill(col, 0.35));
  c.drawCircle(o, r, p.stroke(col, 0.6));
  p.text(c, s, o, size: ts ?? r * 0.95, bold: true);
}

void _bond(Canvas c, WbArtPen p, Offset a, Offset b, [int n = 1]) {
  final d = b - a;
  final len = d.distance;
  if (len == 0) return;
  final nrm = Offset(-d.dy / len, d.dx / len);
  for (int i = 0; i < n; i++) {
    final off = nrm * ((i - (n - 1) / 2) * 4.0);
    c.drawLine(a + off, b + off, p.line);
  }
}

void _box(
  Canvas c,
  WbArtPen p,
  Rect r,
  Color col, [
  double a = 0.2,
  double rad = 6,
]) {
  final rr = RRect.fromRectAndRadius(r, Radius.circular(rad));
  c.drawRRect(rr, p.fill(col, a));
  c.drawRRect(rr, p.line);
}

void _tilted(
  Canvas c,
  WbArtPen p,
  Offset a,
  Offset b,
  double hw,
  Color col, [
  double alpha = 0.18,
]) {
  final d = b - a;
  final l = d.distance;
  final n = Offset(-d.dy / l, d.dx / l) * hw;
  final path = WbArtPen.poly([a + n, b + n, b - n, a - n]);
  c.drawPath(path, p.fill(col, alpha));
  c.drawPath(path, p.line);
}

void _axes(
  Canvas c,
  WbArtPen p,
  Offset o,
  double w,
  double h,
  String xl,
  String yl,
) {
  p.arrow(c, o, Offset(o.dx + w, o.dy), size: 7);
  p.arrow(c, o, Offset(o.dx, o.dy - h), size: 7);
  p.text(c, xl, Offset(o.dx + w, o.dy + 10), size: 9, anchor: 'right');
  p.text(c, yl, Offset(o.dx + 4, o.dy - h - 6), size: 9, anchor: 'left');
}

void _plot(
  Canvas c,
  Paint paint,
  Rect area,
  double Function(double) f, {
  int n = 50,
}) {
  final path = Path();
  for (int i = 0; i <= n; i++) {
    final t = i / n;
    final pt = Offset(
      area.left + area.width * t,
      area.bottom - area.height * f(t),
    );
    if (i == 0) {
      path.moveTo(pt.dx, pt.dy);
    } else {
      path.lineTo(pt.dx, pt.dy);
    }
  }
  c.drawPath(path, paint);
}

void _battery(Canvas c, WbArtPen p, Offset ctr) {
  c.drawLine(
    Offset(ctr.dx - 8, ctr.dy - 12),
    Offset(ctr.dx - 8, ctr.dy + 12),
    p.line,
  );
  c.drawLine(
    Offset(ctr.dx + 8, ctr.dy - 6),
    Offset(ctr.dx + 8, ctr.dy + 6),
    p.stroke(p.color, 2),
  );
  p.text(
    c,
    '+',
    Offset(ctr.dx - 16, ctr.dy - 12),
    size: 11,
    c: WbArtColors.red,
    bold: true,
  );
  p.text(
    c,
    '–',
    Offset(ctr.dx + 16, ctr.dy - 12),
    size: 11,
    c: WbArtColors.blue,
    bold: true,
  );
}

Path _flaskPath(
  double cx,
  double top,
  double nhw,
  double neckBot,
  double base,
  double bhw,
) => Path()
  ..moveTo(cx - nhw, top)
  ..lineTo(cx - nhw, neckBot)
  ..lineTo(cx - bhw, base)
  ..lineTo(cx + bhw, base)
  ..lineTo(cx + nhw, neckBot)
  ..lineTo(cx + nhw, top);

Path _roundFlask(double cx, double top, double nhw, double cy, double r) {
  final ang = math.asin(nhw / r);
  final by = cy - r * math.cos(ang);
  return Path()
    ..moveTo(cx - nhw, top)
    ..lineTo(cx - nhw, by)
    ..arcToPoint(
      Offset(cx + nhw, by),
      radius: Radius.circular(r),
      largeArc: true,
      clockwise: false,
    )
    ..lineTo(cx + nhw, top);
}

void _stopper(Canvas c, WbArtPen p, double cx, double y, double hw) {
  final path = WbArtPen.poly([
    Offset(cx - hw - 2, y - 10),
    Offset(cx + hw + 2, y - 10),
    Offset(cx + hw - 2, y + 4),
    Offset(cx - hw + 2, y + 4),
  ]);
  c.drawPath(path, p.fill(WbArtColors.brown, 0.35));
  c.drawPath(path, p.line);
}

void _thermo(Canvas c, WbArtPen p, double cx, double top, double bot) {
  final path = _tubePath(cx, top, bot, 3);
  c.drawPath(path, p.line);
  c.drawLine(
    Offset(cx, top + 6),
    Offset(cx, bot - 3),
    p.stroke(WbArtColors.red, 1.2),
  );
  c.drawCircle(Offset(cx, bot - 3), 2.5, p.fill(WbArtColors.red));
}

void _trough(Canvas c, WbArtPen p, Rect r, double water) {
  final path = Path()
    ..moveTo(r.left, r.top)
    ..lineTo(r.left, r.bottom)
    ..lineTo(r.right, r.bottom)
    ..lineTo(r.right, r.top);
  _liq(c, p, path, water, WbArtColors.blue, 0.3);
  c.drawPath(path, p.line);
}

void _stand(
  Canvas c,
  WbArtPen p,
  double x,
  double top,
  double base,
  double footW,
) {
  c.drawLine(Offset(x, top), Offset(x, base), p.stroke(WbArtColors.gray, 1.3));
  c.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(x - 4, base, footW, 7),
      const Radius.circular(2),
    ),
    p.fill(WbArtColors.gray, 0.5),
  );
  c.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(x - 4, base, footW, 7),
      const Radius.circular(2),
    ),
    p.thin(),
  );
}

void _clamp(Canvas c, WbArtPen p, Offset from, Offset to) {
  c.drawLine(from, to, p.stroke(WbArtColors.gray, 1.2));
  c.drawCircle(to, 3, p.fill(WbArtColors.gray, 0.7));
}

void _wave(Canvas c, WbArtPen p, Offset s, double h, Color col) {
  final path = Path()..moveTo(s.dx, s.dy);
  for (int i = 1; i <= 3; i++) {
    path.quadraticBezierTo(
      s.dx + (i.isOdd ? 5 : -5),
      s.dy - h * (i - 0.5) / 3,
      s.dx,
      s.dy - h * i / 3,
    );
  }
  c.drawPath(path, p.stroke(col, 0.5));
}

// ───────────────────────── Şekil kütüphanesi ─────────────────────────

final List<WbArtItem> _chemLab = [
  // ===================== LABORATUVAR MALZEMELERİ =====================
  WbArtItem(
    'kim_deney_tupu',
    'Deney tüpü',
    200,
    240,
    (c, p) {
      final t = _tubePath(100, 40, 210, 24);
      _glass(c, p, t);
      _liq(c, p, t, 120, WbArtColors.teal, 0.35);
      c.drawLine(const Offset(74, 40), const Offset(126, 40), p.line);
      c.drawLine(const Offset(76, 120), const Offset(124, 120), p.thin());
      _bubbles(
        c,
        p,
        const [Offset(95, 160), Offset(106, 145), Offset(100, 175)],
        3,
        WbArtColors.teal,
      );
      p.text(c, 'Deney tüpü', const Offset(100, 228), size: 11, bold: true);
    },
    tags: 'deney tüpü tup laboratuvar cam malzeme',
  ),
  WbArtItem(
    'kim_tup_standi',
    'Deney tüpü standı',
    220,
    220,
    (c, p) {
      final cols = [WbArtColors.red, WbArtColors.blue, WbArtColors.green];
      for (int i = 0; i < 3; i++) {
        final cx = 55.0 + i * 55;
        final t = _tubePath(cx, 45, 150, 16);
        _glass(c, p, t);
        _liq(c, p, t, 95 + i * 12, cols[i], 0.4);
      }
      _box(
        c,
        p,
        const Rect.fromLTWH(20, 80, 180, 10),
        WbArtColors.brown,
        0.35,
        2,
      );
      c.drawLine(const Offset(30, 90), const Offset(30, 190), p.line);
      c.drawLine(const Offset(190, 90), const Offset(190, 190), p.line);
      _box(
        c,
        p,
        const Rect.fromLTWH(20, 185, 180, 10),
        WbArtColors.brown,
        0.35,
        2,
      );
      p.text(
        c,
        'Deney tüpü standı',
        const Offset(110, 212),
        size: 11,
        bold: true,
      );
    },
    tags: 'tüp stand sehpa deney tüpü standı',
  ),
  WbArtItem(
    'kim_erlenmayer',
    'Erlenmayer',
    200,
    240,
    (c, p) {
      final f = _flaskPath(100, 40, 20, 100, 205, 62);
      _glass(c, p, f);
      _liq(c, p, f, 150, WbArtColors.orange, 0.35);
      c.drawLine(const Offset(76, 40), const Offset(124, 40), p.line);
      for (int i = 0; i < 3; i++) {
        c.drawLine(
          Offset(78 - i * 3.0, 160 + i * 10),
          Offset(92 - i * 3.0, 160 + i * 10),
          p.thin(),
        );
      }
      p.text(c, 'Erlenmayer', const Offset(100, 226), size: 11, bold: true);
    },
    tags: 'erlen erlenmeyer erlenmayer conical flask',
  ),
  WbArtItem('kim_beher', 'Beher (ölçekli)', 200, 240, (c, p) {
    final b = WbArtPen.poly(const [
      Offset(48, 36),
      Offset(55, 44),
      Offset(55, 200),
      Offset(145, 200),
      Offset(145, 44),
      Offset(152, 36),
    ], close: false);
    _glass(c, p, b);
    _liq(c, p, b, 110, WbArtColors.blue, 0.3);
    for (int i = 0; i <= 8; i++) {
      final y = 70.0 + i * 16;
      c.drawLine(Offset(55, y), Offset(i.isEven ? 80 : 68, y), p.thin());
      if (i.isEven)
        p.text(c, '${200 - i * 25}', Offset(86, y), size: 8, anchor: 'left');
    }
    p.text(c, 'mL', const Offset(120, 50), size: 9);
    p.text(c, 'Beher', const Offset(100, 226), size: 11, bold: true);
  }, tags: 'beher ölçekli cam kap'),
  WbArtItem('kim_balon_joje', 'Balon joje', 200, 240, (c, p) {
    final f = _roundFlask(100, 30, 11, 170, 52);
    _glass(c, p, f);
    _liq(c, p, f, 150, WbArtColors.purple, 0.3);
    c.drawLine(const Offset(86, 80), const Offset(114, 80), p.line);
    p.text(c, '100 mL', const Offset(124, 80), size: 9, anchor: 'left');
    p.text(c, 'Ayar çizgisi', const Offset(124, 66), size: 8, anchor: 'left');
    p.text(c, 'Balon joje', const Offset(100, 232), size: 11, bold: true);
  }, tags: 'balon joje hacimli ölçü'),
  WbArtItem('kim_mezur', 'Mezür', 200, 240, (c, p) {
    final t = Path()
      ..moveTo(78, 30)
      ..lineTo(78, 195)
      ..lineTo(122, 195)
      ..lineTo(122, 30);
    _glass(c, p, t);
    _liq(c, p, t, 105, WbArtColors.green, 0.35);
    c.drawPath(
      WbArtPen.poly(const [
        Offset(60, 212),
        Offset(70, 195),
        Offset(130, 195),
        Offset(140, 212),
      ]),
      p.fill(WbArtColors.gray, 0.3),
    );
    c.drawLine(const Offset(58, 212), const Offset(142, 212), p.line);
    _ticks(c, p, 78, 45, 190, 20, 16, majorEvery: 5);
    p.text(c, 'Mezür', const Offset(100, 228), size: 11, bold: true);
    p.text(c, 'mL', const Offset(100, 20), size: 9);
  }, tags: 'mezür dereceli silindir ölçü hacim'),
  WbArtItem(
    'kim_spirit_lambasi',
    'Spirit lambası',
    200,
    240,
    (c, p) {
      final body = Path()
        ..moveTo(85, 120)
        ..cubicTo(40, 150, 40, 210, 100, 210)
        ..cubicTo(160, 210, 160, 150, 115, 120)
        ..close();
      _glass(c, p, body, col: WbArtColors.yellow);
      _liq(c, p, body, 165, WbArtColors.yellow, 0.4);
      c.drawRect(
        const Rect.fromLTWH(88, 105, 24, 15),
        p.fill(WbArtColors.gray, 0.5),
      );
      c.drawRect(const Rect.fromLTWH(88, 105, 24, 15), p.line);
      c.drawLine(
        const Offset(100, 105),
        const Offset(100, 92),
        p.stroke(WbArtColors.brown, 1.2),
      );
      _flame(c, p, const Offset(100, 92), 22);
      p.text(c, 'Spirit lambası', const Offset(100, 228), size: 11, bold: true);
      p.text(c, 'Fitil', const Offset(122, 95), size: 8, anchor: 'left');
      p.text(c, 'Alkol', const Offset(100, 185), size: 9);
    },
    tags: 'spirit lambası alkol ısıtma alev',
  ),
  WbArtItem('kim_bunsen_bek', 'Bunsen bek', 200, 240, (c, p) {
    c.drawRect(
      const Rect.fromLTWH(90, 90, 20, 100),
      p.fill(WbArtColors.gray, 0.25),
    );
    c.drawRect(const Rect.fromLTWH(90, 90, 20, 100), p.line);
    c.drawRect(
      const Rect.fromLTWH(86, 150, 28, 18),
      p.fill(WbArtColors.gray, 0.5),
    );
    c.drawRect(const Rect.fromLTWH(86, 150, 28, 18), p.thin());
    c.drawPath(
      WbArtPen.poly(const [
        Offset(55, 205),
        Offset(145, 205),
        Offset(130, 190),
        Offset(70, 190),
      ]),
      p.fill(WbArtColors.gray, 0.4),
    );
    c.drawPath(
      WbArtPen.poly(const [
        Offset(55, 205),
        Offset(145, 205),
        Offset(130, 190),
        Offset(70, 190),
      ]),
      p.line,
    );
    c.drawLine(const Offset(110, 195), const Offset(160, 195), p.line);
    p.text(c, 'Gaz girişi', const Offset(160, 183), size: 8, anchor: 'left');
    _flame(c, p, const Offset(100, 90), 20);
    p.text(
      c,
      'Hava ayar halkası',
      const Offset(120, 159),
      size: 8,
      anchor: 'left',
    );
    p.text(c, 'Bunsen bek', const Offset(100, 226), size: 11, bold: true);
  }, tags: 'bunsen bek gaz ocağı alev ısıtıcı'),
  WbArtItem('kim_damlalik', 'Damlalık', 200, 240, (c, p) {
    final bulb = Path()
      ..moveTo(88, 90)
      ..cubicTo(88, 40, 112, 40, 112, 90)
      ..close();
    c.drawPath(bulb, p.fill(WbArtColors.red, 0.4));
    c.drawPath(bulb, p.line);
    final tube = Path()
      ..moveTo(90, 90)
      ..lineTo(90, 150)
      ..lineTo(100, 190)
      ..lineTo(110, 150)
      ..lineTo(110, 90)
      ..close();
    _glass(c, p, tube);
    _liq(c, p, tube, 130, WbArtColors.blue, 0.4);
    c.drawCircle(const Offset(100, 208), 4, p.fill(WbArtColors.blue, 0.6));
    p.text(c, 'Lastik başlık', const Offset(122, 60), size: 8, anchor: 'left');
    p.text(c, 'Damlalık', const Offset(100, 232), size: 11, bold: true);
  }, tags: 'damlalık pipet damla'),
  WbArtItem('kim_buret', 'Büret', 200, 240, (c, p) {
    final t = Path()
      ..moveTo(92, 15)
      ..lineTo(92, 190)
      ..lineTo(108, 190)
      ..lineTo(108, 15);
    _glass(c, p, t);
    _liq(c, p, t, 70, WbArtColors.purple, 0.3);
    _ticks(c, p, 92, 25, 180, 31, 13, majorEvery: 5, right: false);
    c.drawLine(const Offset(80, 200), const Offset(120, 200), p.line);
    c.drawLine(const Offset(100, 190), const Offset(100, 210), p.line);
    c.drawPath(
      WbArtPen.poly(const [
        Offset(100, 210),
        Offset(96, 224),
        Offset(104, 224),
      ]),
      p.line,
    );
    c.drawCircle(const Offset(100, 232), 2.5, p.fill(WbArtColors.purple, 0.7));
    p.text(c, 'Musluk', const Offset(124, 200), size: 8, anchor: 'left');
    p.text(
      c,
      'Büret',
      const Offset(135, 100),
      size: 11,
      bold: true,
      anchor: 'left',
    );
    p.text(c, '0 mL', const Offset(56, 25), size: 8, anchor: 'right');
    p.text(c, '50 mL', const Offset(56, 180), size: 8, anchor: 'right');
  }, tags: 'büret titrasyon musluk'),
  WbArtItem('kim_pipet', 'Balonlu pipet', 200, 240, (c, p) {
    final path = Path()
      ..moveTo(95, 15)
      ..lineTo(95, 90)
      ..cubicTo(60, 100, 60, 150, 95, 160)
      ..lineTo(95, 220)
      ..lineTo(100, 232)
      ..lineTo(105, 220)
      ..lineTo(105, 160)
      ..cubicTo(140, 150, 140, 100, 105, 90)
      ..lineTo(105, 15);
    _glass(c, p, path);
    _liq(c, p, path, 120, WbArtColors.teal, 0.3);
    c.drawLine(const Offset(90, 60), const Offset(110, 60), p.line);
    p.text(c, 'Ayar çizgisi', const Offset(115, 60), size: 8, anchor: 'left');
    p.text(
      c,
      'Pipet',
      const Offset(150, 125),
      size: 11,
      bold: true,
      anchor: 'left',
    );
  }, tags: 'pipet balonlu pipet hacim çekme'),
  WbArtItem(
    'kim_ayirma_hunisi',
    'Ayırma hunisi',
    200,
    240,
    (c, p) {
      _sepFunnel(c, p, 100, 30);
      p.text(c, 'Ayırma hunisi', const Offset(100, 230), size: 11, bold: true);
    },
    tags: 'ayırma hunisi karışmayan sıvı musluk',
  ),
  WbArtItem(
    'kim_huni_suzgec',
    'Huni ve süzgeç kâğıdı',
    200,
    240,
    (c, p) {
      final h = WbArtPen.poly(const [
        Offset(45, 55),
        Offset(155, 55),
        Offset(108, 140),
        Offset(108, 205),
        Offset(92, 205),
        Offset(92, 140),
      ]);
      _glass(c, p, h);
      final kagit = WbArtPen.poly(const [
        Offset(55, 62),
        Offset(145, 62),
        Offset(100, 138),
      ]);
      c.drawPath(kagit, p.fill(WbArtColors.yellow, 0.35));
      c.drawPath(kagit, p.stroke(WbArtColors.brown, 0.6));
      c.drawLine(const Offset(100, 62), const Offset(100, 138), p.thin(0.3));
      p.text(
        c,
        'Süzgeç kâğıdı',
        const Offset(160, 90),
        size: 8,
        anchor: 'left',
      );
      p.text(
        c,
        'Huni',
        const Offset(30, 90),
        size: 10,
        anchor: 'right',
        bold: true,
      );
      p.text(
        c,
        'Huni + süzgeç kâğıdı',
        const Offset(100, 226),
        size: 10,
        bold: true,
      );
    },
    tags: 'huni süzgeç kağıdı süzme filtre',
  ),
  WbArtItem('kim_porselen_kroze', 'Porselen kroze', 200, 240, (c, p) {
    final k = Path()
      ..moveTo(60, 90)
      ..lineTo(72, 170)
      ..quadraticBezierTo(100, 185, 128, 170)
      ..lineTo(140, 90)
      ..close();
    c.drawPath(k, p.fill(WbArtColors.gray, 0.2));
    c.drawPath(k, p.line);
    c.drawOval(const Rect.fromLTWH(60, 84, 80, 12), p.thin());
    final kapak = Path()
      ..moveTo(56, 80)
      ..quadraticBezierTo(100, 60, 144, 80)
      ..close();
    c.drawPath(kapak, p.fill(WbArtColors.gray, 0.3));
    c.drawPath(kapak, p.line);
    c.drawCircle(const Offset(100, 68), 3, p.fill(WbArtColors.gray, 0.6));
    p.text(c, 'Kapak', const Offset(150, 65), size: 8, anchor: 'left');
    p.text(c, 'Porselen kroze', const Offset(100, 226), size: 11, bold: true);
  }, tags: 'kroze porselen kroze yakma'),
  WbArtItem(
    'kim_evaporasyon_kabi',
    'Evaporasyon kabı',
    200,
    240,
    (c, p) {
      final k = Path()
        ..moveTo(40, 110)
        ..quadraticBezierTo(100, 230, 160, 110)
        ..close();
      c.drawPath(k, p.fill(WbArtColors.gray, 0.2));
      c.drawPath(k, p.line);
      _liq(c, p, k, 140, WbArtColors.blue, 0.3);
      c.drawLine(const Offset(160, 110), const Offset(172, 106), p.line);
      p.text(
        c,
        'Evaporasyon kabı',
        const Offset(100, 226),
        size: 11,
        bold: true,
      );
      p.text(c, 'Çözelti', const Offset(100, 155), size: 9);
    },
    tags: 'evaporasyon kabı buharlaştırma porselen kap',
  ),
  WbArtItem(
    'kim_vakum_suzme',
    'Çektirme balonu (vakum süzme)',
    200,
    240,
    (c, p) {
      final f = _flaskPath(100, 100, 18, 130, 215, 55);
      _glass(c, p, f);
      c.drawLine(const Offset(115, 135), const Offset(165, 125), p.line);
      c.drawLine(const Offset(115, 143), const Offset(168, 133), p.line);
      p.text(
        c,
        'Vakum pompasına',
        const Offset(100, 112),
        size: 8,
        anchor: 'left',
        c: WbArtColors.gray,
      );
      final b = WbArtPen.poly(const [
        Offset(62, 62),
        Offset(138, 62),
        Offset(138, 80),
        Offset(110, 100),
        Offset(90, 100),
        Offset(62, 80),
      ]);
      _glass(c, p, b, col: WbArtColors.gray);
      c.drawLine(
        const Offset(72, 80),
        const Offset(128, 80),
        p.stroke(WbArtColors.yellow, 1.5),
      );
      _liq(c, p, f, 190, WbArtColors.teal, 0.35);
      p.text(c, 'Büchner hunisi', const Offset(100, 50), size: 9);
      p.text(
        c,
        'Çektirme balonu',
        const Offset(100, 232),
        size: 11,
        bold: true,
      );
    },
    tags: 'çektirme balon kitasat vakum büchner süzme',
  ),
  WbArtItem('kim_termometre', 'Termometre', 200, 240, (c, p) {
    _thermo(c, p, 100, 20, 200);
    final t = _tubePath(100, 20, 205, 7);
    c.drawPath(t, p.line);
    c.drawCircle(const Offset(100, 198), 8, p.fill(WbArtColors.red, 0.8));
    c.drawLine(
      const Offset(100, 190),
      const Offset(100, 70),
      p.stroke(WbArtColors.red, 1.5),
    );
    _ticks(c, p, 110, 30, 180, 15, 12, majorEvery: 5);
    p.text(c, '100°C', const Offset(128, 30), size: 8, anchor: 'left');
    p.text(c, '50°C', const Offset(128, 105), size: 8, anchor: 'left');
    p.text(c, '0°C', const Offset(128, 180), size: 8, anchor: 'left');
    p.text(c, 'Termometre', const Offset(100, 230), size: 11, bold: true);
  }, tags: 'termometre sıcaklık ölçme derece'),
  WbArtItem(
    'kim_ucayak',
    'Üçayak ve amyant tel',
    200,
    240,
    (c, p) {
      c.drawLine(
        const Offset(60, 105),
        const Offset(40, 205),
        p.stroke(WbArtColors.gray, 1.4),
      );
      c.drawLine(
        const Offset(140, 105),
        const Offset(160, 205),
        p.stroke(WbArtColors.gray, 1.4),
      );
      c.drawLine(
        const Offset(100, 105),
        const Offset(100, 205),
        p.stroke(WbArtColors.gray, 1.0),
      );
      c.drawOval(
        const Rect.fromLTWH(55, 98, 90, 14),
        p.stroke(WbArtColors.gray, 1.4),
      );
      c.drawRect(
        const Rect.fromLTWH(62, 92, 76, 8),
        p.fill(WbArtColors.yellow, 0.3),
      );
      c.drawRect(const Rect.fromLTWH(62, 92, 76, 8), p.thin());
      c.drawLine(const Offset(70, 96), const Offset(130, 96), p.dashedHelper());
      _flame(c, p, const Offset(100, 200), 16);
      p.text(c, 'Amyant tel', const Offset(150, 80), size: 9, anchor: 'left');
      p.text(
        c,
        'Üçayak',
        const Offset(165, 150),
        size: 10,
        anchor: 'left',
        bold: true,
      );
      p.text(
        c,
        'Üçayak + amyant tel',
        const Offset(100, 228),
        size: 10,
        bold: true,
      );
    },
    tags: 'üçayak tripod amyant tel ısıtma',
  ),
  WbArtItem(
    'kim_gaz_toplama',
    'Gaz toplama (suyun üstünde)',
    260,
    220,
    (c, p) {
      _trough(c, p, const Rect.fromLTWH(60, 130, 160, 70), 150);
      final tube = _tubePath(150, 70, 170, 22);
      c.save();
      c.clipRect(const Rect.fromLTWH(0, 0, 300, 400));
      c.drawPath(tube, p.fill(WbArtColors.lightBlue, 0.12));
      c.restore();
      c.drawPath(tube, p.line);
      _liq(c, p, tube, 105, WbArtColors.blue, 0.3);
      p.text(c, 'Gaz', const Offset(150, 88), size: 10, bold: true);
      final d = Path()
        ..moveTo(20, 60)
        ..lineTo(80, 60)
        ..lineTo(80, 190)
        ..lineTo(145, 190)
        ..lineTo(145, 175);
      c.drawPath(d, p.stroke(WbArtColors.gray, 1.2));
      _bubbles(
        c,
        p,
        const [Offset(145, 165), Offset(152, 150), Offset(147, 135)],
        3,
        WbArtColors.blue,
      );
      p.text(
        c,
        'Gaz çıkış borusu',
        const Offset(20, 48),
        size: 8,
        anchor: 'left',
      );
      p.text(c, 'Su', const Offset(200, 160), size: 10, c: WbArtColors.blue);
      p.text(
        c,
        'Suyun üstünde gaz toplama',
        const Offset(130, 212),
        size: 10,
        bold: true,
      );
    },
    tags: 'gaz toplama suyun üstünde pnömatik küvet',
  ),
  WbArtItem('kim_saat_cami', 'Saat camı', 200, 240, (c, p) {
    final s = Path()
      ..moveTo(30, 120)
      ..quadraticBezierTo(100, 175, 170, 120);
    c.drawPath(s, p.line);
    c.drawOval(const Rect.fromLTWH(30, 110, 140, 20), p.thin());
    c.drawCircle(const Offset(80, 128), 3, p.fill(WbArtColors.gray, 0.8));
    c.drawCircle(const Offset(100, 134), 3, p.fill(WbArtColors.gray, 0.8));
    c.drawCircle(const Offset(118, 128), 3, p.fill(WbArtColors.gray, 0.8));
    p.text(c, 'Katı madde', const Offset(100, 100), size: 9);
    p.text(c, 'Saat camı', const Offset(100, 200), size: 11, bold: true);
  }, tags: 'saat camı cam tartım'),
  WbArtItem('kim_desikator', 'Desikatör', 200, 240, (c, p) {
    final alt = Path()
      ..moveTo(40, 130)
      ..lineTo(35, 205)
      ..quadraticBezierTo(100, 220, 165, 205)
      ..lineTo(160, 130)
      ..close();
    _glass(c, p, alt);
    final ust = Path()
      ..moveTo(38, 128)
      ..cubicTo(38, 40, 162, 40, 162, 128)
      ..close();
    _glass(c, p, ust);
    c.drawCircle(const Offset(100, 62), 4, p.fill(WbArtColors.gray, 0.6));
    c.drawLine(const Offset(50, 150), const Offset(150, 150), p.line);
    c.drawRect(
      const Rect.fromLTWH(75, 125, 50, 25),
      p.fill(WbArtColors.gray, 0.3),
    );
    p.text(c, 'Kroze', const Offset(100, 138), size: 8);
    p.text(c, 'Kurutucu madde', const Offset(100, 180), size: 9);
    p.text(c, 'Desikatör', const Offset(100, 232), size: 11, bold: true);
  }, tags: 'desikatör nem çekici kurutma'),
  WbArtItem(
    'kim_geri_sogutucu',
    'Cam balon ve geri soğutucu',
    200,
    240,
    (c, p) {
      final f = _roundFlask(100, 110, 14, 175, 45);
      _glass(c, p, f);
      _liq(c, p, f, 170, WbArtColors.orange, 0.35);
      final jacket = Rect.fromLTRB(84, 15, 116, 110);
      c.drawRect(jacket, p.fill(WbArtColors.lightBlue, 0.2));
      c.drawRect(jacket, p.line);
      c.drawLine(const Offset(100, 10), const Offset(100, 110), p.thin());
      p.arrow(
        c,
        const Offset(55, 95),
        const Offset(84, 95),
        c: WbArtColors.blue,
        size: 6,
      );
      p.arrow(
        c,
        const Offset(84, 30),
        const Offset(55, 30),
        c: WbArtColors.blue,
        size: 6,
      );
      p.text(c, 'Su girişi', const Offset(52, 95), size: 8, anchor: 'right');
      p.text(c, 'Su çıkışı', const Offset(52, 30), size: 8, anchor: 'right');
      _flame(c, p, const Offset(100, 232), 14);
      p.text(
        c,
        'Geri soğutucu',
        const Offset(124, 60),
        size: 9,
        anchor: 'left',
      );
    },
    tags: 'geri soğutucu reflux cam balon yuvarlak dipli',
  ),
];

// ───────────────────────── Düzenekler ─────────────────────────

void _sepFunnel(Canvas c, WbArtPen p, double cx, double top) {
  final f = Path()
    ..moveTo(cx - 8, top + 10)
    ..cubicTo(cx - 60, top + 40, cx - 55, top + 110, cx - 6, top + 135)
    ..lineTo(cx - 6, top + 150)
    ..lineTo(cx + 6, top + 150)
    ..lineTo(cx + 6, top + 135)
    ..cubicTo(cx + 55, top + 110, cx + 60, top + 40, cx + 8, top + 10)
    ..close();
  _glass(c, p, f);
  _liq(c, p, f, top + 95, WbArtColors.orange, 0.3);
  _liq(c, p, f, top + 60, WbArtColors.blue, 0.0);
  c.save();
  c.clipPath(f);
  c.drawRect(
    Rect.fromLTRB(cx - 70, top + 70, cx + 70, top + 95),
    p.fill(WbArtColors.blue, 0.35),
  );
  c.restore();
  c.drawLine(
    Offset(cx - 60, top + 70),
    Offset(cx + 60, top + 70),
    p.dashedHelperPaint(),
  );
  _stopper(c, p, cx, top + 6, 8);
  c.drawLine(
    Offset(cx - 14, top + 143),
    Offset(cx + 14, top + 143),
    p.stroke(WbArtColors.gray, 1.5),
  );
  c.drawLine(
    Offset(cx + 14, top + 143),
    Offset(cx + 22, top + 140),
    p.stroke(WbArtColors.gray, 1.5),
  );
  p.text(
    c,
    'Yoğunluğu küçük sıvı',
    Offset(cx + 54, top + 50),
    size: 8,
    anchor: 'left',
  );
  p.text(
    c,
    'Yoğunluğu büyük sıvı',
    Offset(cx + 54, top + 85),
    size: 8,
    anchor: 'left',
  );
  p.text(c, 'Musluk', Offset(cx + 26, top + 143), size: 8, anchor: 'left');
}

void _distill(Canvas c, WbArtPen p, bool fractional) {
  final f = _roundFlask(60, 110, 11, 160, 34);
  _glass(c, p, f);
  _liq(c, p, f, 150, WbArtColors.blue, 0.3);
  _flame(c, p, const Offset(60, 214), 14);
  c.drawLine(
    const Offset(40, 198),
    const Offset(80, 198),
    p.stroke(WbArtColors.gray, 1.2),
  );
  double armY = 100;
  if (fractional) {
    final col = Rect.fromLTRB(52, 40, 68, 112);
    c.drawRect(col, p.fill(WbArtColors.lightBlue, 0.12));
    c.drawRect(col, p.line);
    for (int i = 0; i < 6; i++) {
      c.drawCircle(Offset(60, 52.0 + i * 11), 2.5, p.thin());
    }
    _stopper(c, p, 60, 36, 8);
    _thermo(c, p, 60, 10, 44);
    armY = 45;
    p.text(
      c,
      'Ayrımsal damıtma kolonu',
      const Offset(20, 24),
      size: 8,
      anchor: 'left',
    );
  } else {
    _stopper(c, p, 60, 102, 11);
    _thermo(c, p, 60, 55, 140);
    p.text(c, 'Termometre', const Offset(20, 48), size: 8, anchor: 'left');
  }
  final a = Offset(68, armY);
  final b = Offset(100, armY - 2);
  c.drawLine(a, b, p.line);
  c.drawLine(b, const Offset(112, 94), p.line);
  _tilted(
    c,
    p,
    const Offset(105, 95),
    const Offset(225, 155),
    11,
    WbArtColors.lightBlue,
    0.25,
  );
  c.drawLine(const Offset(105, 95), const Offset(225, 155), p.thin());
  p.arrow(
    c,
    const Offset(150, 190),
    const Offset(176, 166),
    c: WbArtColors.blue,
    size: 6,
  );
  p.text(c, 'Su girişi', const Offset(150, 198), size: 8, anchor: 'top');
  p.arrow(
    c,
    const Offset(150, 72),
    const Offset(124, 94),
    c: WbArtColors.blue,
    size: 6,
    line: false,
  );
  p.text(c, 'Su çıkışı', const Offset(150, 66), size: 8);
  p.text(
    c,
    'Liebig soğutucusu',
    const Offset(190, 110),
    size: 8,
    anchor: 'left',
  );
  final r = _flaskPath(240, 170, 8, 185, 215, 24);
  _glass(c, p, r);
  _liq(c, p, r, 205, WbArtColors.teal, 0.4);
  c.drawCircle(const Offset(232, 160), 2, p.fill(WbArtColors.teal));
  p.text(c, 'Damıtık', const Offset(262, 205), size: 8, anchor: 'left');
}

final List<WbArtItem> _chemSetups = [
  WbArtItem(
    'kim_basit_damitma',
    'Basit damıtma düzeneği',
    300,
    240,
    (c, p) {
      _distill(c, p, false);
      p.text(c, 'Basit damıtma', const Offset(150, 232), size: 11, bold: true);
    },
    tags: 'basit damıtma düzenek liebig soğutucu ayırma',
  ),
  WbArtItem(
    'kim_ayrimsal_damitma',
    'Ayrımsal damıtma düzeneği',
    300,
    240,
    (c, p) {
      _distill(c, p, true);
      p.text(
        c,
        'Ayrımsal damıtma',
        const Offset(150, 232),
        size: 11,
        bold: true,
      );
    },
    tags: 'ayrımsal damıtma düzenek kolon petrol',
  ),
  WbArtItem(
    'kim_suzme_duzenegi',
    'Süzme düzeneği',
    240,
    250,
    (c, p) {
      final e = _flaskPath(120, 150, 14, 175, 235, 45);
      _glass(c, p, e);
      _liq(c, p, e, 225, WbArtColors.blue, 0.3);
      final h = WbArtPen.poly(const [
        Offset(75, 100),
        Offset(165, 100),
        Offset(127, 160),
        Offset(127, 178),
        Offset(113, 178),
        Offset(113, 160),
      ]);
      _glass(c, p, h);
      final k = WbArtPen.poly(const [
        Offset(82, 106),
        Offset(158, 106),
        Offset(120, 158),
      ]);
      c.drawPath(k, p.fill(WbArtColors.yellow, 0.35));
      c.drawPath(k, p.stroke(WbArtColors.brown, 0.6));
      c.drawLine(
        const Offset(150, 20),
        const Offset(120, 100),
        p.stroke(WbArtColors.brown, 1.8),
      );
      c.save();
      c.translate(185, 40);
      c.rotate(0.7);
      final b = WbArtPen.poly(const [
        Offset(-22, -30),
        Offset(-18, -25),
        Offset(-18, 25),
        Offset(18, 25),
        Offset(18, -25),
        Offset(22, -30),
      ], close: false);
      _glass(c, p, b);
      c.restore();
      c.drawLine(
        const Offset(165, 62),
        const Offset(142, 90),
        p.stroke(WbArtColors.blue, 1.5),
      );
      p.text(c, 'Cam çubuk', const Offset(60, 40), size: 9, anchor: 'left');
      p.text(
        c,
        'Süzgeç kâğıdı',
        const Offset(60, 130),
        size: 8,
        anchor: 'right',
      );
      p.text(
        c,
        'Artık (kalıntı)',
        const Offset(178, 135),
        size: 8,
        anchor: 'left',
        c: WbArtColors.brown,
      );
      p.text(c, 'Süzüntü', const Offset(175, 215), size: 9, anchor: 'left');
      p.text(c, 'Süzme', const Offset(120, 246), size: 11, bold: true);
    },
    tags: 'süzme düzenek huni süzgeç kağıdı karışım ayırma',
  ),
  WbArtItem(
    'kim_buharlastirma',
    'Buharlaştırma düzeneği',
    240,
    240,
    (c, p) {
      final k = Path()
        ..moveTo(55, 100)
        ..quadraticBezierTo(120, 175, 185, 100)
        ..close();
      c.drawPath(k, p.fill(WbArtColors.gray, 0.2));
      c.drawPath(k, p.line);
      _liq(c, p, k, 125, WbArtColors.blue, 0.3);
      for (int i = 0; i < 3; i++) {
        _wave(c, p, Offset(95 + i * 25.0, 88), 40, WbArtColors.gray);
      }
      c.drawLine(
        const Offset(75, 150),
        const Offset(55, 215),
        p.stroke(WbArtColors.gray, 1.4),
      );
      c.drawLine(
        const Offset(165, 150),
        const Offset(185, 215),
        p.stroke(WbArtColors.gray, 1.4),
      );
      c.drawLine(
        const Offset(70, 148),
        const Offset(170, 148),
        p.stroke(WbArtColors.gray, 1.4),
      );
      _flame(c, p, const Offset(120, 215), 18);
      p.text(c, 'Su buharı', const Offset(150, 55), size: 9, anchor: 'left');
      p.text(c, 'Tuzlu su', const Offset(120, 120), size: 9);
      p.text(
        c,
        'Evaporasyon kabı',
        const Offset(20, 100),
        size: 8,
        anchor: 'left',
      );
      p.text(
        c,
        'Buharlaştırma ile tuz eldesi',
        const Offset(120, 234),
        size: 10,
        bold: true,
      );
    },
    tags: 'buharlaştırma tuz eldesi evaporasyon düzenek',
  ),
  WbArtItem(
    'kim_kromatografi',
    'Kâğıt kromatografisi',
    200,
    240,
    (c, p) {
      final b = WbArtPen.poly(const [
        Offset(40, 90),
        Offset(45, 100),
        Offset(45, 205),
        Offset(155, 205),
        Offset(155, 100),
        Offset(160, 90),
      ], close: false);
      _glass(c, p, b);
      _liq(c, p, b, 190, WbArtColors.blue, 0.3);
      c.drawRect(
        const Rect.fromLTRB(80, 25, 120, 200),
        p.fill(WbArtColors.yellow, 0.2),
      );
      c.drawRect(
        const Rect.fromLTRB(80, 25, 120, 200),
        p.stroke(WbArtColors.brown, 0.6),
      );
      c.drawLine(const Offset(80, 175), const Offset(120, 175), p.thin());
      c.drawLine(
        const Offset(80, 45),
        const Offset(120, 45),
        p.dashedHelperPaint(),
      );
      c.drawCircle(const Offset(90, 175), 3, p.fill(WbArtColors.red, 0.7));
      c.drawCircle(const Offset(100, 175), 3, p.fill(WbArtColors.red, 0.7));
      c.drawCircle(const Offset(110, 175), 3, p.fill(WbArtColors.red, 0.7));
      c.drawOval(
        Rect.fromCenter(center: const Offset(90, 140), width: 9, height: 7),
        p.fill(WbArtColors.red, 0.7),
      );
      c.drawOval(
        Rect.fromCenter(center: const Offset(100, 105), width: 10, height: 12),
        p.fill(WbArtColors.blue, 0.7),
      );
      c.drawOval(
        Rect.fromCenter(center: const Offset(110, 70), width: 10, height: 12),
        p.fill(WbArtColors.green, 0.7),
      );
      p.text(c, 'Çözücü önü', const Offset(125, 45), size: 8, anchor: 'left');
      p.text(
        c,
        'Başlangıç çizgisi',
        const Offset(125, 175),
        size: 8,
        anchor: 'left',
      );
      p.text(c, 'Çözücü', const Offset(100, 198), size: 8, c: WbArtColors.blue);
      p.text(c, 'Kromatografi', const Offset(100, 228), size: 11, bold: true);
    },
    tags: 'kromatografi kağıt boyar madde ayırma',
  ),
  WbArtItem(
    'kim_ayirma_hunisi_duzenek',
    'Ayırma hunisi ile ayırma',
    250,
    250,
    (c, p) {
      _stand(c, p, 40, 20, 225, 90);
      _clamp(c, p, const Offset(40, 70), const Offset(110, 75));
      _sepFunnel(c, p, 130, 40);
      final b = WbArtPen.poly(const [
        Offset(115, 205),
        Offset(118, 215),
        Offset(118, 235),
        Offset(160, 235),
        Offset(160, 215),
        Offset(163, 205),
      ], close: false);
      _glass(c, p, b);
      _liq(c, p, b, 222, WbArtColors.blue, 0.4);
      p.text(
        c,
        'Ayırma hunisi ile ayırma',
        const Offset(125, 248),
        size: 10,
        bold: true,
      );
    },
    tags: 'ayırma hunisi ile ayırma karışmayan sıvılar yağ su düzenek',
  ),
  WbArtItem(
    'kim_h2_eldesi',
    'Hidrojen gazı eldesi',
    300,
    240,
    (c, p) {
      final f = _roundFlask(60, 90, 12, 165, 40);
      _glass(c, p, f);
      _liq(c, p, f, 150, WbArtColors.lightBlue, 0.35);
      c.drawCircle(const Offset(55, 195), 3, p.fill(WbArtColors.gray, 0.9));
      c.drawCircle(const Offset(65, 197), 3, p.fill(WbArtColors.gray, 0.9));
      _stopper(c, p, 60, 92, 12);
      c.drawLine(const Offset(52, 30), const Offset(52, 125), p.line);
      c.drawLine(const Offset(52, 125), const Offset(46, 135), p.line);
      p.text(c, 'HCl', const Offset(52, 22), size: 9, bold: true);
      final d = Path()
        ..moveTo(68, 85)
        ..lineTo(68, 55)
        ..lineTo(220, 55)
        ..lineTo(220, 185)
        ..lineTo(205, 185);
      c.drawPath(d, p.stroke(WbArtColors.gray, 1.2));
      _trough(c, p, const Rect.fromLTWH(165, 150, 120, 70), 170);
      final t = _tubePath(205, 120, 205, 20);
      c.drawPath(t, p.line);
      _liq(c, p, t, 165, WbArtColors.blue, 0.3);
      _bubbles(
        c,
        p,
        const [Offset(205, 195), Offset(210, 180), Offset(203, 170)],
        3,
        WbArtColors.blue,
      );
      p.text(c, 'H₂', const Offset(205, 140), size: 11, bold: true);
      p.text(c, 'Zn + HCl', const Offset(60, 175), size: 9);
      p.text(
        c,
        'Zn(k) + 2HCl → ZnCl₂ + H₂(g)',
        const Offset(150, 12),
        size: 9,
        bold: true,
      );
      p.text(c, 'Su', const Offset(260, 195), size: 9, c: WbArtColors.blue);
    },
    tags: 'hidrojen h2 gaz eldesi çinko hcl düzenek',
  ),
  WbArtItem(
    'kim_elektroliz_su',
    'Suyun elektrolizi',
    240,
    250,
    (c, p) {
      final b = WbArtPen.poly(const [
        Offset(35, 110),
        Offset(40, 120),
        Offset(40, 220),
        Offset(200, 220),
        Offset(200, 120),
        Offset(205, 110),
      ], close: false);
      _glass(c, p, b);
      _liq(c, p, b, 130, WbArtColors.blue, 0.25);
      final k = _tubePath(85, 60, 150, 20);
      final a = _tubePath(155, 60, 150, 20);
      c.drawPath(k, p.line);
      c.drawPath(a, p.line);
      _liq(c, p, k, 95, WbArtColors.blue, 0.3);
      _liq(c, p, a, 125, WbArtColors.blue, 0.3);
      c.drawLine(
        const Offset(85, 220),
        const Offset(85, 120),
        p.stroke(WbArtColors.gray, 2),
      );
      c.drawLine(
        const Offset(155, 220),
        const Offset(155, 120),
        p.stroke(WbArtColors.gray, 2),
      );
      final w = Path()
        ..moveTo(85, 220)
        ..lineTo(85, 238)
        ..lineTo(105, 238);
      c.drawPath(w, p.thin());
      final w2 = Path()
        ..moveTo(155, 220)
        ..lineTo(155, 238)
        ..lineTo(135, 238);
      c.drawPath(w2, p.thin());
      _battery(c, p, const Offset(120, 238));
      _bubbles(
        c,
        p,
        const [
          Offset(85, 160),
          Offset(80, 185),
          Offset(90, 200),
          Offset(155, 170),
          Offset(152, 195),
        ],
        3,
        WbArtColors.teal,
      );
      p.text(c, 'H₂', const Offset(85, 78), size: 11, bold: true);
      p.text(c, 'O₂', const Offset(155, 110), size: 11, bold: true);
      p.text(
        c,
        'Katot (–)',
        const Offset(85, 40),
        size: 9,
        c: WbArtColors.blue,
        bold: true,
      );
      p.text(
        c,
        'Anot (+)',
        const Offset(155, 40),
        size: 9,
        c: WbArtColors.red,
        bold: true,
      );
      p.text(
        c,
        'Hacim: 2 H₂ : 1 O₂',
        const Offset(120, 18),
        size: 9,
        bold: true,
      );
      p.text(c, '2H₂O → 2H₂ + O₂', const Offset(120, 138), size: 8);
    },
    tags: 'elektroliz su hidrojen oksijen katot anot hoffman',
  ),
  WbArtItem(
    'kim_elektroliz_nacl',
    'Erimiş NaCl elektrolizi',
    260,
    250,
    (c, p) {
      final k = Path()
        ..moveTo(40, 110)
        ..lineTo(48, 195)
        ..quadraticBezierTo(130, 225, 212, 195)
        ..lineTo(220, 110);
      _glass(c, p, k, col: WbArtColors.gray);
      _liq(c, p, k, 130, WbArtColors.orange, 0.4);
      c.drawLine(
        const Offset(90, 70),
        const Offset(90, 185),
        p.stroke(WbArtColors.gray, 3),
      );
      c.drawLine(
        const Offset(170, 70),
        const Offset(170, 185),
        p.stroke(WbArtColors.gray, 3),
      );
      c.drawLine(const Offset(90, 70), const Offset(90, 40), p.line);
      c.drawLine(const Offset(170, 70), const Offset(170, 40), p.line);
      c.drawLine(const Offset(90, 40), const Offset(120, 40), p.line);
      c.drawLine(const Offset(170, 40), const Offset(140, 40), p.line);
      _battery(c, p, const Offset(130, 40));
      _bubbles(
        c,
        p,
        const [Offset(172, 115), Offset(168, 100), Offset(173, 85)],
        3,
        WbArtColors.green,
      );
      c.drawCircle(const Offset(90, 190), 4, p.fill(WbArtColors.gray, 0.8));
      p.arrow(
        c,
        const Offset(130, 160),
        const Offset(100, 160),
        c: WbArtColors.purple,
        size: 6,
      );
      p.arrow(
        c,
        const Offset(130, 175),
        const Offset(160, 175),
        c: WbArtColors.green,
        size: 6,
      );
      p.text(
        c,
        'Na⁺',
        const Offset(130, 150),
        size: 9,
        c: WbArtColors.purple,
        bold: true,
      );
      p.text(
        c,
        'Cl⁻',
        const Offset(130, 188),
        size: 9,
        c: WbArtColors.darkGreen,
        bold: true,
      );
      p.text(
        c,
        'Katot (–): Na⁺ + e⁻ → Na',
        const Offset(40, 18),
        size: 8,
        anchor: 'left',
      );
      p.text(
        c,
        'Anot (+): 2Cl⁻ → Cl₂ + 2e⁻',
        const Offset(40, 8),
        size: 8,
        anchor: 'left',
      );
      p.text(c, 'Cl₂(g)', const Offset(195, 90), size: 9, anchor: 'left');
      p.text(c, 'Na(s)', const Offset(55, 165), size: 9, anchor: 'right');
      p.text(
        c,
        'Erimiş NaCl',
        const Offset(130, 215),
        size: 9,
        c: WbArtColors.orange,
      );
      p.text(
        c,
        'NaCl elektrolizi',
        const Offset(130, 240),
        size: 11,
        bold: true,
      );
    },
    tags: 'elektroliz nacl sodyum klor erimiş tuz katot anot',
  ),
  WbArtItem(
    'kim_galvanik_pil',
    'Galvanik pil (Zn–Cu)',
    320,
    250,
    (c, p) {
      for (int i = 0; i < 2; i++) {
        final x = 30.0 + i * 170;
        final b = WbArtPen.poly([
          Offset(x, 110),
          Offset(x + 5, 120),
          Offset(x + 5, 215),
          Offset(x + 115, 215),
          Offset(x + 115, 120),
          Offset(x + 120, 110),
        ], close: false);
        _glass(c, p, b);
        _liq(
          c,
          p,
          b,
          140,
          i == 0 ? WbArtColors.lightBlue : WbArtColors.blue,
          0.35,
        );
      }
      c.drawRect(
        const Rect.fromLTRB(70, 70, 86, 200),
        p.fill(WbArtColors.gray, 0.5),
      );
      c.drawRect(const Rect.fromLTRB(70, 70, 86, 200), p.line);
      c.drawRect(
        const Rect.fromLTRB(234, 70, 250, 200),
        p.fill(WbArtColors.orange, 0.5),
      );
      c.drawRect(const Rect.fromLTRB(234, 70, 250, 200), p.line);
      final sb = Path()
        ..moveTo(115, 175)
        ..lineTo(115, 105)
        ..lineTo(205, 105)
        ..lineTo(205, 175);
      c.drawPath(sb, p.stroke(WbArtColors.green, 5));
      c.drawPath(sb, p.line);
      final w = Path()
        ..moveTo(78, 70)
        ..lineTo(78, 40)
        ..lineTo(140, 40)
        ..moveTo(180, 40)
        ..lineTo(242, 40)
        ..lineTo(242, 70);
      c.drawPath(w, p.line);
      c.drawCircle(const Offset(160, 40), 20, p.fill(WbArtColors.yellow, 0.3));
      c.drawCircle(const Offset(160, 40), 20, p.line);
      p.text(c, 'V', const Offset(160, 40), size: 13, bold: true);
      p.arrow(
        c,
        const Offset(95, 28),
        const Offset(135, 28),
        c: WbArtColors.blue,
        size: 6,
      );
      p.text(
        c,
        'e⁻',
        const Offset(115, 18),
        size: 9,
        c: WbArtColors.blue,
        bold: true,
      );
      p.text(c, 'Zn (anot, –)', const Offset(78, 232), size: 9, bold: true);
      p.text(c, 'Cu (katot, +)', const Offset(242, 232), size: 9, bold: true);
      p.text(c, 'ZnSO₄', const Offset(100, 190), size: 8, anchor: 'right');
      p.text(c, 'CuSO₄', const Offset(220, 190), size: 8, anchor: 'left');
      p.text(
        c,
        'Tuz köprüsü',
        const Offset(160, 125),
        size: 9,
        c: WbArtColors.darkGreen,
      );
      p.text(
        c,
        'Zn → Zn²⁺ + 2e⁻',
        const Offset(10, 70),
        size: 8,
        anchor: 'left',
      );
      p.text(
        c,
        'Cu²⁺ + 2e⁻ → Cu',
        const Offset(310, 70),
        size: 8,
        anchor: 'right',
      );
      p.arrow(
        c,
        const Offset(140, 150),
        const Offset(110, 150),
        c: WbArtColors.purple,
        size: 5,
      );
      p.arrow(
        c,
        const Offset(180, 150),
        const Offset(210, 150),
        c: WbArtColors.purple,
        size: 5,
      );
      p.text(c, 'Anyon', const Offset(210, 160), size: 7, anchor: 'left');
      p.text(c, 'Katyon', const Offset(110, 160), size: 7, anchor: 'right');
    },
    tags: 'galvanik pil daniell zn cu tuz köprüsü elektron yönü anot katot',
  ),
  WbArtItem(
    'kim_titrasyon',
    'Titrasyon düzeneği',
    220,
    260,
    (c, p) {
      _stand(c, p, 40, 15, 235, 100);
      _clamp(c, p, const Offset(40, 80), const Offset(95, 80));
      final t = Path()
        ..moveTo(95, 12)
        ..lineTo(95, 140)
        ..lineTo(109, 140)
        ..lineTo(109, 12);
      _glass(c, p, t);
      _liq(c, p, t, 40, WbArtColors.purple, 0.3);
      _ticks(c, p, 95, 20, 135, 23, 10, right: false);
      c.drawLine(const Offset(86, 145), const Offset(118, 145), p.line);
      c.drawLine(const Offset(102, 140), const Offset(102, 160), p.line);
      c.drawCircle(
        const Offset(102, 175),
        2.5,
        p.fill(WbArtColors.purple, 0.8),
      );
      final e = _flaskPath(102, 185, 12, 200, 240, 36);
      _glass(c, p, e);
      _liq(c, p, e, 225, WbArtColors.pink, 0.4);
      c.drawRect(
        const Rect.fromLTRB(55, 240, 150, 247),
        p.fill(WbArtColors.gray, 0.3),
      );
      p.text(c, 'NaOH (büret)', const Offset(122, 40), size: 9, anchor: 'left');
      p.text(c, 'Musluk', const Offset(122, 145), size: 8, anchor: 'left');
      p.text(
        c,
        'HCl + indikatör',
        const Offset(150, 222),
        size: 8,
        anchor: 'left',
      );
      p.text(c, 'Beyaz zemin', const Offset(155, 245), size: 8, anchor: 'left');
      p.text(c, 'Titrasyon', const Offset(110, 258), size: 11, bold: true);
    },
    tags: 'titrasyon büret erlenmayer asit baz nötrleşme indikatör',
  ),
];

extension _PenX on WbArtPen {
  Paint dashedHelper() => thin(0.6);
  Paint dashedHelperPaint() => thin(0.6);
}

// ───────────────────────── Atom / Periyodik ─────────────────────────

void _bohr(
  Canvas c,
  WbArtPen p,
  String name,
  String sym,
  int pr,
  int ne,
  List<int> shells,
) {
  const ctr = Offset(100, 100);
  for (int i = 0; i < shells.length; i++) {
    final r = 32.0 + i * 24;
    c.drawCircle(ctr, r, p.thin(0.6));
    for (int k = 0; k < shells[i]; k++) {
      final a = -math.pi / 2 + 2 * math.pi * k / shells[i] + i * 0.4;
      final o = ctr + Offset(math.cos(a), math.sin(a)) * r;
      c.drawCircle(o, 4.5, p.fill(WbArtColors.blue, 0.85));
      p.text(c, '–', o, size: 7, c: Colors.white, bold: true);
    }
  }
  c.drawCircle(ctr, 20, p.fill(WbArtColors.red, 0.3));
  c.drawCircle(ctr, 20, p.stroke(WbArtColors.red, 0.6));
  p.text(c, '${pr}p\n${ne}n', ctr, size: 9, bold: true);
  p.text(c, '$name ($sym) atomu', const Offset(100, 192), size: 11, bold: true);
  p.text(
    c,
    'Elektron dizilimi: ${shells.join(' , ')}',
    const Offset(100, 208),
    size: 9,
  );
}

void _lobe(
  Canvas c,
  WbArtPen p,
  Offset ctr,
  double angle,
  double len,
  double wid,
  Color col,
) {
  c.save();
  c.translate(ctr.dx, ctr.dy);
  c.rotate(angle);
  final r = Rect.fromCenter(
    center: Offset(len / 2, 0),
    width: len,
    height: wid,
  );
  c.drawOval(r, p.fill(col, 0.35));
  c.drawOval(r, p.stroke(col, 0.7));
  c.restore();
}

final List<WbArtItem> _chemAtoms = [
  WbArtItem(
    'kim_bohr_h',
    'Bohr atom modeli – Hidrojen',
    200,
    220,
    (c, p) => _bohr(c, p, 'Hidrojen', 'H', 1, 0, [1]),
    tags: 'bohr atom modeli hidrojen h yörünge elektron',
  ),
  WbArtItem(
    'kim_bohr_he',
    'Bohr atom modeli – Helyum',
    200,
    220,
    (c, p) => _bohr(c, p, 'Helyum', 'He', 2, 2, [2]),
    tags: 'bohr atom modeli helyum he',
  ),
  WbArtItem(
    'kim_bohr_li',
    'Bohr atom modeli – Lityum',
    200,
    220,
    (c, p) => _bohr(c, p, 'Lityum', 'Li', 3, 4, [2, 1]),
    tags: 'bohr atom modeli lityum li',
  ),
  WbArtItem(
    'kim_bohr_c',
    'Bohr atom modeli – Karbon',
    200,
    220,
    (c, p) => _bohr(c, p, 'Karbon', 'C', 6, 6, [2, 4]),
    tags: 'bohr atom modeli karbon c',
  ),
  WbArtItem(
    'kim_bohr_na',
    'Bohr atom modeli – Sodyum',
    200,
    220,
    (c, p) => _bohr(c, p, 'Sodyum', 'Na', 11, 12, [2, 8, 1]),
    tags: 'bohr atom modeli sodyum na',
  ),
  WbArtItem(
    'kim_orbital_s',
    's orbitali',
    200,
    220,
    (c, p) {
      c.drawCircle(const Offset(100, 100), 65, p.fill(WbArtColors.blue, 0.2));
      c.drawCircle(const Offset(100, 100), 65, p.stroke(WbArtColors.blue, 0.7));
      c.drawCircle(const Offset(100, 100), 40, p.fill(WbArtColors.blue, 0.2));
      c.drawCircle(const Offset(100, 100), 4, p.solid);
      p.arrow(c, const Offset(100, 100), const Offset(165, 100), size: 5);
      p.text(c, 'Çekirdek', const Offset(100, 114), size: 8);
      p.text(
        c,
        's orbitali (küresel)',
        const Offset(100, 192),
        size: 11,
        bold: true,
      );
      p.text(c, 'En fazla 2 elektron', const Offset(100, 208), size: 9);
    },
    tags: 'orbital s küresel kuantum atom orbitali',
  ),
  WbArtItem(
    'kim_orbital_p',
    'p orbitalleri (px, py, pz)',
    300,
    170,
    (c, p) {
      final names = ['px', 'py', 'pz'];
      final cols = [WbArtColors.red, WbArtColors.green, WbArtColors.purple];
      for (int i = 0; i < 3; i++) {
        final ctr = Offset(50.0 + i * 100, 80);
        c.drawLine(
          ctr + const Offset(-40, 0),
          ctr + const Offset(40, 0),
          p.thin(0.4),
        );
        c.drawLine(
          ctr + const Offset(0, -40),
          ctr + const Offset(0, 40),
          p.thin(0.4),
        );
        if (i == 0) {
          _lobe(c, p, ctr, 0, 40, 26, cols[i]);
          _lobe(c, p, ctr, math.pi, 40, 26, cols[i]);
        } else if (i == 1) {
          _lobe(c, p, ctr, -math.pi / 2, 40, 26, cols[i]);
          _lobe(c, p, ctr, math.pi / 2, 40, 26, cols[i]);
        } else {
          _lobe(c, p, ctr, -2.35, 40, 26, cols[i]);
          _lobe(c, p, ctr, 0.8, 40, 26, cols[i]);
        }
        c.drawCircle(ctr, 2.5, p.solid);
        p.text(c, names[i], Offset(ctr.dx, 140), size: 11, bold: true);
      }
      p.text(
        c,
        'p orbitalleri (halter biçimli, 3 tane)',
        const Offset(150, 160),
        size: 9,
      );
    },
    tags: 'orbital p halter px py pz atom orbitalleri',
  ),
  WbArtItem(
    'kim_periyodik_tablo',
    'Periyodik tablo',
    380,
    235,
    (c, p) {
      const rows = [
        'H - - - - - - - - - - - - - - - - He',
        'Li Be - - - - - - - - - - B C N O F Ne',
        'Na Mg - - - - - - - - - - Al Si P S Cl Ar',
        'K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr',
        'Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe',
        'Cs Ba La Hf Ta W Re Os Ir Pt Au Hg Tl Pb Bi Po At Rn',
        'Fr Ra Ac Rf Db Sg Bh Hs Mt Ds Rg Cn Nh Fl Mc Lv Ts Og',
      ];
      const cw = 19.5;
      const ch = 20.0;
      const left = 10.0;
      const top = 28.0;
      Color colorFor(int col, int row) {
        if (col <= 1 || (row == 0 && col == 17)) return WbArtColors.red;
        if (col >= 12) return WbArtColors.blue;
        return WbArtColors.green;
      }

      for (int r = 0; r < rows.length; r++) {
        final syms = rows[r].split(' ');
        for (int col = 0; col < 18; col++) {
          final s = syms[col];
          if (s == '-') continue;
          final rect = Rect.fromLTWH(
            left + col * cw,
            top + r * ch,
            cw - 1.5,
            ch - 1.5,
          );
          final colr = colorFor(col, r);
          c.drawRect(rect, p.fill(colr, 0.25));
          c.drawRect(rect, p.stroke(colr, 0.3));
          p.text(c, s, rect.center, size: 8, bold: true);
        }
        p.text(
          c,
          '${r + 1}',
          Offset(left - 3, top + r * ch + ch / 2),
          size: 8,
          anchor: 'right',
        );
      }
      for (int col = 0; col < 18; col++) {
        p.text(
          c,
          '${col + 1}',
          Offset(left + col * cw + cw / 2, top - 6),
          size: 7,
        );
      }
      for (int i = 0; i < 2; i++) {
        for (int k = 0; k < 14; k++) {
          final rect = Rect.fromLTWH(
            left + (k + 3) * cw,
            top + 7.6 * ch + i * ch,
            cw - 1.5,
            ch - 1.5,
          );
          c.drawRect(rect, p.fill(WbArtColors.orange, 0.25));
          c.drawRect(rect, p.stroke(WbArtColors.orange, 0.3));
        }
        p.text(
          c,
          i == 0 ? 'Lantanitler' : 'Aktinitler',
          Offset(left + 3 * cw - 3, top + 7.6 * ch + i * ch + ch / 2),
          size: 7,
          anchor: 'right',
        );
      }
      p.text(c, 'Periyodik Tablo', const Offset(190, 10), size: 11, bold: true);
      p.text(
        c,
        'Periyot ↓   Grup →',
        const Offset(10, 10),
        size: 8,
        anchor: 'left',
      );
      final lg = [
        ['s bloğu', WbArtColors.red],
        ['p bloğu', WbArtColors.blue],
        ['d bloğu', WbArtColors.green],
        ['f bloğu', WbArtColors.orange],
      ];
      for (int i = 0; i < 4; i++) {
        c.drawRect(
          Rect.fromLTWH(260.0 + (i % 2) * 55, 28.0 + (i ~/ 2) * 14, 8, 8),
          p.fill(lg[i][1] as Color, 0.5),
        );
        p.text(
          c,
          lg[i][0] as String,
          Offset(272 + (i % 2) * 55, 32 + (i ~/ 2) * 14),
          size: 8,
          anchor: 'left',
        );
      }
    },
    tags: 'periyodik tablo elementler s p d f blok periyot grup',
  ),
  WbArtItem(
    'kim_elektron_dizilimi',
    'Elektron dizilimi kutu şeması',
    260,
    240,
    (c, p) {
      final orbs = [
        ['1s', 1, 2],
        ['2s', 1, 2],
        ['2p', 3, 4],
        ['3s', 1, 0],
        ['3p', 3, 0],
        ['4s', 1, 0],
      ];
      for (int i = 0; i < orbs.length; i++) {
        final y = 195.0 - i * 28;
        final n = orbs[i][1] as int;
        final e = orbs[i][2] as int;
        p.text(
          c,
          orbs[i][0] as String,
          Offset(40, y + 11),
          size: 10,
          bold: true,
          anchor: 'right',
        );
        for (int k = 0; k < n; k++) {
          final r = Rect.fromLTWH(50.0 + k * 26, y, 24, 22);
          c.drawRect(r, p.line);
          int up = 0;
          int down = 0;
          if (n == 1) {
            up = e >= 1 ? 1 : 0;
            down = e >= 2 ? 1 : 0;
          } else {
            up = e > k ? 1 : 0;
            down = e > k + n ? 1 : 0;
          }
          if (up == 1)
            p.arrow(
              c,
              Offset(r.center.dx - 4, r.bottom - 3),
              Offset(r.center.dx - 4, r.top + 3),
              size: 4,
              c: WbArtColors.blue,
            );
          if (down == 1)
            p.arrow(
              c,
              Offset(r.center.dx + 4, r.top + 3),
              Offset(r.center.dx + 4, r.bottom - 3),
              size: 4,
              c: WbArtColors.red,
            );
        }
      }
      p.arrow(c, const Offset(20, 200), const Offset(20, 40), size: 6);
      p.text(c, 'Enerji', const Offset(8, 120), size: 9, anchor: 'left');
      p.text(
        c,
        'Örnek: ₈O  1s² 2s² 2p⁴',
        const Offset(140, 40),
        size: 10,
        bold: true,
        anchor: 'left',
      );
      p.text(
        c,
        'Pauli: her kutuda\nzıt spinli 2 e⁻',
        const Offset(190, 90),
        size: 9,
        anchor: 'left',
      );
      p.text(
        c,
        'Hund: önce her kutuya\ntek e⁻, sonra eşleşme',
        const Offset(190, 135),
        size: 9,
        anchor: 'left',
      );
      p.text(
        c,
        'Elektron dizilimi kutu şeması',
        const Offset(130, 230),
        size: 11,
        bold: true,
      );
    },
    tags: 'elektron dizilimi kutu şeması orbital pauli hund aufbau',
  ),
  WbArtItem(
    'kim_izotop',
    'İzotop gösterimi',
    300,
    170,
    (c, p) {
      final data = [
        ['12', '6', 'C', '6p  6n'],
        ['13', '6', 'C', '6p  7n'],
        ['14', '6', 'C', '6p  8n'],
      ];
      for (int i = 0; i < 3; i++) {
        final x = 55.0 + i * 95;
        p.text(
          c,
          data[i][0],
          Offset(x - 22, 45),
          size: 14,
          bold: true,
          c: WbArtColors.red,
        );
        p.text(
          c,
          data[i][1],
          Offset(x - 22, 80),
          size: 14,
          bold: true,
          c: WbArtColors.blue,
        );
        p.text(c, data[i][2], Offset(x + 5, 62), size: 30, bold: true);
        p.text(c, data[i][3], Offset(x, 112), size: 10);
        p.text(c, 'Karbon-${data[i][0]}', Offset(x, 130), size: 9);
      }
      p.text(
        c,
        'Kütle numarası (A) = p + n',
        const Offset(150, 10),
        size: 9,
        c: WbArtColors.red,
      );
      p.text(
        c,
        'Atom numarası (Z) = p',
        const Offset(150, 24),
        size: 9,
        c: WbArtColors.blue,
      );
      p.text(
        c,
        'İzotoplar: proton sayısı aynı, nötron sayısı farklı',
        const Offset(150, 155),
        size: 9,
        bold: true,
      );
    },
    tags: 'izotop kütle numarası atom numarası karbon 12 13 14',
  ),
];

// ───────────────────────── Bağ / Molekül ─────────────────────────

final List<WbArtItem> _chemMolecules = [
  WbArtItem('kim_h2o', 'Su molekülü (H₂O)', 200, 180, (c, p) {
    const o = Offset(100, 70);
    final h1 =
        o +
        Offset(math.cos(math.pi / 2 + 0.91), math.sin(math.pi / 2 + 0.91)) * 55;
    final h2 =
        o +
        Offset(math.cos(math.pi / 2 - 0.91), math.sin(math.pi / 2 - 0.91)) * 55;
    _bond(c, p, o, h1);
    _bond(c, p, o, h2);
    _atom(c, p, o, 20, WbArtColors.red, 'O');
    _atom(c, p, h1, 13, WbArtColors.lightBlue, 'H');
    _atom(c, p, h2, 13, WbArtColors.lightBlue, 'H');
    p.text(c, '104,5°', const Offset(100, 125), size: 9);
    p.text(
      c,
      'δ–',
      const Offset(100, 38),
      size: 10,
      c: WbArtColors.red,
      bold: true,
    );
    p.text(
      c,
      'δ+',
      Offset(h1.dx - 20, h1.dy),
      size: 9,
      c: WbArtColors.blue,
      bold: true,
    );
    p.text(
      c,
      'δ+',
      Offset(h2.dx + 20, h2.dy),
      size: 9,
      c: WbArtColors.blue,
      bold: true,
    );
    p.text(
      c,
      'H₂O – kırık (V) yapı, polar',
      const Offset(100, 160),
      size: 10,
      bold: true,
    );
  }, tags: 'su h2o molekül kırık yapı polar'),
  WbArtItem(
    'kim_co2',
    'Karbondioksit (CO₂)',
    220,
    140,
    (c, p) {
      _bond(c, p, const Offset(55, 60), const Offset(110, 60), 2);
      _bond(c, p, const Offset(110, 60), const Offset(165, 60), 2);
      _atom(c, p, const Offset(110, 60), 17, WbArtColors.gray, 'C');
      _atom(c, p, const Offset(50, 60), 17, WbArtColors.red, 'O');
      _atom(c, p, const Offset(170, 60), 17, WbArtColors.red, 'O');
      p.text(
        c,
        'O = C = O   (180°, doğrusal, apolar)',
        const Offset(110, 105),
        size: 10,
        bold: true,
      );
      p.text(c, 'CO₂', const Offset(110, 125), size: 10);
    },
    tags: 'karbondioksit co2 doğrusal molekül',
  ),
  WbArtItem('kim_ch4', 'Metan (CH₄)', 200, 190, (c, p) {
    const ctr = Offset(100, 80);
    final hs = [
      const Offset(100, 20),
      const Offset(45, 105),
      const Offset(155, 105),
      const Offset(125, 135),
    ];
    c.drawLine(ctr, hs[0], p.line);
    c.drawLine(ctr, hs[1], p.line);
    c.drawLine(ctr, hs[2], p.line);
    final w = WbArtPen.poly([
      ctr + const Offset(-4, 0),
      ctr + const Offset(4, 0),
      hs[3],
    ]);
    c.drawPath(w, p.fill(p.color, 0.5));
    for (final h in hs) {
      _atom(c, p, h, 12, WbArtColors.lightBlue, 'H');
    }
    _atom(c, p, ctr, 17, WbArtColors.gray, 'C');
    p.text(
      c,
      'CH₄ – düzgün dörtyüzlü, 109,5°',
      const Offset(100, 170),
      size: 10,
      bold: true,
    );
  }, tags: 'metan ch4 dörtyüzlü tetrahedral molekül'),
  WbArtItem('kim_nh3', 'Amonyak (NH₃)', 200, 190, (c, p) {
    const n = Offset(100, 60);
    final hs = [
      const Offset(50, 115),
      const Offset(100, 130),
      const Offset(150, 115),
    ];
    for (final h in hs) {
      _bond(c, p, n, h);
    }
    for (final h in hs) {
      _atom(c, p, h, 12, WbArtColors.lightBlue, 'H');
    }
    _atom(c, p, n, 18, WbArtColors.blue, 'N');
    c.drawCircle(const Offset(94, 30), 2, p.solid);
    c.drawCircle(const Offset(106, 30), 2, p.solid);
    p.text(
      c,
      'Ortaklanmamış e⁻ çifti',
      const Offset(130, 25),
      size: 8,
      anchor: 'left',
    );
    p.text(
      c,
      'NH₃ – üçgen piramit, polar',
      const Offset(100, 170),
      size: 10,
      bold: true,
    );
  }, tags: 'amonyak nh3 piramit molekül'),
  WbArtItem('kim_o2', 'Oksijen molekülü (O₂)', 200, 120, (c, p) {
    _bond(c, p, const Offset(70, 55), const Offset(130, 55), 2);
    _atom(c, p, const Offset(65, 55), 20, WbArtColors.red, 'O');
    _atom(c, p, const Offset(135, 55), 20, WbArtColors.red, 'O');
    p.text(
      c,
      'O = O  (çift bağ)',
      const Offset(100, 100),
      size: 10,
      bold: true,
    );
  }, tags: 'oksijen o2 çift bağ molekül'),
  WbArtItem('kim_n2', 'Azot molekülü (N₂)', 200, 120, (c, p) {
    _bond(c, p, const Offset(70, 55), const Offset(130, 55), 3);
    _atom(c, p, const Offset(65, 55), 20, WbArtColors.blue, 'N');
    _atom(c, p, const Offset(135, 55), 20, WbArtColors.blue, 'N');
    p.text(
      c,
      'N ≡ N  (üçlü bağ)',
      const Offset(100, 100),
      size: 10,
      bold: true,
    );
  }, tags: 'azot n2 üçlü bağ molekül'),
  WbArtItem(
    'kim_hcl',
    'Hidrojen klorür (HCl)',
    200,
    130,
    (c, p) {
      _bond(c, p, const Offset(70, 55), const Offset(125, 55));
      _atom(c, p, const Offset(60, 55), 14, WbArtColors.lightBlue, 'H');
      _atom(c, p, const Offset(135, 55), 22, WbArtColors.green, 'Cl');
      p.text(
        c,
        'δ+',
        const Offset(60, 28),
        size: 10,
        c: WbArtColors.blue,
        bold: true,
      );
      p.text(
        c,
        'δ–',
        const Offset(135, 22),
        size: 10,
        c: WbArtColors.red,
        bold: true,
      );
      p.arrow(c, const Offset(60, 90), const Offset(135, 90), size: 6);
      p.text(
        c,
        'Polar kovalent bağ (dipol)',
        const Offset(100, 112),
        size: 10,
        bold: true,
      );
    },
    tags: 'hcl hidrojen klorür polar kovalent dipol',
  ),
  WbArtItem(
    'kim_nacl_kafes',
    'NaCl kristal örgüsü',
    220,
    220,
    (c, p) {
      const s = 44.0;
      for (int i = 0; i < 4; i++) {
        c.drawLine(
          Offset(30, 30 + i * s),
          Offset(30 + 3 * s, 30 + i * s),
          p.thin(),
        );
        c.drawLine(
          Offset(30 + i * s, 30),
          Offset(30 + i * s, 30 + 3 * s),
          p.thin(),
        );
      }
      for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
          final o = Offset(30 + i * s, 30 + j * s);
          if ((i + j).isEven) {
            _atom(c, p, o, 9, WbArtColors.purple, 'Na⁺', ts: 7);
          } else {
            _atom(c, p, o, 13, WbArtColors.green, 'Cl⁻', ts: 8);
          }
        }
      }
      p.text(
        c,
        'NaCl kristal örgüsü (iyonik)',
        const Offset(110, 205),
        size: 10,
        bold: true,
      );
    },
    tags: 'nacl kristal örgü iyonik kafes sodyum klorür',
  ),
  WbArtItem(
    'kim_elmas',
    'Elmas yapısı',
    220,
    220,
    (c, p) {
      final pts = <Offset>[
        const Offset(110, 40),
        const Offset(60, 80),
        const Offset(160, 80),
        const Offset(110, 115),
        const Offset(30, 125),
        const Offset(190, 125),
        const Offset(70, 160),
        const Offset(150, 160),
      ];
      final bonds = [
        [0, 1],
        [0, 2],
        [0, 3],
        [1, 3],
        [2, 3],
        [1, 4],
        [2, 5],
        [3, 6],
        [3, 7],
      ];
      for (final b in bonds) {
        c.drawLine(pts[b[0]], pts[b[1]], p.line);
      }
      for (final o in pts) {
        _atom(c, p, o, 9, WbArtColors.gray, 'C', ts: 8);
      }
      p.text(
        c,
        'Elmas: her C, 4 C ile bağlı',
        const Offset(110, 190),
        size: 10,
        bold: true,
      );
      p.text(
        c,
        '(kovalent ağ yapısı, çok sert)',
        const Offset(110, 206),
        size: 9,
      );
    },
    tags: 'elmas karbon kovalent ağ yapı sert allotrop',
  ),
  WbArtItem(
    'kim_grafit',
    'Grafit yapısı',
    240,
    230,
    (c, p) {
      for (int l = 0; l < 2; l++) {
        final dy = l * 70.0;
        final col = l == 0 ? WbArtColors.gray : WbArtColors.blue;
        for (int r = 0; r < 2; r++) {
          for (int k = 0; k < 3; k++) {
            final ctr = Offset(
              70 + k * 50 + (r.isOdd ? 25 : 0),
              50 + dy + r * 22,
            );
            final pts = [
              for (int i = 0; i < 6; i++)
                ctr +
                    Offset(
                      math.cos(i * math.pi / 3) * 24,
                      math.sin(i * math.pi / 3) * 9,
                    ),
            ];
            c.drawPath(WbArtPen.poly(pts), p.stroke(col, 0.7));
            c.drawPath(WbArtPen.poly(pts), p.fill(col, 0.1));
          }
        }
        p.text(
          c,
          'Katman ${l + 1}',
          Offset(10, 55 + dy),
          size: 8,
          anchor: 'left',
        );
      }
      p.dashed(c, const Offset(100, 60), const Offset(100, 120));
      p.dashed(c, const Offset(150, 60), const Offset(150, 120));
      p.text(
        c,
        'Zayıf van der Waals',
        const Offset(160, 95),
        size: 8,
        anchor: 'left',
      );
      p.text(
        c,
        'Grafit: altıgen katmanlı yapı',
        const Offset(120, 195),
        size: 10,
        bold: true,
      );
      p.text(c, '(katmanlar kayar, iletken)', const Offset(120, 211), size: 9);
    },
    tags: 'grafit karbon katman altıgen allotrop iletken',
  ),
  WbArtItem(
    'kim_lewis_atom',
    'Lewis nokta yapıları (atomlar)',
    300,
    150,
    (c, p) {
      final data = [
        [
          'Li',
          [0, 0, 0, 1],
        ],
        [
          'Be',
          [0, 0, 0, 2],
        ],
        [
          'B',
          [1, 0, 0, 2],
        ],
        [
          'C',
          [1, 1, 0, 2],
        ],
        [
          'N',
          [1, 1, 1, 2],
        ],
        [
          'O',
          [2, 1, 1, 2],
        ],
        [
          'F',
          [2, 2, 1, 2],
        ],
        [
          'Ne',
          [2, 2, 2, 2],
        ],
      ];
      for (int i = 0; i < 8; i++) {
        final o = Offset(30.0 + (i % 4) * 80, 45.0 + (i ~/ 4) * 60);
        p.text(c, data[i][0] as String, o, size: 16, bold: true);
        final s = data[i][1] as List<int>;
        final dirs = [
          const Offset(0, -15),
          const Offset(15, 0),
          const Offset(0, 15),
          const Offset(-15, 0),
        ];
        for (int k = 0; k < 4; k++) {
          for (int e = 0; e < s[k]; e++) {
            final horiz = k.isEven;
            final off = (e == 0 ? -1 : 1) * 3.5;
            c.drawCircle(
              o + dirs[k] + (horiz ? Offset(off, 0) : Offset(0, off)),
              1.8,
              p.solid,
            );
          }
        }
      }
      p.text(
        c,
        'Lewis nokta yapıları (değerlik elektronları)',
        const Offset(150, 140),
        size: 9,
        bold: true,
      );
    },
    tags: 'lewis nokta yapısı değerlik elektron atom',
  ),
  WbArtItem(
    'kim_lewis_molekul',
    'Lewis yapıları (moleküller)',
    300,
    170,
    (c, p) {
      void d(Offset o, [double dx = 0, double dy = 0]) =>
          c.drawCircle(o + Offset(dx, dy), 1.8, p.solid);
      // H2O
      p.text(c, 'O', const Offset(50, 40), size: 15, bold: true);
      p.text(c, 'H', const Offset(20, 40), size: 15, bold: true);
      p.text(c, 'H', const Offset(80, 40), size: 15, bold: true);
      d(const Offset(50, 25), -4);
      d(const Offset(50, 25), 4);
      d(const Offset(50, 55), -4);
      d(const Offset(50, 55), 4);
      c.drawLine(const Offset(28, 40), const Offset(40, 40), p.line);
      c.drawLine(const Offset(60, 40), const Offset(72, 40), p.line);
      p.text(c, 'H₂O', const Offset(50, 72), size: 9);
      // NH3
      p.text(c, 'N', const Offset(150, 40), size: 15, bold: true);
      p.text(c, 'H', const Offset(120, 40), size: 15, bold: true);
      p.text(c, 'H', const Offset(180, 40), size: 15, bold: true);
      p.text(c, 'H', const Offset(150, 72), size: 15, bold: true);
      d(const Offset(150, 25), -4);
      d(const Offset(150, 25), 4);
      c.drawLine(const Offset(128, 40), const Offset(140, 40), p.line);
      c.drawLine(const Offset(160, 40), const Offset(172, 40), p.line);
      c.drawLine(const Offset(150, 50), const Offset(150, 63), p.line);
      p.text(c, 'NH₃', const Offset(150, 92), size: 9);
      // CO2
      p.text(c, 'O', const Offset(225, 40), size: 15, bold: true);
      p.text(c, 'C', const Offset(255, 40), size: 15, bold: true);
      p.text(c, 'O', const Offset(285, 40), size: 15, bold: true);
      for (final x in [225.0, 285.0]) {
        d(Offset(x, 25), -4);
        d(Offset(x, 25), 4);
        d(Offset(x, 55), -4);
        d(Offset(x, 55), 4);
      }
      c.drawLine(const Offset(233, 37), const Offset(247, 37), p.line);
      c.drawLine(const Offset(233, 43), const Offset(247, 43), p.line);
      c.drawLine(const Offset(263, 37), const Offset(277, 37), p.line);
      c.drawLine(const Offset(263, 43), const Offset(277, 43), p.line);
      p.text(c, 'CO₂', const Offset(255, 72), size: 9);
      // N2
      p.text(c, 'N', const Offset(40, 115), size: 15, bold: true);
      p.text(c, 'N', const Offset(80, 115), size: 15, bold: true);
      for (final y in [111.0, 115.0, 119.0]) {
        c.drawLine(Offset(48, y), Offset(72, y), p.line);
      }
      d(const Offset(30, 115), -3);
      d(const Offset(30, 115), 3);
      d(const Offset(90, 115), -3);
      d(const Offset(90, 115), 3);
      p.text(c, 'N₂', const Offset(60, 140), size: 9);
      // HCl
      p.text(c, 'H', const Offset(140, 115), size: 15, bold: true);
      p.text(c, 'Cl', const Offset(172, 115), size: 15, bold: true);
      c.drawLine(const Offset(149, 115), const Offset(160, 115), p.line);
      d(const Offset(172, 100), -4);
      d(const Offset(172, 100), 4);
      d(const Offset(172, 130), -4);
      d(const Offset(172, 130), 4);
      d(const Offset(190, 115), 0, -4);
      d(const Offset(190, 115), 0, 4);
      p.text(c, 'HCl', const Offset(160, 145), size: 9);
      // CH4
      p.text(c, 'C', const Offset(255, 115), size: 15, bold: true);
      p.text(c, 'H', const Offset(255, 85 + 12), size: 12, bold: true);
      p.text(c, 'H', const Offset(255, 150), size: 12, bold: true);
      p.text(c, 'H', const Offset(225, 115), size: 12, bold: true);
      p.text(c, 'H', const Offset(285, 115), size: 12, bold: true);
      p.text(c, 'CH₄', const Offset(255, 165), size: 9);
    },
    tags: 'lewis yapıları molekül nokta h2o nh3 co2 n2 hcl ch4 ortaklanmamış',
  ),
  WbArtItem(
    'kim_iyonik_kovalent',
    'İyonik ve kovalent bağ',
    300,
    190,
    (c, p) {
      p.text(
        c,
        'İyonik bağ (NaCl)',
        const Offset(75, 15),
        size: 10,
        bold: true,
      );
      _atom(c, p, const Offset(40, 70), 22, WbArtColors.purple, 'Na');
      _atom(c, p, const Offset(115, 70), 28, WbArtColors.green, 'Cl');
      p.arrow(
        c,
        const Offset(60, 45),
        const Offset(92, 45),
        c: WbArtColors.blue,
        size: 6,
      );
      p.text(
        c,
        'e⁻',
        const Offset(75, 35),
        size: 9,
        c: WbArtColors.blue,
        bold: true,
      );
      p.text(c, 'Na⁺', const Offset(40, 115), size: 11, bold: true);
      p.text(c, 'Cl⁻', const Offset(115, 115), size: 11, bold: true);
      p.text(c, 'Elektron alışverişi', const Offset(75, 145), size: 9);
      p.text(c, 'Metal + ametal', const Offset(75, 160), size: 9);
      c.drawLine(const Offset(150, 20), const Offset(150, 170), p.thin());
      p.text(
        c,
        'Kovalent bağ (H₂)',
        const Offset(225, 15),
        size: 10,
        bold: true,
      );
      c.drawCircle(const Offset(205, 70), 26, p.fill(WbArtColors.blue, 0.2));
      c.drawCircle(const Offset(245, 70), 26, p.fill(WbArtColors.red, 0.2));
      c.drawCircle(const Offset(205, 70), 26, p.thin());
      c.drawCircle(const Offset(245, 70), 26, p.thin());
      c.drawCircle(const Offset(218, 70), 2.5, p.solid);
      c.drawCircle(const Offset(232, 70), 2.5, p.solid);
      p.text(c, 'H', const Offset(193, 70), size: 11, bold: true);
      p.text(c, 'H', const Offset(257, 70), size: 11, bold: true);
      p.text(c, 'H : H', const Offset(225, 115), size: 11, bold: true);
      p.text(c, 'Ortak elektron çifti', const Offset(225, 145), size: 9);
      p.text(c, 'Ametal + ametal', const Offset(225, 160), size: 9);
    },
    tags:
        'iyonik bağ kovalent bağ karşılaştırma elektron alışverişi ortaklaşma',
  ),
  WbArtItem(
    'kim_benzen',
    'Benzen halkası (C₆H₆)',
    220,
    220,
    (c, p) {
      const ctr = Offset(110, 100);
      final pts = WbArtPen.regular(ctr, 55, 6);
      c.drawPath(WbArtPen.poly(pts), p.line);
      for (int i = 0; i < 6; i += 2) {
        final a = pts[i];
        final b = pts[(i + 1) % 6];
        final mid = (a + b) / 2;
        final tw = ctr + (mid - ctr) * 0.78;
        final ra = ctr + (a - ctr) * 0.78;
        final rb = ctr + (b - ctr) * 0.78;
        c.drawLine(ra + (tw - ra) * 0.15, rb + (tw - rb) * 0.15, p.line);
      }
      for (int i = 0; i < 6; i++) {
        final out = ctr + (pts[i] - ctr) * 1.35;
        c.drawLine(pts[i], ctr + (pts[i] - ctr) * 1.25, p.thin());
        p.text(c, 'H', out, size: 10, c: WbArtColors.blue);
      }
      p.text(
        c,
        'C₆H₆ – benzen (aromatik halka)',
        const Offset(110, 195),
        size: 10,
        bold: true,
      );
    },
    tags: 'benzen halka aromatik organik c6h6',
  ),
  WbArtItem(
    'kim_etan',
    'Etan (C₂H₆)',
    240,
    150,
    (c, p) => _twoC(c, p, 1),
    tags: 'etan alkan c2h6 organik hidrokarbon tekli bağ',
  ),
  WbArtItem(
    'kim_eten',
    'Eten (C₂H₄)',
    240,
    150,
    (c, p) => _twoC(c, p, 2),
    tags: 'eten etilen alken c2h4 organik çift bağ',
  ),
  WbArtItem(
    'kim_etin',
    'Etin (C₂H₂)',
    240,
    150,
    (c, p) => _twoC(c, p, 3),
    tags: 'etin asetilen alkin c2h2 organik üçlü bağ',
  ),
  WbArtItem(
    'kim_etanol',
    'Etanol (C₂H₅OH)',
    280,
    160,
    (c, p) {
      final cs = [const Offset(75, 70), const Offset(135, 70)];
      const o = Offset(195, 70);
      _bond(c, p, cs[0], cs[1]);
      _bond(c, p, cs[1], o);
      final hs = [
        const Offset(75, 22),
        const Offset(75, 118),
        const Offset(27, 70),
        const Offset(135, 22),
        const Offset(135, 118),
        const Offset(235, 100),
      ];
      final from = [cs[0], cs[0], cs[0], cs[1], cs[1], o];
      for (int i = 0; i < hs.length; i++) {
        _bond(c, p, from[i], hs[i]);
        _atom(c, p, hs[i], 10, WbArtColors.lightBlue, 'H', ts: 9);
      }
      for (final k in cs) {
        _atom(c, p, k, 15, WbArtColors.gray, 'C');
      }
      _atom(c, p, o, 15, WbArtColors.red, 'O');
      p.text(
        c,
        'Hidroksil (–OH)',
        const Offset(235, 125),
        size: 8,
        c: WbArtColors.red,
      );
      p.text(
        c,
        'Etanol CH₃CH₂OH (alkol)',
        const Offset(140, 150),
        size: 10,
        bold: true,
      );
    },
    tags: 'etanol alkol c2h5oh organik hidroksil',
  ),
  WbArtItem(
    'kim_glikoz',
    'Glikoz halkası',
    220,
    220,
    (c, p) {
      final pts = WbArtPen.regular(
        const Offset(110, 100),
        48,
        6,
        math.pi / 6 * 3 + math.pi / 3,
      );
      final path = WbArtPen.poly(pts);
      c.drawPath(path, p.fill(WbArtColors.yellow, 0.2));
      c.drawPath(path, p.line);
      p.text(c, 'O', pts[0], size: 12, bold: true, c: WbArtColors.red);
      final lab = ['', 'CH₂OH', 'OH', 'OH', 'OH', 'OH'];
      for (int i = 1; i < 6; i++) {
        final dir = (pts[i] - const Offset(110, 100));
        final o = pts[i] + (dir / dir.distance) * 24;
        c.drawLine(pts[i], pts[i] + (dir / dir.distance) * 14, p.thin());
        p.text(c, lab[i], o, size: 9, c: WbArtColors.blue);
      }
      p.text(
        c,
        'α-D-Glikoz (C₆H₁₂O₆)',
        const Offset(110, 195),
        size: 10,
        bold: true,
      );
    },
    tags: 'glikoz şeker halka karbonhidrat c6h12o6',
  ),
];

void _twoC(Canvas c, WbArtPen p, int order) {
  const a = Offset(95, 70);
  const b = Offset(145, 70);
  _bond(c, p, a, b, order);
  final up = order == 1;
  final pos = <List<Offset>>[];
  if (order == 1) {
    pos.add([a, const Offset(95, 25)]);
    pos.add([a, const Offset(95, 115)]);
    pos.add([a, const Offset(55, 70)]);
    pos.add([b, const Offset(145, 25)]);
    pos.add([b, const Offset(145, 115)]);
    pos.add([b, const Offset(185, 70)]);
  } else if (order == 2) {
    pos.add([a, const Offset(70, 30)]);
    pos.add([a, const Offset(70, 110)]);
    pos.add([b, const Offset(170, 30)]);
    pos.add([b, const Offset(170, 110)]);
  } else {
    pos.add([a, const Offset(50, 70)]);
    pos.add([b, const Offset(190, 70)]);
  }
  for (final h in pos) {
    _bond(c, p, h[0], h[1]);
    _atom(c, p, h[1], 10, WbArtColors.lightBlue, 'H', ts: 9);
  }
  _atom(c, p, a, 15, WbArtColors.gray, 'C');
  _atom(c, p, b, 15, WbArtColors.gray, 'C');
  final names = [
    '',
    'Etan  C₂H₆  (alkan, tekli bağ)',
    'Eten  C₂H₄  (alken, çift bağ)',
    'Etin  C₂H₂  (alkin, üçlü bağ)',
  ];
  p.text(c, names[order], const Offset(120, 138), size: 10, bold: true);
  if (up) {
    p.text(c, '', const Offset(0, 0));
  }
}

// ───────────────────────── Maddenin halleri ─────────────────────────

void _particles(
  Canvas c,
  WbArtPen p,
  Rect r,
  int n,
  double rad,
  Color col,
  int seed, {
  bool arrows = false,
}) {
  final rnd = math.Random(seed);
  final pts = <Offset>[];
  int tries = 0;
  while (pts.length < n && tries < 600) {
    tries++;
    final o = Offset(
      r.left + rad + rnd.nextDouble() * (r.width - 2 * rad),
      r.top + rad + rnd.nextDouble() * (r.height - 2 * rad),
    );
    if (pts.every((q) => (q - o).distance > rad * 2.1)) pts.add(o);
  }
  for (final o in pts) {
    c.drawCircle(o, rad, p.fill(col, 0.4));
    c.drawCircle(o, rad, p.stroke(col, 0.35));
    if (arrows) {
      final a = rnd.nextDouble() * 6.28;
      p.arrow(
        c,
        o,
        o + Offset(math.cos(a), math.sin(a)) * 11,
        size: 3.5,
        c: WbArtColors.gray,
      );
    }
  }
}

void _stateBox(Canvas c, WbArtPen p, Rect r, String title) {
  c.drawRect(r, p.thin());
  p.text(c, title, Offset(r.center.dx, r.bottom + 12), size: 10, bold: true);
}

final List<WbArtItem> _chemStates = [
  WbArtItem(
    'kim_uc_hal',
    'Katı – sıvı – gaz tanecik modeli',
    320,
    160,
    (c, p) {
      const r = 10.0;
      const b1 = Rect.fromLTWH(10, 10, 90, 100);
      const b2 = Rect.fromLTWH(115, 10, 90, 100);
      const b3 = Rect.fromLTWH(220, 10, 90, 100);
      _stateBox(c, p, b1, 'Katı');
      _stateBox(c, p, b2, 'Sıvı');
      _stateBox(c, p, b3, 'Gaz');
      for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
          final o = Offset(b1.left + 14 + i * 20.5, b1.top + 14 + j * 22.0);
          c.drawCircle(o, r - 1, p.fill(WbArtColors.blue, 0.4));
          c.drawCircle(o, r - 1, p.stroke(WbArtColors.blue, 0.35));
        }
      }
      _particles(
        c,
        p,
        Rect.fromLTWH(b2.left, b2.top + 30, b2.width, b2.height - 30),
        12,
        8,
        WbArtColors.teal,
        3,
      );
      _particles(c, p, b3, 6, 6, WbArtColors.orange, 5, arrows: true);
      p.text(c, 'Düzenli, sıkı', Offset(b1.center.dx, 135), size: 8);
      p.text(
        c,
        'Düzensiz, birbirine yakın',
        Offset(b2.center.dx, 135),
        size: 8,
      );
      p.text(c, 'Çok uzak, hızlı', Offset(b3.center.dx, 135), size: 8);
    },
    tags: 'katı sıvı gaz tanecik modeli maddenin halleri',
  ),
  WbArtItem(
    'kim_hal_degisimi',
    'Hal değişimleri',
    320,
    220,
    (c, p) {
      final names = ['KATI', 'SIVI', 'GAZ'];
      final cols = [WbArtColors.blue, WbArtColors.teal, WbArtColors.orange];
      for (int i = 0; i < 3; i++) {
        final r = Rect.fromLTWH(15.0 + i * 110, 85, 70, 50);
        _box(c, p, r, cols[i], 0.25);
        p.text(c, names[i], r.center, size: 11, bold: true);
      }
      final lab = [
        ['Erime', 'Donma', 0],
        ['Buharlaşma', 'Yoğuşma', 1],
      ];
      for (final l in lab) {
        final i = l[2] as int;
        final x0 = 85.0 + i * 110;
        p.arrow(
          c,
          Offset(x0 + 2, 100),
          Offset(x0 + 38, 100),
          c: WbArtColors.red,
          size: 6,
        );
        p.arrow(
          c,
          Offset(x0 + 38, 122),
          Offset(x0 + 2, 122),
          c: WbArtColors.blue,
          size: 6,
        );
        p.text(
          c,
          l[0] as String,
          Offset(x0 + 20, 90),
          size: 8,
          c: WbArtColors.red,
          bold: true,
        );
        p.text(
          c,
          l[1] as String,
          Offset(x0 + 20, 133),
          size: 8,
          c: WbArtColors.blue,
          bold: true,
        );
      }
      final up = Path()
        ..moveTo(50, 85)
        ..cubicTo(50, 20, 250, 20, 250, 80);
      c.drawPath(up, p.stroke(WbArtColors.red, 0.8));
      p.arrow(
        c,
        const Offset(250, 55),
        const Offset(250, 83),
        c: WbArtColors.red,
        size: 6,
        line: false,
      );
      p.text(
        c,
        'Süblimleşme',
        const Offset(150, 40),
        size: 9,
        c: WbArtColors.red,
        bold: true,
      );
      final dn = Path()
        ..moveTo(250, 138)
        ..cubicTo(250, 205, 50, 205, 50, 140);
      c.drawPath(dn, p.stroke(WbArtColors.blue, 0.8));
      p.arrow(
        c,
        const Offset(50, 165),
        const Offset(50, 138),
        c: WbArtColors.blue,
        size: 6,
        line: false,
      );
      p.text(
        c,
        'Kırağılaşma',
        const Offset(150, 183),
        size: 9,
        c: WbArtColors.blue,
        bold: true,
      );
      p.text(
        c,
        'Isı alır (endotermik)',
        const Offset(310, 10),
        size: 8,
        c: WbArtColors.red,
        anchor: 'right',
      );
      p.text(
        c,
        'Isı verir (ekzotermik)',
        const Offset(310, 22),
        size: 8,
        c: WbArtColors.blue,
        anchor: 'right',
      );
    },
    tags: 'hal değişimi erime donma buharlaşma yoğuşma süblimleşme kırağılaşma',
  ),
  WbArtItem(
    'kim_madde_siniflari',
    'Element – bileşik – karışım modeli',
    320,
    190,
    (c, p) {
      final titles = [
        'Element',
        'Bileşik',
        'Element karışımı',
        'Bileşik karışımı',
      ];
      for (int i = 0; i < 4; i++) {
        final r = Rect.fromLTWH(
          10.0 + (i % 2) * 155,
          8.0 + (i ~/ 2) * 90,
          145,
          62,
        );
        c.drawRect(r, p.thin());
        p.text(
          c,
          titles[i],
          Offset(r.center.dx, r.bottom + 10),
          size: 9,
          bold: true,
        );
        final rnd = math.Random(i + 7);
        for (int k = 0; k < 6; k++) {
          final o = Offset(
            r.left + 18 + (k % 3) * 40 + rnd.nextDouble() * 10,
            r.top + 16 + (k ~/ 3) * 30 + rnd.nextDouble() * 6,
          );
          if (i == 0) {
            _atom(c, p, o, 8, WbArtColors.blue, '', ts: 6);
          } else if (i == 1) {
            _atom(
              c,
              p,
              o + const Offset(-7, 0),
              7,
              WbArtColors.blue,
              '',
              ts: 6,
            );
            _atom(c, p, o + const Offset(7, 0), 7, WbArtColors.red, '', ts: 6);
          } else if (i == 2) {
            _atom(
              c,
              p,
              o,
              8,
              k.isEven ? WbArtColors.blue : WbArtColors.green,
              '',
              ts: 6,
            );
          } else {
            if (k.isEven) {
              _atom(
                c,
                p,
                o + const Offset(-7, 0),
                7,
                WbArtColors.blue,
                '',
                ts: 6,
              );
              _atom(
                c,
                p,
                o + const Offset(7, 0),
                7,
                WbArtColors.red,
                '',
                ts: 6,
              );
            } else {
              _atom(
                c,
                p,
                o + const Offset(-7, 0),
                7,
                WbArtColors.green,
                '',
                ts: 6,
              );
              _atom(
                c,
                p,
                o + const Offset(7, 0),
                7,
                WbArtColors.yellow,
                '',
                ts: 6,
              );
            }
          }
        }
      }
    },
    tags: 'saf madde karışım element bileşik tanecik modeli sınıflandırma',
  ),
  WbArtItem(
    'kim_cozelti_sus_emul',
    'Çözelti – süspansiyon – emülsiyon',
    330,
    190,
    (c, p) {
      final titles = ['Çözelti', 'Süspansiyon', 'Emülsiyon'];
      for (int i = 0; i < 3; i++) {
        final x = 10.0 + i * 110;
        final b = WbArtPen.poly([
          Offset(x, 20),
          Offset(x + 3, 26),
          Offset(x + 3, 130),
          Offset(x + 87, 130),
          Offset(x + 87, 26),
          Offset(x + 90, 20),
        ], close: false);
        _glass(c, p, b);
        _liq(c, p, b, 45, WbArtColors.blue, 0.25);
        final rnd = math.Random(i + 11);
        if (i == 0) {
          for (int k = 0; k < 24; k++) {
            c.drawCircle(
              Offset(x + 8 + rnd.nextDouble() * 74, 52 + rnd.nextDouble() * 72),
              1.8,
              p.fill(WbArtColors.purple, 0.8),
            );
          }
        } else if (i == 1) {
          for (int k = 0; k < 14; k++) {
            final y = 50 + math.pow(rnd.nextDouble(), 0.5) * 74;
            c.drawRect(
              Rect.fromCenter(
                center: Offset(x + 10 + rnd.nextDouble() * 70, y.toDouble()),
                width: 5,
                height: 5,
              ),
              p.fill(WbArtColors.brown, 0.7),
            );
          }
        } else {
          for (int k = 0; k < 9; k++) {
            c.drawCircle(
              Offset(
                x + 12 + rnd.nextDouble() * 66,
                55 + rnd.nextDouble() * 68,
              ),
              5 + rnd.nextDouble() * 3,
              p.fill(WbArtColors.yellow, 0.7),
            );
          }
        }
        p.text(c, titles[i], Offset(x + 45, 150), size: 10, bold: true);
      }
      p.text(c, 'Homojen', const Offset(55, 168), size: 8);
      p.text(c, 'Katı–sıvı (heterojen)', const Offset(165, 168), size: 8);
      p.text(c, 'Sıvı–sıvı (heterojen)', const Offset(275, 168), size: 8);
    },
    tags: 'çözelti süspansiyon emülsiyon karışım homojen heterojen',
  ),
];

// ───────────────────────── Gazlar / Termokimya ─────────────────────────

void _manometer(Canvas c, WbArtPen p, double x, bool open) {
  final bulb = Rect.fromLTWH(x, 25, 50, 50);
  c.drawOval(bulb, p.fill(WbArtColors.lightBlue, 0.2));
  c.drawOval(bulb, p.line);
  p.text(c, 'Gaz', bulb.center, size: 9);
  final u = Path()
    ..moveTo(x + 25, 75)
    ..lineTo(x + 25, 150)
    ..arcToPoint(
      Offset(x + 65, 150),
      radius: const Radius.circular(20),
      clockwise: false,
    )
    ..lineTo(x + 65, 70);
  c.drawPath(u, p.line);
  c.save();
  c.clipPath(u);
  c.drawRect(
    Rect.fromLTRB(x + 20, 110, x + 70, 190),
    p.fill(WbArtColors.gray, 0.6),
  );
  c.drawRect(
    Rect.fromLTRB(x + 54, 95, x + 70, 110),
    p.fill(WbArtColors.gray, 0.6),
  );
  c.restore();
  c.drawLine(Offset(x + 15, 110), Offset(x + 80, 110), p.thin(0.4));
  c.drawLine(Offset(x + 15, 95), Offset(x + 80, 95), p.thin(0.4));
  p.arrow(c, Offset(x + 82, 102), Offset(x + 82, 95), size: 4);
  p.arrow(c, Offset(x + 82, 102), Offset(x + 82, 110), size: 4);
  p.text(c, 'h', Offset(x + 90, 102), size: 10, bold: true, anchor: 'left');
  if (!open) {
    c.drawLine(Offset(x + 54, 70), Offset(x + 76, 70), p.stroke(p.color, 2));
    p.text(c, 'Boşluk (vakum)', Offset(x + 60, 56), size: 8);
    p.text(c, 'P = h', Offset(x + 45, 205), size: 9);
  } else {
    p.text(c, 'Açık uç (P₀)', Offset(x + 64, 56), size: 8);
    p.arrow(
      c,
      Offset(x + 65, 68),
      Offset(x + 65, 78),
      size: 4,
      c: WbArtColors.red,
    );
    p.text(c, 'P = P₀ + h', Offset(x + 45, 205), size: 9);
  }
  p.text(c, 'Civa', Offset(x + 45, 175), size: 8, c: WbArtColors.gray);
}

void _energy(Canvas c, WbArtPen p, bool exo) {
  _axes(
    c,
    p,
    const Offset(35, 190),
    230,
    175,
    'Tepkime koordinatı',
    'Potansiyel enerji',
  );
  final yr = exo ? 90.0 : 130.0;
  final yp = exo ? 140.0 : 80.0;
  const yk = 35.0;
  final path = Path()
    ..moveTo(45, yr)
    ..lineTo(75, yr)
    ..cubicTo(100, yr, 100, yk, 130, yk)
    ..cubicTo(160, yk, 160, yp, 190, yp)
    ..lineTo(240, yp);
  c.drawPath(path, p.line);
  final cat = Path()
    ..moveTo(75, yr)
    ..cubicTo(100, yr, 100, 62, 130, 62)
    ..cubicTo(160, 62, 160, yp, 190, yp);
  c.drawPath(cat, p.stroke(WbArtColors.green, 0.8));
  p.arrow(c, Offset(100, yr), Offset(100, yk + 2), size: 5, c: WbArtColors.red);
  p.text(
    c,
    'Eₐ',
    Offset(92, (yr + yk) / 2),
    size: 10,
    c: WbArtColors.red,
    bold: true,
    anchor: 'right',
  );
  p.arrow(
    c,
    Offset(225, yr),
    Offset(225, yp),
    size: 5,
    c: exo ? WbArtColors.blue : WbArtColors.orange,
  );
  c.drawLine(Offset(200, yr), Offset(225, yr), p.thin(0.4));
  p.text(
    c,
    exo ? 'ΔH < 0' : 'ΔH > 0',
    Offset(215, (yr + yp) / 2),
    size: 10,
    bold: true,
    anchor: 'right',
  );
  p.text(c, 'Girenler', Offset(60, yr - 10), size: 9);
  p.text(c, 'Ürünler', Offset(215, yp - (exo ? -12 : 10)), size: 9);
  p.text(c, 'Aktifleşmiş kompleks', Offset(132, yk - 10), size: 8);
  p.text(
    c,
    'Katalizörlü yol (Eₐ düşük)',
    Offset(230, 62),
    size: 8,
    c: WbArtColors.green,
    anchor: 'right',
  );
  p.text(
    c,
    exo ? 'Ekzotermik tepkime' : 'Endotermik tepkime',
    const Offset(150, 214),
    size: 11,
    bold: true,
  );
}

final List<WbArtItem> _chemGases = [
  WbArtItem(
    'kim_piston_gaz',
    'Pistonlu kapta gaz',
    240,
    240,
    (c, p) {
      final cyl = Path()
        ..moveTo(60, 40)
        ..lineTo(60, 200)
        ..lineTo(180, 200)
        ..lineTo(180, 40);
      c.drawPath(cyl, p.line);
      c.drawRect(
        const Rect.fromLTRB(62, 200, 178, 208),
        p.fill(WbArtColors.gray, 0.3),
      );
      c.drawRect(
        const Rect.fromLTRB(60, 82, 180, 92),
        p.fill(WbArtColors.gray, 0.5),
      );
      c.drawRect(const Rect.fromLTRB(60, 82, 180, 92), p.line);
      c.drawLine(
        const Offset(120, 82),
        const Offset(120, 40),
        p.stroke(WbArtColors.gray, 1.5),
      );
      c.drawRect(
        const Rect.fromLTRB(95, 18, 145, 40),
        p.fill(WbArtColors.brown, 0.4),
      );
      c.drawRect(const Rect.fromLTRB(95, 18, 145, 40), p.line);
      p.text(c, 'm', const Offset(120, 29), size: 10, bold: true);
      _particles(
        c,
        p,
        const Rect.fromLTRB(64, 95, 176, 198),
        9,
        5,
        WbArtColors.orange,
        9,
        arrows: true,
      );
      p.arrow(
        c,
        const Offset(30, 87),
        const Offset(30, 130),
        c: WbArtColors.red,
        size: 5,
      );
      p.text(
        c,
        'P',
        const Offset(30, 75),
        size: 11,
        bold: true,
        c: WbArtColors.red,
      );
      p.arrow(c, const Offset(205, 92), const Offset(205, 198), size: 5);
      p.arrow(c, const Offset(205, 198), const Offset(205, 92), size: 5);
      p.text(
        c,
        'V',
        const Offset(215, 145),
        size: 11,
        bold: true,
        anchor: 'left',
      );
      p.text(
        c,
        'Gaz (n, T)',
        const Offset(120, 150),
        size: 9,
        c: WbArtColors.gray,
      );
      p.text(c, 'PV = nRT', const Offset(120, 228), size: 11, bold: true);
    },
    tags: 'piston gaz basınç hacim sıcaklık silindir ideal gaz',
  ),
  WbArtItem(
    'kim_boyle',
    'Boyle yasası (P–V)',
    240,
    220,
    (c, p) {
      _axes(c, p, const Offset(40, 175), 180, 150, 'V', 'P');
      const area = Rect.fromLTRB(55, 40, 210, 170);
      final pth = Path();
      for (int i = 0; i <= 40; i++) {
        final v = 0.12 + i / 40 * 0.88;
        final o = Offset(
          area.left + area.width * v,
          area.bottom - area.height * (0.12 / v),
        );
        if (i == 0) {
          pth.moveTo(o.dx, o.dy);
        } else {
          pth.lineTo(o.dx, o.dy);
        }
      }
      c.drawPath(pth, p.stroke(WbArtColors.red, 1.2));
      p.dashed(c, const Offset(100, 175), const Offset(100, 100));
      p.dashed(c, const Offset(40, 100), const Offset(100, 100));
      p.text(c, 'P₁V₁ = P₂V₂', const Offset(150, 70), size: 10, bold: true);
      p.text(c, 'T sabit, P · V = sabit', const Offset(150, 90), size: 8);
      p.text(c, 'Boyle yasası', const Offset(120, 205), size: 11, bold: true);
    },
    tags: 'boyle yasası basınç hacim grafik izotermal',
  ),
  WbArtItem(
    'kim_charles',
    'Charles yasası (V–T)',
    240,
    220,
    (c, p) {
      _axes(c, p, const Offset(70, 175), 150, 150, 'T (°C)', 'V');
      c.drawLine(
        const Offset(88, 175),
        const Offset(210, 45),
        p.stroke(WbArtColors.red, 1.2),
      );
      p.dashed(
        c,
        const Offset(88, 175),
        const Offset(46, 175),
        paint: p.stroke(WbArtColors.red, 0.6),
      );
      p.text(c, '–273 °C', const Offset(70, 188), size: 8);
      c.drawCircle(const Offset(88, 175), 3, p.solid);
      p.text(c, '0', const Offset(112, 188), size: 8);
      p.text(
        c,
        'P sabit, V / T = sabit',
        const Offset(130, 80),
        size: 9,
        anchor: 'left',
      );
      p.text(c, 'Charles yasası', const Offset(120, 210), size: 11, bold: true);
    },
    tags: 'charles yasası hacim sıcaklık grafik izobar mutlak sıfır',
  ),
  WbArtItem(
    'kim_manometre',
    'Açık ve kapalı uçlu manometre',
    320,
    230,
    (c, p) {
      _manometer(c, p, 20, true);
      _manometer(c, p, 180, false);
      p.text(c, 'Açık uçlu', const Offset(65, 222), size: 10, bold: true);
      p.text(c, 'Kapalı uçlu', const Offset(225, 222), size: 10, bold: true);
    },
    tags: 'manometre açık uçlu kapalı uçlu gaz basıncı civa',
  ),
  WbArtItem(
    'kim_ekzotermik',
    'Ekzotermik tepkime enerji profili',
    280,
    225,
    (c, p) => _energy(c, p, true),
    tags: 'ekzotermik tepkime enerji profili aktivasyon enerjisi katalizör',
  ),
  WbArtItem(
    'kim_endotermik',
    'Endotermik tepkime enerji profili',
    280,
    225,
    (c, p) => _energy(c, p, false),
    tags: 'endotermik tepkime enerji profili aktivasyon enerjisi katalizör',
  ),
  WbArtItem(
    'kim_isinma_egrisi',
    'Hal değişim (ısınma) eğrisi',
    300,
    230,
    (c, p) {
      _axes(c, p, const Offset(40, 190), 245, 165, 'Isı (Q)', 'Sıcaklık (°C)');
      final pts = [
        const Offset(50, 175),
        const Offset(90, 130),
        const Offset(125, 130),
        const Offset(165, 90),
        const Offset(200, 90),
        const Offset(240, 45),
      ];
      final pl = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (int i = 1; i < pts.length; i++) {
        pl.lineTo(pts[i].dx, pts[i].dy);
      }
      c.drawPath(pl, p.stroke(WbArtColors.red, 1.3));
      p.dashed(c, const Offset(40, 130), const Offset(90, 130));
      p.dashed(c, const Offset(40, 90), const Offset(165, 90));
      p.text(c, 'EN', const Offset(36, 130), size: 8, anchor: 'right');
      p.text(c, 'KN', const Offset(36, 90), size: 8, anchor: 'right');
      p.text(c, 'Katı', const Offset(60, 135), size: 9, bold: true);
      p.text(c, 'Katı+Sıvı', const Offset(108, 145), size: 8, bold: true);
      p.text(c, 'Sıvı', const Offset(150, 118), size: 9, bold: true);
      p.text(c, 'Sıvı+Gaz', const Offset(183, 105), size: 8, bold: true);
      p.text(c, 'Gaz', const Offset(235, 68), size: 9, bold: true);
      p.text(
        c,
        'Isınma eğrisi (EN: erime, KN: kaynama noktası)',
        const Offset(150, 218),
        size: 9,
        bold: true,
      );
    },
    tags:
        'hal değişim ısınma eğrisi erime noktası kaynama noktası sıcaklık ısı grafik',
  ),
  WbArtItem(
    'kim_cozunurluk',
    'Çözünürlük–sıcaklık eğrisi',
    280,
    230,
    (c, p) {
      _axes(
        c,
        p,
        const Offset(40, 185),
        225,
        160,
        'Sıcaklık (°C)',
        'Çözünürlük (g/100 g su)',
      );
      const area = Rect.fromLTRB(45, 45, 255, 180);
      _plot(c, p.stroke(WbArtColors.red, 1.2), area, (t) => 0.1 + 0.85 * t * t);
      _plot(c, p.stroke(WbArtColors.blue, 1.2), area, (t) => 0.38 + 0.08 * t);
      _plot(c, p.stroke(WbArtColors.green, 1.2), area, (t) => 0.55 - 0.45 * t);
      p.text(
        c,
        'KNO₃',
        const Offset(235, 55),
        size: 9,
        c: WbArtColors.red,
        bold: true,
      );
      p.text(
        c,
        'NaCl',
        const Offset(235, 105),
        size: 9,
        c: WbArtColors.blue,
        bold: true,
      );
      p.text(
        c,
        'Gaz / Ce₂(SO₄)₃',
        const Offset(215, 160),
        size: 8,
        c: WbArtColors.green,
        bold: true,
      );
      p.text(c, 'Doymamış', const Offset(75, 78), size: 8);
      p.text(c, 'Aşırı doymuş', const Offset(75, 168), size: 8);
      p.text(c, 'Eğri üstü: doygun', const Offset(140, 35), size: 8);
      p.text(
        c,
        'Çözünürlük eğrisi',
        const Offset(140, 218),
        size: 10,
        bold: true,
      );
    },
    tags: 'çözünürlük sıcaklık eğrisi doygun doymamış kno3 nacl',
  ),
  WbArtItem(
    'kim_hiz_derisim',
    'Tepkime hızı – derişim grafiği',
    260,
    220,
    (c, p) {
      _axes(c, p, const Offset(40, 175), 200, 150, 'Derişim [A]', 'Hız');
      const area = Rect.fromLTRB(45, 40, 235, 172);
      _plot(c, p.stroke(WbArtColors.green, 1.2), area, (t) => 0.4);
      _plot(c, p.stroke(WbArtColors.blue, 1.2), area, (t) => 0.9 * t);
      _plot(c, p.stroke(WbArtColors.red, 1.2), area, (t) => 0.9 * t * t);
      p.text(
        c,
        '0. mertebe',
        const Offset(238, 110),
        size: 8,
        anchor: 'right',
        c: WbArtColors.green,
      );
      p.text(
        c,
        '1. mertebe',
        const Offset(180, 62),
        size: 8,
        anchor: 'right',
        c: WbArtColors.blue,
      );
      p.text(
        c,
        '2. mertebe',
        const Offset(235, 48),
        size: 8,
        anchor: 'right',
        c: WbArtColors.red,
      );
      p.text(c, 'Hız = k [A]ⁿ', const Offset(100, 55), size: 9, bold: true);
      p.text(c, 'Hız – derişim', const Offset(130, 208), size: 11, bold: true);
    },
    tags: 'tepkime hızı derişim grafik mertebe kinetik',
  ),
  WbArtItem(
    'kim_denge_le_chatelier',
    'Denge – Le Chatelier grafiği',
    280,
    220,
    (c, p) {
      _axes(c, p, const Offset(40, 175), 225, 150, 'Zaman', 'Derişim');
      const area = Rect.fromLTRB(45, 40, 255, 172);
      double a(double t) {
        if (t < 0.45) return 0.5 + 0.4 * math.exp(-t * 9);
        final a0 = 0.5 + 0.4 * math.exp(-0.45 * 9);
        return 0.62 + (a0 + 0.25 - 0.62) * math.exp(-(t - 0.45) * 10);
      }

      double b(double t) {
        if (t < 0.45) return 0.5 - 0.4 * math.exp(-t * 9);
        final b0 = 0.5 - 0.4 * math.exp(-0.45 * 9);
        return b0 + (0.66 - b0) * (1 - math.exp(-(t - 0.45) * 10));
      }

      _plot(c, p.stroke(WbArtColors.blue, 1.2), area, (t) => a(t) * 0.9);
      _plot(c, p.stroke(WbArtColors.red, 1.2), area, (t) => b(t) * 0.9);
      final tx = area.left + area.width * 0.45;
      p.dashed(c, Offset(tx, 175), Offset(tx, 45));
      p.text(c, 'Girenler ekle', Offset(tx + 4, 48), size: 8, anchor: 'left');
      p.text(
        c,
        'Girenler',
        const Offset(70, 70),
        size: 9,
        c: WbArtColors.blue,
        bold: true,
      );
      p.text(
        c,
        'Ürünler',
        const Offset(70, 150),
        size: 9,
        c: WbArtColors.red,
        bold: true,
      );
      p.text(c, 'Denge', const Offset(95, 110), size: 8);
      p.text(c, 'Yeni denge', const Offset(215, 120), size: 8);
      p.text(
        c,
        'Le Chatelier ilkesi',
        const Offset(140, 208),
        size: 11,
        bold: true,
      );
    },
    tags: 'denge le chatelier derişim zaman grafik kimyasal denge',
  ),
];

// ───────────────────────── Asit–baz / Organik / Diğer ─────────────────────────

void _hazard(
  Canvas c,
  WbArtPen p,
  String label,
  void Function(Canvas, WbArtPen) icon,
) {
  final d = WbArtPen.poly(const [
    Offset(100, 10),
    Offset(190, 100),
    Offset(100, 190),
    Offset(10, 100),
  ]);
  c.drawPath(d, p.fill(Colors.white, 0.9));
  c.drawPath(d, p.stroke(WbArtColors.red, 3.5));
  icon(c, p);
  p.text(c, label, const Offset(100, 212), size: 12, bold: true);
}

final List<WbArtItem> _chemMisc = [
  WbArtItem(
    'kim_ph_skala',
    'pH skalası',
    320,
    170,
    (c, p) {
      const rect = Rect.fromLTWH(20, 40, 280, 28);
      final sh = const LinearGradient(
        colors: [
          Color(0xFFDC2626),
          Color(0xFFF97316),
          Color(0xFFFACC15),
          Color(0xFF84CC16),
          Color(0xFF22C55E),
          Color(0xFF14B8A6),
          Color(0xFF3B82F6),
          Color(0xFF7C3AED),
        ],
      ).createShader(rect);
      c.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(5)),
        Paint()..shader = sh,
      );
      c.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(5)),
        p.line,
      );
      for (int i = 0; i <= 14; i++) {
        final x = 20 + 280 * i / 14;
        c.drawLine(Offset(x, 68), Offset(x, 74), p.thin());
        p.text(c, '$i', Offset(x, 83), size: 9, bold: true);
      }
      p.arrow(
        c,
        const Offset(150, 28),
        const Offset(30, 28),
        size: 5,
        c: WbArtColors.red,
      );
      p.arrow(
        c,
        const Offset(170, 28),
        const Offset(290, 28),
        size: 5,
        c: WbArtColors.blue,
      );
      p.text(
        c,
        'Asidik',
        const Offset(90, 14),
        size: 10,
        bold: true,
        c: WbArtColors.red,
      );
      p.text(
        c,
        'Bazik',
        const Offset(230, 14),
        size: 10,
        bold: true,
        c: WbArtColors.blue,
      );
      p.text(c, 'Nötr', const Offset(160, 14), size: 9, bold: true);
      final ex = [
        ['Pil asidi', 0.0],
        ['Mide özü', 1.5],
        ['Limon', 2.5],
        ['Kahve', 5.0],
        ['Saf su', 7.0],
        ['Kan', 7.4],
        ['Sabun', 10.0],
        ['Çamaşır suyu', 12.5],
      ];
      for (int i = 0; i < ex.length; i++) {
        final v = ex[i][1] as double;
        final x = 20 + 280 * v / 14;
        final y = 105.0 + (i % 2) * 22;
        c.drawLine(Offset(x, 90), Offset(x, y - 6), p.thin(0.4));
        p.text(c, ex[i][0] as String, Offset(x, y), size: 8);
      }
      p.text(
        c,
        'pH skalası ve indikatör renkleri',
        const Offset(160, 160),
        size: 10,
        bold: true,
      );
    },
    tags: 'ph skalası asit baz indikatör renk evrensel',
  ),
  WbArtItem(
    'kim_litmus',
    'Turnusol (litmus) kâğıdı',
    300,
    180,
    (c, p) {
      final cols = [
        ['Kırmızı turnusol', WbArtColors.red, WbArtColors.blue],
        ['Mavi turnusol', WbArtColors.blue, WbArtColors.red],
      ];
      for (int i = 0; i < 2; i++) {
        final y = 20.0 + i * 70;
        final c1 = cols[i][1] as Color;
        final c2 = cols[i][2] as Color;
        c.drawRect(Rect.fromLTWH(20, y, 70, 22), p.fill(c1, 0.6));
        c.drawRect(Rect.fromLTWH(20, y, 70, 22), p.thin());
        c.drawRect(Rect.fromLTWH(210, y, 70, 22), p.fill(c2, 0.6));
        c.drawRect(Rect.fromLTWH(210, y, 70, 22), p.thin());
        p.arrow(c, Offset(100, y + 11), Offset(200, y + 11), size: 6);
        p.text(c, cols[i][0] as String, Offset(55, y + 38), size: 8);
        p.text(
          c,
          i == 0 ? 'Baz ortamında' : 'Asit ortamında',
          Offset(150, y + 2),
          size: 8,
          anchor: 'bottom',
          bold: true,
        );
        p.text(
          c,
          i == 0 ? 'mavi olur' : 'kırmızı olur',
          Offset(245, y + 38),
          size: 8,
        );
      }
      p.text(
        c,
        'Turnusol kâğıdı: asit–baz tayini',
        const Offset(150, 165),
        size: 10,
        bold: true,
      );
    },
    tags: 'turnusol litmus kağıdı asit baz indikatör',
  ),
  WbArtItem('kim_ph_metre', 'pH metre', 240, 240, (c, p) {
    _box(c, p, const Rect.fromLTWH(20, 20, 90, 130), WbArtColors.gray, 0.25, 8);
    _box(c, p, const Rect.fromLTWH(30, 32, 70, 36), WbArtColors.green, 0.3, 4);
    p.text(c, '7.00', const Offset(65, 50), size: 16, bold: true);
    p.text(c, 'pH', const Offset(65, 82), size: 10, bold: true);
    for (int i = 0; i < 3; i++) {
      c.drawCircle(
        Offset(40.0 + i * 25, 115),
        8,
        p.fill(WbArtColors.gray, 0.5),
      );
      c.drawCircle(Offset(40.0 + i * 25, 115), 8, p.thin());
    }
    final cable = Path()
      ..moveTo(110, 100)
      ..cubicTo(150, 100, 140, 40, 165, 40)
      ..lineTo(165, 70);
    c.drawPath(cable, p.line);
    const probe = Rect.fromLTRB(158, 70, 172, 170);
    c.drawRRect(
      RRect.fromRectAndRadius(probe, const Radius.circular(5)),
      p.fill(WbArtColors.gray, 0.35),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(probe, const Radius.circular(5)),
      p.line,
    );
    final b = WbArtPen.poly(const [
      Offset(120, 140),
      Offset(125, 150),
      Offset(125, 215),
      Offset(215, 215),
      Offset(215, 150),
      Offset(220, 140),
    ], close: false);
    _glass(c, p, b);
    _liq(c, p, b, 165, WbArtColors.blue, 0.3);
    p.text(
      c,
      'Elektrot (prob)',
      const Offset(180, 60),
      size: 8,
      anchor: 'left',
    );
    p.text(c, 'Çözelti', const Offset(170, 200), size: 9);
    p.text(c, 'pH metre', const Offset(120, 233), size: 11, bold: true);
  }, tags: 'ph metre ölçüm elektrot asit baz'),
  WbArtItem(
    'kim_fonksiyonel_gruplar',
    'Fonksiyonel gruplar tablosu',
    320,
    230,
    (c, p) {
      final rows = [
        ['Grup', 'Formül', 'Örnek'],
        ['Alkol', '–OH', 'Etanol'],
        ['Aldehit', '–CHO', 'Metanal'],
        ['Keton', '>C=O', 'Propanon'],
        ['Karboksilik asit', '–COOH', 'Etanoik asit'],
        ['Ester', '–COO–', 'Etil asetat'],
        ['Eter', '–O–', 'Dietil eter'],
        ['Amin', '–NH₂', 'Metil amin'],
      ];
      const rh = 24.0;
      for (int i = 0; i < rows.length; i++) {
        final y = 15 + i * rh;
        if (i == 0) {
          c.drawRect(
            Rect.fromLTWH(10, y, 300, rh),
            p.fill(WbArtColors.purple, 0.3),
          );
        } else if (i.isEven) {
          c.drawRect(
            Rect.fromLTWH(10, y, 300, rh),
            p.fill(WbArtColors.gray, 0.15),
          );
        }
        p.text(
          c,
          rows[i][0],
          Offset(20, y + rh / 2),
          size: 10,
          bold: i == 0,
          anchor: 'left',
        );
        p.text(
          c,
          rows[i][1],
          Offset(140, y + rh / 2),
          size: 11,
          bold: true,
          anchor: 'left',
          c: i == 0 ? null : WbArtColors.red,
        );
        p.text(
          c,
          rows[i][2],
          Offset(215, y + rh / 2),
          size: 10,
          bold: i == 0,
          anchor: 'left',
        );
      }
      c.drawRect(Rect.fromLTWH(10, 15, 300, rh * rows.length), p.line);
      c.drawLine(
        const Offset(130, 15),
        Offset(130, 15 + rh * rows.length),
        p.thin(),
      );
      c.drawLine(
        const Offset(205, 15),
        Offset(205, 15 + rh * rows.length),
        p.thin(),
      );
    },
    tags:
        'fonksiyonel gruplar organik alkol aldehit keton asit ester eter amin tablo',
  ),
  WbArtItem(
    'kim_mol_kavrami',
    'Mol kavramı şeması',
    300,
    230,
    (c, p) {
      c.drawCircle(const Offset(150, 55), 38, p.fill(WbArtColors.purple, 0.25));
      c.drawCircle(const Offset(150, 55), 38, p.line);
      p.text(c, '1 MOL', const Offset(150, 55), size: 14, bold: true);
      final bx = [
        ['Kütle', 'MA (g/mol)', 15.0],
        ['Tanecik sayısı', '6,02×10²³', 115.0],
        ['Hacim (NŞA)', '22,4 L', 215.0],
      ];
      for (int i = 0; i < 3; i++) {
        final x = bx[i][2] as double;
        _box(
          c,
          p,
          Rect.fromLTWH(x, 150, 70, 40),
          [WbArtColors.blue, WbArtColors.green, WbArtColors.orange][i],
          0.25,
        );
        p.text(c, bx[i][0] as String, Offset(x + 35, 164), size: 8, bold: true);
        p.text(c, bx[i][1] as String, Offset(x + 35, 179), size: 8);
        final tgt = Offset(x + 30, 150);
        final src = Offset(150 + (i - 1) * 28 - 5, 93);
        p.arrow(c, src, tgt, size: 5);
        p.arrow(
          c,
          tgt + const Offset(10, 0),
          src + const Offset(10, 0),
          size: 5,
          c: WbArtColors.red,
        );
      }
      p.text(
        c,
        'n = m / MA  =  N / NA  =  V / 22,4',
        const Offset(150, 210),
        size: 10,
        bold: true,
      );
      p.text(c, 'NA = 6,02×10²³ tanecik/mol', const Offset(150, 225), size: 8);
    },
    tags: 'mol kavramı kütle tanecik hacim avogadro 22,4 köprü',
  ),
  WbArtItem(
    'kim_molarite',
    'Derişim (molarite) şablonu',
    280,
    230,
    (c, p) {
      final b = WbArtPen.poly(const [
        Offset(25, 40),
        Offset(30, 50),
        Offset(30, 150),
        Offset(110, 150),
        Offset(110, 50),
        Offset(115, 40),
      ], close: false);
      _glass(c, p, b);
      _liq(c, p, b, 70, WbArtColors.pink, 0.3);
      for (int i = 0; i < 10; i++) {
        c.drawCircle(
          Offset(40 + (i % 5) * 14.0, 90 + (i ~/ 5) * 24.0),
          3,
          p.fill(WbArtColors.purple, 0.8),
        );
      }
      p.text(c, 'Çözünen (n mol)', const Offset(70, 165), size: 9);
      p.text(c, 'V litre çözelti', const Offset(70, 180), size: 9);
      p.text(c, 'M = n / V', const Offset(200, 55), size: 18, bold: true);
      p.text(c, '(mol/L)', const Offset(200, 78), size: 10);
      p.text(c, 'n = m / MA', const Offset(200, 105), size: 11);
      p.text(
        c,
        'Örnek: 0,5 mol NaOH,',
        const Offset(135, 130),
        size: 9,
        anchor: 'left',
      );
      p.text(
        c,
        '1 L çözelti → 0,5 M',
        const Offset(135, 145),
        size: 9,
        anchor: 'left',
      );
      p.text(
        c,
        'M₁V₁ = M₂V₂ (seyreltme)',
        const Offset(140, 205),
        size: 10,
        bold: true,
      );
    },
    tags: 'molarite derişim mol litre çözelti seyreltme',
  ),
  WbArtItem(
    'kim_redoks',
    'Redoks – elektron aktarımı',
    300,
    200,
    (c, p) {
      _atom(c, p, const Offset(60, 90), 30, WbArtColors.gray, 'Zn');
      _atom(
        c,
        p,
        const Offset(240, 90),
        30,
        WbArtColors.orange,
        'Cu²⁺',
        ts: 12,
      );
      final arc = Path()
        ..moveTo(70, 58)
        ..quadraticBezierTo(150, 8, 230, 58);
      c.drawPath(arc, p.stroke(WbArtColors.blue, 1));
      p.arrow(
        c,
        const Offset(205, 40),
        const Offset(230, 58),
        c: WbArtColors.blue,
        size: 7,
        line: false,
      );
      p.text(
        c,
        '2e⁻',
        const Offset(150, 20),
        size: 12,
        bold: true,
        c: WbArtColors.blue,
      );
      p.text(
        c,
        'Yükseltgenir',
        const Offset(60, 135),
        size: 10,
        bold: true,
        c: WbArtColors.red,
      );
      p.text(c, '(e⁻ verir, indirgen)', const Offset(60, 150), size: 8);
      p.text(
        c,
        'İndirgenir',
        const Offset(240, 135),
        size: 10,
        bold: true,
        c: WbArtColors.blue,
      );
      p.text(c, '(e⁻ alır, yükseltgen)', const Offset(240, 150), size: 8);
      p.text(c, 'Zn → Zn²⁺ + 2e⁻', const Offset(60, 170), size: 9);
      p.text(c, 'Cu²⁺ + 2e⁻ → Cu', const Offset(240, 170), size: 9);
      p.text(
        c,
        'Zn + Cu²⁺ → Zn²⁺ + Cu',
        const Offset(150, 192),
        size: 10,
        bold: true,
      );
    },
    tags:
        'redoks yükseltgenme indirgenme elektron aktarımı ok yükseltgen indirgen',
  ),
  WbArtItem(
    'kim_cozunme_nacl',
    'NaCl’nin suda çözünmesi',
    300,
    230,
    (c, p) {
      final b = WbArtPen.poly(const [
        Offset(20, 20),
        Offset(25, 30),
        Offset(25, 190),
        Offset(275, 190),
        Offset(275, 30),
        Offset(280, 20),
      ], close: false);
      _glass(c, p, b);
      _liq(c, p, b, 50, WbArtColors.blue, 0.15);
      for (int i = 0; i < 2; i++) {
        for (int j = 0; j < 2; j++) {
          final o = Offset(45.0 + i * 20, 160.0 + j * 20);
          if ((i + j).isEven) {
            _atom(c, p, o, 7, WbArtColors.purple, '+', ts: 8);
          } else {
            _atom(c, p, o, 9, WbArtColors.green, '–', ts: 9);
          }
        }
      }
      void water(Offset o, double ang) {
        c.save();
        c.translate(o.dx, o.dy);
        c.rotate(ang);
        c.drawCircle(Offset.zero, 5, p.fill(WbArtColors.red, 0.5));
        c.drawCircle(
          const Offset(-5, 6),
          3,
          p.fill(WbArtColors.lightBlue, 0.9),
        );
        c.drawCircle(const Offset(5, 6), 3, p.fill(WbArtColors.lightBlue, 0.9));
        c.restore();
      }

      const nap = Offset(150, 95);
      const clp = Offset(220, 130);
      _atom(c, p, nap, 9, WbArtColors.purple, 'Na⁺', ts: 7);
      _atom(c, p, clp, 12, WbArtColors.green, 'Cl⁻', ts: 8);
      for (int k = 0; k < 4; k++) {
        final a = k * math.pi / 2 + 0.5;
        water(
          nap + Offset(math.cos(a), math.sin(a)) * 24,
          a + math.pi / 2 + math.pi,
        );
        final a2 = k * math.pi / 2 + 0.2;
        water(clp + Offset(math.cos(a2), math.sin(a2)) * 28, a2 + math.pi / 2);
      }
      p.arrow(
        c,
        const Offset(85, 150),
        const Offset(130, 115),
        size: 6,
        c: WbArtColors.red,
      );
      p.arrow(
        c,
        const Offset(85, 160),
        const Offset(195, 140),
        size: 6,
        c: WbArtColors.red,
      );
      p.text(c, 'NaCl kristali', const Offset(55, 205), size: 9);
      p.text(c, 'Hidratlanmış iyonlar', const Offset(185, 60), size: 9);
      p.text(
        c,
        'NaCl(k) → Na⁺(suda) + Cl⁻(suda)',
        const Offset(150, 218),
        size: 10,
        bold: true,
      );
    },
    tags: 'çözünme nacl suda iyonlaşma hidratlaşma çözelti',
  ),
  WbArtItem(
    'kim_tehlike_yanici',
    'Tehlike: Yanıcı',
    200,
    225,
    (c, p) {
      _hazard(c, p, 'YANICI', (c, p) {
        _flame(c, p, const Offset(100, 140), 38);
        c.drawLine(const Offset(70, 145), const Offset(130, 145), p.line);
      });
    },
    tags: 'tehlike uyarı sembol yanıcı alev güvenlik',
  ),
  WbArtItem(
    'kim_tehlike_zehirli',
    'Tehlike: Zehirli',
    200,
    225,
    (c, p) {
      _hazard(c, p, 'ZEHİRLİ', (c, p) {
        c.drawCircle(const Offset(100, 85), 20, p.fill(Colors.white, 1));
        c.drawCircle(const Offset(100, 85), 20, p.line);
        c.drawCircle(const Offset(92, 82), 4, p.solid);
        c.drawCircle(const Offset(108, 82), 4, p.solid);
        c.drawLine(const Offset(94, 98), const Offset(106, 98), p.line);
        c.drawLine(
          const Offset(70, 125),
          const Offset(130, 150),
          p.stroke(p.color, 1.5),
        );
        c.drawLine(
          const Offset(130, 125),
          const Offset(70, 150),
          p.stroke(p.color, 1.5),
        );
      });
    },
    tags: 'tehlike uyarı sembol zehirli toksik kuru kafa',
  ),
  WbArtItem(
    'kim_tehlike_asindirici',
    'Tehlike: Aşındırıcı',
    200,
    225,
    (c, p) {
      _hazard(c, p, 'AŞINDIRICI', (c, p) {
        for (final s in [-1.0, 1.0]) {
          c.save();
          c.translate(100 + s * 22, 70);
          c.rotate(s * 0.5);
          c.drawRect(
            const Rect.fromLTWH(-5, -22, 10, 34),
            p.fill(WbArtColors.lightBlue, 0.4),
          );
          c.drawRect(const Rect.fromLTWH(-5, -22, 10, 34), p.line);
          c.restore();
        }
        c.drawCircle(const Offset(88, 105), 3, p.fill(WbArtColors.green, 0.8));
        c.drawCircle(const Offset(112, 105), 3, p.fill(WbArtColors.green, 0.8));
        c.drawRect(
          const Rect.fromLTWH(60, 120, 80, 12),
          p.fill(WbArtColors.gray, 0.6),
        );
        c.drawRect(const Rect.fromLTWH(60, 120, 80, 12), p.line);
        c.drawLine(const Offset(75, 132), const Offset(80, 142), p.line);
        c.drawLine(const Offset(110, 132), const Offset(105, 146), p.line);
      });
    },
    tags: 'tehlike uyarı sembol aşındırıcı korozif asit',
  ),
  WbArtItem(
    'kim_tehlike_patlayici',
    'Tehlike: Patlayıcı',
    200,
    225,
    (c, p) {
      _hazard(c, p, 'PATLAYICI', (c, p) {
        final pts = <Offset>[];
        for (int i = 0; i < 16; i++) {
          final r = i.isEven ? 40.0 : 20.0;
          final a = i * math.pi / 8;
          pts.add(Offset(100 + r * math.cos(a), 100 + r * math.sin(a)));
        }
        c.drawPath(WbArtPen.poly(pts), p.fill(WbArtColors.orange, 0.7));
        c.drawPath(WbArtPen.poly(pts), p.line);
        c.drawCircle(const Offset(100, 100), 9, p.fill(Colors.black, 0.8));
      });
    },
    tags: 'tehlike uyarı sembol patlayıcı bomba patlama',
  ),
  WbArtItem(
    'kim_tehlike_cevre',
    'Tehlike: Çevreye zararlı',
    200,
    225,
    (c, p) {
      _hazard(c, p, 'ÇEVREYE ZARARLI', (c, p) {
        c.drawLine(
          const Offset(70, 140),
          const Offset(70, 100),
          p.stroke(WbArtColors.brown, 1.4),
        );
        c.drawLine(const Offset(70, 115), const Offset(58, 100), p.thin());
        c.drawLine(const Offset(70, 108), const Offset(82, 92), p.thin());
        c.drawLine(const Offset(55, 142), const Offset(145, 142), p.line);
        final fish = Path()
          ..moveTo(105, 100)
          ..quadraticBezierTo(125, 85, 145, 100)
          ..quadraticBezierTo(125, 115, 105, 100)
          ..lineTo(98, 90)
          ..lineTo(98, 110)
          ..close();
        c.drawPath(fish, p.fill(WbArtColors.gray, 0.4));
        c.drawPath(fish, p.line);
        c.drawLine(const Offset(133, 95), const Offset(137, 105), p.thin());
      });
    },
    tags: 'tehlike uyarı sembol çevreye zararlı çevre balık ağaç',
  ),
];

// ───────────────────────── Tüm liste ─────────────────────────

final List<WbArtItem> wbArtChemistry = [
  ..._chemLab,
  ..._chemSetups,
  ..._chemAtoms,
  ..._chemMolecules,
  ..._chemStates,
  ..._chemGases,
  ..._chemMisc,
];
