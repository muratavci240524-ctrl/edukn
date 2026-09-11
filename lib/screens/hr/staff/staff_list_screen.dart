import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:edukn/services/user_permission_service.dart';
import 'package:edukn/services/crypto_service.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'staff_detail_screen.dart';
import 'staff_form_screen.dart';
import 'package:intl/intl.dart';
import 'package:file_saver/file_saver.dart';

class StaffListScreen extends StatefulWidget {
  static const routeName = '/hr/staff';
  final String? fixedSchoolTypeId;
  final String? fixedSchoolTypeName;
  
  const StaffListScreen({
    super.key,
    this.fixedSchoolTypeId,
    this.fixedSchoolTypeName,
  });

  @override
  State<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends State<StaffListScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _search = TextEditingController();
  String _statusFilter = 'active';
  Map<String, dynamic>? userData;
  String? _departmentFilter;
  String? _titleFilter;
  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _filteredStaff = [];
  Map<String, dynamic>? _selectedStaff;
  bool _isLoading = false;
  int _detectedDuplicateCount = 0;

  // Geçerli Ünvanlar Haritası (Kullanıcı Dostu İsim -> Sistem Kodu)
  final Map<String, String> _validTitlesMapping = {
    'Öğretmen': 'ogretmen',
    'Müdür': 'mudur',
    'Müdür Yardımcısı': 'mudur_yardimcisi',
    'Personel': 'personel',
    'İnsan Kaynakları': 'hr',
    'Muhasebe': 'muhasebe',
    'Satın Alma': 'satin_alma',
    'Depo Sorumlusu': 'depo',
    'Destek Hizmetleri': 'destek_hizmetleri',
    'ogretmen': 'ogretmen',
    'mudur': 'mudur',
    'mudur_yardimcisi': 'mudur_yardimcisi',
    'personel': 'personel',
    'hr': 'hr',
    'muhasebe': 'muhasebe',
    'satin_alma': 'satin_alma',
    'depo': 'depo',
    'destek_hizmetleri': 'destek_hizmetleri',
    'Diğer': 'diger',
    'diger': 'diger',
  };

  // Geçerli Branşlar Listesi (staff_form_screen ile birebir aynı)
  final List<String> _validBranches = [
    'Almanca', 'Arapça', 'Beden Eğitimi ve Spor', 'Bilişim Teknolojileri ve Yazılım',
    'Biyoloji', 'Coğrafya', 'Din Kültürü ve Ahlak Bilgisi', 'Felsefe', 'Fen Bilimleri',
    'Fizik', 'Fransızca', 'Görsel Sanatlar', 'İlköğretim Matematik', 'İngilizce',
    'İspanyolca', 'Kimya', 'Kulüp', 'Matematik', 'Müzik', 'Okul Öncesi', 'Özel Eğitim',
    'Rehberlik ve Psikolojik Danışmanlık', 'Rusça', 'Sınıf Öğretmenliği', 'Sosyal Bilgiler',
    'Tarih', 'Teknoloji ve Tasarım', 'Türk Dili ve Edebiyatı', 'Türkçe', 'Diğer'
  ];

