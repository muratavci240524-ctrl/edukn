import 'package:flutter/material.dart';

import 'single_exam_results_screen.dart';
import 'combined_exam_results_screen.dart';
import 'reinforcement/reinforcement_dashboard_screen.dart';
import 'agm/screens/agm_dashboard_screen.dart';
import '../guidance/guidance_study_program_screen.dart';

class AssessmentReportsScreen extends StatelessWidget {
  final String institutionId;
  final String schoolTypeId;
  final bool isTeacher;

  const AssessmentReportsScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    this.isTeacher = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Raporlar',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Grid of Main Cards
                LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = constraints.maxWidth > 800 ? 4 : (constraints.maxWidth > 500 ? 2 : 1);
                    return GridView.count(
                      crossAxisCount: crossAxisCount,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 20,
                      mainAxisSpacing: 20,
                      childAspectRatio: constraints.maxWidth > 800 ? 0.85 : (constraints.maxWidth > 500 ? 1.1 : 2.2),
                      children: [
                        _buildHubCard(
                          context,
                          title: 'Tekil Sınav Raporları',
                          subtitle: 'Tek bir sınavın detaylı analiz ve raporları.',
                          icon: Icons.description_rounded,
                          color: Colors.indigo.shade400,
                          actionLabel: 'Görüntüle',
                          isMobile: constraints.maxWidth <= 500,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SingleExamResultsScreen(
                                  institutionId: institutionId,
                                  schoolTypeId: schoolTypeId,
                                ),
                              ),
                            );
                          },
                        ),
                        _buildHubCard(
                          context,
                          title: 'Birleştirilmiş Sınav Raporları',
                          subtitle: 'Birden fazla sınavın karşılaştırmalı raporları.',
                          icon: Icons.analytics_rounded,
                          color: Colors.blue.shade600,
                          actionLabel: 'Analiz Et',
                          isMobile: constraints.maxWidth <= 500,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CombinedExamResultsScreen(
                                  institutionId: institutionId,
                                  schoolTypeId: schoolTypeId,
                                ),
                              ),
                            );
                          },
                        ),
                        _buildHubCard(
                          context,
                          title: 'Güçlendirme Programları',
                          subtitle: 'Öğrenci eksiklerine göre çalışma programları.',
                          icon: Icons.trending_up_rounded,
                          color: Colors.indigo.shade400,
                          actionLabel: 'Program Oluştur',
                          isMobile: constraints.maxWidth <= 500,
                          onTap: () {
                            // Redirect to GuidanceStudyProgramScreen as requested
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => GuidanceStudyProgramScreen(
                                  institutionId: institutionId,
                                  schoolTypeId: schoolTypeId,
                                ),
                              ),
                            );
                          },
                        ),
                        _buildHubCard(
                          context,
                          title: 'AGM – Akademik Güçlendirme',
                          subtitle: 'Otomatik etüt grubu yerleştirme sistemi.',
                          icon: Icons.auto_awesome_rounded,
                          color: Colors.indigo.shade400,
                          actionLabel: 'Yönet',
                          isMobile: constraints.maxWidth <= 500,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AgmDashboardScreen(
                                  institutionId: institutionId,
                                  schoolTypeId: schoolTypeId,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 32),

                // Responsive Row for Summary and Custom Report
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 850) {
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 2,
                              child: _buildPerformanceBanner(context),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              flex: 1,
                              child: _buildCustomReportCard(context, isCompact: true),
                            ),
                          ],
                        ),
                      );
                    } else {
                      return Column(
                        children: [
                          _buildPerformanceBanner(context),
                          const SizedBox(height: 24),
                          _buildCustomReportCard(context, isCompact: false),
                        ],
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHubCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String actionLabel,
    required VoidCallback onTap,
    bool isMobile = false,
  }) {
    // Responsive sizes
    final double cardPadding = isMobile ? 16 : 24;
    final double iconPadding = isMobile ? 8 : 12;
    final double iconSize = isMobile ? 22 : 28;
    final double spacing1 = isMobile ? 8 : 20; // Icon to Title
    final double spacing2 = isMobile ? 4 : 8; // Title to Subtitle
    final double spacing3 = isMobile ? 8 : 24; // Subtitle to Button

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: EdgeInsets.all(cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(iconPadding),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
            ),
            child: Icon(icon, color: color, size: iconSize),
          ),
          SizedBox(height: spacing1),
          Text(
            title,
            style: TextStyle(
              fontSize: isMobile ? 16 : 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
              height: 1.2,
            ),
            maxLines: isMobile ? 1 : 2,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: spacing2),
          Expanded(
            child: Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
                height: 1.4,
              ),
              maxLines: isMobile ? 2 : 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(height: spacing3),
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  actionLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.indigo),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade600, Colors.deepPurple.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            bottom: -20,
            child: Opacity(
              opacity: 0.1,
              child: Icon(Icons.auto_graph_rounded, size: 180, color: Colors.white),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Haftalık Performans Özeti',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Kurum genelindeki başarı oranlarını ve gelişim grafiklerini\nanlık olarak takip edin.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    // Redirect to ReinforcementDashboardScreen as requested
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ReinforcementDashboardScreen(
                          institutionId: institutionId,
                          schoolTypeId: schoolTypeId,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.indigo.shade900,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Görüntüle',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12), // Some space at bottom
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomReportCard(BuildContext context, {required bool isCompact}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F9),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: isCompact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Icon(Icons.insert_chart_outlined_rounded, color: Colors.blue.shade600, size: 28),
          ),
          const SizedBox(height: 20),
          Text(
            'Özel Rapor Oluştur',
            textAlign: isCompact ? TextAlign.center : TextAlign.start,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Kendi kriterlerinize göre özelleştirilmiş analizler hazırlayın.',
            textAlign: isCompact ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Özel Rapor Oluşturma yakında sizlerle!')),
              );
            },
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Görüntüle',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
