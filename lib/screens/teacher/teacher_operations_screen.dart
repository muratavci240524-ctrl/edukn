import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../school/profile_settings_screen.dart';
import 'teacher_lessons_screen.dart';
import 'teacher_student_list_screen.dart';
import '../school/guidance/guidance_interview_screen.dart';
import '../school/activity/activity_list_screen.dart';
import '../school/guidance/saved_study_programs_screen.dart';
import '../guidance/guidance_test_catalog_screen.dart';
import '../guidance/reports/development_report_management_screen.dart';
import '../school/tasks/todo_list_screen.dart';
import '../portfolio/portfolio_screen.dart';
import '../../widgets/edukn_logo.dart';
import '../school/work_calendar_screen.dart';
import '../school/attendance_statistics_screen.dart';
import '../school/homework/homework_operations_screen.dart';
import '../school/etut_process_screen.dart';
import '../school/survey/survey_list_screen.dart';
import '../../services/user_permission_service.dart';
import '../hr/leave/leave_management_screen.dart';
import 'teacher_duty_screen.dart';
import '../school/tasks/field_trip_list_screen.dart';
import '../school/assessment/assessment_reports_screen.dart';
import 'teacher_qr_scan_screen.dart';

class TeacherOperationsScreen extends StatefulWidget {
  final String institutionId;

