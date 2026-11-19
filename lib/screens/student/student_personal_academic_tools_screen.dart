import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../services/term_service.dart';
import '../../widgets/edukn_app_bar.dart';
import 'student_etut_stats_screen.dart';

/// Öğrenci ve Veli için YALNIZCA tek öğrencinin (giriş yapan öğrenci veya
/// velinin seçili çocuğu) kendi verileriyle çalışan kişisel akademik araçlar:
/// 0 -> Kişisel LGS / YKS Puan & Hedef Simülatörü
/// 1 -> Kişisel Deneme Gelişim & Net Koçum (Eşdeğer Soru Sayısı Korumalı)
/// 2 -> Branş & Kazanım Eksik Karnem
/// 3 -> Yazılı Ortalaması & Takdir / Teşekkür Hesaplayıcı
class StudentPersonalAcademicToolsScreen extends StatefulWidget {
  final String institutionId;
  final String studentId;
  final Map<String, dynamic> studentData;
  final int initialToolIndex;
  final bool isParentView;

  const StudentPersonalAcademicToolsScreen({
    super.key,
    required this.institutionId,
    required this.studentId,
    required this.studentData,
    this.initialToolIndex = 0,
    this.isParentView = false,
  });

  @override
  State<StudentPersonalAcademicToolsScreen> createState() =>
      _StudentPersonalAcademicToolsScreenState();
}

class _PersonalTrialRecord {
  final String examId;
  final String examName;
  final DateTime date;
  final String examTypeName;
  final double totalNet;
  final double score;
  final int totalCorrect;
  final int totalWrong;
  final int totalEmpty;
  final int effectiveQuestions;
  final int subjectCount;
  final Map<String, _PersonalSubjectStat> subjects;

  const _PersonalTrialRecord({
    required this.examId,
    required this.examName,
    required this.date,
    required this.examTypeName,
    required this.totalNet,
    required this.score,
    required this.totalCorrect,
    required this.totalWrong,
    required this.totalEmpty,
    required this.effectiveQuestions,
    required this.subjectCount,
    required this.subjects,
  });

  bool get isFullTrial {
    final lower = '$examName $examTypeName'.toLowerCase();
    if (lower.contains('tarama') ||
        lower.contains('branş') ||
        lower.contains('brans') ||
        lower.contains('konu') ||
        lower.contains('quiz') ||
        lower.contains('fasikül')) {
      return false;
    }
    if (subjectCount >= 4) return true;
    return effectiveQuestions >= 50;
  }

  double get netSuccessPercent => effectiveQuestions > 0
      ? ((totalNet / effectiveQuestions) * 100).clamp(0.0, 100.0)
      : 0.0;
}

class _PersonalSubjectStat {
  final String name;
  final int correct;
  final int wrong;
  final int empty;
  final double net;
  final List<String> weakTopics;

  const _PersonalSubjectStat({
    required this.name,
    required this.correct,
    required this.wrong,
    required this.empty,
    required this.net,
    this.weakTopics = const [],
  });

  int get totalQuestions => correct + wrong + empty;
  double get successRate =>
      totalQuestions > 0 ? ((correct / totalQuestions) * 100).clamp(0, 100) : 0;
}

class _CourseGradeEntry {
  String courseName;
  double weeklyHours;
  final TextEditingController exam1Ctrl;
  final TextEditingController exam2Ctrl;
  final TextEditingController perf1Ctrl;
  final TextEditingController perf2Ctrl;

  _CourseGradeEntry({
    required this.courseName,
    this.weeklyHours = 4,
    String exam1 = '',
    String exam2 = '',
    String perf1 = '',
    String perf2 = '',
  }) : exam1Ctrl = TextEditingController(text: exam1),
       exam2Ctrl = TextEditingController(text: exam2),
       perf1Ctrl = TextEditingController(text: perf1),
       perf2Ctrl = TextEditingController(text: perf2);

