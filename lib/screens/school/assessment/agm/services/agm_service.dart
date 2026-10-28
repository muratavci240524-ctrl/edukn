import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/agm_cycle_model.dart';
import '../models/agm_group_model.dart';
import '../models/agm_assignment_model.dart';
import '../models/agm_assignment_log_model.dart';
import '../repository/agm_repository.dart';
import 'agm_assignment_engine.dart';
import '../../../../../services/term_service.dart';

class AgmService {
  final AgmRepository _repo = AgmRepository();
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  String get _currentUserId => _auth.currentUser?.uid ?? '';
  String get _currentUserName => _auth.currentUser?.displayName ?? 'Bilinmeyen Kullanıcı';

  Stream<List<AgmCycle>> watchCycles(
    String institutionId,
    String schoolTypeId, {
    String? workPeriodId,
    bool isPastPeriod = false,
  }) => 
      _repo.watchCycles(
        institutionId,
        schoolTypeId,
        workPeriodId: workPeriodId,
        isPastPeriod: isPastPeriod,
      );

  Future<String> createCycle({
    required String institutionId,
    required String schoolTypeId,
    String? workPeriodId,
    String? title,
    required String referansDenemeSinavId,
    required String referansDenemeSinavAdi,
    List<String> referansDenemeSinavIds = const [],
    List<String> referansDenemeSinavAdlari = const [],
    required DateTime baslangicTarihi,
    required DateTime bitisTarihi,
    int? haftalikMaksimumSaat,
    int? minimumDersSayisi,
    int? minimumGrupOgrenciSayisi,
    bool isSpecialClassActive = false,
    int? specialClassCapacity,
    String? specialClassRoomId,
    String? specialClassRoomName,
    String specialClassCriteria = 'success_rate',
  }) async {
    String? effectiveWorkPeriodId = workPeriodId;
    if (effectiveWorkPeriodId == null || effectiveWorkPeriodId.isEmpty) {
      effectiveWorkPeriodId = await TermService().getActiveTermId();
    }

    final cycle = AgmCycle(
      id: '',
      institutionId: institutionId,
      schoolTypeId: schoolTypeId,
      workPeriodId: effectiveWorkPeriodId,
      title: title,
      referansDenemeSinavId: referansDenemeSinavId,
      referansDenemeSinavAdi: referansDenemeSinavAdi,
      referansDenemeSinavIds: referansDenemeSinavIds,
      referansDenemeSinavAdlari: referansDenemeSinavAdlari,
      baslangicTarihi: baslangicTarihi,
      bitisTarihi: bitisTarihi,
      status: AgmCycleStatus.draft,
      olusturulmaZamani: DateTime.now(),
      olusturanKullaniciId: _currentUserId,
      haftalikMaksimumSaat: haftalikMaksimumSaat,
      minimumDersSayisi: minimumDersSayisi,
      minimumGrupOgrenciSayisi: minimumGrupOgrenciSayisi,
      isSpecialClassActive: isSpecialClassActive,
      specialClassCapacity: specialClassCapacity,
      specialClassRoomId: specialClassRoomId,
      specialClassRoomName: specialClassRoomName,
      specialClassCriteria: specialClassCriteria,
    );
    return await _repo.createCycle(cycle);
  }

