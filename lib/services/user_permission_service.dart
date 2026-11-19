import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'crypto_service.dart';
import 'role_permission_service.dart';
import '../constants/app_modules.dart';
import '../constants/school_type_modules.dart';
import '../widgets/school_logo.dart';

/// Merkezi kullanıcı yetki yönetim servisi
/// Tüm modüller bu servisi kullanarak kullanıcı verilerini ve yetkilerini alır
class UserPermissionService {
  static Map<String, dynamic>? _cachedUserData;
  static Map<String, dynamic>? get cachedUserData => _cachedUserData;
  static bool _isImpersonating = false;
  static Future<Map<String, dynamic>?>? _loadFuture;
  // resolveInstitutionId sonucunu cache'le — her ekran açılışında Firestore'a gitmemek için
  static String? _cachedInstitutionId;
  // Rol şablonu cache — login sonrası yüklenir
  static Map<String, dynamic>? _cachedRoleTemplate;

  static Map<String, dynamic> _makeJsonSafe(Map<String, dynamic> map) {
    final result = <String, dynamic>{};
    map.forEach((key, value) {
      if (value is Timestamp) {
        result[key] = value.toDate().toIso8601String();
      } else if (value is DateTime) {
        result[key] = value.toIso8601String();
      } else if (value is Map) {
        result[key] = _makeJsonSafe(Map<String, dynamic>.from(value));
      } else if (value is List) {
        result[key] = value.map((e) {
          if (e is Timestamp) return e.toDate().toIso8601String();
          if (e is DateTime) return e.toIso8601String();
          if (e is Map) return _makeJsonSafe(Map<String, dynamic>.from(e));
          return e;
        }).toList();
      } else {
        result[key] = value;
      }
    });
    return result;
  }

