import 'package:flutter_local_notifications/flutter_local_notifications.dart'; void main() async { final l = FlutterLocalNotificationsPlugin(); await l.initialize(); await l.show(0, '', '', null); }
