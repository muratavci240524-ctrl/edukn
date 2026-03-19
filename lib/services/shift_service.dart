import 'package:cloud_firestore/cloud_firestore.dart';

class ShiftService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ==================== SHIFT TEMPLATES ====================

  Future<String> createShiftTemplate({
    required String name,
    required String startTime,
    required String endTime,
    required int breakDuration,
    required String institutionId,
    List<int>? workDays, // 1-5 for Mon-Fri
    int toleranceMinutes = 10,
  }) async {
    final workDuration = _calculateWorkDuration(startTime, endTime, breakDuration);
    
    final docRef = await _firestore.collection('shift_templates').add({
      'name': name,
      'startTime': startTime,
      'endTime': endTime,
      'breakDuration': breakDuration,
      'workDuration': workDuration,
      'workDays': workDays ?? [1, 2, 3, 4, 5],
      'toleranceMinutes': toleranceMinutes,
      'isActive': true,
      'institutionId': institutionId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    
    return docRef.id;
  }

  Future<void> updateShiftTemplate({
    required String templateId,
    required String name,
    required String startTime,
    required String endTime,
    required int breakDuration,
    int toleranceMinutes = 10,
  }) async {
    final workDuration = _calculateWorkDuration(startTime, endTime, breakDuration);
    await _firestore.collection('shift_templates').doc(templateId).update({
      'name': name,
      'startTime': startTime,
      'endTime': endTime,
      'breakDuration': breakDuration,
      'workDuration': workDuration,
      'toleranceMinutes': toleranceMinutes,
      'lastUpdate': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteTemplate(String templateId) async {
    await _firestore.collection('shift_templates').doc(templateId).delete();
  }

  // Vardiya şablonlarını getir
  Future<List<Map<String, dynamic>>> getShiftTemplates(String institutionId, {bool onlyActive = true}) async {
    Query query = _firestore.collection('shift_templates').where('institutionId', isEqualTo: institutionId);
    
    if (onlyActive) {
      query = query.where('isActive', isEqualTo: true);
    }
    
    final snapshot = await query.get();
    return snapshot.docs.map((e) {
      final data = e.data() as Map<String, dynamic>;
      data['id'] = e.id;
      return data;
    }).toList();
  }

  // ==================== STAFF ASSIGNMENTS ====================

  Future<void> assignTemplateToStaff({
    required String staffId,
    required String templateId,
    required String institutionId,
  }) async {
    await _firestore.collection('staff_shift_assignments').doc(staffId).set({
      'templateId': templateId,
      'institutionId': institutionId,
      'lastUpdate': FieldValue.serverTimestamp(),
    });
  }

  Future<void> assignBulkTemplates(List<String> staffIds, String templateId, String institutionId) async {
    final batch = _firestore.batch();
    for (var id in staffIds) {
      batch.set(_firestore.collection('staff_shift_assignments').doc(id), {
        'templateId': templateId,
        'institutionId': institutionId,
        'lastUpdate': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  // Helper to get all staff with their current assignments
  Future<List<Map<String, dynamic>>> getAllStaffWithAssignments(String institutionId) async {
    // Get all users who are not students or parents
    print('👨‍🏫 Fetching staff for institution: $institutionId');
    final usersSnapshot = await _firestore
        .collection('users')
        .where('institutionId', isEqualTo: institutionId)
        .where('role', whereIn: ['teacher', 'admin', 'manager', 'staff', 'ogretmen', 'öğretmen', 'mudur', 'müdür', 'personel'])
        .get();
    
    print('👥 Found ${usersSnapshot.docs.length} users with staff roles.');

    final assignmentsSnapshot = await _firestore
        .collection('staff_shift_assignments')
        .where('institutionId', isEqualTo: institutionId)
        .get();
    
    final Map<String, dynamic> assignments = {};
    for (var doc in assignmentsSnapshot.docs) {
      assignments[doc.id] = doc.data();
    }

    return usersSnapshot.docs.map((doc) {
      final data = doc.data();
      String rawRole = (data['role'] ?? 'staff').toString().toLowerCase();
      String localizedRole = 'Personel';
      if (rawRole.contains('teacher') || rawRole.contains('ogretmen') || rawRole.contains('öğretmen')) {
        localizedRole = 'Öğretmen';
      } else if (rawRole.contains('admin') || rawRole.contains('manager') || rawRole.contains('mudur') || rawRole.contains('müdür')) {
        localizedRole = 'Yönetici';
      }
      
      return {
        'id': doc.id,
        'name': data['fullName'] ?? data['name'] ?? data['displayName'] ?? 'İsimsiz Personel',
        'role': localizedRole,
        'department': data['departman'] ?? data['department'] ?? data['branch'] ?? data['brans'] ?? 'Genel',
        'assignment': assignments[doc.id],
      };
    }).toList();
  }

  // ==================== ATTENDANCE ====================

  Future<void> markAttendanceManual({
    required String staffId,
    required String institutionId,
    required String date,
    required String status, // 'geldi', 'geckaldi', 'gelmedi', 'izinli', 'erkencikti'
    String? checkIn,
    String? checkOut,
  }) async {
    final docId = '${staffId}_$date';
    await _firestore.collection('staff_attendance').doc(docId).set({
      'userId': staffId,
      'institutionId': institutionId,
      'date': date,
      'status': status,
      'checkInTime': checkIn,
      'checkOutTime': checkOut,
      'lastUpdate': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> markAllArrived(String institutionId, String date, List<String> staffIds) async {
    final batch = _firestore.batch();
    for (var id in staffIds) {
      batch.set(_firestore.collection('staff_attendance').doc('${id}_$date'), {
        'userId': id,
        'institutionId': institutionId,
        'date': date,
        'status': 'geldi',
        'lastUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  // ==================== OVERTIME ====================

  Future<String> addOvertime({
    required String staffId,
    required String institutionId,
    required String date,
    required int durationMinutes,
    required String description,
  }) async {
    final docRef = await _firestore.collection('staff_overtime').add({
      'userId': staffId,
      'institutionId': institutionId,
      'date': date,
      'durationMinutes': durationMinutes,
      'description': description,
      'status': 'bekliyor',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<void> approveOvertime(String id, bool approved) async {
    await _firestore.collection('staff_overtime').doc(id).update({
      'status': approved ? 'onaylandi' : 'reddedildi',
      'approvedAt': FieldValue.serverTimestamp(),
    });
  }

  // Gets monthly overtime for a staff
  Future<List<Map<String, dynamic>>> getStaffOvertime(String institutionId, String month) async {
    final snapshot = await _firestore
        .collection('staff_overtime')
        .where('institutionId', isEqualTo: institutionId)
        .where('date', isGreaterThanOrEqualTo: '$month-01')
        .where('date', isLessThanOrEqualTo: '$month-31')
        .get();
    
    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  // ==================== DASHBOARD SUMMARY ====================

  Future<Map<String, dynamic>> getDailySummary(String institutionId, String date) async {
    // 1. Get ALL staff members first (to show absent ones too)
    final staffList = await getAllStaffWithAssignments(institutionId);
    
    // 2. Fetch from Shift-specific attendance
    final snapshot = await _firestore
        .collection('staff_attendance')
        .where('institutionId', isEqualTo: institutionId)
        .where('date', isEqualTo: date)
        .get();

    // 3. Fetch from legacy 'attendance' collection (Puantaj source)
    final legacySnapshot = await _firestore
        .collection('attendance')
        .where('institutionId', isEqualTo: institutionId)
        .where('date', isEqualTo: date)
        .get();
    
    int present = 0, late = 0, absent = 0, leave = 0, earlyExit = 0;
    Map<String, Map<String, dynamic>> mergedLogs = {};

    // Initialize with all staff as "GELMEDI"
    for (var staff in staffList) {
      mergedLogs[staff['id']] = {
        'userId': staff['id'],
        'name': staff['name'], // Important for UI
        'status': 'gelmedi',
        'isAuto': true,
      };
    }

    // Process shift records
    for (var doc in snapshot.docs) {
      final data = doc.data();
      final uid = data['userId'];
      if (mergedLogs.containsKey(uid)) {
        final existingName = mergedLogs[uid]!['name'];
        mergedLogs[uid] = Map<String, dynamic>.from(data);
        mergedLogs[uid]!['name'] = existingName;
        mergedLogs[uid]!['isAuto'] = false;
      }
    }

    // Process legacy records (merge or overwrite if check-in is present)
    for (var doc in legacySnapshot.docs) {
      final data = doc.data();
      final uid = data['userId'];
      
      if (mergedLogs.containsKey(uid)) {
        if (mergedLogs[uid]?['isAuto'] == true || (mergedLogs[uid]?['status'] != 'geldi' && data['status'] == 'present')) {
          mergedLogs[uid]!.addAll({
            'status': data['status'] == 'present' ? 'geldi' : (data['status'] == 'absent' ? 'gelmedi' : 'geldi'),
            'checkInTime': _formatTimestamp(data['checkIn']),
            'checkOutTime': _formatTimestamp(data['checkOut']),
            'source': 'puantaj',
            'isAuto': false,
          });
        }
      }
    }

    final logs = mergedLogs.values.toList();
    for (var data in logs) {
      switch (data['status']) {
        case 'geldi': present++; break;
        case 'geckaldi': late++; break;
        case 'gelmedi': absent++; break;
        case 'izinli': leave++; break;
        case 'erkencikti': earlyExit++; break;
      }
    }

    return {
      'present': present,
      'late': late,
      'absent': absent,
      'leave': leave,
      'earlyExit': earlyExit,
      'logs': logs,
    };
  }

  String? _formatTimestamp(dynamic ts) {
    if (ts is Timestamp) {
      final d = ts.toDate();
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return null;
  }

  // ==================== CALENDAR DATA ====================

  Future<Map<int, String>> getUserMonthlyStatus(String userId, String institutionId, String yearMonth) async {
    final snapshot = await _firestore
        .collection('staff_attendance')
        .where('userId', isEqualTo: userId)
        .where('institutionId', isEqualTo: institutionId)
        .where('date', isGreaterThanOrEqualTo: '$yearMonth-01')
        .where('date', isLessThanOrEqualTo: '$yearMonth-31')
        .get();
    
    Map<int, String> statusMap = {};
    for (var doc in snapshot.docs) {
      final date = doc.data()['date'] as String;
      final day = int.parse(date.split('-')[2]);
      statusMap[day] = doc.data()['status'] ?? 'geldi';
    }
    return statusMap;
  }

  Future<Map<int, String>> getGeneralMonthlyStatus(String institutionId, String yearMonth, int totalStaff) async {
    final snapshot = await _firestore
        .collection('staff_attendance')
        .where('institutionId', isEqualTo: institutionId)
        .where('date', isGreaterThanOrEqualTo: '$yearMonth-01')
        .where('date', isLessThanOrEqualTo: '$yearMonth-31')
        .get();
    
    Map<int, Map<String, int>> dailyCounts = {};
    for (var doc in snapshot.docs) {
      final date = doc.data()['date'] as String;
      final parts = date.split('-');
      if (parts.length < 3) continue;
      final day = int.parse(parts[2]);
      final status = doc.data()['status'] ?? 'geldi';
      
      dailyCounts[day] ??= {};
      dailyCounts[day]![status] = (dailyCounts[day]![status] ?? 0) + 1;
    }

    Map<int, String> result = {};
    dailyCounts.forEach((day, counts) {
      final absent = counts['gelmedi'] ?? 0;
      final late = counts['geckaldi'] ?? 0;
      
      // %20'den fazlası gelmediyse kırmızı, %10'dan fazlası geç kaldıysa sarı, aksi halde yeşil.
      if (absent > (totalStaff * 0.2)) {
        result[day] = 'gelmedi';
      } else if (late > (totalStaff * 0.1) || absent > 0) {
        result[day] = 'geckaldi'; // Birkaç kişi gelmediyse veya geç geldiyse sarı yansın.
      } else {
        result[day] = 'geldi';
      }
    });
    return result;
  }

  // ==================== HELPERS ====================

  int _calculateWorkDuration(String startTime, String endTime, int breakDuration) {
    final start = _parseTime(startTime);
    final end = _parseTime(endTime);
    int totalMinutes = end.difference(start).inMinutes;
    if (totalMinutes < 0) totalMinutes += 24 * 60;
    return totalMinutes - breakDuration;
  }

  DateTime _parseTime(String time) {
    final parts = time.split(':');
    return DateTime(2024, 1, 1, int.parse(parts[0]), int.parse(parts[1]));
  }
}
