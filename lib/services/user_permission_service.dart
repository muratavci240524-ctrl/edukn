import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'crypto_service.dart';
import 'role_permission_service.dart';
import '../constants/app_modules.dart';

/// Merkezi kullanıcı yetki yönetim servisi
/// Tüm modüller bu servisi kullanarak kullanıcı verilerini ve yetkilerini alır
class UserPermissionService {
  static Map<String, dynamic>? _cachedUserData;
  static bool _isImpersonating = false;
  static Future<Map<String, dynamic>?>? _loadFuture;
  // resolveInstitutionId sonucunu cache'le — her ekran açılışında Firestore'a gitmemek için
  static String? _cachedInstitutionId;
  // Rol şablonu cache — login sonrası yüklenir
  static Map<String, dynamic>? _cachedRoleTemplate;

  /// Kullanıcı verilerini yükle (normal veya impersonation)
  static Future<Map<String, dynamic>?> loadUserData({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedUserData != null) return _cachedUserData;
    if (!forceRefresh && _loadFuture != null) {
      final result = await _loadFuture!;
      if (result != null) return result;
      // Önceki sonuç null ise tekrar dene
    }
    
    _loadFuture = _internalLoadUserData();
    return _loadFuture;
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
        // Normal mod - Email'den kullanıcıyı bul (En güvenli yöntem)
        print('👤 Normal mod - Email: ${user.email}');

        final userQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: user.email?.toLowerCase())
            .get();

