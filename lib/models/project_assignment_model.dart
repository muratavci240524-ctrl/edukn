import 'package:cloud_firestore/cloud_firestore.dart';

class ProjectAssignment {
  final String id;
  final String institutionId;
  final String termId; // Optional: e.g. "2023-2024-1"
  final String name; // e.g. "Yıl Sonu Projeleri"
  final DateTime createdAt;
  final String authorId;
  final String status; // 'draft', 'active', 'completed'

  // Target Audience
  final List<String> targetStudentIds;
  final List<String> targetClassLevels; // e.g. ["9", "10"]
  final List<String> targetBranchIds; // e.g. ["branch_id_1", "branch_id_2"]

  // Topics / Projects
  // Replaced topics with subjects structure
  final List<ProjectSubject> subjects;

  // Assignments / Allocations
  final List<ProjectAllocation> allocations;

  // Survey Integration
  final String? surveyId;
  final DateTime? surveyDeadline;

  ProjectAssignment({
    required this.id,
    required this.institutionId,
    this.termId = '',
    required this.name,
    required this.createdAt,
    required this.authorId,
    this.status = 'draft',
    required this.targetStudentIds,
    this.targetClassLevels = const [],
    this.targetBranchIds = const [],
    required this.subjects,
    this.allocations = const [],
    this.surveyId,
    this.surveyDeadline,
  });

  factory ProjectAssignment.fromMap(Map<String, dynamic> map) {
    return ProjectAssignment(
      id: map['id'] ?? '',
      institutionId: map['institutionId'] ?? '',
      termId: map['termId'] ?? '',
      name: map['name'] ?? '',
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      authorId: map['authorId'] ?? '',
      status: map['status'] ?? 'draft',
      targetStudentIds: List<String>.from(map['targetStudentIds'] ?? []),
      targetClassLevels: List<String>.from(map['targetClassLevels'] ?? []),
      targetBranchIds: List<String>.from(map['targetBranchIds'] ?? []),
      subjects:
          (map['subjects'] as List<dynamic>?)
              ?.map((t) => ProjectSubject.fromMap(t))
              .toList() ??
          [],
      allocations:
          (map['allocations'] as List<dynamic>?)
              ?.map((a) => ProjectAllocation.fromMap(a))
              .toList() ??
          [],
      surveyId: map['surveyId'],
      surveyDeadline: map['surveyDeadline'] != null
          ? (map['surveyDeadline'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'institutionId': institutionId,
      'termId': termId,
      'name': name,
      'createdAt': Timestamp.fromDate(createdAt),
      'authorId': authorId,
      'status': status,
      'targetStudentIds': targetStudentIds,
      'targetClassLevels': targetClassLevels,
      'targetBranchIds': targetBranchIds,
      'subjects': subjects.map((t) => t.toMap()).toList(),
      'allocations': allocations.map((a) => a.toMap()).toList(),
      'surveyId': surveyId,
      'surveyDeadline': surveyDeadline != null
          ? Timestamp.fromDate(surveyDeadline!)
          : null,
    };
  }

  // Backward compatibility helper
  List<ProjectTopic> get topics {
    return subjects.expand((s) => s.topics).toList();
  }
}

class ProjectSubject {
  final String id;
  final String lessonName; // e.g. "Matematik"
  final List<String> targetBranchIds; // e.g. ["9-A_id", "9-B_id"]
  final List<ProjectTopic> topics;

  ProjectSubject({
    required this.id,
    required this.lessonName,
    required this.targetBranchIds,
    required this.topics,
  });

  factory ProjectSubject.fromMap(Map<String, dynamic> map) {
    return ProjectSubject(
      id: map['id'] ?? '',
      lessonName: map['lessonName'] ?? '',
      targetBranchIds: List<String>.from(map['targetBranchIds'] ?? []),
      topics:
          (map['topics'] as List<dynamic>?)
              ?.map((t) => ProjectTopic.fromMap(t))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'lessonName': lessonName,
      'targetBranchIds': targetBranchIds,
      'topics': topics.map((t) => t.toMap()).toList(),
    };
  }
}

class ProjectTopic {
  final String id;
  final String name; // Topic Title
  final String description;
  final int quotaPerTeacher;

  // Derived/Legacy fields for compatibility or distribution logic
  // We can keep branchName if needed, but it's now parent's lessonName
  // We remove teacherIds as they are implicit from Lesson+Branch

  ProjectTopic({
    required this.id,
    required this.name,
    this.description = '',
    this.quotaPerTeacher = 0,
  });

  factory ProjectTopic.fromMap(Map<String, dynamic> map) {
    return ProjectTopic(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      quotaPerTeacher: map['quotaPerTeacher'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'quotaPerTeacher': quotaPerTeacher,
    };
  }

  // Legacy getters/setters if helpful to minimize breaking changes elsewhere
  String get branchName => ''; // TODO: Fix call sites
  List<String> get teacherIds =>
      []; // TODO: Fix call sites for specific teachers
}

class ProjectAllocation {
  final String studentId;
  final String topicId;
  final String teacherId;
  final String method; // 'manual', 'survey_1', 'survey_2', 'survey_3', 'random'
  final DateTime allocatedAt;

  ProjectAllocation({
    required this.studentId,
    required this.topicId,
    required this.teacherId,
    required this.method,
    required this.allocatedAt,
  });

  factory ProjectAllocation.fromMap(Map<String, dynamic> map) {
    return ProjectAllocation(
      studentId: map['studentId'] ?? '',
      topicId: map['topicId'] ?? '',
      teacherId: map['teacherId'] ?? '',
      method: map['method'] ?? 'manual',
      allocatedAt: (map['allocatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'studentId': studentId,
      'topicId': topicId,
      'teacherId': teacherId,
      'method': method,
      'allocatedAt': Timestamp.fromDate(allocatedAt),
    };
  }
}
