import 'dart:js_interop';

@JS('window.location.replace')
external void _replaceLocation(String url);

bool hardNavigateWeb(String path) {
  try {
    _replaceLocation(path);
    return true;
  } catch (_) {
    return false;
  }
}

