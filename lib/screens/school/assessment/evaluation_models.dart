class StudentResult {
  String tcNo;
  String studentNo;
  String name;
  String classLevel;
  String branch;
  String booklet;
  Map<String, String> answers; // Subject -> Answer String
  Map<String, String> correctAnswers; // Subject -> Correct Answer
  Map<String, SubjectStats> subjects;
  double score;
  int rankGeneral;
  int rankInstitution;
  int rankBranch;
  bool isMatched;
  String? systemStudentId;
  Set<int> participatedSessions;

  StudentResult({
    required this.tcNo,
    required this.studentNo,
    required this.name,
    required this.classLevel,
    required this.branch,
    this.booklet = '',
    Map<String, SubjectStats>? subjects,
    Map<String, String>? answers,
    Map<String, String>? correctAnswers,
    this.score = 0.0,
    this.rankGeneral = 0,
    this.rankInstitution = 0,
    this.rankBranch = 0,
    this.isMatched = false,
    this.systemStudentId,
    Set<int>? participatedSessions,
  }) : subjects = subjects ?? <String, SubjectStats>{},
       answers = answers ?? <String, String>{},
       correctAnswers = correctAnswers ?? <String, String>{},
       participatedSessions = participatedSessions ?? <int>{};

  SubjectStats get total {
    int d = 0, y = 0, b = 0;
    double n = 0;
    subjects.values.forEach((s) {
      d += s.correct;
      y += s.wrong;
      b += s.empty;
      n += s.net;
    });
    return SubjectStats(correct: d, wrong: y, empty: b, net: n);
  }

  Map<String, dynamic> toJson() {
    return {
      'tcNo': tcNo,
      'studentNo': studentNo,
      'name': name,
      'classLevel': classLevel,
      'branch': branch,
      'booklet': booklet,
      'score': score,
      'rankGeneral': rankGeneral,
      'rankInstitution': rankInstitution,
      'rankBranch': rankBranch,
      'subjects': subjects.map((k, v) => MapEntry(k, v.toJson())),
      'answers': answers,
      // 'correctAnswers': correctAnswers, // Redundant, removed to save space
      'isMatched': isMatched,
      'systemStudentId': systemStudentId,
      'participatedSessions': participatedSessions.toList(),
    };
  }

  factory StudentResult.fromJson(Map<String, dynamic> json) {
    var s = StudentResult(
      tcNo: json['tcNo'] ?? '',
      studentNo: json['studentNo'] ?? '',
      name: json['name'] ?? '',
      classLevel: json['classLevel'] ?? '',
      branch: json['branch'] ?? '',
      booklet: json['booklet'] ?? '',
      score: (json['score'] ?? 0.0).toDouble(),
      rankGeneral: json['rankGeneral'] ?? 0,
      rankInstitution: json['rankInstitution'] ?? 0,
      rankBranch: json['rankBranch'] ?? 0,
      answers: (json['answers'] as Map<String, dynamic>?)
          ?.cast<String, String>(),
      correctAnswers: (json['correctAnswers'] as Map<String, dynamic>?)
          ?.cast<String, String>(),
      isMatched: json['isMatched'] ?? false,
      systemStudentId: json['systemStudentId'],
      participatedSessions: (json['participatedSessions'] as List<dynamic>?)
          ?.map((e) => e as int)
          .toSet(),
    );
    if (json['subjects'] != null) {
      s.subjects = (json['subjects'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, SubjectStats.fromJson(v)),
      );
    }
    return s;
  }
}

class SubjectStats {
  int correct;
  int wrong;
  int empty;
  double net;
  SubjectStats({
    this.correct = 0,
    this.wrong = 0,
    this.empty = 0,
    this.net = 0.0,
  });

  Map<String, dynamic> toJson() => {
    'correct': correct,
    'wrong': wrong,
    'empty': empty,
    'net': net,
  };

  factory SubjectStats.fromJson(Map<String, dynamic> json) {
    return SubjectStats(
      correct: json['correct'] ?? 0,
      wrong: json['wrong'] ?? 0,
      empty: json['empty'] ?? 0,
      net: (json['net'] ?? 0).toDouble(),
    );
  }
}
