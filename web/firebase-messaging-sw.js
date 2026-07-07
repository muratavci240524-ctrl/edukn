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

  const notificationTitle = payload.notification?.title || 'eduKN';
  const notificationOptions = {
    body: payload.notification?.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: payload.data || {},
    tag: payload.data?.notifId || 'edukn-notif',
    requireInteraction: false,
    vibrate: [200, 100, 200],
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});

// Bildirime tıklandığında
self.addEventListener('notificationclick', (event) => {
  console.log('[SW] Bildirime tıklandı:', event);
  event.notification.close();

  const route = event.notification.data?.route || '/';
  const urlToOpen = new URL(route, self.location.origin).href;

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
      // Açık pencere varsa onu öne getir
      for (const client of windowClients) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          client.focus();
          client.postMessage({ type: 'NOTIFICATION_CLICK', route: route });
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
