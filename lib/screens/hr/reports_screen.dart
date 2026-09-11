import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';

class ReportsScreen extends StatelessWidget {
  static const routeName = '/hr/reports';
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: EduknAppBar(title: 'Raporlama ve Analitik'),
      body: const Center(child: Text('Grafikler ve export iskeleti')), 
    );
  }
}
