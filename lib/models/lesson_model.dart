import 'package:cloud_firestore/cloud_firestore.dart';

/// Ders modeli
class LessonModel {
  final String? id;
  final String lessonName;
  final String shortName; // Dersin kısa adı (max 4 karakter)
  final String branchId;
  final String branchName;
  final String schoolTypeId;
  final String institutionId;
  final String? termId;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  LessonModel({
    this.id,
    required this.lessonName,
    this.shortName = '',
    required this.branchId,
    required this.branchName,
    required this.schoolTypeId,
    required this.institutionId,
    this.termId,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory LessonModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return LessonModel(
      id: doc.id,
      lessonName: data['lessonName'] ?? '',
      shortName: data['shortName'] ?? '',
      branchId: data['branchId'] ?? '',
      branchName: data['branchName'] ?? '',
      schoolTypeId: data['schoolTypeId'] ?? '',
      institutionId: data['institutionId'] ?? '',
      termId: data['termId'],
      isActive: data['isActive'] ?? true,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'lessonName': lessonName,
      'shortName': shortName,
      'branchId': branchId,
      'branchName': branchName,
      'schoolTypeId': schoolTypeId,
      'institutionId': institutionId,
      'termId': termId,
      'isActive': isActive,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

/// Ders-Sınıf Atama modeli
class LessonClassAssignment {
  final String? id;
  final String lessonId;
  final String lessonName;
  final String classId;
  final String className;
  final int weeklyHours; // Haftalık ders saati
  final List<String> teacherIds; // Atanan öğretmenler
  final List<String> teacherNames; // Öğretmen isimleri
  final String schoolTypeId;
  final String institutionId;
  final bool isActive;

  LessonClassAssignment({
    this.id,
    required this.lessonId,
    required this.lessonName,
    required this.classId,
    required this.className,
    required this.weeklyHours,
    required this.teacherIds,
    required this.teacherNames,
    required this.schoolTypeId,
    required this.institutionId,
    this.isActive = true,
  });

  factory LessonClassAssignment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return LessonClassAssignment(
      id: doc.id,
      lessonId: data['lessonId'] ?? '',
      lessonName: data['lessonName'] ?? '',
      classId: data['classId'] ?? '',
      className: data['className'] ?? '',
      weeklyHours: data['weeklyHours'] ?? 0,
      teacherIds: List<String>.from(data['teacherIds'] ?? []),
      teacherNames: List<String>.from(data['teacherNames'] ?? []),
      schoolTypeId: data['schoolTypeId'] ?? '',
      institutionId: data['institutionId'] ?? '',
      isActive: data['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'lessonId': lessonId,
      'lessonName': lessonName,
      'classId': classId,
      'className': className,
      'weeklyHours': weeklyHours,
      'teacherIds': teacherIds,
      'teacherNames': teacherNames,
      'schoolTypeId': schoolTypeId,
      'institutionId': institutionId,
      'isActive': isActive,
    };
  }
}

/// Branş modeli
class BranchModel {
  final String? id;
  final String branchName;
  final String institutionId;
  final bool isDefault; // Sistem tarafından tanımlanan varsayılan branş mı?
  final bool isActive;

  BranchModel({
    this.id,
    required this.branchName,
    required this.institutionId,
    this.isDefault = false,
    this.isActive = true,
  });

  factory BranchModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BranchModel(
      id: doc.id,
      branchName: data['branchName'] ?? '',
      institutionId: data['institutionId'] ?? '',
      isDefault: data['isDefault'] ?? false,
      isActive: data['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'branchName': branchName,
      'institutionId': institutionId,
      'isDefault': isDefault,
      'isActive': isActive,
    };
  }
}
