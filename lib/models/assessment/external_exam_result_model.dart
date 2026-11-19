import 'package:cloud_firestore/cloud_firestore.dart';

/// Dış katılımlı sınavda bir sınıf seviyesinin (ör. 4. Sınıf) sınav tanımındaki tek bir ders.
class ExternalLevelSubject {
  final String name;
  final int questionCount;

  /// Cevap anahtarı: her soru için `A-E`; `#` = iptal soru (herkese doğru sayılır).
  final String answerKey;

  /// Puan hesabında ders katsayısı (varsayılan 1).
  final double coefficient;

  const ExternalLevelSubject({
    required this.name,
    required this.questionCount,
    this.answerKey = '',
    this.coefficient = 1,
  });

  bool get isKeyComplete => answerKey.length == questionCount && questionCount > 0;

  ExternalLevelSubject copyWith({
    String? name,
    int? questionCount,
    String? answerKey,
    double? coefficient,
  }) => ExternalLevelSubject(
    name: name ?? this.name,
    questionCount: questionCount ?? this.questionCount,
    answerKey: answerKey ?? this.answerKey,
    coefficient: coefficient ?? this.coefficient,
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'questionCount': questionCount,
    'answerKey': answerKey,
    'coefficient': coefficient,
  };

  factory ExternalLevelSubject.fromMap(Map<String, dynamic> m) =>
      ExternalLevelSubject(
        name: (m['name'] ?? '').toString(),
        questionCount: (m['questionCount'] as num?)?.toInt() ?? 0,
        answerKey: (m['answerKey'] ?? '').toString(),
        coefficient: (m['coefficient'] as num?)?.toDouble() ?? 1,
      );
}

/// Bir sınıf seviyesi için sınav tanımı.
///
/// Yeni yöntem: Deneme Sınavları modülündeki hazır bir deneme sınavına bağlanır
/// (`trialExamId`). Optik form, oturumlar ve cevap anahtarı o denemeden okunur.
/// Eski yöntem (elle optik form + cevap anahtarı) geriye dönük uyumluluk için korunur.
class ExternalLevelDefinition {
  final String opticalFormId;
  final String opticalFormName;
  final List<ExternalLevelSubject> subjects;

  /// "N yanlış 1 doğruyu götürür". 0 → yanlış doğruyu götürmez.
  final double penaltyDivisor;

  /// Bağlı deneme sınavı (Deneme Sınavları modülü). Boşsa eski elle tanım.
  final String trialExamId;
  final String trialExamName;
  final int sessionCount;
  final int linkedQuestionCount;

  const ExternalLevelDefinition({
    this.opticalFormId = '',
    this.opticalFormName = '',
    this.subjects = const [],
    this.penaltyDivisor = 3,
    this.trialExamId = '',
    this.trialExamName = '',
    this.sessionCount = 0,
    this.linkedQuestionCount = 0,
  });

  bool get isTrialLinked => trialExamId.isNotEmpty;

  int get totalQuestions => isTrialLinked
      ? linkedQuestionCount
      : subjects.fold(0, (a, s) => a + s.questionCount);

  bool get isComplete => isTrialLinked
      ? true
      : opticalFormId.isNotEmpty &&
            subjects.isNotEmpty &&
            subjects.every((s) => s.isKeyComplete);

  Map<String, dynamic> toMap() => {
    'opticalFormId': opticalFormId,
    'opticalFormName': opticalFormName,
    'subjects': subjects.map((s) => s.toMap()).toList(),
    'penaltyDivisor': penaltyDivisor,
    'trialExamId': trialExamId,
    'trialExamName': trialExamName,
    'sessionCount': sessionCount,
    'linkedQuestionCount': linkedQuestionCount,
  };

