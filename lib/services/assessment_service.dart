import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/assessment/exam_type_model.dart';
import '../models/assessment/optical_form_model.dart';
import '../models/assessment/outcome_list_model.dart';
import '../models/assessment/trial_exam_model.dart';

class AssessmentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- Exam Types ---

  Future<void> saveExamType(ExamType examType) async {
    final docRef = _firestore
        .collection('exam_types')
        .doc(examType.id.isEmpty ? null : examType.id);
    final data = examType.toMap();
    if (examType.id.isEmpty) {
      data['id'] = docRef.id;
    }
    await docRef.set(data, SetOptions(merge: true));
  }

  Stream<List<ExamType>> getExamTypes(String institutionId) {
    return _firestore
        .collection('exam_types')
        .where('institutionId', isEqualTo: institutionId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ExamType.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<ExamType?> getExamType(String id) async {
    final doc = await _firestore.collection('exam_types').doc(id).get();
    if (!doc.exists) return null;
    return ExamType.fromMap(doc.data()!, doc.id);
  }

  Future<void> deleteExamType(String id) async {
    await _firestore.collection('exam_types').doc(id).update({
      'isActive': false,
    });
  }

  // --- Optical Forms ---

  Future<void> saveOpticalForm(OpticalForm form) async {
    final docRef = _firestore
        .collection('optical_forms')
        .doc(form.id.isEmpty ? null : form.id);
    final data = form.toMap();
    if (form.id.isEmpty) {
      data['id'] = docRef.id;
    }
    await docRef.set(data, SetOptions(merge: true));
  }

  Stream<List<OpticalForm>> getOpticalForms(String institutionId) {
    return _firestore
        .collection('optical_forms')
        .where('institutionId', isEqualTo: institutionId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => OpticalForm.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<void> deleteOpticalForm(String id) async {
    await _firestore.collection('optical_forms').doc(id).update({
      'isActive': false,
    });
  }

  // --- Trial Exams ---

  Future<void> saveTrialExam(TrialExam exam) async {
    final docRef = _firestore
        .collection('trial_exams')
        .doc(exam.id.isEmpty ? null : exam.id);
    final data = exam.toMap();
    if (exam.id.isEmpty) {
      data['id'] = docRef.id;
    }
    await docRef.set(data, SetOptions(merge: true));
  }

  Future<void> updateTrialExamSharingSettings(
    String id,
    Map<String, dynamic> settings,
    bool isPublished,
  ) async {
    await _firestore.collection('trial_exams').doc(id).update({
      'sharingSettings': settings,
      'isPublished': isPublished,
    });
  }

  Stream<List<TrialExam>> getTrialExams(String institutionId) {
    return _firestore
        .collection('trial_exams')
        .where('institutionId', isEqualTo: institutionId)
        .where('isActive', isEqualTo: true)
        .orderBy('date', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => TrialExam.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<void> deleteTrialExam(String id) async {
    await _firestore.collection('trial_exams').doc(id).update({
      'isActive': false,
    });
  }

  // --- Outcome Lists ---

  Future<void> saveOutcomeList(OutcomeList outcomeList) async {
    final docRef = _firestore
        .collection('outcome_lists')
        .doc(outcomeList.id.isEmpty ? null : outcomeList.id);
    final data = outcomeList.toMap();
    if (outcomeList.id.isEmpty) {
      data['id'] = docRef.id;
    }
    await docRef.set(data, SetOptions(merge: true));
  }

  Stream<List<OutcomeList>> getOutcomeLists(String institutionId) {
    return _firestore
        .collection('outcome_lists')
        .where('institutionId', isEqualTo: institutionId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => OutcomeList.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<void> deleteOutcomeList(String id) async {
    await _firestore.collection('outcome_lists').doc(id).update({
      'isActive': false,
    });
  }

  // --- Helper: Fetch Branches for Dropdown ---
  Future<List<String>> getAvailableBranches(String institutionId) async {
    final defaultBranches = [
      'Almanca',
      'Arapça',
      'Beden Eğitimi ve Spor',
      'Bilişim Teknolojileri ve Yazılım',
      'Biyoloji',
      'Coğrafya',
      'Din Kültürü ve Ahlak Bilgisi',
      'Felsefe',
      'Fen Bilimleri',
      'Fizik',
      'Fransızca',
      'Görsel Sanatlar',
      'İlköğretim Matematik',
      'İngilizce',
      'İspanyolca',
      'Kimya',
      'Kulüp',
      'Matematik',
      'Müzik',
      'Okul Öncesi',
      'Özel Eğitim',
      'Rehberlik ve Psikolojik Danışmanlık',
      'Rusça',
      'Sınıf Öğretmenliği',
      'Sosyal Bilgiler',
      'Tarih',
      'Teknoloji ve Tasarım',
      'Türk Dili ve Edebiyatı',
      'Türkçe',
    ];

    final allBranches = Set<String>.from(defaultBranches);

    try {
      final customBranches = await _firestore
          .collection('branches')
          .where('institutionId', isEqualTo: institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      for (var doc in customBranches.docs) {
        final name = doc.data()['branchName'] as String?;
        if (name != null && name.isNotEmpty) {
          allBranches.add(name);
        }
      }
    } catch (e) {
      print('AssessmentService: Error fetching custom branches: $e');
    }

    return allBranches.toList()..sort();
  }
}