  const TeacherOperationsScreen({
    Key? key,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<TeacherOperationsScreen> createState() => _TeacherOperationsScreenState();
}

class _TeacherOperationsScreenState extends State<TeacherOperationsScreen> {
  String? _expandedCategory;
  String _selectedCategory = 'Tümü';
  bool _isNavigating = false;

  Future<void> _navigateToAssessmentReports() async {
    setState(() => _isNavigating = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final userData = await UserPermissionService.loadUserData();
      final instId = (userData?['institutionId'] ?? widget.institutionId).toString().toUpperCase();
      final teacherId = userData?['id'] ?? user.uid;

      List<String> userSTIds = List<String>.from(userData?['schoolTypes'] ?? []);
      
      if (userSTIds.isEmpty) {
        final assignmentsSnap = await FirebaseFirestore.instance
            .collection('lessonAssignments')
            .where('institutionId', isEqualTo: instId)
            .where('teacherIds', arrayContains: teacherId)
            .where('isActive', isEqualTo: true)
            .get();

        userSTIds = assignmentsSnap.docs
            .map((doc) => doc.data()['schoolTypeId']?.toString())
            .where((id) => id != null)
            .cast<String>()
            .toSet()
            .toList();
      }

      if (userSTIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bağlı olduğunuz bir okul türü bulunamadı.')),
          );
        }
        return;
      }

      if (userSTIds.length == 1) {
        final stId = userSTIds.first;
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => AssessmentReportsScreen(
                institutionId: instId,
                schoolTypeId: stId,
                isTeacher: true,
              ),
            ),
          );
        }
      } else {
        final List<Map<String, String>> schoolTypesWithNames = [];
        for (var stId in userSTIds) {
          final stDoc = await FirebaseFirestore.instance.collection('school_types').doc(stId).get();
          if (stDoc.exists) {
            schoolTypesWithNames.add({
              'id': stId,
              'name': stDoc.data()?['name'] ?? 'Okul',
            });
          }
        }

        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Okul Türü Seçin'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: schoolTypesWithNames.map((st) => ListTile(
                  title: Text(st['name']!),
                  leading: const Icon(Icons.school, color: Colors.orange),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => AssessmentReportsScreen(
                          institutionId: instId,
                          schoolTypeId: st['id']!,
                          isTeacher: true,
                        ),
                      ),
                    );
                  },
                )).toList(),
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error navigating to assessment reports: $e');
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white.withOpacity(0.95),
        automaticallyImplyLeading: false,
        flexibleSpace: Stack(
          children: [
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: Row(
                children: [
                  const EduKnLogo(iconSize: 28, type: EduKnLogoType.iconOnly),
                  const SizedBox(width: 12),
                  Text(
                    'eduKN',
                    style: TextStyle(
                      color: Colors.indigo.shade900,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Öğretmen İşlemleri',
                        style: TextStyle(
                          color: Colors.indigo.shade900,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Size Tanımlı Modüller',
                        style: TextStyle(
                          color: Colors.indigo.shade400,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            offset: const Offset(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 8,
            shadowColor: Colors.black.withOpacity(0.12),
            onSelected: (value) {
              if (value == 'profile') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) => const ProfileSettingsScreen(),
                  ),
                );
              } else if (value == 'qr_scan') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) => const TeacherQrScanScreen(),
                  ),
                );
              } else if (value == 'logout') {
                _logout();
              }
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem<String>(
                value: 'profile',
                child: Row(
                  children: [
                    Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.person_outline_rounded, color: Colors.indigo.shade700, size: 18)),
                    const SizedBox(width: 12),
                    const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Profilim', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      Text('Profili Düzenle', style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                    ]),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'qr_scan',
                child: Row(
                  children: [
                    Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.qr_code_scanner_rounded, color: Colors.orange.shade700, size: 18)),
                    const SizedBox(width: 12),
                    const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Giriş / Çıkış (QR)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      Text('Kamera ile QR tarama', style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                    ]),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.logout_rounded, color: Colors.red.shade600, size: 18)),
                    const SizedBox(width: 12),
                    Text('Çıkış Yap', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.red.shade700)),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: CircleAvatar(
                radius: 17,
                backgroundColor: Colors.indigo.shade50,
                child: const Icon(Icons.person, color: Colors.indigo, size: 18),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  padding: EdgeInsets.symmetric(
                    horizontal: MediaQuery.of(context).size.width < 768 ? 16 : 24, 
                    vertical: MediaQuery.of(context).size.width < 768 ? 24 : 32
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCategorySelector(),
                      const SizedBox(height: 24),
                      _buildGridSections(MediaQuery.of(context).size.width < 768),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_isNavigating)
            Container(
              color: Colors.black26,
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _navigateToSurvey() async {
    setState(() => _isNavigating = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final userData = await UserPermissionService.loadUserData();
      final instId = (userData?['institutionId'] ?? widget.institutionId).toString().toUpperCase();
      final teacherId = userData?['id'] ?? user.uid;

      // Deducing school types
      List<String> userSTIds = List<String>.from(userData?['schoolTypes'] ?? []);
      
      if (userSTIds.isEmpty) {
        final assignmentsSnap = await FirebaseFirestore.instance
            .collection('lessonAssignments')
            .where('institutionId', isEqualTo: instId)
            .where('teacherIds', arrayContains: teacherId)
            .where('isActive', isEqualTo: true)
            .get();

        userSTIds = assignmentsSnap.docs
            .map((doc) => doc.data()['schoolTypeId']?.toString())
            .where((id) => id != null)
            .cast<String>()
            .toSet()
            .toList();
      }

      if (userSTIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bağlı olduğunuz bir okul türü bulunamadı.')),
          );
        }
        return;
      }

      if (userSTIds.length == 1) {
        final stId = userSTIds.first;
        final stDoc = await FirebaseFirestore.instance.collection('school_types').doc(stId).get();
        final stName = stDoc.exists ? (stDoc.data()?['name'] ?? 'Okul') : 'Okul';

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => SurveyListScreen(
                institutionId: instId,
                schoolTypeId: stId,
                schoolTypeName: stName,
                isTeacher: true,
                teacherId: teacherId,
              ),
            ),
          );
        }
      } else {
        // Multiple school types dialog
        final List<Map<String, String>> schoolTypesWithNames = [];
        for (var stId in userSTIds) {
          final stDoc = await FirebaseFirestore.instance.collection('school_types').doc(stId).get();
          if (stDoc.exists) {
            schoolTypesWithNames.add({
              'id': stId,
              'name': stDoc.data()?['name'] ?? 'Okul',
            });
          }
        }

        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Okul Türü Seçin'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: schoolTypesWithNames.map((st) => ListTile(
                  title: Text(st['name']!),
                  leading: const Icon(Icons.school, color: Colors.orange),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => SurveyListScreen(
                          institutionId: instId,
                          schoolTypeId: st['id']!,
                          schoolTypeName: st['name']!,
                          isTeacher: true,
                          teacherId: teacherId,
                        ),
                      ),
                    );
                  },
                )).toList(),
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error navigating to survey: $e');
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _navigateToEtutProcess() async {
    setState(() => _isNavigating = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final userData = await UserPermissionService.loadUserData();
      final instId = (userData?['institutionId'] ?? widget.institutionId).toString().toUpperCase();
      final teacherId = userData?['id'] ?? user.uid;

      // Deducing school types
      List<String> userSTIds = List<String>.from(userData?['schoolTypes'] ?? []);
      
      if (userSTIds.isEmpty) {
        final assignmentsSnap = await FirebaseFirestore.instance
            .collection('lessonAssignments')
            .where('institutionId', isEqualTo: instId)
            .where('teacherIds', arrayContains: teacherId)
            .where('isActive', isEqualTo: true)
            .get();

        userSTIds = assignmentsSnap.docs
            .map((doc) => doc.data()['schoolTypeId']?.toString())
            .where((id) => id != null)
            .cast<String>()
            .toSet()
            .toList();
      }

      if (userSTIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bağlı olduğunuz bir okul türü bulunamadı.')),
          );
        }
        return;
      }

      if (userSTIds.length == 1) {
        final stId = userSTIds.first;
        final stDoc = await FirebaseFirestore.instance.collection('school_types').doc(stId).get();
        final stName = stDoc.exists ? (stDoc.data()?['name'] ?? 'Okul') : 'Okul';

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => EtutProcessScreen(
                institutionId: instId,
                schoolTypeId: stId,
                schoolTypeName: stName,
                isTeacher: true,
                teacherId: teacherId,
              ),
            ),
          );
        }
      } else {
        // Multiple school types dialog
        final List<Map<String, String>> schoolTypesWithNames = [];
        for (var stId in userSTIds) {
          final stDoc = await FirebaseFirestore.instance.collection('school_types').doc(stId).get();
          if (stDoc.exists) {
            schoolTypesWithNames.add({
              'id': stId,
              'name': stDoc.data()?['name'] ?? 'Okul',
            });
          }
        }

        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Okul Türü Seçin'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: schoolTypesWithNames.map((st) => ListTile(
                  title: Text(st['name']!),
                  leading: const Icon(Icons.school, color: Colors.orange),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => EtutProcessScreen(
                          institutionId: instId,
                          schoolTypeId: st['id']!,
                          schoolTypeName: st['name']!,
                          isTeacher: true,
                          teacherId: teacherId,
                        ),
                      ),
                    );
                  },
                )).toList(),
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error navigating to etut process: $e');
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _navigateToHomeworkStats() async {
    setState(() => _isNavigating = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final userData = await UserPermissionService.loadUserData();
      final instId = (userData?['institutionId'] ?? widget.institutionId).toString().toUpperCase();

      // Deducing school types
      List<String> userSTIds = List<String>.from(userData?['schoolTypes'] ?? []);
      
      if (userSTIds.isEmpty) {
        final teacherId = userData?['id'] ?? user.uid;
        final assignmentsSnap = await FirebaseFirestore.instance
            .collection('lessonAssignments')
            .where('institutionId', isEqualTo: instId)
            .where('teacherIds', arrayContains: teacherId)
            .where('isActive', isEqualTo: true)
            .get();

        userSTIds = assignmentsSnap.docs
            .map((doc) => doc.data()['schoolTypeId']?.toString())
            .where((id) => id != null)
            .cast<String>()
            .toSet()
            .toList();
      }

      if (userSTIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bağlı olduğunuz bir okul türü bulunamadı.')),
          );
        }
        return;
      }

      if (userSTIds.length == 1) {
        final stId = userSTIds.first;
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => HomeworkOperationsScreen(
                institutionId: instId,
                schoolTypeId: stId,
                isTeacher: true,
              ),
            ),
          );
        }
      } else {
        // Multiple school types dialog
        final List<Map<String, String>> schoolTypesWithNames = [];
        for (var stId in userSTIds) {
          final stDoc = await FirebaseFirestore.instance.collection('school_types').doc(stId).get();
          if (stDoc.exists) {
            schoolTypesWithNames.add({
              'id': stId,
              'name': stDoc.data()?['name'] ?? 'Okul',
            });
          }
        }

        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Okul Türü Seçin'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: schoolTypesWithNames.map((st) => ListTile(
                  title: Text(st['name']!),
                  leading: const Icon(Icons.school, color: Colors.orange),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => HomeworkOperationsScreen(
                          institutionId: instId,
                          schoolTypeId: st['id']!,
                          isTeacher: true,
                        ),
                      ),
                    );
                  },
                )).toList(),
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error navigating to homework stats: $e');
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _navigateToAttendanceStats() async {
    setState(() => _isNavigating = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final userData = await UserPermissionService.loadUserData();
      final instId = (userData?['institutionId'] ?? widget.institutionId).toString().toUpperCase();

      // Similar logic to deduce school types
      List<String> userSTIds = List<String>.from(userData?['schoolTypes'] ?? []);
      
      if (userSTIds.isEmpty) {
        final teacherId = userData?['id'] ?? user.uid;
        final assignmentsSnap = await FirebaseFirestore.instance
            .collection('lessonAssignments')
            .where('institutionId', isEqualTo: instId)
            .where('teacherIds', arrayContains: teacherId)
            .where('isActive', isEqualTo: true)
            .get();

        userSTIds = assignmentsSnap.docs
            .map((doc) => doc.data()['schoolTypeId']?.toString())
            .where((id) => id != null)
            .cast<String>()
            .toSet()
            .toList();
      }

      if (userSTIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bağlı olduğunuz bir okul türü bulunamadı.')),
          );
        }
        return;
      }

      if (userSTIds.length == 1) {
        final stId = userSTIds.first;
        final stDoc = await FirebaseFirestore.instance.collection('school_types').doc(stId).get();
        final stName = stDoc.exists ? (stDoc.data()?['name'] ?? 'Okul') : 'Okul';

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => AttendanceStatisticsScreen(
                institutionId: instId,
                schoolTypeId: stId,
                schoolTypeName: stName,
              ),
            ),
          );
        }
      } else {
        // Multiple school types dialog
        final List<Map<String, String>> schoolTypesWithNames = [];
        for (var stId in userSTIds) {
          final stDoc = await FirebaseFirestore.instance.collection('school_types').doc(stId).get();
          if (stDoc.exists) {
            schoolTypesWithNames.add({
              'id': stId,
              'name': stDoc.data()?['name'] ?? 'Okul',
            });
          }
        }

        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Okul Türü Seçin'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: schoolTypesWithNames.map((st) => ListTile(
                  title: Text(st['name']!),
                  leading: const Icon(Icons.school, color: Colors.orange),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => AttendanceStatisticsScreen(
                          institutionId: instId,
                          schoolTypeId: st['id']!,
                          schoolTypeName: st['name']!,
                        ),
                      ),
                    );
                  },
                )).toList(),
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error navigating to attendance stats: $e');
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _navigateToWorkCalendar() async {
    setState(() => _isNavigating = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final userData = await UserPermissionService.loadUserData();
      final instId = (userData?['institutionId'] ?? widget.institutionId).toString().toUpperCase();

      // Similar logic to portfolio for school type selection
      List<String> userSTIds = List<String>.from(userData?['schoolTypes'] ?? []);
      
      if (userSTIds.isEmpty) {
        // Find assigned classes to deduce school types
        final teacherId = userData?['id'] ?? user.uid;
        final assignmentsSnap = await FirebaseFirestore.instance
            .collection('lessonAssignments')
            .where('institutionId', isEqualTo: instId)
            .where('teacherIds', arrayContains: teacherId)
            .where('isActive', isEqualTo: true)
            .get();

        userSTIds = assignmentsSnap.docs
            .map((doc) => doc.data()['schoolTypeId']?.toString())
            .where((id) => id != null)
            .cast<String>()
            .toSet()
            .toList();
      }

      if (userSTIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bağlı olduğunuz bir okul türü bulunamadı.')),
          );
        }
        return;
      }

      if (userSTIds.length == 1) {
        final stId = userSTIds.first;
        final stDoc = await FirebaseFirestore.instance.collection('school_types').doc(stId).get();
        final stName = stDoc.exists ? (stDoc.data()?['name'] ?? 'Okul') : 'Okul';

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => WorkCalendarScreen(
                institutionId: instId,
                schoolTypeId: stId,
                schoolTypeName: stName,
                isTeacher: true,
              ),
            ),
          );
        }
      } else {
        // Dialog selection
        final List<Map<String, String>> schoolTypesWithNames = [];
        for (var stId in userSTIds) {
          final stDoc = await FirebaseFirestore.instance.collection('school_types').doc(stId).get();
          if (stDoc.exists) {
            schoolTypesWithNames.add({
              'id': stId,
              'name': stDoc.data()?['name'] ?? 'Okul',
            });
          }
        }

        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Okul Türü Seçin'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: schoolTypesWithNames.map((st) => ListTile(
                  title: Text(st['name']!),
                  leading: const Icon(Icons.school, color: Colors.orange),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => WorkCalendarScreen(
                          institutionId: instId,
                          schoolTypeId: st['id']!,
                          schoolTypeName: st['name']!,
                          isTeacher: true,
                        ),
                      ),
                    );
                  },
                )).toList(),
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error navigating to work calendar: $e');
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _navigateToPortfolio() async {
    setState(() => _isNavigating = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final userData = await UserPermissionService.loadUserData();
      final teacherId = userData?['id'] ?? user.uid;
      final instId = (userData?['institutionId'] ?? widget.institutionId).toString().toUpperCase();

      // Get assigned classes
      final assignmentsSnap = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('institutionId', isEqualTo: instId)
          .where('teacherIds', arrayContains: teacherId)
          .where('isActive', isEqualTo: true)
          .get();

      final classIds = assignmentsSnap.docs
          .map((doc) => doc.data()['classId']?.toString())
          .where((id) => id != null)
          .cast<String>()
          .toSet()
          .toList();

      if (classIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Portfolyosunu görebileceğiniz atanmış bir sınıfınız bulunamadı.')),
          );
        }
        return;
      }

      // Check teacher's school types
      List<String> userSTIds = List<String>.from(userData?['schoolTypes'] ?? []);
      
      if (userSTIds.isEmpty && classIds.isNotEmpty) {
        // Fallback: Get school types from assigned classes if not in profile
        // Limited to first 30 classes for whereIn safety
        final limitIds = classIds.length > 30 ? classIds.take(30).toList() : classIds;
        final classesSnap = await FirebaseFirestore.instance
            .collection('classes')
            .where(FieldPath.documentId, whereIn: limitIds)
            .get();
        
        userSTIds = classesSnap.docs
            .map((doc) => doc.data()['schoolTypeId']?.toString())
            .where((id) => id != null)
            .cast<String>()
            .toSet()
            .toList();
      }
      
      if (userSTIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bağlı olduğunuz bir okul türü bulunamadı.')),
          );
        }
        return;
      }

      // If only one school type, navigate directly
      if (userSTIds.length == 1) {
        final stId = userSTIds.first.toString();
        // Get school type name
        final stDoc = await FirebaseFirestore.instance.collection('school_types').doc(stId).get();
        final stName = stDoc.exists ? (stDoc.data()?['name'] ?? 'Okul') : 'Okul';

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => PortfolioScreen(
                institutionId: instId,
                schoolTypeId: stId,
                schoolTypeName: stName,
                allowedClassIds: classIds,
              ),
            ),
          );
        }
      } else {
        // Multiple school types: show selection dialog
        final List<Map<String, String>> schoolTypesWithNames = [];
        for (var stId in userSTIds) {
          final stDoc = await FirebaseFirestore.instance.collection('school_types').doc(stId.toString()).get();
          if (stDoc.exists) {
            schoolTypesWithNames.add({
              'id': stId.toString(),
              'name': stDoc.data()?['name'] ?? 'Okul',
            });
          }
        }

        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Okul Türü Seçin'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: schoolTypesWithNames.map((st) => ListTile(
                  title: Text(st['name']!),
                  leading: const Icon(Icons.school, color: Colors.indigo),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => PortfolioScreen(
                          institutionId: instId,
                          schoolTypeId: st['id']!,
                          schoolTypeName: st['name']!,
                          allowedClassIds: classIds,
                        ),
                      ),
                    );
                  },
                )).toList(),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
              ],
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error navigating to portfolio: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bir hata oluştu: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _navigateToGuidanceInterview() async {
    setState(() => _isNavigating = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final userData = await UserPermissionService.loadUserData();
      final instId = (userData?['institutionId'] ?? widget.institutionId).toString().toUpperCase();
      final teacherId = userData?['id'] ?? user.uid;

      List<String> userSTIds = List<String>.from(userData?['schoolTypes'] ?? []);
      if (userSTIds.isEmpty) {
        final assignmentsSnap = await FirebaseFirestore.instance.collection('lessonAssignments').where('institutionId', isEqualTo: instId).where('teacherIds', arrayContains: teacherId).where('isActive', isEqualTo: true).get();
        userSTIds = assignmentsSnap.docs.map((doc) => doc.data()['schoolTypeId']?.toString()).where((id) => id != null).cast<String>().toSet().toList();
      }

      if (userSTIds.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bağlı olduğunuz bir okul türü bulunamadı.')));
        return;
      }

      final stId = userSTIds.first;
      final stDoc = await FirebaseFirestore.instance.collection('school_types').doc(stId).get();
      final stName = stDoc.exists ? (stDoc.data()?['name'] ?? 'Okul') : 'Okul';

      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (ctx) => GuidanceInterviewScreen(institutionId: instId, schoolTypeId: stId, schoolTypeName: stName, isTeacher: true, teacherId: teacherId)));
      }
    } catch (e) {
      debugPrint('Hata: $e');
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _navigateToGuidanceActivity() async {
    setState(() => _isNavigating = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final userData = await UserPermissionService.loadUserData();
      final instId = (userData?['institutionId'] ?? widget.institutionId).toString().toUpperCase();
      final teacherId = userData?['id'] ?? user.uid;

      List<String> userSTIds = List<String>.from(userData?['schoolTypes'] ?? []);
      if (userSTIds.isEmpty) {
        final assignmentsSnap = await FirebaseFirestore.instance.collection('lessonAssignments').where('institutionId', isEqualTo: instId).where('teacherIds', arrayContains: teacherId).where('isActive', isEqualTo: true).get();
        userSTIds = assignmentsSnap.docs.map((doc) => doc.data()['schoolTypeId']?.toString()).where((id) => id != null).cast<String>().toSet().toList();
      }

      if (userSTIds.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bağlı olduğunuz bir okul türü bulunamadı.')));
        return;
      }

      final stId = userSTIds.first;
      final stDoc = await FirebaseFirestore.instance.collection('school_types').doc(stId).get();
      final stName = stDoc.exists ? (stDoc.data()?['name'] ?? 'Okul') : 'Okul';

      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (ctx) => ActivityListScreen(institutionId: instId, schoolTypeId: stId, schoolTypeName: stName)));
      }
    } catch (e) {
      debugPrint('Hata: $e');
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _navigateToSavedStudyPrograms() async {
    setState(() => _isNavigating = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final userData = await UserPermissionService.loadUserData();
      final instId = (userData?['institutionId'] ?? widget.institutionId).toString().toUpperCase();
      final teacherId = userData?['id'] ?? user.uid;

      final assignmentsSnap = await FirebaseFirestore.instance.collection('lessonAssignments').where('institutionId', isEqualTo: instId).where('teacherIds', arrayContains: teacherId).where('isActive', isEqualTo: true).get();
      final classIds = assignmentsSnap.docs.map((doc) => doc.data()['classId']?.toString()).where((id) => id != null).cast<String>().toSet().toList();

      List<String> classNames = [];
      List<String> studentIds = [];
      if (classIds.isNotEmpty) {
        final limitIds = classIds.length > 30 ? classIds.take(30).toList() : classIds;
        
        // Fetch Class Names
        final classesSnap = await FirebaseFirestore.instance.collection('classes').where(FieldPath.documentId, whereIn: limitIds).get();
        classNames = classesSnap.docs.map((d) => (d.data()['name'] ?? '').toString()).where((n) => n.isNotEmpty).toList();

        // Fetch Student IDs for these classes
        for (var i = 0; i < limitIds.length; i += 10) {
          final chunk = limitIds.sublist(i, i + 10 > limitIds.length ? limitIds.length : i + 10);
          final studentsSnap = await FirebaseFirestore.instance.collection('students').where('institutionId', isEqualTo: instId).where('classId', whereIn: chunk).where('isActive', isEqualTo: true).get();
          studentIds.addAll(studentsSnap.docs.map((doc) => doc.id));
        }
      }

      List<String> userSTIds = List<String>.from(userData?['schoolTypes'] ?? []);
      if (userSTIds.isEmpty) {
        userSTIds = assignmentsSnap.docs.map((doc) => doc.data()['schoolTypeId']?.toString()).where((id) => id != null).cast<String>().toSet().toList();
      }

      if (userSTIds.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bağlı olduğunuz bir okul türü bulunamadı.')));
        return;
      }

      final stId = userSTIds.first;
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (ctx) => SavedStudyProgramsScreen(
          institutionId: instId, 
          schoolTypeId: stId, 
          isTeacher: true, 
          allowedClassNames: classNames.isEmpty ? null : classNames,
          allowedStudentIds: studentIds.isEmpty ? null : studentIds,
        )));
      }
    } catch (e) {
      debugPrint('Hata: $e');
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _navigateToGuidanceTestCatalog() async {
    setState(() => _isNavigating = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final userData = await UserPermissionService.loadUserData();
      final instId = (userData?['institutionId'] ?? widget.institutionId).toString().toUpperCase();
      
      List<String> userSTIds = List<String>.from(userData?['schoolTypes'] ?? []);
      if (userSTIds.isEmpty) {
        final teacherId = userData?['id'] ?? user.uid;
        final assignmentsSnap = await FirebaseFirestore.instance.collection('lessonAssignments').where('institutionId', isEqualTo: instId).where('teacherIds', arrayContains: teacherId).where('isActive', isEqualTo: true).get();
        userSTIds = assignmentsSnap.docs.map((doc) => doc.data()['schoolTypeId']?.toString()).where((id) => id != null).cast<String>().toSet().toList();
      }

      if (userSTIds.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bağlı olduğunuz bir okul türü bulunamadı.')));
        return;
      }

      final stId = userSTIds.first;
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (ctx) => GuidanceTestCatalogScreen(institutionId: instId, schoolTypeId: stId)));
      }
    } catch (e) {
      debugPrint('Hata: $e');
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _navigateToDevelopmentReports() async {
    setState(() => _isNavigating = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final userData = await UserPermissionService.loadUserData();
      final instId = (userData?['institutionId'] ?? widget.institutionId).toString().toUpperCase();
      final teacherId = userData?['id'] ?? user.uid;

      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (ctx) => DevelopmentReportManagementScreen(institutionId: instId, isTeacher: true, teacherId: teacherId)));
      }
    } catch (e) {
      debugPrint('Hata: $e');
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  void _navigateToGuidanceLibrary() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rehberlik Kütüphanesi yakında eklenecek')));
  }

  Future<void> _navigateToTodoList() async {
    setState(() => _isNavigating = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final userData = await UserPermissionService.loadUserData();
      final instId = (userData?['institutionId'] ?? widget.institutionId).toString().toUpperCase();
      final teacherId = userData?['id'] ?? user.uid;

      List<String> userSTIds = List<String>.from(userData?['schoolTypes'] ?? []);
      if (userSTIds.isEmpty) {
        final assignmentsSnap = await FirebaseFirestore.instance.collection('lessonAssignments').where('institutionId', isEqualTo: instId).where('teacherIds', arrayContains: teacherId).where('isActive', isEqualTo: true).get();
        userSTIds = assignmentsSnap.docs.map((doc) => doc.data()['schoolTypeId']?.toString()).where((id) => id != null).cast<String>().toSet().toList();
      }

      if (userSTIds.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bağlı olduğunuz bir okul türü bulunamadı.')));
        return;
      }

      final stId = userSTIds.first;
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (ctx) => ToDoListScreen(institutionId: instId, schoolTypeId: stId)));
      }
    } catch (e) {
      debugPrint('Hata: $e');
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _navigateToTeacherDuty() async {
    setState(() => _isNavigating = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final userData = await UserPermissionService.loadUserData();
      final instId = (userData?['institutionId'] ?? widget.institutionId).toString().toUpperCase();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (ctx) => TeacherDutyScreen(
              institutionId: instId,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error navigating to teacher duty: $e');
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _navigateToLeaveManagement() async {
    setState(() => _isNavigating = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final userData = await UserPermissionService.loadUserData();
      final instId = (userData?['institutionId'] ?? widget.institutionId).toString().toUpperCase();
      final teacherId = userData?['id'] ?? user.uid;

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (ctx) => LeaveManagementScreen(
              institutionId: instId,
              isTeacherMode: true,
              forceUserId: teacherId,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error navigating to leave management: $e');
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _navigateToFieldTrip() async {
    setState(() => _isNavigating = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final userData = await UserPermissionService.loadUserData();
      final instId = (userData?['institutionId'] ?? widget.institutionId).toString().toUpperCase();
      final teacherId = userData?['id'] ?? user.uid;

      List<String> userSTIds = List<String>.from(userData?['schoolTypes'] ?? []);
      if (userSTIds.isEmpty) {
        final assignmentsSnap = await FirebaseFirestore.instance.collection('lessonAssignments').where('institutionId', isEqualTo: instId).where('teacherIds', arrayContains: teacherId).where('isActive', isEqualTo: true).get();
        userSTIds = assignmentsSnap.docs.map((doc) => doc.data()['schoolTypeId']?.toString()).where((id) => id != null).cast<String>().toSet().toList();
      }

      if (userSTIds.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bağlı olduğunuz bir okul türü bulunamadı.')));
        return;
      }

      final stId = userSTIds.first;
      final stDoc = await FirebaseFirestore.instance.collection('school_types').doc(stId).get();
      final stName = stDoc.exists ? (stDoc.data()?['name'] ?? 'Okul') : 'Okul';

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (ctx) => FieldTripListScreen(
              institutionId: instId,
              schoolTypeId: stId,
              schoolTypeName: stName,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error navigating to field trip: $e');
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Widget _buildCategorySelector() {
    final categories = [
      {'label': 'Tümü', 'icon': Icons.grid_view_rounded, 'id': 'Tümü'},
      {'label': 'Derslerim', 'icon': Icons.calendar_month, 'id': 'Derslerim'},
      {'label': 'Öğrenci Yönetimi', 'icon': Icons.people_alt, 'id': 'Ogrenciler'},
      {'label': 'Eğitim', 'icon': Icons.school, 'id': 'egitim'},
      {'label': 'Rehberlik', 'icon': Icons.folder_special, 'id': 'rehberlik'},
      {'label': 'Görev', 'icon': Icons.assignment_ind, 'id': 'gorev'},
    ];

    return Container(
      width: double.infinity,
      height: 120,
      child: Center(
        child: ScrollConfiguration(
          behavior: _MouseDraggableScrollBehavior(),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: categories.map((cat) {
                final isSelected = _selectedCategory == cat['label'];
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedCategory = cat['label'] as String;
                        if (_selectedCategory != 'Tümü') {
                          _expandedCategory = cat['id'] as String;
                        } else {
                          _expandedCategory = null;
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.indigo : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: isSelected
                                ? Colors.indigo.withOpacity(0.3)
                                : Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: isSelected ? Colors.indigo : Colors.grey.shade200,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            cat['icon'] as IconData,
                            color: isSelected ? Colors.white : Colors.indigo.shade400,
                            size: 24,
                          ),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              cat['label'] as String,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? Colors.white : Colors.grey.shade700,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridSections(bool isMobile) {
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth > 1400 ? 1400.0 : screenWidth;
    final availableWidth = contentWidth - (isMobile ? 32 : 48);

    final isFiltered = _selectedCategory != 'Tümü';
    double cardWidth;
    if (isFiltered) {
      cardWidth = availableWidth;
    } else if (availableWidth > 1000) {
      cardWidth = (availableWidth - 48) / 3;
    } else if (availableWidth > 700) {
      cardWidth = (availableWidth - 24) / 2;
    } else {
      cardWidth = availableWidth;
    }

    final List<_ModuleCardWidget> allModules = [
      _ModuleCardWidget(
        title: 'DERSLERİM',
        badge: 'Akademik',
        icon: Icons.calendar_month_rounded,
        color: Colors.blue,
        cardWidth: cardWidth,
        isMobile: isMobile,
        category: 'Derslerim',
        showAllItems: isFiltered,
        items: [
          {'title': 'Derslerim', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (ctx) => TeacherLessonsScreen(institutionId: widget.institutionId)))},
        ],
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (ctx) => TeacherLessonsScreen(institutionId: widget.institutionId))),
        buttonLabel: 'DERSLERİ GÖR',
      ),
      _ModuleCardWidget(
        title: 'ÖĞRENCİ YÖNETİMİ',
        badge: 'Öğrenci',
        icon: Icons.people_alt,
        color: Colors.green,
        cardWidth: cardWidth,
        isMobile: isMobile,
        category: 'Öğrenci Yönetimi',
        showAllItems: isFiltered,
        items: [
          {'title': 'Tanımlı Öğrencilerim', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (ctx) => TeacherStudentListScreen(institutionId: widget.institutionId)))},
          {'title': 'Öğrenci Portfolyoları', 'onTap': _navigateToPortfolio},
        ],
        onTap: () => setState(() => _selectedCategory = 'Öğrenci Yönetimi'),
      ),
      _ModuleCardWidget(
        title: 'EĞİTİM İŞLEMLERİ',
        badge: 'Eğitim',
        icon: Icons.school,
        color: Colors.orange,
        cardWidth: cardWidth,
        isMobile: isMobile,
        category: 'Eğitim',
        showAllItems: isFiltered,
        items: [
          {'title': 'Ders İşleyiş Planı', 'onTap': _navigateToWorkCalendar},
          {'title': 'Yoklama İstatistikleri', 'onTap': _navigateToAttendanceStats},
          {'title': 'Ödev İstatistikleri', 'onTap': _navigateToHomeworkStats},
          {'title': 'Etüt İşlemleri', 'onTap': _navigateToEtutProcess},
          {'title': 'Anket İşlemleri', 'onTap': _navigateToSurvey},
          {'title': 'Sınav Raporları', 'onTap': _navigateToAssessmentReports},
        ],
        onTap: () => setState(() => _selectedCategory = 'Eğitim'),
      ),
      _ModuleCardWidget(
        title: 'REHBERLİK İŞLEMLERİ',
        badge: 'Rehberlik',
        icon: Icons.folder_special,
        color: Colors.deepPurple,
        cardWidth: cardWidth,
        isMobile: isMobile,
        category: 'Rehberlik',
        showAllItems: isFiltered,
        items: [
          {'title': 'Görüşmeler', 'onTap': _navigateToGuidanceInterview},
          {'title': 'Gözlem ve Etkinlik İşlemleri', 'onTap': _navigateToGuidanceActivity},
          {'title': 'Ders Çalışma Programı', 'onTap': _navigateToSavedStudyPrograms},
          {'title': 'Rehberlik Envanterleri', 'onTap': _navigateToGuidanceTestCatalog},
          {'title': 'Rehberlik Kütüphanesi', 'onTap': _navigateToGuidanceLibrary},
          {'title': '360 Gelişim Raporları', 'onTap': _navigateToDevelopmentReports},
        ],
        onTap: () => setState(() => _selectedCategory = 'Rehberlik'),
      ),
      _ModuleCardWidget(
        title: 'GÖREVLENDİRME VE İZİN',
        badge: 'Görev',
        icon: Icons.assignment_ind,
        color: Colors.brown,
        cardWidth: cardWidth,
        isMobile: isMobile,
        category: 'Görev',
        showAllItems: isFiltered,
        items: [
          {'title': 'Nöbetlerim', 'onTap': _navigateToTeacherDuty},
          {'title': 'İzin İşlemleri', 'onTap': _navigateToLeaveManagement},
          {'title': 'Yapılacaklar (To-Do)', 'onTap': _navigateToTodoList},
          {'title': 'Giriş-Çıkış (QR)', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherQrScanScreen()))},
          {'title': 'Gezi Görevlendirmeleri', 'onTap': _navigateToFieldTrip},
        ],
        onTap: () => setState(() => _selectedCategory = 'Görev'),
      ),
    ];

    final filteredModules = (_selectedCategory == 'Tümü' 
        ? allModules 
        : allModules.where((m) => m.category == _selectedCategory).toList())
        .where((m) => m.items.isNotEmpty)
        .toList();

    return Wrap(
      key: ValueKey('grid_${_selectedCategory}_$isMobile'),
      spacing: 24,
      runSpacing: 24,
      children: filteredModules,
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Çıkış Yap'),
        content: const Text('Çıkış yapmak istediğinize emin misiniz?'),
        actions: [
          TextButton(
            child: const Text('İptal'),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Çıkış Yap', style: TextStyle(color: Colors.white)),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/school-login', (route) => false);
      }
    }
  }
}

class _MouseDraggableScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

class _ModuleCardWidget extends StatefulWidget {
  final String title;
  final String badge;
  final IconData icon;
  final Color color;
  final List<Map<String, dynamic>> items;
  final VoidCallback onTap;
  final double cardWidth;
  final bool isMobile;
  final String? buttonLabel;
  final String category;
  final bool showAllItems;

  const _ModuleCardWidget({
    Key? key,
    required this.title,
    required this.badge,
    required this.icon,
    required this.color,
    required this.items,
    required this.onTap,
    required this.cardWidth,
    required this.isMobile,
    this.buttonLabel,
    required this.category,
    this.showAllItems = false,
  }) : super(key: key);
  @override State<_ModuleCardWidget> createState() => _ModuleCardWidgetState();
}

class _ModuleCardWidgetState extends State<_ModuleCardWidget> {
  bool isCardHovered = false; int? hoveredItemIndex;
  @override Widget build(BuildContext context) {
    final displayedItems = widget.showAllItems ? widget.items : widget.items.take(3).toList(); final remainingCount = widget.items.length - displayedItems.length; final String label = remainingCount > 0 ? '+$remainingCount işlem daha görüntüle' : (widget.buttonLabel ?? 'GÖRÜNTÜLE');
    return MouseRegion(
      onEnter: (_) => setState(() => isCardHovered = true),
      onExit: (_) => setState(() => isCardHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: widget.cardWidth,
        height: (widget.isMobile || widget.showAllItems) ? null : 380,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isCardHovered || widget.showAllItems ? 0.08 : 0.03),
              blurRadius: isCardHovered || widget.showAllItems ? 30 : 20,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(
            color: isCardHovered || widget.showAllItems ? widget.color.withOpacity(0.3) : Colors.indigo.withOpacity(0.05),
            width: 1.5,
          ),
        ),
        padding: EdgeInsets.all(widget.isMobile ? 20 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 28),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.badge,
                    style: TextStyle(
                      color: widget.color,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              widget.title,
              style: TextStyle(
                fontSize: widget.isMobile ? 18 : 22,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF1E293B),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 24),
            ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayedItems.length,
              itemBuilder: (context, index) {
                final item = displayedItems[index];
                final isHovered = hoveredItemIndex == index;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: MouseRegion(
                    onEnter: (_) => setState(() => hoveredItemIndex = index),
                    onExit: (_) => setState(() => hoveredItemIndex = null),
                    child: InkWell(
                      onTap: item['onTap'] as VoidCallback,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isHovered ? widget.color : Colors.blueGrey.shade200,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item['title'] as String,
                                style: TextStyle(
                                  color: isHovered ? widget.color : Colors.blueGrey.shade600,
                                  fontSize: 14,
                                  fontWeight: isHovered ? FontWeight.w900 : FontWeight.w500,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                              color: isHovered ? widget.color : Colors.blueGrey.shade300,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (!widget.isMobile && !widget.showAllItems) const Spacer(),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isCardHovered ? widget.color : const Color(0xFFF1F5F9),
                  foregroundColor: isCardHovered ? Colors.white : Colors.blueGrey.shade700,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
