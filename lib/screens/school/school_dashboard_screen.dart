import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/edukn_logo.dart';
// Web için
import 'dart:html' as html show window;
import 'user_profile_screen.dart';
import '../../services/term_service.dart';
import 'terms_screen.dart';
import 'assessment/assessment_dashboard_screen.dart';
import 'assessment/assessment_reports_screen.dart';
import '../../services/announcement_service.dart';
import 'dart:async';

class SchoolDashboardScreen extends StatefulWidget {
  const SchoolDashboardScreen({Key? key}) : super(key: key);

  @override
  _SchoolDashboardScreenState createState() => _SchoolDashboardScreenState();
}

class _SchoolDashboardScreenState extends State<SchoolDashboardScreen> {
  Map<String, dynamic>? schoolData;
  Map<String, dynamic>? userData; // Giriş yapan kullanıcının verileri
  Map<String, dynamic>? activeTerm; // Aktif dönem
  List<Map<String, dynamic>> _terms = []; // Tüm dönemler
  String? _selectedTermId; // Seçili dönem ID
  bool isLoading = true;
  String _selectedCategory = 'Tümü';
  int studentCount = 0;
  int userCount = 0;
  int schoolTypesCount = 0;
  Timer? _announcementTimer;
  final AnnouncementService _announcementService = AnnouncementService();

  @override
  void initState() {
    super.initState();
    _loadSchoolData();
    _startAnnouncementCheck();
  }

