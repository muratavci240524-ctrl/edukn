import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/assessment/exam_type_model.dart';
import '../models/assessment/optical_form_model.dart';
import '../models/assessment/outcome_list_model.dart';
import '../models/assessment/trial_exam_model.dart';
import '../models/assessment/assessment_action_plan_model.dart';

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

  Stream<List<TrialExam>> getTrialExams(String institutionId, {List<String>? classLevels}) {
    return _firestore
        .collection('trial_exams')
        .where('institutionId', isEqualTo: institutionId)
        .where('isActive', isEqualTo: true)
        .orderBy('date', descending: true)
        .snapshots()
        .map(
          (snapshot) {
            var exams = snapshot.docs
                .map((doc) => TrialExam.fromMap(doc.data() as Map<String, dynamic>, doc.id))
                .toList();
            
            if (classLevels != null && classLevels.isNotEmpty) {
              return exams.where((exam) => classLevels.contains(exam.classLevel)).toList();
            }
            
            return exams;
          },
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

  // --- Assessment Action Plans ---

  Future<void> saveAssessmentActionPlan(AssessmentActionPlan plan) async {
    print('Saving Action Plan: ID=${plan.id}, Title=${plan.title}, Institution=${plan.institutionId}, SchoolType=${plan.schoolTypeId}');
    final docRef = _firestore
        .collection('assessment_action_plans')
        .doc(plan.id.isEmpty ? null : plan.id);
    
    final data = plan.toMap();
    if (plan.id.isEmpty) {
      data['id'] = docRef.id;
    }
    
    await docRef.set(data, SetOptions(merge: true));
    print('Action Plan saved successfully with ID: ${data['id']}');
  }

  Stream<List<AssessmentActionPlan>> getAssessmentActionPlans(String institutionId, String schoolTypeId) {
    print('Fetching Action Plans: Institution=$institutionId, SchoolType=$schoolTypeId');
    
    // Using a simpler query to avoid composite index requirements.
    // Filtering and sorting are handled in-memory for immediate use.
    return _firestore
        .collection('assessment_action_plans')
        .where('institutionId', isEqualTo: institutionId)
        .snapshots()
        .map((snapshot) {
          List<AssessmentActionPlan> plans = snapshot.docs
              .map((doc) => AssessmentActionPlan.fromMap(doc.data() as Map<String, dynamic>, doc.id))
              .where((plan) => plan.isActive)
              .toList();

          if (schoolTypeId.isNotEmpty) {
            plans = plans.where((plan) => plan.schoolTypeId == schoolTypeId).toList();
          }

          // Sort by date descending
          plans.sort((a, b) => b.date.compareTo(a.date));
          
          return plans;
        });
  }

  Future<void> deleteAssessmentActionPlan(String id) async {
    await _firestore.collection('assessment_action_plans').doc(id).update({
      'isActive': false,
    });
  }

  Future<void> updateActionPlanRealization(String id, bool isRealized, String notes) async {
    await _firestore.collection('assessment_action_plans').doc(id).update({
      'isRealized': isRealized,
      'realizationNotes': notes,
      'realizedDate': isRealized ? Timestamp.now() : null,
    });
  }

  // --- Performance Analysis Engine ---

  Future<Map<String, List<Map<String, dynamic>>>> getPerformanceAnalysis(String institutionId, String schoolTypeId) async {
    try {
      // 1. Fetch recent trial exams for this institution
      final examsQuery = await _firestore
          .collection('trial_exams')
          .where('institutionId', isEqualTo: institutionId)
          .where('isActive', isEqualTo: true)
          .orderBy('date', descending: true)
          .limit(5)
          .get();

      final List<Map<String, dynamic>> weakTopics = [];
      
      for (var doc in examsQuery.docs) {
        final examData = doc.data();
        final String examClassLevel = examData['classLevel'] ?? '';
        
        // Skip if not the right school type (simple check)
        // You might have a better way to link exam to schoolType
        
        // 2. Look into outcome stats (often stored in a sub-collection or field)
        // Assuming stats are stored in the exam document for simplicity, 
        // or in assessment_action_plans which derive from these exams.
        
        // Let's look for existing action plans' outcomeStats as they contain 
        // the calculated branch-based performance data.
        final plansQuery = await _firestore
            .collection('assessment_action_plans')
            .where('institutionId', isEqualTo: institutionId)
            .where('schoolTypeId', isEqualTo: schoolTypeId)
            .where('isActive', isEqualTo: true)
            .orderBy('date', descending: true)
            .limit(3)
            .get();

        for (var planDoc in plansQuery.docs) {
          final plan = AssessmentActionPlan.fromMap(planDoc.data(), planDoc.id);
          
          // Map of branch -> subject -> outcome -> success%
          // plan.outcomeStats: Map<String, Map<String, Map<String, double>>>
          plan.outcomeStats.forEach((branch, subjects) {
            subjects.forEach((subject, outcomes) {
              outcomes.forEach((outcome, success) {
                if (success < 50.0) {
                  weakTopics.add({
                    'branch': branch,
                    'subject': subject,
                    'topic': outcome,
                    'successRate': success,
                    'studentCount': (plan.branchActionPlans[branch]?['targetStudents'] as List?)?.length ?? 0,
                  });
                }
              });
            });
          });
          
          // If we found enough weak topics from the most recent plan, we can stop
          if (weakTopics.length >= 5) break;
        }
        if (weakTopics.isNotEmpty) break;
      }

      return {
        'weakTopics': weakTopics,
        'atRiskStudents': [], // Individual tracking would go here
      };
    } catch (e) {
      print('Error in performance analysis: $e');
      return {'weakTopics': [], 'atRiskStudents': []};
    }
  }
}
