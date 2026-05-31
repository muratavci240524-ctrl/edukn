import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────── ENUMS ───────────────────────────────────────────────────────

enum ExamType { bursluluk, provaDeneme, diger }

enum SeatingMode { noSeating, butterfly, simpleRandom }

// ─────────────── SCHOLARSHIP ─────────────────────────────────────────────────

class ScholarshipTier {
  final int minRank;
  final int maxRank;
  final int rate; // percentage: 100, 80, 60...

  const ScholarshipTier({
    required this.minRank,
    required this.maxRank,
    required this.rate,
  });

  Map<String, dynamic> toMap() => {
        'minRank': minRank,
        'maxRank': maxRank,
        'rate': rate,
      };

  factory ScholarshipTier.fromMap(Map<String, dynamic> map) => ScholarshipTier(
        minRank: map['minRank'] ?? 1,
        maxRank: map['maxRank'] ?? 1,
        rate: map['rate'] ?? 0,
      );

  String get displayText => '$minRank – $maxRank. arası: %$rate Burs';
}

// ─────────────── VENUE / CLASSROOM ──────────────────────────────────────────

class RoomSlot {
  final String classroomId;
  final String classroomName;
  final String classroomCode;
  final int originalCapacity;
  final int? overrideCapacity;
  final String? building;

  const RoomSlot({
    required this.classroomId,
    required this.classroomName,
    required this.classroomCode,
    required this.originalCapacity,
    this.overrideCapacity,
    this.building,
  });

  int get effectiveCapacity => overrideCapacity ?? originalCapacity;

  Map<String, dynamic> toMap() => {
        'classroomId': classroomId,
        'classroomName': classroomName,
        'classroomCode': classroomCode,
        'originalCapacity': originalCapacity,
        'overrideCapacity': overrideCapacity,
        'building': building,
      };

  factory RoomSlot.fromMap(Map<String, dynamic> map) => RoomSlot(
        classroomId: map['classroomId'] ?? '',
        classroomName: map['classroomName'] ?? '',
        classroomCode: map['classroomCode'] ?? '',
        originalCapacity: map['originalCapacity'] ?? 0,
        overrideCapacity: map['overrideCapacity'],
        building: map['building'],
      );

  RoomSlot copyWith({int? overrideCapacity}) => RoomSlot(
        classroomId: classroomId,
        classroomName: classroomName,
        classroomCode: classroomCode,
        originalCapacity: originalCapacity,
        overrideCapacity: overrideCapacity ?? this.overrideCapacity,
        building: building,
      );
}

class GradeClassroomAssignment {
  final String gradeLevel;
  final List<RoomSlot> rooms;

  const GradeClassroomAssignment({
    required this.gradeLevel,
    required this.rooms,
  });

  int get totalCapacity => rooms.fold(0, (acc, r) => acc + r.effectiveCapacity);

  Map<String, dynamic> toMap() => {
        'gradeLevel': gradeLevel,
        'rooms': rooms.map((r) => r.toMap()).toList(),
      };

  factory GradeClassroomAssignment.fromMap(Map<String, dynamic> map) =>
      GradeClassroomAssignment(
        gradeLevel: map['gradeLevel'] ?? '',
        rooms: (map['rooms'] as List<dynamic>? ?? [])
            .map((r) => RoomSlot.fromMap(r as Map<String, dynamic>))
            .toList(),
      );
}

class VenueConfig {
  final SeatingMode seatingMode;
  final List<String> schoolTypeIds;
  final List<GradeClassroomAssignment> classroomAssignments;

  const VenueConfig({
    required this.seatingMode,
    required this.schoolTypeIds,
    required this.classroomAssignments,
  });

  static SeatingMode _modeFromString(String? s) {
    switch (s) {
      case 'butterfly':
        return SeatingMode.butterfly;
      case 'simple_random':
        return SeatingMode.simpleRandom;
      default:
        return SeatingMode.noSeating;
    }
  }

  static String _modeToString(SeatingMode m) {
    switch (m) {
      case SeatingMode.butterfly:
        return 'butterfly';
      case SeatingMode.simpleRandom:
        return 'simple_random';
      case SeatingMode.noSeating:
        return 'no_seating';
    }
  }

  Map<String, dynamic> toMap() => {
        'seatingMode': _modeToString(seatingMode),
        'schoolTypeIds': schoolTypeIds,
        'classroomAssignments':
            classroomAssignments.map((a) => a.toMap()).toList(),
      };

  factory VenueConfig.fromMap(Map<String, dynamic> map) => VenueConfig(
        seatingMode: _modeFromString(map['seatingMode']),
        schoolTypeIds: List<String>.from(map['schoolTypeIds'] ?? []),
        classroomAssignments:
            (map['classroomAssignments'] as List<dynamic>? ?? [])
                .map((a) =>
                    GradeClassroomAssignment.fromMap(a as Map<String, dynamic>))
                .toList(),
      );

  VenueConfig get empty => const VenueConfig(
        seatingMode: SeatingMode.noSeating,
        schoolTypeIds: [],
        classroomAssignments: [],
      );
}

// ─────────────── APPLICATION SESSION ─────────────────────────────────────────

class ApplicationSession {
  final String id;
  final DateTime sessionDate;
  final String startTime;
  final String endTime;
  final List<String> gradeLevels;
  final Map<String, int> gradeLevelQuotas; // gradeLevel -> quota count

  const ApplicationSession({
    required this.id,
    required this.sessionDate,
    required this.startTime,
    required this.endTime,
    required this.gradeLevels,
    required this.gradeLevelQuotas,
  });

