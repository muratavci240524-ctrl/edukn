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
  final List<String> eksikAtananOgrenciIds; // Minimum ders sayısına ulaşamayanlar
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
/// ─────────────────────────────────────────────────────────────────────────────
class AgmAssignmentEngine {
  final String cycleId;
  final String institutionId;
  final int? haftalikMaksimumSaat;
  int? minimumGrupOgrenciSayisi;
  int? _minimumDersSayisi;

  AgmAssignmentEngine({
    required this.cycleId,
    required this.institutionId,
    this.haftalikMaksimumSaat,
    this.minimumGrupOgrenciSayisi,
  });

  void setMinimumDersSayisi(int? val) => _minimumDersSayisi = val;
  void setMinimumGrupOgrenciSayisi(int? val) => minimumGrupOgrenciSayisi = val;

  /// Ana giriş noktası. İteratif olarak dağıtım yapar.
  Future<AgmDraftResult> generateDraft({
    required List<StudentNeedProfile> ogrenciProfiller,
    required List<AgmGroup> gruplar,
  }) async {
    final Set<String> disabledGroupIds = {};
    AgmDraftResult? finalResult;

    // Maksimum 10 iterasyon (Infinite loop önlemi)
    for (int iter = 0; iter < 10; iter++) {
      final passResult = _runPass(
        ogrenciProfiller: ogrenciProfiller,
        gruplar: gruplar,
        disabledGroupIds: disabledGroupIds,
      );

      if (minimumGrupOgrenciSayisi == null || minimumGrupOgrenciSayisi! <= 1) {
        finalResult = passResult;
        break;
      }

      // Kriteri sağlamayan grupları bul (en az 1 öğrencisi olan ama min altı kalanlar)
      final underEnrolledIds = passResult.gruplar
          .where((g) =>
              g.mevcutOgrenciSayisi > 0 &&
              g.mevcutOgrenciSayisi < minimumGrupOgrenciSayisi!)
          .map((g) => g.id)
          .toList();

      if (underEnrolledIds.isEmpty) {
        finalResult = passResult;
        break;
      }

      // Bu grupları devre dışı bırak ve yeniden dene
      disabledGroupIds.addAll(underEnrolledIds);
      finalResult = passResult;
    }

    // Son aşamada hala kriteri sağlamayan grup kaldıysa (10 iterasyona rağmen),
    // o grupları ve atamalarini temizleyip öğrencileri yerleşemeyenlere geri ekleyelim.
    if (minimumGrupOgrenciSayisi != null && minimumGrupOgrenciSayisi! > 1) {
      final finalUnderEnrolledIds = finalResult!.gruplar
          .where((g) =>
              g.mevcutOgrenciSayisi > 0 &&
              g.mevcutOgrenciSayisi < minimumGrupOgrenciSayisi!)
          .map((g) => g.id)
          .toSet();

      if (finalUnderEnrolledIds.isNotEmpty) {
        final filteredAtamalar = finalResult.atamalar
            .where((a) => !finalUnderEnrolledIds.contains(a.groupId))
            .toList();

        final studentsFromRemovedGroups = finalResult.atamalar
            .where((a) => finalUnderEnrolledIds.contains(a.groupId))
            .map((a) => a.ogrenciId)
            .toList();

        final Set<String> newYerlesmeyen =
            finalResult.yerlesmeyenOgrenciIds.toSet()..addAll(studentsFromRemovedGroups);

        final filteredGruplar = finalResult.gruplar.map((g) {
          if (finalUnderEnrolledIds.contains(g.id)) {
            return g.copyWith(mevcutOgrenciSayisi: 0, kazanimlar: []);
          }
          return g;
        }).toList();

        finalResult = AgmDraftResult(
          atamalar: filteredAtamalar,
          gruplar: filteredGruplar,
          yerlesmeyenOgrenciIds: newYerlesmeyen.toList(),
          eksikAtananOgrenciIds: finalResult.eksikAtananOgrenciIds,
          softUyarilar: finalResult.softUyarilar,
          yerlesmemeNedenleri: finalResult.yerlesmemeNedenleri,
        );
      }
    }

    return finalResult!;
  }

