import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Uygulama açıkken gelen arka plan mesajlarını işler (top-level function gerekiyor)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Arka planda mesaj geldiğinde Firestore'a zaten Cloud Function yazmış olacak.
  // Burada ekstra işlem gerekmez.
  debugPrint('📬 Arka plan mesajı: ${message.messageId}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  
  /// Sayfa yönlendirmesi için navigator key (main.dart'taki ile aynı)
  static GlobalKey<NavigatorState>? navigatorKey;

  /// Servisi başlat: izin iste, token kaydet, listener'ları kur
  Future<void> initialize({required String uid}) async {
    // Arka plan handler'ı kaydet
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 1. İzin İste
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint('🔔 Bildirim izni: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('❌ Bildirim izni reddedildi.');
      return;
    }

    // 2. FCM Token Al ve Kaydet
    await _saveToken(uid);

    // 3. Token yenilenince güncelle
    _messaging.onTokenRefresh.listen((newToken) {
      _saveToken(uid, token: newToken);
    });

    // 4. Uygulama açıkken gelen bildirimleri dinle (Foreground)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('📩 Foreground mesaj: ${message.notification?.title}');
      // In-app bildirim zaten Firestore listener'ı ile gösterilecek.
      // Ek olarak snackbar gösterilebilir (opsiyonel).
    });

    // 5. Bildirime tıklanıp uygulama açıldığında (Background → Foreground)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('👆 Bildirime tıklandı (bg→fg): ${message.data}');
      _handleNotificationTap(message.data);
    });

    // 6. Uygulama kapalıyken bildirime tıklandığında (Terminated)
    final RemoteMessage? initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('👆 Uygulama açılış bildirimi: ${initialMessage.data}');
      // Kısa gecikme: Navigator hazır olsun
      Future.delayed(const Duration(milliseconds: 1500), () {
        _handleNotificationTap(initialMessage.data);
      });
    }
  }

  /// FCM token'ı Firestore'a kaydeder
  Future<void> _saveToken(String uid, {String? token}) async {
    try {
      String? fcmToken;
      
      if (kIsWeb) {
        // Web için VAPID key gerekiyor (Firebase Console > Project Settings > Cloud Messaging)
        try {
          fcmToken = await _messaging.getToken(
            vapidKey: 'BG8qZKjX_placeholder_replace_with_real_vapid_key',
          );
        } catch (e) {
          debugPrint('⚠️ Web FCM token alınamadı (VAPID key gerekli): $e');
          return;
        }
      } else {
        fcmToken = token ?? await _messaging.getToken();
      }

      if (fcmToken == null) {
        debugPrint('⚠️ FCM token alınamadı.');
        return;
      }

      debugPrint('✅ FCM Token: ${fcmToken.substring(0, 20)}...');

      // Firestore'daki users/{uid} belgesine token ekle (array olarak)
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'fcmTokens': FieldValue.arrayUnion([fcmToken]),
          'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        },
        SetOptions(merge: true),
      );

      debugPrint('✅ FCM token Firestore\'a kaydedildi.');
    } catch (e) {
      debugPrint('❌ FCM token kaydedilemedi: $e');
    }
  }

  /// Bildirime tıklandığında ilgili sayfaya yönlendir
  void _handleNotificationTap(Map<String, dynamic> data) {
    final route = data['route'] as String?;
    if (route == null || navigatorKey?.currentState == null) return;

    debugPrint('🧭 Yönlendirme: $route');

    switch (route) {
      case '/announcements':
        navigatorKey!.currentState!.pushNamed('/announcements');
        break;
      case '/school-dashboard':
        navigatorKey!.currentState!.pushNamed('/school-dashboard');
        break;
      default:
        navigatorKey!.currentState!.pushNamed('/school-dashboard');
        break;
    }
  }

  /// Çıkış yapınca token'ı Firestore'dan sil
  Future<void> removeToken() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final token = kIsWeb
          ? await _messaging.getToken(
              vapidKey: 'BG8qZKjX_placeholder_replace_with_real_vapid_key',
            )
          : await _messaging.getToken();

      if (token == null) return;

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmTokens': FieldValue.arrayRemove([token]),
      });

      debugPrint('🗑️ FCM token silindi.');
    } catch (e) {
      debugPrint('❌ FCM token silinemedi: $e');
    }
  }
}
