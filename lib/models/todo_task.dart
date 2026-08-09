import 'package:cloud_firestore/cloud_firestore.dart';

class ToDoTask {
  final String id;
  final String title;
  final String description;
  final String creatorId;
  final String creatorName;
  final DateTime createdAt;
  final DateTime? deadline;
  final List<String> assigneeIds;
  final Map<String, String> assigneeNames;
  final List<String> completedBy;
  final String recurrence;
  final bool isArchived;
  final String? termId;
  /// uid → tamamladığı zaman
  final Map<String, DateTime> completedAt;

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
    this.termId,
    this.completedAt = const {},
  });

  factory ToDoTask.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // completedAt: {uid: Timestamp} map'i
    Map<String, DateTime> completedAtMap = {};
    final rawCompletedAt = data['completedAt'];
    if (rawCompletedAt is Map) {
      rawCompletedAt.forEach((k, v) {
        if (v is Timestamp) {
          completedAtMap[k.toString()] = v.toDate();
        }
      });
    }

    return ToDoTask(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      creatorId: data['creatorId'] ?? '',
      creatorName: data['creatorName'] ?? '',
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      deadline: data['deadline'] != null
          ? (data['deadline'] as Timestamp).toDate()
          : null,
      assigneeIds: List<String>.from(data['assigneeIds'] ?? []),
      assigneeNames: (data['assigneeNames'] as Map<dynamic, dynamic>? ?? {})
          .map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')),
      completedBy: List<String>.from(data['completedBy'] ?? []),
      recurrence: data['recurrence'] ?? 'none',
      isArchived: data['isArchived'] ?? false,
      termId: data['termId'] as String?,
      completedAt: completedAtMap,
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
      'completedAt': completedAt.map((k, v) => MapEntry(k, Timestamp.fromDate(v))),
      'recurrence': recurrence,
      'isArchived': isArchived,
      if (termId != null) 'termId': termId,
    };
  }
}
