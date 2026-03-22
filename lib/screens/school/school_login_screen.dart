import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/edukn_logo.dart';
import '../teacher/teacher_main_screen.dart';

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

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final institutionId = _institutionController.text.trim().toUpperCase();

    try {
      final email = '$username@$institutionId.edukn';

      print('🔐 Okul girişi deneniyor...');
      print('🆔 Kurum ID: $institutionId');
      print('📧 Email: $email');

      // 1. Kurum bilgilerini kontrol et
      final schoolQuery = await FirebaseFirestore.instance
          .collection('schools')
          .where('institutionId', isEqualTo: institutionId)
          .limit(1)
          .get()
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () =>
                throw 'Okul bilgileri alınırken zaman aşımı oluştu.',
          );

      if (schoolQuery.docs.isEmpty) {
        throw 'Bu kurum ID ile kayıtlı okul bulunamadı!';
      }

      final schoolData = schoolQuery.docs.first.data();
      if (schoolData['isActive'] != true) {
        throw 'Bu okul şu an pasif durumda!';
      }

      // 2. Firebase Auth ile giriş yap
      print('🔐 Firebase Auth giriş denemesi: $email');
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password)
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              print('❌ FirebaseAuth Timeout!');
              throw 'Giriş işlemi zaman aşımına uğradı. Lütfen internetinizi kontrol edin.';
            },
          );

      final uid = userCredential.user?.uid;
      if (uid == null) throw 'Kullanıcı kimliği alınamadı.';

      print('✅ Auth başarılı. UID: $uid');

      // 3. Kullanıcı verisini doğrula
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () =>
                throw 'Kullanıcı verisi alınırken zaman aşımı oluştu.',
          );

      Map<String, dynamic>? userData;
      if (userDoc.exists) {
        userData = userDoc.data();
      } else {
        // Fallback search
        final fallbackQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('institutionId', isEqualTo: institutionId)
            .where('username', isEqualTo: username)
            .limit(1)
            .get();
        if (fallbackQuery.docs.isNotEmpty) {
          userData = fallbackQuery.docs.first.data();
        }
      }

      if (userData == null && schoolData['adminUsername'] != username) {
        await FirebaseAuth.instance.signOut();
        throw 'Kullanıcı kaydı bulunamadı!';
      }

      if (userData != null && userData['isActive'] != true) {
        await FirebaseAuth.instance.signOut();
        throw 'Hesabınız pasif durumda!';
      }

      print('✅ Giriş başarılı, yönlendiriliyor...');

      if (mounted) {
        // Show success loading animation for 2 seconds
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => WillPopScope(
            onWillPop: () async => false,
            child: const Center(
              child: EduKnLoader(size: 100),
            ),
          ),
        );

        await Future.delayed(const Duration(milliseconds: 2000));
        if (!mounted) return;
        Navigator.pop(context); // Close the dialog

        final role = userData?['role']?.toString().toLowerCase() ?? '';
        if (role.contains('ogretmen') ||
            role.contains('teacher') ||
            role.contains('öğretmen')) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  TeacherMainScreen(institutionId: institutionId),
            ),
          );
        } else {
          Navigator.pushReplacementNamed(context, '/school-dashboard');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _forgotPassword() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Şifremi Unuttum'),
        content: const Text(
          'Lütfen okul yönetiminizle iletişime geçin veya kurum yöneticisinden şifre sıfırlama talep edin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  Future<void> _showKvkkDialog() async {
    final accepted = await Navigator.pushNamed(context, '/kvkk-detail');
    if (accepted == true) {
      setState(() => _kvkkAccepted = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;
    final isShortScreen = size.height < 700;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Full-screen background image
          Positioned.fill(
            child: Image.asset(
              'assets/images/login_bg.png',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            ),
          ),
          // Soft gradient overlay for premium feel
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

          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: isShortScreen
                      ? const ClampingScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                      maxHeight: isShortScreen
                          ? double.infinity
                          : constraints.maxHeight,
                    ),
                    child: Center(
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 20 : 24,
                            vertical: isMobile ? 10 : 20,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Spacer(flex: 1),
                              // Logo & Header
                              const EduKnLogo(
                                type: EduKnLogoType.iconOnly,
                                iconSize: 70,
                              ),
                              SizedBox(height: isMobile ? 12 : 20),
                              GestureDetector(
                                onLongPress: () {
                                  Navigator.pushNamed(context, '/admin-login');
                                },
                                child: Text(
                                  'eduKN Giriş',
                                  style: GoogleFonts.inter(
                                    fontSize: isMobile ? 26 : 32,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF1E2661),
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Eğitim Yönetim Sistemine Hoş Geldiniz',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: isMobile ? 12 : 14,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: isMobile ? 24 : 40),

                              // Login Card
                              Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 420,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(
                                    isMobile ? 24 : 32,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 40,
                                      offset: const Offset(0, 20),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(isMobile ? 24 : 40),
                                  child: Form(
                                    key: _formKey,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Center(
                                          child: Text(
                                            'Kurumunuza Giriş Yapın',
                                            style: GoogleFonts.inter(
                                              fontSize: isMobile ? 16 : 18,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF1E2661),
                                            ),
                                          ),
                                        ),
                                        SizedBox(height: isMobile ? 20 : 32),

                                        _buildLabel('Kurum ID'),
                                        _buildInputField(
                                          controller: _institutionController,
                                          hint: 'Kurum numarası',
                                          icon: Icons.business_rounded,
                                          isMobile: isMobile,
                                        ),
                                        SizedBox(height: isMobile ? 12 : 20),

                                        _buildLabel('Kullanıcı Adı'),
                                        _buildInputField(
                                          controller: _usernameController,
                                          hint: 'Kullanıcı adı',
                                          icon: Icons.person_outline_rounded,
                                          isMobile: isMobile,
                                        ),
                                        SizedBox(height: isMobile ? 12 : 20),

                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            _buildLabel('Şifre'),
                                            GestureDetector(
                                              onTap: _forgotPassword,
                                              child: Text(
                                                'Şifremi Unuttum',
                                                style: GoogleFonts.inter(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: const Color(
                                                    0xFF4C59BC,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        _buildInputField(
                                          controller: _passwordController,
                                          hint: '********',
                                          icon: Icons.lock_outline_rounded,
                                          isPassword: true,
                                          isMobile: isMobile,
                                        ),
                                        SizedBox(height: isMobile ? 16 : 24),

                                        // KVKK
                                        _buildKvkkRow(isMobile),
                                        SizedBox(height: isMobile ? 24 : 40),

                                        // Submit Button
                                        SizedBox(
                                          width: double.infinity,
                                          height: isMobile ? 50 : 56,
                                          child: ElevatedButton(
                                            onPressed: _isLoading
                                                ? null
                                                : _login,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(
                                                0xFF4C59BC,
                                              ),
                                              foregroundColor: Colors.white,
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                            ),
                                            child: _isLoading
                                                ? const SizedBox(
                                                    width: 24,
                                                    height: 24,
                                                    child: EduKnLoader(size: 24),
                                                  )
                                                : Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Text(
                                                        'Giriş Yap',
                                                        style: TextStyle(
                                                          fontSize: isMobile
                                                              ? 15
                                                              : 16,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      const Icon(
                                                        Icons.login_rounded,
                                                        size: 18,
                                                      ),
                                                    ],
                                                  ),
                                          ),
                                        ),

                                        const SizedBox(height: 24),

                                        // --- ALTERNATIVE LOGINS ---
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Divider(
                                                color: Colors.grey.shade300,
                                              ),
                                            ),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                  ),
                                              child: Text(
                                                'Veya şununla devam et',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade500,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child: Divider(
                                                color: Colors.grey.shade300,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 20),

                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceEvenly,
                                          children: [
                                            // Gmail Login
                                            _buildSocialButton(
                                              icon:
                                                  'https://cdn-icons-png.flaticon.com/512/2991/2991148.png',
                                              label: 'Google',
                                              onTap: _loginWithGmail,
                                            ),
                                            const SizedBox(width: 16),
                                            // QR Login
                                            _buildSocialButton(
                                              icon: 'qr_code',
                                              label: 'QR Kod',
                                              onTap: _showQrLoginDialog,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const Spacer(flex: 3),
                            ],
                          ),
                        ),
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

  Widget _buildKvkkRow(bool isMobile) {
    return GestureDetector(
      onTap: () => setState(() => _kvkkAccepted = !_kvkkAccepted),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _kvkkAccepted
                    ? const Color(0xFF4C59BC)
                    : Colors.grey.shade300,
                width: 1.5,
              ),
              color: _kvkkAccepted
                  ? const Color(0xFF4C59BC)
                  : Colors.transparent,
            ),
            child: _kvkkAccepted
                ? const Icon(Icons.check, size: 10, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: _showKvkkDialog,
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                  children: [
                    TextSpan(
                      text: 'KVKK Metnini',
                      style: TextStyle(
                        decoration: TextDecoration.underline,
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade700,
        ),
      ),
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
      style: GoogleFonts.inter(
        fontSize: 13,
        color: Colors.indigo.shade900,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400),
        prefixIcon: Icon(icon, size: 18, color: Colors.grey.shade400),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 18,
                ),
                color: Colors.grey.shade400,
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: isMobile ? 14 : 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4C59BC), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
        ),
      ),
      validator: (v) => v == null || v.isEmpty ? 'Gerekli' : null,
    );
  }

  Widget _buildSocialButton({
    required String icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final isQr = icon == 'qr_code';

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isQr)
                  Icon(
                    Icons.qr_code_2_rounded,
                    color: Colors.indigo.shade700,
                    size: 22,
                  )
                else
                  Image.network(icon, width: 22, height: 22),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E2661),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _loginWithGmail() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Google ile giriş şu an aktif değil. Kurum Mail tanımlaması bekleniyor.',
        ),
      ),
    );
  }

  void _showQrLoginDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Center(
          child: Text(
            'QR Kod ile Giriş Yap',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Mobil uygulamadan "QR Giriş" özelliğini açarak bu kodu taratın.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.indigo.shade50, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.indigo.shade100.withOpacity(0.3),
                    blurRadius: 40,
                  ),
                ],
              ),
              child: Image.network(
                'https://api.qrserver.com/v1/create-qr-code/?size=250x250&data=edukn_login_session_demo_12345',
                width: 200,
                height: 200,
              ), // Demo QR
            ),
            const SizedBox(height: 24),
            const Text(
              'Oturum Bekleniyor...',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }
}
