import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

class AutoScheduleResult {
  final int assignedCount;
  final int unassignedCount;
  final List<String> unassignedDetails;

  AutoScheduleResult({
    required this.assignedCount,
    required this.unassignedCount,
    required this.unassignedDetails,
  });
}

class AutoScheduleService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ═══════════════════════════════════════════════════════════════
  // ██  ANA DAĞİTİM FONKSİYONU
  // ═══════════════════════════════════════════════════════════════
  Future<AutoScheduleResult> distributeSchedule({
    required String periodId,
    required String institutionId,
    required String schoolTypeId,
    Map<String, List<int>>? lessonBlockPatterns,
    Map<String, bool>? lessonAllowSplit,
    Map<String, bool>? lessonAvoidFirstHour,
    Map<String, bool>? lessonAvoidLastHour,
    List<Map<String, dynamic>>? lessonClassMerges,
    Map<String, Set<String>>? closedSlots,
    Map<String, int>? teacherMaxDailyHours,
    Set<String>? lockedSlots,
  }) async {
    print('🤖 Otomatik Dağıtım Başlatılıyor (Gelişmiş Algoritma v2) — Dönem: $periodId');

    // ── 1. Dönem Yapılandırmasını Yükle ──────────────────────────
    final periodDoc = await _firestore.collection('workPeriods').doc(periodId).get();
    if (!periodDoc.exists) throw Exception('Period not found');

    final periodData = periodDoc.data()!;
    final lessonHoursData = periodData['lessonHours'] as Map<String, dynamic>?;
    if (lessonHoursData == null) throw Exception('No lesson hours defined for this period');

    final List<String> selectedDays = List<String>.from(lessonHoursData['selectedDays'] ?? []);
    if (selectedDays.isEmpty) throw Exception('No selected days in period');

    final Map<String, int> dailyCounts = {};
    if (lessonHoursData['dailyLessonCounts'] != null) {
      final counts = lessonHoursData['dailyLessonCounts'] as Map<String, dynamic>;
      counts.forEach((k, v) {
        dailyCounts[k] = v is int ? v : int.tryParse(v.toString()) ?? 0;
      });
    }

    // ── 2. Mevcut Kilitli / Manuel Kayıtları Yükle ────────────────
    final existingSnap = await _firestore
        .collection('classSchedules')
        .where('periodId', isEqualTo: periodId)
        .where('institutionId', isEqualTo: institutionId)
        .get();

    final List<Map<String, dynamic>> allExisting =
        existingSnap.docs.map((d) => d.data()).toList();

    // Sadece kilitli olanları sabit tut (eğer kilitli tanımlanmışsa)
    final List<Map<String, dynamic>> existingSchedule;
    if (lockedSlots != null && lockedSlots.isNotEmpty) {
      existingSchedule = allExisting.where((entry) {
        final key = '${entry['classId']}_${entry['day']}_${entry['hourIndex']}';
        return lockedSlots.contains(key);
      }).toList();
      print('🔒 ${existingSchedule.length} kilitli ders tespit edildi ve korunuyor');
    } else {
      existingSchedule = [];
      print('📌 Kilitli ders yok, sıfırdan tam dağıtım yapılıyor');
    }

    // ── 3. Ders Atamalarını Yükle ────────────────────────────────
    final termId = periodData['termId'] as String?;
    var assignmentsQuery = _firestore
        .collection('lessonAssignments')
        .where('institutionId', isEqualTo: institutionId)
        .where('schoolTypeId', isEqualTo: schoolTypeId)
        .where('isActive', isEqualTo: true);

    if (termId != null && termId.isNotEmpty) {
      assignmentsQuery = assignmentsQuery.where('termId', isEqualTo: termId);
    }

    final assignmentsSnap = await assignmentsQuery.get();
    final rawAssignments = assignmentsSnap.docs.map((d) => d.data()).toList();
    print('📚 Veritabanından ${rawAssignments.length} atama bulundu');

    // Tekrarlanan atamaları temizle
    final Map<String, Map<String, dynamic>> uniqueAssignmentMap = {};
    for (var a in rawAssignments) {
      final classId = (a['classId'] ?? '').toString();
      final lessonId = (a['lessonId'] ?? '').toString();
      final tIds = (a['teacherIds'] as List?)?.map((e) => e.toString()).join(',') ??
          (a['teacherId'] ?? '').toString();
      final key = '$classId|$lessonId|$tIds';
      if (!uniqueAssignmentMap.containsKey(key)) {
        uniqueAssignmentMap[key] = a;
      }
    }

    final assignments = uniqueAssignmentMap.values.toList();
    print('📚 ${assignments.length} benzersiz atama dağıtılacak');

    // Birleştirilmiş ders kontrolü
    bool isMergedAssignment(Map<String, dynamic> a) {
      if (lessonClassMerges == null || lessonClassMerges.isEmpty) return false;
      final cId = (a['classId'] ?? '').toString();
      final lName = (a['lessonName'] as String? ?? '').trim().toLowerCase();
      for (var merge in lessonClassMerges) {
        final mLessonName = (merge['lessonName'] as String? ?? '').trim().toLowerCase();
        final mClasses = List<String>.from(merge['classIds'] ?? []);
        if (mLessonName == lName && mClasses.contains(cId)) return true;
      }
      return false;
    }

    // Sıralama: Birleştirilmişler önce, sonra haftalık saat yüksekliğine göre
    assignments.sort((a, b) {
      final bool mergedA = isMergedAssignment(a);
      final bool mergedB = isMergedAssignment(b);
      if (mergedA != mergedB) return mergedA ? -1 : 1;
      final hoursA = (a['weeklyHours'] as num?)?.toInt() ?? 0;
      final hoursB = (b['weeklyHours'] as num?)?.toInt() ?? 0;
      return hoursB.compareTo(hoursA);
    });

    // ── 4. Monte Carlo + Kalite Skorlu Simülasyon ────────────────
    //    Birden fazla dağıtım denemesi yapılır, her seferinde farklı
    //    sıralama ve rastgele faktörlerle. En az yerleştirilemeyen
    //    ders saati ve en yüksek dağıtım kalitesi olan sonuç seçilir.
    int maxAttempts = 500;
    List<Map<String, dynamic>>? bestSchedule;
    List<String>? bestUnassignedDetails;
    int bestUnassignedCount = 999999;
    int bestAssignedCount = 0;
    double bestQualityScore = -999999;

    print('🎲 $maxAttempts simülasyon çalıştırılıyor...');

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      final result = _runAttempt(
        assignments,
        existingSchedule,
        selectedDays,
        dailyCounts,
        periodId,
        institutionId,
        schoolTypeId,
        attempt,
        lessonBlockPatterns: lessonBlockPatterns,
        lessonAllowSplit: lessonAllowSplit,
        lessonAvoidFirstHour: lessonAvoidFirstHour,
        lessonAvoidLastHour: lessonAvoidLastHour,
        lessonClassMerges: lessonClassMerges,
        closedSlots: closedSlots,
        teacherMaxDailyHours: teacherMaxDailyHours,
        lockedSlots: lockedSlots,
      );

      if (result.unassignedCount < bestUnassignedCount ||
          (result.unassignedCount == bestUnassignedCount &&
              result.qualityScore > bestQualityScore)) {
        bestUnassignedCount = result.unassignedCount;
        bestAssignedCount = result.assignedCount;
        bestSchedule = result.schedule;
        bestUnassignedDetails = result.unassignedDetails;
        bestQualityScore = result.qualityScore;
        print('🏆 Yeni En İyi: Deneme $attempt - $bestUnassignedCount saat yerleştirilemedi (Kalite: ${bestQualityScore.toStringAsFixed(1)})');
      }

      // Mükemmel sonuç (0 yerleşemeyen) bulunduysa hiç bekleme, direkt bitir!
      if (bestUnassignedCount == 0) {
        print('🎯 0 yerleşemeyen ders bulundu (Deneme $attempt), anında tamamlanıyor!');
        break;
      }
    }

    print('🏆 En iyi sonuç: $bestUnassignedCount yerleştirilemeyen saat, '
        'kalite: ${bestQualityScore.toStringAsFixed(1)}');

    // ── 5. En İyi Sonucu Kaydet ──────────────────────────────────
    print('💾 ${bestSchedule!.length} kayıt kaydediliyor...');

    final oldRecords = await _firestore
        .collection('classSchedules')
        .where('periodId', isEqualTo: periodId)
        .where('institutionId', isEqualTo: institutionId)
        .get();

    List<WriteBatch> batches = [];
    WriteBatch currentBatch = _firestore.batch();
    int operationCount = 0;

    for (var doc in oldRecords.docs) {
      currentBatch.delete(doc.reference);
      operationCount++;
      if (operationCount >= 450) {
        batches.add(currentBatch);
        currentBatch = _firestore.batch();
        operationCount = 0;
      }
    }

    for (var data in bestSchedule) {
      final ref = _firestore.collection('classSchedules').doc();
      currentBatch.set(ref, data);
      operationCount++;
      if (operationCount >= 450) {
        batches.add(currentBatch);
        currentBatch = _firestore.batch();
        operationCount = 0;
      }
    }

    batches.add(currentBatch);
    await Future.wait(batches.map((batch) => batch.commit()));

    return AutoScheduleResult(
      assignedCount: bestAssignedCount,
      unassignedCount: bestUnassignedCount,
      unassignedDetails: bestUnassignedDetails ?? [],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ██  TEK SİMÜLASYON DENEMESİ
  // ═══════════════════════════════════════════════════════════════
  //
  //  TEMEL KURALLAR:
  //  1. allowSplit = false → Bloklar aynen yerleştirilir (3+3 = 2 blok)
  //     Her blok aynı gün ardışık saat olarak konulur.
  //
  //  2. allowSplit = true → Bloklar farklı GÜNLERE bölünebilir,
  //     ama gün İÇİNDE her zaman ARDIŞIK kalır.
  //     3+3 → 3+2+1 veya 2+2+2 olabilir ama 1.saat + 5.saat OLMAZ.
  //
  //  3. Aynı dersin blokları kesinlikle farklı günlere konur.
  //
  //  4. Akıllı gün seçimi: En az dolu güne öncelik verilir.
  //
  //  5. Akıllı slot seçimi: Boşluk bırakmadan sıkıştırma tercih edilir.
  //
  // ═══════════════════════════════════════════════════════════════
  _SimulationResult _runAttempt(
    List<Map<String, dynamic>> assignments,
    List<Map<String, dynamic>> existingSchedule,
    List<String> selectedDays,
    Map<String, int> dailyCounts,
    String periodId,
    String institutionId,
    String schoolTypeId,
    int attemptNumber, {
    Map<String, List<int>>? lessonBlockPatterns,
    Map<String, bool>? lessonAllowSplit,
    Map<String, bool>? lessonAvoidFirstHour,
    Map<String, bool>? lessonAvoidLastHour,
    List<Map<String, dynamic>>? lessonClassMerges,
    Map<String, Set<String>>? closedSlots,
    Map<String, int>? teacherMaxDailyHours,
    Set<String>? lockedSlots,
  }) {
    final random = Random();

    // ── Durum Haritaları ──────────────────────────────────────────
    final Map<String, Map<String, Set<int>>> teacherTimeline = {};
    final Map<String, Map<String, Set<int>>> classTimeline = {};
    final Map<String, Map<String, int>> teacherDailyHours = {};
    // Ders bazlı gün-slot takibi: "classId|lessonId" → day → [slotlar]
    final Map<String, Map<String, List<int>>> lessonDaySlots = {};

    // ── Yardımcı: Slot Dolu mu? ──────────────────────────────────
    bool isSlotOccupied(String type, String id, String day, int hour) {
      final timeline = type == 'teacher' ? teacherTimeline : classTimeline;
      return timeline[id]?[day]?.contains(hour) ?? false;
    }

    void markSlot(String type, String id, String day, int hour) {
      final timeline = type == 'teacher' ? teacherTimeline : classTimeline;
      timeline.putIfAbsent(id, () => {});
      timeline[id]!.putIfAbsent(day, () => <int>{});
      timeline[id]![day]!.add(hour);
    }

    // ── Yardımcı: Kapalı Slot mu? ────────────────────────────────
    bool isClosedSlot(
        List<String> teacherIds, List<String> classIds, String day, int hour) {
      if (closedSlots == null) return false;
      final slotKey = '${day}_$hour';
      for (var tId in teacherIds) {
        if (closedSlots['teacher_$tId']?.contains(slotKey) ?? false) return true;
      }
      for (var cId in classIds) {
        if (closedSlots['class_$cId']?.contains(slotKey) ?? false) return true;
      }
      return false;
    }

    // ── Yardımcı: Blok Yerleştirilebilir mi? ──────────────────────
    bool canPlaceBlock(
        int startHour,
        int blockSize,
        String day,
        int dayMax,
        List<String> mergedClassIds,
        List<String> teacherIds,
        bool avoidFirst,
        bool avoidLast) {
      if (startHour < 0 || startHour + blockSize > dayMax) return false;
      if (avoidFirst && startHour == 0) return false;
      if (avoidLast && startHour + blockSize == dayMax) return false;

      for (int b = 0; b < blockSize; b++) {
        final slot = startHour + b;
        for (var mCId in mergedClassIds) {
          if (isSlotOccupied('class', mCId, day, slot)) return false;
        }
        for (var tId in teacherIds) {
          if (isSlotOccupied('teacher', tId, day, slot)) return false;
        }
        if (isClosedSlot(teacherIds, mergedClassIds, day, slot)) return false;
      }
      return true;
    }

    // ── Yardımcı: Slot Kalite Skoru (yüksek=iyi) ─────────────────
    double scoreSlot(
        int startHour, int blockSize, String day, int dayMax, String classId) {
      double score = 0;

      // Mevcut derslere bitişik → sıkıştırma bonus
      if (startHour > 0 && isSlotOccupied('class', classId, day, startHour - 1)) {
        score += 15;
      }
      if (startHour + blockSize < dayMax &&
          isSlotOccupied('class', classId, day, startHour + blockSize)) {
        score += 15;
      }

      // Erken saatleri hafifçe tercih et (üstten doldur)
      score -= startHour * 0.3;

      return score;
    }

    // ── Yardımcı: Gün Kalite Skoru (yüksek=iyi) ──────────────────
    double scoreDay(String day, String primaryClassId, List<String> teacherIds,
        Set<String> usedDaysForLesson) {
      double score = 0;

      // ★ Bu ders bu güne henüz konmamış → GÜÇLÜ tercih
      if (!usedDaysForLesson.contains(day)) {
        score += 1000;
      }

      // Daha az dolu gün → dengeli dağıtım
      final classHours = classTimeline[primaryClassId]?[day]?.length ?? 0;
      score -= classHours * 5;

      // Öğretmen yükü daha az olan gün → dengeli
      for (var tId in teacherIds) {
        final tHours = teacherDailyHours[tId]?[day] ?? 0;
        score -= tHours * 3;
      }

      // Rastgele faktör (Monte Carlo çeşitliliği)
      score += random.nextDouble() * 8;

      return score;
    }

    // ── Kayıt Konteynerleri ──────────────────────────────────────
    final List<Map<String, dynamic>> newScheduleRecords = [];
    int assignedCount = 0;
    final Map<String, int> unassignedHoursMap = {};

    // ── 1) Mevcut Manuel Atamaları İşle ──────────────────────────
    final Map<String, int> alreadyPlacedHours = {};
    final Map<String, Set<String>> lessonUsedDays = {};

    for (var rec in existingSchedule) {
      final cId = (rec['classId'] ?? '').toString();
      final day = (rec['day'] ?? '').toString();
      final hourIndex = rec['hourIndex'] is int
          ? rec['hourIndex'] as int
          : int.tryParse(rec['hourIndex'].toString()) ?? 0;
      final tId = rec['teacherId']?.toString();
      final tIds = (rec['teacherIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          (tId != null ? [tId] : <String>[]);

      markSlot('class', cId, day, hourIndex);
      for (var t in tIds) {
        if (!isSlotOccupied('teacher', t, day, hourIndex)) {
          markSlot('teacher', t, day, hourIndex);
          teacherDailyHours.putIfAbsent(t, () => {});
          teacherDailyHours[t]![day] = (teacherDailyHours[t]![day] ?? 0) + 1;
        }
      }

      final lId = (rec['lessonId'] ?? '').toString();
      final lName = (rec['lessonName'] ?? '').toString().trim().toLowerCase();
      alreadyPlacedHours['$cId|$lId'] =
          (alreadyPlacedHours['$cId|$lId'] ?? 0) + 1;
      alreadyPlacedHours['$cId|$lName'] =
          (alreadyPlacedHours['$cId|$lName'] ?? 0) + 1;

      // Gün takibi
      final dayTrackKey = '$cId|$lId';
      lessonUsedDays.putIfAbsent(dayTrackKey, () => <String>{});
      lessonUsedDays[dayTrackKey]!.add(day);

      // Slot takibi (gün içi ardışıklık kontrolü için)
      lessonDaySlots.putIfAbsent(dayTrackKey, () => {});
      lessonDaySlots[dayTrackKey]!.putIfAbsent(day, () => []);
      lessonDaySlots[dayTrackKey]![day]!.add(hourIndex);

      newScheduleRecords.add(Map<String, dynamic>.from(rec));
      assignedCount++;
    }

    // ── 2) Monte Carlo Çeşitliliği İçin Sıralama ────────────────
    final shuffled = List<Map<String, dynamic>>.from(assignments);

    if (attemptNumber > 1) {
      // Birleştirilmiş ve normal atamaları ayır
      bool checkMerged(Map<String, dynamic> a) {
        if (lessonClassMerges == null || lessonClassMerges.isEmpty) return false;
        final cId = (a['classId'] ?? '').toString();
        final lName = (a['lessonName'] as String? ?? '').trim().toLowerCase();
        for (var merge in lessonClassMerges) {
          final mLessonName =
              (merge['lessonName'] as String? ?? '').trim().toLowerCase();
          final mClasses = List<String>.from(merge['classIds'] ?? []);
          if (mLessonName == lName && mClasses.contains(cId)) return true;
        }
        return false;
      }

      final merged = shuffled.where((a) => checkMerged(a)).toList();
      final nonMerged = shuffled.where((a) => !checkMerged(a)).toList();

      // Gürültülü sıralama → farklı denemeler farklı sonuçlar verir
      merged.sort((a, b) {
        final ha = (a['weeklyHours'] as num?)?.toInt() ?? 0;
        final hb = (b['weeklyHours'] as num?)?.toInt() ?? 0;
        return (hb + random.nextInt(4)).compareTo(ha + random.nextInt(4));
      });
      nonMerged.sort((a, b) {
        final ha = (a['weeklyHours'] as num?)?.toInt() ?? 0;
        final hb = (b['weeklyHours'] as num?)?.toInt() ?? 0;
        return (hb + random.nextInt(4)).compareTo(ha + random.nextInt(4));
      });

      shuffled
        ..clear()
        ..addAll(merged)
        ..addAll(nonMerged);
    }

    // ── 3) Her Atamayı İşle ──────────────────────────────────────
    final Set<String> processedMergedAssignments = {};

    for (var assignment in shuffled) {
      final classId = assignment['classId'] as String;
      final lessonId = assignment['lessonId'] as String;
      final lessonName =
          (assignment['lessonName'] as String? ?? 'Unknown').trim();
      final className = assignment['className'] as String? ?? 'Unknown';
      final totalWeeklyHours =
          (assignment['weeklyHours'] as num?)?.toInt() ?? 0;

      // Kalan saat hesapla
      final placedSoFar = max(
        alreadyPlacedHours['$classId|$lessonId'] ?? 0,
        alreadyPlacedHours['$classId|${lessonName.toLowerCase()}'] ?? 0,
      );
      int remainingWeeklyHours = totalWeeklyHours - placedSoFar;
      if (remainingWeeklyHours <= 0) continue;

      // Öğretmen bilgisi
      String? teacherId;
      String? teacherName;
      List<String> teacherIds = [];
      if (assignment['teacherIds'] != null &&
          (assignment['teacherIds'] as List).isNotEmpty) {
        teacherIds = (assignment['teacherIds'] as List)
            .map((e) => e.toString())
            .toList();
        teacherId = teacherIds.first;
        teacherName = assignment['teacherNames']?[0];
      } else {
        teacherId = assignment['teacherId'];
        teacherName = assignment['teacherName'];
        if (teacherId != null) teacherIds = [teacherId];
      }

      // Birleştirme bilgisi
      List<String> mergedClassIds = [classId];
      if (lessonClassMerges != null) {
        for (var merge in lessonClassMerges) {
          final mLessonName =
              (merge['lessonName'] as String? ?? '').trim().toLowerCase();
          final mClasses = List<String>.from(merge['classIds'] ?? []);
          if (mLessonName == lessonName.toLowerCase() &&
              mClasses.contains(classId)) {
            mergedClassIds = mClasses;
            break;
          }
        }
      }
      final bool isMerged = mergedClassIds.length > 1;
      final mergeProcessKey =
          '${lessonName.toLowerCase()}_${mergedClassIds.join('_')}';
      if (isMerged && processedMergedAssignments.contains(mergeProcessKey)) {
        continue;
      }

      // Ayarlar
      final patternKey = '${lessonName.toLowerCase()}|$totalWeeklyHours';
      final allowSplit = lessonAllowSplit?[patternKey] ??
          lessonAllowSplit?[lessonId] ??
          false;
      final avoidFirstHour = lessonAvoidFirstHour?[patternKey] ??
          lessonAvoidFirstHour?[lessonId] ??
          false;
      final avoidLastHour = lessonAvoidLastHour?[patternKey] ??
          lessonAvoidLastHour?[lessonId] ??
          false;

      // Blok deseni
      List<int> rawBlocks;
      bool hasExplicitPattern = false;
      if (lessonBlockPatterns != null &&
          (lessonBlockPatterns.containsKey(patternKey) ||
              lessonBlockPatterns.containsKey(lessonId))) {
        final raw =
            lessonBlockPatterns[patternKey] ?? lessonBlockPatterns[lessonId]!;
        rawBlocks = List.from(raw);
        hasExplicitPattern = true;
        int total = rawBlocks.fold(0, (s, b) => s + b);
        while (total > remainingWeeklyHours && rawBlocks.isNotEmpty) {
          rawBlocks.removeLast();
          total = rawBlocks.fold(0, (s, b) => s + b);
        }
        int remaining = remainingWeeklyHours - total;
        for (int r = 0; r < remaining; r++) {
          rawBlocks.add(1);
        }
      } else {
        rawBlocks = List.filled(remainingWeeklyHours, 1);
      }

      // Büyük bloklar önce
      rawBlocks.sort((a, b) => b.compareTo(a));

      // Günlük limit: Bu ders bir günde en fazla kaç saat olabilir?
      int dailyCap;
      if (hasExplicitPattern) {
        dailyCap = rawBlocks.isNotEmpty
            ? rawBlocks.reduce((a, b) => a > b ? a : b)
            : remainingWeeklyHours;
      } else {
        // Desen yoksa → makul bir günlük limit hesapla
        dailyCap = max(1, (remainingWeeklyHours / selectedDays.length).ceil());
      }

      // Bu ders+sınıf için kullanılmış günler
      final dayTrackKey = '$classId|$lessonId';
      Set<String> usedDays = Set.from(lessonUsedDays[dayTrackKey] ?? {});
      if (isMerged) {
        for (var mCId in mergedClassIds) {
          usedDays.addAll(lessonUsedDays['$mCId|$lessonId'] ?? {});
        }
      }

      int totalUnplaced = 0;

      // ────────────────────────────────────────────────────────────
      // ██  tryPlaceBlock: Ardışık bir bloğu en iyi güne/slota yerleştir
      // ────────────────────────────────────────────────────────────
      bool tryPlaceBlock(int blockSize) {
        // Aday günleri skorla ve sırala
        List<MapEntry<String, double>> dayCandidates = [];

        for (var day in selectedDays) {
          final dayMax = dailyCounts[day] ?? 0;
          if (dayMax < blockSize) continue;

          // Bu dersin bu günde zaten kaç saati var? dailyCap kontrolü
          final existingOnDay =
              lessonDaySlots[dayTrackKey]?[day]?.length ?? 0;
          if (existingOnDay + blockSize > dailyCap) continue;

          // Öğretmen günlük limit kontrolü
          bool limitExceeded = false;
          for (var tId in teacherIds) {
            final limit = teacherMaxDailyHours?[tId] ??
                (dayMax > 1 ? dayMax - 1 : dayMax);
            final currentDaily = teacherDailyHours[tId]?[day] ?? 0;
            if (currentDaily + blockSize > limit) {
              limitExceeded = true;
              break;
            }
          }
          if (limitExceeded) continue;

          final ds = scoreDay(day, classId, teacherIds, usedDays);
          dayCandidates.add(MapEntry(day, ds));
        }

        // En iyi günden başla
        dayCandidates.sort((a, b) => b.value.compareTo(a.value));

        for (var dayEntry in dayCandidates) {
          final day = dayEntry.key;
          final dayMax = dailyCounts[day] ?? 0;

          // ── Aday başlangıç pozisyonlarını belirle ──────────────
          List<int> candidateStarts;
          final existingSlots = lessonDaySlots[dayTrackKey]?[day];

          if (existingSlots != null && existingSlots.isNotEmpty) {
            // Bu ders bu günde zaten var → sadece bitişik uzatma
            final sortedSlots = List<int>.from(existingSlots)..sort();
            final minSlot = sortedSlots.first;
            final maxSlot = sortedSlots.last;
            candidateStarts = [];

            // Öncesine uzat
            final beforeStart = minSlot - blockSize;
            if (beforeStart >= 0) candidateStarts.add(beforeStart);

            // Sonrasına uzat
            final afterStart = maxSlot + 1;
            if (afterStart + blockSize <= dayMax) candidateStarts.add(afterStart);
          } else {
            // Yeni gün → tüm pozisyonları dene
            candidateStarts =
                List.generate(dayMax - blockSize + 1, (i) => i);
          }

          // ── Pozisyonları skorla ve filtrele ─────────────────────
          List<MapEntry<int, double>> slotCandidates = [];
          for (var h in candidateStarts) {
            if (!canPlaceBlock(h, blockSize, day, dayMax, mergedClassIds,
                teacherIds, avoidFirstHour, avoidLastHour)) {
              continue;
            }
            final ss = scoreSlot(h, blockSize, day, dayMax, classId) +
                random.nextDouble() * 2;
            slotCandidates.add(MapEntry(h, ss));
          }

          if (slotCandidates.isEmpty) continue;

          // En iyi slotu seç
          slotCandidates.sort((a, b) => b.value.compareTo(a.value));
          final bestStart = slotCandidates.first.key;

          // ── BLOĞU YERLEŞTİR ────────────────────────────────────
          for (int b = 0; b < blockSize; b++) {
            final slot = bestStart + b;
            for (var tId in teacherIds) {
              markSlot('teacher', tId, day, slot);
            }
            for (var mCId in mergedClassIds) {
              markSlot('class', mCId, day, slot);
              newScheduleRecords.add(<String, dynamic>{
                'classId': mCId,
                'className': mCId,
                'lessonId': lessonId,
                'lessonName': lessonName,
                'teacherId': teacherId,
                'teacherName': teacherName,
                'teacherIds': teacherIds,
                'day': day,
                'hourIndex': slot,
                'periodId': periodId,
                'institutionId': institutionId,
                'schoolTypeId': schoolTypeId,
                'isActive': true,
                'isMerged': isMerged,
                if (isMerged) 'mergedClassIds': mergedClassIds,
                'isAutoDistributed': true,
                'createdAt': FieldValue.serverTimestamp(),
              });
              assignedCount++;
            }

            // Slot takibini güncelle
            lessonDaySlots.putIfAbsent(dayTrackKey, () => {});
            lessonDaySlots[dayTrackKey]!.putIfAbsent(day, () => []);
            lessonDaySlots[dayTrackKey]![day]!.add(slot);
          }

          // Öğretmen günlük saatlerini güncelle
          for (var tId in teacherIds) {
            teacherDailyHours.putIfAbsent(tId, () => {});
            teacherDailyHours[tId]![day] =
                (teacherDailyHours[tId]![day] ?? 0) + blockSize;
          }

          // Kullanılmış gün takibi
          usedDays.add(day);
          lessonUsedDays.putIfAbsent(dayTrackKey, () => <String>{});
          lessonUsedDays[dayTrackKey]!.add(day);
          for (var mCId in mergedClassIds) {
            lessonUsedDays.putIfAbsent('$mCId|$lessonId', () => <String>{});
            lessonUsedDays['$mCId|$lessonId']!.add(day);
          }

          // Yerleştirilmiş saat takibi
          for (var mCId in mergedClassIds) {
            alreadyPlacedHours['$mCId|$lessonId'] =
                (alreadyPlacedHours['$mCId|$lessonId'] ?? 0) + blockSize;
            alreadyPlacedHours['$mCId|${lessonName.toLowerCase()}'] =
                (alreadyPlacedHours['$mCId|${lessonName.toLowerCase()}'] ??
                        0) +
                    blockSize;
          }

          return true; // Başarıyla yerleştirildi
        }

        return false; // Hiçbir gün/slot uygun değil
      }

      // ────────────────────────────────────────────────────────────
      // ██  YERLEŞTIRME MODU SEÇİMİ
      // ────────────────────────────────────────────────────────────

      if (!allowSplit) {
        // ═══════════════════════════════════════════════════════════
        // ██  KATI BLOK MODU
        // ──  Her blok olduğu gibi yerleştirilir.
        // ──  3+3 → bir güne 3 ardışık, başka güne 3 ardışık.
        // ──  Bölünemez. Sığmıyorsa → yerleştirilemedi.
        // ═══════════════════════════════════════════════════════════
        for (var blockSize in rawBlocks) {
          if (!tryPlaceBlock(blockSize)) {
            totalUnplaced += blockSize;
          }
        }
      } else {
        // ═══════════════════════════════════════════════════════════
        // ██  BÖLÜNEBİLİR BLOK MODU
        // ──  Önce orijinal bloklar denenır.
        // ──  Sığmıyorsa blok küçültülerek tekrar denenır.
        // ──  Gün içinde HER ZAMAN ardışık kalır.
        // ──  Bölme = günler ARASI bölme, gün içi DEĞİL.
        // ──
        // ──  Örnek: [3,3] → 3 sığmıyorsa → [2,1] olarak bölünür
        // ──           2 de sığmıyorsa → [1,1] olarak bölünür
        // ═══════════════════════════════════════════════════════════
        List<int> blockQueue = List.from(rawBlocks);
        blockQueue.sort((a, b) => b.compareTo(a));
        int maxIterations = remainingWeeklyHours * 4; // Güvenlik limiti
        int iterations = 0;

        while (blockQueue.isNotEmpty && iterations < maxIterations) {
          iterations++;
          int blockSize = blockQueue.removeAt(0);

          bool placed = tryPlaceBlock(blockSize);

          if (!placed && blockSize > 1) {
            // Blok sığmadı → küçült ve tekrar dene
            // [3] → [2, 1] olarak böl
            blockQueue.add(blockSize - 1);
            blockQueue.add(1);
            blockQueue.sort((a, b) => b.compareTo(a)); // Büyükler önce
          } else if (!placed) {
            // 1 saatlik blok bile sığmadı → gerçekten yerleştirilemedi
            totalUnplaced += 1;
          }
        }

        // Güvenlik: Kuyrukta kalan bloklar
        for (var b in blockQueue) {
          totalUnplaced += b;
        }
      }

      // Yerleştirilemeyen saatleri kaydet
      if (totalUnplaced > 0) {
        final reportKey =
            '$className - $lessonName [Öğretmen: ${teacherName ?? "Belirtilmemiş"}]';
        unassignedHoursMap[reportKey] =
            (unassignedHoursMap[reportKey] ?? 0) + totalUnplaced;
      }

      if (isMerged) processedMergedAssignments.add(mergeProcessKey);
    }

    // ── Yerleştirilemeyenleri raporla ─────────────────────────────
    final List<String> unassignedDetails = [];
    int totalUnassignedHours = 0;
    for (var entry in unassignedHoursMap.entries) {
      unassignedDetails.add('${entry.key} → ${entry.value} saat kaldı');
      totalUnassignedHours += entry.value;
    }

    // ── Kalite skoru hesapla ─────────────────────────────────────
    final qualityScore =
        _calculateQualityScore(newScheduleRecords, selectedDays, dailyCounts);

    return _SimulationResult(
      newScheduleRecords,
      unassignedDetails,
      totalUnassignedHours,
      assignedCount,
      qualityScore,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ██  KALİTE SKORU HESAPLAMA
  // ═══════════════════════════════════════════════════════════════
  //
  //  Daha yüksek skor = daha iyi dağıtım kalitesi.
  //  Kriterler:
  //   1. Sınıf günlük ders dengesi (günler arası eşit dağılım)
  //   2. Gün içi boşluk sayısı (az boşluk = iyi)
  //   3. Öğretmen günlük yük dengesi
  //   4. Derslerin farklı günlere yayılma oranı
  //
  // ═══════════════════════════════════════════════════════════════
  double _calculateQualityScore(
    List<Map<String, dynamic>> schedule,
    List<String> selectedDays,
    Map<String, int> dailyCounts,
  ) {
    double score = 100.0;

    // ── 1. Sınıf Günlük Denge ────────────────────────────────────
    final Map<String, Map<String, int>> classDaily = {};
    for (var rec in schedule) {
      final cId = (rec['classId'] ?? '').toString();
      final day = (rec['day'] ?? '').toString();
      classDaily.putIfAbsent(cId, () => {});
      classDaily[cId]![day] = (classDaily[cId]![day] ?? 0) + 1;
    }
    for (var entry in classDaily.entries) {
      final counts = selectedDays.map((d) => entry.value[d] ?? 0).toList();
      if (counts.isEmpty) continue;
      final mean = counts.fold(0, (s, c) => s + c) / counts.length;
      final variance = counts.fold(
              0.0, (double s, int c) => s + (c - mean) * (c - mean)) /
          counts.length;
      score -= sqrt(variance) * 2;
    }

    // ── 2. Gün İçi Boşluklar ────────────────────────────────────
    final Map<String, Map<String, Set<int>>> classSlots = {};
    for (var rec in schedule) {
      final cId = (rec['classId'] ?? '').toString();
      final day = (rec['day'] ?? '').toString();
      final hour = rec['hourIndex'] is int
          ? rec['hourIndex'] as int
          : int.tryParse(rec['hourIndex'].toString()) ?? 0;
      classSlots.putIfAbsent(cId, () => {});
      classSlots[cId]!.putIfAbsent(day, () => <int>{});
      classSlots[cId]![day]!.add(hour);
    }
    for (var cEntry in classSlots.entries) {
      for (var dayEntry in cEntry.value.entries) {
        final slots = dayEntry.value;
        if (slots.length < 2) continue;
        final minSlot = slots.reduce(min);
        final maxSlot = slots.reduce(max);
        final gaps = (maxSlot - minSlot + 1) - slots.length;
        score -= gaps * 3;
      }
    }

    // ── 3. Öğretmen Günlük Denge ─────────────────────────────────
    final Map<String, Map<String, int>> teacherDaily = {};
    for (var rec in schedule) {
      final tIds = (rec['teacherIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          (rec['teacherId'] != null
              ? [rec['teacherId'].toString()]
              : <String>[]);
      final day = (rec['day'] ?? '').toString();
      for (var tId in tIds) {
        teacherDaily.putIfAbsent(tId, () => {});
        teacherDaily[tId]![day] = (teacherDaily[tId]![day] ?? 0) + 1;
      }
    }
    for (var entry in teacherDaily.entries) {
      final counts = selectedDays.map((d) => entry.value[d] ?? 0).toList();
      if (counts.every((c) => c == 0)) continue;
      final mean = counts.fold(0, (s, c) => s + c) / counts.length;
      final variance = counts.fold(
              0.0, (double s, int c) => s + (c - mean) * (c - mean)) /
          counts.length;
      score -= sqrt(variance) * 1.5;
    }

    // ── 4. Ders Yayılma Bonusu ───────────────────────────────────
    final Map<String, Set<String>> lessonDays = {};
    for (var rec in schedule) {
      final key = '${rec['classId']}|${rec['lessonId']}';
      final day = (rec['day'] ?? '').toString();
      lessonDays.putIfAbsent(key, () => <String>{});
      lessonDays[key]!.add(day);
    }
    for (var entry in lessonDays.entries) {
      score += entry.value.length * 0.5;
    }

    return score;
  }
}

// ═══════════════════════════════════════════════════════════════
// Simülasyon Sonucu (İç Kullanım)
// ═══════════════════════════════════════════════════════════════
class _SimulationResult {
  final List<Map<String, dynamic>> schedule;
  final List<String> unassignedDetails;
  final int unassignedCount;
  final int assignedCount;
  final double qualityScore;

  _SimulationResult(
    this.schedule,
    this.unassignedDetails,
    this.unassignedCount,
    this.assignedCount,
    this.qualityScore,
  );
}
