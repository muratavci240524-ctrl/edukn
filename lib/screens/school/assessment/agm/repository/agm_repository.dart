import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/agm_cycle_model.dart';
import '../models/agm_group_model.dart';
import '../models/agm_assignment_model.dart';
import '../models/agm_time_slot_model.dart';
import '../models/agm_assignment_log_model.dart';

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

  Future<AgmCycle?> getCycle(String cycleId) async {
    final doc = await _db.collection('agm_cycles').doc(cycleId).get();
    if (!doc.exists) return null;
    return AgmCycle.fromMap(doc.data()!, doc.id);
  }

  Future<void> updateCycleStatus(String cycleId, AgmCycleStatus status) async {
    await _db.collection('agm_cycles').doc(cycleId).update({'status': status.name});
  }

  Future<List<AgmGroup>> getGroupsByCycle(String cycleId) async {
    final query = await _db.collection('agm_groups').where('cycleId', isEqualTo: cycleId).get();
    return query.docs.map((d) => AgmGroup.fromMap(d.data(), d.id)).toList();
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
    final docRef = _db.collection('agm_cycles').doc(cycleId);

    // 1. Önce remove işlemlerini yap
    final Map<String, dynamic> removeUpdates = {};
    if (unassignedRemove != null && unassignedRemove.isNotEmpty) {
      removeUpdates['unassignedStudentIds'] = FieldValue.arrayRemove(unassignedRemove);
    }
    if (absentRemove != null && absentRemove.isNotEmpty) {
      removeUpdates['absentStudentIds'] = FieldValue.arrayRemove(absentRemove);
    }
    if (underAssignedRemove != null && underAssignedRemove.isNotEmpty) {
      removeUpdates['underAssignedStudentIds'] = FieldValue.arrayRemove(underAssignedRemove);
    }
    if (removeUpdates.isNotEmpty) {
      await docRef.update(removeUpdates);
    }

    // 2. Sonra add işlemlerini yap
    final Map<String, dynamic> addUpdates = {};
    if (unassignedAdd != null && unassignedAdd.isNotEmpty) {
      addUpdates['unassignedStudentIds'] = FieldValue.arrayUnion(unassignedAdd);
    }
    if (absentAdd != null && absentAdd.isNotEmpty) {
      addUpdates['absentStudentIds'] = FieldValue.arrayUnion(absentAdd);
    }
    if (underAssignedAdd != null && underAssignedAdd.isNotEmpty) {
      addUpdates['underAssignedStudentIds'] = FieldValue.arrayUnion(underAssignedAdd);
    }
    if (addUpdates.isNotEmpty) {
      await docRef.update(addUpdates);
    }
  }

  Future<void> deleteCycle(String cycleId) async {
    final batch = _db.batch();
    final groups = await _db.collection('agm_groups').where('cycleId', isEqualTo: cycleId).get();
    for (final doc in groups.docs) batch.delete(doc.reference);
    final assignments = await _db.collection('agm_assignments').where('cycleId', isEqualTo: cycleId).get();
    for (final doc in assignments.docs) batch.delete(doc.reference);
    batch.delete(_db.collection('agm_cycles').doc(cycleId));
    await batch.commit();
  }

  Future<void> batchWriteGroups(List<AgmGroup> groups) async {
    if (groups.isEmpty) return;
    for (var i = 0; i < groups.length; i += 400) {
      final batch = _db.batch();
      final chunk = groups.sublist(i, i + 400 > groups.length ? groups.length : i + 400);
      for (final group in chunk) {
        final ref = _db.collection('agm_groups').doc();
        final data = group.toMap();
        data['id'] = ref.id;
        batch.set(ref, data);
      }
      await batch.commit();
    }
  }

  Future<void> batchUpdateGroups(List<AgmGroup> groups) async {
    if (groups.isEmpty) return;
    for (var i = 0; i < groups.length; i += 400) {
      final batch = _db.batch();
      final chunk = groups.sublist(i, i + 400 > groups.length ? groups.length : i + 400);
      for (final group in chunk) {
        batch.update(_db.collection('agm_groups').doc(group.id), group.toMap());
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

  Stream<List<AgmCycle>> watchCycles(
    String institutionId,
    String schoolTypeId, {
    String? workPeriodId,
    bool isPastPeriod = false,
  }) {
    return _db
        .collection('agm_cycles')
        .where('institutionId', isEqualTo: institutionId)
        .where('schoolTypeId', isEqualTo: schoolTypeId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) => AgmCycle.fromMap(d.data(), d.id)).toList();
      
      // workPeriodId filtresi: Kesin dönem izolasyonu
      final filteredList = (workPeriodId != null && workPeriodId.isNotEmpty)
          ? list.where((c) {
              if (c.workPeriodId == workPeriodId) return true;
              // Geçmiş dönemdeyse SADECE o döneme ait olanları göster, başka dönemleri ASLA gösterme
              if (isPastPeriod) return false;
              // Aktif dönemde ise sadece workPeriodId boş/tanımsız olan eski kayıtlar fallback olarak görülebilir
              return (c.workPeriodId == null || c.workPeriodId!.isEmpty);
            }).toList()
          : list;

      filteredList.sort((a, b) => b.olusturulmaZamani.compareTo(a.olusturulmaZamani));
      return filteredList;
    });
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

  Future<void> updateTimeSlotTeachers(String slotId, List<AgmSlotTeacherEntry> entries) async {
    await _timeSlots.doc(slotId).update({
      'ogretmenGirisler': entries.map((e) => e.toMap()).toList(),
    });
  }

  Future<void> deleteTimeSlot(String slotId) async {
    await _timeSlots.doc(slotId).update({'isActive': false});
  }

  Future<List<AgmTimeSlot>> getTimeSlots(String institutionId, {bool includeInactive = false}) async {
    Query query = _timeSlots.where('institutionId', isEqualTo: institutionId);
    if (!includeInactive) query = query.where('isActive', isEqualTo: true);
    final snap = await query.get();
    return snap.docs.map((d) => AgmTimeSlot.fromMap(d.data() as Map<String, dynamic>, d.id)).toList();
  }

  // ─── GROUPS ───────────────────────────────────────────────────────────────

  Stream<List<AgmGroup>> watchGroupsByCycle(String cycleId) {
    return _db
        .collection('agm_groups')
        .where('cycleId', isEqualTo: cycleId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => AgmGroup.fromMap(d.data(), d.id)).toList());
  }

  // ─── ASSIGNMENTS ──────────────────────────────────────────────────────────

  Future<void> batchWriteAssignments(List<AgmAssignment> assignments) async {
    for (var i = 0; i < assignments.length; i += 400) {
      final batch = _db.batch();
      final chunk = assignments.sublist(i, i + 400 > assignments.length ? assignments.length : i + 400);
      for (final assignment in chunk) {
        final ref = _db.collection('agm_assignments').doc();
        final data = assignment.toMap();
        data['id'] = ref.id;
        batch.set(ref, data);
      }
      await batch.commit();
    }
  }

  Future<void> rollbackAssignments(String cycleId) async {
    final snap = await _db.collection('agm_assignments').where('cycleId', isEqualTo: cycleId).get();
    for (var i = 0; i < snap.docs.length; i += 400) {
      final batch = _db.batch();
      final chunk = snap.docs.sublist(i, i + 400 > snap.docs.length ? snap.docs.length : i + 400);
      for (final doc in chunk) batch.delete(doc.reference);
      await batch.commit();
    }
    await _db.collection('agm_cycles').doc(cycleId).update({
      'unassignedStudentIds': [],
      'absentStudentIds': [],
      'underAssignedStudentIds': [],
    });
    final groupsSnap = await _db.collection('agm_groups').where('cycleId', isEqualTo: cycleId).get();
    if (groupsSnap.docs.isNotEmpty) {
      final batch = _db.batch();
      for (final doc in groupsSnap.docs) {
        batch.update(doc.reference, {'mevcutOgrenciSayisi': 0, 'kazanimlar': []});
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
    final snap = await _logs.where('cycleId', isEqualTo: cycleId).get();
    final list = snap.docs.map((d) => AgmAssignmentLog.fromMap(d.data() as Map<String, dynamic>, d.id)).toList();
    list.sort((a, b) => b.tarih.compareTo(a.tarih));
    return list;
  }

  // ─── MIGRATION: KAMP -> AGM ───────────────────────────────────────────────
  /// Daha önce Kamp Programı ile açılmış döngüleri ve bağlı kayıtları
  /// AGM koleksiyonlarına aktarır (Hiçbir veri kaybı yaşanmaması için).
  Future<void> migrateCampCyclesIfNeeded(String institutionId, String schoolTypeId) async {
    try {
      final campCyclesSnap = await _db
          .collection('camp_cycles')
          .where('institutionId', isEqualTo: institutionId)
          .where('schoolTypeId', isEqualTo: schoolTypeId)
          .get();

      if (campCyclesSnap.docs.isEmpty) return;

      for (final cDoc in campCyclesSnap.docs) {
        final cData = cDoc.data();
        final cycleId = cDoc.id;

        // agm_cycles'ta bu kayıt zaten var mı kontrol et
        final agmDoc = await _db.collection('agm_cycles').doc(cycleId).get();
        if (!agmDoc.exists) {
          // 1. Döngüyü agm_cycles'a aktar
          await _db.collection('agm_cycles').doc(cycleId).set(cData);

          // 2. camp_groups -> agm_groups aktar
          final groupsSnap = await _db
              .collection('camp_groups')
              .where('cycleId', isEqualTo: cycleId)
              .get();
          if (groupsSnap.docs.isNotEmpty) {
            final gBatch = _db.batch();
            for (final gDoc in groupsSnap.docs) {
              gBatch.set(_db.collection('agm_groups').doc(gDoc.id), gDoc.data());
            }
            await gBatch.commit();
          }

          // 3. camp_assignments -> agm_assignments aktar
          final assignSnap = await _db
              .collection('camp_assignments')
              .where('cycleId', isEqualTo: cycleId)
              .get();
          if (assignSnap.docs.isNotEmpty) {
            for (var i = 0; i < assignSnap.docs.length; i += 400) {
              final aBatch = _db.batch();
              final chunk = assignSnap.docs.sublist(
                i,
                i + 400 > assignSnap.docs.length ? assignSnap.docs.length : i + 400,
              );
              for (final aDoc in chunk) {
                aBatch.set(_db.collection('agm_assignments').doc(aDoc.id), aDoc.data());
              }
              await aBatch.commit();
            }
          }

          // 4. camp_assignment_logs -> agm_assignment_logs aktar
          final logsSnap = await _db
              .collection('camp_assignment_logs')
              .where('cycleId', isEqualTo: cycleId)
              .get();
          if (logsSnap.docs.isNotEmpty) {
            final lBatch = _db.batch();
            for (final lDoc in logsSnap.docs) {
              lBatch.set(_db.collection('agm_assignment_logs').doc(lDoc.id), lDoc.data());
            }
            await lBatch.commit();
          }
        }
      }
    } catch (e) {
      debugPrint('Camp -> AGM migration error: $e');
    }
  }
}
