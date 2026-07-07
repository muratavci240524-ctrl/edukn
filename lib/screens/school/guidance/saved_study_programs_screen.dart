import 'package:flutter/material.dart';
import '../../../../services/guidance_service.dart';
import 'study_program_printing_helper.dart';
import 'study_program_detail_screen.dart';
import 'guidance_study_program_screen.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SavedStudyProgramsScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final bool isTeacher;
  final List<String>? allowedClassNames;
  final List<String>? allowedStudentIds;

  const SavedStudyProgramsScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    this.isTeacher = false,
    this.allowedClassNames,
    this.allowedStudentIds,
  });

  @override
  State<SavedStudyProgramsScreen> createState() =>
      _SavedStudyProgramsScreenState();
}

class _SavedStudyProgramsScreenState extends State<SavedStudyProgramsScreen> {
  final _guidanceService = GuidanceService();
  List<Map<String, dynamic>> _programs = [];
  String _searchQuery = '';
  String? _selectedExamFilter;
  String? _selectedBranchFilter;
  Set<String> _selectedProgramIds = {};
  bool _isLoading = true;
  bool _isSelectionMode = false;
  final TextEditingController _searchController = TextEditingController();
  final Map<String, String> _studentBranchCache =
      {}; // Cache for studentId -> branch

