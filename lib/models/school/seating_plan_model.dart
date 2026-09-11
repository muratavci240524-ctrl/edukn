import 'package:cloud_firestore/cloud_firestore.dart';

/// Masa tipi (Tekli veya Çiftli sıra)
enum DeskType {
  single, // 1 koltuk
  double, // 2 koltuk
}

/// Izgaradaki bir hücrenin durumu
enum CellType {
  desk, // Masa (oturulabilir)
  aisle, // Koridor / Boşluk (oturulamaz)
  teacherDesk, // Öğretmen masası / Kürsü
}

/// Tek bir koltuk yuvası
class SeatSlot {
  final int slotIndex; // 0: Sol / Tekli, 1: Sağ
  String? studentId;
  String? studentName;
  String? studentNumber;
  String? gender; // 'E', 'K' vb.
  String? photoUrl;
  bool isPinned; // Öğretmen tarafından sabitlendi mi

  SeatSlot({
    required this.slotIndex,
    this.studentId,
    this.studentName,
    this.studentNumber,
    this.gender,
    this.photoUrl,
    this.isPinned = false,
  });

  bool get isOccupied => studentId != null && studentId!.isNotEmpty;

  SeatSlot copyWith({
    int? slotIndex,
    String? studentId,
    String? studentName,
    String? studentNumber,
    String? gender,
    String? photoUrl,
    bool? isPinned,
  }) {
    return SeatSlot(
      slotIndex: slotIndex ?? this.slotIndex,
      studentId: studentId ?? this.studentId,
      studentName: studentName ?? this.studentName,
      studentNumber: studentNumber ?? this.studentNumber,
      gender: gender ?? this.gender,
      photoUrl: photoUrl ?? this.photoUrl,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'slotIndex': slotIndex,
      'studentId': studentId,
      'studentName': studentName,
      'studentNumber': studentNumber,
      'gender': gender,
      'photoUrl': photoUrl,
      'isPinned': isPinned,
    };
  }

  factory SeatSlot.fromMap(Map<String, dynamic> map) {
    return SeatSlot(
      slotIndex: map['slotIndex'] ?? 0,
      studentId: map['studentId'],
      studentName: map['studentName'],
      studentNumber: map['studentNumber']?.toString(),
      gender: map['gender'],
      photoUrl: map['photoUrl'],
      isPinned: map['isPinned'] ?? false,
    );
  }
}

/// Izgaradaki tek bir masa hücresi
class DeskCell {
  final int row;
  final int col;
  CellType cellType;
  DeskType deskType;
  String? customLabel;
  List<SeatSlot> slots;

  DeskCell({
    required this.row,
    required this.col,
    this.cellType = CellType.desk,
    this.deskType = DeskType.double,
    this.customLabel,
    List<SeatSlot>? slots,
  }) : slots = slots ??
            (cellType == CellType.desk
                ? (deskType == DeskType.double
                    ? [SeatSlot(slotIndex: 0), SeatSlot(slotIndex: 1)]
                    : [SeatSlot(slotIndex: 0)])
                : []);

  bool get isAisle => cellType == CellType.aisle;
  bool get isDesk => cellType == CellType.desk;
  int get capacity => isDesk ? (deskType == DeskType.double ? 2 : 1) : 0;

  String get coordinateKey => '$row-$col';

  Map<String, dynamic> toMap() {
    return {
      'row': row,
      'col': col,
      'cellType': cellType.name,
      'deskType': deskType.name,
      'customLabel': customLabel,
      'slots': slots.map((s) => s.toMap()).toList(),
    };
  }

  factory DeskCell.fromMap(Map<String, dynamic> map) {
    final cellTypeStr = map['cellType'] as String? ?? 'desk';
    final cellType = CellType.values.firstWhere(
      (e) => e.name == cellTypeStr,
      orElse: () => CellType.desk,
    );

    final deskTypeStr = map['deskType'] as String? ?? 'double';
    final deskType = DeskType.values.firstWhere(
      (e) => e.name == deskTypeStr,
      orElse: () => DeskType.double,
    );

    final rawSlots = (map['slots'] as List<dynamic>?) ?? [];
    final slots = rawSlots.map((s) => SeatSlot.fromMap(Map<String, dynamic>.from(s as Map))).toList();

    return DeskCell(
      row: map['row'] ?? 0,
      col: map['col'] ?? 0,
      cellType: cellType,
      deskType: deskType,
      customLabel: map['customLabel'],
      slots: slots,
    );
  }

