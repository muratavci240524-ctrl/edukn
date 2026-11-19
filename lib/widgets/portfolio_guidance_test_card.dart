import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/survey_model.dart';
import '../screens/guidance/reports/failure_causes_report.dart';
import '../screens/guidance/reports/academic_self_concept_report.dart';
import '../screens/guidance/reports/test_anxiety_report.dart';
import '../screens/guidance/reports/burdon_attention_report.dart';
import '../screens/guidance/reports/sleep_deprivation_report.dart';
import '../screens/guidance/reports/technology_addiction_report.dart';
import '../screens/guidance/reports/stress_coping_report.dart';
import '../screens/guidance/reports/depressive_tendency_report.dart';
import '../screens/guidance/reports/anxiety_assessment_report.dart';
import '../screens/guidance/reports/social_skill_report.dart';
import '../screens/guidance/reports/exam_anxiety_coping_report.dart';
import '../screens/guidance/reports/academic_procrastination_report.dart';
import '../screens/guidance/reports/test_taking_skills_report.dart';
import '../screens/guidance/reports/exam_prep_skills_report.dart';
import '../screens/guidance/reports/post_exam_self_evaluation_report.dart';
import '../screens/guidance/reports/learning_styles_report.dart';
import '../screens/guidance/reports/school_adaptation_report.dart';
import '../screens/guidance/reports/attention_focus_report.dart';
import '../screens/guidance/reports/academic_resilience_report.dart';
import '../screens/guidance/reports/academic_self_efficacy_report.dart';
import '../screens/guidance/reports/academic_motivation_report.dart';
import '../screens/guidance/reports/academic_emotional_responses_report.dart';
import '../screens/guidance/reports/academic_self_regulation_report.dart';
import '../screens/guidance/reports/exam_cognitive_processes_report.dart';
import '../screens/guidance/reports/academic_motivation_sources_report.dart';
import '../screens/guidance/reports/failure_perception_report.dart';
import '../screens/guidance/reports/academic_self_efficacy_control_report.dart';
import '../screens/guidance/reports/time_management_discipline_report.dart';
import '../screens/guidance/reports/academic_motivation_goal_report.dart';
import '../screens/guidance/reports/academic_resilience_grit_report.dart';
import '../screens/guidance/reports/academic_anxiety_performance_report.dart';
import '../screens/guidance/reports/self_regulation_management_report.dart';
import '../screens/guidance/reports/academic_self_efficacy_confidence_report.dart';
import '../screens/guidance/reports/failure_fear_performance_obstacle_report.dart';
import '../screens/guidance/reports/emotional_regulation_resilience_report.dart';

