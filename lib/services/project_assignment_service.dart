import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/project_assignment_model.dart';

class ProjectAssignmentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> createProjectAssignment(ProjectAssignment assignment) async {
    await _firestore
        .collection('project_assignments')
        .doc(assignment.id)
        .set(assignment.toMap());
  }

  Future<void> updateProjectAssignment(ProjectAssignment assignment) async {
    await _firestore
        .collection('project_assignments')
        .doc(assignment.id)
        .update(assignment.toMap());
  }

  Future<void> deleteProjectAssignment(String id) async {
    await _firestore.collection('project_assignments').doc(id).delete();
  }

  Future<ProjectAssignment?> getProjectAssignment(String id) async {
    final doc = await _firestore
        .collection('project_assignments')
        .doc(id)
        .get();
    if (doc.exists) {
      return ProjectAssignment.fromMap({'id': doc.id, ...doc.data()!});
    }
    return null;
  }

  Stream<List<ProjectAssignment>> getProjectAssignments(String institutionId) {
    return _firestore
        .collection('project_assignments')
        .where('institutionId', isEqualTo: institutionId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return ProjectAssignment.fromMap({'id': doc.id, ...doc.data()});
          }).toList();
        });
  }
}