  DeskCell clone() {
    return DeskCell(
      row: row,
      col: col,
      cellType: cellType,
      deskType: deskType,
      customLabel: customLabel,
      slots: slots.map((s) => s.copyWith()).toList(),
    );
  }
}

/// Derslik Masa Düzeni Şablonu
class ClassroomLayout {
  final String? id;
  final String name; // Şablon adı (Örn: Standart 3 Blok 18 Masa)
  final String? classroomId; // Bağlı olduğu derslik ID (varsa)
  final String? classroomName;
  final String institutionId;
  final String schoolTypeId;
  final int rows;
  final int cols;
  final DeskType defaultDeskType;
  final List<DeskCell> cells;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isDefault;

  ClassroomLayout({
    this.id,
    required this.name,
    this.classroomId,
    this.classroomName,
    required this.institutionId,
    required this.schoolTypeId,
    required this.rows,
    required this.cols,
    this.defaultDeskType = DeskType.double,
    required this.cells,
    required this.createdAt,
    this.updatedAt,
    this.isDefault = false,
  });

  int get totalDeskCount => cells.where((c) => c.isDesk).length;
  int get totalCapacity => cells.fold<int>(0, (sum, c) => sum + c.capacity);

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'classroomId': classroomId,
      'classroomName': classroomName,
      'institutionId': institutionId,
      'schoolTypeId': schoolTypeId,
      'rows': rows,
      'cols': cols,
      'defaultDeskType': defaultDeskType.name,
      'cells': cells.map((c) => c.toMap()).toList(),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'isDefault': isDefault,
    };
  }

  factory ClassroomLayout.fromMap(Map<String, dynamic> map, String id) {
    final rawCells = (map['cells'] as List<dynamic>?) ?? [];
    final cells = rawCells.map((c) => DeskCell.fromMap(Map<String, dynamic>.from(c as Map))).toList();

    final deskTypeStr = map['defaultDeskType'] as String? ?? 'double';
    final deskType = DeskType.values.firstWhere(
      (e) => e.name == deskTypeStr,
      orElse: () => DeskType.double,
    );

    return ClassroomLayout(
      id: id,
      name: map['name'] ?? 'Masa Düzeni',
      classroomId: map['classroomId'],
      classroomName: map['classroomName'],
      institutionId: map['institutionId'] ?? '',
      schoolTypeId: map['schoolTypeId'] ?? '',
      rows: map['rows'] ?? 4,
      cols: map['cols'] ?? 3,
      defaultDeskType: deskType,
      cells: cells,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      isDefault: map['isDefault'] ?? false,
    );
  }

  ClassroomLayout clone() {
    return ClassroomLayout(
      id: id,
      name: name,
      classroomId: classroomId,
      classroomName: classroomName,
      institutionId: institutionId,
      schoolTypeId: schoolTypeId,
      rows: rows,
      cols: cols,
      defaultDeskType: defaultDeskType,
      cells: cells.map((c) => c.clone()).toList(),
      createdAt: createdAt,
      updatedAt: updatedAt,
      isDefault: isDefault,
    );
  }

  /// Hazır Şablonlar Üretici
  static ClassroomLayout createPreset({
    required String name,
    required String institutionId,
    required String schoolTypeId,
    required String presetType, // '3_col_double', 'u_shape', '2_col_single', 'group_tables'
    String? classroomId,
    String? classroomName,
  }) {
    List<DeskCell> cells = [];
    int rows = 4;
    int cols = 3;
    DeskType defaultType = DeskType.double;

    switch (presetType) {
      case '3_col_double':
        rows = 4;
        cols = 3;
        defaultType = DeskType.double;
        for (int r = 0; r < rows; r++) {
          for (int c = 0; c < cols; c++) {
            cells.add(DeskCell(
              row: r,
              col: c,
              cellType: CellType.desk,
              deskType: DeskType.double,
              customLabel: 'Sıra ${r + 1} - Blok ${c + 1}',
            ));
          }
        }
        break;

      case '3_col_double_with_aisles':
        // 5 sütun: Sütun 0 (Masa), Sütun 1 (Koridor), Sütun 2 (Masa), Sütun 3 (Koridor), Sütun 4 (Masa)
        rows = 4;
        cols = 5;
        defaultType = DeskType.double;
        for (int r = 0; r < rows; r++) {
          for (int c = 0; c < cols; c++) {
            final isAisle = (c == 1 || c == 3);
            cells.add(DeskCell(
              row: r,
              col: c,
              cellType: isAisle ? CellType.aisle : CellType.desk,
              deskType: DeskType.double,
              customLabel: isAisle ? 'Koridor' : 'Sıra ${r + 1} - Blok ${(c ~/ 2) + 1}',
            ));
          }
        }
        break;

      case 'u_shape':
        // U Düzeni (5x5, kenarlar masa, ortalar koridor)
        rows = 4;
        cols = 5;
        defaultType = DeskType.single;
        for (int r = 0; r < rows; r++) {
          for (int c = 0; c < cols; c++) {
            final isDesk = (c == 0 || c == cols - 1 || r == rows - 1);
            cells.add(DeskCell(
              row: r,
              col: c,
              cellType: isDesk ? CellType.desk : CellType.aisle,
              deskType: DeskType.single,
              customLabel: isDesk ? 'Masa ${r + 1}-${c + 1}' : 'Boşluk',
            ));
          }
        }
        break;

      case '2_col_single':
        rows = 5;
        cols = 3;
        defaultType = DeskType.single;
        for (int r = 0; r < rows; r++) {
          for (int c = 0; c < cols; c++) {
            final isAisle = (c == 1);
            cells.add(DeskCell(
              row: r,
              col: c,
              cellType: isAisle ? CellType.aisle : CellType.desk,
              deskType: DeskType.single,
              customLabel: isAisle ? 'Koridor' : 'Masa ${r + 1}-${c == 0 ? 1 : 2}',
            ));
          }
        }
        break;

      case 'group_tables':
        // 6'lı grup masaları (3 grup)
        rows = 3;
        cols = 3;
        defaultType = DeskType.double;
        for (int r = 0; r < rows; r++) {
          for (int c = 0; c < cols; c++) {
            final isGroup = (r % 2 == 0 && c % 2 == 0);
            cells.add(DeskCell(
              row: r,
              col: c,
              cellType: isGroup ? CellType.desk : CellType.aisle,
              deskType: DeskType.double,
              customLabel: isGroup ? 'Grup ${((r ~/ 2) * 2) + (c ~/ 2) + 1}' : 'Koridor',
            ));
          }
        }
        break;

      case '5x5_single_24':
      case '5x5_closed_bottom_left':
        // 5x5 Grid Düzen (24 Tekli Masa - Sol Alt Hücre Kapalı)
        rows = 5;
        cols = 5;
        defaultType = DeskType.single;
        for (int r = 0; r < rows; r++) {
          for (int c = 0; c < cols; c++) {
            final isBottomLeft = (r == 4 && c == 0);
            cells.add(DeskCell(
              row: r,
              col: c,
              cellType: isBottomLeft ? CellType.aisle : CellType.desk,
              deskType: DeskType.single,
              customLabel: isBottomLeft ? 'Kapalı / Geçiş' : 'Masa ${r + 1}-${c + 1}',
            ));
          }
        }
        break;

      default:
        rows = 4;
        cols = 3;
        for (int r = 0; r < rows; r++) {
          for (int c = 0; c < cols; c++) {
            cells.add(DeskCell(row: r, col: c));
          }
        }
    }

    return ClassroomLayout(
      name: name,
      classroomId: classroomId,
      classroomName: classroomName,
      institutionId: institutionId,
      schoolTypeId: schoolTypeId,
      rows: rows,
      cols: cols,
      defaultDeskType: defaultType,
      cells: cells,
      createdAt: DateTime.now(),
      isDefault: true,
    );
  }
}

