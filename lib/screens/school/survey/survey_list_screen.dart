import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/survey_model.dart';
import '../../../services/survey_service.dart';
import 'create_survey_screen.dart';
import 'survey_stats_screen.dart'; // Will create this later

class SurveyListScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;

  final bool isTeacher;
  final String? teacherId;

  const SurveyListScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.isTeacher = false,
    this.teacherId,
  }) : super(key: key);

  @override
  State<SurveyListScreen> createState() => _SurveyListScreenState();
}

class _SurveyListScreenState extends State<SurveyListScreen> {
  final SurveyService _surveyService = SurveyService();

  List<String> _classIds = [];
  bool _isInitLoading = false;

  @override
  void initState() {
    super.initState();
    _surveyService.checkScheduledSurveys(widget.institutionId);
    if (widget.isTeacher && widget.teacherId != null) {
      _loadTeacherClasses();
    }
  }

  Future<void> _loadTeacherClasses() async {
    setState(() => _isInitLoading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('teacherIds', arrayContains: widget.teacherId)
          .where('isActive', isEqualTo: true)
          .get();

      final ids = snap.docs
          .map((doc) => doc.data()['classId']?.toString())
          .whereType<String>()
          .toSet()
          .toList();

      if (mounted) {
        setState(() {
          _classIds = ids;
          _isInitLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading teacher classes for surveys: $e');
      if (mounted) setState(() => _isInitLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Anket İşlemleri'), centerTitle: false),
      body: Align(
        alignment: Alignment.topCenter,
        child: _isInitLoading
            ? const Center(child: CircularProgressIndicator())
            : ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: StreamBuilder<List<Survey>>(
                  stream: widget.isTeacher
                      ? _surveyService.getFilteredSurveys(
                          institutionId: widget.institutionId,
                          authorId: widget.teacherId,
                          targetedClassIds: _classIds,
                        )
                      : _surveyService.getSurveys(widget.institutionId),
                  builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Hata: ${snapshot.error}'));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final surveys = snapshot.data ?? [];

              if (surveys.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.poll_outlined,
                        size: 80,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Henüz anket oluşturulmamış',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _navigateToCreate(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Yeni Anket Oluştur'),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: surveys.length,
                itemBuilder: (context, index) {
                  final survey = surveys[index];
                  return _buildSurveyCard(context, survey);
                },
              );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToCreate(context),
        child: const Icon(Icons.add),
        tooltip: 'Yeni Anket',
      ),
    );
  }

  Widget _buildSurveyCard(BuildContext context, Survey survey) {
    Color statusColor;
    String statusText;

    switch (survey.status) {
      case SurveyStatus.draft:
        statusColor = Colors.orange;
        statusText = 'Taslak';
        break;
      case SurveyStatus.published:
        statusColor = Colors.green;
        statusText = 'Yayında';
        break;
      case SurveyStatus.closed:
        statusColor = Colors.red;
        statusText = 'Kapandı';
        break;
      case SurveyStatus.scheduled:
        statusColor = Colors.purple;
        statusText = 'Planlandı';
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SurveyStatsScreen(survey: survey),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      survey.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor.withOpacity(0.5)),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (survey.description.isNotEmpty)
                Text(
                  survey.description,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 16,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${survey.responseCount} Yanıt',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(survey.createdAt),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}.${date.month}.${date.year}';
  }

  void _navigateToCreate(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateSurveyScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          isTeacher: widget.isTeacher,
          teacherId: widget.teacherId,
        ),
      ),
    );
  }
}