  AgmDraftResult _runPass({
    required List<StudentNeedProfile> ogrenciProfiller,
    required List<AgmGroup> gruplar,
    required Set<String> disabledGroupIds,
  }) {
    final Map<String, Set<String>> ogrenciDoluSlot = {};
    final Map<String, int> ogrenciSaatSayisi = {};
    final Map<String, List<String>> yerlesmemeNedenleri = {};

    final Map<String, int> grupMevcut = {
      for (final g in gruplar) g.id: 0,
    };

    final List<AgmAssignment> atamalar = [];
    final List<String> yerlesmeyenIds = [];
    final List<AgmSoftWarning> uyarilar = [];

    final Map<String, Map<String, int>> grupKazanimFrekanslari = {
      for (final g in gruplar)
        g.id: {
          for (final k in g.kazanimlar) k: 10,
        },
    };

    final Map<String, int> grupBucket = {};

    final siralanmisProfillar = List<StudentNeedProfile>.from(ogrenciProfiller)
      ..sort((a, b) => b.toplamIhtiyac.compareTo(a.toplamIhtiyac));

    for (final profil in siralanmisProfillar) {
      final ogrenciId = profil.ogrenciId;
      ogrenciDoluSlot.putIfAbsent(ogrenciId, () => {});
      ogrenciSaatSayisi.putIfAbsent(ogrenciId, () => 0);
      yerlesmemeNedenleri.putIfAbsent(ogrenciId, () => []);

      final siraliDersler = profil.dersIhtiyaclari.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      for (final dersEntry in siraliDersler) {
        final dersId = dersEntry.key;

        if (haftalikMaksimumSaat != null &&
            ogrenciSaatSayisi[ogrenciId]! >= haftalikMaksimumSaat!) {
          yerlesmemeNedenleri[ogrenciId]!.add(
            '$dersId: Haftalık max ders limitine ($haftalikMaksimumSaat) takıldı.',
          );
          continue;
        }

        final ogrenciKazanimlar = profil.kazanimIhtiyaclari[dersId] ?? {};
        final ogrenciBasariOrani = profil.dersBasariOranlari[dersId] ?? 0.0;

        final findResult = _findBestEfficientGroupWithReason(
          dersId: dersId,
          ogrenciId: ogrenciId,
          ogrenciKazanimlar: ogrenciKazanimlar,
          ogrenciBasariOrani: ogrenciBasariOrani,
          ogrenciDoluSlot: ogrenciDoluSlot[ogrenciId]!,
          gruplar: gruplar,
          grupMevcut: grupMevcut,
          grupKazanimFrekanslari: grupKazanimFrekanslari,
          grupBucket: grupBucket,
          disabledGroupIds: disabledGroupIds,
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

          ogrenciDoluSlot[ogrenciId]!.add(uygunGrup.saatDilimiId);
          grupMevcut[uygunGrup.id] = (grupMevcut[uygunGrup.id] ?? 0) + 1;
          ogrenciSaatSayisi[ogrenciId] = ogrenciSaatSayisi[ogrenciId]! + 1;

          if (!grupBucket.containsKey(uygunGrup.id)) {
            grupBucket[uygunGrup.id] = (ogrenciBasariOrani * 5).floor().clamp(0, 4);
          }

          if (ogrenciKazanimlar.isNotEmpty) {
            final frekansMap = grupKazanimFrekanslari.putIfAbsent(uygunGrup.id, () => {});
            for (final k in ogrenciKazanimlar) {
              frekansMap[k] = (frekansMap[k] ?? 0) + 1;
            }
          }
        } else {
          yerlesmemeNedenleri[ogrenciId]!.add('$dersId: ${findResult.reason}');
        }
      }
    }

    final List<String> eksikAtananIds = [];
    for (final profil in ogrenciProfiller) {
      final ogrenciId = profil.ogrenciId;
      final ogrenciAtamalar = atamalar.where((a) => a.ogrenciId == ogrenciId).toList();
      final atananSayisi = ogrenciAtamalar.length;

      if (atananSayisi == 0) {
        yerlesmeyenIds.add(ogrenciId);
      } else if (_minimumDersSayisi != null && atananSayisi < _minimumDersSayisi!) {
        eksikAtananIds.add(ogrenciId);
      }
    }

    final listGuncelGruplar = gruplar.map((g) {
      final frekanslar = grupKazanimFrekanslari[g.id] ?? {};
      final siraliKazanimlar = frekanslar.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
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
    required Set<String> disabledGroupIds,
  }) {
    final dersGruplari = gruplar.where((g) {
      return g.dersId == dersId || g.dersAdi == dersId;
    }).toList();

    if (dersGruplari.isEmpty) {
      return _FindGroupResult(null, 'Bu ders için tanımlanmış grup bulunamadı.');
    }

    final uygunGruplar = <AgmGroup>[];
    String lastRefusalReason = 'Uygun grup bulunamadı.';

    for (final g in dersGruplari) {
      if (ogrenciDoluSlot.contains(g.saatDilimiId)) {
        lastRefusalReason = 'Saat çakışması (${g.baslangicSaat}-${g.bitisSaat}).';
        continue;
      }
      final mevcut = grupMevcut[g.id] ?? 0;
      if (mevcut >= g.kapasite) {
        lastRefusalReason = 'Tüm gruplar dolu (${g.kapasite}/${g.kapasite}).';
        continue;
      }
      if (disabledGroupIds.contains(g.id)) {
        lastRefusalReason = 'Bu grup minimum öğrenci sayısını karşılamadığı için kapatıldı.';
        continue;
      }
      uygunGruplar.add(g);
    }

    if (uygunGruplar.isEmpty) {
      return _FindGroupResult(null, lastRefusalReason);
    }

    final int studentBucket = (ogrenciBasariOrani * 5).floor().clamp(0, 4);

    uygunGruplar.sort((a, b) {
      final aDoluluk = grupMevcut[a.id] ?? 0;
      final bDoluluk = grupMevcut[b.id] ?? 0;
      final aBkt = grupBucket[a.id];
      final bBkt = grupBucket[b.id];

      int aDist = aBkt == null ? 0 : (aBkt - studentBucket).abs();
      int bDist = bBkt == null ? 0 : (bBkt - studentBucket).abs();

      if (aDist != bDist) return aDist.compareTo(bDist);
      if (aDist == 0 && bDist == 0) {
        bool aIsExact = aBkt != null && aBkt == studentBucket;
        bool bIsExact = bBkt != null && bBkt == studentBucket;
        if (aIsExact != bIsExact) return aIsExact ? -1 : 1;
      }

      final aKazanimlar = (grupKazanimFrekanslari[a.id] ?? {}).keys.toSet();
      final bKazanimlar = (grupKazanimFrekanslari[b.id] ?? {}).keys.toSet();
      final aMatchCount = ogrenciKazanimlar.intersection(aKazanimlar).length;
      final bMatchCount = ogrenciKazanimlar.intersection(bKazanimlar).length;
      if (aMatchCount != bMatchCount) return bMatchCount.compareTo(aMatchCount);
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
