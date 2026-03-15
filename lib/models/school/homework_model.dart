import 'package:cloud_firestore/cloud_firestore.dart';

enum HomeworkStatus {
  pending, // 0 - Henüz kontrol edilmedi / İşlem yapılmadı
  completed, // 1 - Yaptı (Tam Puan/Yeşil)
  notCompleted, // 2 - Yapmadı (Kırmızı)
  missing, // 3 - Eksik Yaptı (Turuncu)
  notBrought, // 4 - Getirmedi (Mor)
}

class Homework {
  final String id;
  final String institutionId;
  final String classId;
  final String lessonId;
  final String teacherId;
  final String title;
  final String content;
  final DateTime createdAt; // Kayıt tarihi
  final DateTime assignedDate; // Öğrenciye görünecek tarih (Veriliş)
  final DateTime dueDate; // Son Kontrol
  final List<HomeworkAttachment> attachments;
  final List<String> targetStudentIds;
  final Map<String, int> studentStatuses; // studentId -> status index

  Homework({
    required this.id,
    required this.institutionId,
    required this.classId,
    required this.lessonId,
    required this.teacherId,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.assignedDate,
    required this.dueDate,
    this.attachments = const [],
    required this.targetStudentIds,
    this.studentStatuses = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'institutionId': institutionId,
      'classId': classId,
      'lessonId': lessonId,
      'teacherId': teacherId,
      'title': title,
      'content': content,
      'createdAt': Timestamp.fromDate(createdAt),
      'assignedDate': Timestamp.fromDate(assignedDate),
      'dueDate': Timestamp.fromDate(dueDate),
      'attachments': attachments.map((x) => x.toMap()).toList(),
      'targetStudentIds': targetStudentIds,
      'studentStatuses': studentStatuses,
    };
  }

  factory Homework.fromMap(Map<String, dynamic> map) {
    return Homework(
      id: map['id'] ?? '',
      institutionId: map['institutionId'] ?? '',
      classId: map['classId'] ?? '',
      lessonId: map['lessonId'] ?? '',
      teacherId: map['teacherId'] ?? '',
      title: map['title'] ?? '',
      content: map['content'] ?? '',
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      assignedDate: map['assignedDate'] != null
          ? (map['assignedDate'] as Timestamp).toDate()
          : (map['createdAt'] as Timestamp).toDate(),
      dueDate: (map['dueDate'] as Timestamp).toDate(),
      attachments:
          (map['attachments'] as List<dynamic>?)
              ?.map((x) => HomeworkAttachment.fromMap(x))
              .toList() ??
          [],
      targetStudentIds: List<String>.from(map['targetStudentIds'] ?? []),
      studentStatuses: Map<String, int>.from(map['studentStatuses'] ?? {}),
    );
  }
}

class HomeworkAttachment {
  final String type; // 'file', 'link'
  final String title;
  final String url;

  HomeworkAttachment({
    required this.type,
    required this.title,
    required this.url,
  });

  Map<String, dynamic> toMap() {
    return {'type': type, 'title': title, 'url': url};
  }

  factory HomeworkAttachment.fromMap(Map<String, dynamic> map) {
    return HomeworkAttachment(
      type: map['type'] ?? 'link',
      title: map['title'] ?? '',
      url: map['url'] ?? '',
    );
  }
}
