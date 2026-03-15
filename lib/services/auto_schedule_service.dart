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

    // Fetch Assignments
    final assignmentsSnap = await _firestore
        .collection('lessonAssignments')
        .where('institutionId', isEqualTo: institutionId)
        .where('schoolTypeId', isEqualTo: schoolTypeId)
        .where('isActive', isEqualTo: true)
        .get();

    final assignments = assignmentsSnap.docs.map((d) => d.data()).toList();
    print('📚 Found ${assignments.length} assignments to distribute');

    // Sort assignments: Most hours first
    assignments.sort((a, b) {
      final hoursA = (a['weeklyHours'] as num?)?.toInt() ?? 0;
      final hoursB = (b['weeklyHours'] as num?)?.toInt() ?? 0;
      return hoursB.compareTo(hoursA);
    });

    // Run Multiple Attempts
    int maxAttempts = 10; // Try 10 times
    List<Map<String, dynamic>>? bestSchedule;
    List<String>? bestUnassignedDetails;
    int bestUnassignedCount = 999999;
    int bestAssignedCount = 0;

    print('🎲 Running $maxAttempts simulations...');

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      final result = _runAttempt(
        assignments,
        selectedDays,
        dailyCounts,
        periodId,
        institutionId,
        schoolTypeId,
      );

      if (result.unassignedCount < bestUnassignedCount) {
        bestUnassignedCount = result.unassignedCount;
        bestAssignedCount = result.assignedCount;
        bestSchedule = result.schedule;
        bestUnassignedDetails = result.unassignedDetails;
      }

      // Perfect score shortcut
      if (bestUnassignedCount == 0) break;
    }

    print('🏆 Best result: $bestUnassignedCount unassigned lessons.');

    // Save Best Result
    print('💾 Saving ${bestSchedule!.length} records...');

    // Step A: Delete old
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

    // Step B: Add new
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

    // Commit all
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
    List<String> selectedDays,
    Map<String, int> dailyCounts,
    String periodId,
    String institutionId,
    String schoolTypeId,
  ) {
    // Local Timelines
    final Map<String, Map<String, Set<int>>> teacherTimeline = {};
    final Map<String, Map<String, Set<int>>> classTimeline = {};

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

    final List<Map<String, dynamic>> newScheduleRecords = [];
    final List<String> unassignedDetails = [];
    int assignedCount = 0;
    final random = Random();

    for (var assignment in assignments) {
      // Basic info extraction
      final classId = assignment['classId'] as String;
      final lessonId = assignment['lessonId'] as String;
      final lessonName = assignment['lessonName'] as String? ?? 'Unknown';
      final className = assignment['className'] as String? ?? 'Unknown';
      final weeklyHours = (assignment['weeklyHours'] as num?)?.toInt() ?? 0;

      String? teacherId;
      String? teacherName;
      if (assignment['teacherIds'] != null &&
          (assignment['teacherIds'] as List).isNotEmpty) {
        teacherId = assignment['teacherIds'][0];
        teacherName = assignment['teacherNames']?[0];
      } else {
        teacherId = assignment['teacherId'];
        teacherName = assignment['teacherName'];
      }

      // Try to place each hour (Compact Strategy: Early hours first)
      for (int i = 0; i < weeklyHours; i++) {
        bool placed = false;

        // Strategy: Iterate hours 0 to Max-1 (0-based indexing)
        // This fills 1st hours (index 0) of all days, then 2nd hours...

        // Determin max possible hours across all days (e.g. 10)
        int maxPossibleHours = 0;
        for (var c in dailyCounts.values)
          if (c > maxPossibleHours) maxPossibleHours = c;

        outerLoop:
        for (int h = 0; h < maxPossibleHours; h++) {
          // Shuffle days to ensure load balancing across week
          List<String> shuffledDays = List.from(selectedDays)..shuffle(random);

          for (var day in shuffledDays) {
            final dayMax = dailyCounts[day] ?? 0;
            // h is 0-indexed. If dayMax is 8, valid indices are 0..7.
            if (h >= dayMax) continue;

            // Check Availability
            if (isSlotOccupied('class', classId, day, h)) continue;
            if (teacherId != null &&
                isSlotOccupied('teacher', teacherId, day, h))
              continue;

            // Found slot
            markSlot('class', classId, day, h);
            if (teacherId != null) markSlot('teacher', teacherId, day, h);

            newScheduleRecords.add({
              'classId': classId,
              'className': className,
              'lessonId': lessonId,
              'lessonName': lessonName,
              'teacherId': teacherId,
              'teacherName': teacherName,
              'day': day,
              'hourIndex': h, // 0-based
              'periodId': periodId,
              'institutionId': institutionId,
              'schoolTypeId': schoolTypeId,
              'isActive': true,
              'createdAt': FieldValue.serverTimestamp(),
            });

            placed = true;
            assignedCount++;
            break outerLoop; // Move to next required hour for this lesson
          }
        }

        if (!placed) {
          unassignedDetails.add(
            '$className - $lessonName (${i + 1}. saat) [Hoca: $teacherName]',
          );
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
