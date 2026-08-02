import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/announcement_service.dart';
import '../services/user_permission_service.dart';
import '../services/role_permission_service.dart';

class AliciSecimi extends StatefulWidget {
  final List<String> selectedRecipients;
  final Map<String, String> initialRecipientNames;
  final List<String> savedGroups;
  final Function(List<String>)? onRecipientsUpdated;
  final Function(String) onSaveGroup;
  final String? schoolTypeId;
  final String? institutionId; // Genel hesap için doğrudan kurum ID
  final Function(Map<String, String>)? onRecipientNamesUpdated;
  final Function(List<String>, Map<String, String>)? onConfirmed;
  final bool isPage;

  const AliciSecimi({
    Key? key,
    required this.selectedRecipients,
    this.initialRecipientNames = const {},
    required this.savedGroups,
    this.onRecipientsUpdated,
    required this.onSaveGroup,
    this.schoolTypeId,
    this.institutionId,
    this.onRecipientNamesUpdated,
    this.onConfirmed,
    this.isPage = false,
  }) : super(key: key);

  @override
  State<AliciSecimi> createState() => _AliciSecimiState();
}

class _AliciSecimiState extends State<AliciSecimi> {
  late List<String> _selectedRecipients;
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final AnnouncementService _announcementService = AnnouncementService();

  String _selectedTargetType = '';
  String _selectedSchoolType = '';
  String _selectedClassLevel = '';
  List<String> _selectedClassLevels = [];
  bool _isClassDropdownOpen = false;

  // Firebase'den gelecek veriler
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _units = [];
  List<Map<String, dynamic>> _schoolTypes = [];
  List<Map<String, dynamic>> _classLevels = [];
  List<Map<String, dynamic>> _groups = [];

  // Displayed users for search filtering
  List<Map<String, dynamic>> _displayedUsers = [];

  final List<String> _recipientTypes = ['Öğrenciler', 'Veliler', 'Öğretmenler'];

  bool _isLoading = false;

  // Map to store display names for recipients (ID -> Name)
  Map<String, String> _recipientNames = {};

  /// Türkçe locale-aware küçük harfe çevirme.
  /// Dart'ın standart toLowerCase() Türkçe'de yanlış sonuç üretir:
  ///   'I'.toLowerCase() => 'i'  (doğrusu 'ı')
  ///   'İ'.toLowerCase() => 'i'  (doğru)
  /// Bu fonksiyon Türkçe'ye özel I→ı ve İ→i dönüşümünü yapar.
  static String _trLower(String s) {
    // Önce Türkçe özel karakterleri düzelt, sonra standart toLowerCase()
    return s
        .replaceAll('I', 'ı')
        .replaceAll('İ', 'i')
        .replaceAll('Ş', 'ş')
        .replaceAll('Ğ', 'ğ')
        .replaceAll('Ü', 'ü')
        .replaceAll('Ö', 'ö')
        .replaceAll('Ç', 'ç')
        .toLowerCase();
  }

  @override
  void initState() {
    super.initState();
    _selectedRecipients = List.from(widget.selectedRecipients);
    _recipientNames = Map.from(widget.initialRecipientNames);
    // Auto-select school type if provided in context
    if (widget.schoolTypeId != null) {
      _selectedSchoolType = widget.schoolTypeId!;
    }
    _loadData();
  }

  /// Geçerli kullanıcının institutionId'sini doğrudan Firestore'dan çöz.
  /// Widget parametrelerine güvenmez — her zaman doğrudan Firebase Auth + Firestore kullanır.
  Future<String?> _resolveInstitutionId() async {
    // 1. Widget parametresi varsa ve geçerliyse onu kullan
    final widgetId = widget.institutionId;
    if (widgetId != null && widgetId.isNotEmpty && widgetId.toUpperCase() != 'GMAIL') {
      return widgetId;
    }

    // 2. schoolTypeId varsa, o dokümanın institutionId'sini al
    if (widget.schoolTypeId != null && widget.schoolTypeId!.isNotEmpty) {
      try {
        final stDoc = await FirebaseFirestore.instance
            .collection('schoolTypes')
            .doc(widget.schoolTypeId!)
            .get();
        final id = stDoc.data()?['institutionId']?.toString();
        if (id != null && id.isNotEmpty) return id;
      } catch (_) {}
    }

    // 3. Mevcut kullanıcının UID'si ile Firestore dokümanına bak
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return null;

    try {
      final uidDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(firebaseUser.uid)
          .get();
      final id = uidDoc.data()?['institutionId']?.toString();
      if (id != null && id.isNotEmpty && id.toUpperCase() != 'GMAIL') return id;
    } catch (_) {}

    // 4. Email ile ara
    try {
      if (firebaseUser.email != null && firebaseUser.email!.isNotEmpty) {
        final q = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: firebaseUser.email!.toLowerCase())
            .limit(3)
            .get();
        for (final doc in q.docs) {
          final id = doc.data()['institutionId']?.toString();
          if (id != null && id.isNotEmpty && id.toUpperCase() != 'GMAIL') return id;
        }
      }
    } catch (_) {}

    // 5. UserPermissionService üzerinden dene
    try {
      final ud = await UserPermissionService.loadUserData();
      final resolved = await UserPermissionService.resolveInstitutionId(
        firebaseUser.email ?? '', userData: ud);
      if (resolved.isNotEmpty && resolved.toUpperCase() != 'GMAIL') return resolved;
    } catch (_) {}

