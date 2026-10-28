import 'package:edukn/models/assessment/trial_exam_model.dart';

import '../models/odak_models.dart';

/// ODAK-64 çekirdek hesaplama mantığı. Tamamen deterministik, kural tabanlıdır.
class OdakEngine {
  OdakEngine._();

  // ─── AĞIRLIKLAR ──────────────────────────────────────────────────────────

  /// Varsayılan ağırlıklar: Matematik %60, Türkçe %40. Bu dersler yoksa eşit dağıtır.
  static Map<String, int> defaultWeights(List<String> subjects) {
    if (subjects.isEmpty) return {};
    String? mat;
    String? tr;
    for (final s in subjects) {
      final n = s.toLowerCase();
      if (mat == null && n.contains('mat')) mat = s;
      if (tr == null && (n.contains('türk') || n.contains('turk'))) tr = s;
    }
    final result = <String, int>{for (final s in subjects) s: 0};
    if (mat != null && tr != null) {
      result[mat] = 60;
      result[tr] = 40;
      return result;
    }
    final base = 100 ~/ subjects.length;
    var rest = 100 - base * subjects.length;
    for (final s in subjects) {
      result[s] = base + (rest > 0 ? 1 : 0);
      if (rest > 0) rest--;
    }
    return result;
  }

  /// Bir slider değiştiğinde diğerlerini orantılı olarak ayarlar. Toplam daima 100'dür.
  static Map<String, int> rebalance(
    Map<String, int> current,
    String changed,
    int newValue,
  ) {
    final keys = current.keys.toList();
    if (keys.length <= 1) return {for (final k in keys) k: 100};

    final value = newValue.clamp(0, 100);
    final others = keys.where((k) => k != changed).toList();
    final remaining = 100 - value;
    final otherSum = others.fold<int>(0, (s, k) => s + current[k]!);

    final result = <String, int>{changed: value};
    var assigned = 0;
    for (final k in others) {
      final v = otherSum > 0
          ? (current[k]! * remaining / otherSum).floor()
          : (remaining / others.length).floor();
      result[k] = v;
      assigned += v;
    }

    var diff = remaining - assigned;
    final order = [...others]
      ..sort((a, b) => current[b]!.compareTo(current[a]!));
    var i = 0;
    while (diff > 0 && order.isNotEmpty) {
      final k = order[i % order.length];
      result[k] = result[k]! + 1;
      diff--;
      i++;
    }

    // Orijinal anahtar sırasını koru.
    return {for (final k in keys) k: result[k]!};
  }

  // ─── SKOR VE SIRALAMA ────────────────────────────────────────────────────

  /// Öğrencinin ağırlıklı OdakScore değeri (0..100).
  static double calcOdakScore(OdakExamResult r, Map<String, int> weights) {
    var score = 0.0;
    weights.forEach((subject, w) {
      if (w <= 0) return;
      final stat = r.subjects[subject];
      final success = stat?.successRate ?? 0.0;
      score += (w / 100.0) * success * 100.0;
    });
    return score;
  }

