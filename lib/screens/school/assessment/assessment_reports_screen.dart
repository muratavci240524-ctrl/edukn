import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';

import 'single_exam_results_screen.dart';
import 'combined_exam_results_screen.dart';
import 'performance/performance_summary_screen.dart';
import 'agm/screens/agm_dashboard_screen.dart';
import 'odak64/screens/odak64_dashboard_screen.dart';
import '../guidance/guidance_study_program_screen.dart';
import 'action_plan/assessment_action_plan_list_screen.dart';
import 'parent_report/parent_report_dashboard.dart';
import '../../../services/user_permission_service.dart';
import '../tools/academic_tracking/academic_tracking_models.dart';
import '../tools/academic_tracking/champions_league_screen.dart';

class AssessmentReportsScreen extends StatelessWidget {
  final String institutionId;
  final String schoolTypeId;
  final String? schoolTypeName;
  final bool isTeacher;

  const AssessmentReportsScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    this.schoolTypeName,
    this.isTeacher = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final canViewTekil =
        !isTeacher ||
        UserPermissionService.hasTeacherModuleAccess(
          'egitim_islemleri',
          subModuleKey: 'sinav_raporlari',
        ) ||
        UserPermissionService.hasTeacherModuleAccess(
          'egitim_islemleri',
          subModuleKey: 'sinav_tekil_liste',
        ) ||
        UserPermissionService.hasTeacherModuleAccess(
          'egitim_islemleri',
          subModuleKey: 'sinav_tekil_karne',
        ) ||
        UserPermissionService.hasTeacherModuleAccess(
          'egitim_islemleri',
          subModuleKey: 'sinav_tekil_ortalama',
        ) ||
        UserPermissionService.hasTeacherModuleAccess(
          'egitim_islemleri',
          subModuleKey: 'sinav_tekil_basari_belgesi',
        ) ||
        UserPermissionService.hasTeacherModuleAccess(
          'egitim_islemleri',
          subModuleKey: 'sinav_tekil_kazanim',
        ) ||
        UserPermissionService.hasTeacherModuleAccess(
          'egitim_islemleri',
          subModuleKey: 'sinav_tekil_soru',
        );

    final canViewBirlestirilmis =
        !isTeacher ||
        (UserPermissionService.hasTeacherModuleAccess(
              'egitim_islemleri',
              subModuleKey: 'sinav_raporlari',
            ) &&
            UserPermissionService.hasTeacherModuleAccess(
              'egitim_islemleri',
              subModuleKey: 'sinav_birlestirilmis_raporlar',
            ));

    final canViewGuclendirme =
        !isTeacher ||
        (UserPermissionService.hasTeacherModuleAccess(
              'egitim_islemleri',
              subModuleKey: 'sinav_raporlari',
            ) &&
            UserPermissionService.hasTeacherModuleAccess(
              'egitim_islemleri',
              subModuleKey: 'sinav_guclendirme_programlari',
            ));

    final canViewAgm =
        !isTeacher ||
        (UserPermissionService.hasTeacherModuleAccess(
              'egitim_islemleri',
              subModuleKey: 'sinav_raporlari',
            ) &&
            UserPermissionService.hasTeacherModuleAccess(
              'egitim_islemleri',
              subModuleKey: 'sinav_agm',
            ));

    final canViewActionPlan =
        !isTeacher ||
        (UserPermissionService.hasTeacherModuleAccess(
              'egitim_islemleri',
              subModuleKey: 'sinav_raporlari',
            ) &&
            UserPermissionService.hasTeacherModuleAccess(
              'egitim_islemleri',
              subModuleKey: 'sinav_aksiyon_plani',
            ));

