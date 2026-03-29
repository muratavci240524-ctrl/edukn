import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// LOGO GÖRÜNÜM TİPLERİ (4 İhtiyacını Karşılar)
enum EduKnLogoType {
  full, // 1. İkon + Yazı + Slogan
  noSlogan, // 2. İkon + Yazı
  iconOnly, // 3. Sadece İkon
}

/// eduKN SABİT LOGO WIDGET'I
class EduKnLogo extends StatelessWidget {
  final EduKnLogoType type;
  final double iconSize;

  const EduKnLogo({
    Key? key,
    this.type = EduKnLogoType.full,
    this.iconSize = 60.0, // İkonun varsayılan yüksekliği/genişliği
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 3. İhtiyacın: Sadece İkon
    if (type == EduKnLogoType.iconOnly) {
      return CustomPaint(
        size: Size(iconSize * 1.2, iconSize),
        painter: _SprintIconPainter(step: 3), // Animasyonsuz, hepsi parlak
      );
    }

    // 1 ve 2. İhtiyacın: İkon + Yazı (Sloganlı veya Slogansız)
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // İkon Kısmı
        CustomPaint(
          size: Size(iconSize * 1.2, iconSize),
          painter: _SprintIconPainter(step: 3),
        ),
        SizedBox(width: iconSize * 0.2), // İkon ile yazı arası boşluk
        // Yazı Kısmı
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // eduKN Ana Yazısı
            RichText(
              text: TextSpan(
                style: GoogleFonts.roboto(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic, // Görseldeki o harika eğim
                  letterSpacing: -2.0, // Harfleri sıkıştırdık
                  height: 0.9,
                ),
                children: const [
                  TextSpan(
                    text: 'edu',
                    style: TextStyle(color: Colors.white),
                  ),
                  TextSpan(
                    text: 'KN',
                    style: TextStyle(color: Color(0xFF60A5FA)),
                  ), // Açık Mavi
                ],
              ),
            ),
            // Slogan (Eğer type full ise göster)
            if (type == EduKnLogoType.full)
              Padding(
                padding: const EdgeInsets.only(top: 4.0, left: 4.0),
                child: Text(
                  'DAHA İYİ PLANLA, DAHA HIZLI İLERLE',
                  style: GoogleFonts.roboto(
                    color: const Color(0x99BFDBFE), // Yarı şeffaf açık mavi-gri
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.5,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// eduKN YÜKLEME (LOADING) ANİMASYONU WIDGET'I
/// 4. İhtiyacın: Yükleme ekranları için hareketli ikon
class EduKnLoader extends StatefulWidget {
  final double size;
  const EduKnLoader({Key? key, this.size = 80.0}) : super(key: key);

  @override
  State<EduKnLoader> createState() => _EduKnLoaderState();
}

class _EduKnLoaderState extends State<EduKnLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 1.5 saniyelik sürekli dönen bir animasyon (GIF hissiyatı)
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Zamanı 4 aşamaya böl (0, 1, 2 = parçalar yanar, 3 = hepsi söner başa döner)
        int step = (_controller.value * 4).floor();
        return CustomPaint(
          size: Size(widget.size * 1.2, widget.size),
          painter: _SprintIconPainter(step: step),
        );
      },
    );
  }
}

/// İKONU GPU ÜZERİNDE MATEMATİKSEL OLARAK ÇİZEN CUSTOM PAINTER
class _SprintIconPainter extends CustomPainter {
  final int step;

  _SprintIconPainter({required this.step});

  @override
  void paint(Canvas canvas, Size size) {
    // Çizimi orijinal 120x100 boyutlarına göre ölçeklendiriyoruz ki her ekrana uysun
    final scaleX = size.width / 120;
    final scaleY = size.height / 100;
    canvas.scale(scaleX, scaleY);

    // İtalik yatıklığı (-15 derece) Flutter matrisi ile veriyoruz!
    canvas.translate(25, 10);
    canvas.transform(
      Float64List.fromList([
        1.0, 0.0, 0.0, 0.0,
        -0.2679, 1.0, 0.0, 0.0, // tan(-15 derece) = -0.2679
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
      ]),
    );

    // 1. Parça (En arka planlama bloğu)
    final path1 = Path()
      ..moveTo(0, 15)
      ..lineTo(35, 15)
      ..lineTo(55, 40)
      ..lineTo(35, 65)
      ..lineTo(0, 65)
      ..lineTo(20, 40)
      ..close();
    final paint1 = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(path1.getBounds())
      ..color = const Color(
        0xFF1E3A8A,
      ).withOpacity((step == 0 || step == 3) ? 0.9 : 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path1, paint1);

    // 2. Parça (Ortadaki hızlanma bloğu)
    final path2 = Path()
      ..moveTo(25, 15)
      ..lineTo(60, 15)
      ..lineTo(80, 40)
      ..lineTo(60, 65)
      ..lineTo(25, 65)
      ..lineTo(45, 40)
      ..close();
    final paint2 = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF2563EB), Color(0xFF60A5FA)],
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
      ).createShader(path2.getBounds())
      ..color = const Color(
        0xFF2563EB,
      ).withOpacity((step == 1 || step == 3) ? 0.9 : 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path2, paint2);

    // 3. Parça (Zirve hız oku)
    final path3 = Path()
      ..moveTo(50, 15)
      ..lineTo(85, 15)
      ..lineTo(105, 40)
      ..lineTo(85, 65)
      ..lineTo(50, 65)
      ..lineTo(70, 40)
      ..close();
    final paint3 = Paint()
      ..color = const Color(
        0xFF60A5FA,
      ).withOpacity((step == 2 || step == 3) ? 1.0 : 0.2)
      ..style = PaintingStyle.fill;

    // Yanan parçada veya statik halinde parlama efekti (Glow/Neon)
    if (step == 2 || step == 3) {
      paint3.maskFilter = const MaskFilter.blur(BlurStyle.solid, 4.0);
    }
    canvas.drawPath(path3, paint3);
  }

  @override
  bool shouldRepaint(covariant _SprintIconPainter oldDelegate) {
    return oldDelegate.step !=
        step; // Sadece adım değiştiğinde ekranı yor (Mükemmel performans)
  }
}
