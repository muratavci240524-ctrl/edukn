import 'dart:convert';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:cloud_functions/cloud_functions.dart';

/// 🔐 EduKN Veri Şifreleme Servisi
///
/// AES-256-CBC kullanarak hassas kişisel verileri şifreler.
/// Şifreleme anahtarı Firebase Functions'dan alınır — uygulama koduna gömülmez.
///
/// Format: "ENC:<base64_iv>:<base64_encrypted>"
/// Bu prefix sayesinde sistem şifreli mi düz metin mi olduğunu ayırt eder.
class EncryptionService {
  static const String _encPrefix = 'ENC:';

  // Bellek içi anahtar cache — oturum boyunca Functions'a 1 kez gidilir
  static String? _cachedKey;
  static bool _isFetching = false;

  /// Şifreleme anahtarını Firebase Functions'dan al (ilk kullanımda)
  static Future<enc.Key> _getKey() async {
    if (_cachedKey != null) {
      return enc.Key.fromBase64(_cachedKey!);
    }

    // Eş zamanlı fetch'leri önle
    if (_isFetching) {
      // Kısa bekleyerek cache dolmasını bekle
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_cachedKey != null) return enc.Key.fromBase64(_cachedKey!);
      }
      throw Exception('Şifreleme anahtarı alınamadı.');
    }

    _isFetching = true;
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'getEncryptionKeyForClient',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
      );
      final result = await callable.call();
      _cachedKey = result.data['key'] as String;
      return enc.Key.fromBase64(_cachedKey!);
    } finally {
      _isFetching = false;
    }
  }

  /// Bir metni şifreler. Boş veya null ise olduğu gibi döner.
  /// [ENC:iv:ciphertext] formatında döner.
  static Future<String?> encrypt(String? plaintext) async {
    if (plaintext == null || plaintext.trim().isEmpty) return plaintext;
    // Zaten şifreliyse tekrar şifreleme
    if (plaintext.startsWith(_encPrefix)) return plaintext;

    try {
      final key = await _getKey();
      final iv = enc.IV.fromSecureRandom(16);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final encrypted = encrypter.encrypt(plaintext, iv: iv);
      return '$_encPrefix${iv.base64}:${encrypted.base64}';
    } catch (e) {
      // Şifreleme başarısız olursa düz metin döndür (veri kaybı olmasın)
      // Üretimde bu log silinebilir
      print('⚠️ EncryptionService.encrypt hatası: $e');
      return plaintext;
    }
  }

  /// Şifreli metni çözer. Şifreli değilse (ENC: prefix yoksa) olduğu gibi döner.
  static Future<String?> decrypt(String? ciphertext) async {
    if (ciphertext == null || ciphertext.trim().isEmpty) return ciphertext;
    if (!ciphertext.startsWith(_encPrefix)) return ciphertext; // Zaten düz metin

    try {
      final body = ciphertext.substring(_encPrefix.length);
      final parts = body.split(':');
      if (parts.length != 2) return ciphertext; // Format bozuk, olduğu gibi dön

      final iv = enc.IV.fromBase64(parts[0]);
      final encryptedBase64 = parts[1];

      final key = await _getKey();
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      return encrypter.decrypt64(encryptedBase64, iv: iv);
    } catch (e) {
      print('⚠️ EncryptionService.decrypt hatası: $e');
      return ciphertext; // Hata durumunda şifreli göster (daha güvenli)
    }
  }

  /// Şifreli mi kontrol et
  static bool isEncrypted(String? value) {
    return value != null && value.startsWith(_encPrefix);
  }

  /// Bellek cache'ini temizle (logout sırasında çağrıl)
  static void clearCache() {
    _cachedKey = null;
    _isFetching = false;
  }

  /// Bir Map içindeki belirtilen alanları şifrele
  /// Kullanım: final encrypted = await EncryptionService.encryptFields(data, ['tcNo', 'birthDate', 'phone']);
  static Future<Map<String, dynamic>> encryptFields(
    Map<String, dynamic> data,
    List<String> fields,
  ) async {
    final result = Map<String, dynamic>.from(data);
    for (final field in fields) {
      if (result.containsKey(field) && result[field] != null) {
        result[field] = await encrypt(result[field].toString());
      }
    }
    return result;
  }

  /// Bir Map içindeki belirtilen alanları çöz (Display için)
  static Future<Map<String, dynamic>> decryptFields(
    Map<String, dynamic> data,
    List<String> fields,
  ) async {
    final result = Map<String, dynamic>.from(data);
    for (final field in fields) {
      if (result.containsKey(field) && result[field] != null) {
        result[field] = await decrypt(result[field].toString());
      }
    }
    return result;
  }

  // ─── Koleksiyon bazlı alan listeleri ─────────────────────────────────────

  /// Öğrenci kaydında şifrelenecek alanlar
  static const List<String> studentSensitiveFields = [
    'tcNo',
    'birthDate',
    'phone',
    'parentPhone1',
    'parentPhone2',
    'parentPhone',
  ];

  /// Kullanıcı (öğretmen/yönetici) kaydında şifrelenecek alanlar
  static const List<String> userSensitiveFields = [
    'tcNo',
    'birthDate',
    'phone',
  ];

  /// Veli kaydında şifrelenecek alanlar
  static const List<String> parentSensitiveFields = [
    'tcNo',
    'birthDate',
    'phone',
  ];

  /// Personel kaydında şifrelenecek alanlar
  static const List<String> staffSensitiveFields = [
    'tcNo',
    'birthDate',
    'phone',
    'iban',
    'salary',
    'baseSalary',
  ];
}
