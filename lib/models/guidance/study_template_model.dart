import 'package:cloud_firestore/cloud_firestore.dart';

class StudyTemplate {
  final String id;
  final String institutionId;
  final String name;
  final Map<String, List<String>> schedule;
  final DateTime createdAt;

  StudyTemplate({
    required this.id,
    required this.institutionId,
    required this.name,
    required this.schedule,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'institutionId': institutionId,
      'name': name,
      'schedule': schedule,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory StudyTemplate.fromMap(Map<String, dynamic> map) {
    // Check schedule type (Map<String, dynamic> from Firestore need conversion to Map<String, List<String>>)
    Map<String, List<String>> parsedSchedule = {};
    if (map['schedule'] != null) {
      (map['schedule'] as Map).forEach((key, value) {
        if (value is List) {
          parsedSchedule[key.toString()] = value
              .map((e) => e.toString())
              .toList();
        }
      });
    }

    return StudyTemplate(
      id: map['id'] ?? '',
      institutionId: map['institutionId'] ?? '',
      name: map['name'] ?? '',
      schedule: parsedSchedule,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
