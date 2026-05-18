import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/camp_cycle_model.dart';
import '../models/camp_group_model.dart';
import '../models/camp_assignment_model.dart';
import '../models/camp_time_slot_model.dart';
import '../models/camp_assignment_log_model.dart';

class CampRepository {
  final _db = FirebaseFirestore.instance;

  CollectionReference get _timeSlots => _db.collection('camp_time_slots');
  CollectionReference get _logs => _db.collection('camp_assignment_logs');

  // ─── CYCLE ────────────────────────────────────────────────────────────────

  Future<String> createCycle(CampCycle cycle) async {
    final ref = _db.collection('camp_cycles').doc();
    final data = cycle.toMap();
    data['id'] = ref.id;
    await ref.set(data);
    return ref.id;
  }

  Future<void> updateCycle(CampCycle cycle) async {
    await _db.collection('camp_cycles').doc(cycle.id).update(cycle.toMap());
  }

  Future<CampCycle?> getCycle(String cycleId) async {
    final doc = await _db.collection('camp_cycles').doc(cycleId).get();
    if (!doc.exists) return null;
    return CampCycle.fromMap(doc.data()!, doc.id);
  }

  Future<void> updateCycleStatus(String cycleId, CampCycleStatus status) async {
    await _db.collection('camp_cycles').doc(cycleId).update({'status': status.name});
  }

  Future<List<CampGroup>> getGroupsByCycle(String cycleId) async {
    final query = await _db.collection('camp_groups').where('cycleId', isEqualTo: cycleId).get();
    return query.docs.map((d) => CampGroup.fromMap(d.data(), d.id)).toList();
  }

  Future<void> updateCycleStudentLists(
    String cycleId, {
    List<String>? unassignedAdd,
    List<String>? unassignedRemove,
    List<String>? absentAdd,
    List<String>? absentRemove,
    List<String>? underAssignedAdd,
    List<String>? underAssignedRemove,
  }) async {
    final Map<String, dynamic> updates = {};
    if (unassignedAdd != null && unassignedAdd.isNotEmpty) {
      updates['unassignedStudentIds'] = FieldValue.arrayUnion(unassignedAdd);
    }
    if (unassignedRemove != null && unassignedRemove.isNotEmpty) {
      updates['unassignedStudentIds'] = FieldValue.arrayRemove(unassignedRemove);
    }
    if (absentAdd != null && absentAdd.isNotEmpty) {
      updates['absentStudentIds'] = FieldValue.arrayUnion(absentAdd);
    }
    if (absentRemove != null && absentRemove.isNotEmpty) {
      updates['absentStudentIds'] = FieldValue.arrayRemove(absentRemove);
    }
    if (underAssignedAdd != null && underAssignedAdd.isNotEmpty) {
      updates['underAssignedStudentIds'] = FieldValue.arrayUnion(underAssignedAdd);
    }
    if (underAssignedRemove != null && underAssignedRemove.isNotEmpty) {
      updates['underAssignedStudentIds'] = FieldValue.arrayRemove(underAssignedRemove);
    }

    if (updates.isNotEmpty) {
      await _db.collection('camp_cycles').doc(cycleId).update(updates);
    }
  }

  Future<void> deleteCycle(String cycleId) async {
    final batch = _db.batch();
    final groups = await _db.collection('camp_groups').where('cycleId', isEqualTo: cycleId).get();
    for (final doc in groups.docs) batch.delete(doc.reference);
    final assignments = await _db.collection('camp_assignments').where('cycleId', isEqualTo: cycleId).get();
    for (final doc in assignments.docs) batch.delete(doc.reference);
    batch.delete(_db.collection('camp_cycles').doc(cycleId));
    await batch.commit();
  }

  Future<void> batchWriteGroups(List<CampGroup> groups) async {
    if (groups.isEmpty) return;
    for (var i = 0; i < groups.length; i += 400) {
      final batch = _db.batch();
      final chunk = groups.sublist(i, i + 400 > groups.length ? groups.length : i + 400);
      for (final group in chunk) {
        final ref = _db.collection('camp_groups').doc();
        final data = group.toMap();
        data['id'] = ref.id;
        batch.set(ref, data);
      }
      await batch.commit();
    }
  }

  Future<void> batchUpdateGroups(List<CampGroup> groups) async {
    if (groups.isEmpty) return;
    for (var i = 0; i < groups.length; i += 400) {
      final batch = _db.batch();
      final chunk = groups.sublist(i, i + 400 > groups.length ? groups.length : i + 400);
      for (final group in chunk) {
        batch.update(_db.collection('camp_groups').doc(group.id), group.toMap());
      }
      await batch.commit();
    }
  }

