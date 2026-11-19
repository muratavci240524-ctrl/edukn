import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../constants/turkey_address_data.dart';
import '../models/assessment/central_exam_model.dart';
import '../models/assessment/exam_type_model.dart';
import '../models/assessment/trial_exam_model.dart';
import '../screens/school/assessment/evaluation_models.dart';
import 'term_service.dart';
import 'user_permission_service.dart';

class CentralSchoolTypeNode {
  final String schoolTypeId;
  final String schoolTypeName;
  final String category;
  final List<String> activeGrades;

  const CentralSchoolTypeNode({
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.category,
    this.activeGrades = const [],
  });
}

class CentralSchoolNode {
  final String schoolId;
  final String institutionId;
  final String schoolName;
  final String city;
  final String district;
  final String region;
  final bool isActive;
  final List<CentralSchoolTypeNode> schoolTypes;

  const CentralSchoolNode({
    required this.schoolId,
    required this.institutionId,
    required this.schoolName,
    required this.city,
    required this.district,
    required this.region,
    this.isActive = true,
    this.schoolTypes = const [],
  });
}

class CentralChildExamStatus {
  final CentralExamTarget target;
  final bool childExists;
  final bool hasOpticalUpload;
  final bool isEvaluatedLocally;
  final bool isPublishedBySchool;
  final int participantCount;
  final double avgScore;
  final DateTime? centralEvaluatedAt;

  const CentralChildExamStatus({
    required this.target,
    required this.childExists,
    required this.hasOpticalUpload,
    required this.isEvaluatedLocally,
    required this.isPublishedBySchool,
    required this.participantCount,
    required this.avgScore,
    this.centralEvaluatedAt,
  });

  String get statusLabel {
    if (isEvaluatedLocally) {
      return isPublishedBySchool
          ? 'Yayında ($participantCount Öğrenci)'
          : 'Okundu ($participantCount Öğrenci)';
    }
    if (hasOpticalUpload) {
      return 'Optik Yüklendi (Değerlendirme Bekliyor)';
    }
    return 'Optik Okuma Bekleniyor';
  }
}

class _OutcomeCounter {
  int total = 0;
  int correct = 0;
  int wrong = 0;
  int empty = 0;
  final Set<int> questionIndices = {};

  double get correctRate => total > 0 ? (correct / total) * 100.0 : 0.0;
  double get wrongRate => total > 0 ? (wrong / total) * 100.0 : 0.0;
  double get emptyRate => total > 0 ? (empty / total) * 100.0 : 0.0;
}

class _SubjectAccumulator {
  int studentCount = 0;
  int questionCount = 0;
  double sumCorrect = 0;
  double sumWrong = 0;
  double sumEmpty = 0;
  double sumNet = 0;

  void add(SubjectStats stats, int fallbackQuestionCount) {
    studentCount++;
    sumCorrect += stats.correct;
    sumWrong += stats.wrong;
    sumEmpty += stats.empty;
    sumNet += stats.net;
    final totalQ = stats.correct + stats.wrong + stats.empty;
    if (fallbackQuestionCount > questionCount) {
      questionCount = fallbackQuestionCount;
    } else if (totalQ > questionCount) {
      questionCount = totalQ;
    }
  }

  Map<String, dynamic> toSummaryMap() {
    if (studentCount == 0) {
      return {
        'questionCount': questionCount,
        'avgCorrect': 0.0,
        'avgWrong': 0.0,
        'avgEmpty': 0.0,
        'avgNet': 0.0,
        'successRate': 0.0,
      };
    }
    final avgC = sumCorrect / studentCount;
    final avgW = sumWrong / studentCount;
    final avgE = sumEmpty / studentCount;
    final avgN = sumNet / studentCount;
    final effectiveQ = questionCount > 0
        ? questionCount.toDouble()
        : (avgC + avgW + avgE);
    final successRate = effectiveQ > 0
        ? ((avgC / effectiveQ) * 100.0).clamp(0.0, 100.0)
        : 0.0;
    return {
      'questionCount': questionCount,
      'avgCorrect': double.parse(avgC.toStringAsFixed(2)),
      'avgWrong': double.parse(avgW.toStringAsFixed(2)),
      'avgEmpty': double.parse(avgE.toStringAsFixed(2)),
      'avgNet': double.parse(avgN.toStringAsFixed(2)),
      'successRate': double.parse(successRate.toStringAsFixed(1)),
    };
  }
}

class _GlobalStudentEntry {
  final String childDocId;
  final CentralExamTarget target;
  final StudentResult student;

  _GlobalStudentEntry({
    required this.childDocId,
    required this.target,
    required this.student,
  });
}

class CentralMergeResult {
  final int totalParticipants;
  final int participatingSchoolsCount;
  final int pendingSchoolsCount;
  final double globalAvgScore;
  final Map<String, dynamic> analyticsSummary;

  const CentralMergeResult({
    required this.totalParticipants,
    required this.participatingSchoolsCount,
    required this.pendingSchoolsCount,
    required this.globalAvgScore,
    required this.analyticsSummary,
  });
}

class CentralAssessmentService {
  static const String hqInstitutionId = 'SUPER_ADMIN';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ---------------------------------------------------------------------------
  // 1. CENTRAL EXAMS CRUD & STREAMS
  // ---------------------------------------------------------------------------

  Stream<List<CentralExam>> streamCentralExams() {
    return _firestore.collection('central_exams').snapshots().map((snap) {
      final list = snap.docs
          .map((d) => CentralExam.fromMap(d.data(), d.id))
          .toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    });
  }

  Future<CentralExam?> getCentralExam(String centralExamId) async {
    final doc = await _firestore
        .collection('central_exams')
        .doc(centralExamId)
        .get();
    if (!doc.exists || doc.data() == null) return null;
    return CentralExam.fromMap(doc.data()!, doc.id);
  }

