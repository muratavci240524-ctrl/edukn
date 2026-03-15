import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../constants/app_modules.dart';
import '../../firebase_options.dart';
import '../../services/user_permission_service.dart';
// Web için
import 'dart:html' as html show window;

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({Key? key}) : super(key: key);

  @override
  _UserManagementScreenState createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen>
    with SingleTickerProviderStateMixin {
  String? institutionId;
  String? schoolId;
  Map<String, dynamic>? userData; // Giriş yapan kullanıcının verileri
  bool isLoadingPermissions = true;

  // Kullanıcı rolleri (Görevler)
  final Map<String, String> userRoles = {
    'genel_mudur': 'Genel Müdür',
    'mudur': 'Müdür',
    'mudur_yardimcisi': 'Müdür Yardımcısı',
    'ogretmen': 'Öğretmen',
    'personel': 'Personel',
  };

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _getSchoolInfo();
    _loadUserPermissions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Kullanıcı yetkilerini yükle
  Future<void> _loadUserPermissions() async {
    final data = await UserPermissionService.loadUserData();
    if (mounted) {
      setState(() {
        userData = data;
        isLoadingPermissions = false;
      });
    }
  }

  // Kullanıcı yönetimi modülünde düzenleme yetkisi var mı?
  bool _canEditUsers() {
    return UserPermissionService.canEdit('kullanici_yonetimi', userData);
  }

  Future<void> _getSchoolInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final email = user.email!;
      final instId = email.split('@')[1].split('.')[0].toUpperCase();

      // Okul bilgilerini al
      final schoolQuery = await FirebaseFirestore.instance
          .collection('schools')
          .where('institutionId', isEqualTo: instId)
          .limit(1)
          .get();

      if (schoolQuery.docs.isNotEmpty) {
        setState(() {
          institutionId = instId;
          schoolId = schoolQuery.docs.first.id;
        });
      }
    }
  }

  // Firebase Auth kullanıcısı oluştur
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

  void _showAddUserSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _UserFormSheet(
        institutionId: institutionId!,
        schoolId: schoolId!,
        onCreateAuth: _createAuthUser,
      ),
    );
  }

  // Geçici: Admin kullanıcı kaydı oluştur
  Future<void> _createAdminUser() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final adminUserData = {
        'authUserId': currentUser.uid,
        'institutionId': institutionId,
        'schoolId': schoolId,
        'fullName': 'Murat AVCI',
        'username': 'abckoleji',
        'email': currentUser.email,
        'phone': '05452242482',
        'role': 'genel_mudur',
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
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
        'schoolTypes': [],
        'schoolTypePermissions': {},
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .set(adminUserData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Admin kullanıcı kaydı oluşturuldu!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showEditUserSheet(String userId, Map<String, dynamic> userData) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _UserFormSheet(
        institutionId: institutionId!,
        schoolId: schoolId!,
        userId: userId,
        userData: userData,
        onCreateAuth: _createAuthUser,
      ),
    );
  }

  String _formatRole(String? role) {
    if (role == null) return 'Ünvan Girilmedi';
    switch (role.toLowerCase()) {
      case 'genel_mudur':
        return 'GENEL MÜDÜR';
      case 'mudur':
        return 'MÜDÜR';
      case 'mudur_yardimcisi':
        return 'MÜDÜR YARDIMCISI';
      case 'ogretmen':
      case 'teacher':
        return 'ÖĞRETMEN';
      case 'personel':
      case 'staff':
        return 'PERSONEL';
      case 'hr':
        return 'İNSAN KAYNAKLARI';
      case 'muhasebe':
        return 'MUHASEBE';
      case 'satin_alma':
        return 'SATIN ALMA';
      case 'depo':
        return 'DEPO SORUMLUSU';
      case 'destek_hizmetleri':
        return 'DESTEK HİZMETLERİ';
      case 'ogrenci':
      case 'student':
        return 'ÖĞRENCİ';
      case 'veli':
      case 'parent':
        return 'VELİ';
      case 'admin':
        return 'YÖNETİCİ';
      default:
        return role.toUpperCase();
    }
  }

  void _showUserDetails(Map<String, dynamic> data, String userId) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: BoxConstraints(maxHeight: 600, maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.indigo.shade400, Colors.indigo.shade600],
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.white,
                      child: Text(
                        (data['fullName'] ?? 'U')[0].toUpperCase(),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['fullName'] ?? 'İsimsiz',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            _formatRole(data['role']),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Kullanıcı Adı
                      if (data['username'] != null)
                        _buildDetailRow(
                          Icons.account_circle,
                          'Kullanıcı Adı',
                          data['username'],
                        ),

                      // TC Kimlik
                      if (data['tcKimlik'] != null &&
                          data['tcKimlik'].toString().isNotEmpty)
                        _buildDetailRow(
                          Icons.badge,
                          'TC Kimlik',
                          data['tcKimlik'],
                        ),

                      // Telefon
                      if (data['phone'] != null)
                        _buildDetailRow(Icons.phone, 'Telefon', data['phone']),

                      // Email
                      if (data['email'] != null &&
                          data['email'].toString().isNotEmpty)
                        _buildDetailRow(Icons.email, 'E-posta', data['email']),

                      // Durum
                      _buildDetailRow(
                        data['isActive'] == true
                            ? Icons.check_circle
                            : Icons.cancel,
                        'Durum',
                        data['isActive'] == true ? 'Aktif' : 'Pasif',
                        valueColor: data['isActive'] == true
                            ? Colors.green
                            : Colors.red,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: Colors.indigo),
          ),
          SizedBox(width: 12),
          Expanded(
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
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? Colors.grey.shade900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Kullanıcı olarak giriş yap
  Future<void> _loginAsUser(Map<String, dynamic> userData) async {
    try {
      // Onay dialog'u
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.login, color: Colors.green),
              SizedBox(width: 8),
              Text('Kullanıcı Olarak Giriş'),
            ],
          ),
          content: Text(
            '${userData['fullName'] ?? 'Bu kullanıcı'} olarak giriş yapmak istediğinizden emin misiniz?\n\nSayfayı yenileyerek admin hesabınıza geri dönebilirsiniz.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: Text('Giriş Yap'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // Mevcut kullanıcı bilgilerini kaydet (admin backup)
      final currentUser = FirebaseAuth.instance.currentUser;
      final prefs = await SharedPreferences.getInstance();

      print('🔐 Login as user başlatıldı: ${userData['fullName']}');
      print('📧 Email: ${userData['email']}');

      if (currentUser != null) {
        await prefs.setString('admin_backup_email', currentUser.email ?? '');
        print('✅ Admin backup kaydedildi: ${currentUser.email}');
      }

      // Yeni kullanıcı bilgilerini kaydet
      await prefs.setString(
        'impersonated_user_id',
        userData['authUserId'] ?? '',
      );
      await prefs.setString('impersonated_user_email', userData['email'] ?? '');
      await prefs.setString(
        'impersonated_user_name',
        userData['fullName'] ?? '',
      );
      await prefs.setBool('is_impersonating', true);

      // Kaydedilen değerleri kontrol et
      final savedEmail = prefs.getString('impersonated_user_email');
      final savedName = prefs.getString('impersonated_user_name');
      final isImp = prefs.getBool('is_impersonating');
      print('✅ SharedPreferences kaydedildi:');
      print('   - Email: $savedEmail');
      print('   - Name: $savedName');
      print('   - Is Impersonating: $isImp');

      // UserPermissionService cache'ini temizle
      UserPermissionService.clearCache();
      print('🧹 UserPermissionService cache temizlendi');

      // Başarı mesajı göster
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${userData['fullName']} olarak giriş yapılıyor...'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      // Web için sayfayı tamamen yeniden yükle
      if (kIsWeb) {
        await Future.delayed(Duration(milliseconds: 800));
        html.window.location.href = '/#/school-dashboard';
      } else {
        // Mobil için navigation
        await Future.delayed(Duration(milliseconds: 500));
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/school-dashboard',
          (route) => false,
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteUser(
    String userId,
    String userName,
    Map<String, dynamic> userData,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 12),
            Text('Kullanıcıyı Sil'),
          ],
        ),
        content: Text(
          '$userName kullanıcısını silmek istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Sil', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final authUserId = userData['authUserId'] as String?;
      final usersCol = FirebaseFirestore.instance.collection('users');
      final legacyRef = usersCol.doc(userId);
      final authRef = authUserId != null ? usersCol.doc(authUserId) : null;

      final legacySnap = await legacyRef.get();
      final authSnap = authRef != null ? await authRef.get() : null;

      final batch = FirebaseFirestore.instance.batch();
      if (legacySnap.exists) batch.delete(legacyRef);
      if (authSnap != null && authSnap.exists && authRef != null) {
        batch.delete(authRef);
      }

      if (!legacySnap.exists && (authSnap == null || !authSnap.exists)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Silinecek kullanıcı dokümanı bulunamadı.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Kullanıcı silindi!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (institutionId == null || schoolId == null) {
      return Scaffold(
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.indigo),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Kullanıcı Yönetimi',
            style: TextStyle(
              color: Colors.grey.shade900,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.indigo),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Kullanıcı Yönetimi',
          style: TextStyle(
            color: Colors.grey.shade900,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          // Geçici: Admin kullanıcı oluştur butonu
          IconButton(
            icon: Icon(Icons.admin_panel_settings, color: Colors.orange),
            tooltip: 'Admin Kullanıcı Oluştur',
            onPressed: _createAdminUser,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.indigo,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.indigo,
          tabs: [
            Tab(text: 'Yönetim'),
            Tab(text: 'Öğretmen'),
            Tab(text: 'Personel'),
            Tab(text: 'Öğrenci-Veli'),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('institutionId', isEqualTo: institutionId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Hata: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          final users = snapshot.data!.docs;

          if (users.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 80,
                    color: Colors.grey.shade400,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Henüz Kullanıcı Yok',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text('Yeni kullanıcı eklemek için + butonuna tıklayın'),
                  SizedBox(height: 20),
                  // Geçici: Admin kullanıcı oluştur butonu
                  ElevatedButton(
                    onPressed: _createAdminUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                    ),
                    child: Text(
                      'Admin Kullanıcı Oluştur (Geçici)',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            );
          }

          // Kullanıcıları sırala: Admin önce, sonra diğerleri
          final sortedUsers = users.toList();
          sortedUsers.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aRole = aData['role'] ?? '';
            final bRole = bData['role'] ?? '';

            // Admin rolleri önce
            if ((aRole == 'genel_mudur' || aRole == 'mudur') &&
                !(bRole == 'genel_mudur' || bRole == 'mudur')) {
              return -1;
            } else if (!(aRole == 'genel_mudur' || aRole == 'mudur') &&
                (bRole == 'genel_mudur' || bRole == 'mudur')) {
              return 1;
            }

            // Aynı seviyedeyse alfabetik sırala
            return (aData['fullName'] ?? '').compareTo(bData['fullName'] ?? '');
          });

          return TabBarView(
            controller: _tabController,
            children: [
              _buildUserList(sortedUsers, 'management'),
              _buildUserList(sortedUsers, 'teacher'),
              _buildUserList(sortedUsers, 'staff'),
              _buildUserList(sortedUsers, 'student_parent'),
            ],
          );
        },
      ),

      floatingActionButton: _canEditUsers()
          ? FloatingActionButton.extended(
              onPressed: _showAddUserSheet,
              backgroundColor: Colors.indigo,
              icon: Icon(Icons.person_add, color: Colors.white),
              label: Text(
                'Kullanıcı Ekle',
                style: TextStyle(color: Colors.white),
              ),
            )
          : null,
    );
  }

  Widget _buildUserList(List<QueryDocumentSnapshot> allUsers, String category) {
    final filteredUsers = allUsers.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final role = (data['role'] ?? '').toString().toLowerCase();

      switch (category) {
        case 'management':
          return [
            'genel_mudur',
            'mudur',
            'mudur_yardimcisi',
            'admin',
            'hr',
            'muhasebe',
            'satin_alma',
            'depo',
            'destek_hizmetleri',
          ].contains(role);
        case 'teacher':
          return ['ogretmen', 'teacher'].contains(role);
        case 'staff':
          return ['personel', 'staff'].contains(role);
        case 'student_parent':
          return ['ogrenci', 'student', 'veli', 'parent'].contains(role);
        default:
          return false;
      }
    }).toList();

    if (filteredUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 64, color: Colors.grey.shade300),
            SizedBox(height: 16),
            Text(
              'Bu kategoride kullanıcı bulunamadı',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: filteredUsers.length,
      itemBuilder: (context, index) {
        final doc = filteredUsers[index];
        final data = doc.data() as Map<String, dynamic>;
        final role = data['role'] ?? 'staff';
        final isAdmin = role == 'genel_mudur' || role == 'mudur';

        return Card(
          margin: EdgeInsets.only(bottom: 12),
          elevation: isAdmin ? 4 : 0,
          color: isAdmin ? Colors.orange.shade50 : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isAdmin ? Colors.orange.shade300 : Colors.grey.shade200,
              width: isAdmin ? 2 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _showUserDetails(data, doc.id),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isAdmin
                            ? [Colors.orange.shade400, Colors.orange.shade600]
                            : [Colors.indigo.shade400, Colors.indigo.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: (isAdmin ? Colors.orange : Colors.indigo)
                              .withOpacity(0.3),
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        (data['fullName'] ?? 'U')[0].toUpperCase(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 16),

                  // Ad ve Görev
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['fullName'] ?? 'İsimsiz',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade900,
                          ),
                        ),
                        SizedBox(height: 6),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isAdmin
                                  ? [
                                      Colors.orange.shade50,
                                      Colors.orange.shade100,
                                    ]
                                  : [Colors.blue.shade50, Colors.blue.shade100],
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isAdmin
                                  ? Colors.orange.shade200
                                  : Colors.blue.shade200,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isAdmin
                                    ? Icons.admin_panel_settings
                                    : Icons.work_outline,
                                size: 14,
                                color: isAdmin
                                    ? Colors.orange.shade700
                                    : Colors.blue.shade700,
                              ),
                              SizedBox(width: 4),
                              Text(
                                _formatRole(role),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isAdmin
                                      ? Colors.orange.shade900
                                      : Colors.blue.shade900,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 3 Nokta Menü
                  PopupMenuButton<String>(
                    icon: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.more_vert,
                        color: Colors.grey.shade700,
                        size: 20,
                      ),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onSelected: (value) async {
                      if (value == 'details') {
                        _showUserDetails(data, doc.id);
                      } else if (value == 'edit') {
                        _showEditUserSheet(doc.id, data);
                      } else if (value == 'login_as') {
                        await _loginAsUser(data);
                      } else if (value == 'delete') {
                        _deleteUser(
                          doc.id,
                          data['fullName'] ?? 'Bu kullanıcı',
                          data,
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'details',
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 20,
                              color: Colors.indigo,
                            ),
                            SizedBox(width: 12),
                            Text('Detayları Gör'),
                          ],
                        ),
                      ),
                      if (_canEditUsers())
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 20, color: Colors.blue),
                              SizedBox(width: 12),
                              Text('Düzenle'),
                            ],
                          ),
                        ),
                      PopupMenuItem(
                        value: 'login_as',
                        child: Row(
                          children: [
                            Icon(Icons.login, size: 20, color: Colors.green),
                            SizedBox(width: 12),
                            Text('Kullanıcı Olarak Giriş Yap'),
                          ],
                        ),
                      ),
                      if (_canEditUsers()) ...[
                        PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, size: 20, color: Colors.red),
                              SizedBox(width: 12),
                              Text('Sil'),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// Kullanıcı Form Sheet - Stepper Yapısı
