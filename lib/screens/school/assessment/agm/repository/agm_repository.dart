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
    final ref = _db.collection('agm_cycles').doc();
    final data = cycle.toMap();
    data['id'] = ref.id;
    await ref.set(data);
    return ref.id;
  }

  Future<void> updateCycle(AgmCycle cycle) async {
    await _db.collection('agm_cycles').doc(cycle.id).update(cycle.toMap());
  }

  Future<void> updateCycleStatus(String cycleId, AgmCycleStatus status) async {
    await _db.collection('agm_cycles').doc(cycleId).update({
      'status': status.name,
    });
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
    final batch = _db.batch();
    final groups = await _db
        .collection('agm_groups')
        .where('cycleId', isEqualTo: cycleId)
        .get();
    for (final doc in groups.docs) {
      batch.delete(doc.reference);
    }
    // Atamaları da siliyoruz çünkü gruplar değişiyor
    final assignments = await _db
        .collection('agm_assignments')
        .where('cycleId', isEqualTo: cycleId)
        .get();
    for (final doc in assignments.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
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

  Future<void> updateGroup(AgmGroup group) async {
    await _db.collection('agm_groups').doc(group.id).update(group.toMap());
  }

  Future<List<AgmGroup>> getGroupsByCycle(String cycleId) async {
    final snap = await _db
        .collection('agm_groups')
        .where('cycleId', isEqualTo: cycleId)
        .get();
    return snap.docs.map((d) => AgmGroup.fromMap(d.data(), d.id)).toList();
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
