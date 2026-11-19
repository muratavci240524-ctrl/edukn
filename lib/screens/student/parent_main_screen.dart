import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/daily_report_service.dart';
import '../../services/term_service.dart';
import '../../services/user_permission_service.dart';
import '../../widgets/edukn_app_bar.dart';
import '../../widgets/stylish_bottom_nav.dart';
import '../../widgets/web_qr_login_scanner_sheet.dart';
import '../school/profile_settings_screen.dart';
import 'parent_dashboard_tab.dart';
import 'parent_haberlesme_screen.dart';
import 'parent_operations_screen.dart';
import 'student_and_parent_tools_screen.dart';

class ParentMainScreen extends StatefulWidget {
  final String institutionId;

  const ParentMainScreen({Key? key, required this.institutionId})
    : super(key: key);

  @override
  State<ParentMainScreen> createState() => _ParentMainScreenState();
}

class _ParentMainScreenState extends State<ParentMainScreen> {
  int _selectedIndex = 1; // Varsayılan: Ana Sayfa (Bildirimler & Takvim)

  String? _selectedStudentId;
  Map<String, dynamic>? _selectedStudentData;
  List<Map<String, dynamic>> _myChildren = [];
  bool _isParentUser = false;
  bool _isLoadingChildren = true;
  bool _dailyReportEnabled = false;
  Map<String, dynamic>? _currentUserData;

  @override
  void initState() {
    super.initState();
    _loadSelectedStudentAndChildren();
  }

  Future<void> _loadSelectedStudentAndChildren() async {
    setState(() => _isLoadingChildren = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoadingChildren = false);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final savedKey = 'selected_student_id_${user.uid}';
      final savedId = prefs.getString(savedKey);
      final instUpper = widget.institutionId.toUpperCase();

      // 1. Önce aktif kullanıcı dokümanını çözümle (Öğrenci mi, Veli mi?)
      Map<String, dynamic>? uData = await UserPermissionService.loadUserData();
      if (uData == null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          uData = {'id': userDoc.id, ...userDoc.data()!};
        }
      }
      _currentUserData = uData;

      final role = (uData?['role'] ?? '').toString().toLowerCase().trim();
      final activePortal = prefs.getString('active_portal') ?? '';
      _isParentUser =
          role == 'parent' || role == 'veli' || activePortal == 'parent';

