import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class LeaveConflictService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Checks for lesson conflicts between [startDate] and [endDate] for [teacherId].
  /// NEW APPROACH: Uses period's lessonHours as source of truth, not classSchedules
  Future<List<Map<String, dynamic>>> checkLessonConflicts({
    required String institutionId,
    required String teacherId,
    required DateTime startDate,
    required DateTime endDate,
    bool isFullDay = true,
    String? startTime, // "HH:mm"
    String? endTime, // "HH:mm"
  }) async {
    List<Map<String, dynamic>> conflicts = [];
    Set<String> addedConflicts = {}; // Track unique conflicts

    print('🔍 Starting conflict check for teacher: $teacherId');
    print(
      '   📅 Date range: ${DateFormat('dd.MM.yyyy').format(startDate)} - ${DateFormat('dd.MM.yyyy').format(endDate)}',
    );
    print('   ⏰ ${isFullDay ? "Full day" : "Hourly: $startTime - $endTime"}');

    // 1. Find all active work periods
    final periodsSnap = await _firestore
        .collection('workPeriods')
        .where('institutionId', isEqualTo: institutionId)
        .where('isActive', isEqualTo: true)
        .get();

    print('\n📚 Active periods found: ${periodsSnap.docs.length}');

    if (periodsSnap.docs.isEmpty) {
      print('⚠️ No active periods found!');
      return [];
    }

    for (var periodDoc in periodsSnap.docs) {
      final periodId = periodDoc.id;
      final periodData = periodDoc.data();
      final schoolTypeId = periodData['schoolTypeId'];
      final periodName = periodData['name'] ?? 'Unnamed Period';
      final lessonHoursData = periodData['lessonHours'];

      print('\n🔖 Period: $periodName (ID: $periodId)');

      if (lessonHoursData == null || lessonHoursData['lessonTimes'] == null) {
        print('   ⚠️ No lessonHours defined for this period, skipping...');
        continue;
      }

      final periodStart = (periodData['startDate'] as Timestamp?)?.toDate();
      final periodEnd = (periodData['endDate'] as Timestamp?)?.toDate();

      // 2. Iterate each day in leave range
      for (int i = 0; i <= endDate.difference(startDate).inDays; i++) {
        final currentDay = startDate.add(Duration(days: i));

        // Date Range Check: Skip if the leave day is outside the period's active range
        if (periodStart != null && periodEnd != null) {
          final pSafeStart = DateTime(
            periodStart.year,
            periodStart.month,
            periodStart.day,
          );
          final pSafeEnd = DateTime(
            periodEnd.year,
            periodEnd.month,
            periodEnd.day,
            23,
            59,
            59,
          );
          final cSafe = DateTime(
            currentDay.year,
            currentDay.month,
            currentDay.day,
          );

          if (cSafe.isBefore(pSafeStart) || cSafe.isAfter(pSafeEnd)) {
            print(
              '   ⚠️ Date ${DateFormat('dd.MM.yyyy').format(currentDay)} is outside Period "${periodName}" range. Skipping.',
            );
            continue;
          }
        }

        final dayName = _getDayNameTr(currentDay.weekday);

        final dayLessonTimes = lessonHoursData['lessonTimes'][dayName] as List?;

        if (dayLessonTimes == null || dayLessonTimes.isEmpty) {
          print('   📅 $dayName: No lesson hours defined, skipping...');
          continue;
        }

        print(
          '\n   📅 $dayName: ${dayLessonTimes.length} lesson slots defined',
        );

        // 3. Get all classSchedules for this teacher on this day
        final teacherSchedulesQuery1 = await _firestore
            .collection('classSchedules')
            .where('institutionId', isEqualTo: institutionId)
            .where('periodId', isEqualTo: periodId)
            .where('day', isEqualTo: dayName)
            .where('teacherId', isEqualTo: teacherId)
            .get();

        final teacherSchedulesQuery2 = await _firestore
            .collection('classSchedules')
            .where('institutionId', isEqualTo: institutionId)
            .where('periodId', isEqualTo: periodId)
            .where('day', isEqualTo: dayName)
            .where('teacherIds', arrayContains: teacherId)
            .get();

        // Merge and deduplicate
        final Map<int, QueryDocumentSnapshot> schedulesByHour = {};

        for (var doc in teacherSchedulesQuery1.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final hourIdx = data['hourIndex'] as int;
          schedulesByHour[hourIdx] = doc;
        }

        for (var doc in teacherSchedulesQuery2.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final hourIdx = data['hourIndex'] as int;
          schedulesByHour[hourIdx] = doc; // Will override if duplicate
        }

        print(
          '      🔍 Found ${schedulesByHour.length} classSchedule records for teacher',
        );

        // 3.5. NEW: Check for Temporary Assignments (Substitutes)
        // If the teacher has been substituted for a specific hour,
        // that hour should NOT be considered a conflict.
        final Set<int> substitutedHours = {};

        final startOfDay = DateTime(
          currentDay.year,
          currentDay.month,
          currentDay.day,
        );
        final endOfDay = DateTime(
          currentDay.year,
          currentDay.month,
          currentDay.day,
          23,
          59,
          59,
        );

        final tempAssignmentsSnap = await _firestore
            .collection('temporaryTeacherAssignments')
            .where('institutionId', isEqualTo: institutionId)
            .where('originalTeacherId', isEqualTo: teacherId)
            .where(
              'date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
            )
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
            .get();

        for (var doc in tempAssignmentsSnap.docs) {
          final data = doc.data();
          // Only consider if not cancelled
          // NOTE: We assume 'status' exists. If you use 'pending' or 'published', both mean "assigned away" from this teacher's perspective.
          // Cancelled ones might be deleted or have status='cancelled'.
          final status = data['status'];
          if (status != 'cancelled') {
            final h = data['hourIndex'];
            if (h is int) substitutedHours.add(h);
          }
        }
        if (substitutedHours.isNotEmpty) {
          print(
            '      🛡️ Found ${substitutedHours.length} substituted hours (Teacher relies on sub): $substitutedHours',
          );
        }

        // 4. Check each lesson slot
        for (int hourIdx = 0; hourIdx < dayLessonTimes.length; hourIdx++) {
          final lessonTime = dayLessonTimes[hourIdx] as Map<String, dynamic>;

          // Check if teacher has a lesson at this hour
          if (!schedulesByHour.containsKey(hourIdx)) {
            continue; // No lesson for this teacher at this hour
          }

          // NEW: Skip if this hour was already substituted (assigned to another teacher)
          if (substitutedHours.contains(hourIdx)) {
            print(
              '      ⏭️ Hour ${hourIdx + 1}: Skipping - already assigned to substitute teacher',
            );
            continue;
          }

          final scheduleDoc = schedulesByHour[hourIdx]!;
          final scheduleData = scheduleDoc.data() as Map<String, dynamic>;

          // Calculate lesson times
          final lessonStartMins =
              (lessonTime['startHour'] as int) * 60 +
              (lessonTime['startMinute'] as int);
          final lessonEndMins =
              (lessonTime['endHour'] as int) * 60 +
              (lessonTime['endMinute'] as int);

          bool hasConflict = false;

          // Check for time overlap
          if (isFullDay) {
            hasConflict = true; // Full day = all lessons conflict
          } else if (startTime != null && endTime != null) {
            final leaveStartParts = startTime.split(':');
            final leaveEndParts = endTime.split(':');
            final leaveStartMins =
                int.parse(leaveStartParts[0]) * 60 +
                int.parse(leaveStartParts[1]);
            final leaveEndMins =
                int.parse(leaveEndParts[0]) * 60 + int.parse(leaveEndParts[1]);

            // Check overlap
            hasConflict =
                !(lessonEndMins <= leaveStartMins ||
                    lessonStartMins >= leaveEndMins);

            print(
              '      📊 Hour ${hourIdx + 1}: ${scheduleData['lessonName']} at $lessonStartMins-$lessonEndMins mins | Leave: $leaveStartMins-$leaveEndMins mins | Overlap: $hasConflict',
            );
          }

          if (!hasConflict) continue;

          // Get class name
          final className =
              scheduleData['className'] ??
              (await _firestore
                  .collection('classes')
                  .doc(scheduleData['classId'])
                  .get()
                  .then((d) => d.data()?['className'] ?? 'Bilinmeyen Sınıf'));

          // Create unique conflict key
          final conflictKey =
              '${currentDay.toIso8601String()}_${scheduleData['classId']}_${scheduleData['lessonId']}_$hourIdx';

          if (addedConflicts.contains(conflictKey)) {
            print('      ⏭️  Skipping duplicate conflict');
            continue;
          }

          print(
            '      ✅ CONFLICT: ${scheduleData['lessonName']} - $className - Hour ${hourIdx + 1}',
          );

          addedConflicts.add(conflictKey);
          conflicts.add({
            'type': 'lesson',
            'date': currentDay,
            'dayName': dayName,
            'hourIndex': hourIdx,
            'courseName': scheduleData['lessonName'] ?? 'Bilinmeyen Ders',
            'className': className,
            'schoolTypeId': schoolTypeId,
            'periodId': periodId,
            'classId': scheduleData['classId'],
            'lessonId': scheduleData['lessonId'],
          });
        }
      }
    }

    print('\n📋 Total conflicts found: ${conflicts.length}');
    return conflicts;
  }

  /// Checks for duty conflicts
  Future<List<Map<String, dynamic>>> checkDutyConflicts({
    required String institutionId,
    required String teacherId,
    required DateTime startDate,
    required DateTime endDate,
    bool isFullDay = true,
    String? startTime,
    String? endTime,
  }) async {
    List<Map<String, dynamic>> conflicts = [];

    for (int i = 0; i <= endDate.difference(startDate).inDays; i++) {
      final currentDay = startDate.add(Duration(days: i));
      final dayName = _getDayNameTr(currentDay.weekday);

      final dutySnap = await _firestore
          .collection('dutyScheduleItems')
          .where('institutionId', isEqualTo: institutionId)
          .where('day', isEqualTo: dayName)
          .where('teacherId', isEqualTo: teacherId)
          .get();

      for (var doc in dutySnap.docs) {
        final data = doc.data();
        final locationId = data['locationId'];

        String locationName = 'Bilinmeyen Nöbet Yeri';
        if (locationId != null) {
          final locationDoc = await _firestore
              .collection('dutyLocations')
              .doc(locationId)
              .get();
          if (locationDoc.exists) {
            locationName = locationDoc.data()?['name'] ?? locationName;
          }
        }

        conflicts.add({
          'type': 'duty',
          'date': currentDay,
          'dayName': dayName,
          'locationName': locationName,
          'locationId': locationId,
        });
      }
    }

    return conflicts;
  }

  /// Find teachers who are free at a specific time slot
  /// Now includes: branch matching, workload sorting, proper staff filtering
  Future<List<Map<String, dynamic>>> findFreeTeachers({
    required String institutionId,
    required String schoolTypeId,
    required String periodId,
    required int dayOfWeek,
    required int hourIndex,
    required DateTime date,
    String? absentTeacherBranch,
  }) async {
    final dayName = _getDayNameTr(dayOfWeek);

    // 1. Get all staff (teachers) for this institution
    final teachersSnap = await _firestore
        .collection('users')
        .where('institutionId', isEqualTo: institutionId)
        .where('type', isEqualTo: 'staff')
        .where('isActive', isEqualTo: true)
        .get();

    // 2. Get busy teachers (classSchedules)
    final busyFromSchedule1 = await _firestore
        .collection('classSchedules')
        .where('institutionId', isEqualTo: institutionId)
        .where('periodId', isEqualTo: periodId)
        .where('day', isEqualTo: dayName)
        .where('hourIndex', isEqualTo: hourIndex)
        .where('isActive', isEqualTo: true)
        .get();

    Set<String> busyTeacherIds = {};
    for (var doc in busyFromSchedule1.docs) {
      final data = doc.data();
      if (data['teacherId'] != null) busyTeacherIds.add(data['teacherId']);
      if (data['teacherIds'] is List) {
        for (var tid in (data['teacherIds'] as List)) {
          busyTeacherIds.add(tid.toString());
        }
      }
    }

    // 3. Get busy teachers from temporaryTeacherAssignments (already assigned elsewhere)
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

    final tempAssignments = await _firestore
        .collection('temporaryTeacherAssignments')
        .where('institutionId', isEqualTo: institutionId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .get();

    for (var doc in tempAssignments.docs) {
      final data = doc.data();
      if (data['hourIndex'] == hourIndex) {
        final subId = data['substituteTeacherId'];
        if (subId != null) busyTeacherIds.add(subId.toString());
      }
    }

    // 4. Calculate monthly substitution stats for workload sorting
    final startOfMonth = DateTime(date.year, date.month, 1);
    final endOfMonth = DateTime(date.year, date.month + 1, 0, 23, 59, 59);

    final statsSnap = await _firestore
        .collection('temporaryTeacherAssignments')
        .where('institutionId', isEqualTo: institutionId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
        .get();

    final teacherStats = <String, int>{};
    for (var doc in statsSnap.docs) {
      final tid = doc.data()['substituteTeacherId'] as String?;
      if (tid != null) teacherStats[tid] = (teacherStats[tid] ?? 0) + 1;
    }

    // 5. Filter available teachers
    List<Map<String, dynamic>> freeTeachers = [];
    final absentBranchUpper = absentTeacherBranch?.toUpperCase();

    for (var teacherDoc in teachersSnap.docs) {
      final teacherId = teacherDoc.id;
      final teacherData = teacherDoc.data();

      // Skip if busy
      if (busyTeacherIds.contains(teacherId)) continue;

      // Filter by title (only teachers, not other staff)
      final title = (teacherData['title'] ?? '').toString().toLowerCase();
      final isTeacher =
          title == 'ogretmen' || title == 'teacher' || title.isEmpty;
      if (!isTeacher) continue;

      // Get branch info
      String teacherBranch = '';
      if (teacherData['branch'] is String) {
        teacherBranch = teacherData['branch'];
      } else if (teacherData['branches'] is List &&
          (teacherData['branches'] as List).isNotEmpty) {
        teacherBranch = (teacherData['branches'] as List).first.toString();
      }

      // Check branch match for priority sorting
      bool branchMatch = false;
      if (absentBranchUpper != null &&
          teacherBranch.toUpperCase() == absentBranchUpper) {
        branchMatch = true;
      }

      freeTeachers.add({
        'id': teacherId,
        'fullName': teacherData['fullName'] ?? 'İsimsiz Öğretmen',
        'name': teacherData['fullName'] ?? 'İsimsiz Öğretmen',
        'branch': teacherBranch,
        'branchMatch': branchMatch,
        'assignmentCount': teacherStats[teacherId] ?? 0,
      });
    }

    // 6. Sort: branch match first, then by assignment count (ascending)
    freeTeachers.sort((a, b) {
      // Branch match priority
      if (a['branchMatch'] == true && b['branchMatch'] != true) return -1;
      if (b['branchMatch'] == true && a['branchMatch'] != true) return 1;

      // Then by assignment count (fewer first)
      return (a['assignmentCount'] as int).compareTo(
        b['assignmentCount'] as int,
      );
    });

    return freeTeachers;
  }

  String _getDayNameTr(int weekday) {
    const days = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];
    return days[weekday - 1];
  }
}
