import 'package:cloud_firestore/cloud_firestore.dart';

class FieldTripGroup {
  final String id;
  final String name;
  final List<String> teacherIds;
  final List<String> teacherNames;
  final List<String> studentIds;
  final String? vehiclePlate; // Optional vehicle info
  final String? driverPhone; // Optional driver info

  FieldTripGroup({
    required this.id,
    required this.name,
    required this.teacherIds,
    required this.teacherNames,
    required this.studentIds,
    this.vehiclePlate,
    this.driverPhone,
  });

  factory FieldTripGroup.fromMap(Map<String, dynamic> map) {
    return FieldTripGroup(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      teacherIds: List<String>.from(map['teacherIds'] ?? []),
      teacherNames: List<String>.from(map['teacherNames'] ?? []),
      studentIds: List<String>.from(map['studentIds'] ?? []),
      vehiclePlate: map['vehiclePlate'],
      driverPhone: map['driverPhone'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'teacherIds': teacherIds,
      'teacherNames': teacherNames,
      'studentIds': studentIds,
      'vehiclePlate': vehiclePlate,
      'driverPhone': driverPhone,
    };
  }
}

class FieldTrip {
  final String id;
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;

  // Plan Details
  final String name;
  final String purpose;
  final DateTime departureTime;
  final DateTime returnTime;

  // Targets
  final String classLevel;
  final List<String> targetBranchIds;
  final List<String> targetStudentIds;
  final int totalStudents;

  // Survey
  final String? participationSurveyId;
  final DateTime? surveyPublishDate;

  // Manual Overrides
  final Map<String, String> manualParticipationStatus;

  // Payment
  final bool isPaid;
  final double amount;
  final Map<String, bool> paymentStatus;

  // Post-Trip Survey
  final String? feedbackSurveyId;

  // Groups
  final List<FieldTripGroup> groups;

  // Metadata
  final String authorId;
  final DateTime createdAt;
  final String status;

  FieldTrip({
    required this.id,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.name,
    required this.purpose,
    required this.departureTime,
    required this.returnTime,
    required this.classLevel,
    required this.targetBranchIds,
    required this.targetStudentIds,
    required this.totalStudents,
    this.participationSurveyId,
    this.surveyPublishDate,
    this.manualParticipationStatus = const {},
    required this.isPaid,
    required this.amount,
    required this.paymentStatus,
    this.feedbackSurveyId,
    this.groups = const [],
    required this.authorId,
    required this.createdAt,
    this.status = 'planned',
  });

  factory FieldTrip.fromMap(Map<String, dynamic> map, String id) {
    var groupsList = <FieldTripGroup>[];
    if (map['groups'] != null) {
      final list = map['groups'] as List<dynamic>;
      groupsList = list.map((g) {
        Map<String, dynamic> gMap = g as Map<String, dynamic>;

        // Migration helper
        if (gMap['teacherIds'] == null && gMap['teacherId'] != null) {
          gMap['teacherIds'] = [gMap['teacherId']];
          gMap['teacherNames'] = [gMap['teacherName'] ?? ''];
        }

        return FieldTripGroup.fromMap(gMap);
      }).toList();
    }

    return FieldTrip(
      id: id,
      institutionId: map['institutionId'] ?? '',
      schoolTypeId: map['schoolTypeId'] ?? '',
      schoolTypeName: map['schoolTypeName'] ?? '',
      name: map['name'] ?? '',
      purpose: map['purpose'] ?? '',
      departureTime: (map['departureTime'] as Timestamp).toDate(),
      returnTime: (map['returnTime'] as Timestamp).toDate(),
      classLevel: map['classLevel'] ?? '',
      targetBranchIds: List<String>.from(map['targetBranchIds'] ?? []),
      targetStudentIds: List<String>.from(map['targetStudentIds'] ?? []),
      totalStudents: map['totalStudents'] ?? 0,
      participationSurveyId: map['participationSurveyId'],
      surveyPublishDate: map['surveyPublishDate'] != null
          ? (map['surveyPublishDate'] as Timestamp).toDate()
          : null,
      manualParticipationStatus: Map<String, String>.from(
        map['manualParticipationStatus'] ?? {},
      ),
      isPaid: map['isPaid'] ?? false,
      amount: (map['amount'] ?? 0).toDouble(),
      paymentStatus: Map<String, bool>.from(map['paymentStatus'] ?? {}),
      feedbackSurveyId: map['feedbackSurveyId'],
      groups: groupsList,
      authorId: map['authorId'] ?? '',
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      status: map['status'] ?? 'planned',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'schoolTypeId': schoolTypeId,
      'schoolTypeName': schoolTypeName,
      'name': name,
      'purpose': purpose,
      'departureTime': Timestamp.fromDate(departureTime),
      'returnTime': Timestamp.fromDate(returnTime),
      'classLevel': classLevel,
      'targetBranchIds': targetBranchIds,
      'targetStudentIds': targetStudentIds,
      'totalStudents': totalStudents,
      'participationSurveyId': participationSurveyId,
      'surveyPublishDate': surveyPublishDate != null
          ? Timestamp.fromDate(surveyPublishDate!)
          : null,
      'manualParticipationStatus': manualParticipationStatus,
      'isPaid': isPaid,
      'amount': amount,
      'paymentStatus': paymentStatus,
      'feedbackSurveyId': feedbackSurveyId,
      'groups': groups.map((g) => g.toMap()).toList(),
      'authorId': authorId,
      'createdAt': Timestamp.fromDate(createdAt),
      'status': status,
    };
  }
}
