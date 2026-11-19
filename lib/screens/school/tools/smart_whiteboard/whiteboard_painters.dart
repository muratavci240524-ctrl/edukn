import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'whiteboard_models.dart';

Color wbBgColor(WbBackground bg) {
  switch (bg) {
    case WbBackground.black:
      return const Color(0xFF14171C);
    case WbBackground.green:
      return const Color(0xFF1E4D3B);
    default:
      return Colors.white;
  }
}

bool wbIsDark(WbBackground bg) =>
    bg == WbBackground.black || bg == WbBackground.green;

double _adapt(double base, double scale, double minPx) {
  var s = base;
  int guard = 0;
  while (s * scale < minPx && guard < 30) {
    s *= 2;
    guard++;
  }
  return s;
}

/// Kalıcı katman: arka plan + tüm nesneler. Yalnızca sürüm / görünüm değişince çizilir.
class WbCommittedPainter extends CustomPainter {
  WbCommittedPainter({
    required this.objects,
    required this.bg,
    required this.scale,
    required this.offset,
    required this.version,
    this.paperSize,
    this.paperImage,
  });

  final List<WbObject> objects;
  final WbBackground bg;
  final double scale;
  final Offset offset;
  final int version;
  final Size? paperSize;
  final ui.Image? paperImage;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = paperSize != null ? const Color(0xFFCBD5E1) : wbBgColor(bg),
    );
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);
    final visible = Rect.fromLTWH(
      -offset.dx / scale,
      -offset.dy / scale,
      size.width / scale,
      size.height / scale,
    );
    if (paperSize != null) {
      final paper = Offset.zero & paperSize!;
      canvas.drawRect(
        paper.shift(Offset(4 / scale, 6 / scale)),
        Paint()..color = const Color(0x33000000),
      );
      canvas.drawRect(paper, Paint()..color = Colors.white);
      if (paperImage != null) {
        canvas.drawImageRect(
          paperImage!,
          Rect.fromLTWH(
            0,
            0,
            paperImage!.width.toDouble(),
            paperImage!.height.toDouble(),
          ),
          paper,
          Paint()..filterQuality = FilterQuality.medium,
        );
      }
    } else {
      _paintPattern(canvas, visible);
    }
    for (final o in objects) {
      if (o.bounds.overlaps(visible)) o.paint(canvas);
    }
    canvas.restore();
  }

  void _paintPattern(Canvas canvas, Rect v) {
    final dark = wbIsDark(bg);
    final ink = dark ? const Color(0x33FFFFFF) : const Color(0x55607D8B);
    final line = Paint()
      ..color = ink
      ..strokeWidth = 1 / scale
      ..style = PaintingStyle.stroke;

    void vLines(double step, Paint p) {
      for (double x = (v.left / step).floor() * step; x <= v.right; x += step) {
        canvas.drawLine(Offset(x, v.top), Offset(x, v.bottom), p);
      }
    }

    void hLines(double step, Paint p) {
      for (double y = (v.top / step).floor() * step; y <= v.bottom; y += step) {
        canvas.drawLine(Offset(v.left, y), Offset(v.right, y), p);
      }
    }

    switch (bg) {
      case WbBackground.grid:
        final s = _adapt(40, scale, 14);
        vLines(s, line);
        hLines(s, line);
        break;
      case WbBackground.lined:
        final s = _adapt(48, scale, 18);
        hLines(
          s,
          Paint()
            ..color = const Color(0x664F8CD6)
            ..strokeWidth = 1.2 / scale,
        );
        if (v.left < 90 && v.right > 70) {
          canvas.drawLine(
            Offset(80, v.top),
            Offset(80, v.bottom),
            Paint()
              ..color = const Color(0x77E57373)
              ..strokeWidth = 1.6 / scale,
          );
        }
        break;
      case WbBackground.dotted:
        final s = _adapt(40, scale, 14);
        final dot = Paint()..color = ink.withValues(alpha: 0.7);
        for (double x = (v.left / s).floor() * s; x <= v.right; x += s) {
          for (double y = (v.top / s).floor() * s; y <= v.bottom; y += s) {
            canvas.drawCircle(Offset(x, y), 1.8 / scale + 0.6, dot);
          }
        }
        break;
      case WbBackground.graph:
        final minor = _adapt(10, scale, 7);
        final major = _adapt(50, scale, 35);
        final p1 = Paint()
          ..color = ink.withValues(alpha: 0.25)
          ..strokeWidth = 0.6 / scale;
        final p2 = Paint()
          ..color = ink.withValues(alpha: 0.7)
          ..strokeWidth = 1.2 / scale;
        vLines(minor, p1);
        hLines(minor, p1);
        vLines(major, p2);
        hLines(major, p2);
        break;
      case WbBackground.axes:
        final s = _adapt(40, scale, 20);
        vLines(s, line);
        hLines(s, line);
        final axis = Paint()
          ..color = dark ? Colors.white70 : const Color(0xFF263238)
          ..strokeWidth = 2.2 / scale;
        canvas.drawLine(Offset(v.left, 0), Offset(v.right, 0), axis);
        canvas.drawLine(Offset(0, v.top), Offset(0, v.bottom), axis);
        int count = 0;
        final lc = dark ? Colors.white70 : const Color(0xFF455A64);
        final fs = 12 / scale;
        for (
          double x = (v.left / s).floor() * s;
          x <= v.right && count < 80;
          x += s, count++
        ) {
          final n = (x / 40).round();
          if (n == 0) continue;
          final tp = wbTextPainter('$n', fs, lc);
          tp.paint(canvas, Offset(x - tp.width / 2, 4 / scale));
        }
        count = 0;
        for (
          double y = (v.top / s).floor() * s;
          y <= v.bottom && count < 80;
          y += s, count++
        ) {
          final n = -(y / 40).round();
          if (n == 0) continue;
          final tp = wbTextPainter('$n', fs, lc);
          tp.paint(canvas, Offset(-tp.width - 5 / scale, y - tp.height / 2));
        }
        break;
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant WbCommittedPainter old) =>
      old.version != version ||
      old.scale != scale ||
      old.offset != offset ||
      old.bg != bg ||
      !identical(old.paperImage, paperImage) ||
      old.paperSize != paperSize ||
      !identical(old.objects, objects);
}