  /// OdakScore'a göre büyükten küçüğe sıralar.
  static List<OdakRankedStudent> rank(
    List<OdakExamResult> results,
    Map<String, int> weights,
  ) {
    final scored = results
        .map((r) => MapEntry(r, calcOdakScore(r, weights)))
        .toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.student.name.compareTo(b.key.student.name);
      });
    return [
      for (var i = 0; i < scored.length; i++)
        OdakRankedStudent(
          result: scored[i].key,
          score: scored[i].value,
          rank: i + 1,
        ),
    ];
  }

  /// Sınıf adı üretir: A..Z, sonra AA, AB ...
  static String className(int index) {
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    var n = index;
    var s = '';
    do {
      s = letters[n % 26] + s;
      n = n ~/ 26 - 1;
    } while (n >= 0);
    return s;
  }

  /// Sıralı öğrencileri sınıf mevcuduna göre A, B, C ... sınıflarına böler.
  static List<OdakClassGroup> split(
    List<OdakRankedStudent> ranked,
    int maxSize,
  ) {
    final size = maxSize < 1 ? 1 : maxSize;
    final groups = <OdakClassGroup>[];
    for (var i = 0; i < ranked.length; i += size) {
      final end = (i + size > ranked.length) ? ranked.length : i + size;
      groups.add(
        OdakClassGroup(
          id: className(groups.length),
          students: ranked.sublist(i, end),
        ),
      );
    }
    return groups;
  }

  /// Şube etiketi: "7-A" gibi. Şube bilgisi yoksa "Şubesiz".
  static String branchLabel(OdakStudent s) {
    final b = s.branch.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final lvl = s.classLevel.trim().replaceAll(RegExp(r'\s+'), '');
    if (b.isEmpty && lvl.isEmpty) return 'Şubesiz';
    if (b.isEmpty) return lvl;
    // "708" gibi seviye+şube içeren tam şube kodları olduğu gibi kalır; böylece
    // manuel yüklenen öğrencide classLevel farklı olsa da aynı şubede toplanır.
    if (RegExp(r'^\d{3,}$').hasMatch(b)) return b;
    if (lvl.isEmpty || b.startsWith(lvl) || b.contains('-') || b.contains('/')) {
      return b;
    }
    return '$lvl-$b';
  }

  /// Yeni sınıf OLUŞTURMAZ: öğrenciler kendi şubelerinde kalır. Her şubede
  /// öğrenciler [weights] ile hesaplanan puana göre kendi içinde sıralanır.
  static List<OdakClassGroup> groupByBranch(
    List<OdakExamResult> results,
    Map<String, int> weights,
  ) {
    final byBranch = <String, List<OdakExamResult>>{};
    for (final r in results) {
      byBranch.putIfAbsent(branchLabel(r.student), () => []).add(r);
    }
    final labels = byBranch.keys.toList()..sort();
    return [
      for (final label in labels)
        OdakClassGroup(
          id: label,
          displayName: 'Şube $label',
          students: rank(byBranch[label]!, weights),
        ),
    ];
  }

  /// Performans Özeti: kurlu derslerde (ör. İngilizce) şube yerine KUR kullanılır.
  /// - Her şube yalnızca kurlu OLMAYAN dersleri kapsar.
  /// - Her kur, yalnızca kendi dersini kapsayan ayrı bir grup olur.
  /// [slotLabelFor]: (öğrenciId, ders) -> kur etiketi (yoksa null).
  static List<OdakClassGroup> groupByBranchWithTracks(
    List<OdakExamResult> results,
    Map<String, int> weights, {
    required bool Function(String subject) isTrackSubject,
    required String? Function(String studentId, String subject) slotLabelFor,
  }) {
    final trackSubjects = {
      for (final e in weights.entries)
        if (e.value > 0 && isTrackSubject(e.key)) e.key,
    };
    if (trackSubjects.isEmpty) return groupByBranch(results, weights);

    Map<String, int> scaled(Set<String> keep) {
      final sub = {
        for (final e in weights.entries)
          if (keep.contains(e.key) && e.value > 0) e.key: e.value,
      };
      final sum = sub.values.fold<int>(0, (a, b) => a + b);
      if (sum <= 0) return sub;
      return {for (final e in sub.entries) e.key: (e.value * 100 / sum).round()};
    }

    final groups = <OdakClassGroup>[];

    // 1) Şubeler (kurlu dersler hariç)
    final branchSubjects = {
      for (final k in weights.keys)
        if (!trackSubjects.contains(k)) k,
    };
    final branchWeights = scaled(branchSubjects);
    if (branchWeights.isNotEmpty) {
      final byBranch = <String, List<OdakExamResult>>{};
      for (final r in results) {
        byBranch.putIfAbsent(branchLabel(r.student), () => []).add(r);
      }
      final labels = byBranch.keys.toList()..sort();
      for (final label in labels) {
        groups.add(OdakClassGroup(
          id: label,
          displayName: 'Şube $label',
          students: rank(byBranch[label]!, branchWeights),
          excludeSubjects: trackSubjects,
        ));
      }
    }

    // 2) Kurlar (her kurlu ders için)
    for (final subject in trackSubjects) {
      final byTrack = <String, List<OdakExamResult>>{};
      for (final r in results) {
        final label = slotLabelFor(r.student.id, subject) ??
            '$subject • Kura atanmamış';
        byTrack.putIfAbsent(label, () => []).add(r);
      }
      final labels = byTrack.keys.toList()..sort();
      for (final label in labels) {
        groups.add(OdakClassGroup(
          id: 'KUR::$label',
          displayName: 'Kur $label',
          students: rank(byTrack[label]!, {subject: 100}),
          onlySubjects: {subject},
        ));
      }
    }
    return groups;
  }
}

