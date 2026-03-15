import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/user_permission_service.dart';
import '../../services/term_service.dart';

class StaffManagementScreen extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;
  final bool isManagerStaff; // true: Yönetici Personel, false: Diğer Personel

  const StaffManagementScreen({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
    required this.isManagerStaff,
  }) : super(key: key);

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  Map<String, dynamic>? userData;
  bool _isLoadingPermissions = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadUserPermissions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  // Personel modülüne düzenleme yetkisi var mı?
  bool _canEditStaff() {
    // Admin kullanıcısı (userData yok) - Her zaman ekleyebilir
    if (userData == null) return true;

    // Okul türü bazlı yetkileri kontrol et
    final schoolTypePerms =
        userData!['schoolTypePermissions'] as Map<String, dynamic>?;
    if (schoolTypePerms == null) return false;

    // Bu okul türü için editor yetkisi var mı?
    final permission = schoolTypePerms[widget.schoolTypeId];
    return permission == 'editor';
  }

  // Okul türü bazlı personel listesini getir
  Stream<QuerySnapshot> _getStaffList() {
    // workLocations array'inde bu okul türünü içeren personelleri getir
    // Firestore array-contains kullanarak filtreleme yapıyoruz
    
    var query = FirebaseFirestore.instance
        .collection('users')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('workLocations', arrayContains: widget.schoolTypeName);

    return query.snapshots();
  }

  void _openAddStaffSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _StaffFormSheet(
        schoolTypeId: widget.schoolTypeId,
        schoolTypeName: widget.schoolTypeName,
        institutionId: widget.institutionId,
        isManagerStaff: widget.isManagerStaff,
      ),
    );
  }

  void _openEditStaffSheet(String staffId, Map<String, dynamic> staffData) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _StaffFormSheet(
        schoolTypeId: widget.schoolTypeId,
        schoolTypeName: widget.schoolTypeName,
        institutionId: widget.institutionId,
        isManagerStaff: widget.isManagerStaff,
        editStaffId: staffId,
        initialData: staffData,
      ),
    );
  }

  Future<void> _deleteStaff(String staffId, String staffName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 12),
            Text('Personeli Sil'),
          ],
        ),
        content: Text(
          '$staffName isimli personeli silmek istediğinize emin misiniz?',
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
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(staffId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Personel silindi'),
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.indigo),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isManagerStaff ? 'Yönetici Personel' : 'Diğer Personel',
              style: TextStyle(
                color: Colors.grey.shade900,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.schoolTypeName,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
      floatingActionButton: _isLoadingPermissions
          ? null
          : (_canEditStaff()
                ? FloatingActionButton.extended(
                    onPressed: _openAddStaffSheet,
                    backgroundColor: Colors.indigo,
                    icon: Icon(Icons.add, color: Colors.white),
                    label: Text(
                      'Personel Ekle',
                      style: TextStyle(color: Colors.white),
                    ),
                  )
                : null),
      body: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: 1200),
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              // Arama çubuğu
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Ad, soyad veya email ile ara',
                      prefixIcon: Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear),
                              onPressed: () {
                                setState(() {
                                  _searchController.clear();
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      border: InputBorder.none,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.toLowerCase();
                      });
                    },
                  ),
                ),
              ),
              SizedBox(height: 16),

              // Personel listesi
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _getStaffList(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 80,
                              color: Colors.red.shade300,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Veri yüklenemedi',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: EdgeInsets.all(32),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                widget.isManagerStaff
                                    ? Icons.admin_panel_settings
                                    : Icons.person_outline,
                                size: 80,
                                color: Colors.indigo.shade300,
                              ),
                            ),
                            SizedBox(height: 24),
                            Text(
                              'Henüz Personel Yok',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              _canEditStaff()
                                  ? 'İlk personeli eklemek için alt taraftaki\n+ butonuna tıklayın'
                                  : 'Henüz personel eklenmemiş',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    // Client-side filtreleme (role ve arama)
                    final managerRoles = ['mudur', 'mudur_yardimcisi', 'genel_mudur', 'MUDUR', 'MUDUR_YARDIMCISI', 'GENEL_MUDUR'];

                    var filteredStaff = snapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final role = (data['role'] ?? '').toString().toLowerCase();
                      final title = (data['title'] ?? '').toString().toLowerCase();

                      // Role kontrolü - yönetici mi değil mi?
                      final isManager = managerRoles.contains(role) || managerRoles.contains(title);
                      
                      // Eğer yönetici personel ekranındaysak sadece yöneticileri göster
                      // Diğer personel ekranındaysak yönetici olmayanları göster
                      if (widget.isManagerStaff && !isManager) return false;
                      if (!widget.isManagerStaff && isManager) return false;

                      // Arama kontrolü
                      if (_searchQuery.isNotEmpty) {
                        final name = (data['fullName'] ?? '')
                            .toString()
                            .toLowerCase();
                        final email = (data['email'] ?? '')
                            .toString()
                            .toLowerCase();
                        if (!name.contains(_searchQuery) &&
                            !email.contains(_searchQuery)) {
                          return false;
                        }
                      }

                      return true;
                    }).toList();

                    if (filteredStaff.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Arama kriterlerine uygun personel bulunamadı',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: filteredStaff.length,
                      separatorBuilder: (_, __) => SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final doc = filteredStaff[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final fullName = data['fullName'] ?? 'İsimsiz';
                        final email = data['email'] ?? '';
                        final role = data['role'] ?? 'Personel';
                        final phone = data['phone'] ?? '-';

                        return Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Row(
                              children: [
                                // Avatar
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.shade50,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      fullName.isNotEmpty
                                          ? fullName[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.indigo,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 16),

                                // Bilgiler
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        fullName,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey.shade900,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.indigo.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              role,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.indigo.shade900,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.email_outlined,
                                            size: 14,
                                            color: Colors.grey.shade600,
                                          ),
                                          SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              email,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey.shade600,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.phone_outlined,
                                            size: 14,
                                            color: Colors.grey.shade600,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            phone,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // Düzenleme ve silme butonları
                                if (_canEditStaff())
                                  PopupMenuButton<String>(
                                    icon: Icon(Icons.more_vert),
                                    itemBuilder: (context) => [
                                      PopupMenuItem(
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
                                      PopupMenuItem(
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
                                    ],
                                    onSelected: (value) {
                                      if (value == 'edit') {
                                        _openEditStaffSheet(doc.id, data);
                                      } else if (value == 'delete') {
                                        _deleteStaff(doc.id, fullName);
                                      }
                                    },
                                  ),
                              ],
                            ),
                          ),
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
    );
  }
}

