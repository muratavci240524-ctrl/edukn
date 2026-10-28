import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/school/butterfly_exam_model.dart';
import '../models/school/seating_plan_model.dart';

/// 3 Farklı Dağıtım Modu
enum DistributionMode {
  /// 1. Tam Kelebek: Farklı sınıf seviyeleri ve şubeler tam çapraz karışır (Aynı seviye/şube yan yana veya ön-arka gelemez)
  fullCross,

  /// 2. Seviye İçi Çapraz: Sınıf seviyeleri kendi içinde kalır, ancak o seviyedeki şubeler (örn. 8-A, 8-B, 8-C) kendi içinde çapraz karışır
  gradeLevelCross,

  /// 3. Sıralı Dağıtım: Öğrenciler mevcut şube ve okul numaralarına göre standart sıralı olarak dizilir
  sequential,
}

/// Kelebek Dağıtım İstek Parametreleri (Isolate / Compute uyumlu)
class ButterflyDistributionParams {
  final String title;
  final String lessonName;
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final DateTime examDate;
  final String examTime;
  final List<String> selectedClassIds;
  final List<String> selectedClassNames;
  final List<String> gradeLevels;
  final List<ExamStudent> students;
  final List<Map<String, dynamic>> roomConfigs; // roomId, classroomName, layout, customCapacity, supervisorName
  final String? notes;
  final DistributionMode distributionMode;
  final bool balanceEmptySeats; // true: Boşlukları eşit dağıt, false: Boşlukları son sınıfa ver
  final bool showExamTitleOnPdf; // true: Sınav adını yaz, false: 'Deneme Sınavı' yaz
  final List<Map<String, dynamic>> sessionSlots;
  final List<String> instructions;

  ButterflyDistributionParams({
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
    required this.students,
    required this.roomConfigs,
    this.notes,
    this.distributionMode = DistributionMode.fullCross,
    this.balanceEmptySeats = true,
    this.showExamTitleOnPdf = true,
    this.sessionSlots = const [],
    this.instructions = const [],
  });
}

/// Kelebek (Çapraz) Sınav Dağıtım Motoru
class ButterflyDistributionService {
  /// UI donmasını engellemek için arka planda Isolate (compute) veya doğrudan çalıştırılabilir
  static Future<ExamDistribution> distributeExam(ButterflyDistributionParams params) async {
    if (kIsWeb) {
      return _executeButterflyAlgorithm(params);
    } else {
      try {
        return await compute(_executeButterflyAlgorithm, params);
      } catch (e) {
        debugPrint('Compute hatası, ana threadde çalıştırılıyor: $e');
        return _executeButterflyAlgorithm(params);
      }
    }
  }

