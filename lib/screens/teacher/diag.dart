import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DiagnosticScreen extends StatefulWidget {
  final String instId;
  const DiagnosticScreen({Key? key, required this.instId}) : super(key: key);

  @override
  _DiagnosticScreenState createState() => _DiagnosticScreenState();
}

class _DiagnosticScreenState extends State<DiagnosticScreen> {
  String results = "Loading...";

  @override
  void initState() {
    super.initState();
    _runDiag();
  }

  Future<void> _runDiag() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('institutionId', isEqualTo: widget.instId)
          .limit(20)
          .get();
      
      String buffer = "Institution: ${widget.instId}\nFound ${snap.docs.length} assignments\n\n";
      for (var doc in snap.docs) {
        final data = doc.data();
        buffer += "ID: ${doc.id}\n";
        buffer += "Lesson: ${data['lessonName']}\n";
        buffer += "Class: ${data['className']}\n";
        buffer += "Teachers: ${data['teacherIds']}\n";
        buffer += "Active: ${data['isActive']}\n";
        buffer += "---\n";
      }
      
      setState(() {
        results = buffer;
      });
    } catch (e) {
      setState(() {
        results = "Error: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Diagnostic")),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Text(results, style: TextStyle(fontFamily: 'monospace')),
      ),
    );
  }
}
