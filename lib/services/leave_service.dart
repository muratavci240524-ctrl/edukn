import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class LeaveService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ==================== LEAVE REQUESTS ====================

  Future<String> requestLeave({
    String? staffId,
    required String institutionId,
    String? leaveType,
    required DateTime startDate,
    required DateTime endDate,
    String? note,
    required String role,
    int lessonConflicts = 0,
    int dutyConflicts = 0,
    bool isFullDay = true,
    String? startTime,
    String? endTime,
    // Legacy support
    String? userId,
    String? type,
    String? reason,
  }) async {
    final finalStaffId = staffId ?? userId ?? '';
    final finalType = leaveType ?? type ?? 'Yıllık İzin';
    final finalNote = note ?? reason ?? '';
    
    final totalDays = endDate.difference(startDate).inDays + 1;
    
    final docRef = await _firestore.collection('leave_requests').add({
      'staffId': finalStaffId,
      'userId': finalStaffId,
      'institutionId': institutionId,
      'leaveType': finalType,
      'type': finalType,
      'startDate': DateFormat('yyyy-MM-dd').format(startDate),
      'endDate': DateFormat('yyyy-MM-dd').format(endDate),
      'totalDays': totalDays,
      'status': 'pending',
      'note': finalNote,
      'reason': finalNote,
      'managerNote': '',
      'createdAt': FieldValue.serverTimestamp(),
      'createdByRole': role,
      'lessonConflicts': lessonConflicts,
      'dutyConflicts': dutyConflicts,
      'isFullDay': isFullDay,
      'startTime': startTime,
      'endTime': endTime,
    });
    
    return docRef.id;
  }

  Future<void> deleteLeave(String id) async {
    await _firestore.collection('leave_requests').doc(id).delete();
  }

  Future<void> assignTemporaryTeacher({required String leaveId, required String temporaryTeacherId}) async {
    await _firestore.collection('leave_requests').doc(leaveId).update({
      'temporaryTeacherId': temporaryTeacherId,
      'status': 'lessons_assigned',
    });
  }

  Future<void> sendInternalNotification({required String userId, required String title, required String body}) async {
    // Stub for now
    print('🔔 Notification to $userId: $title - $body');
  }

  Future<List<Map<String, dynamic>>> getLeaveRequests({
    required String institutionId,
    String? staffId,
    String? status,
  }) async {
    Query query = _firestore.collection('leave_requests').where('institutionId', isEqualTo: institutionId);
    
    if (staffId != null) {
      query = query.where('staffId', isEqualTo: staffId);
    }
    
    if (status != null) {
      query = query.where('status', isEqualTo: status);
    }
    
    final snapshot = await query.get();
    
    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  Future<void> updateLeaveStatus({
    required String leaveId,
    required String status,
    required String managerNote,
  }) async {
    await _firestore.collection('leave_requests').doc(leaveId).update({
      'status': status,
      'managerNote': managerNote,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ==================== BALANCE CALCULATIONS ====================

  Future<Map<String, dynamic>> getLeaveBalance(String staffId, String institutionId) async {
    // 1. Get User Data (Join Date & Role)
    final userDoc = await _firestore.collection('users').doc(staffId).get();
    if (!userDoc.exists) return {'total': 0, 'used': 0, 'remaining': 0};
    
    final userData = userDoc.data()!;
    final role = (userData['role'] ?? 'staff').toString().toLowerCase();
    
    // Teacher Exception: 0 Annual Leave
    if (role.contains('teacher') || role.contains('ogretmen') || role.contains('öğretmen')) {
      return {'total': 0, 'used': 0, 'remaining': 0, 'isTeacher': true};
    }

    // 2. Calculate Total Entitlement based on tenure
    final joinDateTs = userData['hireDate'] ?? userData['joinDate'] ?? userData['createdAt'];
    DateTime joinDate;
    if (joinDateTs is Timestamp) {
      joinDate = joinDateTs.toDate();
    } else if (joinDateTs is String) {
      joinDate = DateTime.parse(joinDateTs);
    } else {
      joinDate = DateTime.now(); // Fallback
    }

    final now = DateTime.now();
    final tenureYears = now.year - joinDate.year - (now.month < joinDate.month || (now.month == joinDate.month && now.day < joinDate.day) ? 1 : 0);
    
    int totalEntitlement = 14;
    if (tenureYears >= 10) {
      totalEntitlement = 26;
    } else if (tenureYears >= 5) {
      totalEntitlement = 21;
    }

    // 3. Get Used Days (Approved Annual Leaves)
    final approvedLeaves = await _firestore
        .collection('leave_requests')
        .where('staffId', isEqualTo: staffId)
        .where('leaveType', isEqualTo: 'Yıllık İzin')
        .where('status', isEqualTo: 'approved')
        .get();
    
    int usedDays = 0;
    for (var doc in approvedLeaves.docs) {
      usedDays += (doc.data()['totalDays'] as num).toInt();
    }

    return {
      'total': totalEntitlement,
      'used': usedDays,
      'remaining': totalEntitlement - usedDays,
      'tenureYears': tenureYears,
      'isTeacher': false,
    };
  }

  // ==================== CALENDAR & INTEGRATION ====================

  Future<List<Map<String, dynamic>>> getDailyLeaves(String institutionId, String date) async {
    final snapshot = await _firestore
        .collection('leave_requests')
        .where('institutionId', isEqualTo: institutionId)
        .where('status', isEqualTo: 'approved')
        .where('startDate', isLessThanOrEqualTo: date)
        .get();
    
    // Filter locally because Firestore doesn't support multiple inequalities easily without extra indexing
    return snapshot.docs
        .map((doc) => {...doc.data(), 'id': doc.id})
        .where((data) => (data['endDate'] as String).compareTo(date) >= 0)
        .toList();
  }
}
