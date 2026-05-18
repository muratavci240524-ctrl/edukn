enum CampAssignmentType { auto, manual }

class CampAssignment {
  final String id;
  final String cycleId;
  final String groupId;
  final String groupName; // Mirroring AGM naming
  final String ogrenciId;
  final String ogrenciAdi;
  final String? sube;
  final String? subeId;
  final CampAssignmentType atamaTipi;
  final double ihtiyacSkoru; // 0.0 - 1.0 (1.0 means most needed)
  final double basariOrani; // 0.0 - 1.0
  final bool isAbsent;

  CampAssignment({
    required this.id,
    required this.cycleId,
    required this.groupId,
    required this.groupName,
    required this.ogrenciId,
    required this.ogrenciAdi,
    this.sube,
    this.subeId,
    this.atamaTipi = CampAssignmentType.auto,
    this.ihtiyacSkoru = 0.0,
    this.basariOrani = 0.0,
    this.isAbsent = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'cycleId': cycleId,
      'groupId': groupId,
      'groupName': groupName,
      'ogrenciId': ogrenciId,
      'ogrenciAdi': ogrenciAdi,
      'sube': sube,
      'subeId': subeId,
      'atamaTipi': atamaTipi.name,
      'ihtiyacSkoru': ihtiyacSkoru,
      'basariOrani': basariOrani,
      'isAbsent': isAbsent,
    };
  }

  factory CampAssignment.fromMap(Map<String, dynamic> map, String id) {
    return CampAssignment(
      id: id,
      cycleId: map['cycleId'] ?? '',
      groupId: map['groupId'] ?? '',
      groupName: map['groupName'] ?? map['groupAdi'] ?? '',
      ogrenciId: map['ogrenciId'] ?? '',
      ogrenciAdi: map['ogrenciAdi'] ?? '',
      sube: map['sube'],
      subeId: map['subeId'],
      atamaTipi: CampAssignmentType.values.firstWhere(
        (e) => e.name == map['atamaTipi'],
        orElse: () => CampAssignmentType.auto,
      ),
      ihtiyacSkoru: (map['ihtiyacSkoru'] ?? 0.0).toDouble(),
      basariOrani: (map['basariOrani'] ?? 0.0).toDouble(),
      isAbsent: map['isAbsent'] ?? false,
    );
  }
}
