import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../school/assessment/evaluation_models.dart';
import '../school/assessment/student_report_card_dialog.dart';
import '../school/assessment/exam_report_card_service.dart';
import '../../models/assessment/lgs_data.dart';

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import '../../services/assessment_service.dart';
import '../../models/assessment/trial_exam_model.dart';
import '../../models/assessment/exam_type_model.dart';
import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'topic_analysis_detail_screen.dart';
import '../school/guidance/study_program_printing_helper.dart';
import '../../models/school/book_model.dart';
import '../../models/school/book_assignment_model.dart';
import '../../models/guidance/development_report/development_report_model.dart';

import 'development_report_detail_screen.dart';
import '../guidance/reports/development_report_pdf_helper.dart';
import 'portfolio_guide_page.dart';
import 'portfolio_report_dialog.dart';
import '../../services/term_service.dart';
import '../school/guidance/demand/create_demand_dialog.dart';
import '../../models/guidance/demand_model.dart';
import '../../services/guidance/demand_service.dart';
import '../../services/guidance_service.dart';
import '../student/student_homework_stats_screen.dart';
import '../student/student_attendance_stats_screen.dart';
import '../student/student_etut_stats_screen.dart';
import '../student/student_exam_stats_screen.dart';
import 'package:edukn/widgets/safe_stream_builder.dart';
import '../../services/user_permission_service.dart';
import '../../services/course_track_resolver.dart';


class PortfolioScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;

  final List<String>? allowedClassIds;
  final String? initialStudentId;
  final bool showAllSchoolTypes;

  const PortfolioScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.allowedClassIds,
    this.initialStudentId,
    this.showAllSchoolTypes = false,
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
  List<String> _schoolTypeGrades = [];
  List<String> _classLevels = [];
  List<String> _classes = [];

  String? _extractLevelKey(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') return null;

    final lower = trimmed.toLowerCase();
    if (lower.contains('mezun')) return 'Mezun';
    if (lower.contains('hazırlık') || lower.contains('hazirlik')) return 'Hazırlık';
    if (lower.contains('anaokul') || lower.contains('anasınıf') || lower.contains('anasinif')) {
      return 'Anaokulu';
    }

    // Doğrudan "5", "7. Sınıf", "12.Sınıf" vb.
    final directGrade = RegExp(
      r'^(1[0-2]|[1-9])\s*(?:\.\s*s[ıi]n[ıi]f.*)?$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (directGrade != null) {
      return directGrade.group(1)!;
    }

    // 4 haneli şube kodu: 1001, 1102, 1201 -> 10, 11, 12
    final m4 = RegExp(r'^(1[0-2])\d{2}\b').firstMatch(trimmed);
    if (m4 != null) return m4.group(1)!;

    // 3 haneli şube kodu: 501, 607, 708, 804 -> 5, 6, 7, 8
    final m3 = RegExp(r'^([1-9])\d{2}\b').firstMatch(trimmed);
    if (m3 != null) return m3.group(1)!;

    // Tireli/harfli şube kodu: 7-A, 7/B, 7A, 12-A -> 7, 12
    final mSep = RegExp(r'^(1[0-2]|[1-9])(?:\s*[-/.\s]\s*|[A-Za-zÇĞİÖŞÜçğıöşü])').firstMatch(trimmed);
    if (mSep != null) return mSep.group(1)!;

    return null;
  }

  String _formatLevelLabel(String levelKey) {
    if (int.tryParse(levelKey) != null) {
      return '$levelKey. Sınıf';
    }
    return levelKey;
  }

  String? _getStudentLevelKey(Map<String, dynamic> s) {
    final rawLevel = (s['classLevel'] ?? s['grade'] ?? s['level'] ?? '').toString().trim();
    final fromLevel = _extractLevelKey(rawLevel);
    if (fromLevel != null && fromLevel.isNotEmpty) return fromLevel;

    final rawClass = (s['className'] ?? s['branch'] ?? '').toString().trim();
    return _extractLevelKey(rawClass);
  }

  String? _getClassLevelKey(String className) {
    final direct = _extractLevelKey(className);
    if (direct != null && direct.isNotEmpty) return direct;

    for (final s in _allStudents) {
      if ((s['className'] ?? '').toString().trim() == className.trim()) {
        final k = _getStudentLevelKey(s);
        if (k != null && k.isNotEmpty) return k;
      }
    }
    return null;
  }

  List<String> get _filteredClassesForSelectedLevel {
    final selectedKey = _extractLevelKey(_filterClassLevel);
    if (selectedKey == null) return _classes;
    return _classes.where((c) => _getClassLevelKey(c) == selectedKey).toList();
  }

  // Scroll
  final ScrollController _studentListScrollController = ScrollController();
  final GlobalKey _selectedStudentCardKey = GlobalKey();

  // Report Context
  String? _activeTermId;
  Map<String, dynamic> _schoolSettings = {};

  @override
  void initState() {
    super.initState();
    _loadStudents();
    _loadActiveFilterData();
    _loadReportContext();
    _searchController.addListener(_filterStudents);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _studentListScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadActiveFilterData() async {
    try {
      if (widget.showAllSchoolTypes) {
        final snapshot = await FirebaseFirestore.instance
            .collection('schoolTypes')
            .where('institutionId', isEqualTo: widget.institutionId)
            .get();

        final Set<String> allGrades = {};
        for (var doc in snapshot.docs) {
          final data = doc.data();
          if (data['activeGrades'] != null) {
            allGrades.addAll(List<String>.from(data['activeGrades'].map((e) => e.toString())));
          }
        }

        if (mounted) {
          _schoolTypeGrades = allGrades.toList();
          _extractFilterData();
        }
      } else {
        final doc = await FirebaseFirestore.instance
            .collection('schoolTypes')
            .doc(widget.schoolTypeId)
            .get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          if (data['activeGrades'] != null) {
            final grades = List<String>.from(
              data['activeGrades'].map((e) => e.toString()),
            );
            final stName = (data['name'] ?? widget.schoolTypeName)
                .toString()
                .toLowerCase();
            if (stName.contains('lise') && !grades.contains('Mezun')) {
              grades.add('Mezun');
            }
            if (mounted) {
              _schoolTypeGrades = grades;
              _extractFilterData();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading active filter data: $e');
    }
  }

  Future<void> _loadReportContext() async {
    try {
      _activeTermId = await TermService().getActiveTermId();
      final instDoc = await FirebaseFirestore.instance
          .collection('institutions')
          .doc(widget.institutionId)
          .get();
      if (instDoc.exists) {
        setState(() {
          _schoolSettings = instDoc.data() ?? {};
        });
      }
    } catch (e) {
      debugPrint('Error loading report context: $e');
    }
  }

  Future<void> _loadStudents() async {
    setState(() => _isLoading = true);
    try {
      List<Map<String, dynamic>> students = [];

      if (widget.allowedClassIds != null && widget.allowedClassIds!.isNotEmpty) {
        // Teacher mode: Filter by assigned classes using chunks (max 10-30 per whereIn)
        final classChunks = <List<String>>[];
        for (var i = 0; i < widget.allowedClassIds!.length; i += 10) {
          classChunks.add(widget.allowedClassIds!.skip(i).take(10).toList());
        }

        for (final chunk in classChunks) {
          final snapshot = await FirebaseFirestore.instance
              .collection('students')
              .where('institutionId', isEqualTo: widget.institutionId)
              .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
              .where('classId', whereIn: chunk)
              .get();
          
          students.addAll(snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }));
        }
        
        // Remove duplicates if any (due to overlapping assignments, though unlikely for student-class)
        final seenIds = <String>{};
        students.retainWhere((s) => seenIds.add(s['id']));
      } else {
        // Admin mode: Load all students
        var query = FirebaseFirestore.instance
            .collection('students')
            .where('institutionId', isEqualTo: widget.institutionId);
            
        if (!widget.showAllSchoolTypes) {
          query = query.where('schoolTypeId', isEqualTo: widget.schoolTypeId);
        }
        
        final snapshot = await query.orderBy('name').get();

        students = snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
      }

      // Final sort by name since chunks might mess up order
      students.sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));

      if (mounted) {
        setState(() {
          _allStudents = students;
          _extractFilterData();
          _filterStudents();
          if (widget.initialStudentId != null) {
            try {
              _selectedStudent = _allStudents.firstWhere((s) => s['id'] == widget.initialStudentId);
            } catch (silentError) { debugPrint('[portfolio_screen] hata yutuldu: $silentError'); }
          }
          _isLoading = false;
        });
        // Seçili öğrenciye scroll yap
        if (widget.initialStudentId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToSelectedStudent();
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading students: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Öğrenci listesi yüklenirken hata oluştu: $e'),
          ),
        );
      }
    }
  }

  void _extractFilterData() {
    // Öğrencilerden mevcut şube adlarını çıkar (501, 708, 12-A vb.)
    final classes = _allStudents
        .map((s) => (s['className'] ?? '').toString().trim())
        .where((c) => c.isNotEmpty && c.toLowerCase() != 'null')
        .toSet()
        .toList();
    classes.sort((a, b) {
      final ia = int.tryParse(a);
      final ib = int.tryParse(b);
      if (ia != null && ib != null) return ia.compareTo(ib);
      final ka = int.tryParse(_extractLevelKey(a) ?? '');
      final kb = int.tryParse(_extractLevelKey(b) ?? '');
      if (ka != null && kb != null && ka != kb) return ka.compareTo(kb);
      return a.compareTo(b);
    });

    // Hem schoolType.activeGrades hem de öğrencilerden (classLevel veya className üzerinden) sınıf seviyelerini çıkar
    final Set<String> levelKeys = {};
    for (final g in _schoolTypeGrades) {
      final k = _extractLevelKey(g);
      if (k != null && k.isNotEmpty) levelKeys.add(k);
    }
    for (final s in _allStudents) {
      final k = _getStudentLevelKey(s);
      if (k != null && k.isNotEmpty) levelKeys.add(k);
    }

    final sortedKeys = levelKeys.toList()
      ..sort((a, b) {
        final ia = int.tryParse(a);
        final ib = int.tryParse(b);
        if (ia != null && ib != null) return ia.compareTo(ib);
        if (ia != null) return -1;
        if (ib != null) return 1;
        return a.compareTo(b);
      });

    final formattedLevels = sortedKeys.map(_formatLevelLabel).toList();

    setState(() {
      _classes = classes;
      _classLevels = formattedLevels;
      if (_filterClassLevel != null && !_classLevels.contains(_filterClassLevel)) {
        final key = _extractLevelKey(_filterClassLevel);
        final match = key != null ? _formatLevelLabel(key) : null;
        _filterClassLevel = (match != null && _classLevels.contains(match)) ? match : null;
      }
      if (_filterClass != null && !_filteredClassesForSelectedLevel.contains(_filterClass)) {
        _filterClass = null;
      }
    });
  }

  void _scrollToSelectedStudent() {
    if (_selectedStudent == null) return;
    final index = _filteredStudents.indexWhere((s) => s['id'] == _selectedStudent!['id']);
    if (index < 0) return;

    // itemExtent ile sabit yükseklik: her öğrenci kartı tam 80px
    // Liste padding'i (top: 8px) + index * itemExtent = kesin piksel pozisyon
    const double itemExtent = 80.0;
    const double listPaddingTop = 8.0;
    final targetOffset = listPaddingTop + index * itemExtent;

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_studentListScrollController.hasClients) {
        _studentListScrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _filterStudents() {
    final query = _searchController.text.trim().toLowerCase();
    final targetLevelKey = _extractLevelKey(_filterClassLevel);

    setState(() {
      _filteredStudents = _allStudents.where((s) {
        // Status Filter
        final isActive = s['isActive'] ?? true;
        if (_statusFilter == 'active' && !isActive) return false;
        if (_statusFilter == 'inactive' && isActive) return false;

        // Class Level Filter
        if (targetLevelKey != null) {
          final studentLevelKey = _getStudentLevelKey(s);
          if (studentLevelKey != targetLevelKey) return false;
        }

        // Class (Branch) Filter
        if (_filterClass != null) {
          if ((s['className'] ?? '').toString().trim() != _filterClass!.trim()) return false;
        }

        // Search Filter
        if (query.isNotEmpty) {
          final fullName = (s['fullName'] ?? s['name'] ?? '').toString().toLowerCase();
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
                          filteredStudents: _filteredStudents,
                          activeTermId: _activeTermId,
                          schoolSettings: _schoolSettings,
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
                  value: _classLevels.contains(_filterClassLevel) ? _filterClassLevel : null,
                  items: _classLevels,
                  onChanged: (val) => setState(() {
                    _filterClassLevel = val;
                    if (val == null) {
                      _filterClass = null;
                    } else if (_filterClass != null &&
                        _getClassLevelKey(_filterClass!) != _extractLevelKey(val)) {
                      _filterClass = null;
                    }
                    _filterStudents();
                  }),
                  allLabel: 'Tüm Seviyeler',
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _buildDropdown(
                  hint: 'Sınıf',
                  value: _filteredClassesForSelectedLevel.contains(_filterClass)
                      ? _filterClass
                      : null,
                  items: _filteredClassesForSelectedLevel,
                  onChanged: (val) => setState(() {
                    _filterClass = val;
                    if (val != null) {
                      final levelKey = _getClassLevelKey(val);
                      if (levelKey != null) {
                        final formatted = _formatLevelLabel(levelKey);
                        if (_classLevels.contains(formatted)) {
                          _filterClassLevel = formatted;
                        }
                      }
                    }
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
      controller: _studentListScrollController,
      itemExtent: 80.0, // Sabit yükseklik: scroll hesabı her index için kesin çalışır
      padding: EdgeInsets.all(8),
      itemCount: _filteredStudents.length,
      itemBuilder: (context, index) {
        final student = _filteredStudents[index];
        bool isSelected =
            _selectedStudent != null &&
            _selectedStudent!['id'] == student['id'];

        return Card(
          key: isSelected ? _selectedStudentCardKey : null,
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
                      filteredStudents: _filteredStudents,
                      activeTermId: _activeTermId,
                      schoolSettings: _schoolSettings,
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
  
  // Reporting Context
  final List<Map<String, dynamic>> filteredStudents;
  final String? activeTermId;
  final Map<String, dynamic> schoolSettings;

  const PortfolioDetailView({
    Key? key,
    required this.student,
    required this.institutionId,
    this.onClose,
    required this.filteredStudents,
    this.activeTermId,
    required this.schoolSettings,
    this.initialTab = 0,
  }) : super(key: key);

  final int initialTab;

  @override
  _PortfolioDetailViewState createState() => _PortfolioDetailViewState();
}

class _PortfolioTabConfig {
  final String key;
  final String title;
  final Widget Function() builder;

  const _PortfolioTabConfig(this.key, this.title, this.builder);
}

class _PortfolioDetailViewState extends State<PortfolioDetailView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final List<_PortfolioTabConfig> _allTabs;
  late List<_PortfolioTabConfig> _activeTabs;

  // Trial Exam State
  String? _selectedExamType;
  Set<String> _availableExamTypes = {};
  String _selectedGraphSubject = 'Tümü';
  String? _expandedExamId;
  String? _selectedTopicExamId;
  Set<String> _selectedTopicExamIds = {};
  String _selectedTopicSubjectFilter = 'Tümü';
  Set<String> _availableSubjects = {'Tümü'};
  String _graphMetric = 'score'; // Default to score ('net' or 'score')
  String _selectedLgsYear = '2026'; // Default to latest LGS year
  String _selectedWrittenSubject = 'Tümü';
  String _selectedHomeworkSubject = 'Tümü';
  int? _touchedIndex;
  String _selectedAttendanceLesson = 'Tümü';
  String _selectedInterviewTitle = 'Tümü';
  BookType _activeBookTabFilter = BookType.questionBank;
  String _selectedEtutSubject = 'Tümü';

  // Store full ExamType objects (examTypeId -> ExamType)
  Map<String, ExamType> _examTypesMap = {};
  StreamSubscription? _examTypesSubscription;
  CourseTrackResolver _courseTracks = CourseTrackResolver.empty;

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
    CourseTrackResolver.load(
      institutionId: widget.institutionId,
      schoolTypeId: (widget.student['schoolTypeId'] ?? '').toString(),
    ).then((tracks) {
      if (mounted) {
        setState(() {
          _courseTracks = tracks;
        });
      }
    });
    _allTabs = [
      _PortfolioTabConfig('portfolyo_genel_bilgiler', 'Genel Bilgiler', _buildGeneralInfoTab),
      _PortfolioTabConfig('portfolyo_deneme_sinavlari', 'Deneme Sınavları', _buildTrialExamsTab),
      _PortfolioTabConfig('portfolyo_yazili_sinavlar', 'Yazılı Sınavlar', _buildWrittenExamsTab),
      _PortfolioTabConfig('portfolyo_odevler', 'Ödevler', _buildHomeworksTab),
      _PortfolioTabConfig('portfolyo_devamsizlik', 'Devamsızlık', _buildAttendanceTab),
      _PortfolioTabConfig('portfolyo_eylem_planlari', 'Eylem Planları', _buildEylemPlanlariTab),
      _PortfolioTabConfig('portfolyo_etutler', 'Etütler', _buildEtutlerTab),
      _PortfolioTabConfig('portfolyo_kitaplar', 'Kitaplar', _buildBooksTab),
      _PortfolioTabConfig('portfolyo_gorusmeler', 'Görüşmeler', _buildInterviewsTab),
      _PortfolioTabConfig('portfolyo_talepler', 'Talepler', _buildDemandsTab),
      _PortfolioTabConfig('portfolyo_gelisim_raporu', 'Gelişim Raporu', _buildDevelopmentReportTab),
      _PortfolioTabConfig('portfolyo_mentor_calismalari', 'Mentör Çalışmaları', _buildStudyProgramsTab),
      _PortfolioTabConfig('portfolyo_rehberlik_testleri', 'Rehberlik Testleri', _buildGuidanceTestsTab),
      _PortfolioTabConfig('portfolyo_etkinlik_raporlari', 'Etkinlik Raporları', _buildActivityReportsTab),
    ];

    _activeTabs = _allTabs.where((t) => UserPermissionService.hasTeacherModuleAccess('rehberlik_islemleri', subModuleKey: t.key)).toList();
    if (_activeTabs.isEmpty) {
      _activeTabs = _allTabs;
    }

    int initialIdx = 0;
    if (widget.initialTab >= 0 && widget.initialTab < _allTabs.length) {
      final targetKey = _allTabs[widget.initialTab].key;
      final foundIdx = _activeTabs.indexWhere((t) => t.key == targetKey);
      if (foundIdx != -1) initialIdx = foundIdx;
    }

    _tabController = TabController(length: _activeTabs.length, vsync: this, initialIndex: initialIdx.clamp(0, _activeTabs.length - 1));

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
    _trialExamsStream = AssessmentService().getTrialExams(widget.institutionId, termId: widget.activeTermId);

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
        .where('studentIds', arrayContains: sid)
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

  // ─── İstatistik yardımcı metodları ─────────────────────────────────────────

  String get _studentId => widget.student['id']?.toString() ?? '';
  String get _studentClassId => widget.student['classId']?.toString() ?? '';
  String get _studentClassLevel => widget.student['classLevel']?.toString() ?? '';
  String get _studentFullName =>
      widget.student['fullName']?.toString().isNotEmpty == true
          ? widget.student['fullName'].toString()
          : '${widget.student['name'] ?? ''} ${widget.student['surname'] ?? ''}'.trim();
  String get _studentSchoolNumber =>
      (widget.student['schoolNumber'] ??
          widget.student['studentNumber'] ??
          widget.student['no'] ??
          '').toString().trim();

  Widget _buildStatsButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: color),
        label: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          backgroundColor: color.withValues(alpha: 0.05),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  void _openHomeworkStats() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => StudentHomeworkStatsScreen(
        institutionId: widget.institutionId,
        studentId: _studentId,
        classId: _studentClassId,
      ),
    ));
  }

  void _openAttendanceStats() {
    if (_studentClassId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sınıf bilgisi bulunamadı.')));
      return;
    }
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => StudentAttendanceStatsScreen(
        institutionId: widget.institutionId,
        studentId: _studentId,
        classId: _studentClassId,
        studentName: _studentFullName,
      ),
    ));
  }

  void _openEtutStats() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => StudentEtutStatsScreen(
        institutionId: widget.institutionId,
        studentId: _studentId,
      ),
    ));
  }

  void _openExamStats({int initialTab = 0}) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => StudentExamStatsScreen(
        institutionId: widget.institutionId,
        studentId: _studentId,
        classId: _studentClassId,
        classLevel: _studentClassLevel,
        studentName: _studentFullName,
        schoolNumber: _studentSchoolNumber,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: EduknAppBar(
        title: widget.student['fullName'] ?? 'Öğrenci Detayı',
        actions: [
          IconButton(
            icon: const Icon(Icons.print_rounded, color: Colors.indigo),
            tooltip: 'Rapor Yazdır',
            onPressed: () {
              final isMobile = MediaQuery.of(context).size.width < 700;
              if (isMobile) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PortfolioReportDialog(
                      isPage: true,
                      filteredStudents: widget.filteredStudents,
                      selectedStudent: widget.student,
                      institutionId: widget.institutionId,
                      termId: widget.activeTermId ?? '',
                      schoolSettings: widget.schoolSettings,
                    ),
                  ),
                );
              } else {
                showDialog(
                  context: context,
                  builder: (context) => PortfolioReportDialog(
                    filteredStudents: widget.filteredStudents,
                    selectedStudent: widget.student,
                    institutionId: widget.institutionId,
                    termId: widget.activeTermId ?? '',
                    schoolSettings: widget.schoolSettings,
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline_rounded, color: Colors.indigo),
            tooltip: 'Nasıl Kullanılır?',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const PortfolioGuidePage()),
              );
            },
          ),
          if (widget.onClose != null && MediaQuery.of(context).size.width > 900)
            IconButton(
              icon: Icon(Icons.close, color: Colors.grey),
              onPressed: widget.onClose,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.indigo,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: Colors.indigo,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: _activeTabs.map((t) => Tab(text: t.title)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _activeTabs.map((t) => t.builder()).toList(),
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
                  color: Colors.indigo.withValues(alpha: 0.3),
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

        debugPrint(
          "DEBUG REPORT CARD: StudentID: $studentId, Match Found: ${match != null}",
        );
        if (match == null) {
          debugPrint(
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

          List<String>? definedOrder;
          final etId = res['examTypeId'];
          if (etId != null && _examTypesMap.containsKey(etId)) {
            definedOrder = _examTypesMap[etId]!
                .subjects
                .map((s) => s.branchName)
                .toList();
          }
          final sortedSubjects = ExamReportCardService.sortSubjectsList(
            resultObj.subjects.keys.toList(),
            definedOrder: definedOrder,
          );

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StudentReportCardDialog(
                student: resultObj,
                examName: res['examName'],
                subjects: sortedSubjects,
                outcomes: dummyExam.outcomes,
                totalStudents: 0,
                isRankingVisible: res['isRankingVisible'] != false,
                trialExamId: res['examId'],
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
      debugPrint("Error showing report card: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Hata: $e")));
    }
  }

  // Actual implementation will serve the dialog.
  // We'll implement the UI parts first.

  Widget _buildSummaryStats(List<Map<String, dynamic>> results) {
    if (results.isEmpty) return SizedBox.shrink();

    double totalScore = 0;
    double totalNet = 0;

    for (var r in results) {
      totalScore += (r['score'] as num).toDouble();
      
      if (_selectedGraphSubject == 'Tümü') {
        totalNet += (r['net'] as num).toDouble();
      } else {
        final subMap = r['subjects'];
        if (subMap is Map && subMap.containsKey(_selectedGraphSubject)) {
          final subData = subMap[_selectedGraphSubject];
          if (subData is Map) {
            totalNet += (subData['net'] ?? 0).toDouble();
          } else if (subData is num) {
            totalNet += subData.toDouble();
          }
        }
      }
    }

    double avgScore = totalScore / results.length;
    double avgNet = totalNet / results.length;

    bool isLgs = _selectedExamType != null &&
        _selectedExamType!.toUpperCase().contains('LGS');
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
                  color: Colors.purple.withValues(alpha: 0.05),
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
                              "LGS'de yüzdelik dilimler sadece puana değil, o yıl sınava giren öğrenci sayısına ve standart sapmaya da bağlıdır. Bu veriler MEB 2024, 2025 ve 2026 LGS yerleştirme istatistiklerine dayalı 'genel ortalamaları' yansıtır.\n\nSistem, öğrenciye bu sonuçları gösterirken her zaman 'Tahmini Referans Değerleridir' ibaresini baz alır.",
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
                    children: ['2024', '2025', '2026'].map((y) {
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

  String _normOutcomeText(String input) {
    return input
        .trim()
        .toLowerCase()
        .replaceAll('i̇', 'i')
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _canonicalTopicSubject(String rawSubject) {
    final clean = rawSubject.trim();
    if (clean.isEmpty) return 'Genel';
    final n = _normOutcomeText(clean);

    if (n.contains('edebiyat') || n.contains('turk dili')) {
      return 'Türk Dili ve Edebiyatı';
    }
    if (n.contains('turkce') || n == 'trk' || n == 'tur') {
      return 'Türkçe';
    }
    if (n.contains('geometri')) {
      return 'Geometri';
    }
    if (n.contains('matematik') || n == 'mat' || n == 'mtm') {
      return 'Matematik';
    }
    if (n.contains('fen') || n == 'fb') {
      return 'Fen Bilimleri';
    }
    if (n.contains('inkilap')) {
      return 'T.C. İnkılap Tarihi ve Atatürkçülük';
    }
    if (n.contains('sosyal') || n == 'sb' || n == 'sos') {
      return 'Sosyal Bilgiler';
    }
    if (n.contains('din') || n.contains('dkab') || n.contains('ahlak')) {
      return 'Din Kültürü ve Ahlak Bilgisi';
    }
    if (n.contains('ingilizce') ||
        n.contains('english') ||
        n.contains('yabanci dil') ||
        n.contains('main course') ||
        n == 'ing') {
      return 'İngilizce';
    }
    if (n.contains('fizik')) return 'Fizik';
    if (n.contains('kimya')) return 'Kimya';
    if (n.contains('biyoloji')) return 'Biyoloji';
    if (n.contains('tarih')) return 'Tarih';
    if (n.contains('cografya')) return 'Coğrafya';
    if (n.contains('felsefe')) return 'Felsefe';

    return clean;
  }

  ({String code, String normBody, String display}) _parseOutcomeIdentity(String rawTopic) {
    var trimmed = rawTopic.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) {
      return (code: '', normBody: 'genel', display: 'Genel');
    }

    // MEB kazanım kodu: örn. "M.7.1.1.1.", "T.7.3.5 -", "F.8.4.1.2:", "SB.7.1.2", "E7.1.R1"
    final codeRegex = RegExp(
      r'^([A-ZÇĞİÖŞÜa-zçğıöşü]{1,5}\s*\.\s*\d+(?:\s*\.\s*[A-Za-z0-9]+){1,5})\s*[-:.)\s]*\s*(.*)$',
    );
    final match = codeRegex.firstMatch(trimmed);
    String code = '';
    String body = trimmed;

    if (match != null) {
      code = match.group(1)!.replaceAll(RegExp(r'\s+'), '').toUpperCase();
      final rest = match.group(2)!.trim();
      if (rest.isNotEmpty) {
        body = rest;
      }
    }

    final normBody = _normOutcomeText(body);
    return (
      code: code,
      normBody: normBody.isNotEmpty ? normBody : _normOutcomeText(trimmed),
      display: trimmed,
    );
  }

  Map<String, Map<String, Map<String, double>>> _calculateTopicStatsForResults(
    List<Map<String, dynamic>> results,
  ) {
    Map<String, Map<String, Map<String, double>>> allSubjectStats = {};
    // subject -> { displayTopic -> {code, normBody, examIds} }
    final Map<String, Map<String, ({String code, String normBody, Set<String> examIds})>>
        subjectTopicMeta = {};

    for (int rIdx = 0; rIdx < results.length; rIdx++) {
      final res = results[rIdx];
      final examId = (res['examId'] ?? res['id'] ?? 'exam_$rIdx').toString();
      final outcomes = res['examOutcomes'];
      if (outcomes is! Map || outcomes.isEmpty) continue;

      final studentAnswers = (res['studentAnswers'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          ) ??
          {};
      final correctAnswers = (res['correctAnswers'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          ) ??
          {};
      final answerKeys =
          res['examAnswerKeys'] is Map ? (res['examAnswerKeys'] as Map) : null;

      if (studentAnswers.isEmpty && correctAnswers.isEmpty) continue;

      String lookupBooklet = (res['booklet'] ?? 'A').toString().trim();
      if (!outcomes.containsKey(lookupBooklet)) {
        if (lookupBooklet.length > 1 &&
            outcomes.containsKey(lookupBooklet[0])) {
          lookupBooklet = lookupBooklet[0];
        }
      }
      if (!outcomes.containsKey(lookupBooklet)) {
        lookupBooklet = outcomes.containsKey('A')
            ? 'A'
            : (outcomes.isNotEmpty ? outcomes.keys.first.toString() : '');
      }

      var outcomesMap = outcomes[lookupBooklet] is Map
          ? (outcomes[lookupBooklet] as Map)
          : null;
      if (outcomesMap == null || outcomesMap.isEmpty) continue;

      // Fallback answerKeys if correctAnswers map is missing
      Map? fallbackAnswerKeys;
      if (answerKeys != null) {
        if (answerKeys.containsKey(lookupBooklet) &&
            answerKeys[lookupBooklet] is Map) {
          fallbackAnswerKeys = answerKeys[lookupBooklet] as Map;
        } else if (answerKeys.containsKey('A') && answerKeys['A'] is Map) {
          fallbackAnswerKeys = answerKeys['A'] as Map;
        } else if (answerKeys.isNotEmpty && answerKeys.values.first is Map) {
          fallbackAnswerKeys = answerKeys.values.first as Map;
        }
      }

      String _findInMap(Map map, String key) {
        if (map.containsKey(key)) return map[key]?.toString() ?? '';
        final lowerKey = key.trim().toLowerCase();
        for (var k in map.keys) {
          if (k.toString().trim().toLowerCase() == lowerKey) {
            return map[k]?.toString() ?? '';
          }
        }
        final canonTarget = _canonicalTopicSubject(key);
        for (var k in map.keys) {
          if (_canonicalTopicSubject(k.toString()) == canonTarget) {
            return map[k]?.toString() ?? '';
          }
        }
        for (var k in map.keys) {
          final kStr = k.toString().trim().toLowerCase();
          if (kStr.contains(lowerKey) || lowerKey.contains(kStr)) {
            return map[k]?.toString() ?? '';
          }
        }
        return '';
      }

      outcomesMap.forEach((subjectKey, outcomeList) {
        if (outcomeList is! List || outcomeList.isEmpty) return;
        final rawSubject = subjectKey.toString().trim();
        final subject = _canonicalTopicSubject(rawSubject);

        final studentAns = _findInMap(studentAnswers, rawSubject);
        String correctAns = _findInMap(correctAnswers, rawSubject);
        if (correctAns.isEmpty && fallbackAnswerKeys != null) {
          correctAns = _findInMap(fallbackAnswerKeys, rawSubject);
        }

        if (correctAns.isEmpty && studentAns.isEmpty) return;

        allSubjectStats.putIfAbsent(subject, () => {});
        subjectTopicMeta.putIfAbsent(subject, () => {});

        int len = correctAns.length;
        if (outcomeList.length < len) len = outcomeList.length;

        for (int i = 0; i < len; i++) {
          String rawTopic = outcomeList[i]?.toString().trim() ?? '';
          if (rawTopic.isEmpty) rawTopic = 'Genel';

          final parsed = _parseOutcomeIdentity(rawTopic);
          final metaMap = subjectTopicMeta[subject]!;
          final statsMap = allSubjectStats[subject]!;

          // Mevcut kazanımlar arasında aynı kazanım kodu veya aynı normalize metin var mı kontrol et
          String? matchedDisplayKey;
          for (final entry in metaMap.entries) {
            final existing = entry.value;
            final sameBody = parsed.normBody.isNotEmpty &&
                existing.normBody == parsed.normBody;
            final sameCode = parsed.code.isNotEmpty &&
                existing.code.isNotEmpty &&
                existing.code == parsed.code;
            if (sameBody || sameCode) {
              matchedDisplayKey = entry.key;
              break;
            }
          }

          String activeKey;
          if (matchedDisplayKey != null) {
            activeKey = matchedDisplayKey;
            final oldMeta = metaMap[activeKey]!;
            // Eğer yeni gelen kazanımda MEB kodu da varsa ve eskisinde yoksa başlığı zenginleştir
            if (oldMeta.code.isEmpty &&
                parsed.code.isNotEmpty &&
                parsed.display.length > activeKey.length) {
              final existingStats = statsMap.remove(activeKey)!;
              metaMap.remove(activeKey);
              activeKey = parsed.display;
              statsMap[activeKey] = existingStats;
              metaMap[activeKey] = (
                code: parsed.code,
                normBody: oldMeta.normBody,
                examIds: oldMeta.examIds..add(examId),
              );
            } else {
              oldMeta.examIds.add(examId);
            }
          } else {
            activeKey = parsed.display;
            statsMap[activeKey] = {
              'correct': 0,
              'wrong': 0,
              'empty': 0,
              'examCount': 1,
            };
            metaMap[activeKey] = (
              code: parsed.code,
              normBody: parsed.normBody,
              examIds: {examId},
            );
          }

          statsMap[activeKey]!['examCount'] =
              metaMap[activeKey]!.examIds.length.toDouble();

          final c = correctAns[i];
          final s = (i < studentAns.length) ? studentAns[i] : ' ';

          final status = TrialExam.evaluateAnswer(s, c);
          if (status == AnswerStatus.correct) {
            statsMap[activeKey]!['correct'] =
                statsMap[activeKey]!['correct']! + 1;
          } else if (status == AnswerStatus.empty) {
            statsMap[activeKey]!['empty'] =
                statsMap[activeKey]!['empty']! + 1;
          } else {
            statsMap[activeKey]!['wrong'] =
                statsMap[activeKey]!['wrong']! + 1;
          }
        }
      });
    }

    return allSubjectStats;
  }

  int _topicSubjectOrderIndex(String subject) {
    final s = subject
        .trim()
        .toLowerCase()
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı');
    // 1. Türkçe
    if (s.contains('türkçe') ||
        s.contains('turkce') ||
        s.contains('edebiyat') ||
        s.contains('türk dili')) {
      return 10;
    }
    // 2. Sosyal Bilgiler / T.C. İnkılap Tarihi ve Atatürkçülük
    if (s.contains('sosyal') ||
        s.contains('inkılap') ||
        s.contains('inkilap') ||
        s.contains('tarih') ||
        s.contains('coğrafya') ||
        s.contains('cografya') ||
        s.contains('felsefe')) {
      return 20;
    }
    // 3. Din Kültürü ve Ahlak Bilgisi
    if (s.contains('din')) {
      return 30;
    }
    // 4. İngilizce / Yabancı Dil
    if (s.contains('ingilizce') ||
        s.contains('yabancı') ||
        s.contains('yabanci') ||
        s.contains('almanca') ||
        s.contains('fransızca')) {
      return 40;
    }
    // 5. Matematik
    if (s.contains('matematik') || s.contains('geometri')) {
      return 50;
    }
    // 6. Fen Bilimleri
    if (s.contains('fen') ||
        s.contains('fizik') ||
        s.contains('kimya') ||
        s.contains('biyoloji')) {
      return 60;
    }
    return 999;
  }

  List<Map<String, dynamic>> _sortExamResultsNewestFirst(
    List<Map<String, dynamic>> pool,
  ) {
    final copy = List<Map<String, dynamic>>.from(pool);
    copy.sort((a, b) {
      final da = a['date'] is DateTime
          ? (a['date'] as DateTime)
          : DateTime.fromMillisecondsSinceEpoch(0);
      final db = b['date'] is DateTime
          ? (b['date'] as DateTime)
          : DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });
    return copy;
  }

  Future<void> _showTopicExamSelectorDialog(
    List<Map<String, dynamic>> allResultsPool,
    List<Map<String, dynamic>> currentTypeResults,
  ) async {
    final newestFirstPool = _sortExamResultsNewestFirst(allResultsPool);
    final allIds = newestFirstPool
        .map((r) => (r['examId'] ?? r['id']).toString())
        .toSet();

    Set<String> tempSelected;
    String activePreset = _selectedTopicExamId ?? 'ALL';
    if (activePreset == 'ALL') {
      tempSelected = Set<String>.from(allIds);
    } else if (activePreset == 'LAST_1') {
      tempSelected = newestFirstPool
          .take(1)
          .map((r) => (r['examId'] ?? r['id']).toString())
          .toSet();
    } else if (activePreset == 'LAST_3') {
      tempSelected = newestFirstPool
          .take(3)
          .map((r) => (r['examId'] ?? r['id']).toString())
          .toSet();
    } else if (activePreset == 'LAST_5') {
      tempSelected = newestFirstPool
          .take(5)
          .map((r) => (r['examId'] ?? r['id']).toString())
          .toSet();
    } else if (activePreset == 'LAST_10') {
      tempSelected = newestFirstPool
          .take(10)
          .map((r) => (r['examId'] ?? r['id']).toString())
          .toSet();
    } else if (activePreset == 'CURRENT_TYPE') {
      tempSelected = currentTypeResults
          .map((r) => (r['examId'] ?? r['id']).toString())
          .toSet();
    } else if (activePreset == 'CUSTOM' && _selectedTopicExamIds.isNotEmpty) {
      tempSelected = Set<String>.from(_selectedTopicExamIds)..retainAll(allIds);
    } else {
      tempSelected = {activePreset}..retainAll(allIds);
    }
    if (tempSelected.isEmpty) {
      tempSelected = Set<String>.from(allIds);
    }

    String searchQuery = '';
    String selectedTypeTab = 'Tümü';
    final examTypes = <String>{
      'Tümü',
      ...newestFirstPool
          .map((r) => (r['typeName'] ?? '').toString().trim())
          .where((t) => t.isNotEmpty),
    }.toList();

    final quickPresets = <Map<String, dynamic>>[
      {
        'id': 'ALL',
        'label': 'Tüm Sınavlar',
        'icon': Icons.all_inclusive_rounded,
      },
      {
        'id': 'LAST_1',
        'label': 'Son Sınav',
        'icon': Icons.looks_one_outlined,
      },
      {
        'id': 'LAST_3',
        'label': 'Son 3 Sınav',
        'icon': Icons.looks_3_outlined,
      },
      {
        'id': 'LAST_5',
        'label': 'Son 5 Sınav',
        'icon': Icons.looks_5_outlined,
      },
      {
        'id': 'LAST_10',
        'label': 'Son 10 Sınav',
        'icon': Icons.filter_9_plus_outlined,
      },
    ];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final filteredList = newestFirstPool.where((r) {
              final eName = (r['examName'] ?? '').toString().toLowerCase();
              final eType = (r['typeName'] ?? '').toString().trim();
              if (selectedTypeTab != 'Tümü' && eType != selectedTypeTab) {
                return false;
              }
              if (searchQuery.isNotEmpty) {
                final q = searchQuery.toLowerCase();
                return eName.contains(q) || eType.toLowerCase().contains(q);
              }
              return true;
            }).toList();

            final screenHeight = MediaQuery.of(ctx).size.height;
            final isMobileSheet = MediaQuery.of(ctx).size.width < 600;

            return Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 720,
                  maxHeight: screenHeight * 0.85,
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  padding: EdgeInsets.only(
                    left: isMobileSheet ? 16 : 24,
                    right: isMobileSheet ? 16 : 24,
                    top: 12,
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Üst tutamaç çizgisi (Bottom Sheet handle)
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.layers_rounded,
                              color: Colors.indigo.shade700,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Kazanım Analizi Sınav Seçimi',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                Text(
                                  'Hızlı seçim yapabilir veya istediğiniz sınavları işaretleyerek ortak kazanımları birleştirebilirsiniz.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Hızlı Seçim (Son Sınav, Son 3 Sınav, Son 5 Sınav, Son 10 Sınav, Tüm Sınavlar)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.indigo.shade100),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.bolt_rounded,
                                  size: 16,
                                  color: Colors.indigo.shade700,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Hızlı Seçim',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo.shade900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ScrollConfiguration(
                              behavior: ScrollConfiguration.of(ctx).copyWith(
                                dragDevices: {
                                  PointerDeviceKind.touch,
                                  PointerDeviceKind.mouse,
                                  PointerDeviceKind.trackpad,
                                },
                              ),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(
                                  parent: AlwaysScrollableScrollPhysics(),
                                ),
                                child: Row(
                                  children: quickPresets.map((preset) {
                                    final pId = preset['id'] as String;
                                    final pLabel = preset['label'] as String;
                                    final pIcon = preset['icon'] as IconData;
                                    final isSelectedPreset =
                                        activePreset == pId;

                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () {
                                          Set<String> newIds;
                                          if (pId == 'ALL') {
                                            newIds = Set<String>.from(allIds);
                                          } else {
                                            final count = int.tryParse(
                                                  pId.replaceFirst('LAST_', ''),
                                                ) ??
                                                1;
                                            newIds = newestFirstPool
                                                .take(count)
                                                .map(
                                                  (r) => (r['examId'] ?? r['id'])
                                                      .toString(),
                                                )
                                                .toSet();
                                          }
                                          setState(() {
                                            _selectedTopicExamIds = newIds;
                                            _selectedTopicExamId = pId;
                                          });
                                          Navigator.pop(ctx);
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 7,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSelectedPreset
                                                ? Colors.indigo.shade600
                                                : Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                              color: isSelectedPreset
                                                  ? Colors.indigo.shade600
                                                  : Colors.indigo.shade200,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                pIcon,
                                                size: 15,
                                                color: isSelectedPreset
                                                    ? Colors.white
                                                    : Colors.indigo.shade700,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                pLabel,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: isSelectedPreset
                                                      ? FontWeight.bold
                                                      : FontWeight.w600,
                                                  color: isSelectedPreset
                                                      ? Colors.white
                                                      : Colors.indigo.shade900,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Arama ve Tümünü Seç / Temizle Satırı
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              onChanged: (v) =>
                                  setSheetState(() => searchQuery = v.trim()),
                              decoration: InputDecoration(
                                hintText: 'Sınav adı veya sınav türü ara...',
                                hintStyle: const TextStyle(fontSize: 13),
                                prefixIcon: const Icon(Icons.search, size: 18),
                                isDense: true,
                                filled: true,
                                fillColor: Colors.grey.shade100,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () {
                              setSheetState(() {
                                activePreset = 'CUSTOM';
                                for (final r in filteredList) {
                                  tempSelected.add(
                                    (r['examId'] ?? r['id']).toString(),
                                  );
                                }
                              });
                            },
                            icon: const Icon(Icons.select_all, size: 16),
                            label: const Text(
                              'Tümünü Seç',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setSheetState(() {
                                activePreset = 'CUSTOM';
                                tempSelected.clear();
                              });
                            },
                            child: Text(
                              'Temizle',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.red.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (examTypes.length > 2) ...[
                        const SizedBox(height: 10),
                        ScrollConfiguration(
                          behavior: ScrollConfiguration.of(ctx).copyWith(
                            dragDevices: {
                              PointerDeviceKind.touch,
                              PointerDeviceKind.mouse,
                              PointerDeviceKind.trackpad,
                            },
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            child: Row(
                              children: examTypes.map((typeLabel) {
                                final isSel = selectedTypeTab == typeLabel;
                                final count = typeLabel == 'Tümü'
                                    ? newestFirstPool.length
                                    : newestFirstPool
                                        .where(
                                          (r) =>
                                              (r['typeName'] ?? '')
                                                  .toString()
                                                  .trim() ==
                                              typeLabel,
                                        )
                                        .length;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text('$typeLabel ($count)'),
                                    selected: isSel,
                                    selectedColor: Colors.indigo.shade100,
                                    labelStyle: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSel
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                      color: isSel
                                          ? Colors.indigo.shade900
                                          : Colors.grey.shade700,
                                    ),
                                    onSelected: (_) {
                                      setSheetState(() {
                                        selectedTypeTab = typeLabel;
                                      });
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                       Flexible(
                        child: filteredList.isEmpty
                            ? Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 32),
                                child: Center(
                                  child: Text(
                                    'Arama kriterine uygun sınav bulunamadı.',
                                    style:
                                        TextStyle(color: Colors.grey.shade500),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: filteredList.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 6),
                                itemBuilder: (ctx, idx) {
                                  final r = filteredList[idx];
                                  final eId =
                                      (r['examId'] ?? r['id']).toString();
                                  final eName = (r['examName'] ?? 'Deneme Sınavı')
                                      .toString();
                                  final eType =
                                      (r['typeName'] ?? '').toString().trim();
                                  final eDate = r['date'] is DateTime
                                      ? DateFormat('dd.MM.yyyy')
                                          .format(r['date'] as DateTime)
                                      : '';
                                  final eNet = (r['net'] as num?)?.toDouble();
                                  final isChecked = tempSelected.contains(eId);

                                  return InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () {
                                      setSheetState(() {
                                        activePreset = 'CUSTOM';
                                        if (isChecked) {
                                          tempSelected.remove(eId);
                                        } else {
                                          tempSelected.add(eId);
                                        }
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isChecked
                                            ? Colors.indigo.shade50
                                                .withValues(alpha: 0.6)
                                            : Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isChecked
                                              ? Colors.indigo.shade300
                                              : Colors.grey.shade200,
                                          width: isChecked ? 1.5 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Checkbox(
                                            value: isChecked,
                                            activeColor: Colors.indigo,
                                            visualDensity:
                                                VisualDensity.compact,
                                            onChanged: (v) {
                                              setSheetState(() {
                                                activePreset = 'CUSTOM';
                                                if (v == true) {
                                                  tempSelected.add(eId);
                                                } else {
                                                  tempSelected.remove(eId);
                                                }
                                              });
                                            },
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  eName,
                                                  style: TextStyle(
                                                    fontSize: 13.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: isChecked
                                                        ? Colors.indigo.shade900
                                                        : Colors.black87,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 4,
                                                  crossAxisAlignment:
                                                      WrapCrossAlignment.center,
                                                  children: [
                                                    if (eType.isNotEmpty)
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 7,
                                                          vertical: 2,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors
                                                              .indigo.shade100
                                                              .withValues(
                                                                  alpha: 0.6),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(6),
                                                        ),
                                                        child: Text(
                                                          eType,
                                                          style: TextStyle(
                                                            fontSize: 10.5,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: Colors
                                                                .indigo.shade800,
                                                          ),
                                                        ),
                                                      ),
                                                    if (eDate.isNotEmpty)
                                                      Text(
                                                        eDate,
                                                        style: TextStyle(
                                                          fontSize: 11.5,
                                                          color: Colors
                                                              .grey.shade600,
                                                        ),
                                                      ),
                                                    if (eNet != null)
                                                      Text(
                                                        '• ${eNet.toStringAsFixed(1)} Net',
                                                        style: TextStyle(
                                                          fontSize: 11.5,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Colors
                                                              .teal.shade700,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          OutlinedButton(
                                            onPressed: () {
                                              setState(() {
                                                _selectedTopicExamIds = {eId};
                                                _selectedTopicExamId = eId;
                                              });
                                              Navigator.pop(ctx);
                                            },
                                            style: OutlinedButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 6,
                                              ),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              side: BorderSide(
                                                color: Colors.indigo.shade200,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                            child: Text(
                                              'Sadece Bu',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.indigo.shade700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${tempSelected.length} / ${newestFirstPool.length} sınav seçildi',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.indigo.shade900,
                            ),
                          ),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('İptal'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: tempSelected.isEmpty
                                    ? null
                                    : () {
                                        setState(() {
                                          if (tempSelected.length ==
                                              allIds.length) {
                                            _selectedTopicExamIds = {};
                                            _selectedTopicExamId = 'ALL';
                                          } else if (tempSelected.length == 1) {
                                            _selectedTopicExamIds =
                                                Set<String>.from(tempSelected);
                                            _selectedTopicExamId =
                                                tempSelected.first;
                                          } else {
                                            _selectedTopicExamIds =
                                                Set<String>.from(tempSelected);
                                            _selectedTopicExamId = 'CUSTOM';
                                          }
                                        });
                                        Navigator.pop(ctx);
                                      },
                                icon: const Icon(Icons.check_rounded, size: 18),
                                label: Text(
                                  tempSelected.length > 1
                                      ? 'Seçilen ${tempSelected.length} Sınavı Birleştir'
                                      : 'Seçili Sınavı Göster',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigo,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
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
          },
        );
      },
    );
  }

  Widget _buildTopicAnalysis(
    List<Map<String, dynamic>> results, {
    List<Map<String, dynamic>>? allStudentResults,
  }) {
    final allResultsPool =
        (allStudentResults != null && allStudentResults.isNotEmpty)
            ? allStudentResults
            : results;
    if (allResultsPool.isEmpty) return SizedBox.shrink();

    final newestFirstPool = _sortExamResultsNewestFirst(allResultsPool);
    final bool hasMultipleExamTypes =
        allResultsPool.length > results.length && _availableExamTypes.length > 1;

    // Geçerli seçimi belirle (varsayılan: tüm sınav türlerini birleştiren 'ALL')
    String effectiveSelection = _selectedTopicExamId ?? 'ALL';

    List<Map<String, dynamic>> targetResults;
    if (effectiveSelection == 'ALL') {
      targetResults = newestFirstPool;
    } else if (effectiveSelection == 'LAST_1') {
      targetResults = newestFirstPool.take(1).toList();
    } else if (effectiveSelection == 'LAST_3') {
      targetResults = newestFirstPool.take(3).toList();
    } else if (effectiveSelection == 'LAST_5') {
      targetResults = newestFirstPool.take(5).toList();
    } else if (effectiveSelection == 'LAST_10') {
      targetResults = newestFirstPool.take(10).toList();
    } else if (effectiveSelection == 'CURRENT_TYPE') {
      targetResults = results;
    } else if (effectiveSelection == 'CUSTOM' &&
        _selectedTopicExamIds.isNotEmpty) {
      targetResults = newestFirstPool
          .where(
            (r) => _selectedTopicExamIds.contains(
              (r['examId'] ?? r['id']).toString(),
            ),
          )
          .toList();
      if (targetResults.isEmpty) {
        targetResults = newestFirstPool;
        effectiveSelection = 'ALL';
        _selectedTopicExamId = 'ALL';
      }
    } else {
      targetResults = newestFirstPool
          .where(
            (r) => (r['examId'] ?? r['id']).toString() == effectiveSelection,
          )
          .toList();
      if (targetResults.isEmpty) {
        targetResults = newestFirstPool;
        effectiveSelection = 'ALL';
        _selectedTopicExamId = 'ALL';
      }
    }

    final allSubjectStats = _calculateTopicStatsForResults(targetResults);

    // Ders filtre çipleri için sınav sırasına göre sıralanmış mevcut ders listesi:
    // 1. Türkçe -> 2. Sosyal Bilgiler -> 3. Din Kültürü -> 4. İngilizce -> 5. Matematik -> 6. Fen Bilimleri
    final sortedSubjectKeys = allSubjectStats.keys.toList()
      ..sort((a, b) {
        final cmp =
            _topicSubjectOrderIndex(a).compareTo(_topicSubjectOrderIndex(b));
        if (cmp != 0) return cmp;
        return a.compareTo(b);
      });
    final availableTopicSubjects = <String>[
      'Tümü',
      ...sortedSubjectKeys,
    ];
    if (!availableTopicSubjects.contains(_selectedTopicSubjectFilter)) {
      _selectedTopicSubjectFilter = 'Tümü';
    }

    // Flatten topics (seçili ders filtresine göre)
    List<Map<String, dynamic>> allTopics = [];
    int mergedMultiExamTopicCount = 0;
    for (final subject in sortedSubjectKeys) {
      final topicsMap = allSubjectStats[subject]!;
      topicsMap.forEach((topic, stats) {
        double corr = stats['correct'] ?? 0;
        double wrng = stats['wrong'] ?? 0;
        double empty = stats['empty'] ?? 0;
        double examCnt = stats['examCount'] ?? 1;
        if (examCnt > 1) mergedMultiExamTopicCount++;
        if (_selectedTopicSubjectFilter != 'Tümü' &&
            subject != _selectedTopicSubjectFilter) {
          return;
        }
        double total = corr + wrng + empty;
        double pct = total > 0 ? (corr / total) * 100 : 0;

        allTopics.add({
          'subject': subject,
          'topic': topic,
          'correct': corr.toInt(),
          'wrong': wrng.toInt(),
          'empty': empty.toInt(),
          'total': total.toInt(),
          'examCount': examCnt.toInt(),
          'success': pct,
        });
      });
    }

    // En Başarılı Konular: Başarı % yüksekten düşüğe (eşitlikte soru sayısı yüksek olan önce)
    final sortedByBest = List<Map<String, dynamic>>.from(allTopics)
      ..sort((a, b) {
        final cmp = (b['success'] as double).compareTo(a['success'] as double);
        if (cmp != 0) return cmp;
        return (b['total'] as int).compareTo(a['total'] as int);
      });
    final topTopics = sortedByBest
        .where((t) => (t['success'] as double) >= 50.0)
        .take(3)
        .toList();
    final topKeys = topTopics
        .map((t) => '${t['subject']}_${t['topic']}')
        .toSet();

    // Geliştirilmesi Gerekenler: Sadece %100'ün altında olanlar (en düşük başarıdan başlayarak)
    final sortedByWorst = allTopics
        .where(
          (t) =>
              (t['success'] as double) < 100.0 &&
              !topKeys.contains('${t['subject']}_${t['topic']}'),
        )
        .toList()
      ..sort((a, b) {
        final cmp = (a['success'] as double).compareTo(b['success'] as double);
        if (cmp != 0) return cmp;
        return (b['wrong'] as int).compareTo(a['wrong'] as int);
      });
    final worstTopics = sortedByWorst.take(3).toList();

    // Seçili durum başlığı ve alt etiketi
    String selectorTitle;
    String? selectorSubtitle;
    if (effectiveSelection == 'ALL') {
      selectorTitle = hasMultipleExamTypes
          ? 'Tüm Sınav Türleri Birleşik'
          : 'Tüm Sınavlar Birleşik';
      selectorSubtitle = '${allResultsPool.length} sınav dahil edildi';
    } else if (effectiveSelection == 'LAST_1') {
      final selExam = targetResults.first;
      selectorTitle = 'Son Sınav';
      selectorSubtitle = (selExam['examName'] ?? 'Deneme Sınavı').toString();
    } else if (effectiveSelection == 'LAST_3') {
      selectorTitle = 'Son 3 Sınav Birleşik';
      selectorSubtitle = '${targetResults.length} sınav dahil edildi';
    } else if (effectiveSelection == 'LAST_5') {
      selectorTitle = 'Son 5 Sınav Birleşik';
      selectorSubtitle = '${targetResults.length} sınav dahil edildi';
    } else if (effectiveSelection == 'LAST_10') {
      selectorTitle = 'Son 10 Sınav Birleşik';
      selectorSubtitle = '${targetResults.length} sınav dahil edildi';
    } else if (effectiveSelection == 'CURRENT_TYPE') {
      selectorTitle = _selectedExamType ?? 'Seçili Sınav Türü';
      selectorSubtitle = '${results.length} sınav dahil edildi';
    } else if (effectiveSelection == 'CUSTOM') {
      selectorTitle = 'Özel Sınav Seçimi';
      selectorSubtitle = '${targetResults.length} sınav birleştirildi';
    } else {
      final selExam = targetResults.first;
      selectorTitle = (selExam['examName'] ?? 'Deneme Sınavı').toString();
      final sType = (selExam['typeName'] ?? '').toString().trim();
      final sDate = selExam['date'] is DateTime
          ? DateFormat('dd.MM.yyyy').format(selExam['date'] as DateTime)
          : '';
      selectorSubtitle = [
        if (sType.isNotEmpty) sType,
        if (sDate.isNotEmpty) sDate,
      ].join(' • ');
    }

    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Üst Başlık ve Sağa Yaslı Sınav Seçici Kart (Mobilde sadece ikon)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Genel Kazanım ve Konu Analizi',
                      style: TextStyle(
                        fontSize: isMobile ? 16 : 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      targetResults.length > 1
                          ? '${targetResults.length} sınavdaki ortak kazanımlar birleştirildi'
                              '${mergedMultiExamTopicCount > 0 ? ' ($mergedMultiExamTopicCount ortak kazanım)' : ''}'
                          : 'Tekil sınav kazanım analizi ($selectorTitle)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (isMobile)
                Tooltip(
                  message: selectorSubtitle != null &&
                          selectorSubtitle.isNotEmpty
                      ? '$selectorTitle ($selectorSubtitle)'
                      : selectorTitle,
                  child: InkWell(
                    onTap: () => _showTopicExamSelectorDialog(
                      allResultsPool,
                      results,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.indigo.shade200),
                      ),
                      child: Icon(
                        effectiveSelection == 'ALL' ||
                                effectiveSelection.startsWith('LAST_') ||
                                effectiveSelection == 'CUSTOM' ||
                                effectiveSelection == 'CURRENT_TYPE'
                            ? Icons.layers_rounded
                            : Icons.description_outlined,
                        color: Colors.indigo.shade700,
                        size: 20,
                      ),
                    ),
                  ),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (effectiveSelection != 'ALL') ...[
                      ActionChip(
                        avatar: Icon(
                          Icons.merge_type_rounded,
                          size: 16,
                          color: Colors.indigo.shade700,
                        ),
                        label: Text(
                          'Tümünü Birleştir (${allResultsPool.length})',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.indigo.shade800,
                          ),
                        ),
                        backgroundColor: Colors.indigo.shade50,
                        side: BorderSide(color: Colors.indigo.shade100),
                        onPressed: () {
                          setState(() {
                            _selectedTopicExamIds = {};
                            _selectedTopicExamId = 'ALL';
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                    InkWell(
                      onTap: () => _showTopicExamSelectorDialog(
                        allResultsPool,
                        results,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 320),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.indigo.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                effectiveSelection == 'ALL' ||
                                        effectiveSelection.startsWith('LAST_') ||
                                        effectiveSelection == 'CUSTOM' ||
                                        effectiveSelection == 'CURRENT_TYPE'
                                    ? Icons.layers_rounded
                                    : Icons.description_outlined,
                                color: Colors.indigo.shade700,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    selectorTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo.shade900,
                                    ),
                                  ),
                                  if (selectorSubtitle != null &&
                                      selectorSubtitle.isNotEmpty)
                                    Text(
                                      selectorSubtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.indigo.shade600,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade700,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Seç',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 2),
                                  Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          // Ders (Branş) Hızlı Filtre Çipleri (Mouse ile sağa-sola kaydırılabilir ve sınav sırasına göre)
          if (availableTopicSubjects.length > 1) ...[
            const SizedBox(height: 14),
            ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                },
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                child: Row(
                  children: availableTopicSubjects.map((subj) {
                    final isSel = _selectedTopicSubjectFilter == subj;
                    final count = subj == 'Tümü'
                        ? allSubjectStats.values
                            .fold<int>(0, (sum, m) => sum + m.length)
                        : (allSubjectStats[subj]?.length ?? 0);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('$subj ($count)'),
                        selected: isSel,
                        selectedColor: Colors.indigo.shade600,
                        backgroundColor: Colors.grey.shade100,
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                          color: isSel ? Colors.white : Colors.grey.shade800,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: isSel
                                ? Colors.indigo.shade600
                                : Colors.grey.shade300,
                          ),
                        ),
                        onSelected: (_) {
                          setState(() {
                            _selectedTopicSubjectFilter = subj;
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
          SizedBox(height: 16),
          if (allSubjectStats.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Bu sınav(lar) için konu analiz verisi bulunamadı.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ),
            )
          else ...[
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
                  List<String>? definedOrder;
                  if (targetResults.isNotEmpty) {
                    final etId = targetResults.first['examTypeId'];
                    if (etId != null && _examTypesMap.containsKey(etId)) {
                      definedOrder = _examTypesMap[etId]!
                          .subjects
                          .map((s) => _canonicalTopicSubject(s.branchName))
                          .toList();
                    }
                  }

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TopicAnalysisDetailScreen(
                        allSubjectStats: allSubjectStats,
                        studentName: widget.student['fullName'] ??
                            widget.student['name'] ??
                            'Öğrenci',
                        definedSubjectOrder: definedOrder,
                        analyzedExamCount: targetResults.length,
                        initialSubject: _selectedTopicSubjectFilter != 'Tümü'
                            ? _selectedTopicSubjectFilter
                            : null,
                      ),
                    ),
                  );
                },
                icon: Icon(Icons.analytics_outlined),
                label: Text('Birleşik Kazanım Analiz Raporunu Gör'),
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
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.05),
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
          Divider(color: accentColor.withValues(alpha: 0.1), height: 24),
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
                                color: scoreColor.withValues(alpha: 0.1),
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            _buildStatsButton(
              label: '📊 Deneme İstatistiklerim',
              icon: Icons.bar_chart_rounded,
              color: const Color(0xFF1E40AF),
              onTap: _openExamStats,
            ),
          ]),
        ),
        Expanded(child: SafeStreamBuilder<List<TrialExam>>(
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

        return GestureDetector(
          onTap: () {
            if (_touchedIndex != null) {
              setState(() => _touchedIndex = null);
            }
          },
          child: SingleChildScrollView(
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
                            color: Colors.black.withValues(alpha: 0.05),
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
                            color: Colors.black.withValues(alpha: 0.05),
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
                            if (val != null) {
                              setState(() {
                                _selectedGraphSubject = val;
                                // Automatically switch to Net mode when a branch is selected
                                if (val != 'Tümü') {
                                  _graphMetric = 'net';
                                }
                              });
                            }
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
                      color: Colors.indigo.withValues(alpha: 0.08),
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
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isMobile = constraints.maxWidth < 600;
                            final List<Map<String, dynamic>> chartData = (isMobile && filteredRes.length > 10) 
                                ? filteredRes.sublist(filteredRes.length - 10) 
                                : filteredRes;

                            return Column(
                              children: [
                                Expanded(
                                  child: Stack(
                                    children: [
                                      LineChart(_getLineChartData(chartData)),
                                      // Fixed Info Bar at the bottom of the chart
                                      if (_touchedIndex != null)
                                        Positioned(
                                          bottom: 30, // Tangent to zero line
                                          left: 30,   // Final alignment to remove the last tiny gap
                                          right: 0,
                                          child: _buildChartDetailBar(chartData, _touchedIndex!),
                                        ),
                                    ],
                                  ),
                                ),
                                if (isMobile && filteredRes.length > 10)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12.0),
                                    child: Column(
                                      children: [
                                        Text(
                                          'Grafikte son 10 sınav verisi listelenmektedir.\nTüm sınav geçmişini incelemek için:',
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.poppins(
                                            fontSize: 10,
                                            color: Colors.grey.shade500,
                                            fontWeight: FontWeight.w500,
                                            height: 1.4,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        TextButton.icon(
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => FullScreenTrialChartPage(
                                                  allResults: filteredRes,
                                                  examType: _selectedExamType ?? '',
                                                  subject: _selectedGraphSubject,
                                                  metric: _graphMetric,
                                                ),
                                              ),
                                            );
                                          },
                                          icon: const Icon(Icons.fullscreen_rounded, size: 18),
                                          label: const Text('Tümünü Gör', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                          style: TextButton.styleFrom(
                                            foregroundColor: Colors.indigo,
                                            padding: EdgeInsets.zero,
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 24),
              _buildSummaryStats(filteredRes),
              SizedBox(height: 24),

              _buildTopicAnalysis(
                filteredRes,
                allStudentResults: studentRes,
              ),
              SizedBox(height: 24),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Sınav Geçmişi",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${widget.student['fullName'] ?? widget.student['name'] ?? 'Öğrenci'} uygulanan toplam ${exams.where((e) => e.isActive && e.isPublished && e.examTypeName == _selectedExamType).length} deneme sınavının ${filteredRes.length}'sine katılım sağlamıştır.",
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Detailed List (Latest First)
              ...filteredRes.reversed.map((res) {
                return Card(
                  margin: EdgeInsets.only(bottom: 16),
                  elevation: 2,
                  shadowColor: Colors.black.withValues(alpha: 0.1),
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
                            (res['score'] as num).toStringAsFixed(0),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.indigo.shade900,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_today_rounded,
                                size: 12,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                DateFormat('dd.MM.yyyy').format(res['date']),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.analytics_rounded,
                                size: 12,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "${(res['net'] as num).toStringAsFixed(2)} Net",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
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
                                debugPrint("Error sorting subjects: $e");
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
                                  Wrap(
                                    spacing: 12,
                                    alignment: WrapAlignment.center,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () => _showReportCard(res),
                                        icon: Icon(Icons.sticky_note_2_outlined),
                                        label: Text("Sınav Karnesini Görüntüle"),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.indigo,
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed: () {
                                          final singleStats =
                                              _calculateTopicStatsForResults([res]);
                                          List<String>? definedOrder;
                                          final etId = res['examTypeId'];
                                          if (etId != null &&
                                              _examTypesMap.containsKey(etId)) {
                                            definedOrder = _examTypesMap[etId]!
                                                .subjects
                                                .map((s) => s.branchName)
                                                .toList();
                                          }
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  TopicAnalysisDetailScreen(
                                                allSubjectStats: singleStats,
                                                studentName:
                                                    widget.student['fullName'] ??
                                                        widget.student['name'] ??
                                                        'Öğrenci',
                                                definedSubjectOrder: definedOrder,
                                              ),
                                            ),
                                          );
                                        },
                                        icon: Icon(Icons.analytics_outlined),
                                        label: Text("Konu Analizini Gör"),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.indigo,
                                        ),
                                      ),
                                    ],
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
        ),
      );
      })),
      ],
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
                final isMobile = MediaQuery.of(context).size.width < 600;
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    isMobile ? "${index + 1}" : DateFormat('dd.MM').format(date),
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
                Colors.indigo.withValues(alpha: 0.3),
                Colors.indigo.withValues(alpha: 0.0),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (touchedSpot) => Colors.transparent, // Invisible
          getTooltipItems: (touchedSpots) => [], // Return empty list instead of null
        ),
        handleBuiltInTouches: true,
        touchCallback: (FlTouchEvent event, LineTouchResponse? touchResponse) {
          if (!event.isInterestedForInteractions ||
              touchResponse == null ||
              touchResponse.lineBarSpots == null ||
              touchResponse.lineBarSpots!.isEmpty) {
            return;
          }
          final spotIndex = touchResponse.lineBarSpots!.first.spotIndex;
          setState(() {
            _touchedIndex = spotIndex;
          });
        },
      ),
    );
  }

  Widget _buildChartDetailBar(List<Map<String, dynamic>> results, int index) {
    if (index < 0 || index >= results.length) return const SizedBox.shrink();
    final exam = results[index];
    final name = exam['examName'] ?? 'Sınav';
    final date = DateFormat('dd.MM.yyyy').format(exam['date']);
    final metric = _graphMetric == 'score' ? 'Puan' : 'Net';
    final val = _graphMetric == 'score' 
        ? (exam['score'] as num).toStringAsFixed(2)
        : (_selectedGraphSubject == 'Tümü' 
            ? (exam['net'] as num).toStringAsFixed(2)
            : (exam['subjects']?[_selectedGraphSubject]?['net'] ?? 0).toStringAsFixed(2));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.indigo.shade900.withValues(alpha: 0.85),
        // Flat strip aligned with the graph base
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              name,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 10, color: Colors.white30),
          const SizedBox(width: 8),
          Text(
            date,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 10, color: Colors.white30),
          const SizedBox(width: 8),
          Text(
            "$val $metric",
            style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11),
          ),
        ],
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

    List<Map<String, dynamic>> results = [];

    for (var exam in exams) {
      if (!exam.isActive || !exam.isPublished || exam.resultsJson == null)
        continue;

      try {
        final List<dynamic> allResults = jsonDecode(exam.resultsJson!);

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
            return rNo == studentNo;
          }, orElse: () => null);
        }

        // 2. Match by Student ID
        match ??= allResults.firstWhere((r) {
            return r['studentId'].toString() == studentId ||
                r['id'].toString() == studentId;
          }, orElse: () => null);

        // 3. Match by Name (Fuzzy)
        match ??= allResults.firstWhere((r) {
            final rName = (r['name'] ?? r['studentName'] ?? '')
                .toString()
                .toLowerCase();
            return rName.contains(studentName);
          }, orElse: () => null);

        if (match != null) {
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
            'id': exam.id,
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
            'isRankingVisible': exam.sharingSettings['isRankingVisible'] ?? true,
            'rank': match['rank'],
            'institutionRank': match['institutionRank'],
            'classRank': match['classRank'],
            'generalRank': match['generalRank'],
            'studentAnswers': match['answers'],
            'correctAnswers': match['correctAnswers'],
            'studentResult': match,
            'examOutcomes': exam.outcomes,
            'examAnswerKeys': exam.answerKeys,
            'resultsJson':
                exam.resultsJson, // Needed for report card re-parsing
            'booklet': match['booklet'] ?? 'A', // Extract booklet
          });
        }
      } catch (e) {
        debugPrint("Error parsing exam ${exam.id}: $e");
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            _buildStatsButton(
              label: '📊 Yazılı Sınav İstatistiklerim',
              icon: Icons.edit_note_rounded,
              color: const Color(0xFF4F46E5),
              onTap: _openExamStats,
            ),
          ]),
        ),
        Expanded(child: SafeStreamBuilder<QuerySnapshot>(
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
    )),
    ],
  );
  }

  // --- 3. ÖDEVLER TAB ---
  Widget _buildHomeworksTab() {
    final studentId = widget.student['id'];
    final classId = widget.student['classId'];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            _buildStatsButton(
              label: '📊 Ödev İstatistiklerim',
              icon: Icons.assignment_rounded,
              color: const Color(0xFF7C3AED),
              onTap: _openHomeworkStats,
            ),
          ]),
        ),
        Expanded(child: SafeStreamBuilder<QuerySnapshot>(
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
    )),
    ],
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            _buildStatsButton(
              label: '📊 Yoklama İstatistiklerim',
              icon: Icons.how_to_reg_rounded,
              color: const Color(0xFF059669),
              onTap: _openAttendanceStats,
            ),
          ]),
        ),
        Expanded(child: SafeStreamBuilder<QuerySnapshot>(
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
                              backgroundColor: statusColor.withValues(alpha: 0.1),
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
                                color: statusColor.withValues(alpha: 0.1),
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
    )),
    ],
  );
  }

  Widget _buildEtutlerTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            _buildStatsButton(
              label: '📊 Etüt İstatistiklerim',
              icon: Icons.menu_book_rounded,
              color: const Color(0xFF7C3AED),
              onTap: _openEtutStats,
            ),
          ]),
        ),
        Expanded(child: SafeStreamBuilder<QuerySnapshot>(
      stream: _etutlerStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint("Etüt Yükleme Hatası: ${snapshot.error}");
          return _buildEmptyState('Etütler yüklenirken hata oluştu: ${snapshot.error}');
        }

        if (snapshot.connectionState == ConnectionState.waiting)
          return Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
          return _buildEmptyState('Planlanmış etüt bulunmuyor.');

        // Firestore composite index gereksinimini aşmak için yerel sıralama yapıyoruz
        final allDocs = List<QueryDocumentSnapshot>.from(snapshot.data!.docs);
        allDocs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aDate = (aData['date'] as Timestamp?)?.toDate();
          final bDate = (bData['date'] as Timestamp?)?.toDate();
          
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return bDate.compareTo(aDate); // date descending
        });

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
                              backgroundColor: statusColor.withValues(alpha: 0.1),
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
                                color: statusColor.withValues(alpha: 0.1),
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
    )),
    ],
  );
  }

  String _normEylem(String s) => s
      .replaceAll('İ', 'i')
      .replaceAll('I', 'i')
      .replaceAll('ı', 'i')
      .toLowerCase()
      .replaceAll('i̇', 'i')
      .replaceAll('ı', 'i')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ş', 's')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  int _eylemSubjectOrder(String subject) {
    final s = _normEylem(subject);
    if (s.contains('turkce')) return 1;
    if (s.contains('sosyal') || s.contains('tarih') || s.contains('inkilap')) return 2;
    if (s.contains('din')) return 3;
    if (s.contains('ingilizce') || s.contains('english') || s.contains('yabancidil')) return 4;
    if (s.contains('matematik')) return 5;
    if (s.contains('fen')) return 6;
    return 99;
  }

  Color _eylemSubjectColor(String subject) {
    final s = _normEylem(subject);
    if (s.contains('turkce')) return const Color(0xFFE53935);
    if (s.contains('matematik')) return const Color(0xFF1E88E5);
    if (s.contains('fen')) return const Color(0xFF43A047);
    if (s.contains('sosyal') || s.contains('inkilap') || s.contains('tarih')) return const Color(0xFFFB8C00);
    if (s.contains('ingilizce') || s.contains('english')) return const Color(0xFF8E24AA);
    if (s.contains('din')) return const Color(0xFF00897B);
    return Colors.indigo;
  }

  Widget _buildEylemPlanlariTab() {
    return SafeStreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('assessment_action_plans')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildEmptyState('Eylem planları yüklenirken hata oluştu: ${snapshot.error}');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        final sId = (widget.student['id'] ?? '').toString().trim();
        final sNum = (widget.student['studentNumber'] ??
                widget.student['studentNo'] ??
                widget.student['number'] ??
                '')
            .toString()
            .trim();
        final sName = (widget.student['fullName'] ?? widget.student['name'] ?? '').toString().trim();
        final sBranchRaw = (widget.student['className'] ?? widget.student['branch'] ?? '').toString().trim();
        final sClassLevel = (widget.student['classLevel'] ?? '').toString().trim();
        final sTc = (widget.student['tcNo'] ?? '').toString().trim();

        String cleanBranchCode(String raw) {
          var b = raw.trim();
          if (b.contains('•')) {
            b = b.split('•').last.trim();
          }
          b = b.replaceAll(RegExp(r'\s+Kur$', caseSensitive: false), '').trim();
          return b;
        }

        final String realBranch = cleanBranchCode(sBranchRaw);
        final String normRealBranch = _normEylem(realBranch);

        final normId = _normEylem(sId);
        final normNum = _normEylem(sNum);
        final normName = _normEylem(sName);

        bool matchesThisStudent(String token) {
          final t = token.trim();
          if (t.isEmpty) return false;
          final nt = _normEylem(t);
          if (sId.isNotEmpty && (t.toLowerCase() == sId.toLowerCase() || (normId.isNotEmpty && nt == normId))) {
            return true;
          }
          if (sNum.isNotEmpty && (t.toLowerCase() == sNum.toLowerCase() || (normNum.isNotEmpty && nt == normNum))) {
            return true;
          }
          if (normName.isNotEmpty && nt == normName) {
            return true;
          }
          return false;
        }

        bool isCourseSubject(String subject) {
          if (!_courseTracks.isEmpty) {
            return _courseTracks.hasTrackForBranchOrLevel(
              subject,
              rawBranch: realBranch,
              classLevel: sClassLevel,
            );
          }
          final ns = _normEylem(subject);
          return ns.contains('ingilizce') || ns.contains('english') || ns.contains('maincourse');
        }

        // Öğrencinin kurs derslerindeki kur şubesi (ders -> kur şube kodu, örn. 'İngilizce' -> '706')
        final Map<String, String> studentCourseBranches = {};
        if (!_courseTracks.isEmpty) {
          for (final g in _courseTracks.groups) {
            final lesson = g.lessonName.isNotEmpty ? g.lessonName : g.name;
            final slot = _courseTracks.slotForStudent(
              studentId: sId,
              studentNo: sNum,
              tcNo: sTc,
              studentName: sName,
              subject: lesson,
              rawBranch: realBranch,
              classLevel: sClassLevel,
            );
            if (slot != null) {
              final cb = cleanBranchCode(slot.subGroupName);
              if (cb.isNotEmpty) {
                final ns = _normEylem(lesson);
                final displayLesson = (ns.contains('ingilizce') || ns.contains('english') || ns.contains('maincourse'))
                    ? 'İngilizce'
                    : lesson;
                studentCourseBranches[displayLesson] = cb;
              }
            }
          }
        }

        final myPlans = <Map<String, dynamic>>[];
        int globalTotalTasks = 0;
        int globalDoneTasks = 0;
        int globalBranchActions = 0;

        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final tasksRaw = data['studentTasks'] as Map<String, dynamic>? ?? {};
          final infoRaw = data['studentInfo'] as Map<String, dynamic>? ?? {};
          final notifiedRaw = data['parentNotified'] as Map<String, dynamic>? ?? {};
          final branchPlansRaw = data['branchActionPlans'] as Map<String, dynamic>? ?? {};
          final outcomeStatsRaw = data['outcomeStats'] as Map<String, dynamic>? ?? {};

          // Bu planda kurs dersi için öğrencinin kur şubesini döndürür (yalnızca kurs dersleri için!)
          String? courseBranchForSubject(String subject) {
            if (!isCourseSubject(subject)) return null;
            if (!_courseTracks.isEmpty) {
              final slot = _courseTracks.slotForStudent(
                studentId: sId,
                studentNo: sNum,
                tcNo: sTc,
                studentName: sName,
                subject: subject,
                rawBranch: realBranch,
                classLevel: sClassLevel,
              );
              if (slot != null) {
                final cb = cleanBranchCode(slot.subGroupName);
                if (cb.isNotEmpty) return cb;
              }
              for (final entry in studentCourseBranches.entries) {
                if (CourseTrackResolver.lessonMatches(entry.key, subject)) {
                  return entry.value;
                }
              }
            }
            // Yedek: _courseTracks henüz boşsa yalnızca bu kurs dersi için outcomeStats içinde öğrencinin bulunduğu şubeye bak
            for (final bEntry in outcomeStatsRaw.entries) {
              final subjectsVal = bEntry.value;
              if (subjectsVal is! Map) continue;
              final cleanB = cleanBranchCode(bEntry.key.toString());
              for (final sEntry in subjectsVal.entries) {
                if (!CourseTrackResolver.lessonMatches(sEntry.key.toString(), subject)) continue;
                final outcomesVal = sEntry.value;
                if (outcomesVal is! Map) continue;
                for (final oVal in outcomesVal.values) {
                  if (oVal is! Map) continue;
                  final stList = oVal['students'];
                  if (stList is List) {
                    for (final st in stList) {
                      if (st is Map) {
                        final stNo = (st['no'] ?? '').toString();
                        final stName = (st['name'] ?? '').toString();
                        if (matchesThisStudent(stNo) || matchesThisStudent(stName)) {
                          if (cleanB.isNotEmpty) return cleanB;
                        }
                      }
                    }
                  }
                }
              }
            }
            return null;
          }

          // branch_subject -> {branch, subject, tasks, success, notified}
          final Map<String, Map<String, dynamic>> studentSubjectsMap = {};

          void mergeStudentEntry({
            required String branch,
            required String subject,
            List<Map<String, dynamic>> tasks = const [],
            double? success,
            bool notified = false,
          }) {
            final cleanSubj = subject.trim();
            if (cleanSubj.isEmpty) return;

            final bool isCourse = isCourseSubject(cleanSubj);
            String displayBranch;
            if (isCourse) {
              final trackB = courseBranchForSubject(cleanSubj) ?? cleanBranchCode(branch);
              if (trackB.isEmpty) return;
              displayBranch = '$trackB Kur';
            } else {
              // Normal derslerde her zaman öğrencinin gerçek şubesi baz alınır
              displayBranch = realBranch.isNotEmpty ? realBranch : cleanBranchCode(branch);
            }
            if (displayBranch.isEmpty) return;

            final mapKey = '${_normEylem(displayBranch)}_${_normEylem(cleanSubj)}';
            final cur = studentSubjectsMap.putIfAbsent(mapKey, () => {
              'branch': displayBranch,
              'subject': cleanSubj,
              'tasks': <Map<String, dynamic>>[],
              'success': null,
              'notified': false,
            });

            if (success != null && cur['success'] == null) {
              cur['success'] = success;
            }
            if (notified) {
              cur['notified'] = true;
            }
            final existingTasks = cur['tasks'] as List<Map<String, dynamic>>;
            for (final t in tasks) {
              final type = (t['type'] ?? '').toString();
              final label = (t['label'] ?? '').toString();
              if (label.isEmpty) continue;
              final idx = existingTasks.indexWhere(
                (et) => (type.isNotEmpty && et['type'] == type) || et['label'] == label,
              );
              if (idx >= 0) {
                if (t['done'] == true) existingTasks[idx]['done'] = true;
              } else {
                existingTasks.add({
                  'type': type,
                  'label': label,
                  'done': t['done'] == true,
                });
              }
            }
          }

          // 1. studentTasks taraması
          tasksRaw.forEach((key, value) {
            if (value is! List || value.isEmpty) return;
            final parts = key.split('_');
            if (parts.length < 3) return;
            final studentToken = parts.sublist(2).join('_');
            if (!matchesThisStudent(studentToken)) return;

            final inf = infoRaw[key];
            if (inf is Map) {
              final infName = (inf['name'] ?? '').toString().trim();
              if (infName.isNotEmpty && normName.isNotEmpty && _normEylem(infName) != normName) {
                return;
              }
            }

            final branch = parts[0];
            final subject = parts[1];
            final parsedTasks = value
                .whereType<Map>()
                .map((m) => Map<String, dynamic>.from(m))
                .toList();
            final notified = notifiedRaw[key] == true;
            double? success;
            if (inf is Map && inf['success'] is num) {
              success = (inf['success'] as num).toDouble();
            }
            mergeStudentEntry(
              branch: branch,
              subject: subject,
              tasks: parsedTasks,
              success: success,
              notified: notified,
            );
          });

          // 2. studentInfo taraması (görev atanmış veya velisi bilgilendirilmiş öğrencilerin başarı yüzdesini tamamlamak için)
          infoRaw.forEach((key, val) {
            if (val is! Map) return;
            final parts = key.split('_');
            final tokenFromKey = parts.length >= 3 ? parts.sublist(2).join('_') : '';
            final vNo = (val['no'] ?? '').toString();
            final vName = (val['name'] ?? '').toString().trim();
            if (vName.isNotEmpty && normName.isNotEmpty && _normEylem(vName) != normName) {
              return;
            }
            final isMatch = matchesThisStudent(tokenFromKey) ||
                matchesThisStudent(vNo) ||
                matchesThisStudent(vName);
            if (!isMatch) return;

            final branch = (val['branch'] ?? (parts.isNotEmpty ? parts[0] : '')).toString();
            final subject = (val['subject'] ?? (parts.length >= 2 ? parts[1] : '')).toString();
            final success = val['success'] is num ? (val['success'] as num).toDouble() : null;
            final notified = notifiedRaw[key] == true;

            mergeStudentEntry(
              branch: branch,
              subject: subject,
              success: success,
              notified: notified,
            );
          });

          // 3. parentNotified taraması (studentTasks veya studentInfo'da olmasa bile veli bilgilendirmesi yapılanlar)
          notifiedRaw.forEach((key, val) {
            if (val != true) return;
            final parts = key.split('_');
            if (parts.length < 3) return;
            final studentToken = parts.sublist(2).join('_');
            if (!matchesThisStudent(studentToken)) return;
            final branch = parts[0];
            final subject = parts[1];
            mergeStudentEntry(
              branch: branch,
              subject: subject,
              notified: true,
            );
          });

          // 4. Öğrencinin gerçek şubesine (normal dersler) ve kurs şubesindeki kurs dersine ait girilmiş Şube Eylem Planlarını topla
          final List<Map<String, dynamic>> myBranchPlans = [];

          branchPlansRaw.forEach((key, val) {
            if (val is! Map) return;
            final problem = (val['problemSource'] ?? '').toString().trim();
            final action = (val['actionPlan'] ?? '').toString().trim();
            final status = (val['status'] ?? 'Planlandı').toString().trim();
            if (problem.isEmpty && action.isEmpty) return;

            String rawBranch = '';
            String subject = '';
            String outcome = '';

            final parts = key.split('_');
            if (parts.length >= 3) {
              rawBranch = parts[0].trim();
              subject = parts[1].trim();
              outcome = parts.sublist(2).join('_').trim();
            }
            final cleanB = cleanBranchCode(rawBranch);
            if (cleanB.isEmpty || subject.isEmpty) return;

            final bool isCourse = isCourseSubject(subject);
            String displayBranch;

            if (isCourse) {
              // Kurs derslerinde SADECE öğrencinin o kurs dersindeki kur şubesi baz alınır
              final String? trackB = courseBranchForSubject(subject);
              if (trackB == null || trackB.isEmpty) return;
              if (_normEylem(cleanB) != _normEylem(trackB)) return;
              displayBranch = '$trackB Kur';
            } else {
              // Normal derslerde SADECE öğrencinin gerçek şubesi baz alınır
              if (normRealBranch.isEmpty || _normEylem(cleanB) != normRealBranch) return;
              displayBranch = realBranch;
            }

            // Kazanım başarı yüzdesini outcomeStats'tan bul
            double? outcomeSuccess;
            Map? bStats = (outcomeStatsRaw[cleanB] ?? outcomeStatsRaw['$cleanB Kur'] ?? outcomeStatsRaw[rawBranch]) as Map?;
            if (bStats == null) {
              for (final bEntry in outcomeStatsRaw.entries) {
                if (_normEylem(cleanBranchCode(bEntry.key.toString())) == _normEylem(cleanB) && bEntry.value is Map) {
                  final candidate = bEntry.value as Map;
                  if (candidate.containsKey(subject)) {
                    bStats = candidate;
                    break;
                  }
                  bStats ??= candidate;
                }
              }
            }
            if (bStats != null) {
              final sStats = bStats[subject];
              if (sStats is Map) {
                final oStat = sStats[outcome];
                if (oStat is Map) {
                  final total = (oStat['total'] ?? 0) as num;
                  final correct = (oStat['correct'] ?? 0) as num;
                  if (total > 0) {
                    outcomeSuccess = (correct / total) * 100.0;
                  }
                }
              }
            }

            myBranchPlans.add({
              'branch': displayBranch,
              'subject': subject,
              'outcome': outcome,
              'problemSource': problem,
              'actionPlan': action,
              'status': status,
              'success': outcomeSuccess,
            });
          });

          // Yalnızca gerçekten görev atanmış veya velisi bilgilendirilmiş öğrenci bazlı eylem planı satırlarını dahil et ve sırala
          final studentItems = studentSubjectsMap.values
              .where((item) => (item['tasks'] as List).isNotEmpty || item['notified'] == true)
              .toList()
            ..sort((a, b) {
              final oa = _eylemSubjectOrder(a['subject'] as String);
              final ob = _eylemSubjectOrder(b['subject'] as String);
              if (oa != ob) return oa.compareTo(ob);
              return (a['subject'] as String).compareTo(b['subject'] as String);
            });

          myBranchPlans.sort((a, b) {
            final oa = _eylemSubjectOrder(a['subject'] as String);
            final ob = _eylemSubjectOrder(b['subject'] as String);
            if (oa != ob) return oa.compareTo(ob);
            final sCmp = (a['subject'] as String).compareTo(b['subject'] as String);
            if (sCmp != 0) return sCmp;
            return (a['outcome'] as String).compareTo(b['outcome'] as String);
          });

          if (studentItems.isNotEmpty || myBranchPlans.isNotEmpty) {
            int planTotalTasks = 0;
            int planDoneTasks = 0;
            for (final item in studentItems) {
              final tList = item['tasks'] as List<Map<String, dynamic>>;
              planTotalTasks += tList.length;
              planDoneTasks += tList.where((t) => t['done'] == true).length;
            }
            globalTotalTasks += planTotalTasks;
            globalDoneTasks += planDoneTasks;
            globalBranchActions += myBranchPlans.length;

            final selectedExams = List<String>.from(data['selectedExamNames'] ?? []);
            final rawNote = (data['realizationNotes'] ?? '').toString().trim();
            final String realizationNotes = (rawNote.toLowerCase() == 'results are reviewed.' ||
                    rawNote.toLowerCase() == 'results are reviewed')
                ? 'Sonuçlar incelendi ve değerlendirildi.'
                : rawNote;
            if (rawNote != realizationNotes && doc.id.isNotEmpty) {
              FirebaseFirestore.instance
                  .collection('assessment_action_plans')
                  .doc(doc.id)
                  .update({'realizationNotes': realizationNotes})
                  .catchError((_) {});
            }

            // Başlık ve açıklama için gerçek şube + varsa kurs şubesi özeti
            final List<String> courseSummaryParts = [];
            studentCourseBranches.forEach((lessonName, cb) {
              courseSummaryParts.add('$lessonName: $cb Kur');
            });

            myPlans.add({
              'id': doc.id,
              'title': (data['title'] ?? 'Eylem Planı').toString(),
              'date': (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
              'isRealized': data['isRealized'] == true,
              'selectedExams': selectedExams,
              'realizationNotes': realizationNotes,
              'studentItems': studentItems,
              'branchPlans': myBranchPlans,
              'totalTasks': planTotalTasks,
              'doneTasks': planDoneTasks,
              'realBranch': realBranch,
              'courseSummary': courseSummaryParts.join(', '),
            });
          }
        }

        if (myPlans.isEmpty) {
          return _buildEmptyState('Öğrenciye tanımlanmış bir eylem planı bulunmuyor.');
        }

        // Tarihe göre yeniden eskiye sırala
        myPlans.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            // ── Minimalist Üst Özet Çubuğu ──
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.indigo.shade50),
                boxShadow: [
                  BoxShadow(
                    color: Colors.indigo.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Wrap(
                spacing: 20,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(Icons.track_changes_rounded, size: 16, color: Colors.indigo.shade700),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Deneme Eylem Planı Takibi',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.indigo.shade900,
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildMinimalSummaryChip(
                        Icons.description_outlined,
                        '${myPlans.length} Deneme Planı',
                        Colors.indigo,
                      ),
                      if (globalTotalTasks > 0)
                        _buildMinimalSummaryChip(
                          Icons.task_alt_rounded,
                          '$globalDoneTasks/$globalTotalTasks Bireysel Görev',
                          globalDoneTasks == globalTotalTasks ? Colors.green : Colors.blue,
                        ),
                      if (globalBranchActions > 0)
                        _buildMinimalSummaryChip(
                          Icons.groups_2_outlined,
                          '$globalBranchActions Şube Kazanım Eylemi',
                          Colors.deepPurple,
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Deneme Bazlı Açılır/Kapanır (Dropdown) Eylem Planı Kartları ──
            ...List.generate(myPlans.length, (index) {
              final plan = myPlans[index];
              return _buildActionPlanDropdownCard(plan, initiallyExpanded: index == 0);
            }),
          ],
        );
      },
    );
  }

  Widget _buildMinimalSummaryChip(IconData icon, String label, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.shade100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color.shade700),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionPlanDropdownCard(Map<String, dynamic> plan, {required bool initiallyExpanded}) {
    final DateTime date = plan['date'] as DateTime;
    final bool isRealized = plan['isRealized'] as bool;
    final List<Map<String, dynamic>> studentItems = plan['studentItems'] as List<Map<String, dynamic>>;
    final List<Map<String, dynamic>> branchPlans = plan['branchPlans'] as List<Map<String, dynamic>>;
    final List<String> selectedExams = plan['selectedExams'] as List<String>;
    final String realizationNotes = plan['realizationNotes'] as String;
    final int totalTasks = plan['totalTasks'] as int;
    final int doneTasks = plan['doneTasks'] as int;
    final String realBranch = (plan['realBranch'] ?? '').toString();
    final String courseSummary = (plan['courseSummary'] ?? '').toString();

    final String branchHeaderText = [
      if (realBranch.isNotEmpty) '$realBranch Şubesi',
      if (courseSummary.isNotEmpty) courseSummary,
    ].join(' • ');

    final String branchDescText = courseSummary.isNotEmpty
        ? 'Öğrencinin gerçek şubesi ($realBranch) ve kurs şubesi ($courseSummary) baz alınarak, baraj altında kalan kazanımlar için ders bazında planlanan sınıf içi destek ve telafi çalışmaları aşağıda özetlenmiştir:'
        : 'Öğrencinin gerçek şubesi ($realBranch) baz alınarak, baraj altında kalan kazanımlar için ders bazında planlanan sınıf içi destek ve telafi çalışmaları aşağıda özetlenmiştir:';

    final bool allStudentTasksDone = totalTasks > 0 && doneTasks == totalTasks;
    final bool isCompleted = isRealized || allStudentTasksDone;

    // Şube eylem planlarını ders bazında grupla
    final Map<String, List<Map<String, dynamic>>> groupedBranchPlans = {};
    for (final bp in branchPlans) {
      final key = '${bp['subject']} (${bp['branch']})';
      groupedBranchPlans.putIfAbsent(key, () => []).add(bp);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isCompleted ? Colors.green.shade50 : Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isCompleted ? Icons.fact_check_rounded : Icons.analytics_outlined,
              size: 19,
              color: isCompleted ? Colors.green.shade700 : Colors.indigo.shade700,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  plan['title'] as String,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Colors.grey.shade900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isCompleted ? Colors.green.shade50 : Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isCompleted ? Colors.green.shade200 : Colors.amber.shade200,
                  ),
                ),
                child: Text(
                  isCompleted ? 'Tamamlandı' : 'Uygulanıyor',
                  style: TextStyle(
                    color: isCompleted ? Colors.green.shade800 : Colors.amber.shade900,
                    fontWeight: FontWeight.w600,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  DateFormat('dd.MM.yyyy').format(date),
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                ),
                if (selectedExams.isNotEmpty)
                  Text(
                    '• ${selectedExams.join(', ')}',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                    overflow: TextOverflow.ellipsis,
                  ),
                if (studentItems.isNotEmpty)
                  Text(
                    '• ${studentItems.length} Ders Destek ($doneTasks/$totalTasks Görev)',
                    style: TextStyle(fontSize: 11.5, color: Colors.indigo.shade600, fontWeight: FontWeight.w600),
                  ),
                if (branchPlans.isNotEmpty)
                  Text(
                    '• ${branchPlans.length} Şube Eylemi',
                    style: TextStyle(fontSize: 11.5, color: Colors.deepPurple.shade600, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
          children: [
            Divider(height: 1, color: Colors.grey.shade100),
            const SizedBox(height: 12),

            // ── 1. ÖĞRENCİ BAZLI KAZANIM DESTEK ÇALIŞMALARI (MİNİMALİST LİSTE) ──
            if (studentItems.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.person_pin_circle_outlined, size: 15, color: Colors.indigo.shade600),
                  const SizedBox(width: 6),
                  Text(
                    'Öğrenci Bazlı Kazanım Destek Çalışmaları',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const Spacer(),
                  if (totalTasks > 0)
                    Text(
                      '$doneTasks / $totalTasks tamamlandı',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: doneTasks == totalTasks ? Colors.green.shade700 : Colors.grey.shade500,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFBFF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.indigo.shade50),
                ),
                child: Column(
                  children: List.generate(studentItems.length, (i) {
                    final item = studentItems[i];
                    final branch = item['branch'] as String;
                    final subject = item['subject'] as String;
                    final tasksList = item['tasks'] as List<Map<String, dynamic>>;
                    final double? success = item['success'] as double?;
                    final bool notified = item['notified'] == true;
                    final subjColor = _eylemSubjectColor(subject);

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        border: i < studentItems.length - 1
                            ? Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.7))
                            : null,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(color: subjColor, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 190,
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  subject,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    color: Colors.grey.shade900,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    branch,
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                                if (success != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '%${success.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.red.shade700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 5,
                              children: tasksList.isEmpty
                                  ? [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade50,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: Colors.amber.shade200,
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.schedule_rounded,
                                              size: 12,
                                              color: Colors.amber.shade800,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Bireysel Destek / Telafi Takibi',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.amber.shade900,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ]
                                  : tasksList.map((t) {
                                      final isDone = t['done'] == true;
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                        decoration: BoxDecoration(
                                          color: isDone ? Colors.green.shade50 : Colors.white,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isDone ? Colors.green.shade200 : Colors.grey.shade300,
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isDone ? Icons.check_circle_rounded : Icons.schedule_rounded,
                                              size: 12,
                                              color: isDone ? Colors.green.shade700 : Colors.grey.shade500,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              (t['label'] ?? '').toString(),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDone ? Colors.green.shade800 : Colors.grey.shade800,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                            ),
                          ),
                          if (notified) ...[
                            const SizedBox(width: 8),
                            Tooltip(
                              message: 'Veli Bilgilendirildi',
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: Colors.teal.shade50,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: Colors.teal.shade100),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.family_restroom_rounded, size: 11, color: Colors.teal.shade700),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Veli Bilgi',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.teal.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],

            // ── 2. ŞUBE EYLEM PLANLARI (METİN OLARAK AÇIKLAMA) ──
            if (groupedBranchPlans.isNotEmpty) ...[
              if (studentItems.isNotEmpty) const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.menu_book_rounded, size: 15, color: Colors.deepPurple.shade600),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            branchHeaderText.isNotEmpty
                                ? 'Şube Eylem Planları ($branchHeaderText)'
                                : 'Şube Eylem Planları',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                        Text(
                          '${branchPlans.length} kazanım eylemi',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      branchDescText,
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, height: 1.35),
                    ),
                    const SizedBox(height: 10),
                    ...groupedBranchPlans.entries.map((entry) {
                      final subjHeader = entry.key;
                      final items = entry.value;
                      final subjColor = _eylemSubjectColor(subjHeader);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(color: subjColor, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  subjHeader,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11.5,
                                    color: Colors.indigo.shade900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ...items.map((bp) {
                              final outcome = (bp['outcome'] ?? '').toString();
                              final problem = (bp['problemSource'] ?? '').toString();
                              final action = (bp['actionPlan'] ?? '').toString();
                              final status = (bp['status'] ?? '').toString();
                              final double? rate = bp['success'] as double?;

                              final rateText = rate != null ? ' (%${rate.toStringAsFixed(0)} başarı)' : '';
                              final problemText = problem.isNotEmpty ? 'Sorun kaynağı: $problem. ' : '';
                              final actionText = action.isNotEmpty ? 'Eylem planı: $action.' : '';
                              final statusText = status.isNotEmpty && status != 'Belirlenmedi' ? ' [$status]' : '';

                              return Padding(
                                padding: const EdgeInsets.only(left: 12, bottom: 3),
                                child: RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.grey.shade800,
                                      height: 1.4,
                                    ),
                                    children: [
                                      const TextSpan(
                                        text: '• ',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      TextSpan(
                                        text: '$outcome$rateText: ',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      TextSpan(text: '$problemText$actionText'),
                                      if (statusText.isNotEmpty)
                                        TextSpan(
                                          text: statusText,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: status == 'Tamamlandı'
                                                ? Colors.green.shade700
                                                : Colors.indigo.shade600,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],

            if (realizationNotes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Text(
                  'İzleme Notu: $realizationNotes',
                  style: TextStyle(fontSize: 11.5, color: Colors.amber.shade900),
                ),
              ),
            ],
          ],
        ),
      ),
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
          child: SafeStreamBuilder<QuerySnapshot>(
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
                      color: Colors.black.withValues(alpha: 0.05),
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
    return SafeStreamBuilder<QuerySnapshot>(
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
    return SafeStreamBuilder<QuerySnapshot>(
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
                    color: Colors.indigo.withValues(alpha: 0.05),
                    blurRadius: 15,
                    offset: Offset(0, 5),
                  ),
                ],
                border: Border.all(color: Colors.indigo.withValues(alpha: 0.05)),
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
                    report.term,
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
                    Divider(height: 1, color: Colors.grey.withValues(alpha: 0.1)),
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
        color: color.withValues(alpha: 0.1),
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
    return SafeStreamBuilder<QuerySnapshot>(
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
    return SafeStreamBuilder<QuerySnapshot>(
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

            for (var list in executionStatus.values) {
              if (list is List) {
                total += list.length;
                done += list.where((s) => s == 1).length;
                incomplete += list.where((s) => s == 2).length;
              }
            }

            // Fallback total from schedule if executionStatus is empty
            if (total == 0) {
              for (var list in schedule.values) {
                if (list is List) total += list.length;
              }
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
                    color: Colors.black.withValues(alpha: 0.05),
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
                backgroundColor: Colors.indigo.shade50.withValues(alpha: 0.05),
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
                        // Weekly Target Card (Part of Mentör Çalışmaları)
                        if (data['weeklyTarget'] != null && data['weeklyTarget'].toString().trim().isNotEmpty) ...[
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.amber.shade200, width: 1),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.track_changes, color: Colors.amber.shade800, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('🎯 BU HAFTANIN HEDEFİ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF78350F), letterSpacing: 0.5)),
                                      const SizedBox(height: 2),
                                      Text(data['weeklyTarget'].toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF451A03))),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                          const SizedBox(height: 20),
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
                              return const SizedBox.shrink();
                            final dayStatuses = executionStatus[key] as List?;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.indigo,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        key.toString(),
                                        style: const TextStyle(
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
                                const SizedBox(height: 12),
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

                                  // Priority Task Check
                                  final priorityTasks = data['priorityTasks'] as Map<String, dynamic>? ?? {};
                                  final bool isPriority = priorityTasks["${key}_$idx"] == true;

                                  return InkWell(
                                    onTap: () async {
                                      await _showStatusSelectionSheet(
                                        context,
                                        widget.institutionId,
                                        programData['id'],
                                        key.toString(),
                                        idx,
                                        executionStatus,
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isPriority ? Colors.red.shade50.withValues(alpha: 0.3) : Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isPriority ? Colors.red.shade200 : Colors.grey.shade100,
                                          width: isPriority ? 1.5 : 1,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.01),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(icon, size: 18, color: color),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                if (isPriority) ...[
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.red.shade100,
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      '🚨 ÖNCELİKLİ GÖREV',
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.red.shade900,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                ],
                                                Text(
                                                  lessonText.trim(),
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.blueGrey.shade900,
                                                    height: 1.3,
                                                    fontWeight: isPriority ? FontWeight.bold : FontWeight.normal,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                                const SizedBox(height: 8),
                              ],
                            );
                          }).toList();
                        })(),

                        // Mentor Feedback Card (Part of Mentör Çalışmaları)
                        if (data['mentorEvaluation'] != null && data['mentorEvaluation'].toString().trim().isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.indigo.shade100),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.rate_review_rounded, color: Colors.indigo.shade700, size: 18),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Mentör Değerlendirmesi',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  data['mentorEvaluation'].toString(),
                                  style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade800, height: 1.4, fontStyle: FontStyle.italic),
                                ),
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.bottomRight,
                                  child: Text(
                                    'Değerlendiren: ${data['mentorEvaluationBy'] ?? "Mentör"}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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

  Future<void> _showStatusSelectionSheet(
    BuildContext context,
    String institutionId,
    String programId,
    String day,
    int index,
    Map<String, dynamic> executionStatus,
  ) async {
    final statusList = [
      {'label': 'Beklemede (Atandı)', 'value': 0, 'color': Colors.grey, 'icon': Icons.circle_outlined},
      {'label': 'Tamamlandı', 'value': 1, 'color': Colors.green, 'icon': Icons.check_circle},
      {'label': 'Eksik Yapıldı', 'value': 2, 'color': Colors.orange, 'icon': Icons.access_time_filled},
      {'label': 'Yapılamadı', 'value': 3, 'color': Colors.red, 'icon': Icons.cancel},
    ];

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Görev Durumu Güncelle',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo),
              ),
              const SizedBox(height: 16),
              ...statusList.map((status) {
                return ListTile(
                  leading: Icon(status['icon'] as IconData, color: status['color'] as Color),
                  title: Text(status['label'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () async {
                    final Map<String, List<int>> updatedStatus = {};
                    executionStatus.forEach((k, v) {
                      updatedStatus[k] = List<int>.from(v);
                    });
                    updatedStatus[day]![index] = status['value'] as int;

                    await GuidanceService().updateStudyProgramStatus(
                      institutionId,
                      programId,
                      updatedStatus,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                );
              }).toList(),
            ],
          ),
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
    return SafeStreamBuilder<QuerySnapshot>(
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
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.05),
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

  Widget _buildDemandsTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Öğrenciye Ait Talepler',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              if (UserPermissionService.canEditTeacherModule('rehberlik_islemleri', subModuleKey: 'portfolyo_talepler'))
                ElevatedButton.icon(
                  onPressed: () => _showCreateDemandDialogForStudent(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Yeni Talep'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: SafeStreamBuilder<List<DemandModel>>(
            stream: DemandService().streamDemands(
              institutionId: widget.institutionId,
              schoolTypeId: widget.student['schoolTypeId'] ?? '',
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final sid = widget.student['id'];
              final demands = (snapshot.data ?? [])
                  .where((d) => d.studentUid == sid)
                  .toList();

              if (demands.isEmpty) {
                return _buildEmptyState('Bu öğrenciye ait bir talep bulunmuyor.');
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: demands.length,
                itemBuilder: (context, index) {
                  final d = demands[index];
                   return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          d.status == DemandStatus.completed ? Icons.check_circle : Icons.pending_actions,
                          color: d.status == DemandStatus.completed ? Colors.green : Colors.orange,
                        ),
                      ),
                      title: Text(d.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(d.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(DateFormat('dd.MM.yyyy').format(d.createdAt), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                              const SizedBox(width: 12),
                              _buildStatusBadgeMini(d.status),
                            ],
                          ),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showDemandDetailProxy(d),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showCreateDemandDialogForStudent() {
     showDialog(
      context: context,
      builder: (context) => CreateDemandDialog(
        institutionId: widget.institutionId,
        schoolTypeId: widget.student['schoolTypeId'] ?? '',
        senderUid: FirebaseAuth.instance.currentUser?.uid ?? '',
        senderName: 'Yönetici', 
        senderRole: 'admin',
        userData: null, 
      ),
    );
  }

  void _showDemandDetailProxy(DemandModel d) {
    // DemandDashboardScreen içinde kullandığımız detayı burada da kullanabiliriz
    // Kod tekrarı olmaması için ortak bir widget'a çıkarmıştık zaten (_DemandDetailSheet)
    // Ancak o sınıf private (_) olduğu için erişemeyebiliriz. 
    // Onu DemandDashboardScreen dosyasında public yapalım sonra burayı güncelleriz.
    // Şimdilik sadece alert dialog ile bir özet gösterelim.
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(d.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Durum: ${d.status.name}"),
            Text("Açıklama: ${d.description}"),
            if (d.closingNote != null) ...[
              const SizedBox(height: 16),
              const Text("Kapanış Notu:", style: TextStyle(fontWeight: FontWeight.bold)),
              Text(d.closingNote!),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat')),
        ],
      ),
    );
  }

  Widget _buildStatusBadgeMini(DemandStatus status) {
    Color c = status == DemandStatus.completed ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(status.name, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold)),
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
              color: color.withValues(alpha: 0.1),
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

class FullScreenTrialChartPage extends StatefulWidget {
  final List<Map<String, dynamic>> allResults;
  final String examType;
  final String subject;
  final String metric;

  const FullScreenTrialChartPage({
    Key? key,
    required this.allResults,
    required this.examType,
    required this.subject,
    required this.metric,
  }) : super(key: key);

  @override
  State<FullScreenTrialChartPage> createState() => _FullScreenTrialChartPageState();
}

class _FullScreenTrialChartPageState extends State<FullScreenTrialChartPage> {
  int? _fullTouchedIndex;

  @override
  void initState() {
    super.initState();
    // Force Landscape for this page on mobile
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    // Restore Portrait when leaving
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Sort ascending for graph
    final results = List<Map<String, dynamic>>.from(widget.allResults);
    results.sort((a, b) => (a['date'] as DateTime).compareTo(b['date']));

    // Dynamic width based on exam count
    final chartWidth = math.max(MediaQuery.of(context).size.width, results.length * 60.0);

    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_fullTouchedIndex != null) {
            setState(() => _fullTouchedIndex = null);
          }
        },
        child: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "${widget.examType} - ${widget.subject == 'Tümü' ? (widget.metric == 'score' ? 'Toplam Puan' : 'Toplam Net') : widget.subject}",
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.indigo.shade900,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "(Tüm Geçmiş)",
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Container(
                      width: chartWidth,
                      padding: const EdgeInsets.fromLTRB(24, 24, 48, 24),
                      child: Stack(
                        children: [
                          LineChart(_getLineChartData(results)),
                          if (_fullTouchedIndex != null)
                            Positioned(
                              bottom: 30, // Tangent to zero line
                              left: 30,   // Final alignment
                              right: 0,
                              child: _buildFullScreenDetailBar(results, _fullTouchedIndex!),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 10,
            left: 10,
            child: SafeArea(
              child: CircleAvatar(
                backgroundColor: Colors.black.withValues(alpha: 0.05),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.black87),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }

  // Reuse the same logic for chart data
  LineChartData _getLineChartData(List<Map<String, dynamic>> filteredRes) {
    double calculatedMaxY = 100.0;
    if (widget.metric == 'score') {
      calculatedMaxY = 500.0;
    } else {
      calculatedMaxY = widget.subject == 'Tümü' ? 100.0 : 20.0;
    }

    double interval = calculatedMaxY > 100 ? 50.0 : 10.0;

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: interval,
        getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.shade100, strokeWidth: 1),
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
                    DateFormat('dd.MM.yy').format(date),
                    style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold, fontSize: 10),
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
            getTitlesWidget: (value, meta) => Text(
              value.toInt().toString(),
              style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold, fontSize: 10),
            ),
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
            if (widget.metric == 'score') {
              yVal = (e.value['score'] as num).toDouble();
            } else {
              if (widget.subject == 'Tümü') {
                yVal = (e.value['net'] as num).toDouble();
              } else {
                final subMap = e.value['subjects'];
                if (subMap is Map && subMap.containsKey(widget.subject)) {
                  final subData = subMap[widget.subject];
                  yVal = subData is Map ? (subData['net'] ?? 0).toDouble() : (subData as num? ?? 0).toDouble();
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
            getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
              radius: 4, color: Colors.white, strokeWidth: 2, strokeColor: Colors.indigo,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [Colors.indigo.withValues(alpha: 0.3), Colors.indigo.withValues(alpha: 0.0)],
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (touchedSpot) => Colors.transparent,
          getTooltipItems: (touchedSpots) => [],
        ),
        handleBuiltInTouches: true,
        touchCallback: (FlTouchEvent event, LineTouchResponse? touchResponse) {
          if (!event.isInterestedForInteractions ||
              touchResponse == null ||
              touchResponse.lineBarSpots == null ||
              touchResponse.lineBarSpots!.isEmpty) {
            return;
          }
          final spotIndex = touchResponse.lineBarSpots!.first.spotIndex;
          setState(() {
            _fullTouchedIndex = spotIndex;
          });
        },
      ),
    );
  }

  Widget _buildFullScreenDetailBar(List<Map<String, dynamic>> results, int index) {
    if (index < 0 || index >= results.length) return const SizedBox.shrink();
    final exam = results[index];
    final name = exam['examName'] ?? 'Sınav';
    final date = DateFormat('dd.MM.yyyy').format(exam['date']);
    final metric = widget.metric == 'score' ? 'Puan' : 'Net';
    final val = widget.metric == 'score' 
        ? (exam['score'] as num).toStringAsFixed(2)
        : (widget.subject == 'Tümü' 
            ? (exam['net'] as num).toStringAsFixed(2)
            : (exam['subjects']?[widget.subject]?['net'] ?? 0).toStringAsFixed(2));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.indigo.shade900.withValues(alpha: 0.85),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              name,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 14, color: Colors.white30),
          const SizedBox(width: 12),
          Text(
            date,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 14, color: Colors.white30),
          const SizedBox(width: 12),
          Text(
            "$val $metric",
            style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