    // 6. Son çare: schoolTypes koleksiyonunda uid/email ile ara
    //    Genel Müdür hesabı users koleksiyonunda yoksa bu fallback devreye girer
    try {
      final schoolTypesSnap = await FirebaseFirestore.instance
          .collection('schoolTypes')
          .limit(1)
          .get();
      if (schoolTypesSnap.docs.isNotEmpty) {
        final id = schoolTypesSnap.docs.first.data()['institutionId']?.toString();
        if (id != null && id.isNotEmpty && id.toUpperCase() != 'GMAIL') {
          debugPrint('⚠️ _resolveInstitutionId: Fallback to schoolTypes collection → $id');
          return id;
        }
      }
    } catch (_) {}

    debugPrint('❌ _resolveInstitutionId: Could not resolve institutionId for uid=${firebaseUser.uid}');
    return null;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Her durumda güvenilir institutionId çöz
      final resolvedInstId = await _resolveInstitutionId();
      debugPrint('🔑 AliciSecimi._loadData: institutionId=$resolvedInstId, schoolTypeId=${widget.schoolTypeId}');

      // Hem null hem de boş string kontrolü
      final hasSchoolType = widget.schoolTypeId != null && widget.schoolTypeId!.isNotEmpty;

      // Kullanıcıları yükle
      List<Map<String, dynamic>> users;
      if (hasSchoolType) {
        // Okul türü bağlamı: o okul türüne ait öğrenci+öğretmen+personel
        users = await _announcementService.getUsersBySchoolType(widget.schoolTypeId!);
      } else {
        // Genel hesap: tüm koleksiyonlardan kullanıcı çek
        users = await _announcementService.getAllUsersIncludingStudents(
          institutionId: resolvedInstId,
        );
      }

      // Birimleri (roller) yükle
      final Map<String, String> mergedRoles = Map.from(RolePermissionService.builtInRoles);
      if (resolvedInstId != null && resolvedInstId.isNotEmpty) {
        try {
          final customTemplates = await RolePermissionService().getAllTemplates(resolvedInstId);
          customTemplates.forEach((key, value) {
            if (!mergedRoles.containsKey(key)) {
              mergedRoles[key] = value['roleName'] ?? key;
            }
          });
        } catch (e) {
          debugPrint('Error loading custom roles in AliciSecimi: $e');
        }
      }

      final List<Map<String, dynamic>> units = mergedRoles.entries.map((e) {
        return {'id': e.key, 'name': e.value};
      }).toList();

      // Okul türleri — resolvedInstId ile çek
      final schoolTypes = await _announcementService.getSchoolTypes(
        institutionId: resolvedInstId,
      );
      // Sınıf seviyeleri — resolvedInstId ile çek
      final classLevels = await _announcementService.getClassLevels(
        institutionId: resolvedInstId,
      );
      final groups = await _announcementService.getGroups();

      debugPrint('📋 Yüklendi: ${users.length} kullanıcı, ${schoolTypes.length} okul türü, ${classLevels.length} sınıf seviyesi');

      // Okul türü filtresi: schoolTypeId varsa sadece o okul türü gösterilir
      List<Map<String, dynamic>> filteredSchoolTypes;
      if (hasSchoolType) {
        filteredSchoolTypes = schoolTypes
            .where((s) => s['id'] == widget.schoolTypeId)
            .toList();
      } else {
        filteredSchoolTypes = schoolTypes; // Genel hesap: tüm okul türleri
      }

      _sortUsersList(users);
      setState(() {
        _allUsers = users;
        _displayedUsers = List.from(users);
        _units = units;
        _schoolTypes = filteredSchoolTypes;
        _classLevels = classLevels;
        _groups = groups;
        _isLoading = false;
      });

