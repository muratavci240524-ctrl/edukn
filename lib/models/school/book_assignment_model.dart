import 'package:cloud_firestore/cloud_firestore.dart';

enum BookAssignmentTarget { schoolType, classLevel, className, student }

class BookAssignment {
  final String id;
  final String institutionId;
  final String bookId;
  final BookAssignmentTarget targetType;
  final String
  targetId; // schoolTypeId, classLevel string, className string, or studentId
  final String? targetName; // For easy display
  final DateTime assignedAt;

  BookAssignment({
    required this.id,
    required this.institutionId,
    required this.bookId,
    required this.targetType,
    required this.targetId,
    this.targetName,
    required this.assignedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'bookId': bookId,
      'targetType': targetType.name,
      'targetId': targetId,
      'targetName': targetName,
      'assignedAt': Timestamp.fromDate(assignedAt),
    };
  }

  factory BookAssignment.fromMap(Map<String, dynamic> map, String id) {
    return BookAssignment(
      id: id,
      institutionId: map['institutionId'] ?? '',
      bookId: map['bookId'] ?? '',
      targetType: BookAssignmentTarget.values.byName(
        map['targetType'] ?? 'student',
      ),
      targetId: map['targetId'] ?? '',
      targetName: map['targetName'],
      assignedAt: (map['assignedAt'] as Timestamp).toDate(),
    );
  }
}
