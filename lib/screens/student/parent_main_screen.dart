import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/stylish_bottom_nav.dart';
import '../../widgets/edukn_logo.dart';
import '../school/profile_settings_screen.dart';
import '../../services/user_permission_service.dart';
import '../../services/term_service.dart';
import 'parent_haberlesme_screen.dart';
import 'parent_operations_screen.dart';
import 'parent_dashboard_tab.dart';

class ParentMainScreen extends StatefulWidget {
  final String institutionId;

  const ParentMainScreen({Key? key, required this.institutionId}) : super(key: key);

  @override
  State<ParentMainScreen> createState() => _ParentMainScreenState();
}

class _ParentMainScreenState extends State<ParentMainScreen> {
  int _currentIndex = 1;
  String _selectedStudentId = '';
  String _selectedStudentName = '';
  String _selectedStudentClass = '';
  String _studentNumber = '';
  List<Map<String, dynamic>> _myChildren = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSelectedStudentAndChildren();
  }

  Future<void> _loadSelectedStudentAndChildren() async {
    if (mounted) setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // ── ADIM 1: SharedPreferences'ta kayıtlı bir öğrenci ID'si var mı? ──
      final savedId = prefs.getString('selected_student_id') ?? '';
      if (savedId.isNotEmpty) {
        final doc = await FirebaseFirestore.instance.collection('students').doc(savedId).get();
        if (doc.exists && mounted) {
          final d = doc.data()!;
          final nm = (d['fullName'] ?? '${d['name'] ?? ''} ${d['surname'] ?? ''}'.trim()).toString().trim();
          final no = (d['studentNo'] ?? d['studentNumber'] ?? '').toString();
          final cls = (d['className'] ?? '').toString();
          setState(() {
            _selectedStudentId = savedId;
            _selectedStudentName = nm;
            _selectedStudentClass = cls;
            _studentNumber = no;
          });
          await _saveToPrefs(prefs, savedId, nm, cls, no);
          return; // Tamam, her şey hazır
        }
      }

      // ── ADIM 2: Kullanıcı dokümanından bilgileri çek ──
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
      if (!userDoc.exists) return;
      final uData = userDoc.data()!;
      final tcNo = (uData['tcNo'] ?? '').toString().trim();
      final username = (uData['username'] ?? '').toString().trim();

      // ── ADIM 3: VELİ ise → parentTcNos ile çocukları bul ──
      if (tcNo.isNotEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('students')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('parentTcNos', arrayContains: tcNo)
            .get();
        if (snap.docs.isNotEmpty && mounted) {
          final children = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
          final prevId = prefs.getString('selected_student_id') ?? '';
          final matched = children.firstWhere((c) => c['id'] == prevId, orElse: () => children[0]);
          final nm = (matched['fullName'] ?? '${matched['name'] ?? ''} ${matched['surname'] ?? ''}'.trim()).toString().trim();
          final no = (matched['studentNo'] ?? matched['studentNumber'] ?? '').toString();
          final cls = (matched['className'] ?? '').toString();
          final id = matched['id'].toString();
          setState(() {
            _myChildren = children;
            _selectedStudentId = id;
            _selectedStudentName = nm;
            _selectedStudentClass = cls;
            _studentNumber = no;
          });
          await _saveToPrefs(prefs, id, nm, cls, no);
          return;
        }
      }

      // ── ADIM 4: ÖĞRENCİ ise → username = studentNo olarak ara ──
      if (username.isNotEmpty) {
        // username'i studentNo, studentNumber ve fullName alanlarına karşı sorgula
        for (final field in ['studentNo', 'studentNumber', 'username']) {
          final snap = await FirebaseFirestore.instance
              .collection('students')
              .where('institutionId', isEqualTo: widget.institutionId)
              .where(field, isEqualTo: username)
              .limit(1)
              .get();
          if (snap.docs.isNotEmpty && mounted) {
            final d = snap.docs.first.data();
            final id = snap.docs.first.id;
            final nm = (d['fullName'] ?? '${d['name'] ?? ''} ${d['surname'] ?? ''}'.trim()).toString().trim();
            final no = (d['studentNo'] ?? d['studentNumber'] ?? '').toString();
            final cls = (d['className'] ?? '').toString();
            setState(() {
              _selectedStudentId = id;
              _selectedStudentName = nm;
              _selectedStudentClass = cls;
              _studentNumber = no;
            });
            await _saveToPrefs(prefs, id, nm, cls, no);
            return;
          }
        }
      }

      // ── ADIM 5: İsim ile ara ──
      final name = (uData['name'] ?? '').toString().trim();
      final surname = (uData['surname'] ?? '').toString().trim();
      if (name.isNotEmpty && surname.isNotEmpty) {
        final fullName = '$name $surname';
        final snap = await FirebaseFirestore.instance
            .collection('students')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('fullName', isEqualTo: fullName)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty && mounted) {
          final d = snap.docs.first.data();
          final id = snap.docs.first.id;
          final nm = (d['fullName'] ?? fullName).toString();
          final no = (d['studentNo'] ?? d['studentNumber'] ?? '').toString();
          final cls = (d['className'] ?? '').toString();
          setState(() {
            _selectedStudentId = id;
            _selectedStudentName = nm;
            _selectedStudentClass = cls;
            _studentNumber = no;
          });
          await _saveToPrefs(prefs, id, nm, cls, no);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Öğrenci/Çocuk verisi yüklenirken hata: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveToPrefs(SharedPreferences prefs, String id, String name, String cls, String no) async {
    await prefs.setString('selected_student_id', id);
    await prefs.setString('selected_student_name', name);
    await prefs.setString('selected_student_class', cls);
    await prefs.setString('selected_student_no', no);
  }


  Future<void> _switchStudent(Map<String, dynamic> child) async {
    final prefs = await SharedPreferences.getInstance();
    final newId = child['id'];
    final newName = child['fullName'] ?? '';
    final newClass = child['className'] ?? '';
    final newNo = child['studentNumber']?.toString() ?? '';

    await prefs.setString('selected_student_id', newId);
    await prefs.setString('selected_student_name', newName);
    await prefs.setString('selected_student_class', newClass);

    setState(() {
      _selectedStudentId = newId;
      _selectedStudentName = newName;
      _selectedStudentClass = newClass;
      _studentNumber = newNo;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✓ Aktif öğrenci değiştirildi: $newName'),
        backgroundColor: Colors.indigo,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showStudentSwitchModal() {
    if (_myChildren.length <= 1) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Öğrenci Seçin',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E2661),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Takip etmek istediğiniz öğrenciyi seçin',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _myChildren.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final child = _myChildren[index];
                    final isSelected = child['id'] == _selectedStudentId;
                    final stNo = child['studentNumber']?.toString() ?? '';
                    final fullName = child['fullName'] ?? 'Öğrenci';

                    return InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        _switchStudent(child);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.indigo.shade50 : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? Colors.indigo.shade400 : Colors.grey.shade200,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: isSelected ? Colors.indigo : Colors.grey.shade400,
                              child: Icon(
                                child['gender'] == 'Kız' ? Icons.face_3_rounded : Icons.face_6_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fullName,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: isSelected ? Colors.indigo.shade900 : Colors.black87,
                                    ),
                                  ),
                                  Text(
                                    '${stNo.isNotEmpty ? '$stNo ' : ''}${child['className'] != null ? '(${child['className']})' : ''}',
                                    style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle_rounded, color: Colors.indigo, size: 22),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_portal');
      await prefs.remove('selected_student_id');
      await prefs.remove('selected_student_name');
      await prefs.remove('selected_student_class');
      UserPermissionService.clearCache();
      TermService().clearCache();
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/school-login', (route) => false);
      }
    } catch (e) {
      debugPrint('Çıkış hatası: $e');
    }
  }

  String _getSubtitleText() {
    final name = _selectedStudentName.trim().toUpperCase();
    final num = _studentNumber.trim();
    final cls = _selectedStudentClass.trim();
    
    if (name.isNotEmpty) {
      String result = '';
      if (num.isNotEmpty) result += '$num ';
      result += name;
      if (cls.isNotEmpty) result += ' ($cls)';
      return result;
    }
    return 'Öğrenci Paneli';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: EduKnLoader(size: 80),
        ),
      );
    }

    final pages = [
      ParentHaberlesmeScreen(institutionId: widget.institutionId),
      ParentDashboardTab(institutionId: widget.institutionId),
      ParentOperationsScreen(
        institutionId: widget.institutionId,
        studentId: _selectedStudentId,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        flexibleSpace: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const EduKnLogo(iconSize: 32, type: EduKnLogoType.noSlogan),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: _myChildren.length > 1 ? _showStudentSwitchModal : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Öğrenci İşlemleri',
                                style: GoogleFonts.inter(
                                  color: Colors.indigo.shade900,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_myChildren.length > 1) ...[
                                const SizedBox(width: 4),
                                Icon(Icons.arrow_drop_down_rounded, color: Colors.indigo.shade900, size: 22),
                              ],
                            ],
                          ),
                          Text(
                            _getSubtitleText(),
                            style: GoogleFonts.inter(
                              color: Colors.indigo.shade400,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            offset: const Offset(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (value) {
              if (value == 'profile') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (ctx) => const ProfileSettingsScreen()),
                );
              } else if (value == 'logout') {
                _logout();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person_outline, size: 20, color: Colors.indigo),
                    SizedBox(width: 12),
                    Text('Profilim'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 20, color: Colors.red),
                    SizedBox(width: 12),
                    Text('Çıkış Yap', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: CircleAvatar(
                radius: 17,
                backgroundColor: Colors.indigo.shade50,
                child: Icon(Icons.person, color: Colors.indigo.shade800, size: 18),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StylishBottomNav(
            currentIndex: _currentIndex,
            badgeCounts: const {0: 0},
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
                    InkWell(onTap: () {}, child: Text('Destek', style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 10, fontWeight: FontWeight.w500))),
                    const SizedBox(width: 16),
                    InkWell(onTap: () {}, child: Text('Gizlilik', style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 10, fontWeight: FontWeight.w500))),
                    const SizedBox(width: 16),
                    InkWell(onTap: () {}, child: Text('Şartlar', style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 10, fontWeight: FontWeight.w500))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
