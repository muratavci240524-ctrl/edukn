import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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
    if (_cachedSelectedTermId != null) return _cachedSelectedTermId;
    final prefs = await SharedPreferences.getInstance();
    final savedTermId = prefs.getString('selected_term_id');
    _cachedSelectedTermId = savedTermId;
    return savedTermId;
  }
  
  /// Kayıt için aktif dönem ID'sini döndürür (Firestore'dan)
  /// YENİ KAYITLAR HER ZAMAN AKTİF DÖNEME YAPILIR
  Future<String?> getActiveTermId() async {
    if (_cachedActiveTermId != null && _cachedActiveTermId!.isNotEmpty) {
      return _cachedActiveTermId;
    }

    final prefs = await SharedPreferences.getInstance();
    final savedActiveTermId = prefs.getString('active_term_id');
    if (savedActiveTermId != null && savedActiveTermId.isNotEmpty) {
      _cachedActiveTermId = savedActiveTermId;
      // ⚡ Cold Start Hızı: Kayıtlı dönemi hemen 0 ms'de döndür, arka planda sessizce doğrula!
      _refreshActiveTermInBackground();
      return _cachedActiveTermId;
    }
    
    return _internalFetchActiveTerm();
  }

  void _refreshActiveTermInBackground() {
    _internalFetchActiveTerm().catchError((e) {
      debugPrint('Background term refresh error: $e');
      return null;
    });
  }

  Future<String?> _internalFetchActiveTerm() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return _cachedActiveTermId;
      
      final email = user.email ?? '';
      final userData = await UserPermissionService.loadUserData();
      
      if (userData != null) {
        final directTermId = (userData['activeTermId'] ?? userData['termId'] ?? userData['currentTermId'])?.toString();
        if (directTermId != null && directTermId.isNotEmpty) {
          _cachedActiveTermId = directTermId;
          await prefs.setString('active_term_id', directTermId);
          return _cachedActiveTermId;
        }
      }

      final institutionId = await UserPermissionService.resolveInstitutionId(email, userData: userData);
      if (institutionId == 'GMAIL' || institutionId.isEmpty) {
        return _cachedActiveTermId;
      }
      
      final instIds = [institutionId, institutionId.toUpperCase(), institutionId.toLowerCase()].toSet().toList();
      QuerySnapshot<Map<String, dynamic>>? snapshot;

      for (final inst in instIds) {
        try {
          snapshot = await FirebaseFirestore.instance
              .collection('terms')
              .where('institutionId', isEqualTo: inst)
              .get();
          if (snapshot.docs.isNotEmpty) break;
        } catch (silentError) { debugPrint('[term_service] hata yutuldu: $silentError'); }
      }
      
      if (snapshot != null && snapshot.docs.isNotEmpty) {
        QueryDocumentSnapshot<Map<String, dynamic>>? activeDoc;
        for (final doc in snapshot.docs) {
          if (doc.data()['isActive'] == true) {
            activeDoc = doc;
            break;
          }
        }
        activeDoc ??= snapshot.docs.first;
        _cachedActiveTermId = activeDoc.id;
        await prefs.setString('active_term_id', activeDoc.id);
        final tName = activeDoc.data()['name']?.toString();
        if (tName != null) {
          await prefs.setString('active_term_name', tName);
        }
        return _cachedActiveTermId;
      }

      // Fallback 1: Kurum belgesinde tanımlı aktif dönem
      for (final inst in instIds) {
        try {
          final instDoc = await FirebaseFirestore.instance.collection('institutions').doc(inst).get();
          if (instDoc.exists) {
            final instTerm = (instDoc.data()?['activeTermId'] ?? instDoc.data()?['termId'])?.toString();
            if (instTerm != null && instTerm.isNotEmpty) {
              _cachedActiveTermId = instTerm;
              await prefs.setString('active_term_id', instTerm);
              return _cachedActiveTermId;
            }
          }
        } catch (silentError) { debugPrint('[term_service] hata yutuldu: $silentError'); }
      }

      // Fallback 2: trial_exams koleksiyonu üzerinden son aktif dönem
      for (final inst in instIds) {
        try {
          final examSnap = await FirebaseFirestore.instance
              .collection('trial_exams')
              .where('institutionId', isEqualTo: inst)
              .limit(5)
              .get();
          for (final doc in examSnap.docs) {
            final tId = doc.data()['termId']?.toString();
            if (tId != null && tId.isNotEmpty) {
              _cachedActiveTermId = tId;
              await prefs.setString('active_term_id', tId);
              return _cachedActiveTermId;
            }
          }
        } catch (silentError) { debugPrint('[term_service] hata yutuldu: $silentError'); }
      }
    } catch (e) {
      debugPrint('Aktif dönem alınırken hata: $e');
    }

    if (_cachedActiveTermId != null) return _cachedActiveTermId;
    return prefs.getString('selected_term_id');
  }
  
  /// Seçili dönem adını döndürür
  Future<String?> getSelectedTermName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_term_name') ?? prefs.getString('active_term_name');
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
    await prefs.setString('active_term_id', termId);
    _cachedSelectedTermId = termId;
    _cachedActiveTermId ??= termId;
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
    // Güvenlik: geçmiş dönem görüntülenirken çalıştırılırsa kayıtlar yanlış döneme yazılır
    if (await getSelectedTermId() != null) {
      debugPrint('Geçmiş dönem seçili, migration iptal edildi. Önce aktif döneme dönün.');
      return 0;
    }
    final activeTermId = await getActiveTermId();
    if (activeTermId == null) {
      debugPrint('Aktif dönem bulunamadı, migration yapılamıyor');
      return 0;
    }

    final institutionId = await getInstitutionId();
    if (institutionId == 'GMAIL') return 0;

    int migratedCount = 0;
    final collections = ['students', 'classes', 'lessons', 'classrooms', 'yearlyPlans', 'workPeriods', 'lessonAssignments', 'classSchedules', 'social_media_posts', 'trial_exams', 'external_exams', 'exam_types', 'optical_forms', 'outcome_lists', 'assessment_action_plans'];

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
        debugPrint('$collectionName: ${snapshot.docs.length} kayıt kontrol edildi');
      } catch (e) {
        debugPrint('$collectionName migration hatası: $e');
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
        debugPrint('announcements: ${announcementsSnapshot.docs.length} kayıt kontrol edildi');
      }
    } catch (e) {
      debugPrint('announcements migration hatası: $e');
    }

    await deduplicateAndCleanClasses(institutionId: institutionId);
    debugPrint('Toplam $migratedCount kayıt aktif döneme atandı');
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
      'social_media_posts',
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
        debugPrint('$collectionName: ${snapshot.docs.length} kayıt silindi');
      } catch (e) {
        debugPrint('$collectionName silme hatası: $e');
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
        debugPrint('announcements: ${announcementsSnapshot.docs.length} kayıt silindi');
      }
    } catch (e) {
      debugPrint('announcements silme hatası: $e');
    }

    debugPrint('Toplam $deletedCount kayıt silindi');
    return deletedCount;
  }

  /// Mükerrer (aynı isimli) ve boş şubeleri tespit eder, öğrencileri/dersleri
  /// dolu olan asıl şubede birleştirir ve mükerrer/boş kopyaları Firestore'dan siler.
  /// Ayrıca sınıf atlatma kaynaklı String `classLevel` ('7', '8') ve eski `shortName`
  /// alanlarını standartlaştırır.
  Future<int> deduplicateAndCleanClasses({
    String? institutionId,
    String? schoolTypeId,
    String? termId,
  }) async {
    try {
      final instId = (institutionId ?? await getInstitutionId()).trim();
      if (instId.isEmpty || instId == 'GMAIL') return 0;

      final db = FirebaseFirestore.instance;
      final activeTermId = await getActiveTermId();

      // 1. Kuruma ait tüm şubeleri çek
      var classesQuery = db
          .collection('classes')
          .where('institutionId', isEqualTo: instId);
      if (schoolTypeId != null && schoolTypeId.isNotEmpty) {
        classesQuery = classesQuery.where(
          'schoolTypeId',
          isEqualTo: schoolTypeId,
        );
      }
      final classesSnap = await classesQuery.get();
      if (classesSnap.docs.isEmpty) return 0;

      // 2. Kuruma ait aktif öğrencileri, ders atamalarını ve ders programı slotlarını çek
      final studentsSnap = await db
          .collection('students')
          .where('institutionId', isEqualTo: instId)
          .get();
      final assignmentsSnap = await db
          .collection('lessonAssignments')
          .where('institutionId', isEqualTo: instId)
          .get();
      final schedulesSnap = await db
          .collection('classSchedules')
          .where('institutionId', isEqualTo: instId)
          .get();

      // Her classId için öğrenci, ders ataması ve ders programı sayısı
      final studentCountByClass = <String, int>{};
      final studentDocsByClass =
          <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
      for (final sDoc in studentsSnap.docs) {
        final sData = sDoc.data();
        if (sData['isActive'] == false) continue;
        final cId = (sData['classId'] ?? '').toString().trim();
        if (cId.isNotEmpty) {
          studentCountByClass[cId] = (studentCountByClass[cId] ?? 0) + 1;
          studentDocsByClass.putIfAbsent(cId, () => []).add(sDoc);
        }
      }

      final assignmentDocsByClass =
          <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
      for (final aDoc in assignmentsSnap.docs) {
        final aData = aDoc.data();
        if (aData['isActive'] == false) continue;
        final cId = (aData['classId'] ?? '').toString().trim();
        if (cId.isNotEmpty) {
          assignmentDocsByClass.putIfAbsent(cId, () => []).add(aDoc);
        }
      }

      final scheduleDocsByClass =
          <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
      for (final schDoc in schedulesSnap.docs) {
        final schData = schDoc.data();
        if (schData['isActive'] == false) continue;
        final cId = (schData['classId'] ?? '').toString().trim();
        if (cId.isNotEmpty) {
          scheduleDocsByClass.putIfAbsent(cId, () => []).add(schDoc);
        }
      }

      var batch = db.batch();
      int batchOps = 0;
      int cleanedCount = 0;

      Future<void> commitIfNeeded({bool force = false}) async {
        if (batchOps > 0 && (force || batchOps >= 400)) {
          await batch.commit();
          batch = db.batch();
          batchOps = 0;
        }
      }

      // 3. Aktif şubelerde String olarak kalmış classLevel ('7' -> 7) ve shortName uyumsuzluklarını onar
      for (final cDoc in classesSnap.docs) {
        final cData = cDoc.data();
        if (cData['isActive'] == false) continue;

        final updates = <String, dynamic>{};
        final rawLevel = cData['classLevel'];
        if (rawLevel is String) {
          final parsed = int.tryParse(rawLevel.trim());
          if (parsed != null) {
            updates['classLevel'] = parsed;
          }
        }

        final cName = (cData['className'] ?? '').toString().trim();
        final sName = (cData['shortName'] ?? '').toString().trim();
        if (cName.isNotEmpty &&
            cName.length <= 5 &&
            sName.isNotEmpty &&
            sName != cName &&
            cData['copiedFrom'] != null) {
          updates['shortName'] = cName;
        }

        if (updates.isNotEmpty) {
          batch.update(cDoc.reference, updates);
          batchOps++;
          await commitIfNeeded();
        }
      }

      // 4. Aynı (schoolTypeId, termId, className) içindeki mükerrer şubeleri grupla
      final groupedSameTerm =
          <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
      for (final cDoc in classesSnap.docs) {
        final cData = cDoc.data();
        if (cData['isActive'] == false) continue;
        final stId = (cData['schoolTypeId'] ?? '').toString().trim();
        final tId = (cData['termId'] ?? activeTermId ?? '').toString().trim();
        if (termId != null && termId.isNotEmpty && tId != termId) continue;
        final normName = (cData['className'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (normName.isEmpty) continue;

        final key = '${stId}__${tId}__$normName';
        groupedSameTerm.putIfAbsent(key, () => []).add(cDoc);
      }

      final deletedDocIds = <String>{};
      // Kazanan şube haritası: '${schoolTypeId}__${termId}__${normName}' -> winnerDoc
      final canonicalByTermAndName =
          <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

      for (final entry in groupedSameTerm.entries) {
        final docs = entry.value;
        if (docs.length == 1) {
          canonicalByTermAndName[entry.key] = docs.first;
          continue;
        }

        // En çok öğrencisi olan, eşitse en çok ders ataması/programı olan,
        // eşitse öğretmeni tanımlı veya int classLevel'a sahip olan şubeyi kazanan seç
        docs.sort((a, b) {
          final sA = studentCountByClass[a.id] ?? 0;
          final sB = studentCountByClass[b.id] ?? 0;
          if (sA != sB) return sB.compareTo(sA);

          final aAssign =
              (assignmentDocsByClass[a.id]?.length ?? 0) +
              (scheduleDocsByClass[a.id]?.length ?? 0);
          final bAssign =
              (assignmentDocsByClass[b.id]?.length ?? 0) +
              (scheduleDocsByClass[b.id]?.length ?? 0);
          if (aAssign != bAssign) return bAssign.compareTo(aAssign);

          final aHasTeacher =
              (a.data()['classTeacherId'] ?? '').toString().isNotEmpty ? 1 : 0;
          final bHasTeacher =
              (b.data()['classTeacherId'] ?? '').toString().isNotEmpty ? 1 : 0;
          if (aHasTeacher != bHasTeacher) {
            return bHasTeacher.compareTo(aHasTeacher);
          }

          final aIntLvl = a.data()['classLevel'] is int ? 1 : 0;
          final bIntLvl = b.data()['classLevel'] is int ? 1 : 0;
          return bIntLvl.compareTo(aIntLvl);
        });

        final winner = docs.first;
        final winnerData = winner.data();
        final winnerName = (winnerData['className'] ?? '').toString().trim();
        canonicalByTermAndName[entry.key] = winner;

        final winnerUpdates = <String, dynamic>{};
        if (winnerData['classLevel'] is String) {
          final parsed = int.tryParse(winnerData['classLevel'].toString());
          if (parsed != null) winnerUpdates['classLevel'] = parsed;
        }

        for (int i = 1; i < docs.length; i++) {
          final loser = docs[i];
          final loserData = loser.data();

          // Kazanan şubede eksik olan öğretmen/sınıf tipi bilgisini yedekten tamamla
          if ((winnerData['classTeacherId'] == null ||
                  winnerData['classTeacherId'].toString().isEmpty) &&
              loserData['classTeacherId'] != null &&
              loserData['classTeacherId'].toString().isNotEmpty) {
            winnerUpdates['classTeacherId'] = loserData['classTeacherId'];
            winnerUpdates['classTeacherName'] = loserData['classTeacherName'];
          }
          if ((winnerData['classTypeId'] == null ||
                  winnerData['classTypeId'].toString().isEmpty) &&
              loserData['classTypeId'] != null &&
              loserData['classTypeId'].toString().isNotEmpty) {
            winnerUpdates['classTypeId'] = loserData['classTypeId'];
            winnerUpdates['classTypeName'] = loserData['classTypeName'];
          }

          // Kaybeden şubeye bağlı öğrencileri kazanana taşı
          for (final sDoc in studentDocsByClass[loser.id] ?? const []) {
            batch.update(sDoc.reference, {
              'classId': winner.id,
              'className': winnerName,
            });
            batchOps++;
            await commitIfNeeded();
          }

          // Kaybeden şubeye bağlı ders atamalarını kazanana taşı
          for (final aDoc in assignmentDocsByClass[loser.id] ?? const []) {
            batch.update(aDoc.reference, {
              'classId': winner.id,
              'className': winnerName,
            });
            batchOps++;
            await commitIfNeeded();
          }

          // Kaybeden şubeye bağlı ders programı slotlarını kazanana taşı
          for (final schDoc in scheduleDocsByClass[loser.id] ?? const []) {
            batch.update(schDoc.reference, {
              'classId': winner.id,
              'className': winnerName,
            });
            batchOps++;
            await commitIfNeeded();
          }

          // Mükerrer / boş şubeyi tamamen sil
          batch.delete(loser.reference);
          deletedDocIds.add(loser.id);
          cleanedCount++;
          batchOps++;
          await commitIfNeeded();
        }

        if (winnerUpdates.isNotEmpty) {
          batch.update(winner.reference, winnerUpdates);
          batchOps++;
          await commitIfNeeded();
        }
      }

      // 5. Aktif dönemde aynı isimli şubesi bulunan fakat eski/farklı dönemde
      // hiç öğrencisi olmayan (0 öğrenci) boş mükerrer şubeleri de temizle
      if (activeTermId != null && activeTermId.isNotEmpty) {
        final activeClassNamesBySchoolType = <String, Set<String>>{};
        for (final cDoc in classesSnap.docs) {
          if (deletedDocIds.contains(cDoc.id)) continue;
          final cData = cDoc.data();
          if (cData['isActive'] == false) continue;
          final tId = (cData['termId'] ?? '').toString().trim();
          if (tId != activeTermId) continue;
          final stId = (cData['schoolTypeId'] ?? '').toString().trim();
          final normName = (cData['className'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          if (normName.isNotEmpty) {
            activeClassNamesBySchoolType
                .putIfAbsent(stId, () => <String>{})
                .add(normName);
          }
        }

        for (final cDoc in classesSnap.docs) {
          if (deletedDocIds.contains(cDoc.id)) continue;
          final cData = cDoc.data();
          final tId = (cData['termId'] ?? '').toString().trim();
          if (tId == activeTermId) continue;

          final stId = (cData['schoolTypeId'] ?? '').toString().trim();
          final normName = (cData['className'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          final sCount = studentCountByClass[cDoc.id] ?? 0;
          final hasActiveCounterpart =
              activeClassNamesBySchoolType[stId]?.contains(normName) ?? false;

          // Öğrencisi olmayan (boş) ve aktif dönemde karşılığı olan şubeyi sil
          if (sCount == 0 && hasActiveCounterpart) {
            batch.delete(cDoc.reference);
            deletedDocIds.add(cDoc.id);
            cleanedCount++;
            batchOps++;
            await commitIfNeeded();
          }
        }
      }

      // 6. Öğrencilerin className'i dolu olup classId'si silinmiş veya farklı şubeyi
      // gösteriyorsa kendi dönemindeki kanonik şube ID'si ile eşleştir
      for (final sDoc in studentsSnap.docs) {
        final sData = sDoc.data();
        if (sData['isActive'] == false) continue;
        final stId = (sData['schoolTypeId'] ?? '').toString().trim();
        final tId = (sData['termId'] ?? activeTermId ?? '').toString().trim();
        final cName = (sData['className'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (cName.isEmpty || cName == 'mezun') continue;

        final canonicalDoc = canonicalByTermAndName['${stId}__${tId}__$cName'];
        if (canonicalDoc != null && sData['classId'] != canonicalDoc.id) {
          batch.update(sDoc.reference, {
            'classId': canonicalDoc.id,
            'className': (canonicalDoc.data()['className'] ?? '')
                .toString()
                .trim(),
          });
          batchOps++;
          await commitIfNeeded();
        }
      }

      await commitIfNeeded(force: true);
      if (cleanedCount > 0) {
        debugPrint(
          '🧹 deduplicateAndCleanClasses: $cleanedCount mükerrer/boş şube temizlendi.',
        );
      }
      return cleanedCount;
    } catch (e) {
      debugPrint('deduplicateAndCleanClasses hatası: $e');
      return 0;
    }
  }

  /// Veritabanı bütünlük taraması ve onarımı
  Future<void> healDatabaseMismatches() async {
    try {
      final institutionId = await getInstitutionId();
      if (institutionId == 'GMAIL' || institutionId.isEmpty) {
        debugPrint('ℹ️ Oturum açılmamış veya geçersiz kurum, bütünlük taraması atlanıyor.');
        return;
      }

      // Önce mükerrer ve boş şubeleri birleştirip temizle
      await deduplicateAndCleanClasses(institutionId: institutionId);
      
      final db = FirebaseFirestore.instance;
      debugPrint('=== STARTING DATABASE INTEGRITY SCAN & HEALING ===');
      debugPrint('Kurum: $institutionId');
      
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
      debugPrint('Yüklenen alt dönem sayısı: ${periodTermMap.length}');
      if (periodTermMap.isEmpty) {
        debugPrint('ℹ️ Herhangi bir alt dönem bulunamadı, tarama sonlandırılıyor.');
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
      debugPrint('Yüklenen şube sayısı: ${classMap.length}');
      
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
      debugPrint('Yüklenen ders tanımı sayısı: ${lessonMap.length}');
      
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
      debugPrint('Mevcut atama sayısı: ${assignmentSet.length}');

      // 5. Ders programı slotlarını tara
      final schedulesSnap = await db.collection('classSchedules')
          .where('institutionId', isEqualTo: institutionId)
          .get();
      debugPrint('Toplam program slot sayısı: ${schedulesSnap.docs.length}');
      
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
      debugPrint('Mevcut doğru formatta slot sayısı: ${existingCorrectDocIds.length}');

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
      
      debugPrint('=== INTEGRITY SCAN SUMMARY ===');
      debugPrint('Tarama Yapılan Şube Sınıf Mismatch: $schedulesMismatched');
      debugPrint('Onarılan Slot Sayısı: $schedulesHealed');
      debugPrint('Yeni Oluşturulan Atama Sayısı: $assignmentsCreated');
      debugPrint('=============================================');
    } catch (e) {
      debugPrint('❌ healDatabaseMismatches Hatası: $e');
    }
  }
}