/// Kaydedilen Sınıf Oturma Planı
class SeatingPlan {
  final String? id;
  final String title; // Plan adı (örn: 1. Dönem 3. Hafta Oturma Düzeni)
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final String classId; // Şube ID (örn: 8-A)
  final String className;
  final String? classroomId; // Derslik ID
  final String? classroomName;
  final String? layoutId; // Kullanılan şablon ID
  final String? termId; // Dönem ID
  final String? termName;
  final DateTime planDate;
  final List<DeskCell> cells;
  final String? createdBy;
  final String? createdByName;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? notes;
  final double? penaltyScore; // Algoritmanın hesapladığı toplam ceza puanı
  final Map<String, StudentSeatingConstraint> studentConstraints; // Öğrenci ID -> Kısıtlamalar & Tercihler

  SeatingPlan({
    this.id,
    required this.title,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.classId,
    required this.className,
    this.classroomId,
    this.classroomName,
    this.layoutId,
    this.termId,
    this.termName,
    required this.planDate,
    required this.cells,
    this.createdBy,
    this.createdByName,
    required this.createdAt,
    this.updatedAt,
    this.notes,
    this.penaltyScore,
    Map<String, StudentSeatingConstraint>? studentConstraints,
  }) : studentConstraints = studentConstraints ?? {};

