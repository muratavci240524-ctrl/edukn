import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../models/assessment/lgs_data.dart';
import '../../../../models/assessment/trial_exam_model.dart';
import '../../../../services/pdf_service.dart';
import '../../../../services/term_service.dart';
import '../../assessment/evaluation_models.dart';

class AcademicClassInfo {
  final String id;
  final String name;
  final String classLevel;
  final String schoolTypeId;

  const AcademicClassInfo({
    required this.id,
    required this.name,
    required this.classLevel,
    required this.schoolTypeId,
  });
}

class AcademicStudentInfo {
  final String id;
  final String studentNo;
  final String tcNo;
  final String name;
  final String classId;
  final String className;
  final String classLevel;

  const AcademicStudentInfo({
    required this.id,
    required this.studentNo,
    required this.tcNo,
    required this.name,
    required this.classId,
    required this.className,
    required this.classLevel,
  });
}

class ParsedTrialExam {
  final TrialExam exam;
  final List<StudentResult> results;

  const ParsedTrialExam({required this.exam, required this.results});

  String get id => exam.id;
  String get name => exam.name;
  DateTime get date => exam.date;
  String get classLevel => exam.classLevel;

  /// Sınavın gerçek toplam soru kapasitesi (cevap anahtarı ve katılımcı verisinden hesaplanır).
  /// Örn: Fen Bilimleri Tarama = 20, LGS Genel Deneme = 90, Kurumsal Ara Sınıf = 75, TYT = 120.
  int get totalQuestionCapacity {
    int fromKey = 0;
    if (exam.answerKeys.isNotEmpty) {
      for (final subjMap in exam.answerKeys.values) {
        int sum = 0;
        for (final keyStr in subjMap.values) {
          sum += keyStr.trim().length;
        }
        if (sum > fromKey) fromKey = sum;
      }
    }
    int fromResults = 0;
    for (final r in results) {
      final q = r.total.correct + r.total.wrong + r.total.empty;
      if (q > fromResults) fromResults = q;
    }
    return math.max(fromKey, fromResults);
  }

  /// Sınavda aktif soru barındıran farklı ders/branş sayısı.
  int get activeSubjectCount {
    final subjSet = <String>{};
    for (final subjMap in exam.answerKeys.values) {
      for (final entry in subjMap.entries) {
        if (entry.value.trim().isNotEmpty) {
          subjSet.add(AcademicTrackingDataService.normTr(entry.key));
        }
      }
    }
    for (final r in results.take(35)) {
      for (final entry in r.subjects.entries) {
        final st = entry.value;
        if (st.correct + st.wrong + st.empty > 0 || st.net != 0) {
          subjSet.add(AcademicTrackingDataService.normTr(entry.key));
        }
      }
    }
    return subjSet.length;
  }

  /// Kapsamlı çok branşlı Genel Deneme mi (true), yoksa tek/az branşlı veya düşük soru sayılı
  /// Tarama / Branş Denemesi mi (false, örn. 20 soruluk Fen Bilimleri Tarama Sınavı)?
  bool get isFullTrialExam {
    final cap = totalQuestionCapacity;
    final subCount = activeSubjectCount;
    final lowerName = AcademicTrackingDataService.normTr(
      '${exam.name} ${exam.examTypeName}',
    );
    final hasBranchOrScreeningTag =
        lowerName.contains('tarama') ||
        lowerName.contains('brans') ||
        lowerName.contains('konu sinav') ||
        lowerName.contains('quiz') ||
        lowerName.contains('yaprak');

    if (cap > 0 && cap < 45) return false;
    if (subCount > 0 && subCount <= 2 && cap < 75) return false;
    if (hasBranchOrScreeningTag && cap < 70) return false;
    return true;
  }
}

class ParsedClassExam {
  final String id;
  final String examName;
  final String lessonName;
  final String classId;
  final String className;
  final DateTime date;
  final Map<String, double> grades;

  const ParsedClassExam({
    required this.id,
    required this.examName,
    required this.lessonName,
    required this.classId,
    required this.className,
    required this.date,
    required this.grades,
  });

  double get average {
    if (grades.isEmpty) return 0;
    final sum = grades.values.fold<double>(0, (a, b) => a + b);
    return sum / grades.length;
  }
}

class StudentAttendanceSummary {
  final String studentId;
  int presentLessons = 0;
  int absentLessons = 0;
  int excusedLessons = 0;
  int lateLessons = 0;
  int firstHourLateCount = 0;
  final Set<String> absentDateKeys = {};
  final Set<String> excusedDateKeys = {};
  final Map<String, int> absentLessonsPerDate = {};
  final Map<String, int> excusedLessonsPerDate = {};

  StudentAttendanceSummary(this.studentId);

  /// MEB mantığına uygun yaklaşık gün hesabı:
  /// Bir günde >= 4 ders yoklama "absent" ise tam gün (1.0), 1-3 ders ise yarım gün (0.5) sayılır.
  double get estimatedAbsentDays {
    double days = 0;
    absentLessonsPerDate.forEach((_, count) {
      if (count >= 4) {
        days += 1.0;
      } else if (count > 0) {
        days += 0.5;
      }
    });
    return days;
  }

  double get estimatedExcusedDays {
    double days = 0;
    excusedLessonsPerDate.forEach((_, count) {
      if (count >= 4) {
        days += 1.0;
      } else if (count > 0) {
        days += 0.5;
      }
    });
    return days;
  }

  double get totalEstimatedDays => estimatedAbsentDays + estimatedExcusedDays;
}

class StudentHomeworkSummary {
  final String studentId;
  int assignedCount = 0;
  int doneCount = 0;
  int incompleteCount = 0;
  int missingCount = 0;
  int pendingCount = 0;

  StudentHomeworkSummary(this.studentId);

  int get evaluatedCount => doneCount + incompleteCount + missingCount;

  double get completionRate {
    if (evaluatedCount == 0) return 100.0;
    return ((doneCount + (incompleteCount * 0.5)) / evaluatedCount) * 100.0;
  }
}

class ClassHomeworkSummary {
  final String classId;
  final String className;
  final int homeworkCount;
  final int doneCount;
  final int incompleteCount;
  final int missingCount;

  const ClassHomeworkSummary({
    required this.classId,
    required this.className,
    required this.homeworkCount,
    required this.doneCount,
    required this.incompleteCount,
    required this.missingCount,
  });

  int get totalEvaluated => doneCount + incompleteCount + missingCount;

  double get completionRate {
    if (totalEvaluated == 0) return 100.0;
    return ((doneCount + incompleteCount * 0.5) / totalEvaluated) * 100.0;
  }
}

class SubjectHomeworkSummary {
  final String subjectName;
  final int homeworkCount;
  final int doneCount;
  final int incompleteCount;
  final int missingCount;

  const SubjectHomeworkSummary({
    required this.subjectName,
    required this.homeworkCount,
    required this.doneCount,
    required this.incompleteCount,
    required this.missingCount,
  });

  int get totalEvaluated => doneCount + incompleteCount + missingCount;

  double get completionRate {
    if (totalEvaluated == 0) return 100.0;
    return ((doneCount + incompleteCount * 0.5) / totalEvaluated) * 100.0;
  }
}

class EtutAnalyticsSummary {
  final int totalRequests;
  final int completedCount;
  final int pendingCount;
  final Map<String, int> bySubject;
  final Map<String, int> byTeacher;

  const EtutAnalyticsSummary({
    this.totalRequests = 0,
    this.completedCount = 0,
    this.pendingCount = 0,
    this.bySubject = const {},
    this.byTeacher = const {},
  });

  double get attendanceRate =>
      totalRequests == 0 ? 0.0 : (completedCount / totalRequests) * 100.0;
}

class StudentTrialPoint {
  final String examId;
  final String examName;
  final DateTime date;
  final double score;
  final double totalNet;
  final int totalCorrect;
  final int totalWrong;
  final int totalEmpty;
  final int examQuestionCount;
  final bool isFullTrial;
  final int rankInstitution;
  final int rankBranch;
  final Map<String, SubjectStats> subjects;

  const StudentTrialPoint({
    required this.examId,
    required this.examName,
    required this.date,
    required this.score,
    required this.totalNet,
    required this.totalCorrect,
    required this.totalWrong,
    required this.totalEmpty,
    this.examQuestionCount = 0,
    this.isFullTrial = true,
    required this.rankInstitution,
    required this.rankBranch,
    required this.subjects,
  });

