import 'package:flutter/material.dart';

class TrainingScreen extends StatelessWidget {
  static const routeName = '/hr/training';
  const TrainingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Eğitim ve Gelişim (PD)')),
      body: const Center(child: Text('Eğitim planı ve katılım iskeleti')), 
    );
  }
}
