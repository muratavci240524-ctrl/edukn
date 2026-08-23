import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

@JS('window.location.reload')
external void _reloadPage(bool forceGet);

@JS('window.onPwaUpdateAvailable')
external set _onPwaUpdateAvailable(JSFunction? callback);

class PwaUpdateService {
  static void initialize(GlobalKey<NavigatorState> navigatorKey) {
    if (!kIsWeb) return;

    _onPwaUpdateAvailable = () {
      _showUpdateDialog(navigatorKey);
    }.toJS;
  }

  static void _showUpdateDialog(GlobalKey<NavigatorState> navigatorKey) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          title: Row(
            children: const [
              Icon(Icons.system_update_rounded, color: Colors.blue, size: 28),
              SizedBox(width: 10),
              Text('Yeni Sürüm Mevcut'),
            ],
          ),
          content: const Text(
            'Uygulamanın yeni bir sürümü yayınlandı.\n\nGüncel sürümü kullanmak ve yenilikleri görmek için lütfen uygulamayı yenileyin.',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            ElevatedButton.icon(
              onPressed: () {
                _reloadPage(true);
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Yenile / Güncelle'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        );
      },
    );
  }
}
