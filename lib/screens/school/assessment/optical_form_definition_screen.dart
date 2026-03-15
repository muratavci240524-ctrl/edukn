import 'package:flutter/material.dart';
import '../../../../models/assessment/exam_type_model.dart';
import '../../../../models/assessment/optical_form_model.dart';
import '../../../../services/assessment_service.dart';

class OpticalFormDefinition extends StatefulWidget {
  final String institutionId;
  final OpticalForm? opticalForm;
  final VoidCallback onSuccess;

  const OpticalFormDefinition({
    Key? key,
    required this.institutionId,
    this.opticalForm,
    required this.onSuccess,
  }) : super(key: key);

  @override
  State<OpticalFormDefinition> createState() => _OpticalFormDefinitionState();
}

class _OpticalFormDefinitionState extends State<OpticalFormDefinition> {
  final _formKey = GlobalKey<FormState>();
  final _service = AssessmentService();

  late TextEditingController _nameController;

  String? _selectedExamTypeId;
  String _selectedExamTypeName = '';
  List<ExamType> _examTypes = [];
  bool _isLoading = false;

  final Map<String, OpticalField> _standardFields = {
    'studentNo': OpticalField.empty(),
    'studentName': OpticalField.empty(),
    'identityNo': OpticalField.empty(),
    'classLevel': OpticalField.empty(),
    'branch': OpticalField.empty(),
    'institutionCode': OpticalField.empty(),
    'session': OpticalField.empty(),
    'bookletType': OpticalField.empty(),
  };

  final Map<String, String> _standardLabels = {
    'studentNo': 'Öğrenci No',
    'studentName': 'Ad Soyad',
    'identityNo': 'TC Kimlik / Tel No',
    'classLevel': 'Sınıf Seviyesi',
    'branch': 'Şube',
    'institutionCode': 'Kurum Kodu',
    'session': 'Oturum',
    'bookletType': 'Kitapçık Türü',
  };

  final Map<String, IconData> _standardIcons = {
    'studentNo': Icons.onetwothree,
    'studentName': Icons.abc,
    'identityNo': Icons.perm_identity,
    'classLevel': Icons.grade,
    'branch': Icons.class_,
    'institutionCode': Icons.business,
    'session': Icons.timer,
    'bookletType': Icons.book,
  };

  Map<String, OpticalField> _subjectFields = {};

  @override
  void initState() {
    super.initState();
    _initForm();
    _loadExamTypes();
  }