  int get effectiveTotalQuestions {
    final studentSum = totalCorrect + totalWrong + totalEmpty;
    if (examQuestionCount > 0) {
      return math.max(examQuestionCount, studentSum);
    }
    return studentSum > 0 ? studentSum : 90;
  }

  double get netSuccessRate =>
      (totalNet / math.max(1, effectiveTotalQuestions)).clamp(-0.35, 1.0);
}

class StudentRiskProfile {
  final AcademicStudentInfo student;
  final double riskScore; // 0 - 100
  final String riskTier; // 'critical' | 'warning' | 'safe'
  final List<String> reasons;
  final double? latestTrialScore;
  final double? latestTrialNet;
  final double? trialNetDelta;
  final double? writtenGradeAverage;
  final double homeworkCompletionRate;
  final int missingHomeworkCount;
  final double absentDays;
  final int lateLessons;

  const StudentRiskProfile({
    required this.student,
    required this.riskScore,
    required this.riskTier,
    required this.reasons,
    this.latestTrialScore,
    this.latestTrialNet,
    this.trialNetDelta,
    this.writtenGradeAverage,
    required this.homeworkCompletionRate,
    required this.missingHomeworkCount,
    required this.absentDays,
    required this.lateLessons,
  });
}

class AcademicDataset {
  final String institutionId;
  final String schoolTypeId;
  final String schoolName;
  final String activeTermId;
  final String activeTermName;
  final String
  schoolStage; // 'ortaokul' | 'lise' | 'ilkokul' | 'anaokulu' | 'genel'
  final List<AcademicClassInfo> classes;
  final List<AcademicStudentInfo> students;
  final List<ParsedTrialExam> trialExams;
  final List<ParsedClassExam> classExams;
  final Map<String, StudentAttendanceSummary> attendanceByStudent;
  final Map<String, StudentHomeworkSummary> homeworkByStudent;
  final List<ClassHomeworkSummary> classHomeworkSummaries;
  final List<SubjectHomeworkSummary> subjectHomeworkSummaries;
  final EtutAnalyticsSummary etutSummary;
  final Map<String, List<StudentTrialPoint>> trialHistoryByStudent;
  final List<StudentRiskProfile> riskProfiles;

  const AcademicDataset({
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolName,
    this.activeTermId = '',
    this.activeTermName = '',
    this.schoolStage = 'genel',
    required this.classes,
    required this.students,
    required this.trialExams,
    required this.classExams,
    required this.attendanceByStudent,
    required this.homeworkByStudent,
    required this.classHomeworkSummaries,
    required this.subjectHomeworkSummaries,
    required this.etutSummary,
    required this.trialHistoryByStudent,
    required this.riskProfiles,
  });

  int get criticalRiskCount =>
      riskProfiles.where((r) => r.riskTier == 'critical').length;

  int get warningRiskCount =>
      riskProfiles.where((r) => r.riskTier == 'warning').length;

  int get criticalAttendanceCount => attendanceByStudent.values
      .where(
        (a) => a.estimatedAbsentDays >= 7.0 || a.totalEstimatedDays >= 20.0,
      )
      .length;

  double get overallHomeworkCompletionRate {
    if (classHomeworkSummaries.isEmpty) return 100.0;
    int done = 0, inc = 0, miss = 0;
    for (final c in classHomeworkSummaries) {
      done += c.doneCount;
      inc += c.incompleteCount;
      miss += c.missingCount;
    }
    final tot = done + inc + miss;
    if (tot == 0) return 100.0;
    return ((done + inc * 0.5) / tot) * 100.0;
  }
}

class AcademicTrackingDataService {
  static final Map<String, ({DateTime fetchedAt, AcademicDataset data})>
  _cache = {};

  static String normTr(String input) {
    return input
        .trim()
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .replaceAll('Ş', 'ş')
        .replaceAll('Ğ', 'ğ')
        .replaceAll('Ü', 'ü')
        .replaceAll('Ö', 'ö')
        .replaceAll('Ç', 'ç')
        .toLowerCase();
  }

