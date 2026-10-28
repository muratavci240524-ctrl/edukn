import 'package:cloud_firestore/cloud_firestore.dart';

class AgmTimeSlot {
  final String id;
  final String institutionId;
  final String gun;
  final String baslangicSaat;
  final String bitisSaat;
  final String ad;
  final DateTime? tarih;
  final bool isActive;
  final List<AgmSlotTeacherEntry> ogretmenGirisler;

  AgmTimeSlot({
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

  factory AgmTimeSlot.fromMap(Map<String, dynamic> map, String id) {
    return AgmTimeSlot(
      id: id,
      institutionId: map['institutionId'] ?? '',
      gun: map['gun'] ?? '',
      baslangicSaat: map['baslangicSaat'] ?? '',
      bitisSaat: map['bitisSaat'] ?? '',
      ad: map['ad'] ?? map['label'] ?? '',
      tarih: map['tarih'] != null ? (map['tarih'] as Timestamp).toDate() : null,
      isActive: map['isActive'] ?? true,
      ogretmenGirisler: (map['ogretmenGirisler'] as List<dynamic>? ?? [])
          .map((e) => AgmSlotTeacherEntry.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }

  AgmTimeSlot copyWith({
    String? id,
    String? institutionId,
    String? gun,
    String? baslangicSaat,
    String? bitisSaat,
    String? ad,
    DateTime? tarih,
    bool? isActive,
    List<AgmSlotTeacherEntry>? ogretmenGirisler,
  }) {
    return AgmTimeSlot(
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

class AgmSlotTeacherEntry {
  final String ogretmenId;
  final String ogretmenAdi;
  final String dersId;
  final String dersAdi;
  final String? derslikId;
  final String? derslikAdi;
  final int kapasite;

  AgmSlotTeacherEntry({
    required this.ogretmenId,
    required this.ogretmenAdi,
    required this.dersId,
    required this.dersAdi,
    this.derslikId,
    this.derslikAdi,
    this.kapasite = 24,
  });

  AgmSlotTeacherEntry copyWith({
    String? ogretmenId,
    String? ogretmenAdi,
    String? dersId,
    String? dersAdi,
    String? derslikId,
    String? derslikAdi,
    int? kapasite,
  }) {
    return AgmSlotTeacherEntry(
      ogretmenId: ogretmenId ?? this.ogretmenId,
      ogretmenAdi: ogretmenAdi ?? this.ogretmenAdi,
      dersId: dersId ?? this.dersId,
      dersAdi: dersAdi ?? this.dersAdi,
      derslikId: derslikId ?? this.derslikId,
      derslikAdi: derslikAdi ?? this.derslikAdi,
      kapasite: kapasite ?? this.kapasite,
    );
  }

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

  factory AgmSlotTeacherEntry.fromMap(Map<String, dynamic> map) {
    return AgmSlotTeacherEntry(
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
