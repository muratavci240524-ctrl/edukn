void showWebNotification(String title, String body) {
  // Sadece web'de çalışacak
}

Future<String?> requestWebNotificationPermission() async {
  // Sadece web'de çalışacak
  return null;
}

String getWebNotificationPermissionStatus() {
  return 'unsupported';
}

bool isIosWeb() {
  return false;
}

bool isStandalonePwa() {
  return false;
}

bool isNotificationSupported() {
  return false;
}
