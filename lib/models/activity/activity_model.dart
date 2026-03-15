import 'package:cloud_firestore/cloud_firestore.dart';
import '../survey_model.dart'; // Import SurveyQuestion if needed, or redefine

enum ActivityType {
  observation, // Gözlem
  activity, // Etkinlik
}

enum ActivityStatus { planned, completed, cancelled }

class ActivityObservation {
  final String id;
  final String institutionId;
  final String schoolTypeId;
  final String title;
  final String description;
  final String type; // 'observation' or 'activity'
  final DateTime date;
  final String responsibleTeacherId;
  final String responsibleTeacherName;
  final List<String> targetStudentIds; // List of student IDs
  final bool isEvaluationEnabled;
  final List<String>?
  evaluatorTeacherIds; // If empty/null, all teachers can evaluate? Or specific ones.
  final List<SurveyQuestion> questions; // Questions for evaluation
  final ActivityStatus status;
  final DateTime createdAt;
  final List<String> participatedStudentIds; // IDs of students who participated

  ActivityObservation({
    required this.id,
    required this.institutionId,
    required this.schoolTypeId,
    required this.title,
    required this.description,
    required this.type,
    required this.date,
    required this.responsibleTeacherId,
    required this.responsibleTeacherName,
    required this.targetStudentIds,
    required this.isEvaluationEnabled,
    this.evaluatorTeacherIds,
    this.questions = const [],
    this.status = ActivityStatus.planned,
    required this.createdAt,
    this.participatedStudentIds = const [],
  });

  factory ActivityObservation.fromMap(Map<String, dynamic> map, String id) {
    return ActivityObservation(
      id: id,
      institutionId: map['institutionId'] ?? '',
      schoolTypeId: map['schoolTypeId'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      type: map['type'] ?? 'activity',
      date: (map['date'] as Timestamp).toDate(),
      responsibleTeacherId: map['responsibleTeacherId'] ?? '',
      responsibleTeacherName: map['responsibleTeacherName'] ?? '',
      targetStudentIds: List<String>.from(map['targetStudentIds'] ?? []),
      isEvaluationEnabled: map['isEvaluationEnabled'] ?? false,
      evaluatorTeacherIds: map['evaluatorTeacherIds'] != null
          ? List<String>.from(map['evaluatorTeacherIds'])
          : null,
      questions:
          (map['questions'] as List<dynamic>?)
              ?.map((x) => SurveyQuestion.fromMap(x))
              .toList() ??
          [],
      status: ActivityStatus.values.firstWhere(
        (e) => e.name == (map['status'] ?? 'planned'),
        orElse: () => ActivityStatus.planned,
      ),
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      participatedStudentIds: List<String>.from(
        map['participatedStudentIds'] ?? [],
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'schoolTypeId': schoolTypeId,
      'title': title,
      'description': description,
      'type': type,
      'date': Timestamp.fromDate(date),
      'responsibleTeacherId': responsibleTeacherId,
      'responsibleTeacherName': responsibleTeacherName,
      'targetStudentIds': targetStudentIds,
      'isEvaluationEnabled': isEvaluationEnabled,
      'evaluatorTeacherIds': evaluatorTeacherIds,
      'questions': questions.map((x) => x.toMap()).toList(),
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'participatedStudentIds': participatedStudentIds,
    };
  }
}

class ActivityEvaluation {
  final String id;
  final String activityId;
  final String studentId;
  final String evaluatorId;
  final String evaluatorName;
  final DateTime createdAt;
  final Map<String, dynamic> responses; // questionId -> answer (String or List)

  ActivityEvaluation({
    required this.id,
    required this.activityId,
    required this.studentId,
    required this.evaluatorId,
    required this.evaluatorName,
    required this.createdAt,
    required this.responses,
  });

  factory ActivityEvaluation.fromMap(Map<String, dynamic> map, String id) {
    return ActivityEvaluation(
      id: id,
      activityId: map['activityId'] ?? '',
      studentId: map['studentId'] ?? '',
      evaluatorId: map['evaluatorId'] ?? '',
      evaluatorName: map['evaluatorName'] ?? '',
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      responses: Map<String, dynamic>.from(map['responses'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'activityId': activityId,
      'studentId': studentId,
      'evaluatorId': evaluatorId,
      'evaluatorName': evaluatorName,
      'createdAt': Timestamp.fromDate(createdAt),
      'responses': responses,
    };
  }
}
