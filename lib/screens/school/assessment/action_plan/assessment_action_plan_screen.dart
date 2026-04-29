import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../services/assessment_service.dart';
import '../../../../models/assessment/trial_exam_model.dart';
import '../../../../models/lesson_model.dart';
import '../../../../widgets/edukn_logo.dart';

class AssessmentActionPlanScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const AssessmentActionPlanScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  _AssessmentActionPlanScreenState createState() =>
      _AssessmentActionPlanScreenState();
}

class _AssessmentActionPlanScreenState extends State<AssessmentActionPlanScreen>
    with SingleTickerProviderStateMixin {
  final AssessmentService _service = AssessmentService();
  late TabController _tabController;

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadInitialData();
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text.toLowerCase();
          _filterExams();
        });
      }
    });
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
        }
      });

      // Load Lesson Assignments for Teachers
      final assignmentsSnapshot = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true)
          .get();

      Map<String, Map<String, String>> teacherMap = {};
      for (var doc in assignmentsSnapshot.docs) {
        final data = doc.data();
        String className = data['className'] ?? '';
        String lessonName = data['lessonName'] ?? '';
        List<dynamic> teacherNames = data['teacherNames'] ?? [];
        
        if (className.isNotEmpty && lessonName.isNotEmpty && teacherNames.isNotEmpty) {
          teacherMap.putIfAbsent(className, () => {});
          teacherMap[className]![lessonName] = teacherNames.join(', ');
        }
      }

      if (mounted) {
        setState(() {
          _branchTeachers = teacherMap;
        });
      }
    } catch (e) {
      print('Error loading initial data: $e');
      if (mounted) setState(() => _isLoading = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Eylem Planları', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 4,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: '1. SINAV & EŞİK'),
            Tab(text: '2. ŞUBE EYLEM PLANI'),
            Tab(text: '3. ÖĞRENCİ TAKİBİ'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: EduKnLoader(size: 80))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildStep1Selection(),
                _buildStep2BranchPlans(),
                _buildStep3StudentPlans(),
              ],
            ),
    );
  }

  Widget _buildStep1Selection() {
    final levels = _allExams.map((e) => e.classLevel).toSet().toList()..sort();
    return Row(
      children: [
        Container(
          width: 380,
          decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.indigo.shade900, Colors.indigo.shade800])),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedClassLevel,
                          dropdownColor: Colors.indigo.shade800,
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Tümü', style: TextStyle(color: Colors.white, fontSize: 13))),
                            ...levels.map((l) => DropdownMenuItem(value: l, child: Text('$l. Sınıf', style: const TextStyle(color: Colors.white, fontSize: 13)))),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _selectedClassLevel = val;
                              _filterExams();
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(hintText: 'Sınav ara...', hintStyle: TextStyle(color: Colors.white54, fontSize: 12), border: InputBorder.none),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _filteredExams.isEmpty
                    ? const Center(child: Text('Sınav bulunamadı'))
                    : ListView.separated(
                        itemCount: _filteredExams.length,
                        separatorBuilder: (c, i) => Divider(height: 1),
                        itemBuilder: (context, index) {
                          final exam = _filteredExams[index];
                          return CheckboxListTile(
                            value: _selectedExamIds.contains(exam.id),
                            onChanged: (_) => _onExamSelected(exam.id),
                            title: Text(exam.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _selectedExamIds.isEmpty
              ? _buildEmptyState('Lütfen eylem planı oluşturmak için en az bir sınav seçin.')
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader('Başarı Eşikleri', 'Branş bazlı başarı hedeflerinizi belirleyin.'),
                      const SizedBox(height: 24),
                      Expanded(
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 2.2, crossAxisSpacing: 16, mainAxisSpacing: 16),
                          itemCount: _availableSubjects.length,
                          itemBuilder: (context, index) => _buildThresholdCard(_availableSubjects[index]),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildStep2BranchPlans() {
    if (_selectedExamIds.isEmpty) return _buildEmptyState('Lütfen önce sınav seçimi yapın.');
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _buildHeader('Şube Eylem Planları', 'Düşük başarı gösterilen kazanımlar için eylem planı belirleyin.')),
              _buildMultiSelectFilter('Şube', _selectedViewBranches, _outcomeStats.keys.toList()..sort(), (v) => setState(() => _selectedViewBranches = v), Icons.business, width: 180),
              const SizedBox(width: 12),
              _buildMultiSelectFilter('Branş', _selectedViewSubjects, _availableSubjects, (v) => setState(() => _selectedViewSubjects = v), Icons.book, width: 200),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(child: _buildMultiFilteredOutcomeTable()),
        ],
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
        cards.add(Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Chip(label: Text(branch, style: const TextStyle(color: Colors.white)), backgroundColor: Colors.indigo.shade900),
                const SizedBox(width: 8),
                Text(subject, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 16),
              ...sorted.map((e) => _buildOutcomeRow(branch, subject, e.key, e.value, threshold)).toList(),
            ],
          ),
        ));
      }
    }
    return cards.isEmpty ? _buildEmptyState('Veri bulunamadı.') : ListView(children: cards);
  }

  Widget _buildOutcomeRow(String branch, String subject, String outcome, Map<String, dynamic> data, double threshold) {
    double success = data['total'] > 0 ? (data['correct'] / data['total']) * 100 : 0.0;
    bool isLow = success < threshold;
    String key = '${branch}_${subject}_$outcome';
    _branchActionPlans.putIfAbsent(key, () => {'problemSource': '', 'actionPlan': '', 'status': 'Belirlenmedi'});
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          ListTile(
            title: Text(outcome, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Öğretmen: ${_getTeacherName(branch, subject)} | %${success.toStringAsFixed(1)} Başarı'),
            trailing: Chip(label: Text(isLow ? 'KRİTİK' : 'YETERLİ', style: const TextStyle(color: Colors.white, fontSize: 10)), backgroundColor: isLow ? Colors.red : Colors.green),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(child: _buildProblemSourceDropdown(key)),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: _buildActionPlanField(key)),
                const SizedBox(width: 12),
                _buildStatusDropdown(key),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep3StudentPlans() {
    if (_selectedExamIds.isEmpty) return _buildEmptyState('Lütfen önce sınav seçimi yapın.');
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildHeader('Öğrenci Takibi', 'Ders bazlı barajın altında kalan öğrenciler.')),
              _buildMultiSelectFilter('Şube', _selectedViewBranches, _outcomeStats.keys.toList()..sort(), (v) => setState(() => _selectedViewBranches = v), Icons.business, width: 180),
              const SizedBox(width: 12),
              _buildMultiSelectFilter('Branş', _selectedViewSubjects, _availableSubjects, (v) => setState(() => _selectedViewSubjects = v), Icons.book, width: 200),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(child: subjectCards.isEmpty ? _buildEmptyState('Öğrenci bulunamadı.') : ListView.builder(itemCount: subjectCards.length, itemBuilder: (c, i) => subjectCards[i])),
        ],
      ),
    );
  }

  Widget _buildStudentSubjectGroupCard(String branch, String subject, List<Map<String, dynamic>> students) {
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      child: ExpansionTile(
        title: Text('$branch - $subject (${students.length} Öğrenci)', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
        children: students.map((s) => ListTile(
          leading: CircleAvatar(child: Text(s['no']?.toString() ?? '?')),
          title: Text(s['name']),
          subtitle: Text('Başarı: %${(s['success'] as double).toStringAsFixed(1)}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [_buildStudentTaskButton(s), const SizedBox(width: 8), _buildStudentStatusDropdown(s)],
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildMultiSelectFilter(String hint, List<String> selected, List<String> all, Function(List<String>) onChanged, IconData icon, {double? width}) {
    bool isAll = selected.length == all.length && all.isNotEmpty;
    return Container(
      width: width, height: 45,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: PopupMenuButton<String>(
        onSelected: (val) {
          List<String> next = List.from(selected);
          if (val == 'ALL') next = isAll ? [] : List.from(all);
          else next.contains(val) ? next.remove(val) : next.add(val);
          onChanged(next);
        },
        itemBuilder: (c) => [
          PopupMenuItem(value: 'ALL', child: Row(children: [Checkbox(value: isAll, onChanged: null), const Text('Tümü')])),
          ...all.map((e) => PopupMenuItem(value: e, child: Row(children: [Checkbox(value: selected.contains(e), onChanged: null), Text(e)]))),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [Icon(icon, size: 16), const SizedBox(width: 8), Expanded(child: Text(isAll ? 'Tümü' : '${selected.length} Seçili')), const Icon(Icons.expand_more)]),
        ),
      ),
    );
  }

  Widget _buildThresholdCard(String subject) {
    double value = _subjectThresholds[subject] ?? 70.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(subject), Text('%${value.round()}')]),
            Slider(value: value, min: 0, max: 100, divisions: 20, onChanged: (v) => setState(() => _subjectThresholds[subject] = v)),
          ],
        ),
      ),
    );
  }

  Widget _buildProblemSourceDropdown(String key) {
    String current = _branchActionPlans[key]?['problemSource'] ?? '';
    return DropdownButton<String>(
      value: current.isEmpty ? null : current,
      hint: const Text('Problem Kaynağı'),
      isExpanded: true,
      items: ['Konu eksikliği', 'Soru pratiği azlığı', 'Dikkat hatası', 'Süre yetersizliği', 'Kavram yanılgısı'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: (v) => setState(() => _branchActionPlans[key]!['problemSource'] = v),
    );
  }

  Widget _buildActionPlanField(String key) {
    String current = _branchActionPlans[key]?['actionPlan'] ?? '';
    bool isOther = current.isNotEmpty && !_predefinedActionPlans.contains(current) && current != ' ';

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.indigo.shade100),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: isOther ? 'Diğer' : (current.isEmpty ? null : current),
                hint: const Text('Eylem planı seçiniz', style: TextStyle(fontSize: 12)),
                isExpanded: true,
                items: _predefinedActionPlans
                    .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(e,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12))))
                    .toList(),
                onChanged: (val) {
                  setState(() {
                    if (val == 'Diğer') {
                      _branchActionPlans[key]!['actionPlan'] = ' '; // Signal to show textfield
                    } else {
                      _branchActionPlans[key]!['actionPlan'] = val;
                    }
                  });
                },
              ),
            ),
          ),
        ),
        if (isOther || current == ' ') ...[
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.indigo.shade100),
              ),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Eylem planı yazın...',
                  hintStyle: TextStyle(fontSize: 12),
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 12),
                onChanged: (val) {
                  _branchActionPlans[key]!['actionPlan'] = val;
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _getTeacherName(String branch, String subject) {
    return _branchTeachers[branch]?[subject] ?? 'Öğretmen Atanmamış';
  }

  Widget _buildStudentTaskButton(Map<String, dynamic> student) {
    return IconButton(
      icon: const Icon(Icons.add_task, color: Colors.indigo, size: 20),
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${student['name']} için görev atama özelliği yakında eklenecek.')),
        );
      },
      tooltip: 'Görev Ata',
    );
  }

  Widget _buildStudentStatusDropdown(Map<String, dynamic> student) {
    // This could be linked to a state map if persistence is needed
    String currentStatus = 'Beklemede';
    return Container(
      width: 130,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentStatus,
          isExpanded: true,
          style: const TextStyle(fontSize: 11, color: Colors.black87),
          items: ['Beklemede', 'Planlandı', 'Uygulandı', 'Tamamlandı'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) {
            // Update status logic
          },
        ),
      ),
    );
  }

  Widget _buildStatusDropdown(String key) {
    String current = _branchActionPlans[key]?['status'] ?? 'Belirlenmedi';
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: current == 'Tamamlandı' ? Colors.green.shade50 : (current == 'Devam Ediyor' ? Colors.orange.shade50 : Colors.grey.shade100),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: current == 'Tamamlandı' ? Colors.green.shade200 : (current == 'Devam Ediyor' ? Colors.orange.shade200 : Colors.transparent)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: current,
          icon: const Icon(Icons.arrow_drop_down, color: Colors.indigo),
          isExpanded: true,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: current == 'Tamamlandı' ? Colors.green.shade700 : (current == 'Devam Ediyor' ? Colors.orange.shade700 : Colors.grey.shade700),
          ),
          items: [
            'Belirlenmedi',
            'Devam Ediyor',
            'Tamamlandı',
          ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (val) {
            setState(() {
              _branchActionPlans[key]!['status'] = val;
            });
          },
        ),
      ),
    );
  }

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
