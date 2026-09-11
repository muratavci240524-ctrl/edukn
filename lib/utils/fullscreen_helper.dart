import 'fullscreen_helper_stub.dart'
    if (dart.library.html) 'fullscreen_helper_web.dart' as helper;

/// Tarayıcıyı F11 gibi gerçek HTML5 Tam Ekran yapar veya tam ekrandan çıkarır
void toggleBrowserFullscreen(bool enter) {
  helper.toggleFullscreen(enter);
}

/// Tarayıcının şu an tam ekranda olup olmadığını kontrol eder
bool isBrowserFullscreen() {
  return helper.isFullscreen();
}
