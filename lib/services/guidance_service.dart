import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/guidance/study_template_model.dart';

class GuidanceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- Templates ---

  Future<void> saveStudyTemplate(StudyTemplate template) async {
    final docRef = _firestore
        .collection('institutions')
        .doc(template.institutionId)
        .collection('study_templates')
        .doc(template.id.isEmpty ? null : template.id);

    final data = template.toMap();
    if (template.id.isEmpty) {
      data['id'] = docRef.id;
    }

    await docRef.set(data, SetOptions(merge: true));
  }

  // Assign template to specific student IDs
  Future<void> assignTemplateToStudents(
    String institutionId,
    String templateId,
    String templateName,
    List<String> studentIds,
  ) async {
    final batch = _firestore.batch();

    for (var studentId in studentIds) {
      final docRef = _firestore.collection('students').doc(studentId);
      batch.update(docRef, {
        'studyTemplateId': templateId,
        'studyTemplateName': templateName,
      });
    }

    await batch.commit();
  }

  // Assign template to a whole class/branch
  Future<void> assignTemplateToClass(
    String institutionId,
    String schoolTypeId, // Added parameter
    String templateId,
    String templateName,
    String className,
  ) async {
    // Determine target students
    final query = await _firestore
        .collection('students')
        .where('institutionId', isEqualTo: institutionId)
        .where('schoolTypeId', isEqualTo: schoolTypeId) // Added filter
        .where(
          'className',
          isEqualTo: className,
        ) // assuming className is stored
        .where('isActive', isEqualTo: true)
        .get();

    final batch = _firestore.batch();
    int count = 0;

    for (var doc in query.docs) {
      batch.update(doc.reference, {
        'studyTemplateId': templateId,
        'studyTemplateName': templateName,
      });
      count++;
      // Batch limit is 500, simple check
      if (count >= 490) {
        await batch.commit();
        count = 0;
      }
    }

    if (count > 0) {
      await batch.commit();
    }
  }

  // Assign to ALL active students
  Future<void> assignTemplateToAll(
    String institutionId,
    String schoolTypeId, // Added parameter
    String templateId,
    String templateName,
  ) async {
    final query = await _firestore
        .collection('students')
        .where('institutionId', isEqualTo: institutionId)
        .where('schoolTypeId', isEqualTo: schoolTypeId) // Added filter
        .where('isActive', isEqualTo: true)
        .get();

    final batch = _firestore.batch();
    int count = 0;

    for (var doc in query.docs) {
      batch.update(doc.reference, {
        'studyTemplateId': templateId,
        'studyTemplateName': templateName,
      });
      count++;
      if (count >= 490) {
        await batch.commit();
        count = 0;
      }
    }

    if (count > 0) {
      await batch.commit();
    }
  }

  // Unassign
  Future<void> removeTemplateFromStudent(String studentId) async {
    await _firestore.collection('students').doc(studentId).update({
      'studyTemplateId': FieldValue.delete(),
      'studyTemplateName': FieldValue.delete(),
    });
  }

  Stream<List<StudyTemplate>> getStudyTemplates(String institutionId) {
    return _firestore
        .collection('institutions')
        .doc(institutionId)
        .collection('study_templates')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return StudyTemplate.fromMap(doc.data());
          }).toList();
        });
  }

  Future<void> deleteStudyTemplate(
    String institutionId,
    String templateId,
  ) async {
    await _firestore
        .collection('institutions')
        .doc(institutionId)
        .collection('study_templates')
        .doc(templateId)
        .delete();
  }

  Future<StudyTemplate?> getStudyTemplate(
    String institutionId,
    String templateId,
  ) async {
    final doc = await _firestore
        .collection('institutions')
        .doc(institutionId)
        .collection('study_templates')
        .doc(templateId)
        .get();

    if (doc.exists) {
      return StudyTemplate.fromMap(doc.data()!);
    }
    return null;
  }

  // --- Study Programs ---
  Future<void> saveStudyProgram(
    String institutionId,
    Map<String, dynamic> programData,
  ) async {
    // Defensive copy and serialization to handle objects from memory
    var data = Map<String, dynamic>.from(programData);
    if (data['template'] is StudyTemplate) {
      data['template'] = (data['template'] as StudyTemplate).toMap();
    }

    await _firestore
        .collection('institutions')
        .doc(institutionId)
        .collection('study_programs')
        .add({...data, 'createdAt': FieldValue.serverTimestamp()});
  }

  Future<Map<String, dynamic>?> getStudentStudyProgram(
    String institutionId,
    String studentId,
  ) async {
    final query = await _firestore
        .collection('institutions')
        .doc(institutionId)
        .collection('study_programs')
        .where('studentId', isEqualTo: studentId)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      final doc = query.docs.first;
      return {...doc.data(), 'id': doc.id};
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getStudentStudyPrograms(
    String institutionId,
    String studentId,
  ) async {
    final query = await _firestore
        .collection('institutions')
        .doc(institutionId)
        .collection('study_programs')
        .where('studentId', isEqualTo: studentId)
        .orderBy('createdAt', descending: true)
        .get();

    return query.docs.map((d) => {...d.data(), 'id': d.id}).toList();
  }

  // Fetch ALL programs (for history/management)
  Future<List<Map<String, dynamic>>> getAllStudyPrograms(
    String institutionId,
  ) async {
    final query = await _firestore
        .collection('institutions')
        .doc(institutionId)
        .collection('study_programs')
        .orderBy('createdAt', descending: true)
        .get();

    return query.docs.map((d) => {...d.data(), 'id': d.id}).toList();
  }

  // Delete a program
  Future<void> deleteStudyProgram(
    String institutionId,
    String programId,
  ) async {
    await _firestore
        .collection('institutions')
        .doc(institutionId)
        .collection('study_programs')
        .doc(programId)
        .delete();
  }

  Future<void> updateStudyProgramStatus(
    String institutionId,
    String programId,
    Map<String, List<int>> executionStatus,
  ) async {
    await _firestore
        .collection('institutions')
        .doc(institutionId)
        .collection('study_programs')
        .doc(programId)
        .update({'executionStatus': executionStatus});
  }
}
