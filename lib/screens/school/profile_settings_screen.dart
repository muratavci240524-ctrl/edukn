import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:html' as html;

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({Key? key}) : super(key: key);

  @override
  _ProfileSettingsScreenState createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers - Okul Bilgileri (Admin için)
  final _schoolNameController = TextEditingController();
  final _schoolAddressController = TextEditingController();
  final _schoolPhoneController = TextEditingController();
  final _schoolEmailController = TextEditingController();
  
  // Controllers - Kullanıcı Bilgileri (Normal kullanıcı için)
  final _fullNameController = TextEditingController();
  final _userPhoneController = TextEditingController();
  final _userEmailController = TextEditingController();
  
  // Controllers - Şifre
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isAdmin = false; // Admin mi normal kullanıcı mı?
  String? _logoUrl;
  String? _schoolId;
  String? _userId;
  Map<String, dynamic>? _schoolData;
  Map<String, dynamic>? _userData;
  
  // İstatistikler
  int studentCount = 0;
  int studentQuota = 0;
  bool isActive = false;
  int? remainingDays;
  String institutionId = '';

  @override
  void initState() {
    super.initState();
    _loadSchoolData();
  }

  @override
  void dispose() {
    _schoolNameController.dispose();
    _schoolAddressController.dispose();
    _schoolPhoneController.dispose();
    _schoolEmailController.dispose();
    _fullNameController.dispose();
    _userPhoneController.dispose();
    _userEmailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadSchoolData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final email = user.email!;
      final institutionId = email.split('@')[1].split('.')[0].toUpperCase();
      final username = email.split('@')[0]; // Kullanıcı adı

      // Okul bilgilerini al
      final schoolQuery = await FirebaseFirestore.instance
          .collection('schools')
          .where('institutionId', isEqualTo: institutionId)
          .limit(1)
          .get();

      if (schoolQuery.docs.isEmpty) {
        throw 'Okul bulunamadı!';
      }

      final schoolDoc = schoolQuery.docs.first;
      _schoolData = schoolDoc.data();
      _schoolId = schoolDoc.id;

      // Kullanıcı tipini kontrol et - users koleksiyonunda var mı?
      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: institutionId)
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      bool isAdmin = userQuery.docs.isEmpty; // users'da yoksa admin
      Map<String, dynamic>? userData;
      String? userId;

      if (!isAdmin) {
        // Normal kullanıcı - kendi bilgilerini yükle
        userData = userQuery.docs.first.data();
        userId = userQuery.docs.first.id;
        
        _fullNameController.text = userData['fullName'] ?? '';
        _userPhoneController.text = userData['phone'] ?? '';
        _userEmailController.text = userData['email'] ?? '';
        
        print('ℹ️ Normal kullanıcı: ${userData['fullName']}');
      } else {
        // Admin - okul bilgilerini yükle
        _schoolNameController.text = _schoolData!['schoolName'] ?? '';
        _schoolAddressController.text = _schoolData!['schoolAddress'] ?? '';
        _schoolPhoneController.text = _schoolData!['schoolPhone'] ?? '';
        _schoolEmailController.text = _schoolData!['schoolEmail'] ?? '';
        _logoUrl = _schoolData!['logoUrl'];

        // Öğrenci sayısını al (sadece admin için)
        final studentsQuery = await FirebaseFirestore.instance
            .collection('students')
            .where('institutionId', isEqualTo: institutionId)
            .get();

        // Lisans bitiş tarihi hesapla
        DateTime? licenseExpiresAt;
        if (_schoolData!['licenseExpiresAt'] != null) {
          licenseExpiresAt = (_schoolData!['licenseExpiresAt'] as Timestamp).toDate();
        }

        studentCount = studentsQuery.docs.length;
        studentQuota = _schoolData!['studentQuota'] ?? 0;
        isActive = _schoolData!['isActive'] ?? false;
        if (licenseExpiresAt != null) {
          remainingDays = licenseExpiresAt.difference(DateTime.now()).inDays;
        }
        
        print('ℹ️ Admin kullanıcısı: ${_schoolData!['schoolName']}');
      }

      setState(() {
        _isAdmin = isAdmin;
        _userData = userData;
        _userId = userId;
        this.institutionId = institutionId;
        _isLoading = false;
      });
    } catch (e) {
      print('Hata: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Veriler yüklenemedi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickLogo() async {
    // Web için basit file picker
    final uploadInput = html.FileUploadInputElement()..accept = 'image/*';
    uploadInput.click();

    uploadInput.onChange.listen((e) {
      final files = uploadInput.files;
      if (files!.isEmpty) return;

      final file = files[0];
      final reader = html.FileReader();

      reader.readAsDataUrl(file);
      reader.onLoadEnd.listen((e) {
        setState(() {
          _logoUrl = reader.result as String?;
        });
      });
    });
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      if (_isAdmin) {
        // ADMIN: Okul bilgilerini güncelle
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(_schoolId)
            .update({
          'schoolName': _schoolNameController.text.trim(),
          'schoolAddress': _schoolAddressController.text.trim(),
          'schoolPhone': _schoolPhoneController.text.trim(),
          'schoolEmail': _schoolEmailController.text.trim(),
          'logoUrl': _logoUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        print('✅ Okul bilgileri güncellendi');
      } else {
        // NORMAL KULLANICI: Kendi bilgilerini güncelle
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_userId)
            .update({
          'fullName': _fullNameController.text.trim(),
          'phone': _userPhoneController.text.trim(),
          'email': _userEmailController.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        print('✅ Kullanıcı bilgileri güncellendi');
      }

      // Şifre değişikliği (hem admin hem kullanıcı için)
      if (_newPasswordController.text.isNotEmpty) {
        final user = FirebaseAuth.instance.currentUser!;
        final credential = EmailAuthProvider.credential(
          email: user.email!,
          password: _currentPasswordController.text,
        );

        // Önce mevcut şifreyi doğrula
        await user.reauthenticateWithCredential(credential);
        
        // Yeni şifreyi ayarla
        await user.updatePassword(_newPasswordController.text);
        
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        print('✅ Şifre güncellendi');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Bilgileriniz başarıyla güncellendi!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Bir hata oluştu!';
      if (e.code == 'wrong-password') {
        message = 'Mevcut şifreniz hatalı!';
      } else if (e.code == 'weak-password') {
        message = 'Yeni şifre çok zayıf!';
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
            content: Text('Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.indigo),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Bilgilerimi Güncelle',
            style: TextStyle(
              color: Colors.grey.shade900,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.indigo),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Bilgilerimi Güncelle',
          style: TextStyle(
            color: Colors.grey.shade900,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // İstatistik Kartları - Sadece Admin için
                  if (_isAdmin) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            icon: Icons.check_circle,
                            iconColor: isActive ? Colors.green : Colors.red,
                            title: 'Durum',
                            value: isActive ? 'Aktif' : 'Pasif',
                            bgColor: isActive ? Colors.green.shade50 : Colors.red.shade50,
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: _buildStatCard(
                            icon: Icons.calendar_today,
                            iconColor: (remainingDays != null && remainingDays! > 30) ? Colors.blue : Colors.orange,
                            title: 'Lisans',
                            value: remainingDays != null ? '$remainingDays gün' : 'N/A',
                            bgColor: (remainingDays != null && remainingDays! > 30) ? Colors.blue.shade50 : Colors.orange.shade50,
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: _buildStatCard(
                            icon: Icons.people,
                            iconColor: Colors.purple,
                            title: 'Öğrenci',
                            value: '$studentCount/$studentQuota',
                            bgColor: Colors.purple.shade50,
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: _buildStatCard(
                            icon: Icons.badge,
                            iconColor: Colors.teal,
                            title: 'Kurum ID',
                            value: institutionId,
                            bgColor: Colors.teal.shade50,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 24),
                  ],

                  // Logo Bölümü - Sadece Admin için
                  if (_isAdmin) ...[
                    Text(
                      'Okul Logosu',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  SizedBox(height: 12),
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade400, width: 2),
                          ),
                          child: _logoUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    _logoUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(Icons.school, size: 64, color: Colors.grey);
                                    },
                                  ),
                                )
                              : Icon(Icons.school, size: 64, color: Colors.grey),
                        ),
                        SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _pickLogo,
                          icon: Icon(Icons.upload_file),
                          label: Text('Logo Yükle'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                    SizedBox(height: 32),

                    // Okul Bilgileri
                    Text(
                      'Okul Bilgileri',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    SizedBox(height: 16),

                    TextFormField(
                      controller: _schoolNameController,
                      decoration: _modernInputDecoration(label: 'Okul Adı', icon: Icons.school),
                      validator: (v) => v == null || v.isEmpty ? 'Okul adı gerekli' : null,
                    ),
                    SizedBox(height: 16),

                    TextFormField(
                      controller: _schoolAddressController,
                      decoration: _modernInputDecoration(label: 'Okul Adresi', icon: Icons.location_on),
                      maxLines: 2,
                    ),
                    SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _schoolPhoneController,
                            decoration: _modernInputDecoration(label: 'Telefon', icon: Icons.phone),
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _schoolEmailController,
                            decoration: _modernInputDecoration(label: 'E-posta', icon: Icons.email),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'E-posta gerekli';
                              if (!v.contains('@')) return 'Geçersiz e-posta';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 32),
                  ],

                  // Kullanıcı Bilgileri - Normal Kullanıcı için
                  if (!_isAdmin) ...[
                    Text(
                      'Kişisel Bilgilerim',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    SizedBox(height: 16),

                    TextFormField(
                      controller: _fullNameController,
                      decoration: _modernInputDecoration(label: 'Ad Soyad', icon: Icons.person),
                      validator: (v) => v == null || v.isEmpty ? 'Ad soyad gerekli' : null,
                    ),
                    SizedBox(height: 16),

                    TextFormField(
                      controller: _userPhoneController,
                      decoration: _modernInputDecoration(label: 'Telefon', icon: Icons.phone),
                    ),
                    SizedBox(height: 16),

                    TextFormField(
                      controller: _userEmailController,
                      decoration: _modernInputDecoration(label: 'E-posta (İletişim)', icon: Icons.email),
                    ),
                    SizedBox(height: 32),
                  ],

                  // Şifre Değiştirme
                  Text(
                    'Şifre Değiştir',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  SizedBox(height: 16),

                  TextFormField(
                    controller: _currentPasswordController,
                    obscureText: true,
                    decoration: _modernInputDecoration(label: 'Mevcut Şifre', icon: Icons.lock_outline),
                  ),
                  SizedBox(height: 16),

                  TextFormField(
                    controller: _newPasswordController,
                    obscureText: true,
                    decoration: _modernInputDecoration(label: 'Yeni Şifre', icon: Icons.lock),
                    validator: (v) {
                      if (v != null && v.isNotEmpty && v.length < 6) {
                        return 'Şifre en az 6 karakter olmalı';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 16),

                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    decoration: _modernInputDecoration(label: 'Yeni Şifre (Tekrar)', icon: Icons.lock),
                    validator: (v) {
                      if (_newPasswordController.text.isNotEmpty &&
                          v != _newPasswordController.text) {
                        return 'Şifreler eşleşmiyor';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 32),

                  // Kaydet Butonu
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveChanges,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSaving
                          ? SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'Değişiklikleri Kaydet',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Modern input decoration
  InputDecoration _modernInputDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.indigo),
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.indigo, width: 2),
      ),
    );
  }

  // Kompakt istatistik kartı
  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required Color bgColor,
  }) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: iconColor.withOpacity(0.2), width: 1),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 24),
          SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade900,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
