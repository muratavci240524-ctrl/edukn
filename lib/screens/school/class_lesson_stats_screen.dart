import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'parent_weekly_updates_overview_screen.dart';

class ClassLessonStatsScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String? periodId;

  final String classId;
  final String lessonId;

  final String className;
  final String lessonName;

  const ClassLessonStatsScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    this.periodId,
    required this.classId,
    required this.lessonId,
    required this.className,
    required this.lessonName,
  });

  @override
  State<ClassLessonStatsScreen> createState() => _ClassLessonStatsScreenState();
}

class _ClassLessonStatsScreenState extends State<ClassLessonStatsScreen> {
  bool _loading = true;
  List<_PlannedTopicItem> _topics = [];

  // Homework Data
  List<Map<String, dynamic>> _homeworks = [];
  List<Map<String, dynamic>> _students = [];

  // Computed Stats
  List<Map<String, dynamic>> _riskyStudents =
      []; // {name, missingCount, consecutiveMissing}
  int _totalHomeworks = 0;
  int _checkedHomeworks = 0; // At least one student graded
  double _avgParticipation = 0.0;

  // Trial Exam Stats
  List<_BarChartItem> _trialStats = [];
  String? _trialError;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      // --- 0. Fetch Class & Lesson Info ---
      String classLevel = '';
      String branchName = '';

      try {
        final classDoc = await FirebaseFirestore.instance
            .collection('classes')
            .doc(widget.classId)
            .get();
        if (classDoc.exists) {
          classLevel = (classDoc.data()?['classLevel'] ?? '').toString();
        }

        final lessonDoc = await FirebaseFirestore.instance
            .collection('lessons')
            .doc(widget.lessonId)
            .get();
        if (lessonDoc.exists) {
          branchName = (lessonDoc.data()?['branchName'] ?? '').toString();
        }
      } catch (e) {
        debugPrint('Error fetching class/lesson info: $e');
      }

      // --- 1. Fetch Trial Exams (ISOLATED) ---
      List<_BarChartItem> trialStats = [];
      _trialError = null;