      // Şubeleri yükle — schoolTypeId varsa sadece o okul türünün şubeleri
      if (hasSchoolType) {
        await _loadBranchesForSchoolType(widget.schoolTypeId!);
      }
      // Genel hesap için tüm okul türlerinin şubelerini çek
      else if (resolvedInstId != null) {
        await _loadAllBranches();
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Veriler yüklenirken hata oluştu: $e')),
        );
      }
    }
  }


  Widget _buildClassSelection() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    List<Map<String, dynamic>> filteredLevels = _classLevels;

    if (_selectedSchoolType.isNotEmpty) {
      filteredLevels = _classLevels
          .where(
            (l) =>
                l['schoolTypeId'] == _selectedSchoolType ||
                l['schoolType'] == _getSchoolTypeName(_selectedSchoolType),
          )
          .toList();
    } else if (widget.schoolTypeId != null && widget.schoolTypeId!.isNotEmpty) {
      filteredLevels = _classLevels
          .where(
            (l) =>
                l['schoolTypeId'] == widget.schoolTypeId ||
                l['schoolType'] == _getSchoolTypeName(widget.schoolTypeId!),
          )
          .toList();
    }

    final hasSchoolTypeCtx = widget.schoolTypeId != null && widget.schoolTypeId!.isNotEmpty;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        if (!hasSchoolTypeCtx)
          DropdownButtonFormField<String>(
            value: _selectedSchoolType.isEmpty ? null : _selectedSchoolType,
            decoration: const InputDecoration(
              labelText: 'Okul Türüne Göre Filtrele',
              border: OutlineInputBorder(),
            ),
            items: _schoolTypes
                .map(
                  (st) => DropdownMenuItem<String>(
                    value: st['id'] as String,
                    child: Text(st['name'] as String),
                  ),
                )
                .toList(),
            onChanged: (val) {
              setState(() {
                _selectedSchoolType = val ?? '';
                _selectedClassLevels.clear();
              });
            },
          ),

        if (!hasSchoolTypeCtx) const SizedBox(height: 16),

        // Premium Multi-Select Dropdown Field
        GestureDetector(
          onTap: () {
            setState(() {
              _isClassDropdownOpen = !_isClassDropdownOpen;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isClassDropdownOpen ? Colors.indigo : Colors.grey.shade400,
                width: _isClassDropdownOpen ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _selectedClassLevels.isEmpty
                        ? 'Sınıf Seviyesi Seç'
                        : _selectedClassLevels.map((id) => _getClassName(id)).join(', '),
                    style: TextStyle(
                      color: _selectedClassLevels.isEmpty ? Colors.grey.shade600 : Colors.grey.shade900,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  _isClassDropdownOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  color: Colors.grey.shade700,
                ),
              ],
            ),
          ),
        ),

        if (_isClassDropdownOpen) ...[
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Scrollbar(
              thumbVisibility: true,
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  ...filteredLevels.map((level) {
                    final id = (level['id'] ?? '').toString();
                    final name = _selectedSchoolType.isNotEmpty || (widget.schoolTypeId != null && widget.schoolTypeId!.isNotEmpty)
                        ? level['name']
                        : '${level['name']} (${level['schoolType']})';
                    final isChecked = _selectedClassLevels.contains(id);

                    return CheckboxListTile(
                      title: Text(name, style: const TextStyle(fontSize: 13)),
                      dense: true,
                      value: isChecked,
                      activeColor: Colors.indigo,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedClassLevels.add(id);
                          } else {
                            _selectedClassLevels.remove(id);
                          }
                        });
                      },
                    );
                  }).toList(),
                ],
              ),
            ),
          ),
        ],

        if (_selectedClassLevels.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text(
            'Alıcı Türü Seç',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          ..._recipientTypes.map((type) {
            final isAllSelected = _selectedClassLevels.every((clId) => _selectedRecipients.contains('class:$clId:$type'));
            
            return CheckboxListTile(
              title: Text(type),
              subtitle: Text('Seçili tüm sınıflardaki $type'),
              value: isAllSelected,
              onChanged: (value) {
                setState(() {
                  for (final clId in _selectedClassLevels) {
                    final recipientId = 'class:$clId:$type';
                    final className = _getClassName(clId);
                    final displayName = '$className-$type';

                    if (value == true) {
                      if (!_selectedRecipients.contains(recipientId)) {
                        _selectedRecipients.add(recipientId);
                        _recipientNames[recipientId] = displayName;
                      }
                      // Öğrenci seçilince Veli de otomatik ekle
                      if (type == 'Öğrenciler') {
                        final veliId = 'class:$clId:Veliler';
                        final veliName = '$className-Veliler';
                        if (!_selectedRecipients.contains(veliId)) {
                          _selectedRecipients.add(veliId);
                          _recipientNames[veliId] = veliName;
                        }
                      }
                    } else {
                      _selectedRecipients.remove(recipientId);
                      _recipientNames.remove(recipientId);
                      // Öğrenci kaldırılınca Veli de kaldır
                      if (type == 'Öğrenciler') {
                        final veliId = 'class:$clId:Veliler';
                        _selectedRecipients.remove(veliId);
                        _recipientNames.remove(veliId);
                      }
                    }
                  }
                });
                widget.onRecipientsUpdated?.call(_selectedRecipients);
                widget.onRecipientNamesUpdated?.call(_recipientNames);
              },
            );
          }),
        ],
      ],
    ),
    );
  }

  String _getClassName(String id) {
    final classLevel = _classLevels.firstWhere(
      (cl) => cl['id'] == id,
      orElse: () => {'name': id, 'schoolType': ''},
    );
    return classLevel['name'];
  }

  Future<void> _showSaveGroupDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Grup Kaydet'),
        content: TextField(
          controller: _groupNameController,
          decoration: const InputDecoration(
            labelText: 'Grup Adı',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () async {
              if (_groupNameController.text.isNotEmpty) {
                try {
                  await _announcementService.saveGroup(
                    _groupNameController.text,
                    _selectedRecipients,
                  );
                  widget.onSaveGroup(_groupNameController.text);
                  _groupNameController.clear();
                  Navigator.pop(context);
                  await _loadData(); // Grupları yeniden yükle
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Grup başarıyla kaydedildi'),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Grup kaydedilemedi: $e')),
                    );
                  }
                }
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  void _addRecipients(List<String> recipients, {Map<String, String>? names}) {
    setState(() {
      _selectedRecipients.addAll(recipients);
      _selectedRecipients = _selectedRecipients.toSet().toList();

      if (names != null) {
        _recipientNames.addAll(names);
      }
    });
    widget.onRecipientsUpdated?.call(_selectedRecipients);
    widget.onRecipientNamesUpdated?.call(_recipientNames);
  }

  void _removeRecipient(String recipient) {
    setState(() {
      _selectedRecipients.remove(recipient);
      _recipientNames.remove(recipient);
    });
    widget.onRecipientsUpdated?.call(_selectedRecipients);
    widget.onRecipientNamesUpdated?.call(_recipientNames);
  }

  void _clearAllRecipients() {
    setState(() {
      _selectedRecipients.clear();
      _recipientNames.clear();
    });
    widget.onRecipientsUpdated?.call(_selectedRecipients);
    widget.onRecipientNamesUpdated?.call(_recipientNames);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;
    final showAsPage = widget.isPage || isMobile;

    if (showAsPage) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.indigo.shade600, Colors.purple.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Alıcı Seçimi',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                'Hedef kitlenizi seçin',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.8),
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
          leading: IconButton(
            icon: Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            if (_selectedRecipients.isNotEmpty)
              Center(
                child: Container(
                  margin: EdgeInsets.only(right: 16),
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 14),
                      SizedBox(width: 4),
                      Text(
                        '${_selectedRecipients.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          elevation: 0,
        ),
        body: Column(
          children: [
            _buildCategorySelector(),
            Expanded(
              child: Container(
                padding: EdgeInsets.all(16),
                child: _buildTargetSpecificContent(),
              ),
            ),
            _buildBottomActionBar(isMobile: true),
          ],
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: Container(
        width: 650,
        height: 720,
        constraints: BoxConstraints(maxWidth: 650, maxHeight: 720),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 30,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Modern Header with Gradient
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.indigo.shade600, Colors.purple.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.people_alt_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Alıcı Seçimi',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Hedef kitlenizi seçin',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_selectedRecipients.isNotEmpty)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 16,
                          ),
                          SizedBox(width: 4),
                          Text(
                            '${_selectedRecipients.length}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            _buildCategorySelector(),

            // Content Area
            Expanded(
              child: Container(
                padding: EdgeInsets.all(16),
                child: _buildTargetSpecificContent(),
              ),
            ),

            _buildBottomActionBar(isMobile: false),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySelector() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: BouncingScrollPhysics(),
          child: Row(
            children: [
              _buildCategoryChip('person', Icons.person, 'Kişi'),
              SizedBox(width: 8),
              _buildCategoryChip('branch', Icons.class_, 'Şube'),
              SizedBox(width: 8),
              _buildCategoryChip('class', Icons.school, 'Sınıf'),
              SizedBox(width: 8),
              _buildCategoryChip('school', Icons.account_balance, 'Okul'),
              SizedBox(width: 8),
              _buildCategoryChip('unit', Icons.business, 'Birim'),
              SizedBox(width: 8),
              _buildCategoryChip('group', Icons.group, 'Grup'),
              SizedBox(width: 8),
              _buildCategoryChip('selected', Icons.check_circle, 'Seçilenler'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActionBar({required bool isMobile}) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: isMobile
            ? null
            : BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          if (_selectedRecipients.isNotEmpty) ...[
            _buildActionButton(
              icon: Icons.clear_all,
              label: 'Temizle',
              color: Colors.red.shade400,
              onPressed: _clearAllRecipients,
            ),
            _buildActionButton(
              icon: Icons.save,
              label: 'Grup Kaydet',
              color: Colors.green.shade500,
              onPressed: _showSaveGroupDialog,
            ),
          ],
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text('İptal', style: TextStyle(fontSize: 14)),
          ),
          ElevatedButton(
            onPressed: () {
              if (widget.onConfirmed != null) {
                widget.onConfirmed!(_selectedRecipients, _recipientNames);
              } else {
                widget.onRecipientsUpdated?.call(_selectedRecipients);
                widget.onRecipientNamesUpdated?.call(_recipientNames);
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check, size: 18),
                SizedBox(width: 8),
                Text(
                  'Tamam',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String value, IconData icon, String label) {
    final isSelected = _selectedTargetType == value;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedTargetType = value;
            _selectedSchoolType = '';
            _selectedClassLevel = '';
            if (value == 'branch') {
              _loadAllBranches();
            }
          });
        },
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.indigo : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? Colors.indigo : Colors.grey.shade300,
              width: 1.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.indigo.withOpacity(0.3),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : Colors.grey.shade600,
              ),
              SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey.shade700,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: color),
      label: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w500),
      ),
      style: TextButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildTargetSpecificContent() {
    switch (_selectedTargetType) {
      case 'person':
        return _buildPersonSelection();
      case 'unit':
        return _buildUnitSelection();
      case 'school':
        return _buildSchoolSelection();
      case 'branch':
        return _buildBranchSelection();
      case 'class':
        return _buildClassSelection();
      case 'group':
        return _buildGroupSelection();
      case 'selected':
        return _buildSelectedRecipientsList();
      default:
        return const Center(
          child: Text(
            'Lütfen hedef kitle seçiniz',
            style: TextStyle(color: Colors.grey),
          ),
        );
    }
  }

  Widget _buildBranchSelection() {
    final hasSchoolTypeCtx = widget.schoolTypeId != null && widget.schoolTypeId!.isNotEmpty;
    // Genel hesapta okul türü seçilmemişse önce okul türü seç
    if (!hasSchoolTypeCtx && _selectedSchoolType.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.school_rounded, size: 56, color: Colors.indigo.shade200),
              const SizedBox(height: 16),
              Text(
                'Önce Okul Türü Seçin',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'Okul Türü',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.school_rounded, color: Colors.indigo),
                ),
                items: _schoolTypes.map((type) => DropdownMenuItem<String>(
                  value: type['id'] as String,
                  child: Text(type['name'] as String),
                )).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedSchoolType = val);
                    _loadBranchesForSchoolType(val);
                  }
                },
              ),
            ],
          ),
        ),
      );
    }

    if (_loadingBranches) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.indigo),
            SizedBox(height: 16),
            Text(
              'Şubeler yükleniyor...',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    if (_branches.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.class_, size: 64, color: Colors.grey.shade300),
            SizedBox(height: 16),
            Text(
              'Şube bulunamadı',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.class_, color: Colors.green.shade700, size: 20),
              SizedBox(width: 8),
              Text(
                'Şube Seç',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
              Spacer(),
              Text(
                '${_branches.length} şube',
                style: TextStyle(color: Colors.green.shade600, fontSize: 12),
              ),
            ],
          ),
        ),
        SizedBox(height: 12),
        // Table Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  'Şube Adı',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey.shade700),
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  'Öğr.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue.shade700),
                ),
              ),
              SizedBox(width: 8),
              SizedBox(
                width: 48,
                child: Text(
                  'Veli',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.orange.shade700),
                ),
              ),
              SizedBox(width: 8),
              SizedBox(
                width: 48,
                child: Text(
                  'Öğrt.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.purple.shade700),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: _branches.length,
            itemBuilder: (context, index) {
              final branch = _branches[index];
              final branchName = branch['name'] ?? 'Şube';
              final classLevel = branch['classLevel']?.toString() ?? '';

              final studentId = 'branch:${branch['id']}:Öğrenciler';
              final parentId = 'branch:${branch['id']}:Veliler';
              final teacherId = 'branch:${branch['id']}:Öğretmenler';

              final isStudentSelected = _selectedRecipients.contains(studentId);
              final isParentSelected = _selectedRecipients.contains(parentId);
              final isTeacherSelected = _selectedRecipients.contains(teacherId);

              return Container(
                margin: EdgeInsets.only(bottom: 6),
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.01),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            branchName,
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          if (classLevel.isNotEmpty)
                            Text(
                              '$classLevel. Sınıf seviyesi',
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Checkbox(
                        value: isStudentSelected,
                        activeColor: Colors.blue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        onChanged: (val) {
                          if (val == true) {
                            _addRecipients([studentId], names: {studentId: '$branchName-Öğrenciler'});
                            // Öğrenci seçilince Veli de otomatik ekle
                            if (!_selectedRecipients.contains(parentId)) {
                              _addRecipients([parentId], names: {parentId: '$branchName-Veliler'});
                            }
                          } else {
                            _removeRecipient(studentId);
                            // Öğrenci kaldırılınca Veli de kaldır
                            _removeRecipient(parentId);
                          }
                          setState(() {});
                        },
                      ),
                    ),
                    SizedBox(width: 8),
                    SizedBox(
                      width: 48,
                      child: Checkbox(
                        value: isParentSelected,
                        activeColor: Colors.orange,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        onChanged: (val) {
                          if (val == true) {
                            _addRecipients([parentId], names: {parentId: '$branchName-Veliler'});
                          } else {
                            _removeRecipient(parentId);
                          }
                          setState(() {});
                        },
                      ),
                    ),
                    SizedBox(width: 8),
                    SizedBox(
                      width: 48,
                      child: Checkbox(
                        value: isTeacherSelected,
                        activeColor: Colors.purple,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        onChanged: (val) {
                          if (val == true) {
                            _addRecipients([teacherId], names: {teacherId: '$branchName-Öğretmenler'});
                          } else {
                            _removeRecipient(teacherId);
                          }
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'Öğrenciler':
        return Colors.blue;
      case 'Veliler':
        return Colors.orange;
      case 'Öğretmenler':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Future<void> _loadAllBranches() async {
    setState(() => _loadingBranches = true);
    try {
      List<Map<String, dynamic>> all = [];

      final hasSchoolTypeCtx = widget.schoolTypeId != null && widget.schoolTypeId!.isNotEmpty;

      if (hasSchoolTypeCtx) {
        var b = await _announcementService.getBranches(widget.schoolTypeId!);
        all.addAll(b);
      } else {
        for (var st in _schoolTypes) {
          var b = await _announcementService.getBranches(st['id']);
          all.addAll(b);
        }
      }

      setState(() {
        _branches = all;
        _loadingBranches = false;
      });
    } catch (e) {
      setState(() => _loadingBranches = false);
    }
  }

  Future<void> _loadBranchesForSchoolType(String schoolTypeId) async {
    setState(() => _loadingBranches = true);
    try {
      final branches = await _announcementService.getBranches(schoolTypeId);
      setState(() {
        _branches = branches;
        _loadingBranches = false;
      });
    } catch (e) {
      setState(() => _loadingBranches = false);
    }
  }

  String _selectedBranchId = '';
  List<Map<String, dynamic>> _branches = [];
  bool _loadingBranches = false;

  String _buildUserSubtitle(Map<String, dynamic> user) {
    final rawRole = user['role'] ?? 'Kullanıcı';
    final role = _normalizeRole(rawRole);
    final branch = user['branch']?.toString() ?? '';

    if (role == 'Öğrenci' && branch.isNotEmpty) {
      return '$role - $branch';
    } else if (branch.isNotEmpty) {
      return '$role - $branch';
    } else if (user['email'] != null && user['email'].toString().isNotEmpty) {
      return '$role - ${user['email']}';
    } else {
      return role;
    }
  }

  String _normalizeRole(String role) {
    final lowerRole = role.toLowerCase().trim();

    if (lowerRole == 'ogretmen' ||
        lowerRole == 'öğretmen' ||
        lowerRole == 'teacher') {
      return 'Öğretmen';
    } else if (lowerRole == 'ogrenci' ||
        lowerRole == 'öğrenci' ||
        lowerRole == 'student') {
      return 'Öğrenci';
    } else if (lowerRole == 'veli' || lowerRole == 'parent') {
      return 'Veli';
    } else if (lowerRole == 'mudur' ||
        lowerRole == 'müdür' ||
        lowerRole == 'principal') {
      return 'Müdür';
    } else if (lowerRole == 'mudur yardimcisi' ||
        lowerRole == 'müdür yardımcısı') {
      return 'Müdür Yardımcısı';
    } else if (lowerRole == 'rehber' ||
        lowerRole == 'counselor' ||
        lowerRole == 'rehber öğretmen') {
      return 'Rehber Öğretmen';
    } else if (lowerRole == 'idari personel' || lowerRole == 'staff') {
      return 'İdari Personel';
    } else if (lowerRole == 'admin' || lowerRole == 'yönetici') {
      return 'Yönetici';
    }

    if (role.isNotEmpty) {
      return role[0].toUpperCase() + role.substring(1);
    }
    return 'Kullanıcı';
  }

  Widget _buildPersonSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Kullanıcı Ara',
              hintText: 'Ad, soyad veya e-posta yazınız...',
              prefixIcon: Icon(Icons.search, color: Colors.indigo),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _displayedUsers = List.from(_allUsers);
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.transparent,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            onChanged: (val) {
              if (val.length > 2) {
                _performUserSearch(val);
              } else if (val.isEmpty) {
                setState(() {
                  _displayedUsers = List.from(_allUsers);
                });
              }
            },
          ),
        ),
        SizedBox(height: 16),

        if (_displayedUsers.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '${_displayedUsers.length} kullanıcı bulundu',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),

        Expanded(
          child: _isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Colors.indigo),
                      SizedBox(height: 12),
                      Text(
                        'Yükleniyor...',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : _displayedUsers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_alt_rounded, size: 64, color: Colors.grey.shade300),
                      SizedBox(height: 16),
                      Text(
                        _isLoading ? 'Yükleniyor...' : 'Kullanıcı bulunamadı',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      if (!_isLoading) ...[  
                        SizedBox(height: 4),
                        Text(
                          'Arama kutusuna en az 3 karakter yazın',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _displayedUsers.length,
                  itemBuilder: (context, index) {
                    final user = _displayedUsers[index];
                    final userId = 'user:${user['id']}';
                    final isSelected = _selectedRecipients.contains(userId);
                    final role = _normalizeRole(user['role'] ?? 'Kullanıcı');

                    Color avatarColor;
                    if (role == 'Öğrenci') {
                      avatarColor = Colors.blue;
                    } else if (role == 'Öğretmen') {
                      avatarColor = Colors.purple;
                    } else if (role == 'Veli') {
                      avatarColor = Colors.orange;
                    } else {
                      avatarColor = Colors.grey;
                    }

                    return Container(
                      margin: EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.indigo.shade50
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? Colors.indigo.shade300
                              : Colors.grey.shade200,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: avatarColor.withOpacity(0.2),
                          child: Text(
                            (_getUserDisplayName(user))[0].toUpperCase(),
                            style: TextStyle(
                              color: avatarColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          _getUserDisplayName(user),
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          _buildUserSubtitle(user),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        trailing: AnimatedContainer(
                          duration: Duration(milliseconds: 200),
                          padding: EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.green
                                : Colors.grey.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isSelected ? Icons.check : Icons.add,
                            color: isSelected
                                ? Colors.white
                                : Colors.grey.shade600,
                            size: 18,
                          ),
                        ),
                        onTap: () {
                          if (isSelected) {
                            _removeRecipient(userId);
                          } else {
                            final name = _getUserDisplayName(user);
                            final branch = user['branch']?.toString() ?? '';
                            final displayName = branch.isNotEmpty
                                ? '$name ($branch)'
                                : name;
                            _addRecipients(
                              [userId],
                              names: {userId: displayName},
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

  Widget _buildUnitSelection() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.business, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Birim Seç',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
              const Spacer(),
              Text(
                '${_units.length} birim',
                style: TextStyle(color: Colors.blue.shade600, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _units.isEmpty
              ? const Center(child: Text('Birim bulunamadı'))
              : ListView.builder(
                  itemCount: _units.length,
                  itemBuilder: (context, index) {
                    final unit = _units[index];
                    final unitId = 'unit:${unit['id']}';
                    final isSelected = _selectedRecipients.contains(unitId);
                    final roleColor = RolePermissionService.getRoleColor(unit['id'] as String);
                    final roleIcon = RolePermissionService.getRoleIcon(unit['id'] as String);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? roleColor.withOpacity(0.05) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? roleColor : Colors.grey.shade200,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: roleColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            roleIcon,
                            color: roleColor,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          unit['name'],
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isSelected ? roleColor : Colors.grey.shade800,
                          ),
                        ),
                        subtitle: Text(
                          'Tüm ${unit['name']} personeli',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        ),
                        trailing: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.green : Colors.grey.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isSelected ? Icons.check : Icons.add,
                            color: isSelected ? Colors.white : Colors.grey.shade600,
                            size: 18,
                          ),
                        ),
                        onTap: () {
                          final displayName = unit['name'] ?? 'Birim';
                          if (isSelected) {
                            _removeRecipient(unitId);
                          } else {
                            _addRecipients(
                              [unitId],
                              names: {unitId: displayName},
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

  Future<void> _performUserSearch(String query) async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 100));

    if (query.isEmpty) {
      setState(() {
        _displayedUsers = List.from(_allUsers);
        _isLoading = false;
      });
      return;
    }

    // Türkçe-farkında büyük/küçük harf duyarsız arama
    final lowerQuery = _trLower(query);
    final results = _allUsers.where((user) {
      final name = _trLower((user['name'] ?? '').toString());
      final email = _trLower((user['email'] ?? '').toString());
      final role = _trLower((user['role'] ?? '').toString());
      final username = _trLower((user['username'] ?? '').toString());
      final branch = _trLower((user['branch'] ?? '').toString());

      return name.contains(lowerQuery) ||
          email.contains(lowerQuery) ||
          role.contains(lowerQuery) ||
          username.contains(lowerQuery) ||
          branch.contains(lowerQuery);
    }).toList();

    _sortUsersList(results);
    setState(() {
      _displayedUsers = results;
      _isLoading = false;
    });
  }

  Widget _buildSchoolSelection() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Auto-select school type if we have it from context (null ve boş olmayan)
    final hasSchoolTypeCtx = widget.schoolTypeId != null && widget.schoolTypeId!.isNotEmpty;
    if (hasSchoolTypeCtx && _selectedSchoolType.isEmpty) {
      _selectedSchoolType = widget.schoolTypeId!;
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasSchoolTypeCtx)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.indigo.shade100),
              ),
              child: Row(
                children: [
                  Icon(Icons.school, color: Colors.indigo.shade700, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Seçili Okul Türü',
                          style: TextStyle(fontSize: 11, color: Colors.indigo, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _getSchoolTypeName(_selectedSchoolType),
                          style: TextStyle(fontSize: 14, color: Colors.indigo.shade900, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            DropdownButtonFormField<String>(
              value: _selectedSchoolType.isEmpty ? null : _selectedSchoolType,
              decoration: const InputDecoration(
                labelText: 'Okul Türü Seç',
                border: OutlineInputBorder(),
              ),
              items: _schoolTypes
                  .map(
                    (type) => DropdownMenuItem<String>(
                      value: type['id'] as String,
                      child: Text(type['name'] as String),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedSchoolType = value ?? '';
                });
              },
            ),

          if (_selectedSchoolType.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Alıcı Türü Seç',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),

            ..._recipientTypes.map((type) {
              final recipientId = 'school:$_selectedSchoolType:$type';
              final schoolTypeName = _getSchoolTypeName(_selectedSchoolType);
              final displayName = '$schoolTypeName-$type';
              final subtitle = '$schoolTypeName - tüm $type';

              return CheckboxListTile(
                title: Text(type),
                subtitle: Text(subtitle),
                value: _selectedRecipients.contains(recipientId),
                onChanged: (value) {
                  if (value == true) {
                    _addRecipients(
                      [recipientId],
                      names: {recipientId: displayName},
                    );
                  } else {
                    _removeRecipient(recipientId);
                  }
                },
              );
            }),
          ],
        ],
      ),
    );
  }

  Future<void> _loadBranches(String schoolTypeId) async {
    setState(() => _loadingBranches = true);
    final list = await _announcementService.getBranches(schoolTypeId);
    setState(() {
      _branches = list;
      _loadingBranches = false;
    });
  }

  String _getSchoolTypeName(String id) {
    final schoolType = _schoolTypes.firstWhere(
      (st) => st['id'] == id,
      orElse: () => {'name': id},
    );
    return schoolType['name'];
  }

  Widget _buildGroupSelection() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.indigo),
            SizedBox(height: 12),
            Text(
              'Gruplar yükleniyor...',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.group, color: Colors.teal.shade700, size: 20),
              SizedBox(width: 8),
              Text(
                'Kayıtlı Gruplar',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade700,
                ),
              ),
              Spacer(),
              Text(
                '${_groups.length} grup',
                style: TextStyle(color: Colors.teal.shade600, fontSize: 12),
              ),
              SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _showSaveGroupDialog,
                icon: Icon(Icons.add, size: 16),
                label: Text('Yeni Grup'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12),
        Expanded(
          child: _groups.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.group_off,
                        size: 64,
                        color: Colors.grey.shade300,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Kayıtlı grup bulunmamaktadır',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _showSaveGroupDialog,
                        icon: Icon(Icons.add),
                        label: Text('İlk Grubu Oluştur'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _groups.length,
                  itemBuilder: (context, index) {
                    final group = _groups[index];
                    final groupId = 'group:${group['id']}';
                    final isSelected = _selectedRecipients.contains(groupId);
                    final recipientCount =
                        (group['recipients'] as List?)?.length ?? 0;

                    return Container(
                      margin: EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.teal.shade50 : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? Colors.teal.shade300
                              : Colors.grey.shade200,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.group,
                            color: Colors.teal.shade700,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          group['name'] ?? 'İsimsiz Grup',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '$recipientCount alıcı',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                color: Colors.red.shade400,
                                size: 20,
                              ),
                              tooltip: 'Grubu Sil',
                              onPressed: () => _confirmDeleteGroup(group),
                            ),
                            SizedBox(width: 4),
                            AnimatedContainer(
                              duration: Duration(milliseconds: 200),
                              padding: EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.green
                                    : Colors.grey.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isSelected ? Icons.check : Icons.add,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.grey.shade600,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          final displayName = group['name'] ?? 'Grup';
                          if (isSelected) {
                            _removeRecipient(groupId);
                          } else {
                            _addRecipients(
                              [groupId],
                              names: {groupId: displayName},
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

  void _confirmDeleteGroup(Map<String, dynamic> group) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('Grubu Sil'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bu grubu silmek istediğinizden emin misiniz?'),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.group, color: Colors.teal),
                  SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group['name'] ?? 'İsimsiz Grup',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${(group['recipients'] as List?)?.length ?? 0} alıcı',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
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
              Navigator.pop(context);
              await _deleteGroup(group['id']);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Sil'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteGroup(String groupId) async {
    try {
      setState(() => _isLoading = true);

      await _announcementService.deleteRecipientGroup(groupId);

      setState(() {
        _groups.removeWhere((g) => g['id'] == groupId);
        _selectedRecipients.removeWhere((r) => r == 'group:$groupId');
        _recipientNames.remove('group:$groupId');
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Grup başarıyla silindi'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 8),
                Text('Grup silinirken hata oluştu: $e'),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildSelectedRecipientsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.indigo.shade50, Colors.purple.shade50],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.indigo.shade700, size: 20),
              SizedBox(width: 8),
              Text(
                'Seçilen Alıcılar',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo.shade700,
                ),
              ),
              Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_selectedRecipients.length}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade700,
                  ),
                ),
              ),
              if (_selectedRecipients.isNotEmpty) ...[
                SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _clearAllRecipients,
                  icon: Icon(
                    Icons.clear_all,
                    size: 16,
                    color: Colors.red.shade400,
                  ),
                  label: Text(
                    'Temizle',
                    style: TextStyle(color: Colors.red.shade400),
                  ),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: 16),
        Expanded(
          child: _selectedRecipients.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 64,
                        color: Colors.grey.shade300,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Henüz alıcı seçilmedi',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Yukarıdaki kategorilerden alıcı ekleyin',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _selectedRecipients.length,
                  itemBuilder: (context, index) {
                    final recipientId = _selectedRecipients[index];
                    final displayName =
                        _recipientNames[recipientId] ?? recipientId;

                    Color cardColor;
                    Color textColor;
                    IconData icon;

                    if (recipientId.startsWith('user:')) {
                      cardColor = Colors.blue.shade50;
                      textColor = Colors.blue.shade700;
                      icon = Icons.person;
                    } else if (recipientId.startsWith('branch:')) {
                      cardColor = Colors.green.shade50;
                      textColor = Colors.green.shade700;
                      icon = Icons.class_;
                    } else if (recipientId.startsWith('class:')) {
                      cardColor = Colors.orange.shade50;
                      textColor = Colors.orange.shade700;
                      icon = Icons.school;
                    } else if (recipientId.startsWith('school:')) {
                      cardColor = Colors.purple.shade50;
                      textColor = Colors.purple.shade700;
                      icon = Icons.account_balance;
                    } else if (recipientId.startsWith('unit:')) {
                      cardColor = Colors.teal.shade50;
                      textColor = Colors.teal.shade700;
                      icon = Icons.business;
                    } else {
                      cardColor = Colors.grey.shade100;
                      textColor = Colors.grey.shade700;
                      icon = Icons.group;
                    }

                    return Container(
                      margin: EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: textColor.withOpacity(0.3)),
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: textColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(icon, color: textColor, size: 20),
                        ),
                        title: Text(
                          displayName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        subtitle: Text(
                          _getRecipientTypeLabel(recipientId),
                          style: TextStyle(
                            fontSize: 11,
                            color: textColor.withOpacity(0.7),
                          ),
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.remove_circle,
                            color: Colors.red.shade400,
                          ),
                          onPressed: () => _removeRecipient(recipientId),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _getRecipientTypeLabel(String id) {
    if (id.startsWith('user:')) return 'Kişi';
    if (id.startsWith('branch:')) return 'Şube';
    if (id.startsWith('class:')) return 'Sınıf Seviyesi';
    if (id.startsWith('school:')) return 'Okul/Kurum';
    if (id.startsWith('unit:')) return 'Birim';
    if (id.startsWith('group:')) return 'Grup';
    return 'Diğer';
  }

  String _getUserDisplayName(Map<String, dynamic> user) {
    final name = (user['fullName'] ?? user['name'] ?? user['displayName'] ?? '').toString().trim();
    if (name.isNotEmpty && name != 'null' && name != 'İsimsiz') return name;

    final first = (user['firstName'] ?? user['first_name'] ?? user['studentName'] ?? user['teacherName'] ?? user['parentName'] ?? '').toString().trim();
    final last = (user['lastName'] ?? user['last_name'] ?? user['surname'] ?? '').toString().trim();
    if (first.isNotEmpty || last.isNotEmpty) {
      return '$first $last'.trim();
    }

    final email = (user['email'] ?? user['username'] ?? '').toString().trim();
    if (email.isNotEmpty && email != 'null') return email;

    return 'Kullanıcı';
  }

  static const String _trAlphabet = 'aabccçdeefgğhıijklmnoöprsştuüvyzAABCCÇDEEFGĞHIİJKLMNOÖPRSŞTUÜVYZ0123456789';

  static int _trCompare(String str1, String str2) {
    final s1 = str1.trim();
    final s2 = str2.trim();
    final len = s1.length < s2.length ? s1.length : s2.length;

    for (int i = 0; i < len; i++) {
      final c1 = s1[i];
      final c2 = s2[i];
      if (c1 == c2) continue;

      final idx1 = _trAlphabet.indexOf(c1);
      final idx2 = _trAlphabet.indexOf(c2);

      if (idx1 != -1 && idx2 != -1) {
        if (idx1 != idx2) return idx1.compareTo(idx2);
      } else {
        final cmp = c1.compareTo(c2);
        if (cmp != 0) return cmp;
      }
    }
    return s1.length.compareTo(s2.length);
  }

  int _getRolePriority(String roleStr) {
    final r = roleStr.toLowerCase().trim();
    if (r.contains('genel_mudur') || r.contains('genel müdür') || r.contains('kurucu') || r.contains('admin') || r.contains('yönetici')) {
      return 0; // Genel Müdür / Kurucu / Admin
    }
    if (r.contains('müdür') || r.contains('mudur') || r.contains('director')) {
      if (r.contains('yardımcı') || r.contains('yardimci') || r.contains('vice')) {
        return 2; // Müdür Yardımcısı
      }
      return 1; // Müdür
    }
    if (r.contains('öğretmen') || r.contains('ogretmen') || r.contains('teacher')) {
      return 3; // Öğretmen
    }
    if (r.contains('personel') || r.contains('muhasebe') || r.contains('idari') || r.contains('rehberlik') || r.contains('psikolojik')) {
      return 4; // Personel / İdari
    }
    if (r.contains('veli') || r.contains('parent')) {
      return 5; // Veli
    }
    if (r.contains('öğrenci') || r.contains('ogrenci') || r.contains('student')) {
      return 6; // Öğrenci
    }
    return 7;
  }

  void _sortUsersList(List<Map<String, dynamic>> users) {
    users.sort((a, b) {
      final roleA = (a['role'] ?? '').toString();
      final roleB = (b['role'] ?? '').toString();
      final priorityA = _getRolePriority(roleA);
      final priorityB = _getRolePriority(roleB);

      if (priorityA != priorityB) {
        return priorityA.compareTo(priorityB);
      }

      final nameA = _getUserDisplayName(a);
      final nameB = _getUserDisplayName(b);
      return _trCompare(nameA, nameB);
    });
  }
}