  int get assignedStudentCount {
    int count = 0;
    for (var cell in cells) {
      if (cell.isDesk) {
        count += cell.slots.where((s) => s.isOccupied).length;
      }
    }
    return count;
  }

  int get pinnedStudentCount {
    int count = 0;
    for (var cell in cells) {
      if (cell.isDesk) {
        count += cell.slots.where((s) => s.isOccupied && s.isPinned).length;
      }
    }
    return count;
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'institutionId': institutionId,
      'schoolTypeId': schoolTypeId,
      'schoolTypeName': schoolTypeName,
      'classId': classId,
      'className': className,
      'classroomId': classroomId,
      'classroomName': classroomName,
      'layoutId': layoutId,
      'termId': termId,
      'termName': termName,
      'planDate': planDate,
      'cells': cells.map((c) => c.toMap()).toList(),
      'createdBy': createdBy,
      'createdByName': createdByName,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'notes': notes,
      'penaltyScore': penaltyScore,
      'studentConstraints': studentConstraints.map((k, v) => MapEntry(k, v.toMap())),
    };
  }

  factory SeatingPlan.fromMap(Map<String, dynamic> map, String id) {
    final rawCells = (map['cells'] as List<dynamic>?) ?? [];
    final cells = rawCells.map((c) => DeskCell.fromMap(Map<String, dynamic>.from(c as Map))).toList();

    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is String) {
        final parsed = DateTime.tryParse(val);
        if (parsed != null) return parsed;
      }
      return DateTime.now();
    }

    final rawConstraints = (map['studentConstraints'] as Map<dynamic, dynamic>?) ?? {};
    final constraints = rawConstraints.map(
      (k, v) => MapEntry(
        k.toString(),
        StudentSeatingConstraint.fromMap(Map<String, dynamic>.from(v as Map)),
      ),
    );

    return SeatingPlan(
      id: id,
      title: map['title'] ?? 'Oturma Planı',
      institutionId: map['institutionId'] ?? '',
      schoolTypeId: map['schoolTypeId'] ?? '',
      schoolTypeName: map['schoolTypeName'] ?? '',
      classId: map['classId'] ?? '',
      className: map['className'] ?? '',
      classroomId: map['classroomId'],
      classroomName: map['classroomName'],
      layoutId: map['layoutId'],
      termId: map['termId'],
      termName: map['termName'],
      planDate: parseDate(map['planDate']),
      cells: cells,
      createdBy: map['createdBy'],
      createdByName: map['createdByName'],
      createdAt: parseDate(map['createdAt']),
      updatedAt: map['updatedAt'] != null ? parseDate(map['updatedAt']) : null,
      notes: map['notes'],
      penaltyScore: (map['penaltyScore'] as num?)?.toDouble(),
      studentConstraints: constraints,
    );
  }
}

/// Öğrenci Oturma Tercihi / Sıra Kriterleri
enum RowZonePreference {
  any, // Farketmez / Genel
  frontRow, // Ön Sıralar (1. ve 2. Sıra)
  middleRow, // Orta Sıralar
  backRow, // Arka Sıralar (Uzun boy vb.)
  windowSide, // Pencere Kenarı
  corridorSide, // Koridor / Kapı Kenarı
}