  static Future<AcademicDataset> loadDataset({
    required String institutionId,
    required String schoolTypeId,
    String schoolTypeName = '',
    bool isTeacher = false,
    List<String>? allowedClassIds,
    bool forceRefresh = false,
  }) async {
    final termService = TermService();
    final selectedTermId = await termService.getSelectedTermId();
    final activeTermId = await termService.getActiveTermId();
    final effectiveTermId =
        (selectedTermId != null && selectedTermId.trim().isNotEmpty)
        ? selectedTermId.trim()
        : (activeTermId?.trim() ?? '');
    String effectiveTermName =
        (await termService.getSelectedTermName())?.trim() ?? '';

    final allowedKey = (allowedClassIds ?? const <String>[]).join(',');
    final cacheKey =
        '${institutionId}_${schoolTypeId}_${effectiveTermId}_${isTeacher}_$allowedKey';

    if (!forceRefresh && _cache.containsKey(cacheKey)) {
      final entry = _cache[cacheKey]!;
      if (DateTime.now().difference(entry.fetchedAt).inMinutes < 3) {
        return entry.data;
      }
    }

    final db = FirebaseFirestore.instance;
    final instVariants = {
      institutionId.trim(),
      institutionId.trim().toUpperCase(),
      institutionId.trim().toLowerCase(),
    }.where((e) => e.isNotEmpty).toList();

    if (instVariants.isEmpty) {
      return AcademicDataset(
        institutionId: institutionId,
        schoolTypeId: schoolTypeId,
        schoolName: schoolTypeName,
        activeTermId: effectiveTermId,
        activeTermName: effectiveTermName,
        schoolStage: _detectSchoolStage(schoolTypeName, const {}, const {}),
        classes: const [],
        students: const [],
        trialExams: const [],
        classExams: const [],
        attendanceByStudent: const {},
        homeworkByStudent: const {},
        classHomeworkSummaries: const [],
        subjectHomeworkSummaries: const [],
        etutSummary: const EtutAnalyticsSummary(),
        trialHistoryByStudent: const {},
        riskProfiles: const [],
      );
    }

    Future<QuerySnapshot<Map<String, dynamic>>?> safeQuery(
      Query<Map<String, dynamic>> q,
    ) async {
      try {
        return await q.get().timeout(const Duration(seconds: 7));
      } catch (_) {
        return null;
      }
    }

    Future<DocumentSnapshot<Map<String, dynamic>>?> safeDoc(
      DocumentReference<Map<String, dynamic>> ref,
    ) async {
      try {
        return await ref.get().timeout(const Duration(seconds: 5));
      } catch (_) {
        return null;
      }
    }

    final docFutures = Future.wait([
      effectiveTermId.isNotEmpty
          ? safeDoc(db.collection('terms').doc(effectiveTermId))
          : Future<DocumentSnapshot<Map<String, dynamic>>?>.value(null),
      schoolTypeId.trim().isNotEmpty
          ? safeDoc(db.collection('schoolTypes').doc(schoolTypeId.trim()))
          : Future<DocumentSnapshot<Map<String, dynamic>>?>.value(null),
    ]);

    final futures = await Future.wait([
      safeQuery(
        db
            .collection('schools')
            .where('institutionId', whereIn: instVariants)
            .limit(1),
      ), // 0
      safeQuery(
        db.collection('classes').where('institutionId', whereIn: instVariants),
      ), // 1
      safeQuery(
        db.collection('students').where('institutionId', whereIn: instVariants),
      ), // 2
      safeQuery(
        db
            .collection('trial_exams')
            .where('institutionId', whereIn: instVariants),
      ), // 3
      safeQuery(
        db
            .collection('class_exams')
            .where('institutionId', whereIn: instVariants),
      ), // 4
      safeQuery(
        db
            .collection('lessonAttendance')
            .where('institutionId', whereIn: instVariants),
      ), // 5
      safeQuery(
        db
            .collection('homeworks')
            .where('institutionId', whereIn: instVariants),
      ), // 6
      safeQuery(
        db
            .collection('etut_requests')
            .where('institutionId', whereIn: instVariants),
      ), // 7
    ]);

    final metaDocs = await docFutures;
    final termDoc = metaDocs[0];
    final schoolTypeDoc = metaDocs[1];

    DateTime? termStart;
    DateTime? termEnd;
    if (termDoc != null && termDoc.exists) {
      final td = termDoc.data() ?? const <String, dynamic>{};
      if (effectiveTermName.isEmpty) {
        effectiveTermName = (td['name'] ?? '').toString().trim();
      }
      final sy = td['startYear'] is int
          ? td['startYear'] as int
          : int.tryParse((td['startYear'] ?? '').toString());
      final ey = td['endYear'] is int
          ? td['endYear'] as int
          : int.tryParse((td['endYear'] ?? '').toString());
      if (sy != null && ey != null) {
        termStart = DateTime(sy, 8, 15);
        termEnd = DateTime(ey, 8, 31, 23, 59, 59);
      } else {
        termStart = _parseAnyDate(td['startDate']);
        termEnd = _parseAnyDate(td['endDate']);
      }
    }
    if (termStart == null && effectiveTermName.isNotEmpty) {
      final m = RegExp(r'(20\d{2})\D+(20\d{2})').firstMatch(effectiveTermName);
      if (m != null) {
        final sy = int.tryParse(m.group(1)!);
        final ey = int.tryParse(m.group(2)!);
        if (sy != null && ey != null) {
          termStart = DateTime(sy, 8, 15);
          termEnd = DateTime(ey, 8, 31, 23, 59, 59);
        }
      }
    }

    bool matchesTerm(Map<String, dynamic> d, {DateTime? recordDate}) {
      if (effectiveTermId.isEmpty) return true;
      final docTermId = (d['termId'] ?? '').toString().trim();
      if (docTermId.isNotEmpty) {
        return docTermId == effectiveTermId;
      }
      if (recordDate != null && termStart != null && termEnd != null) {
        return !recordDate.isBefore(termStart) && !recordDate.isAfter(termEnd);
      }
      return true;
    }

    String stDocLabel = schoolTypeName.trim();
    final stDocGrades = <String>{};
    if (schoolTypeDoc != null && schoolTypeDoc.exists) {
      final std = schoolTypeDoc.data() ?? const <String, dynamic>{};
      final stName = (std['schoolTypeName'] ?? std['name'] ?? std['type'] ?? '')
          .toString()
          .trim();
      if (stDocLabel.isEmpty && stName.isNotEmpty) {
        stDocLabel = stName;
      }
      final ag = std['activeGrades'];
      if (ag is Iterable) {
        for (final g in ag) {
          final lv = _extractLevel(g.toString());
          if (lv.isNotEmpty) stDocGrades.add(lv);
          if (normTr(g.toString()).contains('mezun')) stDocGrades.add('12');
        }
      }
    }

    String resolvedSchoolName = stDocLabel;
    final schoolSnap = futures[0];
    if (schoolSnap != null && schoolSnap.docs.isNotEmpty) {
      final sd = schoolSnap.docs.first.data();
      final base = (sd['schoolName'] ?? sd['name'] ?? '').toString().trim();
      if (base.isNotEmpty) {
        resolvedSchoolName =
            resolvedSchoolName.isNotEmpty &&
                !normTr(base).contains(normTr(resolvedSchoolName))
            ? '$base • $resolvedSchoolName'
            : base;
      }
    }
    if (resolvedSchoolName.isEmpty) resolvedSchoolName = 'Akademik Merkez';

    final allowedSet =
        (isTeacher && allowedClassIds != null && allowedClassIds.isNotEmpty)
        ? allowedClassIds.toSet()
        : null;

    // 1. Sınıfları ayrıştır (Aktif / Seçili Dönem Filtreli)
    final classes = <AcademicClassInfo>[];
    final classMap = <String, AcademicClassInfo>{};
    final classByName = <String, AcademicClassInfo>{};
    final classesSnap = futures[1];
    if (classesSnap != null) {
      for (final doc in classesSnap.docs) {
        final d = doc.data();
        if (d['isActive'] == false) continue;
        if (!matchesTerm(d)) continue;
        final cStId = (d['schoolTypeId'] ?? '').toString().trim();
        if (schoolTypeId.isNotEmpty &&
            cStId.isNotEmpty &&
            cStId != schoolTypeId) {
          continue;
        }
        if (allowedSet != null && !allowedSet.contains(doc.id)) continue;

        final cName = (d['className'] ?? d['name'] ?? doc.id).toString().trim();
        final cLevel =
            (d['classLevel'] ?? d['gradeLevel'] ?? _extractLevel(cName))
                .toString()
                .trim();
        final info = AcademicClassInfo(
          id: doc.id,
          name: cName,
          classLevel: cLevel,
          schoolTypeId: cStId,
        );
        classes.add(info);
        classMap[doc.id] = info;
        final cKey = normTr(cName);
        if (cKey.isNotEmpty) classByName[cKey] = info;
      }
    }
    classes.sort((a, b) => a.name.compareTo(b.name));

    // 2. Öğrencileri ayrıştır (Aktif / Seçili Dönem Filtreli)
    final students = <AcademicStudentInfo>[];
    final studentById = <String, AcademicStudentInfo>{};
    final studentByNo = <String, AcademicStudentInfo>{};
    final studentByTc = <String, AcademicStudentInfo>{};
    final studentByName = <String, AcademicStudentInfo>{};
    final allTermStudentsById = <String, AcademicStudentInfo>{};

    final studentsSnap = futures[2];
    if (studentsSnap != null) {
      for (final doc in studentsSnap.docs) {
        final d = doc.data();
        if (d['isActive'] == false) continue;
        if (!matchesTerm(d)) continue;

        final rawClassId = (d['classId'] ?? d['classroomId'] ?? '')
            .toString()
            .trim();
        final rawClassName = (d['className'] ?? d['branch'] ?? '')
            .toString()
            .trim();
        final matchedClass =
            classMap[rawClassId] ??
            (rawClassName.isNotEmpty
                ? classByName[normTr(rawClassName)]
                : null);
        final sClassId = matchedClass?.id ?? rawClassId;
        final sStId = (d['schoolTypeId'] ?? '').toString().trim();

        final fullName = _extractStudentName(d);
        final sNo = (d['studentNo'] ?? d['schoolNumber'] ?? d['number'] ?? '')
            .toString()
            .trim();
        final tc = (d['tcNo'] ?? d['tcKimlik'] ?? '').toString().trim();
        final cName =
            matchedClass?.name ??
            (rawClassName.isNotEmpty ? rawClassName : 'Sınıf');
        final cLevel =
            matchedClass?.classLevel ??
            (d['classLevel'] ?? _extractLevel(cName)).toString().trim();

        final candidateSt = AcademicStudentInfo(
          id: doc.id,
          studentNo: sNo,
          tcNo: tc,
          name: fullName,
          classId: sClassId,
          className: cName,
          classLevel: cLevel,
        );
        allTermStudentsById[doc.id] = candidateSt;

        if (schoolTypeId.isNotEmpty) {
          if (matchedClass == null) {
            if (sStId.isNotEmpty && sStId != schoolTypeId) {
              continue;
            }
            if (sClassId.isNotEmpty && classMap.isNotEmpty) {
              continue;
            }
          }
        }
        if (allowedSet != null && !allowedSet.contains(sClassId)) {
          continue;
        }

        students.add(candidateSt);
        studentById[candidateSt.id] = candidateSt;
        if (sNo.isNotEmpty) studentByNo[sNo] = candidateSt;
        if (tc.isNotEmpty) studentByTc[tc] = candidateSt;
        final nKey = normTr(fullName);
        if (nKey.isNotEmpty) studentByName[nKey] = candidateSt;
      }
    }
    students.sort((a, b) {
      final c = a.className.compareTo(b.className);
      if (c != 0) return c;
      return a.name.compareTo(b.name);
    });

    final validClassLevels = {
      ...stDocGrades,
      ...classes
          .map(
            (c) =>
                _extractLevel(c.classLevel.isNotEmpty ? c.classLevel : c.name),
          )
          .where((l) => l.isNotEmpty),
      ...students
          .map(
            (s) => _extractLevel(
              s.classLevel.isNotEmpty ? s.classLevel : s.className,
            ),
          )
          .where((l) => l.isNotEmpty),
    };

    final schoolStage = _detectSchoolStage(
      schoolTypeId.isNotEmpty ? '$stDocLabel $schoolTypeName' : schoolTypeName,
      stDocGrades,
      validClassLevels,
    );

    // 3. Deneme Sınavlarını (`trial_exams`) ve Öğrenci Geçmişlerini ayrıştır (Dönem + Kademe Filtreli)
    final trialExams = <ParsedTrialExam>[];
    final trialHistoryByStudent = <String, List<StudentTrialPoint>>{};
    final trialSnap = futures[3];
    if (trialSnap != null) {
      for (final doc in trialSnap.docs) {
        final d = doc.data();
        if (d['isActive'] == false) continue;
        final exam = TrialExam.fromMap(d, doc.id);
        if (!matchesTerm(d, recordDate: exam.date)) continue;

        final examNumericLevel = _extractLevel(
          exam.classLevel.isNotEmpty ? exam.classLevel : exam.name,
        );
        final stageMatchesExam = _examMatchesStage(
          schoolStage: schoolTypeId.isNotEmpty ? schoolStage : 'genel',
          examLevel: examNumericLevel,
          examName: exam.name,
          validLevels: validClassLevels,
        );
        if (schoolTypeId.isNotEmpty && !stageMatchesExam) {
          continue;
        }

        final parsedResults = _parseTrialResultsJson(exam.resultsJson);
        final tempExamInfo = ParsedTrialExam(
          exam: exam,
          results: parsedResults,
        );
        final examCap = tempExamInfo.totalQuestionCapacity;
        final isFullTrial = tempExamInfo.isFullTrialExam;
        final matchedResults = <StudentResult>[];

        for (final sr in parsedResults) {
          AcademicStudentInfo? matchedSt;
          if (sr.systemStudentId != null &&
              studentById.containsKey(sr.systemStudentId)) {
            matchedSt = studentById[sr.systemStudentId];
          } else if (sr.tcNo.trim().isNotEmpty &&
              studentByTc.containsKey(sr.tcNo.trim())) {
            matchedSt = studentByTc[sr.tcNo.trim()];
          } else if (sr.studentNo.trim().isNotEmpty &&
              studentByNo.containsKey(sr.studentNo.trim())) {
            matchedSt = studentByNo[sr.studentNo.trim()];
          } else {
            final nk = normTr(sr.name);
            if (nk.isNotEmpty && studentByName.containsKey(nk)) {
              matchedSt = studentByName[nk];
            }
          }

          if (matchedSt != null) {
            sr.systemStudentId = matchedSt.id;
            if (sr.branch.trim().isEmpty) sr.branch = matchedSt.className;
            matchedResults.add(sr);

            final tot = sr.total;
            trialHistoryByStudent
                .putIfAbsent(matchedSt.id, () => <StudentTrialPoint>[])
                .add(
                  StudentTrialPoint(
                    examId: exam.id,
                    examName: exam.name,
                    date: exam.date,
                    score: sr.score,
                    totalNet: tot.net,
                    totalCorrect: tot.correct,
                    totalWrong: tot.wrong,
                    totalEmpty: tot.empty,
                    examQuestionCount: examCap,
                    isFullTrial: isFullTrial,
                    rankInstitution: sr.rankInstitution,
                    rankBranch: sr.rankBranch,
                    subjects: sr.subjects,
                  ),
                );
          } else if (schoolTypeId.isEmpty && allowedSet == null) {
            matchedResults.add(sr);
          } else if (stageMatchesExam && allowedSet == null) {
            matchedResults.add(sr);
          }
        }

        if (matchedResults.isNotEmpty ||
            (stageMatchesExam && allowedSet == null)) {
          trialExams.add(
            ParsedTrialExam(
              exam: exam,
              results: matchedResults.isNotEmpty
                  ? matchedResults
                  : (allowedSet == null ? parsedResults : const []),
            ),
          );
        }
      }
    }
    trialExams.sort((a, b) => b.date.compareTo(a.date));
    for (final list in trialHistoryByStudent.values) {
      list.sort((a, b) => a.date.compareTo(b.date));
    }

    // 4. Yazılı Sınıf Sınavlarını (`class_exams`) ayrıştır (Dönem Filtreli)
    final classExams = <ParsedClassExam>[];
    final writtenGradesByStudent = <String, List<double>>{};
    final classExamSnap = futures[4];
    if (classExamSnap != null) {
      for (final doc in classExamSnap.docs) {
        final d = doc.data();
        final dt = _parseAnyDate(d['date'] ?? d['createdAt']) ?? DateTime.now();
        if (!matchesTerm(d, recordDate: dt)) continue;

        final cid = (d['classId'] ?? '').toString().trim();
        if (classMap.isNotEmpty &&
            cid.isNotEmpty &&
            !classMap.containsKey(cid)) {
          continue;
        }
        if (allowedSet != null && !allowedSet.contains(cid)) continue;

        final rawGrades = d['grades'];
        final parsedGrades = <String, double>{};
        if (rawGrades is Map) {
          rawGrades.forEach((sid, val) {
            final numVal = val is num
                ? val.toDouble()
                : double.tryParse(val.toString().trim());
            if (numVal != null && numVal >= 0 && numVal <= 100) {
              final sKey = sid.toString();
              parsedGrades[sKey] = numVal;
              if (studentById.containsKey(sKey)) {
                writtenGradesByStudent
                    .putIfAbsent(sKey, () => <double>[])
                    .add(numVal);
              }
            }
          });
        }

        classExams.add(
          ParsedClassExam(
            id: doc.id,
            examName: (d['examName'] ?? d['name'] ?? 'Yazılı Sınav').toString(),
            lessonName: (d['lessonName'] ?? d['subjectName'] ?? 'Ders')
                .toString(),
            classId: cid,
            className:
                classMap[cid]?.name ?? (d['className'] ?? 'Sınıf').toString(),
            date: dt,
            grades: parsedGrades,
          ),
        );
      }
    }
    classExams.sort((a, b) => b.date.compareTo(a.date));

    // 5. Yoklama (`lessonAttendance`) verisini ayrıştır (Dönem Filtreli)
    final attendanceByStudent = <String, StudentAttendanceSummary>{
      for (final s in students) s.id: StudentAttendanceSummary(s.id),
    };
    final attSnap = futures[5];
    if (attSnap != null) {
      for (final doc in attSnap.docs) {
        final d = doc.data();
        final attDate = _parseAnyDate(d['date'] ?? d['createdAt']);
        if (!matchesTerm(d, recordDate: attDate)) continue;

        final cid = (d['classId'] ?? '').toString().trim();
        if (schoolTypeId.isNotEmpty &&
            classMap.isNotEmpty &&
            cid.isNotEmpty &&
            !classMap.containsKey(cid)) {
          continue;
        }
        if (allowedSet != null && cid.isNotEmpty && !allowedSet.contains(cid)) {
          continue;
        }
        final rawStatuses = d['studentStatuses'];
        if (rawStatuses is! Map) continue;

        final dateKey = (d['date'] ?? doc.id).toString().trim();
        final lessonHour = d['lessonHour'] is int
            ? d['lessonHour'] as int
            : (int.tryParse((d['lessonHour'] ?? '1').toString()) ?? 1);

        rawStatuses.forEach((sidObj, stVal) {
          final sid = sidObj.toString();
          final summary = attendanceByStudent[sid];
          if (summary == null) return;
          final s = stVal.toString().trim();
          if (s == 'absent') {
            summary.absentLessons += 1;
            summary.absentDateKeys.add(dateKey);
            summary.absentLessonsPerDate[dateKey] =
                (summary.absentLessonsPerDate[dateKey] ?? 0) + 1;
          } else if (s == 'excused' || s == 'reported' || s == 'onDuty') {
            summary.excusedLessons += 1;
            summary.excusedDateKeys.add(dateKey);
            summary.excusedLessonsPerDate[dateKey] =
                (summary.excusedLessonsPerDate[dateKey] ?? 0) + 1;
          } else if (s == 'late') {
            summary.lateLessons += 1;
            if (lessonHour == 1) summary.firstHourLateCount += 1;
          } else if (s == 'present') {
            summary.presentLessons += 1;
          }
        });
      }
    }

    // 6. Ödev (`homeworks`) verisini ayrıştır (Dönem Filtreli + Tam Öğrenci Eşleştirmeli)
    final homeworkByStudent = <String, StudentHomeworkSummary>{
      for (final s in students) s.id: StudentHomeworkSummary(s.id),
    };
    final hwClassAcc = <String, ({int hwCount, int done, int inc, int miss})>{};
    final hwSubjAcc = <String, ({int hwCount, int done, int inc, int miss})>{};

    final hwSnap = futures[6];
    if (hwSnap != null) {
      for (final doc in hwSnap.docs) {
        final d = doc.data();
        final hwDate = _parseAnyDate(
          d['assignedDate'] ?? d['createdAt'] ?? d['dueDate'],
        );
        if (!matchesTerm(d, recordDate: hwDate)) continue;

        final rawCid = (d['classId'] ?? '').toString().trim();
        final resolvedClass =
            classMap[rawCid] ??
            (rawCid.isNotEmpty ? classByName[normTr(rawCid)] : null);
        final cid = resolvedClass?.id ?? rawCid;

        if (classMap.isNotEmpty &&
            cid.isNotEmpty &&
            !classMap.containsKey(cid)) {
          continue;
        }
        if (allowedSet != null && cid.isNotEmpty && !allowedSet.contains(cid)) {
          continue;
        }

        final subj =
            (d['lessonName'] ?? d['subjectName'] ?? d['branch'] ?? 'Genel')
                .toString()
                .trim();
        final statuses = d['studentStatuses'] is Map
            ? Map<String, dynamic>.from(d['studentStatuses'] as Map)
            : const <String, dynamic>{};
        final targetSet = <String>{
          if (d['targetStudentIds'] is Iterable)
            ...(d['targetStudentIds'] as Iterable)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty),
          ...statuses.keys
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty),
        };

        int cDone = 0, cInc = 0, cMiss = 0;
        for (final sid in targetSet) {
          StudentHomeworkSummary? stHw = homeworkByStudent[sid];
          if (stHw == null && allTermStudentsById.containsKey(sid)) {
            final baseSt = allTermStudentsById[sid]!;
            final fixedSt = AcademicStudentInfo(
              id: baseSt.id,
              studentNo: baseSt.studentNo,
              tcNo: baseSt.tcNo,
              name: baseSt.name,
              classId: cid.isNotEmpty ? cid : baseSt.classId,
              className: classMap[cid]?.name ?? baseSt.className,
              classLevel: classMap[cid]?.classLevel ?? baseSt.classLevel,
            );
            students.add(fixedSt);
            studentById[sid] = fixedSt;
            attendanceByStudent.putIfAbsent(
              sid,
              () => StudentAttendanceSummary(sid),
            );
            stHw = homeworkByStudent.putIfAbsent(
              sid,
              () => StudentHomeworkSummary(sid),
            );
          }

          // Silinmiş/başka döneme ait hayalet ID'lerin sınıf özetini bozmasını engelle
          if (stHw == null && students.isNotEmpty) continue;

          final rawCode = statuses[sid];
          final parsed = _classifyHomeworkStatus(rawCode);
          if (stHw != null) {
            stHw.assignedCount += 1;
            if (parsed == 'done') {
              stHw.doneCount += 1;
            } else if (parsed == 'incomplete') {
              stHw.incompleteCount += 1;
            } else if (parsed == 'missing') {
              stHw.missingCount += 1;
            } else {
              stHw.pendingCount += 1;
            }
          }
          if (parsed == 'done') cDone++;
          if (parsed == 'incomplete') cInc++;
          if (parsed == 'missing') cMiss++;
        }

        if (cid.isNotEmpty &&
            (cDone + cInc + cMiss > 0 || targetSet.isNotEmpty)) {
          final prev =
              hwClassAcc[cid] ?? (hwCount: 0, done: 0, inc: 0, miss: 0);
          hwClassAcc[cid] = (
            hwCount: prev.hwCount + 1,
            done: prev.done + cDone,
            inc: prev.inc + cInc,
            miss: prev.miss + cMiss,
          );
        }
        if (subj.isNotEmpty &&
            (cDone + cInc + cMiss > 0 || targetSet.isNotEmpty)) {
          final prev =
              hwSubjAcc[subj] ?? (hwCount: 0, done: 0, inc: 0, miss: 0);
          hwSubjAcc[subj] = (
            hwCount: prev.hwCount + 1,
            done: prev.done + cDone,
            inc: prev.inc + cInc,
            miss: prev.miss + cMiss,
          );
        }
      }
    }

    final classHomeworkSummaries = hwClassAcc.entries.map((e) {
      return ClassHomeworkSummary(
        classId: e.key,
        className: classMap[e.key]?.name ?? e.key,
        homeworkCount: e.value.hwCount,
        doneCount: e.value.done,
        incompleteCount: e.value.inc,
        missingCount: e.value.miss,
      );
    }).toList()..sort((a, b) => a.completionRate.compareTo(b.completionRate));

    final subjectHomeworkSummaries = hwSubjAcc.entries.map((e) {
      return SubjectHomeworkSummary(
        subjectName: e.key,
        homeworkCount: e.value.hwCount,
        doneCount: e.value.done,
        incompleteCount: e.value.inc,
        missingCount: e.value.miss,
      );
    }).toList()..sort((a, b) => a.completionRate.compareTo(b.completionRate));

    // 7. Etüt (`etut_requests`) verisini ayrıştır (Dönem Filtreli)
    int etutTotal = 0, etutCompleted = 0, etutPending = 0;
    final etutBySubject = <String, int>{};
    final etutByTeacher = <String, int>{};
    final etutSnap = futures[7];
    if (etutSnap != null) {
      for (final doc in etutSnap.docs) {
        final d = doc.data();
        final etutDate = _parseAnyDate(
          d['date'] ?? d['requestDate'] ?? d['createdAt'],
        );
        if (!matchesTerm(d, recordDate: etutDate)) continue;

        final eStId = (d['schoolTypeId'] ?? '').toString().trim();
        if (schoolTypeId.isNotEmpty &&
            eStId.isNotEmpty &&
            eStId != schoolTypeId) {
          continue;
        }
        etutTotal++;
        final taken =
            d['attendanceTaken'] == true || d['status'] == 'completed';
        if (taken) {
          etutCompleted++;
        } else {
          etutPending++;
        }
        final subj = (d['lessonName'] ?? d['subject'] ?? 'Genel Etüt')
            .toString()
            .trim();
        if (subj.isNotEmpty) {
          etutBySubject[subj] = (etutBySubject[subj] ?? 0) + 1;
        }
        final tName = (d['teacherName'] ?? '').toString().trim();
        if (tName.isNotEmpty) {
          etutByTeacher[tName] = (etutByTeacher[tName] ?? 0) + 1;
        }
      }
    }

    // 8. 360° Akademik Risk & Erken Uyarı Skorlarını Hesapla
    final riskProfiles = <StudentRiskProfile>[];
    for (final st in students) {
      double score = 0;
      final reasons = <String>[];

      final tHist = trialHistoryByStudent[st.id] ?? const [];
      double? latestScore;
      double? latestNet;
      double? netDelta;

      if (tHist.isNotEmpty) {
        final fullTrials = tHist.where((e) => e.isFullTrial).toList();
        final refHist = fullTrials.isNotEmpty ? fullTrials : tHist;
        final last = refHist.last;
        latestScore = last.score;
        latestNet = last.totalNet;

        if (refHist.length >= 2) {
          final prev = refHist[refHist.length - 2];
          final lastQ = last.effectiveTotalQuestions;
          final prevQ = prev.effectiveTotalQuestions;
          // Soru sayıları farklıysa (örn. 20 soruluk tarama vs 90 soruluk deneme) aynı soru ölçeğine eşitleyerek fark al
          if (lastQ == prevQ) {
            netDelta = last.totalNet - prev.totalNet;
          } else {
            netDelta =
                (last.netSuccessRate - prev.netSuccessRate) * lastQ.toDouble();
          }
          // Düşüş eşiklerini de soru sayısına göre orantıla (90 soruda -6 net = %6.7 kayıp)
          final scaleFactor = (lastQ / 90.0).clamp(0.25, 1.35);
          if (netDelta <= -(6.0 * scaleFactor)) {
            score += 28;
            reasons.add(
              'Son denemede ${netDelta.toStringAsFixed(1)} net sert düşüş ($lastQ soru ölçeği)',
            );
          } else if (netDelta <= -(3.0 * scaleFactor)) {
            score += 15;
            reasons.add(
              'Son denemede ${netDelta.toStringAsFixed(1)} net gerileme ($lastQ soru ölçeği)',
            );
          }
        }
        if (last.isFullTrial && last.score >= 120 && last.score < 310) {
          score += 22;
          reasons.add(
            'Deneme puanı kritik bandın altında (${last.score.toStringAsFixed(1)})',
          );
        }
      }

      final wList = writtenGradesByStudent[st.id];
      double? writtenAvg;
      if (wList != null && wList.isNotEmpty) {
        writtenAvg = wList.reduce((a, b) => a + b) / wList.length;
        if (writtenAvg < 50) {
          score += 28;
          reasons.add(
            'Yazılı ortalaması geçme sınırının altında (${writtenAvg.toStringAsFixed(1)})',
          );
        } else if (writtenAvg < 62) {
          score += 12;
          reasons.add(
            'Yazılı ortalaması sınırda (${writtenAvg.toStringAsFixed(1)})',
          );
        }
      }

      final hw = homeworkByStudent[st.id]!;
      final hwRate = hw.completionRate;
      if (hw.evaluatedCount >= 2 && hwRate < 55) {
        score += 24;
        reasons.add(
          'Ödev tamamlama oranı düşük (%${hwRate.toStringAsFixed(0)} • ${hw.missingCount} yapılmadı)',
        );
      } else if (hw.missingCount >= 3) {
        score += 14;
        reasons.add('${hw.missingCount} ödev teslim edilmedi');
      }

      final att = attendanceByStudent[st.id]!;
      final absDays = att.estimatedAbsentDays;
      if (absDays >= 8.0) {
        score += 30;
        reasons.add(
          'Özürsüz devamsızlık kritik sınırda (${absDays.toStringAsFixed(1)} gün)',
        );
      } else if (absDays >= 4.5) {
        score += 15;
        reasons.add(
          'Özürsüz devamsızlık artıyor (${absDays.toStringAsFixed(1)} gün)',
        );
      }
      if (att.lateLessons >= 5) {
        score += 8;
        reasons.add('${att.lateLessons} kez derse geç kalma');
      }

      final clamped = score.clamp(0.0, 100.0);
      final tier = clamped >= 50
          ? 'critical'
          : (clamped >= 25 ? 'warning' : 'safe');

      riskProfiles.add(
        StudentRiskProfile(
          student: st,
          riskScore: clamped,
          riskTier: tier,
          reasons: reasons,
          latestTrialScore: latestScore,
          latestTrialNet: latestNet,
          trialNetDelta: netDelta,
          writtenGradeAverage: writtenAvg,
          homeworkCompletionRate: hwRate,
          missingHomeworkCount: hw.missingCount,
          absentDays: absDays,
          lateLessons: att.lateLessons,
        ),
      );
    }

    riskProfiles.sort((a, b) => b.riskScore.compareTo(a.riskScore));

    final dataset = AcademicDataset(
      institutionId: institutionId,
      schoolTypeId: schoolTypeId,
      schoolName: resolvedSchoolName,
      activeTermId: effectiveTermId,
      activeTermName: effectiveTermName,
      schoolStage: schoolStage,
      classes: classes,
      students: students,
      trialExams: trialExams,
      classExams: classExams,
      attendanceByStudent: attendanceByStudent,
      homeworkByStudent: homeworkByStudent,
      classHomeworkSummaries: classHomeworkSummaries,
      subjectHomeworkSummaries: subjectHomeworkSummaries,
      etutSummary: EtutAnalyticsSummary(
        totalRequests: etutTotal,
        completedCount: etutCompleted,
        pendingCount: etutPending,
        bySubject: etutBySubject,
        byTeacher: etutByTeacher,
      ),
      trialHistoryByStudent: trialHistoryByStudent,
      riskProfiles: riskProfiles,
    );

    _cache[cacheKey] = (fetchedAt: DateTime.now(), data: dataset);
    return dataset;
  }

  static DateTime? _parseAnyDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    final dm = RegExp(r'^(\d{2})[./-](\d{2})[./-](\d{4})').firstMatch(s);
    if (dm != null) {
      final d = int.tryParse(dm.group(1)!);
      final m = int.tryParse(dm.group(2)!);
      final y = int.tryParse(dm.group(3)!);
      if (d != null && m != null && y != null) {
        return DateTime(y, m, d);
      }
    }
    return null;
  }

  static String _detectSchoolStage(
    String rawLabel,
    Set<String> stDocGrades,
    Set<String> classLevels,
  ) {
    final s = normTr(rawLabel);
    if (s.contains('ortaokul')) return 'ortaokul';
    if (s.contains('lise') ||
        s.contains('anadolu') ||
        s.contains('fen lise') ||
        s.contains('meslek') ||
        s.contains('yks') ||
        s.contains('kurs')) {
      return 'lise';
    }
    if (s.contains('ilkokul')) return 'ilkokul';
    if (s.contains('anaokul') || s.contains('kres') || s.contains('kreş')) {
      return 'anaokulu';
    }

    final merged = {...stDocGrades, ...classLevels};
    final hasMiddle = merged.any((g) => {'5', '6', '7', '8'}.contains(g));
    final hasHigh = merged.any(
      (g) => {'9', '10', '11', '12', 'mezun'}.contains(g.toLowerCase()),
    );
    final hasPrimary = merged.any((g) => {'1', '2', '3', '4'}.contains(g));

    if (hasMiddle && !hasHigh) return 'ortaokul';
    if (hasHigh && !hasMiddle) return 'lise';
    if (hasPrimary && !hasMiddle && !hasHigh) return 'ilkokul';
    return 'genel';
  }

  static bool _examMatchesStage({
    required String schoolStage,
    required String examLevel,
    required String examName,
    required Set<String> validLevels,
  }) {
    if (schoolStage == 'genel') return true;
    final en = normTr(examName);
    if (schoolStage == 'ortaokul') {
      if (en.contains('tyt') || en.contains('ayt') || en.contains('yks')) {
        return false;
      }
      if (examLevel.isNotEmpty) {
        return {'5', '6', '7', '8'}.contains(examLevel);
      }
      return true;
    }
    if (schoolStage == 'lise') {
      if (en.contains('lgs') ||
          en.contains('bursluluk 5') ||
          en.contains('bursluluk 6')) {
        return false;
      }
      if (examLevel.isNotEmpty) {
        return {'9', '10', '11', '12'}.contains(examLevel);
      }
      return true;
    }
    if (validLevels.isNotEmpty && examLevel.isNotEmpty) {
      return validLevels.contains(examLevel);
    }
    return true;
  }

  static String _extractStudentName(Map<String, dynamic> d) {
    final full = (d['fullName'] ?? '').toString().trim();
    if (full.isNotEmpty) return full;
    final n = (d['name'] ?? d['firstName'] ?? '').toString().trim();
    final s = (d['surname'] ?? d['lastName'] ?? '').toString().trim();
    final c = '$n $s'.trim();
    return c.isNotEmpty ? c : 'Öğrenci';
  }

  static String _extractLevel(String className) {
    final m = RegExp(r'(\d{1,2})').firstMatch(className.trim());
    return m != null ? m.group(1)! : '';
  }

  static String _classifyHomeworkStatus(dynamic raw) {
    if (raw == null) return 'pending';
    if (raw is int) {
      if (raw == 1) return 'done';
      if (raw == 2 || raw == 4) return 'missing';
      if (raw == 3) return 'incomplete';
      return 'pending';
    }
    final s = normTr(raw.toString());
    if (s == '1' || s == 'done' || s == 'completed' || s.contains('yapt')) {
      return 'done';
    }
    if (s == '3' ||
        s == 'incomplete' ||
        s == 'partial' ||
        s.contains('eksik')) {
      return 'incomplete';
    }
    if (s == '2' ||
        s == '4' ||
        s == 'missing' ||
        s == 'not_done' ||
        s == 'notbrought' ||
        s.contains('yapmad') ||
        s.contains('getirmed')) {
      return 'missing';
    }
    return 'pending';
  }

  static List<StudentResult> _parseTrialResultsJson(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(rawJson);
      List<dynamic> list = const [];
      if (decoded is List) {
        list = decoded;
      } else if (decoded is Map) {
        if (decoded['students'] is List) {
          list = decoded['students'] as List;
        } else if (decoded['results'] is List) {
          list = decoded['results'] as List;
        }
      }
      final results = <StudentResult>[];
      for (final item in list) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        if (map['raw'] is Map) {
          results.add(
            StudentResult.fromJson(
              Map<String, dynamic>.from(map['raw'] as Map),
            ),
          );
        } else {
          results.add(StudentResult.fromJson(map));
        }
      }
      return results;
    } catch (_) {
      return const [];
    }
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// LGS & YKS KALİBRE PUAN, YÜZDELİK DİLİM VE HEDEF REÇETE MOTORU
/// ═══════════════════════════════════════════════════════════════════════════
class AcademicScoreEngine {
  static ({
    double score,
    double totalNet,
    double percentile,
    int estimatedRank,
    String targetTierLabel,
  })
  calculateLgs({
    required double turkceNet, // /20
    required double matNet, // /20
    required double fenNet, // /20
    required double inkilapNet, // /10
    required double dinNet, // /10
    required double ingNet, // /10
    String referenceYear = '2026',
  }) {
    final t = turkceNet.clamp(0.0, 20.0);
    final m = matNet.clamp(0.0, 20.0);
    final f = fenNet.clamp(0.0, 20.0);
    final ink = inkilapNet.clamp(0.0, 10.0);
    final din = dinNet.clamp(0.0, 10.0);
    final ing = ingNet.clamp(0.0, 10.0);

    // MEB ağırlıklı katsayı modeli: Maksimum ağırlıklı net = (20*4)*3 + (10*1)*3 = 270
    // Taban puan = 194.75, Tavan puan = 500.0 (Tam net = 500.00)
    final weightedSum =
        (t * 4.0) +
        (m * 4.0) +
        (f * 4.0) +
        (ink * 1.0) +
        (din * 1.0) +
        (ing * 1.0);
    final rawScore = 194.75 + (weightedSum / 270.0) * (500.0 - 194.75);
    final score = rawScore.clamp(194.75, 500.0);
    final totalNet = t + m + f + ink + din + ing;

    // MEB referans yüzdelik dilim tablosundan doğrusal enterpolasyon (`lgs_data.dart`)
    final table = lgsPercentiles[referenceYear] ?? lgsPercentiles['2026']!;
    double percentile = 92.0;
    if (score >= 499.95) {
      percentile = 0.01;
    } else {
      for (final r in table) {
        if (score >= r.minScore && score <= r.maxScore) {
          final ratio =
              (r.maxScore - score) / math.max(0.001, (r.maxScore - r.minScore));
          percentile =
              r.minPercentile + ratio * (r.maxPercentile - r.minPercentile);
          break;
        }
      }
    }

    final participantCount = referenceYear == '2025' ? 963142 : 994358;
    final estimatedRank = math.max(
      1,
      ((percentile / 100.0) * participantCount).round(),
    );

    String tier;
    if (percentile <= 0.35) {
      tier =
          'Türkiye Zirve Liseleri (Galatasaray / İstanbul Erkek / Kabataş / Ankara Fen)';
    } else if (percentile <= 2.0) {
      tier = 'Seçkin Fen Liseleri & Köklü Proje Anadolu Liseleri';
    } else if (percentile <= 5.5) {
      tier = 'Nitelikli Proje Anadolu & Bölge Fen Liseleri';
    } else if (percentile <= 12.0) {
      tier = 'Sınavlı Anadolu & Sosyal Bilimler Liseleri';
    } else if (percentile <= 25.0) {
      tier = 'Merkezi Sınavlı Mesleki/Anadolu Programları & Güçlü OBP Tercihi';
    } else {
      tier =
          'Temel Kazanım Güçlendirme Bandı (Çekirdek Branş Odaklı Çalışma Önerilir)';
    }

    return (
      score: score,
      totalNet: totalNet,
      percentile: percentile,
      estimatedRank: estimatedRank,
      targetTierLabel: tier,
    );
  }

