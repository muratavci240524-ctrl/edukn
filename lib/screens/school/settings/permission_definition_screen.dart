import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../services/role_permission_service.dart';
import '../../../services/user_permission_service.dart';
import '../../../widgets/granular_permission_tree.dart';

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
  String _roleSearch = '';
  final TextEditingController _roleSearchCtrl = TextEditingController();

  /// roleKey → template data (from Firestore)
  Map<String, Map<String, dynamic>> _templates = {};

  /// Merged list: built‑in roles + custom roles from Firestore
  Map<String, String> _allRoles = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _roleSearchCtrl.dispose();
    super.dispose();
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
          _institutionId = await UserPermissionService.resolveInstitutionId(
            email,
            userData: userData,
          );
        }
      }

      if (_institutionId != null) {
        _templates = await _roleService.getAllTemplates(_institutionId!);
      }

      _allRoles = {...RolePermissionService.builtInRoles};
      for (final key in _templates.keys) {
        if (!_allRoles.containsKey(key)) {
          _allRoles[key] = _templates[key]?['roleName']?.toString() ?? key;
        }
      }
    } catch (e) {
      debugPrint('Error loading permissions: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, Map<String, dynamic>> _deepClonePermissionMap(
    Map<String, dynamic> source,
  ) {
    final result = <String, Map<String, dynamic>>{};
    source.forEach((k, v) {
      if (v is Map) {
        final modCopy = Map<String, dynamic>.from(v);
        if (modCopy['subModules'] is Map) {
          final subsCopy = <String, dynamic>{};
          (modCopy['subModules'] as Map).forEach((sk, sv) {
            if (sv is Map) {
              subsCopy[sk.toString()] = Map<String, dynamic>.from(sv);
            } else {
              subsCopy[sk.toString()] = sv;
            }
          });
          modCopy['subModules'] = subsCopy;
        } else {
          modCopy['subModules'] = <String, dynamic>{};
        }
        result[k] = modCopy;
      }
    });
    return result;
  }

  (int activeModules, int activeSubOps) _countRoleActiveStats(String roleKey) {
    final template = _templates[roleKey];
    final appMap = (template?['appPermissions'] as Map<String, dynamic>?) ??
        RolePermissionService.getDefaultPermissions(roleKey);
    final stMap =
        (template?['schoolTypePermissions'] as Map<String, dynamic>?) ??
            RolePermissionService.getDefaultSchoolTypePermissions(roleKey);
    final tpMap = (template?['teacherPermissions'] as Map<String, dynamic>?) ??
        RolePermissionService.getDefaultTeacherPermissions(roleKey);

    int activeMods = 0;
    int activeOps = 0;

    void scan(Map<String, dynamic> m) {
      m.forEach((_, v) {
        if (v is Map) {
          final modEnabled =
              v['enabled'] == true ||
              (!v.containsKey('enabled') && v['level'] != null);
          if (modEnabled) {
            activeMods++;
            if (v['subModules'] is Map) {
              (v['subModules'] as Map).forEach((_, sv) {
                if (sv is Map) {
                  final subEnabled =
                      sv['enabled'] == true ||
                      (!sv.containsKey('enabled') && sv['level'] != null);
                  if (subEnabled) activeOps++;
                }
              });
            }
          }
        }
      });
    }

    scan(appMap);
    scan(stMap);
    scan(tpMap);
    return (activeMods, activeOps);
  }

  // ──────────────────────────────────────────────────────────
  //  UI
  // ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: const EduknAppBar(
        title: 'Yetki Tanımlama',
        actions: [],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddRoleDialog,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(
          'Yeni Görev / Tür Ekle',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: const Color(0xFF4F46E5),
      ),
    );
  }

  Widget _buildBody() {
    if (_allRoles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.security_rounded, size: 76, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('Henüz kullanıcı türü tanımlanmamış'),
          ],
        ),
      );
    }

    final q = _roleSearch.trim().toLowerCase();
    final entries = _allRoles.entries.where((e) {
      if (q.isEmpty) return true;
      return e.value.toLowerCase().contains(q) ||
          e.key.toLowerCase().contains(q);
    }).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF312E81), Color(0xFF4F46E5)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.admin_panel_settings_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rol & Görev Bazlı Parça Parça Yetki Şablonları',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Her görev türü için Genel Kurum, Okul Türü ve Öğretmen Arayüzü modüllerini, alt başlıklarını ve en alt işlem yetkilerini tek tek açıp kapatabilir, Görüntüleyen / Düzenleyen olarak tanımlayabilirsiniz.',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.88),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _roleSearchCtrl,
                  onChanged: (v) => setState(() => _roleSearch = v),
                  style: GoogleFonts.inter(fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText:
                        'Görev / rol ara (Öğretmen, Müdür Yardımcısı, Depo Sorumlusu, Satın Alma...)',
                    hintStyle: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF94A3B8),
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF64748B),
                    ),
                    suffixIcon: _roleSearch.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _roleSearchCtrl.clear();
                              setState(() => _roleSearch = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFF4F46E5),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 380,
              mainAxisExtent: 196,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final entry = entries[index];
                final roleKey = entry.key;
                final roleName = entry.value;
                final hasTemplate = _templates.containsKey(roleKey);
                final isBuiltIn = RolePermissionService.isBuiltIn(roleKey);
                return _buildRoleCard(
                  roleKey,
                  roleName,
                  hasTemplate,
                  isBuiltIn,
                );
              },
              childCount: entries.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleCard(
    String roleKey,
    String roleName,
    bool hasTemplate,
    bool isBuiltIn,
  ) {
    final color = RolePermissionService.getRoleColor(roleKey);
    final icon = RolePermissionService.getRoleIcon(roleKey);
    final stats = _countRoleActiveStats(roleKey);

    return InkWell(
      onTap: () => _openEditor(roleKey, roleName),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(
            color: hasTemplate
                ? color.withValues(alpha: 0.35)
                : const Color(0xFFE2E8F0),
            width: 1.4,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const Spacer(),
                if (isBuiltIn && hasTemplate)
                  IconButton(
                    onPressed: () => _confirmResetBuiltInRole(roleKey, roleName),
                    icon: Icon(
                      Icons.restart_alt_rounded,
                      size: 19,
                      color: Colors.orange.shade600,
                    ),
                    tooltip: 'Varsayılan Şablona Sıfırla',
                    visualDensity: VisualDensity.compact,
                  ),
                if (!isBuiltIn)
                  IconButton(
                    onPressed: () => _confirmDeleteRole(roleKey, roleName),
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 19,
                      color: Colors.red.shade400,
                    ),
                    tooltip: 'Sil',
                    visualDensity: VisualDensity.compact,
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: hasTemplate
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    hasTemplate ? 'ÖZELLEŞTİRİLMİŞ' : 'VARSAYILAN',
                    style: GoogleFonts.inter(
                      color: hasTemplate
                          ? const Color(0xFF047857)
                          : const Color(0xFF64748B),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              roleName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 14,
                  color: color,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '${stats.$1} ana modül • ${stats.$2} alt yetki açık',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: const Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  Icons.tune_rounded,
                  size: 16,
                  color: color,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  //  Add / Reset / Delete Dialogs
  // ──────────────────────────────────────────────────────────

  void _showAddRoleDialog() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.indigo),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Yeni Kullanıcı Türü / Görevi')),
          ],
        ),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Tür / Görev Adı',
            hintText: 'Örn: Anaokulu Koordinatörü, Kantin Sorumlusu...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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

              final appPerms = RolePermissionService.getDefaultPermissions(key);
              final stPerms =
                  RolePermissionService.getDefaultSchoolTypePermissions(key);
              final tpPerms =
                  RolePermissionService.getDefaultTeacherPermissions(key);

              await _roleService.saveRoleTemplate(_institutionId!, key, {
                'roleName': name,
                'appPermissions': appPerms,
                'schoolTypePermissions': stPerms,
                'teacherPermissions': tpPerms,
                'isCustom': true,
              });
              await _loadAll();

              if (mounted) {
                _openEditor(key, name);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Oluştur ve Yetkileri Düzenle'),
          ),
        ],
      ),
    );
  }

  void _confirmResetBuiltInRole(String roleKey, String roleName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.restart_alt_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Expanded(child: Text('Varsayılan Şablona Sıfırla')),
          ],
        ),
        content: Text(
          '"$roleName" görevi için yaptığınız özelleştirmeler kaldırılıp sistem varsayılan yetkilerine dönülecek. Onaylıyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (_institutionId != null) {
                await _roleService.deleteRoleTemplate(_institutionId!, roleKey);
                await _loadAll();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Sıfırla'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteRole(String roleKey, String roleName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 12),
            Expanded(child: Text('Kullanıcı Türünü Sil')),
          ],
        ),
        content: Text(
          '"$roleName" kullanıcı türünü silmek istediğinize emin misiniz?\n\nBu türe atanmış mevcut kullanıcılar etkilenmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (_institutionId != null) {
                await _roleService.deleteRoleTemplate(_institutionId!, roleKey);
                await _loadAll();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  //  Bottom-Docked Granular Role Permission Editor Sheet
  // ──────────────────────────────────────────────────────────

  void _openEditor(String roleKey, String roleName) {
    final template = _templates[roleKey] ?? {};

    final appPerms = _deepClonePermissionMap(
      (template['appPermissions'] as Map<String, dynamic>?) ??
          RolePermissionService.getDefaultPermissions(roleKey),
    );
    final stPerms = _deepClonePermissionMap(
      (template['schoolTypePermissions'] as Map<String, dynamic>?) ??
          RolePermissionService.getDefaultSchoolTypePermissions(roleKey),
    );
    final tpPerms = _deepClonePermissionMap(
      (template['teacherPermissions'] as Map<String, dynamic>?) ??
          RolePermissionService.getDefaultTeacherPermissions(roleKey),
    );

    final roleColor = RolePermissionService.getRoleColor(roleKey);
    final roleIcon = RolePermissionService.getRoleIcon(roleKey);
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 1020),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final media = MediaQuery.of(ctx);
            final maxHeight = media.size.height * 0.92;

            return Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: maxHeight,
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    // Üst Tutamaç ve Başlık
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 10, 14, 14),
                      child: Column(
                        children: [
                          Container(
                            width: 42,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFCBD5E1),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: roleColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  roleIcon,
                                  color: roleColor,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$roleName Yetki Tanımlamaları',
                                      style: GoogleFonts.inter(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Tüm modülleri, alt başlıkları ve alt işlemleri parça parça açıp kapatabilir, Görüntüleyen / Düzenleyen yetkisi verebilirsiniz.',
                                      style: GoogleFonts.inter(
                                        fontSize: 11.5,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(sheetCtx),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Gövde: 3 Seviyeli Yetki Ağacı
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        child: GranularPermissionEditor(
                          appPermissions: appPerms,
                          schoolTypeModulePermissions: stPerms,
                          teacherPermissions: tpPerms,
                        ),
                      ),
                    ),

                    // Alt Sabit Kaydet Barı
                    Container(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        14,
                        20,
                        14 + media.padding.bottom,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: const Border(
                          top: BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 12,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          OutlinedButton(
                            onPressed: isSaving
                                ? null
                                : () => Navigator.pop(sheetCtx),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Vazgeç'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      if (_institutionId == null) return;
                                      setSheetState(() => isSaving = true);
                                      try {
                                        await _roleService.saveRoleTemplate(
                                          _institutionId!,
                                          roleKey,
                                          {
                                            'roleName': roleName,
                                            'appPermissions': appPerms,
                                            'schoolTypePermissions': stPerms,
                                            'teacherPermissions': tpPerms,
                                            'isCustom':
                                                !RolePermissionService.isBuiltIn(
                                                  roleKey,
                                                ),
                                          },
                                        );

                                        // Aktif kullanıcının rolüyse önbelleği yenile
                                        final cachedUser =
                                            UserPermissionService.getCachedUserData();
                                        final currentRole =
                                            (cachedUser?['role'] ?? '')
                                                .toString()
                                                .toLowerCase();
                                        if (currentRole == roleKey) {
                                          await UserPermissionService.loadAndCacheRoleTemplate(
                                            _institutionId!,
                                            roleKey,
                                          );
                                        }

                                        if (sheetCtx.mounted) {
                                          Navigator.pop(sheetCtx);
                                        }
                                        await _loadAll();
                                        if (mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                '✅ "$roleName" görev yetkileri kaydedildi.',
                                              ),
                                              backgroundColor:
                                                  const Color(0xFF059669),
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        setSheetState(() => isSaving = false);
                                        if (mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text('Hata: $e'),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                      }
                                    },
                              icon: isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save_rounded, size: 19),
                              label: Text(
                                isSaving
                                    ? 'Kaydediliyor...'
                                    : 'Yetki Şablonunu Kaydet',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4F46E5),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
