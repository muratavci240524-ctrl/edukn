import 'package:cloud_firestore/cloud_firestore.dart';

class TemporaryTeacherAssignment {
  final String id;
  final String institutionId;
  final String schoolTypeId;
  final String originalTeacherId;
  final String originalTeacherName;
  final String? substituteTeacherId;
  final String? substituteTeacherName;
  final String classId;
  final String className;
  final String lessonId;
  final String lessonName;
  final DateTime date;
  final int hourIndex; // 0-indexed lesson hour
  final String dayName;
  final String reason;
  final String status; // 'draft', 'published'
  final DateTime createdAt;
  final String creatorId;

  TemporaryTeacherAssignment({
    required this.id,
    required this.institutionId,
    required this.schoolTypeId,
    required this.originalTeacherId,
    required this.originalTeacherName,
    this.substituteTeacherId,
    this.substituteTeacherName,
    required this.classId,
    required this.className,
    required this.lessonId,
    required this.lessonName,
    required this.date,
    required this.hourIndex,
    required this.dayName,
    required this.reason,
    required this.status,
    required this.createdAt,
    required this.creatorId,
  });

  factory TemporaryTeacherAssignment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TemporaryTeacherAssignment(
      id: doc.id,
      institutionId: (data['institutionId'] ?? '').toString(),
      schoolTypeId: (data['schoolTypeId'] ?? '').toString(),
      originalTeacherId: (data['originalTeacherId'] ?? '').toString(),
      originalTeacherName: (data['originalTeacherName'] ?? '').toString(),
      substituteTeacherId: data['substituteTeacherId']?.toString(),
      substituteTeacherName: data['substituteTeacherName']?.toString(),
      classId: (data['classId'] ?? '').toString(),
      className: (data['className'] ?? '').toString(),
      lessonId: (data['lessonId'] ?? '').toString(),
      lessonName: (data['lessonName'] ?? '').toString(),
      date: (data['date'] as Timestamp).toDate(),
      hourIndex: data['hourIndex'] is int
          ? data['hourIndex']
          : int.tryParse(data['hourIndex'].toString()) ?? 0,
      dayName: (data['dayName'] ?? '').toString(),
      reason: (data['reason'] ?? '').toString(),
      status: (data['status'] ?? 'draft').toString(),
      createdAt: (data['createdAt'] as Timestamp? ?? Timestamp.now()).toDate(),
      creatorId: (data['creatorId'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'schoolTypeId': schoolTypeId,
      'originalTeacherId': originalTeacherId,
      'originalTeacherName': originalTeacherName,
      'substituteTeacherId': substituteTeacherId,
      'substituteTeacherName': substituteTeacherName,
      'classId': classId,
      'className': className,
      'lessonId': lessonId,
      'lessonName': lessonName,
      'date': Timestamp.fromDate(date),
      'hourIndex': hourIndex,
      'dayName': dayName,
      'reason': reason,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'creatorId': creatorId,
    };
  }
}