class _QStat {
  final String subject;
  final int index;
  int total = 0;
  int empty = 0;
  int correct = 0;
  String outcome = '';
  final Map<String, int> wrongOptions = {};
  final Map<String, int> refCounts = {};

  _QStat(this.subject, this.index);

  int get questionNo => index + 1;

  String get correctOption {
    var best = '';
    var bestCount = 0;
    refCounts.forEach((k, v) {
      if (v > bestCount) {
        best = k;
        bestCount = v;
      }
    });
    return best;
  }
}

/// Sınıf bazlı veri madenciliği. Fonksiyonlar `classId` ile çağrılır.
class OdakAnalyzer {
  final List<OdakClassGroup> groups;
  final Map<String, int> weights;
  final Map<String, Map<String, List<String>>> outcomes;
  final int weeks;
  final int hoursPerWeek;

  /// false ise raporlarda haftalık aksiyon planı bölümü üretilmez/gösterilmez.
  final bool showActionPlan;

  /// Kullanıcının seçtiği dersler ve haftalık saatleri. Boşsa ağırlıklara göre bölünür.
  final Map<String, int> lessonHours;

  /// Bir yanlış şıkkın "tuzak" sayılması için sınıf içindeki asgari oran.
  static const double distractorThreshold = 0.40;

  /// Sınıf ortalamasının bu oranda altı "riskli" sayılır.
  static const double riskGap = 0.20;

  /// Doluysa (0..100) bu başarı puanının ALTINDAKİ öğrenciler riskli sayılır
  /// (ODAK-64: %50). Boşsa sınıf ortalamasının [riskGap] kadar altı riskli olur
  /// (Performans Özeti).
  final double? riskBelowScore;

  /// Raporlarda kullanılan risk tanımı metni.
  String get riskRuleText => riskBelowScore != null
      ? '%${riskBelowScore!.toStringAsFixed(0)} başarının altında'
      : 'sınıf ortalamasının %20 ve daha fazla altında';

  final Map<String, Map<String, _QStat>> _cache = {};

  OdakAnalyzer({
    required this.groups,
    required this.weights,
    required this.outcomes,
    required this.weeks,
    required this.hoursPerWeek,
    this.lessonHours = const {},
    this.riskBelowScore,
    this.showActionPlan = true,
  });

  OdakClassGroup _group(String classId) =>
      groups.firstWhere((g) => g.id == classId);

  Map<String, _QStat> _stats(String classId) =>
      _cache.putIfAbsent(classId, () => _buildStats(_group(classId)));

  bool _meaningful(String o) => o.isNotEmpty && o != '-';

  String _outcomeFor(OdakExamResult r, String subject, int i) {
    List<String>? list = outcomes[r.bookletLetter]?[subject];
    if (list == null) {
      for (final m in outcomes.values) {
        final l = m[subject];
        if (l != null) {
          list = l;
          break;
        }
      }
    }
    if (list == null || i >= list.length) return '';
    return list[i];
  }

  Map<String, _QStat> _buildStats(OdakClassGroup group) {
    final map = <String, _QStat>{};
    for (final rs in group.students) {
      final r = rs.result;
      // Analiz: sıralamada ağırlığı olan dersler + programda verilecek (seçilen) dersler.
      final analysed = <String>{
        for (final e in weights.entries)
          if (e.value > 0) e.key,
        for (final e in lessonHours.entries)
          if (e.value > 0) e.key,
      }.where((s) => group.filterSubjects([s]).isNotEmpty).toSet();
      for (final subject in analysed) {
        final ans = r.answers[subject] ?? '';
        final ref = r.correctAnswers[subject] ?? '';
        for (var i = 0; i < ref.length; i++) {
          final refChar = ref[i].toUpperCase();
          // İptal edilen / sayılmayan sorular analize girmez.
          if (refChar == 'S' || refChar == 'X' || refChar == '#') continue;
          final sChar = i < ans.length ? ans[i] : ' ';
          final status = TrialExam.evaluateAnswer(sChar, refChar);
          final q = map.putIfAbsent('$subject#$i', () => _QStat(subject, i));
          q.total++;
          q.refCounts[refChar] = (q.refCounts[refChar] ?? 0) + 1;
          if (q.outcome.isEmpty) q.outcome = _outcomeFor(r, subject, i);
          switch (status) {
            case AnswerStatus.empty:
              q.empty++;
              break;
            case AnswerStatus.correct:
              q.correct++;
              break;
            case AnswerStatus.wrong:
              final key = sChar.toUpperCase();
              q.wrongOptions[key] = (q.wrongOptions[key] ?? 0) + 1;
              break;
          }
        }
      }
    }
    return map;
  }

