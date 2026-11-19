import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// PDF hazırlanırken tam ekran gösterilen animasyonlu bekleme katmanı.
/// Dönen halka, yukarı doğru dizilen sayfalar, nabız atan PDF ikonu ve değişen durum mesajları içerir.
class PdfGeneratingOverlay extends StatefulWidget {
  final String title;
  final int questionCount;

  const PdfGeneratingOverlay({
    super.key,
    this.title = 'PDF Hazırlanıyor',
    this.questionCount = 0,
  });

  @override
  State<PdfGeneratingOverlay> createState() => _PdfGeneratingOverlayState();
}

class _PdfGeneratingOverlayState extends State<PdfGeneratingOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _pulse;
  late final AnimationController _pages;
  Timer? _msgTimer;
  int _msgIndex = 0;

  List<String> get _messages => [
        'Sorular havuzdan getiriliyor...',
        'Görseller indiriliyor ve beyazlatılıyor...',
        if (widget.questionCount > 0)
          '${widget.questionCount} soru sayfalara yerleştiriliyor...'
        else
          'Sorular sayfalara yerleştiriliyor...',
        '1 ve 2 sütunlu sorular akıllıca diziliyor...',
        'Antet, alt bilgi ve kazanımlar ekleniyor...',
        'Cevap anahtarı hazırlanıyor...',
        'Son dokunuşlar yapılıyor...',
      ];

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
    _pages = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat();
    _msgTimer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
      if (mounted) setState(() => _msgIndex = (_msgIndex + 1) % _messages.length);
    });
  }

  @override
  void dispose() {
    _msgTimer?.cancel();
    _spin.dispose();
    _pulse.dispose();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: Container(
          color: const Color(0xFF0F172A).withValues(alpha: 0.55),
          alignment: Alignment.center,
          child: Container(
            width: 380,
            padding: const EdgeInsets.fromLTRB(28, 30, 28, 26),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.indigo.withValues(alpha: 0.35),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 170,
                  height: 170,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Dönen gradyan halka
                      AnimatedBuilder(
                        animation: _spin,
                        builder: (_, __) => Transform.rotate(
                          angle: _spin.value * 2 * math.pi,
                          child: CustomPaint(
                            size: const Size(170, 170),
                            painter: _RingPainter(),
                          ),
                        ),
                      ),
                      // Yukarı süzülen sayfalar
                      AnimatedBuilder(
                        animation: _pages,
                        builder: (_, __) => Stack(
                          alignment: Alignment.center,
                          children: List.generate(3, (i) {
                            final t = (_pages.value + i / 3) % 1.0;
                            final dy = 26 - t * 52;
                            final opacity = math.sin(t * math.pi).clamp(0.0, 1.0);
                            final dx = (i - 1) * 30.0;
                            return Transform.translate(
                              offset: Offset(dx, dy),
                              child: Opacity(
                                opacity: opacity * 0.85,
                                child: Transform.rotate(
                                  angle: (i - 1) * 0.18,
                                  child: const _MiniPage(),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      // Nabız atan PDF rozeti
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, child) => Transform.scale(
                          scale: 0.92 + _pulse.value * 0.12,
                          child: child,
                        ),
                        child: Container(
                          width: 66,
                          height: 66,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.indigo.withValues(alpha: 0.45),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.picture_as_pdf_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E1B4B),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 22,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.4),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: Text(
                      _messages[_msgIndex % _messages.length],
                      key: ValueKey(_msgIndex),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.indigo.shade400,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    backgroundColor: Colors.indigo.shade50,
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF6366F1)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Lütfen sayfayı kapatmayın, PDF birazdan inecek.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniPage extends StatelessWidget {
  const _MiniPage();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 44,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.indigo.shade100),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final w in [1.0, 0.7, 0.9, 0.5])
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: FractionallySizedBox(
                widthFactor: w,
                child: Container(height: 3, color: Colors.indigo.shade100),
              ),
            ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [Color(0x004F46E5), Color(0xFF6366F1), Color(0xFFA855F7), Color(0xFF22D3EE)],
        stops: [0.0, 0.45, 0.8, 1.0],
      ).createShader(rect);
    canvas.drawArc(rect.deflate(6), 0, math.pi * 1.7, false, paint);

    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFE0E7FF);
    canvas.drawCircle(size.center(Offset.zero), size.width / 2 - 20, bg);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

