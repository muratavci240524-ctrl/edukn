class ExamType {
  final String id;
  final String
  gradeLevel; // Sınav Türü Adı (User said Sınav Türünün Adı, but usually this is LGS/TYT etc. Let's call it name)
  final String name;
  final String institutionId;
  final double baseScore; // Taban puan
  final double maxScore; // Tavan puan
  final double
  wrongCorrectRatio; // Kaç yanlış bir doğruyu götürür (e.g. 3.0, 4.0)
  final int optionCount; // Şık sayısı (3, 4, 5)
  final List<ExamSubject> subjects;
  final bool isActive;

  ExamType({
    required this.id,
    required this.name,
    required this.institutionId,
    this.gradeLevel = '',
    this.baseScore = 0.0,
    this.maxScore = 500.0,
    this.wrongCorrectRatio = 3.0,
    this.optionCount = 4,
    required this.subjects,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'gradeLevel': gradeLevel,
      'institutionId': institutionId,
      'baseScore': baseScore,
      'maxScore': maxScore,
      'wrongCorrectRatio': wrongCorrectRatio,
      'optionCount': optionCount,
      'subjects': subjects.map((s) => s.toMap()).toList(),
      'isActive': isActive,
    };
  }

  factory ExamType.fromMap(Map<String, dynamic> map, String id) {
    return ExamType(
      id: id,
      name: map['name'] ?? '',
      gradeLevel: map['gradeLevel'] ?? '',
      institutionId: map['institutionId'] ?? '',
      baseScore: (map['baseScore'] ?? 0.0).toDouble(),
      maxScore: (map['maxScore'] ?? 0.0).toDouble(),
      wrongCorrectRatio: (map['wrongCorrectRatio'] ?? 0.0).toDouble(),
      optionCount: map['optionCount'] ?? 4,
      subjects: List<ExamSubject>.from(
        (map['subjects'] as List<dynamic>? ?? []).map(
          (x) => ExamSubject.fromMap(x),
        ),
      ),
      isActive: map['isActive'] ?? true,
    );
  }
}

class ExamSubject {
  final String branchName; // Dersin adı (Matematik vs)
  final int questionCount; // Soru sayısı
  final double coefficient; // Katsayı

  ExamSubject({
    required this.branchName,
    required this.questionCount,
    required this.coefficient,
  });

  Map<String, dynamic> toMap() {
    return {
      'branchName': branchName,
      'questionCount': questionCount,
      'coefficient': coefficient,
    };
  }

  factory ExamSubject.fromMap(Map<String, dynamic> map) {
    return ExamSubject(
      branchName: map['branchName'] ?? '',
      questionCount: map['questionCount'] ?? 0,
      coefficient: (map['coefficient'] ?? 0.0).toDouble(),
    );
  }
}
