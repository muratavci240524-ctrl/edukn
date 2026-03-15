import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/guidance/development_report/development_report_model.dart';
import '../models/guidance/development_report/development_evaluation_model.dart';
import '../models/guidance/development_report/development_criterion_model.dart';
import '../models/guidance/development_report/development_report_session_model.dart';

class DevelopmentReportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- Sessions ---

  Future<String> createSession(DevelopmentReportSession session) async {
    final docRef = _firestore.collection('development_report_sessions').doc();
    final data = session.toMap();
    data['id'] = docRef.id;
    await docRef.set(data);

    // After creating a session, initialize a draft DevelopmentReport for each target user
    final batch = _firestore.batch();
    for (var targetId in session.targetUserIds) {
      final reportRef = _firestore.collection('development_reports').doc();
      final report = DevelopmentReport(
        id: reportRef.id,
        institutionId: session.institutionId,
        sessionId: docRef.id,
        targetId: targetId,
        targetType: session.targetGroup,
        term: session.title, // using title as term for compatibility
        schoolYear: session.schoolYear,
        createdAt: DateTime.now(),
      );

      final reportData = report.toMap();
      reportData['id'] = reportRef.id; // ensure ID is set in the map
      batch.set(reportRef, reportData);
    }
    await batch.commit();

    return docRef.id;
  }

  Stream<List<DevelopmentReportSession>> getSessions(String institutionId) {
    return _firestore
        .collection('development_report_sessions')
        .where('institutionId', isEqualTo: institutionId)
        .snapshots()
        .map((snapshot) {
          final sessions = snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return DevelopmentReportSession.fromMap(data);
          }).toList();
          sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return sessions;
        });
  }

  Future<void> updateSessionPublishStatus(
    String sessionId,
    bool isPublished,
  ) async {
    final batch = _firestore.batch();

    // 1. Update Session
    batch.update(
      _firestore.collection('development_report_sessions').doc(sessionId),
      {'isPublished': isPublished, 'updatedAt': FieldValue.serverTimestamp()},
    );

    // 2. Update all associated reports
    final reportsRef = _firestore.collection('development_reports');
    final querySnapshot = await reportsRef
        .where('sessionId', isEqualTo: sessionId)
        .get();

    for (var doc in querySnapshot.docs) {
      batch.update(doc.reference, {
        'isPublished': isPublished,
        'status': isPublished ? 'published' : 'draft',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  Future<void> recalculateSessionAnalysis(String sessionId) async {
    final reportsRef = _firestore.collection('development_reports');
    final querySnapshot = await reportsRef
        .where('sessionId', isEqualTo: sessionId)
        .get();

    for (var doc in querySnapshot.docs) {
      await calculateAnalysis(doc.id);
    }
  }

  Future<void> deleteSession(String sessionId) async {
    await _firestore
        .collection('development_report_sessions')
        .doc(sessionId)
        .delete();

    // Also delete associated reports
    final reports = await _firestore
        .collection('development_reports')
        .where('sessionId', isEqualTo: sessionId)
        .get();

    for (var doc in reports.docs) {
      await deleteReport(doc.id);
    }
  }

  // --- Reports ---

  Future<String> createReport(DevelopmentReport report) async {
    final docRef = _firestore.collection('development_reports').doc();
    final data = report.toMap();
    data['id'] = docRef.id;
    // Ensure ID is set in the object if not passed
    await docRef.set(data);
    return docRef.id;
  }

  Future<DevelopmentReport?> getReport(String reportId) async {
    final doc = await _firestore
        .collection('development_reports')
        .doc(reportId)
        .get();
    if (doc.exists && doc.data() != null) {
      final data = doc.data()!;
      data['id'] = doc.id;
      return DevelopmentReport.fromMap(data);
    }
    return null;
  }

  Stream<List<DevelopmentReport>> getReportByTargetId(String targetId) {
    return _firestore
        .collection('development_reports')
        .where('targetId', isEqualTo: targetId)
        // .orderBy('createdAt', descending: true) // Index workaround
        .snapshots()
        .map((snapshot) {
          final reports = snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return DevelopmentReport.fromMap(data);
          }).toList();

          reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return reports;
        });
  }

  // Backward compatibility alias
  Stream<List<DevelopmentReport>> getStudentReports(String studentId) {
    return getReportByTargetId(studentId);
  }

  Future<void> deleteReport(String reportId) async {
    await _firestore.collection('development_reports').doc(reportId).delete();

    // Also delete associated evaluations?
    // For now, keeping them or let cloud functions handle cleanup is better,
    // but to keep it clean we might want to delete them.
    final evals = await _firestore
        .collection('development_evaluations')
        .where('reportId', isEqualTo: reportId)
        .get();

    for (var doc in evals.docs) {
      await doc.reference.delete();
    }
  }

  Future<void> seedDefaultCriteria(String institutionId) async {
    final criteriaRef = _firestore.collection('development_criteria');
    final snapshot = await criteriaRef
        .where('institutionId', isEqualTo: institutionId)
        .get();

    if (snapshot.docs.isNotEmpty) return; // Already exists

    final defaults = [
      // Akademik
      {
        'category': 'Akademik Gelişim',
        'subCategory': 'Genel',
        'title': 'Ders İlgisi',
        'description': 'Derslere karşı ilgi ve katılım düzeyi.',
        'targetGradeLevels': ['5', '6', '7', '8'],
        'type': 'scale_1_5',
        'order': 1,
      },
      {
        'category': 'Akademik Gelişim',
        'subCategory': 'Genel',
        'title': 'Ödev Bilinci',
        'description': 'Ödevlerini zamanında ve eksiksiz yapma.',
        'targetGradeLevels': ['5', '6', '7', '8'],
        'type': 'scale_1_5',
        'order': 2,
      },
      // Sosyal
      {
        'category': 'Sosyal Gelişim',
        'subCategory': 'İletişim',
        'title': 'Arkadaşlık İlişkileri',
        'description': 'Arkadaşlarıyla uyumlu ilişkiler kurma.',
        'targetGradeLevels': ['5', '6', '7', '8'],
        'type': 'scale_1_5',
        'order': 3,
      },
      {
        'category': 'Sosyal Gelişim',
        'subCategory': 'İletişim',
        'title': 'Kurallara Uyma',
        'description': 'Okul ve sınıf kurallarına uyum.',
        'targetGradeLevels': ['5', '6', '7', '8'],
        'type': 'scale_1_5',
        'order': 4,
      },
      // Davranış
      {
        'category': 'Davranış ve Sorumluluk',
        'subCategory': 'Genel',
        'title': 'Sorumluluk Bilinci',
        'description': 'Aldığı görevleri yerine getirme.',
        'targetGradeLevels': ['5', '6', '7', '8'],
        'type': 'scale_1_5',
        'order': 5,
      },
    ];

    for (var item in defaults) {
      await criteriaRef.add({...item, 'institutionId': institutionId});
    }
  }

  // --- Evaluations ---

  Future<void> submitEvaluation(DevelopmentEvaluation evaluation) async {
    final docRef = _firestore
        .collection('development_evaluations')
        .doc(evaluation.id.isEmpty ? null : evaluation.id);

    final data = evaluation.toMap();
    if (evaluation.id.isEmpty) {
      data['id'] = docRef.id;
    }

    await docRef.set(data, SetOptions(merge: true));

    // Allow re-calculation trigger here or via cloud function
    await calculateAnalysis(evaluation.reportId);
  }

  Future<List<DevelopmentEvaluation>> getReportEvaluations(
    String reportId,
  ) async {
    final snapshot = await _firestore
        .collection('development_evaluations')
        .where('reportId', isEqualTo: reportId)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return DevelopmentEvaluation.fromMap(data);
    }).toList();
  }

  // --- Criteria ---
  Stream<List<DevelopmentCriterion>> getCriteria(String institutionId) {
    return _firestore
        .collection('development_criteria')
        .where('institutionId', isEqualTo: institutionId)
        // .orderBy('order') // Index workaround
        .snapshots()
        .map((snapshot) {
          final criteria = snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return DevelopmentCriterion.fromMap(data);
          }).toList();

          criteria.sort((a, b) => a.order.compareTo(b.order));
          return criteria;
        });
  }

  // --- Smart Analysis Engine & Risk Warning ---

  Future<void> calculateAnalysis(String reportId) async {
    // 1. Fetch Report & Evaluations
    final reportDoc = await _firestore
        .collection('development_reports')
        .doc(reportId)
        .get();
    if (!reportDoc.exists) return;

    final reportData = reportDoc.data()!;
    final currentReport = DevelopmentReport.fromMap({
      ...reportData,
      'id': reportDoc.id,
    });

    final evaluations = await getReportEvaluations(reportId);
    if (evaluations.isEmpty) return;

    // 2. Fetch Criteria for Categorization
    // Optimization: In production, caching strategies should be used.
    final criteriaSnapshot = await _firestore
        .collection('development_criteria')
        .where('institutionId', isEqualTo: currentReport.institutionId)
        .get();

    final criteriaMap = {
      for (var doc in criteriaSnapshot.docs)
        doc.id: DevelopmentCriterion.fromMap({...doc.data(), 'id': doc.id}),
    };

    // 3. Aggregate Scores & Comments by Category
    Map<String, double> categorySums = {};
    Map<String, int> categoryCounts = {};
    Map<String, List<String>> categoryComments = {};

    // Also track sub-category scores for detailed analysis if needed later
    Map<String, double> subCategorySums = {};
    Map<String, int> subCategoryCounts = {};

    for (var eval in evaluations) {
      // Scores
      eval.scores.forEach((critId, val) {
        if (val is num && criteriaMap.containsKey(critId)) {
          final crit = criteriaMap[critId]!;
          // Main Category
          categorySums[crit.category] =
              (categorySums[crit.category] ?? 0) + val.toDouble();
          categoryCounts[crit.category] =
              (categoryCounts[crit.category] ?? 0) + 1;

          // Sub Category
          final subKey = "${crit.category}_${crit.subCategory}";
          subCategorySums[subKey] =
              (subCategorySums[subKey] ?? 0) + val.toDouble();
          subCategoryCounts[subKey] = (subCategoryCounts[subKey] ?? 0) + 1;
        }
      });

      // Comments
      eval.comments.forEach((critId, comment) {
        if (comment.trim().isNotEmpty && criteriaMap.containsKey(critId)) {
          final crit = criteriaMap[critId]!;
          if (!categoryComments.containsKey(crit.category)) {
            categoryComments[crit.category] = [];
          }
          final commentWithAuthor =
              "${eval.evaluatorName} (${eval.evaluatorRole}): $comment";
          if (!categoryComments[crit.category]!.contains(commentWithAuthor)) {
            categoryComments[crit.category]!.add(commentWithAuthor);
          }
        }
      });
    }

    Map<String, double> finalCategoryScores = {};
    categorySums.forEach((cat, sum) {
      final count = categoryCounts[cat] ?? 1;
      finalCategoryScores[cat] = double.parse((sum / count).toStringAsFixed(2));
    });

    // 4. Fetch Previous Report for Trend Analysis
    DevelopmentReport? previousReport;
    try {
      // Fetch all reports for target and sort in memory to find the previous one
      // This avoids complex index requirements
      final allReportsQuery = await _firestore
          .collection('development_reports')
          .where('targetId', isEqualTo: currentReport.targetId)
          .get();

      final allReports = allReportsQuery.docs
          .map((d) => DevelopmentReport.fromMap({...d.data(), 'id': d.id}))
          .toList();

      // Sort descending by date
      allReports.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Find the first report that is older than current
      // (Assuming currentReport is already in the list or has a timestamp)
      for (var r in allReports) {
        if (r.createdAt.isBefore(currentReport.createdAt)) {
          previousReport = r;
          break;
        }
      }
    } catch (e) {
      print("Previous report fetch error: $e");
    }

    // 5. Calculate Risk & Trends
    double riskScore = 0;
    List<String> riskFactors = [];
    List<String> strengths = [];
    List<String> improvements = [];
    List<String> warnings = [];

    // Rule 1: Behavior Score < 2 (Assuming 'davranis' or 'behavior' key)
    // We try both Turkish and English keys to be safe, or assume standardized keys.
    double behaviorScore =
        finalCategoryScores['Daavranış ve Sorumluluk'] ??
        finalCategoryScores['behavior'] ??
        finalCategoryScores['davranis'] ??
        5.0;

    if (behaviorScore < 2.0) {
      riskScore += 40;
      riskFactors.add('Davranış puanı kritik seviyenin altında (<2).');
    }

    // Rule 2: Academic Drop > 15%
    double academicScore =
        finalCategoryScores['Akademik Gelişim'] ??
        finalCategoryScores['academic'] ??
        finalCategoryScores['akademik'] ??
        0;

    if (previousReport != null) {
      double prevAcademic =
          previousReport.categoryScores['Akademik Gelişim'] ??
          previousReport.categoryScores['academic'] ??
          previousReport.categoryScores['akademik'] ??
          0;

      if (prevAcademic > 0) {
        double dropRate = (prevAcademic - academicScore) / prevAcademic;
        if (dropRate > 0.15) {
          riskScore += 30;
          riskFactors.add(
            'Akademik başarıda %${(dropRate * 100).toInt()} oranında ciddi düşüş.',
          );
        } else if (dropRate > 0.05) {
          warnings.add('Akademik başarıda düşüş eğilimi var.');
        }
      }
    }

    // Identify Strengths (Top categories > 4.0)
    final sortedCategories = finalCategoryScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (var entry in sortedCategories) {
      if (entry.value >= 4.0 && strengths.length < 3) {
        strengths.add(entry.key);
      }
      if (entry.value < 2.5 && improvements.length < 3) {
        improvements.add(entry.key);
      }
    }

    // AI Comment Generation (Simple Rule-Based)
    String aiSummary = "Öğrencinin genel gelişimi ";
    double avgTotal = finalCategoryScores.values.isEmpty
        ? 0
        : finalCategoryScores.values.reduce((a, b) => a + b) /
              finalCategoryScores.length;

    if (avgTotal >= 4.5)
      aiSummary += "mükemmel seviyededir. ";
    else if (avgTotal >= 3.5)
      aiSummary += "iyi seviyededir. ";
    else if (avgTotal >= 2.5)
      aiSummary += "orta seviyededir. ";
    else
      aiSummary += "desteklenmesi gereken seviyededir. ";

    if (riskScore > 50) {
      aiSummary +=
          "Dikkat! Risk faktörleri tespit edilmiştir. Rehberlik servisi görüşmesi önerilir.";
    }

    // 6. Update Report
    await _firestore.collection('development_reports').doc(reportId).update({
      'categoryScores': finalCategoryScores,
      'riskScore': riskScore,
      'growthIndex': double.parse(avgTotal.toStringAsFixed(2)),
      'analysis': {
        'riskFactors': riskFactors,
        'strengths': strengths,
        'improvements': improvements,
        'warnings': warnings,
        'summary': aiSummary,
        'categoryComments': categoryComments,
        'lastCalculated': Timestamp.now(),
        'evaluationCount': evaluations.length,
        'trend': previousReport != null
            ? double.parse(
                (avgTotal - (previousReport.growthIndex ?? 0)).toStringAsFixed(
                  2,
                ),
              )
            : 0.0,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
