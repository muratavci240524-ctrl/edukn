import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'class_lesson_attendance_screen.dart';
import 'class_lesson_stats_screen.dart';
import 'parent_weekly_update_screen.dart';
import 'homework/create_homework_dialog.dart';
import 'homework/homework_list_tab.dart';
import 'class_lesson_plan_entry_dialog.dart';
import 'class_lesson_plan_list_tab.dart';
import 'grades/grade_list_tab.dart';

class ClassLessonHubScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String? periodId;

  final String classId;
  final String lessonId;

  final String className;
  final String lessonName;

  final DateTime? initialDate;
  final int? initialLessonHour;
  final List<int>? availableLessonHours;

  const ClassLessonHubScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    this.periodId,
    required this.classId,
    required this.lessonId,
    required this.className,
    required this.lessonName,
    this.initialDate,
    this.initialLessonHour,
    this.availableLessonHours,
  });

  @override
  State<ClassLessonHubScreen> createState() => _ClassLessonHubScreenState();
}

class _ClassLessonHubScreenState extends State<ClassLessonHubScreen> {
  void _showQuickActions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final maxHeight = MediaQuery.of(context).size.height * 0.85;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Container(
              margin: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 8),
                  Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  SizedBox(height: 10),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Hızlı İşlemler',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(Icons.close, color: Colors.grey.shade700),
                          tooltip: 'Kapat',
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1),
                  Flexible(
                    fit: FlexFit.loose,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _ActionTile(
                            icon: Icons.fact_check_outlined,
                            title: 'Yoklama Al',
                            subtitle: 'Bu ders için yoklama oluştur',
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                this.context,
                                MaterialPageRoute(
                                  builder: (_) => ClassLessonAttendanceScreen(
                                    institutionId: widget.institutionId,
                                    schoolTypeId: widget.schoolTypeId,
                                    periodId: widget.periodId,
                                    classId: widget.classId,
                                    lessonId: widget.lessonId,
                                    className: widget.className,
                                    lessonName: widget.lessonName,
                                    initialDate: widget.initialDate,
                                    initialLessonHour: widget.initialLessonHour,
                                    availableLessonHours:
                                        widget.availableLessonHours,
                                  ),
                                ),
                              );
                            },
                          ),
                          _ActionTile(
                            icon: Icons.event_note_outlined,
                            title: 'Ders Planı Gir',
                            subtitle: 'Plan / kazanım / açıklama',
                            onTap: () async {
                              Navigator.pop(context);
                              await showDialog(
                                context: context,
                                builder: (_) => ClassLessonPlanEntryDialog(
                                  institutionId: widget.institutionId,
                                  schoolTypeId: widget.schoolTypeId,
                                  periodId: widget.periodId,
                                  classId: widget.classId,
                                  lessonId: widget.lessonId,
                                  lessonName: widget.lessonName,
                                ),
                              );
                            },
                          ),
                          _ActionTile(
                            icon: Icons.assignment_outlined,
                            title: 'Ödev Ver',
                            subtitle: 'Ödev oluştur ve paylaş',
                            onTap: () async {
                              Navigator.pop(context);
                              final uid =
                                  FirebaseAuth.instance.currentUser?.uid;
                              if (uid == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Oturum hatası: Öğretmen kimliği bulunamadı.',
                                    ),
                                  ),
                                );
                                return;
                              }

                              await showDialog(
                                context: context,
                                builder: (_) => CreateHomeworkDialog(
                                  institutionId: widget.institutionId,
                                  classId: widget.classId,
                                  lessonId: widget.lessonId,
                                  lessonName: widget.lessonName,
                                  teacherId: uid,
                                ),
                              );
                            },
                          ),
                          _ActionTile(
                            icon: Icons.mail_outline,
                            title: 'Veli Bilgilendirme',
                            subtitle: 'Haftalık veli mektubu oluştur',
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                this.context,
                                MaterialPageRoute(
                                  builder: (_) => ParentWeeklyUpdateScreen(
                                    institutionId: widget.institutionId,
                                    schoolTypeId: widget.schoolTypeId,
                                    periodId: widget.periodId,
                                    classId: widget.classId,
                                    lessonId: widget.lessonId,
                                    className: widget.className,
                                    lessonName: widget.lessonName,
                                    initialDate: widget.initialDate,
                                  ),
                                ),
                              );
                            },
                          ),
                          SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.className} • ${widget.lessonName}',
                style: TextStyle(
                  color: Colors.grey.shade900,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Ders Sayfası',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'İstatistik',
              icon: Icon(Icons.insights_outlined, color: Colors.blue.shade700),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ClassLessonStatsScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                      periodId: widget.periodId,
                      classId: widget.classId,
                      lessonId: widget.lessonId,
                      className: widget.className,
                      lessonName: widget.lessonName,
                    ),
                  ),
                );
              },
            ),
          ],
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(48),
            child: Container(
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: TabBar(
                labelColor: Colors.blue.shade700,
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: Colors.blue.shade700,
                indicatorWeight: 3,
                tabs: [
                  Tab(text: 'Ders Planları'),
                  Tab(text: 'Ödevler'),
                  Tab(text: 'Notlar'),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showQuickActions,
          backgroundColor: Colors.blue.shade600,
          child: Icon(Icons.add, color: Colors.white),
        ),
        body: TabBarView(
          children: [
            ClassLessonPlanListTab(
              institutionId: widget.institutionId,
              schoolTypeId: widget.schoolTypeId,
              periodId: widget.periodId,
              classId: widget.classId,
              lessonId: widget.lessonId,
              lessonName: widget.lessonName,
            ),
            HomeworkListTab(
              institutionId: widget.institutionId,
              classId: widget.classId,
              lessonId: widget.lessonId,
            ),
            GradeListTab(
              institutionId: widget.institutionId,
              classId: widget.classId,
              lessonId: widget.lessonId,
              lessonName: widget.lessonName,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.blue.shade700),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }
}
