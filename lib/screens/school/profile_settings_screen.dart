import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:html' as html;
import 'dart:math' as math;
import '../../services/user_permission_service.dart';
import '../../widgets/school_logo.dart';


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
    _loadSchoolData(); // Cache'den aninda yukler, ek query yok
  }

  final Map<String, bool> _notificationSettings = {
    'announcements': true,
    'studies': true,
    'homeworks': true,
    'messages': true,
    'exams': true,
  };



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
      // HIZLI YOL: AppBar zaten cache'ledi, 0 network call
      final cached = await UserPermissionService.loadUserData();

      if (cached != null && mounted) {
        final userId  = cached['id']?.toString();
        final instId  = cached['institutionId']?.toString().toUpperCase();
        final role    = cached['role']?.toString().toLowerCase();
        final isAdmin = (role == 'genel_mudur' || role == 'admin');

        _fullNameController.text  = cached['fullName'] ?? '';
        _userPhoneController.text = cached['phone'] ?? '';
        _userEmailController.text = cached['email'] ?? '';
        _profileImageUrl = cached['profileImageUrl'];

        // Bildirim ayarlarini da cache'den oku (ekstra query yok)
        if (cached.containsKey('notificationSettings')) {
          final raw = Map<String, dynamic>.from(cached['notificationSettings']);
          raw.forEach((key, value) {
            if (_notificationSettings.containsKey(key) && value is bool) {
              _notificationSettings[key] = value;
            }
          });
        }

        setState(() {
          _isAdmin = isAdmin;
          _userData = cached;
          _userId = userId;
          institutionId = instId ?? '';
          _isLoading = false; // Aninda yuklendi!
        });

        // Okul detaylari sadece okul ayarlari ekraninda lazim — arka planda getir
        if (instId != null && instId.isNotEmpty && widget.isSchoolSettings) {
          _loadSchoolDetails(instId);
        }
      } else {
        // Cache bossa (ilk acilista) fallback
        await _loadSchoolDataFallback();
      }
    } catch (e) {
      debugPrint('Profil yukleme hatasi: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Okul istatistiklerini paralel olarak getirir (okul ayarlari ekrani icin)
  Future<void> _loadSchoolDetails(String instId) async {
    try {
      final instIds = {instId, instId.toLowerCase(), instId.toUpperCase()}.toList();

      // 1) Okul dokümanı: institutionId alanıyla bul (doküman ID'si kurum kodu olmayabilir)
      DocumentSnapshot<Map<String, dynamic>>? schoolDoc;
      final byField = await FirebaseFirestore.instance
          .collection('schools')
          .where('institutionId', whereIn: instIds)
          .limit(1)
          .get();
      if (byField.docs.isNotEmpty) {
        schoolDoc = byField.docs.first;
      } else {
        // 2) Doküman ID'si kurum koduyla aynıysa
        final byId = await FirebaseFirestore.instance.collection('schools').doc(instId).get();
        if (byId.exists) {
          schoolDoc = byId;
        } else {
          // 3) Kullanıcı kaydındaki schoolId
          final sid = _userData?['schoolId']?.toString();
          if (sid != null && sid.isNotEmpty) {
            final bySchoolId = await FirebaseFirestore.instance.collection('schools').doc(sid).get();
            if (bySchoolId.exists) schoolDoc = bySchoolId;
          }
        }
      }

      // Öğrenci sayısı: sadece aktif öğrenciler
      final studentsSnap = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', whereIn: instIds)
          .get();
      final activeStudents = studentsSnap.docs.where((d) {
        final s = d.data();
        final status = (s['status'] ?? '').toString().toLowerCase();
        return s['isActive'] != false &&
            status != 'passive' &&
            status != 'pasif' &&
            status != 'inactive';
      }).length;

      if (schoolDoc != null && schoolDoc.exists && mounted) {
        final data = schoolDoc.data()!;
        _schoolData  = data;
        _schoolId    = schoolDoc.id;
        _schoolNameController.text    = (data['schoolName'] ?? data['name'] ?? '').toString();
        _schoolAddressController.text = (data['schoolAddress'] ?? data['address'] ?? '').toString();
        _schoolPhoneController.text   = (data['schoolPhone'] ?? data['phone'] ?? '').toString();
        _schoolEmailController.text   = (data['schoolEmail'] ?? data['email'] ?? '').toString();
        _logoUrl      = data['logoUrl']?.toString();
        studentQuota  = (data['studentQuota'] as num?)?.toInt() ?? 0;
        isActive      = data['isActive'] ?? false;
        studentCount  = activeStudents;
        final expiresRaw = data['licenseExpiresAt'];
        if (expiresRaw is Timestamp) {
          remainingDays = expiresRaw.toDate().difference(DateTime.now()).inDays;
        } else {
          remainingDays = null;
        }
        if (mounted) setState(() {});
      } else if (mounted) {
        studentCount = activeStudents;
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Okul kaydı bulunamadı.'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      debugPrint('Okul detay hatasi: $e');
    }
  }

  // Fallback: cache yoksa email ile arama
  Future<void> _loadSchoolDataFallback() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final searchEmail = user.email?.toLowerCase() ?? '';
      var q = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: searchEmail)
          .limit(1)
          .get();
      if (q.docs.isEmpty) {
        q = await FirebaseFirestore.instance
            .collection('users')
            .where('authEmail', isEqualTo: searchEmail)
            .limit(1)
            .get();
      }
      if (q.docs.isNotEmpty && mounted) {
        final data   = q.docs.first.data();
        final userId = q.docs.first.id;
        final instId = data['institutionId']?.toString().toUpperCase();
        final role   = data['role']?.toString().toLowerCase();
        _fullNameController.text  = data['fullName'] ?? '';
        _userPhoneController.text = data['phone'] ?? '';
        _userEmailController.text = data['email'] ?? '';
        _profileImageUrl = data['profileImageUrl'];
        if (data.containsKey('notificationSettings')) {
          final raw = Map<String, dynamic>.from(data['notificationSettings']);
          raw.forEach((key, value) {
            if (_notificationSettings.containsKey(key) && value is bool) {
              _notificationSettings[key] = value;
            }
          });
        }
        setState(() {
          _isAdmin = (role == 'genel_mudur' || role == 'admin');
          _userData = data;
          _userId = userId;
          institutionId = instId ?? '';
          _isLoading = false;
        });
        if (instId != null && widget.isSchoolSettings) {
          _loadSchoolDetails(instId);
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Fallback hatasi: $e');
      if (mounted) setState(() => _isLoading = false);
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
      reader.onLoadEnd.listen((e) async {
        final dataUrl = reader.result as String?;
        if (dataUrl == null) return;

        if (isLogo) {
          // Logo için yatay zoom/pan düzenleme ve kırpma dialogu aç
          if (!mounted) return;
          final croppedUrl = await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => LogoCropDialog(imageDataUrl: dataUrl),
          );
          if (croppedUrl != null && mounted) {
            setState(() => _logoUrl = croppedUrl);
          }
        } else {
          // Profil fotoğrafı için kırpma dialogu aç
          if (!mounted) return;
          final croppedUrl = await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => PhotoCropDialog(imageDataUrl: dataUrl),
          );
          if (croppedUrl != null && mounted) {
            setState(() => _profileImageUrl = croppedUrl);
          }
        }
      });
    });
  }

  /// Mevcut okul logosunu yeniden yakınlaştırıp/konumlandırmak için açar
  Future<void> _editCurrentLogo() async {
    if (_logoUrl == null || _logoUrl!.isEmpty) return;
    final croppedUrl = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => LogoCropDialog(imageDataUrl: _logoUrl!),
    );
    if (croppedUrl != null && mounted) {
      setState(() => _logoUrl = croppedUrl);
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      if (widget.isSchoolSettings) {
        // OKUL BİLGİLERİNİ GÜNCELLE
        if (_schoolId == null) {
          throw Exception('Okul kaydı bulunamadı, kaydedilemedi.');
        }
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
        // App bar'lardaki logo anında güncellensin
        SchoolLogoService.update(institutionId, _logoUrl);
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
            'notificationSettings': _notificationSettings,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        
        // Şifre güncelleme
        if (_newPasswordController.text.isNotEmpty) {
          if (_currentPasswordController.text.isEmpty) {
            throw Exception('Şifre değişikliği için mevcut şifrenizi girmelisiniz.');
          }
          if (_newPasswordController.text != _confirmPasswordController.text) {
            throw Exception('Yeni şifreler eşleşmiyor.');
          }
          if (_newPasswordController.text.length < 6) {
            throw Exception('Yeni şifre en az 6 karakter olmalıdır.');
          }
          final user = FirebaseAuth.instance.currentUser!;
          final credential = EmailAuthProvider.credential(
            email: user.email!,
            password: _currentPasswordController.text,
          );
          await user.reauthenticateWithCredential(credential);
          await user.updatePassword(_newPasswordController.text);
          try {
            await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
              'passwordStatus': 'degistirildi',
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            if (user.email != null) {
              final q = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: user.email).get();
              for (var d in q.docs) {
                await d.reference.set({'passwordStatus': 'degistirildi', 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
              }
            }
          } catch (silentError) { debugPrint('[profile_settings_screen] hata yutuldu: $silentError'); }
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
      appBar: EduknAppBar(
        title: title,
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
        const SizedBox(height: 4),
        Text(
          'Okul logosu başlık ve menülerde yatay olarak görüntülenir. Şeffaf PNG veya JPG yükleyebilirsiniz.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        Center(
          child: Column(
            children: [
              _buildImageFrame(_logoUrl, Icons.school, isLogo: true),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _pickImage(isLogo: true),
                    icon: const Icon(Icons.upload, size: 18),
                    label: Text(_logoUrl != null ? 'Yeni Logo Yükle' : 'Logo Yükle'),
                  ),
                  if (_logoUrl != null && _logoUrl!.isNotEmpty) ...[
                    OutlinedButton.icon(
                      onPressed: _editCurrentLogo,
                      icon: const Icon(Icons.tune, size: 18),
                      label: const Text('Yakınlaştır / Düzenle'),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() => _logoUrl = null);
                      },
                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      label: const Text('Logoyu Kaldır', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ],
              ),
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

        // ── Şifre Değiştirme ──────────────────────────────────────────
        SizedBox(height: 32),
        Row(
          children: [
            Icon(Icons.lock_outline, color: Colors.indigo, size: 20),
            SizedBox(width: 8),
            Text('Şifre Değiştir', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        SizedBox(height: 6),
        Text(
          'Şifrenizi değiştirmek istemiyorsanız boş bırakın.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        SizedBox(height: 16),
        _PasswordField(
          controller: _currentPasswordController,
          label: 'Mevcut Şifre',
          icon: Icons.lock_outline,
        ),
        SizedBox(height: 12),
        _PasswordField(
          controller: _newPasswordController,
          label: 'Yeni Şifre',
          icon: Icons.lock_reset,
          validator: (v) {
            if (v != null && v.isNotEmpty && v.length < 6) {
              return 'Şifre en az 6 karakter olmalıdır';
            }
            return null;
          },
        ),
        SizedBox(height: 12),
        _PasswordField(
          controller: _confirmPasswordController,
          label: 'Yeni Şifre (Tekrar)',
          icon: Icons.lock_reset,
          validator: (v) {
            if (_newPasswordController.text.isNotEmpty && v != _newPasswordController.text) {
              return 'Şifreler eşleşmiyor';
            }
            return null;
          },
        ),

        // ── Bildirim Tercihleri ────────────────────────────
        const SizedBox(height: 32),
        const Text('Bildirim Tercihleri', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _buildNotificationToggle('announcements', 'Duyurular', Icons.campaign_outlined),
        _buildNotificationToggle('studies', 'Etüt ve Ek Dersler', Icons.school_outlined),
        _buildNotificationToggle('homeworks', 'Ödevler', Icons.assignment_outlined),
        _buildNotificationToggle('messages', 'Mesajlar', Icons.forum_outlined),
        _buildNotificationToggle('exams', 'Sınav Sonuçları', Icons.analytics_outlined),

        SizedBox(height: 32),
        _buildSaveButton(),
      ],
    );
  }


  Widget _buildImageFrame(String? url, IconData fallbackIcon, {bool isCircle = false, bool isLogo = false}) {
    final double w = isLogo ? 320 : 120;
    final double h = isLogo ? 110 : 120;
    return Container(
      width: w,
      height: h,
      padding: isLogo ? const EdgeInsets.all(10) : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: isLogo ? const Color(0xFFF8FAFC) : Colors.grey.shade100,
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(16),
        border: Border.all(
          color: isLogo ? Colors.indigo.shade100 : Colors.grey.shade300,
          width: 2,
        ),
        boxShadow: isLogo
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                )
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: isCircle ? BorderRadius.circular(60) : BorderRadius.circular(12),
        child: url != null && url.isNotEmpty
            ? Image.network(
                url,
                fit: isLogo ? BoxFit.contain : BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(fallbackIcon, size: isLogo ? 36 : 48, color: Colors.grey),
                ),
              )
            : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(fallbackIcon, size: isLogo ? 32 : 48, color: Colors.grey.shade400),
                    if (isLogo) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Henüz logo yüklenmedi (varsayılan eduKN logosu kullanılır)',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
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
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: iconColor.withValues(alpha: 0.2))),
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
      activeThumbColor: Colors.indigo,
      contentPadding: EdgeInsets.zero,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// ŞİFRE ALANI — göz ikonuyla görünürlük toggle
// ─────────────────────────────────────────────────────────────────────
class _PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? Function(String?)? validator;

  const _PasswordField({
    required this.controller,
    required this.label,
    required this.icon,
    this.validator,
  });

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: Icon(widget.icon, color: Colors.indigo),
        suffixIcon: IconButton(
          icon: Icon(
            _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: Colors.grey.shade500,
            size: 20,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
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
          borderSide: const BorderSide(color: Colors.indigo, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// FOTOĞRAF KIRPMA & KONUMLANDIRMA DİALOGU
// ─────────────────────────────────────────────────────────────────────
class PhotoCropDialog extends StatefulWidget {
  final String imageDataUrl;
  const PhotoCropDialog({Key? key, required this.imageDataUrl}) : super(key: key);

  @override
  State<PhotoCropDialog> createState() => _PhotoCropDialogState();
}

class _PhotoCropDialogState extends State<PhotoCropDialog> {
  static const double _cropSize = 280.0;

  double _imgNaturalWidth = 0;
  double _imgNaturalHeight = 0;
  double _scale = 1.0;       // mevcut zoom
  Offset _offset = Offset.zero; // görüntü kayması (piksel)
  Offset _dragStart = Offset.zero;
  Offset _offsetAtDragStart = Offset.zero;
  bool _ready = false;
  bool _isCropping = false;

  @override
  void initState() {
    super.initState();
    _loadImageDimensions();
  }

  void _loadImageDimensions() {
    final img = html.ImageElement()..src = widget.imageDataUrl;
    img.onLoad.listen((_) {
      final naturalW = (img.naturalWidth).toDouble();
      final naturalH = (img.naturalHeight).toDouble();
      // Görüntü daireyi tam kapatsın diye başlangıç scale hesapla
      final scaleX = _cropSize / naturalW;
      final scaleY = _cropSize / naturalH;
      final initialScale = math.max(scaleX, scaleY);
      if (mounted) {
        setState(() {
          _imgNaturalWidth = naturalW;
          _imgNaturalHeight = naturalH;
          _scale = initialScale;
          _offset = Offset.zero;
          _ready = true;
        });
      }
    });
  }

  Offset _clamp(Offset offset) {
    if (_imgNaturalWidth == 0) return offset;
    final scaledW = _imgNaturalWidth * _scale;
    final scaledH = _imgNaturalHeight * _scale;
    final maxDx = math.max(0.0, (scaledW - _cropSize) / 2);
    final maxDy = math.max(0.0, (scaledH - _cropSize) / 2);
    return Offset(
      offset.dx.clamp(-maxDx, maxDx),
      offset.dy.clamp(-maxDy, maxDy),
    );
  }

  Future<String> _renderCroppedImage() async {
    const int outSize = 400; // çıktı piksel boyutu
    final canvas = html.CanvasElement(width: outSize, height: outSize);
    final ctx = canvas.context2D;

    final img = html.ImageElement()..src = widget.imageDataUrl;
    await img.onLoad.first;

    // Dairesel clip
    ctx.beginPath();
    ctx.arc(outSize / 2, outSize / 2, outSize / 2, 0, 2 * math.pi);
    ctx.clip();

    // Görüntü konumunu hesapla:
    // offset = (0,0) → görüntü tam ortada
    final scaledW = _imgNaturalWidth * _scale;
    final scaledH = _imgNaturalHeight * _scale;
    final imgLeft = (_cropSize - scaledW) / 2 + _offset.dx; // crop alanındaki sol kenar
    final imgTop  = (_cropSize - scaledH) / 2 + _offset.dy; // crop alanındaki üst kenar

    // Kaynak dikdörtgeni (orijinal görüntü koordinatlarında)
    final srcX = -imgLeft / _scale;
    final srcY = -imgTop  / _scale;
    final srcW = _cropSize / _scale;
    final srcH = _cropSize / _scale;

    ctx.drawImageScaledFromSource(
      img,
      srcX.clamp(0, _imgNaturalWidth),
      srcY.clamp(0, _imgNaturalHeight),
      srcW.clamp(0, _imgNaturalWidth - srcX.clamp(0, _imgNaturalWidth)),
      srcH.clamp(0, _imgNaturalHeight - srcY.clamp(0, _imgNaturalHeight)),
      0, 0, outSize.toDouble(), outSize.toDouble(),
    );

    return canvas.toDataUrl('image/jpeg', 0.88);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Başlık
            Row(
              children: [
                const Icon(Icons.crop_rounded, color: Colors.indigo, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Fotoğrafı Konumlandır',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context, null),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Fotoğrafı sürükleyerek yüzünüzü ortala. + / − ile yakınlaştır.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Dairesel kırpma alanı
            Container(
              width: _cropSize,
              height: _cropSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.indigo, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.indigo.withValues(alpha: 0.15),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipOval(
                child: !_ready
                    ? const Center(child: CircularProgressIndicator())
                    : GestureDetector(
                        onPanStart: (d) {
                          _dragStart = d.localPosition;
                          _offsetAtDragStart = _offset;
                        },
                        onPanUpdate: (d) {
                          final delta = d.localPosition - _dragStart;
                          setState(() {
                            _offset = _clamp(_offsetAtDragStart + delta);
                          });
                        },
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Gri arka plan
                            Container(color: Colors.grey.shade200),
                            // Görüntü
                            Transform.translate(
                              offset: _offset,
                              child: Image.network(
                                widget.imageDataUrl,
                                width: _imgNaturalWidth * _scale,
                                height: _imgNaturalHeight * _scale,
                                fit: BoxFit.fill,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 16),

            // Zoom kontrolleri
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // — küçült butonu
                Material(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _ready ? () {
                      final minScale = math.max(_cropSize / _imgNaturalWidth, _cropSize / _imgNaturalHeight);
                      final step = (minScale * 3 - minScale) / 10;
                      setState(() {
                        _scale = math.max(minScale, _scale - step);
                        _offset = _clamp(_offset);
                      });
                    } : null,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.remove, color: Colors.indigo, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: _scale,
                    min: _ready ? math.max(_cropSize / _imgNaturalWidth, _cropSize / _imgNaturalHeight) : 0.5,
                    max: _ready ? math.max(_cropSize / _imgNaturalWidth, _cropSize / _imgNaturalHeight) * 3 : 3.0,
                    activeColor: Colors.indigo,
                    onChanged: (v) {
                      setState(() {
                        _scale = v;
                        _offset = _clamp(_offset);
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // + büyüt butonu
                Material(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _ready ? () {
                      final minScale = math.max(_cropSize / _imgNaturalWidth, _cropSize / _imgNaturalHeight);
                      final step = (minScale * 3 - minScale) / 10;
                      setState(() {
                        _scale = math.min(minScale * 3, _scale + step);
                        _offset = _clamp(_offset);
                      });
                    } : null,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.add, color: Colors.indigo, size: 20),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Butonlar
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, null),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('İptal'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isCropping
                        ? null
                        : () async {
                            setState(() => _isCropping = true);
                            try {
                              final cropped = await _renderCroppedImage();
                              if (mounted) Navigator.of(context).pop(cropped);
                            } catch (e) {
                              if (mounted) Navigator.of(context).pop(null);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isCropping
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Uygula', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// ŞEFFAFLIK DAMA DESENİ (CHECKERBOARD)
// ─────────────────────────────────────────────────────────────────────
class _CheckerboardPainter extends CustomPainter {
  const _CheckerboardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const double cellSize = 12.0;
    final paint1 = Paint()..color = const Color(0xFFF1F5F9);
    final paint2 = Paint()..color = const Color(0xFFE2E8F0);
    canvas.drawRect(Offset.zero & size, paint1);
    for (double y = 0; y < size.height; y += cellSize) {
      for (double x = 0; x < size.width; x += cellSize) {
        final isEven = ((x / cellSize).floor() + (y / cellSize).floor()) % 2 == 0;
        if (!isEven) {
          canvas.drawRect(Rect.fromLTWH(x, y, cellSize, cellSize), paint2);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerboardPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────
// OKUL LOGOSU DÜZENLEME & KIRPMA DİALOGU (YATAY / GENİŞ FORMAT VE ZOOM)
// ─────────────────────────────────────────────────────────────────────
class LogoCropDialog extends StatefulWidget {
  final String imageDataUrl;
  const LogoCropDialog({Key? key, required this.imageDataUrl}) : super(key: key);

  @override
  State<LogoCropDialog> createState() => _LogoCropDialogState();
}

class _LogoCropDialogState extends State<LogoCropDialog> {
  // En-boy oranı modları: 0: Yatay Geniş (2.6:1 - App Bar formatı), 1: Standart (16:9), 2: Kare (1:1)
  int _aspectRatioIndex = 0;

  double get _cropWidth {
    switch (_aspectRatioIndex) {
      case 0: return 360.0; // Yatay Geniş
      case 1: return 360.0; // 16:9
      case 2: return 240.0; // Kare
      default: return 360.0;
    }
  }

  double get _cropHeight {
    switch (_aspectRatioIndex) {
      case 0: return 138.0; // 360 / 2.6
      case 1: return 202.0; // 360 / (16/9)
      case 2: return 240.0; // 240 / 1
      default: return 138.0;
    }
  }

  double _imgNaturalWidth = 0;
  double _imgNaturalHeight = 0;
  double _scale = 1.0;
  double _minScale = 0.05;
  double _maxScale = 4.0;
  Offset _offset = Offset.zero;
  Offset _dragStart = Offset.zero;
  Offset _offsetAtDragStart = Offset.zero;
  bool _ready = false;
  bool _isCropping = false;
  bool _darkPreview = false; // Koyu zemin üzerinde önizleme modu

  @override
  void initState() {
    super.initState();
    _loadImageDimensions();
  }

  void _loadImageDimensions() {
    final img = html.ImageElement()..src = widget.imageDataUrl;
    img.onLoad.listen((_) {
      final naturalW = (img.naturalWidth).toDouble();
      final naturalH = (img.naturalHeight).toDouble();
      _setupInitialScale(naturalW, naturalH);
    });
  }

  void _setupInitialScale(double naturalW, double naturalH) {
    // Logoyu kırpma kutusuna tam sığdıracak ölçek (%5 iç boşlukla)
    final scaleX = _cropWidth / naturalW;
    final scaleY = _cropHeight / naturalH;
    final fitScale = math.min(scaleX, scaleY) * 0.95;

    if (mounted) {
      setState(() {
        _imgNaturalWidth = naturalW;
        _imgNaturalHeight = naturalH;
        _minScale = math.max(0.05, fitScale * 0.25);
        _maxScale = math.max(fitScale * 4.5, 3.0);
        _scale = fitScale;
        _offset = Offset.zero;
        _ready = true;
      });
    }
  }

  void _fitAndCenter() {
    if (_imgNaturalWidth == 0 || _imgNaturalHeight == 0) return;
    final scaleX = _cropWidth / _imgNaturalWidth;
    final scaleY = _cropHeight / _imgNaturalHeight;
    final fitScale = math.min(scaleX, scaleY) * 0.95;
    setState(() {
      _scale = fitScale;
      _offset = Offset.zero;
    });
  }

  Offset _clamp(Offset offset) {
    if (_imgNaturalWidth == 0) return offset;
    final scaledW = _imgNaturalWidth * _scale;
    final scaledH = _imgNaturalHeight * _scale;

    // Kullanıcının logoyu serbestçe kutu içinde kaydırmasına izin ver
    final maxDx = math.max(scaledW, _cropWidth) / 1.5;
    final maxDy = math.max(scaledH, _cropHeight) / 1.5;
    return Offset(
      offset.dx.clamp(-maxDx, maxDx),
      offset.dy.clamp(-maxDy, maxDy),
    );
  }

  Future<String> _renderCroppedImage() async {
    final double cropW = _cropWidth;
    final double cropH = _cropHeight;
    // Çıktı boyutu: 2 katı (Retina için keskin), maksimum genişlik 720
    final double scaleFactor = math.min(2.0, 720.0 / cropW);
    final int outW = (cropW * scaleFactor).round();
    final int outH = (cropH * scaleFactor).round();

    final canvas = html.CanvasElement(width: outW, height: outH);
    final ctx = canvas.context2D;

    final img = html.ImageElement()..src = widget.imageDataUrl;
    await img.onLoad.first;

    // Şeffaf arka planı temizle
    ctx.clearRect(0, 0, outW, outH);

    // Ekranda görünen göreli konumu hesapla
    final scaledW = _imgNaturalWidth * _scale;
    final scaledH = _imgNaturalHeight * _scale;
    final imgLeft = (cropW - scaledW) / 2 + _offset.dx;
    final imgTop = (cropH - scaledH) / 2 + _offset.dy;

    ctx.drawImageScaled(
      img,
      imgLeft * scaleFactor,
      imgTop * scaleFactor,
      scaledW * scaleFactor,
      scaledH * scaleFactor,
    );

    return canvas.toDataUrl('image/png');
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Başlık
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.tune, color: Colors.indigo, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Okul Logosunu Düzenle',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Yatayda konumlandırın, yakınlaştırıp uzaklaştırın.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context, null),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Oran Seçimi & Zemin Seçimi
              Row(
                children: [
                  const Text('Format:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Yatay Geniş')),
                        ButtonSegment(value: 1, label: Text('16:9')),
                        ButtonSegment(value: 2, label: Text('Kare (1:1)')),
                      ],
                      selected: {_aspectRatioIndex},
                      onSelectionChanged: (val) {
                        setState(() {
                          _aspectRatioIndex = val.first;
                          _offset = _clamp(_offset);
                        });
                      },
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: _darkPreview ? 'Açık Zemin' : 'Koyu Zemin Önizleme',
                    child: IconButton(
                      icon: Icon(_darkPreview ? Icons.light_mode : Icons.dark_mode, size: 20),
                      color: Colors.indigo,
                      onPressed: () => setState(() => _darkPreview = !_darkPreview),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Kırpma Alanı (Canvas / Sürükleme)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _cropWidth,
                height: _cropHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.indigo, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.indigo.withValues(alpha: 0.15),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9.5),
                  child: !_ready
                      ? const Center(child: CircularProgressIndicator())
                      : GestureDetector(
                          onPanStart: (d) {
                            _dragStart = d.localPosition;
                            _offsetAtDragStart = _offset;
                          },
                          onPanUpdate: (d) {
                            final delta = d.localPosition - _dragStart;
                            setState(() {
                              _offset = _clamp(_offsetAtDragStart + delta);
                            });
                          },
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Arka plan: Dama deseni veya Koyu zemin
                              Positioned.fill(
                                child: _darkPreview
                                    ? Container(color: const Color(0xFF1E293B))
                                    : CustomPaint(painter: const _CheckerboardPainter()),
                              ),
                              // Görüntü
                              Transform.translate(
                                offset: _offset,
                                child: Image.network(
                                  widget.imageDataUrl,
                                  width: _imgNaturalWidth * _scale,
                                  height: _imgNaturalHeight * _scale,
                                  fit: BoxFit.fill,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 14),

              // Zoom kontrolleri (+ / - ve Slider ve Sığdır butonu)
              Row(
                children: [
                  Material(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _ready
                          ? () {
                              final step = (_maxScale - _minScale) / 15;
                              setState(() {
                                _scale = math.max(_minScale, _scale - step);
                                _offset = _clamp(_offset);
                              });
                            }
                          : null,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.remove, color: Colors.indigo, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Slider(
                      value: _scale.clamp(_minScale, _maxScale),
                      min: _minScale,
                      max: _maxScale,
                      activeColor: Colors.indigo,
                      onChanged: (v) {
                        setState(() {
                          _scale = v;
                          _offset = _clamp(_offset);
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _ready
                          ? () {
                              final step = (_maxScale - _minScale) / 15;
                              setState(() {
                                _scale = math.min(_maxScale, _scale + step);
                                _offset = _clamp(_offset);
                              });
                            }
                          : null,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.add, color: Colors.indigo, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton.icon(
                    onPressed: _ready ? _fitAndCenter : null,
                    icon: const Icon(Icons.filter_center_focus, size: 16),
                    label: const Text('Ortala & Sığdır', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),
              Text(
                'İpucu: Logoyu fare ile tutarak istediğiniz konuma sürükleyebilirsiniz.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),

              const SizedBox(height: 20),

              // Butonlar
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, null),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('İptal'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isCropping
                          ? null
                          : () async {
                              setState(() => _isCropping = true);
                              try {
                                final cropped = await _renderCroppedImage();
                                if (mounted) Navigator.of(context).pop(cropped);
                              } catch (e) {
                                debugPrint('Crop error: $e');
                                if (mounted) Navigator.of(context).pop(null);
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isCropping
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'Logoyu Uygula',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
