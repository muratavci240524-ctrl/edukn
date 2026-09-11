import 'package:cloud_firestore/cloud_firestore.dart';
import 'seating_plan_model.dart';

/// Sınava dahil edilen tekil öğrenci modeli
class ExamStudent {
  final String id;
  final String name;
  final String surname;
  final String studentNumber;
  final String classId;
  final String className;
  final String gradeLevel; // Örn: '8. Sınıf', '11. Sınıf'
  final String? gender; // 'E', 'K'
  final String? photoUrl;

  ExamStudent({
    required this.id,
    required this.name,
    required this.surname,
    required this.studentNumber,
    required this.classId,
    required this.className,
    required this.gradeLevel,
    this.gender,
    this.photoUrl,
  });

  String get fullName => '$name $surname'.trim();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'surname': surname,
      'studentNumber': studentNumber,
      'classId': classId,
      'className': className,
      'gradeLevel': gradeLevel,
      'gender': gender,
      'photoUrl': photoUrl,
    };
  }

  factory ExamStudent.fromMap(Map<String, dynamic> map) {
    return ExamStudent(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      surname: map['surname']?.toString() ?? '',
      studentNumber: map['studentNumber']?.toString() ?? '',
      classId: map['classId']?.toString() ?? '',
      className: map['className']?.toString() ?? '',
      gradeLevel: map['gradeLevel']?.toString() ?? '',
      gender: map['gender']?.toString(),
      photoUrl: map['photoUrl']?.toString(),
    );
  }

  ExamStudent clone() {
    return ExamStudent(
      id: id,
      name: name,
      surname: surname,
      studentNumber: studentNumber,
      classId: classId,
      className: className,
      gradeLevel: gradeLevel,
      gender: gender,
      photoUrl: photoUrl,
    );
  }
}

/// Sınav salonundaki tekil koltuk koordinatı ve yerleşim durumu
class SeatCoordinate {
  final String roomId;
  final int row;
  final int col;
  final int slotIndex; // 0: Tekli / Çiftli Sol, 1: Çiftli Sağ
  final int seatNumber; // Salondaki 1'den başlayan genel sıra numarası
  ExamStudent? student;

  SeatCoordinate({
    required this.roomId,
    required this.row,
    required this.col,
    required this.slotIndex,
    required this.seatNumber,
    this.student,
  });

  bool get isOccupied => student != null;
  String get coordinateKey => '$row-$col-$slotIndex';

  Map<String, dynamic> toMap() {
    return {
      'roomId': roomId,
      'row': row,
      'col': col,
      'slotIndex': slotIndex,
      'seatNumber': seatNumber,
      'student': student?.toMap(),
    };
  }

  factory SeatCoordinate.fromMap(Map<String, dynamic> map) {
    return SeatCoordinate(
      roomId: map['roomId']?.toString() ?? '',
      row: map['row'] ?? 0,
      col: map['col'] ?? 0,
      slotIndex: map['slotIndex'] ?? 0,
      seatNumber: map['seatNumber'] ?? 0,
      student: map['student'] != null
          ? ExamStudent.fromMap(Map<String, dynamic>.from(map['student'] as Map))
          : null,
    );
  }

  SeatCoordinate clone() {
    return SeatCoordinate(
      roomId: roomId,
      row: row,
      col: col,
      slotIndex: slotIndex,
      seatNumber: seatNumber,
      student: student?.clone(),
    );
  }
}

/// Sınav Salonu / Dersliği Modeli
class ExamRoom {
  final String id;
  final String classroomId;
  final String classroomName;
  final String layoutId;
  final String layoutName;
  final ClassroomLayout layoutSnapshot; // Dersliğin fiziksel grid düzeninin anlık kopyası
  final String? supervisorId; // Sınav Gözetmen Öğretmeni ID
  final String? supervisorName; // Sınav Gözetmen Öğretmeni
  final List<SeatCoordinate> seats;

  ExamRoom({
    required this.id,
    required this.classroomId,
    required this.classroomName,
    required this.layoutId,
    required this.layoutName,
    required this.layoutSnapshot,
    this.supervisorId,
    this.supervisorName,
    required this.seats,
  });

  int get totalCapacity => seats.length;
  int get seatedStudentCount => seats.where((s) => s.isOccupied).length;
  int get emptySeatCount => totalCapacity - seatedStudentCount;