  DateTime _selectedDate = DateTime.now();
  bool _isAllTime = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    setState(() => _isLoading = true);
    await Future.wait([_fetchStudentCache(), _fetchPrograms()]);
    setState(() => _isLoading = false);
  }

  Future<void> _fetchStudentCache() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true)
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();

        // Use the most robust extraction for the cache
        String rawBranch =
            (data['studentBranch'] ??
                    data['className'] ??
                    data['branch'] ??
                    data['sube'] ??
                    data['shube'] ??
                    data['class'] ??
                    data['studentClass'] ??
                    data['class_name'] ??
                    data['studentGroup'] ??
                    '')
                .toString()
                .trim();

        final rawLevel = (data['classLevel'] ?? data['level'] ?? '')
            .toString()
            .trim();
        String className = rawBranch;

        if (className.isEmpty) {
          className = rawLevel.isNotEmpty ? "$rawLevel. Sınıf" : 'Sınıfsız';
        } else if (rawLevel.isNotEmpty) {
          String levelDigits = rawLevel.replaceAll(RegExp(r'[^0-9]'), '');
          if (levelDigits.isNotEmpty && !className.contains(levelDigits)) {
            className = "$levelDigits-$className";
          }
        }
        _studentBranchCache[doc.id] = className;
      }
    } catch (e) {
      debugPrint('Error fetching student cache: $e');
    }
  }

  Future<void> _fetchPrograms() async {
    setState(() => _isLoading = true);
    try {
      final programs = await _guidanceService.getAllStudyPrograms(
        widget.institutionId,
      );
      setState(() {
        _programs = programs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  String _getBranchName(Map<String, dynamic> p) {
    String rawBranch =
        (p['studentBranch'] ??
                p['class'] ??
                p['className'] ??
                p['branch'] ??
                p['sube'] ??
                p['shube'] ??
                p['studentClass'] ??
                p['class_name'] ??
                p['studentGroup'] ??
                '')
            .toString()
            .trim();

    final rawLevel = (p['classLevel'] ?? p['level'] ?? '').toString().trim();
    String finalBranch = rawBranch;

    if (finalBranch == 'Sınıfsız' || finalBranch.isEmpty) {
      final studentId = p['studentId']?.toString();
      if (studentId != null && _studentBranchCache.containsKey(studentId)) {
        return _studentBranchCache[studentId]!;
      }
    }

    return finalBranch.isEmpty ? 'Sınıfsız' : finalBranch;
  }

  List<Map<String, dynamic>> get _filteredPrograms {
    return _programs.where((p) {
      if (widget.isTeacher) {
        bool branchMatch = true;
        bool studentMatch = true;

        if (widget.allowedClassNames != null) {
          final branch = _getBranchName(p);
          bool found = false;
          for (var allowed in widget.allowedClassNames!) {
            if (branch == allowed || branch.contains(allowed)) {
              found = true;
              break;
            }
          }
          branchMatch = found;
        }

        if (widget.allowedStudentIds != null) {
          final sId = p['studentId']?.toString();
          studentMatch = widget.allowedStudentIds!.contains(sId);
        }

        if (!branchMatch && !studentMatch) return false;
        // If both provided, usually we want students who are in those branches AND are the specific students, 
        // but often it's "OR" or just one of them is provided. 
        // Given the request "subeleri ve ogrencileri", it's safer to say if any check fails, return false if we want strict.
        // But usually "allowedStudentIds" is a subset of students in "allowedClassNames".
        if (widget.allowedStudentIds != null && !studentMatch) return false;
        if (widget.allowedClassNames != null && !branchMatch) return false;
      }

      // 1. Text Search
      final name = (p['studentName'] ?? '').toString().toLowerCase();
      if (_searchQuery.isNotEmpty &&
          !name.contains(_searchQuery.toLowerCase())) {
        return false;
      }

      // 2. Exam Filter
      if (_selectedExamFilter != null && p['examName'] != _selectedExamFilter) {
        return false;
      }

      // 3. Branch Filter
      if (_selectedBranchFilter != null) {
        final branch = _getBranchName(p);
        if (branch != _selectedBranchFilter) {
          return false;
        }
      }

      // 4. Date Filter (Month/Year)
      if (_isAllTime) return true;

      final date = (p['createdAt'] as dynamic)?.toDate();
      if (date == null) return false;

      return date.month == _selectedDate.month &&
          date.year == _selectedDate.year;
    }).toList();
  }

  List<String> get _uniqueExams {
    Set<String> exams = {};
    for (var p in _programs) {
      if (!_isAllTime) {
        final date = (p['createdAt'] as dynamic)?.toDate();
        if (date != null) {
          if (date.month != _selectedDate.month ||
              date.year != _selectedDate.year) {
            continue;
          }
        }
      }
      final name = p['examName'] as String?;
      if (name != null && name.isNotEmpty) exams.add(name);
    }
    return exams.toList()..sort();
  }

  List<String> get _uniqueBranches {
    Set<String> branches = {};
    for (var p in _programs) {
      if (!_isAllTime) {
        final date = (p['createdAt'] as dynamic)?.toDate();
        if (date != null) {
          if (date.month != _selectedDate.month ||
              date.year != _selectedDate.year) {
            continue;
          }
        }
      }
      // Check all possible branch fields for maximum compatibility
      final branch = _getBranchName(p);
      if (branch != 'Bilinmiyor') branches.add(branch);
    }
    return branches.toList()..sort();
  }

  void _toggleSelectAll() {
    final filtered = _filteredPrograms;
    setState(() {
      if (_selectedProgramIds.length == filtered.length) {
        _selectedProgramIds.clear();
      } else {
        _selectedProgramIds = filtered.map((p) => p['id'] as String).toSet();
      }
    });
  }

  Future<void> _deleteSelectedPrograms() async {
    if (_selectedProgramIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Programları Sil'),
        content: Text(
          '${_selectedProgramIds.length} adet programı silmek istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      for (var id in _selectedProgramIds) {
        await _guidanceService.deleteStudyProgram(widget.institutionId, id);
      }

      setState(() {
        _selectedProgramIds.clear();
        _isSelectionMode = false;
      });

      await _fetchPrograms();

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Seçilen programlar silindi.')));
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Silme Hatası: $e')));
      }
    }
  }

  Future<void> _deleteSingleProgram(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Programı Sil'),
        content: Text(
          'Bu çalışma programını silmek istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      await _guidanceService.deleteStudyProgram(widget.institutionId, id);
      await _fetchPrograms();

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Program silindi.')));
      }
    } catch (e) {
      print('Error deleting program: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteFilteredPrograms() async {
    final filtered = _filteredPrograms;
    if (filtered.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Filtrelenenleri Sil'),
        content: Text(
          'Şu an listelenen ${filtered.length} adet programın tamamını silmek istediğinize emin misiniz?\n\nBu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Tümünü Sil'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      int count = 0;
      for (var p in filtered) {
        final id = p['id'];
        if (id != null) {
          await _guidanceService.deleteStudyProgram(widget.institutionId, id);
          count++;
        }
      }

      await _fetchPrograms();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count adet program başarıyla silindi.')),
        );
      }
    } catch (e) {
      print('Error deleting filtered programs: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _regenerateProgram(Map<String, dynamic> program) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GuidanceStudyProgramScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          initialStudentId: program['studentId'],
          initialExamName: program['examName'],
          initialThresholds: (program['thresholds'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int)),
        ),
      ),
    );
  }

  Future<void> _printSelectedPrograms() async {
    if (_selectedProgramIds.isEmpty) return;

    List<Map<String, dynamic>> selected = _programs
        .where((p) => _selectedProgramIds.contains(p['id']))
        .toList();

    await StudyProgramPrintingHelper.generateBulkPdf(
      context,
      selected,
      // Default options for bulk print
      includeSchedule: true,
      includeAnalysis: true,
      showPriority1: true,
      showPriority2: true,
    );
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedProgramIds.contains(id)) {
        _selectedProgramIds.remove(id);
        if (_selectedProgramIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedProgramIds.add(id);
        _isSelectionMode = true;
      }
    });
  }

  Map<String, dynamic> _calculateStats() {
    int total = _programs.length;
    int displayedCount = _filteredPrograms.length;

    // Calculate simple completion status for displayed programs
    int totalTasks = 0;
    int completedTasks = 0;

    for (var p in _filteredPrograms) {
      if (p['executionStatus'] != null) {
        final statusMap = p['executionStatus'] as Map<String, dynamic>;
        statusMap.forEach((key, val) {
          final list = List<int>.from(val as List);
          totalTasks += list.length;
          completedTasks += list.where((s) => s == 1).length; // 1 = Done
        });
      }
    }

    int completionRate = totalTasks > 0
        ? ((completedTasks / totalTasks) * 100).round()
        : 0;

    return {
      'total': total,
      'displayed': displayedCount,
      'completionRate': completionRate,
    };
  }

  void _showStatsDialog() {
    // 1. Group stats by teacher
    // Map<TeacherName, { 'assigned': int, 'evaluated': int }>
    Map<String, Map<String, int>> teacherFeedbackStats = {};

    // 2. Group stats by student for risk analysis
    // Map<StudentName, { 'totalTasks': int, 'completedTasks': int, 'missedTasks': int, 'incompleteTasks': int, 'branch': String }>
    Map<String, Map<String, dynamic>> studentRiskStats = {};

    for (var p in _filteredPrograms) {
      // 1. Teacher feedback calculation
      String teacher = p['creatorName'] ?? 'Bilinmiyor';
      bool hasEvaluation = p['mentorEvaluation'] != null && p['mentorEvaluation'].toString().trim().isNotEmpty;
      
      teacherFeedbackStats.putIfAbsent(teacher, () => {'assigned': 0, 'evaluated': 0});
      teacherFeedbackStats[teacher]!['assigned'] = teacherFeedbackStats[teacher]!['assigned']! + 1;
      if (hasEvaluation) {
        teacherFeedbackStats[teacher]!['evaluated'] = teacherFeedbackStats[teacher]!['evaluated']! + 1;
      }

      // 2. Student task completion calculation
      String student = p['studentName'] ?? 'Bilinmiyor';
      String branch = _getBranchName(p);
      
      int totalTasks = 0;
      int completedTasks = 0;
      int missedTasks = 0;
      int incompleteTasks = 0;

      if (p['executionStatus'] != null) {
        final statusMap = p['executionStatus'] as Map<String, dynamic>;
        statusMap.forEach((key, val) {
          final list = List<int>.from(val as List);
          totalTasks += list.length;
          completedTasks += list.where((s) => s == 1).length;
          incompleteTasks += list.where((s) => s == 2).length;
          missedTasks += list.where((s) => s == 3).length;
        });
      }

      studentRiskStats.putIfAbsent(student, () => {
        'totalTasks': 0,
        'completedTasks': 0,
        'missedTasks': 0,
        'incompleteTasks': 0,
        'branch': branch,
      });

      studentRiskStats[student]!['totalTasks'] = studentRiskStats[student]!['totalTasks'] + totalTasks;
      studentRiskStats[student]!['completedTasks'] = studentRiskStats[student]!['completedTasks'] + completedTasks;
      studentRiskStats[student]!['incompleteTasks'] = studentRiskStats[student]!['incompleteTasks'] + incompleteTasks;
      studentRiskStats[student]!['missedTasks'] = studentRiskStats[student]!['missedTasks'] + missedTasks;
    }

    // Sort teachers by assigned programs descending
    var sortedTeachers = teacherFeedbackStats.entries.toList()
      ..sort((a, b) => b.value['assigned']!.compareTo(a.value['assigned']!));

    // Sort students by missed/incomplete tasks descending (high-risk first)
    var sortedStudents = studentRiskStats.entries.toList()
      ..sort((a, b) {
        int missedA = a.value['missedTasks'] + a.value['incompleteTasks'];
        int missedB = b.value['missedTasks'] + b.value['incompleteTasks'];
        return missedB.compareTo(missedA);
      });

    showDialog(
      context: context,
      builder: (ctx) {
        return DefaultTabController(
          length: 2,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            titlePadding: const EdgeInsets.all(0),
            title: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                color: Colors.indigo,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Mentör Çalışmaları Analiz Paneli",
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${DateFormat('MMMM yyyy', 'tr_TR').format(_selectedDate)} İnceleme Dönemi",
                    style: TextStyle(color: Colors.indigo.shade100, fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  const TabBar(
                    indicatorColor: Colors.white,
                    indicatorWeight: 3,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    tabs: [
                      Tab(text: "Mentör Geri Bildirim Oranları"),
                      Tab(text: "Riskli Öğrenci Analizi"),
                    ],
                  ),
                ],
              ),
            ),
            content: SizedBox(
              width: 600,
              height: 400,
              child: TabBarView(
                children: [
                  // Tab 1: Mentor Feedback Rate List
                  sortedTeachers.isEmpty
                      ? const Center(child: Text("Değerlendirilecek mentör verisi bulunamadı.", style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 8),
                          itemCount: sortedTeachers.length,
                          itemBuilder: (context, index) {
                            final entry = sortedTeachers[index];
                            final teacherName = entry.key;
                            final assigned = entry.value['assigned']!;
                            final evaluated = entry.value['evaluated']!;
                            final rate = assigned > 0 ? ((evaluated / assigned) * 100).round() : 0;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: rate > 75 ? Colors.green.shade50 : (rate > 40 ? Colors.orange.shade50 : Colors.red.shade50),
                                  child: Text(
                                    "%$rate",
                                    style: TextStyle(
                                      color: rate > 75 ? Colors.green : (rate > 40 ? Colors.orange : Colors.red),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                title: Text(teacherName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                subtitle: Text("Oluşturulan: $assigned program • Geri Bildirim: $evaluated adet"),
                                trailing: Icon(
                                  rate > 75 ? Icons.check_circle : (rate > 40 ? Icons.warning : Icons.error),
                                  color: rate > 75 ? Colors.green : (rate > 40 ? Colors.orange : Colors.red),
                                  size: 20,
                                ),
                              ),
                            );
                          },
                        ),

                  // Tab 2: High Risk Students (Accruing missed tasks)
                  sortedStudents.isEmpty
                      ? const Center(child: Text("Değerlendirilecek öğrenci verisi bulunamadı.", style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 8),
                          itemCount: sortedStudents.length,
                          itemBuilder: (context, index) {
                            final entry = sortedStudents[index];
                            final studentName = entry.key;
                            final total = entry.value['totalTasks'] as int;
                            final completed = entry.value['completedTasks'] as int;
                            final missed = entry.value['missedTasks'] as int;
                            final incomplete = entry.value['incompleteTasks'] as int;
                            final branch = entry.value['branch'] as String;

                            final totalFailed = missed + incomplete;
                            final failureRate = total > 0 ? ((totalFailed / total) * 100).round() : 0;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: failureRate > 30 ? Colors.red.shade50 : Colors.green.shade50,
                                  child: Icon(
                                    failureRate > 30 ? Icons.warning_amber_rounded : Icons.thumb_up_alt_rounded,
                                    color: failureRate > 30 ? Colors.red : Colors.green,
                                  ),
                                ),
                                title: Text(studentName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                subtitle: Text("Sınıf: $branch • Toplam Görev: $total\nTamamlanan: $completed • Aksatılan/Eksik: $totalFailed"),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      "%$failureRate",
                                      style: TextStyle(
                                        color: failureRate > 30 ? Colors.red : Colors.green,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const Text("Aksatma Oranı", style: TextStyle(fontSize: 8, color: Colors.grey)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Kapat", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.indigo,
          fontSize: 15,
        ),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    // Show a simple month/year picker dialog instead of a full calendar
    final DateTime? picked = await showDialog<DateTime>(
      context: context,
      builder: (ctx) {
        DateTime tempDate = _selectedDate;
        return AlertDialog(
          title: Text("Ay/Yıl Seçin"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.chevron_left),
                    onPressed: () {
                      tempDate = DateTime(tempDate.year - 1, tempDate.month);
                      (ctx as Element).markNeedsBuild();
                    },
                  ),
                  Text(
                    "${tempDate.year}",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  IconButton(
                    icon: Icon(Icons.chevron_right),
                    onPressed: () {
                      tempDate = DateTime(tempDate.year + 1, tempDate.month);
                      (ctx as Element).markNeedsBuild();
                    },
                  ),
                ],
              ),
              Divider(),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(12, (index) {
                  final month = index + 1;
                  final isSelected =
                      tempDate.month == month &&
                      tempDate.year == _selectedDate.year;
                  final monthName = DateFormat(
                    'MMM',
                    'tr_TR',
                  ).format(DateTime(2024, month));

                  return InkWell(
                    onTap: () =>
                        Navigator.pop(ctx, DateTime(tempDate.year, month)),
                    child: Container(
                      width: 60,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.indigo
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: isSelected
                            ? null
                            : Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        monthName,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("İptal"),
            ),
          ],
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      // After state update, check if filters are still valid
      if (!_uniqueExams.contains(_selectedExamFilter)) {
        setState(() => _selectedExamFilter = null);
      }
      if (!_uniqueBranches.contains(_selectedBranchFilter)) {
        setState(() => _selectedBranchFilter = null);
      }
    }
  }

  Future<Map<String, bool>?> _showContentSelectionDialog() async {
    bool includeSchedule = true;
    bool includeAnalysis = true;
    bool includePriority1 = true;
    bool includePriority2 = true;

    return await showDialog<Map<String, bool>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('İçerik Seçimi'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CheckboxListTile(
                    title: Text('Haftalık Program'),
                    subtitle: Text('Ders programı tablosu'),
                    value: includeSchedule,
                    onChanged: (val) {
                      setState(() => includeSchedule = val ?? true);
                    },
                  ),
                  CheckboxListTile(
                    title: Text('Konu Analiz Tablosu'),
                    subtitle: Text('Öncelikli konular ve detaylı analiz'),
                    value: includeAnalysis,
                    onChanged: (val) {
                      setState(() => includeAnalysis = val ?? true);
                    },
                  ),
                  if (includeAnalysis) ...[
                    Padding(
                      padding: EdgeInsets.only(left: 20),
                      child: CheckboxListTile(
                        title: Text('1. Öncelik (Eksikler)'),
                        value: includePriority1,
                        dense: true,
                        onChanged: (val) {
                          setState(() => includePriority1 = val ?? true);
                        },
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: 20),
                      child: CheckboxListTile(
                        title: Text('2. Öncelik (Pekiştirme)'),
                        value: includePriority2,
                        dense: true,
                        onChanged: (val) {
                          setState(() => includePriority2 = val ?? true);
                        },
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (!includeSchedule && !includeAnalysis) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('En az bir içerik seçmelisiniz.'),
                        ),
                      );
                      return;
                    }
                    Navigator.pop(ctx, {
                      'schedule': includeSchedule,
                      'analysis': includeAnalysis,
                      'priority1': includePriority1,
                      'priority2': includePriority2,
                    });
                  },
                  child: Text('Yazdır'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _bulkPrintPdf() async {
    final programsToPrint = _isSelectionMode
        ? _programs.where((p) => _selectedProgramIds.contains(p['id'])).toList()
        : _filteredPrograms;

    if (programsToPrint.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yazdırılacak program seçilmedi.')),
      );
      return;
    }

    final selection = await _showContentSelectionDialog();
    if (selection == null) return;

    StudyProgramPrintingHelper.generateBulkPdf(
      context,
      programsToPrint,
      includeSchedule: selection['schedule']!,
      includeAnalysis: selection['analysis']!,
      showPriority1: selection['priority1']!,
      showPriority2: selection['priority2']!,
    );
  }

  Future<void> _bulkPrintZip() async {
    final programsToPrint = _isSelectionMode
        ? _programs.where((p) => _selectedProgramIds.contains(p['id'])).toList()
        : _filteredPrograms;

    if (programsToPrint.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('İndirilecek program seçilmedi.')));
      return;
    }

    final selection = await _showContentSelectionDialog();
    if (selection == null) return;

    StudyProgramPrintingHelper.generateBulkZip(
      context,
      programsToPrint,
      includeSchedule: selection['schedule']!,
      includeAnalysis: selection['analysis']!,
      showPriority1: selection['priority1']!,
      showPriority2: selection['priority2']!,
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = _calculateStats();
    final filteredList = _filteredPrograms;
    final dateStr = DateFormat('MMMM yyyy', 'tr_TR').format(_selectedDate);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          _isSelectionMode
              ? '${_selectedProgramIds.length} Seçildi'
              : 'Kayıtlı Mentör Çalışmaları',
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.bar_chart),
            tooltip: 'İstatistikler',
            onPressed: _showStatsDialog,
          ),
          if (!_isSelectionMode && _filteredPrograms.isNotEmpty) ...[
            if (_selectedExamFilter != null || _selectedBranchFilter != null)
              IconButton(
                icon: Icon(Icons.delete_sweep_outlined, color: Colors.red),
                tooltip: 'Filtrelenenlerin Tümünü Sil',
                onPressed: _deleteFilteredPrograms,
              ),
            PopupMenuButton<String>(
              icon: Icon(Icons.print_outlined),
              tooltip: 'Filtrelenenleri Yazdır',
              onSelected: (val) {
                if (val == 'pdf') {
                  _bulkPrintPdf();
                } else {
                  _bulkPrintZip();
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'pdf',
                  child: ListTile(
                    leading: Icon(Icons.picture_as_pdf, color: Colors.red),
                    title: Text('Tek PDF Olarak Yazdır'),
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  value: 'zip',
                  child: ListTile(
                    leading: Icon(Icons.folder_zip, color: Colors.orange),
                    title: Text('Ayrı PDFler (ZIP) İndir'),
                    dense: true,
                  ),
                ),
              ],
            ),
          ],
          if (_isSelectionMode) ...[
            IconButton(
              icon: Icon(
                _selectedProgramIds.length == _filteredPrograms.length
                    ? Icons.deselect
                    : Icons.select_all,
              ),
              tooltip: 'Tümünü Seç / Kaldır',
              onPressed: _toggleSelectAll,
            ),
            IconButton(
              icon: Icon(Icons.print),
              tooltip: 'Seçilenleri Yazdır',
              onPressed: _printSelectedPrograms,
            ),
            IconButton(
              icon: Icon(Icons.delete),
              tooltip: 'Seçilenleri Sil',
              onPressed: _deleteSelectedPrograms,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // 1. Stats Header & Date Filter
          Container(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        TextButton.icon(
                          icon: Icon(
                            Icons.calendar_month,
                            color: Colors.indigo,
                          ),
                          label: Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          ),
                          onPressed: () => _selectDate(context),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            backgroundColor: Colors.indigo.shade50,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        ChoiceChip(
                          label: Text("Tümü"),
                          selected: _isAllTime,
                          onSelected: (val) => setState(() => _isAllTime = val),
                          selectedColor: Colors.indigo.shade100,
                          labelStyle: TextStyle(
                            color: _isAllTime ? Colors.indigo : Colors.black87,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    if (_searchQuery.isNotEmpty ||
                        _selectedExamFilter != null ||
                        _selectedBranchFilter != null)
                      TextButton.icon(
                        icon: Icon(Icons.filter_alt_off, size: 16),
                        label: Text("Temizle", style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          setState(() {
                            _searchQuery = "";
                            _selectedExamFilter = null;
                            _selectedBranchFilter = null;
                            _searchController.clear();
                          });
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                          padding: EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    Text(
                      "${stats['displayed']} Kayıt",
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildHeaderStat(
                      "Toplam (Tümü)",
                      "${stats['total']}",
                      Icons.folder_copy,
                      Colors.grey,
                    ),
                    _buildHeaderStat(
                      "Bu Ay Verilen",
                      "${stats['displayed']}",
                      Icons.description,
                      Colors.blue,
                    ),
                    _buildHeaderStat(
                      "Tamamlanma %",
                      "%${stats['completionRate']}",
                      Icons.pie_chart,
                      Colors.orange,
                    ),
                  ],
                ),
                SizedBox(height: 16),
              ],
            ),
          ),

          // 2. Search & Filters
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 1200),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Öğrenci Adına Göre Ara...',
                          hintStyle: TextStyle(color: Colors.grey.shade400),
                          prefixIcon: Icon(Icons.search, color: Colors.indigo),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val),
                      ),
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildFilterDropdown(
                            hint: "Sınav Seçin",
                            value: _selectedExamFilter,
                            items: _uniqueExams,
                            onChanged: (val) =>
                                setState(() => _selectedExamFilter = val),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: _buildFilterDropdown(
                            hint: "Şube Seçin",
                            value: _selectedBranchFilter,
                            items: _uniqueBranches,
                            onChanged: (val) =>
                                setState(() => _selectedBranchFilter = val),
                          ),
                        ),
                        if (_selectedExamFilter != null ||
                            _selectedBranchFilter != null)
                          IconButton(
                            icon: Icon(Icons.filter_alt_off, color: Colors.red),
                            onPressed: () => setState(() {
                              _selectedExamFilter = null;
                              _selectedBranchFilter = null;
                            }),
                          ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.touch_app_outlined,
                          size: 14,
                          color: Colors.grey.shade500,
                        ),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            "Birden fazla kartta işlem yapabilmek için üzerine basılı tutup seçim işlemini başlatabilirsiniz.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. List
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : filteredList.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 48,
                          color: Colors.grey.shade300,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Bu tarih/aramaya uygun kayıt yok.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.only(top: 8, bottom: 80),
                    itemCount: filteredList.length,
                    itemBuilder: (context, index) {
                      final program = filteredList[index];
                      final id = program['id'] as String;
                      final isSelected = _selectedProgramIds.contains(id);
                      final creationDate = (program['createdAt'] as Timestamp?)
                          ?.toDate();
                      final dateLabel = creationDate != null
                          ? DateFormat('dd.MM.yyyy HH:mm').format(creationDate)
                          : '';

                      return Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.indigo.withOpacity(0.05)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? Colors.indigo
                                : Colors.grey.withOpacity(0.1),
                            width: isSelected ? 2 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onLongPress: () => _toggleSelection(id),
                          onTap: () {
                            if (_isSelectionMode) {
                              _toggleSelection(id);
                            } else {
                              // Navigate to Detail
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      StudyProgramDetailScreen(
                                        institutionId: widget.institutionId,
                                        program: program,
                                      ),
                                ),
                              ).then(
                                (_) => _fetchPrograms(),
                              ); // Refresh on return
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                if (_isSelectionMode)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 16.0),
                                    child: Checkbox(
                                      value: isSelected,
                                      onChanged: (val) => _toggleSelection(id),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      activeColor: Colors.indigo,
                                    ),
                                  ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (program['studentName'] ??
                                                'Bilinmeyen Öğrenci')
                                            .toString()
                                            .toUpperCase(),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                          color: Colors.grey.shade900,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.indigo.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              _getBranchName(program),
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.indigo.shade700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              program['examName'] ?? '-',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.access_time,
                                            size: 14,
                                            color: Colors.grey.shade400,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            dateLabel,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (!_isSelectionMode)
                                  PopupMenuButton<String>(
                                    icon: Icon(
                                      Icons.more_vert,
                                      color: Colors.grey.shade600,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    onSelected: (val) {
                                      if (val == 'view') {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                StudyProgramDetailScreen(
                                                  program: program,
                                                  institutionId:
                                                      widget.institutionId,
                                                ),
                                          ),
                                        );
                                      } else if (val == 'regenerate') {
                                        _regenerateProgram(program);
                                      } else if (val == 'delete') {
                                        _deleteSingleProgram(id);
                                      }
                                    },
                                    itemBuilder: (ctx) => [
                                      const PopupMenuItem(
                                        value: 'view',
                                        child: ListTile(
                                          leading: Icon(
                                            Icons.visibility,
                                            color: Colors.indigo,
                                          ),
                                          title: Text('Görüntüle'),
                                          dense: true,
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'regenerate',
                                        child: ListTile(
                                          leading: Icon(
                                            Icons.refresh,
                                            color: Colors.blue,
                                          ),
                                          title: Text('Yeniden Oluştur'),
                                          dense: true,
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: ListTile(
                                          leading: Icon(
                                            Icons.delete_outline,
                                            color: Colors.red,
                                          ),
                                          title: Text('Sil'),
                                          dense: true,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String hint,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    items.sort();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          hint: Text(hint, style: TextStyle(fontSize: 13, color: Colors.grey)),
          items: [
            DropdownMenuItem<String>(
              value: null,
              child: Text("Tümü", style: TextStyle(fontSize: 13)),
            ),
            ...items.map(
              (e) => DropdownMenuItem(
                value: e,
                child: Text(
                  e,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildHeaderStat(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        Text(title, style: TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
