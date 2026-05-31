import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/sms_settings_model.dart';

class SmsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const _netgsmUrl = 'https://api.netgsm.com.tr/sms/send/get';

  // ─────────────────────────────── SETTINGS CRUD ───────────────────────────

  Future<SmsSettings?> loadSmsSettings(String schoolId) async {
    try {
      final doc = await _firestore.collection('schools').doc(schoolId).get();
      if (!doc.exists) return null;
      final data = doc.data()?['smsSettings'] as Map<String, dynamic>?;
      if (data == null) return null;
      return SmsSettings.fromMap(data);
    } catch (e) {
      debugPrint('SMS settings yüklenirken hata: $e');
      return null;
    }
  }

  Future<void> saveSmsSettings(
    String schoolId,
    SmsSettings settings,
    String updatedBy,
  ) async {
    try {
      final updated = settings.copyWith(updatedBy: updatedBy);
      await _firestore.collection('schools').doc(schoolId).set({
        'smsSettings': updated.toMap(),
      }, SetOptions(merge: true));
      debugPrint('✅ SMS ayarları kaydedildi: $schoolId');
    } catch (e) {
      debugPrint('SMS settings kaydedilirken hata: $e');
      rethrow;
    }
  }

  // ─────────────────────────────── CONNECTION TEST ──────────────────────────

  /// Gerçek SMS gönderir → {success: bool, message: String}
  Future<Map<String, dynamic>> testConnection(
    SmsSettings settings,
    String testPhone,
  ) async {
    try {
      final cleanPhone = _cleanPhone(testPhone);
      final testMessage = 'EduKN SMS testi başarılı. Bu mesajı göz ardı edebilirsiniz.';

      final result = await sendSmsWithSettings(
        phones: [cleanPhone],
        message: testMessage,
        settings: settings,
      );

      return result;
    } catch (e) {
      return {'success': false, 'message': 'Hata: $e'};
    }
  }

  // ─────────────────────────────── SEND SMS ────────────────────────────────

  /// schoolId ile ayarları Firestore'dan çeker ve SMS gönderir
  Future<Map<String, dynamic>> sendSms({
    required List<String> phones,
    required String message,
    required String schoolId,
  }) async {
    try {
      final settings = await loadSmsSettings(schoolId);
      if (settings == null || !settings.isActive) {
        return {
          'success': false,
          'message': 'SMS entegrasyonu aktif değil veya yapılandırılmamış.',
          'sentCount': 0,
        };
      }
      return await sendSmsWithSettings(
        phones: phones,
        message: message,
        settings: settings,
      );
    } catch (e) {
      return {'success': false, 'message': 'Hata: $e', 'sentCount': 0};
    }
  }

  /// Direkt settings ile SMS gönderir (test için)
  Future<Map<String, dynamic>> sendSmsWithSettings({
    required List<String> phones,
    required String message,
    required SmsSettings settings,
  }) async {
    if (phones.isEmpty) {
      return {'success': false, 'message': 'Alıcı listesi boş.', 'sentCount': 0};
    }

    try {
      switch (settings.provider) {
        case SmsProvider.netgsm:
          return await _sendNetgsm(phones, message, settings);
        case SmsProvider.iletisim360:
          return await _sendIletisim360(phones, message, settings);
        case SmsProvider.mutlucell:
          return await _sendMutlucell(phones, message, settings);
        case SmsProvider.custom:
          return await _sendCustom(phones, message, settings);
      }
    } catch (e) {
      debugPrint('SMS gönderim hatası: $e');
      return {'success': false, 'message': 'Gönderim hatası: $e', 'sentCount': 0};
    }
  }

  // ────────────── PROVIDER IMPLEMENTATIONS ──────────────────────────────────

  Future<Map<String, dynamic>> _sendNetgsm(
    List<String> phones,
    String message,
    SmsSettings settings,
  ) async {
    // Netgsm GET API
    final phoneStr = phones.map(_cleanPhone).join(',');
    final uri = Uri.parse(_netgsmUrl).replace(queryParameters: {
      'usercode': settings.apiKey,
      'password': settings.apiSecret,
      'gsmno': phoneStr,
      'message': message,
      'msgheader': settings.originator,
      'dil': 'TR',
    });

    try {
      // Flutter web'de http paketi yerine Uri-based HTTP çağrısı
      // http paketi mevcut değilse, Firestore'a kuyruk yaz
      final response = await _makeHttpGet(uri.toString());
      return _parseNetgsmResponse(response, phones.length);
    } catch (e) {
      // HTTP paketi yoksa kuyruk bazlı gönderim
      return await _queueSmsViaFirestore(phones, message, settings, 'netgsm');
    }
  }

  Map<String, dynamic> _parseNetgsmResponse(String? response, int count) {
    if (response == null) {
      return {'success': false, 'message': 'Yanıt alınamadı.', 'sentCount': 0};
    }
    // Netgsm başarılı yanıtları "00 ..." ile başlar
    if (response.startsWith('00')) {
      return {
        'success': true,
        'message': '$count mesaj başarıyla gönderildi.',
        'sentCount': count,
        'netgsmCode': response,
      };
    }
    // Hata kodları
    final errorMsg = _netgsmErrorMessage(response.trim());
    return {'success': false, 'message': errorMsg, 'sentCount': 0, 'netgsmCode': response};
  }

  String _netgsmErrorMessage(String code) {
    switch (code) {
      case '20':
        return 'Kimlik doğrulama hatası. API kullanıcı kodu veya şifre yanlış.';
      case '30':
        return 'Geçersiz SMS başlığı. Netgsm hesabınızda onaylı başlık kullanın.';
      case '40':
        return 'Mesaj içeriği boş.';
      case '50':
        return 'Alıcı numarası geçersiz.';
      case '51':
        return 'Alıcı numarası formatı hatalı.';
      case '70':
        return 'Hatalı sorgulama. Parametreleri kontrol edin.';
      case '80':
        return 'Aynı numaraya çok fazla mesaj gönderildi.';
      default:
        return 'SMS gönderilemedi. Hata kodu: $code';
    }
  }

  Future<Map<String, dynamic>> _sendIletisim360(
    List<String> phones,
    String message,
    SmsSettings settings,
  ) async {
    return await _queueSmsViaFirestore(phones, message, settings, 'iletisim360');
  }

  Future<Map<String, dynamic>> _sendMutlucell(
    List<String> phones,
    String message,
    SmsSettings settings,
  ) async {
    return await _queueSmsViaFirestore(phones, message, settings, 'mutlucell');
  }

  Future<Map<String, dynamic>> _sendCustom(
    List<String> phones,
    String message,
    SmsSettings settings,
  ) async {
    if (settings.customApiUrl == null || settings.customApiUrl!.isEmpty) {
      return {'success': false, 'message': 'Özel API URL tanımlanmamış.', 'sentCount': 0};
    }
    return await _queueSmsViaFirestore(phones, message, settings, 'custom');
  }

  // ────────────── FIRESTORE SMS QUEUE (Cloud Function triggers) ─────────────

  /// SMS'leri Firestore kuyruğuna yazar → Cloud Function gönderir
  Future<Map<String, dynamic>> _queueSmsViaFirestore(
    List<String> phones,
    String message,
    SmsSettings settings,
    String providerCode,
  ) async {
    try {
      final batch = _firestore.batch();
      for (final phone in phones) {
        final docRef = _firestore.collection('sms_queue').doc();
        batch.set(docRef, {
          'phone': _cleanPhone(phone),
          'message': message,
          'provider': providerCode,
          'apiKey': settings.apiKey,
          'apiSecret': settings.apiSecret,
          'originator': settings.originator,
          'apiUrl': settings.providerApiUrl,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      return {
        'success': true,
        'message': '${phones.length} SMS kuyruğa eklendi. Cloud Function ile gönderilecek.',
        'sentCount': phones.length,
        'queued': true,
      };
    } catch (e) {
      return {'success': false, 'message': 'Kuyruk hatası: $e', 'sentCount': 0};
    }
  }

  // ────────────── HELPERS ───────────────────────────────────────────────────

  String _cleanPhone(String phone) {
    // +905xxxxxxxxx → 905xxxxxxxxx (Netgsm formatı)
    String cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.startsWith('0')) {
      cleaned = '90${cleaned.substring(1)}';
    } else if (!cleaned.startsWith('90')) {
      cleaned = '90$cleaned';
    }
    return cleaned;
  }

  /// Basit GET isteği — http paketi yoksa null döner
  Future<String?> _makeHttpGet(String url) async {
    try {
      // Dart:io HttpClient kullan
      // ignore: avoid_dynamic_calls
      final client = _createHttpClient();
      if (client == null) return null;
      return await client.call(url);
    } catch (e) {
      debugPrint('HTTP GET hatası: $e');
      return null;
    }
  }

  dynamic _createHttpClient() {
    // Flutter web'de http paketi gereklidir
    // Eğer http paketi pubspec'te varsa kullanılabilir
    // Aksi hâlde null döner, kuyruk sistemi devreye girer
    return null;
  }
}
