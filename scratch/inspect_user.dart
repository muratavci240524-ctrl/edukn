import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../lib/firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  print('Initializing Firebase...');
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  print('Querying schools with institutionId: DENEMEKN...');
  final schools = await FirebaseFirestore.instance
      .collection('schools')
      .where('institutionId', isEqualTo: 'DENEMEKN')
      .get();
      
  if (schools.docs.isEmpty) {
    print('❌ School not found!');
  } else {
    for (var doc in schools.docs) {
      print('School Doc ID: ${doc.id}');
      print('School Data: ${doc.data()}');
    }
  }

  print('\nQuerying users with institutionId: DENEMEKN...');
  final users = await FirebaseFirestore.instance
      .collection('users')
      .where('institutionId', isEqualTo: 'DENEMEKN')
      .get();
      
  if (users.docs.isEmpty) {
    print('❌ Users not found!');
  } else {
    for (var doc in users.docs) {
      print('User Doc ID: ${doc.id}');
      print('User Data: ${doc.data()}');
    }
  }
  
  exit(0);
}