  /// O sınıfın en çok boş bıraktığı 3 soru (ve bağlı kazanımı).
  List<OdakEmptyQuestion> getMostEmptyQuestions(
    String classId, {
    int top = 3,
    String? subject,
  }) {
    final list = _stats(classId)
        .values
        .where((q) => q.empty > 0 && (subject == null || q.subject == subject))
        .toList()
      ..sort((a, b) {
        final ra = a.empty / a.total;
        final rb = b.empty / b.total;
        final c = rb.compareTo(ra);
        return c != 0 ? c : b.empty.compareTo(a.empty);
      });
    return list
        .take(top)
        .map(
          (q) => OdakEmptyQuestion(
            subject: q.subject,
            questionNo: q.questionNo,
            outcome: q.outcome,
            emptyCount: q.empty,
            total: q.total,
          ),
        )
        .toList();
  }

  /// Bir yanlış şık; doğru cevaptan ve diğer yanlışlardan fazla işaretlenmiş
  /// ve sınıfın %40'ından fazlası tarafından seçilmişse "çeldirici tuzağı" sayılır.
  List<OdakDistractorFinding> getMostFallenDistractor(
    String classId, {
    int top = 5,
    String? subject,
  }) {
    final findings = <OdakDistractorFinding>[];
    for (final q in _stats(classId).values) {
      if (subject != null && q.subject != subject) continue;
      if (q.total == 0 || q.wrongOptions.isEmpty) continue;
      final sorted = q.wrongOptions.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top1 = sorted.first;
      final secondCount = sorted.length > 1 ? sorted[1].value : 0;
      final share = top1.value / q.total;
      if (share >= distractorThreshold &&
          top1.value > q.correct &&
          top1.value > secondCount) {
        findings.add(
          OdakDistractorFinding(
            subject: q.subject,
            questionNo: q.questionNo,
            outcome: q.outcome,
            option: top1.key,
            correctOption: q.correctOption,
            count: top1.value,
            correctCount: q.correct,
            total: q.total,
          ),
        );
      }
    }
    findings.sort((a, b) => b.ratio.compareTo(a.ratio));
    return findings.take(top).toList();
  }

  /// Riskli öğrenciler: eşik tanımlıysa eşiğin altı, değilse sınıf ortalamasının %20 altı.
  List<OdakRiskStudent> getStudentWarnings(String classId) {
    final g = _group(classId);
    final avg = g.avgScore;
    if (avg <= 0) return [];
    final limit = riskBelowScore ?? avg * (1 - riskGap);
    final list = g.students
        .where((s) => riskBelowScore != null ? s.score < limit : s.score <= limit)
        .map((s) => OdakRiskStudent(ranked: s, classAvg: avg))
        .toList()
      ..sort((a, b) => a.ranked.score.compareTo(b.ranked.score));
    return list;
  }

  /// Sınıfın en zayıf kazanımları (başarı oranı düşükten yükseğe).
  List<OdakWeakOutcome> getWeakOutcomes(
    String classId, {
    int top = 5,
    String? subject,
  }) {
    final agg = <String, List<int>>{}; // key -> [correct, total, questionCount]
    final subjectOf = <String, String>{};
    for (final q in _stats(classId).values) {
      if (subject != null && q.subject != subject) continue;
      final label = _meaningful(q.outcome)
          ? q.outcome
          : '${q.subject} ${q.questionNo}. soru (kazanım tanımsız)';
      final key = '${q.subject}||$label';
      subjectOf[key] = q.subject;
      final a = agg.putIfAbsent(key, () => [0, 0, 0]);
      a[0] += q.correct;
      a[1] += q.total;
      a[2] += 1;
    }
    final list = agg.entries
        .where((e) => e.value[1] > 0)
        .map(
          (e) => OdakWeakOutcome(
            subject: subjectOf[e.key]!,
            label: e.key.split('||').last,
            successRate: e.value[0] / e.value[1],
            questionCount: e.value[2],
          ),
        )
        .toList()
      ..sort((a, b) => a.successRate.compareTo(b.successRate));
    return list.take(top).toList();
  }

