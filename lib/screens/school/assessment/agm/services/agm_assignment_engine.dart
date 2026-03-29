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

    // ── Gelişmiş Dağıtım İstatistikleri ──
    final Map<String, int> subjectTotalNeeds = {};
    final Map<String, List<double>> subjectSuccessLevels = {};
    for (final p in ogrenciProfiller) {
      for (final entry in p.dersIhtiyaclari.entries) {
        subjectTotalNeeds[entry.key] = (subjectTotalNeeds[entry.key] ?? 0) + 1;
        subjectSuccessLevels.putIfAbsent(entry.key, () => []).add(p.dersBasariOranlari[entry.key] ?? 0.0);
      }
    }
    
    final Map<String, int> targetGroupSize = {};
    final Map<String, List<AgmGroup>> groupsOfSubject = {};
    for (final g in gruplar) {
      if (disabledGroupIds.contains(g.id)) continue;
      groupsOfSubject.putIfAbsent(g.dersId, () => []).add(g);
    }
    
    final Map<String, double> grupTargetValue = {};
    groupsOfSubject.forEach((dersId, dersGruplari) {
      final totalNeed = subjectTotalNeeds[dersId] ?? 0;
      targetGroupSize[dersId] = (totalNeed / dersGruplari.length).ceil();
      
      final levels = subjectSuccessLevels[dersId]!..sort();
      for (int i = 0; i < dersGruplari.length; i++) {
        final targetPercentile = (i + 0.5) / dersGruplari.length;
        final val = levels[(targetPercentile * levels.length).floor().clamp(0, levels.length - 1)];
        grupTargetValue[dersGruplari[i].id] = val;
      }
    });

    final Map<String, Map<String, int>> grupKazanimFrekanslari = {
      for (final g in gruplar) g.id: {},
    };

    final Map<String, int> grupBucket = {};

    // Öğrencileri toplam ihtiyaca göre sırala (zor durumdakiler önce)
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
        final int studentBucket = (ogrenciBasariOrani * 10).floor().clamp(0, 9);

        final findResult = _findBestEfficientGroupWithReason(
          dersId: dersId,
          ogrenciId: ogrenciId,
          ogrenciKazanimlar: ogrenciKazanimlar,
          studentBucket: studentBucket,
          ogrenciBasariOrani: ogrenciBasariOrani,
          ogrenciDoluSlot: ogrenciDoluSlot[ogrenciId]!,
          gruplar: gruplar,
          grupMevcut: grupMevcut,
          grupKazanimFrekanslari: grupKazanimFrekanslari,
          grupBucket: grupBucket,
          grupTargetValues: grupTargetValue,
          disabledGroupIds: disabledGroupIds,
          targetSize: targetGroupSize[dersId] ?? 99,
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
          ogrenciSaatSayisi[ogrenciId] = (ogrenciSaatSayisi[ogrenciId] ?? 0) + 1;
          
          if (!grupBucket.containsKey(uygunGrup.id)) {
            grupBucket[uygunGrup.id] = studentBucket;
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
    required int studentBucket,
    required double ogrenciBasariOrani,
    required Set<String> ogrenciDoluSlot,
    required List<AgmGroup> gruplar,
    required Map<String, int> grupMevcut,
    required Map<String, Map<String, int>> grupKazanimFrekanslari,
    required Map<String, int> grupBucket,
    required Map<String, double> grupTargetValues,
    required Set<String> disabledGroupIds,
    required int targetSize,
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
        lastRefusalReason = 'Bu grup kapatıldı.';
        continue;
      }
      uygunGruplar.add(g);
    }

    if (uygunGruplar.isEmpty) {
      return _FindGroupResult(null, lastRefusalReason);
    }

    uygunGruplar.sort((a, b) {
      final aDoluluk = grupMevcut[a.id] ?? 0;
      final bDoluluk = grupMevcut[b.id] ?? 0;
      final aBkt = grupBucket[a.id];
      final bBkt = grupBucket[b.id];

      // 1. Hedef Seviye Uyumu (Percentile Match)
      // Bu grubun hedeflediği başarı seviyesi öğrenciye ne kadar yakın?
      final aTarget = grupTargetValues[a.id] ?? 0.5;
      final bTarget = grupTargetValues[b.id] ?? 0.5;
      final aTargetDist = (aTarget - ogrenciBasariOrani).abs();
      final bTargetDist = (bTarget - ogrenciBasariOrani).abs();
      
      if ((aTargetDist - bTargetDist).abs() > 0.001) {
        return aTargetDist.compareTo(bTargetDist);
      }

      // 2. Homojenlik (Mevcut Bucket Uyumu)
      // Grup zaten bir seviye kazandıysa oraya sadık kal.
      int aDist = aBkt == null ? 0 : (aBkt - studentBucket).abs();
      int bDist = bBkt == null ? 0 : (bBkt - studentBucket).abs();
      if (aDist != bDist) return aDist.compareTo(bDist);

      if (aDist == 0) {
        bool aIsMarked = aBkt != null;
        bool bIsMarked = bBkt != null;
        if (aIsMarked != bIsMarked) return aIsMarked ? -1 : 1;
      }

      // 3. Yoğunluk Dengesi (Equality)
      bool aIsOverTarget = aDoluluk >= targetSize;
      bool bIsOverTarget = bDoluluk >= targetSize;
      if (aIsOverTarget != bIsOverTarget) return aIsOverTarget ? 1 : -1;

      // 4. İnce Yük Dengeleme (Doluluk)
      if (aDoluluk != bDoluluk) return aDoluluk.compareTo(bDoluluk);

      // 5. Kazanım Uyumu
      final aKazanimlar = (grupKazanimFrekanslari[a.id] ?? {}).keys.toSet();
      final bKazanimlar = (grupKazanimFrekanslari[b.id] ?? {}).keys.toSet();
      final aMatchCount = ogrenciKazanimlar.intersection(aKazanimlar).length;
      final bMatchCount = ogrenciKazanimlar.intersection(bKazanimlar).length;
      if (aMatchCount != bMatchCount) return bMatchCount.compareTo(aMatchCount);
      
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
