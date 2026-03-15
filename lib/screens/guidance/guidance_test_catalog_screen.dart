import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/guidance/tests/guidance_test_definition.dart';
import '../../models/guidance/tests/failure_causes_test.dart';
import '../../models/guidance/tests/academic_self_concept_test.dart';
import '../../models/guidance/tests/test_anxiety_test.dart';
import '../../models/guidance/tests/burdon_attention_test.dart';
import '../../models/guidance/tests/sleep_deprivation_test.dart';
import '../../models/guidance/tests/technology_addiction_test.dart';
import '../../models/guidance/tests/stress_coping_test.dart';
import '../../models/guidance/tests/depressive_tendency_test.dart';
import '../../models/guidance/tests/anxiety_assessment_test.dart';
import '../../models/guidance/tests/social_skill_test.dart';
import '../../models/guidance/tests/exam_anxiety_coping_test.dart';
import '../../models/guidance/tests/academic_procrastination_test.dart';
import '../../models/guidance/tests/test_taking_skills_test.dart';
import '../../models/guidance/tests/exam_prep_skills_test.dart';
import '../../models/guidance/tests/post_exam_self_evaluation_test.dart';
import '../../models/guidance/tests/learning_styles_3x2_test.dart';
import '../../models/guidance/tests/school_adaptation_test.dart';
import '../../models/guidance/tests/attention_focus_test.dart';
import '../../models/guidance/tests/academic_resilience_test.dart';
import '../../models/guidance/tests/academic_self_efficacy_test.dart';
import '../../models/guidance/tests/academic_motivation_test.dart';
import '../../models/guidance/tests/academic_emotional_responses_test.dart';
import '../../models/guidance/tests/academic_self_regulation_test.dart';
import '../../models/guidance/tests/exam_cognitive_processes_test.dart';
import '../../models/guidance/tests/academic_motivation_sources_test.dart';
import '../../models/guidance/tests/failure_perception_test.dart';
import '../../models/guidance/tests/academic_self_efficacy_control_test.dart';
import '../../models/guidance/tests/time_management_discipline_test.dart';
import '../../models/guidance/tests/academic_motivation_goal_test.dart';
import '../../models/guidance/tests/academic_resilience_grit_test.dart';
import '../../models/guidance/tests/academic_anxiety_performance_test.dart';
import '../../models/guidance/tests/self_regulation_management_test.dart';
import '../../models/guidance/tests/academic_self_efficacy_confidence_test.dart';
import '../../models/guidance/tests/failure_fear_performance_obstacle_test.dart';
import '../../models/guidance/tests/emotional_regulation_resilience_test.dart';
import '../../models/guidance/tests/goal_setting_purpose_clarity_test.dart';
import '../../models/guidance/tests/time_management_prioritization_test.dart';
import '../../models/guidance/tests/self_regulation_control_test.dart';
import '../../models/guidance/tests/academic_motivation_internal_test.dart';
import '../../models/guidance/tests/academic_self_efficacy_perception_test.dart';
import '../../models/survey_model.dart';
// For full customization if needed?
// Or we might navigate to a simplified publish dialog.

import '../school/survey/survey_response_screen.dart';
import 'guidance_test_publish_screen.dart'; // New Publish Screen
import 'guidance_test_history_screen.dart'; // New History Screen
import 'guidance_test_policy_screen.dart';
import 'guidance_category_detail_screen.dart';

class GuidanceTestCatalogScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const GuidanceTestCatalogScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<GuidanceTestCatalogScreen> createState() =>
      _GuidanceTestCatalogScreenState();
}