  List<ExamStudent> get seatedStudents =>
      seats.where((s) => s.isOccupied).map((s) => s.student!).toList();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'classroomId': classroomId,
      'classroomName': classroomName,
      'layoutId': layoutId,
      'layoutName': layoutName,
      'layoutSnapshot': layoutSnapshot.toMap(),
      'supervisorId': supervisorId,
      'supervisorName': supervisorName,
      'seats': seats.map((s) => s.toMap()).toList(),
    };
  }

  factory ExamRoom.fromMap(Map<String, dynamic> map) {
    final layoutMap = Map<String, dynamic>.from(map['layoutSnapshot'] as Map? ?? {});
    final layoutId = map['layoutId']?.toString() ?? '';
    final layout = ClassroomLayout.fromMap(layoutMap, layoutId);

    final rawSeats = (map['seats'] as List<dynamic>?) ?? [];
    final seats = rawSeats
        .map((s) => SeatCoordinate.fromMap(Map<String, dynamic>.from(s as Map)))
        .toList();

    return ExamRoom(
      id: map['id']?.toString() ?? '',
      classroomId: map['classroomId']?.toString() ?? '',
      classroomName: map['classroomName']?.toString() ?? '',
      layoutId: layoutId,
      layoutName: map['layoutName']?.toString() ?? '',
      layoutSnapshot: layout,
      supervisorId: map['supervisorId']?.toString(),
      supervisorName: map['supervisorName']?.toString(),
      seats: seats,
    );
  }

  ExamRoom clone() {
    return ExamRoom(
      id: id,
      classroomId: classroomId,
      classroomName: classroomName,
      layoutId: layoutId,
      layoutName: layoutName,
      layoutSnapshot: layoutSnapshot.clone(),
      supervisorId: supervisorId,
      supervisorName: supervisorName,
      seats: seats.map((s) => s.clone()).toList(),
    );
  }
}

/// Kelebek Sınav Oturumu Üst Modeli
class ExamDistribution {
  final String? id;
  final String title; // Örn: '1. Dönem 1. Ortak Matematik Sınavı'
  final String lessonName; // Örn: 'Matematik'
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final DateTime examDate;
  final String examTime; // Örn: '09:30 - 10:10'
  final List<String> selectedClassIds;
  final List<String> selectedClassNames;
  final List<String> gradeLevels; // Örn: ['8. Sınıf', '7. Sınıf']
  final List<ExamRoom> rooms;
  final int totalStudents;
  final int seatedStudents;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? notes;
  final bool showExamTitleOnPdf;

  ExamDistribution({
    this.id,
    required this.title,
    required this.lessonName,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.examDate,
    required this.examTime,
    required this.selectedClassIds,
    required this.selectedClassNames,
    required this.gradeLevels,
    required this.rooms,
    required this.totalStudents,
    required this.seatedStudents,
    required this.createdAt,
    this.updatedAt,
    this.notes,
    this.showExamTitleOnPdf = true,
  });

  int get totalRoomCapacity =>
      rooms.fold<int>(0, (total, room) => total + room.totalCapacity);
  int get totalSeatedCount =>
      rooms.fold<int>(0, (total, room) => total + room.seatedStudentCount);
  int get unplacedStudentsCount => totalStudents - totalSeatedCount;

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'lessonName': lessonName,
      'institutionId': institutionId,
      'schoolTypeId': schoolTypeId,
      'schoolTypeName': schoolTypeName,
      'examDate': Timestamp.fromDate(examDate),
      'examTime': examTime,
      'selectedClassIds': selectedClassIds,
      'selectedClassNames': selectedClassNames,
      'gradeLevels': gradeLevels,
      'rooms': rooms.map((r) => r.toMap()).toList(),
      'totalStudents': totalStudents,
      'seatedStudents': seatedStudents,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'notes': notes,
      'showExamTitleOnPdf': showExamTitleOnPdf,
    };
  }

  factory ExamDistribution.fromMap(Map<String, dynamic> map, String id) {
    final rawRooms = (map['rooms'] as List<dynamic>?) ?? [];
    final rooms = rawRooms
        .map((r) => ExamRoom.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();

    return ExamDistribution(
      id: id,
      title: map['title']?.toString() ?? 'Kelebek Sınav Dağıtımı',
      lessonName: map['lessonName']?.toString() ?? '',
      institutionId: map['institutionId']?.toString() ?? '',
      schoolTypeId: map['schoolTypeId']?.toString() ?? '',
      schoolTypeName: map['schoolTypeName']?.toString() ?? '',
      examDate: (map['examDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      examTime: map['examTime']?.toString() ?? '09:00',
      selectedClassIds: List<String>.from(map['selectedClassIds'] ?? []),
      selectedClassNames: List<String>.from(map['selectedClassNames'] ?? []),
      gradeLevels: List<String>.from(map['gradeLevels'] ?? []),
      rooms: rooms,
      totalStudents: map['totalStudents'] ?? 0,
      seatedStudents: map['seatedStudents'] ?? 0,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      notes: map['notes']?.toString(),
      showExamTitleOnPdf: map['showExamTitleOnPdf'] ?? true,
    );
  }

  ExamDistribution clone() {
    return ExamDistribution(
      id: id,
      title: title,
      lessonName: lessonName,
      institutionId: institutionId,
      schoolTypeId: schoolTypeId,
      schoolTypeName: schoolTypeName,
      examDate: examDate,
      examTime: examTime,
      selectedClassIds: List<String>.from(selectedClassIds),
      selectedClassNames: List<String>.from(selectedClassNames),
      gradeLevels: List<String>.from(gradeLevels),
      rooms: rooms.map((r) => r.clone()).toList(),
      totalStudents: totalStudents,
      seatedStudents: seatedStudents,
      createdAt: createdAt,
      updatedAt: updatedAt,
      notes: notes,
      showExamTitleOnPdf: showExamTitleOnPdf,
    );
  }
}
