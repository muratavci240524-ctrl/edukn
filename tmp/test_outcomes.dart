import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edukn/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:io';

void main() async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.windows);

    final snap = await FirebaseFirestore.instance
        .collection('trial_exams')
        .get();
    for (var doc in snap.docs) {
      final data = doc.data();
      final outcomes = data['outcomes'] as Map<String, dynamic>? ?? {};
      if (outcomes.containsKey('B')) {
        print('Exam: ${data['name']}');
        print('A Outcomes: ${outcomes['A']}');
        print('B Outcomes: ${outcomes['B']}');
        break;
      }
    }
  } catch (e) {
    print('Error: $e');
  }
  exit(0);
}
