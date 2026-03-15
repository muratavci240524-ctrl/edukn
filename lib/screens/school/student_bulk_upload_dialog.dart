import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../services/term_service.dart';

class StudentBulkUploadDialog extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String? termId;

  const StudentBulkUploadDialog({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    this.termId,
  }) : super(key: key);

  @override
  State<StudentBulkUploadDialog> createState() =>
      _StudentBulkUploadDialogState();
}

class _StudentBulkUploadDialogState extends State<StudentBulkUploadDialog> {
  // States
  bool _isProcessing = false;
  bool _isFileLoaded = false;
  bool _isUploadComplete = false;

  // Data
  List<Map<String, dynamic>> _parsedStudents =
      []; // Excel'den okunan ham veriler
  List<Map<String, dynamic>> _classList = []; // Esnek arama için liste
  Map<String, String> _existingStudentsMap =
      {}; // TC -> docId (Var olanları kontrol için)
  Set<String> _existingStudentNos =
      {}; // Okul Numaraları (Unique kontrolü için)

  // Stats
  List<String> _logs = [];
  int _successCount = 0;
  int _failCount = 0;
  int _updatedCount = 0;

  // Initialization
  late Future<void> _initializationFuture;

  @override
  void initState() {
    super.initState();
    _initializationFuture = _loadClasses();
  }

