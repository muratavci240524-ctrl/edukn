import '../../../constants/school_type_modules.dart';
import '../../../services/user_permission_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'school_type_stats_screen.dart';
import 'school_type_detail_screen.dart';

class SchoolTypesScreen extends StatefulWidget {
  const SchoolTypesScreen({Key? key}) : super(key: key);

  @override
  _SchoolTypesScreenState createState() => _SchoolTypesScreenState();
}

class _SchoolTypesScreenState extends State<SchoolTypesScreen> {
  String? institutionId;

  // Yetkilendirme için
  Map<String, dynamic>? userData;
  bool _isLoadingPermissions = true;

  @override
  void initState() {
    super.initState();
    _getInstitutionId();
    _loadUserPermissions();
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

    final modulePerms = userData!['modulePermissions'] as Map<String, dynamic>?;
    if (modulePerms == null) return false;

    final schoolTypePerm = modulePerms['okul_turleri'] as Map<String, dynamic>?;
    if (schoolTypePerm == null) return false;

    return schoolTypePerm['enabled'] == true;
  }

  // Yeni okul türü ekleyebilir mi? (Genel modül editor yetkisi gerekli)
  bool _canCreateSchoolType() {
    // Admin kullanıcısı (userData yok) - Her zaman ekleyebilir
    if (userData == null) {
      return true;
    }

    final modulePerms = userData!['modulePermissions'] as Map<String, dynamic>?;
    if (modulePerms == null) {
      return false;
    }

    final schoolTypePerm = modulePerms['okul_turleri'] as Map<String, dynamic>?;
    if (schoolTypePerm == null) {
      return false;
    }

    final level = schoolTypePerm['level'];
    final canCreate = level == 'editor';

    // Genel modül düzenleme yetkisi gerekli
    return canCreate;
  }

  // Belirli bir okul türünü düzenleyebilir mi?
  bool _canEditSpecificSchoolType(String schoolTypeId) {
    // Admin kullanıcısı (userData yok) - Her zaman düzenleyebilir
    if (userData == null) {
      return true;
    }

    // Önce genel modül erişimi kontrol et
    if (!_hasSchoolTypeAccess()) {
      return false;
    }

    // Okul türü bazlı yetkileri kontrol et
    final schoolTypePerms =
        userData!['schoolTypePermissions'] as Map<String, dynamic>?;

    // Eğer okul türü bazlı yetki kaydı yoksa, genel modül seviyesine bak
    if (schoolTypePerms == null || !schoolTypePerms.containsKey(schoolTypeId)) {
      final modulePerms =
          userData!['modulePermissions'] as Map<String, dynamic>?;
      final generalLevel =
          (modulePerms?['okul_turleri'] as Map<String, dynamic>?)?['level'];
      final canEdit = generalLevel == 'editor';
      return canEdit;
    }

    // Bu okul türü için editor yetkisi var mı?
    final permission = schoolTypePerms[schoolTypeId];
    final canEdit = permission == 'editor';
    return canEdit;
  }

