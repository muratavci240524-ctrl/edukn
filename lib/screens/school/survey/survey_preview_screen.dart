import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../models/survey_model.dart';
import '../../../services/survey_service.dart';
import '../../../services/announcement_service.dart';

class SurveyPreviewScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String title;
  final String description;
  final SurveyTargetType targetType;
  final List<String> targetIds;
  final Map<String, String> targetNames;
  final List<SurveySection> sections;
  final bool isAnonymous;
  final DateTime? scheduledAt;
  final String? authorId;

  const SurveyPreviewScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.title,
    required this.description,
    required this.targetType,
    required this.targetIds,
    required this.targetNames,
    required this.sections,
    this.isAnonymous = false,
    this.scheduledAt,
    this.authorId,
  }) : super(key: key);

  @override
  State<SurveyPreviewScreen> createState() => _SurveyPreviewScreenState();
}

class _SurveyPreviewScreenState extends State<SurveyPreviewScreen> {
  bool _isPublishing = false;
  int _currentStep = 0;

  void _nextStep() {
    setState(() {
      if (_currentStep < widget.sections.length - 1) {
        _currentStep++;
      } else {
        _publishSurvey();
      }
    });
  }

  void _prevStep() {
    setState(() {
      if (_currentStep > 0) _currentStep--;
    });
  }

  void _jumpToStep(int step) {
    setState(() => _currentStep = step);
  }

