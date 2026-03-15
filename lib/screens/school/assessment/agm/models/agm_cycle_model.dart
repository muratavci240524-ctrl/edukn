import 'package:cloud_firestore/cloud_firestore.dart';

enum AgmCycleStatus { draft, locked, published }

class AgmCycle {
  final String id;
  final String institutionId;
  final String schoolTypeId;
  final String? title;
  final String referansDenemeSinavId;
  final String referansDenemeSinavAdi;
  final List<String> referansDenemeSinavIds;
  final List<String> referansDenemeSinavAdlari;
  final DateTime baslangicTarihi;
  final DateTime bitisTarihi;
  final AgmCycleStatus status;
  final DateTime olusturulmaZamani;
  final String olusturanKullaniciId;

  // Ön tanımlama ayarları
  final int? haftalikMaksimumSaat; // soft constraint
  final int? minimumDersSayisi; // soft constraint

  // Taslak istatistikleri (Persistence için)
  final List<String> unassignedStudentIds;
  final List<String> absentStudentIds;
  final List<String> underAssignedStudentIds;

  /// ogrenciId -> List<Neden Mesajları>
  final Map<String, List<String>> unassignedReasons;

  AgmCycle({
    required this.id,
    required this.institutionId,
    required this.schoolTypeId,
    this.title,
    required this.referansDenemeSinavId,
    required this.referansDenemeSinavAdi,
    this.referansDenemeSinavIds = const [],
    this.referansDenemeSinavAdlari = const [],
    required this.baslangicTarihi,
    required this.bitisTarihi,
    this.status = AgmCycleStatus.draft,
    required this.olusturulmaZamani,
    required this.olusturanKullaniciId,
    this.haftalikMaksimumSaat,
    this.minimumDersSayisi,
    this.unassignedStudentIds = const [],
    this.absentStudentIds = const [],
    this.underAssignedStudentIds = const [],
    this.unassignedReasons = const {},
  });

  String get statusLabel {
    switch (status) {
      case AgmCycleStatus.draft:
        return 'Taslak';
      case AgmCycleStatus.locked:
        return 'Kilitli';
      case AgmCycleStatus.published:
        return 'Yayında';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'schoolTypeId': schoolTypeId,
      'title': title,
      'referansDenemeSinavId': referansDenemeSinavId,
      'referansDenemeSinavAdi': referansDenemeSinavAdi,
      'referansDenemeSinavIds': referansDenemeSinavIds,
      'referansDenemeSinavAdlari': referansDenemeSinavAdlari,
      'baslangicTarihi': Timestamp.fromDate(baslangicTarihi),
      'bitisTarihi': Timestamp.fromDate(bitisTarihi),
      'status': status.name,
      'olusturulmaZamani': Timestamp.fromDate(olusturulmaZamani),
      'olusturanKullaniciId': olusturanKullaniciId,
      'haftalikMaksimumSaat': haftalikMaksimumSaat,
      'minimumDersSayisi': minimumDersSayisi,
      'unassignedStudentIds': unassignedStudentIds,
      'absentStudentIds': absentStudentIds,
      'underAssignedStudentIds': underAssignedStudentIds,
      'unassignedReasons': unassignedReasons,
    };
  }

  factory AgmCycle.fromMap(Map<String, dynamic> map, String id) {
    return AgmCycle(
      id: id,
      institutionId: map['institutionId'] ?? '',
      schoolTypeId: map['schoolTypeId'] ?? '',
      title: map['title'],
      referansDenemeSinavId: map['referansDenemeSinavId'] ?? '',
      referansDenemeSinavAdi: map['referansDenemeSinavAdi'] ?? '',
      referansDenemeSinavIds: List<String>.from(
        map['referansDenemeSinavIds'] ?? [],
      ),
      referansDenemeSinavAdlari: List<String>.from(
        map['referansDenemeSinavAdlari'] ?? [],
      ),
      baslangicTarihi:
          (map['baslangicTarihi'] as Timestamp?)?.toDate() ?? DateTime.now(),
      bitisTarihi:
          (map['bitisTarihi'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: AgmCycleStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => AgmCycleStatus.draft,
      ),
      olusturulmaZamani:
          (map['olusturulmaZamani'] as Timestamp?)?.toDate() ?? DateTime.now(),
      olusturanKullaniciId: map['olusturanKullaniciId'] ?? '',
      haftalikMaksimumSaat: map['haftalikMaksimumSaat'],
      minimumDersSayisi: map['minimumDersSayisi'],
      unassignedStudentIds: List<String>.from(
        map['unassignedStudentIds'] ?? [],
      ),
      absentStudentIds: List<String>.from(map['absentStudentIds'] ?? []),
      underAssignedStudentIds: List<String>.from(
        map['underAssignedStudentIds'] ?? [],
      ),
      unassignedReasons:
          (map['unassignedReasons'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, List<String>.from(v)),
          ) ??
          {},
    );
  }

  AgmCycle copyWith({
    String? id,
    String? institutionId,
    String? schoolTypeId,
    String? title,
    String? referansDenemeSinavId,
    String? referansDenemeSinavAdi,
    List<String>? referansDenemeSinavIds,
    List<String>? referansDenemeSinavAdlari,
    DateTime? baslangicTarihi,
    DateTime? bitisTarihi,
    AgmCycleStatus? status,
    DateTime? olusturulmaZamani,
    String? olusturanKullaniciId,
    int? haftalikMaksimumSaat,
    int? minimumDersSayisi,
    List<String>? unassignedStudentIds,
    List<String>? absentStudentIds,
    List<String>? underAssignedStudentIds,
    Map<String, List<String>>? unassignedReasons,
  }) {
    return AgmCycle(
      id: id ?? this.id,
      institutionId: institutionId ?? this.institutionId,
      schoolTypeId: schoolTypeId ?? this.schoolTypeId,
      title: title ?? this.title,
      referansDenemeSinavId:
          referansDenemeSinavId ?? this.referansDenemeSinavId,
      referansDenemeSinavAdi:
          referansDenemeSinavAdi ?? this.referansDenemeSinavAdi,
      referansDenemeSinavIds:
          referansDenemeSinavIds ?? this.referansDenemeSinavIds,
      referansDenemeSinavAdlari:
          referansDenemeSinavAdlari ?? this.referansDenemeSinavAdlari,
      baslangicTarihi: baslangicTarihi ?? this.baslangicTarihi,
      bitisTarihi: bitisTarihi ?? this.bitisTarihi,
      status: status ?? this.status,
      olusturulmaZamani: olusturulmaZamani ?? this.olusturulmaZamani,
      olusturanKullaniciId: olusturanKullaniciId ?? this.olusturanKullaniciId,
      haftalikMaksimumSaat: haftalikMaksimumSaat ?? this.haftalikMaksimumSaat,
      minimumDersSayisi: minimumDersSayisi ?? this.minimumDersSayisi,
      unassignedStudentIds: unassignedStudentIds ?? this.unassignedStudentIds,
      absentStudentIds: absentStudentIds ?? this.absentStudentIds,
      underAssignedStudentIds:
          underAssignedStudentIds ?? this.underAssignedStudentIds,
      unassignedReasons: unassignedReasons ?? this.unassignedReasons,
    );
  }
}
