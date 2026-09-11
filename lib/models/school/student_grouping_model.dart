import 'package:flutter/material.dart';

/// Dağıtım Modları
enum GroupingMode {
  /// Tamamen rastgele karıştırma
  random,

  /// Heterojen / Dengeli (Not ortalamalarını eşitleyen Serpentine Yılan Algoritması)
  balanced,

  /// Homojen / Seviye Odaklı (Benzer puanlı öğrencileri aynı gruba toplar)
  tiered,
}

extension GroupingModeExtension on GroupingMode {
  String get title {
    switch (this) {
      case GroupingMode.random:
        return 'Rastgele (Random)';
      case GroupingMode.balanced:
        return 'Dengeli / Heterojen (Serpentine)';
      case GroupingMode.tiered:
        return 'Seviye Odaklı / Homojen (Tiered)';
    }
  }

  String get description {
    switch (this) {
      case GroupingMode.random:
        return 'Öğrencileri tamamen şansa bağlı ve tarafsız şekilde gruplara böler.';
      case GroupingMode.balanced:
        return 'Tüm grupların başarı puanı ortalamasını eşitler (Yılan Draft algoritması).';
      case GroupingMode.tiered:
        return 'Benzer akademik seviyedeki öğrencileri aynı seviye gruplarında toplar.';
    }
  }

  IconData get icon {
    switch (this) {
      case GroupingMode.random:
        return Icons.casino_rounded;
      case GroupingMode.balanced:
        return Icons.balance_rounded;
      case GroupingMode.tiered:
        return Icons.layers_rounded;
    }
  }

  Color get color {
    switch (this) {
      case GroupingMode.random:
        return const Color(0xFF8B5CF6);
      case GroupingMode.balanced:
        return const Color(0xFF10B981);
      case GroupingMode.tiered:
        return const Color(0xFF3B82F6);
    }
  }
}

/// Gruplamada kullanılan öğrenci modeli
class GroupingStudent {
  final String id;
  final String name;
  final String? studentNumber;
  final String? className;
  final String gender; // 'E', 'K' veya 'unspecified'
  double academicScore; // 0 - 100 arası başarı puanı
  final String? avatarUrl;

  GroupingStudent({
    required this.id,
    required this.name,
    this.studentNumber,
    this.className,
    this.gender = 'unspecified',
    this.academicScore = 70.0,
    this.avatarUrl,
  });

  bool get isFemale {
    final g = gender.trim().toLowerCase();
    return g.startsWith('k') || g.startsWith('f') || g == 'kadın' || g == 'kız';
  }

  bool get isMale {
    final g = gender.trim().toLowerCase();
    return g.startsWith('e') || g.startsWith('m') || g == 'erkek';
  }

  GroupingStudent clone() {
    return GroupingStudent(
      id: id,
      name: name,
      studentNumber: studentNumber,
      className: className,
      gender: gender,
      academicScore: academicScore,
      avatarUrl: avatarUrl,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'studentNumber': studentNumber,
      'className': className,
      'gender': gender,
      'academicScore': academicScore,
      'avatarUrl': avatarUrl,
    };
  }

  factory GroupingStudent.fromMap(Map<String, dynamic> map) {
    return GroupingStudent(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      studentNumber: map['studentNumber']?.toString(),
      className: map['className']?.toString(),
      gender: map['gender'] ?? 'unspecified',
      academicScore: (map['academicScore'] is num)
          ? (map['academicScore'] as num).toDouble()
          : 70.0,
      avatarUrl: map['avatarUrl'],
    );
  }
}

/// Öğrenci Grubu Modeli
class StudentGroup {
  final String id;
  String groupName;
  Color groupColor;
  List<GroupingStudent> students;

  StudentGroup({
    required this.id,
    required this.groupName,
    required this.groupColor,
    List<GroupingStudent>? students,
  }) : students = students ?? [];

  /// Grubun ortalama başarı puanı
  double get averageScore {
    if (students.isEmpty) return 0.0;
    final total = students.fold<double>(0.0, (sum, s) => sum + s.academicScore);
    return total / students.length;
  }

  /// Kız öğrenci sayısı
  int get femaleCount => students.where((s) => s.isFemale).length;

  /// Erkek öğrenci sayısı
  int get maleCount => students.where((s) => s.isMale).length;

  /// Toplam öğrenci sayısı
  int get totalStudents => students.length;

  StudentGroup clone() {
    return StudentGroup(
      id: id,
      groupName: groupName,
      groupColor: groupColor,
      students: students.map((s) => s.clone()).toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'groupName': groupName,
      'colorHex': '#${groupColor.value.toRadixString(16).padLeft(8, '0')}',
      'students': students.map((s) => s.toMap()).toList(),
    };
  }

  factory StudentGroup.fromMap(Map<String, dynamic> map) {
    Color parsedColor = const Color(0xFF5C6BC0);
    if (map['colorHex'] != null) {
      try {
        final hexStr = map['colorHex'].toString().replaceAll('#', '');
        parsedColor = Color(int.parse(hexStr, radix: 16));
      } catch (_) {}
    }

    final rawStudents = (map['students'] as List?) ?? [];
    return StudentGroup(
      id: map['id'] ?? '',
      groupName: map['groupName'] ?? '',
      groupColor: parsedColor,
      students: rawStudents.map((s) => GroupingStudent.fromMap(Map<String, dynamic>.from(s))).toList(),
    );
  }
}

