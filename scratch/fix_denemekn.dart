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
  
  print('Updating user document omustafa061...');
  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc('omustafa061')
        .update({
          'email': 'omustafa061@gmail.com',
        });
    print('✅ Successfully updated user email to omustafa061@gmail.com!');
  } catch (e) {
    print('❌ Error updating user document: $e');
  }
  
  exit(0);
}
