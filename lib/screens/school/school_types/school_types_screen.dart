import '../../../constants/school_type_modules.dart';
import '../../../services/user_permission_service.dart';
import '../../../services/term_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_type_stats_screen.dart';
import 'school_type_detail_screen.dart';
import 'package:google_fonts/google_fonts.dart';

class SchoolTypesScreen extends StatefulWidget {
  const SchoolTypesScreen({Key? key}) : super(key: key);

  @override
  _SchoolTypesScreenState createState() => _SchoolTypesScreenState();
}

class _SchoolTypesScreenState extends State<SchoolTypesScreen> {
  String? institutionId;

  // Okul türü icon'ları
  final Map<String, IconData> schoolTypes_icons = {
    'Anaokulu': Icons.child_care,
    'İlkokul': Icons.school,
    'Ortaokul': Icons.menu_book,
    'Lise': Icons.collections_bookmark,
    'Kurs': Icons.class_,
    'Diğer': Icons.category,
  };
  
  // Yetkilendirme için
  Map<String, dynamic>? userData;
  bool _isLoadingPermissions = true;

  @override
  void initState() {
    super.initState();
    _loadUserPermissions().then((_) {
      _getInstitutionId();
    });
  }

  // Kullanıcı yetkilendirme bilgilerini yükle
  Future<void> _loadUserPermissions() async {
    final data = await UserPermissionService.loadUserData();
    if (mounted) {
      setState(() {
        userData = data;
        _isLoadingPermissions = false;
      });
    }
  }

  // Okul türü modülüne genel erişim yetkisi var mı?
  bool _hasSchoolTypeAccess() {
    // Admin kullanıcısı (userData yok) - Her zaman erişebilir
    if (userData == null) return true;

    return UserPermissionService.hasSubModuleAccess('egitim', 'okul_turleri', userData);
  }

  // Yeni okul türü ekleyebilir mi? (Genel modül editor yetkisi gerekli)
  bool _canCreateSchoolType() {
    // Admin kullanıcısı (userData yok) - Her zaman ekleyebilir
    if (userData == null) return true;

    return UserPermissionService.canEditSubModule('egitim', 'okul_turleri', userData);
  }

  // Belirli bir okul türünü düzenleyebilir mi?
  bool _canEditSpecificSchoolType(String schoolTypeId) {
    // Admin kullanıcısı (userData yok) - Her zaman düzenleyebilir
    if (userData == null) return true;

    final role = (userData!['role'] as String?)?.toLowerCase();
    if (role == 'admin') return true;

    // Eğer kullanıcının çalıştığı okul türleri listesi (schoolTypes) tanımlı ve boş değilse,
    // sadece bu listedeki okul türlerini düzenleyebilir (Genel müdür olmayan herkes için geçerli).
    if (role != 'genel_mudur') {
      final userSchoolTypes = userData!['schoolTypes'] as List<dynamic>?;
      if (userSchoolTypes != null && userSchoolTypes.isNotEmpty) {
        if (!userSchoolTypes.contains(schoolTypeId)) {
          return false;
        }
      }
    }

    if (role == 'genel_mudur') return true;

    // Önce genel modül erişimi kontrol et
    if (!_hasSchoolTypeAccess()) return false;

    // Eğer genel seviyede editor ise tüm okulları düzenleyebilir
    if (UserPermissionService.canEditSubModule('egitim', 'okul_turleri', userData)) {
      return true;
    }

    // Okul türü bazlı yetkileri kontrol et
    final schoolTypePerms = userData!['schoolTypePermissions'] as Map<String, dynamic>?;
    final permission = schoolTypePerms?[schoolTypeId];
    
    return permission == 'editor';
  }

