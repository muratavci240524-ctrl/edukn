import 'package:cloud_firestore/cloud_firestore.dart';

class ClassroomModel {
  final String? id;
  final String classroomName; // Derslik adı (örn: A101, Fen Lab)
  final String classroomCode; // Kısa kod (örn: A101)
  final String? classroomType; // Derslik tipi (Sınıf, Laboratuvar, Spor Salonu vb.)
  final int capacity; // Kapasite
  final String? floor; // Kat bilgisi
  final String? building; // Bina bilgisi
  final String? description; // Açıklama
  final String schoolTypeId; // Okul türü ID
  final String schoolTypeName; // Okul türü adı
  final String institutionId; // Kurum ID
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isActive;

  ClassroomModel({
    this.id,
    required this.classroomName,
    required this.classroomCode,
    this.classroomType,
    required this.capacity,
    this.floor,
    this.building,
    this.description,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
    required this.createdAt,
    this.updatedAt,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'classroomName': classroomName,
      'classroomCode': classroomCode,
      'classroomType': classroomType,
      'capacity': capacity,
      'floor': floor,
      'building': building,
      'description': description,
      'schoolTypeId': schoolTypeId,
      'schoolTypeName': schoolTypeName,
      'institutionId': institutionId,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'isActive': isActive,
    };
  }

  factory ClassroomModel.fromMap(Map<String, dynamic> map, String id) {
    return ClassroomModel(
      id: id,
      classroomName: map['classroomName'] ?? '',
      classroomCode: map['classroomCode'] ?? '',
      classroomType: map['classroomType'],
      capacity: map['capacity'] ?? 0,
      floor: map['floor'],
      building: map['building'],
      description: map['description'],
      schoolTypeId: map['schoolTypeId'] ?? '',
      schoolTypeName: map['schoolTypeName'] ?? '',
      institutionId: map['institutionId'] ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      isActive: map['isActive'] ?? true,
    );
  }
}
