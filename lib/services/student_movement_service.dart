import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/school/student_movement_model.dart';
import 'crypto_service.dart';
import 'user_permission_service.dart';

class StudentMovementService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static final Map<String, String> _schoolDocIdCache = {};

  static String formatDateYmd(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String dayNameTr(int weekday) {
    const names = <int, String>{
      DateTime.monday: 'Pazartesi',
      DateTime.tuesday: 'Salı',
      DateTime.wednesday: 'Çarşamba',
      DateTime.thursday: 'Perşembe',
      DateTime.friday: 'Cuma',
      DateTime.saturday: 'Cumartesi',
      DateTime.sunday: 'Pazar',
    };
    return names[weekday] ?? 'Pazartesi';
  }

  static String _normTr(String input) {
    return input
        .trim()
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .replaceAll('Ç', 'ç')
        .replaceAll('Ğ', 'ğ')
        .replaceAll('Ö', 'ö')
        .replaceAll('Ş', 'ş')
        .replaceAll('Ü', 'ü')
        .toLowerCase();
  }

  List<String> _instVariants(String institutionId) {
    return {
      institutionId.trim(),
      institutionId.trim().toUpperCase(),
      institutionId.trim().toLowerCase(),
    }.where((e) => e.isNotEmpty).toList();
  }

  /// `schools/{schoolDocId}` doküman kimliğini çözümler (önbellekli)
  Future<String> resolveSchoolDocId(String institutionId) async {
    final clean = institutionId.trim();
    if (clean.isEmpty) return '';
    if (_schoolDocIdCache.containsKey(clean)) {
      return _schoolDocIdCache[clean]!;
    }

    try {
      final variants = _instVariants(clean);
      final snap = await _db
          .collection('schools')
          .where('institutionId', whereIn: variants)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final id = snap.docs.first.id;
        _schoolDocIdCache[clean] = id;
        return id;
      }
      final direct = await _db.collection('schools').doc(clean).get();
      if (direct.exists) {
        _schoolDocIdCache[clean] = direct.id;
        return direct.id;
      }
    } catch (_) {}

    _schoolDocIdCache[clean] = clean;
    return clean;
  }

  /// Oturum açan personelin bilgilerini getirir
  Future<({String uid, String name, String role})> resolveCurrentActor() async {
    final authUser = FirebaseAuth.instance.currentUser;
    final userData = await UserPermissionService.loadUserData();
    final uid = authUser?.uid ?? (userData?['id'] ?? '').toString();
    final first = (userData?['firstName'] ?? '').toString().trim();
    final last = (userData?['lastName'] ?? '').toString().trim();
    final name =
        (userData?['fullName'] ??
                userData?['name'] ??
                authUser?.displayName ??
                '$first $last')
            .toString()
            .trim();
    final role = (userData?['title'] ?? userData?['role'] ?? 'Personel')
        .toString()
        .trim();
    return (
      uid: uid,
      name: name.isNotEmpty ? name : (authUser?.email ?? 'Okul Yönetimi'),
      role: role,
    );
  }

  /// Bugünün veya seçili tarihin tüm öğrenci hareketlerini canlı stream olarak döner
  Stream<List<StudentMovementRecord>> watchMovementsForDate({
    required String schoolDocId,
    required String dateStr,
    String? schoolTypeId,
    String? classId,
  }) {
    if (schoolDocId.isEmpty) return Stream.value(const []);
    Query<Map<String, dynamic>> q = _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('studentMovements')
        .where('dateStr', isEqualTo: dateStr);

    return q.snapshots().map((snap) {
      final list = snap.docs.map((d) => StudentMovementRecord.fromDoc(d)).where(
        (r) {
          if (schoolTypeId != null &&
              schoolTypeId.isNotEmpty &&
              r.schoolTypeId.isNotEmpty &&
              r.schoolTypeId != schoolTypeId) {
            return false;
          }
          if (classId != null && classId.isNotEmpty && r.classId != classId) {
            return false;
          }
          return true;
        },
      ).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Öğrencinin bu dönem kaç kez geç kaldığını / revire gittiğini vb. sayar
  Future<Map<StudentMovementType, int>> getStudentMovementCounts({
    required String schoolDocId,
    required String studentId,
  }) async {
    final counts = <StudentMovementType, int>{
      for (final t in StudentMovementType.values) t: 0,
    };
    if (schoolDocId.isEmpty || studentId.isEmpty) return counts;
    try {
      final snap = await _db
          .collection('schools')
          .doc(schoolDocId)
          .collection('studentMovements')
          .where('studentId', isEqualTo: studentId)
          .get();
      for (final doc in snap.docs) {
        final rec = StudentMovementRecord.fromDoc(doc);
        if (rec.status == StudentMovementStatus.cancelled) continue;
        counts[rec.type] = (counts[rec.type] ?? 0) + 1;
      }
    } catch (_) {}
    return counts;
  }

  /// Seçili sınıf ve öğrenci için işlem yapılan günün ders saatlerini, saat aralıklarını ve
  /// (kurlu dersler dahil) her ders saatinin gerçek öğretmenini çözümler.
  Future<
    ({
      int currentLessonHour,
      int maxLessonHour,
      String periodId,
      List<ResolvedLessonSlot> slots,
    })
  >
  resolveTodayScheduleForStudent({
    required String institutionId,
    required String schoolTypeId,
    required String classId,
    String? studentId,
    DateTime? referenceTime,
  }) async {
    final now = referenceTime ?? DateTime.now();
    final todayName = dayNameTr(now.weekday);
    final variants = _instVariants(institutionId);

    String activePeriodId = '';
    int maxHour = 8;
    String effectiveDayName = todayName;
    bool isOffDayFallback = false;
    final Map<
      int,
      ({String start, String end, int startMinutes, int endMinutes})
    >
    hourTimes = {};

    DateTime? parsePeriodDate(dynamic raw) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      if (raw is String && raw.trim().isNotEmpty) {
        return DateTime.tryParse(raw.trim());
      }
      return null;
    }

    ({String start, String end, int startMinutes, int endMinutes})?
    parseTimeItem(dynamic item) {
      if (item is! Map) return null;
      int? sh = int.tryParse((item['startHour'] ?? '').toString());
      int? sm = int.tryParse((item['startMinute'] ?? '').toString());
      int? eh = int.tryParse((item['endHour'] ?? '').toString());
      int? em = int.tryParse((item['endMinute'] ?? '').toString());

      if (sh == null || eh == null) {
        final sRaw = (item['startTime'] ?? item['start'] ?? '')
            .toString()
            .trim();
        final eRaw = (item['endTime'] ?? item['end'] ?? '').toString().trim();
        if (sRaw.contains(':') && eRaw.contains(':')) {
          final sp = sRaw.split(':');
          final ep = eRaw.split(':');
          sh = int.tryParse(sp[0]);
          sm = sp.length > 1 ? int.tryParse(sp[1]) : 0;
          eh = int.tryParse(ep[0]);
          em = ep.length > 1 ? int.tryParse(ep[1]) : 0;
        }
      }

      if (sh == null || eh == null) return null;
      final sMin = sm ?? 0;
      final eMin = em ?? 0;
      return (
        start:
            '${sh.toString().padLeft(2, '0')}:${sMin.toString().padLeft(2, '0')}',
        end:
            '${eh.toString().padLeft(2, '0')}:${eMin.toString().padLeft(2, '0')}',
        startMinutes: sh * 60 + sMin,
        endMinutes: eh * 60 + eMin,
      );
    }

    // 1. Aktif workPeriod ve işlem yapılan günün ders saat çizelgesini bul
    try {
      QuerySnapshot<Map<String, dynamic>> wpSnap;
      if (schoolTypeId.isNotEmpty) {
        wpSnap = await _db
            .collection('workPeriods')
            .where('institutionId', whereIn: variants)
            .where('schoolTypeId', isEqualTo: schoolTypeId)
            .where('isActive', isEqualTo: true)
            .get();
        if (wpSnap.docs.isEmpty) {
          wpSnap = await _db
              .collection('workPeriods')
              .where('institutionId', whereIn: variants)
              .where('isActive', isEqualTo: true)
              .get();
        }
      } else {
        wpSnap = await _db
            .collection('workPeriods')
            .where('institutionId', whereIn: variants)
            .where('isActive', isEqualTo: true)
            .get();
      }

      QueryDocumentSnapshot<Map<String, dynamic>>? chosen;
      int bestScore = -1;
      DateTime bestEnd = DateTime(1970);

      for (final doc in wpSnap.docs) {
        final d = doc.data();
        int score = 0;
        final start = parsePeriodDate(d['startDate']);
        final end = parsePeriodDate(d['endDate']);
        if (start != null && end != null) {
          final dayStart = DateTime(start.year, start.month, start.day);
          final dayEnd = DateTime(end.year, end.month, end.day, 23, 59, 59);
          if (!now.isBefore(dayStart) && !now.isAfter(dayEnd)) {
            score += 100;
          }
        }
        if (d['schedulePublished'] == true || d['isPublished'] == true) {
          score += 50;
        }
        if (d['lessonHours'] is Map && (d['lessonHours'] as Map).isNotEmpty) {
          score += 30;
        }
        final endCmp = end ?? DateTime(1970);
        if (score > bestScore ||
            (score == bestScore && endCmp.isAfter(bestEnd))) {
          bestScore = score;
          bestEnd = endCmp;
          chosen = doc;
        }
      }

      if (chosen != null) {
        activePeriodId = chosen.id;
        final d = chosen.data();
        final lh = d['lessonHours'];
        if (lh is Map) {
          final selectedDays = lh['selectedDays'] is Iterable
              ? (lh['selectedDays'] as Iterable)
                    .map((e) => e.toString().trim())
                    .where((e) => e.isNotEmpty)
                    .toList()
              : <String>[];

          // Gün bazlı ders sayıları
          final Map<String, int> countsByNormDay = {};
          final Map<String, String> origDayByNorm = {};
          for (final sd in selectedDays) {
            origDayByNorm[_normTr(sd)] = sd;
          }
          final dailyCounts = lh['dailyLessonCounts'];
          if (dailyCounts is Map) {
            dailyCounts.forEach((k, v) {
              final ks = k.toString().trim();
              final cnt = v is int ? v : (int.tryParse(v.toString()) ?? 0);
              if (ks.isNotEmpty && cnt > 0) {
                countsByNormDay[_normTr(ks)] = cnt;
                origDayByNorm.putIfAbsent(_normTr(ks), () => ks);
              }
            });
          } else if (lh['dailyLessonCount'] != null) {
            final legacyCnt =
                int.tryParse(lh['dailyLessonCount'].toString()) ?? 0;
            if (legacyCnt > 0) {
              final daysToFill = selectedDays.isNotEmpty
                  ? selectedDays
                  : const ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma'];
              for (final sd in daysToFill) {
                countsByNormDay[_normTr(sd)] = legacyCnt;
                origDayByNorm.putIfAbsent(_normTr(sd), () => sd);
              }
            }
          }

          final rawTimes = lh['lessonTimes'];
          final Map<String, List<dynamic>> slotsByNormDay = {};
          List<dynamic>? sharedSlots;

          if (rawTimes is List) {
            sharedSlots = rawTimes;
          } else if (rawTimes is Map && rawTimes.isNotEmpty) {
            final firstKey = rawTimes.keys.first.toString();
            if (int.tryParse(firstKey) != null) {
              final keys =
                  rawTimes.keys
                      .map((k) => int.tryParse(k.toString()))
                      .whereType<int>()
                      .toList()
                    ..sort();
              sharedSlots = keys
                  .map((k) => rawTimes[k.toString()] ?? rawTimes[k])
                  .toList();
            } else {
              rawTimes.forEach((k, v) {
                if (v is List && v.isNotEmpty) {
                  final ks = k.toString().trim();
                  slotsByNormDay[_normTr(ks)] = v;
                  origDayByNorm.putIfAbsent(_normTr(ks), () => ks);
                }
              });
            }
          }

          final todayNorm = _normTr(todayName);
          final bool hasTodayInPeriod =
              (countsByNormDay[todayNorm] ?? 0) > 0 ||
              slotsByNormDay.containsKey(todayNorm) ||
              selectedDays.any((sd) => _normTr(sd) == todayNorm);

          String chosenNormDay = todayNorm;
          if (!hasTodayInPeriod) {
            // İşlem yapılan günde (örn. Pazar) ders tanımı yoksa kurumun ilk aktif ders gününü (örn. Pazartesi) referans al
            final pztNorm = _normTr('Pazartesi');
            if ((countsByNormDay[pztNorm] ?? 0) > 0 ||
                slotsByNormDay.containsKey(pztNorm)) {
              chosenNormDay = pztNorm;
              isOffDayFallback = true;
            } else if (countsByNormDay.isNotEmpty) {
              chosenNormDay = countsByNormDay.keys.first;
              isOffDayFallback = true;
            } else if (slotsByNormDay.isNotEmpty) {
              chosenNormDay = slotsByNormDay.keys.first;
              isOffDayFallback = true;
            }
          }

          effectiveDayName = origDayByNorm[chosenNormDay] ?? todayName;
          final daySlots = slotsByNormDay[chosenNormDay] ?? sharedSlots;
          final explicitDayCount = countsByNormDay[chosenNormDay];

          if (explicitDayCount != null && explicitDayCount > 0) {
            maxHour = explicitDayCount;
          } else if (daySlots != null && daySlots.isNotEmpty) {
            maxHour = daySlots.length;
          }

          if (daySlots != null) {
            final limit = daySlots.length < maxHour ? daySlots.length : maxHour;
            for (int i = 0; i < limit; i++) {
              final parsed = parseTimeItem(daySlots[i]);
              if (parsed != null) {
                hourTimes[i + 1] = parsed;
              }
            }
          }
        }
      }
    } catch (_) {}

    // Kurumda henüz saat aralığı girilmemiş ders dilimleri varsa standart 40 dk ders + 10 dk teneffüs üret
    if (hourTimes.length < maxHour) {
      int baseStartMin = 9 * 60; // 09:00
      if (hourTimes.isNotEmpty) {
        final maxDefinedKey = (hourTimes.keys.toList()..sort()).last;
        baseStartMin = hourTimes[maxDefinedKey]!.endMinutes + 10;
        for (int h = maxDefinedKey + 1; h <= maxHour; h++) {
          final endMin = baseStartMin + 40;
          hourTimes[h] = (
            start:
                '${(baseStartMin ~/ 60).toString().padLeft(2, '0')}:${(baseStartMin % 60).toString().padLeft(2, '0')}',
            end:
                '${(endMin ~/ 60).toString().padLeft(2, '0')}:${(endMin % 60).toString().padLeft(2, '0')}',
            startMinutes: baseStartMin,
            endMinutes: endMin,
          );
          baseStartMin = endMin + 10;
        }
      } else {
        for (int h = 1; h <= maxHour; h++) {
          final endMin = baseStartMin + 40;
          hourTimes[h] = (
            start:
                '${(baseStartMin ~/ 60).toString().padLeft(2, '0')}:${(baseStartMin % 60).toString().padLeft(2, '0')}',
            end:
                '${(endMin ~/ 60).toString().padLeft(2, '0')}:${(endMin % 60).toString().padLeft(2, '0')}',
            startMinutes: baseStartMin,
            endMinutes: endMin,
          );
          baseStartMin = endMin + 10;
        }
      }
    }

    // Şu anki saat:dakikaya göre aktif ders saatini bul
    int currentHour = 1;
    final nowMinutes = now.hour * 60 + now.minute;
    if (hourTimes.isNotEmpty) {
      final sortedHours = hourTimes.keys.toList()..sort();
      currentHour = sortedHours.last;
      for (final h in sortedHours) {
        if (nowMinutes <= hourTimes[h]!.endMinutes) {
          currentHour = h;
          break;
        }
      }
    }

    if (classId.isEmpty) {
      return (
        currentLessonHour: currentHour,
        maxLessonHour: maxHour,
        periodId: activePeriodId,
        slots: List<ResolvedLessonSlot>.generate(
          maxHour,
          (i) => ResolvedLessonSlot(
            lessonHour: i + 1,
            lessonId: '',
            lessonName: '${i + 1}. Ders',
            startTime: hourTimes[i + 1]?.start ?? '',
            endTime: hourTimes[i + 1]?.end ?? '',
            periodId: activePeriodId,
            scheduleDayName: effectiveDayName,
            isOffDayFallback: isOffDayFallback,
          ),
        ),
      );
    }

    // 2. lessonAssignments ve Kurlu Ders (courseGroups) eşleşmelerini çek
    final Map<String, List<String>> lessonIdToTeacherIds = {};
    final Map<String, List<String>> lessonIdToTeacherNames = {};
    final Map<String, List<String>> lessonNameToTeacherIds = {};
    final Map<String, List<String>> lessonNameToTeacherNames = {};

    try {
      final assignSnap = await _db
          .collection('lessonAssignments')
          .where('institutionId', whereIn: variants)
          .where('classId', isEqualTo: classId)
          .where('isActive', isEqualTo: true)
          .get();

      for (final doc in assignSnap.docs) {
        final d = doc.data();
        final lid = (d['lessonId'] ?? '').toString().trim();
        final lname = _normTr((d['lessonName'] ?? '').toString());
        final tIds = <String>[
          if (d['teacherIds'] is Iterable)
            ...(d['teacherIds'] as Iterable).map((e) => e.toString().trim()),
          if (d['teacherId'] != null) d['teacherId'].toString().trim(),
        ].where((e) => e.isNotEmpty).toSet().toList();
        final tNames = <String>[
          if (d['teacherNames'] is Iterable)
            ...(d['teacherNames'] as Iterable).map((e) => e.toString().trim()),
          if (d['teacherName'] != null) d['teacherName'].toString().trim(),
        ].where((e) => e.isNotEmpty).toSet().toList();

        if (lid.isNotEmpty) {
          lessonIdToTeacherIds[lid] = tIds;
          lessonIdToTeacherNames[lid] = tNames;
        }
        if (lname.isNotEmpty) {
          lessonNameToTeacherIds[lname] = tIds;
          lessonNameToTeacherNames[lname] = tNames;
        }
      }
    } catch (_) {}

    // Kurlu derslerde (örn. İngilizce) öğrencinin kayıtlı olduğu alt kurun öğretmenini bul
    if (studentId != null && studentId.isNotEmpty) {
      try {
        final cgSnap = await _db
            .collection('courseGroups')
            .where('institutionId', whereIn: variants)
            .where('isActive', isEqualTo: true)
            .get();
        for (final doc in cgSnap.docs) {
          final d = doc.data();
          if ((d['type'] ?? '').toString().toLowerCase() == 'club') continue;
          final lid = (d['lessonId'] ?? '').toString().trim();
          final lname = _normTr(
            (d['lessonName'] ?? d['name'] ?? '').toString(),
          );
          final subGroups = d['subGroups'] is List
              ? (d['subGroups'] as List)
              : const [];
          for (final sg in subGroups) {
            if (sg is! Map) continue;
            final sIds = sg['studentIds'] is Iterable
                ? (sg['studentIds'] as Iterable)
                      .map((e) => e.toString())
                      .toSet()
                : const <String>{};
            if (sIds.contains(studentId)) {
              final sgTIds = sg['teacherIds'] is Iterable
                  ? (sg['teacherIds'] as Iterable)
                        .map((e) => e.toString().trim())
                        .where((e) => e.isNotEmpty)
                        .toList()
                  : const <String>[];
              final sgTNames = sg['teacherNames'] is Iterable
                  ? (sg['teacherNames'] as Iterable)
                        .map((e) => e.toString().trim())
                        .where((e) => e.isNotEmpty)
                        .toList()
                  : const <String>[];
              if (lid.isNotEmpty) {
                if (sgTIds.isNotEmpty) lessonIdToTeacherIds[lid] = sgTIds;
                if (sgTNames.isNotEmpty) lessonIdToTeacherNames[lid] = sgTNames;
              }
              if (lname.isNotEmpty) {
                if (sgTIds.isNotEmpty) lessonNameToTeacherIds[lname] = sgTIds;
                if (sgTNames.isNotEmpty)
                  lessonNameToTeacherNames[lname] = sgTNames;
              }
            }
          }
        }
      } catch (_) {}
    }

    // 3. Bugünkü classSchedules kayıtlarını çek
    final Map<int, ResolvedLessonSlot> slotByHour = {};
    try {
      Query<Map<String, dynamic>> schedQuery = _db
          .collection('classSchedules')
          .where('classId', isEqualTo: classId);
      if (activePeriodId.isNotEmpty) {
        schedQuery = schedQuery.where('periodId', isEqualTo: activePeriodId);
      }
      final schedSnap = await schedQuery.get();
      var schedDocs = schedSnap.docs.where((doc) {
        final d = doc.data();
        if (d['isActive'] == false) return false;
        final dayStr = (d['day'] ?? '').toString().trim();
        return _normTr(dayStr) == _normTr(todayName);
      }).toList();

      if (schedDocs.isEmpty && isOffDayFallback) {
        schedDocs = schedSnap.docs.where((doc) {
          final d = doc.data();
          if (d['isActive'] == false) return false;
          final dayStr = (d['day'] ?? '').toString().trim();
          return _normTr(dayStr) == _normTr(effectiveDayName);
        }).toList();
      } else if (schedDocs.isNotEmpty && isOffDayFallback) {
        effectiveDayName = todayName;
        isOffDayFallback = false;
      }

      for (final doc in schedDocs) {
        final d = doc.data();

        final hIdx = d['hourIndex'] is int
            ? d['hourIndex'] as int
            : (int.tryParse((d['hourIndex'] ?? '0').toString()) ?? 0);
        final hour = hIdx + 1;
        if (hour > maxHour) maxHour = hour;

        final lessonId = (d['lessonId'] ?? '').toString().trim();
        final lessonName =
            (d['lessonName'] ?? d['subjectName'] ?? '$hour. Ders')
                .toString()
                .trim();
        final lNorm = _normTr(lessonName);

        List<String> tIds = [
          if (d['teacherIds'] is Iterable)
            ...(d['teacherIds'] as Iterable).map((e) => e.toString().trim()),
          if (d['teacherId'] != null) d['teacherId'].toString().trim(),
        ].where((e) => e.isNotEmpty).toSet().toList();

        List<String> tNames =
            [
                  if (d['teacherNames'] is Iterable)
                    ...(d['teacherNames'] as Iterable).map(
                      (e) => e.toString().trim(),
                    ),
                  if (d['teacherName'] != null)
                    d['teacherName'].toString().trim(),
                ]
                .where(
                  (e) =>
                      e.isNotEmpty &&
                      !_normTr(e).startsWith('kur:') &&
                      _normTr(e) != 'ogretmen' &&
                      _normTr(e) != 'öğretmen',
                )
                .toSet()
                .toList();

        // Kurlu ders veya eksik öğretmen adında lessonAssignments / courseGroups'tan tamamla
        if (tIds.isEmpty) {
          tIds =
              lessonIdToTeacherIds[lessonId] ??
              lessonNameToTeacherIds[lNorm] ??
              const [];
        }
        if (tNames.isEmpty) {
          tNames =
              lessonIdToTeacherNames[lessonId] ??
              lessonNameToTeacherNames[lNorm] ??
              const [];
        } else if (lessonNameToTeacherNames.containsKey(lNorm) &&
            (d['teacherName'] ?? '').toString().startsWith('Kur:')) {
          // Kur dersiyse öğrencinin kendi kur öğretmenini kullan
          tIds = lessonNameToTeacherIds[lNorm] ?? tIds;
          tNames = lessonNameToTeacherNames[lNorm] ?? tNames;
        }

        slotByHour[hour] = ResolvedLessonSlot(
          lessonHour: hour,
          lessonId: lessonId,
          lessonName: lessonName,
          startTime: hourTimes[hour]?.start ?? '',
          endTime: hourTimes[hour]?.end ?? '',
          teacherIds: tIds,
          teacherNames: tNames,
          periodId: activePeriodId,
          scheduleDayName: effectiveDayName,
          isOffDayFallback: isOffDayFallback,
        );
      }
    } catch (_) {}

    // Eksik öğretmen adlarını users tablosundan çöz
    final unresolvedIds = <String>{
      for (final s in slotByHour.values)
        if (s.teacherNames.isEmpty) ...s.teacherIds,
    };
    if (unresolvedIds.isNotEmpty) {
      try {
        final usersSnap = await _db
            .collection('users')
            .where('institutionId', whereIn: variants)
            .get();
        final idToName = <String, String>{};
        for (final doc in usersSnap.docs) {
          final u = doc.data();
          final fn =
              (u['fullName'] ??
                      u['name'] ??
                      '${u['firstName'] ?? ''} ${u['lastName'] ?? ''}')
                  .toString()
                  .trim();
          if (fn.isNotEmpty) {
            idToName[doc.id] = fn;
            final authId = (u['authUserId'] ?? '').toString().trim();
            if (authId.isNotEmpty) idToName[authId] = fn;
          }
        }
        slotByHour.updateAll((hour, slot) {
          if (slot.teacherNames.isNotEmpty) return slot;
          final resolved = slot.teacherIds
              .map((id) => idToName[id] ?? '')
              .where((n) => n.isNotEmpty)
              .toSet()
              .toList();
          return ResolvedLessonSlot(
            lessonHour: slot.lessonHour,
            lessonId: slot.lessonId,
            lessonName: slot.lessonName,
            startTime: slot.startTime,
            endTime: slot.endTime,
            teacherIds: slot.teacherIds,
            teacherNames: resolved,
            periodId: slot.periodId,
            scheduleDayName: slot.scheduleDayName,
            isOffDayFallback: slot.isOffDayFallback,
          );
        });
      } catch (_) {}
    }

    final List<ResolvedLessonSlot> orderedSlots = List.generate(maxHour, (idx) {
      final h = idx + 1;
      return slotByHour[h] ??
          ResolvedLessonSlot(
            lessonHour: h,
            lessonId: '',
            lessonName: '$h. Ders',
            startTime: hourTimes[h]?.start ?? '',
            endTime: hourTimes[h]?.end ?? '',
            periodId: activePeriodId,
            scheduleDayName: effectiveDayName,
            isOffDayFallback: isOffDayFallback,
          );
    });

    return (
      currentLessonHour: currentHour,
      maxLessonHour: maxHour,
      periodId: activePeriodId,
      slots: orderedSlots,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ALICI ÇÖZÜMLEME VE ÇOK KANALLI BİLDİRİM MOTORU
  // ═══════════════════════════════════════════════════════════════════════════

  void _collectUserDocUids(
    DocumentSnapshot<Map<String, dynamic>> doc,
    Set<String> bucket,
  ) {
    if (doc.id.trim().isNotEmpty) bucket.add(doc.id.trim());
    final d = doc.data();
    final authId = (d?['authUserId'] ?? '').toString().trim();
    if (authId.isNotEmpty) bucket.add(authId);
  }

  /// Öğretmen ID veya Ad Soyad listesinden gerçek `users` bildirim UID'lerini çözümler
  Future<List<String>> resolveTeacherRecipientUids({
    required String institutionId,
    required List<String> teacherIds,
    required List<String> teacherNames,
  }) async {
    final Set<String> uids = {
      for (final id in teacherIds)
        if (id.trim().isNotEmpty) id.trim(),
    };
    final normNames = teacherNames
        .map(_normTr)
        .where((e) => e.isNotEmpty)
        .toSet();
    if (uids.isEmpty && normNames.isEmpty) return const [];

    try {
      final snap = await _db
          .collection('users')
          .where('institutionId', whereIn: _instVariants(institutionId))
          .get();
      for (final doc in snap.docs) {
        final u = doc.data();
        if (u['isActive'] == false) continue;
        final fn = _normTr(
          (u['fullName'] ??
                  u['name'] ??
                  '${u['firstName'] ?? ''} ${u['lastName'] ?? ''}')
              .toString(),
        );
        final authId = (u['authUserId'] ?? '').toString().trim();
        final matchesId =
            uids.contains(doc.id) ||
            (authId.isNotEmpty && uids.contains(authId));
        final matchesName = fn.isNotEmpty && normNames.contains(fn);
        if (matchesId || matchesName) {
          _collectUserDocUids(doc, uids);
        }
      }
    } catch (_) {}

    return uids.toList();
  }

  /// Kullanıcının belirtilen `schoolTypeId` kapsamına ait olup olmadığını kontrol eder:
  /// `1`: Açıkça bu okul türüne atanmış
  /// `0`: Hiçbir okul türü atanmamış (genel/kampüs görevlisi)
  /// `-1`: Başka okul türlerine atanmış (bu okul türünde değil)
  int _matchUserSchoolType(Map<String, dynamic> u, String? schoolTypeId) {
    final target = (schoolTypeId ?? '').trim();
    if (target.isEmpty) return 1;

    final assigned = <String>{};
    if (u['schoolTypes'] is Iterable) {
      for (final item in (u['schoolTypes'] as Iterable)) {
        final s = item.toString().trim();
        if (s.isNotEmpty) assigned.add(s);
      }
    }
    final single = (u['schoolTypeId'] ?? '').toString().trim();
    if (single.isNotEmpty) assigned.add(single);

    if (assigned.isEmpty) return 0;
    return assigned.contains(target) ? 1 : -1;
  }

  bool _isSecurityUser(Map<String, dynamic> u) {
    final role = _normTr((u['role'] ?? '').toString());
    final title = _normTr((u['title'] ?? '').toString());
    return role.contains('guvenlik') ||
        role.contains('security') ||
        title.contains('guvenlik') ||
        title.contains('kapi');
  }

  bool _isVicePrincipalUser(Map<String, dynamic> u) {
    final role = _normTr((u['role'] ?? '').toString());
    final title = _normTr((u['title'] ?? '').toString());
    return role.contains('mudur_yardimcisi') ||
        role.contains('yardimci') ||
        (title.contains('mudur') && title.contains('yardimci'));
  }

  bool _isPrincipalUser(Map<String, dynamic> u) {
    if (_isVicePrincipalUser(u)) return false;
    final role = _normTr((u['role'] ?? '').toString());
    final title = _normTr((u['title'] ?? '').toString());
    return role == 'mudur' ||
        role == 'genel_mudur' ||
        role == 'manager' ||
        role == 'admin' ||
        title.contains('okul muduru') ||
        (title.contains('mudur') && !title.contains('yardimci'));
  }

  /// Uygulama Ayarlarındaki Kapı / Ziyaretçi / Öğrenci Çıkış bildirim tercihlerini yükler.
  /// Okul türüne özel ayar tanımlanmışsa onu, yoksa kurum geneli ayarı döndürür.
  Future<GateNotificationSettings> loadGateNotificationSettings({
    required String institutionId,
    String? schoolDocId,
    String? schoolTypeId,
  }) async {
    try {
      final docId = (schoolDocId != null && schoolDocId.trim().isNotEmpty)
          ? schoolDocId.trim()
          : await resolveSchoolDocId(institutionId);
      if (docId.isEmpty) return const GateNotificationSettings();

      final snap = await _db.collection('schools').doc(docId).get();
      final appSettings = snap.data()?['appSettings'];
      if (appSettings is! Map) return const GateNotificationSettings();

      final stId = (schoolTypeId ?? '').trim();
      if (stId.isNotEmpty) {
        final stMap = appSettings['schoolTypeGateNotificationSettings'];
        if (stMap is Map && stMap[stId] is Map) {
          return GateNotificationSettings.fromMap(stMap[stId]);
        }
      }
      return GateNotificationSettings.fromMap(
        appSettings['gateNotificationSettings'],
      );
    } catch (_) {
      return const GateNotificationSettings();
    }
  }

  /// Yalnızca ilgili Okul Türündeki seçili alıcı gruplarının (`Müdür`, `Müdür Yardımcısı`, `Güvenlik`)
  /// kullanıcı UID'lerini çözümler. Başka okul türlerinin yöneticilerine bildirim gitmez.
  Future<List<String>> resolveScopedRoleRecipients({
    required String institutionId,
    required String schoolTypeId,
    required bool includeMudur,
    required bool includeMudurYardimcisi,
    required bool includeGuvenlik,
  }) async {
    if (!includeMudur && !includeMudurYardimcisi && !includeGuvenlik) {
      return const [];
    }

    final Set<String> strictMudur = {};
    final Set<String> fallbackMudur = {};
    final Set<String> strictMdYrd = {};
    final Set<String> fallbackMdYrd = {};
    final Set<String> securityUids = {};

    try {
      final snap = await _db
          .collection('users')
          .where('institutionId', whereIn: _instVariants(institutionId))
          .get();

      for (final doc in snap.docs) {
        final u = doc.data();
        if (u['isActive'] == false) continue;

        final match = _matchUserSchoolType(u, schoolTypeId);
        if (match == -1)
          continue; // Başka okul türüne ait kullanıcıyı kesinlikle hariç tut

        if (includeGuvenlik && _isSecurityUser(u)) {
          _collectUserDocUids(doc, securityUids);
          continue;
        }
        if (includeMudurYardimcisi && _isVicePrincipalUser(u)) {
          if (match == 1) {
            _collectUserDocUids(doc, strictMdYrd);
          } else {
            _collectUserDocUids(doc, fallbackMdYrd);
          }
          continue;
        }
        if (includeMudur && _isPrincipalUser(u)) {
          if (match == 1) {
            _collectUserDocUids(doc, strictMudur);
          } else {
            _collectUserDocUids(doc, fallbackMudur);
          }
        }
      }
    } catch (_) {}

    final result = <String>{
      if (includeGuvenlik) ...securityUids,
      if (includeMudur)
        ...(strictMudur.isNotEmpty ? strictMudur : fallbackMudur),
      if (includeMudurYardimcisi)
        ...(strictMdYrd.isNotEmpty ? strictMdYrd : fallbackMdYrd),
    };
    return result.toList();
  }

  /// Boş `schoolTypeId` geldiğinde görüşülecek personelin veya kurumun varsayılan Okul Türünü çözümler
  /// (Böylece bildirimler hiçbir zaman Genel Kısımda kalmaz, ilgili Okul Türü içine düşer).
  Future<String> resolveDefaultSchoolTypeId({
    required String institutionId,
    String? preferredSchoolTypeId,
    String? hostStaffUid,
  }) async {
    final pref = (preferredSchoolTypeId ?? '').trim();
    if (pref.isNotEmpty) return pref;

    final host = (hostStaffUid ?? '').trim();
    if (host.isNotEmpty) {
      try {
        final uDoc = await _db.collection('users').doc(host).get();
        if (uDoc.exists) {
          final ud = uDoc.data() ?? const <String, dynamic>{};
          if (ud['schoolTypes'] is Iterable) {
            for (final item in (ud['schoolTypes'] as Iterable)) {
              final s = item.toString().trim();
              if (s.isNotEmpty) return s;
            }
          }
          final single = (ud['schoolTypeId'] ?? '').toString().trim();
          if (single.isNotEmpty) return single;
        }
      } catch (_) {}
    }

    try {
      final stSnap = await _db
          .collection('schoolTypes')
          .where('institutionId', whereIn: _instVariants(institutionId))
          .limit(1)
          .get();
      if (stSnap.docs.isNotEmpty) {
        return stSnap.docs.first.id;
      }
    } catch (_) {}

    return '';
  }

  /// Ziyaretçi Giriş / Çıkış bildirimini Uygulama Ayarlarındaki tercihlere göre
  /// yalnızca ilgili Okul Türündeki seçili alıcılara iletir.
  Future<void> notifyVisitorEvent({
    required String institutionId,
    String? schoolDocId,
    required String schoolTypeId,
    required bool isExit,
    required String visitorLogId,
    required String visitorName,
    required String visitorCategory,
    required String targetUnit,
    required String visitReason,
    String hostStaffUid = '',
    String badgeNo = '',
    required String timeStr,
    String stayDurationLabel = '',
  }) async {
    final resolvedSchoolTypeId = await resolveDefaultSchoolTypeId(
      institutionId: institutionId,
      preferredSchoolTypeId: schoolTypeId,
      hostStaffUid: hostStaffUid,
    );

    final settings = await loadGateNotificationSettings(
      institutionId: institutionId,
      schoolDocId: schoolDocId,
      schoolTypeId: resolvedSchoolTypeId,
    );
    final cfg = isExit ? settings.visitorExit : settings.visitorEntry;
    if (!cfg.enabled) return;

    final recipients = <String>{};

    if (cfg.isRecipientEnabled('host_staff') &&
        hostStaffUid.trim().isNotEmpty) {
      recipients.add(hostStaffUid.trim());
      try {
        final hostDoc = await _db
            .collection('users')
            .doc(hostStaffUid.trim())
            .get();
        if (hostDoc.exists) {
          _collectUserDocUids(hostDoc, recipients);
        }
      } catch (_) {}
    }

    final roleUids = await resolveScopedRoleRecipients(
      institutionId: institutionId,
      schoolTypeId: resolvedSchoolTypeId,
      includeMudur: cfg.isRecipientEnabled('mudur'),
      includeMudurYardimcisi: cfg.isRecipientEnabled('mudur_yardimcisi'),
      includeGuvenlik: cfg.isRecipientEnabled('guvenlik'),
    );
    recipients.addAll(roleUids);

    if (recipients.isEmpty) return;

    final title = isExit
        ? '🚪 Ziyaretçi Çıkış Bildirimi: $visitorName'
        : '🛎️ Ziyaretçi Giriş Bildirimi: $visitorName';
    final message = isExit
        ? '$visitorName ($visitorCategory), $targetUnit ziyareti sonrasında saat $timeStr\'de güvenlik kapısından çıkış yaptı'
              '${stayDurationLabel.isNotEmpty ? " (Süre: $stayDurationLabel)" : ""}.'
        : '$visitorName ($visitorCategory), "$visitReason" kapsamında saat $timeStr\'de güvenlik kapı kontrolünden geçerek $targetUnit birimine yönlendirildi'
              '${badgeNo.isNotEmpty ? " (Kart: $badgeNo)" : ""}.';

    await dispatchNotification(
      institutionId: institutionId,
      schoolTypeId: resolvedSchoolTypeId,
      recipientUids: recipients.toList(),
      title: title,
      message: message,
      type: isExit ? 'visitor_check_out' : 'visitor_check_in',
      entityId: visitorLogId,
    );
  }

  /// Güvenlik birimi (+ yedek olarak ilgili okul türünün idaresi) kullanıcı UID'lerini çözümler
  Future<List<String>> resolveSecurityRecipientUids({
    required String institutionId,
    String? schoolTypeId,
  }) async {
    final securityOnly = await resolveScopedRoleRecipients(
      institutionId: institutionId,
      schoolTypeId: schoolTypeId ?? '',
      includeMudur: false,
      includeMudurYardimcisi: false,
      includeGuvenlik: true,
    );
    if (securityOnly.isNotEmpty) {
      return securityOnly;
    }
    return resolveScopedRoleRecipients(
      institutionId: institutionId,
      schoolTypeId: schoolTypeId ?? '',
      includeMudur: true,
      includeMudurYardimcisi: true,
      includeGuvenlik: false,
    );
  }

  /// Revir / Sağlık birimi kullanıcı UID'lerini çözümler
  Future<List<String>> resolveInfirmaryRecipientUids({
    required String institutionId,
  }) async {
    final Set<String> infirmaryUids = {};
    try {
      final snap = await _db
          .collection('users')
          .where('institutionId', whereIn: _instVariants(institutionId))
          .get();
      for (final doc in snap.docs) {
        final u = doc.data();
        if (u['isActive'] == false) continue;
        final combined = _normTr(
          '${u['role'] ?? ''} ${u['title'] ?? ''} ${u['branch'] ?? ''}',
        );
        if (combined.contains('revir') ||
            combined.contains('saglik') ||
            combined.contains('sağlık') ||
            combined.contains('hemsire') ||
            combined.contains('hemşire') ||
            combined.contains('doktor') ||
            combined.contains('tabip')) {
          _collectUserDocUids(doc, infirmaryUids);
        }
      }
    } catch (_) {}
    return infirmaryUids.toList();
  }

  /// Öğrencinin veli kullanıcı hesaplarının UID'lerini çözümler (şifreli/açık TC, studentIds ve username destekli)
  Future<List<String>> resolveParentRecipientUids({
    required String institutionId,
    required String studentId,
  }) async {
    if (studentId.isEmpty) return const [];
    final Set<String> parentUids = {};

    try {
      final stDoc = await _db.collection('students').doc(studentId).get();
      final sd = stDoc.data() ?? const <String, dynamic>{};

      final Set<String> parentCandidateTcs = {};
      final Set<String> parentUsernames = {};

      if (sd['parentTcNos'] is Iterable) {
        for (final raw in (sd['parentTcNos'] as Iterable)) {
          final s = raw.toString().trim();
          if (s.isNotEmpty) {
            parentCandidateTcs.add(s);
            final dec = CryptoService.decrypt(s, institutionId: institutionId);
            if (dec.isNotEmpty) parentCandidateTcs.add(dec);
          }
        }
      }
      if (sd['parents'] is Iterable) {
        for (final p in (sd['parents'] as Iterable)) {
          if (p is! Map) continue;
          final rawTc = (p['tcNo'] ?? '').toString().trim();
          if (rawTc.isNotEmpty) {
            parentCandidateTcs.add(rawTc);
            final dec = CryptoService.decrypt(
              rawTc,
              institutionId: institutionId,
            );
            if (dec.isNotEmpty) parentCandidateTcs.add(dec);
          }
          final uname = (p['username'] ?? p['email'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          if (uname.isNotEmpty) parentUsernames.add(uname);
        }
      }

      final usersSnap = await _db
          .collection('users')
          .where('institutionId', whereIn: _instVariants(institutionId))
          .get();

      for (final doc in usersSnap.docs) {
        final u = doc.data();
        if (u['isActive'] == false) continue;
        final rNorm = _normTr((u['role'] ?? '').toString());
        final isParentRole = rNorm == 'veli' || rNorm == 'parent';

        final linkedSingle =
            (u['studentId'] ?? '').toString().trim() == studentId;
        final linkedList =
            u['studentIds'] is Iterable &&
            (u['studentIds'] as Iterable)
                .map((e) => e.toString())
                .contains(studentId);

        final uTcRaw = (u['tcNo'] ?? u['tcKimlik'] ?? '').toString().trim();
        final uTcDec = uTcRaw.isNotEmpty
            ? CryptoService.decrypt(uTcRaw, institutionId: institutionId)
            : '';
        final tcMatched =
            (uTcRaw.isNotEmpty && parentCandidateTcs.contains(uTcRaw)) ||
            (uTcDec.isNotEmpty && parentCandidateTcs.contains(uTcDec));

        final uName = (u['username'] ?? '').toString().trim().toLowerCase();
        final uMail = (u['email'] ?? '').toString().trim().toLowerCase();
        final unameMatched =
            (uName.isNotEmpty && parentUsernames.contains(uName)) ||
            (uMail.isNotEmpty && parentUsernames.contains(uMail));

        if (linkedSingle ||
            linkedList ||
            (isParentRole && (tcMatched || unameMatched))) {
          _collectUserDocUids(doc, parentUids);
        }
      }
    } catch (_) {}

    return parentUids.toList();
  }

  /// Hem FCM Push (`notificationRequests`) hem de uygulama içi anlık bildirim kutusu (`notifications/{uid}/items`)
  /// üzerinden yalnızca hedef alıcılara (`recipientUids`) ve ilgili Okul Türü (`schoolTypeId`) kapsamında bildirim iletir.
  /// Genel Kısım (`activities` koleksiyonu) kirletilmez.
  Future<void> dispatchNotification({
    required String institutionId,
    required String schoolTypeId,
    required List<String> recipientUids,
    required String title,
    required String message,
    required String type,
    String entityId = '',
    String route = '/school-dashboard',
    bool publishToActivityStream = false,
    List<String>? activityTargetRoles,
  }) async {
    final cleanUids = recipientUids
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    if (cleanUids.isEmpty) return;

    final resolvedStId = schoolTypeId.trim().isNotEmpty
        ? schoolTypeId.trim()
        : await resolveDefaultSchoolTypeId(institutionId: institutionId);

    // 1. Cloud Function FCM tetikleyicisi (`notificationRequests`)
    try {
      await _db.collection('notificationRequests').add({
        'institutionId': institutionId,
        'schoolTypeId': resolvedStId,
        'recipientUids': cleanUids,
        'teacherIds': cleanUids,
        'title': title,
        'message': message,
        'type': type,
        'category': 'gate_movement',
        'isOperationalNotification': true,
        'route': route,
        'entityId': entityId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    // 2. Anlık uygulama içi bildirim kartı (`notifications/{uid}/items`)
    try {
      final batch = _db.batch();
      for (final uid in cleanUids) {
        final itemRef = _db
            .collection('notifications')
            .doc(uid)
            .collection('items')
            .doc();
        batch.set(itemRef, {
          'institutionId': institutionId,
          'schoolTypeId': resolvedStId,
          'category': 'gate_movement',
          'isOperationalNotification': true,
          'title': title,
          'body': message,
          'type': type,
          'route': route,
          'entityId': entityId,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // YOKLAMA SİSTEMİ (`lessonAttendance`) OTOMATİK İŞLEME MOTORU
  // ═══════════════════════════════════════════════════════════════════════════

  /// Belirtilen ders saatleri için öğrencinin `lessonAttendance` durumunu (`'excused'`, `'late'`, `'onDuty'`)
  /// diğer öğrencilerin yoklama verilerini bozmadan (`SetOptions(merge: true)`) otomatik yazar.
  Future<List<int>> writeStudentAttendanceForHours({
    required String institutionId,
    required String schoolTypeId,
    required String classId,
    required String className,
    required String studentId,
    required DateTime date,
    required List<int> targetHours,
    required String statusKey, // 'excused' | 'late' | 'onDuty'
    required String methodTag,
  }) async {
    if (classId.isEmpty || studentId.isEmpty || targetHours.isEmpty) {
      return const [];
    }

    final schedule = await resolveTodayScheduleForStudent(
      institutionId: institutionId,
      schoolTypeId: schoolTypeId,
      classId: classId,
      studentId: studentId,
      referenceTime: date,
    );

    final periodId = schedule.periodId;
    if (periodId.isEmpty) return const [];

    final dateStr = formatDateYmd(date);
    final writtenHours = <int>[];
    final targetSet = targetHours.toSet();

    try {
      final batch = _db.batch();
      for (final slot in schedule.slots) {
        if (!targetSet.contains(slot.lessonHour)) continue;
        if (slot.lessonId.isEmpty) continue;

        final docId =
            '${periodId}_${classId}_${slot.lessonId}_${dateStr}_${slot.lessonHour}';
        final docRef = _db.collection('lessonAttendance').doc(docId);

        batch.set(docRef, {
          'id': docId,
          'institutionId': institutionId.toUpperCase(),
          'schoolTypeId': schoolTypeId,
          'periodId': periodId,
          'classId': classId,
          'className': className,
          'lessonId': slot.lessonId,
          'lessonName': slot.lessonName,
          'date': dateStr,
          'lessonHour': slot.lessonHour,
          'allowedLessonHours': [slot.lessonHour],
          'studentStatuses': {studentId: statusKey},
          'method': methodTag,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        writtenHours.add(slot.lessonHour);
      }
      if (writtenHours.isNotEmpty) {
        await batch.commit();
      }
    } catch (_) {}

    return writtenHours;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. GEÇ KAĞIDI VERME İŞ AKIŞI
  // ═══════════════════════════════════════════════════════════════════════════
  Future<StudentMovementRecord> issueLateSlip({
    required String institutionId,
    required String schoolTypeId,
    required String schoolTypeName,
    required Map<String, dynamic> student,
    required ResolvedLessonSlot targetSlot,
    required String reason,
    String notes = '',
    bool markLateInAttendance = true,
  }) async {
    final schoolDocId = await resolveSchoolDocId(institutionId);
    final actor = await resolveCurrentActor();
    final now = DateTime.now();
    final dateStr = formatDateYmd(now);
    final timeStr = DateFormat('HH:mm').format(now);

    final studentId = (student['id'] ?? '').toString();
    final studentName = _extractStudentName(student);
    final studentNo = _extractStudentNo(student);
    final classId = (student['classId'] ?? '').toString();
    final className = (student['className'] ?? '').toString();

    final docRef = _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('studentMovements')
        .doc();

    final record = StudentMovementRecord(
      id: docRef.id,
      institutionId: institutionId,
      schoolDocId: schoolDocId,
      schoolTypeId: schoolTypeId,
      schoolTypeName: schoolTypeName,
      dateStr: dateStr,
      type: StudentMovementType.lateSlip,
      status: StudentMovementStatus.issuedLate,
      studentId: studentId,
      studentName: studentName,
      studentNo: studentNo,
      classId: classId,
      className: className,
      bloodType: (student['bloodType'] ?? '').toString(),
      parentName: _extractParentName(student),
      parentPhone: _extractParentPhone(student),
      lessonHour: targetSlot.lessonHour,
      coveredLessonHours: [targetSlot.lessonHour],
      lessonId: targetSlot.lessonId,
      lessonName: targetSlot.lessonName,
      lessonStartTime: targetSlot.startTime,
      lessonEndTime: targetSlot.endTime,
      targetTeacherIds: targetSlot.teacherIds,
      targetTeacherNames: targetSlot.teacherNames,
      reason: reason,
      notes: notes,
      createdByUid: actor.uid,
      createdByName: actor.name,
      createdByRole: actor.role,
      createdAt: now,
    );

    await docRef.set(record.toMap());

    // Yoklamaya otomatik 'late' (Geç) işle
    if (markLateInAttendance && targetSlot.lessonId.isNotEmpty) {
      await writeStudentAttendanceForHours(
        institutionId: institutionId,
        schoolTypeId: schoolTypeId,
        classId: classId,
        className: className,
        studentId: studentId,
        date: now,
        targetHours: [targetSlot.lessonHour],
        statusKey: 'late',
        methodTag: 'late_slip',
      );
    }

    // Dersi olan öğretmene anlık bildirim gönder
    final teacherUids = await resolveTeacherRecipientUids(
      institutionId: institutionId,
      teacherIds: targetSlot.teacherIds,
      teacherNames: targetSlot.teacherNames,
    );

    await dispatchNotification(
      institutionId: institutionId,
      schoolTypeId: schoolTypeId,
      recipientUids: teacherUids,
      title: '🕐 Geç Kağıdı Verildi ($className)',
      message:
          '$className sınıfından $studentName saat $timeStr\'de okula gelmiştir (${reason.isNotEmpty ? reason : "Geç geliş"}). ${targetSlot.lessonHour}. dersinize (${targetSlot.lessonName}) geç kağıdı ile yönlendirilmiştir; derse alınması rica olunur.',
      type: 'student_late_slip',
      entityId: record.id,
    );

    return record;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. ÖĞRENCİ ÇIKIŞ İZNİ & GÜVENLİK KAPI ONAYI İŞ AKIŞI
  // ═══════════════════════════════════════════════════════════════════════════
  Future<StudentMovementRecord> issueExitPermission({
    required String institutionId,
    required String schoolTypeId,
    required String schoolTypeName,
    required Map<String, dynamic> student,
    required int startLessonHour,
    required List<int> remainingHours,
    required String exitMode,
    required String reason,
    String receiverName = '',
    String receiverRelation = '',
    String receiverPhone = '',
    String plannedExitTime = '',
    String notes = '',
    ResolvedLessonSlot? currentSlot,
  }) async {
    final schoolDocId = await resolveSchoolDocId(institutionId);
    final actor = await resolveCurrentActor();
    final now = DateTime.now();
    final dateStr = formatDateYmd(now);
    final effTime = plannedExitTime.trim().isNotEmpty
        ? plannedExitTime.trim()
        : DateFormat('HH:mm').format(now);

    final studentId = (student['id'] ?? '').toString();
    final studentName = _extractStudentName(student);
    final studentNo = _extractStudentNo(student);
    final classId = (student['classId'] ?? '').toString();
    final className = (student['className'] ?? '').toString();

    final docRef = _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('studentMovements')
        .doc();

    final record = StudentMovementRecord(
      id: docRef.id,
      institutionId: institutionId,
      schoolDocId: schoolDocId,
      schoolTypeId: schoolTypeId,
      schoolTypeName: schoolTypeName,
      dateStr: dateStr,
      type: StudentMovementType.exitPermission,
      status: StudentMovementStatus.pendingGate,
      studentId: studentId,
      studentName: studentName,
      studentNo: studentNo,
      classId: classId,
      className: className,
      bloodType: (student['bloodType'] ?? '').toString(),
      parentName: _extractParentName(student),
      parentPhone: _extractParentPhone(student),
      lessonHour: startLessonHour,
      coveredLessonHours: remainingHours,
      lessonId: currentSlot?.lessonId ?? '',
      lessonName: currentSlot?.lessonName ?? '',
      lessonStartTime: currentSlot?.startTime ?? '',
      lessonEndTime: currentSlot?.endTime ?? '',
      targetTeacherIds: currentSlot?.teacherIds ?? const [],
      targetTeacherNames: currentSlot?.teacherNames ?? const [],
      reason: reason,
      notes: notes,
      exitMode: exitMode,
      receiverName: receiverName,
      receiverRelation: receiverRelation,
      receiverPhone: receiverPhone,
      plannedExitTime: effTime,
      createdByUid: actor.uid,
      createdByName: actor.name,
      createdByRole: actor.role,
      createdAt: now,
    );

    await docRef.set(record.toMap());

    // Uygulama Ayarlarındaki "Öğrenci Çıkış İzni Verildiğinde" bildirim tercihlerini oku
    final notifSettings = await loadGateNotificationSettings(
      institutionId: institutionId,
      schoolDocId: schoolDocId,
      schoolTypeId: schoolTypeId,
    );
    final permCfg = notifSettings.studentExitPermission;
    if (permCfg.enabled) {
      final receiverInfo = receiverName.trim().isNotEmpty
          ? ' • Teslim Alan: $receiverName${receiverRelation.isNotEmpty ? " ($receiverRelation)" : ""}'
          : ' • Çıkış Şekli: $exitMode';

      // 1. Güvenlik + Müdür + Müdür Yardımcısı (yalnızca seçili gruplar ve bu Okul Türü)
      final roleUids = await resolveScopedRoleRecipients(
        institutionId: institutionId,
        schoolTypeId: schoolTypeId,
        includeMudur: permCfg.isRecipientEnabled('mudur'),
        includeMudurYardimcisi: permCfg.isRecipientEnabled('mudur_yardimcisi'),
        includeGuvenlik: permCfg.isRecipientEnabled('guvenlik'),
      );
      if (roleUids.isNotEmpty) {
        await dispatchNotification(
          institutionId: institutionId,
          schoolTypeId: schoolTypeId,
          recipientUids: roleUids,
          title: '🚪 Öğrenci Çıkış İzni — Kapı Onayı Bekleniyor',
          message:
              '$className sınıfından $studentName için saat $effTime itibarıyla çıkış izni verildi$receiverInfo. Öğrenci kapıdan çıkarken onay veriniz.',
          type: 'student_exit_gate_pending',
          entityId: record.id,
        );
      }

      // 2. İlgili Ders Öğretmeni
      if (permCfg.isRecipientEnabled('ogretmen') &&
          currentSlot != null &&
          (currentSlot.teacherIds.isNotEmpty ||
              currentSlot.teacherNames.isNotEmpty)) {
        final tUids = await resolveTeacherRecipientUids(
          institutionId: institutionId,
          teacherIds: currentSlot.teacherIds,
          teacherNames: currentSlot.teacherNames,
        );
        if (tUids.isNotEmpty) {
          await dispatchNotification(
            institutionId: institutionId,
            schoolTypeId: schoolTypeId,
            recipientUids: tUids,
            title: '🚪 Öğrenci Çıkış İzni ($className)',
            message:
                '$className - $studentName için idare tarafından çıkış izni düzenlenmiştir ($reason). Güvenlik kapı çıkış onayından sonra kalan derslerde otomatik izinli sayılacaktır.',
            type: 'student_exit_teacher_info',
            entityId: record.id,
          );
        }
      }

      // 3. Öğrenci Velisi (Ayarlarda açık ise izin verildiği anda da bilgilendirilir)
      if (permCfg.isRecipientEnabled('veli')) {
        final parentUids = await resolveParentRecipientUids(
          institutionId: institutionId,
          studentId: studentId,
        );
        if (parentUids.isNotEmpty) {
          await dispatchNotification(
            institutionId: institutionId,
            schoolTypeId: schoolTypeId,
            recipientUids: parentUids,
            title: '📋 Öğrenci Çıkış İzni Düzenlendi',
            message:
                'Öğrencimiz $studentName ($className) için saat $effTime itibarıyla okul çıkış izni düzenlenmiştir ($reason$receiverInfo).',
            type: 'student_exit_parent_permission',
            entityId: record.id,
            route: '/parent-main',
          );
        }
      }
    }

    return record;
  }

  /// GÜVENLİK KAPI ÇIKIŞ ONAYI:
  /// Güvenlik onayladığı anda:
  /// 1) Kayıt `exited_school` olur, çıkış saati mühürlenir,
  /// 2) O andan sonraki TÜM derslerde öğrenci `lessonAttendance` tablosuna OTOMATİK `excused` (İzinli) yazılır,
  /// 3) Uygulama Ayarlarında seçili olan Müdür, Müdür Yardımcısı, İzni Veren, Ders Öğretmeni ve Veliye bildirim gider!
  Future<List<int>> approveGateExit({
    required StudentMovementRecord record,
    String gateNote = '',
  }) async {
    final actor = await resolveCurrentActor();
    final now = DateTime.now();
    final timeStr = DateFormat('HH:mm').format(now);

    // Çıkış anındaki ve sonraki ders saatlerini hesapla
    final schedule = await resolveTodayScheduleForStudent(
      institutionId: record.institutionId,
      schoolTypeId: record.schoolTypeId,
      classId: record.classId,
      studentId: record.studentId,
      referenceTime: now,
    );

    final startHour = record.lessonHour > 0
        ? (record.lessonHour < schedule.currentLessonHour
              ? record.lessonHour
              : schedule.currentLessonHour)
        : schedule.currentLessonHour;

    final hoursToExcuse = record.coveredLessonHours.isNotEmpty
        ? record.coveredLessonHours
        : [for (int h = startHour; h <= schedule.maxLessonHour; h++) h];

    // Otomatik İZİNLİ ('excused') yaz!
    final writtenHours = await writeStudentAttendanceForHours(
      institutionId: record.institutionId,
      schoolTypeId: record.schoolTypeId,
      classId: record.classId,
      className: record.className,
      studentId: record.studentId,
      date: now,
      targetHours: hoursToExcuse,
      statusKey: 'excused',
      methodTag: 'security_exit_approved',
    );

    final effectiveExcused = writtenHours.isNotEmpty
        ? writtenHours
        : hoursToExcuse;

    final docRef = _db
        .collection('schools')
        .doc(record.schoolDocId)
        .collection('studentMovements')
        .doc(record.id);

    await docRef.update({
      'status': StudentMovementStatus.exitedSchool.firestoreKey,
      'gateApprovedAt': Timestamp.fromDate(now),
      'gateApprovedByUid': actor.uid,
      'gateApprovedByName': actor.name,
      'gateNote': gateNote.trim(),
      'autoExcusedHours': effectiveExcused,
      'completedAt': Timestamp.fromDate(now),
    });

    final notifSettings = await loadGateNotificationSettings(
      institutionId: record.institutionId,
      schoolDocId: record.schoolDocId,
      schoolTypeId: record.schoolTypeId,
    );
    final exitCfg = notifSettings.studentGateExitConfirmed;
    if (exitCfg.enabled) {
      final staffRecipients = <String>{};

      if (exitCfg.isRecipientEnabled('issuer') &&
          record.createdByUid.isNotEmpty) {
        staffRecipients.add(record.createdByUid);
      }

      if (exitCfg.isRecipientEnabled('mudur') ||
          exitCfg.isRecipientEnabled('mudur_yardimcisi')) {
        final managerUids = await resolveScopedRoleRecipients(
          institutionId: record.institutionId,
          schoolTypeId: record.schoolTypeId,
          includeMudur: exitCfg.isRecipientEnabled('mudur'),
          includeMudurYardimcisi: exitCfg.isRecipientEnabled(
            'mudur_yardimcisi',
          ),
          includeGuvenlik: false,
        );
        staffRecipients.addAll(managerUids);
      }

      if (exitCfg.isRecipientEnabled('ogretmen')) {
        final remainingTeacherIds = <String>{};
        final remainingTeacherNames = <String>{};
        for (final slot in schedule.slots) {
          if (effectiveExcused.contains(slot.lessonHour)) {
            remainingTeacherIds.addAll(slot.teacherIds);
            remainingTeacherNames.addAll(slot.teacherNames);
          }
        }
        final teacherUids = await resolveTeacherRecipientUids(
          institutionId: record.institutionId,
          teacherIds: remainingTeacherIds.toList(),
          teacherNames: remainingTeacherNames.toList(),
        );
        staffRecipients.addAll(teacherUids);
      }

      final hoursLabel = effectiveExcused.isNotEmpty
          ? ' (${effectiveExcused.map((h) => "$h.").join(", ")} dersler otomatik İZİNLİ işlendi)'
          : '';
      final isEarly = record.type == StudentMovementType.earlyPickup;

      if (staffRecipients.isNotEmpty) {
        await dispatchNotification(
          institutionId: record.institutionId,
          schoolTypeId: record.schoolTypeId,
          recipientUids: staffRecipients.toList(),
          title: isEarly
              ? '✅ Veliye Erken Teslim Onayı: ${record.studentName}'
              : '✅ Güvenlik Çıkış Onayı: ${record.studentName}',
          message: isEarly
              ? '${record.className} sınıfından ${record.studentName} saat $timeStr\'de güvenlik/idare (${actor.name}) onayıyla velisine teslim edildi$hoursLabel.'
              : '${record.className} sınıfından ${record.studentName} saat $timeStr\'de güvenlik birimi (${actor.name}) onayıyla okuldan çıkış yaptı$hoursLabel.',
          type: 'student_exit_confirmed',
          entityId: record.id,
        );
      }

      if (exitCfg.isRecipientEnabled('veli')) {
        final parentUids = await resolveParentRecipientUids(
          institutionId: record.institutionId,
          studentId: record.studentId,
        );
        if (parentUids.isNotEmpty) {
          await dispatchNotification(
            institutionId: record.institutionId,
            schoolTypeId: record.schoolTypeId,
            recipientUids: parentUids,
            title: isEarly
                ? '✅ Öğrenci Erken Teslim Bilgilendirmesi'
                : '🚪 Öğrenci Okul Çıkış Bilgilendirmesi',
            message: isEarly
                ? 'Öğrencimiz ${record.studentName} (${record.className}), saat $timeStr itibarıyla güvenlik kontrolünden geçerek erken teslim edilmiştir. Kalan derslerde otomatik izinli sayılmıştır.'
                : 'Öğrencimiz ${record.studentName} (${record.className}), verilen çıkış izni kapsamında saat $timeStr itibarıyla güvenlik kontrolünden geçerek okuldan ayrılmıştır. Kalan derslerde izinli sayılmıştır.',
            type: 'student_exit_parent',
            entityId: record.id,
            route: '/parent-main',
          );
        }
      }
    }

    return effectiveExcused;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. REVİR KAĞIDI VERME VE SAĞLIK İŞLEMLERİ (`healthVisits`) TAM ENTEGRASYONU
  // ═══════════════════════════════════════════════════════════════════════════

  /// Öğrenciye Revir Kağıdı verir ve Sağlık İşlemleri (`schools/{schoolDocId}/healthVisits`)
  /// modülünde Revir görevlisinin anında göreceği AÇIK DOSYAYI oluşturur.
  Future<StudentMovementRecord> issueInfirmaryReferral({
    required String institutionId,
    required String schoolTypeId,
    required String schoolTypeName,
    required Map<String, dynamic> student,
    required ResolvedLessonSlot currentSlot,
    required String complaint,
    String urgency = 'Normal',
    String notes = '',
  }) async {
    final schoolDocId = await resolveSchoolDocId(institutionId);
    final actor = await resolveCurrentActor();
    final now = DateTime.now();
    final dateStr = formatDateYmd(now);
    final timeStr = DateFormat('HH:mm').format(now);

    final studentId = (student['id'] ?? '').toString();
    final studentName = _extractStudentName(student);
    final studentNo = _extractStudentNo(student);
    final classId = (student['classId'] ?? '').toString();
    final className = (student['className'] ?? '').toString();
    final bloodType = (student['bloodType'] ?? '').toString();

    final movRef = _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('studentMovements')
        .doc();

    final healthVisitRef = _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('healthVisits')
        .doc();

    // 1. Sağlık İşlemleri (Revir) modülünde açık dosya oluştur (`CryptoService` şifrelemeli)
    await healthVisitRef.set({
      'studentId': studentId,
      'studentNo': studentNo,
      'classId': classId,
      'className': className,
      'bloodType': bloodType,
      'studentName': className.isNotEmpty
          ? '$studentName ($className)'
          : studentName,
      'complaint': CryptoService.encrypt(
        complaint.trim(),
        institutionId: institutionId,
      ),
      'treatment': CryptoService.encrypt('', institutionId: institutionId),
      'medicationGiven': false,
      'medicationName': CryptoService.encrypt('', institutionId: institutionId),
      'notes': CryptoService.encrypt(
        notes.trim(),
        institutionId: institutionId,
      ),
      'visitDate': Timestamp.fromDate(now),
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': FirebaseAuth.instance.currentUser?.email ?? actor.name,
      'schoolTypeId': schoolTypeId,
      'institutionId': institutionId,
      // Entegrasyon & durum takip alanları
      'visitStatus': 'open', // Revirde işlem bekliyor!
      'urgency': urgency,
      'referralMovementId': movRef.id,
      'referredByUid': actor.uid,
      'referredByName': actor.name,
      'referredByRole': actor.role,
      'lessonHour': currentSlot.lessonHour,
      'lessonId': currentSlot.lessonId,
      'lessonName': currentSlot.lessonName,
      'targetTeacherIds': currentSlot.teacherIds,
      'targetTeacherNames': currentSlot.teacherNames,
    });

    // 2. Canlı Öğrenci Hareket kaydını oluştur
    final record = StudentMovementRecord(
      id: movRef.id,
      institutionId: institutionId,
      schoolDocId: schoolDocId,
      schoolTypeId: schoolTypeId,
      schoolTypeName: schoolTypeName,
      dateStr: dateStr,
      type: StudentMovementType.infirmary,
      status: StudentMovementStatus.inInfirmary,
      studentId: studentId,
      studentName: studentName,
      studentNo: studentNo,
      classId: classId,
      className: className,
      bloodType: bloodType,
      parentName: _extractParentName(student),
      parentPhone: _extractParentPhone(student),
      lessonHour: currentSlot.lessonHour,
      coveredLessonHours: [currentSlot.lessonHour],
      lessonId: currentSlot.lessonId,
      lessonName: currentSlot.lessonName,
      lessonStartTime: currentSlot.startTime,
      lessonEndTime: currentSlot.endTime,
      targetTeacherIds: currentSlot.teacherIds,
      targetTeacherNames: currentSlot.teacherNames,
      reason: complaint.trim(),
      notes: notes.trim(),
      urgency: urgency,
      healthVisitId: healthVisitRef.id,
      createdByUid: actor.uid,
      createdByName: actor.name,
      createdByRole: actor.role,
      createdAt: now,
    );

    await movRef.set(record.toMap());

    // 3. Revir birimine + mevcut ders öğretmenine bildirim gönder
    final infirmaryUids = await resolveInfirmaryRecipientUids(
      institutionId: institutionId,
    );
    final teacherUids = await resolveTeacherRecipientUids(
      institutionId: institutionId,
      teacherIds: currentSlot.teacherIds,
      teacherNames: currentSlot.teacherNames,
    );

    if (infirmaryUids.isNotEmpty) {
      await dispatchNotification(
        institutionId: institutionId,
        schoolTypeId: schoolTypeId,
        recipientUids: infirmaryUids,
        title: '🏥 Yeni Revir Sevki${urgency == "Acil" ? " (ACİL)" : ""}',
        message:
            '$className sınıfından $studentName saat $timeStr\'de "${complaint.trim()}" şikayetiyle (${actor.name} tarafından) revire yönlendirildi. Açık dosyaya işlem girebilirsiniz.',
        type: 'infirmary_referral_new',
        entityId: healthVisitRef.id,
        publishToActivityStream: true,
      );
    }

    if (teacherUids.isNotEmpty) {
      await dispatchNotification(
        institutionId: institutionId,
        schoolTypeId: schoolTypeId,
        recipientUids: teacherUids.where((u) => u != actor.uid).toList(),
        title: '🏥 Öğrenci Revirde ($className)',
        message:
            '$className - $studentName saat $timeStr itibarıyla revire sevk edilmiştir ("${complaint.trim()}"). İşlem tamamlandığında tarafınıza bilgi verilecektir.',
        type: 'infirmary_teacher_notice',
        entityId: record.id,
      );
    }

    return record;
  }

  /// REVİR İŞLEM TAMAMLAMA (Hem Sağlık İşlemleri `HealthScreen` ekranından hem Hareket Merkezinden çağrılır):
  /// Açık revir dosyasına yapılan müdahaleyi yazar, dosyayı kapatır ve:
  /// 1) VELİYE,
  /// 2) REVİRE YÖNLENDİRENE (`referredByUid`),
  /// 3) DERS SAATİNDEYSE O ANKİ DERS ÖĞRETMENİNE
  /// ne yapıldığını içeren otomatik bildirim gönderir!
  Future<void> completeInfirmaryVisit({
    required String institutionId,
    required String schoolDocId,
    required String healthVisitId,
    String? movementId,
    required String treatment,
    bool medicationGiven = false,
    String medicationName = '',
    String notes = '',
    String outcome =
        'Derse Döndü', // 'Derse Döndü' | 'İstirahat Sonrası Derse Döndü' | 'Veliye Teslim / Eve Sevk'
  }) async {
    final actor = await resolveCurrentActor();
    final now = DateTime.now();
    final timeStr = DateFormat('HH:mm').format(now);

    // 1. healthVisits dokümanını oku ve güncelle
    final visitRef = _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('healthVisits')
        .doc(healthVisitId);
    final visitSnap = await visitRef.get();
    final vData = visitSnap.data() ?? const <String, dynamic>{};

    final effMovementId = (movementId != null && movementId.isNotEmpty)
        ? movementId
        : (vData['referralMovementId'] ?? '').toString();
    final schoolTypeId = (vData['schoolTypeId'] ?? '').toString();
    final studentId = (vData['studentId'] ?? '').toString();
    final classId = (vData['classId'] ?? '').toString();
    final className = (vData['className'] ?? '').toString();
    final rawStudentName = (vData['studentName'] ?? 'Öğrenci').toString();
    final cleanStudentName = rawStudentName.contains('(')
        ? rawStudentName.split('(').first.trim()
        : rawStudentName;
    final complaintPlain = CryptoService.decrypt(
      vData['complaint']?.toString(),
      institutionId: institutionId,
    );
    final referredByUid = (vData['referredByUid'] ?? '').toString();

    await visitRef.set({
      'treatment': CryptoService.encrypt(
        treatment.trim(),
        institutionId: institutionId,
      ),
      'medicationGiven': medicationGiven,
      'medicationName': CryptoService.encrypt(
        medicationGiven ? medicationName.trim() : '',
        institutionId: institutionId,
      ),
      'notes': CryptoService.encrypt(
        notes.trim(),
        institutionId: institutionId,
      ),
      'visitStatus': 'completed',
      'outcome': outcome,
      'handledByUid': actor.uid,
      'handledByName': actor.name,
      'completedAt': Timestamp.fromDate(now),
    }, SetOptions(merge: true));

    // 2. Eşleşen studentMovements kaydını güncelle
    List<String> origTeacherIds = const [];
    List<String> origTeacherNames = const [];
    String effectiveReferredByUid = referredByUid;

    if (effMovementId.isNotEmpty) {
      final movRef = _db
          .collection('schools')
          .doc(schoolDocId)
          .collection('studentMovements')
          .doc(effMovementId);
      final movSnap = await movRef.get();
      if (movSnap.exists) {
        final rec = StudentMovementRecord.fromDoc(movSnap);
        origTeacherIds = rec.targetTeacherIds;
        origTeacherNames = rec.targetTeacherNames;
        if (effectiveReferredByUid.isEmpty) {
          effectiveReferredByUid = rec.createdByUid;
        }
        await movRef.update({
          'status': StudentMovementStatus.completed.firestoreKey,
          'infirmaryTreatment': treatment.trim(),
          'medicationGiven': medicationGiven,
          'medicationName': medicationGiven ? medicationName.trim() : '',
          'infirmaryOutcome': outcome,
          'handledByInfirmaryName': actor.name,
          if (notes.trim().isNotEmpty) 'notes': notes.trim(),
          'completedAt': Timestamp.fromDate(now),
        });
      }
    }

    final medSummary = (medicationGiven && medicationName.trim().isNotEmpty)
        ? ' • İlaç/Uygulama: ${medicationName.trim()}'
        : '';
    final actionSummary =
        'Yapılan işlem: ${treatment.trim()}$medSummary • Sonuç: $outcome.';

    // 3A. VELİYE BİLDİRİM GÖNDER
    if (studentId.isNotEmpty) {
      final parentUids = await resolveParentRecipientUids(
        institutionId: institutionId,
        studentId: studentId,
      );
      if (parentUids.isNotEmpty) {
        await dispatchNotification(
          institutionId: institutionId,
          schoolTypeId: schoolTypeId,
          recipientUids: parentUids,
          title: '🏥 Revir / Sağlık İşlemi Bilgilendirmesi',
          message:
              'Öğrencimiz $cleanStudentName${className.isNotEmpty ? " ($className)" : ""}${complaintPlain.isNotEmpty ? ", \"$complaintPlain\" şikayetiyle" : ""} okul revirimizde değerlendirilmiştir ($timeStr). $actionSummary',
          type: 'infirmary_completed_parent',
          entityId: healthVisitId,
        );
      }
    }

    // 3B. REVİRE YÖNLENDİRENE BİLDİRİM GÖNDER
    if (effectiveReferredByUid.isNotEmpty) {
      await dispatchNotification(
        institutionId: institutionId,
        schoolTypeId: schoolTypeId,
        recipientUids: [effectiveReferredByUid],
        title: '✅ Revir İşlemi Tamamlandı ($cleanStudentName)',
        message:
            'Revire yönlendirdiğiniz $cleanStudentName${className.isNotEmpty ? " ($className)" : ""} için sağlık işlemi saat $timeStr\'de tamamlandı. $actionSummary',
        type: 'infirmary_completed_referrer',
        entityId: healthVisitId,
      );
    }

    // 3C. DERS SAATİNDEYSE O ANKİ DERS ÖĞRETMENİNE (+ Sevk anındaki öğretmene) BİLDİRİM GÖNDER
    final Set<String> allTeacherIds = {...origTeacherIds};
    final Set<String> allTeacherNames = {...origTeacherNames};

    if (classId.isNotEmpty) {
      final liveSchedule = await resolveTodayScheduleForStudent(
        institutionId: institutionId,
        schoolTypeId: schoolTypeId,
        classId: classId,
        studentId: studentId,
        referenceTime: now,
      );
      final activeSlot = liveSchedule.slots.where(
        (s) => s.lessonHour == liveSchedule.currentLessonHour,
      );
      if (activeSlot.isNotEmpty) {
        allTeacherIds.addAll(activeSlot.first.teacherIds);
        allTeacherNames.addAll(activeSlot.first.teacherNames);
      }
    }

    final teacherUids = await resolveTeacherRecipientUids(
      institutionId: institutionId,
      teacherIds: allTeacherIds.toList(),
      teacherNames: allTeacherNames.toList(),
    );

    final distinctTeacherUids = teacherUids
        .where((uid) => uid != effectiveReferredByUid)
        .toList();

    if (distinctTeacherUids.isNotEmpty) {
      await dispatchNotification(
        institutionId: institutionId,
        schoolTypeId: schoolTypeId,
        recipientUids: distinctTeacherUids,
        title: '🏥 Revir İşlemi Tamamlandı ($className)',
        message:
            '$className - $cleanStudentName revir işlemini saat $timeStr\'de tamamlamıştır. $actionSummary',
        type: 'infirmary_completed_teacher',
        entityId: healthVisitId,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. ÖĞRENCİ GÖRÜŞME BİLDİRİMİ & YOK YAZILMAMA KORUMASI İŞ AKIŞI
  // ═══════════════════════════════════════════════════════════════════════════
  Future<StudentMovementRecord> startStudentInterview({
    required String institutionId,
    required String schoolTypeId,
    required String schoolTypeName,
    required Map<String, dynamic> student,
    required List<ResolvedLessonSlot> coveredSlots,
    required String interviewUnit,
    required String interviewerName,
    required String reason,
    String notes = '',
    bool protectAttendance = true,
  }) async {
    final schoolDocId = await resolveSchoolDocId(institutionId);
    final actor = await resolveCurrentActor();
    final now = DateTime.now();
    final dateStr = formatDateYmd(now);
    final timeStr = DateFormat('HH:mm').format(now);

    final studentId = (student['id'] ?? '').toString();
    final studentName = _extractStudentName(student);
    final studentNo = _extractStudentNo(student);
    final classId = (student['classId'] ?? '').toString();
    final className = (student['className'] ?? '').toString();

    final coveredHours = coveredSlots.map((s) => s.lessonHour).toList()..sort();
    final firstHour = coveredHours.isNotEmpty ? coveredHours.first : 1;
    final lessonNames = coveredSlots
        .map((s) => '${s.lessonHour}. Ders (${s.lessonName})')
        .join(', ');

    final tIds = <String>{
      for (final s in coveredSlots) ...s.teacherIds,
    }.toList();
    final tNames = <String>{
      for (final s in coveredSlots) ...s.teacherNames,
    }.toList();

    final docRef = _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('studentMovements')
        .doc();

    final effInterviewer = interviewerName.trim().isNotEmpty
        ? interviewerName.trim()
        : actor.name;

    final record = StudentMovementRecord(
      id: docRef.id,
      institutionId: institutionId,
      schoolDocId: schoolDocId,
      schoolTypeId: schoolTypeId,
      schoolTypeName: schoolTypeName,
      dateStr: dateStr,
      type: StudentMovementType.interview,
      status: StudentMovementStatus.inMeeting,
      studentId: studentId,
      studentName: studentName,
      studentNo: studentNo,
      classId: classId,
      className: className,
      bloodType: (student['bloodType'] ?? '').toString(),
      parentName: _extractParentName(student),
      parentPhone: _extractParentPhone(student),
      lessonHour: firstHour,
      coveredLessonHours: coveredHours,
      lessonId: coveredSlots.isNotEmpty ? coveredSlots.first.lessonId : '',
      lessonName: lessonNames,
      lessonStartTime: coveredSlots.isNotEmpty
          ? coveredSlots.first.startTime
          : '',
      lessonEndTime: coveredSlots.isNotEmpty ? coveredSlots.last.endTime : '',
      targetTeacherIds: tIds,
      targetTeacherNames: tNames,
      reason: reason.trim(),
      notes: notes.trim(),
      interviewUnit: interviewUnit,
      interviewerName: effInterviewer,
      protectAttendance: protectAttendance,
      createdByUid: actor.uid,
      createdByName: actor.name,
      createdByRole: actor.role,
      createdAt: now,
    );

    await docRef.set(record.toMap());

    // Çocuk derse gelmeyeceği için YOK YAZILMASIN -> Yoklamada otomatik 'excused' (İzinli) olarak koruma altına al!
    if (protectAttendance && coveredHours.isNotEmpty) {
      await writeStudentAttendanceForHours(
        institutionId: institutionId,
        schoolTypeId: schoolTypeId,
        classId: classId,
        className: className,
        studentId: studentId,
        date: now,
        targetHours: coveredHours,
        statusKey: 'excused',
        methodTag: 'interview_excused',
      );
    }

    // İlgili ders öğretmen(ler)ine nerede olduğunu bildir
    final teacherUids = await resolveTeacherRecipientUids(
      institutionId: institutionId,
      teacherIds: tIds,
      teacherNames: tNames,
    );

    await dispatchNotification(
      institutionId: institutionId,
      schoolTypeId: schoolTypeId,
      recipientUids: teacherUids,
      title: '🗣️ Öğrenci Görüşmede — Yok Yazmayınız ($className)',
      message:
          '$className sınıfından $studentName, saat $timeStr itibarıyla "$interviewUnit" ($effInterviewer) kapsamında görüşmededir (${coveredHours.map((h) => "$h.").join(", ")} ders). Yoklamada izinli olarak işaretlenmiştir; yok yazılmaması rica olunur.',
      type: 'student_interview_started',
      entityId: record.id,
    );

    return record;
  }

  /// Görüşmeyi sonlandırıp öğrenciyi derse yönlendirir ve öğretmene bilgi verir
  Future<void> completeStudentInterview(StudentMovementRecord record) async {
    final now = DateTime.now();
    final timeStr = DateFormat('HH:mm').format(now);

    await _db
        .collection('schools')
        .doc(record.schoolDocId)
        .collection('studentMovements')
        .doc(record.id)
        .update({
          'status': StudentMovementStatus.completed.firestoreKey,
          'completedAt': Timestamp.fromDate(now),
        });

    // Şu anki dersin öğretmenine derse döndüğünü bildir
    final liveSchedule = await resolveTodayScheduleForStudent(
      institutionId: record.institutionId,
      schoolTypeId: record.schoolTypeId,
      classId: record.classId,
      studentId: record.studentId,
      referenceTime: now,
    );
    final activeSlot = liveSchedule.slots.where(
      (s) => s.lessonHour == liveSchedule.currentLessonHour,
    );

    final teacherUids = await resolveTeacherRecipientUids(
      institutionId: record.institutionId,
      teacherIds: [
        ...record.targetTeacherIds,
        if (activeSlot.isNotEmpty) ...activeSlot.first.teacherIds,
      ],
      teacherNames: [
        ...record.targetTeacherNames,
        if (activeSlot.isNotEmpty) ...activeSlot.first.teacherNames,
      ],
    );

    if (teacherUids.isNotEmpty) {
      await dispatchNotification(
        institutionId: record.institutionId,
        schoolTypeId: record.schoolTypeId,
        recipientUids: teacherUids,
        title: '✅ Görüşme Tamamlandı — Öğrenci Derse Dönüyor',
        message:
            '${record.className} - ${record.studentName} ile yapılan görüşme saat $timeStr itibarıyla tamamlanmış olup öğrenci sınıfına/dersine yönlendirilmiştir.',
        type: 'student_interview_completed',
        entityId: record.id,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. VELİ ERKEN ALMA & "OKULA GELDİM" ANLIK ÇAĞRI SİSTEMİ
  // ═══════════════════════════════════════════════════════════════════════════

  /// Tek bir öğrencinin bugünkü Erken Alma / Çıkış hareketlerini canlı izler (Veli Paneli için)
  Stream<List<StudentMovementRecord>> watchStudentEarlyPickupsForToday({
    required String schoolDocId,
    required String studentId,
    String? dateStr,
  }) {
    if (schoolDocId.isEmpty || studentId.isEmpty) {
      return Stream.value(const []);
    }
    final effDate = dateStr ?? formatDateYmd(DateTime.now());
    return _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('studentMovements')
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => StudentMovementRecord.fromDoc(d))
              .where(
                (r) =>
                    r.dateStr == effDate &&
                    (r.type == StudentMovementType.earlyPickup ||
                        r.type == StudentMovementType.exitPermission),
              )
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  /// Veli veya İdare tarafından **Erken Alma** kaydı oluşturur:
  /// - `arrivedNow == false`: Veli önceden haber verdi ("Saat 14:30'da alacağım") -> İdare + Güvenlik + Sınıf/Ders öğretmenine ön bilgi gider.
  /// - `arrivedNow == true`: Veli şu an okula geldi ("Okula Geldim, öğrencimi hazırlayın") -> Dersi olan öğretmene + İdareye + Güvenliğe ANLIK ÇAĞRI gider!
  Future<StudentMovementRecord> createEarlyPickupNotice({
    required String institutionId,
    required String schoolTypeId,
    required String schoolTypeName,
    required Map<String, dynamic> student,
    required int targetLessonHour,
    required List<int> remainingHours,
    required String reason,
    String plannedPickupTime = '',
    String receiverName = '',
    String receiverRelation = 'Velisi',
    String receiverPhone = '',
    String vehiclePlate = '',
    String notes = '',
    bool arrivedNow = false,
    String requestSource = 'parent_portal',
    ResolvedLessonSlot? targetSlot,
  }) async {
    final schoolDocId = await resolveSchoolDocId(institutionId);
    final actor = await resolveCurrentActor();
    final now = DateTime.now();
    final dateStr = formatDateYmd(now);
    final nowTimeStr = DateFormat('HH:mm').format(now);
    final effPlannedTime = plannedPickupTime.trim().isNotEmpty
        ? plannedPickupTime.trim()
        : nowTimeStr;

    final studentId = (student['id'] ?? '').toString();
    final studentName = _extractStudentName(student);
    final studentNo = _extractStudentNo(student);
    final classId = (student['classId'] ?? '').toString();
    final className = (student['className'] ?? '').toString();
    final effReceiver = receiverName.trim().isNotEmpty
        ? receiverName.trim()
        : (_extractParentName(student).isNotEmpty
              ? _extractParentName(student)
              : actor.name);
    final effPhone = receiverPhone.trim().isNotEmpty
        ? receiverPhone.trim()
        : _extractParentPhone(student);

    // Eğer slot dışarıdan gelmediyse otomatik çözümle
    ResolvedLessonSlot resolvedSlot;
    List<int> effRemaining = remainingHours;
    if (targetSlot != null) {
      resolvedSlot = targetSlot;
    } else {
      final sched = await resolveTodayScheduleForStudent(
        institutionId: institutionId,
        schoolTypeId: schoolTypeId,
        classId: classId,
        studentId: studentId,
        referenceTime: now,
      );
      final chosenHour = arrivedNow
          ? sched.currentLessonHour
          : targetLessonHour;
      final match = sched.slots.where((s) => s.lessonHour == chosenHour);
      resolvedSlot = match.isNotEmpty
          ? match.first
          : ResolvedLessonSlot(
              lessonHour: chosenHour,
              lessonId: '',
              lessonName: '$chosenHour. Ders',
            );
      if (effRemaining.isEmpty) {
        effRemaining = [
          for (int h = chosenHour; h <= sched.maxLessonHour; h++) h,
        ];
      }
    }

    final docRef = _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('studentMovements')
        .doc();

    final record = StudentMovementRecord(
      id: docRef.id,
      institutionId: institutionId,
      schoolDocId: schoolDocId,
      schoolTypeId: schoolTypeId,
      schoolTypeName: schoolTypeName,
      dateStr: dateStr,
      type: StudentMovementType.earlyPickup,
      status: arrivedNow
          ? StudentMovementStatus.parentArrived
          : StudentMovementStatus.earlyPickupNotified,
      studentId: studentId,
      studentName: studentName,
      studentNo: studentNo,
      classId: classId,
      className: className,
      bloodType: (student['bloodType'] ?? '').toString(),
      parentName: _extractParentName(student),
      parentPhone: _extractParentPhone(student),
      lessonHour: resolvedSlot.lessonHour,
      coveredLessonHours: effRemaining,
      lessonId: resolvedSlot.lessonId,
      lessonName: resolvedSlot.lessonName,
      lessonStartTime: resolvedSlot.startTime,
      lessonEndTime: resolvedSlot.endTime,
      targetTeacherIds: resolvedSlot.teacherIds,
      targetTeacherNames: resolvedSlot.teacherNames,
      reason: reason.trim(),
      notes: notes.trim(),
      exitMode: 'Veli Eşliğinde Erken Alma',
      receiverName: effReceiver,
      receiverRelation: receiverRelation.trim().isNotEmpty
          ? receiverRelation.trim()
          : 'Velisi',
      receiverPhone: effPhone,
      vehiclePlate: vehiclePlate.trim(),
      plannedExitTime: effPlannedTime,
      parentArrivedAt: arrivedNow ? now : null,
      requestSource: requestSource,
      createdByUid: actor.uid,
      createdByName: actor.name,
      createdByRole: requestSource == 'parent_portal' ? 'Veli' : actor.role,
      createdAt: now,
    );

    await docRef.set(record.toMap());

    final notifSettings = await loadGateNotificationSettings(
      institutionId: institutionId,
      schoolDocId: schoolDocId,
      schoolTypeId: schoolTypeId,
    );
    final earlyCfg = notifSettings.earlyPickupNotice;
    if (earlyCfg.enabled) {
      final roleUids = await resolveScopedRoleRecipients(
        institutionId: institutionId,
        schoolTypeId: schoolTypeId,
        includeMudur: earlyCfg.isRecipientEnabled('mudur'),
        includeMudurYardimcisi: earlyCfg.isRecipientEnabled('mudur_yardimcisi'),
        includeGuvenlik: earlyCfg.isRecipientEnabled('guvenlik'),
      );
      final teacherUids = earlyCfg.isRecipientEnabled('ogretmen')
          ? await resolveTeacherRecipientUids(
              institutionId: institutionId,
              teacherIds: resolvedSlot.teacherIds,
              teacherNames: resolvedSlot.teacherNames,
            )
          : const <String>[];

      final plateLabel = vehiclePlate.trim().isNotEmpty
          ? ' • Plaka/Not: ${vehiclePlate.trim()}'
          : '';

      if (arrivedNow) {
        if (teacherUids.isNotEmpty) {
          await dispatchNotification(
            institutionId: institutionId,
            schoolTypeId: schoolTypeId,
            recipientUids: teacherUids,
            title: '📍 VELİ OKULA GELDİ — Öğrenciyi Hazırlayınız ($className)',
            message:
                '$className sınıfından $studentName öğrencimizin velisi ($effReceiver) şu an okul kapısına gelmiştir (${resolvedSlot.lessonHour}. Ders - ${resolvedSlot.lessonName} • $reason). Öğrencinin eşyalarıyla çıkış noktasına yönlendirilmesi rica olunur.',
            type: 'early_pickup_parent_arrived_teacher',
            entityId: record.id,
          );
        }

        if (roleUids.isNotEmpty) {
          await dispatchNotification(
            institutionId: institutionId,
            schoolTypeId: schoolTypeId,
            recipientUids: roleUids,
            title: '🚗 Veli Kapıda Bekliyor (Erken Alma): $studentName',
            message:
                '$className sınıfından $studentName için veli ($effReceiver$plateLabel) saat $nowTimeStr itibarıyla okula geldiğini bildirdi. Ders öğretmenine hazırlık çağrısı iletildi; teslimatta kapı onayı veriniz.',
            type: 'early_pickup_parent_arrived_gate',
            entityId: record.id,
          );
        }
      } else {
        final merged = {...roleUids, ...teacherUids}.toList();
        if (merged.isNotEmpty) {
          await dispatchNotification(
            institutionId: institutionId,
            schoolTypeId: schoolTypeId,
            recipientUids: merged,
            title: '📅 Erken Alma Ön Bildirimi ($className - $effPlannedTime)',
            message:
                '$className sınıfından $studentName öğrencimizin velisi ($effReceiver$plateLabel), bugün saat $effPlannedTime civarında (${resolvedSlot.lessonHour}. Ders • $reason) öğrencisini okuldan erken alacağını önceden bildirdi.',
            type: 'early_pickup_advance_notice',
            entityId: record.id,
          );
        }
      }
    }

    return record;
  }

  /// Veli okul kapısına ulaştığında ("📍 OKULA GELDİM" butonuyla veya güvenlik/idare işaretiyle)
  /// öğrencinin **o anki canlı ders öğretmenini** bulup anında hazırlık bildirimi gönderir!
  Future<void> notifyParentArrivedAtSchool({
    required StudentMovementRecord record,
    String arrivalNote = '',
  }) async {
    final now = DateTime.now();
    final timeStr = DateFormat('HH:mm').format(now);

    // Veli planlanandan biraz erken/geç gelmiş olabilir -> ŞU ANKİ canlı ders saatini ve öğretmenini bul!
    final liveSchedule = await resolveTodayScheduleForStudent(
      institutionId: record.institutionId,
      schoolTypeId: record.schoolTypeId,
      classId: record.classId,
      studentId: record.studentId,
      referenceTime: now,
    );

    final liveHour = liveSchedule.currentLessonHour;
    final matched = liveSchedule.slots
        .where((s) => s.lessonHour == liveHour)
        .toList();
    final liveSlot = matched.isNotEmpty
        ? matched.first
        : ResolvedLessonSlot(
            lessonHour: liveHour,
            lessonId: record.lessonId,
            lessonName: record.lessonName.isNotEmpty
                ? record.lessonName
                : '$liveHour. Ders',
            teacherIds: record.targetTeacherIds,
            teacherNames: record.targetTeacherNames,
          );

    final updatedRemaining = [
      for (int h = liveHour; h <= liveSchedule.maxLessonHour; h++) h,
    ];

    final mergedNotes = arrivalNote.trim().isNotEmpty
        ? (record.notes.isNotEmpty
              ? '${record.notes} • Veli Geliş Notu: ${arrivalNote.trim()}'
              : arrivalNote.trim())
        : record.notes;

    await _db
        .collection('schools')
        .doc(record.schoolDocId)
        .collection('studentMovements')
        .doc(record.id)
        .update({
          'status': StudentMovementStatus.parentArrived.firestoreKey,
          'parentArrivedAt': Timestamp.fromDate(now),
          'lessonHour': liveSlot.lessonHour,
          'coveredLessonHours': updatedRemaining,
          'lessonId': liveSlot.lessonId,
          'lessonName': liveSlot.lessonName,
          'lessonStartTime': liveSlot.startTime,
          'lessonEndTime': liveSlot.endTime,
          'targetTeacherIds': liveSlot.teacherIds,
          'targetTeacherNames': liveSlot.teacherNames,
          if (mergedNotes.isNotEmpty) 'notes': mergedNotes,
        });

    final notifSettings = await loadGateNotificationSettings(
      institutionId: record.institutionId,
      schoolDocId: record.schoolDocId,
      schoolTypeId: record.schoolTypeId,
    );
    final earlyCfg = notifSettings.earlyPickupNotice;
    if (!earlyCfg.enabled) return;

    final teacherUids = earlyCfg.isRecipientEnabled('ogretmen')
        ? await resolveTeacherRecipientUids(
            institutionId: record.institutionId,
            teacherIds: liveSlot.teacherIds,
            teacherNames: liveSlot.teacherNames,
          )
        : const <String>[];
    final roleUids = await resolveScopedRoleRecipients(
      institutionId: record.institutionId,
      schoolTypeId: record.schoolTypeId,
      includeMudur: earlyCfg.isRecipientEnabled('mudur'),
      includeMudurYardimcisi: earlyCfg.isRecipientEnabled('mudur_yardimcisi'),
      includeGuvenlik: earlyCfg.isRecipientEnabled('guvenlik'),
    );

    final who = record.receiverName.isNotEmpty ? record.receiverName : 'Velisi';
    final plate = record.vehiclePlate.isNotEmpty
        ? ' (${record.vehiclePlate})'
        : '';

    if (teacherUids.isNotEmpty) {
      await dispatchNotification(
        institutionId: record.institutionId,
        schoolTypeId: record.schoolTypeId,
        recipientUids: teacherUids,
        title:
            '📍 VELİ OKULA GELDİ — Öğrenciyi Çıkışa Hazırlayınız (${record.className})',
        message:
            '${record.className} sınıfından ${record.studentName} öğrencimizin velisi ($who$plate) saat $timeStr itibarıyla okul kapısına ulaşmıştır (${liveSlot.lessonHour}. Ders - ${liveSlot.lessonName}). Öğrencinin eşyalarıyla çıkış noktasına yönlendirilmesi rica olunur.',
        type: 'early_pickup_parent_arrived_teacher',
        entityId: record.id,
      );
    }

    if (roleUids.isNotEmpty) {
      await dispatchNotification(
        institutionId: record.institutionId,
        schoolTypeId: record.schoolTypeId,
        recipientUids: roleUids,
        title:
            '🚗 Veli Okula Ulaştı: ${record.studentName} (${record.className})',
        message:
            '${record.studentName} için önceden bildirim yapan veli ($who$plate) saat $timeStr\'de okula geldiğini bildirdi. Ders öğretmenine (${liveSlot.teacherSummary}) öğrenciyi hazırlaması için anlık bildirim gönderildi.',
        type: 'early_pickup_parent_arrived_gate',
        entityId: record.id,
      );
    }
  }

  /// Öğretmen veya idare öğrenciyi sınıftan çıkış kapısına gönderdiğinde durumu `pendingGate` yapar
  /// ve hem Veliye ("Öğrenciniz kapıya yönlendirildi") hem Güvenliğe haber verir.
  Future<void> sendStudentToGateForEarlyPickup({
    required StudentMovementRecord record,
  }) async {
    final now = DateTime.now();
    final timeStr = DateFormat('HH:mm').format(now);

    await _db
        .collection('schools')
        .doc(record.schoolDocId)
        .collection('studentMovements')
        .doc(record.id)
        .update({'status': StudentMovementStatus.pendingGate.firestoreKey});

    final notifSettings = await loadGateNotificationSettings(
      institutionId: record.institutionId,
      schoolDocId: record.schoolDocId,
      schoolTypeId: record.schoolTypeId,
    );
    final earlyCfg = notifSettings.earlyPickupNotice;
    if (!earlyCfg.enabled) return;

    if (earlyCfg.isRecipientEnabled('veli')) {
      final parentUids = await resolveParentRecipientUids(
        institutionId: record.institutionId,
        studentId: record.studentId,
      );
      if (parentUids.isNotEmpty) {
        await dispatchNotification(
          institutionId: record.institutionId,
          schoolTypeId: record.schoolTypeId,
          recipientUids: parentUids,
          title: '🎒 Öğrenciniz Çıkış Kapısına Yönlendirildi',
          message:
              'Öğrencimiz ${record.studentName} (${record.className}) saat $timeStr itibarıyla sınıfından çıkış/güvenlik noktasına yönlendirilmiştir.',
          type: 'early_pickup_student_on_way',
          entityId: record.id,
          route: '/parent-main',
        );
      }
    }

    if (earlyCfg.isRecipientEnabled('guvenlik')) {
      final securityUids = await resolveScopedRoleRecipients(
        institutionId: record.institutionId,
        schoolTypeId: record.schoolTypeId,
        includeMudur: false,
        includeMudurYardimcisi: false,
        includeGuvenlik: true,
      );
      if (securityUids.isNotEmpty) {
        await dispatchNotification(
          institutionId: record.institutionId,
          schoolTypeId: record.schoolTypeId,
          recipientUids: securityUids,
          title: '🚪 Öğrenci Kapıya İniyor: ${record.studentName}',
          message:
              '${record.className} - ${record.studentName} sınıfından çıkış kapısına yönlendirildi. Veliye teslim ederken kapı onayı veriniz.',
          type: 'early_pickup_gate_ready',
          entityId: record.id,
        );
      }
    }
  }

  /// Kaydı iptal eder
  Future<void> cancelMovement(StudentMovementRecord record) async {
    await _db
        .collection('schools')
        .doc(record.schoolDocId)
        .collection('studentMovements')
        .doc(record.id)
        .update({
          'status': StudentMovementStatus.cancelled.firestoreKey,
          'completedAt': Timestamp.fromDate(DateTime.now()),
        });
  }

  // ─── Yardımcı Alan Çözücüler ────────────────────────────────────────────────
  static String _extractStudentName(Map<String, dynamic> s) {
    final full = (s['fullName'] ?? '').toString().trim();
    if (full.isNotEmpty) return full;
    final first = (s['name'] ?? s['firstName'] ?? '').toString().trim();
    final last = (s['surname'] ?? s['lastName'] ?? '').toString().trim();
    final comb = '$first $last'.trim();
    return comb.isNotEmpty ? comb : 'Öğrenci';
  }

  static String _extractStudentNo(Map<String, dynamic> s) {
    return (s['studentNo'] ?? s['studentNumber'] ?? s['number'] ?? '')
        .toString()
        .trim();
  }

  static String _extractParentName(Map<String, dynamic> s) {
    final direct = (s['parentName'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;
    if (s['parents'] is Iterable && (s['parents'] as Iterable).isNotEmpty) {
      final first = (s['parents'] as Iterable).first;
      if (first is Map) {
        return '${first['name'] ?? ''} ${first['surname'] ?? ''}'.trim();
      }
    }
    return '';
  }

  static String _extractParentPhone(Map<String, dynamic> s) {
    final direct = (s['parentPhone'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;
    if (s['parents'] is Iterable && (s['parents'] as Iterable).isNotEmpty) {
      final first = (s['parents'] as Iterable).first;
      if (first is Map) {
        return (first['phone'] ?? '').toString().trim();
      }
    }
    return '';
  }
}
