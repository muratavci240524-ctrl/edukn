import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';

class PerformanceScreen extends StatelessWidget {
  static const routeName = '/hr/performance';
  const PerformanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: EduknAppBar(title: 'Performans ve Değerlendirme'),
      body: const Center(child: Text('Hedefler ve değerlendirme iskeleti')), 
    );
  }
}
