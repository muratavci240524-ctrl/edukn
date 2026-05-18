import 'dart:math';
import '../models/camp_assignment_model.dart';
import '../models/camp_group_model.dart';

/// Bir öğrencinin ders bazlı ihtiyaç profili
class StudentNeedProfile {
  final String ogrenciId;
  final String ogrenciAdi;
  final String subeId;
  final String subeAdi;

  /// dersId -> ihtiyaçlar (1.0 - basariOrani), azalan sıralı
  final Map<String, double> dersIhtiyaclari;

  /// dersId -> başarı oranı (0.0 - 1.0)
  final Map<String, double> dersBasariOranlari;

  /// dersId -> Set<kazanimAdi> (öğrencinin bu derste zayıf olduğu kazanımlar)
  final Map<String, Set<String>> kazanimIhtiyaclari;

  double get toplamIhtiyac => dersIhtiyaclari.values.fold(0.0, (a, b) => a + b);

  StudentNeedProfile({
    required this.ogrenciId,
    required this.ogrenciAdi,
    required this.subeId,
    required this.subeAdi,
    required this.dersIhtiyaclari,
    this.dersBasariOranlari = const {},
    this.kazanimIhtiyaclari = const {},
  });
}

/// Yerleştirme sonucu
class CampDraftResult {
  final List<CampAssignment> atamalar;
  final List<CampGroup> gruplar;
  final List<String> yerlesmeyenOgrenciIds;
  final List<String> eksikAtananOgrenciIds;
  final Map<String, List<String>> yerlesmemeNedenleri;

  CampDraftResult({
    required this.atamalar,
    required this.gruplar,
    required this.yerlesmeyenOgrenciIds,
    this.eksikAtananOgrenciIds = const [],
    this.yerlesmemeNedenleri = const {},
  });
}

class CampAssignmentEngine {
  final String cycleId;
  final String institutionId;
  final int? haftalikMaksimumSaat;
  int? minimumGrupOgrenciSayisi;
  int? _minimumDersSayisi;

  CampAssignmentEngine({
    required this.cycleId,
    required this.institutionId,
    this.haftalikMaksimumSaat,
    this.minimumGrupOgrenciSayisi,
  });

  void setMinimumDersSayisi(int? val) => _minimumDersSayisi = val;