  /// Öğrencinin hedeflediği LGS puanına ulaşması için en verimli net artış reçetesini üretir
  static List<String> suggestLgsNetRecipe({
    required double currentScore,
    required double targetScore,
    required double turkceNet,
    required double matNet,
    required double fenNet,
    required double inkilapNet,
    required double dinNet,
    required double ingNet,
  }) {
    if (targetScore <= currentScore + 0.5) {
      return const [
        'Mevcut netleriniz hedef puan bandınızı halihazırda karşılıyor! Deneme sürekliliğini koruyun.',
      ];
    }

    double gapPoints = targetScore - currentScore;
    // 1 ana ders neti ≈ 4 * (305.25 / 270) = 4.522 puan; 1 ara ders neti ≈ 1.13 puan
    const mainUnitPts = 4.0 * (305.25 / 270.0);
    const subUnitPts = 1.0 * (305.25 / 270.0);

    final steps = <String>[];
    final branches = <({String name, double room, double ptsPerNet})>[
      (
        name: 'Matematik',
        room: (20.0 - matNet).clamp(0, 20),
        ptsPerNet: mainUnitPts,
      ),
      (
        name: 'Fen Bilimleri',
        room: (20.0 - fenNet).clamp(0, 20),
        ptsPerNet: mainUnitPts,
      ),
      (
        name: 'Türkçe',
        room: (20.0 - turkceNet).clamp(0, 20),
        ptsPerNet: mainUnitPts,
      ),
      (
        name: 'T.C. İnkılap Tarihi',
        room: (10.0 - inkilapNet).clamp(0, 10),
        ptsPerNet: subUnitPts,
      ),
      (
        name: 'Yabancı Dil',
        room: (10.0 - ingNet).clamp(0, 10),
        ptsPerNet: subUnitPts,
      ),
      (
        name: 'Din Kültürü',
        room: (10.0 - dinNet).clamp(0, 10),
        ptsPerNet: subUnitPts,
      ),
    ]..sort((a, b) => (b.room * b.ptsPerNet).compareTo(a.room * a.ptsPerNet));

    for (final b in branches) {
      if (gapPoints <= 0.4 || b.room < 0.5) continue;
      final neededNets = (gapPoints / b.ptsPerNet);
      final takeNets = math.min(b.room, (neededNets * 2).ceil() / 2.0);
      if (takeNets >= 0.5) {
        final gained = takeNets * b.ptsPerNet;
        gapPoints -= gained;
        steps.add(
          '${b.name}: +${takeNets.toStringAsFixed(1)} net artış → yaklaşık +${gained.toStringAsFixed(1)} puan katkı sağlar.',
        );
      }
    }

    if (gapPoints > 1.0) {
      steps.add(
        'Not: Hedef puana ulaşmak için tüm branşlarda neredeyse tam net performansı gerekmektedir.',
      );
    }
    return steps;
  }

