import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'whiteboard_art_core.dart';

/// Genel şekiller: akış şemaları, organizatörler, ödüller, okul nesneleri,
/// semboller, Türkçe/matematik/müzik şablonları vb.

typedef _C = WbArtColors;

Offset _o(double x, double y) => Offset(x, y);

void _t(
  Canvas c,
  WbArtPen p,
  String s,
  Offset at, {
  double size = 9,
  Color? col,
  bool bold = false,
  String anchor = 'center',
}) => p.text(c, s, at, size: size, c: col, bold: bold, anchor: anchor);

void _ln(
  Canvas c,
  WbArtPen p,
  Offset a,
  Offset b, {
  bool thin = false,
  Color? col,
}) {
  final paint = col != null
      ? p.stroke(col, thin ? 0.5 : 1)
      : (thin ? p.thin() : p.line);
  c.drawLine(a, b, paint);
}

void _box(
  Canvas c,
  WbArtPen p,
  Rect r, {
  Color? f,
  double a = 0.25,
  double rad = 0,
  bool thin = false,
}) {
  final rr = RRect.fromRectAndRadius(r, Radius.circular(rad));
  if (f != null) c.drawRRect(rr, p.fill(f, a));
  c.drawRRect(rr, thin ? p.thin() : p.line);
}

void _ell(
  Canvas c,
  WbArtPen p,
  Rect r, {
  Color? f,
  double a = 0.25,
  bool thin = false,
}) {
  if (f != null) c.drawOval(r, p.fill(f, a));
  c.drawOval(r, thin ? p.thin() : p.line);
}

void _poly(
  Canvas c,
  WbArtPen p,
  List<Offset> pts, {
  Color? f,
  double a = 0.25,
  bool thin = false,
  bool close = true,
}) {
  final path = WbArtPen.poly(pts, close: close);
  if (f != null && close) c.drawPath(path, p.fill(f, a));
  c.drawPath(path, thin ? p.thin() : p.line);
}

void _path(
  Canvas c,
  WbArtPen p,
  Path path, {
  Color? f,
  double a = 0.25,
  bool thin = false,
}) {
  if (f != null) c.drawPath(path, p.fill(f, a));
  c.drawPath(path, thin ? p.thin() : p.line);
}

List<Offset> _starPts(
  Offset c,
  double r, {
  int n = 5,
  double k = 0.42,
  double start = -math.pi / 2,
}) => [
  for (int i = 0; i < n * 2; i++)
    Offset(
      c.dx + (i.isEven ? r : r * k) * math.cos(start + math.pi * i / n),
      c.dy + (i.isEven ? r : r * k) * math.sin(start + math.pi * i / n),
    ),
];

/// Izgara: [rows] x [cols] hücre, ince iç çizgiler + kalın dış çerçeve.
void _grid(Canvas c, WbArtPen p, Rect r, int rows, int cols) {
  for (int i = 1; i < rows; i++) {
    final y = r.top + r.height * i / rows;
    c.drawLine(_o(r.left, y), _o(r.right, y), p.thin());
  }
  for (int j = 1; j < cols; j++) {
    final x = r.left + r.width * j / cols;
    c.drawLine(_o(x, r.top), _o(x, r.bottom), p.thin());
  }
  c.drawRect(r, p.line);
}

Path _union(List<Rect> ovals) {
  Path res = Path()..addOval(ovals.first);
  for (int i = 1; i < ovals.length; i++) {
    res = Path.combine(PathOperation.union, res, Path()..addOval(ovals[i]));
  }
  return res;
}

Path _cloudPath(double x, double y, double s) => _union([
  Rect.fromCircle(center: _o(x - 18 * s, y + 4 * s), radius: 14 * s),
  Rect.fromCircle(center: _o(x - 4 * s, y - 8 * s), radius: 18 * s),
  Rect.fromCircle(center: _o(x + 16 * s, y - 2 * s), radius: 15 * s),
  Rect.fromCircle(center: _o(x + 2 * s, y + 8 * s), radius: 16 * s),
]);

void _heart(
  Canvas c,
  WbArtPen p,
  Offset ct,
  double s, {
  Color col = _C.red,
  bool stroke = true,
}) {
  final path = Path()
    ..moveTo(ct.dx, ct.dy + s * 0.9)
    ..cubicTo(
      ct.dx - s * 1.6,
      ct.dy - s * 0.1,
      ct.dx - s * 0.9,
      ct.dy - s * 1.2,
      ct.dx,
      ct.dy - s * 0.35,
    )
    ..cubicTo(
      ct.dx + s * 0.9,
      ct.dy - s * 1.2,
      ct.dx + s * 1.6,
      ct.dy - s * 0.1,
      ct.dx,
      ct.dy + s * 0.9,
    )
    ..close();
  c.drawPath(path, p.fill(col, 0.85));
  if (stroke) c.drawPath(path, p.line);
}

void _sun(Canvas c, WbArtPen p, Offset ct, double r) {
  for (int i = 0; i < 12; i++) {
    final a = i * math.pi / 6;
    c.drawLine(
      ct + Offset(math.cos(a), math.sin(a)) * (r * 1.3),
      ct + Offset(math.cos(a), math.sin(a)) * (r * 1.8),
      p.stroke(_C.orange),
    );
  }
  c.drawCircle(ct, r, p.fill(_C.yellow, 0.9));
  c.drawCircle(ct, r, p.line);
}

void _drop(Canvas c, WbArtPen p, Offset ct, double s) {
  final path = Path()
    ..moveTo(ct.dx, ct.dy - s * 1.2)
    ..cubicTo(
      ct.dx + s * 0.2,
      ct.dy - s * 0.6,
      ct.dx + s * 0.9,
      ct.dy - s * 0.1,
      ct.dx + s * 0.9,
      ct.dy + s * 0.35,
    )
    ..arcToPoint(
      _o(ct.dx - s * 0.9, ct.dy + s * 0.35),
      radius: Radius.circular(s * 0.9),
      clockwise: true,
    )
    ..cubicTo(
      ct.dx - s * 0.9,
      ct.dy - s * 0.1,
      ct.dx - s * 0.2,
      ct.dy - s * 0.6,
      ct.dx,
      ct.dy - s * 1.2,
    )
    ..close();
  c.drawPath(path, p.fill(_C.blue, 0.5));
  c.drawPath(path, p.line);
}

/// Küçük akış şeması oku (dikey/yatay).
void _ar(Canvas c, WbArtPen p, Offset a, Offset b) => p.arrow(c, a, b, size: 6);

void _bubbleTail(
  Canvas c,
  WbArtPen p,
  Path body,
  Offset a,
  Offset b,
  Offset tip, {
  Color f = _C.lightBlue,
}) {
  final tail = WbArtPen.poly([a, tip, b]);
  final all = Path.combine(PathOperation.union, body, tail);
  c.drawPath(all, p.fill(f, 0.25));
  c.drawPath(all, p.line);
}

/// Tüm genel şekiller.
final List<WbArtItem> wbArtGeneral = [..._gen1, ..._gen2];

