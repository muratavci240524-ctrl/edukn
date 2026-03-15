import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/survey_model.dart';
import 'survey_preview_screen.dart';
import '../../../widgets/recipient_selector_field.dart'; // Correct import

class CreateSurveyScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  final Survey? templateSurvey;

  const CreateSurveyScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    this.templateSurvey,
  }) : super(key: key);

  @override
  State<CreateSurveyScreen> createState() => _CreateSurveyScreenState();
}

class _CreateSurveyScreenState extends State<CreateSurveyScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  SurveyTargetType _targetType = SurveyTargetType.all;
  List<String> _selectedRecipients = [];
  Map<String, String> _recipientNames = {};

  // Section management
  List<SurveySection> _sections = [];

  bool _isAnonymous = false;
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;

  @override
  void initState() {
    super.initState();
    if (widget.templateSurvey != null) {
      _loadFromTemplate(widget.templateSurvey!);
    } else {
      // Initialize with one default section
      _sections.add(
        SurveySection(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: 'Bölüm 1',
          questions: [],
        ),
      );
    }
  }

  void _loadFromTemplate(Survey template) {
    _titleController.text = template.title + ' (Kopya)';
    _descController.text = template.description;
    _targetType = template.targetType;
    _isAnonymous = template.isAnonymous;

    // Deep copy sections with new IDs to be safe
    _sections = template.sections.map((s) {
      return SurveySection(
        id:
            DateTime.now().millisecondsSinceEpoch.toString() +
            '_' +
            s.id.substring(0, 3),
        title: s.title,
        description: s.description,
        questions: s.questions
            .map(
              (q) => SurveyQuestion(
                id:
                    DateTime.now().millisecondsSinceEpoch.toString() +
                    '_' +
                    q.id.substring(0, 3),
                text: q.text,
                type: q.type,
                options: List.from(q.options),
                isRequired: q.isRequired,
                mediaUrl: q.mediaUrl,
              ),
            )
            .toList(),
      );
    }).toList();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (time == null) return;

    setState(() {
      _scheduledDate = date;
      _scheduledTime = time;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Yeni Anket Oluştur',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: TextButton.icon(
              onPressed: _openPreview,
              icon: Icon(Icons.remove_red_eye_outlined, size: 20),
              label: Text('Önizle'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.indigo,
                textStyle: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                // Top Card: General Info
                _buildInfoCard(),
                SizedBox(height: 24),

                // Sections List
                ..._sections.asMap().entries.map((entry) {
                  final index = entry.key;
                  final section = entry.value;
                  return _buildSectionCard(index, section);
                }).toList(),

                SizedBox(height: 16),

                // Add Section Button
                OutlinedButton.icon(
                  onPressed: _addSection,
                  icon: Icon(Icons.add_circle_outline),
                  label: Text('Yeni Bölüm Ekle'),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Genel Bilgiler',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          SizedBox(height: 16),
          TextFormField(
            controller: _titleController,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.indigo.shade900,
            ),
            decoration: InputDecoration(
              labelText: 'Anket Başlığı',
              labelStyle: TextStyle(color: Colors.indigo.shade300),
              hintText: 'Örn: Okul Memnuniyet Anketi',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.indigo.shade100),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.indigo.shade50),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.indigo, width: 2),
              ),
              filled: true,
              fillColor: Colors.indigo.withOpacity(0.02),
              prefixIcon: Icon(Icons.title, color: Colors.indigo.shade300),
            ),
          ),
          SizedBox(height: 16),
          TextFormField(
            controller: _descController,
            maxLines: 2,
            style: GoogleFonts.inter(fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Anket Açıklaması',
              labelStyle: TextStyle(color: Colors.indigo.shade300),
              hintText: 'Anketin amacı ve içeriği hakkında kısa bilgi...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.indigo.shade100),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.indigo.shade50),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.indigo, width: 2),
              ),
              filled: true,
              fillColor: Colors.indigo.withOpacity(0.02),
              prefixIcon: Icon(
                Icons.description,
                color: Colors.indigo.shade300,
              ),
            ),
          ),
          SizedBox(height: 20),
          Divider(color: Colors.indigo.withOpacity(0.1)),
          SizedBox(height: 20),
          RecipientSelectorField(
            selectedRecipients: _selectedRecipients,
            recipientNames: _recipientNames,
            schoolTypeId: widget.schoolTypeId,
            onChanged: (ids, names) {
              setState(() {
                _selectedRecipients = ids;
                _recipientNames = names;
                // Update targetType based on selection if needed,
                // but usually the selector handles specific logic.
                if (ids.isEmpty) {
                  _targetType = SurveyTargetType.all;
                } else {
                  _targetType = SurveyTargetType.specific_classes; // Or similar
                }
              });
            },
          ),
          SizedBox(height: 16),

          SwitchListTile(
            title: Text('Anonim Anket'),
            subtitle: Text('Katılımcı isimleri gizli tutulacak'),
            value: _isAnonymous,
            onChanged: (val) => setState(() => _isAnonymous = val),
            contentPadding: EdgeInsets.zero,
          ),

          Divider(),

          ListTile(
            title: Text('Yayınlanma Tarihi'),
            subtitle: Text(
              _scheduledDate == null
                  ? 'Hemen yayınla'
                  : '${_scheduledDate!.day}/${_scheduledDate!.month}/${_scheduledDate!.year} ${_scheduledTime!.format(context)}',
            ),
            trailing: Icon(Icons.calendar_today),
            contentPadding: EdgeInsets.zero,
            onTap: _pickDateTime,
          ),
          if (_scheduledDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: TextButton(
                onPressed: () => setState(() {
                  _scheduledDate = null;
                  _scheduledTime = null;
                }),
                child: Text(
                  'Tarihi Temizle (Hemen Yayınla)',
                  style: TextStyle(color: Colors.red),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(int index, SurveySection section) {
    return Container(
      margin: EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Section Header
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_open, color: Colors.blue.shade700),
                SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    initialValue: section.title,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade900,
                    ),
                    decoration: InputDecoration.collapsed(
                      hintText: 'Bölüm Başlığı',
                    ),
                    onChanged: (v) => section = SurveySection(
                      id: section.id,
                      title: v,
                      description: section.description,
                      questions: section.questions,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.copy, size: 20, color: Colors.blue.shade400),
                  tooltip: 'Bölümü Çoğalt',
                  onPressed: () => _duplicateSection(index),
                ),
                if (_sections.length > 1)
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: Colors.red.shade400,
                    ),
                    tooltip: 'Bölümü Sil',
                    onPressed: () => _deleteSection(index),
                  ),
              ],
            ),
          ),

          // Questions List
          if (section.questions.isEmpty)
            Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.quiz_outlined,
                      size: 48,
                      color: Colors.grey.shade300,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Bu bölümde henüz soru yok',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              padding: EdgeInsets.all(16),
              itemCount: section.questions.length,
              separatorBuilder: (ctx, i) => SizedBox(height: 16),
              itemBuilder: (ctx, qIndex) {
                final question = section.questions[qIndex];
                return _buildQuestionItem(
                  index,
                  qIndex,
                  question,
                  section.questions.length,
                );
              },
            ),

          Divider(height: 1),

          // Add Question Button
          InkWell(
            onTap: () => _showAddQuestionDialog(index),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 16),
              width: double.infinity,
              alignment: Alignment.center,
              child: Text(
                '+ Soru Ekle',
                style: TextStyle(
                  color: Colors.blue.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionItem(
    int sectionIndex,
    int questionIndex,
    SurveyQuestion question,
    int totalQuestions,
  ) {
    IconData typeIcon;
    switch (question.type) {
      case SurveyQuestionType.text:
        typeIcon = Icons.short_text;
        break;
      case SurveyQuestionType.longText:
        typeIcon = Icons.notes;
        break;
      case SurveyQuestionType.singleChoice:
        typeIcon = Icons.radio_button_checked;
        break;
      case SurveyQuestionType.multipleChoice:
        typeIcon = Icons.check_box;
        break;
      case SurveyQuestionType.rating:
        typeIcon = Icons.star_outline;
        break;
      case SurveyQuestionType.date:
        typeIcon = Icons.calendar_today;
        break;
      case SurveyQuestionType.ranking:
        typeIcon = Icons.format_list_numbered;
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.indigo.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Action icons in a top row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.indigo.withOpacity(0.03),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(typeIcon, size: 16, color: Colors.indigo.shade300),
                const SizedBox(width: 8),
                Text(
                  _getTypeLabel(question.type),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.indigo.shade300,
                  ),
                ),
                const Spacer(),
                // Move arrows
                IconButton(
                  icon: Icon(
                    Icons.keyboard_arrow_up,
                    size: 20,
                    color: Colors.indigo.shade400,
                  ),
                  onPressed: questionIndex > 0
                      ? () => _moveQuestion(sectionIndex, questionIndex, -1)
                      : null,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 18,
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    size: 20,
                    color: Colors.indigo.shade400,
                  ),
                  onPressed: questionIndex < totalQuestions - 1
                      ? () => _moveQuestion(sectionIndex, questionIndex, 1)
                      : null,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 18,
                ),
                const SizedBox(width: 12),
                const VerticalDivider(width: 1),
                const SizedBox(width: 12),
                // Actions
                IconButton(
                  icon: Icon(
                    Icons.content_copy,
                    size: 18,
                    color: Colors.indigo.shade400,
                  ),
                  onPressed: () =>
                      _duplicateQuestion(sectionIndex, questionIndex),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 18,
                  tooltip: 'Çoğalt',
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: Colors.blue.shade400,
                  ),
                  onPressed: () => _editQuestion(sectionIndex, questionIndex),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 18,
                  tooltip: 'Düzenle',
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: Colors.red.shade400,
                  ),
                  onPressed: () => _deleteQuestion(sectionIndex, questionIndex),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 18,
                  tooltip: 'Sil',
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  question.text,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: Colors.indigo.shade900,
                  ),
                ),
                if (question.options.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: question.options
                          .map(
                            (o) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.indigo.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                o,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.indigo.shade700,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _getStaticTypeLabel(SurveyQuestionType type) {
    switch (type) {
      case SurveyQuestionType.text:
        return 'Kısa Yanıt';
      case SurveyQuestionType.longText:
        return 'Uzun Yanıt';
      case SurveyQuestionType.singleChoice:
        return 'Tek Seçimli';
      case SurveyQuestionType.multipleChoice:
        return 'Çok Seçimli';
      case SurveyQuestionType.rating:
        return 'Puanlama';
      case SurveyQuestionType.date:
        return 'Tarih';
      case SurveyQuestionType.ranking:
        return 'Sıralama (Öncelik)';
    }
  }

  String _getTypeLabel(SurveyQuestionType type) => _getStaticTypeLabel(type);

  // LOGIC METHODS

  void _addSection() {
    setState(() {
      _sections.add(
        SurveySection(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: 'Bölüm ${_sections.length + 1}',
          questions: [],
        ),
      );
    });
  }

  void _deleteSection(int index) {
    setState(() {
      _sections.removeAt(index);
    });
  }

  void _duplicateSection(int index) {
    final original = _sections[index];
    final sectionId = '${DateTime.now().millisecondsSinceEpoch}_${index}_copy';

    final copy = SurveySection(
      id: sectionId,
      title: '${original.title} (Kopya)',
      description: original.description,
      questions: original.questions.asMap().entries.map((entry) {
        final i = entry.key;
        final q = entry.value;
        return SurveyQuestion(
          // Ensure extremely unique ID
          id: '${sectionId}_q${i}_${DateTime.now().microsecondsSinceEpoch}',
          text: q.text,
          type: q.type,
          options: List.from(q.options),
          isRequired: q.isRequired,
          mediaUrl: q.mediaUrl,
        );
      }).toList(),
    );

    setState(() {
      _sections.insert(index + 1, copy);
    });
  }

  void _moveQuestion(int sectionIndex, int questionIndex, int direction) {
    setState(() {
      final questions = _sections[sectionIndex].questions;
      final newIndex = questionIndex + direction;

      if (newIndex >= 0 && newIndex < questions.length) {
        final item = questions.removeAt(questionIndex);
        questions.insert(newIndex, item);
      }
    });
  }

  void _duplicateQuestion(int sectionIndex, int questionIndex) {
    final original = _sections[sectionIndex].questions[questionIndex];
    final copy = SurveyQuestion(
      id: '${DateTime.now().microsecondsSinceEpoch}_copy',
      text: '${original.text} (Kopya)',
      type: original.type,
      options: List.from(original.options),
      isRequired: original.isRequired,
      mediaUrl: original.mediaUrl,
    );

    setState(() {
      _sections[sectionIndex].questions.insert(questionIndex + 1, copy);
    });
  }

  void _deleteQuestion(int sectionIndex, int questionIndex) {
    setState(() {
      _sections[sectionIndex].questions.removeAt(questionIndex);
    });
  }

  void _showAddQuestionDialog(
    int sectionIndex, {
    SurveyQuestion? existingQuestion,
    int? editIndex,
  }) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => QuestionEditorPage(
            isEditing: existingQuestion != null,
            existingQuestion: existingQuestion,
            onSaved: (question) {
              setState(() {
                if (editIndex != null) {
                  _sections[sectionIndex].questions[editIndex] = question;
                } else {
                  _sections[sectionIndex].questions.add(question);
                }
              });
            },
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: QuestionEditor(
              isEditing: existingQuestion != null,
              existingQuestion: existingQuestion,
              onSaved: (question) {
                setState(() {
                  if (editIndex != null) {
                    _sections[sectionIndex].questions[editIndex] = question;
                  } else {
                    _sections[sectionIndex].questions.add(question);
                  }
                });
                Navigator.pop(ctx);
              },
              onCancel: () => Navigator.pop(ctx),
            ),
          ),
        ),
      );
    }
  }

  void _editQuestion(int sectionIndex, int questionIndex) {
    _showAddQuestionDialog(
      sectionIndex,
      existingQuestion: _sections[sectionIndex].questions[questionIndex],
      editIndex: questionIndex,
    );
  }

  void _openPreview() {
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lütfen anket başlığı giriniz')));
      return;
    }

    // Check if any section has questions
    bool hasQuestions = _sections.any((s) => s.questions.isNotEmpty);
    if (!hasQuestions) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lütfen en az bir soru ekleyiniz')),
      );
      return;
    }

    DateTime? scheduledInfo;
    if (_scheduledDate != null && _scheduledTime != null) {
      scheduledInfo = DateTime(
        _scheduledDate!.year,
        _scheduledDate!.month,
        _scheduledDate!.day,
        _scheduledTime!.hour,
        _scheduledTime!.minute,
      );
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SurveyPreviewScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          title: _titleController.text,
          description: _descController.text,
          targetType: _targetType,
          targetIds: _selectedRecipients,
          targetNames: _recipientNames,
          sections: _sections,
          isAnonymous: _isAnonymous,
          scheduledAt: scheduledInfo,
        ),
      ),
    );
  }
}