  Future<void> batchDeleteByRefs(List<DocumentReference> refs) async {
    if (refs.isEmpty) return;
    for (var i = 0; i < refs.length; i += 400) {
      final batch = _db.batch();
      final chunk = refs.sublist(i, i + 400 > refs.length ? refs.length : i + 400);
      for (final ref in chunk) batch.delete(ref);
      await batch.commit();
    }
  }

  Stream<List<CampCycle>> watchCycles(String institutionId, String schoolTypeId) {
    return _db
        .collection('camp_cycles')
        .where('institutionId', isEqualTo: institutionId)
        .where('schoolTypeId', isEqualTo: schoolTypeId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) => CampCycle.fromMap(d.data(), d.id)).toList();
      list.sort((a, b) => b.olusturulmaZamani.compareTo(a.olusturulmaZamani));
      return list;
    });
  }

  // ─── TIME SLOTS ───────────────────────────────────────────────────────────

  Future<String> createTimeSlot(CampTimeSlot slot) async {
    final ref = _timeSlots.doc();
    final data = slot.toMap();
    await ref.set(data);
    return ref.id;
  }

  Future<void> updateTimeSlot(CampTimeSlot slot) async {
    await _timeSlots.doc(slot.id).update(slot.toMap());
  }

  Future<void> updateTimeSlotTeachers(String slotId, List<CampSlotTeacherEntry> entries) async {
    await _timeSlots.doc(slotId).update({
      'ogretmenGirisler': entries.map((e) => e.toMap()).toList(),
    });
  }

  Future<void> deleteTimeSlot(String slotId) async {
    await _timeSlots.doc(slotId).update({'isActive': false});
  }

  Future<List<CampTimeSlot>> getTimeSlots(String institutionId, {bool includeInactive = false}) async {
    Query query = _timeSlots.where('institutionId', isEqualTo: institutionId);
    if (!includeInactive) query = query.where('isActive', isEqualTo: true);
    final snap = await query.get();
    return snap.docs.map((d) => CampTimeSlot.fromMap(d.data() as Map<String, dynamic>, d.id)).toList();
  }

  // ─── GROUPS ───────────────────────────────────────────────────────────────

  Stream<List<CampGroup>> watchGroupsByCycle(String cycleId) {
    return _db
        .collection('camp_groups')
        .where('cycleId', isEqualTo: cycleId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => CampGroup.fromMap(d.data(), d.id)).toList());
  }

  // ─── ASSIGNMENTS ──────────────────────────────────────────────────────────

  Future<void> batchWriteAssignments(List<CampAssignment> assignments) async {
    for (var i = 0; i < assignments.length; i += 400) {
      final batch = _db.batch();
      final chunk = assignments.sublist(i, i + 400 > assignments.length ? assignments.length : i + 400);
      for (final assignment in chunk) {
        final ref = _db.collection('camp_assignments').doc();
        final data = assignment.toMap();
        data['id'] = ref.id;
        batch.set(ref, data);
      }
      await batch.commit();
    }
  }

  Future<void> rollbackAssignments(String cycleId) async {
    final snap = await _db.collection('camp_assignments').where('cycleId', isEqualTo: cycleId).get();
    for (var i = 0; i < snap.docs.length; i += 400) {
      final batch = _db.batch();
      final chunk = snap.docs.sublist(i, i + 400 > snap.docs.length ? snap.docs.length : i + 400);
      for (final doc in chunk) batch.delete(doc.reference);
      await batch.commit();
    }
    await _db.collection('camp_cycles').doc(cycleId).update({
      'unassignedStudentIds': [],
      'absentStudentIds': [],
      'underAssignedStudentIds': [],
    });
    final groupsSnap = await _db.collection('camp_groups').where('cycleId', isEqualTo: cycleId).get();
    if (groupsSnap.docs.isNotEmpty) {
      final batch = _db.batch();
      for (final doc in groupsSnap.docs) {
        batch.update(doc.reference, {'mevcutOgrenciSayisi': 0, 'kazanimlar': []});
      }
      await batch.commit();
    }
  }

  // ─── LOGS ─────────────────────────────────────────────────────────────────

  Future<void> addLog(CampAssignmentLog log) async {
    final ref = _logs.doc();
    final data = log.toMap();
    data['id'] = ref.id;
    await ref.set(data);
  }

  Future<List<CampAssignmentLog>> getLogsByCycle(String cycleId) async {
    final snap = await _logs.where('cycleId', isEqualTo: cycleId).get();
    final list = snap.docs.map((d) => CampAssignmentLog.fromMap(d.data() as Map<String, dynamic>, d.id)).toList();
    list.sort((a, b) => b.tarih.compareTo(a.tarih));
    return list;
  }
}