final List<WbArtItem> _gen1 = [
  // ───────────── AKIŞ ŞEMASI ─────────────
  WbArtItem(
    'gen_akis_basla',
    'Akış: Başla/Bitir',
    120,
    50,
    (c, p) {
      _box(c, p, const Rect.fromLTWH(6, 6, 108, 38), f: _C.green, rad: 19);
      _t(c, p, 'BAŞLA / BİTİR', _o(60, 25), size: 10, bold: true);
    },
    tags: 'akış şeması başla bitir başlangıç son oval algoritma',
  ),
  WbArtItem(
    'gen_akis_islem',
    'Akış: İşlem',
    120,
    50,
    (c, p) {
      _box(c, p, const Rect.fromLTWH(6, 6, 108, 38), f: _C.blue);
      _t(c, p, 'İŞLEM', _o(60, 25), size: 11, bold: true);
    },
    tags: 'akış şeması işlem dikdörtgen algoritma',
  ),
  WbArtItem(
    'gen_akis_karar',
    'Akış: Karar',
    120,
    80,
    (c, p) {
      _poly(c, p, [
        _o(60, 5),
        _o(115, 40),
        _o(60, 75),
        _o(5, 40),
      ], f: _C.yellow);
      _t(c, p, 'KARAR?', _o(60, 40), size: 10, bold: true);
    },
    tags: 'akış şeması karar eşkenar dörtgen evet hayır algoritma',
  ),
  WbArtItem(
    'gen_akis_giris',
    'Akış: Giriş/Çıkış',
    130,
    50,
    (c, p) {
      _poly(c, p, [
        _o(24, 6),
        _o(124, 6),
        _o(106, 44),
        _o(6, 44),
      ], f: _C.purple);
      _t(c, p, 'GİRİŞ / ÇIKIŞ', _o(65, 25), size: 9.5, bold: true);
    },
    tags: 'akış şeması giriş çıkış paralelkenar veri okuma yazma algoritma',
  ),
  WbArtItem(
    'gen_akis_baglayici',
    'Akış: Bağlayıcı',
    50,
    50,
    (c, p) {
      _ell(c, p, const Rect.fromLTWH(6, 6, 38, 38), f: _C.orange);
      _t(c, p, 'A', _o(25, 25), size: 13, bold: true);
    },
    tags: 'akış şeması bağlayıcı daire sayfa bağlantı algoritma',
  ),
  WbArtItem(
    'gen_akis_ornek',
    'Örnek akış şeması',
    230,
    330,
    (c, p) {
      _box(c, p, const Rect.fromLTWH(70, 6, 90, 30), f: _C.green, rad: 15);
      _t(c, p, 'BAŞLA', _o(115, 21), size: 10, bold: true);
      _ar(c, p, _o(115, 36), _o(115, 56));
      _poly(c, p, [
        _o(80, 56),
        _o(170, 56),
        _o(158, 86),
        _o(68, 86),
      ], f: _C.purple);
      _t(c, p, 'Sayıyı oku', _o(119, 71), size: 9.5);
      _ar(c, p, _o(115, 86), _o(115, 108));
      _poly(c, p, [
        _o(115, 108),
        _o(170, 143),
        _o(115, 178),
        _o(60, 143),
      ], f: _C.yellow);
      _t(c, p, 'Sayı > 0 ?', _o(115, 143), size: 9.5, bold: true);
      _ln(c, p, _o(170, 143), _o(195, 143));
      _ar(c, p, _o(195, 143), _o(195, 200));
      _t(c, p, 'Evet', _o(182, 135), size: 8.5, col: _C.darkGreen, bold: true);
      _ln(c, p, _o(60, 143), _o(35, 143));
      _ar(c, p, _o(35, 143), _o(35, 200));
      _t(c, p, 'Hayır', _o(48, 135), size: 8.5, col: _C.red, bold: true);
      _box(c, p, const Rect.fromLTWH(150, 200, 80, 34), f: _C.blue);
      _t(c, p, 'Pozitif yaz', _o(190, 217), size: 9);
      _box(c, p, const Rect.fromLTWH(0, 200, 70, 34), f: _C.blue);
      _t(c, p, 'Negatif yaz', _o(35, 217), size: 9);
      _ln(c, p, _o(190, 234), _o(190, 262));
      _ln(c, p, _o(35, 234), _o(35, 262));
      _ln(c, p, _o(35, 262), _o(190, 262));
      _ar(c, p, _o(115, 262), _o(115, 286));
      _box(c, p, const Rect.fromLTWH(70, 288, 90, 30), f: _C.red, rad: 15);
      _t(c, p, 'BİTİR', _o(115, 303), size: 10, bold: true);
    },
    tags: 'akış şeması örnek algoritma sayı pozitif negatif karar',
  ),

  // ───────────── ORGANİZATÖRLER ─────────────
  WbArtItem(
    'gen_zihin_haritasi',
    'Zihin haritası',
    320,
    230,
    (c, p) {
      final cols = [_C.red, _C.orange, _C.green, _C.teal, _C.blue, _C.purple];
      for (int i = 0; i < 6; i++) {
        final a =
            -math.pi / 2 + (i + 0.5) * math.pi / 3 - math.pi / 6 + math.pi / 6;
        final e = _o(160 + 118 * math.cos(a), 115 + 82 * math.sin(a));
        final mid = _o(
          160 + 60 * math.cos(a - 0.25),
          115 + 42 * math.sin(a - 0.25),
        );
        c.drawPath(
          Path()
            ..moveTo(160, 115)
            ..quadraticBezierTo(mid.dx, mid.dy, e.dx, e.dy),
          p.stroke(cols[i], 1.2),
        );
        _ell(
          c,
          p,
          Rect.fromCenter(center: e, width: 62, height: 28),
          f: cols[i],
        );
        _t(c, p, 'Dal ${i + 1}', e, size: 10, bold: true);
      }
      _ell(
        c,
        p,
        Rect.fromCenter(center: _o(160, 115), width: 84, height: 48),
        f: _C.yellow,
        a: 0.5,
      );
      _t(c, p, 'KONU', _o(160, 115), size: 12, bold: true);
    },
    tags: 'zihin haritası merkez dal fikir beyin fırtınası şablon',
  ),
  WbArtItem(
    'gen_kavram_haritasi',
    'Kavram haritası',
    320,
    230,
    (c, p) {
      _box(c, p, const Rect.fromLTWH(115, 6, 90, 32), f: _C.purple, rad: 16);
      _t(c, p, 'ANA KAVRAM', _o(160, 22), size: 10, bold: true);
      final xs = [45.0, 160.0, 275.0];
      for (final x in xs) {
        _ar(c, p, _o(160, 38), _o(x, 100));
        _t(
          c,
          p,
          'bağlaç',
          _o((160 + x) / 2 + (x < 160 ? -6 : (x > 160 ? 6 : 12)), 66),
          size: 8,
          col: _C.gray,
        );
        _box(
          c,
          p,
          Rect.fromCenter(center: _o(x, 115), width: 80, height: 30),
          f: _C.blue,
          rad: 15,
        );
        _t(c, p, 'Kavram', _o(x, 115), size: 10);
      }
      _ar(c, p, _o(45, 130), _o(45, 192));
      _ar(c, p, _o(275, 130), _o(275, 192));
      _t(c, p, 'bağlaç', _o(60, 162), size: 8, col: _C.gray);
      _t(c, p, 'bağlaç', _o(260, 162), size: 8, col: _C.gray);
      for (final x in [45.0, 275.0]) {
        _box(
          c,
          p,
          Rect.fromCenter(center: _o(x, 208), width: 80, height: 30),
          f: _C.green,
          rad: 15,
        );
        _t(c, p, 'Kavram', _o(x, 208), size: 10);
      }
      _ln(c, p, _o(85, 115), _o(120, 115), thin: true);
      _ln(c, p, _o(200, 115), _o(235, 115), thin: true);
    },
    tags: 'kavram haritası bağlaç ilişki şablon organizatör',
  ),
  WbArtItem(
    'gen_balik_kilcigi',
    'Balık kılçığı (neden-sonuç)',
    320,
    190,
    (c, p) {
      _ln(c, p, _o(15, 95), _o(220, 95));
      _poly(c, p, [_o(220, 95), _o(210, 80), _o(210, 110)], f: _C.blue, a: 0.4);
      _box(c, p, const Rect.fromLTWH(225, 70, 90, 50), f: _C.orange, rad: 10);
      _t(c, p, 'SORUN /\nSONUÇ', _o(270, 95), size: 10, bold: true);
      final xs = [60.0, 120.0, 180.0];
      for (final x in xs) {
        _ln(c, p, _o(x, 20), _o(x + 30, 95));
        _ln(c, p, _o(x, 170), _o(x + 30, 95));
        _t(c, p, 'Neden', _o(x - 4, 10), size: 9, bold: true, col: _C.red);
        _t(c, p, 'Neden', _o(x - 4, 180), size: 9, bold: true, col: _C.red);
        for (final fy in [0.4, 0.7]) {
          _ln(
            c,
            p,
            _o(x + 30 * fy - 18, 20 + 75 * fy),
            _o(x + 30 * fy, 20 + 75 * fy),
            thin: true,
          );
          _ln(
            c,
            p,
            _o(x + 30 * fy - 18, 170 - 75 * fy),
            _o(x + 30 * fy, 170 - 75 * fy),
            thin: true,
          );
        }
      }
    },
    tags: 'balık kılçığı neden sonuç ishikawa diyagram',
  ),
  WbArtItem(
    'gen_t_grafigi',
    'T grafiği',
    240,
    180,
    (c, p) {
      _box(c, p, const Rect.fromLTWH(6, 6, 228, 168), rad: 6, thin: true);
      _ln(c, p, _o(120, 6), _o(120, 174));
      _ln(c, p, _o(6, 38), _o(234, 38));
      _t(c, p, 'Başlık A', _o(63, 22), size: 11, bold: true, col: _C.blue);
      _t(c, p, 'Başlık B', _o(177, 22), size: 11, bold: true, col: _C.red);
      for (final y in [70.0, 100.0, 130.0, 160.0]) {
        c.drawLine(_o(14, y), _o(112, y), p.thin(0.3));
        c.drawLine(_o(128, y), _o(226, y), p.thin(0.3));
      }
    },
    tags: 't grafiği karşılaştırma artı eksi iki sütun organizatör',
  ),
  WbArtItem(
    'gen_venn',
    'Venn karşılaştırma',
    280,
    170,
    (c, p) {
      final a = Rect.fromCircle(center: _o(105, 85), radius: 70);
      final b = Rect.fromCircle(center: _o(175, 85), radius: 70);
      c.drawOval(a, p.fill(_C.blue, 0.25));
      c.drawOval(b, p.fill(_C.red, 0.25));
      c.drawOval(a, p.line);
      c.drawOval(b, p.line);
      _t(c, p, 'A', _o(70, 30), size: 12, bold: true, col: _C.blue);
      _t(c, p, 'B', _o(210, 30), size: 12, bold: true, col: _C.red);
      _t(c, p, 'Ortak', _o(140, 85), size: 10, bold: true);
      _t(c, p, 'Sadece A', _o(75, 100), size: 8.5);
      _t(c, p, 'Sadece B', _o(205, 100), size: 8.5);
    },
    tags: 'venn şeması karşılaştırma ortak kesişim kümeler',
  ),
  WbArtItem(
    'gen_swot',
    'SWOT 2x2',
    260,
    210,
    (c, p) {
      final cols = [_C.green, _C.red, _C.blue, _C.orange];
      final names = ['Güçlü yönler', 'Zayıf yönler', 'Fırsatlar', 'Tehditler'];
      for (int i = 0; i < 4; i++) {
        final r = Rect.fromLTWH(
          6 + (i % 2) * 124,
          6 + (i ~/ 2) * 100,
          124,
          100,
        );
        c.drawRect(r, p.fill(cols[i], 0.2));
        _t(
          c,
          p,
          names[i],
          _o(r.center.dx, r.top + 12),
          size: 10,
          bold: true,
          col: cols[i],
        );
      }
      c.drawRect(const Rect.fromLTWH(6, 6, 248, 200), p.line);
      _ln(c, p, _o(130, 6), _o(130, 206));
      _ln(c, p, _o(6, 106), _o(254, 106));
    },
    tags: 'swot analiz güçlü zayıf fırsat tehdit 2x2 matris',
  ),
  WbArtItem(
    'gen_kwl',
    'KWL tablosu',
    270,
    200,
    (c, p) {
      _grid(c, p, const Rect.fromLTWH(6, 6, 258, 188), 1, 3);
      _ln(c, p, _o(6, 40), _o(264, 40));
      final cols = [_C.green, _C.orange, _C.blue];
      final t = ['Biliyorum\n(K)', 'Merak ediyorum\n(W)', 'Öğrendim\n(L)'];
      for (int i = 0; i < 3; i++) {
        c.drawRect(Rect.fromLTWH(6 + i * 86, 6, 86, 34), p.fill(cols[i], 0.3));
        _t(c, p, t[i], _o(49 + i * 86, 23), size: 9, bold: true);
      }
    },
    tags: 'kwl tablosu biliyorum merak öğrendim okuma stratejisi',
  ),
  WbArtItem(
    'gen_5n1k',
    '5N1K şablonu',
    280,
    190,
    (c, p) {
      final q = ['Ne?', 'Nerede?', 'Ne zaman?', 'Neden?', 'Nasıl?', 'Kim?'];
      final cols = [_C.red, _C.orange, _C.green, _C.teal, _C.blue, _C.purple];
      for (int i = 0; i < 6; i++) {
        final r = Rect.fromLTWH(
          6 + (i % 2) * 138,
          6 + (i ~/ 3 == 0 ? 0 : 0) + (i ~/ 2) * 61,
          130,
          54,
        );
        _box(c, p, r, f: cols[i], rad: 8);
        _t(c, p, q[i], _o(r.left + 30, r.center.dy), size: 11, bold: true);
        c.drawLine(
          _o(r.left + 58, r.bottom - 12),
          _o(r.right - 8, r.bottom - 12),
          p.thin(0.4),
        );
      }
    },
    tags: '5n1k ne nerede ne zaman neden nasıl kim soru şablon',
  ),
  WbArtItem(
    'gen_hikaye_haritasi',
    'Hikâye haritası',
    300,
    200,
    (c, p) {
      final lbl = ['Yer', 'Zaman', 'Kişiler', 'Olay', 'Sorun', 'Çözüm'];
      final cols = [_C.green, _C.yellow, _C.orange, _C.blue, _C.red, _C.purple];
      for (int i = 0; i < 6; i++) {
        final r = Rect.fromLTWH(6 + (i % 3) * 98, 6 + (i ~/ 3) * 98, 92, 90);
        _box(c, p, r, f: cols[i], rad: 8);
        _t(c, p, lbl[i], _o(r.center.dx, r.top + 12), size: 10.5, bold: true);
      }
    },
    tags: 'hikaye haritası yer zaman kişiler olay sorun çözüm öyküleyici metin',
  ),
  WbArtItem(
    'gen_hikaye_piramidi',
    'Hikâye piramidi',
    240,
    200,
    (c, p) {
      final labels = ['Kahraman', 'Yer', 'Zaman', 'Sorun', 'Olay', 'Çözüm'];
      for (int i = 0; i < 6; i++) {
        final y = 8 + i * 30.0;
        final w = 30 + i * 36.0;
        _box(
          c,
          p,
          Rect.fromCenter(center: _o(120, y + 14), width: w, height: 26),
          f: _C.purple,
          a: 0.1 + i * 0.07,
          rad: 5,
        );
        _t(c, p, labels[i], _o(120, y + 14), size: 8.5, bold: true);
      }
    },
    tags: 'hikaye piramidi öykü kahraman yer zaman sorun çözüm',
  ),
  WbArtItem(
    'gen_dongu_4',
    'Döngü diyagramı (4 adım)',
    220,
    220,
    (c, p) {
      final cols = [_C.red, _C.orange, _C.green, _C.blue];
      for (int i = 0; i < 4; i++) {
        final s = -90 + i * 90 + 14.0;
        c.drawArc(
          Rect.fromCircle(center: _o(110, 110), radius: 70),
          s * math.pi / 180,
          62 * math.pi / 180,
          false,
          p.stroke(cols[i], 1.6),
        );
        final ea = (s + 62) * math.pi / 180;
        p.arrow(
          c,
          _o(110 + 70 * math.cos(ea - 0.1), 110 + 70 * math.sin(ea - 0.1)),
          _o(110 + 70 * math.cos(ea + 0.08), 110 + 70 * math.sin(ea + 0.08)),
          c: cols[i],
          size: 9,
          line: false,
        );
        final ctr = _o(
          110 + 70 * math.cos(-math.pi / 2 + i * math.pi / 2),
          110 + 70 * math.sin(-math.pi / 2 + i * math.pi / 2),
        );
        _ell(
          c,
          p,
          Rect.fromCenter(center: ctr, width: 40, height: 40),
          f: cols[i],
          a: 0.35,
        );
        _t(c, p, '${i + 1}. Adım', ctr, size: 8, bold: true);
      }
      _t(c, p, 'DÖNGÜ', _o(110, 110), size: 11, bold: true);
    },
    tags: 'döngü diyagramı 4 adım çember yaşam döngüsü su döngüsü',
  ),
  WbArtItem(
    'gen_dongu_6',
    'Döngü diyagramı (6 adım)',
    240,
    240,
    (c, p) {
      final cols = [_C.red, _C.orange, _C.yellow, _C.green, _C.blue, _C.purple];
      for (int i = 0; i < 6; i++) {
        final s = -90 + i * 60 + 12.0;
        c.drawArc(
          Rect.fromCircle(center: _o(120, 120), radius: 80),
          s * math.pi / 180,
          36 * math.pi / 180,
          false,
          p.stroke(cols[i], 1.5),
        );
        final ea = (s + 36) * math.pi / 180;
        p.arrow(
          c,
          _o(120 + 80 * math.cos(ea - 0.1), 120 + 80 * math.sin(ea - 0.1)),
          _o(120 + 80 * math.cos(ea + 0.08), 120 + 80 * math.sin(ea + 0.08)),
          c: cols[i],
          size: 8,
          line: false,
        );
        final a = -math.pi / 2 + i * math.pi / 3;
        final ctr = _o(120 + 80 * math.cos(a), 120 + 80 * math.sin(a));
        _ell(
          c,
          p,
          Rect.fromCenter(center: ctr, width: 36, height: 36),
          f: cols[i],
          a: 0.4,
        );
        _t(c, p, '${i + 1}', ctr, size: 12, bold: true);
      }
      _t(c, p, 'DÖNGÜ', _o(120, 120), size: 11, bold: true);
    },
    tags: 'döngü diyagramı 6 adım çember süreç',
  ),
  WbArtItem(
    'gen_piramit_3',
    'Piramit (3 katman)',
    220,
    180,
    (c, p) {
      final cols = [_C.red, _C.yellow, _C.green];
      for (int i = 0; i < 3; i++) {
        final y0 = 10 + i * 53.0;
        final y1 = y0 + 53;
        final x0 = 110 - (y0 - 10) / 160 * 100;
        final x1 = 110 - (y1 - 10) / 160 * 100;
        _poly(
          c,
          p,
          [
            _o(110 - (y0 - 10) / 160 * 100, y0),
            _o(110 + (y0 - 10) / 160 * 100, y0),
            _o(110 + (110 - x1), y1),
            _o(x1, y1),
          ],
          f: cols[i],
          a: 0.4,
        );
        if (x0 < 0) continue;
        _t(
          c,
          p,
          ['Tepe', 'Orta', 'Taban'][i],
          _o(110, y0 + 33),
          size: 10,
          bold: true,
        );
      }
    },
    tags: 'piramit 3 katman besin piramidi hiyerarşi',
  ),
  WbArtItem(
    'gen_piramit_4',
    'Piramit (4 katman)',
    240,
    200,
    (c, p) {
      final cols = [_C.red, _C.orange, _C.yellow, _C.green];
      for (int i = 0; i < 4; i++) {
        final y0 = 10 + i * 45.0;
        final y1 = y0 + 45;
        double hw(double y) => (y - 10) / 180 * 110;
        _poly(
          c,
          p,
          [
            _o(120 - hw(y0), y0),
            _o(120 + hw(y0), y0),
            _o(120 + hw(y1), y1),
            _o(120 - hw(y1), y1),
          ],
          f: cols[i],
          a: 0.4,
        );
        _t(c, p, '${4 - i}. katman', _o(120, y0 + 28), size: 9, bold: true);
      }
    },
    tags: 'piramit 4 katman hiyerarşi seviye',
  ),
  WbArtItem(
    'gen_huni',
    'Huni diyagramı',
    220,
    200,
    (c, p) {
      final cols = [_C.blue, _C.teal, _C.green, _C.yellow];
      final lbl = ['Geniş', 'Eleme', 'Daralt', 'Sonuç'];
      for (int i = 0; i < 4; i++) {
        final y0 = 10 + i * 40.0;
        double hw(double y) => 100 - (y - 10) / 160 * 70;
        _poly(
          c,
          p,
          [
            _o(110 - hw(y0), y0),
            _o(110 + hw(y0), y0),
            _o(110 + hw(y0 + 36), y0 + 36),
            _o(110 - hw(y0 + 36), y0 + 36),
          ],
          f: cols[i],
          a: 0.4,
        );
        _t(c, p, lbl[i], _o(110, y0 + 18), size: 10, bold: true);
      }
      c.drawRect(const Rect.fromLTWH(95, 172, 30, 22), p.fill(_C.yellow, 0.3));
      c.drawRect(const Rect.fromLTWH(95, 172, 30, 22), p.line);
    },
    tags: 'huni diyagramı eleme süzgeç daralma satış',
  ),
  WbArtItem(
    'gen_merdiven',
    'Basamaklar / merdiven',
    240,
    180,
    (c, p) {
      final cols = [_C.red, _C.orange, _C.yellow, _C.green, _C.blue];
      for (int i = 0; i < 5; i++) {
        final r = Rect.fromLTWH(
          10 + i * 42.0,
          150 - i * 30.0,
          42,
          20 + i * 30.0,
        );
        c.drawRect(r, p.fill(cols[i], 0.35));
        c.drawRect(r, p.line);
        _t(c, p, '${i + 1}', _o(r.center.dx, r.top + 14), size: 11, bold: true);
      }
      p.arrow(c, _o(14, 30), _o(80, 8), c: _C.gray, size: 8);
    },
    tags: 'basamak merdiven adım gelişim başarı',
  ),
  WbArtItem(
    'gen_zaman_yatay',
    'Zaman çizelgesi (yatay)',
    320,
    130,
    (c, p) {
      p.arrow(c, _o(10, 65), _o(310, 65), size: 9);
      final cols = [_C.red, _C.orange, _C.green, _C.blue, _C.purple];
      for (int i = 0; i < 5; i++) {
        final x = 45.0 + i * 62;
        final up = i.isEven;
        c.drawLine(_o(x, 65), _o(x, up ? 38 : 92), p.thin());
        c.drawCircle(_o(x, 65), 6, p.fill(cols[i], 0.9));
        c.drawCircle(_o(x, 65), 6, p.line);
        _box(
          c,
          p,
          Rect.fromCenter(center: _o(x, up ? 24 : 106), width: 54, height: 24),
          f: cols[i],
          rad: 6,
        );
        _t(c, p, 'Olay ${i + 1}', _o(x, up ? 24 : 106), size: 8.5);
      }
    },
    tags: 'zaman çizelgesi şeridi yatay tarih olay kronoloji',
  ),
  WbArtItem(
    'gen_zaman_dikey',
    'Zaman çizelgesi (dikey)',
    200,
    280,
    (c, p) {
      p.arrow(c, _o(100, 8), _o(100, 272), size: 9);
      final cols = [_C.red, _C.orange, _C.green, _C.blue, _C.purple];
      for (int i = 0; i < 5; i++) {
        final y = 32.0 + i * 50;
        final left = i.isEven;
        c.drawLine(_o(100, y), _o(left ? 78 : 122, y), p.thin());
        c.drawCircle(_o(100, y), 6, p.fill(cols[i], 0.9));
        c.drawCircle(_o(100, y), 6, p.line);
        _box(
          c,
          p,
          Rect.fromCenter(
            center: _o(left ? 44 : 156, y),
            width: 66,
            height: 28,
          ),
          f: cols[i],
          rad: 6,
        );
        _t(c, p, 'Olay ${i + 1}', _o(left ? 44 : 156, y), size: 9);
      }
    },
    tags: 'zaman çizelgesi dikey tarih olay kronoloji',
  ),
  WbArtItem(
    'gen_org_semasi',
    'Organizasyon şeması',
    320,
    210,
    (c, p) {
      _box(c, p, const Rect.fromLTWH(120, 6, 80, 30), f: _C.purple, rad: 6);
      _t(c, p, 'Üst', _o(160, 21), size: 10, bold: true);
      _ln(c, p, _o(160, 36), _o(160, 58));
      _ln(c, p, _o(55, 58), _o(265, 58));
      for (final x in [55.0, 160.0, 265.0]) {
        _ln(c, p, _o(x, 58), _o(x, 76));
        _box(
          c,
          p,
          Rect.fromCenter(center: _o(x, 92), width: 76, height: 28),
          f: _C.blue,
          rad: 6,
        );
        _t(c, p, 'Birim', _o(x, 92), size: 9.5, bold: true);
      }
      for (final x in [25.0, 85.0, 130.0, 190.0, 235.0, 295.0]) {
        final par = x < 107 ? 55.0 : (x < 213 ? 160.0 : 265.0);
        _ln(c, p, _o(par, 106), _o(par, 124), thin: true);
        _ln(c, p, _o(par, 124), _o(x, 124), thin: true);
        _ln(c, p, _o(x, 124), _o(x, 142), thin: true);
        _box(
          c,
          p,
          Rect.fromCenter(center: _o(x, 158), width: 50, height: 32),
          f: _C.green,
          rad: 5,
        );
        _t(c, p, 'Alt', _o(x, 158), size: 9);
      }
    },
    tags: 'organizasyon şeması ilişki ağacı soy ağacı hiyerarşi şema',
  ),
  WbArtItem('gen_matris_3x3', 'Matris 3x3', 210, 210, (c, p) {
    _grid(c, p, const Rect.fromLTWH(30, 30, 174, 174), 3, 3);
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        if ((i + j).isEven)
          c.drawRect(
            Rect.fromLTWH(30 + j * 58.0, 30 + i * 58.0, 58, 58),
            p.fill(_C.lightBlue, 0.25),
          );
      }
      _t(c, p, '${i + 1}', _o(15, 59 + i * 58.0), size: 11, bold: true);
      _t(c, p, ['A', 'B', 'C'][i], _o(59 + i * 58.0, 14), size: 11, bold: true);
    }
  }, tags: 'matris 3x3 tablo ızgara dokuz kare'),
  WbArtItem(
    'gen_rubrik',
    'Puanlama tablosu (rubrik)',
    300,
    190,
    (c, p) {
      _grid(c, p, const Rect.fromLTWH(6, 6, 288, 178), 5, 5);
      c.drawRect(const Rect.fromLTWH(6, 6, 288, 35.6), p.fill(_C.blue, 0.3));
      c.drawRect(const Rect.fromLTWH(6, 6, 57.6, 178), p.fill(_C.blue, 0.2));
      _t(c, p, 'Ölçüt', _o(35, 24), size: 9, bold: true);
      final h = ['1 Geliştir', '2 Orta', '3 İyi', '4 Çok iyi'];
      for (int i = 0; i < 4; i++) {
        _t(c, p, h[i], _o(92 + i * 57.6, 24), size: 8.5, bold: true);
        _t(c, p, 'Ölçüt ${i + 1}', _o(35, 59 + i * 35.6), size: 8);
      }
    },
    tags: 'rubrik puanlama tablosu değerlendirme ölçüt performans',
  ),
  WbArtItem(
    'gen_ders_programi',
    'Haftalık ders programı',
    320,
    220,
    (c, p) {
      _grid(c, p, const Rect.fromLTWH(6, 6, 308, 208), 7, 6);
      c.drawRect(const Rect.fromLTWH(6, 6, 308, 29.7), p.fill(_C.orange, 0.3));
      final d = ['Saat', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum'];
      for (int i = 0; i < 6; i++) {
        _t(c, p, d[i], _o(6 + 25.7 + i * 51.3, 21), size: 9.5, bold: true);
      }
      for (int r = 1; r <= 6; r++) {
        _t(c, p, '$r. ders', _o(6 + 25.7, 6 + 29.7 * r + 15), size: 8);
      }
    },
    tags: 'ders programı haftalık çizelge pazartesi cuma saat tablo',
  ),
  WbArtItem(
    'gen_takvim_ay',
    'Takvim ayı ızgarası',
    280,
    230,
    (c, p) {
      _box(c, p, const Rect.fromLTWH(6, 6, 268, 28), f: _C.red, rad: 4);
      _t(
        c,
        p,
        'AY: ................ YIL: ........',
        _o(140, 20),
        size: 10,
        bold: true,
      );
      final g = const Rect.fromLTWH(6, 38, 268, 186);
      _grid(c, p, g, 6, 7);
      final days = ['Pt', 'Sa', 'Ça', 'Pe', 'Cu', 'Ct', 'Pz'];
      final cw = g.width / 7, rh = g.height / 6;
      for (int i = 0; i < 7; i++) {
        _t(
          c,
          p,
          days[i],
          _o(g.left + cw * (i + 0.5), g.top + rh / 2),
          size: 9,
          bold: true,
          col: i >= 5 ? _C.red : null,
        );
      }
      for (int n = 1; n <= 30; n++) {
        final idx = n + 1;
        final r = 1 + idx ~/ 7, cl = idx % 7;
        if (r > 5) continue;
        _t(
          c,
          p,
          '$n',
          _o(g.left + cw * (cl + 0.15), g.top + rh * r + 8),
          size: 8,
          anchor: 'left',
        );
      }
    },
    tags: 'takvim ay ızgara gün hafta tarih',
  ),

  // ───────────── ÖDÜL / İŞARET ─────────────
  WbArtItem('gen_odul_yildiz', 'Ödül yıldızı', 110, 110, (c, p) {
    _poly(c, p, _starPts(_o(55, 58), 48), f: _C.yellow, a: 0.8);
    _poly(
      c,
      p,
      _starPts(_o(55, 58), 26, k: 0.5),
      f: _C.orange,
      a: 0.35,
      thin: true,
    );
  }, tags: 'yıldız ödül başarı altın puan'),
  WbArtItem('gen_madalya', 'Madalya', 100, 140, (c, p) {
    _poly(
      c,
      p,
      [_o(25, 4), _o(50, 4), _o(62, 52), _o(38, 52)],
      f: _C.red,
      a: 0.6,
    );
    _poly(
      c,
      p,
      [_o(75, 4), _o(50, 4), _o(38, 52), _o(62, 52)],
      f: _C.blue,
      a: 0.6,
    );
    c.drawCircle(_o(50, 88), 38, p.fill(_C.yellow, 0.85));
    c.drawCircle(_o(50, 88), 38, p.line);
    c.drawCircle(_o(50, 88), 29, p.thin());
    _poly(c, p, _starPts(_o(50, 88), 20), f: _C.orange, a: 0.6, thin: true);
  }, tags: 'madalya ödül birinci başarı şampiyon'),
  WbArtItem('gen_rozet', 'Rozet', 110, 150, (c, p) {
    _poly(
      c,
      p,
      [_o(32, 80), _o(18, 144), _o(40, 130), _o(52, 148), _o(62, 90)],
      f: _C.red,
      a: 0.55,
    );
    _poly(
      c,
      p,
      [_o(78, 80), _o(92, 144), _o(70, 130), _o(58, 148), _o(48, 90)],
      f: _C.blue,
      a: 0.55,
    );
    _poly(c, p, _starPts(_o(55, 55), 50, n: 14, k: 0.88), f: _C.green, a: 0.7);
    c.drawCircle(_o(55, 55), 30, p.fill(_C.yellow, 0.7));
    c.drawCircle(_o(55, 55), 30, p.thin());
    _t(c, p, '1', _o(55, 55), size: 24, bold: true);
  }, tags: 'rozet ödül başarı kurdele birinci'),
  WbArtItem('gen_onay', 'Onay işareti', 100, 100, (c, p) {
    c.drawCircle(_o(50, 50), 44, p.fill(_C.green, 0.25));
    c.drawCircle(_o(50, 50), 44, p.line);
    c.drawPath(
      Path()
        ..moveTo(26, 52)
        ..lineTo(44, 70)
        ..lineTo(76, 32),
      p.stroke(_C.green, 2.2),
    );
  }, tags: 'onay tik doğru evet işareti'),
  WbArtItem('gen_carpi', 'Çarpı işareti', 100, 100, (c, p) {
    c.drawCircle(_o(50, 50), 44, p.fill(_C.red, 0.25));
    c.drawCircle(_o(50, 50), 44, p.line);
    c.drawLine(_o(30, 30), _o(70, 70), p.stroke(_C.red, 2.2));
    c.drawLine(_o(70, 30), _o(30, 70), p.stroke(_C.red, 2.2));
  }, tags: 'çarpı yanlış hayır işareti iptal'),
  WbArtItem('gen_soru', 'Soru işareti', 100, 110, (c, p) {
    c.drawCircle(_o(50, 55), 46, p.fill(_C.blue, 0.2));
    c.drawCircle(_o(50, 55), 46, p.line);
    _t(c, p, '?', _o(50, 52), size: 62, bold: true, col: _C.blue);
  }, tags: 'soru işareti merak neden'),
  WbArtItem('gen_unlem', 'Ünlem işareti', 100, 110, (c, p) {
    _poly(c, p, [_o(50, 6), _o(94, 90), _o(6, 90)], f: _C.yellow, a: 0.5);
    _t(c, p, '!', _o(50, 62), size: 52, bold: true, col: _C.red);
  }, tags: 'ünlem dikkat uyarı önemli'),

  // ───────────── BALONLAR ─────────────
  WbArtItem(
    'gen_balon_konusma',
    'Konuşma balonu (oval)',
    150,
    110,
    (c, p) {
      _bubbleTail(
        c,
        p,
        Path()..addOval(const Rect.fromLTWH(6, 6, 138, 74)),
        _o(35, 68),
        _o(62, 77),
        _o(28, 104),
      );
    },
    tags: 'konuşma balonu diyalog söz oval',
  ),
  WbArtItem(
    'gen_balon_kose',
    'Konuşma balonu (köşeli)',
    150,
    110,
    (c, p) {
      _bubbleTail(
        c,
        p,
        Path()..addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(6, 6, 138, 74),
            const Radius.circular(12),
          ),
        ),
        _o(95, 78),
        _o(120, 78),
        _o(122, 104),
        f: _C.green,
      );
    },
    tags: 'konuşma balonu diyalog köşeli yuvarlak dikdörtgen',
  ),
  WbArtItem(
    'gen_balon_bagir',
    'Bağırma balonu',
    150,
    120,
    (c, p) {
      _poly(
        c,
        p,
        _starPts(_o(75, 55), 62, n: 12, k: 0.68)
            .map((e) => _o(75 + (e.dx - 75) * 1.1, 55 + (e.dy - 55) * 0.85))
            .toList(),
        f: _C.yellow,
        a: 0.6,
      );
    },
    tags: 'bağırma balonu çığlık patlama ünlem heyecan',
  ),
  WbArtItem(
    'gen_balon_dusunce',
    'Düşünce balonu',
    150,
    120,
    (c, p) {
      final path = _cloudPath(75, 48, 1.7);
      c.drawPath(path, p.fill(_C.lightBlue, 0.3));
      c.drawPath(path, p.line);
      for (final e in [
        [40.0, 92.0, 7.0],
        [26.0, 106.0, 5.0],
        [16.0, 116.0, 3.0],
      ]) {
        c.drawCircle(_o(e[0], e[1]), e[2], p.fill(_C.lightBlue, 0.3));
        c.drawCircle(_o(e[0], e[1]), e[2], p.line);
      }
    },
    tags: 'düşünce balonu hayal bulut düşünmek',
  ),
  WbArtItem(
    'gen_balon_fisilti',
    'Fısıltı balonu (kesikli)',
    150,
    110,
    (c, p) {
      final path = Path()..addOval(const Rect.fromLTWH(6, 6, 138, 74));
      c.drawPath(path, p.fill(_C.gray, 0.15));
      p.dashedPath(c, path, dash: 5, gap: 4, paint: p.line);
      p.dashed(c, _o(110, 78), _o(122, 104), paint: p.thin());
      p.dashed(c, _o(122, 104), _o(92, 80), paint: p.thin());
    },
    tags: 'fısıltı balonu kesikli sessiz gizli',
  ),
  WbArtItem(
    'gen_balon_anlatici',
    'Anlatıcı kutusu',
    160,
    90,
    (c, p) {
      _box(c, p, const Rect.fromLTWH(6, 6, 148, 60), f: _C.orange, rad: 3);
      _poly(c, p, [_o(120, 66), _o(132, 84), _o(138, 66)], f: _C.orange);
      _t(c, p, 'ANLATICI', _o(80, 36), size: 11, bold: true);
    },
    tags: 'anlatıcı kutusu çizgi roman balon not',
  ),

  // ───────────── OKLAR / AYRAÇ / ÇERÇEVE ─────────────
  WbArtItem('gen_ok_kivrik', 'Kıvrık ok', 160, 90, (c, p) {
    c.drawPath(
      Path()
        ..moveTo(10, 70)
        ..cubicTo(40, -10, 100, 100, 140, 25),
      p.line,
    );
    p.arrow(c, _o(122, 45), _o(145, 22), size: 11, line: false);
  }, tags: 'ok kıvrık eğri yönlendirme'),
  WbArtItem('gen_ok_donus', 'Dönüş oku', 120, 100, (c, p) {
    c.drawArc(
      Rect.fromCircle(center: _o(60, 52), radius: 36),
      -0.3,
      4.6,
      false,
      p.line,
    );
    p.arrow(c, _o(32, 22), _o(44, 21), size: 12, line: false);
  }, tags: 'ok dönüş tekrar yenile döngü u dönüşü'),
  WbArtItem('gen_ok_cift', 'Çift yönlü ok', 160, 50, (c, p) {
    _ln(c, p, _o(18, 25), _o(142, 25));
    p.arrow(c, _o(40, 25), _o(8, 25), size: 11, line: false);
    p.arrow(c, _o(120, 25), _o(152, 25), size: 11, line: false);
  }, tags: 'ok çift yönlü iki yönlü karşılıklı'),
  WbArtItem('gen_ok_blok', 'Blok ok', 160, 80, (c, p) {
    _poly(
      c,
      p,
      [
        _o(8, 26),
        _o(98, 26),
        _o(98, 8),
        _o(152, 40),
        _o(98, 72),
        _o(98, 54),
        _o(8, 54),
      ],
      f: _C.blue,
      a: 0.4,
    );
  }, tags: 'blok ok kalın ok yön sağ'),
  WbArtItem(
    'gen_ayrac_parantez',
    'Ayraç ve parantezler',
    240,
    110,
    (c, p) {
      final s = [
        ['(', ')'],
        ['[', ']'],
        ['{', '}'],
        ['<', '>'],
      ];
      for (int i = 0; i < 4; i++) {
        _t(
          c,
          p,
          '${s[i][0]} ${s[i][1]}',
          _o(30 + i * 60.0, 35),
          size: 36,
          bold: true,
        );
      }
      for (int i = 0; i < 4; i++) {
        _t(
          c,
          p,
          ['parantez', 'köşeli', 'küme', 'açılı'][i],
          _o(30 + i * 60.0, 70),
          size: 8.5,
        );
      }
      _t(c, p, '“ ”   ‘ ’   « »   -  –  —', _o(120, 96), size: 14, bold: true);
    },
    tags: 'ayraç parantez köşeli küme tırnak noktalama işaret',
  ),
  WbArtItem(
    'gen_ayrac_sus',
    'Süslü ayraçlar',
    260,
    120,
    (c, p) {
      c.drawPath(
        Path()
          ..moveTo(30, 10)
          ..quadraticBezierTo(8, 10, 12, 30)
          ..quadraticBezierTo(14, 40, 20, 42)
          ..quadraticBezierTo(12, 46, 12, 54)
          ..quadraticBezierTo(8, 74, 30, 74),
        p.line,
      );
      c.drawPath(
        Path()
          ..moveTo(230, 10)
          ..quadraticBezierTo(252, 10, 248, 30)
          ..quadraticBezierTo(246, 40, 240, 42)
          ..quadraticBezierTo(248, 46, 248, 54)
          ..quadraticBezierTo(252, 74, 230, 74),
        p.line,
      );
      _ln(c, p, _o(40, 100), _o(105, 100));
      _ln(c, p, _o(155, 100), _o(220, 100));
      _poly(
        c,
        p,
        [_o(130, 90), _o(140, 100), _o(130, 110), _o(120, 100)],
        f: _C.orange,
        a: 0.6,
      );
      _t(c, p, 'Metin', _o(130, 42), size: 12, bold: true);
    },
    tags: 'süslü ayraç küme parantezi çizgi ayırıcı bölücü',
  ),
  WbArtItem('gen_cerceve', 'Çerçeve', 240, 170, (c, p) {
    _box(c, p, const Rect.fromLTWH(6, 6, 228, 158), rad: 10);
    _box(c, p, const Rect.fromLTWH(16, 16, 208, 138), rad: 6, thin: true);
    for (final e in [_o(6, 6), _o(234, 6), _o(6, 164), _o(234, 164)]) {
      c.drawCircle(e, 6, p.fill(_C.orange, 0.8));
      c.drawCircle(e, 6, p.line);
    }
  }, tags: 'çerçeve kenarlık pano başlık'),
  WbArtItem('gen_bordur', 'Süs bordürü', 300, 40, (c, p) {
    _ln(c, p, _o(4, 6), _o(296, 6));
    _ln(c, p, _o(4, 34), _o(296, 34));
    for (int i = 0; i < 12; i++) {
      final x = 20.0 + i * 24;
      if (i.isEven) {
        _poly(
          c,
          p,
          [_o(x, 20), _o(x + 8, 11), _o(x + 16, 20), _o(x + 8, 29)],
          f: _C.orange,
          a: 0.6,
          thin: true,
        );
      } else {
        c.drawCircle(_o(x + 8, 20), 6, p.fill(_C.blue, 0.5));
        c.drawCircle(_o(x + 8, 20), 6, p.thin());
      }
    }
  }, tags: 'bordür süs şerit kenar desen'),
  WbArtItem(
    'gen_serit_etiket',
    'Kâğıt şerit etiket',
    200,
    60,
    (c, p) {
      _poly(
        c,
        p,
        [_o(4, 10), _o(28, 10), _o(36, 30), _o(28, 50), _o(4, 50), _o(14, 30)],
        f: _C.red,
        a: 0.5,
      );
      _poly(
        c,
        p,
        [
          _o(196, 10),
          _o(172, 10),
          _o(164, 30),
          _o(172, 50),
          _o(196, 50),
          _o(186, 30),
        ],
        f: _C.red,
        a: 0.5,
      );
      _box(c, p, const Rect.fromLTWH(24, 4, 152, 42), f: _C.yellow, a: 0.5);
      _t(c, p, 'BAŞLIK', _o(100, 25), size: 13, bold: true);
    },
    tags: 'şerit etiket kurdele banner başlık',
  ),
  WbArtItem(
    'gen_not_kagidi',
    'Not kâğıdı',
    130,
    130,
    (c, p) {
      _poly(
        c,
        p,
        [_o(8, 8), _o(122, 8), _o(122, 94), _o(94, 122), _o(8, 122)],
        f: _C.yellow,
        a: 0.55,
      );
      _poly(
        c,
        p,
        [_o(122, 94), _o(94, 94), _o(94, 122)],
        f: _C.orange,
        a: 0.4,
        thin: true,
      );
      for (final y in [34.0, 54.0, 74.0]) {
        c.drawLine(_o(20, y), _o(108, y), p.thin(0.35));
      }
      c.drawCircle(_o(65, 14), 4, p.fill(_C.red, 0.8));
    },
    tags: 'not kâğıdı yapışkan post-it hatırlatma',
  ),
  WbArtItem(
    'gen_ampul',
    'Ampul (fikir)',
    100,
    130,
    (c, p) {
      final bulb = Path()
        ..moveTo(36, 78)
        ..cubicTo(36, 62, 14, 55, 14, 34)
        ..arcToPoint(
          _o(86, 34),
          radius: const Radius.circular(36),
          clockwise: true,
        )
        ..cubicTo(86, 55, 64, 62, 64, 78)
        ..close();
      _path(c, p, bulb, f: _C.yellow, a: 0.55);
      _box(c, p, const Rect.fromLTWH(36, 80, 28, 8), rad: 2);
      _box(c, p, const Rect.fromLTWH(38, 90, 24, 8), rad: 2);
      _ln(c, p, _o(44, 100), _o(56, 100));
      c.drawPath(
        Path()
          ..moveTo(42, 78)
          ..lineTo(42, 52)
          ..lineTo(50, 44)
          ..lineTo(58, 52)
          ..lineTo(58, 78),
        p.thin(),
      );
      for (final a in [-2.2, -1.57, -0.9]) {
        c.drawLine(
          _o(50 + 44 * math.cos(a), 34 + 44 * math.sin(a)),
          _o(50 + 56 * math.cos(a), 34 + 56 * math.sin(a)),
          p.stroke(_C.orange),
        );
      }
      c.drawLine(_o(2, 34), _o(-8, 34), p.stroke(_C.orange));
      c.drawLine(_o(98, 34), _o(108, 34), p.stroke(_C.orange));
    },
    tags: 'ampul fikir buluş yaratıcılık düşünce',
  ),

  // ───────────── OKUL NESNELERİ ─────────────
  WbArtItem('gen_kitap', 'Kitap', 130, 110, (c, p) {
    _poly(
      c,
      p,
      [_o(65, 28), _o(10, 18), _o(10, 94), _o(65, 104)],
      f: _C.blue,
      a: 0.3,
    );
    _poly(
      c,
      p,
      [_o(65, 28), _o(120, 18), _o(120, 94), _o(65, 104)],
      f: _C.lightBlue,
      a: 0.35,
    );
    for (final y in [40.0, 54.0, 68.0]) {
      c.drawLine(_o(18, y - 4), _o(58, y + 4), p.thin(0.35));
      c.drawLine(_o(72, y + 4), _o(112, y - 4), p.thin(0.35));
    }
  }, tags: 'kitap açık kitap okuma ders'),
  WbArtItem('gen_kalem', 'Kalem', 40, 150, (c, p) {
    _poly(
      c,
      p,
      [_o(12, 20), _o(28, 20), _o(28, 110), _o(20, 130), _o(12, 110)],
      f: _C.yellow,
      a: 0.6,
    );
    _poly(
      c,
      p,
      [_o(12, 110), _o(28, 110), _o(20, 130)],
      f: _C.brown,
      a: 0.3,
      thin: true,
    );
    _poly(
      c,
      p,
      [_o(17, 122), _o(23, 122), _o(20, 130)],
      f: _C.gray,
      a: 0.9,
      thin: true,
    );
    _box(c, p, const Rect.fromLTWH(12, 8, 16, 12), f: _C.pink, a: 0.6, rad: 2);
    c.drawLine(_o(12, 26), _o(28, 26), p.thin());
    c.drawLine(_o(20, 30), _o(20, 106), p.thin(0.4));
  }, tags: 'kalem kurşun kalem yazı okul'),
  WbArtItem('gen_defter', 'Defter', 100, 140, (c, p) {
    _box(
      c,
      p,
      const Rect.fromLTWH(14, 6, 80, 128),
      f: _C.lightBlue,
      a: 0.3,
      rad: 5,
    );
    for (final y in [26.0, 42.0, 58.0, 74.0, 90.0, 106.0]) {
      c.drawLine(_o(26, y), _o(86, y), p.thin(0.35));
    }
    for (int i = 0; i < 7; i++) {
      c.drawCircle(_o(14, 18 + i * 18.0), 4, p.fill(_C.gray, 0.8));
      c.drawCircle(_o(14, 18 + i * 18.0), 4, p.thin());
    }
  }, tags: 'defter spiral not okul yazı'),
  WbArtItem('gen_cetvel', 'Cetvel', 170, 50, (c, p) {
    _box(
      c,
      p,
      const Rect.fromLTWH(6, 8, 158, 34),
      f: _C.yellow,
      a: 0.4,
      rad: 3,
    );
    for (int i = 0; i <= 15; i++) {
      final x = 12.0 + i * 9.8;
      c.drawLine(_o(x, 8), _o(x, i % 5 == 0 ? 24 : 17), p.thin(0.4));
      if (i % 5 == 0) _t(c, p, '${i ~/ 5 * 5}', _o(x, 31), size: 7);
    }
  }, tags: 'cetvel ölçü uzunluk santimetre geometri'),
  WbArtItem('gen_silgi', 'Silgi', 110, 70, (c, p) {
    _poly(
      c,
      p,
      [_o(10, 56), _o(34, 14), _o(100, 14), _o(76, 56)],
      f: _C.pink,
      a: 0.5,
    );
    _poly(
      c,
      p,
      [_o(10, 56), _o(34, 14), _o(52, 14), _o(28, 56)],
      f: _C.blue,
      a: 0.4,
      thin: true,
    );
    c.drawLine(_o(28, 56), _o(76, 56), p.thin());
  }, tags: 'silgi okul silmek'),
  WbArtItem('gen_canta', 'Okul çantası', 120, 140, (c, p) {
    c.drawPath(
      Path()
        ..moveTo(38, 24)
        ..quadraticBezierTo(60, -8, 82, 24),
      p.line,
    );
    _box(
      c,
      p,
      const Rect.fromLTWH(14, 24, 92, 104),
      f: _C.red,
      a: 0.4,
      rad: 14,
    );
    _box(
      c,
      p,
      const Rect.fromLTWH(26, 76, 68, 40),
      f: _C.orange,
      a: 0.4,
      rad: 6,
    );
    c.drawArc(const Rect.fromLTWH(14, 24, 92, 60), 0.1, 2.94, false, p.thin());
    c.drawCircle(_o(60, 60), 5, p.fill(_C.yellow, 0.9));
    c.drawCircle(_o(60, 60), 5, p.thin());
    _box(c, p, const Rect.fromLTWH(2, 62, 12, 40), f: _C.red, a: 0.4, rad: 4);
    _box(c, p, const Rect.fromLTWH(106, 62, 12, 40), f: _C.red, a: 0.4, rad: 4);
  }, tags: 'çanta okul çantası sırt çantası'),
];