  String get displayTime => '$startTime – $endTime';

  int quotaForGrade(String grade) => gradeLevelQuotas[grade] ?? 0;

  Map<String, dynamic> toMap() => {
        'id': id,
        'sessionDate': Timestamp.fromDate(sessionDate),
        'startTime': startTime,
        'endTime': endTime,
        'gradeLevels': gradeLevels,
        'gradeLevelQuotas': gradeLevelQuotas,
      };

  factory ApplicationSession.fromMap(Map<String, dynamic> map) =>
      ApplicationSession(
        id: map['id'] ?? '',
        sessionDate:
            (map['sessionDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
        startTime: map['startTime'] ?? '',
        endTime: map['endTime'] ?? '',
        gradeLevels: List<String>.from(map['gradeLevels'] ?? []),
        gradeLevelQuotas: Map<String, int>.from(
          (map['gradeLevelQuotas'] as Map<String, dynamic>? ?? {})
              .map((k, v) => MapEntry(k, (v as num).toInt())),
        ),
      );
}

// ─────────────── EXTERNAL EXAM ───────────────────────────────────────────────

class ExternalExam {
  final String? id;
  final String institutionId;
  final String schoolId;
  final String title;
  final ExamType examType;
  final List<String> gradeLevels;
  final Map<String, String> trialExamIds; // gradeLevel -> trialExamId
  final List<ApplicationSession> applicationSessions;
  final VenueConfig venueConfig;
  final bool scholarshipEnabled;
  final Map<String, List<ScholarshipTier>> scholarshipConfig;
  final String? regulationUrl;
  final DateTime? regulationPublishDate;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const ExternalExam({
    this.id,
    required this.institutionId,
    required this.schoolId,
    required this.title,
    required this.examType,
    required this.gradeLevels,
    required this.trialExamIds,
    required this.applicationSessions,
    required this.venueConfig,
    required this.scholarshipEnabled,
    required this.scholarshipConfig,
    this.regulationUrl,
    this.regulationPublishDate,
    required this.isActive,
    required this.createdAt,
    this.updatedAt,
  });

  String get examTypeName {
    switch (examType) {
      case ExamType.bursluluk:
        return 'Bursluluk Sınavı';
      case ExamType.provaDeneme:
        return 'Prova / Deneme Sınavı';
      case ExamType.diger:
        return 'Diğer';
    }
  }

  static ExamType _typeFromString(String? s) {
    switch (s) {
      case 'bursluluk':
        return ExamType.bursluluk;
      case 'prova_deneme':
        return ExamType.provaDeneme;
      default:
        return ExamType.diger;
    }
  }

  static String _typeToString(ExamType t) {
    switch (t) {
      case ExamType.bursluluk:
        return 'bursluluk';
      case ExamType.provaDeneme:
        return 'prova_deneme';
      case ExamType.diger:
        return 'diger';
    }
  }

  Map<String, dynamic> toMap() {
    final scholarshipMap = <String, dynamic>{};
    scholarshipConfig.forEach((grade, tiers) {
      scholarshipMap[grade] = tiers.map((t) => t.toMap()).toList();
    });

    return {
      'institutionId': institutionId,
      'schoolId': schoolId,
      'title': title,
      'examType': _typeToString(examType),
      'gradeLevels': gradeLevels,
      'trialExamIds': trialExamIds,
      'applicationSessions':
          applicationSessions.map((s) => s.toMap()).toList(),
      'venueConfig': venueConfig.toMap(),
      'scholarshipEnabled': scholarshipEnabled,
      'scholarshipConfig': scholarshipMap,
      'regulationUrl': regulationUrl,
      'regulationPublishDate': regulationPublishDate != null
          ? Timestamp.fromDate(regulationPublishDate!)
          : null,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory ExternalExam.fromMap(Map<String, dynamic> map, String id) {
    // Parse scholarshipConfig
    final rawScholarship =
        map['scholarshipConfig'] as Map<String, dynamic>? ?? {};
    final scholarshipConfig = <String, List<ScholarshipTier>>{};
    rawScholarship.forEach((grade, tiers) {
      scholarshipConfig[grade] = (tiers as List<dynamic>)
          .map((t) => ScholarshipTier.fromMap(t as Map<String, dynamic>))
          .toList();
    });

    return ExternalExam(
      id: id,
      institutionId: map['institutionId'] ?? '',
      schoolId: map['schoolId'] ?? '',
      title: map['title'] ?? '',
      examType: _typeFromString(map['examType']),
      gradeLevels: List<String>.from(map['gradeLevels'] ?? []),
      trialExamIds: Map<String, String>.from(map['trialExamIds'] ?? {}),
      applicationSessions:
          (map['applicationSessions'] as List<dynamic>? ?? [])
              .map((s) =>
                  ApplicationSession.fromMap(s as Map<String, dynamic>))
              .toList(),
      venueConfig: map['venueConfig'] != null
          ? VenueConfig.fromMap(map['venueConfig'] as Map<String, dynamic>)
          : const VenueConfig(
              seatingMode: SeatingMode.noSeating,
              schoolTypeIds: [],
              classroomAssignments: [],
            ),
      scholarshipEnabled: map['scholarshipEnabled'] ?? false,
      scholarshipConfig: scholarshipConfig,
      regulationUrl: map['regulationUrl'],
      regulationPublishDate:
          (map['regulationPublishDate'] as Timestamp?)?.toDate(),
      isActive: map['isActive'] ?? true,
      createdAt:
          (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
