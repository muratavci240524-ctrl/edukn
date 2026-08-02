import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../screens/school/school_types/school_type_announcements_screen.dart';
import '../screens/school/school_types/school_type_social_media_screen.dart';
import '../screens/school/school_types/chat/chat_screen.dart';
import '../screens/announcements/announcements_screen.dart';
import '../services/user_permission_service.dart';

class HaberlesmeHubWidget extends StatelessWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final Map<String, dynamic>? userData;
  final bool isTeacher;

  const HaberlesmeHubWidget({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.userData,
    this.isTeacher = false,
  }) : super(key: key);

  bool _hasSubModuleAccess(String module, String subModule) {
    return UserPermissionService.hasSubModuleAccess(module, subModule, userData);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Centered Header
                Padding(
                  padding: const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Haberleşme',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Colors.indigo.shade900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isTeacher
                              ? 'Öğretmenlere özel duyurular ve mesajlaşma merkezi.'
                              : (schoolTypeId.isEmpty
                                  ? 'Tüm kurum iletişim kanallarına tek bir yerden ulaşın.'
                                  : 'Okulunuzdaki iletişim kanallarına tek bir yerden ulaşın.'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.blueGrey.shade600,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Action Cards list
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      // 1. Duyurular
                      if (_hasSubModuleAccess('haberlesme', 'genel_duyurular')) ...[
                        _buildCommCard(
                          title: 'Duyurular',
                          description: schoolTypeId.isEmpty
                              ? 'Tüm okul türlerinin duyurularını görüntüleyin ve yönetin.'
                              : 'Okul ve kurum içi güncel duyuruları takip edin.',
                          icon: Icons.campaign_rounded,
                          color: Colors.orange,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SchoolTypeAnnouncementsScreen(
                                  schoolTypeId: schoolTypeId,
                                  schoolTypeName: schoolTypeName.isEmpty ? 'Tüm Okul Türleri' : schoolTypeName,
                                  institutionId: institutionId,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                      ],

                      // 2. Sosyal Medya
                      if (_hasSubModuleAccess('haberlesme', 'sosyal_medya')) ...[
                        _buildCommCard(
                          title: 'Sosyal Medya',
                          description: schoolTypeId.isEmpty
                              ? 'Okulun global sosyal medya paylaşımlarını inceleyin.'
                              : 'Okulun sosyal medya paylaşımlarını inceleyin.',
                          icon: Icons.share_rounded,
                          color: Colors.blue,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SchoolTypeSocialMediaScreen(
                                  schoolTypeId: schoolTypeId,
                                  schoolTypeName: schoolTypeName.isEmpty ? 'Tüm Okul Türleri' : schoolTypeName,
                                  institutionId: institutionId,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                      ],

                      // 3. Mesajlar
                      if (_hasSubModuleAccess('haberlesme', 'mesajlar')) ...[
                        _buildCommCard(
                          title: 'Mesajlar',
                          description: schoolTypeId.isEmpty
                              ? 'Tüm kullanıcılara ve okul türlerine mesajlaşın.'
                              : 'Öğrenciler, veliler ve personelle mesajlaşın.',
                          icon: Icons.forum_rounded,
                          color: Colors.green,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  schoolTypeId: schoolTypeId,
                                  schoolTypeName: schoolTypeName.isEmpty ? 'Tüm Okul Türleri' : schoolTypeName,
                                  institutionId: institutionId,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 100),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
  }

  Widget _buildCommCard({
    required String title,
    required String description,
    required IconData icon,
    required MaterialColor color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.shade500.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: color.shade50,
            highlightColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color.shade400, color.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(icon, size: 32, color: Colors.white),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.indigo.shade900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blueGrey.shade600,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: Colors.indigo.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DoodlePainter extends CustomPainter {
  const DoodlePainter();
  @override
  void paint(Canvas canvas, Size size) {
    const iconSize = 40.0;
    const spacing = 120.0;
    final icons = [
      Icons.school,
      Icons.book,
      Icons.edit,
      Icons.science,
      Icons.calculate,
      Icons.public,
      Icons.history_edu,
      Icons.psychology,
      Icons.menu_book,
      Icons.biotech,
      Icons.brush,
      Icons.music_note
    ];
    final random = math.Random(42);
    for (double x = 0; x < size.width + spacing; x += spacing) {
      for (double y = 0; y < size.height + spacing; y += spacing) {
        final iconData = icons[random.nextInt(icons.length)];
        final jitterX = random.nextDouble() * 40 - 20;
        final jitterY = random.nextDouble() * 40 - 20;
        final rotation = random.nextDouble() * 0.5 - 0.25;
        final textPainter = TextPainter(
            textDirection: TextDirection.ltr,
            text: TextSpan(
                text: String.fromCharCode(iconData.codePoint),
                style: TextStyle(
                    fontSize: iconSize,
                    fontFamily: iconData.fontFamily,
                    package: iconData.fontPackage,
                    color: Colors.indigo
                        .withOpacity(0.02 + random.nextDouble() * 0.03))));
        textPainter.layout();
        canvas.save();
        canvas.translate(x + jitterX, y + jitterY);
        canvas.rotate(rotation);
        textPainter.paint(
            canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
