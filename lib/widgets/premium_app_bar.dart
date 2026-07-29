import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'edukn_logo.dart';
import '../services/user_permission_service.dart';
import '../services/term_service.dart';
import '../screens/school/profile_settings_screen.dart';
import '../screens/teacher/teacher_qr_scan_screen.dart';
import '../screens/portfolio/portfolio_screen.dart';
import '../screens/school/student_registration_screen.dart';
import '../screens/school/class_management_screen.dart';

class PremiumAppBar extends StatefulWidget implements PreferredSizeWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;
  final String subtitle;
  final bool showSearch;
  final bool showBackButton;
  final VoidCallback? onTermChanged;
  final List<Widget>? actions;

  const PremiumAppBar({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
    required this.subtitle,
    this.showSearch = true,
    this.showBackButton = true,
    this.onTermChanged,
    this.actions,
  }) : super(key: key);

  @override
  State<PremiumAppBar> createState() => _PremiumAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _PremiumAppBarState extends State<PremiumAppBar> {
  Map<String, dynamic>? userData;
  Map<String, dynamic>? schoolData;

  // Term variables
  List<Map<String, dynamic>> _terms = [];
  Map<String, dynamic>? _activeTerm;
  Map<String, dynamic>? _selectedTerm;

  // Search variables
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  OverlayEntry? _searchOverlayEntry;
  final LayerLink _searchLayerLink = LayerLink();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _isMobileSearchActive = false;
  bool _suppressFocusListener = false;
  StateSetter? _overlaySetState;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _loadTerms();
    _searchFocusNode.addListener(() {
      if (_suppressFocusListener) return;
      if (_searchFocusNode.hasFocus) {
        _showSearchOverlay();
      } else {
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

  Future<void> _loadInitialData() async {
    final data = await UserPermissionService.loadUserData();
    if (mounted) {
      setState(() {
        userData = data;
      });
    }
    _loadSchoolData();
  }

  Future<void> _loadSchoolData() async {
    try {
      final schoolQuery = await FirebaseFirestore.instance
          .collection('schools')
          .where('institutionId', isEqualTo: widget.institutionId)
          .limit(1)
          .get();

      if (schoolQuery.docs.isNotEmpty) {
        if (mounted) {
          setState(() {
            schoolData = schoolQuery.docs.first.data();
          });
        }
      }
    } catch (e) {
      debugPrint('Okul verisi yüklenemedi: $e');
    }
  }

  Future<void> _loadTerms() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final email = user.email;
      if (email == null) return;

      final profileData = await UserPermissionService.loadUserData();
      final institutionId = await UserPermissionService.resolveInstitutionId(email, userData: profileData);

      final snapshot = await FirebaseFirestore.instance
          .collection('terms')
          .where('institutionId', isEqualTo: institutionId)
          .get();

      final termsList = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      termsList.sort((a, b) {
        final aYear = a['startYear'] ?? 0;
        final bYear = b['startYear'] ?? 0;
        return bYear.compareTo(aYear);
      });

      final active = termsList.firstWhere(
        (t) => t['isActive'] == true,
        orElse: () => termsList.isNotEmpty ? termsList.first : {},
      );

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
      debugPrint('Dönemler yüklenirken hata: $e');
    }
  }

  void _showTermSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Icon(Icons.calendar_month_rounded, color: Colors.indigo.shade900, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Dönem Yönetimi',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_terms.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Henüz dönem tanımlanmamış')),
              )
            else
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 242,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _terms.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final term = _terms[index];
                      final isActive = term['isActive'] == true;
                      final isSelected = _selectedTerm == null
                          ? isActive
                          : _selectedTerm!['id'] == term['id'];
                      return InkWell(
                        onTap: () async {
                          final isActive = term['isActive'] == true;

                          if (isActive) {
                            await TermService().clearSelectedTerm();
                          } else {
                            await TermService().setSelectedTerm(
                              term['id'],
                              term['name'] ?? '${term['startYear']}-${term['endYear']}',
                            );
                          }

                          setState(() => _selectedTerm = term);
                          Navigator.pop(context);
                          if (widget.onTermChanged != null) {
                            widget.onTermChanged!();
                          }
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
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.indigo.shade50 : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? Colors.indigo.shade200 : Colors.grey.shade200,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: isActive
                                    ? Colors.green.shade100
                                    : (isSelected ? Colors.indigo.shade100 : Colors.grey.shade100),
                                child: Icon(
                                  isActive
                                      ? Icons.check_circle_rounded
                                      : (isSelected ? Icons.visibility : Icons.history),
                                  color: isActive
                                      ? Colors.green.shade700
                                      : (isSelected ? Colors.indigo : Colors.blueGrey.shade400),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      term['name'] ?? '${term['startYear']}-${term['endYear']}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: isSelected
                                            ? Colors.indigo.shade900
                                            : Colors.blueGrey.shade900,
                                      ),
                                    ),
                                    Text(
                                      isActive ? 'Aktif Dönem' : 'Geçmiş Dönem',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isActive
                                            ? Colors.green.shade700
                                            : Colors.blueGrey.shade400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                color: isSelected ? Colors.indigo.shade700 : Colors.blueGrey.shade300,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
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
      final snapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .get();
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
            Navigator.push(context, MaterialPageRoute(builder: (_) => PortfolioScreen(
              institutionId: widget.institutionId,
              schoolTypeId: stId,
              schoolTypeName: stName,
              initialStudentId: studentId,
            )));
          },
          'onRegTap': () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => StudentRegistrationScreen(
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

  void _safeNavigate(Function action) {
    _suppressFocusListener = true;
    action();
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

  void _showSearchOverlay() {
    if (_searchOverlayEntry != null) return;
    _searchOverlayEntry = _createSearchOverlayEntry();
    Overlay.of(context).insert(_searchOverlayEntry!);
  }

  void _hideSearchOverlay() {
    _searchOverlayEntry?.remove();
    _searchOverlayEntry = null;
  }

  OverlayEntry _createSearchOverlayEntry() {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 1100;
    final overlayWidth = isMobile ? (size.width - 32) : 450.0;
    final double appBarHeight = kToolbarHeight + MediaQuery.of(context).padding.top;

    return OverlayEntry(
      builder: (overlayCtx) {
        if (isMobile) {
          return Stack(
            children: [
              Positioned(
                top: appBarHeight + 4,
                left: 16,
                right: 16,
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
            ],
          );
        }

        return Stack(
          children: [
            CompositedTransformFollower(
              link: _searchLayerLink,
              showWhenUnlinked: false,
              offset: const Offset(0, 52),
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
        );
      },
    );
  }

  Widget _buildInitialSearchItems() {
    final List<Map<String, dynamic>> shortcuts = [
      {
        'title': 'Öğrenci Kaydı',
        'subtitle': 'Eğitim Modülü',
        'icon': Icons.person_add_outlined,
        'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => StudentRegistrationScreen(fixedSchoolTypeId: widget.schoolTypeId, fixedSchoolTypeName: widget.schoolTypeName, fixedInstitutionId: widget.institutionId)))
      },
      {
        'title': 'Şube Listesi',
        'subtitle': 'Yönetim Modülü',
        'icon': Icons.group_outlined,
        'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (context) => ClassManagementScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: widget.schoolTypeName)))
      }
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
          );
        }).toList()
      ],
    );
  }

  String _getUserDisplayName() {
    if (userData != null) return userData!['fullName'] ?? 'Kullanıcı';
    return schoolData?['adminFullName'] ?? 'Yönetici';
  }

  String _getUserRole() {
    if (userData != null) {
      final role = userData!['role'] ?? '';
      const roleMap = {
        'admin': 'Kurum Admini',
        'genel_mudur': 'Genel Müdür',
        'mudur': 'Müdür',
        'mudir_yardimcisi': 'Müdür Yardımcısı',
        'ogretmen': 'Öğretmen',
        'personel': 'Personel',
      };
      return roleMap[role] ?? role;
    }
    return 'Yönetici';
  }

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
      UserPermissionService.clearCache();
      TermService().clearCache();
      await FirebaseAuth.instance.signOut();
      if (mounted) Navigator.pushReplacementNamed(context, '/school-login');
    }
  }

  Widget _buildProfileButton(String currentTermName, bool isMobile) {
    final displayName = _getUserDisplayName();
    final role = _getUserRole();
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';

    return PopupMenuButton<String>(
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.12),
      onSelected: (value) {
        if (value == 'profile') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => const ProfileSettingsScreen(isSchoolSettings: false),
            ),
          );
        } else if (value == 'school_settings') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => const ProfileSettingsScreen(isSchoolSettings: true),
            ),
          );
        } else if (value == 'notifications') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => const ProfileSettingsScreen(isSchoolSettings: false),
            ),
          );
        } else if (value == 'qr') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherQrScanScreen()));
        } else if (value == 'term') {
          _showTermSelector();
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
        if (userData == null || userData!['role'] == 'genel_mudur' || userData!['role'] == 'admin') ...[
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'school_settings',
            child: Row(children: [
              Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.business_outlined, color: Colors.blue.shade700, size: 18)),
              const SizedBox(width: 12),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Okul Bilgileri', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text('Kurum Ayarlarını Yönet', style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
              ]),
            ]),
          ),
        ],
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'notifications',
          child: Row(children: [
            Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.notifications_active_outlined, color: Colors.teal.shade700, size: 18)),
            const SizedBox(width: 12),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Bildirim Ayarları', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text('Tercihleri Düzenle', style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
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
        if (isMobile) ...[
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'term',
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _selectedTerm != null && _selectedTerm!['isActive'] != true ? Colors.orange.shade50 : Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _selectedTerm != null && _selectedTerm!['isActive'] != true ? Icons.history : Icons.calendar_today_outlined,
                  color: _selectedTerm != null && _selectedTerm!['isActive'] != true ? Colors.orange.shade700 : Colors.indigo.shade700,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Dönem İşlemleri', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(
                    currentTermName,
                    style: TextStyle(
                      fontSize: 11,
                      color: _selectedTerm != null && _selectedTerm!['isActive'] != true ? Colors.orange.shade700 : Colors.blueGrey,
                      fontWeight: _selectedTerm != null && _selectedTerm!['isActive'] != true ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ]),
          ),
        ],
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

  Widget _buildTermSelectorButton(String currentTermName, bool isMobile) {
    return InkWell(
      onTap: _showTermSelector,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12, vertical: 8),
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
            if (!isMobile) ...[
              const SizedBox(width: 8),
              Text(currentTermName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.indigo),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isMobile) {
    return CompositedTransformTarget(
      link: _searchLayerLink,
      child: Container(
        width: 380,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(40),
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Öğrenci veya işlem ara...',
            hintStyle: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13),
            prefixIcon: Icon(Icons.search, color: Colors.indigo.shade300, size: 20),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 11),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileSearchInput() {
    return CompositedTransformTarget(
      link: _searchLayerLink,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(40),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.blueGrey),
              onPressed: () => setState(() => _isMobileSearchActive = false),
            ),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Arayın...',
                  hintStyle: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13),
                  border: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 1100;
    final String currentTermName = _selectedTerm != null
        ? (_selectedTerm!['termName'] ?? '${_selectedTerm!['startYear']}-${_selectedTerm!['endYear']}')
        : (_activeTerm != null ? (_activeTerm!['termName'] ?? 'Aktif Dönem') : 'Dönem Seçin');

    return Container(
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
            if (_isMobileSearchActive && widget.showSearch) ...[
              Expanded(child: _buildMobileSearchInput()),
            ] else ...[
              if (widget.showBackButton &&
                  (userData == null ||
                      UserPermissionService.hasAnyMainModuleAccess(userData) ||
                      (userData!['schoolTypes'] as List<dynamic>? ?? []).length > 1 ||
                      Navigator.canPop(context)))
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.indigo),
                  onPressed: () => Navigator.maybePop(context),
                ),
              const SizedBox(width: 8),
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
              if (isMobile) ...[
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.schoolTypeName,
                        style: TextStyle(
                          color: Colors.indigo.shade900,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        widget.subtitle,
                        style: TextStyle(
                          color: Colors.indigo.shade400,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.schoolTypeName,
                      style: TextStyle(
                        color: Colors.indigo.shade900,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        color: Colors.indigo.shade400,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
              if (!isMobile && widget.showSearch) ...[
                const Spacer(),
                _buildSearchBar(isMobile),
                const Spacer(),
              ],
              if (isMobile && widget.showSearch) ...[
                if (widget.actions != null) ...widget.actions!,
                IconButton(
                  icon: const Icon(Icons.search, color: Colors.indigo),
                  onPressed: () {
                    setState(() => _isMobileSearchActive = true);
                    _searchFocusNode.requestFocus();
                  },
                ),
                const SizedBox(width: 4),
                _buildProfileButton(currentTermName, isMobile),
              ] else ...[
                if (widget.showSearch) const Spacer(),
                if (widget.actions != null) ...[
                  ...widget.actions!,
                  const SizedBox(width: 8),
                ],
                _buildTermSelectorButton(currentTermName, isMobile),
                const SizedBox(width: 8),
                _buildProfileButton(currentTermName, isMobile),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