  // Belirli bir okul türüne geçiş yapabilir mi?
  bool _canSwitchToSchoolType(String schoolTypeId) {
    // Sadece gerçek admin (userData == null) her şeyi görebilir
    if (userData == null) return true;

    final role = (userData!['role'] as String?)?.toLowerCase();
    if (role == 'admin') return true;

    // Eğer kullanıcının çalıştığı okul türleri listesi (schoolTypes) tanımlı ve boş değilse,
    // sadece bu listedeki okul türlerine giriş yapabilir (Genel müdür olmayan herkes için geçerli).
    if (role != 'genel_mudur') {
      final userSchoolTypes = userData!['schoolTypes'] as List<dynamic>?;
      if (userSchoolTypes != null && userSchoolTypes.isNotEmpty) {
        if (!userSchoolTypes.contains(schoolTypeId)) {
          return false;
        }
      }
    }

    if (role == 'genel_mudur') return true;

    // Önce genel modül erişimi kontrol et
    if (!_hasSchoolTypeAccess()) return false;

    // Modül düzeyindeki yetki seviyesine bak
    final modulePerms = userData!['modulePermissions'] as Map<String, dynamic>?;
    final egitimPerm = modulePerms?['egitim'] as Map<String, dynamic>?;
    final subModules = egitimPerm?['subModules'] as Map<String, dynamic>?;
    final schoolTypePerm = subModules?['okul_turleri'] as Map<String, dynamic>?;
    final generalLevel = schoolTypePerm?['level'];

    // Eğer modül düzeyinde 'editor' ise tüm okul türlerine girebilir
    if (generalLevel == 'editor') return true;

    // Eğer 'viewer' ise veya seviye belirsizse sadece yetkisi olan okul türlerine girebilir
    final schoolTypePerms = userData!['schoolTypePermissions'] as Map<String, dynamic>?;
    return schoolTypePerms != null && schoolTypePerms.containsKey(schoolTypeId);
  }

