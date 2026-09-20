import 'dart:js_interop';

@JS('hideLoadingSplash')
external void _hideLoadingSplash();

void hideSplash() {
  try {
    _hideLoadingSplash();
  } catch (_) {
    // Ignore if not running in a browser with the splash function
  }
}
