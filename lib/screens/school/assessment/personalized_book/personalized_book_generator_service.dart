import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:printing/printing.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import '../../../../models/assessment/trial_exam_model.dart';
import '../../../../services/assessment_service.dart';
import '../../../../services/web_share/web_file_share.dart';
import '../../../../utils/drive_image_helper.dart';
import '../../../../utils/difficulty_scale.dart';
import '../../../../utils/gercek_kazanim_mapper.dart';
import 'personalized_book_models.dart';

class PersonalizedBookAnalysisBundle {
  final List<StudentMasteryProfile> students;
  final List<ExamOutcomeTopicRule> outcomeRules;
  final List<PoolQuestionItem> poolQuestions;

  const PersonalizedBookAnalysisBundle({
    required this.students,
    required this.outcomeRules,
    required this.poolQuestions,
  });
}

class PersonalizedBookGeneratorService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // A4: 595.28 x 841.89 pt. Margin: L=24, R=24, T=20, B=20 => 547.28 x 801.89 pt
  static const double _fullPageWidth = 544.0;
  static const double _colWidth = 262.0;
  static const double _centerCorridorWidth = 20.0; // 262 + 20 + 262 = 544
  static const double _bodyMaxHeight =
      724.0; // Safe body height between header & footer

  // ─── 1. FIRESTORE ŞABLON & GEÇMİŞ YÖNETİMİ ─────────────────────────────────

  Stream<List<PersonalizedBookConfig>> watchSavedConfigs(String institutionId) {
    final cleanId = institutionId.trim();
    if (cleanId.isEmpty) return Stream.value(const []);
    return _firestore
        .collection('institutions')
        .doc(cleanId)
        .collection('personalized_book_configs')
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => PersonalizedBookConfig.fromMap(d.data(), d.id))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  Future<String> saveConfigTemplate(PersonalizedBookConfig config) async {
    final cleanId = config.institutionId.trim().isNotEmpty
        ? config.institutionId.trim()
        : 'SUPER_ADMIN';
    config.institutionId = cleanId;
    final col = _firestore
        .collection('institutions')
        .doc(cleanId)
        .collection('personalized_book_configs');
    final docRef = config.id.isEmpty ? col.doc() : col.doc(config.id);
    config.id = docRef.id;
    await docRef.set(config.toMap(), SetOptions(merge: true));
    return docRef.id;
  }

  Future<void> deleteConfigTemplate(
    String institutionId,
    String configId,
  ) async {
    final cleanId = institutionId.trim();
    if (cleanId.isEmpty || configId.trim().isEmpty) return;
    await _firestore
        .collection('institutions')
        .doc(cleanId)
        .collection('personalized_book_configs')
        .doc(configId.trim())
        .delete();
  }

  Stream<List<PersonalizedBookHistoryRecord>> watchHistory(
    String institutionId,
  ) {
    final cleanId = institutionId.trim();
    if (cleanId.isEmpty) return Stream.value(const []);
    return _firestore
        .collection('institutions')
        .doc(cleanId)
        .collection('personalized_books')
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => PersonalizedBookHistoryRecord.fromMap(d.data(), d.id))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  Future<void> recordGenerationHistory({
    required String institutionId,
    required PersonalizedBookConfig config,
    required int studentCount,
    required String exportMode,
  }) async {
    try {
      final cleanId = institutionId.trim().isNotEmpty
          ? institutionId.trim()
          : config.institutionId.trim();
      if (cleanId.isEmpty) return;
      final ref = _firestore
          .collection('institutions')
          .doc(cleanId)
          .collection('personalized_books')
          .doc();
      final rec = PersonalizedBookHistoryRecord(
        id: ref.id,
        institutionId: cleanId,
        bookTitle: config.bookTitle,
        examNames: config.selectedExamNames,
        studentCount: studentCount,
        targetPageCount: config.targetPageCount,
        exportMode: exportMode,
        coverThemeKey: config.coverTheme.key,
        createdAt: DateTime.now(),
      );
      await ref.set(rec.toMap());
    } catch (_) {}
  }

  // ─── 2. HAVUZ YÜKLEME (KURUM + GENEL MERKEZ + DENEMELER) ───────────────────

  Future<List<PoolQuestionItem>> loadFullQuestionPool(
    String institutionId, {
    List<TrialExam> extraExams = const [],
  }) async {
    final cleanInstId = institutionId.trim();
    final List<PoolQuestionItem> items = [];
    final Set<String> visitedContainers = {};
    final Set<String> seenPoolKeys = {};

    void parsePoolDocs(
      Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
      required String containerId,
      required String fallbackExamName,
      required String fallbackClassLevel,
      required bool isCentral,
    }) {
      for (final doc in docs) {
        final pKey = '$containerId/${doc.id}';
        if (seenPoolKeys.contains(pKey)) continue;

        final data = doc.data();
        final hasImg =
            (data['base64Image'] != null &&
                data['base64Image'].toString().trim().isNotEmpty) ||
            (data['imageUrl'] != null &&
                data['imageUrl'].toString().trim().isNotEmpty);
        if (!hasImg) continue;
        seenPoolKeys.add(pKey);

        final rawSub = (data['subject'] ?? '').toString().trim();
        final rawOutcome = (data['outcome'] ?? '').toString().trim();
        final resolvedKaz = GercekKazanimMapper.resolve(
          outcome: rawOutcome,
          kazanimCode: data['kazanimCode']?.toString(),
          k12Code: data['k12Code']?.toString(),
          legacyOutcome: data['legacyOutcome']?.toString(),
        );
        final effectiveRawOutcome = (resolvedKaz.code.isNotEmpty && resolvedKaz.outcome.isNotEmpty)
            ? '${resolvedKaz.code} - ${resolvedKaz.outcome}'
            : (resolvedKaz.outcome.isNotEmpty ? resolvedKaz.outcome : rawOutcome);
        final sanitized = _sanitizeSubjectAndOutcome(
          currentCanonSubject: FokusTextUtils.canonicalSubject(rawSub),
          rawOutcome: effectiveRawOutcome,
          knownExamCanonSubjects: const {},
        );
        final canonSub = sanitized.subject;
        final cleanOutcome = sanitized.outcome;
        final normKey = FokusTextUtils.buildOutcomeKey(canonSub, cleanOutcome);
        final qNo = (num.tryParse('${data['questionNo']}') ?? 0).toInt();
        final diff = (data['difficulty'] as num?)?.toDouble() ?? 50.0;
        final eName = (data['examName'] ?? fallbackExamName).toString();
        final cls = AssessmentService.normalizeClassLevel(
          (data['classLevel'] ?? fallbackClassLevel).toString(),
          examName: eName,
        );

        items.add(
          PoolQuestionItem(
            poolKey: pKey,
            examId: (data['examId'] ?? containerId).toString(),
            examName: eName,
            docId: doc.id,
            subject: canonSub,
            rawSubject: rawSub,
            outcome: cleanOutcome,
            normalizedOutcomeKey: normKey,
            classLevel: cls,
            questionNo: qNo,
            correctAnswer: (data['correctAnswer'] ?? 'A')
                .toString()
                .trim()
                .toUpperCase(),
            difficulty: diff.clamp(0.0, 100.0),
            isWide: data['isWide'] == true,
            isCritical: data['isCritical'] == true,
            base64Image: data['base64Image']?.toString(),
            imageUrl: data['imageUrl']?.toString(),
            driveFileId: data['driveFileId']?.toString(),
            k12Code: null,
            kazanimCode: resolvedKaz.code.isNotEmpty ? resolvedKaz.code : data['kazanimCode']?.toString(),
            legacyOutcome: data['legacyOutcome']?.toString(),
            passageId: data['passageId']?.toString(),
            passageBase64: data['passageBase64']?.toString(),
            isCentralPool: isCentral,
            questionType: (data['questionType'] ?? 'Çoktan Seçmeli')
                .toString()
                .trim(),
            sourceType: (data['sourceType'] ?? '').toString().trim(),
          ),
        );
      }
    }

    Future<void> fetchContainer(
      String containerId, {
      String fallbackExamName = 'Soru Havuzu',
      String fallbackClassLevel = '',
      bool isCentral = false,
    }) async {
      final cid = containerId.trim();
      if (cid.isEmpty || visitedContainers.contains(cid)) {
        return;
      }
      visitedContainers.add(cid);
      try {
        final snap = await _firestore
            .collection('trial_exams')
            .doc(cid)
            .collection('questions_pool')
            .get()
            .timeout(const Duration(seconds: 30));

        parsePoolDocs(
          snap.docs,
          containerId: cid,
          fallbackExamName: fallbackExamName,
          fallbackClassLevel: fallbackClassLevel,
          isCentral: isCentral,
        );

        if (isCentral && snap.docs.isEmpty && cid != 'pool_SUPER_ADMIN') {
          final altSnap = await _firestore
              .collection('central_exams')
              .doc(cid)
              .collection('questions_pool')
              .get()
              .timeout(const Duration(seconds: 20));
          parsePoolDocs(
            altSnap.docs,
            containerId: 'central_$cid',
            fallbackExamName: fallbackExamName,
            fallbackClassLevel: fallbackClassLevel,
            isCentral: true,
          );
        }
      } catch (_) {}
    }

    Future<void> fetchInstitutionQuestionPool(
      String instId, {
      required String fallbackExamName,
      required bool isCentral,
    }) async {
      final clean = instId.trim();
      final marker = 'inst_qpool_$clean';
      if (clean.isEmpty || visitedContainers.contains(marker)) return;
      visitedContainers.add(marker);
      try {
        final snap = await _firestore
            .collection('institutions')
            .doc(clean)
            .collection('question_pool')
            .get()
            .timeout(const Duration(seconds: 25));
        parsePoolDocs(
          snap.docs,
          containerId: marker,
          fallbackExamName: fallbackExamName,
          fallbackClassLevel: '',
          isCentral: isCentral,
        );
      } catch (_) {}
    }

    // 1. Kurumun ve Genel Merkez'in havuz konteynerlerini çek
    final Map<String, ({String name, String classLevel})> centralExamMeta = {};
    final List<Future<void>> tasks = [];

    if (cleanInstId.isNotEmpty) {
      tasks.add(
        fetchContainer(
          'pool_$cleanInstId',
          fallbackExamName: 'Kurum Soru Havuzu',
        ),
      );
      if (cleanInstId != 'SUPER_ADMIN') {
        tasks.add(
          fetchInstitutionQuestionPool(
            cleanInstId,
            fallbackExamName: 'Kurum Soru Havuzu',
            isCentral: false,
          ),
        );
      }
    }
    tasks.add(
      fetchContainer(
        'pool_SUPER_ADMIN',
        fallbackExamName: 'Genel Merkez Soru Havuzu',
        isCentral: true,
      ),
    );
    tasks.add(
      fetchInstitutionQuestionPool(
        'SUPER_ADMIN',
        fallbackExamName: 'Genel Merkez Soru Havuzu',
        isCentral: true,
      ),
    );

    if (cleanInstId.isNotEmpty) {
      try {
        final examsSnap = await _firestore
            .collection('trial_exams')
            .where('institutionId', isEqualTo: cleanInstId)
            .get()
            .timeout(const Duration(seconds: 25));

        for (final doc in examsSnap.docs) {
          final d = doc.data();
          final isRelevant =
              d['isActive'] == true ||
              d['isPoolContainer'] == true ||
              doc.id == 'pool_$cleanInstId';
          if (!isRelevant) continue;
          final eName = (d['name'] ?? 'Deneme Sınavı').toString();
          final cLvl = (d['classLevel'] ?? '').toString();
          tasks.add(
            fetchContainer(
              doc.id,
              fallbackExamName: eName,
              fallbackClassLevel: cLvl,
            ),
          );
          final cId = d['centralExamId']?.toString();
          if (cId != null && cId.trim().isNotEmpty) {
            centralExamMeta.putIfAbsent(
              cId.trim(),
              () => (name: eName, classLevel: cLvl),
            );
          }
        }
      } catch (_) {}
    }

    for (final ex in extraExams) {
      tasks.add(
        fetchContainer(
          ex.id,
          fallbackExamName: ex.name,
          fallbackClassLevel: ex.classLevel,
        ),
      );
      if (ex.centralExamId != null && ex.centralExamId!.trim().isNotEmpty) {
        centralExamMeta.putIfAbsent(
          ex.centralExamId!.trim(),
          () => (name: ex.name, classLevel: ex.classLevel),
        );
      }
    }

    // 2. Tüm aktif Genel Merkez (`central_exams`) denemelerinin havuzlarını da keşfet
    try {
      final hqSnap = await _firestore
          .collection('central_exams')
          .where('isActive', isEqualTo: true)
          .get()
          .timeout(const Duration(seconds: 20));
      for (final doc in hqSnap.docs) {
        final d = doc.data();
        final eName = (d['name'] ?? d['title'] ?? 'Genel Merkez Denemesi')
            .toString();
        final cLvl = (d['classLevel'] ?? '').toString();
        centralExamMeta.putIfAbsent(
          doc.id,
          () => (name: eName, classLevel: cLvl),
        );
        final linkedId = (d['trialExamId'] ?? d['poolContainerId'] ?? '')
            .toString()
            .trim();
        if (linkedId.isNotEmpty) {
          centralExamMeta.putIfAbsent(
            linkedId,
            () => (name: eName, classLevel: cLvl),
          );
        }
      }
    } catch (_) {}

    await Future.wait(tasks);

    // 3. Genel Merkez deneme havuzlarını bounded gruplar halinde yükle
    if (centralExamMeta.isNotEmpty) {
      final entries = centralExamMeta.entries.toList();
      const int batchSize = 8;
      for (int i = 0; i < entries.length; i += batchSize) {
        final slice = entries.sublist(
          i,
          math.min(entries.length, i + batchSize),
        );
        await Future.wait(
          slice.map(
            (e) => fetchContainer(
              e.key,
              fallbackExamName: e.value.name,
              fallbackClassLevel: e.value.classLevel,
              isCentral: true,
            ),
          ),
        );
      }
    }

    return items;
  }

  // ─── 3. DENEME DEĞERLENDİRME & ÖĞRENCİ KAZANIM ANALİZ MOTORU ──────────────

  Future<PersonalizedBookAnalysisBundle> analyzeExamsAndPool({
    required String institutionId,
    required List<TrialExam> selectedExams,
    List<PoolQuestionItem>? preloadedPool,
  }) async {
    final pool =
        preloadedPool ??
        await loadFullQuestionPool(institutionId, extraExams: selectedExams);

    // Sınav içi soru kazanım yedeği: "${examId}_${normSub}_${qNo}" -> outcome
    final Map<String, String> poolOutcomeLookup = {};
    for (final pq in pool) {
      if (pq.outcome.trim().isNotEmpty && pq.questionNo > 0) {
        poolOutcomeLookup[pq.examQuestionIdentity] = pq.outcome.trim();
      }
    }

    final Map<String, StudentMasteryProfile> studentsById = {};
    // Sınıf geneli kazanım toplulaştırma: key -> {subject, outcome, examQSet, totalAsked, totalCorrect}
    final Map<String, _AggregatedOutcomeMeta> classOutcomes = {};

    for (final exam in selectedExams) {
      final rawJson = exam.resultsJson;
      if (rawJson == null || rawJson.trim().isEmpty) continue;

      dynamic decoded;
      try {
        decoded = jsonDecode(rawJson);
      } catch (_) {
        continue;
      }
      if (decoded is! List) continue;

      final Set<String> knownExamCanonSubjects = {};
      for (final subMap in exam.answerKeys.values) {
        for (final rawK in subMap.keys) {
          final c = FokusTextUtils.canonicalSubject(rawK);
          if (c.isNotEmpty && c != 'Genel') knownExamCanonSubjects.add(c);
        }
      }
      for (final outMap in exam.outcomes.values) {
        for (final rawK in outMap.keys) {
          final c = FokusTextUtils.canonicalSubject(rawK);
          if (c.isNotEmpty && c != 'Genel') knownExamCanonSubjects.add(c);
        }
      }

      for (final rawEntry in decoded) {
        if (rawEntry is! Map) continue;
        final res = Map<String, dynamic>.from(rawEntry);

        final rawName = (res['studentName'] ?? res['name'] ?? 'İsimsiz Öğrenci')
            .toString()
            .trim();
        if (rawName.isEmpty) continue;

        final tc = (res['tcNo'] ?? '')
            .toString()
            .replaceAll(RegExp(r'[^0-9]'), '')
            .trim();
        final stuNo = (res['studentNo'] ?? res['studentNumber'] ?? '')
            .toString()
            .trim();
        final sysId = (res['systemStudentId'] ?? '').toString().trim();
        final branch =
            (res['branch'] ?? res['className'] ?? res['sube'] ?? 'Genel')
                .toString()
                .trim();
        final rawCls = (res['classLevel'] ?? res['level'] ?? res['sinif'] ?? '')
            .toString()
            .trim();
        final normCls = AssessmentService.normalizeClassLevel(
          rawCls.isNotEmpty ? rawCls : exam.classLevel,
          examName: exam.name,
        );

        final String studentKey = _buildStudentIdentityKey(
          tc: tc,
          sysId: sysId,
          studentNo: stuNo,
          name: rawName,
          classLevel: normCls,
          branch: branch,
        );

        final profile = studentsById.putIfAbsent(
          studentKey,
          () => StudentMasteryProfile(
            id: studentKey,
            name: rawName.toUpperCase(),
            studentNo: stuNo,
            tcNo: tc,
            classLevel: normCls,
            branch: branch.isEmpty ? 'Genel' : branch,
          ),
        );

        if (!profile.participatedExamIds.contains(exam.id)) {
          profile.participatedExamIds.add(exam.id);
          profile.participatedExamNames.add(exam.name);
        }

        final String rawBooklet =
            (res['booklet'] ??
                    res['kitapcik'] ??
                    res['Kitapçık'] ??
                    res['bookletType'] ??
                    'A')
                .toString()
                .trim()
                .toUpperCase();
        final String booklet = rawBooklet.isEmpty ? 'A' : rawBooklet;

        // Cevap haritalarını oku (hem üst seviye 'answers' hem 'subjects[sub].answers' destekli)
        final Map<String, String> studentAnswersMap = {};
        final dynamic topAns = res['answers'] ?? res['cevaplar'];
        if (topAns is Map) {
          topAns.forEach((k, v) {
            studentAnswersMap[k.toString()] = v.toString();
          });
        }
        final Map<String, dynamic> backendSubjects = res['subjects'] is Map
            ? Map<String, dynamic>.from(res['subjects'] as Map)
            : {};
        backendSubjects.forEach((k, v) {
          if (!studentAnswersMap.containsKey(k) &&
              v is Map &&
              v['answers'] != null) {
            studentAnswersMap[k] = v['answers'].toString();
          }
        });

        for (final rawK in studentAnswersMap.keys) {
          final c = FokusTextUtils.canonicalSubject(rawK);
          if (c.isNotEmpty && c != 'Genel') knownExamCanonSubjects.add(c);
        }

        // Eğer öğrenci cevap dizisi boşsa ama sınavda cevap anahtarı varsa ders anahtarlarını gez
        final Iterable<String> subjectKeys = studentAnswersMap.isNotEmpty
            ? studentAnswersMap.keys
            : (exam.answerKeys[booklet]?.keys ??
                  exam.answerKeys['A']?.keys ??
                  const Iterable<String>.empty());

        for (final rawSubject in subjectKeys) {
          final String sAns = studentAnswersMap[rawSubject] ?? '';
          final String canonSub = FokusTextUtils.canonicalSubject(rawSubject);

          int expectedC = -1;
          final dynamic bs = backendSubjects[rawSubject];
          if (bs is Map && bs['correct'] != null) {
            expectedC = (num.tryParse('${bs['correct']}') ?? -1).toInt();
          }

          // Doğru kitapçık cevap anahtarını bul
          String effectiveBooklet = booklet;
          String rAns =
              _lookupSubjectMap<String>(exam.answerKeys[booklet], rawSubject) ??
              _lookupSubjectMap<String>(exam.answerKeys['A'], rawSubject) ??
              '';

          if (expectedC >= 0 && exam.answerKeys.isNotEmpty) {
            for (final bKey in exam.answerKeys.keys) {
              final candR =
                  _lookupSubjectMap<String>(
                    exam.answerKeys[bKey],
                    rawSubject,
                  ) ??
                  '';
              if (candR.isEmpty) continue;
              int testC = 0;
              for (int j = 0; j < candR.length; j++) {
                final sc = j < sAns.length ? sAns[j] : ' ';
                if (TrialExam.evaluateAnswer(sc, candR[j]) ==
                    AnswerStatus.correct) {
                  testC++;
                }
              }
              if (testC == expectedC) {
                rAns = candR;
                effectiveBooklet = bKey;
                break;
              }
            }
          }

          if (rAns.isEmpty) continue;

          for (int j = 0; j < rAns.length; j++) {
            final String sChar = j < sAns.length ? sAns[j] : ' ';
            final String rChar = rAns[j];
            if (rChar == '#') continue; // İptal edilmiş soru

            final AnswerStatus status = TrialExam.evaluateAnswer(sChar, rChar);
            final int masterQNo = _resolveMasterQuestionNo(
              exam: exam,
              booklet: effectiveBooklet,
              rawSubject: rawSubject,
              zeroBasedIndex: j,
            );

            final String rawResolvedOutcome = _resolveQuestionOutcomeText(
              exam: exam,
              booklet: effectiveBooklet,
              rawSubject: rawSubject,
              canonSubject: canonSub,
              zeroBasedIndex: j,
              masterQNo: masterQNo,
              poolOutcomeLookup: poolOutcomeLookup,
            );

            final sanitized = _sanitizeSubjectAndOutcome(
              currentCanonSubject: canonSub,
              rawOutcome: rawResolvedOutcome,
              knownExamCanonSubjects: knownExamCanonSubjects,
            );
            final String effSub = sanitized.subject;
            final String resolvedOutcome = sanitized.outcome;
            final String normSub = FokusTextUtils.normAlnum(effSub);

            final subSummary = profile.subjectStats.putIfAbsent(
              effSub,
              () => SubjectSummaryStat(subject: effSub),
            );

            final String outKey = FokusTextUtils.buildOutcomeKey(
              effSub,
              resolvedOutcome,
            );

            final outStat = profile.outcomeStats.putIfAbsent(
              outKey,
              () => OutcomeMasteryStat(
                key: outKey,
                subject: effSub,
                outcome: resolvedOutcome,
              ),
            );

            outStat.totalAsked++;
            subSummary.total++;
            profile.totalAsked++;

            final String qIdLocal = '${exam.id}_${normSub}_$masterQNo';
            final String? qIdCentral =
                (exam.centralExamId != null && exam.centralExamId!.isNotEmpty)
                ? '${exam.centralExamId}_${normSub}_$masterQNo'
                : null;

            if (status == AnswerStatus.correct) {
              outStat.correct++;
              subSummary.correct++;
              profile.totalCorrect++;
              profile.answeredCorrectKeys.add(qIdLocal);
              if (qIdCentral != null) {
                profile.answeredCorrectKeys.add(qIdCentral);
              }
            } else if (status == AnswerStatus.wrong) {
              outStat.wrong++;
              subSummary.wrong++;
              profile.totalWrong++;
              profile.answeredWrongOrEmptyKeys.add(qIdLocal);
              if (qIdCentral != null) {
                profile.answeredWrongOrEmptyKeys.add(qIdCentral);
              }
            } else {
              outStat.empty++;
              subSummary.empty++;
              profile.totalEmpty++;
              profile.answeredWrongOrEmptyKeys.add(qIdLocal);
              if (qIdCentral != null) {
                profile.answeredWrongOrEmptyKeys.add(qIdCentral);
              }
            }

            // Sınıf geneli kazanım istatistiği
            final agg = classOutcomes.putIfAbsent(
              outKey,
              () => _AggregatedOutcomeMeta(
                key: outKey,
                subject: effSub,
                outcome: resolvedOutcome,
              ),
            );
            agg.uniqueExamSlots.add('${exam.id}::$masterQNo');
            agg.totalStudentAsked++;
            if (status == AnswerStatus.correct) {
              agg.totalStudentCorrect++;
            }
          }
        }
      }
    }

    // Eğer sonuçlarda kazanım haritası henüz oluşmadıysa sınavların outcomes haritasından da oku
    if (classOutcomes.isEmpty) {
      for (final exam in selectedExams) {
        final masterOut =
            exam.outcomes['A'] ??
            (exam.outcomes.isNotEmpty ? exam.outcomes.values.first : {});
        final Set<String> knownSubs = {
          for (final rawK in masterOut.keys)
            if (FokusTextUtils.canonicalSubject(rawK) != 'Genel')
              FokusTextUtils.canonicalSubject(rawK),
        };
        masterOut.forEach((rawSub, list) {
          final canonSub = FokusTextUtils.canonicalSubject(rawSub);
          for (int idx = 0; idx < list.length; idx++) {
            final rawTxt = list[idx].trim().isNotEmpty
                ? list[idx].trim()
                : '$canonSub Genel Kazanım';
            final sanitized = _sanitizeSubjectAndOutcome(
              currentCanonSubject: canonSub,
              rawOutcome: rawTxt,
              knownExamCanonSubjects: knownSubs,
            );
            final key = FokusTextUtils.buildOutcomeKey(
              sanitized.subject,
              sanitized.outcome,
            );
            final agg = classOutcomes.putIfAbsent(
              key,
              () => _AggregatedOutcomeMeta(
                key: key,
                subject: sanitized.subject,
                outcome: sanitized.outcome,
              ),
            );
            agg.uniqueExamSlots.add('${exam.id}::${idx + 1}');
          }
        });
      }
    }

    // Branş bazlı toplam havuz sayılarını hesapla
    final Map<String, int> poolCountBySubject = {};
    for (final pq in pool) {
      poolCountBySubject[pq.subject] =
          (poolCountBySubject[pq.subject] ?? 0) + 1;
    }

    final List<ExamOutcomeTopicRule> rules = [];
    for (final agg in classOutcomes.values) {
      int exactCount = 0;
      for (final pq in pool) {
        if (pq.subject != agg.subject) continue;
        if (pq.normalizedOutcomeKey == agg.key ||
            pq.matchesOutcomeTextOrK12(agg.outcome)) {
          exactCount++;
        }
      }
      final double avgMastery = agg.totalStudentAsked > 0
          ? (agg.totalStudentCorrect / agg.totalStudentAsked * 100.0).clamp(
              0.0,
              100.0,
            )
          : 0.0;

      rules.add(
        ExamOutcomeTopicRule(
          key: agg.key,
          subject: agg.subject,
          outcome: agg.outcome,
          examQuestionCount: agg.uniqueExamSlots.length,
          poolExactCount: exactCount,
          poolSubjectTotalCount: poolCountBySubject[agg.subject] ?? 0,
          avgClassMastery: avgMastery,
          minQuestions: 0,
          isEnabled: true,
        ),
      );
    }

    rules.sort((a, b) {
      final rCmp = FokusTextUtils.subjectSortRank(
        a.subject,
      ).compareTo(FokusTextUtils.subjectSortRank(b.subject));
      if (rCmp != 0) return rCmp;
      final sCmp = a.subject.compareTo(b.subject);
      if (sCmp != 0) return sCmp;
      return a.avgClassMastery.compareTo(b.avgClassMastery);
    });

    final sortedStudents = studentsById.values.toList()
      ..sort((a, b) {
        final bCmp = a.branch.compareTo(b.branch);
        if (bCmp != 0) return bCmp;
        return a.name.compareTo(b.name);
      });

    return PersonalizedBookAnalysisBundle(
      students: sortedStudents,
      outcomeRules: rules,
      poolQuestions: pool,
    );
  }

  /// Yalnızca `:` öncesi metin bilinen bir okul branşıysa veya sınavın branş haritasında
  /// varsa branş öneki olarak ayırır (`'Saatler: Tam ve Yarım Saatler'` gibi kazanım
  /// açıklamalarını bozmaz).
  static ({String subject, String outcome}) _sanitizeSubjectAndOutcome({
    required String currentCanonSubject,
    required String rawOutcome,
    required Set<String> knownExamCanonSubjects,
  }) {
    final String baseSub = currentCanonSubject.trim().isEmpty
        ? 'Genel'
        : currentCanonSubject.trim();
    final String trimmed = rawOutcome.trim();
    if (trimmed.isEmpty) {
      return (subject: baseSub, outcome: '$baseSub Genel Kazanım');
    }

    String resolvedSub = baseSub;
    String restOutcome = trimmed;
    final int colonIdx = trimmed.indexOf(':');
    if (colonIdx > 0 && colonIdx < trimmed.length - 1) {
      final String prefix = trimmed.substring(0, colonIdx).trim();
      final String rest = trimmed.substring(colonIdx + 1).trim();
      if (prefix.isNotEmpty && rest.isNotEmpty && prefix.length <= 36) {
        final String canonPrefix = FokusTextUtils.canonicalSubject(prefix);
        final bool isValidSubjectPrefix =
            FokusTextUtils.isKnownSchoolSubject(prefix) ||
            knownExamCanonSubjects.contains(canonPrefix);
        if (isValidSubjectPrefix) {
          resolvedSub = (baseSub == 'Genel' || canonPrefix == baseSub)
              ? canonPrefix
              : baseSub;
          restOutcome = rest;
        }
      }
    }

    final resolvedKaz = GercekKazanimMapper.resolve(outcome: restOutcome);
    if (resolvedKaz.code.isNotEmpty && resolvedKaz.outcome.isNotEmpty) {
      return (
        subject: resolvedSub,
        outcome: '${resolvedKaz.code} - ${resolvedKaz.outcome}',
      );
    }
    if (resolvedKaz.outcome.isNotEmpty) {
      return (subject: resolvedSub, outcome: resolvedKaz.outcome);
    }

    return (subject: resolvedSub, outcome: restOutcome);
  }

  static String _buildStudentIdentityKey({
    required String tc,
    required String sysId,
    required String studentNo,
    required String name,
    required String classLevel,
    required String branch,
  }) {
    if (tc.length == 11 &&
        !tc.startsWith('000') &&
        !tc.startsWith('1111111111')) {
      return 'tc_$tc';
    }
    if (sysId.isNotEmpty) return 'sys_$sysId';
    final cName = FokusTextUtils.normAlnum('${classLevel}_$branch');
    final sNo = studentNo.replaceFirst(RegExp(r'^0+'), '').trim();
    final sName = FokusTextUtils.normAlnum(name);
    return 'anon_${cName}_${sNo}_$sName';
  }

  static T? _lookupSubjectMap<T>(Map<String, T>? map, String targetSubject) {
    if (map == null) return null;
    if (map.containsKey(targetSubject)) return map[targetSubject];
    final targetCanon = FokusTextUtils.canonicalSubject(targetSubject);
    final targetNorm = FokusTextUtils.normAlnum(targetSubject);
    for (final entry in map.entries) {
      if (FokusTextUtils.canonicalSubject(entry.key) == targetCanon ||
          FokusTextUtils.normAlnum(entry.key) == targetNorm) {
        return entry.value;
      }
    }
    return null;
  }

  int _resolveMasterQuestionNo({
    required TrialExam exam,
    required String booklet,
    required String rawSubject,
    required int zeroBasedIndex,
  }) {
    final int qNoInStudentBooklet = zeroBasedIndex + 1;
    if (booklet == 'A') return qNoInStudentBooklet;

    final String? mappingStr = _lookupSubjectMap<String>(
      exam.bookletMapping[booklet],
      rawSubject,
    );
    if (mappingStr != null && mappingStr.trim().isNotEmpty) {
      if (mappingStr.contains('(')) {
        final matches = RegExp(r'(\d+)\((\d+)\)').allMatches(mappingStr);
        for (final m in matches) {
          if (int.tryParse(m.group(1)!) == qNoInStudentBooklet) {
            return int.tryParse(m.group(2)!) ?? qNoInStudentBooklet;
          }
        }
      } else {
        final nums = RegExp(
          r'\d+',
        ).allMatches(mappingStr).map((m) => int.parse(m.group(0)!)).toList();
        if (zeroBasedIndex < nums.length && nums[zeroBasedIndex] > 0) {
          return nums[zeroBasedIndex];
        }
      }
    }

    // Fallback: kazanım eşleşmesi üzerinden A kitapçığı sırasını bul
    final studentSubOutcomes = _lookupSubjectMap<List<String>>(
      exam.outcomes[booklet],
      rawSubject,
    );
    final masterSubOutcomes = _lookupSubjectMap<List<String>>(
      exam.outcomes['A'],
      rawSubject,
    );
    if (studentSubOutcomes != null &&
        masterSubOutcomes != null &&
        zeroBasedIndex < studentSubOutcomes.length) {
      final rawTarget = studentSubOutcomes[zeroBasedIndex].trim();
      final parsedDirect = int.tryParse(rawTarget);
      if (parsedDirect != null && parsedDirect > 0) {
        return parsedDirect;
      }
      final normTarget = FokusTextUtils.normAlnum(rawTarget);
      if (normTarget.isNotEmpty) {
        int occurrence = 0;
        for (int k = 0; k <= zeroBasedIndex; k++) {
          if (FokusTextUtils.normAlnum(studentSubOutcomes[k]) == normTarget) {
            occurrence++;
          }
        }
        int found = 0;
        for (int k = 0; k < masterSubOutcomes.length; k++) {
          if (FokusTextUtils.normAlnum(masterSubOutcomes[k]) == normTarget) {
            found++;
            if (found == occurrence) return k + 1;
          }
        }
      }
    }
    return qNoInStudentBooklet;
  }

  String _resolveQuestionOutcomeText({
    required TrialExam exam,
    required String booklet,
    required String rawSubject,
    required String canonSubject,
    required int zeroBasedIndex,
    required int masterQNo,
    required Map<String, String> poolOutcomeLookup,
  }) {
    final studentOutList = _lookupSubjectMap<List<String>>(
      exam.outcomes[booklet],
      rawSubject,
    );
    if (studentOutList != null && zeroBasedIndex < studentOutList.length) {
      final candidate = studentOutList[zeroBasedIndex].trim();
      if (candidate.isNotEmpty && int.tryParse(candidate) == null) {
        return candidate;
      }
    }

    final masterOutList = _lookupSubjectMap<List<String>>(
      exam.outcomes['A'],
      rawSubject,
    );
    if (masterOutList != null &&
        masterQNo >= 1 &&
        masterQNo <= masterOutList.length) {
      final candidate = masterOutList[masterQNo - 1].trim();
      if (candidate.isNotEmpty && int.tryParse(candidate) == null) {
        return candidate;
      }
    }

    final normSub = FokusTextUtils.normAlnum(canonSubject);
    final fromLocalPool = poolOutcomeLookup['${exam.id}_${normSub}_$masterQNo'];
    if (fromLocalPool != null && fromLocalPool.isNotEmpty) {
      return fromLocalPool;
    }
    if (exam.centralExamId != null && exam.centralExamId!.isNotEmpty) {
      final fromCentralPool =
          poolOutcomeLookup['${exam.centralExamId}_${normSub}_$masterQNo'];
      if (fromCentralPool != null && fromCentralPool.isNotEmpty) {
        return fromCentralPool;
      }
    }

    return '$canonSubject Genel Kazanım';
  }

  // ─── 4. EK PDF RASTERİZASYONU (ÖN SÖZ PDF YÜKLEME) ─────────────────────────

  /// Yüklenen PDF baytlarını `Printing.raster(pdfBytes, dpi: 150)` ile sayfa sayfa
  /// PNG görsellerine çevirir ve gerçek sayfa sayısını anında döner.
  Future<List<Uint8List>> rasterizeUploadedPrefacePdf(
    Uint8List pdfBytes,
  ) async {
    final List<Uint8List> pageImages = [];
    if (pdfBytes.isEmpty) return pageImages;

    // 1. Birincil yol: Printing.raster (dpi: 150)
    try {
      final safeCopy = Uint8List.fromList(pdfBytes);
      await for (final rasterPage in Printing.raster(safeCopy, dpi: 150)) {
        final pngBytes = await rasterPage.toPng();
        if (pngBytes.isNotEmpty) {
          pageImages.add(pngBytes);
        }
      }
      if (pageImages.isNotEmpty) return pageImages;
    } catch (_) {}

    // 2. Yedek yol (Web PdfJS / pdfx): PdfDocument.openData
    try {
      final safeCopy = Uint8List.fromList(pdfBytes);
      final doc = await pdfx.PdfDocument.openData(safeCopy);
      try {
        for (int p = 1; p <= doc.pagesCount; p++) {
          final page = await doc.getPage(p);
          try {
            final rendered = await page.render(
              width: page.width * 2.0,
              height: page.height * 2.0,
              format: pdfx.PdfPageImageFormat.png,
              backgroundColor: '#FFFFFF',
            );
            if (rendered != null && rendered.bytes.isNotEmpty) {
              pageImages.add(rendered.bytes);
            }
          } finally {
            await page.close();
          }
        }
      } finally {
        await doc.close();
      }
    } catch (_) {}

    return pageImages;
  }

  // ─── 5. GÖRSEL ÖN HAZIRLIK VE PNG/JPEG HEADER ASPECT RATIO ────────────────

  static Uint8List? _decodeBase64Clean(String? raw) {
    if (raw == null) return null;
    String clean = raw.trim();
    if (clean.isEmpty) return null;
    if (clean.contains(',')) {
      clean = clean.substring(clean.indexOf(',') + 1);
    }
    clean = clean.replaceAll(RegExp(r'\s+'), '');
    if (clean.isEmpty) return null;
    try {
      final bytes = base64Decode(clean);
      return bytes.isNotEmpty ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _prepareSinglePoolItem(PoolQuestionItem q) async {
    if (q.cachedImageBytes == null) {
      if (q.base64Image != null && q.base64Image!.trim().isNotEmpty) {
        q.cachedImageBytes = _decodeBase64Clean(q.base64Image);
      }
      if (q.cachedImageBytes == null &&
          q.imageUrl != null &&
          q.imageUrl!.trim().isNotEmpty) {
        final String url = q.imageUrl!.trim();
        if (url.startsWith('data:')) {
          q.cachedImageBytes = _decodeBase64Clean(url);
        } else {
          if (url.contains('firebasestorage') || url.startsWith('gs://')) {
            try {
              final data = await FirebaseStorage.instance
                  .refFromURL(url)
                  .getData(6 * 1024 * 1024)
                  .timeout(const Duration(seconds: 8));
              if (data != null && data.isNotEmpty) {
                q.cachedImageBytes = data;
              }
            } catch (_) {}
          }
          if (q.cachedImageBytes == null &&
              (url.startsWith('http://') ||
                  url.startsWith('https://') ||
                  (q.driveFileId != null && q.driveFileId!.trim().isNotEmpty))) {
            try {
              final fetched = await DriveImageHelper.fetchImageBytes(
                url,
                driveFileId: q.driveFileId,
                perTryTimeout: const Duration(seconds: 5),
              );
              if (fetched != null && fetched.isNotEmpty) {
                q.cachedImageBytes = fetched;
              }
            } catch (_) {}
          }
        }
      }
    }
    if (q.cachedImageBytes != null && q.cachedAspectRatio == null) {
      q.cachedAspectRatio = getImageAspectRatio(q.cachedImageBytes!);
    }
    if (q.cachedPassageBytes == null &&
        q.passageBase64 != null &&
        q.passageBase64!.trim().isNotEmpty) {
      final pBytes = _decodeBase64Clean(q.passageBase64);
      if (pBytes != null) {
        q.cachedPassageBytes = pBytes;
        q.cachedPassageAspectRatio = getImageAspectRatio(pBytes);
      }
    }
  }

  Future<void> ensurePoolImagesPrepared(Iterable<PoolQuestionItem> pool) async {
    final List<PoolQuestionItem> pending = [];
    for (final q in pool) {
      final needsMain =
          q.cachedImageBytes == null || q.cachedAspectRatio == null;
      final needsPassage =
          q.cachedPassageBytes == null &&
          q.passageBase64 != null &&
          q.passageBase64!.trim().isNotEmpty;
      if (needsMain || needsPassage) {
        pending.add(q);
      }
    }
    if (pending.isEmpty) return;

    const int chunkSize = 8;
    for (int i = 0; i < pending.length; i += chunkSize) {
      final end = math.min(pending.length, i + chunkSize);
      await Future.wait(pending.sublist(i, end).map(_prepareSinglePoolItem));
      if (((i + chunkSize) % 24 == 0) || end < pending.length) {
        await Future.delayed(Duration.zero);
      }
    }
  }

  /// Piksel tamponu açmadan doğrudan PNG / JPEG bayt başlığından `height / width` okur.
  static double getImageAspectRatio(Uint8List bytes) {
    try {
      if (bytes.length < 24) return 0.62;
      // PNG IHDR
      if (bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47) {
        final int w =
            (bytes[16] << 24) |
            (bytes[17] << 16) |
            (bytes[18] << 8) |
            bytes[19];
        final int h =
            (bytes[20] << 24) |
            (bytes[21] << 16) |
            (bytes[22] << 8) |
            bytes[23];
        if (w > 0 && h > 0) return (h / w).clamp(0.14, 2.2);
      }
      // JPEG SOF0..SOF15
      if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
        int offset = 2;
        while (offset + 9 < bytes.length) {
          if (bytes[offset] != 0xFF) {
            offset++;
            continue;
          }
          final int marker = bytes[offset + 1];
          if (marker == 0xFF) {
            offset++;
            continue;
          }
          if (marker == 0xD8 ||
              marker == 0xD9 ||
              (marker >= 0xD0 && marker <= 0xD7)) {
            offset += 2;
            continue;
          }
          final int segLen = (bytes[offset + 2] << 8) | bytes[offset + 3];
          if (segLen < 2) break;
          final bool isSof =
              (marker >= 0xC0 && marker <= 0xC3) ||
              (marker >= 0xC5 && marker <= 0xC7) ||
              (marker >= 0xC9 && marker <= 0xCB) ||
              (marker >= 0xCD && marker <= 0xCF);
          if (isSof && offset + 8 < bytes.length) {
            final int h = (bytes[offset + 5] << 8) | bytes[offset + 6];
            final int w = (bytes[offset + 7] << 8) | bytes[offset + 8];
            if (w > 0 && h > 0) return (h / w).clamp(0.14, 2.2);
            break;
          }
          offset += 2 + segLen;
        }
      }
    } catch (_) {}
    return 0.62;
  }

  /// PNG / JPEG başlığından piksel genişliğini okur (bulunamazsa 0).
  static int getImagePixelWidth(Uint8List bytes) {
    try {
      if (bytes.length < 24) return 0;
      if (bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47) {
        return (bytes[16] << 24) |
            (bytes[17] << 16) |
            (bytes[18] << 8) |
            bytes[19];
      }
      if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
        int offset = 2;
        while (offset + 9 < bytes.length) {
          if (bytes[offset] != 0xFF) {
            offset++;
            continue;
          }
          final int marker = bytes[offset + 1];
          if (marker == 0xFF) {
            offset++;
            continue;
          }
          if (marker == 0xD8 ||
              marker == 0xD9 ||
              (marker >= 0xD0 && marker <= 0xD7)) {
            offset += 2;
            continue;
          }
          final int segLen = (bytes[offset + 2] << 8) | bytes[offset + 3];
          if (segLen < 2) break;
          final bool isSof =
              (marker >= 0xC0 && marker <= 0xC3) ||
              (marker >= 0xC5 && marker <= 0xC7) ||
              (marker >= 0xC9 && marker <= 0xCB) ||
              (marker >= 0xCD && marker <= 0xCF);
          if (isSof && offset + 8 < bytes.length) {
            return (bytes[offset + 7] << 8) | bytes[offset + 8];
          }
          offset += 2 + segLen;
        }
      }
    } catch (_) {}
    return 0;
  }

  // ─── 6. ADAPTİF SORU SEÇİMİ + BİREBİR SAYFA BÜTÇESİ SIĞDIRMA ALGORİTMASI ───

  double _scoreCandidateForStudent({
    required PoolQuestionItem question,
    required StudentMasteryProfile student,
    required PersonalizedBookConfig config,
    required double studentOutcomeMastery,
    required bool isExactOutcomeMatch,
  }) {
    final MasteryBand band = MasteryBandExt.fromPercent(studentOutcomeMastery);
    final double diff = question.difficulty;
    double score = 0.0;

    // 1. Kazanım eşleşme kalitesi
    score += isExactOutcomeMatch ? 45.0 : 5.0;

    // 2. Daha önce görmediği soru önceliği vs yanlış/boş bıraktığı soru
    final bool wasWrongOrEmpty = student.answeredWrongOrEmptyKeys.contains(
      question.examQuestionIdentity,
    );
    score += wasWrongOrEmpty ? 14.0 : 32.0;

    // 3. Seviye (Difficulty) uyumu + öğretmen 5 kademeli zorluk ağırlık çarpanı
    if (diff >= band.minPreferredDifficulty &&
        diff <= band.maxPreferredDifficulty) {
      score += 28.0;
    }
    final double dist = (diff - band.centerPreferredDifficulty).abs();
    score -= dist * 0.55;

    final double tierWeight = config.weightForDifficulty(diff);
    score += (tierWeight - 1.0) * 28.0;

    // 4. Yıldızlı / Kritik soru bonusu
    if (question.isCritical) {
      score += 6.0;
    }

    return score;
  }

  /// Öğrencinin bireysel kazanım karnesine, `minQuestions` kurallarına,
  /// `%100 Başarı Sıfır Soru` kuralına ve `targetPageCount` bütçesine göre
  /// tam sayfa sığdırmalı iki aşamalı (two-pass) kitap planını üretir.
  StudentBookPlan buildStudentBookPlan({
    required StudentMasteryProfile student,
    required PersonalizedBookConfig config,
    required List<ExamOutcomeTopicRule> rules,
    required List<PoolQuestionItem> preparedPool,
  }) {
    const int kTocRowsPerPage = PersonalizedBookConfig.kTocRowsPerPage;

    // Yalnızca görseli hazır olan, şablon filtrelerine (Egzersiz / Deneme) uyan
    // ve öğrencinin ZATEN DOĞRU YAPMADIĞI havuz soruları
    final List<PoolQuestionItem> validPool = preparedPool.where((q) {
      if (!q.isAllowedByConfig(config)) {
        return false;
      }
      if (q.cachedImageBytes == null || q.cachedImageBytes!.isEmpty) {
        return false;
      }
      if (student.answeredCorrectKeys.contains(q.examQuestionIdentity)) {
        return false;
      }
      return true;
    }).toList();

    final int coverPages = config.includeCover ? 1 : 0;
    int prefacePages = 0;
    if (config.prefaceMode == PrefaceMode.manual) {
      prefacePages = 1;
    } else if (config.prefaceMode == PrefaceMode.uploadedPdf) {
      prefacePages = config.uploadedPrefacePagePngs.length;
    }

    // Öğrencinin alan dışı (hiç işaretlemediği) branşları tespit et (ör. EA öğrencisi için AYT Fen)
    final Set<String> attemptedSubjects = {
      for (final entry in student.subjectStats.entries)
        if ((entry.value.correct + entry.value.wrong) > 0) entry.key,
    };
    final bool hasAttemptedOtherSubjects = attemptedSubjects.isNotEmpty;
    final bool poolHasQuestionsForAttemptedSubjects =
        hasAttemptedOtherSubjects &&
        validPool.any((q) => attemptedSubjects.contains(q.subject));

    // Aktif kuralları hazırla
    final List<_OutcomeCandidateBucket> buckets = [];
    int skippedMasteredCount = 0;

    for (final rule in rules) {
      final bool isDisabled =
          !rule.isEnabled || config.disabledOutcomeKeys.contains(rule.key);
      if (isDisabled) continue;

      final int minQ =
          config.minQuestionsByOutcomeKey[rule.key] ?? rule.minQuestions;
      final SubjectSummaryStat? subStat = student.subjectStats[rule.subject];
      final int subAttempted = (subStat?.correct ?? 0) + (subStat?.wrong ?? 0);
      final bool isUnattemptedSubject =
          hasAttemptedOtherSubjects && subAttempted == 0;

      // Öğrenci bu branşta tek bir soru bile işaretlemediyse ve minQuestions == 0 ise
      // alan dışı branş sorularının kitabı doldurmasını engelle
      if (isUnattemptedSubject &&
          minQ == 0 &&
          poolHasQuestionsForAttemptedSubjects) {
        continue;
      }

      final OutcomeMasteryStat? stStat = student.outcomeStats[rule.key];
      final double stMastery =
          stStat?.masteryPercent ?? student.overallAbilityPercent;

      // %100 Başarıda (Min=0 ise) Soru Sorma Kuralı!
      if (minQ == 0 &&
          config.skipZeroMinOnHighMastery &&
          stStat != null &&
          stStat.totalAsked > 0 &&
          stMastery >= config.highMasteryZeroThreshold - 0.01) {
        skippedMasteredCount++;
        continue;
      }

      // Bu kazanım için aday soruları topla ve adaptif puanla sırala
      final List<_ScoredQuestion> exactMatches = [];
      final List<_ScoredQuestion> fallbackMatches = [];

      for (final pq in validPool) {
        if (pq.subject != rule.subject) continue;
        final bool exact =
            pq.normalizedOutcomeKey == rule.key ||
            pq.matchesOutcomeTextOrK12(rule.outcome);
        if (exact) {
          exactMatches.add(
            _ScoredQuestion(
              item: pq,
              score: _scoreCandidateForStudent(
                question: pq,
                student: student,
                config: config,
                studentOutcomeMastery: stMastery,
                isExactOutcomeMatch: true,
              ),
            ),
          );
        } else if (config.allowSubjectFallbackWhenOutcomePoolShort) {
          fallbackMatches.add(
            _ScoredQuestion(
              item: pq,
              score: _scoreCandidateForStudent(
                question: pq,
                student: student,
                config: config,
                studentOutcomeMastery: stMastery,
                isExactOutcomeMatch: false,
              ),
            ),
          );
        }
      }

      exactMatches.sort((a, b) => b.score.compareTo(a.score));
      fallbackMatches.sort((a, b) => b.score.compareTo(a.score));

      final List<PoolQuestionItem> orderedCandidates = [
        ...exactMatches.map((e) => e.item),
        ...fallbackMatches.map((e) => e.item),
      ];

      if (orderedCandidates.isEmpty) continue;

      // İhtiyaç ağırlığı: öğrenci bu kazanımda ne kadar zayıfsa o kadar yüksek ağırlık!
      final double needWeight = (isUnattemptedSubject && minQ == 0)
          ? 0.08
          : (math.max(8.0, 100.0 - stMastery) +
                (stStat != null && stStat.wrong > 0
                    ? stStat.wrong * 6.0
                    : 0.0));

      buckets.add(
        _OutcomeCandidateBucket(
          rule: rule,
          minQuestions: minQ,
          studentMastery: stStat?.masteryPercent,
          effectiveMastery: stMastery,
          needWeight: needWeight,
          candidates: orderedCandidates,
        ),
      );
    }

    final Set<String> usedPoolKeys = {};
    final Map<String, List<PlacedBookQuestion>> selectedByRuleKey = {};

    int computeAnswerKeyPagesForCurrentSelection() {
      if (!config.includeAnswerKey) return 0;
      final Map<String, int> countsBySub = {};
      for (final list in selectedByRuleKey.values) {
        if (list.isEmpty) continue;
        final sub = list.first.subject;
        countsBySub[sub] = (countsBySub[sub] ?? 0) + list.length;
      }
      return FokusLayoutLimits.computeAnswerKeyPageCountFromCounts(
        includeAnswerKey: true,
        subjectQuestionCounts: countsBySub.values.toList(),
      );
    }

    // Sayfa bütçesini deterministik TOC (24 satır/sayfa) ve Cevap Anahtarı blok yüksekliği ile hesapla
    int computeTargetQuestionPages(int tocEntriesCount) {
      final int tocP = config.includeTableOfContents
          ? math.max(1, (tocEntriesCount / kTocRowsPerPage).ceil())
          : 0;
      final int ansP = computeAnswerKeyPagesForCurrentSelection();
      return math.max(
        1,
        config.targetPageCount - (coverPages + prefacePages + tocP + ansP),
      );
    }

    // Ortak metinli (passageId) kardeş soruları bir arada tutmak için yardımcı
    List<PoolQuestionItem> takeNextGroup(_OutcomeCandidateBucket bucket) {
      while (bucket.cursor < bucket.candidates.length) {
        final cand = bucket.candidates[bucket.cursor++];
        if (usedPoolKeys.contains(cand.poolKey)) continue;
        final pid = cand.passageId;
        if (pid != null && pid.isNotEmpty && cand.cachedPassageBytes != null) {
          final siblings =
              validPool
                  .where(
                    (x) =>
                        x.passageId == pid &&
                        x.examId == cand.examId &&
                        !usedPoolKeys.contains(x.poolKey),
                  )
                  .toList()
                ..sort((a, b) => a.questionNo.compareTo(b.questionNo));
          if (siblings.isNotEmpty) return siblings;
        }
        return [cand];
      }
      return const [];
    }

    int countTotalSelected() {
      int total = 0;
      for (final list in selectedByRuleKey.values) {
        total += list.length;
      }
      return total;
    }

    List<PackedQuestionPage> packCurrentSelection() {
      return _packSelectedQuestionsIntoPages(
        buckets: buckets,
        selectedByRuleKey: selectedByRuleKey,
      );
    }

    // AŞAMA A: Zorunlu Minimum Soruları (`minQuestions > 0`) yerleştir
    for (final bucket in buckets) {
      if (bucket.minQuestions <= 0) continue;
      int addedForBucket = 0;
      while (addedForBucket < bucket.minQuestions) {
        final group = takeNextGroup(bucket);
        if (group.isEmpty) break;

        final prevList = List<PlacedBookQuestion>.from(
          selectedByRuleKey[bucket.rule.key] ?? const [],
        );
        for (final q in group) {
          usedPoolKeys.add(q.poolKey);
          selectedByRuleKey
              .putIfAbsent(bucket.rule.key, () => [])
              .add(
                PlacedBookQuestion(
                  item: q,
                  subject: bucket.rule.subject,
                  outcome: bucket.rule.outcome,
                  studentOutcomeMastery: bucket.studentMastery,
                ),
              );
        }

        final packed = packCurrentSelection();
        final allowedQPages = computeTargetQuestionPages(
          selectedByRuleKey.values.where((l) => l.isNotEmpty).length,
        );
        if (packed.length > allowedQPages &&
            countTotalSelected() > group.length) {
          // Bütçeyi aşarsa geri al
          for (final q in group) {
            usedPoolKeys.remove(q.poolKey);
          }
          if (prevList.isEmpty) {
            selectedByRuleKey.remove(bucket.rule.key);
          } else {
            selectedByRuleKey[bucket.rule.key] = prevList;
          }
          break;
        }
        addedForBucket += group.length;
      }
    }

    // AŞAMA B: Kalan sayfa bütçesini `(100 - masteryPercent)` ağırlıklı olarak tam doldur!
    int consecutiveOverflowRejections = 0;
    const int maxConsecutiveOverflows = 4;

    while (consecutiveOverflowRejections < maxConsecutiveOverflows) {
      // Hâlâ adayı olan en yüksek öncelikli kazanım kovasını seç
      _OutcomeCandidateBucket? bestBucket;
      double bestPriority = -1.0;

      for (final b in buckets) {
        if (!b.hasMore(usedPoolKeys)) continue;
        final int currentCount = selectedByRuleKey[b.rule.key]?.length ?? 0;
        final double dynamicPriority = b.needWeight / (currentCount + 1.0);
        if (dynamicPriority > bestPriority) {
          bestPriority = dynamicPriority;
          bestBucket = b;
        }
      }

      if (bestBucket == null) break; // Tüm havuz tükendi

      final group = takeNextGroup(bestBucket);
      if (group.isEmpty) continue;

      final prevList = List<PlacedBookQuestion>.from(
        selectedByRuleKey[bestBucket.rule.key] ?? const [],
      );
      for (final q in group) {
        usedPoolKeys.add(q.poolKey);
        selectedByRuleKey
            .putIfAbsent(bestBucket.rule.key, () => [])
            .add(
              PlacedBookQuestion(
                item: q,
                subject: bestBucket.rule.subject,
                outcome: bestBucket.rule.outcome,
                studentOutcomeMastery: bestBucket.studentMastery,
              ),
            );
      }

      final packed = packCurrentSelection();
      final int activeOutcomeCount = selectedByRuleKey.values
          .where((l) => l.isNotEmpty)
          .length;
      final int allowedQPages = computeTargetQuestionPages(activeOutcomeCount);

      if (packed.length <= allowedQPages) {
        consecutiveOverflowRejections = 0;
      } else {
        // Bu grup sayfa sayısını `allowedQPages + 1` yaptı -> geri al; kapasite sınırında 4 ardışık taşmada erken çık
        for (final q in group) {
          usedPoolKeys.remove(q.poolKey);
        }
        if (prevList.isEmpty) {
          selectedByRuleKey.remove(bestBucket.rule.key);
        } else {
          selectedByRuleKey[bestBucket.rule.key] = prevList;
        }
        consecutiveOverflowRejections++;
      }
    }

    // Son paketleme ve sıra numaralarını (her branş kendi içinde 1, 2, 3...) atama
    List<PackedQuestionPage> packedPages = packCurrentSelection();
    final int pureQuestionPagesCount = packedPages.length;
    final int finalTotalQuestions = countTotalSelected();

    final Map<String, int> seqBySubject = {};
    final Map<String, List<PlacedBookQuestion>> questionsBySubject = {};
    final Set<String> uniqueTocOutcomeKeys = {};

    for (final page in packedPages) {
      if (page.isStudyNotePadPage) continue;
      for (final block in page.blocks) {
        final List<PlacedBookQuestion> blockQuestions = [
          ...block.leftColumn,
          ...block.rightColumn,
          ...block.fullWidthQuestions,
        ];
        for (final pq in blockQuestions) {
          final nextSeq = (seqBySubject[pq.subject] ?? 0) + 1;
          seqBySubject[pq.subject] = nextSeq;
          pq.sequenceNoInSubject = nextSeq;
          questionsBySubject.putIfAbsent(pq.subject, () => []).add(pq);
          uniqueTocOutcomeKeys.add('${pq.subject}::${pq.outcome}');
        }
      }
    }

    final int finalTocPages = config.includeTableOfContents
        ? math.max(1, (uniqueTocOutcomeKeys.length / kTocRowsPerPage).ceil())
        : 0;
    final List<List<AnswerKeyBlockPlan>> answerKeyPageBlocks =
        config.includeAnswerKey
        ? FokusLayoutLimits.paginateAnswerKeyBlocks(questionsBySubject)
        : const [];
    final int finalAnswerKeyPages = config.includeAnswerKey
        ? answerKeyPageBlocks.length
        : 0;

    final int targetQuestionPages = math.max(
      1,
      config.targetPageCount -
          (coverPages + prefacePages + finalTocPages + finalAnswerKeyPages),
    );

    int notePadPagesCount = 0;
    if (packedPages.isEmpty ||
        (config.padShortBooksWithStudyNotes &&
            packedPages.length < targetQuestionPages)) {
      final int padNeeded = math.max(
        packedPages.isEmpty ? 1 : 0,
        config.padShortBooksWithStudyNotes
            ? (targetQuestionPages - packedPages.length)
            : 0,
      );
      for (int p = 0; p < padNeeded; p++) {
        packedPages.add(
          const PackedQuestionPage(
            primarySubject: 'Kişisel Çalışma & Çözüm Alanı',
            isStudyNotePadPage: true,
            blocks: [
              PackedPageBlock(
                kind: QuestionBlockKind.studyNotesPad,
                subject: 'Kişisel Çalışma & Çözüm Alanı',
                outcome: 'Kazanım Tekrar ve Çözüm Notları',
                allocatedHeight: _bodyMaxHeight,
              ),
            ],
          ),
        );
        notePadPagesCount++;
      }
    }

    // İKİ AŞAMALI (TWO-PASS) TOC gerçek başlangıç sayfa numaralarını üret!
    final List<TocEntryItem> tocEntries = [];
    final Set<String> recordedTocOutcomes = {};
    final Set<String> seenSubjectsInToc = {};

    final int firstQuestionPageNumber =
        coverPages + prefacePages + finalTocPages + 1;

    for (int pageIdx = 0; pageIdx < packedPages.length; pageIdx++) {
      final page = packedPages[pageIdx];
      final int exactPageNumber = firstQuestionPageNumber + pageIdx;
      if (page.isStudyNotePadPage) continue;

      for (final block in page.blocks) {
        final List<PlacedBookQuestion> blockQuestions = [
          ...block.leftColumn,
          ...block.rightColumn,
          ...block.fullWidthQuestions,
        ];
        for (final pq in blockQuestions) {
          final tocKey = '${pq.subject}::${pq.outcome}';
          if (!recordedTocOutcomes.contains(tocKey)) {
            recordedTocOutcomes.add(tocKey);
            final isFirstSub = !seenSubjectsInToc.contains(pq.subject);
            seenSubjectsInToc.add(pq.subject);

            int countInOutcome = 0;
            for (final list in selectedByRuleKey.values) {
              if (list.isNotEmpty &&
                  list.first.subject == pq.subject &&
                  list.first.outcome == pq.outcome) {
                countInOutcome += list.length;
              }
            }

            tocEntries.add(
              TocEntryItem(
                subject: pq.subject,
                outcome: pq.outcome,
                questionCount: countInOutcome > 0 ? countInOutcome : 1,
                studentMasteryPercent: pq.studentOutcomeMastery,
                startPageNumber: exactPageNumber,
                isSubjectFirstEntry: isFirstSub,
              ),
            );
          }
        }
      }
    }

    final int? answerKeyStartPage = finalAnswerKeyPages > 0
        ? (firstQuestionPageNumber + packedPages.length)
        : null;

    final int actualTotalPages =
        coverPages +
        prefacePages +
        finalTocPages +
        packedPages.length +
        finalAnswerKeyPages;

    return StudentBookPlan(
      student: student,
      coverPages: coverPages,
      prefacePages: prefacePages,
      tocPages: finalTocPages,
      questionPagesCount: pureQuestionPagesCount,
      studyNotePadPagesCount: notePadPagesCount,
      answerKeyPages: finalAnswerKeyPages,
      totalPages: actualTotalPages,
      totalQuestionCount: finalTotalQuestions,
      skippedMasteredOutcomeCount: skippedMasteredCount,
      tocEntries: tocEntries,
      answerKeyStartPage: answerKeyStartPage,
      packedPages: packedPages,
      questionsBySubject: questionsBySubject,
      answerKeyPageBlocks: answerKeyPageBlocks,
    );
  }

  // ─── 7. 2 SÜTUNLU A4 SAYFA PAKETLEYİCİ (262pt + 20pt + 262pt) ──────────────

  double _estimateNarrowHeight(PoolQuestionItem q, {double widthScale = 1.0}) {
    final double ar = q.cachedAspectRatio ?? 0.62;
    final double imgH = ((_colWidth * widthScale) * ar).clamp(54.0, 520.0);
    return 24.0 + imgH + 6.0; // header (20+4) + img + alt boşluk
  }

  double _estimateWideHeight(PoolQuestionItem q) {
    final double ar = q.cachedAspectRatio ?? 0.50;
    final double imgH = ((_fullPageWidth - 6.0) * ar).clamp(65.0, 540.0);
    final double rawH = 26.0 + imgH + 8.0;
    if (rawH >= _bodyMaxHeight * 0.65) return rawH;
    final double halfCap = (_bodyMaxHeight - 36.0) * 0.48;
    return math.min(rawH, halfCap);
  }

  double _estimatePassageGroupHeight(List<PlacedBookQuestion> group) {
    final double pAr = group.first.item.cachedPassageAspectRatio ?? 0.38;
    final double pH = (520.0 * pAr).clamp(55.0, 185.0);
    if (group.length >= 2 && group.every((g) => !_isEffectivelyWide(g.item))) {
      final int split = (group.length / 2).ceil();
      final left = group.sublist(0, split);
      final right = group.sublist(split);
      final double lH = _sumColumnHeight(left, widthScale: 0.92);
      final double rH = _sumColumnHeight(right, widthScale: 0.92);
      final double colsH = math.max(lH, rH).clamp(75.0, 380.0);
      return 34.0 + pH + 14.0 + colsH + 8.0;
    }
    double qTotal = 0.0;
    for (final g in group) {
      final double qAr = g.item.cachedAspectRatio ?? 0.55;
      qTotal += 26.0 + (320.0 * qAr).clamp(55.0, 210.0) + 8.0;
    }
    return (34.0 + pH + 12.0 + qTotal).clamp(150.0, _bodyMaxHeight - 50.0);
  }

  bool _isEffectivelyWide(PoolQuestionItem q) {
    if (q.isWide) return true;
    final double ar = q.cachedAspectRatio ?? 0.62;
    if (q.cachedImageBytes != null) {
      final int pxW = getImagePixelWidth(q.cachedImageBytes!);
      if (pxW > 0) {
        if (pxW < DriveImageHelper.kWidePixelThreshold) {
          return ar < 0.28;
        }
        return ar < 0.50;
      }
    }
    return ar < 0.36;
  }

  double _sumColumnHeight(
    List<PlacedBookQuestion> col, {
    double widthScale = 1.0,
  }) {
    if (col.isEmpty) return 0.0;
    double sum = 0.0;
    for (int i = 0; i < col.length; i++) {
      sum += _estimateNarrowHeight(col[i].item, widthScale: widthScale);
      if (i < col.length - 1) sum += 26.0;
    }
    return sum;
  }

  /// Fokus Kitap için çift sütunlu akıllı dizgi kombinasyon seçici:
  /// Dar soru havuzundan Sol ve Sağ sütunu BİRLİKTE seçerek:
  /// - Uzun soru ile kısa soruyu aynı sütunda eşleştirir (`tall + short | tall + short`) veya
  ///   3 kısa soruyu 2 orta-uzun soruyla dengeler (`3 short | 2 medium-tall`),
  /// - İki sütun arasındaki yükseklik farkını (`|lH - rH|`) minimize eder,
  /// - Sorular arasında ferah boşluk bırakır ve üst/alt sınırları tam hizalar.
  ({List<PlacedBookQuestion> left, List<PlacedBookQuestion> right})
      _selectSmartTwoColumnPairForBook(
    List<PlacedBookQuestion> narrowPool,
    double maxSectionH,
  ) {
    if (narrowPool.isEmpty) {
      return (left: <PlacedBookQuestion>[], right: <PlacedBookQuestion>[]);
    }
    if (narrowPool.length == 1) {
      return (
        left: <PlacedBookQuestion>[narrowPool.removeAt(0)],
        right: <PlacedBookQuestion>[],
      );
    }

    const double gap = 26.0;
    final int m = narrowPool.length < 12 ? narrowPool.length : 12;
    final List<double> hNat = List<double>.generate(
      m,
      (idx) => _estimateNarrowHeight(narrowPool[idx].item, widthScale: 1.0),
    );
    final List<double> hMin = List<double>.generate(
      m,
      (idx) => _estimateNarrowHeight(narrowPool[idx].item, widthScale: 0.90),
    );

    final List<({int mask, List<int> indices, double natH, double minH})>
        candCols = [];

    void addIfFits(List<int> idxs) {
      final int k = idxs.length;
      double sumNat = (k - 1) * gap;
      double sumMin = (k - 1) * gap;
      int mask = 0;
      for (final idx in idxs) {
        sumNat += hNat[idx];
        sumMin += hMin[idx];
        mask |= (1 << idx);
      }
      if (k == 1 ||
          (k == 2 && sumMin <= maxSectionH * 0.96) ||
          (k == 3 && sumNat <= maxSectionH * 0.88)) {
        candCols.add((
          mask: mask,
          indices: idxs,
          natH: sumNat,
          minH: sumMin,
        ));
      }
    }

    for (int a = 0; a < m; a++) {
      addIfFits([a]);
      for (int b = a + 1; b < m; b++) {
        addIfFits([a, b]);
        for (int c = b + 1; c < m; c++) {
          addIfFits([a, b, c]);
        }
      }
    }

    double bestScore = double.negativeInfinity;
    List<int> chosenLeftIdx = [0];
    List<int> chosenRightIdx = narrowPool.length >= 2 ? [1] : const [];

    for (int i = 0; i < candCols.length; i++) {
      final c1 = candCols[i];
      for (int j = i + 1; j < candCols.length; j++) {
        final c2 = candCols[j];
        if ((c1.mask & c2.mask) != 0) continue;

        final leftCand = c1.indices.first < c2.indices.first ? c1 : c2;
        final rightCand = c1.indices.first < c2.indices.first ? c2 : c1;

        final double lH = leftCand.natH;
        final double rH = rightCand.natH;
        final int lLen = leftCand.indices.length;
        final int rLen = rightCand.indices.length;

        final double effL = lH.clamp(0.0, maxSectionH);
        final double effR = rH.clamp(0.0, maxSectionH);
        final double avgFill = (effL + effR) / (2.0 * maxSectionH);
        final double diffRatio = ((lH - rH).abs() / maxSectionH).clamp(0.0, 1.0);

        double score = (avgFill * 2.3) + ((1.0 - diffRatio) * 1.45);

        if (lLen >= 2 && rLen >= 2) {
          score += 1.15;
        } else if (lLen >= 2 || rLen >= 2) {
          final double singleH = lLen == 1 ? lH : rH;
          if (singleH >= maxSectionH * 0.68) {
            score += 0.55;
          } else {
            score -= 0.55;
          }
        } else {
          if (lH >= maxSectionH * 0.65 && rH >= maxSectionH * 0.65) {
            score += 0.40;
          } else if (narrowPool.length > 2) {
            score -= 0.85;
          }
        }

        if (lH <= maxSectionH && rH <= maxSectionH) {
          score += 0.45;
        } else {
          final double overL = lH > maxSectionH ? (lH - maxSectionH) : 0.0;
          final double overR = rH > maxSectionH ? (rH - maxSectionH) : 0.0;
          score -= ((overL + overR) / maxSectionH) * 1.85;
        }

        double orderBonus = 0.0;
        for (final idx in leftCand.indices) {
          orderBonus += ((m - idx) / m) * 0.07;
        }
        for (final idx in rightCand.indices) {
          orderBonus += ((m - idx) / m) * 0.07;
        }
        if (leftCand.indices.first == 0) {
          orderBonus += 0.14;
        }
        score += orderBonus;

        if (score > bestScore) {
          bestScore = score;
          chosenLeftIdx = leftCand.indices;
          chosenRightIdx = rightCand.indices;
        }
      }
    }

    final List<PlacedBookQuestion> bestLeft = [
      for (final idx in chosenLeftIdx) narrowPool[idx],
    ];
    final List<PlacedBookQuestion> bestRight = [
      for (final idx in chosenRightIdx) narrowPool[idx],
    ];

    final List<int> allUsed = [...chosenLeftIdx, ...chosenRightIdx]..sort();
    for (final idx in allUsed.reversed) {
      narrowPool.removeAt(idx);
    }

    return (left: bestLeft, right: bestRight);
  }

  List<PackedQuestionPage> _packSelectedQuestionsIntoPages({
    required List<_OutcomeCandidateBucket> buckets,
    required Map<String, List<PlacedBookQuestion>> selectedByRuleKey,
  }) {
    // Branş -> Kazanım sırasına göre seçili soruları düzenle
    final Map<String, List<_OutcomeSlice>> slicesBySubject = {};
    for (final b in buckets) {
      final qList = selectedByRuleKey[b.rule.key];
      if (qList == null || qList.isEmpty) continue;
      slicesBySubject
          .putIfAbsent(b.rule.subject, () => [])
          .add(
            _OutcomeSlice(
              subject: b.rule.subject,
              outcome: b.rule.outcome,
              mastery: b.studentMastery,
              questions: qList,
            ),
          );
    }

    final List<String> subjects = slicesBySubject.keys.toList()
      ..sort((a, b) {
        final rCmp = FokusTextUtils.subjectSortRank(
          a,
        ).compareTo(FokusTextUtils.subjectSortRank(b));
        return rCmp != 0 ? rCmp : a.compareTo(b);
      });

    final List<PackedQuestionPage> pages = [];

    for (final subject in subjects) {
      final slices = slicesBySubject[subject]!;
      List<PackedPageBlock> currentBlocks = [];
      double remH = _bodyMaxHeight;
      bool subjectBannerShown = false;

      void flushPage() {
        if (currentBlocks.isNotEmpty) {
          pages.add(
            PackedQuestionPage(
              primarySubject: subject,
              blocks: List<PackedPageBlock>.from(currentBlocks),
            ),
          );
          currentBlocks = [];
        }
        remH = _bodyMaxHeight;
      }

      for (final slice in slices) {
        bool outcomeRibbonShown = false;
        int i = 0;
        final qList = slice.questions;

        while (i < qList.length) {
          final double headerOverhead =
              (!subjectBannerShown ? 44.0 : 0.0) +
              (!outcomeRibbonShown ? 26.0 : 0.0);

          // 1. Ortak metinli (passageBytes) grup
          if (qList[i].item.cachedPassageBytes != null) {
            final String? pid = qList[i].item.passageId;
            final List<PlacedBookQuestion> pGroup = [qList[i]];
            i++;
            if (pid != null && pid.isNotEmpty) {
              while (i < qList.length && qList[i].item.passageId == pid) {
                pGroup.add(qList[i]);
                i++;
              }
            }
            final double estH = _estimatePassageGroupHeight(pGroup);
            if (remH < headerOverhead + estH && currentBlocks.isNotEmpty) {
              flushPage();
            }
            final double freshOverhead =
                (!subjectBannerShown ? 44.0 : 0.0) +
                (!outcomeRibbonShown ? 26.0 : 0.0);
            final double allocH = math.min(remH - freshOverhead, estH);
            currentBlocks.add(
              PackedPageBlock(
                kind: QuestionBlockKind.sharedPassageGroup,
                subject: subject,
                outcome: slice.outcome,
                showSubjectBanner: !subjectBannerShown,
                showOutcomeRibbon: !outcomeRibbonShown,
                studentOutcomeMastery: slice.mastery,
                fullWidthQuestions: pGroup,
                allocatedHeight: allocH,
              ),
            );
            subjectBannerShown = true;
            outcomeRibbonShown = true;
            remH -= (freshOverhead + allocH + 8.0);
            continue;
          }

          // 2. Geniş (2 sütunluk) soru
          if (_isEffectivelyWide(qList[i].item)) {
            final wq = qList[i];
            i++;
            final double estW = _estimateWideHeight(wq.item);
            if (remH < headerOverhead + math.min(estW, 200.0) &&
                currentBlocks.isNotEmpty) {
              flushPage();
            }
            final double freshOverhead =
                (!subjectBannerShown ? 44.0 : 0.0) +
                (!outcomeRibbonShown ? 26.0 : 0.0);
            final double availForWide = (remH - freshOverhead).clamp(
              140.0,
              _bodyMaxHeight - freshOverhead,
            );
            final double allocH = math.min(estW, availForWide);
            currentBlocks.add(
              PackedPageBlock(
                kind: QuestionBlockKind.wideQuestion,
                subject: subject,
                outcome: slice.outcome,
                showSubjectBanner: !subjectBannerShown,
                showOutcomeRibbon: !outcomeRibbonShown,
                studentOutcomeMastery: slice.mastery,
                fullWidthQuestions: [wq],
                allocatedHeight: allocH,
              ),
            );
            subjectBannerShown = true;
            outcomeRibbonShown = true;
            remH -= (freshOverhead + allocH + 8.0);
            continue;
          }

          // 3. Ardışık dar (1 sütunluk) soruları topla ve 2 sütuna dengeli diz
          final List<PlacedBookQuestion> narrowPool = [];
          while (i < qList.length &&
              qList[i].item.cachedPassageBytes == null &&
              !_isEffectivelyWide(qList[i].item)) {
            narrowPool.add(qList[i]);
            i++;
          }

          while (narrowPool.isNotEmpty) {
            final double curOverhead =
                (!subjectBannerShown ? 44.0 : 0.0) +
                (!outcomeRibbonShown ? 26.0 : 0.0);
            final double minFirst = _estimateNarrowHeight(
              narrowPool.first.item,
              widthScale: 0.88,
            );

            if (remH < curOverhead + minFirst + 4.0 &&
                currentBlocks.isNotEmpty) {
              flushPage();
            }

            final double effOverhead =
                (!subjectBannerShown ? 44.0 : 0.0) +
                (!outcomeRibbonShown ? 26.0 : 0.0);
            final double maxSectionH = (remH - effOverhead).clamp(
              90.0,
              _bodyMaxHeight - effOverhead,
            );

            final paired = _selectSmartTwoColumnPairForBook(
              narrowPool,
              maxSectionH,
            );
            final List<PlacedBookQuestion> bestLeft = paired.left;
            final List<PlacedBookQuestion> bestRight = paired.right;

            final double naturalH = math.max(
              _sumColumnHeight(bestLeft),
              _sumColumnHeight(bestRight),
            );
            final bool fillsRestOfPage =
                narrowPool.isNotEmpty ||
                ((bestLeft.length >= 2 || bestRight.length >= 2) &&
                    naturalH >= maxSectionH * 0.52);
            final double sectionAllocH = fillsRestOfPage
                ? (maxSectionH - 2.0).clamp(90.0, maxSectionH)
                : naturalH.clamp(85.0, maxSectionH);

            currentBlocks.add(
              PackedPageBlock(
                kind: QuestionBlockKind.twoColumnSection,
                subject: subject,
                outcome: slice.outcome,
                showSubjectBanner: !subjectBannerShown,
                showOutcomeRibbon: !outcomeRibbonShown,
                studentOutcomeMastery: slice.mastery,
                leftColumn: bestLeft,
                rightColumn: bestRight,
                allocatedHeight: sectionAllocH,
              ),
            );

            subjectBannerShown = true;
            outcomeRibbonShown = true;
            remH -= (effOverhead + sectionAllocH + 8.0);

            if (narrowPool.isNotEmpty) {
              flushPage();
            }
          }
        }
      }

      if (currentBlocks.isNotEmpty) {
        flushPage();
      }
    }

    return pages;
  }

  // ─── 8. PDF DÖKÜMAN OLUŞTURMA & DIŞA AKTARIM (ÖNİZLEME / TEK / ZIP / BİRLEŞİK)

  Future<(pw.Font, pw.Font)> _loadFonts() async {
    try {
      final reg = await PdfGoogleFonts.robotoRegular().timeout(
        const Duration(seconds: 6),
      );
      final bold = await PdfGoogleFonts.robotoBold().timeout(
        const Duration(seconds: 6),
      );
      return (reg, bold);
    } catch (_) {
      return (pw.Font.helvetica(), pw.Font.helveticaBold());
    }
  }

  Future<Uint8List> generateSingleStudentPdfBytes({
    required StudentMasteryProfile student,
    required PersonalizedBookConfig config,
    required List<ExamOutcomeTopicRule> rules,
    required List<PoolQuestionItem> pool,
  }) async {
    await ensurePoolImagesPrepared(pool);
    final (reg, bold) = await _loadFonts();
    final doc = pw.Document();
    final plan = buildStudentBookPlan(
      student: student,
      config: config,
      rules: rules,
      preparedPool: pool,
    );
    appendStudentBookToDocument(
      doc: doc,
      plan: plan,
      config: config,
      reg: reg,
      bold: bold,
    );
    return doc.save();
  }

  Future<void> previewSingleStudentBook({
    required StudentMasteryProfile student,
    required PersonalizedBookConfig config,
    required List<ExamOutcomeTopicRule> rules,
    required List<PoolQuestionItem> pool,
  }) async {
    final bytes = await generateSingleStudentPdfBytes(
      student: student,
      config: config,
      rules: rules,
      pool: pool,
    );
    final safeName = sanitizeFileName('${student.name}_FokusKitap.pdf');
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: safeName);
  }

  Future<void> downloadSingleStudentBook({
    required StudentMasteryProfile student,
    required PersonalizedBookConfig config,
    required List<ExamOutcomeTopicRule> rules,
    required List<PoolQuestionItem> pool,
  }) async {
    final bytes = await generateSingleStudentPdfBytes(
      student: student,
      config: config,
      rules: rules,
      pool: pool,
    );
    final safeName = sanitizeFileName('${student.name}_FokusKitap.pdf');
    await downloadFileUniversal(
      bytes: bytes,
      fileName: safeName,
      mimeType: 'application/pdf',
    );
    await recordGenerationHistory(
      institutionId: config.institutionId,
      config: config,
      studentCount: 1,
      exportMode: 'single',
    );
  }

  Future<void> exportBulkBooksAsZip({
    required List<StudentMasteryProfile> students,
    required PersonalizedBookConfig config,
    required List<ExamOutcomeTopicRule> rules,
    required List<PoolQuestionItem> pool,
    void Function(int current, int total, String status)? onProgress,
  }) async {
    if (students.isEmpty) return;
    onProgress?.call(0, students.length, 'Soru görselleri hazırlanıyor...');
    await ensurePoolImagesPrepared(pool);
    final (reg, bold) = await _loadFonts();

    final archive = Archive();
    for (int idx = 0; idx < students.length; idx++) {
      final st = students[idx];
      onProgress?.call(idx + 1, students.length, st.name);
      await Future.delayed(Duration.zero);

      final doc = pw.Document();
      final plan = buildStudentBookPlan(
        student: st,
        config: config,
        rules: rules,
        preparedPool: pool,
      );
      appendStudentBookToDocument(
        doc: doc,
        plan: plan,
        config: config,
        reg: reg,
        bold: bold,
      );
      final pdfBytes = await doc.save();

      final safeBranch = st.branch.trim().replaceAll(
        RegExp(r'[\\/:*?"<>|]'),
        '_',
      );
      final safeStudentFile = sanitizeFileName('${st.name}_FokusKitap.pdf');
      final zipPath =
          '${safeBranch.isEmpty ? 'Genel' : safeBranch}/$safeStudentFile';
      archive.addFile(
        ArchiveFile.noCompress(zipPath, pdfBytes.length, pdfBytes),
      );
    }

    onProgress?.call(
      students.length,
      students.length,
      'ZIP arşivi paketleniyor...',
    );
    await Future.delayed(Duration.zero);

    final encodedZip = ZipEncoder().encode(archive);
    if (encodedZip == null) return;
    final zipBytes = Uint8List.fromList(encodedZip);
    final zipName = sanitizeFileName('${config.bookTitle}_Toplu_Kitaplar.zip');

    await downloadFileUniversal(
      bytes: zipBytes,
      fileName: zipName,
      mimeType: 'application/zip',
    );
    await recordGenerationHistory(
      institutionId: config.institutionId,
      config: config,
      studentCount: students.length,
      exportMode: 'zip',
    );
  }

  Future<void> exportBulkBooksAsCombinedPdf({
    required List<StudentMasteryProfile> students,
    required PersonalizedBookConfig config,
    required List<ExamOutcomeTopicRule> rules,
    required List<PoolQuestionItem> pool,
    void Function(int current, int total, String status)? onProgress,
  }) async {
    if (students.isEmpty) return;
    onProgress?.call(0, students.length, 'Soru görselleri hazırlanıyor...');
    await ensurePoolImagesPrepared(pool);
    final (reg, bold) = await _loadFonts();

    final combinedDoc = pw.Document();
    for (int idx = 0; idx < students.length; idx++) {
      final st = students[idx];
      onProgress?.call(idx + 1, students.length, st.name);
      await Future.delayed(Duration.zero);

      final plan = buildStudentBookPlan(
        student: st,
        config: config,
        rules: rules,
        preparedPool: pool,
      );
      appendStudentBookToDocument(
        doc: combinedDoc,
        plan: plan,
        config: config,
        reg: reg,
        bold: bold,
      );
    }

    onProgress?.call(
      students.length,
      students.length,
      'Birleşik PDF kaydediliyor...',
    );
    await Future.delayed(Duration.zero);

    final pdfBytes = await combinedDoc.save();
    final fileName = sanitizeFileName(
      '${config.bookTitle}_Birlesik_Baski_${students.length}_Ogrenci.pdf',
    );

    await downloadFileUniversal(
      bytes: pdfBytes,
      fileName: fileName,
      mimeType: 'application/pdf',
    );
    await recordGenerationHistory(
      institutionId: config.institutionId,
      config: config,
      studentCount: students.length,
      exportMode: 'combined_pdf',
    );
  }

  // ─── 9. KİTAP SAYFALARINI PDF DÖKÜMANINA EKLEME ────────────────────────────

  void appendStudentBookToDocument({
    required pw.Document doc,
    required StudentBookPlan plan,
    required PersonalizedBookConfig config,
    required pw.Font reg,
    required pw.Font bold,
  }) {
    final theme = config.coverTheme;
    final primaryPdf = PdfColor.fromInt(theme.primaryHex);
    final secondaryPdf = PdfColor.fromInt(theme.secondaryHex);
    final accentPdf = PdfColor.fromInt(theme.accentHex);
    final softPdf = PdfColor.fromInt(theme.softTintHex);

    int bookPageCursor = 0;

    // 1. KAPAK SAYFASI
    if (config.includeCover) {
      bookPageCursor++;
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) => _buildCoverPage(
            plan: plan,
            config: config,
            primaryPdf: primaryPdf,
            secondaryPdf: secondaryPdf,
            accentPdf: accentPdf,
            softPdf: softPdf,
            reg: reg,
            bold: bold,
          ),
        ),
      );
    }

    // 2. ÖN SÖZ SAYFALARI (Manuel VEYA Yüklenen Ek PDF!)
    if (config.prefaceMode == PrefaceMode.manual) {
      bookPageCursor++;
      final currentNo = bookPageCursor;
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 28),
          build: (_) => _buildManualPrefacePage(
            plan: plan,
            config: config,
            pageNo: currentNo,
            primaryPdf: primaryPdf,
            accentPdf: accentPdf,
            softPdf: softPdf,
            reg: reg,
            bold: bold,
          ),
        ),
      );
    } else if (config.prefaceMode == PrefaceMode.uploadedPdf &&
        config.uploadedPrefacePagePngs.isNotEmpty) {
      for (final pngBytes in config.uploadedPrefacePagePngs) {
        bookPageCursor++;
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Container(
              width: PdfPageFormat.a4.width,
              height: PdfPageFormat.a4.height,
              color: PdfColors.white,
              alignment: pw.Alignment.center,
              child: pw.Image(
                pw.MemoryImage(pngBytes),
                width: PdfPageFormat.a4.width,
                height: PdfPageFormat.a4.height,
                fit: pw.BoxFit.contain,
              ),
            ),
          ),
        );
      }
    }

    // 3. İÇİNDEKİLER SAYFALARI (24 satır/sayfa dinamik çok sayfalı dilimleme!)
    if (config.includeTableOfContents && plan.budget.tocPages > 0) {
      const int kTocRowsPerPage = PersonalizedBookConfig.kTocRowsPerPage;
      for (int p = 0; p < plan.budget.tocPages; p++) {
        bookPageCursor++;
        final int pageNo = bookPageCursor;
        final int start = p * kTocRowsPerPage;
        final int end = math.min(
          plan.tocEntries.length,
          start + kTocRowsPerPage,
        );
        final List<TocEntryItem> entries = start < plan.tocEntries.length
            ? plan.tocEntries.sublist(start, end)
            : const <TocEntryItem>[];
        final bool isLastTocPage = p == plan.budget.tocPages - 1;
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.fromLTRB(30, 26, 30, 24),
            build: (_) => _buildTocPage(
              plan: plan,
              config: config,
              entries: entries,
              isContinuation: p > 0,
              showAnswerKeyRow:
                  isLastTocPage && plan.answerKeyStartPage != null,
              pageNo: pageNo,
              primaryPdf: primaryPdf,
              accentPdf: accentPdf,
              softPdf: softPdf,
              reg: reg,
              bold: bold,
            ),
          ),
        );
      }
    }

    // 4. SORU BANKASI SAYFALARI (+ Varsa Çalışma Not Alanı Tamamlama Sayfaları)
    for (int pIdx = 0; pIdx < plan.packedPages.length; pIdx++) {
      bookPageCursor++;
      final int pageNo = bookPageCursor;
      final packedPage = plan.packedPages[pIdx];
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(24, 20, 24, 20),
          build: (_) => _buildPackedQuestionPageWidget(
            plan: plan,
            config: config,
            packedPage: packedPage,
            pageNo: pageNo,
            studyNoteIndex: pIdx + 1,
            primaryPdf: primaryPdf,
            accentPdf: accentPdf,
            softPdf: softPdf,
            reg: reg,
            bold: bold,
          ),
        ),
      );
    }

    // 5. CEVAP ANAHTARI SAYFALARI (Yükseklik ve hücre sınırı korumalı çoklu sayfa!)
    if (config.includeAnswerKey && plan.answerKeyPages > 0) {
      final List<List<AnswerKeyBlockPlan>> answerPages =
          plan.answerKeyPageBlocks.isNotEmpty
          ? plan.answerKeyPageBlocks
          : FokusLayoutLimits.paginateAnswerKeyBlocks(plan.questionsBySubject);

      for (int aIdx = 0; aIdx < plan.answerKeyPages; aIdx++) {
        bookPageCursor++;
        final int pageNo = bookPageCursor;
        final List<AnswerKeyBlockPlan> blocksOnPage = aIdx < answerPages.length
            ? answerPages[aIdx]
            : const <AnswerKeyBlockPlan>[];
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 22),
            build: (_) => _buildAnswerKeyPage(
              plan: plan,
              config: config,
              blocksOnPage: blocksOnPage,
              isContinuation: aIdx > 0,
              pageNo: pageNo,
              primaryPdf: primaryPdf,
              softPdf: softPdf,
              reg: reg,
              bold: bold,
            ),
          ),
        );
      }
    }
  }

  // ─── PDF BİLEŞENLERİ: KAPAK, ÖN SÖZ, İÇİNDEKİLER, SORU SAYFASI, CEVAP ANAHTARI

  pw.Widget _buildEduknVectorLogo({
    required pw.Font bold,
    required PdfColor textColor,
    required PdfColor barColor,
    required PdfColor cyanColor,
    double fontSize = 26,
  }) {
    final scale = fontSize / 26.0;
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Transform(
          transform: vm.Matrix4.skewX(-0.2679),
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(
                width: 15 * scale,
                height: 3.0 * scale,
                decoration: pw.BoxDecoration(
                  color: barColor,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(1.2),
                  ),
                ),
              ),
              pw.SizedBox(height: 2.0 * scale),
              pw.Container(
                width: 22 * scale,
                height: 3.0 * scale,
                decoration: pw.BoxDecoration(
                  color: barColor,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(1.2),
                  ),
                ),
              ),
              pw.SizedBox(height: 2.0 * scale),
              pw.Container(
                width: 11 * scale,
                height: 3.0 * scale,
                decoration: pw.BoxDecoration(
                  color: cyanColor,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(1.2),
                  ),
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 8 * scale),
        pw.Text(
          'eduKN',
          style: pw.TextStyle(
            font: bold,
            fontSize: fontSize,
            fontStyle: pw.FontStyle.italic,
            color: textColor,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildCoverPage({
    required StudentBookPlan plan,
    required PersonalizedBookConfig config,
    required PdfColor primaryPdf,
    required PdfColor secondaryPdf,
    required PdfColor accentPdf,
    required PdfColor softPdf,
    required pw.Font reg,
    required pw.Font bold,
  }) {
    final st = plan.student;
    final bool isMinimal = config.coverTheme.isLightCover;
    final bool hasCustomImage =
        config.customCoverImageBytes != null &&
        config.customCoverImageBytes!.isNotEmpty;
    final bgColor = isMinimal ? PdfColors.white : primaryPdf;
    final titleColor = isMinimal ? primaryPdf : PdfColors.white;
    final subColor = isMinimal ? PdfColors.blueGrey700 : PdfColors.grey200;

    final subjectEntries = st.subjectStats.values.toList()
      ..sort(
        (a, b) => FokusTextUtils.subjectSortRank(
          a.subject,
        ).compareTo(FokusTextUtils.subjectSortRank(b.subject)),
      );

    final double titleFontSize = config.bookTitle.trim().length > 26
        ? 24.0
        : (hasCustomImage ? 28.0 : 32.0);

    return pw.Container(
      width: PdfPageFormat.a4.width,
      height: PdfPageFormat.a4.height,
      color: bgColor,
      child: pw.Stack(
        children: [
          // Üst dekoratif geometrik şerit
          pw.Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: pw.Container(
              height: isMinimal ? 14 : 180,
              color: secondaryPdf,
            ),
          ),
          pw.Positioned(
            top: isMinimal ? 14 : 176,
            left: 0,
            right: 0,
            child: pw.Container(height: 5, color: accentPdf),
          ),
          // Çerçeve ve ana içerik
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(34, 30, 34, 26),
            child: pw.Container(
              padding: pw.EdgeInsets.fromLTRB(
                24,
                hasCustomImage ? 18 : 22,
                24,
                hasCustomImage ? 16 : 20,
              ),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                  color: isMinimal ? PdfColors.grey300 : accentPdf,
                  width: 1.4,
                ),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(14)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  // Üst Kurum & Logo Satırı
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      _buildEduknVectorLogo(
                        bold: bold,
                        textColor: titleColor,
                        barColor: isMinimal ? accentPdf : PdfColors.white,
                        cyanColor: accentPdf,
                        fontSize: 21,
                      ),
                      pw.Flexible(
                        child: pw.Container(
                          margin: const pw.EdgeInsets.only(left: 10),
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: pw.BoxDecoration(
                            color: isMinimal ? softPdf : primaryPdf,
                            borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(20),
                            ),
                            border: pw.Border.all(color: accentPdf, width: 0.9),
                          ),
                          child: pw.Text(
                            config.institutionDisplayName.toUpperCase(),
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip,
                            style: pw.TextStyle(
                              font: bold,
                              fontSize: 8.2,
                              color: titleColor,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: hasCustomImage ? 12 : 22),

                  // Kitap Rozeti & Ana Başlık
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    decoration: pw.BoxDecoration(
                      color: accentPdf,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(20),
                      ),
                    ),
                    child: pw.Text(
                      'AKILLI KAZANIM & SEVİYE UYUMLU SORU BANKASI',
                      style: pw.TextStyle(
                        font: bold,
                        fontSize: 8.2,
                        color: primaryPdf,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: hasCustomImage ? 10 : 12),
                  pw.Text(
                    config.bookTitle.toUpperCase(),
                    textAlign: pw.TextAlign.center,
                    maxLines: 2,
                    overflow: pw.TextOverflow.clip,
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: titleFontSize,
                      color: titleColor,
                      letterSpacing: 1.8,
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Text(
                    config.bookSubtitle,
                    textAlign: pw.TextAlign.center,
                    maxLines: 2,
                    overflow: pw.TextOverflow.clip,
                    style: pw.TextStyle(
                      font: reg,
                      fontSize: hasCustomImage ? 10 : 10.8,
                      color: subColor,
                    ),
                  ),

                  // Opsiyonel Özel Kapak Görseli (733pt sınırı için 78pt yükseklik)
                  if (hasCustomImage) ...[
                    pw.SizedBox(height: 10),
                    pw.Container(
                      height: 78,
                      width: 220,
                      padding: const pw.EdgeInsets.all(5),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(10),
                        ),
                        border: pw.Border.all(color: accentPdf, width: 1.2),
                      ),
                      child: pw.Image(
                        pw.MemoryImage(config.customCoverImageBytes!),
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                    pw.SizedBox(height: 10),
                  ] else
                    pw.SizedBox(height: 20),

                  // Öğrenci Kimlik Kartı
                  pw.Container(
                    width: double.infinity,
                    padding: pw.EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: hasCustomImage ? 12 : 15,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(12),
                      ),
                      border: pw.Border.all(color: accentPdf, width: 1.5),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          'BU KİTAP ÖZEL OLARAK HAZIRLANMIŞTIR',
                          style: pw.TextStyle(
                            font: bold,
                            fontSize: 7.8,
                            color: PdfColors.grey600,
                            letterSpacing: 1.1,
                          ),
                        ),
                        pw.SizedBox(height: 5),
                        pw.Text(
                          st.name,
                          textAlign: pw.TextAlign.center,
                          maxLines: 1,
                          overflow: pw.TextOverflow.clip,
                          style: pw.TextStyle(
                            font: bold,
                            fontSize: st.name.length > 26 ? 18 : 21,
                            color: primaryPdf,
                          ),
                        ),
                        pw.SizedBox(height: 7),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.center,
                          children: [
                            _coverInfoPill(
                              'SINIF / ŞUBE',
                              '${st.classLevel} / ${st.branch}',
                              primaryPdf,
                              softPdf,
                              bold,
                              reg,
                            ),
                            pw.SizedBox(width: 10),
                            if (st.studentNo.isNotEmpty) ...[
                              _coverInfoPill(
                                'ÖĞRENCİ NO',
                                st.studentNo,
                                primaryPdf,
                                softPdf,
                                bold,
                                reg,
                              ),
                              pw.SizedBox(width: 10),
                            ],
                            _coverInfoPill(
                              'SEVİYE GRUBU',
                              st.overallBand.shortLabel.toUpperCase(),
                              primaryPdf,
                              softPdf,
                              bold,
                              reg,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  pw.SizedBox(height: hasCustomImage ? 10 : 14),

                  // Kişisel Kazanım Hakimiyet Rozeti & Kitap Metrikleri
                  pw.Container(
                    width: double.infinity,
                    padding: pw.EdgeInsets.all(hasCustomImage ? 11 : 13),
                    decoration: pw.BoxDecoration(
                      color: isMinimal ? softPdf : secondaryPdf,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(12),
                      ),
                      border: pw.Border.all(
                        color: isMinimal ? PdfColors.grey300 : accentPdf,
                        width: 0.8,
                      ),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                      children: [
                        _coverMetricItem(
                          'GENEL HAKİMİYET',
                          '%${st.overallAbilityPercent.toStringAsFixed(0)}',
                          titleColor,
                          accentPdf,
                          bold,
                          reg,
                        ),
                        _coverMetricItem(
                          'KİŞİSEL SORU',
                          '${plan.totalQuestionCount} Soru',
                          titleColor,
                          accentPdf,
                          bold,
                          reg,
                        ),
                        _coverMetricItem(
                          'KİTAP HACMİ',
                          '${plan.totalPages} Sayfa',
                          titleColor,
                          accentPdf,
                          bold,
                          reg,
                        ),
                        _coverMetricItem(
                          'ODAK KAZANIM',
                          '${plan.tocEntries.length} Konu',
                          titleColor,
                          accentPdf,
                          bold,
                          reg,
                        ),
                      ],
                    ),
                  ),

                  pw.SizedBox(height: hasCustomImage ? 10 : 14),

                  // Branş Bazlı Başarı Özeti + Kapsamdaki Sınavlar
                  pw.Container(
                    width: double.infinity,
                    padding: pw.EdgeInsets.all(hasCustomImage ? 11 : 13),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(12),
                      ),
                      border: pw.Border.all(
                        color: PdfColors.grey300,
                        width: 0.8,
                      ),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'REFERANS ALINAN DENEME SINAVLARI (${st.participatedExamNames.length})',
                          style: pw.TextStyle(
                            font: bold,
                            fontSize: 8.2,
                            color: primaryPdf,
                            letterSpacing: 0.5,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          st.participatedExamNames.take(3).join('  •  '),
                          maxLines: 1,
                          overflow: pw.TextOverflow.clip,
                          style: pw.TextStyle(
                            font: reg,
                            fontSize: 8.2,
                            color: PdfColors.grey800,
                          ),
                        ),
                        if (subjectEntries.isNotEmpty) ...[
                          pw.SizedBox(height: 8),
                          pw.Divider(color: PdfColors.grey200, height: 1),
                          pw.SizedBox(height: 7),
                          pw.Wrap(
                            spacing: 8,
                            runSpacing: 5,
                            children: subjectEntries.take(6).map((s) {
                              return pw.Container(
                                width: 140,
                                padding: const pw.EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4.5,
                                ),
                                decoration: pw.BoxDecoration(
                                  color: softPdf,
                                  borderRadius: const pw.BorderRadius.all(
                                    pw.Radius.circular(6),
                                  ),
                                ),
                                child: pw.Row(
                                  mainAxisAlignment:
                                      pw.MainAxisAlignment.spaceBetween,
                                  children: [
                                    pw.Expanded(
                                      child: pw.Text(
                                        s.subject,
                                        maxLines: 1,
                                        style: pw.TextStyle(
                                          font: bold,
                                          fontSize: 7.4,
                                          color: primaryPdf,
                                        ),
                                      ),
                                    ),
                                    pw.Text(
                                      '%${s.masteryPercent.toStringAsFixed(0)}',
                                      style: pw.TextStyle(
                                        font: bold,
                                        fontSize: 7.8,
                                        color: s.masteryPercent < 45
                                            ? PdfColors.red700
                                            : (s.masteryPercent < 75
                                                  ? PdfColors.amber800
                                                  : PdfColors.green700),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),

                  pw.Spacer(),

                  // Alt Kurumsal İmza
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Fokus Kitap • Kişiye Özel Akıllı Soru Bankası Motoru',
                        style: pw.TextStyle(
                          font: reg,
                          fontSize: 8,
                          color: subColor,
                        ),
                      ),
                      pw.Text(
                        _formatDateTr(DateTime.now()),
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: 8.5,
                          color: titleColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _coverInfoPill(
    String label,
    String value,
    PdfColor primary,
    PdfColor soft,
    pw.Font bold,
    pw.Font reg,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: pw.BoxDecoration(
        color: soft,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              font: reg,
              fontSize: 6.5,
              color: PdfColors.grey600,
            ),
          ),
          pw.SizedBox(height: 1.5),
          pw.Text(
            value,
            style: pw.TextStyle(font: bold, fontSize: 8.5, color: primary),
          ),
        ],
      ),
    );
  }

  pw.Widget _coverMetricItem(
    String label,
    String value,
    PdfColor textColor,
    PdfColor accentColor,
    pw.Font bold,
    pw.Font reg,
  ) {
    return pw.Column(
      children: [
        pw.Text(
          value,
          style: pw.TextStyle(font: bold, fontSize: 15, color: textColor),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          label,
          style: pw.TextStyle(
            font: bold,
            fontSize: 6.8,
            color: accentColor,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  String _resolvePlaceholders(
    String template,
    StudentMasteryProfile student,
    PersonalizedBookConfig config,
  ) {
    final weakTop = student.weakestOutcomes
        .where((o) => o.masteryPercent < 75.0)
        .take(3)
        .map((o) => '${o.subject} (${o.outcome})')
        .toList();
    final weakStr = weakTop.isNotEmpty
        ? weakTop.join(', ')
        : 'öncelikli pekiştirme kazanımların';

    return template
        .replaceAll('{ogrenci}', student.name)
        .replaceAll('{sinif}', '${student.classLevel} / ${student.branch}')
        .replaceAll('{okul}', config.institutionDisplayName)
        .replaceAll('{tarih}', _formatDateTr(DateTime.now()))
        .replaceAll('{zayifKonular}', weakStr);
  }

  pw.Widget _buildManualPrefacePage({
    required StudentBookPlan plan,
    required PersonalizedBookConfig config,
    required int pageNo,
    required PdfColor primaryPdf,
    required PdfColor accentPdf,
    required PdfColor softPdf,
    required pw.Font reg,
    required pw.Font bold,
  }) {
    final st = plan.student;
    final resolvedTitle = _resolvePlaceholders(
      config.manualPrefaceTitle,
      st,
      config,
    );
    final resolvedBody = _resolvePlaceholders(
      config.manualPrefaceBody,
      st,
      config,
    );
    final resolvedAuthor = _resolvePlaceholders(
      config.manualPrefaceAuthor,
      st,
      config,
    );

    final int newlineCount = '\n'.allMatches(resolvedBody).length;
    final int effectiveLen = resolvedBody.length + (newlineCount * 48);
    final bool isVeryLong = resolvedBody.length > 1350 || effectiveLen > 1450;
    final bool isLong =
        !isVeryLong && (resolvedBody.length > 850 || effectiveLen > 920);

    final String safeBodyText = resolvedBody.length > 2300
        ? '${resolvedBody.substring(0, 2300).trimRight()}...'
        : resolvedBody;
    final double bodyFontSize = isVeryLong ? 9.2 : (isLong ? 9.9 : 11.0);
    final double bodyLineSpacing = isVeryLong ? 2.6 : (isLong ? 3.3 : 4.8);
    final int bodyMaxLines = isVeryLong ? 34 : (isLong ? 23 : 19);
    final double bodyBoxPadding = isVeryLong ? 13.0 : (isLong ? 15.0 : 18.0);
    final List<OutcomeMasteryStat> weakList = isVeryLong
        ? const []
        : st.weakestOutcomes.take(isLong ? 3 : 4).toList();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          decoration: pw.BoxDecoration(
            color: primaryPdf,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'ÖN SÖZ & ÇALIŞMA REHBERİ',
                      style: pw.TextStyle(
                        font: bold,
                        fontSize: 15,
                        color: PdfColors.white,
                        letterSpacing: 1.1,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      '${config.bookTitle} • Kişiye Özel Öğrenme Yol Haritası',
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                      style: pw.TextStyle(
                        font: reg,
                        fontSize: 8.5,
                        color: PdfColors.grey300,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: pw.BoxDecoration(
                  color: accentPdf,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(14),
                  ),
                ),
                child: pw.Text(
                  st.overallBand.label,
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 8.5,
                    color: primaryPdf,
                  ),
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: isVeryLong ? 14 : (isLong ? 18 : 24)),
        pw.Text(
          resolvedTitle,
          maxLines: 2,
          overflow: pw.TextOverflow.clip,
          style: pw.TextStyle(
            font: bold,
            fontSize: isVeryLong ? 14.5 : 16,
            color: primaryPdf,
          ),
        ),
        pw.SizedBox(height: isVeryLong ? 10 : 12),
        pw.Container(
          width: double.infinity,
          padding: pw.EdgeInsets.all(bodyBoxPadding),
          decoration: pw.BoxDecoration(
            color: softPdf,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
            border: pw.Border.all(color: primaryPdf, width: 1.2),
          ),
          child: pw.Text(
            safeBodyText,
            maxLines: bodyMaxLines,
            overflow: pw.TextOverflow.clip,
            style: pw.TextStyle(
              font: reg,
              fontSize: bodyFontSize,
              color: PdfColors.grey900,
              lineSpacing: bodyLineSpacing,
            ),
          ),
        ),
        if (weakList.isNotEmpty) ...[
          pw.SizedBox(height: isLong ? 14 : 22),
          pw.Text(
            'ÖNCELİKLİ GÜÇLENDİRME KAZANIMLARIN',
            style: pw.TextStyle(
              font: bold,
              fontSize: 10.2,
              color: primaryPdf,
              letterSpacing: 0.7,
            ),
          ),
          pw.SizedBox(height: 8),
          for (final item in weakList)
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 6),
              padding: pw.EdgeInsets.symmetric(
                horizontal: 12,
                vertical: isLong ? 6.5 : 8,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
              ),
              child: pw.Row(
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2.5,
                    ),
                    decoration: pw.BoxDecoration(
                      color: primaryPdf,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(4),
                      ),
                    ),
                    child: pw.Text(
                      item.subject.toUpperCase(),
                      style: pw.TextStyle(
                        font: bold,
                        fontSize: 7.5,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Text(
                      item.outcome,
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                      style: pw.TextStyle(
                        font: reg,
                        fontSize: 8.8,
                        color: PdfColors.grey800,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Text(
                    'Hakimiyet: %${item.masteryPercent.toStringAsFixed(0)}',
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 8.4,
                      color: item.masteryPercent < 45
                          ? PdfColors.red700
                          : PdfColors.amber800,
                    ),
                  ),
                ],
              ),
            ),
        ],
        pw.Spacer(),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(width: 120, height: 1.2, color: primaryPdf),
              pw.SizedBox(height: 5),
              pw.Text(
                resolvedAuthor,
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 10.2,
                  color: primaryPdf,
                ),
              ),
              pw.Text(
                config.institutionDisplayName,
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
                style: pw.TextStyle(
                  font: reg,
                  fontSize: 8.8,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        _buildBookFooter(
          config: config,
          pageNo: pageNo,
          totalPages: plan.totalPages,
          rightLabel: 'ÖN SÖZ',
          primaryPdf: primaryPdf,
          reg: reg,
          bold: bold,
        ),
      ],
    );
  }

  pw.Widget _buildTocPage({
    required StudentBookPlan plan,
    required PersonalizedBookConfig config,
    required List<TocEntryItem> entries,
    required bool isContinuation,
    required bool showAnswerKeyRow,
    required int pageNo,
    required PdfColor primaryPdf,
    required PdfColor accentPdf,
    required PdfColor softPdf,
    required pw.Font reg,
    required pw.Font bold,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: pw.BoxDecoration(
            color: primaryPdf,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                isContinuation ? 'İÇİNDEKİLER (DEVAM)' : 'İÇİNDEKİLER',
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 15,
                  color: PdfColors.white,
                  letterSpacing: 1.2,
                ),
              ),
              pw.Text(
                '${plan.student.name}  •  ${plan.totalQuestionCount} Soru',
                style: pw.TextStyle(
                  font: reg,
                  fontSize: 8.5,
                  color: PdfColors.grey200,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 10),
        if (plan.skippedMasteredOutcomeCount > 0 && !isContinuation)
          pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(bottom: 8),
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: pw.BoxDecoration(
              color: softPdf,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Text(
              'Not: Tam hakimiyet sağladığın ${plan.skippedMasteredOutcomeCount} kazanımdan soru eklenmeyerek sayfa bütçen öncelikli konularına aktarılmıştır.',
              style: pw.TextStyle(font: reg, fontSize: 7.8, color: primaryPdf),
            ),
          ),
        for (final item in entries) ...[
          if (item.isSubjectFirstEntry)
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(top: 5, bottom: 3),
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 3,
              ),
              decoration: pw.BoxDecoration(
                color: softPdf,
                border: pw.Border(
                  left: pw.BorderSide(color: primaryPdf, width: 3),
                ),
              ),
              child: pw.Text(
                item.subject.toUpperCase(),
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 8.5,
                  color: primaryPdf,
                ),
              ),
            ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(
              vertical: 2.2,
              horizontal: 4,
            ),
            child: pw.Row(
              children: [
                pw.Container(
                  width: 4,
                  height: 4,
                  decoration: pw.BoxDecoration(
                    color: primaryPdf,
                    shape: pw.BoxShape.circle,
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  flex: 6,
                  child: pw.Text(
                    item.outcome,
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    style: pw.TextStyle(
                      font: reg,
                      fontSize: 8.2,
                      color: PdfColors.grey800,
                    ),
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    '. . . . . . . . . . . . . . . . . . . . . .',
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    style: pw.TextStyle(
                      font: reg,
                      fontSize: 7,
                      color: PdfColors.grey400,
                    ),
                  ),
                ),
                pw.SizedBox(width: 6),
                if (item.studentMasteryPercent != null)
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1.5,
                    ),
                    decoration: pw.BoxDecoration(
                      color: item.studentMasteryPercent! < 45
                          ? PdfColors.red50
                          : (item.studentMasteryPercent! < 75
                                ? PdfColors.amber50
                                : PdfColors.green50),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(4),
                      ),
                    ),
                    child: pw.Text(
                      '%${item.studentMasteryPercent!.toStringAsFixed(0)}',
                      style: pw.TextStyle(
                        font: bold,
                        fontSize: 7.2,
                        color: item.studentMasteryPercent! < 45
                            ? PdfColors.red800
                            : (item.studentMasteryPercent! < 75
                                  ? PdfColors.amber900
                                  : PdfColors.green800),
                      ),
                    ),
                  ),
                pw.SizedBox(width: 5),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    '${item.questionCount} Soru',
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 7.2,
                      color: PdfColors.grey700,
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Container(
                  width: 24,
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    '${item.startPageNumber}',
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 8.8,
                      color: primaryPdf,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (showAnswerKeyRow && plan.answerKeyStartPage != null) ...[
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: pw.BoxDecoration(
              color: softPdf,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: primaryPdf, width: 0.7),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'CEVAP ANAHTARI',
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 8.8,
                    color: primaryPdf,
                  ),
                ),
                pw.Text(
                  '${plan.answerKeyStartPage}',
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 9.2,
                    color: primaryPdf,
                  ),
                ),
              ],
            ),
          ),
        ],
        pw.Spacer(),
        _buildBookFooter(
          config: config,
          pageNo: pageNo,
          totalPages: plan.totalPages,
          rightLabel: 'İÇİNDEKİLER',
          primaryPdf: primaryPdf,
          reg: reg,
          bold: bold,
        ),
      ],
    );
  }

  pw.Widget _buildPackedQuestionPageWidget({
    required StudentBookPlan plan,
    required PersonalizedBookConfig config,
    required PackedQuestionPage packedPage,
    required int pageNo,
    required int studyNoteIndex,
    required PdfColor primaryPdf,
    required PdfColor accentPdf,
    required PdfColor softPdf,
    required pw.Font reg,
    required pw.Font bold,
  }) {
    final List<pw.Widget> bodyChildren = [];

    // Sayfa dizgisi: sayfa doluysa kalan boşluk, içinde 2+ soru olan sütun bloklarına
    // dağıtılır → sayfanın ilk sorusu üst çizgide, son sorusu alt çizgide biter ve
    // sorular arasındaki boşluk eşit olur. (Yarım kalan son sayfalar gerilmez.)
    final Map<int, double> extraHeightByBlock = {};
    double interBlockExtraGap = 0.0;
    {
      double used = 0.0;
      for (int bIdx = 0; bIdx < packedPage.blocks.length; bIdx++) {
        final b = packedPage.blocks[bIdx];
        if (bIdx > 0) used += 6.0;
        if (b.kind == QuestionBlockKind.studyNotesPad) {
          used = _bodyMaxHeight;
          break;
        }
        if (b.showSubjectBanner) used += 42.0;
        if (b.showOutcomeRibbon) used += 25.0;
        used += b.allocatedHeight;
      }
      final double leftover = _bodyMaxHeight - used;
      if (leftover > 4.0 && leftover < _bodyMaxHeight * 0.58) {
        final List<int> stretchable = [
          for (int bIdx = 0; bIdx < packedPage.blocks.length; bIdx++)
            if (packedPage.blocks[bIdx].kind == QuestionBlockKind.twoColumnSection &&
                (packedPage.blocks[bIdx].leftColumn.length >= 2 ||
                    packedPage.blocks[bIdx].rightColumn.length >= 2))
              bIdx,
        ];
        if (stretchable.isNotEmpty) {
          final double usable = leftover - 4.0;
          final double totalAlloc = stretchable.fold<double>(
            0.0,
            (s, idx) => s + packedPage.blocks[idx].allocatedHeight,
          );
          for (final idx in stretchable) {
            final share = totalAlloc > 0
                ? packedPage.blocks[idx].allocatedHeight / totalAlloc
                : 1.0 / stretchable.length;
            extraHeightByBlock[idx] = usable * share;
          }
        } else if (packedPage.blocks.length >= 2) {
          // Üstte [5 | 6], altta 7. soru (geniş) veya aynı sayfada 2 geniş soru (14 ve 15)
          // olduğunda alttaki soruyu sayfanın alt sınırına yasla!
          interBlockExtraGap = (leftover - 4.0) / (packedPage.blocks.length - 1);
        }
      }
    }
    for (int bIdx = 0; bIdx < packedPage.blocks.length; bIdx++) {
      final block = packedPage.blocks[bIdx];
      if (bIdx > 0) {
        bodyChildren.add(pw.SizedBox(height: 6.0 + interBlockExtraGap));
      }

      if (block.kind == QuestionBlockKind.studyNotesPad) {
        bodyChildren.add(
          _buildStudyNotesPadWidget(
            plan: plan,
            primaryPdf: primaryPdf,
            softPdf: softPdf,
            reg: reg,
            bold: bold,
          ),
        );
        continue;
      }

      if (block.showSubjectBanner) {
        final subStat = plan.student.subjectStats[block.subject];
        bodyChildren.add(
          pw.Container(
            width: _fullPageWidth,
            height: 36,
            margin: const pw.EdgeInsets.only(bottom: 6),
            padding: const pw.EdgeInsets.symmetric(horizontal: 12),
            decoration: pw.BoxDecoration(
              color: primaryPdf,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${block.subject.toUpperCase()} BÖLÜMÜ',
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 12,
                    color: PdfColors.white,
                    letterSpacing: 0.8,
                  ),
                ),
                if (subStat != null)
                  pw.Text(
                    'Deneme Hakimiyeti: %${subStat.masteryPercent.toStringAsFixed(0)}  •  Net: ${subStat.net.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 8.2,
                      color: accentPdf,
                    ),
                  ),
              ],
            ),
          ),
        );
      }

      if (block.showOutcomeRibbon) {
        bodyChildren.add(
          pw.Container(
            width: _fullPageWidth,
            height: 20,
            margin: const pw.EdgeInsets.only(bottom: 5),
            padding: const pw.EdgeInsets.symmetric(horizontal: 8),
            decoration: pw.BoxDecoration(
              color: softPdf,
              border: pw.Border(
                left: pw.BorderSide(color: primaryPdf, width: 3),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'KAZANIM: ${block.outcome}',
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 7.6,
                      color: primaryPdf,
                    ),
                  ),
                ),
                if (block.studentOutcomeMastery != null) ...[
                  pw.SizedBox(width: 8),
                  pw.Text(
                    'Öğrenci Başarısı: %${block.studentOutcomeMastery!.toStringAsFixed(0)}',
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 7.4,
                      color: block.studentOutcomeMastery! < 45
                          ? PdfColors.red700
                          : (block.studentOutcomeMastery! < 75
                                ? PdfColors.amber900
                                : PdfColors.green700),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }

      if (block.kind == QuestionBlockKind.twoColumnSection) {
        bodyChildren.add(
          _buildTwoColBlockWidget(
            block: block,
            extraHeight: extraHeightByBlock[bIdx] ?? 0.0,
            primaryPdf: primaryPdf,
            softPdf: softPdf,
            reg: reg,
            bold: bold,
          ),
        );
      } else if (block.kind == QuestionBlockKind.wideQuestion &&
          block.fullWidthQuestions.isNotEmpty) {
        bodyChildren.add(
          _buildWideQuestionWidget(
            pq: block.fullWidthQuestions.first,
            maxBoxHeight: block.allocatedHeight,
            primaryPdf: primaryPdf,
            softPdf: softPdf,
            bold: bold,
          ),
        );
      } else if (block.kind == QuestionBlockKind.sharedPassageGroup &&
          block.fullWidthQuestions.isNotEmpty) {
        bodyChildren.add(
          _buildPassageGroupWidget(
            group: block.fullWidthQuestions,
            maxBoxHeight: block.allocatedHeight,
            primaryPdf: primaryPdf,
            softPdf: softPdf,
            reg: reg,
            bold: bold,
          ),
        );
      }
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Üst Başlık Çubuğu (26pt + 6pt margin)
        pw.Container(
          width: _fullPageWidth,
          height: 24,
          margin: const pw.EdgeInsets.only(bottom: 6),
          padding: const pw.EdgeInsets.only(bottom: 4),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.7),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                '${config.bookTitle.toUpperCase()}  •  ${packedPage.primarySubject.toUpperCase()}',
                style: pw.TextStyle(font: bold, fontSize: 8, color: primaryPdf),
              ),
              pw.Text(
                '${plan.student.name} (${plan.student.classLevel} / ${plan.student.branch})',
                style: pw.TextStyle(
                  font: reg,
                  fontSize: 7.8,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ),
        ...bodyChildren,
        pw.Spacer(),
        _buildBookFooter(
          config: config,
          pageNo: pageNo,
          totalPages: plan.totalPages,
          rightLabel: packedPage.primarySubject.toUpperCase(),
          primaryPdf: primaryPdf,
          reg: reg,
          bold: bold,
        ),
      ],
    );
  }

  pw.Widget _buildTwoColBlockWidget({
    required PackedPageBlock block,
    double extraHeight = 0.0,
    required PdfColor primaryPdf,
    required PdfColor softPdf,
    required pw.Font reg,
    required pw.Font bold,
  }) {
    final double baseH = block.allocatedHeight.clamp(68.0, 680.0);
    final double secH = (baseH + extraHeight).clamp(68.0, _bodyMaxHeight);
    // Görsel boyutları blok yüksekliğine göre değil, asıl ayrılan yüksekliğe göre hesaplanır;
    // eklenen boşluk yalnızca sorular arasına dağıtılır (görseller büyüyüp taşmaz).
    final double sizingH = baseH;

    pw.Widget buildCol(List<PlacedBookQuestion> col) {
      if (col.isEmpty) return pw.SizedBox(width: _colWidth);
      final double idealH = _sumColumnHeight(col);
      final double scale = (idealH > sizingH && idealH > 0)
          ? (sizingH / idealH).clamp(0.84, 1.0)
          : 1.0;
      final double maxEachH = col.length == 1
          ? math.max(36.0, sizingH - 24.0)
          : math.max(
              32.0,
              ((sizingH - (col.length - 1) * 20.0) / col.length) - 24.0,
            );

      final children = col.map((pq) {
        final bytes = pq.item.cachedImageBytes!;
        final ar = pq.item.cachedAspectRatio ?? 0.62;
        final renderW = (_colWidth * scale).clamp(_colWidth * 0.84, _colWidth);
        final naturalImgH = (renderW * ar).clamp(44.0, 500.0);
        final double cappedImgH = math.min(naturalImgH, maxEachH);

        return pw.Container(
          width: _colWidth,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildSingleQuestionHeader(
                pq: pq,
                width: _colWidth,
                isNarrow: true,
                primaryPdf: primaryPdf,
                softPdf: softPdf,
                bold: bold,
              ),
              pw.SizedBox(height: 4),
              pw.Container(
                width: _colWidth,
                height: cappedImgH,
                alignment: pw.Alignment.topLeft,
                child: pw.Image(
                  pw.MemoryImage(bytes),
                  width: renderW,
                  height: cappedImgH,
                  fit: pw.BoxFit.contain,
                ),
              ),
            ],
          ),
        );
      }).toList();

      if (children.length >= 2) {
        return pw.Container(
          width: _colWidth,
          height: secH,
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: children,
          ),
        );
      }
      return pw.Container(
        width: _colWidth,
        height: secH,
        alignment: pw.Alignment.topLeft,
        child: children.first,
      );
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        buildCol(block.leftColumn),
        pw.Container(
          width: _centerCorridorWidth,
          height: secH,
          alignment: pw.Alignment.topCenter,
          child: pw.Container(
            width: 0.85,
            height: secH,
            color: PdfColors.grey300,
          ),
        ),
        buildCol(block.rightColumn),
      ],
    );
  }

  pw.Widget _buildWideQuestionWidget({
    required PlacedBookQuestion pq,
    required double maxBoxHeight,
    required PdfColor primaryPdf,
    required PdfColor softPdf,
    required pw.Font bold,
  }) {
    final bytes = pq.item.cachedImageBytes!;
    final ar = pq.item.cachedAspectRatio ?? 0.50;
    final targetW = _fullPageWidth - 4.0;
    final double maxAllowedImgH = math.max(36.0, maxBoxHeight - 24.0);
    final double imgH = math.min(
      (targetW * ar).clamp(44.0, 560.0),
      maxAllowedImgH,
    );
    return pw.Container(
      width: _fullPageWidth,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _buildSingleQuestionHeader(
            pq: pq,
            width: _fullPageWidth,
            isNarrow: false,
            primaryPdf: primaryPdf,
            softPdf: softPdf,
            bold: bold,
          ),
          pw.SizedBox(height: 4),
          pw.Container(
            width: targetW,
            height: imgH,
            alignment: pw.Alignment.topCenter,
            child: pw.Image(
              pw.MemoryImage(bytes),
              width: targetW,
              height: imgH,
              fit: pw.BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPassageGroupWidget({
    required List<PlacedBookQuestion> group,
    required double maxBoxHeight,
    required PdfColor primaryPdf,
    required PdfColor softPdf,
    required pw.Font reg,
    required pw.Font bold,
  }) {
    final pBytes = group.first.item.cachedPassageBytes!;
    final seqs = group.map((g) => g.sequenceNoInSubject).toList();
    final String rangeLabel = seqs.length == 1
        ? '${seqs.first}. soruyu aşağıdaki ortak metne göre cevaplayınız.'
        : '${seqs.first} - ${seqs.last}. soruları aşağıdaki ortak metne göre cevaplayınız.';

    const double innerW = _fullPageWidth - 12.0;
    final double pAr = group.first.item.cachedPassageAspectRatio ?? 0.38;
    final double maxPassageH = math.max(
      44.0,
      math.min(170.0, maxBoxHeight * 0.42),
    );
    final double pH = math.min((innerW * pAr).clamp(44.0, 170.0), maxPassageH);

    final bool twoCol =
        group.length >= 2 && group.every((g) => !_isEffectivelyWide(g.item));
    final double remForQuestions = math.max(72.0, maxBoxHeight - pH - 36.0);
    final double perWideImgCap = math.max(
      44.0,
      (remForQuestions / group.length) - 24.0,
    );

    return pw.Container(
      width: _fullPageWidth,
      padding: const pw.EdgeInsets.only(left: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(left: pw.BorderSide(color: primaryPdf, width: 3)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: innerW,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: pw.BoxDecoration(
              color: softPdf,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Row(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: pw.BoxDecoration(
                    color: primaryPdf,
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(3),
                    ),
                  ),
                  child: pw.Text(
                    'ORTAK METİN',
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 6.8,
                      color: PdfColors.white,
                    ),
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.Text(
                    rangeLabel,
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 8.2,
                      color: primaryPdf,
                    ),
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Container(
            width: innerW,
            height: pH,
            alignment: pw.Alignment.center,
            child: pw.Image(
              pw.MemoryImage(pBytes),
              width: innerW - 8,
              height: pH,
              fit: pw.BoxFit.contain,
            ),
          ),
          pw.SizedBox(height: 6),
          if (twoCol)
            _buildTwoColBlockWidget(
              block: PackedPageBlock(
                kind: QuestionBlockKind.twoColumnSection,
                subject: group.first.subject,
                outcome: group.first.outcome,
                leftColumn: group.sublist(0, (group.length / 2).ceil()),
                rightColumn: group.sublist((group.length / 2).ceil()),
                allocatedHeight: remForQuestions,
              ),
              primaryPdf: primaryPdf,
              softPdf: softPdf,
              reg: reg,
              bold: bold,
            )
          else
            for (final q in group)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: _buildWideQuestionWidget(
                  pq: q,
                  maxBoxHeight: perWideImgCap + 20.0,
                  primaryPdf: primaryPdf,
                  softPdf: softPdf,
                  bold: bold,
                ),
              ),
        ],
      ),
    );
  }

  pw.Widget _buildSingleQuestionHeader({
    required PlacedBookQuestion pq,
    required double width,
    required bool isNarrow,
    required PdfColor primaryPdf,
    required PdfColor softPdf,
    required pw.Font bold,
  }) {
    final diff = pq.item.difficulty;
    // Hata Kitapçığı / Soru Havuzu ile aynı 5 aşamalı ölçek
    final String diffBadge = DifficultyScale.labelOf(diff);

    return pw.Container(
      width: width,
      height: 19,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6),
      decoration: pw.BoxDecoration(
        color: softPdf,
        border: pw.Border(left: pw.BorderSide(color: primaryPdf, width: 2.5)),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 1.5,
            ),
            decoration: pw.BoxDecoration(
              color: primaryPdf,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
            ),
            child: pw.Text(
              '${pq.sequenceNoInSubject}. SORU',
              style: pw.TextStyle(
                font: bold,
                fontSize: isNarrow ? 7.0 : 7.8,
                color: PdfColors.white,
              ),
            ),
          ),
          pw.SizedBox(width: 5),
          pw.Expanded(
            child: pw.Text(
              pq.outcome,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: pw.TextStyle(
                font: bold,
                fontSize: isNarrow ? 6.3 : 7.0,
                color: primaryPdf,
              ),
            ),
          ),
          pw.SizedBox(width: 4),
          pw.Text(
            diffBadge,
            style: pw.TextStyle(
              font: bold,
              fontSize: 6.2,
              color: PdfColors.grey600,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildStudyNotesPadWidget({
    required StudentBookPlan plan,
    required PdfColor primaryPdf,
    required PdfColor softPdf,
    required pw.Font reg,
    required pw.Font bold,
  }) {
    final weakTop = plan.student.weakestOutcomes.take(5).toList();
    return pw.Container(
      width: _fullPageWidth,
      height: _bodyMaxHeight - 8,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.9),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: pw.BoxDecoration(
              color: softPdf,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: primaryPdf, width: 1.0),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'ÖĞRENCİ ÇÖZÜM & KAZANIM TEKRAR NOT ALANI',
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 10,
                    color: primaryPdf,
                  ),
                ),
                pw.Text(
                  'Kişisel Çalışma Sayfası',
                  style: pw.TextStyle(
                    font: reg,
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),
          if (weakTop.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              'Kazanım Kontrol Listesi (Tekrar ettiğin konuları işaretle):',
              style: pw.TextStyle(
                font: bold,
                fontSize: 8.2,
                color: PdfColors.grey800,
              ),
            ),
            pw.SizedBox(height: 6),
            for (final w in weakTop)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Row(
                  children: [
                    pw.Container(
                      width: 9,
                      height: 9,
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: primaryPdf, width: 1),
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(2),
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 7),
                    pw.Expanded(
                      child: pw.Text(
                        '${w.subject} — ${w.outcome} (Mevcut Başarı: %${w.masteryPercent.toStringAsFixed(0)})',
                        maxLines: 1,
                        style: pw.TextStyle(
                          font: reg,
                          fontSize: 7.8,
                          color: PdfColors.grey800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          pw.SizedBox(height: 12),
          pw.Expanded(
            child: pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey50,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.grey200, width: 0.7),
              ),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                children: List.generate(
                  19,
                  (_) => pw.Divider(
                    color: PdfColors.grey300,
                    height: 1,
                    thickness: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildAnswerKeyPage({
    required StudentBookPlan plan,
    required PersonalizedBookConfig config,
    required List<AnswerKeyBlockPlan> blocksOnPage,
    required bool isContinuation,
    required int pageNo,
    required PdfColor primaryPdf,
    required PdfColor softPdf,
    required pw.Font reg,
    required pw.Font bold,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: pw.BoxDecoration(
            color: primaryPdf,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                isContinuation ? 'CEVAP ANAHTARI (DEVAM)' : 'CEVAP ANAHTARI',
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 14,
                  color: PdfColors.white,
                  letterSpacing: 1.0,
                ),
              ),
              pw.Flexible(
                child: pw.Text(
                  plan.student.name,
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                  style: pw.TextStyle(
                    font: reg,
                    fontSize: 8.5,
                    color: PdfColors.grey200,
                  ),
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 10),
        for (final block in blocksOnPage)
          if (block.questions.isNotEmpty)
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(bottom: 8),
              padding: const pw.EdgeInsets.all(9),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.grey300, width: 0.7),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2.5,
                    ),
                    decoration: pw.BoxDecoration(
                      color: primaryPdf,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(4),
                      ),
                    ),
                    child: pw.Text(
                      block.titleLabel,
                      style: pw.TextStyle(
                        font: bold,
                        fontSize: 8.2,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: block.questions.map((pq) {
                      return pw.Container(
                        width: 44,
                        padding: const pw.EdgeInsets.symmetric(vertical: 2.2),
                        decoration: pw.BoxDecoration(
                          color: softPdf,
                          borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(3),
                          ),
                        ),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.center,
                          children: [
                            pw.Text(
                              '${pq.sequenceNoInSubject}-',
                              style: pw.TextStyle(
                                font: reg,
                                fontSize: 7.4,
                                color: PdfColors.grey700,
                              ),
                            ),
                            pw.Text(
                              pq.item.correctAnswer,
                              style: pw.TextStyle(
                                font: bold,
                                fontSize: 8.6,
                                color: primaryPdf,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
        pw.Spacer(),
        _buildBookFooter(
          config: config,
          pageNo: pageNo,
          totalPages: plan.totalPages,
          rightLabel: 'CEVAP ANAHTARI',
          primaryPdf: primaryPdf,
          reg: reg,
          bold: bold,
        ),
      ],
    );
  }

  pw.Widget _buildBookFooter({
    required PersonalizedBookConfig config,
    required int pageNo,
    required int totalPages,
    required String rightLabel,
    required PdfColor primaryPdf,
    required pw.Font reg,
    required pw.Font bold,
  }) {
    return pw.Container(
      height: 20,
      padding: const pw.EdgeInsets.only(top: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey300, width: 0.6),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '${config.institutionDisplayName} • Fokus Kitap',
            style: pw.TextStyle(
              font: reg,
              fontSize: 7.2,
              color: PdfColors.grey600,
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 1.5,
            ),
            decoration: pw.BoxDecoration(
              color: primaryPdf,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Text(
              '$pageNo / $totalPages',
              style: pw.TextStyle(
                font: bold,
                fontSize: 7.5,
                color: PdfColors.white,
              ),
            ),
          ),
          pw.Text(
            rightLabel,
            style: pw.TextStyle(font: bold, fontSize: 7.2, color: primaryPdf),
          ),
        ],
      ),
    );
  }

  static String _formatDateTr(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d.$m.${dt.year}';
  }
}

class _AggregatedOutcomeMeta {
  final String key;
  final String subject;
  final String outcome;
  final Set<String> uniqueExamSlots = {};
  int totalStudentAsked = 0;
  int totalStudentCorrect = 0;

  _AggregatedOutcomeMeta({
    required this.key,
    required this.subject,
    required this.outcome,
  });
}

class _ScoredQuestion {
  final PoolQuestionItem item;
  final double score;

  const _ScoredQuestion({required this.item, required this.score});
}

class _OutcomeCandidateBucket {
  final ExamOutcomeTopicRule rule;
  final int minQuestions;
  final double? studentMastery;
  final double effectiveMastery;
  final double needWeight;
  final List<PoolQuestionItem> candidates;
  int cursor = 0;

  _OutcomeCandidateBucket({
    required this.rule,
    required this.minQuestions,
    required this.studentMastery,
    required this.effectiveMastery,
    required this.needWeight,
    required this.candidates,
  });

  bool hasMore(Set<String> usedKeys) {
    for (int idx = cursor; idx < candidates.length; idx++) {
      if (!usedKeys.contains(candidates[idx].poolKey)) return true;
    }
    return false;
  }
}

class _OutcomeSlice {
  final String subject;
  final String outcome;
  final double? mastery;
  final List<PlacedBookQuestion> questions;

  const _OutcomeSlice({
    required this.subject,
    required this.outcome,
    required this.mastery,
    required this.questions,
  });
}