  /// ===========================================================================
  /// ÇAPRAZ DAĞITIM ALGORİTMASI ÇEKİRDEĞİ (DETERMİNİSTİK & OFF-LINE)
  /// ===========================================================================
  static ExamDistribution _executeButterflyAlgorithm(ButterflyDistributionParams params) {
    // Her çalıştırmada tamamen benzersiz ve rastgele bir dağıtım üret
    final rand = Random();

    // -------------------------------------------------------------------------
    // 1. ADIM: DERSLİKLERİ VE BOŞ KOLTUKLARI ÇIKARMA (ÖNDEN ARKAYA SIRALAMA)
    // -------------------------------------------------------------------------
    final List<ExamRoom> generatedRooms = [];

    for (int rIdx = 0; rIdx < params.roomConfigs.length; rIdx++) {
      final config = params.roomConfigs[rIdx];
      final classroomId = config['classroomId']?.toString() ?? 'room_$rIdx';
      final classroomName = config['classroomName']?.toString() ?? 'Salon ${rIdx + 1}';
      final customCap = (config['customCapacity'] as num?)?.toInt();
      final layoutSnapshot = (config['layout'] as ClassroomLayout?) ??
          ClassroomLayout.createPreset(
            presetType: '3_col_double_with_aisles',
            name: 'Standart 3 Blok (18 Masa / 36 Koltuk)',
            institutionId: params.institutionId,
            schoolTypeId: params.schoolTypeId,
          );
      final supervisorId = config['supervisorId']?.toString();
      final supervisorName = config['supervisorName']?.toString();

      final List<SeatCoordinate> roomSeats = [];
      int seatCounter = 1;

      // SIRA NUMARALANDIRMA (1 numara en ön sol, 2 numara 1'in hemen arkası)
      // Sütun bazında (kolon kolon) önden arkaya doğru ilerleme
      for (int col = 0; col < layoutSnapshot.cols; col++) {
        final colCells = layoutSnapshot.cells
            .where((c) => c.col == col && c.cellType != CellType.aisle && c.cellType != CellType.teacherDesk)
            .toList();
        if (colCells.isEmpty) continue;

        // Önden arkaya doğru sıralar (row 0, 1, 2...)
        colCells.sort((a, b) => a.row.compareTo(b.row));

        for (int slot = 0; slot < 2; slot++) {
          for (final cell in colCells) {
            if (slot == 1 && cell.deskType != DeskType.double) continue;

            // Özel kapasite sınırı varsa kontrol et
            if (customCap != null && roomSeats.length >= customCap) continue;

            final seat = SeatCoordinate(
              roomId: classroomId,
              row: cell.row,
              col: col,
              slotIndex: slot,
              seatNumber: seatCounter++,
            );
            roomSeats.add(seat);
          }
        }
      }

        final rawSups = (config['supervisors'] as List<dynamic>?) ?? [];
        final supervisors = rawSups.map((e) => Map<String, dynamic>.from(e as Map)).toList();

        generatedRooms.add(ExamRoom(
          id: 'room_${rIdx + 1}',
          classroomId: classroomId,
          classroomName: classroomName,
          layoutId: layoutSnapshot.id ?? 'layout_$rIdx',
          layoutName: layoutSnapshot.name,
          layoutSnapshot: layoutSnapshot,
          supervisorId: supervisorId,
          supervisorName: supervisorName,
          supervisors: supervisors,
          seats: roomSeats,
        ));
      }

    // -------------------------------------------------------------------------
    // 2. ADIM: EŞİT / DENGELİ SALON KONTENJANLARI HESAPLAMA
    // -------------------------------------------------------------------------
    final totalStudents = params.students.length;
    final int numRooms = generatedRooms.length;
    final Map<int, int> roomQuotas = {};

    if (numRooms > 0) {
      if (params.balanceEmptySeats) {
        final int baseQuota = totalStudents ~/ numRooms;
        final int remainder = totalStudents % numRooms;
        for (int i = 0; i < numRooms; i++) {
          final maxCap = generatedRooms[i].seats.length;
          final target = baseQuota + (i < remainder ? 1 : 0);
          roomQuotas[i] = target.clamp(0, maxCap);
        }
      } else {
        for (int i = 0; i < numRooms; i++) {
          roomQuotas[i] = generatedRooms[i].seats.length;
        }
      }
    }

    // -------------------------------------------------------------------------
    // 3. ADIM: SEÇİLEN MODA GÖRE DAĞITIM MOTORUNU ÇALIŞTIRMA
    // -------------------------------------------------------------------------
    switch (params.distributionMode) {
      case DistributionMode.sequential:
        _distributeSequentially(params, generatedRooms, roomQuotas);
        break;

      case DistributionMode.gradeLevelCross:
        _distributeGradeLevelCross(params, generatedRooms, rand, roomQuotas);
        break;

      case DistributionMode.fullCross:
        _distributeFullCross(params, generatedRooms, rand, roomQuotas);
        break;
    }

    // -------------------------------------------------------------------------
    // 4. ADIM: DAĞITIM SONUCU VE İSTATİSTİKLERİN OLUŞTURULMASI
    // -------------------------------------------------------------------------
    final totalSeated = generatedRooms.fold<int>(0, (sum, r) => sum + r.seatedStudentCount);

    return ExamDistribution(
      title: params.title,
      lessonName: params.lessonName,
      institutionId: params.institutionId,
      schoolTypeId: params.schoolTypeId,
      schoolTypeName: params.schoolTypeName,
      examDate: params.examDate,
      examTime: params.examTime,
      selectedClassIds: params.selectedClassIds,
      selectedClassNames: params.selectedClassNames,
      gradeLevels: params.gradeLevels,
      rooms: generatedRooms,
      totalStudents: params.students.length,
      seatedStudents: totalSeated,
      createdAt: DateTime.now(),
      notes: params.notes,
      showExamTitleOnPdf: params.showExamTitleOnPdf,
      sessionSlots: params.sessionSlots,
      instructions: params.instructions,
      distributionMode: params.distributionMode.name,
    );
  }

