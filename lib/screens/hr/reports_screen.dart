import 'package:flutter/material.dart';

class ReportsScreen extends StatelessWidget {
  static const routeName = '/hr/reports';
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Raporlama ve Analitik')),
      body: const Center(child: Text('Grafikler ve export iskeleti')), 
    );
  }
}
