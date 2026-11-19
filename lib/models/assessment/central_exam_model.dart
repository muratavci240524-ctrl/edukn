import 'package:cloud_firestore/cloud_firestore.dart';

class CentralExamTarget {
  final String schoolId;
  final String institutionId;
  final String schoolName;
  final String schoolTypeId;
  final String schoolTypeName;
  final String schoolTypeCategory;
  final String city;
  final String district;
  final String region;
  final String childTrialExamId;

  const CentralExamTarget({
    required this.schoolId,
    required this.institutionId,
    required this.schoolName,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.schoolTypeCategory,
    this.city = '',
    this.district = '',
    this.region = 'Belirtilmemiş',
    required this.childTrialExamId,
  });

  static String buildChildDocId(String centralExamId, String schoolTypeId) {
    return 'central_${centralExamId}_$schoolTypeId';
  }

  static String inferCategory(
    String schoolTypeName, [
    List<String> activeGrades = const [],
  ]) {
    final lower = schoolTypeName
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .toLowerCase();
    if (lower.contains('ortaokul') || lower.contains('imam hatip orta')) {
      return 'Ortaokul';
    }
    if (lower.contains('lise') ||
        lower.contains('anadolu') ||
        lower.contains('fen')) {
      return 'Lise';
    }
    if (lower.contains('ilkokul')) {
      return 'İlkokul';
    }
    if (lower.contains('anaokul') ||
        lower.contains('kreş') ||
        lower.contains('anasınıf')) {
      return 'Anaokulu';
    }
    if (lower.contains('kurs') || lower.contains('etüt')) {
      return 'Kurs Merkezi';
    }

    final gradeNums = activeGrades
        .map((g) => int.tryParse(g.replaceAll(RegExp(r'[^0-9]'), '')))
        .whereType<int>()
        .toList();
    if (gradeNums.any((g) => g >= 9 && g <= 12)) return 'Lise';
    if (gradeNums.any((g) => g >= 5 && g <= 8)) return 'Ortaokul';
    if (gradeNums.any((g) => g >= 1 && g <= 4)) return 'İlkokul';
    return 'Diğer';
  }

  Map<String, dynamic> toMap() {
    return {
      'schoolId': schoolId,
      'institutionId': institutionId,
      'schoolName': schoolName,
      'schoolTypeId': schoolTypeId,
      'schoolTypeName': schoolTypeName,
      'schoolTypeCategory': schoolTypeCategory,
      'city': city,
      'district': district,
      'region': region,
      'childTrialExamId': childTrialExamId,
    };
  }

  factory CentralExamTarget.fromMap(Map<String, dynamic> map) {
    final stName = (map['schoolTypeName'] ?? '').toString();
    final rawCat = (map['schoolTypeCategory'] ?? '').toString();
    return CentralExamTarget(
      schoolId: (map['schoolId'] ?? '').toString(),
      institutionId: (map['institutionId'] ?? '').toString(),
      schoolName: (map['schoolName'] ?? '').toString(),
      schoolTypeId: (map['schoolTypeId'] ?? '').toString(),
      schoolTypeName: stName,
      schoolTypeCategory: rawCat.isNotEmpty ? rawCat : inferCategory(stName),
      city: (map['city'] ?? '').toString(),
      district: (map['district'] ?? '').toString(),
      region: (map['region'] ?? 'Belirtilmemiş').toString(),
      childTrialExamId: (map['childTrialExamId'] ?? '').toString(),
    );
  }

  CentralExamTarget copyWith({
    String? schoolId,
    String? institutionId,
    String? schoolName,
    String? schoolTypeId,
    String? schoolTypeName,
    String? schoolTypeCategory,
    String? city,
    String? district,
    String? region,
    String? childTrialExamId,
  }) {
    return CentralExamTarget(
      schoolId: schoolId ?? this.schoolId,
      institutionId: institutionId ?? this.institutionId,
      schoolName: schoolName ?? this.schoolName,
      schoolTypeId: schoolTypeId ?? this.schoolTypeId,
      schoolTypeName: schoolTypeName ?? this.schoolTypeName,
      schoolTypeCategory: schoolTypeCategory ?? this.schoolTypeCategory,
      city: city ?? this.city,
      district: district ?? this.district,
      region: region ?? this.region,
      childTrialExamId: childTrialExamId ?? this.childTrialExamId,
    );
  }
}