  Map<String, int> _hourSplit() {
    if (lessonHours.isNotEmpty) {
      return {
        for (final e in lessonHours.entries)
          if (e.value > 0) e.key: e.value,
      };
    }
    final active = weights.entries.where((e) => e.value > 0).toList();
    final result = <String, int>{};
    if (active.isEmpty || hoursPerWeek <= 0) return result;
    final raws = {for (final e in active) e.key: hoursPerWeek * e.value / 100.0};
    var assigned = 0;
    for (final e in raws.entries) {
      result[e.key] = e.value.floor();
      assigned += result[e.key]!;
    }
    var diff = hoursPerWeek - assigned;
    final order = raws.entries.toList()
      ..sort(
        (a, b) => (b.value - b.value.floor()).compareTo(a.value - a.value.floor()),
      );
    var i = 0;
    while (diff > 0 && order.isNotEmpty) {
      final k = order[i % order.length].key;
      result[k] = result[k]! + 1;
      diff--;
      i++;
    }
    return result;
  }

  /// Sınıfın bir dersteki ortalama başarı oranı (0..1, net bazlı).
  double subjectClassRate(String classId, String subject) {
    final rates = _group(classId)
        .students
        .map((s) => s.result.subjects[subject])
        .whereType<OdakSubjectStat>()
        .map((s) => s.successRate)
        .toList();
    if (rates.isEmpty) return 0;
    return rates.reduce((a, b) => a + b) / rates.length;
  }

  /// Sınıfın bir dersteki toplam doğru/yanlış/boş ortalamaları.
  OdakSubjectStat subjectTotals(String classId, String subject) {
    var c = 0, w = 0, e = 0;
    var net = 0.0;
    for (final s in _group(classId).students) {
      final st = s.result.subjects[subject];
      if (st == null) continue;
      c += st.correct;
      w += st.wrong;
      e += st.empty;
      net += st.net;
    }
    return OdakSubjectStat(correct: c, wrong: w, empty: e, net: net);
  }

  /// O dersteki sınıf ortalamasının %20 ve daha fazla altında kalan öğrenciler.
  List<OdakSubjectRisk> getSubjectWarnings(String classId, String subject) {
    final avg = subjectClassRate(classId, subject);
    if (avg <= 0) return [];
    final limit = riskBelowScore != null ? riskBelowScore! / 100 : avg * (1 - riskGap);
    final list = <OdakSubjectRisk>[];
    for (final s in _group(classId).students) {
      final st = s.result.subjects[subject];
      if (st == null) continue;
      final isRisk = riskBelowScore != null
          ? st.successRate < limit
          : st.successRate <= limit;
      if (isRisk) {
        list.add(OdakSubjectRisk(
          name: s.student.name,
          rate: st.successRate,
          classRate: avg,
        ));
      }
    }
    list.sort((a, b) => a.rate.compareTo(b.rate));
    return list;
  }

  /// Bir dersin tüm soruları için sınıf bazlı istatistik (soru sırasıyla).
  List<OdakQuestionStat> questionStats(String classId, String subject) {
    final list = _stats(classId)
        .values
        .where((q) => q.subject == subject)
        .map((q) {
      String topWrong = '';
      var topWrongCount = 0;
      q.wrongOptions.forEach((k, v) {
        if (v > topWrongCount) {
          topWrong = k;
          topWrongCount = v;
        }
      });
      final wrong = q.total - q.correct - q.empty;
      return OdakQuestionStat(
        questionNo: q.questionNo,
        outcome: _meaningful(q.outcome) ? q.outcome : '',
        total: q.total,
        correct: q.correct,
        wrong: wrong < 0 ? 0 : wrong,
        empty: q.empty,
        correctOption: q.correctOption,
        topWrongOption: topWrong,
        topWrongCount: topWrongCount,
      );
    }).toList()
      ..sort((a, b) => a.questionNo.compareTo(b.questionNo));
    return list;
  }

