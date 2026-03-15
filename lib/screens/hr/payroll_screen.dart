import 'package:flutter/material.dart';

class PayrollScreen extends StatelessWidget {
  static const routeName = '/hr/payroll';
  const PayrollScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Maaş ve Bordro Yönetimi')),
      body: const Center(child: Text('Maaş kalemleri ve bordro iskeleti')), 
    );
  }
}