  double? get average {
    final vals = <double>[];
    for (final c in [exam1Ctrl, exam2Ctrl, perf1Ctrl, perf2Ctrl]) {
      final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
      if (v != null && v >= 0 && v <= 100) vals.add(v);
    }
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  void dispose() {
    exam1Ctrl.dispose();
    exam2Ctrl.dispose();
    perf1Ctrl.dispose();
    perf2Ctrl.dispose();
  }
}

class _StudentPersonalAcademicToolsScreenState
    extends State<StudentPersonalAcademicToolsScreen> {
  late int _selectedTab;
  bool _loading = true;
  String? _activeTermName;

  List<_PersonalTrialRecord> _myTrials = [];
  int _coachExamMode = 0; // 0: Genel Denemeler, 1: Tarama/Branş, 2: Tümü
  int? _hoveredTrendIdx;

  // Simülatör (0: LGS, 1: YKS TYT)
  late bool _isHighSchoolMode;
  double _targetScore = 450;
  final Map<String, int> _simCorrect = {};
  final Map<String, int> _simWrong = {};

  // Takdir / Teşekkür hesaplayıcı
  final List<_CourseGradeEntry> _courseEntries = [];

  static const Map<String, ({int maxQ, double coeff})> _lgsSpec = {
    'Türkçe': (maxQ: 20, coeff: 4.348),
    'Matematik': (maxQ: 20, coeff: 4.254),
    'Fen Bilimleri': (maxQ: 20, coeff: 4.123),
    'T.C. İnkılap Tarihi': (maxQ: 10, coeff: 1.666),
    'Din Kültürü': (maxQ: 10, coeff: 1.899),
    'Yabancı Dil': (maxQ: 10, coeff: 1.508),
  };

  static const Map<String, ({int maxQ, double coeff})> _tytSpec = {
    'TYT Türkçe': (maxQ: 40, coeff: 3.30),
    'TYT Sosyal Bilimler': (maxQ: 20, coeff: 3.40),
    'TYT Temel Matematik': (maxQ: 40, coeff: 3.30),
    'TYT Fen Bilimleri': (maxQ: 20, coeff: 3.40),
  };

  String get _studentName {
    final full = (widget.studentData['fullName'] ?? '').toString().trim();
    if (full.isNotEmpty) return full;
    return '${widget.studentData['name'] ?? ''} ${widget.studentData['surname'] ?? ''}'
        .trim();
  }

  String get _studentNo =>
      (widget.studentData['studentNo'] ??
              widget.studentData['studentNumber'] ??
              widget.studentData['no'] ??
              '')
          .toString()
          .trim();

  String get _className =>
      (widget.studentData['className'] ?? '').toString().trim();

  String get _classId =>
      (widget.studentData['classId'] ?? '').toString().trim();

  String get _classLevel {
    final raw =
        (widget.studentData['classLevel'] ??
                widget.studentData['gradeLevel'] ??
                '')
            .toString()
            .trim();
    if (raw.isNotEmpty) return raw;
    final digits = RegExp(r'\d+').firstMatch(_className)?.group(0) ?? '';
    if (digits.startsWith('10') ||
        digits.startsWith('11') ||
        digits.startsWith('12')) {
      return digits.substring(0, 2);
    }
    return digits.isNotEmpty ? digits.substring(0, 1) : '';
  }

  String get _studentSubtitle {
    final parts = <String>[
      if (_studentNo.isNotEmpty) _studentNo,
      if (_studentName.isNotEmpty) _studentName,
      if (_className.isNotEmpty) '($_className)',
    ];
    return parts.join(' • ');
  }

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialToolIndex.clamp(0, 3);
    final gradeNum = int.tryParse(_classLevel) ?? 8;
    final stName = (widget.studentData['schoolTypeName'] ?? '')
        .toString()
        .toLowerCase();
    _isHighSchoolMode =
        gradeNum >= 9 || stName.contains('lise') || stName.contains('anadolu');
    _targetScore = _isHighSchoolMode ? 430 : 450;
    _initDefaultSimValues();
    _loadPersonalAcademicData();
  }

  void _initDefaultSimValues() {
    _simCorrect.clear();
    _simWrong.clear();
    final spec = _isHighSchoolMode ? _tytSpec : _lgsSpec;
    for (final e in spec.entries) {
      _simCorrect[e.key] = (e.value.maxQ * 0.75).round();
      _simWrong[e.key] = (e.value.maxQ * 0.10).round();
    }
  }

  @override
  void dispose() {
    for (final c in _courseEntries) {
      c.dispose();
    }
    super.dispose();
  }

