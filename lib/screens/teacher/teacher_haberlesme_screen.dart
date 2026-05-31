import 'package:flutter/material.dart';
import 'teacher_announcements_screen.dart';
import 'teacher_social_media_screen.dart';
import 'teacher_messages_screen.dart';

class TeacherHaberlesmeScreen extends StatelessWidget {
  final String institutionId;

  const TeacherHaberlesmeScreen({
    Key? key,
    required this.institutionId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 1100;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Haberleşme',
                    style: TextStyle(
                      fontSize: 28, 
                      fontWeight: FontWeight.w900, 
                      color: Colors.indigo.shade900, 
                      letterSpacing: -0.5
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tüm iletişim kanallarına tek bir yerden ulaşın.',
                    style: TextStyle(
                      fontSize: 15, 
                      color: Colors.blueGrey.shade600, 
                      height: 1.4
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildCommCard(
                    context: context,
                    title: 'Duyurular',
                    description: 'Size ve sınıflarınıza gönderilen duyuruları inceleyin.',
                    icon: Icons.campaign_rounded,
                    color: Colors.orange,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TeacherAnnouncementsScreen(institutionId: institutionId),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildCommCard(
                    context: context,
                    title: 'Sosyal Medya',
                    description: 'Şubelerinizle ilgili güncel paylaşımları ve gelişmeleri takip edin.',
                    icon: Icons.share_rounded,
                    color: Colors.blue,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TeacherSocialMediaScreen(institutionId: institutionId),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildCommCard(
                    context: context,
                    title: 'Mesajlar',
                    description: 'Velileriniz ve diğer personel ile anlık mesajlaşın.',
                    icon: Icons.forum_rounded,
                    color: Colors.green,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TeacherMessagesScreen(institutionId: institutionId),
                      ),
                    ),
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommCard({
    required BuildContext context,
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
                      size: 14,
                      color: Colors.indigo.shade400,
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
