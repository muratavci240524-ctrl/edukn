import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../school/assessment/evaluation_models.dart';
import '../school/assessment/student_report_card_dialog.dart';
import '../../models/assessment/lgs_data.dart';

import 'dart:convert';
import '../../services/assessment_service.dart';
import '../../models/assessment/trial_exam_model.dart';
import '../../models/assessment/exam_type_model.dart';
import 'dart:async';
import 'topic_analysis_detail_screen.dart';
import '../school/guidance/study_program_printing_helper.dart';
import '../../models/school/book_model.dart';
import '../../models/school/book_assignment_model.dart';
import '../../models/guidance/development_report/development_report_model.dart';

import 'development_report_detail_screen.dart';
import '../guidance/reports/development_report_pdf_helper.dart';

class PortfolioScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;

  const PortfolioScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
  }) : super(key: key);

  @override
  _PortfolioScreenState createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  // Data
  List<Map<String, dynamic>> _allStudents = [];
  List<Map<String, dynamic>> _filteredStudents = [];
  Map<String, dynamic>? _selectedStudent;
  bool _isLoading = true;

  // Filters
  final TextEditingController _searchController = TextEditingController();
  String? _filterClassLevel;
  String? _filterClass;
  String _statusFilter = 'active'; // 'active', 'inactive', 'all'

  // Drops
  List<String> _classLevels = [];
  List<String> _classes = [];

  @override
  void initState() {
    super.initState();
    _loadStudents();
    _loadActiveFilterData();
    _searchController.addListener(_filterStudents);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadActiveFilterData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('school_types')
          .doc(widget.schoolTypeId)
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (data['activeGrades'] != null) {
          final grades = List<String>.from(
            data['activeGrades'].map((e) => e.toString()),
          );
          if (mounted) {
            setState(() {
              _classLevels = grades;
              // Add 'Mezun' if it's a high school
              final stName = (data['name'] ?? widget.schoolTypeName)
                  .toString()
                  .toLowerCase();
              if (stName.contains('lise') && !_classLevels.contains('Mezun')) {
                _classLevels.add('Mezun');
              }
            });
          }
        }
      }
    } catch (e) {
      print('Error loading active filter data: $e');
    }
  }

  Future<void> _loadStudents() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .orderBy('name')
          .get();

      final students = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      setState(() {
        _allStudents = students;
        _extractFilterData();
        _filterStudents();
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading students: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Öğrenci listesi yüklenirken hata oluştu: $e'),
          ),
        );
      }
    }
  }

  void _extractFilterData() {
    // Extract class names (sections like 12-A, 11-B) from the current student list
    final classes = _allStudents
        .where((s) => s['className'] != null)
        .map((s) => s['className'].toString())
        .toSet()
        .toList();
    classes.sort();

    // Extract levels from actual students in this list
    final levelsFound = _allStudents
        .where((s) => s['classLevel'] != null)
        .map((s) => s['classLevel'].toString())
        .toSet()
        .toList();

    setState(() {
      _classes = classes;

      // Update _classLevels with levels found in students, while keeping existing ones from school_types
      for (var level in levelsFound) {
        if (!_classLevels.contains(level)) {
          _classLevels.add(level);
        }
      }

      // Sort levels: numeric first, then alpha
      _classLevels.sort((a, b) {
        int? ia = int.tryParse(a);
        int? ib = int.tryParse(b);
        if (ia != null && ib != null) return ia.compareTo(ib);
        if (ia != null) return -1;
        if (ib != null) return 1;
        return a.compareTo(b);
      });
    });
  }

  void _filterStudents() {
    final query = _searchController.text.toLowerCase();

    setState(() {
      _filteredStudents = _allStudents.where((s) {
        // Status Filter
        final isActive = s['isActive'] ?? true;
        if (_statusFilter == 'active' && !isActive) return false;
        if (_statusFilter == 'inactive' && isActive) return false;

        // Class Level Filter
        if (_filterClassLevel != null) {
          if (s['classLevel'].toString() != _filterClassLevel) return false;
        }

        // Class Filter
        if (_filterClass != null) {
          if (s['className'] != _filterClass) return false;
        }

        // Search Filter
        if (query.isNotEmpty) {
          final fullName = (s['fullName'] ?? '').toLowerCase();
          final number = (s['studentNumber'] ?? '').toString();
          final tc = (s['tcNo'] ?? '').toString();
          return fullName.contains(query) ||
              number.contains(query) ||
              tc.contains(query);
        }

        return true;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 900;

          if (isWide) {
            // DESKTOP: Split View
            return Row(
              children: [
                Container(
                  width: 380,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      right: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildLeftHeader(isWide: true),
                      Expanded(
                        child: _isLoading
                            ? Center(child: CircularProgressIndicator())
                            : _buildStudentList(isWide: true),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _selectedStudent == null
                      ? _buildEmptySelectionState()
                      // Use Key to force rebuild when student changes
                      : PortfolioDetailView(
                          key: ValueKey(_selectedStudent!['id']),
                          student: _selectedStudent!,
                          institutionId: widget.institutionId,
                          onClose: () =>
                              setState(() => _selectedStudent = null),
                        ),
                ),
              ],
            );
          } else {
            // MOBILE: List Only
            return Column(
              children: [
                _buildLeftHeader(isWide: false),
                Expanded(
                  child: _isLoading
                      ? Center(child: CircularProgressIndicator())
                      : _buildStudentList(isWide: false),
                ),
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildLeftHeader({required bool isWide}) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.indigo.shade900,
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
                tooltip: 'Geri Dön',
                constraints: BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Portfolyo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_filteredStudents.length} Öğrenci',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          // Search
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Öğrenci Ara...',
                prefixIcon: Icon(Icons.search, color: Colors.grey),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
                isDense: true,
              ),
            ),
          ),
          SizedBox(height: 12),
          // Context Header
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.school_outlined, color: Colors.white70, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.schoolTypeName,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
          // Filters
          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  hint: 'Sınıf Seviyesi',
                  value: _filterClassLevel,
                  items: _classLevels,
                  onChanged: (val) => setState(() {
                    _filterClassLevel = val;
                    _filterStudents();
                  }),
                  allLabel: 'Tüm Seviyeler',
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _buildDropdown(
                  hint: 'Sınıf',
                  value: _filterClass,
                  items: _classes,
                  onChanged: (val) => setState(() {
                    _filterClass = val;
                    _filterStudents();
                  }),
                  allLabel: 'Tüm Sınıflar',
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Row(
            children: [
              _buildStatusChip('active', 'Aktif'),
              SizedBox(width: 4),
              _buildStatusChip('inactive', 'Pasif'),
              SizedBox(width: 4),
              _buildStatusChip('all', 'Tümü'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String hint,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    String? allLabel,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      decoration: BoxDecoration(
        color: Colors.indigo.shade800,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(
            hint,
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          icon: Icon(Icons.arrow_drop_down, color: Colors.white70),
          dropdownColor: Colors.indigo.shade700,
          style: TextStyle(color: Colors.white, fontSize: 13),
          isExpanded: true,
          onChanged: onChanged,
          items: [
            DropdownMenuItem<String>(
              value: null,
              child: Text(allLabel ?? 'Tümü'),
            ),
            ...items.map((e) => DropdownMenuItem(value: e, child: Text(e))),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String key, String label) {
    bool isSelected = _statusFilter == key;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _statusFilter = key;
            _filterStudents();
          });
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.white24,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.indigo.shade900 : Colors.white,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStudentList({required bool isWide}) {
    if (_filteredStudents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey.shade300),
            SizedBox(height: 8),
            Text('Öğrenci bulunamadı', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(8),
      itemCount: _filteredStudents.length,
      itemBuilder: (context, index) {
        final student = _filteredStudents[index];
        bool isSelected =
            _selectedStudent != null &&
            _selectedStudent!['id'] == student['id'];

        return Card(
          margin: EdgeInsets.symmetric(vertical: 4),
          elevation: isSelected ? 2 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isSelected ? Colors.indigo.shade300 : Colors.grey.shade200,
              width: isSelected ? 2 : 1,
            ),
          ),
          color: isSelected ? Colors.indigo.shade50 : Colors.white,
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: CircleAvatar(
              backgroundColor: isSelected
                  ? Colors.indigo.shade100
                  : Colors.grey.shade100,
              backgroundImage: student['photoUrl'] != null
                  ? NetworkImage(student['photoUrl'])
                  : null,
              child: student['photoUrl'] == null
                  ? Text(
                      (student['name'] ?? 'X')[0],
                      style: TextStyle(
                        color: isSelected
                            ? Colors.indigo
                            : Colors.grey.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
            title: Text(
              student['fullName'] ?? 'İsimsiz',
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.indigo.shade900 : Colors.black87,
              ),
            ),
            subtitle: Text(
              '${student['className'] ?? '-'} · No: ${student['studentNumber'] ?? '-'}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            trailing: Icon(Icons.chevron_right, color: Colors.indigo),
            onTap: () {
              if (isWide) {
                // Desktop: Select item
                setState(() => _selectedStudent = student);
              } else {
                // Mobile: Navigate to detail
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PortfolioDetailView(
                      student: student,
                      institutionId: widget.institutionId,
                      onClose: () => Navigator.pop(context),
                    ),
                  ),
                );
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptySelectionState() {
    return Container(
      color: Colors.grey.shade50,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
              ),
              child: Icon(
                Icons.folder_shared,
                size: 80,
                color: Colors.indigo.shade200,
              ),
            ),
            SizedBox(height: 24),
            Text(
              'Portfolyo Görüntüle',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Soldaki listeden bir öğrenci seçerek bilgilerini görüntüleyebilirsiniz.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

// --- DETAIL VIEW ---

class PortfolioDetailView extends StatefulWidget {
  final Map<String, dynamic> student;
  final String institutionId;
  final VoidCallback? onClose;

  const PortfolioDetailView({
    Key? key,
    required this.student,
    required this.institutionId,
    this.onClose,
  }) : super(key: key);

  @override
  _PortfolioDetailViewState createState() => _PortfolioDetailViewState();
}

class _PortfolioDetailViewState extends State<PortfolioDetailView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Trial Exam State
  String? _selectedExamType;
  Set<String> _availableExamTypes = {};
  String _selectedGraphSubject = 'Tümü';
  String? _expandedExamId;
  Set<String> _availableSubjects = {'Tümü'};
  String _graphMetric = 'net'; // 'net' or 'score'
  String _selectedLgsYear = '2025'; // Default to latest LGS year
  String _selectedWrittenSubject = 'Tümü';
  String _selectedHomeworkSubject = 'Tümü';
  String _selectedAttendanceLesson = 'Tümü';
  String _selectedInterviewTitle = 'Tümü';
  BookType _activeBookTabFilter = BookType.questionBank;
  String _selectedEtutSubject = 'Tümü';

  // Store full ExamType objects (examTypeId -> ExamType)
  Map<String, ExamType> _examTypesMap = {};
  StreamSubscription? _examTypesSubscription;

  // Streams
  late Stream<List<TrialExam>> _trialExamsStream;
  late Stream<QuerySnapshot> _writtenExamsStream;
  late Stream<QuerySnapshot> _homeworksStream;
  late Stream<QuerySnapshot> _attendanceStream;
  late Stream<QuerySnapshot> _interviewsStream;
  late Stream<QuerySnapshot> _guidanceTestsStream;
  late Stream<QuerySnapshot> _studyProgramsStream;
  late Stream<QuerySnapshot> _activityReportsStream;
  late Stream<QuerySnapshot> _etutlerStream;
  // Removed unused _developmentReportsStream

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 12, vsync: this);

    // Listen to Exam Types to get subject order and question counts
    _examTypesSubscription = AssessmentService()
        .getExamTypes(widget.institutionId)
        .listen((types) {
          if (mounted) {
            setState(() {
              _examTypesMap = {for (var t in types) t.id: t};
            });
          }
        });

    _selectedWrittenSubject = 'Tümü';

    // Initialize Streams
    _trialExamsStream = AssessmentService().getTrialExams(widget.institutionId);

    final classId = widget.student['classId'];
    _writtenExamsStream = FirebaseFirestore.instance
        .collection('class_exams')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('classId', isEqualTo: classId)
        .snapshots();

    _homeworksStream = FirebaseFirestore.instance
        .collection('homeworks')
        .where('institutionId', isEqualTo: widget.institutionId)
        .orderBy('dueDate', descending: true)
        .limit(50)
        .snapshots();

    final sid = widget.student['id'];
    _attendanceStream = FirebaseFirestore.instance
        .collection('lessonAttendance')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('classId', isEqualTo: classId)
        .orderBy('date', descending: true)
        .limit(100)
        .snapshots();

    _interviewsStream = FirebaseFirestore.instance
        .collection('guidance_interviews')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('participants', arrayContains: sid)
        .orderBy('date', descending: true)
        .snapshots();

    _guidanceTestsStream = FirebaseFirestore.instance
        .collection('applied_tests')
        .where('studentId', isEqualTo: sid)
        .orderBy('completedAt', descending: true)
        .snapshots();

    _studyProgramsStream = FirebaseFirestore.instance
        .collection('institutions')
        .doc(widget.institutionId)
        .collection('study_programs')
        .where('studentId', isEqualTo: sid)
        .orderBy('createdAt', descending: true)
        .snapshots();

    _activityReportsStream = FirebaseFirestore.instance
        .collection('activity_reports')
        .where('studentId', isEqualTo: sid)
        .orderBy('date', descending: true)
        .snapshots();

    _etutlerStream = FirebaseFirestore.instance
        .collection('etut_requests')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('studentId', isEqualTo: sid)
        .orderBy('date', descending: true)
        .snapshots();

    // New Service usage
    // We can use the service stream directly or keep using raw snapshots if we prefer
    // But since we have a service, let's use it or at least point to the right collection.
    // However, the existing code expects QuerySnapshot for _developmentReportsStream.
    // So let's update the query to the new collection 'development_reports'.
  }

  @override
  void dispose() {
    _tabController.dispose();
    _examTypesSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading:
            widget.onClose != null && MediaQuery.of(context).size.width > 900
            ? null
            : BackButton(color: Colors.indigo),
        title: Row(
          children: [
            if (MediaQuery.of(context).size.width > 900) ...[
              Icon(Icons.person, color: Colors.indigo),
              SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                widget.student['fullName'] ?? 'Öğrenci Detayı',
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.indigo,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: Colors.indigo,
          indicatorWeight: 3,
          labelStyle: TextStyle(fontWeight: FontWeight.bold),
          tabs: [
            Tab(text: 'Genel Bilgiler'),
            Tab(text: 'Deneme Sınavları'),
            Tab(text: 'Yazılı Sınavlar'),
            Tab(text: 'Ödevler'),
            Tab(text: 'Devamsızlık'),
            Tab(text: 'Etütler'),
            Tab(text: 'Kitaplar'),
            Tab(text: 'Görüşmeler'),
            Tab(text: 'Gelişim Raporu'),
            Tab(text: 'Çalışma Programları'),
            Tab(text: 'Rehberlik Testleri'),
            Tab(text: 'Etkinlik Raporları'),
          ],
        ),
        actions: [
          if (widget.onClose != null && MediaQuery.of(context).size.width > 900)
            IconButton(
              icon: Icon(Icons.close, color: Colors.grey),
              onPressed: widget.onClose,
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGeneralInfoTab(),
          _buildTrialExamsTab(),
          _buildWrittenExamsTab(),
          _buildHomeworksTab(),
          _buildAttendanceTab(),
          _buildEtutlerTab(),
          _buildBooksTab(),
          _buildInterviewsTab(),
          _buildDevelopmentReportTab(),
          _buildStudyProgramsTab(),
          _buildGuidanceTestsTab(),
          _buildActivityReportsTab(),
        ],
      ),
    );
  }

  // ... General Info Tab (Previous Code) ...
  Widget _buildGeneralInfoTab() {
    final s = widget.student;
    final dob = s['birthDate'] ?? '-';

    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.indigo.shade800, Colors.indigo.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.indigo.withOpacity(0.3),
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.white,
                  backgroundImage: s['photoUrl'] != null
                      ? NetworkImage(s['photoUrl'])
                      : null,
                  child: s['photoUrl'] == null
                      ? Icon(Icons.person, size: 40, color: Colors.indigo)
                      : null,
                ),
                SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s['fullName'] ?? '-',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '${s['className'] ?? 'Sınıfsız'} | No: ${s['studentNumber'] ?? '-'}',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      SizedBox(height: 8),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          s['isActive'] == true ? 'Aktif Öğrenci' : 'Pasif',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 24),
          Text(
            'Kişisel Bilgiler',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          SizedBox(height: 12),
          _buildInfoGrid([
            _buildInfoCard(Icons.badge, 'TC Kimlik No', s['tcNo'] ?? '-'),
            _buildInfoCard(Icons.cake, 'Doğum Tarihi', dob),
            _buildInfoCard(Icons.male, 'Cinsiyet', s['gender'] ?? '-'),
            _buildInfoCard(Icons.email, 'E-posta', s['email'] ?? '-'),
            _buildInfoCard(Icons.phone, 'Telefon', s['phone'] ?? '-'),
            _buildInfoCard(Icons.login, 'Giriş Türü', s['entryType'] ?? '-'),
          ]),
          SizedBox(height: 24),
          Text(
            'Veli Bilgileri',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          SizedBox(height: 12),
          if (s['parents'] != null && (s['parents'] as List).isNotEmpty)
            ...((s['parents'] as List).map(
              (p) => Card(
                margin: EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.shade50,
                    child: Icon(Icons.family_restroom, color: Colors.orange),
                  ),
                  title: Text(p['name'] ?? '-'),
                  subtitle: Text(
                    '${p['relation'] ?? '-'} · ${p['phone'] ?? '-'}',
                  ),
                ),
              ),
            ))
          else
            Text(
              'Veli bilgisi bulunmuyor.',
              style: TextStyle(color: Colors.grey),
            ),
        ],
      ),
    );
  }

  // --- HELPER METHODS FOR TRIAL EXAMS ---

  void _showReportCard(Map<String, dynamic> res) {
    try {
      if (res['resultsJson'] != null) {
        final List<dynamic> allResults = jsonDecode(res['resultsJson']);
        final studentId = widget.student['id'].toString();

        // Robust Matching Logic
        Map<String, dynamic>? match;

        // 1. Match by ID
        match = allResults.firstWhere((r) {
          final rId = r['studentId']?.toString() ?? r['id']?.toString();
          return rId == studentId;
        }, orElse: () => null);

        // 2. Match by School Number if ID failed
        if (match == null) {
          final studentNo =
              widget.student['schoolNumber']?.toString().trim() ??
              widget.student['studentNumber']?.toString().trim() ??
              widget.student['no']?.toString().trim();
          if (studentNo != null && studentNo.isNotEmpty) {
            match = allResults.firstWhere((r) {
              final rNo =
                  (r['studentNumber'] ??
                          r['number'] ??
                          r['schoolNumber'] ??
                          r['no'] ??
                          '')
                      .toString()
                      .trim();
              return rNo == studentNo;
            }, orElse: () => null);
          }
        }

        // 3. Match by Name (Fuzzy) if others failed
        if (match == null) {
          final sName = (widget.student['fullName'] ?? widget.student['name'])
              .toString()
              .toLowerCase();
          match = allResults.firstWhere((r) {
            final rName = (r['name'] ?? r['studentName'] ?? '')
                .toString()
                .toLowerCase();
            return rName.contains(sName);
          }, orElse: () => null);
        }

        print(
          "DEBUG REPORT CARD: StudentID: $studentId, Match Found: ${match != null}",
        );
        if (match == null) {
          print(
            "DEBUG REPORT CARD: Available IDs in results: ${allResults.map((e) => e['studentId'] ?? e['id']).toList()}",
          );
        }

        if (match != null) {
          final resultObj = StudentResult.fromJson(match);

          final dummyExam = TrialExam(
            id: res['examId'],
            institutionId: widget.institutionId,
            name: res['examName'],
            classLevel: widget.student['classLevel']?.toString() ?? '',
            examTypeId: res['examTypeId'] ?? '',
            examTypeName: res['typeName'],
            applicationType: TrialExamApplicationType.optical,
            date: res['date'],
            bookletCount: 1,
            answerKeys: res['examAnswerKeys'] is Map
                ? (res['examAnswerKeys'] as Map).map(
                    (k, v) => MapEntry(
                      k.toString(),
                      (v as Map).map(
                        (k2, v2) => MapEntry(k2.toString(), v2.toString()),
                      ),
                    ),
                  )
                : {},
            outcomes: res['examOutcomes'] is Map
                ? Map<String, Map<String, List<String>>>.from(
                    (res['examOutcomes'] as Map).map(
                      (k, v) => MapEntry(
                        k,
                        Map<String, List<String>>.from(
                          (v as Map).map(
                            (k2, v2) => MapEntry(
                              k2,
                              List<String>.from(
                                (v2 as List).map((e) => e.toString()),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : {},
            resultsJson: res['resultsJson'],
          );

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StudentReportCardDialog(
                student: resultObj,
                examName: res['examName'],
                subjects: resultObj.subjects.keys.toList(),
                outcomes: dummyExam.outcomes,
                totalStudents: 0,
              ),
            ),
          );
          return;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Sınav detaylarına şu an ulaşılamıyor.")),
      );
    } catch (e) {
      print("Error showing report card: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Hata: $e")));
    }
  }

  // Actual implementation will serve the dialog.
  // We'll implement the UI parts first.

  Widget _buildSummaryStats(List<Map<String, dynamic>> results) {
    if (results.isEmpty) return SizedBox.shrink();

    // Calculate Averages
    double totalScore = 0;
    double totalNet = 0;

    for (var r in results) {
      totalScore += (r['score'] as num).toDouble();
      totalNet += (r['net'] as num).toDouble();
    }

    double avgScore = totalScore / results.length;
    double avgNet = totalNet / results.length;

    bool isLgs = _selectedExamType == 'LGS';
    String estimatedPercentile = '-';
    String percentileRange = '-';

    if (isLgs) {
      estimatedPercentile = getLgsPercentile(avgScore, _selectedLgsYear);
      percentileRange = getLgsPercentileRangeString(avgScore, _selectedLgsYear);
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildInfoCard(
                Icons.star_rounded,
                "Genel Puan Ort.",
                avgScore.toStringAsFixed(1),
                color: Colors.orange,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildInfoCard(
                Icons.bolt_rounded,
                "Genel Net Ort.",
                avgNet.toStringAsFixed(1),
                color: Colors.green,
              ),
            ),
          ],
        ),
        if (isLgs) ...[
          SizedBox(height: 12),
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.purple.shade100),
              boxShadow: [
                BoxShadow(
                  color: Colors.purple.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, 4),
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
                        Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.pie_chart,
                            color: Colors.purple,
                            size: 20,
                          ),
                        ),
                        SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Tahmini Yüzdelik Dilim",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.purple.shade900,
                              ),
                            ),
                            Text(
                              "$_selectedLgsYear LGS Verilerine Göre",
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.purple.shade400,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.info_outline,
                        color: Colors.purple.shade300,
                        size: 20,
                      ),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: Text("Bilgilendirme"),
                            content: Text(
                              "LGS'de yüzdelik dilimler sadece puana değil, o yıl sınava giren öğrenci sayısına ve standart sapmaya da bağlıdır. Bu veriler 'genel ortalamaları' yansıtır.\\n\\nSistem, öğrenciye bu sonuçları gösterirken her zaman 'Tahmini Referans Değerleridir' ibaresini eklemelidir.",
                            ),
                            actions: [
                              TextButton(
                                child: Text("Tamam"),
                                onPressed: () => Navigator.pop(c),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      estimatedPercentile,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.purple.shade800,
                        letterSpacing: -1,
                      ),
                    ),
                    SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        percentileRange,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.purple.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                // Year Selector
                Container(
                  padding: EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: ['2023', '2024', '2025'].map((y) {
                      bool isSel = _selectedLgsYear == y;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedLgsYear = y),
                          child: Container(
                            alignment: Alignment.center,
                            padding: EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: isSel ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: isSel
                                  ? [
                                      BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 2,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              y,
                              style: TextStyle(
                                fontWeight: isSel
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: isSel
                                    ? Colors.black87
                                    : Colors.grey.shade600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTopicAnalysis(List<Map<String, dynamic>> results) {
    if (results.isEmpty) return SizedBox.shrink();

    // Calculate topic stats for each subject
    Map<String, Map<String, Map<String, double>>> allSubjectStats = {};
    Set<String> availableSubjects = {};

    for (var res in results) {
      final outcomes = res['examOutcomes'];
      final answerKeys = res['examAnswerKeys'];
      final studentAnswers = res['studentAnswers'];

      if (outcomes is! Map || answerKeys is! Map || studentAnswers is! Map)
        continue;

      var booklet = res['booklet']?.toString() ?? 'A';
      var outcomesMap = (outcomes as Map?)?[booklet];
      var answerKeysMap = (answerKeys as Map?)?[booklet];

      // Fallback logic
      if (outcomesMap == null && outcomes.isNotEmpty) {
        outcomesMap = outcomes['A'] ?? outcomes.values.first;
        booklet = outcomes.keys.firstWhere(
          (k) => outcomes[k] == outcomesMap,
          orElse: () => 'A',
        );
        answerKeysMap = answerKeys[booklet];
      }
      if (answerKeysMap == null && answerKeys.isNotEmpty) {
        answerKeysMap = answerKeys['A'] ?? answerKeys.values.first;
      }

      if (outcomesMap is! Map || answerKeysMap is! Map) continue;

      outcomesMap.forEach((subject, outcomeList) {
        if (outcomeList is! List) return;

        availableSubjects.add(subject.toString());

        // Find matching answer key
        String? validSubjectKey;
        final subjectKeyRaw = subject.toString().trim();

        if (answerKeysMap.containsKey(subjectKeyRaw)) {
          validSubjectKey = subjectKeyRaw;
        } else {
          validSubjectKey = answerKeysMap.keys.firstWhere(
            (k) =>
                k.toString().trim().toLowerCase() ==
                subjectKeyRaw.toLowerCase(),
            orElse: () => '',
          );
        }

        if (validSubjectKey == null || validSubjectKey.isEmpty) return;

        final correctKey = answerKeysMap[validSubjectKey]?.toString() ?? '';
        final studentAns = studentAnswers[validSubjectKey]?.toString() ?? '';

        if (correctKey.isEmpty || studentAns.isEmpty) return;

        // Initialize subject stats if needed
        if (!allSubjectStats.containsKey(subject.toString())) {
          allSubjectStats[subject.toString()] = {};
        }

        // Process each question/topic
        for (int i = 0; i < outcomeList.length; i++) {
          if (i >= correctKey.length || i >= studentAns.length) break;

          // outcomeList is a list of strings (topics), not maps
          final topic = outcomeList[i]?.toString() ?? 'Diğer';

          // Initialize topic stats if needed
          allSubjectStats[subject.toString()]!.putIfAbsent(
            topic,
            () => {'correct': 0, 'wrong': 0, 'empty': 0},
          );

          final c = correctKey[i].toUpperCase();
          final s = studentAns[i].toUpperCase();

          if (s == c) {
            allSubjectStats[subject.toString()]![topic]!['correct'] =
                (allSubjectStats[subject.toString()]![topic]!['correct']! + 1);
          } else if (s == ' ' || s.isEmpty) {
            allSubjectStats[subject.toString()]![topic]!['empty'] =
                (allSubjectStats[subject.toString()]![topic]!['empty']! + 1);
          } else {
            allSubjectStats[subject.toString()]![topic]!['wrong'] =
                (allSubjectStats[subject.toString()]![topic]!['wrong']! + 1);
          }
        }
      });
    }

    if (allSubjectStats.isEmpty) {
      return SizedBox.shrink();
    }

    // Flatten all topics across all subjects for summary
    List<Map<String, dynamic>> allTopics = [];
    allSubjectStats.forEach((subject, topicsMap) {
      topicsMap.forEach((topic, stats) {
        double corr = stats['correct']!;
        double wrng = stats['wrong']!;
        double empty = stats['empty']!;
        double total = corr + wrng + empty;
        double pct = total > 0 ? (corr / total) * 100 : 0;

        allTopics.add({
          'subject': subject,
          'topic': topic,
          'correct': corr.toInt(),
          'wrong': wrng.toInt(),
          'empty': empty.toInt(),
          'total': total.toInt(),
          'success': pct,
        });
      });
    });

    // Sort by success percentage
    allTopics.sort(
      (a, b) => (b['success'] as double).compareTo(a['success'] as double),
    );

    final topTopics = allTopics.take(3).toList();
    final worstTopics = allTopics.reversed.take(3).toList().reversed.toList();

    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Konu Bazlı Analiz',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 600;
              return isNarrow
                  ? Column(
                      children: [
                        _buildTopicSummaryCard(
                          "En Başarılı Konular",
                          topTopics,
                          Colors.green,
                          Icons.trending_up,
                        ),
                        SizedBox(height: 12),
                        _buildTopicSummaryCard(
                          "Geliştirilmesi Gerekenler",
                          worstTopics,
                          Colors.red,
                          Icons.trending_down,
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildTopicSummaryCard(
                            "En Başarılı Konular",
                            topTopics,
                            Colors.green,
                            Icons.trending_up,
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: _buildTopicSummaryCard(
                            "Geliştirilmesi Gerekenler",
                            worstTopics,
                            Colors.red,
                            Icons.trending_down,
                          ),
                        ),
                      ],
                    );
            },
          ),
          SizedBox(height: 20),
          Center(
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TopicAnalysisDetailScreen(
                      allSubjectStats: allSubjectStats,
                      studentName:
                          widget.student['fullName'] ??
                          widget.student['name'] ??
                          'Öğrenci',
                    ),
                  ),
                );
              },
              icon: Icon(Icons.analytics_outlined),
              label: Text('Konu Analiz Raporunu Gör'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicSummaryCard(
    String title,
    List<Map<String, dynamic>> topics,
    Color accentColor,
    IconData icon,
  ) {
    return Container(
      height: 240, // Fixed height for equal card sizes
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.05),
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
              Icon(icon, color: accentColor, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                "Başarı %",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          Divider(color: accentColor.withOpacity(0.1), height: 24),
          Expanded(
            child: topics.isEmpty
                ? Center(
                    child: Text(
                      "Veri yok",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: topics.length,
                    padding: EdgeInsets.zero,
                    itemBuilder: (context, index) {
                      final t = topics[index];
                      final score = t['success'] as double;
                      final topicText = t['subject'] != null
                          ? "${t['subject']} - ${t['topic']}"
                          : t['topic'];

                      // Color based on success percentage
                      Color scoreColor;
                      if (score >= 80) {
                        scoreColor = Colors.green;
                      } else if (score >= 60) {
                        scoreColor = Colors.blue;
                      } else if (score >= 40) {
                        scoreColor = Colors.orange;
                      } else {
                        scoreColor = Colors.red;
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                topicText,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(width: 8),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: scoreColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                "%${score.toStringAsFixed(1)}",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: scoreColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrialExamsTab() {
    return StreamBuilder<List<TrialExam>>(
      stream: _trialExamsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildEmptyState('Henüz deneme sınavı sonucu bulunmuyor.');
        }

        final exams = snapshot.data!;
        // Parse results for this student
        final studentRes = _parseTrialExamResults(exams);

        if (studentRes.isEmpty) {
          return _buildEmptyState('Öğrenciye ait sınav sonucu bulunamadı.');
        }

        // Filter valid exam types
        _availableExamTypes = studentRes
            .map((e) => e['typeName'] as String)
            .toSet();

        // Default selection if null or not in available
        if (_selectedExamType == null ||
            !_availableExamTypes.contains(_selectedExamType)) {
          if (_availableExamTypes.isNotEmpty) {
            // Try to find 'TYT' or 'LGS' as default preference, else first
            if (_availableExamTypes.contains('TYT'))
              _selectedExamType = 'TYT';
            else if (_availableExamTypes.contains('LGS'))
              _selectedExamType = 'LGS';
            else
              _selectedExamType = _availableExamTypes.first;
          }
        }

        // Filter results by selected type
        final filteredRes = studentRes
            .where((r) => r['typeName'] == _selectedExamType)
            .toList();

        // Extract available subjects for the selected exam type
        // Use the definition from ExamType if available to sort correctly
        List<String> sortedSubjects = ['Tümü'];

        // Find the ExamType ID from the first result if possible
        String? currentExamTypeId;
        if (filteredRes.isNotEmpty) {
          currentExamTypeId = filteredRes.first['examTypeId'];
        }

        // Get unique subjects from results
        Set<String> resultSubjects = {};
        for (var res in filteredRes) {
          if (res['subjects'] is Map) {
            resultSubjects.addAll(
              (res['subjects'] as Map).keys.map((e) => e.toString()),
            );
          }
        }

        // Sort them based on ExamType definition
        if (currentExamTypeId != null &&
            _examTypesMap.containsKey(currentExamTypeId)) {
          final examType = _examTypesMap[currentExamTypeId]!;
          final definedOrder = examType.subjects
              .map((s) => s.branchName)
              .toList();

          // Sort resultSubjects based on definedOrder
          final sortedList = resultSubjects.toList();
          sortedList.sort((a, b) {
            int indexA = definedOrder.indexOf(a);
            int indexB = definedOrder.indexOf(b);
            if (indexA != -1 && indexB != -1) return indexA.compareTo(indexB);
            if (indexA != -1) return -1;
            if (indexB != -1) return 1;
            return a.compareTo(b);
          });
          sortedSubjects.addAll(sortedList);
        } else {
          // Fallback sort
          final list = resultSubjects.toList()..sort();
          sortedSubjects.addAll(list);
        }

        _availableSubjects = sortedSubjects.toSet();

        // Reset subject if not available
        if (!_availableSubjects.contains(_selectedGraphSubject)) {
          _selectedGraphSubject = 'Tümü';
        }

        // Sort by date ascending for graph
        filteredRes.sort(
          (a, b) => (a['date'] as DateTime).compareTo(b['date']),
        );

        return SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // FILTERS ROW
              Row(
                children: [
                  // Exam Type Dropdown
                  Expanded(
                    flex: 1,
                    child: Container(
                      height: 48,
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedExamType,
                          isExpanded: true,
                          icon: Icon(
                            Icons.arrow_drop_down_rounded,
                            color: Colors.indigo,
                          ),
                          hint: Text("Sınav Türü"),
                          items: _availableExamTypes.map((t) {
                            return DropdownMenuItem(
                              value: t,
                              child: Text(
                                t,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.indigo.shade900,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null)
                              setState(() => _selectedExamType = val);
                          },
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  // Subject Dropdown
                  Expanded(
                    flex: 1,
                    child: Container(
                      height: 48,
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedGraphSubject,
                          isExpanded: true,
                          icon: Icon(
                            Icons.arrow_drop_down_rounded,
                            color: Colors.indigo,
                          ),
                          hint: Text("Ders Seçiniz"),
                          items: _availableSubjects.toList().map((s) {
                            return DropdownMenuItem(
                              value: s,
                              child: Text(
                                s,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.indigo.shade900,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null)
                              setState(() => _selectedGraphSubject = val);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: 24),

              // GRAPH
              Container(
                height: 300,
                padding: EdgeInsets.fromLTRB(16, 24, 16, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.indigo.withOpacity(0.08),
                      blurRadius: 15,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "$_selectedExamType - ${_selectedGraphSubject == 'Tümü' ? (_graphMetric == 'score' ? 'Toplam Puan' : 'Toplam Net') : _selectedGraphSubject}",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.indigo.shade900,
                          ),
                        ),
                        if (_selectedGraphSubject == 'Tümü') ...[
                          SizedBox(width: 8),
                          InkWell(
                            onTap: () {
                              setState(() {
                                _graphMetric = _graphMetric == 'net'
                                    ? 'score'
                                    : 'net';
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.indigo.shade100,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.swap_horiz,
                                    size: 16,
                                    color: Colors.indigo,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    _graphMetric == 'net'
                                        ? 'Puana Göre'
                                        : 'Nete Göre',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      "Gelişim Grafiği",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 24.0, right: 16),
                        child: LineChart(_getLineChartData(filteredRes)),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 24),
              _buildSummaryStats(filteredRes),
              SizedBox(height: 24),

              _buildTopicAnalysis(studentRes),
              SizedBox(height: 24),

              Text(
                "Sınav Geçmişi",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo.shade900,
                ),
              ),
              SizedBox(height: 12),

              // Detailed List (Latest First)
              ...filteredRes.reversed.map((res) {
                return Card(
                  margin: EdgeInsets.only(bottom: 16),
                  elevation: 2,
                  shadowColor: Colors.black.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ExpansionTile(
                    key: Key(
                      "${res['id']}_${_expandedExamId == res['id'].toString()}",
                    ),
                    initiallyExpanded: _expandedExamId == res['id'].toString(),
                    onExpansionChanged: (expanded) {
                      if (expanded) {
                        setState(() {
                          _expandedExamId = res['id'].toString();
                        });
                      } else {
                        if (_expandedExamId == res['id'].toString()) {
                          setState(() {
                            _expandedExamId = null;
                          });
                        }
                      }
                    },
                    tilePadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "${(res['score'] as num).toStringAsFixed(0)}",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.indigo.shade700,
                            ),
                          ),
                          Text(
                            "Puan",
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.indigo.shade400,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    title: Text(
                      res['examName'],
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.indigo.shade900,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 14,
                            color: Colors.grey.shade600,
                          ),
                          SizedBox(width: 4),
                          Text(
                            DateFormat('dd.MM.yyyy').format(res['date']),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(width: 12),
                          Icon(
                            Icons.analytics_rounded,
                            size: 14,
                            color: Colors.grey.shade600,
                          ),
                          SizedBox(width: 4),
                          Text(
                            "${(res['net'] as num).toStringAsFixed(2)} Net",
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    children: [
                      if (res['subjects'] is Map)
                        Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Builder(
                            builder: (context) {
                              // SORTING LOGIC
                              final subjectsMap = res['subjects'] as Map;
                              final examTypeId = res['examTypeId'];

                              List<String> sortedKeys = subjectsMap.keys
                                  .map((e) => e.toString())
                                  .toList();

                              // Use the order defined in the Exam Type
                              try {
                                if (examTypeId != null &&
                                    _examTypesMap.containsKey(examTypeId)) {
                                  final examType = _examTypesMap[examTypeId]!;
                                  final definedOrder = examType.subjects
                                      .map((s) => s.branchName)
                                      .toList();

                                  if (definedOrder.isNotEmpty) {
                                    sortedKeys.sort((a, b) {
                                      int indexA = definedOrder.indexOf(a);
                                      int indexB = definedOrder.indexOf(b);
                                      if (indexA != -1 && indexB != -1)
                                        return indexA.compareTo(indexB);
                                      if (indexA != -1) return -1;
                                      if (indexB != -1) return 1;
                                      return a.compareTo(b);
                                    });
                                  } else {
                                    sortedKeys.sort();
                                  }
                                } else {
                                  // Fallback: If no ExamType defined, maybe sort by common subjects if possible, or just alpha
                                  sortedKeys.sort();
                                }
                              } catch (e) {
                                print("Error sorting subjects: $e");
                                sortedKeys.sort();
                              }

                              // Calculate Totals
                              double totalNet = 0;
                              int totalTrue = 0;
                              int totalFalse = 0;

                              subjectsMap.forEach((key, val) {
                                if (val is Map) {
                                  totalNet += (val['net'] ?? val['netler'] ?? 0)
                                      .toDouble();
                                  totalTrue +=
                                      (val['true'] ??
                                              val['dogru'] ??
                                              val['d'] ??
                                              val['correct'] ??
                                              val['D'] ??
                                              0)
                                          as int;
                                  totalFalse +=
                                      (val['false'] ??
                                              val['yanlis'] ??
                                              val['y'] ??
                                              val['incorrect'] ??
                                              val['Y'] ??
                                              val['wrong'] ??
                                              0)
                                          as int;
                                } else if (val is num) {
                                  totalNet += val.toDouble();
                                }
                              });

                              return Column(
                                children: [
                                  // TOTAL STATS HEADER
                                  Container(
                                    margin: EdgeInsets.only(bottom: 12),
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.indigo.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.indigo.shade100,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "TOPLAM",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: Colors.indigo.shade900,
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            Text(
                                              "$totalTrue D  $totalFalse Y",
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.indigo.shade700,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            SizedBox(width: 12),
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 5,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Colors.indigo.shade200,
                                                ),
                                              ),
                                              child: Text(
                                                "${totalNet.toStringAsFixed(2)} Net",
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.indigo.shade800,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  // SUBJECT LIST
                                  ...sortedKeys.map((key) {
                                    final val = subjectsMap[key];
                                    String netStr = '-';
                                    String detailStr = '';

                                    if (val is Map) {
                                      final net =
                                          (val['net'] ?? val['netler'] ?? 0)
                                              .toDouble();
                                      final dogru =
                                          val['true'] ??
                                          val['dogru'] ??
                                          val['d'] ??
                                          val['correct'] ??
                                          val['D'] ??
                                          '-';
                                      final yanlis =
                                          val['false'] ??
                                          val['yanlis'] ??
                                          val['y'] ??
                                          val['incorrect'] ??
                                          val['Y'] ??
                                          val['wrong'] ?? // Added check
                                          '-';
                                      netStr = "${net.toStringAsFixed(2)} Net";
                                      detailStr = "$dogru D  $yanlis Y";
                                    } else if (val is num) {
                                      netStr =
                                          "${(val).toDouble().toStringAsFixed(2)} Net";
                                    } else {
                                      netStr = val.toString();
                                    }

                                    return Container(
                                      margin: EdgeInsets.symmetric(vertical: 4),
                                      padding: EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              key,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ),
                                          Row(
                                            children: [
                                              if (detailStr.isNotEmpty)
                                                Text(
                                                  detailStr,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey.shade600,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              if (detailStr.isNotEmpty)
                                                SizedBox(width: 8),
                                              Container(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color:
                                                        Colors.indigo.shade100,
                                                  ),
                                                ),
                                                child: Text(
                                                  netStr,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color:
                                                        Colors.indigo.shade700,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                  SizedBox(height: 16),
                                  Divider(),
                                  TextButton.icon(
                                    onPressed: () => _showReportCard(res),
                                    icon: Icon(Icons.sticky_note_2_outlined),
                                    label: Text("Sınav Karnesini Görüntüle"),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.indigo,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  // Helper method for Chart Data
  LineChartData _getLineChartData(List<Map<String, dynamic>> filteredRes) {
    double calculatedMaxY = 100.0;
    if (_graphMetric == 'score') {
      calculatedMaxY = 500.0;
    } else {
      if (filteredRes.isNotEmpty) {
        final typeId = filteredRes.first['examTypeId'];
        if (typeId != null && _examTypesMap.containsKey(typeId)) {
          final examType = _examTypesMap[typeId]!;
          if (_selectedGraphSubject == 'Tümü') {
            calculatedMaxY = examType.subjects
                .fold<double>(0, (sum, s) => sum + s.questionCount)
                .toDouble();
          } else {
            final sub = examType.subjects.firstWhere(
              (s) => s.branchName == _selectedGraphSubject,
              orElse: () => ExamSubject(
                branchName: '',
                questionCount: 20,
                coefficient: 1,
              ),
            );
            calculatedMaxY = sub.questionCount.toDouble();
          }
        }
      } else {
        calculatedMaxY = _selectedGraphSubject == 'Tümü' ? 100.0 : 20.0;
      }
    }

    // Determine interval
    double interval = 10.0;
    if (calculatedMaxY > 100) {
      interval = 50.0;
    } else if (calculatedMaxY <= 20) {
      interval = 5.0;
    }

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: interval,
        getDrawingHorizontalLine: (value) {
          return FlLine(color: Colors.grey.shade200, strokeWidth: 1);
        },
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 1,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index >= 0 && index < filteredRes.length) {
                final date = filteredRes[index]['date'] as DateTime;
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    DateFormat('dd.MM').format(date),
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                );
              }
              return const Text('');
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: interval,
            getTitlesWidget: (value, meta) {
              return Text(
                value.toInt().toString(),
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              );
            },
            reservedSize: 30,
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      minX: 0,
      maxX: (filteredRes.length - 1).toDouble(),
      minY: 0,
      maxY: calculatedMaxY,
      lineBarsData: [
        LineChartBarData(
          spots: filteredRes.asMap().entries.map((e) {
            double yVal = 0;
            if (_graphMetric == 'score') {
              yVal = (e.value['score'] as num).toDouble();
            } else {
              if (_selectedGraphSubject == 'Tümü') {
                yVal = (e.value['net'] as num).toDouble();
              } else {
                final subMap = e.value['subjects'];
                if (subMap is Map &&
                    subMap.containsKey(_selectedGraphSubject)) {
                  final subData = subMap[_selectedGraphSubject];
                  if (subData is Map) {
                    yVal = (subData['net'] ?? 0).toDouble();
                  } else if (subData is num) {
                    yVal = subData.toDouble();
                  }
                }
              }
            }
            return FlSpot(e.key.toDouble(), yVal);
          }).toList(),
          isCurved: true,
          color: Colors.indigo,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) {
              return FlDotCirclePainter(
                radius: 4,
                color: Colors.white,
                strokeWidth: 2,
                strokeColor: Colors.indigo,
              );
            },
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [
                Colors.indigo.withOpacity(0.3),
                Colors.indigo.withOpacity(0.0),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (touchedSpot) => Colors.indigo,
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              return LineTooltipItem(
                "${spot.y.toStringAsFixed(2)} ${_selectedGraphSubject == 'Tümü' && _graphMetric == 'score' ? 'Puan' : 'Net'}",
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              );
            }).toList();
          },
        ),
      ),
    );
  }

  // Helper to parse all exam results for the student
  List<Map<String, dynamic>> _parseTrialExamResults(List<TrialExam> exams) {
    final studentNo =
        widget.student['schoolNumber']?.toString().trim() ??
        widget.student['studentNumber']?.toString().trim() ??
        widget.student['no']?.toString().trim() ??
        widget.student['number']?.toString().trim();

    final studentId = widget.student['id'].toString();
    final studentName = (widget.student['fullName'] ?? widget.student['name'])
        .toString()
        .toLowerCase();

    // ignore: avoid_print
    print(
      "DEBUG: Parsing exams for Student: $studentName (ID: $studentId, No: $studentNo)",
    );

    List<Map<String, dynamic>> results = [];

    for (var exam in exams) {
      if (!exam.isActive || !exam.isPublished || exam.resultsJson == null)
        continue;

      try {
        final List<dynamic> allResults = jsonDecode(exam.resultsJson!);
        // ignore: avoid_print
        print("DEBUG: Exam ${exam.name} has ${allResults.length} results.");

        Map<String, dynamic>? match;

        // 1. Match by Student Number
        if (studentNo != null && studentNo.isNotEmpty) {
          match = allResults.firstWhere((r) {
            final rNo =
                (r['studentNumber'] ??
                        r['number'] ??
                        r['schoolNumber'] ??
                        r['no'] ??
                        '')
                    .toString()
                    .trim();
            // print("DEBUG: Checking No ($rNo) == ($studentNo)");
            return rNo == studentNo;
          }, orElse: () => null);
        }

        // 2. Match by Student ID
        if (match == null) {
          match = allResults.firstWhere((r) {
            // print("DEBUG: Checking ID (${r['studentId']}) == ($studentId)");
            return r['studentId'].toString() == studentId ||
                r['id'].toString() == studentId;
          }, orElse: () => null);
        }

        // 3. Match by Name (Fuzzy)
        if (match == null) {
          match = allResults.firstWhere((r) {
            final rName = (r['name'] ?? r['studentName'] ?? '')
                .toString()
                .toLowerCase();
            return rName.contains(studentName);
          }, orElse: () => null);
        }

        if (match != null) {
          // ignore: avoid_print
          print("DEBUG: Match FOUND for ${exam.name}: $match");
          // Calculate total net if missing or 0
          double totalNet =
              (match['totalNet'] ?? match['net'] ?? match['netler'] ?? 0)
                  .toDouble();

          final localSubjects = match['subjects'] ?? {};
          if (totalNet == 0 && localSubjects is Map) {
            localSubjects.forEach((key, val) {
              if (val is Map) {
                totalNet += (val['net'] ?? 0).toDouble();
              } else if (val is num) {
                totalNet += val.toDouble();
              }
            });
          }

          results.add({
            'examId': exam.id,
            'examTypeId': exam.examTypeId, // Added for sorting lookup
            'examName': exam.name,
            'typeName': exam.examTypeName, // Important for grouping
            'date': exam.date,
            'score':
                (match['score'] ?? match['totalScore'] ?? match['puan'] ?? 0)
                    .toDouble(),
            'net': totalNet,
            'subjects': localSubjects,
            'rank': match['rank'],
            'institutionRank': match['institutionRank'],
            'classRank': match['classRank'],
            'generalRank': match['generalRank'],
            'studentAnswers': match['answers'],
            'examOutcomes': exam.outcomes,
            'examAnswerKeys': exam.answerKeys,
            'resultsJson':
                exam.resultsJson, // Needed for report card re-parsing
            'booklet': match['booklet'] ?? 'A', // Extract booklet
          });
        }
      } catch (e) {
        print("Error parsing exam ${exam.id}: $e");
      }
    }
    return results;
  }

  // --- 2. YAZILI SINAVLAR TAB ---
  Widget _buildWrittenExamsTab() {
    // Logic: Fetch class_exams where classId matches student's classId
    // Then check if this student has a grade in 'grades' map locally

    final classId = widget.student['classId'];
    if (classId == null)
      return _buildEmptyState('Öğrenci bir sınıfa atanmamış.');

    return StreamBuilder<QuerySnapshot>(
      stream: _writtenExamsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
          return _buildEmptyState('Yazılı sınav kaydı bulunamadı.');

        final studentId = widget.student['id'];
        final docs = snapshot.data!.docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final grades = data['grades'] as Map<String, dynamic>?;
          return grades != null && grades.containsKey(studentId);
        }).toList();

        if (docs.isEmpty)
          return _buildEmptyState('Öğrenciye ait yazılı notu bulunamadı.');

        // Extract and sort subjects
        final rawSubjects =
            docs
                .map(
                  (d) =>
                      (d.data() as Map<String, dynamic>)['lessonName']
                          ?.toString() ??
                      'Bilinmiyor',
                )
                .toSet()
                .toList()
              ..sort();

        final subjects = ['Tümü', ...rawSubjects];

        // Ensure current selection is valid
        if (!subjects.contains(_selectedWrittenSubject)) {
          _selectedWrittenSubject = 'Tümü';
        }

        // Filter by subject
        final filteredDocs = _selectedWrittenSubject == 'Tümü'
            ? docs
            : docs
                  .where(
                    (d) =>
                        (d.data() as Map<String, dynamic>)['lessonName'] ==
                        _selectedWrittenSubject,
                  )
                  .toList();

        // Sort by date desc
        filteredDocs.sort((a, b) {
          final dA = a['date'] as Timestamp?;
          final dB = b['date'] as Timestamp?;
          if (dA == null) return 1;
          if (dB == null) return -1;
          return dB.compareTo(dA);
        });

        return Column(
          children: [
            // Filter Row (Styled exactly like Homeworks tab)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.indigo.shade100),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedWrittenSubject,
                          isExpanded: true,
                          hint: Text('Branş Filtrele'),
                          icon: Icon(Icons.filter_list, color: Colors.indigo),
                          style: TextStyle(
                            color: Colors.indigo.shade900,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          items: subjects.map<DropdownMenuItem<String>>((s) {
                            return DropdownMenuItem<String>(
                              value: s,
                              child: Text(s),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null)
                              setState(() => _selectedWrittenSubject = val);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.all(16),
                itemCount: filteredDocs.length,
                itemBuilder: (context, index) {
                  final data =
                      filteredDocs[index].data() as Map<String, dynamic>;
                  final date = (data['date'] as Timestamp?)?.toDate();
                  final grades = data['grades'] as Map<String, dynamic>?;
                  final score = grades?[studentId];

                  return Card(
                    margin: EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          "$score",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade800,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      title: Text(
                        data['lessonName'] ?? 'Ders',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(data['examName'] ?? 'Yazılı Sınav'),
                      trailing: Text(
                        date != null
                            ? DateFormat('dd MMM yyyy', 'tr_TR').format(date)
                            : '-',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // --- 3. ÖDEVLER TAB ---
  Widget _buildHomeworksTab() {
    final studentId = widget.student['id'];
    final classId = widget.student['classId'];

    return StreamBuilder<QuerySnapshot>(
      stream: _homeworksStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return Center(child: CircularProgressIndicator());

        final allDocs = snapshot.data?.docs ?? [];

        // Filter valid homeworks
        final myHomeworks = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;

          // 1. Check Class Assignment (Direct classId match)
          if (classId != null && data['classId'] == classId) {
            return true;
          }

          // 2. Check Class Target Array (Legacy support if 'targetClasses' exists)
          if (classId != null && data['targetClasses'] is List) {
            final classes = List<String>.from(data['targetClasses'] ?? []);
            if (classes.contains(classId)) return true;
          }

          // 3. Check specific student assignment
          if (data['targetStudentIds'] is List) {
            final students = List<String>.from(data['targetStudentIds'] ?? []);
            if (students.contains(studentId)) return true;
          }
          // Legacy field check
          if (data['targetStudents'] is List) {
            final students = List<String>.from(data['targetStudents'] ?? []);
            if (students.contains(studentId)) return true;
          }

          return false;
        }).toList();

        // Extract subjects for filter
        final availableSubjects = <String>{'Tümü'};
        for (var h in myHomeworks) {
          final data = h.data() as Map<String, dynamic>;
          String? subject = data['subject']?.toString();

          // Fallback: extract from title if empty
          if (subject == null || subject.isEmpty) {
            final title = data['title']?.toString() ?? '';
            if (title.contains(' - ')) {
              subject = title.split(' - ').first.trim();
            } else if (title.contains('-')) {
              subject = title.split('-').first.trim();
            }
          }

          if (subject != null && subject.isNotEmpty) {
            availableSubjects.add(subject);
          }
        }
        final subjectsList = availableSubjects.toList()..sort();

        // Apply branch filter
        final filteredHomeworks = myHomeworks.where((h) {
          if (_selectedHomeworkSubject == 'Tümü') return true;
          final data = h.data() as Map<String, dynamic>;
          String? subject = data['subject']?.toString();

          // Fallback: extract from title if empty
          if (subject == null || subject.isEmpty) {
            final title = data['title']?.toString() ?? '';
            if (title.contains(' - ')) {
              subject = title.split(' - ').first.trim();
            } else if (title.contains('-')) {
              subject = title.split('-').first.trim();
            }
          }

          return subject == _selectedHomeworkSubject;
        }).toList();

        if (myHomeworks.isEmpty) return _buildEmptyState('Ödev bulunamadı.');

        // Stats based on FILTERED homeworks
        int total = filteredHomeworks.length;
        int completed = 0;

        for (var h in filteredHomeworks) {
          final data = h.data() as Map<String, dynamic>;
          if (data['studentStatuses'] is Map) {
            final statuses = data['studentStatuses'] as Map;
            if (statuses[studentId] == 1) completed++;
          }
        }
        int pending = total - completed;

        return Column(
          children: [
            // 1. Subject Filter Row (Now at the top)
            if (subjectsList.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.indigo.shade100),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedHomeworkSubject,
                            isExpanded: true,
                            hint: Text('Branş Filtrele'),
                            icon: Icon(Icons.filter_list, color: Colors.indigo),
                            style: TextStyle(
                              color: Colors.indigo.shade900,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            items: subjectsList.map((s) {
                              return DropdownMenuItem(value: s, child: Text(s));
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedHomeworkSubject = val);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // 2. Stats Row (Now follows filter)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  _buildStatCard('Toplam', '$total', Colors.blue),
                  SizedBox(width: 12),
                  _buildStatCard('Tamamlanan', '$completed', Colors.green),
                  SizedBox(width: 12),
                  _buildStatCard('Eksik', '$pending', Colors.orange),
                ],
              ),
            ),

            Expanded(
              child: filteredHomeworks.isEmpty
                  ? Center(child: Text('Seçili branşta ödev bulunamadı.'))
                  : ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filteredHomeworks.length,
                      itemBuilder: (context, index) {
                        final data =
                            filteredHomeworks[index].data()
                                as Map<String, dynamic>;
                        final assignedDate =
                            _parseDate(data['assignedDate']) ??
                            _parseDate(data['createdAt']);
                        final dueDate = _parseDate(data['dueDate']);
                        final description = data['content']?.toString() ?? '';

                        String? displaySubject = data['subject']?.toString();
                        if (displaySubject == null || displaySubject.isEmpty) {
                          final title = data['title']?.toString() ?? '';
                          if (title.contains(' - ')) {
                            displaySubject = title.split(' - ').first.trim();
                          } else if (title.contains('-')) {
                            displaySubject = title.split('-').first.trim();
                          }
                        }
                        displaySubject ??= '-';

                        bool isDone = false;
                        // Check studentStatuses map (studentId -> int where 1 is done)
                        if (data['studentStatuses'] is Map) {
                          final statuses = data['studentStatuses'] as Map;
                          isDone = statuses[studentId] == 1;
                        }

                        final screenWidth = MediaQuery.of(context).size.width;
                        final isSmallMobile = screenWidth < 360;

                        return Card(
                          margin: EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              _showHomeworkDetailDialog(
                                context,
                                data,
                                displaySubject ?? '-',
                                isDone,
                                assignedDate,
                                dueDate,
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    isDone
                                        ? Icons.check_circle
                                        : Icons.circle_outlined,
                                    color: isDone
                                        ? Colors.green
                                        : Colors.grey.shade400,
                                    size: isSmallMobile ? 24 : 32,
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          data['title'] ?? 'Ödev',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: isSmallMobile ? 13 : 15,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                            bottom: 4,
                                          ),
                                          child: Text(
                                            "$displaySubject | ${description.isNotEmpty ? description : 'Açıklama yok'}",
                                            style: TextStyle(
                                              fontSize: isSmallMobile ? 11 : 12,
                                              color: Colors.indigo.shade800,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          children: [
                                            if (assignedDate != null)
                                              Text(
                                                DateFormat(
                                                  'dd.MM.yyyy',
                                                ).format(assignedDate),
                                                style: TextStyle(
                                                  fontSize: isSmallMobile
                                                      ? 10
                                                      : 11,
                                                  color: Colors.grey.shade600,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            if (assignedDate != null &&
                                                dueDate != null)
                                              Text(
                                                "-",
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey.shade400,
                                                ),
                                              ),
                                            if (dueDate != null)
                                              Text(
                                                DateFormat(
                                                  'dd.MM.yyyy',
                                                ).format(dueDate),
                                                style: TextStyle(
                                                  fontSize: isSmallMobile
                                                      ? 10
                                                      : 11,
                                                  color: Colors.orange.shade700,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDone
                                          ? Colors.green.shade50
                                          : Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      isDone ? 'TAMAMLANDI' : 'BEKLİYOR',
                                      style: TextStyle(
                                        color: isDone
                                            ? Colors.green
                                            : Colors.orange,
                                        fontWeight: FontWeight.bold,
                                        fontSize: isSmallMobile ? 8 : 10,
                                      ),
                                    ),
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
        );
      },
    );
  }

  void _showHomeworkDetailDialog(
    BuildContext context,
    Map<String, dynamic> data,
    String displaySubject,
    bool isDone,
    DateTime? assignedDate,
    DateTime? dueDate,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: EdgeInsets.zero,
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDone ? Colors.green.shade600 : Colors.indigo.shade800,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          displaySubject,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close, color: Colors.white),
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    data['title'] ?? 'Ödev Detayı',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 16,
                          color: Colors.grey,
                        ),
                        SizedBox(width: 8),
                        Text(
                          "${assignedDate != null ? DateFormat('dd.MM.yyyy').format(assignedDate) : '-'}  →  ${dueDate != null ? DateFormat('dd.MM.yyyy').format(dueDate) : '-'}",
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 20),
                    Text(
                      "Ödev İçeriği",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Text(
                        data['content'] ?? 'İçerik belirtilmemiş.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: Colors.blueGrey.shade900,
                        ),
                      ),
                    ),
                    if (data['attachments'] != null &&
                        (data['attachments'] as List).isNotEmpty) ...[
                      SizedBox(height: 24),
                      Text(
                        "Ekler",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                      SizedBox(height: 8),
                      ...(data['attachments'] as List).map(
                        (a) => Card(
                          margin: EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            dense: true,
                            leading: Icon(
                              Icons.attach_file,
                              color: Colors.orange,
                            ),
                            title: Text(
                              a['title'] ?? 'Dosya',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            trailing: Icon(
                              Icons.open_in_new,
                              size: 16,
                              color: Colors.grey,
                            ),
                            onTap: () {
                              // Handle opening attachment URL
                            },
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.all(20),
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDone ? Colors.green : Colors.indigo,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  minimumSize: Size(double.infinity, 50),
                  elevation: 0,
                ),
                child: Text(
                  "KAPAT",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceTab() {
    final studentId = widget.student['id'];

    return StreamBuilder<QuerySnapshot>(
      stream: _attendanceStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint("Devamsızlık Hatası: ${snapshot.error}");
          return _buildEmptyState(
            'Veri yüklenirken hata oluştu: ${snapshot.error}',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting)
          return Center(child: CircularProgressIndicator());

        final docs = snapshot.data?.docs ?? [];

        // 1. First, process ALL data to extract unique lessons for the filter
        final allAttendanceHistory = <Map<String, dynamic>>[];
        final availableLessons = <String>{'Tümü'};

        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final statuses = data['studentStatuses'] as Map? ?? {};
          final status = (statuses[studentId] ?? '').toString();

          if (status.isEmpty || status == 'present') continue;

          String lessonName = data['lessonName'] ?? 'Ders';
          availableLessons.add(lessonName);

          allAttendanceHistory.add({
            'date': data['date'],
            'hour': data['lessonHour'],
            'lesson': lessonName,
            'status': status,
          });
        }

        final sortedLessons = availableLessons.toList()
          ..sort((a, b) {
            if (a == 'Tümü') return -1;
            if (b == 'Tümü') return 1;
            return a.compareTo(b);
          });

        // 2. Filter the history based on selected lesson
        final filteredHistory = allAttendanceHistory.where((item) {
          if (_selectedAttendanceLesson == 'Tümü') return true;
          return item['lesson'] == _selectedAttendanceLesson;
        }).toList();

        // 3. Calculate stats based on FILTERED history
        int absentLessons = 0;
        int lateLessons = 0;
        int excusedLessons = 0;
        int reportedLessons = 0;
        int onDutyLessons = 0;

        for (var item in filteredHistory) {
          final status = item['status'];
          if (status == 'absent')
            absentLessons++;
          else if (status == 'late')
            lateLessons++;
          else if (status == 'excused')
            excusedLessons++;
          else if (status == 'reported')
            reportedLessons++;
          else if (status == 'onDuty')
            onDutyLessons++;
        }

        if (allAttendanceHistory.isEmpty) {
          return _buildEmptyState('Devamsızlık kaydı yok.');
        }

        return Column(
          children: [
            // Filter Dropdown (Styled like Homeworks Tab)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.indigo.shade100),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedAttendanceLesson,
                          isExpanded: true,
                          hint: Text('Ders Filtrele'),
                          icon: Icon(Icons.filter_list, color: Colors.indigo),
                          style: TextStyle(
                            color: Colors.indigo.shade900,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedAttendanceLesson = newValue;
                              });
                            }
                          },
                          items: sortedLessons.map<DropdownMenuItem<String>>((
                            String value,
                          ) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  _buildStatCard('Gelmedi', '$absentLessons', Colors.red),
                  SizedBox(width: 8),
                  _buildStatCard('Geç', '$lateLessons', Colors.orange),
                  SizedBox(width: 8),
                  _buildStatCard(
                    'İzinli',
                    '${excusedLessons + reportedLessons + onDutyLessons}',
                    Colors.blue,
                  ),
                ],
              ),
            ),
            Expanded(
              child: filteredHistory.isEmpty
                  ? Center(child: Text('Seçili derse ait kayıt bulunamadı.'))
                  : ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filteredHistory.length,
                      itemBuilder: (context, index) {
                        final item = filteredHistory[index];
                        final status = item['status'];

                        Color statusColor = Colors.grey;
                        String statusText = status;

                        if (status == 'absent') {
                          statusColor = Colors.red;
                          statusText = 'Gelmedi';
                        } else if (status == 'late') {
                          statusColor = Colors.orange;
                          statusText = 'Geç Geldi';
                        } else if (status == 'excused') {
                          statusColor = Colors.blue;
                          statusText = 'İzinli';
                        } else if (status == 'reported') {
                          statusColor = Colors.purple;
                          statusText = 'Raporlu';
                        } else if (status == 'onDuty') {
                          statusColor = Colors.indigo;
                          statusText = 'Görevli';
                        }

                        return Card(
                          margin: EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: statusColor.withOpacity(0.1),
                              child: Icon(
                                Icons.event_busy,
                                color: statusColor,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              "${item['lesson'] ?? 'Ders'}",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              "${item['date']} • ${item['hour']}. Ders",
                              style: TextStyle(fontSize: 12),
                            ),
                            trailing: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEtutlerTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _etutlerStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
          return _buildEmptyState('Planlanmış etüt bulunmuyor.');

        final allDocs = snapshot.data!.docs;

        // 1. Extract Subjects
        Set<String> subjects = {'Tümü'};
        for (var doc in allDocs) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['subject'] != null) {
            subjects.add(data['subject'].toString());
          }
        }
        final sortedSubjects = subjects.toList()..sort();

        // 2. Filter
        final filteredDocs = allDocs.where((doc) {
          if (_selectedEtutSubject == 'Tümü') return true;
          final data = doc.data() as Map<String, dynamic>;
          return data['subject'] == _selectedEtutSubject;
        }).toList();

        return Column(
          children: [
            // Filter Dropdown
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.indigo.shade100),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedEtutSubject,
                    isExpanded: true,
                    hint: Text('Ders Filtrele'),
                    icon: Icon(Icons.filter_list, color: Colors.indigo),
                    style: TextStyle(
                      color: Colors.indigo.shade900,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _selectedEtutSubject = newValue;
                        });
                      }
                    },
                    items: sortedSubjects.map<DropdownMenuItem<String>>((
                      String value,
                    ) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
            // List
            Expanded(
              child: filteredDocs.isEmpty
                  ? Center(child: Text('Seçili derse ait etüt bulunamadı.'))
                  : ListView.builder(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: filteredDocs.length,
                      itemBuilder: (context, index) {
                        final data =
                            filteredDocs[index].data() as Map<String, dynamic>;
                        final date = (data['date'] as Timestamp?)?.toDate();
                        final subject = data['subject'] ?? 'Ders';
                        final topic = data['topic'] ?? 'Konu';
                        final teacher = data['teacherName'] ?? 'Öğretmen';
                        final status = data['status'] ?? 'pending';

                        Color statusColor = Colors.orange;
                        String statusText = 'Beklemede';
                        if (status == 'completed') {
                          statusColor = Colors.green;
                          statusText = 'Tamamlandı';
                        } else if (status == 'cancelled') {
                          statusColor = Colors.red;
                          statusText = 'İptal';
                        }

                        return Card(
                          margin: EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: statusColor.withOpacity(0.1),
                              child: Icon(
                                Icons.school,
                                color: statusColor,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              'Etüt',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                              ),
                            ),
                            subtitle: Text(
                              '$teacher\n$subject - $topic\n${date != null ? DateFormat('dd.MM.yyyy HH:mm').format(date) : '-'}',
                            ),
                            trailing: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBooksTab() {
    final sid = widget.student['id'];
    final classId = widget.student['classId'];
    final classLevel = widget.student['classLevel']?.toString();
    final schoolTypeId = widget.student['schoolTypeId'];

    List<String> targetIds = [sid];
    if (classId != null) targetIds.add(classId);
    if (classLevel != null) targetIds.add(classLevel);
    if (schoolTypeId != null) targetIds.add(schoolTypeId);

    return Column(
      children: [
        // Sub-tabs (Toggle)
        Container(
          margin: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              _buildBookSubTabButton('Soru Bankası', BookType.questionBank),
              _buildBookSubTabButton('Okuma Kitabı', BookType.reading),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('book_assignments')
                .where('institutionId', isEqualTo: widget.institutionId)
                .where('targetId', whereIn: targetIds)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return Center(child: Text('Hata: ${snapshot.error}'));
              if (snapshot.connectionState == ConnectionState.waiting)
                return const Center(child: CircularProgressIndicator());

              final assignments = snapshot.data!.docs
                  .map(
                    (doc) => BookAssignment.fromMap(
                      doc.data() as Map<String, dynamic>,
                      doc.id,
                    ),
                  )
                  .toList();

              if (assignments.isEmpty) {
                return _buildEmptyState('Atanmış kitap bulunamadı.');
              }

              final bookIds = assignments.map((a) => a.bookId).toSet().toList();

              return FutureBuilder<QuerySnapshot>(
                future: FirebaseFirestore.instance
                    .collection('books')
                    .where(FieldPath.documentId, whereIn: bookIds)
                    .get(),
                builder: (context, bookSnap) {
                  if (bookSnap.connectionState == ConnectionState.waiting)
                    return const Center(child: CircularProgressIndicator());
                  if (bookSnap.hasError)
                    return Center(child: Text('Kitaplar yüklenirken hata.'));

                  final allBooks = bookSnap.data!.docs
                      .map(
                        (doc) => Book.fromMap(
                          doc.data() as Map<String, dynamic>,
                          doc.id,
                        ),
                      )
                      .toList();

                  // Filter by selected sub-tab
                  final books = allBooks
                      .where((b) => b.type == _activeBookTabFilter)
                      .toList();

                  if (books.isEmpty) {
                    return _buildEmptyState(
                      _activeBookTabFilter == BookType.questionBank
                          ? 'Atanmış soru bankası bulunmuyor.'
                          : 'Atanmış okuma kitabı bulunmuyor.',
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(24),
                    itemCount: books.length,
                    itemBuilder: (context, index) {
                      final book = books[index];
                      final isQB = book.type == BookType.questionBank;
                      double progress = 0.0;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 2,
                        child: InkWell(
                          onTap: () {},
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isQB
                                            ? Colors.blue.shade50
                                            : Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        isQB
                                            ? Icons.quiz_rounded
                                            : Icons.auto_stories_rounded,
                                        color: isQB
                                            ? Colors.blue.shade700
                                            : Colors.green.shade700,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            book.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          Text(
                                            isQB
                                                ? (book.branch ?? 'Genel')
                                                : (book.author ??
                                                      'Bilinmeyen Yazar'),
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Tamamlama Oranı',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade700,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      '%${(progress * 100).toInt()}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.indigo,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    backgroundColor: Colors.grey.shade200,
                                    color: Colors.indigo,
                                    minHeight: 8,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (isQB) ...[
                                  Text(
                                    '${book.topics.length} Ünite/Konu İçeriği',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ] else ...[
                                  Text(
                                    '${book.pageCount ?? '-'} Sayfa',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
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

  Widget _buildBookSubTabButton(String label, BookType type) {
    final isSelected = _activeBookTabFilter == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeBookTabFilter = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.indigo.shade800 : Colors.grey.shade500,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInterviewsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _interviewsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint("Görüşme Hatası: ${snapshot.error}");
          return _buildEmptyState(
            'Veri yüklenirken hata oluştu: ${snapshot.error}',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting)
          return Center(child: CircularProgressIndicator());

        final docs = snapshot.data?.docs ?? [];
        debugPrint("Görüşme Veri Sayısı: ${docs.length}");

        if (docs.isEmpty) return _buildEmptyState('Görüşme kaydı bulunmuyor.');

        // Extract unique titles for filtering
        final titles = <String>{'Tümü'};
        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final title = data['title'] as String?;
          if (title != null && title.isNotEmpty) {
            titles.add(title);
          }
        }

        final sortedTitles = titles.toList()
          ..sort((a, b) {
            if (a == 'Tümü') return -1;
            if (b == 'Tümü') return 1;
            return a.compareTo(b);
          });

        // Filter documents based on selection
        final filteredDocs = docs.where((doc) {
          if (_selectedInterviewTitle == 'Tümü') return true;
          final data = doc.data() as Map<String, dynamic>;
          return data['title'] == _selectedInterviewTitle;
        }).toList();

        return Column(
          children: [
            // Filter UI
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.indigo.shade100),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedInterviewTitle,
                          isExpanded: true,
                          icon: Icon(Icons.filter_list, color: Colors.indigo),
                          style: TextStyle(
                            color: Colors.indigo.shade900,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          items: sortedTitles.map((s) {
                            return DropdownMenuItem<String>(
                              value: s,
                              child: Text(s),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null)
                              setState(() => _selectedInterviewTitle = val);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Results List
            Expanded(
              child: filteredDocs.isEmpty
                  ? _buildEmptyState('Seçili başlıkta görüşme bulunmuyor.')
                  : ListView.builder(
                      padding: EdgeInsets.all(16),
                      itemCount: filteredDocs.length,
                      itemBuilder: (context, index) {
                        final data =
                            filteredDocs[index].data() as Map<String, dynamic>;
                        final date = (data['date'] as Timestamp?)?.toDate();
                        final isPrivate = data['isPrivate'] ?? false;
                        final interviewerName =
                            data['interviewerName'] ?? 'Bilinmiyor';

                        return Card(
                          margin: EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            onTap: () => _showInterviewDetailDialog(data),
                            leading: CircleAvatar(
                              backgroundColor: isPrivate
                                  ? Colors.red.shade50
                                  : Colors.purple.shade50,
                              child: Icon(
                                isPrivate
                                    ? Icons.lock
                                    : Icons.chat_bubble_outline,
                                color: isPrivate ? Colors.red : Colors.purple,
                              ),
                            ),
                            title: Text(
                              data['title'] ?? 'Görüşme',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(height: 4),
                                Text(
                                  isPrivate
                                      ? '🔒 Gizli Görüşme'
                                      : (data['notes'] ?? 'Not yok'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontStyle: isPrivate
                                        ? FontStyle.italic
                                        : null,
                                    color: isPrivate
                                        ? Colors.red.shade700
                                        : null,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.person_outline,
                                      size: 12,
                                      color: Colors.grey,
                                    ),
                                    SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        interviewerName,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      date != null
                                          ? DateFormat(
                                              'dd.MM.yyyy',
                                            ).format(date)
                                          : '-',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            trailing: Icon(Icons.chevron_right, size: 20),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDevelopmentReportTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('development_reports')
          .where('targetId', isEqualTo: widget.student['id'])
          .where('isPublished', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
          return _buildEmptyState(
            'Henüz yayınlanmış bir gelişim raporu bulunmuyor.',
          );

        return ListView.builder(
          padding: EdgeInsets.all(20),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final report = DevelopmentReport.fromMap({...data, 'id': doc.id});
            final studentName = widget.student['fullName'] ?? 'Öğrenci';

            return Container(
              margin: EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.indigo.withOpacity(0.05),
                    blurRadius: 15,
                    offset: Offset(0, 5),
                  ),
                ],
                border: Border.all(color: Colors.indigo.withOpacity(0.05)),
              ),
              child: Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  leading: Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.description_outlined,
                      color: Colors.indigo,
                      size: 24,
                    ),
                  ),
                  title: Text(
                    "${report.term}",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Row(
                      children: [
                        _buildMiniBadge(
                          "Endeks: ${report.growthIndex ?? '0.0'}",
                          Colors.indigo,
                        ),
                        SizedBox(width: 8),
                        _buildMiniBadge(
                          report.riskScore != null && report.riskScore! > 30
                              ? 'Riskli'
                              : 'Güvenli',
                          report.riskScore != null && report.riskScore! > 30
                              ? Colors.red
                              : Colors.green,
                        ),
                      ],
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.picture_as_pdf,
                          color: Colors.blue,
                          size: 20,
                        ),
                        onPressed: () {
                          DevelopmentReportPdfHelper.generateAndPrint(
                            report,
                            studentName,
                          );
                        },
                      ),
                      Icon(
                        Icons.expand_more_rounded,
                        color: Colors.indigo.shade200,
                      ),
                    ],
                  ),
                  children: [
                    Divider(height: 1, color: Colors.grey.withOpacity(0.1)),
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: DevelopmentReportContent(
                        report: report,
                        studentName: studentName,
                        showHeader: false,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMiniBadge(String text, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildGuidanceTestsTab() {
    // Note: Assuming 'applied_tests' or similar. If 'surveys' is used, this needs update.
    // For now, keeping as placeholder query but standardizing on institutionId if possible.
    return StreamBuilder<QuerySnapshot>(
      stream: _guidanceTestsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
          return _buildEmptyState('Uygulanan test bulunmuyor.');

        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final data =
                snapshot.data!.docs[index].data() as Map<String, dynamic>;
            final date = (data['completedAt'] as Timestamp?)?.toDate();

            return Card(
              margin: EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: Icon(Icons.assignment_turned_in, color: Colors.teal),
                title: Text(
                  data['testName'] ?? 'Rehberlik Testi',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  "Sonuç: ${data['resultSummary'] ?? 'Detay görüntüle'}",
                ),
                trailing: Text(
                  date != null ? DateFormat('dd.MM.yyyy').format(date) : '-',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStudyProgramsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _studyProgramsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
          return _buildEmptyState('Çalışma programı bulunmuyor.');

        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final data =
                snapshot.data!.docs[index].data() as Map<String, dynamic>;
            final start =
                _parseDate(data['startDate']) ?? _parseDate(data['createdAt']);

            // Generic format
            String toDate(DateTime? d) =>
                d == null ? '?' : DateFormat('dd.MM.yyyy').format(d);

            // Calculate percentage
            final schedule = data['schedule'] as Map<String, dynamic>? ?? {};
            final executionStatus =
                data['executionStatus'] as Map<String, dynamic>? ?? {};

            int total = 0;
            int done = 0;
            int incomplete = 0;

            executionStatus.values.forEach((list) {
              if (list is List) {
                total += list.length;
                done += list.where((s) => s == 1).length;
                incomplete += list.where((s) => s == 2).length;
              }
            });

            // Fallback total from schedule if executionStatus is empty
            if (total == 0) {
              schedule.values.forEach((list) {
                if (list is List) total += list.length;
              });
            }

            final percentage = total > 0
                ? ((done + (incomplete * 0.5)) / total * 100).round()
                : 0;

            final programData = Map<String, dynamic>.from(data);
            programData['id'] = snapshot.data!.docs[index].id;

            return Container(
              margin: EdgeInsets.only(bottom: 12),
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
              child: ExpansionTile(
                key: ValueKey('study_final_${snapshot.data!.docs[index].id}'),
                maintainState: true,
                tilePadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                collapsedShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                backgroundColor: Colors.indigo.shade50.withOpacity(0.05),
                leading: CircleAvatar(
                  backgroundColor: Colors.orange.shade50,
                  child: Icon(Icons.schedule, color: Colors.orange, size: 20),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.print, color: Colors.indigo, size: 20),
                      onPressed: () =>
                          StudyProgramPrintingHelper.generateBulkPdf(context, [
                            programData,
                          ]),
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.expand_more, color: Colors.grey),
                  ],
                ),
                title: Text(
                  data['title'] ?? 'Çalışma Programı',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Veriliş: ${toDate(start)}",
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: percentage / 100,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                percentage > 70
                                    ? Colors.green
                                    : percentage > 30
                                    ? Colors.orange
                                    : Colors.red,
                              ),
                              minHeight: 4,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          "%$percentage",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(height: 1, color: Colors.indigo.shade100),
                        SizedBox(height: 16),
                        if (data['description'] != null &&
                            data['description']
                                .toString()
                                .trim()
                                .isNotEmpty) ...[
                          Text(
                            data['description'].toString().trim(),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blueGrey.shade800,
                              height: 1.4,
                            ),
                          ),
                          SizedBox(height: 20),
                        ],

                        ...(() {
                          final List<String> dayOrder = [
                            'Pazartesi',
                            'Salı',
                            'Çarşamba',
                            'Perşembe',
                            'Cuma',
                            'Cumartesi',
                            'Pazar',
                          ];
                          final keys = schedule.keys.toList();
                          keys.sort((a, b) {
                            int idxA = dayOrder.indexWhere(
                              (d) =>
                                  d.toLowerCase() ==
                                  a.toString().toLowerCase().trim(),
                            );
                            int idxB = dayOrder.indexWhere(
                              (d) =>
                                  d.toLowerCase() ==
                                  b.toString().toLowerCase().trim(),
                            );
                            if (idxA != -1 && idxB != -1)
                              return idxA.compareTo(idxB);
                            if (idxA != -1) return -1;
                            if (idxB != -1) return 1;
                            return a.toString().compareTo(b.toString());
                          });

                          return keys.map((key) {
                            final lessons = schedule[key] as List?;
                            if (lessons == null || lessons.isEmpty)
                              return SizedBox.shrink();
                            final dayStatuses = executionStatus[key] as List?;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.indigo,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        key.toString(),
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Divider(
                                        indent: 8,
                                        color: Colors.indigo.shade50,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 12),
                                ...lessons.asMap().entries.map((entry) {
                                  final int idx = entry.key;
                                  final String lessonText = entry.value
                                      .toString();
                                  final int status =
                                      (dayStatuses != null &&
                                          dayStatuses.length > idx)
                                      ? (int.tryParse(
                                              dayStatuses[idx].toString(),
                                            ) ??
                                            0)
                                      : 0;

                                  IconData icon = Icons.circle_outlined;
                                  Color color = Colors.grey;
                                  if (status == 1) {
                                    icon = Icons.check_circle;
                                    color = Colors.green;
                                  } else if (status == 2) {
                                    icon = Icons.access_time_filled;
                                    color = Colors.orange;
                                  } else if (status == 3) {
                                    icon = Icons.cancel;
                                    color = Colors.red;
                                  }

                                  return Container(
                                    margin: EdgeInsets.only(bottom: 12),
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.grey.shade100,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.01),
                                          blurRadius: 4,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(icon, size: 18, color: color),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            lessonText.trim(),
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.blueGrey.shade900,
                                              height: 1.3,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                SizedBox(height: 8),
                              ],
                            );
                          }).toList();
                        })(),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showInterviewDetailDialog(Map<String, dynamic> data) {
    final date = (data['date'] as Timestamp?)?.toDate();
    final isPrivate = data['isPrivate'] ?? false;
    final interviewerName = data['interviewerName'] ?? 'Bilinmiyor';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade600,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.chat_bubble, color: Colors.white, size: 28),
                      SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          data['title'] ?? 'Görüşme Detayı',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow(
                        Icons.person,
                        "Görüşen Kişi",
                        interviewerName,
                      ),
                      SizedBox(height: 16),
                      _buildDetailRow(
                        Icons.calendar_today,
                        "Görüşme Tarihi",
                        date != null
                            ? DateFormat(
                                'dd MMMM yyyy HH:mm',
                                'tr_TR',
                              ).format(date)
                            : '-',
                      ),
                      SizedBox(height: 24),
                      Text(
                        "Görüşme Notları",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                      SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isPrivate
                              ? Colors.red.shade50
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isPrivate
                                ? Colors.red.shade200
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: isPrivate
                            ? Row(
                                children: [
                                  Icon(Icons.lock, color: Colors.red, size: 20),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      "Bu görüşme gizli olarak işaretlenmiştir. İçeriği görüntüleme yetkiniz bulunmamaktadır.",
                                      style: TextStyle(
                                        color: Colors.red.shade800,
                                        fontSize: 14,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                data['notes'] ?? 'Not girilmemiş.',
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.6,
                                  color: Colors.blueGrey.shade900,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.indigo.shade400),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.blueGrey.shade900,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- HELPER --

  // Robust Date Parser
  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  // --- 8. ETKİNLİK RAPORLARI TAB ---
  Widget _buildActivityReportsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _activityReportsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
          return _buildEmptyState('Etkinlik raporu bulunmuyor.');

        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final data =
                snapshot.data!.docs[index].data() as Map<String, dynamic>;
            final date = (data['date'] as Timestamp?)?.toDate();

            return Card(
              margin: EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: Icon(Icons.event_note, color: Colors.green),
                title: Text(
                  data['activityName'] ?? 'Etkinlik',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(data['notes'] ?? 'Not yok'),
                trailing: Text(
                  date != null ? DateFormat('dd.MM.yyyy').format(date) : '-',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Expanded(
      child: Container(
        height: isMobile ? 85 : 100,
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.05),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: isMobile ? 22 : 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                title,
                style: TextStyle(
                  fontSize: isMobile ? 11 : 13,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, size: 48, color: Colors.grey.shade300),
          SizedBox(height: 12),
          Text(msg, style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  // --- HELPERS ---
  Widget _buildInfoGrid(List<Widget> children) {
    if (MediaQuery.of(context).size.width < 600) {
      return Column(
        children: children
            .map((c) => Padding(padding: EdgeInsets.only(bottom: 8), child: c))
            .toList(),
      );
    }
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      childAspectRatio: 2.5,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: children,
    );
  }

  Widget _buildInfoCard(
    IconData icon,
    String label,
    String value, {
    Color color = Colors.indigo,
  }) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
} // End of _PortfolioScreenState class
