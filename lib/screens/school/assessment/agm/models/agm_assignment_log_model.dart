import 'package:cloud_firestore/cloud_firestore.dart';

/// Manuel override veya otomatik atama değişikliklerinin log kaydı.
/// Her değişiklik burada saklanır – audit trail.
class AgmAssignmentLog {
  final String id;
  final String cycleId;
  final String institutionId;
  final String ogrenciId;
  final String ogrenciAdi;

  // Önceki ve yeni grup bilgisi (null = yeni ekleme veya silme)
  final String? eskiGrupId;
  final String? eskiGrupAdi;
  final String? yeniGrupId;
  final String? yeniGrupAdi;

  // Kim yaptı
  final String yapanKullaniciId;
  final String yapanKullaniciAdi;

  // Kapasite aşımı override mı?
  final bool isOverride;
  final String? overrideNedeni;

  final DateTime tarih;

  AgmAssignmentLog({
    required this.id,
    required this.cycleId,
    required this.institutionId,
    required this.ogrenciId,
    required this.ogrenciAdi,
    this.eskiGrupId,
    this.eskiGrupAdi,
    this.yeniGrupId,
    this.yeniGrupAdi,
    required this.yapanKullaniciId,
    required this.yapanKullaniciAdi,
    this.isOverride = false,
    this.overrideNedeni,
    required this.tarih,
  });

  String get aciklama {
    if (eskiGrupId == null) return 'Gruba eklendi: $yeniGrupAdi';
    if (yeniGrupId == null) return 'Gruptan çıkarıldı: $eskiGrupAdi';
    return '$eskiGrupAdi → $yeniGrupAdi';
  }

  Map<String, dynamic> toMap() {
    return {
      'cycleId': cycleId,
      'institutionId': institutionId,
      'ogrenciId': ogrenciId,
      'ogrenciAdi': ogrenciAdi,
      'eskiGrupId': eskiGrupId,
      'eskiGrupAdi': eskiGrupAdi,
      'yeniGrupId': yeniGrupId,
      'yeniGrupAdi': yeniGrupAdi,
      'yapanKullaniciId': yapanKullaniciId,
      'yapanKullaniciAdi': yapanKullaniciAdi,
      'isOverride': isOverride,
      'overrideNedeni': overrideNedeni,
      'tarih': Timestamp.fromDate(tarih),
    };
  }

  factory AgmAssignmentLog.fromMap(Map<String, dynamic> map, String id) {
    return AgmAssignmentLog(
      id: id,
      cycleId: map['cycleId'] ?? '',
      institutionId: map['institutionId'] ?? '',
      ogrenciId: map['ogrenciId'] ?? '',
      ogrenciAdi: map['ogrenciAdi'] ?? '',
      eskiGrupId: map['eskiGrupId'],
      eskiGrupAdi: map['eskiGrupAdi'],
      yeniGrupId: map['yeniGrupId'],
      yeniGrupAdi: map['yeniGrupAdi'],
      yapanKullaniciId: map['yapanKullaniciId'] ?? '',
      yapanKullaniciAdi: map['yapanKullaniciAdi'] ?? '',
      isOverride: map['isOverride'] ?? false,
      overrideNedeni: map['overrideNedeni'],
      tarih: (map['tarih'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
