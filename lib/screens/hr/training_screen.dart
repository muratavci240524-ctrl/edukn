import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';

class TrainingScreen extends StatelessWidget {
  static const routeName = '/hr/training';
  const TrainingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: EduknAppBar(title: 'Eğitim ve Gelişim (PD)'),
      body: const Center(child: Text('Eğitim planı ve katılım iskeleti')), 
    );
  }
}
