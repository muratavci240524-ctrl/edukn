import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'term_service.dart';

class AnnouncementService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _schoolId;
  String? _cachedInstitutionId;

  // Helper: Get Institution ID reliably
  Future<String?> _getInstitutionId() async {
    if (_cachedInstitutionId != null) return _cachedInstitutionId;

    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      // 1. Try fetching from user document
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists && userDoc.data()!.containsKey('institutionId')) {
        _cachedInstitutionId = userDoc.data()!['institutionId'];
        return _cachedInstitutionId;
      }

      // 2. Fallback: Try finding by email query
      final query = await _firestore
          .collection('users')
          .where('email', isEqualTo: user.email)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty &&
          query.docs.first.data().containsKey('institutionId')) {
        _cachedInstitutionId = query.docs.first.data()['institutionId'];
        return _cachedInstitutionId;
      }

      // 3. Fallback: Parse from email (Legacy/Last resort)
      if (user.email != null) {
        final parts = user.email!.split('@');
        if (parts.length > 1) {
          _cachedInstitutionId = parts[1].split('.')[0].toUpperCase();
          return _cachedInstitutionId;
        }
      }
    } catch (e) {
      print('Correction error for Institution ID: $e');
    }
    return null;
  }

  // Helper: Get Institution ID from School Type Document
  Future<String?> _getInstitutionIdFromSchoolType(String schoolTypeId) async {
    if (schoolTypeId.isEmpty) return null;
    try {
      final doc = await _firestore
          .collection('schoolTypes')
          .doc(schoolTypeId)
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (data.containsKey('institutionId')) {
          _cachedInstitutionId = data['institutionId']; // Cache it!
          return _cachedInstitutionId;
        }
      }
    } catch (e) {
      print('Error getting institutionId from schoolType: $e');
    }
    return null;
  }

  // Okul bilgilerini al
  Future<void> _getSchoolInfo() async {
    if (_schoolId != null) return;

    final instId = await _getInstitutionId();
    if (instId != null) {
      final schoolQuery = await _firestore
          .collection('schools')
          .where('institutionId', isEqualTo: instId)
          .limit(1)
          .get();

      if (schoolQuery.docs.isNotEmpty) {
        _schoolId = schoolQuery.docs.first.id;
      }
    }
  }

  // Okul ID'sini al (public metod)
  Future<String?> getSchoolId() async {
    await _getSchoolInfo();
    return _schoolId;
  }

  // Tüm kullanıcıları getir
  Future<List<Map<String, dynamic>>> getAllUsers({String? schoolTypeId}) async {
    print('📋 AnnouncementService: getAllUsers called');
    try {
      String? instId;
      if (schoolTypeId != null) {
        instId = await _getInstitutionIdFromSchoolType(schoolTypeId);
      }
      instId ??= await _getInstitutionId();

      if (instId == null) {
        print('❌ No Institution ID found');
        return [];
      }

      print('📋 Fetching users for institution: $instId');

      final usersSnapshot = await _firestore
          .collection('users')
          .where('institutionId', isEqualTo: instId)
          .limit(4000)
          .get()
          .timeout(
            Duration(seconds: 15),
            onTimeout: () {
              print('⚠️ getAllUsers timed out');
              throw TimeoutException('User fetch timed out');
            },
          );

      print('✅ Got ${usersSnapshot.docs.length} users');

      final usersList = usersSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['fullName'] ?? data['name'] ?? 'İsimsiz',
          'role': data['role'] ?? 'Kullanıcı',
          'email': data['email'] ?? '',
          'username': data['username'] ?? '',
        };
      }).toList();

      // Sort by name client-side to avoid index requirement errors
      usersList.sort(
        (a, b) => (a['name'] as String).compareTo(b['name'] as String),
      );

      return usersList;
    } catch (e) {
      print('❌ Kullanıcılar alınırken hata: $e');
      return [];
    }
  }

  // Birimleri getir (roller)
  Future<List<Map<String, dynamic>>> getAllUnits() async {
    // Sistem tanımlı roller
    return [
      {'id': 'genel_mudur', 'name': 'Genel Müdür'},
      {'id': 'mudur', 'name': 'Müdür'},
      {'id': 'mudur_yardimcisi', 'name': 'Müdür Yardımcısı'},
      {'id': 'ogretmen', 'name': 'Öğretmen'},
      {'id': 'personel', 'name': 'Personel'},
      {'id': 'muhasebe', 'name': 'Muhasebe'},
      {'id': 'idari_isler', 'name': 'İdari İşler'},
      {'id': 'kutuphane', 'name': 'Kütüphane'},
      {'id': 'yemekhane', 'name': 'Yemekhane'},
    ];
  }

  // Okul türlerini getir (schoolTypes koleksiyonundan)
  Future<List<Map<String, dynamic>>> getSchoolTypes() async {
    await _getSchoolInfo();

    try {
      final instId = await _getInstitutionId();
      if (instId == null) return [];

      final schoolTypesSnapshot = await _firestore
          .collection('schoolTypes')
          .where('institutionId', isEqualTo: instId)
          .get();

      return schoolTypesSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name':
              data['schoolTypeName'] ??
              data['typeName'] ??
              data['schoolType'] ??
              'İsimsiz Okul Türü',
          'classes': data['classes'] ?? [],
          'schoolType': data['schoolType'],
        };
      }).toList();
    } catch (e) {
      print('Okul türleri alınırken hata: $e');
      return [];
    }
  }

  // Sınıf seviyelerini getir
  Future<List<Map<String, dynamic>>> getClassLevels() async {
    try {
      final instId = await _getInstitutionId();
      if (instId == null) return [];

      // Okul türlerini doğrudan Firestore'dan al (activeGrades dahil)
      final schoolTypesSnapshot = await _firestore
          .collection('schoolTypes')
          .where('institutionId', isEqualTo: instId)
          .get();

      final List<Map<String, dynamic>> allClasses = [];

      for (var doc in schoolTypesSnapshot.docs) {
        final data = doc.data();
        final schoolTypeName =
            data['schoolTypeName'] ?? data['typeName'] ?? 'Okul Türü';

        // activeGrades alanını kontrol et
        final activeGrades = data['activeGrades'] as List<dynamic>? ?? [];

        // Eğer activeGrades varsa kullan
        if (activeGrades.isNotEmpty) {
          for (var grade in activeGrades) {
            String gradeName = grade.toString();
            // Clean up: If grade implies 'Sınıf', don't append it again
            // E.g. if grade is '5. Sınıf', usage as is. If '5', become '5. Sınıf'
            if (!gradeName.toLowerCase().contains('sınıf')) {
              gradeName = '$gradeName. Sınıf';
            }

            allClasses.add({
              'id': '${doc.id}_$grade',
              'name': gradeName,
              'schoolType': schoolTypeName,
              'schoolTypeId': doc.id,
            });
          }
        }

        // classes alanını da kontrol et (geriye uyumluluk)
        final classes = data['classes'] as List<dynamic>? ?? [];
        if (classes.isNotEmpty && activeGrades.isEmpty) {
          for (var className in classes) {
            allClasses.add({
              'id': '${doc.id}_$className',
              'name': className.toString(),
              'schoolType': schoolTypeName,
              'schoolTypeId': doc.id,
            });
          }
        }
      }

      print('📚 Toplam ${allClasses.length} sınıf seviyesi bulundu');
      return allClasses;
    } catch (e) {
      print('Sınıf seviyeleri alınırken hata: $e');
      return [];
    }
  }

  // Belirli bir sınıf/şube için öğrencileri getir
  Future<List<Map<String, dynamic>>> getStudentsByClass(
    String schoolTypeId,
    String className,
    String? branch,
  ) async {
    try {
      // 1. Try to get Institution ID from the school type document itself
      String? instId = await _getInstitutionIdFromSchoolType(schoolTypeId);
      // 2. Fallback
      instId ??= await _getInstitutionId();

      if (instId == null) return [];

      print(
        '🎓 Öğrenciler aranıyor: $className, Şube: $branch, OkulTürü: $schoolTypeId',
      );

      // İndeks karmaşasından kaçınmak için temel filtrelerle çekip detay filtrelemeyi burada yapalım
      var query = _firestore
          .collection('users')
          .where('institutionId', isEqualTo: instId)
          .where('role', isEqualTo: 'Öğrenci')
          .where('class', isEqualTo: className);

      final snapshot = await query.get();

      var filteredDocs = snapshot.docs;

      // Dart tarafında filtreleme
      if (schoolTypeId.isNotEmpty) {
        filteredDocs = filteredDocs.where((doc) {
          final st = doc.data()['schoolType'];
          return st == schoolTypeId;
        }).toList();
      }

      if (branch != null && branch.isNotEmpty) {
        filteredDocs = filteredDocs.where((doc) {
          final b = doc.data()['branch'];
          // Branch ID veya Branch Name olabilir, her ihtimale karşı kontrol
          return b == branch;
        }).toList();
      }

      print('🎓 Bulunan öğrenci sayısı: ${filteredDocs.length}');

      return filteredDocs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['fullName'] ?? data['name'] ?? 'İsimsiz',
          'role': 'Öğrenci',
        };
      }).toList();
    } catch (e) {
      print('❌ Öğrenciler alınırken hata: $e');
      return [];
    }
  }

  // Belirli öğrencilerin velilerini getir
  Future<List<Map<String, dynamic>>> getParentsByStudents(
    List<String> studentIds,
  ) async {
    if (studentIds.isEmpty) return [];

    try {
      final user = _auth.currentUser;
      if (user == null) return [];

      final email = user.email!;
      final instId = email.split('@')[1].split('.')[0].toUpperCase();

      final snapshot = await _firestore
          .collection('users')
          .where('institutionId', isEqualTo: instId)
          .where('role', isEqualTo: 'Veli')
          .where('studentIds', arrayContainsAny: studentIds)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['fullName'] ?? data['name'] ?? 'İsimsiz',
          'role': 'Veli',
        };
      }).toList();
    } catch (e) {
      print('Veliler alınırken hata: $e');
      return [];
    }
  }

  // Belirli bir sınıfa ders veren öğretmenleri getir
  Future<List<Map<String, dynamic>>> getTeachersByClass(
    String schoolTypeId,
    String className,
  ) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return [];

      final email = user.email!;
      final instId = email.split('@')[1].split('.')[0].toUpperCase();

      final snapshot = await _firestore
          .collection('users')
          .where('institutionId', isEqualTo: instId)
          .where('role', isEqualTo: 'Öğretmen')
          .where('classes', arrayContains: '${schoolTypeId}_$className')
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['fullName'] ?? data['name'] ?? 'İsimsiz',
          'role': 'Öğretmen',
        };
      }).toList();
    } catch (e) {
      print('Öğretmenler alınırken hata: $e');
      return [];
    }
  }

  // Şubeleri getir
  Future<List<Map<String, dynamic>>> getBranches(String schoolTypeId) async {
    try {
      print('🌿 getBranches called with schoolTypeId: $schoolTypeId');

      // 1. Try to get Institution ID from the school type document itself (Context-aware)
      String? instId = await _getInstitutionIdFromSchoolType(schoolTypeId);
      if (instId != null) {
        print('🔍 getBranches: Found Institution ID from SchoolType: $instId');
      }

      // 2. Fallback to user-based Institution ID
      if (instId == null) {
        instId = await _getInstitutionId();
        print('🔍 getBranches: Using User-based Institution ID: $instId');
      }

      if (instId == null) {
        print('❌ getBranches: Could not determine Institution ID');
        return [];
      }

      print(
        '🌿 Şubeler getiriliyor... Sorgulanan Kurum: $instId, Filtrelenecek OkulTürü: $schoolTypeId',
      );

      // IMPORTANT: Class sections (şubeler like 11A, 11B) are stored in 'classes' collection
      // 'branches' collection is for teacher subjects (Matematik, Türkçe, etc.)

      // Try exact match first
      var snapshot = await _firestore
          .collection('classes')
          .where('institutionId', isEqualTo: instId)
          .where('schoolTypeId', isEqualTo: schoolTypeId)
          .where('isActive', isEqualTo: true)
          .get();

      // If no results with isActive filter, try without it
      if (snapshot.docs.isEmpty) {
        print(
          '🔍 getBranches: No active classes found, trying without isActive filter...',
        );
        snapshot = await _firestore
            .collection('classes')
            .where('institutionId', isEqualTo: instId)
            .where('schoolTypeId', isEqualTo: schoolTypeId)
            .get();
      }

      // If still no results, try uppercase institutionId
      if (snapshot.docs.isEmpty) {
        print(
          '🔍 getBranches: Still no classes, trying uppercase institutionId...',
        );
        snapshot = await _firestore
            .collection('classes')
            .where('institutionId', isEqualTo: instId.toUpperCase())
            .where('schoolTypeId', isEqualTo: schoolTypeId)
            .get();
      }

      print(
        '🌿 Toplam ${snapshot.docs.length} şube bulundu (Kurum: $instId, OkulTürü: $schoolTypeId).',
      );

      if (snapshot.docs.isNotEmpty) {
        final firstDoc = snapshot.docs.first.data();
        print('🌿 Örnek Şube Verisi (İlk Kayıt):');
        print('   - ID: ${snapshot.docs.first.id}');
        print('   - className: ${firstDoc['className']}');
        print('   - classLevel: ${firstDoc['classLevel']}');
        print('   - SchoolTypeId: ${firstDoc['schoolTypeId']}');
        print('   - InstitutionId: ${firstDoc['institutionId']}');
      }

      final branches = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['className'] ?? data['name'] ?? 'İsimsiz Şube',
          'classLevel': data['classLevel'] ?? data['grade'] ?? '',
          'schoolTypeId': data['schoolTypeId'] ?? '',
        };
      }).toList();

      // Sort by classLevel and then by name
      branches.sort((a, b) {
        final levelA = a['classLevel'] is int
            ? a['classLevel']
            : int.tryParse(a['classLevel'].toString()) ?? 0;
        final levelB = b['classLevel'] is int
            ? b['classLevel']
            : int.tryParse(b['classLevel'].toString()) ?? 0;
        final levelCompare = levelA.compareTo(levelB);
        if (levelCompare != 0) return levelCompare;
        return (a['name'] ?? '').toString().compareTo(
          (b['name'] ?? '').toString(),
        );
      });

      print('🌿 ${branches.length} şube hazır.');
      return branches;
    } catch (e) {
      print('❌ Şubeler alınırken hata: $e');
      return [];
    }
  }

  // Kullanıcı Ara (Sunucu Taraflı - Geliştirilmiş)
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.isEmpty) return [];
    try {
      final instId = await _getInstitutionId();
      if (instId == null) return [];

      // Case-insensitive simulation: Try Original, Capitalized, Uppercase
      List<String> variations = [];
      variations.add(query);

      if (query.length > 0) {
        String capitalized = query[0].toUpperCase() + query.substring(1);
        if (capitalized != query) variations.add(capitalized);

        String upper = query.toUpperCase();
        if (upper != query && upper != capitalized) variations.add(upper);
      }

      Map<String, Map<String, dynamic>> uniqueResults = {};

      for (var q in variations) {
        var snapshot = await _firestore
            .collection('users')
            .where('institutionId', isEqualTo: instId)
            .orderBy('fullName')
            .startAt([q])
            .endAt([q + '\uf8ff'])
            .limit(10)
            .get();

        for (var doc in snapshot.docs) {
          uniqueResults[doc.id] = {
            'id': doc.id,
            'name': doc.data()['fullName'] ?? doc.data()['name'] ?? 'İsimsiz',
            'role': doc.data()['role'] ?? 'Kullanıcı',
            'email': doc.data()['email'] ?? '',
          };
        }

        // Also try 'name' field if 'fullName' didn't yield enough
        if (uniqueResults.length < 5) {
          var snapshotName = await _firestore
              .collection('users')
              .where('institutionId', isEqualTo: instId)
              .orderBy('name')
              .startAt([q])
              .endAt([q + '\uf8ff'])
              .limit(10)
              .get();

          for (var doc in snapshotName.docs) {
            uniqueResults[doc.id] = {
              'id': doc.id,
              'name': doc.data()['fullName'] ?? doc.data()['name'] ?? 'İsimsiz',
              'role': doc.data()['role'] ?? 'Kullanıcı',
              'email': doc.data()['email'] ?? '',
            };
          }
        }
      }

      return uniqueResults.values.toList();
    } catch (e) {
      print('Arama hatası: $e');
      return [];
    }
  }

  // Grupları getir
  Future<List<Map<String, dynamic>>> getGroups() async {
    await _getSchoolInfo();
    if (_schoolId == null) return [];

    try {
      final groupsSnapshot = await _firestore
          .collection('schools')
          .doc(_schoolId)
          .collection('announcementGroups')
          .get();

      return groupsSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? 'İsimsiz Grup',
          'recipients': data['recipients'] ?? [],
          'createdAt': data['createdAt'],
        };
      }).toList();
    } catch (e) {
      print('Gruplar alınırken hata: $e');
      return [];
    }
  }

  // Grup kaydet
  Future<void> saveGroup(String groupName, List<String> recipients) async {
    await _getSchoolInfo();
    if (_schoolId == null) return;

    try {
      await _firestore
          .collection('schools')
          .doc(_schoolId)
          .collection('announcementGroups')
          .add({
            'name': groupName,
            'recipients': recipients,
            'createdAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      print('Grup kaydedilirken hata: $e');
      rethrow;
    }
  }

  // Grup sil
  Future<void> deleteRecipientGroup(String groupId) async {
    await _getSchoolInfo();
    if (_schoolId == null) {
      throw Exception('Okul bilgileri bulunamadı');
    }

    try {
      await _firestore
          .collection('schools')
          .doc(_schoolId)
          .collection('announcementGroups')
          .doc(groupId)
          .delete();
      print('✅ Grup silindi: $groupId');
    } catch (e) {
      print('❌ Grup silinirken hata: $e');
      rethrow;
    }
  }

  // Duyuru kaydet
  Future<void> saveAnnouncement({
    required String title,
    required String content,
    required List<String> recipients,
    required DateTime publishDate,
    required String publishTime,
    bool sendSms = false,
    List<Map<String, String>?> links = const [],
    bool isAnonymous = false,
    bool schedulePublish = false,
    List<Map<String, dynamic>> reminders = const [],
    String? schoolTypeId,
    Map<String, String> recipientNames = const {},
    String? repeatMode, // none, daily, weekly, biweekly, monthly
    DateTime? repeatUntil,
  }) async {
    try {
      await _getSchoolInfo();
      if (_schoolId == null) {
        print('Hata: Okul ID bulunamadı!');
        throw Exception('Okul bilgileri yüklenemedi. Lütfen tekrar deneyin.');
      }

      print('Duyuru kaydediliyor - Okul ID: $_schoolId');

      // Get user info for creator name
      String creatorName = 'Bilinmeyen';
      if (!isAnonymous && _auth.currentUser?.email != null) {
        try {
          print('🔍 Kullanıcı arıyor: ${_auth.currentUser!.email}');

          // Önce email ile ara
          var userDocs = await _firestore
              .collection('users')
              .where('email', isEqualTo: _auth.currentUser!.email)
              .limit(1)
              .get();

          // Bulunamadıysa okul ID ile ara
          if (userDocs.docs.isEmpty) {
            print('📧 Email ile bulunamadı, institutionId ile deneniyor...');
            userDocs = await _firestore
                .collection('users')
                .where('institutionId', isEqualTo: _schoolId)
                .where(
                  'username',
                  isEqualTo: _auth.currentUser!.email!.split('@')[0],
                )
                .limit(1)
                .get();
          }

          if (userDocs.docs.isNotEmpty) {
            final userData = userDocs.docs.first.data();
            print('📄 Kullanıcı verisi: $userData');
            // Dashboard'daki gibi fullName öncelikli olarak kullan
            creatorName =
                userData['fullName'] ??
                userData['name'] ??
                userData['username'] ??
                _auth.currentUser!.email?.split('@')[0] ??
                'Bilinmeyen';
            print('✅ Kullanıcı adı: $creatorName');
          } else {
            print(
              '❌ Kullanıcı dokümanı bulunamadı: ${_auth.currentUser!.email}',
            );
            creatorName =
                _auth.currentUser!.email?.split('@')[0] ?? 'Bilinmeyen';
          }
        } catch (e) {
          print('❌ Kullanıcı adı alınırken hata: $e');
          creatorName = _auth.currentUser!.email?.split('@')[0] ?? 'Bilinmeyen';
        }
      }

      // Get institution name for anonymous posts
      String institutionName = 'Kurum';
      if (isAnonymous) {
        final schoolDoc = await _firestore
            .collection('schools')
            .doc(_schoolId)
            .get();
        if (schoolDoc.exists) {
          institutionName = schoolDoc.data()?['name'] ?? 'Kurum';
          print('Okul adı bulundu: $institutionName');
        }
      }

      // Convert reminders to serializable format
      final remindersList = reminders.map((r) {
        final date = r['date'] as DateTime;
        final time = r['time'] as TimeOfDay;
        return {
          'date': Timestamp.fromDate(
            DateTime(date.year, date.month, date.day, time.hour, time.minute),
          ),
          'sent': false,
        };
      }).toList();

      // Yeni kayıtlar için aktif dönemi otomatik al
      final activeTermId = await TermService().getActiveTermId();

      final announcementData = {
        'title': title,
        'content': content,
        'recipients': recipients,
        'publishDate': Timestamp.fromDate(publishDate),
        'publishTime': publishTime,
        'sendSms': sendSms,
        'links': links,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': _auth.currentUser?.email ?? 'unknown@example.com',
        'creatorName': isAnonymous ? institutionName : creatorName,
        'isAnonymous': isAnonymous,
        'status': schedulePublish ? 'scheduled' : 'published',
        'schedulePublish': schedulePublish,
        'reminders': remindersList,
        'isReminder': false, // Ana duyuru asla hatırlatma değil
        'readBy': <String>[], // List of user IDs who have read the announcement
        'termId': activeTermId, // Dönem ID'si
        if (schoolTypeId != null)
          'schoolTypeId': schoolTypeId, // Okul türü ID'si
        'recipientNames': recipientNames,
        if (repeatMode != null && repeatMode != 'none') 'repeatMode': repeatMode,
        if (repeatUntil != null) 'repeatUntil': Timestamp.fromDate(repeatUntil),
      };

      final docRef = await _firestore
          .collection('schools')
          .doc(_schoolId)
          .collection('announcements')
          .add(announcementData);

      print('Duyuru başarıyla kaydedildi. Doküman ID: ${docRef.id}');

      // Tekrarlayan duyuruları oluştur
      if (repeatMode != null && repeatMode != 'none' && repeatUntil != null) {
        await _createRepeatedAnnouncements(
          docRef.id,
          announcementData,
          repeatMode,
          repeatUntil,
        );
      }

      // Eğer duyuru hemen yayınlanıyorsa (scheduled değilse), hatırlatmaları hemen oluştur
      if (!schedulePublish && remindersList.isNotEmpty) {
        print('🔔 Duyuru hemen yayınlandı, hatırlatmalar oluşturuluyor...');
        await _createReminderAnnouncements(docRef.id, announcementData);
      }
    } catch (e, stackTrace) {
      print('Duyuru kaydedilirken hata: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  // Duyuruları getir (sadece yayınlanmış olanlar, dönem filtresine göre)
  Stream<QuerySnapshot> getAnnouncements() {
    // Önce schoolId'yi senkron kontrol et, yoksa async olarak al
    if (_schoolId != null) {
      print('Duyurular yükleniyor - Okul ID: $_schoolId');
      return _firestore
          .collection('schools')
          .doc(_schoolId)
          .collection('announcements')
          .orderBy('publishDate', descending: true)
          .snapshots();
    }

    // schoolId yoksa, önce al sonra stream döndür
    return Stream.fromFuture(_getSchoolInfo()).asyncExpand((_) {
      if (_schoolId == null) {
        print('Hata: Okul ID bulunamadı');
        return Stream.empty();
      }
      print('Duyurular yükleniyor - Okul ID: $_schoolId');
      return _firestore
          .collection('schools')
          .doc(_schoolId)
          .collection('announcements')
          .orderBy('publishDate', descending: true)
          .snapshots();
    });
  }

  // Duyuru güncelle
  Future<void> updateAnnouncement(
    String announcementId,
    Map<String, dynamic> data,
  ) async {
    await _getSchoolInfo();
    if (_schoolId == null) return;

    try {
      // isAnonymous değişikliği varsa creatorName'i güncelle
      if (data.containsKey('isAnonymous')) {
        final isAnonymous = data['isAnonymous'] as bool;

        if (isAnonymous) {
          // Anonim ise okul adını al
          String institutionName = 'Kurum';
          try {
            final schoolDoc = await _firestore
                .collection('schools')
                .doc(_schoolId)
                .get();
            if (schoolDoc.exists) {
              institutionName = schoolDoc.data()?['name'] ?? 'Kurum';
              print('Okul adı bulundu (güncelleme): $institutionName');
            }
          } catch (e) {
            print('Okul adı alınırken hata: $e');
          }
          data['creatorName'] = institutionName;
        } else {
          // Anonim değilse kullanıcı adını al
          String creatorName = 'Bilinmeyen';
          if (_auth.currentUser?.email != null) {
            try {
              print(
                '🔍 Kullanıcı güncelleme için arıyor: ${_auth.currentUser!.email}',
              );

              // Önce email ile ara
              var userDocs = await _firestore
                  .collection('users')
                  .where('email', isEqualTo: _auth.currentUser!.email)
                  .limit(1)
                  .get();

              // Bulunamadıysa okul ID ile ara
              if (userDocs.docs.isEmpty) {
                print(
                  '📧 Email ile bulunamadı, institutionId ile deneniyor...',
                );
                userDocs = await _firestore
                    .collection('users')
                    .where('institutionId', isEqualTo: _schoolId)
                    .where(
                      'username',
                      isEqualTo: _auth.currentUser!.email!.split('@')[0],
                    )
                    .limit(1)
                    .get();
              }

              if (userDocs.docs.isNotEmpty) {
                final userData = userDocs.docs.first.data();
                print('📄 Kullanıcı verisi (güncelleme): $userData');
                creatorName =
                    userData['fullName'] ??
                    userData['name'] ??
                    userData['username'] ??
                    _auth.currentUser!.email?.split('@')[0] ??
                    'Bilinmeyen';
                print('✅ Kullanıcı adı (güncelleme): $creatorName');
              } else {
                print(
                  '❌ Kullanıcı dokümanı bulunamadı (güncelleme): ${_auth.currentUser!.email}',
                );
                creatorName =
                    _auth.currentUser!.email?.split('@')[0] ?? 'Bilinmeyen';
              }
            } catch (e) {
              print('❌ Kullanıcı adı alınırken hata (güncelleme): $e');
              creatorName =
                  _auth.currentUser!.email?.split('@')[0] ?? 'Bilinmeyen';
            }
          }
          data['creatorName'] = creatorName;
        }
      }

      await _firestore
          .collection('schools')
          .doc(_schoolId)
          .collection('announcements')
          .doc(announcementId)
          .update(data);

      // Hatırlatmaları güncelle/oluştur (eğer varsa)
      if (data.containsKey('reminders')) {
        final reminders = data['reminders'] as List<dynamic>;
        if (reminders.isNotEmpty) {
          print('🔔 Duyuru güncellendi, hatırlatmalar kontrol ediliyor...');
          // Güncel halini tekrar çek ki schoolTypeId gibi eksik alanlar da gelsin
          final updatedDoc = await _firestore
              .collection('schools')
              .doc(_schoolId)
              .collection('announcements')
              .doc(announcementId)
              .get();

          if (updatedDoc.exists) {
            await _createReminderAnnouncements(
              announcementId,
              updatedDoc.data()!,
            );
          }
        }
      }
    } catch (e) {
      print('Duyuru güncellenirken hata: $e');
      rethrow;
    }
  }

  // Duyuru sil
  Future<void> deleteAnnouncement(String announcementId) async {
    await _getSchoolInfo();
    if (_schoolId == null) return;

    try {
      await _firestore
          .collection('schools')
          .doc(_schoolId)
          .collection('announcements')
          .doc(announcementId)
          .delete();
    } catch (e) {
      print('Duyuru silinirken hata: $e');
      rethrow;
    }
  }

  // Duyuru sabitle
  Future<void> pinAnnouncement(String announcementId) async {
    await _getSchoolInfo();
    if (_schoolId == null) return;

    try {
      await _firestore
          .collection('schools')
          .doc(_schoolId)
          .collection('announcements')
          .doc(announcementId)
          .update({'isPinned': true, 'pinnedAt': FieldValue.serverTimestamp()});
      print('📌 Duyuru sabitlendi');
    } catch (e) {
      print('Duyuru sabitlenirken hata: $e');
      rethrow;
    }
  }

  // Duyuru sabitlemeyi kaldır
  Future<void> unpinAnnouncement(String announcementId) async {
    await _getSchoolInfo();
    if (_schoolId == null) return;

    try {
      await _firestore
          .collection('schools')
          .doc(_schoolId)
          .collection('announcements')
          .doc(announcementId)
          .update({'isPinned': false, 'pinnedAt': null});
      print('📌 Duyuru sabitleme kaldırıldı');
    } catch (e) {
      print('Duyuru sabitleme kaldırılırken hata: $e');
      rethrow;
    }
  }

  // Zamanlanmış duyuruları kontrol et ve yayınla
  Future<void> checkAndPublishScheduledAnnouncements() async {
    try {
      await _getSchoolInfo();
      if (_schoolId == null) return;

      final now = DateTime.now();
      print('🕐 Zamanlanmış duyurular kontrol ediliyor: ${now.toString()}');

      // Scheduled durumundaki duyuruları al
      final scheduledDocs = await _firestore
          .collection('schools')
          .doc(_schoolId)
          .collection('announcements')
          .where('status', isEqualTo: 'scheduled')
          .get();

      print('📋 ${scheduledDocs.docs.length} zamanlanmış duyuru bulundu');

      for (var doc in scheduledDocs.docs) {
        final data = doc.data();
        final publishDate = (data['publishDate'] as Timestamp).toDate();

        // Yayınlama zamanı geldiyse
        if (now.isAfter(publishDate) || now.isAtSameMomentAs(publishDate)) {
          print('✅ Duyuru yayınlanıyor: ${data['title']}');

          await doc.reference.update({
            'status': 'published',
            'actualPublishDate': FieldValue.serverTimestamp(),
          });

          // Hatırlatmaları kontrol et ve oluştur (Orijinal veriyi kullanıyoruz)
          await _createReminderAnnouncements(doc.id, data);
        }
      }

      // Hatırlatma zamanı gelmiş duyuruları kontrol et
      await _checkAndSendReminders();
    } catch (e) {
      print('❌ Zamanlanmış duyurular kontrol edilirken hata: $e');
    }
  }

  // Hatırlatma duyuruları oluştur
  Future<void> _createReminderAnnouncements(
    String originalAnnouncementId,
    Map<String, dynamic> originalData,
  ) async {
    try {
      final reminders = originalData['reminders'] as List<dynamic>? ?? [];

      if (reminders.isEmpty) {
        print('ℹ️ Hatırlatma yok');
        return;
      }

      print('🔔 ${reminders.length} hatırlatma kontrol ediliyor...');

      // Mevcut alt hatırlatmaları kontrol et ki mükerrer oluşturmayalım
      final existingRemindersSnapshot = await _firestore
          .collection('schools')
          .doc(_schoolId)
          .collection('announcements')
          .where('originalAnnouncementId', isEqualTo: originalAnnouncementId)
          .where('isReminder', isEqualTo: true)
          .get();

      final existingReminderDates = existingRemindersSnapshot.docs.map((doc) {
        return (doc.data()['publishDate'] as Timestamp).toDate();
      }).toList();

      bool hasNewReminder = false;
      final List<dynamic> updatedRemindersInOriginal = [];

      for (var reminder in reminders) {
        final reminderDate = (reminder['date'] as Timestamp).toDate();
        final isAlreadyCreated = existingReminderDates.any(
          (d) =>
              d.year == reminderDate.year &&
              d.month == reminderDate.month &&
              d.day == reminderDate.day &&
              d.hour == reminderDate.hour &&
              d.minute == reminderDate.minute,
        );

        // Daha önce oluşturulmamışsa hatırlatma duyurusu oluştur
        if (!isAlreadyCreated) {
          final originalTitle = originalData['title'] as String;
          final reminderTitle = originalTitle.startsWith('Hatırlatma - ')
              ? originalTitle
              : 'Hatırlatma - $originalTitle';

          final reminderData = {
            'title': reminderTitle,
            'content': originalData['content'],
            'recipients': originalData['recipients'],
            'publishDate': reminder['date'],
            'publishTime': originalData['publishTime'],
            'sendSms': originalData['sendSms'] ?? false,
            'links': originalData['links'] ?? [],
            'createdAt': FieldValue.serverTimestamp(),
            'createdBy': originalData['createdBy'],
            'creatorName': originalData['creatorName'],
            'isAnonymous': originalData['isAnonymous'] ?? false,
            'status': 'scheduled',
            'schedulePublish': true,
            'isReminder': true,
            'originalAnnouncementId': originalAnnouncementId,
            'readBy': <String>[],
            'termId': originalData['termId'],
            if (originalData['schoolTypeId'] != null)
              'schoolTypeId': originalData['schoolTypeId'],
            'recipientNames': originalData['recipientNames'] ?? {},
          };

          await _firestore
              .collection('schools')
              .doc(_schoolId)
              .collection('announcements')
              .add(reminderData);

          print('✅ Yeni hatırlatma duyurusu oluşturuldu: $reminderTitle');
          updatedRemindersInOriginal.add({
            'date': reminder['date'],
            'sent': true,
          });
          hasNewReminder = true;
        } else {
          updatedRemindersInOriginal.add({
            'date': reminder['date'],
            'sent': true,
          });
        }
      }

      // Orijinal duyurudaki hatırlatmaları "sent: true" olarak işaretle (Sadece yeni bir şey eklendiyse veya durumu güncellemek gerekiyorsa)
      if (hasNewReminder) {
        await _firestore
            .collection('schools')
            .doc(_schoolId)
            .collection('announcements')
            .doc(originalAnnouncementId)
            .update({'reminders': updatedRemindersInOriginal});
      }
    } catch (e) {
      print('❌ Hatırlatma duyuruları oluşturulurken hata: $e');
    }
  }

  // Hatırlatma zamanı gelmiş duyuruları kontrol et ve yayınla
  Future<void> _checkAndSendReminders() async {
    try {
      final now = DateTime.now();

      // Scheduled durumundaki hatırlatma duyurularını al
      final reminderDocs = await _firestore
          .collection('schools')
          .doc(_schoolId)
          .collection('announcements')
          .where('status', isEqualTo: 'scheduled')
          .where('isReminder', isEqualTo: true)
          .get();

      print('🔔 ${reminderDocs.docs.length} zamanlanmış hatırlatma bulundu');

      for (var doc in reminderDocs.docs) {
        final data = doc.data();
        final publishDate = (data['publishDate'] as Timestamp).toDate();

        // Hatırlatma zamanı geldiyse yayınla
        if (now.isAfter(publishDate) || now.isAtSameMomentAs(publishDate)) {
          print('✅ Hatırlatma yayınlanıyor: ${data['title']}');

          await doc.reference.update({
            'status': 'published',
            'actualPublishDate': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      print('❌ Hatırlatmalar kontrol edilirken hata: $e');
    }
  }

  // Scheduled duyuruları getir (Admin için)
  Stream<QuerySnapshot> getScheduledAnnouncements() async* {
    try {
      await _getSchoolInfo();
      if (_schoolId == null) {
        yield* Stream.value(
          await _firestore
              .collection('schools')
              .doc('none')
              .collection('announcements')
              .limit(0)
              .get(),
        );
        return;
      }

      yield* _firestore
          .collection('schools')
          .doc(_schoolId)
          .collection('announcements')
          .where('status', isEqualTo: 'scheduled')
          .orderBy('publishDate', descending: false)
          .snapshots();
    } catch (e) {
      print('Zamanlanmış duyurular alınırken hata: $e');
      yield* Stream.value(
        await _firestore
            .collection('schools')
            .doc('none')
            .collection('announcements')
            .limit(0)
            .get(),
      );
    }
  }

  // Okul türüne göre kullanıcıları getir
  Future<List<Map<String, dynamic>>> getUsersBySchoolType(
    String schoolTypeId,
  ) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return [];

      final email = user.email!;
      final instId = email.split('@')[1].split('.')[0].toUpperCase();

      print(
        '📋 getUsersBySchoolType: instId=$instId, schoolTypeId=$schoolTypeId',
      );

      // Önce okul türü bilgisini al
      final schoolTypeDoc = await _firestore
          .collection('schoolTypes')
          .doc(schoolTypeId)
          .get();

      if (!schoolTypeDoc.exists) {
        print('❌ getUsersBySchoolType: SchoolType document not found');
        return [];
      }

      final schoolTypeName =
          schoolTypeDoc.data()?['schoolTypeName'] ??
          schoolTypeDoc.data()?['typeName'] ??
          '';

      print('📋 getUsersBySchoolType: schoolTypeName=$schoolTypeName');

      List<Map<String, dynamic>> allUsers = [];
      Set<String> addedUserIds = {}; // To avoid duplicates

      // 1. Öğrencileri 'students' koleksiyonundan çek (schoolTypeId'ye göre)
      try {
        final studentsSnapshot = await _firestore
            .collection('students')
            .where('institutionId', isEqualTo: instId)
            .where('schoolTypeId', isEqualTo: schoolTypeId)
            .get();

        print(
          '📋 getUsersBySchoolType: Found ${studentsSnapshot.docs.length} students in students collection',
        );

        for (var doc in studentsSnapshot.docs) {
          if (!addedUserIds.contains(doc.id)) {
            final data = doc.data();
            // Get branch/class name
            final branch =
                data['className'] ?? data['branch'] ?? data['class'] ?? '';
            allUsers.add({
              'id': doc.id,
              'name': data['fullName'] ?? data['name'] ?? 'İsimsiz',
              'role': 'Öğrenci',
              'email': data['email'] ?? '',
              'username': data['studentNumber'] ?? '',
              'branch': branch,
            });
            addedUserIds.add(doc.id);
          }
        }
      } catch (e) {
        print(
          '⚠️ getUsersBySchoolType: Error fetching from students collection: $e',
        );
      }

      // 2. Öğrencileri 'users' koleksiyonundan da çek (role = 'Öğrenci' ve schoolTypeId = schoolTypeId)
      try {
        final usersStudentsSnapshot = await _firestore
            .collection('users')
            .where('institutionId', isEqualTo: instId)
            .where('role', isEqualTo: 'Öğrenci')
            .get();

        // Client-side filter by schoolTypeId since composite index might not exist
        final filteredStudents = usersStudentsSnapshot.docs.where((doc) {
          final data = doc.data();
          final docSchoolType = data['schoolTypeId'] ?? data['schoolType'];
          return docSchoolType == schoolTypeId ||
              docSchoolType == schoolTypeName;
        }).toList();

        print(
          '📋 getUsersBySchoolType: Found ${filteredStudents.length} students in users collection',
        );

        for (var doc in filteredStudents) {
          if (!addedUserIds.contains(doc.id)) {
            final data = doc.data();
            // Get branch/class name
            final branch =
                data['className'] ?? data['branch'] ?? data['class'] ?? '';
            allUsers.add({
              'id': doc.id,
              'name': data['fullName'] ?? data['name'] ?? 'İsimsiz',
              'role': 'Öğrenci',
              'email': data['email'] ?? '',
              'username': data['username'] ?? data['studentNumber'] ?? '',
              'branch': branch,
            });
            addedUserIds.add(doc.id);
          }
        }
      } catch (e) {
        print(
          '⚠️ getUsersBySchoolType: Error fetching students from users collection: $e',
        );
      }

      // 3. Personel ve öğretmenleri ekle (workLocations varsa kontrol et, yoksa dahil et)
      try {
        final allStaffSnapshot = await _firestore
            .collection('users')
            .where('institutionId', isEqualTo: instId)
            .get();

        // Filter staff members: role != 'Öğrenci' and (no workLocations OR workLocations contains this school type)
        final staffDocs = allStaffSnapshot.docs.where((doc) {
          final data = doc.data();
          final role = data['role'] ?? '';

          // Skip students (already added above)
          if (role == 'Öğrenci') return false;

          // Check workLocations if present
          if (data['workLocations'] != null && data['workLocations'] is List) {
            final locations = List<String>.from(data['workLocations']);
            return locations.contains(schoolTypeName) ||
                locations.contains(schoolTypeId);
          }

          // workLocations yoksa tüm personeli dahil et (geriye uyumluluk)
          return true;
        });

        print(
          '📋 getUsersBySchoolType: Found ${staffDocs.length} staff members',
        );

        for (var doc in staffDocs) {
          if (!addedUserIds.contains(doc.id)) {
            final data = doc.data();
            // Get branch/subject for teachers
            final branch =
                data['branch'] ?? data['subject'] ?? data['branş'] ?? '';
            allUsers.add({
              'id': doc.id,
              'name': data['fullName'] ?? data['name'] ?? 'İsimsiz',
              'role': data['role'] ?? data['title'] ?? 'Kullanıcı',
              'email': data['email'] ?? '',
              'username': data['username'] ?? '',
              'branch': branch,
            });
            addedUserIds.add(doc.id);
          }
        }
      } catch (e) {
        print('⚠️ getUsersBySchoolType: Error fetching staff: $e');
      }

      print('✅ getUsersBySchoolType: Total ${allUsers.length} users loaded');
      return allUsers;
    } catch (e) {
      print('❌ Okul türüne göre kullanıcılar alınırken hata: $e');
      return [];
    }
  }

  // Okul türüne göre sınıf seviyelerini getir
  Future<List<Map<String, dynamic>>> getClassLevelsBySchoolType(
    String schoolTypeId,
  ) async {
    try {
      // Okul türü bilgisini al
      final schoolTypeDoc = await _firestore
          .collection('schoolTypes')
          .doc(schoolTypeId)
          .get();

      if (!schoolTypeDoc.exists) return [];

      final data = schoolTypeDoc.data();
      final schoolTypeName = data?['schoolTypeName'] ?? data?['typeName'] ?? '';
      final activeGrades = data?['activeGrades'] as List<dynamic>? ?? [];

      // Sınıf seviyelerini oluştur
      return activeGrades.map((grade) {
        return {
          'id': '${schoolTypeId}_$grade',
          'name': '$grade. Sınıf',
          'schoolType': schoolTypeName,
        };
      }).toList();
    } catch (e) {
      print('Sınıf seviyeleri alınırken hata: $e');
      return [];
    }
  }

  // Okul türüne göre sınıfları getir
  Future<List<Map<String, dynamic>>> getClasses(String schoolTypeId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return [];

      final email = user.email!;
      // EduKN standard pattern: email domain stores institution ID (e.g. user@ABC.edukn.com) -> ABC
      // Actually simpler: we can use the pattern from getAllUsers
      final instId = email.split('@')[1].split('.')[0].toUpperCase();

      final snapshot = await _firestore
          .collection('classes')
          .where('institutionId', isEqualTo: instId)
          .where('schoolTypeId', isEqualTo: schoolTypeId)
          .where('isActive', isEqualTo: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {'id': doc.id, 'name': data['className'] ?? 'İsimsiz Sınıf'};
      }).toList();
    } catch (e) {
      print('Sınıflar alınırken hata: $e');
      return [];
    }
  }

  // Tekrarlayan duyuruları oluştur
  Future<void> _createRepeatedAnnouncements(
    String originalId,
    Map<String, dynamic> data,
    String mode,
    DateTime until,
  ) async {
    try {
      DateTime nextDate = (data['publishDate'] as Timestamp).toDate();
      int count = 0;

      while (count < 24) {
        // Limit to 24 repetitions to avoid infinite loops/too many docs
        if (mode == 'daily') {
          nextDate = nextDate.add(const Duration(days: 1));
        } else if (mode == 'weekly') {
          nextDate = nextDate.add(const Duration(days: 7));
        } else if (mode == 'biweekly') {
          nextDate = nextDate.add(const Duration(days: 14));
        } else if (mode == 'monthly') {
          nextDate = DateTime(
            nextDate.year,
            nextDate.month + 1,
            nextDate.day,
            nextDate.hour,
            nextDate.minute,
          );
        } else {
          break;
        }

        if (nextDate.isAfter(until)) break;

        final repeatedData = Map<String, dynamic>.from(data);
        repeatedData['publishDate'] = Timestamp.fromDate(nextDate);
        repeatedData['status'] = 'scheduled';
        repeatedData['isRepeatedInstance'] = true;
        repeatedData['parentAnnouncementId'] = originalId;
        repeatedData['createdAt'] = FieldValue.serverTimestamp();
        repeatedData.remove('repeatMode'); // Repeated instances don't repeat further
        repeatedData.remove('repeatUntil');

        await _firestore
            .collection('schools')
            .doc(_schoolId)
            .collection('announcements')
            .add(repeatedData);

        count++;
      }
      print('✅ $count adet tekrarlayan duyuru oluşturuldu');
    } catch (e) {
      print('❌ Tekrarlayan duyuru oluşturma hatası: $e');
    }
  }
}