  factory ExternalLevelDefinition.fromMap(Map<String, dynamic> m) =>
      ExternalLevelDefinition(
        opticalFormId: (m['opticalFormId'] ?? '').toString(),
        opticalFormName: (m['opticalFormName'] ?? '').toString(),
        subjects: (m['subjects'] as List? ?? [])
            .map(
              (e) => ExternalLevelSubject.fromMap(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
        penaltyDivisor: (m['penaltyDivisor'] as num?)?.toDouble() ?? 3,
        trialExamId: (m['trialExamId'] ?? '').toString(),
        trialExamName: (m['trialExamName'] ?? '').toString(),
        sessionCount: (m['sessionCount'] as num?)?.toInt() ?? 0,
        linkedQuestionCount: (m['linkedQuestionCount'] as num?)?.toInt() ?? 0,
      );
}

/// Bir öğrencinin tek bir dersteki sonucu.
class ExternalSubjectResult {
  final String name;
  final int questionCount;
  final int correct;
  final int wrong;
  final int empty;
  final double net;

  /// Öğrencinin işaretlediği cevaplar, doğru cevap anahtarı ve kitapçık (kazanım karnesi için).
  final String answers;
  final String key;
  final String booklet;

  /// Soru başına kazanım (kazanım karnesi için; herkese açık sorgulamada da çalışsın diye sonuçta saklanır).
  final List<String> outcomes;

  /// Dersin karnedeki sırası (sınav türündeki ders sırası). 999 = tanımsız.
  final int order;

  const ExternalSubjectResult({
    required this.name,
    required this.questionCount,
    required this.correct,
    required this.wrong,
    required this.empty,
    required this.net,
    this.answers = '',
    this.key = '',
    this.booklet = '',
    this.outcomes = const [],
    this.order = 999,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'questionCount': questionCount,
    'correct': correct,
    'wrong': wrong,
    'empty': empty,
    'net': net,
    'answers': answers,
    'key': key,
    'booklet': booklet,
    'outcomes': outcomes,
    'order': order,
  };

  factory ExternalSubjectResult.fromMap(Map<String, dynamic> m) =>
      ExternalSubjectResult(
        name: (m['name'] ?? '').toString(),
        questionCount: (m['questionCount'] as num?)?.toInt() ?? 0,
        correct: (m['correct'] as num?)?.toInt() ?? 0,
        wrong: (m['wrong'] as num?)?.toInt() ?? 0,
        empty: (m['empty'] as num?)?.toInt() ?? 0,
        net: (m['net'] as num?)?.toDouble() ?? 0,
        answers: (m['answers'] ?? '').toString(),
        key: (m['key'] ?? '').toString(),
        booklet: (m['booklet'] ?? '').toString(),
        outcomes: (m['outcomes'] as List? ?? const []).map((e) => e.toString()).toList(),
        order: (m['order'] as num?)?.toInt() ?? 999,
      );
}

/// Bir adayın dış katılımlı sınav sonucu (karne verisi).
/// Doküman kimliği: `{examId}_{tcNo}`.
class ExternalExamResult {
  final String examId;
  final String institutionId;
  final String registrationId;
  final String tcNo;
  final String fullName;
  final String gradeLevel;
  final String currentSchool;
  final List<ExternalSubjectResult> subjects;
  final int correct;
  final int wrong;
  final int empty;
  final double net;
  final double score;
  final int rank;
  final int totalInGrade;

  /// 0 → burs yok. Yüzde olarak burs oranı.
  final int scholarshipRate;
  final String scholarshipText;
  final DateTime? createdAt;

  /// Sonucun okunduğu deneme sınavı (kazanım karnesi için). Boşsa eski elle tanım.
  final String trialExamId;

  /// Yönetici 'Paylaş' dediyse true. false iken aday/herkese açık sorgulamada görünmez.
  final bool shared;

  const ExternalExamResult({
    required this.examId,
    required this.institutionId,
    required this.registrationId,
    required this.tcNo,
    required this.fullName,
    required this.gradeLevel,
    required this.currentSchool,
    required this.subjects,
    required this.correct,
    required this.wrong,
    required this.empty,
    required this.net,
    required this.score,
    this.rank = 0,
    this.totalInGrade = 0,
    this.scholarshipRate = 0,
    this.scholarshipText = '',
    this.createdAt,
    this.trialExamId = '',
    this.shared = false,
  });

  static String docIdFor(String examId, String tcNo) => '${examId}_$tcNo';

  String get docId => docIdFor(examId, tcNo);

  /// Dersler karne sırasına göre: önce sınav türündeki ders sırası, tanımsızsa
  /// LGS düzeni (Türkçe, Sosyal/İnkılap, Din, İngilizce, Matematik, Fen).
  List<ExternalSubjectResult> get orderedSubjects {
    int rank(ExternalSubjectResult s) => s.order != 999 ? s.order : _builtinRank(s.name);
    final list = [...subjects];
    list.sort((a, b) {
      final c = rank(a).compareTo(rank(b));
      return c != 0 ? c : a.name.compareTo(b.name);
    });
    return list;
  }

  static int _builtinRank(String name) {
    final c = name.trim().toLowerCase();
    bool has(List<String> k) => k.any(c.contains);
    if (has(['türkçe', 'turkce', 'edebiyat', 'türk dili'])) return 10;
    if (has(['sosyal', 'inkılap', 'inkilap', 'tarih', 'coğrafya', 'felsefe'])) return 20;
    if (c.contains('din')) return 30;
    if (has(['ingilizce', 'i̇ngilizce', 'yabancı', 'yabanci', 'dil', 'almanca', 'fransızca'])) return 40;
    if (has(['matematik', 'geometri'])) return 50;
    if (has(['fen', 'fizik', 'kimya', 'biyoloji'])) return 60;
    return 999;
  }

  /// Başvurusuz aday (başvuru kaydı yok).
  bool get isGuest => registrationId.isEmpty;

  /// Karnede gösterilecek maskeli T.C. (TC'si olmayan adaylarda '-').
  String get maskedTc {
    if (tcNo.startsWith('NOTC-')) return '-';
    if (tcNo.length < 5) return tcNo;
    return '${tcNo.substring(0, 3)}${'*' * (tcNo.length - 5)}${tcNo.substring(tcNo.length - 2)}';
  }

  ExternalExamResult withRanking({
    required int rank,
    required int totalInGrade,
    required int scholarshipRate,
    required String scholarshipText,
  }) => ExternalExamResult(
    examId: examId,
    institutionId: institutionId,
    registrationId: registrationId,
    tcNo: tcNo,
    fullName: fullName,
    gradeLevel: gradeLevel,
    currentSchool: currentSchool,
    subjects: subjects,
    correct: correct,
    wrong: wrong,
    empty: empty,
    net: net,
    score: score,
    rank: rank,
    totalInGrade: totalInGrade,
    scholarshipRate: scholarshipRate,
    scholarshipText: scholarshipText,
    createdAt: createdAt,
    trialExamId: trialExamId,
    shared: shared,
  );

  ExternalExamResult withShared(bool value) => ExternalExamResult(
    examId: examId,
    institutionId: institutionId,
    registrationId: registrationId,
    tcNo: tcNo,
    fullName: fullName,
    gradeLevel: gradeLevel,
    currentSchool: currentSchool,
    subjects: subjects,
    correct: correct,
    wrong: wrong,
    empty: empty,
    net: net,
    score: score,
    rank: rank,
    totalInGrade: totalInGrade,
    scholarshipRate: scholarshipRate,
    scholarshipText: scholarshipText,
    createdAt: createdAt,
    trialExamId: trialExamId,
    shared: value,
  );

  Map<String, dynamic> toMap() => {
    'examId': examId,
    'institutionId': institutionId,
    'registrationId': registrationId,
    'tcNo': tcNo,
    'fullName': fullName,
    'gradeLevel': gradeLevel,
    'currentSchool': currentSchool,
    'subjects': subjects.map((s) => s.toMap()).toList(),
    'correct': correct,
    'wrong': wrong,
    'empty': empty,
    'net': net,
    'score': score,
    'rank': rank,
    'totalInGrade': totalInGrade,
    'scholarshipRate': scholarshipRate,
    'scholarshipText': scholarshipText,
    'trialExamId': trialExamId,
    'shared': shared,
    'createdAt': FieldValue.serverTimestamp(),
  };

  factory ExternalExamResult.fromMap(Map<String, dynamic> m) {
    DateTime? created;
    final c = m['createdAt'];
    if (c is Timestamp) created = c.toDate();
    return ExternalExamResult(
      examId: (m['examId'] ?? '').toString(),
      institutionId: (m['institutionId'] ?? '').toString(),
      registrationId: (m['registrationId'] ?? '').toString(),
      tcNo: (m['tcNo'] ?? '').toString(),
      fullName: (m['fullName'] ?? '').toString(),
      gradeLevel: (m['gradeLevel'] ?? '').toString(),
      currentSchool: (m['currentSchool'] ?? '').toString(),
      subjects: (m['subjects'] as List? ?? [])
          .map(
            (e) => ExternalSubjectResult.fromMap(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
      correct: (m['correct'] as num?)?.toInt() ?? 0,
      wrong: (m['wrong'] as num?)?.toInt() ?? 0,
      empty: (m['empty'] as num?)?.toInt() ?? 0,
      net: (m['net'] as num?)?.toDouble() ?? 0,
      score: (m['score'] as num?)?.toDouble() ?? 0,
      rank: (m['rank'] as num?)?.toInt() ?? 0,
      totalInGrade: (m['totalInGrade'] as num?)?.toInt() ?? 0,
      scholarshipRate: (m['scholarshipRate'] as num?)?.toInt() ?? 0,
      scholarshipText: (m['scholarshipText'] ?? '').toString(),
      createdAt: created,
      trialExamId: (m['trialExamId'] ?? '').toString(),
      shared: m['shared'] == true,
    );
  }
}