  // Okul türü detay bilgilerini göster
  void _showSchoolTypeDetails(BuildContext context, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue),
              SizedBox(width: 8),
              Text('Detay Bilgileri'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data['name'] ?? data['schoolTypeName'] ?? data['typeName'] ?? 'İsimsiz',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              _buildDetailRow(
                icon: Icons.people,
                label: 'Öğrenci Sayısı',
                value: '${data['studentCount'] ?? 0}',
                color: Colors.blue,
              ),
              SizedBox(height: 8),
              _buildDetailRow(
                icon: Icons.person,
                label: 'Öğretmen Sayısı',
                value: '${data['teacherCount'] ?? 0}',
                color: Colors.orange,
              ),
              SizedBox(height: 8),
              _buildDetailRow(
                icon: Icons.class_,
                label: 'Şube Sayısı',
                value: '${data['classCount'] ?? 0}',
                color: Colors.green,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Kapat'),
            ),
          ],
        );
      },
    );
  }

  // Detay satırı widget'ı
  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  // İstatistik kartı widget'ı
  Widget _buildCompactStat(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade900,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.shade500,
          ),
        ),
      ],
    );
  }

  Future<void> _getInstitutionId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final email = user.email!;
      final derivedId = await UserPermissionService.resolveInstitutionId(email, userData: userData);
      
      if (mounted) {
        setState(() {
          institutionId = derivedId;
        });
      }

      // Kapatıldı: Servisten gelen kanonik/gerçek ID'yi (derivedId) kullanmamız gerekiyor.
      // Sizin profilinizdeki veriyi direkt kullanmak büyük/küçük harf çakışmasına sebep oluyor.
      /*
      final data = await UserPermissionService.loadUserData();
      if (data != null && data['institutionId'] != null) {
        if (mounted) {
          setState(() {
            institutionId = data['institutionId'];
          });
        }
      }
      */
    }
  }

  // Modern bottom sheet - Ekle
  void _showModernAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _ModernSchoolTypeForm(institutionId: institutionId!),
    );
  }

  // Modern bottom sheet - Düzenle
  void _showModernEditSheet(
    BuildContext context,
    String id,
    Map<String, dynamic> data,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ModernSchoolTypeForm(
        institutionId: institutionId!,
        editId: id,
        initialData: data,
      ),
    );
  }

  Future<void> _deleteSchoolType(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 12),
            Text('Okul Türünü Sil'),
          ],
        ),
        content: Text('$name okul türünü silmek istediğinize emin misiniz?'),
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
      await FirebaseFirestore.instance
          .collection('schoolTypes')
          .doc(id)
          .delete();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🗑️ Okul türü silindi!'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.logout_rounded, color: Colors.red, size: 22)),
          const SizedBox(width: 12),
          const Text('Çıkış Yap', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        content: const Text('Hesabınızdan çıkış yapmak istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      UserPermissionService.clearCache();
      TermService().clearCache();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/school-login');
      }
    }
  }

  // Aktif modülleri gösteren dialog
  void _showActiveModulesDialog(
    BuildContext context,
    String schoolTypeName,
    List<dynamic> activeModules,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.widgets, color: Colors.indigo),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                '$schoolTypeName Modülleri',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: ListBody(
            children: activeModules.isNotEmpty
                ? activeModules.map((moduleKey) {
                    final moduleInfo = SchoolTypeModules.getModule(
                      moduleKey.toString(),
                    );
                    return ListTile(
                      leading: moduleInfo != null
                          ? Icon(moduleInfo.icon, color: moduleInfo.color)
                          : Icon(Icons.settings),
                      title: Text(
                        SchoolTypeModules.getModuleName(moduleKey.toString()),
                      ),
                    );
                  }).toList()
                : [Text('Bu okul türü için aktif modül bulunmuyor.')],
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

  @override
  Widget build(BuildContext context) {
    if (institutionId == null || _isLoadingPermissions) {
      return Scaffold(
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.indigo),
            onPressed: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                Navigator.pushReplacementNamed(context, '/school-dashboard');
              }
            },
          ),
          title: Text('Okul Türleri', style: TextStyle(color: Colors.grey.shade900, fontSize: 18, fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: Icon(Icons.logout_rounded, color: Colors.red),
              tooltip: 'Çıkış Yap',
              onPressed: _logout,
            ),
            SizedBox(width: 8),
          ],
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        if (userData != null && !UserPermissionService.hasAnyMainModuleAccess(userData)) {
          return false;
        }
        if (Navigator.canPop(context)) {
          return true;
        } else {
          Navigator.pushReplacementNamed(context, '/school-dashboard');
          return false;
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F4FF),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          leading: (userData != null && !UserPermissionService.hasAnyMainModuleAccess(userData))
              ? null
              : IconButton(
                  icon: Icon(Icons.arrow_back, color: Colors.indigo),
                  onPressed: () {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    } else {
                      Navigator.pushReplacementNamed(context, '/school-dashboard');
                    }
                  },
                ),
          title: Text('Okul Türleri', style: TextStyle(color: Colors.grey.shade900, fontSize: 18, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(Icons.bar_chart, color: Colors.indigo),
            tooltip: 'İstatistikleri Gör',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SchoolTypeStatsScreen())),
          ),
          IconButton(
            icon: Icon(Icons.logout_rounded, color: Colors.red),
            tooltip: 'Çıkış Yap',
            onPressed: _logout,
          ),
          SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('schoolTypes').where('institutionId', isEqualTo: institutionId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Hata: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator());

          final schoolTypes = snapshot.data!.docs.where((doc) => _canSwitchToSchoolType(doc.id)).toList();

          const List<String> sortOrder = ['Anaokulu', 'İlkokul', 'Ortaokul', 'Lise', 'Kurs', 'Diğer'];
          schoolTypes.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aIndex = sortOrder.indexOf(aData['schoolType'] ?? '').clamp(0, sortOrder.length);
            final bIndex = sortOrder.indexOf(bData['schoolType'] ?? '').clamp(0, sortOrder.length);
            if (aIndex != bIndex) return aIndex.compareTo(bIndex);
            final aTime = aData['createdAt'] as Timestamp?;
            final bTime = bData['createdAt'] as Timestamp?;
            return (bTime ?? Timestamp(0, 0)).compareTo(aTime ?? Timestamp(0, 0));
          });

          if (schoolTypes.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: EdgeInsets.all(28),
                    decoration: BoxDecoration(color: Colors.indigo.shade50, shape: BoxShape.circle),
                    child: Icon(Icons.school_outlined, size: 56, color: Colors.indigo.shade300),
                  ),
                  SizedBox(height: 20),
                  Text('Henüz Okul Türü Yok', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                  SizedBox(height: 8),
                  Text(_canCreateSchoolType() ? 'Okul türleri ekleyebilirsiniz' : 'Henüz okul türü eklenmemiş',
                    textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500)),
                  if (_canCreateSchoolType()) ...[
                    SizedBox(height: 28),
                    ElevatedButton.icon(
                      onPressed: () => _showModernAddSheet(context),
                      icon: Icon(Icons.add), label: Text('İlk Okul Türünü Ekle'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    ),
                  ],
                ],
              ),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth > 1100 ? 3 : (constraints.maxWidth > 700 ? 2 : 1);
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 20, 16, 100),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 900),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols, 
                        crossAxisSpacing: 16, 
                        mainAxisSpacing: 16, 
                        mainAxisExtent: 280, // Sabit yükseklik, aspect ratio kaynaklı taşmaları engeller
                      ),
                      itemCount: schoolTypes.length,
                      itemBuilder: (context, index) {
                        final doc = schoolTypes[index];
                        final data = doc.data() as Map<String, dynamic>;
                        return _SchoolTypeCard(
                          doc: doc, data: data, institutionId: institutionId!,
                          canEdit: _canEditSpecificSchoolType(doc.id), canSwitch: _canSwitchToSchoolType(doc.id),
                          onEdit: () => _showModernEditSheet(context, doc.id, data),
                          onDelete: () => _deleteSchoolType(doc.id, data['name'] ?? data['schoolTypeName'] ?? 'Bu okul türü'),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: _canCreateSchoolType()
          ? FloatingActionButton.extended(
              onPressed: () => _showModernAddSheet(context),
              backgroundColor: Colors.indigo,
              icon: Icon(Icons.add, color: Colors.white),
              label: Text('Okul Türü Ekle', style: TextStyle(color: Colors.white)),
            )
          : null,
      ),
    );
  }
}

