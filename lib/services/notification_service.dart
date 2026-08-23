import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'web_notification/web_notification.dart' if (dart.library.html) 'web_notification/web_notification_web.dart';

import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';

/// Uygulama kapalıyken veya arka plandayken gelen mesajları işler
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('📬 Arka plan mesajı: ${message.messageId}');
  
  final type = message.data['type'] ?? 'general';
  
  if (type == 'call_ended' && !kIsWeb) {
    debugPrint('🛑 Arama sonlandı sinyali alındı, çağrı kapatılıyor.');
    await FlutterCallkitIncoming.endAllCalls();
    return;
  }
  
  final isCall = message.data['isCall'] == 'true' || type == 'call';
  
  if (isCall && !kIsWeb) {
    final title = message.data['title'] ?? 'Gelen Arama';
    final body = message.data['body'] ?? '';
    final callerName = message.data['callerName'] ?? title.replaceAll('📹 ', '').replaceAll('📞 ', '');
    
    final callParams = CallKitParams(
      id: message.data['entityId'] ?? message.messageId ?? 'unknown_call',
      nameCaller: callerName,
      appName: 'eduKN',
      avatar: 'https://i.pravatar.cc/100', // Opsiyonel avatar URL'si
      handle: body,
      type: 0,
      duration: 30000,
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Cevapsız Arama',
        callbackText: 'Geri Ara',
      ),
      extra: <String, dynamic>{'route': message.data['route']},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: '', // Boş bırakınca sistemin varsayılan çalma sesine döner
        backgroundColor: '#0955fa',
        backgroundUrl: 'assets/test.png',
        actionColor: '#4CAF50',
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 2,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: true,
        supportsHolding: true,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );
    await FlutterCallkitIncoming.showCallkitIncoming(callParams);
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin? _localNotifications = kIsWeb ? null : FlutterLocalNotificationsPlugin();
  
  /// Sayfa yönlendirmesi için navigator key (main.dart'taki ile aynı)
  static GlobalKey<NavigatorState>? navigatorKey;

  bool _initialized = false;

  /// Servisi başlat: izin iste, token kaydet, listener'ları kur
  Future<void> initialize({required String uid}) async {
    if (_initialized) {
      debugPrint('🔔 NotificationService zaten başlatılmış, atlanıyor.');
      return;
    }
    _initialized = true;

    // Arka plan handler'ı kaydet
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    if (!kIsWeb) {
      const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings();
      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );
      await _localNotifications?.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationAction,
      );
      
      // Android için Heads-up notification kanalı (genel bildirimler)
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'high_importance_channel',
        'High Importance Notifications',
        description: 'This channel is used for important notifications.',
        importance: Importance.max,
      );
      await _localNotifications
          ?.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      // Android için Gelen Arama kanalı (zil sesi + titreşim)
      const AndroidNotificationChannel callChannel = AndroidNotificationChannel(
        'incoming_call_channel',
        'Gelen Aramalar',
        description: 'Sesli ve görüntülü arama bildirimleri.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
      );
      await _localNotifications
          ?.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(callChannel);
          
      // iOS için foreground Heads-up aktif et
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

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
      
      final title = message.notification?.title ?? message.data['title'] ?? 'Yeni Bildirim';
      final body = message.notification?.body ?? message.data['body'] ?? '';
      final type = message.data['type'] ?? 'general';
      
      if (type == 'call_ended' && !kIsWeb) {
        debugPrint('🛑 Arama sonlandı sinyali alındı (Foreground), çağrı kapatılıyor.');
        FlutterCallkitIncoming.endAllCalls();
        return;
      }
      
      final isCall = message.data['isCall'] == 'true' || type == 'call';

      if (kIsWeb) {
        showWebNotification(title, body);
      } else {
        if (isCall) {
          // 📞 Arama bildirimi: CallKit ile tam ekran VoIP çaldır
          final callerName = message.data['callerName'] ?? title.replaceAll('📹 ', '').replaceAll('📞 ', '');
          
          final callParams = CallKitParams(
            id: message.data['entityId'] ?? message.messageId ?? 'unknown_call',
            nameCaller: callerName,
            appName: 'eduKN',
            avatar: 'https://i.pravatar.cc/100', // Opsiyonel avatar URL'si
            handle: body,
            type: 0,
            duration: 30000,
            missedCallNotification: const NotificationParams(
              showNotification: true,
              isShowCallback: true,
              subtitle: 'Cevapsız Arama',
              callbackText: 'Geri Ara',
            ),
            extra: <String, dynamic>{'route': message.data['route']},
            android: const AndroidParams(
              isCustomNotification: true,
              isShowLogo: false,
              ringtonePath: '', // Boş bırakınca sistemin varsayılan çalma sesine döner
              backgroundColor: '#0955fa',
              backgroundUrl: 'assets/test.png',
              actionColor: '#4CAF50',
            ),
            ios: const IOSParams(
              iconName: 'CallKitLogo',
              handleType: 'generic',
              supportsVideo: true,
              maximumCallGroups: 2,
              maximumCallsPerCallGroup: 1,
              audioSessionMode: 'default',
              audioSessionActive: true,
              audioSessionPreferredSampleRate: 44100.0,
              audioSessionPreferredIOBufferDuration: 0.005,
              supportsDTMF: true,
              supportsHolding: true,
              supportsGrouping: false,
              supportsUngrouping: false,
              ringtonePath: 'system_ringtone_default',
            ),
          );
          FlutterCallkitIncoming.showCallkitIncoming(callParams);
        } else {
          // 📩 Normal bildirim
          _localNotifications?.show(
            id: message.hashCode,
            title: title,
            body: body,
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'high_importance_channel',
                'High Importance Notifications',
                channelDescription: 'This channel is used for important notifications.',
                importance: Importance.max,
                priority: Priority.high,
                icon: '@mipmap/ic_launcher',
              ),
              iOS: DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
            ),
          );
        }
      }
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

    if (!kIsWeb) {
      FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
        if (event is CallEventActionCallAccept) {
          debugPrint('✅ Arama kabul edildi: ${event.callKitParams.id}');
          final route = event.callKitParams.extra?['route'] as String?;
          if (route != null) {
            _handleNotificationTap({'route': route});
          }
        } else if (event is CallEventActionCallDecline) {
          debugPrint('❌ Arama reddedildi: ${event.callKitParams.id}');
        }
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
            vapidKey: 'BFbtofT_FGdqCvPYbSgZ_ggmb-JVGf7mYZhZWXE8v1dfAcw7kbJN_KvrUKV4hgBxXzdBbj-L8AtJw5VzKQQE8nE',
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

  /// Bildirim butonlarına (Yanıtla/Reddet) tıklandığında
  void _onNotificationAction(NotificationResponse response) {
    debugPrint('🔔 Bildirim aksiyonu: ${response.actionId} (payload: ${response.payload})');

    switch (response.actionId) {
      case 'answer_call':
        debugPrint('✅ Arama yanıtlandı');
        // Arama ekranını aç
        if (navigatorKey?.currentState != null) {
          navigatorKey!.currentState!.pushNamed('/school-dashboard');
        }
        break;
      case 'decline_call':
        debugPrint('❌ Arama reddedildi');
        // Bildirimi kapat (cancelNotification: true zaten yapıyor)
        break;
      default:
        // Normal bildirime tıklandı
        _handleNotificationTap({'route': '/school-dashboard'});
        break;
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
              vapidKey: 'BFbtofT_FGdqCvPYbSgZ_ggmb-JVGf7mYZhZWXE8v1dfAcw7kbJN_KvrUKV4hgBxXzdBbj-L8AtJw5VzKQQE8nE',
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