      try {
        if (classLevel.isNotEmpty) {
          debugPrint('DEBUG: Fetching trials, Level: $classLevel');
          final trialsSnap = await FirebaseFirestore.instance
              .collection('trial_exams')
              .where('institutionId', isEqualTo: widget.institutionId)
              .where('isActive', isEqualTo: true)
              .orderBy('date', descending: true)
              .limit(30)
              .get();

          debugPrint('DEBUG: Raw Fetched: ${trialsSnap.docs.length}');
          for (var d in trialsSnap.docs) {
            debugPrint(
              'DEBUG: Trial Found: ${d.data()['name']} - Level: ${d.data()['classLevel']}',
            );
          }

          final trials = trialsSnap.docs
              .where((d) {
                final lvl = (d.data()['classLevel'] ?? '').toString().trim();
                final target = classLevel.trim();
                // Gevşek eşleştirme: "8" == "8. Sınıf"
                return lvl == target ||
                    lvl.startsWith('$target.') ||
                    lvl.startsWith('$target ') ||
                    target.startsWith('$lvl.') ||
                    target.startsWith('$lvl ');
              })
              .take(5)
              .toList()
              .reversed
              .toList();

          debugPrint('DEBUG: Filtered Trials: ${trials.length}');

          if (trials.isEmpty) {
            // _trialError = 'Bu sınıf seviyesinde ($classLevel) aktif deneme sınavı bulunamadı.';
            // Don't show error for empty, show empty state instead (handled by checks)
          }

          for (var tDoc in trials) {
            final tData = tDoc.data();
            final resultsJson = tData['resultsJson'] as String?;
            if (resultsJson != null && resultsJson.isNotEmpty) {
              try {
                final List<dynamic> results = jsonDecode(resultsJson);
                if (results.isEmpty) continue;

                final classResults = results.where((r) {
                  final rBranch = (r['branch'] ?? r['className'] ?? '')
                      .toString();
                  return rBranch == widget.className;
                }).toList();

                if (classResults.isEmpty) continue;

                double totalNet = 0;
                int studentCount = 0;

                for (var res in classResults) {
                  final subjects = res['subjects'] as Map<String, dynamic>?;
                  if (subjects != null) {
                    // 1. Try Lesson Name
                    var subjData = subjects[widget.lessonName];

                    if (subjData == null) {
                      final key = subjects.keys.firstWhere(
                        (k) =>
                            k.toString().toLowerCase() ==
                            widget.lessonName.toLowerCase(),
                        orElse: () => '',
                      );
                      if (key.isNotEmpty) subjData = subjects[key];
                    }

                    // 2. Try Branch Name (Fallback)
                    if (subjData == null && branchName.isNotEmpty) {
                      subjData = subjects[branchName];
                      if (subjData == null) {
                        final key = subjects.keys.firstWhere(
                          (k) =>
                              k.toString().toLowerCase() ==
                              branchName.toLowerCase(),
                          orElse: () => '',
                        );
                        if (key.isNotEmpty) subjData = subjects[key];
                      }
                    }

                    if (subjData != null && subjData is Map) {
                      final net =
                          num.tryParse(
                            subjData['net']?.toString() ?? '0',
                          )?.toDouble() ??
                          0.0;
                      totalNet += net;
                      studentCount++;
                    }
                  }
                }

                if (studentCount > 0) {
                  final avg = totalNet / studentCount;

                  String label = '';
                  final dateRaw = tData['date'];
                  if (dateRaw is Timestamp) {
                    label = DateFormat('dd.MM.yy').format(dateRaw.toDate());
                  } else {
                    label = tData['name'] ?? '-';
                    if (label.length > 8) label = label.substring(0, 8);
                  }

                  // Determine Max Score (Question Count)
                  int maxScore = 0;
                  try {
                    final answerKeys =
                        tData['answerKeys'] as Map<String, dynamic>?;
                    if (answerKeys != null && answerKeys.isNotEmpty) {
                      // Try Booklet 'A' first, or any
                      final firstBooklet =
                          answerKeys.values.first as Map<String, dynamic>?;
                      if (firstBooklet != null) {
                        // 1. Try Lesson Name
                        String? keyStr = firstBooklet[widget.lessonName]
                            ?.toString();

                        // 2. Try Branch Name fallback
                        if (keyStr == null && branchName.isNotEmpty) {
                          keyStr = firstBooklet[branchName]?.toString();
                        }

                        // 3. Try fuzzy match
                        if (keyStr == null) {
                          final k = firstBooklet.keys.firstWhere(
                            (k) =>
                                k.toString().toLowerCase() ==
                                widget.lessonName.toLowerCase(),
                            orElse: () => '',
                          );
                          if (k.isNotEmpty)
                            keyStr = firstBooklet[k]?.toString();
                        }

                        if (keyStr != null) {
                          maxScore = keyStr.length;
                        }
                      }
                    }
                  } catch (e) {
                    debugPrint('Error finding max score: $e');
                  }

                  // Fallback if not found (Requested "20 soru varsa")
                  if (maxScore == 0) maxScore = 20;

                  trialStats.add(
                    _BarChartItem(label: label, value: avg, maxScore: maxScore),
                  );
                }
              } catch (e) {
                debugPrint('Error parsing trial results: $e');
              }
            }
          }
        } else {
          // classLevel empty
          // _trialError = 'Sınıf seviyesi bilgisi eksik.';
        }
      } catch (e) {
        debugPrint('Error loading trial exams (Index might be missing): $e');
        if (e.toString().contains('failed-precondition')) {
          _trialError = 'Index oluşturuluyor. Lütfen 5-10 dk bekleyiniz.';
        } else {
          _trialError = 'Veri alınamadı: $e';
        }
      }
      _trialStats = trialStats;

