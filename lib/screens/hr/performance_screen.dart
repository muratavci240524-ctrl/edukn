import 'package:flutter/material.dart';

class PerformanceScreen extends StatelessWidget {
  static const routeName = '/hr/performance';
  const PerformanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Performans ve Değerlendirme')),
      body: const Center(child: Text('Hedefler ve değerlendirme iskeleti')), 
    );
  }
}
