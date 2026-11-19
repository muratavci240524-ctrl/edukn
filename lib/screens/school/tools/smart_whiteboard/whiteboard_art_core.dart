import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Şekil kütüphanesi (clip-art) için ortak tipler ve çizim yardımcıları.
///
/// Her şekil kendi "tasarım kutusu" (w × h birim) içinde çizilir. Tahtada
/// nesne büyütülüp küçültülürken kutu orantılı ölçeklenir.

/// Aksan renkleri (ana çizgi rengi kullanıcı rengidir, bunlar sabittir).
class WbArtColors {
  static const blue = Color(0xFF3B82F6);
  static const lightBlue = Color(0xFF93C5FD);
  static const red = Color(0xFFEF4444);
  static const green = Color(0xFF22C55E);
  static const darkGreen = Color(0xFF15803D);
  static const yellow = Color(0xFFFACC15);
  static const orange = Color(0xFFF97316);
  static const purple = Color(0xFF8B5CF6);
  static const pink = Color(0xFFEC4899);
  static const brown = Color(0xFF92400E);
  static const gray = Color(0xFF94A3B8);
  static const teal = Color(0xFF14B8A6);
}

/// Çizim kalemi: ana renk + çizgi kalınlığı (tasarım birimi cinsinden).
class WbArtPen {
  WbArtPen(this.color, this.w);
  final Color color;
  final double w;

  /// Ana çizgi.
  Paint get line => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  /// İnce yardımcı çizgi (ana renkte).
  Paint thin([double factor = 0.5]) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.4, w * factor)
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  /// Renkli çizgi.
  Paint stroke(Color c, [double factor = 1]) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.4, w * factor)
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  /// Dolgu (opaklık verilebilir).
  Paint fill(Color c, [double alpha = 1]) => Paint()
    ..color = c.withValues(alpha: alpha)
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  /// Ana renkte dolgu.
  Paint get solid => fill(color);

  /// Kesikli çizgi çizer.
  void dashed(Canvas canvas, Offset a, Offset b, {double dash = 4, double gap = 3, Paint? paint}) {
    final p = paint ?? thin();
    final d = b - a;
    final len = d.distance;
    if (len == 0) return;
    final dir = d / len;
    double t = 0;
    while (t < len) {
      final e = math.min(t + dash, len);
      canvas.drawLine(a + dir * t, a + dir * e, p);
      t += dash + gap;
    }
  }

  /// Kesikli yol (daire, eğri vb.).
  void dashedPath(Canvas canvas, Path path, {double dash = 4, double gap = 3, Paint? paint}) {
    final p = paint ?? thin();
    for (final m in path.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), p);
        d += dash + gap;
      }
    }
  }

  /// Ok ucu (dolu üçgen) – [to] noktasında, [from]→[to] yönünde.
  void arrow(Canvas canvas, Offset from, Offset to, {Color? c, double size = 7, bool line = true}) {
    final col = c ?? color;
    final ang = math.atan2(to.dy - from.dy, to.dx - from.dx);
    final p1 = to - Offset(math.cos(ang - 0.42), math.sin(ang - 0.42)) * size;
    final p2 = to - Offset(math.cos(ang + 0.42), math.sin(ang + 0.42)) * size;
    if (line) {
      canvas.drawLine(from, to - Offset(math.cos(ang), math.sin(ang)) * (size * 0.6), stroke(col));
    }
    canvas.drawPath(
      Path()
        ..moveTo(to.dx, to.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close(),
      fill(col),
    );
  }

  /// Metin; [at] metnin [anchor] hizasındaki noktasıdır
  /// (center: yatay-dikey ortalı, left: sol-orta, right: sağ-orta,
  /// top: üst-orta, bottom: alt-orta).
  void text(
    Canvas canvas,
    String s,
    Offset at, {
    double size = 9,
    Color? c,
    bool bold = false,
    String anchor = 'center',
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: c ?? color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          height: 1.1,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 600);
    Offset o;
    switch (anchor) {
      case 'left':
        o = Offset(at.dx, at.dy - tp.height / 2);
        break;
      case 'right':
        o = Offset(at.dx - tp.width, at.dy - tp.height / 2);
        break;
      case 'top':
        o = Offset(at.dx - tp.width / 2, at.dy);
        break;
      case 'bottom':
        o = Offset(at.dx - tp.width / 2, at.dy - tp.height);
        break;
      default:
        o = Offset(at.dx - tp.width / 2, at.dy - tp.height / 2);
    }
    tp.paint(canvas, o);
  }

  /// Çokgen yolu.
  static Path poly(List<Offset> pts, {bool close = true}) {
    final p = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      p.lineTo(pts[i].dx, pts[i].dy);
    }
    if (close) p.close();
    return p;
  }

  /// Düzgün çokgen köşeleri.
  static List<Offset> regular(Offset c, double r, int n, [double start = -math.pi / 2]) => [
    for (int i = 0; i < n; i++)
      Offset(c.dx + r * math.cos(start + 2 * math.pi * i / n), c.dy + r * math.sin(start + 2 * math.pi * i / n)),
  ];

  /// Yay (derece cinsinden başlangıç ve süpürme; ekran koordinatı, saat yönü pozitif).
  static Path arc(Offset c, double r, double startDeg, double sweepDeg) => Path()
    ..addArc(Rect.fromCircle(center: c, radius: r), startDeg * math.pi / 180, sweepDeg * math.pi / 180);

  /// Enlem/boylam gibi (x,y) listesini hedef kutuya oturtur.
  static List<Offset> fit(List<List<double>> pts, Rect box, {required double minX, required double maxX, required double minY, required double maxY, bool flipY = true}) {
    final sx = box.width / (maxX - minX);
    final sy = box.height / (maxY - minY);
    return [
      for (final p in pts)
        Offset(
          box.left + (p[0] - minX) * sx,
          flipY ? box.bottom - (p[1] - minY) * sy : box.top + (p[1] - minY) * sy,
        ),
    ];
  }
}

typedef WbArtDraw = void Function(Canvas canvas, WbArtPen pen);

/// Kütüphanedeki tek bir şekil.
class WbArtItem {
  const WbArtItem(this.id, this.name, this.w, this.h, this.draw, {this.tags = ''});

  /// Benzersiz kimlik (ör. `mat_kup`).
  final String id;
  final String name;

  /// Tasarım kutusu boyutu.
  final double w;
  final double h;
  final WbArtDraw draw;

  /// Aramada kullanılacak ek anahtar kelimeler (küçük harf).
  final String tags;
}

/// Ders / konu grubu.
class WbArtCategory {
  const WbArtCategory(this.id, this.name, this.icon, this.color, this.items);
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final List<WbArtItem> items;
}

