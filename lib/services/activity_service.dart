import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/activity/activity_model.dart';

class ActivityService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collection References
  CollectionReference get _activitiesRef => _firestore.collection('activities');
  CollectionReference get _evaluationsRef =>
      _firestore.collection('activity_evaluations');

  // --- ACTIVITY OPERATIONS ---

  // Create new activity
  Future<void> createActivity(ActivityObservation activity) async {
    await _activitiesRef.add(activity.toMap());
  }

  // Update activity
  Future<void> updateActivity(String id, Map<String, dynamic> data) async {
    await _activitiesRef.doc(id).update(data);
  }

  // Delete activity
  Future<void> deleteActivity(String id) async {
    await _activitiesRef.doc(id).delete();
  }

  // Update participation status
  Future<void> updateParticipationStatus(
    String activityId,
    List<String> participatedStudentIds,
  ) async {
    await _activitiesRef.doc(activityId).update({
      'participatedStudentIds': participatedStudentIds,
    });
  }

  // Stream activities for list
  Stream<List<ActivityObservation>> getActivities(
    String institutionId,
    String schoolTypeId, {
    String? type,
  }) {
    Query query = _activitiesRef
        .where('institutionId', isEqualTo: institutionId)
        .where('schoolTypeId', isEqualTo: schoolTypeId);

    if (type != null) {
      query = query.where('type', isEqualTo: type);
    }

    // Order by date desc
    query = query.orderBy('date', descending: true);

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return ActivityObservation.fromMap(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );
      }).toList();
    });
  }

  // Get specific activity
  Future<ActivityObservation?> getActivity(String id) async {
    final doc = await _activitiesRef.doc(id).get();
    if (doc.exists) {
      return ActivityObservation.fromMap(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );
    }
    return null;
  }

  // --- EVALUATION OPERATIONS ---

  // Submit evaluation
  Future<void> submitEvaluation(ActivityEvaluation evaluation) async {
    await _evaluationsRef.add(evaluation.toMap());
  }

  // Check if student is already evaluated by this teacher for this activity
  Future<bool> hasEvaluated(
    String activityId,
    String studentId,
    String evaluatorId,
  ) async {
    final query = await _evaluationsRef
        .where('activityId', isEqualTo: activityId)
        .where('studentId', isEqualTo: studentId)
        .where('evaluatorId', isEqualTo: evaluatorId)
        .limit(1)
        .get();
    return query.docs.isNotEmpty;
  }

  // Get evaluations for an activity (for stats)
  Future<List<ActivityEvaluation>> getActivityEvaluations(
    String activityId,
  ) async {
    final query = await _evaluationsRef
        .where('activityId', isEqualTo: activityId)
        .get();

    return query.docs.map((doc) {
      return ActivityEvaluation.fromMap(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );
    }).toList();
  }

  // Get all evaluations for a student (for profile/stats)
  Stream<List<ActivityEvaluation>> getStudentEvaluations(String studentId) {
    return _evaluationsRef
        .where('studentId', isEqualTo: studentId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return ActivityEvaluation.fromMap(
              doc.data() as Map<String, dynamic>,
              doc.id,
            );
          }).toList();
        });
  }
}
