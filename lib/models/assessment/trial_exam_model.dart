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
  final Map<String, Map<String, String>> bookletMapping; // NEW: Booklet -> Subject -> MappingString (e.g. "4,3,2,1")
  final String? termId; // Dönem ID'si
  final int durationMinutes; // Sınav süresi (dakika, 0 = tanımlanmamış)

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
    if (studentChar == ' ' || studentChar == '*' || studentChar == '.' || studentChar == '-' || studentChar == '_' || studentChar.isEmpty) {
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
    this.bookletMapping = const {},
    this.termId,
    this.durationMinutes = 0,
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
      'bookletMapping': bookletMapping,
      'termId': termId,
      'durationMinutes': durationMinutes,
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

    // Booklet Mapping Parsing
    Map<String, Map<String, String>> parsedMapping = {};
    if (map['bookletMapping'] != null) {
      Map<String, dynamic> bm = Map<String, dynamic>.from(map['bookletMapping']);
      bm.forEach((booklet, subjects) {
        parsedMapping[booklet] = {};
        if (subjects is Map) {
          subjects.forEach((subj, mapping) {
            parsedMapping[booklet]![subj.toString()] = mapping.toString();
          });
        }
      });
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
      bookletMapping: parsedMapping,
      termId: map['termId'],
      durationMinutes: (map['durationMinutes'] as num?)?.toInt() ?? 0,
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
    bool? isLaunched,
    String? resultsJson,
    Map<String, dynamic>? sharingSettings,
    String? termId,
    int? durationMinutes,
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
      isLaunched: isLaunched ?? this.isLaunched,
      resultsJson: resultsJson ?? this.resultsJson,
      sharingSettings: sharingSettings ?? this.sharingSettings,
      termId: termId ?? this.termId,
      durationMinutes: durationMinutes ?? this.durationMinutes,
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

  /// Okunan dosyaya (TXT/DAT) DOKUNMADAN yapılan satır düzeltmeleri.
  /// Değerlendirme sırasında dosya satırlarına uygulanır.
  final List<OpticalLineEdit> lineEdits;

  TrialExamSession({
    required this.sessionNumber,
    this.selectedSubjects = const [],
    this.opticalFormId,
    this.opticalFormName,
    this.fileName,
    this.fileUrl,
    this.uploadedAt,
    this.lineEdits = const [],
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
      'lineEdits': lineEdits.map((e) => e.toMap()).toList(),
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
      lineEdits: (map['lineEdits'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => OpticalLineEdit.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  TrialExamSession copyWith({
    int? sessionNumber,
    List<String>? selectedSubjects,
    String? opticalFormId,
    String? opticalFormName,
    String? fileName,
    String? fileUrl,
    DateTime? uploadedAt,
    List<OpticalLineEdit>? lineEdits,
  }) {
    return TrialExamSession(
      sessionNumber: sessionNumber ?? this.sessionNumber,
      selectedSubjects: selectedSubjects ?? this.selectedSubjects,
      opticalFormId: opticalFormId ?? this.opticalFormId,
      opticalFormName: opticalFormName ?? this.opticalFormName,
      fileName: fileName ?? this.fileName,
      fileUrl: fileUrl ?? this.fileUrl,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      lineEdits: lineEdits ?? this.lineEdits,
    );
  }
}

/// Okunan optik dosyadaki TEK satırın (bir öğrenci kâğıdı) düzeltmesi.
/// Orijinal dosya değişmez; düzeltme değerlendirme anında uygulanır.
class OpticalLineEdit {
  /// Dosyadaki satır sırası (0'dan başlar; `content.split('\n')` indeksi).
  final int line;

  /// Orijinal satırın parmak izi. Dosya değişirse düzeltme uygulanmaz.
  final String fingerprint;

  /// Alan anahtarı -> yeni değer. Anahtarlar: identityNo, studentNo,
  /// studentName, classLevel, branch, institutionCode, session, bookletType,
  /// 'subj:<Ders Adı>'.
  final Map<String, String> fields;

  /// true: bu kâğıt değerlendirmeye alınmaz (çift okunan / hatalı kâğıt).
  final bool excluded;

  const OpticalLineEdit({
    required this.line,
    required this.fingerprint,
    this.fields = const {},
    this.excluded = false,
  });

  bool get isEmpty => fields.isEmpty && !excluded;

  Map<String, dynamic> toMap() => {
        'line': line,
        'fp': fingerprint,
        'fields': fields,
        'excluded': excluded,
      };

  factory OpticalLineEdit.fromMap(Map<String, dynamic> map) => OpticalLineEdit(
        line: (map['line'] as num?)?.toInt() ?? -1,
        fingerprint: (map['fp'] ?? '').toString(),
        fields: (map['fields'] as Map? ?? {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
        excluded: map['excluded'] == true,
      );
}
