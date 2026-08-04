import 'package:flutter/material.dart';
import '../teacher/teacher_dashboard_tab.dart';

class ParentDashboardTab extends StatelessWidget {
  final String institutionId;

  const ParentDashboardTab({
    Key? key,
    required this.institutionId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TeacherDashboardTab(
      institutionId: institutionId,
    );
  }
}