class _UserFormSheet extends StatefulWidget {
  final String institutionId;
  final String schoolId;
  final String? userId;
  final Map<String, dynamic>? userData;
  final Future<String?> Function(String, String) onCreateAuth;

  const _UserFormSheet({
    required this.institutionId,
    required this.schoolId,
    required this.onCreateAuth,
    this.userId,
    this.userData,
  });

  @override
  _UserFormSheetState createState() => _UserFormSheetState();
}

class _UserFormSheetState extends State<_UserFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _fullNameController;
  late TextEditingController _usernameController;
  late TextEditingController _tcController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _passwordController;

  String _selectedRole = 'ogretmen';
  int _currentStep = 0;

  // Kullanıcının çalıştığı okul türleri
  Set<String> _selectedSchoolTypes = {};

  // Modül yetkileri yapısı: moduleKey -> {enabled, level}
  // level: 'viewer' (Görüntüleyen) veya 'editor' (Düzenleyen)
  Map<String, Map<String, dynamic>> _modulePermissions = {};

  // Okul türü yetkileri: schoolTypeId -> level ('viewer' veya 'editor')
  Map<String, String> _schoolTypePermissions = {};

  List<Map<String, dynamic>> _schoolTypes = []; // Okulun tüm okul türleri
  bool _isSaving = false;
  bool _isLoadingSchoolTypes = true;

  @override
  void initState() {
    super.initState();
    _loadSchoolTypes();
    final isEdit = widget.userId != null;

    _fullNameController = TextEditingController(
      text: widget.userData?['fullName'] ?? '',
    );
    _usernameController = TextEditingController(
      text: widget.userData?['username'] ?? '',
    );
    _tcController = TextEditingController(
      text: widget.userData?['tcKimlik'] ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.userData?['phone'] ?? '',
    );
    _emailController = TextEditingController(
      text: widget.userData?['email'] ?? '',
    );
    _passwordController = TextEditingController();

    if (isEdit && widget.userData != null) {
      _selectedRole = widget.userData!['role'] ?? 'ogretmen';

      // Çalıştığı okul türlerini yükle
      final schoolTypesList = widget.userData!['schoolTypes'] as List<dynamic>?;
      if (schoolTypesList != null) {
        _selectedSchoolTypes = schoolTypesList.map((e) => e.toString()).toSet();
      }

      // Modül yetkilerini yükle
      final modulePerms =
          widget.userData!['modulePermissions'] as Map<String, dynamic>?;
      if (modulePerms != null) {
        modulePerms.forEach((moduleKey, perms) {
          if (perms is Map) {
            _modulePermissions[moduleKey] = {
              'enabled': perms['enabled'] ?? false,
              'level': perms['level'] ?? 'viewer',
            };
          }
        });
      }

      // Okul türü yetkilerini yükle
      final schoolTypePerms =
          widget.userData!['schoolTypePermissions'] as Map<String, dynamic>?;
      if (schoolTypePerms != null) {
        schoolTypePerms.forEach((stId, level) {
          _schoolTypePermissions[stId] = level.toString();
        });
      }
    } else {
      // Yeni kullanıcı için boş başlat
      AppModules.allModuleKeys.forEach((moduleKey) {
        _modulePermissions[moduleKey] = {'enabled': false, 'level': 'viewer'};
      });
    }
  }

  Future<void> _loadSchoolTypes() async {
    try {
      // Kullanıcı kontrolü ekleyelim
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('⚠️ Kullanıcı giriş yapmamış');
        setState(() => _isLoadingSchoolTypes = false);
        return;
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('schoolTypes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      setState(() {
        _schoolTypes = snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
        _isLoadingSchoolTypes = false;
      });
    } catch (e) {
      print('❌ Okul türleri yüklenemedi: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Okul türleri yüklenemedi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isLoadingSchoolTypes = false);
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _tcController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final isEdit = widget.userId != null;
      final username = _usernameController.text.trim().toLowerCase();
      final authEmail = '$username@${widget.institutionId}.edukn';

      // Sadece aktif modülleri filtrele
      Map<String, dynamic> activeModules = {};
      _modulePermissions.forEach((key, value) {
        if (value['enabled'] == true) {
          activeModules[key] = {'enabled': true, 'level': value['level']};
        }
      });

      Map<String, dynamic> userData = {
        'institutionId': widget.institutionId,
        'schoolId': widget.schoolId,
        'fullName': _fullNameController.text.trim(),
        'username': username,
        'phone': _phoneController.text.trim(),
        'role': _selectedRole,
        'schoolTypes': _selectedSchoolTypes.toList(), // Çalıştığı okul türleri
        'isActive': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Email'i her zaman kaydet (kullanıcı girmediyse otomatik oluştur)
      if (_emailController.text.trim().isNotEmpty) {
        userData['email'] = _emailController.text.trim();
      } else {
        // Email girilmediyse auth email'ini kullan
        userData['email'] = authEmail;
      }

      // Opsiyonel alanları ekle
      if (_tcController.text.trim().isNotEmpty) {
        userData['tcKimlik'] = _tcController.text.trim();
      }

      // Sadece dolu olanları ekle
      if (_schoolTypePermissions.isNotEmpty) {
        userData['schoolTypePermissions'] = _schoolTypePermissions;
      }

      if (activeModules.isNotEmpty) {
        userData['modulePermissions'] = activeModules;
      }

      if (isEdit) {
        // Güncelleme
        if (_passwordController.text.isNotEmpty) {
          // TODO: Şifre güncelleme için Cloud Function gerekli
          print('⚠️ Şifre güncellemesi için Cloud Function gerekli');
        }

        // Mevcut kullanıcının authUserId'sini al
        final authUserId = widget.userData?['authUserId'];
        print('🔍 Debug - authUserId: $authUserId');
        print('🔍 Debug - widget.userId: ${widget.userId}');
        print(
          '🔍 Debug - Current user UID: ${FirebaseAuth.instance.currentUser?.uid}',
        );

        // En doğru dokümanı hedefle: önce authUserId varsa ve doküman mevcutsa onu güncelle
        String? targetDocId;
        if (authUserId != null) {
          final authDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(authUserId)
              .get();
          if (authDoc.exists) {
            targetDocId = authUserId;
          }
        }

        // authUserId yoksa veya bulunamadıysa, widget.userId dokümanı var mı bak
        if (targetDocId == null && widget.userId != null) {
          final legacyDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(widget.userId)
              .get();
          if (legacyDoc.exists) {
            targetDocId = widget.userId;
          }
        }

        if (targetDocId != null) {
          print('🔍 Debug - Güncelleme yapılacak doküman: users/$targetDocId');
          await FirebaseFirestore.instance
              .collection('users')
              .doc(targetDocId)
              .update(userData);
        } else {
          // İki doküman da yok: veri tutarsızlığı. Çözüm: authUserId altında oluştur/merge et.
          final fallbackId = authUserId ?? widget.userId;
          print(
            '⚠️ Debug - Hedef doküman bulunamadı, set(merge) ile oluşturuluyor: users/$fallbackId',
          );
          await FirebaseFirestore.instance
              .collection('users')
              .doc(fallbackId)
              .set(userData, SetOptions(merge: true));
        }
      } else {
        // Yeni kullanıcı - geçerli şifre ve benzersiz kullanıcı adı kontrolü
        if (_passwordController.text.trim().length < 6) {
          throw 'Şifre en az 6 karakter olmalı';
        }

        // Aynı kurumda aynı kullanıcı adı var mı?
        final dupCheck = await FirebaseFirestore.instance
            .collection('users')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('username', isEqualTo: username)
            .limit(1)
            .get();
        if (dupCheck.docs.isNotEmpty) {
          throw 'Bu kullanıcı adı zaten kullanılıyor';
        }

        // Firebase Auth kullanıcısı oluştur
        String? authUserId;
        try {
          authUserId = await widget.onCreateAuth(
            authEmail,
            _passwordController.text.trim(),
          );
        } catch (e) {
          // Yaygın hataları daha anlaşılır göster
          final msg = e.toString();
          if (msg.contains('EMAIL_EXISTS')) {
            throw 'Bu e-posta zaten kayıtlı (kullanıcı adı çakışıyor olabilir)';
          } else if (msg.contains('WEAK_PASSWORD')) {
            throw 'Zayıf şifre: lütfen en az 6 karakter kullanın';
          } else if (msg.contains('OPERATION_NOT_ALLOWED')) {
            throw 'Auth kapalı görünüyor: Firebase Auth ayarlarını kontrol edin';
          }
          throw 'Firebase Auth hata: $e';
        }

        userData['authUserId'] = authUserId;
        userData['createdAt'] = FieldValue.serverTimestamp();

        // Doküman ID'sini Firebase Auth uid ile aynı yap
        await FirebaseFirestore.instance
            .collection('users')
            .doc(authUserId)
            .set(userData);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEdit ? '✅ Kullanıcı güncellendi!' : '✅ Kullanıcı eklendi!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Okul türleri modülü için özel widget
  Widget _buildSchoolTypesModule(
    dynamic moduleInfo,
    bool isEnabled,
    String level,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isEnabled
            ? moduleInfo.color.withOpacity(0.05)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEnabled
              ? moduleInfo.color.withOpacity(0.3)
              : Colors.grey.shade300,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ana modül satırı
            Row(
              children: [
                // Checkbox
                InkWell(
                  onTap: () {
                    setState(() {
                      _modulePermissions['okul_turleri']!['enabled'] =
                          !isEnabled;
                      if (!isEnabled) {
                        _modulePermissions['okul_turleri']!['level'] = 'viewer';
                      }
                      // Modül kapatıldığında okul türü yetkilerini temizle
                      if (isEnabled) {
                        _schoolTypePermissions.clear();
                        _selectedSchoolTypes.clear();
                      }
                    });
                  },
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isEnabled ? moduleInfo.color : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isEnabled
                            ? moduleInfo.color
                            : Colors.grey.shade400,
                        width: 2,
                      ),
                    ),
                    child: isEnabled
                        ? Icon(Icons.check, color: Colors.white, size: 16)
                        : null,
                  ),
                ),
                SizedBox(width: 12),

                // Icon ve Modül Adı
                Icon(moduleInfo.icon, color: moduleInfo.color, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    moduleInfo.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isEnabled ? Colors.black87 : Colors.grey.shade600,
                    ),
                  ),
                ),

                // Yetki Seviyesi Badge
                if (isEnabled)
                  InkWell(
                    onTap: () {
                      setState(() {
                        _modulePermissions['okul_turleri']!['level'] =
                            level == 'viewer' ? 'editor' : 'viewer';
                      });
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: level == 'editor'
                            ? moduleInfo.color
                            : moduleInfo.color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            level == 'editor' ? Icons.edit : Icons.visibility,
                            size: 12,
                            color: level == 'editor'
                                ? Colors.white
                                : moduleInfo.color,
                          ),
                          SizedBox(width: 4),
                          Text(
                            level == 'editor' ? 'Düzenleyen' : 'Görüntüleyen',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: level == 'editor'
                                  ? Colors.white
                                  : moduleInfo.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),

            // Okul türleri listesi (sadece modül aktifse göster)
            if (isEnabled) ...[
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Okul Türü Yetkileri',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    SizedBox(height: 8),
                    if (_isLoadingSchoolTypes)
                      Center(child: CircularProgressIndicator(strokeWidth: 2))
                    else if (_schoolTypes.isEmpty)
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber,
                              color: Colors.orange,
                              size: 16,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Henüz okul türü tanımlanmamış',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Column(
                        children: _schoolTypes.map((schoolType) {
                          final stId = schoolType['id'];
                          final stName =
                              schoolType['schoolTypeName'] ?? 'İsimsiz';
                          final isSelected = _selectedSchoolTypes.contains(
                            stId,
                          );
                          final stLevel =
                              _schoolTypePermissions[stId] ?? 'viewer';

                          return Container(
                            margin: EdgeInsets.only(bottom: 6),
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? moduleInfo.color.withOpacity(0.3)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              children: [
                                // Checkbox
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedSchoolTypes.remove(stId);
                                        _schoolTypePermissions.remove(stId);
                                      } else {
                                        _selectedSchoolTypes.add(stId);
                                        _schoolTypePermissions[stId] = 'viewer';
                                      }
                                    });
                                  },
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? moduleInfo.color
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: isSelected
                                            ? moduleInfo.color
                                            : Colors.grey.shade400,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: isSelected
                                        ? Icon(
                                            Icons.check,
                                            size: 12,
                                            color: Colors.white,
                                          )
                                        : null,
                                  ),
                                ),
                                SizedBox(width: 8),

                                // Okul türü adı
                                Expanded(
                                  child: Text(
                                    stName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color: isSelected
                                          ? Colors.black87
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ),

                                // Yetki seviyesi
                                if (isSelected)
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        _schoolTypePermissions[stId] =
                                            stLevel == 'viewer'
                                            ? 'editor'
                                            : 'viewer';
                                      });
                                    },
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: stLevel == 'editor'
                                            ? moduleInfo.color
                                            : moduleInfo.color.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        stLevel == 'editor'
                                            ? 'Düzenleyen'
                                            : 'Görüntüleyen',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: stLevel == 'editor'
                                              ? Colors.white
                                              : moduleInfo.color,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
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

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.userId != null;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
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

              // Header
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isEdit ? Icons.edit : Icons.person_add,
                        color: Colors.indigo,
                        size: 28,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        isEdit ? 'Kullanıcıyı Düzenle' : 'Yeni Kullanıcı Ekle',
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
              ),

              Divider(height: 1),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Kişisel Bilgiler Card
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: Colors.indigo.shade100,
                              width: 1.5,
                            ),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.indigo.shade50,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        Icons.person_outline,
                                        color: Colors.indigo,
                                        size: 20,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Kişisel Bilgiler',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.indigo.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 20),
                                // Ad Soyad
                                TextFormField(
                                  controller: _fullNameController,
                                  decoration: InputDecoration(
                                    labelText: 'Ad Soyad *',
                                    prefixIcon: Icon(
                                      Icons.person,
                                      color: Colors.indigo,
                                    ),
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Colors.grey.shade200,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Colors.indigo,
                                        width: 2,
                                      ),
                                    ),
                                    hintText: 'Örn: Ahmet Yılmaz',
                                  ),
                                  validator: (v) => v == null || v.isEmpty
                                      ? 'Ad soyad gerekli'
                                      : null,
                                ),
                                SizedBox(height: 16),

                                // Kullanıcı Adı
                                TextFormField(
                                  controller: _usernameController,
                                  decoration: InputDecoration(
                                    labelText: 'Kullanıcı Adı *',
                                    prefixIcon: Icon(Icons.account_circle),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    hintText:
                                        'Giriş için kullanılacak kullanıcı adı',
                                  ),
                                  onChanged: (value) {
                                    // Sadece küçük harf, rakam ve alt çizgi
                                    final filtered = value
                                        .toLowerCase()
                                        .replaceAll(RegExp(r'[^a-z0-9_]'), '');
                                    if (filtered != value) {
                                      _usernameController.value =
                                          _usernameController.value.copyWith(
                                            text: filtered,
                                            selection: TextSelection.collapsed(
                                              offset: filtered.length,
                                            ),
                                          );
                                    }
                                  },
                                  validator: (v) {
                                    if (v == null || v.isEmpty)
                                      return 'Kullanıcı adı gerekli';
                                    if (v.length < 3)
                                      return 'En az 3 karakter olmalı';
                                    return null;
                                  },
                                ),
                                SizedBox(height: 16),

                                // TC Kimlik (Opsiyonel)
                                TextFormField(
                                  controller: _tcController,
                                  decoration: InputDecoration(
                                    labelText: 'TC Kimlik No (Opsiyonel)',
                                    prefixIcon: Icon(Icons.badge),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    hintText: '11 haneli TC Kimlik No',
                                  ),
                                  keyboardType: TextInputType.number,
                                  maxLength: 11,
                                  onChanged: (value) {
                                    // Sadece rakam kabul et
                                    final filtered = value.replaceAll(
                                      RegExp(r'[^0-9]'),
                                      '',
                                    );
                                    if (filtered != value) {
                                      _tcController.value = _tcController.value
                                          .copyWith(
                                            text: filtered,
                                            selection: TextSelection.collapsed(
                                              offset: filtered.length,
                                            ),
                                          );
                                    }
                                  },
                                  validator: (v) {
                                    // TC opsiyonel ama girilirse 11 haneli olmalı
                                    if (v != null &&
                                        v.isNotEmpty &&
                                        v.length != 11) {
                                      return 'TC Kimlik No 11 haneli olmalı';
                                    }
                                    return null;
                                  },
                                ),
                                SizedBox(height: 16),

                                // Telefon
                                TextFormField(
                                  controller: _phoneController,
                                  decoration: InputDecoration(
                                    labelText: 'Telefon Numarası *',
                                    prefixIcon: Icon(Icons.phone),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    hintText: '05XX XXX XX XX',
                                  ),
                                  keyboardType: TextInputType.phone,
                                  validator: (v) => v == null || v.isEmpty
                                      ? 'Telefon gerekli'
                                      : null,
                                ),
                                SizedBox(height: 16),

                                // Email
                                TextFormField(
                                  controller: _emailController,
                                  decoration: InputDecoration(
                                    labelText: 'E-posta Adresi (Opsiyonel)',
                                    prefixIcon: Icon(Icons.email),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    hintText: 'ornek@mail.com',
                                  ),
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (v) {
                                    if (v != null &&
                                        v.isNotEmpty &&
                                        !v.contains('@')) {
                                      return 'Geçerli email adresi girin';
                                    }
                                    return null;
                                  },
                                ),
                                SizedBox(height: 16),

                                // Şifre
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: true,
                                  decoration: InputDecoration(
                                    labelText: isEdit
                                        ? 'Yeni Şifre (Boş bırakılırsa değişmez)'
                                        : 'Şifre *',
                                    prefixIcon: Icon(Icons.lock),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  validator: (v) {
                                    if (!isEdit && (v == null || v.isEmpty))
                                      return 'Şifre gerekli';
                                    if (v != null &&
                                        v.isNotEmpty &&
                                        v.length < 6)
                                      return 'En az 6 karakter';
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 20),

                        // Görev ve Okul Türleri Card
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: Colors.purple.shade100,
                              width: 1.5,
                            ),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.shade50,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        Icons.work_outline,
                                        color: Colors.purple,
                                        size: 20,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Görevi',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.purple.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 20),
                                DropdownButtonFormField<String>(
                                  value: _selectedRole,
                                  decoration: InputDecoration(
                                    labelText: 'Görev Seçin *',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    prefixIcon: Icon(Icons.work),
                                  ),
                                  items:
                                      const {
                                        'genel_mudur': 'Genel Müdür',
                                        'mudur': 'Müdür',
                                        'mudur_yardimcisi': 'Müdür Yardımcısı',
                                        'ogretmen': 'Öğretmen',
                                        'personel': 'Personel',
                                        'hr': 'İnsan Kaynakları',
                                        'muhasebe': 'Muhasebe',
                                        'satin_alma': 'Satın Alma',
                                        'depo': 'Depo Sorumlusu',
                                        'destek_hizmetleri':
                                            'Destek Hizmetleri',
                                      }.entries.map((e) {
                                        return DropdownMenuItem(
                                          value: e.key,
                                          child: Text(e.value),
                                        );
                                      }).toList(),
                                  onChanged: (value) =>
                                      setState(() => _selectedRole = value!),
                                ),
                                SizedBox(height: 24),

                                // Bilgilendirme
                                if (_currentStep == 0)
                                  Container(
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.blue.shade200,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.info_outline,
                                          color: Colors.blue,
                                          size: 18,
                                        ),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Kişisel bilgileri doldurun, sonra "İleri" butonuna basın',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.blue.shade900,
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
                        SizedBox(height: 20),

                        // ADIM 2: Modül Yetkileri (Sadece currentStep=1 ise göster)
                        if (_currentStep == 1) ...[
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: Colors.green.shade100,
                                width: 1.5,
                              ),
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.security,
                                          color: Colors.green,
                                          size: 20,
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Modül Yetkileri',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green.shade700,
                                              ),
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              'Checkbox ile aktif edin, badge tıklayarak seviye değiştirin',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 20),

                                  // Kategoriye göre grupla
                                  ...AppModules.allCategories.map((category) {
                                    final categoryModules =
                                        AppModules.getModulesByCategory(
                                          category,
                                        );

                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Kategori Başlığı
                                        Padding(
                                          padding: EdgeInsets.only(
                                            bottom: 12,
                                            top: 8,
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 4,
                                                height: 16,
                                                decoration: BoxDecoration(
                                                  color: Colors.indigo,
                                                  borderRadius:
                                                      BorderRadius.circular(2),
                                                ),
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                category,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.grey.shade700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Modül Liste
                                        ...categoryModules.entries.map((
                                          moduleEntry,
                                        ) {
                                          final moduleKey = moduleEntry.key;
                                          final moduleInfo = moduleEntry.value;

                                          // Initialize permissions if null
                                          if (_modulePermissions[moduleKey] ==
                                              null) {
                                            _modulePermissions[moduleKey] = {
                                              'enabled': false,
                                              'level': 'viewer',
                                            };
                                          }

                                          final perms =
                                              _modulePermissions[moduleKey]!;
                                          final isEnabled =
                                              perms['enabled'] ?? false;
                                          final level =
                                              perms['level'] ?? 'viewer';

                                          // Okul türleri modülü için özel yapı
                                          if (moduleKey == 'okul_turleri') {
                                            return _buildSchoolTypesModule(
                                              moduleInfo,
                                              isEnabled,
                                              level,
                                            );
                                          }

                                          return Container(
                                            margin: EdgeInsets.only(bottom: 8),
                                            decoration: BoxDecoration(
                                              color: isEnabled
                                                  ? moduleInfo.color
                                                        .withOpacity(0.05)
                                                  : Colors.grey.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: isEnabled
                                                    ? moduleInfo.color
                                                          .withOpacity(0.3)
                                                    : Colors.grey.shade300,
                                              ),
                                            ),
                                            child: Padding(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 12,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      // Checkbox
                                                      InkWell(
                                                        onTap: () {
                                                          setState(() {
                                                            _modulePermissions[moduleKey]!['enabled'] =
                                                                !isEnabled;
                                                            // Aktif olduğunda varsayılan olarak 'viewer' yap
                                                            if (!isEnabled) {
                                                              _modulePermissions[moduleKey]!['level'] =
                                                                  'viewer';
                                                            }
                                                          });
                                                        },
                                                        child: Container(
                                                          width: 24,
                                                          height: 24,
                                                          decoration: BoxDecoration(
                                                            color: isEnabled
                                                                ? moduleInfo
                                                                      .color
                                                                : Colors
                                                                      .transparent,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  6,
                                                                ),
                                                            border: Border.all(
                                                              color: isEnabled
                                                                  ? moduleInfo
                                                                        .color
                                                                  : Colors
                                                                        .grey
                                                                        .shade400,
                                                              width: 2,
                                                            ),
                                                          ),
                                                          child: isEnabled
                                                              ? Icon(
                                                                  Icons.check,
                                                                  color: Colors
                                                                      .white,
                                                                  size: 16,
                                                                )
                                                              : null,
                                                        ),
                                                      ),
                                                      SizedBox(width: 12),

                                                      // Icon ve Modül Adı
                                                      Icon(
                                                        moduleInfo.icon,
                                                        color: isEnabled
                                                            ? moduleInfo.color
                                                            : Colors
                                                                  .grey
                                                                  .shade400,
                                                        size: 20,
                                                      ),
                                                      SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          moduleInfo.name,
                                                          style: TextStyle(
                                                            fontSize: 14,
                                                            fontWeight:
                                                                isEnabled
                                                                ? FontWeight
                                                                      .w600
                                                                : FontWeight
                                                                      .normal,
                                                            color: isEnabled
                                                                ? Colors.black87
                                                                : Colors
                                                                      .grey
                                                                      .shade600,
                                                          ),
                                                        ),
                                                      ),

                                                      // Yetki Seviyesi Badge (Tıklanabilir)
                                                      if (isEnabled)
                                                        InkWell(
                                                          onTap: () {
                                                            setState(() {
                                                              // Toggle between viewer and editor
                                                              _modulePermissions[moduleKey]!['level'] =
                                                                  level ==
                                                                      'viewer'
                                                                  ? 'editor'
                                                                  : 'viewer';
                                                            });
                                                          },
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                16,
                                                              ),
                                                          child: Container(
                                                            padding:
                                                                EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      12,
                                                                  vertical: 6,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  level ==
                                                                      'editor'
                                                                  ? moduleInfo
                                                                        .color
                                                                  : moduleInfo
                                                                        .color
                                                                        .withOpacity(
                                                                          0.2,
                                                                        ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    16,
                                                                  ),
                                                            ),
                                                            child: Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                Icon(
                                                                  level ==
                                                                          'editor'
                                                                      ? Icons
                                                                            .edit
                                                                      : Icons
                                                                            .visibility,
                                                                  size: 14,
                                                                  color:
                                                                      level ==
                                                                          'editor'
                                                                      ? Colors
                                                                            .white
                                                                      : moduleInfo
                                                                            .color,
                                                                ),
                                                                SizedBox(
                                                                  width: 4,
                                                                ),
                                                                Text(
                                                                  level ==
                                                                          'editor'
                                                                      ? 'Düzenleyen'
                                                                      : 'Görüntüleyen',
                                                                  style: TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    color:
                                                                        level ==
                                                                            'editor'
                                                                        ? Colors
                                                                              .white
                                                                        : moduleInfo
                                                                              .color,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        )
                                                      else
                                                        Container(
                                                          padding:
                                                              EdgeInsets.symmetric(
                                                                horizontal: 12,
                                                                vertical: 6,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: Colors
                                                                .grey
                                                                .shade200,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  16,
                                                                ),
                                                          ),
                                                          child: Text(
                                                            'Pasif',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: Colors
                                                                  .grey
                                                                  .shade500,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                        SizedBox(height: 16),
                                      ],
                                    );
                                  }).toList(),

                                  // Bilgilendirme
                                  Container(
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.blue.shade200,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.info_outline,
                                          color: Colors.blue,
                                          size: 20,
                                        ),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Görüntüleyen: Sadece görüntüleme yetkisi • Düzenleyen: Tam yetki (ekleme, düzenleme, silme)',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.blue.shade900,
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
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              // Stepper Navigation Buttons
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Geri Butonu
                    if (_currentStep > 0)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() => _currentStep = 0);
                          },
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: BorderSide(color: Colors.indigo),
                          ),
                          child: Text(
                            'Geri',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.indigo,
                            ),
                          ),
                        ),
                      ),

                    if (_currentStep > 0) SizedBox(width: 12),

                    // İleri / Kaydet Butonu
                    Expanded(
                      flex: _currentStep == 0 ? 1 : 2,
                      child: ElevatedButton(
                        onPressed: _isSaving
                            ? null
                            : () {
                                if (_currentStep == 0) {
                                  // Form validasyonu
                                  if (_formKey.currentState!.validate()) {
                                    setState(() => _currentStep = 1);
                                  }
                                } else {
                                  // Kaydet
                                  _save();
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.indigo,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSaving
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _currentStep == 0
                                    ? 'İleri'
                                    : (isEdit ? 'Güncelle' : 'Kaydet'),
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
