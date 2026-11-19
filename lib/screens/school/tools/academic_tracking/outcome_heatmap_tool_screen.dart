import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../../models/assessment/trial_exam_model.dart';
import '../../../../widgets/edukn_app_bar.dart';
import '../../assessment/evaluation_models.dart';
import 'academic_tracking_models.dart';
import 'academic_ui_widgets.dart';

class _CellRealStats {
  final int correct;
  final int total;
  final int examCount;
  final double realPct;

  const _CellRealStats({
    required this.correct,
    required this.total,
    required this.examCount,
    required this.realPct,
  });
}

typedef _HeatmapDataBundle = ({
  String title,
  String subtitleInfo,
  List<String> rowLabels,
  List<String> colLabels,
  List<String> fullColLabels,
  List<List<double?>> matrix,
  Map<String, _CellRealStats> realCellDetails,
  List<({String label, double pct, String action})> weakHighlights,
});

class OutcomeHeatmapToolScreen extends StatefulWidget {
  final AcademicDataset dataset;

  const OutcomeHeatmapToolScreen({super.key, required this.dataset});

  @override
  State<OutcomeHeatmapToolScreen> createState() =>
      _OutcomeHeatmapToolScreenState();
}

class _OutcomeHeatmapToolScreenState extends State<OutcomeHeatmapToolScreen> {
  // 'trial_branch' | 'trial_outcome' | 'written_class' | 'zumre_cumulative'
  late String _sourceMode;
  String? _selectedTrialId;
  String? _selectedSubject;
  String _zumreGrade = 'all';
  String _zumreBranch = '__ALL__';
  double _remedialThreshold = 55.0;

  // Görünüm modu: 'matrix' (Isı Haritası) | 'bar_chart' (Kazanım Sütun Grafiği)
  String _visualMode = 'matrix';

  // Fareyle üzerine gelinen sütun/hücre takibi (alttaki tam metin okuma şeridi için)
  int? _hoveredColIndex;
  int? _hoveredRowIndex;

  /// Kullanıcının yalnızca kendisi tıklayıp "Zümre Hedef Simülasyonu" uyguladığı hücreler:
  /// Başlangıçta tamamen BOŞTUR; hiçbir uydurma/rastgele veri üretilmez.
  final Map<String, double> _simulationOverrides = {};

  @override
  void initState() {
    super.initState();
    final availableGrades = _availableGrades();
    if (availableGrades.contains('8')) {
      _zumreGrade = '8';
    } else if (availableGrades.contains('12')) {
      _zumreGrade = '12';
    } else if (availableGrades.isNotEmpty) {
      _zumreGrade = availableGrades.last;
    }

    if (widget.dataset.trialExams.isNotEmpty) {
      _sourceMode = 'trial_branch';
      _selectedTrialId = widget.dataset.trialExams.first.id;
      final firstSubjects = _subjectsOfTrial(widget.dataset.trialExams.first);
      if (firstSubjects.isNotEmpty) _selectedSubject = firstSubjects.first;
    } else if (widget.dataset.classExams.isNotEmpty) {
      _sourceMode = 'written_class';
    } else {
      _sourceMode = 'zumre_cumulative';
    }
  }

  void _resetHover() {
    _hoveredColIndex = null;
    _hoveredRowIndex = null;
  }

  static String _extractGrade(String raw) {
    final lower = AcademicTrackingDataService.normTr(raw);
    if (lower.contains('mezun')) return '12';
    final m = RegExp(r'(\d{1,2})').firstMatch(raw.trim());
    return m != null ? m.group(1)! : '';
  }

  static String _shortenLabel(String full, {int maxChars = 24}) {
    final clean = full.trim();
    if (clean.length <= maxChars) return clean;
    return '${clean.substring(0, maxChars).trimRight()}…';
  }

  List<String> _availableGrades() {
    final set = <String>{};
    for (final c in widget.dataset.classes) {
      final g = _extractGrade(c.classLevel.isNotEmpty ? c.classLevel : c.name);
      if (g.isNotEmpty) set.add(g);
    }
    for (final ex in widget.dataset.trialExams) {
      final g = _extractGrade(
        ex.classLevel.isNotEmpty ? ex.classLevel : ex.name,
      );
      if (g.isNotEmpty) set.add(g);
    }
    final list = set.toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    return list;
  }

  List<ParsedTrialExam> _zumreFilteredExams() {
    if (_zumreGrade == 'all') return widget.dataset.trialExams;
    return widget.dataset.trialExams.where((ex) {
      final g = _extractGrade(
        ex.classLevel.isNotEmpty ? ex.classLevel : ex.name,
      );
      if (g.isNotEmpty) return g == _zumreGrade;
      return ex.results.any((r) {
        final rg = _extractGrade(
          r.classLevel.isNotEmpty ? r.classLevel : r.branch,
        );
        return rg == _zumreGrade;
      });
    }).toList();
  }

  List<String> _zumreAvailableSubjects(List<ParsedTrialExam> exams) {
    final set = <String>{};
    for (final ex in exams) {
      set.addAll(_subjectsOfTrial(ex));
    }
    return set.toList();
  }

  List<String> _subjectsOfTrial(ParsedTrialExam? t) {
    if (t == null) return const [];
    final set = <String>{};
    for (final r in t.results) {
      set.addAll(r.subjects.keys);
    }
    for (final b in t.exam.answerKeys.values) {
      set.addAll(b.keys);
    }
    return set.toList();
  }

  ParsedTrialExam? get _activeTrial {
    if (widget.dataset.trialExams.isEmpty) return null;
    for (final t in widget.dataset.trialExams) {
      if (t.id == _selectedTrialId) return t;
    }
    return widget.dataset.trialExams.first;
  }

  /// Öğrencinin kitapçığına uygun cevap anahtarını ve kazanım listesini esnek branş eşleşmesiyle bulur
  static ({String answerKey, List<String> outcomes}) _resolveBookletData({
    required TrialExam exam,
    required StudentResult student,
    required String subject,
  }) {
    final normTarget = AcademicTrackingDataService.normTr(subject);

    String? findKeyInMap<V>(Map<String, V>? map) {
      if (map == null || map.isEmpty) return null;
      if (map.containsKey(subject)) return subject;
      for (final k in map.keys) {
        final nk = AcademicTrackingDataService.normTr(k);
        if (nk == normTarget ||
            (nk.length >= 3 && normTarget.contains(nk)) ||
            (normTarget.length >= 3 && nk.contains(normTarget))) {
          return k;
        }
      }
      return null;
    }

    final preferredBooklet = student.booklet.trim().toUpperCase();
    String? chosenBooklet;
    if (preferredBooklet.isNotEmpty &&
        exam.answerKeys.containsKey(preferredBooklet)) {
      chosenBooklet = preferredBooklet;
    } else if (exam.answerKeys.containsKey('A')) {
      chosenBooklet = 'A';
    } else if (exam.answerKeys.isNotEmpty) {
      chosenBooklet = exam.answerKeys.keys.first;
    }

    String answerKey = '';
    final studentDirectKey = findKeyInMap(student.correctAnswers);
    if (studentDirectKey != null &&
        (student.correctAnswers[studentDirectKey] ?? '').isNotEmpty) {
      answerKey = student.correctAnswers[studentDirectKey]!;
    } else if (chosenBooklet != null) {
      final bkMap = exam.answerKeys[chosenBooklet];
      final matchK = findKeyInMap(bkMap);
      if (matchK != null) answerKey = bkMap![matchK] ?? '';
    }

    List<String> outcomes = const [];
    final outBooklet =
        (preferredBooklet.isNotEmpty &&
            exam.outcomes.containsKey(preferredBooklet))
        ? preferredBooklet
        : (exam.outcomes.containsKey('A')
              ? 'A'
              : (exam.outcomes.isNotEmpty ? exam.outcomes.keys.first : null));
    if (outBooklet != null) {
      final outMap = exam.outcomes[outBooklet];
      final matchK = findKeyInMap(outMap);
      if (matchK != null) {
        outcomes = outMap![matchK] ?? const [];
      }
    }

    return (answerKey: answerKey, outcomes: outcomes);
  }

