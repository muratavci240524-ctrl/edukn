import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _parseDateTime(dynamic val) {
  if (val == null) return null;
  if (val is Timestamp) return val.toDate();
  if (val is String) return DateTime.tryParse(val);
  return null;
}


enum RegistrationSource { online, manualExcel }

enum RegistrationStatus { pending, confirmed, cancelled }

class ExternalExamRegistration {
  final String? id;
  final String examId;
  final String institutionId;
  final String sessionId;

  // Student info
  final String studentName;
  final String studentSurname;
  final String studentTcNo;
  final String? studentNumber;
  final String gradeLevel;

  // Parent info (required)
  final String parentName;
  final String parentSurname;
  final String parentPhone;
  final String? parentEmail;

  // Location
  final String city;
  final String district;
  final String currentSchool;

  // Optional contact
  final String? phone;
  final String? email;

  // Metadata
  final RegistrationSource registrationSource;
  final RegistrationStatus status;

  // Seat assignment
  final String? assignedRoomId;
  final String? assignedRoomName;
  final String? assignedRoomCode;
  final int? seatNumber;
  final String? examEntryCode;
  final bool isScanned;

  final DateTime createdAt;

  const ExternalExamRegistration({
    this.id,
    required this.examId,
    required this.institutionId,
    required this.sessionId,
    required this.studentName,
    required this.studentSurname,
    required this.studentTcNo,
    this.studentNumber,
    required this.gradeLevel,
    required this.parentName,
    required this.parentSurname,
    required this.parentPhone,
    this.parentEmail,
    required this.city,
    required this.district,
    required this.currentSchool,
    this.phone,
    this.email,
    required this.registrationSource,
    required this.status,
    this.assignedRoomId,
    this.assignedRoomName,
    this.assignedRoomCode,
    this.seatNumber,
    this.examEntryCode,
    this.isScanned = false,
    required this.createdAt,
  });

  String get fullName => '$studentName $studentSurname';

  String get parentFullName => '$parentName $parentSurname';

  /// TC kimlik numarasını maskeler: 123*****89
  String get displayTcNo {
    if (studentTcNo.length < 4) return studentTcNo;
    final prefix = studentTcNo.substring(0, 3);
    final suffix = studentTcNo.substring(studentTcNo.length - 2);
    final stars = '*' * (studentTcNo.length - 5);
    return '$prefix$stars$suffix';
  }

  String get statusName {
    switch (status) {
      case RegistrationStatus.pending:
        return 'Bekliyor';
      case RegistrationStatus.confirmed:
        return 'Onaylandı';
      case RegistrationStatus.cancelled:
        return 'İptal';
    }
  }

  String get sourceName {
    switch (registrationSource) {
      case RegistrationSource.online:
        return 'Online Başvuru';
      case RegistrationSource.manualExcel:
        return 'Excel Yükleme';
    }
  }

  static RegistrationSource _sourceFromString(String? s) {
    switch (s) {
      case 'manual_excel':
        return RegistrationSource.manualExcel;
      default:
        return RegistrationSource.online;
    }
  }

  static String _sourceToString(RegistrationSource s) {
    switch (s) {
      case RegistrationSource.online:
        return 'online';
      case RegistrationSource.manualExcel:
        return 'manual_excel';
    }
  }

  static RegistrationStatus _statusFromString(String? s) {
    switch (s) {
      case 'confirmed':
        return RegistrationStatus.confirmed;
      case 'cancelled':
        return RegistrationStatus.cancelled;
      default:
        return RegistrationStatus.pending;
    }
  }

  static String _statusToString(RegistrationStatus s) {
    switch (s) {
      case RegistrationStatus.pending:
        return 'pending';
      case RegistrationStatus.confirmed:
        return 'confirmed';
      case RegistrationStatus.cancelled:
        return 'cancelled';
    }
  }