      if (!_isParentUser) {
        // ── ÖĞRENCİ GİRİŞİ: Yalnızca kendi öğrenci kaydını yükle ──
        Map<String, dynamic>? stDocData;
        final directStudentId =
            (uData?['studentId'] ?? uData?['selectedStudentId'])?.toString();
        if (directStudentId != null && directStudentId.isNotEmpty) {
          final sDoc = await FirebaseFirestore.instance
              .collection('students')
              .doc(directStudentId)
              .get();
          if (sDoc.exists) stDocData = {'id': sDoc.id, ...sDoc.data()!};
        }

        if (stDocData == null) {
          final emailPrefix =
              (uData?['username'] ?? (user.email ?? '').split('@').first)
                  .toString()
                  .trim();
          if (emailPrefix.isNotEmpty) {
            for (final field in [
              'username',
              'tcNo',
              'studentNo',
              'studentNumber',
            ]) {
              final q = await FirebaseFirestore.instance
                  .collection('students')
                  .where('institutionId', isEqualTo: instUpper)
                  .where(field, isEqualTo: emailPrefix)
                  .limit(1)
                  .get();
              if (q.docs.isNotEmpty) {
                stDocData = {'id': q.docs.first.id, ...q.docs.first.data()};
                break;
              }
            }
          }
        }

        if (stDocData != null && mounted) {
          await prefs.setString(savedKey, stDocData['id'].toString());
          await _refreshDailyReportFlag(stDocData);
          setState(() {
            _selectedStudentId = stDocData!['id'].toString();
            _selectedStudentData = stDocData;
            _myChildren = [stDocData];
            _isLoadingChildren = false;
          });
          return;
        }
      } else {
        // ── VELİ GİRİŞİ: Velinin tüm çocuklarını bul ──
        final List<Map<String, dynamic>> childrenList = [];
        final List<String> childIds = [
          ...List<String>.from(uData?['childIds'] ?? []),
          ...List<String>.from(uData?['studentIds'] ?? []),
        ];
        final singleStId = uData?['studentId']?.toString();
        if (singleStId != null &&
            singleStId.isNotEmpty &&
            !childIds.contains(singleStId)) {
          childIds.add(singleStId);
        }

        // Ayrıca parents koleksiyonunda kayıtlı studentIds var mı kontrol et
        final parentTc =
            (uData?['tcNo'] ??
                    uData?['username'] ??
                    (user.email ?? '').split('@').first)
                .toString()
                .trim();
        if (parentTc.isNotEmpty) {
          try {
            var pq = await FirebaseFirestore.instance
                .collection('parents')
                .where('institutionId', isEqualTo: instUpper)
                .where('username', isEqualTo: parentTc.toLowerCase())
                .limit(2)
                .get();
            if (pq.docs.isEmpty) {
              pq = await FirebaseFirestore.instance
                  .collection('parents')
                  .where('institutionId', isEqualTo: instUpper)
                  .where('tcNo', isEqualTo: parentTc)
                  .limit(2)
                  .get();
            }
            for (final pd in pq.docs) {
              final pData = pd.data();
              for (final id in List<String>.from(
                pData['studentIds'] ?? pData['childIds'] ?? [],
              )) {
                if (id.isNotEmpty && !childIds.contains(id)) childIds.add(id);
              }
              final pSingle = pData['studentId']?.toString();
              if (pSingle != null &&
                  pSingle.isNotEmpty &&
                  !childIds.contains(pSingle)) {
                childIds.add(pSingle);
              }
            }
          } catch (_) {}
        }

        for (final cid in childIds) {
          final cDoc = await FirebaseFirestore.instance
              .collection('students')
              .doc(cid)
              .get();
          if (cDoc.exists) {
            childrenList.add({'id': cDoc.id, ...cDoc.data()!});
          }
        }

        if (childrenList.isEmpty && parentTc.isNotEmpty) {
          var q = await FirebaseFirestore.instance
              .collection('students')
              .where('institutionId', isEqualTo: instUpper)
              .where('parentIds', arrayContains: user.uid)
              .get();
          if (q.docs.isEmpty) {
            q = await FirebaseFirestore.instance
                .collection('students')
                .where('institutionId', isEqualTo: instUpper)
                .where('parentTc', isEqualTo: parentTc)
                .get();
          }
          if (q.docs.isEmpty) {
            final allSnap = await FirebaseFirestore.instance
                .collection('students')
                .where('institutionId', isEqualTo: instUpper)
                .get();
            final pPhone = (uData?['phone'] ?? '').toString().replaceAll(
              RegExp(r'\D'),
              '',
            );
            for (final doc in allSnap.docs) {
              final sData = doc.data();
              final parents = sData['parents'] as List<dynamic>? ?? [];
              bool matched = false;
              for (final p in parents) {
                if (p is Map) {
                  final tc = (p['tcNo'] ?? '').toString().trim();
                  final ph = (p['phone'] ?? '').toString().replaceAll(
                    RegExp(r'\D'),
                    '',
                  );
                  if ((tc.isNotEmpty && tc == parentTc) ||
                      (pPhone.length >= 10 &&
                          ph.isNotEmpty &&
                          ph.endsWith(pPhone.substring(pPhone.length - 10)))) {
                    matched = true;
                    break;
                  }
                }
              }
              if (matched) {
                childrenList.add({'id': doc.id, ...sData});
              }
            }
          } else {
            for (final doc in q.docs) {
              childrenList.add({'id': doc.id, ...doc.data()});
            }
          }
        }

        if (childrenList.isNotEmpty && mounted) {
          Map<String, dynamic> chosen = childrenList.first;
          if (savedId != null && savedId.isNotEmpty) {
            final found = childrenList.where((c) => c['id'] == savedId);
            if (found.isNotEmpty) chosen = found.first;
          }
          await prefs.setString(savedKey, chosen['id'].toString());
          await _refreshDailyReportFlag(chosen);
          setState(() {
            _myChildren = childrenList;
            _selectedStudentId = chosen['id'].toString();
            _selectedStudentData = chosen;
            _isLoadingChildren = false;
          });
          return;
        }
      }