// Personel ekleme/düzenleme formu
class _StaffFormSheet extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;
  final bool isManagerStaff;
  final String? editStaffId;
  final Map<String, dynamic>? initialData;

  const _StaffFormSheet({
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
    required this.isManagerStaff,
    this.editStaffId,
    this.initialData,
  });

  @override
  State<_StaffFormSheet> createState() => _StaffFormSheetState();
}

class _StaffFormSheetState extends State<_StaffFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _fullNameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _tcController;
  String? _selectedRole;
  bool _isSaving = false;

  List<String> _managerRoles = ['Genel Müdür', 'Müdür', 'Müdür Yardımcısı'];
  List<String> _otherRoles = [
    'Personel',
    'Hizmetli',
    'Memur',
    'Muhasebe',
    'İdari İşler',
  ];

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(
      text: widget.initialData?['fullName'] ?? '',
    );
    _emailController = TextEditingController(
      text: widget.initialData?['email'] ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.initialData?['phone'] ?? '',
    );
    _tcController = TextEditingController(
      text: widget.initialData?['tc'] ?? '',
    );
    _selectedRole = widget.initialData?['role'];
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _tcController.dispose();
    super.dispose();
  }

  Future<void> _saveStaff() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      // Yeni kayıtlar için aktif dönemi otomatik al
      final activeTermId = await TermService().getActiveTermId();
      
      final data = {
        'fullName': _fullNameController.text.trim(),
        'email': _emailController.text.trim().toLowerCase(),
        'phone': _phoneController.text.trim(),
        'tc': _tcController.text.trim(),
        'role': _selectedRole,
        'institutionId': widget.institutionId,
        'schoolTypeId': widget.schoolTypeId,
        'termId': activeTermId,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (widget.editStaffId != null) {
        // Güncelleme
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.editStaffId)
            .update(data);
      } else {
        // Yeni ekleme
        data['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('users').add(data);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.editStaffId != null
                  ? '✅ Personel güncellendi'
                  : '✅ Personel eklendi',
            ),
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
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Başlık
                Row(
                  children: [
                    Icon(
                      widget.isManagerStaff
                          ? Icons.admin_panel_settings
                          : Icons.person_outline,
                      color: Colors.indigo,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.editStaffId != null
                                ? 'Personeli Düzenle'
                                : 'Yeni Personel Ekle',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            widget.schoolTypeName,
                            style: TextStyle(
                              fontSize: 14,
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
                SizedBox(height: 24),

                // Ad Soyad
                TextFormField(
                  controller: _fullNameController,
                  decoration: InputDecoration(
                    labelText: 'Ad Soyad *',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ad soyad gerekli';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                // Email
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Email *',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Email gerekli';
                    }
                    if (!value.contains('@')) {
                      return 'Geçerli bir email giriniz';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                // Telefon
                TextFormField(
                  controller: _phoneController,
                  decoration: InputDecoration(
                    labelText: 'Telefon',
                    prefixIcon: Icon(Icons.phone),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                SizedBox(height: 16),

                // TC Kimlik
                TextFormField(
                  controller: _tcController,
                  decoration: InputDecoration(
                    labelText: 'TC Kimlik No',
                    prefixIcon: Icon(Icons.badge),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 11,
                ),
                SizedBox(height: 16),

                // Rol seçimi
                DropdownButtonFormField<String>(
                  value: _selectedRole,
                  decoration: InputDecoration(
                    labelText: 'Rol *',
                    prefixIcon: Icon(Icons.work),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: (widget.isManagerStaff ? _managerRoles : _otherRoles)
                      .map(
                        (role) =>
                            DropdownMenuItem(value: role, child: Text(role)),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _selectedRole = value);
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'Rol seçiniz';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 24),

                // Kaydet butonu
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveStaff,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isSaving
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Text(
                            widget.editStaffId != null ? 'Güncelle' : 'Kaydet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
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
}
