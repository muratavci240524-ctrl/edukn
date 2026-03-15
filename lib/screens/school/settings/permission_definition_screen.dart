import 'package:flutter/material.dart';

class PermissionDefinitionScreen extends StatelessWidget {
  const PermissionDefinitionScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yetki Tanımlama'), elevation: 0),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.security, size: 80, color: Colors.indigo.shade300),
            const SizedBox(height: 16),
            const Text(
              'Yetki Tanımlama İşlemleri',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Bu ekran yetki türlerini ve kapsamlarını yönetmek için kullanılacak.',
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Geri Dön'),
            ),
          ],
        ),
      ),
    );
  }
}
