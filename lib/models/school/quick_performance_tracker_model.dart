import 'package:cloud_firestore/cloud_firestore.dart';

/// Performans Kayıt Türü (+ / -)
enum PerformanceRecordType {
  plus,
  minus,
}

/// Tekil Performans Kaydı Modeli
class PerformanceRecord {
  final String id;
  final String institutionId;
  final String classId;
  final String className;
  final String studentId;
  final String studentName;
  final String type; // 'plus' veya 'minus'
  final int scoreChange; // +1 veya -1
  final String? note;
  final DateTime createdAt;
  final String dateKey; // 'yyyy-MM-dd' formatı
  final String? teacherId;
  final String? teacherName;

  PerformanceRecord({
    required this.id,
    required this.institutionId,
    required this.classId,
    required this.className,
    required this.studentId,
    required this.studentName,
    required this.type,
    required this.scoreChange,
    this.note,
    required this.createdAt,
    required this.dateKey,
    this.teacherId,
    this.teacherName,
  });

  bool get isPlus => type == 'plus';
  bool get isMinus => type == 'minus';

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'classId': classId,
      'className': className,
      'studentId': studentId,
      'studentName': studentName,
      'type': type,
      'scoreChange': scoreChange,
      'note': note,
      'createdAt': Timestamp.fromDate(createdAt),
      'dateKey': dateKey,
      'teacherId': teacherId,
      'teacherName': teacherName,
    };
  }

  factory PerformanceRecord.fromMap(Map<String, dynamic> map, String id) {
    DateTime parsedDate = DateTime.now();
    if (map['createdAt'] is Timestamp) {
      parsedDate = (map['createdAt'] as Timestamp).toDate();
    } else if (map['createdAt'] is String) {
      parsedDate = DateTime.tryParse(map['createdAt']) ?? DateTime.now();
    }

    return PerformanceRecord(
      id: id,
      institutionId: map['institutionId'] ?? '',
      classId: map['classId'] ?? '',
      className: map['className'] ?? '',
      studentId: map['studentId'] ?? '',
      studentName: map['studentName'] ?? '',
      type: map['type'] ?? 'plus',
      scoreChange: map['scoreChange'] ?? (map['type'] == 'minus' ? -1 : 1),
      note: map['note'],
      createdAt: parsedDate,
      dateKey: map['dateKey'] ?? '',
      teacherId: map['teacherId'],
      teacherName: map['teacherName'],
    );
  }
}

/// Hızlı Performans Takibinde Listelenen Öğrenci Modeli
class QuickPerformanceStudent {
  final String id;
  final String name;
  final String? studentNumber;
  final String? className;
  final String gender; // 'E', 'K' veya 'unspecified'
  final String? avatarUrl;

  // Seçilen gün içindeki canlı sayaçlar
  int plusCount;
  int minusCount;
  List<PerformanceRecord> records;

  QuickPerformanceStudent({
    required this.id,
    required this.name,
    this.studentNumber,
    this.className,
    this.gender = 'unspecified',
    this.avatarUrl,
    this.plusCount = 0,
    this.minusCount = 0,
    List<PerformanceRecord>? records,
  }) : records = records ?? [];

  int get netScore => plusCount - minusCount;

  bool get isFemale {
    final g = gender.trim().toLowerCase();
    return g.startsWith('k') || g.startsWith('f') || g == 'kadın' || g == 'kız';
  }

  bool get isMale {
    final g = gender.trim().toLowerCase();
    return g.startsWith('e') || g.startsWith('m') || g == 'erkek';
  }
}