  static String? _studentAnswerString(StudentResult st, String subject) {
    if (st.answers.containsKey(subject)) return st.answers[subject];
    final normTarget = AcademicTrackingDataService.normTr(subject);
    for (final k in st.answers.keys) {
      final nk = AcademicTrackingDataService.normTr(k);
      if (nk == normTarget ||
          (nk.length >= 3 && normTarget.contains(nk)) ||
          (normTarget.length >= 3 && nk.contains(normTarget))) {
        return st.answers[k];
      }
    }
    return null;
  }

  static SubjectStats? _studentSubjectStats(StudentResult st, String subject) {
    if (st.subjects.containsKey(subject)) return st.subjects[subject];
    final normTarget = AcademicTrackingDataService.normTr(subject);
    for (final k in st.subjects.keys) {
      final nk = AcademicTrackingDataService.normTr(k);
      if (nk == normTarget ||
          (nk.length >= 3 && normTarget.contains(nk)) ||
          (normTarget.length >= 3 && nk.contains(normTarget))) {
        return st.subjects[k];
      }
    }
    return null;
  }

  String _overrideKey(String rowLabel, String fullColLabel) =>
      '$_sourceMode|$_zumreGrade|$_zumreBranch|$rowLabel|$fullColLabel';

  /// Seçili mod için gerçek kurumsal veriden ısı matrisini ve tam kazanım metinlerini hesaplar
  _HeatmapDataBundle _computeMatrix() {
    final realDetails = <String, _CellRealStats>{};

    // 1. TEKİL DENEME: ŞUBE × BRANŞ
    if (_sourceMode == 'trial_branch' && _activeTrial != null) {
      final trial = _activeTrial!;
      final subjects = _subjectsOfTrial(trial);
      final branchesSet = <String>{};
      for (final r in trial.results) {
        final b = r.branch.trim().isEmpty ? 'Genel' : r.branch.trim();
        branchesSet.add(b);
      }
      final branches = branchesSet.toList()..sort();

      final matrix = <List<double?>>[];
      final weak = <({String label, double pct, String action})>[];

      for (final br in branches) {
        final row = <double?>[];
        final brStudents = trial.results
            .where(
              (r) =>
                  (r.branch.trim().isEmpty ? 'Genel' : r.branch.trim()) == br,
            )
            .toList();
        for (final subj in subjects) {
          int totalQ = 0;
          int totalCorrect = 0;
          for (final st in brStudents) {
            final s = _studentSubjectStats(st, subj);
            if (s != null) {
              final q = s.correct + s.wrong + s.empty;
              totalQ += q;
              totalCorrect += s.correct;
            }
          }
          if (totalQ == 0) {
            row.add(null);
          } else {
            final realPct = (totalCorrect / totalQ) * 100.0;
            final oKey = _overrideKey(br, subj);
            realDetails[oKey] = _CellRealStats(
              correct: totalCorrect,
              total: totalQ,
              examCount: 1,
              realPct: realPct,
            );
            final effectivePct = _simulationOverrides[oKey] ?? realPct;
            row.add(effectivePct);
            if (effectivePct < _remedialThreshold) {
              weak.add((
                label: '$br • $subj',
                pct: effectivePct,
                action:
                    '${brStudents.length} öğrenci ($totalCorrect/$totalQ doğru • %${effectivePct.toStringAsFixed(0)}) — Branş telafi etüdü önerilir.',
              ));
            }
          }
        }
        matrix.add(row);
      }
      weak.sort((a, b) => a.pct.compareTo(b.pct));
      return (
        title: '${trial.name} — Şube × Branş Başarı Isı Haritası (%)',
        subtitleInfo:
            'Seçili deneme sınavındaki gerçek doğru / toplam soru oranları gösterilmektedir.',
        rowLabels: branches,
        colLabels: subjects.map((s) => _shortenLabel(s, maxChars: 20)).toList(),
        fullColLabels: subjects,
        matrix: matrix,
        realCellDetails: realDetails,
        weakHighlights: weak,
      );
    }

    // 2. TEKİL DENEME: SORU & KAZANIM BAZLI (KİTAPÇIK A/B EŞLEŞTİRMELİ)
    if (_sourceMode == 'trial_outcome' && _activeTrial != null) {
      final trial = _activeTrial!;
      final subjects = _subjectsOfTrial(trial);
      final subj =
          (_selectedSubject != null && subjects.contains(_selectedSubject))
          ? _selectedSubject!
          : (subjects.isNotEmpty ? subjects.first : '');

      final branchesSet = <String>{};
      for (final r in trial.results) {
        branchesSet.add(r.branch.trim().isEmpty ? 'Genel' : r.branch.trim());
      }
      final branches = branchesSet.toList()..sort();

      final dummyStudent = StudentResult(
        tcNo: '',
        studentNo: '',
        name: '',
        classLevel: trial.classLevel,
        branch: '',
        booklet: 'A',
      );
      final refData = _resolveBookletData(
        exam: trial.exam,
        student: dummyStudent,
        subject: subj,
      );
      String refKey = refData.answerKey;
      if (refKey.isEmpty) {
        for (final r in trial.results) {
          final resolved = _resolveBookletData(
            exam: trial.exam,
            student: r,
            subject: subj,
          );
          if (resolved.answerKey.isNotEmpty) {
            refKey = resolved.answerKey;
            break;
          }
        }
      }

      final hasDefinedOutcomes = refData.outcomes.any(
        (o) => o.trim().isNotEmpty,
      );

      if (hasDefinedOutcomes) {
        final orderedTopics = <String>[];
        for (final o in refData.outcomes) {
          final clean = o.trim();
          if (clean.isNotEmpty && !orderedTopics.contains(clean)) {
            orderedTopics.add(clean);
          }
        }

        final matrix = <List<double?>>[];
        final globalCorrect = <String, int>{};
        final globalTotal = <String, int>{};

        for (final br in branches) {
          final brStudents = trial.results
              .where(
                (r) =>
                    (r.branch.trim().isEmpty ? 'Genel' : r.branch.trim()) == br,
              )
              .toList();
          final brCorrect = <String, int>{};
          final brTotal = <String, int>{};

          for (final st in brStudents) {
            final ansStr = _studentAnswerString(st, subj) ?? '';
            if (ansStr.isEmpty) continue;
            final bData = _resolveBookletData(
              exam: trial.exam,
              student: st,
              subject: subj,
            );
            final keyStr = bData.answerKey.isNotEmpty
                ? bData.answerKey
                : refKey;
            final stOutcomes = bData.outcomes.isNotEmpty
                ? bData.outcomes
                : refData.outcomes;
            final len = [
              ansStr.length,
              keyStr.length,
              stOutcomes.length,
            ].reduce((a, b) => a < b ? a : b);

            for (int q = 0; q < len; q++) {
              final topic = stOutcomes[q].trim();
              if (topic.isEmpty) continue;
              final status = TrialExam.evaluateAnswer(ansStr[q], keyStr[q]);
              brTotal[topic] = (brTotal[topic] ?? 0) + 1;
              globalTotal[topic] = (globalTotal[topic] ?? 0) + 1;
              if (status == AnswerStatus.correct) {
                brCorrect[topic] = (brCorrect[topic] ?? 0) + 1;
                globalCorrect[topic] = (globalCorrect[topic] ?? 0) + 1;
              }
            }
          }

          final row = <double?>[];
          for (final fullTopic in orderedTopics) {
            final tot = brTotal[fullTopic] ?? 0;
            final cor = brCorrect[fullTopic] ?? 0;
            if (tot == 0) {
              row.add(null);
            } else {
              final realPct = (cor / tot) * 100.0;
              final oKey = _overrideKey(br, fullTopic);
              realDetails[oKey] = _CellRealStats(
                correct: cor,
                total: tot,
                examCount: 1,
                realPct: realPct,
              );
              row.add(_simulationOverrides[oKey] ?? realPct);
            }
          }
          matrix.add(row);
        }

        final colLabels = orderedTopics
            .map((t) => _shortenLabel(t, maxChars: 24))
            .toList();

        final weak = <({String label, double pct, String action})>[];
        for (final topic in orderedTopics) {
          final tot = globalTotal[topic] ?? 0;
          final cor = globalCorrect[topic] ?? 0;
          if (tot > 0) {
            final pct = (cor / tot) * 100.0;
            if (pct < _remedialThreshold) {
              weak.add((
                label: '$subj • $topic',
                pct: pct,
                action:
                    'Kurum genelinde $cor/$tot doğru (%${pct.toStringAsFixed(0)}) — Kazanım telafi etüdü önerilir.',
              ));
            }
          }
        }
        weak.sort((a, b) => a.pct.compareTo(b.pct));

        return (
          title: '${trial.name} ($subj) — Gerçek Kazanım Isı Haritası (%)',
          subtitleInfo:
              'Öğrencilerin kendi kitapçık türlerine (A/B) göre eşleştirilmiş gerçek sınav kazanım yüzdeleri.',
          rowLabels: branches,
          colLabels: colLabels,
          fullColLabels: orderedTopics,
          matrix: matrix,
          realCellDetails: realDetails,
          weakHighlights: weak,
        );
      }

      // Kazanım metni tanımlanmamışsa soru bazlı (S1, S2...) gerçek optik analiz
      final qCount = refKey.length;
      if (qCount == 0) {
        return (
          title: '${trial.name} ($subj) — Optik Cevap Dizisi Bulunamadı',
          subtitleInfo:
              'Bu sınavda soru bazlı optik cevap dizisi kayıtlı olmadığından "Şube × Branş" veya "Dönemlik Zümre Matrisi" sekmesini kullanabilirsiniz.',
          rowLabels: const [],
          colLabels: const [],
          fullColLabels: const [],
          matrix: const [],
          realCellDetails: realDetails,
          weakHighlights: const [],
        );
      }

      final colLabels = List<String>.generate(qCount, (i) => 'Soru ${i + 1}');
      final fullColLabels = List<String>.generate(
        qCount,
        (i) => '$subj • ${i + 1}. Soru (Doğru Şık: ${refKey[i]})',
      );
      final matrix = <List<double?>>[];
      final colTotals = List<int>.filled(qCount, 0);
      final colCorrects = List<int>.filled(qCount, 0);

      for (final br in branches) {
        final brStudents = trial.results
            .where(
              (r) =>
                  (r.branch.trim().isEmpty ? 'Genel' : r.branch.trim()) == br,
            )
            .toList();
        final row = <double?>[];
        for (int q = 0; q < qCount; q++) {
          int n = 0;
          int c = 0;
          for (final st in brStudents) {
            final ansStr = _studentAnswerString(st, subj) ?? '';
            final bData = _resolveBookletData(
              exam: trial.exam,
              student: st,
              subject: subj,
            );
            final keyStr = bData.answerKey.isNotEmpty
                ? bData.answerKey
                : refKey;
            if (q < ansStr.length && q < keyStr.length) {
              n++;
              colTotals[q]++;
              if (TrialExam.evaluateAnswer(ansStr[q], keyStr[q]) ==
                  AnswerStatus.correct) {
                c++;
                colCorrects[q]++;
              }
            }
          }
          if (n == 0) {
            row.add(null);
          } else {
            final realPct = (c / n) * 100.0;
            final oKey = _overrideKey(br, fullColLabels[q]);
            realDetails[oKey] = _CellRealStats(
              correct: c,
              total: n,
              examCount: 1,
              realPct: realPct,
            );
            row.add(_simulationOverrides[oKey] ?? realPct);
          }
        }
        matrix.add(row);
      }

      final weak = <({String label, double pct, String action})>[];
      for (int q = 0; q < qCount; q++) {
        if (colTotals[q] > 0) {
          final pct = (colCorrects[q] / colTotals[q]) * 100.0;
          if (pct < _remedialThreshold) {
            weak.add((
              label: '$subj • ${q + 1}. Soru',
              pct: pct,
              action:
                  'Kurum genelinde ${colCorrects[q]}/${colTotals[q]} doğru (%${pct.toStringAsFixed(0)}) — Soru çözüm etüdü önerilir.',
            ));
          }
        }
      }
      weak.sort((a, b) => a.pct.compareTo(b.pct));

      return (
        title: '${trial.name} ($subj) — Soru Bazlı Optik Isı Haritası (%)',
        subtitleInfo:
            'Bu sınavda kazanım metni eşleştirilmediği için doğrudan optik soru başarı oranları gösterilmektedir.',
        rowLabels: branches,
        colLabels: colLabels,
        fullColLabels: fullColLabels,
        matrix: matrix,
        realCellDetails: realDetails,
        weakHighlights: weak,
      );
    }

    // 3. YAZILI SINAVLAR: SINIF × DERS
    if (_sourceMode == 'written_class') {
      final classes = <String>{};
      final lessons = <String>{};
      for (final ce in widget.dataset.classExams) {
        if (ce.grades.isEmpty) continue;
        classes.add(ce.className);
        lessons.add(ce.lessonName);
      }
      final rowLabels = classes.toList()..sort();
      final fullColLabels = lessons.toList()..sort();
      final colLabels = fullColLabels
          .map((l) => _shortenLabel(l, maxChars: 20))
          .toList();
      final matrix = <List<double?>>[];
      final weak = <({String label, double pct, String action})>[];

      for (final cl in rowLabels) {
        final row = <double?>[];
        for (final les in fullColLabels) {
          final matching = widget.dataset.classExams
              .where(
                (e) =>
                    e.className == cl &&
                    e.lessonName == les &&
                    e.grades.isNotEmpty,
              )
              .toList();
          if (matching.isEmpty) {
            row.add(null);
          } else {
            final avg =
                matching.map((m) => m.average).reduce((a, b) => a + b) /
                matching.length;
            final studentCount = matching.fold<int>(
              0,
              (a, b) => a + b.grades.length,
            );
            final oKey = _overrideKey(cl, les);
            realDetails[oKey] = _CellRealStats(
              correct: avg.round(),
              total: 100,
              examCount: matching.length,
              realPct: avg,
            );
            final effective = _simulationOverrides[oKey] ?? avg;
            row.add(effective);
            if (effective < _remedialThreshold) {
              weak.add((
                label: '$cl • $les',
                pct: effective,
                action:
                    '${matching.length} yazılı sınav ortalaması ${effective.toStringAsFixed(1)} ($studentCount öğrenci notu) — Zümre telafi çalışması önerilir.',
              ));
            }
          }
        }
        matrix.add(row);
      }
      weak.sort((a, b) => a.pct.compareTo(b.pct));

      return (
        title: 'Kurum Yazılı Sınavları — Sınıf × Ders Ortalaması Isı Haritası',
        subtitleInfo:
            'Aktif dönemde sisteme girilen gerçek yazılı sınav notlarının sınıf ve ders bazlı ortalamaları.',
        rowLabels: rowLabels,
        colLabels: colLabels,
        fullColLabels: fullColLabels,
        matrix: matrix,
        realCellDetails: realDetails,
        weakHighlights: weak,
      );
    }

    // 4. DÖNEMLİK KÜMÜLATİF ZÜMRE & KAZANIM MATRİSİ (%100 GERÇEK KURUM VERİSİ)
    final exams = _zumreFilteredExams();
    if (exams.isEmpty) {
      return (
        title: 'Dönemlik Zümre & Kazanım Matrisi',
        subtitleInfo:
            'Seçili kademede ve aktif dönemde henüz deneme sınavı verisi bulunmuyor.',
        rowLabels: const [],
        colLabels: const [],
        fullColLabels: const [],
        matrix: const [],
        realCellDetails: realDetails,
        weakHighlights: const [],
      );
    }

    final availSubjects = _zumreAvailableSubjects(exams);
    final activeBranch =
        (_zumreBranch != '__ALL__' && availSubjects.contains(_zumreBranch))
        ? _zumreBranch
        : '__ALL__';

    final branchSet = <String>{};
    for (final ex in exams) {
      for (final r in ex.results) {
        final b = r.branch.trim();
        if (b.isEmpty) continue;
        if (_zumreGrade != 'all') {
          final rg = _extractGrade(r.classLevel.isNotEmpty ? r.classLevel : b);
          if (rg.isNotEmpty && rg != _zumreGrade) continue;
        }
        branchSet.add(b);
      }
    }
    final realBranches = branchSet.toList()..sort();

    // 4A. TÜM ZÜMRELER ÖZETİ
    if (activeBranch == '__ALL__') {
      final matrix = <List<double?>>[];
      final weak = <({String label, double pct, String action})>[];

      for (final br in realBranches) {
        final row = <double?>[];
        for (final subj in availSubjects) {
          int cor = 0;
          int tot = 0;
          int exCnt = 0;
          for (final ex in exams) {
            bool foundInExam = false;
            for (final st in ex.results) {
              if (st.branch.trim() != br) continue;
              final s = _studentSubjectStats(st, subj);
              if (s != null) {
                final q = s.correct + s.wrong + s.empty;
                if (q > 0) {
                  cor += s.correct;
                  tot += q;
                  foundInExam = true;
                }
              }
            }
            if (foundInExam) exCnt++;
          }

          if (tot == 0) {
            row.add(null);
          } else {
            final realPct = (cor / tot) * 100.0;
            final oKey = _overrideKey(br, subj);
            realDetails[oKey] = _CellRealStats(
              correct: cor,
              total: tot,
              examCount: exCnt,
              realPct: realPct,
            );
            final effectivePct = _simulationOverrides[oKey] ?? realPct;
            row.add(effectivePct);
            if (effectivePct < _remedialThreshold) {
              weak.add((
                label: '$br • $subj',
                pct: effectivePct,
                action:
                    'Aktif dönemdeki $exCnt denemede toplam $cor/$tot doğru (%${effectivePct.toStringAsFixed(0)}) — Zümre telafi programı önerilir.',
              ));
            }
          }
        }
        matrix.add(row);
      }
      weak.sort((a, b) => a.pct.compareTo(b.pct));
      final gradeLabel = _zumreGrade == 'all'
          ? 'Tüm Kademeler'
          : '$_zumreGrade. Sınıf';
      return (
        title:
            'Dönemlik Kümülatif Zümre Başarı Matrisi — $gradeLabel (${exams.length} Deneme Birleşimi)',
        subtitleInfo:
            'Aktif dönemdeki ${exams.length} deneme sınavının tamamı birleştirilerek her şubenin gerçek branş başarı yüzdesi hesaplanmıştır. Belirli bir dersin alt kazanımlarını görmek için yukarıdan branş seçin.',
        rowLabels: realBranches,
        colLabels: availSubjects
            .map((s) => _shortenLabel(s, maxChars: 20))
            .toList(),
        fullColLabels: availSubjects,
        matrix: matrix,
        realCellDetails: realDetails,
        weakHighlights: weak,
      );
    }

    // 4B. BELİRLİ BİR BRANŞ SEÇİLDİĞİNDE: Gerçek kazanım birleşimi
    final topicOrder = <String>[];
    final cellAcc = <String, ({int cor, int tot, Set<String> examIds})>{};

    for (final ex in exams) {
      for (final st in ex.results) {
        final br = st.branch.trim();
        if (!realBranches.contains(br)) continue;
        final ansStr = _studentAnswerString(st, activeBranch) ?? '';
        if (ansStr.isEmpty) continue;
        final bData = _resolveBookletData(
          exam: ex.exam,
          student: st,
          subject: activeBranch,
        );
        if (bData.answerKey.isEmpty || bData.outcomes.isEmpty) continue;

        final len = [
          ansStr.length,
          bData.answerKey.length,
          bData.outcomes.length,
        ].reduce((a, b) => a < b ? a : b);

        for (int q = 0; q < len; q++) {
          final topic = bData.outcomes[q].trim();
          if (topic.isEmpty) continue;
          if (!topicOrder.contains(topic)) {
            topicOrder.add(topic);
          }
          final status = TrialExam.evaluateAnswer(
            ansStr[q],
            bData.answerKey[q],
          );
          final mapKey = '$br||$topic';
          final prev = cellAcc[mapKey] ?? (cor: 0, tot: 0, examIds: <String>{});
          prev.examIds.add(ex.id);
          cellAcc[mapKey] = (
            cor: prev.cor + (status == AnswerStatus.correct ? 1 : 0),
            tot: prev.tot + 1,
            examIds: prev.examIds,
          );
        }
      }
    }

    if (topicOrder.isNotEmpty) {
      final colLabels = topicOrder
          .map((t) => _shortenLabel(t, maxChars: 24))
          .toList();
      final matrix = <List<double?>>[];
      final weak = <({String label, double pct, String action})>[];

      for (final br in realBranches) {
        final row = <double?>[];
        for (int i = 0; i < topicOrder.length; i++) {
          final fullTopic = topicOrder[i];
          final acc = cellAcc['$br||$fullTopic'];
          if (acc == null || acc.tot == 0) {
            row.add(null);
          } else {
            final realPct = (acc.cor / acc.tot) * 100.0;
            final oKey = _overrideKey(br, fullTopic);
            realDetails[oKey] = _CellRealStats(
              correct: acc.cor,
              total: acc.tot,
              examCount: acc.examIds.length,
              realPct: realPct,
            );
            final effectivePct = _simulationOverrides[oKey] ?? realPct;
            row.add(effectivePct);
            if (effectivePct < _remedialThreshold) {
              weak.add((
                label: '$br • $fullTopic',
                pct: effectivePct,
                action:
                    '${acc.examIds.length} denemede toplam ${acc.cor}/${acc.tot} doğru (%${effectivePct.toStringAsFixed(0)}) — Kazanım telafi etüdü önerilir.',
              ));
            }
          }
        }
        matrix.add(row);
      }
      weak.sort((a, b) => a.pct.compareTo(b.pct));
      return (
        title:
            '$activeBranch Zümresi — Dönemlik Kümülatif Kazanım Isı Haritası (%)',
        subtitleInfo:
            'Aktif dönem denemelerinde eşleştirilmiş gerçek "$activeBranch" kazanımlarının şube bazlı kümülatif doğru oranları.',
        rowLabels: realBranches,
        colLabels: colLabels,
        fullColLabels: topicOrder,
        matrix: matrix,
        realCellDetails: realDetails,
        weakHighlights: weak,
      );
    }

    // Kazanım metni girilmemişse kronolojik sınav bazlı gerçek gelişim
    final chronological = [...exams]..sort((a, b) => a.date.compareTo(b.date));
    final dateFmt = DateFormat('dd/MM');
    final usedExams = <ParsedTrialExam>[];
    for (final ex in chronological) {
      final hasBranch = ex.results.any(
        (r) => _studentSubjectStats(r, activeBranch) != null,
      );
      if (hasBranch) usedExams.add(ex);
    }

    final colLabels = usedExams.map((e) {
      return '${_shortenLabel(e.name, maxChars: 16)} (${dateFmt.format(e.date)})';
    }).toList();
    final fullColLabels = usedExams.map((e) {
      return '${e.name} • ${DateFormat('dd.MM.yyyy').format(e.date)} ($activeBranch)';
    }).toList();

    final matrix = <List<double?>>[];
    final weak = <({String label, double pct, String action})>[];

    for (final br in realBranches) {
      final row = <double?>[];
      for (int i = 0; i < usedExams.length; i++) {
        final ex = usedExams[i];
        final fullColName = fullColLabels[i];
        int cor = 0;
        int tot = 0;
        for (final st in ex.results) {
          if (st.branch.trim() != br) continue;
          final s = _studentSubjectStats(st, activeBranch);
          if (s != null) {
            cor += s.correct;
            tot += (s.correct + s.wrong + s.empty);
          }
        }
        if (tot == 0) {
          row.add(null);
        } else {
          final realPct = (cor / tot) * 100.0;
          final oKey = _overrideKey(br, fullColName);
          realDetails[oKey] = _CellRealStats(
            correct: cor,
            total: tot,
            examCount: 1,
            realPct: realPct,
          );
          final effectivePct = _simulationOverrides[oKey] ?? realPct;
          row.add(effectivePct);
          if (effectivePct < _remedialThreshold) {
            weak.add((
              label: '$br • ${ex.name} ($activeBranch)',
              pct: effectivePct,
              action:
                  '$activeBranch doğru oranı %${effectivePct.toStringAsFixed(0)} ($cor/$tot soru) — Konu tekrarı önerilir.',
            ));
          }
        }
      }
      matrix.add(row);
    }
    weak.sort((a, b) => a.pct.compareTo(b.pct));

    return (
      title:
          '$activeBranch Zümresi — Deneme Bazlı Şube Gelişim Isı Haritası (%)',
      subtitleInfo:
          'Bu branştaki denemelere henüz kazanım listesi eşleştirilmediği için uydurma konu gösterilmez; şubelerin gerçek sınav bazlı "$activeBranch" başarı oranları listelenir.',
      rowLabels: realBranches,
      colLabels: colLabels,
      fullColLabels: fullColLabels,
      matrix: matrix,
      realCellDetails: realDetails,
      weakHighlights: weak,
    );
  }