  void _startAnnouncementCheck() {
    // Hemen bir kontrol yap
    _announcementService.checkAndPublishScheduledAnnouncements();
    // Her 5 dakikada bir kontrol et
    _announcementTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _announcementService.checkAndPublishScheduledAnnouncements();
    });
  }

  @override
  void dispose() {
    _announcementTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSchoolData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Navigator.pushReplacementNamed(context, '/school-login');
        return;
      }

      // Kullanıcının email'inden kurum ID'sini al
      final email = user.email!;
      final institutionId = email.split('@')[1].split('.')[0].toUpperCase();
      var instIdForQueries = institutionId; // fallback sonrası güncellenebilir

      // Firestore'dan okul verilerini al (kurum ID ile)
      var schoolQuery = await FirebaseFirestore.instance
          .collection('schools')
          .where('institutionId', isEqualTo: institutionId)
          .limit(1)
          .get();

      Map<String, dynamic>? data;
      if (schoolQuery.docs.isNotEmpty) {
        final schoolDoc = schoolQuery.docs.first;
        data = schoolDoc.data();
        data['id'] = schoolDoc.id;
      } else {
        // Fallback: Kullanıcının users/{uid} belgesine bak ve schoolId ile oku
        print(
          'ℹ️ Kurum ID ile okul bulunamadı. Fallback: users/${user.uid} -> schoolId',
        );
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          final u = userDoc.data() as Map<String, dynamic>;
          final fallbackSchoolId = u['schoolId'] as String?;
          if (fallbackSchoolId != null && fallbackSchoolId.isNotEmpty) {
            final schoolById = await FirebaseFirestore.instance
                .collection('schools')
                .doc(fallbackSchoolId)
                .get();
            if (schoolById.exists) {
              data = schoolById.data() as Map<String, dynamic>;
              data['id'] = schoolById.id;
              // Kurum ID'yi okuldan al (tüm sorgular için doğru olsun)
              final schInstId = (data['institutionId'] ?? '').toString();
              if (schInstId.isNotEmpty) {
                instIdForQueries = schInstId;
              }
            }
          }
        }
      }
      if (data != null) {
        // Tüm dönemleri al
        final allTermsQuery = await FirebaseFirestore.instance
            .collection('terms')
            .where('institutionId', isEqualTo: instIdForQueries)
            .get();

        final termsList = allTermsQuery.docs.map((doc) {
          final termData = doc.data();
          termData['id'] = doc.id;
          return termData;
        }).toList();

        // Sırala (yeni dönemler önce)
        termsList.sort((a, b) {
          final aYear = a['startYear'] ?? 0;
          final bYear = b['startYear'] ?? 0;
          return bYear.compareTo(aYear);
        });

        // Aktif dönemi bul
        Map<String, dynamic>? activeTermData;
        String? activeTermId;
        for (var term in termsList) {
          if (term['isActive'] == true) {
            activeTermData = term;
            activeTermId = term['id'];
            break;
          }
        }

        // Seçili dönemi kontrol et (SharedPreferences'dan)
        final prefs = await SharedPreferences.getInstance();
        final selectedTermId =
            prefs.getString('selected_term_id') ?? activeTermId;

        // Öğrenci sayısını al (dönem filtresine göre)
        final studentsSnapshot = await FirebaseFirestore.instance
            .collection('students')
            .where('institutionId', isEqualTo: data['institutionId'])
            .get();

        // Client-side dönem filtresi
        final filteredStudents = studentsSnapshot.docs.where((doc) {
          final studentData = doc.data();
          return selectedTermId == null ||
              studentData['termId'] == selectedTermId;
        }).toList();

        // Kullanıcı sayısını al
        final usersQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('institutionId', isEqualTo: data['institutionId'])
            .get();

        // Okul türleri sayısını al
        final schoolTypesQuery = await FirebaseFirestore.instance
            .collection('schoolTypes')
            .where('institutionId', isEqualTo: data['institutionId'])
            .get();

        // Impersonation kontrolü
        print('🔍 Impersonation kontrolü başlatılıyor...');
        final isImpersonating = prefs.getBool('is_impersonating') ?? false;
        final impersonatedEmail = prefs.getString('impersonated_user_email');
        final impersonatedName = prefs.getString('impersonated_user_name');

        print('📋 SharedPreferences durumu:');
        print('   - is_impersonating: $isImpersonating');
        print('   - impersonated_email: $impersonatedEmail');
        print('   - impersonated_name: $impersonatedName');

        Map<String, dynamic>? currentUserData;

        if (isImpersonating) {
          print('🎭 Impersonation modu aktif: $impersonatedEmail');

          if (impersonatedEmail != null) {
            print('🔍 Firestore\'dan kullanıcı aranıyor: $impersonatedEmail');
            final impUserQuery = await FirebaseFirestore.instance
                .collection('users')
                .where('email', isEqualTo: impersonatedEmail)
                .limit(1)
                .get();

            print('📊 Query sonucu: ${impUserQuery.docs.length} döküman');

            if (impUserQuery.docs.isNotEmpty) {
              currentUserData = impUserQuery.docs.first.data();
              print(
                '✅ Impersonated kullanıcı yüklendi: ${currentUserData['fullName']}',
              );
            } else {
              print('❌ Impersonated kullanıcı Firestore\'da bulunamadı!');
            }
          } else {
            print('❌ impersonated_user_email null!');
          }
        } else {
          print('ℹ️ Normal mod - Impersonation yok');
          // Normal giriş - Email'den kullanıcı adını al
          final username = email.split('@')[0];
          final userQuery = await FirebaseFirestore.instance
              .collection('users')
              .where('institutionId', isEqualTo: data['institutionId'])
              .where('username', isEqualTo: username)
              .limit(1)
              .get();

          if (userQuery.docs.isNotEmpty) {
            currentUserData = userQuery.docs.first.data();
            print(
              '✅ Kullanıcı verileri yüklendi: ${currentUserData['fullName']}',
            );
          }
        }

        if (currentUserData != null) {
          print('📋 Modül yetkileri: ${currentUserData['modulePermissions']}');
          print(
            '🏫 Okul türü yetkileri: ${currentUserData['schoolTypePermissions']}',
          );
        } else {
          // Admin kullanıcısı (users koleksiyonunda yok)
          print('ℹ️ Admin kullanıcısı - Tüm yetkiler var');
        }

        setState(() {
          schoolData = data;
          userData = currentUserData;
          activeTerm = activeTermData;
          _terms = termsList;
          _selectedTermId = selectedTermId;
          studentCount = filteredStudents.length;
          userCount = usersQuery.docs.length;
          schoolTypesCount = schoolTypesQuery.docs.length;
          isLoading = false;
        });
      } else {
        throw 'Okul verisi bulunamadı! (institutionId=$instIdForQueries)';
      }
    } catch (e) {
      print('Hata: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Okul verileri yüklenemedi: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => isLoading = false);
    }
  }

  // Modül kontrolü - Kullanıcının bu modüle erişimi var mı?
  bool _hasModuleAccess(String moduleKey) {
    // Önce okulda bu modül aktif mi kontrol et
    if (schoolData == null) return false;
    final activeModules = schoolData!['activeModules'] as List<dynamic>? ?? [];

    // Okulda modül aktif değilse, kimse erişemez
    if (!activeModules.contains(moduleKey)) {
      print('⚠️ Modül okulda aktif değil: $moduleKey');
      return false;
    }

    // Admin kullanıcısı (userData yok) - Okulda aktif olan her modüle erişebilir
    if (userData == null) {
      return true;
    }

    // Normal kullanıcı - modulePermissions kontrol et
    final modulePerms = userData!['modulePermissions'] as Map<String, dynamic>?;
    if (modulePerms == null) {
      print('⚠️ Kullanıcının modül yetkisi yok');
      return false;
    }

    final modulePerm = modulePerms[moduleKey] as Map<String, dynamic>?;
    if (modulePerm == null) {
      print('⚠️ Kullanıcının $moduleKey modülüne yetkisi yok');
      return false;
    }

    // Modül kullanıcı için aktif mi?
    final hasAccess = modulePerm['enabled'] == true;
    if (!hasAccess) {
      print('⚠️ Kullanıcı için $moduleKey modülü pasif');
    }
    return hasAccess;
  }

  // Düzenleme yetkisi var mı? (viewer ise false, editor ise true)
  bool _canEdit(String moduleKey) {
    // Önce modüle erişimi var mı kontrol et
    if (!_hasModuleAccess(moduleKey)) return false;

    // Admin - Her zaman düzenleyebilir
    if (userData == null) return true;

    final modulePerms = userData!['modulePermissions'] as Map<String, dynamic>?;
    if (modulePerms == null) return false;

    final modulePerm = modulePerms[moduleKey] as Map<String, dynamic>?;
    if (modulePerm == null) return false;

    // level: 'editor' ise true, 'viewer' ise false
    return modulePerm['level'] == 'editor';
  }

  // Okul türü yetkisi var mı?
  bool _hasSchoolTypeAccess(String schoolTypeId) {
    // Admin - Tüm okul türlerine erişim var
    if (userData == null) return true;

    final schoolTypes = userData!['schoolTypes'] as List<dynamic>? ?? [];
    return schoolTypes.contains(schoolTypeId);
  }

  // Kullanıcı adını al
  String _getUserDisplayName() {
    if (userData != null) {
      return userData!['fullName'] ?? 'Kullanıcı';
    }
    return schoolData?['adminFullName'] ?? 'Yönetici';
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Çıkış Yap'),
        content: Text('Çıkış yapmak istediğinize emin misiniz?'),
        actions: [
          TextButton(
            child: Text('İptal'),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Çıkış Yap'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/school-login');
      }
    }
  }

  // Dönem seçici bottom sheet
  void _showTermSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        padding: EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_month, color: Colors.indigo),
                  SizedBox(width: 8),
                  Text(
                    'Dönem Seç',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Divider(height: 24),
              if (_terms.isEmpty)
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: Text('Henüz dönem tanımlanmamış')),
                )
              else
                ...(_terms.map((term) {
                  final isActive = term['isActive'] == true;
                  final isSelected = _selectedTermId == term['id'];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isActive
                          ? Colors.green[100]
                          : (isSelected
                                ? Colors.orange[100]
                                : Colors.grey[100]),
                      child: Icon(
                        isActive
                            ? Icons.check_circle
                            : (isSelected
                                  ? Icons.visibility
                                  : Icons.calendar_today),
                        color: isActive
                            ? Colors.green
                            : (isSelected ? Colors.orange : Colors.grey),
                      ),
                    ),
                    title: Text(
                      '${term['startYear']}-${term['endYear']}',
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: isActive
                        ? Text(
                            'Aktif Dönem',
                            style: TextStyle(color: Colors.green),
                          )
                        : (isSelected
                              ? Text(
                                  'Görüntüleniyor',
                                  style: TextStyle(color: Colors.orange),
                                )
                              : null),
                    trailing: isSelected
                        ? Icon(Icons.radio_button_checked, color: Colors.indigo)
                        : Icon(Icons.radio_button_off),
                    onTap: () async {
                      Navigator.pop(context);
                      await _switchToTerm(term);
                    },
                  );
                }).toList()),
              Divider(height: 24),
              // Migration butonu
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue[100],
                  child: Icon(Icons.sync, color: Colors.blue),
                ),
                title: Text('Verileri Aktif Döneme Ata'),
                subtitle: Text(
                  'Dönem bilgisi olmayan verileri aktif döneme atar',
                  style: TextStyle(fontSize: 11),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _migrateDataToActiveTerm();
                },
              ),
              // Tüm verileri sil butonu
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.red[100],
                  child: Icon(Icons.delete_forever, color: Colors.red),
                ),
                title: Text(
                  'Tüm Verileri Sil',
                  style: TextStyle(color: Colors.red),
                ),
                subtitle: Text(
                  'Öğrenci, sınıf, ders, duyuru vb. tüm verileri siler',
                  style: TextStyle(fontSize: 11),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _deleteAllData();
                },
              ),
              Divider(height: 24),
              // Dönem yönetimi butonu
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.indigo[100],
                  child: Icon(Icons.settings, color: Colors.indigo),
                ),
                title: Text('Dönem Yönetimi'),
                subtitle: Text(
                  'Dönem ekle, düzenle, veri kopyala',
                  style: TextStyle(fontSize: 11),
                ),
                trailing: Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TermsScreen(),
                    ),
                  ).then(
                    (_) => _loadSchoolData(),
                  ); // Geri dönünce dönemleri yenile
                },
              ),
              SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // Verileri aktif döneme ata (migration)
  Future<void> _migrateDataToActiveTerm() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.sync, color: Colors.blue),
            SizedBox(width: 12),
            Text('Veri Aktarımı'),
          ],
        ),
        content: Text(
          'Dönem bilgisi olmayan tüm mevcut veriler (öğrenciler, sınıflar, dersler vb.) aktif döneme atanacak.\n\nBu işlem bir kez yapılmalıdır. Devam etmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('İptal'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: Icon(Icons.sync),
            label: Text('Aktar'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Loading dialog göster
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            EduKnLoader(size: 40),
            SizedBox(width: 16),
            Text('Veriler aktarılıyor...'),
          ],
        ),
      ),
    );

    try {
      final count = await TermService().migrateDataToActiveTerm();
      Navigator.pop(context); // Loading dialog kapat

      // Verileri yeniden yükle
      setState(() => isLoading = true);
      await _loadSchoolData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ $count kayıt aktif döneme atandı'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // Loading dialog kapat
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // Tüm verileri sil
  Future<void> _deleteAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 12),
            Text('Tüm Verileri Sil'),
          ],
        ),
        content: Text(
          'DİKKAT! Bu işlem geri alınamaz!\n\nAşağıdaki veriler silinecek:\n• Öğrenci kayıtları\n• Sınıf kayıtları\n• Ders kayıtları\n• Derslik kayıtları\n• Çalışma takvimi ve yıllık planlar\n• Ders saatleri\n• Duyurular\n\nDevam etmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('İptal'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: Icon(Icons.delete_forever),
            label: Text('Tümünü Sil'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            EduKnLoader(size: 40),
            SizedBox(width: 16),
            Text('Veriler siliniyor...'),
          ],
        ),
      ),
    );

    try {
      final count = await TermService().deleteAllData();
      Navigator.pop(context); // Loading dialog kapat

      // Verileri yeniden yükle
      setState(() => isLoading = true);
      await _loadSchoolData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ $count kayıt silindi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // Loading dialog kapat
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // Döneme geç
  Future<void> _switchToTerm(Map<String, dynamic> term) async {
    final isActive = term['isActive'] == true;

    // TermService üzerinden dönem değişikliğini yap (cache'i de temizler)
    if (isActive) {
      // Aktif döneme dönülüyorsa seçili dönemi temizle
      await TermService().clearSelectedTerm();
    } else {
      // Geçmiş döneme geçiliyorsa kaydet
      await TermService().setSelectedTerm(
        term['id'],
        term['name'] ?? '${term['startYear']}-${term['endYear']}',
      );
    }

    // Verileri yeniden yükle
    setState(() => isLoading = true);
    await _loadSchoolData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isActive
                ? '✓ Aktif döneme dönüldü'
                : '✓ ${term['startYear']}-${term['endYear']} dönemi görüntüleniyor',
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // Geçmiş dönem görüntüleniyor mu?
  bool _isViewingPastTerm() {
    if (_selectedTermId == null) return false;
    if (activeTerm == null) return false;
    return _selectedTermId != activeTerm!['id'];
  }

  // Seçili dönem bilgisini al
  String _getSelectedTermDisplay() {
    if (_selectedTermId == null) return '';

    final selectedTerm = _terms.firstWhere(
      (t) => t['id'] == _selectedTermId,
      orElse: () => {},
    );

    if (selectedTerm.isEmpty) return '';

    return '${selectedTerm['startYear']}-${selectedTerm['endYear']}';
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(body: Center(child: EduKnLoader(size: 100)));
    }

    if (schoolData == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text('Okul verileri yüklenemedi!'),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/school-login'),
                child: Text('Giriş Ekranına Dön'),
              ),
            ],
          ),
        ),
      );
    }

    final schoolName = schoolData!['schoolName'] ?? 'Okul İsmi';

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: Builder(
          builder: (context) => IconButton(
            icon: Icon(Icons.menu, color: Colors.indigo),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              schoolName,
              style: TextStyle(
                color: Colors.grey.shade900,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              _getUserDisplayName(),
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          // Dönem seçici butonu - sadece geniş ekranda göster
          if (MediaQuery.of(context).size.width >= 600) ...[
            InkWell(
              onTap: _showTermSelector,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                margin: EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _isViewingPastTerm()
                      ? Colors.orange[50]
                      : Colors.indigo[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isViewingPastTerm() ? Colors.orange : Colors.indigo,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_month,
                      size: 18,
                      color: _isViewingPastTerm()
                          ? Colors.orange
                          : Colors.indigo,
                    ),
                    SizedBox(width: 6),
                    Text(
                      _getSelectedTermDisplay().isNotEmpty
                          ? _getSelectedTermDisplay()
                          : (activeTerm != null
                                ? '${activeTerm!['startYear']}-${activeTerm!['endYear']}'
                                : 'Dönem'),
                      style: TextStyle(
                        color: _isViewingPastTerm()
                            ? Colors.orange[800]
                            : Colors.indigo,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 18,
                      color: _isViewingPastTerm()
                          ? Colors.orange
                          : Colors.indigo,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 4),
          ],
          // Admin olarak dön butonu (sadece impersonation modunda)
          FutureBuilder<bool>(
            future: _checkImpersonation(),
            builder: (context, snapshot) {
              if (snapshot.data == true) {
                return IconButton(
                  icon: Icon(Icons.admin_panel_settings, color: Colors.orange),
                  tooltip: 'Admin Olarak Dön',
                  onPressed: _returnToAdmin,
                );
              }
              return SizedBox.shrink();
            },
          ),
          // Bildirim ikonu - sadece geniş ekranda göster
          if (MediaQuery.of(context).size.width >= 600)
            IconButton(
              icon: Icon(Icons.notifications_outlined, color: Colors.indigo),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Bildirimler yakında eklenecek...')),
                );
              },
            ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.indigo),
            onSelected: (value) {
              if (value == 'term') {
                _showTermSelector();
              } else if (value == 'notifications') {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Bildirimler yakında eklenecek...')),
                );
              } else if (value == 'profile') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) => const UserProfileScreen(),
                  ),
                );
              } else if (value == 'add-user') {
                Navigator.pushNamed(context, '/user-management');
              } else if (value == 'logout') {
                _logout();
              }
            },
            itemBuilder: (BuildContext context) => [
              // Mobilde dönem ve bildirim menüye taşınır
              if (MediaQuery.of(context).size.width < 600) ...[
                PopupMenuItem(
                  value: 'term',
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_month,
                        color: _isViewingPastTerm()
                            ? Colors.orange
                            : Colors.indigo,
                        size: 20,
                      ),
                      SizedBox(width: 12),
                      Text(
                        _getSelectedTermDisplay().isNotEmpty
                            ? 'Dönem: ${_getSelectedTermDisplay()}'
                            : (activeTerm != null
                                  ? 'Dönem: ${activeTerm!['startYear']}-${activeTerm!['endYear']}'
                                  : 'Dönem Seç'),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'notifications',
                  child: Row(
                    children: [
                      Icon(
                        Icons.notifications_outlined,
                        color: Colors.indigo,
                        size: 20,
                      ),
                      SizedBox(width: 12),
                      Text('Bildirimler'),
                    ],
                  ),
                ),
                PopupMenuDivider(),
              ],
              PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person, color: Colors.indigo, size: 20),
                    SizedBox(width: 12),
                    Text('Profilim'),
                  ],
                ),
              ),
              // Kullanıcı Ekle (Admin her zaman görebilir)
              if ((userData == null) ||
                  (_hasModuleAccess('kullanici_yonetimi') &&
                      _canEdit('kullanici_yonetimi')))
                PopupMenuItem(
                  value: 'add-user',
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_add_alt_1,
                        color: Colors.deepPurple,
                        size: 20,
                      ),
                      SizedBox(width: 12),
                      Text('Kullanıcı Yönetimi'),
                    ],
                  ),
                ),
              if (_hasModuleAccess('kullanici_yonetimi') &&
                  _canEdit('kullanici_yonetimi'))
                PopupMenuDivider(),
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red, size: 20),
                    SizedBox(width: 12),
                    Text('Çıkış Yap', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(width: 8),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.indigo, Colors.blue]),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.school, size: 36, color: Colors.indigo),
                  ),
                  SizedBox(height: 12),
                  Text(
                    _getUserDisplayName(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // Okul adı ve dönem bilgisi
                  InkWell(
                    onTap: _showTermSelector,
                    child: Row(
                      children: [
                        Text(
                          '$schoolName | ',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        Text(
                          _getSelectedTermDisplay().isNotEmpty
                              ? _getSelectedTermDisplay()
                              : (activeTerm != null
                                    ? '${activeTerm!['startYear']}-${activeTerm!['endYear']}'
                                    : 'Dönem'),
                          style: TextStyle(
                            color: _isViewingPastTerm()
                                ? Colors.orange[300]
                                : Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.arrow_drop_down,
                          color: _isViewingPastTerm()
                              ? Colors.orange[300]
                              : Colors.white70,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.dashboard),
              title: Text('Ana Sayfa'),
              selected: true,
              onTap: () {
                Navigator.pop(context);
              },
            ),
            Divider(),
            // İLETİŞİM VE EĞİTİM BÖLÜMÜ
            // Genel Duyurular - Modül (1. sıra)
            if (_hasModuleAccess('genel_duyurular'))
              ListTile(
                leading: Icon(Icons.campaign),
                title: Text('Genel Duyurular'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/announcements');
                },
              ),
            // Öğrenci Kayıt - Modül (2. sıra)
            if (_hasModuleAccess('ogrenci_kayit'))
              ListTile(
                leading: Icon(Icons.person_add),
                title: Text('Öğrenci Kayıt'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/student-registration');
                },
              ),
            // Okul Türleri - Modül (3. sıra)
            if (_hasModuleAccess('okul_turleri'))
              ListTile(
                leading: Icon(Icons.school_outlined),
                title: Text('Okul Türleri'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/school-types');
                },
              ),
            Divider(),
            // YÖNETİM BÖLÜMÜ
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'YÖNETİM',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            // Kullanıcı Yönetimi - Modül (Admin her zaman görebilir)
            if (userData == null || _hasModuleAccess('kullanici_yonetimi'))
              ListTile(
                leading: Icon(Icons.person_add_alt_1, color: Colors.deepPurple),
                title: Text('Kullanıcı Yönetimi'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/user-management');
                },
              ),
            // İnsan Kaynakları - Modül
            if (_hasModuleAccess('insan_kaynaklari'))
              ListTile(
                leading: Icon(Icons.group),
                title: Text('İnsan Kaynakları'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/hr');
                },
              ),
            Divider(),
            // MALİ İŞLER BÖLÜMÜ
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'MALİ İŞLER',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            // Muhasebe - Modül
            if (_hasModuleAccess('muhasebe'))
              ListTile(
                leading: Icon(Icons.account_balance),
                title: Text('Muhasebe'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Muhasebe modülü yakında eklenecek...'),
                    ),
                  );
                },
              ),

            Divider(),
            // HİZMETLER BÖLÜMÜ
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'HİZMETLER',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            // Destek Hizmetleri - Modül
            if (_hasModuleAccess('destek_hizmetleri'))
              ListTile(
                leading: Icon(Icons.support_agent),
                title: Text('Destek Hizmetleri'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/support-services');
                },
              ),
            Divider(),
            // RAPORLAR BÖLÜMÜ
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'RAPORLAR',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            if (_hasModuleAccess('yoklama'))
              ListTile(
                leading: Icon(
                  Icons.fact_check_outlined,
                  color: Colors.blueGrey,
                ),
                title: Text('Yoklama Raporları'),
                onTap: () {
                  Navigator.pop(context);
                  // Yoklama modülü yönlendirmesi
                },
              ),
            if (_hasModuleAccess('odevler'))
              ListTile(
                leading: Icon(
                  Icons.assignment_outlined,
                  color: Colors.blueGrey,
                ),
                title: Text('Ödev Raporları'),
                onTap: () {
                  Navigator.pop(context);
                  // Ödevler modülü yönlendirmesi
                },
              ),
            ListTile(
              leading: Icon(Icons.assessment_outlined, color: Colors.blueGrey),
              title: Text('Ölçme Değerlendirme Raporları'),
              onTap: () {
                Navigator.pop(context);
                // Ölçme değerlendirme raporları yönlendirmesi
              },
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.settings),
              title: Text('Ayarlar'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Ayarlar ekranı
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Ayarlar yakında eklenecek...')),
                );
              },
            ),
          ],
        ),
      ),
      body: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCategorySelector(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: _buildFilteredModuleList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategorySelector() {
    final categories = [
      {'label': 'Tümü', 'icon': Icons.grid_view_rounded},
      {'label': 'İletişim ve Eğitim', 'icon': Icons.forum_rounded},
      {'label': 'Yönetim', 'icon': Icons.manage_accounts_rounded},
      {'label': 'Mali İşler', 'icon': Icons.account_balance_wallet_rounded},
      {'label': 'Hizmetler', 'icon': Icons.design_services_rounded},
      {'label': 'Raporlar', 'icon': Icons.analytics_outlined},
      {'label': 'Ayarlar', 'icon': Icons.settings_rounded},
    ];

    return Container(
      width: double.infinity,
      height: 140,
      child: Center(
        child: ScrollConfiguration(
          behavior: MyCustomScrollBehavior(),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: IntrinsicWidth(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: categories.map((cat) {
                  final isSelected = _selectedCategory == cat['label'];
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: GestureDetector(
                      onTap: () => setState(
                        () => _selectedCategory = cat['label'] as String,
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.indigo : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: isSelected
                                  ? Colors.indigo.withOpacity(0.3)
                                  : Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: Border.all(
                            color: isSelected
                                ? Colors.indigo
                                : Colors.grey.shade200,
                            width: 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              cat['icon'] as IconData,
                              color: isSelected
                                  ? Colors.white
                                  : Colors.indigo.shade400,
                              size: 28,
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Text(
                                cat['label'] as String,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.grey.shade700,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ), // Row
            ), // IntrinsicWidth
          ), // SingleChildScrollView
        ), // ScrollConfiguration
      ), // Center
    ); // Container
  }

  Widget _buildFilteredModuleList() {
    final bool showAll = _selectedCategory == 'Tümü';
    final bool showIletisim =
        showAll || _selectedCategory == 'İletişim ve Eğitim';
    final bool showYonetim = showAll || _selectedCategory == 'Yönetim';
    final bool showMali = showAll || _selectedCategory == 'Mali İşler';
    final bool showHizmet = showAll || _selectedCategory == 'Hizmetler';
    final bool showRapor = showAll || _selectedCategory == 'Raporlar';
    final bool showAyarlar = showAll || _selectedCategory == 'Ayarlar';

    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        // İLETİŞİM VE EĞİTİM
        if (showIletisim &&
            (_hasModuleAccess('genel_duyurular') ||
                _hasModuleAccess('ogrenci_kayit') ||
                _hasModuleAccess('okul_turleri'))) ...[
          _buildCategoryHeader('İLETİŞİM VE EĞİTİM'),
          if (_hasModuleAccess('genel_duyurular')) ...[
            _buildHorizontalCard(
              icon: Icons.campaign,
              title: 'Genel Duyurular',
              subtitle: 'Duyuru oluştur ve paylaş',
              color: Colors.purple,
              onTap: () => Navigator.pushNamed(context, '/announcements'),
            ),
            const SizedBox(height: 8),
          ],
          if (_hasModuleAccess('ogrenci_kayit')) ...[
            _buildHorizontalCard(
              icon: Icons.contact_phone,
              title: 'Ön Kayıt / Görüşme',
              subtitle: 'Aday görüşmeleri ve fiyat teklifleri',
              color: Colors.orange,
              onTap: () =>
                  Navigator.pushNamed(context, '/pre-registration'),
            ),
            const SizedBox(height: 8),
            _buildHorizontalCard(
              icon: Icons.person_add,
              title: 'Öğrenci Kayıt',
              subtitle: 'Kesin kayıt ve öğrenci yönetimi',
              color: Colors.blue,
              onTap: () =>
                  Navigator.pushNamed(context, '/student-registration'),
            ),
            const SizedBox(height: 8),
          ],
          if (_hasModuleAccess('okul_turleri')) ...[
            _buildHorizontalCard(
              icon: Icons.school_outlined,
              title: 'Okul Türleri',
              subtitle: 'Anaokulu, İlkokul, Lise vb.',
              color: Colors.teal,
              onTap: () => Navigator.pushNamed(context, '/school-types'),
            ),
            const SizedBox(height: 8),
          ],
          _buildHorizontalCard(
            icon: Icons.assignment_turned_in,
            title: 'Ölçme Değerlendirme',
            subtitle: 'Sınav, Deneme, Optik Form Tanımları',
            color: Colors.deepOrange,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AssessmentDashboardScreen(
                    institutionId: schoolData!['institutionId'],
                    schoolTypeId: schoolData!['id'],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
        ],

        // YÖNETİM
        if (showYonetim &&
            (userData == null ||
                _hasModuleAccess('kullanici_yonetimi') ||
                _hasModuleAccess('insan_kaynaklari'))) ...[
          _buildCategoryHeader('YÖNETİM'),
          if (userData == null || _hasModuleAccess('kullanici_yonetimi')) ...[
            _buildHorizontalCard(
              icon: Icons.person_add_alt_1,
              title: 'Kullanıcı Yönetimi',
              subtitle: 'Kullanıcı ekleme ve yetkilendirme',
              color: Colors.deepPurple,
              onTap: () => Navigator.pushNamed(context, '/user-management'),
            ),
            const SizedBox(height: 8),
          ],
          if (_hasModuleAccess('insan_kaynaklari')) ...[
            _buildHorizontalCard(
              icon: Icons.group,
              title: 'İnsan Kaynakları',
              subtitle: 'Personel yönetimi',
              color: Colors.indigo,
              onTap: () => Navigator.pushNamed(context, '/hr'),
            ),
            const SizedBox(height: 16),
          ],
        ],

        // MALİ İŞLER
        if (showMali &&
            (_hasModuleAccess('muhasebe') ||
                _hasModuleAccess('satin_alma') ||
                _hasModuleAccess('depo'))) ...[
          _buildCategoryHeader('MALİ İŞLER'),
          if (_hasModuleAccess('muhasebe')) ...[
            _buildHorizontalCard(
              icon: Icons.account_balance,
              title: 'Muhasebe',
              subtitle: 'Mali işlemler ve raporlama',
              color: Colors.green,
              onTap: () {
                Navigator.pushNamed(context, '/accounting');
              },
            ),
            const SizedBox(height: 16),
          ],
        ],

        // HİZMETLER
        if (showHizmet && _hasModuleAccess('destek_hizmetleri')) ...[
          _buildCategoryHeader('HİZMETLER'),
          _buildHorizontalCard(
            icon: Icons.support_agent,
            title: 'Destek Hizmetleri',
            subtitle: 'Teknik destek ve yardım',
            color: Colors.cyan,
            onTap: () => Navigator.pushNamed(context, '/support-services'),
          ),
          const SizedBox(height: 16),
        ],

        // RAPORLAR
        if (showRapor) ...[
          _buildCategoryHeader('RAPORLAR'),
          if (_hasModuleAccess('yoklama')) ...[
            _buildHorizontalCard(
              icon: Icons.fact_check_outlined,
              title: 'Yoklama Raporları',
              subtitle: 'Günlük ve genel yoklama istatistikleri',
              color: Colors.blueGrey,
              onTap: () {
                // Yoklama raporları
              },
            ),
            const SizedBox(height: 8),
          ],
          if (_hasModuleAccess('odevler')) ...[
            _buildHorizontalCard(
              icon: Icons.assignment_outlined,
              title: 'Ödev Raporları',
              subtitle: 'Ödev teslimat ve başarı raporları',
              color: Colors.blueGrey,
              onTap: () {
                // Ödev raporları
              },
            ),
            const SizedBox(height: 8),
          ],
          _buildHorizontalCard(
            icon: Icons.assessment_outlined,
            title: 'Ölçme Değerlendirme Raporları',
            subtitle: 'Sınav sonuçları ve analiz raporları',
            color: Colors.blueGrey,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AssessmentReportsScreen(
                    institutionId: schoolData!['institutionId'],
                    schoolTypeId: schoolData!['id'],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
        ],

        // AYARLAR
        if (showAyarlar) ...[
          _buildCategoryHeader('AYARLAR'),
          _buildHorizontalCard(
            icon: Icons.security,
            title: 'Yetki Tanımlama',
            subtitle: 'Yetki türlerini ve kapsamlarını yönet',
            color: Colors.blueAccent,
            onTap: () => Navigator.pushNamed(context, '/permission-definition'),
          ),
          const SizedBox(height: 8),
          _buildHorizontalCard(
            icon: Icons.manage_accounts,
            title: 'Kullanıcı Yetkilendirme',
            subtitle: 'Kullanıcılara yetki ve okul türü ata',
            color: Colors.deepPurple,
            onTap: () => Navigator.pushNamed(context, '/user-management'),
          ),
          const SizedBox(height: 8),
          _buildHorizontalCard(
            icon: Icons.settings_suggest,
            title: 'Uygulama Ayarları',
            subtitle: 'Genel uygulama ve kurum ayarları',
            color: Colors.grey,
            onTap: () => Navigator.pushNamed(context, '/app-settings'),
          ),
          const SizedBox(height: 16),
        ],

        _buildEmptyState(
          showIletisim,
          showYonetim,
          showMali,
          showHizmet,
          showRapor,
          showAyarlar,
        ),
      ],
    );
  }

  Widget _buildCategoryHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12, top: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade600,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    bool iletisim,
    bool yonetim,
    bool mali,
    bool hizmet,
    bool rapor,
    bool ayarlar,
  ) {
    if (!iletisim && !yonetim && !mali && !hizmet && !rapor && !ayarlar) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.info_outline, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'Bu kategoride aktif modül yok',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  // Okul türüne geçiş yetkisi
  bool _canSwitchToSchoolType(String schoolTypeId) {
    if (userData == null) return true; // Admin

    // 1. Kullanıcının atandığı okul türlerini kontrol et
    final assignedSchoolTypes =
        userData!['schoolTypes'] as List<dynamic>? ?? [];
    if (!assignedSchoolTypes.contains(schoolTypeId)) return false;

    // 2. Modül yetkisi içinde 'okul_turleri' varsa ve editor ise
    // (veya özel bir yetki tanımı varsa)
    return true;
  }

  // Okul türlerini getir
  Future<List<Map<String, dynamic>>> _getSchoolTypes() async {
    final query = await FirebaseFirestore.instance
        .collection('schoolTypes')
        .where('institutionId', isEqualTo: schoolData!['institutionId'])
        .orderBy('level')
        .get();

    return query.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  // Okul türü seçici dialog
  void _showSchoolTypeSelector(
    List<Map<String, dynamic>> schoolTypes,
    Function(Map<String, dynamic>) onSelected,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Okul Türü Seçin'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: schoolTypes.length,
            separatorBuilder: (c, i) => const Divider(),
            itemBuilder: (context, index) {
              final type = schoolTypes[index];
              return ListTile(
                title: Text(type['name']),
                onTap: () {
                  Navigator.pop(context);
                  onSelected(type);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  // Yatay kart - Hoş geldiniz gibi
  Widget _buildHorizontalCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 28, color: color),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade900,
                      ),
                    ),
                    SizedBox(height: 2),
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
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Impersonation kontrolü
  Future<bool> _checkImpersonation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_impersonating') ?? false;
  }

  // Admin olarak geri dön
  Future<void> _returnToAdmin() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Impersonation bilgilerini temizle
      await prefs.remove('impersonated_user_id');
      await prefs.remove('impersonated_user_email');
      await prefs.remove('impersonated_user_name');
      await prefs.remove('is_impersonating');
      await prefs.remove('admin_backup_email');

      // Web için sayfayı tamamen yeniden yükle
      if (kIsWeb) {
        html.window.location.reload();
      } else {
        // Mobil için navigation
        Navigator.pushReplacementNamed(context, '/school-dashboard');
      }

      // Başarı mesajı
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Admin hesabına geri dönüldü'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }
}

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
  };
}
