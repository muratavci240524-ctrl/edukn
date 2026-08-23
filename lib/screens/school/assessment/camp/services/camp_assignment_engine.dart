import 'dart:math';
import '../models/camp_assignment_model.dart';
import '../models/camp_group_model.dart';

/// Bir öğrencinin ders bazlı ihtiyaç profili
class StudentNeedProfile {
  final String ogrenciId;
  final String ogrenciAdi;
  final String subeId;
  final String subeAdi;
  final double examScore;

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
    this.examScore = 0.0,
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
    String specialClassCriteria = 'success_rate',
    Map<String, double> dersBazliEsikler = const {},
    Map<String, Map<String, int>>? gecmisKatilimlar,
    double penaltyMultiplier = 0.15,
    List<CampAssignment>? mevcutAtamalar,
    bool highSuccessSoruCozumActive = true,
    double highSuccessSoruCozumThreshold = 0.95,
    Map<String, Map<String, int>> dersBazliSaatSinirlari = const {},
    bool dersBazliZorlaAtama = true,
  }) async {
    final Set<String> disabledGroupIds = {};
    CampDraftResult? finalResult;

    // Maksimum 10 iterasyon (AGM Assignment Engine logic)
    for (int iter = 0; iter < 10; iter++) {
      // İlk çalıştırma
      CampDraftResult bestPass = _runPass(
        ogrenciProfiller: ogrenciProfiller,
        gruplar: gruplar,
        disabledGroupIds: disabledGroupIds,
        esikBasariOrani: esikBasariOrani,
        sadeceDusukBasari: sadeceDusukBasari,
        specialClassCriteria: specialClassCriteria,
        dersBazliEsikler: dersBazliEsikler,
        gecmisKatilimlar: gecmisKatilimlar,
        penaltyMultiplier: penaltyMultiplier,
        mevcutAtamalar: mevcutAtamalar,
        highSuccessSoruCozumActive: highSuccessSoruCozumActive,
        highSuccessSoruCozumThreshold: highSuccessSoruCozumThreshold,
        dersBazliSaatSinirlari: dersBazliSaatSinirlari,
        dersBazliZorlaAtama: dersBazliZorlaAtama,
      );

      // Eğer ders bazlı modda eksik kalan varsa veya homojenliği artırmak için farklı stratejileri dene
      if (dersBazliSaatSinirlari.isNotEmpty) {
        final List<double> candidatePenalties = [0.0, 0.05, 0.1, 0.15, 0.2, 0.25, 0.35, 0.5];
        for (final p in candidatePenalties) {
          final cand = _runPass(
            ogrenciProfiller: ogrenciProfiller,
            gruplar: gruplar,
            disabledGroupIds: disabledGroupIds,
            esikBasariOrani: esikBasariOrani,
            sadeceDusukBasari: sadeceDusukBasari,
            specialClassCriteria: specialClassCriteria,
            dersBazliEsikler: dersBazliEsikler,
            gecmisKatilimlar: gecmisKatilimlar,
            penaltyMultiplier: p,
            mevcutAtamalar: mevcutAtamalar,
            highSuccessSoruCozumActive: highSuccessSoruCozumActive,
            highSuccessSoruCozumThreshold: highSuccessSoruCozumThreshold,
            dersBazliSaatSinirlari: dersBazliSaatSinirlari,
            dersBazliZorlaAtama: dersBazliZorlaAtama,
          );

          final bestUnplaced = bestPass.eksikAtananOgrenciIds.length + bestPass.yerlesmeyenOgrenciIds.length;
          final candUnplaced = cand.eksikAtananOgrenciIds.length + cand.yerlesmeyenOgrenciIds.length;

          if (candUnplaced < bestUnplaced) {
            bestPass = cand;
            if (candUnplaced == 0) break; // Kusursuz %100 yerleşim bulundu!
          } else if (candUnplaced == bestUnplaced && candUnplaced == 0) {
            bestPass = cand;
            break;
          }
        }
      }

      final passResult = bestPass;

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
    String specialClassCriteria = 'success_rate',
    Map<String, double> dersBazliEsikler = const {},
    Map<String, Map<String, int>>? gecmisKatilimlar,
    double penaltyMultiplier = 0.15,
    List<CampAssignment>? mevcutAtamalar,
    bool highSuccessSoruCozumActive = true,
    double highSuccessSoruCozumThreshold = 0.95,
    Map<String, Map<String, int>> dersBazliSaatSinirlari = const {},
    bool dersBazliZorlaAtama = true,
  }) {
    final bool dersBazliAktif = dersBazliSaatSinirlari.isNotEmpty;
    final Map<String, Set<String>> ogrenciDoluSlot = {};
    final Map<String, int> ogrenciSaatSayisi = {};
    final Map<String, Map<String, int>> ogrenciDersSayisi = {}; // ogrenciId -> dersId -> atanma sayısı
    final Map<String, int> grupMevcut = {for (final g in gruplar) g.id: 0};
    final Map<String, List<String>> yerlesmemeNedenleri = {};
    final List<CampAssignment> atamalar = [];
    final List<String> yerlesmeyenIds = [];
    final Map<String, List<double>> grupBasarilari = {};

    // Kazanım takibi
    final Map<String, Map<String, int>> grupKazanimFrekanslari = {for (final g in gruplar) g.id: {}};

    // 1. ÖZEL SINIF YERLEŞTİRMESİ
    final Set<String> specialClassStudentIds = {};
    final specialGroups = gruplar.where((g) => g.isSpecial && !disabledGroupIds.contains(g.id)).toList();
    
    if (mevcutAtamalar != null && mevcutAtamalar.isNotEmpty) {
      atamalar.addAll(mevcutAtamalar);
      for (final a in mevcutAtamalar) {
        try {
          final g = gruplar.firstWhere((grp) => grp.id == a.groupId);
          ogrenciDoluSlot.putIfAbsent(a.ogrenciId, () => {}).add(g.saatDilimiId);
          grupMevcut[g.id] = (grupMevcut[g.id] ?? 0) + 1;
          ogrenciSaatSayisi[a.ogrenciId] = (ogrenciSaatSayisi[a.ogrenciId] ?? 0) + 1;
          if (g.isSpecial) {
            grupKazanimFrekanslari[g.id]!['Soru Çözüm'] = 100;
            specialClassStudentIds.add(a.ogrenciId);
          }
        } catch(e) {}
      }
    } else if (specialGroups.isNotEmpty) {
      // Kriterine göre sırala (Yüksekten düşüğe)
      final basariliOgrenciler = List<StudentNeedProfile>.from(ogrenciProfiller)
        ..sort((a, b) {
          if (specialClassCriteria == 'exam_score') {
            return b.examScore.compareTo(a.examScore);
          } else {
            final avgA = a.dersBasariOranlari.isEmpty ? 0.0 : a.dersBasariOranlari.values.fold(0.0, (sum, v) => sum + v) / a.dersBasariOranlari.length;
            final avgB = b.dersBasariOranlari.isEmpty ? 0.0 : b.dersBasariOranlari.values.fold(0.0, (sum, v) => sum + v) / b.dersBasariOranlari.length;
            return avgB.compareTo(avgA);
          }
        });

      final capacity = specialGroups.first.kapasite;
      final topStudents = basariliOgrenciler.take(capacity).toList();
      for (final profil in topStudents) {
        final ogrenciId = profil.ogrenciId;
        specialClassStudentIds.add(ogrenciId);
        ogrenciDoluSlot.putIfAbsent(ogrenciId, () => {});
        ogrenciSaatSayisi.putIfAbsent(ogrenciId, () => 0);

        for (final g in specialGroups) {
          final studentAvg = profil.dersBasariOranlari.isEmpty ? 0.0 : profil.dersBasariOranlari.values.fold(0.0, (sum, v) => sum + v) / profil.dersBasariOranlari.length;
          atamalar.add(CampAssignment(
            id: '${cycleId}_${ogrenciId}_${g.id}',
            cycleId: cycleId,
            institutionId: institutionId,
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
        // Özel sınıfa atanmış öğrenciler normal branş gruplarına atanmaz
        if (specialClassStudentIds.contains(ogrenciId)) continue;

        ogrenciDoluSlot.putIfAbsent(ogrenciId, () => {});
        ogrenciSaatSayisi.putIfAbsent(ogrenciId, () => 0);
        yerlesmemeNedenleri.putIfAbsent(ogrenciId, () => []);

        final ogrenciGecmis = workingGecmisKatilimlar.putIfAbsent(ogrenciId, () => {});
        
        final siraliDersler = profil.dersIhtiyaclari.entries.toList()..sort((a, b) {
          if (dersBazliAktif) {
            // Ders bazlı modda henüz hedefine ulaşmamış ve en az atanmış derse öncelik ver
            final countA = ogrenciDersSayisi[ogrenciId]?[a.key] ?? 0;
            final countB = ogrenciDersSayisi[ogrenciId]?[b.key] ?? 0;
            final minA = dersBazliSaatSinirlari[a.key]?['min'] ?? 0;
            final minB = dersBazliSaatSinirlari[b.key]?['min'] ?? 0;
            final needA = minA - countA;
            final needB = minB - countB;
            if (needA != needB) return needB.compareTo(needA); // İhtiyacı çok olan ders önce
          }

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

          // Ders bazlı saat sınırı aktifken başarı filtresi devre dışı
          if (!dersBazliAktif && sadeceDusukBasari && basariOrani > esik) continue;

          if (haftalikMaksimumSaat != null && ogrenciSaatSayisi[ogrenciId]! >= haftalikMaksimumSaat!) {
            yerlesmemeNedenleri[ogrenciId]!.add('$dersId: Maksimum saat limitine takıldı.');
            continue;
          }

          // Ders bazlı maksimum saat kontrolü
          final maxSaat = dersBazliSaatSinirlari[dersId]?['max'];
          if (maxSaat != null && (ogrenciDersSayisi[ogrenciId]?[dersId] ?? 0) >= maxSaat) {
            continue; // Bu ders için max'a ulaştı, sessizce sonraki derse geç
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
            grupBasarilari: grupBasarilari,
            disabledGroupIds: disabledGroupIds,
          );

          if (findResult.group != null) {
            final g = findResult.group!;
            atamalar.add(CampAssignment(
              id: '${cycleId}_${ogrenciId}_${g.id}',
              cycleId: cycleId,
              institutionId: institutionId,
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
            ogrenciDersSayisi.putIfAbsent(ogrenciId, () => {})[dersId] = (ogrenciDersSayisi[ogrenciId]?[dersId] ?? 0) + 1;
            grupBasarilari.putIfAbsent(g.id, () => []).add(basariOrani);
            
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

    // ═══ DERS BAZLI MİNİMUM SAAT ZORLAMA PASS'I ═══
    if (dersBazliAktif && dersBazliZorlaAtama) {
      final allNonSpecialGroups = gruplar.where((g) => !g.isSpecial && !disabledGroupIds.contains(g.id)).toList();
      for (final profil in ogrenciProfiller) {
        final ogrenciId = profil.ogrenciId;
        // Özel sınıfa atanmış öğrenciler minimum saat zorlama pass'ından muaf tutulur
        if (specialClassStudentIds.contains(ogrenciId)) continue;

        ogrenciDoluSlot.putIfAbsent(ogrenciId, () => {});
        ogrenciSaatSayisi.putIfAbsent(ogrenciId, () => 0);
        ogrenciDersSayisi.putIfAbsent(ogrenciId, () => {});
        yerlesmemeNedenleri.putIfAbsent(ogrenciId, () => []);

        for (final entry in dersBazliSaatSinirlari.entries) {
          final dersId = entry.key;
          final minSaat = entry.value['min'] ?? 0;
          final maxSaat = entry.value['max'];
          final atanmis = ogrenciDersSayisi[ogrenciId]?[dersId] ?? 0;

          if (atanmis >= minSaat) continue; // Minimum zaten dolu

          // Eksik olan saatleri doldurmaya çalış
          final ihtiyac = minSaat - atanmis;
          for (int i = 0; i < ihtiyac; i++) {
            if (haftalikMaksimumSaat != null && ogrenciSaatSayisi[ogrenciId]! >= haftalikMaksimumSaat!) break;
            if (maxSaat != null && (ogrenciDersSayisi[ogrenciId]?[dersId] ?? 0) >= maxSaat) break;

            final basariOrani = profil.dersBasariOranlari[dersId] ?? 0.0;
            var findResult = _findBestGroup(
              dersId: dersId,
              ogrenciBasariOrani: basariOrani,
              ogrenciDoluSlot: ogrenciDoluSlot[ogrenciId]!,
              gruplar: allNonSpecialGroups,
              grupMevcut: grupMevcut,
              grupTargetValues: grupTargetValue,
              ogrenciKazanimlar: profil.kazanimIhtiyaclari[dersId] ?? {},
              grupKazanimFrekanslari: grupKazanimFrekanslari,
              grupBasarilari: grupBasarilari,
              disabledGroupIds: disabledGroupIds,
            );

            // ── AKILLI SLOT SWAP (Yer Değiştirerek Yer Açma) ──
            // Eğer doğrudan boş grup bulunamadıysa ama öğrencinin başka saatte kaydırılabilecek dersi varsa:
            if (findResult.group == null) {
              final studentAssigns = atamalar.where((a) => a.ogrenciId == ogrenciId && !specialClassStudentIds.contains(a.ogrenciId)).toList();
              for (final existingA in studentAssigns) {
                final existingG = allNonSpecialGroups.firstWhere((g) => g.id == existingA.groupId, orElse: () => allNonSpecialGroups.first);
                // Bu ders için öğrencinin boş olduğu BAŞKA bir saat diliminde alternatif açık grup var mı?
                final alternativeGroups = allNonSpecialGroups.where((altG) =>
                  altG.id != existingG.id &&
                  altG.dersId == existingG.dersId &&
                  altG.saatDilimiId != existingG.saatDilimiId &&
                  !ogrenciDoluSlot[ogrenciId]!.contains(altG.saatDilimiId) &&
                  (grupMevcut[altG.id] ?? 0) < altG.kapasite
                ).toList();

                if (alternativeGroups.isNotEmpty) {
                  final altG = alternativeGroups.first;
                  // Geçici olarak mevcut dersi kaydıralım
                  ogrenciDoluSlot[ogrenciId]!.remove(existingG.saatDilimiId);
                  ogrenciDoluSlot[ogrenciId]!.add(altG.saatDilimiId);

                  // Şimdi aradığımız eksik ders için bu boşalan saatte grup var mı kontrol edelim
                  final testFind = _findBestGroup(
                    dersId: dersId,
                    ogrenciBasariOrani: basariOrani,
                    ogrenciDoluSlot: ogrenciDoluSlot[ogrenciId]!,
                    gruplar: allNonSpecialGroups,
                    grupMevcut: grupMevcut,
                    grupTargetValues: grupTargetValue,
                    ogrenciKazanimlar: profil.kazanimIhtiyaclari[dersId] ?? {},
                    grupKazanimFrekanslari: grupKazanimFrekanslari,
                    grupBasarilari: grupBasarilari,
                    disabledGroupIds: disabledGroupIds,
                  );

                  if (testFind.group != null) {
                    // Başarılı swap! Eski atamayı güncelle
                    atamalar.remove(existingA);
                    grupMevcut[existingG.id] = (grupMevcut[existingG.id] ?? 1) - 1;

                    atamalar.add(existingA.copyWith(
                      groupId: altG.id,
                      groupName: '${altG.dersId} - ${altG.ogretmenAdi}',
                    ));
                    grupMevcut[altG.id] = (grupMevcut[altG.id] ?? 0) + 1;

                    findResult = testFind;
                    break;
                  } else {
                    // Geri al
                    ogrenciDoluSlot[ogrenciId]!.remove(altG.saatDilimiId);
                    ogrenciDoluSlot[ogrenciId]!.add(existingG.saatDilimiId);
                  }
                }
              }
            }

            if (findResult.group != null) {
              final g = findResult.group!;
              atamalar.add(CampAssignment(
                id: '${cycleId}_${ogrenciId}_${g.id}_minforce',
                cycleId: cycleId,
                institutionId: institutionId,
                groupId: g.id,
                groupName: '${g.dersId} - ${g.ogretmenAdi}',
                ogrenciId: ogrenciId,
                ogrenciAdi: profil.ogrenciAdi,
                sube: profil.subeAdi,
                subeId: profil.subeId,
                atamaTipi: CampAssignmentType.auto,
                basariOrani: basariOrani,
                ihtiyacSkoru: 0.0,
              ));
              ogrenciDoluSlot[ogrenciId]!.add(g.saatDilimiId);
              grupMevcut[g.id] = (grupMevcut[g.id] ?? 0) + 1;
              ogrenciSaatSayisi[ogrenciId] = (ogrenciSaatSayisi[ogrenciId] ?? 0) + 1;
              ogrenciDersSayisi[ogrenciId]![dersId] = (ogrenciDersSayisi[ogrenciId]![dersId] ?? 0) + 1;
              grupBasarilari.putIfAbsent(g.id, () => []).add(basariOrani);
            } else {
              yerlesmemeNedenleri[ogrenciId]!.add('$dersId: Min. saat zorlamasında uygun grup bulunamadı (${findResult.reason})');
              break; // Bu ders için daha fazla denemeye gerek yok
            }
          }
        }
      }
    }

    final List<String> eksikAtananIds = [];
    for (final profil in ogrenciProfiller) {
      // Özel sınıfa yerleştirilmiş öğrenciler eksik veya yerleşmeyen sayılamaz
      if (specialClassStudentIds.contains(profil.ogrenciId)) continue;

      final atananSayisi = atamalar.where((a) => a.ogrenciId == profil.ogrenciId).length;
      if (atananSayisi == 0) {
        yerlesmeyenIds.add(profil.ogrenciId);
      } else if (_minimumDersSayisi != null && atananSayisi < _minimumDersSayisi!) {
        eksikAtananIds.add(profil.ogrenciId);
      }
      // Ders bazlı minimum saat kontrolü
      if (dersBazliAktif && atananSayisi > 0) {
        final dersAtamalari = ogrenciDersSayisi[profil.ogrenciId] ?? {};
        for (final entry in dersBazliSaatSinirlari.entries) {
          final minSaat = entry.value['min'] ?? 0;
          final atanmis = dersAtamalari[entry.key] ?? 0;
          if (atanmis < minSaat) {
            if (!eksikAtananIds.contains(profil.ogrenciId)) eksikAtananIds.add(profil.ogrenciId);
            yerlesmemeNedenleri.putIfAbsent(profil.ogrenciId, () => []).add(
              '${entry.key}: Minimum $minSaat saat gerekli, $atanmis saat atandı.'
            );
          }
        }
      }
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
      if (highSuccessSoruCozumActive && !g.isSpecial) {
         final basarilar = grupBasarilari[g.id] ?? [];
         final avgSuccess = basarilar.isEmpty ? 0.0 : basarilar.reduce((a, b) => a + b) / basarilar.length;
         if (avgSuccess >= highSuccessSoruCozumThreshold && basarilar.isNotEmpty) {
            return g.copyWith(mevcutOgrenciSayisi: grupMevcut[g.id] ?? 0, kazanimlar: ['Soru Çözüm']);
         }
      }

      var frekanslar = grupKazanimFrekanslari[g.id] ?? {};
      
      // FALLBACK: Eğer bu grupta hiç kazanım birikmemişse, dersin genel en sık konularını al
      if (frekanslar.isEmpty && !g.isSpecial) {
        frekanslar = subjectGlobalFrequencies[g.dersId] ?? subjectGlobalFrequencies[g.dersAdi] ?? {};
      }

      final siraliKazanimlar = frekanslar.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final top3 = siraliKazanimlar.take(3).map((e) => e.key).toList();
      return g.copyWith(mevcutOgrenciSayisi: grupMevcut[g.id] ?? 0, kazanimlar: top3);
    }).toList();

    // 4. FALLBACK: Soru Çözüm Sınıflarına Boşta Kalanları Ata
    if (highSuccessSoruCozumActive) {
      final soruCozumGruplari = updatedGroups.where((g) => g.kazanimlar.contains('Soru Çözüm')).toList();
      if (soruCozumGruplari.isNotEmpty) {
        final List<String> toRemoveFromYerlesmeyen = [];
        final List<String> toRemoveFromEksik = [];
        
        final checkList = [...yerlesmeyenIds, ...eksikAtananIds].toSet().toList();
        
        for (final ogrenciId in checkList) {
          final profil = ogrenciProfiller.firstWhere((p) => p.ogrenciId == ogrenciId);
          
          for (final g in soruCozumGruplari) {
            if (haftalikMaksimumSaat != null && (ogrenciSaatSayisi[ogrenciId] ?? 0) >= haftalikMaksimumSaat!) break;
            
            if (grupMevcut[g.id]! < g.kapasite) {
              if (!ogrenciDoluSlot[ogrenciId]!.contains(g.saatDilimiId)) {
                atamalar.add(CampAssignment(
                  id: '${cycleId}_${ogrenciId}_${g.id}_fallback',
                  cycleId: cycleId,
                  institutionId: institutionId,
                  groupId: g.id,
                  groupName: '${g.dersId} - ${g.ogretmenAdi}',
                  ogrenciId: ogrenciId,
                  ogrenciAdi: profil.ogrenciAdi,
                  sube: profil.subeAdi,
                  subeId: profil.subeId,
                  atamaTipi: CampAssignmentType.auto,
                  basariOrani: profil.dersBasariOranlari[g.dersId] ?? 0.0,
                  ihtiyacSkoru: 0.0,
                ));
                ogrenciDoluSlot[ogrenciId]!.add(g.saatDilimiId);
                grupMevcut[g.id] = grupMevcut[g.id]! + 1;
                ogrenciSaatSayisi[ogrenciId] = (ogrenciSaatSayisi[ogrenciId] ?? 0) + 1;
                
                final index = updatedGroups.indexWhere((ug) => ug.id == g.id);
                if (index != -1) {
                  updatedGroups[index] = updatedGroups[index].copyWith(mevcutOgrenciSayisi: grupMevcut[g.id]!);
                }
                
                toRemoveFromYerlesmeyen.add(ogrenciId);
                if (_minimumDersSayisi != null && ogrenciSaatSayisi[ogrenciId]! >= _minimumDersSayisi!) {
                  toRemoveFromEksik.add(ogrenciId);
                }
              }
            }
          }
        }
        
        yerlesmeyenIds.removeWhere((id) => toRemoveFromYerlesmeyen.contains(id));
        eksikAtananIds.removeWhere((id) => toRemoveFromEksik.contains(id));
      }
    }

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
    required Map<String, List<double>> grupBasarilari,
    required Set<String> disabledGroupIds,
    bool strictSpread = true,
  }) {
    final uygunGruplar = gruplar.where((g) => 
      !disabledGroupIds.contains(g.id) &&
      (g.dersId == dersId || g.dersAdi == dersId) && 
      !ogrenciDoluSlot.contains(g.saatDilimiId) && 
      (grupMevcut[g.id] ?? 0) < g.kapasite
    ).toList();

    if (uygunGruplar.isEmpty) {
      final potential = gruplar.where((g) => !disabledGroupIds.contains(g.id) && (g.dersId == dersId || g.dersAdi == dersId)).toList();
      if (potential.isEmpty) return _FindResult(null, 'Bu ders için grup yok.');
      if (potential.every((g) => ogrenciDoluSlot.contains(g.saatDilimiId))) return _FindResult(null, 'Saat çakışması.');
      return _FindResult(null, 'Kapasite dolu.');
    }

    uygunGruplar.sort((a, b) {
      // 0. Homojenlik Kuralı: Grup içi min-max başarı farkı en fazla %50 olmalı!
      final scoresA = grupBasarilari[a.id] ?? [];
      final scoresB = grupBasarilari[b.id] ?? [];

      double spreadA = 0.0;
      if (scoresA.isNotEmpty) {
        double minA = scoresA.first;
        double maxA = scoresA.first;
        for (final s in scoresA) {
          if (s < minA) minA = s;
          if (s > maxA) maxA = s;
        }
        final newMinA = ogrenciBasariOrani < minA ? ogrenciBasariOrani : minA;
        final newMaxA = ogrenciBasariOrani > maxA ? ogrenciBasariOrani : maxA;
        spreadA = newMaxA - newMinA;
      }

      double spreadB = 0.0;
      if (scoresB.isNotEmpty) {
        double minB = scoresB.first;
        double maxB = scoresB.first;
        for (final s in scoresB) {
          if (s < minB) minB = s;
          if (s > maxB) maxB = s;
        }
        final newMinB = ogrenciBasariOrani < minB ? ogrenciBasariOrani : minB;
        final newMaxB = ogrenciBasariOrani > maxB ? ogrenciBasariOrani : maxB;
        spreadB = newMaxB - newMinB;
      }

      // %50 (0.50) üstü fark cezalandırılır, %60 (0.60) üstü uç farklar en sona atılır
      final aViolatesHard = spreadA > 0.60;
      final bViolatesHard = spreadB > 0.60;
      if (aViolatesHard != bViolatesHard) return aViolatesHard ? 1 : -1;

      final aViolatesSoft = spreadA > 0.50;
      final bViolatesSoft = spreadB > 0.50;
      if (aViolatesSoft != bViolatesSoft) return aViolatesSoft ? 1 : -1;

      // 1. Seviye Uyumu (Öğrencinin başarı yüzdesine en yakın seviye hedefli grup)
      final aTarget = grupTargetValues[a.id] ?? 0.5;
      final bTarget = grupTargetValues[b.id] ?? 0.5;
      final aDist = (aTarget - ogrenciBasariOrani).abs();
      final bDist = (bTarget - ogrenciBasariOrani).abs();
      if ((aDist - bDist).abs() > 0.05) return aDist.compareTo(bDist);

      // 2. Homojenlik Spread Karşılaştırması (Grup içi fark ne kadar azsa o kadar iyi)
      if ((spreadA - spreadB).abs() > 0.08) return spreadA.compareTo(spreadB);

      // 3. Kazanım Uyumu
      final aK = (grupKazanimFrekanslari[a.id] ?? {}).keys.toSet();
      final bK = (grupKazanimFrekanslari[b.id] ?? {}).keys.toSet();
      final aMatch = ogrenciKazanimlar.intersection(aK).length;
      final bMatch = ogrenciKazanimlar.intersection(bK).length;
      if (aMatch != bMatch) return bMatch.compareTo(aMatch);

      // 4. Doluluk Dengesi
      return (grupMevcut[a.id] ?? 0).compareTo(grupMevcut[b.id] ?? 0);
    });

    return _FindResult(uygunGruplar.first, '');
  }

  List<CampAssignment> generateSpecialClassOnly({
    required List<StudentNeedProfile> ogrenciProfiller,
    required List<CampGroup> gruplar,
    String specialClassCriteria = 'success_rate',
  }) {
    final specialGroups = gruplar.where((g) => g.isSpecial).toList();
    if (specialGroups.isEmpty) return [];

    final atamalar = <CampAssignment>[];
    final basariliOgrenciler = List<StudentNeedProfile>.from(ogrenciProfiller)
      ..sort((a, b) {
        if (specialClassCriteria == 'exam_score') {
          return b.examScore.compareTo(a.examScore);
        } else {
          final avgA = a.dersBasariOranlari.isEmpty ? 0.0 : a.dersBasariOranlari.values.fold(0.0, (sum, v) => sum + v) / a.dersBasariOranlari.length;
          final avgB = b.dersBasariOranlari.isEmpty ? 0.0 : b.dersBasariOranlari.values.fold(0.0, (sum, v) => sum + v) / b.dersBasariOranlari.length;
          return avgB.compareTo(avgA);
        }
      });

    final capacity = specialGroups.first.kapasite;
    final topStudents = basariliOgrenciler.take(capacity).toList(); // Özel sınıf için dinamik kota
    for (final profil in topStudents) {
      for (final g in specialGroups) {
        final studentAvg = profil.dersBasariOranlari.isEmpty ? 0.0 : profil.dersBasariOranlari.values.fold(0.0, (sum, v) => sum + v) / profil.dersBasariOranlari.length;
        atamalar.add(CampAssignment(
          id: '${cycleId}_${profil.ogrenciId}_${g.id}',
          cycleId: cycleId,
          institutionId: institutionId,
          groupId: g.id,
          groupName: g.dersAdi,
          ogrenciId: profil.ogrenciId,
          ogrenciAdi: profil.ogrenciAdi,
          sube: profil.subeAdi,
          subeId: profil.subeId,
          atamaTipi: CampAssignmentType.auto,
          basariOrani: studentAvg, 
          ihtiyacSkoru: 0.0,
        ));
      }
    }
    return atamalar;
  }
}


class _FindResult {
  final CampGroup? group;
  final String reason;
  _FindResult(this.group, this.reason);
}
