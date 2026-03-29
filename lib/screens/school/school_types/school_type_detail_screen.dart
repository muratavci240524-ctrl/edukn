import 'dart:ui';
import 'package:flutter/material.dart';
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

import 'chat/chat_screen.dart';
import '../../hr/leave/leave_management_screen.dart';
import '../../../../widgets/stylish_bottom_nav.dart';
import '../guidance/guidance_interview_screen.dart';
import '../guidance/guidance_study_program_screen.dart';
import '../../guidance/guidance_test_catalog_screen.dart'; // Import Catalog
import '../../support_services/cafeteria/cafeteria_screen.dart';
import '../../support_services/transportation/transportation_screen.dart';
import '../../support_services/health/health_screen.dart';
import '../../support_services/library/library_screen.dart';
import '../../support_services/cleaning/cleaning_screen.dart';
import '../../support_services/inventory/inventory_screen.dart';
import '../../guidance/reports/development_report_management_screen.dart';
import 'school_type_detail_v2_screen.dart';

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

// ============== MESAJLAR TAB ==============
class _MessagesTab extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const _MessagesTab({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<_MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<_MessagesTab> {
  @override
  Widget build(BuildContext context) {
    return ChatScreen(
      schoolTypeId: widget.schoolTypeId,
      schoolTypeName: widget.schoolTypeName,
      institutionId: widget.institutionId,
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
  // Açık olan kategoriyi takip et (tek seferde sadece bir tane)
  String? _expandedCategory;

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
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.indigo,
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.schoolTypeName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'İşlemler',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: MediaQuery.of(context).size.width < 600
            ? [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: (value) {
                    if (value == 'term') {
                      _showTermSelector();
                    } else if (value == 'profile') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) => const UserProfileScreen(),
                        ),
                      );
                    } else if (value == 'home') {
                      Navigator.pop(context);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'term',
                      child: Row(
                        children: [
                          Icon(
                            _selectedTerm != null &&
                                    _selectedTerm!['isActive'] != true
                                ? Icons.history
                                : Icons.calendar_month,
                            color: Colors.indigo,
                          ),
                          const SizedBox(width: 12),
                          const Text('Dönem Değiştir'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'profile',
                      child: Row(
                        children: [
                          Icon(
                            Icons.account_circle_outlined,
                            color: Colors.indigo,
                          ),
                          SizedBox(width: 12),
                          Text('Profil Bilgisi'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'home',
                      child: Row(
                        children: [
                          Icon(Icons.home_outlined, color: Colors.indigo),
                          SizedBox(width: 12),
                          Text('Anasayfaya Dön'),
                        ],
                      ),
                    ),
                  ],
                ),
              ]
            : [
                // Dönem Seçici
                Builder(
                  builder: (context) {
                    final isViewingPastTerm =
                        _selectedTerm != null &&
                        _selectedTerm!['isActive'] != true;
                    return InkWell(
                      onTap: _showTermSelector,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isViewingPastTerm
                              ? Colors.orange[50]
                              : Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isViewingPastTerm
                                ? Colors.orange[400]!
                                : Colors.white.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isViewingPastTerm
                                  ? Icons.history
                                  : Icons.calendar_month,
                              size: 16,
                              color: isViewingPastTerm
                                  ? Colors.orange[700]
                                  : Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _selectedTerm != null
                                  ? '${_selectedTerm!['startYear']}-${_selectedTerm!['endYear']}'
                                  : 'Dönem',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isViewingPastTerm
                                    ? Colors.orange[700]
                                    : Colors.white,
                              ),
                            ),
                            Icon(
                              Icons.arrow_drop_down,
                              size: 16,
                              color: isViewingPastTerm
                                  ? Colors.orange[700]
                                  : Colors.white,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                // Profil
                IconButton(
                  icon: Icon(
                    Icons.account_circle_outlined,
                    color: Colors.white,
                  ),
                  tooltip: 'Profilim',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => const UserProfileScreen(),
                      ),
                    );
                  },
                ),
                // V2 Preview Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) => SchoolTypeDetailV2Screen(
                            schoolTypeId: widget.schoolTypeId,
                            schoolTypeName: widget.schoolTypeName,
                            institutionId: widget.institutionId,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.auto_awesome, size: 16, color: Colors.amber),
                    label: const Text('V2\'yi Dene', style: TextStyle(color: Colors.white, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.white.withOpacity(0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
                // Okul Yönetimine Dön
                IconButton(
                  icon: Icon(Icons.home_outlined, color: Colors.white),
                  tooltip: 'Okul Yönetimine Dön',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
      ),
      body: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: 1200),
          child: Column(
            children: [
              _buildCategorySelector(),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.all(16),
                  children: [
                    // KAYIT İŞLEMLERİ
                    if (_selectedCategory == 'Tümü' ||
                        _selectedCategory == 'Kayıt')
                      _buildExpandableCategory(
                        categoryId: 'kayit',
                        title: 'Kayıt İşlemleri',
                        icon: Icons.app_registration,
                        color: Colors.blue,
                        itemCount: 6,
                      ),
                    if (_selectedCategory == 'Tümü' ||
                        _selectedCategory == 'Kayıt')
                      SizedBox(height: 12),

                    // EĞİTİM İŞLEMLERİ
                    if (_selectedCategory == 'Tümü' ||
                        _selectedCategory == 'Eğitim')
                      _buildExpandableCategory(
                        categoryId: 'egitim',
                        title: 'Eğitim İşlemleri',
                        icon: Icons.school,
                        color: Colors.green,
                        itemCount: 9,
                      ),
                    if (_selectedCategory == 'Tümü' ||
                        _selectedCategory == 'Eğitim')
                      SizedBox(height: 12),

                    // REHBERLİK VE PORTFOLYO
                    if (_selectedCategory == 'Tümü' ||
                        _selectedCategory == 'Portfolyo')
                      _buildExpandableCategory(
                        categoryId: 'portfolyo',
                        title: 'Rehberlik ve Portfolyo',
                        icon: Icons.folder_special,
                        color: Colors.deepPurple,
                        itemCount: 6,
                      ),
                    if (_selectedCategory == 'Tümü' ||
                        _selectedCategory == 'Portfolyo')
                      SizedBox(height: 12),

                    // ÖLÇME DEĞERLENDİRME
                    if (_selectedCategory == 'Tümü' ||
                        _selectedCategory == 'Ölçme')
                      _buildExpandableCategory(
                        categoryId: 'olcme',
                        title: 'Ölçme Değerlendirme',
                        icon: Icons.bar_chart,
                        color: Colors.red,
                        itemCount: 4,
                      ),
                    if (_selectedCategory == 'Tümü' ||
                        _selectedCategory == 'Ölçme')
                      SizedBox(height: 12),

                    if (_selectedCategory == 'Tümü' ||
                        _selectedCategory == 'Görevlendirme')
                      _buildExpandableCategory(
                        categoryId: 'gorevlendirme',
                        title: 'Görevlendirme ve İzin',
                        icon: Icons.assignment_ind,
                        color: Colors.brown,
                        itemCount: 6,
                      ),
                    if (_selectedCategory == 'Tümü' ||
                        _selectedCategory == 'Görevlendirme')
                      SizedBox(height: 12),

                    // DESTEK HİZMETLERİ
                    if (_selectedCategory == 'Tümü' ||
                        _selectedCategory == 'Destek')
                      _buildExpandableCategory(
                        categoryId: 'destek',
                        title: 'Destek Hizmetleri',
                        icon: Icons.support_agent,
                        color: Colors.cyan,
                        itemCount: 6,
                      ),
                    if (_selectedCategory == 'Tümü' ||
                        _selectedCategory == 'Destek')
                      SizedBox(height: 12),

                    // RAPORLAR İŞLEMLERİ
                    if (_selectedCategory == 'Tümü' ||
                        _selectedCategory == 'Raporlar')
                      _buildExpandableCategory(
                        categoryId: 'raporlar',
                        title: 'Raporlar İşlemleri',
                        icon: Icons.analytics_outlined,
                        color: Colors.indigo,
                        itemCount: 3,
                      ),
                    if (_selectedCategory == 'Tümü' ||
                        _selectedCategory == 'Ayarlar')
                      SizedBox(height: 12),

                    // AYARLAR
                    if (_selectedCategory == 'Tümü' ||
                        _selectedCategory == 'Ayarlar')
                      _buildExpandableCategory(
                        categoryId: 'ayarlar',
                        title: 'Ayarlar',
                        icon: Icons.settings,
                        color: Colors.grey.shade700,
                        itemCount: 3,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategorySelector() {
    final categories = [
      {'label': 'Tümü', 'icon': Icons.grid_view_rounded, 'id': 'Tümü'},
      {'label': 'Kayıt', 'icon': Icons.app_registration, 'id': 'kayit'},
      {'label': 'Eğitim', 'icon': Icons.school, 'id': 'egitim'},
      {'label': 'Portfolyo', 'icon': Icons.folder_special, 'id': 'portfolyo'},
      {'label': 'Ölçme', 'icon': Icons.bar_chart, 'id': 'olcme'},
      {
        'label': 'Görevlendirme',
        'icon': Icons.assignment_ind,
        'id': 'gorevlendirme',
      },
      {'label': 'Destek', 'icon': Icons.support_agent, 'id': 'destek'},
      {'label': 'Raporlar', 'icon': Icons.analytics_outlined, 'id': 'raporlar'},
      {'label': 'Ayarlar', 'icon': Icons.settings, 'id': 'ayarlar'},
    ];

    return Container(
      width: double.infinity,
      height: 120,
      child: Center(
        child: ScrollConfiguration(
          behavior: MyCustomScrollBehavior(),
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
                          color: isSelected
                              ? Colors.indigo
                              : Colors.grey.shade200,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            cat['icon'] as IconData,
                            color: isSelected
                                ? Colors.white
                                : Colors.indigo.shade400,
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
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.grey.shade700,
                              ),
                              maxLines: 1,
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

  // Expandable kategori oluştur
  Widget _buildExpandableCategory({
    required String categoryId,
    required String title,
    required IconData icon,
    required Color color,
    required int itemCount,
  }) {
    final isExpanded = _expandedCategory == categoryId;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              setState(() {
                // Eğer zaten açıksa kapat, değilse aç (diğerlerini kapat)
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
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade900,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '$itemCount işlem',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            Divider(height: 1),
            Padding(
              padding: EdgeInsets.all(16),
              child: _buildCategoryContent(categoryId),
            ),
          ],
        ],
      ),
    );
  }

  // Kategori içeriğini oluştur
  Widget _buildCategoryContent(String categoryId) {
    switch (categoryId) {
      case 'kayit':
        return Column(
          children: [
            _buildMenuItem('Öğrenci Listesi', Icons.groups, Colors.blue),
            _buildMenuItem('Personel Listesi', Icons.badge, Colors.purple),
            _buildMenuItem('Şube Listesi', Icons.class_, Colors.blue),
            _buildMenuItem('Ders Listesi', Icons.book, Colors.teal),
            _buildMenuItem(
              'Derslik Listesi',
              Icons.meeting_room,
              Colors.orange,
            ),
            _buildMenuItem('Kitap Listesi', Icons.menu_book, Colors.brown),
          ],
        );
      case 'egitim':
        return Column(
          children: [
            _buildMenuItem(
              'Çalışma Takvimi ve Yıllık Planlar',
              Icons.calendar_month,
              Colors.green,
            ),
            _buildMenuItem('Ders Saatleri', Icons.access_time, Colors.blue),
            _buildMenuItem('Ders Programı', Icons.schedule, Colors.pink),
            _buildMenuItem('Şube Ders Programı', Icons.view_list, Colors.blue),
            _buildMenuItem(
              'Derslik Ders Programı',
              Icons.meeting_room,
              Colors.orange,
            ),
            _buildMenuItem(
              'Öğretmen Ders Programı',
              Icons.person,
              Colors.purple,
            ),
            _buildMenuItem('Anket İşlemleri', Icons.poll, Colors.cyan),
            _buildMenuItem('Etüt İşlemleri', Icons.groups, Colors.lightBlue),
          ],
        );
      case 'portfolyo':
        return Column(
          children: [
            _buildMenuItem(
              'Portfolyo',
              Icons.folder_special,
              Colors.deepPurple,
            ),
            _buildMenuItem(
              'Görüşmeler',
              Icons.connect_without_contact,
              Colors.blue,
            ),
            _buildMenuItem(
              'Gözlem ve Etkinlik İşlemleri',
              Icons.visibility,
              Colors.orange,
            ),
            _buildMenuItem(
              'Ders Çalışma Programı',
              Icons.edit_calendar,
              Colors.green,
            ),
            _buildMenuItem(
              'Rehberlik Envanterleri',
              Icons.assignment_turned_in,
              Colors.red,
            ),
            _buildMenuItem(
              'Rehberlik Kütüphanesi',
              Icons.local_library,
              Colors.brown,
            ),
            _buildMenuItem(
              '360 Gelişim Raporları',
              Icons.analytics,
              Colors.indigo,
            ),
          ],
        );
      case 'olcme':
        return Column(
          children: [
            _buildMenuItem('Raporlar', Icons.bar_chart, Colors.red),
            _buildMenuItem('Denemeler', Icons.assignment, Colors.amber),
            _buildMenuItem('Sınavlar', Icons.quiz, Colors.deepOrange),

            _buildMenuItem(
              'Tanımlar',
              Icons.settings_applications,
              Colors.grey,
            ),
          ],
        );
      case 'gorevlendirme':
        return Column(
          children: [
            _buildMenuItem('To do List', Icons.checklist, Colors.teal),
            _buildMenuItem('İzin Yönetimi', Icons.event_busy, Colors.red),
            _buildMenuItem(
              'Geçici Öğretmen Atama',
              Icons.person_add,
              Colors.orange,
            ),
            _buildMenuItem('Nöbet İşlemleri', Icons.security, Colors.blueGrey),
            _buildMenuItem(
              'Gezi Görevlendirmeleri',
              Icons.bus_alert,
              Colors.green,
            ),
            _buildMenuItem(
              'Proje Görevlendirmeleri',
              Icons.science,
              Colors.deepPurple,
            ),
          ],
        );
      case 'destek':
        return Column(
          children: [
            _buildMenuItem(
              'Yemekhane İşlemleri',
              Icons.restaurant,
              Colors.orange,
            ),
            _buildMenuItem(
              'Servis İşlemleri',
              Icons.directions_bus,
              Colors.blue,
            ),
            _buildMenuItem(
              'Sağlık İşlemleri',
              Icons.local_hospital,
              Colors.red,
            ),
            _buildMenuItem(
              'Kütüphane İşlemleri',
              Icons.menu_book,
              Colors.deepPurple,
            ),
            _buildMenuItem(
              'Temizlik İşlemleri',
              Icons.cleaning_services,
              Colors.green,
            ),
            _buildMenuItem('Depo ve Satın Alma', Icons.inventory, Colors.brown),
          ],
        );
      case 'raporlar':
        return Column(
          children: [
            _buildMenuItem(
              'Yoklama Raporları',
              Icons.fact_check_outlined,
              Colors.red,
            ),
            _buildMenuItem(
              'Ödev Raporları',
              Icons.assignment_outlined,
              Colors.amber,
            ),
            _buildMenuItem(
              'Ölçme Değerlendirme Raporları',
              Icons.assessment_outlined,
              Colors.deepOrange,
            ),
          ],
        );
      case 'ayarlar':
        return Column(
          children: [
            _buildMenuItem(
              'Yetki Tanımlama',
              Icons.security,
              Colors.blueAccent,
            ),
            _buildMenuItem(
              'Kullanıcı Yetkilendirme',
              Icons.manage_accounts,
              Colors.deepPurple,
            ),
            _buildMenuItem(
              'Uygulama Ayarları',
              Icons.settings_suggest,
              Colors.grey,
            ),
          ],
        );
      default:
        return SizedBox.shrink();
    }
  }

  // Menü öğesi oluştur
  Widget _buildMenuItem(String title, IconData icon, Color color) {
    return InkWell(
      onTap: () {
        // Öğrenci Listesi için özel sayfa
        if (title == 'Öğrenci Listesi') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StudentRegistrationScreen(
                fixedSchoolTypeId: widget.schoolTypeId,
                fixedSchoolTypeName: widget.schoolTypeName,
                fixedInstitutionId: widget.institutionId,
              ),
            ),
          );
        }
        // Personel Listesi için özel sayfa
        else if (title == 'Personel Listesi') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StaffListScreen(
                fixedSchoolTypeId: widget.schoolTypeId,
                fixedSchoolTypeName: widget.schoolTypeName,
              ),
            ),
          );
        } else if (title == 'Yemekhane İşlemleri') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CafeteriaScreen(
                fixedSchoolTypeId: widget.schoolTypeId,
                fixedSchoolTypeName: widget.schoolTypeName,
              ),
            ),
          );
        } else if (title == 'Servis İşlemleri') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TransportationScreen(
                fixedSchoolTypeId: widget.schoolTypeId,
                fixedSchoolTypeName: widget.schoolTypeName,
              ),
            ),
          );
        } else if (title == 'Sağlık İşlemleri') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => HealthScreen(
                fixedSchoolTypeId: widget.schoolTypeId,
                fixedSchoolTypeName: widget.schoolTypeName,
              ),
            ),
          );
        } else if (title == 'Kütüphane İşlemleri') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LibraryScreen(
                fixedSchoolTypeId: widget.schoolTypeId,
                fixedSchoolTypeName: widget.schoolTypeName,
              ),
            ),
          );
        } else if (title == 'Temizlik İşlemleri') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CleaningScreen(
                fixedSchoolTypeId: widget.schoolTypeId,
                fixedSchoolTypeName: widget.schoolTypeName,
              ),
            ),
          );
        } else if (title == 'Depo ve Satın Alma') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => InventoryScreen(
                fixedSchoolTypeId: widget.schoolTypeId,
                fixedSchoolTypeName: widget.schoolTypeName,
              ),
            ),
          );
        }
        // Şube Listesi için özel sayfa
        else if (title == 'Şube Listesi') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ClassManagementScreen(
                schoolTypeId: widget.schoolTypeId,
                schoolTypeName: widget.schoolTypeName,
                institutionId: widget.institutionId,
              ),
            ),
          );
        }
        // Ders Listesi için özel sayfa
        else if (title == 'Ders Listesi') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LessonManagementScreen(
                schoolTypeId: widget.schoolTypeId,
                schoolTypeName: widget.schoolTypeName,
                institutionId: widget.institutionId,
              ),
            ),
          );
        }
        // Derslik Listesi için özel sayfa
        else if (title == 'Derslik Listesi') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ClassroomManagementScreen(
                schoolTypeId: widget.schoolTypeId,
                schoolTypeName: widget.schoolTypeName,
                institutionId: widget.institutionId,
              ),
            ),
          );
        }
        // Çalışma Takvimi ve Yıllık Planlar için özel sayfa
        else if (title == 'Çalışma Takvimi ve Yıllık Planlar') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => WorkCalendarScreen(
                schoolTypeId: widget.schoolTypeId,
                schoolTypeName: widget.schoolTypeName,
                institutionId: widget.institutionId,
              ),
            ),
          );
        } else if (title == 'Ders Saatleri') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LessonHoursScreen(
                schoolTypeId: widget.schoolTypeId,
                schoolTypeName: widget.schoolTypeName,
                institutionId: widget.institutionId,
              ),
            ),
          );
        }
        // Ders Çalışma Programı için özel sayfa
        else if (title == 'Ders Çalışma Programı') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => GuidanceStudyProgramScreen(
                institutionId: widget.institutionId,
                schoolTypeId: widget.schoolTypeId,
              ),
            ),
          );
        }
        // Ders Programı için özel sayfa
        else if (title == 'Ders Programı') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ClassScheduleScreen(
                schoolTypeId: widget.schoolTypeId,
                schoolTypeName: widget.schoolTypeName,
                institutionId: widget.institutionId,
              ),
            ),
          );
        }
        // Şube Ders Programı için özel sayfa
        else if (title == 'Şube Ders Programı') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ClassScheduleViewScreen(
                schoolTypeId: widget.schoolTypeId,
                schoolTypeName: widget.schoolTypeName,
                institutionId: widget.institutionId,
              ),
            ),
          );
        }
        // Raporlar (Yeni ve Eski İsimler)
        else if (title == 'Yoklama Raporları' || title == 'Yoklama İşlemleri') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AttendanceOperationsScreen(
                institutionId: widget.institutionId,
                schoolTypeId: widget.schoolTypeId,
                schoolTypeName: widget.schoolTypeName,
              ),
            ),
          );
        } else if (title == 'Ödev Raporları' || title == 'Ödev İşlemleri') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => HomeworkOperationsScreen(
                institutionId: widget.institutionId,
                schoolTypeId: widget.schoolTypeId,
              ),
            ),
          );
        } else if (title == 'Ölçme Değerlendirme Raporları' ||
            title == 'Raporlar') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AssessmentReportsScreen(
                institutionId: widget.institutionId,
                schoolTypeId: widget.schoolTypeId,
              ),
            ),
          );
        }
        // Diğer İlgili Modüller
        else if (title == 'Öğretmen Ders Programı') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TeacherScheduleViewScreen(
                schoolTypeId: widget.schoolTypeId,
                schoolTypeName: widget.schoolTypeName,
                institutionId: widget.institutionId,
              ),
            ),
          );
        } else if (title == 'Anket İşlemleri') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SurveyListScreen(
                institutionId: widget.institutionId,
                schoolTypeId: widget.schoolTypeId,
                schoolTypeName: widget.schoolTypeName,
              ),
            ),
          );
        } else if (title == 'To do List') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ToDoListScreen(
                institutionId: widget.institutionId,
                schoolTypeId: widget.schoolTypeId,
              ),
            ),
          );
        } else if (title == 'Geçici Öğretmen Atama') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SubstituteTeacherListScreen(
                institutionId: widget.institutionId,
                schoolTypeId: widget.schoolTypeId,
                schoolTypeName: widget.schoolTypeName,
              ),
            ),
          );
        } else if (title == 'Tanımlar') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AssessmentDefinitionsScreen(
                institutionId: widget.institutionId,
              ),
            ),
          );
        } else if (title == 'Denemeler') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TrialExamListScreen(
                institutionId: widget.institutionId,
                schoolTypeId: widget.schoolTypeId,
              ),
            ),
          );
        } else if (title == 'Sınavlar') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ActiveExamListScreen(
                institutionId: widget.institutionId,
                schoolTypeId: widget.schoolTypeId,
              ),
            ),
          );
        } else if (title == 'Nöbet İşlemleri') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  DutyManagementScreen(institutionId: widget.institutionId),
            ),
          );
        } else if (title == 'Gezi Görevlendirmeleri') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FieldTripListScreen(
                institutionId: widget.institutionId,
                schoolTypeId: widget.schoolTypeId,
                schoolTypeName: widget.schoolTypeName,
              ),
            ),
          );
        } else if (title == 'İzin Yönetimi') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const LeaveManagementScreen(),
            ),
          );
        } else if (title == 'Proje Görevlendirmeleri') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProjectAssignmentListScreen(
                institutionId: widget.institutionId,
              ),
            ),
          );
        } else if (title == 'Portfolyo') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PortfolioScreen(
                institutionId: widget.institutionId,
                schoolTypeId: widget.schoolTypeId,
                schoolTypeName: widget.schoolTypeName,
              ),
            ),
          );
        } else if (title == 'Görüşmeler') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => GuidanceInterviewScreen(
                institutionId: widget.institutionId,
                schoolTypeId: widget.schoolTypeId,
                schoolTypeName: widget.schoolTypeName,
              ),
            ),
          );
        } else if (title == 'Rehberlik Envanterleri') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => GuidanceTestCatalogScreen(
                institutionId: widget.institutionId,
                schoolTypeId: widget.schoolTypeId,
              ),
            ),
          );
        } else if (title == 'Gözlem ve Etkinlik İşlemleri') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ActivityListScreen(
                institutionId: widget.institutionId,
                schoolTypeId: widget.schoolTypeId,
                schoolTypeName: widget.schoolTypeName,
              ),
            ),
          );
        } else if (title == 'Etüt İşlemleri') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EtutProcessScreen(
                institutionId: widget.institutionId,
                schoolTypeId: widget.schoolTypeId,
                schoolTypeName: widget.schoolTypeName,
              ),
            ),
          );
        } else if (title == 'Kitap Listesi') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => BookManagementScreen(
                institutionId: widget.institutionId,
                schoolTypeId: widget.schoolTypeId,
                schoolTypeName: widget.schoolTypeName,
              ),
            ),
          );
        } else if (title == '360 Gelişim Raporları') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DevelopmentReportManagementScreen(
                institutionId: widget.institutionId,
              ),
            ),
          );
        } else if (title == 'Yetki Tanımlama') {
          Navigator.pushNamed(context, '/permission-definition');
        } else if (title == 'Kullanıcı Yetkilendirme') {
          Navigator.pushNamed(context, '/user-management');
        } else if (title == 'Uygulama Ayarları') {
          Navigator.pushNamed(context, '/app-settings');
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$title yakında eklenecek')));
        }
      },
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade800),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: Colors.grey.shade400,
            ),
          ],
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
          return Scaffold(
            backgroundColor: Colors.grey.shade50,
            body: Row(
              children: [
                // Sol Panel: Bildirimler
                Expanded(
                  flex: 2,
                  child: _NotificationSection(
                    schoolTypeId: widget.schoolTypeId,
                    institutionId: widget.institutionId,
                  ),
                ),
                // Sağ Panel: Takvim
                Expanded(
                  flex: 3,
                  child: _CalendarSection(
                    schoolTypeId: widget.schoolTypeId,
                    institutionId: widget.institutionId,
                  ),
                ),
              ],
            ),
          );
        } else {
          return DefaultTabController(
            length: 2,
            child: Scaffold(
              backgroundColor: Colors.white,
              appBar: AppBar(
                backgroundColor: Colors.white,
                elevation: 0,
                title: Text(
                  'Dashboard',
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                bottom: TabBar(
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
              body: TabBarView(
                children: [
                  _NotificationSection(
                    schoolTypeId: widget.schoolTypeId,
                    institutionId: widget.institutionId,
                  ),
                  _CalendarSection(
                    schoolTypeId: widget.schoolTypeId,
                    institutionId: widget.institutionId,
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }
}

class _NotificationSection extends StatelessWidget {
  final String schoolTypeId;
  final String institutionId;

  const _NotificationSection({
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

class _CalendarSection extends StatefulWidget {
  final String schoolTypeId;
  final String institutionId;

  const _CalendarSection({
    required this.schoolTypeId,
    required this.institutionId,
  });

  @override
  State<_CalendarSection> createState() => _CalendarSectionState();
}

class _CalendarSectionState extends State<_CalendarSection> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  List<Map<String, dynamic>> _events = [];
  bool _isLoading = false;

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
              if (sId != widget.schoolTypeId) return false;
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
              if (sId != widget.schoolTypeId) return false;
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
              if (sId != widget.schoolTypeId) return false;
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
                padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_months[_focusedDay.month - 1]} ${_focusedDay.year}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade900,
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
                    Spacer(),
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
                          _focusedDay = DateTime(
                            _focusedDay.year,
                            _focusedDay.month - 1,
                          );
                        });
                        _loadEvents();
                      },
                      icon: Icon(Icons.chevron_left_rounded),
                      splashRadius: 24,
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _focusedDay = DateTime(
                            _focusedDay.year,
                            _focusedDay.month + 1,
                          );
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
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              SizedBox(height: 12),
              // Günler Grid
              Expanded(
                flex: isWideScreen ? 5 : 4, // Izgaraya daha fazla yer ver
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _buildCalendarGrid(),
                ),
              ),
              // Seçili Gün Etkinlikleri
              Expanded(
                flex: isWideScreen ? 3 : 3,
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
    final totalCells = 42;

    return GridView.builder(
      physics: ClampingScrollPhysics(), // İçerik sığmazsa kaydırılabilsin
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: isWideScreen
            ? 1.3
            : 1.1, // Daha basık hücreler, daha fazla satır sığar
      ),
      itemCount: totalCells,
      itemBuilder: (context, index) {
        int dayNum = index - firstDayWeekday + 1;
        bool isCurrentMonth = dayNum > 0 && dayNum <= daysInMonth;

        if (!isCurrentMonth) return SizedBox.shrink();

        final currentDay = DateTime(
          _focusedDay.year,
          _focusedDay.month,
          dayNum,
        );
        bool isSelected =
            dayNum == _selectedDay.day &&
            _focusedDay.month == _selectedDay.month &&
            _focusedDay.year == _selectedDay.year;

        bool isToday =
            dayNum == DateTime.now().day &&
            _focusedDay.month == DateTime.now().month &&
            _focusedDay.year == DateTime.now().year;

        // Bu gün için etkinlikleri bul
        final dayEvents = _events.where((e) {
          final eventDate = (e['date'] as Timestamp).toDate();
          return eventDate.day == dayNum &&
              eventDate.month == _focusedDay.month &&
              eventDate.year == _focusedDay.year;
        }).toList();

        return InkWell(
          onTap: () {
            setState(() {
              _selectedDay = currentDay;
            });
          },
          onLongPress: () => _showAddEventDialog(date: currentDay),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: Duration(milliseconds: 200),
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
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  dayNum.toString(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: (isSelected || isToday)
                        ? FontWeight.bold
                        : FontWeight.w500,
                    color: isSelected
                        ? Colors.white
                        : (isToday
                              ? Colors.blue.shade700
                              : Colors.grey.shade800),
                  ),
                ),
                if (dayEvents.isNotEmpty)
                  Container(
                    margin: EdgeInsets.only(top: 2),
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white70 : Colors.blue.shade400,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
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