class _GuidanceTestCatalogScreenState extends State<GuidanceTestCatalogScreen> {
  // REGISTER NEW TESTS HERE
  final List<GuidanceTestDefinition> _availableTests = [
    FailureCausesTest(),
    AcademicSelfConceptTest(),
    TestAnxietyTest(),
    BurdonAttentionTest(),
    SleepDeprivationTest(),
    TechnologyAddictionTest(),
    StressCopingTest(),
    DepressiveTendencyTest(),
    AnxietyAssessmentTest(),
    SocialSkillTest(),
    ExamAnxietyCopingTest(),
    AcademicProcrastinationTest(),
    TestTakingSkillsTest(),
    ExamPrepSkillsTest(),
    PostExamSelfEvaluationTest(),
    LearningStyles3x2Test(),
    SchoolAdaptationTest(),
    AttentionFocusTest(),
    AcademicResilienceTest(),
    AcademicSelfEfficacyTest(),
    AcademicMotivationTest(),
    AcademicEmotionalResponsesTest(),
    AcademicSelfRegulationTest(),
    ExamCognitiveProcessesTest(),
    AcademicMotivationSourcesTest(),
    FailurePerceptionTest(),
    AcademicSelfEfficacyControlTest(),
    TimeManagementDisciplineTest(),
    AcademicMotivationGoalTest(),
    AcademicResilienceGritTest(),
    AcademicAnxietyPerformanceTest(),
    SelfRegulationManagementTest(),
    AcademicSelfEfficacyConfidenceTest(),
    FailureFearPerformanceObstacleTest(),
    EmotionalRegulationResilienceTest(),
    GoalSettingPurposeClarityTest(),
    TimeManagementPrioritizationTest(),
    SelfRegulationControlTest(),
    AcademicMotivationInternalTest(),
    AcademicSelfEfficacyPerceptionTest(),
  ];

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _availableTests.sort((a, b) => a.title.compareTo(b.title));
  }

  void _onTestSelected(GuidanceTestDefinition test, String action) async {
    if (action == 'preview') {
      final dummySurvey = test.createSurvey(
        institutionId: 'preview',
        schoolTypeId: 'preview',
        authorId: 'preview',
        targetIds: [],
        targetType: SurveyTargetType.students,
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => SurveyResponseScreen(survey: dummySurvey),
        ),
      );
    } else if (action == 'history') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => GuidanceTestHistoryScreen(
            templateId: test.id,
            templateTitle: test.title,
            institutionId: widget.institutionId,
          ),
        ),
      );
    } else if (action == 'publish') {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => GuidanceTestPublishScreen(
            test: test,
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
            authorId: userId,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: Text('Rehberlik Envanterleri', style: GoogleFonts.inter()),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildInfoBanner(isMobile)),
              SliverToBoxAdapter(child: _buildSearchBox()),
              if (_searchQuery.isEmpty) ...[
                _buildCategoryGridSliver(),
              ] else ...[
                _buildSearchResultsSliver(),
              ],
              // Add some padding at the bottom
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBox() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Tüm testlerde ara...',
          prefixIcon: const Icon(Icons.search, color: Colors.indigo),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: const BorderSide(color: Colors.indigo, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResultsSliver() {
    final filtered = _availableTests
        .where(
          (t) =>
              t.title.toLowerCase().contains(_searchQuery) ||
              t.description.toLowerCase().contains(_searchQuery),
        )
        .toList();

    if (filtered.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text(
                'Aramanızla eşleşen test bulunamadı.',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final test = filtered[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            child: _buildExtendedTestCard(test),
          );
        }, childCount: filtered.length),
      ),
    );
  }

  Widget _buildExtendedTestCard(GuidanceTestDefinition test) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.assignment_ind, color: Colors.indigo),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        test.title,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        test.description,
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _onTestSelected(test, 'publish'),
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('Öğrencilere Gönder'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.indigo,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.visibility,
                    size: 22,
                    color: Colors.grey,
                  ),
                  onPressed: () => _onTestSelected(test, 'preview'),
                  tooltip: 'Önizle',
                ),
                IconButton(
                  icon: const Icon(Icons.history, size: 22, color: Colors.grey),
                  onPressed: () => _onTestSelected(test, 'history'),
                  tooltip: 'Geçmiş',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner(bool isMobile) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(16, 16, 16, isMobile ? 4 : 8),
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade600, Colors.indigo.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
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
                child: Icon(
                  Icons.info_outline,
                  color: Colors.white,
                  size: isMobile ? 18 : 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Rehberlik Envanterleri',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: isMobile ? 16 : 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_availableTests.length} Test',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 8 : 12),
          Text(
            'Bu katalog, öğrencilerimizin akademik, duygusal ve sosyal gelişimlerini takip etmek için profesyonelce hazırlanmış ölçekleri içerir. Bu testler tanı koyma amacı taşımaz.',
            style: GoogleFonts.inter(
              color: Colors.white.withOpacity(0.9),
              fontSize: isMobile ? 12 : 13,
              height: 1.4,
            ),
            maxLines: isMobile ? 3 : 5,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: isMobile ? 8 : 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const GuidanceTestPolicyScreen(),
                  ),
                );
              },
              icon: Icon(
                Icons.auto_stories_outlined,
                size: isMobile ? 14 : 16,
                color: Colors.white,
              ),
              label: Text(
                'Yönergeyi Oku',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: isMobile ? 12 : 13,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryGridSliver() {
    final categories = [
      {
        'title': 'Genel Akademik & Öz Yeterlik',
        'desc': 'Akademik benlik, özgüven ve akademik dayanıklılık analizleri.',
        'icon': Icons.school,
        'color': Colors.blue,
        'id': 1,
      },
      {
        'title': 'Dikkat & Odaklanma',
        'desc': 'Bilişsel performans ve odaklanma becerileri değerlendirmesi.',
        'icon': Icons.psychology,
        'color': Colors.deepPurple,
        'id': 2,
      },
      {
        'title': 'Sınav Süreci & Davranışlar',
        'desc': 'Çalışma alışkanlıkları, erteleme ve sınav anı stratejileri.',
        'icon': Icons.assignment,
        'color': Colors.orange,
        'id': 3,
      },
      {
        'title': 'Kaygı, Stres & Duygular',
        'desc': 'Sınav kaygısı ve psikolojik faktörlerin akademik etkisi.',
        'icon': Icons.favorite,
        'color': Colors.red,
        'id': 4,
      },
      {
        'title': 'Yaşam Düzeni & Çevre',
        'desc':
            'Uyku, teknoloji bağımlılığı ve dış odaklı performans engelleri.',
        'icon': Icons.bedtime,
        'color': Colors.teal,
        'id': 5,
      },
      {
        'title': 'Sosyal & Okula Uyum',
        'desc': 'Sosyal beceriler ve okul ortamına uyum göstergeleri.',
        'icon': Icons.people,
        'color': Colors.indigo,
        'id': 6,
      },
    ];

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 300,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          mainAxisExtent: 165,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final cat = categories[index];
          return _buildCategoryCard(cat);
        }, childCount: categories.length),
      ),
    );
  }

  Widget _buildCategoryCard(Map<String, dynamic> cat) {
    final color = cat['color'] as Color;
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GuidanceCategoryDetailScreen(
              title: cat['title'],
              description: cat['desc'],
              tests: _getFilteredTests(cat['id']),
              institutionId: widget.institutionId,
              schoolTypeId: widget.schoolTypeId,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: color.withOpacity(0.2), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(cat['icon'], color: color, size: 24),
            ),
            const Spacer(),
            Text(
              cat['title'],
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              cat['desc'],
              style: TextStyle(
                fontSize: 10.5,
                color: Colors.grey.shade600,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  List<GuidanceTestDefinition> _getFilteredTests(int categoryId) {
    if (categoryId == 0) return _availableTests;
    return _availableTests.where((test) {
      switch (categoryId) {
        case 1: // Zemin & Öz Yeterlik
          return test is AcademicSelfConceptTest ||
              test is AcademicSelfEfficacyTest ||
              test is AcademicResilienceTest ||
              test is AcademicMotivationTest ||
              test is AcademicMotivationSourcesTest ||
              test is AcademicSelfEfficacyControlTest ||
              test is AcademicMotivationGoalTest ||
              test is AcademicResilienceGritTest ||
              test is AcademicSelfEfficacyConfidenceTest ||
              test is AcademicMotivationInternalTest ||
              test is AcademicSelfEfficacyPerceptionTest;
        case 2: // Dikkat & Odak
          return test is BurdonAttentionTest || test is AttentionFocusTest;
        case 3: // Sınav Süreci & Davranışlar
          return test is AcademicProcrastinationTest ||
              test is TestTakingSkillsTest ||
              test is ExamPrepSkillsTest ||
              test is PostExamSelfEvaluationTest ||
              test is LearningStyles3x2Test ||
              test is AcademicSelfRegulationTest ||
              test is ExamCognitiveProcessesTest ||
              test is TimeManagementDisciplineTest ||
              test is SelfRegulationManagementTest ||
              test is GoalSettingPurposeClarityTest ||
              test is TimeManagementPrioritizationTest ||
              test is SelfRegulationControlTest;
        case 4: // Kaygı, Stres & Duygular
          return test is TestAnxietyTest ||
              test is StressCopingTest ||
              test is DepressiveTendencyTest ||
              test is AnxietyAssessmentTest ||
              test is ExamAnxietyCopingTest ||
              test is AcademicEmotionalResponsesTest ||
              test is AcademicAnxietyPerformanceTest ||
              test is EmotionalRegulationResilienceTest;
        case 5: // Yaşam Düzeni & Çevre
          return test is SleepDeprivationTest ||
              test is TechnologyAddictionTest ||
              test is FailureCausesTest ||
              test is FailurePerceptionTest ||
              test is FailureFearPerformanceObstacleTest;
        case 6: // Sosyal & Okula Uyum
          return test is SocialSkillTest || test is SchoolAdaptationTest;
        default:
          return true;
      }
    }).toList();
  }
}
