import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../../services/assessment_service.dart';
import '../../../../models/assessment/trial_exam_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../services/pdf_service.dart';
import 'package:printing/printing.dart';

class CombinedExamResultsScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const CombinedExamResultsScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  _CombinedExamResultsScreenState createState() =>
      _CombinedExamResultsScreenState();
}

class _CombinedExamResultsScreenState extends State<CombinedExamResultsScreen>
    with SingleTickerProviderStateMixin {
  final AssessmentService _service = AssessmentService();
  final PdfService _pdfService = PdfService();

  // Filters
  String? _selectedClassLevel;
  String _selectedBranch = 'Tümü';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Data
  List<TrialExam> _allExams = [];
  List<TrialExam> _filteredExams = [];
  Set<String> _selectedExamIds = {};
  List<String> _branches = ['Tümü'];

  // Aggregated Data
  bool _isLoadingResults = false;
  List<Map<String, dynamic>> _aggregatedResults = [];
  List<String> _availableSubjects = [];
  Map<String, Map<String, double>> _examStats =
      {}; // examId -> {scoreAvg, netAvg, studentCount}
  List<TrialExam> _selectedExamsList = [];
  String _selectedAnalysisSubject = 'Tümü';
  Map<String, Map<String, dynamic>> _topicStats =
      {}; // subject -> topicName -> stats
  Map<String, Map<String, double>> _subjectExamStats =
      {}; // examId -> subjectName -> netAvg
  Map<String, Map<String, double>> _branchExamStats =
      {}; // examId -> branchName -> netAvg

  // Tabs
  late TabController _tabController;
  final List<String> _tabs = [
    'Genel Bakış',
    'Gelişim Trendi',
    'Şube Analizi',
    'Konu Analizi',
    'Sıralama',
  ];

  // Ranking Settings
  String _rankingMode = 'Puan'; // 'Puan' or 'Net'
  String _summaryInsightSubject = 'Tümü';
  String _selectedTrendSubject = 'Tümü';
  String _selectedBranchAnalysisSubject = 'Tümü';

  // Analysis Data
  List<Map<String, dynamic>> _risingStars = [];
  Map<String, int> _examParticipationRates = {};

  bool _isSidebarVisible = true;
  String _bestSortMode = 'Başarı %';
  String _worstSortMode = 'Başarı %';

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('tr_TR', null);
    _tabController = TabController(length: _tabs.length, vsync: this);
    _loadExams();
    _loadBranches();
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text.toLowerCase();
          _filterExams();
        });
      }
    });
  }

  Future<void> _loadExams() async {
    try {
      final stream = _service.getTrialExams(widget.institutionId);
      stream.listen((exams) {
        if (mounted) {
          setState(() {
            _allExams = exams;
            _filterExams();
          });
        }
      });
    } catch (e) {
      print('Error loading exams: $e');
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
          _branches = [
            'Tümü',
            ...snapshot.docs
                .map((doc) => doc['className']?.toString() ?? '')
                .where((n) => n.isNotEmpty)
                .toSet()
                .toList()
              ..sort(),
          ];
        });
      }
    } catch (e) {
      print('Error loading branches: $e');
    }
  }

  void _filterExams() {
    setState(() {
      _filteredExams = _allExams.where((exam) {
        final matchesClass =
            _selectedClassLevel == null ||
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
      _calculateAggregatedResults();
    });
  }

  void _calculateAggregatedResults() {
    if (_selectedExamIds.isEmpty) {
      setState(() {
        _aggregatedResults = [];
        _availableSubjects = [];
        _selectedExamsList = [];
        _examStats = {};
        _topicStats = {};
      });
      return;
    }

    setState(() => _isLoadingResults = true);

    List<TrialExam> selectedExams = _allExams
        .where((e) => _selectedExamIds.contains(e.id))
        .toList();
    selectedExams.sort((a, b) => a.date.compareTo(b.date));
    _selectedExamsList = selectedExams;

    Map<String, Map<String, dynamic>> studentDataMap = {};
    List<String> orderedSubjects = [];
    Set<String> foundBranches = {'Tümü'};
    Map<String, Map<String, double>> examStats = {};

    for (var exam in selectedExams) {
      if (exam.resultsJson != null && exam.resultsJson!.isNotEmpty) {
        try {
          final decoded = jsonDecode(exam.resultsJson!);
          if (decoded is List) {
            double totalScore = 0;
            double totalNet = 0;
            int examStudentCount = 0;

            for (var result in decoded) {
              // Collect subjects in order
              if (result['subjects'] != null && result['subjects'] is Map) {
                for (var k in (result['subjects'] as Map).keys) {
                  String s = k.toString().trim();
                  if (s.isNotEmpty && !orderedSubjects.contains(s)) {
                    orderedSubjects.add(s);
                  }
                }
              }

              // Extract data with robust field checking
              String branchName =
                  (result['branch'] ??
                          result['className'] ??
                          result['sınıf'] ??
                          '')
                      .toString()
                      .trim();
              if (branchName.isNotEmpty) foundBranches.add(branchName);

              // Apply global branch filter
              if (_selectedBranch != 'Tümü' && branchName != _selectedBranch)
                continue;

              String studentName =
                  result['name'] ?? result['studentName'] ?? '';
              String studentNo =
                  (result['studentNumber'] ??
                          result['number'] ??
                          result['no'] ??
                          '')
                      .toString();
              String key = studentNo.isNotEmpty ? studentNo : studentName;

              if (key.isEmpty) continue;

              examStudentCount++;
              double score =
                  num.tryParse(
                    (result['score'] ??
                            result['totalScore'] ??
                            result['puan'] ??
                            '0')
                        .toString(),
                  )?.toDouble() ??
                  0;

              double net = 0.0;
              if (result['subjects'] != null && result['subjects'] is Map) {
                for (var v in (result['subjects'] as Map).values) {
                  if (v is Map) {
                    net +=
                        num.tryParse(
                          (v['net'] ?? v['netler'] ?? '0').toString(),
                        )?.toDouble() ??
                        0.0;
                  }
                }
              } else {
                net =
                    num.tryParse(
                      (result['totalNet'] ??
                              result['net'] ??
                              result['netler'] ??
                              '0')
                          .toString(),
                    )?.toDouble() ??
                    0.0;
              }

              totalScore += score;
              totalNet += net;

              if (!studentDataMap.containsKey(key)) {
                studentDataMap[key] = {
                  'name': studentName.isEmpty ? 'İsimsiz Öğrenci' : studentName,
                  'no': studentNo,
                  'branch': branchName.isEmpty ? 'Şubesiz' : branchName,
                  'exams': <String, dynamic>{},
                };
              }

              studentDataMap[key]!['exams'][exam.id] = {
                'score': score,
                'net': net,
                'raw': result,
              };
            }

            if (examStudentCount > 0) {
              examStats[exam.id] = {
                'scoreAvg': totalScore / examStudentCount,
                'netAvg': totalNet / examStudentCount,
                'count': examStudentCount.toDouble(),
              };

              // Subject based stats for this exam
              Map<String, double> sTotals = {};
              Map<String, int> sCounts = {};

              for (var result in decoded) {
                String bName = (result['branch'] ?? result['className'] ?? '')
                    .toString()
                    .trim();
                if (_selectedBranch != 'Tümü' && bName != _selectedBranch)
                  continue;

                if (result['subjects'] != null && result['subjects'] is Map) {
                  for (var entry in (result['subjects'] as Map).entries) {
                    String sKey = entry.key.toString().trim();
                    var val = entry.value;
                    if (val is Map) {
                      double sNet =
                          num.tryParse(
                            (val['net'] ?? val['netler'] ?? '0').toString(),
                          )?.toDouble() ??
                          0.0;
                      sTotals[sKey] = (sTotals[sKey] ?? 0) + sNet;
                      sCounts[sKey] = (sCounts[sKey] ?? 0) + 1;
                    }
                  }
                }
              }

              Map<String, double> sAvgs = {};
              sTotals.forEach((s, total) {
                int count = sCounts[s] ?? 1;
                sAvgs[s] = total / count;
              });
              _subjectExamStats[exam.id] = sAvgs;

              // Branch based stats for this exam
              Map<String, double> bTotals = {};
              Map<String, int> bCounts = {};
              for (var result in decoded) {
                String bName =
                    (result['branch'] ?? result['className'] ?? 'Şubesiz')
                        .toString()
                        .trim();
                double studentNet = 0.0;
                if (result['subjects'] != null && result['subjects'] is Map) {
                  for (var v in (result['subjects'] as Map).values) {
                    if (v is Map) {
                      studentNet +=
                          num.tryParse(
                            (v['net'] ?? v['netler'] ?? '0').toString(),
                          )?.toDouble() ??
                          0.0;
                    }
                  }
                } else {
                  studentNet =
                      num.tryParse(
                        (result['totalNet'] ??
                                result['net'] ??
                                result['netler'] ??
                                '0')
                            .toString(),
                      )?.toDouble() ??
                      0.0;
                }

                bTotals[bName] = (bTotals[bName] ?? 0) + studentNet;
                bCounts[bName] = (bCounts[bName] ?? 0) + 1;
              }
              Map<String, double> bAvgs = {};
              bTotals.forEach(
                (b, total) => bAvgs[b] = total / (bCounts[b] ?? 1),
              );
              _branchExamStats[exam.id] = bAvgs;
            }
          }
        } catch (e) {
          print('Error parsing JSON for exam ${exam.id}: $e');
        }
      }
    }

    // Calculate Rising Stars
    List<Map<String, dynamic>> stars = [];
    studentDataMap.forEach((key, data) {
      Map exams = data['exams'];
      if (exams.length >= 2) {
        // Find first and last selected exams this student took
        var sortedExamIds = selectedExams
            .where((e) => exams.containsKey(e.id))
            .map((e) => e.id)
            .toList();
        if (sortedExamIds.length >= 2) {
          double firstNet = exams[sortedExamIds.first]['net'] ?? 0.0;
          double lastNet = exams[sortedExamIds.last]['net'] ?? 0.0;
          stars.add({
            'name': data['name'],
            'branch': data['branch'],
            'improvement': lastNet - firstNet,
            'firstNet': firstNet,
            'lastNet': lastNet,
          });
        }
      }
    });
    stars.sort(
      (a, b) =>
          (b['improvement'] as double).compareTo(a['improvement'] as double),
    );

    setState(() {
      _aggregatedResults = studentDataMap.values.toList();
      _availableSubjects = orderedSubjects;
      _examStats = examStats;
      _risingStars = stars.take(5).toList();
      _examParticipationRates = Map.fromIterables(
        examStats.keys,
        examStats.values.map((v) => (v['count'] as double).toInt()),
      );

      if (foundBranches.length > 1) {
        _branches = foundBranches.toList()..sort();
      }
      _calculateAllTopicStats(selectedExams);
      _isLoadingResults = false;
    });
  }

  void _calculateAllTopicStats(List<TrialExam> exams) {
    Map<String, Map<String, dynamic>> allSubjectStats = {};

    for (var subj in _availableSubjects) {
      Map<String, Map<String, dynamic>> aggregatedTopicsMap = {};

      for (var exam in exams) {
        if (exam.resultsJson == null) continue;

        // Don't use .contains() on raw JSON string as it misses escaped characters
        var results = _calculateExamTopicStats(subj, exam);
        var stats = results['stats'] as Map<String, Map<String, double>>;

        for (var entry in stats.entries) {
          final topic = entry.key;
          final data = entry.value;
          if (!aggregatedTopicsMap.containsKey(topic)) {
            aggregatedTopicsMap[topic] = {
              'correct': 0.0,
              'wrong': 0.0,
              'empty': 0.0,
              'count': 0,
            };
          }
          aggregatedTopicsMap[topic]!['correct'] += data['correct'] ?? 0;
          aggregatedTopicsMap[topic]!['wrong'] += data['wrong'] ?? 0;
          aggregatedTopicsMap[topic]!['empty'] += data['empty'] ?? 0;
          aggregatedTopicsMap[topic]!['count']++;
        }
      }
      allSubjectStats[subj] = aggregatedTopicsMap;
    }

    _topicStats = allSubjectStats;

    _topicStats = allSubjectStats;
  }

  String _turkishToLower(String text) {
    return text
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .replaceAll('Ğ', 'ğ')
        .replaceAll('Ü', 'ü')
        .replaceAll('Ş', 'ş')
        .replaceAll('Ö', 'ö')
        .replaceAll('Ç', 'ç')
        .toLowerCase();
  }

  Map<String, dynamic> _calculateExamTopicStats(
    String subject,
    TrialExam exam,
  ) {
    Map<String, Map<String, double>> stats = {};
    if (exam.resultsJson == null || exam.resultsJson!.isEmpty)
      return {'stats': stats};

    try {
      final decoded = jsonDecode(exam.resultsJson!);
      if (decoded is List) {
        String normSub = _turkishToLower(subject.trim());

        for (var student in decoded) {
          if (student is! Map<String, dynamic>) continue;

          String branchName =
              (student['branch'] ??
                      student['className'] ??
                      student['sınıf'] ??
                      '')
                  .toString();
          if (_selectedBranch != 'Tümü' && branchName != _selectedBranch)
            continue;

          String booklet = (student['booklet'] ?? student['kitapçık'] ?? 'A')
              .toString()
              .toUpperCase()
              .trim();
          if (!exam.outcomes.containsKey(booklet)) {
            if (exam.outcomes.isEmpty) continue;
            booklet = exam.outcomes.keys.first;
          }

          Map<String, dynamic> subMap = student['subjects'] ?? {};
          String? actualKey;

          if (subMap.containsKey(subject)) {
            actualKey = subject;
          } else {
            for (var k in subMap.keys) {
              String kNorm = _turkishToLower(k.toString().trim());
              if (kNorm == normSub ||
                  kNorm.contains(normSub) ||
                  normSub.contains(kNorm)) {
                actualKey = k.toString();
                break;
              }
            }
          }

          if (actualKey == null) continue;

          Map<String, List<String>>? bookOutcomes = exam.outcomes[booklet];
          Map<String, String>? bookKeys = exam.answerKeys[booklet];
          if (bookOutcomes == null || bookKeys == null) continue;

          List<String>? outcomesList;
          String? rawAnswerKey;

          for (var k in bookOutcomes.keys) {
            String bookKeyNorm = _turkishToLower(k.trim());
            if (bookKeyNorm == _turkishToLower(actualKey.trim()) ||
                bookKeyNorm.contains(normSub) ||
                normSub.contains(bookKeyNorm)) {
              outcomesList = bookOutcomes[k];
              rawAnswerKey = bookKeys[k];
              break;
            }
          }

          if (outcomesList == null || rawAnswerKey == null) continue;

          // EXTRACT STUDENT ANSWERS
          dynamic rawStudentAns;
          if (student['answers'] is Map &&
              student['answers'].containsKey(actualKey)) {
            rawStudentAns = student['answers'][actualKey];
          } else {
            var sData = subMap[actualKey];
            if (sData is Map) {
              rawStudentAns =
                  sData['answers'] ??
                  sData['cevaplar'] ??
                  sData['cevaplar_array'] ??
                  sData['studentAnswers'] ??
                  sData['choices'];
            }
          }

          if (rawStudentAns == null) continue;

          List<String> studentAnsList = [];
          if (rawStudentAns is List) {
            studentAnsList = rawStudentAns
                .map((e) => e.toString().toUpperCase().trim())
                .toList();
          } else {
            String ansStr = rawStudentAns.toString().toUpperCase();
            if (ansStr.contains(',')) {
              studentAnsList = ansStr.split(',').map((e) => e.trim()).toList();
            } else if (ansStr.contains('|')) {
              studentAnsList = ansStr.split('|').map((e) => e.trim()).toList();
            } else {
              if (ansStr.contains(' ') &&
                  ansStr.replaceAll(' ', '').length == outcomesList.length) {
                ansStr = ansStr.replaceAll(' ', '');
              }
              studentAnsList = ansStr.split('');
            }
          }

          // EXTRACT ANSWER KEY
          List<String> keyAnsList = [];
          String keyStr = rawAnswerKey.toUpperCase();
          if (keyStr.contains(',')) {
            keyAnsList = keyStr.split(',').map((e) => e.trim()).toList();
          } else if (keyStr.contains('|')) {
            keyAnsList = keyStr.split('|').map((e) => e.trim()).toList();
          } else {
            if (keyStr.contains(' ') &&
                keyStr.replaceAll(' ', '').length == outcomesList.length) {
              keyStr = keyStr.replaceAll(' ', '');
            }
            keyAnsList = keyStr.split('');
          }

          String mapChar(String c) {
            if (c == '1') return 'A';
            if (c == '2') return 'B';
            if (c == '3') return 'C';
            if (c == '4') return 'D';
            if (c == '5') return 'E';
            return c;
          }

          int len = outcomesList.length;
          for (int i = 0; i < len; i++) {
            String topic = outcomesList[i].trim();
            if (topic.isEmpty) topic = 'Diğer';

            stats.putIfAbsent(
              topic,
              () => {'correct': 0, 'wrong': 0, 'empty': 0},
            );

            String sAns = mapChar(
              i < studentAnsList.length ? studentAnsList[i] : '',
            );
            String kAns = mapChar(i < keyAnsList.length ? keyAnsList[i] : '');

            if (kAns.isEmpty) continue;

            if (kAns == sAns) {
              stats[topic]!['correct'] = (stats[topic]!['correct'] ?? 0) + 1;
            } else if (sAns.isEmpty ||
                sAns == ' ' ||
                sAns == '-' ||
                sAns == '.' ||
                sAns == '*') {
              stats[topic]!['empty'] = (stats[topic]!['empty'] ?? 0) + 1;
            } else {
              stats[topic]!['wrong'] = (stats[topic]!['wrong'] ?? 0) + 1;
            }
          }
        }
      }
    } catch (e) {
      print('Error parsing topic stats: $e');
    }
    return {'stats': stats};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isMobile = constraints.maxWidth < 900;
            return Row(
              children: [
                if (_isSidebarVisible || !isMobile) _buildSidebar(isMobile),
                Expanded(
                  child: _selectedExamIds.isEmpty
                      ? _buildEmptyState()
                      : _buildMainContent(isMobile),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSidebar(bool isMobile) {
    return Container(
      width: isMobile ? MediaQuery.of(context).size.width : 320,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        children: [
          _buildSidebarHeader(),
          Expanded(child: _buildExamList()),
          if (_selectedExamIds.isNotEmpty && isMobile) _buildMobileShowButton(),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader() {
    final levels = _allExams.map((e) => e.classLevel).toSet().toList()..sort();
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade800, Colors.indigo.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_graph, color: Colors.white, size: 28),
              SizedBox(width: 10),
              Text(
                'Analiz Paneli',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Spacer(),
              if (_selectedExamIds.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.refresh, color: Colors.white),
                  onPressed: _calculateAggregatedResults,
                  tooltip: 'Yenile',
                ),
            ],
          ),
          SizedBox(height: 20),
          _buildFilterDropdown(
            'Sınıf Seviyesi',
            _selectedClassLevel,
            [
              DropdownMenuItem(value: null, child: Text('Tümü')),
              ...levels.map(
                (l) => DropdownMenuItem(value: l, child: Text('$l. Sınıf')),
              ),
            ],
            (val) => setState(() {
              _selectedClassLevel = val;
              _filterExams();
            }),
          ),
          SizedBox(height: 10),
          _buildSearchField(),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown<T>(
    String hint,
    T? value,
    List<DropdownMenuItem<T>> items,
    Function(T?) onChanged,
  ) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      dropdownColor: Colors.indigo.shade700,
      style: TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white60),
        filled: true,
        fillColor: Colors.white.withAlpha(40),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      style: TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Sınav ara...',
        hintStyle: TextStyle(color: Colors.white60),
        prefixIcon: Icon(Icons.search, color: Colors.white60),
        filled: true,
        fillColor: Colors.white.withAlpha(40),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        isDense: true,
      ),
    );
  }

  Widget _buildExamList() {
    return _filteredExams.isEmpty
        ? Center(
            child: Text(
              'Sınav bulunamadı',
              style: TextStyle(color: Colors.grey),
            ),
          )
        : ListView.separated(
            padding: EdgeInsets.symmetric(vertical: 10),
            itemCount: _filteredExams.length,
            separatorBuilder: (c, i) =>
                Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (context, index) {
              final exam = _filteredExams[index];
              final isSel = _selectedExamIds.contains(exam.id);
              return CheckboxListTile(
                value: isSel,
                onChanged: (v) => _onExamSelected(exam.id),
                activeColor: Colors.indigo,
                title: Text(
                  exam.name,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                subtitle: Text(
                  DateFormat('dd MMM yyyy').format(exam.date),
                  style: TextStyle(fontSize: 11),
                ),
                secondary: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: isSel
                        ? Colors.indigo.shade100
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('dd').format(exam.date),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isSel ? Colors.indigo : Colors.blueGrey,
                        ),
                      ),
                      Text(
                        DateFormat('MMM', 'tr_TR').format(exam.date),
                        style: TextStyle(
                          fontSize: 9,
                          color: isSel ? Colors.indigo : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
  }

  Widget _buildMobileShowButton() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ElevatedButton(
        onPressed: () => setState(() => _isSidebarVisible = false),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.indigo,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          minimumSize: Size(double.infinity, 50),
        ),
        child: Text(
          'Analizi Gör (${_selectedExamIds.length})',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.indigo.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.auto_awesome_motion,
              size: 80,
              color: Colors.indigo.withOpacity(0.4),
            ),
          ),
          SizedBox(height: 24),
          Text(
            ' Karşılaştırmaya Başla',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey.shade800,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Soldaki listeden en az iki sınav seçerek\ngelişim ve başarı grafiklerini görüntüleyebilirsin.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(bool isMobile) {
    if (_isLoadingResults) return Center(child: CircularProgressIndicator());

    return Column(
      children: [
        _buildContentTopBar(isMobile),
        _buildTabBar(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSummaryTab(isMobile),
              _buildProgressTab(),
              _buildBranchComparisonTab(),
              _buildTopicTab(isMobile),
              _buildRankingTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContentTopBar(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          if (isMobile)
            IconButton(
              icon: Icon(Icons.menu),
              onPressed: () => setState(() => _isSidebarVisible = true),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Birleştirilmiş Analiz Raporu',
                  style: TextStyle(
                    fontSize: isMobile ? 16 : 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${_selectedExamIds.length} Sınav • ${_aggregatedResults.length} Öğrenci',
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
          _buildGlobalBranchFilter(isMobile),
          SizedBox(width: 12),
          IconButton(
            icon: Icon(Icons.picture_as_pdf, color: Colors.indigo, size: 22),
            onPressed: () => _printAssessmentReport(), // Implement this
            tooltip: 'PDF Rapor İndir',
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalBranchFilter(bool isMobile) {
    if (isMobile) {
      return PopupMenuButton<String>(
        initialValue: _selectedBranch,
        icon: Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.indigo.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.filter_list, color: Colors.indigo, size: 20),
        ),
        tooltip: 'Şube Filtresi',
        onSelected: (v) => setState(() {
          _selectedBranch = v;
          _calculateAggregatedResults();
        }),
        itemBuilder: (context) => _branches
            .map((b) => PopupMenuItem(value: b, child: Text(b)))
            .toList(),
      );
    }

    return Container(
      width: 180,
      child: DropdownButtonFormField<String>(
        value: _selectedBranch,
        items: _branches
            .map(
              (b) => DropdownMenuItem(
                value: b,
                child: Text(b, style: TextStyle(fontSize: 13)),
              ),
            )
            .toList(),
        onChanged: (v) => setState(() {
          _selectedBranch = v!;
          _calculateAggregatedResults();
        }),
        decoration: InputDecoration(
          isDense: true,
          labelText: 'Şube Filtresi',
          labelStyle: TextStyle(fontSize: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        labelColor: Colors.indigo,
        unselectedLabelColor: Colors.grey,
        indicatorColor: Colors.indigo,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: TextStyle(fontWeight: FontWeight.bold),
        tabs: _tabs.map((t) => Tab(text: t)).toList(),
      ),
    );
  }

  Widget _buildSummaryTab(bool isMobile) {
    if (_examStats.isEmpty) return _buildNoDataPlaceholder();

    // Calc global averages
    double avgScore = 0;
    double avgNet = 0;
    for (var s in _examStats.values) {
      avgScore += s['scoreAvg']!;
      avgNet += s['netAvg']!;
    }
    avgScore /= _examStats.length;
    avgNet /= _examStats.length;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildQuickStatsSection(avgScore, avgNet),
          SizedBox(height: 32),
          _buildTopicInsights(isMobile),
          SizedBox(height: 32),
          if (isMobile) ...[
            _buildTopStudentsCard(),
            SizedBox(height: 16),
            _buildRisingStarsCard(),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildTopStudentsCard()),
                SizedBox(width: 16),
                Expanded(child: _buildRisingStarsCard()),
              ],
            ),
          SizedBox(height: 24),
          _buildParticipationInsights(),
          SizedBox(height: 32),
          Text(
            'Sınav Bazlı Performans',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          _buildExamSummaryList(),
        ],
      ),
    );
  }

  Widget _buildTopStudentsCard() {
    var sorted =
        _aggregatedResults.map((res) {
            final exams = res['exams'] as Map;
            double sum = 0;
            for (var v in exams.values) sum += (v['score'] as num).toDouble();
            return {
              'name': res['name'],
              'branch': res['branch'],
              'avg': exams.isEmpty ? 0 : sum / exams.length,
            };
          }).toList()
          ..sort((a, b) => (b['avg'] as double).compareTo(a['avg'] as double));

    var top5 = sorted.take(5).toList();

    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.indigo.withAlpha(20)),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events, color: Colors.amber, size: 24),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'En Başarılı 5 Öğrenci (Genel Ort.)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          ...top5.asMap().entries.map((e) {
            int rank = e.key + 1;
            var st = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: rank == 1
                          ? Colors.amber.withAlpha(40)
                          : Colors.grey.withAlpha(20),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      rank.toString(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: rank == 1
                            ? Colors.amber.shade900
                            : Colors.blueGrey,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          st['name'],
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          st['branch'],
                          style: TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    (st['avg'] as double).toStringAsFixed(1),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildRisingStarsCard() {
    if (_risingStars.isEmpty) return SizedBox.shrink();
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withAlpha(20)),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up, color: Colors.green, size: 24),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Gelişim Liderleri (+Net)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Icon(Icons.open_in_full, size: 18, color: Colors.green),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
                onPressed: _showFullImprovementReport,
                tooltip: 'Tümünü Gör',
              ),
            ],
          ),
          SizedBox(height: 16),
          ..._risingStars.map((st) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          st['name'],
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          st['branch'],
                          style: TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '+${(st['improvement'] as double).toStringAsFixed(1)} Net',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${st['firstNet'].toStringAsFixed(1)} → ${st['lastNet'].toStringAsFixed(1)}',
                        style: TextStyle(color: Colors.grey, fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildParticipationInsights() {
    if (_examParticipationRates.isEmpty) return SizedBox.shrink();
    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.indigo.shade900,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sınav Katılım Analizi',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Icon(Icons.groups, color: Colors.white70),
            ],
          ),
          SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  height: 180,
                  child: BarChart(
                    BarChartData(
                      gridData: FlGridData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (val, meta) {
                              int idx = val.toInt();
                              if (idx < 0 || idx >= _selectedExamsList.length)
                                return SizedBox();
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  'S${idx + 1}',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 10,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: _selectedExamsList.asMap().entries.map((e) {
                        final count = _examParticipationRates[e.value.id] ?? 0;
                        return BarChartGroupData(
                          x: e.key,
                          barRods: [
                            BarChartRodData(
                              toY: count.toDouble(),
                              color: Colors.amber,
                              width: 16,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 24),
              Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildParticipationStat(
                      'En Yüksek',
                      _examParticipationRates.values.fold(
                        0,
                        (max, v) => v > max ? v : max,
                      ),
                    ),
                    SizedBox(height: 12),
                    _buildParticipationStat(
                      'En Düşük',
                      _examParticipationRates.values.fold(
                        999,
                        (min, v) => v < min ? v : min,
                      ),
                    ),
                    SizedBox(height: 12),
                    _buildParticipationStat(
                      'Toplam Tekil',
                      _aggregatedResults.length,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildParticipationStat(String label, int value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.white60, fontSize: 11)),
        Text(
          value.toString(),
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  void _showFullImprovementReport() {
    List<Map<String, dynamic>> allImprovements = [];
    _aggregatedResults.forEach((res) {
      final exams = res['exams'] as Map;
      if (exams.length >= 2) {
        final sortedExams = exams.keys.toList()
          ..sort((a, b) {
            final examA = _selectedExamsList.firstWhere((e) => e.id == a);
            final examB = _selectedExamsList.firstWhere((e) => e.id == b);
            return examA.date.compareTo(examB.date);
          });
        double firstNet = (exams[sortedExams.first]['net'] as num).toDouble();
        double lastNet = (exams[sortedExams.last]['net'] as num).toDouble();
        allImprovements.add({
          'name': res['name'],
          'branch': res['branch'],
          'firstNet': firstNet,
          'lastNet': lastNet,
          'improvement': lastNet - firstNet,
        });
      }
    });

    allImprovements.sort(
      (a, b) =>
          (b['improvement'] as double).compareTo(a['improvement'] as double),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Öğrenci Gelişim Raporu'),
        content: Container(
          width: 600,
          height: 500,
          child: ListView.builder(
            itemCount: allImprovements.length,
            itemBuilder: (context, index) {
              final st = allImprovements[index];
              return ListTile(
                dense: true,
                title: Text(
                  st['name'],
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(st['branch']),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${st['improvement'] >= 0 ? '+' : ''}${st['improvement'].toStringAsFixed(1)} Net',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: st['improvement'] >= 0
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                    Text(
                      '${st['firstNet'].toStringAsFixed(1)} → ${st['lastNet'].toStringAsFixed(1)}',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Kapat'),
          ),
        ],
      ),
    );
  }

  Future<void> _printAssessmentReport() async {
    if (_selectedExamsList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rapor için en az bir sınav seçilmelidir.')),
      );
      return;
    }

    try {
      int tabIdx = _tabController.index;
      String tabName = _tabs[tabIdx];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$tabName Raporu hazırlanıyor...'),
          duration: Duration(seconds: 2),
        ),
      );

      Uint8List pdfBytes;

      switch (tabIdx) {
        case 0: // Genel Bakış
          double avgScore = 0, avgNet = 0;
          for (var s in _examStats.values) {
            avgScore += s['scoreAvg']!;
            avgNet += s['netAvg']!;
          }
          avgScore /= _examStats.length;
          avgNet /= _examStats.length;
          pdfBytes = await _pdfService.generateAssessmentReportPdf(
            exams: _selectedExamsList,
            students: _aggregatedResults,
            stats: _examStats,
            risingStars: _risingStars,
            avgScore: avgScore,
            avgNet: avgNet,
          );
          break;
        case 1: // Gelişim Trendi
          pdfBytes = await _pdfService.generateTrendReportPdf(
            exams: _selectedExamsList,
            examStats: _examStats,
            branchExamStats: _branchExamStats,
          );
          break;
        case 2: // Şube Analizi
          pdfBytes = await _pdfService.generateBranchReportPdf(
            exams: _selectedExamsList,
            branches: _branches,
            subjects: _availableSubjects,
            subjectExamStats: _subjectExamStats,
          );
          break;
        case 3: // Konu Analizi
          pdfBytes = await _pdfService.generateTopicReportPdf(
            topicStats: _topicStats,
            subjects: _availableSubjects,
          );
          break;
        case 4: // Sıralama
          pdfBytes = await _pdfService.generateRankingReportPdf(
            students: _aggregatedResults,
            mode: _rankingMode,
          );
          break;
        default:
          throw 'Bilinmeyen sekme';
      }

      await Printing.layoutPdf(
        onLayout: (format) => pdfBytes,
        name:
            'Analiz_Raporu_${tabName}_${DateFormat('dd_MM_yyyy').format(DateTime.now())}',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF oluşturulurken hata oluştu: $e')),
      );
    }
  }

  Widget _buildTopicInsights(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Konu Bazlı Analiz',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Theme(
              data: Theme.of(context).copyWith(
                canvasColor: Colors.white,
                hoverColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                focusColor: Colors.transparent,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _summaryInsightSubject,
                  dropdownColor: Colors.white,
                  focusColor: Colors.transparent,
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    size: 18,
                    color: Colors.indigo,
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.indigo,
                    fontWeight: FontWeight.w600,
                  ),
                  items: ['Tümü', ..._availableSubjects].map((s) {
                    return DropdownMenuItem(value: s, child: Text(s));
                  }).toList(),
                  onChanged: (v) => setState(() => _summaryInsightSubject = v!),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        _buildTopicInsightCards(isMobile),
      ],
    );
  }

  Widget _buildTopicInsightCards(bool isMobile) {
    // Collect all topics and their global average success
    Map<String, Map<String, double>> topicData = {};
    for (var entry in _topicStats.entries) {
      final subject = entry.key;
      if (_summaryInsightSubject != 'Tümü' && subject != _summaryInsightSubject)
        continue;

      final topics = entry.value;
      for (var topicEntry in topics.entries) {
        final topicName = topicEntry.key;
        final data = topicEntry.value;
        double corr = (data['correct'] as num).toDouble();
        double wrng = (data['wrong'] as num).toDouble();
        double empty = (data['empty'] as num).toDouble();
        double total = corr + wrng + empty;
        if (total > 0) {
          String key = _summaryInsightSubject == 'Tümü'
              ? '$subject - $topicName'
              : topicName;
          topicData[key] = {
            'pct': (corr / total) * 100,
            'corr': corr,
            'wrng': wrng,
            'missed':
                wrng +
                empty, // Number of items students failed to answer correctly
            'strength': corr, // Number of items students answered correctly
          };
        }
      }
    }

    if (topicData.isEmpty) return SizedBox.shrink();

    // Sorting Best Topics
    var sortedForBest = topicData.entries.toList();
    if (_bestSortMode == 'Başarı %') {
      sortedForBest.sort((a, b) => b.value['pct']!.compareTo(a.value['pct']!));
    } else {
      sortedForBest.sort(
        (a, b) => b.value['corr']!.compareTo(a.value['corr']!),
      );
    }

    // Sorting Worst Topics
    var sortedForWorst = topicData.entries.toList();
    if (_worstSortMode == 'Başarı %') {
      sortedForWorst.sort((a, b) => a.value['pct']!.compareTo(b.value['pct']!));
    } else {
      sortedForWorst.sort(
        (a, b) => b.value['wrng']!.compareTo(a.value['wrng']!),
      );
    }

    var best = sortedForBest.take(3).toList();

    // Filter out best topics from worst list to avoid contradiction
    var bestKeys = best.map((e) => e.key).toSet();
    var worst = sortedForWorst
        .where((e) => !bestKeys.contains(e.key))
        .take(3)
        .toList();

    if (isMobile) {
      return Column(
        children: [
          _buildInsightCard(
            'En Başarılı Konular',
            best,
            Colors.green,
            Icons.trending_up,
            sortMode: _bestSortMode,
            sortOptions: ['Başarı %', 'Doğru Sayısı'],
            onSortChanged: (v) => setState(() => _bestSortMode = v!),
          ),
          SizedBox(height: 16),
          _buildInsightCard(
            'Geliştirilmesi Gerekenler',
            worst,
            Colors.red,
            Icons.trending_down,
            sortMode: _worstSortMode,
            sortOptions: ['Başarı %', 'Yanlış Sayısı'],
            onSortChanged: (v) => setState(() => _worstSortMode = v!),
          ),
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _buildInsightCard(
              'En Başarılı Konular',
              best,
              Colors.green,
              Icons.trending_up,
              sortMode: _bestSortMode,
              sortOptions: ['Başarı %', 'Doğru Sayısı'],
              onSortChanged: (v) => setState(() => _bestSortMode = v!),
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: _buildInsightCard(
              'Geliştirilmesi Gerekenler',
              worst,
              Colors.red,
              Icons.trending_down,
              sortMode: _worstSortMode,
              sortOptions: ['Başarı %', 'Yanlış Sayısı'],
              onSortChanged: (v) => setState(() => _worstSortMode = v!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightCard(
    String title,
    List<MapEntry<String, Map<String, double>>> items,
    Color color,
    IconData icon, {
    required String sortMode,
    required List<String> sortOptions,
    required ValueChanged<String?> onSortChanged,
  }) {
    return Container(
      constraints: BoxConstraints(minHeight: 180),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(40), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(10),
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
              Container(
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: sortMode,
                  icon: Icon(Icons.sort, size: 14, color: color),
                  style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                  onChanged: onSortChanged,
                  items: sortOptions.map((o) {
                    return DropdownMenuItem(value: o, child: Text(o));
                  }).toList(),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          ...items.map((e) {
            double pct = e.value['pct']!;
            double corr = e.value['corr']!;
            double wrng = e.value['wrng']!;

            return Tooltip(
              message:
                  '${e.key}\nDoğru: ${corr.toInt()}, Yanlış: ${wrng.toInt()}, Başarı: %${pct.toStringAsFixed(1)}',
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.key,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.blueGrey.shade800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          '%${pct.toStringAsFixed(1)}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildQuickStatsSection(double avgScore, double avgNet) {
    return Row(
      children: [
        _buildStatCard(
          'Genel Puan Ort.',
          avgScore.toStringAsFixed(1),
          Icons.stars,
          Colors.amber,
        ),
        SizedBox(width: 16),
        _buildStatCard(
          'Genel Net Ort.',
          avgNet.toStringAsFixed(1),
          Icons.bolt,
          Colors.green,
        ),
        SizedBox(width: 16),
        _buildStatCard(
          'Toplam Katılım',
          _aggregatedResults.length.toString(),
          Icons.people,
          Colors.blue,
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color),
            ),
            SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(title, style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildExamSummaryList() {
    return GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        mainAxisExtent: 140,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _selectedExamsList.length,
      itemBuilder: (c, i) {
        final ex = _selectedExamsList[i];
        final stat =
            _examStats[ex.id] ?? {'scoreAvg': 0.0, 'netAvg': 0.0, 'count': 0.0};
        return Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ex.name,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildMiniStat(
                    'Ort. Puan',
                    stat['scoreAvg']!.toStringAsFixed(1),
                    Colors.amber,
                  ),
                  _buildMiniStat(
                    'Ort. Net',
                    stat['netAvg']!.toStringAsFixed(1),
                    Colors.green,
                  ),
                  _buildMiniStat(
                    'Öğrenci',
                    stat['count']!.toInt().toString(),
                    Colors.grey,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMiniStat(String label, String val, Color col) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey)),
        Text(
          val,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: col,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Gelişim Trendi',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              Theme(
                data: Theme.of(context).copyWith(
                  canvasColor: Colors.white,
                  hoverColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  focusColor: Colors.transparent,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedTrendSubject,
                    dropdownColor: Colors.white,
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      size: 18,
                      color: Colors.indigo,
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.indigo,
                      fontWeight: FontWeight.w600,
                    ),
                    items: ['Tümü', ..._availableSubjects].map((s) {
                      return DropdownMenuItem(value: s, child: Text(s));
                    }).toList(),
                    onChanged: (v) =>
                        setState(() => _selectedTrendSubject = v!),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 24),
          if (_selectedTrendSubject == 'Tümü') ...[
            _buildChartCard(
              'Puan Trendi',
              Colors.indigo,
              'scoreAvg',
              Icons.show_chart,
            ),
            SizedBox(height: 24),
          ],
          _buildChartCard(
            _selectedTrendSubject == 'Tümü'
                ? 'Genel Net Trendi'
                : '$_selectedTrendSubject Net Trendi',
            Colors.teal,
            'netAvg',
            Icons.auto_graph,
            subject: _selectedTrendSubject,
          ),
          SizedBox(height: 24),
          _buildBranchProgressChart(),
        ],
      ),
    );
  }

  Widget _buildBranchProgressChart() {
    if (_branches.length <= 1) return SizedBox.shrink();

    // 1. Calculate Min/Max for Dynamic Y-Axis
    double minVal = double.infinity;
    double maxVal = double.negativeInfinity;
    bool hasData = false;

    // Filter branches excluding 'Tümü'
    var activeBranches = _branches.where((b) => b != 'Tümü').toList();

    for (var bName in activeBranches) {
      for (var exam in _selectedExamsList) {
        double? val = _branchExamStats[exam.id]?[bName];
        if (val != null) {
          if (val < minVal) minVal = val;
          if (val > maxVal) maxVal = val;
          hasData = true;
        }
      }
    }

    // Defaults if no data found
    if (!hasData) {
      minVal = 0;
      maxVal = 100;
    }

    // Add buffer to min/max so lines don't touch the edges
    double buffer = (maxVal - minVal) * 0.1;
    if (buffer < 2) buffer = 5; // Minimum buffer

    double chartMinY = (minVal - buffer).floorToDouble();
    double chartMaxY = (maxVal + buffer).ceilToDouble();
    if (chartMinY < 0) chartMinY = 0; // Don't go below zero

    // 2. Larger Color Palette
    final List<Color> distinctColors = [
      Colors.blue.shade700,
      Colors.red.shade700,
      Colors.green.shade700,
      Colors.orange.shade800,
      Colors.purple.shade700,
      Colors.teal.shade700,
      Colors.pink.shade700,
      Colors.brown.shade700,
      Colors.cyan.shade800,
      Colors.indigo.shade900,
      Colors.lime.shade800,
      Colors.amber.shade900,
      Colors.deepPurple.shade700,
      Colors.lightBlue.shade800,
      Colors.deepOrange.shade800,
      Colors.blueGrey.shade700,
      Colors.lightGreen.shade800,
      Colors.indigoAccent.shade700,
    ];

    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.indigo.withAlpha(20)),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.compare_arrows, color: Colors.indigo),
              SizedBox(width: 10),
              Text(
                'Şube Gelişim Kıyaslaması (Net)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SizedBox(height: 24),
          Container(
            height: 300,
            child: LineChart(
              LineChartData(
                minY: chartMinY,
                maxY: chartMaxY,
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (spot) => Colors.blueGrey.shade900,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        // Cast to LineBarSpot to get barIndex
                        final splitSpot = spot as LineBarSpot;
                        final String branchName =
                            activeBranches[splitSpot.barIndex];
                        return LineTooltipItem(
                          '$branchName: ${spot.y.toStringAsFixed(2)}',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: (chartMaxY - chartMinY) / 5,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(color: Colors.grey.shade200, strokeWidth: 1);
                  },
                ),
                titlesData: FlTitlesData(
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: (chartMaxY - chartMinY) / 5,
                      getTitlesWidget: (v, m) {
                        if (v == chartMinY || v == chartMaxY) return SizedBox();
                        return Text(
                          v.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (v, m) {
                        int idx = v.toInt();
                        if (idx < 0 || idx >= _selectedExamsList.length)
                          return SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'S${idx + 1}',
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: activeBranches.asMap().entries.map((branchEntry) {
                  String bName = branchEntry.value;
                  int bIdx = branchEntry.key;

                  Color color = distinctColors[bIdx % distinctColors.length];

                  return LineChartBarData(
                    spots: _selectedExamsList.asMap().entries.map((e) {
                      double val = _branchExamStats[e.value.id]?[bName] ?? 0;
                      return FlSpot(e.key.toDouble(), val);
                    }).toList(),
                    isCurved: true,
                    color: color,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: true),
                    belowBarData: BarAreaData(show: false),
                  );
                }).toList(),
              ),
            ),
          ),
          SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: activeBranches.asMap().entries.map((e) {
              Color color = distinctColors[e.key % distinctColors.length];
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 4),
                  Text(
                    e.value,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard(
    String title,
    Color color,
    String statKey,
    IconData icon, {
    String? subject,
  }) {
    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(30)),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(10),
            blurRadius: 15,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SizedBox(height: 32),
          SizedBox(
            height: 300,
            child: LineChart(
              LineChartData(
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (spot) => color,
                    getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
                      String val = statKey == 'scoreAvg'
                          ? s.y.toInt().toString()
                          : s.y.toStringAsFixed(1);
                      return LineTooltipItem(
                        val,
                        TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) =>
                      FlLine(color: Colors.grey.withAlpha(20), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 45,
                      getTitlesWidget: (v, m) {
                        if (statKey == 'scoreAvg') {
                          return Text(
                            v.toInt().toString(),
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          );
                        }
                        return Text(
                          v.toStringAsFixed(1),
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (v, m) {
                        int idx = v.toInt();
                        if (idx < 0 || idx >= _selectedExamsList.length)
                          return SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            DateFormat(
                              'dd.MM',
                            ).format(_selectedExamsList[idx].date),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: _selectedExamsList.asMap().entries.map((e) {
                      double val = 0;
                      if (subject != null &&
                          subject != 'Tümü' &&
                          statKey == 'netAvg') {
                        // Find matching subject key with turkish comparison
                        String normTarget = _turkishToLower(subject);
                        Map<String, double> sStats =
                            _subjectExamStats[e.value.id] ?? {};
                        for (var entry in sStats.entries) {
                          String kNorm = _turkishToLower(entry.key);
                          if (kNorm == normTarget ||
                              kNorm.contains(normTarget) ||
                              normTarget.contains(kNorm)) {
                            val = entry.value;
                            break;
                          }
                        }
                      } else {
                        val = _examStats[e.value.id]?[statKey] ?? 0;
                      }
                      return FlSpot(e.key.toDouble(), val);
                    }).toList(),
                    color: color,
                    barWidth: 4,
                    isCurved: true,
                    curveSmoothness: 0.15,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                        radius: 6,
                        color: Colors.white,
                        strokeWidth: 3,
                        strokeColor: color,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [color.withAlpha(50), color.withAlpha(0)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, Map<String, double>> _calculateBranchStats() {
    Map<String, List<double>> branchScores = {};
    Map<String, List<double>> branchNets = {};
    Map<String, int> branchStudentCounts = {};

    for (var result in _aggregatedResults) {
      final branch = (result['branch'] ?? 'Şubesiz').toString().trim();
      final exams = result['exams'] as Map<String, dynamic>;

      branchScores.putIfAbsent(branch, () => []);
      branchNets.putIfAbsent(branch, () => []);
      branchStudentCounts.update(
        branch,
        (value) => value + 1,
        ifAbsent: () => 1,
      );

      double totalScore = 0;
      double totalNet = 0;
      int examCountForStudent = 0;

      for (var examData in exams.values) {
        if (_selectedBranchAnalysisSubject == 'Tümü') {
          totalScore += (examData['score'] as num).toDouble();
          totalNet += (examData['net'] as num).toDouble();
          examCountForStudent++;
        } else {
          // Calculate specific subject net
          var raw = examData['raw'];
          if (raw != null && raw['subjects'] is Map) {
            String normTarget = _turkishToLower(_selectedBranchAnalysisSubject);
            Map subMap = raw['subjects'];
            for (var entry in subMap.entries) {
              String kNorm = _turkishToLower(entry.key.toString());
              if (kNorm == normTarget ||
                  kNorm.contains(normTarget) ||
                  normTarget.contains(kNorm)) {
                var val = entry.value;
                if (val is Map) {
                  double sNet =
                      num.tryParse(
                        (val['net'] ?? val['netler'] ?? '0').toString(),
                      )?.toDouble() ??
                      0.0;
                  totalNet += sNet;
                  examCountForStudent++;
                  break;
                }
              }
            }
          }
        }
      }

      if (examCountForStudent > 0) {
        if (_selectedBranchAnalysisSubject == 'Tümü') {
          branchScores[branch]!.add(totalScore / examCountForStudent);
        }
        branchNets[branch]!.add(totalNet / examCountForStudent);
      }
    }

    Map<String, Map<String, double>> finalStats = {};
    for (var entry in branchScores.entries) {
      final branch = entry.key;
      final scores = entry.value;

      double avgScore = scores.isEmpty
          ? 0.0
          : scores.reduce((a, b) => a + b) / scores.length;
      double avgNet = branchNets[branch]!.isEmpty
          ? 0.0
          : branchNets[branch]!.reduce((a, b) => a + b) /
                branchNets[branch]!.length;
      finalStats[branch] = {
        'scoreAvg': avgScore,
        'netAvg': avgNet,
        'studentCount': branchStudentCounts[branch]!.toDouble(),
      };
    }

    return finalStats;
  }

  Widget _buildBranchComparisonTab() {
    var branchStats = _calculateBranchStats();
    if (branchStats.isEmpty) return _buildNoDataPlaceholder();

    var sortedBranches = branchStats.entries.toList()
      ..sort((a, b) => b.value['netAvg']!.compareTo(a.value['netAvg']!));

    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _selectedBranchAnalysisSubject == 'Tümü'
                      ? 'Şube Bazlı Başarı Sıralaması'
                      : '$_selectedBranchAnalysisSubject Şube Sıralaması',
                  style: TextStyle(
                    fontSize: MediaQuery.of(context).size.width < 600 ? 14 : 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Theme(
                data: Theme.of(context).copyWith(
                  canvasColor: Colors.white,
                  hoverColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  focusColor: Colors.transparent,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedBranchAnalysisSubject,
                    dropdownColor: Colors.white,
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      size: 18,
                      color: Colors.indigo,
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.indigo,
                      fontWeight: FontWeight.w600,
                    ),
                    items: ['Tümü', ..._availableSubjects].map((s) {
                      return DropdownMenuItem(
                        value: s,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: 100),
                          child: Text(
                            s,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (v) =>
                        setState(() => _selectedBranchAnalysisSubject = v!),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          _buildBranchBarChart(sortedBranches),
          SizedBox(height: 32),
          _buildBranchTable(sortedBranches),
        ],
      ),
    );
  }

  Widget _buildBranchBarChart(
    List<MapEntry<String, Map<String, double>>> data,
  ) {
    return Container(
      height: 300,
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10),
        ],
      ),
      child: BarChart(
        BarChartData(
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) => Colors.blueGrey.shade900,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  rod.toY.toStringAsFixed(2),
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, m) {
                  int idx = v.toInt();
                  if (idx < 0 || idx >= data.length) return SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      data[idx].key,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: data.asMap().entries.map((e) {
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: e.value.value['netAvg']!,
                  color: Colors.indigo,
                  width: 25,
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildBranchTable(List<MapEntry<String, Map<String, double>>> data) {
    bool isSubject = _selectedBranchAnalysisSubject != 'Tümü';

    // Define headers
    List<Widget> headers = [
      Text('Şube', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      Text('Öğr.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      if (!isSubject)
        Text(
          'Puan',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
      Text(
        isSubject ? '$_selectedBranchAnalysisSubject Net' : 'Net',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        textAlign: TextAlign.center,
      ),
      ..._selectedExamsList.asMap().entries.map((e) {
        return Text(
          'S${e.key + 1}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: Colors.indigo,
          ),
        );
      }),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          // Header
          _buildCustomTableRow(headers, isHeader: true),
          Divider(color: Colors.grey.shade200),
          // Rows
          ...data.map((e) {
            String bName = e.key;

            List<Widget> cells = [
              Text(
                bName,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              Text(
                e.value['studentCount']!.toInt().toString(),
                style: TextStyle(fontSize: 12),
              ),
              if (!isSubject)
                Text(
                  e.value['scoreAvg']!.toStringAsFixed(1),
                  style: TextStyle(fontSize: 12),
                ),
              Text(
                e.value['netAvg']!.toStringAsFixed(2),
                style: TextStyle(
                  color: Colors.indigo,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              ..._selectedExamsList.map((exam) {
                double val = _getBranchExamNet(bName, exam.id);
                return Text(
                  val.toStringAsFixed(2),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                );
              }),
            ];

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: _buildCustomTableRow(cells, isHeader: false),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCustomTableRow(List<Widget> cells, {bool isHeader = false}) {
    return Row(
      children: cells.asMap().entries.map((entry) {
        int idx = entry.key;
        Widget w = entry.value;

        // First column aligns left, others center
        CrossAxisAlignment align = idx == 0
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center;

        return Expanded(
          child: Column(crossAxisAlignment: align, children: [w]),
        );
      }).toList(),
    );
  }

  Widget _buildTopicTab(bool isMobile) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Konu Analizi',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                Theme(
                  data: Theme.of(context).copyWith(
                    canvasColor: Colors.white,
                    hoverColor: Colors.transparent,
                    splashColor: Colors.transparent,
                    focusColor: Colors.transparent,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedAnalysisSubject,
                      dropdownColor: Colors.white,
                      icon: Icon(
                        Icons.keyboard_arrow_down,
                        size: 18,
                        color: Colors.indigo,
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.indigo,
                        fontWeight: FontWeight.w600,
                      ),
                      items: ['Tümü', ..._availableSubjects].map((s) {
                        return DropdownMenuItem(value: s, child: Text(s));
                      }).toList(),
                      onChanged: (v) =>
                          setState(() => _selectedAnalysisSubject = v!),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: _selectedAnalysisSubject == 'Tümü'
                ? Column(
                    children: _availableSubjects
                        .map((s) => _buildTopicTable(s, isMobile))
                        .toList(),
                  )
                : _buildTopicTable(_selectedAnalysisSubject, isMobile),
          ),
          SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildTopicTable(String subject, bool isMobile) {
    final statsMap = _topicStats[subject] ?? {};
    if (statsMap.isEmpty) return SizedBox.shrink();

    // Sort by success percentage (ascending)
    final sortedEntries = statsMap.entries.toList()
      ..sort((a, b) {
        double aCorr = (a.value['correct'] as num).toDouble();
        double aTotal =
            aCorr +
            (a.value['wrong'] as num).toDouble() +
            (a.value['empty'] as num).toDouble();
        double aPct = aTotal > 0 ? (aCorr / aTotal) * 100 : 0;

        double bCorr = (b.value['correct'] as num).toDouble();
        double bTotal =
            bCorr +
            (b.value['wrong'] as num).toDouble() +
            (b.value['empty'] as num).toDouble();
        double bPct = bTotal > 0 ? (bCorr / bTotal) * 100 : 0;

        return aPct.compareTo(bPct);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            subject,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
          ),
        ),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: isMobile ? 24 : 48,
              horizontalMargin: 12,
              columns: [
                DataColumn(
                  label: Text(
                    'Konu',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(label: Text('Soru'), numeric: true),
                DataColumn(label: Text('Doğru'), numeric: true),
                DataColumn(label: Text('Yanlış'), numeric: true),
                DataColumn(label: Text('Başarı %'), numeric: true),
              ],
              rows: sortedEntries.map((e) {
                double corr = (e.value['correct'] as num).toDouble();
                double wrng = (e.value['wrong'] as num).toDouble();
                double empty = (e.value['empty'] as num).toDouble();
                double total = corr + wrng + empty;
                double pct = total > 0 ? (corr / total) * 100 : 0;
                return DataRow(
                  cells: [
                    DataCell(
                      Tooltip(
                        message: e.key,
                        child: Container(
                          width: isMobile ? 140 : 500,
                          child: Text(
                            e.key,
                            style: TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    DataCell(Text(total.toInt().toString())),
                    DataCell(
                      Text(
                        corr.toInt().toString(),
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        wrng.toInt().toString(),
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    DataCell(_buildSuccessBadge(pct)),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
        SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSuccessBadge(double value) {
    Color col = value >= 70
        ? Colors.green
        : (value >= 40 ? Colors.orange : Colors.red);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: col.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${value.toStringAsFixed(1)}%',
        style: TextStyle(color: col, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }

  Widget _buildRankingTab() {
    String dataKey = _rankingMode == 'Puan' ? 'score' : 'net';
    String avgKey = _rankingMode == 'Puan' ? 'avgScore' : 'avgNet';

    var sortedResults =
        _aggregatedResults.map((res) {
          final exams = res['exams'] as Map;
          double scoreSum = 0;
          double netSum = 0;
          for (var v in exams.values) {
            scoreSum += (v['score'] as num).toDouble();
            netSum += (v['net'] as num).toDouble();
          }
          return {
            ...res,
            'avgScore': exams.isEmpty ? 0.0 : scoreSum / exams.length,
            'avgNet': exams.isEmpty ? 0.0 : netSum / exams.length,
            'examCount': exams.length,
          };
        }).toList()..sort(
          (a, b) => (b[avgKey] as double).compareTo(a[avgKey] as double),
        );

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildRankingHeader(),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 20,
                  columns: [
                    DataColumn(label: Text('Sıra')),
                    DataColumn(label: Text('Öğrenci')),
                    DataColumn(label: Text('Şube')),
                    DataColumn(
                      label: Text(
                        _rankingMode == 'Puan' ? 'Ort. Puan' : 'Ort. Net',
                      ),
                    ),
                    ..._selectedExamsList.asMap().entries.map((e) {
                      return DataColumn(
                        label: Text(
                          'S${e.key + 1}\n(${DateFormat('dd.MM').format(e.value.date)})',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11),
                        ),
                      );
                    }),
                  ],
                  rows: sortedResults.asMap().entries.map((entry) {
                    int globalRank = entry.key + 1;
                    var res = entry.value;
                    final examsMap = res['exams'] as Map;

                    return DataRow(
                      cells: [
                        DataCell(
                          Text(
                            globalRank.toString(),
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataCell(
                          Text(
                            res['name'] ?? '',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataCell(Text(res['branch'] ?? '')),
                        DataCell(
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.indigo.withAlpha(20),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              (res[avgKey] as double).toStringAsFixed(1),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                              ),
                            ),
                          ),
                        ),
                        ..._selectedExamsList.asMap().entries.map((e) {
                          final examId = e.value.id;
                          final examData = examsMap[examId];
                          if (examData == null) return DataCell(Text('-'));

                          double currentVal = (examData[dataKey] as num)
                              .toDouble();

                          // Trend calculation
                          Widget? trendIcon;
                          if (e.key > 0) {
                            final prevExamId = _selectedExamsList[e.key - 1].id;
                            final prevData = examsMap[prevExamId];
                            if (prevData != null) {
                              double prevVal = (prevData[dataKey] as num)
                                  .toDouble();
                              if (currentVal > prevVal) {
                                trendIcon = Icon(
                                  Icons.trending_up,
                                  color: Colors.green,
                                  size: 14,
                                );
                              } else if (currentVal < prevVal) {
                                trendIcon = Icon(
                                  Icons.trending_down,
                                  color: Colors.red,
                                  size: 14,
                                );
                              }
                            }
                          }

                          return DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(currentVal.toStringAsFixed(1)),
                                if (trendIcon != null) ...[
                                  SizedBox(width: 4),
                                  trendIcon,
                                ],
                              ],
                            ),
                          );
                        }),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildRankingHeader() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Başarı Sıralaması',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Sıralama Modu:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              SizedBox(width: 12),
              Theme(
                data: Theme.of(context).copyWith(
                  canvasColor: Colors.white,
                  hoverColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  focusColor: Colors.transparent,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _rankingMode,
                    dropdownColor: Colors.white,
                    focusColor: Colors.transparent,
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      size: 18,
                      color: Colors.indigo,
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.indigo,
                      fontWeight: FontWeight.w600,
                    ),
                    items: ['Puan', 'Net'].map((mode) {
                      return DropdownMenuItem(value: mode, child: Text(mode));
                    }).toList(),
                    onChanged: (v) => setState(() => _rankingMode = v!),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoDataPlaceholder() {
    return Center(
      child: Text('Veri bulunamadı', style: TextStyle(color: Colors.grey)),
    );
  }

  double _getBranchExamNet(String branch, String examId) {
    double totalNet = 0;
    int count = 0;

    for (var student in _aggregatedResults) {
      // Check branch
      String sBranch = (student['branch'] ?? 'Şubesiz').toString().trim();
      if (sBranch != branch) continue;

      // Check exam
      Map exams = student['exams'];
      if (!exams.containsKey(examId)) continue;

      var examData = exams[examId];
      if (_selectedBranchAnalysisSubject == 'Tümü') {
        totalNet += (examData['net'] as num).toDouble();
      } else {
        // Specific subject net
        var raw = examData['raw'];
        if (raw != null && raw['subjects'] is Map) {
          String normTarget = _turkishToLower(_selectedBranchAnalysisSubject);
          Map subMap = raw['subjects'];
          bool found = false;
          for (var entry in subMap.entries) {
            String kNorm = _turkishToLower(entry.key.toString());
            if (kNorm == normTarget ||
                kNorm.contains(normTarget) ||
                normTarget.contains(kNorm)) {
              var val = entry.value;
              if (val is Map) {
                totalNet +=
                    num.tryParse(
                      (val['net'] ?? val['netler'] ?? '0').toString(),
                    )?.toDouble() ??
                    0.0;
                found = true;
                break;
              }
            }
          }
          if (!found) {
            // If subject not found for this student in this exam, add 0?
            // Yes, counts as 0 net.
          }
        }
      }
      count++;
    }

    if (count == 0) return 0.0;
    return totalNet / count;
  }
}