      if (mounted) setState(() => _isLoadingChildren = false);
    } catch (e) {
      debugPrint('Error loading selected student: $e');
      if (mounted) setState(() => _isLoadingChildren = false);
    }
  }

  Future<void> _refreshDailyReportFlag(Map<String, dynamic>? st) async {
    try {
      final instId = widget.institutionId.toUpperCase();
      if (instId.isEmpty) return;
      final service = DailyReportService();
      final schoolDocId = await service.resolveSchoolDocId(instId);
      if (schoolDocId.isEmpty) return;
      final cfg = await service.loadConfig(schoolDocId);
      final stId = (st?['schoolTypeId'] ?? '').toString();
      _dailyReportEnabled = cfg.isEnabledForSchoolType(stId);
    } catch (_) {}
  }

  Future<void> _selectChild(Map<String, dynamic> child) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'selected_student_id_${user.uid}',
        child['id'].toString(),
      );
    }
    await _refreshDailyReportFlag(child);
    if (mounted) {
      setState(() {
        _selectedStudentId = child['id'].toString();
        _selectedStudentData = child;
      });
    }
  }

  // ─── ŞİFRE GÜNCELLEME MODALI (Öğretmen ile Birebir Uyumlu + Senkronize) ──

  Future<void> _showPasswordUpdateDialog() async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscureCur = true;
    bool obscureNew = true;
    bool saving = false;
    String? errorMsg;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.lock_reset_rounded,
                    color: Color(0xFF4F46E5),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Şifre Güncelle',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Hesap güvenliğiniz için mevcut şifrenizi doğrulayarak yeni şifrenizi belirleyin.',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: currentCtrl,
                    obscureText: obscureCur,
                    decoration: InputDecoration(
                      labelText: 'Mevcut Şifre',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureCur
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () =>
                            setDialogState(() => obscureCur = !obscureCur),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newCtrl,
                    obscureText: obscureNew,
                    decoration: InputDecoration(
                      labelText: 'Yeni Şifre (En az 6 karakter)',
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureNew
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () =>
                            setDialogState(() => obscureNew = !obscureNew),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmCtrl,
                    obscureText: obscureNew,
                    decoration: InputDecoration(
                      labelText: 'Yeni Şifre (Tekrar)',
                      prefixIcon: const Icon(
                        Icons.check_circle_outline_rounded,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  if (errorMsg != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        errorMsg!,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFDC2626),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: const Text('İptal'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                ),
                onPressed: saving
                    ? null
                    : () async {
                        final cur = currentCtrl.text.trim();
                        final nw = newCtrl.text.trim();
                        final cf = confirmCtrl.text.trim();
                        if (cur.isEmpty) {
                          setDialogState(
                            () => errorMsg = 'Lütfen mevcut şifrenizi girin.',
                          );
                          return;
                        }
                        if (nw.length < 6) {
                          setDialogState(
                            () => errorMsg =
                                'Yeni şifre en az 6 karakter olmalıdır.',
                          );
                          return;
                        }
                        if (nw != cf) {
                          setDialogState(
                            () => errorMsg = 'Yeni şifreler eşleşmiyor.',
                          );
                          return;
                        }

                        setDialogState(() {
                          saving = true;
                          errorMsg = null;
                        });

                        try {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null || user.email == null) {
                            throw Exception('Oturum bilgisi bulunamadı.');
                          }
                          final cred = EmailAuthProvider.credential(
                            email: user.email!,
                            password: cur,
                          );
                          await user.reauthenticateWithCredential(cred);
                          await user.updatePassword(nw);

                          // Firestore senkronizasyonu (users + students / parents)
                          final instUpper = widget.institutionId.toUpperCase();
                          try {
                            final uDocId = (_currentUserData?['id'] ?? user.uid)
                                .toString();
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(uDocId)
                                .set({
                                  'password': nw,
                                  'passwordStatus': 'degistirildi',
                                  'updatedAt': FieldValue.serverTimestamp(),
                                }, SetOptions(merge: true));

                            if (!_isParentUser &&
                                _selectedStudentId != null &&
                                _selectedStudentId!.isNotEmpty) {
                              await FirebaseFirestore.instance
                                  .collection('students')
                                  .doc(_selectedStudentId)
                                  .set({
                                    'password': nw,
                                    'updatedAt': FieldValue.serverTimestamp(),
                                  }, SetOptions(merge: true));
                            } else if (_isParentUser) {
                              final uname =
                                  (_currentUserData?['username'] ??
                                          (user.email ?? '').split('@').first)
                                      .toString()
                                      .trim();
                              if (uname.isNotEmpty) {
                                final pq = await FirebaseFirestore.instance
                                    .collection('parents')
                                    .where(
                                      'institutionId',
                                      isEqualTo: instUpper,
                                    )
                                    .where('username', isEqualTo: uname)
                                    .limit(3)
                                    .get();
                                for (final d in pq.docs) {
                                  await d.reference.set({
                                    'password': nw,
                                    'updatedAt': FieldValue.serverTimestamp(),
                                  }, SetOptions(merge: true));
                                }
                              }
                            }
                          } catch (_) {}

                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  '✅ Şifreniz başarıyla güncellendi!',
                                ),
                                backgroundColor: Color(0xFF059669),
                              ),
                            );
                          }
                        } on FirebaseAuthException catch (e) {
                          setDialogState(() {
                            saving = false;
                            if (e.code == 'wrong-password' ||
                                e.code == 'invalid-credential') {
                              errorMsg = 'Mevcut şifreniz hatalı.';
                            } else {
                              errorMsg = 'Şifre güncellenemedi: ${e.message}';
                            }
                          });
                        } catch (e) {
                          setDialogState(() {
                            saving = false;
                            errorMsg = 'Hata: $e';
                          });
                        }
                      },
                icon: saving
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded, size: 17),
                label: const Text('Şifreyi Güncelle'),
              ),
            ],
          );
        },
      ),
    );

    currentCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Çıkış Yap'),
        content: const Text(
          'Hesabınızdan çıkış yapmak istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_portal');
      UserPermissionService.clearCache();
      TermService().clearCache();
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/school-login',
          (route) => false,
        );
      }
    }
  }

  void _showStudentSwitcherSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'Öğrenci Seçin',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ..._myChildren.map((child) {
                final name =
                    child['fullName'] ??
                    '${child['name'] ?? ''} ${child['surname'] ?? ''}'.trim();
                final className = child['className'] ?? '';
                final isSelected = child['id'] == _selectedStudentId;
                return ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  tileColor: isSelected ? Colors.indigo.shade50 : null,
                  leading: CircleAvatar(
                    backgroundColor: isSelected
                        ? Colors.indigo
                        : Colors.blueGrey.shade100,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'Ö',
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : Colors.blueGrey.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    name,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: isSelected
                          ? Colors.indigo.shade900
                          : Colors.black87,
                    ),
                  ),
                  subtitle: className.toString().isNotEmpty
                      ? Text('Sınıf: $className')
                      : null,
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Colors.indigo)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _selectChild(child);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  String get _appBarTitle {
    switch (_selectedIndex) {
      case 0:
        return 'Haberleşme Merkezi';
      case 1:
        return 'Bildirimler ve Takvim';
      case 2:
        return _isParentUser
            ? 'Veli İşlemleri ve Araçlar'
            : 'Öğrenci İşlemleri ve Araçlar';
      default:
        return _isParentUser ? 'Veli Paneli' : 'Öğrenci Paneli';
    }
  }

  String get _appBarStudentSubtitle {
    if (_selectedStudentData == null) {
      return _isParentUser ? 'Veli Portalı' : 'Öğrenci Portalı';
    }
    final name =
        (_selectedStudentData!['fullName'] ??
                '${_selectedStudentData!['name'] ?? ''} ${_selectedStudentData!['surname'] ?? ''}')
            .toString()
            .trim();
    final className = (_selectedStudentData!['className'] ?? '')
        .toString()
        .trim();
    final studentNo =
        (_selectedStudentData!['studentNo'] ??
                _selectedStudentData!['studentNumber'] ??
                _selectedStudentData!['no'] ??
                '')
            .toString()
            .trim();

    final parts = <String>[
      if (_isParentUser) 'Veli Paneli',
      if (studentNo.isNotEmpty) studentNo,
      if (name.isNotEmpty) name,
      if (className.isNotEmpty) '($className)',
    ];
    return parts.join(' • ');
  }

  Widget _buildProfileMenuButton() {
    return PopupMenuButton<String>(
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      onSelected: (val) {
        if (val == 'profile') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()),
          );
        } else if (val == 'password') {
          _showPasswordUpdateDialog();
        } else if (val == 'tools' && _selectedStudentData != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StudentAndParentToolsScreen(
                institutionId: widget.institutionId.toUpperCase(),
                studentId: _selectedStudentId ?? '',
                studentData: _selectedStudentData!,
                isParentUser: _isParentUser,
                dailyReportEnabled: _dailyReportEnabled,
              ),
            ),
          );
        } else if (val == 'switch_student') {
          _showStudentSwitcherSheet();
        } else if (val == 'web_qr_login') {
          WebQrLoginScannerSheet.show(context);
        } else if (val == 'logout') {
          _logout();
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          value: 'profile',
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.person_outline_rounded,
                  color: Colors.indigo.shade700,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Profilim',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Kişisel Bilgiler & Bildirimler',
                    style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                  ),
                ],
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'password',
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.lock_reset_rounded,
                  color: Colors.teal.shade700,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Şifre Güncelle',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Giriş şifrenizi değiştirin',
                    style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_selectedStudentData != null)
          PopupMenuItem<String>(
            value: 'tools',
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.handyman_rounded,
                    color: Colors.purple.shade700,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Araçlar Merkezi',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Online İşlemler, Yemek & Analiz',
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (_isParentUser && _myChildren.length > 1) ...[
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'switch_student',
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.swap_horiz_rounded,
                    color: Colors.orange.shade700,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Öğrenci Değiştir',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'web_qr_login',
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.devices_rounded,
                  color: Colors.indigo.shade700,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Web\'de QR ile Oturum Aç',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Bilgisayarda QR okutarak giriş yap',
                    style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                  ),
                ],
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.logout_rounded,
                  color: Colors.red.shade600,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Çıkış Yap',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade700,
                ),
              ),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.only(right: 12, left: 4),
        child: CircleAvatar(
          radius: 17,
          backgroundColor: Colors.indigo.shade50,
          child: const Icon(Icons.person, color: Colors.indigo, size: 18),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      ParentHaberlesmeScreen(
        institutionId: widget.institutionId,
        schoolTypeId: _selectedStudentData?['schoolTypeId']?.toString(),
        schoolTypeName: _selectedStudentData?['schoolTypeName']?.toString(),
      ),
      ParentDashboardTab(
        institutionId: widget.institutionId,
        studentId: _selectedStudentId,
        studentData: _selectedStudentData,
        isParentUser: _isParentUser,
        dailyReportEnabled: _dailyReportEnabled,
      ),
      ParentOperationsScreen(
        institutionId: widget.institutionId,
        selectedStudentId: _selectedStudentId,
        selectedStudentData: _selectedStudentData,
        isParentUser: _isParentUser,
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      // TÜM SEKMELERDE TEK, VARSAYILAN OKUL LOGOLU EDUKN APPBAR!
      appBar: EduknAppBar(
        institutionId: widget.institutionId,
        title: _appBarTitle,
        subtitle: _appBarStudentSubtitle,
        showBackButton: false,
        actions: [
          if (_isParentUser && _myChildren.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: TextButton.icon(
                onPressed: _showStudentSwitcherSheet,
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFEEF2FF),
                  foregroundColor: const Color(0xFF4338CA),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                label: const Text(
                  'Öğrenci Değiştir',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          if (_selectedStudentData != null)
            IconButton(
              tooltip: 'Araçlar Merkezi',
              icon: const Icon(
                Icons.handyman_rounded,
                color: Color(0xFF4F46E5),
                size: 21,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudentAndParentToolsScreen(
                      institutionId: widget.institutionId.toUpperCase(),
                      studentId: _selectedStudentId ?? '',
                      studentData: _selectedStudentData!,
                      isParentUser: _isParentUser,
                      dailyReportEnabled: _dailyReportEnabled,
                    ),
                  ),
                );
              },
            ),
          _buildProfileMenuButton(),
        ],
      ),
      body: _isLoadingChildren
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(index: _selectedIndex, children: screens),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StylishBottomNav(
            currentIndex: _selectedIndex,
            badgeCounts: const {0: 0},
            onTap: (index) => setState(() => _selectedIndex = index),
          ),
          Container(
            color: Colors.white,
            width: double.infinity,
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: 4,
              bottom: 2,
            ),
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
                    InkWell(
                      onTap: () {},
                      child: Text(
                        'Destek',
                        style: TextStyle(
                          color: Colors.blueGrey.shade400,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    InkWell(
                      onTap: () {},
                      child: Text(
                        'Gizlilik',
                        style: TextStyle(
                          color: Colors.blueGrey.shade400,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    InkWell(
                      onTap: () {},
                      child: Text(
                        'Şartlar',
                        style: TextStyle(
                          color: Colors.blueGrey.shade400,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
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