        if (userQuery.docs.isNotEmpty) {
          // Eğer birden fazla doküman varsa, gerçek bir institutionId'si olanı tercih et
          QueryDocumentSnapshot? bestDoc;
          for (var doc in userQuery.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final instId = data['institutionId']?.toString();
            if (instId != null && instId.isNotEmpty && instId.toUpperCase() != 'GMAIL') {
              bestDoc = doc;
              break;
            }
          }
          
          if (bestDoc == null) {
             for (var doc in userQuery.docs) {
               final data = doc.data() as Map<String, dynamic>;
               if (data['institutionId'] != null) {
                 bestDoc = doc;
                 break;
               }
             }
          }
          
          final selectedDoc = bestDoc ?? userQuery.docs.first;
          userData = selectedDoc.data() as Map<String, dynamic>;
          userData['id'] = selectedDoc.id;
          print('✅ Email ile kullanıcı bulundu: ${userData['fullName']} (ID: ${selectedDoc.id})');
          if (userData['institutionId'] == null) {
            print('⚠️ UYARI: Kullanıcının institutionId bilgisi boş!');
          }
        } else {
          // Email ile bulunamazsa doküman ID'si olarak UID'yi dene
          print('🔍 Email ile bulunamadı, UID (doc id) deneniyor...');
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

          if (userDoc.exists) {
            userData = userDoc.data();
            if (userData != null) {
              userData['id'] = user.uid;
              print(
                '✅ UID (doc id) ile kullanıcı bulundu: ${userData['fullName']}',
              );
            }
          } else {
            // Hala bulunamazsa authUserId alanı ile dene
            print('🔍 Email ile bulunamadı, authUserId alanı ile deneniyor...');
            final authUserQuery = await FirebaseFirestore.instance
                .collection('users')
                .where('authUserId', isEqualTo: user.uid)
                .limit(1)
                .get();

            if (authUserQuery.docs.isNotEmpty) {
              userData = authUserQuery.docs.first.data();
              userData['id'] = authUserQuery.docs.first.id;
              print(
                '✅ authUserId alanı ile kullanıcı bulundu: ${userData['fullName']}',
              );
            }
          }
        }
      }

      if (userData == null) {
        // Parents koleksiyonunda ara
        print('🔍 Users koleksiyonunda bulunamadı, parents koleksiyonu deneniyor...');
        final parentQuery = await FirebaseFirestore.instance
            .collection('parents')
            .where('username', isEqualTo: user.email?.split('@')[0])
            .limit(1)
            .get();
            
        if (parentQuery.docs.isNotEmpty) {
          userData = parentQuery.docs.first.data();
          userData!['id'] = parentQuery.docs.first.id;
          userData['role'] = 'parent';
          print('✅ Parent olarak bulundu: ${userData['fullName'] ?? userData['name']}');
        }
      }

      if (userData == null) {
        // Eğer hala bulunamadıysa ama bu bir admin ise (Email'den veya ID'den anlayabiliyorsak)
        // Şimdilik null dönüyoruz ama hasModuleAccess içinde null userData = admin yetkisi veriyoruz
        print('ℹ️ Kullanıcı verisi bulunamadı, varsayılan yetkiler kullanılacak.');
      }

      _cachedUserData = userData != null ? CryptoService.decryptMap(userData) : null;
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
    print('📌 Rol şablonu cache ayarlandı: ${template != null ? "yüklendi" : "null"}');
  }

  /// Rol şablonunu Firestore'dan yükle ve cache'le
  static Future<void> loadAndCacheRoleTemplate(String institutionId, String role) async {
    try {
      final template = await RolePermissionService().loadRoleTemplate(institutionId, role);
      if (template != null) {
        _cachedRoleTemplate = template;
        print('✅ Rol şablonu yüklendi: $role');
        // Debug: Şablondaki modülleri listele
        final appPerms = template['appPermissions'] as Map<String, dynamic>?;
        if (appPerms != null) {
          print('📋 Şablon modülleri ($role):');
          appPerms.forEach((key, value) {
            if (value is Map) {
              print('   ${value['enabled'] == true ? "✅" : "❌"} $key (${value['level'] ?? "yok"})');
            }
          });
        } else {
          print('⚠️ Şablonda appPermissions yok! Anahtarlar: ${template.keys.toList()}');
        }
      } else {
        // Varsayılan şablonu oluştur
        _cachedRoleTemplate = {
          'appPermissions': RolePermissionService.getDefaultPermissions(role),
          'schoolTypePermissions': RolePermissionService.getDefaultSchoolTypePermissions(role),
        };
        print('ℹ️ Varsayılan rol şablonu kullanıldı: $role');
      }
    } catch (e) {
      print('⚠️ Rol şablonu yüklenemedi: $e');
      _cachedRoleTemplate = null;
    }
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
  }

  // ─── Yardımcı: Rol kontrolü ───
  static bool _isTopAdmin(String role) {
    return role == 'admin' || role == 'genel_mudur' || role == 'genel müdür' || role == 'genel mudur';
  }

  /// Modül yetkisini önce kişisel izinlerden, yoksa rol şablonundan kontrol et
  /// Kişisel izinler VARSA → sadece onlar geçerli (kişiye özel override)
  /// Kişisel izinler YOKSA (null/boş) → rol şablonu varsayılan olarak kullanılır
  static Map<String, dynamic>? _getEffectiveModulePerm(String moduleKey, Map<String, dynamic>? userData) {
    final personalPerms = userData?['modulePermissions'] as Map<String, dynamic>?;
    final schoolTypePerms = userData?['schoolTypeModulePermissions'] as Map<String, dynamic>?;
    
    final hasPersonalPerms = personalPerms != null && personalPerms.isNotEmpty;
    final hasSchoolTypePerms = schoolTypePerms != null && schoolTypePerms.isNotEmpty;
    
    // Kişisel izinler tanımlıysa → SADECE kişisel izinleri kullan
    if (hasPersonalPerms || hasSchoolTypePerms) {
      if (hasPersonalPerms && personalPerms.containsKey(moduleKey)) {
        final perm = personalPerms[moduleKey];
        if (perm is Map) return Map<String, dynamic>.from(perm);
      }
      
      // Ana modüller arasında yoksa, okul türü modülleri arasında var mı bak
      if (hasSchoolTypePerms && schoolTypePerms.containsKey(moduleKey)) {
        final perm = schoolTypePerms[moduleKey];
        if (perm is Map) return Map<String, dynamic>.from(perm);
      }
      
      // Kişisel izinlerde bu modül tanımlı değil → erişim yok
      return null;
    }
    
    // Kişisel izinler BOŞ veya NULL → Rol şablonunu varsayılan olarak kullan
    if (_cachedRoleTemplate != null) {
      final templatePerms = _cachedRoleTemplate!['appPermissions'] as Map<String, dynamic>?;
      if (templatePerms != null && templatePerms.containsKey(moduleKey)) {
        final perm = templatePerms[moduleKey];
        if (perm is Map) {
          // Şablonda level tanımlıysa modül aktif demektir — normalize et
          final normalized = Map<String, dynamic>.from(perm);
          if (normalized.containsKey('level') && normalized['level'] != null) {
            normalized['enabled'] = true;
          }
          // Alt modülleri de normalize et
          if (normalized['subModules'] is Map) {
            final subs = Map<String, dynamic>.from(normalized['subModules']);
            subs.forEach((subKey, subVal) {
              if (subVal is Map) {
                final subNorm = Map<String, dynamic>.from(subVal);
                if (subNorm.containsKey('level') && subNorm['level'] != null) {
                  subNorm['enabled'] = true;
                }
                subs[subKey] = subNorm;
              }
            });
            normalized['subModules'] = subs;
          }
          return normalized;
        }
      }
    }

    return null;
  }

  /// Belirli bir modüle erişim yetkisi var mı?
  static bool hasModuleAccess(
    String moduleKey,
    Map<String, dynamic>? userData,
  ) {
    if (userData == null) return true; // Admin has full access

    final role = (userData['role'] as String?)?.toLowerCase() ?? '';
    if (_isTopAdmin(role)) return true;

    final effectivePerm = _getEffectiveModulePerm(moduleKey, userData);

    if (effectivePerm != null) {
      // Ana modül aktifse veya herhangi bir alt modülü aktifse erişim vardır
      if (effectivePerm['enabled'] == true) return true;

      final subModules = effectivePerm['subModules'] as Map<String, dynamic>?;
      if (subModules != null) {
        for (var sub in subModules.values) {
          if (sub is Map && sub['enabled'] == true) return true;
        }
      }
      return false;
    }

    // Ne kişisel ne şablon izni tanımlı → erişim yok
    return false;
  }

  /// Belirli bir modülde düzenleme yetkisi var mı?
  static bool canEdit(String moduleKey, Map<String, dynamic>? userData) {
    if (userData == null) return true;

    final role = (userData['role'] as String?)?.toLowerCase() ?? '';
    if (_isTopAdmin(role)) return true;

    final effectivePerm = _getEffectiveModulePerm(moduleKey, userData);

    if (effectivePerm != null) {
      if (effectivePerm['enabled'] != true) return false;
      final level = effectivePerm['level']?.toString();
      if (level == 'editor' || level == 'admin') return true;
      return false; // viewer
    }

    return false;
  }

  /// Belirli bir alt modüle erişim yetkisi var mı?
  static bool hasSubModuleAccess(
    String moduleKey,
    String subModuleKey,
    Map<String, dynamic>? userData,
  ) {
    if (userData == null) return true;

    final role = (userData['role'] as String?)?.toLowerCase() ?? '';
    if (_isTopAdmin(role)) return true;

    final effectivePerm = _getEffectiveModulePerm(moduleKey, userData);

    if (effectivePerm != null) {
      if (effectivePerm['enabled'] != true) return false;

      final subModules = effectivePerm['subModules'] as Map<String, dynamic>?;
      if (subModules != null && subModules.containsKey(subModuleKey)) {
        final subPerm = subModules[subModuleKey];
        if (subPerm is Map) return subPerm['enabled'] == true;
      }
      // Alt modül tanımlı değil ama ana modül açık → erişim var
      return true;
    }

    return false;
  }

  /// Belirli bir alt modülde düzenleme yetkisi var mı?
  static bool canEditSubModule(
    String moduleKey,
    String subModuleKey,
    Map<String, dynamic>? userData,
  ) {
    if (userData == null) return true;

    final role = (userData['role'] as String?)?.toLowerCase() ?? '';
    if (_isTopAdmin(role)) return true;

    final effectivePerm = _getEffectiveModulePerm(moduleKey, userData);

    if (effectivePerm != null) {
      if (effectivePerm['enabled'] != true) return false;

      final subModules = effectivePerm['subModules'] as Map<String, dynamic>?;
      if (subModules != null && subModules.containsKey(subModuleKey)) {
        final subPerm = subModules[subModuleKey];
        if (subPerm is Map) {
          final level = subPerm['level']?.toString();
          if (level == 'editor' || level == 'admin') return true;
          return false; // viewer
        }
      }
      // Alt modül tanımlı değil → ana modül seviyesine bak
      final level = effectivePerm['level']?.toString();
      if (level == 'editor' || level == 'admin') return true;
      return false;
    }

    return false;
  }

  /// Kullanıcının HERHANGİ bir ana modüle (dashboard modülü) erişimi var mı?
  static bool hasAnyMainModuleAccess(Map<String, dynamic>? userData) {
    if (userData == null) return false;

    final role = (userData['role'] as String?)?.toLowerCase() ?? '';
    if (_isTopAdmin(role)) return true;

    // Sadece gerçek ana modül key'lerini kontrol et (AppModules'daki tanımlı modüller)
    final mainModuleKeys = AppModules.allModuleKeys;

    final modulePerms = userData['modulePermissions'] as Map<String, dynamic>?;
    
    // Kişisel izinler VARSA → sadece ana modül key'lerine bak
    if (modulePerms != null && modulePerms.isNotEmpty) {
      for (var key in mainModuleKeys) {
        final perm = modulePerms[key];
        if (perm is Map && perm['enabled'] == true) return true;
      }
      return false; // Kişisel izinlerde hiçbir ana modül aktif değil
    }

    // Kişisel izinler YOKSA → rol şablonuna bak
    if (_cachedRoleTemplate != null) {
      final templatePerms = _cachedRoleTemplate!['appPermissions'] as Map<String, dynamic>?;
      if (templatePerms != null) {
        for (var key in mainModuleKeys) {
          final perm = templatePerms[key];
          if (perm is Map) {
            if (perm['enabled'] == true || (perm['level'] != null)) return true;
          }
        }
      }
    }

    return false;
  }


  /// Impersonation modunda mı?
  static bool isImpersonating() {
    return _isImpersonating;
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
  static Future<String> resolveInstitutionId(String email, {Map<String, dynamic>? userData}) async {
    // Cache'de varsa hemen dön — Firestore'a gitme
    if (_cachedInstitutionId != null &&
        _cachedInstitutionId!.isNotEmpty &&
        _cachedInstitutionId!.toUpperCase() != 'GMAIL') {
      return _cachedInstitutionId!;
    }

    // userData verilmemişse cache veya loadUserData'dan al
    userData ??= _cachedUserData;
    if (userData == null) {
      userData = await loadUserData();
    }

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
      final userInst = (userData['institutionId'] ?? userData['instId'])?.toString().trim();
      if (userInst != null && userInst.isNotEmpty && userInst.toUpperCase() != 'GMAIL') {
        _cachedInstitutionId = userInst;
        return _cachedInstitutionId!;
      }
    }

    final lowerEmail = email.toLowerCase().trim();
    if (lowerEmail.contains('@')) {
      final domain = lowerEmail.split('@')[1];
      final genericDomains = [
        'gmail.com', 'hotmail.com', 'outlook.com', 'yahoo.com', 
        'icloud.com', 'yandex.com', 'windowslive.com', 'live.com'
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
}
