import 'package:cloud_firestore/cloud_firestore.dart';

class DevelopmentEvaluation {
  final String id;
  final String institutionId;
  final String reportId;
  final String evaluatorId;
  final String evaluatorName;
  final String evaluatorRole; // 'teacher', 'guidance', 'parent', 'student'

  // Map of Criterion ID to Score (or value)
  final Map<String, dynamic> scores;

  // Map of Criterion ID to Comment
  final Map<String, String> comments;

  final DateTime createdAt;
  final DateTime? updatedAt;

  DevelopmentEvaluation({
    required this.id,
    required this.institutionId,
    required this.reportId,
    required this.evaluatorId,
    required this.evaluatorName,
    required this.evaluatorRole,
    this.scores = const {},
    this.comments = const {},
    required this.createdAt,
    this.updatedAt,
  });

  factory DevelopmentEvaluation.fromMap(Map<String, dynamic> map) {
    return DevelopmentEvaluation(
      id: map['id'] ?? '',
      institutionId: map['institutionId'] ?? '',
      reportId: map['reportId'] ?? '',
      evaluatorId: map['evaluatorId'] ?? '',
      evaluatorName: map['evaluatorName'] ?? '',
      evaluatorRole: map['evaluatorRole'] ?? '',
      scores: Map<String, dynamic>.from(map['scores'] ?? {}),
      comments: Map<String, String>.from(map['comments'] ?? {}),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'reportId': reportId,
      'evaluatorId': evaluatorId,
      'evaluatorName': evaluatorName,
      'evaluatorRole': evaluatorRole,
      'scores': scores,
      'comments': comments,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }
}