  Color _heatBg(double? val) {
    if (val == null) return const Color(0xFFF1F5F9);
    if (val < 45) return const Color(0xFFFEE2E2);
    if (val < 60) return const Color(0xFFFEF3C7);
    if (val < 78) return const Color(0xFFDBEAFE);
    return const Color(0xFFD1FAE5);
  }

  Color _heatFg(double? val) {
    if (val == null) return const Color(0xFF94A3B8);
    if (val < 45) return const Color(0xFFB91C1C);
    if (val < 60) return const Color(0xFFB45309);
    if (val < 78) return const Color(0xFF1D4ED8);
    return const Color(0xFF047857);
  }

  Future<void> _exportPdf() async {
    final data = _computeMatrix();
    if (data.rowLabels.isEmpty || data.colLabels.isEmpty) return;

    final termText = widget.dataset.activeTermName.isNotEmpty
        ? ' • Dönem: ${widget.dataset.activeTermName}'
        : '';

    await AcademicTrackingPdfService.printTableReport(
      documentTitle: 'KAZANIM VE ZÜMRE BAŞARI ISI HARİTASI RAPORU',
      schoolName: '${widget.dataset.schoolName}$termText',
      subtitle: data.title,
      landscape: data.colLabels.length > 5,
      kpis: [
        (label: 'İncelenen Şube', value: '${data.rowLabels.length} Şube'),
        (label: 'Başlık / Kazanım', value: '${data.colLabels.length} Sütun'),
        (
          label: 'Telafi Eşiği',
          value: '< %${_remedialThreshold.toStringAsFixed(0)}',
        ),
        (
          label: 'Kritik Uyarı Hücresi',
          value: '${data.weakHighlights.length} Alan',
        ),
      ],
      headers: ['Şube / Grup', ...data.colLabels],
      rows: List.generate(data.rowLabels.length, (r) {
        return [
          data.rowLabels[r],
          ...data.matrix[r].map(
            (v) => v == null ? '-' : '%${v.toStringAsFixed(0)}',
          ),
        ];
      }),
      notes: data.weakHighlights
          .take(12)
          .map((w) => '${w.label}: ${w.action}')
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 780;
    final data = _computeMatrix();
    final trialSubjects = _subjectsOfTrial(_activeTrial);
    final subtitleParts = <String>[
      widget.dataset.schoolName,
      if (widget.dataset.activeTermName.isNotEmpty)
        'Dönem: ${widget.dataset.activeTermName}',
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: EduknAppBar(
        title: 'Kazanım & Branş Başarı Isı Haritası',
        subtitle: subtitleParts.join(' • '),
        actions: [
          if (_simulationOverrides.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: TextButton.icon(
                onPressed: () => setState(() => _simulationOverrides.clear()),
                icon: const Icon(
                  Icons.restart_alt_rounded,
                  size: 18,
                  color: Color(0xFFB45309),
                ),
                label: Text(
                  isMobile ? 'Sıfırla' : 'Gerçek Verilere Sıfırla',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: const Color(0xFFB45309),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton.icon(
              onPressed: data.rowLabels.isEmpty ? null : _exportPdf,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
              label: Text(
                isMobile ? 'PDF' : 'Isı Haritası PDF',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(isMobile ? 14 : 22),
        children: [
          _buildControlCard(isMobile, trialSubjects),
          const SizedBox(height: 14),
          _buildLegendBar(),
          const SizedBox(height: 12),
          _buildMatrixCard(data),
          const SizedBox(height: 16),
          _buildRemedialActionCard(data.weakHighlights),
        ],
      ),
    );
  }

  Widget _buildControlCard(bool isMobile, List<String> trialSubjects) {
    final grades = _availableGrades();
    final zumreExams = _zumreFilteredExams();
    final zumreSubjects = _zumreAvailableSubjects(zumreExams);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _sourceChip(
                'trial_branch',
                'Tekil Deneme: Şube × Branş (${widget.dataset.trialExams.length})',
                Icons.grid_view_rounded,
              ),
              _sourceChip(
                'trial_outcome',
                'Tekil Deneme: Soru & Kazanım',
                Icons.fact_check_outlined,
              ),
              _sourceChip(
                'zumre_cumulative',
                'Dönemlik Zümre & Kazanım Matrisi',
                Icons.analytics_rounded,
              ),
              _sourceChip(
                'written_class',
                'Yazılı Sınavlar (${widget.dataset.classExams.length})',
                Icons.assignment_turned_in_rounded,
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 760;
              return Wrap(
                spacing: 14,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  if ((_sourceMode == 'trial_branch' ||
                          _sourceMode == 'trial_outcome') &&
                      widget.dataset.trialExams.isNotEmpty)
                    SizedBox(
                      width: narrow ? constraints.maxWidth : 310,
                      child: AcademicDropdownField<String>(
                        label: 'Deneme Sınavı Seçin',
                        icon: Icons.assignment_rounded,
                        accentColor: const Color(0xFFD97706),
                        value: _activeTrial?.id,
                        items: widget.dataset.trialExams
                            .map(
                              (t) => DropdownMenuItem(
                                value: t.id,
                                child: Text(
                                  '${t.name} (${t.results.length} Öğr.)',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          setState(() {
                            _selectedTrialId = v;
                            final subs = _subjectsOfTrial(_activeTrial);
                            _selectedSubject = subs.isNotEmpty
                                ? subs.first
                                : null;
                            _resetHover();
                          });
                        },
                      ),
                    ),
                  if (_sourceMode == 'trial_outcome' &&
                      trialSubjects.isNotEmpty)
                    SizedBox(
                      width: narrow ? constraints.maxWidth : 210,
                      child: AcademicDropdownField<String>(
                        label: 'Branş Seçin',
                        icon: Icons.menu_book_rounded,
                        accentColor: const Color(0xFFD97706),
                        value: trialSubjects.contains(_selectedSubject)
                            ? _selectedSubject
                            : trialSubjects.first,
                        items: trialSubjects
                            .map(
                              (s) => DropdownMenuItem(
                                value: s,
                                child: Text(
                                  s,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() {
                          _selectedSubject = v;
                          _resetHover();
                        }),
                      ),
                    ),
                  if (_sourceMode == 'zumre_cumulative') ...[
                    SizedBox(
                      width: narrow ? constraints.maxWidth : 195,
                      child: AcademicDropdownField<String>(
                        label: 'Sınıf Seviyesi',
                        icon: Icons.layers_rounded,
                        accentColor: const Color(0xFFD97706),
                        value:
                            (_zumreGrade == 'all' ||
                                grades.contains(_zumreGrade))
                            ? _zumreGrade
                            : 'all',
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Text('Tüm Kademeler'),
                          ),
                          ...grades.map(
                            (g) => DropdownMenuItem(
                              value: g,
                              child: Text('$g. Sınıf'),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() {
                            _zumreGrade = v ?? 'all';
                            _resetHover();
                          });
                        },
                      ),
                    ),
                    SizedBox(
                      width: narrow ? constraints.maxWidth : 275,
                      child: AcademicDropdownField<String>(
                        label: 'Zümre / Branş Seçimi',
                        icon: Icons.account_tree_rounded,
                        accentColor: const Color(0xFFD97706),
                        value:
                            (_zumreBranch == '__ALL__' ||
                                zumreSubjects.contains(_zumreBranch))
                            ? _zumreBranch
                            : '__ALL__',
                        items: [
                          const DropdownMenuItem(
                            value: '__ALL__',
                            child: Text(
                              'Tüm Zümreler (Kümülatif Branş Özeti)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          ...zumreSubjects.map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                '$s Zümresi (Kazanım / Gelişim)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() {
                          _zumreBranch = v ?? '__ALL__';
                          _resetHover();
                        }),
                      ),
                    ),
                  ],
                  SizedBox(
                    width: narrow ? constraints.maxWidth : 265,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        children: [
                          Text(
                            'Telafi: <%${_remedialThreshold.toStringAsFixed(0)}',
                            style: GoogleFonts.inter(
                              fontSize: 12.2,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFB45309),
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: _remedialThreshold,
                              min: 35,
                              max: 75,
                              divisions: 8,
                              activeColor: const Color(0xFFD97706),
                              onChanged: (v) =>
                                  setState(() => _remedialThreshold = v),
                            ),
                          ),
                        ],
                      ),
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

  Widget _sourceChip(String mode, String label, IconData icon) {
    return AcademicChoicePill(
      label: label,
      icon: icon,
      selected: _sourceMode == mode,
      accentColor: const Color(0xFFD97706),
      onTap: () => setState(() {
        _sourceMode = mode;
        _resetHover();
      }),
    );
  }

  Widget _buildLegendBar() {
    Widget badge(String text, Color bg, Color fg) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            badge(
              '0–44% Kritik Eksik',
              const Color(0xFFFEE2E2),
              const Color(0xFFB91C1C),
            ),
            badge(
              '45–59% Geliştirilmeli',
              const Color(0xFFFEF3C7),
              const Color(0xFFB45309),
            ),
            badge(
              '60–77% İyi Düzey',
              const Color(0xFFDBEAFE),
              const Color(0xFF1D4ED8),
            ),
            badge(
              '78–100% Tam Öğrenme',
              const Color(0xFFD1FAE5),
              const Color(0xFF047857),
            ),
          ],
        ),
        Wrap(
          spacing: 6,
          children: [
            AcademicChoicePill(
              icon: Icons.table_view_rounded,
              label: 'Isı Haritası Matrisi',
              selected: _visualMode == 'matrix',
              accentColor: const Color(0xFFD97706),
              compact: true,
              onTap: () => setState(() => _visualMode = 'matrix'),
            ),
            AcademicChoicePill(
              icon: Icons.bar_chart_rounded,
              label: 'Kazanım Başarı Grafiği',
              selected: _visualMode == 'bar_chart',
              accentColor: const Color(0xFFD97706),
              compact: true,
              onTap: () => setState(() => _visualMode = 'bar_chart'),
            ),
          ],
        ),
      ],
    );
  }

  /// Her sütunun kurum geneli ortalama başarı ve toplam doğru/soru istatistiğini hesaplar
  ({double? avgPct, int totalCor, int totalQ}) _columnSummary(
    _HeatmapDataBundle data,
    int colIdx,
  ) {
    if (colIdx < 0 || colIdx >= data.fullColLabels.length) {
      return (avgPct: null, totalCor: 0, totalQ: 0);
    }
    final fullCol = data.fullColLabels[colIdx];
    double sumPct = 0;
    int validRows = 0;
    int cor = 0;
    int tot = 0;

    for (int r = 0; r < data.rowLabels.length; r++) {
      final v = data.matrix[r][colIdx];
      if (v != null) {
        sumPct += v;
        validRows++;
      }
      final info =
          data.realCellDetails[_overrideKey(data.rowLabels[r], fullCol)];
      if (info != null) {
        cor += info.correct;
        tot += info.total;
      }
    }

    if (validRows == 0) return (avgPct: null, totalCor: 0, totalQ: 0);
    final weightedOrAvg = (_sourceMode != 'written_class' && tot > 0)
        ? (cor / tot) * 100.0
        : (sumPct / validRows);
    return (avgPct: weightedOrAvg, totalCor: cor, totalQ: tot);
  }

  Widget _buildMatrixCard(_HeatmapDataBundle data) {
    if (data.rowLabels.isEmpty || data.colLabels.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.grid_off_rounded,
              size: 46,
              color: Color(0xFF94A3B8),
            ),
            const SizedBox(height: 10),
            Text(
              data.title,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              data.subtitleInfo,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12.8,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      );
    }

    final safeHoveredCol =
        (_hoveredColIndex != null &&
            _hoveredColIndex! >= 0 &&
            _hoveredColIndex! < data.fullColLabels.length)
        ? _hoveredColIndex
        : null;
    final safeHoveredRow =
        (_hoveredRowIndex != null &&
            _hoveredRowIndex! >= 0 &&
            _hoveredRowIndex! < data.rowLabels.length)
        ? _hoveredRowIndex
        : null;

    return Container(
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
            data.title,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${data.subtitleInfo} Kısaltılmış kazanımların tam metnini okumak için fareyle üzerine gelin; simülasyon için hücreye tıklayın.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 14),
          if (_visualMode == 'bar_chart')
            _buildInteractiveOutcomeBarChart(data, safeHoveredCol)
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const IntrinsicColumnWidth(),
                border: TableBorder.all(
                  color: Colors.white,
                  width: 3,
                  borderRadius: BorderRadius.circular(8),
                ),
                children: [
                  TableRow(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        color: const Color(0xFFF8FAFC),
                        child: Text(
                          'Şube / Başlık',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: const Color(0xFF334155),
                          ),
                        ),
                      ),
                      ...List.generate(data.colLabels.length, (c) {
                        final shortLabel = data.colLabels[c];
                        final fullLabel = data.fullColLabels[c];
                        final isColHovered = safeHoveredCol == c;

                        return MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) {
                            setState(() {
                              _hoveredColIndex = c;
                              _hoveredRowIndex = null;
                            });
                          },
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _hoveredColIndex = c;
                                _hoveredRowIndex = null;
                              });
                            },
                            child: Tooltip(
                              message: fullLabel,
                              waitDuration: const Duration(milliseconds: 250),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 140),
                                constraints: const BoxConstraints(
                                  minWidth: 108,
                                  maxWidth: 180,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: isColHovered
                                      ? const Color(0xFFFFFBEB)
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isColHovered
                                        ? const Color(0xFFF59E0B)
                                        : Colors.transparent,
                                    width: 1.4,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  shortLabel,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11.5,
                                    color: isColHovered
                                        ? const Color(0xFFB45309)
                                        : const Color(0xFF1E293B),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                  ...List.generate(data.rowLabels.length, (r) {
                    final rLabel = data.rowLabels[r];
                    return TableRow(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          color: safeHoveredRow == r
                              ? const Color(0xFFFFFBEB)
                              : const Color(0xFFF8FAFC),
                          child: Text(
                            rLabel,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        ...List.generate(data.colLabels.length, (c) {
                          final fullLabel = data.fullColLabels[c];
                          final val = data.matrix[r][c];
                          final oKey = _overrideKey(rLabel, fullLabel);
                          final isSimulated = _simulationOverrides.containsKey(
                            oKey,
                          );
                          final realInfo = data.realCellDetails[oKey];
                          final isCellHovered =
                              safeHoveredCol == c && safeHoveredRow == r;

                          return MouseRegion(
                            cursor: val == null
                                ? SystemMouseCursors.basic
                                : SystemMouseCursors.click,
                            onEnter: (_) {
                              setState(() {
                                _hoveredColIndex = c;
                                _hoveredRowIndex = r;
                              });
                            },
                            child: InkWell(
                              onTap: val == null
                                  ? () {
                                      setState(() {
                                        _hoveredColIndex = c;
                                        _hoveredRowIndex = r;
                                      });
                                    }
                                  : () => _onCellTap(
                                      rowLabel: rLabel,
                                      fullColLabel: fullLabel,
                                      currentVal: val,
                                      realStats: realInfo,
                                    ),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: _heatBg(val),
                                  borderRadius: BorderRadius.circular(8),
                                  border: isCellHovered
                                      ? Border.all(
                                          color: const Color(0xFF0F172A),
                                          width: 1.8,
                                        )
                                      : (isSimulated
                                            ? Border.all(
                                                color: const Color(0xFFD97706),
                                                width: 1.5,
                                              )
                                            : null),
                                ),
                                alignment: Alignment.center,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      val == null
                                          ? '—'
                                          : '%${val.toStringAsFixed(0)}',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                        color: _heatFg(val),
                                      ),
                                    ),
                                    if (isSimulated)
                                      Text(
                                        'Simüle',
                                        style: GoogleFonts.inter(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFFB45309),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    );
                  }),
                ],
              ),
            ),
          const SizedBox(height: 14),
          // ALTTA TAM KAZANIM METNİ OKUMA KUTUSU (FARE ÜZERİNE GELDİĞİNDE ANINDA GÜNCELLENİR)
          _buildHoveredOutcomeFooter(
            data: data,
            hoveredCol: safeHoveredCol,
            hoveredRow: safeHoveredRow,
          ),
        ],
      ),
    );
  }

  /// İnteraktif Kazanım Sütun Grafiği (üzerine fareyle gelindiğinde alttaki tam metin şeridini günceller)
  Widget _buildInteractiveOutcomeBarChart(
    _HeatmapDataBundle data,
    int? safeHoveredCol,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(data.colLabels.length, (c) {
            final summary = _columnSummary(data, c);
            final pct = (summary.avgPct ?? 0.0).clamp(0.0, 100.0);
            final barColor = _heatFg(summary.avgPct);
            final isHovered = safeHoveredCol == c;

            return MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) {
                setState(() {
                  _hoveredColIndex = c;
                  _hoveredRowIndex = null;
                });
              },
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _hoveredColIndex = c;
                    _hoveredRowIndex = null;
                  });
                },
                child: Tooltip(
                  message: data.fullColLabels[c],
                  waitDuration: const Duration(milliseconds: 250),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 82,
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isHovered
                          ? const Color(0xFFFFFBEB)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isHovered
                            ? const Color(0xFFF59E0B)
                            : Colors.transparent,
                        width: 1.4,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          summary.avgPct == null
                              ? '—'
                              : '%${pct.toStringAsFixed(0)}',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: barColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 135,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: isHovered ? 34 : 28,
                              height: summary.avgPct == null
                                  ? 6
                                  : (135.0 * (pct / 100.0)).clamp(8.0, 135.0),
                              decoration: BoxDecoration(
                                color: barColor.withValues(
                                  alpha: isHovered ? 1.0 : 0.82,
                                ),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(8),
                                  bottom: Radius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 32,
                          child: Text(
                            data.colLabels[c],
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 10.4,
                              fontWeight: isHovered
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: isHovered
                                  ? const Color(0xFFB45309)
                                  : const Color(0xFF334155),
                              height: 1.2,
                            ),
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
    );
  }

  /// Tablonun / Grafiğin hemen altında yer alan Canlı Kazanım Tam Metin Okuma Şeridi
  Widget _buildHoveredOutcomeFooter({
    required _HeatmapDataBundle data,
    required int? hoveredCol,
    required int? hoveredRow,
  }) {
    if (hoveredCol == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            const Icon(Icons.mouse_rounded, size: 18, color: Color(0xFF64748B)),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'Kısaltılmış kazanım / başlık metninin tamamını burada okumak için fareyle yukarıdaki sütunların, grafik çubuklarının veya hücrelerin üzerine gelin.',
                style: GoogleFonts.inter(
                  fontSize: 12.2,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF475569),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final fullTitle = data.fullColLabels[hoveredCol];
    String scopeBadge;
    String statsText;
    double? displayPct;

    if (hoveredRow != null) {
      final rLabel = data.rowLabels[hoveredRow];
      displayPct = data.matrix[hoveredRow][hoveredCol];
      final realInfo = data.realCellDetails[_overrideKey(rLabel, fullTitle)];
      scopeBadge = '$rLabel Şubesi';
      if (realInfo != null) {
        statsText = _sourceMode == 'written_class'
            ? '${realInfo.examCount} Yazılı Ortalaması: %${realInfo.realPct.toStringAsFixed(1)}'
            : '${realInfo.correct} / ${realInfo.total} Doğru • Başarı: %${(displayPct ?? realInfo.realPct).toStringAsFixed(1)}';
      } else {
        statsText = displayPct == null
            ? 'Veri yok'
            : 'Başarı: %${displayPct.toStringAsFixed(1)}';
      }
    } else {
      final colSum = _columnSummary(data, hoveredCol);
      displayPct = colSum.avgPct;
      scopeBadge = 'Kurum Geneli (${data.rowLabels.length} Şube)';
      if (colSum.avgPct != null) {
        statsText = (_sourceMode != 'written_class' && colSum.totalQ > 0)
            ? 'Toplam ${colSum.totalCor} / ${colSum.totalQ} Doğru • Ortalama Başarı: %${colSum.avgPct!.toStringAsFixed(1)}'
            : 'Ortalama Başarı: %${colSum.avgPct!.toStringAsFixed(1)}';
      } else {
        statsText = 'Veri yok';
      }
    }

    final accentFg = _heatFg(displayPct);
    final accentBg = _heatBg(displayPct);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFF59E0B), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFD97706),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'KAZANIM / BAŞLIK TAM METNİ (${hoveredCol + 1}/${data.fullColLabels.length})',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  scopeBadge,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1E293B),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accentBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statsText,
                  style: GoogleFonts.inter(
                    fontSize: 11.2,
                    fontWeight: FontWeight.w800,
                    color: accentFg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            fullTitle,
            style: GoogleFonts.inter(
              fontSize: 13.4,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  void _onCellTap({
    required String rowLabel,
    required String fullColLabel,
    required double currentVal,
    required _CellRealStats? realStats,
  }) {
    final oKey = _overrideKey(rowLabel, fullColLabel);
    double temp = currentVal;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            '$rowLabel • Kazanım / Başlık Detayı',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              fontSize: 15.5,
            ),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Text(
                    fullColLabel,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.8,
                      color: const Color(0xFF92400E),
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (realStats != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gerçek Sınav Verisi: %${realStats.realPct.toStringAsFixed(1)}',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _sourceMode == 'written_class'
                              ? '${realStats.examCount} yazılı sınavın gerçek not ortalaması'
                              : '${realStats.examCount} sınavda toplam ${realStats.total} soruda ${realStats.correct} doğru yanıt',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                Text(
                  'Zümre Hedef / Telafi Simülasyonu: %${temp.toStringAsFixed(0)}',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: _heatFg(temp),
                  ),
                ),
                Slider(
                  value: temp.clamp(0.0, 100.0),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  activeColor: const Color(0xFFD97706),
                  onChanged: (v) => setModal(() => temp = v),
                ),
                Text(
                  'Not: Değişiklik yaptığınızda yalnızca bu oturumda "Simüle" etiketiyle gösterilir; istediğiniz an gerçek veriye sıfırlayabilirsiniz.',
                  style: GoogleFonts.inter(
                    fontSize: 11.2,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (_simulationOverrides.containsKey(oKey))
              TextButton(
                onPressed: () {
                  setState(() => _simulationOverrides.remove(oKey));
                  Navigator.pop(ctx);
                },
                child: const Text('Gerçek Veriye Dön'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Kapat'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
              ),
              onPressed: () {
                setState(() => _simulationOverrides[oKey] = temp);
                Navigator.pop(ctx);
              },
              child: const Text('Simülasyonu Uygula'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemedialActionCard(
    List<({String label, double pct, String action})> weakHighlights,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.medical_services_rounded,
                color: Color(0xFFDC2626),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Otomatik Telafi Etüdü & Konu Tekrarı Önerileri (${weakHighlights.length})',
                  style: GoogleFonts.inter(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (weakHighlights.isEmpty)
            Text(
              'Seçili eşik (%${_remedialThreshold.toStringAsFixed(0)}) altında kalan kritik şube veya kazanım bulunmuyor.',
              style: GoogleFonts.inter(
                color: const Color(0xFF047857),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            )
          else
            ...weakHighlights
                .take(15)
                .map(
                  (w) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '%${w.pct.toStringAsFixed(0)}',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                w.label,
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: const Color(0xFF7F1D1D),
                                ),
                              ),
                              Text(
                                w.action,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFF991B1B),
                                ),
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
    );
  }
}