class WbLaserPoint {
  const WbLaserPoint(this.p, this.age);
  final Offset p;
  final double age; // 0 (yeni) .. 1 (silinmek üzere)
}

/// Canlı katman: çizilmekte olan nesne, seçim çerçevesi, silgi imleci, lazer.
class WbLivePainter extends CustomPainter {
  WbLivePainter({
    required this.preview,
    required this.selection,
    required this.scale,
    required this.offset,
    required this.eraserPos,
    required this.eraserRadius,
    required this.laser,
    required this.darkBg,
    super.repaint,
  });

  final WbObject? preview;
  final Rect? selection;
  final double scale;
  final Offset offset;
  final Offset? eraserPos;
  final double eraserRadius;
  final List<WbLaserPoint> laser;
  final bool darkBg;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);

    preview?.paint(canvas);

    if (selection != null) {
      final r = selection!.inflate(6 / scale);
      final path = Path()..addRect(r);
      canvas.drawPath(
        wbDashPath(path, dash: 8 / scale, gap: 5 / scale),
        Paint()
          ..color = const Color(0xFF2563EB)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8 / scale,
      );
      final h = r.bottomRight;
      canvas.drawCircle(h, 10 / scale, Paint()..color = Colors.white);
      canvas.drawCircle(
        h,
        10 / scale,
        Paint()
          ..color = const Color(0xFF2563EB)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4 / scale,
      );
      canvas.drawCircle(
        h,
        3.5 / scale,
        Paint()..color = const Color(0xFF2563EB),
      );
    }

    if (eraserPos != null) {
      canvas.drawCircle(
        eraserPos!,
        eraserRadius,
        Paint()
          ..color = (darkBg ? Colors.white : Colors.black).withValues(
            alpha: 0.08,
          ),
      );
      canvas.drawCircle(
        eraserPos!,
        eraserRadius,
        Paint()
          ..color = darkBg ? Colors.white70 : Colors.black54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / scale,
      );
    }

    if (laser.isNotEmpty) {
      for (int i = 1; i < laser.length; i++) {
        final a = laser[i - 1], b = laser[i];
        final alpha = (1 - b.age).clamp(0.0, 1.0);
        canvas.drawLine(
          a.p,
          b.p,
          Paint()
            ..color = const Color(0xFFFF1744).withValues(alpha: 0.25 * alpha)
            ..strokeWidth = 18 / scale
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawLine(
          a.p,
          b.p,
          Paint()
            ..color = const Color(0xFFFF1744).withValues(alpha: alpha)
            ..strokeWidth = 6 / scale
            ..strokeCap = StrokeCap.round,
        );
      }
      final last = laser.last;
      if (last.age < 0.6) {
        canvas.drawCircle(
          last.p,
          16 / scale,
          Paint()..color = const Color(0xFFFF1744).withValues(alpha: 0.3),
        );
        canvas.drawCircle(
          last.p,
          8 / scale,
          Paint()..color = const Color(0xFFFF1744),
        );
        canvas.drawCircle(last.p, 3 / scale, Paint()..color = Colors.white);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant WbLivePainter old) => true;
}

double wbClampScale(double s) => math.max(0.15, math.min(8.0, s));
