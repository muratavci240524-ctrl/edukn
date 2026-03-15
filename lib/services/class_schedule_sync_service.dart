import 'package:cloud_firestore/cloud_firestore.dart';

/// Service to sync class schedules to Firestore classSchedules collection
///
/// This ensures that when teachers modify schedules in the UI,
/// the changes are automatically reflected in Firestore for:
/// - Leave conflict detection
/// - Substitute assignment
/// - Reports and analytics
class ClassScheduleSyncService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Syncs a single lesson assignment to Firestore
  Future<void> syncLessonAssignment({
    required String institutionId,
    required String periodId,
    required String classId,
    required String className,
    required String day,
    required int hourIndex,
    required String lessonId,
    required String lessonName,
    required List<String> teacherIds,
  }) async {
    try {
      // Create unique document ID - fixed backslashes
      final docId = '${periodId}_${classId}_${day}_$hourIndex';
      print('DEBUG SYNC: Writing to docId=$docId');

      // Prepare data
      final data = {
        'institutionId': institutionId,
        'periodId': periodId,
        'classId': classId,
        'className': className,
        'day': day,
        'hourIndex': hourIndex,
        'lessonId': lessonId,
        'lessonName': lessonName,
        'isActive': true, // CRITICAL: Required for query filtering
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Handle both single and multiple teachers
      // CRITICAL: Always save teacherIds/teacherId even if empty list
      // to ensure query filtering works correctly in substitute assignment
      if (teacherIds.isNotEmpty) {
        data['teacherId'] = teacherIds.first;
        data['teacherIds'] = teacherIds;
      } else {
        // Empty teacherIds - save empty array for consistency
        data['teacherIds'] = [];
      }

      await _firestore
          .collection('classSchedules')
          .doc(docId)
          .set(data, SetOptions(merge: true));

      print(
        '✅ Synced lesson: $lessonName ($className - $day - Hour ${hourIndex + 1})',
      );
    } catch (e) {
      print('❌ Error syncing lesson: $e');
      // Rethrow to let caller handle
      rethrow;
    }
  }

  /// Removes a lesson assignment from Firestore
  Future<void> removeLessonAssignment({
    required String periodId,
    required String classId,
    required String day,
    required int hourIndex,
  }) async {
    try {
      final docId = '${periodId}_${classId}_${day}_$hourIndex';

      await _firestore.collection('classSchedules').doc(docId).delete();

      print(
        '✅ Removed lesson assignment: $classId - $day - Hour ${hourIndex + 1}',
      );
    } catch (e) {
      print('❌ Error removing lesson: $e');
      rethrow;
    }
  }

  /// Syncs an entire class schedule for a period (for bulk operations)
  Future<void> syncClassSchedule({
    required String institutionId,
    required String periodId,
    required String classId,
    required String className,
    required Map<String, Map<int, Map<String, dynamic>>> schedule,
  }) async {
    try {
      final batch = _firestore.batch();
      int count = 0;

      // schedule structure: {day: {hourIndex: {lessonData}}}
      for (var day in schedule.keys) {
        final daySchedule = schedule[day]!;
        for (var hourIndex in daySchedule.keys) {
          final lessonData = daySchedule[hourIndex]!;
          final docId = '${periodId}_${classId}_${day}_$hourIndex';

          final data = {
            'institutionId': institutionId,
            'periodId': periodId,
            'classId': classId,
            'className': className,
            'day': day,
            'hourIndex': hourIndex,
            'lessonId': lessonData['lessonId'],
            'lessonName': lessonData['lessonName'],
            'updatedAt': FieldValue.serverTimestamp(),
          };

          final teacherIds = lessonData['teacherIds'] as List<String>?;
          if (teacherIds != null && teacherIds.isNotEmpty) {
            if (teacherIds.length == 1) {
              data['teacherId'] = teacherIds.first;
            }
            data['teacherIds'] = teacherIds;
          }

          batch.set(
            _firestore.collection('classSchedules').doc(docId),
            data,
            SetOptions(merge: true),
          );
          count++;
        }
      }

      await batch.commit();
      print('✅ Synced $count lesson assignments for class $className');
    } catch (e) {
      print('❌ Error syncing class schedule: $e');
      rethrow;
    }
  }

  /// Copies schedule from one period to another
  Future<void> copyScheduleBetweenPeriods({
    required String sourcePeriodId,
    required String targetPeriodId,
  }) async {
    try {
      // Get all schedules from source period
      final sourceSchedules = await _firestore
          .collection('classSchedules')
          .where('periodId', isEqualTo: sourcePeriodId)
          .get();

      final batch = _firestore.batch();
      int count = 0;

      for (var doc in sourceSchedules.docs) {
        final data = doc.data();

        // Create new doc ID for target period
        final newDocId = doc.id.replaceFirst(sourcePeriodId, targetPeriodId);

        // Update periodId
        data['periodId'] = targetPeriodId;
        data['copiedAt'] = FieldValue.serverTimestamp();

        batch.set(
          _firestore.collection('classSchedules').doc(newDocId),
          data,
          SetOptions(merge: true),
        );
        count++;
      }

      await batch.commit();
      print(
        '✅ Copied $count schedules from period $sourcePeriodId to $targetPeriodId',
      );
    } catch (e) {
      print('❌ Error copying schedules: $e');
      rethrow;
    }
  }
}
