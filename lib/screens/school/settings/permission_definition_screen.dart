import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../constants/app_modules.dart';
import '../../../constants/school_type_modules.dart';
import '../../../constants/teacher_modules.dart';
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
          final email = user.email!;
          _institutionId = await UserPermissionService.resolveInstitutionId(email, userData: userData);
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
      appBar: EduknAppBar(
        title: 'Yetki Tanımlama',
        actions: [],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddRoleDialog,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Yeni Tür Ekle', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.indigo,
      ),
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
      final tp = _templates[roleKey]?['teacherPermissions'] as Map? ?? {};
      app.forEach((_, v) {
        if (v is Map && v['enabled'] == true) activeCount++;
      });
      st.forEach((_, v) {
        if (v is Map && v['enabled'] == true) activeCount++;
      });
      tp.forEach((_, v) {
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

              // Default permissions (all disabled for custom roles)
              Map<String, dynamic> appPerms = RolePermissionService.getDefaultPermissions(key);
              Map<String, dynamic> stPerms = RolePermissionService.getDefaultSchoolTypePermissions(key);

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
      if (v is Map) {
        final modCopy = Map<String, dynamic>.from(v);
        if (modCopy['subModules'] is Map) {
          modCopy['subModules'] = Map<String, dynamic>.from(modCopy['subModules']);
        } else {
          modCopy['subModules'] = <String, dynamic>{};
        }
        appPerms[k] = modCopy;
      } else {
        appPerms[k] = v;
      }
    });

    Map<String, dynamic> stPerms = {};
    final srcSt = template['schoolTypePermissions'] as Map<String, dynamic>? ??
        RolePermissionService.getDefaultSchoolTypePermissions(roleKey);
    srcSt.forEach((k, v) {
      if (v is Map) {
        final modCopy = Map<String, dynamic>.from(v);
        if (modCopy['subModules'] is Map) {
          modCopy['subModules'] = Map<String, dynamic>.from(modCopy['subModules']);
        } else {
          modCopy['subModules'] = <String, dynamic>{};
        }
        stPerms[k] = modCopy;
      } else {
        stPerms[k] = v;
      }
    });

    final isTeacherRole = roleKey == 'ogretmen' ||
        roleKey == 'rehber_ogretmen' ||
        roleKey.contains('ogretmen') ||
        roleKey.contains('teacher') ||
        roleKey.contains('öğretmen');

    Map<String, dynamic> teacherPerms = {};
    final srcTeacher = template['teacherPermissions'] as Map<String, dynamic>? ??
        RolePermissionService.getDefaultTeacherPermissions(roleKey);
    srcTeacher.forEach((k, v) {
      if (v is Map) {
        final modCopy = Map<String, dynamic>.from(v);
        if (modCopy['subModules'] is Map) {
          modCopy['subModules'] = Map<String, dynamic>.from(modCopy['subModules']);
        } else {
          modCopy['subModules'] = <String, dynamic>{};
        }
        teacherPerms[k] = modCopy;
      } else {
        teacherPerms[k] = v;
      }
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

          final Map<String, bool> expandedModules = {};
          final Map<String, bool> collapsedSubGroups = {
            'sinav_raporlari': false,
            'ogrenci_portfolyolari': false,
            'gozlem_ve_etkinlik': false,
          };

          bool isGroupParent(String key) =>
              key == 'sinav_raporlari' ||
              key == 'ogrenci_portfolyolari' ||
              key == 'gozlem_ve_etkinlik';

          String? getParentGroupKey(String key) {
            if (key.startsWith('sinav_') && key != 'sinav_raporlari') return 'sinav_raporlari';
            if (key.startsWith('portfolyo_') && key != 'ogrenci_portfolyolari') return 'ogrenci_portfolyolari';
            if (key.startsWith('gozlem_etkinlik_') && key != 'gozlem_ve_etkinlik') return 'gozlem_ve_etkinlik';
            return null;
          }

          Widget subModuleTile(String modKey, String subKey, String subName, Map<String, dynamic> subPerms, Color modColor, Map<String, dynamic> perms) {
            final parentKey = getParentGroupKey(subKey);
            final isNestedChild = parentKey != null;
            final isParent = isGroupParent(subKey);

            // Eğer ebeveyn grup daraltılmışsa alt öğeleri gizle
            if (isNestedChild && (collapsedSubGroups[parentKey] == true)) {
              return const SizedBox.shrink();
            }

            final p = subPerms[subKey];
            final isEnabled = (p is Map && p['enabled'] == true);
            final level = (p is Map ? p['level'] : 'viewer') ?? 'viewer';
            final isMobile = MediaQuery.of(ctx).size.width < 600;

            void toggleSubModule() {
              setModalState(() {
                final newVal = !isEnabled;
                subPerms[subKey] = {
                  'enabled': newVal,
                  'level': level,
                };

                // Alt başlık açıldığında ana başlık da otomatik aktif olsun
                if (newVal == true) {
                  perms[modKey]['enabled'] = true;
                } else {
                  // Eğer bu modüldeki hiçbir alt başlık kalmadıysa ana başlığı kapat
                  final hasAnyActive = subPerms.entries.any(
                    (e) => e.key != subKey && e.value is Map && e.value['enabled'] == true,
                  );
                  if (!hasAnyActive) {
                    perms[modKey]['enabled'] = false;
                  }
                }

                if (isParent) {
                  if (newVal) collapsedSubGroups[subKey] = false;
                  final modDef = TeacherModules.modules[modKey];
                  if (modDef != null) {
                    for (final k in modDef.subModules.keys) {
                      if (getParentGroupKey(k) == subKey) {
                        final childLvl = (subPerms[k] is Map ? subPerms[k]['level'] : level) ?? level;
                        subPerms[k] = {'enabled': newVal, 'level': childLvl};
                      }
                    }
                  }
                } else if (isNestedChild && newVal == true) {
                  final parentP = subPerms[parentKey];
                  final parentLvl = (parentP is Map ? parentP['level'] : 'viewer') ?? 'viewer';
                  subPerms[parentKey] = {'enabled': true, 'level': parentLvl};
                }
              });
            }

            void toggleSubLevel() {
              setModalState(() {
                final newLevel = level == 'viewer' ? 'editor' : 'viewer';
                subPerms[subKey] = {
                  'enabled': isEnabled,
                  'level': newLevel,
                };
                if (isParent) {
                  final modDef = TeacherModules.modules[modKey];
                  if (modDef != null) {
                    for (final k in modDef.subModules.keys) {
                      if (getParentGroupKey(k) == subKey) {
                        final childEn = (subPerms[k] is Map ? subPerms[k]['enabled'] : isEnabled) ?? isEnabled;
                        subPerms[k] = {'enabled': childEn, 'level': newLevel};
                      }
                    }
                  }
                }
              });
            }

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: EdgeInsets.only(left: isNestedChild ? 56 : 40, right: 16, top: 4, bottom: 4),
              child: Row(
                children: [
                  // Checkbox
                  InkWell(
                    onTap: toggleSubModule,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: isEnabled ? modColor : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isEnabled ? modColor : Colors.grey.shade400,
                          width: 1.5,
                        ),
                      ),
                      child: isEnabled ? const Icon(Icons.check, color: Colors.white, size: 15) : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Title
                  Expanded(
                    child: InkWell(
                      onTap: toggleSubModule,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          subName,
                          style: GoogleFonts.inter(
                            fontSize: isNestedChild ? 12 : 13,
                            fontWeight: isParent ? FontWeight.w600 : FontWeight.w500,
                            color: isEnabled
                                ? (isNestedChild ? Colors.indigo.shade800 : Colors.indigo.shade900)
                                : Colors.grey.shade500,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Expand/Collapse Chevron if this item has children
                  if (isParent)
                    IconButton(
                      icon: Icon(
                        (collapsedSubGroups[subKey] == true)
                            ? Icons.expand_more_rounded
                            : Icons.expand_less_rounded,
                        color: modColor,
                        size: 22,
                      ),
                      tooltip: (collapsedSubGroups[subKey] == true) ? 'Alt Başlıkları Göster' : 'Alt Başlıkları Gizle',
                      onPressed: () {
                        setModalState(() {
                          collapsedSubGroups[subKey] = !(collapsedSubGroups[subKey] ?? false);
                        });
                      },
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      constraints: const BoxConstraints(),
                    ),
                  const SizedBox(width: 8),
                  // Level Badge Button
                  if (isEnabled)
                    InkWell(
                      onTap: toggleSubLevel,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: level == 'editor' ? modColor : modColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              level == 'editor' ? Icons.edit : Icons.visibility,
                              size: 13,
                              color: level == 'editor' ? Colors.white : modColor,
                            ),
                            if (!isMobile) ...[
                              const SizedBox(width: 4),
                              Text(
                                level == 'editor' ? 'Düzenleyen' : 'Görüntüleyen',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: level == 'editor' ? Colors.white : modColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          }

          Widget moduleTile(dynamic mod, Map<String, dynamic> perms, String key) {
            if (perms[key] == null || perms[key] is! Map) {
              perms[key] = {'enabled': false, 'level': 'viewer', 'subModules': <String, dynamic>{}};
            }
            if (perms[key]['subModules'] == null || perms[key]['subModules'] is! Map) {
              perms[key]['subModules'] = <String, dynamic>{};
            }
            final Map<String, dynamic> subPerms = perms[key]['subModules'] as Map<String, dynamic>;

            final p = perms[key];
            final isEnabled = (p is Map && p['enabled'] == true);
            final level = (p is Map ? p['level'] : 'viewer') ?? 'viewer';
            final hasSubModules = mod.subModules.isNotEmpty;
            final isExpanded = expandedModules[key] ?? isEnabled;
            final isMobile = MediaQuery.of(ctx).size.width < 600;

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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        // Checkbox
                        InkWell(
                          onTap: () {
                            setModalState(() {
                              final currentVal = isEnabled;
                              final newVal = !currentVal;
                              perms[key]['enabled'] = newVal;
                              if (newVal) {
                                expandedModules[key] = true;
                              }
                              
                              // Ana başlık değişince tüm alt başlıklara yay (Cascading)
                              if (hasSubModules) {
                                mod.subModules.forEach((sk, _) {
                                  final curLvl = (subPerms[sk] is Map ? subPerms[sk]['level'] : level) ?? level;
                                  subPerms[sk] = {'enabled': newVal, 'level': curLvl};
                                });
                              }
                            });
                          },
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: isEnabled ? mod.color : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isEnabled ? mod.color : Colors.grey.shade400,
                                width: 2,
                              ),
                            ),
                            child: isEnabled ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Icon(mod.icon, color: isEnabled ? mod.color : Colors.grey.shade400, size: 22),
                        const SizedBox(width: 14),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setModalState(() {
                                expandedModules[key] = !isExpanded;
                              });
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      mod.name,
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: isEnabled ? Colors.indigo.shade900 : Colors.grey.shade600,
                                      ),
                                    ),
                                    if (hasSubModules) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        '(${mod.subModules.length})',
                                        style: TextStyle(
                                          color: Colors.grey.shade400,
                                          fontSize: 12,
                                          fontWeight: FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (mod.description.isNotEmpty)
                                  Text(
                                    mod.description,
                                    style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (isEnabled)
                          InkWell(
                            onTap: () {
                              setModalState(() {
                                final newLevel = level == 'viewer' ? 'editor' : 'viewer';
                                perms[key]['level'] = newLevel;
                                
                                // Ana başlık seviyesi değişince tüm alt başlıklara yay (Cascading)
                                if (hasSubModules) {
                                  mod.subModules.forEach((sk, _) {
                                    final curEn = (subPerms[sk] is Map ? subPerms[sk]['enabled'] : true) ?? true;
                                    subPerms[sk] = {'enabled': curEn, 'level': newLevel};
                                  });
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: level == 'editor' ? mod.color : mod.color.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    level == 'editor' ? Icons.edit : Icons.visibility,
                                    size: 16,
                                    color: level == 'editor' ? Colors.white : mod.color,
                                  ),
                                  if (!isMobile) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      level == 'editor' ? 'Düzenleyen' : 'Görüntüleyen',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: level == 'editor' ? Colors.white : mod.color,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        if (hasSubModules)
                          IconButton(
                            icon: Icon(
                              isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                              color: isEnabled ? mod.color : Colors.grey.shade400,
                              size: 24,
                            ),
                            tooltip: isExpanded ? 'Alt Başlıkları Gizle' : 'Alt Başlıkları Göster',
                            onPressed: () {
                              setModalState(() {
                                expandedModules[key] = !isExpanded;
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                if (hasSubModules && isExpanded)
                  ...mod.subModules.entries.map((e) => subModuleTile(key, e.key, e.value, subPerms, mod.color, perms)).toList(),
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
                        if (isTeacherRole) ...[
                          sectionHeader('ÖĞRETMEN ARAYÜZÜ MODÜLLERİ', Icons.school),
                          ...TeacherModules.allModuleKeys.map((k) =>
                              moduleTile(
                                  TeacherModules.getModule(k)!,
                                  teacherPerms,
                                  k)),
                          sectionHeader('OKUL TÜRÜ YÖNETİM MODÜLLERİ', Icons.admin_panel_settings_outlined),
                          ...SchoolTypeModules.allModuleKeys.map((k) =>
                              moduleTile(
                                  SchoolTypeModules.getModule(k)!,
                                  stPerms,
                                  k)),
                        ] else ...[
                          sectionHeader('ANA MODÜLLER', Icons.apps),
                          ...AppModules.allModuleKeys.map((k) =>
                              moduleTile(
                                  AppModules.getModule(k)!,
                                  appPerms,
                                  k)),
                          sectionHeader('OKUL TÜRÜ MODÜLLERİ', Icons.school),
                          ...SchoolTypeModules.allModuleKeys.map((k) =>
                              moduleTile(
                                  SchoolTypeModules.getModule(k)!,
                                  stPerms,
                                  k)),
                        ],
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
                                    'schoolTypePermissions': stPerms,
                                    'teacherPermissions': teacherPerms,
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
