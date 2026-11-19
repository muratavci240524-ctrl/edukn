import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../../../../widgets/edukn_app_bar.dart';
import '../../assessment/evaluation_models.dart';
import 'academic_tracking_models.dart';
import 'academic_ui_widgets.dart';

/// Doğrudan Ölçme Değerlendirme / Raporlar ekranlarından tek tıkla açılabilmesi için yükleyici sarmalayıcı
class ChampionsLeagueLoaderScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final bool isTeacher;
  final List<String>? allowedClassIds;

  const ChampionsLeagueLoaderScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    this.schoolTypeName = '',
    this.isTeacher = false,
    this.allowedClassIds,
  });

  @override
  State<ChampionsLeagueLoaderScreen> createState() =>
      _ChampionsLeagueLoaderScreenState();
}

class _ChampionsLeagueLoaderScreenState
    extends State<ChampionsLeagueLoaderScreen> {
  AcademicDataset? _dataset;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ds = await AcademicTrackingDataService.loadDataset(
      institutionId: widget.institutionId,
      schoolTypeId: widget.schoolTypeId,
      schoolTypeName: widget.schoolTypeName,
      isTeacher: widget.isTeacher,
      allowedClassIds: widget.allowedClassIds,
    );
    if (mounted) {
      setState(() {
        _dataset = ds;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _dataset == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F6FB),
        appBar: EduknAppBar(
          title: 'Şampiyonlar & Zirve Derece Odağı',
          subtitle: widget.schoolTypeName,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return ChampionsLeagueScreen(dataset: _dataset!);
  }
}

class _StudentExamSnapshot {
  final String examId;
  final String examName;
  final DateTime date;
  final double calibratedScore; // 500 ölçeğinde kalibre puan
  final double totalNet;
  final int totalWrong;
  final int totalEmpty;
  final int totalQuestions; // Sınavın gerçek soru kapasitesi (örn. 20 veya 90)
  final bool isFullTrial; // true: Genel Deneme, false: Tarama / Branş Sınavı
  final Map<String, SubjectStats> subjects;

  const _StudentExamSnapshot({
    required this.examId,
    required this.examName,
    required this.date,
    required this.calibratedScore,
    required this.totalNet,
    required this.totalWrong,
    required this.totalEmpty,
    required this.totalQuestions,
    required this.isFullTrial,
    required this.subjects,
  });

  double get netSuccessRate =>
      (totalNet / math.max(1, totalQuestions)).clamp(-0.35, 1.0);
}

class _ChampionCandidate {
  final String key;
  final String studentNo;
  final String name;
  final String branchName;
  final String gradeLevel;
  final int examCount;
  final int referenceQuestions; // Eşdeğer karşılaştırma soru ölçeği (örn. 90)
  final double weightedScore;
  final double projectedScore;
  final double peakScore;
  final double weightedNet; // Referans soru ölçeğinde ağırlıklı eşdeğer net
  final double
  avgQuestionLoss; // Referans soru ölçeğinde deneme başı kaçan soru (yanlış + boş)
  final double
  netTrendDelta; // Soru sayısına göre eşitlenmiş net artış / azalış farkı
  final double scoreStdDev;
  final double estimatedPercentile;
  final int estimatedTurkeyRank;
  final double fullCrownProb; // LGS: 500 Tam Puan (≥498) | YKS: İlk 100 (≥494)
  final double topApexProb; // LGS: İlk %0.1 (≥493) | YKS: İlk 1.000 (≥484)
  final double degreeBandProb; // LGS: İlk %0.5 (≥486) | YKS: İlk 5.000 (≥473)
  final String tierCode; // 'crown' | 'apex' | 'contender' | 'other'
  final String tierLabel;
  final String weakestBranchHint;
  final List<_StudentExamSnapshot> history;

  const _ChampionCandidate({
    required this.key,
    required this.studentNo,
    required this.name,
    required this.branchName,
    required this.gradeLevel,
    required this.examCount,
    required this.referenceQuestions,
    required this.weightedScore,
    required this.projectedScore,
    required this.peakScore,
    required this.weightedNet,
    required this.avgQuestionLoss,
    required this.netTrendDelta,
    required this.scoreStdDev,
    required this.estimatedPercentile,
    required this.estimatedTurkeyRank,
    required this.fullCrownProb,
    required this.topApexProb,
    required this.degreeBandProb,
    required this.tierCode,
    required this.tierLabel,
    required this.weakestBranchHint,
    required this.history,
  });
}

/// ═══════════════════════════════════════════════════════════════════════════
/// DARALTILMIŞ LGS ŞAMPİYONLARI (ORTAOKUL) & YKS ŞAMPİYONLARI (LİSE) STÜDYOSU
/// Yalnızca gerçek Türkiye derecesi / tam puan barajındaki elit aday havuzuna odaklanır.
/// ═══════════════════════════════════════════════════════════════════════════
class ChampionsLeagueScreen extends StatefulWidget {
  final AcademicDataset dataset;

  const ChampionsLeagueScreen({super.key, required this.dataset});

  @override
  State<ChampionsLeagueScreen> createState() => _ChampionsLeagueScreenState();
}

class _ChampionsLeagueScreenState extends State<ChampionsLeagueScreen> {
  late String _examMode; // 'LGS' | 'YKS'
  String _selectedGrade = 'auto';
  String _selectedBranch = 'all';

  /// Havuz daraltma modu:
  /// - 'strict_crown': Sadece Mutlak Şampiyonluk Odağı (≥486 LGS / ≥478 YKS)
  /// - 'elite_pool'  : Dar Derece Havuzu (İlk %1 • ≥472 LGS / ≥460 YKS) [VARSAYILAN]
  /// - 'top15'       : İlk 15 Zirve Takip Listesi
  /// - 'all'         : Tüm Sınava Girenler
  String _scopeMode = 'elite_pool';
  int _minExamCount = 1;
  bool _includeScreeningExams =
      false; // Varsayılan: 20 soruluk Tarama/Branş sınavlarını Genel Denemelerden ayırır
  String _sortBy = 'prob'; // 'prob' | 'avg' | 'peak' | 'loss'
  String _search = '';

  @override
  void initState() {
    super.initState();
    if (widget.dataset.schoolStage == 'lise') {
      _examMode = 'YKS';
    } else if (widget.dataset.schoolStage == 'ortaokul') {
      _examMode = 'LGS';
    } else {
      final hasHighExams = widget.dataset.trialExams.any((e) {
        final lv = _extractGrade(
          e.classLevel.isNotEmpty ? e.classLevel : e.name,
        );
        return {'9', '10', '11', '12'}.contains(lv);
      });
      final hasMidExams = widget.dataset.trialExams.any((e) {
        final lv = _extractGrade(
          e.classLevel.isNotEmpty ? e.classLevel : e.name,
        );
        return {'5', '6', '7', '8'}.contains(lv);
      });
      _examMode = (hasHighExams && !hasMidExams) ? 'YKS' : 'LGS';
    }
    _initDefaultGrade();
  }

  void _initDefaultGrade() {
    final targetGrades = _examMode == 'LGS'
        ? const ['8', '7', '6', '5']
        : const ['12', '11', '10', '9'];
    final primaryGrade = _examMode == 'LGS' ? '8' : '12';

    final availableGrades = <String>{};
    for (final ex in widget.dataset.trialExams) {
      final g = _extractGrade(
        ex.classLevel.isNotEmpty ? ex.classLevel : ex.name,
      );
      if (targetGrades.contains(g) && ex.results.isNotEmpty) {
        availableGrades.add(g);
      }
    }

    if (availableGrades.contains(primaryGrade)) {
      _selectedGrade = primaryGrade;
    } else if (availableGrades.isNotEmpty) {
      _selectedGrade = targetGrades.firstWhere(
        availableGrades.contains,
        orElse: () => primaryGrade,
      );
    } else {
      _selectedGrade = primaryGrade;
    }
    _selectedBranch = 'all';
  }

  static String _extractGrade(String raw) {
    final lower = AcademicTrackingDataService.normTr(raw);
    if (lower.contains('mezun')) return '12';
    final m = RegExp(r'(\d{1,2})').firstMatch(raw.trim());
    return m != null ? m.group(1)! : '';
  }

  bool get _isLgs => _examMode == 'LGS';

  String get _championshipTitle =>
      _isLgs ? 'LGS ŞAMPİYONLARI' : 'YKS ŞAMPİYONLARI';

  String get _prob1ShortLabel =>
      _isLgs ? '500 Tam Puan (0Y)' : 'Türkiye İlk 100';

  String get _prob2ShortLabel =>
      _isLgs ? 'İlk %0.1 (≥493p)' : 'Türkiye İlk 1.000';

  String get _prob3ShortLabel =>
      _isLgs ? 'İlk %0.5 (≥486p)' : 'Türkiye İlk 5.000';

  double get _strictBarScore => _isLgs ? 486.0 : 478.0;
  double get _elitePoolBarScore => _isLgs ? 472.0 : 460.0;

  List<String> get _gradeOptions =>
      _isLgs ? const ['8', '7', '6', '5'] : const ['12', '11', '10', '9'];

  /// Deneme sonucundan 500 tam puan ölçeğinde kalibre edilmiş puan üretir.
  /// Sınavın gerçek soru kapasitesini (`examCapacity`) dikkate alır; örn. 90 soruluk bir
  /// sınavda öğrenci sadece 20 soru işaretlemişse payda 90 kalır, 20 soruluk bir Tarama sınavında ise payda 20 olur.
  double _calibrateExamScore(
    StudentResult sr, {
    required int examCapacity,
    required bool isFullTrial,
  }) {
    final studentMarkedQ = sr.total.correct + sr.total.wrong + sr.total.empty;
    final effectiveExamQ = examCapacity > 0
        ? math.max(examCapacity, studentMarkedQ)
        : (studentMarkedQ > 0 ? studentMarkedQ : (_isLgs ? 90 : 120));
    final net = sr.total.net;

    if (_isLgs) {
      if (isFullTrial && sr.score >= 190.0 && sr.score <= 500.0) {
        return sr.score;
      }
      // Tam denemede öğrencinin hiç işaretlemediği dersler varsa sınavın toplam soru sayısına sadık kal
      if (sr.subjects.isNotEmpty && studentMarkedQ >= effectiveExamQ - 2) {
        double mainNet = 0, mainMax = 0, subNet = 0, subMax = 0;
        sr.subjects.forEach((subjName, st) {
          final sn = AcademicTrackingDataService.normTr(subjName);
          final qCount = math.max(1, st.correct + st.wrong + st.empty);
          if (sn.contains('turk') || sn.contains('mat') || sn.contains('fen')) {
            mainNet += st.net;
            mainMax += qCount;
          } else {
            subNet += st.net;
            subMax += qCount;
          }
        });
        final denom = (mainMax * 4.0) + (subMax * 1.0);
        if (denom > 0) {
          final w =
              (mainNet.clamp(0, mainMax) * 4.0) +
              (subNet.clamp(0, subMax) * 1.0);
          final rawCal = (194.75 + (w / denom) * 305.25).clamp(194.75, 500.0);
          // Tek branş 20 soruluk tarama sınavında 20/20 yapmak tek başına tam 500 LGS şampiyonluk puanı sayılmaz
          return isFullTrial ? rawCal : math.min(rawCal, 492.0);
        }
      }
      if (isFullTrial && sr.score > 0 && sr.score <= 100.0) {
        return (194.75 + (sr.score / 100.0) * 305.25).clamp(194.75, 500.0);
      }
      final maxQ = effectiveExamQ.toDouble();
      final rawCal = (194.75 + (net.clamp(0.0, maxQ) / maxQ) * 305.25).clamp(
        194.75,
        500.0,
      );
      return isFullTrial ? rawCal : math.min(rawCal, 492.0);
    } else {
      if (isFullTrial && sr.score >= 120.0 && sr.score <= 560.0) {
        return sr.score.clamp(120.0, 500.0);
      }
      if (isFullTrial && sr.score > 0 && sr.score <= 100.0) {
        return (120.0 + (sr.score / 100.0) * 380.0).clamp(120.0, 500.0);
      }
      final maxQ = effectiveExamQ.toDouble();
      final rawCal = (120.0 + (net.clamp(0.0, maxQ) / maxQ) * 380.0).clamp(
        120.0,
        500.0,
      );
      return isFullTrial ? rawCal : math.min(rawCal, 486.0);
    }
  }

  ({
    List<_ChampionCandidate> allCandidates,
    int analyzedExamCount,
    int fullExamCount,
    int screeningExamCount,
    bool autoFallbackToScreening,
    List<String> branches,
  })
  _computeCandidates() {
    final ds = widget.dataset;
    final allowedModeGrades = _gradeOptions.toSet();

    final stById = {for (final s in ds.students) s.id: s};
    final stByNo = {
      for (final s in ds.students)
        if (s.studentNo.isNotEmpty) s.studentNo: s,
    };
    final stByTc = {
      for (final s in ds.students)
        if (s.tcNo.isNotEmpty) s.tcNo: s,
    };
    final stByName = {
      for (final s in ds.students)
        if (s.name.isNotEmpty) AcademicTrackingDataService.normTr(s.name): s,
    };

    final chronologicalExams = [...ds.trialExams]
      ..sort((a, b) => a.date.compareTo(b.date));

    // Önce kademeye uyan sınavları Genel Deneme (örn. 90S) ve Tarama/Branş Sınavı (örn. 20S) olarak sınıflandır
    final eligibleExams =
        <({ParsedTrialExam exam, int capacity, bool isFullTrial})>[];
    int fullExamCount = 0;
    int screeningExamCount = 0;

    for (final ex in chronologicalExams) {
      final exGrade = _extractGrade(
        ex.classLevel.isNotEmpty ? ex.classLevel : ex.name,
      );
      if (exGrade.isNotEmpty && !allowedModeGrades.contains(exGrade)) {
        continue;
      }
      if (_selectedGrade != 'all' &&
          exGrade.isNotEmpty &&
          exGrade != _selectedGrade) {
        continue;
      }
      if (ex.results.isEmpty) continue;

      final cap = ex.totalQuestionCapacity;
      final isFull = ex.isFullTrialExam;
      eligibleExams.add((exam: ex, capacity: cap, isFullTrial: isFull));
      if (isFull) {
        fullExamCount++;
      } else {
        screeningExamCount++;
      }
    }

    // Kademede en az 1 Genel Deneme varsa varsayılan olarak 20 soruluk Tarama sınavlarını ayır;
    // hiç Genel Deneme yoksa ekran boş kalmasın diye Tarama sınavlarını otomatik devreye al
    final autoFallbackToScreening =
        !_includeScreeningExams && fullExamCount == 0 && screeningExamCount > 0;
    final useScreening = _includeScreeningExams || autoFallbackToScreening;

    // Standart referans soru ölçeğini belirle (örn. LGS 8. sınıf = 90, 5-7. sınıf kurumsal = 75/90, YKS = 120)
    final fullQuestionFreq = <int, int>{};
    final anyQuestionFreq = <int, int>{};
    for (final item in eligibleExams) {
      if (item.capacity <= 0) continue;
      anyQuestionFreq[item.capacity] =
          (anyQuestionFreq[item.capacity] ?? 0) + 1;
      if (item.isFullTrial) {
        fullQuestionFreq[item.capacity] =
            (fullQuestionFreq[item.capacity] ?? 0) + 1;
      }
    }
    int referenceQuestions = _isLgs ? 90 : 120;
    if (fullQuestionFreq.isNotEmpty) {
      final sortedQ = fullQuestionFreq.entries.toList()
        ..sort((a, b) {
          final c = b.value.compareTo(a.value);
          return c != 0 ? c : b.key.compareTo(a.key);
        });
      referenceQuestions = sortedQ.first.key;
    } else if (anyQuestionFreq.isNotEmpty) {
      final sortedQ = anyQuestionFreq.entries.toList()
        ..sort((a, b) {
          final c = b.value.compareTo(a.value);
          return c != 0 ? c : b.key.compareTo(a.key);
        });
      referenceQuestions = sortedQ.first.key;
    }

    final grouped =
        <
          String,
          ({
            String studentNo,
            String name,
            String branch,
            String grade,
            List<_StudentExamSnapshot> exams,
          })
        >{};

    int analyzedExams = 0;

    for (final item in eligibleExams) {
      if (!item.isFullTrial && !useScreening) continue;
      final ex = item.exam;
      final exGrade = _extractGrade(
        ex.classLevel.isNotEmpty ? ex.classLevel : ex.name,
      );

      bool examUsed = false;
      for (final sr in ex.results) {
        AcademicStudentInfo? matched = sr.systemStudentId != null
            ? stById[sr.systemStudentId!]
            : null;
        matched ??= sr.tcNo.trim().isNotEmpty ? stByTc[sr.tcNo.trim()] : null;
        matched ??= sr.studentNo.trim().isNotEmpty
            ? stByNo[sr.studentNo.trim()]
            : null;
        matched ??= stByName[AcademicTrackingDataService.normTr(sr.name)];

        final branchName = (matched?.className.isNotEmpty == true)
            ? matched!.className
            : (sr.branch.trim().isNotEmpty ? sr.branch.trim() : 'Genel');
        final stGrade = (matched?.classLevel.isNotEmpty == true)
            ? _extractGrade(matched!.classLevel)
            : (exGrade.isNotEmpty ? exGrade : _extractGrade(branchName));

        if (stGrade.isNotEmpty && !allowedModeGrades.contains(stGrade)) {
          continue;
        }
        if (_selectedGrade != 'all' &&
            stGrade.isNotEmpty &&
            stGrade != _selectedGrade) {
          continue;
        }

        final studentMarkedQ =
            sr.total.correct + sr.total.wrong + sr.total.empty;
        if (sr.score <= 0 && sr.total.net <= 0 && studentMarkedQ == 0) continue;

        final effectiveExamQ = item.capacity > 0
            ? math.max(item.capacity, studentMarkedQ)
            : (studentMarkedQ > 0 ? studentMarkedQ : referenceQuestions);
        // Tam denemede kodlanmamış dersler varsa eksik soruları boş sayısına yansıt
        final unrecordedEmpty = math.max(0, effectiveExamQ - studentMarkedQ);

        final uniqueKey =
            matched?.id ??
            (sr.tcNo.trim().isNotEmpty
                ? 'tc_${sr.tcNo.trim()}'
                : (sr.studentNo.trim().isNotEmpty
                      ? 'no_${sr.studentNo.trim()}_$branchName'
                      : 'nm_${AcademicTrackingDataService.normTr(sr.name)}_$branchName'));

        final dispName = (matched?.name.isNotEmpty == true)
            ? matched!.name
            : (sr.name.trim().isNotEmpty ? sr.name.trim() : 'Öğrenci');
        final dispNo = (matched?.studentNo.isNotEmpty == true)
            ? matched!.studentNo
            : sr.studentNo.trim();

        final calScore = _calibrateExamScore(
          sr,
          examCapacity: effectiveExamQ,
          isFullTrial: item.isFullTrial,
        );
        examUsed = true;

        final entry = grouped.putIfAbsent(
          uniqueKey,
          () => (
            studentNo: dispNo,
            name: dispName,
            branch: branchName,
            grade: stGrade.isNotEmpty ? stGrade : (_isLgs ? '8' : '12'),
            exams: <_StudentExamSnapshot>[],
          ),
        );
        entry.exams.add(
          _StudentExamSnapshot(
            examId: ex.id,
            examName: ex.name,
            date: ex.date,
            calibratedScore: calScore,
            totalNet: sr.total.net,
            totalWrong: sr.total.wrong,
            totalEmpty: sr.total.empty + unrecordedEmpty,
            totalQuestions: effectiveExamQ,
            isFullTrial: item.isFullTrial,
            subjects: sr.subjects,
          ),
        );
      }
      if (examUsed) analyzedExams++;
    }

    final candidates = <_ChampionCandidate>[];
    final branchSet = <String>{};

    // Daraltılmış gerçek Türkiye Şampiyonluk & Zirve Derece eşikleri (500 tam puan ölçeği)
    final double fullCrownThreshold = _isLgs ? 498.0 : 494.0;
    final double topApexThreshold = _isLgs ? 493.0 : 484.0;
    final double degreeBandThreshold = _isLgs ? 486.0 : 473.0;

    grouped.forEach((key, bundle) {
      final hist = bundle.exams;
      if (hist.isEmpty) return;
      if (bundle.branch.isNotEmpty) branchSet.add(bundle.branch);

      final fullHist = hist.where((h) => h.isFullTrial).toList();
      final hasFullTrials = fullHist.isNotEmpty;

      double wScoreSum = 0;
      double wEqNetSum = 0;
      double wEqLossSum = 0;
      double wTotal = 0;
      double peakScore = 0;

      for (int i = 0; i < hist.length; i++) {
        final h = hist[i];
        final recency = 1.0 + (i * 0.22);
        // Soru sayısına göre ağırlık: 20 soruluk Tarama sınavı, 90 soruluk LGS denemesinin ~%8-22 ağırlığını alır
        final qFactor =
            (h.totalQuestions / math.max(1, referenceQuestions)).clamp(
              0.18,
              1.15,
            );
        final typeFactor = h.isFullTrial ? 1.0 : 0.40;
        final weight = recency * qFactor * typeFactor;

        // Farklı soru sayılı sınavları referans soru ölçeğine (örn. 90 soruya) eşitle
        final eqNet = h.netSuccessRate * referenceQuestions;
        final eqLoss =
            ((h.totalWrong + h.totalEmpty) / math.max(1, h.totalQuestions)) *
            referenceQuestions;

        wScoreSum += h.calibratedScore * weight;
        wEqNetSum += eqNet * weight;
        wEqLossSum += eqLoss * weight;
        wTotal += weight;

        // Rekor puanı belirlerken öğrencinin Genel Denemesi varsa yalnızca Genel Denemeleri baz al
        if ((!hasFullTrials || h.isFullTrial) &&
            h.calibratedScore > peakScore) {
          peakScore = h.calibratedScore;
        }
      }

      final weightedScore = wScoreSum / wTotal;
      final weightedNet = wEqNetSum / wTotal;
      final avgLoss = wEqLossSum / wTotal;

      // Net Artış / Azalış (netTrendDelta):
      // Asla 20 soruluk Tarama neti ile 90 soruluk Genel Deneme neti ham olarak çıkarılmaz!
      // Öncelikle varsa Genel Denemeler kendi aralarında karşılaştırılır; soru sayıları farklıysa
      // her sınav referans soru ölçeğine (`eqNet`) eşitlendikten sonra fark alınır.
      double netDelta = 0;
      final trendSeries = fullHist.length >= 2 ? fullHist : hist;
      if (trendSeries.length >= 2) {
        final mid = trendSeries.length ~/ 2;
        final firstAvg =
            trendSeries
                .sublist(0, mid)
                .fold<double>(
                  0,
                  (a, b) => a + (b.netSuccessRate * referenceQuestions),
                ) /
            mid;
        final secondAvg =
            trendSeries
                .sublist(mid)
                .fold<double>(
                  0,
                  (a, b) => a + (b.netSuccessRate * referenceQuestions),
                ) /
            (trendSeries.length - mid);
        netDelta = secondAvg - firstAvg;
      }

      // Daraltılmış gerçekçi standart sapma (şişirilmiş olasılıkları önler)
      final stdSeries = fullHist.length >= 2 ? fullHist : hist;
      double empiricalVar = 0;
      if (stdSeries.length >= 2) {
        for (final h in stdSeries) {
          empiricalVar += math.pow(h.calibratedScore - weightedScore, 2);
        }
        empiricalVar /= (stdSeries.length - 1);
      }
      final empiricalStd = math.sqrt(empiricalVar);
      const priorStd = 8.2;
      final effectiveStd = stdSeries.length == 1
          ? priorStd
          : (((empiricalStd * (stdSeries.length - 1)) + (priorStd * 1.4)) /
                    (stdSeries.length + 0.4))
                .clamp(4.2, 12.5);

      // İvme bonusu 90/120 soru ölçeğine göre normalize edilir (örn. 20 soruluk ölçekte de orantılı kalır)
      final normalizedDeltaOn90 =
          netDelta * (90.0 / math.max(1, referenceQuestions));
      final trendScoreBonus =
          (normalizedDeltaOn90 * (_isLgs ? 0.85 : 0.70)).clamp(-4.0, 4.5);
      final projectedScore =
          ((weightedScore * 0.85) + (peakScore * 0.15) + trendScoreBonus).clamp(
            _isLgs ? 194.75 : 120.0,
            500.0,
          );

      final crownProb = AcademicScoreEngine.normalSurvivalProbability(
        mean: projectedScore,
        stdDev: effectiveStd,
        threshold: fullCrownThreshold,
      );
      final apexProb = AcademicScoreEngine.normalSurvivalProbability(
        mean: projectedScore,
        stdDev: effectiveStd,
        threshold: topApexThreshold,
      );
      final degreeProb = AcademicScoreEngine.normalSurvivalProbability(
        mean: projectedScore,
        stdDev: effectiveStd,
        threshold: degreeBandThreshold,
      );

      double estPct;
      int estRank;
      if (_isLgs) {
        estPct = AcademicScoreEngine.lgsPercentileFromScore(projectedScore);
        estRank = math.max(1, ((estPct / 100.0) * 994358).round());
      } else {
        final yksEst = AcademicScoreEngine.yksPercentileFromScore(
          projectedScore,
        );
        estPct = yksEst.percentile;
        estRank = yksEst.estimatedRank;
      }

      String tierCode;
      String tierLabel;
      if (projectedScore >= (_isLgs ? 491.0 : 484.0) ||
          (peakScore >= (_isLgs ? 496.5 : 491.0) &&
              weightedScore >= (_isLgs ? 485.0 : 476.0))) {
        tierCode = 'crown';
        tierLabel = _isLgs
            ? 'Mutlak Şampiyon Adayı (Tam Puan Odağı)'
            : 'Türkiye İlk 100 / Şampiyon Adayı';
      } else if (projectedScore >= _strictBarScore) {
        tierCode = 'apex';
        tierLabel = _isLgs
            ? 'Türkiye Zirve Derece (%0.1 – %0.4)'
            : 'Türkiye İlk 1.000 – 3.000 Derece Adayı';
      } else if (projectedScore >= _elitePoolBarScore ||
          peakScore >= (_isLgs ? 484.0 : 472.0)) {
        tierCode = 'contender';
        tierLabel = _isLgs
            ? 'İlk %1 Yakın Derece Takibi'
            : 'İlk 5.000 – 10.000 Derece Takibi';
      } else {
        tierCode = 'other';
        tierLabel = 'Derece Barajı Altı';
      }

      final branchLoss = <String, ({double lostQ, int count})>{};
      for (final h in hist) {
        h.subjects.forEach((subj, st) {
          final lost = st.wrong * 1.33 + st.empty;
          final prev = branchLoss[subj] ?? (lostQ: 0.0, count: 0);
          branchLoss[subj] = (lostQ: prev.lostQ + lost, count: prev.count + 1);
        });
      }
      String weakestHint = 'Sıfır hata disiplini ve süre kontrolü korunmalı';
      if (branchLoss.isNotEmpty) {
        final sortedLoss = branchLoss.entries.toList()
          ..sort(
            (a, b) => (b.value.lostQ / b.value.count).compareTo(
              a.value.lostQ / a.value.count,
            ),
          );
        final topLoss = sortedLoss.first;
        final avgBrLost = topLoss.value.lostQ / topLoss.value.count;
        if (avgBrLost >= 0.6) {
          weakestHint =
              '${topLoss.key} branşındaki ort. ${avgBrLost.toStringAsFixed(1)} net kaybı sıfırlanırsa tam puan / zirve kapısı açılır';
        }
      }

      candidates.add(
        _ChampionCandidate(
          key: key,
          studentNo: bundle.studentNo,
          name: bundle.name,
          branchName: bundle.branch,
          gradeLevel: bundle.grade,
          examCount: hist.length,
          referenceQuestions: referenceQuestions,
          weightedScore: weightedScore,
          projectedScore: projectedScore,
          peakScore: peakScore,
          weightedNet: weightedNet,
          avgQuestionLoss: avgLoss,
          netTrendDelta: netDelta,
          scoreStdDev: effectiveStd,
          estimatedPercentile: estPct,
          estimatedTurkeyRank: estRank,
          fullCrownProb: crownProb,
          topApexProb: apexProb,
          degreeBandProb: degreeProb,
          tierCode: tierCode,
          tierLabel: tierLabel,
          weakestBranchHint: weakestHint,
          history: hist,
        ),
      );
    });

    candidates.sort((a, b) {
      final p = b.projectedScore.compareTo(a.projectedScore);
      if (p != 0) return p;
      return b.peakScore.compareTo(a.peakScore);
    });

    final sortedBranches = branchSet.toList()..sort();
    return (
      allCandidates: candidates,
      analyzedExamCount: analyzedExams,
      fullExamCount: fullExamCount,
      screeningExamCount: screeningExamCount,
      autoFallbackToScreening: autoFallbackToScreening,
      branches: sortedBranches,
    );
  }

  ({List<_ChampionCandidate> visible, bool usedTopFallback}) _applyFilters(
    List<_ChampionCandidate> all,
  ) {
    final q = AcademicTrackingDataService.normTr(_search);

    final baseFiltered = all.where((c) {
      if (c.examCount < _minExamCount) return false;
      if (_selectedBranch != 'all' && c.branchName != _selectedBranch) {
        return false;
      }
      if (q.isNotEmpty) {
        final hay = AcademicTrackingDataService.normTr(
          '${c.name} ${c.studentNo} ${c.branchName} ${c.tierLabel}',
        );
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();

    bool usedFallback = false;
    List<_ChampionCandidate> scoped;

    if (q.isNotEmpty) {
      // Kullanıcı doğrudan isimle arama yapıyorsa aradığı öğrenciyi gizleme
      scoped = baseFiltered;
    } else if (_scopeMode == 'strict_crown') {
      scoped = baseFiltered
          .where((c) => c.tierCode == 'crown' || c.tierCode == 'apex')
          .toList();
    } else if (_scopeMode == 'elite_pool') {
      scoped = baseFiltered
          .where(
            (c) =>
                c.tierCode == 'crown' ||
                c.tierCode == 'apex' ||
                c.tierCode == 'contender',
          )
          .toList();
      if (scoped.isEmpty && baseFiltered.isNotEmpty) {
        usedFallback = true;
        scoped = baseFiltered.take(5).toList();
      } else if (scoped.length > 15) {
        // Şampiyonluk ekranı geniş kalmasın: dar havuzda en fazla ilk 15 elit adayı göster
        scoped = scoped.take(15).toList();
      }
    } else if (_scopeMode == 'top15') {
      scoped = baseFiltered.take(15).toList();
    } else {
      scoped = baseFiltered;
    }

    scoped.sort((a, b) {
      switch (_sortBy) {
        case 'avg':
          return b.weightedScore.compareTo(a.weightedScore);
        case 'peak':
          return b.peakScore.compareTo(a.peakScore);
        case 'loss':
          return a.avgQuestionLoss.compareTo(b.avgQuestionLoss);
        case 'prob':
        default:
          final c = b.projectedScore.compareTo(a.projectedScore);
          return c != 0 ? c : b.topApexProb.compareTo(a.topApexProb);
      }
    });

    return (visible: scoped, usedTopFallback: usedFallback);
  }

  Future<void> _exportPdf(
    List<_ChampionCandidate> list,
    int analyzedExams,
  ) async {
    final rankFmt = NumberFormat('#,###', 'tr_TR');
    final crownCount = list.where((c) => c.tierCode == 'crown').length;
    final apexCount = list
        .where((c) => c.tierCode == 'crown' || c.tierCode == 'apex')
        .length;
    final termText = widget.dataset.activeTermName.isNotEmpty
        ? ' • Dönem: ${widget.dataset.activeTermName}'
        : '';

    await AcademicTrackingPdfService.printTableReport(
      documentTitle:
          '$_championshipTitle — DARALTILMIŞ ZİRVE & DERECE ADAY RAPORU',
      schoolName: '${widget.dataset.schoolName}$termText',
      subtitle:
          'Aktif dönemdeki $analyzedExams deneme sınavı verisine göre şampiyonluk ve Türkiye derecesi potansiyeli taşıyan elit aday listesi',
      kpis: [
        (label: 'Listelenen Elit Aday', value: '${list.length} Öğrenci'),
        (label: 'Tam Puan / Şampiyon Odağı', value: '$crownCount Öğrenci'),
        (label: 'Türkiye Derece Odağı', value: '$apexCount Öğrenci'),
        (label: 'Deneme Havuzu', value: '$analyzedExams Sınav'),
      ],
      headers: [
        'Sıra',
        'Öğrenci',
        'Şube',
        'Deneme',
        'Ort. / Rekor Puan',
        'Ort. Net (Kayıp)',
        'Tahmini Dilim',
        _prob1ShortLabel,
        _prob2ShortLabel,
        _prob3ShortLabel,
      ],
      rows: List.generate(math.min(60, list.length), (idx) {
        final c = list[idx];
        return [
          '${idx + 1}',
          c.name,
          c.branchName,
          '${c.examCount}',
          '${c.weightedScore.toStringAsFixed(1)} / ${c.peakScore.toStringAsFixed(0)}',
          '${c.weightedNet.toStringAsFixed(1)} (-${c.avgQuestionLoss.toStringAsFixed(1)}S)',
          '%${c.estimatedPercentile.toStringAsFixed(2)} (~${rankFmt.format(c.estimatedTurkeyRank)})',
          '%${c.fullCrownProb.toStringAsFixed(1)}',
          '%${c.topApexProb.toStringAsFixed(1)}',
          '%${c.degreeBandProb.toStringAsFixed(1)}',
        ];
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 760;

    final computed = _computeCandidates();
    final allCandidates = computed.allCandidates;
    final filteredBundle = _applyFilters(allCandidates);
    final visible = filteredBundle.visible;

    final crownCount = allCandidates.where((c) => c.tierCode == 'crown').length;
    final apexCount = allCandidates
        .where((c) => c.tierCode == 'crown' || c.tierCode == 'apex')
        .length;
    final elitePoolCount = allCandidates
        .where(
          (c) =>
              c.tierCode == 'crown' ||
              c.tierCode == 'apex' ||
              c.tierCode == 'contender',
        )
        .length;

    final subtitleParts = <String>[
      widget.dataset.schoolName,
      if (widget.dataset.activeTermName.isNotEmpty)
        'Dönem: ${widget.dataset.activeTermName}',
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: EduknAppBar(
        title: '$_championshipTitle • Zirve Derece Odağı',
        subtitle: subtitleParts.join(' • '),
        actions: [
          if (visible.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: FilledButton.icon(
                onPressed: () =>
                    _exportPdf(visible, computed.analyzedExamCount),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB45309),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 17),
                label: Text(
                  isMobile ? 'PDF' : 'Şampiyon Adayları PDF',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.8,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1060),
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 20,
              vertical: isMobile ? 12 : 18,
            ),
            children: [
              _buildCompactHeroBanner(
                isMobile: isMobile,
                totalCount: allCandidates.length,
                analyzedExamCount: computed.analyzedExamCount,
                crownCount: crownCount,
                apexCount: apexCount,
                elitePoolCount: elitePoolCount,
              ),
              const SizedBox(height: 12),
              _buildFilterPanel(
                allCandidates: allCandidates,
                branches: computed.branches,
                crownPlusApexCount: apexCount,
                elitePoolCount: elitePoolCount,
                fullExamCount: computed.fullExamCount,
                screeningExamCount: computed.screeningExamCount,
                autoFallbackToScreening: computed.autoFallbackToScreening,
              ),
              if (filteredBundle.usedTopFallback) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.filter_center_focus_rounded,
                        color: Color(0xFFD97706),
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Seçili kademede henüz ≥${_elitePoolBarScore.toStringAsFixed(0)} puan (İlk %1) barajını aşan öğrenci bulunmadığından liste yalnızca zirveye en yakın ilk ${visible.length} adayla daraltılmıştır.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (visible.isNotEmpty && _scopeMode != 'all') ...[
                _buildTopPodium(
                  visible.take(math.min(3, visible.length)).toList(),
                ),
                const SizedBox(height: 12),
              ],
              if (visible.isEmpty)
                _buildEmptyState(allCandidates.isEmpty)
              else
                _buildCandidateListCard(visible, allCandidates.length),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactHeroBanner({
    required bool isMobile,
    required int totalCount,
    required int analyzedExamCount,
    required int crownCount,
    required int apexCount,
    required int elitePoolCount,
  }) {
    final canSwitchStage = widget.dataset.schoolStage == 'genel';

    return Container(
      padding: EdgeInsets.all(isMobile ? 15 : 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _isLgs
              ? const [Color(0xFF1E1B4B), Color(0xFF312E81), Color(0xFFB45309)]
              : const [Color(0xFF0F172A), Color(0xFF1E3A8A), Color(0xFF7E22CE)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.emoji_events_rounded,
                  color: Color(0xFF1E1B4B),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '$_championshipTitle — DARALTILMIŞ ZİRVE HAVUZU',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 15.5 : 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFBBF24,
                            ).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(
                                0xFFFBBF24,
                              ).withValues(alpha: 0.45),
                            ),
                          ),
                          child: Text(
                            _isLgs
                                ? 'Baraj: ≥486p Derece • ≥498p Şampiyonluk'
                                : 'Baraj: İlk 5.000 • İlk 1.000 • İlk 100',
                            style: GoogleFonts.inter(
                              fontSize: 10.8,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFFDE68A),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _isLgs
                          ? 'Genel öğrenci listesi yerine yalnızca 0–2 yanlış bandındaki gerçek LGS şampiyonluk ve İlk %0.1–%1 Türkiye derecesi adaylarına odaklanır.'
                          : 'Genel sıralama yerine yalnızca Türkiye İlk 100, İlk 1.000 ve İlk 5.000 derece potansiyeli taşıyan elit YKS adaylarına odaklanır.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (canSwitchStage) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _modeSwitchButton(
                  mode: 'LGS',
                  label: 'Ortaokul • LGS Şampiyonları',
                  icon: Icons.workspace_premium_rounded,
                ),
                _modeSwitchButton(
                  mode: 'YKS',
                  label: 'Lise • YKS Şampiyonları',
                  icon: Icons.school_rounded,
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final isTwoByTwo = maxW < 680;
              final gap = maxW < 400 ? 8.0 : 10.0;
              final cardWidth = isTwoByTwo
                  ? (maxW - gap) / 2
                  : (maxW - gap * 3) / 4;

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  _heroStatCard(
                    width: cardWidth,
                    label: _isLgs
                        ? '500 Tam Puan Odağı'
                        : 'Türkiye İlk 100 Odağı',
                    value: '$crownCount Aday',
                    sub: _isLgs
                        ? '≥491 Projeksiyon / Rekor'
                        : 'Mutlak Şampiyonluk',
                    accent: const Color(0xFFFBBF24),
                  ),
                  _heroStatCard(
                    width: cardWidth,
                    label: _isLgs
                        ? 'Türkiye Derece (%0.4)'
                        : 'İlk 1.000–3.000 Odağı',
                    value: '$apexCount Aday',
                    sub: '≥${_strictBarScore.toStringAsFixed(0)} Puan Üstü',
                    accent: const Color(0xFF34D399),
                  ),
                  _heroStatCard(
                    width: cardWidth,
                    label: 'Dar Derece Havuzu',
                    value: '$elitePoolCount Aday',
                    sub: 'Toplam $totalCount Öğrenciden Seçilen',
                    accent: const Color(0xFF38BDF8),
                  ),
                  _heroStatCard(
                    width: cardWidth,
                    label: 'Aktif Dönem Verisi',
                    value: '$analyzedExamCount Deneme',
                    sub: widget.dataset.activeTermName.isNotEmpty
                        ? widget.dataset.activeTermName
                        : 'Mevcut Dönem',
                    accent: const Color(0xFFE2E8F0),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _modeSwitchButton({
    required String mode,
    required String label,
    required IconData icon,
  }) {
    final active = _examMode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        if (_examMode == mode) return;
        setState(() {
          _examMode = mode;
          _scopeMode = 'elite_pool';
          _initDefaultGrade();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFFBBF24)
              : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? const Color(0xFFFBBF24)
                : Colors.white.withValues(alpha: 0.24),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: active ? const Color(0xFF1E1B4B) : Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: active ? const Color(0xFF1E1B4B) : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroStatCard({
    required double width,
    required String label,
    required String value,
    required String sub,
    required Color accent,
  }) {
    final compact = width < 165;
    final valSize = (width * 0.105).clamp(15.0, 18.0);
    return SizedBox(
      width: width,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: compact ? 10.0 : 10.8,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.80),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: valSize,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: compact ? 9.8 : 10.5,
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPanel({
    required List<_ChampionCandidate> allCandidates,
    required List<String> branches,
    required int crownPlusApexCount,
    required int elitePoolCount,
    required int fullExamCount,
    required int screeningExamCount,
    required bool autoFallbackToScreening,
  }) {
    final safeBranch =
        (_selectedBranch == 'all' || branches.contains(_selectedBranch))
        ? _selectedBranch
        : 'all';

    final branchItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'all', child: Text('Tüm Şubeler')),
      ...branches.map(
        (b) => DropdownMenuItem(
          value: b,
          child: Text(b, overflow: TextOverflow.ellipsis),
        ),
      ),
    ];

    const sortItems = <DropdownMenuItem<String>>[
      DropdownMenuItem(
        value: 'prob',
        child: Text(
          'Zirve Projeksiyon & Şampiyonluk İhtimali',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      DropdownMenuItem(
        value: 'avg',
        child: Text(
          'Ağırlıklı Deneme Puanı (Yüksekten Düşüğe)',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      DropdownMenuItem(
        value: 'peak',
        child: Text('En Yüksek Rekor Puan', overflow: TextOverflow.ellipsis),
      ),
      DropdownMenuItem(
        value: 'loss',
        child: Text(
          'En Az Soru Kaybı (0 Hataya En Yakın)',
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Satır: Alan Daraltma (Spesifik Şampiyonluk Kapsamı)
          Wrap(
            spacing: 7,
            runSpacing: 7,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.filter_center_focus_rounded,
                    size: 16,
                    color: Color(0xFFB45309),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Şampiyonluk Odağı:',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              AcademicChoicePill(
                icon: Icons.emoji_events_rounded,
                label:
                    'Mutlak Şampiyon Odağı ≥${_strictBarScore.toStringAsFixed(0)}p ($crownPlusApexCount)',
                selected: _scopeMode == 'strict_crown',
                accentColor: const Color(0xFFD97706),
                compact: true,
                onTap: () => setState(() => _scopeMode = 'strict_crown'),
              ),
              AcademicChoicePill(
                icon: Icons.military_tech_rounded,
                label:
                    'Dar Derece Havuzu ≥${_elitePoolBarScore.toStringAsFixed(0)}p (${math.min(15, elitePoolCount)})',
                selected: _scopeMode == 'elite_pool',
                accentColor: const Color(0xFF059669),
                compact: true,
                onTap: () => setState(() => _scopeMode = 'elite_pool'),
              ),
              AcademicChoicePill(
                icon: Icons.leaderboard_rounded,
                label: 'İlk 15 Zirve Adayı',
                selected: _scopeMode == 'top15',
                accentColor: const Color(0xFF4F46E5),
                compact: true,
                onTap: () => setState(() => _scopeMode = 'top15'),
              ),
              AcademicChoicePill(
                label: 'Tüm Sınava Girenler (${allCandidates.length})',
                selected: _scopeMode == 'all',
                accentColor: const Color(0xFF475569),
                compact: true,
                onTap: () => setState(() => _scopeMode = 'all'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 2. Satır: Kademe + Min. Deneme Filtresi
          Wrap(
            spacing: 7,
            runSpacing: 7,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Kademe:',
                style: GoogleFonts.inter(
                  fontSize: 11.8,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF475569),
                ),
              ),
              ..._gradeOptions.map((g) {
                final isExamYear =
                    (_isLgs && g == '8') || (!_isLgs && g == '12');
                return AcademicChoicePill(
                  label: isExamYear ? '$g. Sınıf ($_examMode)' : '$g. Sınıf',
                  selected: _selectedGrade == g,
                  accentColor: const Color(0xFFB45309),
                  compact: true,
                  onTap: () => setState(() {
                    _selectedGrade = g;
                    _selectedBranch = 'all';
                  }),
                );
              }),
              const SizedBox(width: 8),
              Text(
                'Min. Deneme:',
                style: GoogleFonts.inter(
                  fontSize: 11.8,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF475569),
                ),
              ),
              ...[1, 2, 3].map(
                (cnt) => AcademicChoicePill(
                  label: cnt == 1 ? '≥1 Sınav' : '≥$cnt Sınav',
                  selected: _minExamCount == cnt,
                  accentColor: const Color(0xFF0284C7),
                  compact: true,
                  onTap: () => setState(() => _minExamCount = cnt),
                ),
              ),
              if (screeningExamCount > 0) ...[
                const SizedBox(width: 8),
                Text(
                  'Sınav Türü:',
                  style: GoogleFonts.inter(
                    fontSize: 11.8,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF475569),
                  ),
                ),
                if (fullExamCount > 0)
                  AcademicChoicePill(
                    icon: Icons.assignment_turned_in_rounded,
                    label: 'Genel Denemeler ($fullExamCount)',
                    selected: !_includeScreeningExams,
                    accentColor: const Color(0xFF0F766E),
                    compact: true,
                    onTap: () => setState(() => _includeScreeningExams = false),
                  ),
                AcademicChoicePill(
                  icon: Icons.fact_check_rounded,
                  label:
                      'Tarama / Branş Dahil (${fullExamCount + screeningExamCount})',
                  selected: _includeScreeningExams || autoFallbackToScreening,
                  accentColor: const Color(0xFF7C3AED),
                  compact: true,
                  onTap: fullExamCount == 0
                      ? () {}
                      : () => setState(
                          () =>
                              _includeScreeningExams = !_includeScreeningExams,
                        ),
                ),
              ],
            ],
          ),
          if (screeningExamCount > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.balance_rounded,
                    size: 15,
                    color: Color(0xFF0F766E),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      (_includeScreeningExams || autoFallbackToScreening)
                          ? 'Farklı soru sayılı sınavlar (örn. 20 soruluk Tarama ile 90 soruluk Deneme) kendi soru sayısına bölünerek standart soru ölçeğine eşitlenip karşılaştırılır.'
                          : '$screeningExamCount adet kısa soru sayılı Tarama / Branş sınavı net artış-azalış hesabını bozmaması için Genel Denemelerden ayrıldı.',
                      style: GoogleFonts.inter(
                        fontSize: 11.1,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF475569),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 780) {
                return Column(
                  children: [
                    AcademicDropdownField<String>(
                      label: 'Şube',
                      icon: Icons.class_rounded,
                      accentColor: const Color(0xFFB45309),
                      value: safeBranch,
                      items: branchItems,
                      onChanged: (v) =>
                          setState(() => _selectedBranch = v ?? 'all'),
                    ),
                    const SizedBox(height: 8),
                    AcademicDropdownField<String>(
                      label: 'Sıralama Ölçütü',
                      icon: Icons.sort_rounded,
                      accentColor: const Color(0xFFB45309),
                      value: _sortBy,
                      items: sortItems,
                      onChanged: (v) => setState(() => _sortBy = v ?? 'prob'),
                    ),
                    const SizedBox(height: 8),
                    AcademicSearchField(
                      label: 'Aday Ara',
                      hint: 'Öğrenci adı veya numara ile ara...',
                      accentColor: const Color(0xFFB45309),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    flex: 2,
                    child: AcademicDropdownField<String>(
                      label: 'Şube',
                      icon: Icons.class_rounded,
                      accentColor: const Color(0xFFB45309),
                      value: safeBranch,
                      items: branchItems,
                      onChanged: (v) =>
                          setState(() => _selectedBranch = v ?? 'all'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: AcademicDropdownField<String>(
                      label: 'Sıralama Ölçütü',
                      icon: Icons.sort_rounded,
                      accentColor: const Color(0xFFB45309),
                      value: _sortBy,
                      items: sortItems,
                      onChanged: (v) => setState(() => _sortBy = v ?? 'prob'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: AcademicSearchField(
                      label: 'Aday Ara',
                      hint: 'İsim veya numara (tüm havuzda arar)...',
                      accentColor: const Color(0xFFB45309),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTopPodium(List<_ChampionCandidate> topThree) {
    return Container(
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
              const Icon(
                Icons.workspace_premium_rounded,
                color: Color(0xFFD97706),
                size: 19,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '$_championshipTitle Kürsüsü — Zirveye En Yakın İlk ${topThree.length} Öğrenci',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 760) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(topThree.length, (i) {
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: i < topThree.length - 1 ? 10 : 0,
                        ),
                        child: _buildPodiumCard(topThree[i], i + 1),
                      ),
                    );
                  }),
                );
              }
              return Column(
                children: List.generate(topThree.length, (i) {
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: i < topThree.length - 1 ? 8 : 0,
                    ),
                    child: _buildPodiumCard(topThree[i], i + 1),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPodiumCard(_ChampionCandidate c, int rank) {
    final medalColors = switch (rank) {
      1 => (
        bg: const Color(0xFFFFFBEB),
        border: const Color(0xFFF59E0B),
        badge: const Color(0xFFD97706),
        label: '1. ZİRVE ADAYI',
      ),
      2 => (
        bg: const Color(0xFFF8FAFC),
        border: const Color(0xFF94A3B8),
        badge: const Color(0xFF475569),
        label: '2. ZİRVE ADAYI',
      ),
      _ => (
        bg: const Color(0xFFFFF7ED),
        border: const Color(0xFFEA580C),
        badge: const Color(0xFFC2410C),
        label: '3. ZİRVE ADAYI',
      ),
    };

    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: () => _openCandidateSheet(c, rank),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: medalColors.bg,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: medalColors.border, width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: medalColors.badge,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    medalColors.label,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '%${c.estimatedPercentile.toStringAsFixed(2)} Dilim',
                  style: GoogleFonts.inter(
                    fontSize: 11.2,
                    fontWeight: FontWeight.w800,
                    color: medalColors.badge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${c.branchName} • ${c.examCount} Sınav • Ort. ${c.weightedNet.toStringAsFixed(1)} Net (-${c.avgQuestionLoss.toStringAsFixed(1)} Soru)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11.2,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: _miniStatBox(
                    'Ort. / Rekor Puan',
                    '${c.weightedScore.toStringAsFixed(1)} / ${c.peakScore.toStringAsFixed(0)}',
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: _miniStatBox(
                    _prob1ShortLabel,
                    '%${c.fullCrownProb.toStringAsFixed(1)}',
                    highlight: medalColors.badge,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStatBox(String label, String value, {Color? highlight}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12.8,
              fontWeight: FontWeight.w800,
              color: highlight ?? const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool noExamAtAll) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.emoji_events_outlined,
              size: 32,
              color: Color(0xFFD97706),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            noExamAtAll
                ? 'Seçili kademe ve aktif dönemde değerlendirilmiş deneme sınavı bulunamadı'
                : 'Seçili dar şampiyonluk barajını (≥${_strictBarScore.toStringAsFixed(0)} puan) aşan aday bulunamadı',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            noExamAtAll
                ? 'Aktif dönemde optik deneme sınavı sonuçları yüklendiğinde şampiyonluk adayları otomatik hesaplanır.'
                : 'Yukarıdaki "Dar Derece Havuzu" veya "İlk 15 Zirve Adayı" seçeneğine geçerek baraja en yakın öğrencileri inceleyebilirsiniz.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12.4,
              color: const Color(0xFF64748B),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCandidateListCard(
    List<_ChampionCandidate> list,
    int totalAnalyzed,
  ) {
    final rankFmt = NumberFormat('#,###', 'tr_TR');

    final scopeHeading = switch (_scopeMode) {
      'strict_crown' =>
        'Mutlak Şampiyonluk & Zirve Derece Odağı (${list.length} / $totalAnalyzed Öğrenci)',
      'elite_pool' =>
        'Daraltılmış Şampiyon & Derece Aday Havuzu (${list.length} / $totalAnalyzed Öğrenci)',
      'top15' =>
        'Zirveye En Yakın İlk ${list.length} Aday (Toplam $totalAnalyzed Öğrenciden)',
      _ => 'Tüm Öğrencilerin Derece Olasılık Listesi (${list.length} Öğrenci)',
    };

    return Container(
      padding: const EdgeInsets.all(15),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scopeHeading,
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Öğrenciye tıklayarak aktif dönem deneme geçmişini ve sıfır hata için kapatılması gereken branş kaybını görebilirsiniz.',
                      style: GoogleFonts.inter(
                        fontSize: 11.6,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final c = list[index];
              return _buildCandidateRow(c, index + 1, rankFmt);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCandidateRow(
    _ChampionCandidate c,
    int rank,
    NumberFormat rankFmt,
  ) {
    final tierAccent = switch (c.tierCode) {
      'crown' => const Color(0xFFD97706),
      'apex' => const Color(0xFF059669),
      'contender' => const Color(0xFF4F46E5),
      _ => const Color(0xFF64748B),
    };

    final minTrendStep = (c.referenceQuestions / 90.0).clamp(0.25, 1.35) * 0.5;
    final trendPositive = c.netTrendDelta >= minTrendStep;
    final trendNegative = c.netTrendDelta <= -minTrendStep;

    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: () => _openCandidateSheet(c, rank),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: rank <= 3
              ? tierAccent.withValues(alpha: 0.04)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: rank <= 3
                ? tierAccent.withValues(alpha: 0.35)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 780;

            final identityBlock = Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tierAccent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    '#$rank',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: tierAccent,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: tierAccent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              c.tierLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: tierAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 8,
                        runSpacing: 3,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${c.branchName} • ${c.examCount} Deneme',
                            style: GoogleFonts.inter(
                              fontSize: 11.2,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                          Text(
                            'Ort: ${c.weightedScore.toStringAsFixed(1)}p (${c.weightedNet.toStringAsFixed(1)}/${c.referenceQuestions} Net)',
                            style: GoogleFonts.inter(
                              fontSize: 11.2,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF334155),
                            ),
                          ),
                          Text(
                            'Ort. Kayıp: ${c.avgQuestionLoss.toStringAsFixed(1)} Soru',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: c.avgQuestionLoss <= 2.0
                                  ? const Color(0xFF059669)
                                  : const Color(0xFFB45309),
                            ),
                          ),
                          if (c.examCount >= 2 &&
                              (trendPositive || trendNegative))
                            Text(
                              trendPositive
                                  ? '▲ +${c.netTrendDelta.toStringAsFixed(1)}N'
                                  : '▼ ${c.netTrendDelta.toStringAsFixed(1)}N',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: trendPositive
                                    ? const Color(0xFF059669)
                                    : const Color(0xFFDC2626),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );

            final percentileBadge = Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: wide
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    '%${c.estimatedPercentile.toStringAsFixed(2)} Dilim',
                    style: GoogleFonts.inter(
                      fontSize: 13.2,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    '~${rankFmt.format(c.estimatedTurkeyRank)}. Sıra',
                    style: GoogleFonts.inter(
                      fontSize: 10.4,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            );

            final probabilitiesBlock = Row(
              children: [
                Expanded(
                  child: _probMeter(
                    label: _prob1ShortLabel,
                    percent: c.fullCrownProb,
                    color: const Color(0xFFD97706),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: _probMeter(
                    label: _prob2ShortLabel,
                    percent: c.topApexProb,
                    color: const Color(0xFF059669),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: _probMeter(
                    label: _prob3ShortLabel,
                    percent: c.degreeBandProb,
                    color: const Color(0xFF4F46E5),
                  ),
                ),
              ],
            );

            if (wide) {
              return Row(
                children: [
                  Expanded(flex: 5, child: identityBlock),
                  const SizedBox(width: 10),
                  percentileBadge,
                  const SizedBox(width: 10),
                  Expanded(flex: 6, child: probabilitiesBlock),
                ],
              );
            }

            // Dar mobil ekranlarda 4 kutu (Yüzdelik Dilim + 3 İhtimal Barı) genişliğe göre 2x2 dizilir
            if (constraints.maxWidth < 460) {
              final cellWidth = (constraints.maxWidth - 8.0) / 2;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  identityBlock,
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SizedBox(width: cellWidth, child: percentileBadge),
                      SizedBox(
                        width: cellWidth,
                        child: _probMeter(
                          label: _prob1ShortLabel,
                          percent: c.fullCrownProb,
                          color: const Color(0xFFD97706),
                        ),
                      ),
                      SizedBox(
                        width: cellWidth,
                        child: _probMeter(
                          label: _prob2ShortLabel,
                          percent: c.topApexProb,
                          color: const Color(0xFF059669),
                        ),
                      ),
                      SizedBox(
                        width: cellWidth,
                        child: _probMeter(
                          label: _prob3ShortLabel,
                          percent: c.degreeBandProb,
                          color: const Color(0xFF4F46E5),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: identityBlock),
                    const SizedBox(width: 8),
                    percentileBadge,
                  ],
                ),
                const SizedBox(height: 8),
                probabilitiesBlock,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _probMeter({
    required String label,
    required double percent,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 9.8,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF475569),
                  ),
                ),
              ),
              const SizedBox(width: 3),
              Text(
                '%${percent.toStringAsFixed(1)}',
                style: GoogleFonts.inter(
                  fontSize: 11.4,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: (percent / 100.0).clamp(0.015, 1.0),
              minHeight: 5,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  void _openCandidateSheet(_ChampionCandidate c, int rank) {
    final rankFmt = NumberFormat('#,###', 'tr_TR');
    final dateFmt = DateFormat('dd.MM.yyyy');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 760),
      builder: (ctx) {
        return Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.emoji_events_rounded,
                        color: Color(0xFFD97706),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '#$rank • ${c.name}',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            '${c.branchName} • ${c.tierLabel} • %${c.estimatedPercentile.toStringAsFixed(2)} Dilim (~${rankFmt.format(c.estimatedTurkeyRank)}. Sıra)',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _probMeter(
                        label: _prob1ShortLabel,
                        percent: c.fullCrownProb,
                        color: const Color(0xFFD97706),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _probMeter(
                        label: _prob2ShortLabel,
                        percent: c.topApexProb,
                        color: const Color(0xFF059669),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _probMeter(
                        label: _prob3ShortLabel,
                        percent: c.degreeBandProb,
                        color: const Color(0xFF4F46E5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.tips_and_updates_rounded,
                        color: Color(0xFFD97706),
                        size: 19,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Zirve Koçluk Teşhisi: ${c.weakestBranchHint}. (Deneme başı ort. kayıp: ${c.avgQuestionLoss.toStringAsFixed(1)} soru • Sapma σ: ±${c.scoreStdDev.toStringAsFixed(1)}p)',
                          style: GoogleFonts.inter(
                            fontSize: 12.2,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Aktif Dönem Deneme Geçmişi (${c.history.length} Sınav)',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                ...c.history.reversed.map((h) {
                  final successPct = (h.netSuccessRate * 100.0).clamp(
                    0.0,
                    100.0,
                  );
                  final examTag = h.isFullTrial
                      ? 'Genel • ${h.totalQuestions}S'
                      : 'Tarama/Branş • ${h.totalQuestions}S';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 7),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      h.examName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: h.isFullTrial
                                          ? const Color(0xFFECFDF5)
                                          : const Color(0xFFF3E8FF),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      examTag,
                                      style: GoogleFonts.inter(
                                        fontSize: 9.8,
                                        fontWeight: FontWeight.w700,
                                        color: h.isFullTrial
                                            ? const Color(0xFF047857)
                                            : const Color(0xFF6D28D9),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${dateFmt.format(h.date)} • ${h.totalWrong} Yanlış, ${h.totalEmpty} Boş • %${successPct.toStringAsFixed(1)} Net Başarı',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${h.totalNet.toStringAsFixed(1)} / ${h.totalQuestions} Net',
                              style: GoogleFonts.inter(
                                fontSize: 12.3,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1E1B4B),
                              ),
                            ),
                            Text(
                              '${h.calibratedScore.toStringAsFixed(1)} Puan',
                              style: GoogleFonts.inter(
                                fontSize: 10.6,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}
