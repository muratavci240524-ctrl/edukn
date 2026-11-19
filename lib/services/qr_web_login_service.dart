import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'user_permission_service.dart';

class QrLoginChallenge {
  final String sessionId;
  final String sessionKey;
  final DateTime createdAt;

  const QrLoginChallenge({
    required this.sessionId,
    required this.sessionKey,
    required this.createdAt,
  });

  String get qrData => 'edukn_qr_login:$sessionId:$sessionKey';

  String get docId => 'qr_login_$sessionId';
}

class QrWebLoginService {
  static const String qrPrefix = 'edukn_qr_login:';
  static const String _collectionName = 'pre_registration_settings';
  static const String _chars =
      'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz0123456789';

  static String _randomString(int length) {
    final rnd = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(
        length,
        (_) => _chars.codeUnitAt(rnd.nextInt(_chars.length)),
      ),
    );
  }

  /// Web giriş ekranında gösterilecek yeni bir QR oturum anahtarı üretir.
  static QrLoginChallenge createChallenge() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final sessionId = '${ts}_${_randomString(14)}';
    final sessionKey = _randomString(32); // 256-bit AES key
    return QrLoginChallenge(
      sessionId: sessionId,
      sessionKey: sessionKey,
      createdAt: DateTime.now(),
    );
  }

  /// QR verisinin Web Oturum Açma QR kodu olup olmadığını kontrol eder.
  static bool isWebLoginQr(String? rawCode) {
    if (rawCode == null) return false;
    return rawCode.trim().startsWith(qrPrefix);
  }

  /// Manuel giriş veya şifre değişimi sırasında cihazda aktif şifreyi önbelleğe alır.
  static Future<void> saveLocalAuthCredentials({
    required String email,
    required String password,
    String? institutionId,
    String? username,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('qr_auth_email', email.trim());
      await prefs.setString('qr_auth_pass', password);
      if (institutionId != null && institutionId.isNotEmpty) {
        await prefs.setString('qr_auth_inst', institutionId.trim().toUpperCase());
      }
      if (username != null && username.isNotEmpty) {
        await prefs.setString('qr_auth_user', username.trim());
      }
    } catch (_) {}
  }

  static String _encryptPayload(Map<String, dynamic> payload, String sessionKey) {
    final keyBytes = Uint8List.fromList(utf8.encode(sessionKey).take(32).toList());
    final key = enc.Key(keyBytes);
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final jsonStr = json.encode(payload);
    final encrypted = encrypter.encrypt(jsonStr, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
  }

  static Map<String, dynamic>? decryptPayload(
    String encryptedPayload,
    String sessionKey,
  ) {
    try {
      final parts = encryptedPayload.split(':');
      if (parts.length != 2) return null;
      final keyBytes =
          Uint8List.fromList(utf8.encode(sessionKey).take(32).toList());
      final key = enc.Key(keyBytes);
      final iv = enc.IV.fromBase64(parts[0]);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final decrypted = encrypter.decrypt64(parts[1], iv: iv);
      return Map<String, dynamic>.from(json.decode(decrypted) as Map);
    } catch (e) {
      debugPrint('⚠️ QrWebLoginService.decryptPayload hatası: $e');
      return null;
    }
  }

  /// Web tarafında QR oturum belgesini gerçek zamanlı dinler.
  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchChallenge(
    QrLoginChallenge challenge,
  ) {
    return FirebaseFirestore.instance
        .collection(_collectionName)
        .doc(challenge.docId)
        .snapshots();
  }

  /// Web tarafında oturum açıldıktan veya pencere kapatıldıktan sonra geçici belgeyi siler.
  static Future<void> cleanupChallenge(QrLoginChallenge challenge) async {
    try {
      if (FirebaseAuth.instance.currentUser != null) {
        await FirebaseFirestore.instance
            .collection(_collectionName)
            .doc(challenge.docId)
            .delete();
      }
    } catch (_) {}
  }

  /// REST API üzerinden mevcut şifrenin Firebase Auth'ta geçerli olup olmadığını
  /// mobil oturumu bozmadan kontrol eder.
  static Future<bool> _verifyPasswordViaRest(
    String email,
    String password,
  ) async {
    if (email.isEmpty || password.isEmpty) return false;
    try {
      final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
      final url =
          'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey';
      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'email': email,
              'password': password,
              'returnSecureToken': false,
            }),
          )
          .timeout(const Duration(seconds: 6));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Mobil cihazdan QR okutulduğunda Web oturumunu onaylar ve şifreli bilgileri iletir.
  static Future<String> approveSessionFromQr(String rawQrData) async {
    final trimmed = rawQrData.trim();
    if (!trimmed.startsWith(qrPrefix)) {
      throw 'Geçersiz QR kodu. Lütfen Web giriş ekranındaki "QR Kod" penceresini okutun.';
    }

    final body = trimmed.substring(qrPrefix.length);
    final firstColon = body.indexOf(':');
    if (firstColon <= 0 || firstColon >= body.length - 1) {
      throw 'QR kodu formatı doğrulanamadı. Lütfen Web ekranındaki QR kodu yenileyin.';
    }

    final sessionId = body.substring(0, firstColon).trim();
    final sessionKey = body.substring(firstColon + 1).trim();
    if (sessionId.isEmpty || sessionKey.length < 32) {
      throw 'QR kodu güvenlik anahtarı geçersiz veya eksik.';
    }

    // Süre kontrolü (5 dakika)
    final underscoreIdx = sessionId.indexOf('_');
    if (underscoreIdx > 0) {
      final qrTs = int.tryParse(sessionId.substring(0, underscoreIdx)) ?? 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (qrTs > 0 && (nowMs - qrTs).abs() > 5 * 60 * 1000) {
        throw 'QR kodunun süresi dolmuş. Lütfen Web ekranında QR penceresini kapatıp tekrar açın.';
      }
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw 'Mobil cihazda aktif bir oturum bulunamadı.';
    }

    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic>? userData =
        UserPermissionService.getCachedUserData() ??
        await UserPermissionService.loadUserData();

    // Taze kullanıcı dokümanını da kontrol et (şifre alanı için)
    final userDocId = (userData?['id'] ?? user.uid).toString();
    try {
      final freshDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userDocId)
          .get();
      if (freshDoc.exists && freshDoc.data() != null) {
        userData = {
          ...?userData,
          ...freshDoc.data()!,
          'id': freshDoc.id,
        };
      }
    } catch (_) {}

    final authEmail = (user.email ?? userData?['email'] ?? '').toString().trim();
    if (authEmail.isEmpty) {
      throw 'Hesabınıza bağlı e-posta kimliği bulunamadı.';
    }

    String institutionId = (userData?['institutionId'] ??
            prefs.getString('qr_auth_inst') ??
            '')
        .toString()
        .trim()
        .toUpperCase();
    if (institutionId.isEmpty) {
      institutionId = await UserPermissionService.resolveInstitutionId(
        authEmail,
        userData: userData,
      );
    }

    // Olası şifre adaylarını topla
    final candidatePasswords = <String>[];
    void addCandidate(dynamic val) {
      final s = (val ?? '').toString().trim();
      if (s.isNotEmpty && !candidatePasswords.contains(s)) {
        candidatePasswords.add(s);
      }
    }

    addCandidate(prefs.getString('qr_auth_pass'));
    addCandidate(userData?['password']);
    addCandidate(userData?['_tempPassword']);
    addCandidate(userData?['defaultPassword']);

    final role = (userData?['role'] ?? '').toString().toLowerCase().trim();
    final username = (userData?['username'] ??
            prefs.getString('qr_auth_user') ??
            authEmail.split('@').first)
        .toString()
        .trim();

    // Okul yöneticisi ise schools koleksiyonundaki adminPassword'ü de kontrol et
    if (institutionId.isNotEmpty &&
        (role == 'admin' || role == 'genel_mudur' || candidatePasswords.isEmpty)) {
      try {
        final sQuery = await FirebaseFirestore.instance
            .collection('schools')
            .where('institutionId', isEqualTo: institutionId)
            .limit(1)
            .get();
        if (sQuery.docs.isNotEmpty) {
          addCandidate(sQuery.docs.first.data()['adminPassword']);
        }
      } catch (_) {}
    }

    // Öğrenci veya veli ise kendi koleksiyonundaki şifreyi de kontrol et
    if (institutionId.isNotEmpty &&
        (role == 'student' ||
            role == 'ogrenci' ||
            role == 'öğrenci' ||
            role == 'parent' ||
            role == 'veli' ||
            candidatePasswords.isEmpty)) {
      try {
        final selectedStId =
            prefs.getString('selected_student_id_${user.uid}') ??
            prefs.getString('selected_student_id') ??
            userData?['studentId']?.toString();
        if (selectedStId != null && selectedStId.isNotEmpty) {
          final stDoc = await FirebaseFirestore.instance
              .collection('students')
              .doc(selectedStId)
              .get();
          if (stDoc.exists) {
            addCandidate(stDoc.data()?['password']);
          }
        }
        if (username.isNotEmpty) {
          final pQuery = await FirebaseFirestore.instance
              .collection('parents')
              .where('institutionId', isEqualTo: institutionId)
              .where('username', isEqualTo: username.toLowerCase())
              .limit(1)
              .get();
          if (pQuery.docs.isNotEmpty) {
            addCandidate(pQuery.docs.first.data()['password']);
          }
        }
      } catch (_) {}
    }

    addCandidate('123456');

    String? verifiedPassword;
    for (final candidate in candidatePasswords) {
      if (await _verifyPasswordViaRest(authEmail, candidate)) {
        verifiedPassword = candidate;
        break;
      }
    }

    // Eğer hiçbir aday şifre eşleşmediyse (örn. Google ile giriş yapılmış hesap),
    // mevcut updateUserCredentials Cloud Function ile kullanıcının kendi hesabına şifre tanımla
    if (verifiedPassword == null) {
      final fallbackPass = (userData?['password']?.toString().trim().length ?? 0) >= 6
          ? userData!['password'].toString().trim()
          : 'EduKn_${_randomString(10)}!';
      try {
        await FirebaseFunctions.instance
            .httpsCallable('updateUserCredentials')
            .call({
              'uid': user.uid,
              'newPassword': fallbackPass,
            });
        verifiedPassword = fallbackPass;
        await saveLocalAuthCredentials(
          email: authEmail,
          password: verifiedPassword,
          institutionId: institutionId,
          username: username,
        );
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userDocId)
              .set({'password': verifiedPassword}, SetOptions(merge: true));
        } catch (_) {}
      } catch (e) {
        debugPrint('⚠️ QR şifre senkronizasyon hatası: $e');
        if (candidatePasswords.isNotEmpty) {
          verifiedPassword = candidatePasswords.first;
        } else {
          throw 'Web oturumu için kimlik doğrulama anahtarı oluşturulamadı.';
        }
      }
    } else {
      await saveLocalAuthCredentials(
        email: authEmail,
        password: verifiedPassword,
        institutionId: institutionId,
        username: username,
      );
    }

    final activePortal = prefs.getString('active_portal') ?? '';
    final selectedStudentId =
        prefs.getString('selected_student_id_${user.uid}') ??
        prefs.getString('selected_student_id') ??
        '';
    final selectedStudentName =
        prefs.getString('selected_student_name') ?? '';
    final displayName = (userData?['fullName'] ??
            userData?['name'] ??
            user.displayName ??
            username)
        .toString()
        .trim();

    final payload = <String, dynamic>{
      'uid': user.uid,
      'email': authEmail,
      'password': verifiedPassword,
      'institutionId': institutionId,
      'username': username,
      'userDocId': userDocId,
      'role': role,
      'activePortal': activePortal,
      'selectedStudentId': selectedStudentId,
      'selectedStudentName': selectedStudentName,
      'displayName': displayName,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };

    final encryptedPayload = _encryptPayload(payload, sessionKey);

    await FirebaseFirestore.instance
        .collection(_collectionName)
        .doc('qr_login_$sessionId')
        .set({
          'type': 'qr_login_session',
          'status': 'approved',
          'payloadEnc': encryptedPayload,
          'displayName': displayName,
          'approvedByUid': user.uid,
          'approvedAt': FieldValue.serverTimestamp(),
        });

    return displayName.isNotEmpty ? displayName : authEmail;
  }
}
