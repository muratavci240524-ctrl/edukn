import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../models/activity/activity_model.dart';
import '../../../../models/survey_model.dart'; // For SurveyQuestion
import '../../../../services/activity_service.dart';
import '../../../../models/class_model.dart';

class ActivityFormScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String initialType; // 'observation' or 'activity'
  final ActivityObservation? existingActivity;

  const ActivityFormScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.initialType,
    this.existingActivity,
  }) : super(key: key);

  @override
  State<ActivityFormScreen> createState() => _ActivityFormScreenState();
}

class _ActivityFormScreenState extends State<ActivityFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  late String _type;
  DateTime _selectedDate = DateTime.now();

  // Responsible Teacher
  String? _responsibleTeacherId;
  String _responsibleTeacherName = '';
  List<Map<String, dynamic>> _teachers = [];

  // Target Selection
  String _targetMode = 'grade'; // 'grade', 'class', 'student'

  // Data Caching
  List<ClassModel> _allClasses = [];
  List<int> _availableGrades = [];

  // Selections
  List<int> _selectedGrades = [];
  List<String> _selectedClassIds = [];
  List<String> _selectedStudentIds = [];

  int _totalStudentCount = 0;

  // Evaluation
  bool _isEvaluationEnabled = false;
  List<SurveyQuestion> _questions = [];

  // Loading
  bool _isLoading = false;
  bool _isCalculating = false;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _loadTeachers();
    _loadClasses();

    if (widget.existingActivity != null) {
      _loadExistingData();
    } else {
      _loadCurrentUserAsDefaultResponsible();
    }
  }

  Future<void> _loadClasses() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true)
          .get();

      if (mounted) {
        setState(() {
          _allClasses = snapshot.docs
              .map((d) => ClassModel.fromMap(d.data(), d.id))
              .toList();

          // Sort classes: Grade ascending, then Branch Name ascending
          _allClasses.sort((a, b) {
            final gradeComp = a.classLevel.compareTo(b.classLevel);
            if (gradeComp != 0) return gradeComp;
            return a.className.compareTo(b.className);
          });

          _availableGrades =
              _allClasses.map((c) => c.classLevel).toSet().toList()..sort();
        });
      }
    } catch (e) {
      debugPrint('Error loading classes: $e');
    }
  }

  void _loadExistingData() {
    final act = widget.existingActivity!;
    _titleController.text = act.title;
    _descController.text = act.description;
    _type = act.type;
    _selectedDate = act.date;
    _responsibleTeacherId = act.responsibleTeacherId;
    _responsibleTeacherName = act.responsibleTeacherName;
    _selectedStudentIds = List.from(act.targetStudentIds);
    _totalStudentCount = _selectedStudentIds.length;
    _isEvaluationEnabled = act.isEvaluationEnabled;
    _questions = List.from(act.questions);

    // Default to student mode in edit to preserve specific selection
    _targetMode = 'student';
  }

  Future<void> _loadCurrentUserAsDefaultResponsible() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists && mounted) {
        setState(() {
          _responsibleTeacherId = user.uid;
          _responsibleTeacherName =
              doc.data()?['fullName'] ?? user.displayName ?? 'Öğretmen';
        });
      }
    }
  }

  Future<void> _loadTeachers() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('type', isEqualTo: 'staff')
        .get();

    if (mounted) {
      setState(() {
        _teachers = snapshot.docs.map((d) {
          final data = d.data();
          return {
            'id': d.id,
            'name': data['fullName'] ?? data['name'] ?? 'İsimsiz',
            'title': data['title'] ?? '',
          };
        }).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingActivity != null
              ? (_type == 'observation' ? 'Gözlem Düzenle' : 'Etkinlik Düzenle')
              : (_type == 'observation' ? 'Yeni Gözlem' : 'Yeni Etkinlik'),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: Stepper(
              type: StepperType.vertical,
              physics: const ClampingScrollPhysics(),
              currentStep: _currentStep,
              onStepContinue: _nextStep,
              onStepCancel: _prevStep,
              controlsBuilder: (context, details) {
                return Padding(
                  padding: const EdgeInsets.only(top: 24.0),
                  child: Row(
                    children: [
                      ElevatedButton(
                        onPressed: details.onStepContinue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(_currentStep == 2 ? 'Kaydet' : 'Devam Et'),
                      ),
                      const SizedBox(width: 12),
                      if (_currentStep > 0)
                        TextButton(
                          onPressed: details.onStepCancel,
                          child: const Text('Geri'),
                        ),
                    ],
                  ),
                );
              },
              steps: [
                Step(
                  title: const Text('Genel Bilgiler'),
                  content: _buildGeneralInfoStep(),
                  isActive: _currentStep >= 0,
                  state: _currentStep > 0
                      ? StepState.complete
                      : StepState.editing,
                ),
                Step(
                  title: const Text('Hedef Kitle'),
                  content: _buildTargetStep(),
                  isActive: _currentStep >= 1,
                  state: _currentStep > 1
                      ? StepState.complete
                      : StepState.editing,
                ),
                Step(
                  title: const Text('Değerlendirme Kriterleri'),
                  content: _buildEvaluationStep(),
                  isActive: _currentStep >= 2,
                ),
              ],
            ),
          ),
          if (_isLoading || _isCalculating)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  int _currentStep = 0;

  void _nextStep() {
    if (_currentStep == 0) {
      if (!_formKey.currentState!.validate()) return;
      if (_responsibleTeacherId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen sorumlu öğretmen seçiniz')),
        );
        return;
      }
    } else if (_currentStep == 1) {
      if (_selectedStudentIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen en az bir öğrenci seçiniz')),
        );
        return;
      }
    } else if (_currentStep == 2) {
      _saveActivity();
      return;
    }

    setState(() => _currentStep++);
  }

  void _prevStep() {
    if (_currentStep > 0) setState(() => _currentStep--);
  }

  // --- STEP 1: General Info ---
  Widget _buildGeneralInfoStep() {
    final bool isObservation = _type == 'observation';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _titleController,
          decoration: InputDecoration(
            labelText: 'Başlık',
            hintText: isObservation
                ? 'Örn: Sınıf İçi Gözlem'
                : 'Örn: Kütüphane Gezisi',
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          validator: (v) => v?.isEmpty == true ? 'Başlık zorunludur' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _descController,
          decoration: InputDecoration(
            labelText: 'Açıklama',
            hintText: isObservation
                ? 'Gözlem detayları...'
                : 'Etkinlik detayları...',
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _selectedDate,
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            );
            if (picked != null) setState(() => _selectedDate = picked);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, color: Colors.indigo),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tarih',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_selectedDate.day}.${_selectedDate.month}.${_selectedDate.year}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _responsibleTeacherId,
          decoration: InputDecoration(
            labelText: 'Sorumlu Öğretmen',
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          items: [
            ..._teachers.map(
              (t) => DropdownMenuItem(
                value: t['id'] as String,
                child: Text(t['name']),
              ),
            ),
            if (_responsibleTeacherId != null &&
                !_teachers.any((t) => t['id'] == _responsibleTeacherId))
              DropdownMenuItem(
                value: _responsibleTeacherId!,
                child: Text(
                  _responsibleTeacherName.isNotEmpty
                      ? _responsibleTeacherName
                      : 'Aktif Kullanıcı',
                ),
              ),
          ].toList(),
          onChanged: (v) {
            setState(() {
              _responsibleTeacherId = v;
              _responsibleTeacherName = _teachers.firstWhere(
                (t) => t['id'] == v,
                orElse: () => {'name': 'Öğretmen'},
              )['name'];
            });
          },
        ),
      ],
    );
  }

  // --- STEP 2: Target Selection ---
  Widget _buildTargetStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildChoiceChip('Sınıf Seviyesi', 'grade'),
              const SizedBox(width: 8),
              _buildChoiceChip('Şube Bazlı', 'class'),
              const SizedBox(width: 8),
              _buildChoiceChip('Öğrenci Bazlı', 'student'),
            ],
          ),
        ),
        const Divider(height: 32),

        if (_targetMode == 'grade') ...[
          _buildGradeSelector(),
        ] else if (_targetMode == 'class') ...[
          _buildBranchSelector(),
        ] else ...[
          _buildStudentSelector(),
        ],

        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.people, color: Colors.indigo),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Toplam Hedef Öğrenci',
                    style: TextStyle(color: Colors.indigo),
                  ),
                  Text(
                    '$_totalStudentCount',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: Colors.indigo,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChoiceChip(String label, String value) {
    final isSelected = _targetMode == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: Colors.indigo.shade100,
      labelStyle: TextStyle(
        color: isSelected ? Colors.indigo.shade900 : Colors.black,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (val) {
        if (val) {
          setState(() {
            _targetMode = value;
            _selectedGrades = [];
            _selectedClassIds = [];
            _selectedStudentIds = [];
            _totalStudentCount = 0;
          });
        }
      },
    );
  }

  Widget _buildGradeSelector() {
    if (_availableGrades.isEmpty) {
      return const Text('Kayıtlı sınıf seviyesi bulunamadı.');
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _availableGrades.map((grade) {
        final isSelected = _selectedGrades.contains(grade);
        return FilterChip(
          label: Text('$grade. Sınıflar'),
          selected: isSelected,
          onSelected: (val) {
            setState(() {
              if (val) {
                _selectedGrades.add(grade);
              } else {
                _selectedGrades.remove(grade);
              }
            });
            _calculateStudents();
          },
        );
      }).toList(),
    );
  }

  Widget _buildBranchSelector() {
    final validClasses = _allClasses.where((c) => c.id != null).toList();

    if (validClasses.isEmpty) {
      return const Text('Kayıtlı şube bulunamadı.');
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: validClasses.map((cls) {
        final isSelected = _selectedClassIds.contains(cls.id);
        return FilterChip(
          label: Text(cls.className),
          selected: isSelected,
          onSelected: (val) {
            setState(() {
              if (val) {
                _selectedClassIds.add(cls.id!);
              } else {
                _selectedClassIds.remove(cls.id!);
              }
            });
            _calculateStudents();
          },
        );
      }).toList(),
    );
  }

  Widget _buildStudentSelector() {
    // Redesigned Student Selector
    return InkWell(
      onTap: _openStudentSelectionDialog,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.person_add_alt_1_rounded,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Öğrenci Listesi',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _selectedStudentIds.isEmpty
                        ? 'Listeden öğrenci seçmek için dokunun'
                        : '${_selectedStudentIds.length} öğrenci seçildi',
                    style: TextStyle(
                      color: _selectedStudentIds.isEmpty
                          ? Colors.grey.shade500
                          : Colors.green.shade600,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Future<void> _calculateStudents() async {
    setState(() => _isCalculating = true);

    try {
      if (_targetMode == 'grade') {
        if (_selectedGrades.isEmpty) {
          setState(() {
            _selectedStudentIds = [];
            _totalStudentCount = 0;
          });
          return;
        }

        // 1. Find class IDs for selected grades
        final targetClassIds = _allClasses
            .where(
              (c) => _selectedGrades.contains(c.classLevel) && c.id != null,
            )
            .map((c) => c.id!)
            .toList();

        if (targetClassIds.isEmpty) {
          setState(() {
            _selectedStudentIds = [];
            _totalStudentCount = 0;
          });
          return;
        }

        // 2. Query students in chunks (Firestore limit 10)
        List<String> foundIds = [];
        // Chunking manually
        for (var i = 0; i < targetClassIds.length; i += 10) {
          final chunk = targetClassIds.sublist(
            i,
            i + 10 > targetClassIds.length ? targetClassIds.length : i + 10,
          );
          final snap = await FirebaseFirestore.instance
              .collection('students')
              .where('institutionId', isEqualTo: widget.institutionId)
              .where('classId', whereIn: chunk)
              .get();
          foundIds.addAll(snap.docs.map((d) => d.id));
        }

        setState(() {
          _selectedStudentIds = foundIds;
          _totalStudentCount = foundIds.length;
        });
      } else if (_targetMode == 'class') {
        if (_selectedClassIds.isEmpty) {
          setState(() {
            _selectedStudentIds = [];
            _totalStudentCount = 0;
          });
          return;
        }

        List<String> foundIds = [];
        for (var i = 0; i < _selectedClassIds.length; i += 10) {
          final chunk = _selectedClassIds.sublist(
            i,
            i + 10 > _selectedClassIds.length
                ? _selectedClassIds.length
                : i + 10,
          );
          final snap = await FirebaseFirestore.instance
              .collection('students')
              .where('institutionId', isEqualTo: widget.institutionId)
              .where('classId', whereIn: chunk)
              .get();
          foundIds.addAll(snap.docs.map((d) => d.id));
        }

        setState(() {
          _selectedStudentIds = foundIds;
          _totalStudentCount = foundIds.length;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _isCalculating = false);
    }
  }

  void _openStudentSelectionDialog() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Öğrenci Seç'),
        content: SizedBox(
          width: double.maxFinite,
          child: StudentMultiSelect(
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
            initialSelection: _selectedStudentIds,
            onSelectionChanged: (ids) {
              setState(() {
                _selectedStudentIds = ids;
                _totalStudentCount = ids.length;
              });
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  // --- STEP 3: Evaluation ---
  Widget _buildEvaluationStep() {
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Değerlendirme Yapılacak mı?'),
          subtitle: const Text(
            'Etkinlik sonrası öğrenciler değerlendirilsin mi?',
          ),
          value: _isEvaluationEnabled,
          onChanged: (v) => setState(() => _isEvaluationEnabled = v),
        ),
        if (_isEvaluationEnabled) ...[
          const Divider(),
          const Text('Sorular', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._questions.asMap().entries.map((entry) {
            final index = entry.key;
            final q = entry.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(child: Text('${index + 1}')),
                title: Text(q.text),
                subtitle: Text(q.type.name),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => setState(() => _questions.removeAt(index)),
                ),
              ),
            );
          }).toList(),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _showAddQuestionDialog,
            icon: const Icon(Icons.add),
            label: const Text('Soru Ekle'),
          ),
        ],
      ],
    );
  }

  void _showAddQuestionDialog() {
    final qTextCtrl = TextEditingController();
    SurveyQuestionType qType = SurveyQuestionType.rating;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateFn) => AlertDialog(
          title: const Text('Soru Ekle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qTextCtrl,
                decoration: const InputDecoration(labelText: 'Soru Metni'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<SurveyQuestionType>(
                value: qType,
                items: const [
                  DropdownMenuItem(
                    value: SurveyQuestionType.rating,
                    child: Text('Puanlama (1-5)'),
                  ),
                  DropdownMenuItem(
                    value: SurveyQuestionType.text,
                    child: Text('Metin'),
                  ),
                  DropdownMenuItem(
                    value: SurveyQuestionType.singleChoice,
                    child: Text('Evet/Hayır'),
                  ),
                ],
                onChanged: (v) => setStateFn(() => qType = v!),
                decoration: const InputDecoration(labelText: 'Soru Tipi'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                if (qTextCtrl.text.isEmpty) return;
                setState(() {
                  _questions.add(
                    SurveyQuestion(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      text: qTextCtrl.text,
                      type: qType,
                      options: qType == SurveyQuestionType.singleChoice
                          ? ['Evet', 'Hayır']
                          : [],
                    ),
                  );
                });
                Navigator.pop(ctx);
              },
              child: const Text('Ekle'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveActivity() async {
    setState(() => _isLoading = true);
    try {
      final activity = ActivityObservation(
        id: widget.existingActivity?.id ?? '',
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
        title: _titleController.text,
        description: _descController.text,
        type: _type,
        date: _selectedDate,
        responsibleTeacherId: _responsibleTeacherId!,
        responsibleTeacherName: _responsibleTeacherName,
        targetStudentIds: _selectedStudentIds,
        isEvaluationEnabled: _isEvaluationEnabled,
        questions: _questions,
        createdAt: DateTime.now(),
        status: ActivityStatus.planned,
      );

      final service = ActivityService();
      if (widget.existingActivity != null) {
        await service.updateActivity(
          widget.existingActivity!.id,
          activity.toMap(),
        );
      } else {
        await service.createActivity(activity);
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Kaydedildi')));
        Navigator.pop(context);
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
}

class StudentMultiSelect extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final List<String> initialSelection;
  final ValueChanged<List<String>> onSelectionChanged;

  const StudentMultiSelect({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.initialSelection,
    required this.onSelectionChanged,
  }) : super(key: key);

  @override
  State<StudentMultiSelect> createState() => _StudentMultiSelectState();
}

class _StudentMultiSelectState extends State<StudentMultiSelect> {
  List<String> _selectedIds = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedIds = List.from(widget.initialSelection);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Öğrenci Ara',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: (val) {
              setState(() {
                _searchQuery = val.toLowerCase();
              });
            },
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('students')
                .where('institutionId', isEqualTo: widget.institutionId)
                .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
                .orderBy('name')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final name = (data['fullName'] ?? data['name'] ?? '')
                    .toString()
                    .toLowerCase();
                return name.contains(_searchQuery);
              }).toList();

              if (docs.isEmpty) {
                return const Center(child: Text('Öğrenci bulunamadı'));
              }

              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final id = docs[index].id;
                  final name = data['fullName'] ?? data['name'] ?? 'İsimsiz';
                  final className = data['className'] ?? '';
                  final isSelected = _selectedIds.contains(id);

                  return CheckboxListTile(
                    value: isSelected,
                    title: Text(name),
                    subtitle: Text(className),
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedIds.add(id);
                        } else {
                          _selectedIds.remove(id);
                        }
                        widget.onSelectionChanged(_selectedIds);
                      });
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