  @override
  Widget build(BuildContext context) {
    final isLastStep = _currentStep == widget.sections.length - 1;
    final currentSection = widget.sections[_currentStep];

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Anket Önizleme',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // STEP INDICATOR
            if (widget.sections.length > 1)
              Container(
                color: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.sections.length, (index) {
                    final isActive = index == _currentStep;
                    final isCompleted = index < _currentStep;

                    return GestureDetector(
                      onTap: () => _jumpToStep(index),
                      child: Container(
                        margin: EdgeInsets.symmetric(horizontal: 8),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isActive
                              ? Colors.indigo
                              : (isCompleted ? Colors.green : Colors.grey[300]),
                          border: isActive
                              ? null
                              : Border.all(color: Colors.grey[300]!),
                        ),
                        alignment: Alignment.center,
                        child: isCompleted
                            ? Icon(Icons.check, size: 16, color: Colors.white)
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: isActive
                                      ? Colors.white
                                      : Colors.grey[600],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    );
                  }),
                ),
              ),

            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        // Header Card (Only on Step 0)
                        if (_currentStep == 0)
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(24),
                            margin: EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border(
                                top: BorderSide(
                                  color: widget.scheduledAt != null
                                      ? Colors.purple
                                      : Colors.indigo,
                                  width: 6,
                                ),
                              ),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        widget.title,
                                        style: GoogleFonts.inter(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (widget.isAnonymous)
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[200],
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.visibility_off,
                                              size: 14,
                                              color: Colors.grey[700],
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              'Anonim',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[700],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                if (widget.description.isNotEmpty) ...[
                                  SizedBox(height: 12),
                                  Text(
                                    widget.description,
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ],
                                SizedBox(height: 16),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: 14,
                                      color: Colors.grey[500],
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Hedef Kitle: ${_getTargetLabel(widget.targetType)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                    if (widget.scheduledAt != null) ...[
                                      SizedBox(width: 16),
                                      Icon(
                                        Icons.calendar_today,
                                        size: 14,
                                        color: Colors.purple,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'Yayın: ${widget.scheduledAt!.day}/${widget.scheduledAt!.month} ${widget.scheduledAt!.hour}:${widget.scheduledAt!.minute.toString().padLeft(2, "0")}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.purple,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),

                        // Current Section
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.sections.length > 1 ||
                                currentSection.title.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: 12,
                                  left: 4,
                                ),
                                child: Text(
                                  currentSection.title,
                                  style: GoogleFonts.inter(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[800],
                                  ),
                                ),
                              ),
                            ...currentSection.questions
                                .map((q) => _buildQuestionCard(q))
                                .toList(),
                            SizedBox(height: 100), // Bottom sheet space
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomSheet: Container(
        color: Colors.white,
        padding: EdgeInsets.all(16),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: widget.sections.length == 1
                ? MainAxisAlignment.center
                : MainAxisAlignment.spaceBetween,
            children: [
              if (widget.sections.length > 1)
                if (_currentStep > 0)
                  TextButton.icon(
                    onPressed: _prevStep,
                    icon: Icon(Icons.arrow_back),
                    label: Text('Geri'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey[700],
                      textStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  SizedBox(width: 80),

              ElevatedButton(
                onPressed: _isPublishing ? null : _nextStep,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isLastStep
                      ? (widget.scheduledAt != null
                            ? Colors.purple
                            : Colors.green)
                      : Colors.indigo,
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isPublishing
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Row(
                        children: [
                          Text(
                            isLastStep
                                ? (widget.scheduledAt != null
                                      ? 'PLANLA'
                                      : 'YAYINLA')
                                : 'İLERİ',
                          ),
                          if (!isLastStep) ...[
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward, size: 18),
                          ],
                          if (isLastStep) ...[
                            SizedBox(width: 8),
                            Icon(
                              widget.scheduledAt != null
                                  ? Icons.schedule
                                  : Icons.send,
                              size: 18,
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionCard(SurveyQuestion q) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  q.text,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (q.isRequired)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Text(
                    '*',
                    style: TextStyle(color: Colors.red, fontSize: 16),
                  ),
                ),
            ],
          ),
          SizedBox(height: 16),
          _buildQuestionInput(q),
        ],
      ),
    );
  }

  Widget _buildQuestionInput(SurveyQuestion q) {
    switch (q.type) {
      case SurveyQuestionType.text:
        return TextField(
          enabled: false,
          decoration: InputDecoration(
            hintText: 'Kısa yanıtınız',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            filled: true,
            fillColor: Colors.grey[50],
          ),
        );
      case SurveyQuestionType.longText:
        return TextField(
          enabled: false,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Uzun yanıtınız',
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.grey[50],
          ),
        );
      case SurveyQuestionType.singleChoice:
        return Column(
          children: q.options
              .map(
                (o) => RadioListTile<String>(
                  title: Text(o),
                  value: o,
                  groupValue: null,
                  onChanged: null,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              )
              .toList(),
        );
      case SurveyQuestionType.multipleChoice:
        return Column(
          children: q.options
              .map(
                (o) => CheckboxListTile(
                  title: Text(o),
                  value: false,
                  onChanged: null,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              )
              .toList(),
        );
      case SurveyQuestionType.rating:
        return Row(
          children: List.generate(
            5,
            (index) => Icon(Icons.star_border, color: Colors.amber, size: 30),
          ),
        );
      case SurveyQuestionType.date:
        return OutlinedButton.icon(
          onPressed: null,
          icon: Icon(Icons.calendar_today),
          label: Text('Tarih Seçiniz'),
        );
      case SurveyQuestionType.ranking:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Her seçenek için öncelik sırası belirleyin:',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
            SizedBox(height: 12),
            ...q.options.map((option) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(option, style: TextStyle(fontSize: 14)),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<int>(
                        value: null,
                        decoration: InputDecoration(
                          labelText: 'Öncelik',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        items: [
                          DropdownMenuItem<int>(
                            value: null,
                            child: Text('Seçiniz'),
                          ),
                        ],
                        onChanged: null,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        );
    }
  }

  String _getTargetLabel(SurveyTargetType type) {
    switch (type) {
      case SurveyTargetType.all:
        return 'Herkes';
      case SurveyTargetType.students:
        return 'Öğrenciler';
      case SurveyTargetType.teachers:
        return 'Öğretmenler';
      case SurveyTargetType.parents:
        return 'Veliler';
      case SurveyTargetType.specific_classes:
        return 'Belirli Sınıflar';
    }
  }

  Future<void> _publishSurvey() async {
    setState(() => _isPublishing = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final survey = Survey(
        id: '',
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
        title: widget.title,
        description: widget.description,
        authorId: widget.authorId ?? user?.uid ?? '',
        createdAt: DateTime.now(),
        status: widget.scheduledAt != null
            ? SurveyStatus.scheduled
            : SurveyStatus.published,
        scheduledAt: widget.scheduledAt,
        targetType: widget.targetType,
        targetIds: widget.targetIds,
        targetNames: widget.targetNames.values.toList(),
        sections: widget.sections,
        isAnonymous: widget.isAnonymous,
      );

      final surveyService = SurveyService();
      final id = await surveyService.createSurvey(survey);

      // Determine recipients logic
      List<String> recipients = widget.targetIds;
      final annService = AnnouncementService();

      if (recipients.isEmpty) {
        final allUsers = await annService.getAllUsers();
        if (widget.targetType == SurveyTargetType.all) {
          recipients = allUsers.map((u) => u['id'].toString()).toList();
        } else if (widget.targetType == SurveyTargetType.teachers) {
          recipients = allUsers
              .where((u) => u['role'] == 'Öğretmen')
              .map((u) => u['id'].toString())
              .toList();
        } else if (widget.targetType == SurveyTargetType.students) {
          recipients = allUsers
              .where((u) => u['role'] == 'Öğrenci')
              .map((u) => u['id'].toString())
              .toList();
        } else if (widget.targetType == SurveyTargetType.parents) {
          recipients = allUsers
              .where((u) => u['role'] == 'Veli')
              .map((u) => u['id'].toString())
              .toList();
        }
      }

      await surveyService.publishSurvey(id, recipients);

      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  widget.scheduledAt != null
                      ? Icons.schedule
                      : Icons.check_circle,
                  color: Colors.white,
                ),
                SizedBox(width: 8),
                Text(
                  widget.scheduledAt != null
                      ? 'Anket planlandı!'
                      : 'Anket başarıyla yayınlandı!',
                ),
              ],
            ),
            backgroundColor: widget.scheduledAt != null
                ? Colors.purple
                : Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata oluştu: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }
}
