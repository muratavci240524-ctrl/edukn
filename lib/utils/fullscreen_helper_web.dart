// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

void toggleFullscreen(bool enter) {
  try {
    if (enter) {
      final docEl = html.document.documentElement;
      if (docEl != null && html.document.fullscreenElement == null) {
        docEl.requestFullscreen();
      }
    } else {
      if (html.document.fullscreenElement != null) {
        html.document.exitFullscreen();
      }
    }
  } catch (e) {
    // Tarayıcı izinleri veya durumu
  }
}

bool isFullscreen() {
  try {
    return html.document.fullscreenElement != null;
  } catch (_) {
    return false;
  }
}