      // --- 2. Fetch Basic Data (Homeworks & Students) ---
      try {
        final hwSnap = await FirebaseFirestore.instance
            .collection('homeworks')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('classId', isEqualTo: widget.classId)
            .where('lessonId', isEqualTo: widget.lessonId)
            .orderBy('assignedDate', descending: true)
            .get();

        _homeworks = hwSnap.docs.map((d) {
          final data = d.data();
          data['id'] = d.id;
          return data;
        }).toList();

        _homeworks.sort((a, b) {
          final d1 =
              (a['assignedDate'] as Timestamp?)?.toDate() ?? DateTime(2000);
          final d2 =
              (b['assignedDate'] as Timestamp?)?.toDate() ?? DateTime(2000);
          return d2.compareTo(d1);
        });

        final stSnap = await FirebaseFirestore.instance
            .collection('students')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('classId', isEqualTo: widget.classId)
            .get();

        _students = stSnap.docs.map((d) {
          final data = d.data();
          data['id'] = d.id;
          return data;
        }).toList();

        // Stats
        _totalHomeworks = _homeworks.length;
        _checkedHomeworks = _homeworks.where((h) {
          final statuses = h['studentStatuses'] as Map<String, dynamic>? ?? {};
          return statuses.values.any((v) => (v is int ? v : 0) > 0);
        }).length;

        if (_homeworks.isNotEmpty && _students.isNotEmpty) {
          double totalPart = 0;
          int gradedHwCount = 0;
          for (var h in _homeworks) {
            final statuses =
                h['studentStatuses'] as Map<String, dynamic>? ?? {};
            if (statuses.values.any((v) => (v is int ? v : 0) > 0)) {
              final doneCount = statuses.values.where((v) => v == 1).length;
              totalPart += (doneCount / _students.length);
              gradedHwCount++;
            }
          }
          _avgParticipation = gradedHwCount == 0
              ? 0
              : (totalPart / gradedHwCount);
        }

        // Risky Students
        _riskyStudents = [];
        for (var s in _students) {
          final sid = s['id'];
          final name = s['fullName'] ?? s['name'] ?? '??';

          int missingTotal = 0;
          int maxConsecutive = 0;
          int currentConsecutive = 0;

          for (var h in _homeworks.reversed) {
            final statuses =
                h['studentStatuses'] as Map<String, dynamic>? ?? {};
            final status = statuses[sid] as int? ?? 0;

            if (status == 2 || status == 3 || status == 4) {
              missingTotal++;
              currentConsecutive++;
            } else if (status == 1) {
              if (currentConsecutive > maxConsecutive) {
                maxConsecutive = currentConsecutive;
              }
              currentConsecutive = 0;
            }
          }
          if (currentConsecutive > maxConsecutive) {
            maxConsecutive = currentConsecutive;
          }

          if (missingTotal >= 3 || maxConsecutive >= 3) {
            _riskyStudents.add({
              'name': name,
              'missing': missingTotal,
              'consecutive': maxConsecutive,
              'isSevere': maxConsecutive >= 3,
            });
          }
        }
        _riskyStudents.sort(
          (a, b) => (b['missing'] as int).compareTo(a['missing'] as int),
        );
      } catch (e) {
        debugPrint('Error loading homeworks: $e');
      }

