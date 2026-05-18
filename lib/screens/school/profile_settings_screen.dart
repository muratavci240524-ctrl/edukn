import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:html' as html;

class ProfileSettingsScreen extends StatefulWidget {
  final bool isSchoolSettings; // Okul bilgileri mi yoksa kişisel profil mi?
  const ProfileSettingsScreen({Key? key, this.isSchoolSettings = false}) : super(key: key);

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
  bool _isAdmin = false;
  String? _logoUrl; // Okul Logosu
  String? _profileImageUrl; // Kişisel Profil Fotoğrafı
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
    _loadNotificationSettings();
  }

  Map<String, bool> _notificationSettings = {
    'announcements': true,
    'studies': true,
    'homeworks': true,
    'messages': true,
    'exams': true,
  };

  Future<void> _loadNotificationSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (userDoc.exists) {
      final data = userDoc.data();
      if (data != null && data.containsKey('notificationSettings')) {
        setState(() {
          final settings = Map<String, dynamic>.from(data['notificationSettings']);
          settings.forEach((key, value) {
            _notificationSettings[key] = value as bool;
          });
        });
      }
    }
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

      final originalEmail = user.email!;
      final searchEmail = originalEmail.toLowerCase();
      
      Map<String, dynamic>? userData;
      String? userId;
      String? currentInstitutionId;

      // --- ÇOK AŞAMALI AKILLI ARAMA ---
      
      // 1. Aşama: Standart Email Araması
      var userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: searchEmail)
          .limit(1)
          .get();

      // 2. Aşama: authEmail Araması (Username girişi için)
      if (userQuery.docs.isEmpty) {
        userQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('authEmail', isEqualTo: searchEmail)
            .limit(1)
            .get();
      }

      // 3. Aşama: Username Araması (Sistem mailinden username ayıklayarak)
      if (userQuery.docs.isEmpty && searchEmail.contains('.edukn')) {
        final extractedUsername = searchEmail.split('@')[0];
        userQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('username', isEqualTo: extractedUsername)
            .limit(1)
            .get();
      }

      // 4. Aşama: Orijinal Mail Araması (Case-sensitive eski kayıtlar için)
      if (userQuery.docs.isEmpty && originalEmail != searchEmail) {
        userQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: originalEmail)
            .limit(1)
            .get();
      }

      bool isAdmin = false;

      if (userQuery.docs.isNotEmpty) {
        userData = userQuery.docs.first.data();
        userId = userQuery.docs.first.id;
        currentInstitutionId = userData['institutionId']?.toString().toUpperCase();
        
        _fullNameController.text = userData['fullName'] ?? '';
        _userPhoneController.text = userData['phone'] ?? '';
        _userEmailController.text = userData['email'] ?? '';
        _profileImageUrl = userData['profileImageUrl'];
        
        // Rol kontrolü
        final role = userData['role']?.toString().toLowerCase();
        isAdmin = (role == 'genel_mudur' || role == 'admin');
        
        print('✅ Profil bulundu: ${_fullNameController.text}');
      } else {
        print('⚠️ Profil belgesi bulunamadı. Aranan: $searchEmail');
      }

      // 2. Okul verilerini yükle (Eğer kurum ID varsa ve mod aktifse)
      if (currentInstitutionId != null) {
        final schoolDoc = await FirebaseFirestore.instance
            .collection('schools')
            .doc(currentInstitutionId)
            .get();

        if (schoolDoc.exists) {
          _schoolData = schoolDoc.data();
          _schoolId = schoolDoc.id;

          _schoolNameController.text = _schoolData!['schoolName'] ?? '';
          _schoolAddressController.text = _schoolData!['schoolAddress'] ?? '';
          _schoolPhoneController.text = _schoolData!['schoolPhone'] ?? '';
          _schoolEmailController.text = _schoolData!['schoolEmail'] ?? '';
          _logoUrl = _schoolData!['logoUrl'];

          // İstatistikler
          final studentsQuery = await FirebaseFirestore.instance
              .collection('students')
              .where('institutionId', isEqualTo: currentInstitutionId)
              .get();
          studentCount = studentsQuery.docs.length;
          
          studentQuota = _schoolData!['studentQuota'] ?? 0;
          isActive = _schoolData!['isActive'] ?? false;
          
          if (_schoolData!['licenseExpiresAt'] != null) {
            final expires = (_schoolData!['licenseExpiresAt'] as Timestamp).toDate();
            remainingDays = expires.difference(DateTime.now()).inDays;
          }
        }
      }

      setState(() {
        _isAdmin = isAdmin;
        _userData = userData;
        _userId = userId;
        this.institutionId = currentInstitutionId ?? '';
        _isLoading = false;
      });
    } catch (e) {
      print('Hata: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage({bool isLogo = true}) async {
    final uploadInput = html.FileUploadInputElement()..accept = 'image/*';
    uploadInput.click();

    uploadInput.onChange.listen((e) {
      final files = uploadInput.files;
      if (files!.isEmpty) return;

      final reader = html.FileReader();
      reader.readAsDataUrl(files[0]);
      reader.onLoadEnd.listen((e) {
        setState(() {
          if (isLogo) {
            _logoUrl = reader.result as String?;
          } else {
            _profileImageUrl = reader.result as String?;
          }
        });
      });
    });
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      if (widget.isSchoolSettings) {
        // OKUL BİLGİLERİNİ GÜNCELLE
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
      } else {
        // KİŞİSEL PROFİLİ GÜNCELLE
        if (_userId != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(_userId)
              .update({
            'fullName': _fullNameController.text.trim(),
            'phone': _userPhoneController.text.trim(),
            'email': _userEmailController.text.trim(),
            'profileImageUrl': _profileImageUrl,
            'updatedAt': FieldValue.serverTimestamp(),
            'notificationSettings': _notificationSettings,
          });
        }
        
        // Şifre güncelleme
        if (_newPasswordController.text.isNotEmpty) {
          final user = FirebaseAuth.instance.currentUser!;
          final credential = EmailAuthProvider.credential(
            email: user.email!,
            password: _currentPasswordController.text,
          );
          await user.reauthenticateWithCredential(credential);
          await user.updatePassword(_newPasswordController.text);
          _currentPasswordController.clear();
          _newPasswordController.clear();
          _confirmPasswordController.clear();
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Bilgiler başarıyla güncellendi!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final String title = widget.isSchoolSettings ? 'Okul Bilgileri' : 'Profilim';

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.indigo),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(title, style: TextStyle(color: Colors.grey.shade900, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: widget.isSchoolSettings ? _buildSchoolSection() : _buildProfileSection(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSchoolSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // İstatistikler
        Row(
          children: [
            Expanded(child: _buildStatCard(icon: Icons.check_circle, iconColor: isActive ? Colors.green : Colors.red, title: 'Durum', value: isActive ? 'Aktif' : 'Pasif', bgColor: isActive ? Colors.green.shade50 : Colors.red.shade50)),
            SizedBox(width: 8),
            Expanded(child: _buildStatCard(icon: Icons.calendar_today, iconColor: Colors.blue, title: 'Lisans', value: remainingDays != null ? '$remainingDays gün' : 'N/A', bgColor: Colors.blue.shade50)),
            SizedBox(width: 8),
            Expanded(child: _buildStatCard(icon: Icons.people, iconColor: Colors.purple, title: 'Öğrenci', value: '$studentCount/$studentQuota', bgColor: Colors.purple.shade50)),
            SizedBox(width: 8),
            Expanded(child: _buildStatCard(icon: Icons.badge, iconColor: Colors.teal, title: 'Kurum ID', value: institutionId, bgColor: Colors.teal.shade50)),
          ],
        ),
        SizedBox(height: 32),
        Text('Okul Logosu', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        SizedBox(height: 12),
        Center(
          child: Column(
            children: [
              _buildImageFrame(_logoUrl, Icons.school),
              SizedBox(height: 12),
              ElevatedButton.icon(onPressed: () => _pickImage(isLogo: true), icon: Icon(Icons.upload), label: Text('Logo Değiştir')),
            ],
          ),
        ),
        SizedBox(height: 24),
        TextFormField(controller: _schoolNameController, decoration: _modernInputDecoration(label: 'Okul Adı', icon: Icons.business)),
        SizedBox(height: 16),
        TextFormField(controller: _schoolAddressController, decoration: _modernInputDecoration(label: 'Adres', icon: Icons.location_on), maxLines: 2),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: TextFormField(controller: _schoolPhoneController, decoration: _modernInputDecoration(label: 'Telefon', icon: Icons.phone))),
            SizedBox(width: 16),
            Expanded(child: TextFormField(controller: _schoolEmailController, decoration: _modernInputDecoration(label: 'E-posta', icon: Icons.email))),
          ],
        ),
        SizedBox(height: 32),
        _buildSaveButton(),
      ],
    );
  }

  Widget _buildProfileSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Profil Fotoğrafı', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        SizedBox(height: 12),
        Center(
          child: Column(
            children: [
              _buildImageFrame(_profileImageUrl, Icons.person, isCircle: true),
              SizedBox(height: 12),
              ElevatedButton.icon(onPressed: () => _pickImage(isLogo: false), icon: Icon(Icons.camera_alt), label: Text('Fotoğrafı Değiştir')),
            ],
          ),
        ),
        SizedBox(height: 24),
        TextFormField(controller: _fullNameController, decoration: _modernInputDecoration(label: 'Ad Soyad', icon: Icons.person)),
        SizedBox(height: 16),
        TextFormField(controller: _userPhoneController, decoration: _modernInputDecoration(label: 'Telefon', icon: Icons.phone)),
        SizedBox(height: 16),
        TextFormField(controller: _userEmailController, decoration: _modernInputDecoration(label: 'E-posta (İletişim)', icon: Icons.email)),
        SizedBox(height: 32),
        const SizedBox(height: 32),
        const Text('Bildirim Tercihleri', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _buildNotificationToggle('announcements', 'Duyurular', Icons.campaign_outlined),
        _buildNotificationToggle('studies', 'Etüt ve Ek Dersler', Icons.school_outlined),
        _buildNotificationToggle('homeworks', 'Ödevler', Icons.assignment_outlined),
        _buildNotificationToggle('messages', 'Mesajlar', Icons.forum_outlined),
        _buildNotificationToggle('exams', 'Sınav Sonuçları', Icons.analytics_outlined),
        const SizedBox(height: 32),
        _buildSaveButton(),
      ],
    );
  }

  Widget _buildImageFrame(String? url, IconData fallbackIcon, {bool isCircle = false}) {
    return Container(
      width: 120, height: 120,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300, width: 2),
      ),
      child: ClipRRect(
        borderRadius: isCircle ? BorderRadius.circular(60) : BorderRadius.circular(14),
        child: url != null && url.isNotEmpty
            ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(fallbackIcon, size: 48, color: Colors.grey))
            : Icon(fallbackIcon, size: 48, color: Colors.grey),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity, height: 50,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveChanges,
        style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        child: _isSaving ? CircularProgressIndicator(color: Colors.white) : Text('Değişiklikleri Kaydet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  InputDecoration _modernInputDecoration({required String label, required IconData icon}) {
    return InputDecoration(
      labelText: label, prefixIcon: Icon(icon, color: Colors.indigo),
      filled: true, fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.indigo, width: 2)),
    );
  }

  Widget _buildStatCard({required IconData icon, required Color iconColor, required String title, required String value, required Color bgColor}) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: iconColor.withOpacity(0.2))),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 20),
          SizedBox(height: 4),
          Text(title, style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildNotificationToggle(String key, String title, IconData icon) {
    return SwitchListTile(
      value: _notificationSettings[key] ?? true,
      onChanged: (val) => setState(() => _notificationSettings[key] = val),
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      secondary: Icon(icon, color: Colors.indigo, size: 20),
      activeColor: Colors.indigo,
      contentPadding: EdgeInsets.zero,
    );
  }
}
