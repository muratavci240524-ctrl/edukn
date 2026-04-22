import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
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
import '../../../../widgets/recipient_selector_field.dart';
import '../../../../widgets/edukn_logo.dart';

import 'chat/chat_screen.dart';
import '../hr/school_type_leave_management_screen.dart';
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
import '../guidance/demand/demand_dashboard_screen.dart';
import '../notes/personal_notes_screen.dart';

class SchoolTypeDetailScreen extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const SchoolTypeDetailScreen({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<SchoolTypeDetailScreen> createState() => _SchoolTypeDetailScreenState();
}

class _SchoolTypeDetailScreenState extends State<SchoolTypeDetailScreen> {
  int _currentIndex = 0;

  // Alt menü sayfaları
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    // Default to Dashboard (index 1) or Haberleşme (index 0). We will default to 1 (Dashboard).
    _currentIndex = 1;
    _pages = [
      _CommunicationTab(
        schoolTypeId: widget.schoolTypeId,
        schoolTypeName: widget.schoolTypeName,
        institutionId: widget.institutionId,
      ),
      _DashboardTab(
        schoolTypeId: widget.schoolTypeId,
        schoolTypeName: widget.schoolTypeName,
        institutionId: widget.institutionId,
      ),
      _OperationsTab(
        schoolTypeId: widget.schoolTypeId,
        schoolTypeName: widget.schoolTypeName,
        institutionId: widget.institutionId,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StylishBottomNav(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
          ),
          Container(
            color: Colors.white,
            width: double.infinity,
            padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 2), // Sadece üst ve alt ince boşluk
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '© 2026 eduKN.',
                  style: TextStyle(
                    color: Colors.blueGrey.shade400,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildFooterLink('Destek'),
                    const SizedBox(width: 16),
                    _buildFooterLink('Gizlilik'),
                    const SizedBox(width: 16),
                    _buildFooterLink('Şartlar'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterLink(String label) {
    return InkWell(
      onTap: () {},
      child: Text(
        label,
        style: TextStyle(
          color: Colors.blueGrey.shade400,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ============== HABERLEŞME TAB ==============
class _CommunicationTab extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const _CommunicationTab({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<_CommunicationTab> createState() => _CommunicationTabState();
}

class _CommunicationTabState extends State<_CommunicationTab> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.blue.shade50, Colors.indigo.shade50],
              ),
            ),
          ),
          
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Haberleşme',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Colors.indigo.shade900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Okulunuzdaki iletişim kanallarına tek bir yerden ulaşın.',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.blueGrey.shade600,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Cards
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _buildCommCard(
                        context: context,
                        index: 0,
                        title: 'Duyurular',
                        description: 'Okul ve kurum içi güncel duyuruları takip edin.',
                        icon: Icons.campaign_rounded,
                        color: Colors.orange,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SchoolTypeAnnouncementsScreen(
                            schoolTypeId: widget.schoolTypeId,
                            schoolTypeName: widget.schoolTypeName,
                            institutionId: widget.institutionId,
                        ))),
                      ),
                      const SizedBox(height: 20),
                      _buildCommCard(
                        context: context,
                        index: 1,
                        title: 'Sosyal Medya',
                        description: 'Okulun sosyal medya paylaşımlarını inceleyin.',
                        icon: Icons.share_rounded,
                        color: Colors.blue,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SchoolTypeSocialMediaScreen(
                            schoolTypeId: widget.schoolTypeId,
                            schoolTypeName: widget.schoolTypeName,
                            institutionId: widget.institutionId,
                        ))),
                      ),
                      const SizedBox(height: 20),
                      _buildCommCard(
                        context: context,
                        index: 2,
                        title: 'Mesajlar',
                        description: 'Öğrenciler, veliler ve personelle mesajlaşın.',
                        icon: Icons.forum_rounded,
                        color: Colors.green,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
                            schoolTypeId: widget.schoolTypeId,
                            schoolTypeName: widget.schoolTypeName,
                            institutionId: widget.institutionId,
                        ))),
                      ),
                      const SizedBox(height: 100), // padding for bottom nav
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommCard({
    required BuildContext context,
    required int index,
    required String title,
    required String description,
    required IconData icon,
    required MaterialColor color,
    required VoidCallback onTap,
  }) {
    final animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Interval(0.1 * index, 1.0, curve: Curves.easeOutBack),
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, 50 * (1 - animation.value)),
          child: Opacity(
            opacity: animation.value,
            child: child,
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: color.shade100.withOpacity(0.5),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            splashColor: color.shade50.withOpacity(0.5),
            highlightColor: color.shade50.withOpacity(0.5),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: color.shade50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(icon, size: 32, color: color.shade700),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo.shade900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blueGrey.shade600,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded, size: 18, color: Colors.indigo.shade200),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============== İŞLEMLER TAB ==============
class _OperationsTab extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const _OperationsTab({
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
  });

  @override
  State<_OperationsTab> createState() => _OperationsTabState();
}

class _OperationsTabState extends State<_OperationsTab> {

  // Seçili kategoriyi takip et (Üst bar için)
  String _selectedCategory = 'Tümü';

  // Dönem bilgileri
  List<Map<String, dynamic>> _terms = [];
  Map<String, dynamic>? _activeTerm;
  Map<String, dynamic>? _selectedTerm;

  @override
  void initState() {
    super.initState();
    _loadTerms();
  }

  Future<void> _loadTerms() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final email = user.email;
      if (email == null) return; // Add null check for email

      final institutionId = email.split('@')[1].split('.')[0].toUpperCase();

      final snapshot = await FirebaseFirestore.instance
          .collection('terms')
          .where('institutionId', isEqualTo: institutionId)
          .get();

      final termsList = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      // Sırala
      termsList.sort((a, b) {
        final aYear = a['startYear'] ?? 0;
        final bYear = b['startYear'] ?? 0;
        return bYear.compareTo(aYear);
      });

      // Aktif dönemi bul
      final active = termsList.firstWhere(
        (t) => t['isActive'] == true,
        orElse: () => termsList.isNotEmpty ? termsList.first : {},
      );

      // SharedPreferences'tan seçili dönemi oku
      final prefs = await SharedPreferences.getInstance();
      final savedTermId = prefs.getString('selected_term_id');

