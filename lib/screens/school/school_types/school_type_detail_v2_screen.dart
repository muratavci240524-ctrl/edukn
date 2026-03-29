import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import '../../../services/term_service.dart';
import 'school_type_announcements_screen.dart';
import 'school_type_social_media_screen.dart';
import '../student_registration_screen.dart';
import '../../hr/staff/staff_list_screen.dart';
import '../class_management_screen.dart';
import '../lesson_management_screen.dart';
import '../classroom_management_screen.dart';
import '../work_calendar_screen.dart';
import '../lesson_hours_screen.dart';
import '../class_schedule_screen.dart';
import '../class_schedule_view_screen.dart';
import '../teacher_schedule_view_screen.dart';
import '../user_profile_screen.dart';
import '../attendance_operations_screen.dart';
import '../survey/survey_list_screen.dart';
import '../assessment/trial_exam_list_screen.dart';
import '../assessment/active_exam_list_screen.dart';
import '../assessment/assessment_definitions_screen.dart';
import '../assessment/assessment_reports_screen.dart';
import '../../portfolio/portfolio_screen.dart';
import '../tasks/todo_list_screen.dart';
import '../tasks/substitute_teacher_list_screen.dart';
import '../tasks/duty_management_screen.dart';
import '../tasks/field_trip_list_screen.dart';
import '../tasks/project_assignments/project_assignment_list_screen.dart';
import '../homework/homework_operations_screen.dart';
import '../book_management_screen.dart';
import '../etut_process_screen.dart';
import '../activity/activity_list_screen.dart';
import 'chat/chat_screen.dart';
import '../../hr/leave/leave_management_screen.dart';
import '../../../../widgets/stylish_bottom_nav.dart';
import '../guidance/guidance_interview_screen.dart';
import '../guidance/guidance_study_program_screen.dart';
import '../../guidance/guidance_test_catalog_screen.dart';
import '../../support_services/cafeteria/cafeteria_screen.dart';
import '../../support_services/transportation/transportation_screen.dart';
import '../../support_services/health/health_screen.dart';
import '../../support_services/library/library_screen.dart';
import '../../support_services/cleaning/cleaning_screen.dart';
import '../../support_services/inventory/inventory_screen.dart';
import '../../guidance/reports/development_report_management_screen.dart';
import '../notes/personal_notes_screen.dart';

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
      };
}

class SchoolTypeDetailV2Screen extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const SchoolTypeDetailV2Screen({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<SchoolTypeDetailV2Screen> createState() => _SchoolTypeDetailV2ScreenState();
}

class _SchoolTypeDetailV2ScreenState extends State<SchoolTypeDetailV2Screen> {
  int _currentIndex = 0;
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      SchoolTypeAnnouncementsScreen(
        schoolTypeId: widget.schoolTypeId,
        schoolTypeName: widget.schoolTypeName,
        institutionId: widget.institutionId,
      ),
      SchoolTypeSocialMediaScreen(
        schoolTypeId: widget.schoolTypeId,
        schoolTypeName: widget.schoolTypeName,
        institutionId: widget.institutionId,
      ),
      _DashboardTab(
        schoolTypeId: widget.schoolTypeId,
        schoolTypeName: widget.schoolTypeName,
        institutionId: widget.institutionId,
      ),
      _MessagesTab(
        schoolTypeId: widget.schoolTypeId,
        schoolTypeName: widget.schoolTypeName,
        institutionId: widget.institutionId,
      ),
      _OperationsV2Tab(
        schoolTypeId: widget.schoolTypeId,
        schoolTypeName: widget.schoolTypeName,
        institutionId: widget.institutionId,
      ),
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

class _MessagesTab extends StatelessWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const _MessagesTab({required this.schoolTypeId, required this.schoolTypeName, required this.institutionId});

  @override
  Widget build(BuildContext context) {
    return ChatScreen(
      schoolTypeId: schoolTypeId,
      schoolTypeName: schoolTypeName,
      institutionId: institutionId,
    );
  }
}

class _DashboardTab extends StatelessWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const _DashboardTab({required this.schoolTypeId, required this.schoolTypeName, required this.institutionId});

  @override
  Widget build(BuildContext context) {
    // Current Dashboard Tab logic ... using existing or simplified version
    return Center(child: Text('Dashboard (V2 Bekleniyor)'));
  }
}

