import 'package:cloud_firestore/cloud_firestore.dart';

class AttendanceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'attendance';

  // Bugünün tarihini YYYY-MM-DD formatında alır
  String _getTodayDate() {
    final now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  // Personelin bugünkü kaydını getirir
  Future<Map<String, dynamic>?> getTodayAttendance(String userId, String institutionId) async {
    final date = _getTodayDate();
    final query = await _firestore
        .collection(_collection)
        .where('userId', isEqualTo: userId)
        .where('institutionId', isEqualTo: institutionId)
        .where('date', isEqualTo: date)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      final doc = query.docs.first;
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }
    return null;
  }

  // Son 24 saat içindeki aktif (çıkış yapılmamış) kaydı getirir
  Future<Map<String, dynamic>?> getLastActiveSession(String userId, String institutionId) async {
    final now = DateTime.now();
    final oneDayAgo = now.subtract(const Duration(hours: 24));
    
    // Index hatasını (FAILED_PRECONDITION) önlemek için sorguyu en basit hale getiriyoruz
    // Sadece personelin "checkOut" yapılmamış kayıtlarını alıp gerisini kodda filtreleyeceğiz.
    try {
      final query = await _firestore
          .collection(_collection)
          .where('userId', isEqualTo: userId)
          .where('checkOut', isNull: true)
          .get();

      if (query.docs.isEmpty) return null;

      // Filtreleme ve sıralamayı burada yapıyoruz (Index gerektirmez)
      final activeSessions = query.docs
          .map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          })
          .where((data) => data['institutionId'] == institutionId)
          .where((data) {
            final checkIn = data['checkIn'];
            if (checkIn is Timestamp) {
              return checkIn.toDate().isAfter(oneDayAgo);
            }
            return false;
          })
          .toList();

      if (activeSessions.isEmpty) return null;

      // En yeni kaydı döndür
      activeSessions.sort((a, b) {
        final tA = (a['checkIn'] as Timestamp).toDate();
        final tB = (b['checkIn'] as Timestamp).toDate();
        return tB.compareTo(tA);
      });

      return activeSessions.first;
    } catch (e) {
      print("Query Error (Simplifying...): $e");
      return null;
    }
  }

  // Giriş Yap (Check-In)
  Future<void> checkIn(String userId, String institutionId) async {
    final date = _getTodayDate();
    final now = DateTime.now();

    // Önce bugün kayıt var mı kontrol et
    final existing = await getTodayAttendance(userId, institutionId);
    if (existing != null) {
      throw Exception('Bugün için zaten giriş kaydı mevcut.');
    }

    await _firestore.collection(_collection).add({
      'userId': userId,
      'institutionId': institutionId,
      'date': date,
      'checkIn': Timestamp.fromDate(now),
      'checkOut': null,
      'breakDuration': 0,
      'method': 'web', // İleride 'mobile' vs olabilir
      'status': 'present', // Varsayılan olarak 'mevcut'
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Çıkış Yap (Check-Out)
  Future<void> checkOut(String userId, String institutionId, {String? docId}) async {
    final now = DateTime.now();
    String? targetId = docId;

    if (targetId == null) {
      final active = await getLastActiveSession(userId, institutionId);
      if (active == null) {
        throw Exception('Aktif bir giriş kaydı bulunamadı.');
      }
      targetId = active['id'];
    }

    await _firestore.collection(_collection).doc(targetId).update({
      'checkOut': Timestamp.fromDate(now),
    });
  }

  // Belirli bir ayın kayıtlarını getir
  Future<List<Map<String, dynamic>>> getMonthlyAttendance(String userId, String institutionId, DateTime month) async {
    // Ayın başı ve sonu
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0);

    // Tarih string karşılaştırması yapmak daha kolay olabilir: "2025-11-01" ile "2025-11-31" arası
    // Ancak Firestore'da 'date' string tutuyoruz.
    // String karşılaştırması (lexicographical) YYYY-MM-DD formatında çalışır.
    
    final startStr = "${start.year}-${start.month.toString().padLeft(2, '0')}-01";
    final endStr = "${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}";

    final query = await _firestore
        .collection(_collection)
        .where('userId', isEqualTo: userId)
        .where('institutionId', isEqualTo: institutionId)
        .where('date', isGreaterThanOrEqualTo: startStr)
        .where('date', isLessThanOrEqualTo: endStr)
        .orderBy('date', descending: true)
        .get();

    return query.docs.map((e) => e.data()).toList();
  }

  // Belirli bir tarihteki tüm kayıtları getir (İK için)
  Future<List<Map<String, dynamic>>> getAttendanceForDate(String date, String institutionId) async {
    // Birden fazla 'where' kullanıldığında Firestore 'Composite Index' gerektirir.
    // Index hatası alma riskini azaltmak için tarihe göre çekip kurumu lokalde filtreliyoruz.
    final query = await _firestore
        .collection(_collection)
        .where('date', isEqualTo: date)
        .get();

    return query.docs
        .map((e) {
          final data = e.data();
          data['id'] = e.id;
          return data;
        })
        .where((data) => data['institutionId'] == institutionId)
        .toList();
  }

  // Tarih aralığına göre kayıtları getir (Arşiv için)
  Future<List<Map<String, dynamic>>> getHistory({
    required DateTime startDate,
    required DateTime endDate,
    required String institutionId,
    String? userId,
  }) async {
    final startStr = "${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}";
    final endStr = "${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}";

    Query query = _firestore
        .collection(_collection)
        .where('date', isGreaterThanOrEqualTo: startStr)
        .where('date', isLessThanOrEqualTo: endStr);

    final snapshot = await query.get();
    
    final results = snapshot.docs.map((e) {
      final data = e.data() as Map<String, dynamic>;
      data['id'] = e.id;
      return data;
    }).where((data) {
      // Kurum filtresi lokalde (Lokal filtre en garantisidir)
      bool matches = data['institutionId'] == institutionId;
      if (matches && userId != null) {
        matches = data['userId'] == userId;
      }
      return matches;
    }).toList();
    
    // Tarihe göre yeniden eskiye sırala
    results.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    
    return results;
  }

  // Manuel Kayıt Ekleme (İK için)
  Future<void> addManualEntry({
    required String userId,
    required String institutionId,
    required DateTime date,
    required DateTime checkIn,
    DateTime? checkOut,
    String? note,
  }) async {
    final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    
    await _firestore.collection(_collection).add({
      'userId': userId,
      'institutionId': institutionId,
      'date': dateStr,
      'checkIn': Timestamp.fromDate(checkIn),
      'checkOut': checkOut != null ? Timestamp.fromDate(checkOut) : null,
      'breakDuration': 0,
      'method': 'manual',
      'status': 'present',
      'notes': note,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
  // Kayıt Güncelleme (İK için)
  Future<void> updateAttendance({
    required String docId,
    DateTime? checkIn,
    DateTime? checkOut,
    String? status,
    String? note,
  }) async {
    final updates = <String, dynamic>{};
    
    if (checkIn != null) updates['checkIn'] = Timestamp.fromDate(checkIn);
    if (checkOut != null) updates['checkOut'] = Timestamp.fromDate(checkOut);
    if (status != null) updates['status'] = status;
    if (note != null) updates['notes'] = note;
    
    // Check-out değiştiyse ve check-in varsa süreyi tekrar hesaplamak gerekebilir
    // Şimdilik basit update yapıyoruz.
    
    await _firestore.collection(_collection).doc(docId).update(updates);
  }
}
