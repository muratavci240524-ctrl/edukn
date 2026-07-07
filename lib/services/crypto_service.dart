import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 🔐 CryptoService — Hassas verileri veritabanına yazmadan önce cihaz üzerinde
/// şifreler (AES-256) ve okurken çözer.
///
/// ⚙️ YENİ GÜVENLİK MİMARİSİ:
///   - Şifreleme anahtarı Firebase Secret Manager'dan Cloud Functions aracılığıyla çekilir.
///   - Her şifrelemede benzersiz dinamik IV (Initialization Vector) kullanılır.
///   - Geriye Dönük Uyumluluk (Graceful Fallback): Eski şifreli verileri (statik IV ve lokal anahtarlı) otomatik tespit eder ve çözer.
class CryptoService {
  static const String _globalSalt = 'eDuKn_sEcUrE_kEy_2026_FieLd_Enc!';
  static final _globalIV = enc.IV.fromUtf8('eDuKn_iv_Vector16');

  static String? _serverKeyBase64;
  static bool _isFetching = false;

  /// Map içindeki bilinen tüm şifreli alanları çözer.
  static Map<String, dynamic> decryptMap(Map<String, dynamic> data, {String? institutionId}) {
    final result = Map<String, dynamic>.from(data);
    final inst = institutionId ?? result['institutionId'] as String?;

    const fieldsToDecrypt = [
      'tcNo', 'tcKimlik', 'phone', 'birthDate', 'parentPhone1', 'parentPhone2', 'parentPhone',
      'iban', 'salary', 'baseSalary', 'extraHourRate', 'overtimeHourRate', 'totalEarnings', 'totalDeductions', 'netSalary'
    ];

    for (final field in fieldsToDecrypt) {
      if (result.containsKey(field) && result[field] != null) {
        final val = result[field].toString();
        if (val.startsWith('ENC:')) {
          result[field] = decrypt(val, institutionId: inst);
        }
      }
    }

    if (result.containsKey('parents') && result['parents'] is List) {
      result['parents'] = (result['parents'] as List).map((p) {
        if (p is Map) {
          return decryptMap(Map<String, dynamic>.from(p), institutionId: inst);
        }
        return p;
      }).toList();
    }

    return result;
  }

  /// Şifreleme anahtarını Firebase Functions'dan güvenli bir şekilde çeker.
  /// Kullanıcı giriş yaptıktan sonra veya uygulama başlangıcında çağrılmalıdır.
  static Future<void> init() async {
    if (_serverKeyBase64 != null) return;
    if (_isFetching) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return; // Kullanıcı yoksa anahtar çekilemez

    _isFetching = true;
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
        'getEncryptionKeyForClient',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
      );
      final result = await callable.call();
      _serverKeyBase64 = result.data['key'] as String?;
      print('🔐 CryptoService: Sunucu şifreleme anahtarı başarıyla yüklendi.');
    } catch (e) {
      print('⚠️ CryptoService: Şifreleme anahtarı sunucudan alınamadı: $e');
    } finally {
      _isFetching = false;
    }
  }

  /// Sunucu anahtarının yüklü olup olmadığını döner.
  static bool get isInitialized => _serverKeyBase64 != null;

  /// Kurum ID'sine göre 32-byte (256-bit) eski AES anahtarını türetir.
  static enc.Key _getLegacyKey(String? institutionId) {
    final seed = (institutionId != null && institutionId.isNotEmpty)
        ? '${institutionId}_$_globalSalt'
        : _globalSalt;
    final bytes = seed.codeUnits;
    final keyBytes = List<int>.generate(32, (i) => bytes[i % bytes.length]);
    return enc.Key(Uint8List.fromList(keyBytes));
  }

  /// Düz metni şifreler ve Base64 formatında döner.
  /// Sunucu anahtarı yüklüyse: AES-256-CBC + Dinamik IV kullanarak şifreler, format: "ENC:iv_base64:ciphertext_base64"
  /// Sunucu anahtarı yüklü değilse: Eski yönteme (kurum bazlı anahtar + statik IV) geri döner, format: "ENC:ciphertext_base64"
  static String encrypt(String? plainText, {String? institutionId}) {
    if (plainText == null || plainText.trim().isEmpty) return '';
    if (plainText.startsWith('ENC:')) return plainText; // Zaten şifreli

    try {
      if (_serverKeyBase64 != null) {
        // Yeni güvenli şifreleme (Sunucu anahtarı + Dinamik IV)
        final key = enc.Key.fromBase64(_serverKeyBase64!);
        final iv = enc.IV.fromSecureRandom(16);
        final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
        final encrypted = encrypter.encrypt(plainText, iv: iv);
        return 'ENC:${iv.base64}:${encrypted.base64}';
      } else {
        // Eski yöntem (Graceful fallback)
        final key = _getLegacyKey(institutionId);
        final encrypter = enc.Encrypter(enc.AES(key));
        final encrypted = encrypter.encrypt(plainText, iv: _globalIV);
        return 'ENC:${encrypted.base64}';
      }
    } catch (e) {
      print('⚠️ CryptoService.encrypt hatası: $e');
      return plainText;
    }
  }

  /// Şifreli Base64 verisini çözer. Şifreli değilse veya hata oluşursa orijinal metni döner.
  /// Hem yeni (dinamik IV) hem de eski (statik IV) şifreleme formatlarını otomatik tanır.
  static String decrypt(String? cipherText, {String? institutionId}) {
    if (cipherText == null || cipherText.trim().isEmpty) return '';
    if (!cipherText.startsWith('ENC:')) return cipherText; // Şifreli değil, aynen dön

    try {
      final body = cipherText.substring(4); // "ENC:" sonrasını al
      final parts = body.split(':');

      if (parts.length == 2) {
        // Yeni format: "ENC:iv_base64:ciphertext_base64"
        if (_serverKeyBase64 == null) {
          // Arka planda çekmeyi tetikle ama şimdilik çözemediğimiz için şifreli göster
          init();
          return cipherText;
        }
        final iv = enc.IV.fromBase64(parts[0]);
        final encryptedBase64 = parts[1];
        final key = enc.Key.fromBase64(_serverKeyBase64!);
        final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
        return encrypter.decrypt64(encryptedBase64, iv: iv);
      } else {
        // Eski format: "ENC:ciphertext_base64"
        final key = _getLegacyKey(institutionId);
        final encrypter = enc.Encrypter(enc.AES(key));
        return encrypter.decrypt64(body, iv: _globalIV);
      }
    } catch (e) {
      // Çözme başarısız olursa çökme yerine düz metni geri döndür (Graceful Fallback)
      return cipherText;
    }
  }

  /// Bellek cache'ini temizler (logout sırasında çağrılmalıdır)
  static void clearCache() {
    _serverKeyBase64 = null;
    _isFetching = false;
  }
}
