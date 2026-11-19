import '../../evaluation_models.dart';

/// ODAK-64 modelleri.
/// Not: Projede başka yerlerde `Student` / `ClassGroup` gibi isimler olabileceği için
/// çakışmayı önlemek adına tüm sınıflar `Odak` önekiyle tanımlanmıştır.

/// Öğrenci kimliği.
class OdakStudent {
  final String id;
  final String name;
  final String branch;
  final String classLevel;

  const OdakStudent({
    required this.id,
    required this.name,
    this.branch = '',
    this.classLevel = '',
  });
}

/// Bir ders için doğru / yanlış / boş istatistiği.
class OdakSubjectStat {
  final int correct;
  final int wrong;
  final int empty;
  final double net;

  const OdakSubjectStat({
    required this.correct,
    required this.wrong,
    required this.empty,
    required this.net,
  });

  int get total => correct + wrong + empty;

  /// 0..1 aralığında net başarı oranı.
  double get successRate =>
      total == 0 ? 0.0 : (net / total).clamp(0.0, 1.0).toDouble();
}

/// Bir öğrencinin tek bir deneme sınavındaki sonucu.
class OdakExamResult {
  final OdakStudent student;
  final String booklet;
  final Map<String, OdakSubjectStat> subjects;

  /// Ders -> öğrencinin işaretlediği cevap dizisi.
  final Map<String, String> answers;

  /// Ders -> öğrencinin kitapçığına ait doğru cevap dizisi.
  final Map<String, String> correctAnswers;

  /// Tüm derslerin dahil olduğu sınav genel puanı (ör. LGS 500 tam puanı).
  final double examScore;

  /// Karnede kullanılmak üzere orijinal öğrenci sonuç kaydı.
  final StudentResult? rawStudentResult;

  const OdakExamResult({
    required this.student,
    required this.booklet,
    required this.subjects,
    required this.answers,
    required this.correctAnswers,
    this.examScore = 0.0,
    this.rawStudentResult,
  });

  /// Sınavdaki tüm derslerin toplam neti.
  double get totalNet =>
      subjects.values.fold<double>(0.0, (s, v) => s + v.net);

  /// Sınavdaki tüm derslerin toplam doğru sayısı.
  int get totalCorrect =>
      subjects.values.fold<int>(0, (s, v) => s + v.correct);

  /// Sınavdaki tüm derslerin toplam yanlış sayısı.
  int get totalWrong =>
      subjects.values.fold<int>(0, (s, v) => s + v.wrong);

  /// Birden fazla sınavın birleştirildiği sonuç mu? (kitapçık anahtarı '#' ile başlar)
  bool get isMerged => booklet.startsWith('#');

  String get bookletLetter => isMerged
      ? booklet
      : (booklet.isNotEmpty ? booklet[0] : 'A');

  /// Sınav karnesi (`StudentReportCardDialog`) için `StudentResult` nesnesi üretir.
  StudentResult toStudentResult() {
    if (rawStudentResult != null && !isMerged) {
      final raw = rawStudentResult!;
      return StudentResult(
        tcNo: raw.tcNo,
        studentNo: raw.studentNo,
        name: raw.name,
        classLevel: raw.classLevel,
        branch: raw.branch,
        booklet: raw.booklet,
        score: raw.score > 0 ? raw.score : examScore,
        rankGeneral: raw.rankGeneral,
        rankInstitution: raw.rankInstitution,
        rankBranch: raw.rankBranch,
        isMatched: raw.isMatched,
        systemStudentId: raw.systemStudentId,
        participatedSessions: Set<int>.from(raw.participatedSessions),
        subjects: subjects.map(
          (k, v) => MapEntry(
            k,
            SubjectStats(
              correct: v.correct,
              wrong: v.wrong,
              empty: v.empty,
              net: v.net,
            ),
          ),
        ),
        answers: Map<String, String>.from(answers),
        correctAnswers: Map<String, String>.from(correctAnswers),
      );
    }
    return StudentResult(
      tcNo: rawStudentResult?.tcNo ?? '',
      studentNo: rawStudentResult?.studentNo ?? '',
      name: student.name,
      classLevel: student.classLevel,
      branch: student.branch,
      booklet: booklet,
      score: examScore,
      rankGeneral: 0,
      rankInstitution: 0,
      rankBranch: 0,
      isMatched: rawStudentResult?.isMatched ?? false,
      systemStudentId: rawStudentResult?.systemStudentId ?? student.id,
      subjects: subjects.map(
        (k, v) => MapEntry(
          k,
          SubjectStats(
            correct: v.correct,
            wrong: v.wrong,
            empty: v.empty,
            net: v.net,
          ),
        ),
      ),
      answers: Map<String, String>.from(answers),
      correctAnswers: Map<String, String>.from(correctAnswers),
    );
  }

