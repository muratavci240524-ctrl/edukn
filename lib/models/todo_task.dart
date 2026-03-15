import 'package:cloud_firestore/cloud_firestore.dart';

class ToDoTask {
  final String id;
  final String title;
  final String description;
  final String creatorId;
  final String creatorName;
  final DateTime createdAt;
  final DateTime? deadline;
  final List<String> assigneeIds; // UIDs of people assigned
  final Map<String, String> assigneeNames; // UID -> Name mapping for display
  final List<String>
  completedBy; // UIDs of people who completed this specific instance
  final String recurrence; // 'none', 'daily', 'weekly', 'monthly'
  final bool isArchived;

  ToDoTask({
    required this.id,
    required this.title,
    required this.description,
    required this.creatorId,
    required this.creatorName,
    required this.createdAt,
    this.deadline,
    required this.assigneeIds,
    required this.assigneeNames,
    required this.completedBy,
    required this.recurrence,
    this.isArchived = false,
  });

  factory ToDoTask.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ToDoTask(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      creatorId: data['creatorId'] ?? '',
      creatorName: data['creatorName'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      deadline: data['deadline'] != null
          ? (data['deadline'] as Timestamp).toDate()
          : null,
      assigneeIds: List<String>.from(data['assigneeIds'] ?? []),
      assigneeNames: Map<String, String>.from(data['assigneeNames'] ?? {}),
      completedBy: List<String>.from(data['completedBy'] ?? []),
      recurrence: data['recurrence'] ?? 'none',
      isArchived: data['isArchived'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'creatorId': creatorId,
      'creatorName': creatorName,
      'createdAt': Timestamp.fromDate(createdAt),
      'deadline': deadline != null ? Timestamp.fromDate(deadline!) : null,
      'assigneeIds': assigneeIds,
      'assigneeNames': assigneeNames,
      'completedBy': completedBy,
      'recurrence': recurrence,
      'isArchived': isArchived,
    };
  }
}