  static ({
    double tytHam,
    double tytYerlestirme,
    int tytRank,
    double aytHam,
    double aytYerlestirme,
    int aytRank,
    double obpContribution,
    String targetBand,
  })
  calculateYks({
    required String fieldType, // 'SAY' | 'EA' | 'SOZ' | 'DIL'
    required double diplomaGrade, // 50 - 100
    required bool brokenObp,
    required double tytTurkce, // /40
    required double tytSosyal, // /20
    required double tytMat, // /40
    required double tytFen, // /20
    required double aytMat, // /40
    required double aytFizik, // /14
    required double aytKimya, // /13
    required double aytBiyoloji, // /13
    required double aytEdebiyatSos1, // /40
    required double aytSos2, // /40
    required double ydtDil, // /80
  }) {
    final dip = diplomaGrade.clamp(50.0, 100.0);
    final obp =
        dip * 5.0 * (brokenObp ? 0.06 : 0.12); // Max +60 puan (kırık OBP +30)

    final tytHam =
        (100.0 +
                tytTurkce.clamp(0, 40) * 3.30 +
                tytSosyal.clamp(0, 20) * 3.40 +
                tytMat.clamp(0, 40) * 3.30 +
                tytFen.clamp(0, 20) * 3.40)
            .clamp(100.0, 500.0);
    final tytYer = (tytHam + obp).clamp(100.0, 560.0);

    double aytPart = 0;
    if (fieldType == 'SAY') {
      aytPart =
          aytMat.clamp(0, 40) * 3.00 +
          aytFizik.clamp(0, 14) * 2.85 +
          aytKimya.clamp(0, 13) * 3.07 +
          aytBiyoloji.clamp(0, 13) * 3.07;
    } else if (fieldType == 'EA') {
      aytPart =
          aytMat.clamp(0, 40) * 3.00 + aytEdebiyatSos1.clamp(0, 40) * 3.00;
    } else if (fieldType == 'SOZ') {
      aytPart =
          aytEdebiyatSos1.clamp(0, 40) * 3.00 + aytSos2.clamp(0, 40) * 3.00;
    } else {
      aytPart = ydtDil.clamp(0, 80) * 3.00;
    }

    // YKS: %40 TYT + %60 AYT birleşik modeli
    final tytContribution = 100.0 + (tytHam - 100.0) * 0.40;
    final aytHam = (tytContribution + aytPart).clamp(100.0, 500.0);
    final aytYer = (aytHam + obp).clamp(100.0, 560.0);

    int estimateYksRank(double yerScore, {required bool isTyt}) {
      if (yerScore >= 545) return 250;
      if (yerScore >= 530) return 1500;
      if (yerScore >= 515) return 5200;
      if (yerScore >= 500) return 12500;
      if (yerScore >= 480) return 28000;
      if (yerScore >= 460) return 52000;
      if (yerScore >= 435) return 95000;
      if (yerScore >= 405) return 165000;
      if (yerScore >= 370) return 290000;
      if (yerScore >= 330) return 490000;
      if (yerScore >= 280) return 850000;
      return isTyt ? 1450000 : 1100000;
    }

    final tytRank = estimateYksRank(tytYer, isTyt: true);
    final aytRank = estimateYksRank(aytYer, isTyt: false);

    String band;
    if (aytRank <= 5000) {
      band =
          'İlk 5.000 Bandı (Tıp / Üst Düzey Mühendislik / Hukuk / Boğaziçi-ODTÜ-İTÜ)';
    } else if (aytRank <= 25000) {
      band =
          'İlk 25.000 Bandı (Tıp / Diş / Seçkin Mühendislik / Hukuk / Psikoloji)';
    } else if (aytRank <= 60000) {
      band =
          'İlk 60.000 Bandı (Eczacılık / Mühendislik / Mimarlık / Eğitim / İİBF)';
    } else if (aytRank <= 150000) {
      band = 'İlk 150.000 Bandı (Devlet & Burslu Vakıf Lisans Programları)';
    } else {
      band =
          'Gelişim Bandı (TYT Hız + AYT Konu Eksiklerini Kapatma Odaklı Plan)';
    }

    return (
      tytHam: tytHam,
      tytYerlestirme: tytYer,
      tytRank: tytRank,
      aytHam: aytHam,
      aytYerlestirme: aytYer,
      aytRank: aytRank,
      obpContribution: obp,
      targetBand: band,
    );
  }