  Stream<List<ExamType>> streamHqExamTypes() {
    return _firestore
        .collection('exam_types')
        .where('institutionId', isEqualTo: hqInstitutionId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => ExamType.fromMap(d.data(), d.id)).toList(),
        );
  }

  Future<ExamType> createStandardExamTypeTemplate(String templateKey) async {
    ExamType template;
    switch (templateKey) {
      case 'LGS':
        template = ExamType(
          id: '',
          name: 'Genel Merkez LGS (8. Sınıf)',
          gradeLevel: '8. Sınıf',
          institutionId: hqInstitutionId,
          baseScore: 194.75,
          maxScore: 500.0,
          wrongCorrectRatio: 3.0,
          optionCount: 4,
          subjects: [
            ExamSubject(
              branchName: 'Türkçe',
              questionCount: 20,
              coefficient: 4.348,
            ),
            ExamSubject(
              branchName: 'T.C. İnkılap Tarihi ve Atatürkçülük',
              questionCount: 10,
              coefficient: 1.666,
            ),
            ExamSubject(
              branchName: 'Din Kültürü ve Ahlak Bilgisi',
              questionCount: 10,
              coefficient: 1.899,
            ),
            ExamSubject(
              branchName: 'İngilizce',
              questionCount: 10,
              coefficient: 1.507,
            ),
            ExamSubject(
              branchName: 'Matematik',
              questionCount: 20,
              coefficient: 4.254,
            ),
            ExamSubject(
              branchName: 'Fen Bilimleri',
              questionCount: 20,
              coefficient: 4.123,
            ),
          ],
        );
        break;
      case 'TYT':
        template = ExamType(
          id: '',
          name: 'Genel Merkez TYT (YKS 1. Oturum)',
          gradeLevel: '12. Sınıf',
          institutionId: hqInstitutionId,
          baseScore: 100.0,
          maxScore: 500.0,
          wrongCorrectRatio: 4.0,
          optionCount: 5,
          subjects: [
            ExamSubject(
              branchName: 'Türkçe',
              questionCount: 40,
              coefficient: 3.3,
            ),
            ExamSubject(
              branchName: 'Sosyal Bilimler',
              questionCount: 20,
              coefficient: 3.4,
            ),
            ExamSubject(
              branchName: 'Temel Matematik',
              questionCount: 40,
              coefficient: 3.3,
            ),
            ExamSubject(
              branchName: 'Fen Bilimleri',
              questionCount: 20,
              coefficient: 3.4,
            ),
          ],
        );
        break;
      case 'AYT':
        template = ExamType(
          id: '',
          name: 'Genel Merkez AYT (YKS 2. Oturum)',
          gradeLevel: '12. Sınıf',
          institutionId: hqInstitutionId,
          baseScore: 100.0,
          maxScore: 500.0,
          wrongCorrectRatio: 4.0,
          optionCount: 5,
          subjects: [
            ExamSubject(
              branchName: 'Türk Dili ve Edebiyatı - Sosyal-1',
              questionCount: 40,
              coefficient: 3.0,
            ),
            ExamSubject(
              branchName: 'Sosyal Bilimler-2',
              questionCount: 40,
              coefficient: 2.9,
            ),
            ExamSubject(
              branchName: 'Matematik',
              questionCount: 40,
              coefficient: 3.0,
            ),
            ExamSubject(
              branchName: 'Fen Bilimleri',
              questionCount: 40,
              coefficient: 3.1,
            ),
          ],
        );
        break;
      default:
        template = ExamType(
          id: '',
          name: 'Genel Merkez Ortaokul Kurumsal Deneme (5-6-7)',
          gradeLevel: '7. Sınıf',
          institutionId: hqInstitutionId,
          baseScore: 100.0,
          maxScore: 500.0,
          wrongCorrectRatio: 3.0,
          optionCount: 4,
          subjects: [
            ExamSubject(
              branchName: 'Türkçe',
              questionCount: 15,
              coefficient: 5.333,
            ),
            ExamSubject(
              branchName: 'Matematik',
              questionCount: 15,
              coefficient: 5.333,
            ),
            ExamSubject(
              branchName: 'Fen Bilimleri',
              questionCount: 15,
              coefficient: 5.333,
            ),
            ExamSubject(
              branchName: 'Sosyal Bilgiler',
              questionCount: 10,
              coefficient: 3.0,
            ),
            ExamSubject(
              branchName: 'Din Kültürü ve Ahlak Bilgisi',
              questionCount: 10,
              coefficient: 2.5,
            ),
            ExamSubject(
              branchName: 'İngilizce',
              questionCount: 10,
              coefficient: 2.5,
            ),
          ],
        );
    }

    final docRef = _firestore.collection('exam_types').doc();
    final map = template.toMap();
    map['id'] = docRef.id;
    await docRef.set(map);
    return ExamType.fromMap(map, docRef.id);
  }

  // ---------------------------------------------------------------------------
  // 2. FETCH SCHOOLS + SCHOOL TYPES TREE
  // ---------------------------------------------------------------------------

  Future<List<CentralSchoolNode>> fetchSchoolsTree() async {
    final results = await Future.wait([
      _firestore.collection('schools').get(),
      _firestore.collection('schoolTypes').get(),
    ]);

    final schoolsSnap = results[0];
    final schoolTypesSnap = results[1];

    // Group schoolTypes by uppercase institutionId
    final Map<String, List<CentralSchoolTypeNode>> typesByInstUpper = {};
    for (final stDoc in schoolTypesSnap.docs) {
      final d = stDoc.data();
      if (d['isActive'] == false) continue;
      final rawInst =
          (d['institutionId'] ?? d['institution_id'] ?? d['schoolId'] ?? '')
              .toString()
              .trim();
      if (rawInst.isEmpty) continue;

      final stName =
          (d['schoolTypeName'] ??
                  d['name'] ??
                  d['schoolType'] ??
                  d['title'] ??
                  'Okul Türü')
              .toString()
              .trim();
      final activeGrades = (d['activeGrades'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();
      final category = CentralExamTarget.inferCategory(stName, activeGrades);

      typesByInstUpper
          .putIfAbsent(rawInst.toUpperCase(), () => [])
          .add(
            CentralSchoolTypeNode(
              schoolTypeId: stDoc.id,
              schoolTypeName: stName,
              category: category,
              activeGrades: activeGrades,
            ),
          );
    }

    final List<CentralSchoolNode> nodes = [];
    for (final sDoc in schoolsSnap.docs) {
      final d = sDoc.data();
      if (d['isActive'] == false) continue;

      final instId = (d['institutionId'] ?? d['institution_id'] ?? sDoc.id)
          .toString()
          .trim();
      final schoolName = (d['schoolName'] ?? d['name'] ?? instId)
          .toString()
          .trim();
      final city = (d['city'] ?? '').toString().trim();
      final district = (d['district'] ?? '').toString().trim();
      final rawRegion = (d['region'] ?? '').toString().trim();
      final region = rawRegion.isNotEmpty
          ? rawRegion
          : TurkeyAddressData.getRegion(city);

      final matchedTypes = <CentralSchoolTypeNode>[];
      final seenTypeIds = <String>{};
      for (final key in {instId.toUpperCase(), sDoc.id.toUpperCase()}) {
        final list = typesByInstUpper[key];
        if (list != null) {
          for (final t in list) {
            if (seenTypeIds.add(t.schoolTypeId)) {
              matchedTypes.add(t);
            }
          }
        }
      }

      matchedTypes.sort((a, b) => a.schoolTypeName.compareTo(b.schoolTypeName));

      nodes.add(
        CentralSchoolNode(
          schoolId: sDoc.id,
          institutionId: instId,
          schoolName: schoolName,
          city: city,
          district: district,
          region: region,
          isActive: d['isActive'] != false,
          schoolTypes: matchedTypes,
        ),
      );
    }

    nodes.sort((a, b) => a.schoolName.compareTo(b.schoolName));
    return nodes;
  }

  // ---------------------------------------------------------------------------
  // 3. SAVE & PROVISION / SYNC CENTRAL EXAM TO TARGET SCHOOLS
  // ---------------------------------------------------------------------------

  Future<CentralExam> saveAndProvisionCentralExam(CentralExam exam) async {
    final docRef = _firestore
        .collection('central_exams')
        .doc(exam.id.isEmpty ? null : exam.id);
    final centralExamId = docRef.id;

    // Load ExamType subjects for initializing new child sessions
    ExamType? examType;
    if (exam.examTypeId.isNotEmpty) {
      final etDoc = await _firestore
          .collection('exam_types')
          .doc(exam.examTypeId)
          .get();
      if (etDoc.exists && etDoc.data() != null) {
        examType = ExamType.fromMap(etDoc.data()!, etDoc.id);
      }
    }
    final allSubjectNames =
        examType?.subjects.map((s) => s.branchName).toList() ?? <String>[];

    final activeTermId =
        exam.termId ??
        await TermService().getSelectedTermId() ??
        await TermService().getActiveTermId();

    // Ensure deterministic childTrialExamId on every target
    final normalizedTargets = exam.targets
        .map(
          (t) => t.copyWith(
            childTrialExamId: CentralExamTarget.buildChildDocId(
              centralExamId,
              t.schoolTypeId,
            ),
          ),
        )
        .toList();

    final String nextStatus = exam.status == 'evaluated'
        ? 'evaluated'
        : (normalizedTargets.isNotEmpty ? 'assigned' : 'draft');

    final updatedCentralExam = exam.copyWith(
      id: centralExamId,
      targets: normalizedTargets,
      status: nextStatus,
      termId: activeTermId,
    );

    await docRef.set(updatedCentralExam.toMap(), SetOptions(merge: true));

    final defaultMasterSessions = _buildDefaultSessions(
      sessionCount: updatedCentralExam.sessionCount,
      allSubjects: allSubjectNames,
    );

    // Upsert HQ master pool container so SUPER_ADMIN can crop questions once
    // and all child school exams inherit trial_exams/{centralExamId}/questions_pool
    await _firestore.collection('trial_exams').doc(centralExamId).set({
      'id': centralExamId,
      'institutionId': hqInstitutionId,
      'isCentralExam': true,
      'centralExamId': centralExamId,
      'isPoolContainer': true,
      'isActive': true,
      'isLaunched': true,
      'name': updatedCentralExam.name,
      'classLevel': updatedCentralExam.classLevel,
      'examTypeId': updatedCentralExam.examTypeId,
      'examTypeName': updatedCentralExam.examTypeName,
      'applicationType': TrialExamApplicationType.optical.index,
      'bookletCount': updatedCentralExam.bookletCount,
      'sessionCount': updatedCentralExam.sessionCount,
      'durationMinutes': updatedCentralExam.durationMinutes,
      'sessions': defaultMasterSessions.map((s) => s.toMap()).toList(),
      'answerKeys': updatedCentralExam.answerKeys,
      'outcomes': updatedCentralExam.outcomes,
      'bookletMapping': updatedCentralExam.bookletMapping,
      'date': Timestamp.fromDate(updatedCentralExam.date),
      'applicationDate': Timestamp.fromDate(updatedCentralExam.date),
      if (activeTermId != null) 'termId': activeTermId,
    }, SetOptions(merge: true));

    // Fetch existing child trial_exams for this centralExamId (excluding pool container)
    final existingChildrenSnap = await _firestore
        .collection('trial_exams')
        .where('centralExamId', isEqualTo: centralExamId)
        .get();
    final Map<String, Map<String, dynamic>> existingChildById = {
      for (final d in existingChildrenSnap.docs)
        if (d.id != centralExamId &&
            d.data()['isPoolContainer'] != true &&
            d.data()['institutionId'] != hqInstitutionId)
          d.id: d.data(),
    };

    final Set<String> activeChildDocIds = {};
    final String gradeDigits = exam.classLevel.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );

    // Pre-fetch target school branches in parallel chunks of 15
    final Map<String, List<String>> preselectedBranchesByTypeId = {};
    const int branchChunkSize = 15;
    for (int i = 0; i < normalizedTargets.length; i += branchChunkSize) {
      final end = (i + branchChunkSize).clamp(0, normalizedTargets.length);
      final chunk = normalizedTargets.sublist(i, end);
      final branchResults = await Future.wait(
        chunk.map(
          (target) => _fetchTargetSchoolBranches(
            institutionId: target.institutionId,
            schoolTypeId: target.schoolTypeId,
            gradeDigits: gradeDigits,
          ),
        ),
      );
      for (int j = 0; j < chunk.length; j++) {
        preselectedBranchesByTypeId[chunk[j].schoolTypeId] = branchResults[j];
      }
    }

    var currentBatch = _firestore.batch();
    int currentBatchCount = 0;
    const int writeBatchChunkSize = 200;

    Future<void> flushBatchIfNeeded() async {
      if (currentBatchCount >= writeBatchChunkSize) {
        await currentBatch.commit();
        currentBatch = _firestore.batch();
        currentBatchCount = 0;
      }
    }

    // Provision or sync each target schoolType's TrialExam
    for (final target in normalizedTargets) {
      final childDocId = CentralExamTarget.buildChildDocId(
        centralExamId,
        target.schoolTypeId,
      );
      activeChildDocIds.add(childDocId);

      final preselectedBranches =
          preselectedBranchesByTypeId[target.schoolTypeId] ?? const <String>[];

      final childRef = _firestore.collection('trial_exams').doc(childDocId);
      final existingMap = existingChildById[childDocId];

      if (existingMap != null) {
        // PRESERVE school's optical sessions, resultsJson, isPublished, sharingSettings
        final existingTrial = TrialExam.fromMap(existingMap, childDocId);
        final mergedSessions = _mergeExistingSessions(
          existingSessions: existingTrial.sessions,
          sessionCount: updatedCentralExam.sessionCount,
          allSubjects: allSubjectNames,
        );
        final effectiveBranches = existingTrial.selectedBranches.isNotEmpty
            ? existingTrial.selectedBranches
            : preselectedBranches;

        final payload = <String, dynamic>{
          'id': childDocId,
          'institutionId': target.institutionId,
          'name': updatedCentralExam.name,
          'classLevel': updatedCentralExam.classLevel,
          'examTypeId': updatedCentralExam.examTypeId,
          'examTypeName': updatedCentralExam.examTypeName,
          'applicationType': TrialExamApplicationType.optical.index,
          'bookletCount': updatedCentralExam.bookletCount,
          'sessionCount': updatedCentralExam.sessionCount,
          'answerKeys': updatedCentralExam.answerKeys,
          'outcomes': updatedCentralExam.outcomes,
          'bookletMapping': updatedCentralExam.bookletMapping,
          'sessions': mergedSessions.map((s) => s.toMap()).toList(),
          'selectedBranches': effectiveBranches,
          'date': Timestamp.fromDate(updatedCentralExam.date),
          'applicationDate': Timestamp.fromDate(updatedCentralExam.date),
          'durationMinutes': updatedCentralExam.durationMinutes,
          'centralExamId': centralExamId,
          'isCentralExam': true,
          'targetSchoolTypeId': target.schoolTypeId,
          'isLaunched': true,
          'isActive': true,
          if (activeTermId != null) 'termId': activeTermId,
        };
        currentBatch.set(childRef, payload, SetOptions(merge: true));
        currentBatchCount++;
        await flushBatchIfNeeded();
      } else {
        final initialSessions = _buildDefaultSessions(
          sessionCount: updatedCentralExam.sessionCount,
          allSubjects: allSubjectNames,
        );

        final childExam = TrialExam(
          id: childDocId,
          institutionId: target.institutionId,
          name: updatedCentralExam.name,
          classLevel: updatedCentralExam.classLevel,
          examTypeId: updatedCentralExam.examTypeId,
          examTypeName: updatedCentralExam.examTypeName,
          applicationType: TrialExamApplicationType.optical,
          bookletCount: updatedCentralExam.bookletCount,
          sessionCount: updatedCentralExam.sessionCount,
          answerKeys: updatedCentralExam.answerKeys,
          outcomes: updatedCentralExam.outcomes,
          bookletMapping: updatedCentralExam.bookletMapping,
          sessions: initialSessions,
          selectedBranches: preselectedBranches,
          date: updatedCentralExam.date,
          isActive: true,
          isPublished: false,
          isLaunched: true,
          durationMinutes: updatedCentralExam.durationMinutes,
          termId: activeTermId,
          centralExamId: centralExamId,
          isCentralExam: true,
          targetSchoolTypeId: target.schoolTypeId,
        );

        final childMap = childExam.toMap();
        childMap['applicationDate'] = Timestamp.fromDate(
          updatedCentralExam.date,
        );
        currentBatch.set(childRef, childMap);
        currentBatchCount++;
        await flushBatchIfNeeded();
      }
    }

    // Cleanly deactivate removed targets IF they have no evaluated resultsJson yet
    for (final entry in existingChildById.entries) {
      if (!activeChildDocIds.contains(entry.key)) {
        final rJson = (entry.value['resultsJson'] ?? '').toString().trim();
        if (rJson.isEmpty || rJson == '[]') {
          final docRefToDeactivate = _firestore
              .collection('trial_exams')
              .doc(entry.key);
          currentBatch.update(docRefToDeactivate, {'isActive': false});
          currentBatchCount++;
          await flushBatchIfNeeded();
        }
      }
    }

    if (currentBatchCount > 0) {
      await currentBatch.commit();
    }

    return updatedCentralExam;
  }

  Future<void> deleteCentralExam(String centralExamId) async {
    final childSnap = await _firestore
        .collection('trial_exams')
        .where('centralExamId', isEqualTo: centralExamId)
        .get();

    var currentBatch = _firestore.batch();
    int currentBatchCount = 0;
    const int writeBatchChunkSize = 200;

    Future<void> flushBatchIfNeeded() async {
      if (currentBatchCount >= writeBatchChunkSize) {
        await currentBatch.commit();
        currentBatch = _firestore.batch();
        currentBatchCount = 0;
      }
    }

    bool deletedMasterContainer = false;
    for (final doc in childSnap.docs) {
      final data = doc.data();
      if (doc.id == centralExamId ||
          data['isPoolContainer'] == true ||
          data['institutionId'] == hqInstitutionId) {
        if (doc.id == centralExamId) deletedMasterContainer = true;
        currentBatch.delete(doc.reference);
        currentBatchCount++;
        await flushBatchIfNeeded();
        continue;
      }
      final rJson = (data['resultsJson'] ?? '').toString().trim();
      if (rJson.isEmpty || rJson == '[]') {
        currentBatch.update(doc.reference, {'isActive': false});
        currentBatchCount++;
        await flushBatchIfNeeded();
      }
    }
    if (!deletedMasterContainer) {
      final masterRef = _firestore.collection('trial_exams').doc(centralExamId);
      currentBatch.delete(masterRef);
      currentBatchCount++;
      await flushBatchIfNeeded();
    }

    if (currentBatchCount > 0) {
      await currentBatch.commit();
    }

    await _firestore.collection('central_exams').doc(centralExamId).delete();
  }

  Future<List<String>> _fetchTargetSchoolBranches({
    required String institutionId,
    required String schoolTypeId,
    required String gradeDigits,
  }) async {
    try {
      final variants = UserPermissionService.getInstitutionIdVariants(
        institutionId,
      );
      final QuerySnapshot<Map<String, dynamic>> snap = variants.length > 1
          ? await _firestore
                .collection('classes')
                .where('institutionId', whereIn: variants)
                .get()
          : await _firestore
                .collection('classes')
                .where('institutionId', isEqualTo: institutionId)
                .get();

      final allForSchoolType = <Map<String, dynamic>>[];
      final seenBranchNames = <String>{};
      for (final d in snap.docs) {
        final data = d.data();
        if (data['isActive'] == false) continue;
        final docStId = (data['schoolTypeId'] ?? '').toString();
        if (docStId.isEmpty || docStId == schoolTypeId) {
          final normName = (data['className'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          if (normName.isNotEmpty && seenBranchNames.add(normName)) {
            allForSchoolType.add(data);
          }
        }
      }

      if (gradeDigits.isNotEmpty) {
        final matchingGrade = allForSchoolType
            .where((data) {
              final lvlDigits = (data['classLevel'] ?? '')
                  .toString()
                  .replaceAll(RegExp(r'[^0-9]'), '');
              final cName = (data['className'] ?? '').toString().trim();
              final nameDigits =
                  RegExp(r'^\d+').firstMatch(cName)?.group(0) ?? '';
              return lvlDigits == gradeDigits || nameDigits == gradeDigits;
            })
            .map((d) => (d['className'] ?? '').toString().trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList();
        if (matchingGrade.isNotEmpty) {
          matchingGrade.sort();
          return matchingGrade;
        }
      }

      final fallback = allForSchoolType
          .map((d) => (d['className'] ?? '').toString().trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
      fallback.sort();
      return fallback;
    } catch (_) {
      return [];
    }
  }

  List<TrialExamSession> _buildDefaultSessions({
    required int sessionCount,
    required List<String> allSubjects,
  }) {
    if (sessionCount <= 1) {
      return [
        TrialExamSession(
          sessionNumber: 1,
          selectedSubjects: List<String>.from(allSubjects),
        ),
      ];
    }

    // For 2 sessions (e.g. LGS Sözel + Sayısal), split intelligently
    if (sessionCount == 2 && allSubjects.length == 6) {
      return [
        TrialExamSession(
          sessionNumber: 1,
          selectedSubjects: allSubjects.sublist(0, 4),
        ),
        TrialExamSession(
          sessionNumber: 2,
          selectedSubjects: allSubjects.sublist(4),
        ),
      ];
    }

    final List<TrialExamSession> sessions = [];
    final int perSession = allSubjects.isEmpty
        ? 0
        : (allSubjects.length / sessionCount).ceil();
    for (int i = 0; i < sessionCount; i++) {
      final start = i * perSession;
      final end = (start + perSession).clamp(0, allSubjects.length);
      final slice = start < allSubjects.length
          ? allSubjects.sublist(start, end)
          : <String>[];
      sessions.add(
        TrialExamSession(
          sessionNumber: i + 1,
          selectedSubjects: slice.isNotEmpty
              ? slice
              : List<String>.from(allSubjects),
        ),
      );
    }
    return sessions;
  }

  List<TrialExamSession> _mergeExistingSessions({
    required List<TrialExamSession> existingSessions,
    required int sessionCount,
    required List<String> allSubjects,
  }) {
    final defaults = _buildDefaultSessions(
      sessionCount: sessionCount,
      allSubjects: allSubjects,
    );
    final List<TrialExamSession> merged = [];
    for (int i = 0; i < sessionCount; i++) {
      if (i < existingSessions.length) {
        final prev = existingSessions[i];
        merged.add(
          prev.copyWith(
            sessionNumber: i + 1,
            selectedSubjects: prev.selectedSubjects.isNotEmpty
                ? prev.selectedSubjects
                : defaults[i].selectedSubjects,
          ),
        );
      } else {
        merged.add(defaults[i]);
      }
    }
    return merged;
  }

  // ---------------------------------------------------------------------------
  // 4. CHILD STATUS INSPECTION FOR LIVE PROGRESS MONITORING
  // ---------------------------------------------------------------------------

  Future<List<CentralChildExamStatus>> getChildExamStatuses(
    CentralExam exam,
  ) async {
    final snap = await _firestore
        .collection('trial_exams')
        .where('centralExamId', isEqualTo: exam.id)
        .get();

    final Map<String, TrialExam> childByDocId = {
      for (final d in snap.docs)
        if (d.id != exam.id &&
            d.data()['isPoolContainer'] != true &&
            d.data()['institutionId'] != hqInstitutionId)
          d.id: TrialExam.fromMap(d.data(), d.id),
    };

    final List<CentralChildExamStatus> statuses = [];
    for (final target in exam.targets) {
      final docId = target.childTrialExamId.isNotEmpty
          ? target.childTrialExamId
          : CentralExamTarget.buildChildDocId(exam.id, target.schoolTypeId);
      final child = childByDocId[docId];
      if (child == null) {
        statuses.add(
          CentralChildExamStatus(
            target: target,
            childExists: false,
            hasOpticalUpload: false,
            isEvaluatedLocally: false,
            isPublishedBySchool: false,
            participantCount: 0,
            avgScore: 0.0,
          ),
        );
        continue;
      }

      final hasUpload = child.sessions.any(
        (s) =>
            (s.fileName != null && s.fileName!.isNotEmpty) ||
            (s.fileUrl != null && s.fileUrl!.isNotEmpty),
      );

      int count = 0;
      double sumScore = 0.0;
      if (child.resultsJson != null && child.resultsJson!.isNotEmpty) {
        try {
          final decoded = jsonDecode(child.resultsJson!);
          if (decoded is List && decoded.isNotEmpty) {
            count = decoded.length;
            for (final item in decoded) {
              if (item is Map) {
                sumScore +=
                    num.tryParse(
                      (item['score'] ?? '0').toString(),
                    )?.toDouble() ??
                    0.0;
              }
            }
          }
        } catch (_) {}
      }

      statuses.add(
        CentralChildExamStatus(
          target: target,
          childExists: true,
          hasOpticalUpload: hasUpload,
          isEvaluatedLocally: count > 0,
          isPublishedBySchool: child.isPublished,
          participantCount: count,
          avgScore: count > 0 ? sumScore / count : 0.0,
          centralEvaluatedAt: child.centralEvaluatedAt,
        ),
      );
    }

    return statuses;
  }

  // ---------------------------------------------------------------------------
  // 5. GLOBAL MERGE EVALUATION & MULTI-DIMENSIONAL ANALYTICS
  // ---------------------------------------------------------------------------

  Future<CentralMergeResult> evaluateAndMergeCentralExam(
    String centralExamId,
  ) async {
    final exam = await getCentralExam(centralExamId);
    if (exam == null) {
      throw Exception('Merkezi deneme bulunamadı: $centralExamId');
    }

    ExamType? examType;
    if (exam.examTypeId.isNotEmpty) {
      final etDoc = await _firestore
          .collection('exam_types')
          .doc(exam.examTypeId)
          .get();
      if (etDoc.exists && etDoc.data() != null) {
        examType = ExamType.fromMap(etDoc.data()!, etDoc.id);
      }
    }

    final Map<String, int> subjectQuestionCounts = {
      if (examType != null)
        for (final s in examType.subjects) s.branchName: s.questionCount,
    };
    final List<String> orderedSubjects = [
      if (examType != null) ...examType.subjects.map((s) => s.branchName),
    ];

    final childSnap = await _firestore
        .collection('trial_exams')
        .where('centralExamId', isEqualTo: centralExamId)
        .where('isActive', isEqualTo: true)
        .get();

    // Target lookup by childTrialExamId and schoolTypeId
    final Map<String, CentralExamTarget> targetByDocId = {};
    for (final t in exam.targets) {
      final cid = t.childTrialExamId.isNotEmpty
          ? t.childTrialExamId
          : CentralExamTarget.buildChildDocId(centralExamId, t.schoolTypeId);
      targetByDocId[cid] = t.copyWith(childTrialExamId: cid);
    }

    final Map<String, List<StudentResult>> schoolStudentsByDocId = {};
    final Map<String, CentralExamTarget> participatingTargetsByDocId = {};
    final Set<String> evaluatedDocIds = {};

    for (final doc in childSnap.docs) {
      final data = doc.data();
      if (doc.id == centralExamId ||
          data['isPoolContainer'] == true ||
          data['institutionId'] == hqInstitutionId) {
        continue;
      }
      final rJson = (data['resultsJson'] ?? '').toString().trim();
      if (rJson.isEmpty || rJson == '[]') continue;

      List<StudentResult> parsedStudents = [];
      try {
        final decoded = jsonDecode(rJson);
        if (decoded is List) {
          parsedStudents = decoded
              .whereType<Map>()
              .map((m) => StudentResult.fromJson(Map<String, dynamic>.from(m)))
              .toList();
        }
      } catch (_) {}

      if (parsedStudents.isEmpty) continue;

      // Re-score every student with non-empty optical answers against latest HQ answerKeys
      if (exam.answerKeys.isNotEmpty) {
        final double ratio =
            (examType != null && examType.wrongCorrectRatio > 0)
            ? examType.wrongCorrectRatio
            : 4.0;
        for (final st in parsedStudents) {
          if (st.answers.isEmpty) continue;

          bool updatedAnySubject = false;
          for (final ansEntry in st.answers.entries) {
            final subjName = ansEntry.key;
            final sAns = ansEntry.value;
            final bookletKey = _resolveBookletKeyForSubject(
              student: st,
              subject: subjName,
              answerKeys: exam.answerKeys,
            );
            final bookletMap =
                exam.answerKeys[bookletKey] ??
                exam.answerKeys['A'] ??
                const <String, String>{};
            String? refAns = bookletMap[subjName];
            if (refAns == null) {
              for (final k in bookletMap.keys) {
                if (k.trim().toLowerCase() == subjName.trim().toLowerCase()) {
                  refAns = bookletMap[k];
                  break;
                }
              }
            }
            if (refAns == null || refAns.isEmpty) continue;

            int correct = 0;
            int wrong = 0;
            int empty = 0;
            for (int q = 0; q < refAns.length; q++) {
              final sChar = q < sAns.length ? sAns[q] : ' ';
              final rChar = refAns[q];
              final status = TrialExam.evaluateAnswer(sChar, rChar);
              if (status == AnswerStatus.correct) {
                correct++;
              } else if (status == AnswerStatus.wrong) {
                wrong++;
              } else {
                empty++;
              }
            }

            final net = correct - (wrong / ratio);
            st.subjects[subjName] = SubjectStats(
              correct: correct,
              wrong: wrong,
              empty: empty,
              net: net,
            );
            st.correctAnswers[subjName] = refAns;
            updatedAnySubject = true;
          }

          if (updatedAnySubject && examType != null) {
            double recalculatedScore = examType.baseScore;
            st.subjects.forEach((subjName, stats) {
              final subjectDef = examType!.subjects.firstWhere(
                (s) =>
                    s.branchName.trim().toLowerCase() ==
                    subjName.trim().toLowerCase(),
                orElse: () => ExamSubject(
                  branchName: '',
                  questionCount: 0,
                  coefficient: 0,
                ),
              );
              if (subjectDef.coefficient > 0) {
                recalculatedScore += stats.net * subjectDef.coefficient;
              }
            });
            if (recalculatedScore < 0) recalculatedScore = 0.0;
            st.score = recalculatedScore;
          }
        }
      }

      // Ensure local rankInstitution and rankBranch are preserved accurately
      parsedStudents.sort((a, b) => b.score.compareTo(a.score));
      int instRank = 0;
      for (int i = 0; i < parsedStudents.length; i++) {
        if (i == 0 ||
            (parsedStudents[i].score - parsedStudents[i - 1].score).abs() >=
                0.001) {
          instRank++;
        }
        parsedStudents[i].rankInstitution = instRank;
      }

      final Map<String, List<StudentResult>> byBranch = {};
      for (final s in parsedStudents) {
        byBranch.putIfAbsent(s.branch, () => []).add(s);
      }
      byBranch.forEach((_, bList) {
        int bRank = 0;
        for (int i = 0; i < bList.length; i++) {
          if (i == 0 || (bList[i].score - bList[i - 1].score).abs() >= 0.001) {
            bRank++;
          }
          bList[i].rankBranch = bRank;
        }
      });

      final target =
          targetByDocId[doc.id] ??
          CentralExamTarget(
            schoolId: (data['institutionId'] ?? '').toString(),
            institutionId: (data['institutionId'] ?? '').toString(),
            schoolName: (data['institutionId'] ?? 'Okul').toString(),
            schoolTypeId: (data['targetSchoolTypeId'] ?? '').toString(),
            schoolTypeName: 'Okul Kademesi',
            schoolTypeCategory: 'Diğer',
            region: 'Belirtilmemiş',
            childTrialExamId: doc.id,
          );

      evaluatedDocIds.add(doc.id);
      schoolStudentsByDocId[doc.id] = parsedStudents;
      participatingTargetsByDocId[doc.id] = target;
    }

    final List<CentralExamTarget> pendingTargets = [];
    for (final t in exam.targets) {
      final cid = t.childTrialExamId.isNotEmpty
          ? t.childTrialExamId
          : CentralExamTarget.buildChildDocId(centralExamId, t.schoolTypeId);
      if (!evaluatedDocIds.contains(cid)) {
        pendingTargets.add(t);
      }
    }

    if (schoolStudentsByDocId.isEmpty) {
      throw Exception(
        'Henüz hiçbir okul optik okuma ve değerlendirme işlemini tamamlamadı.',
      );
    }

    // Build global combined student list across ALL participating schools
    final List<_GlobalStudentEntry> globalEntries = [];
    schoolStudentsByDocId.forEach((docId, list) {
      final target = participatingTargetsByDocId[docId]!;
      for (final student in list) {
        globalEntries.add(
          _GlobalStudentEntry(
            childDocId: docId,
            target: target,
            student: student,
          ),
        );
        for (final subj in student.subjects.keys) {
          if (!orderedSubjects.contains(subj)) {
            orderedSubjects.add(subj);
          }
        }
      }
    });

    // Global sort by score descending & assign global rankGeneral
    globalEntries.sort((a, b) => b.student.score.compareTo(a.student.score));
    int globalRank = 0;
    for (int i = 0; i < globalEntries.length; i++) {
      if (i == 0 ||
          (globalEntries[i].student.score - globalEntries[i - 1].student.score)
                  .abs() >=
              0.001) {
        globalRank++;
      }
      globalEntries[i].student.rankGeneral = globalRank;
    }

    final int totalParticipants = globalEntries.length;
    final int participatingSchoolsCount = schoolStudentsByDocId.length;

    // Accumulators for Global, Region, City, School, and Outcomes
    double globalScoreSum = 0.0;
    double globalMaxScore = globalEntries.first.student.score;
    double globalMinScore = globalEntries.last.student.score;
    double globalNetSum = 0.0;

    final Map<String, _SubjectAccumulator> globalSubjAcc = {};
    final Map<String, Map<String, _OutcomeCounter>> globalOutcomeMap = {};

    // Region accumulators
    final Map<String, Set<String>> regionSchools = {};
    final Map<String, List<double>> regionScores = {};
    final Map<String, double> regionNetSum = {};
    final Map<String, Map<String, _SubjectAccumulator>> regionSubjAcc = {};
    final Map<String, Map<String, Map<String, _OutcomeCounter>>>
    regionOutcomeMap = {};

    // City accumulators
    final Map<String, String> cityToRegionMap = {};
    final Map<String, Set<String>> citySchools = {};
    final Map<String, List<double>> cityScores = {};
    final Map<String, double> cityNetSum = {};
    final Map<String, Map<String, _SubjectAccumulator>> citySubjAcc = {};

    // School accumulators
    final Map<String, Map<String, _SubjectAccumulator>> schoolSubjAcc = {};
    final Map<String, Map<String, Map<String, _OutcomeCounter>>>
    schoolOutcomeMap = {};

    for (final entry in globalEntries) {
      final st = entry.student;
      final t = entry.target;
      final region = t.region.isNotEmpty ? t.region : 'Belirtilmemiş';
      final city = t.city.isNotEmpty
          ? TurkeyAddressData.toUpperTr(t.city)
          : 'BELİRTİLMEMİŞ';
      final docId = entry.childDocId;

      globalScoreSum += st.score;
      if (st.score > globalMaxScore) globalMaxScore = st.score;
      if (st.score < globalMinScore) globalMinScore = st.score;

      final totalNet = st.total.net;
      globalNetSum += totalNet;

      regionSchools.putIfAbsent(region, () => {}).add(docId);
      regionScores.putIfAbsent(region, () => []).add(st.score);
      regionNetSum[region] = (regionNetSum[region] ?? 0.0) + totalNet;

      cityToRegionMap[city] = region;
      citySchools.putIfAbsent(city, () => {}).add(docId);
      cityScores.putIfAbsent(city, () => []).add(st.score);
      cityNetSum[city] = (cityNetSum[city] ?? 0.0) + totalNet;

      for (final subj in orderedSubjects) {
        final stats = st.subjects[subj] ?? SubjectStats();
        final qCount = subjectQuestionCounts[subj] ?? 0;

        globalSubjAcc
            .putIfAbsent(subj, () => _SubjectAccumulator())
            .add(stats, qCount);
        regionSubjAcc
            .putIfAbsent(region, () => {})
            .putIfAbsent(subj, () => _SubjectAccumulator())
            .add(stats, qCount);
        citySubjAcc
            .putIfAbsent(city, () => {})
            .putIfAbsent(subj, () => _SubjectAccumulator())
            .add(stats, qCount);
        schoolSubjAcc
            .putIfAbsent(docId, () => {})
            .putIfAbsent(subj, () => _SubjectAccumulator())
            .add(stats, qCount);

        // Outcome mastery re-evaluation using student's booklet & answer key
        final bookletKey = st.booklet.trim().isNotEmpty
            ? st.booklet.trim()[0].toUpperCase()
            : 'A';
        final refAnswers =
            exam.answerKeys[bookletKey]?[subj] ??
            exam.answerKeys['A']?[subj] ??
            st.correctAnswers[subj] ??
            '';
        final outcomesForSubj =
            exam.outcomes[bookletKey]?[subj] ??
            exam.outcomes['A']?[subj] ??
            const <String>[];
        final studentAns = st.answers[subj] ?? '';

        if (outcomesForSubj.isNotEmpty && refAnswers.isNotEmpty) {
          final limit = outcomesForSubj.length < refAnswers.length
              ? outcomesForSubj.length
              : refAnswers.length;
          for (int q = 0; q < limit; q++) {
            final outcomeText = outcomesForSubj[q].trim();
            if (outcomeText.isEmpty) continue;
            final sChar = q < studentAns.length ? studentAns[q] : ' ';
            final rChar = refAnswers[q];
            final ansStatus = TrialExam.evaluateAnswer(sChar, rChar);

            void recordOutcome(_OutcomeCounter counter) {
              counter.total++;
              counter.questionIndices.add(q + 1);
              if (ansStatus == AnswerStatus.correct) {
                counter.correct++;
              } else if (ansStatus == AnswerStatus.wrong) {
                counter.wrong++;
              } else {
                counter.empty++;
              }
            }

            recordOutcome(
              globalOutcomeMap
                  .putIfAbsent(subj, () => {})
                  .putIfAbsent(outcomeText, () => _OutcomeCounter()),
            );
            recordOutcome(
              regionOutcomeMap
                  .putIfAbsent(region, () => {})
                  .putIfAbsent(subj, () => {})
                  .putIfAbsent(outcomeText, () => _OutcomeCounter()),
            );
            recordOutcome(
              schoolOutcomeMap
                  .putIfAbsent(docId, () => {})
                  .putIfAbsent(subj, () => {})
                  .putIfAbsent(outcomeText, () => _OutcomeCounter()),
            );
          }
        }
      }
    }

    final double globalAvgScore = globalScoreSum / totalParticipants;
    final double globalAvgNet = globalNetSum / totalParticipants;

    final Map<String, Map<String, dynamic>> globalSubjectsSummary = {
      for (final subj in orderedSubjects)
        subj: (globalSubjAcc[subj] ?? _SubjectAccumulator()).toSummaryMap(),
    };

    // Region breakdown
    final Map<String, double> regionAvgScoreLookup = {};
    final Map<String, Map<String, Map<String, dynamic>>>
    regionSubjectSummaryLookup = {};

    final List<Map<String, dynamic>> bolgelerList = [];
    regionScores.forEach((region, scores) {
      final rAvg = scores.reduce((a, b) => a + b) / scores.length;
      final rNet = (regionNetSum[region] ?? 0.0) / scores.length;
      regionAvgScoreLookup[region] = rAvg;

      final Map<String, Map<String, dynamic>> rSubjs = {
        for (final subj in orderedSubjects)
          subj: (regionSubjAcc[region]?[subj] ?? _SubjectAccumulator())
              .toSummaryMap(),
      };
      regionSubjectSummaryLookup[region] = rSubjs;

      // Weakest outcomes in this region
      final List<Map<String, dynamic>> rWeak = [];
      regionOutcomeMap[region]?.forEach((subj, outMap) {
        outMap.forEach((outText, counter) {
          final genRate = globalOutcomeMap[subj]?[outText]?.correctRate ?? 0.0;
          if (counter.correctRate < 55.0 ||
              (counter.correctRate - genRate) <= -10.0) {
            rWeak.add({
              'subject': subj,
              'outcome': outText,
              'successRate': double.parse(
                counter.correctRate.toStringAsFixed(1),
              ),
              'generalRate': double.parse(genRate.toStringAsFixed(1)),
            });
          }
        });
      });
      rWeak.sort(
        (a, b) => (a['successRate'] as num).compareTo(b['successRate'] as num),
      );

      bolgelerList.add({
        'region': region,
        'schoolCount': regionSchools[region]?.length ?? 0,
        'studentCount': scores.length,
        'avgScore': double.parse(rAvg.toStringAsFixed(2)),
        'avgNet': double.parse(rNet.toStringAsFixed(2)),
        'diffFromGeneral': double.parse(
          (rAvg - globalAvgScore).toStringAsFixed(2),
        ),
        'subjects': rSubjs,
        'weakOutcomes': rWeak.take(8).toList(),
      });
    });
    bolgelerList.sort(
      (a, b) => (b['avgScore'] as num).compareTo(a['avgScore'] as num),
    );

    // City breakdown
    final List<Map<String, dynamic>> illerList = [];
    cityScores.forEach((city, scores) {
      final cAvg = scores.reduce((a, b) => a + b) / scores.length;
      final cNet = (cityNetSum[city] ?? 0.0) / scores.length;
      final Map<String, Map<String, dynamic>> cSubjs = {
        for (final subj in orderedSubjects)
          subj: (citySubjAcc[city]?[subj] ?? _SubjectAccumulator())
              .toSummaryMap(),
      };
      illerList.add({
        'city': city,
        'region': cityToRegionMap[city] ?? 'Belirtilmemiş',
        'schoolCount': citySchools[city]?.length ?? 0,
        'studentCount': scores.length,
        'avgScore': double.parse(cAvg.toStringAsFixed(2)),
        'avgNet': double.parse(cNet.toStringAsFixed(2)),
        'diffFromGeneral': double.parse(
          (cAvg - globalAvgScore).toStringAsFixed(2),
        ),
        'subjects': cSubjs,
      });
    });
    illerList.sort(
      (a, b) => (b['avgScore'] as num).compareTo(a['avgScore'] as num),
    );

    // School & SchoolType breakdown + Weak Outcomes Needs Analysis
    final Map<String, Map<String, int>> outcomeSchoolsNeedingSupport = {};
    final List<Map<String, dynamic>> okullarList = [];

    schoolStudentsByDocId.forEach((docId, stList) {
      final target = participatingTargetsByDocId[docId]!;
      final region = target.region.isNotEmpty ? target.region : 'Belirtilmemiş';
      final sCount = stList.length;
      final sAvgScore =
          stList.fold<double>(0.0, (sum, s) => sum + s.score) / sCount;
      final sMaxScore = stList
          .map((s) => s.score)
          .reduce((a, b) => a > b ? a : b);
      final sMinScore = stList
          .map((s) => s.score)
          .reduce((a, b) => a < b ? a : b);
      final sAvgNet =
          stList.fold<double>(0.0, (sum, s) => sum + s.total.net) / sCount;
      final rAvgScore = regionAvgScoreLookup[region] ?? globalAvgScore;

      final Map<String, Map<String, dynamic>> sSubjs = {
        for (final subj in orderedSubjects)
          subj: (schoolSubjAcc[docId]?[subj] ?? _SubjectAccumulator())
              .toSummaryMap(),
      };

      // Weak outcomes for this school
      final List<Map<String, dynamic>> sWeakOutcomes = [];
      schoolOutcomeMap[docId]?.forEach((subj, outMap) {
        outMap.forEach((outText, counter) {
          final schoolRate = counter.correctRate;
          final genRate = globalOutcomeMap[subj]?[outText]?.correctRate ?? 0.0;
          final regRate =
              regionOutcomeMap[region]?[subj]?[outText]?.correctRate ?? genRate;

          final needsSupport =
              schoolRate < 50.0 || (schoolRate - genRate) <= -10.0;
          if (needsSupport || schoolRate < 55.0) {
            if (needsSupport) {
              final subjSupport = outcomeSchoolsNeedingSupport.putIfAbsent(
                subj,
                () => {},
              );
              subjSupport[outText] = (subjSupport[outText] ?? 0) + 1;
            }
            final priority =
                (schoolRate < 40.0 || (schoolRate - genRate) <= -15.0)
                ? 'ACİL DESTEK'
                : 'GELİŞTİRİLMELİ';
            sWeakOutcomes.add(
              WeakOutcomeNeed(
                subject: subj,
                outcome: outText,
                questionCount: counter.questionIndices.isNotEmpty
                    ? counter.questionIndices.length
                    : 1,
                schoolSuccessRate: double.parse(schoolRate.toStringAsFixed(1)),
                regionSuccessRate: double.parse(regRate.toStringAsFixed(1)),
                generalSuccessRate: double.parse(genRate.toStringAsFixed(1)),
                priority: priority,
              ).toMap(),
            );
          }
        });
      });

      // Fallback: if outcome mapping wasn't entered on the exam, highlight weak subjects (< 55% successRate)
      if (sWeakOutcomes.isEmpty) {
        for (final subj in orderedSubjects) {
          final sSubjMap = sSubjs[subj] ?? {};
          final genSubjMap = globalSubjectsSummary[subj] ?? {};
          final regSubjMap = regionSubjectSummaryLookup[region]?[subj] ?? {};
          final sRate = (sSubjMap['successRate'] as num?)?.toDouble() ?? 0.0;
          final gRate = (genSubjMap['successRate'] as num?)?.toDouble() ?? 0.0;
          final rRate =
              (regSubjMap['successRate'] as num?)?.toDouble() ?? gRate;
          if (sRate < 55.0 || (sRate - gRate) <= -10.0) {
            sWeakOutcomes.add(
              WeakOutcomeNeed(
                subject: subj,
                outcome: '$subj Genel Branş Kazanımları',
                questionCount:
                    (sSubjMap['questionCount'] as num?)?.toInt() ?? 0,
                schoolSuccessRate: sRate,
                regionSuccessRate: rRate,
                generalSuccessRate: gRate,
                priority: sRate < 40.0 ? 'ACİL DESTEK' : 'GELİŞTİRİLMELİ',
              ).toMap(),
            );
          }
        }
      }

      sWeakOutcomes.sort(
        (a, b) => (a['schoolSuccessRate'] as num).compareTo(
          b['schoolSuccessRate'] as num,
        ),
      );

      okullarList.add({
        'childTrialExamId': docId,
        'schoolId': target.schoolId,
        'institutionId': target.institutionId,
        'schoolName': target.schoolName,
        'schoolTypeId': target.schoolTypeId,
        'schoolTypeName': target.schoolTypeName,
        'schoolTypeCategory': target.schoolTypeCategory,
        'city': target.city,
        'district': target.district,
        'region': region,
        'studentCount': sCount,
        'avgScore': double.parse(sAvgScore.toStringAsFixed(2)),
        'maxScore': double.parse(sMaxScore.toStringAsFixed(2)),
        'minScore': double.parse(sMinScore.toStringAsFixed(2)),
        'avgNet': double.parse(sAvgNet.toStringAsFixed(2)),
        'regionAvgScore': double.parse(rAvgScore.toStringAsFixed(2)),
        'diffFromGeneral': double.parse(
          (sAvgScore - globalAvgScore).toStringAsFixed(2),
        ),
        'diffFromRegion': double.parse(
          (sAvgScore - rAvgScore).toStringAsFixed(2),
        ),
        'subjects': sSubjs,
        'weakOutcomes': sWeakOutcomes.take(25).toList(),
      });
    });

    // Rank schools by avgScore descending
    okullarList.sort(
      (a, b) => (b['avgScore'] as num).compareTo(a['avgScore'] as num),
    );
    final Map<String, int> schoolRankByDocId = {};
    for (int i = 0; i < okullarList.length; i++) {
      final rank = i + 1;
      okullarList[i]['schoolRank'] = rank;
      schoolRankByDocId[okullarList[i]['childTrialExamId'].toString()] = rank;
    }

    // Global outcome mastery map
    final Map<String, List<Map<String, dynamic>>> kazanimlarSummary = {};
    globalOutcomeMap.forEach((subj, outMap) {
      final List<Map<String, dynamic>> list = [];
      outMap.forEach((outText, counter) {
        list.add({
          'outcome': outText,
          'questionCount': counter.questionIndices.isNotEmpty
              ? counter.questionIndices.length
              : 1,
          'correctRate': double.parse(counter.correctRate.toStringAsFixed(1)),
          'wrongRate': double.parse(counter.wrongRate.toStringAsFixed(1)),
          'emptyRate': double.parse(counter.emptyRate.toStringAsFixed(1)),
          'schoolsNeedingSupportCount':
              outcomeSchoolsNeedingSupport[subj]?[outText] ?? 0,
        });
      });
      list.sort(
        (a, b) => (a['correctRate'] as num).compareTo(b['correctRate'] as num),
      );
      kazanimlarSummary[subj] = list.take(40).toList();
    });

    // Top 50 Leaderboard (compact & privacy-aware initials/name)
    final List<Map<String, dynamic>> topLeaderboard = globalEntries
        .take(50)
        .map(
          (e) => {
            'rank': e.student.rankGeneral,
            'studentName': _maskStudentName(e.student.name),
            'schoolName': e.target.schoolName,
            'schoolTypeName': e.target.schoolTypeName,
            'city': e.target.city,
            'region': e.target.region,
            'score': double.parse(e.student.score.toStringAsFixed(2)),
            'net': double.parse(e.student.total.net.toStringAsFixed(2)),
          },
        )
        .toList();

    final Map<String, dynamic> analyticsSummary = {
      'orderedSubjects': orderedSubjects,
      'genel': {
        'totalParticipants': totalParticipants,
        'participatingSchoolsCount': participatingSchoolsCount,
        'assignedSchoolsCount': exam.targets.length,
        'pendingSchoolsCount': pendingTargets.length,
        'avgScore': double.parse(globalAvgScore.toStringAsFixed(2)),
        'maxScore': double.parse(globalMaxScore.toStringAsFixed(2)),
        'minScore': double.parse(globalMinScore.toStringAsFixed(2)),
        'avgNet': double.parse(globalAvgNet.toStringAsFixed(2)),
        'subjects': globalSubjectsSummary,
        'topLeaderboard': topLeaderboard,
      },
      'bolgeler': bolgelerList,
      'iller': illerList,
      'okullar': okullarList,
      'bekleyenOkullar': pendingTargets.map((t) => t.toMap()).toList(),
      'kazanimlar': kazanimlarSummary,
    };

    // Write back updated resultsJson (with global rankGeneral) and centralSummary to EACH participating school
    final Map<String, double> globalSubjectNetAvgs = {
      for (final subj in orderedSubjects)
        subj:
            (globalSubjectsSummary[subj]?['avgNet'] as num?)?.toDouble() ?? 0.0,
    };

    final schoolEntriesList = schoolStudentsByDocId.entries.toList();
    const int schoolUpdateChunkSize = 6;
    for (int i = 0; i < schoolEntriesList.length; i += schoolUpdateChunkSize) {
      final end = (i + schoolUpdateChunkSize).clamp(
        0,
        schoolEntriesList.length,
      );
      final chunk = schoolEntriesList.sublist(i, end);
      await Future.wait(
        chunk.map((entry) {
          final docId = entry.key;
          final stList = entry.value;
          final target = participatingTargetsByDocId[docId]!;
          final region = target.region.isNotEmpty
              ? target.region
              : 'Belirtilmemiş';
          final schoolAvg =
              stList.fold<double>(0.0, (s, item) => s + item.score) /
              stList.length;
          final schoolRank = schoolRankByDocId[docId] ?? 0;
          final regAvg = regionAvgScoreLookup[region] ?? globalAvgScore;

          final updatedJson = jsonEncode(
            stList.map((s) => s.toJson()).toList(),
          );

          return _firestore.collection('trial_exams').doc(docId).update({
            'resultsJson': updatedJson,
            'centralTotalParticipants': totalParticipants,
            'centralEvaluatedAt': FieldValue.serverTimestamp(),
            'centralSummary': {
              'totalParticipants': totalParticipants,
              'participatingSchools': participatingSchoolsCount,
              'avgScore': double.parse(globalAvgScore.toStringAsFixed(2)),
              'schoolAvgScore': double.parse(schoolAvg.toStringAsFixed(2)),
              'subjectAverages': globalSubjectNetAvgs,
              'schoolRank': schoolRank,
              'totalRankedSchools': participatingSchoolsCount,
              'regionName': region,
              'regionAvgScore': double.parse(regAvg.toStringAsFixed(2)),
            },
          });
        }),
      );
    }

    // Update parent CentralExam document
    await _firestore.collection('central_exams').doc(centralExamId).update({
      'status': 'evaluated',
      'totalParticipants': totalParticipants,
      'participatingSchoolsCount': participatingSchoolsCount,
      'lastEvaluatedAt': FieldValue.serverTimestamp(),
      'analyticsSummary': analyticsSummary,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return CentralMergeResult(
      totalParticipants: totalParticipants,
      participatingSchoolsCount: participatingSchoolsCount,
      pendingSchoolsCount: pendingTargets.length,
      globalAvgScore: globalAvgScore,
      analyticsSummary: analyticsSummary,
    );
  }

  String _resolveBookletKeyForSubject({
    required StudentResult student,
    required String subject,
    required Map<String, Map<String, String>> answerKeys,
  }) {
    if (answerKeys.isEmpty) return 'A';
    final rawBooklet = student.booklet.trim().toUpperCase();
    final validBooklets = <String>[];
    for (int i = 0; i < rawBooklet.length; i++) {
      final ch = rawBooklet[i];
      if (answerKeys.containsKey(ch) && !validBooklets.contains(ch)) {
        validBooklets.add(ch);
      }
    }
    if (validBooklets.isEmpty) {
      return answerKeys.containsKey('A') ? 'A' : answerKeys.keys.first;
    }
    if (validBooklets.length == 1) {
      return validBooklets.first;
    }
    final prevRef = student.correctAnswers[subject] ?? '';
    if (prevRef.isNotEmpty) {
      String bestBooklet = validBooklets.first;
      int bestOverlap = -1;
      for (final b in validBooklets) {
        final cand = answerKeys[b]?[subject] ?? '';
        int overlap = 0;
        final limit = prevRef.length < cand.length
            ? prevRef.length
            : cand.length;
        for (int i = 0; i < limit; i++) {
          if (prevRef[i].toUpperCase() == cand[i].toUpperCase()) overlap++;
        }
        if (overlap > bestOverlap) {
          bestOverlap = overlap;
          bestBooklet = b;
        }
      }
      return bestBooklet;
    }
    return validBooklets.first;
  }

  String _maskStudentName(String fullName) {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return 'Öğrenci';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first;
    final firstNames = parts.sublist(0, parts.length - 1).join(' ');
    final lastInitial = parts.last.isNotEmpty ? '${parts.last[0]}.' : '';
    return '$firstNames $lastInitial';
  }

  // ---------------------------------------------------------------------------
  // 6. GENERATE, SEND & STREAM SCHOOL REPORTS + OFFICIAL PDF GENERATOR
  // ---------------------------------------------------------------------------

  CentralSchoolReport buildSchoolReportFromAnalytics({
    required CentralExam exam,
    required Map<String, dynamic> schoolEntry,
    String advisorNote = '',
  }) {
    final summary = exam.analyticsSummary;
    final genel = summary['genel'] is Map
        ? Map<String, dynamic>.from(summary['genel'] as Map)
        : <String, dynamic>{};
    final orderedSubjects = (summary['orderedSubjects'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    final generalSubjects = genel['subjects'] is Map
        ? Map<String, dynamic>.from(genel['subjects'] as Map)
        : <String, dynamic>{};

    final regionName = (schoolEntry['region'] ?? 'Belirtilmemiş').toString();
    Map<String, dynamic> regionEntry = {};
    for (final r in (summary['bolgeler'] as List<dynamic>? ?? [])) {
      if (r is Map && r['region'] == regionName) {
        regionEntry = Map<String, dynamic>.from(r);
        break;
      }
    }
    final regionSubjects = regionEntry['subjects'] is Map
        ? Map<String, dynamic>.from(regionEntry['subjects'] as Map)
        : <String, dynamic>{};
    final schoolSubjects = schoolEntry['subjects'] is Map
        ? Map<String, dynamic>.from(schoolEntry['subjects'] as Map)
        : <String, dynamic>{};

    final List<Map<String, dynamic>> subjectComparisons = [];
    final subjectsToIterate = orderedSubjects.isNotEmpty
        ? orderedSubjects
        : schoolSubjects.keys.toList();

    for (final subj in subjectsToIterate) {
      final sMap = schoolSubjects[subj] is Map
          ? Map<String, dynamic>.from(schoolSubjects[subj] as Map)
          : <String, dynamic>{};
      final rMap = regionSubjects[subj] is Map
          ? Map<String, dynamic>.from(regionSubjects[subj] as Map)
          : <String, dynamic>{};
      final gMap = generalSubjects[subj] is Map
          ? Map<String, dynamic>.from(generalSubjects[subj] as Map)
          : <String, dynamic>{};

      final sNet = (sMap['avgNet'] as num?)?.toDouble() ?? 0.0;
      final rNet = (rMap['avgNet'] as num?)?.toDouble() ?? 0.0;
      final gNet = (gMap['avgNet'] as num?)?.toDouble() ?? 0.0;
      final sRate = (sMap['successRate'] as num?)?.toDouble() ?? 0.0;
      final gRate = (gMap['successRate'] as num?)?.toDouble() ?? 0.0;
      final qCount =
          (sMap['questionCount'] as num?)?.toInt() ??
          (gMap['questionCount'] as num?)?.toInt() ??
          0;

      subjectComparisons.add({
        'subject': subj,
        'questionCount': qCount,
        'schoolNet': sNet,
        'regionNet': rNet,
        'generalNet': gNet,
        'schoolSuccessRate': sRate,
        'generalSuccessRate': gRate,
        'diffNet': double.parse((sNet - gNet).toStringAsFixed(2)),
      });
    }

    final weakList = (schoolEntry['weakOutcomes'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((m) => WeakOutcomeNeed.fromMap(Map<String, dynamic>.from(m)))
        .toList();

    final schoolAvgScore = (schoolEntry['avgScore'] as num?)?.toDouble() ?? 0.0;
    final generalAvgScore = (genel['avgScore'] as num?)?.toDouble() ?? 0.0;
    final regionAvgScore =
        (schoolEntry['regionAvgScore'] as num?)?.toDouble() ?? generalAvgScore;

    final List<String> autoRecommendations = _generateActionRecommendations(
      schoolAvgScore: schoolAvgScore,
      generalAvgScore: generalAvgScore,
      subjectComparisons: subjectComparisons,
      weakOutcomes: weakList,
    );

    final schoolTypeId = (schoolEntry['schoolTypeId'] ?? '').toString();
    final reportId = '${exam.id}_$schoolTypeId';

    return CentralSchoolReport(
      id: reportId,
      centralExamId: exam.id,
      centralExamName: exam.name,
      classLevel: exam.classLevel,
      examTypeName: exam.examTypeName,
      examDate: exam.date,
      schoolId: (schoolEntry['schoolId'] ?? '').toString(),
      institutionId: (schoolEntry['institutionId'] ?? '').toString(),
      schoolName: (schoolEntry['schoolName'] ?? '').toString(),
      schoolTypeId: schoolTypeId,
      schoolTypeName: (schoolEntry['schoolTypeName'] ?? '').toString(),
      city: (schoolEntry['city'] ?? '').toString(),
      region: regionName,
      createdAt: DateTime.now(),
      participantCount: (schoolEntry['studentCount'] as num?)?.toInt() ?? 0,
      generalParticipantCount:
          (genel['totalParticipants'] as num?)?.toInt() ?? 0,
      schoolAvgScore: schoolAvgScore,
      regionAvgScore: regionAvgScore,
      generalAvgScore: generalAvgScore,
      schoolMaxScore: (schoolEntry['maxScore'] as num?)?.toDouble() ?? 0.0,
      schoolRank: (schoolEntry['schoolRank'] as num?)?.toInt() ?? 0,
      totalParticipatingSchools:
          (genel['participatingSchoolsCount'] as num?)?.toInt() ?? 0,
      subjectComparisons: subjectComparisons,
      ihtiyacAnalizi: weakList,
      advisorNote: advisorNote.trim().isNotEmpty
          ? advisorNote.trim()
          : _buildDefaultAdvisorNote(
              schoolName: (schoolEntry['schoolName'] ?? 'Kurumunuz').toString(),
              schoolAvg: schoolAvgScore,
              generalAvg: generalAvgScore,
              weakCount: weakList.length,
            ),
      actionRecommendations: autoRecommendations,
    );
  }

  String buildDefaultAdvisorNote(
    CentralExam exam,
    Map<String, dynamic> schoolEntry,
  ) {
    final genel = exam.analyticsSummary['genel'] is Map
        ? Map<String, dynamic>.from(exam.analyticsSummary['genel'] as Map)
        : <String, dynamic>{};
    final schoolAvgScore = (schoolEntry['avgScore'] as num?)?.toDouble() ?? 0.0;
    final generalAvgScore = (genel['avgScore'] as num?)?.toDouble() ?? 0.0;
    final weakCount = (schoolEntry['weakOutcomes'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .length;
    return _buildDefaultAdvisorNote(
      schoolName: (schoolEntry['schoolName'] ?? 'Kurumunuz').toString(),
      schoolAvg: schoolAvgScore,
      generalAvg: generalAvgScore,
      weakCount: weakCount,
    );
  }

  String _buildDefaultAdvisorNote({
    required String schoolName,
    required double schoolAvg,
    required double generalAvg,
    required int weakCount,
  }) {
    final diff = schoolAvg - generalAvg;
    if (diff >= 5.0) {
      return '$schoolName merkezi değerlendirmede genel ortalamanın +${diff.toStringAsFixed(2)} puan üzerinde güçlü bir akademik performans sergilemiştir. Derece adayı öğrencilerin üst düzey muhakeme çalışmalarıyla desteklenmesi ve tespit edilen $weakCount kazanımda nokta atışı telafi yapılması önerilir.';
    } else if (diff >= -5.0) {
      return '$schoolName merkezi değerlendirmede genel Türkiye/Merkez ortalaması bandında dengeli bir grafik çizmiştir. İhtiyaç listesindeki $weakCount öncelikli kazanıma yönelik şube bazlı etüt ve kazanım tarama testleri ile ortalamanın üst segmente taşınması hedeflenmelidir.';
    } else {
      return '$schoolName genel merkez ortalamasının ${diff.abs().toStringAsFixed(2)} puan gerisinde kalmıştır. İhtiyaç analizinde "ACİL DESTEK" olarak işaretlenen $weakCount kazanım için branş zümreleriyle haftalık telafi planı oluşturulması ve eksik konuların tekrar edilmesi kritik önem taşımaktadır.';
    }
  }

  List<String> _generateActionRecommendations({
    required double schoolAvgScore,
    required double generalAvgScore,
    required List<Map<String, dynamic>> subjectComparisons,
    required List<WeakOutcomeNeed> weakOutcomes,
  }) {
    final List<String> recs = [];
    final laggingSubjects = subjectComparisons
        .where((s) => ((s['diffNet'] as num?)?.toDouble() ?? 0.0) < -0.5)
        .map((s) => s['subject'].toString())
        .toList();

    if (laggingSubjects.isNotEmpty) {
      recs.add(
        'Genel merkez net ortalamasının gerisinde kalan branşlarda (${laggingSubjects.join(", ")}) zümre değerlendirme toplantısı yapılarak soru çözüm saatleri artırılmalıdır.',
      );
    }

    final urgentOutcomes = weakOutcomes
        .where((w) => w.priority == 'ACİL DESTEK')
        .take(3)
        .toList();
    if (urgentOutcomes.isNotEmpty) {
      final names = urgentOutcomes
          .map((u) => '${u.subject}: ${u.outcome}')
          .join(' | ');
      recs.add(
        'Acil destek gerektiren öncelikli kazanımlar için hızlandırılmış etüt/kamp planlanmalıdır: $names.',
      );
    }

    recs.add(
      'Merkezi Soru Havuzu ve Hata Kitapçığı modülü üzerinden bu sınavda yanlış/boş bırakılan sorularla öğrencilere kişiye özel telafi föyleri dağıtılmalıdır.',
    );

    if (schoolAvgScore >= generalAvgScore) {
      recs.add(
        'Genel ortalamanın üzerindeki mevcut ivmeyi korumak adına üst dilimdeki öğrencilere yeni nesil seçici soru kampları uygulanmalıdır.',
      );
    }
    return recs;
  }

  Future<CentralSchoolReport> sendReportToSchool({
    required CentralExam exam,
    required Map<String, dynamic> schoolEntry,
    String advisorNote = '',
    bool createSchoolAnnouncement = true,
  }) async {
    final report = buildSchoolReportFromAnalytics(
      exam: exam,
      schoolEntry: schoolEntry,
      advisorNote: advisorNote,
    );

    await _firestore
        .collection('central_exam_reports')
        .doc(report.id)
        .set(report.toMap(), SetOptions(merge: true));

    if (createSchoolAnnouncement && report.schoolId.isNotEmpty) {
      try {
        final now = DateTime.now();
        await _firestore.collection('schools').doc(report.schoolId).collection('announcements').add({
          'title':
              '📊 Genel Merkez Değerlendirme Raporu: ${report.centralExamName}',
          'content':
              '${report.centralExamName} (${report.classLevel}) merkezi değerlendirme raporu yayınlanmıştır.\n'
              '• Katılan Öğrenci: ${report.participantCount} (Genel: ${report.generalParticipantCount})\n'
              '• Okul Ortalaması: ${report.schoolAvgScore.toStringAsFixed(2)} | Bölge: ${report.regionAvgScore.toStringAsFixed(2)} | Genel: ${report.generalAvgScore.toStringAsFixed(2)}\n'
              '• Kurum Sıralaması: ${report.schoolRank} / ${report.totalParticipatingSchools}\n'
              'Detaylı kazanım ihtiyaç listesini ve resmi PDF raporunu Ölçme Değerlendirme > Genel Merkez Raporları ekranından inceleyebilirsiniz.',
          'recipients': ['role:Yönetici', 'role:Öğretmen'],
          'publishDate': Timestamp.fromDate(now),
          'publishTime': DateFormat('HH:mm').format(now),
          'sendSms': false,
          'links': [],
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': 'superadmin@edukn.com',
          'creatorName': 'Genel Merkez Ölçme Değerlendirme',
          'isAnonymous': false,
          'status': 'published',
          'approvalStatus': 'approved',
          'schedulePublish': false,
          'reminders': [],
          'isReminder': false,
          'readBy': <String>[],
          'institutionId': report.institutionId,
          'schoolId': report.schoolId,
          'isActive': true,
          'schoolTypeId': report.schoolTypeId,
          'targetSchoolTypeIds': [
            if (report.schoolTypeId.isNotEmpty) report.schoolTypeId,
          ],
        });
      } catch (_) {}
    }

    return report;
  }

  Future<int> sendReportsToAllParticipatingSchools({
    required CentralExam exam,
    String advisorNote = '',
    bool createSchoolAnnouncement = true,
  }) async {
    final okullar = (exam.analyticsSummary['okullar'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();

    int count = 0;
    const int reportChunkSize = 10;
    for (int i = 0; i < okullar.length; i += reportChunkSize) {
      final end = (i + reportChunkSize).clamp(0, okullar.length);
      final chunk = okullar.sublist(i, end);
      await Future.wait(
        chunk.map(
          (schoolEntry) => sendReportToSchool(
            exam: exam,
            schoolEntry: schoolEntry,
            advisorNote: advisorNote,
            createSchoolAnnouncement: createSchoolAnnouncement,
          ),
        ),
      );
      count += chunk.length;
    }
    return count;
  }

  Stream<List<CentralSchoolReport>> streamSchoolReports({
    required String institutionId,
    String? schoolTypeId,
  }) {
    final variants = UserPermissionService.getInstitutionIdVariants(
      institutionId,
    );
    final Query<Map<String, dynamic>> query = variants.length > 1
        ? _firestore
              .collection('central_exam_reports')
              .where('institutionId', whereIn: variants)
        : _firestore
              .collection('central_exam_reports')
              .where('institutionId', isEqualTo: institutionId);

    return query.snapshots().map((snap) {
      var list = snap.docs
          .map((d) => CentralSchoolReport.fromMap(d.data(), d.id))
          .toList();
      if (schoolTypeId != null && schoolTypeId.isNotEmpty) {
        list = list
            .where(
              (r) => r.schoolTypeId.isEmpty || r.schoolTypeId == schoolTypeId,
            )
            .toList();
      }
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  // ---------------------------------------------------------------------------
  // 7. TURKISH PDF REPORT BUILDER (PdfGoogleFonts.roboto*)
  // ---------------------------------------------------------------------------

  Future<Uint8List> generateSchoolReportPdfBytes(
    CentralSchoolReport report,
  ) async {
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fontMedium = await PdfGoogleFonts.robotoMedium();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
    );

    final dateStr = DateFormat('dd.MM.yyyy').format(report.examDate);
    final diffGeneral = report.schoolAvgScore - report.generalAvgScore;
    final diffSign = diffGeneral >= 0 ? '+' : '';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 14),
          padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#1E293B'),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'GENEL MERKEZ ÖLÇME VE DEĞERLENDİRME RAPORU',
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 9,
                        color: PdfColor.fromHex('#93C5FD'),
                        letterSpacing: 0.8,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      report.centralExamName,
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 15,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      '${report.schoolName} • ${report.schoolTypeName} (${report.region} / ${report.city})',
                      style: pw.TextStyle(
                        font: fontMedium,
                        fontSize: 10,
                        color: PdfColor.fromHex('#E2E8F0'),
                      ),
                    ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Sınav Tarihi: $dateStr',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '${report.classLevel} • ${report.examTypeName}',
                    style: pw.TextStyle(
                      fontSize: 9,
                      color: PdfColor.fromHex('#CBD5E1'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        footer: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 10),
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(
                color: PdfColor.fromHex('#E2E8F0'),
                width: 0.8,
              ),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'eduKN Genel Merkez Kurumsal Değerlendirme Sistemi',
                style: pw.TextStyle(
                  fontSize: 8,
                  color: PdfColor.fromHex('#64748B'),
                ),
              ),
              pw.Text(
                'Sayfa ${context.pageNumber} / ${context.pagesCount}',
                style: pw.TextStyle(
                  fontSize: 8,
                  color: PdfColor.fromHex('#64748B'),
                ),
              ),
            ],
          ),
        ),
        build: (context) => [
          // KPI Row
          pw.Row(
            children: [
              pw.Expanded(
                child: _pdfKpiBox(
                  title: 'Katılan Öğrenci',
                  value: '${report.participantCount}',
                  subtitle: 'Genel: ${report.generalParticipantCount} Öğrenci',
                  accentHex: '#2563EB',
                  fontBold: fontBold,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _pdfKpiBox(
                  title: 'Okul Ortalaması',
                  value: report.schoolAvgScore.toStringAsFixed(2),
                  subtitle:
                      'Genel Fark: $diffSign${diffGeneral.toStringAsFixed(2)}p',
                  accentHex: diffGeneral >= 0 ? '#059669' : '#DC2626',
                  fontBold: fontBold,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _pdfKpiBox(
                  title: 'Bölge / Genel Ort.',
                  value:
                      '${report.regionAvgScore.toStringAsFixed(1)} / ${report.generalAvgScore.toStringAsFixed(1)}',
                  subtitle: report.region,
                  accentHex: '#7C3AED',
                  fontBold: fontBold,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _pdfKpiBox(
                  title: 'Kurum Sıralaması',
                  value:
                      '${report.schoolRank} / ${report.totalParticipatingSchools}',
                  subtitle: 'Katılan Okullar Arası',
                  accentHex: '#D97706',
                  fontBold: fontBold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),

          // Section 1: Subject Comparisons
          pw.Text(
            '1. Branş Bazlı Karşılaştırmalı Net ve Başarı Analizi',
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 12,
              color: PdfColor.fromHex('#0F172A'),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(
              color: PdfColor.fromHex('#CBD5E1'),
              width: 0.6,
            ),
            columnWidths: {
              0: const pw.FlexColumnWidth(2.6),
              1: const pw.FlexColumnWidth(0.9),
              2: const pw.FlexColumnWidth(1.2),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FlexColumnWidth(1.2),
              5: const pw.FlexColumnWidth(1.2),
              6: const pw.FlexColumnWidth(1.2),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#F1F5F9'),
                ),
                children: [
                  _pdfCell('Ders / Branş', fontBold, isHeader: true),
                  _pdfCell('Soru', fontBold, isHeader: true, alignRight: true),
                  _pdfCell(
                    'Okul Net',
                    fontBold,
                    isHeader: true,
                    alignRight: true,
                  ),
                  _pdfCell(
                    'Bölge Net',
                    fontBold,
                    isHeader: true,
                    alignRight: true,
                  ),
                  _pdfCell(
                    'Genel Net',
                    fontBold,
                    isHeader: true,
                    alignRight: true,
                  ),
                  _pdfCell(
                    'Başarı %',
                    fontBold,
                    isHeader: true,
                    alignRight: true,
                  ),
                  _pdfCell(
                    'Genel Fark',
                    fontBold,
                    isHeader: true,
                    alignRight: true,
                  ),
                ],
              ),
              ...report.subjectComparisons.map((row) {
                final diff = (row['diffNet'] as num?)?.toDouble() ?? 0.0;
                final diffTxt =
                    '${diff >= 0 ? "+" : ""}${diff.toStringAsFixed(2)}';
                return pw.TableRow(
                  children: [
                    _pdfCell((row['subject'] ?? '').toString(), fontMedium),
                    _pdfCell(
                      '${row['questionCount'] ?? 0}',
                      fontRegular,
                      alignRight: true,
                    ),
                    _pdfCell(
                      ((row['schoolNet'] as num?)?.toDouble() ?? 0.0)
                          .toStringAsFixed(2),
                      fontBold,
                      alignRight: true,
                    ),
                    _pdfCell(
                      ((row['regionNet'] as num?)?.toDouble() ?? 0.0)
                          .toStringAsFixed(2),
                      fontRegular,
                      alignRight: true,
                    ),
                    _pdfCell(
                      ((row['generalNet'] as num?)?.toDouble() ?? 0.0)
                          .toStringAsFixed(2),
                      fontRegular,
                      alignRight: true,
                    ),
                    _pdfCell(
                      '%${((row['schoolSuccessRate'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(1)}',
                      fontRegular,
                      alignRight: true,
                    ),
                    _pdfCell(
                      diffTxt,
                      fontBold,
                      alignRight: true,
                      color: diff >= 0
                          ? PdfColor.fromHex('#059669')
                          : PdfColor.fromHex('#DC2626'),
                    ),
                  ],
                );
              }),
            ],
          ),
          pw.SizedBox(height: 18),

          // Section 2: Priority Outcome Needs
          pw.Text(
            '2. Kazanım Bazlı İhtiyaç ve Güçlendirme Listesi',
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 12,
              color: PdfColor.fromHex('#0F172A'),
            ),
          ),
          pw.SizedBox(height: 6),
          if (report.ihtiyacAnalizi.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#ECFDF5'),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Text(
                'Tebrikler! %55 başarı eşiğinin altında kalan kritik kazanım tespit edilmemiştir.',
                style: pw.TextStyle(
                  font: fontMedium,
                  fontSize: 9.5,
                  color: PdfColor.fromHex('#065F46'),
                ),
              ),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(
                color: PdfColor.fromHex('#CBD5E1'),
                width: 0.6,
              ),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.6),
                1: const pw.FlexColumnWidth(3.6),
                2: const pw.FlexColumnWidth(1.1),
                3: const pw.FlexColumnWidth(1.1),
                4: const pw.FlexColumnWidth(1.4),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#FEF2F2'),
                  ),
                  children: [
                    _pdfCell('Branş', fontBold, isHeader: true),
                    _pdfCell('Kazanım / Konu', fontBold, isHeader: true),
                    _pdfCell(
                      'Okul %',
                      fontBold,
                      isHeader: true,
                      alignRight: true,
                    ),
                    _pdfCell(
                      'Genel %',
                      fontBold,
                      isHeader: true,
                      alignRight: true,
                    ),
                    _pdfCell('Öncelik', fontBold, isHeader: true),
                  ],
                ),
                ...report.ihtiyacAnalizi.map((need) {
                  final isUrgent = need.priority == 'ACİL DESTEK';
                  return pw.TableRow(
                    children: [
                      _pdfCell(need.subject, fontMedium),
                      _pdfCell(need.outcome, fontRegular),
                      _pdfCell(
                        '%${need.schoolSuccessRate.toStringAsFixed(1)}',
                        fontBold,
                        alignRight: true,
                        color: isUrgent
                            ? PdfColor.fromHex('#DC2626')
                            : PdfColor.fromHex('#D97706'),
                      ),
                      _pdfCell(
                        '%${need.generalSuccessRate.toStringAsFixed(1)}',
                        fontRegular,
                        alignRight: true,
                      ),
                      _pdfCell(
                        need.priority,
                        fontBold,
                        color: isUrgent
                            ? PdfColor.fromHex('#DC2626')
                            : PdfColor.fromHex('#B45309'),
                      ),
                    ],
                  );
                }),
              ],
            ),
          pw.SizedBox(height: 18),

          // Section 3: HQ Advisor Commentary & Recommendations
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F8FAFC'),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              border: pw.Border.all(
                color: PdfColor.fromHex('#CBD5E1'),
                width: 0.8,
              ),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '3. Genel Merkez Akademik Değerlendirme ve Eylem Önerileri',
                  style: pw.TextStyle(
                    font: fontBold,
                    fontSize: 11,
                    color: PdfColor.fromHex('#1E3A8A'),
                  ),
                ),
                if (report.advisorNote.isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Text(
                    report.advisorNote,
                    style: const pw.TextStyle(fontSize: 9.5, lineSpacing: 2),
                  ),
                ],
                if (report.actionRecommendations.isNotEmpty) ...[
                  pw.SizedBox(height: 8),
                  ...report.actionRecommendations.map(
                    (rec) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 4),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            '• ',
                            style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 10,
                              color: PdfColor.fromHex('#2563EB'),
                            ),
                          ),
                          pw.Expanded(
                            child: pw.Text(
                              rec,
                              style: const pw.TextStyle(fontSize: 9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _pdfKpiBox({
    required String title,
    required String value,
    required String subtitle,
    required String accentHex,
    required pw.Font fontBold,
  }) {
    final accent = PdfColor.fromHex(accentHex);
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0'), width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 8,
              color: PdfColor.fromHex('#64748B'),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(font: fontBold, fontSize: 13, color: accent),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            subtitle,
            style: pw.TextStyle(
              fontSize: 7.5,
              color: PdfColor.fromHex('#475569'),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfCell(
    String text,
    pw.Font font, {
    bool isHeader = false,
    bool alignRight = false,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          font: font,
          fontSize: isHeader ? 8.5 : 8.5,
          color: color ?? PdfColor.fromHex('#0F172A'),
        ),
      ),
    );
  }
}