  // ===========================================================================
  // MOD 1: TAM KELEBEK DAĞITIMI
  // ===========================================================================
  static void _distributeFullCross(
    ButterflyDistributionParams params,
    List<ExamRoom> generatedRooms,
    Random rand,
    Map<int, int> roomQuotas,
  ) {
    // 1) Her şube için ayrı kova oluştur (asla tüm şubeleri tek sepete atma!)
    // Anahtar: Şube Adı (örn: '8-A', '8-B', '5-A')
    final Map<String, List<ExamStudent>> studentBuckets = {};

    for (final student in params.students) {
      final key = student.className;
      studentBuckets.putIfAbsent(key, () => []).add(student.clone());
    }

    // 2) HER ŞUBENİN ÖĞRENCİLERİNİ BAĞIMSIZ VE TAMAMEN RASTGELE KARIŞTIR!
    // Böylece her dağıtımda şubenin içindeki sıra tamamen değişir (hep aynı ilk 4 kişi gelmez!)
    for (final list in studentBuckets.values) {
      list.shuffle(rand);
    }

    // 3) Salonlar arasında dağıtım
    for (int rIdx = 0; rIdx < generatedRooms.length; rIdx++) {
      final room = generatedRooms[rIdx];
      final allowedQuota = roomQuotas[rIdx] ?? room.seats.length;
      final Map<String, SeatCoordinate> roomSeatMap = {
        for (final seat in room.seats) '${seat.row}-${seat.col}-${seat.slotIndex}': seat,
      };

      int seatedInRoom = 0;

      for (final currentSeat in room.seats) {
        if (currentSeat.isOccupied) continue;
        if (seatedInRoom >= allowedQuota && _hasRemainingStudents(studentBuckets)) {
          // Bu salondaki dengeli kota doldu, diğer salonlara geç
          break;
        }

        final surroundingStudents = _getSurroundingStudents(roomSeatMap, currentSeat);
        final forbiddenGradeLevels = surroundingStudents.map((s) => s.gradeLevel).toSet();
        final forbiddenClassNames = surroundingStudents.map((s) => s.className).toSet();

        // 1. Tercih: Hem sınıf seviyesi hem şube farklı olsun
        ExamStudent? selectedStudent = _pickBestStudent(
          studentBuckets: studentBuckets,
          forbiddenGradeLevels: forbiddenGradeLevels,
          forbiddenClassNames: forbiddenClassNames,
          hasMultipleGrades: params.gradeLevels.length > 1,
          rand: rand,
        );

        // 2. Tercih: Aynı seviye olabilir ama şube mutlaka farklı olsun
        selectedStudent ??= _pickBestStudent(
          studentBuckets: studentBuckets,
          forbiddenGradeLevels: {},
          forbiddenClassNames: forbiddenClassNames,
          hasMultipleGrades: params.gradeLevels.length > 1,
          rand: rand,
        );

        // 3. Tercih: Kurala uyan kalmadıysa kalanlardan rastgele seç
        selectedStudent ??= _pickAnyRemainingStudent(studentBuckets, rand);

        if (selectedStudent != null) {
          currentSeat.student = selectedStudent;
          seatedInRoom++;
        }
      }
    }

    // Artan öğrenci kalmışsa kalan boşluklara doldur
    if (_hasRemainingStudents(studentBuckets)) {
      for (final room in generatedRooms) {
        for (final seat in room.seats) {
          if (!seat.isOccupied) {
            final st = _pickAnyRemainingStudent(studentBuckets, rand);
            if (st != null) seat.student = st;
          }
        }
      }
    }
  }

