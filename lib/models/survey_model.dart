import 'package:cloud_firestore/cloud_firestore.dart';

enum SurveyStatus { draft, published, closed, scheduled }

enum SurveyTargetType { all, teachers, students, parents, specific_classes }

enum SurveyQuestionType {
  text,
  longText,
  singleChoice,
  multipleChoice,
  rating,
  date,
  ranking, // For priority-based selection (1st, 2nd, 3rd choice)
}

class Survey {
  final String id;
  final String institutionId;
  final String schoolTypeId;
  final String title;
  final String description;
  final String authorId;
  final DateTime createdAt;
  final DateTime? publishedAt;
  final DateTime? scheduledAt;
  final DateTime? closedAt;
  final SurveyStatus status;
  final SurveyTargetType targetType;
  final List<String> targetIds;
  final List<SurveySection> sections;
  final int responseCount;
  final bool isAnonymous;
  final String? guidanceTemplateId; // Links to a predefined test definition
  final List<String> targetNames; // Display names for target groups
  final int
  totalTargetCount; // Denominator for completion rate (e.g., 14 in 12/14)

  // Ranking configuration (for project assignment surveys)
  final int? maxProjectsPerStudent; // Öğrenci kaç proje alacak
  final int? maxTotalChoices; // Toplam kaç tercih yapabilecek
  final int? maxSubjects; // En fazla kaç farklı ders seçebilir
  final int? maxChoicesPerSubject; // Bir dersten en fazla kaç tercih yapabilir

  Survey({
    required this.id,
    required this.institutionId,
    required this.schoolTypeId,
    required this.title,
    required this.description,
    required this.authorId,
    required this.createdAt,
    this.publishedAt,
    this.scheduledAt,
    this.closedAt,
    required this.status,
    required this.targetType,
    required this.targetIds,
    required this.sections,
    this.responseCount = 0,
    this.isAnonymous = false,
    this.guidanceTemplateId,
    this.maxProjectsPerStudent,
    this.maxTotalChoices,
    this.maxSubjects,
    this.maxChoicesPerSubject,
    this.targetNames = const [],
    this.totalTargetCount = 0,
  });

  factory Survey.fromMap(Map<String, dynamic> map, String id) {
    return Survey(
      id: id,
      institutionId: map['institutionId'] ?? '',
      schoolTypeId: map['schoolTypeId'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      authorId: map['authorId'] ?? '',
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      publishedAt: map['publishedAt'] != null
          ? (map['publishedAt'] as Timestamp).toDate()
          : null,
      scheduledAt: map['scheduledAt'] != null
          ? (map['scheduledAt'] as Timestamp).toDate()
          : null,
      closedAt: map['closedAt'] != null
          ? (map['closedAt'] as Timestamp).toDate()
          : null,
      status: SurveyStatus.values.firstWhere(
        (e) => e.name == (map['status'] ?? 'draft'),
        orElse: () => SurveyStatus.draft,
      ),
      targetType: SurveyTargetType.values.firstWhere(
        (e) => e.name == (map['targetType'] ?? 'all'),
        orElse: () => SurveyTargetType.all,
      ),
      targetIds: List<String>.from(map['targetIds'] ?? []),
      sections:
          (map['sections'] as List<dynamic>?)
              ?.map((x) => SurveySection.fromMap(x))
              .toList() ??
          [],
      responseCount: map['responseCount'] ?? 0,
      isAnonymous: map['isAnonymous'] ?? false,
      guidanceTemplateId: map['guidanceTemplateId'],
      maxProjectsPerStudent: map['maxProjectsPerStudent'],
      maxTotalChoices: map['maxTotalChoices'],
      maxSubjects: map['maxSubjects'],
      maxChoicesPerSubject: map['maxChoicesPerSubject'],
      targetNames: List<String>.from(map['targetNames'] ?? []),
      totalTargetCount: map['totalTargetCount'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'schoolTypeId': schoolTypeId,
      'title': title,
      'description': description,
      'authorId': authorId,
      'createdAt': Timestamp.fromDate(createdAt),
      'publishedAt': publishedAt != null
          ? Timestamp.fromDate(publishedAt!)
          : null,
      'scheduledAt': scheduledAt != null
          ? Timestamp.fromDate(scheduledAt!)
          : null,
      'closedAt': closedAt != null ? Timestamp.fromDate(closedAt!) : null,
      'status': status.name,
      'targetType': targetType.name,
      'targetIds': targetIds,
      'sections': sections.map((x) => x.toMap()).toList(),
      'responseCount': responseCount,
      'isAnonymous': isAnonymous,
      'guidanceTemplateId': guidanceTemplateId,
      if (maxProjectsPerStudent != null)
        'maxProjectsPerStudent': maxProjectsPerStudent,
      if (maxTotalChoices != null) 'maxTotalChoices': maxTotalChoices,
      if (maxSubjects != null) 'maxSubjects': maxSubjects,
      if (maxChoicesPerSubject != null)
        'maxChoicesPerSubject': maxChoicesPerSubject,
      'targetNames': targetNames,
      'totalTargetCount': totalTargetCount,
    };
  }
}

class SurveySection {
  final String id;
  final String title;
  final String? description;
  final List<SurveyQuestion> questions;

  SurveySection({
    required this.id,
    required this.title,
    this.description,
    required this.questions,
  });

  factory SurveySection.fromMap(Map<String, dynamic> map) {
    return SurveySection(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      description: map['description'],
      questions:
          (map['questions'] as List<dynamic>?)
              ?.map((x) => SurveyQuestion.fromMap(x))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'questions': questions.map((x) => x.toMap()).toList(),
    };
  }
}

class SurveyQuestion {
  final String id;
  final String text;
  final SurveyQuestionType type;
  final bool isRequired;
  final List<String> options;
  final String? mediaUrl;

  SurveyQuestion({
    required this.id,
    required this.text,
    required this.type,
    this.isRequired = false,
    this.options = const [],
    this.mediaUrl,
  });

  factory SurveyQuestion.fromMap(Map<String, dynamic> map) {
    return SurveyQuestion(
      id: map['id'] ?? '',
      text: map['text'] ?? '',
      type: SurveyQuestionType.values.firstWhere(
        (e) => e.name == (map['type'] ?? 'text'),
        orElse: () => SurveyQuestionType.text,
      ),
      isRequired: map['isRequired'] ?? false,
      options: List<String>.from(map['options'] ?? []),
      mediaUrl: map['mediaUrl'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'type': type.name,
      'isRequired': isRequired,
      'options': options,
      'mediaUrl': mediaUrl,
    };
  }
}