  /// Kullanıcı verilerini yükle (normal veya impersonation)
  static Future<Map<String, dynamic>?> loadUserData({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedUserData != null) return _cachedUserData;
    if (!forceRefresh && _loadFuture != null) {
      final result = await _loadFuture!;
      if (result != null) return result;
    }

    // ⚡ Cold Start Hızı: SharedPreferences disk önbelleğinden anında 0 ms'de yükle!
    if (!forceRefresh) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final prefs = await SharedPreferences.getInstance();
          final isImp = prefs.getBool('is_impersonating') ?? false;
          if (!isImp) {
            final cachedJson = prefs.getString('edukn_cached_user_${user.uid}');
            if (cachedJson != null && cachedJson.isNotEmpty) {
              final decoded = json.decode(cachedJson) as Map<String, dynamic>;
              _cachedUserData = decoded;
              _cachedInstitutionId = decoded['institutionId']?.toString();
              if (_cachedRoleTemplate == null) {
                final instId = (_cachedInstitutionId ?? '').trim();
                final uRole = (decoded['role'] ?? '')
                    .toString()
                    .trim()
                    .toLowerCase();
                if (instId.isNotEmpty &&
                    uRole.isNotEmpty &&
                    !_isTopAdmin(uRole)) {
                  await loadAndCacheRoleTemplate(instId, uRole);
                }
              }
              // Arka planda sessizce Firestore'dan doğrula/yenile
              _internalLoadUserData()
                  .then((fresh) {
                    if (fresh != null && !_isImpersonating) {
                      prefs.setString(
                        'edukn_cached_user_${user.uid}',
                        json.encode(_makeJsonSafe(fresh)),
                      );
                    }
                  })
                  .catchError((_) {});
              return _cachedUserData;
            }
          }
        }
      } catch (_) {}
    }

    _loadFuture = _internalLoadUserData();
    final res = await _loadFuture!;
    if (res != null) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final prefs = await SharedPreferences.getInstance();
          final isImp = prefs.getBool('is_impersonating') ?? false;
          if (!isImp) {
            await prefs.setString(
              'edukn_cached_user_${user.uid}',
              json.encode(_makeJsonSafe(res)),
            );
          }
        }
      } catch (_) {}
    }
    return res;
  }

  static Future<Map<String, dynamic>?> _internalLoadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _loadFuture = null;
        return null;
      }

      // Şifreleme anahtarını sunucudan güvenli bir şekilde çek ve yükle
      await CryptoService.init();

      // Impersonation kontrolü
      final prefs = await SharedPreferences.getInstance();
      _isImpersonating = prefs.getBool('is_impersonating') ?? false;
      final impersonatedEmail = prefs.getString('impersonated_user_email');

      print('🔐 UserPermissionService - Kullanıcı verileri yükleniyor...');
      print('   - Impersonation: $_isImpersonating');
      print('   - Email: ${_isImpersonating ? impersonatedEmail : user.email}');

      Map<String, dynamic>? userData;

      if (_isImpersonating &&
          impersonatedEmail != null &&
          impersonatedEmail.isNotEmpty) {
        // Impersonation modu - İmpersonate edilen kullanıcıyı yükle
        print('🎭 Impersonation modu aktif: $impersonatedEmail');

        final impUserQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: impersonatedEmail)
            .limit(1)
            .get();

        if (impUserQuery.docs.isNotEmpty) {
          userData = impUserQuery.docs.first.data();
          print('✅ Impersonated kullanıcı yüklendi: ${userData['fullName']}');
        } else {
          print('❌ Impersonated kullanıcı bulunamadı!');
        }
      } else {
        // Normal mod - Orijinal dokümanı bul ve TEKİL olarak bağla (Asla mükerrer klon açma!)
        print('👤 Normal mod - UID: ${user.uid}, Email: ${user.email}');

        DocumentSnapshot<Map<String, dynamic>>? canonicalDoc;

        // 1. Strateji: authUserId alanı ile eşleşen dokümanı bul
        final authUserQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('authUserId', isEqualTo: user.uid)
            .limit(1)
            .get();

        if (authUserQuery.docs.isNotEmpty) {
          canonicalDoc = authUserQuery.docs.first;
          print(
            '✅ authUserId alanı ile orijinal kullanıcı bulundu: ${canonicalDoc.data()?['fullName']} (ID: ${canonicalDoc.id})',
          );
        }

        // 2. Strateji: googleUid alanı ile ara
        if (canonicalDoc == null) {
          final googleUidQuery = await FirebaseFirestore.instance
              .collection('users')
              .where('googleUid', isEqualTo: user.uid)
              .limit(1)
              .get();
          if (googleUidQuery.docs.isNotEmpty) {
            canonicalDoc = googleUidQuery.docs.first;
            print(
              '✅ googleUid alanı ile orijinal kullanıcı bulundu: ${canonicalDoc.data()?['fullName']} (ID: ${canonicalDoc.id})',
            );
          }
        }

        // 3. Strateji: Doğrudan UID ile doküman kontrolü
        if (canonicalDoc == null) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          if (userDoc.exists) {
            final data = userDoc.data();
            final origId = data?['originalDocId']?.toString();
            if (origId != null && origId.isNotEmpty && origId != user.uid) {
              // Bu eski bir ayna/kopya dokümandır, gerçek asıl dokümanı getir
              final realDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(origId)
                  .get();
              if (realDoc.exists) {
                canonicalDoc = realDoc;
                print(
                  '✅ originalDocId takip edilerek asıl dokümana ulaşıldı: $origId',
                );
                // Kopya dokümanı hemen temizle
                userDoc.reference.delete().catchError((_) {});
              } else {
                canonicalDoc = userDoc;
              }
            } else {
              canonicalDoc = userDoc;
            }
          }
        }

        // 4. Strateji: EduKN e-posta formatı (username@institution.edukn)
        if (canonicalDoc == null &&
            user.email != null &&
            user.email!.contains('@') &&
            user.email!.endsWith('.edukn')) {
          try {
            final parts = user.email!.split('@');
            final uName = parts[0].trim().toLowerCase();
            final hostParts = parts[1].split('.');
            final instId = hostParts[0].trim().toUpperCase();

            print(
              '🔍 eduKN email yapısından username: $uName, inst: $instId ile aranıyor...',
            );
            final usernameQuery = await FirebaseFirestore.instance
                .collection('users')
                .where('institutionId', whereIn: [instId, instId.toLowerCase()])
                .where('username', isEqualTo: uName)
                .limit(1)
                .get();

            if (usernameQuery.docs.isNotEmpty) {
              canonicalDoc = usernameQuery.docs.first;
              print(
                '✅ Username + Kurum ile kullanıcı bulundu: ${canonicalDoc.data()?['fullName']} (ID: ${canonicalDoc.id})',
              );
            } else {
              // Kurum kısıtı olmadan dene
              final uQueryNoInst = await FirebaseFirestore.instance
                  .collection('users')
                  .where('username', isEqualTo: uName)
                  .limit(1)
                  .get();
              if (uQueryNoInst.docs.isNotEmpty) {
                canonicalDoc = uQueryNoInst.docs.first;
                print(
                  '✅ Username ile kullanıcı bulundu: ${canonicalDoc.data()?['fullName']} (ID: ${canonicalDoc.id})',
                );
              }
            }
          } catch (e) {
            print('⚠️ Username bazlı arama hatası: $e');
          }
        }

        // 5. Strateji: Email alanları ile ara (email, corporateEmail, personalEmail)
        if (canonicalDoc == null &&
            user.email != null &&
            user.email!.isNotEmpty) {
          final targetEmail = user.email!.toLowerCase();

          final queries = [
            FirebaseFirestore.instance
                .collection('users')
                .where('email', isEqualTo: targetEmail)
                .get(),
            FirebaseFirestore.instance
                .collection('users')
                .where('corporateEmail', isEqualTo: targetEmail)
                .get(),
            FirebaseFirestore.instance
                .collection('users')
                .where('personalEmail', isEqualTo: targetEmail)
                .get(),
          ];

          final emailResults = await Future.wait(queries);
          for (final snap in emailResults) {
            if (snap.docs.isNotEmpty) {
              // Mümkünse institutionId olanı ve klon olmayanı tercih et
              for (var d in snap.docs) {
                if (d.data()['originalDocId'] == null) {
                  canonicalDoc = d;
                  break;
                }
              }
              canonicalDoc ??= snap.docs.first;
              print(
                '✅ Email ile kullanıcı bulundu: ${canonicalDoc.data()?['fullName']} (ID: ${canonicalDoc.id})',
              );
              break;
            }
          }
        }

        // Orijinal doküman bulunduysa veriyi hazırla ve TEKİL olarak bağla
        if (canonicalDoc != null && canonicalDoc.exists) {
          userData = canonicalDoc.data();
          if (userData != null) {
            userData['id'] = canonicalDoc.id;

            // Orijinal dokümana authUserId & googleUid'yi bağla
            if (userData['authUserId'] != user.uid ||
                userData['googleUid'] != user.uid) {
              userData['authUserId'] = user.uid;
              userData['googleUid'] = user.uid;
              canonicalDoc.reference
                  .update({'authUserId': user.uid, 'googleUid': user.uid})
                  .catchError((e) {
                    print('⚠️ authUserId güncelleme hatası: $e');
                  });
              print(
                '🔗 authUserId orijinal dokümana başarıyla bağlandı: ${canonicalDoc.id}',
              );
            }

            // Eğer /users/{user.uid} şeklinde ayrı bir klon/mükerrer doküman varsa onu otomatik temizle
            if (canonicalDoc.id != user.uid) {
              try {
                final cloneDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .get();
                if (cloneDoc.exists) {
                  await cloneDoc.reference.delete();
                  print(
                    '🧹 Eski mükerrer kopya doküman otomatik silindi: ${user.uid}',
                  );
                }
              } catch (_) {}
            }
          }
        }
      }

      if (userData == null) {
        // Parents koleksiyonunda ara
        print(
          '🔍 Users koleksiyonunda bulunamadı, parents koleksiyonu deneniyor...',
        );
        final parentQuery = await FirebaseFirestore.instance
            .collection('parents')
            .where('username', isEqualTo: user.email?.split('@')[0])
            .limit(1)
            .get();

        if (parentQuery.docs.isNotEmpty) {
          userData = parentQuery.docs.first.data();
          userData['id'] = parentQuery.docs.first.id;
          userData['role'] = 'parent';
          print(
            '✅ Parent olarak bulundu: ${userData['fullName'] ?? userData['name']}',
          );
        }
      }

      if (userData == null) {
        // Eğer hala bulunamadıysa ama bu bir admin ise (Email'den veya ID'den anlayabiliyorsak)
        // Şimdilik null dönüyoruz ama hasModuleAccess içinde null userData = admin yetkisi veriyoruz
        print(
          'ℹ️ Kullanıcı verisi bulunamadı, varsayılan yetkiler kullanılacak.',
        );
      }

      _cachedUserData = userData != null
          ? CryptoService.decryptMap(userData)
          : null;
      if (_cachedUserData != null) {
        final instId =
            (_cachedUserData!['institutionId'] ?? _cachedInstitutionId ?? '')
                .toString()
                .trim();
        final uRole = (_cachedUserData!['role'] ?? _cachedUserData!['title'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (instId.isNotEmpty && uRole.isNotEmpty && !_isTopAdmin(uRole)) {
          await loadAndCacheRoleTemplate(instId, uRole);

          // Eğer kullanıcıya özel yetki (hasCustomPermissions == true) verilmemişse
          // ve Yetki Tanımlama'da bu rol için kayıtlı şablon varsa (veya kullanıcıda eski/eksik izin yapısı varsa),
          // rol şablonundaki güncel yetkileri kullanıcı verisine uygula.
          final existingModPerms =
              _cachedUserData!['modulePermissions'] as Map<String, dynamic>?;
          final hasLegacyPermsOnly = existingModPerms == null ||
              (!existingModPerms.containsKey('mali_isler') &&
                  !existingModPerms.containsKey('sistem_ayarlari') &&
                  !existingModPerms.containsKey('olcme_degerlendirme'));
          final fromFirestore = _cachedRoleTemplate?['_fromFirestore'] == true;

          if (_cachedUserData!['hasCustomPermissions'] != true &&
              (fromFirestore || hasLegacyPermsOnly) &&
              _cachedRoleTemplate != null) {
            final tplApp =
                _cachedRoleTemplate!['appPermissions'] as Map<String, dynamic>?;
            final tplSt =
                _cachedRoleTemplate!['schoolTypePermissions']
                    as Map<String, dynamic>?;
            final tplTp =
                _cachedRoleTemplate!['teacherPermissions']
                    as Map<String, dynamic>?;
            if (tplApp != null) {
              _cachedUserData!['modulePermissions'] = tplApp;
            }
            if (tplSt != null) {
              _cachedUserData!['schoolTypeModulePermissions'] = tplSt;
            }
            if (tplTp != null) {
              _cachedUserData!['teacherModulePermissions'] = tplTp;
            }
            final docId = _cachedUserData!['id']?.toString();
            if (hasLegacyPermsOnly && docId != null && docId.isNotEmpty) {
              FirebaseFirestore.instance
                  .collection('users')
                  .doc(docId)
                  .update({
                    if (tplApp != null) 'modulePermissions': tplApp,
                    if (tplSt != null) 'schoolTypeModulePermissions': tplSt,
                    if (tplTp != null) 'teacherModulePermissions': tplTp,
                  })
                  .catchError((_) {});
            }
          }
        }
      }
      return _cachedUserData;
    } catch (e) {
      print('❌ Kullanıcı verileri yüklenirken hata: $e');
      return null;
    }
  }

  /// Cache'lenmiş kullanıcı verisini al (performans için)
  static Map<String, dynamic>? getCachedUserData() {
    return _cachedUserData;
  }

  /// Institution ID cache'ini dışarıdan ayarla (login sonrası için)
  static void setInstitutionIdCache(String institutionId) {
    if (institutionId.isNotEmpty && institutionId.toUpperCase() != 'GMAIL') {
      _cachedInstitutionId = institutionId;
      print('📌 InstitutionId cache ayarlandı: $institutionId');
    }
  }

  /// Kullanıcı verisi cache'ini dışarıdan ayarla (login sonrası için)
  static void setCachedUserData(Map<String, dynamic>? data) {
    _cachedUserData = data;
    _loadFuture = data != null ? Future.value(data) : null;
  }

  /// Rol şablonu cache'ini ayarla
  static void setRoleTemplateCache(Map<String, dynamic>? template) {
    _cachedRoleTemplate = template;
    print(
      '📌 Rol şablonu cache ayarlandı: ${template != null ? "yüklendi" : "null"}',
    );
  }

  /// Rol şablonunu Firestore'dan yükle ve cache'le
  static Future<void> loadAndCacheRoleTemplate(
    String institutionId,
    String role,
  ) async {
    try {
      final template = await RolePermissionService().loadRoleTemplate(
        institutionId,
        role,
      );
      if (template != null) {
        template['teacherPermissions'] ??=
            RolePermissionService.getDefaultTeacherPermissions(role);
        template['appPermissions'] ??=
            RolePermissionService.getDefaultPermissions(role);
        template['schoolTypePermissions'] ??=
            RolePermissionService.getDefaultSchoolTypePermissions(role);
        template['_fromFirestore'] = true;
        _cachedRoleTemplate = template;
        print('✅ Rol şablonu yüklendi: $role');
      } else {
        // Varsayılan şablonu oluştur
        _cachedRoleTemplate = {
          'roleName': role,
          'appPermissions': RolePermissionService.getDefaultPermissions(role),
          'schoolTypePermissions':
              RolePermissionService.getDefaultSchoolTypePermissions(role),
          'teacherPermissions':
              RolePermissionService.getDefaultTeacherPermissions(role),
        };
        print('ℹ️ Varsayılan rol şablonu kullanıldı: $role');
      }
    } catch (e) {
      print(
        'ℹ️ Rol şablonu Firestore\'dan alınamadı ($e). Varsayılan rol şablonu kullanılıyor: $role',
      );
      _cachedRoleTemplate = {
        'roleName': role,
        'appPermissions': RolePermissionService.getDefaultPermissions(role),
        'schoolTypePermissions':
            RolePermissionService.getDefaultSchoolTypePermissions(role),
        'teacherPermissions':
            RolePermissionService.getDefaultTeacherPermissions(role),
      };
    }
  }

  static Map<String, dynamic>? _resolveEffectiveTeacherPermissions([
    Map<String, dynamic>? user,
  ]) {
    final u = user ?? _cachedUserData;
    final personalTeacher = u?['teacherModulePermissions'];
    if (personalTeacher is Map && personalTeacher.isNotEmpty) {
      return Map<String, dynamic>.from(personalTeacher);
    }
    final roleTeacher = _cachedRoleTemplate?['teacherPermissions'];
    if (roleTeacher is Map) {
      return Map<String, dynamic>.from(roleTeacher);
    }
    return null;
  }

  /// Uygulama Ayarları (Kurum Geneli + Okul Türü Bazlı) modül / alt başlık / 3. seviye açık mı kontrolü
  static bool isAppSettingEnabled(
    Map<String, dynamic>? appSettings,
    String key, {
    String? schoolTypeId,
  }) {
    if (appSettings == null || key.isEmpty) return true;
    final globalDisabled =
        (appSettings['disabledModules'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toSet();
    if (globalDisabled.contains(key)) return false;

    // Üst başlık kapalıysa alt başlık da kapalıdır (örn. a.b.c -> a ve a.b kontrolü)
    final parts = key.split('.');
    if (parts.length >= 2) {
      final isPrefixed = parts[0] == 'st' || parts[0] == 't';
      final modPrefix = isPrefixed && parts.length >= 2
          ? '${parts[0]}.${parts[1]}'
          : parts[0];
      if (globalDisabled.contains(modPrefix)) return false;
      if (isPrefixed && parts.length >= 4) {
        final subPrefix = '${parts[0]}.${parts[1]}.${parts[2]}';
        if (globalDisabled.contains(subPrefix)) return false;
      } else if (!isPrefixed && parts.length >= 3) {
        final subPrefix = '${parts[0]}.${parts[1]}';
        if (globalDisabled.contains(subPrefix)) return false;
      }
    }

    final st = (schoolTypeId ?? '').trim();
    if (st.isNotEmpty) {
      final stMap = appSettings['schoolTypeDisabledModules'];
      if (stMap is Map && stMap[st] is Iterable) {
        final stDisabled = (stMap[st] as Iterable)
            .map((e) => e.toString())
            .toSet();
        if (stDisabled.contains(key)) return false;
        if (parts.length >= 2) {
          final isPrefixed = parts[0] == 'st' || parts[0] == 't';
          final modPrefix = isPrefixed && parts.length >= 2
              ? '${parts[0]}.${parts[1]}'
              : parts[0];
          if (stDisabled.contains(modPrefix)) return false;
          if (isPrefixed && parts.length >= 4) {
            final subPrefix = '${parts[0]}.${parts[1]}.${parts[2]}';
            if (stDisabled.contains(subPrefix)) return false;
          } else if (!isPrefixed && parts.length >= 3) {
            final subPrefix = '${parts[0]}.${parts[1]}';
            if (stDisabled.contains(subPrefix)) return false;
          }
        }
      }
    }
    return true;
  }

  /// Öğretmen modülü yetkisi kontrolü (Kategori, alt modül veya 3. seviye alt işlem)
  static bool hasTeacherModuleAccess(
    String moduleKey, {
    String? subModuleKey,
    String? nestedKey,
  }) {
    final tPerms = _resolveEffectiveTeacherPermissions();
    if (tPerms == null) return true; // Güvenli fallback: açık

    final modData = tPerms[moduleKey];
    if (modData is! Map) return true;

    // Ana modül kapalıysa doğrudan false
    if (modData['enabled'] != true) return false;

    final subPerms = modData['subModules'];
    if (subPerms is Map) {
      if (subModuleKey != null && subPerms.containsKey(subModuleKey)) {
        final subData = subPerms[subModuleKey];
        if (subData is Map && subData['enabled'] != true) {
          return false;
        }
      }
      if (nestedKey != null && subPerms.containsKey(nestedKey)) {
        final nestedData = subPerms[nestedKey];
        if (nestedData is Map) {
          return nestedData['enabled'] == true;
        }
      }
    }

    return true;
  }

  /// Öğretmen modülü yetki seviyesi ('editor' / 'viewer')
  static String getTeacherModuleLevel(
    String moduleKey, {
    String? subModuleKey,
    String? nestedKey,
  }) {
    final tPerms = _resolveEffectiveTeacherPermissions();
    if (tPerms == null) return 'editor';

    final modData = tPerms[moduleKey];
    if (modData is! Map) return 'editor';

    final subPerms = modData['subModules'];
    if (subPerms is Map) {
      if (nestedKey != null && subPerms.containsKey(nestedKey)) {
        final nestedData = subPerms[nestedKey];
        if (nestedData is Map) {
          return (nestedData['level'] ?? modData['level'] ?? 'editor')
              .toString();
        }
      }
      if (subModuleKey != null && subPerms.containsKey(subModuleKey)) {
        final subData = subPerms[subModuleKey];
        if (subData is Map) {
          return (subData['level'] ?? modData['level'] ?? 'editor').toString();
        }
      }
    }

    return (modData['level'] ?? 'editor').toString();
  }

  /// Öğretmen modülünde düzenleme yetkisi var mı?
  static bool canEditTeacherModule(
    String moduleKey, {
    String? subModuleKey,
    String? nestedKey,
  }) {
    return getTeacherModuleLevel(
          moduleKey,
          subModuleKey: subModuleKey,
          nestedKey: nestedKey,
        ) ==
        'editor';
  }

  /// Sınav Yoklama Raporu Alma Yetkisi
  static bool canViewExamReports([Map<String, dynamic>? user]) {
    final u = user ?? _cachedUserData;
    if (u == null) return true;
    final role = (u['role'] as String?)?.toLowerCase() ?? '';
    if (_isTopAdmin(role)) return true;
    final isTeacher =
        role.contains('ogretmen') ||
        role.contains('öğretmen') ||
        role == 'teacher';
    if (!isTeacher) return true;
    final tPerms = _resolveEffectiveTeacherPermissions(u);
    final subPerm = tPerms?['araclar']?['subModules']?['sinav_raporu_alma'];
    if (subPerm is Map && subPerm['enabled'] == true) return true;
    return false;
  }

  /// Sınavı Tamamlama / Pasife Alma Yetkisi
  static bool canCompleteExam([Map<String, dynamic>? user]) {
    final u = user ?? _cachedUserData;
    if (u == null) return true;
    final role = (u['role'] as String?)?.toLowerCase() ?? '';
    if (_isTopAdmin(role)) return true;
    final isTeacher =
        role.contains('ogretmen') ||
        role.contains('öğretmen') ||
        role == 'teacher';
    if (!isTeacher) return true;
    final tPerms = _resolveEffectiveTeacherPermissions(u);
    final subPerm = tPerms?['araclar']?['subModules']?['sinav_tamamlama'];
    if (subPerm is Map && subPerm['enabled'] == true) return true;
    return false;
  }

  /// Sınav Gözetmenliklerini Yayınlama Yetkisi
  static bool canPublishExam([Map<String, dynamic>? user]) {
    final u = user ?? _cachedUserData;
    if (u == null) return true;
    final role = (u['role'] as String?)?.toLowerCase() ?? '';
    if (_isTopAdmin(role)) return true;
    final isTeacher =
        role.contains('ogretmen') ||
        role.contains('öğretmen') ||
        role == 'teacher';
    if (!isTeacher) return true;
    final tPerms = _resolveEffectiveTeacherPermissions(u);
    final subPerm = tPerms?['araclar']?['subModules']?['sinav_yayinlama'];
    if (subPerm is Map && subPerm['enabled'] == true) return true;
    final stSubPerm =
        (u['schoolTypeModulePermissions']
            as Map?)?['araclar']?['subModules']?['sinav_yayinlama'];
    if (stSubPerm is Map && stSubPerm['enabled'] == true) return true;
    return false;
  }

  /// Yeni Sınav ve Gözetmenlik Planı Hazırlama / Düzenleme Yetkisi
  static bool canCreateExamPlan([Map<String, dynamic>? user]) {
    final u = user ?? _cachedUserData;
    if (u == null) return true;
    final role = (u['role'] as String?)?.toLowerCase() ?? '';
    if (_isTopAdmin(role)) return true;
    final isTeacher =
        role.contains('ogretmen') ||
        role.contains('öğretmen') ||
        role == 'teacher';
    if (isTeacher) {
      final tPerms = _resolveEffectiveTeacherPermissions(u);
      final subPerm =
          tPerms?['araclar']?['subModules']?['sinav_plan_olusturma'];
      if (subPerm is Map && subPerm['enabled'] == true) return true;
      final stSubPerm =
          (u['schoolTypeModulePermissions']
              as Map?)?['araclar']?['subModules']?['sinav_plan_olusturma'];
      if (stSubPerm is Map && stSubPerm['enabled'] == true) return true;
      return false;
    }

    // İdare / özel görev rolleri için şablon veya kişisel modül yetkisine bak
    final effectivePerm = _getEffectiveModulePerm('araclar', u);
    if (effectivePerm != null) {
      final subModules = effectivePerm['subModules'] as Map<String, dynamic>?;
      if (subModules != null &&
          subModules.containsKey('sinav_plan_olusturma')) {
        final perm = subModules['sinav_plan_olusturma'];
        if (perm is Map) {
          if (perm['enabled'] == false) return false;
          final level = perm['level']?.toString();
          if (level == 'viewer') return false;
        }
      }
    }
    return true;
  }

  /// Cache'lenmiş rol şablonunu al
  static Map<String, dynamic>? getCachedRoleTemplate() => _cachedRoleTemplate;

  /// Cache'i temizle (logout veya impersonation değişikliğinde)
  static void clearCache() {
    _cachedUserData = null;
    _cachedInstitutionId = null;
    _cachedRoleTemplate = null;
    _isImpersonating = false;
    _loadFuture = null;
    CryptoService.clearCache();
    SchoolLogoService.clear();
  }

  // ─── Yardımcı: Rol kontrolü ───
  static bool _isTopAdmin(String role) {
    return role == 'admin' ||
        role == 'genel_mudur' ||
        role == 'genel müdür' ||
        role == 'genel mudur';
  }

  static Map<String, dynamic>? _normalizePermEntry(dynamic rawPerm) {
    if (rawPerm is! Map) return null;
    final normalized = Map<String, dynamic>.from(rawPerm);
    if (!normalized.containsKey('enabled') &&
        normalized.containsKey('level') &&
        normalized['level'] != null) {
      normalized['enabled'] = true;
    }
    if (normalized['subModules'] is Map) {
      final subs = Map<String, dynamic>.from(normalized['subModules']);
      subs.forEach((subKey, subVal) {
        if (subVal is Map) {
          final subNorm = Map<String, dynamic>.from(subVal);
          if (!subNorm.containsKey('enabled') &&
              subNorm.containsKey('level') &&
              subNorm['level'] != null) {
            subNorm['enabled'] = true;
          }
          subs[subKey] = subNorm;
        }
      });
      normalized['subModules'] = subs;
    }
    return normalized;
  }

  static bool _isLegacyPersonalPerms(Map<String, dynamic>? personalPerms) {
    if (personalPerms == null || personalPerms.isEmpty) return true;
    // Eski StaffFormScreen yalnızca 'genel_duyurular', 'okul_turleri', 'ogrenci_kayit' vb. yazıyordu
    return !personalPerms.containsKey('mali_isler') &&
        !personalPerms.containsKey('sistem_ayarlari') &&
        !personalPerms.containsKey('olcme_degerlendirme') &&
        !personalPerms.containsKey('egitim');
  }

  /// Genel Kurum (AppModules) yetkisini getirir (Okul Türü key'leri ile çakışmaz)
  static Map<String, dynamic>? _getEffectiveAppModulePerm(
    String moduleKey,
    Map<String, dynamic>? userData,
  ) {
    final u = userData ?? _cachedUserData;
    final hasCustom = u?['hasCustomPermissions'] == true;
    final fromFirestoreTemplate =
        _cachedRoleTemplate != null &&
        _cachedRoleTemplate!['_fromFirestore'] == true;

    // 1. Kullanıcıya özel izin atanmamışsa ve Firestore'da rol şablonu varsa şablon önceliklidir
    if (!hasCustom && fromFirestoreTemplate) {
      final templatePerms =
          _cachedRoleTemplate!['appPermissions'] as Map<String, dynamic>?;
      if (templatePerms != null && templatePerms.containsKey(moduleKey)) {
        final norm = _normalizePermEntry(templatePerms[moduleKey]);
        if (norm != null) return norm;
      }
    }

    // 2. Kişisel modulePermissions (eski/legacy format değilse)
    final personalPerms = u?['modulePermissions'] as Map<String, dynamic>?;
    if (personalPerms != null &&
        personalPerms.isNotEmpty &&
        !_isLegacyPersonalPerms(personalPerms)) {
      if (personalPerms.containsKey(moduleKey)) {
        return _normalizePermEntry(personalPerms[moduleKey]);
      }
      return null;
    }

    // 3. Rol şablonu (varsayılan veya Firestore)
    if (_cachedRoleTemplate != null) {
      final templatePerms =
          _cachedRoleTemplate!['appPermissions'] as Map<String, dynamic>?;
      if (templatePerms != null && templatePerms.containsKey(moduleKey)) {
        return _normalizePermEntry(templatePerms[moduleKey]);
      }
    }

    // 4. Fallback: Kullanıcının rolüne göre varsayılan izin
    final role = (u?['role'] ?? u?['title'] ?? '').toString().trim().toLowerCase();
    if (role.isNotEmpty) {
      final defPerms = RolePermissionService.getDefaultPermissions(role);
      if (defPerms.containsKey(moduleKey)) {
        return _normalizePermEntry(defPerms[moduleKey]);
      }
    }

    return null;
  }

  /// Okul Türü İçi (SchoolTypeModules) yetkisini getirir (Genel Kurum key'leri ile çakışmaz)
  static Map<String, dynamic>? _getEffectiveSchoolTypeModulePerm(
    String stModuleKey,
    Map<String, dynamic>? userData,
  ) {
    final u = userData ?? _cachedUserData;
    final hasCustom = u?['hasCustomPermissions'] == true;
    final fromFirestoreTemplate =
        _cachedRoleTemplate != null &&
        _cachedRoleTemplate!['_fromFirestore'] == true;

    // 1. Kullanıcıya özel izin atanmamışsa ve Firestore'da rol şablonu varsa şablon önceliklidir
    if (!hasCustom && fromFirestoreTemplate) {
      final stTemplatePerms =
          _cachedRoleTemplate!['schoolTypePermissions']
              as Map<String, dynamic>?;
      if (stTemplatePerms != null && stTemplatePerms.containsKey(stModuleKey)) {
        final norm = _normalizePermEntry(stTemplatePerms[stModuleKey]);
        if (norm != null) return norm;
      }
    }

    // 2. Kişisel schoolTypeModulePermissions
    final schoolTypePerms =
        u?['schoolTypeModulePermissions'] as Map<String, dynamic>?;
    if (schoolTypePerms != null && schoolTypePerms.isNotEmpty) {
      if (schoolTypePerms.containsKey(stModuleKey)) {
        return _normalizePermEntry(schoolTypePerms[stModuleKey]);
      }
      return null;
    }

    // 3. Rol şablonu
    if (_cachedRoleTemplate != null) {
      final stTemplatePerms =
          _cachedRoleTemplate!['schoolTypePermissions']
              as Map<String, dynamic>?;
      if (stTemplatePerms != null && stTemplatePerms.containsKey(stModuleKey)) {
        return _normalizePermEntry(stTemplatePerms[stModuleKey]);
      }
    }

    // 4. Fallback: Kullanıcının rolüne göre varsayılan okul türü izni
    final role = (u?['role'] ?? u?['title'] ?? '').toString().trim().toLowerCase();
    if (role.isNotEmpty) {
      final defStPerms =
          RolePermissionService.getDefaultSchoolTypePermissions(role);
      if (defStPerms.containsKey(stModuleKey)) {
        return _normalizePermEntry(defStPerms[stModuleKey]);
      }
    }

    return null;
  }

  /// Modül yetkisini önce kişisel izinlerden, yoksa rol şablonundan kontrol et
  static Map<String, dynamic>? _getEffectiveModulePerm(
    String moduleKey,
    Map<String, dynamic>? userData,
  ) {
    if (AppModules.allModuleKeys.contains(moduleKey)) {
      return _getEffectiveAppModulePerm(moduleKey, userData);
    }
    if (SchoolTypeModules.allModuleKeys.contains(moduleKey)) {
      return _getEffectiveSchoolTypeModulePerm(moduleKey, userData);
    }
    return _getEffectiveAppModulePerm(moduleKey, userData) ??
        _getEffectiveSchoolTypeModulePerm(moduleKey, userData);
  }

  /// Belirli bir modüle erişim yetkisi var mı? (Genel Kurum Modülleri)
  static bool hasModuleAccess(
    String moduleKey,
    Map<String, dynamic>? userData,
  ) {
    if (userData == null && _cachedUserData == null) return true;
    final u = userData ?? _cachedUserData;
    if (u == null) return true;

    final role = (u['role'] as String?)?.toLowerCase() ?? '';
    if (_isTopAdmin(role)) return true;

    final effectivePerm = _getEffectiveModulePerm(moduleKey, u);

    if (effectivePerm != null) {
      if (effectivePerm['enabled'] == true) return true;

      final subModules = effectivePerm['subModules'] as Map<String, dynamic>?;
      if (subModules != null) {
        for (var sub in subModules.values) {
          if (sub is Map && sub['enabled'] == true) return true;
        }
      }
      return false;
    }

    return false;
  }

  /// Belirli bir modülde düzenleme yetkisi var mı?
  static bool canEdit(String moduleKey, Map<String, dynamic>? userData) {
    if (userData == null && _cachedUserData == null) return true;
    final u = userData ?? _cachedUserData;
    if (u == null) return true;

    final role = (u['role'] as String?)?.toLowerCase() ?? '';
    if (_isTopAdmin(role)) return true;

    final effectivePerm = _getEffectiveModulePerm(moduleKey, u);

    if (effectivePerm != null) {
      final level = effectivePerm['level']?.toString();
      if (effectivePerm['enabled'] == true &&
          (level == 'editor' || level == 'admin')) {
        return true;
      }
      // Ana modül viewer olsa bile alt modüllerden biri editor ise kontrol et
      final subModules = effectivePerm['subModules'] as Map<String, dynamic>?;
      if (subModules != null) {
        for (var sub in subModules.values) {
          if (sub is Map &&
              sub['enabled'] == true &&
              (sub['level'] == 'editor' || sub['level'] == 'admin')) {
            return true;
          }
        }
      }
      return false; // viewer
    }

    return false;
  }

  static String _normalizeAppSubKey(String moduleKey, String subModuleKey) {
    if (moduleKey == 'sistem_ayarlari' &&
        subModuleKey == 'kullanici_yonetimi') {
      return 'kullanici_yetkilendirme';
    }
    if (moduleKey == 'olcme_degerlendirme') {
      if (subModuleKey == 'tanimlar') return 'degerlendirme_tanim';
      if (subModuleKey == 'sinavlar') return 'aktif_sinavlar';
      if (subModuleKey == 'raporlar') return 'toplu_raporlar';
    }
    if (moduleKey == 'rehberlik') {
      if (subModuleKey == 'talepler' || subModuleKey == 'gorusme_kayitlari') {
        return 'gorusme_islemleri';
      }
      if (subModuleKey == 'rehberlik_testleri') return 'envanter_anket';
    }
    return subModuleKey;
  }

  /// Belirli bir alt modüle (veya 3. seviye alt işleme) erişim yetkisi var mı?
  static bool hasSubModuleAccess(
    String moduleKey,
    String subModuleKey,
    Map<String, dynamic>? userData, {
    String? nestedKey,
  }) {
    if (userData == null && _cachedUserData == null) return true;
    final u = userData ?? _cachedUserData;
    if (u == null) return true;

    final role = (u['role'] as String?)?.toLowerCase() ?? '';
    if (_isTopAdmin(role)) return true;

    final normSub = _normalizeAppSubKey(moduleKey, subModuleKey);
    final effectivePerm = _getEffectiveModulePerm(moduleKey, u);

    if (effectivePerm != null) {
      final subModules = effectivePerm['subModules'] as Map<String, dynamic>?;
      final targetSub = (subModules != null && subModules.containsKey(normSub))
          ? normSub
          : subModuleKey;

      // Ana modül kapalı ve hiçbir alt modül açık değilse erişim yok
      if (effectivePerm['enabled'] != true) {
        if (subModules == null) return false;
        final subPerm = subModules[targetSub];
        if (subPerm is! Map || subPerm['enabled'] != true) return false;
      }

      if (subModules != null && subModules.isNotEmpty) {
        if (subModules.containsKey(targetSub)) {
          final subPerm = subModules[targetSub];
          if (subPerm is Map && subPerm['enabled'] != true) return false;
        }
        if (nestedKey != null && subModules.containsKey(nestedKey)) {
          final nestedPerm = subModules[nestedKey];
          if (nestedPerm is Map) return nestedPerm['enabled'] == true;
        }
        if (subModules.containsKey(targetSub)) {
          final subPerm = subModules[targetSub];
          if (subPerm is Map) return subPerm['enabled'] == true;
        }
        // Tanımlı bir alt modül anahtarıysa ama map'te yoksa false dön
        final modInfo = AppModules.getModule(moduleKey);
        if (modInfo != null &&
            (modInfo.allSubAndNestedModules.containsKey(normSub) ||
                modInfo.allSubAndNestedModules.containsKey(subModuleKey))) {
          return false;
        }
      }
      return effectivePerm['enabled'] == true;
    }

    return false;
  }

  /// Belirli bir alt modülde (veya 3. seviye alt işlemde) düzenleme yetkisi var mı?
  static bool canEditSubModule(
    String moduleKey,
    String subModuleKey,
    Map<String, dynamic>? userData, {
    String? nestedKey,
  }) {
    if (userData == null && _cachedUserData == null) return true;
    final u = userData ?? _cachedUserData;
    if (u == null) return true;

    final role = (u['role'] as String?)?.toLowerCase() ?? '';
    if (_isTopAdmin(role)) return true;

    if (!hasSubModuleAccess(moduleKey, subModuleKey, u, nestedKey: nestedKey)) {
      return false;
    }

    final normSub = _normalizeAppSubKey(moduleKey, subModuleKey);
    final effectivePerm = _getEffectiveModulePerm(moduleKey, u);

    if (effectivePerm != null) {
      final subModules = effectivePerm['subModules'] as Map<String, dynamic>?;
      if (subModules != null) {
        if (nestedKey != null && subModules.containsKey(nestedKey)) {
          final nestedPerm = subModules[nestedKey];
          if (nestedPerm is Map) {
            if (nestedPerm['enabled'] != true) return false;
            final nLevel = nestedPerm['level']?.toString();
            return nLevel == 'editor' || nLevel == 'admin';
          }
        }
        final targetSub = subModules.containsKey(normSub)
            ? normSub
            : subModuleKey;
        if (subModules.containsKey(targetSub)) {
          final subPerm = subModules[targetSub];
          if (subPerm is Map) {
            final level = subPerm['level']?.toString();
            if (level == 'editor' || level == 'admin') return true;
            return false; // viewer
          }
        }
      }
      final level = effectivePerm['level']?.toString();
      if (level == 'editor' || level == 'admin') return true;
      return false;
    }

    return false;
  }

  // ─── Okul Türü İçi (SchoolTypeModules) Yetki Kontrolleri ───

  /// Okul türü alt başlık anahtarlarının UI ↔ `SchoolTypeModules` eşleştirmesi (dışarıdan erişim).
  static String normalizeSchoolTypeSubKey(String stSubKey) =>
      _normalizeStSubKey(stSubKey);

  static String _normalizeStSubKey(String stSubKey) {
    switch (stSubKey) {
      case 'sube_ders_programi':
        return 'sube_programi';
      case 'ogretmen_ders_programi':
        return 'ogretmen_programi';
      case 'kazanim_takip':
        return 'kazanimlar';
      case 'anket_islemleri':
        return 'anketler';
      case 'etut_islemleri':
        return 'etutler';
      case 'rehberlik_ajandasi':
        return 'pdr_ajanda';
      case 'evrak_otomasyon':
        return 'evrak_sablon';
      case 'gezi_gorevlendirmeleri':
        return 'gezi_gorev';
      case 'proje_gorevlendirmeleri':
        return 'proje_gorev';
      case 'nobet_cizelgesi':
        return 'nobet_islemleri';
      case 'envanter':
        return 'envanter_takibi';
      case 'gelisim_istatistikleri':
        return 'gelisim_istatistik';
      case 'kullanici_yetkilendirme':
        return 'kullanici_yetki';
      default:
        return stSubKey;
    }
  }

  /// Okul Türü modül/alt modülünün Genel Kurum (AppModules) karşılığını döner
  static (String appModKey, String? appSubKey)? _mapStToAppModule(
    String stModuleKey, [
    String? stSubKey,
  ]) {
    final normSub = stSubKey != null ? _normalizeStSubKey(stSubKey) : null;
    switch (stModuleKey) {
      case 'kayit':
      case 'ogrenci_personel':
        if (normSub == 'on_kayit') return ('egitim', 'on_kayit');
        if (normSub == 'ogrenci_listesi' || normSub == 'ogrenci_kaydi') {
          return ('egitim', 'ogrenci_kaydi');
        }
        if (normSub == 'personel_listesi') {
          return ('insan_kaynaklari', 'personel_bilgi');
        }
        if (normSub == 'sube_listesi') {
          return ('egitim', 'sinif_sube_tanimlari');
        }
        if (normSub == 'ders_listesi') return ('egitim', 'ders_tanimlari');
        if (normSub == 'kurs_listesi') return ('egitim', 'kurs_grup_tanimlari');
        if (normSub == 'kulup_listesi') return ('egitim', 'kulup_tanimlari');
        if (normSub == 'derslik_listesi') {
          return ('egitim', 'derslik_tanimlari');
        }
        if (normSub == 'kitap_listesi') return ('egitim', 'kitap_tanimlari');
        return ('egitim', null);
      case 'egitim':
        if (normSub == 'gunluk_rapor') {
          return ('egitim', 'gunluk_rapor_isleyis');
        }
        if (normSub == 'calisma_takvimi') return ('egitim', 'calisma_takvimi');
        if (normSub == 'ders_saatleri') return ('egitim', 'ders_saatleri');
        if (normSub == 'ders_programi') {
          return ('egitim', 'haftalik_ders_programi');
        }
        if (normSub == 'sube_programi') {
          return ('egitim', 'sube_ders_programi');
        }
        if (normSub == 'ogretmen_programi') {
          return ('egitim', 'ogretmen_ders_programi');
        }
        if (normSub == 'kazanimlar') return ('egitim', 'kazanim_takip');
        if (normSub == 'yoklama_girisi') return ('egitim', 'yoklama_girisi');
        if (normSub == 'odev_tanimlama') return ('egitim', 'odev_islemleri');
        if (normSub == 'anketler') return ('egitim', 'anket_islemleri');
        if (normSub == 'etutler') return ('egitim', 'etut_islemleri');
        return ('egitim', normSub);
      case 'rehberlik':
        if (normSub == 'portfolyo') return ('rehberlik', 'ogrenci_portfolyosu');
        if (normSub == 'talepler') return ('rehberlik', 'gorusme_talepleri');
        if (normSub == 'gorusmeler') {
          return ('rehberlik', 'rehberlik_gorusmeleri');
        }
        if (normSub == 'toplu_gozlem') return ('rehberlik', 'toplu_gozlem');
        if (normSub == 'mentor_calismalari') {
          return ('rehberlik', 'mentor_calismalari');
        }
        if (normSub == 'pdr_ajanda') {
          return ('rehberlik', 'rehberlik_ajandasi');
        }
        if (normSub == 'envanterler') {
          return ('rehberlik', 'envanter_tanimlama');
        }
        if (normSub == 'gelisim_raporlari') {
          return ('rehberlik', 'karne_gelisim');
        }
        if (normSub == 'calisma_programi') {
          return ('rehberlik', 'calisma_programi');
        }
        return ('rehberlik', normSub);
      case 'olcme':
        if (normSub == 'tanimlar') {
          return ('olcme_degerlendirme', 'sinav_turu_tanimlari');
        }
        if (normSub == 'raporlar') {
          return ('olcme_degerlendirme', 'toplu_raporlar');
        }
        if (normSub == 'denemeler') {
          return ('olcme_degerlendirme', 'aktif_sinavlar');
        }
        if (normSub == 'sinavlar') {
          return ('olcme_degerlendirme', 'yazili_sinavlar');
        }
        if (normSub == 'hata_kitapcigi') {
          return ('olcme_degerlendirme', 'hata_kitapcigi');
        }
        if (normSub == 'fokus_kitap') {
          return ('olcme_degerlendirme', 'fokus_kitap');
        }
        if (normSub == 'soru_havuzu') {
          return ('olcme_degerlendirme', 'soru_havuzu');
        }
        if (normSub == 'optik_okuma') {
          return ('olcme_degerlendirme', 'optik_okuma');
        }
        if (normSub == 'sinav_gorevlendirme') {
          return ('olcme_degerlendirme', 'sinav_gorevlendirme');
        }
        if (normSub == 'merkezi_deneme_raporlari') {
          return ('olcme_degerlendirme', 'merkezi_deneme_raporlari');
        }
        return ('olcme_degerlendirme', normSub);
      case 'araclar':
        if (normSub == 'sinif_ici_yonetim') {
          return ('egitim', 'sinif_ici_yonetim');
        }
        if (normSub == 'sinav_gozetmenlik') {
          return ('olcme_degerlendirme', 'sinav_gorevlendirme');
        }
        if (normSub == 'akademik_olcme') {
          return ('olcme_degerlendirme', 'aktif_sinavlar');
        }
        if (normSub == 'evrak_sablon') return ('egitim', 'evrak_otomasyon');
        if (normSub == 'ogrenci_hareket_takip') {
          return ('egitim', 'ogrenci_hareket_takip');
        }
        if (normSub == 'online_hizmetler') return ('online_hizmetler', null);
        if (normSub == 'notlarim') return ('egitim', 'notlarim');
        return ('egitim', null);
      case 'gorev':
        if (normSub == 'todo_list') return ('egitim', 'todo_list');
        if (normSub == 'izin_yonetimi') {
          return ('insan_kaynaklari', 'izin_yonetimi');
        }
        if (normSub == 'gecici_ogretmen') {
          return ('egitim', 'gecici_ogretmen');
        }
        if (normSub == 'nobet_islemleri') return ('egitim', 'nobet_yonetimi');
        if (normSub == 'gezi_gorev') return ('egitim', 'gezi_takip');
        if (normSub == 'proje_gorev') {
          return ('egitim', 'proje_gorevlendirmeleri');
        }
        return ('egitim', null);
      case 'destek':
        if (normSub == 'yemekhane') return ('hizmetler', 'yemekhane_islemleri');
        if (normSub == 'servis' || normSub == 'ulasilim_servis') {
          return ('hizmetler', 'servis_islemleri');
        }
        if (normSub == 'saglik') return ('hizmetler', 'saglik_islemleri');
        if (normSub == 'kutuphane') {
          return ('hizmetler', 'kutuphane_islemleri');
        }
        if (normSub == 'temizlik') return ('hizmetler', 'temizlik_islemleri');
        if (normSub == 'envanter_takibi') {
          return ('hizmetler', 'envanter_takibi');
        }
        if (normSub == 'depo_satin_alma') {
          return ('hizmetler', 'depo_satin_alma');
        }
        if (normSub == 'guvenlik') return ('hizmetler', 'guvenlik_kapi');
        if (normSub == 'satin_alma') {
          return ('hizmetler', 'satin_alma_islemleri');
        }
        return ('hizmetler', null);
      case 'haberlesme':
        if (normSub == 'duyurular' || normSub == 'duyuru_islemleri') {
          return ('haberlesme', 'genel_duyurular');
        }
        if (normSub == 'sosyal_medya') return ('haberlesme', 'sosyal_medya');
        if (normSub == 'mesajlar') return ('haberlesme', 'mesajlar');
        return ('haberlesme', normSub);
      case 'raporlar':
        if (normSub == 'yoklama_raporlari' || normSub == 'yoklama_istatistik') {
          return ('egitim', 'yoklama_girisi');
        }
        if (normSub == 'odev_raporlari') return ('egitim', 'odev_islemleri');
        if (normSub == 'olcme_raporlari' || normSub == 'akademik_raporlar') {
          return ('olcme_degerlendirme', 'toplu_raporlar');
        }
        if (normSub == 'gelisim_istatistik') {
          return ('rehberlik', 'karne_gelisim');
        }
        return ('olcme_degerlendirme', null);
      case 'magaza':
        return ('magaza', normSub);
      case 'kantin':
        return ('kantin', normSub);
      case 'ayarlar':
        if (normSub == 'yetki_tanimlama') {
          return ('sistem_ayarlari', 'yetki_tanimlama');
        }
        if (normSub == 'kullanici_yetki') {
          return ('sistem_ayarlari', 'kullanici_yetkilendirme');
        }
        if (normSub == 'uygulama_ayarlari') {
          return ('sistem_ayarlari', 'uygulama_ayarlari');
        }
        if (normSub == 'okul_bilgileri') {
          return ('sistem_ayarlari', 'okul_bilgileri');
        }
        return ('sistem_ayarlari', normSub);
      default:
        return null;
    }
  }

  /// Kullanıcının HERHANGİ bir Okul Türü İçi modüle doğrudan (`schoolTypePermissions`) erişimi tanımlı mı?
  static bool hasAnyDirectSchoolTypeModuleAccess([
    Map<String, dynamic>? userData,
  ]) {
    final u = userData ?? _cachedUserData;
    if (u == null) return false;

    final role = (u['role'] as String?)?.toLowerCase() ?? '';
    if (_isTopAdmin(role)) return true;

    for (final stKey in SchoolTypeModules.allModuleKeys) {
      final perm = _getEffectiveSchoolTypeModulePerm(stKey, u);
      if (perm != null) {
        if (perm['enabled'] == true) return true;
        final subs = perm['subModules'] as Map<String, dynamic>?;
        if (subs != null) {
          for (final sub in subs.values) {
            if (sub is Map && sub['enabled'] == true) return true;
          }
        }
      }
    }
    return false;
  }

  /// Kullanıcının Okul Türü İçi belirli bir modüle erişimi var mı?
  static bool hasSchoolTypeModuleAccess(
    String stModuleKey, [
    Map<String, dynamic>? userData,
  ]) {
    final u = userData ?? _cachedUserData;
    if (u == null) return true;

    final role = (u['role'] as String?)?.toLowerCase() ?? '';
    if (_isTopAdmin(role)) return true;

    // Eğer kullanıcı için Okul Türü İçi modüllerden en az biri açılmışsa doğrudan Okul Türü yetkilerine bak
    if (hasAnyDirectSchoolTypeModuleAccess(u)) {
      final perm = _getEffectiveSchoolTypeModulePerm(stModuleKey, u);
      if (perm == null) return false;
      if (perm['enabled'] == true) return true;
      final subs = perm['subModules'] as Map<String, dynamic>?;
      if (subs != null) {
        for (final sub in subs.values) {
          if (sub is Map && sub['enabled'] == true) return true;
        }
      }
      return false;
    }

    // Eğer Okul Türü İçi sekmesinde hiçbir modül açılmamış ama Genel Kurum sekmesinde açılmışsa,
    // Genel Kurum'daki karşılık gelen modül/alt modül yetkilerini baz al
    if (hasAnyMainModuleAccess(u)) {
      final modInfo = SchoolTypeModules.getModule(stModuleKey);
      if (modInfo != null) {
        for (final subKey in modInfo.subModules.keys) {
          if (hasSchoolTypeSubModuleAccess(stModuleKey, subKey, u)) {
            return true;
          }
        }
      }
      final mapped = _mapStToAppModule(stModuleKey);
      if (mapped != null) {
        return hasModuleAccess(mapped.$1, u);
      }
    }

    return false;
  }

  /// Kullanıcının Okul Türü İçi belirli bir alt modüle erişimi var mı?
  static bool hasSchoolTypeSubModuleAccess(
    String stModuleKey,
    String stSubKey, [
    Map<String, dynamic>? userData,
    String? nestedKey,
  ]) {
    final u = userData ?? _cachedUserData;
    if (u == null) return true;

    final role = (u['role'] as String?)?.toLowerCase() ?? '';
    if (_isTopAdmin(role)) return true;

    final normSub = _normalizeStSubKey(stSubKey);

    if (hasAnyDirectSchoolTypeModuleAccess(u)) {
      final perm = _getEffectiveSchoolTypeModulePerm(stModuleKey, u);
      if (perm == null) return false;
      final subModules = perm['subModules'] as Map<String, dynamic>?;
      if (perm['enabled'] != true) {
        if (subModules == null) return false;
        final sp = subModules[normSub] ?? subModules[stSubKey];
        if (sp is! Map || sp['enabled'] != true) return false;
      }
      if (subModules != null && subModules.isNotEmpty) {
        final targetSub = subModules.containsKey(normSub) ? normSub : stSubKey;
        if (subModules.containsKey(targetSub)) {
          final sp = subModules[targetSub];
          if (sp is Map && sp['enabled'] != true) return false;
        }
        if (nestedKey != null && subModules.containsKey(nestedKey)) {
          final np = subModules[nestedKey];
          if (np is Map) return np['enabled'] == true;
        }
        if (subModules.containsKey(targetSub)) {
          final sp = subModules[targetSub];
          if (sp is Map) return sp['enabled'] == true;
        }
        final modInfo = SchoolTypeModules.getModule(stModuleKey);
        if (modInfo != null &&
            modInfo.allSubAndNestedModules.containsKey(normSub)) {
          return false;
        }
      }
      return perm['enabled'] == true;
    }

    // Fallback: Genel Kurum sekmesindeki karşılığına bak
    if (hasAnyMainModuleAccess(u)) {
      final mapped = _mapStToAppModule(stModuleKey, normSub);
      if (mapped != null) {
        if (mapped.$2 != null) {
          return hasSubModuleAccess(
            mapped.$1,
            mapped.$2!,
            u,
            nestedKey: nestedKey,
          );
        }
        return hasModuleAccess(mapped.$1, u);
      }
    }

    return false;
  }

  /// Kullanıcının Okul Türü İçi belirli bir modülde düzenleme (editor) yetkisi var mı?
  static bool canEditSchoolTypeModule(
    String stModuleKey, [
    Map<String, dynamic>? userData,
  ]) {
    final u = userData ?? _cachedUserData;
    if (u == null) return true;

    final role = (u['role'] as String?)?.toLowerCase() ?? '';
    if (_isTopAdmin(role)) return true;

    if (!hasSchoolTypeModuleAccess(stModuleKey, u)) return false;

    if (hasAnyDirectSchoolTypeModuleAccess(u)) {
      final perm = _getEffectiveSchoolTypeModulePerm(stModuleKey, u);
      if (perm == null) return false;
      final level = perm['level']?.toString();
      if (perm['enabled'] == true && (level == 'editor' || level == 'admin')) {
        return true;
      }
      final subs = perm['subModules'] as Map<String, dynamic>?;
      if (subs != null) {
        for (final sub in subs.values) {
          if (sub is Map &&
              sub['enabled'] == true &&
              (sub['level'] == 'editor' || sub['level'] == 'admin')) {
            return true;
          }
        }
      }
      return false;
    }

    if (hasAnyMainModuleAccess(u)) {
      final mapped = _mapStToAppModule(stModuleKey);
      if (mapped != null) {
        return canEdit(mapped.$1, u);
      }
    }
    return false;
  }

  /// Kullanıcının Okul Türü İçi belirli bir alt modülde düzenleme (editor) yetkisi var mı?
  static bool canEditSchoolTypeSubModule(
    String stModuleKey,
    String stSubKey, [
    Map<String, dynamic>? userData,
    String? nestedKey,
  ]) {
    final u = userData ?? _cachedUserData;
    if (u == null) return true;

    final role = (u['role'] as String?)?.toLowerCase() ?? '';
    if (_isTopAdmin(role)) return true;

    if (!hasSchoolTypeSubModuleAccess(stModuleKey, stSubKey, u, nestedKey)) {
      return false;
    }

    final normSub = _normalizeStSubKey(stSubKey);

    if (hasAnyDirectSchoolTypeModuleAccess(u)) {
      final perm = _getEffectiveSchoolTypeModulePerm(stModuleKey, u);
      if (perm == null) return false;
      final subModules = perm['subModules'] as Map<String, dynamic>?;
      if (subModules != null) {
        if (nestedKey != null && subModules.containsKey(nestedKey)) {
          final np = subModules[nestedKey];
          if (np is Map) {
            if (np['enabled'] != true) return false;
            final nLevel = np['level']?.toString();
            return nLevel == 'editor' || nLevel == 'admin';
          }
        }
        final targetSub = subModules.containsKey(normSub) ? normSub : stSubKey;
        if (subModules.containsKey(targetSub)) {
          final sp = subModules[targetSub];
          if (sp is Map) {
            final level = sp['level']?.toString();
            return level == 'editor' || level == 'admin';
          }
        }
      }
      final level = perm['level']?.toString();
      return level == 'editor' || level == 'admin';
    }

    if (hasAnyMainModuleAccess(u)) {
      final mapped = _mapStToAppModule(stModuleKey, normSub);
      if (mapped != null) {
        if (mapped.$2 != null) {
          return canEditSubModule(
            mapped.$1,
            mapped.$2!,
            u,
            nestedKey: nestedKey,
          );
        }
        return canEdit(mapped.$1, u);
      }
    }

    return false;
  }

  /// Kullanıcının HERHANGİ bir ana modüle (dashboard modülü) erişimi var mı?
  static bool hasAnyMainModuleAccess(Map<String, dynamic>? userData) {
    final u = userData ?? _cachedUserData;
    if (u == null) return false;

    final role = (u['role'] as String?)?.toLowerCase() ?? '';
    if (_isTopAdmin(role)) return true;

    for (final key in AppModules.allModuleKeys) {
      if (hasModuleAccess(key, u)) return true;
    }

    return false;
  }

  /// Kullanıcının SADECE Sağlık İşlemleri (Revir) veya SADECE Güvenlik Kapı yetkisi olup olmadığını döner.
  /// Döndürdüğü değerler: `'health'` | `'security'` | `null`
  static String? getDedicatedSingleScreenTarget([Map<String, dynamic>? user]) {
    final u = user ?? _cachedUserData;
    if (u == null) return null;

    final roleRaw = (u['role'] ?? '').toString().trim().toLowerCase();
    final titleRaw = (u['title'] ?? '').toString().trim().toLowerCase();
    if (_isTopAdmin(roleRaw) ||
        roleRaw == 'mudur' ||
        roleRaw == 'müdür' ||
        roleRaw == 'mudur_yardimcisi' ||
        roleRaw == 'super_admin') {
      return null;
    }

    bool isHealthRoleKeyword(String r) =>
        r == 'saglik_personeli' ||
        r == 'sağlık_personeli' ||
        r == 'saglik' ||
        r == 'sağlık' ||
        r == 'revir' ||
        r == 'hemsire' ||
        r == 'hemşire' ||
        r == 'doktor';

    bool isSecurityRoleKeyword(String r) =>
        r == 'guvenlik' ||
        r == 'güvenlik' ||
        r == 'guvenlik_gorevlisi' ||
        r == 'security' ||
        r == 'kapi_guvenlik';

    bool isWarehouseRoleKeyword(String r) =>
        r == 'depo' || r == 'depocu' || r == 'depo_sorumlusu' || r == 'ambar';

    bool isPurchasingRoleKeyword(String r) =>
        r == 'satin_alma' ||
        r == 'satın_alma' ||
        r == 'satinalma' ||
        r == 'satin_alma_sorumlusu';

    final roleIndicatesHealth =
        isHealthRoleKeyword(roleRaw) || isHealthRoleKeyword(titleRaw);
    final roleIndicatesSecurity =
        isSecurityRoleKeyword(roleRaw) || isSecurityRoleKeyword(titleRaw);
    final roleIndicatesWarehouse =
        isWarehouseRoleKeyword(roleRaw) || isWarehouseRoleKeyword(titleRaw);
    final roleIndicatesPurchasing =
        isPurchasingRoleKeyword(roleRaw) || isPurchasingRoleKeyword(titleRaw);

    // Etkin izinlerde sağlık veya güvenlik dışında başka aktif modül/alt modül var mı?
    bool hasHealthPerm = false;
    bool hasSecurityPerm = false;
    bool hasWarehousePerm = false;
    bool hasPurchasingPerm = false;
    bool hasOtherMainPerm = false;

    for (final modKey in AppModules.allModuleKeys) {
      final modInfo = AppModules.getModule(modKey);
      if (modInfo == null) continue;
      if (!hasModuleAccess(modKey, u)) continue;

      if (modKey == 'hizmetler') {
        for (final subKey in modInfo.subModules.keys) {
          if (!hasSubModuleAccess('hizmetler', subKey, u)) continue;
          if (subKey == 'saglik_islemleri') {
            hasHealthPerm = true;
          } else if (subKey == 'guvenlik_kapi') {
            hasSecurityPerm = true;
          } else if (subKey == 'depo_satin_alma') {
            hasWarehousePerm = true;
          } else if (subKey == 'satin_alma_islemleri') {
            hasPurchasingPerm = true;
          } else {
            hasOtherMainPerm = true;
          }
        }
      } else {
        hasOtherMainPerm = true;
      }
    }

    // Okul türü modüllerinde sağlık / güvenlik kontrolü (eğer ana modüller kapalıysa)
    final stDestekPerm = _getEffectiveModulePerm('destek', u);
    if (stDestekPerm != null && stDestekPerm['enabled'] == true) {
      final subs = stDestekPerm['subModules'] as Map<String, dynamic>?;
      if (subs != null) {
        subs.forEach((subKey, val) {
          if (val is Map && val['enabled'] == true) {
            if (subKey == 'saglik') {
              hasHealthPerm = true;
            } else if (subKey == 'guvenlik') {
              hasSecurityPerm = true;
            } else if (subKey == 'depo_satin_alma') {
              hasWarehousePerm = true;
            } else if (subKey == 'satin_alma') {
              hasPurchasingPerm = true;
            } else {
              hasOtherMainPerm = true;
            }
          }
        });
      }
    }

    for (final stModKey in const [
      'kayit',
      'egitim',
      'rehberlik',
      'olcme',
      'araclar',
      'gorev',
      'raporlar',
      'ayarlar',
    ]) {
      final p = _getEffectiveModulePerm(stModKey, u);
      if (p != null && p['enabled'] == true) {
        hasOtherMainPerm = true;
      }
    }

    // 1) Sadece tek modül açık olan herhangi bir personel/özel rol
    final hasInvOrProc = hasWarehousePerm || hasPurchasingPerm;
    if (!hasOtherMainPerm &&
        hasHealthPerm &&
        !hasSecurityPerm &&
        !hasInvOrProc) {
      return 'health';
    }
    if (!hasOtherMainPerm &&
        hasSecurityPerm &&
        !hasHealthPerm &&
        !hasInvOrProc) {
      return 'security';
    }
    if (!hasOtherMainPerm &&
        !hasHealthPerm &&
        !hasSecurityPerm &&
        hasInvOrProc) {
      if ((hasPurchasingPerm && !hasWarehousePerm) ||
          (roleIndicatesPurchasing && !roleIndicatesWarehouse)) {
        return 'purchasing';
      }
      return 'warehouse';
    }

    // 2) Doğrudan 'saglik_personeli' / 'guvenlik' rolü atanmış ve ekstra ana modül verilmemişse
    // (Eski StaffFormScreen kaydı veya boş modulePermissions durumunda bile doğrudan kendi ekranına düşer)
    if (roleIndicatesHealth &&
        !hasOtherMainPerm &&
        !hasSecurityPerm &&
        !hasInvOrProc) {
      return 'health';
    }
    if (roleIndicatesSecurity &&
        !hasOtherMainPerm &&
        !hasHealthPerm &&
        !hasInvOrProc) {
      return 'security';
    }
    if (roleIndicatesWarehouse &&
        !hasOtherMainPerm &&
        !hasHealthPerm &&
        !hasSecurityPerm) {
      return 'warehouse';
    }
    if (roleIndicatesPurchasing &&
        !hasOtherMainPerm &&
        !hasHealthPerm &&
        !hasSecurityPerm) {
      return 'purchasing';
    }

    return null;
  }

  /// Impersonation modunda mı?
  static bool isImpersonating() {
    return _isImpersonating;
  }

  static final Map<String, String> _resolvedNameCache = {};

  /// Önbellekteki kullanıcı adını senkron olarak döner
  static String? getCachedUserFullName(String? userId) {
    if (userId == null || userId.isEmpty) return null;
    final cached = _resolvedNameCache[userId.trim()];
    return (cached != null &&
            cached.isNotEmpty &&
            cached != 'Kullanıcı' &&
            cached != 'Sistem Yöneticisi')
        ? cached
        : null;
  }

  /// Kullanıcı ID'sinden (UID veya docId) veya kurumdan kullanıcının gerçek Adını ve Soyadını (fullName) çözümler.
  static Future<String> resolveUserFullName(
    String? userId, {
    String? institutionId,
    String fallback = '',
  }) async {
    final uid = userId?.trim() ?? '';
    if (uid.isNotEmpty &&
        _resolvedNameCache.containsKey(uid) &&
        _resolvedNameCache[uid]!.isNotEmpty &&
        _resolvedNameCache[uid] != 'Kullanıcı' &&
        _resolvedNameCache[uid] != 'Sistem Yöneticisi') {
      return _resolvedNameCache[uid]!;
    }

    try {
      if (uid.isNotEmpty && uid != 'anon') {
        // 1. users/{uid} doğrudan doküman sorgusu
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        if (doc.exists) {
          final d = doc.data() ?? {};
          final n = (d['fullName'] ?? d['displayName'] ?? d['name'] ?? '')
              .toString()
              .trim();
          if (n.isNotEmpty && n != 'Kullanıcı' && n != 'Sistem Yöneticisi') {
            _resolvedNameCache[uid] = n;
            return n;
          }
        }

        // 2. authUserId alanı ile sorgu
        final q1 = await FirebaseFirestore.instance
            .collection('users')
            .where('authUserId', isEqualTo: uid)
            .limit(1)
            .get();
        if (q1.docs.isNotEmpty) {
          final d = q1.docs.first.data();
          final n = (d['fullName'] ?? d['displayName'] ?? d['name'] ?? '')
              .toString()
              .trim();
          if (n.isNotEmpty && n != 'Kullanıcı' && n != 'Sistem Yöneticisi') {
            _resolvedNameCache[uid] = n;
            return n;
          }
        }

        // 3. googleUid alanı ile sorgu
        final q2 = await FirebaseFirestore.instance
            .collection('users')
            .where('googleUid', isEqualTo: uid)
            .limit(1)
            .get();
        if (q2.docs.isNotEmpty) {
          final d = q2.docs.first.data();
          final n = (d['fullName'] ?? d['displayName'] ?? d['name'] ?? '')
              .toString()
              .trim();
          if (n.isNotEmpty && n != 'Kullanıcı' && n != 'Sistem Yöneticisi') {
            _resolvedNameCache[uid] = n;
            return n;
          }
        }

        // 4. schools/{uid} dokümanı sorgusu (Kurum yöneticisi kontrolü)
        final sDoc = await FirebaseFirestore.instance
            .collection('schools')
            .doc(uid)
            .get();
        if (sDoc.exists) {
          final d = sDoc.data() ?? {};
          final n = (d['adminFullName'] ?? d['schoolName'] ?? d['name'] ?? '')
              .toString()
              .trim();
          if (n.isNotEmpty && n != 'Kullanıcı' && n != 'Sistem Yöneticisi') {
            _resolvedNameCache[uid] = n;
            return n;
          }
        }

        // 5. schools tablosunda adminId ile arama
        final sAdminQ = await FirebaseFirestore.instance
            .collection('schools')
            .where('adminId', isEqualTo: uid)
            .limit(1)
            .get();
        if (sAdminQ.docs.isNotEmpty) {
          final d = sAdminQ.docs.first.data();
          final n = (d['adminFullName'] ?? d['schoolName'] ?? '')
              .toString()
              .trim();
          if (n.isNotEmpty && n != 'Kullanıcı' && n != 'Sistem Yöneticisi') {
            _resolvedNameCache[uid] = n;
            return n;
          }
        }
      }

      // 6. Giriş yapan kullanıcının kendi verileri (currentUser)
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser != null) {
        final ud = await loadUserData();
        if (ud != null) {
          final n =
              (ud['fullName'] ??
                      ud['adminFullName'] ??
                      ud['displayName'] ??
                      ud['name'] ??
                      '')
                  .toString()
                  .trim();
          if (n.isNotEmpty && n != 'Kullanıcı' && n != 'Sistem Yöneticisi') {
            if (uid.isNotEmpty) _resolvedNameCache[uid] = n;
            return n;
          }
        }
        if (authUser.displayName != null &&
            authUser.displayName!.trim().isNotEmpty) {
          final n = authUser.displayName!.trim();
          if (n != 'Kullanıcı' && n != 'Sistem Yöneticisi') {
            if (uid.isNotEmpty) _resolvedNameCache[uid] = n;
            return n;
          }
        }
        // E-posta adresiyle users sorgusu
        if (authUser.email != null && authUser.email!.isNotEmpty) {
          final eQuery = await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: authUser.email!.toLowerCase())
              .limit(1)
              .get();
          if (eQuery.docs.isNotEmpty) {
            final d = eQuery.docs.first.data();
            final n = (d['fullName'] ?? d['displayName'] ?? d['name'] ?? '')
                .toString()
                .trim();
            if (n.isNotEmpty && n != 'Kullanıcı' && n != 'Sistem Yöneticisi') {
              if (uid.isNotEmpty) _resolvedNameCache[uid] = n;
              return n;
            }
          }
        }
      }

      // 7. Kurum ID üzerinden schools dokümanındaki adminFullName'i çekme
      if (institutionId != null && institutionId.isNotEmpty) {
        final sInstQ = await FirebaseFirestore.instance
            .collection('schools')
            .where('institutionId', isEqualTo: institutionId)
            .limit(1)
            .get();
        if (sInstQ.docs.isNotEmpty) {
          final d = sInstQ.docs.first.data();
          final n = (d['adminFullName'] ?? d['schoolName'] ?? '')
              .toString()
              .trim();
          if (n.isNotEmpty && n != 'Kullanıcı' && n != 'Sistem Yöneticisi') {
            if (uid.isNotEmpty) _resolvedNameCache[uid] = n;
            return n;
          }
        }

        // users tablosunda bu kurumun admin/müdür kullanıcısını arama
        final uInstQ = await FirebaseFirestore.instance
            .collection('users')
            .where('institutionId', isEqualTo: institutionId)
            .where(
              'role',
              whereIn: ['admin', 'superadmin', 'mudur', 'genel_mudur'],
            )
            .limit(1)
            .get();
        if (uInstQ.docs.isNotEmpty) {
          final d = uInstQ.docs.first.data();
          final n = (d['fullName'] ?? d['displayName'] ?? '').toString().trim();
          if (n.isNotEmpty && n != 'Kullanıcı' && n != 'Sistem Yöneticisi') {
            if (uid.isNotEmpty) _resolvedNameCache[uid] = n;
            return n;
          }
        }
      }
    } catch (e) {
      print('resolveUserFullName hata: $e');
    }

    return fallback;
  }

  /// Kullanıcı görünen adını al
  static String getUserDisplayName(Map<String, dynamic>? userData) {
    if (userData != null) {
      return userData['fullName'] ?? 'Kullanıcı';
    }
    return 'Yönetici';
  }

  /// Kurum ID varyantlarını (büyük, küçük, orijinal) döner - Firestore case-sensitivity çözümüdür
  static List<String> getInstitutionIdVariants(String? institutionId) {
    if (institutionId == null || institutionId.trim().isEmpty) return [];
    final trimmed = institutionId.trim();
    return {
      trimmed,
      trimmed.toUpperCase(),
      trimmed.toLowerCase(),
    }.where((s) => s.isNotEmpty && s.toUpperCase() != 'GMAIL').toList();
  }

  /// Kurum ID'sini çözümler
  /// Öncelik sırası: 1. userData['institutionId'], 2. Email domain (kurumsal ise)
  static Future<String> resolveInstitutionId(
    String email, {
    Map<String, dynamic>? userData,
  }) async {
    // Cache'de varsa hemen dön — Firestore'a gitme
    if (_cachedInstitutionId != null &&
        _cachedInstitutionId!.isNotEmpty &&
        _cachedInstitutionId!.toUpperCase() != 'GMAIL') {
      return _cachedInstitutionId!;
    }

    // userData verilmemişse cache veya loadUserData'dan al
    userData ??= _cachedUserData;
    userData ??= await loadUserData();

    if (userData != null) {
      // 1. Varsa önce schoolId üzerinden schools koleksiyonundaki orijinal (canonical) institutionId'yi al.
      final schoolId = userData['schoolId'];
      if (schoolId != null && schoolId.toString().isNotEmpty) {
        try {
          final schoolDoc = await FirebaseFirestore.instance
              .collection('schools')
              .doc(schoolId.toString())
              .get();
          if (schoolDoc.exists) {
            final realInstId = schoolDoc.data()?['institutionId'];
            if (realInstId != null &&
                realInstId.toString().trim().isNotEmpty &&
                realInstId.toString().toUpperCase() != 'GMAIL') {
              _cachedInstitutionId = realInstId.toString().trim();
              return _cachedInstitutionId!;
            }
          }
        } catch (e) {
          print('Kanonik kurum ID çözümlenirken hata: $e');
        }
      }

      // 2. userData içindeki institutionId / instId değerine bak
      final userInst = (userData['institutionId'] ?? userData['instId'])
          ?.toString()
          .trim();
      if (userInst != null &&
          userInst.isNotEmpty &&
          userInst.toUpperCase() != 'GMAIL') {
        _cachedInstitutionId = userInst;
        return _cachedInstitutionId!;
      }
    }

    final lowerEmail = email.toLowerCase().trim();
    if (lowerEmail.contains('@')) {
      final domain = lowerEmail.split('@')[1];
      final genericDomains = [
        'gmail.com',
        'hotmail.com',
        'outlook.com',
        'yahoo.com',
        'icloud.com',
        'yandex.com',
        'windowslive.com',
        'live.com',
      ];

      if (!genericDomains.contains(domain) && domain.contains('.')) {
        final result = domain.split('.')[0].toUpperCase();
        if (result.isNotEmpty && result != 'GMAIL') {
          _cachedInstitutionId = result;
          return result;
        }
      }
    }

    return _cachedInstitutionId ?? 'GMAIL';
  }

  /// Kullanıcının öğretmen olup olmadığını kontrol eder
  static bool isTeacher() {
    final role = (_cachedUserData?['role'] ?? '').toString().toLowerCase();
    return role == 'teacher' || role == 'ogretmen' || role == 'öğretmen';
  }

  /// Öğretmenin yetkili olduğu sınıfları getirir:
  /// 1. Danışman / Sınıf Öğretmeni olduğu sınıf (classTeacherId, advisoryClassId vb.)
  /// 2. Rehberlik Öğretmeni olduğu sınıf (guidanceCounselorId, counselorId vb.)
  /// 3. Dersine girdiği sınıflar (lessonAssignments & classSchedules)
  static Future<Set<String>> getTeacherAllowedClassIds({
    required String institutionId,
    String? teacherId,
  }) async {
    final Set<String> classIds = {};
    try {
      final user = FirebaseAuth.instance.currentUser;
      final userData = await loadUserData();
      final instId = (userData?['institutionId'] ?? institutionId).toString();
      final instIds = [
        instId,
        instId.toLowerCase(),
        instId.toUpperCase(),
      ].toSet().toList();

      final Set<String> validTeacherIds = {};
      if (teacherId != null && teacherId.isNotEmpty)
        validTeacherIds.add(teacherId);
      if (user != null) validTeacherIds.add(user.uid);
      final docId = userData?['id']?.toString();
      if (docId != null && docId.isNotEmpty) validTeacherIds.add(docId);
      final authUserId = userData?['authUserId']?.toString();
      if (authUserId != null && authUserId.isNotEmpty)
        validTeacherIds.add(authUserId);
      final tId = userData?['teacherId']?.toString();
      if (tId != null && tId.isNotEmpty) validTeacherIds.add(tId);

      // userData içindeki doğrudan tanımlı sınıflar
      for (final field in [
        'advisoryClassId',
        'classTeacherClassId',
        'counselorClassId',
        'guidanceClassId',
        'assignedClassId',
      ]) {
        final cid = userData?[field]?.toString();
        if (cid != null && cid.isNotEmpty) classIds.add(cid);
      }
      if (userData?['assignedClassIds'] is List) {
        for (var c in (userData!['assignedClassIds'] as List)) {
          if (c != null && c.toString().isNotEmpty) classIds.add(c.toString());
        }
      }

      // 1. Sınıf Öğretmenliği (Danışman) ve Rehberlik Öğretmenliği (classes koleksiyonu)
      for (final tid in validTeacherIds) {
        final queries = await Future.wait([
          FirebaseFirestore.instance
              .collection('classes')
              .where('institutionId', whereIn: instIds)
              .where('classTeacherId', isEqualTo: tid)
              .where('isActive', isEqualTo: true)
              .get(),
          FirebaseFirestore.instance
              .collection('classes')
              .where('institutionId', whereIn: instIds)
              .where('guidanceCounselorId', isEqualTo: tid)
              .where('isActive', isEqualTo: true)
              .get(),
          FirebaseFirestore.instance
              .collection('classes')
              .where('institutionId', whereIn: instIds)
              .where('counselorId', isEqualTo: tid)
              .where('isActive', isEqualTo: true)
              .get(),
        ]);
        for (var snap in queries) {
          for (var doc in snap.docs) {
            classIds.add(doc.id);
          }
        }
      }

      // 2. Dersine girdiği sınıflar (lessonAssignments ve classSchedules)
      for (final tid in validTeacherIds) {
        final queries = await Future.wait([
          FirebaseFirestore.instance
              .collection('lessonAssignments')
              .where('institutionId', whereIn: instIds)
              .where('teacherIds', arrayContains: tid)
              .where('isActive', isEqualTo: true)
              .get(),
          FirebaseFirestore.instance
              .collection('lessonAssignments')
              .where('institutionId', whereIn: instIds)
              .where('teacherId', isEqualTo: tid)
              .where('isActive', isEqualTo: true)
              .get(),
          FirebaseFirestore.instance
              .collection('classSchedules')
              .where('institutionId', whereIn: instIds)
              .where('teacherId', isEqualTo: tid)
              .get(),
        ]);
        for (var snap in queries) {
          for (var doc in snap.docs) {
            final cid = (doc.data() as Map<String, dynamic>?)?['classId']
                ?.toString();
            if (cid != null && cid.isNotEmpty) classIds.add(cid);
          }
        }
      }
    } catch (e) {
      print('Öğretmen yetkili sınıfları alınırken hata: $e');
    }
    return classIds;
  }
}