  /// Normal dağılım kuyruk olasılığı P(X >= threshold), X ~ N(mean, stdDev^2)
  /// Abramowitz & Stegun erf yaklaşımı ile 0.0 - 100.0 arasında yüzde döner.
  static double normalSurvivalProbability({
    required double mean,
    required double stdDev,
    required double threshold,
  }) {
    final sigma = math.max(1.0, stdDev);
    final z = (threshold - mean) / (sigma * math.sqrt2);
    final p = 0.5 * _erfc(z);
    return (p * 100.0).clamp(0.1, 99.6);
  }

  static double _erfc(double x) {
    final z = x.abs();
    final t = 1.0 / (1.0 + 0.5 * z);
    final ans =
        t *
        math.exp(
          -z * z -
              1.26551223 +
              t *
                  (1.00002368 +
                      t *
                          (0.37409196 +
                              t *
                                  (0.09678418 +
                                      t *
                                          (-0.18628806 +
                                              t *
                                                  (0.27886807 +
                                                      t *
                                                          (-1.13520398 +
                                                              t *
                                                                  (1.48851587 +
                                                                      t *
                                                                          (-0.82215223 +
                                                                              t * 0.17087277)))))))),
        );
    return x >= 0 ? ans : 2.0 - ans;
  }

  /// LGS puanından Türkiye yüzdelik dilimini enterpolasyonla hesaplar (`lgs_data.dart`)
  static double lgsPercentileFromScore(
    double score, {
    String referenceYear = '2026',
  }) {
    final clamped = score.clamp(194.75, 500.0);
    if (clamped >= 499.95) return 0.01;
    final table = lgsPercentiles[referenceYear] ?? lgsPercentiles['2026']!;
    for (final r in table) {
      if (clamped >= r.minScore && clamped <= r.maxScore) {
        final ratio =
            (r.maxScore - clamped) / math.max(0.001, (r.maxScore - r.minScore));
        return (r.minPercentile + ratio * (r.maxPercentile - r.minPercentile))
            .clamp(0.01, 99.0);
      }
    }
    return clamped < 200 ? 96.0 : 50.0;
  }

