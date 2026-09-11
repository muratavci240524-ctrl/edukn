import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';

class ContractsScreen extends StatelessWidget {
  static const routeName = '/hr/contracts';
  const ContractsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: EduknAppBar(title: 'Sözleşme ve Evrak Yönetimi'),
      body: const Center(child: Text('Sözleşmeler ve evrak iskeleti')), 
    );
  }
}
