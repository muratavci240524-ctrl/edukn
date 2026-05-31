import 'package:flutter/material.dart';

import 'single_exam_results_screen.dart';
import 'combined_exam_results_screen.dart';
import 'reinforcement/reinforcement_dashboard_screen.dart';
import 'agm/screens/agm_dashboard_screen.dart';
import '../guidance/guidance_study_program_screen.dart';
import 'action_plan/assessment_action_plan_list_screen.dart';
import 'camp/screens/camp_dashboard_screen.dart';
import 'parent_report/parent_report_dashboard.dart';

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
                    final isSmallMobile = constraints.maxWidth < 360;
                    return GridView.count(
                      crossAxisCount: crossAxisCount,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 20,
                      mainAxisSpacing: 20,
                      childAspectRatio: constraints.maxWidth > 800
                          ? 0.85
                          : (constraints.maxWidth > 500
                              ? 1.1
                              : (isSmallMobile ? 1.8 : 2.2)),
                      children: [
                        _buildHubCard(
                          context,
                          title: 'Tekil Sınav Raporları',
                          subtitle: 'Tek bir sınavın detaylı analiz ve raporları.',
                          icon: Icons.description_rounded,
                          color: Colors.indigo.shade700,
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
                          color: Colors.teal.shade700,
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
                          color: Colors.amber.shade800,
                          actionLabel: 'Program Oluştur',
                          isMobile: constraints.maxWidth <= 500,
                          onTap: () {
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
                          color: Colors.deepPurple.shade600,
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

                // Responsive Row for Summary and Action Plan
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
                              child: _buildActionPlanCard(context, isCompact: true),
                            ),
                          ],
                        ),
                      );
                    } else {
                      return Column(
                        children: [
                          _buildPerformanceBanner(context),
                          const SizedBox(height: 24),
                          _buildActionPlanCard(context, isCompact: false),
                        ],
                      );
                    }
                  },
                ),

                const SizedBox(height: 24),

                // Full-width Kamp Programı Card
                _buildCampBanner(context),

                const SizedBox(height: 24),

                // Full-width Veli Bilgilendirme Raporu Card
                _buildParentReportBanner(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCampBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade600, Colors.deepOrange.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CampDashboardScreen(
                  institutionId: institutionId,
                  schoolTypeId: schoolTypeId,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                bottom: -20,
                child: Opacity(
                  opacity: 0.1,
                  child: Icon(Icons.campaign_rounded, size: 180, color: Colors.white),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Kamp Programı',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: MediaQuery.of(context).size.width < 360 ? 20 : 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Öğrenci başarı grafiklerine göre özel gruplar ve yoğunlaştırılmış çalışma planları oluşturun.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: MediaQuery.of(context).size.width < 360 ? 12 : 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        'Kamp Planla',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
    final double cardPadding = isMobile ? 16 : 24;
    final double iconPadding = isMobile ? 8 : 12;
    final double iconSize = isMobile ? 22 : 28;
    final double spacing1 = isMobile ? 8 : 20;
    final double spacing2 = isMobile ? 4 : 8;
    final double spacing3 = isMobile ? 8 : 24;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                // Subtle Top Color Accent
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: Container(height: 4, color: color),
                ),
                Padding(
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
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            actionLabel,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded, size: 16, color: color),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
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
          borderRadius: BorderRadius.circular(24),
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
                    Text(
                      'Haftalık Performans Özeti',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: MediaQuery.of(context).size.width < 360 ? 20 : 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Kurum genelindeki başarı oranlarını ve gelişim grafiklerini anlık olarak takip edin.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: MediaQuery.of(context).size.width < 360 ? 12 : 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        'Görüntüle',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionPlanCard(BuildContext context, {required bool isCompact}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F9),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AssessmentActionPlanListScreen(
                  institutionId: institutionId,
                  schoolTypeId: schoolTypeId,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(24),
          child: Padding(
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
                  child: Icon(Icons.assignment_turned_in_rounded, color: Colors.deepOrange.shade400, size: 28),
                ),
                const SizedBox(height: 20),
                Text(
                  'Eylem Planları',
                  textAlign: isCompact ? TextAlign.center : TextAlign.start,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sınav sonuçlarına göre şube ve öğrenci eylem planları hazırlayın.',
                  textAlign: isCompact ? TextAlign.center : TextAlign.start,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Görüntüle',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildParentReportBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade900, Colors.purple.shade900],
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ParentReportDashboard(
                  institutionId: institutionId,
                  schoolTypeId: schoolTypeId,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                bottom: -20,
                child: Opacity(
                  opacity: 0.1,
                  child: Icon(Icons.family_restroom_rounded, size: 180, color: Colors.white),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.family_restroom_rounded, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Veli Bilgilendirme Raporları',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: MediaQuery.of(context).size.width < 360 ? 20 : 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Öğrencinin haftalık sınav sonuçlarını, AGM ve Kamp ders katılımlarını tek bir sayfada şık ve kurumsal PDF mektubu olarak derleyin.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: MediaQuery.of(context).size.width < 360 ? 12 : 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        'Rapor Hazırla',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

