import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/school/seating_plan_model.dart';

/// Dağıtım Algoritması Parametreleri
class DistributionOptions {
  final bool avoidSameSeat; // Aynı koltuğu önle (yüksek öncelik)
  final bool avoidSameDesk; // Aynı masayı önle
  final bool avoidSameNeighbor; // Aynı sıra arkadaşını önle
  final bool prioritizeSpecialNeedsInFront; // Özel gereksinimli öğrencileri ön sıralara al
  final bool balanceGender; // Masalarda kız-erkek dengesi gözet
  final int historyDepth; // Kaç geçmiş plan incelensin (varsayılan: 5)
  final int optimizationIterations; // Optimizasyon deneme sayısı (varsayılan: 80)

  const DistributionOptions({
    this.avoidSameSeat = true,
    this.avoidSameDesk = true,
    this.avoidSameNeighbor = true,
    this.prioritizeSpecialNeedsInFront = true,
    this.balanceGender = false,
    this.historyDepth = 5,
    this.optimizationIterations = 80,
  });
}

/// Dağıtım Sonucu
class DistributionResult {
  final List<DeskCell> updatedCells;
  final double totalPenalty;
  final int assignedCount;
  final int pinnedCount;
  final Map<String, double> studentPenalties; // Öğrenci ID -> Ceza Puanı
  final List<String> logs;

  DistributionResult({
    required this.updatedCells,
    required this.totalPenalty,
    required this.assignedCount,
    required this.pinnedCount,
    required this.studentPenalties,
    required this.logs,
  });
}

/// Tarihsel Geçmişe Duyarlı Dağıtım Motoru
class SeatingDistributionService {
  final FirebaseFirestore _firestore;

  SeatingDistributionService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Geçmiş planları Firestore'dan çeker
  Future<List<SeatingPlan>> fetchClassHistory({
    required String institutionId,
    required String classId,
    int limit = 10,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('seating_plans')
          .where('institutionId', isEqualTo: institutionId)
          .where('classId', isEqualTo: classId)
          .get();

      final list = snapshot.docs.map((doc) => SeatingPlan.fromMap(doc.data(), doc.id)).toList();
      list.sort((a, b) => b.planDate.compareTo(a.planDate));
      return list.take(limit).toList();
    } catch (e) {
      return [];
    }
  }

  /// Geçmiş planlardan her öğrencinin oturma geçmişini haritalandırır
  Map<String, List<HistoricalSeatRecord>> buildStudentHistoryMap(List<SeatingPlan> history) {
    final Map<String, List<HistoricalSeatRecord>> map = {};

    for (var plan in history) {
      for (var cell in plan.cells) {
        if (!cell.isDesk) continue;

        for (int i = 0; i < cell.slots.length; i++) {
          final slot = cell.slots[i];
          if (!slot.isOccupied) continue;

          final studentId = slot.studentId!;

          // Sıra arkadaşı (neighbor) bul
          String? neighborId;
          String? neighborName;
          if (cell.slots.length > 1) {
            final otherSlot = cell.slots[i == 0 ? 1 : 0];
            if (otherSlot.isOccupied) {
              neighborId = otherSlot.studentId;
              neighborName = otherSlot.studentName;
            }
          }

          final record = HistoricalSeatRecord(
            planId: plan.id ?? '',
            date: plan.planDate,
            row: cell.row,
            col: cell.col,
            slotIndex: slot.slotIndex,
            deskLabel: cell.customLabel,
            neighborStudentId: neighborId,
            neighborStudentName: neighborName,
          );

          map.putIfAbsent(studentId, () => []).add(record);
        }
      }
    }

    return map;
  }

