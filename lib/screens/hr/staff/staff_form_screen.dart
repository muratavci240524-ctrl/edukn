import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../firebase_options.dart';

class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class StaffFormScreen extends StatefulWidget {
  final String? staffId;
  final Map<String, dynamic>? staffData;
  final String? fixedSchoolTypeName; // Okul türü içinden ekleniyorsa

  const StaffFormScreen({
    super.key, 
    this.staffId, 
    this.staffData,
    this.fixedSchoolTypeName,
  });

  @override
  State<StaffFormScreen> createState() => _StaffFormScreenState();
}

class _StaffFormScreenState extends State<StaffFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _tcController = TextEditingController();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _birthDateController = TextEditingController();
  final TextEditingController _birthPlaceController = TextEditingController();
  final TextEditingController _nationalityController = TextEditingController();
  final TextEditingController _corporateEmailController =
      TextEditingController();
  final TextEditingController _personalEmailController =
      TextEditingController();
  final TextEditingController _mobilePhoneController = TextEditingController();
  final TextEditingController _homePhoneController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _districtController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _emergencyNameController =
      TextEditingController();
  final TextEditingController _emergencyPhoneController =
      TextEditingController();
  final TextEditingController _photoUrlController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String? _gender;
  String? _maritalStatus;
  String? _bloodGroup;
  String? _title; // Ünvan için değişken
  String? _branch; // Branş için değişken (sadece öğretmenler için)

  bool _isSaving = false;
  String? _institutionId;
  
  // Dinamik branş listesi
  List<String> _branchList = [];
  
  // Varsayılan branşlar
  static const List<String> _defaultBranches = [
    'Almanca', 'Arapça', 'Beden Eğitimi ve Spor', 'Bilişim Teknolojileri ve Yazılım',
    'Biyoloji', 'Coğrafya', 'Din Kültürü ve Ahlak Bilgisi', 'Felsefe', 'Fen Bilimleri',
    'Fizik', 'Fransızca', 'Görsel Sanatlar', 'İlköğretim Matematik', 'İngilizce',
    'İspanyolca', 'Kimya', 'Kulüp', 'Matematik', 'Müzik', 'Okul Öncesi', 'Özel Eğitim',
    'Rehberlik ve Psikolojik Danışmanlık', 'Rusça', 'Sınıf Öğretmenliği', 'Sosyal Bilgiler',
    'Tarih', 'Teknoloji ve Tasarım', 'Türk Dili ve Edebiyatı', 'Türkçe',
  ];

  @override
  void initState() {
    super.initState();
    // Önce varsayılan branşları yükle
    _branchList = List<String>.from(_defaultBranches)..sort();
    _loadInstitutionId(); // Bu metod içinde _loadBranches() çağrılıyor
    if (widget.staffData != null) {
      _populateForm(widget.staffData!);
    }
  }
  
  Future<void> _loadBranches() async {
    final allBranches = Set<String>.from(_defaultBranches);
    
    // Firestore'dan özel branşları ekle
    if (_institutionId != null) {
      try {
        final customBranches = await FirebaseFirestore.instance
            .collection('branches')
            .where('institutionId', isEqualTo: _institutionId)
            .where('isActive', isEqualTo: true)
            .get();

        for (var doc in customBranches.docs) {
          final name = doc.data()['branchName'] as String?;
          if (name != null && name.isNotEmpty) {
            allBranches.add(name);
          }
        }
      } catch (e) {
        print('Özel branş yükleme hatası: $e');
      }
    }

    final sortedList = allBranches.toList()..sort();
    if (mounted) {
      setState(() {
        _branchList = sortedList;
      });
    }
  }

  void _populateForm(Map<String, dynamic> data) {
    _tcController.text = data['tc'] ?? '';
    _fullNameController.text = data['fullName'] ?? '';
    _birthDateController.text = data['birthDate'] ?? '';
    _birthPlaceController.text = data['birthPlace'] ?? '';
    _nationalityController.text = data['nationality'] ?? '';
    _corporateEmailController.text = data['corporateEmail'] ?? '';
    _personalEmailController.text = data['personalEmail'] ?? '';
    _mobilePhoneController.text = data['mobilePhone'] ?? '';
    _homePhoneController.text = data['homePhone'] ?? '';
    _cityController.text = data['city'] ?? '';
    _districtController.text = data['district'] ?? '';
    _addressController.text = data['address'] ?? '';
    _emergencyNameController.text = data['emergencyContact'] ?? '';
    _emergencyPhoneController.text = data['emergencyPhone'] ?? '';
    _photoUrlController.text = data['photoUrl'] ?? '';
    _usernameController.text = data['username'] ?? '';
    _passwordController.text = data['password'] ?? '';

    setState(() {
      _gender = data['gender'];
      _maritalStatus = data['maritalStatus'];
      _bloodGroup = data['bloodGroup'];
      _title = data['title'];
      _branch = data['branch'];
    });
  }

  Future<void> _loadInstitutionId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final email = user.email ?? '';
    if (email.contains('@')) {
      final domain = email.split('@')[1];
      if (domain.contains('.')) {
        setState(() {
          _institutionId = domain.split('.')[0].toUpperCase();
        });
        // Institution ID yüklendikten sonra branşları yükle
        _loadBranches();
      }
    }
  }

  @override
  void dispose() {
    _tcController.dispose();
    _fullNameController.dispose();
    _birthDateController.dispose();
    _birthPlaceController.dispose();
    _nationalityController.dispose();
    _corporateEmailController.dispose();
    _personalEmailController.dispose();
    _mobilePhoneController.dispose();
    _homePhoneController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    _addressController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _photoUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<String?> _createAuthUser(String email, String password) async {
    try {
      final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
      final url =
          'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey';

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'password': password,
          'returnSecureToken': true,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['localId'] as String;
      } else {
        final error = json.decode(response.body);
        throw error['error']['message'];
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _saveStaff() async {
    if (!_formKey.currentState!.validate()) return;
    if (_institutionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kurum bilgisi yüklenemedi. Lütfen tekrar deneyin.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final username = _usernameController.text.trim().toLowerCase();
      final authEmail = _corporateEmailController.text.trim().isNotEmpty
          ? _corporateEmailController.text.trim()
          : '$username@$_institutionId.edukn';
      final defaultPassword = _passwordController.text.trim();

      final data = <String, dynamic>{
        'institutionId': _institutionId,
        'tc': _tcController.text.trim(),
        'fullName': _fullNameController.text.trim(),
        'birthDate': _birthDateController.text.trim(),
        'birthPlace': _birthPlaceController.text.trim(),
        'gender': _gender,
        'maritalStatus': _maritalStatus,
        'nationality': _nationalityController.text.trim(),
        'bloodGroup': _bloodGroup,
        'corporateEmail': _corporateEmailController.text.trim(),
        'personalEmail': _personalEmailController.text.trim(),
        'mobilePhone': _mobilePhoneController.text.trim(),
        'homePhone': _homePhoneController.text.trim(),
        'city': _cityController.text.trim(),
        'district': _districtController.text.trim(),
        'address': _addressController.text.trim(),
        'emergencyContactName': _emergencyNameController.text.trim(),
        'emergencyContactPhone': _emergencyPhoneController.text.trim(),
        'photoUrl': _photoUrlController.text.trim(),
        'username': username,
        'email': authEmail,
        'role': _title ?? 'personel',
        'title': _title,
        'branch': _branch,
        'department': _title == 'ogretmen' ? 'Öğretim Departmanı' : null,
        if (widget.fixedSchoolTypeName != null) 'workLocations': [widget.fixedSchoolTypeName],
        'isActive': true,
        'updatedAt': FieldValue.serverTimestamp(),
        'type': 'staff',
        'tcKimlik': _tcController.text.trim(),
        'phone': _mobilePhoneController.text.trim(),
        'schoolTypes': [],
        'modulePermissions': {
          'genel_duyurular': {'enabled': true, 'level': 'editor'},
          'okul_turleri': {'enabled': true, 'level': 'viewer'},
          'ogrenci_kayit': {'enabled': false, 'level': 'viewer'},
          'insan_kaynaklari': {'enabled': false, 'level': 'viewer'},
          'muhasebe': {'enabled': false, 'level': 'viewer'},
          'satin_alma': {'enabled': false, 'level': 'viewer'},
          'depo': {'enabled': false, 'level': 'viewer'},
          'destek_hizmetleri': {'enabled': false, 'level': 'viewer'},
          'kullanici_yonetimi': {'enabled': false, 'level': 'viewer'},
        },
      };

      if (widget.staffId != null) {
        // Güncelleme
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.staffId)
            .update(data);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Personel güncellendi')));
          Navigator.pop(context, true);
        }
      } else {
        // Yeni Kayıt için Auth user oluştur
        String? authUserId;
        try {
          authUserId = await _createAuthUser(authEmail, defaultPassword);
        } catch (e) {
          final msg = e.toString();
          if (msg.contains('EMAIL_EXISTS')) {
            throw 'Bu e-posta veya TC ile otomatik üretilen e-posta zaten kayıtlı!';
          } else if (msg.contains('WEAK_PASSWORD')) {
            throw 'En az 6 haneli bir şifre girmelisiniz!';
          }
          throw 'Hesap oluşturulurken hata: $e';
        }

        data['authUserId'] = authUserId;
        data['passwordStatus'] = 'ilk_giris';
        data['defaultPassword'] = defaultPassword;
        data['createdAt'] = FieldValue.serverTimestamp();

        if (authUserId != null && authUserId.isNotEmpty) {
          await FirebaseFirestore.instance.collection('users').doc(authUserId).set(data);
        } else {
          await FirebaseFirestore.instance.collection('users').add(data);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Personel kaydedildi')));
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Hata: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      isDense: true,
    );
  }

  String _formatDateInput(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 2) return digits;
    if (digits.length <= 4) {
      return '${digits.substring(0, 2)}.${digits.substring(2)}';
    }
    if (digits.length <= 8) {
      return '${digits.substring(0, 2)}.${digits.substring(2, 4)}.${digits.substring(4)}';
    }
    return '${digits.substring(0, 2)}.${digits.substring(2, 4)}.${digits.substring(4, 8)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.staffId != null ? 'Personeli Düzenle' : 'Yeni Personel Ekle',
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Kişisel Bilgiler',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // TC ve Ad Soyad
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _tcController,
                        decoration: _inputDecoration('T.C. Kimlik Numarası *')
                            .copyWith(
                              counterText: '',
                              suffixText: '${_tcController.text.length}/11',
                              suffixStyle: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                        keyboardType: TextInputType.number,
                        maxLength: 11,
                        onChanged: (_) => setState(() {}),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'TC zorunlu';
                          }
                          if (value.length != 11) {
                            return '11 haneli olmalı';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _fullNameController,
                        decoration: _inputDecoration('Ad Soyad *'),
                        inputFormatters: [_UpperCaseTextFormatter()],
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Ad Soyad zorunlu';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Ünvan (Title)
                DropdownButtonFormField<String>(
                  decoration: _inputDecoration('Ünvan / Görev *'),
                  value: _title,
                  items: const [
                    DropdownMenuItem(
                      value: 'ogretmen',
                      child: Text('Öğretmen'),
                    ),
                    DropdownMenuItem(value: 'mudur', child: Text('Müdür')),
                    DropdownMenuItem(
                      value: 'mudur_yardimcisi',
                      child: Text('Müdür Yardımcısı'),
                    ),
                    DropdownMenuItem(
                      value: 'personel',
                      child: Text('Personel'),
                    ),
                    DropdownMenuItem(
                      value: 'hr',
                      child: Text('İnsan Kaynakları'),
                    ),
                    DropdownMenuItem(
                      value: 'muhasebe',
                      child: Text('Muhasebe'),
                    ),
                    DropdownMenuItem(
                      value: 'satin_alma',
                      child: Text('Satın Alma'),
                    ),
                    DropdownMenuItem(
                      value: 'depo',
                      child: Text('Depo Sorumlusu'),
                    ),
                    DropdownMenuItem(
                      value: 'destek_hizmetleri',
                      child: Text('Destek Hizmetleri'),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    _title = value;
                    // Ünvan öğretmen değilse branşı temizle
                    if (value != 'ogretmen') {
                      _branch = null;
                    }
                  }),
                  validator: (value) =>
                      value == null ? 'Ünvan seçimi zorunlu' : null,
                ),
                const SizedBox(height: 16),

                // Branş (sadece öğretmen seçiliyse görünür)
                if (_title == 'ogretmen') ...[
                  DropdownButtonFormField<String>(
                    decoration: _inputDecoration('Branş *'),
                    value: _branchList.contains(_branch) ? _branch : null,
                    items: _branchList.map((name) {
                      return DropdownMenuItem(
                        value: name,
                        child: Text(name),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => _branch = value),
                    validator: (value) => _title == 'ogretmen' && value == null
                        ? 'Branş seçimi zorunlu'
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],

                // Doğum Tarihi, Doğum Yeri
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _birthDateController,
                        decoration: _inputDecoration(
                          'Doğum Tarihi',
                        ).copyWith(hintText: 'gg.aa.yyyy', counterText: ''),
                        keyboardType: TextInputType.number,
                        maxLength: 10,
                        onChanged: (value) {
                          final formatted = _formatDateInput(value);
                          if (formatted != value) {
                            _birthDateController.value = TextEditingValue(
                              text: formatted,
                              selection: TextSelection.collapsed(
                                offset: formatted.length,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _birthPlaceController,
                        decoration: _inputDecoration('Doğum Yeri'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Cinsiyet, Medeni Durum, Uyruk
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        decoration: _inputDecoration('Cinsiyet'),
                        value: _gender,
                        items: const [
                          DropdownMenuItem(
                            value: 'erkek',
                            child: Text('Erkek'),
                          ),
                          DropdownMenuItem(
                            value: 'kadin',
                            child: Text('Kadın'),
                          ),
                        ],
                        onChanged: (value) => setState(() => _gender = value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        decoration: _inputDecoration('Medeni Durum'),
                        value: _maritalStatus,
                        items: const [
                          DropdownMenuItem(
                            value: 'bekar',
                            child: Text('Bekar'),
                          ),
                          DropdownMenuItem(value: 'evli', child: Text('Evli')),
                        ],
                        onChanged: (value) =>
                            setState(() => _maritalStatus = value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _nationalityController,
                        decoration: _inputDecoration('Uyruk'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Kan Grubu
                DropdownButtonFormField<String>(
                  decoration: _inputDecoration('Kan Grubu'),
                  value: _bloodGroup,
                  items: const [
                    DropdownMenuItem(value: '0+', child: Text('0 +')),
                    DropdownMenuItem(value: '0-', child: Text('0 -')),
                    DropdownMenuItem(value: 'A+', child: Text('A +')),
                    DropdownMenuItem(value: 'A-', child: Text('A -')),
                    DropdownMenuItem(value: 'B+', child: Text('B +')),
                    DropdownMenuItem(value: 'B-', child: Text('B -')),
                    DropdownMenuItem(value: 'AB+', child: Text('AB +')),
                    DropdownMenuItem(value: 'AB-', child: Text('AB -')),
                  ],
                  onChanged: (value) => setState(() => _bloodGroup = value),
                ),
                const SizedBox(height: 24),

                const Text(
                  'İletişim Bilgileri',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                // E-posta
                TextFormField(
                  controller: _corporateEmailController,
                  decoration: _inputDecoration('E-posta (Kurumsal)'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _personalEmailController,
                  decoration: _inputDecoration('E-posta (Kişisel)'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),

                // Telefonlar
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _mobilePhoneController,
                        decoration: _inputDecoration('Telefon (Cep)'),
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _homePhoneController,
                        decoration: _inputDecoration('Telefon (Ev)'),
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Adres
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cityController,
                        decoration: _inputDecoration('İl'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _districtController,
                        decoration: _inputDecoration('İlçe'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: _inputDecoration('Açık Adres'),
                  maxLines: 2,
                ),
                const SizedBox(height: 24),

                const Text(
                  'Diğer Bilgiler',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                // Acil durum
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _emergencyNameController,
                        decoration: _inputDecoration('Acil Durum Kişisi Adı'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _emergencyPhoneController,
                        decoration: _inputDecoration('Acil Durum Telefonu'),
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _photoUrlController,
                  readOnly: true,
                  decoration:
                      _inputDecoration(
                        'Vesikalık Fotoğraf (dosya yükleme)',
                      ).copyWith(
                        hintText:
                            'Dosya seçmek için aşağıdaki butonları kullanın',
                      ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.photo_camera_back_outlined,
                        size: 48,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Dosya yükleme özelliği yakında eklenecek',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.upload_file, size: 18),
                              label: const Text('Dosya Yükle'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Kamera ile çekme özelliği yakında eklenecek',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.camera_alt_outlined,
                                size: 18,
                              ),
                              label: const Text('Fotoğraf Çek'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Kullanıcı Girişi',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        final tc = _tcController.text.trim();
                        if (tc.length < 6) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Önce TC Kimlik numarasını en az 6 hane girin',
                              ),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }
                        final last6 = tc.substring(tc.length - 6);
                        setState(() {
                          _usernameController.text = last6;
                          _passwordController.text = last6;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Kullanıcı adı ve şifre TC son 6 hanesinden oluşturuldu: $last6',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('Otomatik'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _usernameController,
                        decoration: _inputDecoration('Kullanıcı Adı *'),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Kullanıcı adı zorunlu';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _passwordController,
                        decoration: _inputDecoration('Şifre *'),
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Şifre zorunlu';
                          }
                          if (value.length < 6) {
                            return 'En az 6 karakter';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveStaff,
                    icon: _isSaving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(_isSaving ? 'Kaydediliyor...' : 'Kaydet'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
