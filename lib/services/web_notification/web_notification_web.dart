import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;

void showWebNotification(String title, String body) {
  try {
    final permission = js.context['Notification']?['permission'];
    js.context['console'].callMethod('log', ['🌐 Web Push Tetiklendi: $title - $body']);
    js.context['console'].callMethod('log', ['🌐 İzin Durumu: $permission']);

    if (permission == 'granted') {
      final safeTitle = title.replaceAll("'", "\\'").replaceAll('"', '\\"').replaceAll('\n', ' ');
      final safeBody = body.replaceAll("'", "\\'").replaceAll('"', '\\"').replaceAll('\n', ' ');
      
      // Service Worker üzerinden bildirim göster
      // Bu yöntem sayfa aktifken (foreground) bile çalışır
      js.context.callMethod('eval', [
        '''
        (function() {
          if ('serviceWorker' in navigator && navigator.serviceWorker.controller) {
            navigator.serviceWorker.ready.then(function(registration) {
              registration.showNotification("$safeTitle", {
                body: "$safeBody",
                icon: "icons/Icon-192.png",
                badge: "icons/Icon-192.png",
                tag: "edukn-" + Date.now(),
                requireInteraction: false,
                vibrate: [200, 100, 200],
                data: { route: "/school-dashboard" }
              });
              console.log("✅ Service Worker Notification gösterildi!");
            }).catch(function(err) {
              console.error("❌ SW showNotification hatası:", err);
              // Fallback: doğrudan Notification API
              try {
                new Notification("$safeTitle", {body: "$safeBody", icon: "icons/Icon-192.png"});
                console.log("✅ Fallback Notification gösterildi.");
              } catch(e2) {
                console.error("❌ Fallback Notification hatası:", e2);
              }
            });
          } else {
            // Service Worker yoksa doğrudan Notification API
            console.log("⚠️ Service Worker yok, doğrudan Notification API kullanılıyor.");
            try {
              new Notification("$safeTitle", {body: "$safeBody", icon: "icons/Icon-192.png"});
              console.log("✅ Direct Notification gösterildi.");
            } catch(e) {
              console.error("❌ Direct Notification hatası:", e);
            }
          }
        })();
        '''
      ]);
    } else if (permission != 'denied') {
      js.context['console'].callMethod('log', ['⏳ İzin isteniyor...']);
      js.context.callMethod('eval', [
        '''
        Notification.requestPermission().then(function(perm) {
          if (perm === "granted") {
            if (navigator.serviceWorker && navigator.serviceWorker.controller) {
              navigator.serviceWorker.ready.then(function(reg) {
                reg.showNotification("$title", {body: "$body", icon: "icons/Icon-192.png"});
              });
            } else {
              new Notification("$title", {body: "$body", icon: "icons/Icon-192.png"});
            }
          }
        });
        '''
      ]);
    } else {
      js.context['console'].callMethod('log', ['❌ Bildirim izni önceden reddedilmiş (denied).']);
    }
  } catch (e) {
    js.context['console'].callMethod('log', ['❌ Web Notification hatası: $e']);
  }
}

/// Bildirim API'sinin bu tarayıcıda desteklenip desteklenmediğini kontrol eder
bool isNotificationSupported() {
  try {
    return html.Notification.supported;
  } catch (_) {
    return false;
  }
}

/// Mevcut bildirim izin durumunu döner: 'granted', 'denied', 'default', 'unsupported'
String getWebNotificationPermissionStatus() {
  try {
    if (!html.Notification.supported) {
      return 'unsupported';
    }
    return html.Notification.permission ?? 'default';
  } catch (_) {
    return 'unsupported';
  }
}

/// Kullanıcının iOS (iPhone, iPad, iPod) üzerinde olup olmadığını anlar
bool isIosWeb() {
  try {
    final ua = html.window.navigator.userAgent.toLowerCase();
    return ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');
  } catch (_) {
    return false;
  }
}

/// iOS veya Android'de uygulamanın PWA (Ana Ekrana Eklendi) olarak açılıp açılmadığını anlar
bool isStandalonePwa() {
  try {
    final isIosStandalone = js.context['navigator']?['standalone'] == true;
    if (isIosStandalone) return true;

    final matchMedia = html.window.matchMedia('(display-mode: standalone)');
    return matchMedia.matches;
  } catch (_) {
    return false;
  }
}

/// Kullanıcı bir butona bastığında doğrudan sistem bildirim iznini ister
Future<String?> requestWebNotificationPermission() async {
  try {
    if (!html.Notification.supported) {
      js.context['console'].callMethod('log', ['⚠️ Bu tarayıcıda Notification API desteklenmiyor.']);
      return 'unsupported';
    }

    final currentPerm = html.Notification.permission;
    if (currentPerm == 'granted') {
      return 'granted';
    }

    js.context['console'].callMethod('log', ['🌐 Tarayıcı bildirim izni isteniyor...']);
    final permission = await html.Notification.requestPermission();
    js.context['console'].callMethod('log', ['🌐 Tarayıcı bildirim izni sonucu: $permission']);
    return permission;
  } catch (e) {
    js.context['console']?.callMethod('log', ['❌ requestWebNotificationPermission hatası: $e']);
    return null;
  }
}