void _noteHead(Canvas c, WbArtPen p, Offset ct, {bool filled = true}) {
  c.save();
  c.translate(ct.dx, ct.dy);
  c.rotate(-0.4);
  final r = Rect.fromCenter(center: Offset.zero, width: 15, height: 10.5);
  if (filled) c.drawOval(r, p.solid);
  c.drawOval(r, p.line);
  c.restore();
}

void _staff(Canvas c, WbArtPen p, double x0, double x1, double y0, double gap) {
  for (int i = 0; i < 5; i++) {
    c.drawLine(_o(x0, y0 + i * gap), _o(x1, y0 + i * gap), p.thin(0.4));
  }
}

final List<WbArtItem> _gen2 = [
  // ───────────── BAYRAK ─────────────
  WbArtItem(
    'gen_turk_bayragi',
    'Türk bayrağı',
    160,
    110,
    (c, p) {
      // Oran 2:3 (A = 100): ay dış çember Ø A/2, iç çember Ø 0.4A, yıldız Ø A/4.
      const dx = 5.0, dy = 5.0;
      c.drawRect(
        const Rect.fromLTWH(dx, dy, 150, 100),
        Paint()..color = const Color(0xFFE30A17),
      );
      c.drawRect(const Rect.fromLTWH(dx, dy, 150, 100), p.line);
      final moon = Path.combine(
        PathOperation.difference,
        Path()
          ..addOval(Rect.fromCircle(center: _o(dx + 50, dy + 50), radius: 25)),
        Path()..addOval(
          Rect.fromCircle(center: _o(dx + 56.25, dy + 50), radius: 20),
        ),
      );
      c.drawPath(moon, Paint()..color = Colors.white);
      final star = WbArtPen.poly(
        _starPts(_o(dx + 80, dy + 50), 12.5, k: 0.382, start: math.pi),
      );
      c.drawPath(star, Paint()..color = Colors.white);
    },
    tags: 'türk bayrağı bayrak ay yıldız türkiye 29 ekim 23 nisan',
  ),

  // ───────────── BASİT SİMGELER ─────────────
  WbArtItem('gen_kalp', 'Kalp', 100, 90, (c, p) {
    _heart(c, p, _o(50, 42), 38);
  }, tags: 'kalp sevgi aşk'),
  WbArtItem('gen_yildiz_basit', 'Yıldız', 100, 100, (c, p) {
    _poly(c, p, _starPts(_o(50, 54), 44), f: _C.yellow, a: 0.7);
  }, tags: 'yıldız gökyüzü gece'),
  WbArtItem('gen_ay', 'Ay (hilal)', 90, 100, (c, p) {
    final moon = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: _o(45, 50), radius: 38)),
      Path()..addOval(Rect.fromCircle(center: _o(62, 42), radius: 32)),
    );
    _path(c, p, moon, f: _C.yellow, a: 0.6);
  }, tags: 'ay hilal gece gökyüzü'),
  WbArtItem('gen_gunes', 'Güneş', 120, 120, (c, p) {
    _sun(c, p, _o(60, 60), 28);
    c.drawArc(
      Rect.fromCircle(center: _o(52, 58), radius: 14),
      0.4,
      1.6,
      false,
      p.thin(),
    );
  }, tags: 'güneş hava sıcak yaz ışık'),
  WbArtItem('gen_bulut', 'Bulut', 130, 80, (c, p) {
    _path(c, p, _cloudPath(65, 40, 1.3), f: _C.lightBlue, a: 0.4);
  }, tags: 'bulut hava bulutlu gökyüzü'),

  // ───────────── TRAFİK ─────────────
  WbArtItem(
    'gen_trafik_dur',
    'Trafik: DUR',
    110,
    110,
    (c, p) {
      final pts = WbArtPen.regular(_o(55, 55), 50, 8, -math.pi / 8);
      c.drawPath(WbArtPen.poly(pts), Paint()..color = const Color(0xFFDC2626));
      c.drawPath(
        WbArtPen.poly(WbArtPen.regular(_o(55, 55), 44, 8, -math.pi / 8)),
        p.stroke(Colors.white, 0.5),
      );
      c.drawPath(WbArtPen.poly(pts), p.line);
      _t(c, p, 'DUR', _o(55, 55), size: 26, bold: true, col: Colors.white);
    },
    tags: 'trafik işareti dur levhası sekizgen trafik kuralları',
  ),
  WbArtItem(
    'gen_trafik_yaya',
    'Trafik: Yaya geçidi',
    110,
    120,
    (c, p) {
      _box(c, p, const Rect.fromLTWH(6, 6, 98, 98), f: _C.blue, a: 0.8, rad: 8);
      _poly(
        c,
        p,
        [_o(55, 14), _o(96, 90), _o(14, 90)],
        f: Colors.white,
        a: 0.95,
      );
      c.drawCircle(_o(55, 38), 5, p.fill(Colors.black87));
      c.drawLine(_o(55, 44), _o(55, 64), p.stroke(Colors.black87, 1.6));
      c.drawLine(_o(55, 50), _o(46, 58), p.stroke(Colors.black87, 1.2));
      c.drawLine(_o(55, 50), _o(64, 58), p.stroke(Colors.black87, 1.2));
      c.drawLine(_o(55, 64), _o(48, 78), p.stroke(Colors.black87, 1.2));
      c.drawLine(_o(55, 64), _o(63, 78), p.stroke(Colors.black87, 1.2));
      for (int i = 0; i < 5; i++) {
        c.drawRect(
          Rect.fromLTWH(12.0 + i * 20, 108, 12, 8),
          p.fill(Colors.black87, 0.8),
        );
      }
    },
    tags: 'trafik işareti yaya geçidi geçit yaya kural',
  ),
  WbArtItem(
    'gen_trafik_hiz',
    'Trafik: Hız limiti',
    110,
    110,
    (c, p) {
      c.drawCircle(_o(55, 55), 48, p.fill(Colors.white));
      c.drawCircle(_o(55, 55), 48, p.stroke(const Color(0xFFDC2626), 4));
      _t(c, p, '50', _o(55, 55), size: 38, bold: true, col: Colors.black87);
    },
    tags: 'trafik işareti hız limiti sınırı 50 yasak levha',
  ),

  // ───────────── ÇEVRE / İLK YARDIM ─────────────
  WbArtItem(
    'gen_geri_donusum',
    'Geri dönüşüm simgesi',
    120,
    120,
    (c, p) {
      for (int i = 0; i < 3; i++) {
        final s = -90 + i * 120 + 14.0;
        c.drawArc(
          Rect.fromCircle(center: _o(60, 64), radius: 38),
          s * math.pi / 180,
          78 * math.pi / 180,
          false,
          p.stroke(_C.green, 2.4),
        );
        final ea = (s + 78) * math.pi / 180;
        p.arrow(
          c,
          _o(60 + 38 * math.cos(ea - 0.15), 64 + 38 * math.sin(ea - 0.15)),
          _o(60 + 38 * math.cos(ea + 0.2), 64 + 38 * math.sin(ea + 0.2)),
          c: _C.green,
          size: 13,
          line: false,
        );
      }
    },
    tags: 'geri dönüşüm çevre geri kazanım atık sıfır atık',
  ),
  WbArtItem(
    'gen_cop_kutusu',
    'Geri dönüşüm kutusu',
    100,
    130,
    (c, p) {
      _poly(
        c,
        p,
        [_o(16, 32), _o(84, 32), _o(76, 122), _o(24, 122)],
        f: _C.green,
        a: 0.4,
      );
      _box(
        c,
        p,
        const Rect.fromLTWH(10, 20, 80, 12),
        f: _C.darkGreen,
        a: 0.5,
        rad: 3,
      );
      _box(c, p, const Rect.fromLTWH(38, 10, 24, 10), rad: 3, thin: true);
      for (final x in [38.0, 50.0, 62.0]) {
        c.drawLine(_o(x, 44), _o(x - 1, 110), p.thin(0.4));
      }
    },
    tags: 'çöp kutusu geri dönüşüm çevre atık temizlik',
  ),
  WbArtItem('gen_yaprak', 'Yaprak', 90, 110, (c, p) {
    final leaf = Path()
      ..moveTo(45, 100)
      ..cubicTo(-10, 70, 10, 20, 45, 6)
      ..cubicTo(80, 20, 100, 70, 45, 100)
      ..close();
    _path(c, p, leaf, f: _C.green, a: 0.45);
    c.drawLine(_o(45, 100), _o(45, 24), p.thin());
    for (final y in [40.0, 58.0, 76.0]) {
      c.drawLine(_o(45, y + 8), _o(30, y), p.thin(0.4));
      c.drawLine(_o(45, y + 8), _o(60, y), p.thin(0.4));
    }
  }, tags: 'yaprak doğa çevre bitki ağaç'),
  WbArtItem(
    'gen_ilk_yardim',
    'İlk yardım işareti',
    110,
    110,
    (c, p) {
      _box(
        c,
        p,
        const Rect.fromLTWH(8, 8, 94, 94),
        f: _C.green,
        a: 0.9,
        rad: 10,
      );
      final cross = WbArtPen.poly([
        _o(44, 20),
        _o(66, 20),
        _o(66, 44),
        _o(90, 44),
        _o(90, 66),
        _o(66, 66),
        _o(66, 90),
        _o(44, 90),
        _o(44, 66),
        _o(20, 66),
        _o(20, 44),
        _o(44, 44),
      ]);
      c.drawPath(cross, Paint()..color = Colors.white);
    },
    tags: 'ilk yardım haç artı sağlık acil yardım',
  ),

  // ───────────── MÜZİK ─────────────
  WbArtItem('gen_nota', 'Nota (sekizlik)', 70, 110, (c, p) {
    _noteHead(c, p, _o(24, 88));
    c.drawLine(_o(31, 86), _o(31, 18), p.line);
    c.drawPath(
      Path()
        ..moveTo(31, 18)
        ..cubicTo(34, 40, 56, 44, 52, 66),
      p.line,
    );
  }, tags: 'nota müzik sekizlik ses melodi'),
  WbArtItem(
    'gen_porte_sol',
    'Porte ve sol anahtarı',
    260,
    110,
    (c, p) {
      _staff(c, p, 10, 250, 30, 12);
      c.drawLine(_o(10, 30), _o(10, 78), p.line);
      c.drawLine(_o(250, 30), _o(250, 78), p.line);
      final cl = Path()
        ..moveTo(36, 62)
        ..cubicTo(26, 54, 40, 40, 46, 50)
        ..cubicTo(52, 62, 34, 70, 30, 60)
        ..moveTo(40, 52)
        ..cubicTo(52, 34, 46, 14, 40, 14)
        ..cubicTo(34, 14, 34, 50, 38, 70)
        ..cubicTo(40, 88, 40, 96, 30, 96)
        ..cubicTo(22, 96, 24, 86, 32, 88);
      c.drawPath(cl, p.stroke(_C.purple, 1.1));
      _noteHead(c, p, _o(100, 66));
      c.drawLine(_o(107, 64), _o(107, 30), p.line);
      _noteHead(c, p, _o(150, 54), filled: false);
      c.drawLine(_o(157, 52), _o(157, 20), p.line);
      _noteHead(c, p, _o(200, 42));
      c.drawLine(_o(193, 44), _o(193, 76), p.line);
    },
    tags: 'porte beş çizgi sol anahtarı müzik nota yazı',
  ),
  WbArtItem(
    'gen_nota_degerleri',
    'Nota değerleri',
    300,
    130,
    (c, p) {
      final nm = ['Bütün', 'İkilik', 'Dörtlük', 'Sekizlik', 'Onaltılık'];
      final bt = ['4', '2', '1', '½', '¼'];
      for (int i = 0; i < 5; i++) {
        final x = 30.0 + i * 60;
        _noteHead(c, p, _o(x, 56), filled: i >= 2);
        if (i > 0) c.drawLine(_o(x + 7, 54), _o(x + 7, 18), p.line);
        if (i >= 3)
          c.drawPath(
            Path()
              ..moveTo(x + 7, 18)
              ..cubicTo(x + 10, 30, x + 24, 32, x + 20, 44),
            p.line,
          );
        if (i == 4)
          c.drawPath(
            Path()
              ..moveTo(x + 7, 28)
              ..cubicTo(x + 10, 40, x + 24, 42, x + 20, 54),
            p.line,
          );
        _t(c, p, nm[i], _o(x, 88), size: 9, bold: true);
        _t(c, p, '${bt[i]} vuruş', _o(x, 104), size: 8, col: _C.gray);
      }
    },
    tags: 'nota değerleri bütün ikilik dörtlük sekizlik onaltılık müzik ritim',
  ),

  // ───────────── TÜRKÇE ─────────────
  WbArtItem(
    'gen_cumle_ogeleri',
    'Cümle öğeleri tablosu',
    320,
    160,
    (c, p) {
      _grid(c, p, const Rect.fromLTWH(6, 6, 308, 148), 4, 5);
      c.drawRect(const Rect.fromLTWH(6, 6, 308, 37), p.fill(_C.orange, 0.3));
      final h = ['Cümle', 'Özne', 'Nesne', 'Tümleç', 'Yüklem'];
      for (int i = 0; i < 5; i++) {
        _t(c, p, h[i], _o(6 + 30.8 + i * 61.6, 24), size: 9.5, bold: true);
      }
    },
    tags: 'cümle öğeleri özne yüklem nesne tümleç türkçe tablo dil bilgisi',
  ),
  WbArtItem(
    'gen_hece_ses',
    'Hece ve ses şeması',
    260,
    170,
    (c, p) {
      _t(c, p, 'Sözcük:', _o(8, 36), size: 9.5, anchor: 'left', bold: true);
      _box(c, p, const Rect.fromLTWH(60, 22, 130, 28), f: _C.blue, rad: 6);
      _t(c, p, 'kitap', _o(125, 36), size: 12, bold: true);
      _t(c, p, 'Hece:', _o(8, 84), size: 9.5, anchor: 'left', bold: true);
      _ln(c, p, _o(100, 50), _o(85, 70));
      _ln(c, p, _o(150, 50), _o(165, 70));
      _box(c, p, const Rect.fromLTWH(60, 70, 50, 28), f: _C.green, rad: 6);
      _box(c, p, const Rect.fromLTWH(140, 70, 70, 28), f: _C.green, rad: 6);
      _t(c, p, 'ki', _o(85, 84), size: 12, bold: true);
      _t(c, p, 'tap', _o(175, 84), size: 12, bold: true);
      _t(c, p, 'Ses:', _o(8, 138), size: 9.5, anchor: 'left', bold: true);
      final ls = ['k', 'i', 't', 'a', 'p'];
      for (int i = 0; i < 5; i++) {
        final x = 66.0 + i * 36;
        c.drawLine(_o(i < 2 ? 85 : 175, 98), _o(x + 12, 118), p.thin());
        _box(
          c,
          p,
          Rect.fromLTWH(x, 118, 24, 30),
          f: i == 1 || i == 3 ? _C.red : _C.yellow,
          rad: 4,
        );
        _t(c, p, ls[i], _o(x + 12, 133), size: 12, bold: true);
      }
    },
    tags: 'hece ses şeması harf sözcük türkçe okuma yazma ünlü ünsüz',
  ),
  WbArtItem(
    'gen_kafiye',
    'Şiir kafiye şeması',
    240,
    170,
    (c, p) {
      final l = [
        'Mısra 1 ..................',
        'Mısra 2 ..................',
        'Mısra 3 ..................',
        'Mısra 4 ..................',
      ];
      final k = ['a', 'b', 'a', 'b'];
      for (int i = 0; i < 4; i++) {
        final y = 22.0 + i * 38;
        _t(c, p, l[i], _o(8, y), size: 10, anchor: 'left');
        _t(
          c,
          p,
          k[i],
          _o(205, y),
          size: 14,
          bold: true,
          col: k[i] == 'a' ? _C.red : _C.blue,
        );
      }
      c.drawPath(
        Path()
          ..moveTo(222, 22)
          ..lineTo(232, 22)
          ..lineTo(232, 98)
          ..lineTo(222, 98),
        p.stroke(_C.red, 0.6),
      );
      c.drawPath(
        Path()
          ..moveTo(222, 60)
          ..lineTo(228, 60)
          ..lineTo(228, 136)
          ..lineTo(222, 136),
        p.stroke(_C.blue, 0.6),
      );
      _t(
        c,
        p,
        'Kafiye: abab',
        _o(120, 162),
        size: 10,
        bold: true,
        col: _C.gray,
      );
    },
    tags: 'şiir kafiye uyak mısra dörtlük türkçe edebiyat',
  ),
  WbArtItem(
    'gen_yazi_cizgisi',
    'İlkokul yazı çizgisi (4\'lü)',
    300,
    190,
    (c, p) {
      for (int g = 0; g < 3; g++) {
        final y = 12.0 + g * 62;
        c.drawLine(_o(6, y), _o(294, y), p.thin(0.45));
        p.dashed(
          c,
          _o(6, y + 14),
          _o(294, y + 14),
          paint: p.stroke(_C.gray, 0.4),
        );
        c.drawLine(_o(6, y + 28), _o(294, y + 28), p.stroke(_C.red, 0.55));
        c.drawLine(_o(6, y + 42), _o(294, y + 42), p.thin(0.45));
      }
    },
    tags: 'el yazısı çizgili satır ilkokul yazı çizgisi dört çizgi yazma',
  ),
  WbArtItem(
    'gen_alfabe',
    'Türk alfabesi (29 harf)',
    320,
    130,
    (c, p) {
      const big = 'ABCÇDEFGĞHIİJKLMNOÖPRSŞTUÜVYZ';
      const small = 'abcçdefgğhıijklmnoöprsştuüvyz';
      for (int i = 0; i < 29; i++) {
        final r = Rect.fromLTWH(
          5.0 + (i % 10) * 31,
          5.0 + (i ~/ 10) * 40,
          31,
          40,
        );
        c.drawRect(r, p.fill(i % 2 == 0 ? _C.lightBlue : _C.yellow, 0.2));
        c.drawRect(r, p.thin(0.4));
        _t(c, p, '${big[i]}${small[i]}', r.center, size: 14, bold: true);
      }
    },
    tags: 'alfabe harfler büyük küçük türk alfabesi 29 harf okuma yazma',
  ),
  WbArtItem(
    'gen_rakamlar',
    'Rakamlar 0-9 şeridi',
    320,
    60,
    (c, p) {
      for (int i = 0; i < 10; i++) {
        final r = Rect.fromLTWH(5.0 + i * 31, 5, 31, 50);
        final cols = [
          _C.red,
          _C.orange,
          _C.yellow,
          _C.green,
          _C.teal,
          _C.blue,
          _C.purple,
          _C.pink,
          _C.brown,
          _C.gray,
        ];
        c.drawRect(r, p.fill(cols[i], 0.25));
        c.drawRect(r, p.thin(0.5));
        _t(c, p, '$i', r.center, size: 28, bold: true);
      }
    },
    tags: 'rakamlar sayı şeridi 0 1 2 3 4 5 6 7 8 9 matematik',
  ),

  // ───────────── MATEMATİK ─────────────
  WbArtItem(
    'gen_basamak_bloklari',
    'Basamak blokları (yüzlük-onluk-birlik)',
    260,
    160,
    (c, p) {
      _box(c, p, const Rect.fromLTWH(8, 8, 100, 100), f: _C.blue, a: 0.2);
      for (int i = 1; i < 10; i++) {
        c.drawLine(_o(8 + i * 10.0, 8), _o(8 + i * 10.0, 108), p.thin(0.3));
        c.drawLine(_o(8, 8 + i * 10.0), _o(108, 8 + i * 10.0), p.thin(0.3));
      }
      _t(c, p, 'Yüzlük (100)', _o(58, 124), size: 9.5, bold: true);
      _box(c, p, const Rect.fromLTWH(138, 8, 10, 100), f: _C.green, a: 0.3);
      for (int i = 1; i < 10; i++) {
        c.drawLine(_o(138, 8 + i * 10.0), _o(148, 8 + i * 10.0), p.thin(0.3));
      }
      _t(c, p, 'Onluk (10)', _o(143, 124), size: 9.5, bold: true);
      _box(c, p, const Rect.fromLTWH(198, 88, 20, 20), f: _C.red, a: 0.3);
      _poly(
        c,
        p,
        [_o(198, 88), _o(206, 80), _o(226, 80), _o(218, 88)],
        f: _C.red,
        a: 0.15,
      );
      _poly(
        c,
        p,
        [_o(218, 88), _o(226, 80), _o(226, 100), _o(218, 108)],
        f: _C.red,
        a: 0.45,
      );
      _t(c, p, 'Birlik (1)', _o(212, 124), size: 9.5, bold: true);
    },
    tags: 'basamak blokları onluk çubuk yüzlük kare birlik küp matematik sayı',
  ),
  WbArtItem('gen_abakus', 'Abaküs', 240, 170, (c, p) {
    _box(c, p, const Rect.fromLTWH(6, 6, 228, 158), rad: 6);
    final cols = [_C.red, _C.orange, _C.green, _C.blue, _C.purple];
    for (int r = 0; r < 5; r++) {
      final y = 24.0 + r * 30;
      c.drawLine(_o(10, y), _o(230, y), p.thin(0.7));
      final moved = [3, 5, 2, 7, 4][r];
      for (int b = 0; b < 10; b++) {
        final x = b < moved ? 20.0 + b * 15 : 90.0 + b * 15;
        _ell(
          c,
          p,
          Rect.fromCenter(center: _o(x, y), width: 14, height: 18),
          f: cols[r],
          a: 0.7,
          thin: true,
        );
      }
    }
  }, tags: 'abaküs sayı sayma boncuk hesap matematik'),
  WbArtItem(
    'gen_geometri_tahtasi',
    'Geometri tahtası (çivili)',
    190,
    190,
    (c, p) {
      _box(
        c,
        p,
        const Rect.fromLTWH(6, 6, 178, 178),
        f: _C.brown,
        a: 0.2,
        rad: 8,
      );
      for (int i = 0; i < 6; i++) {
        for (int j = 0; j < 6; j++) {
          c.drawCircle(
            _o(24.0 + i * 28, 24.0 + j * 28),
            3,
            p.fill(_C.gray, 0.95),
          );
          c.drawCircle(_o(24.0 + i * 28, 24.0 + j * 28), 3, p.thin(0.4));
        }
      }
      final band = WbArtPen.poly([
        _o(52, 108),
        _o(52, 52),
        _o(136, 52),
        _o(164, 108),
      ]);
      c.drawPath(band, p.stroke(_C.red, 0.8));
    },
    tags: 'geometri tahtası çivili tahta lastik şekil çokgen alan çevre',
  ),
  WbArtItem(
    'gen_tangram',
    'Tangram (7 parça)',
    130,
    130,
    (c, p) {
      c.save();
      c.translate(15, 15);
      _poly(c, p, [_o(0, 0), _o(100, 0), _o(50, 50)], f: _C.red, a: 0.45);
      _poly(c, p, [_o(0, 0), _o(0, 100), _o(50, 50)], f: _C.blue, a: 0.45);
      _poly(c, p, [_o(100, 0), _o(100, 50), _o(75, 25)], f: _C.green, a: 0.5);
      _poly(
        c,
        p,
        [_o(100, 50), _o(100, 100), _o(50, 100)],
        f: _C.orange,
        a: 0.5,
      );
      _poly(
        c,
        p,
        [_o(50, 50), _o(75, 25), _o(100, 50), _o(75, 75)],
        f: _C.yellow,
        a: 0.55,
      );
      _poly(c, p, [_o(50, 50), _o(75, 75), _o(25, 75)], f: _C.purple, a: 0.45);
      _poly(
        c,
        p,
        [_o(25, 75), _o(75, 75), _o(50, 100), _o(0, 100)],
        f: _C.teal,
        a: 0.45,
      );
      c.restore();
    },
    tags: 'tangram yedi parça geometri üçgen kare paralelkenar bulmaca',
  ),
  WbArtItem(
    'gen_saat',
    'Saat yüzü',
    140,
    140,
    (c, p) {
      c.drawCircle(_o(70, 70), 62, p.fill(_C.lightBlue, 0.2));
      c.drawCircle(_o(70, 70), 62, p.line);
      for (int i = 0; i < 60; i++) {
        final a = i * math.pi / 30;
        final r1 = i % 5 == 0 ? 50.0 : 55.0;
        c.drawLine(
          _o(70 + 58 * math.cos(a), 70 + 58 * math.sin(a)),
          _o(70 + r1 * math.cos(a), 70 + r1 * math.sin(a)),
          p.thin(i % 5 == 0 ? 0.8 : 0.4),
        );
      }
      for (int i = 1; i <= 12; i++) {
        final a = i * math.pi / 6 - math.pi / 2;
        _t(
          c,
          p,
          '$i',
          _o(70 + 41 * math.cos(a), 70 + 41 * math.sin(a)),
          size: 11,
          bold: true,
        );
      }
      final ha = (10 + 10 / 60) * math.pi / 6 - math.pi / 2;
      final ma = 10 * math.pi / 30 - math.pi / 2;
      c.drawLine(
        _o(70, 70),
        _o(70 + 28 * math.cos(ha), 70 + 28 * math.sin(ha)),
        p.stroke(_C.red, 1.8),
      );
      c.drawLine(
        _o(70, 70),
        _o(70 + 42 * math.cos(ma), 70 + 42 * math.sin(ma)),
        p.stroke(_C.blue, 1.2),
      );
      c.drawCircle(_o(70, 70), 3.5, p.solid);
    },
    tags: 'saat yüzü akrep yelkovan zaman saat okuma matematik',
  ),
  WbArtItem(
    'gen_para_madeni',
    'Para (TL madeni)',
    100,
    100,
    (c, p) {
      c.drawCircle(_o(50, 50), 44, p.fill(_C.yellow, 0.5));
      c.drawCircle(_o(50, 50), 44, p.line);
      c.drawCircle(_o(50, 50), 30, p.fill(_C.gray, 0.4));
      c.drawCircle(_o(50, 50), 30, p.thin());
      _t(c, p, '1 TL', _o(50, 50), size: 17, bold: true);
    },
    tags: 'para madeni para lira tl kuruş alışveriş matematik',
  ),
  WbArtItem(
    'gen_banknot',
    'Para (TL banknot)',
    180,
    100,
    (c, p) {
      _box(
        c,
        p,
        const Rect.fromLTWH(6, 6, 168, 88),
        f: _C.green,
        a: 0.3,
        rad: 6,
      );
      _box(c, p, const Rect.fromLTWH(12, 12, 156, 76), rad: 4, thin: true);
      c.drawCircle(_o(46, 50), 22, p.fill(_C.yellow, 0.4));
      c.drawCircle(_o(46, 50), 22, p.thin());
      _t(c, p, '20', _o(46, 50), size: 18, bold: true);
      _t(c, p, '20 TL', _o(124, 36), size: 20, bold: true);
      _t(c, p, 'BANKNOT', _o(124, 66), size: 9, col: _C.gray);
    },
    tags: 'banknot kâğıt para lira tl alışveriş matematik',
  ),
  WbArtItem(
    'gen_takvim_yaprak',
    'Takvim yaprağı',
    120,
    140,
    (c, p) {
      _box(
        c,
        p,
        const Rect.fromLTWH(10, 14, 100, 118),
        f: Colors.white,
        a: 0.2,
        rad: 8,
      );
      c.drawPath(
        Path()..addRRect(
          RRect.fromRectAndCorners(
            const Rect.fromLTWH(10, 14, 100, 34),
            topLeft: const Radius.circular(8),
            topRight: const Radius.circular(8),
          ),
        ),
        p.fill(_C.red, 0.7),
      );
      _t(c, p, 'KASIM', _o(60, 31), size: 11, bold: true, col: Colors.white);
      _t(c, p, '21', _o(60, 90), size: 44, bold: true);
      for (final x in [34.0, 86.0]) {
        c.drawCircle(_o(x, 14), 4, p.fill(_C.gray));
        c.drawLine(_o(x, 8), _o(x, 16), p.line);
      }
    },
    tags: 'takvim yaprağı gün tarih ay kasım',
  ),
  WbArtItem(
    'gen_termometre',
    'Termometre (hava)',
    90,
    190,
    (c, p) {
      _box(c, p, const Rect.fromLTWH(30, 8, 22, 130), rad: 11, thin: false);
      c.drawCircle(_o(41, 156), 22, p.fill(_C.red, 0.85));
      c.drawCircle(_o(41, 156), 22, p.line);
      c.drawRect(const Rect.fromLTWH(37, 60, 8, 96), p.fill(_C.red, 0.85));
      for (int i = 0; i <= 8; i++) {
        final y = 130 - i * 14.0;
        c.drawLine(_o(56, y), _o(i.isEven ? 68 : 63, y), p.thin(0.6));
        if (i.isEven)
          _t(c, p, '${i * 5 - 10}', _o(70, y), size: 7.5, anchor: 'left');
      }
    },
    tags: 'termometre sıcaklık derece hava durumu ısı',
  ),
  WbArtItem(
    'gen_hava_tablosu',
    'Hava durumu tablosu',
    300,
    150,
    (c, p) {
      _grid(c, p, const Rect.fromLTWH(6, 6, 288, 138), 3, 6);
      final d = ['', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum'];
      for (int i = 1; i < 6; i++) {
        _t(c, p, d[i], _o(6 + 48 * i + 24, 29), size: 10, bold: true);
      }
      c.drawRect(
        const Rect.fromLTWH(6, 6, 288, 46),
        p.fill(_C.lightBlue, 0.25),
      );
      _sun(c, p, _o(30, 75), 8);
      _drop(c, p, _o(30, 121), 8);
      _t(c, p, 'Güneşli', _o(30, 94), size: 7.5);
      _t(c, p, 'Yağmurlu', _o(30, 136), size: 7.5);
    },
    tags: 'hava durumu tablosu yağmur güneş haftalık gözlem fen',
  ),
];
