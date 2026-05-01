import 'package:cloud_firestore/cloud_firestore.dart';

class AssessmentActionPlan {
  final String id;
  final String institutionId;
  final String schoolTypeId;
  final String title;
  final DateTime date;
  final String createdBy;
  final String creatorName;
  final List<String> selectedExamIds;
  final List<String> selectedExamNames;
  final String classLevel;
  final Map<String, double> subjectThresholds;
  
  /// Serialized outcome stats or summary data
  /// Map<Branch, Map<Subject, Map<Outcome, Map<String, dynamic>>>>
  final Map<String, dynamic> outcomeStats;
  
  /// Map<String, dynamic> containing problemSource, actionPlan, status
  final Map<String, dynamic> branchActionPlans;
  
  final bool isActive;
  final bool isRealized;
  final String realizationNotes;
  final DateTime? realizedDate;

  AssessmentActionPlan({
    this.id = '',
    required this.institutionId,
    required this.schoolTypeId,
    required this.title,
    required this.date,
    required this.createdBy,
    required this.creatorName,
    required this.selectedExamIds,
    required this.selectedExamNames,
    required this.classLevel,
    required this.subjectThresholds,
    required this.outcomeStats,
    required this.branchActionPlans,
    this.isActive = true,
    this.isRealized = false,
    this.realizationNotes = '',
    this.realizedDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'institutionId': institutionId,
      'schoolTypeId': schoolTypeId,
      'title': title,
      'date': Timestamp.fromDate(date),
      'createdBy': createdBy,
      'creatorName': creatorName,
      'selectedExamIds': selectedExamIds,
      'selectedExamNames': selectedExamNames,
      'classLevel': classLevel,
      'subjectThresholds': subjectThresholds,
      'outcomeStats': outcomeStats,
      'branchActionPlans': branchActionPlans,
      'isActive': isActive,
      'isRealized': isRealized,
      'realizationNotes': realizationNotes,
      'realizedDate': realizedDate != null ? Timestamp.fromDate(realizedDate!) : null,
    };
  }

  factory AssessmentActionPlan.fromMap(Map<String, dynamic> map, String docId) {
    return AssessmentActionPlan(
      id: docId,
      institutionId: map['institutionId'] ?? '',
      schoolTypeId: map['schoolTypeId'] ?? '',
      title: map['title'] ?? '',
      date: (map['date'] as Timestamp).toDate(),
      createdBy: map['createdBy'] ?? '',
      creatorName: map['creatorName'] ?? '',
      selectedExamIds: List<String>.from(map['selectedExamIds'] ?? []),
      selectedExamNames: List<String>.from(map['selectedExamNames'] ?? []),
      classLevel: map['classLevel'] ?? '',
      subjectThresholds: Map<String, double>.from(map['subjectThresholds'] ?? {}),
      outcomeStats: Map<String, dynamic>.from(map['outcomeStats'] ?? {}),
      branchActionPlans: Map<String, dynamic>.from(map['branchActionPlans'] ?? {}),
      isActive: map['isActive'] ?? true,
      isRealized: map['isRealized'] ?? false,
      realizationNotes: map['realizationNotes'] ?? '',
      realizedDate: map['realizedDate'] != null ? (map['realizedDate'] as Timestamp).toDate() : null,
    );
  }
}
