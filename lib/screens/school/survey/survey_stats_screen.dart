import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/survey_model.dart';
import '../../../services/survey_service.dart';
import '../../../services/announcement_service.dart';
import 'create_survey_screen.dart';

// Reports
import '../../guidance/reports/failure_causes_report.dart';
import '../../guidance/reports/academic_self_concept_report.dart';
import '../../guidance/reports/test_anxiety_report.dart';
import '../../guidance/reports/burdon_attention_report.dart';
import '../../guidance/reports/sleep_deprivation_report.dart';
import '../../guidance/reports/technology_addiction_report.dart';
import '../../guidance/reports/stress_coping_report.dart';
import '../../guidance/reports/depressive_tendency_report.dart';
import '../../guidance/reports/anxiety_assessment_report.dart';
import '../../guidance/reports/social_skill_report.dart';
import '../../guidance/reports/exam_anxiety_coping_report.dart';
import '../../guidance/reports/academic_procrastination_report.dart';
import '../../guidance/reports/test_taking_skills_report.dart';
import '../../guidance/reports/exam_prep_skills_report.dart';
import '../../guidance/reports/post_exam_self_evaluation_report.dart';
import '../../guidance/reports/learning_styles_report.dart';
import '../../guidance/reports/school_adaptation_report.dart';
import '../../guidance/reports/attention_focus_report.dart';
import '../../guidance/reports/academic_resilience_report.dart';
import '../../guidance/reports/academic_self_efficacy_report.dart';
import '../../guidance/reports/academic_motivation_report.dart';
import '../../guidance/reports/academic_emotional_responses_report.dart';
import '../../guidance/reports/academic_self_regulation_report.dart';
import '../../guidance/reports/exam_cognitive_processes_report.dart';
import '../../guidance/reports/academic_motivation_sources_report.dart';
import '../../guidance/reports/failure_perception_report.dart';
import '../../guidance/reports/academic_self_efficacy_control_report.dart';
import '../../guidance/reports/time_management_discipline_report.dart';
import '../../guidance/reports/academic_motivation_goal_report.dart';
import '../../guidance/reports/academic_resilience_grit_report.dart';
import '../../guidance/reports/academic_anxiety_performance_report.dart';
import '../../guidance/reports/self_regulation_management_report.dart';
import '../../guidance/reports/academic_self_efficacy_confidence_report.dart';
import '../../guidance/reports/failure_fear_performance_obstacle_report.dart';
import '../../guidance/reports/emotional_regulation_resilience_report.dart';

class SurveyStatsScreen extends StatefulWidget {
  final Survey survey;

  const SurveyStatsScreen({Key? key, required this.survey}) : super(key: key);

  @override
  State<SurveyStatsScreen> createState() => _SurveyStatsScreenState();
}

