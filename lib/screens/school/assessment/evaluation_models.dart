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
    for (var s in subjects.values) {
      d += s.correct;
      y += s.wrong;
      b += s.empty;
      n += s.net;
    }
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
      'correctAnswers': correctAnswers, 
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

/// Akıllı öğrenci eşleştirme motoru (TC, Numara, İsim ve Şube kontrolü)
class StudentMatcher {
  final Map<String, Map<String, dynamic>> sysByTc = {};
  final Map<String, List<Map<String, dynamic>>> sysByNo = {};
  final Map<String, List<Map<String, dynamic>>> sysByNameTokens = {};
  final List<Map<String, dynamic>> allStudents = [];

  static String fixWindows1254(String text) {
    return text
        .replaceAll('Ý', 'İ')
        .replaceAll('ý', 'ı')
        .replaceAll('Þ', 'Ş')
        .replaceAll('þ', 'ş')
        .replaceAll('Ð', 'Ğ')
        .replaceAll('ð', 'ğ');
  }

  static String normalizeTurkishForSearch(String text) {
    return fixWindows1254(text)
        .replaceAll('İ', 'i')
        .replaceAll('I', 'i')
        .replaceAll('ı', 'i')
        .replaceAll('ş', 's')
        .replaceAll('Ş', 's')
        .replaceAll('ğ', 'g')
        .replaceAll('Ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('Ü', 'u')
        .replaceAll('ö', 'o')
        .replaceAll('Ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll('Ç', 'c')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String getNameTokensKey(String name) {
    final normalized = normalizeTurkishForSearch(name);
    final tokens = normalized.split(' ').where((t) => t.isNotEmpty).toList();
    tokens.sort();
    return tokens.join('_');
  }

  static Set<String> getNameTokenSet(String name) {
    final normalized = normalizeTurkishForSearch(name);
    return normalized.split(' ').where((t) => t.isNotEmpty).toSet();
  }

  StudentMatcher(Iterable<Map<String, dynamic>> students) {
    for (var s in students) {
      allStudents.add(s);

      // 1. TC Kaydı
      final tc = (s['tcNo'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '').trim();
      if (tc.length == 11 && !tc.startsWith('000') && !tc.startsWith('1111111111')) {
        sysByTc[tc] = s;
      }

      // 2. Numara Kaydı
      final rawNo = (s['studentNo'] ?? s['studentNumber'] ?? '').toString().trim();
      if (rawNo.isNotEmpty) {
        final stripped = rawNo.replaceFirst(RegExp(r'^0+'), '');
        sysByNo.putIfAbsent(rawNo, () => []).add(s);
        if (stripped.isNotEmpty && stripped != rawNo) {
          sysByNo.putIfAbsent(stripped, () => []).add(s);
        }
      }

      // 3. İsim Token Kaydı
      final fullName = (s['fullName'] ?? s['name'] ?? '').toString().trim();
      if (fullName.isNotEmpty) {
        final key = getNameTokensKey(fullName);
        if (key.isNotEmpty) {
          sysByNameTokens.putIfAbsent(key, () => []).add(s);
        }
      }
    }
  }

  Map<String, dynamic>? match({
    required String fileTc,
    required String fileNo,
    required String fileName,
    String? fileBranch,
    String? fileCls,
  }) {
    final cleanTc = fileTc.replaceAll(RegExp(r'[^0-9]'), '').trim();
    final rawNo = fileNo.trim();
    final cleanNo = rawNo.replaceFirst(RegExp(r'^0+'), '');
    final cleanName = fixWindows1254(fileName).trim();
    final cleanBranch = (fileBranch ?? '').trim().toLowerCase();

    // 1. TC Kontrolü (1. Öncelik - 11 Hane & Gerçek TC)
    if (cleanTc.length == 11 && !cleanTc.startsWith('000') && !cleanTc.startsWith('1111111111')) {
      if (sysByTc.containsKey(cleanTc)) {
        return sysByTc[cleanTc];
      }
    }

    // 2. Öğrenci Numarası Kontrolü (2. Öncelik)
    if (cleanNo.isNotEmpty || rawNo.isNotEmpty) {
      List<Map<String, dynamic>>? candidates = sysByNo[cleanNo] ?? sysByNo[rawNo];
      if (candidates != null && candidates.isNotEmpty) {
        if (candidates.length == 1) {
          return candidates.first;
        }
        // Birden fazla varsa şube ile ayrıştır
        if (cleanBranch.isNotEmpty) {
          final branchMatch = candidates.where((c) {
            final cb = (c['className'] ?? c['branch'] ?? '').toString().toLowerCase();
            return cb.contains(cleanBranch) || cleanBranch.contains(cb);
          }).toList();
          if (branchMatch.length == 1) return branchMatch.first;
        }
        // İsim ile ayrıştır
        if (cleanName.isNotEmpty) {
          final fileTokens = getNameTokenSet(cleanName);
          for (var c in candidates) {
            final cTokens = getNameTokenSet((c['fullName'] ?? c['name'] ?? '').toString());
            if (fileTokens.intersection(cTokens).length >= 2 ||
                (fileTokens.length == 1 && cTokens.contains(fileTokens.first))) {
              return c;
            }
          }
        }
        return candidates.first;
      }
    }

    // 3. İsim Kontrolü (3. Öncelik - Sıradan bağımsız tam kelime eşleşmesi)
    if (cleanName.isNotEmpty) {
      final key = getNameTokensKey(cleanName);
      if (key.isNotEmpty && sysByNameTokens.containsKey(key)) {
        final candidates = sysByNameTokens[key]!;
        if (candidates.length == 1) {
          return candidates.first;
        }
        // Birden fazla aynı isimli öğrenci varsa şubeye bak
        if (cleanBranch.isNotEmpty) {
          final branchMatch = candidates.where((c) {
            final cb = (c['className'] ?? c['branch'] ?? '').toString().toLowerCase();
            return cb.contains(cleanBranch) || cleanBranch.contains(cb);
          }).toList();
          if (branchMatch.length == 1) return branchMatch.first;
        }
        return candidates.first;
      }

      // 4. Alt Küme İsim Eşleşmesi (İkinci ad eksik veya fazla olduğunda)
      final fileTokens = getNameTokenSet(cleanName);
      if (fileTokens.length >= 2) {
        final matches = <Map<String, dynamic>>[];
        for (var s in allStudents) {
          final sTokens = getNameTokenSet((s['fullName'] ?? s['name'] ?? '').toString());
          if (sTokens.length >= 2) {
            if (fileTokens.difference(sTokens).isEmpty || sTokens.difference(fileTokens).isEmpty) {
              matches.add(s);
            }
          }
        }
        if (matches.length == 1) {
          return matches.first;
        } else if (matches.length > 1 && cleanBranch.isNotEmpty) {
          final branchMatch = matches.where((c) {
            final cb = (c['className'] ?? c['branch'] ?? '').toString().toLowerCase();
            return cb.contains(cleanBranch) || cleanBranch.contains(cb);
          }).toList();
          if (branchMatch.length == 1) return branchMatch.first;
        }
      }
    }

    return null;
  }

  /// Öğrenci Seçim Diyaloğu için eşleşme skoru hesaplar
  static int scoreCandidate(Map<String, dynamic> candidate, StudentResult target) {
    int score = 0;

    // 1. TC
    final candTc = (candidate['tcNo'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '').trim();
    final targetTc = target.tcNo.replaceAll(RegExp(r'[^0-9]'), '').trim();
    if (candTc.length == 11 && candTc == targetTc && !candTc.startsWith('000')) {
      score += 1000;
    }

    // 2. Numara
    final candNo = (candidate['studentNo'] ?? candidate['studentNumber'] ?? '').toString().trim();
    final targetNo = target.studentNo.trim();
    final candNoClean = candNo.replaceFirst(RegExp(r'^0+'), '');
    final targetNoClean = targetNo.replaceFirst(RegExp(r'^0+'), '');
    if (candNoClean.isNotEmpty && candNoClean == targetNoClean) {
      score += 600;
    }

    // 3. İsim
    final candName = (candidate['fullName'] ?? candidate['name'] ?? '').toString();
    final candTokens = getNameTokenSet(candName);
    final targetTokens = getNameTokenSet(target.name);
    if (candTokens.isNotEmpty && targetTokens.isNotEmpty) {
      final intersection = candTokens.intersection(targetTokens);
      if (candTokens == targetTokens) {
        score += 500;
      } else if (intersection.length >= 2) {
        score += 350;
      } else if (intersection.length == 1 && (candTokens.length == 1 || targetTokens.length == 1)) {
        score += 150;
      }
    }

    // 4. Şube / Seviye
    final candBranch = (candidate['className'] ?? candidate['branch'] ?? '').toString().toLowerCase();
    final targetBranch = target.branch.toLowerCase();
    if (candBranch.isNotEmpty && targetBranch.isNotEmpty) {
      if (candBranch == targetBranch || candBranch.contains(targetBranch) || targetBranch.contains(candBranch)) {
        score += 50;
      }
    }

    final candLevel = (candidate['classLevel'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
    final targetLevel = target.classLevel.replaceAll(RegExp(r'[^0-9]'), '');
    if (candLevel.isNotEmpty && candLevel == targetLevel) {
      score += 20;
    }

    return score;
  }
}
