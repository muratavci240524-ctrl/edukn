import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Dönem yönetimi için merkezi servis
/// 
/// KULLANIM:
/// - Kayıt yaparken: getActiveTermId() kullan (her zaman aktif döneme kaydet)
/// - Görüntülerken: getSelectedTermId() kullan (geçmiş dönem seçilmişse onu göster)
class TermService {
  static final TermService _instance = TermService._internal();
  factory TermService() => _instance;
  TermService._internal();

  String? _cachedSelectedTermId;
  String? _cachedActiveTermId;
  
  /// Görüntüleme için seçili dönem ID'sini döndürür
  /// Eğer geçmiş dönem seçilmişse onu, yoksa null döndürür
  /// NOT: Aktif dönemi döndürmez - bu sayede aktif dönemde olduğumuz anlaşılır
  Future<String?> getSelectedTermId() async {
    // Her zaman SharedPreferences'tan oku (cache güvenilir değil)
    final prefs = await SharedPreferences.getInstance();
    final savedTermId = prefs.getString('selected_term_id');
    _cachedSelectedTermId = savedTermId;
    return savedTermId;
  }
  
  /// Kayıt için aktif dönem ID'sini döndürür (Firestore'dan)
  /// YENİ KAYITLAR HER ZAMAN AKTİF DÖNEME YAPILIR
  Future<String?> getActiveTermId() async {
    if (_cachedActiveTermId != null) return _cachedActiveTermId;
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      
      final email = user.email!;
      final institutionId = email.split('@')[1].split('.')[0].toUpperCase();
      
      final snapshot = await FirebaseFirestore.instance
          .collection('terms')
          .where('institutionId', isEqualTo: institutionId)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      
      if (snapshot.docs.isNotEmpty) {
        _cachedActiveTermId = snapshot.docs.first.id;
        return _cachedActiveTermId;
      }
    } catch (e) {
      print('Aktif dönem alınırken hata: $e');
    }
    return null;
  }
  
  /// Seçili dönem adını döndürür
  Future<String?> getSelectedTermName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_term_name');
  }
  
  /// Geçmiş dönem görüntüleniyor mu?
  Future<bool> isViewingPastTerm() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_term_id') != null;
  }
  
  /// Dönem seçimini kaydet (görüntüleme için)
  Future<void> setSelectedTerm(String termId, String termName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_term_id', termId);
    await prefs.setString('selected_term_name', termName);
    _cachedSelectedTermId = termId;
  }
  
  /// Dönem seçimini temizle (aktif döneme dön)
  Future<void> clearSelectedTerm() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selected_term_id');
    await prefs.remove('selected_term_name');
    _cachedSelectedTermId = null;
  }
  
  /// Cache'i temizle (dönem değiştiğinde çağrılmalı)
  void clearCache() {
    _cachedSelectedTermId = null;
    _cachedActiveTermId = null;
  }
  
  /// Institution ID'yi al
  String? getInstitutionId() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final email = user.email!;
    return email.split('@')[1].split('.')[0].toUpperCase();
  }

  /// Mevcut verileri (termId null olanları) aktif döneme ata
  /// Bu fonksiyon bir kez çalıştırılmalı - migration için
  Future<int> migrateDataToActiveTerm() async {
    final activeTermId = await getActiveTermId();
    if (activeTermId == null) {
      print('Aktif dönem bulunamadı, migration yapılamıyor');
      return 0;
    }

    final institutionId = getInstitutionId();
    if (institutionId == null) return 0;

    int migratedCount = 0;
    final collections = ['students', 'classes', 'lessons', 'classrooms', 'yearlyPlans', 'workPeriods'];

    for (final collectionName in collections) {
      try {
        // termId null olan kayıtları bul
        final snapshot = await FirebaseFirestore.instance
            .collection(collectionName)
            .where('institutionId', isEqualTo: institutionId)
            .get();

        for (final doc in snapshot.docs) {
          final data = doc.data();
          // termId yoksa veya null ise aktif döneme ata
          if (data['termId'] == null) {
            await doc.reference.update({'termId': activeTermId});
            migratedCount++;
          }
        }
        print('$collectionName: ${snapshot.docs.length} kayıt kontrol edildi');
      } catch (e) {
        print('$collectionName migration hatası: $e');
      }
    }

    // Duyuruları da aktif döneme ata (schools/{schoolId}/announcements)
    try {
      final schoolSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .where('institutionId', isEqualTo: institutionId)
          .limit(1)
          .get();
      
      if (schoolSnapshot.docs.isNotEmpty) {
        final schoolId = schoolSnapshot.docs.first.id;
        final announcementsSnapshot = await FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('announcements')
            .get();
        
        for (final doc in announcementsSnapshot.docs) {
          final data = doc.data();
          if (data['termId'] == null) {
            await doc.reference.update({'termId': activeTermId});
            migratedCount++;
          }
        }
        print('announcements: ${announcementsSnapshot.docs.length} kayıt kontrol edildi');
      }
    } catch (e) {
      print('announcements migration hatası: $e');
    }

    print('Toplam $migratedCount kayıt aktif döneme atandı');
    return migratedCount;
  }

  /// Tüm verileri sil (öğrenciler, sınıflar, dersler, derslikler, planlar, duyurular vb.)
  /// DİKKAT: Bu işlem geri alınamaz!
  Future<int> deleteAllData() async {
    final institutionId = getInstitutionId();
    if (institutionId == null) return 0;

    int deletedCount = 0;
    final collections = [
      'students',
      'classes', 
      'lessons',
      'classrooms',
      'yearlyPlans',
      'workPeriods',
      'lessonHours',
    ];

    for (final collectionName in collections) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection(collectionName)
            .where('institutionId', isEqualTo: institutionId)
            .get();

        for (final doc in snapshot.docs) {
          await doc.reference.delete();
          deletedCount++;
        }
        print('$collectionName: ${snapshot.docs.length} kayıt silindi');
      } catch (e) {
        print('$collectionName silme hatası: $e');
      }
    }

    // Duyuruları sil (schools/{schoolId}/announcements)
    try {
      final schoolSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .where('institutionId', isEqualTo: institutionId)
          .limit(1)
          .get();
      
      if (schoolSnapshot.docs.isNotEmpty) {
        final schoolId = schoolSnapshot.docs.first.id;
        final announcementsSnapshot = await FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('announcements')
            .get();
        
        for (final doc in announcementsSnapshot.docs) {
          await doc.reference.delete();
          deletedCount++;
        }
        print('announcements: ${announcementsSnapshot.docs.length} kayıt silindi');
      }
    } catch (e) {
      print('announcements silme hatası: $e');
    }

    print('Toplam $deletedCount kayıt silindi');
    return deletedCount;
  }
}
