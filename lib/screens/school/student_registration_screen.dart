import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/user_permission_service.dart';
import '../../services/term_service.dart';

// Helper metodlar - Her iki class da kullanabilir

// Büyük harf formatlayıcı
class UpperCaseTextFormatter extends TextInputFormatter {
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

// Tarih formatlayıcı (gg.aa.yyyy)
class DateTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (text.isEmpty) {
      return TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    String formatted = '';
    for (int i = 0; i < text.length && i < 8; i++) {
      if (i == 2 || i == 4) {
        formatted += '.';
      }
      formatted += text[i];
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

Future<void> _launchParentPhone(BuildContext context, String? phone) async {
  if (phone == null || phone.isEmpty) return;

  final normalized = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  final uri = Uri(scheme: 'tel', path: normalized);

  try {
    final canCall = await canLaunchUrl(uri);
    if (!canCall) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bu cihazdan arama yapılamıyor.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final launched = await launchUrl(uri);
    if (!launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Arama başlatılamadı.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } catch (_) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Arama yapılırken bir hata oluştu.'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

bool validateTC(String tc) {
  if (tc.length != 11) return false;
  if (tc[0] == '0') return false;

  try {
    final digits = tc.split('').map((e) => int.parse(e)).toList();

    final sum10 = digits.sublist(0, 10).reduce((a, b) => a + b);
    if (sum10 % 10 != digits[10]) return false;

    final odd = digits[0] + digits[2] + digits[4] + digits[6] + digits[8];
    final even = digits[1] + digits[3] + digits[5] + digits[7];
    if ((odd * 7 - even) % 10 != digits[9]) return false;

    return true;
  } catch (e) {
    return false;
  }
}

class StudentRegistrationScreen extends StatefulWidget {
  final String? fixedSchoolTypeId;
  final String? fixedSchoolTypeName;
  final String? fixedInstitutionId;

  const StudentRegistrationScreen({
    Key? key,
    this.fixedSchoolTypeId,
    this.fixedSchoolTypeName,
    this.fixedInstitutionId,
  }) : super(key: key);

  @override
  _StudentRegistrationScreenState createState() =>
      _StudentRegistrationScreenState();
}

class _StudentRegistrationScreenState extends State<StudentRegistrationScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  TabController? _tabController;
  String? _selectedStudentId;
  bool _isLoading = false;
  String? _institutionId;

  // Yetkilendirme için
  Map<String, dynamic>? userData;

  // Öğrenci verileri
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _schoolTypes = [];
  List<Map<String, dynamic>> _filteredStudents = [];

  // Form controllers
  final TextEditingController _searchController = TextEditingController();

  // Additional fields
  List<Map<String, dynamic>> _terms = []; // Dönemler

  // Search & Filter
  String _statusFilter = 'active'; // 'active', 'inactive', 'all'
  String? _selectedTermFilter; // Dönem filtresi
  String? _filterSchoolType; // Okul türü filtresi (null = tümü)
  String? _filterClassLevel; // Sınıf seviyesi filtresi (null = tümü)
  String? _filterClass; // Sınıf filtresi (öğrencinin kayıtlı olduğu sınıf)
  String? _filterEntryType; // Giriş türü filtresi (yeni kayıt, kayıt yenileme)
  bool _showFilters = false; // Filtre panelini göster/gizle
  bool _isViewingPastTerm = false; // Geçmiş dönem görüntüleniyor mu?

  // Selected student
  Map<String, dynamic>? _selectedStudent;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController?.addListener(() {
      setState(() {}); // Tab değiştiğinde UI'ı güncelle
    });

    // Eğer okul türü sabitlendiyse, filtreyi ayarla
    if (widget.fixedSchoolTypeId != null) {
      _filterSchoolType = widget.fixedSchoolTypeId;
    }

    _loadUserPermissions();
    _loadData();
    _searchController.addListener(_filterStudents);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ekrana her dönüşte dönem bilgisini yeniden yükle
    _reloadTermFilter();
  }

  // Dönem filtresini yeniden yükle
  Future<void> _reloadTermFilter() async {
    final selectedTermId = await TermService().getSelectedTermId();
    final activeTermId = await TermService().getActiveTermId();
    // Eğer seçili dönem yoksa aktif dönemi kullan
    final effectiveTermId = selectedTermId ?? activeTermId;
    if (mounted && _selectedTermFilter != effectiveTermId) {
      setState(() {
        _selectedTermFilter = effectiveTermId;
        _isViewingPastTerm =
            selectedTermId != null && selectedTermId != activeTermId;
      });
      _filterStudents();
    }
  }

  // Kullanıcı yetkilendirme bilgilerini yükle
  Future<void> _loadUserPermissions() async {
    final data = await UserPermissionService.loadUserData();
    if (mounted) {
      setState(() => userData = data);
    }
  }

  // Öğrenci kayıt modülüne düzenleme yetkisi var mı?
  bool _canEditStudents() {
    return UserPermissionService.canEdit('ogrenci_kayit', userData);
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Text('Öğrenciyi Sil'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_selectedStudent?['fullName']} isimli öğrenciyi silmek istediğinize emin misiniz?',
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
                  Icon(
                    Icons.info_outline,
                    color: Colors.orange.shade700,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Öğrenci pasif duruma alınacak. Numara başka öğrenciye verilebilir.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Öğrenci numarasını boşa çıkarmak ister misiniz?',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Evet derseniz, bu numara yeni kayıtlarda kullanılabilir.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
                  Icon(
                    Icons.delete_forever,
                    color: Colors.red.shade700,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Kalıcı Sil: Öğrenci kaydı tamamen silinir, geri getirilemez!',
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
              _softDeleteStudent(keepNumber: true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text('Pasif (Numara Sakla)'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _softDeleteStudent(keepNumber: false);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
            child: Text('Pasif (Numara Boşalt)'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _permanentDeleteStudent();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            child: Text('Kalıcı Sil'),
          ),
        ],
      ),
    );
  }

  Future<void> _softDeleteStudent({required bool keepNumber}) async {
    if (_selectedStudentId == null) return;

    try {
      final updateData = {
        'isActive': false,
        'deletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Numarayı boşalt
      if (!keepNumber) {
        updateData['studentNo'] = '';
        updateData['studentNumber'] = '';
      }

      await FirebaseFirestore.instance
          .collection('students')
          .doc(_selectedStudentId)
          .update(updateData);

      setState(() {
        _selectedStudent = null;
        _selectedStudentId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            keepNumber
                ? '✓ Öğrenci pasife alındı (Numara korundu)'
                : '✓ Öğrenci pasife alındı (Numara boşaltıldı)',
          ),
          backgroundColor: Colors.green,
        ),
      );

      _loadData(); // Listeyi yenile
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _permanentDeleteStudent() async {
    if (_selectedStudentId == null) return;

    // Ekstra onay dialogu
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red, size: 32),
            SizedBox(width: 12),
            Text('Kalıcı Silme Onayı'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Bu işlem GERİ ALINAMAZ!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            Text(
              '${_selectedStudent?['fullName']} isimli öğrenci kalıcı olarak silinecek. Bu öğrenciyle ilgili tüm veriler kaybolacak.',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            Text(
              'Devam etmek istediğinize emin misiniz?',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Hayır, İptal Et'),
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
      // Firestore'dan kalıcı olarak sil
      await FirebaseFirestore.instance
          .collection('students')
          .doc(_selectedStudentId)
          .delete();

      setState(() {
        _selectedStudent = null;
        _selectedStudentId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Öğrenci kalıcı olarak silindi'),
          backgroundColor: Colors.red.shade700,
          duration: Duration(seconds: 3),
        ),
      );

      _loadData(); // Listeyi yenile
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteAllStudents() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('DİKKAT!'),
        content: Text(
          'Bu işlem kayıtlı TÜM ÖĞRENCİLERİ kalıcı olarak silecek. Emir geri alınamaz. Emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('EVET, HEPSİNİ SİL'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Siliniyor...')));

      final batchSize = 400; // Batch limit 500
      var query = FirebaseFirestore.instance
          .collection('students')
          .where(
            'institutionId',
            isEqualTo: _institutionId,
          ) // Sadece bu kurumun öğrencilerini sil
          .limit(batchSize);

      while (true) {
        final snapshot = await query.get();
        if (snapshot.docs.isEmpty) break;

        final batch = FirebaseFirestore.instance.batch();
        for (var doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        await Future.delayed(Duration(milliseconds: 50));
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Tüm öğrenciler silindi.')));
      _loadData(); // Listeyi yenile
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Future<void> _loadData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final email = user.email!;
      final institutionId = email.split('@')[1].split('.')[0].toUpperCase();

      final schoolTypesQuery = await FirebaseFirestore.instance
          .collection('schoolTypes')
          .where('institutionId', isEqualTo: institutionId)
          .get();

      // Dönemleri yükle
      final termsQuery = await FirebaseFirestore.instance
          .collection('terms')
          .where('institutionId', isEqualTo: institutionId)
          .get();

      // Seçili dönemi al (TermService'den)
      final selectedTermId = await TermService().getSelectedTermId();

      // Tüm öğrencileri çek, dönem filtresi client-side yapılacak
      final studentsQuery = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: institutionId)
          .orderBy('createdAt', descending: true)
          .get();

      setState(() {
        _institutionId = institutionId;
        _schoolTypes = schoolTypesQuery.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();

        _terms = termsQuery.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();

        // Seçili dönemi kullan (TermService'den gelen)
        if (selectedTermId != null) {
          _selectedTermFilter = selectedTermId;
        } else {
          // Aktif dönemi otomatik seç
          final activeTerm = _terms.firstWhere(
            (term) => term['isActive'] == true,
            orElse: () => _terms.isNotEmpty ? _terms.first : {},
          );
          if (activeTerm.isNotEmpty) {
            _selectedTermFilter = activeTerm['id'];
          }
        }

        _students = studentsQuery.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();

        _filteredStudents = List.from(_students);

        // İlk öğrenciyi otomatik seçme - kullanıcı manuel seçsin

        // Debug: Okul türlerini kontrol et
        print('📚 Yüklenen okul sayısı: ${_schoolTypes.length}');
        for (var st in _schoolTypes) {
          print(
            '  - ${st['schoolTypeName'] ?? st['typeName']} (Tür: ${st['schoolType']})',
          );
        }

        _isLoading = false;
      });

      // Filtrelemeyi her zaman uygula (dönem filtresi dahil)
      _filterStudents();
    } catch (e) {
      print('❌ Veri yükleme hatası: $e');
      setState(() => _isLoading = false);
    }
  }

  void _filterStudents() {
    setState(() {
      _filteredStudents = _students.where((student) {
        final searchQuery = _searchController.text.toLowerCase();
        final matchesSearch =
            searchQuery.isEmpty ||
            (student['fullName'] ?? '').toLowerCase().contains(searchQuery) ||
            (student['studentNumber'] ?? '').toLowerCase().contains(
              searchQuery,
            );

        // Dönem filtresi: sadece seçili döneme ait olanları göster
        final studentTermId = student['termId'] as String?;
        final matchesTerm =
            _selectedTermFilter == null || studentTermId == _selectedTermFilter;

        // Okul türü filtresi
        final matchesSchoolType =
            _filterSchoolType == null ||
            student['schoolTypeId'] == _filterSchoolType;

        // Sınıf seviyesi filtresi
        // Sınıf seviyesi filtresi
        final studentLevelDigits = (student['classLevel']?.toString() ?? '')
            .replaceAll(RegExp(r'[^0-9]'), '');

        String? filterLevelDigits;
        if (_filterClassLevel != null) {
          filterLevelDigits = _filterClassLevel!.replaceAll(
            RegExp(r'[^0-9]'),
            '',
          );
        }

        final matchesClassLevel =
            _filterClassLevel == null ||
            (filterLevelDigits != null &&
                studentLevelDigits == filterLevelDigits);

        // Sınıf filtresi (öğrencinin kayıtlı olduğu sınıf)
        final matchesClass =
            _filterClass == null || student['classId'] == _filterClass;

        // Giriş türü filtresi
        final matchesEntryType =
            _filterEntryType == null ||
            student['entryType'] == _filterEntryType;

        // Status filtresi
        final isActive = student['isActive'] ?? true; // Varsayılan aktif
        final matchesStatus =
            _statusFilter == 'all' ||
            (_statusFilter == 'active' && isActive) ||
            (_statusFilter == 'inactive' && !isActive);

        return matchesSearch &&
            matchesTerm &&
            matchesSchoolType &&
            matchesClassLevel &&
            matchesClass &&
            matchesEntryType &&
            matchesStatus;
      }).toList();

      // Alfabetik sıralama ekle
      _filteredStudents.sort((a, b) {
        final nameA = (a['fullName'] ?? '').toString().toLowerCase();
        final nameB = (b['fullName'] ?? '').toString().toLowerCase();
        return nameA.compareTo(nameB);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // Her build'de dönem kontrolü yap
    _reloadTermFilter();

    final isWideScreen = MediaQuery.of(context).size.width > 900;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('Öğrenci Kayıt')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Geri',
        ),
        title: widget.fixedSchoolTypeName != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.fixedSchoolTypeName!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Öğrenci Listesi',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              )
            : const Text('Öğrenci Kayıt Sistemi'),
        actions: [
          if (_canEditStudents())
            IconButton(
              icon: const Icon(Icons.person_add),
              onPressed: () => _showNewStudentDialog(),
              tooltip: 'Yeni Öğrenci',
            ),
          if (_canEditStudents())
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'delete_all') {
                  _deleteAllStudents();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'delete_all',
                  child: Row(
                    children: [
                      Icon(Icons.delete_forever, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('TÜMÜNÜ SİL (DEBUG)'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: isWideScreen
            ? Row(
                children: [
                  SizedBox(width: 380, child: _buildStudentList()),
                  const VerticalDivider(width: 20),
                  Expanded(
                    child: _selectedStudent != null
                        ? _buildRegistrationForm()
                        : _buildEmptyFormPlaceholder(),
                  ),
                ],
              )
            : Column(children: [Expanded(child: _buildStudentList())]),
      ),
    );
  }

  Widget _buildStudentList() {
    return Column(
      children: [
        // Header - Personel sayfası gibi
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
                  const Icon(Icons.school, color: Colors.white),
                  const SizedBox(width: 8),
                  const Text(
                    'Öğrenciler',
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
                      '${_filteredStudents.length}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Arama + Filtre butonu
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Öğrenci ara',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _searchController.clear();
                                  });
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      icon: Icon(
                        _showFilters
                            ? Icons.filter_alt
                            : Icons.filter_alt_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _showFilters = !_showFilters;
                        });
                      },
                      tooltip: 'Filtreler',
                      padding: EdgeInsets.all(8),
                      constraints: BoxConstraints(),
                    ),
                  ),
                ],
              ),
              // Detaylı Filtreler (Arama ile Aktif/Pasif arasında)
              if (_showFilters) ...[
                const SizedBox(height: 10),
                // İlk satır: Dönem ve Okul Türü
                Row(
                  children: [
                    Flexible(
                      flex: 1,
                      child: Theme(
                        data: Theme.of(
                          context,
                        ).copyWith(canvasColor: Colors.indigo.shade700),
                        child: DropdownButtonFormField<String?>(
                          value: _selectedTermFilter,
                          style: TextStyle(color: Colors.white),
                          icon: Icon(
                            Icons.arrow_drop_down,
                            color: Colors.white70,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Dönem',
                            labelStyle: TextStyle(
                              color: Colors.indigo.shade100,
                            ),
                            isDense: true,
                            filled: true,
                            fillColor: Colors.indigo.shade400,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          isExpanded: true,
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(
                                'Tümü',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            ..._terms.map(
                              (term) => DropdownMenuItem<String?>(
                                value: term['id'],
                                child: Text(
                                  '${term['name']} ${term['isActive'] == true ? ' ✓' : ''}',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedTermFilter = value;
                              _filterStudents();
                            });
                          },
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Flexible(
                      flex: 1,
                      child: Theme(
                        data: Theme.of(
                          context,
                        ).copyWith(canvasColor: Colors.indigo.shade700),
                        child: DropdownButtonFormField<String?>(
                          value: _filterSchoolType,
                          style: TextStyle(color: Colors.white),
                          icon: Icon(
                            Icons.arrow_drop_down,
                            color: Colors.white70,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Okul Türü',
                            labelStyle: TextStyle(
                              color: Colors.indigo.shade100,
                            ),
                            isDense: true,
                            filled: true,
                            fillColor: Colors.indigo.shade400,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          isExpanded: true,
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(
                                'Genel',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            ..._schoolTypes.map(
                              (type) => DropdownMenuItem<String?>(
                                value: type['id'],
                                child: Text(
                                  type['schoolTypeName'] ??
                                      type['typeName'] ??
                                      '',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                          onChanged: widget.fixedSchoolTypeId == null
                              ? (value) {
                                  setState(() {
                                    _filterSchoolType = value;
                                    _filterClassLevel = null;
                                    _filterStudents();
                                  });
                                }
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                // İkinci satır: Sınıf Seviyesi, Şube, Giriş Türü
                Row(
                  children: [
                    Flexible(
                      flex: 1,
                      child: Theme(
                        data: Theme.of(
                          context,
                        ).copyWith(canvasColor: Colors.indigo.shade700),
                        child: DropdownButtonFormField<String?>(
                          value: _filterClassLevel,
                          style: TextStyle(color: Colors.white),
                          icon: Icon(
                            Icons.arrow_drop_down,
                            color: Colors.white70,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Sınıf Seviyesi',
                            labelStyle: TextStyle(
                              color: Colors.indigo.shade100,
                            ),
                            isDense: true,
                            filled: true,
                            fillColor: Colors.indigo.shade400,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          isExpanded: true,
                          items: _getClassLevelFilterItems().map((item) {
                            return DropdownMenuItem<String?>(
                              value: item.value,
                              child: Text(
                                (item.child as Text).data ?? '',
                                style: TextStyle(color: Colors.white),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _filterClassLevel = value;
                              _filterClass =
                                  null; // Seviye değişince şube filtresini sıfırla
                              _filterStudents();
                            });
                          },
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Flexible(
                      flex: 1,
                      child: Builder(
                        builder: (context) {
                          // 1. Mevcut öğrencilerden şube listesini türet (Data-Driven Filter)
                          // Bu yöntem, "classes" koleksiyonundaki veri eksikliklerini veya tip uyuşmazlıklarını by-pass eder.
                          // Sadece listede var olan öğrencilerin şubelerini gösterir.
                          var sourceStudents = _students;

                          // Okul filtrele
                          if (_filterSchoolType != null) {
                            sourceStudents = sourceStudents
                                .where(
                                  (s) => s['schoolTypeId'] == _filterSchoolType,
                                )
                                .toList();
                          }
                          // Sınıf Seviyesi filtrele
                          if (_filterClassLevel != null) {
                            final fDigits = _filterClassLevel!.replaceAll(
                              RegExp(r'[^0-9]'),
                              '',
                            );
                            sourceStudents = sourceStudents.where((s) {
                              final sLevel = (s['classLevel'] ?? '').toString();
                              final sDigits = sLevel.replaceAll(
                                RegExp(r'[^0-9]'),
                                '',
                              );
                              return sDigits == fDigits;
                            }).toList();
                          }

                          // Benzersiz Şubeleri Çıkar (Adına göre)
                          final uniqueBranches = <String>{};
                          final branchList = <Map<String, dynamic>>[];

                          for (final s in sourceStudents) {
                            final cName = s['className'] as String?;
                            final cId = s['classId'] as String?;
                            // Branch ID ve Name dolu olmalı
                            if (cName != null &&
                                cName.isNotEmpty &&
                                cId != null) {
                              if (!uniqueBranches.contains(cName)) {
                                uniqueBranches.add(cName);
                                branchList.add({'id': cId, 'name': cName});
                              }
                            }
                          }

                          // İsme göre sırala (Örn: 8-A, 8-B...)
                          branchList.sort(
                            (a, b) => (a['name'] as String).compareTo(
                              b['name'] as String,
                            ),
                          );

                          // Seçili değerin listede olup olmadığını kontrol et
                          // Eğer filtre değiştiyse ve mevcut _filterClass yeni listede yoksa, value'yu null yapmalıyız
                          // Ancak UI state'ini burada değiştirmek (setState) risklidir (build sırasında).
                          // Bu yüzden Dropdown'a geçecek "effectiveValue"yu hesaplayalım.
                          String? effectiveValue = _filterClass;
                          if (effectiveValue != null) {
                            bool exists = branchList.any(
                              (b) => b['id'] == effectiveValue,
                            );
                            if (!exists) effectiveValue = null;
                          }

                          return Theme(
                            data: Theme.of(
                              context,
                            ).copyWith(canvasColor: Colors.indigo.shade700),
                            child: DropdownButtonFormField<String?>(
                              value: effectiveValue,
                              style: TextStyle(color: Colors.white),
                              icon: Icon(
                                Icons.arrow_drop_down,
                                color: Colors.white70,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Şube',
                                labelStyle: TextStyle(
                                  color: Colors.indigo.shade100,
                                ),
                                isDense: true,
                                filled: true,
                                fillColor: Colors.indigo.shade400,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              isExpanded: true,
                              items: [
                                DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text(
                                    'Tümü',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                                ...branchList.map((classItem) {
                                  return DropdownMenuItem<String?>(
                                    value: classItem['id'],
                                    child: Text(
                                      classItem['name'],
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  );
                                }).toList(),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _filterClass = value;
                                  _filterStudents();
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(width: 8),
                    Flexible(
                      flex: 1,
                      child: Theme(
                        data: Theme.of(
                          context,
                        ).copyWith(canvasColor: Colors.indigo.shade700),
                        child: DropdownButtonFormField<String?>(
                          value: _filterEntryType,
                          style: TextStyle(color: Colors.white),
                          icon: Icon(
                            Icons.arrow_drop_down,
                            color: Colors.white70,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Giriş Türü',
                            labelStyle: TextStyle(
                              color: Colors.indigo.shade100,
                            ),
                            isDense: true,
                            filled: true,
                            fillColor: Colors.indigo.shade400,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          isExpanded: true,
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(
                                'Tümü',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'Yeni',
                              child: Text(
                                'Yeni Kayıt',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'Yenileme',
                              child: Text(
                                'Kayıt Yenileme',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _filterEntryType = value;
                              _filterStudents();
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              // Status chips (Aktif/Pasif/Tümü)
              Row(
                children: [
                  _buildStatusChip('active', 'Aktif', Icons.check_circle),
                  const SizedBox(width: 4),
                  _buildStatusChip('inactive', 'Pasif', Icons.cancel),
                  const SizedBox(width: 4),
                  _buildStatusChip('all', 'Tümü', Icons.list),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Öğrenci listesi veya boş durum
        Expanded(
          child: _filteredStudents.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  itemCount: _filteredStudents.length,
                  itemBuilder: (context, index) {
                    final student = _filteredStudents[index];
                    final studentId = student['id'];
                    final isSelected = studentId == _selectedStudentId;

                    return Container(
                      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.blue.shade50 : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? Colors.blue.shade300
                              : Colors.grey.shade200,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: isSelected
                              ? Colors.blue.shade100
                              : Colors.grey.shade200,
                          backgroundImage: student['photoUrl'] != null
                              ? NetworkImage(student['photoUrl'])
                              : null,
                          child: student['photoUrl'] == null
                              ? Icon(
                                  Icons.person,
                                  color: isSelected
                                      ? Colors.blue.shade700
                                      : Colors.grey.shade600,
                                  size: 18,
                                )
                              : null,
                        ),
                        title: Text(
                          student['fullName'] ?? 'İsimsiz',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: isSelected
                                ? Colors.blue.shade900
                                : Colors.grey.shade900,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: isSelected
                            ? Icon(
                                Icons.check_circle,
                                color: Colors.blue,
                                size: 20,
                              )
                            : Icon(
                                Icons.chevron_right,
                                color: Colors.grey.shade400,
                                size: 20,
                              ),
                        onTap: () {
                          final isWide =
                              MediaQuery.of(context).size.width > 900;

                          setState(() {
                            _selectedStudent = student;
                            _selectedStudentId = studentId;
                          });

                          // Mobilde yeni ekran olarak aç
                          if (!isWide) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    _StudentRegistrationFormScreen(
                                      onSave: () {
                                        _loadData();
                                      },
                                      existingStudent: student,
                                      isViewingPastTerm: _isViewingPastTerm,
                                      fixedSchoolTypeId:
                                          widget.fixedSchoolTypeId,
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
  }

  Widget _buildStatusChip(String value, String label, IconData icon) {
    final isSelected = _statusFilter == value;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _statusFilter = value;
          });
          _filterStudents();
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.3),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.blue : Colors.white,
              ),
              SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.blue : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Sınıf seviyesi filtre öğelerini döndür (okul türüne göre dinamik)
  List<DropdownMenuItem<String?>> _getClassLevelFilterItems() {
    List<DropdownMenuItem<String?>> items = [
      DropdownMenuItem<String?>(value: null, child: Text('Tümü')),
    ];

    if (_filterSchoolType == null) {
      // Genel - tüm seviyeleri göster
      items.addAll(
        ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12'].map(
          (level) =>
              DropdownMenuItem<String?>(value: level, child: Text(level)),
        ),
      );
    } else {
      // Seçili okul türüne ait seviyeleri göster
      final selectedSchool = _schoolTypes.firstWhere(
        (st) => st['id'] == _filterSchoolType,
        orElse: () => {},
      );

      final activeGrades = selectedSchool['activeGrades'] as List<dynamic>?;
      if (activeGrades != null && activeGrades.isNotEmpty) {
        items.addAll(
          activeGrades.map(
            (grade) => DropdownMenuItem<String?>(
              value: grade.toString(),
              child: Text(grade.toString()),
            ),
          ),
        );
      }
    }

    return items;
  }

  Widget _buildEmptyState() {
    // Mesajı duruma göre ayarla
    String title;
    String subtitle;
    bool showAddButton = false;

    if (_searchController.text.isNotEmpty) {
      title = 'Öğrenci Bulunamadı';
      subtitle =
          'Aranan kriterlere uygun öğrenci bulun amadı.\nLütfen farklı bir arama yapın.';
    } else if (_statusFilter == 'inactive') {
      title = 'Pasif Öğrenci Yok';
      subtitle = 'Pasif durumda öğrenci bulunmamaktadır.';
    } else if (_statusFilter == 'all') {
      title = 'Henüz Öğrenci Yok';
      subtitle = 'Sistemde kayıtlı öğrenci bulunmamaktadır.';
      showAddButton = true;
    } else {
      // active
      title = 'Aktif Öğrenci Yok';
      subtitle = 'Yeni bir öğrenci kaydı ekleyerek\nbaşlayabilirsiniz.';
      showAddButton = true;
    }

    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.school_outlined,
                size: 60,
                color: Colors.blue.shade300,
              ),
            ),
            SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            SizedBox(height: 12),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
            if (showAddButton && _canEditStudents()) ...[
              SizedBox(height: 32),
              ElevatedButton.icon(
                icon: Icon(Icons.person_add, size: 24),
                label: Text(
                  'İlk Öğrenciyi Ekle',
                  style: TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => _StudentRegistrationFormScreen(
                        onSave: () {
                          _loadData();
                        },
                        isViewingPastTerm: _isViewingPastTerm,
                        fixedSchoolTypeId: widget.fixedSchoolTypeId,
                      ),
                    ),
                  );
                },
              ),
            ] else if (showAddButton && !_canEditStudents()) ...[
              SizedBox(height: 32),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade700),
                    SizedBox(width: 8),
                    Text(
                      'Sadece görüntüleme yetkiniz var',
                      style: TextStyle(color: Colors.orange.shade900),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyFormPlaceholder() {
    return Container(
      color: Colors.grey.shade50,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_add_alt_1,
              size: 120,
              color: Colors.grey.shade300,
            ),
            SizedBox(height: 24),
            Text(
              'Yeni Öğrenci Kaydı',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Yeni öğrenci eklemek için yukarıdaki\n"Yeni Öğrenci Ekle" butonuna tıklayın',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
            SizedBox(height: 32),
            Text(
              'veya',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
            SizedBox(height: 16),
            Text(
              'Soldan bir öğrenci seçerek\nbilgilerini düzenleyin',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegistrationForm() {
    if (_selectedStudent == null) {
      return _buildEmptyFormPlaceholder();
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 1,
          leading: MediaQuery.of(context).size.width <= 900
              ? IconButton(
                  icon: Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                )
              : null,
          automaticallyImplyLeading: false,
          title: Row(
            children: [
              Icon(Icons.school, color: Colors.indigo),
              SizedBox(width: 8),
              Text(
                'Öğrenci Detayı',
                style: TextStyle(
                  color: Colors.grey.shade900,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          actions: [
            if (_canEditStudents())
              LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = MediaQuery.of(context).size.width <= 900;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Yazdır butonu
                      isMobile
                          ? IconButton(
                              icon: Icon(Icons.print),
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Yazdırma yakında eklenecek'),
                                  ),
                                );
                              },
                              tooltip: 'Yazdır / Dışa Aktar',
                            )
                          : TextButton.icon(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Yazdırma yakında eklenecek'),
                                  ),
                                );
                              },
                              icon: Icon(Icons.print, size: 18),
                              label: Text('Yazdır'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.indigo,
                              ),
                            ),
                      // Sil butonu
                      isMobile
                          ? IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              onPressed: _showDeleteConfirmation,
                              tooltip: 'Öğrenciyi Sil',
                            )
                          : TextButton.icon(
                              onPressed: _showDeleteConfirmation,
                              icon: Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: Colors.red,
                              ),
                              label: Text('Sil'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                            ),
                    ],
                  );
                },
              ),
          ],
          bottom: TabBar(
            labelColor: Colors.indigo,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.indigo,
            tabs: [
              Tab(text: 'Kişisel Bilgiler'),
              Tab(text: 'Okul Bilgileri'),
              Tab(text: 'Veli Bilgileri'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildPersonalInfoTab(),
            _buildSchoolInfoTab(),
            _buildParentInfoTabNew(),
          ],
        ),
      ),
    );
  }

  // Kişisel Bilgiler Tab
  Widget _buildPersonalInfoTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          _buildInfoCard(
            title: 'Genel Bilgiler',
            icon: Icons.person,
            onTap: () => _showEditDialog('Genel Bilgiler'),
            children: [
              _buildStudentPhotoAndName(),
              Divider(height: 32),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 600;
                  if (isMobile) {
                    // Mobilde alt alta
                    return Column(
                      children: [
                        _buildInfoRow('TC:', _selectedStudent?['tcNo'] ?? '-'),
                        _buildInfoRow(
                          'Doğum Tarihi:',
                          _selectedStudent?['birthDate'] ?? '-',
                        ),
                        _buildInfoRow(
                          'Doğum Yeri:',
                          _selectedStudent?['birthPlace'] ?? '-',
                        ),
                        _buildInfoRow(
                          'Cinsiyet:',
                          _selectedStudent?['gender'] ?? '-',
                        ),
                        _buildInfoRow(
                          'Uyruk:',
                          _selectedStudent?['nationality'] ?? 'T.C.',
                        ),
                        _buildInfoRow(
                          'Kan Grubu:',
                          _selectedStudent?['bloodType'] ?? '-',
                        ),
                      ],
                    );
                  }
                  // Desktop'ta yan yana
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            _buildInfoRow(
                              'TC:',
                              _selectedStudent?['tcNo'] ?? '-',
                            ),
                            _buildInfoRow(
                              'Doğum Tarihi:',
                              _selectedStudent?['birthDate'] ?? '-',
                            ),
                            _buildInfoRow(
                              'Doğum Yeri:',
                              _selectedStudent?['birthPlace'] ?? '-',
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          children: [
                            _buildInfoRow(
                              'Cinsiyet:',
                              _selectedStudent?['gender'] ?? '-',
                            ),
                            _buildInfoRow(
                              'Uyruk:',
                              _selectedStudent?['nationality'] ?? 'T.C.',
                            ),
                            _buildInfoRow(
                              'Kan Grubu:',
                              _selectedStudent?['bloodType'] ?? '-',
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          SizedBox(height: 16),
          _buildInfoCard(
            title: 'İletişim Bilgileri',
            icon: Icons.contact_phone,
            onTap: () => _showEditDialog('İletişim Bilgileri'),
            children: [
              _buildInfoRow(
                'E-posta (Kurumsal):',
                _selectedStudent?['email'] ?? '-',
              ),
              _buildInfoRow(
                'E-posta (Kişisel):',
                _selectedStudent?['personalEmail'] ?? '-',
              ),
              _buildInfoRow(
                'Telefon (Cep):',
                _selectedStudent?['phone'] ?? '-',
              ),
            ],
          ),
          SizedBox(height: 16),
          _buildInfoCard(
            title: 'Adres Bilgileri',
            icon: Icons.location_on,
            onTap: () => _showEditDialog('Adres Bilgileri'),
            children: [
              _buildInfoRow(
                'İl / İlçe:',
                '${_selectedStudent?['city'] ?? '-'} / ${_selectedStudent?['district'] ?? '-'}',
              ),
              _buildInfoRow('Açık Adres:', _selectedStudent?['address'] ?? '-'),
            ],
          ),
          SizedBox(height: 16),
          _buildInfoCard(
            title: 'Kullanıcı Bilgileri',
            icon: Icons.account_circle,
            onTap: () => _showEditDialog('Kullanıcı Bilgileri'),
            children: [
              _buildInfoRow(
                'Kullanıcı Adı:',
                _selectedStudent?['username'] ?? '-',
              ),
              _buildInfoRow(
                'Şifre:',
                (_selectedStudent?['password'] != null &&
                        (_selectedStudent!['password'].toString().isNotEmpty))
                    ? '******'
                    : 'Şifre Girilmedi',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Okul Bilgileri Tab
  Widget _buildSchoolInfoTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          _buildInfoCard(
            title: 'Kayıt Bilgileri',
            icon: Icons.school,
            onTap: () => _showEditDialog('Kayıt Bilgileri'),
            children: [
              _buildInfoRow(
                'Öğrenci No:',
                _selectedStudent?['studentNo'] ?? '-',
              ),
              _buildInfoRow(
                'Kayıt Tarihi:',
                _selectedStudent?['registrationDate'] ?? '-',
              ),
              _buildInfoRow(
                'Kayıt Türü:',
                _selectedStudent?['registrationType'] ?? '-',
              ),
              _buildInfoRow(
                'Giriş Türü:',
                _selectedStudent?['entryType'] ?? '-',
              ),
            ],
          ),
          SizedBox(height: 16),
          _buildInfoCard(
            title: 'Sınıf Bilgileri',
            icon: Icons.class_,
            onTap: () => _showEditDialog('Sınıf Bilgileri'),
            children: [
              _buildInfoRow(
                'Okul Türü:',
                _getSchoolTypeName(_selectedStudent?['schoolTypeId']) ?? '-',
              ),
              _buildInfoRow(
                'Sınıf Seviyesi:',
                _selectedStudent?['classLevel']?.toString() ?? '-',
              ),
              _buildInfoRow(
                'Şube:',
                _selectedStudent?['className']?.toString() ?? '-',
              ),
              _buildInfoRow(
                'Dönem:',
                _getTermName(_selectedStudent?['termId']) ?? '-',
              ),
            ],
          ),
          SizedBox(height: 16),
          _buildInfoCard(
            title: 'Eğitim Bilgileri',
            icon: Icons.menu_book,
            onTap: () => _showEditDialog('Eğitim Bilgileri'),
            children: [
              _buildInfoRow(
                'Önceki Okul:',
                _selectedStudent?['previousSchool'] ?? '-',
              ),
              _buildInfoRow(
                'Eğitim Türü:',
                _selectedStudent?['educationType'] ?? '-',
              ),
              _buildInfoRow(
                'Yabancı Dil:',
                _selectedStudent?['foreignLanguage'] ?? '-',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Veli Bilgileri Tab
  Widget _buildParentInfoTabNew() {
    final parents = _selectedStudent?['parents'] as List? ?? [];

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          // Veli Ekle Butonu
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.indigo.shade100, width: 2),
            ),
            child: InkWell(
              onTap: () => _showAddParentDialog(),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_circle_outline,
                      color: Colors.indigo,
                      size: 28,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Veli Ekle',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: 16),
          // Veli Kartları
          if (parents.isEmpty)
            Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.family_restroom,
                      size: 64,
                      color: Colors.grey.shade300,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Henüz veli eklenmemiş',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Yukarıdaki butona tıklayarak veli ekleyebilirsiniz',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ...parents.asMap().entries.map((entry) {
              final index = entry.key;
              final parent = entry.value;
              return Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: _buildParentCard(parent, index),
              );
            }),
        ],
      ),
    );
  }

  // Veli Kartı
  Widget _buildParentCard(Map<String, dynamic> parent, int index) {
    final relation = parent['relation'] ?? 'Veli';
    final fullName = parent['fullName'] ?? '-';
    final phone = parent['phone'] ?? '-';
    final email = parent['email'] ?? '-';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Başlık
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.person, color: Colors.white, size: 20),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        relation,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: Colors.grey),
                  onSelected: (value) {
                    if (value == 'edit') {
                      _showEditParentDialog(parent, index);
                    } else if (value == 'delete') {
                      _showDeleteParentDialog(index);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 18),
                          SizedBox(width: 8),
                          Text('Düzenle'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 18, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Sil', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // İçerik
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                _buildInfoRow('TC Kimlik No:', parent['tcNo'] ?? '-'),
                _buildInfoRow('Telefon:', phone),
                _buildInfoRow('E-posta:', email),
                _buildInfoRow('Adres:', parent['address'] ?? '-'),
                _buildInfoRow('Meslek:', parent['occupation'] ?? '-'),
                _buildInfoRow('İş Yeri:', parent['workplace'] ?? '-'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Veli Ekleme Dialogu
  void _showAddParentDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Başlık
              Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.person_add, color: Colors.indigo),
                    SizedBox(width: 8),
                    Text(
                      'Veli Ekle',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Spacer(),
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Divider(height: 1),
              // Seçenekler
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: EdgeInsets.all(16),
                  children: [
                    _buildParentOption(
                      icon: Icons.search,
                      title: 'Mevcut Kullanıcıdan Seç',
                      subtitle: 'Sistemdeki kullanıcılardan veli seçin',
                      onTap: () {
                        Navigator.pop(context);
                        _showSelectExistingParent();
                      },
                    ),
                    SizedBox(height: 12),
                    _buildParentOption(
                      icon: Icons.person,
                      title: 'Öğrencinin Kendisi',
                      subtitle: 'Öğrenci kendi velisi olarak atanır',
                      onTap: () {
                        Navigator.pop(context);
                        _addStudentAsParent();
                      },
                    ),
                    SizedBox(height: 12),
                    _buildParentOption(
                      icon: Icons.add_circle,
                      title: 'Yeni Veli Ekle',
                      subtitle: 'Yeni bir veli kaydı oluşturun',
                      onTap: () {
                        Navigator.pop(context);
                        _showNewParentForm();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParentOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.indigo, size: 28),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  void _showSelectExistingParent() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.search, color: Colors.indigo),
                    SizedBox(width: 8),
                    Text(
                      'Mevcut Kullanıcıdan Veli Seç',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Spacer(),
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Kullanıcı ara (Ad, TC, Telefon)',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              Divider(height: 24),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: EdgeInsets.all(16),
                  children: [
                    Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(
                              Icons.people,
                              size: 64,
                              color: Colors.grey.shade300,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Kullanıcı listesi yakında eklenecek',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addStudentAsParent() {
    if (_selectedStudent == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.person, color: Colors.indigo),
            SizedBox(width: 8),
            Text('Öğrenciyi Veli Olarak Ekle'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Öğrenci kendi velisi olarak eklenecek:'),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.person, color: Colors.indigo),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_selectedStudent?['name'] ?? ''} ${_selectedStudent?['surname'] ?? ''}',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'TC: ${_selectedStudent?['tcNo'] ?? '-'}',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
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
            onPressed: () async {
              if (_selectedStudent == null || _selectedStudentId == null)
                return;

              try {
                // Öğrenci bilgilerini veli olarak hazırla
                final studentAsParent = {
                  'relation': 'Kendisi',
                  'tcNo': _selectedStudent!['tcNo'] ?? '',
                  'name': _selectedStudent!['name'] ?? '',
                  'surname': _selectedStudent!['surname'] ?? '',
                  'fullName':
                      '${_selectedStudent!['name'] ?? ''} ${_selectedStudent!['surname'] ?? ''}',
                  'phone': _selectedStudent!['phone'] ?? '',
                  'email': _selectedStudent!['email'] ?? '',
                  'username': _selectedStudent!['username'] ?? '',
                  'password': _selectedStudent!['password'] ?? '',
                  'address': _selectedStudent!['address'] ?? '',
                  'occupation': 'Öğrenci',
                  'workplace': '-',
                };

                // Mevcut velileri al
                List<dynamic> currentParents = List.from(
                  _selectedStudent!['parents'] ?? [],
                );

                // Öğrenci zaten veli olarak ekli mi kontrol et
                bool alreadyAdded = currentParents.any(
                  (p) =>
                      p['tcNo'] == studentAsParent['tcNo'] &&
                      p['relation'] == 'Kendisi',
                );

                if (alreadyAdded) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('⚠ Öğrenci zaten veli olarak ekli'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                // Veli listesine ekle
                currentParents.add(studentAsParent);

                // Firestore'a kaydet
                await FirebaseFirestore.instance
                    .collection('students')
                    .doc(_selectedStudentId)
                    .update({'parents': currentParents});

                // Local state'i güncelle
                setState(() {
                  _selectedStudent!['parents'] = currentParents;
                });

                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✓ Öğrenci veli olarak eklendi'),
                    backgroundColor: Colors.green,
                  ),
                );

                _loadData(); // Listeyi yenile
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('❌ Hata: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
            child: Text('Ekle', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showNewParentForm() {
    final nameController = TextEditingController();
    final surnameController = TextEditingController();
    final tcController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final addressController = TextEditingController();
    final occupationController = TextEditingController();
    final workplaceController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final prefixController = TextEditingController();
    String? selectedRelation = 'anne';
    String? selectedSmsOption = 'evet';
    bool useSameAddress = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, controller) => Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  margin: EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.person_add, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text(
                        'Yeni Veli Ekle',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Spacer(),
                      IconButton(
                        icon: Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    controller: controller,
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Yakınlık Türü
                        DropdownButtonFormField<String>(
                          value: selectedRelation,
                          decoration: InputDecoration(
                            labelText: 'Yakınlık Türü *',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: Icon(Icons.family_restroom),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'anne',
                              child: Text('Anne'),
                            ),
                            DropdownMenuItem(
                              value: 'baba',
                              child: Text('Baba'),
                            ),
                            DropdownMenuItem(
                              value: 'kardes',
                              child: Text('Kardeş'),
                            ),
                            DropdownMenuItem(
                              value: 'buyukanne',
                              child: Text('Büyükanne'),
                            ),
                            DropdownMenuItem(
                              value: 'buyukbaba',
                              child: Text('Büyükbaba'),
                            ),
                            DropdownMenuItem(
                              value: 'amca',
                              child: Text('Amca'),
                            ),
                            DropdownMenuItem(
                              value: 'dayi',
                              child: Text('Dayı'),
                            ),
                            DropdownMenuItem(
                              value: 'hala',
                              child: Text('Hala'),
                            ),
                            DropdownMenuItem(
                              value: 'teyze',
                              child: Text('Teyze'),
                            ),
                            DropdownMenuItem(
                              value: 'diger',
                              child: Text('Diğer'),
                            ),
                          ],
                          onChanged: (value) {
                            setModalState(() {
                              selectedRelation = value;
                            });
                          },
                        ),
                        SizedBox(height: 16),
                        // TC Kimlik Numarası
                        TextFormField(
                          controller: tcController,
                          decoration: InputDecoration(
                            labelText: 'T.C. Kimlik Numarası',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: Icon(Icons.badge),
                          ),
                          keyboardType: TextInputType.number,
                          maxLength: 11,
                          onChanged: (value) {
                            if (value.length == 11) {
                              setModalState(() {
                                usernameController.text = 'V$value';
                                if (passwordController.text.isEmpty) {
                                  passwordController.text = value.substring(5);
                                }
                              });
                            }
                          },
                        ),
                        SizedBox(height: 16),
                        // Ön ek
                        TextFormField(
                          controller: prefixController,
                          decoration: InputDecoration(
                            labelText: 'Ön ek',
                            hintText: 'Bay, Bayan...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: Icon(Icons.person_pin),
                          ),
                        ),
                        SizedBox(height: 16),
                        // Ad ve Soyad
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: nameController,
                                decoration: InputDecoration(
                                  labelText: 'Ad *',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  prefixIcon: Icon(Icons.person),
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: surnameController,
                                decoration: InputDecoration(
                                  labelText: 'Soyad *',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 16),
                        // E-Posta
                        TextFormField(
                          controller: emailController,
                          decoration: InputDecoration(
                            labelText: 'E-Posta',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: Icon(Icons.email),
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        SizedBox(height: 16),
                        // Mesaj Gönder (Cep Tel)
                        TextFormField(
                          controller: phoneController,
                          decoration: InputDecoration(
                            labelText: 'Mesaj Gönder (Cep Tel)',
                            prefixText: '+90 ',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: Icon(Icons.phone),
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                        SizedBox(height: 16),
                        // Meslek
                        TextFormField(
                          controller: occupationController,
                          decoration: InputDecoration(
                            labelText: 'Meslek',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: Icon(Icons.work),
                          ),
                        ),
                        SizedBox(height: 16),
                        // İş Yeri
                        TextFormField(
                          controller: workplaceController,
                          decoration: InputDecoration(
                            labelText: 'İş Yeri',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: Icon(Icons.business),
                          ),
                        ),
                        SizedBox(height: 16),
                        // Veli SMS Alsın
                        DropdownButtonFormField<String>(
                          value: selectedSmsOption,
                          decoration: InputDecoration(
                            labelText: 'Veli SMS Alsın',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: Icon(Icons.sms),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'evet',
                              child: Text('Evet'),
                            ),
                            DropdownMenuItem(
                              value: 'hayir',
                              child: Text('Hayır'),
                            ),
                          ],
                          onChanged: (value) {
                            setModalState(() {
                              selectedSmsOption = value;
                            });
                          },
                        ),
                        SizedBox(height: 16),
                        // Kullanıcı Adı
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: usernameController,
                                decoration: InputDecoration(
                                  labelText: 'Kullanıcı Adı',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  prefixIcon: Icon(Icons.account_circle),
                                ),
                              ),
                            ),
                            SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () {
                                if (tcController.text.length == 11) {
                                  setModalState(() {
                                    usernameController.text =
                                        'V${tcController.text}';
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '✓ Kullanıcı adı oluşturuldu',
                                      ),
                                      backgroundColor: Colors.green,
                                      duration: Duration(seconds: 1),
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '⚠ Önce TC Kimlik No giriniz',
                                      ),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                }
                              },
                              icon: Icon(Icons.auto_awesome, size: 18),
                              label: Text('Otomatik'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 16),
                        // Şifre
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: passwordController,
                                decoration: InputDecoration(
                                  labelText: 'Şifre',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  prefixIcon: Icon(Icons.lock),
                                ),
                                obscureText: false,
                              ),
                            ),
                            SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () {
                                if (tcController.text.length == 11) {
                                  setModalState(() {
                                    passwordController.text = tcController.text
                                        .substring(5);
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '✓ Şifre oluşturuldu (TC\'nin son 6 hanesi)',
                                      ),
                                      backgroundColor: Colors.green,
                                      duration: Duration(seconds: 1),
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '⚠ Önce TC Kimlik No giriniz',
                                      ),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                }
                              },
                              icon: Icon(Icons.auto_awesome, size: 18),
                              label: Text('Otomatik'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 16),
                        // Öğrenci ile Aynı Adres
                        CheckboxListTile(
                          title: Text('Öğrenci ile Aynı Adres'),
                          value: useSameAddress,
                          onChanged: (value) {
                            setModalState(() {
                              useSameAddress = value ?? false;
                            });
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade200,
                        blurRadius: 4,
                        offset: Offset(0, -2),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () async {
                      if (nameController.text.isEmpty ||
                          surnameController.text.isEmpty ||
                          tcController.text.isEmpty ||
                          phoneController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('⚠ Lütfen zorunlu alanları doldurun'),
                          ),
                        );
                        return;
                      }

                      if (_selectedStudent == null ||
                          _selectedStudentId == null)
                        return;

                      try {
                        final parentData = {
                          'relation': selectedRelation,
                          'tcNo': tcController.text,
                          'prefix': prefixController.text,
                          'name': nameController.text,
                          'surname': surnameController.text,
                          'fullName':
                              '${nameController.text} ${surnameController.text}',
                          'phone': phoneController.text,
                          'email': emailController.text,
                          'occupation': occupationController.text,
                          'workplace': workplaceController.text,
                          'username': usernameController.text,
                          'password': passwordController.text,
                          'smsOption': selectedSmsOption,
                          'useSameAddress': useSameAddress,
                          'address': useSameAddress
                              ? 'Öğrenci ile aynı'
                              : addressController.text,
                        };

                        // Öğrenciye ekle
                        List<dynamic> currentParents = List.from(
                          _selectedStudent!['parents'] ?? [],
                        );
                        currentParents.add(parentData);

                        await FirebaseFirestore.instance
                            .collection('students')
                            .doc(_selectedStudentId)
                            .update({'parents': currentParents});

                        setState(() {
                          _selectedStudent!['parents'] = currentParents;
                        });

                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✓ Veli eklendi'),
                            backgroundColor: Colors.green,
                          ),
                        );

                        _loadData();
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('❌ Hata: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      minimumSize: Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Kaydet',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEditParentDialog(Map<String, dynamic> parent, int index) {
    // KULLANICI İSTEĞİ: Ad Soyad birleşik. FullName varsa onu al, yoksa birleştir.
    final nameController = TextEditingController(
      text:
          parent['fullName'] ??
          '${parent['name'] ?? ''} ${parent['surname'] ?? ''}'.trim(),
    );
    // Soyad controller kalktı
    final tcController = TextEditingController(text: parent['tcNo']);
    final phoneController = TextEditingController(text: parent['phone']);
    final emailController = TextEditingController(text: parent['email']);
    final addressController = TextEditingController(text: parent['address']);
    final occupationController = TextEditingController(
      text: parent['occupation'],
    );
    final workplaceController = TextEditingController(
      text: parent['workplace'],
    );
    final usernameController = TextEditingController(text: parent['username']);
    final passwordController = TextEditingController(text: parent['password']);
    String? selectedRelation = (parent['relation'] ?? '')
        .toString()
        .toLowerCase();
    const validRelations = {
      'anne',
      'baba',
      'kardes',
      'buyukanne',
      'buyukbaba',
      'amca',
      'dayi',
      'hala',
      'teyze',
      'diger',
      'kendisi',
    };
    if (!validRelations.contains(selectedRelation)) {
      selectedRelation = 'diger';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, controller) => Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  margin: EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.edit, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text(
                        'Veli Düzenle',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Spacer(),
                      IconButton(
                        icon: Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    controller: controller,
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Tek Ad Soyad Alanı
                        TextFormField(
                          controller: nameController,
                          decoration: InputDecoration(
                            labelText: 'Ad Soyad (Tam İsim) *',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: Icon(Icons.person),
                          ),
                        ),
                        SizedBox(height: 16),
                        TextFormField(
                          controller: tcController,
                          decoration: InputDecoration(
                            labelText: 'TC Kimlik No *',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: Icon(Icons.badge),
                          ),
                          keyboardType: TextInputType.number,
                          maxLength: 11,
                        ),
                        SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: selectedRelation,
                          decoration: InputDecoration(
                            labelText: 'Yakınlık Derecesi *',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: Icon(Icons.family_restroom),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'anne',
                              child: Text('Anne'),
                            ),
                            DropdownMenuItem(
                              value: 'baba',
                              child: Text('Baba'),
                            ),
                            DropdownMenuItem(
                              value: 'kardes',
                              child: Text('Kardeş'),
                            ),
                            DropdownMenuItem(
                              value: 'buyukanne',
                              child: Text('Büyükanne'),
                            ),
                            DropdownMenuItem(
                              value: 'buyukbaba',
                              child: Text('Büyükbaba'),
                            ),
                            DropdownMenuItem(
                              value: 'amca',
                              child: Text('Amca'),
                            ),
                            DropdownMenuItem(
                              value: 'dayi',
                              child: Text('Dayı'),
                            ),
                            DropdownMenuItem(
                              value: 'hala',
                              child: Text('Hala'),
                            ),
                            DropdownMenuItem(
                              value: 'teyze',
                              child: Text('Teyze'),
                            ),
                            DropdownMenuItem(
                              value: 'diger',
                              child: Text('Diğer'),
                            ),
                            DropdownMenuItem(
                              value: 'kendisi',
                              child: Text('Kendisi'),
                            ),
                          ],
                          onChanged: (value) {
                            setModalState(() {
                              selectedRelation = value;
                            });
                          },
                        ),
                        SizedBox(height: 16),
                        TextFormField(
                          controller: phoneController,
                          decoration: InputDecoration(
                            labelText: 'Telefon *',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: Icon(Icons.phone),
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                        SizedBox(height: 16),
                        TextFormField(
                          controller: emailController,
                          decoration: InputDecoration(
                            labelText: 'E-posta',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: Icon(Icons.email),
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        SizedBox(height: 16),
                        TextFormField(
                          controller: occupationController,
                          decoration: InputDecoration(
                            labelText: 'Meslek',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: Icon(Icons.work),
                          ),
                        ),
                        SizedBox(height: 16),
                        TextFormField(
                          controller: workplaceController,
                          decoration: InputDecoration(
                            labelText: 'İş Yeri',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: Icon(Icons.business),
                          ),
                        ),
                        SizedBox(height: 16),
                        TextFormField(
                          controller: addressController,
                          decoration: InputDecoration(
                            labelText: 'Adres',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: Icon(Icons.home),
                          ),
                          maxLines: 3,
                        ),
                        SizedBox(height: 16),
                        // Kullanıcı Adı
                        TextFormField(
                          controller: usernameController,
                          decoration: InputDecoration(
                            labelText: 'Kullanıcı Adı',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: Icon(Icons.account_circle),
                          ),
                        ),
                        SizedBox(height: 16),
                        // Şifre
                        TextFormField(
                          controller: passwordController,
                          decoration: InputDecoration(
                            labelText: 'Şifre',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: Icon(Icons.lock),
                          ),
                          obscureText: false,
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade200,
                        blurRadius: 4,
                        offset: Offset(0, -2),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () async {
                      if (nameController.text.isEmpty ||
                          tcController.text.isEmpty ||
                          phoneController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('⚠ Lütfen zorunlu alanları doldurun'),
                          ),
                        );
                        return;
                      }

                      if (_selectedStudent == null ||
                          _selectedStudentId == null)
                        return;

                      try {
                        // Güncellenmiş veli bilgileri
                        final updatedParentData = {
                          'relation': selectedRelation,
                          'tcNo': tcController.text,
                          'name': nameController.text,
                          'surname': '', // Tek alan olduğu için soyad boş
                          'fullName': nameController.text,
                          'phone': phoneController.text,
                          'email': emailController.text,
                          'occupation': occupationController.text,
                          'workplace': workplaceController.text,
                          'username': usernameController.text,
                          'password': passwordController.text,
                          'address': addressController.text,
                        };

                        // Veli listesini güncelle
                        List<dynamic> currentParents = List.from(
                          _selectedStudent!['parents'] ?? [],
                        );
                        if (index >= 0 && index < currentParents.length) {
                          currentParents[index] = updatedParentData;

                          // Firestore'a kaydet
                          await FirebaseFirestore.instance
                              .collection('students')
                              .doc(_selectedStudentId)
                              .update({'parents': currentParents});

                          // Local state'i güncelle
                          setState(() {
                            _selectedStudent!['parents'] = currentParents;
                          });

                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✓ Veli güncellendi'),
                              backgroundColor: Colors.green,
                            ),
                          );

                          _loadData(); // Listeyi yenile
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('❌ Hata: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      minimumSize: Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Güncelle',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteParentDialog(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Veli Sil'),
        content: Text('Bu veliyi silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              if (_selectedStudent == null || _selectedStudentId == null)
                return;

              try {
                // Mevcut velileri al
                List<dynamic> currentParents = List.from(
                  _selectedStudent!['parents'] ?? [],
                );

                // İndexteki veliyi sil
                if (index >= 0 && index < currentParents.length) {
                  currentParents.removeAt(index);

                  // Firestore'a kaydet
                  await FirebaseFirestore.instance
                      .collection('students')
                      .doc(_selectedStudentId)
                      .update({'parents': currentParents});

                  // Local state'i güncelle
                  setState(() {
                    _selectedStudent!['parents'] = currentParents;
                  });

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✓ Veli silindi'),
                      backgroundColor: Colors.green,
                    ),
                  );

                  _loadData(); // Listeyi yenile
                }
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('❌ Hata: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // Yeni Öğrenci Ekleme Dialogu
  void _showNewStudentDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _StudentRegistrationFormScreen(
          onSave: () {
            _loadData(); // Listeyi yenile
          },
          isViewingPastTerm: _isViewingPastTerm,
          fixedSchoolTypeId: widget.fixedSchoolTypeId,
        ),
      ),
    );
  }

  // Öğrenci fotoğrafı ve adı
  Widget _buildStudentPhotoAndName() {
    return Row(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.person, size: 40, color: Colors.grey.shade400),
        ),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _selectedStudent?['fullName'] ?? '-',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'ÖĞRENCİ  ${_selectedStudent?['studentNo'] ?? ''} - ${_selectedStudent?['className'] ?? ''}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Bilgi kartı
  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
    VoidCallback? onTap,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: Colors.indigo),
                  SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Spacer(),
                  if (onTap != null)
                    Icon(Icons.edit, size: 18, color: Colors.grey.shade400),
                ],
              ),
              SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  // Düzenleme dialogu - Alttan modal
  Future<void> _showEditDialog(String section) async {
    // Geçici değişkenler - modal içinde kullanılacak
    Map<String, dynamic> tempData = Map<String, dynamic>.from(
      _selectedStudent ?? {},
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
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
          builder: (context, setModalState) {
            Widget formContent;

            switch (section) {
              case 'Genel Bilgiler':
                formContent = _buildGeneralInfoFormEditable(
                  tempData,
                  setModalState,
                );
                break;
              case 'İletişim Bilgileri':
                formContent = _buildContactInfoFormEditable(
                  tempData,
                  setModalState,
                );
                break;
              case 'Adres Bilgileri':
                formContent = _buildAddressInfoFormEditable(
                  tempData,
                  setModalState,
                );
                break;
              case 'Kullanıcı Bilgileri':
                formContent = _buildUserInfoFormEditable(
                  tempData,
                  setModalState,
                );
                break;
              case 'Kayıt Bilgileri':
                formContent = _buildRegistrationInfoFormEditable(
                  tempData,
                  setModalState,
                );
                break;
              case 'Sınıf Bilgileri':
                formContent = _buildClassInfoFormEditable(
                  tempData,
                  setModalState,
                );
                break;
              case 'Eğitim Bilgileri':
                formContent = _buildEducationInfoFormEditable(
                  tempData,
                  setModalState,
                );
                break;
              default:
                formContent = Center(child: Text('Form bulunamadı'));
            }

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Başlık
                  Row(
                    children: [
                      Icon(Icons.edit, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text(
                        '$section Düzenle',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Spacer(),
                      IconButton(
                        icon: Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  // İçerik
                  formContent,
                  SizedBox(height: 16),
                  // Kaydet butonu
                  ElevatedButton(
                    onPressed: () async {
                      // Kullanıcı Bilgileri için şifre kontrolü
                      if (section == 'Kullanıcı Bilgileri') {
                        final password = tempData['password']?.toString() ?? '';
                        if (password.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '❌ Şifre girilmeden kayıt yapılamaz',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                      }

                      // Veritabanına kaydet
                      if (_selectedStudentId != null) {
                        try {
                          await FirebaseFirestore.instance
                              .collection('students')
                              .doc(_selectedStudentId)
                              .update(tempData);

                          setState(() {
                            _selectedStudent = tempData;
                          });

                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✓ $section kaydedildi'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          _loadData(); // Listeyi yenile
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('❌ Hata: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      minimumSize: Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Kaydet',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // Genel Bilgiler Formu - Düzenlenebilir
  Widget _buildGeneralInfoFormEditable(
    Map<String, dynamic> tempData,
    StateSetter setModalState,
  ) {
    return Column(
      children: [
        TextFormField(
          key: ValueKey('firstName_${tempData['firstName']}'),
          initialValue: tempData['firstName'] ?? '',
          decoration: InputDecoration(
            labelText: 'Ad *',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.person),
          ),
          textCapitalization: TextCapitalization.words,
          onChanged: (value) {
            setModalState(() {
              tempData['firstName'] = value;
              // fullName'i güncelle
              tempData['fullName'] =
                  '${value.trim()} ${(tempData['lastName'] ?? '').trim()}'
                      .trim();
            });
          },
        ),
        SizedBox(height: 16),
        TextFormField(
          key: ValueKey('lastName_${tempData['lastName']}'),
          initialValue: tempData['lastName'] ?? '',
          decoration: InputDecoration(
            labelText: 'Soyad *',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.person),
          ),
          textCapitalization: TextCapitalization.words,
          onChanged: (value) {
            setModalState(() {
              tempData['lastName'] = value;
              // fullName'i güncelle
              tempData['fullName'] =
                  '${(tempData['firstName'] ?? '').trim()} ${value.trim()}'
                      .trim();
            });
          },
        ),
        SizedBox(height: 16),
        TextFormField(
          initialValue: tempData['tcNo'],
          decoration: InputDecoration(
            labelText: 'TC Kimlik No',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.badge),
          ),
          keyboardType: TextInputType.number,
          maxLength: 11,
          onChanged: (value) {
            setModalState(() {
              tempData['tcNo'] = value;
            });
          },
        ),
        SizedBox(height: 16),
        TextFormField(
          initialValue: tempData['birthDate'],
          decoration: InputDecoration(
            labelText: 'Doğum Tarihi (gg.aa.yyyy)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.calendar_today),
          ),
          inputFormatters: [DateTextFormatter()],
          keyboardType: TextInputType.number,
          onChanged: (value) {
            setModalState(() {
              tempData['birthDate'] = value;
            });
          },
        ),
        SizedBox(height: 16),
        TextFormField(
          initialValue: tempData['birthPlace'],
          decoration: InputDecoration(
            labelText: 'Doğum Yeri',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.location_city),
          ),
          onChanged: (value) {
            setModalState(() {
              tempData['birthPlace'] = value;
            });
          },
        ),
        SizedBox(height: 16),
        DropdownButtonFormField<String?>(
          value: ['Erkek', 'Kadın'].contains(tempData['gender'])
              ? tempData['gender']
              : null,
          decoration: InputDecoration(
            labelText: 'Cinsiyet',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.person),
          ),
          items: [
            DropdownMenuItem(value: 'Erkek', child: Text('Erkek')),
            DropdownMenuItem(value: 'Kadın', child: Text('Kadın')),
          ],
          onChanged: (value) {
            setModalState(() {
              tempData['gender'] = value;
            });
          },
        ),
        SizedBox(height: 16),
        TextFormField(
          initialValue: tempData['nationality'] ?? 'T.C.',
          decoration: InputDecoration(
            labelText: 'Uyruk',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.flag),
          ),
          onChanged: (value) {
            setModalState(() {
              tempData['nationality'] = value;
            });
          },
        ),
        SizedBox(height: 16),
        DropdownButtonFormField<String?>(
          value:
              [
                'A+',
                'A-',
                'B+',
                'B-',
                'AB+',
                'AB-',
                '0+',
                '0-',
              ].contains(tempData['bloodType'])
              ? tempData['bloodType']
              : null,
          decoration: InputDecoration(
            labelText: 'Kan Grubu',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.bloodtype),
          ),
          items: [
            DropdownMenuItem(value: 'A+', child: Text('A+')),
            DropdownMenuItem(value: 'A-', child: Text('A-')),
            DropdownMenuItem(value: 'B+', child: Text('B+')),
            DropdownMenuItem(value: 'B-', child: Text('B-')),
            DropdownMenuItem(value: 'AB+', child: Text('AB+')),
            DropdownMenuItem(value: 'AB-', child: Text('AB-')),
            DropdownMenuItem(value: '0+', child: Text('0+')),
            DropdownMenuItem(value: '0-', child: Text('0-')),
          ],
          onChanged: (value) {
            setModalState(() {
              tempData['bloodType'] = value;
            });
          },
        ),
      ],
    );
  }

  // İletişim Bilgileri Formu - Düzenlenebilir
  Widget _buildContactInfoFormEditable(
    Map<String, dynamic> tempData,
    StateSetter setModalState,
  ) {
    return Column(
      children: [
        TextFormField(
          initialValue: tempData['email'],
          decoration: InputDecoration(
            labelText: 'E-posta (Kurumsal)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.email),
          ),
          keyboardType: TextInputType.emailAddress,
          onChanged: (value) {
            setModalState(() {
              tempData['email'] = value;
            });
          },
        ),
        SizedBox(height: 16),
        TextFormField(
          initialValue: tempData['personalEmail'],
          decoration: InputDecoration(
            labelText: 'E-posta (Kişisel)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.email_outlined),
          ),
          keyboardType: TextInputType.emailAddress,
          onChanged: (value) {
            setModalState(() {
              tempData['personalEmail'] = value;
            });
          },
        ),
        SizedBox(height: 16),
        TextFormField(
          initialValue: tempData['phone'],
          decoration: InputDecoration(
            labelText: 'Telefon (Cep)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.phone),
          ),
          keyboardType: TextInputType.phone,
          onChanged: (value) {
            setModalState(() {
              tempData['phone'] = value;
            });
          },
        ),
      ],
    );
  }

  // Adres Bilgileri Formu - Düzenlenebilir
  Widget _buildAddressInfoFormEditable(
    Map<String, dynamic> tempData,
    StateSetter setModalState,
  ) {
    return Column(
      children: [
        DropdownButtonFormField<String?>(
          value: ['İstanbul', 'Ankara', 'İzmir'].contains(tempData['city'])
              ? tempData['city']
              : null,
          decoration: InputDecoration(
            labelText: 'İl',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.location_city),
          ),
          items: [
            DropdownMenuItem(value: 'İstanbul', child: Text('İstanbul')),
            DropdownMenuItem(value: 'Ankara', child: Text('Ankara')),
            DropdownMenuItem(value: 'İzmir', child: Text('İzmir')),
            // Diğer iller...
          ],
          onChanged: (value) {
            setModalState(() {
              tempData['city'] = value;
            });
          },
        ),
        SizedBox(height: 16),
        DropdownButtonFormField<String?>(
          value: ['Kadıköy', 'Beşiktaş'].contains(tempData['district'])
              ? tempData['district']
              : null,
          decoration: InputDecoration(
            labelText: 'İlçe',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.location_on),
          ),
          items: [
            DropdownMenuItem(value: 'Kadıköy', child: Text('Kadıköy')),
            DropdownMenuItem(value: 'Beşiktaş', child: Text('Beşiktaş')),
            // Diğer ilçeler...
          ],
          onChanged: (value) {
            setModalState(() {
              tempData['district'] = value;
            });
          },
        ),
        SizedBox(height: 16),
        TextFormField(
          initialValue: tempData['address'],
          decoration: InputDecoration(
            labelText: 'Açık Adres',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.home),
          ),
          maxLines: 3,
          onChanged: (value) {
            setModalState(() {
              tempData['address'] = value;
            });
          },
        ),
      ],
    );
  }

  // Kullanıcı Bilgileri Formu - Düzenlenebilir
  Widget _buildUserInfoFormEditable(
    Map<String, dynamic> tempData,
    StateSetter setModalState,
  ) {
    final usernameController = TextEditingController(
      text: tempData['username'],
    );
    final passwordController = TextEditingController(
      text: tempData['password'],
    );

    return Column(
      children: [
        // Kullanıcı Adı
        TextFormField(
          controller: usernameController,
          decoration: InputDecoration(
            labelText: 'Kullanıcı Adı',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.person_outline),
            suffixIcon: IconButton(
              icon: Icon(Icons.auto_awesome, color: Colors.indigo),
              tooltip: 'TC\'nin İlk 6 Hanesi',
              onPressed: () {
                final tcNo = tempData['tcNo']?.toString() ?? '';
                if (tcNo.length >= 6) {
                  final autoCredential = tcNo.substring(0, 6);
                  final currentPassword =
                      tempData['password']?.toString() ?? '';

                  setModalState(() {
                    // Kullanıcı adını her zaman güncelle
                    usernameController.text = autoCredential;
                    tempData['username'] = autoCredential;

                    // Şifre yoksa otomatik oluştur
                    if (currentPassword.isEmpty) {
                      passwordController.text = autoCredential;
                      tempData['password'] = autoCredential;
                    }
                  });

                  String message = currentPassword.isEmpty
                      ? '✓ Kullanıcı adı ve şifre otomatik oluşturuldu'
                      : '✓ Kullanıcı adı otomatik oluşturuldu';

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(message),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ Önce TC Kimlik No girilmeli'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ),
          onChanged: (value) {
            setModalState(() {
              tempData['username'] = value;
            });
          },
        ),
        SizedBox(height: 16),
        // Şifre
        TextFormField(
          controller: passwordController,
          decoration: InputDecoration(
            labelText: 'Şifre *',
            hintText: 'Şifre zorunludur',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.lock_outline),
          ),
          obscureText: true,
          onChanged: (value) {
            setModalState(() {
              tempData['password'] = value;
            });
          },
        ),
        SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '* Şifre girilmeden kayıt yapılamaz',
            style: TextStyle(
              fontSize: 12,
              color: Colors.red.shade700,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }

  // Kayıt Bilgileri Formu - Düzenlenebilir
  Widget _buildRegistrationInfoFormEditable(
    Map<String, dynamic> tempData,
    StateSetter setModalState,
  ) {
    final studentNoController = TextEditingController(
      text: tempData['studentNo'],
    );
    final registrationDateController = TextEditingController(
      text: tempData['registrationDate'],
    );

    return Column(
      children: [
        // Öğrenci No
        TextFormField(
          controller: studentNoController,
          decoration: InputDecoration(
            labelText: 'Öğrenci No',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.numbers),
            suffixIcon: IconButton(
              icon: Icon(Icons.auto_awesome, color: Colors.indigo),
              tooltip: 'Otomatik Numara',
              onPressed: () async {
                // Sıradaki numarayı al
                final snapshot = await FirebaseFirestore.instance
                    .collection('students')
                    .orderBy('studentNo', descending: true)
                    .limit(1)
                    .get();

                String nextNo = '1001';
                if (snapshot.docs.isNotEmpty) {
                  final lastNo =
                      snapshot.docs.first.data()['studentNo']?.toString() ??
                      '1000';
                  final numPart = int.tryParse(lastNo) ?? 1000;
                  nextNo = (numPart + 1).toString();
                }

                setModalState(() {
                  studentNoController.text = nextNo;
                  tempData['studentNo'] = nextNo;
                  tempData['studentNumber'] = nextNo;
                });
              },
            ),
          ),
          onChanged: (value) {
            setModalState(() {
              tempData['studentNo'] = value;
              tempData['studentNumber'] = value;
            });
          },
        ),
        SizedBox(height: 16),
        // Kayıt Tarihi
        TextFormField(
          controller: registrationDateController,
          decoration: InputDecoration(
            labelText: 'Kayıt Tarihi (gg.aa.yyyy)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.calendar_today),
            suffixIcon: IconButton(
              icon: Icon(Icons.today, color: Colors.indigo),
              tooltip: 'Bugün',
              onPressed: () {
                final now = DateTime.now();
                final formatted =
                    '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
                setModalState(() {
                  registrationDateController.text = formatted;
                  tempData['registrationDate'] = formatted;
                });
              },
            ),
          ),
          inputFormatters: [DateTextFormatter()],
          keyboardType: TextInputType.number,
          onChanged: (value) {
            setModalState(() {
              tempData['registrationDate'] = value;
            });
          },
        ),
        SizedBox(height: 16),
        // Kayıt Türü
        DropdownButtonFormField<String?>(
          value:
              [
                'Asil Kayıt',
                'Yedek Kayıt',
                'Misafir Kayıt',
                'Demo Kayıt',
              ].contains(tempData['registrationType'])
              ? tempData['registrationType']
              : null,
          decoration: InputDecoration(
            labelText: 'Kayıt Türü',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.category),
          ),
          items: [
            DropdownMenuItem(value: 'Asil Kayıt', child: Text('Asil Kayıt')),
            DropdownMenuItem(value: 'Yedek Kayıt', child: Text('Yedek Kayıt')),
            DropdownMenuItem(
              value: 'Misafir Kayıt',
              child: Text('Misafir Kayıt'),
            ),
            DropdownMenuItem(value: 'Demo Kayıt', child: Text('Demo Kayıt')),
          ],
          onChanged: (value) {
            setModalState(() {
              tempData['registrationType'] = value;
            });
          },
        ),
        SizedBox(height: 16),
        // Giriş Türü
        DropdownButtonFormField<String?>(
          value: ['Yeni', 'Yenileme'].contains(tempData['entryType'])
              ? tempData['entryType']
              : null,
          decoration: InputDecoration(
            labelText: 'Giriş Türü',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.input),
          ),
          items: [
            DropdownMenuItem(value: 'Yeni', child: Text('Yeni Kayıt')),
            DropdownMenuItem(value: 'Yenileme', child: Text('Kayıt Yenileme')),
          ],
          onChanged: (value) {
            setModalState(() {
              tempData['entryType'] = value;
            });
          },
        ),
      ],
    );
  }

  // Sınıf Bilgileri Formu - Düzenlenebilir
  Widget _buildClassInfoFormEditable(
    Map<String, dynamic> tempData,
    StateSetter setModalState,
  ) {
    // Seçili okul türüne göre sınıf seviyeleri
    List<DropdownMenuItem<String?>> getClassLevelsForSchoolType(
      String? schoolTypeId,
    ) {
      if (schoolTypeId == null) return [];

      final schoolType = _schoolTypes.firstWhere(
        (type) => type['id'] == schoolTypeId,
        orElse: () => {},
      );

      final typeName =
          (schoolType['schoolTypeName'] ?? schoolType['typeName'] ?? '')
              .toString()
              .toLowerCase();

      if (typeName.contains('anaokul') || typeName.contains('kreş')) {
        return [
          DropdownMenuItem(value: 'Kreş', child: Text('Kreş')),
          DropdownMenuItem(value: 'Anaokulu', child: Text('Anaokulu')),
        ];
      } else if (typeName.contains('ilkokul')) {
        return [
          DropdownMenuItem(value: '1', child: Text('1. Sınıf')),
          DropdownMenuItem(value: '2', child: Text('2. Sınıf')),
          DropdownMenuItem(value: '3', child: Text('3. Sınıf')),
          DropdownMenuItem(value: '4', child: Text('4. Sınıf')),
        ];
      } else if (typeName.contains('ortaokul')) {
        return [
          DropdownMenuItem(value: '5', child: Text('5. Sınıf')),
          DropdownMenuItem(value: '6', child: Text('6. Sınıf')),
          DropdownMenuItem(value: '7', child: Text('7. Sınıf')),
          DropdownMenuItem(value: '8', child: Text('8. Sınıf')),
        ];
      } else if (typeName.contains('lise')) {
        return [
          DropdownMenuItem(value: '9', child: Text('9. Sınıf')),
          DropdownMenuItem(value: '10', child: Text('10. Sınıf')),
          DropdownMenuItem(value: '11', child: Text('11. Sınıf')),
          DropdownMenuItem(value: '12', child: Text('12. Sınıf')),
        ];
      }

      return _getClassLevelFilterItems();
    }

    return Column(
      children: [
        DropdownButtonFormField<String?>(
          value:
              _schoolTypes.any((type) => type['id'] == tempData['schoolTypeId'])
              ? tempData['schoolTypeId']
              : null,
          decoration: InputDecoration(
            labelText: 'Okul Türü',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.school),
          ),
          items: _schoolTypes
              .map(
                (type) => DropdownMenuItem<String?>(
                  value: type['id'] as String?,
                  child: Text(type['schoolTypeName'] ?? type['typeName'] ?? ''),
                ),
              )
              .toList(),
          onChanged: (value) {
            setModalState(() {
              tempData['schoolTypeId'] = value;
              // Okul türü değişince sınıf seviyesini sıfırla
              tempData['classLevel'] = null;
            });
          },
        ),
        SizedBox(height: 16),
        // Sınıf Seviyesi - Sadece okul türü seçiliyse göster
        if (tempData['schoolTypeId'] != null)
          DropdownButtonFormField<String?>(
            value:
                getClassLevelsForSchoolType(tempData['schoolTypeId']).any(
                  (item) => item.value == tempData['classLevel']?.toString(),
                )
                ? tempData['classLevel']?.toString()
                : null,
            decoration: InputDecoration(
              labelText: 'Sınıf Seviyesi',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              prefixIcon: Icon(Icons.class_),
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text('Bir Sınıf Seçin'),
              ),
              ...getClassLevelsForSchoolType(tempData['schoolTypeId']),
            ],
            onChanged: (value) {
              setModalState(() {
                tempData['classLevel'] = value;
                // Sınıf seviyesi değişince şubeyi sıfırla
                tempData['classId'] = null;
                tempData['className'] = null;
              });
            },
          ),
        if (tempData['schoolTypeId'] != null) SizedBox(height: 16),
        // Şube - Sadece okul türü ve sınıf seviyesi seçiliyse göster
        if (tempData['schoolTypeId'] != null && tempData['classLevel'] != null)
          FutureBuilder<List<Map<String, dynamic>>>(
            future: FirebaseFirestore.instance
                .collection('classes')
                .where('schoolTypeId', isEqualTo: tempData['schoolTypeId'])
                .where(
                  'classLevel',
                  isEqualTo:
                      int.tryParse(tempData['classLevel']?.toString() ?? '0') ??
                      0,
                )
                .where('isActive', isEqualTo: true)
                .where('classTypeName', isEqualTo: 'Ders Sınıfı')
                .get()
                .then((snapshot) {
                  final docs = snapshot.docs.map((doc) {
                    final data = doc.data();
                    data['id'] = doc.id;
                    return data;
                  }).toList();
                  docs.sort(
                    (a, b) =>
                        (a['className'] ?? '').compareTo(b['className'] ?? ''),
                  );
                  return docs;
                }),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: 'Şube',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: Icon(Icons.group),
                  ),
                  items: [],
                  onChanged: null,
                  hint: Text('Yükleniyor...'),
                );
              }

              final classes = snapshot.data ?? [];

              return DropdownButtonFormField<String?>(
                value: classes.any((c) => c['id'] == tempData['classId'])
                    ? tempData['classId']
                    : null,
                decoration: InputDecoration(
                  labelText: 'Şube',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: Icon(Icons.group),
                ),
                hint: Text('Şube seçiniz'),
                items: classes.isEmpty
                    ? [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Bir Şube Seçin'),
                        ),
                      ]
                    : [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Bir Şube Seçin'),
                        ),
                        ...classes.map((classItem) {
                          return DropdownMenuItem<String?>(
                            value: classItem['id'],
                            child: Text(
                              '${classItem['className']} - ${classItem['classTypeName']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                      ],
                onChanged: (value) {
                  setModalState(() {
                    tempData['classId'] = value;
                    if (value != null) {
                      final selectedClass = classes.firstWhere(
                        (c) => c['id'] == value,
                        orElse: () => {},
                      );
                      tempData['className'] = selectedClass['className'];
                    } else {
                      tempData['className'] = null;
                    }
                  });
                },
              );
            },
          ),
        if (tempData['schoolTypeId'] != null && tempData['classLevel'] != null)
          SizedBox(height: 16),
        DropdownButtonFormField<String?>(
          value: _terms.any((term) => term['id'] == tempData['termId'])
              ? tempData['termId']
              : null,
          decoration: InputDecoration(
            labelText: 'Dönem',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.event),
          ),
          items: _terms
              .map(
                (term) => DropdownMenuItem<String?>(
                  value: term['id'] as String?,
                  child: Text(term['name'] ?? ''),
                ),
              )
              .toList(),
          onChanged: (value) {
            setModalState(() {
              tempData['termId'] = value;
            });
          },
        ),
      ],
    );
  }

  // Eğitim Bilgileri Formu - Düzenlenebilir
  Widget _buildEducationInfoFormEditable(
    Map<String, dynamic> tempData,
    StateSetter setModalState,
  ) {
    return Column(
      children: [
        TextFormField(
          initialValue: tempData['previousSchool'],
          decoration: InputDecoration(
            labelText: 'Önceki Okul',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.school_outlined),
          ),
          onChanged: (value) {
            setModalState(() {
              tempData['previousSchool'] = value;
            });
          },
        ),
        SizedBox(height: 16),
        DropdownButtonFormField<String?>(
          value: ['Örgün', 'Açık'].contains(tempData['educationType'])
              ? tempData['educationType']
              : null,
          decoration: InputDecoration(
            labelText: 'Eğitim Türü',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.menu_book),
          ),
          items: [
            DropdownMenuItem(value: 'Örgün', child: Text('Örgün')),
            DropdownMenuItem(value: 'Açık', child: Text('Açık')),
          ],
          onChanged: (value) {
            setModalState(() {
              tempData['educationType'] = value;
            });
          },
        ),
        SizedBox(height: 16),
        TextFormField(
          initialValue: tempData['foreignLanguage'],
          decoration: InputDecoration(
            labelText: 'Yabancı Dil',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: Icon(Icons.language),
          ),
          onChanged: (value) {
            setModalState(() {
              tempData['foreignLanguage'] = value;
            });
          },
        ),
      ],
    );
  }

  // Okul türü ismini ID'den bul
  String? _getSchoolTypeName(String? schoolTypeId) {
    if (schoolTypeId == null) return null;
    final schoolType = _schoolTypes.firstWhere(
      (type) => type['id'] == schoolTypeId,
      orElse: () => {},
    );
    return schoolType['schoolTypeName'] ?? schoolType['typeName'];
  }

  // Dönem ismini ID'den bul
  String? _getTermName(String? termId) {
    if (termId == null) return null;
    final term = _terms.firstWhere((t) => t['id'] == termId, orElse: () => {});
    return term['name'];
  }

  // Bilgi satırı
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

// Ayrı sayfa olarak form ekranı
class _StudentRegistrationFormScreen extends StatefulWidget {
  final VoidCallback onSave;
  final Map<String, dynamic>? existingStudent; // Düzenlenecek öğrenci
  final bool isViewingPastTerm; // Geçmiş dönem görüntüleniyor mu?
  final String? fixedSchoolTypeId; // Sabit okul türü ID'si

  const _StudentRegistrationFormScreen({
    Key? key,
    required this.onSave,
    this.existingStudent,
    this.isViewingPastTerm = false,
    this.fixedSchoolTypeId,
  }) : super(key: key);

  @override
  __StudentRegistrationFormScreenState createState() =>
      __StudentRegistrationFormScreenState();
}

class __StudentRegistrationFormScreenState
    extends State<_StudentRegistrationFormScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;

  // Form controllers ve değişkenler
  final TextEditingController _studentNoController = TextEditingController();
  final TextEditingController _tcController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _surnameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _birthDateController = TextEditingController();
  final TextEditingController _registrationDateController =
      TextEditingController();
  final TextEditingController _previousSchoolController =
      TextEditingController();
  String? _selectedSchoolTypeId;
  String? _selectedClassLevel;
  String? _selectedClassId; // Sınıf ID'si
  String? _selectedClassName; // Sınıf adı (gösterim için)
  String? _selectedTermId; // Seçilen dönem
  String? _photoPath;
  String? _institutionId;
  List<Map<String, dynamic>> _schoolTypes = [];
  List<Map<String, dynamic>> _terms = []; // Dönemler listesi
  Map<String, dynamic>? _activeTerm; // Aktif dönem
  List<Map<String, dynamic>> _parents = []; // Kayıtlı veliler
  final TextEditingController _parentTcController = TextEditingController();
  final TextEditingController _parentNameController = TextEditingController();
  final TextEditingController _parentSurnameController =
      TextEditingController();
  final TextEditingController _parentPhoneController = TextEditingController();
  final TextEditingController _parentEmailController = TextEditingController();
  final TextEditingController _parentAddressController =
      TextEditingController();
  final TextEditingController _parentUsernameController =
      TextEditingController();
  final TextEditingController _parentPasswordController =
      TextEditingController();
  String? _selectedParentRelation;
  String? _selectedRegistrationType;

  String? _selectedEntryType;
  String? _selectedGender;
  final TextEditingController _emailController = TextEditingController();
  String? _selectedHearSource;
  String? _selectedEducationType;
  String? _selectedForeignLanguage;
  final TextEditingController _referenceController = TextEditingController();
  bool _isStudentSelfGuardian = false;
  String? _selectedSubTermId;
  bool _useSameAddress = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController?.addListener(() {
      setState(() {});
    });
    _loadSchoolTypes();
  }

  Future<void> _loadSchoolTypes() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final email = user.email!;
      final institutionId = email.split('@')[1].split('.')[0].toUpperCase();

      final schoolTypesQuery = await FirebaseFirestore.instance
          .collection('schoolTypes')
          .where('institutionId', isEqualTo: institutionId)
          .get();

      // Dönemleri yükle
      final termsQuery = await FirebaseFirestore.instance
          .collection('terms')
          .where('institutionId', isEqualTo: institutionId)
          .get();

      final termsList = termsQuery.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      // Kod içinde sıralama yap
      termsList.sort((a, b) {
        final aYear = a['startYear'] ?? 0;
        final bYear = b['startYear'] ?? 0;
        return bYear.compareTo(aYear); // descending
      });

      // Aktif dönemi bul
      Map<String, dynamic>? activeTermData;
      final activeTerms = termsList.where((term) => term['isActive'] == true);
      if (activeTerms.isNotEmpty) {
        activeTermData = activeTerms.first;
      }

      setState(() {
        _institutionId = institutionId;
        _schoolTypes = schoolTypesQuery.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();

        _terms = termsList;

        _activeTerm = activeTermData;
        // Aktif dönemi otomatik seç
        if (_activeTerm != null) {
          _selectedTermId = _activeTerm!['id'];
        }

        // Debug: Okul türlerini kontrol et
        print('📚 [Ayrı Sayfa] Yüklenen okul sayısı: ${_schoolTypes.length}');
        for (var st in _schoolTypes) {
          print(
            '  - ${st['schoolTypeName'] ?? st['typeName']} (Tür: ${st['schoolType']})',
          );
        }

        // Sabit okul türü varsa otomatik seç
        if (widget.fixedSchoolTypeId != null) {
          _selectedSchoolTypeId = widget.fixedSchoolTypeId;
        }

        // Düzenleme modu: Mevcut öğrenci verilerini yükle
        if (widget.existingStudent != null) {
          _loadExistingStudentData(widget.existingStudent!);
        }
      });
    } catch (e) {
      print('❌ Okul türleri yüklenemedi: $e');
    }
  }

  void _loadExistingStudentData(Map<String, dynamic> student) {
    _studentNoController.text =
        student['studentNo'] ?? student['studentNumber'] ?? '';
    _tcController.text = student['tcNo'] ?? '';
    _selectedRegistrationType = student['registrationType'];
    _selectedEntryType = student['entryType'];
    _nameController.text = student['name'] ?? '';
    _surnameController.text = student['surname'] ?? '';
    _phoneController.text = student['phone'] ?? '';
    _usernameController.text = student['username'] ?? '';
    _passwordController.text = student['password'] ?? '';
    _birthDateController.text = student['birthDate'] ?? '';
    _registrationDateController.text = student['registrationDate'] ?? '';
    _registrationDateController.text = student['registrationDate'] ?? '';
    _previousSchoolController.text = student['previousSchool'] ?? '';
    _selectedGender = student['gender'];
    _emailController.text = student['email'] ?? '';
    _selectedHearSource = student['hearSource'];
    _selectedEducationType = student['educationType'];
    _selectedForeignLanguage = student['foreignLanguage'];
    _referenceController.text = student['reference'] ?? '';

    _selectedSchoolTypeId = student['schoolTypeId'];
    _selectedClassLevel = student['classLevel'];
    _selectedClassId = student['classId'];
    _selectedClassName = student['className'];
    _selectedTermId = student['termId'];

    // Velileri yükle
    if (student['parents'] != null) {
      _parents = List<Map<String, dynamic>>.from(student['parents']);
    }

    print('✅ Öğrenci verileri forma yüklendi: ${student['fullName']}');
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _studentNoController.dispose();
    _tcController.dispose();
    _nameController.dispose();
    _surnameController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _birthDateController.dispose();
    _registrationDateController.dispose();
    _parentTcController.dispose();
    _parentNameController.dispose();
    _parentSurnameController.dispose();
    _parentPhoneController.dispose();
    _parentEmailController.dispose();
    _parentAddressController.dispose();
    _parentUsernameController.dispose();
    _parentPasswordController.dispose();
    _emailController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  String _formatBirthDate(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 2) return digits;
    if (digits.length <= 4)
      return '${digits.substring(0, 2)}/${digits.substring(2)}';
    if (digits.length <= 8)
      return '${digits.substring(0, 2)}/${digits.substring(2, 4)}/${digits.substring(4)}';
    return '${digits.substring(0, 2)}/${digits.substring(2, 4)}/${digits.substring(4, 8)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: Icon(Icons.close, color: Colors.grey.shade700),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.existingStudent != null
              ? 'Öğrenci Düzenle'
              : 'Yeni Öğrenci Kaydı',
          style: TextStyle(
            color: Colors.grey.shade900,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Padding(
            padding: EdgeInsets.all(8),
            child: ElevatedButton.icon(
              icon: Icon(Icons.save, size: 18),
              label: Text('Kaydet'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                elevation: 2,
              ),
              onPressed: () async {
                // Validasyon: Zorunlu alanlar kontrol
                if (_tcController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('⚠ TC Kimlik Numarası zorunlu'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                if (_usernameController.text.isEmpty ||
                    _passwordController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('⚠ Kullanıcı adı ve şifre zorunlu'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                if (_selectedSchoolTypeId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('⚠ Okul seçimi zorunlu'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                if (_studentNoController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('⚠ Öğrenci numarası zorunlu'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                // TC tekrar kontrolü (düzenleme modunda kendi kaydını hariç tut)
                final tcQuery = FirebaseFirestore.instance
                    .collection('students')
                    .where('institutionId', isEqualTo: _institutionId)
                    .where('tcNo', isEqualTo: _tcController.text)
                    .limit(2);

                final tcExists = await tcQuery.get();
                final existingId = widget.existingStudent?['id'];

                // Eğer düzenleme modunda ve bulunan kayıt kendi kaydı değilse hata ver
                if (tcExists.docs.isNotEmpty) {
                  final otherStudent = tcExists.docs.firstWhere(
                    (doc) => doc.id != existingId,
                    orElse: () => tcExists.docs.first,
                  );

                  if (otherStudent.id != existingId) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '⚠ Bu TC Kimlik Numarası ile kayıtlı başka öğrenci var',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                }

                // Kullanıcı adı tekrar kontrolü (düzenleme modunda kendi kaydını hariç tut)
                final usernameQuery = FirebaseFirestore.instance
                    .collection('students')
                    .where('institutionId', isEqualTo: _institutionId)
                    .where('username', isEqualTo: _usernameController.text)
                    .limit(2);

                final usernameExists = await usernameQuery.get();

                if (usernameExists.docs.isNotEmpty) {
                  final otherStudent = usernameExists.docs.firstWhere(
                    (doc) => doc.id != existingId,
                    orElse: () => usernameExists.docs.first,
                  );

                  if (otherStudent.id != existingId) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '⚠ Bu kullanıcı adı zaten başka öğrenci tarafından kullanılıyor',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                }

                // Eğer "Veli Öğrencinin Kendisi" seçiliyse, öğrenci bilgilerini veli olarak ekle
                List<Map<String, dynamic>> parentsToSave = List.from(_parents);
                if (_isStudentSelfGuardian) {
                  parentsToSave.add({
                    'name': 'Öğrencinin Kendisi',
                    'tcNo': _tcController.text,
                    'phone': _phoneController.text,
                    'relation': 'Kendisi',
                    'isSelf': true,
                  });
                }

                try {
                  final studentData = {
                    'institutionId': _institutionId,
                    'schoolTypeId': _selectedSchoolTypeId,
                    'studentNo': _studentNoController.text,
                    'studentNumber': _studentNoController.text,
                    'name': _nameController.text,
                    'surname': _surnameController.text,
                    'fullName':
                        '${_nameController.text} ${_surnameController.text}',
                    'classLevel': _selectedClassLevel,
                    'classId': _selectedClassId,
                    'className': _selectedClassName,
                    'termId': _selectedTermId,
                    'subTermId': _selectedSubTermId,
                    'tcNo': _tcController.text,
                    'phone': _phoneController.text,
                    'username': _usernameController.text,
                    'password':
                        _passwordController.text, // TODO: Hash yapılmalı
                    'birthDate': _birthDateController.text,
                    'registrationDate': _registrationDateController.text,
                    'previousSchool': _previousSchoolController.text,
                    'isSelfGuardian': _isStudentSelfGuardian,
                    'registrationType': _selectedRegistrationType,
                    'entryType': _selectedEntryType,
                    'gender': _selectedGender,
                    'email': _emailController.text,
                    'hearSource': _selectedHearSource,
                    'educationType': _selectedEducationType,
                    'foreignLanguage': _selectedForeignLanguage,
                    'reference': _referenceController.text,
                    'parents': parentsToSave,
                    'updatedAt': FieldValue.serverTimestamp(),
                  };

                  // Düzenleme veya yeni kayıt
                  if (existingId != null) {
                    // Güncelleme
                    await FirebaseFirestore.instance
                        .collection('students')
                        .doc(existingId)
                        .update(studentData);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✓ Öğrenci güncellendi!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } else {
                    // Yeni kayıt
                    studentData['createdAt'] = FieldValue.serverTimestamp();
                    studentData['isActive'] =
                        true; // Yeni kayıtlar aktif olarak başlar
                    await FirebaseFirestore.instance
                        .collection('students')
                        .add(studentData);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✓ Öğrenci kaydedildi!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }

                  widget.onSave();
                  Navigator.pop(context);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ Hata: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: false,
        child: Column(
          children: [
            // Modern Tabs
            Container(
              color: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _buildModernTab(0, Icons.person, 'Öğrenci\nBilgileri'),
                  SizedBox(width: 8),
                  _buildModernTab(1, Icons.location_on, 'Adres\nBilgileri'),
                  SizedBox(width: 8),
                  _buildModernTab(2, Icons.family_restroom, 'Veli\nBilgileri'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildStudentInfoTab(),
                  _buildAddressTab(),
                  _buildParentInfoTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: widget.isViewingPastTerm
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                // Validasyon: Zorunlu alanlar kontrol
                if (_tcController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('⚠ TC Kimlik Numarası zorunlu'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                if (_usernameController.text.isEmpty ||
                    _passwordController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('⚠ Kullanıcı adı ve şifre zorunlu'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                if (_selectedSchoolTypeId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('⚠ Okul seçimi zorunlu'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                if (_studentNoController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('⚠ Öğrenci numarası zorunlu'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                // TC tekrar kontrolü
                final tcExists = await FirebaseFirestore.instance
                    .collection('students')
                    .where('institutionId', isEqualTo: _institutionId)
                    .where('tcNo', isEqualTo: _tcController.text)
                    .limit(1)
                    .get();

                if (tcExists.docs.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '⚠ Bu TC Kimlik Numarası ile kayıtlı öğrenci var',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // Kullanıcı adı tekrar kontrolü
                final usernameExists = await FirebaseFirestore.instance
                    .collection('students')
                    .where('institutionId', isEqualTo: _institutionId)
                    .where('username', isEqualTo: _usernameController.text)
                    .limit(1)
                    .get();

                if (usernameExists.docs.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('⚠ Bu kullanıcı adı zaten kullanılıyor'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // Veli listesi hazırla
                List<Map<String, dynamic>> parentsToSave = List.from(_parents);
                if (_isStudentSelfGuardian) {
                  parentsToSave.add({
                    'name': 'Öğrencinin Kendisi',
                    'tcNo': _tcController.text,
                    'phone': _phoneController.text,
                    'relation': 'Kendisi',
                    'isSelf': true,
                  });
                }

                try {
                  // Yeni kayıtlar için aktif dönemi otomatik al
                  final activeTermId = await TermService().getActiveTermId();

                  // Firestore'a kaydet
                  await FirebaseFirestore.instance.collection('students').add({
                    'institutionId': _institutionId,
                    'schoolTypeId': _selectedSchoolTypeId,
                    'studentNo': _studentNoController.text,
                    'studentNumber': _studentNoController.text,
                    'name': _nameController.text,
                    'surname': _surnameController.text,
                    'fullName':
                        '${_nameController.text} ${_surnameController.text}',
                    'classLevel': _selectedClassLevel,
                    'classId': _selectedClassId,
                    'className': _selectedClassName,
                    'termId': activeTermId,
                    'subTermId': _selectedSubTermId,
                    'tcNo': _tcController.text,
                    'phone': _phoneController.text,
                    'username': _usernameController.text,
                    'password':
                        _passwordController.text, // TODO: Hash yapılmalı
                    'birthDate': _birthDateController.text,
                    'registrationDate': _registrationDateController.text,
                    'previousSchool': _previousSchoolController.text,
                    'isSelfGuardian': _isStudentSelfGuardian,
                    'registrationType': _selectedRegistrationType,
                    'entryType': _selectedEntryType,
                    'gender': _selectedGender,
                    'email': _emailController.text,
                    'hearSource': _selectedHearSource,
                    'educationType': _selectedEducationType,
                    'foreignLanguage': _selectedForeignLanguage,
                    'reference': _referenceController.text,
                    'parents': parentsToSave,
                    'isActive': true,
                    'createdAt': FieldValue.serverTimestamp(),
                    'updatedAt': FieldValue.serverTimestamp(),
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✓ Öğrenci kaydedildi!'),
                      backgroundColor: Colors.green,
                    ),
                  );

                  widget.onSave();
                  Navigator.pop(context);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ Hata: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              icon: Icon(Icons.save, color: Colors.white),
              label: Text('Kaydet', style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.blue,
            ),
    );
  }

  Widget _buildModernTab(int index, IconData icon, String label) {
    final isActive = _tabController?.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _tabController?.animateTo(index),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 200),
          margin: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          padding: EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: isActive
                ? LinearGradient(
                    colors: [Colors.blue.shade400, Colors.blue.shade600],
                  )
                : null,
            color: isActive ? null : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? Colors.blue.shade300 : Colors.grey.shade300,
              width: isActive ? 2 : 1,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isActive ? Colors.white : Colors.grey.shade600,
                size: 24,
              ),
              SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  color: isActive ? Colors.white : Colors.grey.shade600,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Tab içerikleri - Ana state ile aynı
  Widget _buildStudentInfoTab() {
    final isWide = MediaQuery.of(context).size.width > 800;

    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Kayıt Türü', Icons.bookmark),
          SizedBox(height: 12),
          DropdownButtonFormField<String>(
            decoration: _inputDecoration('Kayıt Türü *'),
            items: [
              DropdownMenuItem(value: 'asil', child: Text('Asil Kayıt')),
              DropdownMenuItem(value: 'yedek', child: Text('Yedek Kayıt')),
              DropdownMenuItem(value: 'misafir', child: Text('Misafir Kaydı')),
              DropdownMenuItem(value: 'demo', child: Text('Demo Kayıt')),
              DropdownMenuItem(
                value: 'excel_import',
                child: Text('Excel Aktarımı'),
              ),
            ],

            value: _selectedRegistrationType,
            onChanged: (value) {
              setState(() {
                _selectedRegistrationType = value;
              });
            },
          ),

          SizedBox(height: 16),
          _buildSectionTitle('Dönem Seçimi', Icons.calendar_today),
          SizedBox(height: 12),
          DropdownButtonFormField<String>(
            decoration: _inputDecoration('Kayıt Olacağı Dönem *').copyWith(
              hintText: _terms.isEmpty ? 'Önce dönem oluşturun' : 'Seçiniz',
            ),
            value: _selectedTermId,
            items: _terms.isEmpty
                ? []
                : _terms.expand((term) {
                    // Ana dönem
                    List<DropdownMenuItem<String>> items = [
                      DropdownMenuItem(
                        value: '${term['id']}',
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: Colors.indigo,
                            ),
                            SizedBox(width: 8),
                            Text(
                              term['name'],
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            if (term['isActive'] == true) ...[
                              SizedBox(width: 8),
                              Icon(
                                Icons.check_circle,
                                size: 14,
                                color: Colors.green,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ];

                    // Alt dönemler
                    final subTerms = (term['subTerms'] as List<dynamic>?) ?? [];
                    for (var subTerm in subTerms) {
                      items.add(
                        DropdownMenuItem(
                          value: '${term['id']}_${subTerm['id']}',
                          child: Padding(
                            padding: EdgeInsets.only(left: 24),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.subdirectory_arrow_right,
                                  size: 14,
                                  color: Colors.grey,
                                ),
                                SizedBox(width: 8),
                                Text('${term['name']} - ${subTerm['name']}'),
                              ],
                            ),
                          ),
                        ),
                      );
                    }

                    return items;
                  }).toList(),
            isExpanded: true,
            onChanged: (value) {
              setState(() {
                if (value != null && value.contains('_')) {
                  // Alt dönem seçildi
                  final parts = value.split('_');
                  _selectedTermId = parts[0];
                  _selectedSubTermId = parts[1];
                } else {
                  // Ana dönem seçildi
                  _selectedTermId = value;
                  _selectedSubTermId = null;
                }
              });
            },
            validator: (value) {
              if (value == null) return 'Zorunlu';
              return null;
            },
          ),
          if (_terms.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.orange),
                  SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/terms').then((_) {
                        _loadSchoolTypes(); // Dönemler ekranından dönünce yenile
                      });
                    },
                    child: Text('Dönem eklemek için tıklayın'),
                  ),
                ],
              ),
            ),

          SizedBox(height: 32),
          _buildSectionTitle('Kişisel Bilgiler', Icons.person),
          SizedBox(height: 12),

          // TC, Ad, Soyad - Responsive
          isWide
              ? Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _tcController,
                        decoration: _inputDecoration('T.C. Kimlik Numarası *')
                            .copyWith(
                              counterText: '',
                              suffixText: '${_tcController.text.length}/11',
                              suffixStyle: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                        keyboardType: TextInputType.number,
                        maxLength: 11,
                        onChanged: (value) => setState(() {}),
                        validator: (value) {
                          if (value == null || value.isEmpty)
                            return 'TC zorunlu';
                          if (value.length != 11) return '11 haneli olmalı';
                          if (!validateTC(value)) return 'Geçersiz TC';
                          return null;
                        },
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _nameController,
                        decoration: _inputDecoration('Ad *'),
                        inputFormatters: [UpperCaseTextFormatter()],
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Zorunlu';
                          return null;
                        },
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _surnameController,
                        decoration: _inputDecoration('Soyad *'),
                        inputFormatters: [UpperCaseTextFormatter()],
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Zorunlu';
                          return null;
                        },
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    TextFormField(
                      controller: _tcController,
                      decoration: _inputDecoration('T.C. Kimlik Numarası *')
                          .copyWith(
                            counterText: '',
                            suffixText: '${_tcController.text.length}/11',
                            suffixStyle: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                      keyboardType: TextInputType.number,
                      maxLength: 11,
                      onChanged: (value) => setState(() {}),
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'TC zorunlu';
                        if (value.length != 11) return '11 haneli olmalı';
                        if (!validateTC(value)) return 'Geçersiz TC';
                        return null;
                      },
                    ),
                    SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      decoration: _inputDecoration('Ad *'),
                      inputFormatters: [UpperCaseTextFormatter()],
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Zorunlu';
                        return null;
                      },
                    ),
                    SizedBox(height: 16),
                    TextFormField(
                      controller: _surnameController,
                      decoration: _inputDecoration('Soyad *'),
                      inputFormatters: [UpperCaseTextFormatter()],
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Zorunlu';
                        return null;
                      },
                    ),
                  ],
                ),
          SizedBox(height: 16),

          // Doğum, Cinsiyet, E-Posta - Responsive
          isWide
              ? Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _birthDateController,
                        decoration: _inputDecoration(
                          'Doğum Tarihi *',
                        ).copyWith(hintText: 'gg/aa/yyyy', counterText: ''),
                        keyboardType: TextInputType.number,
                        maxLength: 10,
                        onChanged: (value) {
                          final formatted = _formatBirthDate(value);
                          if (formatted != value) {
                            _birthDateController.value = TextEditingValue(
                              text: formatted,
                              selection: TextSelection.collapsed(
                                offset: formatted.length,
                              ),
                            );
                          }
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Zorunlu';
                          if (value.length != 10)
                            return 'gg/aa/yyyy formatında giriniz';
                          return null;
                        },
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        decoration: _inputDecoration('Cinsiyet *'),
                        items: [
                          DropdownMenuItem(
                            value: 'erkek',
                            child: Text('Erkek'),
                          ),
                          DropdownMenuItem(value: 'kiz', child: Text('Kız')),
                        ],
                        value: _selectedGender,
                        onChanged: (value) {
                          setState(() {
                            _selectedGender = value;
                          });
                        },
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _emailController,
                        decoration: _inputDecoration('E-Posta'),
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    TextFormField(
                      controller: _birthDateController,
                      decoration: _inputDecoration(
                        'Doğum Tarihi *',
                      ).copyWith(hintText: 'gg/aa/yyyy', counterText: ''),
                      keyboardType: TextInputType.number,
                      maxLength: 10,
                      onChanged: (value) {
                        final formatted = _formatBirthDate(value);
                        if (formatted != value) {
                          _birthDateController.value = TextEditingValue(
                            text: formatted,
                            selection: TextSelection.collapsed(
                              offset: formatted.length,
                            ),
                          );
                        }
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Zorunlu';
                        if (value.length != 10)
                          return 'gg/aa/yyyy formatında giriniz';
                        return null;
                      },
                    ),
                    SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      decoration: _inputDecoration('Cinsiyet *'),
                      items: [
                        DropdownMenuItem(value: 'erkek', child: Text('Erkek')),
                        DropdownMenuItem(value: 'kiz', child: Text('Kız')),
                      ],
                      value: _selectedGender,
                      onChanged: (value) {
                        setState(() {
                          _selectedGender = value;
                        });
                      },
                    ),
                    SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      decoration: _inputDecoration('E-Posta'),
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ],
                ),
          SizedBox(height: 16),

          TextFormField(
            controller: _phoneController,
            decoration: _inputDecoration('Telefon').copyWith(
              prefixText: '+90 ',
              prefixStyle: TextStyle(color: Colors.black87, fontSize: 16),
              hintText: '555 123 45 67',
            ),
            keyboardType: TextInputType.phone,
            maxLength: 10,
            validator: (value) {
              if (value == null || value.isEmpty) return null;
              if (value.length != 10) return '10 haneli olmalı';
              if (!RegExp(r'^[0-9]+$').hasMatch(value)) return 'Sadece rakam';
              return null;
            },
          ),

          SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: _buildSectionTitle('Giriş Bilgileri', Icons.login),
              ),
              SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  if (_tcController.text.length >= 6) {
                    final last6 = _tcController.text.substring(
                      _tcController.text.length - 6,
                    );
                    setState(() {
                      _usernameController.text = last6;
                      _passwordController.text = last6;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '✓ Kullanıcı adı ve şifre TC\'nin son 6 hanesi olarak oluşturuldu',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('⚠ Önce TC Kimlik numarasını girin'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                },
                icon: Icon(Icons.auto_awesome, size: 18),
                label: Text('Otomatik'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _usernameController,
                  decoration: _inputDecoration('Kullanıcı Adı *'),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Zorunlu';
                    return null;
                  },
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _passwordController,
                  decoration: _inputDecoration('Şifre *'),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Zorunlu';
                    return null;
                  },
                ),
              ),
            ],
          ),

          SizedBox(height: 32),
          _buildSectionTitle('Okul Bilgileri', Icons.school),
          SizedBox(height: 12),

          // Okul - Firestore'dan
          DropdownButtonFormField<String>(
            decoration: _inputDecoration('Okul *'),
            hint: Text('Okul seçin'),
            value: _selectedSchoolTypeId,
            items: _schoolTypes.map((schoolType) {
              return DropdownMenuItem<String>(
                value: schoolType['id'],
                child: Text(
                  schoolType['schoolTypeName'] ??
                      schoolType['typeName'] ??
                      'Bilinmeyen',
                ),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedSchoolTypeId = value;
                _studentNoController.clear();
              });
            },
            validator: (value) {
              if (value == null) return 'Zorunlu';
              return null;
            },
          ),
          SizedBox(height: 16),

          // Öğrenci No, Sınıf Seviyesi, Şube - 3'lü yan yana
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _studentNoController,
                  decoration: _inputDecoration('Öğrenci No *').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(Icons.calculate, color: Colors.blue),
                      tooltip: 'Otomatik Numara Ata',
                      onPressed: () async {
                        if (_selectedSchoolTypeId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('⚠️ Önce okul türünü seçin!'),
                            ),
                          );
                          return;
                        }

                        try {
                          final count = await FirebaseFirestore.instance
                              .collection('students')
                              .where('institutionId', isEqualTo: _institutionId)
                              .where(
                                'schoolTypeId',
                                isEqualTo: _selectedSchoolTypeId,
                              )
                              .get();

                          final schoolType = _schoolTypes.firstWhere(
                            (st) => st['id'] == _selectedSchoolTypeId,
                          );
                          final startNumber = schoolType['startNumber'] ?? 1;
                          final nextNumber = startNumber + count.docs.length;

                          setState(() {
                            _studentNoController.text = nextNumber.toString();
                          });

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✅ Otomatik numara: $nextNumber'),
                            ),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Hata: $e')));
                        }
                      },
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Zorunlu';
                    return null;
                  },
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: _inputDecoration('Sınıf Seviyesi *'),
                  hint: Text('Seçiniz'),
                  isExpanded: true,
                  items: _selectedSchoolTypeId == null
                      ? []
                      : (_schoolTypes.firstWhere(
                                      (st) => st['id'] == _selectedSchoolTypeId,
                                      orElse: () => {},
                                    )['activeGrades']
                                    as List<dynamic>?)
                                ?.map(
                                  (grade) => DropdownMenuItem<String>(
                                    value: grade.toString(),
                                    child: Text(
                                      grade.toString(),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList() ??
                            [],
                  value: _selectedClassLevel,
                  onChanged: (value) {
                    setState(() {
                      _selectedClassLevel = value;
                      // Sınıf seviyesi değişince şubeyi sıfırla
                      _selectedClassId = null;
                      _selectedClassName = null;
                    });
                  },
                  validator: (value) {
                    if (value == null) return 'Zorunlu';
                    return null;
                  },
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  key: ValueKey(
                    'new_student_class_${_selectedSchoolTypeId}_${_selectedClassLevel}',
                  ),
                  future:
                      _selectedSchoolTypeId == null ||
                          _selectedClassLevel == null
                      ? Future.value([])
                      : FirebaseFirestore.instance
                            .collection('classes')
                            .where(
                              'schoolTypeId',
                              isEqualTo: _selectedSchoolTypeId,
                            )
                            .where(
                              'classLevel',
                              isEqualTo:
                                  int.tryParse(
                                    _selectedClassLevel?.replaceAll(
                                          RegExp(r'[^0-9]'),
                                          '',
                                        ) ??
                                        '',
                                  ) ??
                                  0,
                            )
                            .where('isActive', isEqualTo: true)
                            .where('classTypeName', isEqualTo: 'Ders Sınıfı')
                            .get()
                            .then((snapshot) {
                              final docs = snapshot.docs.map((doc) {
                                final data = doc.data();
                                data['id'] = doc.id;
                                return data;
                              }).toList();
                              // Manuel sıralama
                              docs.sort(
                                (a, b) => (a['className'] ?? '').compareTo(
                                  b['className'] ?? '',
                                ),
                              );
                              return docs;
                            }),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return DropdownButtonFormField<String>(
                        decoration: _inputDecoration('Şube'),
                        items: [],
                        onChanged: null,
                        hint: Text('Yükleniyor...'),
                      );
                    }

                    final classes = snapshot.data ?? [];

                    return DropdownButtonFormField<String>(
                      decoration: _inputDecoration(
                        'Şube ${_selectedClassLevel != null ? "($_selectedClassLevel. Sınıf)" : ""}',
                      ),
                      value: _selectedClassId,
                      hint: Text(
                        _selectedClassLevel == null
                            ? 'Önce sınıf seviyesi seçin'
                            : 'Şube seçiniz',
                      ),
                      isExpanded: true,
                      items: classes.isEmpty
                          ? []
                          : classes.map((classItem) {
                              return DropdownMenuItem<String>(
                                value: classItem['id'],
                                child: Text(
                                  '${classItem['className']} - ${classItem['classTypeName']}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedClassId = value;
                          if (value != null) {
                            final selectedClass = classes.firstWhere(
                              (c) => c['id'] == value,
                              orElse: () => {},
                            );
                            _selectedClassName = selectedClass['className'];
                          } else {
                            _selectedClassName = null;
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _registrationDateController,
                  decoration: _inputDecoration('Kayıt Tarihi *').copyWith(
                    hintText: 'gg/aa/yyyy',
                    counterText: '',
                    suffixIcon: IconButton(
                      icon: Icon(Icons.today, size: 20, color: Colors.blue),
                      tooltip: 'Bugün',
                      onPressed: () {
                        final now = DateTime.now();
                        final formatted = _formatBirthDate(
                          '${now.day.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}${now.year}',
                        );
                        setState(() {
                          _registrationDateController.text = formatted;
                        });
                      },
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 10,
                  onChanged: (value) {
                    final formatted = _formatBirthDate(value);
                    if (formatted != value) {
                      _registrationDateController.value = TextEditingValue(
                        text: formatted,
                        selection: TextSelection.collapsed(
                          offset: formatted.length,
                        ),
                      );
                    }
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Zorunlu';
                    if (value.length != 10)
                      return 'gg/aa/yyyy formatında giriniz';
                    return null;
                  },
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: _inputDecoration('Giriş Türü'),
                  items: [
                    DropdownMenuItem(value: 'yeni', child: Text('Yeni Kayıt')),
                    DropdownMenuItem(
                      value: 'yenileme',
                      child: Text('Kayıt Yenileme'),
                    ),
                    DropdownMenuItem(
                      value: 'excel_import',
                      child: Text('Excel Aktarımı'),
                    ),
                  ],
                  value: _selectedEntryType,
                  onChanged: (value) {
                    setState(() {
                      _selectedEntryType = value;
                    });
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: 16),

          TextFormField(
            controller: _previousSchoolController,
            decoration: _inputDecoration('Geldiği Okul Adı'),
          ),
          SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: _inputDecoration('Okulumu nereden duydunuz'),
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(
                      value: 'internet',
                      child: Text('İnternet', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: 'arkadas',
                      child: Text(
                        'Arkadaş Tavsiyesi',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'reklam',
                      child: Text(
                        'Reklam/Tanıtım',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'sosyal',
                      child: Text(
                        'Sosyal Medya',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  value: _selectedHearSource,
                  onChanged: (value) {
                    setState(() {
                      _selectedHearSource = value;
                    });
                  },
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: _inputDecoration('Eğitim Şekli'),
                  items: [
                    DropdownMenuItem(value: 'tam_gun', child: Text('Tam Gün')),
                    DropdownMenuItem(value: 'sabahci', child: Text('Sabahçı')),
                    DropdownMenuItem(value: 'ogleci', child: Text('Öğlenci')),
                    DropdownMenuItem(value: 'yatili', child: Text('Yatılı')),
                    DropdownMenuItem(
                      value: 'aksam_kursu',
                      child: Text('Akşam Kursu'),
                    ),
                  ],
                  value: _selectedEducationType,
                  onChanged: (value) {
                    setState(() {
                      _selectedEducationType = value;
                    });
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: _inputDecoration('1.Yabancı Dil'),
                  items: [
                    DropdownMenuItem(
                      value: 'ingilizce',
                      child: Text('İngilizce'),
                    ),
                    DropdownMenuItem(value: 'almanca', child: Text('Almanca')),
                    DropdownMenuItem(
                      value: 'fransizca',
                      child: Text('Fransızca'),
                    ),
                    DropdownMenuItem(
                      value: 'ispanyolca',
                      child: Text('İspanyolca'),
                    ),
                    DropdownMenuItem(
                      value: 'italyanca',
                      child: Text('İtalyanca'),
                    ),
                    DropdownMenuItem(value: 'arapca', child: Text('Arapça')),
                  ],
                  value: _selectedForeignLanguage,
                  onChanged: (value) {
                    setState(() {
                      _selectedForeignLanguage = value;
                    });
                  },
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _referenceController,
                  decoration: _inputDecoration('Referans Kişi/Kurum'),
                ),
              ),
            ],
          ),

          SizedBox(height: 32),
          _buildSectionTitle('Öğrenci Fotoğrafı', Icons.photo_camera),
          SizedBox(height: 12),

          // Fotoğraf Ekleme
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              children: [
                if (_photoPath != null)
                  Container(
                    height: 150,
                    width: 150,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      image: DecorationImage(
                        image: NetworkImage(_photoPath!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                else
                  Container(
                    height: 150,
                    width: 150,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.person,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                  ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Galeri özelliği yakında eklenecek',
                              ),
                            ),
                          );
                        },
                        icon: Icon(Icons.attach_file, size: 18),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Galeriden Seç'),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Kamera özelliği yakında eklenecek',
                              ),
                            ),
                          );
                        },
                        icon: Icon(Icons.camera_alt, size: 18),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Fotoğraf Çek'),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_photoPath != null) ...[
                  SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _photoPath = null;
                      });
                    },
                    icon: Icon(Icons.delete, color: Colors.red),
                    label: Text(
                      'Fotoğrafı Kaldır',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildParentInfoTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Kayıtlı Veliler Listesi Başlık
          Text(
            'Kayıtlı Veliler',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          SizedBox(height: 12),

          // Veli Öğrencinin Kendisi - Sadece hiç veli yoksa göster
          if (_parents.isEmpty)
            Card(
              elevation: _isStudentSelfGuardian ? 4 : 2,
              color: _isStudentSelfGuardian ? Colors.green.shade50 : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: _isStudentSelfGuardian
                      ? Colors.green
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _isStudentSelfGuardian = !_isStudentSelfGuardian;
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        _isStudentSelfGuardian
                            ? Icons.check_circle
                            : Icons.check_circle_outline,
                        color: _isStudentSelfGuardian
                            ? Colors.green
                            : Colors.grey,
                        size: 32,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Veli Öğrencinin Kendisi',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _isStudentSelfGuardian
                                    ? Colors.green.shade900
                                    : Colors.black,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              _isStudentSelfGuardian
                                  ? 'Seçildi - Veli bilgisi gerekmiyor'
                                  : 'Veli bilgisi eklenmeyecek',
                              style: TextStyle(
                                fontSize: 12,
                                color: _isStudentSelfGuardian
                                    ? Colors.green.shade700
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (_parents.isEmpty) SizedBox(height: 16),

          // Mevcut Kayıtlardan Seç - Card
          Card(
            elevation: 2,
            color: Colors.blue.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              onTap: () {
                _showParentSelectionDialog();
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.person_search, color: Colors.blue, size: 32),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mevcut Kayıtlardan Seç',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Daha önce kayıtlı veli seç',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, size: 16, color: Colors.blue),
                  ],
                ),
              ),
            ),
          ),

          SizedBox(height: 16),

          // Yeni Veli Ekle Butonu
          ElevatedButton.icon(
            onPressed: () {
              _showAddParentForm();
            },
            icon: Icon(Icons.person_add),
            label: Text('Yeni Veli Ekle'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              minimumSize: Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          SizedBox(height: 24),

          // Veli listesi
          if (_parents.isEmpty)
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.family_restroom,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Henüz veli eklenmedi',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: _parents.length,
              itemBuilder: (context, index) {
                final parent = _parents[index];
                return Container(
                  margin: EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade100, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade200,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.blue.shade400, Colors.blue.shade600],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.person, color: Colors.white, size: 24),
                    ),
                    title: Text(
                      '${(parent['name'] ?? parent['fullName'] ?? 'İsimsiz').toString()}${parent['surname'] != null && (parent['surname'] as String).isNotEmpty ? ' ' + parent['surname'] : ''}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade900,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 4),
                        InkWell(
                          onTap: () =>
                              _launchParentPhone(context, parent['phone']),
                          child: Row(
                            children: [
                              Icon(
                                Icons.phone,
                                size: 14,
                                color: Colors.grey.shade600,
                              ),
                              SizedBox(width: 4),
                              Text(
                                parent['phone'] ?? 'Telefon yok',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                  decoration:
                                      parent['phone'] != null &&
                                          (parent['phone'] as String).isNotEmpty
                                      ? TextDecoration.underline
                                      : TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.family_restroom,
                              size: 14,
                              color: Colors.grey.shade600,
                            ),
                            SizedBox(width: 4),
                            Text(
                              _formatRelation(
                                parent['relation'] ?? 'Belirtilmemiş',
                              ),
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit_outlined, color: Colors.orange),
                          tooltip: 'Düzenle',
                          onPressed: () {
                            _editParentInForm(index, parent);
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.info_outline, color: Colors.blue),
                          tooltip: 'Detayları Görüntüle',
                          onPressed: () {
                            _showParentDetailsDialog(parent);
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: Colors.red),
                          tooltip: 'Veli Çıkar',
                          onPressed: () {
                            setState(() {
                              _parents.removeAt(index);
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('✓ Veli silindi'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // Dialog metodları - Ayrı sayfa için
  void _showParentSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.person_search, color: Colors.blue),
            SizedBox(width: 12),
            Text('Veli Seç'),
          ],
        ),
        content: Container(
          width: 400,
          height: 400,
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: 'Veli ara...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              SizedBox(height: 16),
              Expanded(
                child: Center(
                  child: Text(
                    'Kayıtlı veli bulunamadı',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal'),
          ),
        ],
      ),
    );
  }

  String _formatRelation(String relation) {
    // Özel durumlar için mapping
    final Map<String, String> relationMap = {
      'anne': 'Anne',
      'baba': 'Baba',
      'uvey_anne': 'Üvey Anne',
      'uvey_baba': 'Üvey Baba',
      'koruyucu': 'Koruyucu Ebeveyn',
      'kiz_kardes': 'Kız Kardeş',
      'erkek_kardes': 'Erkek Kardeş',
      'amca_dayi': 'Amca/Dayı',
      'hala_teyze': 'Hala/Teyze',
      'buyukbaba': 'Büyükbaba',
      'buyukanne': 'Büyükanne',
      'kuzen': 'Kuzen',
      'bakici': 'Bakıcı',
      'kocasi': 'Kocası',
      'karisi': 'Karısı',
      'oglu': 'Oğlu',
      'kizi': 'Kızı',
      'erkek_yegen': 'Erkek Yeğen',
      'kiz_yegen': 'Kız Yeğen',
      'arkadas': 'Arkadaş',
      'diger': 'Diğer',
    };

    // Eğer mapping'de varsa kullan
    if (relationMap.containsKey(relation.toLowerCase())) {
      return relationMap[relation.toLowerCase()]!;
    }

    // Yoksa ilk harfi büyük yap
    if (relation.isEmpty) return relation;
    return relation[0].toUpperCase() + relation.substring(1);
  }

  void _editParentInForm(int index, Map<String, dynamic> parent) {
    // Parent bilgilerini düzenleme dialogu göster
    final tcController = TextEditingController(
      text: (parent['tcNo'] ?? '').toString(),
    );
    final nameController = TextEditingController(
      text: (parent['name'] ?? '').toString(),
    );
    final surnameController = TextEditingController(
      text: (parent['surname'] ?? '').toString(),
    );
    final phoneController = TextEditingController(
      text: (parent['phone'] ?? '').toString(),
    );
    final emailController = TextEditingController(
      text: (parent['email'] ?? '').toString(),
    );
    final addressController = TextEditingController(
      text: (parent['address'] ?? '').toString(),
    );
    final usernameController = TextEditingController(
      text: (parent['username'] ?? '').toString(),
    );
    final passwordController = TextEditingController(
      text: (parent['password'] ?? '').toString(),
    );

    // Normalizasyon: Gelen değer "Anne" ise "anne" yap, listede yoksa "diger" yap
    String currentRelation = (parent['relation'] ?? '')
        .toString()
        .toLowerCase();

    // Geçerli listeyi kontrol et (Dropdown items ile aynı olmalı)
    final validRelations = {
      'anne',
      'baba',
      'uvey_anne',
      'uvey_baba',
      'koruyucu',
      'kiz_kardes',
      'erkek_kardes',
      'amca_dayi',
      'hala_teyze',
      'buyukbaba',
      'buyukanne',
      'kuzen',
      'bakici',
      'kocasi',
      'karisi',
      'oglu',
      'kizi',
      'erkek_yegen',
      'kiz_yegen',
      'arkadas',
      'diger',
    };

    String selectedRelation = validRelations.contains(currentRelation)
        ? currentRelation
        : 'diger';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.edit, color: Colors.orange),
                SizedBox(width: 12),
                Text('Veli Düzenle'),
              ],
            ),
            content: Container(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: 'Yakınlık Derecesi',
                        border: OutlineInputBorder(),
                      ),
                      value: selectedRelation,
                      items: [
                        DropdownMenuItem(value: 'anne', child: Text('Anne')),
                        DropdownMenuItem(value: 'baba', child: Text('Baba')),
                        DropdownMenuItem(
                          value: 'uvey_anne',
                          child: Text('Üvey Anne'),
                        ),
                        DropdownMenuItem(
                          value: 'uvey_baba',
                          child: Text('Üvey Baba'),
                        ),
                        DropdownMenuItem(
                          value: 'koruyucu',
                          child: Text('Koruyucu Ebeveyn'),
                        ),
                        DropdownMenuItem(
                          value: 'kiz_kardes',
                          child: Text('Kız Kardeş'),
                        ),
                        DropdownMenuItem(
                          value: 'erkek_kardes',
                          child: Text('Erkek Kardeş'),
                        ),
                        DropdownMenuItem(
                          value: 'amca_dayi',
                          child: Text('Amca/Dayı'),
                        ),
                        DropdownMenuItem(
                          value: 'hala_teyze',
                          child: Text('Hala/Teyze'),
                        ),
                        DropdownMenuItem(
                          value: 'buyukbaba',
                          child: Text('Büyükbaba'),
                        ),
                        DropdownMenuItem(
                          value: 'buyukanne',
                          child: Text('Büyükanne'),
                        ),
                        DropdownMenuItem(value: 'kuzen', child: Text('Kuzen')),
                        DropdownMenuItem(
                          value: 'bakici',
                          child: Text('Bakıcı'),
                        ),
                        DropdownMenuItem(
                          value: 'kocasi',
                          child: Text('Kocası'),
                        ),
                        DropdownMenuItem(
                          value: 'karisi',
                          child: Text('Karısı'),
                        ),
                        DropdownMenuItem(value: 'oglu', child: Text('Oğlu')),
                        DropdownMenuItem(value: 'kizi', child: Text('Kızı')),
                        DropdownMenuItem(
                          value: 'erkek_yegen',
                          child: Text('Erkek Yeğen'),
                        ),
                        DropdownMenuItem(
                          value: 'kiz_yegen',
                          child: Text('Kız Yeğen'),
                        ),
                        DropdownMenuItem(
                          value: 'arkadas',
                          child: Text('Arkadaş'),
                        ),
                        DropdownMenuItem(value: 'diger', child: Text('Diğer')),
                      ],
                      onChanged: (val) {
                        setStateDialog(() => selectedRelation = val!);
                      },
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: tcController,
                      decoration: InputDecoration(
                        labelText: 'TC Kimlik No',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 11,
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Ad',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: surnameController,
                      decoration: InputDecoration(
                        labelText: 'Soyad',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      decoration: InputDecoration(
                        labelText: 'Telefon',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      decoration: InputDecoration(
                        labelText: 'E-posta',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: addressController,
                      decoration: InputDecoration(
                        labelText: 'Adres',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: usernameController,
                      decoration: InputDecoration(
                        labelText: 'Kullanıcı Adı',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      decoration: InputDecoration(
                        labelText: 'Şifre',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                    ),
                  ],
                ),
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
                    _parents[index] = {
                      'tcNo': tcController.text,
                      'name': nameController.text,
                      'surname': surnameController.text,
                      'phone': phoneController.text,
                      'email': emailController.text,
                      'address': addressController.text,
                      'username': usernameController.text,
                      'password': passwordController.text,
                      'relation': selectedRelation,
                    };
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('✓ Veli bilgileri güncellendi')),
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: Text('Kaydet'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showParentDetailsDialog(Map<String, dynamic> parent) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.person, color: Colors.blue),
            SizedBox(width: 12),
            Text('Veli Detayları'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRowInDialog('Ad Soyad', parent['name'] ?? '-'),
              _buildDetailRowInDialog('TC Kimlik No', parent['tcNo'] ?? '-'),
              _buildDetailRowInDialog('Telefon', parent['phone'] ?? '-'),
              _buildDetailRowInDialog('E-posta', parent['email'] ?? '-'),
              _buildDetailRowInDialog('Yakınlık', parent['relation'] ?? '-'),
              _buildDetailRowInDialog('Adres', parent['address'] ?? '-'),
              _buildDetailRowInDialog(
                'Kullanıcı Adı',
                parent['username'] ?? '-',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Kapat'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRowInDialog(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade900),
          ),
          Divider(),
        ],
      ),
    );
  }

  void _showAddParentForm() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.person_add, color: Colors.green),
            SizedBox(width: 12),
            Expanded(child: Text('Yeni Veli Ekle')),
            IconButton(
              icon: Icon(Icons.close, color: Colors.red),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        content: Container(
          width: 600,
          child: SingleChildScrollView(child: _buildParentForm()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Geri'),
          ),
          ElevatedButton(
            onPressed: () {
              // Validasyonlar
              if (_selectedParentRelation == null ||
                  _selectedParentRelation!.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('⚠ Yakınlık türü seçiniz'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }

              if (_parentNameController.text.isEmpty ||
                  _parentSurnameController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('⚠ Ad ve Soyad zorunlu'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }

              if (_parentUsernameController.text.isEmpty ||
                  _parentPasswordController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('⚠ Kullanıcı adı ve şifre zorunlu'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }

              if (_parentPasswordController.text.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('⚠ Şifre en az 6 karakter olmalı'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }

              setState(() {
                _parents.add({
                  'relation': _selectedParentRelation,
                  'tcNo': _parentTcController.text,
                  'name': _parentNameController.text,
                  'surname': _parentSurnameController.text,
                  'fullName':
                      '${_parentNameController.text} ${_parentSurnameController.text}',
                  'phone': _parentPhoneController.text,
                  'email': _parentEmailController.text,
                  'username': _parentUsernameController.text,
                  'password':
                      _parentPasswordController.text, // TODO: Hash yapılmalı
                  'address': _useSameAddress
                      ? 'Öğrenci ile aynı'
                      : _parentAddressController.text,
                });

                _parentTcController.clear();
                _parentNameController.clear();
                _parentSurnameController.clear();
                _parentPhoneController.clear();
                _parentEmailController.clear();
                _parentUsernameController.clear();
                _parentPasswordController.clear();
                _parentAddressController.clear();
                _selectedParentRelation = null;
                _useSameAddress = false;
              });

              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✓ Veli eklendi'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Widget _buildParentForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          decoration: _inputDecoration('Yakınlık Türü *'),
          value: _selectedParentRelation,
          items: [
            DropdownMenuItem(value: 'anne', child: Text('Anne')),
            DropdownMenuItem(value: 'baba', child: Text('Baba')),
            DropdownMenuItem(value: 'uvey_anne', child: Text('Üvey Anne')),
            DropdownMenuItem(value: 'uvey_baba', child: Text('Üvey Baba')),
            DropdownMenuItem(
              value: 'koruyucu',
              child: Text('Koruyucu ebeveyn'),
            ),
            DropdownMenuItem(value: 'kiz_kardes', child: Text('Kız Kardeş')),
            DropdownMenuItem(
              value: 'erkek_kardes',
              child: Text('Erkek Kardeş'),
            ),
            DropdownMenuItem(value: 'amca_dayi', child: Text('Amca/Dayı')),
            DropdownMenuItem(value: 'hala_teyze', child: Text('Hala/Teyze')),
            DropdownMenuItem(value: 'buyukbaba', child: Text('Büyükbaba')),
            DropdownMenuItem(value: 'buyukanne', child: Text('Büyükanne')),
            DropdownMenuItem(value: 'kuzen', child: Text('Kuzen')),
            DropdownMenuItem(value: 'bakici', child: Text('Bakıcı')),
            DropdownMenuItem(value: 'kocasi', child: Text('Kocası')),
            DropdownMenuItem(value: 'karisi', child: Text('Karısı')),
            DropdownMenuItem(value: 'oglu', child: Text('Oğlu')),
            DropdownMenuItem(value: 'kizi', child: Text('Kızı')),
            DropdownMenuItem(value: 'erkek_yegen', child: Text('Erkek Yeğen')),
            DropdownMenuItem(value: 'kiz_yegen', child: Text('Kız Yeğen')),
            DropdownMenuItem(value: 'arkadas', child: Text('Arkadaş')),
            DropdownMenuItem(value: 'diger', child: Text('Diğer')),
          ],
          onChanged: (value) {
            setState(() {
              _selectedParentRelation = value;
            });
          },
        ),
        SizedBox(height: 16),
        TextFormField(
          controller: _parentTcController,
          decoration: _inputDecoration('T.C. Kimlik Numarası'),
          keyboardType: TextInputType.number,
          maxLength: 11,
          onChanged: (value) {
            if (value.length == 11) {
              setState(() {
                _parentUsernameController.text = 'V$value';
                if (_parentPasswordController.text.isEmpty) {
                  _parentPasswordController.text = value.substring(5);
                }
              });
            }
          },
        ),
        SizedBox(height: 16),
        TextFormField(
          decoration: _inputDecoration(
            'Ön ek',
          ).copyWith(hintText: 'Bay, Bayan...'),
        ),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _parentNameController,
                decoration: _inputDecoration('Ad *'),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _parentSurnameController,
                decoration: _inputDecoration('Soyad *'),
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        TextFormField(
          controller: _parentEmailController,
          decoration: _inputDecoration('E-Posta'),
          keyboardType: TextInputType.emailAddress,
        ),
        SizedBox(height: 16),
        TextFormField(
          controller: _parentPhoneController,
          decoration: _inputDecoration('Mesaj Gönder (Cep Tel)').copyWith(
            prefixText: '+90 ',
            prefixStyle: TextStyle(color: Colors.black87),
          ),
          keyboardType: TextInputType.phone,
          maxLength: 10,
        ),
        SizedBox(height: 16),
        DropdownButtonFormField<String>(
          decoration: _inputDecoration('Veli SMS Alsın'),
          items: [
            DropdownMenuItem(value: 'evet', child: Text('Evet')),
            DropdownMenuItem(value: 'hayir', child: Text('Hayır')),
          ],
          onChanged: (value) {},
        ),
        SizedBox(height: 16),
        CheckboxListTile(
          title: Text('Öğrenci ile Aynı Adres'),
          value: _useSameAddress,
          onChanged: (value) {
            setState(() {
              _useSameAddress = value ?? false;
            });
          },
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        SizedBox(height: 16),
        DropdownButtonFormField<String>(
          decoration: _inputDecoration('Eğitim Seviyesi'),
          items: [
            DropdownMenuItem(value: 'ilkokul', child: Text('İlkokul')),
            DropdownMenuItem(value: 'ortaokul', child: Text('Ortaokul')),
            DropdownMenuItem(value: 'lise', child: Text('Lise')),
            DropdownMenuItem(value: 'onlisans', child: Text('Ön Lisans')),
            DropdownMenuItem(value: 'lisans', child: Text('Lisans')),
            DropdownMenuItem(
              value: 'yuksek_lisans',
              child: Text('Yüksek Lisans'),
            ),
            DropdownMenuItem(value: 'doktora', child: Text('Doktora')),
          ],
          onChanged: (value) {},
        ),
        SizedBox(height: 16),
        DropdownButtonFormField<String>(
          decoration: _inputDecoration('Meslek Grubu'),
          items: [
            DropdownMenuItem(value: 'memur', child: Text('Memur')),
            DropdownMenuItem(value: 'isci', child: Text('İşçi')),
            DropdownMenuItem(value: 'serbest', child: Text('Serbest Meslek')),
            DropdownMenuItem(value: 'emekli', child: Text('Emekli')),
            DropdownMenuItem(value: 'ev_hanimi', child: Text('Ev Hanımı')),
            DropdownMenuItem(value: 'ogretmen', child: Text('Öğretmen')),
            DropdownMenuItem(value: 'muhendis', child: Text('Mühendis')),
            DropdownMenuItem(value: 'doktor', child: Text('Doktor')),
            DropdownMenuItem(value: 'diger', child: Text('Diğer')),
          ],
          onChanged: (value) {},
        ),
        SizedBox(height: 16),
        DropdownButtonFormField<String>(
          decoration: _inputDecoration('Çalışma Şekli'),
          items: [
            DropdownMenuItem(value: 'tam_zamanli', child: Text('Tam Zamanlı')),
            DropdownMenuItem(
              value: 'yari_zamanli',
              child: Text('Yarı Zamanlı'),
            ),
            DropdownMenuItem(value: 'freelance', child: Text('Freelance')),
            DropdownMenuItem(value: 'calismıyor', child: Text('Çalışmıyor')),
          ],
          onChanged: (value) {},
        ),
        SizedBox(height: 16),
        TextFormField(decoration: _inputDecoration('Meslek')),
        SizedBox(height: 16),
        TextFormField(decoration: _inputDecoration('Görev / Ünvan')),
        SizedBox(height: 16),
        TextFormField(decoration: _inputDecoration('Çalıştığı Kurum')),
      ],
    );
  }

  Widget _buildAddressTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Adres Ekle Butonu
          ElevatedButton.icon(
            onPressed: () {
              _showAddAddressDialog();
            },
            icon: Icon(Icons.add_location),
            label: Text('Adres Ekle'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              minimumSize: Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          SizedBox(height: 24),

          // Kayıtlı Adresler Listesi
          Text(
            'Kayıtlı Adresler',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          SizedBox(height: 12),

          Container(
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.location_off,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Henüz adres eklenmedi',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Adres dialog metodları - Ayrı sayfa için
  void _showAddAddressDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.add_location, color: Colors.blue),
            SizedBox(width: 12),
            Expanded(child: Text('Yeni Adres Ekle')),
            IconButton(
              icon: Icon(Icons.close, color: Colors.red),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        content: Container(
          width: 600,
          child: SingleChildScrollView(child: _buildAddressForm()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          decoration: _inputDecoration('Adres Türü *'),
          items: [
            DropdownMenuItem(value: 'ev', child: Text('Ev Adresi')),
            DropdownMenuItem(value: 'posta', child: Text('Posta Adresi')),
            DropdownMenuItem(value: 'gonderim', child: Text('Gönderim Adresi')),
            DropdownMenuItem(value: 'diger_ev', child: Text('Diğer Ev Adresi')),
            DropdownMenuItem(value: 'is', child: Text('İş Adresi')),
            DropdownMenuItem(
              value: 'diger_kurum',
              child: Text('Diğer Kurum Adresi'),
            ),
          ],
          onChanged: (value) {},
        ),
        SizedBox(height: 16),
        TextFormField(
          decoration: _inputDecoration(
            'Adres *',
          ).copyWith(hintText: 'Sokak, Mahalle, Bina No...'),
          maxLines: 3,
        ),
        SizedBox(height: 16),
        TextFormField(
          decoration: _inputDecoration('Ülke *'),
          initialValue: 'TÜRKİYE',
        ),
        SizedBox(height: 16),
        TextFormField(decoration: _inputDecoration('İl *')),
        SizedBox(height: 16),
        TextFormField(decoration: _inputDecoration('İlçe')),
        SizedBox(height: 16),
        TextFormField(decoration: _inputDecoration('Semt')),
        SizedBox(height: 16),
        TextFormField(
          decoration: _inputDecoration('Posta Kodu'),
          keyboardType: TextInputType.number,
        ),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                decoration: _inputDecoration('Enlem'),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                decoration: _inputDecoration('Boylam'),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: () {
                // TODO: Haritada işaretle
              },
              icon: Icon(Icons.map, size: 20),
              label: Text('Harita'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Helper metodları
  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey.shade600),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.blue, width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.blue, size: 20),
        ),
        SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
        ),
      ],
    );
  }

  // TODO: Metodları daha sonra aktif edeceğiz
  /*
  Future<void> _autoAssignStudentNumber() async {
    if (_selectedSchoolTypeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Önce okul türünü seçin!')),
      );
      return;
    }
    try {
      final studentsQuery = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: _institutionId)
          .where('schoolTypeId', isEqualTo: _selectedSchoolTypeId)
          .get();
      final schoolTypeDoc = await FirebaseFirestore.instance
          .collection('schoolTypes')
          .doc(_selectedSchoolTypeId)
          .get();
      final startNumber = schoolTypeDoc.data()?['startNumber'] ?? 1;
      final nextNumber = startNumber + studentsQuery.docs.length;
      setState(() {
        _studentNoController.text = nextNumber.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Otomatik numara atandı: $nextNumber')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    }
  }
  */

  // TÜM ÖĞRENCİLERİ SİL (DEBUG)
}
