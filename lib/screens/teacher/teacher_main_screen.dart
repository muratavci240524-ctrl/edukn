import 'package:flutter/material.dart';
import '../../widgets/stylish_bottom_nav.dart';
import 'teacher_announcements_screen.dart';
import 'teacher_social_media_screen.dart';
import 'teacher_messages_screen.dart';
import 'teacher_operations_screen.dart';
import 'teacher_dashboard_tab.dart';

class TeacherMainScreen extends StatefulWidget {
  final String institutionId;

  const TeacherMainScreen({Key? key, required this.institutionId})
    : super(key: key);

  @override
  State<TeacherMainScreen> createState() => _TeacherMainScreenState();
}

class _TeacherMainScreenState extends State<TeacherMainScreen> {
  int _currentIndex = 0;
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      TeacherAnnouncementsScreen(institutionId: widget.institutionId), // 0: Duyurular
      TeacherSocialMediaScreen(institutionId: widget.institutionId),   // 1: Sosyal
      TeacherMessagesScreen(institutionId: widget.institutionId),      // 2: Mesajlar
      TeacherOperationsScreen(institutionId: widget.institutionId),    // 3: İşlemler
      TeacherDashboardTab(institutionId: widget.institutionId),       // 4: Dashboard (Orta)
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: StylishBottomNav(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}