  Future<void> saveCycle({
    required AgmCycle cycle,
    required List<AgmGroup> proposedGroups,
  }) async {
    List<AgmGroup> finalGroups = List.from(proposedGroups);

    if (cycle.isSpecialClassActive) {
      finalGroups.removeWhere((g) => g.isSpecial || g.dersAdi == 'Özel Sınıf' || g.dersId == 'OZEL');
      
      final Map<String, List<AgmGroup>> groupsBySlot = {};
      for (final g in proposedGroups) {
        final slotKey = '${g.gun}_${g.baslangicSaat}-${g.bitisSaat}';
        groupsBySlot.putIfAbsent(slotKey, () => []).add(g);
      }

      final List<AgmGroup> specialClasses = [];
      
      groupsBySlot.forEach((slotKey, slotGroups) {
        final existingInSpecialRoom = slotGroups.where((g) => g.derslikId == cycle.specialClassRoomId).firstOrNull;

        if (existingInSpecialRoom != null) {
          finalGroups.removeWhere((fg) => 
            fg.gun == existingInSpecialRoom.gun && 
            fg.baslangicSaat == existingInSpecialRoom.baslangicSaat && 
            fg.derslikId == existingInSpecialRoom.derslikId
          );
          
          specialClasses.add(existingInSpecialRoom.copyWith(
            dersId: 'OZEL',
            dersAdi: 'Özel Sınıf',
            isSpecial: true,
            kapasite: cycle.specialClassCapacity ?? 24,
          ));
        } else {
          final template = slotGroups.first;
          specialClasses.add(AgmGroup(
            id: '', 
            cycleId: cycle.id, 
            institutionId: cycle.institutionId, 
            dersId: 'OZEL', 
            dersAdi: 'Özel Sınıf', 
            saatDilimiId: template.saatDilimiId, 
            saatDilimiAdi: template.saatDilimiAdi, 
            gun: template.gun, 
            baslangicSaat: template.baslangicSaat, 
            bitisSaat: template.bitisSaat, 
            ogretmenId: '', 
            ogretmenAdi: 'Özel Öğretmen', 
            derslikId: cycle.specialClassRoomId, 
            derslikAdi: cycle.specialClassRoomName, 
            kapasite: cycle.specialClassCapacity ?? 24, 
            isSpecial: true
          ));
        }
      });
      finalGroups.addAll(specialClasses);
    }

    if (cycle.id.isEmpty) {
      final id = await _repo.createCycle(cycle);
      final groupsWithId = finalGroups.map((g) => g.copyWith(cycleId: id)).toList();
      await _repo.batchWriteGroups(groupsWithId);
    } else {
      await _repo.updateCycle(cycle);
      final existing = await _repo.getGroupsByCycle(cycle.id);
      if (existing.isNotEmpty) {
        final refs = existing.map((g) => _db.collection('agm_groups').doc(g.id)).toList();
        await _repo.batchDeleteByRefs(refs);
      }
      final groupsWithId = finalGroups.map((g) => g.copyWith(cycleId: cycle.id)).toList();
      await _repo.batchWriteGroups(groupsWithId);
    }
  }

  Future<AgmDraftResult> generateDraft({
    required AgmCycle cycle,
    required List<StudentNeedProfile> ogrenciProfiller,
    required List<AgmGroup> gruplar,
    double esikBasariOrani = 0.6,
    bool sadeceDusukBasari = true,
    Map<String, double> dersBazliEsikler = const {},
    int minGroupSize = 5,
    Map<String, Map<String, int>>? gecmisKatilimlar,
    double penaltyMultiplier = 0.15,
    List<AgmAssignment>? mevcutAtamalar,
    Map<String, Map<String, int>> dersBazliSaatSinirlari = const {},
    bool dersBazliZorlaAtama = true,
  }) async {
    final engine = AgmAssignmentEngine(
      cycleId: cycle.id,
      institutionId: cycle.institutionId,
      haftalikMaksimumSaat: cycle.haftalikMaksimumSaat,
      minimumGrupOgrenciSayisi: minGroupSize,
    );
    engine.setMinimumDersSayisi(cycle.minimumDersSayisi);

    final draft = await engine.generateDraft(
      ogrenciProfiller: ogrenciProfiller,
      gruplar: gruplar,
      esikBasariOrani: esikBasariOrani,
      sadeceDusukBasari: sadeceDusukBasari,
      specialClassCriteria: cycle.specialClassCriteria,
      dersBazliEsikler: dersBazliEsikler,
      gecmisKatilimlar: gecmisKatilimlar,
      penaltyMultiplier: penaltyMultiplier,
      mevcutAtamalar: mevcutAtamalar,
      highSuccessSoruCozumActive: cycle.highSuccessSoruCozumActive,
      highSuccessSoruCozumThreshold: cycle.highSuccessSoruCozumThreshold,
      dersBazliSaatSinirlari: dersBazliSaatSinirlari,
      dersBazliZorlaAtama: dersBazliZorlaAtama,
    );

    await _repo.rollbackAssignments(cycle.id);
    await _repo.batchWriteAssignments(draft.atamalar);
    await _repo.batchUpdateGroups(draft.gruplar);
    await _db.collection('agm_cycles').doc(cycle.id).update({
      'unassignedStudentIds': draft.yerlesmeyenOgrenciIds,
      'underAssignedStudentIds': draft.eksikAtananOgrenciIds,
      'unassignedReasons': draft.yerlesmemeNedenleri,
    });
    return draft;
  }

  // ─── MANUEL İŞLEMLER ──────────────────────────────────────────────────────