class _OperationsV2Tab extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const _OperationsV2Tab({
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
  });

  @override
  State<_OperationsV2Tab> createState() => _OperationsV2TabState();
}

class _OperationsV2TabState extends State<_OperationsV2Tab> {
  String _selectedCategory = 'Tümü';
  List<Map<String, dynamic>> _terms = [];
  Map<String, dynamic>? _selectedTerm;

  @override
  void initState() {
    super.initState();
    _loadTerms();
  }

  Future<void> _loadTerms() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) return;
      final institutionId = user.email!.split('@')[1].split('.')[0].toUpperCase();
      final snapshot = await FirebaseFirestore.instance.collection('terms').where('institutionId', isEqualTo: institutionId).get();
      final termsList = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
      termsList.sort((a, b) => (b['startYear'] ?? 0).compareTo(a['startYear'] ?? 0));
      final active = termsList.firstWhere((t) => t['isActive'] == true, orElse: () => termsList.isNotEmpty ? termsList.first : {});
      final prefs = await SharedPreferences.getInstance();
      final savedTermId = prefs.getString('selected_term_id');
      Map<String, dynamic>? selectedTerm;
      if (savedTermId != null) {
        selectedTerm = termsList.firstWhere((t) => t['id'] == savedTermId, orElse: () => {});
        if (selectedTerm.isEmpty) selectedTerm = null;
      }
      if (mounted) setState(() { _terms = termsList; _selectedTerm = selectedTerm ?? (active.isNotEmpty ? active : null); });
    } catch (e) { print('Dönemler yüklenirken hata: $e'); }
  }

  void _showTermSelector() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [const Icon(Icons.calendar_month, color: Colors.blue), const SizedBox(width: 8), const Text('Dönem Seç', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))]),
            const Divider(height: 24),
            if (_terms.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('Henüz dönem tanımlanmamış')))
            else ...(_terms.map((term) {
              final isActive = term['isActive'] == true;
              final isSelected = _selectedTerm?['id'] == term['id'];
              return ListTile(
                leading: CircleAvatar(backgroundColor: isActive ? Colors.green[100] : Colors.grey[100], child: Icon(isActive ? Icons.check_circle : Icons.calendar_today, color: isActive ? Colors.green : Colors.grey)),
                title: Text('${term['startYear']}-${term['endYear']}', style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                subtitle: isActive ? const Text('Aktif Dönem', style: TextStyle(color: Colors.green)) : null,
                trailing: isSelected ? const Icon(Icons.radio_button_checked, color: Colors.blue) : const Icon(Icons.radio_button_off),
                onTap: () async {
                  final isActive = term['isActive'] == true;
                  if (isActive) { await TermService().clearSelectedTerm(); } 
                  else { await TermService().setSelectedTerm(term['id'], term['name'] ?? ''); }
                  setState(() => _selectedTerm = term);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isActive ? '✓ Aktif döneme geri dönüldü' : '✓ ${term['startYear']}-${term['endYear']} dönemine geçildi'), backgroundColor: isActive ? Colors.blue : Colors.green, duration: const Duration(seconds: 2)));
                },
              );
            }).toList()),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 1100;
    final bool isViewingPastTerm = _selectedTerm != null && _selectedTerm!['isActive'] != true;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.indigo,
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.schoolTypeName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            Text('İşlemler V2', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
          ],
        ),
        actions: size.width < 600 ? [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              if (value == 'term') { _showTermSelector(); } 
              else if (value == 'profile') { Navigator.push(context, MaterialPageRoute(builder: (ctx) => const UserProfileScreen())); } 
              else if (value == 'home') { Navigator.pop(context); }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'term', child: Row(children: [Icon(isViewingPastTerm ? Icons.history : Icons.calendar_month, color: Colors.indigo), const SizedBox(width: 12), const Text('Dönem Değiştir')])),
              const PopupMenuItem(value: 'profile', child: Row(children: [Icon(Icons.account_circle_outlined, color: Colors.indigo), const SizedBox(width: 12), const Text('Profil Bilgisi')])),
              const PopupMenuItem(value: 'home', child: Row(children: [Icon(Icons.home_outlined, color: Colors.indigo), const SizedBox(width: 12), const Text('Anasayfaya Dön')])),
            ],
          ),
        ] : [
          // Dönem Seçici
          InkWell(
            onTap: _showTermSelector,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isViewingPastTerm ? Colors.orange[50] : Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isViewingPastTerm ? Colors.orange[400]! : Colors.white.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(isViewingPastTerm ? Icons.history : Icons.calendar_month, size: 16, color: isViewingPastTerm ? Colors.orange[700] : Colors.white),
                  const SizedBox(width: 6),
                  Text(_selectedTerm != null ? '${_selectedTerm!['startYear']}-${_selectedTerm!['endYear']}' : 'Dönem', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isViewingPastTerm ? Colors.orange[700] : Colors.white)),
                  Icon(Icons.arrow_drop_down, size: 16, color: isViewingPastTerm ? Colors.orange[700] : Colors.white),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.account_circle_outlined, color: Colors.white), tooltip: 'Profilim', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (ctx) => const UserProfileScreen()))),
          IconButton(icon: const Icon(Icons.home_outlined, color: Colors.white), tooltip: 'Anasayfaya Dön', onPressed: () => Navigator.pop(context)),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: DoodlePainter()))),
                SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 1400),
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 24),
                      child: Column(
                        children: [
                          _buildCategorySelector(isMobile),
                          const SizedBox(height: 32),
                          _buildGridSections(isMobile),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySelector(bool isMobile) {
    final categories = [
      {'id': 'Tümü', 'label': 'Tümü', 'icon': Icons.grid_view_rounded},
      {'id': 'Kayıt', 'label': 'Kayıt', 'icon': Icons.app_registration},
      {'id': 'Eğitim', 'label': 'Eğitim', 'icon': Icons.school_rounded},
      {'id': 'Portfolyo', 'label': 'Portfolyo', 'icon': Icons.folder_special_rounded},
      {'id': 'Ölçme', 'label': 'Ölçme', 'icon': Icons.assignment_turned_in_outlined},
      {'id': 'Görevlendirme', 'label': 'Görev', 'icon': Icons.assignment_ind_rounded},
      {'id': 'Destek', 'label': 'Destek', 'icon': Icons.support_agent_rounded},
      {'id': 'Raporlar', 'label': 'Raporlar', 'icon': Icons.analytics_rounded},
      {'id': 'Ayarlar', 'label': 'Ayarlar', 'icon': Icons.settings_rounded},
    ];

    return Container(
      width: double.infinity,
      height: 100,
      alignment: Alignment.center,
      child: ScrollConfiguration(
        behavior: MyCustomScrollBehavior(),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: categories.map((cat) {
              final isSelected = _selectedCategory == (cat['id'] as String);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: InkWell(
                  onTap: () => setState(() => _selectedCategory = cat['id'] as String),
                  borderRadius: BorderRadius.circular(20),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: isMobile ? 85 : 95,
                    height: isMobile ? 85 : 95,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.indigo : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: isSelected ? Colors.indigo.withOpacity(0.3) : Colors.black.withOpacity(0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                      border: Border.all(color: isSelected ? Colors.indigo : Colors.indigo.shade50, width: 1),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(cat['icon'] as IconData, color: isSelected ? Colors.white : Colors.indigo.shade400, size: 24),
                        const SizedBox(height: 8),
                        Text(cat['label'] as String, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, color: isSelected ? Colors.white : Colors.indigo.shade900)),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildGridSections(bool isMobile) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isAllSelected = _selectedCategory == 'Tümü';
        
        final List<Map<String, dynamic>> moduleData = [
          {
            'title': 'KAYIT İŞLEMLERİ', 'badge': 'Kayıt', 'icon': Icons.app_registration, 'color': Colors.blue, 'onTap': () => setState(() => _selectedCategory = 'Kayıt'),
            'items': [
              {'title': 'Öğrenci Listesi', 'onTap': () => _navigateToStudentRegistration()},
              {'title': 'Personel Listesi', 'onTap': () => _navigateToStaffList()},
              {'title': 'Şube Listesi', 'onTap': () => _navigateToClassManagement()},
              {'title': 'Ders Listesi', 'onTap': () => _navigateToLessonManagement()},
              {'title': 'Derslik Listesi', 'onTap': () => _navigateToClassroomManagement()},
              {'title': 'Kitap Listesi', 'onTap': () => _navigateToBookManagement()},
            ]
          },
          {
            'title': 'EĞİTİM İŞLEMLERİ', 'badge': 'Eğitim', 'icon': Icons.school, 'color': Colors.green, 'onTap': () => setState(() => _selectedCategory = 'Eğitim'),
            'items': [
              {'title': 'Çalışma Takvimi', 'onTap': () => _navigateToWorkCalendar()},
              {'title': 'Ders Saatleri', 'onTap': () => _navigateToLessonHours()},
              {'title': 'Ders Programı', 'onTap': () => _navigateToClassSchedule()},
              {'title': 'Şube Ders Programı', 'onTap': () => _navigateToClassScheduleView()},
              {'title': 'Öğretmen Ders Programı', 'onTap': () => _navigateToTeacherScheduleView()},
              {'title': 'Anket İşlemleri', 'onTap': () => _navigateToSurveyList()},
              {'title': 'Etüt İşlemleri', 'onTap': () => _navigateToEtutProcess()},
            ]
          },
          {
            'title': 'REHBERLİK VE PORTFOLYO', 'badge': 'Portfolyo', 'icon': Icons.folder_special, 'color': Colors.deepPurple, 'onTap': () => setState(() => _selectedCategory = 'Portfolyo'),
            'items': [
              {'title': 'Portfolyo', 'onTap': () => _navigateToPortfolio()},
              {'title': 'Görüşmeler', 'onTap': () => _navigateToGuidanceInterview()},
              {'title': 'Gözlem ve Etkinlikler', 'onTap': () => _navigateToActivityList()},
              {'title': 'Çalışma Programı', 'onTap': () => _navigateToGuidanceStudyProgram()},
              {'title': 'Envanterler', 'onTap': () => _navigateToGuidanceTestCatalog()},
              {'title': '360 Gelişim Raporları', 'onTap': () => _navigateToDevelopmentReport()},
            ]
          },
          {
            'title': 'ÖLÇME DEĞERLENDİRME', 'badge': 'Ölçme', 'icon': Icons.bar_chart, 'color': Colors.red, 'onTap': () => setState(() => _selectedCategory = 'Ölçme'),
            'items': [
              {'title': 'Raporlar', 'onTap': () => _navigateToAssessmentReports()},
              {'title': 'Denemeler', 'onTap': () => _navigateToTrialExams()},
              {'title': 'Sınavlar', 'onTap': () => _navigateToActiveExams()},
              {'title': 'Tanımlar', 'onTap': () => _navigateToAssessmentDefinitions()},
            ]
          },
          {
            'title': 'GÖREVLENDİRME VE İZİN', 'badge': 'Görevlendirme', 'icon': Icons.assignment_ind, 'color': Colors.brown, 'onTap': () => setState(() => _selectedCategory = 'Görevlendirme'),
            'items': [
              {'title': 'To do List', 'onTap': () => _navigateToToDoList()},
              {'title': 'İzin Yönetimi', 'onTap': () => _navigateToLeaveManagement()},
              {'title': 'Geçici Öğretmen', 'onTap': () => _navigateToSubstituteTeacher()},
              {'title': 'Nöbet İşlemleri', 'onTap': () => _navigateToDutyManagement()},
              {'title': 'Gezi Görevlendirmeleri', 'onTap': () => _navigateToFieldTripList()},
              {'title': 'Proje Görevlendirmeleri', 'onTap': () => _navigateToProjectAssignment()},
            ]
          },
          {
            'title': 'DESTEK HİZMETLERİ', 'badge': 'Destek', 'icon': Icons.support_agent, 'color': Colors.cyan, 'onTap': () => setState(() => _selectedCategory = 'Destek'),
            'items': [
              {'title': 'Yemekhane İşlemleri', 'onTap': () => _navigateToCafeteria()},
              {'title': 'Servis İşlemleri', 'onTap': () => _navigateToTransportation()},
              {'title': 'Sağlık İşlemleri', 'onTap': () => _navigateToHealth()},
              {'title': 'Kütüphane İşlemleri', 'onTap': () => _navigateToLibrary()},
              {'title': 'Temizlik İşlemleri', 'onTap': () => _navigateToCleaning()},
              {'title': 'Depo ve Satın Alma', 'onTap': () => _navigateToInventory()},
            ]
          },
          {
            'title': 'RAPORLAR İŞLEMLERİ', 'badge': 'Raporlar', 'icon': Icons.analytics_outlined, 'color': Colors.indigo, 'onTap': () => setState(() => _selectedCategory = 'Raporlar'),
            'items': [
              {'title': 'Yoklama Raporları', 'onTap': () => _navigateToAttendanceOperations()},
              {'title': 'Ödev Raporları', 'onTap': () => _navigateToHomeworkOperations()},
              {'title': 'Ölçme Raporları', 'onTap': () => _navigateToAssessmentReports()},
            ]
          },
          {
            'title': 'SİSTEM AYARLARI', 'badge': 'Ayarlar', 'icon': Icons.settings, 'color': Colors.blueGrey, 'onTap': () => setState(() => _selectedCategory = 'Ayarlar'),
            'items': [
              {'title': 'Yetki Tanımlama', 'onTap': () => Navigator.pushNamed(context, '/permission-definition')},
              {'title': 'Kullanıcı Yetkilendirme', 'onTap': () => Navigator.pushNamed(context, '/user-management')},
              {'title': 'Uygulama Ayarları', 'onTap': () => Navigator.pushNamed(context, '/app-settings')},
            ]
          },
        ];

        final filteredData = isAllSelected ? moduleData : moduleData.where((d) => d['badge'] == _selectedCategory).toList();

        if (isMobile || !isAllSelected) {
          return Column(
            children: filteredData.map((d) => Padding(
              padding: const EdgeInsets.only(bottom: 24), 
              child: _ModuleCardWidget(
                title: d['title'], badge: d['badge'], icon: d['icon'], color: d['color'], items: d['items'], onTap: d['onTap'], isMobile: isMobile, buttonLabel: d['buttonLabel'],
                showAllItems: !isAllSelected,
              )
            )).toList(),
          );
        }

        int count = constraints.maxWidth > 1100 ? 3 : 2;
        double? extent = 350;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: 24,
            mainAxisSpacing: 24,
            mainAxisExtent: extent, 
          ),
          itemCount: filteredData.length,
          itemBuilder: (context, index) {
            final d = filteredData[index];
            return _ModuleCardWidget(
              title: d['title'], badge: d['badge'], icon: d['icon'], color: d['color'], items: d['items'], onTap: d['onTap'], isMobile: isMobile, buttonLabel: d['buttonLabel'],
              showAllItems: !isAllSelected,
            );
          },
        );
      },
    );
  }

  Widget _buildFixedBottom(bool isMobile) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.indigo.shade50))),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1400),
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('© 2026 eduKN.', style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCardCompact({required String title, required IconData icon, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  // Navigation Methods (To match original screen)
  void _navigateToStudentRegistration() => Navigator.push(context, MaterialPageRoute(builder: (c) => StudentRegistrationScreen(fixedSchoolTypeId: widget.schoolTypeId, fixedSchoolTypeName: widget.schoolTypeName, fixedInstitutionId: widget.institutionId)));
  void _navigateToStaffList() => Navigator.push(context, MaterialPageRoute(builder: (c) => StaffListScreen(fixedSchoolTypeId: widget.schoolTypeId, fixedSchoolTypeName: widget.schoolTypeName)));
  void _navigateToClassManagement() => Navigator.push(context, MaterialPageRoute(builder: (c) => ClassManagementScreen(schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName, institutionId: widget.institutionId)));
  void _navigateToLessonManagement() => Navigator.push(context, MaterialPageRoute(builder: (c) => LessonManagementScreen(schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName, institutionId: widget.institutionId)));
  void _navigateToClassroomManagement() => Navigator.push(context, MaterialPageRoute(builder: (c) => ClassroomManagementScreen(schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName, institutionId: widget.institutionId)));
  void _navigateToBookManagement() => Navigator.push(context, MaterialPageRoute(builder: (c) => BookManagementScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)));
  void _navigateToWorkCalendar() => Navigator.push(context, MaterialPageRoute(builder: (c) => WorkCalendarScreen(schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName, institutionId: widget.institutionId)));
  void _navigateToLessonHours() => Navigator.push(context, MaterialPageRoute(builder: (c) => LessonHoursScreen(schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName, institutionId: widget.institutionId)));
  void _navigateToClassSchedule() => Navigator.push(context, MaterialPageRoute(builder: (c) => ClassScheduleScreen(schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName, institutionId: widget.institutionId)));
  void _navigateToClassScheduleView() => Navigator.push(context, MaterialPageRoute(builder: (c) => ClassScheduleViewScreen(schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName, institutionId: widget.institutionId)));
  void _navigateToTeacherScheduleView() => Navigator.push(context, MaterialPageRoute(builder: (c) => TeacherScheduleViewScreen(schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName, institutionId: widget.institutionId)));
  void _navigateToSurveyList() => Navigator.push(context, MaterialPageRoute(builder: (c) => SurveyListScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)));
  void _navigateToEtutProcess() => Navigator.push(context, MaterialPageRoute(builder: (c) => EtutProcessScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)));
  void _navigateToPortfolio() => Navigator.push(context, MaterialPageRoute(builder: (c) => PortfolioScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)));
  void _navigateToGuidanceInterview() => Navigator.push(context, MaterialPageRoute(builder: (c) => GuidanceInterviewScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)));
  void _navigateToActivityList() => Navigator.push(context, MaterialPageRoute(builder: (c) => ActivityListScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)));
  void _navigateToGuidanceStudyProgram() => Navigator.push(context, MaterialPageRoute(builder: (c) => GuidanceStudyProgramScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId)));
  void _navigateToGuidanceTestCatalog() => Navigator.push(context, MaterialPageRoute(builder: (c) => GuidanceTestCatalogScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId)));
  void _navigateToDevelopmentReport() => Navigator.push(context, MaterialPageRoute(builder: (c) => DevelopmentReportManagementScreen(institutionId: widget.institutionId)));
  void _navigateToAssessmentReports() => Navigator.push(context, MaterialPageRoute(builder: (c) => AssessmentReportsScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId)));
  void _navigateToTrialExams() => Navigator.push(context, MaterialPageRoute(builder: (c) => TrialExamListScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId)));
  void _navigateToActiveExams() => Navigator.push(context, MaterialPageRoute(builder: (c) => ActiveExamListScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId)));
  void _navigateToAssessmentDefinitions() => Navigator.push(context, MaterialPageRoute(builder: (c) => AssessmentDefinitionsScreen(institutionId: widget.institutionId)));
  void _navigateToToDoList() => Navigator.push(context, MaterialPageRoute(builder: (c) => ToDoListScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId)));
  void _navigateToLeaveManagement() => Navigator.push(context, MaterialPageRoute(builder: (c) => const LeaveManagementScreen()));
  void _navigateToSubstituteTeacher() => Navigator.push(context, MaterialPageRoute(builder: (c) => SubstituteTeacherListScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)));
  void _navigateToDutyManagement() => Navigator.push(context, MaterialPageRoute(builder: (c) => DutyManagementScreen(institutionId: widget.institutionId)));
  void _navigateToFieldTripList() => Navigator.push(context, MaterialPageRoute(builder: (c) => FieldTripListScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)));
  void _navigateToProjectAssignment() => Navigator.push(context, MaterialPageRoute(builder: (c) => ProjectAssignmentListScreen(institutionId: widget.institutionId)));
  void _navigateToCafeteria() => Navigator.push(context, MaterialPageRoute(builder: (c) => CafeteriaScreen(fixedSchoolTypeId: widget.schoolTypeId, fixedSchoolTypeName: widget.schoolTypeName)));
  void _navigateToTransportation() => Navigator.push(context, MaterialPageRoute(builder: (c) => TransportationScreen(fixedSchoolTypeId: widget.schoolTypeId, fixedSchoolTypeName: widget.schoolTypeName)));
  void _navigateToHealth() => Navigator.push(context, MaterialPageRoute(builder: (c) => HealthScreen(fixedSchoolTypeId: widget.schoolTypeId, fixedSchoolTypeName: widget.schoolTypeName)));
  void _navigateToLibrary() => Navigator.push(context, MaterialPageRoute(builder: (c) => LibraryScreen(fixedSchoolTypeId: widget.schoolTypeId, fixedSchoolTypeName: widget.schoolTypeName)));
  void _navigateToCleaning() => Navigator.push(context, MaterialPageRoute(builder: (c) => CleaningScreen(fixedSchoolTypeId: widget.schoolTypeId, fixedSchoolTypeName: widget.schoolTypeName)));
  void _navigateToInventory() => Navigator.push(context, MaterialPageRoute(builder: (c) => InventoryScreen(fixedSchoolTypeId: widget.schoolTypeId, fixedSchoolTypeName: widget.schoolTypeName)));
  void _navigateToAttendanceOperations() => Navigator.push(context, MaterialPageRoute(builder: (c) => AttendanceOperationsScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)));
  void _navigateToHomeworkOperations() => Navigator.push(context, MaterialPageRoute(builder: (c) => HomeworkOperationsScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId)));
}

