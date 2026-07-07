import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../services/assessment_service.dart';
import '../../../../models/assessment/trial_exam_model.dart';
import '../../../../models/lesson_model.dart';
import '../../../../widgets/edukn_logo.dart';
import '../../../../models/assessment/assessment_action_plan_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
class AssessmentActionPlanScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final AssessmentActionPlan? existingPlan;
  
  // Initial parameters for new plans
  final List<String>? initialExamIds;
  final Map<String, double>? initialThresholds;
  final double? initialGlobalThreshold;
  final String? initialClassLevel;

  const AssessmentActionPlanScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    this.existingPlan,
    this.initialExamIds,
    this.initialThresholds,
    this.initialGlobalThreshold,
    this.initialClassLevel,
  }) : super(key: key);

  @override
  _AssessmentActionPlanScreenState createState() =>
      _AssessmentActionPlanScreenState();
}

class _AssessmentActionPlanScreenState extends State<AssessmentActionPlanScreen>
    with SingleTickerProviderStateMixin {
  final AssessmentService _service = AssessmentService();
  late TabController _tabController;
  String _userName = 'Yükleniyor...';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadInitialData();
    _loadUserName();
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text.toLowerCase();
          _filterExams();
        });
      }
    });
  }

  Future<void> _loadUserName() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (mounted) {
          setState(() {
            _userName = doc.data()?['name'] ?? doc.data()?['displayName'] ?? 'Kullanıcı';
          });
        }
      }
    } catch (e) {
      print('Error loading user name: $e');
    }
  }

  // Filters & Selection
  List<TrialExam> _allExams = [];
  List<TrialExam> _filteredExams = [];
  Set<String> _selectedExamIds = {};
  String? _selectedClassLevel;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Thresholds (Subject -> % Success Threshold)
  Map<String, double> _subjectThresholds = {};
  List<String> _availableSubjects = [];

  // Data
  bool _isLoading = true;
  bool _isProcessing = false;
  
  // Results: Map<Branch, Map<Subject, Map<Outcome, Map<String, dynamic>>>>
  // Contains: { 'correct': int, 'total': int, 'students': List<Map<String, dynamic>> }
  Map<String, Map<String, Map<String, Map<String, dynamic>>>> _outcomeStats = {};
  
  // Teachers: Map<Branch, Map<Subject, String>>
  Map<String, Map<String, String>> _branchTeachers = {};
  // Fallback: Map<Subject, String> — used when branch doesn't match className
  Map<String, String> _subjectTeacherFallback = {};

  // Action Plans: Map<Branch_Subject, Map<String, dynamic>>
  // Contains: { 'problemSource': String, 'actionPlan': String, 'status': String }
  Map<String, Map<String, dynamic>> _branchActionPlans = {};

  // View Filters for Step 2 & 3 (Multi-select)
  List<String> _selectedViewBranches = [];
  List<String> _selectedViewSubjects = [];
  double _globalThreshold = 70.0;

  // Student Subject Performance: Map<Branch, Map<Subject, Map<StudentId, Map<String, dynamic>>>>
  // Contains: { 'correct': int, 'total': int, 'name': String, 'no': String }
  Map<String, Map<String, Map<String, Map<String, dynamic>>>> _studentSubjectStats = {};

  bool _showOnlyCritical = false;

  // Student tracking state
  Set<String> _selectedStudentKeys = {}; // 'branch_subject_studentKey'
  // studentTasks: 'branch_subject_studentKey' -> List<Map<String,dynamic>>
  // Each task: {'type': String, 'label': String, 'done': bool}
  Map<String, List<Map<String, dynamic>>> _studentTasks = {};
  // parentNotified: 'branch_subject_studentKey' -> bool
  Map<String, bool> _parentNotified = {};
  // studentStatus: 'branch_subject_studentKey' -> String
  Map<String, String> _studentStatus = {};

  static const List<Map<String, dynamic>> _taskTypes = [
    {'type': 'soru', 'label': 'Soru Çözümü', 'icon': Icons.quiz_outlined},
    {'type': 'konu', 'label': 'Konu Özeti', 'icon': Icons.menu_book_outlined},
    {'type': 'video', 'label': 'Video İzleme', 'icon': Icons.play_circle_outline},
    {'type': 'etut', 'label': 'Etüt Çalışması', 'icon': Icons.school_outlined},
    {'type': 'odev', 'label': 'Ödev Takibi', 'icon': Icons.assignment_outlined},
    {'type': 'test', 'label': 'Kazanım Testi', 'icon': Icons.check_circle_outline},
  ];

  final List<String> _predefinedActionPlans = [
    'Konu anlatımı tekrarı',
    'Ek soru çözümü saatleri',
    'Ödev takip çizelgesi',
    'Birebir etüt çalışması',
    'Grup etüt çalışması',
    'Kazanım değerlendirme testi',
    'Veli bilgilendirme ve işbirliği',
    'Rehberlik görüşmesi',
    'Diğer',
  ];

  String? _userRole;
  final Map<String, TextEditingController> _otherActionPlanControllers = {};



  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    for (var controller in _otherActionPlanControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      // Load Exams
      final examsStream = _service.getTrialExams(widget.institutionId);
      examsStream.first.then((exams) {
        if (mounted) {
          setState(() {
            _allExams = exams;
            _filterExams();
            _isLoading = false;
          });
          
          if (widget.existingPlan != null) {
            _loadExistingPlanData();
          } else if (widget.initialExamIds != null) {
            _loadInitialParameters();
          }
        }
      });

      // Load Lesson Assignments for Teachers
      // When schoolTypeId is empty (general account), query without that filter
      Query assignmentsQuery = FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true);

      if (widget.schoolTypeId.isNotEmpty) {
        assignmentsQuery = assignmentsQuery.where('schoolTypeId', isEqualTo: widget.schoolTypeId);
      }

      final assignmentsSnapshot = await assignmentsQuery.get();

      Map<String, Map<String, String>> teacherMap = {};
      // Fallback: subject → teacher (ignoring branch), used when branch doesn't match
      Map<String, String> subjectTeacherFallback = {};

      for (var doc in assignmentsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        String className = data['className'] ?? '';
        String lessonName = data['lessonName'] ?? '';
        List<dynamic> teacherNames = data['teacherNames'] ?? [];
        
        if (lessonName.isNotEmpty && teacherNames.isNotEmpty) {
          final teacherStr = teacherNames.join(', ');
          // Primary: class + lesson lookup
          if (className.isNotEmpty) {
            teacherMap.putIfAbsent(className, () => {});
            teacherMap[className]![lessonName] = teacherStr;
          }
          // Fallback: subject only (first assignment wins)
          subjectTeacherFallback.putIfAbsent(lessonName, () => teacherStr);
        }
      }

      if (mounted) {
        final user = FirebaseAuth.instance.currentUser;
        String? role;
        if (user != null) {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
          role = userDoc.data()?['role'];
        }

        setState(() {
          _branchTeachers = teacherMap;
          _subjectTeacherFallback = subjectTeacherFallback;
          _userRole = role;
        });
      }
    } catch (e) {
      print('Error loading initial data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _loadExistingPlanData() {
    final plan = widget.existingPlan!;
    setState(() {
      _selectedExamIds = Set.from(plan.selectedExamIds);
      _subjectThresholds = Map.from(plan.subjectThresholds);
      _branchActionPlans = Map.from(plan.branchActionPlans);
      
      // Load student tasks and parent notifications
      _studentTasks = {};
      plan.studentTasks.forEach((k, v) {
        if (v is List) {
          _studentTasks[k] = List<Map<String, dynamic>>.from(
            v.map((item) => Map<String, dynamic>.from(item as Map)),
          );
        }
      });
      _parentNotified = Map<String, bool>.from(plan.parentNotified);
      _studentStatus = Map<String, String>.from(plan.studentStatus);

      _selectedClassLevel = plan.classLevel;
      _calculateStats();
    });
  }

  void _loadInitialParameters() {
    setState(() {
      _selectedExamIds = Set.from(widget.initialExamIds!);
      _subjectThresholds = Map.from(widget.initialThresholds!);
      _globalThreshold = widget.initialGlobalThreshold ?? 70.0;
      _selectedClassLevel = widget.initialClassLevel;
      _calculateStats();
    });
  }

  Future<void> _saveActionPlan() async {
    if (_selectedExamIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen en az bir sınav seçin.')),
      );
      return;
    }

    // Generate a descriptive title from selected exams
    String defaultTitle = '';
    if (widget.existingPlan != null) {
      defaultTitle = widget.existingPlan!.title;
    } else {
      final selectedExams = _allExams.where((e) => _selectedExamIds.contains(e.id)).toList();
      if (selectedExams.length == 1) {
        defaultTitle = '${selectedExams.first.name} Eylem Planı';
      } else if (selectedExams.length > 1) {
        defaultTitle = '${selectedExams.length} Sınav Karma Eylem Planı';
      } else {
        defaultTitle = '${_selectedClassLevel ?? "Tüm"} Sınıflar Eylem Planı';
      }
      // Add date
      defaultTitle += ' - ${DateFormat("dd.MM.yyyy").format(DateTime.now())}';
    }

    final titleController = TextEditingController(text: defaultTitle);

    final result = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eylem Planını Kaydet'),
        content: TextField(
          controller: titleController,
          decoration: const InputDecoration(labelText: 'Plan Başlığı', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kaydet')),
        ],
      ),
    );

    if (result == true) {
      setState(() => _isProcessing = true);
      try {
        final user = FirebaseAuth.instance.currentUser;
        
        // Get names of selected exams
        List<String> selectedNames = _allExams
            .where((e) => _selectedExamIds.contains(e.id))
            .map((e) => e.name)
            .toList();

        // Transition statuses: Hazır -> Uygulanıyor
        _branchActionPlans.forEach((key, plan) {
          if (plan['status'] == 'Eylem Planı Hazır') {
            plan['status'] = 'Uygulanıyor';
          }
        });

        final plan = AssessmentActionPlan(
          id: widget.existingPlan?.id ?? '',
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          title: titleController.text,
          date: widget.existingPlan?.date ?? DateTime.now(),
          createdBy: user?.uid ?? 'anon',
          creatorName: _userName,
          selectedExamIds: _selectedExamIds.toList(),
          selectedExamNames: selectedNames,
          classLevel: _selectedClassLevel ?? 'Tümü',
          subjectThresholds: _subjectThresholds,
          outcomeStats: _outcomeStats,
          branchActionPlans: _branchActionPlans,
          studentTasks: _studentTasks,
          parentNotified: _parentNotified,
          studentStatus: _studentStatus,
          isRealized: widget.existingPlan?.isRealized ?? false,
          realizationNotes: widget.existingPlan?.realizationNotes ?? '',
        );

        await _service.saveAssessmentActionPlan(plan);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Eylem planı başarıyla kaydedildi.')),
          );
          Navigator.pop(context); // Go back to list
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Hata: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  Future<List<String>> _getOrderedSubjects() async {
    if (_selectedExamIds.isEmpty) return [];
    try {
      final firstExamId = _selectedExamIds.first;
      final exam = _allExams.firstWhere((e) => e.id == firstExamId);
      final examType = await _service.getExamType(exam.examTypeId);
      if (examType != null) {
        return examType.subjects.map((s) => s.branchName).toList();
      }
    } catch (e) {
      print('Error ordering subjects: $e');
    }
    return _availableSubjects;
  }

  void _filterExams() {
    setState(() {
      _filteredExams = _allExams.where((exam) {
        final matchesClass = _selectedClassLevel == null ||
            exam.classLevel == _selectedClassLevel;
        final matchesSearch = exam.name.toLowerCase().contains(_searchQuery);
        return matchesClass && matchesSearch;
      }).toList();
      _filteredExams.sort((a, b) => b.date.compareTo(a.date));
    });
  }

  void _onExamSelected(String examId) {
    setState(() {
      if (_selectedExamIds.contains(examId)) {
        _selectedExamIds.remove(examId);
      } else {
        _selectedExamIds.add(examId);
      }
    });
    _calculateStats();
  }

  Future<void> _calculateStats() async {
    if (_selectedExamIds.isEmpty) {
      setState(() {
        _outcomeStats = {};
        _availableSubjects = [];
      });
      return;
    }

    setState(() => _isProcessing = true);

    List<TrialExam> selectedExams = _allExams
        .where((e) => _selectedExamIds.contains(e.id))
        .toList();

    // Map<Branch, Map<Subject, Map<Outcome, Map<String, dynamic>>>>
    Map<String, Map<String, Map<String, Map<String, dynamic>>>> branchStats = {};
    // Map<Branch, Map<Subject, Map<StudentKey, Map<String, dynamic>>>>
    Map<String, Map<String, Map<String, Map<String, dynamic>>>> studentSubjStats = {};
    Set<String> subjects = {};

    for (var exam in selectedExams) {
      if (exam.resultsJson == null || exam.resultsJson!.isEmpty) continue;

      try {
        final List<dynamic> results = jsonDecode(exam.resultsJson!);
        
        for (var result in results) {
          String branch = (result['branch'] ?? result['className'] ?? 'Belirsiz').toString();
          
          Map<String, dynamic> studentSubjects = result['subjects'] ?? {};
          
          studentSubjects.forEach((subjName, subjData) {
            // 1. Determine Booklet
            String booklet = (result['booklet'] ?? result['kitapçık'] ?? 'A').toString().toUpperCase().trim();
            if (booklet.isEmpty) booklet = 'A';
            if (!exam.outcomes.containsKey(booklet)) {
              if (exam.outcomes.isNotEmpty) booklet = exam.outcomes.keys.first;
            }

            // 2. Normalize subject name for matching
            String normalizedSubjName = subjName;
            if (exam.outcomes[booklet] != null && !exam.outcomes[booklet]!.containsKey(subjName)) {
              final foundKey = exam.outcomes[booklet]!.keys.firstWhere(
                (k) => k.toLowerCase().trim() == subjName.toLowerCase().trim() || 
                       k.toLowerCase().contains(subjName.toLowerCase().trim()) || 
                       subjName.toLowerCase().trim().contains(k.toLowerCase().trim()),
                orElse: () => '',
              );
              if (foundKey.isNotEmpty) normalizedSubjName = foundKey;
            }

            subjects.add(normalizedSubjName);

            // 3. Get Exam Data (Outcomes & Keys)
            var examOutcomes = exam.outcomes[booklet]?[normalizedSubjName];
            var examAnswers = exam.answerKeys[booklet]?[normalizedSubjName];
            
            if (examOutcomes == null || examAnswers == null) return;

            // 4. Extract Student Answers (Robust approach)
            dynamic studentAnsRaw;
            
            // Try subjData first
            if (subjData is Map) {
              studentAnsRaw = subjData['answers'] ?? subjData['cevaplar'] ?? subjData['cevap_anahtari'];
            }
            
            // Try root-level maps if still null
            if (studentAnsRaw == null) {
              if (result['answers'] is Map) {
                studentAnsRaw = result['answers'][subjName] ?? result['answers'][normalizedSubjName];
              }
              if (studentAnsRaw == null && result['cevaplar'] is Map) {
                studentAnsRaw = result['cevaplar'][subjName] ?? result['cevaplar'][normalizedSubjName];
              }
            }
            
            // If still null, try if subjData itself is the string/list
            if (studentAnsRaw == null && (subjData is String || subjData is List)) {
              studentAnsRaw = subjData;
            }

            if (studentAnsRaw == null) return;

            // 5. Parse and Compare
            final studentAnsList = _parseAnswers(studentAnsRaw, examOutcomes.length);
            final correctAnsList = _parseAnswers(examAnswers, examOutcomes.length);

            branchStats.putIfAbsent(branch, () => {});
            branchStats[branch]!.putIfAbsent(normalizedSubjName, () => {});
            
            studentSubjStats.putIfAbsent(branch, () => {});
            studentSubjStats[branch]!.putIfAbsent(normalizedSubjName, () => {});
            
            String studentKey = (result['studentNumber'] ?? result['number'] ?? result['name'] ?? 'İsimsiz').toString();
            studentSubjStats[branch]![normalizedSubjName]!.putIfAbsent(studentKey, () => {
              'correct': 0,
              'total': 0,
              'name': result['name'] ?? result['studentName'] ?? 'İsimsiz',
              'no': result['studentNumber'] ?? result['number'] ?? '',
            });

            for (int i = 0; i < examOutcomes.length; i++) {
              String outcome = examOutcomes[i].toString().trim();
              if (outcome.isEmpty || outcome == 'null') outcome = 'Genel';

              branchStats[branch]![normalizedSubjName]!.putIfAbsent(outcome, () => {
                'correct': 0,
                'total': 0,
                'students': <Map<String, dynamic>>[]
              });

              branchStats[branch]![normalizedSubjName]![outcome]!['total']++;
              studentSubjStats[branch]![normalizedSubjName]![studentKey]!['total']++;
              
              bool isCorrect = i < studentAnsList.length && i < correctAnsList.length && 
                              studentAnsList[i].trim() == correctAnsList[i].trim() && 
                              studentAnsList[i].trim().isNotEmpty;
              
              if (isCorrect) {
                branchStats[branch]![normalizedSubjName]![outcome]!['correct']++;
                studentSubjStats[branch]![normalizedSubjName]![studentKey]!['correct']++;
              } else {
                (branchStats[branch]![normalizedSubjName]![outcome]!['students'] as List).add({
                  'name': result['name'] ?? result['studentName'] ?? 'İsimsiz',
                  'no': result['studentNumber'] ?? result['number'] ?? '',
                  'isWrong': i < studentAnsList.length && studentAnsList[i].trim().isNotEmpty,
                  'isEmpty': i >= studentAnsList.length || studentAnsList[i].trim().isEmpty,
                });
              }
            }
          });
        }
      } catch (e) {
        print('Error processing exam ${exam.id}: $e');
      }
    }

    final orderedSubjects = await _getOrderedSubjects();

    setState(() {
      _outcomeStats = branchStats;
      _studentSubjectStats = studentSubjStats;
      
      // Order available subjects according to ExamType
      List<String> found = subjects.toList();
      _availableSubjects = orderedSubjects.where((s) => found.contains(s)).toList();
      // Add any subjects found in results but not in ExamType (fallback)
      for (var s in found) {
        if (!_availableSubjects.contains(s)) _availableSubjects.add(s);
      }

      for (var s in _availableSubjects) {
        _subjectThresholds.putIfAbsent(s, () => _globalThreshold);
      }
      if (_selectedViewBranches.isEmpty && _outcomeStats.isNotEmpty) {
        final sorted = _outcomeStats.keys.toList()..sort();
        _selectedViewBranches = [sorted.first];
      }
      if (_selectedViewSubjects.isEmpty && _availableSubjects.isNotEmpty) {
        _selectedViewSubjects = [_availableSubjects.first];
      }
      
      _isProcessing = false;
    });
  }

  List<String> _parseAnswers(dynamic raw, int length) {
    if (raw == null) return List.filled(length, ' ');
    
    List<String> res = [];
    if (raw is List) {
      res = raw.map((e) => e.toString().toUpperCase().trim()).toList();
    } else {
      String s = raw.toString().toUpperCase().trim();
      if (s.contains(' ') || s.contains(',') || s.contains('|')) {
        res = s.split(RegExp(r'[\s,|]')).where((e) => e.isNotEmpty).toList();
        if (res.length != length) {
          res = s.replaceAll(RegExp(r'[,|.]'), '').split('');
          if (res.length > length) {
            res = res.where((e) => e != ' ').toList();
          }
        }
      } else {
        res = s.split('');
      }
    }

    if (res.length > length) {
      res = res.sublist(0, length);
    } else if (res.length < length) {
      res.addAll(List.filled(length - res.length, ' '));
    }
    
    return res.map((e) => e.isEmpty ? ' ' : e).toList();
  }

  void _applyGlobalThreshold(double val) {
    setState(() {
      _globalThreshold = val;
      for (var s in _availableSubjects) {
        _subjectThresholds[s] = val;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Eylem Planları', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: IconButton(
                onPressed: (_isProcessing || (widget.existingPlan == null && _userRole == 'teacher')) 
                    ? null 
                    : _saveActionPlan,
                icon: const Icon(Icons.save),
                tooltip: (widget.existingPlan == null && _userRole == 'teacher') 
                    ? 'Yeni plan oluşturma yetkiniz yok' 
                    : 'Kaydet',
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 4,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'ŞUBE EYLEM PLANI'),
            Tab(text: 'ÖĞRENCİ TAKİBİ'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: EduKnLoader(size: 80))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildStep2BranchPlans(),
                _buildStep3StudentPlans(),
              ],
            ),
    );
  }


  Widget _buildStep2BranchPlans() {
    if (_selectedExamIds.isEmpty) return _buildEmptyState('Lütfen önce sınav seçimi yapın.');
    
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isMobile = constraints.maxWidth < 700;
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isMobile) ...[
                _buildHeader('Şube Eylem Planları', 'Düşük başarı gösterilen kazanımlar için eylem planı belirleyin.'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildFilterToggle(true),
                    const SizedBox(width: 8),
                    Expanded(child: _buildMultiSelectFilter('Şube', _selectedViewBranches, _outcomeStats.keys.toList()..sort(), (v) => setState(() => _selectedViewBranches = v), Icons.business)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildMultiSelectFilter('Branş', _selectedViewSubjects, _availableSubjects, (v) => setState(() => _selectedViewSubjects = v), Icons.book)),
                  ],
                ),
              ] else
                Row(
                  children: [
                    Expanded(child: _buildHeader('Şube Eylem Planları', 'Düşük başarı gösterilen kazanımlar için eylem planı belirleyin.')),
                    _buildFilterToggle(false),
                    const SizedBox(width: 16),
                    _buildMultiSelectFilter('Şube', _selectedViewBranches, _outcomeStats.keys.toList()..sort(), (v) => setState(() => _selectedViewBranches = v), Icons.business, width: 180),
                    const SizedBox(width: 12),
                    _buildMultiSelectFilter('Branş', _selectedViewSubjects, _availableSubjects, (v) => setState(() => _selectedViewSubjects = v), Icons.book, width: 200),
                  ],
                ),
              const SizedBox(height: 32),
              _buildMultiFilteredOutcomeTable(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterToggle(bool isMobile) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _showOnlyCritical = !_showOnlyCritical),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 44,
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 12),
        decoration: BoxDecoration(
          color: _showOnlyCritical ? Colors.red.shade50 : Colors.indigo.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _showOnlyCritical ? Colors.red.shade200 : Colors.indigo.shade200),
          boxShadow: [
            BoxShadow(
              color: (_showOnlyCritical ? Colors.red : Colors.indigo).withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _showOnlyCritical ? Icons.report_problem_rounded : Icons.view_list_rounded,
              color: _showOnlyCritical ? Colors.red.shade700 : Colors.indigo.shade700,
              size: 18,
            ),
            if (!isMobile) ...[
              const SizedBox(width: 8),
              Text(
                _showOnlyCritical ? 'Sadece Kritikler' : 'Tüm Kazanımlar',
                style: TextStyle(
                  color: _showOnlyCritical ? Colors.red.shade900 : Colors.indigo.shade900,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMultiFilteredOutcomeTable() {
    List<Widget> cards = [];
    for (var branch in _selectedViewBranches) {
      for (var subject in _selectedViewSubjects) {
        final outcomesMap = _outcomeStats[branch]?[subject] ?? {};
        final threshold = _subjectThresholds[subject] ?? 70.0;
        final sorted = outcomesMap.entries.toList()..sort((a, b) {
          double sA = a.value['total'] > 0 ? (a.value['correct'] / a.value['total']) * 100 : 0;
          double sB = b.value['total'] > 0 ? (b.value['correct'] / b.value['total']) * 100 : 0;
          return sA.compareTo(sB);
        });
        if (sorted.isEmpty) continue;
        
        final filteredRows = sorted.where((e) {
          if (!_showOnlyCritical) return true;
          double success = e.value['total'] > 0 ? (e.value['correct'] / e.value['total']) * 100 : 0;
          return success < threshold;
        }).toList();

        if (filteredRows.isEmpty) continue;

        cards.add(Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(branch, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)), backgroundColor: Colors.indigo.shade900),
                  Text(subject, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              ...filteredRows.map((e) => _buildOutcomeRow(branch, subject, e.key, e.value, threshold)).toList(),
            ],
          ),
        ));
      }
    }
    return cards.isEmpty ? _buildEmptyState(_showOnlyCritical ? 'Kritik başarı seviyesinde kazanım bulunamadı.' : 'Veri bulunamadı.') : Column(children: cards);
  }

  Widget _buildOutcomeRow(String branch, String subject, String outcome, Map<String, dynamic> data, double threshold) {
    double success = data['total'] > 0 ? (data['correct'] / data['total']) * 100 : 0.0;
    bool isLow = success < threshold;
    String key = '${branch}_${subject}_$outcome';
    _branchActionPlans.putIfAbsent(key, () => {'problemSource': '', 'actionPlan': '', 'status': 'Belirlenmedi'});
    
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isMobile = constraints.maxWidth < 700;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isLow ? Colors.red.shade100 : Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: (isLow ? Colors.red : Colors.indigo).withOpacity(0.04),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Section
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isLow ? Colors.red.shade50.withOpacity(0.3) : Colors.indigo.shade50.withOpacity(0.2),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isLow ? Colors.red.shade100 : Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isLow ? 'KRİTİK' : 'YETERLİ',
                                  style: TextStyle(
                                    color: isLow ? Colors.red.shade900 : Colors.green.shade900,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '%${success.toStringAsFixed(1)} Başarı',
                                style: TextStyle(
                                  color: isLow ? Colors.red.shade700 : Colors.indigo.shade700,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            outcome,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    _buildTeacherBadge(branch, subject),
                  ],
                ),
              ),
              
              // Inputs Section
              Padding(
                padding: const EdgeInsets.all(20),
                child: isMobile 
                  ? Column(
                      children: [
                        _buildPremiumInputCard('Problem Kaynağı', _buildProblemSourceDropdown(key), Icons.psychology_outlined),
                        const SizedBox(height: 16),
                        _buildPremiumInputCard('Eylem Planı', _buildActionPlanField(key), Icons.assignment_outlined),
                        const SizedBox(height: 16),
                        _buildPremiumInputCard('Durum', _buildStatusBadge(key), Icons.flag_outlined, noPadding: true),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildPremiumInputCard('Problem Kaynağı', _buildProblemSourceDropdown(key), Icons.psychology_outlined)),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: _buildPremiumInputCard('Eylem Planı', _buildActionPlanField(key), Icons.assignment_outlined)),
                        const SizedBox(width: 16),
                        SizedBox(width: 160, child: _buildPremiumInputCard('Durum', _buildStatusBadge(key), Icons.flag_outlined, noPadding: true)),
                      ],
                    ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTeacherBadge(String branch, String subject) {
    String teacher = _getTeacherName(branch, subject);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Colors.indigo.shade100,
            child: Text(teacher[0], style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo.shade900)),
          ),
          const SizedBox(width: 8),
          Text(teacher, style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildPremiumInputCard(String label, Widget child, IconData icon, {bool noPadding = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 6),
          child: Row(
            children: [
              Icon(icon, size: 14, color: Colors.indigo.shade400),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.indigo.shade900.withOpacity(0.6))),
            ],
          ),
        ),
        Container(
          height: 48,
          alignment: Alignment.centerLeft,
          padding: noPadding ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.indigo.shade50.withOpacity(0.8), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.indigo.withOpacity(0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: noPadding 
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(14.8), // Adjusted for border width
                  child: SizedBox.expand(child: child),
                ) 
              : child,
        ),
      ],
    );
  }

  Widget _buildStep3StudentPlans() {
    if (_selectedExamIds.isEmpty) return _buildEmptyState('Lütfen önce sınav seçimi yapın.');
    
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isMobile = constraints.maxWidth < 700;
        List<Widget> subjectCards = [];
        
        for (var branch in _selectedViewBranches) {
          for (var subject in _selectedViewSubjects) {
            final studentsMap = _studentSubjectStats[branch]?[subject] ?? {};
            final threshold = _subjectThresholds[subject] ?? 70.0;
            List<Map<String, dynamic>> low = [];
            studentsMap.forEach((id, data) {
              double s = data['total'] > 0 ? (data['correct'] / data['total']) * 100 : 0;
              if (s < threshold) low.add({...data, 'success': s, 'id': id});
            });
            if (low.isNotEmpty) {
              low.sort((a, b) => (a['success'] as double).compareTo(b['success'] as double));
              subjectCards.add(_buildStudentSubjectGroupCard(branch, subject, low));
            }
          }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isMobile) ...[
                _buildHeader('Öğrenci Takibi', 'Ders bazlı barajın altında kalan öğrenciler.'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildMultiSelectFilter('Şube', _selectedViewBranches, _outcomeStats.keys.toList()..sort(), (v) => setState(() => _selectedViewBranches = v), Icons.business)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildMultiSelectFilter('Branş', _selectedViewSubjects, _availableSubjects, (v) => setState(() => _selectedViewSubjects = v), Icons.book)),
                  ],
                ),
              ] else
                Row(
                  children: [
                    Expanded(child: _buildHeader('Öğrenci Takibi', 'Ders bazlı barajın altında kalan öğrenciler.')),
                    _buildMultiSelectFilter('Şube', _selectedViewBranches, _outcomeStats.keys.toList()..sort(), (v) => setState(() => _selectedViewBranches = v), Icons.business, width: 180),
                    const SizedBox(width: 12),
                    _buildMultiSelectFilter('Branş', _selectedViewSubjects, _availableSubjects, (v) => setState(() => _selectedViewSubjects = v), Icons.book, width: 200),
                  ],
                ),
              const SizedBox(height: 32),
              subjectCards.isEmpty 
                ? _buildEmptyState('Öğrenci bulunamadı.') 
                : Column(children: subjectCards),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStudentSubjectGroupCard(String branch, String subject, List<Map<String, dynamic>> students) {
    // Keys for this group
    final groupKeys = students.map((s) => '${branch}_${subject}_${s['id']}').toList();
    final allSelected = groupKeys.every((k) => _selectedStudentKeys.contains(k));
    final someSelected = groupKeys.any((k) => _selectedStudentKeys.contains(k));

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.indigo.shade50, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          shape: const RoundedRectangleBorder(side: BorderSide.none),
          collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
          leading: Checkbox(
            value: allSelected ? true : (someSelected ? null : false),
            tristate: true,
            activeColor: Colors.indigo,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            onChanged: (_) {
              setState(() {
                if (allSelected) {
                  _selectedStudentKeys.removeAll(groupKeys);
                } else {
                  _selectedStudentKeys.addAll(groupKeys);
                }
              });
            },
          ),
          title: Text('$branch — $subject', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.indigo, fontSize: 15)),
          subtitle: Text('${students.length} öğrenci barajın altında', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          trailing: someSelected
              ? _buildBulkActionButton(branch, subject, groupKeys.where((k) => _selectedStudentKeys.contains(k)).toList())
              : null,
          children: students.map((s) {
            final key = '${branch}_${subject}_${s['id']}';
            final isSelected = _selectedStudentKeys.contains(key);
            final tasks = _studentTasks[key] ?? [];
            return _buildStudentRow(branch, subject, s, key, isSelected, tasks);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildBulkActionButton(String branch, String subject, List<String> selectedKeys) {
    return TextButton.icon(
      onPressed: () => _showTaskAssignBottomSheet(keys: selectedKeys),
      icon: const Icon(Icons.playlist_add, size: 16),
      label: Text('${selectedKeys.length} Kişiye Görev', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.indigo,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildStudentRow(String branch, String subject, Map<String, dynamic> s, String key, bool isSelected, List<Map<String, dynamic>> tasks) {
    final notified = _parentNotified[key] ?? false;

    // ── Auto-derive status from tasks ──
    final hasTasks = tasks.isNotEmpty;
    final statusLabel = hasTasks ? 'Planlandı' : 'Beklemede';
    final statusColor = hasTasks ? Colors.blue : Colors.grey;

    // ── Shared: task badges ──
    Widget taskBadges = tasks.isEmpty
        ? const SizedBox.shrink()
        : Wrap(
            spacing: 4,
            runSpacing: 4,
            children: tasks.map((t) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: t['done'] == true ? Colors.green.shade50 : Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: t['done'] == true ? Colors.green.shade200 : Colors.indigo.shade100),
              ),
              child: Text(t['label'], style: TextStyle(
                fontSize: 10,
                color: t['done'] == true ? Colors.green.shade800 : Colors.indigo.shade700,
                fontWeight: FontWeight.w600,
              )),
            )).toList(),
          );

    // ── Shared: auto status badge (read-only) ──
    Widget statusBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor.shade700)),
        ],
      ),
    );

    Widget parentBtn = Tooltip(
      message: notified ? 'Veli bilgilendirildi' : 'Veli bilgilendirmesi yap',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _parentNotified[key] = !notified),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: notified ? Colors.green.shade50 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: notified ? Colors.green.shade300 : Colors.grey.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                notified ? Icons.family_restroom : Icons.family_restroom_outlined,
                size: 16,
                color: notified ? Colors.green.shade700 : Colors.grey.shade500,
              ),
              const SizedBox(width: 5),
              Text(
                notified ? 'Bilgilendirildi' : 'Veli',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: notified ? Colors.green.shade700 : Colors.grey.shade600,
                ),
              ),
              if (notified) ...[ 
                const SizedBox(width: 4),
                Icon(Icons.check_circle, size: 12, color: Colors.green.shade600),
              ],
            ],
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        if (isMobile) {
          // ── MOBILE: Card layout ──
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: isSelected ? Colors.indigo.shade50 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? Colors.indigo.shade200 : Colors.grey.shade200,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => isSelected ? _selectedStudentKeys.remove(key) : _selectedStudentKeys.add(key)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: checkbox + avatar + name + success%
                    Row(
                      children: [
                        Checkbox(
                          value: isSelected,
                          activeColor: Colors.indigo,
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          onChanged: (_) => setState(() => isSelected ? _selectedStudentKeys.remove(key) : _selectedStudentKeys.add(key)),
                        ),
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: isSelected ? Colors.indigo.shade200 : Colors.indigo.shade100,
                          child: Text(
                            (s['name'] as String? ?? '?').isNotEmpty ? (s['name'] as String)[0] : '?',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s['name'] ?? '',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.red.shade100),
                                    ),
                                    child: Text(
                                      '%${(s['success'] as double).toStringAsFixed(1)} Başarı',
                                      style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Görev Ata
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => _showTaskAssignBottomSheet(keys: [key]),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.indigo.shade100),
                            ),
                            child: Icon(Icons.add_task_rounded, size: 20, color: Colors.indigo.shade700),
                          ),
                        ),
                      ],
                    ),
                    // Task badges
                    if (tasks.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      taskBadges,
                    ],
                    const SizedBox(height: 10),
                    // Bottom row: status badge + parent notification
                    Row(
                      children: [
                        statusBadge,
                        const SizedBox(width: 8),
                        Expanded(child: parentBtn),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // ── DESKTOP: Single row layout ──
        return Material(
          color: isSelected ? Colors.indigo.shade50 : Colors.white,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => isSelected ? _selectedStudentKeys.remove(key) : _selectedStudentKeys.add(key)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Checkbox(
                    value: isSelected,
                    activeColor: Colors.indigo,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    onChanged: (_) => setState(() => isSelected ? _selectedStudentKeys.remove(key) : _selectedStudentKeys.add(key)),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.indigo.shade100,
                    child: Text(
                      (s['name'] as String? ?? '?').isNotEmpty ? (s['name'] as String)[0] : '?',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text('Başarı: %${(s['success'] as double).toStringAsFixed(1)}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                            if (tasks.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              taskBadges,
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_task_rounded, size: 20),
                    color: Colors.indigo,
                    tooltip: 'Görev Ata',
                    onPressed: () => _showTaskAssignBottomSheet(keys: [key]),
                  ),
                  statusBadge,
                  const SizedBox(width: 8),
                  parentBtn,
                ],
              ),
            ),
          ),
        );
      },
    );
  }


  void _showTaskAssignBottomSheet({required List<String> keys}) {
    final Set<String> selectedTypes = {};

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              Text(keys.length > 1 ? '${keys.length} Öğrenciye Görev Ata' : 'Görev Ata',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
              const SizedBox(height: 8),
              Text('Atanacak görev türlerini seçin', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              const SizedBox(height: 24),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.2,
                physics: const NeverScrollableScrollPhysics(),
                children: _taskTypes.map((t) {
                  final isSelected = selectedTypes.contains(t['type']);
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => setSheet(() =>
                        isSelected ? selectedTypes.remove(t['type']) : selectedTypes.add(t['type'] as String)),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.indigo : Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isSelected ? Colors.indigo : Colors.indigo.shade100),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(t['icon'] as IconData, size: 26,
                              color: isSelected ? Colors.white : Colors.indigo.shade600),
                          const SizedBox(height: 8),
                          Text(t['label'] as String,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? Colors.white : Colors.indigo.shade900)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: selectedTypes.isEmpty ? null : () {
                    setState(() {
                      for (final key in keys) {
                        _studentTasks.putIfAbsent(key, () => []);
                        for (final type in selectedTypes) {
                          final taskDef = _taskTypes.firstWhere((t) => t['type'] == type);
                          final alreadyHas = _studentTasks[key]!.any((t) => t['type'] == type);
                          if (!alreadyHas) {
                            _studentTasks[key]!.add({'type': type, 'label': taskDef['label'], 'done': false});
                          }
                        }
                      }
                    });
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: Text(
                    selectedTypes.isEmpty ? 'Görev Seçin' : '${selectedTypes.length} Görevi Ata',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.indigo.shade100,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMultiSelectFilter(String hint, List<String> selected, List<String> all, Function(List<String>) onChanged, IconData icon, {double? width}) {
    bool isAll = selected.length == all.length && all.isNotEmpty;
    bool hasSelection = selected.isNotEmpty;

    return Container(
      width: width,
      height: 44,
      decoration: BoxDecoration(
        color: hasSelection ? Colors.indigo.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hasSelection ? Colors.indigo.shade200 : Colors.grey.shade200),
        boxShadow: hasSelection ? [BoxShadow(color: Colors.indigo.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))] : null,
      ),
      child: PopupMenuButton<String>(
        tooltip: '$hint Filtrele',
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        borderRadius: BorderRadius.circular(12),
        offset: const Offset(0, 50),
        onSelected: (val) {
          List<String> next = List.from(selected);
          if (val == 'ALL') {
            next = isAll ? [] : List.from(all);
          } else {
            next.contains(val) ? next.remove(val) : next.add(val);
          }
          onChanged(next);
        },
        itemBuilder: (c) => [
          PopupMenuItem(
            value: 'ALL',
            child: Row(
              children: [
                Checkbox(
                  value: isAll,
                  onChanged: null,
                  activeColor: Colors.indigo,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                const Text('Tümü', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          ),
          const PopupMenuDivider(),
          ...all.map((e) => PopupMenuItem(
            value: e,
            child: Row(
              children: [
                Checkbox(
                  value: selected.contains(e),
                  onChanged: null,
                  activeColor: Colors.indigo,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                Expanded(child: Text(e, style: const TextStyle(fontSize: 13))),
              ],
            ),
          )),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(icon, size: 16, color: hasSelection ? Colors.indigo.shade700 : Colors.grey.shade600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isAll ? 'Tümü' : (hasSelection ? '${selected.length} Seçili' : hint),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: hasSelection ? FontWeight.bold : FontWeight.normal,
                    color: hasSelection ? Colors.indigo.shade900 : Colors.grey.shade700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.keyboard_arrow_down, size: 16, color: hasSelection ? Colors.indigo.shade700 : Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThresholdCard(String subject) {
    double value = _subjectThresholds[subject] ?? 70.0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(subject, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
                child: Text('%${value.round()}', style: TextStyle(color: Colors.indigo.shade900, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: value,
              min: 0,
              max: 100,
              divisions: 20,
              activeColor: Colors.indigo,
              inactiveColor: Colors.indigo.withOpacity(0.1),
              onChanged: (v) => setState(() => _subjectThresholds[subject] = v),
            ),
          ),
        ],
      ),
    );
  }

  void _showSelectionBottomSheet({
    required String title,
    required List<String> options,
    required String current,
    required Function(String) onSelected,
    String? fieldKey,
  }) {
    bool isManual = fieldKey != null && current.isNotEmpty && !options.contains(current);
    final manualController = TextEditingController(text: isManual ? current : '');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 30,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
              const SizedBox(height: 24),
              if (!isManual)
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (c, i) => Divider(color: Colors.grey.shade100, height: 1),
                    itemBuilder: (context, index) {
                      final opt = options[index];
                      final isSelected = opt == current;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        title: Text(
                          opt,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.indigo : Colors.black87,
                          ),
                        ),
                        trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.indigo) : null,
                        onTap: () {
                          if (opt == 'Diğer' && fieldKey != null) {
                            setModalState(() => isManual = true);
                          } else {
                            onSelected(opt);
                            Navigator.pop(context);
                          }
                        },
                      );
                    },
                  ),
                )
              else
                Column(
                  children: [
                    TextField(
                      controller: manualController,
                      autofocus: true,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Eylem planınızı buraya detaylıca yazabilirsiniz...',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                        filled: false,
                        contentPadding: const EdgeInsets.all(20),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Colors.indigo, width: 2),
                        ),
                      ),
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => setModalState(() => isManual = false),
                            child: const Text('Geri Dön', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () {
                              if (manualController.text.trim().isNotEmpty) {
                                onSelected(manualController.text.trim());
                                Navigator.pop(context);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Kaydet ve Tamamla', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProblemSourceDropdown(String key) {
    final sources = [
      'Kazanım için gerekli olan önceki sınıf/konu bilgileri şubenin çoğunda eksik.',
      'Kazanımın temel kavramları şubenin büyük bir bölümü tarafından yanlış öğrenilmiş veya hatalı yorumlanmıştır.',
      'Kazanılan bilgiyi kullanmaya yönelik yeterli sınıf içi/ek alıştırma yapılmamış.',
      'Kullanılan öğretim yöntemi (anlatım, materyal vb.) şubenin öğrenme stillerine uygun değil.',
      'Sorular çeldiricili, ifade/dil anlaşılırlığı düşük veya zaman yönetimi sorunu var.',
      'Şubenin genelindeki dikkat dağınıklığı veya olumsuz tutumun öğrenmeye yansıması.',
      'Konu yetişmedi.',
      'Müfredat dışı.',
      'Soru anlaşılmadı.',
    ];
    String current = _branchActionPlans[key]?['problemSource'] ?? '';
    
    return InkWell(
      onTap: () => _showSelectionBottomSheet(
        title: 'Problem Kaynağı Seçin',
        options: sources,
        current: current,
        onSelected: (val) => setState(() {
          _branchActionPlans[key]!['problemSource'] = val;
          _updateStatus(key);
        }),
      ),
      child: Container(
        height: 40,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                current == '' ? 'Seçiniz' : current,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: current == '' ? Colors.grey : Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, color: Colors.indigo, size: 18),
          ],
        ),
      ),
    );
  }

  void _updateStatus(String key) {
    final plan = _branchActionPlans[key]!;
    final problem = plan['problemSource'] ?? '';
    final action = plan['actionPlan'] ?? '';
    final currentStatus = plan['status'] ?? 'Belirlenmedi';

    // Auto-update if in early stages
    if (currentStatus == 'Belirlenmedi' || currentStatus == 'Problem Belirlendi' || currentStatus == 'Eylem Planı Hazır') {
      if (action.isNotEmpty && action != ' ') {
        plan['status'] = 'Eylem Planı Hazır';
      } else if (problem.isNotEmpty && problem != ' ') {
        plan['status'] = 'Problem Belirlendi';
      } else {
        plan['status'] = 'Belirlenmedi';
      }
    }
  }

  Widget _buildActionPlanField(String key) {
    String current = _branchActionPlans[key]?['actionPlan'] ?? '';
    bool isOther = current.isNotEmpty && !_predefinedActionPlans.contains(current) && current != ' ';

    return InkWell(
      onTap: () {
        final problem = _branchActionPlans[key]?['problemSource'] ?? '';
        if (problem.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Lütfen önce problem kaynağını belirleyin.'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }
        _showSelectionBottomSheet(
          title: 'Eylem Planı Seçin',
          options: _predefinedActionPlans,
          current: current,
          fieldKey: key,
          onSelected: (val) => setState(() {
            _branchActionPlans[key]!['actionPlan'] = val;
            _updateStatus(key);
          }),
        );
      },
      child: Container(
        height: 40,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                current.isEmpty ? 'Eylem planı seçiniz' : (isOther ? 'Özel: $current' : current),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: current.isEmpty ? Colors.grey : (isOther ? Colors.indigo.shade700 : Colors.black87),
                  fontWeight: isOther ? FontWeight.bold : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, color: Colors.indigo, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String key) {
    String current = _branchActionPlans[key]?['status'] ?? 'Belirlenmedi';
    
    final colorMap = {
      'Belirlenmedi': Colors.grey,
      'Problem Belirlendi': Colors.orange,
      'Eylem Planı Hazır': Colors.blue,
      'Uygulanıyor': Colors.indigo,
      'Tamamlandı': Colors.green,
    };
    final color = colorMap[current] ?? Colors.grey;
    final canToggle = current == 'Uygulanıyor' || current == 'Tamamlandı';

    return InkWell(
      onTap: !canToggle ? null : () {
        setState(() {
          _branchActionPlans[key]!['status'] = current == 'Uygulanıyor' ? 'Tamamlandı' : 'Uygulanıyor';
        });
      },
      child: Container(
        width: double.infinity,
        height: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                current.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: color.shade900,
                  letterSpacing: 0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (canToggle) ...[
              const SizedBox(width: 4),
              Icon(Icons.sync_alt_rounded, size: 14, color: color.shade600),
            ],
          ],
        ),
      ),
    );
  }

  String _getTeacherName(String branch, String subject) {
    // 1. Exact branch + subject match
    final exact = _branchTeachers[branch]?[subject];
    if (exact != null) return exact;

    // 2. Try subject-only fallback (for general accounts where branch may differ)
    final fallback = _subjectTeacherFallback[subject];
    if (fallback != null) return fallback;

    return 'Öğretmen Atanmamış';
  }

  // _buildStudentTaskButton and _buildStudentStatusDropdown are now inlined in _buildStudentRow

  Widget _buildHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.indigo)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildEmptyState(String message, {IconData icon = Icons.info_outline}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: Colors.indigo),
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  String _getMonthName(int month) {
    const months = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
    return months[month - 1];
  }

  String _getMonthFullName(int month) {
    const months = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
    return months[month - 1];
  }
}