  /// YKS 500 ölçekli ham/yerleştirme puanından yaklaşık Türkiye sıralaması ve yüzdelik dilim döner
  static ({double percentile, int estimatedRank}) yksPercentileFromScore(
    double score500,
  ) {
    final s = score500.clamp(120.0, 500.0);
    // Yaklaşık 2.850.000 aday üzerinden kalibre ÖSYM eğrisi
    const totalCandidates = 2850000;
    int rank;
    if (s >= 492) {
      rank = (1 + ((500.0 - s) / 8.0) * 450).round();
    } else if (s >= 478) {
      rank = (450 + ((492.0 - s) / 14.0) * 1850).round();
    } else if (s >= 455) {
      rank = (2300 + ((478.0 - s) / 23.0) * 9700).round();
    } else if (s >= 425) {
      rank = (12000 + ((455.0 - s) / 30.0) * 28000).round();
    } else if (s >= 390) {
      rank = (40000 + ((425.0 - s) / 35.0) * 55000).round();
    } else if (s >= 350) {
      rank = (95000 + ((390.0 - s) / 40.0) * 115000).round();
    } else if (s >= 300) {
      rank = (210000 + ((350.0 - s) / 50.0) * 250000).round();
    } else if (s >= 240) {
      rank = (460000 + ((300.0 - s) / 60.0) * 520000).round();
    } else {
      rank = (980000 + ((240.0 - s) / 120.0) * 1400000).round();
    }
    final safeRank = rank.clamp(1, totalCandidates);
    final pct = ((safeRank / totalCandidates) * 100.0).clamp(0.01, 99.5);
    return (percentile: pct, estimatedRank: safeRank);
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// AKADEMİK ÖLÇME VE BAŞARI TAKİBİ — KURUMSAL PDF RAPOR ÜRETİCİ
/// ═══════════════════════════════════════════════════════════════════════════
class AcademicTrackingPdfService {
  static Future<void> printTableReport({
    required String documentTitle,
    required String schoolName,
    required String subtitle,
    required List<({String label, String value})> kpis,
    required List<String> headers,
    required List<List<String>> rows,
    List<String> notes = const [],
    bool landscape = false,
  }) async {
    final fonts = await Future.wait([
      PdfService.getFont(),
      PdfService.getFontBold(),
    ]);
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: fonts[0], bold: fonts[1]),
    );

    final navy = PdfColor.fromHex('#0F172A');
    final accent = PdfColor.fromHex('#4F46E5');
    final lightBg = PdfColor.fromHex('#F8FAFC');
    final border = PdfColor.fromHex('#CBD5E1');
    final nowStr = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (_) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: lightBg,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: border, width: 0.7),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        schoolName.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: accent,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        documentTitle,
                        style: pw.TextStyle(
                          fontSize: 13.5,
                          fontWeight: pw.FontWeight.bold,
                          color: navy,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        subtitle,
                        style: pw.TextStyle(
                          fontSize: 8.8,
                          color: PdfColor.fromHex('#475569'),
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Text(
                  'Rapor Tarihi\n$nowStr',
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: navy,
                  ),
                ),
              ],
            ),
          ),
          if (kpis.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Row(
              children: kpis
                  .map(
                    (k) => pw.Expanded(
                      child: pw.Container(
                        margin: const pw.EdgeInsets.only(right: 6),
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 7,
                        ),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: border, width: 0.6),
                          borderRadius: pw.BorderRadius.circular(6),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              k.label,
                              style: pw.TextStyle(
                                fontSize: 7.5,
                                color: PdfColor.fromHex('#64748B'),
                              ),
                            ),
                            pw.SizedBox(height: 2),
                            pw.Text(
                              k.value,
                              style: pw.TextStyle(
                                fontSize: 10.5,
                                fontWeight: pw.FontWeight.bold,
                                color: navy,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          pw.SizedBox(height: 12),
          if (rows.isNotEmpty)
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(color: border, width: 0.5),
              headerDecoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#EEF2FF'),
              ),
              headerStyle: pw.TextStyle(
                fontSize: 8.2,
                fontWeight: pw.FontWeight.bold,
                color: navy,
              ),
              cellStyle: const pw.TextStyle(fontSize: 7.8),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 4.5,
              ),
              headers: headers,
              data: rows,
            ),
          if (notes.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: lightBg,
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: border, width: 0.5),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Değerlendirme Notları ve Eylem Önerileri:',
                    style: pw.TextStyle(
                      fontSize: 8.8,
                      fontWeight: pw.FontWeight.bold,
                      color: navy,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  ...notes.map(
                    (n) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 2.5),
                      child: pw.Text(
                        '• $n',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    final Uint8List bytes = await pdf.save();
    final safeTitle = documentTitle
        .replaceAll(RegExp(r'[^a-zA-Z0-9ğüşöçıİĞÜŞÖÇ\s_-]'), '')
        .trim()
        .replaceAll(' ', '_');
    await Printing.layoutPdf(
      name: '${safeTitle}_${DateFormat("yyyyMMdd").format(DateTime.now())}.pdf',
      onLayout: (_) async => bytes,
    );
  }
}
