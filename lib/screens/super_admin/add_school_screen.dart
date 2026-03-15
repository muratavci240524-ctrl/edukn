import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../firebase_options.dart';
import '../../constants/app_modules.dart';

class AddSchoolScreen extends StatefulWidget {
  final String? schoolId; // Düzenleme modu için okul ID'si
  final Map<String, dynamic>? schoolData; // Düzenleme modu için mevcut data

  const AddSchoolScreen({Key? key, this.schoolId, this.schoolData})
    : super(key: key);

  @override
  _AddSchoolScreenState createState() => _AddSchoolScreenState();
}

class _AddSchoolScreenState extends State<AddSchoolScreen> {
  int _currentStep = 0;
  bool _isLoading = false;
  bool _isEditMode = false;

  // Form Keys - Her adım için ayrı form
  final _step1FormKey = GlobalKey<FormState>();
  final _step2FormKey = GlobalKey<FormState>();
  final _step3FormKey = GlobalKey<FormState>();
  final _step4FormKey = GlobalKey<FormState>();

  // ADIM 1: Okul Bilgileri
  final _schoolNameController = TextEditingController();
  final _institutionIdController = TextEditingController(); // Kurum ID
  final _schoolEmailController = TextEditingController();
  final _schoolPhoneController = TextEditingController();
  final _schoolAddressController = TextEditingController();
  String? _selectedCity;
  String? _selectedDistrict;

  // ADIM 2: Yetkili Bilgileri
  final _adminFullNameController = TextEditingController();
  final _adminUsernameController = TextEditingController(); // Kullanıcı adı
  final _adminEmailController = TextEditingController();
  final _adminPhoneController = TextEditingController();
  final _adminPasswordController = TextEditingController();

  // ADIM 3: Kota ve Modüller
  double _studentQuota = 250; // Başlangıç kotası

  // ADIM 4: Lisans Ayarları
  DateTime? _licenseStartDate;
  DateTime? _licenseEndDate;
  bool _isSchoolActive = true; // Okul başlangıçta aktif

  // Modüllerin durumu - AppModules'den otomatik doldurulacak
  late final Map<String, bool> _modules;

  // Türkiye illeri
  final List<String> _cities = [
    'Adana',
    'Adıyaman',
    'Afyonkarahisar',
    'Ağrı',
    'Aksaray',
    'Amasya',
    'Ankara',
    'Antalya',
    'Ardahan',
    'Artvin',
    'Aydın',
    'Balıkesir',
    'Bartın',
    'Batman',
    'Bayburt',
    'Bilecik',
    'Bingöl',
    'Bitlis',
    'Bolu',
    'Burdur',
    'Bursa',
    'Çanakkale',
    'Çankırı',
    'Çorum',
    'Denizli',
    'Diyarbakır',
    'Düzce',
    'Edirne',
    'Elazığ',
    'Erzincan',
    'Erzurum',
    'Eskişehir',
    'Gaziantep',
    'Giresun',
    'Gümüşhane',
    'Hakkari',
    'Hatay',
    'Iğdır',
    'Isparta',
    'İstanbul',
    'İzmir',
    'Kahramanmaraş',
    'Karabük',
    'Karaman',
    'Kars',
    'Kastamonu',
    'Kayseri',
    'Kırıkkale',
    'Kırklareli',
    'Kırşehir',
    'Kilis',
    'Kocaeli',
    'Konya',
    'Kütahya',
    'Malatya',
    'Manisa',
    'Mardin',
    'Mersin',
    'Muğla',
    'Muş',
    'Nevşehir',
    'Niğde',
    'Ordu',
    'Osmaniye',
    'Rize',
    'Sakarya',
    'Samsun',
    'Siirt',
    'Sinop',
    'Sivas',
    'Şanlıurfa',
    'Şırnak',
    'Tekirdağ',
    'Tokat',
    'Trabzon',
    'Tunceli',
    'Uşak',
    'Van',
    'Yalova',
    'Yozgat',
    'Zonguldak',
  ];

