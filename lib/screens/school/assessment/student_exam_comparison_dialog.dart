import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../models/assessment/trial_exam_model.dart';
import 'evaluation_models.dart';
import 'student_report_card_dialog.dart';

/// Öğrencinin aynı sınav türündeki tüm sınavlarını ve gelişimini karşılaştıran modal dialog
class StudentExamComparisonDialog extends StatefulWidget {
  final Map<String, dynamic> studentData;
  final TrialExam? currentExam;
  final String currentExamName;
  final List<TrialExam> allExams;
  final String? institutionId;
  final List<String> availableSubjects;

  const StudentExamComparisonDialog({
    Key? key,
    required this.studentData,
    this.currentExam,
    required this.currentExamName,
    required this.allExams,
    this.institutionId,
    required this.availableSubjects,
  }) : super(key: key);

  @override
  _StudentExamComparisonDialogState createState() =>
      _StudentExamComparisonDialogState();
}

class _StudentExamComparisonDialogState
    extends State<StudentExamComparisonDialog> {
  bool _isLoading = false;
  bool _onlySameExamType = true;
  List<TrialExam> _examsPool = [];
  List<_ComparedStudentExam> _comparedExams = [];

  final ScrollController _horizontalScrollController = ScrollController();
  final Map<String, String> _customLessonShortNames = {};

  static const Map<String, String> _defaultShortNames = {
    'türkçe': 'TÜR',
    'turkce': 'TÜR',
    'matematik': 'MAT',
    'ilköğretim matematik': 'MAT',
    'ilkogretim matematik': 'MAT',
    'fen bilimleri': 'FEN',
    'fen ve teknoloji': 'FEN',
    'sosyal bilgiler': 'SOS',
    't.c. inkılap tarihi ve atatürkçülük': 'İNK',
    't.c. inkılap tarihi': 'İNK',
    'inkılap tarihi': 'İNK',
    'inkılap': 'İNK',
    'din kültürü ve ahlak bilgisi': 'DİN',
    'din kültürü': 'DİN',
    'din': 'DİN',
    'yabancı dil': 'İNG',
    'yabanci dil': 'İNG',
    'ingilizce': 'İNG',
    'almanca': 'ALM',
    'fransızca': 'FRA',
    'fizik': 'FİZ',
    'kimya': 'KİM',
    'biyoloji': 'BİY',
    'tarih': 'TAR',
    'coğrafya': 'COĞ',
    'cografya': 'COĞ',
    'felsefe': 'FEL',
    'felsefe grubu': 'FEL',
    'mantık': 'MAN',
    'psikoloji': 'PSİ',
    'sosyoloji': 'SOSY',
    'geometri': 'GEO',
    'türk dili ve edebiyatı': 'EDB',
    'edebiyat': 'EDB',
    'temel matematik': 'T.MAT',
    'ileri matematik': 'İ.MAT',
    'çağdaş türk ve dünya tarihi': 'Ç.TAR',
    'bilişim teknolojileri ve yazılım': 'BİL',
    'bilişim teknolojileri': 'BİL',
    'teknoloji ve tasarım': 'TEK',
    'müzik': 'MÜZ',
    'görsel sanatlar': 'GÖR',
    'beden eğitimi ve spor': 'BED',
    'beden eğitimi': 'BED',
    'trafik güvenliği': 'TRAF',
    'rehberlik': 'REH',
  };

  String _targetStudentNo = '';
  String _targetStudentName = '';
  String _targetClassName = '';

  @override
  void initState() {
    super.initState();
    _extractTargetStudentInfo();
    _initExams();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  String _getSubjectShortName(String fullName) {
    final key = fullName.trim().toLowerCase();
    if (_customLessonShortNames.containsKey(key) &&
        _customLessonShortNames[key]!.isNotEmpty) {
      return _customLessonShortNames[key]!;
    }
    if (_defaultShortNames.containsKey(key)) {
      return _defaultShortNames[key]!;
    }
    for (var entry in _defaultShortNames.entries) {
      if (key.contains(entry.key) || entry.key.contains(key)) {
        return entry.value;
      }
    }
    final clean = fullName.trim();
    return clean.length <= 4
        ? clean.toUpperCase()
        : clean.substring(0, 4).toUpperCase();
  }

  void _extractTargetStudentInfo() {
    _targetStudentNo = (widget.studentData['studentNo'] ??
            widget.studentData['studentNumber'] ??
            widget.studentData['number'] ??
            widget.studentData['no'] ??
            widget.studentData['schoolNumber'] ??
            '')
        .toString()
        .trim();

    _targetStudentName = (widget.studentData['studentName'] ??
            widget.studentData['name'] ??
            widget.studentData['ogrAdSoyad'] ??
            '')
        .toString()
        .trim();

    _targetClassName = (widget.studentData['className'] ??
            widget.studentData['branch'] ??
            '')
        .toString()
        .trim();
  }

  Future<void> _initExams() async {
    _examsPool = List.from(widget.allExams);

    final instId = widget.institutionId ?? widget.currentExam?.institutionId;

    // 1. Kurumun ders listesinde tanımladığı Kısa Adları (shortName) yükle
    if (instId != null && instId.isNotEmpty) {
      try {
        final lessonsSnap = await FirebaseFirestore.instance
            .collection('lessons')
            .where('institutionId', isEqualTo: instId)
            .where('isActive', isEqualTo: true)
            .get();

        for (var doc in lessonsSnap.docs) {
          final data = doc.data();
          final lName = (data['lessonName'] ?? data['name'] ?? '')
              .toString()
              .toLowerCase()
              .trim();
          final bName = (data['branchName'] ?? '')
              .toString()
              .toLowerCase()
              .trim();
          final sName = (data['shortName'] ?? '').toString().toUpperCase().trim();
          if (sName.isNotEmpty) {
            if (lName.isNotEmpty) _customLessonShortNames[lName] = sName;
            if (bName.isNotEmpty) _customLessonShortNames[bName] = sName;
          }
        }
      } catch (e) {
        debugPrint('Error loading lessons for short names: $e');
      }
    }

    // 2. Eğer allExams boş geldiyse Firestore'dan çekmeyi dene
    if (_examsPool.isEmpty && instId != null) {
      setState(() => _isLoading = true);
      try {
        final snap = await FirebaseFirestore.instance
            .collection('trial_exams')
            .where('institutionId', isEqualTo: instId)
            .where('isActive', isEqualTo: true)
            .get();

        _examsPool = snap.docs
            .map((doc) => TrialExam.fromMap(doc.data(), doc.id))
            .toList();
      } catch (e) {
        debugPrint('Error fetching exams pool: $e');
      }
    }

    _processComparison();
  }

  void _processComparison() {
    setState(() => _isLoading = true);

    try {
      final List<TrialExam> candidateExams = [];

      // Eğer currentExam pool'da yoksa ekle
      if (widget.currentExam != null &&
          !_examsPool.any((e) => e.id == widget.currentExam!.id)) {
        candidateExams.add(widget.currentExam!);
      }

      for (var exam in _examsPool) {
        if (!candidateExams.any((e) => e.id == exam.id)) {
          candidateExams.add(exam);
        }
      }

      final String currentTypeId = widget.currentExam?.examTypeId ?? '';
      final String currentTypeName = widget.currentExam?.examTypeName ?? '';
      final String currentClassLevel = widget.currentExam?.classLevel ?? '';

      // Filtreleme
      final filteredExams = candidateExams.where((exam) {
        if (!_onlySameExamType) {
          // Tüm sınavlar seçiliyse sınıf seviyesi eşleşmesi yeterli
          if (currentClassLevel.isNotEmpty && exam.classLevel.isNotEmpty) {
            return exam.classLevel == currentClassLevel;
          }
          return true;
        }

        // Aynı sınav türü filtreleme
        if (currentTypeId.isNotEmpty && exam.examTypeId.isNotEmpty) {
          final matchesType = exam.examTypeId == currentTypeId;
          final matchesLevel = currentClassLevel.isEmpty ||
              exam.classLevel.isEmpty ||
              exam.classLevel == currentClassLevel;
          return matchesType && matchesLevel;
        }

        if (currentTypeName.isNotEmpty && exam.examTypeName.isNotEmpty) {
          final matchesType =
              exam.examTypeName.toLowerCase() == currentTypeName.toLowerCase();
          final matchesLevel = currentClassLevel.isEmpty ||
              exam.classLevel.isEmpty ||
              exam.classLevel == currentClassLevel;
          return matchesType && matchesLevel;
        }

        // Tür alanı boşsa aynı sınıf seviyesindeki denemeleri al
        if (currentClassLevel.isNotEmpty && exam.classLevel.isNotEmpty) {
          return exam.classLevel == currentClassLevel;
        }

        return true;
      }).toList();

      final List<_ComparedStudentExam> matchedList = [];

      for (var exam in filteredExams) {
        Map<String, dynamic>? studentRecord;

        // Geçerli sınav için widget.studentData kullanılabilir
        if (widget.currentExam != null && exam.id == widget.currentExam!.id) {
          studentRecord = widget.studentData;
        } else if (exam.resultsJson != null &&
            exam.resultsJson!.trim().isNotEmpty) {
          try {
            final decoded = jsonDecode(exam.resultsJson!);
            if (decoded is List) {
              studentRecord = _findStudentInResults(decoded);
            }
          } catch (e) {
            debugPrint('Error decoding results for exam ${exam.name}: $e');
          }
        }

        if (studentRecord != null) {
          final double score = num.tryParse(
                  (studentRecord['totalScore'] ??
                          studentRecord['score'] ??
                          '0')
                      .toString())
                  ?.toDouble() ??
              0.0;

          final double net = num.tryParse(
                  (studentRecord['totalNet'] ?? '0').toString())
                  ?.toDouble() ??
              _calculateNetFromSubjects(studentRecord['subjects']);

          final int rankGen = int.tryParse(
                  (studentRecord['rankGeneral'] ??
                          studentRecord['rank'] ??
                          '0')
                      .toString()) ??
              0;

          final int rankBr = int.tryParse(
                  (studentRecord['rankBranch'] ?? '0').toString()) ??
              0;

          int totalExamStudents = 0;
          if (exam.resultsJson != null && exam.resultsJson!.isNotEmpty) {
            try {
              final d = jsonDecode(exam.resultsJson!);
              if (d is List) totalExamStudents = d.length;
            } catch (silentError) { debugPrint('[student_exam_comparison_dialog] hata yutuldu: $silentError'); }
          }

          final Map<String, SubjectStats> subjectStatsMap = {};
          if (studentRecord['subjects'] != null &&
              studentRecord['subjects'] is Map) {
            (studentRecord['subjects'] as Map).forEach((k, v) {
              if (v is Map) {
                subjectStatsMap[k.toString()] = SubjectStats(
                  correct: int.tryParse(v['correct']?.toString() ?? '0') ?? 0,
                  wrong: int.tryParse(v['wrong']?.toString() ?? '0') ?? 0,
                  empty: int.tryParse(v['empty']?.toString() ?? '0') ?? 0,
                  net: num.tryParse(v['net']?.toString() ?? '0')?.toDouble() ??
                      0.0,
                );
              }
            });
          }

          matchedList.add(_ComparedStudentExam(
            exam: exam,
            isCurrentExam:
                widget.currentExam != null && exam.id == widget.currentExam!.id,
            studentName: studentRecord['studentName']?.toString() ??
                studentRecord['name']?.toString() ??
                _targetStudentName,
            studentNo: (studentRecord['studentNo'] ??
                    studentRecord['studentNumber'] ??
                    _targetStudentNo)
                .toString(),
            className: studentRecord['className']?.toString() ??
                studentRecord['branch']?.toString() ??
                _targetClassName,
            totalScore: score,
            totalNet: net,
            rankGeneral: rankGen,
            totalStudents: totalExamStudents,
            rankBranch: rankBr,
            subjects: subjectStatsMap,
            rawRecord: studentRecord,
          ));
        }
      }

      // Kronolojik sıralama: En eskiden en yeniye (gelişimi doğru görmek için)
      matchedList.sort((a, b) => a.exam.date.compareTo(b.exam.date));

      _comparedExams = matchedList;
    } catch (e) {
      debugPrint('Error in _processComparison: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic>? _findStudentInResults(List<dynamic> allResults) {
    final normTarget = _normalizeString(_targetStudentName);

    for (var item in allResults) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);

      // 1. Okul Numarasına göre eşleştirme
      final sNo = (map['studentNo'] ??
              map['studentNumber'] ??
              map['number'] ??
              map['no'] ??
              map['schoolNumber'] ??
              '')
          .toString()
          .trim();

      if (_targetStudentNo.isNotEmpty &&
          _targetStudentNo != '0' &&
          sNo.isNotEmpty &&
          sNo != '0') {
        if (_targetStudentNo == sNo) return map;
      }

      // 2. İsim & Soyisim normalizasyonuna göre eşleştirme
      final sName = (map['studentName'] ??
              map['name'] ??
              map['ogrAdSoyad'] ??
              '')
          .toString()
          .trim();

      if (sName.isNotEmpty && normTarget.isNotEmpty) {
        final normCandidate = _normalizeString(sName);
        if (normCandidate == normTarget ||
            (normCandidate.length > 5 && normTarget.contains(normCandidate)) ||
            (normTarget.length > 5 && normCandidate.contains(normTarget))) {
          return map;
        }
      }
    }
    return null;
  }

  String _normalizeString(String str) {
    return str
        .trim()
        .toLowerCase()
        .replaceAll('i̇', 'i')
        .replaceAll('ı', 'i')
        .replaceAll('ş', 's')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  double _calculateNetFromSubjects(dynamic subjects) {
    if (subjects is! Map) return 0.0;
    double sum = 0.0;
    subjects.forEach((_, v) {
      if (v is Map) {
        sum += num.tryParse(v['net']?.toString() ?? '0')?.toDouble() ?? 0.0;
      }
    });
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = (screenWidth * 0.92).clamp(700.0, 1150.0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: dialogWidth,
        constraints: const BoxConstraints(maxHeight: 780),
        child: Column(
          children: [
            // 1. Header Bar
            _buildDialogHeader(),

            // 2. Body
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : _comparedExams.isEmpty
                      ? _buildEmptyState()
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // KPI Cards
                              _buildKpiSummaryCards(),
                              const SizedBox(height: 20),

                              // Sınav Bazlı Karşılaştırma Tablosu
                              _buildComparisonTableSection(),
                              const SizedBox(height: 24),

                              // Ders Bazlı Gelişim Özeti
                              _buildSubjectTrendSection(),
                            ],
                          ),
                        ),
            ),

            // 3. Footer
            _buildDialogFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogHeader() {
    final examTypeName = widget.currentExam?.examTypeName.isNotEmpty == true
        ? widget.currentExam!.examTypeName
        : (widget.currentExam?.classLevel.isNotEmpty == true
            ? '${widget.currentExam!.classLevel}. Sınıf Sınavları'
            : 'Deneme Sınavları');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          // Icon Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Icon(
                Icons.auto_graph_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Title & Student Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _targetStudentName.isNotEmpty
                          ? _targetStudentName
                          : 'Öğrenci Sınav Karşılaştırması',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_targetClassName.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _targetClassName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (_targetStudentNo.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4F46E5).withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'No: $_targetStudentNo',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Aynı Sınav Türü Gelişim Raporu ($examTypeName)',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),

          // Sınav Türü Filtre Toggle
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFilterChip(
                  label: 'Aynı Tür Sınavlar',
                  selected: _onlySameExamType,
                  onTap: () {
                    if (!_onlySameExamType) {
                      setState(() {
                        _onlySameExamType = true;
                      });
                      _processComparison();
                    }
                  },
                ),
                _buildFilterChip(
                  label: 'Tüm Sınavlar',
                  selected: !_onlySameExamType,
                  onTap: () {
                    if (_onlySameExamType) {
                      setState(() {
                        _onlySameExamType = false;
                      });
                      _processComparison();
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Close button
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            tooltip: 'Kapat',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4F46E5) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildKpiSummaryCards() {
    if (_comparedExams.isEmpty) return const SizedBox.shrink();

    final count = _comparedExams.length;
    final double avgScore =
        _comparedExams.map((e) => e.totalScore).reduce((a, b) => a + b) / count;
    final double avgNet =
        _comparedExams.map((e) => e.totalNet).reduce((a, b) => a + b) / count;

    final firstExam = _comparedExams.first;
    final latestExam = _comparedExams.last;

    final double scoreDelta = latestExam.totalScore - firstExam.totalScore;
    final double netDelta = latestExam.totalNet - firstExam.totalNet;

    return LayoutBuilder(builder: (context, constraints) {
      final isCompact = constraints.maxWidth < 750;

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          children: [
            _buildStatCard(
              title: 'Toplam Sınav',
              value: '$count Sınav',
              subtext: 'Kıyaslanan sınav adedi',
              icon: Icons.checklist_rounded,
              color: Colors.blue,
              width: isCompact ? constraints.maxWidth / 2 - 16 : 140,
            ),
            _buildStatCard(
              title: 'Ortalama Puan',
              value: avgScore.toStringAsFixed(2),
              subtext: 'Tüm sınavlar ort.',
              icon: Icons.score_rounded,
              color: Colors.indigo,
              width: isCompact ? constraints.maxWidth / 2 - 16 : 160,
            ),
            _buildStatCard(
              title: 'Ortalama Net',
              value: avgNet.toStringAsFixed(2),
              subtext: 'Tüm sınavlar ort.',
              icon: Icons.calculate_outlined,
              color: Colors.teal,
              width: isCompact ? constraints.maxWidth / 2 - 16 : 150,
            ),
            _buildStatCard(
              title: 'Net Değişimi',
              value:
                  '${netDelta >= 0 ? '+' : ''}${netDelta.toStringAsFixed(2)}',
              subtext: count > 1
                  ? '${firstExam.totalNet.toStringAsFixed(1)} ➔ ${latestExam.totalNet.toStringAsFixed(1)}'
                  : 'Tek sınav mevcut',
              icon: netDelta >= 0
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
              color: netDelta >= 0 ? Colors.green : Colors.red,
              width: isCompact ? constraints.maxWidth / 2 - 16 : 170,
            ),
            _buildStatCard(
              title: 'Puan Değişimi',
              value:
                  '${scoreDelta >= 0 ? '+' : ''}${scoreDelta.toStringAsFixed(2)}',
              subtext: count > 1 ? 'İlk ve son sınav farkı' : 'Tek sınav',
              icon: scoreDelta >= 0
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              color: scoreDelta >= 0 ? Colors.green : Colors.red,
              width: isCompact ? constraints.maxWidth / 2 - 16 : 170,
            ),
          ],
        ),
      );
    });
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtext,
    required IconData icon,
    required MaterialColor color,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade100),
        boxShadow: [
          BoxShadow(
            color: color.shade50.withValues(alpha: 0.5),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              Icon(icon, size: 16, color: color.shade600),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color.shade800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtext,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonTableSection() {
    // Tüm sınavlarda geçen benzersiz ders listesi
    final Set<String> commonSubjects = {};
    for (var ce in _comparedExams) {
      commonSubjects.addAll(ce.subjects.keys);
    }
    // Eğer widget.availableSubjects doluysa onun sırasını koru
    final orderedSubjects = widget.availableSubjects
        .where((s) => commonSubjects.contains(s))
        .toList();
    for (var s in commonSubjects) {
      if (!orderedSubjects.contains(s)) orderedSubjects.add(s);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section Title with Mouse Drag Hint & Navigation Arrows
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.table_chart_rounded,
                    size: 18, color: Color(0xFF475569)),
                const SizedBox(width: 8),
                const Text(
                  'Sınav Bazlı Kıyaslama Tablosu',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.indigo.shade100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app_outlined,
                          size: 13, color: Colors.indigo.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'Mouse ile sağa-sola kaydırabilirsiniz',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.indigo.shade800),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Sola kaydır butonu
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded, size: 14),
                  tooltip: 'Sola Kaydır',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    if (_horizontalScrollController.hasClients) {
                      _horizontalScrollController.animateTo(
                        (_horizontalScrollController.offset - 250)
                            .clamp(0.0, _horizontalScrollController.position.maxScrollExtent),
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                ),
                // Sağa kaydır butonu
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  tooltip: 'Sağa Kaydır',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    if (_horizontalScrollController.hasClients) {
                      _horizontalScrollController.animateTo(
                        (_horizontalScrollController.offset + 250)
                            .clamp(0.0, _horizontalScrollController.position.maxScrollExtent),
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                ),
                const SizedBox(width: 4),
                Text(
                  '${_comparedExams.length} Sınav listeleniyor',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),

          // Table with Mouse Drag, Mouse Wheel Scroll and Visible Scrollbar
          ScrollConfiguration(
            behavior: const MaterialScrollBehavior().copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
                PointerDeviceKind.stylus,
              },
            ),
            child: Listener(
              onPointerSignal: (pointerSignal) {
                if (pointerSignal is PointerScrollEvent) {
                  if (_horizontalScrollController.hasClients) {
                    final target = (_horizontalScrollController.offset +
                            pointerSignal.scrollDelta.dy)
                        .clamp(0.0,
                            _horizontalScrollController.position.maxScrollExtent);
                    _horizontalScrollController.jumpTo(target);
                  }
                }
              },
              child: RawScrollbar(
                controller: _horizontalScrollController,
                thumbVisibility: true,
                trackVisibility: true,
                thickness: 8,
                radius: const Radius.circular(6),
                thumbColor: Colors.indigo.shade300,
                trackColor: const Color(0xFFF1F5F9),
                trackBorderColor: Colors.transparent,
                child: SingleChildScrollView(
                  controller: _horizontalScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: DataTable(
                    headingRowHeight: 52,
                    dataRowMinHeight: 52,
                    dataRowMaxHeight: 56,
                    columnSpacing: 20,
                    horizontalMargin: 16,
                    headingRowColor:
                        WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                    columns: [
                      const DataColumn(
                        label: Text('Sınav Adı',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const DataColumn(
                        label: Text('Tarih',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const DataColumn(
                        label: Text('Toplam Net',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const DataColumn(
                        label: Text('Puan',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const DataColumn(
                        label: Text('Genel Sıra',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const DataColumn(
                        label: Text('Şube Sıra',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      // Ders Net Sütunları - Kısa İsimler ile kompakt gösterim
                      ...orderedSubjects.map((s) {
                        final shortName = _getSubjectShortName(s);
                        return DataColumn(
                          label: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  shortName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                const Text(
                                  'Net',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          tooltip: '$s (Toplam Net)',
                        );
                      }),
                      const DataColumn(
                        label: Text('Karne',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
              rows: List.generate(_comparedExams.length, (index) {
                final ce = _comparedExams[index];
                _ComparedStudentExam? prevCe =
                    index > 0 ? _comparedExams[index - 1] : null;

                final double netDelta =
                    prevCe != null ? ce.totalNet - prevCe.totalNet : 0.0;
                final double scoreDelta =
                    prevCe != null ? ce.totalScore - prevCe.totalScore : 0.0;

                final dateStr =
                    '${ce.exam.date.day.toString().padLeft(2, '0')}.${ce.exam.date.month.toString().padLeft(2, '0')}.${ce.exam.date.year}';

                return DataRow(
                  color: WidgetStateProperty.resolveWith<Color?>(
                    (Set<WidgetState> states) {
                      if (ce.isCurrentExam) {
                        return const Color(0xFFEEF2FF); // Açık indigo
                      }
                      return index.isEven
                          ? Colors.white
                          : const Color(0xFFFAFAFA);
                    },
                  ),
                  cells: [
                    // Sınav Adı
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (ce.isCurrentExam) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4F46E5),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Bu Sınav',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Text(
                              ce.exam.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: ce.isCurrentExam
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                color: ce.isCurrentExam
                                    ? const Color(0xFF312E81)
                                    : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Tarih
                    DataCell(Text(dateStr, style: const TextStyle(fontSize: 12))),

                    // Toplam Net
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            ce.totalNet.toStringAsFixed(2),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          if (prevCe != null && netDelta != 0) ...[
                            const SizedBox(width: 4),
                            _buildDeltaBadge(netDelta),
                          ],
                        ],
                      ),
                    ),

                    // Puan
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            ce.totalScore.toStringAsFixed(3),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.indigo.shade800,
                            ),
                          ),
                          if (prevCe != null && scoreDelta != 0) ...[
                            const SizedBox(width: 4),
                            _buildDeltaBadge(scoreDelta),
                          ],
                        ],
                      ),
                    ),

                    // Genel Sıra
                    DataCell(
                      Center(
                        child: Text(
                          ce.totalStudents > 0
                              ? '${ce.rankGeneral} / ${ce.totalStudents}'
                              : '${ce.rankGeneral}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),

                    // Şube Sıra
                    DataCell(
                      Center(
                        child: Text(
                          ce.rankBranch > 0 ? '${ce.rankBranch}' : '-',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),

                    // Ders Netleri
                    ...orderedSubjects.map((s) {
                      final sStat = ce.subjects[s];
                      final prevStat = prevCe?.subjects[s];

                      if (sStat == null) {
                        return const DataCell(Center(child: Text('-')));
                      }

                      final double subjDelta = prevStat != null
                          ? sStat.net - prevStat.net
                          : 0.0;

                      return DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              sStat.net.toStringAsFixed(2),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (prevStat != null && subjDelta != 0) ...[
                              const SizedBox(width: 3),
                              _buildMiniTrendIndicator(subjDelta),
                            ],
                          ],
                        ),
                      );
                    }),

                    // Karne Açma Butonu
                    DataCell(
                      Tooltip(
                        message: '${ce.exam.name} Sonuç Karnesini Aç',
                        child: InkWell(
                          onTap: () => _openExamReportCard(ce),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              border: Border.all(color: Colors.amber.shade400),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.badge_outlined,
                                    size: 14, color: Colors.amber.shade900),
                                const SizedBox(width: 4),
                                Text(
                                  'Karne',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    ),
  ],
),
);
}

  Widget _buildDeltaBadge(double delta) {
    final isPos = delta > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: isPos ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${isPos ? '+' : ''}${delta.toStringAsFixed(1)}',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isPos ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
        ),
      ),
    );
  }

  Widget _buildMiniTrendIndicator(double delta) {
    final isPos = delta > 0;
    return Icon(
      isPos ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
      size: 16,
      color: isPos ? Colors.green.shade700 : Colors.red.shade700,
    );
  }

  Widget _buildSubjectTrendSection() {
    if (_comparedExams.length < 2) {
      return const SizedBox.shrink();
    }

    final firstExam = _comparedExams.first;
    final latestExam = _comparedExams.last;

    final Set<String> allSubjectNames = {};
    for (var e in _comparedExams) {
      allSubjectNames.addAll(e.subjects.keys);
    }

    final ordered = widget.availableSubjects
        .where((s) => allSubjectNames.contains(s))
        .toList();
    for (var s in allSubjectNames) {
      if (!ordered.contains(s)) ordered.add(s);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded,
                  size: 18, color: Color(0xFF4F46E5)),
              const SizedBox(width: 8),
              const Text(
                'Ders Bazlı Gelişim Seyri',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const Spacer(),
              Text(
                'İlk Sınav ➔ Son Sınav Net Değişimi',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: ordered.map((subjectName) {
              final double firstNet = firstExam.subjects[subjectName]?.net ?? 0.0;
              final double lastNet = latestExam.subjects[subjectName]?.net ?? 0.0;
              final double diff = lastNet - firstNet;
              final bool isPos = diff >= 0;

              return Container(
                width: 250,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isPos
                        ? Colors.green.shade100
                        : Colors.red.shade100,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subjectName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${firstNet.toStringAsFixed(1)} ➔ ${lastNet.toStringAsFixed(1)} Net',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isPos
                                ? const Color(0xFFDCFCE7)
                                : const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${isPos ? '+' : ''}${diff.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isPos
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFFDC2626),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final examTypeName = widget.currentExam?.examTypeName.isNotEmpty == true
        ? widget.currentExam!.examTypeName
        : 'Kurumsal Deneme';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.history_toggle_off_rounded,
                size: 48,
                color: Colors.amber.shade800,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Aynı Sınav Türünde Başka Sınav Bulunamadı',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450),
              child: Text(
                '$_targetStudentName adlı öğrencinin "$examTypeName" türünde karşılaştırılacak başka bir sınav kaydı bulunamadı. Öğrencinin girmiş olduğu tüm sınav türlerini listelemek için aşağıdaki butona basabilirsiniz.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _onlySameExamType = false;
                });
                _processComparison();
              },
              icon: const Icon(Icons.all_inclusive_rounded, size: 18),
              label: const Text('Tüm Sınav Türlerinde Ara'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  void _openExamReportCard(_ComparedStudentExam ce) {
    final raw = ce.rawRecord;

    final answers = (raw['answers'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
        (raw['cevaplar'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
        <String, String>{};

    final booklet = (raw['booklet'] ?? 'A').toString();
    Map<String, String> correctAnswers = {};
    if (raw['correctAnswers'] != null && raw['correctAnswers'] is Map) {
      correctAnswers = (raw['correctAnswers'] as Map)
          .map((k, v) => MapEntry(k.toString(), v.toString()));
    } else if (ce.exam.answerKeys.containsKey(booklet)) {
      correctAnswers = Map<String, String>.from(ce.exam.answerKeys[booklet]!);
    }

    final student = StudentResult(
      tcNo: (raw['tcNo'] ?? '').toString(),
      studentNo: ce.studentNo,
      name: ce.studentName,
      classLevel: ce.exam.classLevel,
      branch: ce.className,
      booklet: booklet,
      score: ce.totalScore,
      rankGeneral: ce.rankGeneral,
      rankInstitution: ce.rankGeneral,
      rankBranch: ce.rankBranch,
      answers: answers,
      correctAnswers: correctAnswers,
      subjects: ce.subjects,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => StudentReportCardDialog(
          student: student,
          examName: ce.exam.name,
          subjects: ce.subjects.keys.toList(),
          outcomes: ce.exam.outcomes,
          totalStudents: ce.totalStudents > 0 ? ce.totalStudents : 1,
          schoolStudents: ce.totalStudents > 0 ? ce.totalStudents : 1,
          branchStudents: 1,
          isRankingVisible: ce.exam.sharingSettings['isRankingVisible'] ?? true,
          trialExamId: ce.exam.id,
        ),
      ),
    );
  }
}

class _ComparedStudentExam {
  final TrialExam exam;
  final bool isCurrentExam;
  final String studentName;
  final String studentNo;
  final String className;
  final double totalScore;
  final double totalNet;
  final int rankGeneral;
  final int totalStudents;
  final int rankBranch;
  final Map<String, SubjectStats> subjects;
  final Map<String, dynamic> rawRecord;

  _ComparedStudentExam({
    required this.exam,
    required this.isCurrentExam,
    required this.studentName,
    required this.studentNo,
    required this.className,
    required this.totalScore,
    required this.totalNet,
    required this.rankGeneral,
    required this.totalStudents,
    required this.rankBranch,
    required this.subjects,
    required this.rawRecord,
  });
}