    final canViewParent =
        !isTeacher ||
        (UserPermissionService.hasTeacherModuleAccess(
              'egitim_islemleri',
              subModuleKey: 'sinav_raporlari',
            ) &&
            UserPermissionService.hasTeacherModuleAccess(
              'egitim_islemleri',
              subModuleKey: 'sinav_veli_raporu',
            ));

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: EduknAppBar(
        title: 'Ölçme Değerlendirme Raporları',
        subtitle: schoolTypeName,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: MediaQuery.of(context).size.width < 600 ? 12 : 20,
          vertical: MediaQuery.of(context).size.width < 600 ? 16 : 24,
        ),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Grid of Main Cards (Mobilde genişliğe göre dinamik 2x2, Web'de 4x1)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final maxW = constraints.maxWidth;
                    final isDesktopRow = maxW > 860;
                    final tempCount =
                        (canViewTekil ? 1 : 0) +
                        (canViewBirlestirilmis ? 1 : 0) +
                        (canViewGuclendirme ? 1 : 0) +
                        (canViewAgm ? 1 : 0);
                    if (tempCount == 0) return const SizedBox.shrink();

                    final crossAxisCount = isDesktopRow
                        ? (tempCount < 4 ? tempCount : 4)
                        : (tempCount == 1 ? 1 : 2);
                    final gap = maxW < 400
                        ? 10.0
                        : (isDesktopRow ? 18.0 : 12.0);
                    final cardWidth =
                        (maxW - gap * (crossAxisCount - 1)) / crossAxisCount;
                    final mainExtent = isDesktopRow
                        ? 236.0
                        : (cardWidth < 170
                              ? 168.0
                              : (cardWidth < 220 ? 180.0 : 196.0));

                    final gridItems = <Widget>[
                      if (canViewTekil)
                        _buildHubCard(
                          context,
                          title: 'Tekil Sınav Raporları',
                          subtitle:
                              'Tek bir sınavın detaylı analiz ve raporları.',
                          icon: Icons.description_rounded,
                          color: Colors.indigo.shade700,
                          actionLabel: 'Görüntüle',
                          cardWidth: cardWidth,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SingleExamResultsScreen(
                                  institutionId: institutionId,
                                  schoolTypeId: schoolTypeId,
                                  schoolTypeName: schoolTypeName,
                                ),
                              ),
                            );
                          },
                        ),
                      if (canViewBirlestirilmis)
                        _buildHubCard(
                          context,
                          title: 'Birleştirilmiş Sınav Raporları',
                          subtitle:
                              'Birden fazla sınavın karşılaştırmalı raporları.',
                          icon: Icons.analytics_rounded,
                          color: Colors.teal.shade700,
                          actionLabel: 'Analiz Et',
                          cardWidth: cardWidth,
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
                      if (canViewGuclendirme)
                        _buildHubCard(
                          context,
                          title: 'Güçlendirme Programları',
                          subtitle:
                              'Öğrenci eksiklerine göre çalışma programları.',
                          icon: Icons.trending_up_rounded,
                          color: Colors.amber.shade800,
                          actionLabel: 'Program Oluştur',
                          cardWidth: cardWidth,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    GuidanceStudyProgramScreen(
                                      institutionId: institutionId,
                                      schoolTypeId: schoolTypeId,
                                    ),
                              ),
                            );
                          },
                        ),
                      if (canViewAgm)
                        _buildHubCard(
                          context,
                          title: 'AGM – Akademik Güçlendirme',
                          subtitle:
                              'Otomatik etüt grubu, özel sınıf ve yoğunlaştırılmış çalışma planları.',
                          icon: Icons.auto_awesome_rounded,
                          color: Colors.deepPurple.shade600,
                          actionLabel: 'Yönet',
                          cardWidth: cardWidth,
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
                    ];

                    return GridView.builder(
                      itemCount: gridItems.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: gap,
                        mainAxisSpacing: gap,
                        mainAxisExtent: mainExtent,
                      ),
                      itemBuilder: (context, idx) => gridItems[idx],
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
                            if (canViewActionPlan) ...[
                              const SizedBox(width: 24),
                              Expanded(
                                flex: 1,
                                child: _buildActionPlanCard(
                                  context,
                                  isCompact: true,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    } else {
                      return Column(
                        children: [
                          _buildPerformanceBanner(context),
                          if (canViewActionPlan) ...[
                            const SizedBox(height: 24),
                            _buildActionPlanCard(context, isCompact: false),
                          ],
                        ],
                      );
                    }
                  },
                ),

                if (_shouldShowChampionsBanner()) ...[
                  const SizedBox(height: 24),
                  _buildChampionsBanner(context),
                ],

                const SizedBox(height: 24),
                // Full-width ODAK-64 Card
                _buildOdak64Banner(context),

                if (canViewParent) ...[
                  const SizedBox(height: 24),
                  // Full-width Veli Bilgilendirme Raporu Card
                  _buildParentReportBanner(context),
                ],
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
    required double cardWidth,
  }) {
    final bool isCompact = cardWidth < 215;
    final bool isUltraCompact = cardWidth < 168;
    final double cardPadding = isUltraCompact ? 12 : (isCompact ? 15 : 22);
    final double iconPadding = isUltraCompact ? 7 : (isCompact ? 9 : 12);
    final double iconSize = isUltraCompact ? 19 : (isCompact ? 22 : 26);
    final double titleFontSize = (cardWidth * 0.082).clamp(13.0, 17.5);
    final double subFontSize = isUltraCompact ? 10.8 : 11.8;
    final double actionFontSize = isUltraCompact ? 11.6 : 12.8;
    final double radius = isCompact ? 18 : 24;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                // Subtle Top Color Accent
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
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
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(
                            isCompact ? 11 : 15,
                          ),
                        ),
                        child: Icon(icon, color: color, size: iconSize),
                      ),
                      SizedBox(height: isCompact ? 8 : 16),
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          height: 1.18,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: subFontSize,
                            color: Colors.grey.shade500,
                            height: 1.32,
                          ),
                          maxLines: isUltraCompact ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              actionLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: actionFontSize,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                          ),
                          const SizedBox(width: 3),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: isUltraCompact ? 14 : 16,
                            color: color,
                          ),
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
            color: Colors.indigo.withValues(alpha: 0.2),
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
                builder: (context) => PerformanceSummaryScreen(
                  institutionId: institutionId,
                  schoolTypeId: schoolTypeId,
                  schoolTypeName: schoolTypeName,
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
                  child: Icon(
                    Icons.auto_graph_rounded,
                    size: 180,
                    color: Colors.white,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Performans Özeti',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: MediaQuery.of(context).size.width < 360
                            ? 20
                            : 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Sınavı seçin, öğrencileri kendi şubelerinde ders ders analiz edin; ders öğretmenleri için ayrıntılı raporları PDF olarak alın.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: MediaQuery.of(context).size.width < 360
                            ? 12
                            : 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        'Görüntüle',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade900,
                        ),
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
              crossAxisAlignment: isCompact
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.assignment_turned_in_rounded,
                    color: Colors.deepOrange.shade400,
                    size: 28,
                  ),
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

  Widget _buildOdak64Banner(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 500;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.teal.shade700,
            Colors.cyan.shade800,
            Colors.blue.shade900,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => Odak64DashboardScreen(
                  institutionId: institutionId,
                  schoolTypeId: schoolTypeId,
                  schoolTypeName: schoolTypeName,
                ),
              ),
            );
          },
          child: Stack(
            children: [
              Positioned(
                right: -20,
                bottom: -30,
                child: Opacity(
                  opacity: 0.12,
                  child: const Icon(
                    Icons.center_focus_strong_rounded,
                    size: 200,
                    color: Colors.white,
                  ),
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
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.center_focus_strong_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'ODAK-64',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isSmall ? 20 : 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Sınıflar, dersler ve planlama modülü.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: isSmall ? 12 : 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        'Giriş Yap',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.teal.shade800,
                        ),
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
            color: Colors.indigo.withValues(alpha: 0.2),
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
                  child: Icon(
                    Icons.family_restroom_rounded,
                    size: 180,
                    color: Colors.white,
                  ),
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
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.family_restroom_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Veli Bilgilendirme Raporları',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: MediaQuery.of(context).size.width < 360
                                ? 20
                                : 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Öğrencinin haftalık sınav sonuçlarını ve AGM ders katılımlarını tek bir sayfada şık ve kurumsal PDF mektubu olarak derleyin.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: MediaQuery.of(context).size.width < 360
                            ? 12
                            : 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        'Rapor Hazırla',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade900,
                        ),
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

  bool _shouldShowChampionsBanner() {
    final norm = AcademicTrackingDataService.normTr(schoolTypeName ?? '');
    if (norm.contains('ilkokul') ||
        norm.contains('anaokul') ||
        norm.contains('kres')) {
      return false;
    }
    return true;
  }

  Widget _buildChampionsBanner(BuildContext context) {
    final norm = AcademicTrackingDataService.normTr(schoolTypeName ?? '');
    final isHigh =
        norm.contains('lise') ||
        norm.contains('anadolu') ||
        norm.contains('fen lise') ||
        norm.contains('kurs');
    final isMiddle = norm.contains('ortaokul');
    final title = isHigh
        ? 'YKS ŞAMPİYONLARI'
        : (isMiddle ? 'LGS ŞAMPİYONLARI' : 'LGS & YKS ŞAMPİYONLARI');
    final desc = isHigh
        ? 'Aktif dönem deneme verilerine göre Türkiye İlk 100 / İlk 1.000 / İlk 5.000 bandındaki elit derece adaylarını odaklanmış havuzda inceleyin.'
        : 'Aktif dönem deneme verilerine göre 500 Tam Puan, İlk %0.1 ve İlk %0.5 bandındaki gerçek LGS şampiyon adaylarını daraltılmış havuzda inceleyin.';
    final isSmall = MediaQuery.of(context).size.width < 360;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF312E81), Color(0xFFB45309)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB45309).withValues(alpha: 0.22),
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
                builder: (_) => ChampionsLeagueLoaderScreen(
                  institutionId: institutionId,
                  schoolTypeId: schoolTypeId,
                  schoolTypeName: schoolTypeName ?? '',
                  isTeacher: isTeacher,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              const Positioned(
                right: -18,
                bottom: -20,
                child: Opacity(
                  opacity: 0.12,
                  child: Icon(
                    Icons.emoji_events_rounded,
                    size: 180,
                    color: Colors.white,
                  ),
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
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFBBF24,
                            ).withValues(alpha: 0.22),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.emoji_events_rounded,
                            color: Color(0xFFFBBF24),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isSmall ? 19 : 23,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      desc,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: isSmall ? 12 : 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBBF24),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Text(
                        'Şampiyonları & Yüzdelik İhtimalleri Aç',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E1B4B),
                        ),
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