  @override
  void initState() {
    super.initState();
    _loadStaff();
    _search.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadStaff() async {
    setState(() {
      _isLoading = true;
    });
    try {
      var user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        // Web ortamında token rehydration için kısa bekleme
        await Future.delayed(const Duration(milliseconds: 300));
        user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          if (mounted) setState(() => _isLoading = false);
          return;
        }
      }

      final email = user.email ?? '';
      userData = await UserPermissionService.loadUserData();
      final institutionId = await UserPermissionService.resolveInstitutionId(email, userData: userData);
      _institutionId = institutionId;

      final instVariants = UserPermissionService.getInstitutionIdVariants(institutionId);
      
      QuerySnapshot<Map<String, dynamic>> query;
      if (instVariants.length > 1) {
        query = await FirebaseFirestore.instance
            .collection('users')
            .where('institutionId', whereIn: instVariants)
            .get();
      } else if (instVariants.length == 1) {
        query = await FirebaseFirestore.instance
            .collection('users')
            .where('institutionId', isEqualTo: instVariants.first)
            .get();
      } else {
        query = await FirebaseFirestore.instance
            .collection('users')
            .where('institutionId', isEqualTo: institutionId)
            .get();
      }

      final items = query.docs.map((doc) {
        var data = doc.data();
        data['id'] = doc.id;
        data = CryptoService.decryptMap(data, institutionId: institutionId);
        return data;
      }).where((data) {
        final role = (data['role'] ?? '').toString().toLowerCase();
        return role != 'veli' && role != 'ogrenci' && role != 'öğrenci';
      }).toList();

      // Mükerrer kayıtları tespit et ve arayüzde tekilleştir
      final Map<String, Map<String, dynamic>> uniqueStaffMap = {};
      int dupCount = 0;

      for (final item in items) {
        final tc = (item['tcKimlik'] ?? item['tc'] ?? '').toString().trim();
        final fullName = (item['fullName'] ?? item['name'] ?? '').toString().trim().toLowerCase();
        final key = (tc.isNotEmpty && tc != '-' && tc.length >= 11) ? 'tc_$tc' : 'name_$fullName';

        if (uniqueStaffMap.containsKey(key)) {
          dupCount++;
          final existing = uniqueStaffMap[key]!;
          // Eksik auth bilgilerini veya fcmTokens'ı birleştir
          final hasAuth = (item['authUserId'] ?? item['googleUid'] ?? '').toString().isNotEmpty;
          final existingHasAuth = (existing['authUserId'] ?? existing['googleUid'] ?? '').toString().isNotEmpty;
          if (hasAuth && !existingHasAuth) {
            existing['authUserId'] = item['authUserId'];
            existing['googleUid'] = item['googleUid'];
          }
          if (item['personalEmail'] != null && (existing['personalEmail'] == null || existing['personalEmail'].toString().isEmpty)) {
            existing['personalEmail'] = item['personalEmail'];
          }
        } else {
          uniqueStaffMap[key] = Map<String, dynamic>.from(item);
        }
      }

      final deduplicatedItems = uniqueStaffMap.values.toList();

      if (mounted) {
        setState(() {
          _staff = deduplicatedItems;
          _detectedDuplicateCount = dupCount;
          _applyFilters();
          if (_filteredStaff.isNotEmpty) {
            _selectedStaff = _filteredStaff.first;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Personel listesi yüklenirken hata: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // --- MÜKERRER PERSONEL TEMİZLEME MOTORU ---

  Future<void> _scanAndCleanDuplicates() async {
    final instId = _institutionId;
    if (instId == null || instId.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.auto_fix_high_rounded, color: Colors.deepOrange),
            SizedBox(width: 8),
            Text('Mükerrer Personelleri Temizle', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: const Text(
          'Kurumdaki mükerrer personel (öğretmen) kayıtları taranacak:\n\n'
          '• Sisteme giriş esnasında açılan çift hesaplar tespit edilir.\n'
          '• Giriş kimlikleri (Auth/Google UID) ve bildirim tokenları ana hesaba güvenle aktarılır.\n'
          '• Ders programı atamaları korunur ve mükerrer klon kayıtlar veritabanından silinir.\n\n'
          'İşlemi başlatmak istiyor musunuz?',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İPTAL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('TARA VE TEMİZLE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final instVariants = UserPermissionService.getInstitutionIdVariants(instId);
      QuerySnapshot<Map<String, dynamic>> query;
      if (instVariants.length > 1) {
        query = await FirebaseFirestore.instance
            .collection('users')
            .where('institutionId', whereIn: instVariants)
            .get();
      } else {
        query = await FirebaseFirestore.instance
            .collection('users')
            .where('institutionId', isEqualTo: instId)
            .get();
      }

      final allStaff = query.docs.map((doc) {
        var data = doc.data();
        data['id'] = doc.id;
        data = CryptoService.decryptMap(data, institutionId: instId);
        return data;
      }).where((data) {
        final role = (data['role'] ?? '').toString().toLowerCase();
        return role != 'veli' && role != 'ogrenci' && role != 'öğrenci';
      }).toList();

      // Grupla: TC veya Ad Soyad bazlı
      final Map<String, List<Map<String, dynamic>>> groups = {};
      for (final s in allStaff) {
        final tc = (s['tcKimlik'] ?? s['tc'] ?? '').toString().trim();
        final fullName = (s['fullName'] ?? s['name'] ?? '').toString().trim().toLowerCase();
        if (fullName.isEmpty && tc.isEmpty) continue;

        final key = (tc.isNotEmpty && tc != '-' && tc.length >= 11) ? 'tc_$tc' : 'name_$fullName';
        groups.putIfAbsent(key, () => []).add(s);
      }

      final List<String> cleanedSummary = [];
      int deletedCount = 0;

      for (final entry in groups.entries) {
        final list = entry.value;
        if (list.length <= 1) continue;

        // Mükerrer kayıtlar bulundu!
        // 1. Ana dokümanı belirle:
        // Ders programı (lessonAssignments veya classSchedules) içinde ataması olan doküman ana kayıttır.
        Map<String, dynamic>? canonicalDoc;

        for (final doc in list) {
          final docId = doc['id'].toString();
          try {
            final laSnap = await FirebaseFirestore.instance
                .collection('lessonAssignments')
                .where('teacherIds', arrayContains: docId)
                .limit(1)
                .get();
            if (laSnap.docs.isNotEmpty) {
              canonicalDoc = doc;
              break;
            }
          } catch (_) {}

          if (canonicalDoc == null) {
            try {
              final csSnap = await FirebaseFirestore.instance
                  .collection('classSchedules')
                  .where('teacherId', isEqualTo: docId)
                  .limit(1)
                  .get();
              if (csSnap.docs.isNotEmpty) {
                canonicalDoc = doc;
                break;
              }
            } catch (_) {}
          }
        }

        // Eğer ders ataması bulunamazsa:
        // Otomatik ID'ye sahip olanı (uzunluğu < 25 ve Auth UID olmayan) ana kayıt yap
        canonicalDoc ??= list.firstWhere(
          (d) => d['id'].toString().length < 25 && !d['id'].toString().contains('-'),
          orElse: () => list.first,
        );

        final canonicalId = canonicalDoc['id'].toString();
        final duplicates = list.where((d) => d['id'].toString() != canonicalId).toList();

        // 2. Klon dokümanlardaki verileri ana dokümana aktar
        final mergeUpdates = <String, dynamic>{};
        for (final dup in duplicates) {
          final dupId = dup['id'].toString();
          final authUid = (dup['authUserId'] ?? dup['googleUid'] ?? (dupId.length >= 25 ? dupId : '')).toString().trim();
          if (authUid.isNotEmpty) {
            mergeUpdates['authUserId'] = authUid;
            mergeUpdates['googleUid'] = authUid;
          }
          final pEmail = (dup['personalEmail'] ?? '').toString().trim();
          if (pEmail.isNotEmpty && (canonicalDoc['personalEmail'] == null || canonicalDoc['personalEmail'].toString().isEmpty)) {
            mergeUpdates['personalEmail'] = pEmail;
          }
          final cEmail = (dup['corporateEmail'] ?? '').toString().trim();
          if (cEmail.isNotEmpty && (canonicalDoc['corporateEmail'] == null || canonicalDoc['corporateEmail'].toString().isEmpty)) {
            mergeUpdates['corporateEmail'] = cEmail;
          }
          final uName = (dup['username'] ?? '').toString().trim();
          if (uName.isNotEmpty && (canonicalDoc['username'] == null || canonicalDoc['username'].toString().isEmpty)) {
            mergeUpdates['username'] = uName;
          }
          final fcmTokens = dup['fcmTokens'];
          if (fcmTokens is List && fcmTokens.isNotEmpty) {
            mergeUpdates['fcmTokens'] = FieldValue.arrayUnion(fcmTokens);
          }

          // Eğer kaza eseri bu dupId'ye atanmış dersler varsa ana kayda yönlendir
          try {
            final csDupSnap = await FirebaseFirestore.instance
                .collection('classSchedules')
                .where('teacherId', isEqualTo: dupId)
                .get();
            for (final csDoc in csDupSnap.docs) {
              await csDoc.reference.update({'teacherId': canonicalId});
            }
          } catch (_) {}

          // Klon dokümanı Firestore'dan sil
          await FirebaseFirestore.instance.collection('users').doc(dupId).delete();
          deletedCount++;
        }

        // Ana dokümanı güncelle
        if (mergeUpdates.isNotEmpty) {
          mergeUpdates['updatedAt'] = FieldValue.serverTimestamp();
          await FirebaseFirestore.instance
              .collection('users')
              .doc(canonicalId)
              .set(mergeUpdates, SetOptions(merge: true));
        }

        final name = canonicalDoc['fullName'] ?? canonicalDoc['name'] ?? 'Personel';
        cleanedSummary.add('$name (${duplicates.length} mükerrer silindi)');
      }

      await _loadStaff();

      if (!mounted) return;

      if (deletedCount > 0) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.green),
                SizedBox(width: 8),
                Text('Temizleme Başarılı'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Toplam $deletedCount mükerrer personel kaydı birleştirilip silindi:\n'),
                  ...cleanedSummary.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check, size: 16, color: Colors.green),
                        const SizedBox(width: 6),
                        Expanded(child: Text(s, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      ],
                    ),
                  )),
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('TAMAM'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kurumda mükerrer personel kaydı bulunamadı. Tüm kayıtlar tekil.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Mükerrer temizleme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- EXCEL DOWNLOAD / UPLOAD LOGIC ---

  Future<void> _downloadStaffList() async {
    final excel = xl.Excel.createExcel();
    final sheet = excel['Personel_Listesi'];
    excel.delete('Sheet1');

    // Başlıklar
    final headers = [
      'TC Kimlik', 'Ad Soyad', 'Ünvan', 'Branş', 'Telefon', 
      'Kurumsal E-posta', 'Kişisel E-posta', 'Şehir', 'İlçe', 'Durum'
    ];
    sheet.appendRow(headers.map((h) => xl.TextCellValue(h)).toList());

    for (var s in _filteredStaff) {
      sheet.appendRow([
        xl.TextCellValue(s['tc'] ?? ''),
        xl.TextCellValue(s['fullName'] ?? ''),
        xl.TextCellValue(_formatRole(s['title'])),
        xl.TextCellValue(s['branch'] ?? ''),
        xl.TextCellValue(s['mobilePhone'] ?? ''),
        xl.TextCellValue(s['corporateEmail'] ?? ''),
        xl.TextCellValue(s['personalEmail'] ?? ''),
        xl.TextCellValue(s['city'] ?? ''),
        xl.TextCellValue(s['district'] ?? ''),
        xl.TextCellValue((s['isActive'] ?? true) ? 'Aktif' : 'Pasif'),
      ]);
    }

    final bytes = excel.save();
    if (bytes != null) {
      await FileSaver.instance.saveFile(
        name: 'Personel_Listesi_${DateFormat('dd_MM_yyyy').format(DateTime.now())}',
        bytes: Uint8List.fromList(bytes),
        ext: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
    }
  }

  Future<void> _downloadTemplate(bool isTeacher) async {
    final excel = xl.Excel.createExcel();
    final sheetName = isTeacher ? 'Ogretmen_Sablon' : 'Personel_Sablon';
    final sheet = excel[sheetName];
    excel.delete('Sheet1');

    // Başlıklar
    final headers = [
      'TC_KIMLIK (Zorunlu)', 
      'AD_SOYAD (Zorunlu)', 
      'UNVAN (Zorunlu)', 
      if (isTeacher) 'BRANS (Zorunlu)',
      'KULLANICI_ADI (Opsiyonel)',
      'SIFRE (Opsiyonel)',
      'TELEFON_CEP', 
      'EPOSTA_KURUMSAL',
      'SEHIR',
      'ILCE'
    ];
    
    sheet.appendRow(headers.map((h) => xl.TextCellValue(h)).toList());
    
    // Örnek veri (Kullanıcıya rehberlik eder)
    sheet.appendRow([
      xl.TextCellValue('12345678901'),
      xl.TextCellValue('ÖRNEK KAĞAN'),
      xl.TextCellValue(isTeacher ? 'Öğretmen' : 'Personel'),
      if (isTeacher) xl.TextCellValue('Matematik'),
      xl.TextCellValue(''), // Kullanıcı adı boş bırakılırsa TC son 6 hane
      xl.TextCellValue(''), // Şifre boş bırakılırsa TC son 6 hane
      xl.TextCellValue('05551112233'),
      xl.TextCellValue('kagan@edukn.com'),
      xl.TextCellValue('İstanbul'),
      xl.TextCellValue('Beşiktaş'),
    ]);

    // YARDIM SAYFASI EKLEME (Kullanıcının dropdown gibi kullanabileceği liste)
    xl.Sheet helpSheet = excel['YARDIM'];
    helpSheet.appendRow([
      xl.TextCellValue('ÜNVAN LİSTESİ'), 
      xl.TextCellValue(''), 
      xl.TextCellValue('BRANŞ LİSTESİ'),
      xl.TextCellValue(''),
      xl.TextCellValue('NOTLAR'),
    ]);
    
    // Sadece okunaklı isimleri listeleyelim (ogretmen yerine Öğretmen gibi)
    final filteredTitles = _validTitlesMapping.keys.where((k) => k.length > 5 && !k.contains('_') && k[0].toUpperCase() == k[0]).toList();
    final sortedBranches = List<String>.from(_validBranches)..sort();
    
    // Notlar
    final notes = [
      'KULLANICI_ADI boş bırakılırsa TC son 6 hane otomatik alınır.',
      'SIFRE boş bırakılırsa TC son 6 hane otomatik alınır.',
      'Branş listesinde olmayan değer yazarsanız "Diğer" olarak kaydedilir.',
      'Bu YARDIM sayfasını silmeyiniz, şablonu yüklerken otomatik atlanır.',
    ];
    
    int maxLen = [filteredTitles.length, sortedBranches.length, notes.length].reduce((a, b) => a > b ? a : b);

    for (int i = 0; i < maxLen; i++) {
      helpSheet.appendRow([
        xl.TextCellValue(i < filteredTitles.length ? filteredTitles[i] : ''),
        xl.TextCellValue(''),
        xl.TextCellValue(i < sortedBranches.length ? sortedBranches[i] : ''),
        xl.TextCellValue(''),
        xl.TextCellValue(i < notes.length ? notes[i] : ''),
      ]);
    }

    final bytes = excel.save();
    if (bytes != null) {
      final fileName = '${sheetName}_Yukleme_Sablonu.xlsx';
      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: Uint8List.fromList(bytes),
        ext: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$fileName indirildi. Lütfen YARDIM sayfasına bakınız.'),
            backgroundColor: Colors.indigo,
          ),
        );
      }
    }
  }

  Future<void> _uploadExcel() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true, // Web'de bytes'ı almak için gerekli
    );

    if (result == null || result.files.isEmpty) return;
    
    setState(() => _isLoading = true);
    
    try {
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) throw 'Dosya okunamadı. Lütfen dosyanın boş olmadığından emin olunuz.';
      
      final excel = xl.Excel.decodeBytes(bytes);
      int addedCount = 0;
      int errorCount = 0;
      int skipCount = 0;

      // Okul türü içi mi kontrol et
      final isInsideSchoolType = widget.fixedSchoolTypeId != null || (widget.fixedSchoolTypeName != null && widget.fixedSchoolTypeName!.isNotEmpty);
      final fixedSchoolName = widget.fixedSchoolTypeName?.trim() ?? '';
      final fixedSchoolId = widget.fixedSchoolTypeId;

      // Okul türünün müdürünü bul
      Map<String, dynamic>? schoolMudur;
      if (isInsideSchoolType) {
        final mudurMatches = _staff.where((u) {
          final uTitle = (u['title'] ?? '').toString().toLowerCase().trim();
          final uRole = (u['role'] ?? '').toString().toLowerCase().trim();
          final isMudurRole = uTitle == 'mudur' || uTitle == 'müdür' || uRole == 'mudur' || uRole == 'müdür';
          final uIsActive = u['isActive'] ?? true;
          if (!isMudurRole || !uIsActive) return false;

          bool stMatch = false;
          if (fixedSchoolId != null && u['schoolTypes'] is List) {
            stMatch = (u['schoolTypes'] as List).map((e) => e.toString()).contains(fixedSchoolId);
          }
          if (!stMatch && fixedSchoolName.isNotEmpty) {
            if (u['workLocations'] is List) {
              stMatch = (u['workLocations'] as List).any((l) => l.toString().toLowerCase().trim() == fixedSchoolName.toLowerCase());
            } else if (u['workLocation'] != null) {
              stMatch = u['workLocation'].toString().toLowerCase().trim() == fixedSchoolName.toLowerCase();
            }
          }
          return stMatch;
        }).toList();

        if (mudurMatches.isNotEmpty) {
          schoolMudur = mudurMatches.first;
        } else {
          // Genel müdür veya herhangi bir müdür fallback
          final anyMudur = _staff.where((u) {
            final uTitle = (u['title'] ?? '').toString().toLowerCase().trim();
            final uRole = (u['role'] ?? '').toString().toLowerCase().trim();
            return (uTitle == 'mudur' || uTitle == 'müdür' || uTitle == 'genel_mudur' || uTitle == 'genel müdür' || uRole == 'admin' || uRole == 'yonetici') && (u['isActive'] ?? true);
          }).toList();
          if (anyMudur.isNotEmpty) schoolMudur = anyMudur.first;
        }
      }

      for (var table in excel.tables.keys) {
        // YARDIM sayfasını atla
        if (table.toUpperCase().contains('YARDIM') || table.toUpperCase().contains('GECERLI')) {
          continue;
        }

        final rows = excel.tables[table]?.rows;
        if (rows == null || rows.length <= 1) continue;

        // Header mapping (cleaning (Zorunlu), (Opsiyonel) etc.)
        final headers = rows[0].map((e) {
          String h = e?.value.toString().toUpperCase() ?? '';
          return h.split('(')[0].trim(); // "TC_KIMLIK (Zorunlu)" -> "TC_KIMLIK"
        }).toList();
        
        for (int i = 1; i < rows.length; i++) {
          final row = rows[i];
          final rowData = <String, dynamic>{};
          String? customUsername;
          String? customPassword;
          
          // Tüm hücreler boş mu kontrol et
          bool allEmpty = true;
          for (int j = 0; j < row.length; j++) {
            if (row[j]?.value != null && row[j]!.value.toString().trim().isNotEmpty) {
              allEmpty = false;
              break;
            }
          }
          if (allEmpty) continue; // Boş satırları atla
          
          for (int j = 0; j < headers.length; j++) {
            if (j >= row.length) break;
            final header = headers[j];
            final value = row[j]?.value?.toString().trim();
            if (value == null || value.isEmpty) continue;
            
            if (header == 'TC_KIMLIK') rowData['tc'] = value;
            else if (header == 'AD_SOYAD') rowData['fullName'] = value.toUpperCase();
            else if (header == 'UNVAN') {
              // Map friendly name to system code
              rowData['title'] = _validTitlesMapping[value] ?? value.toLowerCase();
            }
            else if (header == 'BRANS') {
              if (_validBranches.contains(value)) {
                rowData['branch'] = value;
              } else {
                rowData['branch'] = 'Diğer';
              }
            }
            else if (header == 'KULLANICI_ADI') customUsername = value;
            else if (header == 'SIFRE') customPassword = value;
            else if (header == 'TELEFON_CEP') rowData['mobilePhone'] = value;
            else if (header == 'EPOSTA_KURUMSAL') rowData['corporateEmail'] = value;
            else if (header == 'SEHIR') rowData['city'] = value;
            else if (header == 'ILCE') rowData['district'] = value;
          }

          // Validation
          if (rowData['tc'] == null || rowData['fullName'] == null || rowData['title'] == null) {
            errorCount++;
            continue;
          }

          // Branş validation (öğretmense)
          if (rowData['title'] == 'ogretmen' && rowData['branch'] == null) {
             rowData['branch'] = 'Diğer';
          }

          // Kullanıcı adı ve şifre: önce Excel'den al, yoksa TC son 6 hane
          final tcStr = rowData['tc'].toString();
          final tcLast6 = tcStr.length >= 6 
              ? tcStr.substring(tcStr.length - 6)
              : tcStr;
          final username = (customUsername != null && customUsername.isNotEmpty) ? customUsername : tcLast6;
          final password = (customPassword != null && customPassword.isNotEmpty) ? customPassword : tcLast6;
          
          // TC şifrele
          rowData['tc'] = CryptoService.encrypt(tcStr, institutionId: _institutionId ?? '');
          rowData['tcKimlik'] = rowData['tc'];

          // Mükerrer kontrolü (aynı kullanıcı adı var mı?)
          final existCheck = await FirebaseFirestore.instance.collection('users')
              .where('institutionId', isEqualTo: _institutionId)
              .where('username', isEqualTo: username)
              .limit(1)
              .get();
          if (existCheck.docs.isNotEmpty) {
            skipCount++;
            continue;
          }

          final newUserData = <String, dynamic>{
            ...rowData,
            'institutionId': _institutionId,
            'username': username,
            'password': password,
            'defaultPassword': password,
            'passwordStatus': 'ilk_giris',
            'isActive': true,
            'type': 'staff',
            'role': rowData['title'],
            'department': rowData['department'] ?? (rowData['title'] == 'ogretmen' ? 'Öğretim Departmanı' : 'İdari Departman'),
            'createdAt': FieldValue.serverTimestamp(),
            'modulePermissions': {
              'genel_duyurular': {'enabled': true, 'level': 'editor'},
              'okul_turleri': {'enabled': true, 'level': 'viewer'},
              'insan_kaynaklari': {'enabled': false, 'level': 'viewer'},
            }
          };

          if (isInsideSchoolType) {
            if (fixedSchoolId != null) {
              newUserData['schoolTypes'] = [fixedSchoolId];
            }
            if (fixedSchoolName.isNotEmpty) {
              newUserData['workLocations'] = [fixedSchoolName];
              newUserData['workLocation'] = fixedSchoolName;
            }
            if (schoolMudur != null) {
              newUserData['managerUserId'] = schoolMudur['id'];
              newUserData['managerName'] = schoolMudur['fullName'] ?? schoolMudur['username'] ?? '';
            }
          }

          await FirebaseFirestore.instance.collection('users').add(newUserData);
          addedCount++;
        }
      }

      String msg = '$addedCount personel başarıyla eklendi.';
      if (errorCount > 0) msg += ' $errorCount satır eksik veri.';
      if (skipCount > 0) msg += ' $skipCount mükerrer atlandı.';
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.green,
        ),
      );
      _loadStaff();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yükleme hatası: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String? _institutionId;

  /// Sabit bir okul türü seçiliyse sadece o okul türündeki personelleri filtreler,
  /// değilse tüm kurum personellerini döner.
  List<Map<String, dynamic>> get _scopedStaff {
    if (widget.fixedSchoolTypeId == null &&
        (widget.fixedSchoolTypeName == null || widget.fixedSchoolTypeName!.isEmpty)) {
      return _staff;
    }
    final fixedNameLower = widget.fixedSchoolTypeName?.toLowerCase().trim() ?? '';
    final fixedId = widget.fixedSchoolTypeId;

    return _staff.where((s) {
      bool matchesSchoolType = false;
      // 1. Önce schoolTypes ID'si ile eşleşiyor mu kontrol et
      if (fixedId != null && s['schoolTypes'] != null && s['schoolTypes'] is List) {
        final stIds = List<String>.from(s['schoolTypes']);
        matchesSchoolType = stIds.contains(fixedId);
      }
      // 2. ID ile eşleşmediyse veya schoolTypes boşsa, isimle kontrol et
      if (!matchesSchoolType && fixedNameLower.isNotEmpty) {
        if (s['workLocations'] != null && s['workLocations'] is List) {
          final locations = List<String>.from(s['workLocations']);
          matchesSchoolType = locations.any((loc) => loc.toLowerCase().trim() == fixedNameLower);
        } else if (s['workLocation'] != null) {
          matchesSchoolType = s['workLocation'].toString().toLowerCase().trim() == fixedNameLower;
        }
      }
      return matchesSchoolType;
    }).toList();
  }

  void _applyFilters() {
    final query = _search.text.toLowerCase();
    setState(() {
      _filteredStaff = _scopedStaff.where((s) {
        final fullName = (s['fullName'] ?? '').toString().toLowerCase();
        final username = (s['username'] ?? '').toString().toLowerCase();
        final isActive = s['isActive'] ?? true;
        final department = (s['department'] ?? '').toString();
        final title = (s['title'] ?? '').toString();

        final matchesSearch =
            query.isEmpty ||
            fullName.contains(query) ||
            username.contains(query);

        final matchesStatus =
            _statusFilter == 'all' ||
            (_statusFilter == 'active' && isActive) ||
            (_statusFilter == 'inactive' && !isActive);

        final matchesDepartment =
            _departmentFilter == null ||
            _departmentFilter == 'Tümü' ||
            department == _departmentFilter;

        final matchesTitle =
            _titleFilter == null ||
            _titleFilter == 'Tümü' ||
            _formatTitleForFilter(title) == _titleFilter;

        return matchesSearch &&
            matchesStatus &&
            matchesDepartment &&
            matchesTitle;
      }).toList();
      
      // Branşa göre sırala, sonra isme göre
      _filteredStaff.sort((a, b) {
        final branchA = (a['branch'] ?? '').toString();
        final branchB = (b['branch'] ?? '').toString();
        
        // Branş karşılaştırması (boş olanlar sona)
        if (branchA.isEmpty && branchB.isNotEmpty) return 1;
        if (branchA.isNotEmpty && branchB.isEmpty) return -1;
        
        final branchCompare = branchA.compareTo(branchB);
        if (branchCompare != 0) return branchCompare;
        
        // Aynı branşsa isme göre sırala
        final nameA = (a['fullName'] ?? '').toString();
        final nameB = (b['fullName'] ?? '').toString();
        return nameA.compareTo(nameB);
      });
    });
  }

  List<String> _getUniqueValues(String key) {
    final values = _scopedStaff
        .map((e) => (e[key] ?? '').toString())
        .where((e) => e.isNotEmpty)
        .map((e) => key == 'title' ? _formatTitleForFilter(e) : e) // Ünvan için formatla
        .toSet()
        .toList();
    values.sort();
    return ['Tümü', ...values];
  }

  String _formatTitleForFilter(String title) {
    switch (title.toLowerCase()) {
      case 'ogretmen':
        return 'Öğretmen';
      case 'mudur':
        return 'Müdür';
      case 'mudur_yardimcisi':
        return 'Müdür Yardımcısı';
      case 'personel':
        return 'Personel';
      case 'hr':
        return 'İnsan Kaynakları';
      case 'muhasebe':
        return 'Muhasebe';
      case 'satin_alma':
        return 'Satın Alma';
      case 'depo':
        return 'Depo Sorumlusu';
      case 'destek_hizmetleri':
        return 'Destek Hizmetleri';
      case 'uzman':
        return 'Uzman';
      default:
        return title;
    }
  }

  int _getCount(String status) {
    final scoped = _scopedStaff;
    if (status == 'all') return scoped.length;
    final isActive = status == 'active';
    return scoped.where((s) => (s['isActive'] ?? true) == isActive).length;
  }

  String _formatRole(String? role) {
    if (role == null) return 'Ünvan Girilmedi';
    switch (role.toUpperCase()) {
      case 'OGRETMEN':
      case 'TEACHER':
        return 'ÖĞRETMEN';
      case 'MUDUR':
      case 'MANAGER':
        return 'MÜDÜR';
      case 'MUDUR_YARDIMCISI':
        return 'MÜDÜR YARDIMCISI';
      case 'PERSONEL':
      case 'STAFF':
        return 'PERSONEL';
      case 'OGRENCI':
      case 'STUDENT':
        return 'ÖĞRENCİ';
      case 'VELI':
      case 'PARENT':
        return 'VELİ';
      default:
        return role.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;

    final left = Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.indigo,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.groups, color: Colors.white),
                  const SizedBox(width: 8),
                  const Text(
                    'Personel',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_filteredStaff.length}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Personel ara',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _search.clear();
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _statusChip('active', 'Aktif', Icons.check_circle),
                  const SizedBox(width: 6),
                  _statusChip('inactive', 'Pasif', Icons.pause_circle),
                  const SizedBox(width: 6),
                  _statusChip('all', 'Tümü', Icons.all_inclusive),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildFilterDropdown(
                      label: 'Departman',
                      key: 'department',
                      currentValue: _departmentFilter,
                      onSelect: (val) {
                        setState(() {
                          _departmentFilter = val;
                          _applyFilters();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildFilterDropdown(
                      label: 'Ünvan',
                      key: 'title',
                      currentValue: _titleFilter,
                      onSelect: (val) {
                        setState(() {
                          _titleFilter = val;
                          _applyFilters();
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_detectedDuplicateCount > 0)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$_detectedDuplicateCount mükerrer personel tespit edildi.',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amber.shade900),
                  ),
                ),
                TextButton.icon(
                  onPressed: _scanAndCleanDuplicates,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 14, color: Colors.deepOrange),
                  label: const Text('Temizle', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _filteredStaff.length,
                  itemBuilder: (_, i) {
                    final staff = _filteredStaff[i];
                    final isSelected =
                        _selectedStaff != null &&
                        _selectedStaff!['id'] == staff['id'];
                    return Card(
                      elevation: isWide && isSelected ? 2 : 0.5,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isSelected
                              ? Colors.indigo
                              : Colors.grey.shade300,
                        ),
                      ),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isSelected
                              ? Colors.indigo
                              : Colors.indigo.shade100,
                          child: const Icon(Icons.person, color: Colors.white),
                        ),
                        title: Text(staff['fullName'] ?? 'Ad Soyad'),
                        subtitle: Text(
                          _formatRole(staff['title']) + 
                          (staff['branch'] != null && staff['branch'].toString().isNotEmpty 
                              ? ' - ${staff['branch']}' 
                              : ''),
                        ),

                        selected: isSelected,
                        onTap: () {
                          setState(() {
                            _selectedStaff = staff;
                          });
                          if (!isWide) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => Scaffold(
                                  backgroundColor: const Color(0xFFF8FAFC),
                                  appBar: EduknAppBar(
                                    title: staff['fullName'] ?? 'Personel Detayı',
                                  ),
                                  body: StaffDetailScreen(staff: staff),
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );

    final right = StaffDetailScreen(staff: _selectedStaff);

    return Scaffold(
      appBar: EduknAppBar(
        title: 'Personel Listesi',
        subtitle: widget.fixedSchoolTypeName,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'download_list':
                  _downloadStaffList();
                  break;
                case 'template_staff':
                  _downloadTemplate(false);
                  break;
                case 'template_teacher':
                  _downloadTemplate(true);
                  break;
                case 'upload_excel':
                  _uploadExcel();
                  break;
                case 'clean_duplicates':
                  _scanAndCleanDuplicates();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clean_duplicates',
                child: Row(
                  children: [
                    Icon(Icons.auto_fix_high_rounded, size: 20, color: Colors.deepOrange),
                    SizedBox(width: 8),
                    Text('Mükerrerleri Tara ve Temizle', style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'download_list',
                child: Row(children: [Icon(Icons.download, size: 20), SizedBox(width: 8), Text('Personel Listesi İndir')]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'template_staff',
                child: Row(children: [Icon(Icons.file_download_outlined, size: 20, color: Colors.blue), SizedBox(width: 8), Text('Örnek Şablon (Personel)')]),
              ),
              const PopupMenuItem(
                value: 'template_teacher',
                child: Row(children: [Icon(Icons.file_download_outlined, size: 20, color: Colors.indigo), SizedBox(width: 8), Text('Örnek Şablon (Öğretmen)')]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'upload_excel',
                child: Row(children: [Icon(Icons.upload_file_rounded, size: 20, color: Colors.green), SizedBox(width: 8), Text('Excel ile Toplu Yükle')]),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => StaffFormScreen(
                fixedSchoolTypeName: widget.fixedSchoolTypeName,
                fixedSchoolTypeId: widget.fixedSchoolTypeId,
              ),
            ),
          );
          // Personel eklendiyse listeyi yenile
          if (result == true && mounted) {
            await _loadStaff();
          }
        },
        icon: const Icon(Icons.person_add),
        label: const Text('Yeni Personel'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: isWide
            ? Row(
                children: [
                  SizedBox(width: 380, child: left),
                  const VerticalDivider(width: 20),
                  Expanded(child: StaffDetailScreen(staff: _selectedStaff)),
                ],
              )
            : left,
      ),
    );
  }

  Widget _statusChip(String value, String label, IconData icon) {
    final isSelected = _statusFilter == value;
    final count = _getCount(value);

    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          _statusFilter = value;
          _applyFilters();
        }),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.white24,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.indigo : Colors.white,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '$label ($count)',
                  style: TextStyle(
                    color: isSelected ? Colors.indigo : Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String key,
    required String? currentValue,
    required Function(String?) onSelect,
  }) {
    final items = _getUniqueValues(key);
    final isActive = currentValue != null;

    return PopupMenuButton<String>(
      tooltip: '$label Seç',
      itemBuilder: (context) => items.map((item) {
        final isSelected =
            item == currentValue || (item == 'Tümü' && currentValue == null);
        return PopupMenuItem<String>(
          value: item,
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color: isSelected ? Colors.indigo : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                item,
                style: TextStyle(
                  color: isSelected ? Colors.indigo : Colors.black87,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onSelected: (value) {
        onSelect(value == 'Tümü' ? null : value);
      },
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: isActive ? Colors.indigo.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? Colors.indigo : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.filter_list,
              size: 16,
              color: isActive ? Colors.indigo : Colors.grey,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                currentValue ?? label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isActive ? Colors.indigo : Colors.black87,
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: isActive ? Colors.indigo : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}

