import 'package:cloud_firestore/cloud_firestore.dart';

enum TrialExamApplicationType { optical, online, hybrid }

class TrialExam {
  final String id;
  final String institutionId;
  final String name;
  final String classLevel;
  final String examTypeId;
  final String examTypeName;
  final TrialExamApplicationType applicationType;
  final int bookletCount;
  final int sessionCount;
  final Map<String, Map<String, String>>
  answerKeys; // Booklet -> Subject -> AnswerString
  final Map<String, Map<String, List<String>>>
  outcomes; // Booklet -> Subject -> List<Outcome>
  final List<TrialExamSession> sessions; // NEW: Sessions list
  final DateTime date;
  final bool isActive;
  final bool isPublished;
  final bool isLaunched; // NEW: Indicates if the exam has been launched/started
  final List<String> selectedBranches; // Filter branches
  final String? resultsJson; // Stores computed results
  final Map<String, dynamic> sharingSettings; // Sharing configuration

  static AnswerStatus evaluateAnswer(String studentChar, String refChar) {
    studentChar = studentChar.toUpperCase();
    refChar = refChar.toUpperCase();

    // 1. Check for special reference keys
    if (refChar == 'S' || refChar == 'X') {
      return AnswerStatus.correct;
    }
    if (refChar == '#') {
      return AnswerStatus.empty;
    }

    // 2. Standard comparison
    if (studentChar == ' ' || studentChar == '*' || studentChar == '.') {
      return AnswerStatus.empty;
    }

    if (studentChar == refChar) {
      return AnswerStatus.correct;
    } else {
      return AnswerStatus.wrong;
    }
  }

  TrialExam({
    required this.id,
    required this.institutionId,
    required this.name,
    required this.classLevel,
    required this.examTypeId,
    required this.examTypeName,
    required this.applicationType,
    required this.bookletCount,
    this.sessionCount = 1,
    this.answerKeys = const {},
    this.outcomes = const {},
    this.sessions = const [],
    this.selectedBranches = const [],
    required this.date,
    this.isActive = true,
    this.isPublished = false,
    this.isLaunched = false, // Default false
    this.resultsJson,
    this.sharingSettings = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'institutionId': institutionId,
      'name': name,
      'classLevel': classLevel,
      'examTypeId': examTypeId,
      'examTypeName': examTypeName,
      'applicationType': applicationType.index,
      'bookletCount': bookletCount,
      'sessionCount': sessionCount,
      'answerKeys': answerKeys,
      'outcomes': outcomes,
      'sessions': sessions.map((s) => s.toMap()).toList(),
      'selectedBranches': selectedBranches,
      'date': Timestamp.fromDate(date),
      'isActive': isActive,
      'isPublished': isPublished,
      'isLaunched': isLaunched,
      'resultsJson': resultsJson,
      'sharingSettings': sharingSettings,
    };
  }