class _ModuleCardWidget extends StatefulWidget {
  final String title; final String badge; final IconData icon; final Color color; final List<Map<String, dynamic>> items; final VoidCallback onTap; final bool isMobile; final String? buttonLabel; final bool showAllItems;
  const _ModuleCardWidget({Key? key, required this.title, required this.badge, required this.icon, required this.color, required this.items, required this.onTap, required this.isMobile, this.buttonLabel, this.showAllItems = false}) : super(key: key);
  @override State<_ModuleCardWidget> createState() => _ModuleCardWidgetState();
}

class _ModuleCardWidgetState extends State<_ModuleCardWidget> {
  bool isCardHovered = false; int? hoveredItemIndex;
  @override Widget build(BuildContext context) {
    final displayedItems = widget.showAllItems ? widget.items : widget.items.take(3).toList();
    final remainingCount = widget.showAllItems ? 0 : (widget.items.length - 3);
    final String label = remainingCount > 0 ? '+$remainingCount işlem daha görüntüle' : (widget.buttonLabel ?? 'GÖRÜNTÜLE');
    final bool useFixedLayout = !widget.isMobile && !widget.showAllItems;
    return MouseRegion(
      onEnter: (_) => setState(() => isCardHovered = true), 
      onExit: (_) => setState(() => isCardHovered = false), 
      child: Container(
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(widget.isMobile ? 24 : 32), border: Border.all(color: isCardHovered ? widget.color : Colors.transparent, width: 1.5)), 
        padding: EdgeInsets.all(widget.isMobile ? 24 : 32), 
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, 
          mainAxisSize: useFixedLayout ? MainAxisSize.max : MainAxisSize.min, 
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: widget.color.withOpacity(0.1), borderRadius: BorderRadius.circular(16)), child: Icon(widget.icon, color: widget.color, size: 24)), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: widget.color.withOpacity(0.1), borderRadius: BorderRadius.circular(100)), child: Text(widget.badge, style: TextStyle(color: widget.color, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)))]), 
            const SizedBox(height: 24), 
            Text(widget.title, style: TextStyle(fontSize: widget.isMobile ? 18 : 20, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))), 
            const SizedBox(height: 20), 
            ListView.builder(shrinkWrap: true, padding: EdgeInsets.zero, physics: const NeverScrollableScrollPhysics(), itemCount: displayedItems.length, itemBuilder: (context, index) { final item = displayedItems[index]; final isHovered = hoveredItemIndex == index; return Padding(padding: const EdgeInsets.only(bottom: 8.0), child: MouseRegion(onEnter: (_) => setState(() => hoveredItemIndex = index), onExit: (_) => setState(() => hoveredItemIndex = null), child: InkWell(onTap: item['onTap'] as VoidCallback, borderRadius: BorderRadius.circular(8), child: Padding(padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0), child: Row(children: [Container(width: 5, height: 5, decoration: BoxDecoration(color: isHovered ? widget.color : Colors.blueGrey.shade200, shape: BoxShape.circle)), const SizedBox(width: 10), Expanded(child: Text(item['title'] as String, style: TextStyle(color: isHovered ? widget.color : Colors.blueGrey.shade600, fontSize: 14, fontWeight: isHovered ? FontWeight.bold : FontWeight.w400))), Icon(Icons.chevron_right, size: 14, color: isHovered ? widget.color : Colors.blueGrey.shade300)]))))); }), 
            if (useFixedLayout) const Spacer(), 
            const SizedBox(height: 16), 
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: widget.onTap, style: ElevatedButton.styleFrom(backgroundColor: isCardHovered ? widget.color : const Color(0xFFF1F5F9), foregroundColor: isCardHovered ? Colors.white : Colors.blueGrey.shade700, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold))))
          ]
        )
      )
    ); 
  }
}

