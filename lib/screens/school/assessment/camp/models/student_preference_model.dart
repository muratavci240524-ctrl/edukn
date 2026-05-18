/// V2 – Öğrenci Tercih Tablosu (Versiyon 1'de PASIF kalır)
///
/// Gelecekte kullanılacak formül:
///   Final Skor = (ihtiyaç_skoru × 0.8) + (tercih_katsayısı × 0.2)
///
/// V1'de bu tablo sadece oluşturulur, algoritma tarafından kullanılmaz.
class StudentPreference {
  final String id;
  final String institutionId;
  final String ogrenciId;
  final String dersId;
  final String dersAdi;
  final int oncelikSirasi; // 1 = en öncelikli
  final List<String> musaitSaatDilimleri; // slotId listesi

  // V2'de kullanılacak
  final double tercihKatsayisi; // 0.0 – 1.0 (V1: pasif)

  StudentPreference({
    required this.id,
    required this.institutionId,
    required this.ogrenciId,
    required this.dersId,
    required this.dersAdi,
    required this.oncelikSirasi,
    this.musaitSaatDilimleri = const [],
    this.tercihKatsayisi = 0.0, // V1: pasif
  });

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'ogrenciId': ogrenciId,
      'dersId': dersId,
      'dersAdi': dersAdi,
      'oncelikSirasi': oncelikSirasi,
      'musaitSaatDilimleri': musaitSaatDilimleri,
      'tercihKatsayisi': tercihKatsayisi,
    };
  }

  factory StudentPreference.fromMap(Map<String, dynamic> map, String id) {
    return StudentPreference(
      id: id,
      institutionId: map['institutionId'] ?? '',
      ogrenciId: map['ogrenciId'] ?? '',
      dersId: map['dersId'] ?? '',
      dersAdi: map['dersAdi'] ?? '',
      oncelikSirasi: map['oncelikSirasi'] ?? 1,
      musaitSaatDilimleri: (map['musaitSaatDilimleri'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      tercihKatsayisi: (map['tercihKatsayisi'] ?? 0.0).toDouble(),
    );
  }
}