  // ===========================================================================
  // MOD 2: SEVİYE İÇİ ÇAPRAZ DAĞITIM (Şubeler Seviye İçinde Çapraz)
  // ===========================================================================
  static void _distributeGradeLevelCross(
    ButterflyDistributionParams params,
    List<ExamRoom> generatedRooms,
    Random rand,
    Map<int, int> roomQuotas,
  ) {
    // 1) Şubeleri kovalara ayır
    final Map<String, List<ExamStudent>> branchBuckets = {};
    for (final s in params.students) {
      branchBuckets.putIfAbsent(s.className, () => []).add(s.clone());
    }

    // 2) Her şubenin kendi öğrencilerini tamamen rastgele karıştır
    for (final l in branchBuckets.values) {
      l.shuffle(rand);
    }

    // 3) Salonlar arasında dağıtım
    for (int rIdx = 0; rIdx < generatedRooms.length; rIdx++) {
      final room = generatedRooms[rIdx];
      final allowedQuota = roomQuotas[rIdx] ?? room.seats.length;
      final Map<String, SeatCoordinate> roomSeatMap = {
        for (final seat in room.seats) '${seat.row}-${seat.col}-${seat.slotIndex}': seat,
      };

      int seatedInRoom = 0;

      for (final currentSeat in room.seats) {
        if (currentSeat.isOccupied) continue;
        if (seatedInRoom >= allowedQuota && _hasRemainingStudents(branchBuckets)) {
          break;
        }

        final surroundingStudents = _getSurroundingStudents(roomSeatMap, currentSeat);
        final forbiddenClassNames = surroundingStudents.map((s) => s.className).toSet();

        ExamStudent? selected = _pickBestStudent(
          studentBuckets: branchBuckets,
          forbiddenGradeLevels: {},
          forbiddenClassNames: forbiddenClassNames,
          hasMultipleGrades: false,
          rand: rand,
        );

        selected ??= _pickAnyRemainingStudent(branchBuckets, rand);

        if (selected != null) {
          currentSeat.student = selected;
          seatedInRoom++;
        }
      }
    }

    // Kalan öğrenci varsa boş koltuklara yerleştir
    if (_hasRemainingStudents(branchBuckets)) {
      for (final room in generatedRooms) {
        for (final seat in room.seats) {
          if (!seat.isOccupied) {
            final st = _pickAnyRemainingStudent(branchBuckets, rand);
            if (st != null) seat.student = st;
          }
        }
      }
    }
  }

  // ===========================================================================
  // MOD 3: SIRALI DAĞITIM (Şube ve Numaraya Göre Standart Sıralı)
  // ===========================================================================
  static int _naturalCompare(String a, String b) {
    final re = RegExp(r'(\d+)|(\D+)');
    final pa = re.allMatches(a.trim().toLowerCase()).map((m) => m.group(0)!).toList();
    final pb = re.allMatches(b.trim().toLowerCase()).map((m) => m.group(0)!).toList();
    for (int i = 0; i < pa.length && i < pb.length; i++) {
      final na = int.tryParse(pa[i]);
      final nb = int.tryParse(pb[i]);
      final c = (na != null && nb != null)
          ? na.compareTo(nb)
          : pa[i].compareTo(pb[i]);
      if (c != 0) return c;
    }
    return pa.length.compareTo(pb.length);
  }

  static void _distributeSequentially(
    ButterflyDistributionParams params,
    List<ExamRoom> generatedRooms,
    Map<int, int> roomQuotas,
  ) {
    // Öğrencilerin şubeleri değiştirilmez; yalnızca şube sırasına göre dizilir.
    final sorted = List<ExamStudent>.from(params.students);
    sorted.sort((a, b) {
      final cComp = _naturalCompare(a.className, b.className);
      if (cComp != 0) return cComp;
      return _naturalCompare(a.studentNumber, b.studentNumber);
    });

    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s\-_/.]'), '');

    // 1) Her şube, adı eşleşen salona (501 -> 501 dersliği) yerleştirilir.
    final leftovers = <ExamStudent>[];
    final byClass = <String, List<ExamStudent>>{};
    for (final s in sorted) {
      byClass.putIfAbsent(s.className, () => []).add(s);
    }
    final usedRooms = <int>{};
    for (final entry in byClass.entries) {
      final rIdx = generatedRooms.indexWhere((r) =>
          !usedRooms.contains(generatedRooms.indexOf(r)) &&
          norm(r.classroomName) == norm(entry.key));
      if (rIdx < 0) {
        leftovers.addAll(entry.value);
        continue;
      }
      usedRooms.add(rIdx);
      final seats = generatedRooms[rIdx].seats;
      int i = 0;
      for (final st in entry.value) {
        if (i < seats.length) {
          seats[i++].student = st.clone();
        } else {
          leftovers.add(st);
        }
      }
    }