class QuestionEditorPage extends StatelessWidget {
  final bool isEditing;
  final SurveyQuestion? existingQuestion;
  final Function(SurveyQuestion) onSaved;

  const QuestionEditorPage({
    super.key,
    required this.isEditing,
    this.existingQuestion,
    required this.onSaved,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          isEditing ? 'Soruyu Düzenle' : 'Yeni Soru Ekle',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.indigo,
        elevation: 0,
      ),
      body: QuestionEditor(
        isEditing: isEditing,
        existingQuestion: existingQuestion,
        onSaved: (question) {
          onSaved(question);
          Navigator.pop(context);
        },
      ),
    );
  }
}

class QuestionEditor extends StatefulWidget {
  final bool isEditing;
  final SurveyQuestion? existingQuestion;
  final Function(SurveyQuestion) onSaved;
  final VoidCallback? onCancel;

  const QuestionEditor({
    super.key,
    required this.isEditing,
    this.existingQuestion,
    required this.onSaved,
    this.onCancel,
  });

  @override
  State<QuestionEditor> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends State<QuestionEditor> {
  late TextEditingController textCtrl;
  late TextEditingController optionsCtrl;
  late SurveyQuestionType type;
  late bool isRequired;

  @override
  void initState() {
    super.initState();
    textCtrl = TextEditingController(
      text: widget.isEditing ? widget.existingQuestion!.text : '',
    );
    optionsCtrl = TextEditingController(
      text: widget.isEditing ? widget.existingQuestion!.options.join(', ') : '',
    );
    type = widget.isEditing
        ? widget.existingQuestion!.type
        : SurveyQuestionType.singleChoice;
    isRequired = widget.isEditing ? widget.existingQuestion!.isRequired : false;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.onCancel != null) // Only show header in dialog mode
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.quiz, color: Colors.indigo),
                ),
                const SizedBox(width: 16),
                Text(
                  widget.isEditing ? 'Soruyu Düzenle' : 'Yeni Soru Ekle',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade900,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          if (widget.onCancel != null) const SizedBox(height: 24),

          Row(
            children: [
              Text(
                'Soru Metni',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.indigo.shade700,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => setState(() => isRequired = !isRequired),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: isRequired,
                          onChanged: (v) =>
                              setState(() => isRequired = v ?? false),
                          activeColor: Colors.indigo,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Zorunlu Sorun',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.indigo.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: textCtrl,
            style: GoogleFonts.inter(fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Sorunuzu buraya yazın...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.indigo.shade100),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.indigo, width: 2),
              ),
              filled: true,
              fillColor: Colors.indigo.withOpacity(0.02),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 24),
          Text(
            'Soru Tipi',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.indigo.shade700,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.indigo.withOpacity(0.02),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.indigo.shade100),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButtonFormField<SurveyQuestionType>(
                value: type,
                isExpanded: true,
                elevation: 8,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.indigo,
                ),
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(12),
                menuMaxHeight: 400,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: InputBorder.none,
                ),
                style: GoogleFonts.inter(
                  color: Colors.indigo.shade900,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                alignment: AlignmentDirectional.centerStart,
                items: SurveyQuestionType.values.map((e) {
                  return DropdownMenuItem(
                    value: e,
                    child: Text(
                      _CreateSurveyScreenState._getStaticTypeLabel(e),
                    ),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => type = v);
                },
              ),
            ),
          ),
          if (type == SurveyQuestionType.singleChoice ||
              type == SurveyQuestionType.multipleChoice) ...[
            const SizedBox(height: 24),
            Text(
              'Seçenekler',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.indigo.shade700,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: optionsCtrl,
              style: GoogleFonts.inter(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Evet, Hayır, Belki...',
                helperText: 'Seçenekleri virgülle ayırarak giriniz.',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.indigo.shade100),
                ),
                filled: true,
                fillColor: Colors.indigo.withOpacity(0.02),
              ),
              maxLines: 2,
            ),
          ],
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () {
                if (textCtrl.text.isEmpty) return;

                final options = optionsCtrl.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();

                final question = SurveyQuestion(
                  id: widget.isEditing
                      ? widget.existingQuestion!.id
                      : DateTime.now().millisecondsSinceEpoch.toString(),
                  text: textCtrl.text,
                  type: type,
                  options: options,
                  isRequired: isRequired,
                );

                widget.onSaved(question);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Text(
                widget.isEditing ? 'Güncelle' : 'Soru Ekle',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
