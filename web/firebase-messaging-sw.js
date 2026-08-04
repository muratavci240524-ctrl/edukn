// Firebase Cloud Messaging Service Worker
// Bu dosya web'de uygulama kapalıyken de bildirimleri alır

// FCM Service Worker does not claim clients to avoid conflicts with main app routing.

importScripts('https://www.gstatic.com/firebasejs/9.23.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.23.0/firebase-messaging-compat.js');

// Firebase Yapılandırması (firebase_options.dart ile aynı web config)
firebase.initializeApp({
  apiKey: 'AIzaSyA3rUxB--1WMG1p1Rbqn4y8i918OTI_vPk',
  authDomain: 'edukn-23036.firebaseapp.com',
  projectId: 'edukn-23036',
  storageBucket: 'edukn-23036.firebasestorage.app',
  messagingSenderId: '158619513037',
  appId: '1:158619513037:web:72ea508d1c57c6a50eb984',
  measurementId: 'G-FN2B30TL7H',
});

const messaging = firebase.messaging();

// Arka planda gelen bildirimleri göster
messaging.onBackgroundMessage((payload) => {
  console.log('[SW] Arka plan bildirimi alındı:', payload);

  // Eğer payload'da "notification" alanı varsa, FCM otomatik olarak bildirim çıkaracaktır.
  // Bu durumda manuel olarak showNotification çağırmamıza gerek yok (Çift bildirim olmaması için).
  // Ancak bazen Firebase otomatik çıkarmayabiliyor (data-only mesajlarda). 
  if (payload.notification) {
     console.log('[SW] FCM bildirimi otomatik gösterecek.');
     return;
  }

  const notificationTitle = payload.data?.title || 'eduKN';
  const notificationOptions = {
    body: payload.data?.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: payload.data || {},
    tag: payload.data?.notifId || 'edukn-notif',
    requireInteraction: false,
    vibrate: [200, 100, 200],
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});

// Bildirime tıklandığında (veya butonlara basıldığında)
self.addEventListener('notificationclick', (event) => {
  console.log('[SW] Bildirime tıklandı:', event.action || 'ana_tıklama');
  event.notification.close();

  const action = event.action; // "answer" veya "decline"
  const route = event.notification.data?.route || '/';
  const urlToOpen = new URL(route, self.location.origin).href;

  // Reddet butonuna basıldıysa sadece bildirimi kapat
  if (action === 'decline') {
    console.log('[SW] Arama reddedildi.');
    return;
  }

  // Yanıtla veya normal tıklama → uygulamayı aç
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
      // Açık pencere varsa onu öne getir
      for (const client of windowClients) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          client.focus();
          client.postMessage({ 
            type: action === 'answer' ? 'CALL_ANSWERED' : 'NOTIFICATION_CLICK', 
            route: route 
          });
          return;
        }
      }
      // Açık pencere yoksa yeni tab aç
      if (clients.openWindow) {
        return clients.openWindow(urlToOpen);
      }
    })
  );
});
