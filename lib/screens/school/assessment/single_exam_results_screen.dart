import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'exam_detail_table_screen.dart';
import '../../../../services/assessment_service.dart';
import '../../../../models/assessment/trial_exam_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
// Export Imports
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:edukn/services/web_share/web_file_share.dart';

import 'package:fl_chart/fl_chart.dart';
import 'dart:ui'; // For PointerDeviceKind
import '../../../../services/term_service.dart';
import 'evaluation_models.dart';
import 'student_report_card_dialog.dart';
import 'exam_report_card_service.dart';

class SingleExamResultsScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String? schoolTypeName;

  const SingleExamResultsScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    this.schoolTypeName,
  }) : super(key: key);

  @override
  _SingleExamResultsScreenState createState() =>
      _SingleExamResultsScreenState();
}

class _SingleExamResultsScreenState extends State<SingleExamResultsScreen>
    with SingleTickerProviderStateMixin {
  final AssessmentService _service = AssessmentService();
  String? _schoolTypeName;

  // Left Panel Filters
  String? _selectedClassLevel;
  String? _selectedBranchFilter;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Data
  List<TrialExam> _allExams = [];
  List<TrialExam> _filteredExams = [];
  TrialExam? _selectedExam;

  // List Tab Data
  List<Map<String, dynamic>> _branches = []; // {id, name, level}
  List<Map<String, dynamic>> _examResults = []; // Parsed/Mock results
  List<Map<String, dynamic>> _filteredResults = []; // Displayed results

  // Tabs
  late TabController _tabController;
  final List<String> _tabs = [
    'Liste',
    'Karne',
    'Ortalama',
    'Başarı Belgesi',
    'Kazanım Frekansları',
    'Soru Frekansları',
  ];

  // List Tab Options
  String _listScope = 'Kurum'; // 'Kurum', 'Şube'
  String _listSort = 'Puan Sıralı'; // 'Puan Sıralı', 'Net Sıralı'
  String? _selectedBranchId; // 'all' or specific ID
  bool _isLoadingResults = false; // Loading state for results
  bool _isSidebarVisible = true; // State for sidebar visibility
  String? _activeTermId;

  // Report Card Tab Options
  String _reportCardScope = 'Kurum'; // 'Kurum', 'Şube', 'Öğrenci'
  List<String> _reportSelectedSubjects = []; // Multi-select subjects
  String _reportSelectedBranchId = 'all'; // Dropdown selection
  String _reportSelectedStudentId = 'all'; // Dropdown selection

  OverlayEntry? _studentDropdownOverlay;
  final LayerLink _studentLayerLink = LayerLink();

  // Average Tab Options
  final String _averageScope = 'Kurum'; // 'Kurum', 'Şube'
  final String _averageSelectedBranchId = 'all';
  String _averageType = 'Başarı Yüzdesi'; // 'Başarı Yüzdesi', 'Puan', 'Net'
  List<String> _averageSelectedSubjects = [];

  // Certificate Tab Options
  String _certificateScope = 'Kurum'; // 'Kurum', 'Şube'
  String _certificateSort = 'İlk 3'; // 'İlk 3', 'İlk 5', 'İlk 10'
  String _certificateSelectedBranchId = 'all';
  String _certificateSelectedSubject = 'Tümü';

  // Topic Frequency Tab Options
  String _topicFrequencyScope = 'Kurum'; // 'Kurum', 'Şube', 'Öğrenci'
  List<String> _topicFrequencySelectedSubjects = [];
  String _topicFrequencySelectedBranchId = 'all';
  String _topicFrequencySelectedStudentId = 'all';
  OverlayEntry? _topicFrequencyStudentDropdownOverlay;
  final LayerLink _topicFrequencyStudentLayerLink = LayerLink();

  // Question Frequency Tab Options
  String _questionFrequencyScope = 'Kurum'; // 'Kurum', 'Şube', 'Öğrenci'
  List<String> _questionFrequencySelectedSubjects = [];
  String _questionFrequencySelectedBranchId = 'all';
  String _questionFrequencySelectedStudentId = 'all';
  OverlayEntry? _questionFrequencyStudentDropdownOverlay;
  final LayerLink _questionFrequencyStudentLayerLink = LayerLink();

  /// Sınavda E şıkkı olup olmadığını belirler (Lise/YKS veya cevap anahtarında E olanlar)
  bool get _hasEOption {
    if (_selectedExam == null) return false;
    for (var booklet in _selectedExam!.answerKeys.values) {
      for (var keyStr in booklet.values) {
        if (keyStr.toUpperCase().contains('E')) return true;
      }
    }
    final lvl = _selectedExam!.classLevel.toLowerCase();
    if (lvl.contains('9') ||
        lvl.contains('10') ||
        lvl.contains('11') ||
        lvl.contains('12') ||
        lvl.contains('lise') ||
        lvl.contains('yks') ||
        lvl.contains('tyt') ||
        lvl.contains('ayt')) {
      return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('tr_TR', null);
    _tabController = TabController(length: _tabs.length, vsync: this);
    _schoolTypeName = widget.schoolTypeName;
    if (_schoolTypeName == null || _schoolTypeName!.isEmpty) {
      _loadSchoolTypeName();
    }
    _loadExams();
    _loadBranches(); // Load branches for dropdown
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
        _filterExams();
      });
    });
  }

  Future<void> _loadSchoolTypeName() async {
    try {
      DocumentSnapshot<Map<String, dynamic>>? doc;
      final snap1 = await FirebaseFirestore.instance
          .collection('schoolTypes')
          .doc(widget.schoolTypeId)
          .get();
      if (snap1.exists) {
        doc = snap1;
      } else {
        final snap2 = await FirebaseFirestore.instance
            .collection('school_types')
            .doc(widget.schoolTypeId)
            .get();
        if (snap2.exists) doc = snap2;
      }

      if (doc != null && doc.exists && mounted) {
        final data = doc.data();
        final name = (data?['name'] ??
                data?['schoolTypeName'] ??
                data?['schoolType'] ??
                data?['title'] ??
                '')
            .toString()
            .trim();
        if (name.isNotEmpty) {
          setState(() {
            _schoolTypeName = name;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading schoolTypeName: $e');
    }
  }

  String _getEffectiveSchoolTypeName() {
    if (_schoolTypeName != null &&
        _schoolTypeName!.trim().isNotEmpty &&
        _schoolTypeName!.trim().toLowerCase() != 'eğitim kurumu' &&
        _schoolTypeName!.trim().toLowerCase() != 'egitim kurumu') {
      return _schoolTypeName!.trim();
    }
    final level = _selectedExam?.classLevel ?? '';
    final digits = RegExp(r'\d+').firstMatch(level)?.group(0);
    if (digits != null) {
      final grade = int.tryParse(digits);
      if (grade != null) {
        if (grade >= 1 && grade <= 4) return 'İlkokul';
        if (grade >= 5 && grade <= 8) return 'Ortaokul';
        if (grade >= 9 && grade <= 12) return 'Anadolu Lisesi';
      }
    }
    final clean = level.toLowerCase();
    if (clean.contains('anaokul') || clean.contains('kreş') || clean.contains('anasınıf')) return 'Anaokulu';
    if (clean.contains('ilkokul')) return 'İlkokul';
    if (clean.contains('ortaokul') || clean.contains('lgs')) return 'Ortaokul';
    if (clean.contains('lise') || clean.contains('yks') || clean.contains('tyt')) return 'Anadolu Lisesi';
    return 'Ortaokul';
  }

  Future<void> _loadExams() async {
    try {
      _activeTermId = await TermService().getSelectedTermId() ?? await TermService().getActiveTermId();
      final stream = _service.getTrialExams(widget.institutionId, termId: _activeTermId);
      stream.listen((exams) {
        if (mounted) {
          setState(() {
            _allExams = exams;
            _filterExams();
          });
        }
      });
    } catch (e) {
      debugPrint('Error loading exams: $e');
    }
  }

  Future<void> _loadBranches() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true)
          .get();

      if (mounted) {
        setState(() {
          _branches = snapshot.docs
              .map(
                (doc) => {
                  'id': doc.id,
                  'name': doc['className'] ?? 'Bilinmeyen',
                  'level': doc['classLevel'] ?? 0,
                },
              )
              .toList();

          // Sort branches
          _branches.sort((a, b) {
            final levelComp = (a['level'] as int).compareTo(b['level'] as int);
            if (levelComp != 0) return levelComp;
            return (a['name'] as String).compareTo(b['name'] as String);
          });
        });
      }
    } catch (e) {
      debugPrint('Error loading branches: $e');
    }
  }

  void _filterExams() {
    setState(() {
      _filteredExams = _allExams.where((exam) {
        final matchesClass =
            _selectedClassLevel == null ||
            exam.classLevel == _selectedClassLevel;
        final matchesBranch =
            _selectedBranchFilter == null ||
            exam.selectedBranches.isEmpty ||
            exam.selectedBranches.contains(_selectedBranchFilter);
        final matchesSearch = exam.name.toLowerCase().contains(_searchQuery);
        return matchesClass && matchesBranch && matchesSearch;
      }).toList();

      // Sort by date desc
      _filteredExams.sort((a, b) => b.date.compareTo(a.date));
    });
  }

  // Subject Filtering
  List<String> _availableSubjects = [];
  List<String> _selectedSubjects = [];

  void _parseResults() async {
    if (_selectedExam == null) return;

    setState(() {
      _isLoadingResults = true;
    });

    try {
      await Future.delayed(Duration(milliseconds: 500));
      if (!mounted) return;

      // 1. (Dummy Logic skipped)

      // 2. Try parse REAL data
      List<dynamic> rawData = [];
      if (_selectedExam!.resultsJson != null &&
          _selectedExam!.resultsJson!.isNotEmpty) {
        try {
          final decoded = jsonDecode(_selectedExam!.resultsJson!);
          if (decoded is List && decoded.isNotEmpty) {
            // Map backend fields to UI fields
            rawData = decoded.map((item) {
              double calcNet = 0.0;
              if (item['subjects'] != null && item['subjects'] is Map) {
                (item['subjects'] as Map).forEach((k, v) {
                  if (v is Map) {
                    calcNet +=
                        num.tryParse(v['net']?.toString() ?? '0')?.toDouble() ??
                        0.0;
                  }
                });
              } else if (item['totalNet'] != null) {
                calcNet =
                    num.tryParse(
                      item['totalNet']?.toString() ?? '0',
                    )?.toDouble() ??
                    0.0;
              }

              return {
                'raw': item,
                'rank': item['rankGeneral'] ?? item['rank'] ?? 0,
                'studentName': item['name'] ?? item['studentName'] ?? '',
                'className': item['branch'] ?? item['className'] ?? '',
                'totalScore':
                    num.tryParse(
                      item['score']?.toString() ??
                          item['totalScore']?.toString() ??
                          '0',
                    )?.toDouble() ??
                    0.0,
                'totalNet': calcNet,
                'subjects': item['subjects'] ?? {}, // PRESERVE SUBJECTS
                'studentNumber': (item['studentNo'] ??
                        item['studentNumber'] ??
                        item['number'] ??
                        item['no'] ??
                        item['schoolNumber'] ??
                        item['ogrNo'] ??
                        '')
                    .toString()
                    .trim(),
                'studentNo': (item['studentNo'] ??
                        item['studentNumber'] ??
                        item['number'] ??
                        item['no'] ??
                        item['schoolNumber'] ??
                        item['ogrNo'] ??
                        '')
                    .toString()
                    .trim(),
                'booklet': item['booklet'] ?? 'A',
                // Capture root-level answer maps if available
                'answers': item['answers'],
                'cevaplar': item['cevaplar'],
              };
            }).toList();
          }
        } catch (e) {
          debugPrint('Error parsing results JSON: $e');
        }
      }

      _examResults = List<Map<String, dynamic>>.from(rawData);

      // --- Calculate Ranks (General & Branch) Once to persist them ---
      // 1. Sort by Score Desc for General Rank
      _examResults.sort((a, b) {
        final scoreA = num.tryParse(a['totalScore']?.toString() ?? '0') ?? 0;
        final scoreB = num.tryParse(b['totalScore']?.toString() ?? '0') ?? 0;
        return scoreB.compareTo(scoreA); // Desc
      });

      // 2. Assign General Rank
      // Aynı puanı alanlar aynı sırayı alır; sonraki farklı puan bir artar.
      {
        int currentRank = 0;
        num? prevScore;
        for (int i = 0; i < _examResults.length; i++) {
          final s =
              num.tryParse(_examResults[i]['totalScore']?.toString() ?? '0') ??
              0;
          if (prevScore == null || (s - prevScore).abs() >= 0.001) {
            currentRank++;
            prevScore = s;
          }
          _examResults[i]['rankGeneral'] = currentRank;
        }
      }

      // 3. Assign Branch Rank
      // Group by branch
      Map<String, List<Map<String, dynamic>>> byBranch = {};
      for (var r in _examResults) {
        final bName = r['className'] ?? 'Unknown';
        byBranch.putIfAbsent(bName, () => []).add(r);
      }

      // Sort each branch group and assign rank
      byBranch.forEach((key, list) {
        list.sort((a, b) {
          final scoreA = num.tryParse(a['totalScore']?.toString() ?? '0') ?? 0;
          final scoreB = num.tryParse(b['totalScore']?.toString() ?? '0') ?? 0;
          return scoreB.compareTo(scoreA);
        });
        int currentRank = 0;
        num? prevScore;
        for (int k = 0; k < list.length; k++) {
          final s =
              num.tryParse(list[k]['totalScore']?.toString() ?? '0') ?? 0;
          if (prevScore == null || (s - prevScore).abs() >= 0.001) {
            currentRank++;
            prevScore = s;
          }
          list[k]['rankBranch'] = currentRank;
        }
      });
      // (Objects in _examResults are references, so they are updated)

      // Extract Subjects preserving Session Order
      List<String> orderedSubjects = [];

      if (_selectedExam != null && _selectedExam!.sessions.isNotEmpty) {
        var sortedSessions = List<TrialExamSession>.from(
          _selectedExam!.sessions,
        )..sort((a, b) => a.sessionNumber.compareTo(b.sessionNumber));

        for (var s in sortedSessions) {
          for (var subj in s.selectedSubjects) {
            if (!orderedSubjects.contains(subj)) {
              orderedSubjects.add(subj);
            }
          }
        }
      }

      // 4. Extract Subjects dynamically
      Set<String> subjsFromResults = {};
      for (var r in _examResults) {
        if (r['subjects'] != null && r['subjects'] is Map) {
          subjsFromResults.addAll((r['subjects'] as Map).keys.cast<String>());
        }
      }

      // Merge: Use ordered list first, append any extras found in results
      if (orderedSubjects.isNotEmpty) {
        List<String> finalSubjects = List.from(orderedSubjects);
        for (var s in subjsFromResults) {
          if (!finalSubjects.contains(s)) finalSubjects.add(s);
        }
        _availableSubjects = finalSubjects;
      } else {
        // Fallback
        _availableSubjects = subjsFromResults.toList()..sort();
      }

      // Default: Select ALL subjects for Report Card
      _reportSelectedSubjects = List.from(_availableSubjects);

      // Select all by default
      _selectedSubjects = List.from(_availableSubjects);

      // Default: Select ALL for Average Tab
      _averageSelectedSubjects = List.from(_availableSubjects);

      // Default: Select ALL for Topic Frequency Tab
      _topicFrequencySelectedSubjects = List.from(_availableSubjects);

      // Default: Select ALL for Question Frequency Tab
      _questionFrequencySelectedSubjects = List.from(_availableSubjects);

      // Validate _selectedBranchId against new results
      if (_listScope == 'Şube' &&
          _selectedBranchId != null &&
          _selectedBranchId != 'all') {
        final participatingNames = _examResults
            .map((e) => e['className'] as String?)
            .where((n) => n != null && n.isNotEmpty)
            .toSet();

        // _selectedBranchId is now the NAME.
        if (!participatingNames.contains(_selectedBranchId)) {
          _selectedBranchId = 'all';
        }
      }

      _filterResults();
    } catch (e) {
      debugPrint('CRITICAL Error in _parseResults: $e');
      _examResults = [];
      _filterResults();
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingResults = false;
        });
      }
    }
  }

  // --- Helper Methods ---
  void _filterResults() {
    setState(() {
      var temp = List<Map<String, dynamic>>.from(_examResults);

      // 1. Filter by Scope
      // 1. Filter by Scope
      if (_listScope == 'Şube' &&
          _selectedBranchId != null &&
          _selectedBranchId != 'all') {
        // Now _selectedBranchId holds the Branch Name directly
        temp = temp.where((r) => r['className'] == _selectedBranchId).toList();
      }

      // 2. Sort
      if (_listSort == 'Puan Sıralı') {
        temp.sort((a, b) {
          final scoreA = num.tryParse(a['totalScore']?.toString() ?? '0') ?? 0;
          final scoreB = num.tryParse(b['totalScore']?.toString() ?? '0') ?? 0;
          return scoreB.compareTo(scoreA);
        });
      } else if (_listSort == 'Sınıf/İsim Sıralı') {
        temp.sort((a, b) {
          int cmp = (a['className'] ?? '').toString().compareTo(
            b['className'] ?? '',
          );
          if (cmp != 0) return cmp;
          return (a['studentName'] ?? '').toString().compareTo(
            b['studentName'] ?? '',
          );
        });
      } else {
        temp.sort((a, b) {
          final netA = num.tryParse(a['totalNet']?.toString() ?? '0') ?? 0;
          final netB = num.tryParse(b['totalNet']?.toString() ?? '0') ?? 0;
          return netB.compareTo(netA);
        });
      }

      // Re-assign ranks based on current sort
      if (_listSort == 'Sınıf/İsim Sıralı') {
        for (int i = 0; i < temp.length; i++) {
          temp[i]['rank'] = i + 1;
        }
      } else {
        final key = _listSort == 'Puan Sıralı' ? 'totalScore' : 'totalNet';
        int currentRank = 0;
        num? prevVal;
        for (int i = 0; i < temp.length; i++) {
          final v = num.tryParse(temp[i][key]?.toString() ?? '0') ?? 0;
          if (prevVal == null || (v - prevVal).abs() >= 0.001) {
            currentRank++;
            prevVal = v;
          }
          temp[i]['rank'] = currentRank;
        }
      }

      _filteredResults = temp;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 900;

        if (isMobile) {
          // === MOBILE LAYOUT ===
          if (_selectedExam != null) {
            // Showing DETAIL view (Right Panel content) on Mobile
            return Scaffold(
              // AppBar removed to prevent double headers
              body: SafeArea(child: _buildRightPanel()),
            );
          } else {
            // Showing LIST view (Left Panel content) on Mobile
            return Scaffold(
              appBar: EduknAppBar(title: 'Tekil Sınav Raporları'),
              body: Column(
                children: [
                  _buildLeftPanelHeader(),
                  Expanded(child: _buildExamList()),
                ],
              ),
            );
          }
        } else {
          // === DESKTOP LAYOUT ===
          return Scaffold(
            body: SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ... Rest of the Row content
                  if (_isSidebarVisible)
                    Container(
                      width: 350,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        border: Border(
                          right: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      child: Column(
                        children: [
                          // Modified Header containing Collapse Button
                          _buildLeftPanelHeader(showBack: true),
                          Expanded(child: _buildExamList()),
                        ],
                      ),
                    ),

                  // RIGHT PANEL: Content
                  Expanded(
                    child: Stack(
                      children: [
                        _selectedExam == null
                            ? _buildEmptyState()
                            : _buildRightPanel(showBack: !_isSidebarVisible),
                        // Open Button (Floating or overlays)
                        if (!_isSidebarVisible)
                          Positioned(
                            left: 0,
                            top: 90, // Aligned with TabBar
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _isSidebarVisible = true),
                              child: Container(
                                padding: EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.only(
                                    topRight: Radius.circular(8),
                                    bottomRight: Radius.circular(8),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.chevron_right,
                                  color: Colors.indigo,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  Widget _buildLeftPanelHeader({bool showBack = false}) {
    final classLevels = _allExams.map((e) => e.classLevel).toSet().toList()
      ..sort();
    final branchOptions = _allExams
        .expand((e) => e.selectedBranches)
        .toSet()
        .toList()
      ..sort();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.indigo.shade600, Colors.indigo.shade400],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title Row WITH Collapse Button integrated
          Row(
            children: [
              if (showBack) ...[
                IconButton(
                  icon: Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Geri',
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
                SizedBox(width: 12),
              ],
              Icon(Icons.analytics_outlined, color: Colors.white, size: 24),
              SizedBox(width: 8),
              Text(
                'Sınavlar',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Spacer(),
              // Counter
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_filteredExams.length}',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // Collapse Button
              if (_isSidebarVisible) ...[
                SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.chevron_left, color: Colors.white),
                  onPressed: () => setState(() => _isSidebarVisible = false),
                  tooltip: 'Gizle',
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
              ],
            ],
          ),
          SizedBox(height: 16),
          // Class Level + Branch Filters
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      dropdownColor: Colors.indigo.shade600,
                      value: _selectedClassLevel,
                      hint: Text(
                        'Sınıf Seviyesi',
                        style: TextStyle(color: Colors.white70),
                      ),
                      icon: Icon(Icons.arrow_drop_down, color: Colors.white),
                      style: TextStyle(color: Colors.white),
                      isExpanded: true,
                      items: [
                        DropdownMenuItem<String>(
                          value: null,
                          child: Text(
                            'Tüm Seviyeler',
                            style: TextStyle(color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        ...classLevels.map(
                          (l) => DropdownMenuItem<String>(
                            value: l,
                            child: Text(
                              '$l. Sınıf',
                              style: TextStyle(color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedClassLevel = val;
                          _selectedExam = null;
                          _filterExams();
                        });
                      },
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      dropdownColor: Colors.indigo.shade600,
                      value: branchOptions.contains(_selectedBranchFilter)
                          ? _selectedBranchFilter
                          : null,
                      icon: Icon(Icons.arrow_drop_down, color: Colors.white),
                      style: TextStyle(color: Colors.white),
                      isExpanded: true,
                      items: [
                        DropdownMenuItem<String>(
                          value: null,
                          child: Text(
                            'Tüm Şubeler',
                            style: TextStyle(color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        ...branchOptions.map(
                          (b) => DropdownMenuItem<String>(
                            value: b,
                            child: Text(
                              b,
                              style: TextStyle(color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedBranchFilter = val;
                          _selectedExam = null;
                          _filterExams();
                        });
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          // Search Bar
          TextField(
            controller: _searchController,
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Sınav Adı Ara...',
              hintStyle: TextStyle(color: Colors.white70),
              prefixIcon: Icon(Icons.search, size: 20, color: Colors.white70),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExamList() {
    if (_filteredExams.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey[300]),
            SizedBox(height: 12),
            Text('Sonuç bulunamadı.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.all(12),
      itemCount: _filteredExams.length,
      itemBuilder: (context, index) {
        final exam = _filteredExams[index];
        final isSelected = _selectedExam?.id == exam.id;

        return Card(
          margin: EdgeInsets.only(bottom: 8),
          elevation: isSelected ? 2 : 1,
          color: isSelected ? Colors.indigo[50] : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: isSelected
                ? BorderSide(color: Colors.indigo, width: 1.5)
                : BorderSide.none,
          ),
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? Colors.indigo : Colors.grey[100],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('dd').format(exam.date),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.grey[700],
                    ),
                  ),
                  Text(
                    DateFormat('MMM', 'tr_TR').format(exam.date),
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected ? Colors.white70 : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            title: Text(
              exam.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isSelected ? Colors.indigo[900] : Colors.black87,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      exam.classLevel,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange[800],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      exam.examTypeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            onTap: () {
              setState(() {
                _selectedExam = exam;
                _parseResults();
              });
            },
          ),
        );
      },
    );
  }

  Widget _buildRightPanel({bool showBack = true}) {
    return Column(
      children: [
        // Top Header
        Container(
          color: Colors.white,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    // Icon acts as Back Button now
                    if (showBack) ...[
                    InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.arrow_back,
                          color: Colors.indigo,
                          size: 24,
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    ],

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedExam!.name,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo[900],
                            ),
                          ),
                          Text(
                            '${DateFormat('dd MMMM yyyy', 'tr_TR').format(_selectedExam!.date)} • ${_selectedExam!.classLevel}',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: Colors.indigo,
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: Colors.indigo,
                indicatorWeight: 3,
                labelStyle: TextStyle(fontWeight: FontWeight.bold),
                tabs: _tabs.map((t) => Tab(text: t)).toList(),
              ),
            ],
          ),
        ),
        Divider(height: 1),

        // Tab Content
        Expanded(
          child: Container(
            color: Colors.grey[100],
            child: _isLoadingResults
                ? Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildListTab(), // Liste
                      _buildReportCardTab(), // Karne
                      _buildAverageTab(), // Ortalama
                      _buildCertificateTab(), // Başarı Belgesi
                      _buildTopicFrequencyTab(),
                      _buildQuestionFrequencyTab(),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildListTab() {
    return Column(
      children: [
        // Toolbar
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  label: 'Kapsam',
                  value: _listScope,
                  items: ['Kurum', 'Şube'],
                  onChanged: (val) => setState(() {
                    _listScope = val!;
                    if (_listScope == 'Kurum') {
                      _selectedBranchId = null;
                    } else if (_listScope == 'Şube') {
                      _selectedBranchId = 'all'; // Auto-select all
                    }
                    _filterResults();
                  }),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: _buildDropdown(
                  label: 'Sıralama',
                  value: _listSort,
                  items: ['Puan Sıralı', 'Net Sıralı', 'Sınıf/İsim Sıralı'],
                  onChanged: (val) => setState(() {
                    _listSort = val!;
                    _filterResults();
                  }),
                ),
              ),
              if (_listScope == 'Şube') ...[
                SizedBox(width: 16),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final branchNames = _examResults
                          .map((e) => e['className']?.toString())
                          .where((n) => n != null && n.isNotEmpty)
                          .map((n) => n!)
                          .toSet()
                          .toList();
                      branchNames.sort();

                      final dropdownItems = [
                        DropdownMenuItem<String>(
                          value: 'all',
                          child: Text('Tüm Şubeler'),
                        ),
                        ...branchNames.map(
                          (name) => DropdownMenuItem<String>(
                            value: name,
                            child: Text(name),
                          ),
                        ),
                      ];

                      return _buildDropdown(
                        label: 'Şube Seç',
                        value: _selectedBranchId,
                        items: null,
                        dropdownItems: dropdownItems,
                        onChanged: (val) {
                          setState(() {
                            _selectedBranchId = val;
                            _filterResults();
                          });
                        },
                      );
                    },
                  ),
                ),
              ],

              const SizedBox(width: 12),
              // Actions Menu (3-dots) for LIST TAB
              _buildActionMenuButton(
                tooltip: 'Liste İşlemleri',
                onSelected: (val) {
                  if (val == 'list') {
                    _openExamDetailTable();
                  } else if (val == 'yazdir' || val == 'pdf') {
                    _generateAndPrintPDF();
                  } else if (val == 'excel') {
                    _generateAndExportExcel();
                  } else if (val == 'paylas') {
                    _showShareDialog(
                      title: 'Sınav Sonuç Listesi',
                      reportType: 'Liste',
                      getPdfBytes: () => _getExamResultsPdfBytes(),
                      pdfFileName: sanitizeFileName('sinav_sonuclari_${_selectedExam?.name ?? "sinav"}.pdf'),
                      getExcelBytes: () => _buildExamResultsExcelBytes(),
                      excelFileName: sanitizeFileName('sinav_sonuclari_${_selectedExam?.name ?? "sinav"}.xlsx'),
                      onSharePdf: () => _generateAndPrintPDF(shareOnly: true),
                      onShareExcel: () => _generateAndExportExcel(shareOnly: false),
                    );
                  }
                },
                items: [
                  _buildPopupItem('list', Icons.table_rows_rounded, Colors.indigo, 'Sonuçları Tabloda Göster'),
                  _buildPopupItem('yazdir', Icons.print_rounded, Colors.blue.shade700, 'Yazdır'),
                  _buildPopupItem('pdf', Icons.picture_as_pdf_rounded, Colors.red.shade700, 'PDF İndir'),
                  _buildPopupItem('excel', Icons.table_chart_rounded, Colors.green.shade700, 'Excel İndir'),
                  _buildPopupItem('paylas', Icons.share_rounded, Colors.indigo.shade700, 'Paylaş'),
                ],
              ),
            ],
          ),
        ),

        // Content
        Expanded(child: _buildSummarySection()),
      ],
    );
  }

  void _openExamDetailTable() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExamDetailTableScreen(
          examName: _selectedExam?.name ?? 'Sınav Sonuçları',
          results: _filteredResults,
          availableSubjects: _availableSubjects,
          currentExam: _selectedExam,
          allExams: _allExams,
          institutionId: widget.institutionId,
          schoolTypeName: _getEffectiveSchoolTypeName(),
          onOpenReportCard: (studentData) {
            final student = _mapToStudentResult(studentData);
            final branchCount = _examResults
                .where((r) => r['className'] == studentData['className'])
                .length;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => StudentReportCardDialog(
                  student: student,
                  examName: _selectedExam?.name ?? 'Sınav',
                  subjects: _availableSubjects,
                  outcomes: _selectedExam?.outcomes ?? {},
                  totalStudents: _examResults.length,
                  schoolStudents: _examResults.length,
                  branchStudents: branchCount,
                  isRankingVisible:
                      _selectedExam?.sharingSettings['isRankingVisible'] ?? true,
                  trialExamId: _selectedExam?.id,
                  schoolTypeName: _getEffectiveSchoolTypeName(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSummarySection() {
    if (_filteredResults.isEmpty) {
      return Center(child: Text('Veri bulunamadı.'));
    }

    // Calculate Stats
    final count = _filteredResults.length;
    // Mock Absentees
    final absentCount = (count * 0.1).ceil();

    // Dynamic Calculation Logic
    bool useSubset = _selectedSubjects.length != _availableSubjects.length;

    List<double> calculatedValues = [];
    String statLabel = 'Puan'; // Default

    if (useSubset && _selectedSubjects.isNotEmpty) {
      // If filtering subjects, we prioritize NET stats
      statLabel = 'Net';
      calculatedValues = _filteredResults.map((e) {
        double sumNet = 0.0;
        if (e['subjects'] != null && e['subjects'] is Map) {
          final sMap = e['subjects'] as Map;
          for (var subj in _selectedSubjects) {
            if (sMap.containsKey(subj)) {
              final sData = sMap[subj];
              if (sData is Map) {
                sumNet +=
                    num.tryParse(sData['net']?.toString() ?? '0')?.toDouble() ??
                    0.0;
              }
            }
          }
        }
        return sumNet;
      }).toList();
    } else {
      // Use Global Values
      final key = _listSort == 'Puan Sıralı' ? 'totalScore' : 'totalNet';
      statLabel = _listSort == 'Puan Sıralı' ? 'Puan' : 'Net';

      calculatedValues = _filteredResults.map((e) {
        return num.tryParse(e[key]?.toString() ?? '0')?.toDouble() ?? 0.0;
      }).toList();
    }

    final maxVal = calculatedValues.isNotEmpty
        ? calculatedValues.reduce((a, b) => a > b ? a : b)
        : 0.0;
    final minVal = calculatedValues.isNotEmpty
        ? calculatedValues.reduce((a, b) => a < b ? a : b)
        : 0.0;
    final avgVal = calculatedValues.isNotEmpty
        ? (calculatedValues.reduce((a, b) => a + b) / count)
        : 0.0;

    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        children: [
          // Subject Selection Chips (Reordered to Top)
          if (_availableSubjects.isNotEmpty) ...[
            Container(
              width: double.infinity,
              margin: EdgeInsets.only(bottom: 24),
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                  },
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Tümü Toggle
                      _buildLessonFilterChip(
                        label: 'Tümü',
                        isSelected:
                            _selectedSubjects.length ==
                            _availableSubjects.length,
                        onSelected: (bool selected) {
                          setState(() {
                            if (selected) {
                              _selectedSubjects = List.from(_availableSubjects);
                            } else {
                              _selectedSubjects = [];
                            }
                          });
                        },
                      ),
                      // Vertical Divider Visual
                      Container(
                        height: 24,
                        width: 1,
                        color: Colors.grey.shade300,
                        margin: EdgeInsets.symmetric(
                          horizontal: 12,
                        ), // Adjusted margin
                      ),

                      // Individual Subjects
                      ..._availableSubjects.map((subject) {
                        final isSelected = _selectedSubjects.contains(subject);
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: _buildLessonFilterChip(
                            label: subject,
                            isSelected: isSelected,
                            onSelected: (bool selected) {
                              setState(() {
                                _selectedSubjects = [subject];
                              });
                            },
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
            ),
          ],

          // Stat Cards
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Katılan',
                  count.toString(),
                  Icons.people_alt,
                  Colors.blue,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'Katılmayan',
                  absentCount.toString(),
                  Icons.person_off,
                  Colors.red,
                  onTap: null, // Dialog removed per request
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'Katılım Oranı',
                  '%${((count / (count + absentCount)) * 100).toStringAsFixed(1)}',
                  Icons.pie_chart,
                  Colors.orange,
                ),
              ),
            ],
          ),

          SizedBox(height: 24), // Increased Spacing by user request

          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'En Yüksek $statLabel',
                  maxVal.toStringAsFixed(2),
                  Icons.trending_up,
                  Colors.green,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'En Düşük $statLabel',
                  minVal.toStringAsFixed(2),
                  Icons.trending_down,
                  Colors.orange,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'Ortalama $statLabel',
                  avgVal.toStringAsFixed(2),
                  Icons.bar_chart,
                  Colors.purple,
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Şık "Sonuç Tablosunu Göster" Butonu (Geniş & Ortalı)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4338CA), Color(0xFF312E81)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4338CA).withValues(alpha: 0.32),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _openExamDetailTable,
                    borderRadius: BorderRadius.circular(16),
                    hoverColor: Colors.white.withValues(alpha: 0.08),
                    splashColor: Colors.white.withValues(alpha: 0.15),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.table_chart_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Sonuç Tablosunu Göster',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Öğrenci bazlı detaylı net, puan ve sıralama tablosunu açın',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLessonFilterChip({
    required String label,
    required bool isSelected,
    required ValueChanged<bool> onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: onSelected,
      showCheckmark: false,
      selectedColor: Colors.indigo,
      backgroundColor: Colors.white,
      side: BorderSide(
        color: isSelected ? Colors.indigo : Colors.grey.shade300,
        width: 1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.indigo.shade900,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildActionMenuButton({
    List<PopupMenuEntry<String>>? items,
    PopupMenuItemBuilder<String>? itemBuilder,
    required Function(String) onSelected,
    String tooltip = 'İşlemler',
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 18),
        Container(
          height: 48,
          alignment: Alignment.center,
          child: Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.indigo.shade100),
            ),
            child: PopupMenuButton<String>(
              tooltip: tooltip,
              padding: EdgeInsets.zero,
              icon: Icon(Icons.more_vert, color: Colors.indigo.shade800, size: 20),
              onSelected: onSelected,
              itemBuilder: itemBuilder ?? ((context) => items ?? []),
            ),
          ),
        ),
      ],
    );
  }

  PopupMenuItem<String> _buildPopupItem(
    String value,
    IconData icon,
    Color iconColor,
    String text,
  ) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // --- PAYLAŞ (SHARE) DIALOG & HELPERS ---
  // ==========================================

  String _buildShareText({
    required String title,
    required String reportType,
    String? subject,
    List<Map<String, dynamic>>? data,
    String? customShareText,
    bool fullListForClipboard = false,
  }) {
    if (customShareText != null && customShareText.trim().isNotEmpty) {
      return customShareText;
    }

    final examName = _selectedExam?.name ?? 'Sınav';
    final examDate = _selectedExam?.date != null
        ? DateFormat('dd.MM.yyyy').format(_selectedExam!.date)
        : DateFormat('dd.MM.yyyy').format(DateTime.now());

    final sb = StringBuffer();

    if (reportType == 'Liste') {
      sb.writeln('📊 *eduKN Sınav Sonuç Listesi*');
      sb.writeln('📝 *Sınav:* $examName');
      if (_listScope == 'Şube' &&
          _selectedBranchId != null &&
          _selectedBranchId != 'all') {
        sb.writeln('🏫 *Şube:* $_selectedBranchId');
      }
      sb.writeln('📅 *Tarih:* $examDate');
      final list =
          _filteredResults.isNotEmpty ? _filteredResults : _examResults;
      sb.writeln('👥 *Toplam Öğrenci:* ${list.length}');
      sb.writeln('🔢 *Sıralama:* $_listSort');
      sb.writeln('');
      sb.writeln('🏆 *ÖĞRENCİ SIRALAMA VE SONUÇ LİSTESİ:*');
      sb.writeln('────────────────────────');

      final int limit = fullListForClipboard
          ? list.length
          : (list.length > 50 ? 50 : list.length);
      for (int i = 0; i < limit; i++) {
        final item = list[i];
        final rank = item['rank'] ?? (i + 1);
        final name = item['studentName'] ?? '-';
        final cls = item['className']?.toString() ?? '';
        final net = item['totalNet'] != null
            ? (num.tryParse(item['totalNet'].toString())?.toStringAsFixed(2) ??
                item['totalNet'].toString())
            : '0.00';
        final score = item['totalScore'] != null
            ? (num.tryParse(item['totalScore'].toString())?.toStringAsFixed(2) ??
                item['totalScore'].toString())
            : '0.00';
        final classInfo = cls.isNotEmpty ? ' ($cls)' : '';
        sb.writeln('$rank. $name$classInfo • Net: $net | Puan: $score');
      }

      if (!fullListForClipboard && list.length > 50) {
        sb.writeln('────────────────────────');
        sb.writeln('... ve ${list.length - 50} öğrenci daha.');
        sb.writeln(
            '📄 Listenin tamamı için PDF veya Excel raporunu inceleyebilirsiniz.');
      }
    } else if (reportType == 'Kazanım Analizi' ||
        reportType == 'Kazanım Frekansları') {
      sb.writeln('📊 *eduKN Kazanım Analizi Raporu*');
      sb.writeln('📝 *Sınav:* $examName');
      if (subject != null && subject.isNotEmpty) {
        sb.writeln('📚 *Ders:* $subject');
      }
      sb.writeln('📅 *Tarih:* $examDate');
      sb.writeln('');
      final items = data ?? [];
      if (items.isNotEmpty) {
        sb.writeln('🎯 *KAZANIM BAŞARI ORANLARI:*');
        sb.writeln('────────────────────────');
        final int limit = fullListForClipboard
            ? items.length
            : (items.length > 40 ? 40 : items.length);
        for (int i = 0; i < limit; i++) {
          final item = items[i];
          final topic = item['topic'] ?? item['outcome'] ?? '-';
          final qCount = item['qCount'] ?? item['questionCount'] ?? 1;
          final succ = item['successRate'] != null
              ? '${item['successRate']}%'
              : (item['pct'] != null ? '%${item['pct']}' : '');
          final corr = item['correct'] ?? item['dogru'] ?? 0;
          final incorr = item['incorrect'] ?? item['yanlis'] ?? 0;
          sb.writeln(
              '• $topic ($qCount Soru) - Başarı: $succ (D: $corr, Y: $incorr)');
        }
        if (!fullListForClipboard && items.length > 40) {
          sb.writeln('────────────────────────');
          sb.writeln('... ve ${items.length - 40} kazanım daha.');
        }
      } else {
        sb.writeln(
            'ℹ️ Detaylı kazanım analizlerine eduKN üzerinden erişebilirsiniz.');
      }
    } else if (reportType == 'Soru Frekansları') {
      sb.writeln('📊 *eduKN Soru Frekans Analizi*');
      sb.writeln('📝 *Sınav:* $examName');
      if (subject != null && subject.isNotEmpty) {
        sb.writeln('📚 *Ders:* $subject');
      }
      sb.writeln('📅 *Tarih:* $examDate');
      sb.writeln('');
      final items = data ?? [];
      if (items.isNotEmpty) {
        sb.writeln('📈 *SORU BAŞARI ORANLARI:*');
        sb.writeln('────────────────────────');
        final int limit = fullListForClipboard
            ? items.length
            : (items.length > 40 ? 40 : items.length);
        for (int i = 0; i < limit; i++) {
          final item = items[i];
          final qNum = item['qNum'] ?? (i + 1);
          final correctOpt = item['correctAnswer'] ?? item['correct'] ?? '-';
          final succ =
              item['successRate'] != null ? '%${item['successRate']}' : '';
          final d = item['d'] ?? item['dogru'] ?? 0;
          final y = item['y'] ?? item['yanlis'] ?? 0;
          final b = item['b'] ?? item['bos'] ?? 0;
          sb.writeln(
              '$qNum. Soru (Doğru: $correctOpt) • Başarı: $succ | D: $d, Y: $y, B: $b');
        }
        if (!fullListForClipboard && items.length > 40) {
          sb.writeln('────────────────────────');
          sb.writeln('... ve ${items.length - 40} soru daha.');
        }
      } else {
        sb.writeln('ℹ️ Soru frekanslarına eduKN üzerinden erişebilirsiniz.');
      }
    } else if (reportType == 'Karne') {
      if (_reportCardScope == 'Öğrenci' &&
          _reportSelectedStudentId.isNotEmpty) {
        final student = _examResults.firstWhere(
          (s) => (s['studentId'] ?? s['id']) == _reportSelectedStudentId,
          orElse: () => <String, dynamic>{},
        );
        final stName = student['studentName'] ?? 'Öğrenci';
        final stClass = student['className']?.toString() ?? '';
        final stNet = student['totalNet'] != null
            ? (num.tryParse(student['totalNet'].toString())
                    ?.toStringAsFixed(2) ??
                student['totalNet'].toString())
            : '0.00';
        final stScore = student['totalScore'] != null
            ? (num.tryParse(student['totalScore'].toString())
                    ?.toStringAsFixed(2) ??
                student['totalScore'].toString())
            : '0.00';
        final stRank = student['rank'] ?? '-';
        sb.writeln('📊 *eduKN Öğrenci Sınav Karnesi*');
        sb.writeln('📝 *Sınav:* $examName');
        sb.writeln(
            '👤 *Öğrenci:* $stName ${stClass.isNotEmpty ? "($stClass)" : ""}');
        sb.writeln('📅 *Tarih:* $examDate');
        sb.writeln('');
        sb.writeln('🏆 *SONUÇLAR:*');
        sb.writeln('• Genel Sıralama: $stRank / ${_examResults.length}');
        sb.writeln('• Toplam Net: $stNet');
        sb.writeln('• Toplam Puan: $stScore');
      } else {
        sb.writeln('📊 *eduKN Kurum Sınav Karnesi*');
        sb.writeln('📝 *Sınav:* $examName');
        sb.writeln('📅 *Tarih:* $examDate');
        sb.writeln('👥 *Katılan Öğrenci:* ${_examResults.length}');
        sb.writeln(
            'ℹ️ Kurumsal analiz ve şube karşılaştırmalarına rapor ekinden erişebilirsiniz.');
      }
    } else if (reportType == 'Ortalama') {
      sb.writeln('📊 *eduKN Sınav Ortalamaları*');
      sb.writeln('📝 *Sınav:* $examName');
      sb.writeln('📅 *Tarih:* $examDate');
      sb.writeln('👥 *Toplam Öğrenci:* ${_examResults.length}');
      sb.writeln('');
      double totalSc = 0;
      double totalNt = 0;
      for (var r in _examResults) {
        totalSc += num.tryParse(r['totalScore']?.toString() ?? '0') ?? 0;
        totalNt += num.tryParse(r['totalNet']?.toString() ?? '0') ?? 0;
      }
      if (_examResults.isNotEmpty) {
        final avgScore = (totalSc / _examResults.length).toStringAsFixed(2);
        final avgNet = (totalNt / _examResults.length).toStringAsFixed(2);
        sb.writeln('🎯 *Genel Okul Ortalaması:*');
        sb.writeln('• Puan Ortalaması: $avgScore');
        sb.writeln('• Toplam Net Ortalaması: $avgNet');
      }
    } else {
      sb.writeln('📊 *eduKN Sınav Raporu*');
      sb.writeln('📝 *Sınav:* $examName');
      sb.writeln('📋 *Rapor:* $title');
      sb.writeln('📅 *Tarih:* $examDate');
      sb.writeln(
          'ℹ️ Detaylı sınav analizleri ve sonuçlarına eduKN sistemi üzerinden erişebilirsiniz.');
    }

    return sb.toString().trim();
  }

  Future<void> _sharePdfToWhatsApp({
    BuildContext? dialogCtx,
    required Future<Uint8List> Function() getPdfBytes,
    required String pdfFileName,
    String? title,
  }) async {
    if (dialogCtx != null && Navigator.canPop(dialogCtx)) {
      Navigator.pop(dialogCtx);
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Dialog(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text("PDF hazırlanıyor ve WhatsApp bağlantısı oluşturuluyor..."),
            ],
          ),
        ),
      ),
    );

    try {
      final bytes = await getPdfBytes();
      final safeName = sanitizeFileName(pdfFileName);
      String? pdfUrl;
      try {
        final ref = FirebaseStorage.instance
            .ref()
            .child('reports/${_selectedExam?.id ?? "exam"}_${DateTime.now().millisecondsSinceEpoch}_$safeName');
        final task = await ref.putData(
          bytes,
          SettableMetadata(contentType: 'application/pdf'),
        );
        pdfUrl = await task.ref.getDownloadURL();
      } catch (e) {
        debugPrint('Firebase Storage upload error: $e');
      }

      // Also trigger browser download / native share so user has the file locally too!
      try {
        await Printing.sharePdf(bytes: bytes, filename: safeName);
      } catch (e) {
        debugPrint('Printing share error: $e');
      }

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        if (pdfUrl != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '✅ PDF hazırlandı ve indirildi! WhatsApp mesajına doğrudan PDF bağlantısı eklendi.',
              ),
              backgroundColor: Colors.teal.shade800,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '📁 PDF bilgisayarınıza indirildi. İndirilen PDF dosyasını açılan WhatsApp Web sohbetine sürükleyebilirsiniz.',
              ),
              backgroundColor: Colors.indigo.shade800,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }

      final examName = _selectedExam?.name ?? 'Sınav';
      final dateStr = DateFormat('dd.MM.yyyy').format(DateTime.now());
      final studentCount = _filteredResults.isNotEmpty ? _filteredResults.length : _examResults.length;
      final sb = StringBuffer();
      sb.writeln('📊 *eduKN Sınav Sonuç Belgesi (PDF)*');
      sb.writeln('📝 *Sınav:* $examName');
      sb.writeln('📅 *Tarih:* $dateStr');
      if (studentCount > 0) {
        sb.writeln('👥 *Toplam Öğrenci:* $studentCount');
      }
      sb.writeln('');
      if (pdfUrl != null) {
        sb.writeln('📄 *Resmi Sonuç Listesi PDF Belgesini İncelemek ve İndirmek İçin Tıklayın:*');
        sb.writeln('👉 $pdfUrl');
      }

      final waUrl = Uri.parse(
          'https://api.whatsapp.com/send?text=${Uri.encodeComponent(sb.toString().trim())}');
      await launchUrl(waUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF paylaşılırken hata oluştu: $e')),
        );
      }
    }
  }

  Future<void> _shareExcelToWhatsApp({
    BuildContext? dialogCtx,
    required Future<Uint8List> Function() getExcelBytes,
    required String excelFileName,
    String? title,
  }) async {
    if (dialogCtx != null && Navigator.canPop(dialogCtx)) {
      Navigator.pop(dialogCtx);
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Dialog(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text("Excel tablosu hazırlanıyor ve bağlantı oluşturuluyor..."),
            ],
          ),
        ),
      ),
    );

    try {
      final bytes = await getExcelBytes();
      final safeName = sanitizeFileName(excelFileName);
      String? excelUrl;
      try {
        final ref = FirebaseStorage.instance
            .ref()
            .child('reports/${_selectedExam?.id ?? "exam"}_${DateTime.now().millisecondsSinceEpoch}_$safeName');
        final task = await ref.putData(
          bytes,
          SettableMetadata(contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
        );
        excelUrl = await task.ref.getDownloadURL();
      } catch (e) {
        debugPrint('Firebase Storage upload error: $e');
      }

      // Also trigger browser download / native share so user has the file locally too!
      try {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                bytes,
                mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                name: safeName,
              ),
            ],
            fileNameOverrides: [safeName],
          ),
        );
      } catch (e) {
        debugPrint('Excel local save error: $e');
      }

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        if (excelUrl != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '✅ Excel tablosu hazırlandı ve indirildi! WhatsApp mesajına indirme bağlantısı eklendi.',
              ),
              backgroundColor: Colors.teal.shade800,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '📁 Excel bilgisayarınıza indirildi. İndirilen dosyayı WhatsApp Web sohbetine sürükleyebilirsiniz.',
              ),
              backgroundColor: Colors.indigo.shade800,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }

      final examName = _selectedExam?.name ?? 'Sınav';
      final dateStr = DateFormat('dd.MM.yyyy').format(DateTime.now());
      final studentCount = _filteredResults.isNotEmpty ? _filteredResults.length : _examResults.length;
      final sb = StringBuffer();
      sb.writeln('📊 *eduKN Sınav Sonuç Tablosu (Excel)*');
      sb.writeln('📝 *Sınav:* $examName');
      sb.writeln('📅 *Tarih:* $dateStr');
      if (studentCount > 0) {
        sb.writeln('👥 *Toplam Öğrenci:* $studentCount');
      }
      sb.writeln('');
      if (excelUrl != null) {
        sb.writeln('📊 *Resmi Sonuç Listesi Excel Tablosunu İncelemek ve İndirmek İçin Tıklayın:*');
        sb.writeln('👉 $excelUrl');
      }

      final waUrl = Uri.parse(
          'https://api.whatsapp.com/send?text=${Uri.encodeComponent(sb.toString().trim())}');
      await launchUrl(waUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel paylaşılırken hata oluştu: $e')),
        );
      }
    }
  }


  Future<void> _showShareDialog({
    required String title,
    required String reportType,
    String? subject,
    List<Map<String, dynamic>>? data,
    String? customShareText,
    Future<Uint8List> Function()? getPdfBytes,
    String? pdfFileName,
    Future<void> Function()? onSharePdf,
    Future<Uint8List> Function()? getExcelBytes,
    String? excelFileName,
    Future<void> Function()? onShareExcel,
  }) async {
    final examName = _selectedExam?.name ?? 'Sınav';
    final safePdfName = sanitizeFileName(pdfFileName ?? '$title.pdf');
    final safeExcelName = sanitizeFileName(excelFileName ?? '$title.xlsx');

    final shareText = _buildShareText(
      title: title,
      reportType: reportType,
      subject: subject,
      data: data,
      customShareText: customShareText,
      fullListForClipboard: false,
    );
    final clipboardText = _buildShareText(
      title: title,
      reportType: reportType,
      subject: subject,
      data: data,
      customShareText: customShareText,
      fullListForClipboard: true,
    );

    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 480,
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.share_rounded,
                        color: Colors.indigo.shade800, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Raporu Paylaş',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo.shade900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$examName • $title',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // 1. PDF Belgesini Paylaş (WhatsApp / Sistem Paylaşımı)
              if (getPdfBytes != null || onSharePdf != null) ...[
                _buildShareOptionTile(
                  icon: Icons.share_rounded,
                  iconColor: const Color(0xFF25D366),
                  bgColor: const Color(0xFFE8F5E9),
                  title: 'PDF Belgesini Paylaş (WhatsApp vb.)',
                  subtitle: 'PDF dosyasını WhatsApp veya cihazınızda doğrudan belge olarak paylaşın',
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      final bytes = getPdfBytes != null ? await getPdfBytes() : null;
                      final fName = safePdfName;
                      if (bytes != null) {
                        final shared = await _tryShareFile(
                          bytes: bytes,
                          fileName: fName,
                          mimeType: 'application/pdf',
                          title: '$examName - $title',
                          text: '$examName • $title belgesi ektedir.',
                        );
                        if (shared) return;

                        // Paylaşım penceresi açılamadıysa yedek olarak indir
                        await Printing.sharePdf(bytes: bytes, filename: fName);
                      } else if (onSharePdf != null) {
                        await onSharePdf();
                      }
                    } catch (e) {
                      debugPrint('PDF share error: $e');
                    }
                  },
                ),
                const SizedBox(height: 10),
              ],

              // 2. Excel Dosyasını Paylaş (WhatsApp / Sistem Paylaşımı)
              if (getExcelBytes != null || onShareExcel != null) ...[
                _buildShareOptionTile(
                  icon: Icons.table_chart_rounded,
                  iconColor: const Color(0xFF107C41),
                  bgColor: const Color(0xFFE8F5E9),
                  title: 'Excel Dosyasını Paylaş (WhatsApp vb.)',
                  subtitle: 'Excel dosyasını WhatsApp veya cihazınızda doğrudan belge olarak paylaşın',
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      final bytes = getExcelBytes != null ? await getExcelBytes() : null;
                      final fName = safeExcelName;
                      if (bytes != null) {
                        final shared = await _tryShareFile(
                          bytes: bytes,
                          fileName: fName,
                          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                          title: '$examName - $title',
                          text: '$examName • $title tablosu ektedir.',
                        );
                        if (shared) return;

                        // Masaüstü tarayıcılarda (Chrome vb.) Web Share API .xlsx dosyasını desteklemez.
                        // Bu durumda dosyayı buluta yükleyip doğrudan WhatsApp paylaşımını başlatıyoruz:
                        await _shareExcelToWhatsApp(
                          getExcelBytes: () async => bytes,
                          excelFileName: fName,
                          title: title,
                        );
                      } else if (onShareExcel != null) {
                        await onShareExcel();
                      }
                    } catch (e) {
                      debugPrint('Excel share error: $e');
                    }
                  },
                ),
                const SizedBox(height: 10),
              ],

              // 3. PDF Belgesini İndir
              if (getPdfBytes != null || onSharePdf != null) ...[
                _buildShareOptionTile(
                  icon: Icons.download_rounded,
                  iconColor: Colors.red.shade700,
                  bgColor: Colors.red.shade50,
                  title: 'PDF Belgesini İndir',
                  subtitle: 'Resmi PDF belgesini doğrudan bilgisayarınıza indirin',
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      if (getPdfBytes != null) {
                        final bytes = await getPdfBytes();
                        final fName = safePdfName;
                        await Printing.sharePdf(
                          bytes: bytes,
                          filename: fName,
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('📁 "$fName" bilgisayarınıza indirildi.'),
                              backgroundColor: Colors.indigo.shade800,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } else if (onSharePdf != null) {
                        await onSharePdf();
                      }
                    } catch (e) {
                      debugPrint('PDF download error: $e');
                    }
                  },
                ),
                const SizedBox(height: 10),
              ],

              // 4. Excel Dosyasını İndir
              if (getExcelBytes != null || onShareExcel != null) ...[
                _buildShareOptionTile(
                  icon: Icons.file_download_rounded,
                  iconColor: Colors.teal.shade700,
                  bgColor: Colors.teal.shade50,
                  title: 'Excel Dosyasını İndir',
                  subtitle: 'Excel tablosunu doğrudan bilgisayarınıza indirin',
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      if (onShareExcel != null) {
                        await onShareExcel();
                      } else if (getExcelBytes != null) {
                        final bytes = await getExcelBytes();
                        final fName = safeExcelName;
                        await SharePlus.instance.share(
                          ShareParams(
                            files: [
                              XFile.fromData(
                                bytes,
                                mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                                name: fName,
                              ),
                            ],
                            fileNameOverrides: [fName],
                          ),
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('📁 "$fName" bilgisayarınıza indirildi.'),
                              backgroundColor: Colors.teal.shade800,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    } catch (e) {
                      debugPrint('Excel download error: $e');
                    }
                  },
                ),
                const SizedBox(height: 10),
              ],

              const SizedBox(height: 6),
              const Divider(height: 1),
              const SizedBox(height: 8),

              // Alt Butonlar: Link Olarak Paylaş & Metni Kopyala
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (getPdfBytes != null)
                    TextButton.icon(
                      icon: Icon(Icons.cloud_upload_outlined, size: 16, color: Colors.teal.shade700),
                      label: Text(
                        'WhatsApp PDF Linki (Bulut)',
                        style: TextStyle(fontSize: 12, color: Colors.teal.shade700, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () => _sharePdfToWhatsApp(
                        dialogCtx: ctx,
                        getPdfBytes: getPdfBytes,
                        pdfFileName: safePdfName,
                        title: title,
                      ),
                    ),
                  if (getExcelBytes != null && getPdfBytes == null)
                    TextButton.icon(
                      icon: Icon(Icons.cloud_upload_outlined, size: 16, color: Colors.teal.shade700),
                      label: Text(
                        'WhatsApp Excel Linki (Bulut)',
                        style: TextStyle(fontSize: 12, color: Colors.teal.shade700, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () => _shareExcelToWhatsApp(
                        dialogCtx: ctx,
                        getExcelBytes: getExcelBytes,
                        excelFileName: safeExcelName,
                        title: title,
                      ),
                    ),
                  TextButton.icon(
                    icon: Icon(Icons.copy_rounded, size: 16, color: Colors.grey.shade700),
                    label: Text(
                      'Metni Kopyala',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await Clipboard.setData(ClipboardData(text: clipboardText));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(reportType == 'Liste'
                                ? 'Sınav sonuç listesi panoya kopyalandı!'
                                : 'Rapor metni panoya kopyalandı!'),
                            backgroundColor: Colors.indigo.shade800,
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }


  Future<bool> _tryShareFile({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String title,
    String? text,
  }) async {
    if (kIsWeb) {
      return await shareFileWeb(
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        title: title,
        text: text,
      );
    }
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: mimeType, name: fileName)],
          fileNameOverrides: [fileName],
          subject: title,
          text: text,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Widget _buildShareOptionTile({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // --- TAM SAYFA (FULL SCREEN) SAYFALARI ---
  // ==========================================

  void _openFullScreenTopicAnalysis(
    String subject,
    List<Map<String, dynamic>> students,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: EduknAppBar(
            title: '$subject - Kazanım Analizi',
            subtitle: _selectedExam?.name,
            actions: [
              ElevatedButton.icon(
                icon: const Icon(Icons.print, size: 16),
                label: const Text('Yazdır'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _exportTopicFrequencyPdf(),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.share, size: 16),
                label: const Text('Paylaş'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade50,
                  foregroundColor: Colors.indigo.shade900,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.indigo.shade200),
                  ),
                ),
                onPressed: () => _showShareDialog(
                  title: '$subject - Kazanım Analizi',
                  reportType: 'Kazanım Analizi',
                  subject: subject,
                  data: students,
                  getPdfBytes: () => _buildTopicFrequencyPdfBytes(),
                  pdfFileName: '${subject}_Kazanim_Analizi.pdf',
                  getExcelBytes: () => _buildTopicFrequencyExcelBytes(),
                  excelFileName: '${subject}_Kazanim_Analizi.xlsx',
                  onSharePdf: () => _exportTopicFrequencyPdf(shareOnly: true),
                  onShareExcel: () => _exportTopicFrequencyExcel(shareOnly: false),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.indigo.shade100),
                ),
                child: PopupMenuButton<String>(
                  tooltip: 'İşlemler',
                  icon: Icon(Icons.more_vert, color: Colors.indigo.shade800, size: 20),
                  onSelected: (val) {
                    if (val == 'yazdir' || val == 'pdf') {
                      _exportTopicFrequencyPdf();
                    } else if (val == 'excel') {
                      _exportTopicFrequencyExcel();
                    } else if (val == 'paylas') {
                      _showShareDialog(
                        title: '$subject - Kazanım Analizi',
                        reportType: 'Kazanım Analizi',
                        subject: subject,
                        data: students,
                        getPdfBytes: () => _buildTopicFrequencyPdfBytes(),
                        pdfFileName: '${subject}_Kazanim_Analizi.pdf',
                        getExcelBytes: () => _buildTopicFrequencyExcelBytes(),
                        excelFileName: '${subject}_Kazanim_Analizi.xlsx',
                        onSharePdf: () => _exportTopicFrequencyPdf(shareOnly: true),
                        onShareExcel: () => _exportTopicFrequencyExcel(shareOnly: false),
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    _buildPopupItem('yazdir', Icons.print_rounded, Colors.blue.shade700, 'Yazdır'),
                    _buildPopupItem('pdf', Icons.picture_as_pdf_rounded, Colors.red.shade700, 'PDF İndir'),
                    _buildPopupItem('excel', Icons.table_chart_rounded, Colors.green.shade700, 'Excel İndir'),
                    _buildPopupItem('paylas', Icons.share_rounded, Colors.indigo.shade700, 'Paylaş'),
                  ],
                ),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Expanded(
                  child: _buildTopicTableContent(
                    subject,
                    students,
                    isMobile: false,
                    isFullScreen: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openFullScreenTopicFrequency(
    String subject,
    List<Map<String, dynamic>> students,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: EduknAppBar(
            title: '$subject - Detaylı Kazanım Analizi',
            subtitle: _selectedExam?.name,
            actions: [
              ElevatedButton.icon(
                icon: const Icon(Icons.print, size: 16),
                label: const Text('Yazdır'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _exportTopicFrequencyPdf(),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.share, size: 16),
                label: const Text('Paylaş'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade50,
                  foregroundColor: Colors.indigo.shade900,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.indigo.shade200),
                  ),
                ),
                onPressed: () => _showShareDialog(
                  title: '$subject - Kazanım Frekansları Raporu',
                  reportType: 'Kazanım Frekansları',
                  subject: subject,
                  data: students,
                  getPdfBytes: () => _buildTopicFrequencyPdfBytes(),
                  pdfFileName: '${subject}_Kazanim_Frekanslari.pdf',
                  getExcelBytes: () => _buildTopicFrequencyExcelBytes(),
                  excelFileName: '${subject}_Kazanim_Frekanslari.xlsx',
                  onSharePdf: () => _exportTopicFrequencyPdf(shareOnly: true),
                  onShareExcel: () => _exportTopicFrequencyExcel(shareOnly: false),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.indigo.shade100),
                ),
                child: PopupMenuButton<String>(
                  tooltip: 'İşlemler',
                  icon: Icon(Icons.more_vert, color: Colors.indigo.shade800, size: 20),
                  onSelected: (val) {
                    if (val == 'yazdir' || val == 'pdf') {
                      _exportTopicFrequencyPdf();
                    } else if (val == 'excel') {
                      _exportTopicFrequencyExcel();
                    } else if (val == 'paylas') {
                      _showShareDialog(
                        title: '$subject - Kazanım Frekansları Raporu',
                        reportType: 'Kazanım Frekansları',
                        subject: subject,
                        data: students,
                        getPdfBytes: () => _buildTopicFrequencyPdfBytes(),
                        pdfFileName: '${subject}_Kazanim_Frekanslari.pdf',
                        getExcelBytes: () => _buildTopicFrequencyExcelBytes(),
                        excelFileName: '${subject}_Kazanim_Frekanslari.xlsx',
                        onSharePdf: () => _exportTopicFrequencyPdf(shareOnly: true),
                        onShareExcel: () => _exportTopicFrequencyExcel(shareOnly: false),
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    _buildPopupItem('yazdir', Icons.print_rounded, Colors.blue.shade700, 'Yazdır'),
                    _buildPopupItem('pdf', Icons.picture_as_pdf_rounded, Colors.red.shade700, 'PDF İndir'),
                    _buildPopupItem('excel', Icons.table_chart_rounded, Colors.green.shade700, 'Excel İndir'),
                    _buildPopupItem('paylas', Icons.share_rounded, Colors.indigo.shade700, 'Paylaş'),
                  ],
                ),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Expanded(
                  child: _buildTopicFrequencyTableContent(
                    subject,
                    students,
                    isMobile: false,
                    isFullScreen: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openFullScreenQuestionFrequency(
    String subject,
    List<Map<String, dynamic>> students,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: EduknAppBar(
            title: '$subject - Detaylı Soru Analizi',
            subtitle: _selectedExam?.name,
            actions: [
              ElevatedButton.icon(
                icon: const Icon(Icons.print, size: 16),
                label: const Text('Yazdır'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _exportQuestionFrequencyPdf(),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.share, size: 16),
                label: const Text('Paylaş'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade50,
                  foregroundColor: Colors.indigo.shade900,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.indigo.shade200),
                  ),
                ),
                onPressed: () => _showShareDialog(
                  title: '$subject - Soru Frekansları ve Madde Analizi',
                  reportType: 'Soru Frekansları',
                  subject: subject,
                  data: students,
                  getPdfBytes: () => _buildQuestionFrequencyPdfBytes(),
                  pdfFileName: '${subject}_Soru_Frekanslari.pdf',
                  getExcelBytes: () => _buildQuestionFrequencyExcelBytes(),
                  excelFileName: '${subject}_Soru_Frekanslari.xlsx',
                  onSharePdf: () => _exportQuestionFrequencyPdf(shareOnly: true),
                  onShareExcel: () => _exportQuestionFrequencyExcel(shareOnly: false),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.indigo.shade100),
                ),
                child: PopupMenuButton<String>(
                  tooltip: 'İşlemler',
                  icon: Icon(Icons.more_vert, color: Colors.indigo.shade800, size: 20),
                  onSelected: (val) {
                    if (val == 'yazdir' || val == 'pdf') {
                      _exportQuestionFrequencyPdf();
                    } else if (val == 'excel') {
                      _exportQuestionFrequencyExcel();
                    } else if (val == 'paylas') {
                      _showShareDialog(
                        title: '$subject - Soru Frekansları ve Madde Analizi',
                        reportType: 'Soru Frekansları',
                        subject: subject,
                        data: students,
                        getPdfBytes: () => _buildQuestionFrequencyPdfBytes(),
                        pdfFileName: '${subject}_Soru_Frekanslari.pdf',
                        getExcelBytes: () => _buildQuestionFrequencyExcelBytes(),
                        excelFileName: '${subject}_Soru_Frekanslari.xlsx',
                        onSharePdf: () => _exportQuestionFrequencyPdf(shareOnly: true),
                        onShareExcel: () => _exportQuestionFrequencyExcel(shareOnly: false),
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    _buildPopupItem('yazdir', Icons.print_rounded, Colors.blue.shade700, 'Yazdır'),
                    _buildPopupItem('pdf', Icons.picture_as_pdf_rounded, Colors.red.shade700, 'PDF İndir'),
                    _buildPopupItem('excel', Icons.table_chart_rounded, Colors.green.shade700, 'Excel İndir'),
                    _buildPopupItem('paylas', Icons.share_rounded, Colors.indigo.shade700, 'Paylaş'),
                  ],
                ),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Expanded(
                  child: _buildQuestionFrequencyTableContent(
                    subject,
                    students,
                    isMobile: false,
                    isFullScreen: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    List<String>? items,
    List<DropdownMenuItem<String>>? dropdownItems,
    required Function(String?) onChanged,
  }) {
    // If simple items are provided, convert to DropdownMenuItem
    final menuItems =
        dropdownItems ??
        items
            ?.map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList() ??
        [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.indigo,
          ),
        ),
        SizedBox(height: 4),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: value,
              hint: Text('Seçiniz'),
              items: menuItems,
              onChanged: onChanged,
              icon: Icon(Icons.keyboard_arrow_down, color: Colors.indigo),
              style: TextStyle(color: Colors.black87, fontSize: 13),
              dropdownColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchableSelector({
    required String label,
    required String displayText,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.indigo,
          ),
        ),
        SizedBox(height: 4),
        CompositedTransformTarget(
          link: _studentLayerLink,
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      displayText,
                      style: TextStyle(color: Colors.black87, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.indigo,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _removeStudentDropdownOverlay() {
    _studentDropdownOverlay?.remove();
    _studentDropdownOverlay = null;
  }

  void _showStudentDropdownOverlay() {
    if (_studentDropdownOverlay != null) {
      _removeStudentDropdownOverlay();
      return;
    }

    _studentDropdownOverlay = OverlayEntry(
      builder: (context) {
        String searchText = '';

        return Stack(
          children: [
            // Barrier to close on click outside
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeStudentDropdownOverlay,
                child: Container(color: Colors.transparent),
              ),
            ),
            CompositedTransformFollower(
              link: _studentLayerLink,
              showWhenUnlinked: false,
              offset: Offset(0, 50), // Height of selector + gap
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
                child: Container(
                  width: 400, // Fixed width or match parent if needed
                  height: 500,
                  constraints: BoxConstraints(maxHeight: 500),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: StatefulBuilder(
                    builder: (context, setStateOverlay) {
                      // Filter and Sort Logic
                      List<Map<String, dynamic>> filtered = _examResults.where((
                        s,
                      ) {
                        final name = (s['studentName'] ?? '')
                            .toString()
                            .toLowerCase();
                        final id = _getStudentId(s).toLowerCase();
                        final search = searchText.toLowerCase();
                        return name.contains(search) || id.contains(search);
                      }).toList();

                      // Group by class
                      Map<String, List<Map<String, dynamic>>> grouped = {};
                      for (var s in filtered) {
                        String className = s['className'] ?? 'Diğer';
                        if (className.isEmpty) className = 'Diğer';
                        grouped.putIfAbsent(className, () => []).add(s);
                      }

                      // Sort Classes
                      List<String> sortedClasses = grouped.keys.toList()
                        ..sort();

                      // Sort Students
                      for (var key in grouped.keys) {
                        grouped[key]!.sort((a, b) {
                          return (a['studentName'] ?? '').toString().compareTo(
                            b['studentName'] ?? '',
                          );
                        });
                      }

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Search Box
                          TextField(
                            decoration: InputDecoration(
                              hintText: 'Öğrenci Ara...',
                              prefixIcon: Icon(Icons.search, size: 20),
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 12,
                              ),
                            ),
                            onChanged: (val) {
                              setStateOverlay(() {
                                searchText = val;
                              });
                            },
                          ),
                          SizedBox(height: 8),
                          Divider(height: 1),
                          Expanded(
                            child: ListView(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              children: [
                                ListTile(
                                  dense: true,
                                  leading: Icon(
                                    Icons.people,
                                    color: Colors.indigo,
                                    size: 20,
                                  ),
                                  title: Text(
                                    'Tüm Öğrenciler',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  onTap: () {
                                    setState(() {
                                      _reportSelectedStudentId = 'all';
                                    });
                                    _removeStudentDropdownOverlay();
                                  },
                                ),
                                Divider(height: 1),
                                ...sortedClasses.map((className) {
                                  return Theme(
                                    data: Theme.of(context).copyWith(
                                      dividerColor: Colors.transparent,
                                    ),
                                    child: ExpansionTile(
                                      initiallyExpanded: searchText.isNotEmpty,
                                      title: Text(
                                        className,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.indigo.shade700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      children: grouped[className]!.map((s) {
                                        final sId = _getStudentId(s);
                                        return ListTile(
                                          dense: true,
                                          contentPadding: EdgeInsets.only(
                                            left: 16,
                                            right: 8,
                                          ),
                                          title: Text(
                                            s['studentName'] ?? '',
                                            style: TextStyle(fontSize: 13),
                                          ),
                                          onTap: () {
                                            setState(() {
                                              _reportSelectedStudentId = sId;
                                            });
                                            _removeStudentDropdownOverlay();
                                          },
                                          selected:
                                              _reportSelectedStudentId == sId,
                                          selectedTileColor:
                                              Colors.indigo.shade50,
                                          selectedColor: Colors.indigo,
                                        );
                                      }).toList(),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_studentDropdownOverlay!);
  }

  // --- Report Card Tab Implementation ---

  Widget _buildReportCardTab() {
    return Column(
      children: [
        // Top Filters (Scope & Specific Dropdowns)
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Scope Dropdown
                  Expanded(
                    child: _buildDropdown(
                      label: 'Kapsam',
                      value: _reportCardScope,
                      items: ['Kurum', 'Şube', 'Öğrenci'],
                      onChanged: (val) {
                        setState(() {
                          _reportCardScope = val!;
                          // Reset selections
                          _reportSelectedBranchId = 'all';
                          _reportSelectedStudentId = 'all';
                        });
                      },
                    ),
                  ),
                  SizedBox(width: 16),

                  // Conditional Dropdowns
                  if (_reportCardScope == 'Şube') ...[
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final branchNames = _examResults
                              .map((e) => e['className']?.toString())
                              .where((n) => n != null && n.isNotEmpty)
                              .map((n) => n!)
                              .toSet()
                              .toList();
                          branchNames.sort();

                          final dropdownItems = [
                            DropdownMenuItem<String>(
                              value: 'all',
                              child: Text('Tüm Şubeler'),
                            ),
                            ...branchNames.map(
                              (name) => DropdownMenuItem<String>(
                                value: name,
                                child: Text(name),
                              ),
                            ),
                          ];

                          return _buildDropdown(
                            label: 'Şube Seç',
                            value: _reportSelectedBranchId,
                            items: null,
                            dropdownItems: dropdownItems,
                            onChanged: (val) {
                              setState(() {
                                _reportSelectedBranchId = val!;
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],

                  if (_reportCardScope == 'Öğrenci') ...[
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          // List ALL students sorted by name.
                          final students = List<Map<String, dynamic>>.from(
                            _examResults,
                          );
                          students.sort(
                            (a, b) => (a['studentName'] ?? '').compareTo(
                              b['studentName'] ?? '',
                            ),
                          );

                          final dropdownItems = [
                            DropdownMenuItem<String>(
                              value: 'all',
                              child: Text('Tüm Öğrenciler'),
                            ),
                            ...students.map((s) {
                              final sId = _getStudentId(s);
                              return DropdownMenuItem<String>(
                                value: sId,
                                child: Text(
                                  '${s['studentName']} (${s['className']})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }),
                          ];

                          // Find display text
                          String displayText = 'Tüm Öğrenciler';
                          if (_reportSelectedStudentId != 'all') {
                            final student = _examResults.firstWhere(
                              (s) =>
                                  _getStudentId(s) == _reportSelectedStudentId,
                              orElse: () => {},
                            );
                            if (student.isNotEmpty) {
                              displayText =
                                  '${student['studentName']} (${student['className']})';
                            }
                          }

                          return _buildSearchableSelector(
                            label: 'Öğrenci Seç',
                            displayText: displayText,
                            onTap: () {
                              _showStudentDropdownOverlay();
                            },
                          );
                        },
                      ),
                    ),
                  ],

                  // If Kurum or just padding
                  if (_reportCardScope == 'Kurum') Spacer(),

                  const SizedBox(width: 12),
                  // Actions Menu (3-dots)
                  _buildActionMenuButton(
                    tooltip: 'Karne İşlemleri',
                    onSelected: (val) {
                      if (val == 'institution_pdf') {
                        _printInstitutionalReportCard();
                      } else if (val == 'branch_students_pdf') {
                        _printStudentReportCards(branchFilter: _reportSelectedBranchId);
                      } else if (val == 'all_students_pdf') {
                        _printStudentReportCards();
                      } else if (val == 'student_pdf') {
                        _printStudentReportCards(studentIdFilter: _reportSelectedStudentId);
                      } else if (val == 'student_view') {
                        _openStudentReportCardDialog(_reportSelectedStudentId);
                      } else if (val == 'paylas') {
                        _showShareDialog(
                          title: 'Kurum ve Öğrenci Karneleri',
                          reportType: 'Karne',
                          getPdfBytes: () => _buildInstitutionalReportCardBytes(),
                          pdfFileName: 'kurum_karnesi_${_selectedExam?.name ?? "sinav"}.pdf',
                          onSharePdf: () => _printInstitutionalReportCard(shareOnly: true),
                        );
                      }
                    },
                    itemBuilder: (context) {
                      final items = <PopupMenuEntry<String>>[];

                      if (_reportCardScope == 'Kurum') {
                        items.add(
                          _buildPopupItem('institution_pdf', Icons.business_center, Colors.indigo, 'Kurum Karnesi'),
                        );
                        items.add(
                          _buildPopupItem('all_students_pdf', Icons.print, Colors.blue.shade700, 'Tüm Öğrenci Karneleri'),
                        );
                      } else if (_reportCardScope == 'Şube') {
                        final branchLabel = _reportSelectedBranchId == 'all'
                            ? 'Tüm Şubeler'
                            : '$_reportSelectedBranchId Şubesi';
                        items.add(
                          _buildPopupItem('branch_students_pdf', Icons.print, Colors.blue.shade700, '$branchLabel Karnelerini Yazdır'),
                        );
                        items.add(
                          _buildPopupItem('institution_pdf', Icons.business_center, Colors.indigo, 'Kurum Karnesi'),
                        );
                      } else if (_reportCardScope == 'Öğrenci') {
                        if (_reportSelectedStudentId != 'all') {
                          items.add(
                            _buildPopupItem('student_pdf', Icons.picture_as_pdf, Colors.red.shade700, 'Öğrenci Karnesi'),
                          );
                          items.add(
                            _buildPopupItem('student_view', Icons.visibility, Colors.indigo, 'Karneyi Ekranda İncele'),
                          );
                        } else {
                          items.add(
                            _buildPopupItem('all_students_pdf', Icons.print, Colors.blue.shade700, 'Tüm Öğrenci Karneleri'),
                          );
                        }
                        items.add(
                          _buildPopupItem('institution_pdf', Icons.business_center, Colors.indigo, 'Kurum Karnesi'),
                        );
                      }

                      items.add(
                        _buildPopupItem('paylas', Icons.share_rounded, Colors.indigo.shade700, 'Paylaş'),
                      );

                      return items;
                    },
                  ),
                ],
              ),
            ],
          ),
        ),

        // Charts Area
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Subject Chips (Moved here - identical style to List Tab)
                if (_availableSubjects.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    margin: EdgeInsets.only(bottom: 24),
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                        },
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            // Tümü Toggle
                            _buildLessonFilterChip(
                              label: 'Tümü',
                              isSelected:
                                  _reportSelectedSubjects.length ==
                                  _availableSubjects.length,
                              onSelected: (bool selected) {
                                setState(() {
                                  if (selected) {
                                    _reportSelectedSubjects = List.from(
                                      _availableSubjects,
                                    );
                                  } else {
                                    _reportSelectedSubjects = [];
                                  }
                                });
                              },
                            ),
                            // Vertical Divider Visual
                            Container(
                              height: 24,
                              width: 1,
                              color: Colors.grey.shade300,
                              margin: EdgeInsets.symmetric(horizontal: 12),
                            ),

                            // Individual Subjects
                            ..._availableSubjects.map((subject) {
                              final isSelected = _reportSelectedSubjects
                                  .contains(subject);
                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: _buildLessonFilterChip(
                                  label: subject,
                                  isSelected: isSelected,
                                  onSelected: (bool selected) {
                                    setState(() {
                                      _reportSelectedSubjects = [subject];
                                    });
                                  },
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                _buildSubjectAnalysisRow(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- Topic Frequency Tab Implementation ---

  void _removeTopicFrequencyStudentDropdownOverlay() {
    _topicFrequencyStudentDropdownOverlay?.remove();
    _topicFrequencyStudentDropdownOverlay = null;
  }

  void _showTopicFrequencyStudentDropdownOverlay() {
    if (_topicFrequencyStudentDropdownOverlay != null) {
      _removeTopicFrequencyStudentDropdownOverlay();
      return;
    }

    _topicFrequencyStudentDropdownOverlay = OverlayEntry(
      builder: (context) {
        String searchText = '';

        return Stack(
          children: [
            // Barrier to close on click outside
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeTopicFrequencyStudentDropdownOverlay,
                child: Container(color: Colors.transparent),
              ),
            ),
            CompositedTransformFollower(
              link: _topicFrequencyStudentLayerLink,
              showWhenUnlinked: false,
              offset: Offset(0, 50), // Height of selector + gap
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
                child: Container(
                  width: 400, // Fixed width or match parent if needed
                  height: 500,
                  constraints: BoxConstraints(maxHeight: 500),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: StatefulBuilder(
                    builder: (context, setStateOverlay) {
                      // Filter and Sort Logic
                      List<Map<String, dynamic>> filtered = _examResults.where((
                        s,
                      ) {
                        final name = (s['studentName'] ?? '')
                            .toString()
                            .toLowerCase();
                        final id = _getStudentId(s).toLowerCase();
                        final search = searchText.toLowerCase();
                        return name.contains(search) || id.contains(search);
                      }).toList();

                      // Group by class
                      Map<String, List<Map<String, dynamic>>> grouped = {};
                      for (var s in filtered) {
                        String className = s['className'] ?? 'Misafir';
                        if (className.isEmpty) className = 'Misafir';
                        grouped.putIfAbsent(className, () => []).add(s);
                      }

                      // Sort Classes
                      List<String> sortedClasses = grouped.keys.toList()
                        ..sort();

                      // Sort Students
                      for (var key in grouped.keys) {
                        grouped[key]!.sort((a, b) {
                          return (a['studentName'] ?? '').toString().compareTo(
                            b['studentName'] ?? '',
                          );
                        });
                      }

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Search Box
                          TextField(
                            decoration: InputDecoration(
                              hintText: 'Öğrenci Ara...',
                              prefixIcon: Icon(Icons.search, size: 20),
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 12,
                              ),
                            ),
                            onChanged: (val) {
                              setStateOverlay(() {
                                searchText = val;
                              });
                            },
                          ),
                          SizedBox(height: 8),
                          Divider(height: 1),
                          Expanded(
                            child: ListView(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              children: [
                                ListTile(
                                  dense: true,
                                  leading: Icon(
                                    Icons.people,
                                    color: Colors.indigo,
                                    size: 20,
                                  ),
                                  title: Text(
                                    'Tüm Öğrenciler',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  onTap: () {
                                    setState(() {
                                      _topicFrequencySelectedStudentId = 'all';
                                    });
                                    _removeTopicFrequencyStudentDropdownOverlay();
                                  },
                                ),
                                Divider(height: 1),
                                ...sortedClasses.map((className) {
                                  return Theme(
                                    data: Theme.of(context).copyWith(
                                      dividerColor: Colors.transparent,
                                    ),
                                    child: ExpansionTile(
                                      initiallyExpanded: searchText.isNotEmpty,
                                      title: Text(
                                        className,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.indigo.shade700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      children: grouped[className]!.map((s) {
                                        final sId = _getStudentId(s);
                                        return ListTile(
                                          dense: true,
                                          contentPadding: EdgeInsets.only(
                                            left: 16,
                                            right: 8,
                                          ),
                                          title: Text(
                                            s['studentName'] ?? '',
                                            style: TextStyle(fontSize: 13),
                                          ),
                                          onTap: () {
                                            setState(() {
                                              _topicFrequencySelectedStudentId =
                                                  sId;
                                            });
                                            _removeTopicFrequencyStudentDropdownOverlay();
                                          },
                                          selected:
                                              _topicFrequencySelectedStudentId ==
                                              sId,
                                          selectedTileColor:
                                              Colors.indigo.shade50,
                                          selectedColor: Colors.indigo,
                                        );
                                      }).toList(),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_topicFrequencyStudentDropdownOverlay!);
  }

  Widget _buildTopicFrequencyTab() {
    return Column(
      children: [
        // Top Filters (Scope & Specific Dropdowns)
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Scope Dropdown
                  Expanded(
                    child: _buildDropdown(
                      label: 'Kapsam',
                      value: _topicFrequencyScope,
                      items: ['Kurum', 'Şube', 'Öğrenci'],
                      onChanged: (val) {
                        setState(() {
                          _topicFrequencyScope = val!;
                          // Reset selections
                          _topicFrequencySelectedBranchId = 'all';
                          _topicFrequencySelectedStudentId = 'all';
                        });
                      },
                    ),
                  ),
                  SizedBox(width: 16),

                  // Conditional Dropdowns
                  if (_topicFrequencyScope == 'Şube') ...[
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final branchNames = _examResults
                              .map((e) => e['className']?.toString())
                              .where((n) => n != null && n.isNotEmpty)
                              .map((n) => n!)
                              .toSet()
                              .toList();
                          branchNames.sort();

                          final dropdownItems = [
                            DropdownMenuItem<String>(
                              value: 'all',
                              child: Text('Tüm Şubeler'),
                            ),
                            ...branchNames.map(
                              (name) => DropdownMenuItem<String>(
                                value: name,
                                child: Text(name),
                              ),
                            ),
                          ];

                          return _buildDropdown(
                            label: 'Şube Seç',
                            value: _topicFrequencySelectedBranchId,
                            items: null,
                            dropdownItems: dropdownItems,
                            onChanged: (val) {
                              setState(() {
                                _topicFrequencySelectedBranchId = val!;
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],

                  if (_topicFrequencyScope == 'Öğrenci') ...[
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          // Find display text
                          String displayText = 'Tüm Öğrenciler';
                          if (_topicFrequencySelectedStudentId != 'all') {
                            final student = _examResults.firstWhere(
                              (s) =>
                                  _getStudentId(s) ==
                                  _topicFrequencySelectedStudentId,
                              orElse: () => {},
                            );
                            if (student.isNotEmpty) {
                              displayText =
                                  '${student['studentName']} (${student['className']})';
                            }
                          }

                          return CompositedTransformTarget(
                            link: _topicFrequencyStudentLayerLink,
                            child: _buildSearchableSelector(
                              label: 'Öğrenci Seç',
                              displayText: displayText,
                              onTap: () {
                                _showTopicFrequencyStudentDropdownOverlay();
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  if (_topicFrequencyScope == 'Kurum') Spacer(),

                  const SizedBox(width: 12),
                  // Actions Menu (3-dots)
                  _buildActionMenuButton(
                    tooltip: 'Kazanım Frekans İşlemleri',
                    onSelected: (val) {
                      if (val == 'yazdir' || val == 'pdf') {
                        _exportTopicFrequencyPdf();
                      } else if (val == 'excel') {
                        _exportTopicFrequencyExcel();
                      } else if (val == 'paylas') {
                        _showShareDialog(
                          title: 'Kazanım Frekansları Raporu',
                          reportType: 'Kazanım Frekansları',
                          getPdfBytes: () => _buildTopicFrequencyPdfBytes(),
                          pdfFileName: 'kazanim_frekanslari_${_selectedExam?.name ?? "sinav"}.pdf',
                          getExcelBytes: () => _buildTopicFrequencyExcelBytes(),
                          excelFileName: 'kazanim_frekanslari_${_selectedExam?.name ?? "sinav"}.xlsx',
                          onSharePdf: () => _exportTopicFrequencyPdf(shareOnly: true),
                          onShareExcel: () => _exportTopicFrequencyExcel(shareOnly: false),
                        );
                      }
                    },
                    items: [
                      _buildPopupItem('yazdir', Icons.print_rounded, Colors.blue.shade700, 'Yazdır'),
                      _buildPopupItem('pdf', Icons.picture_as_pdf_rounded, Colors.red.shade700, 'PDF İndir'),
                      _buildPopupItem('excel', Icons.table_chart_rounded, Colors.green.shade700, 'Excel İndir'),
                      _buildPopupItem('paylas', Icons.share_rounded, Colors.indigo.shade700, 'Paylaş'),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        // Charts Area
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Subject Chips
                if (_availableSubjects.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    margin: EdgeInsets.only(bottom: 24),
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                        },
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            // Tümü Toggle
                            _buildLessonFilterChip(
                              label: 'Tümü',
                              isSelected:
                                  _topicFrequencySelectedSubjects.length ==
                                  _availableSubjects.length,
                              onSelected: (bool selected) {
                                setState(() {
                                  if (selected) {
                                    _topicFrequencySelectedSubjects = List.from(
                                      _availableSubjects,
                                    );
                                  } else {
                                    _topicFrequencySelectedSubjects = [];
                                  }
                                });
                              },
                            ),
                            // Vertical Divider Visual
                            Container(
                              height: 24,
                              width: 1,
                              color: Colors.grey.shade300,
                              margin: EdgeInsets.symmetric(horizontal: 12),
                            ),

                            // Individual Subjects
                            ..._availableSubjects.map((subject) {
                              final isSelected = _topicFrequencySelectedSubjects
                                  .contains(subject);
                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: _buildLessonFilterChip(
                                  label: subject,
                                  isSelected: isSelected,
                                  onSelected: (bool selected) {
                                    setState(() {
                                      _topicFrequencySelectedSubjects = [
                                        subject,
                                      ];
                                    });
                                  },
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                _buildTopicFrequencyRow(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Masaüstünde grafik + liste panellerinin yüksekliği: ekran yüksekliğine göre
  double _contentPanelHeight() {
    final h = MediaQuery.of(context).size.height;
    return (h - 340).clamp(320.0, 1400.0).toDouble();
  }

  Widget _buildTopicFrequencyRow() {
    List<String> subjectsToShow = [];
    if (_topicFrequencySelectedSubjects.isEmpty) {
      subjectsToShow = [];
    } else {
      subjectsToShow = _topicFrequencySelectedSubjects;
    }

    // Filter Data based on Scope
    List<Map<String, dynamic>> relevantData = [];

    if (_topicFrequencyScope == 'Kurum') {
      relevantData = _examResults;
    } else if (_topicFrequencyScope == 'Şube') {
      if (_topicFrequencySelectedBranchId == 'all') {
        relevantData = _examResults;
      } else {
        relevantData = _examResults
            .where((r) => r['className'] == _topicFrequencySelectedBranchId)
            .toList();
      }
    } else if (_topicFrequencyScope == 'Öğrenci') {
      if (_topicFrequencySelectedStudentId == 'all') {
        relevantData = _examResults;
      } else {
        relevantData = _examResults
            .where((r) => _getStudentId(r) == _topicFrequencySelectedStudentId)
            .toList();
      }
    }

    if (relevantData.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Seçili kriterlere göre veri bulunamadı.'),
        ),
      );
    }

    bool isMobile = MediaQuery.of(context).size.width < 900;
    // Check if "Tüm Dersler" logic applies (more than 1 subject selected, usually meaning 'All')
    bool isAllView = subjectsToShow.length > 1;

    // --- CASE 1: Multiple Subjects (All) ---
    if (isAllView) {
      if (isMobile) {
        // Mobile: Vertical Stack (Keep as is per user request)
        return Column(
          children: [
            // 1. General Chart
            _buildAnalysisCard(
              'Tüm Dersler',
              relevantData,
              isMobile: true,
              isFullWidth: true,
            ),
            SizedBox(height: 16),
            // 2. List of Tables
            ...subjectsToShow.map((subject) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: _buildTopicFrequencyTable(
                  subject,
                  relevantData,
                  isMobile: true,
                ),
              );
            }).toList(),
          ],
        );
      } else {
        // Desktop: Split View (Chart Left, Tables Right)
        // REVISED: Single Table on Right ("Tüm Dersler")
        return Container(
          height: _contentPanelHeight(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left: General Chart
              _buildAnalysisCard(
                'Tüm Dersler',
                relevantData,
                isMobile: false,
                isFullWidth: false, // Default width
              ),
              Expanded(
                child: _buildTopicFrequencyTable(
                  'Tüm Dersler',
                  relevantData,
                  isMobile: false,
                  fitHeight: true, // Enable scrolling within fixed height
                  onFullScreen: () => _openFullScreenTopicFrequency(
                    'Tüm Dersler',
                    relevantData,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    }

    // --- CASE 2: Single Subject ---
    final subject = subjectsToShow[0];

    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: _buildAnalysisCard(
                subject,
                relevantData,
                isMobile: true,
                isFullWidth: true,
              ),
            ),
            SizedBox(height: 16),
            _buildTopicFrequencyTable(subject, relevantData, isMobile: true),
          ],
        ),
      );
    } else {
      // Desktop Single View
      double sidebarW = _isSidebarVisible ? 320 : 0;
      double availableW = MediaQuery.of(context).size.width - sidebarW - 80;

      return Container(
        width: availableW,
        height: _contentPanelHeight(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch, // STRETCH
          children: [
            _buildAnalysisCard(subject, relevantData, isMobile: false),
            Expanded(
              child: _buildTopicFrequencyTable(
                subject,
                relevantData,
                isMobile: false,
                fitHeight: true, // Enable scrolling within fixed height
                onFullScreen: () => _openFullScreenTopicFrequency(
                  subject,
                  relevantData,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildTopicFrequencyTable(
    String subject,
    List<Map<String, dynamic>> students, {
    bool isMobile = false,
    VoidCallback? onFullScreen,
    bool fitHeight = false, // New parameter to control expansion
  }) {
    // If multiple subjects (All view), we are in a Column -> Expanded(Column) -> children.
    // We shouldn't expand inside the card if the card itself is in a scrolling list or column expecting intrinsic height.
    // However, if we're in Single view (Desktop), we are in a Row -> Expanded -> TopicTable.

    // To solve this universally:
    // We will use Flexible/Expanded ONLY when we know we have bounded height.
    // Since determining that from props is tricky, let's assume we want intrinsic height for the "All Subjects" list view (vertical list).
    // And for Single Subject view (Desktop), we are inside a fixed height Container (500), so we can expand.

    // Better approach: Pass `shrinkWrap: true` or similar?
    // Actually, just avoid `Expanded` around the content. Let the content determine height if possible, OR fill available space.
    // But `DataTable` in a `SingleChildScrollView` (horizontal) needs height? No.

    return Card(
      margin: EdgeInsets.only(left: isMobile ? 0 : 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: fitHeight
              ? MainAxisSize.max
              : MainAxisSize.min, // Fill if fitting
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$subject - Kazanım Analizi (Sayısal)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                if (onFullScreen != null)
                  IconButton(
                    icon: Icon(Icons.fullscreen),
                    onPressed: onFullScreen,
                    tooltip: 'Tam Ekran',
                  ),
              ],
            ),
            Divider(),
            // If fitHeight is true, we must Expand and Scroll
            fitHeight
                ? Expanded(
                    child: SingleChildScrollView(
                      child: _buildTopicFrequencyTableContent(
                        subject,
                        students,
                        isMobile: isMobile,
                      ),
                    ),
                  )
                : _buildTopicFrequencyTableContent(
                    subject,
                    students,
                    isMobile: isMobile,
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicFrequencyTableContent(
    String subject,
    List<Map<String, dynamic>> students, {
    bool isMobile = false,
    bool isFullScreen = false,
  }) {
    if (_selectedExam == null || students.isEmpty) return SizedBox();

    int studentCount = students.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        // --- ALL SUBJECTS AGGREGATION ---
        if (subject == 'Tüm Dersler') {
          List<DataRow> allRows = [];

          for (var subj in _availableSubjects) {
            // Respect filter
            if (!_topicFrequencySelectedSubjects.contains(subj)) continue;

            // Calculate stats for this subject
            var results = _calculateTopicStats(subj, students);
            var subjectStats =
                results['stats'] as Map<String, Map<String, double>>;
            var subjectQCounts = results['topicQCounts'] as Map<String, int>;

            if (subjectQCounts.isEmpty) continue;

            List<DataRow> subjRows = _generateDataRows(
              subj,
              subjectStats,
              subjectQCounts,
              studentCount,
              isMobile,
              constraints.maxWidth,
            );

            if (subjRows.isNotEmpty) {
              // Add Header Row for this subject
              allRows.add(
                DataRow(
                  color: WidgetStateProperty.all(Colors.grey.shade100),
                  cells: [
                    DataCell(
                      Container(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          subj,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                      ),
                    ),
                    DataCell(SizedBox()),
                    DataCell(SizedBox()),
                    DataCell(SizedBox()),
                    DataCell(SizedBox()),
                    DataCell(SizedBox()),
                    DataCell(SizedBox()),
                  ],
                ),
              );
              // Add Data Rows
              allRows.addAll(subjRows);
            }
          }
          return _buildDataTable(context, allRows, isMobile, isFullScreen, minWidth: constraints.maxWidth);
        }

        // --- SINGLE SUBJECT LOGIC ---
        var results = _calculateTopicStats(subject, students);
        var stats = results['stats'] as Map<String, Map<String, double>>;
        var topicQCounts = results['topicQCounts'] as Map<String, int>;

        List<DataRow> dynamicRows = _generateDataRows(
          subject,
          stats,
          topicQCounts,
          studentCount,
          isMobile,
          constraints.maxWidth,
        );

        return _buildDataTable(context, dynamicRows, isMobile, isFullScreen, minWidth: constraints.maxWidth);
      },
    );
  }

  // --- HELPER FUNCTIONS TO AVOID DUPLICATION ---

  Map<String, dynamic> _calculateTopicStats(
    String subject,
    List<Map<String, dynamic>> students,
  ) {
    Map<String, Map<String, double>> stats = {};

    for (var student in students) {
      String booklet = student['booklet']?.toString() ?? 'A';
      if (!_selectedExam!.outcomes.containsKey(booklet)) {
        var match = _selectedExam!.outcomes.keys.firstWhere(
          (k) =>
              k.toString().toUpperCase().contains(booklet.toUpperCase()) ||
              k == 'A',
          orElse: () => _selectedExam!.outcomes.keys.first,
        );
        booklet = match;
      }
      Map<String, dynamic> subMap = student['subjects'] ?? {};

      if (!_selectedExam!.outcomes.containsKey(booklet)) continue;
      if (!_selectedExam!.outcomes[booklet]!.containsKey(subject)) continue;
      if (!_selectedExam!.answerKeys.containsKey(booklet)) continue;
      if (!_selectedExam!.answerKeys[booklet]!.containsKey(subject)) continue;
      if (!subMap.containsKey(subject)) continue;

      List<String> outcomes = _selectedExam!.outcomes[booklet]![subject]!;
      String answerKey = _selectedExam!.answerKeys[booklet]![subject]!;
      String studentAnswers = '';

      String extractStr(dynamic val) {
        if (val == null) return '';
        if (val is String) return val;
        if (val is List) return val.join('');
        return val.toString();
      }

      if (subMap[subject] != null) {
        var sData = subMap[subject];
        if (sData is Map) {
          if (sData['answers'] != null)
            studentAnswers = extractStr(sData['answers']);
          else if (sData['cevaplar'] != null)
            studentAnswers = extractStr(sData['cevaplar']);
          else if (sData['cevap_anahtari'] != null)
            studentAnswers = extractStr(sData['cevap_anahtari']);

          if (studentAnswers.isEmpty) {
            for (var k in sData.keys) {
              String ks = k.toString().toLowerCase();
              if (ks.contains('answer') || ks.contains('cevap')) {
                studentAnswers = extractStr(sData[k]);
                break;
              }
            }
          }
        }
      }

      if (studentAnswers.isEmpty) {
        if (student['answers'] is Map && student['answers'][subject] != null) {
          studentAnswers = extractStr(student['answers'][subject]);
        } else if (student['cevaplar'] is Map &&
            student['cevaplar'][subject] != null) {
          studentAnswers = extractStr(student['cevaplar'][subject]);
        }
      }

      studentAnswers = studentAnswers.toUpperCase();
      answerKey = answerKey.toUpperCase();

      int len = outcomes.length;
      if (answerKey.length < len) len = answerKey.length;
      if (studentAnswers.length < len) {
        studentAnswers = studentAnswers.padRight(len, ' ');
      }

      for (int i = 0; i < len; i++) {
        String topic = outcomes[i];
        if (topic.isEmpty) topic = 'Diğer';

        if (!stats.containsKey(topic)) {
          stats[topic] = {'qCount': 0, 'correct': 0, 'wrong': 0, 'empty': 0};
        }

        String keyChar = answerKey[i];
        String studChar = studentAnswers[i];

        final status = TrialExam.evaluateAnswer(studChar, keyChar);
        bool isCorrect = status == AnswerStatus.correct;
        bool isEmpty = status == AnswerStatus.empty;
        bool isWrong = status == AnswerStatus.wrong;

        if (isCorrect)
          stats[topic]!['correct'] = (stats[topic]!['correct'] ?? 0) + 1;
        if (isWrong) stats[topic]!['wrong'] = (stats[topic]!['wrong'] ?? 0) + 1;
        if (isEmpty) stats[topic]!['empty'] = (stats[topic]!['empty'] ?? 0) + 1;
      }
    }

    // Fix Question Counts and Indices
    Map<String, int> topicQCounts = {};
    Map<String, List<int>> topicIndices = {};

    if (_selectedExam!.outcomes.isNotEmpty) {
      String refBooklet = _selectedExam!.outcomes.keys.firstWhere(
        (k) =>
            k.contains('A') && _selectedExam!.outcomes[k]!.containsKey(subject),
        orElse: () => _selectedExam!.outcomes.keys.first,
      );

      var bookletData = _selectedExam!.outcomes[refBooklet];
      if (bookletData != null && bookletData.containsKey(subject)) {
        List<String> refs = bookletData[subject] ?? [];
        for (int i = 0; i < refs.length; i++) {
          String t = refs[i];
          String top = t.isEmpty ? 'Diğer' : t;
          topicQCounts[top] = (topicQCounts[top] ?? 0) + 1;

          topicIndices.putIfAbsent(top, () => []).add(i + 1);
        }
      }
    }

    return {
      'stats': stats,
      'topicQCounts': topicQCounts,
      'topicIndices': topicIndices,
    };
  }

  List<DataRow> _generateDataRows(
    String subject,
    Map<String, Map<String, double>> stats,
    Map<String, int> topicQCounts,
    int studentCount,
    bool isMobile,
    double parentWidth, {
    Map<String, List<int>>? topicIndices,
    bool showIndices = false,
  }) {
    double topicW;

    if (isMobile) {
      topicW = 280;
    } else {
      topicW = (parentWidth - 450).clamp(180.0, double.infinity);
    }

    if (topicW < 180) topicW = 180;

    List<DataRow> dynamicRows = [];
    Set<String> allTopics = {...topicQCounts.keys, ...stats.keys};

    for (var topic in allTopics) {
      double rawCorrect = stats[topic]?['correct'] ?? 0;
      double rawWrong = stats[topic]?['wrong'] ?? 0;
      double rawEmpty = stats[topic]?['empty'] ?? 0;
      int qCount = topicQCounts[topic] ?? 0;
      if (qCount == 0) continue;

      int totalQCount = qCount * studentCount;
      double successRate = totalQCount > 0
          ? (rawCorrect / totalQCount) * 100
          : 0;

      String questionColValue = '$qCount';
      if (showIndices &&
          topicIndices != null &&
          topicIndices.containsKey(topic)) {
        final indices = topicIndices[topic]!;
        indices.sort();
        questionColValue = indices.join(', '); // "1, 3, 5"
      }

      dynamicRows.add(
        DataRow(
          cells: [
            DataCell(
              Container(
                width: topicW,
                child: _CursorTooltip(
                  message: topic,
                  child: Text(
                    topic,
                    style: TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            DataCell(
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 80),
                  child: _CursorTooltip(
                    message: showIndices
                        ? 'Sorular: $questionColValue'
                        : 'Soru Sayısı: $questionColValue',
                    child: Text(
                      questionColValue,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
            DataCell(
              Align(
                alignment: Alignment.centerRight,
                child: Text('$totalQCount', style: TextStyle(fontSize: 12)),
              ),
            ),
            DataCell(
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  rawCorrect.toStringAsFixed(0),
                  style: TextStyle(fontSize: 12, color: Colors.green),
                ),
              ),
            ),
            DataCell(
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  rawWrong.toStringAsFixed(0),
                  style: TextStyle(fontSize: 12, color: Colors.red),
                ),
              ),
            ),
            DataCell(
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  rawEmpty.toStringAsFixed(0),
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ),
            DataCell(
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '%${successRate.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _getSuccessColor(successRate),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return dynamicRows;
  }

  Widget _buildDataTable(
    BuildContext context,
    List<DataRow> rows,
    bool isMobile,
    bool isFullScreen, {
    double minWidth = 0,
  }) {
    Widget horizontalTable = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth),
          child: DataTable(
            headingRowHeight: 40,
            dataRowHeight: 48, // Standard height
            columnSpacing: 12,
            horizontalMargin: 8,
            columns: [
              DataColumn(
                label: Text(
                  'Kazanım',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              DataColumn(
                label: Text(
                  'Soru',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                numeric: true,
                tooltip: 'Soru Sayısı',
              ),
              DataColumn(
                label: Text(
                  'Top. Soru',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                numeric: true,
                tooltip: 'Toplam Soru Sayısı',
              ),
              DataColumn(
                label: Text(
                  'D',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                numeric: true,
                tooltip: 'Doğru',
              ),
              DataColumn(
                label: Text(
                  'Y',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                numeric: true,
                tooltip: 'Yanlış',
              ),
              DataColumn(
                label: Text(
                  'B',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                numeric: true,
                tooltip: 'Boş',
              ),
              DataColumn(
                label: Text(
                  '% Başarı',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                numeric: true,
              ),
            ],
            rows: rows,
          ),
        ),
      ),
    );

    if (isMobile && !isFullScreen) {
      return horizontalTable;
    } else {
      // Desktop OR FullScreen: Wrap in Vertical Scroll to prevent overflow
      // In FullScreen, we are inside an Expanded widget, so we must scroll internally.
      return ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: horizontalTable,
        ),
      );
    }
  }

  // Obsolete Side Selectors removed

  Widget _buildSubjectAnalysisRow() {
    // 1. Identify Subjects to show (Use Multi-Select list)
    List<String> subjectsToShow = [];
    if (_reportSelectedSubjects.isEmpty) {
      subjectsToShow = [];
    } else {
      subjectsToShow = _reportSelectedSubjects;
    }

    // 2. Filter Data based on Scope
    List<Map<String, dynamic>> relevantData = [];

    if (_reportCardScope == 'Kurum') {
      relevantData = _examResults;
    } else if (_reportCardScope == 'Şube') {
      if (_reportSelectedBranchId == 'all') {
        relevantData = _examResults; // Avg of all
      } else {
        relevantData = _examResults
            .where((r) => r['className'] == _reportSelectedBranchId)
            .toList();
      }
    } else if (_reportCardScope == 'Öğrenci') {
      if (_reportSelectedStudentId == 'all') {
        relevantData = _examResults;
      } else {
        relevantData = _examResults
            .where((r) => _getStudentId(r) == _reportSelectedStudentId)
            .toList();
      }
    }

    if (relevantData.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Seçili kriterlere göre veri bulunamadı.'),
        ),
      );
    }

    bool isMobile = MediaQuery.of(context).size.width < 900;
    bool isAllView = subjectsToShow.length > 1;

    // --- MOBILE LAYOUT ---
    if (isMobile) {
      // Single Subject
      if (subjectsToShow.length == 1) {
        final subject = subjectsToShow[0];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: _buildAnalysisCard(
                  subject,
                  relevantData,
                  isMobile: true,
                  isFullWidth: true,
                ),
              ),
              SizedBox(height: 16),
              _buildTopicAnalysisTable(subject, relevantData, isMobile: true),
            ],
          ),
        );
      }

      // Multiple Subjects (Vertical List of Cards)
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: subjectsToShow.map((subject) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _reportSelectedSubjects = [subject];
                  });
                },
                child: _buildAnalysisCard(
                  subject,
                  relevantData,
                  isMobile: true,
                  isFullWidth: true,
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    // --- DESKTOP LAYOUT ---
    double sidebarW = _isSidebarVisible ? 320 : 0;
    double availableW = MediaQuery.of(context).size.width - sidebarW - 80;

    String targetSubject = isAllView
        ? 'Tüm Dersler'
        : (subjectsToShow.firstOrNull ?? '');
    if (targetSubject.isEmpty) return SizedBox();

    return Container(
      height: _contentPanelHeight(),
      width: availableW,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Analysis Card (Fixed Width ~350, handled internally or via constraint)
          _buildAnalysisCard(targetSubject, relevantData, isMobile: false),
          // Topic Analysis Table (Expanded to fill remaining space)
          Expanded(
            child: _buildTopicAnalysisTable(
              targetSubject,
              relevantData,
              isMobile: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisCard(
    String subject,
    List<Map<String, dynamic>> data, {
    bool isMobile = false,
    bool isFullWidth = false,
    double? width, // Added parameter
  }) {
    // Calculate Stats
    int correct = 0;
    int wrong = 0;
    int empty = 0;

    for (var r in data) {
      if (subject == 'Tüm Dersler') {
        // Aggregate all subjects
        if (r['subjects'] != null && r['subjects'] is Map) {
          (r['subjects'] as Map).forEach((k, v) {
            if (v is Map) {
              correct += int.tryParse(v['correct']?.toString() ?? '0') ?? 0;
              wrong += int.tryParse(v['wrong']?.toString() ?? '0') ?? 0;
              empty += int.tryParse(v['empty']?.toString() ?? '0') ?? 0;
            }
          });
        }
      } else {
        if (r['subjects'] != null &&
            r['subjects'] is Map &&
            (r['subjects'] as Map).containsKey(subject)) {
          final sData = (r['subjects'] as Map)[subject];
          if (sData is Map) {
            correct += int.tryParse(sData['correct']?.toString() ?? '0') ?? 0;
            wrong += int.tryParse(sData['wrong']?.toString() ?? '0') ?? 0;
            empty += int.tryParse(sData['empty']?.toString() ?? '0') ?? 0;
          }
        }
      }
    }

    int total = correct + wrong + empty;
    double successRate = total > 0 ? (correct / total) * 100 : 0.0;

    // Determine width
    double? cardWidth;
    if (width != null) {
      cardWidth = width;
    } else if (isFullWidth) {
      cardWidth = null; // Unbounded, let it stretch
    } else {
      cardWidth = isMobile ? 180 : 260; // Fixed width for list items
    }
    final Widget analysisCard = Container(
      width: cardWidth,
      height: isMobile
          ? 220
          : 320, // Fixed height to safely use Expanded inside
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Text(
            subject,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Divider(height: 16, thickness: 0.5),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: isMobile
                        ? 40
                        : 60, // Smaller center on mobile
                    startDegreeOffset: -90,
                    sections: [
                      PieChartSectionData(
                        color: Colors.green,
                        value: correct.toDouble(),
                        radius: isMobile ? 20 : 25, // Thinner ring on mobile
                        showTitle: false,
                      ),
                      PieChartSectionData(
                        color: Colors.red,
                        value: wrong.toDouble(),
                        radius: isMobile ? 20 : 25,
                        showTitle: false,
                      ),
                      PieChartSectionData(
                        color: Colors.grey.shade300,
                        value: empty.toDouble(),
                        radius: isMobile ? 20 : 25,
                        showTitle: false,
                      ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '%${successRate.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isMobile ? 18 : 24, // Smaller font on mobile
                        color: Colors.indigo.shade900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 8),
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildCompactLegendItem('D', correct.toString(), Colors.green),
              _buildCompactLegendItem('Y', wrong.toString(), Colors.red),
              _buildCompactLegendItem('B', empty.toString(), Colors.grey),
            ],
          ),
        ],
      ),
    );
    // Masaüstünde grafik sabit boyutta kalsın, üstte hizalansın
    if (isMobile) return analysisCard;
    return Align(alignment: Alignment.topCenter, child: analysisCard);
  }

  Widget _buildCompactLegendItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Opacity(
            opacity: 0.1,
            child: Icon(Icons.analytics, size: 150, color: Colors.indigo),
          ),
          SizedBox(height: 20),
          Text(
            'Bir Sınav Seçiniz',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          Text(
            'Detaylı raporları görüntülemek için soldan bir sınav seçin.',
            style: TextStyle(color: Colors.grey[500]),
          ),
          SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.arrow_back),
            label: Text('Geri Dön'),
          ),
        ],
      ),
    );
  }

  // --- Average Tab Implementation ---
  Widget _buildAverageTab() {
    return Column(
      children: [
        // Top Filters
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              // Scope Dropdown
              Expanded(
                child: _buildDropdown(
                  label: 'Kapsam',
                  value: 'Kurum-Şube',
                  items: ['Kurum-Şube'],
                  onChanged: (val) {},
                ),
              ),
              SizedBox(width: 16),

              // Average Type Dropdown
              Expanded(
                child: _buildDropdown(
                  label: 'Ortalama Tipi',
                  value: _averageType,
                  items: ['Başarı Yüzdesi', 'Puan', 'Net'],
                  onChanged: (val) {
                    setState(() {
                      _averageType = val!;
                    });
                  },
                ),
              ),

              const SizedBox(width: 12),
              // Actions Menu (3-dots)
              _buildActionMenuButton(
                tooltip: 'Ortalama İşlemleri',
                onSelected: (val) {
                  if (val == 'yazdir' || val == 'pdf') {
                    _exportAveragePdf();
                  } else if (val == 'excel') {
                    _exportAverageExcel();
                  } else if (val == 'paylas') {
                    _showShareDialog(
                      title: 'Ortalamalar Raporu (${_averageType})',
                      reportType: 'Ortalama',
                      getPdfBytes: () => _buildAveragePdfBytes(),
                      pdfFileName: 'ortalamalar_${_selectedExam?.name ?? "sinav"}.pdf',
                      getExcelBytes: () => _buildAverageExcelBytes(),
                      excelFileName: 'ortalamalar_${_selectedExam?.name ?? "sinav"}.xlsx',
                      onSharePdf: () => _exportAveragePdf(shareOnly: true),
                      onShareExcel: () => _exportAverageExcel(shareOnly: false),
                    );
                  }
                },
                items: [
                  _buildPopupItem('yazdir', Icons.print_rounded, Colors.blue.shade700, 'Yazdır'),
                  _buildPopupItem('pdf', Icons.picture_as_pdf_rounded, Colors.red.shade700, 'PDF İndir'),
                  _buildPopupItem('excel', Icons.table_chart_rounded, Colors.green.shade700, 'Excel İndir'),
                  _buildPopupItem('paylas', Icons.share_rounded, Colors.indigo.shade700, 'Paylaş'),
                ],
              ),
            ],
          ),
        ),

        // Subject Chips
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.white,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildLessonFilterChip(
                    label: 'Tümü',
                    isSelected:
                        _averageSelectedSubjects.length ==
                        _availableSubjects.length,
                    onSelected: (bool selected) {
                      setState(() {
                        if (selected) {
                          _averageSelectedSubjects = List.from(
                            _availableSubjects,
                          );
                        } else {
                          _averageSelectedSubjects = [];
                        }
                      });
                    },
                  ),
                  Container(
                    height: 24,
                    width: 1,
                    color: Colors.grey.shade300,
                    margin: EdgeInsets.symmetric(horizontal: 12),
                  ),
                  ..._availableSubjects.map((subject) {
                    final isSelected = _averageSelectedSubjects.contains(
                      subject,
                    );
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: _buildLessonFilterChip(
                        label: subject,
                        isSelected: isSelected,
                        onSelected: (bool selected) {
                          setState(() {
                            _averageSelectedSubjects = [subject];
                          });
                        },
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ),
        ),

        // Main Content (Split View)
        // Main Content (Responsive View)
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Decide breakpoint, e.g. 900px
              bool isMobile = constraints.maxWidth < 900;

              if (isMobile) {
                // Mobile: Stack Vertical
                return SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildAverageChartCard(isMobile: true),
                      SizedBox(height: 16),
                      // Give table a fixed height so its internal LayoutBuilder works
                      SizedBox(
                        height: 500,
                        child: _buildAverageTable(isMobile: true),
                      ),
                    ],
                  ),
                );
              } else {
                // Desktop: Side-by-Side
                double sidebarW = _isSidebarVisible ? 320 : 0;
                double availableW =
                    MediaQuery.of(context).size.width - sidebarW - 80;

                return Padding(
                  padding: EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                      width: availableW,
                      height: _contentPanelHeight(),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Left: Analysis Chart
                          _buildAverageChartCard(isMobile: false),
                          // Right: Branch Table
                          Expanded(child: _buildAverageTable(isMobile: false)),
                        ],
                      ),
                    ),
                  ),
                );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAverageChartCard({bool isMobile = false}) {
    int totalC = 0;
    int totalW = 0;
    int totalE = 0;
    double totalNet = 0;
    double totalScore = 0;
    int studentCount = 0;

    List<String> subjects = _averageSelectedSubjects.isEmpty
        ? _availableSubjects
        : _averageSelectedSubjects;

    for (var r in _examResults) {
      studentCount++;
      totalScore +=
          num.tryParse(r['totalScore']?.toString() ?? '0')?.toDouble() ?? 0;
      totalNet +=
          num.tryParse(r['totalNet']?.toString() ?? '0')?.toDouble() ?? 0;

      if (r['subjects'] != null && r['subjects'] is Map) {
        (r['subjects'] as Map).forEach((k, v) {
          if (subjects.contains(k) && v is Map) {
            totalC += int.tryParse(v['correct']?.toString() ?? '0') ?? 0;
            totalW += int.tryParse(v['wrong']?.toString() ?? '0') ?? 0;
            totalE += int.tryParse(v['empty']?.toString() ?? '0') ?? 0;
          }
        });
      }
    }

    double avgNet = studentCount > 0 ? totalNet / studentCount : 0;
    double avgScore = studentCount > 0 ? totalScore / studentCount : 0;
    double successRate = (totalC + totalW + totalE) > 0
        ? (totalC / (totalC + totalW + totalE)) * 100
        : 0;
    if (_averageSelectedSubjects.length < _availableSubjects.length) {
      int partialTotal = totalC + totalW + totalE;
      successRate = partialTotal > 0 ? (totalC / partialTotal) * 100 : 0;
    }

    String centerText = '';
    if (_averageType == 'Başarı Yüzdesi')
      centerText = '%${successRate.toStringAsFixed(0)}';
    else if (_averageType == 'Puan')
      centerText = avgScore.toStringAsFixed(0);
    else if (_averageType == 'Net')
      centerText = avgNet.toStringAsFixed(1);

    double? cardWidth = isMobile
        ? 180
        : 260; // Standardize with _buildAnalysisCard

    final Widget averageCard = Container(
      width: cardWidth,
      height: isMobile ? 220 : 320, // Match fixed height of _buildAnalysisCard
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        children: [
          Text(
            _averageSelectedSubjects.length == _availableSubjects.length
                ? 'Genel Ortalama'
                : 'Seçili Ders Ortalama',
            style: TextStyle(
              fontSize: 16, // Match _buildAnalysisCard font size
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Divider(height: 16, thickness: 0.5),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: isMobile ? 40 : 60,
                    startDegreeOffset: -90,
                    sections: [
                      PieChartSectionData(
                        color: Colors.green,
                        value: totalC.toDouble() > 0 ? totalC.toDouble() : 1,
                        radius: isMobile ? 20 : 25,
                        showTitle: false,
                      ),
                      PieChartSectionData(
                        color: Colors.red,
                        value: totalW.toDouble(),
                        radius: isMobile ? 20 : 25,
                        showTitle: false,
                      ),
                      PieChartSectionData(
                        color: Colors.grey.shade300,
                        value: totalE.toDouble(),
                        radius: isMobile ? 20 : 25,
                        showTitle: false,
                      ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      centerText,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isMobile ? 18 : 24, // Match font size
                        color: Colors.indigo.shade900,
                      ),
                    ),
                    if (_averageType != 'Başarı Yüzdesi')
                      Text(
                        _averageType,
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 8),
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildCompactLegendItem('D', totalC.toString(), Colors.green),
              _buildCompactLegendItem('Y', totalW.toString(), Colors.red),
              _buildCompactLegendItem('B', totalE.toString(), Colors.grey),
            ],
          ),
        ],
      ),
    );
    if (isMobile) return averageCard;
    return Align(alignment: Alignment.topCenter, child: averageCard);
  }

  void _showFullScreenBranchComparison() {
    Map<String, List<Map<String, dynamic>>> branchGroups = {};
    for (var r in _examResults) {
      final bName = r['className'] ?? 'Bilinmeyen';
      branchGroups.putIfAbsent(bName, () => []).add(r);
    }
    final sortedBranches = branchGroups.keys.toList()..sort();

    List<String> columns = [];
    if (_averageSelectedSubjects.isNotEmpty) {
      columns = _averageSelectedSubjects;
    }

    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: EduknAppBar(
            title: 'Şube Karşılaştırma Listesi',
            leading: IconButton(
              icon: Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                  },
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _buildComparisonDataTable(
                      sortedBranches,
                      columns,
                      branchGroups,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComparisonDataTable(
    List<String> sortedBranches,
    List<String> columns,
    Map<String, List<Map<String, dynamic>>> branchGroups,
  ) {
    return DataTable(
      headingRowColor: WidgetStateProperty.all(Colors.grey.shade50),
      dataRowHeight: 40, // Reduced height
      headingRowHeight: 60, // Increase header height for subtitle
      columnSpacing: 24,
      columns: [
        DataColumn(
          label: Text(
            'Şube Adı',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
          ),
        ),
        ...columns.map(
          (subj) => DataColumn(
            label: Container(
              width: 100,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    subj,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  SizedBox(height: 2),
                  Text(
                    _averageType == 'Başarı Yüzdesi'
                        ? 'Başarı Yüzdesi'
                        : _averageType,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        DataColumn(
          label: Container(
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'GENEL ORT.',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade900,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  _averageType == 'Başarı Yüzdesi'
                      ? 'Başarı Yüzdesi'
                      : _averageType,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      rows: [
        ...sortedBranches.map((branchName) {
          final students = branchGroups[branchName]!;

          return DataRow(
            cells: [
              DataCell(
                Container(
                  constraints: BoxConstraints(maxWidth: 150),
                  child: Text(
                    branchName,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
              ...columns.map((subj) {
                double totalVal = 0;
                int validCount = 0;

                for (var s in students) {
                  if (s['subjects'] != null && s['subjects'] is Map) {
                    final sData = (s['subjects'] as Map)[subj];
                    if (sData != null && sData is Map) {
                      double val = 0;
                      if (_averageType == 'Net') {
                        val =
                            num.tryParse(
                              sData['net']?.toString() ?? '0',
                            )?.toDouble() ??
                            0.0;
                      } else if (_averageType == 'Başarı Yüzdesi') {
                        double c =
                            num.tryParse(
                              sData['correct']?.toString() ?? '0',
                            )?.toDouble() ??
                            0.0;
                        double w =
                            num.tryParse(
                              sData['wrong']?.toString() ?? '0',
                            )?.toDouble() ??
                            0.0;
                        double e =
                            num.tryParse(
                              sData['empty']?.toString() ?? '0',
                            )?.toDouble() ??
                            0.0;
                        double totalQ = c + w + e;
                        if (totalQ > 0) {
                          val = (c / totalQ) * 100;
                        }
                      } else {
                        val =
                            num.tryParse(
                              sData['net']?.toString() ?? '0',
                            )?.toDouble() ??
                            0.0;
                      }
                      totalVal += val;
                      validCount++;
                    }
                  }
                }

                double avg = validCount > 0 ? totalVal / students.length : 0.0;

                return DataCell(
                  Container(
                    alignment: Alignment.center,
                    child: Text(
                      avg.toStringAsFixed(2),
                      style: TextStyle(
                        color: _getAverageColor(avg, _averageType),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }),

              // GENERAL AVERAGE CELL
              DataCell(
                Builder(
                  builder: (c) {
                    double totalSum = 0;
                    for (var s in students) {
                      if (_averageType == 'Puan') {
                        totalSum +=
                            num.tryParse(
                              s['totalScore']?.toString() ?? '0',
                            )?.toDouble() ??
                            0.0;
                      } else if (_averageType == 'Net') {
                        totalSum +=
                            num.tryParse(
                              s['totalNet']?.toString() ?? '0',
                            )?.toDouble() ??
                            0.0;
                      } else {
                        double c = 0, w = 0, e = 0;
                        if (s['subjects'] != null) {
                          (s['subjects'] as Map).forEach((k, v) {
                            if (v is Map) {
                              c +=
                                  num.tryParse(
                                    v['correct']?.toString() ?? '0',
                                  )?.toDouble() ??
                                  0;
                              w +=
                                  num.tryParse(
                                    v['wrong']?.toString() ?? '0',
                                  )?.toDouble() ??
                                  0;
                              e +=
                                  num.tryParse(
                                    v['empty']?.toString() ?? '0',
                                  )?.toDouble() ??
                                  0;
                            }
                          });
                        }
                        double total = c + w + e;
                        if (total > 0) totalSum += (c / total) * 100;
                      }
                    }
                    double genAvg = students.isNotEmpty
                        ? totalSum / students.length
                        : 0;

                    return Container(
                      alignment: Alignment.center,
                      child: Text(
                        genAvg.toStringAsFixed(2),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Colors.indigo.shade900,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        }).toList(),
        // --- SCHOOL AVERAGE ROW ---
        DataRow(
          color: WidgetStateProperty.all(Colors.indigo.shade50),
          cells: [
            DataCell(
              Container(
                constraints: BoxConstraints(maxWidth: 150),
                child: Text(
                  'OKUL GENELİ',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: Colors.indigo.shade900,
                  ),
                ),
              ),
            ),
            ...columns.map((subj) {
              double totalVal = 0;
              int validCount = 0;
              for (var s in _examResults) {
                if (s['subjects'] != null && s['subjects'] is Map) {
                  final sData = (s['subjects'] as Map)[subj];
                  if (sData != null && sData is Map) {
                    double val = 0;
                    if (_averageType == 'Net') {
                      val =
                          num.tryParse(
                            sData['net']?.toString() ?? '0',
                          )?.toDouble() ??
                          0.0;
                    } else if (_averageType == 'Başarı Yüzdesi') {
                      double c =
                          num.tryParse(
                            sData['correct']?.toString() ?? '0',
                          )?.toDouble() ??
                          0.0;
                      double w =
                          num.tryParse(
                            sData['wrong']?.toString() ?? '0',
                          )?.toDouble() ??
                          0.0;
                      double e =
                          num.tryParse(
                            sData['empty']?.toString() ?? '0',
                          )?.toDouble() ??
                          0.0;
                      double totalQ = c + w + e;
                      if (totalQ > 0) {
                        val = (c / totalQ) * 100;
                      }
                    } else {
                      val =
                          num.tryParse(
                            sData['net']?.toString() ?? '0',
                          )?.toDouble() ??
                          0.0;
                    }
                    totalVal += val;
                    validCount++;
                  }
                }
              }

              double avg = validCount > 0
                  ? totalVal / _examResults.length
                  : 0.0;

              return DataCell(
                Container(
                  alignment: Alignment.center,
                  child: Text(
                    avg.toStringAsFixed(2),
                    style: TextStyle(
                      color: _getAverageColor(avg, _averageType),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              );
            }),
            DataCell(
              Builder(
                builder: (c) {
                  double totalSum = 0;
                  for (var s in _examResults) {
                    if (_averageType == 'Puan') {
                      totalSum +=
                          num.tryParse(
                            s['totalScore']?.toString() ?? '0',
                          )?.toDouble() ??
                          0.0;
                    } else if (_averageType == 'Net') {
                      totalSum +=
                          num.tryParse(
                            s['totalNet']?.toString() ?? '0',
                          )?.toDouble() ??
                          0.0;
                    } else {
                      double c = 0, w = 0, e = 0;
                      if (s['subjects'] != null) {
                        (s['subjects'] as Map).forEach((k, v) {
                          if (v is Map) {
                            c +=
                                num.tryParse(
                                  v['correct']?.toString() ?? '0',
                                )?.toDouble() ??
                                0;
                            w +=
                                num.tryParse(
                                  v['wrong']?.toString() ?? '0',
                                )?.toDouble() ??
                                0;
                            e +=
                                num.tryParse(
                                  v['empty']?.toString() ?? '0',
                                )?.toDouble() ??
                                0;
                          }
                        });
                      }
                      double total = c + w + e;
                      if (total > 0) totalSum += (c / total) * 100;
                    }
                  }
                  double genAvg = _examResults.isNotEmpty
                      ? totalSum / _examResults.length
                      : 0.0;

                  return Container(
                    alignment: Alignment.center,
                    child: Text(
                      genAvg.toStringAsFixed(2),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.indigo.shade900,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAverageTable({bool isMobile = false}) {
    Map<String, List<Map<String, dynamic>>> branchGroups = {};
    for (var r in _examResults) {
      final bName = r['className'] ?? 'Bilinmeyen';
      branchGroups.putIfAbsent(bName, () => []).add(r);
    }

    final sortedBranches = branchGroups.keys.toList()..sort();

    List<String> columns = [];
    if (_averageSelectedSubjects.isEmpty) {
      columns = [];
    } else {
      columns = _averageSelectedSubjects;
    }

    if (sortedBranches.isEmpty) {
      return Center(child: Text('Veri bulunamadı.'));
    }

    return Card(
      margin: EdgeInsets.only(
        left: isMobile ? 0 : 16,
      ), // Match _buildTopicAnalysisTable margin
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0), // Match padding
        child: Column(
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Şube Karşılaştırma Listesi',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16, // Match title size
                    color: Colors.indigo.shade900,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.fullscreen,
                    color: Colors.indigo,
                  ), // Match icon style
                  tooltip: 'Tam Ekran',
                  onPressed: _showFullScreenBranchComparison,
                ),
              ],
            ),
            Divider(),
            // Table
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                  },
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _buildComparisonDataTable(
                      sortedBranches,
                      columns,
                      branchGroups,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getAverageColor(double val, String type) {
    if (type == 'Başarı Yüzdesi') {
      if (val >= 85) return Colors.green.shade700;
      if (val >= 70) return Colors.blue.shade700;
      if (val >= 50) return Colors.orange.shade700;
      return Colors.red.shade700;
    }
    return Colors.black87;
  }

  /*
  Widget _buildAverageTab() {
    return Column(
      children: [
        // Top Filters
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Scope Dropdown
                  Expanded(
                    child: _buildDropdown(
                      label: 'Kapsam',
                      value: _averageScope,
                      items: ['Kurum', 'Şube'],
                      onChanged: (val) {
                        setState(() {
                          _averageScope = val!;
                          _averageSelectedBranchId = 'all';
                        });
                      },
                    ),
                  ),
                  SizedBox(width: 16),

                  // Branch Dropdown (only if Scope used is Branch)
                  if (_averageScope == 'Şube') ...[
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final branchNames = _examResults
                              .map((e) => e['className']?.toString())
                              .where((n) => n != null && n.isNotEmpty)
                              .map((n) => n!)
                              .toSet()
                              .toList();
                          branchNames.sort();

                          final dropdownItems = [
                            DropdownMenuItem<String>(
                              value: 'all',
                              child: Text('Tüm Şubeler'),
                            ),
                            ...branchNames.map(
                              (name) => DropdownMenuItem<String>(
                                value: name,
                                child: Text(name),
                              ),
                            ),
                          ];

                          return _buildDropdown(
                            label: 'Şube Seç',
                            value: _averageSelectedBranchId,
                            items: null,
                            dropdownItems: dropdownItems,
                            onChanged: (val) {
                              setState(() {
                                _averageSelectedBranchId = val!;
                              });
                            },
                          );
                        },
                      ),
                    ),
                    SizedBox(width: 16),
                  ],

                  // Average Type Dropdown
                  Expanded(
                    child: _buildDropdown(
                      label: 'Ortalama Tipi',
                      value: _averageType,
                      items: ['Başarı Yüzdesi', 'Puan', 'Net'],
                      onChanged: (val) {
                        setState(() {
                          _averageType = val!;
                        });
                      },
                    ),
                  ),

                  const SizedBox(width: 12),
                  // Actions Menu (3-dots)
                  _buildActionMenuButton(
                    tooltip: 'Ortalama İşlemleri',
                    onSelected: (val) {
                      if (val == 'yazdir' || val == 'pdf') {
                        _exportAveragePdf();
                      } else if (val == 'excel') {
                        _exportAverageExcel();
                      } else if (val == 'paylas') {
                        _showShareDialog(
                          title: 'Ortalamalar Raporu ($_averageType)',
                          reportType: 'Ortalama',
                          getPdfBytes: () => _buildAveragePdfBytes(),
                          pdfFileName: 'ortalamalar_${_selectedExam?.name ?? "sinav"}.pdf',
                          getExcelBytes: () => _buildAverageExcelBytes(),
                          excelFileName: 'ortalamalar_${_selectedExam?.name ?? "sinav"}.xlsx',
                          onSharePdf: () => _exportAveragePdf(shareOnly: true),
                          onShareExcel: () => _exportAverageExcel(shareOnly: false),
                        );
                      }
                    },
                    items: [
                      _buildPopupItem('yazdir', Icons.print_rounded, Colors.blue.shade700, 'Yazdır'),
                      _buildPopupItem('pdf', Icons.picture_as_pdf_rounded, Colors.red.shade700, 'PDF İndir'),
                      _buildPopupItem('excel', Icons.table_chart_rounded, Colors.green.shade700, 'Excel İndir'),
                      _buildPopupItem('paylas', Icons.share_rounded, Colors.indigo.shade700, 'Paylaş'),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        // Subject Chips & Content
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_availableSubjects.isNotEmpty) ...[
                  // Subject Filters
                  Container(
                    width: double.infinity,
                    margin: EdgeInsets.only(bottom: 24),
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                        },
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildLessonFilterChip(
                              label: 'Tümü',
                              isSelected:
                                  _averageSelectedSubjects.length ==
                                  _availableSubjects.length,
                              onSelected: (bool selected) {
                                setState(() {
                                  if (selected) {
                                    _averageSelectedSubjects = List.from(
                                      _availableSubjects,
                                    );
                                  } else {
                                    _averageSelectedSubjects = [];
                                  }
                                });
                              },
                            ),
                            Container(
                              height: 24,
                              width: 1,
                              color: Colors.grey.shade300,
                              margin: EdgeInsets.symmetric(horizontal: 12),
                            ),
                            ..._availableSubjects.map((subject) {
                              final isSelected = _averageSelectedSubjects
                                  .contains(subject);
                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: _buildLessonFilterChip(
                                  label: subject,
                                  isSelected: isSelected,
                                  onSelected: (bool selected) {
                                    setState(() {
                                      _averageSelectedSubjects = [subject];
                                    });
                                  },
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],

                // Comparison Table
                _buildAverageTable(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAverageTable() {
    // 1. Group Data by Branch
    Map<String, List<Map<String, dynamic>>> branchGroups = {};
    for (var r in _examResults) {
      final bName = r['className'] ?? 'Bilinmeyen';
      if (_averageScope == 'Şube' &&
          _averageSelectedBranchId != 'all' &&
          bName != _averageSelectedBranchId) {
        continue;
      }
      branchGroups.putIfAbsent(bName, () => []).add(r);
    }

    // Sort branches
    final sortedBranches = branchGroups.keys.toList()..sort();

    // Determine Columns (Subjects)
    List<String> columns = [];
    if (_averageSelectedSubjects.isEmpty) {
      columns = [];
    } else {
      columns = _averageSelectedSubjects;
    }

    if (sortedBranches.isEmpty) {
      return Center(child: Text('Veri bulunamadı.'));
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(Colors.grey.shade50),
          dataRowHeight: 60,
          columnSpacing: 24,
          columns: [
            DataColumn(
              label: Text(
                'Şube Adı',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
            ),
            // Dynamic Subject Columns
            ...columns.map(
              (subj) => DataColumn(
                label: Container(
                  width: 100,
                  alignment: Alignment.center,
                  child: Text(
                    subj,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ),
            // General Average Column (if multiple subjects)
            if (columns.length > 1)
              DataColumn(
                label: Text(
                  'GENEL ORT.',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade900,
                  ),
                ),
              ),
          ],
          rows: sortedBranches.map((branchName) {
            final students = branchGroups[branchName]!;

            return DataRow(
              cells: [
                DataCell(
                  Container(
                    constraints: BoxConstraints(maxWidth: 150),
                    child: Text(
                      branchName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                ...columns.map((subj) {
                  // Calculate Avg for this subject in this branch
                  double totalVal = 0;
                  int validCount = 0;

                  for (var s in students) {
                    if (s['subjects'] != null && s['subjects'] is Map) {
                      final sData = (s['subjects'] as Map)[subj];
                      if (sData != null && sData is Map) {
                        double val = 0;
                        if (_averageType == 'Net') {
                          val =
                              num.tryParse(
                                sData['net']?.toString() ?? '0',
                              )?.toDouble() ??
                              0.0;
                        } else if (_averageType == 'Başarı Yüzdesi') {
                          double c =
                              num.tryParse(
                                sData['correct']?.toString() ?? '0',
                              )?.toDouble() ??
                              0.0;
                          double w =
                              num.tryParse(
                                sData['wrong']?.toString() ?? '0',
                              )?.toDouble() ??
                              0.0;
                          double e =
                              num.tryParse(
                                sData['empty']?.toString() ?? '0',
                              )?.toDouble() ??
                              0.0;
                          double totalQ = c + w + e;
                          if (totalQ > 0) {
                            val = (c / totalQ) * 100;
                          }
                        } else {
                          // Puan -> fallback to Net for Subject Column
                          val =
                              num.tryParse(
                                sData['net']?.toString() ?? '0',
                              )?.toDouble() ??
                              0.0;
                        }
                        totalVal += val;
                        validCount++;
                      }
                    }
                  }

                  double avg = validCount > 0
                      ? totalVal / students.length
                      : 0.0;

                  return DataCell(
                    Container(
                      alignment: Alignment.center,
                      child: Text(
                        avg.toStringAsFixed(2),
                        style: TextStyle(
                          color: _getAverageColor(avg, _averageType),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }),

                // General Average
                if (columns.length > 1)
                  DataCell(
                    Builder(
                      builder: (c) {
                        double totalSum = 0;
                        for (var s in students) {
                          if (_averageType == 'Puan') {
                            totalSum +=
                                num.tryParse(
                                  s['totalScore']?.toString() ?? '0',
                                )?.toDouble() ??
                                0.0;
                          } else if (_averageType == 'Net') {
                            totalSum +=
                                num.tryParse(
                                  s['totalNet']?.toString() ?? '0',
                                )?.toDouble() ??
                                0.0;
                          } else {
                            // Success % General not implemented fully for now
                            totalSum += 0;
                          }
                        }
                        double genAvg = students.isNotEmpty
                            ? totalSum / students.length
                            : 0;

                        return Container(
                          alignment: Alignment.center,
                          child: Text(
                            _averageType == 'Başarı Yüzdesi'
                                ? '-'
                                : genAvg.toStringAsFixed(2),
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Colors.black87,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Color _getAverageColor(double val, String type) {
    if (type == 'Başarı Yüzdesi') {
      if (val >= 85) return Colors.green.shade700;
      if (val >= 70) return Colors.blue.shade700;
      if (val >= 50) return Colors.orange.shade700;
      return Colors.red.shade700;
    }
    return Colors.black87;
  }

*/
  /* // --- PDF Export ---
  Future<void> _generateAndPrintPDF_OLD() async {
    final pdf = pw.Document();

    // Sort data same as list
    _filterResults();
    final data = _filteredResults;
    final subjects = _availableSubjects;

    // Font
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text(
                _selectedExam?.name ?? 'Sınav Sonuçları',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                // Header Row 1: Subjects
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Container(
                      padding: pw.EdgeInsets.all(4),
                      child: pw.Text(
                        '#',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.Container(
                      padding: pw.EdgeInsets.all(4),
                      child: pw.Text(
                        'Ad Soyad',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.Container(
                      padding: pw.EdgeInsets.all(4),
                      child: pw.Text(
                        'Sınıf',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    for (var subj in subjects)
                      pw.Container(
                        padding: pw.EdgeInsets.all(4),
                        alignment: pw.Alignment.center,
                        color: PdfColors.grey300,
                        child: pw.Text(
                          subj,
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    pw.Container(
                      padding: pw.EdgeInsets.all(4),
                      child: pw.Text(
                        'Toplam',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.Container(
                      padding: pw.EdgeInsets.all(4),
                      child: pw.Text(
                        'Sıralama',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                // Header Row 2: D/Y/B/N Detail
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    pw.SizedBox(), // Rank
                    pw.SizedBox(), // Name
                    pw.SizedBox(), // Class
                    for (var _ in subjects)
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                        children: [
                          pw.Text(
                            'D',
                            style: pw.TextStyle(
                              fontSize: 8,
                              color: PdfColors.green,
                            ),
                          ),
                          pw.Text(
                            'Y',
                            style: pw.TextStyle(
                              fontSize: 8,
                              color: PdfColors.red,
                            ),
                          ),
                          pw.Text(
                            'B',
                            style: pw.TextStyle(
                              fontSize: 8,
                              color: PdfColors.grey,
                            ),
                          ),
                          pw.Text(
                            'N',
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                      children: [
                        pw.Text('D', style: pw.TextStyle(fontSize: 8)),
                        pw.Text('Y', style: pw.TextStyle(fontSize: 8)),
                        pw.Text('B', style: pw.TextStyle(fontSize: 8)),
                        pw.Text(
                          'Net',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          'Puan',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                      children: [
                        pw.Text('Genel', style: pw.TextStyle(fontSize: 8)),
                        pw.Text('Kurum', style: pw.TextStyle(fontSize: 8)),
                        pw.Text('Şube', style: pw.TextStyle(fontSize: 8)),
                      ],
                    ),
                  ],
                ),
                // Data Rows
                ...List.generate(data.length, (index) {
                  final item = data[index];
                  final bgColor = index % 2 == 0
                      ? PdfColors.white
                      : PdfColors.grey50;

                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: bgColor),
                    children: [
                      pw.Container(
                        padding: pw.EdgeInsets.all(4),
                        child: pw.Text(
                          '${index + 1}',
                          style: pw.TextStyle(fontSize: 9),
                        ),
                      ),
                      pw.Container(
                        padding: pw.EdgeInsets.all(4),
                        child: pw.Text(
                          item['studentName'] ?? '-',
                          style: pw.TextStyle(fontSize: 9),
                        ),
                      ),
                      pw.Container(
                        padding: pw.EdgeInsets.all(4),
                        child: pw.Text(
                          item['className'] ?? '-',
                          style: pw.TextStyle(fontSize: 9),
                        ),
                      ),

                      // Subjects
                      for (var subj in subjects)
                        _buildPdfSubjectCell(item, subj),

                      // Total
                      _buildPdfTotalCell(item),

                      // Ranks
                      _buildPdfRankCell(item),
                    ],
                  );
                }),
              ],
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
    );
  } */

  /* // --- PDF Export (Disabled) ---
  Future<void> _generateAndPrintPDF_Old() async {
    // 1. Prepare Data
    _filterResults();
    final data = _filteredResults;
    final subjects = _availableSubjects;
    final examName = _selectedExam?.name ?? 'Sınav Sonuçları';
    final dateStr = DateFormat('dd.MM.yyyy').format(DateTime.now());

    // 2. Load Fonts (Robust)
    pw.Font font;
    pw.Font fontBold;
    try {
      font = await PdfGoogleFonts.robotoRegular();
      fontBold = await PdfGoogleFonts.robotoBold();
    } catch (e) {
      debugPrint('Error loading fonts: $e');
      font = pw.Font.helvetica();
      fontBold = pw.Font.helveticaBold();
    }

    // 3. Calculate Averages
    Map<String, double> subjectNetSums = {};
    for (var subj in subjects) subjectNetSums[subj] = 0;
    double totalNetSum = 0;

    for (var item in data) {
      if (item['subjects'] != null && item['subjects'] is Map) {
        final sMap = item['subjects'] as Map;
        for (var subj in subjects) {
          if (sMap.containsKey(subj)) {
            double n =
                double.tryParse(sMap[subj]['net']?.toString() ?? '0') ?? 0;
            subjectNetSums[subj] = (subjectNetSums[subj] ?? 0) + n;
          }
        }
      }
      totalNetSum += double.tryParse(item['totalNet']?.toString() ?? '0') ?? 0;
    }

    final pdf = pw.Document();

    // Colors - Blue/Cyan Theme
    final List<PdfColor> subjectColors = [
      PdfColors.blue50,
      PdfColors.cyan50,
      PdfColors.indigo50,
      PdfColors.lightBlue50,
      PdfColors.teal50,
    ];
    final headerColor = PdfColors.cyan100;
    final borderColor = PdfColors.blue900;
    final rowEvenColor = PdfColors.white;
    final rowOddColor = PdfColors.blue50;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        margin: pw.EdgeInsets.all(10), // Reduced margin for more space
        build: (pw.Context context) {
          return [
            // --- Header Section ---
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: borderColor, width: 1),
              ),
              child: pw.Row(
                crossAxisAlignment:
                    pw.CrossAxisAlignment.center, // Align center vertically
                children: [
                  // Date Box
                  pw.Container(
                    width: 80,
                    padding: pw.EdgeInsets.all(4),
                    child: pw.Column(
                      mainAxisSize: pw.MainAxisSize.min,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          'Sınav Tarihi',
                          style: pw.TextStyle(
                            fontSize: 8,
                            color: PdfColors.grey700,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          dateStr,
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Vertical Line
                  pw.Container(width: 1, height: 40, color: PdfColors.blue800),
                  // Title Box
                  pw.Expanded(
                    child: pw.Column(
                      children: [
                        pw.Container(
                          width: double.infinity,
                          color: PdfColors.blue100,
                          padding: pw.EdgeInsets.symmetric(vertical: 4),
                          alignment: pw.Alignment.center,
                          child: pw.Text(
                            'ABC OKULLARI',
                            style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue900,
                            ),
                          ),
                        ),
                        pw.Container(
                          width: double.infinity,
                          color: PdfColors.green100,
                          padding: pw.EdgeInsets.symmetric(vertical: 4),
                          alignment: pw.Alignment.center,
                          child: pw.Text(
                            examName,
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.green900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Vertical Line
                  pw.Container(width: 1, height: 40, color: PdfColors.blue800),
                  // Logo Box Placeholder
                  pw.Container(
                    width: 80,
                    padding: pw.EdgeInsets.all(4),
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      'LOGO',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 5),

            // --- Averages Row ---
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: borderColor, width: 1.5),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    flex: 3,
                    child: pw.Container(
                      padding: pw.EdgeInsets.all(4),
                      alignment: pw.Alignment.center,
                      child: pw.Text(
                        'Genel Toplam ve Ortalamalar',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 8,
                          color: PdfColors.blue900,
                        ),
                      ),
                    ),
                  ),
                  // Subject Averages
                  ...List.generate(subjects.length, (i) {
                    String subj = subjects[i];
                    double avg = data.isNotEmpty
                        ? (subjectNetSums[subj]! / data.length)
                        : 0;
                    return pw.Expanded(
                      flex: 2,
                      child: pw.Container(
                        decoration: pw.BoxDecoration(
                          border: pw.Border(
                            left: pw.BorderSide(color: borderColor),
                          ),
                        ),
                        child: pw.Column(
                          children: [
                            pw.Container(
                              padding: pw.EdgeInsets.all(2),
                              width: double.infinity,
                              color: subjectColors[i % subjectColors.length],
                              alignment: pw.Alignment.center,
                              child: pw.Text(
                                subj,
                                maxLines: 1,
                                overflow: pw.TextOverflow.clip,
                                style: pw.TextStyle(
                                  fontSize: 6,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.blue900,
                                ),
                              ),
                            ),
                            pw.Divider(height: 1, color: borderColor),
                            pw.Container(
                              padding: pw.EdgeInsets.all(2),
                              child: pw.Text(
                                avg.toStringAsFixed(2),
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                  // Total Avg
                  pw.Expanded(
                    flex: 2,
                    child: pw.Container(
                      decoration: pw.BoxDecoration(
                        border: pw.Border(
                          left: pw.BorderSide(color: PdfColors.orange),
                        ),
                      ),
                      child: pw.Column(
                        children: [
                          pw.Container(
                            padding: pw.EdgeInsets.all(2),
                            child: pw.Text(
                              'NET',
                              style: pw.TextStyle(
                                fontSize: 6,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.Divider(height: 1, color: PdfColors.orange),
                          pw.Container(
                            padding: pw.EdgeInsets.all(2),
                            child: pw.Text(
                              data.isNotEmpty
                                  ? (totalNetSum / data.length).toStringAsFixed(
                                      2,
                                    )
                                  : '0.00',
                              style: pw.TextStyle(
                                fontSize: 8,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Stats Counts
                  pw.Expanded(
                    flex: 3,
                    child: pw.Container(
                      decoration: pw.BoxDecoration(
                        border: pw.Border(
                          left: pw.BorderSide(color: PdfColors.orange),
                        ),
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStatBox('GENEL', '${data.length}'),
                          _buildStatBox('ŞUBE', '${data.length}'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 5),

            // --- Main Table ---
            pw.Table(
              border: pw.TableBorder.all(
                color: PdfColors.blueGrey300,
                width: 0.5,
              ),
              columnWidths: {
                0: pw.FixedColumnWidth(20), // #
                1: pw.FixedColumnWidth(80), // Name
                2: pw.FixedColumnWidth(30), // Class
                // Auto for subjects (flex based implicit)
              },
              children: [
                // Header 1: Subjects
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColors.blue50),
                  children: [
                    pw.Container(), pw.Container(), pw.Container(), // Spacer
                    for (int i = 0; i < subjects.length; i++)
                      pw.Container(
                        padding: pw.EdgeInsets.all(2),
                        alignment: pw.Alignment.center,
                        color: subjectColors[i % subjectColors.length],
                        child: pw.Text(
                          subjects[i],
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 7,
                            color: PdfColors.black,
                          ),
                        ),
                      ),
                    pw.Container(
                      color: headerColor,
                      child: pw.Center(
                        child: pw.Text(
                          'TOPLAM',
                          style: pw.TextStyle(
                            fontSize: 7,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue900,
                          ),
                        ),
                      ),
                    ),
                    pw.Container(
                      child: pw.Center(
                        child: pw.Text(
                          'SIRALAMA',
                          style: pw.TextStyle(
                            fontSize: 7,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // Header 2: D Y B N
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    pw.Padding(
                      padding: pw.EdgeInsets.all(2),
                      child: pw.Text(
                        'No',
                        style: pw.TextStyle(
                          fontSize: 6,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: pw.EdgeInsets.all(2),
                      child: pw.Text(
                        'Ad Soyad',
                        style: pw.TextStyle(
                          fontSize: 6,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: pw.EdgeInsets.all(2),
                      child: pw.Text(
                        'Sınıf',
                        style: pw.TextStyle(
                          fontSize: 6,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    for (var _ in subjects)
                      pw.Container(
                        padding: pw.EdgeInsets.symmetric(horizontal: 1),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                          children: [
                            pw.Text(
                              'D',
                              style: pw.TextStyle(
                                fontSize: 5,
                                color: PdfColors.green800,
                              ),
                            ),
                            pw.Text(
                              'Y',
                              style: pw.TextStyle(
                                fontSize: 5,
                                color: PdfColors.red800,
                              ),
                            ),
                            pw.Text(
                              'B',
                              style: pw.TextStyle(
                                fontSize: 5,
                                color: PdfColors.grey700,
                              ),
                            ),
                            pw.Text(
                              'N',
                              style: pw.TextStyle(
                                fontSize: 5,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    pw.Row(
                      // Total Column
                      mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                      children: [
                        pw.Text(
                          'Net',
                          style: pw.TextStyle(
                            fontSize: 5,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          'Puan',
                          style: pw.TextStyle(
                            fontSize: 5,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    pw.Row(
                      // Rank Column
                      mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                      children: [
                        pw.Text('Genel', style: pw.TextStyle(fontSize: 5)),
                        pw.Text('Kurum', style: pw.TextStyle(fontSize: 5)),
                        pw.Text('Şube', style: pw.TextStyle(fontSize: 5)),
                      ],
                    ),
                  ],
                ),
                // --- Data Rows ---
                ...List.generate(data.length, (index) {
                  final item = data[index];
                  final rowColor = index % 2 == 0 ? rowEvenColor : rowOddColor;
                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: rowColor),
                    verticalAlignment: pw.TableCellVerticalAlignment.middle,
                    children: [
                      pw.Container(
                        padding: pw.EdgeInsets.all(2),
                        child: pw.Text(
                          '${index + 1}',
                          style: pw.TextStyle(fontSize: 6),
                        ),
                      ),
                      pw.Container(
                        padding: pw.EdgeInsets.all(2),
                        child: pw.Text(
                          item['studentName'] ?? '',
                          style: pw.TextStyle(fontSize: 6),
                        ),
                      ),
                      pw.Container(
                        padding: pw.EdgeInsets.all(2),
                        child: pw.Text(
                          item['className'] ?? '',
                          style: pw.TextStyle(fontSize: 6),
                        ),
                      ),
                      // Subjects
                      for (var subj in subjects)
                        _buildPdfSubjectCell(item, subj),
                      // Total
                      _buildPdfTotalCell(item),
                      // Rank
                      _buildPdfRankCell(item),
                    ],
                  );
                }),
              ],
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  } */

  // ===========================================================================
  // KARNE / SONUÇ BELGESİ İŞLEMLERİ (Kurum Karnesi ve Öğrenci Karneleri)
  // ===========================================================================

  StudentResult _mapToStudentResult(Map<String, dynamic> r) {
    if (r['raw'] != null && r['raw'] is Map) {
      try {
        final sr = StudentResult.fromJson(Map<String, dynamic>.from(r['raw']));
        sr.rankGeneral = r['rankGeneral'] ?? sr.rankGeneral;
        sr.rankInstitution = r['rankInstitution'] ?? r['rankGeneral'] ?? sr.rankInstitution;
        sr.rankBranch = r['rankBranch'] ?? sr.rankBranch;
        if (sr.score == 0.0 && r['totalScore'] != null) {
          sr.score = num.tryParse(r['totalScore'].toString())?.toDouble() ?? 0.0;
        }
        if (sr.correctAnswers.isEmpty && _selectedExam != null) {
          final b = sr.booklet.isNotEmpty ? sr.booklet : 'A';
          if (_selectedExam!.answerKeys.containsKey(b)) {
            sr.correctAnswers = Map<String, String>.from(_selectedExam!.answerKeys[b]!);
          }
        }
        return sr;
      } catch (e) {
        debugPrint('Error decoding raw student result: $e');
      }
    }

    final answers = (r['answers'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
        (r['cevaplar'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
        <String, String>{};

    final booklet = (r['booklet'] ?? 'A').toString();
    Map<String, String> correctAnswers = {};
    if (r['correctAnswers'] != null && r['correctAnswers'] is Map) {
      correctAnswers = (r['correctAnswers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
    } else if (_selectedExam != null && _selectedExam!.answerKeys.containsKey(booklet)) {
      correctAnswers = Map<String, String>.from(_selectedExam!.answerKeys[booklet]!);
    } else if (_selectedExam != null && _selectedExam!.answerKeys.isNotEmpty) {
      correctAnswers = Map<String, String>.from(_selectedExam!.answerKeys.values.first);
    }

    final Map<String, SubjectStats> subjectStats = {};
    if (r['subjects'] != null && r['subjects'] is Map) {
      (r['subjects'] as Map).forEach((k, v) {
        if (v is Map) {
          subjectStats[k.toString()] = SubjectStats(
            correct: int.tryParse(v['correct']?.toString() ?? '0') ?? 0,
            wrong: int.tryParse(v['wrong']?.toString() ?? '0') ?? 0,
            empty: int.tryParse(v['empty']?.toString() ?? '0') ?? 0,
            net: num.tryParse(v['net']?.toString() ?? '0')?.toDouble() ?? 0.0,
          );
        }
      });
    }

    return StudentResult(
      tcNo: (r['tcNo'] ?? '').toString(),
      studentNo: (r['studentNo'] ??
              r['studentNumber'] ??
              r['no'] ??
              r['number'] ??
              (r['raw'] is Map
                  ? (r['raw']['studentNo'] ??
                      r['raw']['studentNumber'] ??
                      r['raw']['no'] ??
                      r['raw']['number'])
                  : null) ??
              '')
          .toString()
          .trim(),
      name: (r['studentName'] ?? r['name'] ?? '').toString(),
      classLevel: _selectedExam?.classLevel ?? '',
      branch: (r['className'] ?? r['branch'] ?? '').toString(),
      booklet: booklet,
      score: num.tryParse(r['totalScore']?.toString() ?? '0')?.toDouble() ?? 0.0,
      rankGeneral: r['rankGeneral'] ?? 0,
      rankInstitution: r['rankInstitution'] ?? r['rankGeneral'] ?? 0,
      rankBranch: r['rankBranch'] ?? 0,
      answers: answers,
      correctAnswers: correctAnswers,
      subjects: subjectStats,
    );
  }

  Widget _buildPdfLoadingDialog(String message, {String? subtitle}) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                shape: BoxShape.circle,
              ),
              child: const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            if (subtitle != null && subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<Uint8List> _buildInstitutionalReportCardBytes() async {
    final instName = (_schoolTypeName != null && _schoolTypeName!.isNotEmpty)
        ? _schoolTypeName!
        : 'Eğitim Kurumu';

    return await ExamReportCardService().generateInstitutionalReportCardPdf(
      examName: _selectedExam!.name,
      examDate: _selectedExam!.date,
      classLevel: _selectedExam!.classLevel,
      institutionName: instName,
      examResults: _examResults,
      availableSubjects: _availableSubjects,
    );
  }

  Future<void> _printInstitutionalReportCard({bool shareOnly = false}) async {
    if (_selectedExam == null || _examResults.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yazdırılacak sınav sonucu bulunamadı.')),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => _buildPdfLoadingDialog(
        "Kurum Karnesi Hazırlanıyor",
        subtitle: "Kurum geneli ve şube başarı sayfaları oluşturuluyor, lütfen bekleyiniz...",
      ),
    );

    try {
      await Future.delayed(const Duration(milliseconds: 150));
      final pdfBytes = await _buildInstitutionalReportCardBytes();

      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (shareOnly) {
        await Printing.sharePdf(
          bytes: pdfBytes,
          filename: sanitizeFileName('kurum_karnesi_${_selectedExam!.name}.pdf'),
        );
      } else {
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdfBytes,
          name: sanitizeFileName('kurum_karnesi_${_selectedExam!.name}.pdf'),
        );
      }
    } catch (e) {
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kurum karnesi oluşturulurken hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _printStudentReportCards({
    String? branchFilter,
    String? studentIdFilter,
  }) async {
    if (_selectedExam == null || _examResults.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yazdırılacak öğrenci verisi bulunamadı.')),
      );
      return;
    }

    List<Map<String, dynamic>> targetList = List.from(_examResults);

    if (studentIdFilter != null && studentIdFilter != 'all') {
      targetList = targetList.where((r) => _getStudentId(r) == studentIdFilter).toList();
    } else if (branchFilter != null && branchFilter != 'all') {
      targetList = targetList.where((r) => (r['className'] ?? r['branch']) == branchFilter).toList();
    }

    if (targetList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seçili kritere uygun öğrenci bulunamadı.')),
      );
      return;
    }

    // Birden fazla karne varsa sıralama biçimini sor
    if (targetList.length > 1) {
      final sortMode = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Karne Sıralaması'),
          content: const Text(
            'Karneler nasıl sıralansın?\n\n'
            '• Puan Sıralı: Puanı yüksekten düşüğe\n'
            '• Şube Sıralı: Önce şube, her şubenin içinde isme göre (dağıtım için)',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'score'),
              icon: const Icon(Icons.trending_down),
              label: const Text('Puan Sıralı'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'branch'),
              icon: const Icon(Icons.sort_by_alpha),
              label: const Text('Şube Sıralı'),
            ),
          ],
        ),
      );
      if (sortMode == null) return; // İptal
      if (!mounted) return;

      String trKey(String s) => s
          .replaceAll('İ', 'i')
          .replaceAll('I', 'ı')
          .toLowerCase()
          .replaceAll('ç', 'c~')
          .replaceAll('ğ', 'g~')
          .replaceAll('ı', 'h~')
          .replaceAll('ö', 'o~')
          .replaceAll('ş', 's~')
          .replaceAll('ü', 'u~');
      String nameOf(Map<String, dynamic> r) =>
          (r['studentName'] ?? r['name'] ?? '').toString().trim();
      double scoreOf(Map<String, dynamic> r) =>
          num.tryParse((r['totalScore'] ?? r['score'] ?? '0').toString())?.toDouble() ?? 0.0;
      String branchOf(Map<String, dynamic> r) =>
          (r['className'] ?? r['branch'] ?? '').toString();

      if (sortMode == 'score') {
        targetList.sort((a, b) {
          final c = scoreOf(b).compareTo(scoreOf(a));
          return c != 0 ? c : trKey(nameOf(a)).compareTo(trKey(nameOf(b)));
        });
      } else {
        targetList.sort((a, b) {
          final bc = trKey(branchOf(a)).compareTo(trKey(branchOf(b)));
          return bc != 0 ? bc : trKey(nameOf(a)).compareTo(trKey(nameOf(b)));
        });
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => _buildPdfLoadingDialog(
        "Öğrenci Karneleri Hazırlanıyor",
        subtitle: "${targetList.length} öğrencinin karne sayfası oluşturuluyor, lütfen bekleyiniz...",
      ),
    );

    try {
      await Future.delayed(const Duration(milliseconds: 150));
      final instName = _getEffectiveSchoolTypeName();

      final Map<String, int> branchCounts = {};
      for (var r in _examResults) {
        final b = (r['className'] ?? r['branch'] ?? '').toString();
        branchCounts[b] = (branchCounts[b] ?? 0) + 1;
      }

      final studentResults = targetList.map((m) => _mapToStudentResult(m)).toList();

      final pdfBytes = await ExamReportCardService().generateStudentReportCardsPdf(
        students: studentResults,
        examName: _selectedExam!.name,
        examDate: _selectedExam!.date,
        institutionName: instName,
        subjects: _availableSubjects,
        outcomes: _selectedExam!.outcomes,
        totalStudents: _examResults.length,
        schoolStudents: _examResults.length,
        branchStudentCounts: branchCounts,
        isRankingVisible: _selectedExam!.sharingSettings['isRankingVisible'] ?? true,
      );

      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: 'ogrenci_karneleri_${_selectedExam!.name}.pdf',
      );
    } catch (e) {
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Karne oluşturulurken hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _openStudentReportCardDialog(String studentId) {
    final found = _examResults.firstWhere(
      (r) => _getStudentId(r) == studentId,
      orElse: () => {},
    );
    if (found.isEmpty) return;

    final student = _mapToStudentResult(found);
    final branchCount = _examResults.where((r) => r['className'] == found['className']).length;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentReportCardDialog(
          student: student,
          examName: _selectedExam!.name,
          subjects: _availableSubjects,
          outcomes: _selectedExam!.outcomes,
          totalStudents: _examResults.length,
          schoolStudents: _examResults.length,
          branchStudents: branchCount,
          isRankingVisible: _selectedExam!.sharingSettings['isRankingVisible'] ?? true,
          trialExamId: _selectedExam!.id,
          schoolTypeName: _getEffectiveSchoolTypeName(),
        ),
      ),
    );
  }

  // --- Main PDF Entry Point ---
  Future<void> _generateAndPrintPDF({bool shareOnly = false}) async {
    // Show Loading Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text("PDF Hazırlanıyor, lütfen bekleyiniz..."),
              ],
            ),
          ),
        );
      },
    );

    try {
      // Small delay to allow UI to render dialog
      await Future.delayed(Duration(milliseconds: 100));

      // Determine mode
      bool isBranchMode = _listScope == 'Şube';
      if (isBranchMode) {
        // If a specific branch is selected (not 'all'), generate only for that branch
        if (_selectedBranchId != null && _selectedBranchId != 'all') {
          await _generatePdfByBranch(singleBranchId: _selectedBranchId, shareOnly: shareOnly);
        } else {
          await _generatePdfByBranch(
            singleBranchId: null,
            shareOnly: shareOnly,
          ); // All branches, separated
        }
      } else {
        await _generatePdfGlobal(shareOnly: shareOnly);
      }
    } catch (e) {
      debugPrint('PDF Error: $e');
      if (mounted) ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF oluşturulurken hata: $e')));
    } finally {
      // Close Loading Dialog
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  // --- PDF: Global (Kurum) Mode ---
  Future<Uint8List> _buildPdfGlobalBytes() async {
    _filterResults(); // Ensures _filteredResults reflects current UI filter (if any)

    final data = _filteredResults;
    final subjects = _availableSubjects;
    final examName = _selectedExam?.name ?? 'Sınav Sonuçları';
    final dateStr = DateFormat('dd.MM.yyyy').format(DateTime.now());

    final font = await _loadPdfFont();
    final fontBold = await _loadPdfFontBold();

    final globalRankMap = _calculateGlobalRanks();
    final branchRankMap = _calculateBranchRanks();
    final allResults = _examResults;

    final columnWidths = _buildColumnWidths(subjects);
    final summaryBlock = _buildPdfSummaryBlock(
      data,
      allResults,
      subjects,
      columnWidths,
      "Genel Toplam ve Ortalamalar",
    );

    String titleType = _listSort == 'Puan Sıralı'
        ? 'LGS PUAN SIRALI'
        : 'NET SIRALI';
    String fullTitle = '$titleType GENEL LİSTE';

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        margin: const pw.EdgeInsets.all(12),
        header: (context) {
          return pw.Column(
            children: [
              _buildPdfTitleSection(examName, dateStr, fullTitle),
              if (context.pageNumber > 1) ...[
                pw.SizedBox(height: 5),
                _buildPdfHeaderRow(
                  subjects,
                  _getSubjectColors(),
                  PdfColors.cyan100,
                  PdfColors.blue900,
                  columnWidths,
                ),
              ],
            ],
          );
        },
        build: (context) {
          return [
            pw.SizedBox(height: 10),
            summaryBlock,
            pw.SizedBox(height: 5),
            _buildPdfHeaderRow(
              subjects,
              _getSubjectColors(),
              PdfColors.cyan100,
              PdfColors.blue900,
              columnWidths,
            ),
            _buildPdfDataRows(
              data,
              subjects,
              globalRankMap,
              branchRankMap,
              isGrouped: false,
              columnWidths: columnWidths,
            ),
          ];
        },
      ),
    );

    return await pdf.save();
  }

  Future<void> _generatePdfGlobal({bool shareOnly = false}) async {
    final bytes = await _buildPdfGlobalBytes();
    if (shareOnly) {
      await Printing.sharePdf(
        bytes: bytes,
        filename: sanitizeFileName('sinav_sonuclari_${_selectedExam?.name ?? ""}.pdf'),
      );
    } else {
      await Printing.layoutPdf(onLayout: (format) => bytes);
    }
  }

  // --- PDF: Branch (Şube) Mode ---
  Future<Uint8List> _buildPdfByBranchBytes({String? singleBranchId}) async {
    final data = _filteredResults;
    final subjects = _availableSubjects;
    final examName = _selectedExam?.name ?? 'Sınav Sonuçları';
    final dateStr = DateFormat('dd.MM.yyyy').format(DateTime.now());

    final font = await _loadPdfFont();
    final fontBold = await _loadPdfFontBold();

    final globalRankMap = _calculateGlobalRanks();
    final branchRankMap = _calculateBranchRanks();

    final columnWidths = _buildColumnWidths(subjects);

    Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var item in data) {
      String b = item['className'] ?? 'Misafir';
      grouped.putIfAbsent(b, () => []).add(item);
    }

    var sortedBranches = grouped.keys.toList()..sort();

    final pdf = pw.Document();

    for (var bName in sortedBranches) {
      var bData = grouped[bName]!;
      final sortKey = _listSort == 'Puan Sıralı' ? 'totalScore' : 'totalNet';
      bData.sort((a, b) {
        double valA = double.tryParse(a[sortKey]?.toString() ?? '0') ?? 0;
        double valB = double.tryParse(b[sortKey]?.toString() ?? '0') ?? 0;
        if (valA == valB) {
          return (a['studentName'] ?? '').compareTo(b['studentName'] ?? '');
        }
        return valB.compareTo(valA);
      });

      final summaryBlock = _buildPdfSummaryBlock(
        _examResults,
        _examResults,
        subjects,
        columnWidths,
        "Genel Toplam ve Ortalamalar",
        secondaryData: bData,
        secondaryTitle: "Şube Toplam ve Ortalamalar",
      );

      String titleType = _listSort == 'Puan Sıralı'
          ? 'LGS PUAN SIRALI'
          : 'NET SIRALI';
      String fullTitle = '$titleType $bName ŞUBE LİSTESİ';

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          theme: pw.ThemeData.withFont(base: font, bold: fontBold),
          margin: const pw.EdgeInsets.all(12),
          header: (context) {
            return pw.Column(
              children: [_buildPdfTitleSection(examName, dateStr, fullTitle)],
            );
          },
          build: (context) {
            return [
              pw.SizedBox(height: 10),
              summaryBlock,
              pw.SizedBox(height: 5),
              _buildPdfHeaderRow(
                subjects,
                _getSubjectColors(),
                PdfColors.cyan100,
                PdfColors.blue900,
                columnWidths,
              ),
              _buildPdfDataRows(
                bData,
                subjects,
                globalRankMap,
                branchRankMap,
                isGrouped: true,
                columnWidths: columnWidths,
              ),
            ];
          },
        ),
      );
    }

    return await pdf.save();
  }

  Future<void> _generatePdfByBranch({String? singleBranchId, bool shareOnly = false}) async {
    final bytes = await _buildPdfByBranchBytes(singleBranchId: singleBranchId);
    if (shareOnly) {
      await Printing.sharePdf(
        bytes: bytes,
        filename: sanitizeFileName('sube_sonuclari_${_selectedExam?.name ?? ""}.pdf'),
      );
    } else {
      await Printing.layoutPdf(onLayout: (format) => bytes);
    }
  }

  Future<Uint8List> _getExamResultsPdfBytes() async {
    bool isBranchMode = _listScope == 'Şube';
    if (isBranchMode) {
      if (_selectedBranchId != null && _selectedBranchId != 'all') {
        return await _buildPdfByBranchBytes(singleBranchId: _selectedBranchId);
      } else {
        return await _buildPdfByBranchBytes(singleBranchId: null);
      }
    } else {
      return await _buildPdfGlobalBytes();
    }
  }

  // --- Column Widths Helper ---
  Map<int, pw.TableColumnWidth> _buildColumnWidths(List<String> subjects) {
    // A4 Landscape ~842. Margins 24.
    // Updated widths for better spacing and fit.
    final Map<int, pw.TableColumnWidth> widths = {
      0: pw.FixedColumnWidth(25), // #
      1: pw.FixedColumnWidth(90), // Name
      2: pw.FixedColumnWidth(35), // Class
      // Subj: 65
      // Total: 60
      // Ranks: 60
    };

    int index = 3;
    for (var _ in subjects) {
      widths[index++] = pw.FixedColumnWidth(65);
    }
    widths[index++] = pw.FixedColumnWidth(55); // Net/Puan
    widths[index++] = pw.FixedColumnWidth(65); // Ranks (G/K/S)

    return widths;
  }

  // --- Helpers ---

  Future<pw.Font> _loadPdfFont() async {
    try {
      return await PdfGoogleFonts.robotoRegular();
    } catch (_) {
      return pw.Font.helvetica();
    }
  }

  Future<pw.Font> _loadPdfFontBold() async {
    try {
      return await PdfGoogleFonts.robotoBold();
    } catch (_) {
      return pw.Font.helveticaBold();
    }
  }

  List<PdfColor> _getSubjectColors() {
    return [
      PdfColors.blue50,
      PdfColors.cyan50,
      PdfColors.indigo50,
      PdfColors.lightBlue50,
      PdfColors.teal50,
      PdfColors.purple50,
      PdfColors.orange50,
    ];
  }

  Map<String, int> _calculateGlobalRanks() {
    final sortKey = _listSort == 'Puan Sıralı' ? 'totalScore' : 'totalNet';
    List<Map<String, dynamic>> allSorted = List.from(_examResults);
    allSorted.sort((a, b) {
      double valA = double.tryParse(a[sortKey]?.toString() ?? '0') ?? 0;
      double valB = double.tryParse(b[sortKey]?.toString() ?? '0') ?? 0;
      if (valA == valB)
        return (a['studentName'] ?? '').compareTo(b['studentName'] ?? '');
      return valB.compareTo(valA);
    });

    Map<String, int> rankMap = {};
    int currentRank = 0;
    double? prevVal;
    for (int i = 0; i < allSorted.length; i++) {
      final v = double.tryParse(allSorted[i][sortKey]?.toString() ?? '0') ?? 0;
      if (prevVal == null || (v - prevVal).abs() >= 0.001) {
        currentRank++;
        prevVal = v;
      }
      rankMap[_getStudentId(allSorted[i])] = currentRank;
    }
    return rankMap;
  }

  String _getStudentId(Map<String, dynamic> item) {
    if (item['studentNumber'] != null &&
        item['studentNumber'].toString().isNotEmpty) {
      return item['studentNumber'].toString();
    }
    return '${item['studentName']}_${item['className']}';
  }

  // --- Components ---

  // Refined Title Section: [Date] [Center Info] [Logo]
  pw.Widget _buildPdfTitleSection(
    String examName,
    String dateStr,
    String subTitle,
  ) {
    final schoolIconSvg = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M12 3L1 9L12 15L21 10.09V17H23V9M5 13.18V17.18L12 21L19 17.18V13.18L5 5.45V13.18Z" fill="white"/>
<path d="M12 3L1 9L12 15L21 10.09V17H23V9M5 13.18V17.18L12 21L19 17.18V13.18L5 5.45V13.18Z" stroke="white" stroke-width="2"/>
</svg>
''';

    return pw.Container(
      padding: pw.EdgeInsets.symmetric(vertical: 5, horizontal: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blue900, width: 1),
        color: PdfColors.white,
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Left: Date
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Sınav Tarihi', style: pw.TextStyle(fontSize: 8)),
              pw.Text(
                dateStr,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),

          pw.Spacer(),

          // Center: School, Exam, List Title
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                'ABC ORTAOKULU',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue900,
                ),
              ),
              pw.Text(
                examName,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
              ),
              pw.Container(
                height: 4,
                width: 200,
                color: PdfColors.green100,
              ), // Decorative separating line style
              pw.Text(
                subTitle,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
              ),
            ],
          ),

          pw.Spacer(),

          // Right: Logo
          pw.Container(
            width: 40,
            height: 40,
            decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              color: PdfColors.blue900,
            ),
            alignment: pw.Alignment.center,
            child: pw.SvgImage(svg: schoolIconSvg, width: 24, height: 24),
          ),
        ],
      ),
    );
  }

  // --- Revised Summary Block (Matches Image 2 Style, Supports Dual Rows) ---
  pw.Widget _buildPdfSummaryBlock(
    List<Map<String, dynamic>> primaryData,
    List<Map<String, dynamic>> allData,
    List<String> subjects,
    Map<int, pw.TableColumnWidth> columnWidths,
    String primaryTitle, {
    List<Map<String, dynamic>>? secondaryData, // Optional Branch Data
    String? secondaryTitle,
  }) {
    // Colors
    final headerColor = PdfColors.cyan100;
    final valueColor = PdfColors.white;
    final borderColor = PdfColors.blue900;
    final borderStyle = pw.Border.all(color: borderColor, width: 0.5);

    // Layout
    final double leftBlockWidth = 150.0;

    // Header Row
    final headerRow = pw.Row(
      children: [
        pw.Container(
          width: leftBlockWidth,
          height: 25,
          decoration: pw.BoxDecoration(color: headerColor, border: borderStyle),
        ),
        for (var s in subjects)
          pw.Expanded(
            child: pw.Container(
              height: 25,
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(
                color: headerColor,
                border: borderStyle,
              ),
              child: pw.Text(
                s.length > 15 ? s.substring(0, 10) + "..." : s,
                style: pw.TextStyle(
                  fontSize: 6,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
        pw.Expanded(
          flex: 2,
          child: pw.Container(
            height: 25,
            decoration: pw.BoxDecoration(
              color: headerColor,
              border: borderStyle,
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Text(
                      "NET",
                      style: pw.TextStyle(
                        fontSize: 6,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Text(
                      "KATILIM",
                      style: pw.TextStyle(
                        fontSize: 6,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    // Helper to build a value row
    pw.Widget _buildValueRow(
      List<Map<String, dynamic>> data,
      String title,
      bool showStats,
    ) {
      Map<String, double> sums = {};
      for (var s in subjects) sums[s] = 0;
      double totalNet = 0;
      for (var item in data) {
        if (item['subjects'] != null && item['subjects'] is Map) {
          final sMap = item['subjects'] as Map;
          for (var subj in subjects) {
            if (sMap.containsKey(subj)) {
              sums[subj] =
                  (sums[subj] ?? 0) +
                  (double.tryParse(sMap[subj]['net']?.toString() ?? '0') ?? 0);
            }
          }
        }
        totalNet += double.tryParse(item['totalNet']?.toString() ?? '0') ?? 0;
      }
      int count = data.isNotEmpty ? data.length : 1;
      double netAvg = totalNet / count;

      return pw.Row(
        children: [
          pw.Container(
            width: leftBlockWidth,
            height: 20,
            alignment: pw.Alignment.centerLeft,
            padding: pw.EdgeInsets.symmetric(horizontal: 4),
            decoration: pw.BoxDecoration(
              color: valueColor,
              border: borderStyle,
            ),
            child: pw.Text(
              title,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
          ),
          for (var s in subjects)
            pw.Expanded(
              child: pw.Container(
                height: 20,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  color: valueColor,
                  border: borderStyle,
                ),
                child: pw.Text(
                  (sums[s]! / count).toStringAsFixed(2),
                  style: pw.TextStyle(
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ),
          pw.Expanded(
            flex: 2,
            child: pw.Container(
              height: 20,
              decoration: pw.BoxDecoration(
                color: valueColor,
                border: borderStyle,
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Center(
                      child: pw.Text(
                        netAvg.toStringAsFixed(2),
                        style: pw.TextStyle(
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Center(
                      child: pw.Text(
                        "${data.length}",
                        style: pw.TextStyle(fontSize: 6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return pw.Column(
      children: [
        headerRow,
        _buildValueRow(primaryData, primaryTitle, true),
        if (secondaryData != null)
          _buildValueRow(secondaryData, secondaryTitle ?? '', true),
      ],
    );
  }

  Map<String, int> _calculateBranchRanks() {
    final sortKey = _listSort == 'Puan Sıralı' ? 'totalScore' : 'totalNet';

    // Group all results by branch
    Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var item in _examResults) {
      String b = item['className'] ?? 'Misafir';
      grouped.putIfAbsent(b, () => []).add(item);
    }

    Map<String, int> branchRankMap = {};

    // For each branch, sort and assign rank
    for (var bName in grouped.keys) {
      var bList = grouped[bName]!;
      bList.sort((a, b) {
        double valA = double.tryParse(a[sortKey]?.toString() ?? '0') ?? 0;
        double valB = double.tryParse(b[sortKey]?.toString() ?? '0') ?? 0;
        if (valA == valB)
          return (a['studentName'] ?? '').compareTo(b['studentName'] ?? '');
        return valB.compareTo(valA);
      });

      int currentRank = 0;
      double? prevVal;
      for (int i = 0; i < bList.length; i++) {
        final v = double.tryParse(bList[i][sortKey]?.toString() ?? '0') ?? 0;
        if (prevVal == null || (v - prevVal).abs() >= 0.001) {
          currentRank++;
          prevVal = v;
        }
        branchRankMap[_getStudentId(bList[i])] = currentRank;
      }
    }
    return branchRankMap;
  }

  pw.Widget _buildPdfDataRows(
    List<Map<String, dynamic>> data,
    List<String> subjects,
    Map<String, int> globalRankMap,
    Map<String, int> branchRankMap, { // Added Branch Rank Map
    required bool isGrouped,
    required Map<int, pw.TableColumnWidth> columnWidths,
  }) {
    final rowEvenColor = PdfColors.white;
    final rowOddColor = PdfColors.blue50;
    final borderColor = PdfColors.blue900;

    return pw.Table(
      border: pw.TableBorder.all(color: borderColor, width: 0.5),
      columnWidths: columnWidths,
      children: List.generate(data.length, (index) {
        final item = data[index];
        final rowColor = index % 2 == 0 ? rowEvenColor : rowOddColor;
        final id = _getStudentId(item);
        final gRank = globalRankMap[id] ?? 0;
        // Local rank for display
        final listRank = index + 1; // Left-most # column

        // Branch Rank from map
        final bRank = branchRankMap[id] ?? 0;

        return pw.TableRow(
          decoration: pw.BoxDecoration(color: rowColor),
          verticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            pw.Padding(
              padding: pw.EdgeInsets.all(2),
              child: pw.Text('$listRank', style: pw.TextStyle(fontSize: 6)),
            ),
            pw.Padding(
              padding: pw.EdgeInsets.all(2),
              child: pw.Text(
                item['studentName'] ?? '',
                style: pw.TextStyle(fontSize: 6),
              ),
            ),
            pw.Padding(
              padding: pw.EdgeInsets.all(2),
              child: pw.Text(
                item['className'] ?? '',
                style: pw.TextStyle(fontSize: 6),
              ),
            ),
            for (var subj in subjects) _buildPdfSubjectCell(item, subj),
            _buildPdfTotalCell(item),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Text('$gRank', style: pw.TextStyle(fontSize: 5)),
                pw.Text(
                  '$gRank',
                  style: pw.TextStyle(fontSize: 5),
                ), // Kurum Rank often same as Global in this context
                pw.Text(
                  '$bRank',
                  style: pw.TextStyle(
                    fontSize: 5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ), // Corrected Branch Rank
              ],
            ),
          ],
        );
      }),
    );
  }

  // Reuseable Header Row
  pw.Widget _buildPdfHeaderRow(
    List<String> subjects,
    List<PdfColor> subjectColors,
    PdfColor headerColor,
    PdfColor borderColor,
    Map<int, pw.TableColumnWidth> columnWidths,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: borderColor, width: 0.5),
      columnWidths: columnWidths,
      children: [
        // Header 1 (Subject Names + Top Labels)
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColors.blue50),
          children: [
            pw.Container(),
            pw.Container(),
            pw.Container(),
            for (int i = 0; i < subjects.length; i++)
              pw.Container(
                padding: pw.EdgeInsets.all(1),
                alignment: pw.Alignment.center,
                color: subjectColors[i % subjectColors.length],
                child: pw.Text(
                  subjects[i],
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 6,
                    color: PdfColors.black,
                  ),
                ),
              ),
            pw.Container(
              color: headerColor,
              child: pw.Center(
                child: pw.Text(
                  'TOPLAM',
                  style: pw.TextStyle(
                    fontSize: 6,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue900,
                  ),
                ),
              ),
            ),
            pw.Container(
              child: pw.Center(
                child: pw.Text(
                  'SIRALAMA',
                  style: pw.TextStyle(
                    fontSize: 6,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue900,
                  ),
                ),
              ),
            ),
          ],
        ),
        // Header 2 (Sub-columns)
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            pw.Padding(
              padding: pw.EdgeInsets.all(2),
              child: pw.Text(
                'Sıra',
                style: pw.TextStyle(
                  fontSize: 6,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Padding(
              padding: pw.EdgeInsets.all(2),
              child: pw.Text(
                'Ad Soyad',
                style: pw.TextStyle(
                  fontSize: 6,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Padding(
              padding: pw.EdgeInsets.all(2),
              child: pw.Text(
                'Sınıf',
                style: pw.TextStyle(
                  fontSize: 6,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),

            // Subject D-Y-B-N Columns - MUST MATCH DATA ALIGNMENT
            for (var _ in subjects)
              pw.Container(
                padding: pw.EdgeInsets.symmetric(horizontal: 0),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Center(
                        child: pw.Text(
                          'D',
                          style: pw.TextStyle(
                            fontSize: 5,
                            color: PdfColors.green800,
                          ),
                        ),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Center(
                        child: pw.Text(
                          'Y',
                          style: pw.TextStyle(
                            fontSize: 5,
                            color: PdfColors.red800,
                          ),
                        ),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Center(
                        child: pw.Text(
                          'B',
                          style: pw.TextStyle(
                            fontSize: 5,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Center(
                        child: pw.Text(
                          'N',
                          style: pw.TextStyle(
                            fontSize: 5,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Net / Puan
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Text(
                      'Net',
                      style: pw.TextStyle(
                        fontSize: 5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Text(
                      'Puan',
                      style: pw.TextStyle(
                        fontSize: 5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Ranks
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Text('Gnl', style: pw.TextStyle(fontSize: 5)),
                  ),
                ),
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Text('Krm', style: pw.TextStyle(fontSize: 5)),
                  ),
                ),
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Text('Şbe', style: pw.TextStyle(fontSize: 5)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // Replaced Cell Builder to ensure alignment
  pw.Widget _buildPdfSubjectCell(Map<String, dynamic> item, String subj) {
    String d = '-', y = '-', b = '-', n = '-';
    if (item['subjects'] != null && item['subjects'][subj] != null) {
      final s = item['subjects'][subj];
      d = s['correct']?.toString() ?? '0';
      y = s['wrong']?.toString() ?? '0';
      b = s['empty']?.toString() ?? '0';
      n =
          double.tryParse(s['net']?.toString() ?? '0')?.toStringAsFixed(2) ??
          '0.00';
    }

    return pw.Container(
      padding: pw.EdgeInsets.symmetric(vertical: 2, horizontal: 0),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Center(
              child: pw.Text(d, style: pw.TextStyle(fontSize: 5)),
            ),
          ),
          pw.Expanded(
            child: pw.Center(
              child: pw.Text(y, style: pw.TextStyle(fontSize: 5)),
            ),
          ),
          pw.Expanded(
            child: pw.Center(
              child: pw.Text(b, style: pw.TextStyle(fontSize: 5)),
            ),
          ),
          pw.Expanded(
            child: pw.Center(
              child: pw.Text(
                n,
                style: pw.TextStyle(
                  fontSize: 5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfTotalCell(Map<String, dynamic> item) {
    double totN = double.tryParse(item['totalNet']?.toString() ?? '0') ?? 0;
    double score = double.tryParse(item['totalScore']?.toString() ?? '0') ?? 0;

    return pw.Row(
      children: [
        pw.Expanded(
          child: pw.Center(
            child: pw.Text(
              totN.toStringAsFixed(2),
              style: pw.TextStyle(fontSize: 5, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Center(
            child: pw.Text(
              score.toStringAsFixed(3),
              style: pw.TextStyle(fontSize: 5, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  // This function was not part of the original request but was present in the original code.
  // It's kept as is, assuming it's used elsewhere or will be removed if not needed.

  // --- Excel Export ---
  Excel _buildExamResultsExcel() {
    final excel = Excel.createExcel();
    // Rename default sheet
    String defaultSheet = excel.getDefaultSheet()!;
    excel.rename(defaultSheet, 'Sonuclar');
    final sheet = excel['Sonuclar'];

    // Headers
    List<String> headers = ['#', 'Ad Soyad', 'Sınıf'];
    for (var s in _availableSubjects) {
      headers.addAll(['$s D', '$s Y', '$s B', '$s N']);
    }
    headers.addAll([
      'Top D',
      'Top Y',
      'Top B',
      'Top N',
      'Puan',
      'Genel Sıra',
      'Kurum Sıra',
      'Şube Sıra',
    ]);

    sheet.appendRow(headers.map((e) => TextCellValue(e)).toList());

    // Data
    _filterResults(); // Ensure filtered/sorted

    // Sort all for ranking
    final sortKey = _listSort == 'Puan Sıralı' ? 'totalScore' : 'totalNet';
    List<Map<String, dynamic>> allSorted = List.from(_examResults);
    allSorted.sort((a, b) {
      double valA = double.tryParse(a[sortKey]?.toString() ?? '0') ?? 0;
      double valB = double.tryParse(b[sortKey]?.toString() ?? '0') ?? 0;
      if (valA == valB) {
        return (a['studentName'] ?? '').compareTo(b['studentName'] ?? '');
      }
      return valB.compareTo(valA);
    });

    final globalRankMapX = _calculateGlobalRanks();
    final branchRankMapX = _calculateBranchRanks();

    for (int i = 0; i < _filteredResults.length; i++) {
      final item = _filteredResults[i];
      List<CellValue> row = [];
      row.add(IntCellValue(i + 1));
      row.add(TextCellValue(item['studentName'] ?? '-'));
      row.add(TextCellValue(item['className'] ?? '-'));

      // Subjects
      int totD = 0, totY = 0, totB = 0;
      Map<String, dynamic> subMap =
          item['subjects'] != null && item['subjects'] is Map
          ? item['subjects']
          : {};

      for (var s in _availableSubjects) {
        if (subMap.containsKey(s)) {
          final val = subMap[s];
          int d = int.tryParse(val['correct']?.toString() ?? '0') ?? 0;
          int y = int.tryParse(val['wrong']?.toString() ?? '0') ?? 0;
          int b = int.tryParse(val['empty']?.toString() ?? '0') ?? 0;
          double n = double.tryParse(val['net']?.toString() ?? '0') ?? 0;

          totD += d;
          totY += y;
          totB += b;

          row.add(IntCellValue(d));
          row.add(IntCellValue(y));
          row.add(IntCellValue(b));
          row.add(DoubleCellValue(n));
        } else {
          row.addAll([
            TextCellValue('-'),
            TextCellValue('-'),
            TextCellValue('-'),
            TextCellValue('-'),
          ]);
        }
      }

      // Totals
      double totN = double.tryParse(item['totalNet']?.toString() ?? '0') ?? 0;
      double score =
          double.tryParse(item['totalScore']?.toString() ?? '0') ?? 0;

      row.add(IntCellValue(totD));
      row.add(IntCellValue(totY));
      row.add(IntCellValue(totB));
      row.add(DoubleCellValue(totN));
      row.add(DoubleCellValue(score));

      // Ranks Logic
      bool match(Map<String, dynamic> e) {
        if (e['studentNumber'] != null &&
            e['studentNumber'].toString().isNotEmpty &&
            item['studentNumber'] != null &&
            item['studentNumber'].toString().isNotEmpty) {
          return e['studentNumber'].toString() ==
              item['studentNumber'].toString();
        }
        return e['studentName'] == item['studentName'] &&
            e['className'] == item['className'];
      }

      int genelRank = globalRankMapX[_getStudentId(item)] ?? 0;
      int classRank = branchRankMapX[_getStudentId(item)] ?? 0;

      row.add(IntCellValue(genelRank));
      row.add(IntCellValue(genelRank)); // Kurum
      row.add(IntCellValue(classRank));

      sheet.appendRow(row);
    }

    return excel;
  }

  Future<Uint8List> _buildExamResultsExcelBytes() async {
    final excel = _buildExamResultsExcel();
    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? []);
  }

  Future<void> _generateAndExportExcel({bool shareOnly = false}) async {
    final excel = _buildExamResultsExcel();
    final fileName = sanitizeFileName('${_selectedExam?.name ?? "Sonuclar"}.xlsx');
    if (shareOnly) {
      final bytes = excel.encode();
      if (bytes != null) {
        await Share.shareXFiles([
          XFile.fromData(
            Uint8List.fromList(bytes),
            name: fileName,
            mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ]);
      }
    } else {
      excel.save(fileName: fileName);
    }
  }

  // ==========================================
  // --- ORTALAMA TAB: EXCEL & PDF EXPORTS ---
  // ==========================================

  Excel _buildAverageExcel() {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet()!;
    excel.rename(defaultSheet, 'Ortalamalar');
    final sheet = excel['Ortalamalar'];

    Map<String, List<Map<String, dynamic>>> branchGroups = {};
    for (var r in _examResults) {
      final bName = r['className']?.toString() ?? 'Bilinmeyen';
      if (_averageScope == 'Şube' &&
          _averageSelectedBranchId != 'all' &&
          bName != _averageSelectedBranchId) {
        continue;
      }
      branchGroups.putIfAbsent(bName, () => []).add(r);
    }
    final sortedBranches = branchGroups.keys.toList()..sort();
    final columns = _averageSelectedSubjects.isEmpty ? _availableSubjects : _averageSelectedSubjects;

    List<CellValue> headerRow = [TextCellValue('Şube Adı')];
    for (var col in columns) {
      headerRow.add(TextCellValue(col));
    }
    if (columns.length > 1) {
      headerRow.add(TextCellValue('GENEL ORT.'));
    }
    sheet.appendRow(headerRow);

    for (var branchName in sortedBranches) {
      final students = branchGroups[branchName]!;
      List<CellValue> row = [TextCellValue(branchName)];
      List<double> branchSubjAverages = [];

      for (var subj in columns) {
        double totalVal = 0;
        int validCount = 0;
        for (var s in students) {
          if (s['subjects'] is Map) {
            final sData = (s['subjects'] as Map)[subj];
            if (sData is Map) {
              double val = 0;
              if (_averageType == 'Net') {
                val = num.tryParse(sData['net']?.toString() ?? '0')?.toDouble() ?? 0.0;
              } else if (_averageType == 'Başarı Yüzdesi') {
                double c = num.tryParse(sData['correct']?.toString() ?? '0')?.toDouble() ?? 0.0;
                double w = num.tryParse(sData['wrong']?.toString() ?? '0')?.toDouble() ?? 0.0;
                double e = num.tryParse(sData['empty']?.toString() ?? '0')?.toDouble() ?? 0.0;
                double totalQ = c + w + e;
                if (totalQ > 0) val = (c / totalQ) * 100;
              } else {
                val = num.tryParse(sData['net']?.toString() ?? '0')?.toDouble() ?? 0.0;
              }
              totalVal += val;
              validCount++;
            }
          }
        }
        double avg = validCount > 0 ? totalVal / students.length : 0.0;
        branchSubjAverages.add(avg);
        row.add(DoubleCellValue(double.parse(avg.toStringAsFixed(2))));
      }

      if (columns.length > 1) {
        double branchGenAvg = 0.0;
        if (_averageType == 'Başarı Yüzdesi') {
          double totalSuccessSum = 0;
          int successCount = 0;
          for (var s in students) {
            double c = 0, w = 0, e = 0;
            if (s['subjects'] is Map) {
              final sMap = s['subjects'] as Map;
              for (var subj in columns) {
                final sData = sMap[subj];
                if (sData is Map) {
                  c += num.tryParse(sData['correct']?.toString() ?? '0')?.toDouble() ?? 0;
                  w += num.tryParse(sData['wrong']?.toString() ?? '0')?.toDouble() ?? 0;
                  e += num.tryParse(sData['empty']?.toString() ?? '0')?.toDouble() ?? 0;
                }
              }
            }
            double totalQ = c + w + e;
            if (totalQ > 0) {
              totalSuccessSum += (c / totalQ) * 100;
              successCount++;
            }
          }
          if (successCount > 0) {
            branchGenAvg = totalSuccessSum / successCount;
          } else if (branchSubjAverages.isNotEmpty) {
            branchGenAvg = branchSubjAverages.reduce((a, b) => a + b) / branchSubjAverages.length;
          }
        } else if (_averageType == 'Puan') {
          double totalSum = 0;
          for (var s in students) {
            totalSum += num.tryParse(s['totalScore']?.toString() ?? '0')?.toDouble() ?? 0.0;
          }
          branchGenAvg = students.isNotEmpty ? totalSum / students.length : 0;
        } else if (_averageType == 'Net') {
          double totalSum = 0;
          for (var s in students) {
            totalSum += num.tryParse(s['totalNet']?.toString() ?? '0')?.toDouble() ?? 0.0;
          }
          branchGenAvg = students.isNotEmpty ? totalSum / students.length : 0;
        }
        row.add(DoubleCellValue(double.parse(branchGenAvg.toStringAsFixed(2))));
      }

      sheet.appendRow(row);
    }

    // KURUM GENELİ Row for Excel
    if (sortedBranches.length > 1) {
      List<CellValue> summaryRow = [TextCellValue('KURUM GENELİ')];
      List<double> schoolSubjAverages = [];

      for (var subj in columns) {
        double totalVal = 0;
        int validCount = 0;
        for (var s in _examResults) {
          if (s['subjects'] is Map) {
            final sData = (s['subjects'] as Map)[subj];
            if (sData is Map) {
              double val = 0;
              if (_averageType == 'Net') {
                val = num.tryParse(sData['net']?.toString() ?? '0')?.toDouble() ?? 0.0;
              } else if (_averageType == 'Başarı Yüzdesi') {
                double c = num.tryParse(sData['correct']?.toString() ?? '0')?.toDouble() ?? 0.0;
                double w = num.tryParse(sData['wrong']?.toString() ?? '0')?.toDouble() ?? 0.0;
                double e = num.tryParse(sData['empty']?.toString() ?? '0')?.toDouble() ?? 0.0;
                double totalQ = c + w + e;
                if (totalQ > 0) val = (c / totalQ) * 100;
              } else {
                val = num.tryParse(sData['net']?.toString() ?? '0')?.toDouble() ?? 0.0;
              }
              totalVal += val;
              validCount++;
            }
          }
        }
        double avg = validCount > 0 ? totalVal / _examResults.length : 0.0;
        schoolSubjAverages.add(avg);
        summaryRow.add(DoubleCellValue(double.parse(avg.toStringAsFixed(2))));
      }

      if (columns.length > 1) {
        double schoolOverallGenAvg = 0.0;
        if (_averageType == 'Başarı Yüzdesi') {
          double totalSuccessSum = 0;
          int successCount = 0;
          for (var s in _examResults) {
            double c = 0, w = 0, e = 0;
            if (s['subjects'] is Map) {
              final sMap = s['subjects'] as Map;
              for (var subj in columns) {
                final sData = sMap[subj];
                if (sData is Map) {
                  c += num.tryParse(sData['correct']?.toString() ?? '0')?.toDouble() ?? 0;
                  w += num.tryParse(sData['wrong']?.toString() ?? '0')?.toDouble() ?? 0;
                  e += num.tryParse(sData['empty']?.toString() ?? '0')?.toDouble() ?? 0;
                }
              }
            }
            double totalQ = c + w + e;
            if (totalQ > 0) {
              totalSuccessSum += (c / totalQ) * 100;
              successCount++;
            }
          }
          if (successCount > 0) {
            schoolOverallGenAvg = totalSuccessSum / successCount;
          } else if (schoolSubjAverages.isNotEmpty) {
            schoolOverallGenAvg = schoolSubjAverages.reduce((a, b) => a + b) / schoolSubjAverages.length;
          }
        } else if (_averageType == 'Puan') {
          double totalSum = 0;
          for (var s in _examResults) {
            totalSum += num.tryParse(s['totalScore']?.toString() ?? '0')?.toDouble() ?? 0.0;
          }
          schoolOverallGenAvg = _examResults.isNotEmpty ? totalSum / _examResults.length : 0.0;
        } else if (_averageType == 'Net') {
          double totalSum = 0;
          for (var s in _examResults) {
            totalSum += num.tryParse(s['totalNet']?.toString() ?? '0')?.toDouble() ?? 0.0;
          }
          schoolOverallGenAvg = _examResults.isNotEmpty ? totalSum / _examResults.length : 0.0;
        }
        summaryRow.add(DoubleCellValue(double.parse(schoolOverallGenAvg.toStringAsFixed(2))));
      }

      sheet.appendRow(summaryRow);
    }

    return excel;
  }

  Future<Uint8List> _buildAverageExcelBytes() async {
    final excel = _buildAverageExcel();
    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? []);
  }

  Future<void> _exportAverageExcel({bool shareOnly = false}) async {
    final excel = _buildAverageExcel();
    final fileName = '${_selectedExam?.name ?? "Sinav"}_Ortalamalar_${_averageType}.xlsx';
    if (shareOnly) {
      final bytes = excel.encode();
      if (bytes != null) {
        await Share.shareXFiles([
          XFile.fromData(
            Uint8List.fromList(bytes),
            name: fileName,
            mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ]);
      }
    } else {
      excel.save(fileName: fileName);
    }
  }

  Future<void> _exportAveragePdf({bool shareOnly = false}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Dialog(
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text("PDF Hazırlanıyor, lütfen bekleyiniz..."),
              ],
            ),
          ),
        );
      },
    );

    try {
      await Future.delayed(const Duration(milliseconds: 100));
      final bytes = await _buildAveragePdfBytes();
      final fileName = '${_selectedExam?.name ?? "Sinav"}_Ortalamalar.pdf';
      if (shareOnly) {
        await Printing.sharePdf(
          bytes: bytes,
          filename: fileName,
        );
      } else {
        await Printing.layoutPdf(
          onLayout: (format) async => bytes,
          name: fileName,
        );
      }
    } catch (e) {
      debugPrint('Export Average PDF Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF oluşturulurken hata: $e')),
        );
      }
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<Uint8List> _buildAveragePdfBytes() async {
    Map<String, List<Map<String, dynamic>>> branchGroups = {};
      for (var r in _examResults) {
        final bName = r['className']?.toString() ?? 'Bilinmeyen';
        if (_averageScope == 'Şube' &&
            _averageSelectedBranchId != 'all' &&
            bName != _averageSelectedBranchId) {
          continue;
        }
        branchGroups.putIfAbsent(bName, () => []).add(r);
      }
      final sortedBranches = branchGroups.keys.toList()..sort();
      final columns = _averageSelectedSubjects.isEmpty ? _availableSubjects : _averageSelectedSubjects;

      final font = await _loadPdfFont();
      final fontBold = await _loadPdfFontBold();
      final pdf = pw.Document();

      // Color coding helpers for "Başarı Yüzdesi"
      PdfColor getAvgTextColor(double val) {
        if (_averageType == 'Başarı Yüzdesi') {
          if (val >= 85) return PdfColor.fromInt(0xFF1B5E20); // green 900
          if (val >= 70) return PdfColor.fromInt(0xFF0D47A1); // blue 900
          if (val >= 50) return PdfColor.fromInt(0xFFE65100); // orange 900
          return PdfColor.fromInt(0xFFB71C1C); // red 900
        }
        return PdfColors.grey900;
      }

      PdfColor getAvgBgColor(double val, bool isEvenRow) {
        if (_averageType == 'Başarı Yüzdesi') {
          if (val >= 85) return PdfColor.fromInt(0xFFE8F5E9); // green 50
          if (val >= 70) return PdfColor.fromInt(0xFFE3F2FD); // blue 50
          if (val >= 50) return PdfColor.fromInt(0xFFFFF3E0); // orange 50
          return PdfColor.fromInt(0xFFFFEBEE); // red 50
        }
        return isEvenRow ? PdfColors.white : PdfColor.fromInt(0xFFF9FAFB);
      }

      // Column widths: Fixed width for Branch Name, EXACT SAME flex width (1.0) for all lesson columns & GENEL ORT.
      final Map<int, pw.TableColumnWidth> columnWidths = {
        0: const pw.FixedColumnWidth(65),
      };
      int colIdx = 1;
      for (int i = 0; i < columns.length; i++) {
        columnWidths[colIdx++] = const pw.FlexColumnWidth(1.0);
      }
      if (columns.length > 1) {
        columnWidths[colIdx++] = const pw.FlexColumnWidth(1.0);
      }

      // Header TableRow
      final headerRow = pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.indigo50),
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            alignment: pw.Alignment.centerLeft,
            child: pw.Text(
              'Şube Adı',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.indigo900),
            ),
          ),
          for (var col in columns)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              alignment: pw.Alignment.center,
              child: pw.Text(
                col,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.indigo900),
              ),
            ),
          if (columns.length > 1)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              alignment: pw.Alignment.center,
              child: pw.Text(
                'GENEL ORT.',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.indigo900),
              ),
            ),
        ],
      );

      List<pw.TableRow> tableRows = [headerRow];

      for (int rIdx = 0; rIdx < sortedBranches.length; rIdx++) {
        final branchName = sortedBranches[rIdx];
        final students = branchGroups[branchName]!;
        final bool isEven = rIdx.isEven;

        List<double> branchSubjAverages = [];
        List<pw.Widget> cells = [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
            alignment: pw.Alignment.centerLeft,
            color: isEven ? PdfColors.white : PdfColor.fromInt(0xFFF9FAFB),
            child: pw.Text(
              branchName,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.grey800),
            ),
          ),
        ];

        for (var subj in columns) {
          double totalVal = 0;
          int validCount = 0;
          for (var s in students) {
            if (s['subjects'] is Map) {
              final sData = (s['subjects'] as Map)[subj];
              if (sData is Map) {
                double val = 0;
                if (_averageType == 'Net') {
                  val = num.tryParse(sData['net']?.toString() ?? '0')?.toDouble() ?? 0.0;
                } else if (_averageType == 'Başarı Yüzdesi') {
                  double c = num.tryParse(sData['correct']?.toString() ?? '0')?.toDouble() ?? 0.0;
                  double w = num.tryParse(sData['wrong']?.toString() ?? '0')?.toDouble() ?? 0.0;
                  double e = num.tryParse(sData['empty']?.toString() ?? '0')?.toDouble() ?? 0.0;
                  double totalQ = c + w + e;
                  if (totalQ > 0) val = (c / totalQ) * 100;
                } else {
                  val = num.tryParse(sData['net']?.toString() ?? '0')?.toDouble() ?? 0.0;
                }
                totalVal += val;
                validCount++;
              }
            }
          }
          double avg = validCount > 0 ? totalVal / students.length : 0.0;
          branchSubjAverages.add(avg);

          cells.add(
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 2),
              alignment: pw.Alignment.center,
              color: getAvgBgColor(avg, isEven),
              child: pw.Text(
                avg.toStringAsFixed(2),
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9,
                  color: getAvgTextColor(avg),
                ),
              ),
            ),
          );
        }

        if (columns.length > 1) {
          double branchGenAvg = 0.0;
          if (_averageType == 'Başarı Yüzdesi') {
            double totalSuccessSum = 0;
            int successCount = 0;
            for (var s in students) {
              double c = 0, w = 0, e = 0;
              if (s['subjects'] is Map) {
                final sMap = s['subjects'] as Map;
                for (var subj in columns) {
                  final sData = sMap[subj];
                  if (sData is Map) {
                    c += num.tryParse(sData['correct']?.toString() ?? '0')?.toDouble() ?? 0;
                    w += num.tryParse(sData['wrong']?.toString() ?? '0')?.toDouble() ?? 0;
                    e += num.tryParse(sData['empty']?.toString() ?? '0')?.toDouble() ?? 0;
                  }
                }
              }
              double totalQ = c + w + e;
              if (totalQ > 0) {
                totalSuccessSum += (c / totalQ) * 100;
                successCount++;
              }
            }
            if (successCount > 0) {
              branchGenAvg = totalSuccessSum / successCount;
            } else if (branchSubjAverages.isNotEmpty) {
              branchGenAvg = branchSubjAverages.reduce((a, b) => a + b) / branchSubjAverages.length;
            }
          } else if (_averageType == 'Puan') {
            double totalSum = 0;
            for (var s in students) {
              totalSum += num.tryParse(s['totalScore']?.toString() ?? '0')?.toDouble() ?? 0.0;
            }
            branchGenAvg = students.isNotEmpty ? totalSum / students.length : 0.0;
          } else if (_averageType == 'Net') {
            double totalSum = 0;
            for (var s in students) {
              totalSum += num.tryParse(s['totalNet']?.toString() ?? '0')?.toDouble() ?? 0.0;
            }
            branchGenAvg = students.isNotEmpty ? totalSum / students.length : 0.0;
          }

          cells.add(
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 2),
              alignment: pw.Alignment.center,
              color: getAvgBgColor(branchGenAvg, isEven),
              child: pw.Text(
                branchGenAvg.toStringAsFixed(2),
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9.5,
                  color: _averageType == 'Başarı Yüzdesi'
                      ? getAvgTextColor(branchGenAvg)
                      : PdfColors.indigo900,
                ),
              ),
            ),
          );
        }

        tableRows.add(pw.TableRow(children: cells));
      }

      // KURUM GENELİ Summary Row for PDF
      if (sortedBranches.length > 1) {
        List<double> schoolSubjAverages = [];
        List<pw.Widget> summaryCells = [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            alignment: pw.Alignment.centerLeft,
            color: PdfColors.indigo50,
            child: pw.Text(
              'KURUM GENELİ',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.indigo900),
            ),
          ),
        ];

        for (var subj in columns) {
          double totalVal = 0;
          int validCount = 0;
          for (var s in _examResults) {
            if (s['subjects'] is Map) {
              final sData = (s['subjects'] as Map)[subj];
              if (sData is Map) {
                double val = 0;
                if (_averageType == 'Net') {
                  val = num.tryParse(sData['net']?.toString() ?? '0')?.toDouble() ?? 0.0;
                } else if (_averageType == 'Başarı Yüzdesi') {
                  double c = num.tryParse(sData['correct']?.toString() ?? '0')?.toDouble() ?? 0.0;
                  double w = num.tryParse(sData['wrong']?.toString() ?? '0')?.toDouble() ?? 0.0;
                  double e = num.tryParse(sData['empty']?.toString() ?? '0')?.toDouble() ?? 0.0;
                  double totalQ = c + w + e;
                  if (totalQ > 0) val = (c / totalQ) * 100;
                } else {
                  val = num.tryParse(sData['net']?.toString() ?? '0')?.toDouble() ?? 0.0;
                }
                totalVal += val;
                validCount++;
              }
            }
          }
          double sAvg = validCount > 0 ? totalVal / _examResults.length : 0.0;
          schoolSubjAverages.add(sAvg);

          summaryCells.add(
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              alignment: pw.Alignment.center,
              color: _averageType == 'Başarı Yüzdesi' ? getAvgBgColor(sAvg, false) : PdfColors.indigo50,
              child: pw.Text(
                sAvg.toStringAsFixed(2),
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9,
                  color: _averageType == 'Başarı Yüzdesi' ? getAvgTextColor(sAvg) : PdfColors.indigo900,
                ),
              ),
            ),
          );
        }

        if (columns.length > 1) {
          double schoolOverallGenAvg = 0.0;
          if (_averageType == 'Başarı Yüzdesi') {
            double totalSuccessSum = 0;
            int successCount = 0;
            for (var s in _examResults) {
              double c = 0, w = 0, e = 0;
              if (s['subjects'] is Map) {
                final sMap = s['subjects'] as Map;
                for (var subj in columns) {
                  final sData = sMap[subj];
                  if (sData is Map) {
                    c += num.tryParse(sData['correct']?.toString() ?? '0')?.toDouble() ?? 0;
                    w += num.tryParse(sData['wrong']?.toString() ?? '0')?.toDouble() ?? 0;
                    e += num.tryParse(sData['empty']?.toString() ?? '0')?.toDouble() ?? 0;
                  }
                }
              }
              double totalQ = c + w + e;
              if (totalQ > 0) {
                totalSuccessSum += (c / totalQ) * 100;
                successCount++;
              }
            }
            if (successCount > 0) {
              schoolOverallGenAvg = totalSuccessSum / successCount;
            } else if (schoolSubjAverages.isNotEmpty) {
              schoolOverallGenAvg = schoolSubjAverages.reduce((a, b) => a + b) / schoolSubjAverages.length;
            }
          } else if (_averageType == 'Puan') {
            double totalSum = 0;
            for (var s in _examResults) {
              totalSum += num.tryParse(s['totalScore']?.toString() ?? '0')?.toDouble() ?? 0.0;
            }
            schoolOverallGenAvg = _examResults.isNotEmpty ? totalSum / _examResults.length : 0.0;
          } else if (_averageType == 'Net') {
            double totalSum = 0;
            for (var s in _examResults) {
              totalSum += num.tryParse(s['totalNet']?.toString() ?? '0')?.toDouble() ?? 0.0;
            }
            schoolOverallGenAvg = _examResults.isNotEmpty ? totalSum / _examResults.length : 0.0;
          }

          summaryCells.add(
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              alignment: pw.Alignment.center,
              color: _averageType == 'Başarı Yüzdesi' ? getAvgBgColor(schoolOverallGenAvg, false) : PdfColors.indigo50,
              child: pw.Text(
                schoolOverallGenAvg.toStringAsFixed(2),
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9.5,
                  color: _averageType == 'Başarı Yüzdesi' ? getAvgTextColor(schoolOverallGenAvg) : PdfColors.indigo900,
                ),
              ),
            ),
          );
        }

        tableRows.add(pw.TableRow(children: summaryCells));
      }

      // Legend Widget for Success Rate
      pw.Widget? legendWidget;
      if (_averageType == 'Başarı Yüzdesi') {
        legendWidget = pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFE8F5E9),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                ),
                child: pw.Text('>= %85', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF1B5E20))),
              ),
              pw.SizedBox(width: 6),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFE3F2FD),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                ),
                child: pw.Text('%70 - %84', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0D47A1))),
              ),
              pw.SizedBox(width: 6),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFFFF3E0),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                ),
                child: pw.Text('%50 - %69', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFFE65100))),
              ),
              pw.SizedBox(width: 6),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFFFEBEE),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                ),
                child: pw.Text('< %50', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFFB71C1C))),
              ),
            ],
          ),
        );
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          theme: pw.ThemeData.withFont(base: font, bold: fontBold),
          header: (context) => pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            padding: const pw.EdgeInsets.only(bottom: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.indigo, width: 2)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _selectedExam?.name ?? 'Sınav Sonuçları',
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Ders Ortalamaları Raporu (${_averageType}) - Kapsam: ${_averageScope}',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Text(
                  DateFormat('dd.MM.yyyy').format(DateTime.now()),
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                ),
              ],
            ),
          ),
          build: (context) => [
            if (legendWidget != null) legendWidget,
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: columnWidths,
              children: tableRows,
            ),
          ],
        ),
      );

    return await pdf.save();
  }

  // ================================================
  // --- BAŞARI BELGESİ: EXCEL & PDF EXPORTS ---
  // ================================================

  Excel _buildCertificateExcel() {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet()!;
    excel.rename(defaultSheet, 'Basari_Belgeleri');
    final sheet = excel['Basari_Belgeleri'];

    List<Map<String, dynamic>> data = List.from(_examResults);
    if (_certificateScope == 'Şube' && _certificateSelectedBranchId != 'all') {
      data = data.where((r) => r['className'] == _certificateSelectedBranchId).toList();
    }

    bool isGeneral = _certificateSelectedSubject == 'Tümü';
    data.sort((a, b) {
      double valA = 0;
      double valB = 0;
      if (isGeneral) {
        valA = double.tryParse(a['totalScore']?.toString() ?? '0') ?? 0;
        valB = double.tryParse(b['totalScore']?.toString() ?? '0') ?? 0;
      } else {
        if (a['subjects'] is Map) {
          final subMap = a['subjects'][_certificateSelectedSubject];
          if (subMap is Map) valA = double.tryParse(subMap['net']?.toString() ?? '0') ?? 0;
        }
        if (b['subjects'] is Map) {
          final subMap = b['subjects'][_certificateSelectedSubject];
          if (subMap is Map) valB = double.tryParse(subMap['net']?.toString() ?? '0') ?? 0;
        }
      }
      return valB.compareTo(valA);
    });

    int limit = _certificateSort == 'İlk 10' ? 10 : (_certificateSort == 'İlk 5' ? 5 : 3);
    final topStudents = data.take(limit).toList();

    List<String> headers = ['Derece', 'Öğrenci No', 'Ad Soyad', 'Sınıf / Şube', 'Alan / Ders', 'Sonuç (Puan/Net)'];
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    for (int i = 0; i < topStudents.length; i++) {
      final s = topStudents[i];
      final sNo = s['studentNumber'] ?? s['studentNo'] ?? s['schoolNumber'] ?? s['number'] ?? '-';
      final sName = s['studentName'] ?? '-';
      final cName = s['className'] ?? '-';
      String valStr = '';
      if (isGeneral) {
        valStr = (double.tryParse(s['totalScore']?.toString() ?? '0') ?? 0).toStringAsFixed(3);
      } else {
        double net = 0;
        if (s['subjects'] is Map) {
          final subMap = s['subjects'][_certificateSelectedSubject];
          if (subMap is Map) net = double.tryParse(subMap['net']?.toString() ?? '0') ?? 0;
        }
        valStr = net.toStringAsFixed(2);
      }

      sheet.appendRow([
        IntCellValue(i + 1),
        TextCellValue(sNo.toString()),
        TextCellValue(sName.toString()),
        TextCellValue(cName.toString()),
        TextCellValue(_certificateSelectedSubject),
        TextCellValue(valStr),
      ]);
    }

    return excel;
  }

  Future<Uint8List> _buildCertificateExcelBytes() async {
    final excel = _buildCertificateExcel();
    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? []);
  }

  Future<void> _exportCertificateExcel({bool shareOnly = false}) async {
    final excel = _buildCertificateExcel();
    final fileName = '${_selectedExam?.name ?? "Sinav"}_Basari_Belgeleri.xlsx';
    if (shareOnly) {
      final bytes = excel.encode();
      if (bytes != null) {
        await Share.shareXFiles([
          XFile.fromData(
            Uint8List.fromList(bytes),
            name: fileName,
            mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ]);
      }
    } else {
      excel.save(fileName: fileName);
    }
  }

  Future<void> _exportCertificatePdf({bool shareOnly = false}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Dialog(
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text("Başarı Belgeleri PDF Hazırlanıyor..."),
              ],
            ),
          ),
        );
      },
    );

    try {
      await Future.delayed(const Duration(milliseconds: 100));
      final bytes = await _buildCertificatePdfBytes();
      final fileName = '${_selectedExam?.name ?? "Sinav"}_Basari_Belgeleri.pdf';
      if (shareOnly) {
        await Printing.sharePdf(
          bytes: bytes,
          filename: fileName,
        );
      } else {
        await Printing.layoutPdf(
          onLayout: (format) async => bytes,
          name: fileName,
        );
      }
    } catch (e) {
      debugPrint('Export Certificate PDF Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF oluşturulurken hata: $e')),
        );
      }
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<Uint8List> _buildCertificatePdfBytes() async {
    List<Map<String, dynamic>> data = List.from(_examResults);
      if (_certificateScope == 'Şube' && _certificateSelectedBranchId != 'all') {
        data = data.where((r) => r['className'] == _certificateSelectedBranchId).toList();
      }

      bool isGeneral = _certificateSelectedSubject == 'Tümü';
      data.sort((a, b) {
        double valA = 0;
        double valB = 0;
        if (isGeneral) {
          valA = double.tryParse(a['totalScore']?.toString() ?? '0') ?? 0;
          valB = double.tryParse(b['totalScore']?.toString() ?? '0') ?? 0;
        } else {
          if (a['subjects'] is Map) {
            final subMap = a['subjects'][_certificateSelectedSubject];
            if (subMap is Map) valA = double.tryParse(subMap['net']?.toString() ?? '0') ?? 0;
          }
          if (b['subjects'] is Map) {
            final subMap = b['subjects'][_certificateSelectedSubject];
            if (subMap is Map) valB = double.tryParse(subMap['net']?.toString() ?? '0') ?? 0;
          }
        }
        return valB.compareTo(valA);
      });

      int limit = _certificateSort == 'İlk 10' ? 10 : (_certificateSort == 'İlk 5' ? 5 : 3);
      final topStudents = data.take(limit).toList();
      if (topStudents.isEmpty) {
        throw Exception('Yazdırılacak öğrenci bulunamadı.');
      }

      final font = await _loadPdfFont();
      final fontBold = await _loadPdfFontBold();
      final pdf = pw.Document();

      for (int i = 0; i < topStudents.length; i++) {
        final s = topStudents[i];
        final rank = i + 1;
        final sNo = s['studentNumber'] ?? s['studentNo'] ?? s['schoolNumber'] ?? s['number'] ?? '';
        final sName = s['studentName'] ?? 'Öğrenci';
        final cName = s['className'] ?? '';
        String valStr = '';
        String fieldLabel = '';
        if (isGeneral) {
          fieldLabel = 'Toplam Puan';
          valStr = (double.tryParse(s['totalScore']?.toString() ?? '0') ?? 0).toStringAsFixed(3);
        } else {
          fieldLabel = '$_certificateSelectedSubject Net';
          double net = 0;
          if (s['subjects'] is Map) {
            final subMap = s['subjects'][_certificateSelectedSubject];
            if (subMap is Map) net = double.tryParse(subMap['net']?.toString() ?? '0') ?? 0;
          }
          valStr = net.toStringAsFixed(2);
        }

        PdfColor medalColor = PdfColors.amber700;
        String medalName = 'BİRİNCİLİK';
        if (rank == 1) {
          medalColor = PdfColors.amber700;
          medalName = 'BİRİNCİLİK';
        } else if (rank == 2) {
          medalColor = PdfColors.blueGrey600;
          medalName = 'İKİNCİLİK';
        } else if (rank == 3) {
          medalColor = PdfColors.brown600;
          medalName = 'ÜÇÜNCÜLÜK';
        }

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.all(32),
            theme: pw.ThemeData.withFont(base: font, bold: fontBold),
            build: (context) {
              return pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: medalColor, width: 4),
                  borderRadius: pw.BorderRadius.circular(16),
                ),
                padding: const pw.EdgeInsets.all(24),
                child: pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300, width: 1.5),
                    borderRadius: pw.BorderRadius.circular(10),
                  ),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 24),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      // Header
                      pw.Column(
                        children: [
                          pw.Text(
                            (_schoolTypeName ?? 'EĞİTİM KURUMLARI').toUpperCase(),
                            style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.indigo900,
                              letterSpacing: 1.5,
                            ),
                          ),
                          pw.SizedBox(height: 8),
                          pw.Text(
                            'BAŞARI BELGESİ',
                            style: pw.TextStyle(
                              fontSize: 28,
                              fontWeight: pw.FontWeight.bold,
                              color: medalColor,
                              letterSpacing: 3,
                            ),
                          ),
                          pw.Container(
                            margin: const pw.EdgeInsets.symmetric(vertical: 8),
                            height: 2,
                            width: 140,
                            color: medalColor,
                          ),
                          pw.Text(
                            '$medalName ÖDÜLÜ',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.grey700,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),

                      // Body
                      pw.Column(
                        children: [
                          pw.Text(
                            sName,
                            style: pw.TextStyle(
                              fontSize: 24,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.black,
                            ),
                          ),
                          pw.SizedBox(height: 6),
                          pw.Text(
                            'Sınıfı: $cName   ${sNo.toString().isNotEmpty ? "•   Öğrenci No: $sNo" : ""}',
                            style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                          ),
                          pw.SizedBox(height: 16),
                          pw.Container(
                            constraints: const pw.BoxConstraints(maxWidth: 500),
                            child: pw.Text(
                              'Kurumumuzda uygulanan "${_selectedExam?.name ?? 'Sınav'}" değerlendirmesinde '
                              '${isGeneral ? "Genel Değerlendirmede" : "$_certificateSelectedSubject Dersinde"} '
                              'üstün gayret ve başarı göstererek ${rank}. olmuştur. Öğrencimizi tebrik eder, başarılarının devamını dileriz.',
                              textAlign: pw.TextAlign.center,
                              style: const pw.TextStyle(fontSize: 11, height: 1.5, color: PdfColors.grey800),
                            ),
                          ),
                          pw.SizedBox(height: 14),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.grey100,
                              borderRadius: pw.BorderRadius.circular(8),
                              border: pw.Border.all(color: PdfColors.grey300),
                            ),
                            child: pw.Text(
                              '$fieldLabel: $valStr',
                              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                            ),
                          ),
                        ],
                      ),

                      // Footer
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text('Tarih: ${DateFormat('dd.MM.yyyy').format(DateTime.now())}',
                                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                              pw.Text('eduKN Ölçme ve Değerlendirme',
                                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
                            ],
                          ),
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              pw.Text('Okul Yönetimi',
                                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
                              pw.SizedBox(height: 24),
                              pw.Text('İmza / Mühür',
                                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      }

    return await pdf.save();
  }

  // ========================================================
  // --- KAZANIM FREKANSLARI: EXCEL & PDF EXPORTS ---
  // ========================================================

  Excel _buildTopicFrequencyExcel() {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet()!;
    excel.rename(defaultSheet, 'Kazanimlar');
    final sheet = excel['Kazanimlar'];

    List<Map<String, dynamic>> relevantData = [];
    if (_topicFrequencyScope == 'Kurum') {
      relevantData = _examResults;
    } else if (_topicFrequencyScope == 'Şube') {
      relevantData = _topicFrequencySelectedBranchId == 'all'
          ? _examResults
          : _examResults.where((r) => r['className'] == _topicFrequencySelectedBranchId).toList();
    } else if (_topicFrequencyScope == 'Öğrenci') {
      relevantData = _topicFrequencySelectedStudentId == 'all'
          ? _examResults
          : _examResults.where((r) => _getStudentId(r) == _topicFrequencySelectedStudentId).toList();
    }

    final subjects = _topicFrequencySelectedSubjects.isEmpty
        ? _availableSubjects
        : _topicFrequencySelectedSubjects;

    List<String> headers = ['Ders', 'Kazanım', 'Soru Sayısı', 'Toplam Soru', 'Doğru', 'Yanlış', 'Boş', 'Başarı %'];
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    for (var subj in subjects) {
      final results = _calculateTopicStats(subj, relevantData);
      final stats = results['stats'] as Map<String, Map<String, double>>? ?? {};
      final qCounts = results['topicQCounts'] as Map<String, int>? ?? {};
      final allTopics = {...qCounts.keys, ...stats.keys};

      for (var topic in allTopics) {
        int qCount = qCounts[topic] ?? 0;
        if (qCount == 0) continue;
        int totalQCount = qCount * relevantData.length;
        double correct = stats[topic]?['correct'] ?? 0;
        double wrong = stats[topic]?['wrong'] ?? 0;
        double empty = stats[topic]?['empty'] ?? 0;
        double successRate = totalQCount > 0 ? (correct / totalQCount) * 100 : 0;

        sheet.appendRow([
          TextCellValue(subj),
          TextCellValue(topic),
          IntCellValue(qCount),
          IntCellValue(totalQCount),
          DoubleCellValue(correct),
          DoubleCellValue(wrong),
          DoubleCellValue(empty),
          DoubleCellValue(double.parse(successRate.toStringAsFixed(2))),
        ]);
      }
    }

    return excel;
  }

  Future<Uint8List> _buildTopicFrequencyExcelBytes() async {
    final excel = _buildTopicFrequencyExcel();
    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? []);
  }

  Future<void> _exportTopicFrequencyExcel({bool shareOnly = false}) async {
    final excel = _buildTopicFrequencyExcel();
    final fileName = '${_selectedExam?.name ?? "Sinav"}_Kazanim_Frekanslari.xlsx';
    if (shareOnly) {
      final bytes = excel.encode();
      if (bytes != null) {
        await Share.shareXFiles([
          XFile.fromData(
            Uint8List.fromList(bytes),
            name: fileName,
            mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ]);
      }
    } else {
      excel.save(fileName: fileName);
    }
  }

  Future<Uint8List> _buildTopicFrequencyPdfBytes() async {
    List<Map<String, dynamic>> relevantData = [];
    if (_topicFrequencyScope == 'Kurum') {
      relevantData = _examResults;
    } else if (_topicFrequencyScope == 'Şube') {
      relevantData = _topicFrequencySelectedBranchId == 'all'
          ? _examResults
          : _examResults.where((r) => r['className'] == _topicFrequencySelectedBranchId).toList();
    } else if (_topicFrequencyScope == 'Öğrenci') {
      relevantData = _topicFrequencySelectedStudentId == 'all'
          ? _examResults
          : _examResults.where((r) => _getStudentId(r) == _topicFrequencySelectedStudentId).toList();
    }

    final subjects = _topicFrequencySelectedSubjects.isEmpty
        ? _availableSubjects
        : _topicFrequencySelectedSubjects;

    final font = await _loadPdfFont();
    final fontBold = await _loadPdfFontBold();
    final pdf = pw.Document();

    List<pw.Widget> contentWidgets = [];

    for (var subj in subjects) {
      final results = _calculateTopicStats(subj, relevantData);
      final stats = results['stats'] as Map<String, Map<String, double>>? ?? {};
      final qCounts = results['topicQCounts'] as Map<String, int>? ?? {};
      final allTopics = {...qCounts.keys, ...stats.keys};

      List<List<String>> tableData = [];
      for (var topic in allTopics) {
        int qCount = qCounts[topic] ?? 0;
        if (qCount == 0) continue;
        int totalQCount = qCount * relevantData.length;
        double correct = stats[topic]?['correct'] ?? 0;
        double wrong = stats[topic]?['wrong'] ?? 0;
        double empty = stats[topic]?['empty'] ?? 0;
        double successRate = totalQCount > 0 ? (correct / totalQCount) * 100 : 0;

        tableData.add([
          topic,
          qCount.toString(),
          totalQCount.toString(),
          correct.toStringAsFixed(0),
          wrong.toStringAsFixed(0),
          empty.toStringAsFixed(0),
          '%${successRate.toStringAsFixed(1)}',
        ]);
      }

      if (tableData.isNotEmpty) {
        contentWidgets.add(
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 14, bottom: 6),
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: const pw.BoxDecoration(color: PdfColors.indigo50),
            child: pw.Text(
              'DERS: $subj',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
            ),
          ),
        );

        contentWidgets.add(
          pw.TableHelper.fromTextArray(
            headers: ['Kazanım', 'Soru', 'Toplam', 'D', 'Y', 'B', 'Başarı %'],
            data: tableData,
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.indigo900),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.center,
            cellAlignments: {0: pw.Alignment.centerLeft},
            columnWidths: {
              0: const pw.FlexColumnWidth(5),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1),
              4: const pw.FlexColumnWidth(1),
              5: const pw.FlexColumnWidth(1),
              6: const pw.FlexColumnWidth(1.2),
            },
          ),
        );
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        header: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 10),
          padding: const pw.EdgeInsets.only(bottom: 6),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.indigo, width: 2)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _selectedExam?.name ?? 'Sınav Sonuçları',
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Kazanım Analizi ve Frekans Raporu - Kapsam: ${_topicFrequencyScope}',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                  ),
                ],
              ),
              pw.Text(
                DateFormat('dd.MM.yyyy').format(DateTime.now()),
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            ],
          ),
        ),
        build: (context) => contentWidgets,
      ),
    );

    return await pdf.save();
  }

  Future<void> _exportTopicFrequencyPdf({bool shareOnly = false}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Dialog(
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text("Kazanım Frekansları PDF Hazırlanıyor..."),
              ],
            ),
          ),
        );
      },
    );

    try {
      await Future.delayed(const Duration(milliseconds: 100));
      final bytes = await _buildTopicFrequencyPdfBytes();
      final filename = '${_selectedExam?.name ?? "Sinav"}_Kazanim_Frekanslari.pdf';

      if (shareOnly) {
        await Printing.sharePdf(
          bytes: bytes,
          filename: filename,
        );
      } else {
        await Printing.layoutPdf(
          onLayout: (format) async => bytes,
          name: filename,
        );
      }
    } catch (e) {
      debugPrint('Export Topic Frequency PDF Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF oluşturulurken hata: $e')),
        );
      }
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  // =====================================================
  // --- SORU FREKANSLARI: EXCEL & PDF EXPORTS ---
  // =====================================================

  Excel _buildQuestionFrequencyExcel() {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet()!;
    excel.rename(defaultSheet, 'Soru_Frekanslari');
    final sheet = excel['Soru_Frekanslari'];

    List<Map<String, dynamic>> relevantData = [];
    if (_questionFrequencyScope == 'Kurum') {
      relevantData = _examResults;
    } else if (_questionFrequencyScope == 'Şube') {
      relevantData = _questionFrequencySelectedBranchId == 'all'
          ? _examResults
          : _examResults.where((r) => r['className'] == _questionFrequencySelectedBranchId).toList();
    } else if (_questionFrequencyScope == 'Öğrenci') {
      relevantData = _questionFrequencySelectedStudentId == 'all'
          ? _examResults
          : _examResults.where((r) => _getStudentId(r) == _questionFrequencySelectedStudentId).toList();
    }

    List<String> headers = [
      'Ders',
      'Soru No',
      'Konu / Kazanım',
      'Doğru Cevap',
      'A (%)',
      'B (%)',
      'C (%)',
      'D (%)',
      if (_hasEOption) 'E (%)',
      'Boş (%)',
      'Başarı %',
    ];
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    for (var subj in _availableSubjects) {
      final stats = _calculateQuestionStats(subj, relevantData);
      for (var q in stats) {
        sheet.appendRow([
          TextCellValue(subj),
          TextCellValue(q['qNo']?.toString() ?? '-'),
          TextCellValue(q['topic']?.toString() ?? '-'),
          TextCellValue(q['key']?.toString() ?? '-'),
          DoubleCellValue(double.parse((q['A'] as double? ?? 0).toStringAsFixed(1))),
          DoubleCellValue(double.parse((q['B'] as double? ?? 0).toStringAsFixed(1))),
          DoubleCellValue(double.parse((q['C'] as double? ?? 0).toStringAsFixed(1))),
          DoubleCellValue(double.parse((q['D'] as double? ?? 0).toStringAsFixed(1))),
          if (_hasEOption)
            DoubleCellValue(double.parse((q['E'] as double? ?? 0).toStringAsFixed(1))),
          DoubleCellValue(double.parse((q['Empty'] as double? ?? 0).toStringAsFixed(1))),
          DoubleCellValue(double.parse((q['Success'] as double? ?? 0).toStringAsFixed(1))),
        ]);
      }
    }

    return excel;
  }

  Future<Uint8List> _buildQuestionFrequencyExcelBytes() async {
    final excel = _buildQuestionFrequencyExcel();
    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? []);
  }

  Future<void> _exportQuestionFrequencyExcel({bool shareOnly = false}) async {
    final excel = _buildQuestionFrequencyExcel();
    final fileName = '${_selectedExam?.name ?? "Sinav"}_Soru_Frekanslari.xlsx';
    if (shareOnly) {
      final bytes = excel.encode();
      if (bytes != null) {
        await Share.shareXFiles([
          XFile.fromData(
            Uint8List.fromList(bytes),
            name: fileName,
            mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ]);
      }
    } else {
      excel.save(fileName: fileName);
    }
  }

  Future<Uint8List> _buildQuestionFrequencyPdfBytes() async {
    List<Map<String, dynamic>> relevantData = [];
    if (_questionFrequencyScope == 'Kurum') {
      relevantData = _examResults;
    } else if (_questionFrequencyScope == 'Şube') {
      relevantData = _questionFrequencySelectedBranchId == 'all'
          ? _examResults
          : _examResults.where((r) => r['className'] == _questionFrequencySelectedBranchId).toList();
    } else if (_questionFrequencyScope == 'Öğrenci') {
      relevantData = _questionFrequencySelectedStudentId == 'all'
          ? _examResults
          : _examResults.where((r) => _getStudentId(r) == _questionFrequencySelectedStudentId).toList();
    }

    final font = await _loadPdfFont();
    final fontBold = await _loadPdfFontBold();
    final pdf = pw.Document();

    pw.Widget buildPageHeader() => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 10),
          padding: const pw.EdgeInsets.only(bottom: 6),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.indigo, width: 2)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _selectedExam?.name ?? 'Sınav Sonuçları',
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Soru Frekansları ve Madde Analizi Raporu - Kapsam: ${_questionFrequencyScope}',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                  ),
                ],
              ),
              pw.Text(
                DateFormat('dd.MM.yyyy').format(DateTime.now()),
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            ],
          ),
        );

    const double pageMargin = 24;
    bool anyPage = false;

    // Her ders (branş) ayrı bir sayfada ve tek sayfaya sığacak şekilde basılır.
    for (var subj in _availableSubjects) {
      final stats = _calculateQuestionStats(subj, relevantData);
      if (stats.isEmpty) continue;

      List<List<String>> tableData = [];
      for (var q in stats) {
        tableData.add([
          q['qNo']?.toString() ?? '-',
          q['topic']?.toString() ?? '-',
          q['key']?.toString() ?? '-',
          '%${(q['A'] as double? ?? 0).toStringAsFixed(1)}',
          '%${(q['B'] as double? ?? 0).toStringAsFixed(1)}',
          '%${(q['C'] as double? ?? 0).toStringAsFixed(1)}',
          '%${(q['D'] as double? ?? 0).toStringAsFixed(1)}',
          if (_hasEOption) '%${(q['E'] as double? ?? 0).toStringAsFixed(1)}',
          '%${(q['Empty'] as double? ?? 0).toStringAsFixed(1)}',
          '%${(q['Success'] as double? ?? 0).toStringAsFixed(1)}',
        ]);
      }

      // Çok soruluysa dikey sayfa (daha fazla satır sığar), değilse yatay
      final pageFormat = stats.length > 22 ? PdfPageFormat.a4 : PdfPageFormat.a4.landscape;
      final contentWidth = pageFormat.width - pageMargin * 2;

      final table = pw.TableHelper.fromTextArray(
        headers: [
          'Soru',
          'Konu / Kazanım',
          'Cevap',
          'A (%)',
          'B (%)',
          'C (%)',
          'D (%)',
          if (_hasEOption) 'E (%)',
          'Boş (%)',
          'Başarı %',
        ],
        data: tableData,
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.indigo900),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        cellStyle: const pw.TextStyle(fontSize: 8),
        cellAlignment: pw.Alignment.center,
        cellAlignments: {1: pw.Alignment.centerLeft},
        columnWidths: _hasEOption
            ? {
                0: const pw.FlexColumnWidth(0.9),
                1: const pw.FlexColumnWidth(3.5),
                2: const pw.FlexColumnWidth(0.8),
                3: const pw.FlexColumnWidth(0.8),
                4: const pw.FlexColumnWidth(0.8),
                5: const pw.FlexColumnWidth(0.8),
                6: const pw.FlexColumnWidth(0.8),
                7: const pw.FlexColumnWidth(0.8),
                8: const pw.FlexColumnWidth(0.8),
                9: const pw.FlexColumnWidth(1.0),
              }
            : {
                0: const pw.FlexColumnWidth(0.9),
                1: const pw.FlexColumnWidth(3.8),
                2: const pw.FlexColumnWidth(0.8),
                3: const pw.FlexColumnWidth(0.8),
                4: const pw.FlexColumnWidth(0.8),
                5: const pw.FlexColumnWidth(0.8),
                6: const pw.FlexColumnWidth(0.8),
                7: const pw.FlexColumnWidth(0.8),
                8: const pw.FlexColumnWidth(1.0),
              },
      );

      anyPage = true;
      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(pageMargin),
          theme: pw.ThemeData.withFont(base: font, bold: fontBold),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              buildPageHeader(),
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 6),
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: const pw.BoxDecoration(color: PdfColors.indigo50),
                child: pw.Text(
                  'DERS: $subj',
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                ),
              ),
              // Tablo sayfaya sığmıyorsa tek sayfaya sığacak kadar küçültülür
              pw.Expanded(
                child: pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  alignment: pw.Alignment.topCenter,
                  child: pw.SizedBox(width: contentWidth, child: table),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!anyPage) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(pageMargin),
          theme: pw.ThemeData.withFont(base: font, bold: fontBold),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              buildPageHeader(),
              pw.Text('Gösterilecek soru verisi bulunamadı.'),
            ],
          ),
        ),
      );
    }

    return await pdf.save();
  }

  Future<void> _exportQuestionFrequencyPdf({bool shareOnly = false}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Dialog(
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text("Soru Frekansları PDF Hazırlanıyor..."),
              ],
            ),
          ),
        );
      },
    );

    try {
      await Future.delayed(const Duration(milliseconds: 100));
      final bytes = await _buildQuestionFrequencyPdfBytes();
      final filename = '${_selectedExam?.name ?? "Sinav"}_Soru_Frekanslari.pdf';

      if (shareOnly) {
        await Printing.sharePdf(
          bytes: bytes,
          filename: filename,
        );
      } else {
        await Printing.layoutPdf(
          onLayout: (format) async => bytes,
          name: filename,
        );
      }
    } catch (e) {
      debugPrint('Export Question Frequency PDF Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF oluşturulurken hata: $e')),
        );
      }
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Widget _buildTopicAnalysisTable(
    String subject,
    List<Map<String, dynamic>> students, {
    bool isMobile = false,
  }) {
    return Card(
      margin: EdgeInsets.only(
        left: isMobile ? 0 : 16,
      ), // Remove bottom margin to match height
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          // Removed mainAxisSize: MainAxisSize.min to allow stretching without limit
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$subject - Kazanım Analizi',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.fullscreen, color: Colors.indigo),
                  tooltip: 'Tam Ekran',
                  onPressed: () => _openFullScreenTopicAnalysis(subject, students),
                ),
              ],
            ),
            Divider(),
            isMobile
                ? _buildTopicTableContent(subject, students, isMobile: isMobile)
                : Expanded(
                    child: _buildTopicTableContent(
                      subject,
                      students,
                      isMobile: isMobile,
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicTableContent(
    String subject,
    List<Map<String, dynamic>> students, {
    bool isMobile = false,
    bool isFullScreen = false,
  }) {
    if (_selectedExam == null || students.isEmpty) return SizedBox();

    int studentCount = students.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        // --- ALL SUBJECTS AGGREGATION ---
        if (subject == 'Tüm Dersler') {
          List<DataRow> allRows = [];

          // Determine which subjects to show
          List<String> subjectsToProcess = [];
          if (_reportSelectedSubjects.isNotEmpty) {
            subjectsToProcess = _reportSelectedSubjects;
          } else {
            subjectsToProcess = _availableSubjects;
          }

          for (var subj in _availableSubjects) {
            // Only process selected subjects
            if (!subjectsToProcess.contains(subj)) continue;

            // Calculate stats for this subject
            var results = _calculateTopicStats(subj, students);
            var subjectStats =
                results['stats'] as Map<String, Map<String, double>>;
            var subjectQCounts = results['topicQCounts'] as Map<String, int>;
            var subjectTopicIndices =
                results['topicIndices'] as Map<String, List<int>>?;

            if (subjectQCounts.isEmpty) continue;

            List<DataRow> subjRows = _generateDataRows(
              subj,
              subjectStats,
              subjectQCounts,
              studentCount,
              isMobile,
              constraints.maxWidth,
              topicIndices: subjectTopicIndices,
              showIndices: true, // Enable Question Numbers
            );

            if (subjRows.isNotEmpty) {
              // Add Header Row
              allRows.add(
                DataRow(
                  color: WidgetStateProperty.all(Colors.grey.shade100),
                  cells: [
                    DataCell(
                      Container(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          subj,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                      ),
                    ),
                    DataCell(SizedBox()),
                    DataCell(SizedBox()),
                    DataCell(SizedBox()),
                    DataCell(SizedBox()),
                    DataCell(SizedBox()),
                    DataCell(SizedBox()),
                  ],
                ),
              );
              allRows.addAll(subjRows);
            }
          }
          return _buildDataTable(context, allRows, isMobile, isFullScreen, minWidth: constraints.maxWidth);
        }

        // --- SINGLE SUBJECT LOGIC ---
        var results = _calculateTopicStats(subject, students);
        var stats = results['stats'] as Map<String, Map<String, double>>;
        var topicQCounts = results['topicQCounts'] as Map<String, int>;
        var topicIndices = results['topicIndices'] as Map<String, List<int>>?;

        List<DataRow> dynamicRows = _generateDataRows(
          subject,
          stats,
          topicQCounts,
          studentCount,
          isMobile,
          constraints.maxWidth,
          topicIndices: topicIndices,
          showIndices: true, // Enable Question Numbers
        );

        return _buildDataTable(context, dynamicRows, isMobile, isFullScreen, minWidth: constraints.maxWidth);
      },
    );
  }

  // --- Certificate Tab Implementation ---

  Widget _buildCertificateTab() {
    return Column(
      children: [
        // 1. Header Filters
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Kapsam
                  Expanded(
                    child: _buildDropdown(
                      label: 'Kapsam',
                      value: _certificateScope,
                      items: ['Kurum', 'Şube'],
                      onChanged: (val) {
                        setState(() {
                          _certificateScope = val!;
                          if (_certificateScope == 'Kurum') {
                            _certificateSelectedBranchId = 'all';
                          }
                        });
                      },
                    ),
                  ),
                  SizedBox(width: 16),

                  // Sıralama
                  Expanded(
                    child: _buildDropdown(
                      label: 'Sıralama',
                      value: _certificateSort,
                      items: ['İlk 3', 'İlk 5', 'İlk 10'],
                      onChanged: (val) {
                        setState(() => _certificateSort = val!);
                      },
                    ),
                  ),

                  // Conditional Branch
                  if (_certificateScope == 'Şube') ...[
                    SizedBox(width: 16),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final branchNames = _examResults
                              .map((e) => e['className']?.toString())
                              .where((n) => n != null && n.isNotEmpty)
                              .map((n) => n!)
                              .toSet()
                              .toList();
                          branchNames.sort();

                          final dropdownItems = [
                            DropdownMenuItem<String>(
                              value: 'all',
                              child: Text('Tüm Şubeler'),
                            ),
                            ...branchNames.map(
                              (name) => DropdownMenuItem<String>(
                                value: name,
                                child: Text(name),
                              ),
                            ),
                          ];
                          return _buildDropdown(
                            label: 'Şube Seç',
                            value: _certificateSelectedBranchId,
                            items: null,
                            dropdownItems: dropdownItems,
                            onChanged: (val) {
                              setState(
                                () => _certificateSelectedBranchId = val!,
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],

                  const SizedBox(width: 12),
                  // Actions Menu (3-dots)
                  _buildActionMenuButton(
                    tooltip: 'Başarı Belgesi İşlemleri',
                    onSelected: (val) {
                      if (val == 'yazdir' || val == 'pdf') {
                        _exportCertificatePdf();
                      } else if (val == 'excel') {
                        _exportCertificateExcel();
                      } else if (val == 'paylas') {
                        _showShareDialog(
                          title: 'Başarı Belgeleri Raporu',
                          reportType: 'Başarı Belgesi',
                          getPdfBytes: () => _buildCertificatePdfBytes(),
                          pdfFileName: 'basari_belgeleri_${_selectedExam?.name ?? "sinav"}.pdf',
                          getExcelBytes: () => _buildCertificateExcelBytes(),
                          excelFileName: 'basari_belgeleri_${_selectedExam?.name ?? "sinav"}.xlsx',
                          onSharePdf: () => _exportCertificatePdf(shareOnly: true),
                          onShareExcel: () => _exportCertificateExcel(shareOnly: false),
                        );
                      }
                    },
                    items: [
                      _buildPopupItem('yazdir', Icons.print_rounded, Colors.blue.shade700, 'Yazdır'),
                      _buildPopupItem('pdf', Icons.picture_as_pdf_rounded, Colors.red.shade700, 'PDF İndir'),
                      _buildPopupItem('excel', Icons.table_chart_rounded, Colors.green.shade700, 'Excel İndir'),
                      _buildPopupItem('paylas', Icons.share_rounded, Colors.indigo.shade700, 'Paylaş'),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        // 2. Subject Chips (Single Selection Wrapper)
        _buildCertificateSubjectFilter(),

        // 3. Content Area
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: _buildCertificateContent(),
          ),
        ),
      ],
    );
  }

  Widget _buildCertificateSubjectFilter() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildLessonFilterChip(
                label: 'Tümü',
                isSelected: _certificateSelectedSubject == 'Tümü',
                onSelected: (val) {
                  setState(() => _certificateSelectedSubject = 'Tümü');
                },
              ),
              Container(
                height: 24,
                width: 1,
                color: Colors.grey.shade300,
                margin: EdgeInsets.symmetric(horizontal: 12),
              ),
              ..._availableSubjects.map((s) {
                return Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: _buildLessonFilterChip(
                    label: s,
                    isSelected: _certificateSelectedSubject == s,
                    onSelected: (val) {
                      setState(() => _certificateSelectedSubject = s);
                    },
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCertificateContent() {
    // 1. Filter Data
    List<Map<String, dynamic>> data = List.from(_examResults);

    if (_certificateScope == 'Şube' && _certificateSelectedBranchId != 'all') {
      data = data
          .where((r) => r['className'] == _certificateSelectedBranchId)
          .toList();
    }

    // 2. Sort
    bool isGeneral = _certificateSelectedSubject == 'Tümü';
    data.sort((a, b) {
      double valA = 0;
      double valB = 0;

      if (isGeneral) {
        valA = double.tryParse(a['totalScore']?.toString() ?? '0') ?? 0;
        valB = double.tryParse(b['totalScore']?.toString() ?? '0') ?? 0;
      } else {
        // Subject Net
        if (a['subjects'] is Map) {
          final subMap = a['subjects'][_certificateSelectedSubject];
          if (subMap is Map) {
            valA = double.tryParse(subMap['net']?.toString() ?? '0') ?? 0;
          }
        }
        if (b['subjects'] is Map) {
          final subMap = b['subjects'][_certificateSelectedSubject];
          if (subMap is Map) {
            valB = double.tryParse(subMap['net']?.toString() ?? '0') ?? 0;
          }
        }
      }
      return valB.compareTo(valA); // Descending by default
    });

    // Take top students according to selected limit
    int limit = _certificateSort == 'İlk 10' ? 10 : (_certificateSort == 'İlk 5' ? 5 : 3);
    final topStudents = data.take(limit).toList();

    if (topStudents.isEmpty) return Center(child: Text('Veri bulunamadı.'));

    // Determine Layout
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isMobile = constraints.maxWidth < 900;

        if (isMobile) {
          return Column(
            children: topStudents.asMap().entries.map((entry) {
              return Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: _buildCertificateCard(
                  entry.value,
                  entry.key + 1,
                  isGeneral,
                ),
              );
            }).toList(),
          );
        } else {
          if (limit <= 3) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: topStudents.asMap().entries.map((entry) {
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: _buildCertificateCard(
                      entry.value,
                      entry.key + 1,
                      isGeneral,
                    ),
                  ),
                );
              }).toList(),
            );
          } else {
            return Center(
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: topStudents.asMap().entries.map((entry) {
                  return SizedBox(
                    width: 280,
                    child: _buildCertificateCard(
                      entry.value,
                      entry.key + 1,
                      isGeneral,
                    ),
                  );
                }).toList(),
              ),
            );
          }
        }
      },
    );
  }

  Widget _buildCertificateCard(
    Map<String, dynamic> student,
    int displayRank,
    bool isGeneral,
  ) {
    Color medalColor = Colors.indigo.shade300;
    IconData medalIcon = Icons.workspace_premium;
    if (displayRank == 1) {
      medalColor = const Color(0xFFFFD700); // Gold
      medalIcon = Icons.emoji_events;
    } else if (displayRank == 2) {
      medalColor = const Color(0xFFC0C0C0); // Silver
      medalIcon = Icons.emoji_events;
    } else if (displayRank == 3) {
      medalColor = const Color(0xFFCD7F32); // Bronze
      medalIcon = Icons.emoji_events;
    }

    String valueText = '';
    String labelText = '';

    if (isGeneral) {
      double score =
          double.tryParse(student['totalScore']?.toString() ?? '0') ?? 0;
      valueText = score.toStringAsFixed(3);
      labelText = 'Toplam Puan';
    } else {
      double net = 0;
      if (student['subjects'] is Map) {
        final subMap = student['subjects'][_certificateSelectedSubject];
        if (subMap is Map) {
          net = double.tryParse(subMap['net']?.toString() ?? '0') ?? 0;
        }
      }
      valueText = net.toStringAsFixed(2);
      labelText = '$_certificateSelectedSubject Net';
    }

    return Container(
      constraints: BoxConstraints(minHeight: 280),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
        border: Border.all(color: medalColor.withValues(alpha: 0.5), width: 2),
      ),
      child: Stack(
        children: [
          // Header background
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                color: medalColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 24),
              // Medal Icon
              CircleAvatar(
                radius: 36,
                backgroundColor: Colors.white,
                child: Icon(medalIcon, size: 40, color: medalColor),
              ),
              SizedBox(height: 16),
              // Name
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  student['studentName'] ?? 'İsimsiz',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade900,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(height: 4),
              Text(
                student['className'] ?? '',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 24),
              Divider(indent: 32, endIndent: 32),
              SizedBox(height: 16),
              // Score/Net
              Text(
                valueText,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Colors.indigo,
                ),
              ),
              Text(
                labelText,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              SizedBox(height: 24),
            ],
          ),
          // Rank Badge
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
              ),
              child: Text(
                '#$displayRank',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getSuccessColor(double rate) {
    if (rate >= 70) return Colors.green;
    if (rate >= 40) return Colors.orange;
    return Colors.red;
  }
  // --- Question Frequency Tab Implementation ---

  void _removeQuestionFrequencyStudentDropdownOverlay() {
    _questionFrequencyStudentDropdownOverlay?.remove();
    _questionFrequencyStudentDropdownOverlay = null;
  }

  void _showQuestionFrequencyStudentDropdownOverlay() {
    if (_questionFrequencyStudentDropdownOverlay != null) {
      _removeQuestionFrequencyStudentDropdownOverlay();
      return;
    }

    _questionFrequencyStudentDropdownOverlay = OverlayEntry(
      builder: (context) {
        String searchText = '';

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeQuestionFrequencyStudentDropdownOverlay,
                child: Container(color: Colors.transparent),
              ),
            ),
            CompositedTransformFollower(
              link: _questionFrequencyStudentLayerLink,
              showWhenUnlinked: false,
              offset: Offset(0, 50),
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
                child: Container(
                  width: 400,
                  height: 500,
                  constraints: BoxConstraints(maxHeight: 500),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: StatefulBuilder(
                    builder: (context, setStateOverlay) {
                      List<Map<String, dynamic>> filtered = _examResults.where((
                        s,
                      ) {
                        final name = (s['studentName'] ?? '')
                            .toString()
                            .toLowerCase();
                        final id = _getStudentId(s).toLowerCase();
                        final search = searchText.toLowerCase();
                        return name.contains(search) || id.contains(search);
                      }).toList();

                      Map<String, List<Map<String, dynamic>>> grouped = {};
                      for (var s in filtered) {
                        String className = s['className'] ?? 'Misafir';
                        if (className.isEmpty) className = 'Misafir';
                        grouped.putIfAbsent(className, () => []).add(s);
                      }

                      List<String> sortedClasses = grouped.keys.toList()
                        ..sort();

                      for (var key in grouped.keys) {
                        grouped[key]!.sort((a, b) {
                          return (a['studentName'] ?? '').toString().compareTo(
                            b['studentName'] ?? '',
                          );
                        });
                      }

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            decoration: InputDecoration(
                              hintText: 'Öğrenci Ara...',
                              prefixIcon: Icon(Icons.search, size: 20),
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 12,
                              ),
                            ),
                            onChanged: (val) {
                              setStateOverlay(() {
                                searchText = val;
                              });
                            },
                          ),
                          SizedBox(height: 8),
                          Divider(height: 1),
                          Expanded(
                            child: ListView(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              children: [
                                ListTile(
                                  dense: true,
                                  leading: Icon(
                                    Icons.people,
                                    color: Colors.indigo,
                                    size: 20,
                                  ),
                                  title: Text(
                                    'Tüm Öğrenciler',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  onTap: () {
                                    setState(() {
                                      _questionFrequencySelectedStudentId =
                                          'all';
                                    });
                                    _removeQuestionFrequencyStudentDropdownOverlay();
                                  },
                                ),
                                Divider(height: 1),
                                ...sortedClasses.map((className) {
                                  return Theme(
                                    data: Theme.of(context).copyWith(
                                      dividerColor: Colors.transparent,
                                    ),
                                    child: ExpansionTile(
                                      initiallyExpanded: searchText.isNotEmpty,
                                      title: Text(
                                        className,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.indigo.shade700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      children: grouped[className]!.map((s) {
                                        final sId = _getStudentId(s);
                                        return ListTile(
                                          dense: true,
                                          contentPadding: EdgeInsets.only(
                                            left: 16,
                                            right: 8,
                                          ),
                                          title: Text(
                                            s['studentName'] ?? '',
                                            style: TextStyle(fontSize: 13),
                                          ),
                                          onTap: () {
                                            setState(() {
                                              _questionFrequencySelectedStudentId =
                                                  sId;
                                            });
                                            _removeQuestionFrequencyStudentDropdownOverlay();
                                          },
                                          selected:
                                              _questionFrequencySelectedStudentId ==
                                              sId,
                                          selectedTileColor:
                                              Colors.indigo.shade50,
                                          selectedColor: Colors.indigo,
                                        );
                                      }).toList(),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_questionFrequencyStudentDropdownOverlay!);
  }

  Widget _buildQuestionFrequencyTab() {
    return Column(
      children: [
        // Top Filters
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildDropdown(
                      label: 'Kapsam',
                      value: _questionFrequencyScope,
                      items: ['Kurum', 'Şube', 'Öğrenci'],
                      onChanged: (val) {
                        setState(() {
                          _questionFrequencyScope = val!;
                          _questionFrequencySelectedBranchId = 'all';
                          _questionFrequencySelectedStudentId = 'all';
                        });
                      },
                    ),
                  ),
                  SizedBox(width: 16),
                  if (_questionFrequencyScope == 'Şube') ...[
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final branchNames = _examResults
                              .map((e) => e['className']?.toString())
                              .where((n) => n != null && n.isNotEmpty)
                              .map((n) => n!)
                              .toSet()
                              .toList();
                          branchNames.sort();

                          final dropdownItems = [
                            DropdownMenuItem<String>(
                              value: 'all',
                              child: Text('Tüm Şubeler'),
                            ),
                            ...branchNames.map(
                              (name) => DropdownMenuItem<String>(
                                value: name,
                                child: Text(name),
                              ),
                            ),
                          ];

                          return _buildDropdown(
                            label: 'Şube Seç',
                            value: _questionFrequencySelectedBranchId,
                            items: null,
                            dropdownItems: dropdownItems,
                            onChanged: (val) {
                              setState(() {
                                _questionFrequencySelectedBranchId = val!;
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                  if (_questionFrequencyScope == 'Öğrenci') ...[
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          String displayText = 'Tüm Öğrenciler';
                          if (_questionFrequencySelectedStudentId != 'all') {
                            final student = _examResults.firstWhere(
                              (s) =>
                                  _getStudentId(s) ==
                                  _questionFrequencySelectedStudentId,
                              orElse: () => {},
                            );
                            if (student.isNotEmpty) {
                              displayText =
                                  '${student['studentName']} (${student['className']})';
                            }
                          }
                          return CompositedTransformTarget(
                            link: _questionFrequencyStudentLayerLink,
                            child: _buildSearchableSelector(
                              label: 'Öğrenci Seç',
                              displayText: displayText,
                              onTap:
                                  _showQuestionFrequencyStudentDropdownOverlay,
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  if (_questionFrequencyScope == 'Kurum') const Spacer(),
                  const SizedBox(width: 12),
                  // Actions Menu (3-dots)
                  _buildActionMenuButton(
                    tooltip: 'Soru Frekans İşlemleri',
                    onSelected: (val) {
                      if (val == 'yazdir' || val == 'pdf') {
                        _exportQuestionFrequencyPdf();
                      } else if (val == 'excel') {
                        _exportQuestionFrequencyExcel();
                      } else if (val == 'paylas') {
                        _showShareDialog(
                          title: 'Soru Frekansları ve Madde Analizi',
                          reportType: 'Soru Frekansları',
                          getPdfBytes: () => _buildQuestionFrequencyPdfBytes(),
                          pdfFileName: 'soru_frekanslari_${_selectedExam?.name ?? "sinav"}.pdf',
                          getExcelBytes: () => _buildQuestionFrequencyExcelBytes(),
                          excelFileName: 'soru_frekanslari_${_selectedExam?.name ?? "sinav"}.xlsx',
                          onSharePdf: () => _exportQuestionFrequencyPdf(shareOnly: true),
                          onShareExcel: () => _exportQuestionFrequencyExcel(shareOnly: false),
                        );
                      }
                    },
                    items: [
                      _buildPopupItem('yazdir', Icons.print_rounded, Colors.blue.shade700, 'Yazdır'),
                      _buildPopupItem('pdf', Icons.picture_as_pdf_rounded, Colors.red.shade700, 'PDF İndir'),
                      _buildPopupItem('excel', Icons.table_chart_rounded, Colors.green.shade700, 'Excel İndir'),
                      _buildPopupItem('paylas', Icons.share_rounded, Colors.indigo.shade700, 'Paylaş'),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 16),
              // Subject Chips
              if (_availableSubjects.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                      },
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildLessonFilterChip(
                            label: 'Tümü',
                            isSelected:
                                _questionFrequencySelectedSubjects.length ==
                                _availableSubjects.length,
                            onSelected: (bool selected) {
                              setState(() {
                                if (selected) {
                                  _questionFrequencySelectedSubjects =
                                      List.from(_availableSubjects);
                                } else {
                                  _questionFrequencySelectedSubjects = [];
                                }
                              });
                            },
                          ),
                          Container(
                            height: 24,
                            width: 1,
                            color: Colors.grey.shade300,
                            margin: EdgeInsets.symmetric(horizontal: 12),
                          ),
                          ..._availableSubjects.map((subject) {
                            final isSelected =
                                _questionFrequencySelectedSubjects.contains(
                                  subject,
                                );
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: _buildLessonFilterChip(
                                label: subject,
                                isSelected: isSelected,
                                onSelected: (bool selected) {
                                  setState(() {
                                    _questionFrequencySelectedSubjects = [
                                      subject,
                                    ];
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        // Content
        Expanded(
          child: SingleChildScrollView(child: _buildQuestionFrequencyRow()),
        ),
      ],
    );
  }

  Widget _buildQuestionFrequencyRow() {
    List<String> subjectsToShow = [];
    if (_questionFrequencySelectedSubjects.isEmpty) {
      subjectsToShow = [];
    } else {
      subjectsToShow = _questionFrequencySelectedSubjects;
    }

    List<Map<String, dynamic>> relevantData = [];
    if (_questionFrequencyScope == 'Kurum') {
      relevantData = _examResults;
    } else if (_questionFrequencyScope == 'Şube') {
      if (_questionFrequencySelectedBranchId == 'all') {
        relevantData = _examResults;
      } else {
        relevantData = _examResults
            .where((r) => r['className'] == _questionFrequencySelectedBranchId)
            .toList();
      }
    } else if (_questionFrequencyScope == 'Öğrenci') {
      if (_questionFrequencySelectedStudentId == 'all') {
        relevantData = _examResults;
      } else {
        relevantData = _examResults
            .where(
              (r) => _getStudentId(r) == _questionFrequencySelectedStudentId,
            )
            .toList();
      }
    }

    if (relevantData.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Seçili kriterlere göre veri bulunamadı.'),
        ),
      );
    }

    bool isMobile = MediaQuery.of(context).size.width < 900;
    bool isAllView = subjectsToShow.length > 1;

    if (isAllView) {
      if (isMobile) {
        return Column(
          children: [
            _buildAnalysisCard(
              'Tüm Dersler',
              relevantData,
              isMobile: true,
              isFullWidth: true,
            ),
            SizedBox(height: 16),
            ...subjectsToShow.map((subject) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: _buildQuestionFrequencyTable(
                  subject,
                  relevantData,
                  isMobile: true,
                  onFullScreen: () => _openFullScreenQuestionFrequency(
                    subject,
                    relevantData,
                  ),
                ),
              );
            }).toList(),
          ],
        );
      } else {
        // Desktop All View
        return Container(
          height: _contentPanelHeight(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAnalysisCard(
                'Tüm Dersler',
                relevantData,
                isMobile: false,
                isFullWidth: false,
              ),
              Expanded(
                child: _buildQuestionFrequencyTable(
                  'Tüm Dersler', // Aggregate View
                  relevantData,
                  isMobile: false,
                  fitHeight: true,
                  onFullScreen: () => _openFullScreenQuestionFrequency(
                    'Tüm Dersler',
                    relevantData,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    } else {
      // Single Subject
      final subject = subjectsToShow[0];
      if (isMobile) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: _buildAnalysisCard(
                  subject,
                  relevantData,
                  isMobile: true,
                  isFullWidth: true,
                ),
              ),
              SizedBox(height: 16),
              _buildQuestionFrequencyTable(
                subject,
                relevantData,
                isMobile: true,
                onFullScreen: () => _openFullScreenQuestionFrequency(
                  subject,
                  relevantData,
                ),
              ),
            ],
          ),
        );
      } else {
        // Desktop Single View
        double sidebarW = _isSidebarVisible ? 320 : 0;
        double availableW = MediaQuery.of(context).size.width - sidebarW - 80;

        return Container(
          width: availableW,
          height: _contentPanelHeight(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAnalysisCard(subject, relevantData, isMobile: false),
              Expanded(
                child: _buildQuestionFrequencyTable(
                  subject,
                  relevantData,
                  isMobile: false,
                  fitHeight: true,
                  onFullScreen: () =>
                      _openFullScreenQuestionFrequency(subject, relevantData),
                ),
              ),
            ],
          ),
        );
      }
    }
  }


  Widget _buildQuestionFrequencyTable(
    String subject,
    List<Map<String, dynamic>> students, {
    bool isMobile = false,
    VoidCallback? onFullScreen,
    bool fitHeight = false,
  }) {
    return Card(
      margin: EdgeInsets.only(left: isMobile ? 0 : 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: fitHeight ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$subject - Soru Analizi',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                if (onFullScreen != null)
                  IconButton(
                    icon: const Icon(Icons.fullscreen, color: Colors.indigo),
                    onPressed: onFullScreen,
                    tooltip: 'Tam Ekran',
                  ),
              ],
            ),
            Divider(),
            fitHeight
                ? Expanded(
                    child: SingleChildScrollView(
                      child: _buildQuestionFrequencyTableContent(
                        subject,
                        students,
                        isMobile: isMobile,
                      ),
                    ),
                  )
                : _buildQuestionFrequencyTableContent(
                    subject,
                    students,
                    isMobile: isMobile,
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionFrequencyTableContent(
    String subject,
    List<Map<String, dynamic>> students, {
    bool isMobile = false,
    bool isFullScreen = false,
  }) {
    if (_selectedExam == null || students.isEmpty) return SizedBox();

    return LayoutBuilder(
      builder: (context, constraints) {
        // If "Tüm Dersler", we loop through selected subjects and build data for each
        if (subject == 'Tüm Dersler') {
          List<DataRow> allRows = [];
          for (var subj in _availableSubjects) {
            if (!_questionFrequencySelectedSubjects.contains(subj)) continue;
            var stats = _calculateQuestionStats(subj, students);
            if (stats.isEmpty) continue;

            List<DataRow> rows = _generateQuestionDataRows(
              stats,
              subjRows: true,
              isMobile: isMobile,
              parentWidth: constraints.maxWidth,
            );
            if (rows.isNotEmpty) {
              allRows.add(
                DataRow(
                  color: WidgetStateProperty.all(Colors.grey.shade100),
                  cells: [
                    DataCell(SizedBox()), // Soru
                    DataCell(
                      Text(
                        subj,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                          fontSize: 11,
                        ),
                      ),
                    ), // Kazanım (Subject name)
                    DataCell(SizedBox()), // Cevap
                    DataCell(SizedBox()), // Başarı
                    DataCell(SizedBox()), // A
                    DataCell(SizedBox()), // B
                    DataCell(SizedBox()), // C
                    DataCell(SizedBox()), // D
                    if (_hasEOption) DataCell(SizedBox()), // E
                    DataCell(SizedBox()), // Boş
                  ],
                ),
              );
              allRows.addAll(rows);
            }
          }
          return _buildQuestionDataTable(
            context,
            allRows,
            isMobile,
            isFullScreen,
            minWidth: constraints.maxWidth,
          );
        } else {
          var stats = _calculateQuestionStats(subject, students);
          List<DataRow> rows = _generateQuestionDataRows(
            stats,
            isMobile: isMobile,
            parentWidth: constraints.maxWidth,
          );
          return _buildQuestionDataTable(
            context,
            rows,
            isMobile,
            isFullScreen,
            minWidth: constraints.maxWidth,
          );
        }
      },
    );
  }

  // --- QUESTION STATS CALCULATION ---
  // Returns List of Map: { 'qNo': 1, 'key': 'A', 'dist': {'A': 50, 'B': 10...}, 'success': 80 }
  List<Map<String, dynamic>> _calculateQuestionStats(
    String subject,
    List<Map<String, dynamic>> students,
  ) {
    if (_selectedExam == null || _selectedExam!.outcomes.isEmpty) return [];

    // 1. Find Master Booklet (A)
    String refBooklet = _selectedExam!.outcomes.keys.firstWhere(
      (k) =>
          k.contains('A') && _selectedExam!.outcomes[k]!.containsKey(subject),
      orElse: () => _selectedExam!.outcomes.keys.first,
    );

    // 2. Get Master Answer Key and Outcome List
    // We need the ANSWER STRING for Booklet A, Subject S.
    // keys are in _selectedExam!.answerKeys ??
    if (!_selectedExam!.answerKeys.containsKey(refBooklet)) {
      return [];
    }
    String masterKey = _selectedExam!.answerKeys[refBooklet]![subject] ?? '';
    List<String> masterTopics =
        _selectedExam!.outcomes[refBooklet]![subject] ?? [];

    if (masterKey.isEmpty) return [];

    int qCount = masterKey.length;
    List<Map<String, dynamic>> stats = [];

    for (int i = 0; i < qCount; i++) {
      String correctAns = masterKey[i];
      String topic = i < masterTopics.length
          ? masterTopics[i]
          : 'Diğer'; // CAPTURE TOPIC

      int countA = 0;
      int countB = 0;
      int countC = 0;
      int countD = 0;
      int countE = 0;
      int countEmpty = 0;
      int total = 0;

      for (var student in students) {
        total++;
        String studentBooklet = student['booklet']?.toString() ?? 'A';
        // If student booklet is A (or ref), straightforward.
        // If B, we need to find which index corresponds to (Topic, CorrectAns).
        // Heuristic: If we can't map, we fallback to index i (assuming fixed order if map fails).

        String studentAnswerStr = '';
        // Extract answer string logic (reused)
        Map<String, dynamic> subMap = student['subjects'] ?? {};
        if (subMap[subject] != null) {
          var sData = subMap[subject];
          if (sData is Map) {
            // Try to find answers string
            if (sData['answers'] != null)
              studentAnswerStr = sData['answers'].toString();
            else if (sData['cevaplar'] != null)
              studentAnswerStr = sData['cevaplar'].toString();
            else if (sData['cevap_anahtari'] != null)
              studentAnswerStr = sData['cevap_anahtari'].toString();
          }
        }
        // Fallback to root answers
        if (studentAnswerStr.isEmpty) {
          if (student['answers'] is Map && student['answers'][subject] != null)
            studentAnswerStr = student['answers'][subject].toString();
        }

        if (studentAnswerStr.isEmpty) {
          countEmpty++;
          continue;
        }

        // Determine Index in Student Booklet
        int targetIndex = i; // Default to same index

        if (studentBooklet == refBooklet) {
          targetIndex = i;
        } else {
          // Try to map
          // We need Key and Topics for Student Booklet
          if (_selectedExam!.answerKeys.containsKey(studentBooklet) &&
              _selectedExam!.outcomes.containsKey(studentBooklet)) {
            // studKey not needed for mapping by Topic
            List<String> studTopics =
                _selectedExam!.outcomes[studentBooklet]![subject] ?? [];

            // Simple Search: Find N-th occurrence of Topic
            int masterTopicOccurrence = 0;
            for (int m = 0; m < i; m++) {
              if (m < masterTopics.length && masterTopics[m] == topic)
                masterTopicOccurrence++;
            }

            // Now find N-th occurrance of 'topic' in studTopics
            int currentOccurrence = 0;
            int foundIdx = -1;
            for (int sIdx = 0; sIdx < studTopics.length; sIdx++) {
              if (studTopics[sIdx] == topic) {
                if (currentOccurrence == masterTopicOccurrence) {
                  foundIdx = sIdx;
                  break;
                }
                currentOccurrence++;
              }
            }

            if (foundIdx != -1) {
              targetIndex = foundIdx;
            }
          }
        }

        // Get char at targetIndex
        if (targetIndex < studentAnswerStr.length) {
          String char = studentAnswerStr[targetIndex].toUpperCase();
          if (char == 'A')
            countA++;
          else if (char == 'B')
            countB++;
          else if (char == 'C')
            countC++;
          else if (char == 'D')
            countD++;
          else if (char == 'E')
            countE++;
          else
            countEmpty++;
        } else {
          countEmpty++;
        }
      }

      // Calculate distribution percentages
      double pctA = total > 0 ? (countA / total) * 100 : 0;
      double pctB = total > 0 ? (countB / total) * 100 : 0;
      double pctC = total > 0 ? (countC / total) * 100 : 0;
      double pctD = total > 0 ? (countD / total) * 100 : 0;
      double pctE = total > 0 ? (countE / total) * 100 : 0;
      double pctEmpty = total > 0 ? (countEmpty / total) * 100 : 0;

      // Success is the pct of the CORRECT answer
      double success = 0;
      if (correctAns == 'A')
        success = pctA;
      else if (correctAns == 'B')
        success = pctB;
      else if (correctAns == 'C')
        success = pctC;
      else if (correctAns == 'D')
        success = pctD;
      else if (correctAns == 'E')
        success = pctE;

      // --- ALTERNATE BOOKLET MAPPING ---
      // We want to show "1 - 6" where 1 is Booklet A index, and 6 is Booklet B index.
      // If multiple booklets exist, join them e.g. "1 - 6 - 4"
      List<String> displayQNos = [(i + 1).toString()]; // Start with Master

      // Identify other booklets
      List<String> otherBooklets =
          _selectedExam!.outcomes.keys
              .where(
                (k) =>
                    k != refBooklet &&
                    _selectedExam!.outcomes[k]!.containsKey(subject),
              )
              .toList()
            ..sort();

      for (var booklet in otherBooklets) {
        // Find index in 'booklet' that matches 'topic' and 'correctAns'
        // We use the same 'N-th occurrence' logic
        List<String> otherTopics =
            _selectedExam!.outcomes[booklet]![subject] ?? [];

        // Master occurrance
        int masterTopicOccurrence = 0;
        for (int m = 0; m < i; m++) {
          if (m < masterTopics.length && masterTopics[m] == topic)
            masterTopicOccurrence++;
        }

        int foundOtherIdx = -1;
        int currentOtherOccurrence = 0;
        for (int oIdx = 0; oIdx < otherTopics.length; oIdx++) {
          if (otherTopics[oIdx] == topic) {
            if (currentOtherOccurrence == masterTopicOccurrence) {
              foundOtherIdx = oIdx;
              break;
            }
            currentOtherOccurrence++;
          }
        }

        if (foundOtherIdx != -1) {
          displayQNos.add((foundOtherIdx + 1).toString());
        } else {
          displayQNos.add('-'); // Not found
        }
      }

      stats.add({
        'qNo': displayQNos.join(' - '), // "1 - 6"
        'topic': topic, // ADD TOPIC TO STATS
        'key': correctAns,
        'A': pctA,
        'B': pctB,
        'C': pctC,
        'D': pctD,
        'E': pctE,
        'Empty': pctEmpty,
        'Success': success,
      });
    }
    return stats;
  }

  List<DataRow> _generateQuestionDataRows(
    List<Map<String, dynamic>> stats, {
    bool subjRows = false,
    bool isMobile = false,
    double parentWidth = 0,
  }) {
    double otherCols = _hasEOption ? 490 : 430;
    double topicW = isMobile
        ? 280
        : (parentWidth - otherCols).clamp(180.0, double.infinity);

    return stats.map((row) {
      String key = row['key'] ?? '';
      // Helper to determine color
      // If colChar == key -> Green. Else -> Red (if >0 in strict mode, or just always red for wrong options?)
      // User: "yanlış cevaplar kırmızı".
      // Interpretation: Text color of option is Red if option != key. Green if option == key.

      Color getColor(String opt) {
        if (opt == key) return Colors.green.shade700;
        return Colors.red.shade700;
      }

      FontWeight getWeight(String opt) {
        if (opt == key) return FontWeight.bold;
        return FontWeight.normal;
      }

      return DataRow(
        cells: [
          DataCell(Text(row['qNo'].toString(), style: TextStyle(fontSize: 11))),
          DataCell(
            Container(
              width: topicW,
              child: Text(
                row['topic'] ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11),
              ),
            ),
          ),
          DataCell(
            Text(
              key,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade800,
                fontSize: 11,
              ),
            ),
          ),
          DataCell(
            Text(
              '%${(row['Success'] as double).toStringAsFixed(0)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _getSuccessColor(row['Success']),
                fontSize: 11,
              ),
            ),
          ),
          DataCell(
            Text(
              '%${(row['A'] as double).toStringAsFixed(0)}',
              style: TextStyle(
                color: getColor('A'),
                fontWeight: getWeight('A'),
                fontSize: 11,
              ),
            ),
          ),
          DataCell(
            Text(
              '%${(row['B'] as double).toStringAsFixed(0)}',
              style: TextStyle(
                color: getColor('B'),
                fontWeight: getWeight('B'),
                fontSize: 11,
              ),
            ),
          ),
          DataCell(
            Text(
              '%${(row['C'] as double).toStringAsFixed(0)}',
              style: TextStyle(
                color: getColor('C'),
                fontWeight: getWeight('C'),
                fontSize: 11,
              ),
            ),
          ),
          DataCell(
            Text(
              '%${(row['D'] as double).toStringAsFixed(0)}',
              style: TextStyle(
                color: getColor('D'),
                fontWeight: getWeight('D'),
                fontSize: 11,
              ),
            ),
          ),
          if (_hasEOption)
            DataCell(
              Text(
                '%${(row['E'] as double).toStringAsFixed(0)}',
                style: TextStyle(
                  color: getColor('E'),
                  fontWeight: getWeight('E'),
                  fontSize: 11,
                ),
              ),
            ),
          DataCell(
            Text(
              '%${(row['Empty'] as double).toStringAsFixed(0)}',
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ),
        ],
      );
    }).toList();
  }

  Widget _buildQuestionDataTable(
    BuildContext context,
    List<DataRow> rows,
    bool isMobile,
    bool isFullScreen, {
    double minWidth = 0,
  }) {
    Widget table = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth),
          child: DataTable(
            headingRowHeight: 40,
            dataRowHeight: 48,
            columnSpacing: 14,
            horizontalMargin: 8,
            columns: [
              DataColumn(
                label: Text(
                  'Soru',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                numeric: true,
              ),
              DataColumn(
                label: Text(
                  'Kazanım',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              DataColumn(
                label: Text(
                  'Cevap',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              DataColumn(
                label: Text(
                  'Başarı',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                numeric: true,
              ),
              DataColumn(
                label: Text(
                  'A',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                numeric: true,
              ),
              DataColumn(
                label: Text(
                  'B',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                numeric: true,
              ),
              DataColumn(
                label: Text(
                  'C',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                numeric: true,
              ),
              DataColumn(
                label: Text(
                  'D',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                numeric: true,
              ),
              if (_hasEOption)
                DataColumn(
                  label: Text(
                    'E',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                  numeric: true,
                ),
              DataColumn(
                label: Text(
                  'Boş',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                numeric: true,
              ),
            ],
            rows: rows,
          ),
        ),
      ),
    );

    if (isMobile && !isFullScreen) return table;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: table,
      ),
    );
  }
} // End Class

class _CursorTooltip extends StatefulWidget {
  final Widget child;
  final String message;

  const _CursorTooltip({required this.child, required this.message});

  @override
  _CursorTooltipState createState() => _CursorTooltipState();
}

class _CursorTooltipState extends State<_CursorTooltip> {
  OverlayEntry? _overlayEntry;
  final ValueNotifier<Offset> _positionNotifier = ValueNotifier(Offset.zero);

  void _showTooltip(PointerEnterEvent event) {
    _positionNotifier.value = event.position;
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return ValueListenableBuilder<Offset>(
          valueListenable: _positionNotifier,
          builder: (context, position, child) {
            return Positioned(
              left: position.dx + 16, // Offset to not cover cursor
              top: position.dy + 16,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: BoxConstraints(maxWidth: 300),
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    widget.message,
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideTooltip() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _updatePosition(PointerHoverEvent event) {
    // Update position efficienty via notifier
    _positionNotifier.value = event.position;
  }

  @override
  void dispose() {
    _hideTooltip();
    _positionNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _showTooltip,
      onExit: (e) => _hideTooltip(),
      onHover: _updatePosition,
      child: widget.child,
    );
  }
}
