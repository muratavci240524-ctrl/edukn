import 'package:cloud_firestore/cloud_firestore.dart';

class ClassModel {
  final String? id;
  final String className; // Sınıf adı (örn: 8-A, 12-B)
  final String shortName; // Kısa ad (örn: 8A, 12B) - max 5 karakter
  final String classTypeId; // Sınıf tipi ID'si
  final String classTypeName; // Sınıf tipi adı (örn: Ders Sınıfı, Sayısal, Sözel)
  final String? classTeacherId; // Sınıf öğretmeni ID
  final String? classTeacherName; // Sınıf öğretmeni adı
  final String? guidanceCounselorId; // Rehber öğretmen ID
  final String? guidanceCounselorName; // Rehber öğretmen adı
  final String? classroomId; // Derslik ID (zorunlu)
  final String? classroomName; // Derslik adı
  final int classLevel; // Sınıf seviyesi (1-12)
  final String? description; // Açıklama
  final String schoolTypeId; // Okul türü ID
  final String schoolTypeName; // Okul türü adı
  final String institutionId; // Kurum ID
  final String? termId; // Dönem ID
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isActive;

  ClassModel({
    this.id,
    required this.className,
    required this.shortName,
    required this.classTypeId,
    required this.classTypeName,
    this.classTeacherId,
    this.classTeacherName,
    this.guidanceCounselorId,
    this.guidanceCounselorName,
    this.classroomId,
    this.classroomName,
    required this.classLevel,
    this.description,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
    this.termId,
    required this.createdAt,
    this.updatedAt,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'className': className,
      'shortName': shortName,
      'classTypeId': classTypeId,
      'classTypeName': classTypeName,
      'classTeacherId': classTeacherId,
      'classTeacherName': classTeacherName,
      'guidanceCounselorId': guidanceCounselorId,
      'guidanceCounselorName': guidanceCounselorName,
      'classroomId': classroomId,
      'classroomName': classroomName,
      'classLevel': classLevel,
      'description': description,
      'schoolTypeId': schoolTypeId,
      'schoolTypeName': schoolTypeName,
      'institutionId': institutionId,
      'termId': termId,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'isActive': isActive,
    };
  }

  factory ClassModel.fromMap(Map<String, dynamic> map, String id) {
    return ClassModel(
      id: id,
      className: map['className'] ?? '',
      shortName: map['shortName'] ?? '',
      classTypeId: map['classTypeId'] ?? '',
      classTypeName: map['classTypeName'] ?? '',
      classTeacherId: map['classTeacherId'],
      classTeacherName: map['classTeacherName'],
      guidanceCounselorId: map['guidanceCounselorId'],
      guidanceCounselorName: map['guidanceCounselorName'],
      classroomId: map['classroomId'],
      classroomName: map['classroomName'],
      classLevel: map['classLevel'] ?? 1,
      description: map['description'],
      schoolTypeId: map['schoolTypeId'] ?? '',
      schoolTypeName: map['schoolTypeName'] ?? '',
      institutionId: map['institutionId'] ?? '',
      termId: map['termId'],
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      isActive: map['isActive'] ?? true,
    );
  }

  ClassModel copyWith({
    String? id,
    String? className,
    String? shortName,
    String? classTypeId,
    String? classTypeName,
    String? classTeacherId,
    String? classTeacherName,
    String? guidanceCounselorId,
    String? guidanceCounselorName,
    String? classroomId,
    String? classroomName,
    int? classLevel,
    String? description,
    String? schoolTypeId,
    String? schoolTypeName,
    String? institutionId,
    String? termId,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
  }) {
    return ClassModel(
      id: id ?? this.id,
      className: className ?? this.className,
      shortName: shortName ?? this.shortName,
      classTypeId: classTypeId ?? this.classTypeId,
      classTypeName: classTypeName ?? this.classTypeName,
      classTeacherId: classTeacherId ?? this.classTeacherId,
      classTeacherName: classTeacherName ?? this.classTeacherName,
      guidanceCounselorId: guidanceCounselorId ?? this.guidanceCounselorId,
      guidanceCounselorName: guidanceCounselorName ?? this.guidanceCounselorName,
      classroomId: classroomId ?? this.classroomId,
      classroomName: classroomName ?? this.classroomName,
      classLevel: classLevel ?? this.classLevel,
      description: description ?? this.description,
      schoolTypeId: schoolTypeId ?? this.schoolTypeId,
      schoolTypeName: schoolTypeName ?? this.schoolTypeName,
      institutionId: institutionId ?? this.institutionId,
      termId: termId ?? this.termId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
    );
  }
}

class ClassTypeModel {
  final String? id;
  final String typeName; // Sınıf tipi adı (örn: Ders Sınıfı, Sayısal, Sözel, LGS Grubu)
  final String? description;
  final String institutionId;
  final DateTime createdAt;
  final bool isDefault; // Varsayılan tip mi (Ders Sınıfı)

  ClassTypeModel({
    this.id,
    required this.typeName,
    this.description,
    required this.institutionId,
    required this.createdAt,
    this.isDefault = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'typeName': typeName,
      'description': description,
      'institutionId': institutionId,
      'createdAt': createdAt,
      'isDefault': isDefault,
    };
  }

  factory ClassTypeModel.fromMap(Map<String, dynamic> map, String id) {
    return ClassTypeModel(
      id: id,
      typeName: map['typeName'] ?? '',
      description: map['description'],
      institutionId: map['institutionId'] ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isDefault: map['isDefault'] ?? false,
    );
  }
}