class CentralExam {
  final String id;
  final String name;
  final String classLevel;
  final String examTypeId;
  final String examTypeName;
  final int bookletCount;
  final int sessionCount;
  final int durationMinutes;
  final DateTime date;
  final Map<String, Map<String, String>> answerKeys;
  final Map<String, Map<String, List<String>>> outcomes;
  final Map<String, Map<String, String>> bookletMapping;
  final List<CentralExamTarget> targets;
  final bool isPublished;
  final String status; // 'draft' | 'assigned' | 'evaluated'
  final int totalParticipants;
  final int participatingSchoolsCount;
  final DateTime? lastEvaluatedAt;
  final Map<String, dynamic> analyticsSummary;
  final String? termId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CentralExam({
    required this.id,
    required this.name,
    required this.classLevel,
    required this.examTypeId,
    required this.examTypeName,
    this.bookletCount = 2,
    this.sessionCount = 1,
    this.durationMinutes = 120,
    required this.date,
    this.answerKeys = const {},
    this.outcomes = const {},
    this.bookletMapping = const {},
    this.targets = const [],
    this.isPublished = false,
    this.status = 'draft',
    this.totalParticipants = 0,
    this.participatingSchoolsCount = 0,
    this.lastEvaluatedAt,
    this.analyticsSummary = const {},
    this.termId,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'classLevel': classLevel,
      'examTypeId': examTypeId,
      'examTypeName': examTypeName,
      'bookletCount': bookletCount,
      'sessionCount': sessionCount,
      'durationMinutes': durationMinutes,
      'date': Timestamp.fromDate(date),
      'answerKeys': answerKeys,
      'outcomes': outcomes,
      'bookletMapping': bookletMapping,
      'targets': targets.map((t) => t.toMap()).toList(),
      'isPublished': isPublished,
      'status': status,
      'totalParticipants': totalParticipants,
      'participatingSchoolsCount': participatingSchoolsCount,
      if (lastEvaluatedAt != null)
        'lastEvaluatedAt': Timestamp.fromDate(lastEvaluatedAt!),
      'analyticsSummary': analyticsSummary,
      if (termId != null) 'termId': termId,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory CentralExam.fromMap(Map<String, dynamic> map, String id) {
    final Map<String, Map<String, String>> parsedKeys = {};
    if (map['answerKeys'] is Map) {
      (map['answerKeys'] as Map).forEach((booklet, subjects) {
        if (subjects is Map) {
          parsedKeys[booklet.toString()] = subjects.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          );
        }
      });
    }

    final Map<String, Map<String, List<String>>> parsedOutcomes = {};
    if (map['outcomes'] is Map) {
      (map['outcomes'] as Map).forEach((booklet, subjects) {
        if (subjects is Map) {
          final Map<String, List<String>> subMap = {};
          subjects.forEach((subj, list) {
            if (list is List) {
              subMap[subj.toString()] = list.map((e) => e.toString()).toList();
            }
          });
          parsedOutcomes[booklet.toString()] = subMap;
        }
      });
    }

    final Map<String, Map<String, String>> parsedMapping = {};
    if (map['bookletMapping'] is Map) {
      (map['bookletMapping'] as Map).forEach((booklet, subjects) {
        if (subjects is Map) {
          parsedMapping[booklet.toString()] = subjects.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          );
        }
      });
    }

    final List<CentralExamTarget> parsedTargets =
        (map['targets'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map((e) => CentralExamTarget.fromMap(Map<String, dynamic>.from(e)))
            .toList();

    return CentralExam(
      id: id,
      name: (map['name'] ?? '').toString(),
      classLevel: (map['classLevel'] ?? '').toString(),
      examTypeId: (map['examTypeId'] ?? '').toString(),
      examTypeName: (map['examTypeName'] ?? '').toString(),
      bookletCount: (map['bookletCount'] as num?)?.toInt() ?? 1,
      sessionCount: (map['sessionCount'] as num?)?.toInt() ?? 1,
      durationMinutes: (map['durationMinutes'] as num?)?.toInt() ?? 0,
      date: (map['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      answerKeys: parsedKeys,
      outcomes: parsedOutcomes,
      bookletMapping: parsedMapping,
      targets: parsedTargets,
      isPublished: map['isPublished'] == true,
      status: (map['status'] ?? 'draft').toString(),
      totalParticipants: (map['totalParticipants'] as num?)?.toInt() ?? 0,
      participatingSchoolsCount:
          (map['participatingSchoolsCount'] as num?)?.toInt() ?? 0,
      lastEvaluatedAt: (map['lastEvaluatedAt'] as Timestamp?)?.toDate(),
      analyticsSummary: map['analyticsSummary'] is Map
          ? Map<String, dynamic>.from(map['analyticsSummary'] as Map)
          : const {},
      termId: map['termId']?.toString(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  CentralExam copyWith({
    String? id,
    String? name,
    String? classLevel,
    String? examTypeId,
    String? examTypeName,
    int? bookletCount,
    int? sessionCount,
    int? durationMinutes,
    DateTime? date,
    Map<String, Map<String, String>>? answerKeys,
    Map<String, Map<String, List<String>>>? outcomes,
    Map<String, Map<String, String>>? bookletMapping,
    List<CentralExamTarget>? targets,
    bool? isPublished,
    String? status,
    int? totalParticipants,
    int? participatingSchoolsCount,
    DateTime? lastEvaluatedAt,
    Map<String, dynamic>? analyticsSummary,
    String? termId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CentralExam(
      id: id ?? this.id,
      name: name ?? this.name,
      classLevel: classLevel ?? this.classLevel,
      examTypeId: examTypeId ?? this.examTypeId,
      examTypeName: examTypeName ?? this.examTypeName,
      bookletCount: bookletCount ?? this.bookletCount,
      sessionCount: sessionCount ?? this.sessionCount,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      date: date ?? this.date,
      answerKeys: answerKeys ?? this.answerKeys,
      outcomes: outcomes ?? this.outcomes,
      bookletMapping: bookletMapping ?? this.bookletMapping,
      targets: targets ?? this.targets,
      isPublished: isPublished ?? this.isPublished,
      status: status ?? this.status,
      totalParticipants: totalParticipants ?? this.totalParticipants,
      participatingSchoolsCount:
          participatingSchoolsCount ?? this.participatingSchoolsCount,
      lastEvaluatedAt: lastEvaluatedAt ?? this.lastEvaluatedAt,
      analyticsSummary: analyticsSummary ?? this.analyticsSummary,
      termId: termId ?? this.termId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class WeakOutcomeNeed {
  final String subject;
  final String outcome;
  final int questionCount;
  final double schoolSuccessRate;
  final double regionSuccessRate;
  final double generalSuccessRate;
  final String priority; // 'ACİL DESTEK' | 'GELİŞTİRİLMELİ'

  const WeakOutcomeNeed({
    required this.subject,
    required this.outcome,
    this.questionCount = 1,
    required this.schoolSuccessRate,
    this.regionSuccessRate = 0.0,
    required this.generalSuccessRate,
    required this.priority,
  });

  double get deltaFromGeneral => schoolSuccessRate - generalSuccessRate;

  Map<String, dynamic> toMap() {
    return {
      'subject': subject,
      'outcome': outcome,
      'questionCount': questionCount,
      'schoolSuccessRate': schoolSuccessRate,
      'regionSuccessRate': regionSuccessRate,
      'generalSuccessRate': generalSuccessRate,
      'priority': priority,
    };
  }

  factory WeakOutcomeNeed.fromMap(Map<String, dynamic> map) {
    final schoolRate = (map['schoolSuccessRate'] as num?)?.toDouble() ?? 0.0;
    final genRate = (map['generalSuccessRate'] as num?)?.toDouble() ?? 0.0;
    final rawPriority = (map['priority'] ?? '').toString();
    return WeakOutcomeNeed(
      subject: (map['subject'] ?? '').toString(),
      outcome: (map['outcome'] ?? '').toString(),
      questionCount: (map['questionCount'] as num?)?.toInt() ?? 1,
      schoolSuccessRate: schoolRate,
      regionSuccessRate: (map['regionSuccessRate'] as num?)?.toDouble() ?? 0.0,
      generalSuccessRate: genRate,
      priority: rawPriority.isNotEmpty
          ? rawPriority
          : (schoolRate < 40.0 || (schoolRate - genRate) <= -15.0
                ? 'ACİL DESTEK'
                : 'GELİŞTİRİLMELİ'),
    );
  }
}

class CentralSchoolReport {
  final String id;
  final String centralExamId;
  final String centralExamName;
  final String classLevel;
  final String examTypeName;
  final DateTime examDate;
  final String schoolId;
  final String institutionId;
  final String schoolName;
  final String schoolTypeId;
  final String schoolTypeName;
  final String city;
  final String region;
  final DateTime createdAt;

  // Comparative stats
  final int participantCount;
  final int generalParticipantCount;
  final double schoolAvgScore;
  final double regionAvgScore;
  final double generalAvgScore;
  final double schoolMaxScore;
  final int schoolRank;
  final int totalParticipatingSchools;

  // Subject comparisons: {subject, questionCount, schoolNet, regionNet, generalNet, schoolSuccessRate, generalSuccessRate, diffNet}
  final List<Map<String, dynamic>> subjectComparisons;

  // Priority weak outcomes
  final List<WeakOutcomeNeed> ihtiyacAnalizi;

  // HQ Commentary & Recommendations
  final String advisorNote;
  final List<String> actionRecommendations;

  const CentralSchoolReport({
    required this.id,
    required this.centralExamId,
    required this.centralExamName,
    this.classLevel = '',
    this.examTypeName = '',
    required this.examDate,
    required this.schoolId,
    required this.institutionId,
    required this.schoolName,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.city = '',
    this.region = 'Belirtilmemiş',
    required this.createdAt,
    this.participantCount = 0,
    this.generalParticipantCount = 0,
    this.schoolAvgScore = 0.0,
    this.regionAvgScore = 0.0,
    this.generalAvgScore = 0.0,
    this.schoolMaxScore = 0.0,
    this.schoolRank = 0,
    this.totalParticipatingSchools = 0,
    this.subjectComparisons = const [],
    this.ihtiyacAnalizi = const [],
    this.advisorNote = '',
    this.actionRecommendations = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'centralExamId': centralExamId,
      'centralExamName': centralExamName,
      'classLevel': classLevel,
      'examTypeName': examTypeName,
      'examDate': Timestamp.fromDate(examDate),
      'schoolId': schoolId,
      'institutionId': institutionId,
      'institution_id': institutionId,
      'schoolName': schoolName,
      'schoolTypeId': schoolTypeId,
      'schoolTypeName': schoolTypeName,
      'city': city,
      'region': region,
      'createdAt': Timestamp.fromDate(createdAt),
      'participantCount': participantCount,
      'generalParticipantCount': generalParticipantCount,
      'schoolAvgScore': schoolAvgScore,
      'regionAvgScore': regionAvgScore,
      'generalAvgScore': generalAvgScore,
      'schoolMaxScore': schoolMaxScore,
      'schoolRank': schoolRank,
      'totalParticipatingSchools': totalParticipatingSchools,
      'subjectComparisons': subjectComparisons,
      'ihtiyacAnalizi': ihtiyacAnalizi.map((e) => e.toMap()).toList(),
      'advisorNote': advisorNote,
      'actionRecommendations': actionRecommendations,
    };
  }

  factory CentralSchoolReport.fromMap(Map<String, dynamic> map, String id) {
    return CentralSchoolReport(
      id: id,
      centralExamId: (map['centralExamId'] ?? '').toString(),
      centralExamName: (map['centralExamName'] ?? '').toString(),
      classLevel: (map['classLevel'] ?? '').toString(),
      examTypeName: (map['examTypeName'] ?? '').toString(),
      examDate: (map['examDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      schoolId: (map['schoolId'] ?? '').toString(),
      institutionId: (map['institutionId'] ?? map['institution_id'] ?? '')
          .toString(),
      schoolName: (map['schoolName'] ?? '').toString(),
      schoolTypeId: (map['schoolTypeId'] ?? '').toString(),
      schoolTypeName: (map['schoolTypeName'] ?? '').toString(),
      city: (map['city'] ?? '').toString(),
      region: (map['region'] ?? 'Belirtilmemiş').toString(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      participantCount: (map['participantCount'] as num?)?.toInt() ?? 0,
      generalParticipantCount:
          (map['generalParticipantCount'] as num?)?.toInt() ?? 0,
      schoolAvgScore: (map['schoolAvgScore'] as num?)?.toDouble() ?? 0.0,
      regionAvgScore: (map['regionAvgScore'] as num?)?.toDouble() ?? 0.0,
      generalAvgScore: (map['generalAvgScore'] as num?)?.toDouble() ?? 0.0,
      schoolMaxScore: (map['schoolMaxScore'] as num?)?.toDouble() ?? 0.0,
      schoolRank: (map['schoolRank'] as num?)?.toInt() ?? 0,
      totalParticipatingSchools:
          (map['totalParticipatingSchools'] as num?)?.toInt() ?? 0,
      subjectComparisons: (map['subjectComparisons'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      ihtiyacAnalizi: (map['ihtiyacAnalizi'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => WeakOutcomeNeed.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      advisorNote: (map['advisorNote'] ?? '').toString(),
      actionRecommendations:
          (map['actionRecommendations'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
    );
  }

  CentralSchoolReport copyWith({
    String? advisorNote,
    List<String>? actionRecommendations,
    DateTime? createdAt,
  }) {
    return CentralSchoolReport(
      id: id,
      centralExamId: centralExamId,
      centralExamName: centralExamName,
      classLevel: classLevel,
      examTypeName: examTypeName,
      examDate: examDate,
      schoolId: schoolId,
      institutionId: institutionId,
      schoolName: schoolName,
      schoolTypeId: schoolTypeId,
      schoolTypeName: schoolTypeName,
      city: city,
      region: region,
      createdAt: createdAt ?? this.createdAt,
      participantCount: participantCount,
      generalParticipantCount: generalParticipantCount,
      schoolAvgScore: schoolAvgScore,
      regionAvgScore: regionAvgScore,
      generalAvgScore: generalAvgScore,
      schoolMaxScore: schoolMaxScore,
      schoolRank: schoolRank,
      totalParticipatingSchools: totalParticipatingSchools,
      subjectComparisons: subjectComparisons,
      ihtiyacAnalizi: ihtiyacAnalizi,
      advisorNote: advisorNote ?? this.advisorNote,
      actionRecommendations:
          actionRecommendations ?? this.actionRecommendations,
    );
  }
}