  factory OdakExamResult.fromStudentResult(StudentResult r) {
    final id = (r.systemStudentId != null && r.systemStudentId!.isNotEmpty)
        ? r.systemStudentId!
        : (r.tcNo.isNotEmpty ? r.tcNo : '${r.studentNo}|${r.name}');
    return OdakExamResult(
      student: OdakStudent(
        id: id,
        name: r.name,
        branch: r.branch,
        classLevel: r.classLevel,
      ),
      booklet: r.booklet,
      subjects: r.subjects.map(
        (k, v) => MapEntry(
          k,
          OdakSubjectStat(
            correct: v.correct,
            wrong: v.wrong,
            empty: v.empty,
            net: v.net,
          ),
        ),
      ),
      answers: Map<String, String>.from(r.answers),
      correctAnswers: Map<String, String>.from(r.correctAnswers),
      examScore: r.score,
      rawStudentResult: r,
    );
  }
}

/// OdakScore ile sıralanmış öğrenci.
class OdakRankedStudent {
  final OdakExamResult result;
  final double score; // 0..100
  final int rank; // 1'den başlar

  const OdakRankedStudent({
    required this.result,
    required this.score,
    required this.rank,
  });

  OdakStudent get student => result.student;
}

/// Oluşturulan sınıf (A, B, C ...).
class OdakClassGroup {
  final String id;
  final List<OdakRankedStudent> students;

  final String? displayName;

  /// Doluysa bu grup (ör. bir kur) yalnızca bu dersleri kapsar.
  final Set<String>? onlySubjects;

  /// Bu derslere bu grupta yer verilmez (ör. şubede kurlu dersler).
  final Set<String> excludeSubjects;

  const OdakClassGroup({
    required this.id,
    required this.students,
    this.displayName,
    this.onlySubjects,
    this.excludeSubjects = const {},
  });

  /// [subjects] listesini bu grubun kapsamına göre süzer.
  List<String> filterSubjects(List<String> subjects) => subjects
      .where((s) =>
          !excludeSubjects.contains(s) &&
          (onlySubjects == null || onlySubjects!.contains(s)))
      .toList();

  String get name => displayName ?? 'Sınıf $id';

  /// Karşılaştırma tablolarında kullanılan kısa ad: kurlarda yalnızca kur adı (ör. "702").
  String get shortLabel =>
      id.startsWith('KUR::') ? id.substring(5).split(' • ').last.trim() : id;

  bool get isTrack => id.startsWith('KUR::');