  Future<CampDraftResult> generateDraft({
    required List<StudentNeedProfile> ogrenciProfiller,
    required List<CampGroup> gruplar,
    double esikBasariOrani = 0.6,
    bool sadeceDusukBasari = true,
    Map<String, double> dersBazliEsikler = const {},
    Map<String, Map<String, int>>? gecmisKatilimlar,
    double penaltyMultiplier = 0.15,
  }) async {
    final Set<String> disabledGroupIds = {};
    CampDraftResult? finalResult;

    // Maksimum 10 iterasyon (AGM Assignment Engine logic)
    for (int iter = 0; iter < 10; iter++) {
      final passResult = _runPass(
        ogrenciProfiller: ogrenciProfiller,
        gruplar: gruplar,
        disabledGroupIds: disabledGroupIds,
        esikBasariOrani: esikBasariOrani,
        sadeceDusukBasari: sadeceDusukBasari,
        dersBazliEsikler: dersBazliEsikler,
        gecmisKatilimlar: gecmisKatilimlar,
        penaltyMultiplier: penaltyMultiplier,
      );

      if (minimumGrupOgrenciSayisi == null || minimumGrupOgrenciSayisi! <= 1) {
        finalResult = passResult;
        break;
      }

      // Kriteri sağlamayan grupları bul (Özel sınıflar hariç)
      final underEnrolledIds = passResult.gruplar
          .where((g) =>
              !g.isSpecial &&
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
    // o grupları ve atamalarını temizleyip öğrencileri yerleşemeyenlere geri ekleyelim.
    if (minimumGrupOgrenciSayisi != null && minimumGrupOgrenciSayisi! > 1) {
      final finalUnderEnrolledIds = finalResult!.gruplar
          .where((g) =>
              !g.isSpecial &&
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

        finalResult = CampDraftResult(
          atamalar: filteredAtamalar,
          gruplar: filteredGruplar,
          yerlesmeyenOgrenciIds: newYerlesmeyen.toList(),
          eksikAtananOgrenciIds: finalResult.eksikAtananOgrenciIds,
          yerlesmemeNedenleri: finalResult.yerlesmemeNedenleri,
        );
      }
    }

    return finalResult!;
  }

  CampDraftResult _runPass({
    required List<StudentNeedProfile> ogrenciProfiller,
    required List<CampGroup> gruplar,
    required Set<String> disabledGroupIds,
    double esikBasariOrani = 0.6,
    bool sadeceDusukBasari = true,
    Map<String, double> dersBazliEsikler = const {},
    Map<String, Map<String, int>>? gecmisKatilimlar,
    double penaltyMultiplier = 0.15,
  }) {
    final Map<String, Set<String>> ogrenciDoluSlot = {};
    final Map<String, int> ogrenciSaatSayisi = {};
    final Map<String, int> grupMevcut = {for (final g in gruplar) g.id: 0};
    final Map<String, List<String>> yerlesmemeNedenleri = {};
    final List<CampAssignment> atamalar = [];
    final List<String> yerlesmeyenIds = [];

    // Kazanım takibi
    final Map<String, Map<String, int>> grupKazanimFrekanslari = {for (final g in gruplar) g.id: {}};

    // 1. ÖZEL SINIF YERLEŞTİRMESİ (Top 24 Başarılı Öğrenci)
    final specialGroups = gruplar.where((g) => g.isSpecial && !disabledGroupIds.contains(g.id)).toList();
    if (specialGroups.isNotEmpty) {
      // Başarı ortalamasına göre sırala (Yüksekten düşüğe)
      final basariliOgrenciler = List<StudentNeedProfile>.from(ogrenciProfiller)
        ..sort((a, b) {
          final avgA = a.dersBasariOranlari.isEmpty ? 0.0 : a.dersBasariOranlari.values.fold(0.0, (sum, v) => sum + v) / a.dersBasariOranlari.length;
          final avgB = b.dersBasariOranlari.isEmpty ? 0.0 : b.dersBasariOranlari.values.fold(0.0, (sum, v) => sum + v) / b.dersBasariOranlari.length;
          return avgB.compareTo(avgA);
        });

      final top24 = basariliOgrenciler.take(24).toList();
      for (final profil in top24) {
        final ogrenciId = profil.ogrenciId;
        ogrenciDoluSlot.putIfAbsent(ogrenciId, () => {});
        ogrenciSaatSayisi.putIfAbsent(ogrenciId, () => 0);

        for (final g in specialGroups) {
          final studentAvg = profil.dersBasariOranlari.isEmpty ? 0.0 : profil.dersBasariOranlari.values.fold(0.0, (sum, v) => sum + v) / profil.dersBasariOranlari.length;
          atamalar.add(CampAssignment(
            id: '${cycleId}_${ogrenciId}_${g.id}',
            cycleId: cycleId,
            groupId: g.id,
            groupName: g.dersAdi,
            ogrenciId: ogrenciId,
            ogrenciAdi: profil.ogrenciAdi,
            sube: profil.subeAdi,
            subeId: profil.subeId,
            atamaTipi: CampAssignmentType.auto,
            basariOrani: studentAvg, 
            ihtiyacSkoru: 0.0,
          ));

          ogrenciDoluSlot[ogrenciId]!.add(g.saatDilimiId);
          grupMevcut[g.id] = grupMevcut[g.id]! + 1;
          ogrenciSaatSayisi[ogrenciId] = (ogrenciSaatSayisi[ogrenciId] ?? 0) + 1;
          
          // Özel sınıf kazanımı: Soru Çözüm
          grupKazanimFrekanslari[g.id]!['Soru Çözüm'] = 100; 
        }
      }
    }

    // 2. İstatistikler ve Grupları Seviyelendirme (AGM Logic)
    final Map<String, List<double>> subjectSuccessLevels = {};
    for (final p in ogrenciProfiller) {
      for (final entry in p.dersBasariOranlari.entries) {
        subjectSuccessLevels.putIfAbsent(entry.key, () => []).add(entry.value);
      }
    }

    final Map<String, double> grupTargetValue = {};
    final Map<String, List<CampGroup>> groupsOfSubject = {};
    for (final g in gruplar) {
      if (!disabledGroupIds.contains(g.id)) {
        groupsOfSubject.putIfAbsent(g.dersId, () => []).add(g);
      }
    }

    groupsOfSubject.forEach((dersId, dersGruplari) {
      final levels = subjectSuccessLevels[dersId] ?? [0.5];
      levels.sort();
      for (int i = 0; i < dersGruplari.length; i++) {
        final targetPercentile = (i + 0.5) / dersGruplari.length;
        final val = levels[(targetPercentile * levels.length).floor().clamp(0, levels.length - 1)];
        grupTargetValue[dersGruplari[i].id] = val;
      }
    });

    int getDayIndex(String dayStr) {
      final d = dayStr.toLowerCase();
      if (d.contains('pazartesi') || d.contains('pzt')) return 1;
      if (d.contains('salı') || d.contains('sali') || d.contains('sal')) return 2;
      if (d.contains('çarşamba') || d.contains('carsamba') || d.contains('çrş')) return 3;
      if (d.contains('perşembe') || d.contains('persembe') || d.contains('prş')) return 4;
      if (d.contains('cumartesi') || d.contains('cmt')) return 6;
      if (d.contains('cuma') || d.contains('cum')) return 5;
      if (d.contains('pazar') || d.contains('pzr')) return 7;
      return 99;
    }

    final Set<String> gunlerSet = {};
    for (final g in gruplar) {
      if (!g.isSpecial && g.gun.isNotEmpty && !disabledGroupIds.contains(g.id)) gunlerSet.add(g.gun);
    }
    final siraliGunler = gunlerSet.toList()..sort((a, b) {
      final idxA = getDayIndex(a);
      final idxB = getDayIndex(b);
      if (idxA == idxB) return a.compareTo(b);
      return idxA.compareTo(idxB);
    });
    if (siraliGunler.isEmpty) siraliGunler.add(''); // Fallback

    final workingGecmisKatilimlar = gecmisKatilimlar != null 
       ? Map<String, Map<String, int>>.from(gecmisKatilimlar.map((k, v) => MapEntry(k, Map<String, int>.from(v)))) 
       : <String, Map<String, int>>{};

    for (final gun in siraliGunler) {
      final gununGruplari = gun.isEmpty 
          ? gruplar.where((g) => !g.isSpecial && !disabledGroupIds.contains(g.id)).toList() 
          : gruplar.where((g) => !g.isSpecial && !disabledGroupIds.contains(g.id) && g.gun == gun).toList();

      // 2. Öğrencileri Sırala (Zor durumdakiler önce)
      final siralanmisProfiller = List<StudentNeedProfile>.from(ogrenciProfiller)..sort((a, b) => b.toplamIhtiyac.compareTo(a.toplamIhtiyac));

      for (final profil in siralanmisProfiller) {
        final ogrenciId = profil.ogrenciId;
        ogrenciDoluSlot.putIfAbsent(ogrenciId, () => {});
        ogrenciSaatSayisi.putIfAbsent(ogrenciId, () => 0);
        yerlesmemeNedenleri.putIfAbsent(ogrenciId, () => []);

        final ogrenciGecmis = workingGecmisKatilimlar.putIfAbsent(ogrenciId, () => {});
        
        final siraliDersler = profil.dersIhtiyaclari.entries.toList()..sort((a, b) {
          // Geçmiş katılım cezası hesapla (Eğer öğrenci daha önce bu derse atandıysa önceliği düşür)
          final pastA = ogrenciGecmis[a.key] ?? 0;
          final pastB = ogrenciGecmis[b.key] ?? 0;
          
          final penaltyA = pastA * penaltyMultiplier;
          final penaltyB = pastB * penaltyMultiplier;
          
          final adjustedA = a.value - penaltyA;
          final adjustedB = b.value - penaltyB;
          
          return adjustedB.compareTo(adjustedA);
        });

        for (final dersEntry in siraliDersler) {
          final dersId = dersEntry.key;
          final basariOrani = profil.dersBasariOranlari[dersId] ?? 0.0;
          final esik = dersBazliEsikler[dersId] ?? esikBasariOrani;

          if (sadeceDusukBasari && basariOrani > esik) continue;

          if (haftalikMaksimumSaat != null && ogrenciSaatSayisi[ogrenciId]! >= haftalikMaksimumSaat!) {
            yerlesmemeNedenleri[ogrenciId]!.add('$dersId: Maksimum saat limitine takıldı.');
            continue;
          }

          final findResult = _findBestGroup(
            dersId: dersId,
            ogrenciBasariOrani: basariOrani,
            ogrenciDoluSlot: ogrenciDoluSlot[ogrenciId]!,
            gruplar: gununGruplari,
            grupMevcut: grupMevcut,
            grupTargetValues: grupTargetValue,
            ogrenciKazanimlar: profil.kazanimIhtiyaclari[dersId] ?? {},
            grupKazanimFrekanslari: grupKazanimFrekanslari,
            disabledGroupIds: disabledGroupIds,
          );

          if (findResult.group != null) {
            final g = findResult.group!;
            atamalar.add(CampAssignment(
              id: '${cycleId}_${ogrenciId}_${g.id}',
              cycleId: cycleId,
              groupId: g.id,
              groupName: '${g.dersId} - ${g.ogretmenAdi}',
              ogrenciId: ogrenciId,
              ogrenciAdi: profil.ogrenciAdi,
              sube: profil.subeAdi,
              subeId: profil.subeId,
              atamaTipi: CampAssignmentType.auto,
              basariOrani: basariOrani,
              ihtiyacSkoru: dersEntry.value,
            ));

            ogrenciDoluSlot[ogrenciId]!.add(g.saatDilimiId);
            grupMevcut[g.id] = grupMevcut[g.id]! + 1;
            ogrenciSaatSayisi[ogrenciId] = ogrenciSaatSayisi[ogrenciId]! + 1;
            
            // Atandığı dersi geçmiş katılımlara anında ekle (Sonraki gün veya seansta ceza yesin)
            ogrenciGecmis[g.dersId] = (ogrenciGecmis[g.dersId] ?? 0) + 1;

            // Kazanım frekanslarını güncelle
            final ogrenciKazanimlar = profil.kazanimIhtiyaclari[dersId] ?? {};
            if (ogrenciKazanimlar.isNotEmpty) {
              final fMap = grupKazanimFrekanslari[g.id]!;
              for (final k in ogrenciKazanimlar) fMap[k] = (fMap[k] ?? 0) + 1;
            }
          } else {
            yerlesmemeNedenleri[ogrenciId]!.add('$dersId (${gun.isEmpty ? "Genel" : gun}): ${findResult.reason}');
          }
        }
      }
    }

    final List<String> eksikAtananIds = [];
    for (final profil in ogrenciProfiller) {
      final atananSayisi = atamalar.where((a) => a.ogrenciId == profil.ogrenciId).length;
      if (atananSayisi == 0) yerlesmeyenIds.add(profil.ogrenciId);
      else if (_minimumDersSayisi != null && atananSayisi < _minimumDersSayisi!) eksikAtananIds.add(profil.ogrenciId);
    }

    // 3. Grupları ve Kazanımları Güncelle
    // Genel konu frekanslarını hesapla (Fallback için)
    final Map<String, Map<String, int>> subjectGlobalFrequencies = {};
    for (final profil in ogrenciProfiller) {
      profil.kazanimIhtiyaclari.forEach((dersId, topics) {
        final fMap = subjectGlobalFrequencies.putIfAbsent(dersId, () => {});
        for (final k in topics) fMap[k] = (fMap[k] ?? 0) + 1;
      });
    }

    final updatedGroups = gruplar.map((g) {
      var frekanslar = grupKazanimFrekanslari[g.id] ?? {};
      
      // FALLBACK: Eğer bu grupta hiç kazanım birikmemişse, dersin genel en sık konularını al
      if (frekanslar.isEmpty && !g.isSpecial) {
        frekanslar = subjectGlobalFrequencies[g.dersId] ?? subjectGlobalFrequencies[g.dersAdi] ?? {};
      }

      final siraliKazanimlar = frekanslar.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final top3 = siraliKazanimlar.take(3).map((e) => e.key).toList();
      return g.copyWith(mevcutOgrenciSayisi: grupMevcut[g.id] ?? 0, kazanimlar: top3);
    }).toList();

    return CampDraftResult(atamalar: atamalar, gruplar: updatedGroups, yerlesmeyenOgrenciIds: yerlesmeyenIds, eksikAtananOgrenciIds: eksikAtananIds, yerlesmemeNedenleri: yerlesmemeNedenleri);
  }

  _FindResult _findBestGroup({
    required String dersId,
    required double ogrenciBasariOrani,
    required Set<String> ogrenciDoluSlot,
    required List<CampGroup> gruplar,
    required Map<String, int> grupMevcut,
    required Map<String, double> grupTargetValues,
    required Set<String> ogrenciKazanimlar,
    required Map<String, Map<String, int>> grupKazanimFrekanslari,
    required Set<String> disabledGroupIds,
  }) {
    final uygunGruplar = gruplar.where((g) => 
      !disabledGroupIds.contains(g.id) &&
      (g.dersId == dersId || g.dersAdi == dersId) && 
      !ogrenciDoluSlot.contains(g.saatDilimiId) && 
      grupMevcut[g.id]! < g.kapasite
    ).toList();

    if (uygunGruplar.isEmpty) {
      final potential = gruplar.where((g) => !disabledGroupIds.contains(g.id) && (g.dersId == dersId || g.dersAdi == dersId)).toList();
      if (potential.isEmpty) return _FindResult(null, 'Bu ders için grup yok.');
      if (potential.every((g) => ogrenciDoluSlot.contains(g.saatDilimiId))) return _FindResult(null, 'Saat çakışması.');
      return _FindResult(null, 'Kapasite dolu.');
    }

    uygunGruplar.sort((a, b) {
      // 1. Seviye Uyumu (AGM gibi homojen gruplar için)
      final aTarget = grupTargetValues[a.id] ?? 0.5;
      final bTarget = grupTargetValues[b.id] ?? 0.5;
      final aDist = (aTarget - ogrenciBasariOrani).abs();
      final bDist = (bTarget - ogrenciBasariOrani).abs();
      if ((aDist - bDist).abs() > 0.05) return aDist.compareTo(bDist);

      // 2. Kazanım Uyumu
      final aK = (grupKazanimFrekanslari[a.id] ?? {}).keys.toSet();
      final bK = (grupKazanimFrekanslari[b.id] ?? {}).keys.toSet();
      final aMatch = ogrenciKazanimlar.intersection(aK).length;
      final bMatch = ogrenciKazanimlar.intersection(bK).length;
      if (aMatch != bMatch) return bMatch.compareTo(aMatch);

      // 3. Doluluk Dengesi
      return grupMevcut[a.id]!.compareTo(grupMevcut[b.id]!);
    });

    return _FindResult(uygunGruplar.first, '');
  }
}

class _FindResult {
  final CampGroup? group;
  final String reason;
  _FindResult(this.group, this.reason);
}
