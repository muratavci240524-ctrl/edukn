import '../models/agm_assignment_model.dart';
import '../models/agm_group_model.dart';

/// Bir öğrencinin ders bazlı ihtiyaç profili
class StudentNeedProfile {
  final String ogrenciId;
  final String ogrenciAdi;
  final String subeId;
  final String subeAdi;

  /// dersId -> ihtiyaçlar (kazanımlar), azalan sıralı
  final Map<String, double> dersIhtiyaclari;

  /// dersId -> Set<kazanimAdi> (öğrencinin bu derste zayıf olduğu kazanımlar)
  final Map<String, Set<String>> kazanimIhtiyaclari;

  /// dersId -> başarı oranı (0.0 - 1.0)
  final Map<String, double> dersBasariOranlari;

  double get toplamIhtiyac => dersIhtiyaclari.values.fold(0.0, (a, b) => a + b);

  StudentNeedProfile({
    required this.ogrenciId,
    required this.ogrenciAdi,
    required this.subeId,
    required this.subeAdi,
    required this.dersIhtiyaclari,
    this.kazanimIhtiyaclari = const {},
    this.dersBasariOranlari = const {},
  });
}

/// Yerleştirme sonucu
class AgmDraftResult {
  final List<AgmAssignment> atamalar;
  final List<AgmGroup> gruplar; // Updated groups
  final List<String> yerlesmeyenOgrenciIds; // Hard constraint sebebiyle
  final List<String>
  eksikAtananOgrenciIds; // Minimum ders sayısına ulaşamayanlar
  final List<AgmSoftWarning> softUyarilar;
  final Map<String, List<String>> yerlesmemeNedenleri;

  AgmDraftResult({
    required this.atamalar,
    required this.gruplar,
    required this.yerlesmeyenOgrenciIds,
    this.eksikAtananOgrenciIds = const [],
    required this.softUyarilar,
    this.yerlesmemeNedenleri = const {},
  });
}

class AgmSoftWarning {
  final String tip; // 'kapasite_asimi' | 'max_saat_asimi'
  final String ogrenciId;
  final String? grupAdi;
  final String mesaj;

  AgmSoftWarning({
    required this.tip,
    required this.ogrenciId,
    this.grupAdi,
    required this.mesaj,
  });
}

/// ─────────────────────────────────────────────────────────────────────────────
/// AGM Greedy Optimization Algoritması
///
/// AŞAMA 1 – İHTİYAÇ ANALİZİ
///   Her öğrenci için: ihtiyaçSkoru[ders] = 1 - başarıOranı
///   En düşük başarıdan en yükseğe sıralanır
///
/// AŞAMA 2 – 2 FAZLI DAĞITIM
///   FAZ 1 – Dengeleme: Her öğrenciye farklı derslerden en az 1 etüt
///   FAZ 2 – Derinleştirme: Yüksek ihtiyaçlılara ek atama
///
/// HARD CONSTRAINTS:
///   - Öğrenci aynı slotta yalnızca 1 grupta olabilir
///   - Öğretmen aynı slotta yalnızca 1 grupta olabilir
///
/// SOFT CONSTRAINTS (aşılabilir, uyarı üretir):
///   - Grup kapasitesi
///   - Haftalık maksimum saat
/// ─────────────────────────────────────────────────────────────────────────────
class AgmAssignmentEngine {
  final String cycleId;
  final String institutionId;
  final int? haftalikMaksimumSaat;

  AgmAssignmentEngine({
    required this.cycleId,
    required this.institutionId,
    this.haftalikMaksimumSaat,
  });