  @override
  void didUpdateWidget(covariant OpticalFormDefinition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.opticalForm?.id != widget.opticalForm?.id) {
      _initForm();
    }
  }

  void _initForm() {
    _nameController = TextEditingController(
      text: widget.opticalForm?.name ?? '',
    );

    if (widget.opticalForm != null) {
      _selectedExamTypeId = widget.opticalForm!.examTypeId;
      _selectedExamTypeName = widget.opticalForm!.examTypeName;

      _standardFields['studentNo'] = widget.opticalForm!.studentNo;
      _standardFields['studentName'] = widget.opticalForm!.studentNameField;
      _standardFields['identityNo'] = widget.opticalForm!.identityNo;
      _standardFields['classLevel'] = widget.opticalForm!.classLevel;
      _standardFields['branch'] = widget.opticalForm!.branch;
      _standardFields['institutionCode'] = widget.opticalForm!.institutionCode;
      _standardFields['session'] = widget.opticalForm!.session;
      _standardFields['bookletType'] = widget.opticalForm!.bookletType;

      _subjectFields = Map.from(widget.opticalForm!.subjectFields);
    } else {
      _selectedExamTypeId = null;
      _selectedExamTypeName = '';
      _subjectFields.clear();
      _standardFields.updateAll((key, value) => OpticalField.empty());
    }
  }

  Future<void> _loadExamTypes() async {
    _service.getExamTypes(widget.institutionId).listen((types) {
      if (mounted) {
        setState(() {
          _examTypes = types;
        });
      }
    });
  }

  void _onExamTypeChanged(String? typeId) {
    if (typeId == null) return;
    final type = _examTypes.firstWhere((e) => e.id == typeId);

    setState(() {
      _selectedExamTypeId = typeId;
      _selectedExamTypeName = type.name;

      final newMap = <String, OpticalField>{};
      for (var subject in type.subjects) {
        // Initialize with default length from question count if possible, OR 0
        // BUT user asked for auto-calc on start entry, so for now just init empty or preserve
        final existing = _subjectFields[subject.branchName];
        if (existing != null) {
          newMap[subject.branchName] = existing;
        } else {
          // Initialize length = question count by default
          newMap[subject.branchName] = OpticalField(
            start: 0,
            length: subject.questionCount,
          );
        }
      }
      _subjectFields = newMap;
    });
  }

  void _updateStandardField(String key, {int? start, int? length}) {
    final old = _standardFields[key] ?? OpticalField.empty();
    setState(() {
      _standardFields[key] = OpticalField(
        start: start ?? old.start,
        length: length ?? old.length,
      );
    });
  }

  void _updateSubjectField(String key, {int? start, int? length}) {
    final old = _subjectFields[key] ?? OpticalField.empty();
    setState(() {
      _subjectFields[key] = OpticalField(
        start: start ?? old.start,
        length: length ?? old.length,
      );
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedExamTypeId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sınav türü seçmelisiniz.')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final form = OpticalForm(
        id: widget.opticalForm?.id ?? '',
        institutionId: widget.institutionId,
        name: _nameController.text.trim(),
        examTypeId: _selectedExamTypeId!,
        examTypeName: _selectedExamTypeName,
        studentNo: _standardFields['studentNo']!,
        studentNameField: _standardFields['studentName']!,
        identityNo: _standardFields['identityNo']!,
        classLevel: _standardFields['classLevel']!,
        branch: _standardFields['branch']!,
        institutionCode: _standardFields['institutionCode']!,
        session: _standardFields['session']!,
        bookletType: _standardFields['bookletType']!,
        subjectFields: _subjectFields,
      );

      await _service.saveOpticalForm(form);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Optik Form Kaydedildi.')));
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- Helper to get ordered subject fields with question counts
  List<_SubjectFieldData> _getOrderedSubjectFields() {
    final examType = _examTypes.firstWhere(
      (e) => e.id == _selectedExamTypeId,
      orElse: () => ExamType(
        id: '',
        institutionId: '',
        name: '',
        baseScore: 0,
        maxScore: 0,
        wrongCorrectRatio: 0,
        optionCount: 0,
        subjects: [],
      ),
    );

    if (examType.id.isNotEmpty && examType.subjects.isNotEmpty) {
      final List<_SubjectFieldData> ordered = [];
      for (var subject in examType.subjects) {
        if (_subjectFields.containsKey(subject.branchName)) {
          ordered.add(
            _SubjectFieldData(
              label: subject.branchName,
              field: _subjectFields[subject.branchName]!,
              icon: Icons.book,
              defaultQuestionCount: subject.questionCount,
            ),
          );
        }
      }
      return ordered;
    }

    return _subjectFields.entries
        .map(
          (entry) => _SubjectFieldData(
            label: entry.key,
            field: entry.value,
            icon: Icons.book,
            defaultQuestionCount: 0,
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _save,
                        icon: Icon(Icons.save),
                        label: Text('KAYDET'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  _buildBasicInfoCard(),
                  SizedBox(height: 16),
                  _buildSectionTitle(
                    'Parametre Alanları',
                    Icons.settings_input_component,
                  ),
                  _buildStandardFieldsCard(),

                  if (_selectedExamTypeId != null) ...[
                    SizedBox(height: 24),
                    _buildSectionTitle('Ders Alanları', Icons.library_books),
                    _buildSubjectFieldsCard(),
                  ],
                  SizedBox(height: 48),
                ],
              ),
            ),
          );
  }

  Widget _buildBasicInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.description, color: Colors.indigo),
                SizedBox(width: 8),
                Text(
                  'Temel Bilgiler',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Divider(height: 24),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Optik Form Adı',
                hintText: 'Örn: FMV LGS Formu',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: Icon(Icons.title),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              validator: (v) => v!.isEmpty ? 'Zorunlu' : null,
            ),
            SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedExamTypeId,
              decoration: InputDecoration(
                labelText: 'Uygulanacak Sınav Türü',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: Icon(Icons.assignment),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              items: _examTypes
                  .map(
                    (e) => DropdownMenuItem(value: e.id, child: Text(e.name)),
                  )
                  .toList(),
              onChanged: _onExamTypeChanged,
              validator: (v) => v == null ? 'Zorunlu' : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.indigo, size: 20),
          SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
          ),
        ],
      ),
    );
  }

  // --- Specific builder for STANDARD fields (no auto-calc)
  Widget _buildStandardFieldsCard() {
    final fields = _standardLabels.entries
        .map(
          (entry) => MapEntry(
            entry.key,
            _FieldData(
              entry.value,
              _standardFields[entry.key]!,
              _standardIcons[entry.key],
            ),
          ),
        )
        .toList();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: fields.map((entry) {
            return Column(
              children: [
                OpticalFieldEditor(
                  label: entry.value.label,
                  field: entry.value.field,
                  icon: entry.value.icon,
                  onChanged: (s, l) =>
                      _updateStandardField(entry.key, start: s, length: l),
                  isSubject: false,
                ),
                if (entry.key != fields.last.key) Divider(height: 24),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // --- Specific builder for SUBJECT fields (with auto-calc)
  Widget _buildSubjectFieldsCard() {
    final fields = _getOrderedSubjectFields();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: fields.map((data) {
            return Column(
              children: [
                OpticalFieldEditor(
                  label: data.label,
                  field: data.field,
                  icon: data.icon,
                  defaultQuestionCount: data.defaultQuestionCount,
                  isSubject: true,
                  onChanged: (s, l) =>
                      _updateSubjectField(data.label, start: s, length: l),
                ),
                if (data.label != fields.last.label) Divider(height: 24),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // No changes to _FieldData and _SubjectFieldData classes here, they are fine.
}

class _FieldData {
  final String label;
  final OpticalField field;
  final IconData? icon;
  _FieldData(this.label, this.field, this.icon);
}

class _SubjectFieldData {
  final String label;
  final OpticalField field;
  final IconData? icon;
  final int defaultQuestionCount;
  _SubjectFieldData({
    required this.label,
    required this.field,
    this.icon,
    required this.defaultQuestionCount,
  });
}

class OpticalFieldEditor extends StatefulWidget {
  final String label;
  final OpticalField field;
  final IconData? icon;
  final Function(int?, int?) onChanged;
  final bool isSubject;
  final int defaultQuestionCount;

  const OpticalFieldEditor({
    Key? key,
    required this.label,
    required this.field,
    required this.onChanged,
    this.icon,
    this.isSubject = false,
    this.defaultQuestionCount = 0,
  }) : super(key: key);

  @override
  State<OpticalFieldEditor> createState() => _OpticalFieldEditorState();
}

class _OpticalFieldEditorState extends State<OpticalFieldEditor> {
  late TextEditingController _startController;
  late TextEditingController _lengthController;

  @override
  void initState() {
    super.initState();
    _startController = TextEditingController(
      text: widget.field.start == 0 ? '' : widget.field.start.toString(),
    );
    _lengthController = TextEditingController(
      text: widget.field.length == 0 ? '' : widget.field.length.toString(),
    );
  }

  @override
  void didUpdateWidget(covariant OpticalFieldEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update controllers if external values changed and mismatch (e.g. navigation or auto-calc)
    // We strictly check integer values to avoid overwriting "1.0" or similar text formatting if any
    final currentStart = int.tryParse(_startController.text) ?? 0;
    if (widget.field.start != currentStart) {
      // Only update if significantly different (e.g. not just typing '01' vs '1'?)
      // Actually, for integer fields, straightforward comparison is usually safe.
      // But avoid moving cursor if user is typing.
      // User typing triggers onChanged -> parent updates field -> passes back here.
      // So widget.field.start SHOULD equal currentStart.
      // If it doesn't, it means external change (or invalid parse).
      // Auto-calc affects Length mostly.
      _startController.text = widget.field.start == 0
          ? ''
          : widget.field.start.toString();
    }

    final currentLength = int.tryParse(_lengthController.text) ?? 0;
    if (widget.field.length != currentLength) {
      _lengthController.text = widget.field.length == 0
          ? ''
          : widget.field.length.toString();
    }
  }

  @override
  void dispose() {
    _startController.dispose();
    _lengthController.dispose();
    super.dispose();
  }

  void _handleStartChange(String v) {
    final start = int.tryParse(v) ?? 0;
    if (widget.isSubject && start > 0) {
      widget.onChanged(start, widget.defaultQuestionCount);
    } else {
      widget.onChanged(start, widget.field.length);
    }
  }

  void _handleLengthChange(String v) {
    final len = int.tryParse(v) ?? 0;
    widget.onChanged(widget.field.start, len);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: 20, color: Colors.grey[600]),
          SizedBox(width: 12),
        ],
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.label,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              if (widget.isSubject)
                Text(
                  '${widget.defaultQuestionCount} Soru',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
            ],
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: _startController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              labelText: 'Başlangıç',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: Colors.grey[50],
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            ),
            onChanged: _handleStartChange,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: _lengthController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              labelText: 'Uzunluk',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: Colors.grey[50],
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            ),
            onChanged: _handleLengthChange,
          ),
        ),
      ],
    );
  }
}
