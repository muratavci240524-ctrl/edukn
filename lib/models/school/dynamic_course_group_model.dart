import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Dinamik Ders Grubu Türü: Kurlu Ders (Track) veya Kulüp/Seçmeli Ders (Club)
enum DynamicCourseGroupType {
  track, // Kurlu ders (İngilizce, Almanca vb. seviye kurları)
  club,  // Kulüp / Seçmeli ders (Futsal, Robotik, Satranç vb. çok branşlı)
}

extension DynamicCourseGroupTypeExtension on DynamicCourseGroupType {
  String get title {
    switch (this) {
      case DynamicCourseGroupType.track:
        return 'Kurlu Ders (Seviye Grubu)';
      case DynamicCourseGroupType.club:
        return 'Kulüp / Seçmeli Ders';
    }
  }

  String get shortLabel {
    switch (this) {
      case DynamicCourseGroupType.track:
        return 'Kur';
      case DynamicCourseGroupType.club:
        return 'Kulüp';
    }
  }

  IconData get icon {
    switch (this) {
      case DynamicCourseGroupType.track:
        return Icons.layers_outlined;
      case DynamicCourseGroupType.club:
        return Icons.sports_soccer_outlined;
    }
  }

  Color get color {
    switch (this) {
      case DynamicCourseGroupType.track:
        return const Color(0xFF6366F1); // Indigo
      case DynamicCourseGroupType.club:
        return const Color(0xFF10B981); // Emerald Green
    }
  }
}

/// Bir Kur veya Kulüp içindeki alt grup (Örn: "Kur 1 (A1)" veya "Futsal Kulübü")
class DynamicSubGroup {
  final String id;
  final String name;
  final String shortName;
  final List<String> teacherIds;
  final List<String> teacherNames;
  final String classroomName;
  final int? capacity;
  final List<String> studentIds;
  final String? description;

  const DynamicSubGroup({
    required this.id,
    required this.name,
    this.shortName = '',
    this.teacherIds = const [],
    this.teacherNames = const [],
    this.classroomName = '',
    this.capacity,
    this.studentIds = const [],
    this.description,
  });

  factory DynamicSubGroup.fromMap(Map<String, dynamic> map) {
    return DynamicSubGroup(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      shortName: map['shortName']?.toString() ?? '',
      teacherIds: List<String>.from(map['teacherIds'] ?? []),
      teacherNames: List<String>.from(map['teacherNames'] ?? []),
      classroomName: map['classroomName']?.toString() ?? '',
      capacity: map['capacity'] is int ? map['capacity'] : int.tryParse(map['capacity']?.toString() ?? ''),
      studentIds: List<String>.from(map['studentIds'] ?? []),
      description: map['description']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'shortName': shortName,
      'teacherIds': teacherIds,
      'teacherNames': teacherNames,
      'classroomName': classroomName,
      'capacity': capacity,
      'studentIds': studentIds,
      'description': description,
    };
  }

  DynamicSubGroup copyWith({
    String? id,
    String? name,
    String? shortName,
    List<String>? teacherIds,
    List<String>? teacherNames,
    String? classroomName,
    int? capacity,
    List<String>? studentIds,
    String? description,
  }) {
    return DynamicSubGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      shortName: shortName ?? this.shortName,
      teacherIds: teacherIds ?? this.teacherIds,
      teacherNames: teacherNames ?? this.teacherNames,
      classroomName: classroomName ?? this.classroomName,
      capacity: capacity ?? this.capacity,
      studentIds: studentIds ?? this.studentIds,
      description: description ?? this.description,
    );
  }
}

/// Ana Dinamik Ders Grubu Modeli
class DynamicCourseGroup {
  final String id;
  final String institutionId;
  final String schoolTypeId;
  final String? termId;
  final String? periodId;
  final String? subTermId;
  final String? periodName;
  final DynamicCourseGroupType type;
  final String name;
  final String lessonId;
  final String lessonName;
  final List<String> targetClassIds;
  final List<String> targetClassNames;
  final List<int> targetGradeLevels;
  final List<DynamicSubGroup> subGroups;
  final bool isActive;
  final String? day;
  final int? hourIndex;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const DynamicCourseGroup({
    required this.id,
    required this.institutionId,
    required this.schoolTypeId,
    this.termId,
    this.periodId,
    this.subTermId,
    this.periodName,
    required this.type,
    required this.name,
    required this.lessonId,
    required this.lessonName,
    this.targetClassIds = const [],
    this.targetClassNames = const [],
    this.targetGradeLevels = const [],
    this.subGroups = const [],
    this.isActive = true,
    this.day,
    this.hourIndex,
    this.createdAt,
    this.updatedAt,
  });