    // 2) Eşleşen salonu olmayan / taşan öğrenciler kalan boş koltuklara sırayla yerleşir.
    int li = 0;
    for (final room in generatedRooms) {
      for (final seat in room.seats) {
        if (li >= leftovers.length) return;
        seat.student ??= leftovers[li++].clone();
      }
    }
  }

  // ===========================================================================
  // YARDIMCI KOMŞULUK VE SEÇİM METOTLARI
  // ===========================================================================
  static bool _hasRemainingStudents(Map<String, List<ExamStudent>> buckets) {
    return buckets.values.any((l) => l.isNotEmpty);
  }


  static List<ExamStudent> _getSurroundingStudents(
    Map<String, SeatCoordinate> roomSeatMap,
    SeatCoordinate seat,
  ) {
    final List<ExamStudent> surrounding = [];

    final otherSlot = (seat.slotIndex == 0) ? 1 : 0;
    final sideSeat = roomSeatMap['${seat.row}-${seat.col}-$otherSlot'];
    if (sideSeat?.student != null) surrounding.add(sideSeat!.student!);

    final frontSeat0 = roomSeatMap['${seat.row - 1}-${seat.col}-0'];
    final frontSeat1 = roomSeatMap['${seat.row - 1}-${seat.col}-1'];
    if (frontSeat0?.student != null) surrounding.add(frontSeat0!.student!);
    if (frontSeat1?.student != null) surrounding.add(frontSeat1!.student!);

    final backSeat0 = roomSeatMap['${seat.row + 1}-${seat.col}-0'];
    final backSeat1 = roomSeatMap['${seat.row + 1}-${seat.col}-1'];
    if (backSeat0?.student != null) surrounding.add(backSeat0!.student!);
    if (backSeat1?.student != null) surrounding.add(backSeat1!.student!);

    return surrounding;
  }

  static ExamStudent? _pickBestStudent({
    required Map<String, List<ExamStudent>> studentBuckets,
    required Set<String> forbiddenGradeLevels,
    required Set<String> forbiddenClassNames,
    required bool hasMultipleGrades,
    required Random rand,
  }) {
    final candidateKeys = <String>[];
    int maxRemaining = 0;

    for (final entry in studentBuckets.entries) {
      final key = entry.key;
      final bucket = entry.value;
      if (bucket.isEmpty) continue;

      final sample = bucket.first;

      if (hasMultipleGrades && forbiddenGradeLevels.contains(sample.gradeLevel)) {
        continue;
      }

      if (forbiddenClassNames.contains(sample.className)) {
        continue;
      }

      if (bucket.length > maxRemaining) {
        maxRemaining = bucket.length;
      }
      candidateKeys.add(key);
    }

    if (candidateKeys.isEmpty) return null;

    // En çok öğrencisi kalan şubeler (veya bunlara çok yakın olanlar) arasından rastgele bir şube seç
    final topCandidates = candidateKeys.where((k) => studentBuckets[k]!.length >= maxRemaining - 2).toList();
    final chosenKey = topCandidates[rand.nextInt(topCandidates.length)];

    return studentBuckets[chosenKey]!.removeAt(0);
  }

  static ExamStudent? _pickAnyRemainingStudent(
    Map<String, List<ExamStudent>> studentBuckets,
    Random rand,
  ) {
    final nonEmpty = studentBuckets.entries.where((e) => e.value.isNotEmpty).map((e) => e.key).toList();
    if (nonEmpty.isEmpty) return null;

    int maxRemaining = 0;
    for (final k in nonEmpty) {
      final len = studentBuckets[k]!.length;
      if (len > maxRemaining) maxRemaining = len;
    }

    final top = nonEmpty.where((k) => studentBuckets[k]!.length >= maxRemaining - 2).toList();
    final chosenKey = top[rand.nextInt(top.length)];
    return studentBuckets[chosenKey]!.removeAt(0);
  }

  /// ===========================================================================
  /// KOLTUK TAKASI (İNTERAKTİF DÜZENLEME - SWAP)
  /// ===========================================================================
  static ExamDistribution swapStudents({
    required ExamDistribution distribution,
    required String sourceRoomId,
    required int sourceSeatNumber,
    required String targetRoomId,
    required int targetSeatNumber,
  }) {
    final cloned = distribution.clone();

    SeatCoordinate? sourceSeat;
    SeatCoordinate? targetSeat;

    for (final room in cloned.rooms) {
      if (room.classroomId == sourceRoomId || room.id == sourceRoomId) {
        for (final s in room.seats) {
          if (s.seatNumber == sourceSeatNumber) {
            sourceSeat = s;
            break;
          }
        }
      }
      if (room.classroomId == targetRoomId || room.id == targetRoomId) {
        for (final s in room.seats) {
          if (s.seatNumber == targetSeatNumber) {
            targetSeat = s;
            break;
          }
        }
      }
    }

    if (sourceSeat != null && targetSeat != null) {
      final tempStudent = sourceSeat.student;
      sourceSeat.student = targetSeat.student;
      targetSeat.student = tempStudent;
    }

    return cloned;
  }
}
