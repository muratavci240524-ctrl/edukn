import 'package:flutter/material.dart';
import '../../widgets/haberlesme_hub_widget.dart';

class TeacherHaberlesmeScreen extends StatelessWidget {
  final String institutionId;
  final String? schoolTypeId;
  final String? schoolTypeName;

  const TeacherHaberlesmeScreen({
    Key? key,
    required this.institutionId,
    this.schoolTypeId,
    this.schoolTypeName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return HaberlesmeHubWidget(
      institutionId: institutionId,
      schoolTypeId: schoolTypeId ?? '',
      schoolTypeName: schoolTypeName ?? '',
      isTeacher: true,
    );
  }
}
