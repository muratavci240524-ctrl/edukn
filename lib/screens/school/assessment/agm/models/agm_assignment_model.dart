enum AgmAssignmentType { auto, manual }

class AgmAssignment {
  final String id;
  final String cycleId;
  final String institutionId;
  final String groupId;
  final String groupName;
  final String ogrenciId;
  final String ogrenciAdi;
  final String? sube;
  final String? subeId;
  final AgmAssignmentType atamaTipi;
  final double ihtiyacSkoru; // 0.0 - 1.0 (1.0 means most needed)
  final double basariOrani; // 0.0 - 1.0
  final bool isAbsent;

  AgmAssignment({
    required this.id,
    required this.cycleId,
    this.institutionId = '',
    required this.groupId,
    required this.groupName,
    required this.ogrenciId,
    required this.ogrenciAdi,
    this.sube,
    this.subeId,
    this.atamaTipi = AgmAssignmentType.auto,
    this.ihtiyacSkoru = 0.0,
    this.basariOrani = 0.0,
    this.isAbsent = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'cycleId': cycleId,
      'institutionId': institutionId,
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

  factory AgmAssignment.fromMap(Map<String, dynamic> map, String id) {
    return AgmAssignment(
      id: id,
      cycleId: map['cycleId'] ?? '',
      institutionId: map['institutionId'] ?? '',
      groupId: map['groupId'] ?? '',
      groupName: map['groupName'] ?? map['groupAdi'] ?? '',
      ogrenciId: map['ogrenciId'] ?? '',
      ogrenciAdi: map['ogrenciAdi'] ?? '',
      sube: map['sube'] ?? map['subeAdi'],
      subeId: map['subeId'],
      atamaTipi: AgmAssignmentType.values.firstWhere(
        (e) => e.name == map['atamaTipi'],
        orElse: () => AgmAssignmentType.auto,
      ),
      ihtiyacSkoru: (map['ihtiyacSkoru'] ?? 0.0).toDouble(),
      basariOrani: (map['basariOrani'] ?? 0.0).toDouble(),
      isAbsent: map['isAbsent'] ?? false,
    );
  }

  AgmAssignment copyWith({
    String? id,
    String? cycleId,
    String? institutionId,
    String? groupId,
    String? groupName,
    String? ogrenciId,
    String? ogrenciAdi,
    String? sube,
    String? subeId,
    AgmAssignmentType? atamaTipi,
    double? ihtiyacSkoru,
    double? basariOrani,
    bool? isAbsent,
  }) {
    return AgmAssignment(
      id: id ?? this.id,
      cycleId: cycleId ?? this.cycleId,
      institutionId: institutionId ?? this.institutionId,
      groupId: groupId ?? this.groupId,
      groupName: groupName ?? this.groupName,
      ogrenciId: ogrenciId ?? this.ogrenciId,
      ogrenciAdi: ogrenciAdi ?? this.ogrenciAdi,
      sube: sube ?? this.sube,
      subeId: subeId ?? this.subeId,
      atamaTipi: atamaTipi ?? this.atamaTipi,
      ihtiyacSkoru: ihtiyacSkoru ?? this.ihtiyacSkoru,
      basariOrani: basariOrani ?? this.basariOrani,
      isAbsent: isAbsent ?? this.isAbsent,
    );
  }
}
