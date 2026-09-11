import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import '../models/school/seating_plan_model.dart';

/// Tek Bir Öğrencinin Oturma Analizi
class StudentSeatingAnalytics {
  final String studentId;
  final String studentName;
  final String? studentNumber;
  final String? gender;
  final int totalPlansCount;
  final Map<String, int> coordinateCounts; // "row-col" -> count
  final Map<String, String> coordinateLabels; // "row-col" -> "Sıra 1 Masa 2"
  final Map<String, int> neighborCounts; // "Öğrenci Adı" -> count
  final int frontRowCount; // Satır 0 veya 1
  final int middleRowCount; // Satır 2
  final int backRowCount; // Satır 3+
  final int leftBlockCount; // Sütun 0
  final int centerBlockCount; // Sütun 1 (3'lüde)
  final int rightBlockCount; // Sütun 2+

  StudentSeatingAnalytics({
    required this.studentId,
    required this.studentName,
    this.studentNumber,
    this.gender,
    required this.totalPlansCount,
    required this.coordinateCounts,
    required this.coordinateLabels,
    required this.neighborCounts,
    required this.frontRowCount,
    required this.middleRowCount,
    required this.backRowCount,
    required this.leftBlockCount,
    required this.centerBlockCount,
    required this.rightBlockCount,
  });

  double get frontRowPercentage =>
      totalPlansCount > 0 ? (frontRowCount / totalPlansCount) * 100 : 0.0;
  double get middleRowPercentage =>
      totalPlansCount > 0 ? (middleRowCount / totalPlansCount) * 100 : 0.0;
  double get backRowPercentage =>
      totalPlansCount > 0 ? (backRowCount / totalPlansCount) * 100 : 0.0;

  String get mostFrequentCoordinate {
    if (coordinateCounts.isEmpty) return 'Kayıt Yok';
    var sorted = coordinateCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topKey = sorted.first.key;
    final label = coordinateLabels[topKey] ?? topKey;
    return '$label (${sorted.first.value} kez)';
  }

  String get mostFrequentNeighbor {
    if (neighborCounts.isEmpty) return 'Kayıt Yok';
    var sorted = neighborCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return '${sorted.first.key} (${sorted.first.value} kez)';
  }
}

/// Sınıf Geneli Analitik Raporu
class ClassSeatingAnalyticsReport {
  final String classId;
  final String className;
  final int totalPlansAnalyzed;
  final DateTime? earliestDate;
  final DateTime? latestDate;
  final List<StudentSeatingAnalytics> studentAnalytics;
  final Map<String, int> classroomHeatmap; // "row-col" -> toplam oturulma sayısı
  final int maxRow;
  final int maxCol;

  ClassSeatingAnalyticsReport({
    required this.classId,
    required this.className,
    required this.totalPlansAnalyzed,
    this.earliestDate,
    this.latestDate,
    required this.studentAnalytics,
    required this.classroomHeatmap,
    required this.maxRow,
    required this.maxCol,
  });
}

/// Oturma Planı Analitik Motoru
class SeatingAnalyticsService {
  final FirebaseFirestore _firestore;