class DoodlePainter extends CustomPainter {
  const DoodlePainter();
  @override void paint(Canvas canvas, Size size) {
    const iconSize = 40.0; const spacing = 120.0; final icons = [Icons.school, Icons.book, Icons.edit, Icons.science, Icons.calculate, Icons.public, Icons.history_edu, Icons.psychology, Icons.menu_book, Icons.biotech, Icons.brush, Icons.music_note]; final random = math.Random(42); 
    for (double x = 0; x < size.width + spacing; x += spacing) { for (double y = 0; y < size.height + spacing; y += spacing) { final iconData = icons[random.nextInt(icons.length)]; final jitterX = random.nextDouble() * 40 - 20; final jitterY = random.nextDouble() * 40 - 20; final rotation = random.nextDouble() * 0.5 - 0.25; final textPainter = TextPainter(textDirection: TextDirection.ltr, text: TextSpan(text: String.fromCharCode(iconData.codePoint), style: TextStyle(fontSize: iconSize, fontFamily: iconData.fontFamily, package: iconData.fontPackage, color: Colors.indigo.withOpacity(0.02 + random.nextDouble() * 0.03)))); textPainter.layout(); canvas.save(); canvas.translate(x + jitterX, y + jitterY); canvas.rotate(rotation); textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2)); canvas.restore(); } }
  }
  @override bool shouldRepaint(CustomPainter oldDelegate) => false;
}
