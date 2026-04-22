import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/edukn_logo.dart';
import '../../services/term_service.dart';
import 'dart:async';
import 'dart:ui';
import 'assessment/assessment_dashboard_screen.dart';
import 'terms_screen.dart';
import 'notes/personal_notes_screen.dart';
import 'hr/hr_hub_screen.dart';
import 'guidance/demand/demand_dashboard_screen.dart';
import '../portfolio/portfolio_screen.dart';
import 'dart:math' as math;
import '../teacher/teacher_qr_scan_screen.dart';
import 'student_registration_screen.dart';
import '../../main.dart';

import 'school_types/school_type_announcements_screen.dart';
import 'school_types/school_type_social_media_screen.dart';
import 'school_types/chat/chat_screen.dart';
import 'school_types/school_type_detail_screen.dart';
import '../../widgets/stylish_bottom_nav.dart';

class SchoolDashboardV2Screen extends StatefulWidget {
  const SchoolDashboardV2Screen({Key? key}) : super(key: key);

  @override
  _SchoolDashboardV2ScreenState createState() => _SchoolDashboardV2ScreenState();
}

class _SchoolDashboardV2ScreenState extends State<SchoolDashboardV2Screen> {
  int _currentIndex = 1;
  Map<String, dynamic>? schoolData;
  Map<String, dynamic>? userData; 
  Map<String, dynamic>? activeTerm; 
  Map<String, dynamic>? selectedTerm; 
  List<Map<String, dynamic>> allTerms = [];
  Function? _pendingNavAction; 
  StateSetter? _overlaySetState;
  bool isLoading = true;
  final TermService _termService = TermService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  OverlayEntry? _searchOverlayEntry;
  final LayerLink _searchLayerLink = LayerLink();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _isMobileSearchActive = false;
  String _selectedCategory = 'Tümü';

