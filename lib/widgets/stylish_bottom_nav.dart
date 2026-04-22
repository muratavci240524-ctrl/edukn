import 'package:flutter/material.dart';

class StylishBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final Map<int, int>? badgeCounts;

  const StylishBottomNav({
    Key? key,
    required this.currentIndex,
    required this.onTap,
    this.badgeCounts,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      height: 95, // Kartların bittiği yer (90.0) + biraz shadow payı
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // Background Cards with Concave Curve
          CustomPaint(
            size: Size(MediaQuery.of(context).size.width, 95),
            painter: _CurvedPainter(),
          ),

          // Left Item (Haberleşme)
          Positioned(
            left: 16,
            right: MediaQuery.of(context).size.width / 2 + 6,
            top: 25, // matches cardTop in painter
            bottom: 5, // matches cardBottom (95 - 90 = 5)
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => onTap(0),
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 38), // Right padding to avoid the cutout
                  child: _buildFeatureContent(
                    title: 'Haberleşme',
                    subtitle: 'İletişim merkezi',
                    icon: Icons.campaign_rounded,
                    color: Colors.indigo,
                    isSelected: currentIndex == 0,
                  ),
                ),
              ),
            ),
          ),

          // Right Item (İşlemler)
          Positioned(
            left: MediaQuery.of(context).size.width / 2 + 6,
            right: 16,
            top: 25,
            bottom: 5,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => onTap(2),
                child: Padding(
                  padding: const EdgeInsets.only(left: 38, right: 12), // Left padding to avoid the cutout
                  child: _buildFeatureContent(
                    title: 'İşlemler',
                    subtitle: 'Notlarım ve diğerleri',
                    icon: Icons.edit_note_rounded, // matches "Notlarım" icon
                    color: Colors.purple,
                    isSelected: currentIndex == 2,
                  ),
                ),
              ),
            ),
          ),

          // Floating Center Button (Dashboard)
          Positioned(
            top: 0, // So the center of a 60x60 button is exactly at y=30, matching 'cy' inside painter
            child: GestureDetector(
              onTap: () => onTap(1),
              child: Container(
                width: 60,
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

  Widget _buildFeatureContent({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isSelected,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    )
                  ]
                : null,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                    color: color.withOpacity(0.9),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: color.withOpacity(0.6),
                  height: 1.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CurvedPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = 30.0; // Center of the floating button
    final cR = 38.0; // Radius of the concave cutout (slightly larger than button radius 30 for padding)

    final cardTop = 25.0; // Top of the background cards
    final cardBottom = 90.0; // Bottom of the background cards (65px height)

    // Left card shape
    Path leftRect = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTRB(16, cardTop, cx - 6, cardBottom), // Leaves a 6px gap to center
        const Radius.circular(20),
      ));
    Path cutout = Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: cR));
    Path leftPath = Path.combine(PathOperation.difference, leftRect, cutout);

    // Right card shape
    Path rightRect = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTRB(cx + 6, cardTop, size.width - 16, cardBottom), // Starts 6px past center
        const Radius.circular(20),
      ));
    Path rightPath = Path.combine(PathOperation.difference, rightRect, cutout);

    // Provide visual styling matched identically to _buildFeatureCards from Dashboard V2
    // Left card (Indigo)
    canvas.drawPath(
      leftPath,
      Paint()
        ..color = Colors.indigo.withOpacity(0.05)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      leftPath,
      Paint()
        ..color = Colors.indigo.withOpacity(0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Right card (Purple)
    canvas.drawPath(
      rightPath,
      Paint()
        ..color = Colors.purple.withOpacity(0.05)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      rightPath,
      Paint()
        ..color = Colors.purple.withOpacity(0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
