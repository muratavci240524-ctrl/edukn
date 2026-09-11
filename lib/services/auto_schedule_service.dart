import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

class AutoScheduleResult {
  final int assignedCount;
  final int unassignedCount;
  final List<String> unassignedDetails;
  final Map<String, String>? assignedHalfDays;
  final List<Map<String, dynamic>>? updatedTeacherMeetings;

  AutoScheduleResult({
    required this.assignedCount,
    required this.unassignedCount,
    required this.unassignedDetails,
    this.assignedHalfDays,
    this.updatedTeacherMeetings,
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
    Map<String, Map<int, int>>? lessonHourPreferences,
    List<Map<String, dynamic>>? lessonClassMerges,
    Map<String, Set<String>>? closedSlots,
    Map<String, int>? teacherMaxDailyHours,
    Set<String>? lockedSlots,
    Set<String>? halfDayFlexible,      // 'teacher_<id>_morning' veya '_afternoon'
    List<int>? halfDayMorningHours,
    List<int>? halfDayAfternoonHours,
    Map<String, String>? halfDayAssignedDays, // 'teacher_<id>_morning' -> 'Salı'
    List<Map<String, dynamic>>? teacherMeetings, // Zümre toplantıları
    Map<String, Set<String>>? lessonDayPreferences, // groupKey -> izin verilen günler
    String? targetClassId,
    String? targetTeacherId,
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

    final bool isPartial = (targetClassId != null && targetClassId.isNotEmpty) ||
        (targetTeacherId != null && targetTeacherId.isNotEmpty);

    // Sadece kilitli olanları sabit tut (eğer kilitli tanımlanmışsa veya kısmi dağıtımsa)
    final List<Map<String, dynamic>> existingSchedule;
    if (isPartial) {
      existingSchedule = allExisting.where((entry) {
        final key = '${entry['classId']}_${entry['day']}_${entry['hourIndex']}';
        final isLocked = lockedSlots != null && lockedSlots.contains(key);
        final isTargetClass = targetClassId != null && entry['classId'] == targetClassId;
        final isTargetTeacher = targetTeacherId != null &&
            (entry['teacherId'] == targetTeacherId ||
                (entry['teacherIds'] as List?)?.contains(targetTeacherId) == true);
        if (isLocked) return true;
        if (isTargetClass || isTargetTeacher) return false;
        return true;
      }).toList();
      print('🎯 Kısmi dağıtım: ${existingSchedule.length} mevcut ders korunuyor (hedef dışı ve kilitliler)');
    } else if (lockedSlots != null && lockedSlots.isNotEmpty) {
      existingSchedule = allExisting.where((entry) {
        final key = '${entry['classId']}_${entry['day']}_${entry['hourIndex']}';
        return lockedSlots.contains(key);
      }).toList();
      print('🔒 ${existingSchedule.length} kilitli ders tespit edildi ve korunuyor');
    } else {
      existingSchedule = [];
      print('📌 Kilitli ders yok, sıfırdan tam dağıtım yapılıyor');
    }

    // ── 2b. Kapalı Slotları Hazırla (Yarım Günler ve Zümreler Dahil) ──
    final effectiveClosed = closedSlots != null
        ? Map<String, Set<String>>.from(
            closedSlots.map((k, v) => MapEntry(k, Set<String>.from(v))),
          )
        : <String, Set<String>>{};

    final Map<String, String> calculatedHalfDays = {};
    if (halfDayAssignedDays != null) {
      calculatedHalfDays.addAll(halfDayAssignedDays);
    }

    // Sabit Yarım Gün İzinleri (halfDayAssignedDays)
    if (halfDayAssignedDays != null && halfDayAssignedDays.isNotEmpty) {
      for (final entry in halfDayAssignedDays.entries) {
        final flexKey = entry.key; // 'teacher_<id>_morning' veya '_afternoon'
        final assignedDay = entry.value;
        if (assignedDay.isEmpty) continue;

        final lastUnderscore = flexKey.lastIndexOf('_');
        if (lastUnderscore == -1) continue;
        final type = flexKey.substring(lastUnderscore + 1);
        final teacherKey = flexKey.substring(0, lastUnderscore); // 'teacher_<id>'
        if (type != 'morning' && type != 'afternoon') continue;

        // Eğer esnek olarak işaretlenmişse aşağıda dinamik seçilecek, sabitse ekle
        if (halfDayFlexible?.contains(flexKey) == true) continue;

        final hours = type == 'morning'
            ? (halfDayMorningHours ?? <int>[])
            : (halfDayAfternoonHours ?? <int>[]);
        if (hours.isEmpty) continue;

        for (final h in hours) {
          effectiveClosed.putIfAbsent(teacherKey, () => <String>{}).add('${assignedDay}_$h');
        }
        print('🔒 Sabit yarım gün kısıtı: $teacherKey → $type ($hours) → $assignedDay');
      }
    }

    // Esnek Yarım Gün: En Uygun Günü Hesapla ve Kapat
    if (halfDayFlexible != null &&
        halfDayFlexible.isNotEmpty &&
        (halfDayMorningHours?.isNotEmpty == true ||
            halfDayAfternoonHours?.isNotEmpty == true)) {
      int flexCounter = 0;
      for (final flexKey in halfDayFlexible) {
        final lastUnderscore = flexKey.lastIndexOf('_');
        if (lastUnderscore == -1) continue;
        final type = flexKey.substring(lastUnderscore + 1);
        final teacherKey = flexKey.substring(0, lastUnderscore);
        if (type != 'morning' && type != 'afternoon') continue;

        final hours = type == 'morning'
            ? (halfDayMorningHours ?? <int>[])
            : (halfDayAfternoonHours ?? <int>[]);
        if (hours.isEmpty) continue;

        final existing = effectiveClosed[teacherKey] ?? <String>{};

        // Günleri dengeli dağıt
        final preferredDayCandidate = selectedDays[flexCounter % selectedDays.length];
        flexCounter++;

        String bestDay = preferredDayCandidate;
        if (existing.any((s) => s.startsWith('${preferredDayCandidate}_'))) {
          int minClosed = 999;
          for (final day in selectedDays) {
            final closedCount = existing.where((s) => s.startsWith('${day}_')).length;
            if (closedCount < minClosed) {
              minClosed = closedCount;
              bestDay = day;
            }
          }
        }

        for (final h in hours) {
          effectiveClosed.putIfAbsent(teacherKey, () => <String>{}).add('${bestDay}_$h');
        }
        calculatedHalfDays[flexKey] = bestDay;
        print('🌱 Esnek yarım gün: $teacherKey → $type ($hours) → $bestDay');
      }
    }

    // ── 2d. Zümre Toplantıları (Sabit, Esnek Gün veya Esnek Saat) ───────────────
    final List<Map<String, dynamic>> calculatedMeetings = [];
    if (teacherMeetings != null && teacherMeetings.isNotEmpty) {
      for (final mtg in teacherMeetings) {
        final teacherIds = (mtg['teacherIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
        if (teacherIds.isEmpty) continue;
        final origStartH = (mtg['startHour'] as num?)?.toInt() ?? 0;
        final dur = (mtg['duration'] as num?)?.toInt() ?? 1;
        final isFlexDay = mtg['isFlexible'] == true || mtg['isFlexibleDay'] == true;
        final isFlexHour = mtg['isFlexibleHour'] == true;
        String day = (mtg['day'] ?? '').toString();
        int startH = origStartH;

        if (isFlexDay || isFlexHour || day.isEmpty) {
          final candidateDays = (isFlexDay || day.isEmpty) ? selectedDays : [day];
          int minTotalConflict = 999999;
          String bestDay = candidateDays.first;
          int bestHour = origStartH;

          for (final d in candidateDays) {
            final dayHourCount = dailyCounts[d] ?? 8;
            final maxStartH = (dayHourCount - dur).clamp(0, dayHourCount);

            final candidateHours = isFlexHour
                ? List.generate(maxStartH + 1, (i) => i)
                : [origStartH.clamp(0, maxStartH)];

            for (final h in candidateHours) {
              int conflictScore = 0;
              for (final tId in teacherIds) {
                final tKey = 'teacher_$tId';
                final tClosed = effectiveClosed[tKey] ?? <String>{};
                for (int slot = h; slot < h + dur; slot++) {
                  if (tClosed.contains('${d}_$slot')) {
                    conflictScore += 10;
                  }
                }
              }

              // Tercih edilen başlangıç saatine yakın olanı öncelikle seç
              if (isFlexHour) {
                conflictScore += (h - origStartH).abs();
              }

              if (conflictScore < minTotalConflict) {
                minTotalConflict = conflictScore;
                bestDay = d;
                bestHour = h;
              }
            }
          }

          day = bestDay;
          startH = bestHour;
          print('🤝 Esnek zümre toplantısı belirlendi: ${mtg['branch']} → $day (${startH + 1}. ders, $dur ders blok) [EsnekGün: $isFlexDay, EsnekSaat: $isFlexHour]');
        }

        calculatedMeetings.add({
          ...mtg,
          'day': day,
          'startHour': startH,
        });

        for (final tId in teacherIds) {
          final tKey = 'teacher_$tId';
          for (int h = startH; h < startH + dur; h++) {
            effectiveClosed.putIfAbsent(tKey, () => <String>{}).add('${day}_$h');
          }
        }
      }
    }

    // effectiveClosed'u (tüm yarım günler, toplantılar ve kapalı slotlar) closedSlots olarak kullan
    closedSlots = effectiveClosed;

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

    // Bu döneme ait geçerli lesson ID'leri yükle (çapraz doğrulama)
    var lessonsQuery = _firestore
        .collection('lessons')
        .where('institutionId', isEqualTo: institutionId)
        .where('schoolTypeId', isEqualTo: schoolTypeId)
        .where('isActive', isEqualTo: true);
    if (termId != null && termId.isNotEmpty) {
      lessonsQuery = lessonsQuery.where('termId', isEqualTo: termId);
    }

    // Bu döneme ait geçerli class ID'leri yükle
    var classesQuery = _firestore
        .collection('classes')
        .where('institutionId', isEqualTo: institutionId)
        .where('schoolTypeId', isEqualTo: schoolTypeId)
        .where('isActive', isEqualTo: true);
    if (termId != null && termId.isNotEmpty) {
      classesQuery = classesQuery.where('termId', isEqualTo: termId);
    }

    final results = await Future.wait([assignmentsQuery.get(), lessonsQuery.get(), classesQuery.get()]);
    final assignmentsSnap = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final lessonsSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final classesSnap = results[2] as QuerySnapshot<Map<String, dynamic>>;

    // Bu alt döneme ait dersleri filtrele (subTermId / periodId sadece bu döneme ait olmalı)
    final periodLessons = lessonsSnap.docs.where((d) {
      final stId = d.data()['subTermId'] ?? d.data()['periodId'];
      return stId == periodId;
    }).toList();

    final validLessonIds = periodLessons.map((d) => d.id).toSet();
    final validClassIds = classesSnap.docs.map((d) => d.id).toSet();
    print('✅ Bu alt dönemde ($periodId) ${validLessonIds.length} ders, ${validClassIds.length} sınıf bulundu');

    // Sadece bu alt döneme ait geçerli ders ve sınıflara ait atamaları al
    final rawAssignments = assignmentsSnap.docs
        .where((d) {
          final stId = d.data()['subTermId'] ?? d.data()['periodId'];
          return stId == periodId;
        })
        .map((d) => d.data())
        .where((a) {
          final lessonId = (a['lessonId'] ?? '').toString();
          final classId = (a['classId'] ?? '').toString();
          return validClassIds.contains(classId) && (validLessonIds.contains(lessonId) || (validLessonIds.isEmpty && lessonId.isNotEmpty));
        })
        .toList();
    print('📚 Veritabanından ${rawAssignments.length} geçerli atama bulundu');

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

    var assignments = uniqueAssignmentMap.values.toList();
    if (isPartial) {
      if (targetClassId != null && targetClassId.isNotEmpty) {
        assignments = assignments.where((a) => a['classId'] == targetClassId).toList();
      } else if (targetTeacherId != null && targetTeacherId.isNotEmpty) {
        assignments = assignments.where((a) {
          final tId = (a['teacherId'] ?? '').toString();
          final tIds = (a['teacherIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
          return tId == targetTeacherId || tIds.contains(targetTeacherId);
        }).toList();
      }
      print('🎯 Kısmi dağıtım için ${assignments.length} atama işlenecek');
    } else {
      print('📚 ${assignments.length} benzersiz atama dağıtılacak');
    }

    // Öncelik grubu:
    // 1 = Gün veya saat kısıtlı dersler (hareket alanı en dar olanlar - İLK ALINACAK)
    // 2 = Kur ve kulüp dersleri (birleştirilmiş dersler)
    // 3 = Diğer birleştirilmiş dersler
    // 4 = Normal tekil dersler
    int priorityOf(Map<String, dynamic> a) {
      final aKey = (a['lessonName'] as String? ?? '').trim().toLowerCase() +
          '|' + ((a['weeklyHours'] as num?)?.toInt() ?? 0).toString();
      final lId = (a['lessonId'] ?? '').toString();

      // 1. Öncelik: Gün veya saat kısıtlı dersler
      final hasDayConstraint = (lessonDayPreferences?.containsKey(aKey) == true && lessonDayPreferences![aKey]!.isNotEmpty) ||
          (lessonDayPreferences?.containsKey(lId) == true && lessonDayPreferences![lId]!.isNotEmpty);
      final hasHourConstraint = (lessonHourPreferences?.containsKey(aKey) == true && lessonHourPreferences![aKey]!.isNotEmpty) ||
          (lessonHourPreferences?.containsKey(lId) == true && lessonHourPreferences![lId]!.isNotEmpty);
      if (hasDayConstraint || hasHourConstraint) return 1;

      // 2. ve 3. Öncelik: Kur/kulüp veya normal birleştirilmiş dersler
      if (lessonClassMerges != null && lessonClassMerges.isNotEmpty) {
        final cId = (a['classId'] ?? '').toString();
        final lName = (a['lessonName'] as String? ?? '').trim().toLowerCase();
        for (var merge in lessonClassMerges) {
          final mLessonName = (merge['lessonName'] as String? ?? '').trim().toLowerCase();
          final mLessonId   = (merge['lessonId'] ?? '').toString();
          final mClasses = List<String>.from(merge['classIds'] ?? []);
          final nameOrIdMatch = (mLessonName == lName || (lId.isNotEmpty && mLessonId == lId));
          if (nameOrIdMatch && mClasses.contains(cId)) {
            final gType = (merge['groupType'] ?? '').toString();
            if (gType == 'track' || gType == 'club') return 2; // 2: kur ve kulüp
            return 3; // 3: birleşik (manuel)
          }
        }
      }

      return 4; // 4: normal dersler
    }

    // Sıralama: gün/saat kısıtlı → kur/kulüp → birleşik → normal
    assignments.sort((a, b) {
      final pa = priorityOf(a);
      final pb = priorityOf(b);
      if (pa != pb) return pa.compareTo(pb);
      final hoursA = (a['weeklyHours'] as num?)?.toInt() ?? 0;
      final hoursB = (b['weeklyHours'] as num?)?.toInt() ?? 0;
      return hoursB.compareTo(hoursA);
    });

    // ── 4. Monte Carlo + Kalite Skorlu Simülasyon ────────────────
    //    Birden fazla dağıtım denemesi yapılır, her seferinde farklı
    //    sıralama ve rastgele faktörlerle. En az yerleştirilemeyen
    //    ders saati ve en yüksek dağıtım kalitesi olan sonuç seçilir.
    int maxAttempts = 2500;
    List<Map<String, dynamic>>? bestSchedule;
    List<String>? bestUnassignedDetails;
    int bestUnassignedCount = 999999;
    int bestAssignedCount = 0;
    double bestQualityScore = -999999;

    print('🎲 $maxAttempts simülasyon çalıştırılıyor...');

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      // Tarayıcı / UI event-loop'u donmasın: Her 25 denemede bir async yield et
      if (attempt % 25 == 0) {
        await Future.delayed(Duration.zero);
      }

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
        lessonHourPreferences: lessonHourPreferences,
        lessonDayPreferences: lessonDayPreferences,
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
    // Eğer hiç iyi sonuç bulunamadıysa boş program
    if (bestSchedule == null) {
      return AutoScheduleResult(
        assignedCount: 0,
        unassignedCount: bestUnassignedCount,
        unassignedDetails: ['Yerleştirilebilecek ders bulunamadı'],
        assignedHalfDays: calculatedHalfDays,
        updatedTeacherMeetings: calculatedMeetings.isNotEmpty ? calculatedMeetings : null,
      );
    }
    print('💾 ${bestSchedule.length} kayıt kaydediliyor...');

    final oldRecords = await _firestore
        .collection('classSchedules')
        .where('periodId', isEqualTo: periodId)
        .where('institutionId', isEqualTo: institutionId)
        .get();

    List<WriteBatch> batches = [];
    WriteBatch currentBatch = _firestore.batch();
    int operationCount = 0;

    if (isPartial) {
      // Yalnızca hedef şube veya öğretmenin kilitli olmayan eski kayıtlarını sil
      final docsToDelete = oldRecords.docs.where((doc) {
        final d = doc.data();
        final key = '${d['classId']}_${d['day']}_${d['hourIndex']}';
        if (lockedSlots != null && lockedSlots.contains(key)) return false;

        if (targetClassId != null && targetClassId.isNotEmpty) {
          return d['classId'] == targetClassId;
        } else if (targetTeacherId != null && targetTeacherId.isNotEmpty) {
          final tId = d['teacherId']?.toString();
          final tIds = (d['teacherIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
          return tId == targetTeacherId || tIds.contains(targetTeacherId);
        }
        return false;
      }).toList();

      for (var doc in docsToDelete) {
        currentBatch.delete(doc.reference);
        operationCount++;
        if (operationCount >= 450) {
          batches.add(currentBatch);
          currentBatch = _firestore.batch();
          operationCount = 0;
        }
      }

      // Sadece yeni yerleştirilen hedef dersleri ekle (mevcut diğer sınıfların kayıtları zaten veritabanında duruyor)
      final existingKeys = existingSchedule.map((e) => '${e['classId']}_${e['day']}_${e['hourIndex']}').toSet();
      final newToInsert = bestSchedule.where((e) {
        final key = '${e['classId']}_${e['day']}_${e['hourIndex']}';
        return !existingKeys.contains(key);
      }).toList();

      for (var data in newToInsert) {
        final ref = _firestore.collection('classSchedules').doc();
        currentBatch.set(ref, data);
        operationCount++;
        if (operationCount >= 450) {
          batches.add(currentBatch);
          currentBatch = _firestore.batch();
          operationCount = 0;
        }
      }
    } else {
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
    }

    batches.add(currentBatch);
    await Future.wait(batches.map((batch) => batch.commit()));

    if (calculatedMeetings.isNotEmpty) {
      await _firestore.collection('workPeriods').doc(periodId).set({
        'teacherMeetings': calculatedMeetings,
        'scheduleSettings': {
          'teacherMeetings': calculatedMeetings,
        },
      }, SetOptions(merge: true));
    }

    return AutoScheduleResult(
      assignedCount: bestAssignedCount,
      unassignedCount: bestUnassignedCount,
      unassignedDetails: bestUnassignedDetails ?? [],
      assignedHalfDays: calculatedHalfDays,
      updatedTeacherMeetings: calculatedMeetings.isNotEmpty ? calculatedMeetings : null,
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
    Map<String, Map<int, int>>? lessonHourPreferences,
    Map<String, Set<String>>? lessonDayPreferences,
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
    // Aynı ders adındaki farklı merge gruplarının çakışmaması için:
    // key: lessonName.toLowerCase(), value: day → occupied hours
    final Map<String, Map<String, Set<int>>> mergedLessonTimeline = {};

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
        bool avoidLast, {
        Set<int>? redHours,
        Set<int>? greenHours,
        bool strictGreen = true,
        String? lessonNameKey, // Birleşik ders çakışma kontrolü için
    }) {
      if (startHour < 0 || startHour + blockSize > dayMax) return false;
      if (avoidFirst && startHour == 0) return false;
      if (avoidLast && startHour + blockSize == dayMax) return false;

      for (int b = 0; b < blockSize; b++) {
        final slot = startHour + b;
        if (avoidFirst && slot == 0) return false;
        if (avoidLast && slot == dayMax - 1) return false;
        if (redHours != null && redHours.contains(slot)) return false;
        if (strictGreen && greenHours != null && greenHours.isNotEmpty && !greenHours.contains(slot)) {
          return false;
        }

        for (var mCId in mergedClassIds) {
          if (isSlotOccupied('class', mCId, day, slot)) return false;
        }
        for (var tId in teacherIds) {
          if (isSlotOccupied('teacher', tId, day, slot)) return false;
        }
        if (isClosedSlot(teacherIds, mergedClassIds, day, slot)) return false;

        // Aynı ders adındaki başka bir merge grubu bu saati kullanıyor mu?
        if (lessonNameKey != null) {
          if (mergedLessonTimeline[lessonNameKey]?[day]?.contains(slot) == true) {
            return false;
          }
        }
      }

      // ── Sınıf Gün İçi Boşluk (Pencere/Delik) Kontrolü ─────────────
      // "en önemlisi bir ders 7. saat 8 boş 9. saate koymaması gerekiyor"
      // Bloğun yerleşimi sonrasında sınıfın o günkü dersleri arasında boşluk kalmamalı.
      for (var mCId in mergedClassIds) {
        final existing = classTimeline[mCId]?[day];
        if (existing != null && existing.isNotEmpty) {
          final allHours = Set<int>.from(existing);
          for (int b = 0; b < blockSize; b++) {
            allHours.add(startHour + b);
          }
          final minH = allHours.reduce(min);
          final maxH = allHours.reduce(max);
          if ((maxH - minH + 1) != allHours.length) {
            return false; // Arada boşluk (delik/pencere) oluşuyor! Kesinlikle yasak!
          }
        }
      }

      return true;
    }

    // ── Yardımcı: Slot Kalite Skoru (yüksek=iyi) ─────────────────
    double scoreSlot(
        int startHour, int blockSize, String day, int dayMax, String classId, {Set<int>? greenHours}) {
      double score = 0;

      // Mevcut derslere bitişik → sıkıştırma bonus
      if (startHour > 0 && isSlotOccupied('class', classId, day, startHour - 1)) {
        score += 15;
      }
      if (startHour + blockSize < dayMax &&
          isSlotOccupied('class', classId, day, startHour + blockSize)) {
        score += 15;
      }

      // Yeşil saat bonusu (tercih edilen saatler öncelikli yerleştirilir)
      if (greenHours != null && greenHours.isNotEmpty) {
        int greenCount = 0;
        for (int b = 0; b < blockSize; b++) {
          if (greenHours.contains(startHour + b)) greenCount++;
        }
        score += greenCount * 150.0;
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
      // Öncelik grubu ile karıştırma: gün/saat kısıtlı → kur/kulüp → birleşik → normal
      int attemptPriority(Map<String, dynamic> a) {
        final aKey = (a['lessonName'] as String? ?? '').trim().toLowerCase() +
            '|' + ((a['weeklyHours'] as num?)?.toInt() ?? 0).toString();
        final lId = (a['lessonId'] ?? '').toString();

        // 1. Gün veya saat kısıtlı dersler
        final hasDayConstraint = (lessonDayPreferences?.containsKey(aKey) == true && lessonDayPreferences![aKey]!.isNotEmpty) ||
            (lessonDayPreferences?.containsKey(lId) == true && lessonDayPreferences![lId]!.isNotEmpty);
        final hasHourConstraint = (lessonHourPreferences?.containsKey(aKey) == true && lessonHourPreferences![aKey]!.isNotEmpty) ||
            (lessonHourPreferences?.containsKey(lId) == true && lessonHourPreferences![lId]!.isNotEmpty);
        if (hasDayConstraint || hasHourConstraint) return 1;

        // 2. ve 3. Kur/kulüp veya birleşik dersler
        if (lessonClassMerges != null && lessonClassMerges.isNotEmpty) {
          final cId = (a['classId'] ?? '').toString();
          final lName = (a['lessonName'] as String? ?? '').trim().toLowerCase();
          for (var merge in lessonClassMerges) {
            final mLessonName = (merge['lessonName'] as String? ?? '').trim().toLowerCase();
            final mLessonId   = (merge['lessonId'] ?? '').toString();
            final mClasses = List<String>.from(merge['classIds'] ?? []);
            final nameOrIdMatch = (mLessonName == lName || (lId.isNotEmpty && mLessonId == lId));
            if (nameOrIdMatch && mClasses.contains(cId)) {
              final gType = (merge['groupType'] ?? '').toString();
              if (gType == 'track' || gType == 'club') return 2; // kur ve kulüp
              return 3; // birleşik (manuel)
            }
          }
        }
        return 4; // normal dersler
      }

      final constrained  = shuffled.where((a) => attemptPriority(a) == 1).toList();
      final tracksClubs  = shuffled.where((a) => attemptPriority(a) == 2).toList();
      final merged       = shuffled.where((a) => attemptPriority(a) == 3).toList();
      final normal       = shuffled.where((a) => attemptPriority(a) == 4).toList();

      // Her grup içinde gürültülü sıralama (Monte Carlo çeşitliliği)
      void noisySort(List<Map<String, dynamic>> list) {
        list.sort((a, b) {
          final ha = (a['weeklyHours'] as num?)?.toInt() ?? 0;
          final hb = (b['weeklyHours'] as num?)?.toInt() ?? 0;
          return (hb + random.nextInt(4)).compareTo(ha + random.nextInt(4));
        });
      }

      noisySort(constrained);
      noisySort(tracksClubs);
      noisySort(merged);
      noisySort(normal);

      shuffled
        ..clear()
        ..addAll(constrained)
        ..addAll(tracksClubs)
        ..addAll(merged)
        ..addAll(normal);
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
      final hourPrefs = lessonHourPreferences?[patternKey] ??
          lessonHourPreferences?[lessonId] ??
          const <int, int>{};

      final redHours = <int>{};
      final greenHours = <int>{};
      hourPrefs.forEach((h, state) {
        if (state == 2) redHours.add(h);
        if (state == 1) greenHours.add(h);
      });

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

          // ── Gün Kısıtı Kontrolü ──────────────────────────────────
          final dayAllowed = lessonDayPreferences?[patternKey];
          if (dayAllowed != null && dayAllowed.isNotEmpty && !dayAllowed.contains(day)) {
            continue; // Bu gün bu ders için yasak
          }

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
            // Yeni gün → tüm pozisyonları dene (dayMax - blockSize + 1 negatif olmamalı)
            final genCount = dayMax - blockSize + 1;
            candidateStarts = genCount > 0 ? List.generate(genCount, (i) => i) : [];
          }

          // ── Pozisyonları skorla ve filtrele ─────────────────────
          final dayRedHours = Set<int>.from(redHours);
          if (avoidFirstHour) dayRedHours.add(0);
          if (avoidLastHour && dayMax > 0) dayRedHours.add(dayMax - 1);

          List<MapEntry<int, double>> slotCandidates = [];
          for (var h in candidateStarts) {
            if (!canPlaceBlock(h, blockSize, day, dayMax, mergedClassIds,
                teacherIds, avoidFirstHour, avoidLastHour,
                redHours: dayRedHours, greenHours: greenHours, strictGreen: true,
                lessonNameKey: isMerged ? lessonName.toLowerCase() : null)) {
              continue;
            }
            final ss = scoreSlot(h, blockSize, day, dayMax, classId, greenHours: greenHours) +
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

            // Birleştirme ders zaman çizelgesi güncelle (farklı merge grupları çakışmasın)
            if (isMerged) {
              mergedLessonTimeline
                  .putIfAbsent(lessonName.toLowerCase(), () => {})
                  .putIfAbsent(day, () => <int>{})
                  .add(slot);
            }
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
        score -= gaps * 1000; // Gün içi delik/boşluk cezası ağırlaştırıldı
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
