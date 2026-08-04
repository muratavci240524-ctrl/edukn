import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/haberlesme_hub_widget.dart';

class ParentHaberlesmeScreen extends StatefulWidget {
  final String institutionId;

  const ParentHaberlesmeScreen({Key? key, required this.institutionId}) : super(key: key);

  @override
  State<ParentHaberlesmeScreen> createState() => _ParentHaberlesmeScreenState();
}

class _ParentHaberlesmeScreenState extends State<ParentHaberlesmeScreen> {
  String _schoolTypeId = '';
  String _schoolTypeName = '';

  @override
  void initState() {
    super.initState();
    _loadStudentContext();
  }

  Future<void> _loadStudentContext() async {
    final prefs = await SharedPreferences.getInstance();
    final stId = prefs.getString('selected_student_id') ?? '';

    if (stId.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance.collection('students').doc(stId).get();
        if (doc.exists && mounted) {
          final data = doc.data()!;
          setState(() {
            _schoolTypeId = data['schoolTypeId']?.toString() ?? '';
            _schoolTypeName = data['schoolTypeName']?.toString() ?? '';
          });
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return HaberlesmeHubWidget(
      institutionId: widget.institutionId,
      schoolTypeId: _schoolTypeId,
      schoolTypeName: _schoolTypeName,
      isTeacher: false,
    );
  }
}
