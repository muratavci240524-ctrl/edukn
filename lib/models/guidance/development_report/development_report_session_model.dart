import 'package:cloud_firestore/cloud_firestore.dart';

class DevelopmentReportSession {
  final String id;
  final String institutionId;
  final String title;
  final String targetGroup; // 'student', 'teacher', 'personnel'
  final String schoolYear;
  final List<String> assignedReviewerIds;
  final List<String> targetUserIds;
  final DateTime createdAt;
  final String? createdBy;
  final bool isPublished;

  DevelopmentReportSession({
    required this.id,
    required this.institutionId,
    required this.title,
    required this.targetGroup,
    required this.schoolYear,
    this.assignedReviewerIds = const [],
    this.targetUserIds = const [],
    required this.createdAt,
    this.createdBy,
    this.isPublished = false,
  });

  factory DevelopmentReportSession.fromMap(Map<String, dynamic> map) {
    return DevelopmentReportSession(
      id: map['id'] ?? '',
      institutionId: map['institutionId'] ?? '',
      title: map['title'] ?? '',
      targetGroup: map['targetGroup'] ?? 'student',
      schoolYear: map['schoolYear'] ?? '',
      assignedReviewerIds: List<String>.from(map['assignedReviewerIds'] ?? []),
      targetUserIds: List<String>.from(map['targetUserIds'] ?? []),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: map['createdBy'],
      isPublished: map['isPublished'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'title': title,
      'targetGroup': targetGroup,
      'schoolYear': schoolYear,
      'assignedReviewerIds': assignedReviewerIds,
      'targetUserIds': targetUserIds,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      'isPublished': isPublished,
    };
  }
}
