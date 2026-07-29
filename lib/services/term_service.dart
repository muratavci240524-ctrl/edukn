import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'user_permission_service.dart';

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
      final userData = await UserPermissionService.loadUserData();
      final institutionId = await UserPermissionService.resolveInstitutionId(email, userData: userData);
      if (institutionId == 'GMAIL' || institutionId.isEmpty) {
        return null;
      }
      
      final snapshot = await FirebaseFirestore.instance
          .collection('terms')
          .where('institutionId', isEqualTo: institutionId)
          .get();
      
      if (snapshot.docs.isNotEmpty) {
        QueryDocumentSnapshot<Map<String, dynamic>>? activeDoc;
        for (final doc in snapshot.docs) {
          if (doc.data()['isActive'] == true) {
            activeDoc = doc;
            break;
          }
        }
        activeDoc ??= snapshot.docs.first;
        _cachedActiveTermId = activeDoc.id;
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
  Future<String> getInstitutionId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'GMAIL';
    final email = user.email!;
    final userData = await UserPermissionService.loadUserData();
    return await UserPermissionService.resolveInstitutionId(email, userData: userData);
  }

  /// Mevcut verileri (termId null olanları) aktif döneme ata
  /// Bu fonksiyon bir kez çalıştırılmalı - migration için
  Future<int> migrateDataToActiveTerm() async {
    final activeTermId = await getActiveTermId();
    if (activeTermId == null) {
      print('Aktif dönem bulunamadı, migration yapılamıyor');
      return 0;
    }

    final institutionId = await getInstitutionId();
    if (institutionId == 'GMAIL') return 0;

    int migratedCount = 0;
    final collections = ['students', 'classes', 'lessons', 'classrooms', 'yearlyPlans', 'workPeriods', 'lessonAssignments', 'classSchedules'];

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
    final institutionId = await getInstitutionId();
    if (institutionId == 'GMAIL') return 0;

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

  /// Veritabanı bütünlük taraması ve onarımı
  Future<void> healDatabaseMismatches() async {
    try {
      final institutionId = await getInstitutionId();
      if (institutionId == 'GMAIL' || institutionId.isEmpty) {
        print('ℹ️ Oturum açılmamış veya geçersiz kurum, bütünlük taraması atlanıyor.');
        return;
      }
      
      final db = FirebaseFirestore.instance;
      print('=== STARTING DATABASE INTEGRITY SCAN & HEALING ===');
      print('Kurum: $institutionId');
      
      // 1. Tüm workPeriods yükle
      final periodsSnap = await db.collection('workPeriods')
          .where('institutionId', isEqualTo: institutionId)
          .get();
      final periodTermMap = <String, String>{}; // periodId -> termId
      for (var doc in periodsSnap.docs) {
        final termId = doc.data()['termId'] as String?;
        if (termId != null) {
          periodTermMap[doc.id] = termId;
        }
      }
      print('Yüklenen alt dönem sayısı: ${periodTermMap.length}');
      if (periodTermMap.isEmpty) {
        print('ℹ️ Herhangi bir alt dönem bulunamadı, tarama sonlandırılıyor.');
        return;
      }
      
      // 2. Tüm şubeleri yükle
      final classesSnap = await db.collection('classes')
          .where('institutionId', isEqualTo: institutionId)
          .get();
      final classMap = <String, Map<String, dynamic>>{};
      final classByNameAndTerm = <String, Map<String, String>>{}; // className -> {termId: classId}
      
      for (var doc in classesSnap.docs) {
        final data = doc.data();
        classMap[doc.id] = data;
        
        final className = (data['className'] ?? '').toString().trim();
        final termId = (data['termId'] ?? '').toString().trim();
        if (className.isNotEmpty && termId.isNotEmpty) {
          classByNameAndTerm.putIfAbsent(className, () => {});
          classByNameAndTerm[className]![termId] = doc.id;
        }
      }
      print('Yüklenen şube sayısı: ${classMap.length}');
      
      // 3. Tüm dersleri yükle
      final lessonsSnap = await db.collection('lessons')
          .where('institutionId', isEqualTo: institutionId)
          .get();
      final lessonMap = <String, Map<String, dynamic>>{};
      final lessonByNameAndTerm = <String, Map<String, String>>{}; // lessonName -> {termId: lessonId}
      
      for (var doc in lessonsSnap.docs) {
        final data = doc.data();
        lessonMap[doc.id] = data;
        
        final lessonName = (data['lessonName'] ?? '').toString().trim();
        final termId = (data['termId'] ?? '').toString().trim();
        if (lessonName.isNotEmpty && termId.isNotEmpty) {
          lessonByNameAndTerm.putIfAbsent(lessonName, () => {});
          lessonByNameAndTerm[lessonName]![termId] = doc.id;
        }
      }
      print('Yüklenen ders tanımı sayısı: ${lessonMap.length}');
      
      // 4. Mevcut atamaları yükle
      final assignmentsSnap = await db.collection('lessonAssignments')
          .where('institutionId', isEqualTo: institutionId)
          .get();
      final assignmentSet = <String>{}; // "classId_lessonId"
      for (var doc in assignmentsSnap.docs) {
        final data = doc.data();
        final classId = data['classId'] as String?;
        final lessonId = data['lessonId'] as String?;
        final isActive = data['isActive'] ?? true;
        if (classId != null && lessonId != null && isActive) {
          assignmentSet.add('${classId}_$lessonId');
        }
      }
      print('Mevcut atama sayısı: ${assignmentSet.length}');

      // 5. Ders programı slotlarını tara
      final schedulesSnap = await db.collection('classSchedules')
          .where('institutionId', isEqualTo: institutionId)
          .get();
      print('Toplam program slot sayısı: ${schedulesSnap.docs.length}');
      
      int schedulesMismatched = 0;
      int schedulesHealed = 0;
      int assignmentsCreated = 0;
      
      final newAssignmentsToCreate = <String, Map<String, dynamic>>{}; // "classId_lessonId" -> data
      final assignmentHours = <String, int>{}; // "classId_lessonId" -> weeklyHours
      final assignmentTeachers = <String, Set<String>>{}; // "classId_lessonId" -> teacherIds
      final assignmentTeacherNames = <String, Set<String>>{}; // "classId_lessonId" -> teacherNames

      final existingCorrectDocIds = <String>{};
      for (var doc in schedulesSnap.docs) {
        final data = doc.data();
        final periodId = data['periodId'] as String?;
        final classId = data['classId'] as String?;
        final lessonId = data['lessonId'] as String?;
        if (periodId == null || classId == null || lessonId == null) continue;
        
        final activeTermId = periodTermMap[periodId];
        if (activeTermId == null) continue;
        
        final classTermId = classMap[classId]?['termId'];
        final lessonTermId = lessonMap[lessonId]?['termId'];
        
        final expectedDocId = '${periodId}_${classId}_${data['day']}_${data['hourIndex']}';
        if (classTermId == activeTermId && lessonTermId == activeTermId && doc.id == expectedDocId) {
          existingCorrectDocIds.add(doc.id);
        }
      }
      print('Mevcut doğru formatta slot sayısı: ${existingCorrectDocIds.length}');

      var batch = db.batch();
      int batchOperations = 0;

      for (var doc in schedulesSnap.docs) {
        final data = doc.data();
        final periodId = data['periodId'] as String?;
        final classId = data['classId'] as String?;
        final lessonId = data['lessonId'] as String?;
        
        if (periodId == null || classId == null || lessonId == null) continue;
        
        final activeTermId = periodTermMap[periodId];
        if (activeTermId == null) continue;
        
        final classTermId = classMap[classId]?['termId'];
        final lessonTermId = lessonMap[lessonId]?['termId'];
        
        bool needsHealing = false;
        String targetClassId = classId;
        String targetLessonId = lessonId;
        
        final className = (data['className'] ?? classMap[classId]?['className'] ?? '').toString().trim();
        final lessonName = (data['lessonName'] ?? lessonMap[lessonId]?['lessonName'] ?? '').toString().trim();
        
        if (classTermId != activeTermId) {
          needsHealing = true;
          final mappedClassId = classByNameAndTerm[className]?[activeTermId];
          if (mappedClassId != null) {
            targetClassId = mappedClassId;
          }
        }
        
        if (lessonTermId != activeTermId) {
          needsHealing = true;
          final mappedLessonId = lessonByNameAndTerm[lessonName]?[activeTermId];
          if (mappedLessonId != null) {
            targetLessonId = mappedLessonId;
          }
        }
        
        final targetDocId = '${periodId}_${targetClassId}_${data['day']}_${data['hourIndex']}';
        final hasWrongDocId = doc.id != targetDocId;
        
        if (needsHealing || hasWrongDocId) {
          schedulesMismatched++;
          
          // Eski uyumsuz dokümanı sil
          batch.delete(doc.reference);
          batchOperations++;
          
          // Eğer hedef doküman ID'si zaten doğru biçimde mevcut değilse yeni kayıt oluştur
          if (!existingCorrectDocIds.contains(targetDocId)) {
            final targetRef = db.collection('classSchedules').doc(targetDocId);
            final newData = Map<String, dynamic>.from(data);
            newData['classId'] = targetClassId;
            newData['lessonId'] = targetLessonId;
            newData['termId'] = activeTermId;
            newData['className'] = className;
            newData['lessonName'] = lessonName;
            
            batch.set(targetRef, newData, SetOptions(merge: true));
            existingCorrectDocIds.add(targetDocId); // Birden fazla çakışan kopyanın tek bir kayda indirgenmesi
            batchOperations++;
          }
          
          schedulesHealed++;
          if (batchOperations >= 400) {
            await batch.commit();
            batch = db.batch();
            batchOperations = 0;
          }
        }
        
        // Eşlenen şube ve ders için atama yoksa atama listesine ekle
        final assignmentKey = '${targetClassId}_$targetLessonId';
        if (!assignmentSet.contains(assignmentKey)) {
          assignmentHours[assignmentKey] = (assignmentHours[assignmentKey] ?? 0) + 1;
          
          final teacherId = data['teacherId'] as String?;
          final teacherName = data['teacherName'] as String?;
          if (teacherId != null && teacherId.isNotEmpty) {
            assignmentTeachers.putIfAbsent(assignmentKey, () => {}).add(teacherId);
          }
          if (teacherName != null && teacherName.isNotEmpty && teacherName != 'Öğretmen') {
            assignmentTeacherNames.putIfAbsent(assignmentKey, () => {}).add(teacherName);
          }
          
          newAssignmentsToCreate[assignmentKey] = {
            'classId': targetClassId,
            'className': className,
            'lessonId': targetLessonId,
            'lessonName': lessonName,
            'schoolTypeId': data['schoolTypeId'] ?? classMap[targetClassId]?['schoolTypeId'],
            'institutionId': data['institutionId'] ?? classMap[targetClassId]?['institutionId'],
            'termId': activeTermId,
            'isActive': true,
          };
        }
      }
      
      // Değişiklikleri kaydet
      if (batchOperations > 0) {
        await batch.commit();
      }
      
      // Eksik atamaları oluştur
      if (newAssignmentsToCreate.isNotEmpty) {
        var assignBatch = db.batch();
        int assignOps = 0;
        
        for (var entry in newAssignmentsToCreate.entries) {
          final key = entry.key;
          final baseData = entry.value;
          
          final hours = assignmentHours[key] ?? 1;
          final teacherIds = assignmentTeachers[key]?.toList() ?? [];
          final teacherNames = assignmentTeacherNames[key]?.toList() ?? [];
          
          final newDocRef = db.collection('lessonAssignments').doc();
          assignBatch.set(newDocRef, {
            ...baseData,
            'weeklyHours': hours,
            'teacherIds': teacherIds,
            'teacherNames': teacherNames,
            'createdAt': FieldValue.serverTimestamp(),
          });
          
          assignmentsCreated++;
          assignOps++;
          if (assignOps >= 450) {
            await assignBatch.commit();
            assignBatch = db.batch();
            assignOps = 0;
          }
        }
        
        if (assignOps > 0) {
          await assignBatch.commit();
        }
      }
      
      print('=== INTEGRITY SCAN SUMMARY ===');
      print('Tarama Yapılan Şube Sınıf Mismatch: $schedulesMismatched');
      print('Onarılan Slot Sayısı: $schedulesHealed');
      print('Yeni Oluşturulan Atama Sayısı: $assignmentsCreated');
      print('=============================================');
    } catch (e) {
      print('❌ healDatabaseMismatches Hatası: $e');
    }
  }
}
