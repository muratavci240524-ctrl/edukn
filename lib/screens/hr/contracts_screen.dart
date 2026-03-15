import 'package:flutter/material.dart';

class ContractsScreen extends StatelessWidget {
  static const routeName = '/hr/contracts';
  const ContractsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sözleşme ve Evrak Yönetimi')),
      body: const Center(child: Text('Sözleşmeler ve evrak iskeleti')), 
    );
  }
}
