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
  }) async {
    print('🤖 Starting Auto-Distribution (Monte Carlo) for Period: $periodId');

    // 1. Fetch Configuration & Data
    final periodDoc = await _firestore
        .collection('workPeriods')
        .doc(periodId)
        .get();
    if (!periodDoc.exists) throw Exception('Period not found');

    final periodData = periodDoc.data()!;
    final lessonHoursData = periodData['lessonHours'] as Map<String, dynamic>?;

    if (lessonHoursData == null)
      throw Exception('No lesson hours defined for this period');

    // Parse valid days and hours per day
    final List<String> selectedDays = List<String>.from(
      lessonHoursData['selectedDays'] ?? [],
    );
    if (selectedDays.isEmpty) throw Exception('No selected days in period');

    // dailyLessonCounts map: "Pazartesi": 8
    final Map<String, int> dailyCounts = {};
    if (lessonHoursData['dailyLessonCounts'] != null) {
      final counts =
          lessonHoursData['dailyLessonCounts'] as Map<String, dynamic>;
      counts.forEach((k, v) {
        dailyCounts[k] = v is int ? v : int.tryParse(v.toString()) ?? 0;
      });
    }

    // 2. Fetch Existing Placed/Manual Schedule Records to Preserve
    final existingSnap = await _firestore
        .collection('classSchedules')
        .where('periodId', isEqualTo: periodId)
        .where('institutionId', isEqualTo: institutionId)
        .get();

    final List<Map<String, dynamic>> existingSchedule =
        existingSnap.docs.map((d) => d.data()).toList();
    print('📌 Preserving ${existingSchedule.length} existing manual schedule records');

    // 3. Fetch Assignments
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
    print('📚 Found ${rawAssignments.length} raw assignments from database');

    // Deduplicate assignments by Class + Lesson + Teachers
    final Map<String, Map<String, dynamic>> uniqueAssignmentMap = {};
    for (var a in rawAssignments) {
      final classId = (a['classId'] ?? '').toString();
      final lessonId = (a['lessonId'] ?? '').toString();
      final tIds = (a['teacherIds'] as List?)?.map((e) => e.toString()).join(',') ?? (a['teacherId'] ?? '').toString();
      final key = '$classId|$lessonId|$tIds';

      if (!uniqueAssignmentMap.containsKey(key)) {
        uniqueAssignmentMap[key] = a;
      }
    }

    final assignments = uniqueAssignmentMap.values.toList();
    print('📚 Deduplicated to ${assignments.length} unique assignments to distribute');

    // Helper: Is this assignment merged with other classes?
    bool isMergedAssignment(Map<String, dynamic> a) {
      if (lessonClassMerges == null || lessonClassMerges.isEmpty) return false;
      final cId = (a['classId'] ?? '').toString();
      final lName = (a['lessonName'] as String? ?? '').trim().toLowerCase();
      for (var merge in lessonClassMerges) {
        final mLessonName = (merge['lessonName'] as String? ?? '').trim().toLowerCase();
        final mClasses = List<String>.from(merge['classIds'] ?? []);
        if (mLessonName == lName && mClasses.contains(cId)) {
          return true;
        }
      }
      return false;
    }

    // Sort assignments: MERGED LESSONS FIRST, then largest weeklyHours!
    assignments.sort((a, b) {
      final bool mergedA = isMergedAssignment(a);
      final bool mergedB = isMergedAssignment(b);
      if (mergedA != mergedB) {
        return mergedA ? -1 : 1;
      }
      final hoursA = (a['weeklyHours'] as num?)?.toInt() ?? 0;
      final hoursB = (b['weeklyHours'] as num?)?.toInt() ?? 0;
      return hoursB.compareTo(hoursA);
    });

    // Run Multiple Attempts
    int maxAttempts = 10;
    List<Map<String, dynamic>>? bestSchedule;
    List<String>? bestUnassignedDetails;
    int bestUnassignedCount = 999999;
    int bestAssignedCount = 0;

    print('🎲 Running $maxAttempts simulations (preserving manual entries, merged priority & teacher daily limits)...');

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      final result = _runAttempt(
        assignments,
        existingSchedule,
        selectedDays,
        dailyCounts,
        periodId,
        institutionId,
        schoolTypeId,
        lessonBlockPatterns: lessonBlockPatterns,
        lessonAllowSplit: lessonAllowSplit,
        lessonAvoidFirstHour: lessonAvoidFirstHour,
        lessonAvoidLastHour: lessonAvoidLastHour,
        lessonClassMerges: lessonClassMerges,
        closedSlots: closedSlots,
        teacherMaxDailyHours: teacherMaxDailyHours,
      );

      if (result.unassignedCount < bestUnassignedCount) {
        bestUnassignedCount = result.unassignedCount;
        bestAssignedCount = result.assignedCount;
        bestSchedule = result.schedule;
        bestUnassignedDetails = result.unassignedDetails;
      }

      if (bestUnassignedCount == 0) break;
    }

    print('🏆 Best result: $bestUnassignedCount unassigned lessons remaining.');

    // Save Best Result
    print('💾 Saving ${bestSchedule!.length} records...');

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

    for (var batch in batches) {
      await batch.commit();
    }

    return AutoScheduleResult(
      assignedCount: bestAssignedCount,
      unassignedCount: bestUnassignedCount,
      unassignedDetails: bestUnassignedDetails ?? [],
    );
  }

  _SimulationResult _runAttempt(
    List<Map<String, dynamic>> assignments,
    List<Map<String, dynamic>> existingSchedule,
    List<String> selectedDays,
    Map<String, int> dailyCounts,
    String periodId,
    String institutionId,
    String schoolTypeId, {
    Map<String, List<int>>? lessonBlockPatterns,
    Map<String, bool>? lessonAllowSplit,
    Map<String, bool>? lessonAvoidFirstHour,
    Map<String, bool>? lessonAvoidLastHour,
    List<Map<String, dynamic>>? lessonClassMerges,
    Map<String, Set<String>>? closedSlots,
    Map<String, int>? teacherMaxDailyHours,
  }) {
    // Local Timelines & Daily Hours Counters
    final Map<String, Map<String, Set<int>>> teacherTimeline = {};
    final Map<String, Map<String, Set<int>>> classTimeline = {};
    final Map<String, Map<String, int>> teacherDailyHours = {};

    bool isSlotOccupied(String type, String id, String day, int hour) {
      final timeline = type == 'teacher' ? teacherTimeline : classTimeline;
      if (!timeline.containsKey(id)) return false;
      if (!timeline[id]!.containsKey(day)) return false;
      return timeline[id]![day]!.contains(hour);
    }

    void markSlot(String type, String id, String day, int hour) {
      final timeline = type == 'teacher' ? teacherTimeline : classTimeline;
      if (!timeline.containsKey(id)) timeline[id] = {};
      if (!timeline[id]!.containsKey(day)) timeline[id]![day] = {};
      timeline[id]![day]!.add(hour);
    }

    bool isClosedSlot(String? teacherId, String classId, String day, int hour) {
      final slotKey = '${day}_$hour';
      if (teacherId != null && closedSlots != null) {
        final teacherClosed = closedSlots['teacher_$teacherId'];
        if (teacherClosed != null && teacherClosed.contains(slotKey)) return true;
      }
      if (closedSlots != null) {
        final classClosed = closedSlots['class_$classId'];
        if (classClosed != null && classClosed.contains(slotKey)) return true;
      }
      return false;
    }

    final List<Map<String, dynamic>> newScheduleRecords = [];
    final List<String> unassignedDetails = [];
    int assignedCount = 0;
    final random = Random();

    // 1) Mark Existing Manual Assignments into Timelines & Daily Counters
    final Map<String, int> alreadyPlacedHours = {};

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
          (tId != null ? [tId] : []);

      markSlot('class', cId, day, hourIndex);
      for (var t in tIds) {
        if (!isSlotOccupied('teacher', t, day, hourIndex)) {
          markSlot('teacher', t, day, hourIndex);
          teacherDailyHours[t] ??= {};
          teacherDailyHours[t]![day] = (teacherDailyHours[t]![day] ?? 0) + 1;
        }
      }

      final lId = (rec['lessonId'] ?? '').toString();
      final lName = (rec['lessonName'] ?? '').toString().trim().toLowerCase();
      alreadyPlacedHours['$cId|$lId'] = (alreadyPlacedHours['$cId|$lId'] ?? 0) + 1;
      alreadyPlacedHours['$cId|$lName'] = (alreadyPlacedHours['$cId|$lName'] ?? 0) + 1;

      newScheduleRecords.add(Map<String, dynamic>.from(rec));
      assignedCount++;
    }

    final Set<String> processedMergedAssignments = {};

    for (var assignment in assignments) {
      final classId = assignment['classId'] as String;
      final lessonId = assignment['lessonId'] as String;
      final lessonName = (assignment['lessonName'] as String? ?? 'Unknown').trim();
      final className = assignment['className'] as String? ?? 'Unknown';
      final totalWeeklyHours = (assignment['weeklyHours'] as num?)?.toInt() ?? 0;

      final placedSoFar = max(
        alreadyPlacedHours['$classId|$lessonId'] ?? 0,
        alreadyPlacedHours['$classId|${lessonName.toLowerCase()}'] ?? 0,
      );
      int remainingWeeklyHours = totalWeeklyHours - placedSoFar;
      if (remainingWeeklyHours <= 0) continue;

      String? teacherId;
      String? teacherName;
      List<String> teacherIds = [];
      if (assignment['teacherIds'] != null &&
          (assignment['teacherIds'] as List).isNotEmpty) {
        teacherIds = (assignment['teacherIds'] as List).map((e) => e.toString()).toList();
        teacherId = teacherIds.first;
        teacherName = assignment['teacherNames']?[0];
      } else {
        teacherId = assignment['teacherId'];
        teacherName = assignment['teacherName'];
        if (teacherId != null) teacherIds = [teacherId];
      }

      List<String> mergedClassIds = [classId];
      if (lessonClassMerges != null) {
        for (var merge in lessonClassMerges) {
          final mLessonName = (merge['lessonName'] as String? ?? '').trim().toLowerCase();
          final mClasses = List<String>.from(merge['classIds'] ?? []);
          if (mLessonName == lessonName.toLowerCase() && mClasses.contains(classId)) {
            mergedClassIds = mClasses;
            break;
          }
        }
      }
      final bool isMerged = mergedClassIds.length > 1;

      final mergeProcessKey = '${lessonName.toLowerCase()}_${mergedClassIds.join('_')}';
      if (isMerged && processedMergedAssignments.contains(mergeProcessKey)) {
        continue;
      }

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

      List<int> rawBlocks;
      if (lessonBlockPatterns != null &&
          (lessonBlockPatterns.containsKey(patternKey) ||
              lessonBlockPatterns.containsKey(lessonId))) {
        final raw = lessonBlockPatterns[patternKey] ??
            lessonBlockPatterns[lessonId]!;
        rawBlocks = List.from(raw);
        int total = rawBlocks.fold(0, (s, b) => s + b);
        while (total > remainingWeeklyHours && rawBlocks.isNotEmpty) {
          rawBlocks.removeLast();
          total = rawBlocks.fold(0, (s, b) => s + b);
        }
        int remaining = remainingWeeklyHours - total;
        for (int r = 0; r < remaining; r++) rawBlocks.add(1);
      } else {
        rawBlocks = List.filled(remainingWeeklyHours, 1);
      }

      int maxPossibleHours = 0;
      for (var c in dailyCounts.values)
        if (c > maxPossibleHours) maxPossibleHours = c;

      List<int> blocksToPlace = List.from(rawBlocks);

      // ---------------------------------------------------------------
      // Blok yerleştirme — iki mod:
      //
      // allowSplit = false (Katı Blok):
      //   Her blok aynı gün peş peşe yerleştirilmek ZORUNDA.
      //   3+3 → bir güne 3 ardışık saat, başka güne 3 ardışık saat.
      //
      // allowSplit = true (Dağıtılabilir Blok):
      //   Blok desenindeki en büyük blok = bir günde verilebilecek
      //   MAXIMUM ders saati. Saatler farklı günlere dağıtılabilir,
      //   ama hiçbir gün bu limiti geçemez.
      //   Örnek: 3+3 → Toplam 6 saat, max 3/gün → 2+1+3, 3+3, 1+2+3…
      // ---------------------------------------------------------------

      // Sınıf + ders için o gün kaç saat yerleştirildiği izleyici
      // (classTimeline'dan class/day bilgisi çekebiliriz)
      final Map<String, int> classDailyPlaced = {};
      // Önceden var olan kayıtları da say
      for (var rec in existingSchedule) {
        if ((rec['classId'] ?? '') == classId &&
            (rec['lessonId'] ?? '') == lessonId) {
          final d = rec['day']?.toString() ?? '';
          classDailyPlaced[d] = (classDailyPlaced[d] ?? 0) + 1;
        }
      }

      if (!allowSplit) {
        // ── KATİ BLOK modu ──────────────────────────────────────────
        while (blocksToPlace.isNotEmpty) {
          int blockSize = blocksToPlace.removeAt(0);
          bool placed = false;

          outerLoop:
          for (int h = 0; h <= maxPossibleHours - blockSize; h++) {
            if (avoidFirstHour && h == 0) continue;

            List<String> shuffledDays = List.from(selectedDays)..shuffle(random);

            for (var day in shuffledDays) {
              final dayMax = dailyCounts[day] ?? 0;
              if (h + blockSize > dayMax) continue;

              if (avoidLastHour && (h + blockSize == dayMax)) continue;

              // Öğretmen günlük limit
              bool limitExceeded = false;
              for (var tId in teacherIds) {
                final limit = teacherMaxDailyHours?[tId] ?? (dayMax > 1 ? dayMax - 1 : dayMax);
                final currentDaily = teacherDailyHours[tId]?[day] ?? 0;
                if (currentDaily + blockSize > limit) {
                  limitExceeded = true;
                  break;
                }
              }
              if (limitExceeded) continue;

              bool allFree = true;
              for (int b = 0; b < blockSize; b++) {
                final slot = h + b;
                for (var mCId in mergedClassIds) {
                  if (isSlotOccupied('class', mCId, day, slot)) { allFree = false; break; }
                  if (isClosedSlot(teacherId, mCId, day, slot)) { allFree = false; break; }
                }
                if (!allFree) break;
                for (var tId in teacherIds) {
                  if (isSlotOccupied('teacher', tId, day, slot)) { allFree = false; break; }
                }
                if (!allFree) break;
              }
              if (!allFree) continue;

              // Yerleştir
              for (int b = 0; b < blockSize; b++) {
                final slot = h + b;
                for (var tId in teacherIds) markSlot('teacher', tId, day, slot);
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
                classDailyPlaced[day] = (classDailyPlaced[day] ?? 0) + 1;
              }
              for (var tId in teacherIds) {
                teacherDailyHours[tId] ??= {};
                teacherDailyHours[tId]![day] = (teacherDailyHours[tId]![day] ?? 0) + blockSize;
              }
              placed = true;
              if (isMerged) processedMergedAssignments.add(mergeProcessKey);
              break outerLoop;
            }
          }

          if (!placed) {
            unassignedDetails.add(
              '$className - $lessonName ($blockSize saat blok) [Öğretmen: ${teacherName ?? "Belirtilmemiş"}] → Uygun ardışık slot bulunamadı',
            );
          }
        }
      } else {
        // ── DAĞITILABILIR BLOK modu ──────────────────────────────────
        // En büyük blok = günlük maksimum ders saati sınırı
        final int dailyCap = rawBlocks.isNotEmpty
            ? rawBlocks.reduce((a, b) => a > b ? a : b)
            : remainingWeeklyHours;

        // Kalan saatleri 1'er 1'er dağıt, ama günlük cap'e uy
        int hoursLeft = blocksToPlace.fold(0, (s, b) => s + b);

        while (hoursLeft > 0) {
          bool placed = false;

          List<String> shuffledDays = List.from(selectedDays)..shuffle(random);

          outerSplit:
          for (var day in shuffledDays) {
            final dayMax = dailyCounts[day] ?? 0;
            // Bu günde zaten kaç saat yerleşti?
            final placedToday = classDailyPlaced[day] ?? 0;
            if (placedToday >= dailyCap) continue; // Günlük cap doldu

            // Öğretmen günlük limit
            bool limitExceeded = false;
            for (var tId in teacherIds) {
              final limit = teacherMaxDailyHours?[tId] ?? (dayMax > 1 ? dayMax - 1 : dayMax);
              final currentDaily = teacherDailyHours[tId]?[day] ?? 0;
              if (currentDaily + 1 > limit) {
                limitExceeded = true;
                break;
              }
            }
            if (limitExceeded) continue;

            // Bu günde boş bir slot bul (1 saatlik)
            for (int h = 0; h < dayMax; h++) {
              if (avoidFirstHour && h == 0) continue;
              if (avoidLastHour && h == dayMax - 1) continue;

              bool slotFree = true;
              for (var mCId in mergedClassIds) {
                if (isSlotOccupied('class', mCId, day, h)) { slotFree = false; break; }
                if (isClosedSlot(teacherId, mCId, day, h)) { slotFree = false; break; }
              }
              if (!slotFree) continue;
              for (var tId in teacherIds) {
                if (isSlotOccupied('teacher', tId, day, h)) { slotFree = false; break; }
              }
              if (!slotFree) continue;

              // Yerleştir (1 saat)
              for (var tId in teacherIds) markSlot('teacher', tId, day, h);
              for (var mCId in mergedClassIds) {
                markSlot('class', mCId, day, h);
                newScheduleRecords.add(<String, dynamic>{
                  'classId': mCId,
                  'className': mCId,
                  'lessonId': lessonId,
                  'lessonName': lessonName,
                  'teacherId': teacherId,
                  'teacherName': teacherName,
                  'teacherIds': teacherIds,
                  'day': day,
                  'hourIndex': h,
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
              for (var tId in teacherIds) {
                teacherDailyHours[tId] ??= {};
                teacherDailyHours[tId]![day] = (teacherDailyHours[tId]![day] ?? 0) + 1;
              }
              classDailyPlaced[day] = (classDailyPlaced[day] ?? 0) + 1;

              hoursLeft--;
              placed = true;
              if (isMerged) processedMergedAssignments.add(mergeProcessKey);
              break outerSplit;
            }
          }

          if (!placed) {
            unassignedDetails.add(
              '$className - $lessonName ($hoursLeft saat kaldı, günlük max $dailyCap) [Öğretmen: ${teacherName ?? "Belirtilmemiş"}] → Uygun slot bulunamadı',
            );
            break;
          }
        }
      }
    }

    return _SimulationResult(
      newScheduleRecords,
      unassignedDetails,
      unassignedDetails.length,
      assignedCount,
    );
  }
}

class _SimulationResult {
  final List<Map<String, dynamic>> schedule;
  final List<String> unassignedDetails;
  final int unassignedCount;
  final int assignedCount;
  _SimulationResult(
    this.schedule,
    this.unassignedDetails,
    this.unassignedCount,
    this.assignedCount,
  );
}
