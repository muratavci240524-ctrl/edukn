/// Admin tarafından tanımlanan haftalık saat dilimleri.
/// Her saat dilimine birden fazla (ders, öğretmen) çifti atanabilir.
class AgmTimeSlot {
  final String id;
  final String institutionId;
  final String ad; // "Pazartesi 14:00-15:00"
  final String gun;
  final String baslangicSaat; // "14:00"
  final String bitisSaat; // "15:00"
  final List<AgmSlotTeacherEntry> ogretmenGirisler;
  final bool isActive;

  AgmTimeSlot({
    required this.id,
    required this.institutionId,
    required this.ad,
    required this.gun,
    required this.baslangicSaat,
    required this.bitisSaat,
    this.ogretmenGirisler = const [],
    this.isActive = true,
  });

  /// Belirli bir ders için bu slottaki öğretmenleri getirir
  List<AgmSlotTeacherEntry> ogretmenlerByDers(String dersId) {
    return ogretmenGirisler.where((e) => e.dersId == dersId).toList();
  }

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'ad': ad,
      'gun': gun,
      'baslangicSaat': baslangicSaat,
      'bitisSaat': bitisSaat,
      'ogretmenGirisler': ogretmenGirisler.map((e) => e.toMap()).toList(),
      'isActive': isActive,
    };
  }

  factory AgmTimeSlot.fromMap(Map<String, dynamic> map, String id) {
    return AgmTimeSlot(
      id: id,
      institutionId: map['institutionId'] ?? '',
      ad: map['ad'] ?? '',
      gun: map['gun'] ?? '',
      baslangicSaat: map['baslangicSaat'] ?? '',
      bitisSaat: map['bitisSaat'] ?? '',
      ogretmenGirisler: (map['ogretmenGirisler'] as List<dynamic>? ?? [])
          .map((e) => AgmSlotTeacherEntry.fromMap(e as Map<String, dynamic>))
          .toList(),
      isActive: map['isActive'] ?? true,
    );
  }
}

/// Bir saat dilimindeki (ders, öğretmen) ikilisi
class AgmSlotTeacherEntry {
  final String dersId;
  final String dersAdi;
  final String ogretmenId;
  final String ogretmenAdi;
  final String? derslikId;
  final String? derslikAdi;
  final int kapasite; // Bu öğretmen için grup kapasitesi

  AgmSlotTeacherEntry({
    required this.dersId,
    required this.dersAdi,
    required this.ogretmenId,
    required this.ogretmenAdi,
    this.derslikId,
    this.derslikAdi,
    this.kapasite = 20,
  });

  Map<String, dynamic> toMap() {
    return {
      'dersId': dersId,
      'dersAdi': dersAdi,
      'ogretmenId': ogretmenId,
      'ogretmenAdi': ogretmenAdi,
      'derslikId': derslikId,
      'derslikAdi': derslikAdi,
      'kapasite': kapasite,
    };
  }

  factory AgmSlotTeacherEntry.fromMap(Map<String, dynamic> map) {
    return AgmSlotTeacherEntry(
      dersId: map['dersId'] ?? '',
      dersAdi: map['dersAdi'] ?? '',
      ogretmenId: map['ogretmenId'] ?? '',
      ogretmenAdi: map['ogretmenAdi'] ?? '',
      derslikId: map['derslikId'],
      derslikAdi: map['derslikAdi'],
      kapasite: map['kapasite'] ?? 20,
    );
  }

  @override
  String toString() =>
      '$dersAdi – $ogretmenAdi${derslikAdi != null ? ' ($derslikAdi)' : ''}';
}