  factory TrialExam.fromMap(Map<String, dynamic> map, String id) {
    // Answer Key Parsing
    Map<String, Map<String, String>> parsedKeys = {};
    if (map['answerKeys'] != null) {
      final keysMap = map['answerKeys'] as Map<String, dynamic>;
      keysMap.forEach((booklet, subjects) {
        if (subjects is Map<String, dynamic>) {
          parsedKeys[booklet] = subjects.map(
            (k, v) => MapEntry(k, v.toString()),
          );
        }
      });
    }

    // Outcomes Parsing
    Map<String, Map<String, List<String>>> parsedOutcomes = {};
    if (map['outcomes'] != null) {
      final outcomesMap = map['outcomes'] as Map<String, dynamic>;
      outcomesMap.forEach((booklet, subjects) {
        if (subjects is Map<String, dynamic>) {
          Map<String, List<String>> subjectMap = {};
          subjects.forEach((subjectName, outcomeList) {
            if (outcomeList is List) {
              subjectMap[subjectName] = outcomeList
                  .map((e) => e.toString())
                  .toList();
            }
          });
          parsedOutcomes[booklet] = subjectMap;
        }
      });
    }

    // Sessions Parsing
    List<TrialExamSession> parsedSessions = [];
    if (map['sessions'] != null) {
      parsedSessions = (map['sessions'] as List<dynamic>)
          .map((e) => TrialExamSession.fromMap(e as Map<String, dynamic>))
          .toList();
    }

    return TrialExam(
      id: id,
      institutionId: map['institutionId'] ?? '',
      name: map['name'] ?? '',
      classLevel: map['classLevel'] ?? '',
      examTypeId: map['examTypeId'] ?? '',
      examTypeName: map['examTypeName'] ?? '',
      applicationType:
          TrialExamApplicationType.values[map['applicationType'] ?? 0],
      bookletCount: map['bookletCount'] ?? 1,
      sessionCount: map['sessionCount'] ?? 1,
      answerKeys: parsedKeys,
      outcomes: parsedOutcomes,
      sessions: parsedSessions,
      selectedBranches: (map['selectedBranches'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      date: (map['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isActive: map['isActive'] ?? true,
      isPublished: map['isPublished'] ?? false,
      isLaunched: map['isLaunched'] ?? false, // Load from map
      resultsJson: map['resultsJson'],
      sharingSettings: map['sharingSettings'] ?? {},
    );
  }

  TrialExam copyWith({
    String? id,
    String? institutionId,
    String? name,
    String? classLevel,
    String? examTypeId,
    String? examTypeName,
    TrialExamApplicationType? applicationType,
    int? bookletCount,
    int? sessionCount,
    Map<String, Map<String, String>>? answerKeys,
    Map<String, Map<String, List<String>>>? outcomes,
    List<TrialExamSession>? sessions,
    List<String>? selectedBranches,
    DateTime? date,
    bool? isActive,
    bool? isPublished,
    bool? isLaunched, // Add copyWith param
    String? resultsJson,
    Map<String, dynamic>? sharingSettings,
  }) {
    return TrialExam(
      id: id ?? this.id,
      institutionId: institutionId ?? this.institutionId,
      name: name ?? this.name,
      classLevel: classLevel ?? this.classLevel,
      examTypeId: examTypeId ?? this.examTypeId,
      examTypeName: examTypeName ?? this.examTypeName,
      applicationType: applicationType ?? this.applicationType,
      bookletCount: bookletCount ?? this.bookletCount,
      sessionCount: sessionCount ?? this.sessionCount,
      answerKeys: answerKeys ?? this.answerKeys,
      outcomes: outcomes ?? this.outcomes,
      sessions: sessions ?? this.sessions,
      selectedBranches: selectedBranches ?? this.selectedBranches,
      date: date ?? this.date,
      isActive: isActive ?? this.isActive,
      isPublished: isPublished ?? this.isPublished,
      isLaunched: isLaunched ?? this.isLaunched, // Assign it
      resultsJson: resultsJson ?? this.resultsJson,
      sharingSettings: sharingSettings ?? this.sharingSettings,
    );
  }
}

enum AnswerStatus { correct, wrong, empty }

class TrialExamSession {
  final int sessionNumber;
  final List<String> selectedSubjects;
  final String? opticalFormId;
  final String? opticalFormName;
  final String? fileName;
  final String? fileUrl; // Path or URL
  final DateTime? uploadedAt;

  TrialExamSession({
    required this.sessionNumber,
    this.selectedSubjects = const [],
    this.opticalFormId,
    this.opticalFormName,
    this.fileName,
    this.fileUrl,
    this.uploadedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'sessionNumber': sessionNumber,
      'selectedSubjects': selectedSubjects,
      'opticalFormId': opticalFormId,
      'opticalFormName': opticalFormName,
      'fileName': fileName,
      'fileUrl': fileUrl,
      'uploadedAt': uploadedAt != null ? Timestamp.fromDate(uploadedAt!) : null,
    };
  }

  factory TrialExamSession.fromMap(Map<String, dynamic> map) {
    return TrialExamSession(
      sessionNumber: map['sessionNumber'] ?? 1,
      selectedSubjects: (map['selectedSubjects'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      opticalFormId: map['opticalFormId'],
      opticalFormName: map['opticalFormName'],
      fileName: map['fileName'],
      fileUrl: map['fileUrl'],
      uploadedAt: (map['uploadedAt'] as Timestamp?)?.toDate(),
    );
  }
}