// ─── OKUL TÜRÜ KARTI ──────────────────────────────────────────────────────────
class _SchoolTypeTheme {
  final Color primary;
  final Color light;
  final List<Color> gradient;
  final IconData icon;
  
  const _SchoolTypeTheme(this.primary, this.light, this.gradient, this.icon);
}

class _SchoolTypeCard extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final Map<String, dynamic> data;
  final String institutionId;
  final bool canEdit;
  final bool canSwitch;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SchoolTypeCard({
    required this.doc, required this.data, required this.institutionId,
    required this.canEdit, required this.canSwitch, required this.onEdit, required this.onDelete,
  });

  @override
  State<_SchoolTypeCard> createState() => _SchoolTypeCardState();
}

class _SchoolTypeCardState extends State<_SchoolTypeCard> {
  bool _isHovered = false;

  static const Map<String, _SchoolTypeTheme> _themes = {};
  
  static _SchoolTypeTheme _getTheme(String type) {
    switch (type) {
      case 'Anaokulu': 
        return _SchoolTypeTheme(
          Color(0xFFEC4899), Color(0xFFFDF2F8),
          [Color(0xFFF472B6), Color(0xFFDB2777)], Icons.child_care
        );
      case 'İlkokul':  
        return _SchoolTypeTheme(
          Color(0xFF3B82F6), Color(0xFFEFF6FF),
          [Color(0xFF60A5FA), Color(0xFF2563EB)], Icons.school
        );
      case 'Ortaokul': 
        return _SchoolTypeTheme(
          Color(0xFF10B981), Color(0xFFECFDF5),
          [Color(0xFF34D399), Color(0xFF059669)], Icons.menu_book
        );
      case 'Lise':     
        return _SchoolTypeTheme(
          Color(0xFF8B5CF6), Color(0xFFF5F3FF),
          [Color(0xFFA78BFA), Color(0xFF7C3AED)], Icons.collections_bookmark
        );
      case 'Kurs':     
        return _SchoolTypeTheme(
          Color(0xFFF59E0B), Color(0xFFFFFBEB),
          [Color(0xFFFBBF24), Color(0xFFD97706)], Icons.class_
        );
      default:         
        return _SchoolTypeTheme(
          Color(0xFF6B7280), Color(0xFFF9FAFB),
          [Color(0xFF9CA3AF), Color(0xFF4B5563)], Icons.category
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final schoolType = widget.data['schoolType'] as String? ?? 'Diğer';
    final theme = _getTheme(schoolType);
    final name = widget.data['name'] ?? widget.data['schoolTypeName'] ?? widget.data['typeName'] ?? 'İsimsiz';
    final isActive = widget.data['isActive'] != false;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: widget.canSwitch ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: Matrix4.identity()..translate(0.0, _isHovered ? -4.0 : 0.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: theme.primary.withOpacity(_isHovered ? 0.15 : 0.05),
              blurRadius: _isHovered ? 20 : 10,
              offset: Offset(0, _isHovered ? 8 : 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.canSwitch
                ? () => Navigator.push(context, MaterialPageRoute(
                    builder: (context) => SchoolTypeDetailScreen(
                      schoolTypeId: widget.doc.id, 
                      schoolTypeName: name, 
                      institutionId: widget.institutionId
                    )))
                : () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Bu okul türüne giriş yetkiniz bulunmamaktadır.'), 
                    backgroundColor: Colors.red)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Premium Gradient Header
                Container(
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [theme.gradient[0].withOpacity(0.85), theme.gradient[1]],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Decorative Background Icon
                      Positioned(
                        right: -10,
                        bottom: -15,
                        child: Icon(
                          theme.icon,
                          size: 90,
                          color: Colors.white.withOpacity(0.15),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 8,
                                    offset: Offset(0, 4),
                                  )
                                ],
                              ),
                              child: Icon(theme.icon, color: theme.primary, size: 28),
                            ),
                            Spacer(),
                            if (!isActive)
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text('PASİF', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.red.shade700, letterSpacing: 0.5)),
                              ),
                            if (widget.canEdit)
                              Container(
                                margin: EdgeInsets.only(left: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                width: 36,
                                height: 36,
                                child: PopupMenuButton<String>(
                                  icon: Icon(Icons.more_vert, size: 20, color: Colors.white),
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  onSelected: (v) { if (v == 'edit') widget.onEdit(); if (v == 'delete') widget.onDelete(); },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(value: 'edit', child: Row(children: [
                                      Icon(Icons.edit_outlined, size: 18, color: Colors.indigo), SizedBox(width: 12), Text('Düzenle')])),
                                    PopupMenuItem(value: 'delete', child: Row(children: [
                                      Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 12),
                                      Text('Sil', style: TextStyle(color: Colors.red))])),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Tag
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: theme.light,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: theme.primary.withOpacity(0.2)),
                          ),
                          child: Text(
                            schoolType.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10, 
                              fontWeight: FontWeight.w800, 
                              color: theme.primary, 
                              letterSpacing: 0.8
                            )
                          ),
                        ),
                        SizedBox(height: 12),
                        
                        // Name
                        Expanded(
                          child: Text(
                            name,
                            style: GoogleFonts.inter(
                              fontSize: 18, 
                              fontWeight: FontWeight.w800, 
                              color: Colors.grey.shade900, 
                              height: 1.3
                            ),
                            maxLines: 2, 
                            overflow: TextOverflow.ellipsis
                          ),
                        ),

                        // Stats divider
                        Divider(color: Colors.grey.shade100, height: 24),
                        
                        // Stats row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildStatItem(
                              stream: FirebaseFirestore.instance.collection('students')
                                  .where('institutionId', isEqualTo: widget.institutionId)
                                  .where('schoolTypeId', isEqualTo: widget.doc.id).snapshots(),
                              icon: Icons.people_alt_rounded, 
                              label: "Öğrenci",
                              color: Color(0xFF3B82F6)
                            ),
                            _buildStatItem(
                              stream: FirebaseFirestore.instance.collection('users')
                                  .where('institutionId', isEqualTo: widget.institutionId)
                                  .where('role', whereIn: ['ogretmen','öğretmen','teacher','rehber_ogretmen','rehber_öğretmen','Öğretmen','Rehber Öğretmen'])
                                  .where('schoolTypes', arrayContains: widget.doc.id).snapshots(),
                              icon: Icons.badge_rounded, 
                              label: "Öğretmen",
                              color: Color(0xFFF59E0B)
                            ),
                            _buildStatItem(
                              stream: FirebaseFirestore.instance.collection('classes')
                                  .where('institutionId', isEqualTo: widget.institutionId)
                                  .where('schoolTypeId', isEqualTo: widget.doc.id)
                                  .where('isActive', isEqualTo: true).snapshots(),
                              icon: Icons.meeting_room_rounded, 
                              label: "Sınıf",
                              color: Color(0xFF10B981)
                            ),
                          ],
                        ),
                      ],
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

  Widget _buildStatItem({
    required Stream<QuerySnapshot> stream, 
    required IconData icon, 
    required String label,
    required Color color
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return Column(
          children: [
            Container(
              padding: EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            SizedBox(height: 6),
            Text(
              '$count',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.grey.shade800),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500),
            )
          ],
        );
      },
    );
  }
}


