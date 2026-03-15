class OutcomeList {
  final String id;
  final String institutionId;
  final String name; // e.g. "8. Sınıf Matematik"
  final String branchName; // e.g. "Matematik"
  final String classLevel; // e.g. "8. Sınıf"
  final List<OutcomeItem> outcomes;
  final bool isActive;

  OutcomeList({
    required this.id,
    required this.institutionId,
    required this.name,
    required this.branchName,
    required this.classLevel,
    required this.outcomes,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'institutionId': institutionId,
      'name': name,
      'branchName': branchName,
      'classLevel': classLevel,
      'outcomes': outcomes.map((x) => x.toMap()).toList(),
      'isActive': isActive,
    };
  }

  factory OutcomeList.fromMap(Map<String, dynamic> map, String id) {
    return OutcomeList(
      id: id,
      institutionId: map['institutionId'] ?? '',
      name: map['name'] ?? '',
      branchName: map['branchName'] ?? '',
      classLevel: map['classLevel'] ?? '',
      outcomes: List<OutcomeItem>.from(
        (map['outcomes'] as List<dynamic>? ?? []).map(
          (x) => OutcomeItem.fromMap(x),
        ),
      ),
      isActive: map['isActive'] ?? true,
    );
  }
}

class OutcomeItem {
  final String code; // e.g. "1.1" or "M.8.1.1" (Display Code)
  final String description;
  final int depth; // 1: Topic Heading, 2: Outcome
  final String
  k12Code; // e.g. "M.8.1.1.1" (System/Official Code for auto-matching)

  OutcomeItem({
    required this.code,
    required this.description,
    this.depth = 2,
    this.k12Code = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'description': description,
      'depth': depth,
      'k12Code': k12Code,
    };
  }

  factory OutcomeItem.fromMap(Map<String, dynamic> map) {
    return OutcomeItem(
      code: map['code'] ?? '',
      description: map['description'] ?? '',
      depth: map['depth'] ?? 2,
      k12Code: map['k12Code'] ?? '',
    );
  }
}
