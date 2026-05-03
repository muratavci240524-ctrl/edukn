import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../constants/app_modules.dart';
import '../../../constants/school_type_modules.dart';
import '../../../services/role_permission_service.dart';
import '../../../services/user_permission_service.dart';

class PermissionDefinitionScreen extends StatefulWidget {
  const PermissionDefinitionScreen({Key? key}) : super(key: key);

  @override
  State<PermissionDefinitionScreen> createState() =>
      _PermissionDefinitionScreenState();
}

class _PermissionDefinitionScreenState
    extends State<PermissionDefinitionScreen> {
  final RolePermissionService _roleService = RolePermissionService();
  String? _institutionId;
  bool _isLoading = true;

  /// roleKey → template data (from Firestore)
  Map<String, Map<String, dynamic>> _templates = {};

  /// Merged list: built‑in roles + custom roles from Firestore
  Map<String, String> _allRoles = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final userData = await UserPermissionService.loadUserData();
      _institutionId = userData?['institutionId'];

      if (_institutionId == null) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && user.email != null) {
          _institutionId =
              user.email!.split('@')[1].split('.')[0].toUpperCase();
        }
      }

      if (_institutionId != null) {
        _templates = await _roleService.getAllTemplates(_institutionId!);
      }

      // Merge built‑in + custom
      _allRoles = {...RolePermissionService.builtInRoles};
      for (var key in _templates.keys) {
        if (!_allRoles.containsKey(key)) {
          _allRoles[key] = _templates[key]?['roleName'] ?? key;
        }
      }
    } catch (e) {
      debugPrint('Error loading permissions: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ──────────────────────────────────────────────────────────
  //  UI
  // ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Yetki Tanımlama',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            color: Colors.indigo.shade900,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.indigo.shade900),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton.icon(
              onPressed: _showAddRoleDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Yeni Tür Ekle'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_allRoles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.security, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('Henüz kullanıcı türü tanımlanmamış'),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        mainAxisExtent: 200,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: _allRoles.length,
      itemBuilder: (context, index) {
        final roleKey = _allRoles.keys.elementAt(index);
        final roleName = _allRoles[roleKey]!;
        final hasTemplate = _templates.containsKey(roleKey);
        final isBuiltIn = RolePermissionService.isBuiltIn(roleKey);
        return _buildRoleCard(roleKey, roleName, hasTemplate, isBuiltIn);
      },
    );
  }

  // ──────────────────────────────────────────────────────────
  //  Role Card
  // ──────────────────────────────────────────────────────────
  Widget _buildRoleCard(
      String roleKey, String roleName, bool hasTemplate, bool isBuiltIn) {
    final color = RolePermissionService.getRoleColor(roleKey);
    final icon = RolePermissionService.getRoleIcon(roleKey);

    // Count active permissions
    int activeCount = 0;
    if (hasTemplate) {
      final app = _templates[roleKey]?['appPermissions'] as Map? ?? {};
      final st = _templates[roleKey]?['schoolTypePermissions'] as Map? ?? {};
      app.forEach((_, v) {
        if (v is Map && v['enabled'] == true) activeCount++;
      });
      st.forEach((_, v) {
        if (v is Map && v['enabled'] == true) activeCount++;
      });
    }

    return InkWell(
      onTap: () => _openEditor(roleKey, roleName),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(
            color: hasTemplate ? color.withOpacity(0.3) : Colors.grey.shade200,
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const Spacer(),
                if (!isBuiltIn)
                  IconButton(
                    onPressed: () => _confirmDeleteRole(roleKey, roleName),
                    icon: Icon(Icons.delete_outline,
                        size: 20, color: Colors.red.shade300),
                    tooltip: 'Sil',
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasTemplate
                        ? Colors.green.shade50
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    hasTemplate ? 'ÖZELLEŞTİRİLMİŞ' : 'VARSAYILAN',
                    style: TextStyle(
                      color: hasTemplate
                          ? Colors.green.shade700
                          : Colors.grey.shade500,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              roleName,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.indigo.shade900,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (hasTemplate) ...[
                  Icon(Icons.check_circle,
                      size: 14, color: Colors.green.shade400),
                  const SizedBox(width: 4),
                  Text(
                    '$activeCount yetki aktif',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 12),
                  ),
                ] else
                  Text(
                    'Düzenlemek için tıklayın',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 12),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  //  Add Custom Role Dialog
  // ──────────────────────────────────────────────────────────
  void _showAddRoleDialog() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.person_add, color: Colors.indigo),
            ),
            const SizedBox(width: 12),
            const Text('Yeni Kullanıcı Türü'),
          ],
        ),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Tür Adı',
            hintText: 'Örn: Stajyer, Kantinci, Güvenlik...',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);

              // key: türkçe karakterleri kaldır, lowercase, boşlukları _ yap
              final key = name
                  .toLowerCase()
                  .replaceAll('ç', 'c')
                  .replaceAll('ğ', 'g')
                  .replaceAll('ı', 'i')
                  .replaceAll('ö', 'o')
                  .replaceAll('ş', 's')
                  .replaceAll('ü', 'u')
                  .replaceAll(RegExp(r'[^a-z0-9]'), '_')
                  .replaceAll(RegExp(r'_+'), '_');

              if (_institutionId == null) return;

              // Default permissions (all disabled)
              Map<String, dynamic> appPerms = {};
              for (var mk in AppModules.allModuleKeys) {
                appPerms[mk] = {'enabled': false, 'level': 'viewer'};
              }
              Map<String, dynamic> stPerms = {};
              for (var mk in SchoolTypeModules.allModuleKeys) {
                stPerms[mk] = {'enabled': false, 'level': 'viewer'};
              }

              await _roleService.saveRoleTemplate(
                  _institutionId!, key, {
                'roleName': name,
                'appPermissions': appPerms,
                'schoolTypePermissions': stPerms,
                'isCustom': true,
              });
              await _loadAll();

              // Immediately open editor
              _openEditor(key, name);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Oluştur ve Düzenle'),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  //  Delete Confirm
  // ──────────────────────────────────────────────────────────
  void _confirmDeleteRole(String roleKey, String roleName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            const SizedBox(width: 12),
            const Text('Kullanıcı Türünü Sil'),
          ],
        ),
        content: Text('"$roleName" kullanıcı türünü silmek istediğinize emin misiniz?\n\nBu türe atanmış kullanıcılar etkilenmez.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (_institutionId != null) {
                await _roleService.deleteRoleTemplate(
                    _institutionId!, roleKey);
                await _loadAll();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  //  Editor Bottom Sheet
  // ──────────────────────────────────────────────────────────
  void _openEditor(String roleKey, String roleName) {
    final template = _templates[roleKey] ?? {};

    // Deep copy so we don't mutate originals
    Map<String, dynamic> appPerms = {};
    final srcApp = template['appPermissions'] as Map<String, dynamic>? ??
        RolePermissionService.getDefaultPermissions(roleKey);
    srcApp.forEach((k, v) {
      appPerms[k] = v is Map ? Map<String, dynamic>.from(v) : v;
    });

    Map<String, dynamic> stPerms = {};
    final srcSt = template['schoolTypePermissions']
            as Map<String, dynamic>? ??
        RolePermissionService.getDefaultSchoolTypePermissions(roleKey);
    srcSt.forEach((k, v) {
      stPerms[k] = v is Map ? Map<String, dynamic>.from(v) : v;
    });

    final color = RolePermissionService.getRoleColor(roleKey);
    final icon = RolePermissionService.getRoleIcon(roleKey);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          // ── helpers ──
          Widget sectionHeader(String title, IconData ic) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                children: [
                  Icon(ic, size: 18, color: Colors.indigo),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Colors.indigo,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                      child: Divider(
                          color: Colors.indigo.withOpacity(0.1))),
                ],
              ),
            );
          }

          Widget subModuleTile(String modKey, String subKey, String subName,
              Map<String, dynamic> subPerms) {
            final p = subPerms[subKey];
            final isEnabled = (p is Map && p['enabled'] == true);
            final isEditor = (p is Map && p['level'] == 'editor');

            return Container(
              padding: const EdgeInsets.only(left: 48, right: 16, top: 4, bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      subName,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: isEnabled ? Colors.indigo.shade700 : Colors.grey.shade500,
                      ),
                    ),
                  ),
                  // Görüntüle switch
                  Transform.scale(
                    scale: 0.65,
                    child: Switch(
                      value: isEnabled,
                      onChanged: (val) {
                        setModalState(() {
                          subPerms[subKey] = {
                            'enabled': val,
                            'level': val ? (p is Map ? p['level'] : 'viewer') : 'viewer',
                          };
                        });
                      },
                      activeColor: Colors.blue,
                    ),
                  ),
                  // Düzenle switch
                  Transform.scale(
                    scale: 0.65,
                    child: Switch(
                      value: isEnabled && isEditor,
                      onChanged: isEnabled
                          ? (val) {
                              setModalState(() {
                                subPerms[subKey] = {
                                  'enabled': true,
                                  'level': val ? 'editor' : 'viewer',
                                };
                              });
                            }
                          : null,
                      activeColor: Colors.orange,
                    ),
                  ),
                ],
              ),
            );
          }

          Widget moduleTile(dynamic mod, Map<String, dynamic> perms, String key) {
            final p = perms[key];
            final isEnabled = (p is Map && p['enabled'] == true);
            final isEditor = (p is Map && p['level'] == 'editor');
            final hasSubModules = mod.subModules.isNotEmpty;
            final subPerms = (p is Map ? p['subModules'] : {}) as Map<String, dynamic>;

            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: isEnabled ? Colors.white : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isEnabled ? mod.color.withOpacity(0.15) : Colors.transparent,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Icon(mod.icon, color: isEnabled ? mod.color : Colors.grey.shade400, size: 22),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                mod.name,
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: isEnabled ? Colors.indigo.shade900 : Colors.grey.shade500,
                                ),
                              ),
                              if (mod.description.isNotEmpty)
                                Text(
                                  mod.description,
                                  style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                                ),
                            ],
                          ),
                        ),
                        // Görüntüle switch
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Transform.scale(
                              scale: 0.75,
                              child: Switch(
                                value: isEnabled,
                                onChanged: (val) {
                                  setModalState(() {
                                    perms[key]['enabled'] = val;
                                    // Ana modül kapanırsa tüm alt modüller kapanır mı? 
                                    // Genelde evet ama kullanıcı bazen tek tek açmak isteyebilir.
                                    // Ama hiyerarşik olması daha iyi.
                                    if (!val && hasSubModules) {
                                      mod.subModules.forEach((sk, _) {
                                        if (subPerms[sk] != null) subPerms[sk]['enabled'] = false;
                                      });
                                    }
                                  });
                                },
                                activeColor: Colors.blue,
                              ),
                            ),
                            Text('Görüntüle', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isEnabled ? Colors.blue : Colors.grey)),
                          ],
                        ),
                        const SizedBox(width: 4),
                        // Düzenle switch
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Transform.scale(
                              scale: 0.75,
                              child: Switch(
                                value: isEnabled && isEditor,
                                onChanged: isEnabled
                                    ? (val) {
                                        setModalState(() {
                                          perms[key]['level'] = val ? 'editor' : 'viewer';
                                          if (!val && hasSubModules) {
                                            mod.subModules.forEach((sk, _) {
                                              if (subPerms[sk] != null) subPerms[sk]['level'] = 'viewer';
                                            });
                                          }
                                        });
                                      }
                                    : null,
                                activeColor: Colors.orange,
                              ),
                            ),
                            Text('Düzenle', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isEnabled && isEditor ? Colors.orange : Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (hasSubModules && isEnabled)
                  ...mod.subModules.entries.map((e) => subModuleTile(key, e.key, e.value, subPerms)).toList(),
                const SizedBox(height: 8),
              ],
            );
          }


          // ── layout ──
          return Container(
            height: MediaQuery.of(ctx).size.height * 0.92,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              children: [
                // ── Header ──
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 24, 16, 16),
                  decoration: BoxDecoration(
                    border: Border(
                        bottom:
                            BorderSide(color: Colors.grey.shade100)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: color, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$roleName Yetkileri',
                              style: GoogleFonts.inter(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo.shade900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Bu kullanıcı türü için yetkileri belirleyin',
                              style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close),
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.grey.shade100),
                      ),
                    ],
                  ),
                ),

                // ── Content ──
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                        24, 0, 24, 100),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        sectionHeader(
                            'ANA MODÜLLER', Icons.apps),
                        ...AppModules.allModuleKeys.map((k) =>
                            moduleTile(
                                AppModules.getModule(k)!,
                                appPerms,
                                k)),
                        sectionHeader('OKUL TÜRÜ MODÜLLERİ',
                            Icons.school),
                        ...SchoolTypeModules.allModuleKeys
                            .map((k) => moduleTile(
                                SchoolTypeModules.getModule(k)!,
                                stPerms,
                                k)),
                      ],
                    ),
                  ),
                ),

                // ── Footer ──
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 20,
                          offset: const Offset(0, -10)),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(16)),
                          ),
                          child: const Text('İptal'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            setState(() => _isLoading = true);
                            try {
                              await _roleService
                                  .saveRoleTemplate(
                                      _institutionId!,
                                      roleKey,
                                      {
                                    'roleName': roleName,
                                    'appPermissions': appPerms,
                                    'schoolTypePermissions':
                                        stPerms,
                                  });
                              await _loadAll();
                              if (mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                  content: Text(
                                      '"$roleName" yetkileri kaydedildi ✓'),
                                  backgroundColor: Colors.green,
                                ));
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                  content: Text('Hata: $e'),
                                  backgroundColor: Colors.red,
                                ));
                              }
                            } finally {
                              if (mounted) {
                                setState(
                                    () => _isLoading = false);
                              }
                            }
                          },
                          icon: const Icon(Icons.save_alt),
                          label: const Text('Şablonu Kaydet'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(
                                    vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(16)),
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
      ),
    );
  }
}
