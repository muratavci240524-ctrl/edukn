import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/assessment_service.dart';
import '../../../services/guidance_service.dart';
import '../../../models/assessment/trial_exam_model.dart';
import '../../../models/guidance/study_template_model.dart';
import '../../../models/assessment/outcome_list_model.dart';
import 'study_template_creation_screen.dart';
import 'saved_templates_screen.dart';
import 'saved_study_programs_screen.dart';
import '../../../services/gemini_service.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart'; // Added for compute

// Top-level function for compute
Uint8List _encodeZipIsolate(Map<String, Uint8List> files) {
  final archive = Archive();
  files.forEach((name, bytes) {
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  final encoder = ZipEncoder();
  return Uint8List.fromList(encoder.encode(archive)!);
}

class GuidanceStudyProgramScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  final String? initialStudentId;
  final String? initialExamName;
  final Map<String, int>? initialThresholds;

  const GuidanceStudyProgramScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    this.initialStudentId,
    this.initialExamName,
    this.initialThresholds,
  }) : super(key: key);

  @override
  State<GuidanceStudyProgramScreen> createState() =>
      _GuidanceStudyProgramScreenState();
}

class _GuidanceStudyProgramScreenState
    extends State<GuidanceStudyProgramScreen> {
  // Loading
  bool _isLoading = false;

  // Gemini AI State
  String? _geminiAnalysis;
  bool _isGeminiLoading = false;
  GeminiService _geminiService = GeminiService();

  // Data
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _filteredStudents = [];

  // Selections
  Set<String> _selectedStudentIds = {};

  // Program Data
  bool _isProgramGenerated = false;

  // Multi-Student Program Data
  List<Map<String, dynamic>> _generatedPrograms = [];
  List<Map<String, dynamic>> _historyPrograms = [];
  int _currentProgramIndex = 0;

  // Filters
  String _searchQuery = '';
  String? _selectedClassFilter;
  List<String> _classNames = [];

  // New State for Settings Panel
  Set<String> _allSubjects = {};
  Set<String> _hiddenSubjects = {};
  bool _isFullScreen = false;
  bool _isScheduleTableView = false; // false = list, true = table

  // Cache for Printing Assets
  pw.Font? _pdfFont;
  pw.Font? _pdfFontBold;
  pw.Font? _pdfFontItalic;
  pw.Font? _pdfFontIcons;
  pw.MemoryImage? _pdfLogo;

  @override
  void initState() {
    super.initState();
    _fetchStudents().then((_) {
      if (widget.initialStudentId != null) {
        _handleInitialRegeneration();
      }
    });
  }

  Future<void> _handleInitialRegeneration() async {
    final studentId = widget.initialStudentId!;
    setState(() {
      _selectedStudentIds = {studentId};
    });

    if (widget.initialExamName != null) {
      _startSingleExamProgramCreation(
        automatedExamName: widget.initialExamName,
        automatedThresholds: widget.initialThresholds,
      );
    }
  }

  bool _isOperationCancelled = false;

  Future<void> _fetchStudents() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final query = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true)
          .get();

      List<Map<String, dynamic>> loaded = [];
      Set<String> classes = {};

      for (var doc in query.docs) {
        final data = doc.data();
        final name =
            data['fullName'] ??
            '${data['name'] ?? ''} ${data['surname'] ?? ''}'.trim();

        // Robust branch/class name extraction
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
          // Normalize level (e.g. "12. Sınıf" -> "12")
          String levelDigits = rawLevel.replaceAll(RegExp(r'[^0-9]'), '');
          // If branch name doesn't contain the level (e.g. "A" vs "12-A"), prefix it
          if (levelDigits.isNotEmpty && !className.contains(levelDigits)) {
            className = "$levelDigits-$className";
          }
        }

        if (className != 'Sınıfsız' && className.isNotEmpty) {
          classes.add(className);
        }

        // Check if student has a study template assigned
        final hasTemplate = data['studyTemplateId'] != null;

        loaded.add({
          'id': doc.id,
          'name': name.isEmpty ? 'İsimsiz Öğrenci' : name,
          'class': className,
          'studentNo': data['studentNo'] ?? '',
          'hasTemplate': hasTemplate,
          'docData': data,
        });
      }

      // Sort by class then name
      loaded.sort((a, b) {
        int cmp = a['class'].compareTo(b['class']);
        if (cmp != 0) return cmp;
        return a['name'].compareTo(b['name']);
      });

      setState(() {
        _students = loaded;
        _classNames = classes.toList()..sort();
        _filterStudents();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching students: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterStudents() {
    setState(() {
      _filteredStudents = _students.where((s) {
        // Search Filter
        final matchesSearch =
            s['name'].toString().toLowerCase().contains(
              _searchQuery.toLowerCase(),
            ) ||
            s['studentNo'].toString().contains(_searchQuery);

        // Class Filter
        final matchesClass =
            _selectedClassFilter == null || s['class'] == _selectedClassFilter;

        return matchesSearch && matchesClass;
      }).toList();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedStudentIds.contains(id)) {
        _selectedStudentIds.remove(id);
      } else {
        _selectedStudentIds.add(id);
      }

      // If selection is not exactly one, reset the view
      if (_selectedStudentIds.length != 1) {
        _isProgramGenerated = false;
        _generatedPrograms = [];
      }
    });

    if (_selectedStudentIds.length == 1) {
      _checkForExistingProgram(_selectedStudentIds.first);
    }
  }

  Future<void> _checkForExistingProgram(String studentId) async {
    try {
      final programs = await GuidanceService().getStudentStudyPrograms(
        widget.institutionId,
        studentId,
      );

      // Verify assumption: Still single selected and same ID
      if (_selectedStudentIds.contains(studentId) &&
          _selectedStudentIds.length == 1) {
        setState(() {
          _historyPrograms = programs;
          // User requested NOT to auto-show the program.
          // Reset to "Create" view, but history is now available to click.
          _isProgramGenerated = false;
          _generatedPrograms = [];
        });
      }
    } catch (e) {
      debugPrint('Error fetching existing program: $e');
    }
  }

  // ==================== RESPONSIVE HELPERS ====================

  bool _isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  bool _isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 600 && width < 900;
  }

  // ==================== METHODS ====================

  void _selectAll() {
    setState(() {
      if (_selectedStudentIds.length == _filteredStudents.length) {
        _selectedStudentIds.clear();
      } else {
        _selectedStudentIds = _filteredStudents
            .map((e) => e['id'] as String)
            .toSet();
      }
      _isProgramGenerated = false;
      _generatedPrograms = [];
      _allSubjects.clear();
      _hiddenSubjects.clear();
    });
  }

  // Manual Editing
  void _editScheduleItem(String day, int index) {
    if (_generatedPrograms.isEmpty) return;

    final currentProgram = _generatedPrograms[_currentProgramIndex];
    final schedule = currentProgram['schedule'] as Map<String, dynamic>;
    // schedule values are List<dynamic> or List<String>
    List<dynamic> dayTasks = schedule[day] as List<dynamic>;

    final currentText = dayTasks[index].toString();
    final controller = TextEditingController(text: currentText);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 450,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.orange.shade700,
                      Colors.deepOrange.shade600,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.edit_note,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Görevi Düzenle',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '$day',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Content
              Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Görev İçeriği",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    SizedBox(height: 8),
                    TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        hintText: 'Ders ve konu detayları...',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                      maxLines: 4,
                    ),
                  ],
                ),
              ),

              // Actions
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(20),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Delete Button
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          dayTasks.removeAt(index);
                        });
                        Navigator.pop(ctx);
                      },
                      icon: Icon(Icons.delete_outline, color: Colors.red),
                      label: Text('Sil', style: TextStyle(color: Colors.red)),
                    ),

                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(
                            'İptal',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              dayTasks[index] = controller.text;
                            });
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade700,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          icon: Icon(Icons.save, size: 18),
                          label: Text('Değişiklikleri Kaydet'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- ANALYSIS HELPERS ---

  Map<String, dynamic>? _findStudentResult(
    List<dynamic> results,
    Map<String, dynamic> student,
  ) {
    // Support both 'studentNumber' and 'studentNo' keys in student docData
    String? sNo1 = student['docData']['studentNumber']?.toString().trim();
    String? sNo2 = student['docData']['studentNo']?.toString().trim();
    String sName = _normalize(student['name'] as String?);
    String? systemStudentId = student['id']?.toString();

    for (var r in results) {
      if (r is! Map) continue;
      final rMap = r as Map<String, dynamic>;

      // Priority 1: Match by systemStudentId
      if (systemStudentId != null && systemStudentId.isNotEmpty) {
        if (rMap['systemStudentId']?.toString() == systemStudentId) {
          return rMap;
        }
      }

      // Priority 2: Match by student number (try all known keys)
      String? rNo =
          (rMap['studentNo'] ??
                  rMap['studentNumber'] ??
                  rMap['number'] ??
                  rMap['no'])
              ?.toString()
              .trim();
      if (rNo != null && rNo.isNotEmpty) {
        if ((sNo1 != null && sNo1.isNotEmpty && sNo1 == rNo) ||
            (sNo2 != null && sNo2.isNotEmpty && sNo2 == rNo)) {
          return rMap;
        }
      }
    }

    // Priority 3: Match by normalized name
    for (var r in results) {
      if (r is! Map) continue;
      final rMap = r as Map<String, dynamic>;
      String rName = _normalize(
        (rMap['name'] ?? rMap['studentName'] ?? '') as String?,
      );
      if (rName.isNotEmpty && sName.isNotEmpty && rName == sName) {
        return rMap;
      }
    }

    return null;
  }

  Map<String, Map<String, dynamic>> _calculateTopicStats(
    Map<String, dynamic> studentResult,
    TrialExam exam,
    Map<String, dynamic> studentDocData,
    List<OutcomeList> allOutcomeLists,
  ) {
    // --- BOOKLET SELECTION FIX ---
    // booklet field may contain combined values like 'AB' (multi-session merge)
    // Take only the first letter as the actual booklet identifier.
    String rawBooklet = (studentResult['booklet'] ?? 'A')
        .toString()
        .toUpperCase()
        .trim();
    // Extract only the first valid single-character booklet letter
    String singleBooklet = rawBooklet.isNotEmpty ? rawBooklet[0] : 'A';

    // Find the actual booklet key in exam data
    String booklet = singleBooklet;
    if (!exam.outcomes.containsKey(booklet)) {
      // Try to find a matching key
      String? match;
      // 1. Exact match of single letter
      for (var k in exam.outcomes.keys) {
        if (k.toString().toUpperCase() == singleBooklet) {
          match = k;
          break;
        }
      }
      // 2. Key that contains the single letter
      if (match == null) {
        for (var k in exam.outcomes.keys) {
          if (k.toString().toUpperCase().contains(singleBooklet)) {
            match = k;
            break;
          }
        }
      }
      // 3. Fallback to 'A' or first available
      if (match == null) {
        match = exam.outcomes.containsKey('A')
            ? 'A'
            : (exam.outcomes.keys.isNotEmpty ? exam.outcomes.keys.first : 'A');
      }
      booklet = match;
    }

    Map<String, Map<String, dynamic>> topicStats = {};

    // Read answers and correctAnswers maps from studentResult
    // (stored by StudentResult.toJson() as Map<String, String>)
    final Map<String, dynamic> answersMap =
        (studentResult['answers'] as Map<String, dynamic>?) ?? {};
    final Map<String, dynamic> correctAnswersMap =
        (studentResult['correctAnswers'] as Map<String, dynamic>?) ?? {};

    // Helper: find a string value in a map by exact key, normalized match, or partial match
    String? _findInMap(Map<String, dynamic> map, String key) {
      if (map.containsKey(key)) return map[key]?.toString();
      final normKey = _normalize(key);
      for (var k in map.keys) {
        if (_normalize(k.toString()) == normKey) return map[k]?.toString();
      }
      for (var k in map.keys) {
        final normK = _normalize(k.toString());
        if (normK.contains(normKey) || normKey.contains(normK)) {
          return map[k]?.toString();
        }
      }
      return null;
    }

    if (exam.outcomes[booklet] == null) return topicStats;

    exam.outcomes[booklet]!.forEach((subj, outcomesList) {
      if (outcomesList.isEmpty) return;

      // --- Get student's answer string for this subject ---
      String answerStr = _findInMap(answersMap, subj) ?? '';

      // --- Get correct answer string ---
      // Priority 1: correctAnswers map from studentResult (most reliable)
      String? refKey = _findInMap(correctAnswersMap, subj);
      // Priority 2: fall back to exam.answerKeys
      if (refKey == null || refKey.isEmpty) {
        refKey = exam.answerKeys[booklet]?[subj];
        if (refKey == null || refKey.isEmpty) {
          final normSubj = _normalize(subj);
          for (var k in (exam.answerKeys[booklet]?.keys ?? <String>[])) {
            if (_normalize(k) == normSubj) {
              refKey = exam.answerKeys[booklet]![k];
              break;
            }
          }
        }
      }

      if (refKey == null || refKey.isEmpty) return; // skip this subject

      answerStr = answerStr.toUpperCase();
      refKey = refKey.toUpperCase();

      // Use the shorter of: outcomes list length, answer key length
      int len = outcomesList.length;
      if (refKey.length < len) len = refKey.length;
      // Pad answerStr if shorter than len (treat missing as empty)
      if (answerStr.length < len) {
        answerStr = answerStr.padRight(len, ' ');
      }

      debugPrint('    => len=$len, answerStr="$answerStr", refKey="$refKey"');

      String sClass = studentDocData['classLevel'] ?? '';
      String? sClassNum = _extractClassLevel(sClass);
      String sClassNorm = _normalize(sClass);
      String normSubj = _normalize(subj);

      final validLists = allOutcomeLists.where((l) {
        String lClassNorm = _normalize(l.classLevel);
        String? lClassNum = _extractClassLevel(l.classLevel);

        bool cMatch =
            lClassNorm == sClassNorm ||
            (sClassNum != null && lClassNum == sClassNum) ||
            lClassNorm.contains(sClassNorm) ||
            sClassNorm.contains(lClassNorm);

        String normBranch = _normalize(l.branchName);
        String normList = _normalize(l.name);

        bool sMatch =
            normBranch == normSubj ||
            normList.contains(normSubj) ||
            normSubj.contains(normBranch);
        return cMatch && sMatch;
      }).toList();

      for (int k = 0; k < len; k++) {
        String studentChar = answerStr[k];
        String topic = outcomesList[k];

        if (topic.isEmpty) topic = 'Diğer';

        try {
          String? foundTopic;
          String searchOutcome = _normalize(topic);

          for (var oList in validLists) {
            int idx = oList.outcomes.indexWhere((item) {
              String d = _normalize(item.description);
              return d == searchOutcome ||
                  d.contains(searchOutcome) ||
                  searchOutcome.contains(d);
            });

            if (idx != -1) {
              String kazanim = oList.outcomes[idx].description;
              String? uniteAdi;
              for (int i = idx; i >= 0; i--) {
                if (oList.outcomes[i].depth == 1) {
                  uniteAdi = oList.outcomes[i].description;
                  break;
                }
              }
              if (uniteAdi != null) {
                foundTopic = '$uniteAdi ($kazanim)';
              } else {
                foundTopic = kazanim;
              }
            }
            if (foundTopic != null) break;
          }

          if (foundTopic != null) {
            topic = foundTopic;
          } else {
            if (topic.contains(' - ')) {
              List<String> parts = topic.split(' - ');
              topic = parts.last.trim();
            } else if (topic.contains(':')) {
              topic = topic.split(':').last.trim();
            }
          }
        } catch (e) {
          debugPrint('Topic lookup error: $e');
        }

        String uniqueKey = "$subj|$topic";

        if (!topicStats.containsKey(uniqueKey)) {
          topicStats[uniqueKey] = {
            'subject': subj,
            'topic': topic,
            'total': 0,
            'correct': 0,
            'wrong': 0,
            'empty': 0,
          };
        }

        topicStats[uniqueKey]!['total']++;

        final status = TrialExam.evaluateAnswer(studentChar, refKey[k]);
        bool isCorrect = status == AnswerStatus.correct;
        bool isEmpty = status == AnswerStatus.empty;
        bool isWrong = status == AnswerStatus.wrong;

        if (isCorrect)
          topicStats[uniqueKey]!['correct']++;
        else if (isWrong)
          topicStats[uniqueKey]!['wrong']++;
        else if (isEmpty)
          topicStats[uniqueKey]!['empty']++;
      }
    });

    return topicStats;
  }

  List<Map<String, dynamic>> _generateAnalysisList(
    Map<String, Map<String, dynamic>> topicStats,
  ) {
    List<Map<String, dynamic>> analysisList = topicStats.values.map((e) {
      int d = e['correct'];
      int y = e['wrong'];
      int total = e['total'];
      double net = d - (y / 3.0);
      double success = total == 0 ? 0 : (d / total) * 100;
      return {...e, 'net': net, 'success': success};
    }).toList();

    analysisList.sort((a, b) {
      int cmp = (a['success'] as num).compareTo(b['success'] as num);
      if (cmp != 0) return cmp;
      return (b['wrong'] as int).compareTo(a['wrong'] as int);
    });
    return analysisList;
  }

  Map<String, List<String>> _generateScheduleFromAnalysis(
    List<Map<String, dynamic>> analysisList,
    StudyTemplate template, {
    Map<String, int>? thresholds,
  }) {
    Map<String, List<Map<String, dynamic>>> prioritizedTopicsBySubject = {};
    Map<String, List<Map<String, dynamic>>> enrichmentTopicsBySubject = {};

    for (var item in analysisList) {
      double success = item['success'];
      String subj = item['subject'];

      // Determine threshold for this subject (default 70 if not set)
      int threshold = thresholds?[subj] ?? 70;

      if (success < threshold || (item['wrong'] as int) > 0) {
        if (!prioritizedTopicsBySubject.containsKey(subj)) {
          prioritizedTopicsBySubject[subj] = [];
        }
        prioritizedTopicsBySubject[subj]!.add(item);
      } else {
        if (!enrichmentTopicsBySubject.containsKey(subj)) {
          enrichmentTopicsBySubject[subj] = [];
        }
        enrichmentTopicsBySubject[subj]!.add(item);
      }
    }

    Map<String, List<String>> schedule = {};
    template.schedule.forEach((day, lessons) {
      schedule[day] = [];
      for (var lesson in lessons) {
        if (prioritizedTopicsBySubject.containsKey(lesson) &&
            prioritizedTopicsBySubject[lesson]!.isNotEmpty) {
          var item = prioritizedTopicsBySubject[lesson]!.removeAt(0);
          String topic = item['topic'];
          double success = (item['success'] as num?)?.toDouble() ?? 0;
          int wrong = (item['wrong'] as int?) ?? 0;
          int empty = (item['empty'] as int?) ?? 0;

          String taskSuffix = "";
          if (success < 40) {
            taskSuffix = "\n📺 Video + Kavram";
          } else if (success < 70) {
            taskSuffix = "\n📖 Özet + 20 Soru";
          } else if (success < 85) {
            taskSuffix = "\n📝 Test + Pratik";
          } else {
            taskSuffix = "\n⚡ Hız + Deneme";
          }

          if (wrong > 1 && wrong >= empty) {
            taskSuffix += "\n⚠️ Hataları Sor!";
          } else if (empty > 1 && empty > wrong) {
            taskSuffix += "\n📽️ Videoya Dön";
          }

          schedule[day]!.add('$lesson\n🎯 $topic$taskSuffix');
          prioritizedTopicsBySubject[lesson]!.add(item);
        } else if (enrichmentTopicsBySubject.containsKey(lesson) &&
            enrichmentTopicsBySubject[lesson]!.isNotEmpty) {
          var item = enrichmentTopicsBySubject[lesson]!.removeAt(0);
          String topic = item['topic'];
          String taskSuffix = "\n🏆 Ustalık Soruları\n🧠 Zor Kaynak Tara";
          schedule[day]!.add('$lesson\n🚀 $topic$taskSuffix');
          enrichmentTopicsBySubject[lesson]!.add(item);
        } else {
          schedule[day]!.add('$lesson\n📚 Genel Tekrar + Soru Çözümü');
        }
      }
    });
    return schedule;
  }

  // HELPER: Populate _allSubjects from generated programs
  void _updateCurrentProgramSubjects(List<Map<String, dynamic>> programs) {
    Set<String> subjects = {};
    for (var prog in programs) {
      if (prog['schedule'] != null) {
        (prog['schedule'] as Map<String, dynamic>).forEach((key, val) {
          List<String> tasks = List<String>.from(val);
          for (var task in tasks) {
            if (task.isNotEmpty) {
              subjects.add(task.split('\n')[0].trim());
            }
          }
        });
      }
    }
    setState(() {
      _allSubjects = subjects;
      _hiddenSubjects.clear(); // Reset filters on new program
    });
  }

  // 0. BAŞARI SINIRI BELİRLEME DİYALOĞU
  Map<String, int> _calculateInstitutionAverages(
    List<TrialExam> exams,
    List<String> subjects,
  ) {
    Map<String, List<double>> subjectRates = {};

    for (var subj in subjects) {
      subjectRates[subj] = [];
    }

    // Basit ortalama hesaplama: Her sınav için öğrencilerin net/puan ortalamasını bulmak zor olabilir
    // çünkü 'resultsJson' yapısını tam bilmiyoruz.
    // Ancak, genel bir yaklaşım olarak:
    // Her bir subject için varsayılan %50 kabul edelim, eğer veri varsa güncelleyelim.
    // Daha detaylı analiz için tüm answerKey ve result'ları taramak gerekir.
    // Şimdilik performans adına, eğer exams.resultsJson dolu ise oradan basit bir çıkarım yapmayı deneyebiliriz.
    // Fakat 'resultsJson' ham veri içeriyor.

    // HIZLI ÇÖZÜM:
    // Her ders için tüm öğrencilerin başarı yüzdelerinin ortalamasını alalım.
    for (var exam in exams) {
      if (exam.resultsJson == null) continue;

      try {
        final List<dynamic> results = jsonDecode(exam.resultsJson!);
        if (results.isEmpty) continue;

        // Booklet A'yı referans alalım soru sayıları için
        var booklets = exam.answerKeys.keys.toList();
        if (booklets.isEmpty) continue;
        String refBooklet = booklets.first;

        for (var result in results) {
          // Öğrencinin kitapçığı (multi-session merge may produce 'AB' - take first char)
          String rawSBooklet = (result['booklet'] ?? refBooklet)
              .toString()
              .trim();
          String sBooklet = rawSBooklet.isNotEmpty
              ? rawSBooklet[0].toUpperCase()
              : refBooklet;
          if (!exam.answerKeys.containsKey(sBooklet)) sBooklet = refBooklet;

          Map<String, dynamic> answers = result['answers'] is Map
              ? result['answers']
              : {};

          for (var subj in subjects) {
            String? keyStr = exam.answerKeys[sBooklet]?[subj];
            if (keyStr == null || keyStr.isEmpty) continue;

            dynamic ansData = answers[subj];
            String sAns = '';
            if (ansData is String)
              sAns = ansData;
            else if (ansData is Map && ansData['answer'] != null)
              sAns = ansData['answer'].toString();

            int correct = 0;
            int total = keyStr.length;

            for (int i = 0; i < total && i < sAns.length; i++) {
              if (sAns[i].toUpperCase() == keyStr[i].toUpperCase()) correct++;
            }

            double success = (correct / total) * 100;
            if (subjectRates[subj] == null) subjectRates[subj] = [];
            subjectRates[subj]!.add(success);
          }
        }
      } catch (e) {
        print("Error parsing results for averages: $e");
      }
    }

    Map<String, int> averages = {};
    for (var s in subjects) {
      List<double>? rates = subjectRates[s];
      if (rates != null && rates.isNotEmpty) {
        double avg = rates.reduce((a, b) => a + b) / rates.length;
        averages[s] = avg.round();
      } else {
        averages[s] = 50; // Veri yoksa %50 varsayalım
      }
    }
    return averages;
  }

  Future<Map<String, int>?> _showAdvancedThresholdDialog(
    List<String> subjects,
    Map<String, int> defaultThresholds,
  ) async {
    // Initialize thresholds with defaults
    Map<String, int> thresholds = Map.from(defaultThresholds);
    int globalThreshold = 70; // Slider başlangıç değeri

    // Check if mobile
    final isMobile = _isMobile(context);

    if (isMobile) {
      // Mobile: Full-screen Scaffold
      return await Navigator.of(context).push<Map<String, int>>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (ctx) {
            return StatefulBuilder(
              builder: (context, setState) {
                return Scaffold(
                  backgroundColor: Colors.white,
                  appBar: AppBar(
                    elevation: 0,
                    backgroundColor: Colors.white,
                    leading: IconButton(
                      icon: Icon(Icons.close, color: Colors.indigo),
                      onPressed: () => Navigator.pop(ctx, null),
                    ),
                    title: Text(
                      'Başarı Sınırı Belirleme',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade900,
                      ),
                    ),
                    centerTitle: true,
                  ),
                  body: Column(
                    children: [
                      // Scrollable content including global slider
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.all(16),
                          children: [
                            // Info message
                            Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue.shade100),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: Colors.blue.shade700,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Konu analiz listelerini oluştururken kullanılacak başarı yüzdesini belirleyiniz. Bu değerin altındakiler "Çalışılması Gerekenler", üstündekiler "Pekiştirilecekler" listesine girecektir.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            SizedBox(height: 16),

                            // Global Slider Card
                            Container(
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.indigo.shade100,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Genel Başarı Sınırı',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.indigo.shade800,
                                        ),
                                      ),
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: Colors.indigo.shade200,
                                          ),
                                        ),
                                        child: Text(
                                          '%$globalThreshold',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.indigo,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Bu değer tüm derslere uygulanacak başarı yüzdesini belirler. Slider\'ı hareket ettirerek tüm derslerin başarı sınırını aynı anda değiştirebilirsiniz. İsterseniz aşağıdan her ders için ayrı ayrı da ayarlayabilirsiniz.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  SizedBox(height: 12),
                                  SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: Colors.indigo,
                                      inactiveTrackColor:
                                          Colors.indigo.shade100,
                                      thumbColor: Colors.indigo,
                                      overlayColor: Colors.indigo.withOpacity(
                                        0.2,
                                      ),
                                    ),
                                    child: Slider(
                                      value: globalThreshold.toDouble(),
                                      min: 0,
                                      max: 100,
                                      divisions: 20,
                                      label: '%$globalThreshold',
                                      onChanged: (val) {
                                        setState(() {
                                          globalThreshold = val.toInt();
                                          for (var key in thresholds.keys) {
                                            thresholds[key] = globalThreshold;
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            SizedBox(height: 20),

                            // Subject-specific thresholds title
                            Text(
                              'Ders Bazlı Ayarlar',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.indigo.shade900,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Her ders için ayrı başarı sınırı belirleyebilirsiniz.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                            SizedBox(height: 12),

                            // Subject list
                            ...subjects.map((subj) {
                              int currentVal = thresholds[subj] ?? 70;
                              int defaultVal = defaultThresholds[subj] ?? 50;

                              Color activeColor = currentVal < 50
                                  ? Colors.red
                                  : (currentVal < 70
                                        ? Colors.orange
                                        : Colors.green);

                              return Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: Card(
                                  elevation: 0,
                                  color: Colors.grey.shade50,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: Colors.grey.shade200,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    subj,
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 15,
                                                    ),
                                                  ),
                                                  SizedBox(height: 4),
                                                  Container(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          Colors.grey.shade200,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      'Kurum Ort: %$defaultVal',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors
                                                            .grey
                                                            .shade700,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Text(
                                              '%$currentVal',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: activeColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                        SliderTheme(
                                          data: SliderTheme.of(context)
                                              .copyWith(
                                                activeTrackColor: activeColor,
                                                thumbColor: activeColor,
                                                overlayColor: activeColor
                                                    .withOpacity(0.2),
                                                valueIndicatorColor:
                                                    activeColor,
                                              ),
                                          child: Slider(
                                            value: currentVal.toDouble(),
                                            min: 0,
                                            max: 100,
                                            divisions: 20,
                                            label: '%$currentVal',
                                            onChanged: (val) {
                                              setState(() {
                                                thresholds[subj] = val.toInt();
                                              });
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                      // Fixed bottom buttons
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: Offset(0, -2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.pop(ctx, null),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                ),
                                child: Text(
                                  'İptal',
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: () => Navigator.pop(ctx, thresholds),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigo,
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  'Devam Et',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      );
    } else {
      // Desktop: Dialog
      return await showDialog<Map<String, int>>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (context, setState) {
              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                insetPadding: EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 24,
                ),
                child: Container(
                  width: 700,
                  constraints: BoxConstraints(maxWidth: 900, maxHeight: 800),
                  padding: EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.tune,
                              color: Colors.indigo,
                              size: 28,
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Başarı Sınırı Belirleme',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo.shade900,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Konu analiz listelerini oluştururken kullanılacak başarı yüzdesini belirleyiniz. Bu değerin altındakiler "Çalışılması Gerekenler", üstündekiler "Pekiştirilecekler" listesine girecektir.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 24),

                      // Global Slider Card
                      Container(
                        padding: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.indigo.shade100),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Genel Başarı Sınırı',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.indigo.shade800,
                                  ),
                                ),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Colors.indigo.shade200,
                                    ),
                                  ),
                                  child: Text(
                                    '%$globalThreshold',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: Colors.indigo,
                                inactiveTrackColor: Colors.indigo.shade100,
                                thumbColor: Colors.indigo,
                                overlayColor: Colors.indigo.withOpacity(0.2),
                              ),
                              child: Slider(
                                value: globalThreshold.toDouble(),
                                min: 0,
                                max: 100,
                                divisions: 20,
                                label: '%$globalThreshold',
                                onChanged: (val) {
                                  setState(() {
                                    globalThreshold = val.toInt();
                                    for (var key in thresholds.keys) {
                                      thresholds[key] = globalThreshold;
                                    }
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 16),
                      Expanded(
                        child: ListView.separated(
                          itemCount: subjects.length,
                          separatorBuilder: (ctx, index) =>
                              SizedBox(height: 12),
                          itemBuilder: (ctx, index) {
                            String subj = subjects[index];
                            int currentVal = thresholds[subj] ?? 70;
                            int defaultVal = defaultThresholds[subj] ?? 50;

                            Color activeColor = currentVal < 50
                                ? Colors.red
                                : (currentVal < 70
                                      ? Colors.orange
                                      : Colors.green);

                            return Card(
                              elevation: 0,
                              color: Colors.grey.shade50,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.grey.shade200),
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              subj,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade200,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                'Kurum Ort: %$defaultVal',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade700,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          '%$currentVal',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: activeColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        activeTrackColor: activeColor,
                                        thumbColor: activeColor,
                                        overlayColor: activeColor.withOpacity(
                                          0.2,
                                        ),
                                        valueIndicatorColor: activeColor,
                                      ),
                                      child: Slider(
                                        value: currentVal.toDouble(),
                                        min: 0,
                                        max: 100,
                                        divisions: 20,
                                        label: '%$currentVal',
                                        onChanged: (val) {
                                          setState(() {
                                            thresholds[subj] = val.toInt();
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, null),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                            ),
                            child: Text(
                              'İptal',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ),
                          SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, thresholds),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              padding: EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              'Devam Et',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
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
  }

  // --- THRESHOLD MANAGEMENT ---

  void _updateSingleThreshold(String subject, int value) {
    setState(() {
      // Create new thresholds map if it doesn't exist
      Map<String, int> currentThresholds = Map<String, int>.from(
        _generatedPrograms[_currentProgramIndex]['thresholds'] ?? {},
      );
      currentThresholds[subject] = value;
      _generatedPrograms[_currentProgramIndex]['thresholds'] =
          currentThresholds;
    });

    _recalculateCurrentProgram();
  }

  void _applyThresholdsToAll() {
    if (_generatedPrograms.isEmpty) return;

    Map<String, int> masterThresholds = Map<String, int>.from(
      _generatedPrograms[_currentProgramIndex]['thresholds'] ?? {},
    );

    setState(() {
      for (var program in _generatedPrograms) {
        program['thresholds'] = Map<String, int>.from(masterThresholds);
      }
    });

    _recalculateAllPrograms();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Başarı sınırları tüm öğrencilere uygulandı.')),
    );
  }

  void _recalculateCurrentProgram() {
    var program = _generatedPrograms[_currentProgramIndex];

    // Safety check for template
    if (program['template'] == null) {
      print('Template not found for recalculation');
      return;
    }

    StudyTemplate template = program['template'] as StudyTemplate;
    List<Map<String, dynamic>> analysisList =
        (program['topicAnalysis'] as List<dynamic>)
            .map((e) => e as Map<String, dynamic>)
            .toList();
    Map<String, int> thresholds =
        (program['thresholds'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v as int),
        ) ??
        {};

    final newSchedule = _generateScheduleFromAnalysis(
      analysisList,
      template,
      thresholds: thresholds,
    );

    setState(() {
      program['schedule'] = newSchedule;
      // Force rebuild by reassigning the list
      _generatedPrograms = List.from(_generatedPrograms);
    });
  }

  void _recalculateAllPrograms() {
    for (var i = 0; i < _generatedPrograms.length; i++) {
      var program = _generatedPrograms[i];
      if (program['template'] == null) continue;

      StudyTemplate template = program['template'] as StudyTemplate;
      List<Map<String, dynamic>> analysisList =
          (program['topicAnalysis'] as List<dynamic>)
              .map((e) => e as Map<String, dynamic>)
              .toList();
      Map<String, int> thresholds =
          (program['thresholds'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v as int),
          ) ??
          {};

      final newSchedule = _generateScheduleFromAnalysis(
        analysisList,
        template,
        thresholds: thresholds,
      );

      program['schedule'] = newSchedule;
    }

    setState(() {
      // Force rebuild by reassigning the list
      _generatedPrograms = List.from(_generatedPrograms);
    });
  }

  // 1. MANUEL PROGRAM OLUŞTURMA
  Future<void> _createManualProgram() async {
    if (_selectedStudentIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lütfen en az bir öğrenci seçiniz.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      List<Map<String, dynamic>> newPrograms = [];

      for (var studentId in _selectedStudentIds) {
        final student = _students.firstWhere(
          (s) => s['id'] == studentId,
          orElse: () => {},
        );
        if (student.isEmpty) continue;

        // Fetch Template
        final templateId = student['docData']['studyTemplateId'];
        if (templateId == null) continue;

        final StudyTemplate? template = await GuidanceService()
            .getStudyTemplate(widget.institutionId, templateId);
        if (template == null) continue;

        // Create Schedule directly from Template (No analysis)
        Map<String, List<String>> schedule = {};
        template.schedule.forEach((day, lessons) {
          schedule[day] = lessons.map((l) => "$l\n📚 Konu Çalışması").toList();
        });

        newPrograms.add({
          'studentId': studentId,
          'studentName': student['name'],
          'studentBranch': student['class'],
          'examName': 'Manuel Oluşturuldu',
          'schedule': schedule,
          'topicAnalysis': [],
          'template': template,
          'createdAt': DateTime.now(),
          'creatorId': FirebaseAuth.instance.currentUser?.uid,
          'creatorName':
              FirebaseAuth.instance.currentUser?.displayName ?? 'Eğitmen',
        });
      }

      if (newPrograms.isEmpty) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Seçilen öğrencilerin çalışma şablonu eksik.'),
          ),
        );
        return;
      }

      setState(() {
        _generatedPrograms = newPrograms;
        _currentProgramIndex = 0;
        _isProgramGenerated = true;
        _isLoading = false;
      });

      _updateCurrentProgramSubjects(_generatedPrograms);
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  // 3. BİRLEŞİK SINAV PROGRAMI OLUŞTURMA
  Future<void> _startCombinedExamProgramCreation() async {
    if (_selectedStudentIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lütfen en az bir öğrenci seçiniz.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Fetch Exams
      final exams = await AssessmentService()
          .getTrialExams(widget.institutionId)
          .first;

      exams.sort((a, b) => b.date.compareTo(a.date));
      setState(() => _isLoading = false);

      if (exams.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kayıtlı deneme sınavı bulunamadı.')),
        );
        return;
      }

      // 2. Select Multiple Exams
      final selectedExams = await _showMultiExamSelectionDialog(exams);
      if (selectedExams == null || selectedExams.isEmpty) return;

      // 2.1 Select Thresholds
      Set<String> allSubjects = {};
      for (var e in selectedExams) {
        if (e.answerKeys.isNotEmpty) {
          var keys = e.answerKeys['A'] ?? e.answerKeys.values.first;
          allSubjects.addAll(keys.keys);
        }
      }

      // Calculate Defaults
      Map<String, int> defaultThresholds = _calculateInstitutionAverages(
        selectedExams,
        allSubjects.toList(),
      );

      final thresholds = await _showAdvancedThresholdDialog(
        allSubjects.toList(),
        defaultThresholds,
      );
      if (thresholds == null) return;

      setState(() => _isLoading = true);

      // 3. Fetch Outcome Lists
      List<OutcomeList> allOutcomeLists = [];
      try {
        allOutcomeLists = await AssessmentService()
            .getOutcomeLists(widget.institutionId)
            .first;
      } catch (e) {
        print('Error fetching outcome lists: $e');
      }

      // Pre-parse results and pre-fetch exam info for efficiency
      final List<Map<String, dynamic>> examResults = selectedExams.map((exam) {
        return {
          'exam': exam,
          'results': exam.resultsJson != null
              ? jsonDecode(exam.resultsJson!)
              : [],
        };
      }).toList();

      // 4. Process Each Student in Parallel
      final List<Map<String, dynamic>?> newProgramsNullable = await Future.wait(
        _selectedStudentIds.map((studentId) async {
          final student = _students.firstWhere(
            (s) => s['id'] == studentId,
            orElse: () => {},
          );
          if (student.isEmpty) return null;
          final templateId = student['docData']['studyTemplateId'];
          if (templateId == null) return null;

          final StudyTemplate? template = await GuidanceService()
              .getStudyTemplate(widget.institutionId, templateId);
          if (template == null) return null;

          // Aggregate Stats
          Map<String, Map<String, dynamic>> combinedStats = {};

          for (var item in examResults) {
            final TrialExam exam = item['exam'];
            final List<dynamic> results = item['results'];

            var studentResult = _findStudentResult(results, student);
            if (studentResult == null) continue;

            var stats = _calculateTopicStats(
              studentResult,
              exam,
              student['docData'],
              allOutcomeLists,
            );

            // Merge
            stats.forEach((key, val) {
              if (!combinedStats.containsKey(key)) {
                combinedStats[key] = Map.from(val);
              } else {
                combinedStats[key]!['total'] += val['total'];
                combinedStats[key]!['correct'] += val['correct'];
                combinedStats[key]!['wrong'] += val['wrong'];
                combinedStats[key]!['empty'] += val['empty'];
              }
            });
          }

          final analysisList = combinedStats.isNotEmpty
              ? _generateAnalysisList(combinedStats)
              : <Map<String, dynamic>>[];

          final schedule = _generateScheduleFromAnalysis(
            analysisList,
            template,
            thresholds: thresholds,
          );

          return {
            'studentId': studentId,
            'studentName': student['name'],
            'studentBranch': student['class'],
            'examName': '${selectedExams.length} Sınav Analizi',
            'schedule': schedule,
            'topicAnalysis': analysisList,
            'thresholds': thresholds,
            'template': template,
            'createdAt': DateTime.now(),
            'creatorId': FirebaseAuth.instance.currentUser?.uid,
            'creatorName':
                FirebaseAuth.instance.currentUser?.displayName ?? 'Eğitmen',
          };
        }),
      );

      List<Map<String, dynamic>> newPrograms = newProgramsNullable
          .whereType<Map<String, dynamic>>()
          .toList();

      if (newPrograms.isEmpty) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Seçilen öğrenciler için ortak analiz yapılamadı.'),
          ),
        );
        return;
      }

      setState(() {
        _generatedPrograms = newPrograms;
        _currentProgramIndex = 0;
        _isProgramGenerated = true;
        _isLoading = false;
      });

      _updateCurrentProgramSubjects(_generatedPrograms);
    } catch (e) {
      setState(() => _isLoading = false);
      print('Error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  // 2. TEKİL SINAV PROGRAMI OLUŞTURMA (Eski _startProgramCreation)
  Future<void> _startSingleExamProgramCreation({
    String? automatedExamName,
    Map<String, int>? automatedThresholds,
  }) async {
    if (_selectedStudentIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lütfen en az bir öğrenci seçiniz.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Fetch Exams
      final exams = await AssessmentService()
          .getTrialExams(widget.institutionId)
          .first;

      exams.sort((a, b) => b.date.compareTo(a.date));

      setState(() => _isLoading = false);

      if (exams.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kayıtlı deneme sınavı bulunamadı.')),
        );
        return;
      }

      // 2. Select Exam
      TrialExam? selectedExam;
      if (automatedExamName != null) {
        selectedExam = exams.firstWhere(
          (e) => e.name == automatedExamName,
          orElse: () => exams.first,
        );
      } else {
        selectedExam = await _showSingleExamSelectionDialog(exams);
      }

      if (selectedExam == null) return;

      // 2.1 Select Thresholds
      List<String> subjects = [];
      if (selectedExam.answerKeys.isNotEmpty) {
        var keys =
            selectedExam.answerKeys['A'] ??
            selectedExam.answerKeys.values.first;
        subjects = keys.keys.toList();
      }

      // Calculate Defaults
      Map<String, int> defaultThresholds = _calculateInstitutionAverages([
        selectedExam,
      ], subjects);

      Map<String, int>? thresholds;
      if (automatedThresholds != null) {
        thresholds = automatedThresholds;
      } else {
        thresholds = await _showAdvancedThresholdDialog(
          subjects,
          defaultThresholds,
        );
      }
      if (thresholds == null) return;

      final TrialExam finalExam = selectedExam;
      final Map<String, int> finalThresholds = thresholds;

      setState(() => _isLoading = true);

      // 3. Fetch Outcome Lists for Hierarchy Lookup
      List<OutcomeList> allOutcomeLists = [];
      try {
        allOutcomeLists = await AssessmentService()
            .getOutcomeLists(widget.institutionId)
            .first;
      } catch (e) {
        print('Error fetching outcome lists: $e');
      }

      // 4. Generate Programs for ALL Selected Students in Parallel
      List<dynamic> results = [];
      if (finalExam.resultsJson != null) {
        results = jsonDecode(finalExam.resultsJson!);
      }

      final List<Map<String, dynamic>?> newProgramsNullable = await Future.wait(
        _selectedStudentIds.map((studentId) async {
          final student = _students.firstWhere(
            (s) => s['id'] == studentId,
            orElse: () => {},
          );

          if (student.isEmpty) return null;

          var studentResult = _findStudentResult(results, student);
          if (studentResult == null) {
            print(
              'DEBUG: Student ${student['name']} not found in exam results.',
            );
          }

          // Fetch Template
          final templateId = student['docData']['studyTemplateId'];
          if (templateId == null) {
            print('No template for ${student['name']}');
            return null;
          }

          final StudyTemplate? template = await GuidanceService()
              .getStudyTemplate(widget.institutionId, templateId);
          if (template == null) return null;

          List<Map<String, dynamic>> analysisList = [];

          if (studentResult != null) {
            var topicStats = _calculateTopicStats(
              studentResult,
              finalExam,
              student['docData'],
              allOutcomeLists,
            );
            analysisList = _generateAnalysisList(topicStats);
          }

          final schedule = _generateScheduleFromAnalysis(
            analysisList,
            template,
            thresholds: finalThresholds,
          );

          return {
            'studentId': studentId,
            'studentName': student['name'],
            'studentBranch': student['class'],
            'examName': finalExam.name,
            'schedule': schedule,
            'topicAnalysis': analysisList,
            'thresholds': finalThresholds,
            'template': template,
            'createdAt': DateTime.now(),
            'creatorId': FirebaseAuth.instance.currentUser?.uid,
            'creatorName':
                FirebaseAuth.instance.currentUser?.displayName ?? 'Eğitmen',
          };
        }),
      );

      List<Map<String, dynamic>> newPrograms = newProgramsNullable
          .whereType<Map<String, dynamic>>()
          .toList();

      if (newPrograms.isEmpty) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Seçilen öğrenciler için analiz yapılamadı (Şablon veya Sınav Sonucu eksik).',
            ),
          ),
        );
        return;
      }

      setState(() {
        _generatedPrograms = newPrograms;
        _currentProgramIndex = 0;
        _isProgramGenerated = true;
        _isLoading = false;
      });

      _updateCurrentProgramSubjects(_generatedPrograms);
    } catch (e) {
      setState(() => _isLoading = false);
      print('Error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Ders Çalışma Programı',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.indigo,
        iconTheme: IconThemeData(color: Colors.white),
        actions: [
          // 1. Program Actions (Mobile Only)
          if (_isProgramGenerated && isMobile)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Colors.white),
              onSelected: (value) {
                if (value == 'refresh') {
                  setState(() => _isProgramGenerated = false);
                } else if (value == 'save') {
                  _saveCurrentProgram();
                } else if (value == 'print') {
                  if (_generatedPrograms.isNotEmpty &&
                      _currentProgramIndex < _generatedPrograms.length) {
                    _printProgram();
                  }
                } else if (value == 'settings') {
                  _showMobileSettingsSheet();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'settings',
                  child: Row(
                    children: [
                      Icon(Icons.tune, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text('Program Ayarları'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'refresh',
                  child: Row(
                    children: [
                      Icon(Icons.refresh, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Yeniden'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'save',
                  child: Row(
                    children: [
                      Icon(Icons.save, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('Kaydet'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'print',
                  child: Row(
                    children: [
                      Icon(Icons.print, color: Colors.grey),
                      SizedBox(width: 8),
                      Text('Yazdır'),
                    ],
                  ),
                ),
              ],
            ),

          // 2. Global Actions (When NO Program is generated, OR on Desktop if desired)
          // For now, let's show this ONLY when program is NOT generated, to avoid clutter.
          if (!_isProgramGenerated)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Colors.white),
              onSelected: (value) {
                if (value == 'create') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => StudyTemplateCreationScreen(
                        institutionId: widget.institutionId,
                        schoolTypeId: widget.schoolTypeId,
                      ),
                    ),
                  ).then((_) => _fetchStudents());
                } else if (value == 'saved') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SavedTemplatesScreen(
                        institutionId: widget.institutionId,
                        schoolTypeId: widget.schoolTypeId,
                      ),
                    ),
                  ).then((_) => _fetchStudents());
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'create',
                  child: Row(
                    children: [
                      Icon(Icons.add_circle_outline, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text('Şablon Oluştur'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'saved',
                  child: Row(
                    children: [
                      Icon(Icons.folder_open, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text('Kayıtlı Şablonlar'),
                    ],
                  ),
                ),
              ],
            ),

          SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.history, color: Colors.white),
            tooltip: 'Kayıtlı Programlar',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SavedStudyProgramsScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                  ),
                ),
              );
            },
          ),
          SizedBox(width: 8),
        ],
      ),
      body: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
        ),
        child: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
      ),
    );
  }

  // Mobile Settings Sheet
  void _showMobileSettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.9,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (_, controller) => Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    margin: EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Row(
                      children: [
                        Icon(Icons.tune, color: Colors.indigo, size: 24),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Program Ayarları",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),

                  Divider(height: 1),

                  // Settings Content
                  Expanded(
                    child: SingleChildScrollView(
                      controller: controller,
                      padding: EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Threshold Editor
                          if (_isProgramGenerated &&
                              _generatedPrograms.isNotEmpty) ...[
                            _buildThresholdEditorMobile(setModalState),
                            Divider(height: 30),
                          ],

                          // Subject Visibility
                          Text(
                            "Ders Görünümü",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade900,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            "Programda görünmesini istediğiniz dersleri seçiniz.",
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 16),

                          // Add New Subject
                          Container(
                            margin: EdgeInsets.only(bottom: 16),
                            child: InkWell(
                              onTap: () {
                                Navigator.pop(ctx);
                                _showAddSubjectDialog();
                              },
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.indigo.shade200,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  color: Colors.indigo.shade50,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add,
                                      size: 20,
                                      color: Colors.indigo,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      "Yeni Ders Ekle",
                                      style: TextStyle(
                                        color: Colors.indigo,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          if (_allSubjects.isEmpty)
                            Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(
                                child: Text(
                                  "Listelenecek ders bulunamadı.",
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ),
                            )
                          else
                            Column(
                              children: _allSubjects.map((subject) {
                                final isVisible = !_hiddenSubjects.contains(
                                  subject,
                                );
                                return CheckboxListTile(
                                  value: isVisible,
                                  activeColor: Colors.indigo,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  title: Text(
                                    subject,
                                    style: TextStyle(fontSize: 15),
                                  ),
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _hiddenSubjects.remove(subject);
                                      } else {
                                        _hiddenSubjects.add(subject);
                                      }
                                    });
                                    setModalState(() {});
                                  },
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMobileLayout() {
    if (_isProgramGenerated) {
      // Show program view in full screen on mobile
      return _buildProgramView();
    }

    // Student selection view
    return Column(
      children: [
        // Student List
        Expanded(child: _buildLeftPanel()),

        // Sticky Footer with Actions
        if (_selectedStudentIds.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Selected count
                    Container(
                      padding: EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.indigo,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '${_selectedStudentIds.length} öğrenci seçildi',
                            style: TextStyle(
                              color: Colors.indigo.shade900,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 12),

                    // Action buttons
                    Row(
                      children: [
                        // Single Exam button
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _startSingleExamProgramCreation,
                            icon: Icon(Icons.assignment),
                            label: Text('Tek Sınav'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12),

                        // Combined Exam button
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _startCombinedExamProgramCreation,
                            icon: Icon(Icons.library_books),
                            label: Text('Çoklu Sınav'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),

                    // Manual program button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _createManualProgram,
                        icon: Icon(Icons.edit_note),
                        label: Text('Manuel Program'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                          side: BorderSide(color: Colors.grey.shade400),
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // LEFT PANEL (Student List OR Settings)
        if (!_isFullScreen)
          Container(
            width: 350,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.grey.shade300)),
              color: Colors.grey.shade50,
            ),
            child: _isProgramGenerated
                ? _buildSettingsPanel()
                : _buildLeftPanel(),
          ),
        // RIGHT PANEL (Content)
        Expanded(child: Stack(children: [_buildRightPanel()])),
      ],
    );
  }

  Widget _buildLeftPanel() {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.indigo,
            border: Border(bottom: BorderSide(color: Colors.indigo.shade700)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.school, color: Colors.white),
                  const SizedBox(width: 8),
                  const Text(
                    'Öğrenci Listesi',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_filteredStudents.length}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Arama + Filtre
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Öğrenci ara',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _searchQuery = '';
                                    _filterStudents();
                                  });
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val;
                          _filterStudents();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.filter_alt_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () {},
                      padding: EdgeInsets.all(8),
                      constraints: BoxConstraints(),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              // Class Filter Dropdown (Styled)
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(canvasColor: Colors.indigo.shade700),
                child: DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: 'Sınıf / Şube',
                    labelStyle: TextStyle(color: Colors.indigo.shade100),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.indigo.shade400,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  value: _selectedClassFilter,
                  style: TextStyle(color: Colors.white),
                  icon: Icon(Icons.arrow_drop_down, color: Colors.white70),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(
                        "Tümü",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    ..._classNames.map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(c, style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _selectedClassFilter = val;
                      _filterStudents();
                    });
                  },
                ),
              ),
              SizedBox(height: 8),
              // Select All
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: Icon(
                      Icons.select_all,
                      color: Colors.indigo.shade100,
                      size: 16,
                    ),
                    label: Text(
                      _selectedStudentIds.length == _filteredStudents.length &&
                              _filteredStudents.isNotEmpty
                          ? 'Seçimi Kaldır'
                          : 'Tümünü Seç',
                      style: TextStyle(
                        color: Colors.indigo.shade100,
                        fontSize: 12,
                      ),
                    ),
                    onPressed: _selectAll,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // LIST
        Expanded(
          child: _isLoading && !_isProgramGenerated
              ? Center(child: CircularProgressIndicator())
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: _filteredStudents.length,
                  separatorBuilder: (_, __) => Divider(height: 1),
                  itemBuilder: (context, index) {
                    final student = _filteredStudents[index];
                    final isSelected = _selectedStudentIds.contains(
                      student['id'],
                    );
                    return CheckboxListTile(
                      value: isSelected,
                      activeColor: Colors.indigo,
                      tileColor: isSelected ? Colors.indigo.shade50 : null,
                      secondary: CircleAvatar(
                        backgroundColor: Colors.indigo.shade100,
                        radius: 16,
                        child: Text(
                          student['name'].substring(0, 1).toUpperCase(),
                          style: TextStyle(
                            color: Colors.indigo,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      title: Text(
                        student['name'],
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            student['class'],
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          SizedBox(height: 2),
                          Text(
                            student['hasTemplate'] == true
                                ? 'Şablon Var'
                                : 'Şablon Mevcut Değil',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: student['hasTemplate'] == true
                                  ? Colors.green.shade700
                                  : Colors.red.shade400,
                            ),
                          ),
                        ],
                      ),
                      onChanged: (_) => _toggleSelection(student['id']),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 0,
                      ),
                      dense: true,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSettingsPanel() {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.indigo,
            border: Border(bottom: BorderSide(color: Colors.indigo.shade700)),
          ),
          child: Row(
            children: [
              const Icon(Icons.tune, color: Colors.white),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Program Ayarları',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // Collapse toggle on the right
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _isFullScreen = true;
                  });
                },
                tooltip: 'Ayarları Gizle',
              ),
            ],
          ),
        ),

        // Settings Content
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 0. Threshold Editor (New)
                if (_isProgramGenerated && _generatedPrograms.isNotEmpty) ...[
                  _buildThresholdEditor(),
                  Divider(height: 30),
                ],

                // 1. Ders Filtreleme
                Text(
                  "Ders Görünümü",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade900,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "Programda görünmesini istediğiniz dersleri seçiniz.",
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                SizedBox(height: 12),

                // Add New Subject
                Container(
                  margin: EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _showAddSubjectDialog,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 12,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.indigo.shade200),
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.indigo.shade50,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add, size: 18, color: Colors.indigo),
                                SizedBox(width: 8),
                                Text(
                                  "Yeni Ders Ekle",
                                  style: TextStyle(
                                    color: Colors.indigo,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (_allSubjects.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text("Listelenecek ders bulunamadı."),
                  )
                else
                  Column(
                    children: _allSubjects.map((subject) {
                      final isVisible = !_hiddenSubjects.contains(subject);
                      return CheckboxListTile(
                        value: isVisible,
                        activeColor: Colors.indigo,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(subject, style: TextStyle(fontSize: 13)),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _hiddenSubjects.remove(subject);
                            } else {
                              _hiddenSubjects.add(subject);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),

                Divider(height: 30),

                // 2. Other Settings (Placeholder)
                Text(
                  "Diğer Ayarlar",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade900,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 12),
                SwitchListTile(
                  value: true,
                  activeColor: Colors.indigo,
                  contentPadding: EdgeInsets.zero,
                  title: Text("Akıllı Saatler", style: TextStyle(fontSize: 13)),
                  subtitle: Text(
                    "Mola hatırlatıcılarını göster",
                    style: TextStyle(fontSize: 11),
                  ),
                  onChanged: (val) {
                    // Placeholder
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThresholdEditor() {
    var program = _generatedPrograms[_currentProgramIndex];
    Map<String, int> thresholds =
        (program['thresholds'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v as int),
        ) ??
        {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Başarı Sınırları",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.indigo.shade900,
            fontSize: 14,
          ),
        ),
        SizedBox(height: 8),
        Text(
          "Ders bazlı başarı hedeflerini güncelleyin.",
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
        SizedBox(height: 12),
        ExpansionTile(
          title: Text(
            "Hedefleri Düzenle",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          childrenPadding: EdgeInsets.zero,
          collapsedBackgroundColor: Colors.indigo.shade50,
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.indigo.shade100),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.transparent),
          ),
          children: [
            ...thresholds.entries.map((entry) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(entry.key, style: TextStyle(fontSize: 12)),
                        Text(
                          '%${entry.value}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.indigo,
                      thumbColor: Colors.indigo,
                      trackHeight: 2,
                      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      value: entry.value.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 20,
                      onChanged: (val) {
                        _updateSingleThreshold(entry.key, val.toInt());
                      },
                    ),
                  ),
                ],
              );
            }).toList(),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: ElevatedButton.icon(
                onPressed: _applyThresholdsToAll,
                icon: Icon(Icons.copy_all, size: 16),
                label: Text("Tümüne Uygula"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade100,
                  foregroundColor: Colors.indigo.shade900,
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Mobile-specific threshold editor with modal state setter
  Widget _buildThresholdEditorMobile(StateSetter setModalState) {
    var program = _generatedPrograms[_currentProgramIndex];
    Map<String, int> thresholds =
        (program['thresholds'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v as int),
        ) ??
        {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Başarı Sınırları",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.indigo.shade900,
            fontSize: 14,
          ),
        ),
        SizedBox(height: 8),
        Text(
          "Ders bazlı başarı hedeflerini güncelleyin.",
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
        SizedBox(height: 12),
        ExpansionTile(
          title: Text(
            "Hedefleri Düzenle",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          childrenPadding: EdgeInsets.zero,
          collapsedBackgroundColor: Colors.indigo.shade50,
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.indigo.shade100),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.transparent),
          ),
          children: [
            ...thresholds.entries.map((entry) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(entry.key, style: TextStyle(fontSize: 12)),
                        Text(
                          '%${entry.value}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.indigo,
                      thumbColor: Colors.indigo,
                      trackHeight: 2,
                      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      value: entry.value.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 20,
                      onChanged: (val) {
                        // Update main state
                        _updateSingleThreshold(entry.key, val.toInt());
                        // Update modal state to reflect changes immediately
                        setModalState(() {});
                      },
                    ),
                  ),
                ],
              );
            }).toList(),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: ElevatedButton.icon(
                onPressed: () {
                  _applyThresholdsToAll();
                  setModalState(() {});
                },
                icon: Icon(Icons.copy_all, size: 16),
                label: Text("Tümüne Uygula"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade100,
                  foregroundColor: Colors.indigo.shade900,
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showAddSubjectDialog() {
    TextEditingController _controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Yeni Ders Ekle"),
        content: TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: "Ders Adı",
            hintText: "Örn: Almanca",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("İptal"),
          ),
          ElevatedButton(
            onPressed: () {
              if (_controller.text.isNotEmpty) {
                setState(() {
                  _allSubjects.add(_controller.text.trim());
                });
                Navigator.pop(context);
              }
            },
            child: Text("Ekle"),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    if (_selectedStudentIds.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search, size: 80, color: Colors.grey.shade300),
            SizedBox(height: 16),
            Text(
              "Lütfen sol taraftan program oluşturulacak\nöğrenci veya öğrencileri seçiniz.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Add New / View Content Switcher
        if (!_isProgramGenerated)
          // Add "Create New" Button Area on top if needed or keep centered?
          // User said "programlarıd aküçük kartlara koy bu alnın üstüne sağa doğru diz"
          // And "sağ kısımdaki program oluşturmamya başla kısmı yeni program oluşturmaya başla yap"
          // If I am NOT viewing a program, I show the big button.
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.edit_calendar,
                    size: 100,
                    color: Colors.indigo.shade100,
                  ),
                  SizedBox(height: 24),
                  Text(
                    "${_selectedStudentIds.length} Öğrenci Seçildi",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                  SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: Icon(Icons.add),
                    label: Text("Yeni Program Oluşturmaya Başla"),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      textStyle: TextStyle(fontSize: 18),
                    ),
                    onPressed: _showProgramCreationOptionsDialog,
                  ),
                ],
              ),
            ),
          ),

        if (_isProgramGenerated) ...[
          // Show "New Program" button also in the header?
          // User asked to rename the "Start Program Creation" button.
          // But if viewing, the button is gone (replaced by View).
          // Maybe add a "New Program" button to the View's header?
          // I'll keep the view as is for now, as user can click "Yeniden" (Refresh/Reset) to start over,
          // or I can add a small "+" button in the history bar?
          // For now, let's just show the view.
          Expanded(child: _buildProgramView()),
        ],
      ],
    );
  }

  // ========== AI DESTEKLI ÇALIŞMA PROGRAMI HELPER FONKSİYONLARI ==========

  /// Başarı yüzdesine göre durum bilgisi döndürür
  Map<String, dynamic> _getStatusInfo(double success) {
    if (success <= 25) {
      return {
        'icon': Icons.warning_amber_rounded,
        'color': Colors.red,
        'bgColor': Colors.red.shade50,
        'label': 'Tehlike',
        'category': 'Kavramsal video ve temel tanımlar',
        'technique': 'Feynman Tekniği',
        'action': 'Kavramsal video izle, temel tanımları öğren',
        'tasks': [
          '📹 Konuyla ilgili 2 kavram videosu izle',
          '📖 Temel tanımları defterine yaz',
          '🎯 5 temel seviye soru çöz',
        ],
        'motivation':
            '🌟 Her uzman bir zamanlar başlangıç seviyesindeydi. İlk adımı atmak cesaret ister!',
      };
    } else if (success <= 45) {
      return {
        'icon': Icons.trending_down_rounded,
        'color': Colors.orange,
        'bgColor': Colors.orange.shade50,
        'label': 'Dikkat',
        'category': 'Özet çıkarma ve çözümlü örnek analizi',
        'technique': 'Cornell Not Alma',
        'action': 'Özet çıkar, çözümlü örnekleri analiz et',
        'tasks': [
          '📝 Konunun özet notunu çıkar',
          '🔍 3 çözümlü örneği adım adım incele',
          '✏️ 10 orta seviye soru çöz',
        ],
        'motivation':
            '💪 Zor konuları kavramak için çaba gösteriyorsunuz. Bu kararlılık sizi başarıya götürecek!',
      };
    } else if (success <= 65) {
      return {
        'icon': Icons.autorenew_rounded,
        'color': Colors.amber.shade700,
        'bgColor': Colors.amber.shade50,
        'label': 'Gelişen',
        'category': 'Kazanım testleri ve alt başlık analizi',
        'technique': 'Pomodoro Tekniği',
        'action': 'Kazanım testleri çöz, zayıf alt konulara odaklan',
        'tasks': [
          '⏱️ 25 dakikalık odaklı çalışma yap',
          '📊 Kazanım testi çöz ve analiz et',
          '🎯 15 karma soru çöz',
        ],
        'motivation':
            '🚀 Gelişim gösteriyorsunuz! Düzenli tekrarla bu konuları tamamen kavrayacaksınız!',
      };
    } else if (success <= 85) {
      return {
        'icon': Icons.trending_up_rounded,
        'color': Colors.blue,
        'bgColor': Colors.blue.shade50,
        'label': 'İyi',
        'category': 'Yeni nesil sorular ve süreli denemeler',
        'technique': 'Aktif Geri Çağırma',
        'action': 'Yeni nesil sorular çöz, süre tutarak pratik yap',
        'tasks': [
          '🧠 15 yeni nesil soru çöz',
          '⏰ Süreli mini deneme yap (20 dk)',
          '🔄 Yanlışları analiz et ve tekrar çöz',
        ],
        'motivation':
            '⭐ Harika ilerleme! Artık zorlu sorulara meydan okuyabilirsiniz!',
      };
    } else {
      return {
        'icon': Icons.star_rounded,
        'color': Colors.green,
        'bgColor': Colors.green.shade50,
        'label': 'Mükemmel',
        'category': 'Ustalık çalışmaları ve bilgi transferi',
        'technique': 'Öğretme Yöntemi',
        'action': 'Bilgini pekiştir, başkalarına öğret',
        'tasks': [
          '👨‍🏫 Bu konuyu bir arkadaşına anlat',
          '🏆 Zor seviye ve yarışma soruları çöz',
          '📚 Farklı kaynaklardan soru tara',
        ],
        'motivation':
            '🎉 Muhteşem! Bu konuda ustalık seviyesine ulaştınız. Bilginizi paylaşarak pekiştirin!',
      };
    }
  }

  /// İkon Legend Widget'ı
  Widget _buildIconLegend() {
    final levels = [
      {
        'range': '%0-25',
        'icon': Icons.warning_amber_rounded,
        'color': Colors.red,
        'label': 'Tehlike',
      },
      {
        'range': '%26-45',
        'icon': Icons.trending_down_rounded,
        'color': Colors.orange,
        'label': 'Dikkat',
      },
      {
        'range': '%46-65',
        'icon': Icons.autorenew_rounded,
        'color': Colors.amber.shade700,
        'label': 'Gelişen',
      },
      {
        'range': '%66-85',
        'icon': Icons.trending_up_rounded,
        'color': Colors.blue,
        'label': 'İyi',
      },
      {
        'range': '%86-100',
        'icon': Icons.star_rounded,
        'color': Colors.green,
        'label': 'Mükemmel',
      },
    ];

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade50, Colors.purple.shade50],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.indigo, size: 18),
              SizedBox(width: 8),
              Text(
                'Durum İkonları Açıklaması',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo.shade700,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: levels.map((level) {
                return Container(
                  margin: EdgeInsets.only(right: 16),
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 4),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: (level['color'] as Color).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          level['icon'] as IconData,
                          color: level['color'] as Color,
                          size: 18,
                        ),
                      ),
                      SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            level['label'] as String,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            level['range'] as String,
                            style: TextStyle(color: Colors.grey, fontSize: 10),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // Gemini AI Analysis Trigger
  Future<void> _runGeminiAnalysis(
    String studentName,
    List<dynamic> analysis,
  ) async {
    setState(() {
      _isGeminiLoading = true;
      _geminiAnalysis = null;
    });

    try {
      // 1. Always try to load the stored key first
      final prefs = await SharedPreferences.getInstance();
      String? storedKey = prefs.getString('gemini_api_key');

      // If we have a stored key, use it!
      if (storedKey != null &&
          storedKey.isNotEmpty &&
          storedKey != "YOUR_API_KEY_HERE") {
        _geminiService = GeminiService.withKey(storedKey);
      }

      final safeAnalysis = analysis
          .map((e) => e as Map<String, dynamic>)
          .toList();

      final result = await _geminiService.analyzeStudentPerformance(
        studentName: studentName,
        topicAnalysis: safeAnalysis,
      );

      if (mounted) {
        setState(() {
          _geminiAnalysis = result;
          _isGeminiLoading = false;
        });
      }
    } catch (e) {
      print("Gemini First Attempt Error: $e");

      if (mounted) {
        // Stop loading
        setState(() {
          _isGeminiLoading = false;
        });

        // Show Dialog to ask for key
        await _showApiKeyDialog(studentName, analysis);
      }
    }
  }

  Future<void> _showApiKeyDialog(
    String studentName,
    List<dynamic> analysis,
  ) async {
    final TextEditingController keyController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        // Renamed for clarity and to avoid shadowing
        return AlertDialog(
          title: Text('Gemini API Anahtarı Gerekli'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Yapay zeka analizi için geçerli bir API anahtarı giriniz.'),
              SizedBox(height: 10),
              TextField(
                controller: keyController,
                decoration: InputDecoration(
                  labelText: 'API Key (AIzaSy...)',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 10),
              InkWell(
                onTap: () async {
                  // Open URL logic
                },
                child: Text(
                  'Anahtar al: aistudio.google.com',
                  style: TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () async {
                final key = keyController.text.trim();
                if (key.isNotEmpty) {
                  Navigator.pop(dialogContext);

                  // Save key
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('gemini_api_key', key);

                  // Update service
                  setState(() {
                    _geminiService = GeminiService.withKey(key);
                    _isGeminiLoading = true;
                  });

                  // Retry
                  try {
                    final safeAnalysis = analysis
                        .map((e) => e as Map<String, dynamic>)
                        .toList();
                    final result = await _geminiService
                        .analyzeStudentPerformance(
                          studentName: studentName,
                          topicAnalysis: safeAnalysis,
                        );

                    if (mounted) {
                      setState(() {
                        _geminiAnalysis = result;
                        _isGeminiLoading = false;
                      });
                    }
                  } catch (e2) {
                    if (mounted) {
                      setState(() => _isGeminiLoading = false);
                      // Now using 'context' (Screen's context), not 'dialogContext'
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Hata: $e2'),
                          backgroundColor: Colors.red,
                          duration: Duration(seconds: 5),
                        ),
                      );
                    }
                  }
                }
              },
              child: Text('Kaydet ve Dene'),
            ),
          ],
        );
      },
    );
  }

  /// AI Yorum Kartı Widget'ı
  Widget _buildAICommentCard(List<dynamic> topicAnalysis) {
    if (topicAnalysis.isEmpty) {
      return Container(
        margin: EdgeInsets.only(top: 20),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Analiz Verisi Bulunamadı",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade900,
                    ),
                  ),
                  Text(
                    "Sınav sonuçları ile konu listesi eşleştirilemedi. Lütfen öğrenci sınıfı ve sınav verilerini kontrol ediniz.",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // En zayıf konuyu bul
    final weakestTopic = topicAnalysis.first as Map<String, dynamic>;
    final success = (weakestTopic['success'] as num?)?.toDouble() ?? 0;
    final statusInfo = _getStatusInfo(success);

    // Genel durum analizi
    final avgSuccess = topicAnalysis.isNotEmpty
        ? topicAnalysis
                  .map((e) => (e['success'] as num?)?.toDouble() ?? 0)
                  .reduce((a, b) => a + b) /
              topicAnalysis.length
        : 0.0;
    final overallStatus = _getStatusInfo(avgSuccess);

    return Container(
      margin: EdgeInsets.only(top: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade600, Colors.purple.shade600],
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
      child: Column(
        children: [
          // Başlık
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.psychology_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🤖 Yapay Zeka Öğrenme Koçu',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Kişiselleştirilmiş Öğrenme Analizi',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // AI Button or Loading
                if (_isGeminiLoading)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: () => _runGeminiAnalysis(
                      _generatedPrograms[_currentProgramIndex]['studentName'],
                      topicAnalysis,
                    ),
                    icon: Icon(Icons.auto_awesome, size: 16),
                    label: Text("Analiz Et"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.purple,
                      textStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // İçerik
          Container(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 0. Gemini Result (If available) mechanism
                if (_geminiAnalysis != null) ...[
                  _buildAISection(
                    icon: Icons.auto_awesome_motion,
                    title: '✨ Gemini AI Görüşü',
                    content: _geminiAnalysis!,
                  ),
                  SizedBox(height: 16),
                  Divider(color: Colors.white24),
                  SizedBox(height: 16),
                ],

                // 1. Durum Analizi (Legacy Rules)
                _buildAISection(
                  icon: Icons.analytics_rounded,
                  title: '📊 İstatistiksel Durum',
                  content:
                      'En zayıf konunuz "${weakestTopic['topic']}" (%${success.toStringAsFixed(0)}). '
                      'Genel durumunuz: ${overallStatus['label']}. ${overallStatus['category']}.',
                ),
                SizedBox(height: 16),

                // 2. Öncelikli Aksiyon
                _buildAISection(
                  icon: Icons.priority_high_rounded,
                  title: '🎯 Öncelikli Aksiyon',
                  content: statusInfo['action'] as String,
                ),
                SizedBox(height: 16),

                // 3. Çalışma Tekniği
                _buildAISection(
                  icon: Icons.lightbulb_rounded,
                  title: '💡 Önerilen Çalışma Tekniği',
                  content:
                      '${statusInfo['technique']}: Bu seviye için en etkili yöntem.',
                ),
                SizedBox(height: 12),

                // 0. Threshold Editor (New)
                if (_isProgramGenerated && _generatedPrograms.isNotEmpty) ...[
                  _buildThresholdEditor(),
                  Divider(height: 30),
                ],

                // 4. Mini Görev Listesi
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.checklist_rounded,
                            color: Colors.white70,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '📋 Bu Hafta Yapılacaklar',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      ...(statusInfo['tasks'] as List<String>).map((task) {
                        return Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                color: Colors.greenAccent,
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  task,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
                SizedBox(height: 16),

                // 5. Motivasyon
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.amber.shade400, Colors.orange.shade400],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.emoji_events_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          statusInfo['motivation'] as String,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAISection({
    required IconData icon,
    required String title,
    required String content,
  }) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white70, size: 18),
              SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgramView() {
    if (_generatedPrograms.isEmpty) return Container();

    // Safety check for index
    if (_currentProgramIndex >= _generatedPrograms.length) {
      _currentProgramIndex = 0;
    }

    final currentProgram = _generatedPrograms[_currentProgramIndex];
    final schedule = (currentProgram['schedule'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, List<String>.from(value)),
    );
    final topicAnalysis =
        (currentProgram['topicAnalysis'] as List<dynamic>?) ?? [];

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white,
            child: Row(
              children: [
                // Panel toggle button (show settings when hidden)
                if (_isFullScreen && !_isMobile(context))
                  IconButton(
                    icon: Icon(Icons.menu, color: Colors.grey[700]),
                    onPressed: () {
                      setState(() {
                        _isFullScreen = false;
                      });
                    },
                    tooltip: 'Ayarları Göster',
                  ),
                if (_generatedPrograms.length > 1)
                  Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: IconButton(
                      icon: Icon(Icons.arrow_back_ios, size: 20),
                      onPressed: _currentProgramIndex > 0
                          ? () {
                              setState(() {
                                _currentProgramIndex--;
                              });
                            }
                          : null,
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        currentProgram['studentName'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Referans: ${currentProgram['examName']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      if (_generatedPrograms.length > 1)
                        Container(
                          margin: EdgeInsets.only(top: 4),
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_currentProgramIndex + 1} / ${_generatedPrograms.length}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_generatedPrograms.length > 1)
                  Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: IconButton(
                      icon: Icon(Icons.arrow_forward_ios, size: 20),
                      onPressed:
                          _currentProgramIndex < _generatedPrograms.length - 1
                          ? () {
                              setState(() {
                                _currentProgramIndex++;
                              });
                            }
                          : null,
                    ),
                  ),

                // Actions (Icon-only with tooltips)
                if (MediaQuery.of(context).size.width >= 900) ...[
                  SizedBox(width: 16),
                  // History Dropdown
                  if (_historyPrograms.isNotEmpty)
                    PopupMenuButton<Map<String, dynamic>>(
                      tooltip: 'Geçmiş Programlar',
                      icon: Badge(
                        label: Text('${_historyPrograms.length}'),
                        child: Icon(Icons.history, color: Colors.indigo),
                      ),
                      onSelected: (prog) {
                        setState(() {
                          if (!_generatedPrograms.contains(prog)) {
                            _generatedPrograms.add(prog);
                          }
                          _currentProgramIndex = _generatedPrograms.indexOf(
                            prog,
                          );
                          _isProgramGenerated = true;
                        });
                      },
                      itemBuilder: (context) => _historyPrograms.map((prog) {
                        final bool isSavedProgram = prog['id'] != null;
                        dynamic createdAt = prog['createdAt'];
                        String dateStr = 'Tarihsiz';
                        if (createdAt != null) {
                          try {
                            DateTime date;
                            if (createdAt.toString().contains('Timestamp')) {
                              date = (createdAt as dynamic).toDate();
                            } else if (createdAt is String) {
                              date = DateTime.parse(createdAt);
                            } else {
                              date = (createdAt as dynamic).toDate();
                            }
                            dateStr =
                                "${date.day}.${date.month}.${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}";
                          } catch (e) {
                            dateStr = '-';
                          }
                        }
                        return PopupMenuItem<Map<String, dynamic>>(
                          value: prog,
                          child: Row(
                            children: [
                              Icon(
                                !isSavedProgram
                                    ? Icons.fiber_new
                                    : Icons.check_circle_outline,
                                size: 16,
                                color: !isSavedProgram
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      prog['examName'] ?? 'Genel Program',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      !isSavedProgram ? 'YENİ' : dateStr,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  SizedBox(width: 4),
                  Tooltip(
                    message: 'Yeniden Oluştur',
                    child: IconButton(
                      icon: Icon(Icons.refresh),
                      color: Colors.orange,
                      iconSize: 24,
                      onPressed: () {
                        setState(() => _isProgramGenerated = false);
                      },
                    ),
                  ),
                  SizedBox(width: 4),
                  Tooltip(
                    message: 'Kaydet',
                    child: IconButton(
                      icon: Icon(Icons.save),
                      color: Colors.blue,
                      iconSize: 24,
                      onPressed: () => _saveCurrentProgram(),
                    ),
                  ),
                  SizedBox(width: 4),
                  Tooltip(
                    message: 'Yazdır',
                    child: IconButton(
                      icon: Icon(Icons.print),
                      color: Colors.blueGrey,
                      iconSize: 24,
                      onPressed: () => _printProgram(),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // TAB Selection
          Container(
            color: Colors.white,
            child: TabBar(
              labelColor: Colors.purple,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.purple,
              isScrollable: false,
              tabs: [
                Tab(
                  icon: Icon(Icons.psychology_rounded),
                  text: 'Yapay Zeka Koçu',
                ),
                Tab(icon: Icon(Icons.analytics_rounded), text: 'Konu Analizi'),
                Tab(
                  icon: Icon(Icons.calendar_today_rounded),
                  text: 'Çalışma Programı',
                ),
              ],
            ),
          ),

          Expanded(
            child: TabBarView(
              children: [
                // TAB 1: AI LEARNING COACH
                SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildAICommentCard(topicAnalysis),
                      SizedBox(height: 20),
                      _buildIconLegend(),
                    ],
                  ),
                ),

                // TAB 2: TOPIC ANALYSIS TABLE
                SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // SPLIT LIST LOGIC
                      Builder(
                        builder: (context) {
                          // Split by Success Rate (< 70% vs >= 70%)
                          // Split by Dynamic Thresholds
                          Map<String, int> thresholds =
                              (currentProgram['thresholds']
                                      as Map<String, dynamic>?)
                                  ?.map((k, v) => MapEntry(k, v as int)) ??
                              {};

                          final list1 = topicAnalysis
                              .where((e) {
                                String subj = e['subject'];
                                int threshold = thresholds[subj] ?? 70;
                                return ((e['success'] as num?)?.toDouble() ??
                                        0) <
                                    threshold;
                              })
                              .map((e) => e as Map<String, dynamic>)
                              .toList();

                          final list2 = topicAnalysis
                              .where((e) {
                                String subj = e['subject'];
                                int threshold = thresholds[subj] ?? 70;
                                return ((e['success'] as num?)?.toDouble() ??
                                        0) >=
                                    threshold;
                              })
                              .map((e) => e as Map<String, dynamic>)
                              .toList();

                          // Only show "no data" if the original topicAnalysis is empty
                          if (topicAnalysis.isEmpty) {
                            return Padding(
                              padding: EdgeInsets.symmetric(vertical: 32),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.assignment_late_outlined,
                                      size: 48,
                                      color: Colors.grey.shade400,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      "Analiz verisi bulunamadığı için konu listesi oluşturulamadı.",
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 16,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      "Öğrencinin sınav sonucu eksik olabilir.",
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          return Column(
                            children: [
                              // Only show "Çalışılması Gerekenler" if there are topics below threshold
                              if (list1.isNotEmpty) ...[
                                _buildTopicTable(
                                  _isMobile(context)
                                      ? '🔥 Çalışılması Gerekenler'
                                      : '🔥 1. ÖNCELİKLİ KONU LİSTESİ (Çalışılması Gerekenler)',
                                  list1,
                                  0,
                                ),
                                if (list2.isNotEmpty) SizedBox(height: 20),
                              ],
                              // Always show "Pekiştirilecekler" if there are topics at or above threshold
                              if (list2.isNotEmpty)
                                _buildTopicTable(
                                  _isMobile(context)
                                      ? '✅ Pekiştirilecekler'
                                      : '✅ ÖNCELİKLİ KONU LİSTESİ (Pekiştirilecekler)',
                                  list2,
                                  list1.length,
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // TAB 3: SCHEDULE (toggle inline with content, scrolls together)
                _isScheduleTableView
                    ? _buildScheduleTableView(schedule)
                    : _buildScheduleListView(schedule),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleHeader() {
    return Container(
      padding: EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      _isScheduleTableView = false;
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: !_isScheduleTableView
                          ? Colors.purple
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.view_list,
                          size: 18,
                          color: !_isScheduleTableView
                              ? Colors.white
                              : Colors.grey.shade600,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Liste',
                          style: TextStyle(
                            color: !_isScheduleTableView
                                ? Colors.white
                                : Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 4),
                InkWell(
                  onTap: () {
                    setState(() {
                      _isScheduleTableView = true;
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _isScheduleTableView
                          ? Colors.purple
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.table_chart,
                          size: 18,
                          color: _isScheduleTableView
                              ? Colors.white
                              : Colors.grey.shade600,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Tablo',
                          style: TextStyle(
                            color: _isScheduleTableView
                                ? Colors.white
                                : Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicTable(
    String title,
    List<Map<String, dynamic>> items,
    int startIndex,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.purple.shade50),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple.shade400, Colors.purple.shade700],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(Icons.list_alt, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(
                Colors.purple.shade50.withOpacity(0.3),
              ),
              columnSpacing: 20,
              dataRowMinHeight: 60,
              dataRowMaxHeight: 80,
              columns: [
                DataColumn(
                  label: Text(
                    'DURUM',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'ÖNCELİK',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'DERS',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'KONU ADI',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'SS',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'D',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                  numeric: true,
                ),
                DataColumn(
                  label: Text(
                    'Y',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                  numeric: true,
                ),
                DataColumn(
                  label: Text(
                    'B',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                  numeric: true,
                ),
                DataColumn(
                  label: Text(
                    'NET',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                  numeric: true,
                ),
                DataColumn(
                  label: Text(
                    'BAŞARI',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                  numeric: true,
                ),
              ],
              rows: List<DataRow>.generate(items.length, (index) {
                // Calculate dynamic width for topic column
                final screenWidth = MediaQuery.of(context).size.width;
                // Subtract fixed columns width (~850px) to ensure other columns are visible
                double topicWidth = screenWidth - 850;
                // Clamp width between 300 and 500
                if (topicWidth < 300) topicWidth = 300;
                if (topicWidth > 500) topicWidth = 500;
                final item = items[index];
                double success = (item['success'] as num?)?.toDouble() ?? 0;
                final statusInfo = _getStatusInfo(success);

                return DataRow(
                  cells: [
                    DataCell(
                      Tooltip(
                        message: statusInfo['label'],
                        child: Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: statusInfo['bgColor'],
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            statusInfo['icon'],
                            color: statusInfo['color'],
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        '${startIndex + index + 1}',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    DataCell(
                      Text(
                        item['subject'],
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    DataCell(
                      Tooltip(
                        message: item['topic'],
                        child: Container(
                          width: topicWidth,
                          constraints: BoxConstraints(maxWidth: topicWidth),
                          alignment: Alignment.centerLeft,
                          child: Text(
                            item['topic'],
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                            softWrap: true,
                          ),
                        ),
                      ),
                    ),
                    DataCell(Text(item['total'].toString())),
                    DataCell(Text(item['correct'].toString())),
                    DataCell(
                      Text(
                        item['wrong'].toString(),
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    DataCell(Text(item['empty'].toString())),
                    DataCell(Text((item['net'] as num).toStringAsFixed(2))),
                    DataCell(
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: statusInfo['color'],
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: (statusInfo['color'] as Color).withOpacity(
                                0.4,
                              ),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          '%${success.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // SCHEDULE LIST VIEW
  Widget _buildScheduleListView(Map<String, List<String>> schedule) {
    final dayOrder = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];

    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        _buildToggleHeader(),
        ...List.generate(7, (index) {
          final day = dayOrder[index];
          final tasks = (schedule[day] ?? []).where((task) {
            String subject = task.split('\n')[0].trim();
            return !_hiddenSubjects.contains(subject);
          }).toList();

          return Container(
            margin: EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Day Header
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        day,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.indigo.shade900,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.add_circle, color: Colors.indigo),
                        onPressed: () => _showAddTaskDialog(day),
                        tooltip: 'Ders Ekle',
                      ),
                    ],
                  ),
                ),
                // Task List
                if (tasks.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        "Planlanmış ders yok.",
                        style: TextStyle(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  )
                else
                  ...tasks.asMap().entries.map((entry) {
                    int idx = entry.key;
                    String task = entry.value;
                    bool isSmart = task.contains('🎯');
                    return Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade100),
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          backgroundColor: isSmart
                              ? Colors.purple.shade50
                              : Colors.blue.shade50,
                          child: Icon(
                            isSmart ? Icons.batch_prediction : Icons.book,
                            color: isSmart ? Colors.purple : Colors.blue,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          task.split('\n')[0],
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: task.contains('\n')
                            ? Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text(
                                  task.substring(task.indexOf('\n') + 1).trim(),
                                  style: TextStyle(fontSize: 12),
                                ),
                              )
                            : null,
                        trailing: IconButton(
                          icon: Icon(Icons.edit, color: Colors.grey, size: 20),
                          onPressed: () => _editScheduleItem(day, idx),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          );
        }),
      ],
    );
  }

  // SCHEDULE TABLE VIEW
  Widget _buildScheduleTableView(Map<String, List<String>> schedule) {
    final dayOrder = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];

    // Find max number of tasks in any day
    int maxTasks = 0;
    for (var day in dayOrder) {
      final tasks = (schedule[day] ?? []).where((task) {
        String subject = task.split('\n')[0].trim();
        return !_hiddenSubjects.contains(subject);
      }).toList();
      if (tasks.length > maxTasks) maxTasks = tasks.length;
    }

    // Color palette for subjects
    final subjectColors = <String, Color>{};
    final colorPalette = [
      Colors.blue.shade100,
      Colors.green.shade100,
      Colors.orange.shade100,
      Colors.purple.shade100,
      Colors.pink.shade100,
      Colors.teal.shade100,
      Colors.amber.shade100,
      Colors.cyan.shade100,
      Colors.lime.shade100,
      Colors.indigo.shade100,
    ];

    // Assign colors to subjects
    int colorIndex = 0;
    for (var day in dayOrder) {
      final tasks = schedule[day] ?? [];
      for (var task in tasks) {
        String subject = task.split('\n')[0].trim();
        if (!subjectColors.containsKey(subject)) {
          subjectColors[subject] =
              colorPalette[colorIndex % colorPalette.length];
          colorIndex++;
        }
      }
    }

    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        _buildToggleHeader(),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(Colors.indigo.shade50),
              columnSpacing: 16,
              dataRowMinHeight: 90,
              dataRowMaxHeight: 130,
              dividerThickness: 2,
              columns: [
                DataColumn(
                  label: Container(
                    width: 80,
                    child: Text(
                      'Görev\nSırası',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade900,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                ...dayOrder.map((day) {
                  return DataColumn(
                    label: Container(
                      width: 150,
                      child: Text(
                        day,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade900,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }).toList(),
              ],
              rows: [
                // Existing task rows
                ...List.generate(maxTasks, (rowIndex) {
                  return DataRow(
                    cells: [
                      // Row header (task number)
                      DataCell(
                        Container(
                          width: 80,
                          alignment: Alignment.center,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade100,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Görev ${rowIndex + 1}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo.shade900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Day cells
                      ...dayOrder.map((day) {
                        final tasks = (schedule[day] ?? []).where((task) {
                          String subject = task.split('\n')[0].trim();
                          return !_hiddenSubjects.contains(subject);
                        }).toList();

                        if (rowIndex >= tasks.length) {
                          // Empty cell - clickable to add task
                          return DataCell(
                            Container(
                              width: 150,
                              margin: EdgeInsets.all(4),
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.grey.shade300,
                                  style: BorderStyle.solid,
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.add_circle_outline,
                                  color: Colors.grey.shade400,
                                  size: 24,
                                ),
                              ),
                            ),
                            onTap: () => _showAddTaskDialog(day),
                          );
                        }

                        final task = tasks[rowIndex];
                        final subject = task.split('\n')[0];
                        final details = task.contains('\n')
                            ? task.substring(task.indexOf('\n') + 1).trim()
                            : '';
                        final isSmart = task.contains('🎯');
                        final bgColor =
                            subjectColors[subject] ?? Colors.grey.shade100;

                        return DataCell(
                          Container(
                            width: 150,
                            margin: EdgeInsets.all(4),
                            padding: EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: bgColor,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSmart
                                    ? Colors.purple.shade300
                                    : Colors.blue.shade300,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: bgColor.withOpacity(0.5),
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isSmart ? Icons.auto_awesome : Icons.book,
                                      size: 14,
                                      color: isSmart
                                          ? Colors.purple.shade700
                                          : Colors.blue.shade700,
                                    ),
                                    SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        subject,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: Colors.black87,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if (details.isNotEmpty) ...[
                                  SizedBox(height: 6),
                                  Text(
                                    details,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey.shade800,
                                      height: 1.3,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          onTap: () => _editScheduleItem(day, rowIndex),
                        );
                      }).toList(),
                    ],
                  );
                }),
                // Add new task row
                DataRow(
                  cells: [
                    DataCell(
                      Container(
                        width: 80,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.add,
                          color: Colors.indigo.shade400,
                          size: 20,
                        ),
                      ),
                    ),
                    ...dayOrder.map((day) {
                      return DataCell(
                        Container(
                          width: 150,
                          margin: EdgeInsets.all(4),
                          padding: EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.indigo.shade200,
                              style: BorderStyle.solid,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_circle,
                                color: Colors.indigo.shade600,
                                size: 18,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Görev Ekle',
                                style: TextStyle(
                                  color: Colors.indigo.shade700,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        onTap: () => _showAddTaskDialog(day),
                      );
                    }).toList(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 5. TEKİL SINAV SEÇİM SAYFASI (Yeni Sayfa Olarak)
  Future<TrialExam?> _showSingleExamSelectionDialog(
    List<TrialExam> exams,
  ) async {
    return await Navigator.of(context).push<TrialExam>(
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: Colors.white,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.indigo),
              onPressed: () => Navigator.pop(ctx),
            ),
            title: Text(
              'Sınav Seçiniz',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            centerTitle: true,
          ),
          body: Column(
            children: [
              // Search
              Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Sınav ara...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onChanged: (val) {
                    // TODO: Client side search if needed
                  },
                ),
              ),

              // List
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  itemCount: exams.length,
                  separatorBuilder: (c, i) => SizedBox(height: 12),
                  itemBuilder: (c, i) {
                    final ex = exams[i];
                    return InkWell(
                      onTap: () => Navigator.pop(ctx, ex),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.assignment_outlined,
                                color: Colors.blue.shade700,
                                size: 24,
                              ),
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ex.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    "${ex.classLevel} • ${ex.date.day}.${ex.date.month}.${ex.date.year}",
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              color: Colors.grey.shade400,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // 6. ÇOKLU SINAV SEÇİM SAYFASI (Yeni Sayfa Olarak)
  Future<List<TrialExam>?> _showMultiExamSelectionDialog(
    List<TrialExam> exams,
  ) async {
    List<TrialExam> selected = [];

    return await Navigator.of(context).push<List<TrialExam>>(
      MaterialPageRoute(
        builder: (ctx) {
          return StatefulBuilder(
            builder: (context, setStateDialog) {
              return Scaffold(
                backgroundColor: Colors.white,
                appBar: AppBar(
                  elevation: 0,
                  backgroundColor: Colors.white,
                  leading: IconButton(
                    icon: Icon(Icons.arrow_back, color: Colors.indigo),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Sınavları Seçiniz',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                      Text(
                        "Birleştirmek istediğiniz sınavları işaretleyin.",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  centerTitle: true,
                ),
                body: Column(
                  children: [
                    // Exam List
                    Expanded(
                      child: ListView.separated(
                        padding: EdgeInsets.all(20),
                        itemCount: exams.length,
                        separatorBuilder: (c, i) => SizedBox(height: 8),
                        itemBuilder: (c, i) {
                          final ex = exams[i];
                          final isSelected = selected.contains(ex);
                          return InkWell(
                            onTap: () {
                              setStateDialog(() {
                                if (isSelected) {
                                  selected.remove(ex);
                                } else {
                                  selected.add(ex);
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 0,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.indigo
                                      : Colors.grey.shade200,
                                  width: isSelected ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                color: isSelected
                                    ? Colors.indigo.withOpacity(0.05)
                                    : Colors.white,
                              ),
                              child: CheckboxListTile(
                                value: isSelected,
                                onChanged: (val) {
                                  setStateDialog(() {
                                    if (val == true) {
                                      selected.add(ex);
                                    } else {
                                      selected.remove(ex);
                                    }
                                  });
                                },
                                title: Text(
                                  ex.name,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 14,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  "${ex.classLevel} • ${ex.date.day}.${ex.date.month}.${ex.date.year}",
                                  style: TextStyle(fontSize: 12),
                                ),
                                activeColor: Colors.indigo,
                                dense: true,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // Bottom Buttons
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigo,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: selected.isEmpty
                                  ? null
                                  : () {
                                      Navigator.pop(ctx, selected);
                                    },
                              child: Text(
                                "Seçili Sınavları Birleştir (${selected.length})",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: 8),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(
                              "İptal",
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showProgramCreationOptionsDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 400,
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Program Oluşturma Yöntemi",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 24),
              // Option 1: Manual
              _buildCreationOption(
                icon: Icons.edit_note_rounded,
                color: Colors.orange,
                title: "Manuel Program",
                description:
                    "Sınav verisi olmadan, sadece seçili şablonu baz alan boş bir program oluşturur.",
                onTap: () {
                  Navigator.pop(context);
                  _createManualProgram();
                },
              ),
              SizedBox(height: 16),
              // Option 2: Single Exam
              _buildCreationOption(
                icon: Icons.assignment_rounded,
                color: Colors.blue,
                title: "Tekil Sınav Programı",
                description:
                    "Tek bir sınav seçilir ve analizine göre kişiselleştirilmiş program oluşturulur.",
                onTap: () {
                  Navigator.pop(context);
                  _startSingleExamProgramCreation();
                },
              ),
              SizedBox(height: 16),
              // Option 3: Combined Exam
              _buildCreationOption(
                icon: Icons.copy_all_rounded,
                color: Colors.purple,
                title: "Birleşik Sınav Programı",
                description:
                    "Birden fazla sınav seçilir ve ortak analize göre program oluşturulur.",
                onTap: () {
                  Navigator.pop(context);
                  _startCombinedExamProgramCreation();
                },
              ),
              SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("İptal", style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreationOption({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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

  Future<void> _showAddTaskDialog(String day) async {
    // Extract unique subjects
    List<Map<String, dynamic>> analysis =
        (_generatedPrograms[_currentProgramIndex]['topicAnalysis']
                as List<dynamic>?)
            ?.map((e) => e as Map<String, dynamic>)
            .toList() ??
        [];
    Set<String> subjects = analysis.map((e) => e['subject'] as String).toSet();

    // Default values
    String? selectedSubject = subjects.isNotEmpty ? subjects.first : null;
    final topicController = TextEditingController();
    String activityType = "Konu Çalışması";

    // Activity Icons
    final Map<String, IconData> activityIcons = {
      "Konu Çalışması": Icons.menu_book,
      "Soru Çözümü": Icons.quiz,
      "Video İzleme": Icons.play_circle,
      "Tekrar": Icons.refresh,
      "Deneme": Icons.timelapse,
    };

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                width: 450,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.white,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.indigo.shade600,
                            Colors.purple.shade600,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.add_task,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$day',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Yeni Görev Ekle',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Content
                    Flexible(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Ders Seçimi
                            Text(
                              "Ders Seçimi",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            SizedBox(height: 12),
                            if (subjects.isNotEmpty)
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: ButtonTheme(
                                    alignedDropdown: true,
                                    child: DropdownButton<String>(
                                      value: selectedSubject,
                                      isExpanded: true,
                                      borderRadius: BorderRadius.circular(12),
                                      icon: Icon(
                                        Icons.arrow_drop_down_circle,
                                        color: Colors.indigo,
                                      ),
                                      items: subjects.map((s) {
                                        return DropdownMenuItem(
                                          value: s,
                                          child: Text(
                                            s,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (v) => setDialogState(
                                        () => selectedSubject = v,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            else
                              Text(
                                "Ders listesi verisi bulunamadı. Sadece konu girebilirsiniz.",
                                style: TextStyle(color: Colors.red),
                              ),

                            SizedBox(height: 24),

                            // 2. Aktivite Tipi
                            Center(
                              child: Text(
                                "Aktivite Tipi",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ),
                            SizedBox(height: 12),
                            Center(
                              child: Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                alignment: WrapAlignment.center,
                                children: activityIcons.entries.map((entry) {
                                  bool isSelected = activityType == entry.key;
                                  return FilterChip(
                                    label: Text(entry.key),
                                    avatar: Icon(
                                      entry.value,
                                      size: 18,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.indigo.shade300,
                                    ),
                                    selected: isSelected,
                                    selectedColor: Colors.purple.shade400,
                                    checkmarkColor: Colors.white,
                                    labelStyle: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.grey.shade800,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                    backgroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      side: BorderSide(
                                        color: isSelected
                                            ? Colors.transparent
                                            : Colors.grey.shade300,
                                      ),
                                    ),
                                    onSelected: (selected) {
                                      if (selected) {
                                        setDialogState(
                                          () => activityType = entry.key,
                                        );
                                      }
                                    },
                                  );
                                }).toList(),
                              ),
                            ),

                            SizedBox(height: 24),

                            // 3. Konu / Not
                            Text(
                              "Konu veya Not Detayı",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            SizedBox(height: 8),
                            TextField(
                              controller: topicController,
                              decoration: InputDecoration(
                                hintText: 'Örn: Veri Analizi Soru Çözümü',
                                filled: true,
                                fillColor: Colors.grey.shade50,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                                suffixIcon: Icon(
                                  Icons.edit_note,
                                  color: Colors.grey,
                                ),
                              ),
                              maxLines: 2,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Actions
                    Container(
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: Text(
                              'İptal',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () {
                              // Create Task String
                              String task = selectedSubject ?? "";
                              String details = topicController.text.trim();

                              if (task.isNotEmpty) {
                                if (details.isNotEmpty) {
                                  task += "\n$details ($activityType)";
                                } else {
                                  task += "\n($activityType)";
                                }
                              } else {
                                // No subject selected
                                task = details.isNotEmpty
                                    ? "$details ($activityType)"
                                    : activityType;
                              }

                              // Update Main Data
                              setState(() {
                                var currentProg =
                                    _generatedPrograms[_currentProgramIndex];
                                var sch = currentProg['schedule'];

                                // Ensure schedule is mutable map
                                if (sch is Map) {
                                  if (sch[day] == null) {
                                    sch[day] = [];
                                  }

                                  // Check if list is mutable, if not make it
                                  if (sch[day] is! List) {
                                    sch[day] = [];
                                  } else {
                                    // Is it a fixed list? Try adding.
                                    try {
                                      (sch[day] as List).add(task);
                                    } catch (e) {
                                      // If failed (e.g. fixed length), replace with new list
                                      List<dynamic> newList = List.from(
                                        sch[day],
                                      );
                                      newList.add(task);
                                      sch[day] = newList;
                                    }
                                  }
                                }
                              });

                              Navigator.pop(dialogContext);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                            icon: Icon(Icons.add_circle, size: 18),
                            label: Text(
                              'Görevi Ekle',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
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

  Future<void> _saveCurrentProgram() async {
    if (_generatedPrograms.isEmpty) return;

    // Check for bulk save
    if (_generatedPrograms.length > 1) {
      final choice = await showDialog<int>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Program Kaydet'),
          content: Text(
            '${_generatedPrograms.length} adet program oluşturuldu. Nasıl kaydetmek istersiniz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 1),
              child: Text('Sadece Bunu Kaydet'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 2),
              child: Text('Tümünü Kaydet'),
            ),
          ],
        ),
      );

      if (choice == null) return;

      if (choice == 2) {
        await _saveAllPrograms();
        return;
      }
    }

    try {
      await _saveSingleProgram(_generatedPrograms[_currentProgramIndex]);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Program başarıyla kaydedildi.')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Future<void> _saveAllPrograms() async {
    setState(() => _isLoading = true);
    int successCount = 0;
    try {
      for (var program in _generatedPrograms) {
        await _saveSingleProgram(program);
        successCount++;
      }
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$successCount program başarıyla kaydedildi.')),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Toplu Kaydetme Hatası: $e')));
    }
  }

  Future<void> _saveSingleProgram(Map<String, dynamic> program) async {
    // Create a copy to modify for saving
    final programToSave = Map<String, dynamic>.from(program);

    // Use the most robust extraction for the saved document
    String rawBranch =
        (programToSave['studentBranch'] ??
                programToSave['branch'] ??
                programToSave['sube'] ??
                programToSave['shube'] ??
                programToSave['class'] ??
                programToSave['studentClass'] ??
                programToSave['className'] ??
                programToSave['class_name'] ??
                programToSave['studentGroup'] ??
                '')
            .toString()
            .trim();

    final rawLevel =
        (programToSave['classLevel'] ??
                programToSave['level'] ??
                (programToSave['student'] != null
                    ? (programToSave['student']['classLevel'] ??
                          programToSave['student']['level'])
                    : ''))
            .toString()
            .trim();

    String finalBranch = rawBranch;
    if (finalBranch.isEmpty) {
      finalBranch = rawLevel.isNotEmpty ? "$rawLevel. Sınıf" : 'Sınıfsız';
    } else if (rawLevel.isNotEmpty) {
      String levelDigits = rawLevel.replaceAll(RegExp(r'[^0-9]'), '');
      if (levelDigits.isNotEmpty && !finalBranch.contains(levelDigits)) {
        finalBranch = "$levelDigits-$finalBranch";
      }
    }

    programToSave['studentBranch'] = finalBranch;
    programToSave['className'] = finalBranch;

    // Serialize template if it exists as an object
    if (programToSave['template'] is StudyTemplate) {
      programToSave['template'] = (programToSave['template'] as StudyTemplate)
          .toMap();
    }

    // Ensure creatorId is set if missing (fallback)
    if (programToSave['creatorId'] == null) {
      programToSave['creatorId'] = FirebaseAuth.instance.currentUser?.uid;
      programToSave['creatorName'] =
          FirebaseAuth.instance.currentUser?.displayName ?? 'Eğitmen';
    }

    // Save to Firestore via service
    await GuidanceService().saveStudyProgram(
      widget.institutionId,
      programToSave,
    );

    // Update the original program with ID and timestamp
    setState(() {
      // Generate a mock ID if not returned from service
      if (program['id'] == null) {
        program['id'] = DateTime.now().millisecondsSinceEpoch.toString();
      }
      program['createdAt'] = DateTime.now();

      // Add to history if not already there
      if (!_historyPrograms.contains(program)) {
        _historyPrograms.insert(0, program);
      }
    });
  }

  // --- PRINTING & PDF GENERATION ---

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

  Future<void> _printProgram() async {
    // Check if we have bulk options
    if (_generatedPrograms.length > 1) {
      await _showPrintOptionsDialog();
    } else {
      // Single program (Original behavior)
      final contentSelection = await _showContentSelectionDialog();
      if (contentSelection == null) return;

      await _generateSinglePdf(
        _generatedPrograms[_currentProgramIndex],
        includeSchedule: contentSelection['schedule']!,
        includeAnalysis: contentSelection['analysis']!,
        showPriority1: contentSelection['priority1'] ?? true,
        showPriority2: contentSelection['priority2'] ?? true,
      );
    }
  }

  Future<void> _showPrintOptionsDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Yazdırma Seçenekleri'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.print, color: Colors.indigo),
              title: Text('Sadece Şu Ankini Yazdır'),
              subtitle: Text(
                '${_generatedPrograms[_currentProgramIndex]['studentName']}',
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final contentSelection = await _showContentSelectionDialog();
                if (contentSelection != null) {
                  _generateSinglePdf(
                    _generatedPrograms[_currentProgramIndex],
                    includeSchedule: contentSelection['schedule']!,
                    includeAnalysis: contentSelection['analysis']!,
                    showPriority1: contentSelection['priority1'] ?? true,
                    showPriority2: contentSelection['priority2'] ?? true,
                  );
                }
              },
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.playlist_add_check, color: Colors.green),
              title: Text('Seç ve Yazdır'),
              subtitle: Text('Listeden öğrencileri seçin'),
              onTap: () {
                Navigator.pop(ctx);
                _showMultiProgramSelectionDialog();
              },
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.copy_all, color: Colors.orange),
              title: Text(
                'Tümünü Yazdır (${_generatedPrograms.length} Öğrenci)',
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final contentSelection = await _showContentSelectionDialog();
                if (contentSelection != null) {
                  _showOutputFormatDialog(
                    _generatedPrograms,
                    includeSchedule: contentSelection['schedule']!,
                    includeAnalysis: contentSelection['analysis']!,
                    showPriority1: contentSelection['priority1'] ?? true,
                    showPriority2: contentSelection['priority2'] ?? true,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMultiProgramSelectionDialog() async {
    // 1. Show Selection Dialog
    final selected = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (ctx) {
        List<Map<String, dynamic>> tempSelected = [];
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Öğrenci Seçimi'),
              content: Container(
                width: double.maxFinite,
                height: 300,
                child: Column(
                  children: [
                    CheckboxListTile(
                      title: Text('Tümünü Seç'),
                      value: tempSelected.length == _generatedPrograms.length,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            tempSelected = List.from(_generatedPrograms);
                          } else {
                            tempSelected = [];
                          }
                        });
                      },
                    ),
                    Divider(),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _generatedPrograms.length,
                        itemBuilder: (c, i) {
                          final p = _generatedPrograms[i];
                          final isSelected = tempSelected.contains(p);
                          return CheckboxListTile(
                            title: Text(p['studentName']),
                            subtitle: Text(p['examName']),
                            value: isSelected,
                            onChanged: (val) {
                              setState(() {
                                if (val == true)
                                  tempSelected.add(p);
                                else
                                  tempSelected.remove(p);
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, tempSelected),
                  child: Text('Devam Et (${tempSelected.length})'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected != null && selected.isNotEmpty) {
      final contentSelection = await _showContentSelectionDialog();
      if (contentSelection != null) {
        if (selected.length == 1) {
          // Direct Single PDF for 1 student
          await _generateSinglePdf(
            selected.first,
            includeSchedule: contentSelection['schedule']!,
            includeAnalysis: contentSelection['analysis']!,
            showPriority1: contentSelection['priority1'] ?? true,
            showPriority2: contentSelection['priority2'] ?? true,
          );
        } else {
          _showOutputFormatDialog(
            selected,
            includeSchedule: contentSelection['schedule']!,
            includeAnalysis: contentSelection['analysis']!,
            showPriority1: contentSelection['priority1'] ?? true,
            showPriority2: contentSelection['priority2'] ?? true,
          );
        }
      }
    }
  }

  Future<void> _showOutputFormatDialog(
    List<Map<String, dynamic>> programs, {
    required bool includeSchedule,
    required bool includeAnalysis,
    required bool showPriority1,
    required bool showPriority2,
  }) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Çıktı Formatı'),
        content: Text(
          '${programs.length} öğrenci için çıktı formatını seçiniz.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _generateBulkPdf(
                programs,
                includeSchedule: includeSchedule,
                includeAnalysis: includeAnalysis,
                showPriority1: showPriority1,
                showPriority2: showPriority2,
              );
            },
            child: Column(
              children: [
                Icon(Icons.picture_as_pdf, size: 30),
                Text('Tek PDF (Birleşik)'),
              ],
            ),
          ),
          SizedBox(width: 20),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _generateBulkZip(
                programs,
                includeSchedule: includeSchedule,
                includeAnalysis: includeAnalysis,
                showPriority1: showPriority1,
                showPriority2: showPriority2,
              );
            },
            child: Column(
              children: [
                Icon(Icons.folder_zip, size: 30),
                Text('Ayrı Ayrı (ZIP)'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- GENERATION METHODS ---

  Future<void> _loadPrintAssets() async {
    _pdfFont ??= await PdfGoogleFonts.openSansRegular();
    _pdfFontBold ??= await PdfGoogleFonts.openSansBold();
    _pdfFontItalic ??= await PdfGoogleFonts.openSansItalic();
    _pdfFontIcons ??= await PdfGoogleFonts.materialIcons();

    if (_pdfLogo == null) {
      try {
        final logoData = await rootBundle.load('assets/images/logo.png');
        _pdfLogo = pw.MemoryImage(logoData.buffer.asUint8List());
      } catch (e) {
        debugPrint('Logo load error: $e');
      }
    }
  }

  Future<void> _generateSinglePdf(
    Map<String, dynamic> program, {
    required bool includeSchedule,
    required bool includeAnalysis,
    required bool showPriority1,
    required bool showPriority2,
  }) async {
    // Show Loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => Center(child: CircularProgressIndicator()),
    );

    try {
      final pdf = pw.Document();

      // Load Assets once (cached)
      await _loadPrintAssets();

      await _addProgramToDocument(
        pdf,
        program,
        _pdfFont!,
        _pdfFontBold!,
        _pdfFontItalic!,
        _pdfFontIcons!,
        logo: _pdfLogo,
        includeSchedule: includeSchedule,
        includeAnalysis: includeAnalysis,
        showPriority1: showPriority1,
        showPriority2: showPriority2,
      );

      // Close Loading
      Navigator.pop(context);

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'calisma-programi-${program['studentName']}.pdf',
      );
    } catch (e) {
      // Close Loading on Error
      if (Navigator.canPop(context)) Navigator.pop(context);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata (Tekli PDF): $e')));
    }
  }

  Future<void> _generateBulkPdf(
    List<Map<String, dynamic>> programs, {
    required bool includeSchedule,
    required bool includeAnalysis,
    required bool showPriority1,
    required bool showPriority2,
  }) async {
    final progress = ValueNotifier<double>(0);
    final status = ValueNotifier<String>('PDF\'ler Hazırlanıyor...');
    final progressContext = context;
    _isOperationCancelled = false;

    _showProgressDialog(
      progress,
      status,
      onCancel: () {
        _isOperationCancelled = true;
      },
    );

    try {
      final pdf = pw.Document();
      await _loadPrintAssets();

      for (var i = 0; i < programs.length; i++) {
        if (_isOperationCancelled) break;

        await _addProgramToDocument(
          pdf,
          programs[i],
          _pdfFont!,
          _pdfFontBold!,
          _pdfFontItalic!,
          _pdfFontIcons!,
          logo: _pdfLogo,
          includeSchedule: includeSchedule,
          includeAnalysis: includeAnalysis,
          showPriority1: showPriority1,
          showPriority2: showPriority2,
        );

        progress.value = (i + 1) / programs.length;
        status.value = 'PDF Hazırlanıyor (${i + 1} / ${programs.length})';
        await Future.delayed(Duration.zero);
      }

      if (_isOperationCancelled) {
        if (Navigator.canPop(progressContext)) Navigator.pop(progressContext);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('İşlem iptal edildi.')));
        return;
      }

      status.value = 'Dosya Kaydediliyor...';
      final bytes = await pdf.save();

      if (Navigator.canPop(progressContext)) Navigator.pop(progressContext);

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => bytes,
        name: 'toplu-calisma-programi.pdf',
      );
    } catch (e) {
      if (Navigator.canPop(progressContext)) Navigator.pop(progressContext);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata (Toplu PDF): $e')));
    }
  }

  Future<void> _generateBulkZip(
    List<Map<String, dynamic>> programs, {
    required bool includeSchedule,
    required bool includeAnalysis,
    required bool showPriority1,
    required bool showPriority2,
  }) async {
    final progress = ValueNotifier<double>(0);
    final status = ValueNotifier<String>('PDF\'ler Hazırlanıyor...');
    final progressContext = context;
    _isOperationCancelled = false;

    _showProgressDialog(
      progress,
      status,
      onCancel: () {
        _isOperationCancelled = true;
      },
    );

    try {
      await _loadPrintAssets();
      final Map<String, Uint8List> pdfFiles = {};

      const int chunkSize = 3; // Reduced chunk size for smoother UI
      for (int i = 0; i < programs.length; i += chunkSize) {
        if (_isOperationCancelled) break;

        final end = (i + chunkSize > programs.length)
            ? programs.length
            : i + chunkSize;
        final chunk = programs.sublist(i, end);

        final results = await Future.wait(
          chunk.map((program) async {
            final pdf = pw.Document();
            await _addProgramToDocument(
              pdf,
              program,
              _pdfFont!,
              _pdfFontBold!,
              _pdfFontItalic!,
              _pdfFontIcons!,
              logo: _pdfLogo,
              includeSchedule: includeSchedule,
              includeAnalysis: includeAnalysis,
              showPriority1: showPriority1,
              showPriority2: showPriority2,
            );
            final bytes = await pdf.save();
            return MapEntry('program-${program['studentName']}.pdf', bytes);
          }),
        );

        for (var entry in results) {
          pdfFiles[entry.key] = entry.value;
        }

        progress.value = pdfFiles.length / programs.length;
        status.value =
            'Dosyalar Hazırlanıyor (${pdfFiles.length} / ${programs.length})';
        await Future.delayed(const Duration(milliseconds: 50));
      }

      if (_isOperationCancelled) {
        if (Navigator.canPop(progressContext)) Navigator.pop(progressContext);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('İşlem iptal edildi.')));
        return;
      }

      status.value = 'Dosyalar Sıkıştırılıyor...';
      progress.value = 1.0;

      final zipData = await compute(_encodeZipIsolate, pdfFiles);

      if (Navigator.canPop(progressContext)) Navigator.pop(progressContext);

      if (zipData != null) {
        await Printing.sharePdf(
          bytes: zipData,
          filename: 'calisma-programlari.zip',
        );
      }
    } catch (e) {
      if (Navigator.canPop(progressContext)) Navigator.pop(progressContext);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata (ZIP): $e')));
    }
  }

  void _showProgressDialog(
    ValueNotifier<double> progress,
    ValueNotifier<String> status, {
    VoidCallback? onCancel,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<double>(
                    valueListenable: progress,
                    builder: (context, value, _) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 70,
                            height: 70,
                            child: CircularProgressIndicator(
                              value: value == 0 ? null : value,
                              strokeWidth: 6,
                              backgroundColor: Colors.grey[200],
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).primaryColor,
                              ),
                            ),
                          ),
                          if (value > 0)
                            Text(
                              '${(value * 100).toInt()}%',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  ValueListenableBuilder<String>(
                    valueListenable: status,
                    builder: (context, value, _) {
                      return Text(
                        value,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Lütfen bekleyiniz, bu işlem biraz zaman alabilir.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        onCancel?.call();
                        Navigator.pop(context);
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.red[100]!),
                        ),
                      ),
                      child: const Text(
                        'İşlemi İptal Et',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // --- COLOR & ICON STYLE HELPER ---
  Map<String, dynamic> _getSubjectStyle(String subject) {
    // Robust Normalization
    String normalize(String input) {
      return input
          .replaceAll('İ', 'i')
          .replaceAll('I', 'i')
          .replaceAll('ı', 'i')
          .replaceAll('Ğ', 'g')
          .replaceAll('ğ', 'g')
          .replaceAll('Ü', 'u')
          .replaceAll('ü', 'u')
          .replaceAll('Ş', 's')
          .replaceAll('ş', 's')
          .replaceAll('Ö', 'o')
          .replaceAll('ö', 'o')
          .replaceAll('Ç', 'c')
          .replaceAll('ç', 'c')
          .toLowerCase();
    }

    final sRaw = subject.trim();
    final sNorm = normalize(sRaw);

    // Matematik (Blue)
    if (sRaw.contains('Matematik') ||
        sNorm.contains('matematik') ||
        sNorm.contains('geometri')) {
      return {
        'bg': PdfColor.fromInt(0xFFE3F2FD),
        'accent': PdfColor.fromInt(0xFF1565C0),
        'icon': const pw.IconData(0xef45), // calculate
      };
    }

    // Fen (Green)
    if (sRaw.contains('Fen') ||
        sNorm.contains('fen') ||
        sNorm.contains('fizik') ||
        sNorm.contains('kimya') ||
        sNorm.contains('biyoloji')) {
      return {
        'bg': PdfColor.fromInt(0xFFE8F5E9),
        'accent': PdfColor.fromInt(0xFF2E7D32),
        'icon': const pw.IconData(0xea46), // science
      };
    }

    // Sosyal (Orange)
    if (sRaw.contains('Sosyal') ||
        sNorm.contains('sosyal') ||
        sNorm.contains('inkilap') ||
        sNorm.contains('tarih') ||
        sNorm.contains('cografya') ||
        sNorm.contains('felsefe')) {
      return {
        'bg': PdfColor.fromInt(0xFFFFF3E0),
        'accent': PdfColor.fromInt(0xFFEF6C00),
        'icon': const pw.IconData(0xe80b), // public
      };
    }

    // Türkçe (Purple)
    if (sRaw.contains('Türkçe') ||
        sNorm.contains('turkce') ||
        sNorm.contains('edebiyat') ||
        sNorm.contains('okuma')) {
      return {
        'bg': PdfColor.fromInt(0xFFF3E5F5),
        'accent': PdfColor.fromInt(0xFF7B1FA2),
        'icon': const pw.IconData(0xe8af), // menu_book
      };
    }

    // İngilizce (Cyan)
    if (sRaw.contains('İngilizce') ||
        sNorm.contains('ingilizce') ||
        sNorm.contains('yabanci') ||
        sNorm.contains('dil') ||
        sNorm.contains('almanca')) {
      return {
        'bg': PdfColor.fromInt(0xFFE0F7FA),
        'accent': PdfColor.fromInt(0xFF0097A7),
        'icon': const pw.IconData(0xe894), // language
      };
    }

    // Din (Pink)
    if (sRaw.contains('Din') || sNorm.contains('din')) {
      return {
        'bg': PdfColor.fromInt(0xFFFCE4EC),
        'accent': PdfColor.fromInt(0xFFC2185B),
        'icon': const pw.IconData(0xea40), // self_improvement
      };
    }

    // Default (Grey/Indigo)
    return {
      'bg': PdfColor.fromInt(0xFFFAFAFA),
      'accent': PdfColors.indigo,
      'icon': const pw.IconData(0xe896), // note
    };
  }

  String shortenSub(String sub) {
    if (sub == 'İlköğretim Matematik') return 'Matematik';
    return sub;
  }

  // --- CORE PDF BUILDER ---
  Future<void> _addProgramToDocument(
    pw.Document pdf,
    Map<String, dynamic> program,
    pw.Font font,
    pw.Font fontBold,
    pw.Font fontItalic,
    pw.Font fontIcons, {
    pw.MemoryImage? logo,
    required bool includeSchedule,
    required bool includeAnalysis,
    required bool showPriority1,
    required bool showPriority2,
  }) async {
    final studentName = program['studentName'] ?? 'Ogrenci';
    // Safe casting for schedule
    final schedule = (program['schedule'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(key, List<String>.from(value ?? [])),
    );
    // Safe casting for topicAnalysis
    final analysisList = (program['topicAnalysis'] as List<dynamic>? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .toList();

    final thresholds =
        (program['thresholds'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v as int),
        ) ??
        {};

    // AI Report Logic (User Requested Static Message)
    String aiReportContent =
        "Selam $studentName, senin için hazırladığımız bu program, son deneme sınavındaki eksiklerini kapatmaya yönelik özel bir yol haritasıdır. Bu çalışmaları aksatmadan yürütürken, öğretmenlerinin verdiği ödevleri de programa dahil ederek disiplinli bir şekilde ilerlemeni bekliyoruz. Başarılar dileriz!";

    // Page 1: Analysis (Portrait) - NOW FIRST
    if (includeAnalysis && analysisList.isNotEmpty) {
      // Filter Lists
      final priority1List = analysisList.where((item) {
        int t = thresholds[item['subject']] ?? 70;
        double s = (item['success'] as num?)?.toDouble() ?? 0;
        int wrong = (item['wrong'] as int?) ?? 0;
        return (s < t || wrong > 0);
      }).toList();

      final priority2List = analysisList.where((item) {
        int t = thresholds[item['subject']] ?? 70;
        double s = (item['success'] as num?)?.toDouble() ?? 0;
        int wrong = (item['wrong'] as int?) ?? 0;
        return (s >= t && wrong == 0);
      }).toList();

      if ((showPriority1 && priority1List.isNotEmpty) ||
          (showPriority2 && priority2List.isNotEmpty)) {
        pdf.addPage(
          pw.MultiPage(
            pageTheme: pw.PageTheme(
              pageFormat: PdfPageFormat
                  .a4, // Restored to Portrait and moved inside theme
              theme: pw.ThemeData.withFont(
                base: font,
                bold: fontBold,
                italic: fontItalic,
                icons: fontIcons,
              ),
              buildBackground: (context) => logo == null
                  ? pw.SizedBox()
                  : pw.Center(
                      child: pw.Opacity(
                        opacity: 0.07, // Halved opacity
                        child: pw.Image(logo, width: 150), // Smaller width
                      ),
                    ),
            ),
            build: (pw.Context context) {
              return [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      "KİŞİSELLEŞTİRİLMİŞ KAZANIM ANALİZİ",
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.indigo900,
                      ),
                    ),
                    pw.Text(
                      "$studentName",
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 12),

                // Priority 1
                if (showPriority1 && priority1List.isNotEmpty) ...[
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 8,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.red50,
                      border: pw.Border(
                        left: pw.BorderSide(color: PdfColors.red, width: 3),
                      ),
                    ),
                    child: pw.Text(
                      "1. Öncelikli Konu Listesi (Çalışılması Gerekenler)",
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.red900,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  _buildAnalysisListTable(priority1List, true),
                  pw.SizedBox(height: 16),
                ],

                // Priority 2
                if (showPriority2 && priority2List.isNotEmpty) ...[
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 8,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.blue50,
                      border: pw.Border(
                        left: pw.BorderSide(color: PdfColors.blue, width: 3),
                      ),
                    ),
                    child: pw.Text(
                      "2. Öncelikli Konu Listesi (Pekiştirilecekler)",
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  _buildAnalysisListTable(priority2List, false),
                ],
              ];
            },
          ),
        );
      }
    }

    // Page 2: Schedule (Landscape)
    if (includeSchedule) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20), // Reduced margins
          theme: pw.ThemeData.withFont(
            base: font,
            bold: fontBold,
            italic: fontItalic,
            icons: fontIcons,
          ),
          build: (pw.Context context) {
            return pw.Stack(
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // HEADER
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          "Bireysel Analiz Temelli Gelişim Programı",
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.indigo900,
                          ),
                        ),
                        pw.Text(
                          "$studentName - ${DateFormat('yyyy-MM-dd').format(DateTime.now())}",
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 5),
                    // SCHEDULE TABLE (RESTORED)
                    pw.Table(
                      border: pw.TableBorder.all(color: PdfColors.grey300),
                      columnWidths: {
                        0: pw.FlexColumnWidth(1),
                        1: pw.FlexColumnWidth(1),
                        2: pw.FlexColumnWidth(1),
                        3: pw.FlexColumnWidth(1),
                        4: pw.FlexColumnWidth(1),
                        5: pw.FlexColumnWidth(1),
                        6: pw.FlexColumnWidth(1),
                      },
                      children: [
                        // A. Header Row
                        pw.TableRow(
                          decoration: pw.BoxDecoration(
                            color: PdfColors.grey200,
                          ),
                          children:
                              [
                                    'Pazartesi',
                                    'Salı',
                                    'Çarşamba',
                                    'Perşembe',
                                    'Cuma',
                                    'Cumartesi',
                                    'Pazar',
                                  ]
                                  .map(
                                    (day) => pw.Container(
                                      padding: const pw.EdgeInsets.all(8),
                                      alignment: pw.Alignment.center,
                                      child: pw.Text(
                                        day,
                                        style: pw.TextStyle(
                                          fontWeight: pw.FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                        ),
                        // B. Content Row
                        pw.TableRow(
                          children:
                              [
                                'Pazartesi',
                                'Salı',
                                'Çarşamba',
                                'Perşembe',
                                'Cuma',
                                'Cumartesi',
                                'Pazar',
                              ].map((day) {
                                List<String> lessons = schedule[day] ?? [];
                                return pw.Container(
                                  padding: const pw.EdgeInsets.all(5),
                                  child: pw.Column(
                                    crossAxisAlignment:
                                        pw.CrossAxisAlignment.stretch,
                                    children: lessons.map((taskStr) {
                                      List<String> lines = taskStr.split('\n');
                                      String subject = lines.isNotEmpty
                                          ? lines[0]
                                          : "";
                                      String content = lines.length > 1
                                          ? lines.sublist(1).join('\n')
                                          : "";

                                      // Strip any emojis or unsupported characters
                                      content = content
                                          .replaceAll(
                                            RegExp(
                                              r'[^\u0000-\u007F\u00C0-\u017F\s₺]',
                                              unicode: true,
                                            ),
                                            '',
                                          )
                                          .trim();
                                      final style = _getSubjectStyle(subject);
                                      return pw.Container(
                                        margin: const pw.EdgeInsets.only(
                                          bottom: 5,
                                        ),
                                        padding: const pw.EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 4,
                                        ),
                                        decoration: pw.BoxDecoration(
                                          color: style['bg'] as PdfColor,
                                          border: pw.Border(
                                            left: pw.BorderSide(
                                              color:
                                                  style['accent'] as PdfColor,
                                              width: 3,
                                            ),
                                            top: const pw.BorderSide(
                                              color: PdfColors.grey200,
                                              width: 0.5,
                                            ),
                                            right: const pw.BorderSide(
                                              color: PdfColors.grey200,
                                              width: 0.5,
                                            ),
                                            bottom: const pw.BorderSide(
                                              color: PdfColors.grey200,
                                              width: 0.5,
                                            ),
                                          ),
                                        ),
                                        child: pw.Column(
                                          crossAxisAlignment:
                                              pw.CrossAxisAlignment.start,
                                          children: [
                                            pw.Row(
                                              children: [
                                                if (style['icon'] != null)
                                                  pw.Icon(
                                                    style['icon']
                                                        as pw.IconData,
                                                    color:
                                                        style['accent']
                                                            as PdfColor,
                                                    size: 8,
                                                    font: fontIcons,
                                                  ),
                                                pw.SizedBox(width: 2),
                                                pw.Expanded(
                                                  child: pw.Text(
                                                    shortenSub(subject),
                                                    style: pw.TextStyle(
                                                      fontSize: 9,
                                                      fontWeight:
                                                          pw.FontWeight.bold,
                                                      color:
                                                          style['accent']
                                                              as PdfColor,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (content.isNotEmpty)
                                              pw.Text(
                                                content,
                                                style: const pw.TextStyle(
                                                  fontSize: 8,
                                                  color: PdfColors.black,
                                                ),
                                              ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                );
                              }).toList(),
                        ),
                      ],
                    ),
                    // FOOTER AI
                    pw.SizedBox(height: 5), // Reduced
                    pw.Container(
                      padding: pw.EdgeInsets.all(8), // Increased padding
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey100,
                        borderRadius: pw.BorderRadius.circular(4),
                        border: pw.Border.all(color: PdfColors.grey300),
                      ),
                      child: pw.Row(
                        children: [
                          pw.Container(
                            padding: pw.EdgeInsets.all(3), // Increased padding
                            decoration: pw.BoxDecoration(
                              color: PdfColors.purple100,
                              shape: pw.BoxShape.circle,
                            ),
                            child: pw.Text(
                              "AI",
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 8, // Increased font size
                                color: PdfColors.purple,
                              ),
                            ),
                          ),
                          pw.SizedBox(width: 8), // Increased spacing
                          pw.Expanded(
                            child: pw.Text(
                              aiReportContent
                                  .replaceAll(
                                    RegExp(
                                      r'[^\u0000-\u007F\u00C0-\u017F\s₺]',
                                      unicode: true,
                                    ),
                                    '',
                                  )
                                  .trim(),
                              style: pw.TextStyle(
                                fontSize: 8, // Increased font size
                                fontStyle: pw.FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    // DAILY LOG SECTION
                    pw.Expanded(
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(5),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.grey300),
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              "GÜNLÜK YAPTIKLARIM",
                              style: pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.indigo900,
                              ),
                            ),
                            pw.SizedBox(height: 3),
                            pw.Expanded(
                              child: pw.Row(
                                mainAxisAlignment:
                                    pw.MainAxisAlignment.spaceBetween,
                                crossAxisAlignment:
                                    pw.CrossAxisAlignment.stretch,
                                children:
                                    [
                                      'Pazartesi',
                                      'Salı',
                                      'Çarşamba',
                                      'Perşembe',
                                      'Cuma',
                                      'Cumartesi',
                                      'Pazar',
                                    ].map((day) {
                                      return pw.Expanded(
                                        child: pw.Container(
                                          decoration: pw.BoxDecoration(
                                            border: pw.Border.all(
                                              color: PdfColors.grey200,
                                            ),
                                          ),
                                          padding: const pw.EdgeInsets.all(2),
                                          child: pw.Text(
                                            day,
                                            style: const pw.TextStyle(
                                              fontSize: 7,
                                              color: PdfColors.grey600,
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
                    ),
                  ],
                ),
                // Watermark ON TOP but extremely subtle
                if (logo != null)
                  pw.Center(
                    child: pw.Opacity(
                      opacity: 0.02, // 50% less visible than before
                      child: pw.Image(logo, width: 220), // Smaller width
                    ),
                  ),
              ],
            );
          },
        ),
      );
    }
  }

  // PDF Table Helper
  pw.Widget _buildAnalysisListTable(
    List<Map<String, dynamic>> items,
    bool isPriority1,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: {
        0: const pw.FixedColumnWidth(25), // #
        1: const pw.FixedColumnWidth(80), // Ders
        2: const pw.FlexColumnWidth(1), // Konu
        3: const pw.FixedColumnWidth(40), // Başarı
        4: const pw.FixedColumnWidth(60), // Durum
      },
      children: [
        // Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: ['#', 'Ders', 'Konu', 'Başarı', 'Durum']
              .map(
                (t) => pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    t,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        // Items
        ...items.asMap().entries.map((entry) {
          int index = entry.key;
          var item = entry.value;
          double success = (item['success'] as num?)?.toDouble() ?? 0;

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: index % 2 == 0 ? PdfColors.white : PdfColors.grey50,
            ),
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(4),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  '${index + 1}',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(
                  shortenSub(item['subject'] ?? ''),
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(
                  ((item['topic'] ?? ''))
                      .replaceAll(
                        RegExp(
                          r'[^\u0000-\u007F\u00C0-\u017F\s₺]',
                          unicode: true,
                        ),
                        '',
                      )
                      .trim(),
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.all(4),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  '%${success.toStringAsFixed(0)}',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: success < 50
                        ? PdfColors.red
                        : (success < 70 ? PdfColors.orange : PdfColors.green),
                  ),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.all(4),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  isPriority1 ? "Tekrar Et" : "Pekiştir",
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: isPriority1 ? PdfColors.red : PdfColors.green,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }
  // --- HELPER METHODS FOR PRINTING ---

  Map<String, dynamic> _getOverallStatus(List<dynamic> analysis) {
    if (analysis.isEmpty)
      return {
        'label': 'Yetersiz Veri',
        'action': 'Daha fazla sınav girilmeli.',
        'color': PdfColors.grey,
      };

    double avgSuccess =
        analysis.fold(
          0.0,
          (sum, item) => sum + ((item['success'] as num?)?.toDouble() ?? 0),
        ) /
        analysis.length;

    if (avgSuccess >= 85)
      return {
        'label': 'Mükemmel',
        'action':
            'Bu seviyeyi korumak için bol bol deneme çözmeli ve süre yönetimine odaklanmalısın.',
        'color': PdfColors.green,
      };

    if (avgSuccess >= 70)
      return {
        'label': 'İyi',
        'action': 'Konu eksiklerini tamamlayarak bol soru çözümü yapmalısın.',
        'color': PdfColors.blue,
      };

    if (avgSuccess >= 50)
      return {
        'label': 'Orta',
        'action': 'Temel kavramları tekrar etmeli ve düzenli çalışmalısın.',
        'color': PdfColors.orange,
      };

    return {
      'label': 'Geliştirilmeli',
      'action':
          'Öncelikle temel eksiklerini kapatmalı ve ardından basitten zora doğru soru çözmelisin.',
      'color': PdfColors.red,
    };
  }

  String _normalize(String? text) {
    if (text == null) return "";
    return text
        .trim()
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ş', 's')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll('İ', 'i')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  String? _extractClassLevel(String? text) {
    if (text == null) return null;
    final match = RegExp(r'\d+').firstMatch(text);
    return match?.group(0);
  }
}
