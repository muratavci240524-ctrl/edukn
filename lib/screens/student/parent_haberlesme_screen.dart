import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/haberlesme_hub_widget.dart';

class ParentHaberlesmeScreen extends StatefulWidget {
  final String institutionId;
  final String? schoolTypeId;
  final String? schoolTypeName;

  const ParentHaberlesmeScreen({
    Key? key,
    required this.institutionId,
    this.schoolTypeId,
    this.schoolTypeName,
  }) : super(key: key);

  @override
  State<ParentHaberlesmeScreen> createState() => _ParentHaberlesmeScreenState();
}

class _ParentHaberlesmeScreenState extends State<ParentHaberlesmeScreen> {
  String _resolvedTypeId = '';
  String _resolvedTypeName = '';

  @override
  void initState() {
    super.initState();
    _syncFromPropsOrLoad();
  }

  @override
  void didUpdateWidget(covariant ParentHaberlesmeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schoolTypeId != widget.schoolTypeId ||
        oldWidget.schoolTypeName != widget.schoolTypeName) {
      _syncFromPropsOrLoad();
    }
  }

  Future<void> _syncFromPropsOrLoad() async {
    if ((widget.schoolTypeId ?? '').isNotEmpty) {
      setState(() {
        _resolvedTypeId = widget.schoolTypeId!;
        _resolvedTypeName = widget.schoolTypeName ?? '';
      });
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    final stId =
        prefs.getString('selected_student_id_${user.uid}') ??
        prefs.getString('selected_student_id') ??
        '';

    if (stId.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('students')
            .doc(stId)
            .get();
        if (doc.exists && mounted) {
          final data = doc.data()!;
          setState(() {
            _resolvedTypeId = data['schoolTypeId']?.toString() ?? '';
            _resolvedTypeName = data['schoolTypeName']?.toString() ?? '';
          });
        }
      } catch (silentError) {
        debugPrint('[parent_haberlesme_screen] hata yutuldu: $silentError');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return HaberlesmeHubWidget(
      institutionId: widget.institutionId,
      schoolTypeId: _resolvedTypeId,
      schoolTypeName: _resolvedTypeName,
      isTeacher: false,
      showAppBar: false,
    );
  }
}