  /// Ana Dağıtım Fonksiyonu (Geçmişe Duyarlı Ceza Puanı Minimizasyonu ve Öğrenci Kriterleri)
  DistributionResult distributeStudents({
    required List<DeskCell> currentCells,
    required List<SeatingStudentItem> allStudents,
    required List<SeatingPlan> historicalPlans,
    DistributionOptions options = const DistributionOptions(),
    Map<String, StudentSeatingConstraint> studentConstraints = const {},
  }) {
    final random = Random();
    final logs = <String>[];

    // 1. Hücreleri klonla
    final List<DeskCell> workingCells = currentCells.map((c) => c.clone()).toList();

    // 2. Geçmiş haritasını çıkar
    final studentHistory = buildStudentHistoryMap(
      historicalPlans.take(options.historyDepth).toList(),
    );

    // 3. Sabitlenmiş (Pinned) öğrencileri tespit et
    final Set<String> pinnedStudentIds = {};
    int pinnedCount = 0;

    for (var cell in workingCells) {
      if (!cell.isDesk) continue;
      for (var slot in cell.slots) {
        if (slot.isOccupied && slot.isPinned) {
          pinnedStudentIds.add(slot.studentId!);
          pinnedCount++;
        }
      }
    }

    // 4. Dağıtılacak serbest öğrencileri belirle
    final List<SeatingStudentItem> freeStudents = allStudents
        .where((s) => !pinnedStudentIds.contains(s.id))
        .toList();

    // 5. Boş (unpinned) koltuk yuvalarını (Seat Reference) belirle
    final List<_SeatTarget> availableTargets = [];
    for (int cIdx = 0; cIdx < workingCells.length; cIdx++) {
      final cell = workingCells[cIdx];
      if (!cell.isDesk) continue;

      for (int sIdx = 0; sIdx < cell.slots.length; sIdx++) {
        final slot = cell.slots[sIdx];
        if (!slot.isPinned) {
          // Boşalt
          slot.studentId = null;
          slot.studentName = null;
          slot.studentNumber = null;
          slot.gender = null;
          slot.photoUrl = null;
          availableTargets.add(_SeatTarget(
            cellIndex: cIdx,
            slotIndex: sIdx,
            row: cell.row,
            col: cell.col,
            slotNo: slot.slotIndex,
            deskCapacity: cell.capacity,
          ));
        }
      }
    }

    logs.add('Toplam Koltuk Kapasitesi: ${workingCells.fold<int>(0, (s, c) => s + c.capacity)}');
    logs.add('Toplam Öğrenci: ${allStudents.length}');
    logs.add('Sabitlenmiş Öğrenci: $pinnedCount');
    logs.add('Dağıtılacak Serbest Öğrenci: ${freeStudents.length}');
    logs.add('Kullanılabilir Boş Koltuk: ${availableTargets.length}');
    if (studentConstraints.isNotEmpty) {
      logs.add('Özel Öğrenci Kısıtlamaları: ${studentConstraints.length} kural devrede.');
    }

    if (freeStudents.length > availableTargets.length) {
      logs.add('⚠️ Uyarı: Öğrenci sayısı boş koltuk sayısından fazla! Bazı öğrenciler yerleştirilemeyebilir.');
    }

    if (freeStudents.isEmpty || availableTargets.isEmpty) {
      return DistributionResult(
        updatedCells: workingCells,
        totalPenalty: 0.0,
        assignedCount: pinnedCount,
        pinnedCount: pinnedCount,
        studentPenalties: {},
        logs: logs,
      );
    }

    // 6. Stochastic Search / Simulated Annealing ile Ceza Puanı Minimizasyonu
    List<SeatingStudentItem?> bestAssignment = [];
    double bestTotalPenalty = double.infinity;
    Map<String, double> bestStudentPenalties = {};

    final int iterations = max(50, options.optimizationIterations);

    for (int iter = 0; iter < iterations; iter++) {
      // Rastgele karıştır
      final List<SeatingStudentItem?> currentTrial = List.filled(availableTargets.length, null);
      final List<SeatingStudentItem> shuffledStudents = List.of(freeStudents)..shuffle(random);

      // Özel gereksinimli & ön sıra tercihli öğrencileri öne alma
      shuffledStudents.sort((a, b) {
        final aReq = a.isSpecialNeed || (studentConstraints[a.id]?.isFrontRowRequired ?? false);
        final bReq = b.isSpecialNeed || (studentConstraints[b.id]?.isFrontRowRequired ?? false);
        if (aReq && !bReq) return -1;
        if (!aReq && bReq) return 1;
        return 0;
      });

      for (int i = 0; i < min(shuffledStudents.length, availableTargets.length); i++) {
        currentTrial[i] = shuffledStudents[i];
      }

      // Bu yerleşimin ceza puanını hesapla
      final penaltyResult = _calculateTrialPenalty(
        workingCells: workingCells,
        targets: availableTargets,
        trialAssignment: currentTrial,
        studentHistory: studentHistory,
        studentConstraints: studentConstraints,
        options: options,
      );

      if (penaltyResult.total < bestTotalPenalty) {
        bestTotalPenalty = penaltyResult.total;
        bestAssignment = List.of(currentTrial);
        bestStudentPenalties = Map.of(penaltyResult.perStudent);

        // Mükemmel 0 puan bulunduysa erken bitir
        if (bestTotalPenalty == 0) break;
      }
    }

    // 7. En iyi dağıtımı hücrelere yaz
    int newlyAssignedCount = 0;
    for (int i = 0; i < availableTargets.length; i++) {
      final target = availableTargets[i];
      final student = i < bestAssignment.length ? bestAssignment[i] : null;

      if (student != null) {
        final slot = workingCells[target.cellIndex].slots[target.slotIndex];
        slot.studentId = student.id;
        slot.studentName = student.fullName;
        slot.studentNumber = student.studentNumber;
        slot.gender = student.gender;
        slot.photoUrl = student.photoUrl;
        slot.isPinned = false;
        newlyAssignedCount++;
      }
    }

    logs.add('✅ Başarılı: $newlyAssignedCount öğrenci yerleştirildi.');
    logs.add('Toplam Ceza Skoru: ${bestTotalPenalty.toStringAsFixed(1)} (Düşük skor = Yüksek kural uyumu)');

    return DistributionResult(
      updatedCells: workingCells,
      totalPenalty: bestTotalPenalty == double.infinity ? 0.0 : bestTotalPenalty,
      assignedCount: pinnedCount + newlyAssignedCount,
      pinnedCount: pinnedCount,
      studentPenalties: bestStudentPenalties,
      logs: logs,
    );
  }

