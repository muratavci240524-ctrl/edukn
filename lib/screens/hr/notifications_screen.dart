import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';

class NotificationsScreen extends StatelessWidget {
  static const routeName = '/hr/notifications';
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: EduknAppBar(title: 'Bildirim ve Hatırlatma'),
      body: const Center(child: Text('Bildirim kuralları iskeleti')), 
    );
  }
}
