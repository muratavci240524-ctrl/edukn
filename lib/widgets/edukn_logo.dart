
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'web_image_renderer.dart';

/// LOGO GÖRÜNÜM TİPLERİ
enum EduKnLogoType { 
  full,       // İkon + Yazı + Slogan
  noSlogan,   // İkon + Yazı
  iconOnly,   // Sadece İkon
  textOnly    // Sadece Yazı
}

/// eduKN SABİT LOGO WIDGET'I
class EduKnLogo extends StatelessWidget {
  final EduKnLogoType type;
  final double iconSize;
  final Color? textColor;

  const EduKnLogo({
    Key? key,
    this.type = EduKnLogoType.full,
    this.iconSize = 60.0,
    this.textColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final effectiveTextColor = textColor ?? const Color(0xFF1E293B); // Koyu lacivert/siyah varsayılan

    // 🌐 WEB İÇİN KESİN ÇÖZÜM: Yüksek çözünürlüklü PNG resim kullanarak 
    // CanvasKit'in masaüstü bilgisayarlarda yaptığı o "tırtıklanma" hatasını %100 atlıyoruz.
    if (kIsWeb) {
      if (type == EduKnLogoType.iconOnly) {
        return buildWebImage(
          'assets/images/google_auth_logo_light.png',
          width: iconSize * 1.2,
          height: iconSize,
          fit: BoxFit.contain,
        );
      } else if (type == EduKnLogoType.textOnly) {
        return _buildTextOnlyLogo(effectiveTextColor);
      } else {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            buildWebImage(
              'assets/images/google_auth_full_logo_light.png',
              width: iconSize * 3.5,
              height: iconSize * 0.9,
              fit: BoxFit.contain,
            ),
            if (type == EduKnLogoType.full)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  'DAHA İYİ PLANLA, DAHA HIZLI İLERLE',
                  style: GoogleFonts.roboto(
                    color: const Color(0x99BFDBFE),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.5,
                  ),
                ),
              ),
          ],
        );
      }
    }

    // 📱 MOBİL CİHAZLAR İÇİN: Kendi native kodumuz (Performanslı Canvas çizimi)
    if (type == EduKnLogoType.iconOnly) {
      return CustomPaint(
        size: Size(iconSize * 1.2, iconSize),
        painter: _SprintIconPainter(step: 3),
      );
    } else if (type == EduKnLogoType.textOnly) {
      return _buildTextOnlyLogo(effectiveTextColor);
    }

    // İkon + Yazı (Sloganlı veya Slogansız)
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
            _buildTextOnlyLogo(effectiveTextColor),
            // Slogan (Eğer type full ise göster)
            if (type == EduKnLogoType.full)
              Padding(
                padding: const EdgeInsets.only(top: 4.0, left: 4.0),
                child: Text(
                  'DAHA İYİ PLANLA, DAHA HIZLI İLERLE',
                  style: GoogleFonts.roboto(
                    color: const Color(0x99BFDBFE),
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

  Widget _buildTextOnlyLogo(Color color) {
    // Yazı boyutunu ikon boyutuna göre orantılıyoruz
    final double fontSize = iconSize * 0.8;
    return RichText(
      text: TextSpan(
        style: GoogleFonts.roboto(
          fontSize: fontSize, 
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic, // Görseldeki o harika eğim
          letterSpacing: -1.0, // Harfleri hafif sıkıştırdık
          height: 0.9,
        ),
        children: [
          TextSpan(text: 'edu', style: TextStyle(color: color)),
          const TextSpan(
            text: 'KN', 
            style: TextStyle(
              color: Color(0xFF60A5FA),
              shadows: [
                Shadow(color: Color(0xFF60A5FA), blurRadius: 0.5)
              ],
            ),
          ),
        ],
      ),
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

class _EduKnLoaderState extends State<EduKnLoader> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 1.5 saniyelik sürekli dönen bir animasyon (GIF hissiyatı)
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
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
/// NOT: canvas.scale() veya canvas.transform() KULLANILMAZ — web DPR uyumluluğu için
/// tüm koordinatlar dinamik olarak boyutla çarpılır, böylece tarayıcı 
/// piksel seviyesinde (native resolution) pürüzsüz çizim yapar.
class _SprintIconPainter extends CustomPainter {
  final int step;
  _SprintIconPainter({required this.step});

  @override
  void paint(Canvas canvas, Size size) {
    // 120x100 referans koordinatına göre ölçek çarpanları
    final double sx = size.width / 120.0;
    final double sy = size.height / 100.0;

    // Opaklık değerleri (adıma göre)
    final op1 = (step == 0 || step == 3) ? 1.0 : 0.22;
    final op2 = (step == 1 || step == 3) ? 1.0 : 0.22;
    final op3 = (step == 2 || step == 3) ? 1.0 : 0.22;

    // ─── KOORDİNATLAR (Ölçeklenmiş) ───────────────────────────────────────

    // 1. Parça (En arka — koyu mavi)
    final path1 = Path()
      ..moveTo(21.0 * sx, 25.0 * sy)
      ..lineTo(56.0 * sx, 25.0 * sy)
      ..lineTo(69.3 * sx, 50.0 * sy)
      ..lineTo(42.6 * sx, 75.0 * sy)
      ..lineTo( 7.6 * sx, 75.0 * sy)
      ..lineTo(34.3 * sx, 50.0 * sy)
      ..close();

    // 2. Parça (Orta — orta mavi)
    final path2 = Path()
      ..moveTo(46.0 * sx, 25.0 * sy)
      ..lineTo(81.0 * sx, 25.0 * sy)
      ..lineTo(94.3 * sx, 50.0 * sy)
      ..lineTo(67.6 * sx, 75.0 * sy)
      ..lineTo(32.6 * sx, 75.0 * sy)
      ..lineTo(59.3 * sx, 50.0 * sy)
      ..close();

    // 3. Parça (Ön — açık mavi)
    final path3 = Path()
      ..moveTo(71.0 * sx, 25.0 * sy)
      ..lineTo(106.0 * sx, 25.0 * sy)
      ..lineTo(119.3 * sx, 50.0 * sy)
      ..lineTo( 92.6 * sx, 75.0 * sy)
      ..lineTo( 57.6 * sx, 75.0 * sy)
      ..lineTo( 84.3 * sx, 50.0 * sy)
      ..close();

    // ─── ÇİZİM ────────────────────────────────────────────────────────────

    // Anti-Aliasing Hack: Tarayıcı MSAA desteklemiyorsa kenarları yumuşatmak için sub-pixel blur
    final edgeSoftener = MaskFilter.blur(BlurStyle.normal, 0.5 * sx);

    // 1. Parça
    final shader1 = LinearGradient(
      colors: [
        Color(0xFF1E3A8A).withOpacity(op1),
        Color(0xFF2563EB).withOpacity(op1),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(Rect.fromLTWH(0 * sx, 20 * sy, 75 * sx, 60 * sy));

    canvas.drawPath(
      path1,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.fill
        ..maskFilter = edgeSoftener // Tırtıklanmayı yumuşatır
        ..shader = shader1,
    );
    // Anti-aliasing yumuşatma hilesi
    canvas.drawPath(
      path1,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..shader = shader1,
    );

    // 2. Parça
    final shader2 = LinearGradient(
      colors: [
        Color(0xFF2563EB).withOpacity(op2),
        Color(0xFF60A5FA).withOpacity(op2),
      ],
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
    ).createShader(Rect.fromLTWH(25 * sx, 20 * sy, 75 * sx, 60 * sy));

    canvas.drawPath(
      path2,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.fill
        ..maskFilter = edgeSoftener
        ..shader = shader2,
    );
    // Anti-aliasing yumuşatma hilesi
    canvas.drawPath(
      path2,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..shader = shader2,
    );

    // 3. Parça (parlama efekti animasyondayken)
    final color3 = Color(0xFF60A5FA).withOpacity(op3);
    final paint3Fill = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill
      ..color = color3;
      
    if (step == 2 || step == 3) {
      // Glow (parlama) efekti için maske
      paint3Fill.maskFilter = MaskFilter.blur(BlurStyle.solid, 3.0 * sx);
    } else {
      paint3Fill.maskFilter = edgeSoftener;
    }
    
    canvas.drawPath(path3, paint3Fill);
    
    // Anti-aliasing yumuşatma hilesi
    final paint3Stroke = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = color3;
    canvas.drawPath(path3, paint3Stroke);
  }

  @override
  bool shouldRepaint(covariant _SprintIconPainter oldDelegate) {
    return oldDelegate.step != step;
  }
}