  /// Bir yerleşimin toplam ceza puanını hesaplar
  _PenaltyEvaluation _calculateTrialPenalty({
    required List<DeskCell> workingCells,
    required List<_SeatTarget> targets,
    required List<SeatingStudentItem?> trialAssignment,
    required Map<String, List<HistoricalSeatRecord>> studentHistory,
    required Map<String, StudentSeatingConstraint> studentConstraints,
    required DistributionOptions options,
  }) {
    double totalPenalty = 0.0;
    final Map<String, double> perStudent = {};

    // Hızlı erişim için hedef eşleştirmesi
    final Map<String, SeatingStudentItem?> seatStudentMap = {}; // "cIdx-sIdx" -> student

    for (int i = 0; i < targets.length; i++) {
      final target = targets[i];
      final student = trialAssignment[i];
      seatStudentMap['${target.cellIndex}-${target.slotIndex}'] = student;
    }

    for (int i = 0; i < targets.length; i++) {
      final target = targets[i];
      final student = trialAssignment[i];
      if (student == null) continue;

      double studentPenalty = 0.0;
      final historyList = studentHistory[student.id] ?? [];

      // 1. Geçmiş Koltuk / Masa Cezaları
      for (int hIdx = 0; hIdx < historyList.length; hIdx++) {
        final hist = historyList[hIdx];
        final timeWeight = 1.0 / (hIdx + 1); // En son planın ağırlığı 1.0, 2 öncekinin 0.5 vb.

        // Aynı koltuk (aynı satır, sütun, slot)
        if (options.avoidSameSeat &&
            hist.row == target.row &&
            hist.col == target.col &&
            hist.slotIndex == target.slotNo) {
          studentPenalty += 100.0 * timeWeight;
        }
        // Aynı masa (farklı slot olsa bile)
        else if (options.avoidSameDesk && hist.row == target.row && hist.col == target.col) {
          studentPenalty += 60.0 * timeWeight;
        }
        // Çok yakın masa (Manhattan mesafesi <= 1)
        else {
          final manhattanDist = (hist.row - target.row).abs() + (hist.col - target.col).abs();
          if (manhattanDist == 1) {
            studentPenalty += 25.0 * timeWeight;
          }
        }

        // 2. Sıra Arkadaşı (Neighbor) Cezası
        if (options.avoidSameNeighbor && hist.neighborStudentId != null) {
          final otherSlotIndex = target.slotIndex == 0 ? 1 : 0;
          final cell = workingCells[target.cellIndex];

          if (cell.slots.length > 1) {
            String? currentNeighborId;
            final pinnedSlot = cell.slots[otherSlotIndex];
            if (pinnedSlot.isPinned && pinnedSlot.isOccupied) {
              currentNeighborId = pinnedSlot.studentId;
            } else {
              final trialNeighbor = seatStudentMap['${target.cellIndex}-$otherSlotIndex'];
              currentNeighborId = trialNeighbor?.id;
            }

            if (currentNeighborId != null && currentNeighborId == hist.neighborStudentId) {
              studentPenalty += 50.0 * timeWeight;
            }
          }
        }
      }

      // 3. Öğrenci Özel Kısıtlamaları (Birlikte Oturmama & Sıra Tercihleri)
      final constraint = studentConstraints[student.id];
      if (constraint != null) {
        // A) "Şunla Oturmasın" / Birlikte Oturamaz Kuralı (ÇİFT YÖNLÜ DENETİM)
        final otherSlotIndex = target.slotIndex == 0 ? 1 : 0;
        final cell = workingCells[target.cellIndex];
        if (cell.slots.length > 1) {
          String? currentNeighborId;
          final pinnedSlot = cell.slots[otherSlotIndex];
          if (pinnedSlot.isPinned && pinnedSlot.isOccupied) {
            currentNeighborId = pinnedSlot.studentId;
          } else {
            final trialNeighbor = seatStudentMap['${target.cellIndex}-$otherSlotIndex'];
            currentNeighborId = trialNeighbor?.id;
          }

          if (currentNeighborId != null) {
            final neighborConstraint = studentConstraints[currentNeighborId];
            final isAvoidedByA = constraint.avoidStudentIds.contains(currentNeighborId);
            final isAvoidedByB = neighborConstraint != null && neighborConstraint.avoidStudentIds.contains(student.id);

            if (isAvoidedByA || isAvoidedByB) {
              // Birlikte oturtulması kesinlikle istenmeyen çift
              studentPenalty += 10000.0;
            }
          }
        }

        // B) Sıra / Bölge Tercihleri
        if (constraint.isFrontRowRequired || constraint.rowZonePreference == RowZonePreference.frontRow) {
          if (target.row > 1) {
            studentPenalty += 300.0 * (target.row - 1);
          }
        } else if (constraint.rowZonePreference == RowZonePreference.middleRow) {
          if (target.row == 0 || target.row > 3) {
            studentPenalty += 150.0;
          }
        } else if (constraint.rowZonePreference == RowZonePreference.backRow) {
          if (target.row < 2) {
            studentPenalty += 300.0 * (2 - target.row);
          }
        }
      }

      // 4. Özel gereksinimli öğrenci ön sıra cezası
      if (options.prioritizeSpecialNeedsInFront && student.isSpecialNeed) {
        if (target.row > 0) {
          studentPenalty += 40.0 * target.row;
        }
      }

      perStudent[student.id] = studentPenalty;
      totalPenalty += studentPenalty;
    }

    return _PenaltyEvaluation(total: totalPenalty, perStudent: perStudent);
  }
}

class _SeatTarget {
  final int cellIndex;
  final int slotIndex;
  final int row;
  final int col;
  final int slotNo;
  final int deskCapacity;

  _SeatTarget({
    required this.cellIndex,
    required this.slotIndex,
    required this.row,
    required this.col,
    required this.slotNo,
    required this.deskCapacity,
  });
}

class _PenaltyEvaluation {
  final double total;
  final Map<String, double> perStudent;

  _PenaltyEvaluation({required this.total, required this.perStudent});
}