  /// Yalnızca bu öğrencinin sonucunu eşleştirir (başka hiçbir öğrencinin verisi okunmaz/tutulmaz!)
  Map<String, dynamic>? _extractOnlyThisStudentResult(
    List<dynamic> allResults,
  ) {
    final sNo = _studentNo;
    // 1) Sisteme eşleşmiş öğrenci kimliği (en güvenilir)
    if (widget.studentId.isNotEmpty) {
      for (final raw in allResults) {
        if (raw is! Map) continue;
        if ((raw['systemStudentId'] ?? '').toString() == widget.studentId) {
          return Map<String, dynamic>.from(raw);
        }
      }
    }
    if (sNo.isNotEmpty) {
      for (final raw in allResults) {
        if (raw is! Map) continue;
        final rNo =
            (raw['studentNo'] ??
                    raw['studentNumber'] ??
                    raw['number'] ??
                    raw['schoolNumber'] ??
                    raw['no'] ??
                    '')
                .toString()
                .trim();
        if (rNo == sNo) return Map<String, dynamic>.from(raw);
      }
    }
    if (widget.studentId.isNotEmpty) {
      for (final raw in allResults) {
        if (raw is! Map) continue;
        final rid = (raw['studentId'] ?? raw['id'] ?? '').toString().trim();
        if (rid == widget.studentId) return Map<String, dynamic>.from(raw);
      }
    }
    final targetLower = _studentName.toLowerCase();
    if (targetLower.length >= 4) {
      for (final raw in allResults) {
        if (raw is! Map) continue;
        final rName = (raw['name'] ?? raw['studentName'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (rName == targetLower) return Map<String, dynamic>.from(raw);
      }
    }
    return null;
  }

  Future<void> _loadPersonalAcademicData() async {
    setState(() => _loading = true);
    try {
      final instUpper = widget.institutionId.toUpperCase();
      final instIds = {
        widget.institutionId,
        instUpper,
        widget.institutionId.toLowerCase(),
      }.where((s) => s.isNotEmpty).toList();

      final activeTermId =
          await TermService().getSelectedTermId() ??
          await TermService().getActiveTermId();

      if (activeTermId != null && activeTermId.isNotEmpty) {
        try {
          final termDoc = await FirebaseFirestore.instance
              .collection('terms')
              .doc(activeTermId)
              .get();
          _activeTermName =
              (termDoc.data()?['name'] ?? termDoc.data()?['termName'])
                  ?.toString();
        } catch (_) {}
      }

      // Paralel olarak YALNIZCA öğrencinin kendi sınav ve ders verilerini yükle
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('trial_exams')
            .where('institutionId', whereIn: instIds)
            .where('isActive', isEqualTo: true)
            .get()
            .catchError(
              (_) => FirebaseFirestore.instance
                  .collection('trial_exams')
                  .limit(0)
                  .get(),
            ),
        _classId.isNotEmpty
            ? FirebaseFirestore.instance
                  .collection('class_exams')
                  .where('institutionId', whereIn: instIds)
                  .where('classId', isEqualTo: _classId)
                  .get()
                  .catchError(
                    (_) => FirebaseFirestore.instance
                        .collection('class_exams')
                        .limit(0)
                        .get(),
                  )
            : Future.value(null),
        _classId.isNotEmpty
            ? FirebaseFirestore.instance
                  .collection('lessonAssignments')
                  .where('institutionId', whereIn: instIds)
                  .where('classId', isEqualTo: _classId)
                  .where('isActive', isEqualTo: true)
                  .get()
                  .catchError(
                    (_) => FirebaseFirestore.instance
                        .collection('lessonAssignments')
                        .limit(0)
                        .get(),
                  )
            : Future.value(null),
      ]);

      final trialSnap = results[0] as QuerySnapshot<Map<String, dynamic>>;
      final classExamsSnap = results[1] as QuerySnapshot<Map<String, dynamic>>?;
      final assignSnap = results[2] as QuerySnapshot<Map<String, dynamic>>?;

      final parsedTrials = <_PersonalTrialRecord>[];
      for (final doc in trialSnap.docs) {
        final data = doc.data();
        final docTerm = data['termId']?.toString().trim();
        if (activeTermId != null &&
            activeTermId.isNotEmpty &&
            docTerm != null &&
            docTerm.isNotEmpty &&
            docTerm != activeTermId) {
          continue;
        }
        // Sonuçlar gerçekte `resultsJson` (JSON string) alanında saklanır.
        dynamic rawList = data['results'];
        if (rawList == null && data['resultsJson'] is String) {
          try {
            rawList = jsonDecode(data['resultsJson'] as String);
          } catch (_) {}
        }
        if (rawList is! List || rawList.isEmpty) continue;
        final myRow = _extractOnlyThisStudentResult(rawList);
        if (myRow == null) continue;

        final dt = data['date'] is Timestamp
            ? (data['date'] as Timestamp).toDate()
            : (DateTime.tryParse((data['date'] ?? '').toString()) ??
                  DateTime.now());

        final subjMap = <String, _PersonalSubjectStat>{};
        int sumC = 0, sumW = 0, sumE = 0;
        final rawSubjects = myRow['subjects'] ?? myRow['lessons'];
        if (rawSubjects is Map) {
          rawSubjects.forEach((k, v) {
            if (v is Map) {
              final c =
                  int.tryParse((v['correct'] ?? v['d'] ?? 0).toString()) ?? 0;
              final w =
                  int.tryParse((v['wrong'] ?? v['y'] ?? 0).toString()) ?? 0;
              final e =
                  int.tryParse((v['empty'] ?? v['b'] ?? 0).toString()) ?? 0;
              final n =
                  double.tryParse((v['net'] ?? '').toString()) ??
                  (c - (w / (_isHighSchoolMode ? 4.0 : 3.0)));
              final weak = <String>[];
              if (v['wrongOutcomes'] is List) {
                for (final o in (v['wrongOutcomes'] as List)) {
                  final txt = o.toString().trim();
                  if (txt.isNotEmpty) weak.add(txt);
                }
              } else {
                // Yanlış/boş bırakılan soruların kazanımlarını cevap anahtarından türet
                try {
                  final ansAll = myRow['answers'];
                  final keyAll = myRow['correctAnswers'];
                  final outAll = data['outcomes'];
                  final booklet = (myRow['booklet'] ?? 'A').toString();
                  if (ansAll is Map && keyAll is Map && outAll is Map) {
                    final ans = (ansAll[k] ?? '').toString();
                    final key = (keyAll[k] ?? '').toString();
                    final bookletOut = outAll[booklet] ?? outAll.values.first;
                    final outs = bookletOut is Map ? bookletOut[k] : null;
                    if (outs is List && key.isNotEmpty) {
                      for (
                        int qi = 0;
                        qi < key.length && qi < outs.length;
                        qi++
                      ) {
                        final given = qi < ans.length ? ans[qi] : ' ';
                        if (given != key[qi]) {
                          final txt = outs[qi].toString().trim();
                          if (txt.isNotEmpty && !weak.contains(txt))
                            weak.add(txt);
                        }
                      }
                    }
                  }
                } catch (_) {}
              }
              if ((c + w + e) > 0 || n > 0) {
                subjMap[k.toString()] = _PersonalSubjectStat(
                  name: k.toString(),
                  correct: c,
                  wrong: w,
                  empty: e,
                  net: n,
                  weakTopics: weak,
                );
                sumC += c;
                sumW += w;
                sumE += e;
              }
            }
          });
        }

        final totC =
            int.tryParse(
              (myRow['totalCorrect'] ?? myRow['correct'] ?? sumC).toString(),
            ) ??
            sumC;
        final totW =
            int.tryParse(
              (myRow['totalWrong'] ?? myRow['wrong'] ?? sumW).toString(),
            ) ??
            sumW;
        final totE =
            int.tryParse(
              (myRow['totalEmpty'] ?? myRow['empty'] ?? sumE).toString(),
            ) ??
            sumE;
        final totNet =
            double.tryParse(
              (myRow['totalNet'] ?? myRow['net'] ?? '').toString(),
            ) ??
            (totC - (totW / (_isHighSchoolMode ? 4.0 : 3.0)));
        final score =
            double.tryParse(
              (myRow['score'] ?? myRow['totalScore'] ?? 0).toString(),
            ) ??
            0.0;
        final qCap = (totC + totW + totE) > 0
            ? (totC + totW + totE)
            : (int.tryParse((data['totalQuestions'] ?? 0).toString()) ?? 90);

        parsedTrials.add(
          _PersonalTrialRecord(
            examId: doc.id,
            examName: (data['name'] ?? data['examName'] ?? 'Deneme Sınavı')
                .toString(),
            date: dt,
            examTypeName: (data['examTypeName'] ?? data['type'] ?? '')
                .toString(),
            totalNet: totNet,
            score: score,
            totalCorrect: totC,
            totalWrong: totW,
            totalEmpty: totE,
            effectiveQuestions: qCap,
            subjectCount: subjMap.length,
            subjects: subjMap,
          ),
        );
      }

      parsedTrials.sort((a, b) => a.date.compareTo(b.date));
      _myTrials = parsedTrials;

      // En güncel genel deneme verisini simülatöre otomatik doldur
      final fullTrials = _myTrials.where((t) => t.isFullTrial).toList();
      final latestForSim = fullTrials.isNotEmpty
          ? fullTrials.last
          : (_myTrials.isNotEmpty ? _myTrials.last : null);
      if (latestForSim != null && latestForSim.subjects.isNotEmpty) {
        _applyTrialToSimulator(latestForSim, notify: false);
      }

      // Yazılı notlarını YALNIZCA bu öğrenci için oku
      final courseScores = <String, List<double>>{};
      final courseHours = <String, double>{};

      if (assignSnap != null) {
        for (final d in assignSnap.docs) {
          final m = d.data();
          final docTerm = m['termId']?.toString().trim();
          if (activeTermId != null &&
              activeTermId.isNotEmpty &&
              docTerm != null &&
              docTerm.isNotEmpty &&
              docTerm != activeTermId) {
            continue;
          }
          final cName = (m['lessonName'] ?? m['branchName'] ?? '')
              .toString()
              .trim();
          if (cName.isEmpty) continue;
          final hrs =
              double.tryParse(
                (m['weeklyHours'] ?? m['hours'] ?? m['lessonHours'] ?? 4)
                    .toString(),
              ) ??
              4.0;
          courseHours[cName] = hrs > 0 ? hrs : 4.0;
          courseScores.putIfAbsent(cName, () => []);
        }
      }

      if (classExamsSnap != null) {
        for (final doc in classExamsSnap.docs) {
          final d = doc.data();
          final docTerm = d['termId']?.toString().trim();
          if (activeTermId != null &&
              activeTermId.isNotEmpty &&
              docTerm != null &&
              docTerm.isNotEmpty &&
              docTerm != activeTermId) {
            continue;
          }
          final grades = Map<String, dynamic>.from(d['grades'] ?? {});
          final rawMyScore = grades[widget.studentId];
          final myScore = rawMyScore != null
              ? double.tryParse(rawMyScore.toString())
              : null;
          final lessonName = (d['lessonName'] ?? d['lesson'] ?? 'Ders')
              .toString()
              .trim();
          courseScores.putIfAbsent(lessonName, () => []);
          if (myScore != null) {
            courseScores[lessonName]!.add(myScore);
          }
        }
      }

      for (final c in _courseEntries) {
        c.dispose();
      }
      _courseEntries.clear();

      if (courseScores.isNotEmpty) {
        for (final entry in courseScores.entries) {
          final sList = entry.value;
          _courseEntries.add(
            _CourseGradeEntry(
              courseName: entry.key,
              weeklyHours: courseHours[entry.key] ?? 4,
              exam1: sList.isNotEmpty ? sList[0].toStringAsFixed(0) : '',
              exam2: sList.length > 1 ? sList[1].toStringAsFixed(0) : '',
              perf1: sList.length > 2 ? sList[2].toStringAsFixed(0) : '',
            ),
          );
        }
      } else {
        final defaults = _isHighSchoolMode
            ? [
                ('Türk Dili ve Edebiyatı', 5.0),
                ('Matematik', 6.0),
                ('Fizik', 2.0),
                ('Kimya', 2.0),
                ('Biyoloji', 2.0),
                ('Tarih', 2.0),
                ('Yabancı Dil', 4.0),
              ]
            : [
                ('Türkçe', 6.0),
                ('Matematik', 5.0),
                ('Fen Bilimleri', 4.0),
                ('Sosyal Bilgiler / İnkılap', 3.0),
                ('Yabancı Dil', 3.0),
                ('Din Kültürü', 2.0),
              ];
        for (final item in defaults) {
          _courseEntries.add(
            _CourseGradeEntry(courseName: item.$1, weeklyHours: item.$2),
          );
        }
      }
    } catch (e) {
      debugPrint('StudentPersonalAcademicTools error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyTrialToSimulator(_PersonalTrialRecord rec, {bool notify = true}) {
    final spec = _isHighSchoolMode ? _tytSpec : _lgsSpec;
    for (final specEntry in spec.entries) {
      final keyLower = specEntry.key.toLowerCase();
      _PersonalSubjectStat? matched;
      for (final s in rec.subjects.values) {
        final sLower = s.name.toLowerCase();
        if (keyLower.contains('türkçe') && sLower.contains('türk')) {
          matched = s;
          break;
        } else if (keyLower.contains('mat') && sLower.contains('mat')) {
          matched = s;
          break;
        } else if (keyLower.contains('fen') && sLower.contains('fen')) {
          matched = s;
          break;
        } else if (keyLower.contains('inkılap') &&
            (sLower.contains('ink') || sLower.contains('sos'))) {
          matched = s;
          break;
        } else if (keyLower.contains('sosyal') && sLower.contains('sos')) {
          matched = s;
          break;
        } else if (keyLower.contains('din') && sLower.contains('din')) {
          matched = s;
          break;
        } else if (keyLower.contains('dil') &&
            (sLower.contains('ing') || sLower.contains('dil'))) {
          matched = s;
          break;
        }
      }
      if (matched != null) {
        final maxQ = specEntry.value.maxQ;
        final c = matched.correct.clamp(0, maxQ);
        final w = matched.wrong.clamp(0, maxQ - c);
        _simCorrect[specEntry.key] = c;
        _simWrong[specEntry.key] = w;
      }
    }
    if (notify && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ "${rec.examName}" netlerin simülatöre aktarıldı.'),
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  double get _simulatedScore {
    final spec = _isHighSchoolMode ? _tytSpec : _lgsSpec;
    final penalty = _isHighSchoolMode ? 4.0 : 3.0;
    double raw = _isHighSchoolMode ? 100.0 : 194.75;
    for (final e in spec.entries) {
      final c = _simCorrect[e.key] ?? 0;
      final w = _simWrong[e.key] ?? 0;
      final net = math.max(0.0, c - (w / penalty));
      raw += net * e.value.coeff;
    }
    return raw.clamp(100.0, 500.0);
  }

  double get _simulatedTotalNet {
    final spec = _isHighSchoolMode ? _tytSpec : _lgsSpec;
    final penalty = _isHighSchoolMode ? 4.0 : 3.0;
    double total = 0;
    for (final e in spec.entries) {
      final c = _simCorrect[e.key] ?? 0;
      final w = _simWrong[e.key] ?? 0;
      total += math.max(0.0, c - (w / penalty));
    }
    return total;
  }

  String _estimatePercentile(double score) {
    if (score >= 488) return '%0.1 – %0.4 (Türkiye Derecesi)';
    if (score >= 475) return '%0.5 – %1.2 (Şampiyonluk Dilimi)';
    if (score >= 455) return '%1.3 – %3.0 (Proje Okulları / Seçkin Hedef)';
    if (score >= 430) return '%3.1 – %6.5 (Nitelikli Üst Dilim)';
    if (score >= 400) return '%6.6 – %12.0 (İyi Dilim)';
    if (score >= 360) return '%12.1 – %22.0 (Gelişen Dilim)';
    return '%22+ (Temel Güçlendirme Aşaması)';
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      (
        icon: Icons.rocket_launch_rounded,
        label: _isHighSchoolMode
            ? 'YKS Hedef Simülatörü'
            : 'LGS Hedef Simülatörü',
      ),
      (icon: Icons.insights_rounded, label: 'Deneme & Net Koçum'),
      (icon: Icons.radar_rounded, label: 'Kazanım & Branş Karnem'),
      (
        icon: Icons.workspace_premium_rounded,
        label: 'Takdir / Teşekkür Hesapla',
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        institutionId: widget.institutionId,
        title: widget.isParentView
            ? 'Öğrenci Akademik Başarı Araçları'
            : 'Kişisel Akademik Araçlarım',
        subtitle: _studentSubtitle,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Gizlilik & Kişisel Veri Güvencesi + Sekme Seçici
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFFA7F3D0),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.verified_user_rounded,
                                  size: 14,
                                  color: Color(0xFF059669),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Kişisel Veri Alanı: Yalnızca $_studentName verileri görüntülenir',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF065F46),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_activeTermName != null &&
                              _activeTermName!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Aktif Dönem: $_activeTermName',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF4338CA),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: List.generate(tabs.length, (i) {
                            final selected = _selectedTab == i;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                selected: selected,
                                showCheckmark: false,
                                avatar: Icon(
                                  tabs[i].icon,
                                  size: 17,
                                  color: selected
                                      ? Colors.white
                                      : const Color(0xFF475569),
                                ),
                                label: Text(
                                  tabs[i].label,
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: selected
                                        ? Colors.white
                                        : const Color(0xFF334155),
                                  ),
                                ),
                                selectedColor: const Color(0xFF4F46E5),
                                backgroundColor: const Color(0xFFF1F5F9),
                                onSelected: (_) =>
                                    setState(() => _selectedTab = i),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildSelectedToolBody(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSelectedToolBody() {
    switch (_selectedTab) {
      case 0:
        return _buildSimulatorView();
      case 1:
        return _buildPersonalCoachView();
      case 2:
        return _buildOutcomeCardView();
      case 3:
        return _buildGpaCalculatorView();
      default:
        return _buildSimulatorView();
    }
  }

  // ─────────────────── 0. KİŞİSEL HEDEF SİMÜLATÖRÜ ───────────────────────────

  Widget _buildSimulatorView() {
    final spec = _isHighSchoolMode ? _tytSpec : _lgsSpec;
    final maxTotalQ = _isHighSchoolMode ? 120 : 90;
    final score = _simulatedScore;
    final net = _simulatedTotalNet;
    final gap = _targetScore - score;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final summaryPanel = Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF312E81), Color(0xFF4F46E5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4F46E5).withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isHighSchoolMode
                          ? 'Kişisel YKS (TYT) Puan Simülasyonu'
                          : 'Kişisel LGS Puan & Yüzdelik Simülasyonu',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  SegmentedButton<bool>(
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (s) => s.contains(WidgetState.selected)
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.14),
                      ),
                      foregroundColor: WidgetStateProperty.resolveWith(
                        (s) => s.contains(WidgetState.selected)
                            ? const Color(0xFF312E81)
                            : Colors.white,
                      ),
                    ),
                    segments: const [
                      ButtonSegment(value: false, label: Text('LGS')),
                      ButtonSegment(value: true, label: Text('YKS')),
                    ],
                    selected: {_isHighSchoolMode},
                    onSelectionChanged: (s) {
                      setState(() {
                        _isHighSchoolMode = s.first;
                        _initDefaultSimValues();
                        if (_myTrials.isNotEmpty) {
                          _applyTrialToSimulator(_myTrials.last, notify: false);
                        }
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    score.toStringAsFixed(2),
                    style: GoogleFonts.inter(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '/ 500 Puan  •  ${net.toStringAsFixed(2)} / $maxTotalQ Net',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.emoji_events_rounded,
                      color: Color(0xFFFDE047),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tahmini Yüzdelik Dilim: ${_estimatePercentile(score)}',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Hedef Puanım: ${_targetScore.toStringAsFixed(0)} Puan',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              Slider(
                value: _targetScore.clamp(250, 500),
                min: 250,
                max: 500,
                divisions: 50,
                activeColor: const Color(0xFF34D399),
                inactiveColor: Colors.white24,
                onChanged: (v) => setState(() => _targetScore = v),
              ),
              Text(
                gap <= 0
                    ? '🎉 Tebrikler! Hedef puanının ${gap.abs().toStringAsFixed(1)} puan üzerindesin!'
                    : 'Hedefe ulaşmak için +${gap.toStringAsFixed(1)} puana (yaklaşık ${(gap / 4.2).ceil()} ana ders netine) ihtiyacın var.',
                style: GoogleFonts.inter(
                  color: const Color(0xFFA7F3D0),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              if (_myTrials.isNotEmpty) ...[
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF312E81),
                  ),
                  onPressed: () => _applyTrialToSimulator(_myTrials.last),
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 17),
                  label: Text(
                    'Son Denememi Yükle (${_myTrials.last.examName})',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        );

        final slidersPanel = Column(
          children: spec.entries.map((entry) {
            final maxQ = entry.value.maxQ;
            final c = (_simCorrect[entry.key] ?? 0).clamp(0, maxQ);
            final w = (_simWrong[entry.key] ?? 0).clamp(0, maxQ - c);
            final empty = maxQ - c - w;
            final penalty = _isHighSchoolMode ? 4.0 : 3.0;
            final sNet = math.max(0.0, c - (w / penalty));
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
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
                      Expanded(
                        child: Text(
                          entry.key,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${sNet.toStringAsFixed(2)} Net  •  $c D / $w Y / $empty B',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF4338CA),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        width: 68,
                        child: Text(
                          'Doğru: $c',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF059669),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: c.toDouble(),
                          min: 0,
                          max: maxQ.toDouble(),
                          divisions: maxQ,
                          activeColor: const Color(0xFF059669),
                          onChanged: (v) {
                            setState(() {
                              final newC = v.round();
                              _simCorrect[entry.key] = newC;
                              if ((_simWrong[entry.key] ?? 0) > maxQ - newC) {
                                _simWrong[entry.key] = maxQ - newC;
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      SizedBox(
                        width: 68,
                        child: Text(
                          'Yanlış: $w',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFDC2626),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: w.toDouble(),
                          min: 0,
                          max: math.max(1, maxQ - c).toDouble(),
                          divisions: math.max(1, maxQ - c),
                          activeColor: const Color(0xFFEF4444),
                          onChanged: (maxQ - c) == 0
                              ? null
                              : (v) => setState(
                                  () => _simWrong[entry.key] = v.round(),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: summaryPanel),
              const SizedBox(width: 18),
              Expanded(flex: 7, child: slidersPanel),
            ],
          );
        }
        return Column(
          children: [summaryPanel, const SizedBox(height: 16), slidersPanel],
        );
      },
    );
  }

  // ─────────────────── 1. KİŞİSEL DENEME & NET KOÇU ──────────────────────────

  Widget _buildPersonalCoachView() {
    if (_myTrials.isEmpty) {
      return _buildEmptyCard(
        icon: Icons.insights_rounded,
        title: 'Aktif Dönemde Deneme Sonucu Bulunamadı',
        subtitle:
            'Bu dönemde katıldığın deneme sınavları açıklandığında kişisel net gelişim grafiğin ve strateji koçun burada otomatik oluşur.',
      );
    }

    final fullList = _myTrials.where((t) => t.isFullTrial).toList();
    final branchList = _myTrials.where((t) => !t.isFullTrial).toList();

    final filtered = _coachExamMode == 0
        ? (fullList.isNotEmpty ? fullList : _myTrials)
        : (_coachExamMode == 1 ? branchList : _myTrials);

    final refQuestions = _isHighSchoolMode ? 120 : 90;
    final distinctCaps = filtered.map((e) => e.effectiveQuestions).toSet();
    final hasMixedQuestionCounts = distinctCaps.length > 1;

    double bestNet = 0;
    double bestScore = 0;
    for (final t in filtered) {
      if (t.totalNet > bestNet) bestNet = t.totalNet;
      if (t.score > bestScore) bestScore = t.score;
    }

    double eqDelta = 0;
    if (filtered.length >= 2) {
      final first = filtered.first;
      final last = filtered.last;
      if (hasMixedQuestionCounts) {
        final fEq = (first.netSuccessPercent / 100.0) * refQuestions;
        final lEq = (last.netSuccessPercent / 100.0) * refQuestions;
        eqDelta = lEq - fEq;
      } else {
        eqDelta = last.totalNet - first.totalNet;
      }
    }

    final latest = filtered.isNotEmpty ? filtered.last : _myTrials.last;
    final wrongRatio = (latest.totalCorrect + latest.totalWrong) > 0
        ? latest.totalWrong / (latest.totalCorrect + latest.totalWrong)
        : 0.0;
    final strategyNote = wrongRatio > 0.22
        ? '⚠️ Dikkat: Son sınavda yanlış oranın yüksek (%${(wrongRatio * 100).toStringAsFixed(0)}). Emin olmadığın iki şık arasında kaldığında boş bırakma disiplinini artırman netini hızla yükseltir!'
        : (latest.totalEmpty > (latest.effectiveQuestions * 0.25)
              ? '💡 Strateji Notu: Son sınavda ${latest.totalEmpty} boş sorunun var. Eksik konularını tamamlayarak boş sayısını azaltmak en büyük puan sıçramanı sağlayacak.'
              : '✅ Harika Denge: Doğru/yanlış disiplinin çok sağlıklı! Mevcut hızını koruyup branş bazlı eksik kazanımlara odaklanabilirsin.');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text('Genel Denemeler (${fullList.length})'),
              selected: _coachExamMode == 0,
              onSelected: (_) => setState(() => _coachExamMode = 0),
            ),
            if (branchList.isNotEmpty)
              ChoiceChip(
                label: Text('Tarama / Branş (${branchList.length})'),
                selected: _coachExamMode == 1,
                onSelected: (_) => setState(() => _coachExamMode = 1),
              ),
            if (fullList.isNotEmpty && branchList.isNotEmpty)
              ChoiceChip(
                label: Text('Tümü (${_myTrials.length})'),
                selected: _coachExamMode == 2,
                onSelected: (_) => setState(() => _coachExamMode = 2),
              ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, c) {
            final isMobile = c.maxWidth < 768;
            final cols = isMobile ? 2 : 4;
            final gap = 12.0;
            final itemW = (c.maxWidth - gap * (cols - 1)) / cols;
            final kpis = [
              (
                title: 'Katıldığım Deneme',
                val: '${filtered.length} Sınav',
                color: const Color(0xFF4F46E5),
                icon: Icons.assignment_turned_in_rounded,
              ),
              (
                title: 'Kişisel Net Rekorum',
                val: '${bestNet.toStringAsFixed(2)} Net',
                color: const Color(0xFF059669),
                icon: Icons.emoji_events_rounded,
              ),
              (
                title: 'En Yüksek Puanım',
                val: bestScore > 0 ? bestScore.toStringAsFixed(1) : '-',
                color: const Color(0xFF0284C7),
                icon: Icons.workspace_premium_rounded,
              ),
              (
                title: hasMixedQuestionCounts
                    ? 'Eşdeğer Net Trendi'
                    : 'Net Gelişim Trendi',
                val:
                    '${eqDelta >= 0 ? "+" : ""}${eqDelta.toStringAsFixed(2)} Net',
                color: eqDelta >= 0
                    ? const Color(0xFF059669)
                    : const Color(0xFFDC2626),
                icon: eqDelta >= 0
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
              ),
            ];
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: kpis
                  .map(
                    (k) => SizedBox(
                      width: itemW,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(k.icon, color: k.color, size: 22),
                            const SizedBox(height: 8),
                            Text(
                              k.val,
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: k.color,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              k.title,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFC7D2FE)),
          ),
          child: Text(
            strategyNote,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF312E81),
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (filtered.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasMixedQuestionCounts
                      ? 'Sınav Başarı & Eşdeğer Net Grafiğim (Farklı Soru Sayılarına Göre Dengelenmiş)'
                      : 'Deneme Net Gelişim Grafiğim',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 170,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(filtered.length, (i) {
                      final item = filtered[i];
                      final ratio = (item.netSuccessPercent / 100.0).clamp(
                        0.08,
                        1.0,
                      );
                      final isHovered = _hoveredTrendIdx == i;
                      return Expanded(
                        child: MouseRegion(
                          onEnter: (_) => setState(() => _hoveredTrendIdx = i),
                          onExit: (_) =>
                              setState(() => _hoveredTrendIdx = null),
                          child: GestureDetector(
                            onTap: () => setState(() => _hoveredTrendIdx = i),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    '${item.totalNet.toStringAsFixed(1)}N',
                                    style: GoogleFonts.inter(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF312E81),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 220),
                                    height: 110 * ratio,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: isHovered
                                            ? [
                                                const Color(0xFF059669),
                                                const Color(0xFF10B981),
                                              ]
                                            : [
                                                const Color(0xFF4F46E5),
                                                const Color(0xFF6366F1),
                                              ],
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    DateFormat('dd.MM').format(item.date),
                                    style: GoogleFonts.inter(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                if (_hoveredTrendIdx != null &&
                    _hoveredTrendIdx! < filtered.length) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      '📌 ${filtered[_hoveredTrendIdx!].examName} (${filtered[_hoveredTrendIdx!].effectiveQuestions} Soru)  •  '
                      '${filtered[_hoveredTrendIdx!].totalNet.toStringAsFixed(2)} Net  •  '
                      'Başarı: %${filtered[_hoveredTrendIdx!].netSuccessPercent.toStringAsFixed(1)}  •  '
                      '${filtered[_hoveredTrendIdx!].totalCorrect}D / ${filtered[_hoveredTrendIdx!].totalWrong}Y / ${filtered[_hoveredTrendIdx!].totalEmpty}B',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 16),
        ...filtered.reversed.map(
          (t) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: t.isFullTrial
                        ? const Color(0xFFEEF2FF)
                        : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    DateFormat('dd.MM.yyyy').format(t.date),
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: t.isFullTrial
                          ? const Color(0xFF4338CA)
                          : const Color(0xFFB45309),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.examName,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${t.isFullTrial ? "Genel Deneme" : "Tarama / Branş"} (${t.effectiveQuestions} Soru)  •  ${t.totalCorrect} D / ${t.totalWrong} Y / ${t.totalEmpty} B',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${t.totalNet.toStringAsFixed(2)} Net',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                        color: const Color(0xFF059669),
                      ),
                    ),
                    if (t.score > 0)
                      Text(
                        '${t.score.toStringAsFixed(1)} Puan',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF4F46E5),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────── 2. BRANŞ & KAZANIM EKSİK KARNEM ──────────────────────

  Widget _buildOutcomeCardView() {
    final subjectAgg = <String, ({int c, int w, int e, Set<String> topics})>{};
    for (final t in _myTrials) {
      t.subjects.forEach((name, st) {
        final prev = subjectAgg[name] ?? (c: 0, w: 0, e: 0, topics: <String>{});
        subjectAgg[name] = (
          c: prev.c + st.correct,
          w: prev.w + st.wrong,
          e: prev.e + st.empty,
          topics: {...prev.topics, ...st.weakTopics},
        );
      });
    }

    if (subjectAgg.isEmpty) {
      return _buildEmptyCard(
        icon: Icons.radar_rounded,
        title: 'Branş & Kazanım Verisi Henüz Oluşmadı',
        subtitle:
            'Optik veya online deneme sınavlarına katıldığında branş bazlı doğruluk oranların ve öncelikli etüt konuların burada listelenir.',
      );
    }

    final sorted = subjectAgg.entries.toList()
      ..sort((a, b) {
        final totA = a.value.c + a.value.w + a.value.e;
        final totB = b.value.c + b.value.w + b.value.e;
        final rA = totA > 0 ? a.value.c / totA : 0.0;
        final rB = totB > 0 ? b.value.c / totB : 0.0;
        return rA.compareTo(rB); // Önce en zayıf dersler görünsün
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.tips_and_updates_rounded,
                color: Color(0xFF0D9488),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Derslerin en çok desteğe ihtiyaç duyduğundan en güçlüye doğru sıralanmıştır. Başarı oranı %65 altındaki dersler için doğrudan etüt talep edebilirsin.',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...sorted.map((entry) {
          final tot = entry.value.c + entry.value.w + entry.value.e;
          final pct = tot > 0 ? (entry.value.c / tot) * 100 : 0.0;
          final color = pct < 55
              ? const Color(0xFFDC2626)
              : (pct < 75 ? const Color(0xFFD97706) : const Color(0xFF059669));
          final statusText = pct < 55
              ? 'Öncelikli Takviye Önerilir'
              : (pct < 75 ? 'Geliştirilebilir Düzey' : 'Güçlü Branş');
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.key,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '%${pct.toStringAsFixed(1)} • $statusText',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: (pct / 100).clamp(0.0, 1.0),
                    minHeight: 9,
                    backgroundColor: const Color(0xFFF1F5F9),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Toplam $tot Soru  •  ${entry.value.c} Doğru  •  ${entry.value.w} Yanlış  •  ${entry.value.e} Boş',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ),
                    if (pct < 70)
                      TextButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StudentEtutStatsScreen(
                                institutionId: widget.institutionId,
                                studentId: widget.studentId,
                                studentName: _studentName,
                                classId: _classId,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.school_rounded, size: 16),
                        label: const Text('Etüt Talep Et'),
                      ),
                  ],
                ),
                if (entry.value.topics.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: entry.value.topics
                        .take(5)
                        .map(
                          (topic) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              topic,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF991B1B),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  // ─────────────────── 3. YAZILI & TAKDİR / TEŞEKKÜR HESAPLAYICI ─────────────

  Widget _buildGpaCalculatorView() {
    double weightedSum = 0;
    double totalHours = 0;
    bool hasFailingCourse = false;

    for (final c in _courseEntries) {
      final avg = c.average;
      if (avg != null) {
        weightedSum += avg * c.weeklyHours;
        totalHours += c.weeklyHours;
        if (avg < 50) hasFailingCourse = true;
      }
    }

    final gpa = totalHours > 0 ? weightedSum / totalHours : 0.0;
    String certificateLabel = 'Notlarını girerek belge durumunu simüle et';
    Color certColor = const Color(0xFF475569);
    if (totalHours > 0) {
      if (hasFailingCourse) {
        certificateLabel =
            '⚠️ Zayıf (50 altı) ders bulunduğu için belge alınamıyor';
        certColor = const Color(0xFFDC2626);
      } else if (gpa >= 85) {
        certificateLabel = '🏆 TAKDİR BELGESİ Almaya Hak Kazanıyorsun!';
        certColor = const Color(0xFF059669);
      } else if (gpa >= 70) {
        certificateLabel =
            '🎖️ TEŞEKKÜR BELGESİ (Takdir için +${(85 - gpa).toStringAsFixed(2)} puan kaldı)';
        certColor = const Color(0xFF0284C7);
      } else {
        certificateLabel =
            '📘 Teşekkür Belgesi için +${(70 - gpa).toStringAsFixed(2)} puan gerekiyor';
        certColor = const Color(0xFFD97706);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: certColor.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: certColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.workspace_premium_rounded,
                  color: certColor,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      totalHours > 0
                          ? 'Ağırlıklı Dönem Ortalamam: ${gpa.toStringAsFixed(2)}'
                          : 'Ağırlıklı Dönem Ortalaması Simülatörü',
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      certificateLabel,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: certColor,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _courseEntries.add(
                      _CourseGradeEntry(
                        courseName: 'Yeni Ders ${_courseEntries.length + 1}',
                        weeklyHours: 2,
                      ),
                    );
                  });
                },
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const Text('Ders Ekle'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ..._courseEntries.map((entry) {
          final avg = entry.average;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 190,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.courseName,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Haftalık ${entry.weeklyHours.toStringAsFixed(0)} Saat',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                _gradeInputBox('1. Yazılı', entry.exam1Ctrl),
                _gradeInputBox('2. Yazılı', entry.exam2Ctrl),
                _gradeInputBox('1. Perf.', entry.perf1Ctrl),
                _gradeInputBox('2. Perf.', entry.perf2Ctrl),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    avg != null ? 'Ort: ${avg.toStringAsFixed(1)}' : 'Ort: -',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _gradeInputBox(String label, TextEditingController ctrl) {
    return SizedBox(
      width: 82,
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.inter(fontSize: 11),
          isDense: true,
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 46, color: const Color(0xFF94A3B8)),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF64748B),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
