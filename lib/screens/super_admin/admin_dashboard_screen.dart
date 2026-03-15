import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart'; // Yeni fonksiyonlar için
import 'package:intl/intl.dart'; // Tarih formatlamak için
import 'add_school_screen.dart';
import 'admin_login_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  @override
  _AdminDashboardScreenState createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  // Okul verilerini 'schools' koleksiyonundan canlı olarak dinle
  // DİKKAT: 'createdAt' alanına göre sıralama için Firebase'de index gerekir.
  final Stream<QuerySnapshot> _schoolsStream = FirebaseFirestore.instance
      .collection('schools')
      .orderBy('createdAt', descending: true)
      .snapshots();
  
  // Dar ekranlarda hangi sekme gösterilsin
  int _selectedTabIndex = 0; // 0: İstatistikler, 1: Okullar

  void _logout() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => AdminLoginScreen()),
    );
  }

  // --- HATA DÜZELTMESİ: EKSİK FONKSİYON EKLENDİ ---
  void _navigateToAddSchool() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AddSchoolScreen()),
    );
  }
  // --- HATA DÜZELTMESİ BİTTİ ---

  // --- YENİ TASARIM: OKUL YÖNETİM PENCERESİ ---
  void _showManageSchoolDialog(DocumentSnapshot schoolDoc) {
    Map<String, dynamic> school = schoolDoc.data() as Map<String, dynamic>;
    String schoolId = schoolDoc.id;
    bool isActive = school['isActive'] ?? false;

    // Lisans tarihini al
    Timestamp? expiresAtStamp = school['licenseExpiresAt'];
    DateTime? expiresAtDate = expiresAtStamp?.toDate();
    String expiresAtFormatted = expiresAtDate != null
        ? DateFormat('dd.MM.yyyy').format(expiresAtDate)
        : "Bilinmiyor";

    // Lisans durumunu kontrol et
    bool isExpired =
        expiresAtDate != null && expiresAtDate.isBefore(DateTime.now());
    int daysRemaining = expiresAtDate != null
        ? expiresAtDate.difference(DateTime.now()).inDays
        : 0;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: 500,
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Başlık
                Row(
                  children: [
                    Icon(
                      Icons.school,
                      size: 28,
                      color: Theme.of(context).primaryColor,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        school['schoolName'],
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                Divider(height: 32),

                // Durum Kartı
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isActive
                          ? Colors.green.shade200
                          : Colors.red.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isActive ? Icons.check_circle : Icons.cancel,
                        color: isActive ? Colors.green : Colors.red,
                        size: 32,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isActive ? 'Okul Aktif' : 'Okul Pasif',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isActive
                                    ? Colors.green.shade800
                                    : Colors.red.shade800,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Lisans: $expiresAtFormatted',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            if (!isExpired && daysRemaining > 0)
                              Text(
                                '$daysRemaining gün kaldı',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            if (isExpired)
                              Text(
                                'Lisans süresi dolmuş!',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 24),

                // Hızlı İşlemler
                Text(
                  'Hızlı İşlemler',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildActionChip(
                      label: isActive ? 'Pasife Geçir' : 'Aktife Geçir',
                      icon: isActive
                          ? Icons.pause_circle_outline
                          : Icons.play_circle_outline,
                      color: isActive ? Colors.orange : Colors.green,
                      onTap: () {
                        Navigator.pop(context);
                        _toggleSchoolStatus(schoolId, !isActive);
                      },
                    ),
                    _buildActionChip(
                      label: 'Modülleri Düzenle',
                      icon: Icons.tune,
                      color: Colors.blue,
                      onTap: () {
                        Navigator.pop(context);
                        _showModuleEditorDialog(schoolDoc);
                      },
                    ),
                  ],
                ),
                SizedBox(height: 24),

                // Lisans Yönetimi
                Text(
                  'Lisans Yönetimi',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: Icon(Icons.add, size: 18),
                        label: Text('1 Ay Ekle'),
                        onPressed: () {
                          Navigator.pop(context);
                          _extendLicense(schoolId, 30);
                        },
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: Icon(Icons.add, size: 18),
                        label: Text('1 Yıl Ekle'),
                        onPressed: () {
                          Navigator.pop(context);
                          _extendLicense(schoolId, 365);
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: Icon(Icons.edit_calendar, size: 18),
                    label: Text('Özel Tarih Belirle'),
                    onPressed: () {
                      Navigator.pop(context);
                      _showCustomDatePicker(schoolId, expiresAtDate);
                    },
                  ),
                ),
                SizedBox(height: 24),
                Divider(),
                SizedBox(height: 8),
                // Tehlikeli Bölge - Okul Sil
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: Icon(Icons.delete_forever, size: 18),
                    label: Text('Okulu Sil'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: BorderSide(color: Colors.red.shade300),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _showDeleteConfirmation(schoolId, school['schoolName']);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Aksiyon chip'i oluşturan yardımcı metod
  Widget _buildActionChip({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Aktif/Pasif durumu değiştir
  Future<void> _toggleSchoolStatus(String schoolId, bool newStatus) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator()),
    );

    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .update({'isActive': newStatus});

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus
                ? 'Okul aktif hale getirildi!'
                : 'Okul pasif hale getirildi!',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Hata: $e"), backgroundColor: Colors.red),
      );
    }
  }

  // Özel tarih seçici
  Future<void> _showCustomDatePicker(
    String schoolId,
    DateTime? currentDate,
  ) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: currentDate ?? DateTime.now().add(Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(Duration(days: 3650)), // 10 yıl
      helpText: 'Lisans Bitiş Tarihi Seçin',
      cancelText: 'İptal',
      confirmText: 'Kaydet',
    );

    if (picked != null) {
      _updateLicenseDate(schoolId, picked);
    }
  }

  // Okul silme onay dialogu
  Future<void> _showDeleteConfirmation(
    String schoolId,
    String schoolName,
  ) async {
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
      _deleteSchool(schoolId);
    }
  }

  // Okulu sil
  Future<void> _deleteSchool(String schoolId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
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
      // 1. Okul belgesini sil
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .delete();

      // 2. Yönetici hesabını sil (Cloud Function ile)
      // Not: adminUserId = schoolId olduğu için aynı ID'yi kullanıyoruz
      try {
        final HttpsCallable callable = FirebaseFunctions.instanceFor(
          region: 'us-central1',
        ).httpsCallable('deleteSchoolAndAdmin');

        await callable.call({'schoolId': schoolId});
      } catch (e) {
        print('Yönetici hesabı silinemedi (opsiyonel): $e');
        // Okul belgesi zaten silindi, devam et
      }

      Navigator.pop(context); // Loading dialog'unu kapat
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Okul başarıyla silindi!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      Navigator.pop(context); // Loading dialog'unu kapat
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // Lisans tarihini güncelle
  Future<void> _updateLicenseDate(String schoolId, DateTime newDate) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator()),
    );

    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .update({
            'licenseExpiresAt': Timestamp.fromDate(newDate),
            'isActive': true,
          });

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Lisans tarihi ${DateFormat('dd.MM.yyyy').format(newDate)} olarak güncellendi!',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Hata: $e"), backgroundColor: Colors.red),
      );
    }
  }

  // --- 2. LİSANS YENİLEME FONKSİYONU GÜNCELLENDİ (BÖLGE EKLENDİ) ---
  Future<void> _extendLicense(String schoolId, int daysToAdd) async {
    // Yükleniyor dialog'u göster
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator()),
    );

    try {
      // 'extendLicense' isimli YENİ bulut fonksiyonumuzu çağırıyoruz
      final HttpsCallable callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('extendLicense');

      final result = await callable.call({
        'schoolId': schoolId,
        'daysToAdd': daysToAdd,
      });

      Navigator.pop(context); // Yükleniyor dialog'unu kapat
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.data['message'] ?? 'Lisans başarıyla güncellendi!',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      Navigator.pop(context); // Yükleniyor dialog'unu kapat
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Hata: ${e.message} (Kod: ${e.code})"),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      Navigator.pop(context); // Yükleniyor dialog'unu kapat
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Bilinmeyen bir hata oluştu: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // --- 3. YENİ FONKSİYON: MODÜL DÜZENLEME PENCERESİ ---
  // Modül isimlerini (add_school_screen'den kopyaladık)
  final Map<String, String> _moduleNames = {
    'ogrenci_yonetimi': 'Öğrenci Yönetimi',
    'devamsizlik': 'Devamsızlık Takibi',
    'not_sistemi': 'Not Sistemi ve Karne',
    'finans': 'Finans ve Muhasebe',
    'iletisim': 'Duyuru ve İletişim',
    'yemek_listesi': 'Yemek Listesi',
  };

  void _showModuleEditorDialog(DocumentSnapshot schoolDoc) {
    Map<String, dynamic> schoolData = schoolDoc.data() as Map<String, dynamic>;
    // Mevcut modülleri bir Set'e al (daha hızlı kontrol için)
    Set<String> currentModules = Set<String>.from(
      schoolData['activeModules'] ?? [],
    );
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) {
        // Checkbox'ların durumunu yönetmek için StatefulBuilder kullanıyoruz
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text("${schoolData['schoolName']} Modülleri"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _moduleNames.keys.map((String key) {
                    return CheckboxListTile(
                      title: Text(_moduleNames[key]!),
                      value: currentModules.contains(key),
                      onChanged: (bool? value) {
                        setDialogState(() {
                          if (value == true) {
                            currentModules.add(key);
                          } else {
                            currentModules.remove(key);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  child: Text("İptal"),
                  onPressed: () => Navigator.pop(context),
                ),
                ElevatedButton(
                  child: isLoading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text("Kaydet"),
                  onPressed: isLoading
                      ? null
                      : () async {
                          setDialogState(() => isLoading = true);

                          try {
                            // 'updateSchoolModules' fonksiyonunu çağır
                            final HttpsCallable callable =
                                FirebaseFunctions.instanceFor(
                                  region: 'us-central1',
                                ).httpsCallable('updateSchoolModules');

                            await callable.call({
                              'schoolId': schoolDoc.id,
                              'activeModules': currentModules
                                  .toList(), // Listeye çevir
                            });

                            if (mounted) {
                              Navigator.pop(context); // Dialog'u kapat
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("Modüller güncellendi!"),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            // --- HATA MESAJINI DETAYLANDIRMA ---
                            String errorMessage = e.toString();
                            if (e is FirebaseFunctionsException) {
                              errorMessage =
                                  "Hata: ${e.message} (Kod: ${e.code})";
                            }
                            // --- GÜNCELLEME BİTTİ ---

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(errorMessage),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setDialogState(() => isLoading = false);
                            }
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }
  // --- YENİ FONKSİYON BİTTİ ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Text(
          'Okul Yönetimi',
          style: TextStyle(
            color: Colors.grey.shade900,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.logout_outlined, color: Colors.red),
            tooltip: 'Çıkış Yap',
            onPressed: _logout,
          ),
        ],
      ),
      body: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: 1200),
          padding: EdgeInsets.all(16.0),
          // StreamBuilder ile veritabanını canlı dinle
          child: StreamBuilder<QuerySnapshot>(
            stream: _schoolsStream,
            builder:
                (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
                  // Hata varsa
                  if (snapshot.hasError) {
                    print("Hata: ${snapshot.error}");
                    return Center(
                      child: Text('Veriler yüklenirken bir hata oluştu.'),
                    );
                  }
                  // Yükleniyorsa
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }
                  // Veri yoksa
                  if (snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.school_outlined,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Henüz hiç okul eklenmemiş.',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // İstatistikleri hesapla
                  int totalSchools = snapshot.data!.docs.length;
                  int activeSchools = 0;
                  int passiveSchools = 0;
                  int totalStudents = 0;
                  int activeStudents = 0;
                  int passiveStudents = 0;

                  for (var doc in snapshot.data!.docs) {
                    Map<String, dynamic> school =
                        doc.data() as Map<String, dynamic>;
                    bool isActive = school['isActive'] ?? false;

                    if (isActive) {
                      activeSchools++;
                    } else {
                      passiveSchools++;
                    }

                    // Öğrenci sayılarını al (eğer varsa)
                    int schoolTotalStudents = school['totalStudents'] ?? 0;
                    int schoolActiveStudents = school['activeStudents'] ?? 0;
                    int schoolPassiveStudents = school['passiveStudents'] ?? 0;

                    totalStudents += schoolTotalStudents;
                    activeStudents += schoolActiveStudents;
                    passiveStudents += schoolPassiveStudents;
                  }

                  // Veri geldiyse, istatistikler ve listeyi oluştur
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final bool isNarrow = constraints.maxWidth < 900;
                      
                      return ListView(
                        children: [
                          // Dar ekranlarda Tab Seçici
                          if (isNarrow) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _buildTabButton(
                                      'İstatistikler',
                                      0,
                                      Icons.bar_chart,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: _buildTabButton(
                                      'Okullar',
                                      1,
                                      Icons.school,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          
                          // İstatistik Kartları (geniş ekranda her zaman, dar ekranda seçiliyse göster)
                          if (!isNarrow || _selectedTabIndex == 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 24.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!isNarrow)
                                    Text(
                                      'İstatistikler',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  if (!isNarrow) SizedBox(height: 16),
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                // Ekran genişliğine göre sütun sayısı belirle
                                int crossAxisCount = 3; // Varsayılan 3 sütun
                                double childAspectRatio = 2.2; // Daha yüksek kartlar
                                
                                if (constraints.maxWidth < 900) {
                                  crossAxisCount = 2; // Orta ekran: 2 sütun
                                  childAspectRatio = 2.0;
                                }
                                if (constraints.maxWidth < 600) {
                                  crossAxisCount = 1; // Küçük ekran: 1 sütun
                                  childAspectRatio = 3.0;
                                }
                                
                                return GridView.count(
                                  crossAxisCount: crossAxisCount,
                                  shrinkWrap: true,
                                  physics: NeverScrollableScrollPhysics(),
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: childAspectRatio,
                                  children: [
                                    _buildStatCard(
                                      'Toplam Okul',
                                      totalSchools.toString(),
                                      Icons.school,
                                      Colors.blue,
                                    ),
                                    _buildStatCard(
                                      'Aktif Okul',
                                      activeSchools.toString(),
                                      Icons.check_circle,
                                      Colors.green,
                                    ),
                                    _buildStatCard(
                                      'Pasif Okul',
                                      passiveSchools.toString(),
                                      Icons.cancel,
                                      Colors.red,
                                    ),
                                    _buildStatCard(
                                      'Toplam Öğrenci',
                                      totalStudents.toString(),
                                      Icons.people,
                                      Colors.purple,
                                    ),
                                    _buildStatCard(
                                      'Aktif Öğrenci',
                                      activeStudents.toString(),
                                      Icons.person_outline,
                                      Colors.teal,
                                    ),
                                    _buildStatCard(
                                      'Pasif Öğrenci',
                                      passiveStudents.toString(),
                                      Icons.person_off_outlined,
                                      Colors.orange,
                                    ),
                                  ],
                                );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          
                          // Okullar Bölümü (geniş ekranda her zaman, dar ekranda seçiliyse göster)
                          if (!isNarrow || _selectedTabIndex == 1) ...[
                            // Okullar Başlığı
                            if (!isNarrow)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
                                child: Text(
                                  'Okullar',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            // Okul Listesi
                            ...snapshot.data!.docs.map((DocumentSnapshot document) {
                              return _buildSchoolCard(document);
                            }).toList(),
                          ],
                        ],
                      );
                    },
                  );
                },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToAddSchool,
        icon: Icon(Icons.add),
        label: Text('Yeni Okul Ekle'),
      ),
    );
  }

  // Tab butonu oluşturan yardımcı metod
  Widget _buildTabButton(String label, int index, IconData icon) {
    final bool isSelected = _selectedTabIndex == index;
    
    return InkWell(
      onTap: () {
        setState(() {
          _selectedTabIndex = index;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).primaryColor
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).primaryColor
                : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey.shade700,
              size: 20,
            ),
            SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey.shade700,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // İstatistik kartı oluşturan yardımcı metod
  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double w = constraints.maxWidth;
            
            // Daha hassas responsive boyutlandırma
            final double iconSize = w < 120 ? 24 : (w < 180 ? 28 : 36);
            final double valueSize = w < 120 ? 18 : (w < 180 ? 22 : 28);
            final double titleSize = w < 120 ? 11 : (w < 180 ? 12 : 14);
            final double spacing = w < 120 ? 6 : 8;

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: iconSize, color: color),
                SizedBox(height: spacing),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: valueSize,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
                SizedBox(height: spacing - 2),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: titleSize,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // --- 3. OKUL KARTINI LİSANS BİLGİSİNİ GÖSTERECEK ŞEKİLDE GÜNCELLE ---
  Widget _buildSchoolCard(DocumentSnapshot document) {
    Map<String, dynamic> school = document.data()! as Map<String, dynamic>;
    bool isActive = school['isActive'] ?? false;

    // Lisans tarihini al ve formatla
    Timestamp? expiresAtStamp = school['licenseExpiresAt'];
    String expiresAtFormatted = "Lisans tarihi yok";
    bool isExpired = false;
    if (expiresAtStamp != null) {
      DateTime expiresAtDate = expiresAtStamp.toDate();
      expiresAtFormatted =
          "Lisans Bitişi: ${DateFormat('dd.MM.yyyy').format(expiresAtDate)}";
      // Süresi geçmiş mi kontrol et
      if (expiresAtDate.isBefore(DateTime.now())) {
        isExpired = true;
      }
    }

    return Card(
      margin: EdgeInsets.symmetric(vertical: 8.0),
      child: InkWell(
        // Karta tıklayınca düzenleme ekranını aç
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddSchoolScreen(
                schoolId: document.id,
                schoolData: school,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12.0),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Dar ekranlarda farklı layout
              final bool isNarrow = constraints.maxWidth < 600;
              
              if (isNarrow) {
                // Mobil/dar ekran layout: Dikey
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                          child: Icon(
                            Icons.business,
                            size: 20,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                school['schoolName'] ?? 'İsimsiz Okul',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (school['institutionId'] != null) ...[
                                SizedBox(height: 4),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    school['institutionId'],
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        SizedBox(width: 8),
                        Chip(
                          label: Text(
                            isActive ? 'Aktif' : 'Pasif',
                            style: TextStyle(
                              color: isActive ? Colors.green.shade800 : Colors.red.shade800,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          backgroundColor: isActive ? Colors.green.shade100 : Colors.red.shade100,
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 44.0),
                      child: Text(
                        expiresAtFormatted,
                        style: TextStyle(
                          fontSize: 12,
                          color: isExpired ? Colors.red : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                );
              }
              
              // Geniş ekran layout: Yatay (orijinal)
              return Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                    child: Icon(
                      Icons.business,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              school['schoolName'] ?? 'İsimsiz Okul',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (school['institutionId'] != null) ...[
                              SizedBox(width: 8),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  school['institutionId'],
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: 4),
                        Text(
                          expiresAtFormatted,
                          style: TextStyle(
                            fontSize: 13,
                            color: isExpired ? Colors.red : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  Chip(
                    label: Text(
                      isActive ? 'Aktif' : 'Pasif',
                      style: TextStyle(
                        color: isActive ? Colors.green.shade800 : Colors.red.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    backgroundColor: isActive ? Colors.green.shade100 : Colors.red.shade100,
                    padding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                  SizedBox(width: 16),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey.shade400,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
