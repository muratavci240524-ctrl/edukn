import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Öğrenciye özel sınav istatistikleri.
/// Tab 1 → Yazılı Sınavlar (class_exams)
/// Tab 2 → Deneme Sınavları (trial_exams)
class StudentExamStatsScreen extends StatefulWidget {
  final String institutionId;
  final String studentId;
  final String classId;
  final String classLevel; // e.g. "9", "10", "11", "12"
  final String studentName;
  final String schoolNumber; // okul numarası — birincil eşleştirme

  const StudentExamStatsScreen({
    Key? key,
    required this.institutionId,
    required this.studentId,
    required this.classId,
    required this.classLevel,
    required this.studentName,
    this.schoolNumber = '',
  }) : super(key: key);

  @override
  State<StudentExamStatsScreen> createState() => _StudentExamStatsScreenState();
}

class _StudentExamStatsScreenState extends State<StudentExamStatsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Yazılı
  bool _loadingYazili = true;
  List<_WrittenExam> _writtenExams = [];

  // Deneme
  bool _loadingDeneme = true;
  List<_TrialResult> _trialResults = [];

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('tr_TR', null);
    _tabController = TabController(length: 2, vsync: this);
    _loadWritten();
    _loadTrial();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─────────────────── LOAD YAZILI ─────────────────────────────────────────────

  Future<void> _loadWritten() async {
    setState(() => _loadingYazili = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('class_exams')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('classId', isEqualTo: widget.classId)
          .get();

      final exams = <_WrittenExam>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final date = (d['date'] as Timestamp?)?.toDate();
        final grades = Map<String, dynamic>.from(d['grades'] ?? {});
        final studentGrade = grades[widget.studentId];
        final score = studentGrade != null
            ? double.tryParse(studentGrade.toString())
            : null;
        exams.add(_WrittenExam(
          examId: doc.id,
          examName: (d['examName'] ?? 'Sınav').toString(),
          lessonName: (d['lessonName'] ?? d['lesson'] ?? '').toString(),
          date: date,
          studentScore: score,
          totalStudents: grades.length,
          classAvg: _calcAvg(grades),
        ));
      }
      exams.sort((a, b) => (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000)));
      if (mounted) setState(() { _writtenExams = exams; _loadingYazili = false; });
    } catch (e) {
      debugPrint('StudentExamStats yazili error: $e');
      if (mounted) setState(() => _loadingYazili = false);
    }
  }

  double _calcAvg(Map<String, dynamic> grades) {
    if (grades.isEmpty) return 0;
    double sum = 0;
    int count = 0;
    for (final v in grades.values) {
      final s = double.tryParse(v.toString());
      if (s != null) { sum += s; count++; }
    }
    return count > 0 ? sum / count : 0;
  }

  // ─────────────────── LOAD DENEME ─────────────────────────────────────────────

  /// Portfolyo ile aynı 3 adımlı eşleştirme:
  /// 1. Okul numarası (schoolNumber)
  /// 2. studentId
  /// 3. Fuzzy ad (contains)
  Map<String, dynamic>? _findStudentInResults(List<dynamic> allResults) {
    // 1. Match by School Number (primary — same as portfolio)
    final sNo = widget.schoolNumber.trim();
    if (sNo.isNotEmpty) {
      final m = allResults.cast<Map?>().firstWhere((r) {
        if (r == null) return false;
        final rNo = (r['studentNumber'] ?? r['number'] ?? r['schoolNumber'] ?? r['no'] ?? '')
            .toString()
            .trim();
        return rNo == sNo;
      }, orElse: () => null);
      if (m != null) return Map<String, dynamic>.from(m);
    }

    // 2. Match by studentId
    final sid = widget.studentId;
    if (sid.isNotEmpty) {
      final m = allResults.cast<Map?>().firstWhere((r) {
        if (r == null) return false;
        return (r['studentId']?.toString() ?? '') == sid ||
            (r['id']?.toString() ?? '') == sid;
      }, orElse: () => null);
      if (m != null) return Map<String, dynamic>.from(m);
    }

    // 3. Fuzzy name match (same as portfolio: contains check)
    final sName = widget.studentName.toLowerCase().trim();
    if (sName.isNotEmpty) {
      final m = allResults.cast<Map?>().firstWhere((r) {
        if (r == null) return false;
        final rName = (r['name'] ?? r['studentName'] ?? '').toString().toLowerCase();
        return rName.isNotEmpty && rName.contains(sName);
      }, orElse: () => null);
      if (m != null) return Map<String, dynamic>.from(m);

      // Reverse: student name contains result name
      final m2 = allResults.cast<Map?>().firstWhere((r) {
        if (r == null) return false;
        final rName = (r['name'] ?? r['studentName'] ?? '').toString().toLowerCase().trim();
        return rName.isNotEmpty && sName.contains(rName);
      }, orElse: () => null);
      if (m2 != null) return Map<String, dynamic>.from(m2);
    }

    return null;
  }

  Future<void> _loadTrial() async {
    setState(() => _loadingDeneme = true);
    try {
      // Tüm kuruma ait aktif denemeleri çek (classLevel sorgu filtresi yok)
      final snap = await FirebaseFirestore.instance
          .collection('trial_exams')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      final results = <_TrialResult>[];
      final studentClassLevel = widget.classLevel.trim();

      for (final doc in snap.docs) {
        final d = doc.data();
        final examClassLevel = (d['classLevel'] ?? '').toString().trim();

        final date = (d['date'] as Timestamp?)?.toDate();
        final resultsJson = d['resultsJson'] as String?;

        // Eğer bu sınav öğrencinin sınıf seviyesine ait değilse VE
        // öğrencinin okul numarasına/ismine göre sonuç yoksa atla.
        // (katılmadığı sınavları sadece kendi sınıf seviyesinden göster)
        bool isExamForThisStudent = studentClassLevel.isEmpty ||
            examClassLevel.isEmpty ||
            examClassLevel == studentClassLevel;

        double? studentScore;
        double? studentNet;
        Map<String, double> subjectNets = {};
        bool participated = false;

        if (resultsJson != null && resultsJson.isNotEmpty) {
          try {
            final decoded = jsonDecode(resultsJson);
            if (decoded is List && decoded.isNotEmpty) {
              final found = _findStudentInResults(decoded);
              if (found != null) {
                participated = true;
                isExamForThisStudent = true; // katıldıysa mutlaka göster
                studentScore = double.tryParse(
                    (found['score'] ?? found['totalScore'] ?? found['puan'] ?? '0').toString());
                // Net hesapla — portfolyo ile aynı
                double totalNet = (found['totalNet'] ?? found['net'] ?? 0).toDouble();
                final subjects = found['subjects'];
                if (totalNet == 0 && subjects is Map) {
                  subjects.forEach((k, v) {
                    if (v is Map) {
                      final n = (v['net'] ?? 0).toDouble();
                      totalNet += n;
                      subjectNets[k.toString()] = n;
                    } else if (v is num) {
                      totalNet += v.toDouble();
                    }
                  });
                } else if (subjects is Map) {
                  subjects.forEach((k, v) {
                    if (v is Map) {
                      subjectNets[k.toString()] = (v['net'] ?? 0).toDouble();
                    }
                  });
                }
                studentNet = totalNet;
              }
            }
          } catch (e) {
            debugPrint('resultsJson parse error [${doc.id}]: $e');
          }
        }

        // Katılmadı ise sadece öğrencinin sınıf seviyesindeki sınavları ekle
        if (!isExamForThisStudent) continue;

        results.add(_TrialResult(
          examId: doc.id,
          examName: (d['name'] ?? 'Deneme').toString(),
          examTypeName: (d['examTypeName'] ?? '').toString(),
          classLevel: examClassLevel,
          date: date,
          participated: participated,
          studentScore: studentScore,
          studentNet: studentNet,
          subjectNets: subjectNets,
        ));
      }

      results.sort((a, b) =>
          (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000)));

      if (mounted) {
        setState(() {
          _trialResults = results;
          _loadingDeneme = false;
        });
      }
    } catch (e) {
      debugPrint('StudentExamStats deneme error: $e');
      if (mounted) setState(() => _loadingDeneme = false);
    }
  }

  // ─────────────────── BUILD ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: const BackButton(color: Color(0xFF4F46E5)),
        title: const Text(
          'Notlarım & Sınavlar',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF4F46E5),
          labelColor: const Color(0xFF4F46E5),
          unselectedLabelColor: Colors.grey.shade500,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: '📝 Yazılı Sınavlar'),
            Tab(text: '🎯 Deneme Sınavları'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF4F46E5)),
            onPressed: () { _loadWritten(); _loadTrial(); },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildWrittenTab(),
          _buildTrialTab(),
        ],
      ),
    );
  }

  // ─────────────────── YAZILI TAB ───────────────────────────────────────────────

  Widget _buildWrittenTab() {
    if (_loadingYazili) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)));
    }

    final isMobile = MediaQuery.of(context).size.width < 768;
    final attended = _writtenExams.where((e) => e.studentScore != null).toList();
    final notAttended = _writtenExams.where((e) => e.studentScore == null).toList();
    final avgScore = attended.isEmpty
        ? 0.0
        : attended.fold<double>(0, (s, e) => s + (e.studentScore ?? 0)) / attended.length;

    // Subject averages
    final subjectMap = <String, List<double>>{};
    for (final e in attended) {
      if (e.lessonName.isNotEmpty) {
        subjectMap.putIfAbsent(e.lessonName, () => []).add(e.studentScore!);
      }
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero card
              _writtenHero(attended.length, notAttended.length, _writtenExams.length, avgScore),
              const SizedBox(height: 16),
              // Stat row
              _buildWrittenStatCards(attended.length, notAttended.length, _writtenExams.length, avgScore, isMobile),
              if (subjectMap.isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildSubjectAverages(subjectMap),
              ],
              const SizedBox(height: 24),
              _buildWrittenList(attended, notAttended, isMobile),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _writtenHero(int attended, int missed, int total, double avg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF818CF8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Yazılı Ortalamam', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 6),
                Text(
                  attended == 0 ? '—' : avg.toStringAsFixed(1),
                  style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w900, height: 1.1),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 20, children: [
                  _heroStat('$total', 'Toplam'),
                  _heroStat('$attended', 'Katıldım'),
                  _heroStat('$missed', 'Katılmadım'),
                ]),
              ],
            ),
          ),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 40),
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String value, String label) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
    ]);
  }

  Widget _buildWrittenStatCards(int attended, int missed, int total, double avg, bool isMobile) {
    final cards = [
      _StatData('Toplam Sınav', total, Icons.list_alt_rounded, const Color(0xFF4F46E5), const Color(0xFFEEF2FF)),
      _StatData('Katıldım', attended, Icons.check_circle_rounded, const Color(0xFF10B981), const Color(0xFFECFDF5)),
      _StatData('Katılmadım', missed, Icons.cancel_rounded, const Color(0xFFEF4444), const Color(0xFFFEF2F2)),
      _StatData('Ortalama', 0, Icons.bar_chart_rounded, const Color(0xFFF59E0B), const Color(0xFFFFFBEB),
          subtitle: attended == 0 ? '—' : avg.toStringAsFixed(1)),
    ];
    return LayoutBuilder(builder: (ctx, constraints) {
      final cross = constraints.maxWidth < 500 ? 2 : 4;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cross,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: constraints.maxWidth < 500 ? 1.25 : 1.5,
        ),
        itemCount: cards.length,
        itemBuilder: (_, i) => _buildStatCard(cards[i]),
      );
    });
  }

  Widget _buildSubjectAverages(Map<String, List<double>> subjectMap) {
    final sorted = subjectMap.entries.toList()
      ..sort((a, b) => b.value.fold<double>(0, (s, v) => s + v) / b.value.length -
              a.value.fold<double>(0, (s, v) => s + v) / a.value.length >
          0 ? 1 : -1);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Derse Göre Ortalamar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B))),
          const SizedBox(height: 16),
          ...sorted.map((entry) {
            final avg = entry.value.fold<double>(0, (s, v) => s + v) / entry.value.length;
            final ratio = avg / 100;
            final color = avg >= 70
                ? const Color(0xFF10B981)
                : avg >= 50
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFFEF4444);
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis)),
                      Text('${avg.toStringAsFixed(1)}  •  ${entry.value.length} sınav', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: ratio.clamp(0, 1), backgroundColor: color.withValues(alpha: 0.15), valueColor: AlwaysStoppedAnimation<Color>(color), minHeight: 8),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildWrittenList(List<_WrittenExam> attended, List<_WrittenExam> missed, bool isMobile) {
    final all = [..._writtenExams];
    all.sort((a, b) => (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000)));
    if (all.isEmpty) return _emptyCard('Yazılı sınav kaydı bulunamadı.');
    final fmt = DateFormat('dd MMM yyyy', 'tr_TR');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('Sınav Listesi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B))),
          const SizedBox(width: 8),
          _countBadge(all.length, const Color(0xFF4F46E5)),
        ]),
        const SizedBox(height: 12),
        ...all.map((e) {
          final hasScore = e.studentScore != null;
          final color = hasScore
              ? (e.studentScore! >= 70 ? const Color(0xFF10B981) : e.studentScore! >= 50 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444))
              : Colors.grey.shade400;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
              border: Border(left: BorderSide(color: color, width: 4)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: Text(
                    hasScore ? e.studentScore!.toStringAsFixed(0) : '—',
                    style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: hasScore ? 18 : 24),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.examName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1E293B))),
                      const SizedBox(height: 4),
                      Wrap(spacing: 12, children: [
                        if (e.lessonName.isNotEmpty)
                          _infoChip(Icons.book_outlined, e.lessonName, Colors.indigo.shade400),
                        if (e.date != null)
                          _infoChip(Icons.calendar_today_outlined, fmt.format(e.date!), Colors.grey.shade500),
                        if (e.classAvg > 0)
                          _infoChip(Icons.people_outline, 'Sınıf: ${e.classAvg.toStringAsFixed(1)}', Colors.teal.shade400),
                      ]),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    hasScore ? 'Katıldı' : 'Katılmadı',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ]),
            ),
          );
        }).toList(),
      ],
    );
  }

  // ─────────────────── DENEME TAB ───────────────────────────────────────────────

  Widget _buildTrialTab() {
    if (_loadingDeneme) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)));
    }

    final isMobile = MediaQuery.of(context).size.width < 768;
    final total = _trialResults.length;
    final participated = _trialResults.where((r) => r.participated).toList();
    final missed = _trialResults.where((r) => !r.participated).toList();
    final avgScore = participated.isEmpty
        ? 0.0
        : participated.where((r) => r.studentScore != null).fold<double>(0, (s, r) => s + (r.studentScore ?? 0)) /
            (participated.where((r) => r.studentScore != null).length.toDouble().clamp(1, double.infinity));
    final avgNet = participated.isEmpty
        ? 0.0
        : participated.where((r) => r.studentNet != null).fold<double>(0, (s, r) => s + (r.studentNet ?? 0)) /
            (participated.where((r) => r.studentNet != null).length.toDouble().clamp(1, double.infinity));

    // Subject nets overall average
    final subjectNetMap = <String, List<double>>{};
    for (final r in participated) {
      r.subjectNets.forEach((k, v) {
        subjectNetMap.putIfAbsent(k, () => []).add(v);
      });
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _trialHero(participated.length, missed.length, total, avgScore, avgNet),
              const SizedBox(height: 16),
              _buildTrialStatCards(participated.length, missed.length, total, avgScore, avgNet, isMobile),
              if (subjectNetMap.isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildSubjectNets(subjectNetMap),
              ],
              const SizedBox(height: 24),
              _buildTrialList(_trialResults, isMobile),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trialHero(int participated, int missed, int total, double avgScore, double avgNet) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E40AF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.indigo.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Genel Deneme Ortalaması', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 6),
                Text(
                  participated == 0 ? '—' : avgScore.toStringAsFixed(1),
                  style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w900, height: 1.1),
                ),
                const SizedBox(height: 4),
                Text('Net: ${avgNet.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white60, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(spacing: 20, children: [
                  _heroStat('$total', 'Toplam'),
                  _heroStat('$participated', 'Katıldım'),
                  _heroStat('$missed', 'Katılmadım'),
                ]),
              ],
            ),
          ),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.quiz_rounded, color: Colors.white, size: 40),
          ),
        ],
      ),
    );
  }

  Widget _buildTrialStatCards(int part, int missed, int total, double avgScore, double avgNet, bool isMobile) {
    final cards = [
      _StatData('Toplam Deneme', total, Icons.quiz_rounded, const Color(0xFF1E40AF), const Color(0xFFEFF6FF)),
      _StatData('Katıldım', part, Icons.check_circle_rounded, const Color(0xFF10B981), const Color(0xFFECFDF5)),
      _StatData('Katılmadım', missed, Icons.cancel_rounded, const Color(0xFFEF4444), const Color(0xFFFEF2F2)),
      _StatData('Puan Ort.', 0, Icons.bar_chart_rounded, const Color(0xFFF59E0B), const Color(0xFFFFFBEB),
          subtitle: part == 0 ? '—' : avgScore.toStringAsFixed(1)),
      _StatData('Net Ort.', 0, Icons.trending_up_rounded, const Color(0xFF8B5CF6), const Color(0xFFF5F3FF),
          subtitle: part == 0 ? '—' : avgNet.toStringAsFixed(2)),
    ];
    return LayoutBuilder(builder: (ctx, constraints) {
      final cross = constraints.maxWidth < 400 ? 2 : constraints.maxWidth < 700 ? 3 : 5;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cross,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: constraints.maxWidth < 400 ? 1.2 : 1.4,
        ),
        itemCount: cards.length,
        itemBuilder: (_, i) => _buildStatCard(cards[i]),
      );
    });
  }

  Widget _buildSubjectNets(Map<String, List<double>> subjectNets) {
    final sorted = subjectNets.entries.toList()
      ..sort((a, b) {
        final avgA = a.value.fold<double>(0, (s, v) => s + v) / a.value.length;
        final avgB = b.value.fold<double>(0, (s, v) => s + v) / b.value.length;
        return avgB.compareTo(avgA);
      });

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Derse Göre Net Ortalamaları', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B))),
          const SizedBox(height: 16),
          ...sorted.map((entry) {
            final avg = entry.value.fold<double>(0, (s, v) => s + v) / entry.value.length;
            // Find max net in this subject across all exams
            final maxNet = entry.value.reduce((a, b) => a > b ? a : b);
            final ratio = maxNet > 0 ? (avg / maxNet).clamp(0.0, 1.0) : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Flexible(child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis)),
                    Text('${avg.toStringAsFixed(2)} net  •  ${entry.value.length} deneme', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: ratio, backgroundColor: const Color(0xFFEFF6FF), valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1E40AF)), minHeight: 8),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildTrialList(List<_TrialResult> results, bool isMobile) {
    if (results.isEmpty) return _emptyCard('Deneme sınavı kaydı bulunamadı.');
    final fmt = DateFormat('dd MMM yyyy', 'tr_TR');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('Deneme Listesi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B))),
          const SizedBox(width: 8),
          _countBadge(results.length, const Color(0xFF1E40AF)),
        ]),
        const SizedBox(height: 12),
        ...results.map((r) {
          final borderColor = r.participated ? const Color(0xFF1E40AF) : Colors.grey.shade300;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
              border: Border(left: BorderSide(color: borderColor, width: 4)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: r.participated ? const Color(0xFFEFF6FF) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: r.participated && r.studentScore != null
                      ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(r.studentScore!.toStringAsFixed(0), style: const TextStyle(color: Color(0xFF1E40AF), fontWeight: FontWeight.w900, fontSize: 16, height: 1.1)),
                          Text('puan', style: TextStyle(color: Colors.grey.shade500, fontSize: 9)),
                        ])
                      : Icon(r.participated ? Icons.quiz_rounded : Icons.close_rounded,
                          color: r.participated ? const Color(0xFF1E40AF) : Colors.grey.shade400, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.examName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1E293B))),
                      const SizedBox(height: 4),
                      Wrap(spacing: 12, children: [
                        if (r.examTypeName.isNotEmpty)
                          _infoChip(Icons.label_outline_rounded, r.examTypeName, Colors.purple.shade400),
                        if (r.date != null)
                          _infoChip(Icons.calendar_today_outlined, fmt.format(r.date!), Colors.grey.shade500),
                        if (r.participated && r.studentNet != null)
                          _infoChip(Icons.trending_up_rounded, 'Net: ${r.studentNet!.toStringAsFixed(2)}', const Color(0xFF10B981)),
                      ]),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: r.participated
                        ? const Color(0xFFEFF6FF)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    r.participated ? 'Katıldı' : 'Katılmadı',
                    style: TextStyle(
                      color: r.participated ? const Color(0xFF1E40AF) : Colors.grey.shade500,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ]),
            ),
          );
        }).toList(),
      ],
    );
  }

  // ─────────────────── SHARED WIDGETS ──────────────────────────────────────────

  Widget _buildStatCard(_StatData c) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 6))],
        border: Border.all(color: c.color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: c.bgColor, borderRadius: BorderRadius.circular(10)),
            child: Icon(c.icon, color: c.color, size: 18),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              c.subtitle ?? '${c.count}',
              style: TextStyle(fontSize: c.subtitle != null ? 18 : 22, fontWeight: FontWeight.w900, color: c.color, height: 1.1),
            ),
            const SizedBox(height: 2),
            Text(c.label, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
          ]),
        ],
      ),
    );
  }

  Widget _emptyCard(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: Column(children: [
        Icon(Icons.quiz_outlined, size: 56, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text(msg, style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
      ]),
    );
  }

  Widget _countBadge(int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
      child: Text('$count', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    ]);
  }
}

// ─────────────────── MODELS ──────────────────────────────────────────────────

class _WrittenExam {
  final String examId;
  final String examName;
  final String lessonName;
  final DateTime? date;
  final double? studentScore;
  final int totalStudents;
  final double classAvg;

  const _WrittenExam({
    required this.examId,
    required this.examName,
    required this.lessonName,
    this.date,
    this.studentScore,
    required this.totalStudents,
    required this.classAvg,
  });
}

class _TrialResult {
  final String examId;
  final String examName;
  final String examTypeName;
  final String classLevel;
  final DateTime? date;
  final bool participated;
  final double? studentScore;
  final double? studentNet;
  final Map<String, double> subjectNets;

  const _TrialResult({
    required this.examId,
    required this.examName,
    required this.examTypeName,
    required this.classLevel,
    this.date,
    required this.participated,
    this.studentScore,
    this.studentNet,
    required this.subjectNets,
  });
}

class _StatData {
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String? subtitle;

  const _StatData(this.label, this.count, this.icon, this.color, this.bgColor,
      {this.subtitle});
}
