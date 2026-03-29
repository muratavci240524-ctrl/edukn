import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/agm_cycle_model.dart';
import '../models/agm_group_model.dart';
import '../models/agm_assignment_model.dart';
import '../models/agm_time_slot_model.dart';
import '../models/agm_assignment_log_model.dart';

/// AGM Firestore CRUD Repository
/// Tüm koleksiyonlar root-level (institutions/{id}/... yerine flat yapı)
/// mevcut projenin mimarisine uygun olarak tasarlandı.
class AgmRepository {
  final _db = FirebaseFirestore.instance;

  CollectionReference get _timeSlots => _db.collection('agm_time_slots');

  CollectionReference get _logs => _db.collection('agm_assignment_logs');

  // ─── CYCLE ────────────────────────────────────────────────────────────────

  Future<String> createCycle(AgmCycle cycle) async {
    print('DEBUG: AgmRepository.createCycle started');
    final ref = _db.collection('agm_cycles').doc();
    final data = cycle.toMap();
    data['id'] = ref.id;
    await ref.set(data).timeout(const Duration(seconds: 30), onTimeout: () {
      throw Exception('CreateCycle Firestore timeout');
    });
    print('DEBUG: AgmRepository.createCycle finished');
    return ref.id;
  }

  Future<void> updateCycle(AgmCycle cycle) async {
    print('DEBUG: AgmRepository.updateCycle started for ${cycle.id}');
    await _db.collection('agm_cycles').doc(cycle.id).update(cycle.toMap()).timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        throw Exception('UpdateCycle Firestore timeout');
      },
    );
    print('DEBUG: AgmRepository.updateCycle finished');
  }

  Future<void> updateCycleStatus(String cycleId, AgmCycleStatus status) async {
    print('DEBUG: AgmRepository.updateCycleStatus to ${status.name}');
    await _db
        .collection('agm_cycles')
        .doc(cycleId)
        .update({'status': status.name})
        .timeout(const Duration(seconds: 30), onTimeout: () {
          throw Exception('updateCycleStatus Firestore timeout');
        });
  }

  Future<List<AgmGroup>> getGroupsByCycle(String cycleId) async {
    final query = await _db
        .collection('agm_groups')
        .where('cycleId', isEqualTo: cycleId)
        .get();
    return query.docs.map((d) => AgmGroup.fromMap(d.data(), d.id)).toList();
  }

  Future<void> updateCycleStudentLists(
    String cycleId, {
    List<String>? unassignedRemove,
    List<String>? absentRemove,
    List<String>? underAssignedAdd,
    List<String>? underAssignedRemove,
  }) async {
    final Map<String, dynamic> updates = {};
    if (unassignedRemove != null && unassignedRemove.isNotEmpty) {
      updates['unassignedStudentIds'] = FieldValue.arrayRemove(
        unassignedRemove,
      );
    }
    if (absentRemove != null && absentRemove.isNotEmpty) {
      updates['absentStudentIds'] = FieldValue.arrayRemove(absentRemove);
    }
    if (underAssignedAdd != null && underAssignedAdd.isNotEmpty) {
      updates['underAssignedStudentIds'] = FieldValue.arrayUnion(
        underAssignedAdd,
      );
    }
    if (underAssignedRemove != null && underAssignedRemove.isNotEmpty) {
      updates['underAssignedStudentIds'] = FieldValue.arrayRemove(
        underAssignedRemove,
      );
    }

    if (updates.isNotEmpty) {
      await _db.collection('agm_cycles').doc(cycleId).update(updates);
    }
  }

  Future<void> deleteCycle(String cycleId) async {
    // Batch delete: groups + assignments + logs
    final batch = _db.batch();

    final groups = await _db
        .collection('agm_groups')
        .where('cycleId', isEqualTo: cycleId)
        .get();
    for (final doc in groups.docs) {
      batch.delete(doc.reference);
    }

    final assignments = await _db
        .collection('agm_assignments')
        .where('cycleId', isEqualTo: cycleId)
        .get();
    for (final doc in assignments.docs) {
      batch.delete(doc.reference);
    }

    batch.delete(_db.collection('agm_cycles').doc(cycleId));
    await batch.commit();
  }

  Future<void> deleteGroupsByCycle(String cycleId) async {
    print('DEBUG: Starting deleteGroupsByCycle for $cycleId');
    final Stopwatch sw = Stopwatch()..start();
    
    // 1) Grup ve Atamaları PARALEL Bul
    final results = await Future.wait([
      _db.collection('agm_groups').where('cycleId', isEqualTo: cycleId).get(),
      _db.collection('agm_assignments').where('cycleId', isEqualTo: cycleId).get(),
    ]).timeout(const Duration(seconds: 30), onTimeout: () {
      throw Exception('deleteGroupsByCycle.get Firestore timeout');
    });
    
    final groups = results[0];
    final assignments = results[1];
    print('DEBUG: Fetched ${groups.docs.length} groups and ${assignments.docs.length} assignments in ${sw.elapsedMilliseconds}ms');

    final List<DocumentReference> refsToDelete = [];
    for (final d in groups.docs) refsToDelete.add(d.reference);
    for (final d in assignments.docs) refsToDelete.add(d.reference);

    if (refsToDelete.isEmpty) {
      print('DEBUG: Nothing to delete.');
      return;
    }

    // 2) 400'erli gruplar halinde sil
    int batchCount = 0;
    for (var i = 0; i < refsToDelete.length; i += 400) {
      final batch = _db.batch();
      final chunk = refsToDelete.sublist(
        i,
        i + 400 > refsToDelete.length ? refsToDelete.length : i + 400,
      );
      for (final ref in chunk) {
        batch.delete(ref);
      }
      await batch.commit().timeout(const Duration(seconds: 30), onTimeout: () {
        throw Exception('deleteGroupsByCycle.commit Batch $batchCount timeout');
      });
      batchCount++;
      print('DEBUG: Batch $batchCount committed at ${sw.elapsedMilliseconds}ms');
    }
    print('DEBUG: deleteGroupsByCycle completed in ${sw.elapsedMilliseconds}ms');
  }

  Future<void> batchWriteGroups(List<AgmGroup> groups) async {
    if (groups.isEmpty) return;
    print('DEBUG: Starting batchWriteGroups for ${groups.length} groups');
    final Stopwatch sw = Stopwatch()..start();
    
    int batchCount = 0;
    for (var i = 0; i < groups.length; i += 400) {
      final batch = _db.batch();
      final chunk = groups.sublist(
        i,
        i + 400 > groups.length ? groups.length : i + 400,
      );
      for (final group in chunk) {
        final ref = _db.collection('agm_groups').doc();
        final data = group.toMap();
        data['id'] = ref.id;
        batch.set(ref, data);
      }
      await batch.commit().timeout(const Duration(seconds: 30), onTimeout: () {
        throw Exception('batchWriteGroups.commit Batch $batchCount timeout');
      });
      batchCount++;
      print('DEBUG: Groups Batch $batchCount committed at ${sw.elapsedMilliseconds}ms');
    }
    print('DEBUG: batchWriteGroups completed in ${sw.elapsedMilliseconds}ms');
  }

  Future<void> batchUpdateGroups(List<AgmGroup> groups) async {
    if (groups.isEmpty) return;
    print('DEBUG: Starting batchUpdateGroups for ${groups.length} groups');
    final Stopwatch sw = Stopwatch()..start();
    
    int batchCount = 0;
    for (var i = 0; i < groups.length; i += 400) {
      final batch = _db.batch();
      final chunk = groups.sublist(
        i,
        i + 400 > groups.length ? groups.length : i + 400,
      );
      for (final group in chunk) {
        final ref = _db.collection('agm_groups').doc(group.id);
        batch.update(ref, group.toMap());
      }
      await batch.commit().timeout(const Duration(seconds: 30), onTimeout: () {
        throw Exception('batchUpdateGroups.commit Batch $batchCount timeout');
      });
      batchCount++;
      print('DEBUG: Update Batch $batchCount committed at ${sw.elapsedMilliseconds}ms');
    }
  }

  Future<void> batchDeleteByRefs(List<DocumentReference> refs) async {
    if (refs.isEmpty) return;
    print('DEBUG: Starting batchDeleteByRefs for ${refs.length} items');
    final Stopwatch sw = Stopwatch()..start();
    
    int batchCount = 0;
    for (var i = 0; i < refs.length; i += 400) {
      final batch = _db.batch();
      final chunk = refs.sublist(
        i,
        i + 400 > refs.length ? refs.length : i + 400,
      );
      for (final ref in chunk) {
        batch.delete(ref);
      }
      await batch.commit().timeout(const Duration(seconds: 30), onTimeout: () {
        throw Exception('batchDeleteByRefs.commit Batch $batchCount timeout');
      });
      batchCount++;
      print('DEBUG: Delete Batch $batchCount committed at ${sw.elapsedMilliseconds}ms');
    }
  }

  Future<void> saveCycleOptimized({
    required AgmCycle cycle,
    required List<AgmGroup> proposedGroups,
  }) async {
    print('DEBUG: saveCycleOptimized started for ${cycle.id}');
    final sw = Stopwatch()..start();

    // 1) Mevcut grupları çek
    final existingGroups = await getGroupsByCycle(cycle.id);
    print('DEBUG: Found ${existingGroups.length} existing groups in ${sw.elapsedMilliseconds}ms');

    // 2) Diff (Cerrahi Müdahale)
    final existingMap = {for (var g in existingGroups) '${g.saatDilimiId}_${g.ogretmenId}_${g.dersId}': g};
    final proposedMap = {for (var g in proposedGroups) '${g.saatDilimiId}_${g.ogretmenId}_${g.dersId}': g};

    final toCreate = proposedGroups.where((g) {
      final key = '${g.saatDilimiId}_${g.ogretmenId}_${g.dersId}';
      return !existingMap.containsKey(key);
    }).toList();

    final toUpdate = proposedGroups.where((g) {
      final key = '${g.saatDilimiId}_${g.ogretmenId}_${g.dersId}';
      if (!existingMap.containsKey(key)) return false;
      final existing = existingMap[key]!;
      // Önemli metadata değişikliği var mı?
      return existing.derslikId != g.derslikId || 
             existing.kapasite != g.kapasite ||
             existing.dersAdi != g.dersAdi ||
             existing.ogretmenAdi != g.ogretmenAdi;
    }).map((g) {
      final key = '${g.saatDilimiId}_${g.ogretmenId}_${g.dersId}';
      final existing = existingMap[key]!;
      return g.copyWith(id: existing.id); // Mevcut ID'yi koru
    }).toList();

    final toDeleteIds = existingGroups.where((g) {
      final key = '${g.saatDilimiId}_${g.ogretmenId}_${g.dersId}';
      return !proposedMap.containsKey(key);
    }).map((g) => g.id).toList();

    print('DEBUG: Diff Results -> Create: ${toCreate.length}, Update: ${toUpdate.length}, Delete: ${toDeleteIds.length}');

    // 3) İşlemleri Batch ile Yap
    if (toDeleteIds.isNotEmpty) {
      final refs = toDeleteIds.map((id) => _db.collection('agm_groups').doc(id)).toList();
      await batchDeleteByRefs(refs);
    }

    if (toCreate.isNotEmpty) {
      await batchWriteGroups(toCreate);
    }

    if (toUpdate.isNotEmpty) {
      // batchUpdateGroups zaten mevcut
      await batchUpdateGroups(toUpdate);
    }

    // 4) Cycle meta verisini güncelle
    await updateCycle(cycle);

    print('DEBUG: saveCycleOptimized finished in ${sw.elapsedMilliseconds}ms');
  }

  Stream<List<AgmCycle>> watchCycles(
    String institutionId,
    String schoolTypeId,
  ) {
    return _db
        .collection('agm_cycles')
        .where('institutionId', isEqualTo: institutionId)
        .where('schoolTypeId', isEqualTo: schoolTypeId)
        .orderBy('olusturulmaZamani', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => AgmCycle.fromMap(d.data(), d.id)).toList(),
        );
  }

  // ─── TIME SLOTS ───────────────────────────────────────────────────────────

  Future<String> createTimeSlot(AgmTimeSlot slot) async {
    final ref = _timeSlots.doc();
    final data = slot.toMap();
    await ref.set(data);
    return ref.id;
  }

  Future<void> updateTimeSlot(AgmTimeSlot slot) async {
    await _timeSlots.doc(slot.id).update(slot.toMap());
  }

  /// Sadece ogretmenGirisler listesini günceller
  Future<void> updateTimeSlotTeachers(
    String slotId,
    List<AgmSlotTeacherEntry> girisler,
  ) async {
    await _timeSlots.doc(slotId).update({
      'ogretmenGirisler': girisler.map((e) => e.toMap()).toList(),
    });
  }

  Future<void> deleteTimeSlot(String slotId) async {
    await _timeSlots.doc(slotId).update({'isActive': false});
  }

  Future<List<AgmTimeSlot>> getTimeSlots(
    String institutionId, {
    bool includeInactive = false,
  }) async {
    Query query = _timeSlots.where('institutionId', isEqualTo: institutionId);
    if (!includeInactive) {
      query = query.where('isActive', isEqualTo: true);
    }
    final snap = await query.get();
    return snap.docs
        .map((d) => AgmTimeSlot.fromMap(d.data() as Map<String, dynamic>, d.id))
        .toList();
  }

  // ─── GROUPS ───────────────────────────────────────────────────────────────

  Future<String> createGroup(AgmGroup group) async {
    final ref = _db.collection('agm_groups').doc();
    final data = group.toMap();
    data['id'] = ref.id;
    await ref.set(data);
    return ref.id;
  }

  Future<void> updateGroupStudentCount(String groupId, int delta) async {
    await _db.collection('agm_groups').doc(groupId).update({
      'mevcutOgrenciSayisi': FieldValue.increment(delta),
    });
  }

  Stream<List<AgmGroup>> watchGroupsByCycle(String cycleId) {
    return _db
        .collection('agm_groups')
        .where('cycleId', isEqualTo: cycleId)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => AgmGroup.fromMap(d.data(), d.id)).toList(),
        );
  }

  // ─── ASSIGNMENTS ──────────────────────────────────────────────────────────

  /// Toplu atama – transaction ile güvenli yazma (500/batch limit)
  Future<void> batchWriteAssignments(List<AgmAssignment> assignments) async {
    final chunks = <List<AgmAssignment>>[];
    for (var i = 0; i < assignments.length; i += 400) {
      chunks.add(
        assignments.sublist(
          i,
          i + 400 > assignments.length ? assignments.length : i + 400,
        ),
      );
    }

    for (final chunk in chunks) {
      final batch = _db.batch();
      for (final assignment in chunk) {
        final ref = _db.collection('agm_assignments').doc();
        final data = assignment.toMap();
        data['id'] = ref.id;
        batch.set(ref, data);
      }
      await batch.commit();
    }
  }

  Future<void> deleteAssignment(String assignmentId) async {
    await _db.collection('agm_assignments').doc(assignmentId).delete();
  }

  Future<void> moveAssignment(
    String assignmentId,
    String newGroupId,
    String newGroupAdi,
  ) async {
    await _db.collection('agm_assignments').doc(assignmentId).update({
      'groupId': newGroupId,
      'atamaTipi': AgmAssignmentType.manual.name,
    });
  }

  Future<List<AgmAssignment>> getAssignmentsByGroup(String groupId) async {
    final snap = await _db
        .collection('agm_assignments')
        .where('groupId', isEqualTo: groupId)
        .get();
    return snap.docs.map((d) => AgmAssignment.fromMap(d.data(), d.id)).toList();
  }

  Future<List<AgmAssignment>> getAssignmentsByStudent(
    String cycleId,
    String ogrenciId,
  ) async {
    final snap = await _db
        .collection('agm_assignments')
        .where('cycleId', isEqualTo: cycleId)
        .where('ogrenciId', isEqualTo: ogrenciId)
        .get();
    return snap.docs.map((d) => AgmAssignment.fromMap(d.data(), d.id)).toList();
  }

  Future<List<AgmAssignment>> getAssignmentsByCycle(String cycleId) async {
    final snap = await _db
        .collection('agm_assignments')
        .where('cycleId', isEqualTo: cycleId)
        .get();
    return snap.docs.map((d) => AgmAssignment.fromMap(d.data(), d.id)).toList();
  }

  /// Rollback: cycle'daki tüm atamaları sil ve istatistikleri sıfırla
  Future<void> rollbackAssignments(String cycleId) async {
    // 1) Atamaları sil
    final snap = await _db
        .collection('agm_assignments')
        .where('cycleId', isEqualTo: cycleId)
        .get();

    final chunks = <List<QueryDocumentSnapshot>>[];
    for (var i = 0; i < snap.docs.length; i += 400) {
      chunks.add(
        snap.docs.sublist(
          i,
          i + 400 > snap.docs.length ? snap.docs.length : i + 400,
        ),
      );
    }
    for (final chunk in chunks) {
      final batch = _db.batch();
      for (final doc in chunk) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    // 2) Cycle dokümanındaki listeleri temizle
    await _db.collection('agm_cycles').doc(cycleId).update({
      'unassignedStudentIds': [],
      'absentStudentIds': [],
      'underAssignedStudentIds': [],
    });

    // 3) Grupları sıfırla (mevcutOgrenciSayisi = 0, kazanimlar = [])
    final groupsSnap = await _db
        .collection('agm_groups')
        .where('cycleId', isEqualTo: cycleId)
        .get();

    if (groupsSnap.docs.isNotEmpty) {
      final batch = _db.batch();
      for (final doc in groupsSnap.docs) {
        batch.update(doc.reference, {
          'mevcutOgrenciSayisi': 0,
          'kazanimlar': [],
        });
      }
      await batch.commit();
    }
  }

  // ─── LOGS ─────────────────────────────────────────────────────────────────

  Future<void> addLog(AgmAssignmentLog log) async {
    final ref = _logs.doc();
    final data = log.toMap();
    data['id'] = ref.id;
    await ref.set(data);
  }

  Future<List<AgmAssignmentLog>> getLogsByCycle(String cycleId) async {
    final snap = await _logs
        .where('cycleId', isEqualTo: cycleId)
        .orderBy('tarih', descending: true)
        .get();
    return snap.docs
        .map(
          (d) =>
              AgmAssignmentLog.fromMap(d.data() as Map<String, dynamic>, d.id),
        )
        .toList();
  }
}
