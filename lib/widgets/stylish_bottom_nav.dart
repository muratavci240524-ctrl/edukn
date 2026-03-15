import 'package:flutter/material.dart';

class StylishBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const StylishBottomNav({
    Key? key,
    required this.currentIndex,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      height: 70, // Reduced height since we removed top gap
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // Background Curve
          CustomPaint(
            size: Size(MediaQuery.of(context).size.width, 70),
            painter: _CurvedPainter(),
          ),

          // Items Row
          SizedBox(
            height: 70,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(child: _buildNavItem(0, Icons.campaign, 'Duyurular')),
                Expanded(child: _buildNavItem(1, Icons.share, 'Sosyal')),
                const SizedBox(width: 48), // Gap for center button
                Expanded(child: _buildNavItem(2, Icons.message, 'Mesajlar')),
                Expanded(child: _buildNavItem(3, Icons.grid_view, 'İşlemler')),
              ],
            ),
          ),

          // Floating Center Button
          Positioned(
            top: -25, // Adjusted slightly to sit nicely in the new curve
            child: GestureDetector(
              onTap: () {
                onTap(4);
              },
              child: Container(
                width:
                    60, // Slightly smaller to fit better if needed, or keep 64
                height: 60,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF1976D2),
                      Color(0xFF2196F3),
                    ], // Blue 700, Blue 500
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.dashboard_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = currentIndex == index;
    // WRAP IN MATERIAL FOR PROPER INK SPLASH VISIBILITY
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onTap(index),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected
                    ? const Color(0xFF1565C0) // Blue 800
                    : Colors.grey.shade400,
                size: 26,
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? const Color(0xFF1565C0) // Blue 800
                        : Colors.grey.shade400,
                    fontSize: 11,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurvedPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path();
    // Start at 0 instead of 20 to remove top gap
    path.moveTo(0, 0);
    path.lineTo(size.width * 0.35, 0);

    // Curve for the button
    path.quadraticBezierTo(
      size.width * 0.40,
      0,
      size.width * 0.40,
      0, // Start of dip
    );
    path.cubicTo(
      size.width * 0.40,
      0,
      size.width * 0.42,
      40, // Dip down (depth 40)
      size.width * 0.5,
      40, // Bottom of dip
    );
    path.cubicTo(
      size.width * 0.58,
      40,
      size.width * 0.60,
      0,
      size.width * 0.60,
      0, // End of dip
    );

    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    // Shadow
    canvas.drawShadow(path, Colors.black.withOpacity(0.1), 4.0, true);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