  /// Ana giriş noktası
  /// [ogrenciProfillar] – öğrenci listesi + ders ihtiyaç skoru haritası
  /// [gruplar] – admin tarafından ön tanımlanmış gruplar
  Future<AgmDraftResult> generateDraft({
    required List<StudentNeedProfile> ogrenciProfiller,
    required List<AgmGroup> gruplar,
  }) async {
    // ── HARD CONSTRAINT TAKİBİ ────────────────────────────────────────────
    // ogrenciId -> Set<slotId> (dolmuş slotlar)
    final Map<String, Set<String>> ogrenciDoluSlot = {};
    // ogrenciId -> kaç saat atandı
    final Map<String, int> ogrenciSaatSayisi = {};
    // ogrenciId -> Nedenler
    final Map<String, List<String>> yerlesmemeNedenleri = {};

    // groupId -> mevcut öğrenci sayısı (Firestore'dan ayrı, in-memory)
    final Map<String, int> grupMevcut = {
      for (final g in gruplar) g.id: g.mevcutOgrenciSayisi,
    };

    final List<AgmAssignment> atamalar = [];
    final List<String> yerlesmeyenIds = [];
    final List<AgmSoftWarning> uyarilar = [];

    // Group-Outcome Map: groupId -> Map<kazanimAdi, frekans>
    final Map<String, Map<String, int>> grupKazanimFrekanslari = {
      for (final g in gruplar)
        g.id: {
          for (final k in g.kazanimlar) k: 10,
        }, // Mevcutları güçlü frekansla başlat
    };

    // groupId -> bu grubun hedef "başarı seviyesi" (ilk atanan öğrenciye göre belirlenir)
    final Map<String, int> grupBucket = {};

    // ── AŞAMA 1: ÖNCELİKLENDİRME ──────────────────────────────────────────
    // Öğrencileri toplam ihtiyaç skoruna göre azalan sırada sırala
    final siralanmisProfillar = List<StudentNeedProfile>.from(ogrenciProfiller)
      ..sort((a, b) => b.toplamIhtiyac.compareTo(a.toplamIhtiyac));
    for (final profil in siralanmisProfillar) {
      final ogrenciId = profil.ogrenciId;
      ogrenciDoluSlot.putIfAbsent(ogrenciId, () => {});
      ogrenciSaatSayisi.putIfAbsent(ogrenciId, () => 0);
      yerlesmemeNedenleri.putIfAbsent(ogrenciId, () => []);

      // Dersleri ihtiyaç skoruna göre sırala (en yüksek önce)
      final siraliDersler = profil.dersIhtiyaclari.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      for (final dersEntry in siraliDersler) {
        final dersId = dersEntry.key;

        // Haftalık maks saat kontrolü (soft)
        if (haftalikMaksimumSaat != null &&
            ogrenciSaatSayisi[ogrenciId]! >= haftalikMaksimumSaat!) {
          yerlesmemeNedenleri[ogrenciId]!.add(
            '$dersId: Haftalık max ders limitine ($haftalikMaksimumSaat) takıldı.',
          );
          continue;
        }

        // Bu öğrencinin bu dersindeki zayıf kazanımları
        final ogrenciKazanimlar = profil.kazanimIhtiyaclari[dersId] ?? {};
        final ogrenciBasariOrani = profil.dersBasariOranlari[dersId] ?? 0.0;

        final findResult = _findBestEfficientGroupWithReason(
          dersId: dersId,
          ogrenciId: ogrenciId,
          ogrenciKazanimlar: ogrenciKazanimlar,
          ogrenciBasariOrani: profil.dersBasariOranlari[dersId] ?? 0.0,
          ogrenciDoluSlot: ogrenciDoluSlot[ogrenciId]!,
          gruplar: gruplar,
          grupMevcut: grupMevcut,
          grupKazanimFrekanslari: grupKazanimFrekanslari,
          grupBucket: grupBucket,
        );

        final uygunGrup = findResult.group;
        if (uygunGrup != null) {
          atamalar.add(
            AgmAssignment(
              id: '',
              cycleId: cycleId,
              groupId: uygunGrup.id,
              institutionId: institutionId,
              ogrenciId: ogrenciId,
              ogrenciAdi: profil.ogrenciAdi,
              subeId: profil.subeId,
              subeAdi: profil.subeAdi,
              ihtiyacSkoru: dersEntry.value,
              atamaTipi: AgmAssignmentType.auto,
              olusturulmaZamani: DateTime.now(),
            ),
          );

          // Güncellemeler
          ogrenciDoluSlot[ogrenciId]!.add(uygunGrup.saatDilimiId);
          grupMevcut[uygunGrup.id] = (grupMevcut[uygunGrup.id] ?? 0) + 1;
          ogrenciSaatSayisi[ogrenciId] = ogrenciSaatSayisi[ogrenciId]! + 1;

          if (!grupBucket.containsKey(uygunGrup.id)) {
            grupBucket[uygunGrup.id] = (ogrenciBasariOrani * 5).floor().clamp(
              0,
              4,
            );
          }

          if (ogrenciKazanimlar.isNotEmpty) {
            final frekansMap = grupKazanimFrekanslari.putIfAbsent(
              uygunGrup.id,
              () => {},
            );
            for (final k in ogrenciKazanimlar) {
              frekansMap[k] = (frekansMap[k] ?? 0) + 1;
            }
          }
        } else {
          yerlesmemeNedenleri[ogrenciId]!.add('$dersId: ${findResult.reason}');
        }
      }
    }

    // Hiç yerleşemeyenler ve Eksik yerleşenler
    final List<String> eksikAtananIds = [];
    for (final profil in ogrenciProfiller) {
      final ogrenciId = profil.ogrenciId;
      final ogrenciAtamalar = atamalar
          .where((a) => a.ogrenciId == ogrenciId)
          .toList();
      final atananSayisi = ogrenciAtamalar.length;

      if (atananSayisi == 0) {
        yerlesmeyenIds.add(ogrenciId);
      } else if (minimumDersSayisi != null &&
          atananSayisi < minimumDersSayisi!) {
        eksikAtananIds.add(ogrenciId);

        final atananDersIsimleri = ogrenciAtamalar
            .map((e) {
              final g = gruplar.firstWhere(
                (x) => x.id == e.groupId,
                orElse: () => gruplar.first,
              );
              return g.dersAdi;
            })
            .toSet()
            .join(', ');

        if (profil.dersIhtiyaclari.length == atananSayisi) {
          // Öğrenciye gereken tüm dersler atanmış, minimuma sırf başarılı olduğu için ulaşamamış
          yerlesmemeNedenleri[ogrenciId] = [
            'Atandığı dersler: $atananDersIsimleri',
            'Başka dersten yüzdelik başarı eksikliği (ihtiyacı) bulunmamaktadır.',
          ];
        } else {
          // Başka eksikleri de vardı ama kapasite veya çakışma gibi sebeplerle atanamadı
          yerlesmemeNedenleri[ogrenciId]!.insert(
            0,
            'Atandığı dersler: $atananDersIsimleri',
          );
        }
      }
    }

    // Final adım: Grup dökümanlarını (in-memory) kazanımlarla güncelle (UI'da göstermek için)
    final listGuncelGruplar = gruplar.map((g) {
      final frekanslar = grupKazanimFrekanslari[g.id] ?? {};
      // Frekansa göre sırala ve ilk 3'ü al (1 ana + 2 yardımcı)
      final siraliKazanimlar = frekanslar.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final top3 = siraliKazanimlar.take(3).map((e) => e.key).toList();

      return g.copyWith(
        mevcutOgrenciSayisi: grupMevcut[g.id] ?? 0,
        kazanimlar: top3,
      );
    }).toList();

    return AgmDraftResult(
      atamalar: atamalar,
      gruplar: listGuncelGruplar,
      yerlesmeyenOgrenciIds: yerlesmeyenIds,
      eksikAtananOgrenciIds: eksikAtananIds,
      softUyarilar: uyarilar,
      yerlesmemeNedenleri: yerlesmemeNedenleri,
    );
  }

