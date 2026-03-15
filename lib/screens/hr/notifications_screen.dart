import 'package:flutter/material.dart';

class NotificationsScreen extends StatelessWidget {
  static const routeName = '/hr/notifications';
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bildirim ve Hatırlatma')),
      body: const Center(child: Text('Bildirim kuralları iskeleti')), 
    );
  }
}
