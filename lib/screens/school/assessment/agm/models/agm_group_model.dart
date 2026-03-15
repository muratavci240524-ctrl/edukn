/// AGM Grubu = (cycle_id + ders_id + saat_dilimi + teacher_id)
///
/// HARD RULES:
/// - Öğrenci aynı slotta sadece 1 grupta yer alabilir
/// - Öğretmen aynı slotta sadece 1 grupta yer alabilir
class AgmGroup {
  final String id;
  final String cycleId;
  final String institutionId;

  // Tanım bilgileri
  final String dersId;
  final String dersAdi;
  final String saatDilimiId;
  final String saatDilimiAdi; // "Pazartesi 14:00-15:00"
  final String gun;
  final String baslangicSaat;
  final String bitisSaat;

  // Öğretmen
  final String ogretmenId;
  final String ogretmenAdi;

  // Derslik
  final String? derslikId;
  final String? derslikAdi;

  // Kapasite (soft constraint)
  final int kapasite;
  final int mevcutOgrenciSayisi;

  // Outcomes
  final List<String> kazanimlar;

  AgmGroup({
    required this.id,
    required this.cycleId,
    required this.institutionId,
    required this.dersId,
    required this.dersAdi,
    required this.saatDilimiId,
    required this.saatDilimiAdi,
    required this.gun,
    required this.baslangicSaat,
    required this.bitisSaat,
    required this.ogretmenId,
    required this.ogretmenAdi,
    this.derslikId,
    this.derslikAdi,
    this.kapasite = 20,
    this.mevcutOgrenciSayisi = 0,
    this.kazanimlar = const [],
  });

  double get dolulukOrani =>
      kapasite > 0 ? mevcutOgrenciSayisi / kapasite : 0.0;

  bool get kapasite_dolu => mevcutOgrenciSayisi >= kapasite;

  Map<String, dynamic> toMap() {
    return {
      'cycleId': cycleId,
      'institutionId': institutionId,
      'dersId': dersId,
      'dersAdi': dersAdi,
      'saatDilimiId': saatDilimiId,
      'saatDilimiAdi': saatDilimiAdi,
      'gun': gun,
      'baslangicSaat': baslangicSaat,
      'bitisSaat': bitisSaat,
      'ogretmenId': ogretmenId,
      'ogretmenAdi': ogretmenAdi,
      'derslikId': derslikId,
      'derslikAdi': derslikAdi,
      'kapasite': kapasite,
      'mevcutOgrenciSayisi': mevcutOgrenciSayisi,
      'kazanimlar': kazanimlar,
    };
  }

  factory AgmGroup.fromMap(Map<String, dynamic> map, String id) {
    return AgmGroup(
      id: id,
      cycleId: map['cycleId'] ?? '',
      institutionId: map['institutionId'] ?? '',
      dersId: map['dersId'] ?? '',
      dersAdi: map['dersAdi'] ?? '',
      saatDilimiId: map['saatDilimiId'] ?? '',
      saatDilimiAdi: map['saatDilimiAdi'] ?? '',
      gun: map['gun'] ?? '',
      baslangicSaat: map['baslangicSaat'] ?? '',
      bitisSaat: map['bitisSaat'] ?? '',
      ogretmenId: map['ogretmenId'] ?? '',
      ogretmenAdi: map['ogretmenAdi'] ?? '',
      derslikId: map['derslikId'],
      derslikAdi: map['derslikAdi'],
      kapasite: map['kapasite'] ?? 20,
      mevcutOgrenciSayisi: map['mevcutOgrenciSayisi'] ?? 0,
      kazanimlar: (map['kazanimlar'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  AgmGroup copyWith({
    String? id,
    String? cycleId,
    String? institutionId,
    String? dersId,
    String? dersAdi,
    String? saatDilimiId,
    String? saatDilimiAdi,
    String? gun,
    String? baslangicSaat,
    String? bitisSaat,
    String? ogretmenId,
    String? ogretmenAdi,
    String? derslikId,
    String? derslikAdi,
    int? kapasite,
    int? mevcutOgrenciSayisi,
    List<String>? kazanimlar,
  }) {
    return AgmGroup(
      id: id ?? this.id,
      cycleId: cycleId ?? this.cycleId,
      institutionId: institutionId ?? this.institutionId,
      dersId: dersId ?? this.dersId,
      dersAdi: dersAdi ?? this.dersAdi,
      saatDilimiId: saatDilimiId ?? this.saatDilimiId,
      saatDilimiAdi: saatDilimiAdi ?? this.saatDilimiAdi,
      gun: gun ?? this.gun,
      baslangicSaat: baslangicSaat ?? this.baslangicSaat,
      bitisSaat: bitisSaat ?? this.bitisSaat,
      ogretmenId: ogretmenId ?? this.ogretmenId,
      ogretmenAdi: ogretmenAdi ?? this.ogretmenAdi,
      derslikId: derslikId ?? this.derslikId,
      derslikAdi: derslikAdi ?? this.derslikAdi,
      kapasite: kapasite ?? this.kapasite,
      mevcutOgrenciSayisi: mevcutOgrenciSayisi ?? this.mevcutOgrenciSayisi,
      kazanimlar: kazanimlar ?? this.kazanimlar,
    );
  }
}