/// Portföy > Rehberlik Testleri: Başlığa tıklayınca öğrencinin test raporu
/// kartın ALTINA doğru açılır (ilgili envanterin kendi raporu, yalnızca bu
/// öğrencinin cevaplarıyla).
class PortfolioGuidanceTestCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String studentId;
  final String studentName;

  const PortfolioGuidanceTestCard({
    super.key,
    required this.data,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<PortfolioGuidanceTestCard> createState() =>
      _PortfolioGuidanceTestCardState();
}

typedef _ReportBuilder =
    Widget Function(
      Survey survey,
      List<Map<String, dynamic>> responses,
      Map<String, String> userNames,
    );

class _PortfolioGuidanceTestCardState extends State<PortfolioGuidanceTestCard> {
  static final Map<String, _ReportBuilder> _builders = {
    'failure_causes_v1': (s, r, n) =>
        FailureCausesReport(survey: s, responses: r, userNames: n),
    'academic_self_concept_v1': (s, r, n) =>
        AcademicSelfConceptReport(survey: s, responses: r, userNames: n),
    'test_anxiety_v1': (s, r, n) =>
        TestAnxietyReport(survey: s, responses: r, userNames: n),
    'burdon_v1': (s, r, n) =>
        BurdonAttentionReport(survey: s, responses: r, userNames: n),
    'sleep_deprivation_v1': (s, r, n) =>
        SleepDeprivationReport(survey: s, responses: r, userNames: n),
    'technology_addiction_v1': (s, r, n) =>
        TechnologyAddictionReport(survey: s, responses: r, userNames: n),
    'stress_coping_v1': (s, r, n) =>
        StressCopingReport(survey: s, responses: r, userNames: n),
    'depressive_tendency_v1': (s, r, n) =>
        DepressiveTendencyReport(survey: s, responses: r, userNames: n),
    'anxiety_assessment_v1': (s, r, n) =>
        AnxietyAssessmentReport(survey: s, responses: r, userNames: n),
    'social_skill_v1': (s, r, n) =>
        SocialSkillReport(survey: s, responses: r, userNames: n),
    'exam_anxiety_coping_v1': (s, r, n) =>
        ExamAnxietyCopingReport(survey: s, responses: r, userNames: n),
    'academic_procrastination_v1': (s, r, n) =>
        AcademicProcrastinationReport(survey: s, responses: r, userNames: n),
    'test_taking_skills_v1': (s, r, n) =>
        TestTakingSkillsReport(survey: s, responses: r, userNames: n),
    'exam_prep_skills_v1': (s, r, n) =>
        ExamPrepSkillsReport(survey: s, responses: r, userNames: n),
    'post_exam_self_evaluation_v1': (s, r, n) =>
        PostExamSelfEvaluationReport(survey: s, responses: r, userNames: n),
    'learning_styles_3x2_v1': (s, r, n) =>
        LearningStylesReport(survey: s, responses: r, userNames: n),
    'school_adaptation_v1': (s, r, n) =>
        SchoolAdaptationReport(survey: s, responses: r, userNames: n),
    'attention_focus_v1': (s, r, n) =>
        AttentionFocusReport(survey: s, responses: r, userNames: n),
    'academic_resilience_v1': (s, r, n) =>
        AcademicResilienceReport(survey: s, responses: r, userNames: n),
    'academic_self_efficacy_v1': (s, r, n) =>
        AcademicSelfEfficacyReport(survey: s, responses: r, userNames: n),
    'academic_motivation_v1': (s, r, n) =>
        AcademicMotivationReport(survey: s, responses: r, userNames: n),
    'academic_emotional_responses_v1': (s, r, n) =>
        AcademicEmotionalResponsesReport(survey: s, responses: r, userNames: n),
    'academic_self_regulation_v1': (s, r, n) =>
        AcademicSelfRegulationReport(survey: s, responses: r, userNames: n),
    'exam_cognitive_processes_v1': (s, r, n) =>
        ExamCognitiveProcessesReport(survey: s, responses: r, userNames: n),
    'academic_motivation_sources_v1': (s, r, n) =>
        AcademicMotivationSourcesReport(survey: s, responses: r, userNames: n),
    'failure_perception_v1': (s, r, n) =>
        FailurePerceptionReport(survey: s, responses: r, userNames: n),
    'academic_self_efficacy_control_v1': (s, r, n) =>
        AcademicSelfEfficacyControlReport(
          survey: s,
          responses: r,
          userNames: n,
        ),
    'time_management_discipline_v1': (s, r, n) =>
        TimeManagementDisciplineReport(survey: s, responses: r, userNames: n),
    'academic_motivation_goal_v1': (s, r, n) =>
        AcademicMotivationGoalReport(survey: s, responses: r, userNames: n),
    'academic_resilience_grit_v1': (s, r, n) =>
        AcademicResilienceGritReport(survey: s, responses: r, userNames: n),
    'academic_anxiety_performance_v1': (s, r, n) =>
        AcademicAnxietyPerformanceReport(survey: s, responses: r, userNames: n),
    'self_regulation_management_v1': (s, r, n) =>
        SelfRegulationManagementReport(survey: s, responses: r, userNames: n),
    'academic_self_efficacy_confidence_v1': (s, r, n) =>
        AcademicSelfEfficacyConfidenceReport(
          survey: s,
          responses: r,
          userNames: n,
        ),
    'failure_fear_performance_obstacle_v1': (s, r, n) =>
        FailureFearPerformanceObstacleReport(
          survey: s,
          responses: r,
          userNames: n,
        ),
    'emotional_regulation_resilience_v1': (s, r, n) =>
        EmotionalRegulationResilienceReport(
          survey: s,
          responses: r,
          userNames: n,
        ),
  };

  bool _expanded = false;
  bool _loading = false;
  String? _error;
  Survey? _survey;
  List<Map<String, dynamic>> _responses = [];

  Future<void> _loadReport() async {
    final surveyId = (widget.data['surveyId'] ?? '').toString();
    if (surveyId.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = FirebaseFirestore.instance;
      final sDoc = await db.collection('surveys').doc(surveyId).get();
      if (!sDoc.exists) {
        throw Exception('Test tanımı bulunamadı.');
      }
      final survey = Survey.fromMap(sDoc.data()!, sDoc.id);
      final rSnap = await db
          .collection('survey_responses')
          .where('surveyId', isEqualTo: surveyId)
          .where('userId', isEqualTo: widget.studentId)
          .get();
      if (!mounted) return;
      setState(() {
        _survey = survey;
        _responses = rSnap.docs.map((d) => d.data()).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded && _survey == null && !_loading) {
      _loadReport();
    }
  }

  Color _levelColor(String summary) {
    final s = summary.toLowerCase();
    if (s.contains('çok yüksek') || s.contains('yüksek'))
      return Colors.deepOrange;
    if (s.contains('orta')) return Colors.amber.shade800;
    return Colors.green.shade700;
  }

  Widget _buildBody() {
    final hasSurvey = (widget.data['surveyId'] ?? '').toString().isNotEmpty;
    if (!hasSurvey) return _buildSimpleSummary();
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Rapor yüklenemedi: $_error',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
    final survey = _survey;
    if (survey == null) return const SizedBox.shrink();
    if (_responses.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Bu öğrenciye ait test cevabı bulunamadı.'),
      );
    }
    final builder = _builders[survey.guidanceTemplateId ?? ''];
    if (builder == null) return _buildSimpleSummary();
    return SizedBox(
      height: 900,
      child: ClipRect(
        child: builder(survey, _responses, {
          widget.studentId: widget.studentName,
        }),
      ),
    );
  }

  /// Rapor bileşeni olmayan / test tanımına bağlı olmayan kayıtlar için sade özet.
  Widget _buildSimpleSummary() {
    final summary = (widget.data['resultSummary'] ?? '-').toString();
    final score = widget.data['score'];
    final color = _levelColor(summary);
    final pct = score is num ? (score.toDouble() / 100).clamp(0.0, 1.0) : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Text(
            'Test Sonucu',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.indigo.shade900,
            ),
          ),
          const SizedBox(height: 8),
          Text(summary),
          if (pct != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 10,
                color: color,
                backgroundColor: Colors.grey.shade200,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Puan: ${score.toString()} / 100',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Değerlendirme: Sonuçlar rehber öğretmen tarafından incelenmiştir. Öğrencinin güçlü ve gelişime açık '
              'yönleri bireysel görüşmelerde ele alınır; veli ile paylaşılacak öneriler Görüşmeler sekmesinde izlenebilir.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final date = (widget.data['completedAt'] as Timestamp?)?.toDate();
    final title = (widget.data['testName'] ?? 'Rehberlik Testi').toString();
    final summary = (widget.data['resultSummary'] ?? 'Detay görüntüle')
        .toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.assignment_turned_in, color: Colors.teal),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Sonuç: $summary',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (date != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        DateFormat('dd.MM.yyyy').format(date),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.indigo.shade400,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? _buildBody()
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