  bool _suppressFocusListener = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _searchFocusNode.addListener(() {
      if (_suppressFocusListener) return;
      if (_searchFocusNode.hasFocus) {
        _showSearchOverlay();
      } else {
        // Gecikme ekle: butonların onPressed'ının overlay kapanmadan önce çalışmasına izin ver
        // (_GlobalKeyboardUnfocusWrapper her tıklamada unfocus() çağırıyor)
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted && !_searchFocusNode.hasFocus && !_suppressFocusListener) {
            _hideSearchOverlay();
          }
        });
      }
    });
  }

  @override
  void dispose() { 
    _searchController.dispose(); 
    _searchFocusNode.dispose(); 
    _hideSearchOverlay(); 
    super.dispose(); 
  }

  void _safeNavigate(Function action) {
    debugPrint('eduKN: _safeNavigate - navigatorKey: ${MyApp.navigatorKey.currentState}');
    
    // Focus listener'ı geçici olarak sustur (unfocus → overlay kapanmasın)
    _suppressFocusListener = true;
    
    // Önce aksiyonu çağır (MyApp.navigatorKey context bağımsız)
    debugPrint('eduKN: Aksiyon çağrılıyor...');
    action();
    debugPrint('eduKN: Aksiyon çağrıldı.');
    
    // Sonra overlay ve state'i temizle
    _hideSearchOverlay();
    _overlaySetState = null;
    _searchFocusNode.unfocus();
    _suppressFocusListener = false;
    
    if (mounted) {
      setState(() {
        _isMobileSearchActive = false;
        _searchController.clear();
        _searchResults = [];
      });
    }
  }
  void _showSearchOverlay() { if (_searchOverlayEntry != null) return; _searchOverlayEntry = _createSearchOverlayEntry(); Overlay.of(context).insert(_searchOverlayEntry!); }
  void _hideSearchOverlay() { _searchOverlayEntry?.remove(); _searchOverlayEntry = null; }

  OverlayEntry _createSearchOverlayEntry() {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 1100;
    final overlayWidth = isMobile ? (size.width - 32) : 450.0;
    return OverlayEntry(
      builder: (overlayCtx) => Stack(
        children: [
          CompositedTransformFollower(
            link: _searchLayerLink,
            showWhenUnlinked: false,
            offset: Offset(isMobile ? -(size.width * 0.05) : 0, 52),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: overlayWidth,
                child: StatefulBuilder(
                  builder: (_, setOverlayState) {
                    _overlaySetState = setOverlayState;
                    return Material(
                      elevation: 8,
                      shadowColor: Colors.black.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(24),
                      color: Colors.white,
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 400),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.indigo.shade100, width: 1.2),
                        ),
                        child: _isSearching
                          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(strokeWidth: 2)))
                          : _searchResults.isEmpty && _searchController.text.isNotEmpty
                            ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Sonuç bulunamadı.', style: TextStyle(color: Colors.blueGrey, fontSize: 13, fontWeight: FontWeight.w500))))
                            : _searchResults.isEmpty
                              ? _buildInitialSearchItems()
                              : ListView.separated(
                                  shrinkWrap: true,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  itemCount: _searchResults.length,
                                  separatorBuilder: (_, __) => Divider(height: 1, color: Colors.indigo.withOpacity(0.05)),
                                  itemBuilder: (_, index) {
                                    final item = _searchResults[index];
                                    final isStudent = item['type'] == 'student';
                                    final onTapAction = item['onTap'] as Function?;
                                    final onRegTapAction = item['onRegTap'] as Function?;
                                    return ListTile(
                                      onTap: () { if (onTapAction != null) _safeNavigate(onTapAction); },
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                                      leading: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10)),
                                        child: Icon(item['icon'] as IconData, color: Colors.indigo, size: 20),
                                      ),
                                      title: Text(item['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B))),
                                      subtitle: Text(item['subtitle'] as String, style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade400)),
                                      trailing: isStudent ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.folder_shared_outlined, size: 18, color: Colors.indigo),
                                            onPressed: () { if (onTapAction != null) _safeNavigate(onTapAction); },
                                            constraints: const BoxConstraints(),
                                            padding: const EdgeInsets.all(8),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.how_to_reg_outlined, size: 18, color: Colors.orange),
                                            onPressed: () { if (onRegTapAction != null) _safeNavigate(onRegTapAction); },
                                            constraints: const BoxConstraints(),
                                            padding: const EdgeInsets.all(8),
                                          ),
                                        ],
                                      ) : null,
                                    );
                                  },
                                ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialSearchItems() {
    final List<Map<String, dynamic>> shortcuts = [
      {'title': 'Öğrenci Kaydı', 'subtitle': 'Eğitim Modülü', 'icon': Icons.person_add_outlined, 'onTap': () => MyApp.navigatorKey.currentState?.pushNamed('/student-registration')},
      {'title': 'Muhasebe', 'subtitle': 'Mali İşler', 'icon': Icons.account_balance_wallet_outlined, 'onTap': () => MyApp.navigatorKey.currentState?.pushNamed('/accounting')},
      {'title': 'İK / Personel', 'subtitle': 'Yönetim Modülü', 'icon': Icons.group_outlined, 'onTap': () => MyApp.navigatorKey.currentState?.pushNamed('/hr')}
    ];
    return ListView(
      shrinkWrap: true,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 12), child: Text('HIZLI ERİŞİM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.indigo.shade300, letterSpacing: 1.2))),
        ...shortcuts.map((s) {
          final shortcutAction = s['onTap'] as Function?;
          return ListTile(
          onTap: () {
            if (shortcutAction != null) _safeNavigate(shortcutAction);
          },
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10)), child: Icon(s['icon'] as IconData, color: Colors.indigo, size: 18)),
          title: Text(s['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B))),
          subtitle: Text(s['subtitle'] as String, style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
        );}).toList()
      ],
    );
  }

  void _onSearchChanged(String value) async {
    if (value.isEmpty) {
      if (mounted) setState(() => _searchResults = []);
      _overlaySetState?.call(() {});
      return;
    }
    if (mounted) setState(() => _isSearching = true);
    _overlaySetState?.call(() {});
    try {
      final snapshot = await FirebaseFirestore.instance.collection('students').where('institutionId', isEqualTo: schoolData?['institutionId']).get();
      final matches = snapshot.docs.where((doc) {
        final name = (doc['fullName'] ?? '').toString().toLowerCase();
        final number = (doc['studentNumber'] ?? '').toString().toLowerCase();
        final query = value.toLowerCase();
        return name.contains(query) || number.contains(query);
      }).take(5).map((doc) {
        final data = doc.data();
        final studentId = doc.id;
        final stId = data['schoolTypeId'] ?? '';
        final stName = data['schoolTypeName'] ?? 'Okul Türü';

        return {
          'type': 'student',
          'title': data['fullName'],
          'subtitle': 'Öğrenci No: ${data['studentNumber']}',
          'icon': Icons.person_outline,
          'onTap': () {
            MyApp.navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => PortfolioScreen(
              institutionId: schoolData!['institutionId'],
              schoolTypeId: stId,
              schoolTypeName: stName,
              initialStudentId: studentId,
            )));
          },
          'onRegTap': () {
            MyApp.navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => StudentRegistrationScreen(
              initialStudentId: studentId,
            )));
          }
        };
      }).toList();
      if (mounted) {
        setState(() { _searchResults = matches; _isSearching = false; });
        _overlaySetState?.call(() {});
      }
    } catch (e) {
      if (mounted) setState(() => _isSearching = false);
      _overlaySetState?.call(() {});
    }
  }

  Future<void> _loadInitialData() async { await _loadSchoolData(); }

  Future<void> _loadSchoolData() async {
    try {
      final user = FirebaseAuth.instance.currentUser; if (user == null) { Navigator.pushReplacementNamed(context, '/school-login'); return; }
      final email = user.email!; final institutionId = email.split('@')[1].split('.')[0].toUpperCase(); var instIdForQueries = institutionId;
      var schoolQuery = await FirebaseFirestore.instance.collection('schools').where('institutionId', isEqualTo: institutionId).limit(1).get();
      Map<String, dynamic>? data; if (schoolQuery.docs.isNotEmpty) { final schoolDoc = schoolQuery.docs.first; data = schoolDoc.data(); data['id'] = schoolDoc.id; } else { final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get(); if (userDoc.exists) { final u = userDoc.data() as Map<String, dynamic>; final fallbackSchoolId = u['schoolId'] as String?; if (fallbackSchoolId != null && fallbackSchoolId.isNotEmpty) { final schoolById = await FirebaseFirestore.instance.collection('schools').doc(fallbackSchoolId).get(); if (schoolById.exists) { data = schoolById.data() as Map<String, dynamic>; data['id'] = schoolById.id; final schInstId = (data['institutionId'] ?? '').toString(); if (schInstId.isNotEmpty) instIdForQueries = schInstId; } } } }
      if (data != null) {
        final allTermsQuery = await FirebaseFirestore.instance.collection('terms').where('institutionId', isEqualTo: instIdForQueries).get();
        final termsList = allTermsQuery.docs.map((doc) { final termData = doc.data(); termData['id'] = doc.id; return termData; }).toList();
        termsList.sort((a, b) { final aYear = a['startYear'] ?? 0; final bYear = b['startYear'] ?? 0; return bYear.compareTo(aYear); });
        Map<String, dynamic>? activeTermData; for (var term in termsList) if (term['isActive'] == true) { activeTermData = term; break; }
        final viewingTermId = await _termService.getSelectedTermId();
        Map<String, dynamic>? currentViewingTerm; if (viewingTermId != null) try { currentViewingTerm = termsList.firstWhere((t) => t['id'] == viewingTermId); } catch (_) {}
        final prefs = await SharedPreferences.getInstance(); final isImpersonating = prefs.getBool('is_impersonating') ?? false; final impersonatedEmail = prefs.getString('impersonated_user_email');
        Map<String, dynamic>? currentUserData;
        if (isImpersonating && impersonatedEmail != null) { final impUserQuery = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: impersonatedEmail).limit(1).get(); if (impUserQuery.docs.isNotEmpty) currentUserData = impUserQuery.docs.first.data(); } else { final username = email.split('@')[0]; final userQuery = await FirebaseFirestore.instance.collection('users').where('institutionId', isEqualTo: data['institutionId']).where('username', isEqualTo: username).limit(1).get(); if (userQuery.docs.isNotEmpty) currentUserData = userQuery.docs.first.data(); }
        if (mounted) setState(() { schoolData = data; userData = currentUserData; allTerms = termsList; activeTerm = activeTermData; selectedTerm = currentViewingTerm; isLoading = false; });
      }
    } catch (e) { if (mounted) setState(() => isLoading = false); }
  }

  Future<void> _switchToTerm(Map<String, dynamic> term) async { final isActive = term['isActive'] == true; if (isActive) await _termService.clearSelectedTerm(); else await _termService.setSelectedTerm(term['id'], term['termName'] ?? '${term['startYear']}-${term['endYear']}'); setState(() => isLoading = true); await _loadInitialData(); }
  bool _hasModuleAccess(String moduleKey) { if (schoolData == null) return false; final activeModules = schoolData!['activeModules'] as List<dynamic>? ?? []; if (!activeModules.contains(moduleKey)) return false; if (userData == null) return true; final modulePerms = userData!['modulePermissions'] as Map<String, dynamic>?; if (modulePerms == null) return false; final modulePerm = modulePerms[moduleKey] as Map<String, dynamic>?; if (modulePerm == null) return false; return modulePerm['enabled'] == true; }
  String _getUserDisplayName() { if (userData != null) return userData!['fullName'] ?? 'Kullanıcı'; return schoolData?['adminFullName'] ?? 'Yönetici'; }
  String _getUserRole() { if (userData != null) { final role = userData!['role'] ?? ''; const roleMap = { 'mudur': 'Müdür', 'mudir_yardimcisi': 'Müdür Yardımcısı', 'ogretmen': 'Öğretmen', 'personel': 'Personel', 'genel_mudur': 'Genel Müdür', }; return roleMap[role] ?? role; } return 'Yönetici'; }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.logout_rounded, color: Colors.red, size: 22)),
          const SizedBox(width: 12),
          const Text('Çıkış Yap', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        content: const Text('Hesabınızdan çıkış yapmak istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) Navigator.pushReplacementNamed(context, '/school-login');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (schoolData == null) return const Scaffold(body: Center(child: Text('Okul verileri yüklenemedi!')));
    final size = MediaQuery.of(context).size; final isMobile = size.width < 1100;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildAppBar(isMobile),
      body: Stack(
        children: [
          const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: DoodlePainter()))),
          IndexedStack(
            index: _currentIndex,
            children: [
              _buildCommunicationTab(isMobile),
              _buildDashboardTab(isMobile),
              _buildOperationsTab(isMobile),
            ],
          ),
        ],
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
            padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 2),
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
                    _buildFooterLink('Destek', isMobile),
                    const SizedBox(width: 16),
                    _buildFooterLink('Gizlilik', isMobile),
                    const SizedBox(width: 16),
                    _buildFooterLink('Şartlar', isMobile),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommunicationTab(bool isMobile) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Haberleşme',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.indigo.shade900, letterSpacing: -0.5),
              ),
              const SizedBox(height: 8),
              Text(
                'Tüm kurum iletişim kanallarına tek bir yerden ulaşın.',
                style: TextStyle(fontSize: 15, color: Colors.blueGrey.shade600, height: 1.4),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            physics: const BouncingScrollPhysics(),
            children: [
              _buildCommCard(
                title: 'Duyurular',
                description: 'Tüm okul türlerinin duyurularını görüntüleyin ve yönetin.',
                icon: Icons.campaign_rounded,
                color: Colors.orange,
                onTap: () => Navigator.pushNamed(context, '/announcements'),
              ),
              const SizedBox(height: 20),
              _buildCommCard(
                title: 'Sosyal Medya',
                description: 'Okulun global sosyal medya paylaşımlarını inceleyin.',
                icon: Icons.share_rounded,
                color: Colors.blue,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SchoolTypeSocialMediaScreen(
                  schoolTypeId: '',
                  schoolTypeName: 'Tüm Okul Türleri',
                  institutionId: schoolData!['institutionId'],
                ))),
              ),
              const SizedBox(height: 20),
              _buildCommCard(
                title: 'Mesajlar',
                description: 'Tüm kullanıcılara ve okul türlerine mesajlaşın.',
                icon: Icons.forum_rounded,
                color: Colors.green,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
                  schoolTypeId: '',
                  schoolTypeName: 'Tüm Okul Türleri',
                  institutionId: schoolData!['institutionId'],
                ))),
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCommCard({required String title, required String description, required IconData icon, required MaterialColor color, required VoidCallback onTap}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: color.shade100.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 10))]),
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
                Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(20)), child: Icon(icon, size: 32, color: color.shade700)),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo.shade900)),
                      const SizedBox(height: 6),
                      Text(description, style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade600, height: 1.4)),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 18, color: Colors.indigo.shade200),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardTab(bool isMobile) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isWideScreen = constraints.maxWidth > 900;

        if (isWideScreen) {
          return Row(
            children: [
              Expanded(
                flex: 2,
                child: SharedNotificationSection(
                  schoolTypeId: '',
                  institutionId: schoolData!['institutionId'],
                ),
              ),
              Expanded(
                flex: 3,
                child: SharedCalendarSection(
                  schoolTypeId: '',
                  institutionId: schoolData!['institutionId'],
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
                    tabs: const [
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
                        schoolTypeId: '',
                        institutionId: schoolData!['institutionId'],
                      ),
                      SharedCalendarSection(
                        schoolTypeId: '',
                        institutionId: schoolData!['institutionId'],
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

  Widget _buildOperationsTab(bool isMobile) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1400),
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: isMobile ? 24 : 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCategorySelector(isMobile),
                    const SizedBox(height: 16),
                    _buildGridSections(isMobile),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar(bool isMobile) {
    String currentTermName = selectedTerm != null ? (selectedTerm!['termName'] ?? '${selectedTerm!['startYear']}-${selectedTerm!['endYear']}') : (activeTerm != null ? (activeTerm!['termName'] ?? 'Aktif Dönem') : 'Dönem Seçin');
    return AppBar(
      backgroundColor: Colors.white.withOpacity(0.95),
      elevation: 0,
      centerTitle: true,
      flexibleSpace: Stack(
        children: [
          if (!_isMobileSearchActive)
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
                ],
              ),
            ),
        ],
      ),
      title: _isMobileSearchActive
          ? _buildMobileSearchInput()
          : (!isMobile ? _buildSearchBar(isMobile) : const SizedBox.shrink()),
      actions: [
        if (isMobile && !_isMobileSearchActive)
          IconButton(
            icon: const Icon(Icons.search, color: Colors.indigo),
            onPressed: () {
              setState(() => _isMobileSearchActive = true);
              _searchFocusNode.requestFocus();
            },
          ),
        if (!_isMobileSearchActive) _buildTermSelectorButton(currentTermName, isMobile),
        const SizedBox(width: 8),
        if (!_isMobileSearchActive) _buildProfileButton(),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildMobileSearchInput() { return CompositedTransformTarget(link: _searchLayerLink, child: Container(height: 42, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(40)), child: Row(children: [IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.blueGrey), onPressed: () => setState(() => _isMobileSearchActive = false)), Expanded(child: TextField(controller: _searchController, focusNode: _searchFocusNode, onChanged: _onSearchChanged, autofocus: true, decoration: InputDecoration(hintText: 'Arayın...', hintStyle: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13), border: InputBorder.none)))]))); }
  Widget _buildSearchBar(bool isMobile) { return CompositedTransformTarget(link: _searchLayerLink, child: Container(width: 450, height: 42, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(40)), child: TextField(controller: _searchController, focusNode: _searchFocusNode, onChanged: _onSearchChanged, decoration: InputDecoration(hintText: 'Öğrenci, menü veya işlem ara...', hintStyle: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13), prefixIcon: Icon(Icons.search, color: Colors.indigo.shade300, size: 20), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 11))))); }
  Widget _buildTermSelectorButton(String currentTermName, bool isMobile) { return InkWell(onTap: _showTermSelector, borderRadius: BorderRadius.circular(10), child: Container(padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12, vertical: 8), decoration: BoxDecoration(color: selectedTerm != null ? Colors.orange.shade50 : Colors.indigo.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: selectedTerm != null ? Colors.orange.shade200 : Colors.indigo.shade100)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.calendar_today_outlined, size: 14, color: selectedTerm != null ? Colors.orange.shade800 : Colors.indigo), if (!isMobile) ...[const SizedBox(width: 8), Text(currentTermName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)), const SizedBox(width: 4), const Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.indigo)]]))); }

  void _showTermSelector() {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => Container(decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))), padding: const EdgeInsets.fromLTRB(24, 16, 24, 32), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))), const SizedBox(height: 24), Row(children: [Icon(Icons.calendar_month_rounded, color: Colors.indigo.shade900, size: 28), const SizedBox(width: 12), const Text('Dönem Yönetimi', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)))]), const SizedBox(height: 24), Flexible(child: ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4), child: ListView.separated(shrinkWrap: true, itemCount: allTerms.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (context, index) { final term = allTerms[index]; final isActive = term['isActive'] == true; final isCurrent = selectedTerm == null ? isActive : selectedTerm!['id'] == term['id']; return InkWell(onTap: () { Navigator.pop(context); _switchToTerm(term); }, borderRadius: BorderRadius.circular(16), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: isCurrent ? Colors.indigo.shade50 : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: isCurrent ? Colors.indigo.shade200 : Colors.grey.shade200)), child: Row(children: [CircleAvatar(backgroundColor: isActive ? Colors.green.shade100 : (isCurrent ? Colors.indigo.shade100 : Colors.grey.shade100), child: Icon(isActive ? Icons.check_circle_rounded : (isCurrent ? Icons.visibility : Icons.history), color: isActive ? Colors.green.shade700 : (isCurrent ? Colors.indigo : Colors.blueGrey.shade400), size: 20)), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(term['termName'] ?? '${term['startYear']}-${term['endYear']}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isCurrent ? Colors.indigo.shade900 : Colors.blueGrey.shade900)), Text(isActive ? 'Aktif Dönem' : 'Geçmiş Dönem', style: TextStyle(fontSize: 12, color: isActive ? Colors.green.shade700 : Colors.blueGrey.shade400))])), Icon(isCurrent ? Icons.radio_button_checked : Icons.radio_button_off, color: isCurrent ? Colors.indigo.shade700 : Colors.blueGrey.shade300)]))); }))), const SizedBox(height: 24), _buildSelectorAction(icon: Icons.sync_rounded, title: 'Verileri Aktif Döneme Ata', subtitle: 'Eksik dönem bilgisi olan verileri günceller.', color: Colors.blue, onTap: () { Navigator.pop(context); _migrateDataToActiveTerm(); }), _buildSelectorAction(icon: Icons.settings_rounded, title: 'Dönemleri Yönet', subtitle: 'Yeni dönem ekle veya ayarları düzenle.', color: Colors.indigo, onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsScreen())).then((_) => _loadInitialData()); }), _buildSelectorAction(icon: Icons.delete_forever_rounded, title: 'Tüm Verileri Sıfırla', subtitle: 'Kurumun tüm verilerini kalıcı olarak siler.', color: Colors.red, onTap: () { Navigator.pop(context); _deleteAllData(); })])));
  }

  Widget _buildSelectorAction({required IconData icon, required String title, required String subtitle, required Color color, required VoidCallback onTap}) { return ListTile(onTap: onTap, leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 20)), title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueGrey.shade900)), subtitle: Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade500)), trailing: const Icon(Icons.chevron_right, size: 20), contentPadding: EdgeInsets.zero); }

  Widget _buildProfileButton() {
    final displayName = _getUserDisplayName();
    final role = _getUserRole();
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';
    return PopupMenuButton<String>(
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.12),
      onSelected: (value) {
        if (value == 'profile' || value == 'edit_profile') {
          Navigator.pushNamed(context, '/profile-settings');
        } else if (value == 'qr') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherQrScanScreen()));
        } else if (value == 'logout') {
          _logout();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.indigo.shade100,
                  child: Text(initial, style: TextStyle(color: Colors.indigo.shade800, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(role, style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade500)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'profile',
          child: Row(children: [
            Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.person_outline_rounded, color: Colors.indigo.shade700, size: 18)),
            const SizedBox(width: 12),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Profilim', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text('Profili Düzenle', style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
            ]),
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'qr',
          child: Row(children: [
            Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.qr_code_scanner_rounded, color: Colors.orange.shade700, size: 18)),
            const SizedBox(width: 12),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Giriş / Çıkış (QR)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text('Kamera ile QR tarama', style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
            ]),
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'logout',
          child: Row(children: [
            Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.logout_rounded, color: Colors.red.shade600, size: 18)),
            const SizedBox(width: 12),
            Text('Çıkış Yap', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.red.shade700)),
          ]),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: CircleAvatar(
          radius: 17,
          backgroundColor: Colors.indigo.shade50,
          child: Text(initial, style: const TextStyle(color: Colors.indigo, fontSize: 13, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Future<void> _migrateDataToActiveTerm() async { final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Veri Aktarımı'), content: const Text('Dönem bilgisi bulunmayan veriler aktif döneme atanacak. Devam edilsin mi?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aktar'))])); if (confirm == true) { setState(() => isLoading = true); await _termService.migrateDataToActiveTerm(); await _loadInitialData(); } }
  Future<void> _deleteAllData() async { final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('DİKKAT: Veriler Silinecek', style: TextStyle(color: Colors.red)), content: const Text('Kurumun tüm verileri (öğrenciler, dersler, vb.) KALICI olarak silinecek. Bu işlem geri alınamaz!'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Tümünü Sil'))])); if (confirm == true) { setState(() => isLoading = true); await _deleteAllData(); await _loadInitialData(); } }

  Widget _buildCategorySelector(bool isMobile) {
    final categories = [
      {'label': 'Tümü', 'icon': Icons.apps_rounded, 'color': Colors.indigo},
      {'label': 'Akademik', 'icon': Icons.school_rounded, 'color': Colors.indigo},
      {'label': 'Rehberlik', 'icon': Icons.psychology_rounded, 'color': Colors.indigo},
      {'label': 'Kurumsal', 'icon': Icons.groups_rounded, 'color': Colors.indigo},
      {'label': 'Ölçme', 'icon': Icons.assignment_turned_in_rounded, 'color': Colors.indigo},
      {'label': 'Finans', 'icon': Icons.account_balance_wallet_rounded, 'color': Colors.indigo},
      {'label': 'Operasyon', 'icon': Icons.support_agent_rounded, 'color': Colors.indigo},
      {'label': 'Sistem', 'icon': Icons.settings_suggest_rounded, 'color': Colors.indigo},
      {'label': 'Kişisel', 'icon': Icons.person, 'color': Colors.indigo},
    ];

    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth > 1400 ? 1400.0 : screenWidth;
    final availableWidth = contentWidth - (isMobile ? 32 : 48);

    return Container(
      height: 100,
      width: double.infinity,
      child: ScrollConfiguration(
        behavior: MyCustomScrollBehavior(),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Container(
            constraints: BoxConstraints(minWidth: availableWidth.isNegative ? 0.0 : availableWidth),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: categories.map((cat) {
                final isSelected = _selectedCategory == cat['label'];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: InkWell(
                    onTap: () => setState(() => _selectedCategory = cat['label'] as String),
                    borderRadius: BorderRadius.circular(16),
                    child: AnimatedContainer(
                      key: ValueKey('cat_${cat['label']}_$isMobile'),
                      duration: const Duration(milliseconds: 200),
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
            title: 'EĞİTİM',
            badge: 'Akademik',
            icon: Icons.school_outlined,
            color: Colors.indigo,
            cardWidth: cardWidth,
            isMobile: isMobile,
            category: 'Akademik',
            showAllItems: isFiltered,
            items: [
              if (_hasModuleAccess('ogrenci_kayit')) {'title': 'Ön Kayıt', 'onTap': () => Navigator.pushNamed(context, '/pre-registration')},
              if (_hasModuleAccess('ogrenci_kayit')) {'title': 'Öğrenci Kaydı', 'onTap': () => Navigator.pushNamed(context, '/student-registration')},
              if (_hasModuleAccess('okul_turleri')) {'title': 'Okul Türleri', 'onTap': () => Navigator.pushNamed(context, '/school-types')},
            ],
            onTap: () => _showEducationHub(),
          ),
          _ModuleCardWidget(
            title: 'REHBERLİK İŞLEMLERİ',
            badge: 'Rehberlik',
            icon: Icons.psychology_outlined,
            color: Colors.deepOrange,
            cardWidth: cardWidth,
            isMobile: isMobile,
            category: 'Rehberlik',
            showAllItems: isFiltered,
            items: [
              {'title': 'Öğrenci Portfolyosu', 'onTap': () => MyApp.navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => PortfolioScreen(institutionId: schoolData!['institutionId'], schoolTypeId: schoolData!['id'], schoolTypeName: schoolData!['schoolName'] ?? '', showAllSchoolTypes: true)))},
              {'title': 'Talepler (Yönlendirmeler)', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => DemandDashboardScreen(institutionId: schoolData!['institutionId'], schoolTypeId: '', showAllSchoolTypes: true, userData: userData)))},
              {'title': 'Görüşme Kayıtları', 'onTap': () {}},
              {'title': 'Rehberlik Testleri', 'onTap': () {}},
            ],
            onTap: () => _showGuidanceHub(),
          ),
          _ModuleCardWidget(
            title: 'İnsan Kaynakları',
            badge: 'Kurumsal',
            icon: Icons.group_outlined,
            color: Colors.purple,
            cardWidth: cardWidth,
            isMobile: isMobile,
            category: 'Kurumsal',
            showAllItems: isFiltered,
            items: _getHrItems(),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HrHubScreen())),
          ),
          _ModuleCardWidget(
            title: 'ÖLÇME DEĞERLENDİRME',
            badge: 'Ölçme',
            icon: Icons.assignment_turned_in_outlined,
            color: Colors.teal,
            cardWidth: cardWidth,
            isMobile: isMobile,
            category: 'Ölçme',
            showAllItems: isFiltered,
            items: [
              {'title': 'Sınav Tanımları', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssessmentDashboardScreen(institutionId: schoolData!['institutionId'], schoolTypeId: schoolData!['id'])))},
              {'title': 'Optik Formlar', 'onTap': () {}},
              {'title': 'Soru Bankası', 'onTap': () {}},
              {'title': 'Hata Kitapçığı', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssessmentDashboardScreen(institutionId: schoolData!['institutionId'], schoolTypeId: schoolData!['id'], initialTab: 2)))},
              if (_hasModuleAccess('yoklama')) {'title': 'Yoklama Raporları', 'onTap': () {}},
              {'title': 'Gelişim Analizi', 'onTap': () {}},
            ],
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssessmentDashboardScreen(institutionId: schoolData!['institutionId'], schoolTypeId: schoolData!['id']))),
          ),
          _ModuleCardWidget(
            title: 'MALİ İŞLER',
            badge: 'Finans',
            icon: Icons.account_balance_wallet_outlined,
            color: Colors.blue,
            cardWidth: cardWidth,
            isMobile: isMobile,
            category: 'Finans',
            showAllItems: isFiltered,
            items: [
              if (_hasModuleAccess('muhasebe')) {'title': 'Gelir Kaydı', 'onTap': () => Navigator.pushNamed(context, '/accounting')},
              {'title': 'Gider Kaydı', 'onTap': () => Navigator.pushNamed(context, '/accounting')},
              {'title': 'Veli Tahsilat', 'onTap': () => Navigator.pushNamed(context, '/accounting')},
              {'title': 'Makbuz Al', 'onTap': () => Navigator.pushNamed(context, '/accounting')},
            ],
            onTap: () => Navigator.pushNamed(context, '/accounting'),
          ),
          _ModuleCardWidget(
            title: 'HİZMETLER',
            badge: 'Operasyon',
            icon: Icons.support_agent_outlined,
            color: Colors.orange,
            cardWidth: cardWidth,
            isMobile: isMobile,
            category: 'Operasyon',
            showAllItems: isFiltered,
            items: [
              {'title': 'Yemekhane İşlemleri', 'onTap': () => Navigator.pushNamed(context, '/support-services')},
              {'title': 'Servis İşlemleri', 'onTap': () => Navigator.pushNamed(context, '/support-services')},
              {'title': 'Depo ve Satın Alma', 'onTap': () => Navigator.pushNamed(context, '/support-services')},
            ],
            onTap: () => Navigator.pushNamed(context, '/support-services'),
          ),
          _ModuleCardWidget(
            title: 'SİSTEM AYARLARI',
            badge: 'Sistem',
            icon: Icons.settings_outlined,
            color: Colors.blueGrey,
            cardWidth: cardWidth,
            isMobile: isMobile,
            category: 'Sistem',
            showAllItems: isFiltered,
            items: [
              if (userData == null || _hasModuleAccess('kullanici_yonetimi')) {'title': 'Kullanıcı Yönetimi', 'onTap': () => Navigator.pushNamed(context, '/user-management')},
              {'title': 'Yetki Tanımlama', 'onTap': () => Navigator.pushNamed(context, '/permission-definition')},
              {'title': 'Uygulama Ayarları', 'onTap': () => Navigator.pushNamed(context, '/app-settings')},
              {'title': 'Veri Yedekleme', 'onTap': () {}},
            ],
            onTap: () => Navigator.pushNamed(context, '/app-settings'),
            buttonLabel: 'DÜZENLE',
          ),
          _ModuleCardWidget(
            title: 'KİŞİSEL İŞLEMLER',
            badge: 'Kişisel',
            icon: Icons.person,
            color: Colors.pink,
            cardWidth: cardWidth,
            isMobile: isMobile,
            category: 'Kişisel',
            showAllItems: isFiltered,
            items: [
              {'title': 'Notlarım', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PersonalNotesScreen()))},
            ],
            onTap: () => setState(() => _selectedCategory = 'Kişisel'),
          ),
        ];

    final filteredModules = _selectedCategory == 'Tümü' ? allModules : allModules.where((m) => m.category == _selectedCategory).toList();

    return Wrap(
      key: ValueKey('grid_${_selectedCategory}_$isMobile'),
      spacing: 24,
      runSpacing: 24,
      children: filteredModules,
    );
  }

  List<Map<String, dynamic>> _getHrItems() { 
    List<Map<String, dynamic>> items = []; 
    if (_hasModuleAccess('insan_kaynaklari')) items.addAll([
      {'title': 'Personel Bilgi Yönetimi', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HrHubScreen()))}, 
      {'title': 'Devam – Mesai – İzin', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HrHubScreen()))}, 
      {'title': 'Maaş ve Bordro', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HrHubScreen()))}, 
      {'title': 'Performans Yönetimi', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HrHubScreen()))}, 
      {'title': 'Eğitim ve Gelişim', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HrHubScreen()))},
      {'title': 'Sözleşme ve Evrak', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HrHubScreen()))},
      {'title': 'İK Raporlama', 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HrHubScreen()))},
    ]); 
    return items; 
  }

  Widget _buildFooterLink(String label, bool isMobile) {
    return InkWell(
      onTap: () {},
      child: Text(
        label,
        style: TextStyle(
          color: Colors.blueGrey.shade400,
          fontSize: isMobile ? 10 : 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _showGuidanceHub() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: _buildSmallHubCard(
                    title: 'Öğrenci Portfolyosu',
                    subtitle: 'Öğrenci gelişimini ve sınav geçmişini inceleyin.',
                    icon: Icons.assignment_ind_rounded,
                    color: Colors.indigo,
                    onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => PortfolioScreen(institutionId: schoolData!['institutionId'], schoolTypeId: schoolData!['id'], schoolTypeName: schoolData!['schoolName'] ?? '', showAllSchoolTypes: true))); },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildSmallHubCard(
                    title: 'Talepler',
                    subtitle: 'Görüşme ve yönlendirme taleplerini yönetin.',
                    icon: Icons.task_alt_rounded,
                    color: Colors.orange,
                    onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => DemandDashboardScreen(institutionId: schoolData!['institutionId'], schoolTypeId: '', showAllSchoolTypes: true, userData: userData))); },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
             _buildLargeHubCard(
              title: 'Rehberlik Analizi',
              subtitle: 'Kurum genelindeki talep yoğunluğunu ve başarı oranlarını inceleyin.',
              buttonLabel: 'Analizi Aç',
              onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => DemandDashboardScreen(institutionId: schoolData!['institutionId'], schoolTypeId: '', showAllSchoolTypes: true, userData: userData))); },
            ),
          ],
        ),
      ),
    );
  }

  void _showEducationHub() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: _buildSmallHubCard(
                    title: 'Ön Kayıt',
                    subtitle: 'Yeni aday öğrenci başvurularını yönetin.',
                    icon: Icons.campaign_rounded,
                    color: Colors.indigo,
                    onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/pre-registration'); },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildSmallHubCard(
                    title: 'Öğrenci Kaydı',
                    subtitle: 'Kesin kayıt işlemlerini ve öğrenci kütüğünü yönetin.',
                    icon: Icons.how_to_reg_rounded,
                    color: Colors.purple,
                    onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/student-registration'); },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildLargeHubCard(
              title: 'Okul Türleri',
              subtitle: 'Anaokulu, İlkokul, Ortaokul kademelerini buradan yönetin.',
              buttonLabel: 'Görüntüle',
              onTap: () { Navigator.pop(context); Navigator.pushNamed(context, '/school-types'); },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallHubCard({required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 150,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 8))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 24),
            ),
            const Spacer(),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade400, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildLargeHubCard({required String title, required String subtitle, required String buttonLabel, required VoidCallback onTap}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.indigo,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: Colors.indigo.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.indigo, Colors.indigo.shade700],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 8),
                Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8), height: 1.5)),
              ],
            ),
          ),
          const SizedBox(width: 24),
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.indigo,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: Text(buttonLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Removed _buildFeatureCards, _buildFeatureCard, _buildFooter, and _buildFooterLink, since we are using StylishBottomNav now.
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

class DoodlePainter extends CustomPainter {
  const DoodlePainter();
  @override void paint(Canvas canvas, Size size) {
    const iconSize = 40.0; const spacing = 120.0; final icons = [Icons.school, Icons.book, Icons.edit, Icons.science, Icons.calculate, Icons.public, Icons.history_edu, Icons.psychology, Icons.menu_book, Icons.biotech, Icons.brush, Icons.music_note]; final random = math.Random(42); 
    for (double x = 0; x < size.width + spacing; x += spacing) { for (double y = 0; y < size.height + spacing; y += spacing) { final iconData = icons[random.nextInt(icons.length)]; final jitterX = random.nextDouble() * 40 - 20; final jitterY = random.nextDouble() * 40 - 20; final rotation = random.nextDouble() * 0.5 - 0.25; final textPainter = TextPainter(textDirection: TextDirection.ltr, text: TextSpan(text: String.fromCharCode(iconData.codePoint), style: TextStyle(fontSize: iconSize, fontFamily: iconData.fontFamily, package: iconData.fontPackage, color: Colors.indigo.withOpacity(0.02 + random.nextDouble() * 0.03)))); textPainter.layout(); canvas.save(); canvas.translate(x + jitterX, y + jitterY); canvas.rotate(rotation); textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2)); canvas.restore(); } }
  }
  @override bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
      };
}