/// Kural Türü: Birlikte Olsun (Whitelist) veya Birlikte Olmasın (Blacklist)
enum GroupingRuleType {
  /// 🟢 Birlikte Olsun (Aynı Grupta)
  together,

  /// 🔴 Birlikte Olmasın (Farklı Grupta)
  apart,
}

/// Öğrenci Eşleşme / Dışlama Kuralı (Birlikte Olsun / Olmasın)
class BlacklistRule {
  final String student1Id;
  final String student1Name;
  final String student2Id;
  final String student2Name;
  final GroupingRuleType type; // together (🟢) veya apart (🔴)
  final String? note;

  BlacklistRule({
    required this.student1Id,
    required this.student1Name,
    required this.student2Id,
    required this.student2Name,
    this.type = GroupingRuleType.apart,
    this.note,
  });

  bool get isTogether => type == GroupingRuleType.together;
  bool get isApart => type == GroupingRuleType.apart;

  /// Bu kural verilen iki öğrenciyi kapsıyor mu?
  bool conflicts(String idA, String idB) {
    return (student1Id == idA && student2Id == idB) ||
        (student1Id == idB && student2Id == idA);
  }

  BlacklistRule clone() {
    return BlacklistRule(
      student1Id: student1Id,
      student1Name: student1Name,
      student2Id: student2Id,
      student2Name: student2Name,
      type: type,
      note: note,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'student1Id': student1Id,
      'student1Name': student1Name,
      'student2Id': student2Id,
      'student2Name': student2Name,
      'type': type.name,
      'note': note,
    };
  }

  factory BlacklistRule.fromMap(Map<String, dynamic> map) {
    GroupingRuleType parsedType = GroupingRuleType.apart;
    if (map['type'] == 'together') {
      parsedType = GroupingRuleType.together;
    }

    return BlacklistRule(
      student1Id: map['student1Id'] ?? '',
      student1Name: map['student1Name'] ?? '',
      student2Id: map['student2Id'] ?? '',
      student2Name: map['student2Name'] ?? '',
      type: parsedType,
      note: map['note'],
    );
  }
}

/// Gelişmiş İsimlendirme İçin Alias
typedef GroupingRule = BlacklistRule;

/// Firestore'a kaydedilecek Grup Çalışması Paketi
class GroupingPlanModel {
  final String? id;
  final String institutionId;
  final String classId;
  final String className;
  final String title;
  final GroupingMode mode;
  final int groupCount;
  final int totalStudents;
  final DateTime createdAt;
  final List<StudentGroup> groups;
  final List<BlacklistRule> blacklistRules;
  final List<String> spreadStudentIds; // Haşarı / Enerjik ayrık dağıtılan öğrenciler
  final String? notes;

  GroupingPlanModel({
    this.id,
    required this.institutionId,
    required this.classId,
    required this.className,
    required this.title,
    required this.mode,
    required this.groupCount,
    required this.totalStudents,
    required this.createdAt,
    required this.groups,
    required this.blacklistRules,
    this.spreadStudentIds = const [],
    this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'classId': classId,
      'className': className,
      'title': title,
      'mode': mode.name,
      'groupCount': groupCount,
      'totalStudents': totalStudents,
      'createdAt': createdAt.toIso8601String(),
      'groups': groups.map((g) => g.toMap()).toList(),
      'blacklistRules': blacklistRules.map((r) => r.toMap()).toList(),
      'spreadStudentIds': spreadStudentIds,
      'notes': notes,
    };
  }

  factory GroupingPlanModel.fromMap(Map<String, dynamic> map, String docId) {
    GroupingMode parsedMode = GroupingMode.balanced;
    try {
      parsedMode = GroupingMode.values.byName(map['mode'] ?? 'balanced');
    } catch (_) {}

    DateTime parsedDate = DateTime.now();
    if (map['createdAt'] != null) {
      try {
        parsedDate = DateTime.parse(map['createdAt']);
      } catch (_) {}
    }

    final rawGroups = (map['groups'] as List?) ?? [];
    final rawRules = (map['blacklistRules'] as List?) ?? [];
    final rawSpread = (map['spreadStudentIds'] as List?)?.map((e) => e.toString()).toList() ?? [];

    return GroupingPlanModel(
      id: docId,
      institutionId: map['institutionId'] ?? '',
      classId: map['classId'] ?? '',
      className: map['className'] ?? '',
      title: map['title'] ?? 'Grup Çalışması',
      mode: parsedMode,
      groupCount: (map['groupCount'] as num?)?.toInt() ?? rawGroups.length,
      totalStudents: (map['totalStudents'] as num?)?.toInt() ?? 0,
      createdAt: parsedDate,
      groups: rawGroups.map((g) => StudentGroup.fromMap(Map<String, dynamic>.from(g))).toList(),
      blacklistRules: rawRules.map((r) => BlacklistRule.fromMap(Map<String, dynamic>.from(r))).toList(),
      spreadStudentIds: rawSpread,
      notes: map['notes'],
    );
  }
}
