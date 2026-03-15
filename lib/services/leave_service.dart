import 'package:cloud_firestore/cloud_firestore.dart';

class LeaveService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'leave_requests';

  // İzin Talebi Oluştur
  Future<void> requestLeave({
    required String institutionId,
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
    required String type, // Yıllık, Mazeret, Rapor vb.
    int lessonConflicts = 0,
    int dutyConflicts = 0,
    bool isFullDay = true, // Yeni: Tam gün mü?
    String? startTime, // Yeni: "09:00"
    String? endTime, // Yeni: "11:00"
    String? reason,
  }) async {
    await _firestore.collection(_collection).add({
      'institutionId': institutionId,
      'userId': userId,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'type': type,
      'reason': reason,
      'status': 'pending',
      'lessonConflicts': lessonConflicts,
      'dutyConflicts': dutyConflicts,
      'isFullDay': isFullDay,
      'startTime': startTime,
      'endTime': endTime,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // İzin Taleplerini Getir (Filtreli)
  Future<List<Map<String, dynamic>>> getLeaveRequests({
    required String institutionId,
    String? userId,
    String? status,
  }) async {
    Query query = _firestore
        .collection(_collection)
        .where('institutionId', isEqualTo: institutionId);

    if (userId != null) {
      query = query.where('userId', isEqualTo: userId);
    }
    if (status != null) {
      query = query.where('status', isEqualTo: status);
    }

    query = query.orderBy('createdAt', descending: true);

    final snapshot = await query.get();
    return snapshot.docs.map((e) {
      final data = e.data() as Map<String, dynamic>;
      data['id'] = e.id;
      return data;
    }).toList();
  }

  // İzin Durumunu Güncelle (Onay/Red)
  Future<void> updateLeaveStatus(
    String docId,
    String status, {
    String? rejectionReason,
  }) async {
    final updates = <String, dynamic>{
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (rejectionReason != null) {
      updates['rejectionReason'] = rejectionReason;
    }

    await _firestore.collection(_collection).doc(docId).update(updates);
  }

  // İzin Talebini Sil
  Future<void> deleteLeave(String docId) async {
    await _firestore.collection(_collection).doc(docId).delete();
  }

  Future<void> updateLeaveConflicts(
    String docId, {
    required int lessons,
    required int duties,
  }) async {
    await _firestore.collection(_collection).doc(docId).update({
      'lessonConflicts': lessons,
      'dutyConflicts': duties,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Create Temporary Assignment (Substitution)
  Future<void> assignTemporaryTeacher({
    required String institutionId,
    required String originalTeacherId,
    required String originalTeacherName,
    required String substituteTeacherId,
    required String substituteTeacherName,
    required DateTime date,
    required int hourIndex,
    required String courseName,
    required String className,
    required String schoolTypeId,
    required String periodId,
    required String classId,
    required String lessonId,
    String? leaveId,
  }) async {
    await _firestore.collection('temporaryTeacherAssignments').add({
      'institutionId': institutionId,
      'leaveId': leaveId,
      'schoolTypeId': schoolTypeId,
      'periodId': periodId,
      'originalTeacherId': originalTeacherId,
      'originalTeacherName': originalTeacherName,
      'substituteTeacherId': substituteTeacherId,
      'substituteTeacherName': substituteTeacherName,
      'date': Timestamp.fromDate(date),
      'hourIndex': hourIndex,
      'classId': classId,
      'lessonId': lessonId,
      'lessonName': courseName,
      'className': className,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'published',
      'reason': 'İzinli Personel Yerine Atama',
    });
  }

  // Internal Notification
  Future<void> sendInternalNotification({
    required String userId,
    required String title,
    required String body,
    String? type,
  }) async {
    await _firestore.collection('notifications').add({
      'userId': userId,
      'title': title,
      'body': body,
      'type': type ?? 'leave_update',
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
