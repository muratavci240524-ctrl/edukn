import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/edukn_logo.dart';
import '../../widgets/web_image_renderer.dart';
import '../teacher/teacher_main_screen.dart';
import 'parent_student_selection_screen.dart';
import '../../services/notification_service.dart';
import '../../services/user_permission_service.dart';
import '../../services/term_service.dart';
import 'school_types/school_type_detail_screen.dart';

class SchoolLoginScreen extends StatefulWidget {
  const SchoolLoginScreen({Key? key}) : super(key: key);

  @override
  State<SchoolLoginScreen> createState() => _SchoolLoginScreenState();
}

class _SchoolLoginScreenState extends State<SchoolLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _institutionController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _kvkkAccepted = false;
  bool _checkingSession = true; // Oturum kontrol ediliyor mu?

  @override
  void initState() {
    super.initState();
    _clearStaleSessionData();
    _checkExistingSession();
  }

  Future<void> _clearStaleSessionData() async {
    final prefs = await SharedPreferences.getInstance();
    // Only clear active_portal if we don't have an active Firebase session.
    // However, if we are at the login screen, we should clear it so that
    // a new manual login starts fresh.
    if (FirebaseAuth.instance.currentUser == null) {
      await prefs.remove('active_portal');
      UserPermissionService.clearCache();
      TermService().clearCache();
    }
  }

  /// Mevcut Firebase Auth oturumunu kontrol et.
  /// Kullanıcı daha önce giriş yaptıysa (ve çıkış yapmadıysa) direkt dashboard'a yönlendir.
  /// ANCAK: URL public bir sayfaysa (/yoklama-al-* veya /sinav-basvuru) o sayfaya yönlendir.
  Future<void> _checkExistingSession() async {
    try {
      // Mevcut URL public bir sayfa mı? (yoklama-al veya sinav-basvuru)
      // Öyleyse login ekranı değil, direkt o sayfa açılmalı.
      if (kIsWeb) {
        final currentUri = Uri.base;
        final currentPath = currentUri.path;

        if (currentPath.startsWith('/yoklama-al-')) {
          if (!mounted) return;
          // Login ekranı değil, yoklama ekranına yönlendir
          Navigator.pushReplacementNamed(context, currentPath);
          return;
        }
        if (currentPath.startsWith('/sinav-basvuru')) {
          if (!mounted) return;
          final examId = currentUri.queryParameters['examId'];
          final route = examId != null
              ? '/sinav-basvuru?examId=$examId'
              : '/sinav-basvuru';
          Navigator.pushReplacementNamed(context, route);
          return;
        }
      }

      // Firebase Auth oturumu var mı?
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null && kIsWeb) {
        // Web'de yüklenmesi vakit alabilir, çok kısa bekle
        await Future.delayed(const Duration(milliseconds: 1000));
        user = FirebaseAuth.instance.currentUser;
      }
      
      if (user != null) {
        print('✅ Mevcut oturum bulundu: ${user.email}');
        // Token'ı yenile (geçerliliği kontrol et)
        await user.reload();
        if (!mounted) return;
        
        // Süper Admin yönlendirmesi
        if (user.email?.toLowerCase() == 'superadmin@edukn.com') {
          Navigator.pushReplacementNamed(context, '/admin-dashboard');
          return;
        }
        
        // Direkt dashboard'a git
        Navigator.pushReplacementNamed(context, '/school-dashboard');
        return;
      }
    } catch (e) {
      // Token süresi dolmuş veya hesap silinmiş — giriş ekranını göster
      print('⚠️ Oturum geçersiz, giriş ekranı gösteriliyor: $e');
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _checkingSession = false);
    }
  }

  // ─── LOGIN LOGIC ──────────────────────────────────────────────────────────

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_kvkkAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen KVKK Aydınlatma Metni\'ni kabul edin.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final username = _usernameController.text.trim().toLowerCase().replaceAll(' ', '');
    final password = _passwordController.text.trim();
    final institutionId = _institutionController.text.trim().toUpperCase().replaceAll(' ', '');

    try {
      // Eğer girilen kullanıcı adı zaten bir email ise (gerçek mail ile kayıt olunmuşsa) onu kullan
      // Değilse kurumsal formatta oluştur
      String email;
      if (username.contains('@') && username.contains('.')) {
        email = username;
      } else {
        email = '$username@$institutionId.edukn';
      }

      // 1. Giriş Bilgilerini Hazırla
      print('🔍 Giriş denemesi: User=$username, Inst=$institutionId');
      String emailToUse;
      if (username.contains('@')) {
        emailToUse = username;
        print('📧 Email formatı algılandı: $emailToUse. Firestore araması yapılıyor...');
        try {
          final results = await Future.wait([
            FirebaseFirestore.instance
                .collection('users')
                .where('institutionId', isEqualTo: institutionId)
                .where('email', isEqualTo: username)
                .limit(1)
                .get(),
            FirebaseFirestore.instance
                .collection('users')
                .where('institutionId', isEqualTo: institutionId)
                .where('corporateEmail', isEqualTo: username)
                .limit(1)
                .get(),
            FirebaseFirestore.instance
                .collection('users')
                .where('institutionId', isEqualTo: institutionId)
                .where('personalEmail', isEqualTo: username)
                .limit(1)
                .get(),
          ]);

          DocumentSnapshot? matchedDoc;
          for (final snap in results) {
            if (snap.docs.isNotEmpty) {
              matchedDoc = snap.docs.first;
              break;
            }
          }

          if (matchedDoc != null) {
            final dbAuthEmail = matchedDoc.get('email') as String?;
            if (dbAuthEmail != null && dbAuthEmail.isNotEmpty) {
              emailToUse = dbAuthEmail;
              print('✅ E-posta eşleşmesi bulundu! Kullanılacak Auth e-postası: $emailToUse');
            }
          }
        } catch (e) {
          print('❌ E-posta Firestore arama hatası: $e');
        }
      } else {
        // Önce Firestore'dan bu kullanıcı adının gerçek mailini bulmayı dene
        print('🔍 Firestore\'da kullanıcı adı aranıyor: $username');
        try {
          final userLookup = await FirebaseFirestore.instance
              .collection('users')
              .where('institutionId', isEqualTo: institutionId)
              .where('username', isEqualTo: username)
              .limit(1)
              .get();
          
          if (userLookup.docs.isNotEmpty) {
            emailToUse = userLookup.docs.first.get('email') ?? '$username@$institutionId.edukn';
            print('✅ Kullanıcı bulundu, kayıtlı email: $emailToUse');
          } else {
            emailToUse = '$username@$institutionId.edukn';
            print('⚠️ Kullanıcı Firestore\'da bulunamadı, varsayılan email denenecek: $emailToUse');
          }
        } catch (e) {
          print('❌ Firestore arama hatası: $e');
          emailToUse = '$username@$institutionId.edukn';
        }
      }

      // Okul kontrolü
      final schoolQuery = await FirebaseFirestore.instance
          .collection('schools')
          .where('institutionId', isEqualTo: institutionId)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 15), onTimeout: () => throw 'Okul bilgileri alınırken zaman aşımı oluştu.');

      if (schoolQuery.docs.isEmpty) throw 'Bu kurum ID ile kayıtlı okul bulunamadı!';

      final schoolData = schoolQuery.docs.first.data();
      if (schoolData['isActive'] != true) throw 'Bu okul şu an pasif durumda!';

      // 2. Firebase Auth ile Giriş Yap
      // Strateji: Firestore'daki email → başarısız olursa generate format → temp şifre ile de dene
      print('🔐 Firebase Auth denemesi (1): $emailToUse');
      final generatedEmail = '$username@$institutionId.edukn'.toLowerCase();
      UserCredential? userCredential;
      String? successEmail; // hangi email ile giriş başarılı oldu

      // Tüm deneme kombinasyonları
      // [email, password] şeklinde
      String? tempPass;
      try {
        final tempQ = await FirebaseFirestore.instance
            .collection('users')
            .where('institutionId', isEqualTo: institutionId)
            .where('username', isEqualTo: username)
            .limit(1)
            .get();
        if (tempQ.docs.isNotEmpty) {
          tempPass = tempQ.docs.first.data()['_tempPassword'] as String?;
        }
      } catch (_) {}

      final emailsToTry = <String>{emailToUse, generatedEmail}.toList();
      final passwordsToTry = <String>[password, if (tempPass != null && tempPass.isNotEmpty) tempPass];

      bool loginSuccess = false;
      for (final tryEmail in emailsToTry) {
        for (final tryPass in passwordsToTry) {
          if (loginSuccess) break;
          try {
            print('🔐 Deneniyor: $tryEmail / ${tryPass.replaceAll(RegExp(r'.'), '*')}');
            userCredential = await FirebaseAuth.instance
                .signInWithEmailAndPassword(email: tryEmail, password: tryPass)
                .timeout(const Duration(seconds: 15));
            print('✅ Giriş başarılı: $tryEmail');
            successEmail = tryEmail;
            loginSuccess = true;

            // Temp şifre kullanıldıysa Firestore'dan temizle
            if (tryPass == tempPass) {
              try {
                final tQ = await FirebaseFirestore.instance
                    .collection('users')
                    .where('institutionId', isEqualTo: institutionId)
                    .where('username', isEqualTo: username)
                    .limit(1)
                    .get();
                if (tQ.docs.isNotEmpty) {
                  await tQ.docs.first.reference.update({'_tempPassword': FieldValue.delete()});
                  print('🧹 _tempPassword temizlendi');
                }
              } catch (_) {}
            }

            // Eğer generate email ile başarılı olduysa, Firestore'daki email'i güncelle
            if (successEmail == generatedEmail && emailToUse != generatedEmail) {
              try {
                final uQ = await FirebaseFirestore.instance
                    .collection('users')
                    .where('institutionId', isEqualTo: institutionId)
                    .where('username', isEqualTo: username)
                    .limit(1)
                    .get();
                if (uQ.docs.isNotEmpty) {
                  await uQ.docs.first.reference.update({'email': generatedEmail});
                  print('🔄 Firestore email güncellendi: $generatedEmail');
                }
              } catch (_) {}
            }
          } on FirebaseAuthException catch (authErr) {
            print('⚠️ Başarısız: $tryEmail [${authErr.code}]');
            if (authErr.code == 'too-many-requests') {
              throw 'Çok fazla hatalı deneme yaptınız. Lütfen daha sonra tekrar deneyin.';
            }
            if (authErr.code == 'user-disabled') {
              throw 'Bu hesap devre dışı bırakılmış.';
            }
          } catch (otherErr) {
            print('⚠️ Diğer hata: $otherErr');
          }
        }
        if (loginSuccess) break;
      }

      if (!loginSuccess) {
        throw 'Kullanıcı adı veya şifre hatalı.';
      }

      final uid = userCredential?.user?.uid;
      if (uid == null) throw 'Kullanıcı kimliği alınamadı.';

      // 🔔 FCM Token kaydet (bildirim sistemi için)
      NotificationService().initialize(uid: uid).catchError((e) {
        print('⚠️ FCM init hatası (kritik değil): $e');
      });

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get()
          .timeout(const Duration(seconds: 15), onTimeout: () => throw 'Kullanıcı verisi alınırken zaman aşımı oluştu.');

      Map<String, dynamic>? userData;
      if (userDoc.exists) {
        userData = userDoc.data();
      } else {
        final fallbackQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('institutionId', isEqualTo: institutionId)
            .where('email', isEqualTo: successEmail)
            .limit(1)
            .get();
        if (fallbackQuery.docs.isNotEmpty) userData = fallbackQuery.docs.first.data();
      }

      if (userData == null && schoolData['adminUsername'] != username) {
        await FirebaseAuth.instance.signOut();
        throw 'Kullanıcı kaydı bulunamadı!';
      }

      if (userData != null && userData['isActive'] != true) {
        await FirebaseAuth.instance.signOut();
        throw 'Hesabınız pasif durumda!';
      }

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => WillPopScope(
            onWillPop: () async => false,
            child: const Center(child: EduKnLoader(size: 100)),
          ),
        );

        await Future.delayed(const Duration(milliseconds: 2000));
        if (!mounted) return;
        Navigator.pop(context);

        if (userData != null) {
          await _routeUserAfterLoadingData(userData, institutionId);
        } else {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('active_portal', 'manager');
          Navigator.pushReplacementNamed(context, '/school-dashboard');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _routeUserAfterLoadingData(Map<String, dynamic>? userData, String institutionId) async {
    if (userData == null) {
      Navigator.pushReplacementNamed(context, '/school-dashboard');
      return;
    }

    final role = userData['role']?.toString().toLowerCase() ?? '';
    final tcNo = userData['tcNo'] ?? userData['tcKimlik'] ?? '';

    // Check parent eligibility
    bool hasParentRole = role == 'parent' || role == 'veli';
    List<Map<String, dynamic>> students = [];
    if (tcNo.toString().isNotEmpty) {
      try {
        final studentsQuery = await FirebaseFirestore.instance
            .collection('students')
            .where('institutionId', isEqualTo: institutionId)
            .where('parentTcNos', arrayContains: tcNo.toString())
            .get();
        if (studentsQuery.docs.isNotEmpty) {
          hasParentRole = true;
          students = studentsQuery.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
        }
      } catch (e) {
        print('❌ Redirection parent check error: $e');
      }
    }

    // Identify portals
    final eligiblePortals = <Map<String, dynamic>>[];

    // 1. Yönetici / Personel Portalı
    bool isManager = role.contains('genel_mudur') ||
        role.contains('genel müdür') ||
        role.contains('genel mudur') ||
        role.contains('mudur') ||
        role.contains('müdür') ||
        role.contains('admin') ||
        role.contains('hr') ||
        role.contains('muhasebe') ||
        role.contains('satin_alma') ||
        role.contains('depo') ||
        role.contains('destek_hizmetleri') ||
        role.contains('personel') ||
        role.contains('staff') ||
        role.contains('kurucu') ||
        role.contains('yönetici') ||
        role.contains('yonetici');

    bool isStrictlyTeacher = (role.contains('ogretmen') || role.contains('teacher') || role.contains('öğretmen')) && !isManager;
    bool isStrictlyParent = role == 'parent' || role == 'veli';

    if (isManager || (!isStrictlyTeacher && !isStrictlyParent && role.isNotEmpty)) {
      eligiblePortals.add({
        'id': 'manager',
        'title': 'Yönetici / Personel Portalı',
        'subtitle': 'Kurum genel yönetimi ve modüller',
        'icon': Icons.admin_panel_settings_rounded,
        'color': Colors.indigo,
      });
    }

    // 2. Öğretmen Portalı
    if (role.contains('ogretmen') || role.contains('teacher') || role.contains('öğretmen')) {
      eligiblePortals.add({
        'id': 'teacher',
        'title': 'Öğretmen Portalı',
        'subtitle': 'Sınıf, ders ve öğrenci işlemleri',
        'icon': Icons.school_rounded,
        'color': Colors.orange,
      });
    }

    // 3. Veli / Öğrenci Portalı
    if (hasParentRole || isStrictlyParent) {
      eligiblePortals.add({
        'id': 'parent',
        'title': 'Veli / Öğrenci Portalı',
        'subtitle': 'Öğrenci takibi ve bilgilendirme',
        'icon': Icons.family_restroom_rounded,
        'color': Colors.green,
      });
    }

    if (eligiblePortals.length > 1) {
      if (mounted) {
        setState(() {
          _checkingSession = false;
          _isLoading = false;
        });
        _showPortalSelectionDialog(eligiblePortals, userData, institutionId, students);
      }
    } else if (eligiblePortals.length == 1) {
      final portal = eligiblePortals.first['id'];
      _navigateToPortal(portal, userData, institutionId, students);
    } else {
      Navigator.pushReplacementNamed(context, '/school-dashboard');
    }
  }

  void _showPortalSelectionDialog(
    List<Map<String, dynamic>> portals,
    Map<String, dynamic> userData,
    String institutionId,
    List<Map<String, dynamic>> students,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return WillPopScope(
          onWillPop: () async => false,
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            backgroundColor: Colors.white,
            elevation: 16,
            child: Container(
              padding: const EdgeInsets.all(28),
              constraints: const BoxConstraints(maxWidth: 450),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4C59BC).withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.account_tree_rounded,
                      color: Color(0xFF4C59BC),
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Portal Seçimi',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E2661),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hesabınızda tanımlı birden fazla portal bulundu. Lütfen giriş yapmak istediğiniz portalı seçin:',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ...portals.map((portal) {
                    final color = portal['color'] as Color;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(context); // Close dialog
                          _navigateToPortal(portal['id'], userData, institutionId, students);
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            border: Border.all(color: color.withOpacity(0.2), width: 1.5),
                            borderRadius: BorderRadius.circular(20),
                            color: color.withOpacity(0.02),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(portal['icon'] as IconData, color: color, size: 24),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      portal['title'] as String,
                                      style: GoogleFonts.inter(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF1E2661),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      portal['subtitle'] as String,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                                color: Colors.grey.shade400,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      if (mounted) {
                        Navigator.pop(context); // Close dialog
                        setState(() {
                          _checkingSession = false;
                        });
                      }
                    },
                    child: Text(
                      'İptal Et ve Çıkış Yap',
                      style: GoogleFonts.inter(
                        color: Colors.red.shade600,
                        fontWeight: FontWeight.w700,
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

  Future<void> _navigateToPortal(
    String portalId,
    Map<String, dynamic> userData,
    String institutionId,
    List<Map<String, dynamic>> students,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_portal', portalId);

    if (portalId == 'manager') {
      if (!UserPermissionService.hasAnyMainModuleAccess(userData)) {
        final userSchoolTypes = userData['schoolTypes'] as List<dynamic>? ?? [];
        if (userSchoolTypes.length == 1) {
          final schoolTypeId = userSchoolTypes.first.toString();
          try {
            final stDoc = await FirebaseFirestore.instance.collection('schoolTypes').doc(schoolTypeId).get();
            if (stDoc.exists) {
              final stName = stDoc.data()?['name'] ?? stDoc.data()?['schoolTypeName'] ?? 'Okul Türü';
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SchoolTypeDetailScreen(
                      schoolTypeId: schoolTypeId,
                      schoolTypeName: stName,
                      institutionId: institutionId,
                    ),
                  ),
                );
                return;
              }
            }
          } catch (e) {
            print('Error fetching school type details on login redirect: $e');
          }
        }
        
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/school-types');
          return;
        }
      }
      Navigator.pushReplacementNamed(context, '/school-dashboard');
    } else if (portalId == 'teacher') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => TeacherMainScreen(institutionId: institutionId)),
      );
    } else if (portalId == 'parent') {
      final tcNo = userData['tcNo'] ?? userData['tcKimlik'] ?? '';
      if (students.length > 1) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ParentStudentSelectionScreen(
              institutionId: institutionId,
              parentTcNo: tcNo.toString(),
              students: students,
            ),
          ),
        );
      } else if (students.length == 1) {
        await prefs.setString('selected_student_id', students[0]['id']);
        Navigator.pushReplacementNamed(context, '/school-dashboard');
      } else {
        Navigator.pushReplacementNamed(context, '/school-dashboard');
      }
    }
  }

  void _forgotPassword() {
    final resetInstitutionController = TextEditingController(text: _institutionController.text.trim());
    final resetUsernameController = TextEditingController(text: _usernameController.text.trim());
    final resetCodeController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    int currentStep = 1; // 1: Bilgi Girişi, 2: Kod Girişi, 3: Yeni Şifre, 4: Başarı
    bool isLoading = false;
    String? errorMessage;
    String? foundEmail;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Başlık ve İkon
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4C59BC).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          currentStep == 4 ? Icons.check_circle_outline : Icons.lock_reset_rounded,
                          color: const Color(0xFF4C59BC),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        currentStep == 4 ? 'İşlem Başarılı' : 'Şifre Sıfırlama',
                        style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1E2661)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Adım Göstergesi (Opsiyonel)
                  if (currentStep < 4)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Row(
                        children: [1, 2, 3].map((i) {
                          bool isActive = i <= currentStep;
                          return Expanded(
                            child: Container(
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: isActive ? const Color(0xFF4C59BC) : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                  if (errorMessage != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade100),
                      ),
                      child: Text(
                        errorMessage!,
                        style: GoogleFonts.inter(color: Colors.red.shade800, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),

                  // ─── ADIM 1: KURUM VE KULLANICI ADI ──────────────────
                  if (currentStep == 1) ...[
                    Text(
                      'Hesabınızı bulmak için Kurum ID ve kullanıcı adınızı girin.',
                      style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade600, height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    _buildResetField('Kurum ID', resetInstitutionController, Icons.business_rounded, 'Kurum ID girin'),
                    const SizedBox(height: 16),
                    _buildResetField('Kullanıcı Adı', resetUsernameController, Icons.person_outline_rounded, 'Kullanıcı adınız'),
                    const SizedBox(height: 32),
                    _buildResetButton(
                      isLoading: isLoading,
                      text: 'Kod Gönder',
                      onPressed: () async {
                        if (resetInstitutionController.text.isEmpty || resetUsernameController.text.isEmpty) {
                          setDialogState(() => errorMessage = 'Lütfen tüm alanları doldurun.');
                          return;
                        }
                        setDialogState(() { isLoading = true; errorMessage = null; });
                        try {
                          final result = await FirebaseFunctions.instance
                              .httpsCallable('sendPasswordResetCode')
                              .call({
                            'institutionId': resetInstitutionController.text.trim(),
                            'username': resetUsernameController.text.trim(),
                          });
                          setDialogState(() {
                            currentStep = 2;
                            foundEmail = result.data['email'];
                            isLoading = false;
                          });
                        } catch (e) {
                          setDialogState(() {
                            isLoading = false;
                            errorMessage = e.toString().contains('not-found') ? 'Hesap bulunamadı.' : 'Bir hata oluştu.';
                          });
                        }
                      },
                    ),
                  ],

                  // ─── ADIM 2: KOD GİRİŞİ (KUTU KUTU) ─────────────────────────────
                  if (currentStep == 2) ...[
                    Text(
                      '${foundEmail?.replaceRange(2, foundEmail!.indexOf('@'), '****')} adresine gönderilen 6 haneli kodu girin.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade600, height: 1.5),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(6, (index) {
                        return Container(
                          width: 48,
                          height: 58,
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: resetCodeController.text.length == index 
                                ? const Color(0xFF4C59BC) 
                                : Colors.grey.shade200,
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: TextField(
                              autofocus: index == 0,
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.number,
                              maxLength: 1,
                              cursorColor: const Color(0xFF4C59BC),
                              style: GoogleFonts.inter(
                                fontSize: 22, 
                                fontWeight: FontWeight.w800, 
                                color: const Color(0xFF1E2661),
                              ),
                              decoration: const InputDecoration(
                                counterText: "", 
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                filled: false,
                                fillColor: Colors.transparent,
                              ),
                              onChanged: (value) {
                                if (value.isNotEmpty) {
                                  if (index < 5) {
                                    FocusScope.of(ctx).nextFocus();
                                  }
                                  String currentCode = resetCodeController.text;
                                  if (currentCode.length > index) {
                                    currentCode = currentCode.replaceRange(index, index + 1, value);
                                  } else {
                                    currentCode += value;
                                  }
                                  resetCodeController.text = currentCode;
                                  
                                  if (currentCode.length == 6) {
                                    setDialogState(() { currentStep = 3; errorMessage = null; });
                                  }
                                } else {
                                  if (index > 0) {
                                    FocusScope.of(ctx).previousFocus();
                                  }
                                  String currentCode = resetCodeController.text;
                                  if (currentCode.length > index) {
                                    resetCodeController.text = currentCode.substring(0, index);
                                  }
                                }
                                setDialogState(() {});
                              },
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 40),
                    TextButton(
                      onPressed: () => setDialogState(() => currentStep = 1),
                      child: Text('Yanlış Bilgi? Geri Dön', style: GoogleFonts.inter(color: const Color(0xFF4C59BC), fontWeight: FontWeight.w600)),
                    ),
                  ],

                  // ─── ADIM 3: YENİ ŞİFRE ──────────────────────────────
                  if (currentStep == 3) ...[
                    Text(
                      'Lütfen hesabınız için yeni ve güvenli bir şifre belirleyin.',
                      style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade600, height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    _buildResetField('Yeni Şifre', newPasswordController, Icons.lock_outline, 'En az 6 karakter', isPassword: true),
                    const SizedBox(height: 16),
                    _buildResetField('Şifre Tekrar', confirmPasswordController, Icons.lock_outline, 'Tekrar yazın', isPassword: true),
                    const SizedBox(height: 32),
                    _buildResetButton(
                      isLoading: isLoading,
                      text: 'Şifreyi Güncelle',
                      onPressed: () async {
                        if (newPasswordController.text.length < 6) {
                          setDialogState(() => errorMessage = 'Şifre en az 6 karakter olmalı.');
                          return;
                        }
                        if (newPasswordController.text != confirmPasswordController.text) {
                          setDialogState(() => errorMessage = 'Şifreler uyuşmuyor.');
                          return;
                        }
                        setDialogState(() { isLoading = true; errorMessage = null; });
                        try {
                          await FirebaseFunctions.instance
                              .httpsCallable('verifyCodeAndResetPassword')
                              .call({
                            'email': foundEmail,
                            'code': resetCodeController.text.trim(),
                            'newPassword': newPasswordController.text,
                          });
                          setDialogState(() { currentStep = 4; isLoading = false; });
                        } catch (e) {
                          setDialogState(() {
                            isLoading = false;
                            errorMessage = 'İşlem başarısız. Kodun süresi dolmuş olabilir.';
                          });
                        }
                      },
                    ),
                  ],

                  // ─── ADIM 4: BAŞARI ────────────────────────────────
                  if (currentStep == 4) ...[
                    const SizedBox(height: 20),
                    Icon(Icons.check_circle_rounded, size: 80, color: Colors.green.shade500),
                    const SizedBox(height: 20),
                    Text(
                      'Şifreniz Güncellendi!',
                      style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Yeni şifrenizle giriş yapabilirsiniz.',
                      style: GoogleFonts.inter(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 40),
                    _buildResetButton(
                      text: 'Giriş Yap',
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildResetField(String label, TextEditingController controller, IconData icon, String hint, {bool isNumeric = false, bool isPassword = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1E2661))),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: isPassword,
          keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
          style: GoogleFonts.inter(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 20),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.all(18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16), 
              borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5)
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16), 
              borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5)
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16), 
              borderSide: const BorderSide(color: Color(0xFF4C59BC), width: 2)
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResetButton({required String text, required VoidCallback onPressed, bool isLoading = false}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4C59BC),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(vertical: 18),
        ),
        child: isLoading
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
            : Text(text, style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
    );
  }

  Future<void> _showKvkkDialog() async {
    final accepted = await Navigator.pushNamed(context, '/kvkk-detail');
    if (accepted == true) setState(() => _kvkkAccepted = true);
  }

  Future<void> _loginWithGmail() async {
    setState(() => _isLoading = true);

    try {
      User? user;

      if (kIsWeb) {
        // Web: Firebase Auth'un kendi popup akışını kullan (google_sign_in_web gerektirmez)
        final provider = GoogleAuthProvider();
        provider.addScope('email');
        final userCredential = await FirebaseAuth.instance.signInWithPopup(provider);
        user = userCredential.user;
      } else {
        // Native (iOS/Android): google_sign_in paketi ile
        final GoogleSignIn googleSignIn = GoogleSignIn();
        final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          if (mounted) setState(() => _isLoading = false);
          return;
        }
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
        user = userCredential.user;
      }

      if (user != null) {
        // Kullanıcının sistemde kaydı var mı kontrol et (Email ile)
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: user.email)
            .limit(1)
            .get();

        if (userDoc.docs.isEmpty) {
          await FirebaseAuth.instance.signOut();
          throw 'Bu Google hesabı ile kayıtlı bir personel bulunamadı. Lütfen yöneticinizle iletişime geçin.';
        }

        final userData = userDoc.docs.first.data();
        if (userData['isActive'] != true) {
          await FirebaseAuth.instance.signOut();
          throw 'Hesabınız pasif durumda!';
        }

        if (mounted) {
          Navigator.pushReplacementNamed(context, '/school-dashboard');
        }
      }
    } catch (e) {
      print('❌ Google Giriş Hatası: $e');
      final errorMessage = e.toString().contains('popup_closed')
          ? 'Giriş penceresi kapatıldı. Lütfen tekrar deneyin.'
          : 'Google ile giriş yapılamadı. Lütfen tekrar deneyin.';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'TAMAM',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showQrLoginDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Center(child: Text('QR Kod ile Giriş Yap', style: GoogleFonts.inter(fontWeight: FontWeight.bold))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Mobil uygulamadan "QR Giriş" özelliğini açarak bu kodu taratın.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.indigo.shade50, width: 2),
                boxShadow: [BoxShadow(color: Colors.indigo.shade100.withOpacity(0.3), blurRadius: 40)],
              ),
              child: Image.network('https://api.qrserver.com/v1/create-qr-code/?size=250x250&data=edukn_login_session_demo_12345', width: 200, height: 200),
            ),
            const SizedBox(height: 24),
            const Text('Oturum Bekleniyor...', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.indigo)),
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat'))],
      ),
    );
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Oturum kontrol edilirken splash ekranı göster
    if (_checkingSession) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4C59BC)),
          ),
        ),
      );
    }

    final size = MediaQuery.of(context).size;
    
    // Hem split-screen (>1150px) hem de tek sütunlu tam ekran (<1150px) modlarını
    // en esnek ve estetik şekilde yöneten, duyarlı (responsive) _buildWebLayout metodunu kullanıyoruz.
    return _buildWebLayout(size);
  }

  // ─── WEB: Split-screen ────────────────────────────────────────────────────

  Widget _buildWebLayout(Size size) {
    // Total content height estimate for left panel
    const double contentHeight = 40 + 36 + 6 + 13 + 40 // header
        + 16 + 52 + 16 // kurum id
        + 16 + 52 + 16 // kullanıcı adı
        + 16 + 52 + 18 // şifre
        + 24 + 24 + 52 + 24 // kvkk + button
        + 20 + 16 + 52 + 16 // divider + social
        + 32 + 16; // footer gap + footer text
    // ≈ 700px; if screen height < contentHeight + 80(vertical padding), scroll opens

    // Ekran genişliği 1150px ve üzeri olduğunda sağ paneli (split-screen) gösteriyoruz.
    final bool showRightPanel = size.width >= 1150;
    
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Tek ekran modundayken (width < 1150px) arka plandaki görselin tüm ekranı kaplamasını sağlıyoruz.
          if (!showRightPanel) ...[
            Positioned.fill(
              child: Image.asset(
                'assets/images/login_bg.png', 
                fit: BoxFit.cover, 
                filterQuality: FilterQuality.high,
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withOpacity(0.85),
                      Colors.white.withOpacity(0.4),
                      Colors.white.withOpacity(0.85),
                    ],
                  ),
                ),
              ),
            ),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── LEFT PANEL ─────────────────────────────────────────────────────
              Expanded(
                flex: showRightPanel ? 0 : 1,
                child: SizedBox(
                  width: showRightPanel ? 440 : size.width,
                  height: size.height,
                  child: Container(
                    color: showRightPanel ? Colors.white : Colors.transparent,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: SingleChildScrollView(
                          physics: const ClampingScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: size.height),
                            child: Container(
                              color: Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                          // ── GROUP 1: Logo + Başlık (Hem web hem mobilde ortalanmış üst kısım) ──
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(width: double.infinity), // Yatayda Center etmek için
                              GestureDetector(
                                onLongPress: () => Navigator.pushNamed(context, '/admin-login'),
                                child: buildWebImage(
                                  'assets/images/google_auth_full_logo_light.png',
                                  width: 280,
                                  height: 80,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Eğitim Yönetim Sistemine Hoş Geldiniz', 
                                textAlign: TextAlign.center, 
                                style: GoogleFonts.inter(
                                  fontSize: 12, 
                                  color: Colors.grey.shade600, 
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),

                      // ── GROUP 2: Form ──
                      Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildLabel('Kurum ID'),
                            _buildInputField(controller: _institutionController, hint: 'Kurum numarası', icon: Icons.business_rounded),
                            const SizedBox(height: 16),
                            _buildLabel('Kullanıcı Adı'),
                            _buildInputField(controller: _usernameController, hint: 'Kullanıcı adı', icon: Icons.person_outline_rounded),
                            const SizedBox(height: 16),
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              _buildLabel('Şifre'),
                              GestureDetector(
                                onTap: _forgotPassword,
                                child: Text('Şifremi Unuttum', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF4C59BC))),
                              ),
                            ]),
                            _buildInputField(controller: _passwordController, hint: '••••••••', icon: Icons.lock_outline_rounded, isPassword: true),
                            const SizedBox(height: 18),
                            _buildKvkkRow(),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4C59BC),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: _isLoading
                                    ? const SizedBox(width: 24, height: 24, child: EduKnLoader(size: 24))
                                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                        Text('Giriş Yap', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700)),
                                        const SizedBox(width: 8),
                                        const Icon(Icons.login_rounded, size: 18),
                                      ]),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(children: [
                              Expanded(child: Divider(color: Colors.grey.shade200)),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text('Veya şununla devam et', style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400)),
                              ),
                              Expanded(child: Divider(color: Colors.grey.shade200)),
                            ]),
                            const SizedBox(height: 16),
                            Row(children: [
                              _buildSocialButton(icon: 'https://cdn-icons-png.flaticon.com/512/2991/2991148.png', label: 'Google', onTap: _loginWithGmail),
                              const SizedBox(width: 12),
                              _buildSocialButton(icon: 'qr_code', label: 'QR Kod', onTap: _showQrLoginDialog),
                            ]),
                          ],
                        ),
                      ),

                      // ── GROUP 3: Footer ──
                      Center(child: Text('© 2026 eduKN. Tüm hakları saklıdır.', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),

          // ── RIGHT PANEL ────────────────────────────────────────────────────
          if (showRightPanel)
            Expanded(
              child: SizedBox(
              height: size.height, // Always full viewport height
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset('assets/images/login_bg.png', fit: BoxFit.cover),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xDD1E2661), Color(0xDD3B47B5), Color(0xAA2E3E8C)],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 48),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Top: Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.25)),
                          ),
                          child: Text('Eğitim Yönetim Sistemi', style: GoogleFonts.inter(color: Colors.white.withOpacity(0.9), fontSize: 12, fontWeight: FontWeight.w600)),
                        ),

                        // Center: Title + Stats
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Eğitimi\nDijitalleştirin.', style: GoogleFonts.inter(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -1.5)),
                            const SizedBox(height: 16),
                            Text(
                              'Öğrenci kayıttan bordro yönetimine,\nokul türü yönetiminden rehberlik\nraporlarına kadar tüm süreçler tek platformda.',
                              style: GoogleFonts.inter(color: Colors.white.withOpacity(0.75), fontSize: 14, height: 1.6),
                            ),
                            const SizedBox(height: 20),
                            Row(children: [
                              _buildStatBadge('Modüller', '9+'),
                              const SizedBox(width: 24),
                              _buildStatBadge('Kullanıcılar', '∞'),
                              const SizedBox(width: 24),
                              _buildStatBadge('Destek', '7/24'),
                            ]),
                          ],
                        ),

                        // Bottom: KVKK
                        Row(children: [
                          Icon(Icons.verified_rounded, color: Colors.white.withOpacity(0.6), size: 15),
                          const SizedBox(width: 8),
                          Text('Güvenli & KVKK Uyumlu Platform', style: GoogleFonts.inter(color: Colors.white.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.w500)),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
          ],
        ),
    );
  }

  Widget _buildStatBadge(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: GoogleFonts.inter(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
      const SizedBox(height: 2),
      Text(label, style: GoogleFonts.inter(color: Colors.white.withOpacity(0.6), fontSize: 12, fontWeight: FontWeight.w500)),
    ]);
  }

  // ─── MOBILE: Single-column ────────────────────────────────────────────────

  Widget _buildMobileLayout(Size size) {
    final isShortScreen = size.height < 700;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(child: Image.asset('assets/images/login_bg.png', fit: BoxFit.cover, filterQuality: FilterQuality.high)),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white.withOpacity(0.85), Colors.white.withOpacity(0.4), Colors.white.withOpacity(0.85)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onLongPress: () => Navigator.pushNamed(context, '/admin-login'),
                            child: buildWebImage(
                              'assets/images/google_auth_full_logo_light.png',
                              width: 280,
                              height: 80,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('Eğitim Yönetim Sistemine Hoş Geldiniz', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 24),
                          Container(
                            constraints: const BoxConstraints(maxWidth: 420),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 40, offset: const Offset(0, 20))],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Center(child: Text('Kurumunuza Giriş Yapın', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF1E2661)))),
                                    const SizedBox(height: 20),
                                    _buildLabel('Kurum ID'),
                                    _buildInputField(controller: _institutionController, hint: 'Kurum numarası', icon: Icons.business_rounded, isMobile: true),
                                    const SizedBox(height: 12),
                                    _buildLabel('Kullanıcı Adı'),
                                    _buildInputField(controller: _usernameController, hint: 'Kullanıcı adı', icon: Icons.person_outline_rounded, isMobile: true),
                                    const SizedBox(height: 12),
                                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                      _buildLabel('Şifre'),
                                      GestureDetector(onTap: _forgotPassword, child: Text('Şifremi Unuttum', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF4C59BC)))),
                                    ]),
                                    _buildInputField(controller: _passwordController, hint: '••••••••', icon: Icons.lock_outline_rounded, isPassword: true, isMobile: true),
                                    const SizedBox(height: 16),
                                    _buildKvkkRow(),
                                    const SizedBox(height: 24),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 50,
                                      child: ElevatedButton(
                                        onPressed: _isLoading ? null : _login,
                                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4C59BC), foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                                        child: _isLoading
                                            ? const SizedBox(width: 24, height: 24, child: EduKnLoader(size: 24))
                                            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                                Text('Giriş Yap', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700)),
                                                const SizedBox(width: 8),
                                                const Icon(Icons.login_rounded, size: 18),
                                              ]),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Row(children: [
                                      Expanded(child: Divider(color: Colors.grey.shade300)),
                                      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('Veya', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500))),
                                      Expanded(child: Divider(color: Colors.grey.shade300)),
                                    ]),
                                    const SizedBox(height: 16),
                                    Row(children: [
                                      _buildSocialButton(icon: 'https://cdn-icons-png.flaticon.com/512/2991/2991148.png', label: 'Google', onTap: _loginWithGmail),
                                      const SizedBox(width: 12),
                                      _buildSocialButton(icon: 'qr_code', label: 'QR Kod', onTap: _showQrLoginDialog),
                                    ]),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── SHARED WIDGETS ───────────────────────────────────────────────────────

  Widget _buildKvkkRow() {
    return GestureDetector(
      onTap: () => setState(() => _kvkkAccepted = !_kvkkAccepted),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: _kvkkAccepted,
              onChanged: (val) => setState(() => _kvkkAccepted = val ?? false),
              activeColor: const Color(0xFF4C59BC),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: _showKvkkDialog,
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600),
                  children: [
                    TextSpan(text: 'KVKK Metnini', style: TextStyle(decoration: TextDecoration.underline, color: Colors.grey.shade800, fontWeight: FontWeight.w600)),
                    const TextSpan(text: ' okudum ve kabul ediyorum.'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool isMobile = false,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword && _obscurePassword,
      style: GoogleFonts.inter(fontSize: 13, color: Colors.indigo.shade900, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400),
        prefixIcon: Icon(icon, size: 18, color: Colors.grey.shade400),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18, color: Colors.grey.shade400),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: isMobile ? 14 : 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF4C59BC), width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.redAccent, width: 1.2)),
      ),
      validator: (v) => v == null || v.isEmpty ? 'Gerekli' : null,
    );
  }

  Widget _buildSocialButton({required String icon, required String label, required VoidCallback onTap}) {
    final isQr = icon == 'qr_code';
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (isQr) Icon(Icons.qr_code_2_rounded, color: Colors.indigo.shade700, size: 22) else Image.network(icon, width: 22, height: 22),
              const SizedBox(width: 8),
              Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E2661))),
            ]),
          ),
        ),
      ),
    );
  }
}