  SeatingAnalyticsService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Şubeye ait tüm oturma planlarını getirip analitik raporu üretir
  Future<ClassSeatingAnalyticsReport> generateReportForClass({
    required String institutionId,
    required String classId,
    required String className,
    String? termId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    Query query = _firestore
        .collection('seating_plans')
        .where('institutionId', isEqualTo: institutionId)
        .where('classId', isEqualTo: classId);

    if (termId != null && termId.isNotEmpty) {
      query = query.where('termId', isEqualTo: termId);
    }

    QuerySnapshot snapshot;
    try {
      snapshot = await query.get();
    } catch (_) {
      snapshot = await _firestore
          .collection('seating_plans')
          .where('institutionId', isEqualTo: institutionId)
          .where('classId', isEqualTo: classId)
          .get();
    }

    List<SeatingPlan> plans = snapshot.docs
        .map((doc) => SeatingPlan.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .toList();
    plans.sort((a, b) => a.planDate.compareTo(b.planDate));

    // Tarih filtreleri
    if (startDate != null) {
      plans = plans.where((p) => p.planDate.isAfter(startDate.subtract(const Duration(days: 1)))).toList();
    }
    if (endDate != null) {
      plans = plans.where((p) => p.planDate.isBefore(endDate.add(const Duration(days: 1)))).toList();
    }

    return computeReport(plans: plans, classId: classId, className: className);
  }

  /// Oturma planları listesini analiz eder
  ClassSeatingAnalyticsReport computeReport({
    required List<SeatingPlan> plans,
    required String classId,
    required String className,
  }) {
    final Map<String, _StudentAccumulator> accumulators = {};
    final Map<String, int> heatmap = {};
    int maxR = 0;
    int maxC = 0;

    DateTime? minDate;
    DateTime? maxDate;

    for (var plan in plans) {
      if (minDate == null || plan.planDate.isBefore(minDate)) minDate = plan.planDate;
      if (maxDate == null || plan.planDate.isAfter(maxDate)) maxDate = plan.planDate;

      for (var cell in plan.cells) {
        if (!cell.isDesk) continue;

        if (cell.row > maxR) maxR = cell.row;
        if (cell.col > maxC) maxC = cell.col;

        final coordKey = '${cell.row}-${cell.col}';
        final coordLabel = cell.customLabel ?? 'Sıra ${cell.row + 1} - Sütun ${cell.col + 1}';

        for (int i = 0; i < cell.slots.length; i++) {
          final slot = cell.slots[i];
          if (!slot.isOccupied) continue;

          // Isı haritası artır
          heatmap[coordKey] = (heatmap[coordKey] ?? 0) + 1;

          final studentId = slot.studentId!;
          final acc = accumulators.putIfAbsent(
            studentId,
            () => _StudentAccumulator(
              studentId: studentId,
              studentName: slot.studentName ?? 'Bilinmeyen Öğrenci',
              studentNumber: slot.studentNumber,
              gender: slot.gender,
            ),
          );

          acc.totalPlans++;
          acc.coordinateCounts[coordKey] = (acc.coordinateCounts[coordKey] ?? 0) + 1;
          acc.coordinateLabels[coordKey] = coordLabel;

          // Sıra / Blok hesapları
          if (cell.row <= 1) {
            acc.frontRowCount++;
          } else if (cell.row == 2) {
            acc.middleRowCount++;
          } else {
            acc.backRowCount++;
          }

          if (cell.col == 0) {
            acc.leftBlockCount++;
          } else if (cell.col == 1) {
            acc.centerBlockCount++;
          } else {
            acc.rightBlockCount++;
          }

          // Sıra arkadaşı (Neighbor)
          if (cell.slots.length > 1) {
            final otherSlot = cell.slots[i == 0 ? 1 : 0];
            if (otherSlot.isOccupied && otherSlot.studentName != null) {
              final neighborName = otherSlot.studentName!;
              acc.neighborCounts[neighborName] = (acc.neighborCounts[neighborName] ?? 0) + 1;
            }
          }
        }
      }
    }

    final studentList = accumulators.values.map((acc) {
      return StudentSeatingAnalytics(
        studentId: acc.studentId,
        studentName: acc.studentName,
        studentNumber: acc.studentNumber,
        gender: acc.gender,
        totalPlansCount: acc.totalPlans,
        coordinateCounts: acc.coordinateCounts,
        coordinateLabels: acc.coordinateLabels,
        neighborCounts: acc.neighborCounts,
        frontRowCount: acc.frontRowCount,
        middleRowCount: acc.middleRowCount,
        backRowCount: acc.backRowCount,
        leftBlockCount: acc.leftBlockCount,
        centerBlockCount: acc.centerBlockCount,
        rightBlockCount: acc.rightBlockCount,
      );
    }).toList();

    // İsme göre sırala
    studentList.sort((a, b) => a.studentName.compareTo(b.studentName));

    return ClassSeatingAnalyticsReport(
      classId: classId,
      className: className,
      totalPlansAnalyzed: plans.length,
      earliestDate: minDate,
      latestDate: maxDate,
      studentAnalytics: studentList,
      classroomHeatmap: heatmap,
      maxRow: maxR + 1,
      maxCol: maxC + 1,
    );
  }

  /// Analitik Raporu Excel Formatında Üretir
  List<int>? exportToExcel(ClassSeatingAnalyticsReport report) {
    final excel = Excel.createExcel();
    final sheet = excel['Oturma Raporu'];
    excel.setDefaultSheet('Oturma Raporu');

    // Başlıklar
    sheet.appendRow([
      TextCellValue('Öğrenci No'),
      TextCellValue('Ad Soyad'),
      TextCellValue('Cinsiyet'),
      TextCellValue('Toplam Oturum Sayısı'),
      TextCellValue('En Sık Oturduğu Masa/Konum'),
      TextCellValue('Ön Sıra Oturumu (Sıra 1-2)'),
      TextCellValue('Ön Sıra Oranı (%)'),
      TextCellValue('Orta Sıra Oturumu'),
      TextCellValue('Arka Sıra Oturumu (Sıra 4+)'),
      TextCellValue('Sol Blok'),
      TextCellValue('Orta Blok'),
      TextCellValue('Sağ Blok'),
      TextCellValue('En Sık Sıra Arkadaşı'),
      TextCellValue('Detaylı Koordinat Dağılımı'),
    ]);

    for (var st in report.studentAnalytics) {
      final coordDetails = st.coordinateCounts.entries
          .map((e) => '${st.coordinateLabels[e.key] ?? e.key}: ${e.value}x')
          .join(', ');

      sheet.appendRow([
        TextCellValue(st.studentNumber ?? '-'),
        TextCellValue(st.studentName),
        TextCellValue(st.gender ?? '-'),
        IntCellValue(st.totalPlansCount),
        TextCellValue(st.mostFrequentCoordinate),
        IntCellValue(st.frontRowCount),
        DoubleCellValue(double.parse(st.frontRowPercentage.toStringAsFixed(1))),
        IntCellValue(st.middleRowCount),
        IntCellValue(st.backRowCount),
        IntCellValue(st.leftBlockCount),
        IntCellValue(st.centerBlockCount),
        IntCellValue(st.rightBlockCount),
        TextCellValue(st.mostFrequentNeighbor),
        TextCellValue(coordDetails),
      ]);
    }

    return excel.encode();
  }
}

class _StudentAccumulator {
  final String studentId;
  final String studentName;
  final String? studentNumber;
  final String? gender;
  int totalPlans = 0;
  final Map<String, int> coordinateCounts = {};
  final Map<String, String> coordinateLabels = {};
  final Map<String, int> neighborCounts = {};
  int frontRowCount = 0;
  int middleRowCount = 0;
  int backRowCount = 0;
  int leftBlockCount = 0;
  int centerBlockCount = 0;
  int rightBlockCount = 0;

  _StudentAccumulator({
    required this.studentId,
    required this.studentName,
    this.studentNumber,
    this.gender,
  });
}
