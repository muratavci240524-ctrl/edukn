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
        backgroundColor: Colors.indigo,
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Öğretmen İşlemleri',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Size Tanımlı Modüller',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            tooltip: 'İşlemler',
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
              const PopupMenuItem<String>(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person_outline, color: Colors.indigo),
                    SizedBox(width: 8),
                    Text('Profilim'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'qr_scan',
                child: Row(
                  children: [
                    Icon(Icons.qr_code_scanner_rounded, color: Colors.indigo),
                    SizedBox(width: 8),
                    Text('Giriş/Çıkış (QR)'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Çıkış Yap', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: Container(
              constraints: BoxConstraints(maxWidth: 1200),
              child: Column(
                children: [
                  _buildCategorySelector(),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.all(16),
                      children: [
                        // DERS PROGRAMIM KISMI - Tümü ekranında en üstte görünecek özel buton (Kullanıcının isteği)
                        if (_selectedCategory == 'Tümü' || _selectedCategory == 'Derslerim')
                          Card(
                            elevation: 2,
                            margin: EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (ctx) => TeacherLessonsScreen(institutionId: widget.institutionId),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(Icons.calendar_month_rounded, color: Colors.blue, size: 28),
                                    ),
                                    SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Derslerim / Programım',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            'Sadece kendi ders programınızı görüntüleyin',
                                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        
                        if (_selectedCategory == 'Tümü' || _selectedCategory == 'Öğrenci Yönetimi')
                          _buildExpandableCategory(
                            categoryId: 'ogrenciler',
                            title: 'Öğrenci Yönetimi',
                            icon: Icons.people_alt,
                            color: Colors.green,
                            children: [
                              _buildModuleItem(
                                Icons.list_alt,
                                'Tanımlı Öğrencilerim',
                                Colors.green,
                                'Sadece size tanımlı olan öğrencileri listeleyin',
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (ctx) => TeacherStudentListScreen(institutionId: widget.institutionId),
                                    ),
                                  );
                                },
                              ),
                              _buildModuleItem(
                                Icons.folder_special, 
                                'Öğrenci Portfolyoları', 
                                Colors.green, 
                                'Öğrencilerinizin durumunu inceleyin',
                                onTap: _navigateToPortfolio,
                              ),
                            ],
                          ),
                        if (_selectedCategory == 'Tümü' || _selectedCategory == 'Öğrenci Yönetimi')
                          SizedBox(height: 12),

                        if (_selectedCategory == 'Tümü' || _selectedCategory == 'Eğitim')
                          _buildExpandableCategory(
                            categoryId: 'egitim',
                            title: 'Eğitim İşlemleri',
                            icon: Icons.school,
                            color: Colors.orange,
                            children: [
                              _buildModuleItem(
                                Icons.play_lesson, 
                                'Ders İşleyiş Planı', 
                                Colors.orange, 
                                'Günlük ve yıllık planlarınızı yönetin',
                                onTap: _navigateToWorkCalendar,
                              ),
                              _buildModuleItem(
                                Icons.pie_chart_outline, 
                                'Yoklama İstatistikleri', 
                                Colors.orange, 
                                'Yoklama verilerini analiz edin',
                                onTap: _navigateToAttendanceStats,
                              ),
                                _buildModuleItem(
                                  Icons.assignment_turned_in, 
                                  'Ödev İstatistikleri', 
                                  Colors.orange, 
                                  'Ödev başarı ve risk analizlerini inceleyin',
                                  onTap: _navigateToHomeworkStats,
                                ),
                                _buildModuleItem(
                                  Icons.task, 
                                  'Etüt İşlemleri', 
                                  Colors.orange, 
                                  'Tanımlı etütleri yönetin',
                                  onTap: _navigateToEtutProcess,
                                ),
                                _buildModuleItem(
                                  Icons.poll_outlined, 
                                  'Anket İşlemleri', 
                                  Colors.orange, 
                                  'Anketlerinizi yönetin ve sonuçları inceleyin',
                                  onTap: _navigateToSurvey,
                                ),
                                _buildModuleItem(
                                  Icons.analytics_outlined, 
                                  'Sınav Raporları', 
                                  Colors.orange, 
                                  'Detaylı analizleri inceleyin',
                                  onTap: _navigateToAssessmentReports,
                                ),
                            ],
                          ),
                        if (_selectedCategory == 'Tümü' || _selectedCategory == 'Eğitim')
                          SizedBox(height: 12),

                        if (_selectedCategory == 'Tümü' || _selectedCategory == 'Rehberlik')
                          _buildExpandableCategory(
                            categoryId: 'rehberlik',
                            title: 'Rehberlik İşlemleri',
                            icon: Icons.folder_special,
                            color: Colors.deepPurple,
                            children: [
                              _buildModuleItem(Icons.connect_without_contact, 'Görüşmeler', Colors.deepPurple, 'Geçmiş görüşmelerinizi inceleyin', onTap: _navigateToGuidanceInterview),
                              _buildModuleItem(Icons.visibility, 'Gözlem ve Etkinlik İşlemleri', Colors.deepPurple, 'Gözlem ve etkinlikleri görüntüleyin', onTap: _navigateToGuidanceActivity),
                              _buildModuleItem(Icons.edit_calendar, 'Ders Çalışma Programı', Colors.deepPurple, 'Kendi şubelerinizin programları', onTap: _navigateToSavedStudyPrograms),
                              _buildModuleItem(Icons.assignment_turned_in, 'Rehberlik Envanterleri', Colors.deepPurple, 'Envanter işlemlerini gerçekleştirin', onTap: _navigateToGuidanceTestCatalog),
                              _buildModuleItem(Icons.local_library, 'Rehberlik Kütüphanesi', Colors.deepPurple, 'Kütüphane dökümanları', onTap: _navigateToGuidanceLibrary),
                              _buildModuleItem(Icons.analytics, '360 Gelişim Raporları', Colors.deepPurple, 'Size yönlendirilen raporları yorumlayın', onTap: _navigateToDevelopmentReports),
                            ],
                          ),
                        if (_selectedCategory == 'Tümü' || _selectedCategory == 'Rehberlik')
                          SizedBox(height: 12),

                          
                        if (_selectedCategory == 'Tümü' || _selectedCategory == 'Görev')
                          _buildExpandableCategory(
                            categoryId: 'gorev',
                            title: 'Görevlendirme ve İzin',
                            icon: Icons.assignment_ind,
                            color: Colors.brown,
                            children: [
                              _buildModuleItem(Icons.security, 'Nöbetlerim', Colors.brown, 'Nöbet bilgilerinizi görün', onTap: _navigateToTeacherDuty),
                              _buildModuleItem(Icons.time_to_leave, 'İzin İşlemleri', Colors.brown, 'İzin talep edin ve geçmişi görün', onTap: _navigateToLeaveManagement),
                              _buildModuleItem(Icons.playlist_add_check, 'Yapılacaklar (To-Do)', Colors.brown, 'Görevlerinizi yönetin', onTap: _navigateToTodoList),
                              _buildModuleItem(Icons.qr_code_scanner, 'Giriş-Çıkış (QR)', Colors.brown, 'QR kod okutarak mesai başlat/bitir', onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const TeacherQrScanScreen()),
                                );
                              }),
                              _buildModuleItem(Icons.map_outlined, 'Gezi Görevlendirmeleri', Colors.brown, 'Gezi planlarını yönetin', onTap: _navigateToFieldTrip),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
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

  Widget _buildExpandableCategory({
    required String categoryId,
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    final isExpanded = _expandedCategory == categoryId || _selectedCategory == title;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCategory = null;
                } else {
                  _expandedCategory = categoryId;
                }
              });
            },
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                   Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 28),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '${children.length} İşlem Modülü',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Column(
                children: children,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModuleItem(IconData icon, String title, Color color, String subtitle, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap ?? () {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$title Sayfası (Öğretmene Özel)')));
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    )
                  ]
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
          ],
        ),
      ),
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
