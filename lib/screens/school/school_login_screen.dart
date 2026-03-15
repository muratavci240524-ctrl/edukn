import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../teacher/teacher_main_screen.dart';

class SchoolLoginScreen extends StatefulWidget {
  const SchoolLoginScreen({Key? key}) : super(key: key);

  @override
  _SchoolLoginScreenState createState() => _SchoolLoginScreenState();
}

class _SchoolLoginScreenState extends State<SchoolLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _institutionIdController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _kvkkAccepted = false;

  @override
  void dispose() {
    _institutionIdController.dispose();
    _usernameController.dispose();
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
      final institutionId = _institutionIdController.text.trim().toUpperCase();
      final username = _usernameController.text.trim().toLowerCase();
      final password = _passwordController.text;

      // Kullanıcı adı ve kurum ID'den email oluştur
      final email = '$username@$institutionId.edukn';

      print('🔐 Okul girişi deneniyor...');
      print('🆔 Kurum ID: $institutionId');
      print('👤 Kullanıcı Adı: $username');
      print('📧 Oluşturulan Email: $email');

      // 1. Kurum ID ile okulu bul
      final schoolQuery = await FirebaseFirestore.instance
          .collection('schools')
          .where('institutionId', isEqualTo: institutionId)
          .limit(1)
          .get();

      if (schoolQuery.docs.isEmpty) {
        throw 'Bu kurum ID ile kayıtlı okul bulunamadı!';
      }

      final schoolDoc = schoolQuery.docs.first;
      final schoolData = schoolDoc.data();

      // 2. Okul aktif mi kontrol et
      if (schoolData['isActive'] != true) {
        throw 'Bu okul şu an pasif durumda! Lütfen yöneticinizle iletişime geçin.';
      }

      // 3. Lisans süresi kontrol et
      if (schoolData['licenseExpiresAt'] != null) {
        final expiresAt = (schoolData['licenseExpiresAt'] as Timestamp)
            .toDate();
        if (expiresAt.isBefore(DateTime.now())) {
          throw 'Okul lisansı sona ermiş! Lütfen yöneticinizle iletişime geçin.';
        }
      }

      // 4. Önce Firebase Authentication ile giriş yap
      print('🔐 Firebase Auth ile giriş yapılıyor...');
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final String uid = userCredential.user?.uid ?? '';

      print('✅ Firebase Auth başarılı! UID: $uid');

      // 5. Giriş yaptıktan SONRA kullanıcı kontrolü yap
      // ÖNCELİK: Doğrudan UID ile dokümanı çek (Rules için en güvenli yol)
      Map<String, dynamic>? loggedUserData;
      final docSnap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      
      if (docSnap.exists) {
        loggedUserData = docSnap.data();
        print('✅ Kullanıcı dokümanı UID ile bulundu.');
      } else {
        // FALLBACK: Kullanıcı adı ve kurum ID ile sorgula (Eski kayıtlar veya admin için)
        final userQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('institutionId', isEqualTo: institutionId)
            .where('username', isEqualTo: username)
            .limit(1)
            .get();
            
        if (userQuery.docs.isNotEmpty) {
          loggedUserData = userQuery.docs.first.data();
          print('✅ Kullanıcı dokümanı sorgu ile bulundu.');
        }
      }

      // Admin kontrolü yap (adminUsername varsa)
      final isAdmin = schoolData['adminUsername'] == username;

      if (loggedUserData == null && !isAdmin) {
        // Giriş yapıldı ama kullanıcı bulunamadı, çıkış yap
        await FirebaseAuth.instance.signOut();
        throw 'Bu kurum için kullanıcı kaydı bulunamadı!';
      }

      // Kullanıcı varsa aktif mi kontrol et
      if (loggedUserData != null) {
        if (loggedUserData['isActive'] != true) {
          // Kullanıcı pasif, çıkış yap
          await FirebaseAuth.instance.signOut();
          throw 'Kullanıcı hesabınız pasif durumda! Lütfen yöneticinizle iletişime geçin.';
        }
      }

      print('✅ Giriş başarılı!');
      print('🏫 Okul: ${schoolData['schoolName']}');

      if (mounted) {
        // Rol kontrolü: Öğretmen mi?
        final role = loggedUserData?['role']?.toString().toLowerCase();
        if (role == 'ogretmen' || role == 'teacher') {
            Navigator.pushReplacement(
              context, 
              MaterialPageRoute(
                builder: (context) => TeacherMainScreen(institutionId: institutionId)
              )
            );
        } else {
            // Normal okul dashboard'a yönlendir
            Navigator.pushReplacementNamed(context, '/school-dashboard');
        }
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Giriş başarısız!';
      if (e.code == 'user-not-found') {
        message = 'Bu email ile kayıtlı kullanıcı bulunamadı!';
      } else if (e.code == 'wrong-password') {
        message = 'Hatalı şifre!';
      } else if (e.code == 'invalid-email') {
        message = 'Geçersiz email formatı!';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
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
    return PopScope(
      canPop: false, // İlk sayfada geri tuşunu engelle
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 600;

            // Dinamik ölçeklendirme faktörü
            double scale = 1.0;
            if (isMobile) {
              // Mobilde genişliğe göre orantıla (Min 375 referans)
              scale = (constraints.maxWidth / 375.0).clamp(0.85, 1.1);
            } else {
              // Web'de yüksekliğe göre orantıla ki kaydırma gerekmesin (Ref 850px)
              scale = (constraints.maxHeight / 850.0).clamp(0.85, 1.0);
            }

            // Mobil için boyut ve boşlukları ayarla (Scale ile çarpıldı)
            final double paddingValue = (isMobile ? 20.0 : 32.0) * scale;
            final double titleSize = (isMobile ? 24.0 : 28.0) * scale;
            final double iconSize = (isMobile ? 48.0 : 64.0) * scale;
            final double spaceSmall = (isMobile ? 12.0 : 16.0) * scale;
            final double spaceMedium = (isMobile ? 20.0 : 24.0) * scale;
            final double spaceLarge = (isMobile ? 24.0 : 32.0) * scale;
            final double inputIconSize = 24.0 * scale;

            return Container(
              height: constraints.maxHeight,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.indigo.shade700,
                    Colors.indigo.shade400,
                    Colors.blue.shade300,
                  ],
                ),
              ),
              child: Center(
                child: SingleChildScrollView(
                  physics: isMobile ? const ClampingScrollPhysics() : null,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: isMobile ? double.infinity : 450 * scale,
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
                                padding: EdgeInsets.all(
                                  (isMobile ? 12 : 16) * scale,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.shade50,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.school,
                                  size: iconSize,
                                  color: Colors.indigo,
                                ),
                              ),
                              SizedBox(height: spaceMedium),
                              Text(
                                'Okul Giriş Paneli',
                                style: TextStyle(
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo.shade900,
                                ),
                              ),
                              SizedBox(height: 8 * scale),
                              Text(
                                'Kurum bilgilerinizle giriş yapın',
                                style: TextStyle(
                                  fontSize: 14 * scale,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              SizedBox(height: spaceLarge),

                              // Kurum ID
                              TextFormField(
                                controller: _institutionIdController,
                                decoration: InputDecoration(
                                  labelText: 'Kurum ID',
                                  labelStyle: TextStyle(
                                    color: Colors.indigo.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.business_rounded,
                                    color: Colors.indigo.shade400,
                                    size: inputIconSize,
                                  ),
                                  hintText: 'Örn: ANKA2024',
                                  hintStyle: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 14 * scale,
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      16 * scale,
                                    ),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade200,
                                      width: 1.5,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      16 * scale,
                                    ),
                                    borderSide: BorderSide(
                                      color: Colors.indigo,
                                      width: 2,
                                    ),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      16 * scale,
                                    ),
                                    borderSide: BorderSide(
                                      color: Colors.red.shade200,
                                      width: 1.5,
                                    ),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      16 * scale,
                                    ),
                                    borderSide: BorderSide(
                                      color: Colors.red.shade400,
                                      width: 2,
                                    ),
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 20 * scale,
                                    vertical: (isMobile ? 16 : 20) * scale,
                                  ),
                                ),
                                textCapitalization:
                                    TextCapitalization.characters,
                                onChanged: (value) {
                                  // Kullanıcı yazarken müdahale etmiyoruz,
                                  // giriş butonuna basıldığında işleyeceğiz.
                                },
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'Kurum ID gerekli';
                                  }
                                  return null;
                                },
                              ),
                              SizedBox(height: spaceSmall),

                              // Kullanıcı Adı
                              TextFormField(
                                controller: _usernameController,
                                decoration: InputDecoration(
                                  labelText: 'Kullanıcı Adı',
                                  labelStyle: TextStyle(
                                    color: Colors.indigo.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.person_rounded,
                                    color: Colors.indigo.shade400,
                                    size: inputIconSize,
                                  ),
                                  hintText: 'ahmetyilmaz',
                                  hintStyle: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 14 * scale,
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      16 * scale,
                                    ),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade200,
                                      width: 1.5,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      16 * scale,
                                    ),
                                    borderSide: BorderSide(
                                      color: Colors.indigo,
                                      width: 2,
                                    ),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      16 * scale,
                                    ),
                                    borderSide: BorderSide(
                                      color: Colors.red.shade200,
                                      width: 1.5,
                                    ),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      16 * scale,
                                    ),
                                    borderSide: BorderSide(
                                      color: Colors.red.shade400,
                                      width: 2,
                                    ),
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 20 * scale,
                                    vertical: (isMobile ? 16 : 20) * scale,
                                  ),
                                ),
                                onChanged: (value) {
                                  // Kullanıcı yazarken müdahale etmiyoruz,
                                  // giriş butonuna basıldığında işleyeceğiz.
                                },
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'Kullanıcı adı gerekli';
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
                                    color: Colors.indigo.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.lock_rounded,
                                    color: Colors.indigo.shade400,
                                    size: inputIconSize,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_rounded
                                          : Icons.visibility_rounded,
                                      color: Colors.indigo.shade300,
                                      size: inputIconSize,
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
                                    borderRadius: BorderRadius.circular(
                                      16 * scale,
                                    ),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade200,
                                      width: 1.5,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      16 * scale,
                                    ),
                                    borderSide: BorderSide(
                                      color: Colors.indigo,
                                      width: 2,
                                    ),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      16 * scale,
                                    ),
                                    borderSide: BorderSide(
                                      color: Colors.red.shade200,
                                      width: 1.5,
                                    ),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      16 * scale,
                                    ),
                                    borderSide: BorderSide(
                                      color: Colors.red.shade400,
                                      width: 2,
                                    ),
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 20 * scale,
                                    vertical: (isMobile ? 16 : 20) * scale,
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'Şifre gerekli';
                                  }
                                  return null;
                                },
                              ),
                              SizedBox(height: spaceSmall),

                              // KVKK Checkbox
                              Row(
                                children: [
                                  SizedBox(
                                    width: 24 * scale,
                                    height: 24 * scale,
                                    child: Checkbox(
                                      value: _kvkkAccepted,
                                      onChanged: (val) {
                                        setState(() {
                                          _kvkkAccepted = val ?? false;
                                        });
                                      },
                                      activeColor: Colors.indigo,
                                    ),
                                  ),
                                  SizedBox(width: 8 * scale),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: _showKvkkDialog,
                                      child: RichText(
                                        text: TextSpan(
                                          style: TextStyle(
                                            fontSize: 13 * scale,
                                            color: Colors.grey.shade700,
                                          ),
                                          children: [
                                            TextSpan(
                                              text: 'KVKK Aydınlatma Metni',
                                              style: TextStyle(
                                                color: Colors.indigo,
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
                                height: 50 * scale,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _login,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.indigo,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        12 * scale,
                                      ),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? SizedBox(
                                          height: 24 * scale,
                                          width: 24 * scale,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          'Giriş Yap',
                                          style: TextStyle(
                                            fontSize: 16 * scale,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                ),
                              ),
                              SizedBox(height: spaceSmall),

                              // Yardım Linkleri
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: Text(
                                            'Şifrenizi mi unuttunuz?',
                                          ),
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
                                    child: Text(
                                      'Şifremi Unuttum',
                                      style: TextStyle(fontSize: 14 * scale),
                                    ),
                                  ),
                                ],
                              ),

                              // Süper Admin Girişi
                              SizedBox(height: spaceSmall),
                              Divider(),
                              TextButton.icon(
                                icon: Icon(
                                  Icons.admin_panel_settings,
                                  size: 24 * scale,
                                ),
                                label: Text(
                                  'Süper Admin Girişi',
                                  style: TextStyle(fontSize: 14 * scale),
                                ),
                                onPressed: () {
                                  Navigator.pushReplacementNamed(
                                    context,
                                    '/admin-login',
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
      ),
    );
  }
}
