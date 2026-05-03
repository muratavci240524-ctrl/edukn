import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Merkezi kullanıcı yetki yönetim servisi
/// Tüm modüller bu servisi kullanarak kullanıcı verilerini ve yetkilerini alır
class UserPermissionService {
  static Map<String, dynamic>? _cachedUserData;
  static bool _isImpersonating = false;
  static Future<Map<String, dynamic>?>? _loadFuture;

  /// Kullanıcı verilerini yükle (normal veya impersonation)
  static Future<Map<String, dynamic>?> loadUserData({bool forceRefresh = false}) async {
    if (_loadFuture != null && !forceRefresh) return _loadFuture;
    
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
            .where('email', isEqualTo: user.email)
            .limit(1)
            .get();

        if (userQuery.docs.isNotEmpty) {
          userData = userQuery.docs.first.data();
          userData['id'] = userQuery.docs.first.id;
          print('✅ Email ile kullanıcı bulundu: ${userData['fullName']}');
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

      if (userData != null) {
        print('📋 Modül yetkileri: ${userData['modulePermissions']}');
      } else {
        print('ℹ️ Admin kullanıcısı - Firestore\'da kullanıcı kaydı yok');
      }

      _cachedUserData = userData;
      return userData;
    } catch (e) {
      print('❌ Kullanıcı verileri yüklenirken hata: $e');
      return null;
    }
  }

  /// Cache'lenmiş kullanıcı verisini al (performans için)
  static Map<String, dynamic>? getCachedUserData() {
    return _cachedUserData;
  }

  /// Cache'i temizle (logout veya impersonation değişikliğinde)
  static void clearCache() {
    _cachedUserData = null;
    _isImpersonating = false;
  }

  /// Belirli bir modüle erişim yetkisi var mı?
  static bool hasModuleAccess(
    String moduleKey,
    Map<String, dynamic>? userData,
  ) {
    if (userData == null) return true;

    // Admin veya Müdür - Tüm modüllere tam erişim
    final role = (userData['role'] as String?)?.toLowerCase();
    if (role == 'genel_mudur' || role == 'mudur') return true;

    final modulePerms = userData['modulePermissions'] as Map<String, dynamic>?;
    if (modulePerms == null) return false;

    final modulePerm = modulePerms[moduleKey] as Map<String, dynamic>?;
    if (modulePerm == null) return false;

    // Ana modül aktifse veya herhangi bir alt modülü aktifse erişim vardır
    if (modulePerm['enabled'] == true) return true;
    
    final subModules = modulePerm['subModules'] as Map<String, dynamic>?;
    if (subModules != null) {
      for (var sub in subModules.values) {
        if (sub is Map && sub['enabled'] == true) return true;
      }
    }

    return false;
  }

  /// Belirli bir modülde düzenleme yetkisi var mı?
  static bool canEdit(String moduleKey, Map<String, dynamic>? userData) {
    if (userData == null) return true;

    // Admin veya Müdür - Her şeyi düzenleyebilir
    final role = (userData['role'] as String?)?.toLowerCase();
    if (role == 'genel_mudur' || role == 'mudur') return true;

    if (!hasModuleAccess(moduleKey, userData)) return false;

    final modulePerms = userData['modulePermissions'] as Map<String, dynamic>?;
    final modulePerm = modulePerms?[moduleKey] as Map<String, dynamic>?;
    
    return modulePerm?['level'] == 'editor';
  }

  /// Belirli bir alt modüle erişim yetkisi var mı?
  static bool hasSubModuleAccess(
    String moduleKey,
    String subModuleKey,
    Map<String, dynamic>? userData,
  ) {
    if (userData == null) return true;

    // Admin veya Müdür - Tüm alt modüllere tam erişim
    final role = (userData['role'] as String?)?.toLowerCase();
    if (role == 'genel_mudur' || role == 'mudur') return true;

    if (!hasModuleAccess(moduleKey, userData)) return false;

    final modulePerms = userData['modulePermissions'] as Map<String, dynamic>?;
    final modulePerm = modulePerms?[moduleKey] as Map<String, dynamic>?;
    final subModules = modulePerm?['subModules'] as Map<String, dynamic>?;
    
    if (subModules == null) return true; 
    
    final subPerm = subModules[subModuleKey] as Map<String, dynamic>?;
    return subPerm?['enabled'] == true;
  }

  /// Belirli bir alt modülde düzenleme yetkisi var mı?
  static bool canEditSubModule(
    String moduleKey,
    String subModuleKey,
    Map<String, dynamic>? userData,
  ) {
    if (userData == null) return true;

    // Admin veya Müdür - Tüm alt modülleri düzenleyebilir
    final role = (userData['role'] as String?)?.toLowerCase();
    if (role == 'genel_mudur' || role == 'mudur') return true;

    if (!hasSubModuleAccess(moduleKey, subModuleKey, userData)) return false;

    final modulePerms = userData['modulePermissions'] as Map<String, dynamic>?;
    final modulePerm = modulePerms?[moduleKey] as Map<String, dynamic>?;
    final subModules = modulePerm?['subModules'] as Map<String, dynamic>?;
    
    if (subModules == null) return canEdit(moduleKey, userData);
    
    final subPerm = subModules[subModuleKey] as Map<String, dynamic>?;
    return subPerm?['level'] == 'editor';
  }

  /// Kullanıcının HERHANGİ bir ana modüle (dashboard modülü) erişimi var mı?
  static bool hasAnyMainModuleAccess(Map<String, dynamic>? userData) {
    if (userData == null) return true;
    
    final modulePerms = userData['modulePermissions'] as Map<String, dynamic>?;
    if (modulePerms == null) return false;
    
    for (var entry in modulePerms.entries) {
      if (hasModuleAccess(entry.key, userData)) return true;
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
}
