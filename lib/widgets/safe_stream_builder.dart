import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:edukn/screens/school/school_login_screen.dart'; 

class SafeStreamBuilder<T> extends StatelessWidget {
  final Stream<T>? stream;
  final T? initialData;
  final Widget Function(BuildContext context, AsyncSnapshot<T> snapshot) builder;

  const SafeStreamBuilder({
    Key? key,
    required this.stream,
    this.initialData,
    required this.builder,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      key: key,
      stream: stream,
      initialData: initialData,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error.toString().toLowerCase();
          debugPrint("❌ SafeStreamBuilder Hatası: $error");
          
          if (error.contains('permission-denied') || 
              error.contains('unauthenticated') || 
              error.contains('missing or insufficient permissions')) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline, color: Colors.orange.shade400, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      'Bu veriyi görüntüleme yetkiniz bulunmamaktadır veya henüz veri tanımlanmamış.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            );
          }

          // Diğer bilinmeyen hatalar
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Beklenmeyen Veri Hatası:\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),
          );
        }

        // Hata yoksa orijinal builder'a pasla
        return builder(context, snapshot);
      },
    );
  }
}
