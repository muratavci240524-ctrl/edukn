import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/school/homework_model.dart';

class HomeworkStatisticsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 1. Get Homeworks for a specific date range
  Future<List<Homework>> getHomeworksByDateRange(
    String institutionId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    // Index bypass: Fetch all for institution, then filter by date in memory.
    final snap = await _firestore
        .collection('homeworks')
        .where('institutionId', isEqualTo: institutionId)
        .get();

    final allHomeworks = snap.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return Homework.fromMap(data);
    }).toList();

    // Filter in memory
    return allHomeworks.where((hw) {
      return hw.createdAt.isAfter(
            startDate.subtract(const Duration(seconds: 1)),
          ) &&
          hw.createdAt.isBefore(endDate.add(const Duration(seconds: 1)));
    }).toList();
  }

  // 2. Get Student Risk List (Consolidated logic)
  // This is generic and might happen in client-side for performance if dataset is small,
  // but let's provide a helper here assuming we have the list of ALL relevant homeworks.
  List<Map<String, dynamic>> calculateStudentRisk(
    List<Homework> homeworks,
    int consecutiveThreshold,
  ) {
    // Sort homeworks by date descending (newest first)
    homeworks.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Map: StudentId -> ConsecutiveMissedCount
    final studentRiskMap = <String, int>{};
    final studentLastActionMap =
        <String, String>{}; // 'missed' or 'done' to break streak

    /*
      Logic:
      Iterate through sorted homeworks.
      For each homework, iterate target students.
      If student missed (status 2,3,4), increment streak.
      If student did it (status 1), break streak (set 'done').
      If pending (0), ignore or treat as gap? Usually ignore pending for "consecutive missed history".
     */

    for (final hw in homeworks) {
      for (final studentId in hw.targetStudentIds) {
        // If already marked as 'streak broken' (done recently), skip
        if (studentLastActionMap[studentId] == 'done') continue;

        final status = hw.studentStatuses[studentId] ?? 0;

        // Pending (0) -> Skip, doesn't break streak but doesn't add to it (not yet graded)
        if (status == 0) continue;

        // Completed (1) -> Break streak
        if (status == 1) {
          studentLastActionMap[studentId] = 'done';
          continue;
        }

        // Negative (2: notCompleted, 3: missing, 4: notBrought) -> Add to streak
        if (status == 2 || status == 3 || status == 4) {
          studentRiskMap[studentId] = (studentRiskMap[studentId] ?? 0) + 1;
          studentLastActionMap[studentId] = 'missed';
        }
      }
    }

    // Filter by threshold
    final atRiskStudents = <Map<String, dynamic>>[];
    studentRiskMap.forEach((studentId, count) {
      if (count >= consecutiveThreshold &&
          studentLastActionMap[studentId] == 'missed') {
        atRiskStudents.add({'studentId': studentId, 'missedCount': count});
      }
    });

    return atRiskStudents;
  }

  // Helper: Get Teacher Names (Optional, or passed from UI)
  Future<Map<String, String>> getTeacherNames(List<String> teacherIds) async {
    final map = <String, String>{};
    if (teacherIds.isEmpty) return map;

    // Batched read (limit 10 in 'in' query usually, doing individually or all teachers might be better)
    // For now, assume UI passes context or we fetch individually
    // Optimisation: Fetch ALL teachers once and cache in the UI is better.
    return map;
  }
}