  /// Sınıftaki öğrencilerin bir dersteki sonuçları (net'e göre büyükten küçüğe).
  List<OdakStudentSubjectRow> subjectStudentRows(String classId, String subject) {
    final rows = <OdakStudentSubjectRow>[];
    for (final s in _group(classId).students) {
      final st = s.result.subjects[subject];
      if (st == null) continue;
      rows.add(OdakStudentSubjectRow(
        name: s.student.name,
        branch: s.student.branch,
        stat: st,
      ));
    }
    rows.sort((a, b) => b.stat.net.compareTo(a.stat.net));
    return rows;
  }

  /// Tüm sınıfların bir dersteki başarı oranı (karşılaştırma için).
  /// Yalnızca o dersi kapsayan gruplar karşılaştırılır: kurlu derste kurlar (702 vb.),
  /// diğer derslerde şubeler. Böylece kurlar ayrı birer sınıf gibi tabloyu uzatmaz.
  Map<String, double> subjectRatesByClass(String subject) => {
        for (final g in groups)
          if (g.filterSubjects([subject]).isNotEmpty)
            g.id: subjectClassRate(g.id, subject),
      };

  /// Karmaşık grup kimliği yerine ekranda gösterilecek kısa ad (ör. "702").
  String groupLabel(String id) => _group(id).shortLabel;

  /// Tüm sınavdaki (bütün sınıflar) bir ders ortalaması.
  double subjectOverallRate(String subject) {
    final rates = <double>[];
    for (final g in groups) {
      if (g.filterSubjects([subject]).isEmpty) continue;
      for (final s in g.students) {
        final st = s.result.subjects[subject];
        if (st != null) rates.add(st.successRate);
      }
    }
    if (rates.isEmpty) return 0;
    return rates.reduce((a, b) => a + b) / rates.length;
  }

  /// Tek bir ders için, o sınıfın öğretmenine verilecek haftalık aksiyon planı.
  OdakActionPlan buildSubjectPlan(String classId, String subject) {
    final g = _group(classId);
    final weak = getWeakOutcomes(classId, top: 5, subject: subject);
    final empties = getMostEmptyQuestions(classId, subject: subject);
    final distractors = getMostFallenDistractor(classId, subject: subject);
    final risky = getSubjectWarnings(classId, subject);
    final hrs = lessonHours[subject] ?? 0;
    final rate = subjectClassRate(classId, subject);

    final summary = <String>[
      hrs > 0
          ? '$subject: haftada $hrs saat × $weeks hafta = ${hrs * weeks} ders saati.'
          : '$subject: $weeks haftalık çalışma planı.',
      '${g.name} $subject başarısı: %${(rate * 100).round()} • ${g.students.length} öğrenci.',
      if (empties.isNotEmpty)
        'En çok boş bırakılan: ${empties.first.questionNo}. soru '
            '(sınıfın %${(empties.first.ratio * 100).round()}\'i). '
            '"Tahmin ve eleme" tekniği çalışılsın.',
      if (risky.isNotEmpty)
        '${risky.length} öğrenci ${riskBelowScore != null ? 'ders başarısı %${riskBelowScore!.toStringAsFixed(0)} altında' : 'ders ortalamasının %20 altında'}: birebir geri bildirim ve ek ödev planlanmalı.',
    ];

    final weekPlans = <OdakWeekPlan>[];
    for (var w = 1; w <= weeks; w++) {
      final progress = w / weeks;
      final isLast = weeks >= 3 && w == weeks;
      String detail;
      if (isLast) {
        detail = 'Kapanış haftası: $subject zayıf kazanımlarının genel tekrarı, '
            'süreli mini deneme ve riskli öğrencilerle birebir geri bildirim.';
      } else if (weak.isEmpty) {
        detail = '$subject genel soru çözümü ve yanlış analizi.';
      } else {
        final focus = weak[(w - 1) % weak.length];
        final pct = (focus.successRate * 100).round();
        final target = '${focus.label} (sınıf başarısı %$pct)';
        if (progress <= 0.4) {
          detail = 'Konu anlatımı ve temel alıştırmalar: $target.';
        } else if (progress <= 0.8) {
          detail = 'Yanlış kalıplarına odaklı soru çözümü: $target.';
          if (distractors.isNotEmpty) {
            final d = distractors[(w - 1) % distractors.length];
            detail += ' Dikkat: ${d.questionNo}. soruda ${d.option} şıkkı '
                'sınıfın %${(d.ratio * 100).round()}\'i tarafından işaretlendi; '
                'doğru cevap ${d.correctOption.isEmpty ? '?' : d.correctOption}. '
                'Çeldirici ayrımı tahtada gösterilsin.';
          }
        } else {
          detail = 'Karma soru bankası ve süre tutarak çözüm: $target.';
        }
      }
      weekPlans.add(OdakWeekPlan(week: w, detail: detail));
    }
    return OdakActionPlan(summary: summary, weeks: weekPlans);
  }