  /// Toplam kayıtlı öğrenci sayısı
  int get totalStudentCount {
    return subGroups.fold<int>(0, (prev, g) => prev + g.studentIds.length);
  }

  /// Öğrencinin hangi alt grupta olduğunu bulur
  DynamicSubGroup? findSubGroupForStudent(String studentId) {
    for (var g in subGroups) {
      if (g.studentIds.contains(studentId)) {
        return g;
      }
    }
    return null;
  }

  /// Öğretmenin hangi alt grupta olduğunu bulur
  List<DynamicSubGroup> findSubGroupsForTeacher(String teacherId) {
    return subGroups.where((g) => g.teacherIds.contains(teacherId)).toList();
  }

  factory DynamicCourseGroup.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return DynamicCourseGroup.fromMap(data, doc.id);
  }

  factory DynamicCourseGroup.fromMap(Map<String, dynamic> map, [String? docId]) {
    final typeStr = map['type']?.toString() ?? 'track';
    final type = typeStr == 'club' ? DynamicCourseGroupType.club : DynamicCourseGroupType.track;

    final subGroupsRaw = map['subGroups'] as List<dynamic>? ?? [];
    final subGroups = subGroupsRaw
        .map((e) => DynamicSubGroup.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();

    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    final pId = map['periodId']?.toString() ?? map['subTermId']?.toString();

    return DynamicCourseGroup(
      id: docId ?? map['id']?.toString() ?? '',
      institutionId: map['institutionId']?.toString() ?? '',
      schoolTypeId: map['schoolTypeId']?.toString() ?? '',
      termId: map['termId']?.toString(),
      periodId: pId,
      subTermId: pId,
      periodName: map['periodName']?.toString(),
      type: type,
      name: map['name']?.toString() ?? '',
      lessonId: map['lessonId']?.toString() ?? '',
      lessonName: map['lessonName']?.toString() ?? '',
      targetClassIds: List<String>.from(map['targetClassIds'] ?? []),
      targetClassNames: List<String>.from(map['targetClassNames'] ?? []),
      targetGradeLevels: (map['targetGradeLevels'] as List<dynamic>? ?? [])
          .map((e) => e is int ? e : int.tryParse(e.toString()) ?? 0)
          .where((e) => e > 0)
          .toList(),
      subGroups: subGroups,
      isActive: map['isActive'] as bool? ?? true,
      day: map['day']?.toString(),
      hourIndex: map['hourIndex'] is int ? map['hourIndex'] : int.tryParse(map['hourIndex']?.toString() ?? ''),
      createdAt: parseDate(map['createdAt']),
      updatedAt: parseDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'institutionId': institutionId,
      'schoolTypeId': schoolTypeId,
      'termId': termId,
      'periodId': periodId ?? subTermId,
      'subTermId': subTermId ?? periodId,
      'periodName': periodName,
      'type': type == DynamicCourseGroupType.club ? 'club' : 'track',
      'name': name,
      'lessonId': lessonId,
      'lessonName': lessonName,
      'targetClassIds': targetClassIds,
      'targetClassNames': targetClassNames,
      'targetGradeLevels': targetGradeLevels,
      'subGroups': subGroups.map((g) => g.toMap()).toList(),
      'isActive': isActive,
      'day': day,
      'hourIndex': hourIndex,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  DynamicCourseGroup copyWith({
    String? id,
    String? institutionId,
    String? schoolTypeId,
    String? termId,
    String? periodId,
    String? subTermId,
    String? periodName,
    DynamicCourseGroupType? type,
    String? name,
    String? lessonId,
    String? lessonName,
    List<String>? targetClassIds,
    List<String>? targetClassNames,
    List<int>? targetGradeLevels,
    List<DynamicSubGroup>? subGroups,
    bool? isActive,
    String? day,
    int? hourIndex,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DynamicCourseGroup(
      id: id ?? this.id,
      institutionId: institutionId ?? this.institutionId,
      schoolTypeId: schoolTypeId ?? this.schoolTypeId,
      termId: termId ?? this.termId,
      periodId: periodId ?? this.periodId,
      subTermId: subTermId ?? this.subTermId,
      periodName: periodName ?? this.periodName,
      type: type ?? this.type,
      name: name ?? this.name,
      lessonId: lessonId ?? this.lessonId,
      lessonName: lessonName ?? this.lessonName,
      targetClassIds: targetClassIds ?? this.targetClassIds,
      targetClassNames: targetClassNames ?? this.targetClassNames,
      targetGradeLevels: targetGradeLevels ?? this.targetGradeLevels,
      subGroups: subGroups ?? this.subGroups,
      isActive: isActive ?? this.isActive,
      day: day ?? this.day,
      hourIndex: hourIndex ?? this.hourIndex,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