  Future<void> manualAssign({
    required String cycleId,
    required String ogrenciId,
    required String ogrenciAdi,
    required String subeId,
    required String subeAdi,
    required String yeniGrupId,
    required String yeniGrupAdi,
    double basariOrani = 0.5,
    bool isAbsent = false,
  }) async {
    final cycle = await _repo.getCycle(cycleId);
    final institutionId = cycle?.institutionId ?? '';

    final batch = _db.batch();
    final atamaId = '${cycleId}_${ogrenciId}_${yeniGrupId}';
    final atamaRef = _db.collection('agm_assignments').doc(atamaId);

    batch.set(atamaRef, {
      'id': atamaId,
      'cycleId': cycleId,
      'institutionId': institutionId,
      'ogrenciId': ogrenciId,
      'ogrenciAdi': ogrenciAdi,
      'subeId': subeId,
      'sube': subeAdi,
      'groupId': yeniGrupId,
      'groupName': yeniGrupAdi,
      'basariOrani': basariOrani,
      'atamaTipi': 'manual',
      'atamaZamani': FieldValue.serverTimestamp(),
    });

    final logRef = _db.collection('agm_assignment_logs').doc();
    final log = AgmAssignmentLog(
      id: logRef.id,
      cycleId: cycleId,
      institutionId: institutionId,
      ogrenciId: ogrenciId,
      ogrenciAdi: ogrenciAdi,
      yeniGrupId: yeniGrupId,
      yeniGrupAdi: yeniGrupAdi,
      yapanKullaniciId: _currentUserId,
      yapanKullaniciAdi: _currentUserName,
      tarih: DateTime.now(),
    );
    batch.set(logRef, log.toMap());

    final grupRef = _db.collection('agm_groups').doc(yeniGrupId);
    batch.update(grupRef, {'mevcutOgrenciSayisi': FieldValue.increment(1)});

    final cycleRef = _db.collection('agm_cycles').doc(cycleId);
    batch.update(cycleRef, {
      'unassignedStudentIds': FieldValue.arrayRemove([ogrenciId]),
      'underAssignedStudentIds': FieldValue.arrayRemove([ogrenciId]),
      if (isAbsent) 'absentStudentIds': FieldValue.arrayRemove([ogrenciId]),
    });

    await batch.commit();
  }

  Future<void> removeAssignments(List<AgmAssignment> assignments) async {
    if (assignments.isEmpty) return;

    final cycle = await _repo.getCycle(assignments.first.cycleId);
    final institutionId = cycle?.institutionId ?? '';

    final batch = _db.batch();
    for (final a in assignments) {
      batch.delete(_db.collection('agm_assignments').doc(a.id));
      batch.update(_db.collection('agm_groups').doc(a.groupId), {'mevcutOgrenciSayisi': FieldValue.increment(-1)});
      
      final logRef = _db.collection('agm_assignment_logs').doc();
      final log = AgmAssignmentLog(
        id: logRef.id,
        cycleId: a.cycleId,
        institutionId: institutionId,
        ogrenciId: a.ogrenciId,
        ogrenciAdi: a.ogrenciAdi,
        eskiGrupId: a.groupId,
        eskiGrupAdi: a.groupName,
        yapanKullaniciId: _currentUserId,
        yapanKullaniciAdi: _currentUserName,
        tarih: DateTime.now(),
      );
      batch.set(logRef, log.toMap());

      final cycleRef = _db.collection('agm_cycles').doc(a.cycleId);
      batch.update(cycleRef, {
        'unassignedStudentIds': FieldValue.arrayUnion([a.ogrenciId]),
      });
    }
    await batch.commit();
  }

  Future<void> moveAssignments(List<AgmAssignment> assignments, String targetGroupId, String targetGroupName) async {
    if (assignments.isEmpty) return;

    final cycle = await _repo.getCycle(assignments.first.cycleId);
    final institutionId = cycle?.institutionId ?? '';

    final batch = _db.batch();
    for (final a in assignments) {
      batch.update(_db.collection('agm_assignments').doc(a.id), {
        'groupId': targetGroupId,
        'groupName': targetGroupName,
        'atamaTipi': 'manual',
      });
      batch.update(_db.collection('agm_groups').doc(a.groupId), {'mevcutOgrenciSayisi': FieldValue.increment(-1)});
      batch.update(_db.collection('agm_groups').doc(targetGroupId), {'mevcutOgrenciSayisi': FieldValue.increment(1)});

      final logRef = _db.collection('agm_assignment_logs').doc();
      final log = AgmAssignmentLog(
        id: logRef.id,
        cycleId: a.cycleId,
        institutionId: institutionId,
        ogrenciId: a.ogrenciId,
        ogrenciAdi: a.ogrenciAdi,
        eskiGrupId: a.groupId,
        eskiGrupAdi: a.groupName,
        yeniGrupId: targetGroupId,
        yeniGrupAdi: targetGroupName,
        yapanKullaniciId: _currentUserId,
        yapanKullaniciAdi: _currentUserName,
        tarih: DateTime.now(),
      );
      batch.set(logRef, log.toMap());
    }
    await batch.commit();
  }