  static String _k(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  /// Bu şubeye bağlı kurlar (kur adı = şube adı). Kurlar şubenin içinde ilgili ders olarak gösterilir.
  static List<OdakClassGroup> linkedTracks(OdakClassGroup g, List<OdakClassGroup> all) {
    if (g.isTrack) return const [];
    return all.where((t) => t.isTrack && _k(t.shortLabel) == _k(g.id)).toList();
  }

  /// Listede ayrı gösterilecek gruplar: bir şubeye bağlanabilen kurlar gizlenir (şubenin içinde gösterilir).
  static List<OdakClassGroup> visibleGroups(List<OdakClassGroup> all) {
    final branchKeys = {for (final g in all) if (!g.isTrack) _k(g.id)};
    return all.where((g) => !(g.isTrack && branchKeys.contains(_k(g.shortLabel)))).toList();
  }

  double get avgScore => students.isEmpty
      ? 0.0
      : students.fold<double>(0.0, (s, e) => s + e.score) / students.length;
}

/// En çok boş bırakılan soru.
class OdakEmptyQuestion {
  final String subject;
  final int questionNo;
  final String outcome;
  final int emptyCount;
  final int total;

  const OdakEmptyQuestion({
    required this.subject,
    required this.questionNo,
    required this.outcome,
    required this.emptyCount,
    required this.total,
  });

  double get ratio => total == 0 ? 0.0 : emptyCount / total;
}

/// Sınıfın en çok tuzağa düştüğü çeldirici.
class OdakDistractorFinding {
  final String subject;
  final int questionNo;
  final String outcome;
  final String option;
  final String correctOption;
  final int count;
  final int correctCount;
  final int total;

  const OdakDistractorFinding({
    required this.subject,
    required this.questionNo,
    required this.outcome,
    required this.option,
    required this.correctOption,
    required this.count,
    required this.correctCount,
    required this.total,
  });

  double get ratio => total == 0 ? 0.0 : count / total;
}

/// Sınıf ortalamasının belirgin altında kalan öğrenci.
class OdakRiskStudent {
  final OdakRankedStudent ranked;
  final double classAvg;

  const OdakRiskStudent({required this.ranked, required this.classAvg});

  double get gapPercent =>
      classAvg == 0 ? 0.0 : ((classAvg - ranked.score) / classAvg) * 100;
}

/// Bir dersteki sınıf ortalamasının belirgin altında kalan öğrenci.
class OdakSubjectRisk {
  final String name;
  final double rate; // 0..1
  final double classRate; // 0..1
  final OdakRankedStudent? ranked;

  const OdakSubjectRisk({
    required this.name,
    required this.rate,
    required this.classRate,
    this.ranked,
  });

  double get gapPercent =>
      classRate == 0 ? 0.0 : ((classRate - rate) / classRate) * 100;
}

/// Bir sorunun sınıf bazlı istatistiği.
class OdakQuestionStat {
  final int questionNo;
  final String outcome;
  final int total;
  final int correct;
  final int wrong;
  final int empty;
  final String correctOption;
  final String topWrongOption;
  final int topWrongCount;

  const OdakQuestionStat({
    required this.questionNo,
    required this.outcome,
    required this.total,
    required this.correct,
    required this.wrong,
    required this.empty,
    required this.correctOption,
    required this.topWrongOption,
    required this.topWrongCount,
  });

  double get correctRate => total == 0 ? 0 : correct / total;
  double get wrongRate => total == 0 ? 0 : wrong / total;
  double get emptyRate => total == 0 ? 0 : empty / total;
}

/// Bir öğrencinin tek bir dersteki sonucu.
class OdakStudentSubjectRow {
  final String name;
  final String branch;
  final OdakSubjectStat stat;

  const OdakStudentSubjectRow({
    required this.name,
    required this.branch,
    required this.stat,
  });
}

/// Zayıf kazanım.
class OdakWeakOutcome {
  final String subject;
  final String label;
  final double successRate; // 0..1
  final int questionCount;

  const OdakWeakOutcome({
    required this.subject,
    required this.label,
    required this.successRate,
    required this.questionCount,
  });
}

class OdakWeekPlan {
  final int week;
  final String detail;
  const OdakWeekPlan({required this.week, required this.detail});
}

/// Öğretmene verilecek haftalık aksiyon planı.
class OdakActionPlan {
  final List<String> summary;
  final List<OdakWeekPlan> weeks;
  const OdakActionPlan({required this.summary, required this.weeks});
}
