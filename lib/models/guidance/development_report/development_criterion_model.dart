class DevelopmentCriterion {
  final String id;
  final String institutionId;
  final String category; // e.g., 'academic', 'social'
  final String subCategory; // e.g., 'math', 'peer_relations'
  final String title;
  final String description;
  final List<String> targetGradeLevels; // ['preschool', 'primary_1', ...]
  final String type; // 'scale_1_5', 'scale_good_bad', 'text'
  final int order; // For display ordering

  DevelopmentCriterion({
    required this.id,
    required this.institutionId,
    required this.category,
    required this.subCategory,
    required this.title,
    required this.description,
    required this.targetGradeLevels,
    required this.type,
    required this.order,
  });

  factory DevelopmentCriterion.fromMap(Map<String, dynamic> map) {
    return DevelopmentCriterion(
      id: map['id'] ?? '',
      institutionId: map['institutionId'] ?? '',
      category: map['category'] ?? '',
      subCategory: map['subCategory'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      targetGradeLevels: List<String>.from(map['targetGradeLevels'] ?? []),
      type: map['type'] ?? 'scale_1_5',
      order: map['order'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'category': category,
      'subCategory': subCategory,
      'title': title,
      'description': description,
      'targetGradeLevels': targetGradeLevels,
      'type': type,
      'order': order,
    };
  }
}
