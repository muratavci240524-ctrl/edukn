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

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final institutionId = _institutionController.text.trim().toUpperCase();

    try {
      final email = '$username@$institutionId.edukn';

      final schoolQuery = await FirebaseFirestore.instance
          .collection('schools')
          .where('institutionId', isEqualTo: institutionId)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 15), onTimeout: () => throw 'Okul bilgileri alınırken zaman aşımı oluştu.');

      if (schoolQuery.docs.isEmpty) throw 'Bu kurum ID ile kayıtlı okul bulunamadı!';

      final schoolData = schoolQuery.docs.first.data();
      if (schoolData['isActive'] != true) throw 'Bu okul şu an pasif durumda!';

      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password)
          .timeout(const Duration(seconds: 20), onTimeout: () => throw 'Giriş işlemi zaman aşımına uğradı.');

      final uid = userCredential.user?.uid;
      if (uid == null) throw 'Kullanıcı kimliği alınamadı.';

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get()
          .timeout(const Duration(seconds: 15), onTimeout: () => throw 'Kullanıcı verisi alınırken zaman aşımı oluştu.');

      Map<String, dynamic>? userData;
      if (userDoc.exists) {
        userData = userDoc.data();
      } else {
        final fallbackQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('institutionId', isEqualTo: institutionId)
            .where('username', isEqualTo: username)
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

        final role = userData?['role']?.toString().toLowerCase() ?? '';
        if (role.contains('ogretmen') || role.contains('teacher') || role.contains('öğretmen')) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => TeacherMainScreen(institutionId: institutionId)));
        } else {
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

  void _forgotPassword() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Şifremi Unuttum'),
        content: const Text('Lütfen okul yönetiminizle iletişime geçin veya kurum yöneticisinden şifre sıfırlama talep edin.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam'))],
      ),
    );
  }

  Future<void> _showKvkkDialog() async {
    final accepted = await Navigator.pushNamed(context, '/kvkk-detail');
    if (accepted == true) setState(() => _kvkkAccepted = true);
  }

  void _loginWithGmail() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Google ile giriş şu an aktif değil. Kurum Mail tanımlaması bekleniyor.')),
    );
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
    final size = MediaQuery.of(context).size;
    final isWeb = size.width >= 900;

    if (isWeb) return _buildWebLayout(size);
    return _buildMobileLayout(size);
  }

  // ─── WEB: Split-screen ────────────────────────────────────────────────────

  Widget _buildWebLayout(Size size) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: Row(
        children: [
          // ── LEFT PANEL: Login Form ──────────────────────────────────────
          SizedBox(
            width: 440,
            child: Container(
              color: Colors.white,
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 48),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: size.height - 96),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Logo
                          Row(children: [
                            const EduKnLogo(type: EduKnLogoType.iconOnly, iconSize: 36),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onLongPress: () => Navigator.pushNamed(context, '/admin-login'),
                              child: Text('eduKN', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w900, color: const Color(0xFF1E2661))),
                            ),
                          ]),

                          const Spacer(),

                          // Title
                          Text('Tekrar Hoş Geldiniz 👋', style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w800, color: const Color(0xFF1E2661), letterSpacing: -0.5)),
                          const SizedBox(height: 6),
                          Text('Kurumunuza giriş yapın', style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 36),

                          // Form
                          Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLabel('Kurum ID'),
                                _buildInputField(controller: _institutionController, hint: 'Kurum numarası', icon: Icons.business_rounded),
                                const SizedBox(height: 18),

                                _buildLabel('Kullanıcı Adı'),
                                _buildInputField(controller: _usernameController, hint: 'Kullanıcı adı', icon: Icons.person_outline_rounded),
                                const SizedBox(height: 18),

                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  _buildLabel('Şifre'),
                                  GestureDetector(
                                    onTap: _forgotPassword,
                                    child: Text('Şifremi Unuttum', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF4C59BC))),
                                  ),
                                ]),
                                _buildInputField(controller: _passwordController, hint: '••••••••', icon: Icons.lock_outline_rounded, isPassword: true),
                                const SizedBox(height: 20),

                                _buildKvkkRow(),
                                const SizedBox(height: 28),

                                // Giriş Yap butonu
                                SizedBox(
                                  width: double.infinity,
                                  height: 54,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _login,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF4C59BC),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                                const SizedBox(height: 28),

                                // Divider
                                Row(children: [
                                  Expanded(child: Divider(color: Colors.grey.shade200)),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    child: Text('Veya şununla devam et', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400, fontWeight: FontWeight.w500)),
                                  ),
                                  Expanded(child: Divider(color: Colors.grey.shade200)),
                                ]),
                                const SizedBox(height: 18),

                                // Google + QR
                                Row(children: [
                                  _buildSocialButton(icon: 'https://cdn-icons-png.flaticon.com/512/2991/2991148.png', label: 'Google', onTap: _loginWithGmail),
                                  const SizedBox(width: 14),
                                  _buildSocialButton(icon: 'qr_code', label: 'QR Kod', onTap: _showQrLoginDialog),
                                ]),
                              ],
                            ),
                          ),

                          const Spacer(),

                          // Footer
                          Center(child: Text('© 2026 eduKN. Tüm hakları saklıdır.', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400))),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── RIGHT PANEL: Welcome / Decorative ──────────────────────────
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Arka plan görseli
                Image.asset('assets/images/login_bg.png', fit: BoxFit.cover, filterQuality: FilterQuality.high),
                // Gradient overlay
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xDD1E2661), Color(0xDD3B47B5), Color(0xAA2E3E8C)],
                    ),
                  ),
                ),
                // İçerik
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 60),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.25)),
                        ),
                        child: Text('Eğitim Yönetim Sistemi', style: GoogleFonts.inter(color: Colors.white.withOpacity(0.9), fontSize: 12, fontWeight: FontWeight.w600)),
                      ),

                      const Spacer(),

                      // Ana başlık
                      Text('Eğitimi\nDijitalleştirin.', style: GoogleFonts.inter(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -1.5)),
                      const SizedBox(height: 20),
                      Text(
                        'Öğrenci kayıttan bordro yönetimine,\nokul türü yönetiminden rehberlik\nraporlarına kadar tüm süreçler tek platformda.',
                        style: GoogleFonts.inter(color: Colors.white.withOpacity(0.75), fontSize: 15, height: 1.8, fontWeight: FontWeight.w400),
                      ),
                      const SizedBox(height: 52),

                      // İstatistik rozetleri
                      Row(children: [
                        _buildStatBadge('Modüller', '9+'),
                        const SizedBox(width: 32),
                        _buildStatBadge('Kullanıcılar', '∞'),
                        const SizedBox(width: 32),
                        _buildStatBadge('Destek', '7/24'),
                      ]),

                      const Spacer(),

                      // Alt bilgi
                      Row(children: [
                        Icon(Icons.verified_rounded, color: Colors.white.withOpacity(0.6), size: 16),
                        const SizedBox(width: 8),
                        Text('Güvenli & KVKK Uyumlu Platform', style: GoogleFonts.inter(color: Colors.white.withOpacity(0.6), fontSize: 12, fontWeight: FontWeight.w500)),
                      ]),
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
                  physics: isShortScreen ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight, maxHeight: isShortScreen ? double.infinity : constraints.maxHeight),
                    child: Center(
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Spacer(flex: 1),
                              const EduKnLogo(type: EduKnLogoType.iconOnly, iconSize: 70),
                              const SizedBox(height: 12),
                              GestureDetector(
                                onLongPress: () => Navigator.pushNamed(context, '/admin-login'),
                                child: Text('eduKN Giriş', style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w800, color: const Color(0xFF1E2661), letterSpacing: -0.5)),
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

  // ─── SHARED WIDGETS ───────────────────────────────────────────────────────

  Widget _buildKvkkRow() {
    return GestureDetector(
      onTap: () => setState(() => _kvkkAccepted = !_kvkkAccepted),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _kvkkAccepted ? const Color(0xFF4C59BC) : Colors.grey.shade300, width: 1.5),
              color: _kvkkAccepted ? const Color(0xFF4C59BC) : Colors.transparent,
            ),
            child: _kvkkAccepted ? const Icon(Icons.check, size: 10, color: Colors.white) : null,
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