// Modern Form Widget - Bottom Sheet
class _ModernSchoolTypeForm extends StatefulWidget {
  final String institutionId;
  final String? editId;
  final Map<String, dynamic>? initialData;

  const _ModernSchoolTypeForm({
    required this.institutionId,
    this.editId,
    this.initialData,
  });

  @override
  _ModernSchoolTypeFormState createState() => _ModernSchoolTypeFormState();
}

class _ModernSchoolTypeFormState extends State<_ModernSchoolTypeForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _capacityController;
  Map<String, bool> _selectedModules = {};
  Map<String, bool> _selectedGrades = {};
  bool _isSaving = false;

  // Okul türü seçenekleri ve icon'ları
  final Map<String, IconData> schoolTypes = {
    'Anaokulu': Icons.child_care,
    'İlkokul': Icons.school,
    'Ortaokul': Icons.menu_book,
    'Lise': Icons.collections_bookmark,
    'Kurs': Icons.class_,
    'Diğer': Icons.more_horiz,
  };
  String? _selectedSchoolType;

  // Sınıf/Yaş seçenekleri
  Map<String, List<String>> gradeOptions = {
    'Anaokulu': ['3 Yaş', '4 Yaş', '5 Yaş'],
    'İlkokul': ['1. Sınıf', '2. Sınıf', '3. Sınıf', '4. Sınıf'],
    'Ortaokul': ['5. Sınıf', '6. Sınıf', '7. Sınıf', '8. Sınıf'],
    'Lise': ['9. Sınıf', '10. Sınıf', '11. Sınıf', '12. Sınıf'],
    'Kurs': [
      '3 Yaş',
      '4 Yaş',
      '5 Yaş',
      '1. Sınıf',
      '2. Sınıf',
      '3. Sınıf',
      '4. Sınıf',
      '5. Sınıf',
      '6. Sınıf',
      '7. Sınıf',
      '8. Sınıf',
      '9. Sınıf',
      '10. Sınıf',
      '11. Sınıf',
      '12. Sınıf',
      'Mezun',
    ],
  };

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialData?['schoolTypeName'] ?? '',
    );
    _capacityController = TextEditingController(
      text: widget.initialData?['capacity']?.toString() ?? '',
    );
    _selectedSchoolType = widget.initialData?['schoolType'];

    // Modülleri başlat - SchoolTypeModules'den al
    SchoolTypeModules.allModuleKeys.forEach((key) {
      if (widget.initialData != null) {
        List<dynamic> activeModules =
            widget.initialData!['activeModules'] ?? [];
        _selectedModules[key] = activeModules.contains(key);
      } else {
        _selectedModules[key] = true; // Varsayılan hepsi seçili
      }
    });

    // Sınıf/Yaş seçeneklerini başlat
    if (_selectedSchoolType != null &&
        gradeOptions.containsKey(_selectedSchoolType)) {
      for (var grade in gradeOptions[_selectedSchoolType]!) {
        if (widget.initialData != null) {
          List<dynamic> activeGrades =
              widget.initialData!['activeGrades'] ?? [];
          _selectedGrades[grade] = activeGrades.contains(grade);
        } else {
          _selectedGrades[grade] = true; // Varsayılan hepsi aktif
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Widget _buildGradeGroup(String groupName, List<String> grades) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          groupName,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        SizedBox(height: 4),
        Row(
          children: grades.asMap().entries.map((entry) {
            int index = entry.key;
            String grade = entry.value;
            bool isSelected = _selectedGrades[grade] ?? false;
            bool isLast = index == grades.length - 1;

            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: isLast ? 0 : 8),
                child: FilterChip(
                  label: Center(
                    child: Text(
                      grade,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: isSelected ? Colors.white : Colors.grey.shade700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedGrades[grade] = selected;
                    });
                  },
                  selectedColor: Colors.orange,
                  checkmarkColor: Colors.white,
                  backgroundColor: Colors.grey.shade100,
                  side: BorderSide(
                    color: isSelected ? Colors.orange : Colors.grey.shade300,
                    width: 1.5,
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      List<String> activeModules = _selectedModules.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();

      List<String> activeGrades = _selectedGrades.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();

      int? capacity;
      if (_capacityController.text.trim().isNotEmpty) {
        capacity = int.tryParse(_capacityController.text.trim());
      }

      if (widget.editId != null) {
        // Güncelleme
        await FirebaseFirestore.instance
            .collection('schoolTypes')
            .doc(widget.editId)
            .update({
              'schoolType': _selectedSchoolType,
              'schoolTypeName': _nameController.text.trim(),
              'capacity': capacity,
              'activeModules': activeModules,
              'activeGrades': activeGrades,
              'updatedAt': FieldValue.serverTimestamp(),
            });
      } else {
        // Yeni ekleme
        await FirebaseFirestore.instance.collection('schoolTypes').add({
          'institutionId': widget.institutionId,
          'schoolType': _selectedSchoolType,
          'schoolTypeName': _nameController.text.trim(),
          'capacity': capacity,
          'activeModules': activeModules,
          'activeGrades': activeGrades,
          'studentCount': 0,
          'teacherCount': 0,
          'classCount': 0,
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.editId != null ? '✅ Güncellendi!' : '✅ Eklendi!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.editId != null;

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
                        isEdit ? Icons.edit : Icons.add_circle,
                        color: Colors.indigo,
                        size: 28,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEdit ? 'Okul Türünü Düzenle' : 'Yeni Okul Türü',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade900,
                            ),
                          ),
                          Text(
                            isEdit
                                ? 'Bilgileri güncelleyin'
                                : 'Yeni bir okul türü oluşturun',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
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

              // Form içeriği
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    controller: scrollController,
                    padding: EdgeInsets.all(20),
                    children: [
                      // Okul Türü Dropdown
                      Text(
                        'Okul Türü',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedSchoolType,
                        decoration: InputDecoration(
                          hintText: 'Okul türü seçin',
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.indigo,
                              width: 2,
                            ),
                          ),
                          // Prefix icon kaldırıldı - çünkü item'da zaten var
                        ),
                        items: schoolTypes.entries.map((entry) {
                          return DropdownMenuItem<String>(
                            value: entry.key,
                            child: Row(
                              children: [
                                Icon(
                                  entry.value,
                                  size: 22,
                                  color: Colors.indigo,
                                ),
                                SizedBox(width: 12),
                                Text(
                                  entry.key,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedSchoolType = value;
                            // Sınıf/Yaş seçeneklerini sıfırla ve yeniden başlat
                            _selectedGrades.clear();
                            if (value != null &&
                                gradeOptions.containsKey(value)) {
                              for (var grade in gradeOptions[value]!) {
                                _selectedGrades[grade] =
                                    true; // Varsayılan hepsi aktif
                              }
                            }
                          });
                        },
                        validator: (v) =>
                            v == null ? 'Okul türü seçmeniz gerekli' : null,
                      ),
                      SizedBox(height: 20),

                      // Okul Türü Adı (Custom name)
                      Text(
                        'Okul Türü Adı',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      SizedBox(height: 8),
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          hintText: 'Örn: Açı İlkokulu, Merkez Anaokulu',
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.indigo,
                              width: 2,
                            ),
                          ),
                          prefixIcon: Icon(Icons.edit, color: Colors.indigo),
                        ),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Okul türü adı gerekli'
                            : null,
                      ),
                      SizedBox(height: 20),

                      // Kapasite (İsteğe Bağlı)
                      Text(
                        'Kapasite (İsteğe Bağlı)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      SizedBox(height: 8),
                      TextFormField(
                        controller: _capacityController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'Örn: 500 (Toplam öğrenci kapasitesi)',
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.indigo,
                              width: 2,
                            ),
                          ),
                          prefixIcon: Icon(
                            Icons.people_outline,
                            color: Colors.indigo,
                          ),
                          helperText:
                              'Boş bırakırsanız doluluk oranı hesaplanmaz',
                          helperStyle: TextStyle(fontSize: 11),
                        ),
                      ),
                      SizedBox(height: 24),

                      // Sınıf/Yaş Seçenekleri
                      if (_selectedSchoolType != null &&
                          gradeOptions.containsKey(_selectedSchoolType)) ...[
                        Row(
                          children: [
                            Icon(Icons.grade, size: 20, color: Colors.orange),
                            SizedBox(width: 8),
                            Text(
                              _selectedSchoolType == 'Anaokulu'
                                  ? 'Yaş Grupları'
                                  : 'Sınıflar',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Bu okul türünde hangi ${_selectedSchoolType == 'Anaokulu' ? 'yaş grupları' : 'sınıflar'} aktif olacak?',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        SizedBox(height: 12),

                        // Kurs için gruplandırılmış, diğerleri için tek satır
                        if (_selectedSchoolType == 'Kurs') ...[
                          // Anaokulu Grubu
                          _buildGradeGroup('Anaokulu', [
                            '3 Yaş',
                            '4 Yaş',
                            '5 Yaş',
                          ]),
                          SizedBox(height: 8),
                          // İlkokul Grubu
                          _buildGradeGroup('İlkokul', [
                            '1. Sınıf',
                            '2. Sınıf',
                            '3. Sınıf',
                            '4. Sınıf',
                          ]),
                          SizedBox(height: 8),
                          // Ortaokul Grubu
                          _buildGradeGroup('Ortaokul', [
                            '5. Sınıf',
                            '6. Sınıf',
                            '7. Sınıf',
                            '8. Sınıf',
                          ]),
                          SizedBox(height: 8),
                          // Lise Grubu
                          _buildGradeGroup('Lise', [
                            '9. Sınıf',
                            '10. Sınıf',
                            '11. Sınıf',
                            '12. Sınıf',
                          ]),
                          SizedBox(height: 8),
                          // Mezun
                          _buildGradeGroup('Diğer', ['Mezun']),
                        ] else
                          // Tek satır - Ekran genişliğine sığdırılmış
                          Row(
                            children: gradeOptions[_selectedSchoolType]!
                                .asMap()
                                .entries
                                .map((entry) {
                                  int index = entry.key;
                                  String grade = entry.value;
                                  bool isSelected =
                                      _selectedGrades[grade] ?? false;
                                  bool isLast =
                                      index ==
                                      gradeOptions[_selectedSchoolType]!
                                              .length -
                                          1;

                                  return Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        right: isLast ? 0 : 8,
                                      ),
                                      child: FilterChip(
                                        label: Center(
                                          child: Text(
                                            grade,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                              color: isSelected
                                                  ? Colors.white
                                                  : Colors.grey.shade700,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                        selected: isSelected,
                                        onSelected: (selected) {
                                          setState(() {
                                            _selectedGrades[grade] = selected;
                                          });
                                        },
                                        selectedColor: Colors.orange,
                                        checkmarkColor: Colors.white,
                                        backgroundColor: Colors.grey.shade100,
                                        side: BorderSide(
                                          color: isSelected
                                              ? Colors.orange
                                              : Colors.grey.shade300,
                                          width: 1.5,
                                        ),
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 10,
                                        ),
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  );
                                })
                                .toList(),
                          ),
                        SizedBox(height: 24),
                      ],

                      // Aktif Modüller
                      Row(
                        children: [
                          Icon(Icons.widgets, size: 20, color: Colors.indigo),
                          SizedBox(width: 8),
                          Text(
                            'Aktif Modüller',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Bu okul türünde hangi modüller aktif olacak?',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      SizedBox(height: 16),

                      ..._selectedModules.keys.map((key) {
                        final moduleInfo = SchoolTypeModules.getModule(key);
                        final isSelected = _selectedModules[key] ?? false;
                        
                        return Container(
                          margin: EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (moduleInfo?.color.withOpacity(0.05) ?? Colors.indigo.shade50)
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? (moduleInfo?.color.withOpacity(0.3) ?? Colors.indigo.shade200)
                                  : Colors.grey.shade200,
                              width: 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                // Checkbox yerine şık bir indicator
                                InkWell(
                                  onTap: () => setState(() => _selectedModules[key] = !isSelected),
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: isSelected ? (moduleInfo?.color ?? Colors.indigo) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected ? (moduleInfo?.color ?? Colors.indigo) : Colors.grey.shade400,
                                        width: 2,
                                      ),
                                    ),
                                    child: isSelected
                                        ? Icon(Icons.check, color: Colors.white, size: 16)
                                        : null,
                                  ),
                                ),
                                SizedBox(width: 16),
                                
                                // Icon ve İsim
                                if (moduleInfo != null) ...[
                                  Icon(moduleInfo.icon, size: 24, color: moduleInfo.color),
                                  SizedBox(width: 12),
                                ],
                                
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        SchoolTypeModules.getModuleName(key),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: isSelected ? Colors.black87 : Colors.grey.shade600,
                                        ),
                                      ),
                                      if (moduleInfo != null)
                                        Text(
                                          moduleInfo.description,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                
                                // "Görüntüle / Düzenle" tarzı şık Badge
                                InkWell(
                                  onTap: () => setState(() => _selectedModules[key] = !isSelected),
                                  borderRadius: BorderRadius.circular(20),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isSelected 
                                          ? (moduleInfo?.color ?? Colors.indigo) 
                                          : Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: isSelected ? [
                                        BoxShadow(
                                          color: (moduleInfo?.color ?? Colors.indigo).withOpacity(0.3),
                                          blurRadius: 8,
                                          offset: Offset(0, 4),
                                        )
                                      ] : null,
                                    ),
                                    child: Text(
                                      isSelected ? 'AKTİF' : 'PASİF',
                                      style: TextStyle(
                                        color: isSelected ? Colors.white : Colors.grey.shade600,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),

                      SizedBox(height: 80), // Bottom button için boşluk
                    ],
                  ),
                ),
              ),

              // Kaydet Butonu
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle, color: Colors.white),
                                SizedBox(width: 12),
                                Text(
                                  isEdit
                                      ? 'Değişiklikleri Kaydet'
                                      : 'Okul Türü Oluştur',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
