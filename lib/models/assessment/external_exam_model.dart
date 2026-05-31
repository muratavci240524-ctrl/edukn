import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _parseDateTime(dynamic val) {
  if (val == null) return null;
  if (val is Timestamp) return val.toDate();
  if (val is String) return DateTime.tryParse(val);
  return null;
}

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
        minRank: (map['minRank'] as num?)?.toInt() ?? 1,
        maxRank: (map['maxRank'] as num?)?.toInt() ?? 1,
        rate: (map['rate'] as num?)?.toInt() ?? 0,
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
        originalCapacity: (map['originalCapacity'] as num?)?.toInt() ?? 0,
        overrideCapacity: (map['overrideCapacity'] as num?)?.toInt(),
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
        rooms: (map['rooms'] as List?)
                ?.map((r) => RoomSlot.fromMap(Map<String, dynamic>.from(r as Map)))
                .toList() ??
            [],
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
        schoolTypeIds: (map['schoolTypeIds'] as List?)?.map((e) => e.toString()).toList() ?? [],
        classroomAssignments:
            (map['classroomAssignments'] as List?)
                ?.map((a) =>
                    GradeClassroomAssignment.fromMap(Map<String, dynamic>.from(a as Map)))
                .toList() ?? [],
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
  final Map<String, String> gradeLevelStartTimes; // gradeLevel -> startTime
  final Map<String, String> gradeLevelEndTimes; // gradeLevel -> endTime

  const ApplicationSession({
    required this.id,
    required this.sessionDate,
    required this.startTime,
    required this.endTime,
    required this.gradeLevels,
    required this.gradeLevelQuotas,
    this.gradeLevelStartTimes = const {},
    this.gradeLevelEndTimes = const {},
  });

  String get displayTime => '$startTime – $endTime';

  int quotaForGrade(String grade) => gradeLevelQuotas[grade] ?? 0;

  String startTimeForGrade(String grade) => gradeLevelStartTimes[grade] ?? (startTime.isEmpty ? '09:00' : startTime);

  String endTimeForGrade(String grade) => gradeLevelEndTimes[grade] ?? (endTime.isEmpty ? '11:30' : endTime);

  Map<String, dynamic> toMap() => {
        'id': id,
        'sessionDate': Timestamp.fromDate(sessionDate),
        'startTime': startTime,
        'endTime': endTime,
        'gradeLevels': gradeLevels,
        'gradeLevelQuotas': gradeLevelQuotas,
        'gradeLevelStartTimes': gradeLevelStartTimes,
        'gradeLevelEndTimes': gradeLevelEndTimes,
      };

  factory ApplicationSession.fromMap(Map<String, dynamic> map) =>
      ApplicationSession(
        id: map['id'] ?? '',
        sessionDate: _parseDateTime(map['sessionDate']) ?? DateTime.now(),
        startTime: map['startTime'] ?? '',
        endTime: map['endTime'] ?? '',
        gradeLevels: (map['gradeLevels'] as List?)?.map((e) => e.toString()).toList() ?? [],
        gradeLevelQuotas: (map['gradeLevelQuotas'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
            ) ?? {},
        gradeLevelStartTimes: (map['gradeLevelStartTimes'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            ) ?? {},
        gradeLevelEndTimes: (map['gradeLevelEndTimes'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            ) ?? {},
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
  
  // Dynamic Web Portal Visibility Toggles
  final bool showRegister;
  final bool showEdit;
  final bool showTicket;
  final bool showResults;
  final bool showRegulation;

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
    this.showRegister = true,
    this.showEdit = true,
    this.showTicket = true,
    this.showResults = true,
    this.showRegulation = true,
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
      'showRegister': showRegister,
      'showEdit': showEdit,
      'showTicket': showTicket,
      'showResults': showResults,
      'showRegulation': showRegulation,
    };
  }

  factory ExternalExam.fromMap(Map<String, dynamic> map, String id) {
    // Parse scholarshipConfig safely
    final rawScholarship = map['scholarshipConfig'] as Map? ?? {};
    final scholarshipConfig = <String, List<ScholarshipTier>>{};
    rawScholarship.forEach((grade, tiers) {
      if (tiers is List) {
        scholarshipConfig[grade.toString()] = tiers
            .map((t) => ScholarshipTier.fromMap(Map<String, dynamic>.from(t as Map)))
            .toList();
      }
    });

    return ExternalExam(
      id: id,
      institutionId: map['institutionId'] ?? '',
      schoolId: map['schoolId'] ?? '',
      title: map['title'] ?? '',
      examType: _typeFromString(map['examType']),
      gradeLevels: (map['gradeLevels'] as List?)?.map((e) => e.toString()).toList() ?? [],
      trialExamIds: (map['trialExamIds'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {},
      applicationSessions:
          (map['applicationSessions'] as List?)
              ?.map((s) =>
                  ApplicationSession.fromMap(Map<String, dynamic>.from(s as Map)))
              .toList() ?? [],
      venueConfig: map['venueConfig'] != null
          ? VenueConfig.fromMap(Map<String, dynamic>.from(map['venueConfig'] as Map))
          : const VenueConfig(
              seatingMode: SeatingMode.noSeating,
              schoolTypeIds: [],
              classroomAssignments: [],
            ),
      scholarshipEnabled: map['scholarshipEnabled'] ?? false,
      scholarshipConfig: scholarshipConfig,
      regulationUrl: map['regulationUrl'],
      regulationPublishDate: _parseDateTime(map['regulationPublishDate']),
      isActive: map['isActive'] ?? true,
      createdAt: _parseDateTime(map['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDateTime(map['updatedAt']),
      showRegister: map['showRegister'] ?? true,
      showEdit: map['showEdit'] ?? true,
      showTicket: map['showTicket'] ?? true,
      showResults: map['showResults'] ?? true,
      showRegulation: map['showRegulation'] ?? true,
    );
  }
}
