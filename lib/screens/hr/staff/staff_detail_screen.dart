import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../firebase_options.dart';
import 'package:edukn/services/pdf_service.dart';

class StaffDetailScreen extends StatefulWidget {
  final Map<String, dynamic>? staff;
  const StaffDetailScreen({super.key, this.staff});

  @override
  State<StaffDetailScreen> createState() => _StaffDetailScreenState();
}

class _StaffDetailScreenState extends State<StaffDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _pdfService = PdfService();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _showExportDialog() async {
    final staff = widget.staff;
    if (staff == null) return;

    // Varsayılan olarak seçili bölümler
    bool includePersonal = true;
    bool includeJob = true;
    bool includeEducation = true;
    bool includeExperience = true;
    bool includeFiles = true;
    bool includeStatus = true;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Yazdır / Dışa Aktar'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Rapora dahil edilecek bölümleri seçiniz:'),
              const SizedBox(height: 10),
              CheckboxListTile(
                title: const Text('Kişisel Bilgiler'),
                value: includePersonal,
                onChanged: (v) => setState(() => includePersonal = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                title: const Text('Görev Bilgileri'),
                value: includeJob,
                onChanged: (v) => setState(() => includeJob = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                title: const Text('Eğitim Bilgileri'),
                value: includeEducation,
                onChanged: (v) => setState(() => includeEducation = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                title: const Text('İş Deneyimi'),
                value: includeExperience,
                onChanged: (v) =>
                    setState(() => includeExperience = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                title: const Text('Dosyalar ve Belgeler'),
                value: includeFiles,
                onChanged: (v) => setState(() => includeFiles = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                title: const Text('Durum ve Sistem Bilgileri'),
                value: includeStatus,
                onChanged: (v) => setState(() => includeStatus = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            // İndir / Paylaş / Yazdır butonları
            PopupMenuButton<String>(
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'download',
                  child: Row(
                    children: [
                      Icon(Icons.download, color: Colors.grey),
                      SizedBox(width: 8),
                      Text('İndir (PDF)'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.share, color: Colors.grey),
                      SizedBox(width: 8),
                      Text('Paylaş'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'print',
                  child: Row(
                    children: [
                      Icon(Icons.print, color: Colors.grey),
                      SizedBox(width: 8),
                      Text('Yazdır'),
                    ],
                  ),
                ),
              ],
              onSelected: (action) async {
                Navigator.pop(context); // Dialog'u kapat

                final sections = <String>[];
                if (includePersonal) sections.add('personal');
                if (includeJob) sections.add('job');
                if (includeEducation) sections.add('education');
                if (includeExperience) sections.add('experience');
                if (includeFiles) sections.add('files');
                if (includeStatus) sections.add('status');

                if (sections.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Lütfen en az bir bölüm seçiniz.'),
                    ),
                  );
                  return;
                }

                await _handleExportAction(action, staff, sections);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.indigo,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('İşlem Seç', style: TextStyle(color: Colors.white)),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down, color: Colors.white),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleExportAction(
    String action,
    Map<String, dynamic> staff,
    List<String> sections,
  ) async {
    try {
      final pdfBytes = await _pdfService.generateStaffPdf(staff, sections);
      final fileName = 'personel_${staff['fullName'] ?? 'detay'}.pdf';

      switch (action) {
        case 'download':
          await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
          break;
        case 'share':
          await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
          break;
        case 'print':
          await Printing.layoutPdf(
            onLayout: (PdfPageFormat format) async => pdfBytes,
            name: fileName,
          );
          break;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata oluştu: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showDeleteConfirmation() {
    final staff = widget.staff;
    if (staff == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Text('Personeli Sil'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${staff['fullName']} isimli personeli silmek istediğinize emin misiniz?',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Personel pasif duruma alınacak. Sisteme giriş yapamayacak.',
                      style: TextStyle(fontSize: 13, color: Colors.orange.shade900),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.delete_forever, color: Colors.red.shade700, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Kalıcı Sil: Personel kaydı tamamen silinir, geri getirilemez!',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.red.shade900,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _softDeleteStaff();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text('Pasife Al'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _permanentDeleteStaff();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: Text('Kalıcı Sil'),
          ),
        ],
      ),
    );
  }

  Future<void> _softDeleteStaff() async {
    final staff = widget.staff;
    if (staff == null || staff['id'] == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(staff['id'])
          .update({
        'isActive': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Personel pasife alındı'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _permanentDeleteStaff() async {
    final staff = widget.staff;
    if (staff == null || staff['id'] == null) return;

    // Ekstra onay
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text('Kalıcı Silme Onayı'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_forever, size: 64, color: Colors.red),
            SizedBox(height: 16),
            Text(
              '${staff['fullName']} isimli personel kalıcı olarak silinecek. Bu personelle ilgili tüm veriler kaybolacak.',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            Text(
              'Bu işlem geri alınamaz!',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Evet, Kalıcı Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(staff['id'])
          .delete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Personel kalıcı olarak silindi'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.badge, color: Colors.indigo),
              const SizedBox(width: 8),
              const Text(
                'Personel Detayı',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (isMobile) ...[
                IconButton(
                  onPressed: _showExportDialog,
                  icon: const Icon(Icons.print, color: Colors.indigo),
                  tooltip: 'Yazdır / Dışa Aktar',
                ),
                IconButton(
                  onPressed: _showDeleteConfirmation,
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Personeli Sil',
                ),
              ] else ...[
                FilledButton.icon(
                  onPressed: _showExportDialog,
                  icon: const Icon(Icons.print),
                  label: const Text('Yazdır'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.indigo),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _showDeleteConfirmation,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Sil'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          TabBar(
            controller: _tab,
            isScrollable: true,
            labelColor: Colors.indigo,
            unselectedLabelColor: Colors.grey,
            tabs: const [
              Tab(text: 'Kişisel Bilgiler'),
              Tab(text: 'Görev Bilgileri'),
              Tab(text: 'Eğitim Bilgileri'),
              Tab(text: 'Deneyim'),
              Tab(text: 'Dosyalar'),
              Tab(text: 'Durum'),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _PersonalTab(staff: widget.staff),
                _JobTab(staff: widget.staff),
                _EducationTab(staff: widget.staff),
                _ExperienceTab(staff: widget.staff),
                _FilesTab(staff: widget.staff),
                _StatusTab(staff: widget.staff),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonalTab extends StatefulWidget {
  final Map<String, dynamic>? staff;
  const _PersonalTab({required this.staff});

  @override
  State<_PersonalTab> createState() => _PersonalTabState();
}

class _PersonalTabState extends State<_PersonalTab> {
  bool _updating = false;

  Map<String, dynamic> get _staffData => widget.staff ?? {};

  Future<void> _updateStaff(Map<String, dynamic> data) async {
    final staff = widget.staff;
    if (staff == null || staff['id'] == null) return;
    final id = staff['id'] as String;

    setState(() => _updating = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(id).update(data);

      setState(() {
        widget.staff?.addAll(data);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bilgiler güncellendi'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  Future<void> _editPersonalInfo() async {
    final staff = _staffData;

    final tcCtrl = TextEditingController(text: staff['tc']);
    final birthDateCtrl = TextEditingController(text: staff['birthDate']);
    final birthPlaceCtrl = TextEditingController(text: staff['birthPlace']);
    final nationalityCtrl = TextEditingController(text: staff['nationality']);

    // DB'den gelen degerleri kontrol et ve normalize et
    String? gender = staff['gender'];
    String? maritalStatus = staff['maritalStatus'];
    String? bloodGroup = staff['bloodGroup'];

    // Cinsiyet secenekleri
    final genderOptions = {
      'Erkek': 'Erkek',
      'Kadın': 'Kadın',
      'erkek': 'Erkek',
      'kadin': 'Kadın',
      'kadın': 'Kadın',
    };
    // Eger gelen deger listede yoksa null yap ki hata vermesin
    if (gender != null && !genderOptions.containsKey(gender)) {
      gender = null;
    } else if (gender != null) {
      // Eger varsa, bizim dropdown'da kullandigimiz value'ya cevir (standartlastir)
      // Veya direkt DB'deki degeri kullanabiliriz ama dropdown item'larinin value'su ile eslesmeli.
      // En garantisi: Dropdown item'larini DB'de olasi degerleri kapsayacak sekilde ayarlamak veya
      // secilen degeri bizim standartlarimiza maplemek.

      // Basit cozum: Gelen degeri oldugu gibi kabul eden ama gosterimde duzgun gosteren bir yapi.
      // Ancak DropdownButton value'su items listesinde OLMALI.
    }

    // Bizim standart degerlerimiz (Kaydederken bunlari kullanacagiz)
    // Ancak okurken DB'de 'kadin' varsa ve biz 'Kadın' bekliyorsak patlar.
    // O yuzden gelen degeri bizim standartimiza cevirelim.
    if (gender == 'kadin' || gender == 'kadın') gender = 'Kadın';
    if (gender == 'erkek') gender = 'Erkek';

    // Medeni durum
    if (maritalStatus == 'evli') maritalStatus = 'Evli';
    if (maritalStatus == 'bekar') maritalStatus = 'Bekar';

    // Kan grubu (A+ -> A Rh+ cevrimi gerekebilir veya direkt A+ kullanalim)
    // DB'de 'A+' var gorunuyor. Bizim listede 'A Rh+' vardi.
    // Listeyi guncelleyelim.

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Genel Bilgiler',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: tcCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 11,
                  decoration: const InputDecoration(
                    labelText: 'TC Kimlik No',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: birthDateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Doğum Tarihi',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: birthPlaceCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Doğum Yeri',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: (gender != null && ['Erkek', 'Kadın'].contains(gender))
                      ? gender
                      : null,
                  items: const [
                    DropdownMenuItem(value: 'Erkek', child: Text('Erkek')),
                    DropdownMenuItem(value: 'Kadın', child: Text('Kadın')),
                  ],
                  onChanged: (v) => setSheetState(() => gender = v),
                  decoration: const InputDecoration(
                    labelText: 'Cinsiyet',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value:
                      (maritalStatus != null &&
                          ['Evli', 'Bekar'].contains(maritalStatus))
                      ? maritalStatus
                      : null,
                  items: const [
                    DropdownMenuItem(value: 'Evli', child: Text('Evli')),
                    DropdownMenuItem(value: 'Bekar', child: Text('Bekar')),
                  ],
                  onChanged: (v) => setSheetState(() => maritalStatus = v),
                  decoration: const InputDecoration(
                    labelText: 'Medeni Durum',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: nationalityCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Uyruk',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        // Kan grubu icin hem Rh'li hem Rh'siz versiyonlari destekleyelim veya duzeltelim
                        // DB'de A+ varsa ve biz A Rh+ gosteriyorsak, value eslesmez.
                        // En iyisi kullanicinin girdigi degeri korumak adina genis bir liste sunmak veya textfield yapmak.
                        // Ama dropdown isteniyor.
                        // DB'deki degeri listede bulamazsa null gosterir, kullanici yeniden secer.
                        value:
                            (bloodGroup != null &&
                                [
                                  'A Rh+',
                                  'A Rh-',
                                  'B Rh+',
                                  'B Rh-',
                                  'AB Rh+',
                                  'AB Rh-',
                                  '0 Rh+',
                                  '0 Rh-',
                                  'A+',
                                  'A-',
                                  'B+',
                                  'B-',
                                  'AB+',
                                  'AB-',
                                  '0+',
                                  '0-',
                                ].contains(bloodGroup))
                            ? bloodGroup
                            : null,
                        items: const [
                          DropdownMenuItem(
                            value: 'A Rh+',
                            child: Text('A Rh+'),
                          ),
                          DropdownMenuItem(
                            value: 'A Rh-',
                            child: Text('A Rh-'),
                          ),
                          DropdownMenuItem(
                            value: 'B Rh+',
                            child: Text('B Rh+'),
                          ),
                          DropdownMenuItem(
                            value: 'B Rh-',
                            child: Text('B Rh-'),
                          ),
                          DropdownMenuItem(
                            value: 'AB Rh+',
                            child: Text('AB Rh+'),
                          ),
                          DropdownMenuItem(
                            value: 'AB Rh-',
                            child: Text('AB Rh-'),
                          ),
                          DropdownMenuItem(
                            value: '0 Rh+',
                            child: Text('0 Rh+'),
                          ),
                          DropdownMenuItem(
                            value: '0 Rh-',
                            child: Text('0 Rh-'),
                          ),
                          // Kisa versiyonlari da ekleyelim ki DB'de varsa secili gelsin
                          DropdownMenuItem(value: 'A+', child: Text('A+')),
                          DropdownMenuItem(value: 'A-', child: Text('A-')),
                          DropdownMenuItem(value: 'B+', child: Text('B+')),
                          DropdownMenuItem(value: 'B-', child: Text('B-')),
                          DropdownMenuItem(value: 'AB+', child: Text('AB+')),
                          DropdownMenuItem(value: 'AB-', child: Text('AB-')),
                          DropdownMenuItem(value: '0+', child: Text('0+')),
                          DropdownMenuItem(value: '0-', child: Text('0-')),
                        ],
                        onChanged: (v) => setSheetState(() => bloodGroup = v),
                        decoration: const InputDecoration(
                          labelText: 'Kan Grubu',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _updateStaff({
                        'tc': tcCtrl.text.trim(),
                        'birthDate': birthDateCtrl.text.trim(),
                        'birthPlace': birthPlaceCtrl.text.trim(),
                        'gender': gender,
                        'maritalStatus': maritalStatus,
                        'nationality': nationalityCtrl.text.trim(),
                        'bloodGroup': bloodGroup,
                      });
                    },
                    child: const Text('Kaydet'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editContactInfo() async {
    final staff = _staffData;
    final corpEmailCtrl = TextEditingController(text: staff['corporateEmail']);
    final persEmailCtrl = TextEditingController(text: staff['personalEmail']);
    final phoneCtrl = TextEditingController(text: staff['mobilePhone']);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'İletişim Bilgileri',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: corpEmailCtrl,
              decoration: const InputDecoration(
                labelText: 'Kurumsal E-posta',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: persEmailCtrl,
              decoration: const InputDecoration(
                labelText: 'Kişisel E-posta',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(
                labelText: 'Cep Telefonu',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _updateStaff({
                    'corporateEmail': corpEmailCtrl.text.trim(),
                    'personalEmail': persEmailCtrl.text.trim(),
                    'mobilePhone': phoneCtrl.text.trim(),
                  });
                },
                child: const Text('Kaydet'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editAddressInfo() async {
    final staff = _staffData;
    final cityCtrl = TextEditingController(text: staff['city']);
    final districtCtrl = TextEditingController(text: staff['district']);
    final addressCtrl = TextEditingController(text: staff['address']);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Adres Bilgileri',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: cityCtrl,
                    decoration: const InputDecoration(
                      labelText: 'İl',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: districtCtrl,
                    decoration: const InputDecoration(
                      labelText: 'İlçe',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: addressCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Açık Adres',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _updateStaff({
                    'city': cityCtrl.text.trim(),
                    'district': districtCtrl.text.trim(),
                    'address': addressCtrl.text.trim(),
                  });
                },
                child: const Text('Kaydet'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editEmergencyInfo() async {
    final staff = _staffData;
    final nameCtrl = TextEditingController(text: staff['emergencyContactName']);
    final phoneCtrl = TextEditingController(
      text: staff['emergencyContactPhone'],
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Acil Durum Bilgileri',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Ad Soyad',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(
                labelText: 'Telefon',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _updateStaff({
                    'emergencyContactName': nameCtrl.text.trim(),
                    'emergencyContactPhone': phoneCtrl.text.trim(),
                  });
                },
                child: const Text('Kaydet'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.staff;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data == null)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Sol listeden bir personel seçtiğinizde kişisel bilgileri burada görünecek.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else ...[
            _PersonalInfoCard(staff: data, onEdit: _editPersonalInfo),
            const SizedBox(height: 8),
            _ContactInfoCard(staff: data, onEdit: _editContactInfo),
            const SizedBox(height: 8),
            _AddressInfoCard(staff: data, onEdit: _editAddressInfo),
            const SizedBox(height: 8),
            _EmergencyInfoCard(staff: data, onEdit: _editEmergencyInfo),
          ],
        ],
      ),
    );
  }
}

class _PersonalInfoCard extends StatelessWidget {
  final Map<String, dynamic> staff;
  final VoidCallback onEdit;
  const _PersonalInfoCard({required this.staff, required this.onEdit});

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
      case 'DIGER':
        return 'DİĞER';
      default:
        return role.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final fullName = (staff['fullName'] ?? '') as String;
    final role = (staff['title'] ?? 'Ünvan Girilmedi') as String;
    final tc = (staff['tc'] ?? '') as String;
    final birthDate = (staff['birthDate'] ?? '') as String;
    final birthPlace = (staff['birthPlace'] ?? '') as String;
    final gender = (staff['gender'] ?? '') as String;
    final maritalStatus = (staff['maritalStatus'] ?? '') as String;
    final nationality = (staff['nationality'] ?? '') as String;
    final bloodGroup = (staff['bloodGroup'] ?? '') as String;
    final photoUrl = (staff['photoUrl'] ?? '') as String;

    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 36,
                  width: 36,
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.person_outline,
                    color: Colors.indigo,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Genel Bilgiler',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fotoğraf alanı
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey.shade100,
                    border: Border.all(color: Colors.grey.shade300),
                    image: photoUrl.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(photoUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: photoUrl.isEmpty
                      ? Icon(
                          Icons.person,
                          size: 40,
                          color: Colors.grey.shade400,
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                // Bilgi alanı
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              fullName.isEmpty
                                  ? 'Ad Soyad belirtilmemiş'
                                  : fullName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.work_outline,
                                  size: 16,
                                  color: Colors.indigo,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _formatRole(role),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.indigo,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Divider(),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isNarrow = constraints.maxWidth < 700;

                          final leftLines = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _infoLine('TC', tc),
                              _infoLine('Doğum Tarihi', birthDate),
                              _infoLine('Doğum Yeri', birthPlace),
                            ],
                          );

                          final rightLines = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _infoLine('Cinsiyet', gender),
                              _infoLine('Medeni Durum', maritalStatus),
                              _infoLine('Uyruk', nationality),
                              _infoLine('Kan Grubu', bloodGroup),
                            ],
                          );

                          if (isNarrow) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                leftLines,
                                const SizedBox(height: 4),
                                rightLines,
                              ],
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: leftLines),
                              const SizedBox(width: 40),
                              Expanded(child: rightLines),
                            ],
                          );
                        },
                      ),
                    ],
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

Widget _infoChip(String label, String value) {
  final showValue = value.isNotEmpty ? value : '-';
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        Text(showValue, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
}

Widget _infoLine(String label, String value) {
  final showValue = value.isNotEmpty ? value : '-';
  return Padding(
    padding: const EdgeInsets.only(bottom: 2.0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
        Expanded(child: Text(showValue, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );
}

class _ContactInfoCard extends StatelessWidget {
  final Map<String, dynamic> staff;
  final VoidCallback onEdit;
  const _ContactInfoCard({required this.staff, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final corporateEmail = (staff['corporateEmail'] ?? '') as String;
    final personalEmail = (staff['personalEmail'] ?? '') as String;
    final mobilePhone = (staff['mobilePhone'] ?? '') as String;

    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 36,
                  width: 36,
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.contact_phone_outlined,
                    color: Colors.indigo,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'İletişim Bilgileri',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
              ],
            ),
            const SizedBox(height: 12),
            _infoLine('E-posta (Kurumsal)', corporateEmail),
            _infoLine('E-posta (Kişisel)', personalEmail),
            _infoLine('Telefon (Cep)', mobilePhone),
          ],
        ),
      ),
    );
  }
}

class _AddressInfoCard extends StatelessWidget {
  final Map<String, dynamic> staff;
  final VoidCallback onEdit;
  const _AddressInfoCard({required this.staff, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final city = (staff['city'] ?? '') as String;
    final district = (staff['district'] ?? '') as String;
    final address = (staff['address'] ?? '') as String;

    final ilIlce = [city, district].where((e) => e.isNotEmpty).join(' / ');

    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 36,
                  width: 36,
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.location_on_outlined,
                    color: Colors.indigo,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Adres Bilgileri',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
              ],
            ),
            const SizedBox(height: 12),
            _infoLine('İl / İlçe', ilIlce),
            _infoLine('Açık Adres', address),
          ],
        ),
      ),
    );
  }
}

class _EmergencyInfoCard extends StatelessWidget {
  final Map<String, dynamic> staff;
  final VoidCallback onEdit;
  const _EmergencyInfoCard({required this.staff, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final name = (staff['emergencyContactName'] ?? '') as String;
    final phone = (staff['emergencyContactPhone'] ?? '') as String;

    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 36,
                  width: 36,
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.medical_services_outlined,
                    color: Colors.indigo,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Acil Durum Bilgileri',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
              ],
            ),
            const SizedBox(height: 12),
            _infoLine('Kişi', name),
            _infoLine('Telefon', phone),
          ],
        ),
      ),
    );
  }
}

class _JobTab extends StatefulWidget {
  final Map<String, dynamic>? staff;
  const _JobTab({required this.staff});

  @override
  State<_JobTab> createState() => _JobTabState();
}

class _JobTabState extends State<_JobTab> {
  bool _updating = false;
  bool _metaLoading = false;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _schoolTypes = [];

  Map<String, dynamic> get _staffData => widget.staff ?? {};

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    final staff = widget.staff;
    if (staff == null) return;
    final institutionId = staff['institutionId'];
    if (institutionId == null) return;

    setState(() => _metaLoading = true);
    try {
      final usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: institutionId)
          .get();

      final schoolTypesSnap = await FirebaseFirestore.instance
          .collection('schoolTypes')
          .where('institutionId', isEqualTo: institutionId)
          .get();

      setState(() {
        _users = usersSnap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
        _schoolTypes = schoolTypesSnap.docs
            .map((d) => {...d.data(), 'id': d.id})
            .toList();
        _metaLoading = false;
      });
    } catch (_) {
      setState(() => _metaLoading = false);
    }
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

  Future<void> _editJobInfo({required bool isPositionCard}) async {
    final staff = widget.staff;
    if (staff == null || staff['id'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Personel verisi bulunamadı.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final id = staff['id'] as String;

    // Text alanlari icin controller'lar
    final startDateCtrl = TextEditingController(
      text: (staff['jobStartDate'] ?? '').toString(),
    );
    final probationCtrl = TextEditingController(
      text: (staff['probationInfo'] ?? '').toString(),
    );

    // Dropdownlar icin secilen degerler
    String department = (staff['department'] ?? '').toString();
    String jobTitle = (staff['title'] ?? '').toString();
    String branch = (staff['branch'] ?? '').toString();
    String managerUserId = (staff['managerUserId'] ?? '').toString();
    List<String> workLocations = [];
    // workLocation eski versiyondan gelebilir (String) veya yeni versiyondan (List)
    if (staff['workLocations'] != null && staff['workLocations'] is List) {
      workLocations = List<String>.from(staff['workLocations']);
    } else if (staff['workLocation'] != null && staff['workLocation'].toString().isNotEmpty) {
      workLocations = [staff['workLocation'].toString()];
    }
    String employmentType = (staff['employmentType'] ?? '').toString();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: bottomInset + 16,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              Future<void> save() async {
                if (isPositionCard && startDateCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Görevin başlama tarihi zorunludur.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                setSheetState(() => _updating = true);
                try {
                  final updateData = <String, dynamic>{};

                  // Pozisyon ve Birim
                  updateData['department'] = department.trim();
                  updateData['title'] = jobTitle.trim();
                  updateData['branch'] = branch.trim();

                  if (managerUserId.isNotEmpty) {
                    final managerDoc = _users.firstWhere(
                      (u) => u['id'] == managerUserId,
                      orElse: () => {},
                    );
                    updateData['managerUserId'] = managerUserId;
                    if (managerDoc.isNotEmpty) {
                      updateData['managerName'] = (managerDoc['fullName'] ?? '')
                          .toString();
                    }
                  }

                  updateData['workLocations'] = workLocations;
                  updateData['jobStartDate'] = startDateCtrl.text.trim();

                  // İstihdam
                  updateData['probationInfo'] = probationCtrl.text.trim();
                  updateData['employmentType'] = employmentType.trim();
                  updateData['updatedAt'] = FieldValue.serverTimestamp();

                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(id)
                      .update(updateData);

                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Görev bilgileri güncellendi'),
                      backgroundColor: Colors.green,
                    ),
                  );

                  setState(() {
                    widget.staff?.addAll(updateData);
                  });

                  Navigator.pop(context);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hata: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                } finally {
                  if (mounted) {
                    setSheetState(() => _updating = false);
                  }
                }
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isPositionCard
                            ? 'Pozisyon ve Birim'
                            : 'İstihdam Bilgileri',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (isPositionCard) ...[
                    // Departman
                    DropdownButtonFormField<String>(
                      value: department.isEmpty ? null : department,
                      items: const [
                        DropdownMenuItem(
                          value: 'Öğretim Departmanı',
                          child: Text('Öğretim Departmanı'),
                        ),
                        DropdownMenuItem(
                          value: 'İdari Departman',
                          child: Text('İdari Departman'),
                        ),
                        DropdownMenuItem(
                          value: 'İnsan Kaynakları',
                          child: Text('İnsan Kaynakları'),
                        ),
                        DropdownMenuItem(
                          value: 'Muhasebe / Finans',
                          child: Text('Muhasebe / Finans'),
                        ),
                        DropdownMenuItem(
                          value: 'Destek Hizmetleri',
                          child: Text('Destek Hizmetleri'),
                        ),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Departman',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (val) {
                        setSheetState(() {
                          department = val ?? '';
                        });
                      },
                    ),
                    const SizedBox(height: 8),

                    // Ünvan
                    DropdownButtonFormField<String>(
                      value: [
                        'ogretmen', 'mudur', 'mudur_yardimcisi', 'uzman', 'personel',
                        'hr', 'muhasebe', 'satin_alma', 'depo', 'destek_hizmetleri', 'diger'
                      ].contains(jobTitle.toLowerCase()) ? jobTitle.toLowerCase() : null,
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
                        DropdownMenuItem(value: 'uzman', child: Text('Uzman')),
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
                        DropdownMenuItem(
                          value: 'diger',
                          child: Text('Diğer'),
                        ),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Ünvan',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (val) {
                        setSheetState(() {
                          jobTitle = val ?? '';
                          // Ünvan öğretmen değilse branşı temizle
                          if (val != 'ogretmen') {
                            branch = '';
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 8),

                    // Branş (sadece öğretmen seçiliyse görünür)
                    if (jobTitle.toLowerCase() == 'ogretmen') ...[
                      DropdownButtonFormField<String>(
                        value: [
                          'Almanca', 'Arapça', 'Beden Eğitimi ve Spor', 'Bilişim Teknolojileri ve Yazılım',
                          'Biyoloji', 'Coğrafya', 'Din Kültürü ve Ahlak Bilgisi', 'Felsefe',
                          'Fen Bilimleri', 'Fizik', 'Fransızca', 'Görsel Sanatlar', 'İlköğretim Matematik',
                          'İngilizce', 'İspanyolca', 'Kimya', 'Kulüp', 'Matematik', 'Müzik', 'Okul Öncesi',
                          'Özel Eğitim', 'Rehberlik ve Psikolojik Danışmanlık', 'Rusça', 'Sınıf Öğretmenliği',
                          'Sosyal Bilgiler', 'Tarih', 'Teknoloji ve Tasarım', 'Türk Dili ve Edebiyatı',
                          'Türkçe', 'Diğer'
                        ].contains(branch) ? branch : null,
                        items: const [
                          DropdownMenuItem(
                            value: 'Almanca',
                            child: Text('Almanca'),
                          ),
                          DropdownMenuItem(
                            value: 'Arapça',
                            child: Text('Arapça'),
                          ),
                          DropdownMenuItem(
                            value: 'Beden Eğitimi ve Spor',
                            child: Text('Beden Eğitimi ve Spor'),
                          ),
                          DropdownMenuItem(
                            value: 'Bilişim Teknolojileri ve Yazılım',
                            child: Text('Bilişim Teknolojileri ve Yazılım'),
                          ),
                          DropdownMenuItem(
                            value: 'Biyoloji',
                            child: Text('Biyoloji'),
                          ),
                          DropdownMenuItem(
                            value: 'Coğrafya',
                            child: Text('Coğrafya'),
                          ),
                          DropdownMenuItem(
                            value: 'Din Kültürü ve Ahlak Bilgisi',
                            child: Text('Din Kültürü ve Ahlak Bilgisi'),
                          ),
                          DropdownMenuItem(
                            value: 'Felsefe',
                            child: Text('Felsefe'),
                          ),
                          DropdownMenuItem(
                            value: 'Fen Bilimleri',
                            child: Text('Fen Bilimleri'),
                          ),
                          DropdownMenuItem(
                            value: 'Fizik',
                            child: Text('Fizik'),
                          ),
                          DropdownMenuItem(
                            value: 'Fransızca',
                            child: Text('Fransızca'),
                          ),
                          DropdownMenuItem(
                            value: 'Görsel Sanatlar',
                            child: Text('Görsel Sanatlar'),
                          ),
                          DropdownMenuItem(
                            value: 'İlköğretim Matematik',
                            child: Text('İlköğretim Matematik'),
                          ),
                          DropdownMenuItem(
                            value: 'İngilizce',
                            child: Text('İngilizce'),
                          ),
                          DropdownMenuItem(
                            value: 'İspanyolca',
                            child: Text('İspanyolca'),
                          ),
                          DropdownMenuItem(
                            value: 'Kimya',
                            child: Text('Kimya'),
                          ),
                          DropdownMenuItem(
                            value: 'Kulüp',
                            child: Text('Kulüp'),
                          ),
                          DropdownMenuItem(
                            value: 'Matematik',
                            child: Text('Matematik'),
                          ),
                          DropdownMenuItem(
                            value: 'Müzik',
                            child: Text('Müzik'),
                          ),
                          DropdownMenuItem(
                            value: 'Okul Öncesi',
                            child: Text('Okul Öncesi'),
                          ),
                          DropdownMenuItem(
                            value: 'Özel Eğitim',
                            child: Text('Özel Eğitim'),
                          ),
                          DropdownMenuItem(
                            value: 'Rehberlik ve Psikolojik Danışmanlık',
                            child: Text('Rehberlik ve Psikolojik Danışmanlık'),
                          ),
                          DropdownMenuItem(
                            value: 'Rusça',
                            child: Text('Rusça'),
                          ),
                          DropdownMenuItem(
                            value: 'Sınıf Öğretmenliği',
                            child: Text('Sınıf Öğretmenliği'),
                          ),
                          DropdownMenuItem(
                            value: 'Sosyal Bilgiler',
                            child: Text('Sosyal Bilgiler'),
                          ),
                          DropdownMenuItem(
                            value: 'Tarih',
                            child: Text('Tarih'),
                          ),
                          DropdownMenuItem(
                            value: 'Teknoloji ve Tasarım',
                            child: Text('Teknoloji ve Tasarım'),
                          ),
                          DropdownMenuItem(
                            value: 'Türk Dili ve Edebiyatı',
                            child: Text('Türk Dili ve Edebiyatı'),
                          ),
                          DropdownMenuItem(
                            value: 'Türkçe',
                            child: Text('Türkçe'),
                          ),
                          DropdownMenuItem(
                            value: 'Diğer',
                            child: Text('Diğer'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Branş',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (val) {
                          setSheetState(() {
                            branch = val ?? '';
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Yönetici / Bağlı Olduğu Kişi
                    DropdownButtonFormField<String>(
                      value: managerUserId.isEmpty ? null : managerUserId,
                      items: _users
                          .where((u) {
                            final authUserId = (u['authUserId'] ?? '')
                                .toString()
                                .trim();
                            final uid = (u['id'] ?? '').toString();
                            return authUserId.isNotEmpty && uid != id;
                          })
                          .map(
                            (u) => DropdownMenuItem<String>(
                              value: (u['id'] ?? '').toString(),
                              child: Text(
                                (u['fullName'] ?? u['username'] ?? '-')
                                    .toString(),
                              ),
                            ),
                          )
                          .toList(),
                      decoration: const InputDecoration(
                        labelText: 'Yönetici / Bağlı Olduğu Kişi',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (val) {
                        setSheetState(() {
                          managerUserId = val ?? '';
                        });
                      },
                    ),
                    const SizedBox(height: 8),

                    // Çalışma yeri - Çoklu seçim
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Çalışma Yeri (Şube / Lokasyon) - Birden fazla seçebilirsiniz',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            // Okul türleri
                            ..._schoolTypes.map((st) {
                              final locationName = (st['schoolTypeName'] ?? st['typeName'] ?? '').toString();
                              final isSelected = workLocations.contains(locationName);
                              return FilterChip(
                                label: Text(locationName),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setSheetState(() {
                                    if (selected) {
                                      workLocations.add(locationName);
                                    } else {
                                      workLocations.remove(locationName);
                                    }
                                  });
                                },
                                selectedColor: Colors.indigo.withOpacity(0.3),
                                checkmarkColor: Colors.indigo,
                              );
                            }),
                            // Sabit ekstra lokasyonlar
                            ...[
                              {'value': 'ARGE', 'label': 'ARGE'},
                              {'value': 'INSAN_KAYNAKLARI', 'label': 'İnsan Kaynakları'},
                              {'value': 'DANISMA', 'label': 'Danışma'},
                              {'value': 'GUVENLIK', 'label': 'Güvenlik'},
                              {'value': 'TEMIZLIK', 'label': 'Temizlik'},
                              {'value': 'YEMEKHANE', 'label': 'Yemekhane'},
                              {'value': 'REVIR', 'label': 'Revir'},
                            ].map((loc) {
                              final isSelected = workLocations.contains(loc['value']);
                              return FilterChip(
                                label: Text(loc['label']!),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setSheetState(() {
                                    if (selected) {
                                      workLocations.add(loc['value']!);
                                    } else {
                                      workLocations.remove(loc['value']!);
                                    }
                                  });
                                },
                                selectedColor: Colors.indigo.withOpacity(0.3),
                                checkmarkColor: Colors.indigo,
                              );
                            }),
                          ],
                        ),
                        if (workLocations.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.indigo.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Seçili: ${workLocations.join(", ")}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: startDateCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 10,
                      decoration: InputDecoration(
                        labelText: 'Görevin Başlama Tarihi (gg.aa.yyyy)',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        counterText: '',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.today),
                          onPressed: () {
                            final now = DateTime.now();
                            final formattedDate =
                                '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
                            startDateCtrl.text = formattedDate;
                          },
                        ),
                      ),
                      onChanged: (value) {
                        final formatted = _formatDateInput(value);
                        if (formatted != value) {
                          startDateCtrl.value = TextEditingValue(
                            text: formatted,
                            selection: TextSelection.collapsed(
                              offset: formatted.length,
                            ),
                          );
                        }
                      },
                    ),
                  ] else ...[
                    TextField(
                      controller: probationCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Deneme Süresi Bilgisi',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: employmentType.isEmpty ? null : employmentType,
                      items: const [
                        DropdownMenuItem(
                          value: 'tam_zamanli',
                          child: Text('Tam Zamanlı'),
                        ),
                        DropdownMenuItem(
                          value: 'yari_zamanli',
                          child: Text('Yarı Zamanlı'),
                        ),
                        DropdownMenuItem(
                          value: 'donemsel',
                          child: Text('Dönemsel / Proje Bazlı'),
                        ),
                        DropdownMenuItem(
                          value: 'stajyer',
                          child: Text('Stajyer'),
                        ),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'İstihdam Şekli',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (val) {
                        setSheetState(() {
                          employmentType = val ?? '';
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _updating ? null : save,
                      icon: _updating
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
                      label: Text(_updating ? 'Kaydediliyor...' : 'Kaydet'),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildJobCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.indigo, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...children,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _jobInfoLine(String label, String value) {
    final showValue = (value).isNotEmpty ? value : '-';
    return Padding(
      padding: const EdgeInsets.only(bottom: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          Expanded(
            child: Text(showValue, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  String _formatTitle(String? title) {
    if (title == null || title.isEmpty || title == '-') return '-';
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

  String _formatEmploymentType(String value) {
    switch (value) {
      case 'tam_zamanli':
        return 'Tam Zamanlı';
      case 'yari_zamanli':
        return 'Yarı Zamanlı';
      case 'donemsel':
        return 'Dönemsel / Proje Bazlı';
      case 'stajyer':
        return 'Stajyer';
      default:
        return value.isEmpty ? '-' : value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final staff = _staffData;

    final department = (staff['department'] ?? '-') as String;
    final title = (staff['title'] ?? '-') as String;
    final branch = (staff['branch'] ?? '-') as String;
    final managerName = (staff['managerName'] ?? '-') as String;
    
    // Çalışma yeri - eski ve yeni format desteği
    String workLocationDisplay = '-';
    if (staff['workLocations'] != null && staff['workLocations'] is List) {
      final locations = List<String>.from(staff['workLocations']);
      workLocationDisplay = locations.isNotEmpty ? locations.join(', ') : '-';
    } else if (staff['workLocation'] != null && staff['workLocation'].toString().isNotEmpty) {
      workLocationDisplay = staff['workLocation'].toString();
    }
    
    final jobStartDate = (staff['jobStartDate'] ?? '-') as String;
    final probationInfo = (staff['probationInfo'] ?? '-') as String;
    final employmentType = (staff['employmentType'] ?? '-') as String;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildJobCard(
            icon: Icons.business_center_outlined,
            title: 'Pozisyon ve Birim',
            onTap: () => _editJobInfo(isPositionCard: true),
            children: [
              _jobInfoLine('Departman', department),
              _jobInfoLine('Ünvan', _formatTitle(title)),
              if (title.toLowerCase() == 'ogretmen' && branch != '-')
                _jobInfoLine('Branş', branch),
              _jobInfoLine('Yönetici / Bağlı Olduğu Kişi', managerName),
              _jobInfoLine('Çalışma Yeri', workLocationDisplay),
              _jobInfoLine('Görevin Başlama Tarihi', jobStartDate),
            ],
          ),
          _buildJobCard(
            icon: Icons.schedule,
            title: 'İstihdam Bilgileri',
            onTap: () => _editJobInfo(isPositionCard: false),
            children: [
              _jobInfoLine('Deneme Süresi Bilgisi', probationInfo),
              _jobInfoLine(
                'İstihdam Şekli',
                _formatEmploymentType(employmentType),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EducationTab extends StatefulWidget {
  final Map<String, dynamic>? staff;
  const _EducationTab({required this.staff});

  @override
  State<_EducationTab> createState() => _EducationTabState();
}

class _EducationTabState extends State<_EducationTab> {
  Map<String, dynamic> get _staffData => widget.staff ?? {};

  List<dynamic> get _formalEducations =>
      List<dynamic>.from(_staffData['formalEducations'] ?? []);
  List<dynamic> get _certificates =>
      List<dynamic>.from(_staffData['certificates'] ?? []);
  List<dynamic> get _languages =>
      List<dynamic>.from(_staffData['languages'] ?? []);

  Future<void> _addFormalEducation() async {
    final staff = widget.staff;
    if (staff == null || staff['id'] == null) return;
    final id = staff['id'] as String;

    final schoolCtrl = TextEditingController();
    final programCtrl = TextEditingController();
    final startCtrl = TextEditingController();
    final endCtrl = TextEditingController();
    String degree = '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final bottom = MediaQuery.of(context).viewInsets.bottom;
        bool saving = false;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
          child: StatefulBuilder(
            builder: (context, setSheet) {
              Future<void> save() async {
                if (schoolCtrl.text.trim().isEmpty ||
                    programCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Okul ve bölüm alanları zorunludur.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                setSheet(() => saving = true);
                try {
                  final current = List<dynamic>.from(
                    widget.staff?['formalEducations'] ?? [],
                  );
                  current.add({
                    'school': schoolCtrl.text.trim(),
                    'program': programCtrl.text.trim(),
                    'degree': degree.trim(),
                    'start': startCtrl.text.trim(),
                    'end': endCtrl.text.trim(),
                  });
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(id)
                      .update({'formalEducations': current});

                  if (!mounted) return;
                  setState(() => widget.staff?['formalEducations'] = current);
                  Navigator.pop(context);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hata: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  setSheet(() => saving = false);
                }
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Yeni Formal Eğitim',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: schoolCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Okul / Üniversite Adı',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: programCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Bölüm / Program',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: degree.isEmpty ? null : degree,
                    items: const [
                      DropdownMenuItem(value: 'LISE', child: Text('Lise')),
                      DropdownMenuItem(
                        value: 'ONLISANS',
                        child: Text('Ön Lisans'),
                      ),
                      DropdownMenuItem(value: 'LISANS', child: Text('Lisans')),
                      DropdownMenuItem(
                        value: 'YUKSEK_LISANS',
                        child: Text('Yüksek Lisans'),
                      ),
                      DropdownMenuItem(
                        value: 'DOKTORA',
                        child: Text('Doktora'),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Derece',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setSheet(() => degree = v ?? ''),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 10,
                          decoration: const InputDecoration(
                            labelText: 'Başlangıç Tarihi (gg.aa.yyyy)',
                            border: OutlineInputBorder(),
                            isDense: true,
                            counterText: '',
                          ),
                          onChanged: (value) {
                            final formatted = _formatEduDate(value);
                            if (formatted != value) {
                              startCtrl.value = TextEditingValue(
                                text: formatted,
                                selection: TextSelection.collapsed(
                                  offset: formatted.length,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: endCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 10,
                          decoration: const InputDecoration(
                            labelText: 'Bitiş Tarihi (gg.aa.yyyy)',
                            border: OutlineInputBorder(),
                            isDense: true,
                            counterText: '',
                          ),
                          onChanged: (value) {
                            final formatted = _formatEduDate(value);
                            if (formatted != value) {
                              endCtrl.value = TextEditingValue(
                                text: formatted,
                                selection: TextSelection.collapsed(
                                  offset: formatted.length,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: saving ? null : save,
                      icon: saving
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
                      label: Text(saving ? 'Kaydediliyor...' : 'Kaydet'),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _addCertificate() async {
    final staff = widget.staff;
    if (staff == null || staff['id'] == null) return;
    final id = staff['id'] as String;

    final nameCtrl = TextEditingController();
    final providerCtrl = TextEditingController();
    final dateCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final bottom = MediaQuery.of(context).viewInsets.bottom;
        bool saving = false;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
          child: StatefulBuilder(
            builder: (context, setSheet) {
              Future<void> save() async {
                if (nameCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Sertifika / Kurs adı zorunlu.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                setSheet(() => saving = true);
                try {
                  final current = List<dynamic>.from(
                    widget.staff?['certificates'] ?? [],
                  );
                  current.add({
                    'name': nameCtrl.text.trim(),
                    'provider': providerCtrl.text.trim(),
                    'date': dateCtrl.text.trim(),
                  });
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(id)
                      .update({'certificates': current});

                  if (!mounted) return;
                  setState(() => widget.staff?['certificates'] = current);
                  Navigator.pop(context);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hata: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  setSheet(() => saving = false);
                }
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Yeni Sertifika / Kurs',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Sertifika / Kurs Adı',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: providerCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Kurum / Veren Kuruluş',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: dateCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 10,
                    decoration: const InputDecoration(
                      labelText: 'Sertifika Tarihi (gg.aa.yyyy)',
                      border: OutlineInputBorder(),
                      isDense: true,
                      counterText: '',
                    ),
                    onChanged: (value) {
                      final formatted = _formatEduDate(value);
                      if (formatted != value) {
                        dateCtrl.value = TextEditingValue(
                          text: formatted,
                          selection: TextSelection.collapsed(
                            offset: formatted.length,
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: saving ? null : save,
                      icon: saving
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
                      label: Text(saving ? 'Kaydediliyor...' : 'Kaydet'),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _addLanguage() async {
    final staff = widget.staff;
    if (staff == null || staff['id'] == null) return;
    final id = staff['id'] as String;

    final langCtrl = TextEditingController();
    String readLevel = '';
    String writeLevel = '';
    String speakLevel = '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final bottom = MediaQuery.of(context).viewInsets.bottom;
        bool saving = false;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
          child: StatefulBuilder(
            builder: (context, setSheet) {
              Future<void> save() async {
                if (langCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Dil adı zorunlu.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                setSheet(() => saving = true);
                try {
                  final current = List<dynamic>.from(
                    widget.staff?['languages'] ?? [],
                  );
                  current.add({
                    'language': langCtrl.text.trim(),
                    'read': readLevel.trim(),
                    'write': writeLevel.trim(),
                    'speak': speakLevel.trim(),
                  });
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(id)
                      .update({'languages': current});

                  if (!mounted) return;
                  setState(() => widget.staff?['languages'] = current);
                  Navigator.pop(context);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hata: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  setSheet(() => saving = false);
                }
              }

              DropdownButtonFormField<String> buildLevelDropdown(
                String label,
                String currentValue,
                void Function(String) onChanged,
              ) {
                return DropdownButtonFormField<String>(
                  value: currentValue.isEmpty ? null : currentValue,
                  items: const [
                    DropdownMenuItem(value: 'ZAYIF', child: Text('Zayıf')),
                    DropdownMenuItem(value: 'ORTA', child: Text('Orta')),
                    DropdownMenuItem(value: 'IYI', child: Text('İyi')),
                    DropdownMenuItem(value: 'COK_IYI', child: Text('Çok İyi')),
                    DropdownMenuItem(value: 'ANA_DIL', child: Text('Ana Dil')),
                  ],
                  decoration: InputDecoration(
                    labelText: label,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setSheet(() => onChanged(v ?? '')),
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Yeni Yabancı Dil',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: langCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Dil Adı',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  buildLevelDropdown(
                    'Okuma Seviyesi',
                    readLevel,
                    (v) => readLevel = v,
                  ),
                  const SizedBox(height: 8),
                  buildLevelDropdown(
                    'Yazma Seviyesi',
                    writeLevel,
                    (v) => writeLevel = v,
                  ),
                  const SizedBox(height: 8),
                  buildLevelDropdown(
                    'Konuşma Seviyesi',
                    speakLevel,
                    (v) => speakLevel = v,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: saving ? null : save,
                      icon: saving
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
                      label: Text(saving ? 'Kaydediliyor...' : 'Kaydet'),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _editFormalEducation(
    int index,
    Map<String, dynamic> item,
  ) async {
    final staff = widget.staff;
    if (staff == null || staff['id'] == null) return;
    final id = staff['id'] as String;

    final schoolCtrl = TextEditingController(
      text: (item['school'] ?? '').toString(),
    );
    final programCtrl = TextEditingController(
      text: (item['program'] ?? '').toString(),
    );
    final startCtrl = TextEditingController(
      text: (item['start'] ?? '').toString(),
    );
    final endCtrl = TextEditingController(text: (item['end'] ?? '').toString());
    String degree = (item['degree'] ?? '').toString();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final bottom = MediaQuery.of(context).viewInsets.bottom;
        bool saving = false;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
          child: StatefulBuilder(
            builder: (context, setSheet) {
              Future<void> save() async {
                if (schoolCtrl.text.trim().isEmpty ||
                    programCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Okul ve bölüm alanları zorunludur.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                setSheet(() => saving = true);
                try {
                  final current = List<dynamic>.from(
                    widget.staff?['formalEducations'] ?? [],
                  );
                  current[index] = {
                    'school': schoolCtrl.text.trim(),
                    'program': programCtrl.text.trim(),
                    'degree': degree.trim(),
                    'start': startCtrl.text.trim(),
                    'end': endCtrl.text.trim(),
                  };
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(id)
                      .update({'formalEducations': current});

                  if (!mounted) return;
                  setState(() => widget.staff?['formalEducations'] = current);
                  Navigator.pop(context);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hata: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  setSheet(() => saving = false);
                }
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Formal Eğitimi Düzenle',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: schoolCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Okul / Üniversite Adı',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: programCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Bölüm / Program',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: degree.isEmpty ? null : degree,
                    items: const [
                      DropdownMenuItem(value: 'LISE', child: Text('Lise')),
                      DropdownMenuItem(
                        value: 'ONLISANS',
                        child: Text('Ön Lisans'),
                      ),
                      DropdownMenuItem(value: 'LISANS', child: Text('Lisans')),
                      DropdownMenuItem(
                        value: 'YUKSEK_LISANS',
                        child: Text('Yüksek Lisans'),
                      ),
                      DropdownMenuItem(
                        value: 'DOKTORA',
                        child: Text('Doktora'),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Derece',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setSheet(() => degree = v ?? ''),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 10,
                          decoration: const InputDecoration(
                            labelText: 'Başlangıç Tarihi (gg.aa.yyyy)',
                            border: OutlineInputBorder(),
                            isDense: true,
                            counterText: '',
                          ),
                          onChanged: (value) {
                            final formatted = _formatEduDate(value);
                            if (formatted != value) {
                              startCtrl.value = TextEditingValue(
                                text: formatted,
                                selection: TextSelection.collapsed(
                                  offset: formatted.length,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: endCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 10,
                          decoration: const InputDecoration(
                            labelText: 'Bitiş Tarihi (gg.aa.yyyy)',
                            border: OutlineInputBorder(),
                            isDense: true,
                            counterText: '',
                          ),
                          onChanged: (value) {
                            final formatted = _formatEduDate(value);
                            if (formatted != value) {
                              endCtrl.value = TextEditingValue(
                                text: formatted,
                                selection: TextSelection.collapsed(
                                  offset: formatted.length,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: saving ? null : save,
                      icon: saving
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
                      label: Text(saving ? 'Kaydediliyor...' : 'Kaydet'),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _editCertificate(int index, Map<String, dynamic> item) async {
    final staff = widget.staff;
    if (staff == null || staff['id'] == null) return;
    final id = staff['id'] as String;

    final nameCtrl = TextEditingController(
      text: (item['name'] ?? '').toString(),
    );
    final providerCtrl = TextEditingController(
      text: (item['provider'] ?? '').toString(),
    );
    final dateCtrl = TextEditingController(
      text: (item['date'] ?? '').toString(),
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final bottom = MediaQuery.of(context).viewInsets.bottom;
        bool saving = false;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
          child: StatefulBuilder(
            builder: (context, setSheet) {
              Future<void> save() async {
                if (nameCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Sertifika / Kurs adı zorunlu.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                setSheet(() => saving = true);
                try {
                  final current = List<dynamic>.from(
                    widget.staff?['certificates'] ?? [],
                  );
                  current[index] = {
                    'name': nameCtrl.text.trim(),
                    'provider': providerCtrl.text.trim(),
                    'date': dateCtrl.text.trim(),
                  };
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(id)
                      .update({'certificates': current});

                  if (!mounted) return;
                  setState(() => widget.staff?['certificates'] = current);
                  Navigator.pop(context);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hata: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  setSheet(() => saving = false);
                }
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Sertifika / Kursu Düzenle',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Sertifika / Kurs Adı',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: providerCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Kurum / Veren Kuruluş',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: dateCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 10,
                    decoration: const InputDecoration(
                      labelText: 'Sertifika Tarihi (gg.aa.yyyy)',
                      border: OutlineInputBorder(),
                      isDense: true,
                      counterText: '',
                    ),
                    onChanged: (value) {
                      final formatted = _formatEduDate(value);
                      if (formatted != value) {
                        dateCtrl.value = TextEditingValue(
                          text: formatted,
                          selection: TextSelection.collapsed(
                            offset: formatted.length,
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: saving ? null : save,
                      icon: saving
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
                      label: Text(saving ? 'Kaydediliyor...' : 'Kaydet'),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _editLanguage(int index, Map<String, dynamic> item) async {
    final staff = widget.staff;
    if (staff == null || staff['id'] == null) return;
    final id = staff['id'] as String;

    final langCtrl = TextEditingController(
      text: (item['language'] ?? '').toString(),
    );
    String readLevel = (item['read'] ?? '').toString();
    String writeLevel = (item['write'] ?? '').toString();
    String speakLevel = (item['speak'] ?? '').toString();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final bottom = MediaQuery.of(context).viewInsets.bottom;
        bool saving = false;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
          child: StatefulBuilder(
            builder: (context, setSheet) {
              Future<void> save() async {
                if (langCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Dil adı zorunlu.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                setSheet(() => saving = true);
                try {
                  final current = List<dynamic>.from(
                    widget.staff?['languages'] ?? [],
                  );
                  current[index] = {
                    'language': langCtrl.text.trim(),
                    'read': readLevel.trim(),
                    'write': writeLevel.trim(),
                    'speak': speakLevel.trim(),
                  };
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(id)
                      .update({'languages': current});

                  if (!mounted) return;
                  setState(() => widget.staff?['languages'] = current);
                  Navigator.pop(context);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hata: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  setSheet(() => saving = false);
                }
              }

              DropdownButtonFormField<String> buildLevelDropdown(
                String label,
                String currentValue,
                void Function(String) onChanged,
              ) {
                return DropdownButtonFormField<String>(
                  value: currentValue.isEmpty ? null : currentValue,
                  items: const [
                    DropdownMenuItem(value: 'ZAYIF', child: Text('Zayıf')),
                    DropdownMenuItem(value: 'ORTA', child: Text('Orta')),
                    DropdownMenuItem(value: 'IYI', child: Text('İyi')),
                    DropdownMenuItem(value: 'COK_IYI', child: Text('Çok İyi')),
                    DropdownMenuItem(value: 'ANA_DIL', child: Text('Ana Dil')),
                  ],
                  decoration: InputDecoration(
                    labelText: label,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setSheet(() => onChanged(v ?? '')),
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Yabancı Dili Düzenle',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: langCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Dil Adı',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  buildLevelDropdown(
                    'Okuma Seviyesi',
                    readLevel,
                    (v) => readLevel = v,
                  ),
                  const SizedBox(height: 8),
                  buildLevelDropdown(
                    'Yazma Seviyesi',
                    writeLevel,
                    (v) => writeLevel = v,
                  ),
                  const SizedBox(height: 8),
                  buildLevelDropdown(
                    'Konuşma Seviyesi',
                    speakLevel,
                    (v) => speakLevel = v,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: saving ? null : save,
                      icon: saving
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
                      label: Text(saving ? 'Kaydediliyor...' : 'Kaydet'),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEduCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
    required VoidCallback onAdd,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 36,
                width: 36,
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.indigo, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.add_circle_outline,
                  size: 20,
                  color: Colors.indigo,
                ),
                onPressed: onAdd,
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (children.isEmpty)
            const Text(
              'Henüz kayıt yok. Yeni kayıt eklemek için + butonuna tıklayın.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            )
          else
            ...children,
        ],
      ),
    );
  }

  Widget _eduLine(String label, String value) {
    final showValue = value.isNotEmpty ? value : '-';
    return Padding(
      padding: const EdgeInsets.only(bottom: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          Expanded(
            child: Text(showValue, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  String _formatEduDate(String input) {
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
    final formal = _formalEducations;
    final certs = _certificates;
    final langs = _languages;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildEduCard(
            icon: Icons.school_outlined,
            title: 'Formal Eğitim',
            onAdd: _addFormalEducation,
            children: formal.asMap().entries.map((entry) {
              final index = entry.key;
              final e = entry.value as Map<String, dynamic>;
              return InkWell(
                onTap: () => _editFormalEducation(index, e),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (e['school'] ?? '-').toString(),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      _eduLine('Program', (e['program'] ?? '-').toString()),
                      _eduLine('Derece', (e['degree'] ?? '-').toString()),
                      _eduLine(
                        'Tarih',
                        '${(e['start'] ?? '').toString()} - ${(e['end'] ?? '').toString()}',
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          _buildEduCard(
            icon: Icons.workspace_premium_outlined,
            title: 'Sertifika ve Kurslar',
            onAdd: _addCertificate,
            children: certs.asMap().entries.map((entry) {
              final index = entry.key;
              final e = entry.value as Map<String, dynamic>;
              return InkWell(
                onTap: () => _editCertificate(index, e),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (e['name'] ?? '-').toString(),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      _eduLine('Kurum', (e['provider'] ?? '-').toString()),
                      _eduLine('Tarih', (e['date'] ?? '-').toString()),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          _buildEduCard(
            icon: Icons.language_outlined,
            title: 'Yabancı Dil Bilgisi',
            onAdd: _addLanguage,
            children: langs.asMap().entries.map((entry) {
              final index = entry.key;
              final e = entry.value as Map<String, dynamic>;
              return InkWell(
                onTap: () => _editLanguage(index, e),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (e['language'] ?? '-').toString(),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      _eduLine('Okuma', (e['read'] ?? '-').toString()),
                      _eduLine('Yazma', (e['write'] ?? '-').toString()),
                      _eduLine('Konuşma', (e['speak'] ?? '-').toString()),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ExperienceTab extends StatefulWidget {
  final Map<String, dynamic>? staff;
  const _ExperienceTab({required this.staff});

  @override
  State<_ExperienceTab> createState() => _ExperienceTabState();
}

class _ExperienceTabState extends State<_ExperienceTab> {
  Map<String, dynamic> get _staffData => widget.staff ?? {};

  List<dynamic> get _experiences =>
      List<dynamic>.from(_staffData['experiences'] ?? []);

  String _formatExpDate(String input) {
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

  Future<void> _addExperience() async {
    final staff = widget.staff;
    if (staff == null || staff['id'] == null) return;
    final id = staff['id'] as String;

    final companyCtrl = TextEditingController();
    final positionCtrl = TextEditingController();
    final startCtrl = TextEditingController();
    final endCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final bottom = MediaQuery.of(context).viewInsets.bottom;
        bool saving = false;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
          child: StatefulBuilder(
            builder: (context, setSheet) {
              Future<void> save() async {
                if (companyCtrl.text.trim().isEmpty ||
                    positionCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Şirket ve pozisyon alanları zorunludur.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                setSheet(() => saving = true);
                try {
                  final current = List<dynamic>.from(
                    widget.staff?['experiences'] ?? [],
                  );
                  current.add({
                    'company': companyCtrl.text.trim(),
                    'position': positionCtrl.text.trim(),
                    'start': startCtrl.text.trim(),
                    'end': endCtrl.text.trim(),
                    'reason': reasonCtrl.text.trim(),
                    'description': descCtrl.text.trim(),
                  });
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(id)
                      .update({'experiences': current});

                  if (!mounted) return;
                  setState(() => widget.staff?['experiences'] = current);
                  Navigator.pop(context);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hata: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  setSheet(() => saving = false);
                }
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Yeni İş Deneyimi',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: companyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Şirket Adı',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: positionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Pozisyon / Ünvan',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 10,
                          decoration: const InputDecoration(
                            labelText: 'Başlangıç Tarihi (gg.aa.yyyy)',
                            border: OutlineInputBorder(),
                            isDense: true,
                            counterText: '',
                          ),
                          onChanged: (value) {
                            final formatted = _formatExpDate(value);
                            if (formatted != value) {
                              startCtrl.value = TextEditingValue(
                                text: formatted,
                                selection: TextSelection.collapsed(
                                  offset: formatted.length,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: endCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 10,
                          decoration: const InputDecoration(
                            labelText: 'Bitiş Tarihi (gg.aa.yyyy)',
                            border: OutlineInputBorder(),
                            isDense: true,
                            counterText: '',
                          ),
                          onChanged: (value) {
                            final formatted = _formatExpDate(value);
                            if (formatted != value) {
                              endCtrl.value = TextEditingValue(
                                text: formatted,
                                selection: TextSelection.collapsed(
                                  offset: formatted.length,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ayrılma Nedeni',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Kısa Görev Tanımı (Opsiyonel)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: saving ? null : save,
                      icon: saving
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
                      label: Text(saving ? 'Kaydediliyor...' : 'Kaydet'),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _editExperience(int index, Map<String, dynamic> item) async {
    final staff = widget.staff;
    if (staff == null || staff['id'] == null) return;
    final id = staff['id'] as String;

    final companyCtrl = TextEditingController(
      text: (item['company'] ?? '').toString(),
    );
    final positionCtrl = TextEditingController(
      text: (item['position'] ?? '').toString(),
    );
    final startCtrl = TextEditingController(
      text: (item['start'] ?? '').toString(),
    );
    final endCtrl = TextEditingController(text: (item['end'] ?? '').toString());
    final reasonCtrl = TextEditingController(
      text: (item['reason'] ?? '').toString(),
    );
    final descCtrl = TextEditingController(
      text: (item['description'] ?? '').toString(),
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final bottom = MediaQuery.of(context).viewInsets.bottom;
        bool saving = false;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
          child: StatefulBuilder(
            builder: (context, setSheet) {
              Future<void> save() async {
                if (companyCtrl.text.trim().isEmpty ||
                    positionCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Şirket ve pozisyon alanları zorunludur.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                setSheet(() => saving = true);
                try {
                  final current = List<dynamic>.from(
                    widget.staff?['experiences'] ?? [],
                  );
                  current[index] = {
                    'company': companyCtrl.text.trim(),
                    'position': positionCtrl.text.trim(),
                    'start': startCtrl.text.trim(),
                    'end': endCtrl.text.trim(),
                    'reason': reasonCtrl.text.trim(),
                    'description': descCtrl.text.trim(),
                  };
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(id)
                      .update({'experiences': current});

                  if (!mounted) return;
                  setState(() => widget.staff?['experiences'] = current);
                  Navigator.pop(context);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hata: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  setSheet(() => saving = false);
                }
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'İş Deneyimini Düzenle',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: companyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Şirket Adı',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: positionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Pozisyon / Ünvan',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 10,
                          decoration: const InputDecoration(
                            labelText: 'Başlangıç Tarihi (gg.aa.yyyy)',
                            border: OutlineInputBorder(),
                            isDense: true,
                            counterText: '',
                          ),
                          onChanged: (value) {
                            final formatted = _formatExpDate(value);
                            if (formatted != value) {
                              startCtrl.value = TextEditingValue(
                                text: formatted,
                                selection: TextSelection.collapsed(
                                  offset: formatted.length,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: endCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 10,
                          decoration: const InputDecoration(
                            labelText: 'Bitiş Tarihi (gg.aa.yyyy)',
                            border: OutlineInputBorder(),
                            isDense: true,
                            counterText: '',
                          ),
                          onChanged: (value) {
                            final formatted = _formatExpDate(value);
                            if (formatted != value) {
                              endCtrl.value = TextEditingValue(
                                text: formatted,
                                selection: TextSelection.collapsed(
                                  offset: formatted.length,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ayrılma Nedeni',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Kısa Görev Tanımı (Opsiyonel)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: saving ? null : save,
                      icon: saving
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
                      label: Text(saving ? 'Kaydediliyor...' : 'Kaydet'),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _expLine(String label, String value) {
    final showValue = value.isNotEmpty ? value : '-';
    return Padding(
      padding: const EdgeInsets.only(bottom: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          Expanded(
            child: Text(showValue, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final experiences = _experiences;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: _buildExperienceCard(experiences),
    );
  }

  Widget _buildExperienceCard(List<dynamic> items) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 36,
                width: 36,
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.work_outline,
                  color: Colors.indigo,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Önceki İş Tecrübeleri',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.add_circle_outline,
                  size: 20,
                  color: Colors.indigo,
                ),
                onPressed: _addExperience,
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (items.isEmpty)
            const Text(
              'Henüz kayıt yok. Yeni iş deneyimi eklemek için + butonuna tıklayın.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            )
          else
            ...items.asMap().entries.map((entry) {
              final index = entry.key;
              final e = entry.value as Map<String, dynamic>;
              final company = (e['company'] ?? '-').toString();
              final position = (e['position'] ?? '-').toString();
              final start = (e['start'] ?? '').toString();
              final end = (e['end'] ?? '').toString();
              final reason = (e['reason'] ?? '').toString();
              final desc = (e['description'] ?? '').toString();

              return InkWell(
                onTap: () => _editExperience(index, e),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        company,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      _expLine('Pozisyon', position),
                      _expLine('Tarih', '$start - $end'),
                      _expLine('Ayrılma Nedeni', reason),
                      if (desc.isNotEmpty) _expLine('Görev Tanımı', desc),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _FilesTab extends StatefulWidget {
  final Map<String, dynamic>? staff;
  const _FilesTab({required this.staff});

  @override
  State<_FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<_FilesTab> {
  late Map<String, dynamic> _localStaffData;

  @override
  void initState() {
    super.initState();
    _localStaffData = Map<String, dynamic>.from(widget.staff ?? {});
  }

  Map<String, dynamic> get _officialDocs =>
      Map<String, dynamic>.from(_localStaffData['officialDocs'] ?? {});
  Map<String, dynamic> get _contractDocs =>
      Map<String, dynamic>.from(_localStaffData['contractDocs'] ?? {});

  final Map<String, bool> _uploadingStates = {};

  Future<void> _uploadFile(String category, String key) async {
    try {
      print('Dosya seçimi başlatılıyor...');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result == null || result.files.isEmpty) {
        print('Dosya seçilmedi.');
        return;
      }

      setState(() => _uploadingStates[key] = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Yükleme başlıyor...')));

      final file = result.files.first;
      print('Dosya seçildi: ${file.name}, Boyut: ${file.size}');

      if (kIsWeb && file.bytes == null) {
        throw Exception('Dosya verisi okunamadı (Bytes null).');
      }

      final staffId = widget.staff?['id'];
      if (staffId == null) throw Exception('Personel ID bulunamadı');

      final ref = FirebaseStorage.instance
          .ref()
          .child('staff_docs')
          .child(staffId)
          .child(category)
          .child('$key.pdf');

      print('Firebase Storage yüklemesi başlıyor...');
      if (kIsWeb) {
        await ref
            .putData(
              file.bytes!,
              SettableMetadata(contentType: 'application/pdf'),
            )
            .timeout(
              const Duration(seconds: 15),
              onTimeout: () {
                throw Exception(
                  'Yükleme zaman aşımına uğradı (15 sn). İnternet bağlantınızı veya CORS ayarlarını kontrol edin.',
                );
              },
            );
      } else {
        // Mobile implementation if needed later
        // await ref.putFile(File(file.path!));
      }
      print('Firebase Storage yüklemesi tamamlandı.');

      final url = await ref.getDownloadURL();
      print('Download URL alındı: $url');

      // Update Firestore
      final field = category == 'official' ? 'officialDocs' : 'contractDocs';
      final currentData = Map<String, dynamic>.from(
        _localStaffData[field] ?? {},
      );

      currentData[key] = url;

      print('Firestore güncelleniyor...');
      await FirebaseFirestore.instance.collection('users').doc(staffId).update({
        field: currentData,
      });
      print('Firestore güncellendi.');

      // Update local state
      setState(() {
        _localStaffData[field] = currentData;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dosya başarıyla yüklendi')),
        );
      }
    } catch (e, stack) {
      print('Hata oluştu: $e');
      print(stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingStates[key] = false);
    }
  }

  Future<void> _viewFile(String url, String key) async {
    if (url.isEmpty) return;

    try {
      setState(() => _uploadingStates[key] = true);
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) throw Exception('Dosya indirilemedi');

      await Printing.layoutPdf(
        onLayout: (_) => response.bodyBytes,
        name: 'belge.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingStates[key] = false);
    }
  }

  Widget _docLine({
    required String label,
    required bool uploaded,
    required String category,
    required String key,
    String? url,
  }) {
    final isUploading = _uploadingStates[key] ?? false;

    return InkWell(
      onTap: isUploading
          ? null
          : () {
              if (uploaded && url != null) {
                _viewFile(url, key);
              } else {
                _uploadFile(category, key);
              }
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            if (isUploading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Row(
                children: [
                  Icon(
                    uploaded ? Icons.print : Icons.cloud_upload_outlined,
                    size: 18,
                    color: uploaded ? Colors.indigo : Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    uploaded ? 'Yazdır' : 'Eksik',
                    style: TextStyle(
                      fontSize: 12,
                      color: uploaded ? Colors.indigo : Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilesCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
    VoidCallback? onManage,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 36,
                width: 36,
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.indigo, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (onManage != null)
                TextButton.icon(
                  onPressed: onManage,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text(
                    'Menüde Aç',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }

  bool isUploaded(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is bool) return value;
    if (value is Map && value['uploaded'] is bool) return value['uploaded'];
    if (value is String && value.isNotEmpty) return true;
    return false;
  }

  String? getUrl(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is String && value.isNotEmpty) return value;
    if (value is Map && value['url'] is String) return value['url'];
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final official = _officialDocs;
    final contracts = _contractDocs;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilesCard(
            icon: Icons.folder_shared_outlined,
            title: 'Resmi Belgeler (Yasal / Zorunlu)',
            children: [
              _docLine(
                label: 'Nüfus Cüzdanı Fotokopisi',
                uploaded: isUploaded(official, 'id_copy'),
                category: 'official',
                key: 'id_copy',
                url: getUrl(official, 'id_copy'),
              ),
              _docLine(
                label: 'İkametgâh Belgesi',
                uploaded: isUploaded(official, 'residence'),
                category: 'official',
                key: 'residence',
                url: getUrl(official, 'residence'),
              ),
              _docLine(
                label: 'Adli Sicil Kaydı',
                uploaded: isUploaded(official, 'criminal_record'),
                category: 'official',
                key: 'criminal_record',
                url: getUrl(official, 'criminal_record'),
              ),
              _docLine(
                label: 'Sağlık Raporu',
                uploaded: isUploaded(official, 'health_report'),
                category: 'official',
                key: 'health_report',
                url: getUrl(official, 'health_report'),
              ),
              _docLine(
                label: 'Mezuniyet Diploması',
                uploaded: isUploaded(official, 'diploma'),
                category: 'official',
                key: 'diploma',
                url: getUrl(official, 'diploma'),
              ),
              _docLine(
                label: 'Askerlik Durum Belgesi',
                uploaded: isUploaded(official, 'military_status'),
                category: 'official',
                key: 'military_status',
                url: getUrl(official, 'military_status'),
              ),
            ],
          ),
          _buildFilesCard(
            icon: Icons.description_outlined,
            title: 'Sözleşmeler ve Formlar',
            children: [
              _docLine(
                label: 'İş Sözleşmesi',
                uploaded: isUploaded(contracts, 'employment_contract'),
                category: 'contracts',
                key: 'employment_contract',
                url: getUrl(contracts, 'employment_contract'),
              ),
              _docLine(
                label: 'İşe Giriş Bildirgesi',
                uploaded: isUploaded(contracts, 'employment_notification'),
                category: 'contracts',
                key: 'employment_notification',
                url: getUrl(contracts, 'employment_notification'),
              ),
              _docLine(
                label: 'Gizlilik Sözleşmesi (NDA)',
                uploaded: isUploaded(contracts, 'nda'),
                category: 'contracts',
                key: 'nda',
                url: getUrl(contracts, 'nda'),
              ),
              _docLine(
                label: 'Özgeçmiş (CV)',
                uploaded: isUploaded(contracts, 'cv'),
                category: 'contracts',
                key: 'cv',
                url: getUrl(contracts, 'cv'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LabeledBox extends StatelessWidget {
  final String title;
  const _LabeledBox({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

class _StatusTab extends StatefulWidget {
  final Map<String, dynamic>? staff;

  const _StatusTab({required this.staff});

  @override
  State<_StatusTab> createState() => _StatusTabState();
}

class _StatusTabState extends State<_StatusTab> {
  Map<String, dynamic> get _staffData => widget.staff ?? {};

  Future<void> _editWorkStatus() async {
    final staff = widget.staff;
    if (staff == null || staff['id'] == null) return;
    final id = staff['id'] as String;

    bool isActive = (staff['isActive'] ?? true) as bool;
    final reasonCtrl = TextEditingController(
      text: (staff['inactiveReason'] ?? '').toString(),
    );
    final exitDateCtrl = TextEditingController(
      text: (staff['exitDate'] ?? '').toString(),
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final bottom = MediaQuery.of(context).viewInsets.bottom;
        bool saving = false;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
          child: StatefulBuilder(
            builder: (context, setSheet) {
              Future<void> save() async {
                if (!isActive) {
                  if (reasonCtrl.text.trim().isEmpty ||
                      exitDateCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Pasif personel için pasif olma nedeni ve işten ayrılış tarihi zorunludur.',
                        ),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                }
                setSheet(() => saving = true);
                try {
                  final updateData = <String, dynamic>{
                    'isActive': isActive,
                    'inactiveReason': isActive ? '' : reasonCtrl.text.trim(),
                    'exitDate': isActive ? '' : exitDateCtrl.text.trim(),
                  };
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(id)
                      .update(updateData);

                  if (!mounted) return;
                  setState(() {
                    widget.staff?['isActive'] = isActive;
                    widget.staff?['inactiveReason'] =
                        updateData['inactiveReason'];
                    widget.staff?['exitDate'] = updateData['exitDate'];
                  });
                  Navigator.pop(context);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hata: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  setSheet(() => saving = false);
                }
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Çalışma Durumunu Düzenle',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<bool>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Aktif'),
                          value: true,
                          groupValue: isActive,
                          onChanged: (val) {
                            if (val == null) return;
                            setSheet(() => isActive = val);
                          },
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<bool>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Pasif'),
                          value: false,
                          groupValue: isActive,
                          onChanged: (val) {
                            if (val == null) return;
                            setSheet(() => isActive = val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonCtrl,
                    enabled: !isActive,
                    decoration: const InputDecoration(
                      labelText:
                          'Pasif Olma Nedeni (İstifa, Emeklilik, İşten Çıkarma vb.)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: exitDateCtrl,
                    enabled: !isActive,
                    keyboardType: TextInputType.number,
                    maxLength: 10,
                    decoration: const InputDecoration(
                      labelText: 'İşten Ayrılış Tarihi (gg.aa.yyyy)',
                      border: OutlineInputBorder(),
                      isDense: true,
                      counterText: '',
                    ),
                    onChanged: (value) {
                      final formatted = _formatStatusDate(value);
                      if (formatted != value) {
                        exitDateCtrl.value = TextEditingValue(
                          text: formatted,
                          selection: TextSelection.collapsed(
                            offset: formatted.length,
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: saving ? null : save,
                      icon: saving
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
                      label: Text(saving ? 'Kaydediliyor...' : 'Kaydet'),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _editSystemStatus() async {
    final staff = widget.staff;
    if (staff == null || staff['id'] == null) return;
    final id = staff['id'] as String;

    final usernameCtrl = TextEditingController(
      text: (staff['username'] ?? '').toString(),
    );
    String passwordStatus = (staff['passwordStatus'] ?? 'ilk_giris').toString();
    String role = (staff['role'] ?? 'personel').toString();
    final sizeCtrl = TextEditingController(
      text: (staff['clothingSize'] ?? '').toString(),
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final bottom = MediaQuery.of(context).viewInsets.bottom;
        bool saving = false;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
          child: StatefulBuilder(
            builder: (context, setSheet) {
              Future<void> save() async {
                if (usernameCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Kullanıcı adı zorunludur.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                setSheet(() => saving = true);
                try {
                  final updateData = <String, dynamic>{
                    'username': usernameCtrl.text.trim(),
                    'passwordStatus': passwordStatus,
                    'role': role,
                    'clothingSize': sizeCtrl.text.trim(),
                  };
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(staff['id'] ?? id)
                      .update(updateData);

                  if (!mounted) return;
                  setState(() {
                    widget.staff?['username'] = updateData['username'];
                    widget.staff?['passwordStatus'] =
                        updateData['passwordStatus'];
                    widget.staff?['role'] = updateData['role'];
                    widget.staff?['clothingSize'] = updateData['clothingSize'];
                  });
                  Navigator.pop(context);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hata: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  setSheet(() => saving = false);
                }
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Sistem ve Diğer Bilgiler',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: usernameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Kullanıcı Adı',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Şifre gösterimi ve sıfırlama
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Şifre',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    passwordStatus == 'ilk_giris'
                                        ? (staff['defaultPassword'] ?? '123456').toString()
                                        : '*****',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    passwordStatus == 'ilk_giris'
                                        ? 'Varsayılan şifre'
                                        : 'Kullanıcı şifresini değiştirdi',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: passwordStatus == 'ilk_giris'
                                          ? Colors.orange
                                          : Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Şifreyi Sıfırla'),
                                    content: const Text(
                                      'Kullanıcının şifresini varsayılan şifreye (123456) sıfırlamak istediğinize emin misiniz?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, false),
                                        child: const Text('İptal'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(context, true),
                                        child: const Text('Sıfırla'),
                                      ),
                                    ],
                                  ),
                                );
                                
                                if (confirm == true) {
                                  try {
                                    setSheet(() => saving = true);
                                    
                                    // Eğer kullanıcının Authentication hesabı yoksa onu oluştur
                                    final currentEmail = (staff['email'] ?? staff['corporateEmail'] ?? '').toString();
                                    final currentAuthId = (staff['authUserId'] ?? '').toString();
                                    final username = (staff['username'] ?? '').toString();
                                    final instnId = (staff['institutionId'] ?? '').toString();
                                    
                                    String emailToUse = currentEmail;
                                    if (emailToUse.isEmpty && username.isNotEmpty && instnId.isNotEmpty) {
                                      emailToUse = '$username@$instnId.edukn';
                                    }
                                    
                                    String updatedAuthId = currentAuthId;
                                    String? authError;
                                    
                                    if (currentAuthId.isEmpty && emailToUse.isNotEmpty) {
                                      try {
                                        final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
                                        final url = 'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey';
                                  
                                        final response = await http.post(
                                          Uri.parse(url),
                                          headers: {'Content-Type': 'application/json'},
                                          body: json.encode({
                                            'email': emailToUse,
                                            'password': '123456',
                                            'returnSecureToken': true,
                                          }),
                                        );
                                  
                                        if (response.statusCode == 200) {
                                          final rData = json.decode(response.body);
                                          updatedAuthId = rData['localId'] as String;
                                        } else {
                                          final errData = json.decode(response.body);
                                          authError = errData['error']['message'];
                                        }
                                      } catch (e) {
                                        authError = e.toString();
                                      }
                                    }

                                    if (authError != null && authError.contains('EMAIL_EXISTS')) {
                                       // Email already exists, assume auth is valid? We shouldn't fail totally, but maybe show warning.
                                       // Actually, let's show an error and not update if we failed to create a new one when expected to
                                       throw 'Bu e-posta adresi sistemde zaten kayıtlı: $authError';
                                    } else if (authError != null) {
                                       throw 'Kullanıcı hesabı oluşturulurken hata: $authError';
                                    }

                                    // Firestore'u güncelle
                                    final updates = <String, dynamic>{
                                      'passwordStatus': 'ilk_giris',
                                      'defaultPassword': '123456',
                                    };
                                    if (emailToUse != currentEmail) {
                                      updates['email'] = emailToUse;
                                    }
                                    
                                    // Önemli: Eğer modül yetkileri yoksa varsayılanları ekle
                                    if (staff['modulePermissions'] == null) {
                                      updates['modulePermissions'] = {
                                        'genel_duyurular': {'enabled': true, 'level': 'editor'},
                                        'okul_turleri': {'enabled': true, 'level': 'viewer'},
                                        'ogrenci_kayit': {'enabled': false, 'level': 'viewer'},
                                        'insan_kaynaklari': {'enabled': false, 'level': 'viewer'},
                                        'muhasebe': {'enabled': false, 'level': 'viewer'},
                                        'satin_alma': {'enabled': false, 'level': 'viewer'},
                                        'depo': {'enabled': false, 'level': 'viewer'},
                                        'destek_hizmetleri': {'enabled': false, 'level': 'viewer'},
                                        'kullanici_yonetimi': {'enabled': false, 'level': 'viewer'},
                                      };
                                    }
                                    
                                    if (staff['schoolTypes'] == null) {
                                      updates['schoolTypes'] = [];
                                    }
                                    
                                    final oldDocId = staff['id'].toString();

                                    if (updatedAuthId.isNotEmpty && updatedAuthId != oldDocId) {
                                      // DOKÜMAN MİGRASYONU: Eski ID -> Auth UID
                                      // 1. Mevcut veriyi al
                                      final currentDoc = await FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(oldDocId)
                                          .get();
                                      
                                      final fullData = Map<String, dynamic>.from(currentDoc.data() ?? {});
                                      
                                      // 2. Yeni alanları ekle/güncelle
                                      fullData.addAll(updates);
                                      fullData['authUserId'] = updatedAuthId;
                                      
                                      // 3. Yeni dokümanı oluştur
                                      await FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(updatedAuthId)
                                          .set(fullData);
                                          
                                      // 4. Eski dokümanı sil (id çakışması yoksa)
                                      await FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(oldDocId)
                                          .delete();
                                      
                                      print('✅ Kullanıcı dokümanı migre edildi: $oldDocId -> $updatedAuthId');
                                      
                                      // UI için ID güncelle
                                      staff['id'] = updatedAuthId;
                                    } else {
                                      // Sadece güncelleme (zaten UID ile kayıtlı veya authId oluşturulamadı)
                                      if (updatedAuthId.isNotEmpty) {
                                        updates['authUserId'] = updatedAuthId;
                                      }
                                      await FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(oldDocId)
                                          .update(updates);
                                    }
                                    
                                    setSheet(() {
                                      passwordStatus = 'ilk_giris';
                                      saving = false;
                                    });
                                    
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('✅ Şifre sıfırlandı'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  } catch (e) {
                                    setSheet(() => saving = false);
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('❌ Hata: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Sıfırla'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: role,
                    items: const [
                      DropdownMenuItem(
                        value: 'genel_mudur',
                        child: Text('Genel Müdür'),
                      ),
                      DropdownMenuItem(
                        value: 'mudur',
                        child: Text('Müdür'),
                      ),
                      DropdownMenuItem(
                        value: 'mudur_yardimcisi',
                        child: Text('Müdür Yardımcısı'),
                      ),
                      DropdownMenuItem(
                        value: 'yonetici',
                        child: Text('Yönetici'),
                      ),
                      DropdownMenuItem(
                        value: 'rehber_ogretmen',
                        child: Text('Rehber Öğretmen'),
                      ),
                      DropdownMenuItem(
                        value: 'ogretmen',
                        child: Text('Öğretmen'),
                      ),
                      DropdownMenuItem(
                        value: 'personel',
                        child: Text('Personel'),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Kullanıcı Rolü',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setSheet(() {
                      role = v ?? 'personel';
                    }),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: sizeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Kıyafet Bedeni (Opsiyonel)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: saving ? null : save,
                      icon: saving
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
                      label: Text(saving ? 'Kaydediliyor...' : 'Kaydet'),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  String _formatStatusDate(String input) {
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

  Widget buildStatusCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.indigo, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  ...children,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final staff = _staffData;

    final isActive = (staff['isActive'] ?? true) as bool;
    final inactiveReason = (staff['inactiveReason'] ?? '').toString();
    final exitDate = (staff['exitDate'] ?? '').toString();

    final username = (staff['username'] ?? '').toString();
    final passwordStatus = (staff['passwordStatus'] ?? 'ilk_giris').toString();
    final role = (staff['role'] ?? 'personel').toString();
    final clothingSize = (staff['clothingSize'] ?? '').toString();

    String formatRole(String value) {
      switch (value) {
        case 'genel_mudur':
          return 'Genel Müdür';
        case 'mudur':
          return 'Müdür';
        case 'mudur_yardimcisi':
          return 'Müdür Yardımcısı';
        case 'yonetici':
          return 'Yönetici';
        case 'rehber_ogretmen':
          return 'Rehber Öğretmen';
        case 'ogretmen':
          return 'Öğretmen';
        case 'personel':
        default:
          return 'Personel';
      }
    }

    Widget statusLine(String label, String value) {
      final show = value.isNotEmpty ? value : '-';
      return Padding(
        padding: const EdgeInsets.only(bottom: 2.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            Expanded(child: Text(show, style: const TextStyle(fontSize: 12))),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildStatusCard(
            icon: Icons.verified_user_outlined,
            title: 'Çalışma Durumu',
            children: [
              statusLine('Çalışma Durumu', isActive ? 'Aktif' : 'Pasif'),
              statusLine('Pasif Olma Nedeni', inactiveReason),
              statusLine('İşten Ayrılış Tarihi', exitDate),
            ],
            onTap: _editWorkStatus,
          ),
          buildStatusCard(
            icon: Icons.settings_applications_outlined,
            title: 'Sistem Durumu ve Diğer',
            children: [
              statusLine('Kullanıcı Adı', username),
              statusLine(
                'Şifre',
                passwordStatus == 'ilk_giris'
                    ? (staff['defaultPassword'] ?? '123456').toString()
                    : '*****',
              ),
              statusLine('Kullanıcı Rolü', formatRole(role)),
              statusLine('Kıyafet Bedeni', clothingSize),
            ],
            onTap: _editSystemStatus,
          ),
        ],
      ),
    );
  }
}