/// Öğrenci Oturma Kısıtlamaları (Birlikte oturmama, sıra tercihi, ön sıra zorunluluğu)
class StudentSeatingConstraint {
  final String studentId;
  final String? studentName;
  Set<String> avoidStudentIds; // Yan yana / Birlikte oturmaması gereken öğrenci ID'leri
  RowZonePreference rowZonePreference; // Sıra/Bölge Tercihi
  String? preferredNeighborId; // Yanında oturması istenen (opsiyonel)
  bool isFrontRowRequired; // Ön sıra zorunlu mu (Görme/İşitme/Odaklanma)
  String? note;

  StudentSeatingConstraint({
    required this.studentId,
    this.studentName,
    Set<String>? avoidStudentIds,
    this.rowZonePreference = RowZonePreference.any,
    this.preferredNeighborId,
    this.isFrontRowRequired = false,
    this.note,
  }) : avoidStudentIds = avoidStudentIds ?? {};

  Map<String, dynamic> toMap() {
    return {
      'studentId': studentId,
      'studentName': studentName,
      'avoidStudentIds': avoidStudentIds.toList(),
      'rowZonePreference': rowZonePreference.name,
      'preferredNeighborId': preferredNeighborId,
      'isFrontRowRequired': isFrontRowRequired,
      'note': note,
    };
  }

  factory StudentSeatingConstraint.fromMap(Map<String, dynamic> map) {
    return StudentSeatingConstraint(
      studentId: map['studentId'] ?? '',
      studentName: map['studentName'],
      avoidStudentIds: ((map['avoidStudentIds'] as List<dynamic>?) ?? []).map((e) => e.toString()).toSet(),
      rowZonePreference: RowZonePreference.values.firstWhere(
        (e) => e.name == map['rowZonePreference'],
        orElse: () => RowZonePreference.any,
      ),
      preferredNeighborId: map['preferredNeighborId'],
      isFrontRowRequired: map['isFrontRowRequired'] ?? false,
      note: map['note'],
    );
  }

  StudentSeatingConstraint clone() {
    return StudentSeatingConstraint(
      studentId: studentId,
      studentName: studentName,
      avoidStudentIds: Set<String>.from(avoidStudentIds),
      rowZonePreference: rowZonePreference,
      preferredNeighborId: preferredNeighborId,
      isFrontRowRequired: isFrontRowRequired,
      note: note,
    );
  }
}

/// Öğrencinin geçmişteki bir oturum kaydı (Analitik ve algoritma için)
class HistoricalSeatRecord {
  final String planId;
  final DateTime date;
  final int row;
  final int col;
  final int slotIndex;
  final String? deskLabel;
  final String? neighborStudentId;
  final String? neighborStudentName;

  HistoricalSeatRecord({
    required this.planId,
    required this.date,
    required this.row,
    required this.col,
    required this.slotIndex,
    this.deskLabel,
    this.neighborStudentId,
    this.neighborStudentName,
  });

  String get coordinateKey => '$row-$col-$slotIndex';
  String get deskCoordinate => '$row-$col';
}

/// Öğrenci Bilgi Modeli (Oturma Planı Seçim için)
class SeatingStudentItem {
  final String id;
  final String fullName;
  final String? studentNumber;
  final String? gender;
  final String? photoUrl;
  final String? className;
  final String? classId;
  final bool isSpecialNeed; // Özel durum (ön sıra ihtiyacı vb.)

  SeatingStudentItem({
    required this.id,
    required this.fullName,
    this.studentNumber,
    this.gender,
    this.photoUrl,
    this.className,
    this.classId,
    this.isSpecialNeed = false,
  });

  factory SeatingStudentItem.fromMap(Map<String, dynamic> map, String id) {
    return SeatingStudentItem(
      id: id,
      fullName: map['fullName'] ?? map['name'] ?? 'İsimsiz Öğrenci',
      studentNumber: map['studentNumber']?.toString() ?? map['schoolNumber']?.toString(),
      gender: map['gender'] ?? map['cinsiyet'],
      photoUrl: map['photoUrl'] ?? map['profileImageUrl'],
      className: map['className'],
      classId: map['classId'],
      isSpecialNeed: map['isSpecialNeed'] ?? map['specialEducation'] ?? false,
    );
  }
}
