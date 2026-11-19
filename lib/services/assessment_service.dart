import 'dart:async';
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

  Stream<List<ExamType>> getExamTypes(String institutionId, {String? termId}) {
    return _firestore
        .collection('exam_types')
        .where('institutionId', isEqualTo: institutionId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          var list = snapshot.docs
              .map((doc) => ExamType.fromMap(doc.data(), doc.id))
              .toList();
          if (termId != null) {
            list = list.where((e) {
              final docTermId = e.toMap()['termId'];
              return docTermId == null || docTermId == termId;
            }).toList();
          }
          return list;
        });
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

  Stream<List<OpticalForm>> getOpticalForms(
    String institutionId, {
    String? termId,
  }) {
    return _firestore
        .collection('optical_forms')
        .where('institutionId', isEqualTo: institutionId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          var list = snapshot.docs
              .map((doc) => OpticalForm.fromMap(doc.data(), doc.id))
              .toList();
          if (termId != null) {
            list = list.where((e) {
              final docTermId = e.toMap()['termId'];
              return docTermId == null || docTermId == termId;
            }).toList();
          }
          return list;
        });
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

  // Dönem aralığı önbelleği (termId -> [başlangıç, bitiş]); eğitim yılı 1 Eylül - 31 Ağustos
  final Map<String, List<DateTime>?> _termRangeCache = {};

  Future<List<DateTime>?> _termDateRange(String termId) async {
    if (_termRangeCache.containsKey(termId)) return _termRangeCache[termId];
    try {
      final doc = await _firestore.collection('terms').doc(termId).get();
      final data = doc.data();
      final startYear = int.tryParse('${data?['startYear']}');
      final endYear = int.tryParse('${data?['endYear']}');
      if (startYear == null || endYear == null) {
        _termRangeCache[termId] = null;
        return null;
      }
      final range = [
        DateTime(startYear, 9, 1),
        DateTime(endYear, 8, 31, 23, 59, 59),
      ];
      _termRangeCache[termId] = range;
      return range;
    } catch (_) {
      return null;
    }
  }

  Stream<List<TrialExam>> getTrialExams(
    String institutionId, {
    List<String>? classLevels,
    String? termId,
  }) {
    return _firestore
        .collection('trial_exams')
        .where('institutionId', isEqualTo: institutionId)
        .where('isActive', isEqualTo: true)
        .orderBy('date', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          var exams = snapshot.docs
              .map((doc) => TrialExam.fromMap(doc.data(), doc.id))
              .toList();

          // Client-side termId filtreleme (composite index gerektirmez)
          if (termId != null && termId.isNotEmpty) {
            final range = await _termDateRange(termId);
            exams = exams.where((exam) {
              final t = exam.termId;
              if (t != null && t.isNotEmpty) return t == termId;
              // Dönemi hiç atanmamış (eski) sınavlar: sınav tarihine göre dönemi belirle
              if (range == null) return false;
              return !exam.date.isBefore(range[0]) &&
                  !exam.date.isAfter(range[1]);
            }).toList();
          }

          if (classLevels != null && classLevels.isNotEmpty) {
            return exams
                .where((exam) => classLevels.contains(exam.classLevel))
                .toList();
          }

          return exams;
        });
  }

  Future<void> deleteTrialExam(String id) async {
    await _firestore.collection('trial_exams').doc(id).update({
      'isActive': false,
    });
  }

  // --- Question Pool ---
  static final RegExp _digitsOnlyClassRe = RegExp(r'^\d+$');
  static final RegExp _leadingClassRe = RegExp(
    r'^(\d+)\.\s*s[ıi]n[ıi]f',
    caseSensitive: false,
  );
  static final RegExp _anyClassRe = RegExp(
    r'(\d+)\.\s*s[ıi]n[ıi]f',
    caseSensitive: false,
  );

  /// Kurum bazlı bellek içi soru havuzu önbelleği (sekme geçişlerinde ve sihirbaz açılışında 0ms açılış sağlar).
  static final Map<String, List<Map<String, dynamic>>> _poolCacheByInst = {};
  static final Map<String, List<Map<String, dynamic>>> _containerPoolCache = {};

  static List<Map<String, dynamic>>? getCachedQuestionsPool(String institutionId) =>
      _poolCacheByInst[institutionId];

  static void invalidatePoolCache([String? examOrContainerId]) {
    if (examOrContainerId != null && examOrContainerId.isNotEmpty) {
      _containerPoolCache.remove(examOrContainerId);
    } else {
      _containerPoolCache.clear();
    }
  }

  /// Streams all cropped questions across all active trial exams AND the
  /// standalone question pool (`pool_$institutionId`) of the institution
  /// without requiring a Firestore `collectionGroup` composite index.
  static String normalizeClassLevel(String? raw, {String? examName}) {
    final s = (raw ?? '').trim();
    if (s.isNotEmpty) {
      if (_digitsOnlyClassRe.hasMatch(s)) return '$s. Sınıf';
      final m = _leadingClassRe.firstMatch(s);
      if (m != null) return '${m.group(1)}. Sınıf';
      return s;
    }
    if (examName != null && examName.isNotEmpty) {
      final m = _anyClassRe.firstMatch(examName);
      if (m != null) return '${m.group(1)}. Sınıf';
    }
    return '7. Sınıf';
  }

  static void _sortPoolQuestions(List<Map<String, dynamic>> allQuestions) {
    allQuestions.sort((a, b) {
      final Timestamp? tsA = a['updatedAt'] is Timestamp
          ? a['updatedAt'] as Timestamp
          : null;
      final Timestamp? tsB = b['updatedAt'] is Timestamp
          ? b['updatedAt'] as Timestamp
          : null;
      if (tsA != null && tsB != null) {
        final cmp = tsB.compareTo(tsA);
        if (cmp != 0) return cmp;
      }
      final String subA = (a['subject'] ?? '').toString();
      final String subB = (b['subject'] ?? '').toString();
      final int subCmp = subA.compareTo(subB);
      if (subCmp != 0) return subCmp;
      final int qA = (num.tryParse('${a['questionNo']}') ?? 0).toInt();
      final int qB = (num.tryParse('${b['questionNo']}') ?? 0).toInt();
      return qA.compareTo(qB);
    });
  }

  Future<List<Map<String, dynamic>>> _fetchContainerQuestions(
    String containerId, {
    required String fallbackExamName,
    required String fallbackClassLevel,
    bool isCentral = false,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _containerPoolCache.containsKey(containerId)) {
      return _containerPoolCache[containerId]!;
    }
    final List<Map<String, dynamic>> list = [];
    try {
      final poolSnap = await _firestore
          .collection('trial_exams')
          .doc(containerId)
          .collection('questions_pool')
          .get()
          .timeout(const Duration(seconds: 10));
      for (final qDoc in poolSnap.docs) {
        final qData = Map<String, dynamic>.from(qDoc.data());
        qData['docId'] = qDoc.id;
        qData['poolKey'] = '$containerId/${qDoc.id}';
        qData['examId'] = qData['examId'] ?? containerId;
        qData['examName'] = qData['examName'] ?? fallbackExamName;
        if (isCentral) qData['isCentralPool'] = true;
        qData['classLevel'] = normalizeClassLevel(
          (qData['classLevel'] ?? fallbackClassLevel).toString(),
          examName: (qData['examName'] ?? fallbackExamName).toString(),
        );
        list.add(qData);
      }
      _containerPoolCache[containerId] = list;
    } catch (_) {}
    return list;
  }

  Stream<List<Map<String, dynamic>>> getGlobalQuestionsPool(
    String institutionId,
  ) {
    return Stream.multi((controller) {
      bool isClosed = false;
      void emitSafe(List<Map<String, dynamic>> list) {
        if (!isClosed && !controller.isClosed) {
          _poolCacheByInst[institutionId] = list;
          controller.add(list);
        }
      }

      // 1) Önbellekte veri varsa 0ms'de anında gönder (bekleme çarkı hiç dönmesin)
      final cached = _poolCacheByInst[institutionId];
      if (cached != null && cached.isNotEmpty) {
        controller.add(cached);
      }

      // 2) Ana soru havuzunu (`pool_$institutionId`) trial_exams sorgusunu beklemeden anında çek
      final String standalonePoolId = 'pool_$institutionId';
      bool fullLoadCompleted = false;
      _fetchContainerQuestions(
        standalonePoolId,
        fallbackExamName: 'Soru Havuzu',
        fallbackClassLevel: '',
        forceRefresh: true,
      ).then((standaloneQs) {
        if (fullLoadCompleted || isClosed) return;
        if (standaloneQs.isNotEmpty &&
            (_poolCacheByInst[institutionId] == null ||
                _poolCacheByInst[institutionId]!.isEmpty)) {
          final initial = List<Map<String, dynamic>>.from(standaloneQs);
          _sortPoolQuestions(initial);
          emitSafe(initial);
        }
      });

      // 3) Kurumun aktif deneme sınavları + genel merkez + ana havuz birleşimi
      final sub = _firestore
          .collection('trial_exams')
          .where('institutionId', isEqualTo: institutionId)
          .snapshots()
          .listen(
            (examsSnap) async {
              final Map<String, Map<String, dynamic>> byPoolKey = {};
              final Set<String> visitedExamIds = {};
              final Set<String> centralExamContainers = {};

              final activeDocs = examsSnap.docs.where((doc) {
                final d = doc.data();
                return d['isActive'] == true ||
                    d['isPoolContainer'] == true ||
                    doc.id == standalonePoolId;
              }).toList();

              for (final examDoc in activeDocs) {
                final examData = examDoc.data();
                final String centralId = (examData['centralExamId'] ?? '')
                    .toString()
                    .trim();
                if (centralId.isNotEmpty) {
                  centralExamContainers.add(centralId);
                }
              }

              final List<Future<List<Map<String, dynamic>>>> futures = [];

              for (final examDoc in activeDocs) {
                visitedExamIds.add(examDoc.id);
                final examData = examDoc.data();
                final String examName = (examData['name'] ?? 'Soru Havuzu')
                    .toString();
                final String classLevel = (examData['classLevel'] ?? '')
                    .toString();
                futures.add(
                  _fetchContainerQuestions(
                    examDoc.id,
                    fallbackExamName: examName,
                    fallbackClassLevel: classLevel,
                    forceRefresh: examDoc.id == standalonePoolId,
                  ),
                );
              }

              for (final centralId in centralExamContainers) {
                if (visitedExamIds.contains(centralId)) continue;
                visitedExamIds.add(centralId);
                futures.add(
                  _fetchContainerQuestions(
                    centralId,
                    fallbackExamName: 'Genel Merkez Denemesi',
                    fallbackClassLevel: '',
                    isCentral: true,
                  ),
                );
              }

              final Set<String> candidateStandalonePools = {
                standalonePoolId,
                'pool_${institutionId.trim().toUpperCase()}',
                'pool_${institutionId.trim().toLowerCase()}',
                'pool_SUPER_ADMIN',
              };
              for (final pid in candidateStandalonePools) {
                if (visitedExamIds.contains(pid)) continue;
                visitedExamIds.add(pid);
                futures.add(
                  _fetchContainerQuestions(
                    pid,
                    fallbackExamName: 'Soru Havuzu',
                    fallbackClassLevel: '',
                    forceRefresh: pid == standalonePoolId,
                  ),
                );
              }

              final results = await Future.wait(futures);
              for (final chunk in results) {
                for (final q in chunk) {
                  final pk = (q['poolKey'] ?? q['docId'] ?? '').toString();
                  if (pk.isNotEmpty) {
                    byPoolKey[pk] = q;
                  }
                }
              }

              final allQuestions = byPoolKey.values.toList();
              _sortPoolQuestions(allQuestions);
              fullLoadCompleted = true;
              emitSafe(allQuestions);
            },
            onError: (Object e, StackTrace st) {
              if (!isClosed && !controller.isClosed) {
                controller.addError(e, st);
              }
            },
          );

      controller.onCancel = () {
        isClosed = true;
        sub.cancel();
      };
    });
  }

  Future<void> updatePoolQuestion(
    String examId,
    String docId,
    Map<String, dynamic> updates,
  ) async {
    await _firestore
        .collection('trial_exams')
        .doc(examId)
        .collection('questions_pool')
        .doc(docId)
        .update({...updates, 'updatedAt': FieldValue.serverTimestamp()});
    final cachedContainer = _containerPoolCache[examId];
    if (cachedContainer != null) {
      for (final q in cachedContainer) {
        if (q['docId'] == docId) {
          q.addAll(updates);
          break;
        }
      }
    }
    for (final list in _poolCacheByInst.values) {
      for (final q in list) {
        if (q['examId'] == examId && q['docId'] == docId) {
          q.addAll(updates);
          break;
        }
      }
    }
  }

  Future<void> deleteFromPool(String examId, String docId) async {
    await _firestore
        .collection('trial_exams')
        .doc(examId)
        .collection('questions_pool')
        .doc(docId)
        .delete();
    _containerPoolCache[examId]?.removeWhere((q) => q['docId'] == docId);
    for (final list in _poolCacheByInst.values) {
      list.removeWhere((q) => q['examId'] == examId && q['docId'] == docId);
    }
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

  Stream<List<OutcomeList>> getOutcomeLists(
    String institutionId, {
    String? termId,
  }) {
    return _firestore
        .collection('outcome_lists')
        .where('institutionId', isEqualTo: institutionId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          var list = snapshot.docs
              .map((doc) => OutcomeList.fromMap(doc.data(), doc.id))
              .toList();
          if (termId != null) {
            list = list.where((e) {
              final docTermId = e.toMap()['termId'];
              return docTermId == null || docTermId == termId;
            }).toList();
          }
          return list;
        });
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

  /// Updates only the given nested fields (path -> value) so concurrent edits
  /// by different users on other keys are not overwritten.
  Future<void> updateActionPlanFields(
    String id,
    Map<List<String>, dynamic> fields,
  ) async {
    final Map<Object, Object?> data = {};
    fields.forEach((path, value) {
      data[FieldPath(path)] = value;
    });
    await _firestore.collection('assessment_action_plans').doc(id).update(data);
  }

  Future<String> saveAssessmentActionPlan(AssessmentActionPlan plan) async {
    print(
      'Saving Action Plan: ID=${plan.id}, Title=${plan.title}, Institution=${plan.institutionId}, SchoolType=${plan.schoolTypeId}',
    );
    final docRef = _firestore
        .collection('assessment_action_plans')
        .doc(plan.id.isEmpty ? null : plan.id);

    final data = plan.toMap();
    if (plan.id.isEmpty) {
      data['id'] = docRef.id;
    }

    await docRef.set(data, SetOptions(merge: true));
    print('Action Plan saved successfully with ID: ${data['id']}');
    return docRef.id;
  }

  Stream<List<AssessmentActionPlan>> getAssessmentActionPlans(
    String institutionId,
    String schoolTypeId,
  ) {
    print(
      'Fetching Action Plans: Institution=$institutionId, SchoolType=$schoolTypeId',
    );

    // Using a simpler query to avoid composite index requirements.
    // Filtering and sorting are handled in-memory for immediate use.
    return _firestore
        .collection('assessment_action_plans')
        .where('institutionId', isEqualTo: institutionId)
        .snapshots(includeMetadataChanges: true)
        // Boş ve sadece önbellekten gelen ilk anlık görüntüyü atla: sunucudan
        // gerçek veri gelene kadar ekran yükleniyor durumunda kalsın.
        .where(
          (snapshot) =>
              !(snapshot.docs.isEmpty && snapshot.metadata.isFromCache),
        )
        .map((snapshot) {
          List<AssessmentActionPlan> plans = snapshot.docs
              .map((doc) => AssessmentActionPlan.fromMap(doc.data(), doc.id))
              .where((plan) => plan.isActive)
              .toList();

          if (schoolTypeId.isNotEmpty) {
            plans = plans
                .where((plan) => plan.schoolTypeId == schoolTypeId)
                .toList();
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

  Future<void> updateActionPlanRealization(
    String id,
    bool isRealized,
    String notes,
  ) async {
    await _firestore.collection('assessment_action_plans').doc(id).update({
      'isRealized': isRealized,
      'realizationNotes': notes,
      'realizedDate': isRealized ? Timestamp.now() : null,
    });
  }

  // --- Performance Analysis Engine ---

  Future<Map<String, List<Map<String, dynamic>>>> getPerformanceAnalysis(
    String institutionId,
    String schoolTypeId,
  ) async {
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
                    'studentCount':
                        (plan.branchActionPlans[branch]?['targetStudents']
                                as List?)
                            ?.length ??
                        0,
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
