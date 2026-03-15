import 'package:cloud_firestore/cloud_firestore.dart';

class ShiftService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ==================== SHIFT TEMPLATES ====================

  // Yeni vardiya şablonu oluştur
  Future<String> createShiftTemplate({
    required String name,
    required String startTime, // "08:00"
    required String endTime, // "17:00"
    required int breakDuration, // minutes
  }) async {
    final workDuration = _calculateWorkDuration(startTime, endTime, breakDuration);
    
    final docRef = await _firestore.collection('shift_templates').add({
      'name': name,
      'startTime': startTime,
      'endTime': endTime,
      'breakDuration': breakDuration,
      'workDuration': workDuration,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    
    return docRef.id;
  }

  // Vardiya şablonlarını getir
  Future<List<Map<String, dynamic>>> getShiftTemplates({bool onlyActive = true}) async {
    Query query = _firestore.collection('shift_templates');
    
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

  // Vardiya şablonunu güncelle
  Future<void> updateShiftTemplate(String id, Map<String, dynamic> updates) async {
    if (updates.containsKey('startTime') || updates.containsKey('endTime') || updates.containsKey('breakDuration')) {
      // Eğer saat değişirse workDuration'ı yeniden hesapla
      final doc = await _firestore.collection('shift_templates').doc(id).get();
      final current = doc.data()!;
      
      final startTime = updates['startTime'] ?? current['startTime'];
      final endTime = updates['endTime'] ?? current['endTime'];
      final breakDuration = updates['breakDuration'] ?? current['breakDuration'];
      
      updates['workDuration'] = _calculateWorkDuration(startTime, endTime, breakDuration);
    }
    
    await _firestore.collection('shift_templates').doc(id).update(updates);
  }

  // Vardiya şablonunu sil (soft delete)
  Future<void> deleteShiftTemplate(String id) async {
    await _firestore.collection('shift_templates').doc(id).update({'isActive': false});
  }

  // ==================== STAFF SCHEDULING ====================

  // Personel için aylık program oluştur/güncelle
  Future<void> assignShift({
    required String userId,
    required String month, // "2025-11"
    required String date, // "2025-11-23"
    required String shiftTemplateId,
  }) async {
    final docId = '${userId}_$month';
    
    final docRef = _firestore.collection('staff_schedules').doc(docId);
    final doc = await docRef.get();
    
    if (doc.exists) {
      // Güncelle
      await docRef.update({
        'assignments.$date': shiftTemplateId,
      });
    } else {
      // Yeni oluştur
      await docRef.set({
        'userId': userId,
        'month': month,
        'assignments': {date: shiftTemplateId},
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // Personelin belirli bir aydaki programını getir
  Future<Map<String, dynamic>?> getStaffSchedule(String userId, String month) async {
    final docId = '${userId}_$month';
    final doc = await _firestore.collection('staff_schedules').doc(docId).get();
    
    if (doc.exists) {
      final data = doc.data()!;
      data['id'] = doc.id;
      return data;
    }
    return null;
  }

  // Belirli bir tarihteki tüm atamaları getir
  Future<List<Map<String, dynamic>>> getDailyAssignments(String date) async {
    // Bu sorgu için client-side filter gerekebilir çünkü Map içinde arama yapıyoruz
    final month = date.substring(0, 7); // "2025-11-23" -> "2025-11"
    
    final snapshot = await _firestore
        .collection('staff_schedules')
        .where('month', isEqualTo: month)
        .get();
    
    List<Map<String, dynamic>> results = [];
    
    for (var doc in snapshot.docs) {
      final data = doc.data();
      final assignments = data['assignments'] as Map<String, dynamic>?;
      
      if (assignments != null && assignments.containsKey(date)) {
        results.add({
          'userId': data['userId'],
          'shiftTemplateId': assignments[date],
        });
      }
    }
    
    return results;
  }

  // ==================== OVERTIME CALCULATION ====================

  // Belirli bir personel için fazla mesai hesapla
  Future<int> calculateOvertimeMinutes({
    required String userId,
    required String date,
    required DateTime checkIn,
    required DateTime checkOut,
  }) async {
    // 1. Bu tarihte atanmış vardiya var mı?
    final month = date.substring(0, 7);
    final schedule = await getStaffSchedule(userId, month);
    
    if (schedule == null) return 0;
    
    final assignments = schedule['assignments'] as Map<String, dynamic>?;
    if (assignments == null || !assignments.containsKey(date)) return 0;
    
    final shiftId = assignments[date] as String;
    
    // 2. Vardiya şablonunu getir
    final shiftDoc = await _firestore.collection('shift_templates').doc(shiftId).get();
    if (!shiftDoc.exists) return 0;
    
    final shift = shiftDoc.data()!;
    final scheduledMinutes = shift['workDuration'] as int;
    
    // 3. Gerçek çalışma süresini hesapla
    final actualMinutes = checkOut.difference(checkIn).inMinutes - (shift['breakDuration'] as int);
    
    // 4. Fazla mesai = Max(0, Actual - Scheduled)
    return actualMinutes > scheduledMinutes ? (actualMinutes - scheduledMinutes) : 0;
  }

  // ==================== HELPER METHODS ====================

  int _calculateWorkDuration(String startTime, String endTime, int breakDuration) {
    final start = _parseTime(startTime);
    final end = _parseTime(endTime);
    
    int totalMinutes = end.difference(start).inMinutes;
    
    // Gece vardiyası için (ertesi gün bitişi)
    if (totalMinutes < 0) {
      totalMinutes += 24 * 60;
    }
    
    return totalMinutes - breakDuration;
  }

  DateTime _parseTime(String time) {
    final parts = time.split(':');
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
  }
}
