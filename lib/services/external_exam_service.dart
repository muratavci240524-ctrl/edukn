import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/assessment/external_exam_model.dart';
import '../models/assessment/external_exam_registration_model.dart';

class ExternalExamService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const _examsCollection = 'external_exams';
  static const _registrationsCollection = 'external_exam_registrations';

  // ─────────────── EXAM CRUD ────────────────────────────────────────────────

  Future<String> createExternalExam(ExternalExam exam) async {
    try {
      final docRef = await _firestore
          .collection(_examsCollection)
          .add(exam.toMap());
      debugPrint('✅ ExternalExam oluşturuldu: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('ExternalExam oluşturma hatası: $e');
      rethrow;
    }
  }

  Future<void> updateExternalExam(ExternalExam exam) async {
    if (exam.id == null) return;
    try {
      await _firestore
          .collection(_examsCollection)
          .doc(exam.id)
          .update(exam.toMap());
      debugPrint('✅ ExternalExam güncellendi: ${exam.id}');
    } catch (e) {
      debugPrint('ExternalExam güncelleme hatası: $e');
      rethrow;
    }
  }

  Future<void> deleteExternalExam(String examId) async {
    try {
      await _firestore.collection(_examsCollection).doc(examId).delete();
      debugPrint('🗑️ ExternalExam silindi: $examId');
    } catch (e) {
      debugPrint('ExternalExam silme hatası: $e');
      rethrow;
    }
  }

  Stream<List<ExternalExam>> getExternalExams(String institutionId) {
    return _firestore
        .collection(_examsCollection)
        .where('institutionId', isEqualTo: institutionId)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => ExternalExam.fromMap(doc.data(), doc.id))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  Future<ExternalExam?> getExternalExamById(String examId) async {
    try {
      final doc = await _firestore
          .collection(_examsCollection)
          .doc(examId)
          .get();
      if (!doc.exists) return null;
      return ExternalExam.fromMap(doc.data()!, doc.id);
    } catch (e) {
      debugPrint('ExternalExam getirme hatası: $e');
      return null;
    }
  }

  // ─────────────── REGISTRATIONS ───────────────────────────────────────────

  Stream<List<ExternalExamRegistration>> getRegistrations(String examId) {
    return _firestore
        .collection(_registrationsCollection)
        .where('examId', isEqualTo: examId)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) =>
                  ExternalExamRegistration.fromMap(doc.data(), doc.id))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  Future<List<ExternalExamRegistration>> getRegistrationsByGrade(
    String examId,
    String gradeLevel,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(_registrationsCollection)
          .where('examId', isEqualTo: examId)
          .where('gradeLevel', isEqualTo: gradeLevel)
          .get();
      return snapshot.docs
          .map((doc) => ExternalExamRegistration.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      debugPrint('Grade bazlı başvuru getirme hatası: $e');
      return [];
    }
  }

  Future<List<ExternalExamRegistration>> getRegistrationsBySession(
    String examId,
    String sessionId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(_registrationsCollection)
          .where('examId', isEqualTo: examId)
          .where('sessionId', isEqualTo: sessionId)
          .where('status', isNotEqualTo: 'cancelled')
          .get();
      return snapshot.docs
          .map((doc) => ExternalExamRegistration.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      debugPrint('Seans bazlı başvuru getirme hatası: $e');
      return [];
    }
  }

  Future<String> addRegistration(ExternalExamRegistration reg) async {
    try {
      final docRef = await _firestore
          .collection(_registrationsCollection)
          .add(reg.toMap());
      debugPrint('✅ Başvuru eklendi: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('Başvuru ekleme hatası: $e');
      rethrow;
    }
  }

  Future<void> updateRegistrationStatus(
    String regId,
    RegistrationStatus status,
  ) async {
    try {
      final statusStr = status == RegistrationStatus.confirmed
          ? 'confirmed'
          : status == RegistrationStatus.cancelled
              ? 'cancelled'
              : 'pending';
      await _firestore
          .collection(_registrationsCollection)
          .doc(regId)
          .update({'status': statusStr});
    } catch (e) {
      debugPrint('Başvuru durum güncelleme hatası: $e');
      rethrow;
    }
  }

  Future<void> markAsScanned(String regId, bool scanned) async {
    try {
      await _firestore
          .collection(_registrationsCollection)
          .doc(regId)
          .update({'isScanned': scanned});
      debugPrint('✅ Başvuru QR ile okutuldu: $regId ($scanned)');
    } catch (e) {
      debugPrint('QR okutma işaretleme hatası: $e');
      rethrow;
    }
  }

  /// Aynı TC ile aynı sınava başvuru var mı kontrolü
  Future<bool> checkDuplicateRegistration(
    String examId,
    String tcNo,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(_registrationsCollection)
          .where('examId', isEqualTo: examId)
          .where('studentTcNo', isEqualTo: tcNo)
          .get();
          
      // Check if any of the registrations are active (not cancelled)
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['status'] != 'cancelled') {
          return true; // Found an active duplicate
        }
      }
      return false;
    } catch (e) {
      debugPrint('Duplicate kontrol hatası: $e');
      return false;
    }
  }

  /// TC no ve sınav id'sine göre başvuruyu çeker
  Future<ExternalExamRegistration?> getRegistrationByTc(
    String examId,
    String tcNo,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(_registrationsCollection)
          .where('examId', isEqualTo: examId)
          .where('studentTcNo', isEqualTo: tcNo.trim())
          .get();
      
      if (snapshot.docs.isEmpty) return null;
      
      // Filter out cancelled registrations in Dart to avoid missing composite index errors
      final validDocs = snapshot.docs.where((doc) => doc.data()['status'] != 'cancelled').toList();
      
      if (validDocs.isEmpty) return null;
      
      final doc = validDocs.first;
      return ExternalExamRegistration.fromMap(doc.data(), doc.id);
    } catch (e) {
      debugPrint('TC bazlı başvuru bulma hatası: $e');
      return null;
    }
  }

  /// Başvuruyu günceller
  Future<void> updateRegistration(
    String regId,
    ExternalExamRegistration reg,
  ) async {
    try {
      await _firestore
          .collection(_registrationsCollection)
          .doc(regId)
          .update(reg.toMap());
      debugPrint('✅ Başvuru güncellendi: $regId');
    } catch (e) {
      debugPrint('Başvuru güncelleme hatası: $e');
      rethrow;
    }
  }

  /// Başvuruyu siler
  Future<void> deleteRegistration(String regId) async {
    try {
      await _firestore.collection(_registrationsCollection).doc(regId).delete();
      debugPrint('🗑️ Başvuru silindi: $regId');
    } catch (e) {
      debugPrint('Başvuru silme hatası: $e');
      rethrow;
    }
  }

  /// Seans + sınıf için mevcut başvuru sayısı (kota kontrolü için)
  Future<int> getSessionRegistrationCount(
    String examId,
    String sessionId,
    String gradeLevel,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(_registrationsCollection)
          .where('examId', isEqualTo: examId)
          .where('sessionId', isEqualTo: sessionId)
          .where('gradeLevel', isEqualTo: gradeLevel)
          .where('status', isNotEqualTo: 'cancelled')
          .get();
      return snapshot.docs.length;
    } catch (e) {
      debugPrint('Kota kontrol hatası: $e');
      return 0;
    }
  }

  // ─────────────── SEAT ASSIGNMENT (KELEBEK ALGORİTMASI) ───────────────────

  /// Seans için oturma düzeni oluşturur (butterfly veya random)
  Future<void> assignSeats(
    String examId,
    String sessionId,
    SeatingMode mode,
    List<GradeClassroomAssignment> assignments,
  ) async {
    try {
      // 1. Seansa ait onaylı başvuruları al
      final registrations = await getRegistrationsBySession(examId, sessionId);
      if (registrations.isEmpty) return;

      List<ExternalExamRegistration> ordered;

      if (mode == SeatingMode.butterfly) {
        ordered = _applyButterflyAlgorithm(registrations);
      } else {
        // Simple random
        final shuffled = List<ExternalExamRegistration>.from(registrations);
        shuffled.shuffle(Random());
        ordered = shuffled;
      }

      // 2. Salonları düz listeye dönüştür
      final allRooms = assignments
          .expand((a) => a.rooms)
          .toList();

      if (allRooms.isEmpty) return;

      // 3. Her öğrenciye salon + sıra no ata
      int roomIndex = 0;
      int seatInRoom = 0;
      int globalIndex = 1;

      final batch = _firestore.batch();

      for (final reg in ordered) {
        if (reg.id == null) continue;

        // Mevcut oda dolduysa sonrakine geç
        while (roomIndex < allRooms.length &&
            seatInRoom >= allRooms[roomIndex].effectiveCapacity) {
          roomIndex++;
          seatInRoom = 0;
        }

        if (roomIndex >= allRooms.length) break;

        final room = allRooms[roomIndex];
        seatInRoom++;
        final entryCode = _generateEntryCode(globalIndex);

        final docRef = _firestore
            .collection(_registrationsCollection)
            .doc(reg.id);

        batch.update(docRef, {
          'assignedRoomId': room.classroomId,
          'assignedRoomName': room.classroomName,
          'assignedRoomCode': room.classroomCode,
          'seatNumber': seatInRoom,
          'examEntryCode': entryCode,
        });

        globalIndex++;
      }

      await batch.commit();
      debugPrint('✅ Oturma planı oluşturuldu: ${ordered.length} öğrenci');
    } catch (e) {
      debugPrint('Oturma planı hatası: $e');
      rethrow;
    }
  }

  /// Kelebek algoritması: aynı okuldan öğrenciler yan yana oturmasın
  List<ExternalExamRegistration> _applyButterflyAlgorithm(
    List<ExternalExamRegistration> registrations,
  ) {
    // Okul bazlı grupla
    final Map<String, List<ExternalExamRegistration>> schoolGroups = {};
    for (final reg in registrations) {
      final school = reg.currentSchool.trim();
      schoolGroups.putIfAbsent(school, () => []).add(reg);
    }

    // Her grubu isime göre sırala
    for (final group in schoolGroups.values) {
      group.sort((a, b) => a.studentSurname.compareTo(b.studentSurname));
    }

    // Round-robin dağıt
    final groups = schoolGroups.values.toList();
    final result = <ExternalExamRegistration>[];
    int maxLen = groups.fold(0, (max, g) => g.length > max ? g.length : max);

    for (int i = 0; i < maxLen; i++) {
      for (final group in groups) {
        if (i < group.length) {
          result.add(group[i]);
        }
      }
    }

    return result;
  }

  String _generateEntryCode(int index) {
    final year = DateTime.now().year;
    return 'EKS-$year-${index.toString().padLeft(5, '0')}';
  }

  // ─────────────── SCHOLARSHIP ─────────────────────────────────────────────

  /// Öğrencinin sıralamasına göre burs kademesini döner (null = burs yok)
  ScholarshipTier? getScholarshipTier(
    ExternalExam exam,
    String gradeLevel,
    int rank,
  ) {
    if (!exam.scholarshipEnabled) return null;
    final tiers = exam.scholarshipConfig[gradeLevel];
    if (tiers == null || tiers.isEmpty) return null;

    for (final tier in tiers) {
      if (rank >= tier.minRank && rank <= tier.maxRank) {
        return tier;
      }
    }
    return null;
  }
  // ─────────────── SCHOOL AUTOCOMPLETE ──────────────────────────────────────

  Future<List<String>> getExternalSchools() async {
    try {
      final doc = await _firestore.collection('settings').doc('external_schools').get();
      if (doc.exists && doc.data() != null) {
        final List<dynamic> schoolsList = doc.data()!['schools'] ?? [];
        return schoolsList.map((e) => e.toString()).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Okul listesi getirme hatası: $e');
      return [];
    }
  }

  Future<void> addExternalSchool(String schoolName) async {
    if (schoolName.trim().isEmpty) return;
    try {
      final String upperName = schoolName.trim().toUpperCase();
      final docRef = _firestore.collection('settings').doc('external_schools');
      await docRef.set({
        'schools': FieldValue.arrayUnion([upperName])
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Yeni okul ekleme hatası: $e');
    }
  }
}