  Map<String, dynamic> toMap() => {
        'examId': examId,
        'institutionId': institutionId,
        'sessionId': sessionId,
        'studentName': studentName,
        'studentSurname': studentSurname,
        'studentTcNo': studentTcNo,
        'studentNumber': studentNumber,
        'gradeLevel': gradeLevel,
        'parentName': parentName,
        'parentSurname': parentSurname,
        'parentPhone': parentPhone,
        'parentEmail': parentEmail,
        'city': city,
        'district': district,
        'currentSchool': currentSchool,
        'phone': phone,
        'email': email,
        'registrationSource': _sourceToString(registrationSource),
        'status': _statusToString(status),
        'assignedRoomId': assignedRoomId,
        'assignedRoomName': assignedRoomName,
        'assignedRoomCode': assignedRoomCode,
        'seatNumber': seatNumber,
        'examEntryCode': examEntryCode,
        'isScanned': isScanned,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  factory ExternalExamRegistration.fromMap(
    Map<String, dynamic> map,
    String id,
  ) =>
      ExternalExamRegistration(
        id: id,
        examId: map['examId'] ?? '',
        institutionId: map['institutionId'] ?? '',
        sessionId: map['sessionId'] ?? '',
        studentName: map['studentName'] ?? '',
        studentSurname: map['studentSurname'] ?? '',
        studentTcNo: map['studentTcNo'] ?? '',
        studentNumber: map['studentNumber'],
        gradeLevel: map['gradeLevel'] ?? '',
        parentName: map['parentName'] ?? '',
        parentSurname: map['parentSurname'] ?? '',
        parentPhone: map['parentPhone'] ?? '',
        parentEmail: map['parentEmail'],
        city: map['city'] ?? '',
        district: map['district'] ?? '',
        currentSchool: map['currentSchool'] ?? '',
        phone: map['phone'],
        email: map['email'],
        registrationSource: _sourceFromString(map['registrationSource']),
        status: _statusFromString(map['status']),
        assignedRoomId: map['assignedRoomId'],
        assignedRoomName: map['assignedRoomName'],
        assignedRoomCode: map['assignedRoomCode'],
        seatNumber: (map['seatNumber'] as num?)?.toInt(),
        examEntryCode: map['examEntryCode'],
        isScanned: map['isScanned'] ?? false,
        createdAt: _parseDateTime(map['createdAt']) ?? DateTime.now(),
      );

  ExternalExamRegistration copyWith({
    RegistrationStatus? status,
    String? assignedRoomId,
    String? assignedRoomName,
    String? assignedRoomCode,
    int? seatNumber,
    String? examEntryCode,
    bool? isScanned,
    String? studentName,
    String? studentSurname,
    String? studentTcNo,
    String? phone,
    String? gradeLevel,
    String? currentSchool,
  }) =>
      ExternalExamRegistration(
        id: id,
        examId: examId,
        institutionId: institutionId,
        sessionId: sessionId,
        studentName: studentName ?? this.studentName,
        studentSurname: studentSurname ?? this.studentSurname,
        studentTcNo: studentTcNo ?? this.studentTcNo,
        studentNumber: studentNumber,
        gradeLevel: gradeLevel ?? this.gradeLevel,
        parentName: parentName,
        parentSurname: parentSurname,
        parentPhone: parentPhone,
        parentEmail: parentEmail,
        city: city,
        district: district,
        currentSchool: currentSchool ?? this.currentSchool,
        phone: phone ?? this.phone,
        email: email,
        registrationSource: registrationSource,
        status: status ?? this.status,
        assignedRoomId: assignedRoomId ?? this.assignedRoomId,
        assignedRoomName: assignedRoomName ?? this.assignedRoomName,
        assignedRoomCode: assignedRoomCode ?? this.assignedRoomCode,
        seatNumber: seatNumber ?? this.seatNumber,
        examEntryCode: examEntryCode ?? this.examEntryCode,
        isScanned: isScanned ?? this.isScanned,
        createdAt: createdAt,
      );
}