  /// Öğretmene verilecek kural tabanlı haftalık aksiyon planı.
  OdakActionPlan buildActionPlan(String classId) {
    final g = _group(classId);
    var weak = getWeakOutcomes(classId, top: 1000);
    if (lessonHours.isNotEmpty) {
      weak = weak.where((w) => (lessonHours[w.subject] ?? 0) > 0).toList();
    }
    weak = weak.take(5).toList();
    final empties = getMostEmptyQuestions(classId);
    final distractors = getMostFallenDistractor(classId);
    final risky = getStudentWarnings(classId);
    final hours = _hourSplit();

    final summary = <String>[
      'Program: $weeks hafta × $hoursPerWeek saat = ${weeks * hoursPerWeek} ders saati.',
      if (hours.isNotEmpty)
        'Toplam: ${hours.entries.map((e) => '${e.key} ${e.value * weeks} saat').join(', ')}.',
      if (hours.isNotEmpty)
        'Haftalık saat dağılımı: ${hours.entries.map((e) => '${e.key} ${e.value} saat').join(', ')}.',
      'Sınıf ortalaması: ${g.avgScore.toStringAsFixed(1)} • Mevcut: ${g.students.length} öğrenci.',
      if (empties.isNotEmpty)
        'Boş bırakma yüksek: ${empties.first.subject} ${empties.first.questionNo}. soruda '
            'sınıfın %${(empties.first.ratio * 100).round()}\'i boş bıraktı. '
            'Çekingenlik/süre yönetimi için "tahmin ve eleme" tekniği çalışılsın.',
      if (risky.isNotEmpty)
        '${risky.length} riskli öğrenci var: haftalık birebir geri bildirim ve ek ödev planlanmalı.',
    ];

    final weekPlans = <OdakWeekPlan>[];
    for (var w = 1; w <= weeks; w++) {
      final progress = w / weeks;
      final isLast = weeks >= 3 && w == weeks;
      String detail;
      if (isLast) {
        detail =
            'Kapanış haftası: Tüm zayıf kazanımların genel tekrarı, süreli mini deneme '
            've riskli öğrencilerle birebir geri bildirim.';
      } else if (weak.isEmpty) {
        detail = 'Genel soru çözümü ve yanlış analizi.';
      } else {
        final focus = weak[(w - 1) % weak.length];
        final pct = (focus.successRate * 100).round();
        final target =
            '${focus.label} (${focus.subject}, sınıf başarısı %$pct)';
        if (progress <= 0.4) {
          detail = 'Konu anlatımı ve temel alıştırmalar: $target.';
        } else if (progress <= 0.8) {
          detail = 'Yanlış kalıplarına odaklı soru çözümü: $target.';
          if (distractors.isNotEmpty) {
            final d = distractors[(w - 1) % distractors.length];
            detail +=
                ' Dikkat: ${d.subject} ${d.questionNo}. soruda ${d.option} şıkkı '
                'sınıfın %${(d.ratio * 100).round()}\'i tarafından işaretlendi; '
                'doğru cevap ${d.correctOption.isEmpty ? '?' : d.correctOption}. '
                'Çeldirici ayrımı tahtada gösterilsin.';
          }
        } else {
          detail = 'Karma soru bankası ve süre tutarak çözüm: $target.';
        }
      }
      weekPlans.add(OdakWeekPlan(week: w, detail: detail));
    }

    return OdakActionPlan(summary: summary, weeks: weekPlans);
  }
}