  Future<void> swapGroups(AgmGroup groupA, AgmGroup groupB, List<AgmAssignment> assignsA, List<AgmAssignment> assignsB) async {
    final batch = _db.batch();
    for (final a in assignsA) {
      batch.update(_db.collection('agm_assignments').doc(a.id), {
        'groupId': groupB.id,
        'groupName': '${groupB.dersAdi} - ${groupB.ogretmenAdi}',
      });
      final logRef = _db.collection('agm_assignment_logs').doc();
      batch.set(logRef, AgmAssignmentLog(
        id: logRef.id, cycleId: groupA.cycleId, institutionId: groupA.institutionId,
        ogrenciId: a.ogrenciId, ogrenciAdi: a.ogrenciAdi,
        eskiGrupId: groupA.id, eskiGrupAdi: '${groupA.dersAdi} - ${groupA.ogretmenAdi}',
        yeniGrupId: groupB.id, yeniGrupAdi: '${groupB.dersAdi} - ${groupB.ogretmenAdi}',
        yapanKullaniciId: _currentUserId, yapanKullaniciAdi: _currentUserName, tarih: DateTime.now()
      ).toMap());
    }
    for (final a in assignsB) {
      batch.update(_db.collection('agm_assignments').doc(a.id), {
        'groupId': groupA.id,
        'groupName': '${groupA.dersAdi} - ${groupA.ogretmenAdi}',
      });
      final logRef = _db.collection('agm_assignment_logs').doc();
      batch.set(logRef, AgmAssignmentLog(
        id: logRef.id, cycleId: groupB.cycleId, institutionId: groupB.institutionId,
        ogrenciId: a.ogrenciId, ogrenciAdi: a.ogrenciAdi,
        eskiGrupId: groupB.id, eskiGrupAdi: '${groupB.dersAdi} - ${groupB.ogretmenAdi}',
        yeniGrupId: groupA.id, yeniGrupAdi: '${groupA.dersAdi} - ${groupA.ogretmenAdi}',
        yapanKullaniciId: _currentUserId, yapanKullaniciAdi: _currentUserName, tarih: DateTime.now()
      ).toMap());
    }
    batch.update(_db.collection('agm_groups').doc(groupA.id), {'mevcutOgrenciSayisi': assignsB.length});
    batch.update(_db.collection('agm_groups').doc(groupB.id), {'mevcutOgrenciSayisi': assignsA.length});
    await batch.commit();
  }

  Future<List<AgmAssignmentLog>> getLogs(String cycleId) async {
    final snap = await _db.collection('agm_assignment_logs')
        .where('cycleId', isEqualTo: cycleId)
        .orderBy('tarih', descending: true)
        .get();
    return snap.docs.map((d) => AgmAssignmentLog.fromMap(d.data(), d.id)).toList();
  }

  // ─── YAYINLAMA VE DİĞERLERİ ──────────────────────────────────────────────