      // --- 3. Fetch Topics ---
      try {
        final classPlansQuery = await FirebaseFirestore.instance
            .collection('classLessonPlans')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('classId', isEqualTo: widget.classId)
            .where('lessonId', isEqualTo: widget.lessonId)
            .get();

        final Map<String, DateTime> completionMap = {};
        for (final doc in classPlansQuery.docs) {
          final data = doc.data();
          final weeklyPlanId = data['weeklyPlanId'];
          final date = (data['date'] as Timestamp?)?.toDate();

          if (weeklyPlanId != null && date != null) {
            if (!completionMap.containsKey(weeklyPlanId) ||
                date.isBefore(completionMap[weeklyPlanId]!)) {
              completionMap[weeklyPlanId] = date;
            }
          }
        }

        final plansQuery = await FirebaseFirestore.instance
            .collection('yearlyPlans')
            .where('isActive', isEqualTo: true)
            .where('lessonId', isEqualTo: widget.lessonId)
            .get();

        final List<_PlannedTopicItem> items = [];

        for (final planDoc in plansQuery.docs) {
          final data = planDoc.data();
          final planInstitutionId = (data['institutionId'] ?? '').toString();
          if (planInstitutionId.isNotEmpty &&
              planInstitutionId != widget.institutionId) {
            continue;
          }

          final planSchoolTypeId = (data['schoolTypeId'] ?? '').toString();
          if (planSchoolTypeId.isNotEmpty &&
              planSchoolTypeId != widget.schoolTypeId) {
            continue;
          }

          final classIds =
              (data['classIds'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
          if (classIds.isNotEmpty && !classIds.contains(widget.classId)) {
            continue;
          }

          final weeklyPlansSnap = await FirebaseFirestore.instance
              .collection('yearlyPlans')
              .doc(planDoc.id)
              .collection('weeklyPlans')
              .get();

          for (final weekDoc in weeklyPlansSnap.docs) {
            final w = weekDoc.data();
            final topic = (w['topic'] ?? '').toString().trim();
            if (topic.isEmpty) continue;

            final weekNumber = w['weekNumber'];
            final weekStart = (w['weekStart'] as Timestamp?)?.toDate();
            final weekEnd = (w['weekEnd'] as Timestamp?)?.toDate();
            final coveredClassIds =
                (w['coveredClassIds'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [];
            final isCovered = coveredClassIds.contains(widget.classId);
            final completedDate = completionMap[weekDoc.id];

            items.add(
              _PlannedTopicItem(
                planId: planDoc.id,
                weekId: weekDoc.id,
                weekNumber: weekNumber is int
                    ? weekNumber
                    : int.tryParse(weekNumber?.toString() ?? ''),
                weekStart: weekStart,
                weekEnd: weekEnd,
                topic: topic,
                isCovered: isCovered,
                completedDate: completedDate,
              ),
            );
          }
        }

        items.sort((a, b) {
          final aDate = a.weekStart ?? DateTime(2100);
          final bDate = b.weekStart ?? DateTime(2100);
          return aDate.compareTo(bDate);
        });

        _topics = items;
      } catch (e) {
        debugPrint('Error loading topics: $e');
      }
    } catch (e, s) {
      debugPrint('Error global load: $e $s');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final totalTopics = _topics.length;
    final coveredTopics = _topics.where((e) => e.isCovered).length;

    // Restore detailed counts for the UI chips
    final overdueTopics = _topics
        .where(
          (e) =>
              !e.isCovered &&
              e.weekEnd != null &&
              _isBeforeDay(e.weekEnd!, today),
        )
        .length;
    final upcomingTopics = totalTopics - coveredTopics - overdueTopics;

    final progress = totalTopics == 0 ? 0.0 : (coveredTopics / totalTopics);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'İstatistik',
              style: TextStyle(
                color: Colors.grey.shade900,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '${widget.className} • ${widget.lessonName}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. (NEW) Trial Exam Stats
                _SectionCard(
                  title: 'Deneme Ortalamaları',
                  subtitle: 'Sınıfın bu dersteki net ortalamaları',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_trialError != null)
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _trialError!,
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 12,
                            ),
                          ),
                        )
                      else if (_trialStats.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: _EmptyInline(
                              text: 'Henüz deneme verisi yok',
                            ),
                          ),
                        )
                      else ...[
                        _SimpleBarChart(items: _trialStats),
                        const SizedBox(height: 8),
                        Text(
                          'Son ${_trialStats.length} deneme sınavı dikkate alınmıştır.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 2. Konu İlerleme
                _SectionCard(
                  title: 'Konu İlerleme',
                  subtitle: 'Yıllık plan takibi',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _ChipStat(
                            label: 'Toplam',
                            value: '$totalTopics',
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 8),
                          _ChipStat(
                            label: 'İşlenen',
                            value: '$coveredTopics',
                            color: Colors.green,
                          ),
                          const SizedBox(width: 8),
                          _ChipStat(
                            label: 'Geciken',
                            value: '$overdueTopics',
                            color: Colors.red,
                          ),
                          const SizedBox(width: 8),
                          _ChipStat(
                            label: 'Sıradaki',
                            value: '$upcomingTopics',
                            color: Colors.indigo,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: LinearProgressIndicator(
                          minHeight: 12,
                          value: progress,
                          backgroundColor: Colors.grey.shade200,
                          color: Colors.teal.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Toplam konu %100 • İşlenen konu %${(progress * 100).toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // 3. Plan Konuları (Accordion)
                Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: ExpansionTile(
                      backgroundColor: Colors.white,
                      collapsedBackgroundColor: Colors.white,
                      tilePadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      title: const Text(
                        'Plan Konuları',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        'Detaylı konu listesini görüntülemek için dokunun',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      children: [
                        if (totalTopics == 0)
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: _EmptyInline(
                              text: 'Bu ders için plan konusu bulunamadı',
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: _topics.map((t) {
                                final status = _topicStatus(t, today);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _TopicTile(item: t, status: status),
                                );
                              }).toList(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // 4. Ödev İstatistikleri
                _SectionCard(
                  title: 'Ödev Durumu',
                  subtitle: 'Genel ödev performansı',
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _ChipStat(
                            label: 'Verilen',
                            value: '$_totalHomeworks',
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 8),
                          _ChipStat(
                            label: 'Kontrol Edilen',
                            value: '$_checkedHomeworks',
                            color: Colors.purple,
                          ),
                          const SizedBox(width: 8),
                          _ChipStat(
                            label: 'Katılım %',
                            value:
                                '%${(_avgParticipation * 100).toStringAsFixed(0)}',
                            color: Colors.green,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                if (_riskyStudents.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  // 5. Risk Analizi
                  _SectionCard(
                    title: 'Risk Analizi',
                    subtitle: 'Ödevlerini aksatan öğrenciler',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade100),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orange.shade700,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '${_riskyStudents.length} öğrenci son ödevlerde eksik veya devamsızlık gösteriyor.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._riskyStudents.map((s) {
                          final isSevere = s['isSevere'] as bool;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: isSevere
                                      ? Colors.red.shade100
                                      : Colors.orange.shade100,
                                  radius: 16,
                                  child: Text(
                                    '${s['missing']}',
                                    style: TextStyle(
                                      color: isSevere
                                          ? Colors.red.shade800
                                          : Colors.orange.shade800,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s['name'],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        isSevere
                                            ? '${s['consecutive']} ödevdir üst üste yapmıyor!'
                                            : 'Toplamda ${s['missing']} ödev eksiği var.',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isSevere
                                              ? Colors.red
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // 6. Veli Bilgilendirme Mektupları
                _SectionCard(
                  title: 'Veli Bilgilendirme Mektupları',
                  subtitle: 'Haftalık mektuplar (sınıfın tüm dersleri)',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ParentWeeklyUpdatesOverviewScreen(
                            institutionId: widget.institutionId,
                            schoolTypeId: widget.schoolTypeId,
                            periodId: widget.periodId,
                            classId: widget.classId,
                            className: widget.className,
                            initialDate: DateTime.now(),
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.blue.shade100),
                            ),
                            child: Icon(
                              Icons.mail_outline,
                              color: Colors.blue.shade700,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Haftalık listeyi aç',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: Colors.grey.shade900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Seçili haftada hangi derslerde mektup var görüntüle',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: Colors.blue.shade700,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 30),
              ],
            ),
    );
  }

  _TopicStatus _topicStatus(_PlannedTopicItem item, DateTime today) {
    if (item.isCovered) {
      if (item.completedDate != null && item.weekEnd != null) {
        final c = DateTime(
          item.completedDate!.year,
          item.completedDate!.month,
          item.completedDate!.day,
        );
        final e = DateTime(
          item.weekEnd!.year,
          item.weekEnd!.month,
          item.weekEnd!.day,
        );
        if (c.isAfter(e)) {
          return _TopicStatus.coveredLate;
        }
        return _TopicStatus.covered;
      }
      return _TopicStatus.covered;
    }
    if (item.weekEnd != null && _isBeforeDay(item.weekEnd!, today))
      return _TopicStatus.overdue;
    return _TopicStatus.upcoming;
  }

  bool _isBeforeDay(DateTime a, DateTime b) {
    final da = DateTime(a.year, a.month, a.day);
    final db = DateTime(b.year, b.month, b.day);
    return da.isBefore(db);
  }
}

enum _TopicStatus { covered, coveredLate, overdue, upcoming }

class _PlannedTopicItem {
  final String planId;
  final String weekId;
  final int? weekNumber;
  final DateTime? weekStart;
  final DateTime? weekEnd;
  final String topic;
  final bool isCovered;
  final DateTime? completedDate;

  const _PlannedTopicItem({
    required this.planId,
    required this.weekId,
    required this.weekNumber,
    required this.weekStart,
    required this.weekEnd,
    required this.topic,
    required this.isCovered,
    this.completedDate,
  });
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ChipStat extends StatelessWidget {
  final String label;
  final String value;
  final MaterialColor color;
  const _ChipStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color.shade800,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade900,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicTile extends StatelessWidget {
  final _PlannedTopicItem item;
  final _TopicStatus status;

  const _TopicTile({required this.item, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      _TopicStatus.covered => Colors.green,
      _TopicStatus.coveredLate => Colors.orange,
      _TopicStatus.overdue => Colors.red,
      _TopicStatus.upcoming => Colors.indigo,
    };

    final statusText = switch (status) {
      _TopicStatus.covered => 'İşlendi',
      _TopicStatus.coveredLate => 'İşlendi',
      _TopicStatus.overdue => 'Gecikti',
      _TopicStatus.upcoming => 'Sıradaki',
    };

    String dateText = '';
    if (item.weekStart != null && item.weekEnd != null) {
      dateText =
          '${item.weekStart!.day.toString().padLeft(2, '0')}.${item.weekStart!.month.toString().padLeft(2, '0')} - '
          '${item.weekEnd!.day.toString().padLeft(2, '0')}.${item.weekEnd!.month.toString().padLeft(2, '0')}';
    }

    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.topic,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade900,
                        ),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                if (dateText.isNotEmpty || item.weekNumber != null) ...[
                  SizedBox(height: 6),
                  Text(
                    '${item.weekNumber != null ? '${item.weekNumber}. Hafta • ' : ''}$dateText',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BarChartItem {
  final String label;
  final double value;
  final int maxScore;
  const _BarChartItem({
    required this.label,
    required this.value,
    required this.maxScore,
  });
}

class _SimpleBarChart extends StatelessWidget {
  final List<_BarChartItem> items;
  const _SimpleBarChart({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: items.map((e) {
          final h = e.maxScore > 0
              ? (e.value / e.maxScore).clamp(0.0, 1.0)
              : 0.0;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${e.value.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      height: 110,
                      color: Colors.grey.shade200,
                      alignment: Alignment.bottomCenter,
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        height: 110 * h,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.blue.shade400,
                              Colors.blue.shade700,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    e.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _EmptyInline extends StatelessWidget {
  final String text;
  const _EmptyInline({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
      ),
    );
  }
}
