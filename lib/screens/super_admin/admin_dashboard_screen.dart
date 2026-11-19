import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart'; // Yeni fonksiyonlar için
import 'package:intl/intl.dart'; // Tarih formatlamak için
import 'add_school_screen.dart';
import 'admin_login_screen.dart';
import '../admin/data_encryption_screen.dart';
import 'package:edukn/widgets/safe_stream_builder.dart';
import '../../services/splash/splash_service.dart';
import '../../constants/turkey_address_data.dart';
import '../../services/school_module_guard.dart';
import '../../widgets/super_admin/school_module_hierarchy_selector.dart';
import 'assessment/central_assessment_dashboard_screen.dart';
import 'store/hq_store_management_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  _AdminDashboardScreenState createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Okul verilerini 'schools' koleksiyonundan canlı olarak dinle
  Stream<QuerySnapshot>? _schoolsStream;
  bool _authReady = false;

  // Öğrenci sayıları her tuş vuruşunda yeniden çekilmemesi için önbellekte tutulur
  int _cachedTotalStudents = 0;
  int _cachedActiveStudents = 0;
  Map<String, int> _activeStudentCountByInst = <String, int>{};
  bool _studentsStatsLoading = false;

  // Dar ekranlarda hangi sekme gösterilsin
  int _selectedTabIndex = 0; // 0: İstatistikler, 1: Okullar
  // Süper Admin üst modül sekmesi: 0 = Okullar, 1 = Merkezi Ölçme Değerlendirme, 2 = Mağaza Yönetimi
  int _activeSuperSection = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SplashService.hide();
    });
    _initSuperAdminSession();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initSuperAdminSession() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      try {
        user = await FirebaseAuth.instance
            .authStateChanges()
            .firstWhere((u) => u != null)
            .timeout(const Duration(milliseconds: 2500));
      } catch (_) {
        user = FirebaseAuth.instance.currentUser;
      }
    }
    if (!mounted) return;
    if (user == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
      );
      return;
    }
    try {
      await user.getIdToken();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _authReady = true;
      _schoolsStream = FirebaseFirestore.instance
          .collection('schools')
          .orderBy('createdAt', descending: true)
          .snapshots();
    });
    _loadStudentCounts();
  }

  Future<void> _loadStudentCounts() async {
    if (_studentsStatsLoading) return;
    if (mounted) setState(() => _studentsStatsLoading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('students')
          .get();
      int total = 0;
      int active = 0;
      final byInst = <String, int>{};
      for (final doc in snap.docs) {
        total++;
        final data = doc.data();
        final isAct = data['isActive'] != false;
        if (isAct) {
          active++;
          final inst = (data['institutionId'] ?? '')
              .toString()
              .trim()
              .toUpperCase();
          if (inst.isNotEmpty) {
            byInst[inst] = (byInst[inst] ?? 0) + 1;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _cachedTotalStudents = total;
        _cachedActiveStudents = active;
        _activeStudentCountByInst = byInst;
        _studentsStatsLoading = false;
      });
    } catch (e) {
      debugPrint('Öğrenci istatistiği yükleme uyarısı: $e');
      if (mounted) setState(() => _studentsStatsLoading = false);
    }
  }

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('Logout error: $e');
    }
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AdminLoginScreen()),
      );
    }
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
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
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

      if (mounted) Navigator.pop(context);
      if (mounted)
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
      if (mounted) Navigator.pop(context);
      if (mounted)
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
        debugPrint('Yönetici hesabı silinemedi (opsiyonel): $e');
        // Okul belgesi zaten silindi, devam et
      }

      Navigator.pop(context); // Loading dialog'unu kapat
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Okul başarıyla silindi!'),
            backgroundColor: Colors.green,
          ),
        );
    } catch (e) {
      Navigator.pop(context); // Loading dialog'unu kapat
      if (mounted)
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

      if (mounted) Navigator.pop(context);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Lisans tarihi ${DateFormat('dd.MM.yyyy').format(newDate)} olarak güncellendi!',
            ),
            backgroundColor: Colors.green,
          ),
        );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted)
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
      if (mounted)
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
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Hata: ${e.message} (Kod: ${e.code})"),
            backgroundColor: Colors.red,
          ),
        );
    } catch (e) {
      Navigator.pop(context); // Yükleniyor dialog'unu kapat
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Bilinmeyen bir hata oluştu: $e"),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  // --- 3. YENİ FONKSİYON: HİYERARŞİK MODÜL DÜZENLEME PENCERESİ ---
  void _showModuleEditorDialog(DocumentSnapshot schoolDoc) {
    final Map<String, dynamic> schoolData = Map<String, dynamic>.from(
      schoolDoc.data() as Map<String, dynamic>,
    );
    Set<String> activeModules = SchoolModuleGuard.extractActiveModules(
      schoolData,
    );
    Set<String> disabledSubModules =
        SchoolModuleGuard.extractDisabledSubModules(schoolData);
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 920,
                  maxHeight: 760,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.tune_rounded,
                              color: Colors.indigo,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${schoolData['schoolName'] ?? 'Okul'} — Modül & Alt Başlık Yetkileri',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'Genel başlıkları ve alt başlıkları okul lisansına göre açıp kapatabilirsiniz.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Expanded(
                        child: SingleChildScrollView(
                          child: SchoolModuleHierarchySelector(
                            activeModules: activeModules,
                            disabledSubModules: disabledSubModules,
                            compact: true,
                            onChanged: (nextActive, nextDisabled) {
                              setDialogState(() {
                                activeModules = nextActive;
                                disabledSubModules = nextDisabled;
                              });
                            },
                          ),
                        ),
                      ),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Vazgeç'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            icon: isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save_rounded, size: 18),
                            label: const Text('Yetkileri Kaydet'),
                            onPressed: isLoading
                                ? null
                                : () async {
                                    setDialogState(() => isLoading = true);
                                    try {
                                      await FirebaseFirestore.instance
                                          .collection('schools')
                                          .doc(schoolDoc.id)
                                          .update({
                                            'activeModules': activeModules
                                                .toList(),
                                            'disabledSubModules':
                                                disabledSubModules.toList(),
                                            'updatedAt':
                                                FieldValue.serverTimestamp(),
                                          });
                                      try {
                                        final callable =
                                            FirebaseFunctions.instanceFor(
                                              region: 'us-central1',
                                            ).httpsCallable(
                                              'updateSchoolModules',
                                            );
                                        await callable.call({
                                          'schoolId': schoolDoc.id,
                                          'activeModules': activeModules
                                              .toList(),
                                          'disabledSubModules':
                                              disabledSubModules.toList(),
                                        });
                                      } catch (_) {}

                                      if (mounted) {
                                        Navigator.pop(dialogContext);
                                        ScaffoldMessenger.of(
                                          this.context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Okul modül ve alt başlık yetkileri güncellendi!',
                                            ),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(
                                          this.context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Güncelleme hatası: $e',
                                            ),
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
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
  // --- YENİ FONKSİYON BİTTİ ---

  Widget _buildSuperSectionNav() {
    final items = [
      (
        index: 0,
        label: 'Okul & Lisans Yönetimi',
        icon: Icons.school_rounded,
        color: Colors.indigo,
      ),
      (
        index: 1,
        label: 'Ölçme Değerlendirme (Genel Merkez)',
        icon: Icons.analytics_rounded,
        color: Colors.teal,
      ),
      (
        index: 2,
        label: 'Mağaza & Sipariş Yönetimi',
        icon: Icons.storefront_rounded,
        color: Colors.deepOrange,
      ),
    ];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1360),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: items.map((item) {
                final selected = _activeSuperSection == item.index;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () =>
                        setState(() => _activeSuperSection = item.index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: selected ? item.color : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? item.color : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            item.icon,
                            size: 19,
                            color: selected ? Colors.white : item.color,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item.label,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: selected
                                  ? Colors.white
                                  : const Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sectionTitles = [
      'Genel Merkez — Okul & Lisans Yönetimi',
      'Genel Merkez — Ölçme Değerlendirme',
      'Genel Merkez — Mağaza Yönetimi',
    ];
    return Scaffold(
      appBar: EduknAppBar(
        title: sectionTitles[_activeSuperSection],
        actions: [
          if (_activeSuperSection == 0)
            IconButton(
              icon: _studentsStatsLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, color: Colors.indigo),
              tooltip: 'İstatistikleri Yenile',
              onPressed: _studentsStatsLoading ? null : _loadStudentCounts,
            ),
          IconButton(
            icon: Icon(Icons.lock_outline_rounded, color: Colors.indigo),
            tooltip: 'Veri Şifreleme',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DataEncryptionScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.logout_outlined, color: Colors.red),
            tooltip: 'Çıkış Yap',
            onPressed: _logout,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSuperSectionNav(),
          Expanded(
            child: !_authReady
                ? const Center(child: CircularProgressIndicator())
                : _activeSuperSection == 1
                ? const CentralAssessmentDashboardScreen(showAppBar: false)
                : _activeSuperSection == 2
                ? const HqStoreManagementScreen(showAppBar: false)
                : Center(
                    child: Container(
                      constraints: BoxConstraints(maxWidth: 1200),
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          // 🔍 Arama Çubuğu
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'Okul adı veya Kurum ID ile ara...',
                                prefixIcon: Icon(Icons.search),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(Icons.clear),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() {
                                            _searchQuery = '';
                                          });
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 0,
                                ),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _searchQuery = value.toLowerCase();
                                });
                              },
                            ),
                          ),
                          Expanded(
                            child: SafeStreamBuilder<QuerySnapshot>(
                              stream: _schoolsStream,
                              builder:
                                  (
                                    BuildContext context,
                                    AsyncSnapshot<QuerySnapshot> snapshot,
                                  ) {
                                    // Hata varsa
                                    if (snapshot.hasError) {
                                      debugPrint("Hata: ${snapshot.error}");
                                      return Center(
                                        child: Text(
                                          'Veriler yüklenirken bir hata oluştu.',
                                        ),
                                      );
                                    }
                                    // Yükleniyorsa
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return Center(
                                        child: CircularProgressIndicator(),
                                      );
                                    }
                                    // Veri yoksa
                                    if (snapshot.data!.docs.isEmpty) {
                                      return Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
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

                                    // İstatistikleri önbellekten anlık hesapla (arama sırasında sıfır kasma)
                                    final int totalSchools =
                                        snapshot.data!.docs.length;
                                    int activeSchools = 0;
                                    int passiveSchools = 0;

                                    for (final doc in snapshot.data!.docs) {
                                      final school =
                                          doc.data() as Map<String, dynamic>;
                                      final bool isActive =
                                          school['isActive'] ?? false;
                                      if (isActive) {
                                        activeSchools++;
                                      } else {
                                        passiveSchools++;
                                      }
                                    }

                                    final int totalStudents =
                                        _cachedTotalStudents;
                                    final int activeStudents =
                                        _cachedActiveStudents;
                                    final int passiveStudents =
                                        totalStudents - activeStudents;

                                    return LayoutBuilder(
                                      builder: (context, constraints) {
                                        final bool isNarrow =
                                            constraints.maxWidth < 900;

                                        final filteredDocs = snapshot.data!.docs
                                            .where((doc) {
                                              if (_searchQuery.isEmpty) {
                                                return true;
                                              }
                                              final data =
                                                  doc.data()
                                                      as Map<String, dynamic>;
                                              final schoolName =
                                                  (data['schoolName'] ?? '')
                                                      .toString()
                                                      .toLowerCase();
                                              final institutionId =
                                                  (data['institutionId'] ?? '')
                                                      .toString()
                                                      .toLowerCase();
                                              final city = (data['city'] ?? '')
                                                  .toString()
                                                  .toLowerCase();
                                              return schoolName.contains(
                                                    _searchQuery,
                                                  ) ||
                                                  institutionId.contains(
                                                    _searchQuery,
                                                  ) ||
                                                  city.contains(_searchQuery);
                                            })
                                            .toList();

                                        return ListView(
                                          children: [
                                            if (isNarrow) ...[
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 16.0,
                                                ),
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      child: _buildTabButton(
                                                        'İstatistikler',
                                                        0,
                                                        Icons.bar_chart,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: _buildTabButton(
                                                        'Okullar (${filteredDocs.length})',
                                                        1,
                                                        Icons.school,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],

                                            if (!isNarrow ||
                                                _selectedTabIndex == 0)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 24.0,
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    if (!isNarrow)
                                                      const Text(
                                                        'İstatistikler',
                                                        style: TextStyle(
                                                          fontSize: 22,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    if (!isNarrow)
                                                      const SizedBox(
                                                        height: 14,
                                                      ),
                                                    LayoutBuilder(
                                                      builder: (context, statConstraints) {
                                                        int crossAxisCount = 3;
                                                        double
                                                        childAspectRatio = 1.95;

                                                        if (statConstraints
                                                                .maxWidth <
                                                            900) {
                                                          crossAxisCount = 2;
                                                          childAspectRatio =
                                                              1.85;
                                                        }
                                                        if (statConstraints
                                                                .maxWidth <
                                                            560) {
                                                          crossAxisCount = 2;
                                                          childAspectRatio =
                                                              1.55;
                                                        }
                                                        if (statConstraints
                                                                .maxWidth <
                                                            380) {
                                                          crossAxisCount = 1;
                                                          childAspectRatio =
                                                              2.6;
                                                        }

                                                        return GridView.count(
                                                          crossAxisCount:
                                                              crossAxisCount,
                                                          shrinkWrap: true,
                                                          physics:
                                                              const NeverScrollableScrollPhysics(),
                                                          mainAxisSpacing: 12,
                                                          crossAxisSpacing: 12,
                                                          childAspectRatio:
                                                              childAspectRatio,
                                                          children: [
                                                            _buildStatCard(
                                                              'Toplam Okul',
                                                              totalSchools
                                                                  .toString(),
                                                              Icons.school,
                                                              Colors.blue,
                                                            ),
                                                            _buildStatCard(
                                                              'Aktif Okul',
                                                              activeSchools
                                                                  .toString(),
                                                              Icons
                                                                  .check_circle,
                                                              Colors.green,
                                                            ),
                                                            _buildStatCard(
                                                              'Pasif Okul',
                                                              passiveSchools
                                                                  .toString(),
                                                              Icons.cancel,
                                                              Colors.red,
                                                            ),
                                                            _buildStatCard(
                                                              'Toplam Öğrenci',
                                                              _studentsStatsLoading &&
                                                                      totalStudents ==
                                                                          0
                                                                  ? '...'
                                                                  : totalStudents
                                                                        .toString(),
                                                              Icons.people,
                                                              Colors.purple,
                                                            ),
                                                            _buildStatCard(
                                                              'Aktif Öğrenci',
                                                              _studentsStatsLoading &&
                                                                      totalStudents ==
                                                                          0
                                                                  ? '...'
                                                                  : activeStudents
                                                                        .toString(),
                                                              Icons
                                                                  .person_outline,
                                                              Colors.teal,
                                                            ),
                                                            _buildStatCard(
                                                              'Pasif Öğrenci',
                                                              _studentsStatsLoading &&
                                                                      totalStudents ==
                                                                          0
                                                                  ? '...'
                                                                  : passiveStudents
                                                                        .toString(),
                                                              Icons
                                                                  .person_off_outlined,
                                                              Colors.orange,
                                                            ),
                                                          ],
                                                        );
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),

                                            if (!isNarrow ||
                                                _selectedTabIndex == 1) ...[
                                              if (!isNarrow)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 8.0,
                                                        bottom: 14.0,
                                                      ),
                                                  child: Text(
                                                    'Okullar (${filteredDocs.length})',
                                                    style: const TextStyle(
                                                      fontSize: 22,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              if (filteredDocs.isEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.all(
                                                    32,
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                      'Aramanızla eşleşen okul bulunamadı.',
                                                      style: TextStyle(
                                                        color: Colors
                                                            .grey
                                                            .shade600,
                                                      ),
                                                    ),
                                                  ),
                                                )
                                              else
                                                ...filteredDocs.map(
                                                  _buildSchoolCard,
                                                ),
                                            ],
                                          ],
                                        );
                                      },
                                    );
                                  },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: _activeSuperSection == 0
          ? FloatingActionButton.extended(
              onPressed: _navigateToAddSchool,
              icon: Icon(Icons.add),
              label: Text('Yeni Okul Ekle'),
            )
          : null,
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

            return FittedBox(
              fit: BoxFit.scaleDown,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: w > 16 ? w - 8 : w),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: iconSize, color: color),
                    SizedBox(height: spacing),
                    Text(
                      value,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: valueSize,
                        fontWeight: FontWeight.bold,
                        color: color,
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
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // --- 3. OKUL KARTINI LİSANS BİLGİSİNİ GÖSTERECEK ŞEKİLDE GÜNCELLE ---
  Widget _buildSchoolCard(DocumentSnapshot document) {
    final Map<String, dynamic> school =
        document.data()! as Map<String, dynamic>;
    final bool isActive = school['isActive'] ?? false;

    final Timestamp? expiresAtStamp = school['licenseExpiresAt'];
    String expiresAtFormatted = 'Lisans tarihi yok';
    bool isExpired = false;
    if (expiresAtStamp != null) {
      final DateTime expiresAtDate = expiresAtStamp.toDate();
      expiresAtFormatted =
          'Lisans Bitişi: ${DateFormat('dd.MM.yyyy').format(expiresAtDate)}';
      if (expiresAtDate.isBefore(DateTime.now())) {
        isExpired = true;
      }
    }

    final cityStr = (school['city'] ?? '').toString().trim();
    final regionStr = (school['region'] ?? TurkeyAddressData.getRegion(cityStr))
        .toString();
    final quotaVal = ((school['studentQuota'] ?? 0) as num).toInt();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  AddSchoolScreen(schoolId: document.id, schoolData: school),
            ),
          );
          _loadStudentCounts();
        },
        borderRadius: BorderRadius.circular(12.0),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bool isNarrow = constraints.maxWidth < 760;

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Theme.of(
                            context,
                          ).primaryColor.withValues(alpha: 0.1),
                          child: Icon(
                            Icons.business,
                            size: 20,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (school['schoolName'] ?? 'İsimsiz Okul')
                                    .toString(),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (school['institutionId'] != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        school['institutionId'].toString(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue.shade900,
                                        ),
                                      ),
                                    ),
                                  if (cityStr.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.teal.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: Colors.teal.shade100,
                                        ),
                                      ),
                                      child: Text(
                                        '$cityStr • $regionStr',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.teal.shade800,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Chip(
                          label: Text(
                            isActive ? 'Aktif' : 'Pasif',
                            style: TextStyle(
                              color: isActive
                                  ? Colors.green.shade800
                                  : Colors.red.shade800,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          backgroundColor: isActive
                              ? Colors.green.shade100
                              : Colors.red.shade100,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          expiresAtFormatted,
                          style: TextStyle(
                            fontSize: 12,
                            color: isExpired
                                ? Colors.red
                                : Colors.grey.shade600,
                          ),
                        ),
                        _buildLocalStudentQuotaInfo(
                          school['institutionId']?.toString(),
                          quotaVal,
                        ),
                      ],
                    ),
                    const Divider(height: 18),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.tune_rounded, size: 16),
                          label: const Text('Modüller'),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: Colors.indigo,
                          ),
                          onPressed: () => _showModuleEditorDialog(document),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(
                            Icons.settings_suggest_rounded,
                            size: 16,
                          ),
                          label: const Text('Lisans & Durum'),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: Colors.blueGrey.shade700,
                          ),
                          onPressed: () => _showManageSchoolDialog(document),
                        ),
                      ],
                    ),
                  ],
                );
              }

              // Geniş ekran layout: Yatay (overflow korumalı)
              return Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Theme.of(
                      context,
                    ).primaryColor.withValues(alpha: 0.1),
                    child: Icon(
                      Icons.business,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                (school['schoolName'] ?? 'İsimsiz Okul')
                                    .toString(),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (school['institutionId'] != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  school['institutionId'].toString(),
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
                        const SizedBox(height: 4),
                        Text(
                          expiresAtFormatted,
                          style: TextStyle(
                            fontSize: 13,
                            color: isExpired
                                ? Colors.red
                                : Colors.grey.shade600,
                          ),
                        ),
                        if (school['adminFullName'] != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.person,
                                size: 14,
                                color: Colors.indigo.shade300,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  school['adminFullName'].toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.indigo.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildLocalStudentQuotaInfo(
                    school['institutionId']?.toString(),
                    quotaVal,
                  ),
                  if (cityStr.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 190),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.teal.shade100),
                        ),
                        child: Text(
                          '$cityStr • $regionStr',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.teal.shade800,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Modülleri & Alt Başlıkları Aç/Kapat',
                    icon: const Icon(Icons.tune_rounded, color: Colors.indigo),
                    onPressed: () => _showModuleEditorDialog(document),
                  ),
                  IconButton(
                    tooltip: 'Hızlı Lisans & Durum Yönetimi',
                    icon: const Icon(
                      Icons.settings_suggest_rounded,
                      color: Colors.blueGrey,
                    ),
                    onPressed: () => _showManageSchoolDialog(document),
                  ),
                  const SizedBox(width: 6),
                  Chip(
                    label: Text(
                      isActive ? 'Aktif' : 'Pasif',
                      style: TextStyle(
                        color: isActive
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    backgroundColor: isActive
                        ? Colors.green.shade100
                        : Colors.red.shade100,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  const SizedBox(width: 10),
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

  // --- YENİ YARDIMCI WIDGET: ÖĞRENCİ SAYISI VE KOTA GÖSTERİCİ (O(1) ÖNBELLEK) ---
  Widget _buildLocalStudentQuotaInfo(String? institutionId, int quota) {
    if (institutionId == null || institutionId.trim().isEmpty) {
      return Text('Kota: $quota');
    }

    final currentCount =
        _activeStudentCountByInst[institutionId.trim().toUpperCase()] ?? 0;

    final bool isNearLimit = quota > 0 && currentCount >= (quota * 0.9);
    final bool isOverLimit = quota > 0 && currentCount >= quota;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.people_outline,
          size: 14,
          color: isOverLimit
              ? Colors.red
              : (isNearLimit ? Colors.orange : Colors.grey.shade600),
        ),
        const SizedBox(width: 4),
        Text(
          '$currentCount / $quota',
          style: TextStyle(
            fontSize: 13,
            fontWeight: isOverLimit ? FontWeight.bold : FontWeight.normal,
            color: isOverLimit
                ? Colors.red
                : (isNearLimit ? Colors.orange : Colors.grey.shade600),
          ),
        ),
      ],
    );
  }
}