  // İlçeler (basit bir örnek, il seçildikçe doldurulabilir)
  List<String> get _districts {
    if (_selectedCity == 'İstanbul') {
      return [
        'Kadıköy',
        'Beşiktaş',
        'Üsküdar',
        'Şişli',
        'Beyoğlu',
        'Fatih',
        'Bakırköy',
        'Diğer',
      ];
    } else if (_selectedCity == 'Ankara') {
      return [
        'Çankaya',
        'Keçiören',
        'Yenimahalle',
        'Mamak',
        'Etimesgut',
        'Altındağ',
        'Diğer',
      ];
    } else if (_selectedCity == 'İzmir') {
      return [
        'Konak',
        'Karşıyaka',
        'Bornova',
        'Buca',
        'Çiğli',
        'Balçova',
        'Diğer',
      ];
    }
    return ['Merkez', 'Diğer'];
  }

  @override
  void initState() {
    super.initState();
    // Merkezi modül sisteminden tüm modülleri al
    _modules = Map.fromEntries(
      AppModules.allModuleKeys.map((key) => MapEntry(key, true)),
    );
    _isEditMode = widget.schoolId != null;

    if (_isEditMode && widget.schoolData != null) {
      // Düzenleme modunda mevcut verileri doldur
      final data = widget.schoolData!;

      print('📝 Okul düzenleme modu - Veriler yükleniyor...');

      // Düzenleme modunda 4. adıma (Lisans Ayarları) direkt git
      _currentStep = 3;

      // WidgetsBinding ile frame sonrası yükle - UI'ın hazır olmasını bekle
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _schoolNameController.text = data['schoolName'] ?? '';
          _institutionIdController.text = data['institutionId'] ?? '';
          _schoolEmailController.text = data['schoolEmail'] ?? '';
          _schoolPhoneController.text = data['schoolPhone'] ?? '';
          _schoolAddressController.text = data['schoolAddress'] ?? '';
          _selectedCity = data['city'];
          _selectedDistrict = data['district'];

          print('🏫 Okul: ${_schoolNameController.text}');
          print('🆔 Kurum ID: ${_institutionIdController.text}');
          print('📧 Email: ${_schoolEmailController.text}');
          print('📞 Telefon: ${_schoolPhoneController.text}');
          print('🏠 Adres: ${_schoolAddressController.text}');
          print('📍 Şehir/İlçe: $_selectedCity / $_selectedDistrict');

          _adminFullNameController.text = data['adminFullName'] ?? '';
          _adminUsernameController.text = data['adminUsername'] ?? '';
          _adminEmailController.text = data['adminEmail'] ?? '';
          _adminPhoneController.text = data['adminPhone'] ?? '';
          // Şifreyi gösterme (güvenlik)

          print('👤 Yetkili: ${_adminFullNameController.text}');
          print('👤 Kullanıcı Adı: ${_adminUsernameController.text}');
          print('📧 Yetkili Email: ${_adminEmailController.text}');
          print('📞 Yetkili Telefon: ${_adminPhoneController.text}');

          _studentQuota = (data['studentQuota'] ?? 250).toDouble();
          _isSchoolActive = data['isActive'] ?? true;

          print('👥 Öğrenci Kotası: ${_studentQuota.toInt()}');
          print('✅ Okul Durumu: ${_isSchoolActive ? "Aktif" : "Pasif"}');

          // Modülleri doldur
          if (data['activeModules'] != null) {
            final List<dynamic> activeModules = data['activeModules'];
            _modules.forEach((key, value) {
              _modules[key] = activeModules.contains(key);
            });
            print('📦 Aktif Modüller: ${activeModules.join(", ")}');
          } else {
            print('📦 Aktif Modüller: Varsayılan');
          }

          // Lisans tarihlerini doldur
          if (data['licenseStartDate'] != null) {
            try {
              if (data['licenseStartDate'] is Timestamp) {
                _licenseStartDate = (data['licenseStartDate'] as Timestamp)
                    .toDate();
              } else if (data['licenseStartDate'] is String) {
                _licenseStartDate = DateTime.parse(data['licenseStartDate']);
              }
            } catch (e) {
              print('Lisans başlangıç tarihi parse hatası: $e');
              _licenseStartDate = DateTime.now();
            }
          } else {
            _licenseStartDate = DateTime.now();
          }

          if (data['licenseExpiresAt'] != null) {
            try {
              if (data['licenseExpiresAt'] is Timestamp) {
                _licenseEndDate = (data['licenseExpiresAt'] as Timestamp)
                    .toDate();
              } else if (data['licenseExpiresAt'] is String) {
                _licenseEndDate = DateTime.parse(data['licenseExpiresAt']);
              }
            } catch (e) {
              print('Lisans bitiş tarihi parse hatası: $e');
              _licenseEndDate = DateTime.now().add(Duration(days: 365));
            }
          } else {
            _licenseEndDate = DateTime.now().add(Duration(days: 365));
          }

          print(
            '📅 Lisans Başlangıç: ${_licenseStartDate?.day}.${_licenseStartDate?.month}.${_licenseStartDate?.year}',
          );
          print(
            '📅 Lisans Bitiş: ${_licenseEndDate?.day}.${_licenseEndDate?.month}.${_licenseEndDate?.year}',
          );
          if (_licenseStartDate != null && _licenseEndDate != null) {
            final days = _licenseEndDate!.difference(_licenseStartDate!).inDays;
            print('⏱️ Lisans Süresi: $days gün');
          }
          print('✅ Tüm veriler başarıyla yüklendi!');
        });
      });
    } else {
      // Yeni okul eklenirken lisans başlangıcı bugün
      _licenseStartDate = DateTime.now();
      _licenseEndDate = DateTime.now().add(
        Duration(days: 365),
      ); // Varsayılan 1 yıl
      print('🆕 Yeni okul oluşturma modu');
    }
  }

  // Firebase Auth kullanıcısı oluştur
  Future<String?> _createAuthUser(String email, String password) async {
    try {
      // Firebase REST API kullanarak kullanıcı oluştur
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
        print('✅ Firebase Auth kullanıcı oluşturuldu: ${data['localId']}');
        return data['localId'] as String;
      } else {
        final error = json.decode(response.body);
        print(
          '❌ Auth kullanıcı oluşturma hatası: ${error['error']['message']}',
        );
        throw error['error']['message'];
      }
    } catch (e) {
      print('❌ Auth kullanıcı oluşturma hatası: $e');
      rethrow;
    }
  }

  // Hızlı lisans süresi ayarlama
  void _setLicenseDuration(int days) {
    setState(() {
      _licenseStartDate = DateTime.now();
      _licenseEndDate = DateTime.now().add(Duration(days: days));
    });
  }

  // Okul silme onayı
  Future<void> _showDeleteConfirmation() async {
    final schoolName = _schoolNameController.text;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.red, size: 28),
              SizedBox(width: 12),
              Text('Okulu Sil'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bu okulu silmek istediğinizden emin misiniz?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Okul: $schoolName',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade900,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '⚠️ Bu işlem geri alınamaz!',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '• Okul kaydı silinecek\n• Yönetici hesabı silinecek\n• Tüm okul verileri kaybolacak',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.red.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text('Vazgeç'),
              onPressed: () => Navigator.pop(context, false),
            ),
            ElevatedButton(
              child: Text('Evet, Sil'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      _deleteSchool();
    }
  }

  // Okulu sil
  Future<void> _deleteSchool() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Okul siliniyor...',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );

    try {
      // Direkt Firestore'dan sil
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .delete();

      print('✅ Okul silindi: ${widget.schoolId}');
      // TODO: Admin kullanıcısı silmek için Cloud Function gerekli

      if (mounted) {
        Navigator.pop(context); // Loading dialog
        Navigator.pop(context); // Edit screen
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Okul silindi! (Admin hesabı için Cloud Function gerekli)',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Silme hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Okulu kaydet
  void _saveSchool() async {
    // Tüm adımların validasyonunu kontrol et
    if (!_step1FormKey.currentState!.validate() ||
        !_step2FormKey.currentState!.validate() ||
        !_step3FormKey.currentState!.validate() ||
        !_step4FormKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lütfen tüm alanları doldurun'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Seçili modülleri al
    final List<String> selectedModules = [];
    _modules.forEach((key, value) {
      if (value) selectedModules.add(key);
    });

    try {
      // ŞİMDİLİK DİREKT FİRESTORE'A YAZIYORUZ (Cloud Function yerine)
      print('⚠️ Geçici çözüm: Direkt Firestore\'a yazılıyor...');

      // Kullanıcı adı ve kurum ID'den benzersiz email oluştur
      final username = _adminUsernameController.text.trim().toLowerCase();
      final institutionId = _institutionIdController.text.trim().toUpperCase();
      final generatedEmail = '$username@$institutionId.edukn';
      final password = _adminPasswordController.text; // Şifre

      final Map<String, dynamic> data = {
        'schoolName': _schoolNameController.text.trim(),
        'institutionId': institutionId,
        'schoolEmail': _schoolEmailController.text.trim(),
        'schoolPhone': _schoolPhoneController.text.trim(),
        'schoolAddress': _schoolAddressController.text.trim(),
        'city': _selectedCity,
        'district': _selectedDistrict,
        'adminFullName': _adminFullNameController.text.trim(),
        'adminUsername': username,
        'adminEmail': generatedEmail, // Otomatik oluşturulan email
        'adminPhone': _adminPhoneController.text.trim(),
        'studentQuota': _studentQuota.toInt(),
        'activeModules': selectedModules,
        'licenseStartDate': _licenseStartDate != null
            ? Timestamp.fromDate(_licenseStartDate!)
            : FieldValue.serverTimestamp(),
        'licenseExpiresAt': _licenseEndDate != null
            ? Timestamp.fromDate(_licenseEndDate!)
            : Timestamp.fromDate(DateTime.now().add(Duration(days: 365))),
        'isActive': _isSchoolActive,
      };

      // Edit modunda schoolId ve şifre kontrolü ekle
      if (_isEditMode) {
        data['schoolId'] = widget.schoolId;
        // Şifre değiştirilmişse ekle
        if (_adminPasswordController.text.isNotEmpty) {
          data['adminPassword'] = _adminPasswordController.text;
        }
      } else {
        // Yeni okul için şifre zorunlu
        data['adminPassword'] = _adminPasswordController.text;
      }

      // Firebase'e gönderilecek tüm verileri konsola yazdır
      print('\n🚀 Firebase\'e gönderilen veriler:');
      print('=' * 50);
      print('📋 Mod: ${_isEditMode ? "GÜNCELLEME" : "YENİ KAYIT"}');
      print('-' * 50);
      print('🏫 OKUL BİLGİLERİ:');
      print('  • Okul Adı: ${data['schoolName']}');
      print('  • Kurum ID: ${data['institutionId']}');
      print('  • E-posta: ${data['schoolEmail']}');
      print('  • Telefon: ${data['schoolPhone']}');
      print('  • Adres: ${data['schoolAddress']}');
      print('  • Şehir: ${data['city']}');
      print('  • İlçe: ${data['district']}');
      print('-' * 50);
      print('👤 YETKİLİ BİLGİLERİ:');
      print('  • Ad Soyad: ${data['adminFullName']}');
      print('  • E-posta: ${data['adminEmail']}');
      print('  • Telefon: ${data['adminPhone']}');
      print(
        '  • Şifre: ${data.containsKey('adminPassword') ? "***GÜNCELLENDİ***" : "DEĞİŞMEDİ"}',
      );
      print('-' * 50);
      print('📊 KOTA VE MODÜLLER:');
      print('  • Öğrenci Kotası: ${data['studentQuota']}');
      print('  • Aktif Modüller: ${data['activeModules'].join(", ")}');
      print('-' * 50);
      print('📅 LİSANS BİLGİLERİ:');
      print('  • Başlangıç (licenseStartDate): ${data['licenseStartDate']}');
      print('  • Bitiş (licenseExpiresAt): ${data['licenseExpiresAt']}');
      print(
        '  • Okul Durumu (isActive): ${data['isActive'] ? "AKTİF ✅" : "PASİF ❌"}',
      );
      if (_isEditMode) {
        print('  • School ID: ${data['schoolId']}');
      }
      print('=' * 50);
      print('');

      // Firestore'a direkt yaz
      if (_isEditMode) {
        // Güncelleme
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.schoolId)
            .update(data);
        print('✅ Okul güncellendi: ${widget.schoolId}');

        // Şifre değiştirilmişse Auth'da da güncelle
        if (data.containsKey('adminPassword')) {
          // TODO: Şifre güncelleme için Cloud Function gerekli
          print('⚠️ Şifre değişikliği için Cloud Function gerekli');
        }
      } else {
        // Yeni kayıt - Önce Firebase Auth kullanıcısı oluştur
        print('\n🔐 Firebase Auth kullanıcısı oluşturuluyor...');
        String? authUserId;
        try {
          authUserId = await _createAuthUser(
            generatedEmail,
            _adminPasswordController.text,
          );
          print('✅ Auth kullanıcı ID: $authUserId');
        } catch (e) {
          throw 'Firebase Auth kullanıcı oluşturulamadı: $e';
        }

        // Firestore'a kaydet
        final firestoreData = {
          ...data,
          'adminUserId': authUserId, // Auth user ID'yi kaydet
          'createdAt': FieldValue.serverTimestamp(),
          'totalStudents': 0,
          'activeStudents': 0,
          'passiveStudents': 0,
        };

        print('\n💾 Firestore\'a yazılan tam veri:');
        print(firestoreData.toString());
        print('');

        final docRef = await FirebaseFirestore.instance
            .collection('schools')
            .add(firestoreData);
        print('✅ Yeni okul oluşturuldu: ${docRef.id}');
        print('✅ Admin kullanıcısı Firebase Auth\'a eklendi!');

        // ✅ ÖNEMLİ: Admin kullanıcıyı users koleksiyonuna da ekle
        print('\n👤 Admin kullanıcı kaydı users koleksiyonuna ekleniyor...');
        final adminUserData = {
          'authUserId': authUserId,
          'institutionId': institutionId,
          'schoolId': docRef.id, // Yeni oluşturulan okul ID'si
          'fullName': _adminFullNameController.text.trim(),
          'username': username,
          'email': generatedEmail,
          'phone': _adminPhoneController.text.trim(),
          'role': 'genel_mudur', // Okul yöneticisi
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),

          // Tüm modüllerde editor yetkisi ver
          'modulePermissions': {
            'kullanici_yonetimi': {'enabled': true, 'level': 'editor'},
            'ogrenci_kayit': {'enabled': true, 'level': 'editor'},
            'okul_turleri': {'enabled': true, 'level': 'editor'},
            'insan_kaynaklari': {'enabled': true, 'level': 'editor'},
            'muhasebe': {'enabled': true, 'level': 'editor'},
            'satin_alma': {'enabled': true, 'level': 'editor'},
            'depo': {'enabled': true, 'level': 'editor'},
            'destek_hizmetleri': {'enabled': true, 'level': 'editor'},
            'genel_duyurular': {'enabled': true, 'level': 'editor'},
          },

          'schoolTypes': [], // Okul türleri sonradan eklenecek
          'schoolTypePermissions': {}, // Okul türü yetkileri
        };

        // Admin kullanıcıyı Firebase Auth UID'i ile kaydet
        await FirebaseFirestore.instance
            .collection('users')
            .doc(authUserId)
            .set(adminUserData);

        print('✅ Admin kullanıcı kaydı users koleksiyonuna eklendi!');
        print(
          '🎯 Artık okul yöneticisi giriş yapıp kullanıcı yönetimi yapabilir!',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditMode
                  ? 'Okul güncellendi!'
                  : 'Okul ve yönetici hesabı başarıyla oluşturuldu!',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Bilinmeyen hata: $e"),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.indigo),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEditMode ? 'Okul Düzenle' : 'Yeni Okul Oluştur',
          style: TextStyle(
            color: Colors.grey.shade900,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_isEditMode)
            IconButton(
              icon: Icon(Icons.delete_forever, color: Colors.red),
              tooltip: 'Okulu Sil',
              onPressed: _showDeleteConfirmation,
            ),
        ],
      ),
      body: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: 900),
          padding: const EdgeInsets.all(16.0),
          child: Stepper(
            currentStep: _currentStep,
            onStepContinue: () {
              if (_currentStep < 3) {
                // İlgili adımın validasyonunu kontrol et
                bool isValid = false;
                if (_currentStep == 0) {
                  isValid = _step1FormKey.currentState?.validate() ?? false;
                } else if (_currentStep == 1) {
                  isValid = _step2FormKey.currentState?.validate() ?? false;
                } else if (_currentStep == 2) {
                  isValid = _step3FormKey.currentState?.validate() ?? false;
                }

                if (isValid) {
                  setState(() => _currentStep++);
                }
              } else {
                // Son adımda - kaydet
                _saveSchool();
              }
            },
            onStepCancel: () {
              if (_currentStep > 0) {
                setState(() => _currentStep--);
              }
            },
            onStepTapped: (step) => setState(() => _currentStep = step),
            controlsBuilder: (context, details) {
              return Padding(
                padding: const EdgeInsets.only(top: 24.0),
                child: Row(
                  children: [
                    ElevatedButton(
                      onPressed: _isLoading ? null : details.onStepContinue,
                      child: _isLoading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_currentStep == 3 ? 'Kaydet' : 'İleri'),
                    ),
                    SizedBox(width: 12),
                    if (_currentStep > 0)
                      OutlinedButton(
                        onPressed: details.onStepCancel,
                        child: Text('Geri'),
                      ),
                  ],
                ),
              );
            },
            steps: [
              // ADIM 1: Okul Bilgileri
              Step(
                title: Text('Okul Bilgileri'),
                isActive: _currentStep >= 0,
                state: _currentStep > 0
                    ? StepState.complete
                    : StepState.indexed,
                content: _buildStep1(),
              ),
              // ADIM 2: Yetkili Bilgileri
              Step(
                title: Text('Yetkili Bilgileri'),
                isActive: _currentStep >= 1,
                state: _currentStep > 1
                    ? StepState.complete
                    : StepState.indexed,
                content: _buildStep2(),
              ),
              // ADIM 3: Kota ve Modüller
              Step(
                title: Text('Kota ve Modüller'),
                isActive: _currentStep >= 2,
                state: _currentStep > 2
                    ? StepState.complete
                    : StepState.indexed,
                content: _buildStep3(),
              ),
              // ADIM 4: Lisans Ayarları
              Step(
                title: Text('Lisans Ayarları'),
                isActive: _currentStep >= 3,
                state: StepState.indexed,
                content: _buildStep4(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ADIM 1: Okul Bilgileri Formu
  Widget _buildStep1() {
    return Form(
      key: _step1FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _schoolNameController,
            decoration: InputDecoration(
              labelText: 'Okul Adı *',
              prefixIcon: Icon(Icons.school),
            ),
            validator: (v) =>
                v == null || v.isEmpty ? 'Okul adı gerekli' : null,
          ),
          SizedBox(height: 16),
          TextFormField(
            controller: _institutionIdController,
            decoration: InputDecoration(
              labelText: 'Kurum ID *',
              prefixIcon: Icon(Icons.badge),
              helperText:
                  'Örn: MEB2024, OKUL123 (Otomatik büyük harfe çevrilir)',
              hintText: 'Benzersiz kurum kimliği',
            ),
            textCapitalization: TextCapitalization.characters,
            onChanged: (value) {
              // Otomatik büyük harfe çevir
              _institutionIdController.value = _institutionIdController.value
                  .copyWith(
                    text: value.toUpperCase(),
                    selection: TextSelection.collapsed(offset: value.length),
                  );
            },
            validator: (v) {
              if (v == null || v.isEmpty) return 'Kurum ID gerekli';
              if (v.length < 3) return 'En az 3 karakter olmalı';
              if (!RegExp(r'^[A-Z0-9]+$').hasMatch(v)) {
                return 'Sadece harf ve rakam kullanın';
              }
              return null;
            },
          ),
          SizedBox(height: 16),
          TextFormField(
            controller: _schoolEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Okul E-posta *',
              prefixIcon: Icon(Icons.email),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'E-posta gerekli';
              if (!v.contains('@')) return 'Geçerli e-posta girin';
              return null;
            },
          ),
          SizedBox(height: 16),
          TextFormField(
            controller: _schoolPhoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Okul Telefon *',
              prefixIcon: Icon(Icons.phone),
            ),
            validator: (v) => v == null || v.isEmpty ? 'Telefon gerekli' : null,
          ),
          SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              // Dar ekranlarda alt alta, geniş ekranlarda yan yana
              if (constraints.maxWidth < 600) {
                return Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: _selectedCity,
                      decoration: InputDecoration(
                        labelText: 'İl *',
                        prefixIcon: Icon(Icons.location_city),
                      ),
                      items: _cities.map((city) {
                        return DropdownMenuItem(value: city, child: Text(city));
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedCity = value;
                          _selectedDistrict = null;
                        });
                      },
                      validator: (v) => v == null ? 'İl seçin' : null,
                    ),
                    SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedDistrict,
                      decoration: InputDecoration(
                        labelText: 'İlçe *',
                        prefixIcon: Icon(Icons.location_on),
                      ),
                      items: _districts.map((district) {
                        return DropdownMenuItem(
                          value: district,
                          child: Text(district),
                        );
                      }).toList(),
                      onChanged: (value) =>
                          setState(() => _selectedDistrict = value),
                      validator: (v) => v == null ? 'İlçe seçin' : null,
                    ),
                  ],
                );
              }

              // Geniş ekranda yan yana
              return Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedCity,
                      decoration: InputDecoration(
                        labelText: 'İl *',
                        prefixIcon: Icon(Icons.location_city),
                      ),
                      items: _cities.map((city) {
                        return DropdownMenuItem(value: city, child: Text(city));
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedCity = value;
                          _selectedDistrict = null;
                        });
                      },
                      validator: (v) => v == null ? 'İl seçin' : null,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedDistrict,
                      decoration: InputDecoration(
                        labelText: 'İlçe *',
                        prefixIcon: Icon(Icons.location_on),
                      ),
                      items: _districts.map((district) {
                        return DropdownMenuItem(
                          value: district,
                          child: Text(district),
                        );
                      }).toList(),
                      onChanged: (value) =>
                          setState(() => _selectedDistrict = value),
                      validator: (v) => v == null ? 'İlçe seçin' : null,
                    ),
                  ),
                ],
              );
            },
          ),
          SizedBox(height: 16),
          TextFormField(
            controller: _schoolAddressController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Okul Adresi *',
              prefixIcon: Icon(Icons.home),
              alignLabelWithHint: true,
            ),
            validator: (v) => v == null || v.isEmpty ? 'Adres gerekli' : null,
          ),
        ],
      ),
    );
  }

  // ADIM 2: Yetkili Bilgileri Formu
  Widget _buildStep2() {
    return Form(
      key: _step2FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _adminFullNameController,
            decoration: InputDecoration(
              labelText: 'Yetkili Adı Soyadı *',
              prefixIcon: Icon(Icons.person),
            ),
            validator: (v) =>
                v == null || v.isEmpty ? 'Ad soyad gerekli' : null,
          ),
          SizedBox(height: 16),
          TextFormField(
            controller: _adminUsernameController,
            decoration: InputDecoration(
              labelText: 'Kullanıcı Adı *',
              prefixIcon: Icon(Icons.account_circle),
              helperText: 'Giriş için kullanılacak (sadece harf ve rakam)',
              hintText: 'ornek: ahmetyilmaz',
            ),
            onChanged: (value) {
              // Sadece küçük harf, rakam ve alt çizgi
              final filtered = value.toLowerCase().replaceAll(
                RegExp(r'[^a-z0-9_]'),
                '',
              );
              if (filtered != value) {
                _adminUsernameController.value = _adminUsernameController.value
                    .copyWith(
                      text: filtered,
                      selection: TextSelection.collapsed(
                        offset: filtered.length,
                      ),
                    );
              }
            },
            validator: (v) {
              if (v == null || v.isEmpty) return 'Kullanıcı adı gerekli';
              if (v.length < 3) return 'En az 3 karakter olmalı';
              if (!RegExp(r'^[a-z0-9_]+$').hasMatch(v)) {
                return 'Sadece küçük harf, rakam ve alt çizgi';
              }
              return null;
            },
          ),
          SizedBox(height: 16),
          TextFormField(
            controller: _adminEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'İletişim E-posta (Opsiyonel)',
              prefixIcon: Icon(Icons.email),
              helperText: 'Bildirimler için kullanılacak',
            ),
            validator: (v) {
              if (v != null && v.isNotEmpty && !v.contains('@')) {
                return 'Geçerli e-posta girin';
              }
              return null;
            },
          ),
          SizedBox(height: 16),
          TextFormField(
            controller: _adminPhoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Yetkili Telefon *',
              prefixIcon: Icon(Icons.phone),
            ),
            validator: (v) => v == null || v.isEmpty ? 'Telefon gerekli' : null,
          ),
          SizedBox(height: 16),
          TextFormField(
            controller: _adminPasswordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: _isEditMode
                  ? 'Yeni Şifre (Boş bırakılırsa değişmez)'
                  : 'Geçici Şifre *',
              prefixIcon: Icon(Icons.lock),
              helperText: _isEditMode
                  ? 'Değiştirmek istiyorsanız en az 6 karakter'
                  : 'En az 6 karakter',
            ),
            validator: (v) {
              // Edit modunda şifre opsiyonel
              if (_isEditMode) {
                if (v != null && v.isNotEmpty && v.length < 6) {
                  return 'En az 6 karakter olmalı';
                }
                return null;
              }
              // Yeni okul için zorunlu
              if (v == null || v.isEmpty) return 'Şifre gerekli';
              if (v.length < 6) return 'En az 6 karakter olmalı';
              return null;
            },
          ),
        ],
      ),
    );
  }

  // ADIM 3: Kota ve Modüller
  Widget _buildStep3() {
    return Form(
      key: _step3FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Öğrenci Kotası',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Kayıt Kapasitesi:'),
                      Text(
                        '${_studentQuota.toInt()} öğrenci',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _studentQuota,
                    min: 250,
                    max: 10000,
                    divisions: 195, // (10000-250)/50 = 195 adım
                    label: _studentQuota.toInt().toString(),
                    onChanged: (value) => setState(() => _studentQuota = value),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '250',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      Text(
                        '10,000',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 24),
          Text(
            'Aktif Modüller',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          ..._modules.keys.map((key) {
            final moduleInfo = AppModules.getModule(key);
            return CheckboxListTile(
              title: Row(
                children: [
                  if (moduleInfo != null) ...[
                    Icon(moduleInfo.icon, size: 18, color: moduleInfo.color),
                    SizedBox(width: 8),
                  ],
                  Text(AppModules.getModuleName(key)),
                ],
              ),
              subtitle: moduleInfo != null
                  ? Text(moduleInfo.category, style: TextStyle(fontSize: 11))
                  : null,
              value: _modules[key],
              onChanged: (value) => setState(() => _modules[key] = value!),
              controlAffinity: ListTileControlAffinity.leading,
            );
          }).toList(),
        ],
      ),
    );
  }

  // ADIM 4: Lisans Ayarları
  Widget _buildStep4() {
    return Form(
      key: _step4FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Okul Durumu Switch
          Card(
            elevation: 2,
            child: SwitchListTile(
              title: Text(
                'Okul Durumu',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(_isSchoolActive ? 'Aktif' : 'Pasif'),
              value: _isSchoolActive,
              onChanged: (value) => setState(() => _isSchoolActive = value),
              secondary: Icon(
                _isSchoolActive ? Icons.check_circle : Icons.cancel,
                color: _isSchoolActive ? Colors.green : Colors.red,
              ),
            ),
          ),
          SizedBox(height: 24),

          // Lisans Süresi Başlık
          Text(
            'Lisans Süresi',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),

          // Hızlı Seçim Butonları
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: Icon(Icons.rocket_launch, size: 18),
                  label: Text('Deneme'),
                  onPressed: () => _setLicenseDuration(30),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    foregroundColor: Colors.orange,
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: Icon(Icons.calendar_today, size: 18),
                  label: Text('6 Ay'),
                  onPressed: () => _setLicenseDuration(180),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: Icon(Icons.calendar_month, size: 18),
                  label: Text('1 Yıl'),
                  onPressed: () => _setLicenseDuration(365),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),

          // Seçili Tarihler Kartı
          Card(
            elevation: 2,
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Başlangıç',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            _licenseStartDate != null
                                ? '${_licenseStartDate!.day}.${_licenseStartDate!.month}.${_licenseStartDate!.year}'
                                : 'Seçilmedi',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Icon(Icons.arrow_forward, color: Colors.grey),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Bitiş',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            _licenseEndDate != null
                                ? '${_licenseEndDate!.day}.${_licenseEndDate!.month}.${_licenseEndDate!.year}'
                                : 'Seçilmedi',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_licenseStartDate != null && _licenseEndDate != null) ...[
                    Divider(height: 24),
                    Text(
                      'Süre: ${_licenseEndDate!.difference(_licenseStartDate!).inDays} gün',
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(height: 16),

          // Özel Tarih Seç Butonu
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: Icon(Icons.edit_calendar),
              label: Text('Özel Tarih Seç'),
              onPressed: () async {
                final DateTimeRange? picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(Duration(days: 3650)), // 10 yıl
                  initialDateRange: DateTimeRange(
                    start: _licenseStartDate ?? DateTime.now(),
                    end:
                        _licenseEndDate ??
                        DateTime.now().add(Duration(days: 365)),
                  ),
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: ColorScheme.light(
                          primary: Theme.of(context).primaryColor,
                        ),
                      ),
                      child: child!,
                    );
                  },
                );

                if (picked != null) {
                  setState(() {
                    _licenseStartDate = picked.start;
                    _licenseEndDate = picked.end;
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
