import 'splash_service_stub.dart'
    if (dart.library.js) 'splash_service_web.dart';

class SplashService {
  static bool _hidden = false;

  /// Web üzerindeki HTML açılış animasyonunu (splash screen) gizler.
  /// Flutter arka planda oturumu kontrol edip hedef ekranı (Dashboard veya Giriş Formu)
  /// tamamen hazır hale getirdiğinde bu metot çağrılır.
  static void hide() {
    if (_hidden) return;
    _hidden = true;
    hideSplash();
  }
}