  // 1. Sınıf bilgilerini önceden yükle (Donmayı engellemek için init'te değil FutureBuilder'da)
  Future<void> _loadClasses() async {
    try {
      String? termId = widget.termId;
      if (termId == null) {
        termId = await TermService().getActiveTermId();
      }
      if (termId == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('termId', isEqualTo: termId)
          .get();

      final List<Map<String, dynamic>> loadedClasses = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();

        // HAM VERİYİ LOGLA!!!
        debugPrint('RAW CLASS DATA: $data');

        // Görünmez karakterleri temizle (Zero width space vb.)
        String cleanStr(dynamic val) {
          if (val == null) return '';
          return val
              .toString()
              .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '') // Görünmezler
              .trim();
        }

        loadedClasses.add({
          'id': doc.id,
          'level': cleanStr(data['classLevel'] ?? data['level']),
          'branch': cleanStr(data['className'] ?? data['branch']),
          'name': cleanStr(data['name']),
          'rawData': data.toString(),
        });
      }
      _classList = loadedClasses;

      _addLog(
        '📚 Sınıf Listesi Yüklendi. Dönem: $termId, Toplam Sınıf: ${loadedClasses.length}',
      );

      // Debug: Tüm sınıfları listele (Sorunu görmek için)
      if (loadedClasses.isNotEmpty) {
        _addLog('📋 MEVCUT SINIFLAR (DB):');
        for (var c in loadedClasses) {
          String detail = '[${c['level']}] - [${c['branch']}]';
          if ((c['level']?.toString().isEmpty ?? true)) {
            detail += ' ⚠ RAW: ${c['rawData']}';
          }
          _addLog('   🔹 $detail (ID: ${c['id']})');
        }
      }

      await _cacheExistingStudents();
    } catch (e) {
      debugPrint('Sınıf listesi yüklenemedi: $e');
      _addLog('❌ Sınıf listesi yüklenirken hata oluştu: $e', isError: true);
    }
  }

  Future<void> _cacheExistingStudents() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .get();

      _existingStudentsMap.clear();
      _existingStudentNos.clear();
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final tc = data['tcNo']?.toString();
        final no = data['studentNo']?.toString();

        if (tc != null && tc.isNotEmpty) {
          _existingStudentsMap[tc] = doc.id;
        }
        if (no != null && no.isNotEmpty) {
          _existingStudentNos.add(no);
        }
      }
    } catch (e) {
      debugPrint('Mevcut öğrenci cache hatası: $e');
    }
  }

  // Şablon İndirme
  Future<void> _downloadTemplate() async {
    try {
      var excel = Excel.createExcel();
      Sheet sheet = excel['Öğrenci Kayıt Şablonu'];
      excel.delete('Sheet1');

      // Stiller
      CellStyle mandatoryStyle = CellStyle(
        fontColorHex: ExcelColor.fromHexString("#FF0000"),
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );
      CellStyle optionalStyle = CellStyle(
        fontColorHex: ExcelColor.fromHexString("#000000"),
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );

      final headers = [
        {'text': 'TC Kimlik No', 'mandatory': true},
        {'text': 'Ad', 'mandatory': true},
        {'text': 'Soyad', 'mandatory': true},
        {'text': 'Okul Numarası', 'mandatory': false},
        {'text': 'Cinsiyet (E/K)', 'mandatory': false},
        {'text': 'Sınıf Seviyesi', 'mandatory': false},
        {'text': 'Şube', 'mandatory': false},
        {'text': 'Doğum Tarihi (GG.AA.YYYY)', 'mandatory': false},
        {'text': 'Öğrenci Telefon', 'mandatory': false},
        {'text': 'Veli Ad Soyad', 'mandatory': false},
        {'text': 'Veli TC', 'mandatory': false},
        {'text': 'Veli Telefon', 'mandatory': false},
        {'text': 'Veli Yakınlık', 'mandatory': false},
      ];

      for (int i = 0; i < headers.length; i++) {
        var cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
        );
        cell.value = TextCellValue(headers[i]['text'] as String);
        cell.cellStyle = (headers[i]['mandatory'] as bool)
            ? mandatoryStyle
            : optionalStyle;
        sheet.setColumnWidth(i, 20.0);
      }

      final sampleRow = [
        '11111111111',
        'Ali',
        'Yılmaz',
        '123',
        'E',
        '9',
        'A',
        '01.01.2010',
        '05551112233',
        'Ayşe Yılmaz',
        '22222222222',
        '05554445566',
        'Anne',
      ];
      for (int i = 0; i < sampleRow.length; i++) {
        var cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1),
        );
        cell.value = TextCellValue(sampleRow[i]);
      }

      List<int>? fileBytes = excel.save();
      if (fileBytes != null) {
        await FileSaver.instance.saveFile(
          name: 'Ogrenci_Kayit_Sablonu',
          bytes: Uint8List.fromList(fileBytes),
          ext: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('✅ Şablon indirildi.')));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  // Helper: Tarih Formatlama
  String _formatDate(dynamic val) {
    if (val == null) return '';
    try {
      if (val is DateTime) {
        return "${val.day.toString().padLeft(2, '0')}.${val.month.toString().padLeft(2, '0')}.${val.year}";
      }
      String s = val.toString().trim();
      // ISO (2012-10-09) kontrolü
      if (s.contains('-') && s.length > 8) {
        // YYYY-MM-DD
        DateTime d = DateTime.parse(s);
        return "${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}";
      }
      return s;
    } catch (e) {
      return val.toString();
    }
  }

  // 2. Excel Yükleme ve Parse Etme
  Future<void> _pickAndParseFile() async {
    setState(() => _isProcessing = true);

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        Uint8List? fileBytes = result.files.first.bytes;
        if (fileBytes == null) return;

        await Future.delayed(Duration(milliseconds: 100)); // UI nefes alsın

        var excel = Excel.decodeBytes(fileBytes);
        final table = excel.tables[excel.tables.keys.first];

        if (table == null) return;

        List<Map<String, dynamic>> tempStudents = [];

        // Başlık satırını akıllı bul (İlk 10 satırda ara)
        List<Data?>? headerRow;
        int headerIndex = 0;

        for (int i = 0; i < table.rows.length && i < 10; i++) {
          final row = table.rows[i];
          // Satırda 'tc' veya 'ad' veya 'numara' geçen bir hücre var mı?
          bool isHeader = row.any((cell) {
            String v = cell?.value.toString().toLowerCase() ?? '';
            return (v.contains('tc') && v.contains('kimlik')) ||
                v == 'ad' ||
                v == 'soyad' ||
                v.contains('no');
          });

          if (isHeader) {
            headerRow = row;
            headerIndex = i;
            break;
          }
        }

        // Bulamazsa varsayılan 0. satır
        if (headerRow == null && table.rows.isNotEmpty) {
          headerRow = table.rows[0];
        }

        // Başlık haritası oluştur (Header Mapping)
        Map<String, int> colMap = {};
        if (headerRow != null) {
          for (int i = 0; i < headerRow.length; i++) {
            String h =
                headerRow[i]?.value.toString().trim().toLowerCase() ?? '';
            if (h.contains('tc') && h.contains('kimlik'))
              colMap['tc'] = i;
            else if (h == 'ad')
              colMap['name'] = i;
            else if (h == 'soyad')
              colMap['surname'] = i;
            else if (h.contains('okul') && h.contains('no'))
              colMap['no'] = i;
            else if (h.contains('cinsiyet'))
              colMap['gender'] = i;
            else if (h.contains('seviye'))
              colMap['level'] = i;
            else if (h.contains('şube') || h.contains('sube'))
              colMap['branch'] = i;
            else if (h.contains('doğum') || h.contains('dogum'))
              colMap['birth'] = i;
            else if (h.contains('öğrenci') && h.contains('telefon'))
              colMap['studentPhone'] = i;
            else if (h.contains('veli') &&
                (h.contains('ad') || h.contains('isim')))
              colMap['parentName'] = i;
            else if (h.contains('veli') &&
                !h.contains('tc') &&
                !h.contains('telefon') &&
                !h.contains('yakınlık') &&
                !colMap.containsKey('parentName'))
              colMap['parentName'] = i;
            else if (h.contains('veli') && h.contains('tc'))
              colMap['parentTc'] = i;
            else if (h.contains('veli') && h.contains('telefon'))
              colMap['parentPhone'] = i;
            else if (h.contains('yakınlık') || h.contains('yakinlik'))
              colMap['relation'] = i;
          }
        }

        // Default Fallback
        if (!colMap.containsKey('tc')) colMap['tc'] = 0;
        if (!colMap.containsKey('name')) colMap['name'] = 1;
        if (!colMap.containsKey('surname')) colMap['surname'] = 2;
        if (!colMap.containsKey('no')) colMap['no'] = 3;
        if (!colMap.containsKey('gender')) colMap['gender'] = 4;
        if (!colMap.containsKey('level')) colMap['level'] = 5;
        if (!colMap.containsKey('branch')) colMap['branch'] = 6;
        if (!colMap.containsKey('birth')) colMap['birth'] = 7;
        if (!colMap.containsKey('studentPhone')) colMap['studentPhone'] = 8;
        if (!colMap.containsKey('parentName')) colMap['parentName'] = 9;
        if (!colMap.containsKey('parentTc')) colMap['parentTc'] = 10;
        if (!colMap.containsKey('parentPhone')) colMap['parentPhone'] = 11;
        if (!colMap.containsKey('relation')) colMap['relation'] = 12;

        // Satır satır oku (Header'dan sonraki satırdan başla)
        for (int i = headerIndex + 1; i < table.rows.length; i++) {
          final row = table.rows[i];
          if (row.isEmpty) continue;

          // Helper to get safely and cleanup (örn 9.0 -> 9)
          String getVal(int index) {
            var val = (index < row.length ? row[index]?.value : null);
            if (val == null) return '';
            String str = val.toString().trim();
            if (val is double && str.endsWith('.0')) {
              str = str.substring(0, str.length - 2);
            }
            // String olarak "9.0" geldiyse
            if (str.endsWith('.0')) str = str.substring(0, str.length - 2);
            return str;
          }

          // Temel veriler
          String tc = getVal(colMap['tc']!);
          String ad = getVal(colMap['name']!);
          String soyad = getVal(colMap['surname']!);
          String okulNo = getVal(colMap['no']!);
          String sinifSeviyesi = getVal(colMap['level']!);
          String sube = getVal(colMap['branch']!);

          // Boş satır kontrolü
          if (tc.isEmpty && ad.isEmpty && soyad.isEmpty) continue;

          // Duplicate Kontrolü
          // TC varmı?
          bool tcExists = _existingStudentsMap.containsKey(tc);
          // Okul No varmı?
          bool noExists =
              okulNo.isNotEmpty && _existingStudentNos.contains(okulNo);

          String status = 'Yeni Kayıt';
          bool isValid = true;
          String? errorMsg;

          if (tc.isEmpty || ad.isEmpty || soyad.isEmpty) {
            isValid = false;
            errorMsg = 'Zorunlu alanlar eksik';
            status = 'HATA: Eksik Bilgi';
          } else if (tcExists) {
            isValid = false;
            errorMsg = 'Bu TC ile kayıtlı öğrenci var';
            status = 'HATA: TC Kayıtlı';
          } else if (noExists) {
            isValid = false;
            errorMsg = 'Bu Okul No ($okulNo) kullanımda';
            status = 'HATA: No Kayıtlı';
          }

          tempStudents.add({
            'tcNo': tc,
            'name': ad,
            'surname': soyad,
            'studentNo': okulNo,
            'gender': getVal(colMap['gender']!),
            'classLevel': sinifSeviyesi,
            'branch': sube,
            'birthDate': _formatDate(
              row[colMap['birth']!]?.value,
            ), // Doğum Tarihi (Formatla)
            'phone': getVal(colMap['studentPhone']!),
            'parentName': getVal(colMap['parentName']!),
            'parentTc': getVal(colMap['parentTc']!),
            'parentPhone': getVal(colMap['parentPhone']!),
            'parentRelation': getVal(colMap['relation']!),
            'status': status,
            'isValid': isValid,
            'error': errorMsg,
          });

          // UI donmasın
          if (i % 20 == 0) await Future.delayed(Duration(milliseconds: 1));
        }

        setState(() {
          _parsedStudents = tempStudents;
          _isFileLoaded = true;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Dosya okuma hatası: $e')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // 3. Tablodan satır silme
  void _removeRow(int index) {
    setState(() {
      _parsedStudents.removeAt(index);
    });
  }

  // 4. Tablodan satır düzenleme
  void _editRow(int index) {
    final student = _parsedStudents[index];
    final tcCtrl = TextEditingController(text: student['tcNo']);
    final nameCtrl = TextEditingController(text: student['name']);
    final surnameCtrl = TextEditingController(text: student['surname']);
    final noCtrl = TextEditingController(text: student['studentNo']);
    final classCtrl = TextEditingController(text: student['classLevel']);
    final branchCtrl = TextEditingController(text: student['branch']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Öğrenci Düzenle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: tcCtrl,
                decoration: InputDecoration(labelText: 'TC Kimlik No'),
              ),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(labelText: 'Ad'),
              ),
              TextField(
                controller: surnameCtrl,
                decoration: InputDecoration(labelText: 'Soyad'),
              ),
              TextField(
                controller: noCtrl,
                decoration: InputDecoration(labelText: 'Okul No'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: classCtrl,
                      decoration: InputDecoration(labelText: 'Sınıf Seviyesi'),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: branchCtrl,
                      decoration: InputDecoration(labelText: 'Şube'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                student['tcNo'] = tcCtrl.text;
                student['name'] = nameCtrl.text;
                student['surname'] = surnameCtrl.text;
                student['studentNo'] = noCtrl.text;
                student['classLevel'] = classCtrl.text;
                student['branch'] = branchCtrl.text;

                // TC değiştiyse durum ve geçerlilik tekrar kontrol edilmeli
                bool isExisting = _existingStudentsMap.containsKey(tcCtrl.text);
                student['status'] = isExisting
                    ? 'Mevcut (Güncellenecek)'
                    : 'Yeni Kayıt';
                student['isValid'] =
                    tcCtrl.text.isNotEmpty &&
                    nameCtrl.text.isNotEmpty &&
                    surnameCtrl.text.isNotEmpty;
              });
              Navigator.pop(context);
            },
            child: Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  // 5. Kesin Kayıt İşlemi (Firestore'a Basma)
  Future<void> _startUpload() async {
    setState(() {
      _isProcessing = true;
      _isUploadComplete = false;
      _logs = [];
      _successCount = 0;
      _failCount = 0;
      _updatedCount = 0;
    });

    int _total = _parsedStudents.length;
    _addLog('🚀 İşlem başlatılıyor... Toplam $_total kayıt.');

    for (int i = 0; i < _parsedStudents.length; i++) {
      final item = _parsedStudents[i];
      if (item['isValid'] == false) {
        _failCount++;
        _addLog('❌ Geçersiz kayıt atlandı: ${item['name']} ${item['surname']}');
        continue;
      }

      await _processSingleStudent(item, i + 1);

      // UI Update
      if (i % 5 == 0) await Future.delayed(Duration(milliseconds: 1));
    }

    _addLog(
      '🏁 İŞLEM TAMAMLANDI. Başarılı: $_successCount, Güncellenen: $_updatedCount, Hata: $_failCount',
      isSuccess: true,
    );
    setState(() {
      _isProcessing = false;
      _isUploadComplete = true;
    });
  }

  Future<void> _processSingleStudent(
    Map<String, dynamic> item,
    int index,
  ) async {
    try {
      final tc = item['tcNo'];

      // Sınıf Bulma
      String? classId;
      String? className;
      String level = item['classLevel'] ?? '';
      String branch = item['branch'] ?? '';

      // Temizlik (9.0 -> 9 gibi durumlar zaten parse ederken çözüldü ama yine de trim)
      level = level.trim();
      branch = branch.trim();

      if (level.isNotEmpty && branch.isNotEmpty) {
        // En iyi eşleşmeyi bul
        // Excel Level: "8" -> DB Level: "8. Sınıf"
        // Excel Branch: "801" -> DB Branch: "801 - Ders Sınıfı"

        try {
          // Görünmez karakter temizliği local func
          String cleanStr(String s) =>
              s.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '').trim();

          // Excel Verileri
          String excelLevelClean = cleanStr(level);
          String excelBranchClean = cleanStr(branch);

          // 1. Rakam Bazlı Eşleştirme (En Güvenlisi)
          // DB: "8. Sınıf" -> "8"
          // Excel: "8" -> "8"
          String excelLevelDigits = excelLevelClean.replaceAll(
            RegExp(r'[^0-9]'),
            '',
          );
          String excelBranchDigits = excelBranchClean.replaceAll(
            RegExp(r'[^0-9]'),
            '',
          );

          final foundClass = _classList.firstWhere((cls) {
            String dbLevel = cls['level'];
            String dbBranch = cls['branch'];

            // Level Temizliği (Rakam)
            String dbLevelDigits = dbLevel.replaceAll(RegExp(r'[^0-9]'), '');

            bool levelMatch = false;
            if (dbLevelDigits.isNotEmpty && excelLevelDigits.isNotEmpty) {
              // Rakam Eşleşmesi
              levelMatch = (dbLevelDigits == excelLevelDigits);
            } else {
              // Rakam yoksa String Eşleşmesi (örn: Anaokulu)
              levelMatch =
                  dbLevel.replaceAll(' ', '').toUpperCase() ==
                  excelLevelClean.replaceAll(' ', '').toUpperCase();
            }

            if (!levelMatch) return false;

            // Branch Temizliği (Rakam)
            String dbBranchDigits = dbBranch.replaceAll(RegExp(r'[^0-9]'), '');

            bool branchMatch = false;
            if (dbBranchDigits.isNotEmpty && excelBranchDigits.isNotEmpty) {
              // Rakam Eşleşmesi (Branch)
              branchMatch = (dbBranchDigits == excelBranchDigits);
            }

            // Rakamla bulamadıysak Text ile dene
            if (!branchMatch) {
              String dbBranchNorm = dbBranch.replaceAll(' ', '').toUpperCase();
              String excelBranchNorm = excelBranchClean
                  .replaceAll(' ', '')
                  .toUpperCase();
              if (dbBranchNorm == excelBranchNorm) branchMatch = true;
              if (!branchMatch && dbBranchNorm.contains(excelBranchNorm))
                branchMatch = true;
              if (!branchMatch && excelBranchNorm.contains(dbBranchNorm))
                branchMatch = true;
            }

            return branchMatch;
          }, orElse: () => {});

          if (foundClass.isNotEmpty) {
            classId = foundClass['id'];
            // Şube İsmi Düzeltmesi: Eğer şube zaten seviyeyi içeriyorsa (Örn: 8. Sınıf, Şube 806)
            // Sadece şubeyi yaz. Yoksa birleştir.
            String l = foundClass['level'].toString();
            String b = foundClass['branch'].toString();
            if (b.startsWith(l)) {
              className = b; // "806"
            } else {
              className = '$l $b'; // "8 A"
            }
          } else {
            // Hata Logu: Olası adayları (Sadece Level'i uyanları) göster
            String candidates = _classList
                .where((c) {
                  String dl = c['level'].toString().replaceAll(
                    RegExp(r'[^0-9]'),
                    '',
                  );
                  return dl == excelLevelDigits;
                })
                .map((c) => "'${c['branch']}'")
                .join(', ');

            classId = null;
            _addLog(
              '⚠ Sınıf Bulunamadı: Sınıf="$level" (Rakam:$excelLevelDigits), Şube="$branch" (Rakam:$excelBranchDigits).\n'
              '   DB Aday Şubeler: [$candidates]',
            );
          }
        } catch (e) {
          _addLog('⚠ Sınıf arama hatası: $level-$branch ($e)');
        }
      }

      // Cinsiyet Normalizasyonu
      String? gender;
      String gRaw = item['gender']?.toString().toUpperCase() ?? '';
      if (gRaw.startsWith('E')) gender = 'Erkek';
      if (gRaw.startsWith('K')) gender = 'Kız';

      // Veli Hazırlığı
      List<Map<String, dynamic>> parents = [];
      if ((item['parentName'] ?? '').isNotEmpty) {
        String pFull = item['parentName'].toString().trim();

        // KULLANICI İSTEĞİ: Ad Soyad birleşik olsun.
        parents.add({
          'name': pFull,
          'surname': '',
          'fullName': pFull,
          'tcNo': item['parentTc'],
          'phone': item['parentPhone'],
          'relation': (item['parentRelation'] ?? '').isNotEmpty
              ? item['parentRelation']
              : 'Veli',
        });
      }

      // Kullanıcı Adı ve Şifre Oluşturma (TC Son 6 Hane)
      String username = '';
      String password = '';
      if (tc != null && tc.length >= 6) {
        username = tc.substring(tc.length - 6);
        password = tc.substring(tc.length - 6);
      } else {
        username = tc ?? '';
        password = tc ?? '';
      }

      final Map<String, dynamic> studentData = {
        'institutionId': widget.institutionId,
        'schoolTypeId': widget.schoolTypeId,
        'termId': widget.termId,
        'tcNo': tc,
        'name': item['name'],
        'surname': item['surname'],
        'fullName': '${item['name']} ${item['surname']}',
        'gender': gender,
        'phone': item['phone'],
        'studentNo': item['studentNo'],
        'studentNumber': item['studentNo'],
        'birthDate': item['birthDate'],
        'username': username,
        'password': password,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (classId != null) {
        studentData['classId'] = classId;
        studentData['className'] = className;
        studentData['classLevel'] = level;
      }
      if (parents.isNotEmpty) {
        studentData['parents'] = parents;
      }

      // İşlem
      if (_existingStudentsMap.containsKey(tc)) {
        // Update
        String docId = _existingStudentsMap[tc]!;
        await FirebaseFirestore.instance
            .collection('students')
            .doc(docId)
            .update(studentData);
        _updatedCount++;
        _addLog('🔄 Güncellendi: ${item['name']} ${item['surname']}');
      } else {
        // Create
        studentData['isActive'] = true;
        studentData['createdAt'] = FieldValue.serverTimestamp();
        studentData['registrationType'] = 'excel_import';
        if ((item['studentNo'] ?? '').isEmpty) studentData['studentNo'] = null;

        await FirebaseFirestore.instance
            .collection('students')
            .add(studentData);
        _successCount++;
        _addLog(
          '✅ Eklendi: ${item['name']} ${item['surname']}',
          isSuccess: true,
        );
      }
    } catch (e) {
      _failCount++;
      _addLog('❌ Hata ($index): $e', isError: true);
    }
  }

  void _addLog(String msg, {bool isSuccess = false, bool isError = false}) {
    // Sadece log ekranı açıksa göster
    setState(() {
      _logs.insert(0, msg);
    });
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: FutureBuilder(
        future: _initializationFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Container(
              width: 300,
              height: 200,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Sistem hazırlanıyor...'),
                  ],
                ),
              ),
            );
          }

          return Container(
            width: 1000,
            height: 800,
            padding: EdgeInsets.all(24),
            child: Column(
              children: [
                // Header
                Row(
                  children: [
                    Icon(Icons.backup_table, size: 32, color: Colors.indigo),
                    SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Toplu Öğrenci Yükleme',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Excel dosyasını yükleyin, önizleyin ve onaylayın.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                    Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close),
                    ),
                  ],
                ),
                Divider(height: 30),

                // Adım 1: Dosya Seçimi (Eğer dosya yüklenmediyse göster)
                if (!_isFileLoaded)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.upload_file,
                            size: 80,
                            color: Colors.blue.shade100,
                          ),
                          SizedBox(height: 24),
                          Text(
                            'Başlamak için bir Excel dosyası seçin',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'İndirdiğiniz şablonu doldurup buraya yükleyin.',
                            style: TextStyle(color: Colors.grey),
                          ),
                          SizedBox(height: 32),
                          _isProcessing
                              ? CircularProgressIndicator()
                              : ElevatedButton.icon(
                                  onPressed: _pickAndParseFile,
                                  icon: Icon(Icons.folder_open),
                                  label: Text(
                                    'Excel Dosyası Seç',
                                    style: TextStyle(fontSize: 16),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.indigo,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 32,
                                      vertical: 20,
                                    ),
                                  ),
                                ),
                          SizedBox(height: 16),
                          TextButton(
                            onPressed: _downloadTemplate,
                            child: Text(
                              'Şablonu henüz indirmediniz mi? Buradan indirin.',
                              style: TextStyle(color: Colors.blue),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  // Adım 2: Tablo Önizleme
                  Expanded(
                    child: Column(
                      children: [
                        // Üst Bar (Stats & Actions)
                        Row(
                          children: [
                            Text(
                              'Toplam Kayıt: ${_parsedStudents.length}',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            SizedBox(width: 16),
                            Chip(
                              label: Text(
                                'Mevcut: ${_parsedStudents.where((s) => s['status'].contains('Mevcut')).length}',
                              ),
                              backgroundColor: Colors.blue.shade100,
                            ),
                            SizedBox(width: 8),
                            Chip(
                              label: Text(
                                'Yeni: ${_parsedStudents.where((s) => s['status'].contains('Yeni')).length}',
                              ),
                              backgroundColor: Colors.green.shade100,
                            ),
                            Spacer(),
                            // Reset Button
                            if (!_isProcessing)
                              TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _isFileLoaded = false;
                                    _parsedStudents = [];
                                    _logs = [];
                                  });
                                },
                                icon: Icon(Icons.refresh, size: 18),
                                label: Text('Dosyayı Değiştir'),
                              ),
                          ],
                        ),
                        SizedBox(height: 12),

                        // Table Area
                        Expanded(
                          // Önizleme Tablosu: İşlem başlamadıysa ve henüz tamamlanmadıysa göster
                          child: (!_isProcessing && !_isUploadComplete)
                              ? // LOG DEĞİL TABLO GÖSTER
                                Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: ListView.separated(
                                    itemCount: _parsedStudents.length,
                                    separatorBuilder: (c, i) =>
                                        Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final student = _parsedStudents[index];
                                      bool isError =
                                          student['isValid'] == false;
                                      bool isUpdate = student['status']
                                          .contains('Mevcut');

                                      return Container(
                                        color: isError
                                            ? Colors.red.shade50
                                            : (isUpdate
                                                  ? Colors.blue.shade50
                                                  : Colors.white),
                                        child: ListTile(
                                          leading: CircleAvatar(
                                            backgroundColor: isError
                                                ? Colors.red
                                                : (isUpdate
                                                      ? Colors.blue
                                                      : Colors.green),
                                            child: Icon(
                                              isError
                                                  ? Icons.error
                                                  : (isUpdate
                                                        ? Icons.refresh
                                                        : Icons.add),
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                          ),
                                          title: Text(
                                            '${student['name']} ${student['surname']} (${student['tcNo']})',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          subtitle: Text(
                                            '${student['studentNo']} - ${student['classLevel']}/${student['branch']} | Durum: ${student['status']}',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: Icon(
                                                  Icons.edit,
                                                  color: Colors.blue,
                                                ),
                                                onPressed: _isProcessing
                                                    ? null
                                                    : () => _editRow(index),
                                              ),
                                              IconButton(
                                                icon: Icon(
                                                  Icons.delete,
                                                  color: Colors.red,
                                                ),
                                                onPressed: _isProcessing
                                                    ? null
                                                    : () => _removeRow(index),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                )
                              : // LOG VARSA LOG GÖSTER (İşlem sırasında)
                                Container(
                                  color: Colors.black87,
                                  padding: EdgeInsets.all(12),
                                  child: ListView.builder(
                                    itemCount: _logs.length,
                                    itemBuilder: (c, i) => Text(
                                      _logs[i],
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'monospace',
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                        ),

                        SizedBox(height: 16),
                        // Bottom Actions
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (_isProcessing)
                              CircularProgressIndicator()
                            else if (_isUploadComplete)
                              ElevatedButton.icon(
                                onPressed: () => Navigator.pop(context),
                                icon: Icon(Icons.check),
                                label: Text(
                                  'İşlem Tamamlandı, Pencereyi Kapat',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey.shade800,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 16,
                                  ),
                                ),
                              )
                            else
                              ElevatedButton.icon(
                                onPressed: _parsedStudents.isEmpty
                                    ? null
                                    : _startUpload,
                                icon: Icon(Icons.check_circle),
                                label: Text('Onayla ve Kaydı Başlat'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 16,
                                  ),
                                  textStyle: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
