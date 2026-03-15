import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({Key? key}) : super(key: key);

  @override
  _AdminLoginScreenState createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _kvkkAccepted = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_kvkkAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lütfen KVKK metnini onaylayın.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      print('🔐 Süper Admin girişi deneniyor...');
      print('📧 Email: $email');

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      print('✅ Giriş başarılı!');

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/admin-dashboard');
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Giriş başarısız!';
      if (e.code == 'user-not-found') {
        message = 'Bu email ile kayıtlı süper admin bulunamadı!';
      } else if (e.code == 'wrong-password') {
        message = 'Hatalı şifre!';
      } else if (e.code == 'invalid-email') {
        message = 'Geçersiz email formatı!';
      } else if (e.code == 'invalid-credential') {
        message = 'Hatalı email veya şifre!';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bilinmeyen hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showKvkkDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('KVKK Aydınlatma Metni'),
        content: SingleChildScrollView(
          child: Text(
            '6698 Sayılı Kişisel Verilerin Korunması Kanunu ("KVKK") Kapsamında Aydınlatma Metni\n\n'
            'Bu aydınlatma metni, 6698 sayılı Kişisel Verilerin Korunması Kanunu\'nun '
            '10. maddesi ile Aydınlatma Yükümlülüğünün Yerine Getirilmesinde Uyulacak '
            'Usul ve Esaslar Hakkında Tebliğ kapsamında veri sorumlusu sıfatıyla '
            'hazırlanmıştır.\n\n'
            '1. Kişisel Verilerin İşlenme Amacı\n'
            'Kişisel verileriniz; eğitim hizmetlerinin yürütülmesi, öğrenci takibi, '
            'rehberlik faaliyetleri, iletişim ve bilgilendirme amaçlarıyla işlenmektedir.\n\n'
            '2. İşlenen Kişisel Veriler\n'
            'Ad, soyad, kullanıcı adı, e-posta adresi, kurum bilgileri ve '
            'eğitim süreçlerine ilişkin veriler işlenmektedir.\n\n'
            '3. Kişisel Verilerin Aktarılması\n'
            'Kişisel verileriniz, yasal yükümlülükler ve hizmet gereksinimleri '
            'doğrultusunda yetkili kurum ve kuruluşlara aktarılabilir.\n\n'
            '4. Kişisel Veri Toplamanın Yöntemi ve Hukuki Sebebi\n'
            'Kişisel verileriniz, elektronik ortamda bu platform aracılığıyla '
            'toplanmakta olup, KVKK\'nın 5. ve 6. maddelerinde belirtilen hukuki '
            'sebeplere dayanılarak işlenmektedir.\n\n'
            '5. Kişisel Veri Sahibinin Hakları\n'
            'KVKK\'nın 11. maddesi kapsamında; kişisel verilerinizin işlenip '
            'işlenmediğini öğrenme, işlenmişse buna ilişkin bilgi talep etme, '
            'işlenme amacını ve bunların amacına uygun kullanılıp kullanılmadığını '
            'öğrenme, eksik veya yanlış işlenmiş olması halinde düzeltilmesini '
            'isteme ve silinmesini veya yok edilmesini talep etme haklarına '
            'sahipsiniz.',
          ),
        ),
        actions: [
          TextButton(
            child: Text('Kapat'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 600;

          // Mobil için boyut ve boşlukları ayarla
          final double paddingValue = isMobile ? 20.0 : 32.0;
          final double titleSize = isMobile ? 24.0 : 28.0;
          final double iconSize = isMobile ? 48.0 : 64.0;
          final double spaceSmall = isMobile ? 12.0 : 16.0;
          final double spaceMedium = isMobile ? 20.0 : 24.0;
          final double spaceLarge = isMobile ? 24.0 : 32.0;

          return Container(
            height: constraints.maxHeight,

            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Colors.purple.shade700,
                  Colors.deepPurple.shade500,
                  Colors.indigo.shade400,
                ],
              ),
            ),
            child: Center(
              child: SingleChildScrollView(
                physics: isMobile ? const ClampingScrollPhysics() : null,
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: isMobile ? double.infinity : 450,
                    minHeight: isMobile ? constraints.maxHeight : 0,
                  ),
                  color: isMobile ? Colors.white : null,
                  margin: isMobile ? EdgeInsets.zero : EdgeInsets.all(24),
                  child: Card(
                    elevation: isMobile ? 0 : 8,
                    color: isMobile ? Colors.transparent : null,
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(isMobile ? 0 : 16),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(paddingValue),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisAlignment: isMobile
                              ? MainAxisAlignment.center
                              : MainAxisAlignment.start,
                          mainAxisSize: isMobile
                              ? MainAxisSize.max
                              : MainAxisSize.min,
                          children: [
                            // Logo ve Başlık
                            Container(
                              padding: EdgeInsets.all(isMobile ? 12 : 16),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade50,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.admin_panel_settings,
                                size: iconSize,
                                color: Colors.purple,
                              ),
                            ),
                            SizedBox(height: spaceMedium),
                            Text(
                              'Süper Admin Paneli',
                              style: TextStyle(
                                fontSize: titleSize,
                                fontWeight: FontWeight.bold,
                                color: Colors.purple.shade900,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Sistem yönetimi için giriş yapın',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            SizedBox(height: spaceLarge),

                            // Email
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                labelText: 'E-posta',
                                labelStyle: TextStyle(
                                  color: Colors.purple.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                                prefixIcon: Icon(
                                  Icons.alternate_email_rounded,
                                  color: Colors.purple.shade400,
                                ),
                                hintText: 'admin@edukn.com',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade400,
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade200,
                                    width: 1.5,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                    color: Colors.purple,
                                    width: 2,
                                  ),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                    color: Colors.red.shade200,
                                    width: 1.5,
                                  ),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                    color: Colors.red.shade400,
                                    width: 2,
                                  ),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: isMobile ? 16 : 20,
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'E-posta gerekli';
                                }
                                if (!v.contains('@')) {
                                  return 'Geçerli e-posta girin';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: spaceSmall),

                            // Şifre
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                labelText: 'Şifre',
                                labelStyle: TextStyle(
                                  color: Colors.purple.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                                prefixIcon: Icon(
                                  Icons.lock_rounded,
                                  color: Colors.purple.shade400,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    color: Colors.purple.shade300,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade200,
                                    width: 1.5,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                    color: Colors.purple,
                                    width: 2,
                                  ),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                    color: Colors.red.shade200,
                                    width: 1.5,
                                  ),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                    color: Colors.red.shade400,
                                    width: 2,
                                  ),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: isMobile ? 16 : 20,
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Şifre gerekli';
                                }
                                return null;
                              },
                              onFieldSubmitted: (_) {
                                if (!_isLoading) _login();
                              },
                            ),
                            SizedBox(height: spaceSmall),

                            // KVKK Checkbox
                            Row(
                              children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: Checkbox(
                                    value: _kvkkAccepted,
                                    onChanged: (val) {
                                      setState(() {
                                        _kvkkAccepted = val ?? false;
                                      });
                                    },
                                    activeColor: Colors.purple,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: _showKvkkDialog,
                                    child: RichText(
                                      text: TextSpan(
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade700,
                                        ),
                                        children: [
                                          TextSpan(
                                            text: 'KVKK Aydınlatma Metni',
                                            style: TextStyle(
                                              color: Colors.purple,
                                              decoration:
                                                  TextDecoration.underline,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          TextSpan(
                                            text:
                                                '\'ni okudum ve kabul ediyorum.',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: spaceMedium),

                            // Giriş Butonu
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.purple,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _isLoading
                                    ? SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(
                                        'Giriş Yap',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),
                            SizedBox(height: spaceSmall),

                            // Şifremi Unuttum
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                TextButton(
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: Text('Şifrenizi mi unuttunuz?'),
                                        content: Text(
                                          'Lütfen sistem yöneticinizle iletişime geçin.',
                                        ),
                                        actions: [
                                          TextButton(
                                            child: Text('Tamam'),
                                            onPressed: () =>
                                                Navigator.pop(context),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  child: Text('Şifremi Unuttum'),
                                ),
                              ],
                            ),

                            // Okul Girişi
                            SizedBox(height: spaceSmall),
                            Divider(),
                            TextButton.icon(
                              icon: Icon(Icons.school),
                              label: Text('Okul Girişi'),
                              onPressed: () {
                                Navigator.pushReplacementNamed(
                                  context,
                                  '/school-login',
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