  Future<void> publishCycle({
    required AgmCycle cycle,
    required List<AgmGroup> gruplar,
    required List<AgmAssignment> atamalar,
  }) async {
    final batch = _db.batch();
    batch.update(_db.collection('agm_cycles').doc(cycle.id), {'status': AgmCycleStatus.published.name});

    final cycleStartOfWeek = cycle.baslangicTarihi.subtract(Duration(days: cycle.baslangicTarihi.weekday - 1));
    final cycleStartTs = Timestamp.fromDate(DateTime(cycleStartOfWeek.year, cycleStartOfWeek.month, cycleStartOfWeek.day));
    final cycleEndOfWeek = cycle.bitisTarihi;
    final cycleEndTs = Timestamp.fromDate(DateTime(cycleEndOfWeek.year, cycleEndOfWeek.month, cycleEndOfWeek.day, 23, 59, 59));

    final Map<String, List<AgmAssignment>> assignmentsByGroup = {};
    for (final atama in atamalar) assignmentsByGroup.putIfAbsent(atama.groupId, () => []).add(atama);

    for (final entry in assignmentsByGroup.entries) {
      final groupId = entry.key;
      final groupAssignments = entry.value;
      final grup = gruplar.firstWhere((g) => g.id == groupId, orElse: () => gruplar.first);
      final etutRef = _db.collection('etut_requests').doc();
      final dayIndex = _dayNameToIndex(grup.gun);

      DateTime exactDate = cycleStartOfWeek.add(Duration(days: dayIndex - 1));
      if (exactDate.isBefore(DateTime(cycle.baslangicTarihi.year, cycle.baslangicTarihi.month, cycle.baslangicTarihi.day))) {
        exactDate = exactDate.add(const Duration(days: 7));
      }
      if (exactDate.isAfter(cycle.bitisTarihi.add(const Duration(days: 1)))) {
        continue;
      }

      final startParts = grup.baslangicSaat.split(':');
      final endParts = grup.bitisSaat.split(':');
      DateTime? startTime, endTime;
      if (startParts.length == 2 && endParts.length == 2) {
        startTime = DateTime(exactDate.year, exactDate.month, exactDate.day, int.parse(startParts[0]), int.parse(startParts[1]));
        endTime = DateTime(exactDate.year, exactDate.month, exactDate.day, int.parse(endParts[0]), int.parse(endParts[1]));
      }

      batch.set(etutRef, {
        'id': etutRef.id,
        'institutionId': cycle.institutionId,
        'studentId': groupAssignments.first.ogrenciId,
        'studentIds': groupAssignments.map((a) => a.ogrenciId).toList(),
        'recipientNames': {for (final a in groupAssignments) a.ogrenciId: '${a.ogrenciAdi}${a.sube != null && a.sube!.isNotEmpty ? " (${a.sube})" : ""}'},
        'teacherId': grup.ogretmenId,
        'teacherName': grup.ogretmenAdi,
        'dersId': grup.dersId,
        'dersAdi': grup.dersAdi,
        'lessonName': grup.dersAdi,
        'gun': grup.gun,
        'baslangicSaat': grup.baslangicSaat,
        'bitisSaat': grup.bitisSaat,
        'agmCycleId': cycle.id,
        'agmGroupId': grup.id,
        'date': Timestamp.fromDate(exactDate),
        'startTime': startTime != null ? Timestamp.fromDate(startTime) : null,
        'endTime': endTime != null ? Timestamp.fromDate(endTime) : null,
        'className': 'AGM - ${grup.saatDilimiAdi}',
        'weekStart': cycleStartTs,
        'weekEnd': cycleEndTs,
        'status': 'active',
        'type': 'Etut',
        'isGroup': groupAssignments.length > 1,
        'groupStudentCount': groupAssignments.length,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': _currentUserId,
      });

      for (final atama in groupAssignments) {
        final notifRef = _db.collection('notificationRequests').doc();
        batch.set(notifRef, {
          'type': 'agm_assignment',
          'recipientId': atama.ogrenciId,
          'title': 'AGM Programı Yayınlandı',
          'body': '${grup.dersAdi} AGM etüdünüz ${grup.gun} ${grup.baslangicSaat}-${grup.bitisSaat} olarak oluşturuldu.',
          'institutionId': cycle.institutionId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }
    await batch.commit();
  }

  Future<void> unpublishCycle(String cycleId) async {
    final batch = _db.batch();
    final etutsQuery = await _db.collection('etut_requests').where('agmCycleId', isEqualTo: cycleId).get();
    for (final doc in etutsQuery.docs) batch.delete(doc.reference);
    batch.update(_db.collection('agm_cycles').doc(cycleId), {'status': AgmCycleStatus.locked.name});
    await batch.commit();
  }

  int _dayNameToIndex(String dayName) {
    final d = dayName.toLowerCase().replaceAll('ı', 'i').replaceAll('İ', 'i').trim();
    switch (d) {
      case 'pazartesi': return 1;
      case 'sali': return 2;
      case 'carsamba': return 3;
      case 'persembe': return 4;
      case 'cuma': return 5;
      case 'cumartesi': return 6;
      case 'pazar': return 7;
      default: return 1;
    }
  }
}
