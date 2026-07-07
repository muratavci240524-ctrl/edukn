import 'package:cloud_firestore/cloud_firestore.dart';

class CampTimeSlot {
  final String id;
  final String institutionId;
  final String gun;
  final String baslangicSaat;
  final String bitisSaat;
  final String ad; // Renamed from label to match AGM logic
  final DateTime? tarih;
  final bool isActive;
  final List<CampSlotTeacherEntry> ogretmenGirisler;

  CampTimeSlot({
    required this.id,
    required this.institutionId,
    required this.gun,
    required this.baslangicSaat,
    required this.bitisSaat,
    this.ad = '',
    this.tarih,
    this.isActive = true,
    this.ogretmenGirisler = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'gun': gun,
      'baslangicSaat': baslangicSaat,
      'bitisSaat': bitisSaat,
      'ad': ad,
      'tarih': tarih != null ? Timestamp.fromDate(tarih!) : null,
      'isActive': isActive,
      'ogretmenGirisler': ogretmenGirisler.map((e) => e.toMap()).toList(),
    };
  }

  factory CampTimeSlot.fromMap(Map<String, dynamic> map, String id) {
    return CampTimeSlot(
      id: id,
      institutionId: map['institutionId'] ?? '',
      gun: map['gun'] ?? '',
      baslangicSaat: map['baslangicSaat'] ?? '',
      bitisSaat: map['bitisSaat'] ?? '',
      ad: map['ad'] ?? map['label'] ?? '',
      tarih: map['tarih'] != null ? (map['tarih'] as Timestamp).toDate() : null,
      isActive: map['isActive'] ?? true,
      ogretmenGirisler: (map['ogretmenGirisler'] as List<dynamic>? ?? [])
          .map((e) => CampSlotTeacherEntry.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }

  CampTimeSlot copyWith({
    String? id,
    String? institutionId,
    String? gun,
    String? baslangicSaat,
    String? bitisSaat,
    String? ad,
    DateTime? tarih,
    bool? isActive,
    List<CampSlotTeacherEntry>? ogretmenGirisler,
  }) {
    return CampTimeSlot(
      id: id ?? this.id,
      institutionId: institutionId ?? this.institutionId,
      gun: gun ?? this.gun,
      baslangicSaat: baslangicSaat ?? this.baslangicSaat,
      bitisSaat: bitisSaat ?? this.bitisSaat,
      ad: ad ?? this.ad,
      tarih: tarih ?? this.tarih,
      isActive: isActive ?? this.isActive,
      ogretmenGirisler: ogretmenGirisler ?? this.ogretmenGirisler,
    );
  }
}

class CampSlotTeacherEntry {
  final String ogretmenId;
  final String ogretmenAdi;
  final String dersId;
  final String dersAdi;
  String? derslikId;
  String? derslikAdi;
  int kapasite;

  CampSlotTeacherEntry({
    required this.ogretmenId,
    required this.ogretmenAdi,
    required this.dersId,
    required this.dersAdi,
    this.derslikId,
    this.derslikAdi,
    this.kapasite = 24,
  });

  Map<String, dynamic> toMap() {
    return {
      'ogretmenId': ogretmenId,
      'ogretmenAdi': ogretmenAdi,
      'dersId': dersId,
      'dersAdi': dersAdi,
      'derslikId': derslikId,
      'derslikAdi': derslikAdi,
      'kapasite': kapasite,
    };
  }

  factory CampSlotTeacherEntry.fromMap(Map<String, dynamic> map) {
    return CampSlotTeacherEntry(
      ogretmenId: map['ogretmenId'] ?? '',
      ogretmenAdi: map['ogretmenAdi'] ?? '',
      dersId: map['dersId'] ?? '',
      dersAdi: map['dersAdi'] ?? '',
      derslikId: map['derslikId'],
      derslikAdi: map['derslikAdi'],
      kapasite: map['kapasite'] ?? 24,
    );
  }
}