  /// Minimum ders sayısı kontrolü için yardımcı özellik
  int? get minimumDersSayisi {
    // Bu değer genellikle cycle modelinden gelir. GenerateDraft'a parametre olarak da eklenebilir.
    // Ancak mevcut yapıda global bir referans yoksa engine'e constructorda eklenebilir.
    return _minimumDersSayisi;
  }

  int? _minimumDersSayisi;

  void setMinimumDersSayisi(int? val) => _minimumDersSayisi = val;

  /// En verimli grubu bul (Doluluk ve Kazanım odaklı) + Neden Analizi
  _FindGroupResult _findBestEfficientGroupWithReason({
    required String dersId,
    required String ogrenciId,
    required Set<String> ogrenciKazanimlar,
    required double ogrenciBasariOrani,
    required Set<String> ogrenciDoluSlot,
    required List<AgmGroup> gruplar,
    required Map<String, int> grupMevcut,
    required Map<String, Map<String, int>> grupKazanimFrekanslari,
    required Map<String, int> grupBucket,
  }) {
    // 1) Bu ders için tüm gruplar
    final dersGruplari = gruplar.where((g) {
      return g.dersId == dersId || g.dersAdi == dersId;
    }).toList();

    if (dersGruplari.isEmpty) {
      return _FindGroupResult(
        null,
        'Bu ders için tanımlanmış grup bulunamadı.',
      );
    }

    // 2) HARD CONSTRAINT filtreleme
    final uygunGruplar = <AgmGroup>[];
    String lastRefusalReason = 'Uygun grup bulunamadı.';

    for (final g in dersGruplari) {
      // Öğrenci slot çakışması
      if (ogrenciDoluSlot.contains(g.saatDilimiId)) {
        lastRefusalReason =
            'Saat çakışması (${g.baslangicSaat}-${g.bitisSaat}).';
        continue;
      }

      // HARD KAPASİTE KONTROLÜ
      final mevcut = grupMevcut[g.id] ?? 0;
      if (mevcut >= g.kapasite) {
        lastRefusalReason = 'Tüm gruplar dolu (${g.kapasite}/${g.kapasite}).';
        continue;
      }

      uygunGruplar.add(g);
    }

    if (uygunGruplar.isEmpty) {
      return _FindGroupResult(null, lastRefusalReason);
    }

    final int studentBucket = (ogrenciBasariOrani * 5).floor().clamp(0, 4);

    // 3) SIRALAMA (En verimli grup)
    uygunGruplar.sort((a, b) {
      final aDoluluk = grupMevcut[a.id] ?? 0;
      final bDoluluk = grupMevcut[b.id] ?? 0;

      final aBkt = grupBucket[a.id];
      final bBkt = grupBucket[b.id];

      // Eğer grup boşsa, bucket farkı 0 kabul edilir (herkes girebilir).
      int aDist = aBkt == null ? 0 : (aBkt - studentBucket).abs();
      int bDist = bBkt == null ? 0 : (bBkt - studentBucket).abs();

      // Öncelikle seviyesi en yakın olan grubu tercih et
      if (aDist != bDist) return aDist.compareTo(bDist);

      // Mesafe eşitse (örneğin ikisi de 0), "tam eşleşme" ile "boş grup" arasında tam eşleşmeyi öne alalım.
      // Boş grupları diğer seviyeler için rezerve bırakmak daha iyidir.
      if (aDist == 0 && bDist == 0) {
        bool aIsExact = aBkt != null && aBkt == studentBucket;
        bool bIsExact = bBkt != null && bBkt == studentBucket;
        if (aIsExact != bIsExact) return aIsExact ? -1 : 1;
      }

      // Seviyeler eşitse kazanım uyumuna bakalım
      final aKazanimlar = (grupKazanimFrekanslari[a.id] ?? {}).keys.toSet();
      final bKazanimlar = (grupKazanimFrekanslari[b.id] ?? {}).keys.toSet();
      final aMatchCount = ogrenciKazanimlar.intersection(aKazanimlar).length;
      final bMatchCount = ogrenciKazanimlar.intersection(bKazanimlar).length;
      // Çok kesişen (eksik kazanımı grubun odaklandığı kazanıma uyan) önce:
      if (aMatchCount != bMatchCount) return bMatchCount.compareTo(aMatchCount);

      // Doluluk durumu (Sınıfları optimum doldurmak için daha dolu olanı doldurmayı tercih et)
      if (aDoluluk != bDoluluk) return bDoluluk.compareTo(aDoluluk);

      return 0;
    });

    return _FindGroupResult(uygunGruplar.first, '');
  }
}

class _FindGroupResult {
  final AgmGroup? group;
  final String reason;
  _FindGroupResult(this.group, this.reason);
}
