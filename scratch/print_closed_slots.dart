import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  final snaps = await FirebaseFirestore.instance.collection('workPeriods').get();
  for (var doc in snaps.docs) {
    final data = doc.data();
    print("WorkPeriod ID: ${doc.id}");
    print("  isActive: ${data['isActive']}");
    print("  closedSlots: ${data['closedSlots']}");
  }
}
