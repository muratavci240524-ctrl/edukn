import 'package:cloud_firestore/cloud_firestore.dart';

enum AgmAssignmentType { auto, manual }

/// Bir öğrencinin bir AGM grubuna atanması
class AgmAssignment {
  final String id;
  final String cycleId;
  final String groupId;
  final String institutionId;

  // Öğrenci bilgileri
  final String ogrenciId;
  final String ogrenciAdi;
  final String subeId;
  final String subeAdi;

  // Algoritma skoru
  final double ihtiyacSkoru; // 0.0 – 1.0

  // Atama tipi
  final AgmAssignmentType atamaTipi;
  final String? groupName; // Group context for display
  final DateTime olusturulmaZamani;
  final bool isAbsent;

  AgmAssignment({
    required this.id,
    required this.cycleId,
    required this.groupId,
    required this.institutionId,
    required this.ogrenciId,
    required this.ogrenciAdi,
    required this.subeId,
    required this.subeAdi,
    required this.ihtiyacSkoru,
    this.atamaTipi = AgmAssignmentType.auto,
    this.groupName,
    required this.olusturulmaZamani,
    this.isAbsent = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'cycleId': cycleId,
      'groupId': groupId,
      'institutionId': institutionId,
      'ogrenciId': ogrenciId,
      'ogrenciAdi': ogrenciAdi,
      'subeId': subeId,
      'subeAdi': subeAdi,
      'ihtiyacSkoru': ihtiyacSkoru,
      'atamaTipi': atamaTipi.name,
      'groupName': groupName,
      'olusturulmaZamani': Timestamp.fromDate(olusturulmaZamani),
      'isAbsent': isAbsent,
    };
  }

  factory AgmAssignment.fromMap(Map<String, dynamic> map, String id) {
    return AgmAssignment(
      id: id,
      cycleId: map['cycleId'] ?? '',
      groupId: map['groupId'] ?? '',
      institutionId: map['institutionId'] ?? '',
      ogrenciId: map['ogrenciId'] ?? '',
      ogrenciAdi: map['ogrenciAdi'] ?? '',
      subeId: map['subeId'] ?? '',
      subeAdi: map['subeAdi'] ?? '',
      ihtiyacSkoru: (map['ihtiyacSkoru'] ?? 0.0).toDouble(),
      atamaTipi: AgmAssignmentType.values.firstWhere(
        (e) => e.name == map['atamaTipi'],
        orElse: () => AgmAssignmentType.auto,
      ),
      groupName: map['groupName'],
      olusturulmaZamani:
          (map['olusturulmaZamani'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isAbsent: map['isAbsent'] ?? false,
    );
  }
}