  // Belirli bir okul türüne geçiş yapabilir mi?
  bool _canSwitchToSchoolType(String schoolTypeId) {
    // Admin kullanıcısı (userData yok) - Her zaman geçiş yapabilir
    if (userData == null) {
      return true;
    }

    // Önce genel modül erişimi kontrol et
    if (!_hasSchoolTypeAccess()) {
      return false;
    }

    // Okul türü bazlı yetkileri kontrol et
    final schoolTypePerms =
        userData!['schoolTypePermissions'] as Map<String, dynamic>?;

    // Eğer okul türü bazlı yetki kaydı yoksa, genel modül erişimi varsa geçişe izin ver
    if (schoolTypePerms == null || !schoolTypePerms.containsKey(schoolTypeId)) {
      // Genel modül erişimi zaten doğrulandı (_hasSchoolTypeAccess), geçişe izin ver
      return true;
    }

    // Bu okul türü için herhangi bir yetki var mı? (viewer veya editor)
    final permission = schoolTypePerms[schoolTypeId];
    final canSwitch = permission == 'viewer' || permission == 'editor';
    return canSwitch;
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
                data['schoolTypeName'] ?? data['typeName'] ?? 'İsimsiz',
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
                label: 'Sınıf Sayısı',
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

  Future<void> _getInstitutionId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final email = user.email!;
      setState(() {
        institutionId = email.split('@')[1].split('.')[0].toUpperCase();
      });
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
    if (institutionId == null) {
      return Scaffold(
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.indigo),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Okul Türleri',
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
          'Okul Türleri',
          style: TextStyle(
            color: Colors.grey.shade900,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.bar_chart, color: Colors.indigo),
            tooltip: 'İstatistikleri Gör',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SchoolTypeStatsScreen(),
                ),
              );
            },
          ),
          SizedBox(width: 8),
        ],
      ),

      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('schoolTypes')
            .where('institutionId', isEqualTo: institutionId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Hata: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          // Client-side sorting
          final schoolTypes = snapshot.data!.docs.toList();

          // 1. Özel sıralama düzeni tanımla
          const List<String> sortOrder = [
            'Anaokulu',
            'İlkokul',
            'Ortaokul',
            'Lise',
            'Kurs',
            'Diğer',
          ];

          schoolTypes.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;

            final String? aType = aData['schoolType'];
            final String? bType = bData['schoolType'];

            // 2. Ana sıralama: Tanımlanan listeye göre
            final int aIndex = aType != null
                ? sortOrder.indexOf(aType)
                : sortOrder.length;
            final int bIndex = bType != null
                ? sortOrder.indexOf(bType)
                : sortOrder.length;

            int typeComparison = aIndex.compareTo(bIndex);
            if (typeComparison != 0) return typeComparison;

            // 3. İkincil sıralama: Aynı türdekileri oluşturulma tarihine göre (yeni olan üste)
            final aTime = aData['createdAt'] as Timestamp?;
            final bTime = bData['createdAt'] as Timestamp?;
            return (bTime ?? Timestamp(0, 0)).compareTo(
              aTime ?? Timestamp(0, 0),
            );
          });

          // Okul türü yoksa
          if (schoolTypes.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.school_outlined,
                      size: 80,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  SizedBox(height: 24),
                  Text(
                    'Henüz Okul Türü Yok',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    _canCreateSchoolType()
                        ? 'Anaokulu, İlkokul, Ortaokul gibi\nokul türleri ekleyebilirsiniz'
                        : 'Henüz okul türü eklenmemiş',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                  SizedBox(height: 32),
                  if (_canCreateSchoolType())
                    Text(
                      'Başlamak için alt taraftaki + butonuna tıklayın',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else
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
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange.shade700,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Sadece görüntüleme yetkiniz var',
                            style: TextStyle(color: Colors.orange.shade900),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          }

          // Okul türleri listesi - genişlik sınırlandırılmış
          return Center(
            child: Container(
              constraints: BoxConstraints(maxWidth: 800),
              child: ListView.builder(
                padding: EdgeInsets.all(16),
                itemCount: schoolTypes.length,
                itemBuilder: (context, index) {
                  final doc = schoolTypes[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final List<dynamic> activeModules =
                      data['activeModules'] ?? [];

                  return Card(
                    margin: EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.school,
                                  color: Colors.indigo,
                                  size: 28,
                                ),
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Okul Türü Badge
                                    if (data['schoolType'] != null)
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        margin: EdgeInsets.only(bottom: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.indigo.shade100,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          data['schoolType'],
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.indigo.shade900,
                                          ),
                                        ),
                                      ),
                                    // Okul Türü Adı
                                    Text(
                                      data['schoolTypeName'] ??
                                          data['typeName'] ??
                                          'İsimsiz',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Okul türü bazlı yetkilendirme kontrolü - sadece düzenleme yetkisi olanlar PopupMenu görebilir
                              if (_canEditSpecificSchoolType(doc.id))
                                PopupMenuButton<String>(
                                  icon: Icon(Icons.more_vert),
                                  itemBuilder: (context) {
                                    List<PopupMenuEntry<String>> items = [];

                                    // Detay bilgileri (herkes görebilir)
                                    items.add(
                                      PopupMenuItem<String>(
                                        value: 'details',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.info_outline,
                                              size: 20,
                                              color: Colors.blue,
                                            ),
                                            SizedBox(width: 12),
                                            Text('Detay Bilgileri'),
                                          ],
                                        ),
                                      ),
                                    );

                                    // Okul türüne geçiş (viewer veya editor yetkisi gerekli)
                                    if (_canSwitchToSchoolType(doc.id)) {
                                      items.add(
                                        PopupMenuItem<String>(
                                          value: 'view',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.login,
                                                size: 20,
                                                color: Colors.green,
                                              ),
                                              SizedBox(width: 12),
                                              Text('Okul Türüne Geçiş Yap'),
                                            ],
                                          ),
                                        ),
                                      );
                                    }

                                    // Aktif modülleri gör (herkes görebilir)
                                    items.add(
                                      PopupMenuItem<String>(
                                        value: 'modules',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.widgets,
                                              size: 20,
                                              color: Colors.purple,
                                            ),
                                            SizedBox(width: 12),
                                            Text('Aktif Modülleri Gör'),
                                          ],
                                        ),
                                      ),
                                    );

                                    // Düzenleme ve silme (sadece bu okul türü için editor yetkisi olanlar)
                                    if (_canEditSpecificSchoolType(doc.id)) {
                                      items.add(PopupMenuDivider());
                                      items.add(
                                        PopupMenuItem<String>(
                                          value: 'edit',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.edit,
                                                size: 20,
                                                color: Colors.blue,
                                              ),
                                              SizedBox(width: 12),
                                              Text('Düzenle'),
                                            ],
                                          ),
                                        ),
                                      );
                                      items.add(
                                        PopupMenuItem<String>(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.delete,
                                                size: 20,
                                                color: Colors.red,
                                              ),
                                              SizedBox(width: 12),
                                              Text('Sil'),
                                            ],
                                          ),
                                        ),
                                      );
                                    }

                                    return items;
                                  },
                                  onSelected: (value) {
                                    if (value == 'details') {
                                      _showSchoolTypeDetails(context, data);
                                    } else if (value == 'view') {
                                      // Okul türü detay sayfasına git
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              SchoolTypeDetailScreen(
                                                schoolTypeId: doc.id,
                                                schoolTypeName:
                                                    data['schoolTypeName'] ??
                                                    data['typeName'] ??
                                                    'Okul Türü',
                                                institutionId: institutionId!,
                                              ),
                                        ),
                                      );
                                    } else if (value == 'edit') {
                                      _showModernEditSheet(
                                        context,
                                        doc.id,
                                        data,
                                      );
                                    } else if (value == 'delete') {
                                      _deleteSchoolType(
                                        doc.id,
                                        data['schoolTypeName'] ??
                                            data['typeName'] ??
                                            'Bu okul türü',
                                      );
                                    } else if (value == 'modules') {
                                      _showActiveModulesDialog(
                                        context,
                                        data['schoolTypeName'] ?? 'Okul Türü',
                                        activeModules,
                                      );
                                    }
                                  },
                                ),
                            ],
                          ),
                          SizedBox(height: 16),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
      floatingActionButton: _isLoadingPermissions
          ? null
          : (_canCreateSchoolType()
                ? FloatingActionButton.extended(
                    onPressed: () => _showModernAddSheet(context),
                    backgroundColor: Colors.indigo,
                    icon: Icon(Icons.add, color: Colors.white),
                    label: Text(
                      'Okul Türü Ekle',
                      style: TextStyle(color: Colors.white),
                    ),
                  )
                : null),
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
                        return Container(
                          margin: EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: _selectedModules[key]!
                                ? Colors.indigo.shade50
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _selectedModules[key]!
                                  ? Colors.indigo.shade200
                                  : Colors.grey.shade200,
                              width: 1.5,
                            ),
                          ),
                          child: CheckboxListTile(
                            title: Row(
                              children: [
                                if (moduleInfo != null) ...[
                                  Icon(
                                    moduleInfo.icon,
                                    size: 20,
                                    color: moduleInfo.color,
                                  ),
                                  SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Text(
                                    SchoolTypeModules.getModuleName(key),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: _selectedModules[key]!
                                          ? Colors.indigo.shade900
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: moduleInfo != null
                                ? Text(
                                    moduleInfo.description,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  )
                                : null,
                            value: _selectedModules[key],
                            onChanged: (bool? value) {
                              setState(() {
                                _selectedModules[key] = value ?? false;
                              });
                            },
                            activeColor: Colors.indigo,
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            dense: true,
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
