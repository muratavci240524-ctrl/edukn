import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:html' as html;
import 'dart:math' as math;
import '../../services/user_permission_service.dart';


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

  Map<String, bool> _notificationSettings = {
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
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('schools').doc(instId).get(),
        FirebaseFirestore.instance
            .collection('students')
            .where('institutionId', isEqualTo: instId)
            .get(),
      ]);

      final schoolDoc     = results[0] as DocumentSnapshot;
      final studentsSnap  = results[1] as QuerySnapshot;

      if (schoolDoc.exists && mounted) {
        final data = schoolDoc.data() as Map<String, dynamic>;
        _schoolData  = data;
        _schoolId    = schoolDoc.id;
        _schoolNameController.text    = data['schoolName'] ?? '';
        _schoolAddressController.text = data['schoolAddress'] ?? '';
        _schoolPhoneController.text   = data['schoolPhone'] ?? '';
        _schoolEmailController.text   = data['schoolEmail'] ?? '';
        _logoUrl      = data['logoUrl'];
        studentQuota  = data['studentQuota'] ?? 0;
        isActive      = data['isActive'] ?? false;
        studentCount  = studentsSnap.docs.length;
        if (data['licenseExpiresAt'] != null) {
          final expires = (data['licenseExpiresAt'] as Timestamp).toDate();
          remainingDays = expires.difference(DateTime.now()).inDays;
        }
        if (mounted) setState(() {});
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
          // Logo için direkt kaydet (kırpma yok)
          if (mounted) setState(() => _logoUrl = dataUrl);
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
          } catch (_) {}
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
      final naturalW = (img.naturalWidth ?? 100).toDouble();
      final naturalH = (img.naturalHeight ?? 100).toDouble();
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
                    color: Colors.indigo.withOpacity(0.15),
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
                              if (mounted) Navigator.pop(context, cropped);
                            } catch (e) {
                              if (mounted) Navigator.pop(context, null);
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
