import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Merkezi kullanıcı yetki yönetim servisi
/// Tüm modüller bu servisi kullanarak kullanıcı verilerini ve yetkilerini alır
class UserPermissionService {
  static Map<String, dynamic>? _cachedUserData;
  static bool _isImpersonating = false;

  /// Kullanıcı verilerini yükle (normal veya impersonation)
  static Future<Map<String, dynamic>?> loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

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
        // Normal mod - Email'den kullanıcıyı bul
        print('👤 Normal mod - Email: ${user.email}');

        // Önce doküman ID'si olarak UID'yi dene (En güvenli ve hızlı yöntem)
        print('🔍 Doküman ID olarak UID deneniyor...');
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
          // UID ile bulunamazsa email ile dene
          print('🔍 UID ile bulunamadı, email ile deneniyor...');
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
    // Admin kullanıcısı (userData yok) - Tüm modüllere erişebilir
    if (userData == null) return true;

    final modulePerms = userData['modulePermissions'] as Map<String, dynamic>?;
    if (modulePerms == null) return false;

    final modulePerm = modulePerms[moduleKey] as Map<String, dynamic>?;
    if (modulePerm == null) return false;

    return modulePerm['enabled'] == true;
  }

  /// Belirli bir modülde düzenleme yetkisi var mı?
  static bool canEdit(String moduleKey, Map<String, dynamic>? userData) {
    // Admin kullanıcısı (userData yok) - Her zaman düzenleyebilir
    if (userData == null) return true;

    // Önce modüle erişimi var mı kontrol et
    if (!hasModuleAccess(moduleKey, userData)) return false;

    final modulePerms = userData['modulePermissions'] as Map<String, dynamic>?;
    if (modulePerms == null) return false;

    final modulePerm = modulePerms[moduleKey] as Map<String, dynamic>?;
    if (modulePerm == null) return false;

    // level: 'editor' ise true, 'viewer' ise false
    return modulePerm['level'] == 'editor';
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