class _SurveyStatsScreenState extends State<SurveyStatsScreen>
    with SingleTickerProviderStateMixin {
  final SurveyService _surveyService = SurveyService();
  final AnnouncementService _announcementService = AnnouncementService();

  late TabController _tabController;

  bool _isLoading = true;
  List<Map<String, dynamic>> _responses = [];
  List<Map<String, dynamic>> _targetUsers = [];
  Map<String, String> _userNames = {}; // userId -> Name

  // Stats
  int _totalTargetCount = 0;
  int _responseCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    print(
      '📊 SurveyStatsScreen: Starting to load data for survey ${widget.survey.id}',
    );

    try {
      // 1. Fetch Responses with timeout
      print('📊 Fetching survey responses...');
      final responses = await _surveyService
          .getSurveyResponses(widget.survey.id)
          .timeout(
            Duration(seconds: 10),
            onTimeout: () {
              print('⚠️ Survey responses fetch timed out');
              return [];
            },
          );
      print('✅ Got ${responses.length} responses');

      // 2. Fetch Target Audience with timeout
      print('📊 Fetching target users...');
      final allUsers = await _announcementService.getAllUsers().timeout(
        Duration(seconds: 10),
        onTimeout: () {
          print('⚠️ getAllUsers timed out');
          return [];
        },
      );
      print('✅ Got ${allUsers.length} total users');

      List<Map<String, dynamic>> targets = [];

      if (widget.survey.targetType == SurveyTargetType.all) {
        targets = allUsers;
      } else if (widget.survey.targetType == SurveyTargetType.teachers) {
        targets = allUsers.where((u) => u['role'] == 'Öğretmen').toList();
      } else if (widget.survey.targetType == SurveyTargetType.students) {
        targets = allUsers.where((u) => u['role'] == 'Öğrenci').toList();
      } else if (widget.survey.targetType == SurveyTargetType.parents) {
        targets = allUsers.where((u) => u['role'] == 'Veli').toList();
      }
      print('✅ Filtered to ${targets.length} target users');

      // Create user map for quick lookup
      final nameMap = <String, String>{};
      for (var u in allUsers) {
        nameMap[u['id'].toString()] = u['name'] ?? 'İsimsiz';
      }

      if (mounted) {
        setState(() {
          _responses = responses;
          _targetUsers = targets;
          _responseCount = responses.length;
          _totalTargetCount = targets.length;
          _userNames = nameMap;
          _isLoading = false;
        });
        print('✅ SurveyStatsScreen: Data loaded successfully');
      }
    } catch (e, stackTrace) {
      print('❌ SurveyStatsScreen error: $e');
      print('Stack trace: $stackTrace');

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Veriler yüklenirken hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleSurveyStatus() async {
    if (widget.survey.status == SurveyStatus.closed) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Anketi Kapat'),
        content: Text(
          'Bu anketi yayından kaldırmak istediğinize emin misiniz? Artık kimse yanıt veremeyecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Evet, Kapat', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _surveyService.closeSurvey(widget.survey.id);
      setState(() {
        // Update local object blindly or refetch
        // We can't easily modify 'widget.survey' as it is final,
        // but for UI purposes we ideally should navigate back or show updated status
        // Let's just pop back to list to refresh list
        Navigator.pop(context);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Anket kapatıldı.')));
    }
  }

  Future<void> _deleteSurvey() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Anketi Sil'),
        content: Text(
          'Bu anketi silmek istediğinize emin misiniz? Tüm yanıtlar ve veriler kalıcı olarak silinecektir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Evet, Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _surveyService.deleteSurvey(widget.survey.id);
      if (mounted) {
        Navigator.pop(context); // Close stats screen
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Anket silindi.')));
    }
  }

  void _duplicateAndEditSurvey() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateSurveyScreen(
          institutionId: widget.survey.institutionId,
          schoolTypeId: widget.survey.schoolTypeId,
          templateSurvey: widget.survey,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Anket Sonuçları',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (widget.survey.status == SurveyStatus.published)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton.icon(
                onPressed: _toggleSurveyStatus,
                icon: Icon(
                  Icons.stop_circle_outlined,
                  color: Colors.deepOrange,
                ),
                label: Text(
                  'Yayını Durdur',
                  style: TextStyle(color: Colors.deepOrange),
                ),
              ),
            ),
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'clone') _duplicateAndEditSurvey();
              if (val == 'delete') _deleteSurvey();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'clone',
                child: Row(
                  children: [
                    Icon(Icons.copy, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('Kopyala & Düzenle'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Anketi Sil', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(60),
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(25),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey[700],
              indicator: BoxDecoration(
                color: Colors.indigo,
                borderRadius: BorderRadius.circular(25),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              tabs: [
                Tab(text: 'Özet & Grafikler'),
                Tab(text: 'Katılımcı Listesi'),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 1000),
                child: TabBarView(
                  controller: _tabController,
                  physics: NeverScrollableScrollPhysics(), // Scroll inside tabs
                  children: [
                    if (widget.survey.guidanceTemplateId == 'failure_causes_v1')
                      FailureCausesReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'academic_self_concept_v1')
                      AcademicSelfConceptReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'test_anxiety_v1')
                      TestAnxietyReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId == 'burdon_v1')
                      BurdonAttentionReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'sleep_deprivation_v1')
                      SleepDeprivationReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'technology_addiction_v1')
                      TechnologyAddictionReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'stress_coping_v1')
                      StressCopingReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'depressive_tendency_v1')
                      DepressiveTendencyReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'anxiety_assessment_v1')
                      AnxietyAssessmentReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'social_skill_v1')
                      SocialSkillReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'exam_anxiety_coping_v1')
                      ExamAnxietyCopingReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'academic_procrastination_v1')
                      AcademicProcrastinationReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'test_taking_skills_v1')
                      TestTakingSkillsReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'exam_prep_skills_v1')
                      ExamPrepSkillsReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'post_exam_self_evaluation_v1')
                      PostExamSelfEvaluationReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'learning_styles_3x2_v1')
                      LearningStylesReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'school_adaptation_v1')
                      SchoolAdaptationReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'attention_focus_v1')
                      AttentionFocusReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'academic_resilience_v1')
                      AcademicResilienceReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'academic_self_efficacy_v1')
                      AcademicSelfEfficacyReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'academic_motivation_v1')
                      AcademicMotivationReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'academic_emotional_responses_v1')
                      AcademicEmotionalResponsesReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'academic_self_regulation_v1')
                      AcademicSelfRegulationReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'exam_cognitive_processes_v1')
                      ExamCognitiveProcessesReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'academic_motivation_sources_v1')
                      AcademicMotivationSourcesReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'failure_perception_v1')
                      FailurePerceptionReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'academic_self_efficacy_control_v1')
                      AcademicSelfEfficacyControlReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'time_management_discipline_v1')
                      TimeManagementDisciplineReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'academic_motivation_goal_v1')
                      AcademicMotivationGoalReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'academic_resilience_grit_v1')
                      AcademicResilienceGritReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'academic_anxiety_performance_v1')
                      AcademicAnxietyPerformanceReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'self_regulation_management_v1')
                      SelfRegulationManagementReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'academic_self_efficacy_confidence_v1')
                      AcademicSelfEfficacyConfidenceReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'failure_fear_performance_obstacle_v1')
                      FailureFearPerformanceObstacleReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'emotional_regulation_resilience_v1')
                      EmotionalRegulationResilienceReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else if (widget.survey.guidanceTemplateId ==
                        'academic_motivation_sources_v1')
                      AcademicMotivationSourcesReport(
                        survey: widget.survey,
                        responses: _responses,
                        userNames: _userNames,
                      )
                    else
                      _buildSummaryTab(),

                    _buildRespondentsTab(),
                  ],
                ),
              ),
            ),
    );
  }

  // --- TAB 1: SUMMARY & CHARTS ---
  Widget _buildSummaryTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Info Cards Row - Responsive
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 600;
              return Flex(
                direction: isWide ? Axis.horizontal : Axis.vertical,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isWide) ...[
                    Expanded(
                      child: _buildInfoCard(
                        'Toplam Hedef',
                        '$_totalTargetCount Kişi',
                        Icons.people_outline,
                        Colors.blue,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: _buildInfoCard(
                        'Yanıtlayanlar',
                        '$_responseCount Kişi',
                        Icons.check_circle_outline,
                        Colors.green,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: _buildInfoCard(
                        'Katılım Oranı',
                        '${_totalTargetCount == 0 ? 0 : ((_responseCount / _totalTargetCount) * 100).toStringAsFixed(1)}%',
                        Icons.pie_chart_outline,
                        Colors.purple,
                      ),
                    ),
                  ] else ...[
                    // Vertical stack for narrow screens (mobile)
                    _buildInfoCard(
                      'Toplam Hedef',
                      '$_totalTargetCount Kişi',
                      Icons.people_outline,
                      Colors.blue,
                    ),
                    SizedBox(height: 12),
                    _buildInfoCard(
                      'Yanıtlayanlar',
                      '$_responseCount Kişi',
                      Icons.check_circle_outline,
                      Colors.green,
                    ),
                    SizedBox(height: 12),
                    _buildInfoCard(
                      'Katılım Oranı',
                      '${_totalTargetCount == 0 ? 0 : ((_responseCount / _totalTargetCount) * 100).toStringAsFixed(1)}%',
                      Icons.pie_chart_outline,
                      Colors.purple,
                    ),
                  ],
                ],
              );
            },
          ),
          SizedBox(height: 32),

          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Soru Bazlı Analiz',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(height: 16),

          ...widget.survey.sections.expand((section) {
            return section.questions.map((q) => _buildQuestionChartCard(q));
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: EdgeInsets.all(20),
      // Use width infinity for vertical stack, otherwise flexible
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionChartCard(SurveyQuestion q) {
    // Only visualize choice/rating questions nicely. Text questions are listed.
    bool specificChart =
        (q.type == SurveyQuestionType.singleChoice ||
        q.type == SurveyQuestionType.multipleChoice ||
        q.type == SurveyQuestionType.rating);

    return Container(
      margin: EdgeInsets.only(bottom: 24),
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            q.text,
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 24),
          if (specificChart) ...[
            SizedBox(height: 200, child: _buildChartForQuestion(q)),
          ] else ...[
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Bu soru tipi için metin yanıtları "Katılımcı Listesi" sekmesinden inceleyebilirsiniz.',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChartForQuestion(SurveyQuestion q) {
    Map<String, int> counts = {};

    // Initialize options with 0
    if (q.type == SurveyQuestionType.rating) {
      for (int i = 1; i <= 5; i++) counts[i.toString()] = 0;
    } else {
      for (var opt in q.options) counts[opt] = 0;
    }

    // Tally up
    for (var resp in _responses) {
      final answers = resp['answers'] as Map<String, dynamic>?;
      if (answers == null) continue;

      final ans = answers[q.id];
      if (ans == null) continue;

      if (ans is String) {
        // Single choice or rating converted to string
        counts[ans.toString()] = (counts[ans.toString()] ?? 0) + 1;
      } else if (ans is int) {
        counts[ans.toString()] = (counts[ans.toString()] ?? 0) + 1;
      } else if (ans is List) {
        // Multiple choice
        for (var item in ans) {
          counts[item.toString()] = (counts[item.toString()] ?? 0) + 1;
        }
      }
    }

    // Convert to Pie or Bar chart data
    // Let's use simple Bar rows for readability
    final total = _responses.length == 0
        ? 1
        : _responses.length; // avoid div by 0 for percentages

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: counts.entries.map((e) {
        final val = e.value;
        final pct = (val / total * 100).toStringAsFixed(1);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  e.key,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: val / total > 1
                          ? 1
                          : (val /
                                total), // In multi-choice, sum > total, but per bar max is total
                      child: Container(
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.indigoAccent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              SizedBox(
                width: 40,
                child: Text(
                  '$val',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                // Use Expanded or Flexible instead of fixed SizedBox
                flex: 0,
                child: Container(
                  constraints: BoxConstraints(minWidth: 60),
                  child: Text(
                    '($pct%)',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                    textAlign: TextAlign.end,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // --- TAB 2: RESPONDENTS & DATA TABLE ---
  Widget _buildRespondentsTab() {
    // Anonim anketse sadece yanıtlayanları göster, isimleri gizle
    if (widget.survey.isAnonymous) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Bu anket anonimdir. Katılımcı isimleri gizlenmiştir ve yanıtlamayanlar listelenmez.',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.indigo,
              ),
            ),
          ),
          Expanded(child: _buildResponseTable()),
        ],
      );
    }

    final respondedIds = _responses.map((r) => r['userId'].toString()).toSet();
    final notResponded = _targetUsers
        .where((u) => !respondedIds.contains(u['id'].toString()))
        .toList();

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            labelColor: Colors.black87,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.grey[300],
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: [
              Tab(text: 'Yanıtlayanlar (${_responses.length})'),
              Tab(text: 'Yanıtlamayanlar (${notResponded.length})'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildResponseTable(),
                _buildNotRespondedList(notResponded),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponseTable() {
    if (_responses.isEmpty) return Center(child: Text('Henüz yanıt yok'));

    // Flatten logic for Table:
    // Columns: Name, Question 1, Question 2 ...
    // NOTE: If too many questions, this needs horizontal scroll.

    final allQuestions = widget.survey.sections
        .expand((s) => s.questions)
        .toList();

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(Colors.grey[100]),
          columns: [
            DataColumn(
              label: Text(
                'İsim Soyisim',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ...allQuestions.map(
              (q) => DataColumn(
                label: Container(
                  width: 150,
                  child: Text(
                    q.text,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
          rows: _responses.map((resp) {
            final uid = resp['userId'].toString();
            final name = _userNames[uid] ?? 'Bilinmeyen Kullanıcı';
            final answers = resp['answers'] as Map<String, dynamic>? ?? {};

            return DataRow(
              cells: [
                DataCell(
                  Text(
                    widget.survey.isAnonymous ? '**** ****' : name,
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                ...allQuestions.map((q) {
                  var ans = answers[q.id];
                  String display = '-';
                  if (ans != null) {
                    if (ans is List)
                      display = ans.join(', ');
                    else
                      display = ans.toString();
                  }
                  return DataCell(
                    Container(
                      width: 150,
                      child: Text(display, overflow: TextOverflow.ellipsis),
                    ),
                  );
                }),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildNotRespondedList(List<Map<String, dynamic>> users) {
    if (users.isEmpty) return Center(child: Text('Herkes yanıtladı! 🎉'));

    return ListView.builder(
      itemCount: users.length,
      itemBuilder: (context, index) {
        final u = users[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.grey[200],
            child: Text(
              u['name']?[0] ?? '?',
              style: TextStyle(color: Colors.grey[700]),
            ),
          ),
          title: Text(u['name'] ?? 'İsimsiz'),
          subtitle: Text(u['role'] ?? '-'),
        );
      },
    );
  }
}