      Map<String, dynamic>? selectedTerm;
      if (savedTermId != null) {
        selectedTerm = termsList.firstWhere(
          (t) => t['id'] == savedTermId,
          orElse: () => {},
        );
        if (selectedTerm.isEmpty) selectedTerm = null;
      }

      if (mounted) {
        setState(() {
          _terms = termsList;
          _activeTerm = active.isNotEmpty ? active : null;
          _selectedTerm = selectedTerm ?? _activeTerm;
        });
      }
    } catch (e) {
      print('Dönemler yüklenirken hata: $e');
    }
  }

  void _showTermSelector() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Dönem Seç',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            if (_terms.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: Text('Henüz dönem tanımlanmamış')),
              )
            else
              ...(_terms.map((term) {
                final isActive = term['isActive'] == true;
                final isSelected = _selectedTerm?['id'] == term['id'];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isActive
                        ? Colors.green[100]
                        : Colors.grey[100],
                    child: Icon(
                      isActive ? Icons.check_circle : Icons.calendar_today,
                      color: isActive ? Colors.green : Colors.grey,
                    ),
                  ),
                  title: Text(
                    '${term['startYear']}-${term['endYear']}',
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  subtitle: isActive
                      ? const Text(
                          'Aktif Dönem',
                          style: TextStyle(color: Colors.green),
                        )
                      : null,
                  trailing: isSelected
                      ? const Icon(
                          Icons.radio_button_checked,
                          color: Colors.blue,
                        )
                      : const Icon(Icons.radio_button_off),
                  onTap: () async {
                    // TermService üzerinden dönem değişikliğini yap (cache'i de günceller)
                    final isActive = term['isActive'] == true;

                    if (isActive) {
                      // Aktif döneme dönüyorsa, seçili dönemi temizle
                      await TermService().clearSelectedTerm();
                    } else {
                      // Geçmiş döneme geçiyorsa, kaydet
                      await TermService().setSelectedTerm(
                        term['id'],
                        term['name'],
                      );
                    }

                    setState(() => _selectedTerm = term);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isActive
                              ? '✓ Aktif döneme geri dönüldü'
                              : '✓ ${term['startYear']}-${term['endYear']} dönemine geçildi',
                        ),
                        backgroundColor: isActive ? Colors.blue : Colors.green,
                        duration: const Duration(seconds: 2),
                      ),
                    );
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
    final bool isMobile = MediaQuery.of(context).size.width < 1100;
    String currentTermName = _selectedTerm != null ? (_selectedTerm!['termName'] ?? '${_selectedTerm!['startYear']}-${_selectedTerm!['endYear']}') : (_activeTerm != null ? (_activeTerm!['termName'] ?? 'Aktif Dönem') : 'Dönem Seçin');

    return Column(
      children: [
        // Clean Header (AppBar Style)
        Container(
          height: kToolbarHeight + MediaQuery.of(context).padding.top,
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            border: Border(bottom: BorderSide(color: Colors.indigo.withOpacity(0.05))),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.indigo),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),
                // Logo on left (Premium branding)
                const EduKnLogo(iconSize: 28, type: EduKnLogoType.iconOnly),
                const SizedBox(width: 8),
                if (!isMobile) ...[
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
                  Container(width: 1, height: 24, color: Colors.indigo.withOpacity(0.1)),
                  const SizedBox(width: 16),
                ] else ...[
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.schoolTypeName,
                        style: TextStyle(
                          color: Colors.indigo.shade900,
                          fontSize: isMobile ? 15 : 16,
                          fontWeight: FontWeight.w900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'İşlemler Merkezi',
                        style: TextStyle(
                          color: Colors.indigo.shade400,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isMobile)
                  PopupMenuButton<int>(
                    icon: Icon(Icons.more_vert, color: Colors.indigo.shade900),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 1,
                        child: Row(
                          children: [
                            Icon(
                              _selectedTerm != null && _selectedTerm!['isActive'] != true ? Icons.history : Icons.calendar_today_outlined,
                              size: 18,
                              color: _selectedTerm != null && _selectedTerm!['isActive'] != true ? Colors.orange.shade800 : Colors.indigo,
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(currentTermName, style: TextStyle(color: Colors.indigo.shade900, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis, maxLines: 1)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 2,
                        child: Row(
                          children: [
                            const Icon(Icons.person_outline_rounded, size: 18, color: Colors.indigo),
                            const SizedBox(width: 12),
                            Text('Profil', style: TextStyle(color: Colors.indigo.shade900, fontWeight: FontWeight.w600, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      if (value == 1) {
                        _showTermSelector();
                      } else if (value == 2) {
                        Navigator.push(context, MaterialPageRoute(builder: (ctx) => const UserProfileScreen()));
                      }
                    },
                  )
                else ...[
                  // Term Selector
                  InkWell(
                    onTap: _showTermSelector,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _selectedTerm != null && _selectedTerm!['isActive'] != true ? Colors.orange.shade50 : Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _selectedTerm != null && _selectedTerm!['isActive'] != true ? Colors.orange.shade200 : Colors.indigo.shade100),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _selectedTerm != null && _selectedTerm!['isActive'] != true ? Icons.history : Icons.calendar_today_outlined,
                            size: 14,
                            color: _selectedTerm != null && _selectedTerm!['isActive'] != true ? Colors.orange.shade800 : Colors.indigo,
                          ),
                          const SizedBox(width: 8),
                          Text(currentTermName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.indigo),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.indigo.shade50, shape: BoxShape.circle),
                      child: const Icon(Icons.person_outline_rounded, size: 20, color: Colors.indigo),
                    ),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (ctx) => const UserProfileScreen())),
                  ),
                ],
              ],
            ),
          ),
        ),
        // Main Content
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      _buildCategorySelector(isMobile),
                      Center(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 1400),
                          padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildGridSections(isMobile),
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGridSections(bool isMobile) {
    final bool isFiltered = _selectedCategory != 'Tümü';
    final double cardPadding = isMobile ? 16 : 24;
    final double screenWidth = MediaQuery.of(context).size.width;
    const double maxLayoutWidth = 1400.0;
    final double constrainedWidth = screenWidth > maxLayoutWidth ? maxLayoutWidth : screenWidth;
    final double availableWidth = constrainedWidth - (cardPadding * 2);

    double gridCardWidth;
    if (availableWidth > 1000) {
      gridCardWidth = (availableWidth - 48) / 3;
    } else if (availableWidth > 700) {
      gridCardWidth = (availableWidth - 24) / 2;
    } else {
      gridCardWidth = availableWidth;
    }

    final double currentCardWidth = isFiltered ? availableWidth : gridCardWidth;

    final allModules = [
      _ModuleCardWidget(
        key: const ValueKey('kayit'),
        title: 'ÖĞRENCİ VE PERSONEL',
        badge: 'Kayıt',
        icon: Icons.people_outline,
        color: Colors.blue,
        cardWidth: currentCardWidth,
        isMobile: isMobile,
        category: 'Kayıt',
        showAllItems: isFiltered,
        items: [
          {'title': 'Öğrenci Listesi', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => StudentRegistrationScreen(fixedSchoolTypeId: widget.schoolTypeId, fixedSchoolTypeName: widget.schoolTypeName, fixedInstitutionId: widget.institutionId)))},
          {'title': 'Personel Listesi', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => StaffListScreen(fixedSchoolTypeId: widget.schoolTypeId, fixedSchoolTypeName: widget.schoolTypeName)))},
          {'title': 'Şube Listesi', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => ClassManagementScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)))},
          {'title': 'Ders Listesi', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => LessonManagementScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)))},
          {'title': 'Derslik Listesi', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => ClassroomManagementScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)))},
          {'title': 'Kitap Listesi', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => BookManagementScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)))},
        ],
        onTap: () => setState(() => _selectedCategory = 'Kayıt'),
      ),
      _ModuleCardWidget(
        key: const ValueKey('egitim'),
        title: 'EĞİTİM İŞLEMLERİ',
        badge: 'Eğitim',
        icon: Icons.school,
        color: Colors.green,
        cardWidth: currentCardWidth,
        isMobile: isMobile,
        category: 'Eğitim',
        showAllItems: isFiltered,
        items: [
          {'title': 'Çalışma Takvimi', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => WorkCalendarScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)))},
          {'title': 'Ders Saatleri', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => LessonHoursScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)))},
          {'title': 'Ders Programı', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => ClassScheduleScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)))},
          {'title': 'Şube Ders Programı', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => ClassScheduleViewScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)))},
          {'title': 'Öğretmen Ders Programı', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => TeacherScheduleViewScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)))},
          {'title': 'Anket İşlemleri', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => SurveyListScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)))},
          {'title': 'Etüt İşlemleri', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => EtutProcessScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)))},
        ],
        onTap: () => setState(() => _selectedCategory = 'Eğitim'),
      ),
      _ModuleCardWidget(
        key: const ValueKey('rehberlik'),
        title: 'REHBERLİK İŞLEMLERİ',
        badge: 'Rehberlik',
        icon: Icons.folder_special,
        color: Colors.purple,
        cardWidth: currentCardWidth,
        isMobile: isMobile,
        category: 'Rehberlik',
        showAllItems: isFiltered,
        items: [
          {'title': 'Portfolyo', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => PortfolioScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)))},
          {'title': 'Talepler (Yönlendirmeler)', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => DemandDashboardScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId)))},
          {'title': 'Görüşmeler', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => GuidanceInterviewScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)))},
          {'title': 'Gözlem ve Etkinlikler', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => ActivityListScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)))},
          {'title': 'Çalışma Programı', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => GuidanceStudyProgramScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId)))},
          {'title': 'Envanterler', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => GuidanceTestCatalogScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId)))},
          {'title': '360 Gelişim Raporları', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => DevelopmentReportManagementScreen(institutionId: widget.institutionId)))},
        ],
        onTap: () => setState(() => _selectedCategory = 'Rehberlik'),
      ),
      _ModuleCardWidget(
        key: const ValueKey('olcme'),
        title: 'ÖLÇME DEĞERLENDİRME',
        badge: 'Sınav',
        icon: Icons.analytics,
        color: Colors.orange,
        cardWidth: currentCardWidth,
        isMobile: isMobile,
        category: 'Ölçme',
        showAllItems: isFiltered,
        items: [
          {'title': 'Raporlar', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => AssessmentReportsScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId)))},
          {'title': 'Denemeler', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => TrialExamListScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId)))},
          {'title': 'Sınavlar', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => ActiveExamListScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId)))},
          {'title': 'Tanımlar', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => AssessmentDefinitionsScreen(institutionId: widget.institutionId)))},
        ],
        onTap: () => setState(() => _selectedCategory = 'Ölçme'),
      ),
      _ModuleCardWidget(
        key: const ValueKey('gorev'),
        title: 'GÖREVLENDİRME VE İZİN',
        badge: 'Görev',
        icon: Icons.assignment_ind,
        color: Colors.teal,
        cardWidth: currentCardWidth,
        isMobile: isMobile,
        category: 'Görev',
        showAllItems: isFiltered,
        items: [
          {'title': 'To do List', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => ToDoListScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId)))},
          {'title': 'İzin Yönetimi', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => SchoolTypeLeaveManagementScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId)))},
          {'title': 'Geçici Öğretmen', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => SubstituteTeacherListScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)))},
          {'title': 'Nöbet İşlemleri', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => DutyManagementScreen(institutionId: widget.institutionId)))},
          {'title': 'Gezi Görevlendirmeleri', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => FieldTripListScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)))},
          {'title': 'Proje Görevlendirmeleri', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProjectAssignmentListScreen(institutionId: widget.institutionId)))},
        ],
        onTap: () => setState(() => _selectedCategory = 'Görev'),
      ),
      _ModuleCardWidget(
        key: const ValueKey('destek'),
        title: 'DESTEK HİZMETLERİ',
        badge: 'Destek',
        icon: Icons.support_agent,
        color: Colors.cyan,
        cardWidth: currentCardWidth,
        isMobile: isMobile,
        category: 'Destek',
        showAllItems: isFiltered,
        items: [
          {'title': 'Yemekhane İşlemleri', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => CafeteriaScreen(fixedSchoolTypeId: widget.schoolTypeId, fixedSchoolTypeName: widget.schoolTypeName)))},
          {'title': 'Servis İşlemleri', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => TransportationScreen(fixedSchoolTypeId: widget.schoolTypeId, fixedSchoolTypeName: widget.schoolTypeName)))},
          {'title': 'Sağlık İşlemleri', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => HealthScreen(fixedSchoolTypeId: widget.schoolTypeId, fixedSchoolTypeName: widget.schoolTypeName)))},
          {'title': 'Kütüphane İşlemleri', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => LibraryScreen(fixedSchoolTypeId: widget.schoolTypeId, fixedSchoolTypeName: widget.schoolTypeName)))},
          {'title': 'Temizlik İşlemleri', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => CleaningScreen(fixedSchoolTypeId: widget.schoolTypeId, fixedSchoolTypeName: widget.schoolTypeName)))},
          {'title': 'Depo ve Satın Alma', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => InventoryScreen(fixedSchoolTypeId: widget.schoolTypeId, fixedSchoolTypeName: widget.schoolTypeName)))},
        ],
        onTap: () => setState(() => _selectedCategory = 'Destek'),
      ),
      _ModuleCardWidget(
        key: const ValueKey('raporlar'),
        title: 'RAPORLAR İŞLEMLERİ',
        badge: 'Rapor',
        icon: Icons.analytics_outlined,
        color: Colors.indigo,
        cardWidth: currentCardWidth,
        isMobile: isMobile,
        category: 'Raporlar',
        showAllItems: isFiltered,
        items: [
          {'title': 'Yoklama Raporları', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => AttendanceOperationsScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)))},
          {'title': 'Ödev Raporları', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => HomeworkOperationsScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId)))},
          {'title': 'Ölçme Raporları', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => AssessmentReportsScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId)))},
        ],
        onTap: () => setState(() => _selectedCategory = 'Raporlar'),
      ),
      _ModuleCardWidget(
        key: const ValueKey('ayarlar'),
        title: 'SİSTEM AYARLARI',
        badge: 'Ayarlar',
        icon: Icons.settings,
        color: Colors.blueGrey,
        cardWidth: currentCardWidth,
        isMobile: isMobile,
        category: 'Ayarlar',
        showAllItems: isFiltered,
        items: [
          {'title': 'Yetki Tanımlama', 'onTap': () => Navigator.pushNamed(context, '/permission-definition')},
          {'title': 'Kullanıcı Yetkilendirme', 'onTap': () => Navigator.pushNamed(context, '/user-management')},
          {'title': 'Uygulama Ayarları', 'onTap': () => Navigator.pushNamed(context, '/app-settings')},
        ],
        onTap: () => setState(() => _selectedCategory = 'Ayarlar'),
      ),
      _ModuleCardWidget(
        key: const ValueKey('kisisel'),
        title: 'KİŞİSEL İŞLEMLER',
        badge: 'Kişisel',
        icon: Icons.person,
        color: Colors.pink,
        cardWidth: currentCardWidth,
        isMobile: isMobile,
        category: 'Kişisel',
        showAllItems: isFiltered,
        items: [
          {'title': 'Notlarım', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PersonalNotesScreen()))},
        ],
        onTap: () => setState(() => _selectedCategory = 'Kişisel'),
      ),
    ];

    final filteredModules = isFiltered ? allModules.where((m) => m.category == _selectedCategory).toList() : allModules;

    return Wrap(
      key: const ValueKey('stable_modules_grid'),
      spacing: 24,
      runSpacing: 24,
      children: filteredModules,
    );
  }

  Widget _buildCategorySelector(bool isMobile) {
    final categories = [
      {'label': 'Tümü', 'icon': Icons.grid_view_rounded},
      {'label': 'Kayıt', 'icon': Icons.app_registration},
      {'label': 'Eğitim', 'icon': Icons.school},
      {'label': 'Rehberlik', 'icon': Icons.folder_special},
      {'label': 'Ölçme', 'icon': Icons.bar_chart},
      {'label': 'Görev', 'icon': Icons.assignment_ind},
      {'label': 'Destek', 'icon': Icons.support_agent},
      {'label': 'Raporlar', 'icon': Icons.analytics_outlined},
      {'label': 'Ayarlar', 'icon': Icons.settings},
      {'label': 'Kişisel', 'icon': Icons.person},
    ];

    final screenWidth = MediaQuery.of(context).size.width;
    const double maxLayoutWidth = 1400.0;
    final double contentWidth = screenWidth > maxLayoutWidth ? maxLayoutWidth : screenWidth;
    final double availableWidth = contentWidth - (isMobile ? 32 : 48);

    return Container(
      width: double.infinity,
      height: 100,
      color: Colors.white.withOpacity(0.5),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            constraints: BoxConstraints(minWidth: availableWidth.isNegative ? 0.0 : availableWidth),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: categories.map((cat) {
                final isSelected = _selectedCategory == cat['label'];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: InkWell(
                    onTap: () => setState(() => _selectedCategory = cat['label'] as String),
                    borderRadius: BorderRadius.circular(16),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      width: isMobile ? 75 : 80,
                      height: isMobile ? 75 : 80,
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF3F51B5) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isSelected ? 0.2 : 0.03),
                            blurRadius: isSelected ? 12 : 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: isSelected ? Colors.indigo : Colors.indigo.withOpacity(0.05),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            cat['icon'] as IconData,
                            color: isSelected ? Colors.white : Colors.indigo.shade400,
                            size: isMobile ? 20 : 24,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            cat['label'] as String,
                            style: TextStyle(
                              fontSize: isMobile ? 9 : 10,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected ? Colors.white : Colors.blueGrey.shade600,
                              letterSpacing: -0.2,
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

}

// ============== DASHBOARD TAB ==============
class _DashboardTab extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const _DashboardTab({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isWideScreen = constraints.maxWidth > 900;

        if (isWideScreen) {
          return Row(
            children: [
              // Sol Panel: Bildirimler
              Expanded(
                flex: 2,
                child: SharedNotificationSection(
                  schoolTypeId: widget.schoolTypeId,
                  institutionId: widget.institutionId,
                ),
              ),
              // Sağ Panel: Takvim
              Expanded(
                flex: 3,
                child: SharedCalendarSection(
                  schoolTypeId: widget.schoolTypeId,
                  institutionId: widget.institutionId,
                ),
              ),
            ],
          );
        } else {
          return DefaultTabController(
            length: 2,
            child: Column(
              children: [
                Container(
                  color: Colors.white,
                  child: TabBar(
                    labelColor: Colors.blue.shade700,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: Colors.blue.shade700,
                    indicatorSize: TabBarIndicatorSize.label,
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.notifications_none_rounded, size: 20),
                            SizedBox(width: 8),
                            Text('Bildirimler'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.calendar_today_rounded, size: 18),
                            SizedBox(width: 8),
                            Text('Takvim'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      SharedNotificationSection(
                        schoolTypeId: widget.schoolTypeId,
                        institutionId: widget.institutionId,
                      ),
                      SharedCalendarSection(
                        schoolTypeId: widget.schoolTypeId,
                        institutionId: widget.institutionId,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
      },
    );
  }
}

class SharedNotificationSection extends StatelessWidget {
  final String schoolTypeId;
  final String institutionId;

  const SharedNotificationSection({
    required this.schoolTypeId,
    required this.institutionId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'BİLDİRİMLER',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                    letterSpacing: 1.2,
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: Text('Tümünü Oku'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blue,
                    textStyle: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: 5,
              itemBuilder: (context, index) {
                return _buildNotificationCard(
                  title: index == 0
                      ? 'Yeni Duyuru: Veli Toplantısı'
                      : 'Ölçme Değerlendirme Raporu Hazır',
                  subtitle: index == 0
                      ? '12 Mart Perşembe günü saat 15:00\'de online veli toplantısı yapılacaktır.'
                      : 'Son deneme sınavı sonuçları sisteme yüklenmiştir.',
                  time: '${index + 1} saat önce',
                  type: index % 2 == 0 ? 'announcement' : 'report',
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard({
    required String title,
    required String subtitle,
    required String time,
    required String type,
  }) {
    IconData icon;
    Color color;

    if (type == 'announcement') {
      icon = Icons.campaign_rounded;
      color = Colors.blue;
    } else {
      icon = Icons.analytics_rounded;
      color = Colors.orange;
    }

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            spreadRadius: 2,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 6, color: color),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: color, size: 20),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  time,
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SharedCalendarSection extends StatefulWidget {
  final String schoolTypeId;
  final String institutionId;

  const SharedCalendarSection({
    required this.schoolTypeId,
    required this.institutionId,
  });

  @override
  State<SharedCalendarSection> createState() => _SharedCalendarSectionState();
}

class _SharedCalendarSectionState extends State<SharedCalendarSection> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  List<Map<String, dynamic>> _events = [];
  bool _isLoading = false;
  bool _isWeeklyView = false;

  final List<String> _daysOfWeek = ['Pt', 'Sa', 'Çr', 'Pr', 'Cu', 'Ct', 'Pz'];
  final List<String> _months = [
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    try {
      final startOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1);
      final endOfMonth = DateTime(
        _focusedDay.year,
        _focusedDay.month + 1,
        0,
        23,
        59,
        59,
      );

      // 1. Sosyal Etkinlikler ve Özel Notlar (activities)
      final activitiesSnapshot = await FirebaseFirestore.instance
          .collection('activities')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      // 2. Etütler (etut_requests)
      final etutSnapshot = await FirebaseFirestore.instance
          .collection('etut_requests')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      // 3. Geziler (field_trips)
      final geziSnapshot = await FirebaseFirestore.instance
          .collection('field_trips')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      List<Map<String, dynamic>> allEvents = [];

      // Mapper: Activities
      allEvents.addAll(
        activitiesSnapshot.docs
            .map(
              (doc) => {
                ...doc.data(),
                'id': doc.id,
                'source': 'activity',
                'displayType': doc.data()['type'] ?? 'Etkinlik',
              },
            )
            .where((data) {
              final sId = data['schoolTypeId'] as String?;
              if (widget.schoolTypeId.isNotEmpty && sId != widget.schoolTypeId) return false;
              final dateTs = data['date'] as Timestamp?;
              if (dateTs == null) return false;
              final date = dateTs.toDate();
              return date.isAfter(
                    startOfMonth.subtract(Duration(seconds: 1)),
                  ) &&
                  date.isBefore(endOfMonth.add(Duration(seconds: 1)));
            }),
      );

      // Mapper: Etütler
      allEvents.addAll(
        etutSnapshot.docs
            .map(
              (doc) => {
                ...doc.data(),
                'id': doc.id,
                'source': 'etut',
                'title': doc.data()['topic'] ?? 'Etüt',
                'displayType': 'Etüt',
                'date': doc.data()['startTime'], // Indicator için date alanı
                'type': 'Etüt',
              },
            )
            .where((data) {
              final sId = data['schoolTypeId'] as String?;
              if (widget.schoolTypeId.isNotEmpty && sId != widget.schoolTypeId) return false;
              final dateTs = data['startTime'] as Timestamp?;
              if (dateTs == null) return false;
              final date = dateTs.toDate();
              return date.isAfter(
                    startOfMonth.subtract(Duration(seconds: 1)),
                  ) &&
                  date.isBefore(endOfMonth.add(Duration(seconds: 1)));
            }),
      );

      // Mapper: Geziler
      allEvents.addAll(
        geziSnapshot.docs
            .map(
              (doc) => {
                ...doc.data(),
                'id': doc.id,
                'source': 'gezi',
                'title': doc.data()['name'] ?? 'Gezi',
                'displayType': 'Gezi',
                'date': doc.data()['departureTime'],
                'type': 'Gezi',
              },
            )
            .where((data) {
              final sId = data['schoolTypeId'] as String?;
              if (widget.schoolTypeId.isNotEmpty && sId != widget.schoolTypeId) return false;
              final dateTs = data['departureTime'] as Timestamp?;
              if (dateTs == null) return false;
              final date = dateTs.toDate();
              return date.isAfter(
                    startOfMonth.subtract(Duration(seconds: 1)),
                  ) &&
                  date.isBefore(endOfMonth.add(Duration(seconds: 1)));
            }),
      );

      setState(() {
        _events = allEvents;
        _isLoading = false;
      });
    } catch (e) {
      print('Etkinlik yükleme hatası: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isWideScreen = MediaQuery.of(context).size.width > 900;

    return Stack(
      children: [
        Container(
          margin: EdgeInsets.all(isWideScreen ? 24 : 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: isWideScreen
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      spreadRadius: 5,
                      blurRadius: 20,
                      offset: Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              // Takvim Başlığı
              Padding(
                padding: EdgeInsets.fromLTRB(isWideScreen ? 24 : 16, 24, isWideScreen ? 24 : 8, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${_months[_focusedDay.month - 1]} ${_focusedDay.year}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade900,
                              ),
                            ),
                          ),
                          if (_isLoading)
                            Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: SizedBox(
                                width: 60,
                                height: 2,
                                child: LinearProgressIndicator(
                                  backgroundColor: Colors.blue.withOpacity(0.1),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.blue,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _focusedDay = DateTime.now();
                          _selectedDay = DateTime.now();
                        });
                        _loadEvents();
                      },
                      child: Text('Bugün'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.blue,
                        padding: EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          if (_isWeeklyView) {
                            _selectedDay = _selectedDay.subtract(Duration(days: 7));
                            _focusedDay = _selectedDay;
                          } else {
                            _focusedDay = DateTime(
                              _focusedDay.year,
                              _focusedDay.month - 1,
                            );
                          }
                        });
                        _loadEvents();
                      },
                      icon: Icon(Icons.chevron_left_rounded),
                      splashRadius: 24,
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          if (_isWeeklyView) {
                            _selectedDay = _selectedDay.add(Duration(days: 7));
                            _focusedDay = _selectedDay;
                          } else {
                            _focusedDay = DateTime(
                              _focusedDay.year,
                              _focusedDay.month + 1,
                            );
                          }
                        });
                        _loadEvents();
                      },
                      icon: Icon(Icons.chevron_right_rounded),
                      splashRadius: 24,
                    ),
                  ],
                ),
              ),
              // Gün İsimleri
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: _daysOfWeek
                      .map(
                        (day) => Expanded(
                          child: Center(
                            child: Text(
                              day,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey.shade300,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              SizedBox(height: 8),
              // Günler Grid
              if (_isWeeklyView)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _buildCalendarGrid(),
                )
              else
                Flexible(
                  flex: 5,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    child: _buildCalendarGrid(),
                  ),
                ),
              // Seçili Gün Etkinlikleri
              Expanded(
                flex: 6,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                  ),
                  child: _buildEventList(),
                ),
              ),
            ],
          ),
        ),
        // Ekleme FAB (Google Calendar Style)
        Positioned(
          right: isWideScreen ? 48 : 32,
          bottom: isWideScreen ? 48 : 32,
          child: FloatingActionButton(
            onPressed: () => _showAddEventDialog(),
            backgroundColor: Colors.blue,
            child: Icon(Icons.add_rounded, color: Colors.white, size: 30),
            elevation: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarGrid() {
    bool isWideScreen = MediaQuery.of(context).size.width > 900;
    final firstDayOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final daysInMonth = DateTime(
      _focusedDay.year,
      _focusedDay.month + 1,
      0,
    ).day;
    int firstDayWeekday = firstDayOfMonth.weekday - 1;
    final totalCells = _isWeeklyView ? 7 : 42;

    return GridView.builder(
      shrinkWrap: true,
      physics: BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: _isWeeklyView ? (isWideScreen ? 1.5 : 1.2) : (isWideScreen ? 2.3 : 1.6), // Tasarım odaklı yassı oran. Günler arasındaki dikey boşluk problemini çözer.
      ),
      itemCount: totalCells,
      itemBuilder: (context, index) {
        DateTime currentDay;
        
        if (_isWeeklyView) {
          // Hafta görünümündeyse
          DateTime startOfWeek = _selectedDay.subtract(Duration(days: _selectedDay.weekday - 1));
          currentDay = startOfWeek.add(Duration(days: index));
        } else {
          // Ay görünümündeyse
          int dayNum = index - firstDayWeekday + 1;
          bool isCurrentMonth = dayNum > 0 && dayNum <= daysInMonth;
          if (!isCurrentMonth) return SizedBox.shrink();

          currentDay = DateTime(
            _focusedDay.year,
            _focusedDay.month,
            dayNum,
          );
        }

        bool isSelected =
            currentDay.day == _selectedDay.day &&
            currentDay.month == _selectedDay.month &&
            currentDay.year == _selectedDay.year;

        bool isToday =
            currentDay.day == DateTime.now().day &&
            currentDay.month == DateTime.now().month &&
            currentDay.year == DateTime.now().year;

        // Bu gün için etkinlikleri bul
        final dayEvents = _events.where((e) {
          final eventDate = (e['date'] as Timestamp).toDate();
          return eventDate.day == currentDay.day &&
              eventDate.month == currentDay.month &&
              eventDate.year == currentDay.year;
        }).toList();

        return InkWell(
          onTap: () {
            setState(() {
              _selectedDay = currentDay;
              if (!_isWeeklyView && currentDay.month != _focusedDay.month) {
                _focusedDay = currentDay;
                _loadEvents();
              }
            });
          },
          onLongPress: () => _showAddEventDialog(date: currentDay),
          borderRadius: BorderRadius.circular(100),
          splashColor: Colors.blue.withOpacity(0.1),
          highlightColor: Colors.transparent,
          child: Center(
            child: AnimatedContainer(
              duration: Duration(milliseconds: 250),
              curve: Curves.easeOutCirc,
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.blue
                    : (isToday
                          ? Colors.blue.withOpacity(0.05)
                          : Colors.transparent),
                shape: BoxShape.circle,
                border: isToday && !isSelected
                    ? Border.all(color: Colors.blue.withOpacity(0.3), width: 1.5)
                    : null,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.4),
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        )
                      ]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    currentDay.day.toString(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: (isSelected || isToday)
                          ? FontWeight.bold
                          : FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : (isToday
                                ? Colors.blue.shade700
                                : Colors.blueGrey.shade700),
                    ),
                  ),
                  if (dayEvents.isNotEmpty)
                    Container(
                      margin: EdgeInsets.only(top: 1),
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : Colors.blue.shade500,
                        shape: BoxShape.circle,
                        boxShadow: isSelected ? null : [
                          BoxShadow(color: Colors.blue.withOpacity(0.2), blurRadius: 4, spreadRadius: 1)
                        ],
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

  Widget _buildEventList() {
    final selectedDayEvents = _events.where((e) {
      final eventDate = (e['date'] as Timestamp).toDate();
      return eventDate.day == _selectedDay.day &&
          eventDate.month == _selectedDay.month &&
          eventDate.year == _selectedDay.year;
    }).toList();

    selectedDayEvents.sort(
      (a, b) => (a['startTime'] ?? '').compareTo(b['startTime'] ?? ''),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 16, bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_selectedDay.day} ${_months[_selectedDay.month - 1]}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.grey.shade800,
                ),
              ),
              Spacer(),
              IconButton(
                tooltip: _isWeeklyView ? 'Aylık Görünüme Geç' : 'Haftalık Görünüme Geç',
                icon: Icon(
                  _isWeeklyView ? Icons.calendar_month_rounded : Icons.calendar_view_week_rounded,
                  color: Colors.blue.shade600,
                ),
                splashRadius: 24,
                onPressed: () {
                  setState(() {
                    _isWeeklyView = !_isWeeklyView;
                    if (_isWeeklyView) {
                      _focusedDay = _selectedDay;
                    }
                  });
                },
              ),
              Text(
                '${selectedDayEvents.length} Etkinlik',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
        Expanded(
          child: selectedDayEvents.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.event_note_rounded,
                        color: Colors.grey.shade300,
                        size: 40,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Bu gün için etkinlik yok',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.only(bottom: 24),
                  itemCount: selectedDayEvents.length,
                  itemBuilder: (context, index) {
                    final event = selectedDayEvents[index];
                    return Container(
                      margin: EdgeInsets.only(bottom: 12),
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade100),
                      ),
                      child: Row(
                        children: [
                          _buildEventIcon(event),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event['title'] ?? '',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                if (event['startTime'] != null)
                                  Text(
                                    '${event['startTime']} - ${event['endTime'] ?? ''}',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (event['source'] == 'activity')
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                                color: Colors.grey.shade400,
                              ),
                              onPressed: () => _deleteEvent(event['id']),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEventIcon(Map<String, dynamic> event) {
    final source = event['source'] ?? 'activity';
    IconData icon = Icons.circle;
    Color color = Colors.blue;
    double size = 10;

    if (source == 'etut') {
      icon = Icons.book_rounded;
      color = Colors.teal;
      size = 18;
    } else if (source == 'gezi') {
      icon = Icons.map_rounded;
      color = Colors.orange;
      size = 18;
    } else {
      color = _getEventColor(event['type']);
    }

    return Icon(icon, color: color, size: size);
  }

  Color _getEventColor(String? type) {
    switch (type) {
      case 'Önemli':
        return Colors.red;
      case 'Toplantı':
        return Colors.blue;
      case 'Duyuru':
        return Colors.green;
      case 'Etkinlik':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  Future<void> _showAddEventDialog({DateTime? date}) async {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final targetDate = date ?? _selectedDay;

    if (isMobile) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: Text('Yeni Etkinlik'),
              leading: IconButton(
                icon: Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: _AddEventForm(
              initialDate: targetDate,
              schoolTypeId: widget.schoolTypeId,
              onSave: (data) {
                _saveEvent(
                  title: data['title'],
                  type: data['type'],
                  date: data['date'],
                  endDate: data['endDate'],
                  startTime: data['startTime'],
                  endTime: data['endTime'],
                  recipientIds: data['recipientIds'],
                  recipientNames: data['recipientNames'],
                );
                Navigator.pop(context);
              },
            ),
          ),
        ),
      );
    } else {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: EdgeInsets.zero,
          content: Container(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_task_rounded,
                        color: Colors.blue,
                        size: 28,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Yeni Etkinlik',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Spacer(),
                      IconButton(
                        icon: Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    child: _AddEventForm(
                      initialDate: targetDate,
                      schoolTypeId: widget.schoolTypeId,
                      onSave: (data) {
                        _saveEvent(
                          title: data['title'],
                          type: data['type'],
                          date: data['date'],
                          endDate: data['endDate'],
                          startTime: data['startTime'],
                          endTime: data['endTime'],
                          recipientIds: data['recipientIds'],
                          recipientNames: data['recipientNames'],
                        );
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  Future<void> _saveEvent({
    required String title,
    required String type,
    required DateTime date,
    required DateTime endDate,
    required String startTime,
    required String endTime,
    List<String>? recipientIds,
    Map<String, String>? recipientNames,
  }) async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('activities').add({
        'institutionId': widget.institutionId,
        'schoolTypeId': widget.schoolTypeId,
        'title': title,
        'type': type,
        'date': Timestamp.fromDate(date),
        'endDate': Timestamp.fromDate(endDate),
        'startTime': startTime,
        'endTime': endTime,
        'recipientIds': recipientIds ?? [],
        'recipientNames': recipientNames ?? {},
        'createdBy': FirebaseAuth.instance.currentUser?.uid,
        'source': 'activity',
        'createdAt': FieldValue.serverTimestamp(),
      });
      _loadEvents();
    } catch (e) {
      debugPrint('Error saving event: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteEvent(String eventId) async {
    setState(() => _isLoading = true);
    try {
      final eventDoc = await FirebaseFirestore.instance
          .collection('activities')
          .doc(eventId)
          .get();

      if (eventDoc.exists && eventDoc.data()?['source'] == 'activity') {
        await eventDoc.reference.delete();
        _loadEvents();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sadece kendi oluşturduğunuz etkinlikleri silebilirsiniz.',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error deleting event: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Silme hatası: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }
}

class _AddEventForm extends StatefulWidget {
  final DateTime initialDate;
  final String schoolTypeId;
  final Function(Map<String, dynamic>) onSave;

  const _AddEventForm({
    Key? key,
    required this.initialDate,
    required this.schoolTypeId,
    required this.onSave,
  }) : super(key: key);

  @override
  State<_AddEventForm> createState() => _AddEventFormState();
}

class _AddEventFormState extends State<_AddEventForm> {
  final _titleController = TextEditingController();
  String _selectedType = 'Etkinlik';
  late DateTime _startDate;
  late DateTime _endDate;
  TimeOfDay _startTime = TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = TimeOfDay(hour: 10, minute: 0);
  List<String> _selectedRecipients = [];
  Map<String, String> _recipientNames = {};

  @override
  void initState() {
    super.initState();
    _startDate = widget.initialDate;
    _endDate = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: 'Etkinlik Başlığı',
              hintText: 'Örn: Veli Toplantısı',
              prefixIcon: Icon(Icons.title_rounded, color: Colors.blue),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
          SizedBox(height: 20),
          DropdownButtonFormField<String>(
            value: _selectedType,
            decoration: InputDecoration(
              labelText: 'Etkinlik Türü',
              prefixIcon: Icon(Icons.category_rounded, color: Colors.blue),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            items: [
              'Etkinlik',
              'Toplantı',
              'Duyuru',
              'Önemli',
            ].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (val) => setState(() => _selectedType = val!),
          ),
          SizedBox(height: 24),
          Text(
            'Tarih ve Saat',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          SizedBox(height: 16),
          // Start Date & Time
          Row(
            children: [
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _startDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() {
                        _startDate = picked;
                        if (_endDate.isBefore(_startDate))
                          _endDate = _startDate;
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Başlangıç Tarihi',
                      prefixIcon: Icon(Icons.calendar_today_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      DateFormat('d MMM yyyy', 'tr').format(_startDate),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _startTime,
                    );
                    if (picked != null) setState(() => _startTime = picked);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Saat',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(_startTime.format(context)),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          // End Date & Time
          Row(
            children: [
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _endDate,
                      firstDate: _startDate,
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _endDate = picked);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Bitiş Tarihi',
                      prefixIcon: Icon(Icons.calendar_month_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      DateFormat('d MMM yyyy', 'tr').format(_endDate),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _endTime,
                    );
                    if (picked != null) setState(() => _endTime = picked);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Saat',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(_endTime.format(context)),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 24),
          RecipientSelectorField(
            selectedRecipients: _selectedRecipients,
            recipientNames: _recipientNames,
            schoolTypeId: widget.schoolTypeId,
            title: 'Kimler Görecek?',
            hint: 'Boş bırakılırsa sadece siz görürsünüz',
            onChanged: (list, names) {
              setState(() {
                _selectedRecipients = list;
                _recipientNames = names;
              });
            },
          ),
          SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              if (_titleController.text.isNotEmpty) {
                widget.onSave({
                  'title': _titleController.text,
                  'type': _selectedType,
                  'date': _startDate,
                  'endDate': _endDate,
                  'startTime':
                      '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
                  'endTime':
                      '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
                  'recipientIds': _selectedRecipients,
                  'recipientNames': _recipientNames,
                });
              }
            },
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              elevation: 4,
            ),
            child: Text(
              'Kaydet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
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
    required this.category,
    this.showAllItems = false,
  }) : super(key: key);
  @override
  State<_ModuleCardWidget> createState() => _ModuleCardWidgetState();
}

class _ModuleCardWidgetState extends State<_ModuleCardWidget> {
  bool isCardHovered = false;
  int? hoveredItemIndex;
  @override
  Widget build(BuildContext context) {
    final displayedItems =
        widget.showAllItems ? widget.items : widget.items.take(3).toList();
    final remainingCount = widget.items.length - displayedItems.length;
    final String label = remainingCount > 0
        ? '+$remainingCount işlem daha görüntüle'
        : ('GÖRÜNTÜLE');
    return MouseRegion(
      onEnter: (_) => setState(() => isCardHovered = true),
      onExit: (_) => setState(() => isCardHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: widget.cardWidth,
        constraints: BoxConstraints(
          minHeight: (widget.isMobile || widget.showAllItems) ? 0 : 380,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(
                  isCardHovered || widget.showAllItems ? 0.08 : 0.03),
              blurRadius: isCardHovered || widget.showAllItems ? 30 : 20,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(
            color: isCardHovered || widget.showAllItems
                ? widget.color.withOpacity(0.3)
                : Colors.indigo.withOpacity(0.05),
            width: 1.5,
          ),
        ),
        alignment: Alignment.center, // İçeriği merkeze hizala (Dikey ortalama isteği için)
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                                color: isHovered
                                    ? widget.color
                                    : Colors.blueGrey.shade200,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item['title'] as String,
                                style: TextStyle(
                                  color: isHovered
                                      ? widget.color
                                      : Colors.blueGrey.shade600,
                                  fontSize: 14,
                                  fontWeight: isHovered
                                      ? FontWeight.w900
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                              color: isHovered
                                  ? widget.color
                                  : Colors.blueGrey.shade300,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16), // Boşluğu biraz artırdık
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isCardHovered
                      ? widget.color
                      : const Color(0xFFF1F5F9),
                  foregroundColor:
                      isCardHovered ? Colors.white : Colors.blueGrey.shade700,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12), // 18 -> 12 düşürüldü
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
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

class DoodlePainter extends CustomPainter {
  const DoodlePainter();
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    
    const iconSize = 40.0;
    const spacing = 120.0;
    final icons = [
      Icons.school,
      Icons.book,
      Icons.edit,
      Icons.science,
      Icons.calculate,
      Icons.public,
      Icons.history_edu,
      Icons.psychology,
      Icons.menu_book,
      Icons.biotech,
      Icons.brush,
      Icons.music_note
    ];
    final random = math.Random(42);
    for (double x = 0; x < size.width + spacing; x += spacing) {
      for (double y = 0; y < size.height + spacing; y += spacing) {
        final iconData = icons[random.nextInt(icons.length)];
        final jitterX = random.nextDouble() * 40 - 20;
        final jitterY = random.nextDouble() * 40 - 20;
        final rotation = random.nextDouble() * 0.5 - 0.25;
        
        final textPainter = TextPainter(
            textDirection: ui.TextDirection.ltr,
            text: TextSpan(
                text: String.fromCharCode(iconData.codePoint),
                style: TextStyle(
                    fontSize: iconSize,
                    fontFamily: iconData.fontFamily,
                    package: iconData.fontPackage,
                    color: Colors.indigo.withOpacity(0.02 +
                        random.nextDouble() * 0.03))));
        textPainter.layout();
        canvas.save();
        canvas.translate(x + jitterX, y + jitterY);
        canvas.rotate(rotation);
        textPainter.paint(
            canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
