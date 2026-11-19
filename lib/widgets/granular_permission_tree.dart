import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_modules.dart';
import '../constants/school_type_modules.dart';
import '../constants/teacher_modules.dart';

/// 3 Seviyeli (Modül -> Alt Başlık -> Alt Başlığın Altı) Parça Parça Yetki Tanımlama Ağacı.
/// Hem "Yetki Tanımlama" (Rol Şablonları) ekranında hem de "Kullanıcı Yönetimi" (Kişiye Özel Yetki) formunda kullanılır.
class GranularPermissionEditor extends StatefulWidget {
  final Map<String, Map<String, dynamic>> appPermissions;
  final Map<String, Map<String, dynamic>> schoolTypeModulePermissions;
  final Map<String, Map<String, dynamic>> teacherPermissions;
  final VoidCallback? onChanged;

  /// Kullanıcı Yönetimi ekranında okul türü bazlı Görüntüle/Düzenle seçimi için opsiyonel parametreler
  final List<Map<String, dynamic>>? schoolTypes;
  final Set<String>? selectedSchoolTypes;
  final Map<String, String>? schoolTypeAccessLevels;
  final bool isLoadingSchoolTypes;

  const GranularPermissionEditor({
    super.key,
    required this.appPermissions,
    required this.schoolTypeModulePermissions,
    required this.teacherPermissions,
    this.onChanged,
    this.schoolTypes,
    this.selectedSchoolTypes,
    this.schoolTypeAccessLevels,
    this.isLoadingSchoolTypes = false,
  });

  @override
  State<GranularPermissionEditor> createState() =>
      _GranularPermissionEditorState();
}

class _PermissionNodeDescriptor {
  final String key;
  final String name;
  final String description;
  final String? category;
  final IconData icon;
  final Color color;
  final Map<String, String> subModules;
  final Map<String, Map<String, String>> nestedSubModules;

  const _PermissionNodeDescriptor({
    required this.key,
    required this.name,
    required this.description,
    this.category,
    required this.icon,
    required this.color,
    required this.subModules,
    required this.nestedSubModules,
  });

  Map<String, String> childrenOf(String subKey) =>
      nestedSubModules[subKey] ?? const {};
}

class _GranularPermissionEditorState extends State<GranularPermissionEditor> {
  /// 0: Genel Kurum Modülleri, 1: Okul Türü İçi Modüller, 2: Öğretmen Arayüzü Modülleri
  int _activeScope = 0;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  /// Açık/kapalı ağaç durumları (State içinde tutulduğu için tıklamalarda sıfırlanmaz)
  final Set<String> _expandedModules = {};
  final Set<String> _expandedSubModules = {};

  @override
  void initState() {
    super.initState();
    _normalizeAllMaps();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _notifyChanged() {
    setState(() {});
    widget.onChanged?.call();
  }

  List<_PermissionNodeDescriptor> _nodesForScope(int scope) {
    if (scope == 0) {
      return AppModules.modules.values
          .map(
            (m) => _PermissionNodeDescriptor(
              key: m.key,
              name: m.name,
              description: m.description,
              category: m.category,
              icon: m.icon,
              color: m.color,
              subModules: m.subModules,
              nestedSubModules: m.nestedSubModules,
            ),
          )
          .toList();
    } else if (scope == 1) {
      return SchoolTypeModules.modules.values
          .map(
            (m) => _PermissionNodeDescriptor(
              key: m.key,
              name: m.name,
              description: m.description,
              icon: m.icon,
              color: m.color,
              subModules: m.subModules,
              nestedSubModules: m.nestedSubModules,
            ),
          )
          .toList();
    } else {
      return TeacherModules.modules.values
          .map(
            (m) => _PermissionNodeDescriptor(
              key: m.key,
              name: m.name,
              description: m.description,
              icon: m.icon,
              color: m.color,
              subModules: m.subModules,
              nestedSubModules: m.nestedSubModules,
            ),
          )
          .toList();
    }
  }

  Map<String, Map<String, dynamic>> _mapForScope(int scope) {
    if (scope == 0) return widget.appPermissions;
    if (scope == 1) return widget.schoolTypeModulePermissions;
    return widget.teacherPermissions;
  }

  void _normalizeAllMaps() {
    for (int s = 0; s < 3; s++) {
      final nodes = _nodesForScope(s);
      final target = _mapForScope(s);
      for (final node in nodes) {
        _ensureNodeInitialized(target, node);
      }
    }
  }

  Map<String, dynamic> _ensureNodeInitialized(
    Map<String, Map<String, dynamic>> targetMap,
    _PermissionNodeDescriptor node,
  ) {
    var modEntry = targetMap[node.key];
    if (modEntry == null) {
      modEntry = {
        'enabled': false,
        'level': 'viewer',
        'subModules': <String, dynamic>{},
      };
      targetMap[node.key] = modEntry;
    } else {
      if (!modEntry.containsKey('enabled')) {
        modEntry['enabled'] = modEntry['level'] != null;
      }
      modEntry['level'] ??= 'viewer';
      if (modEntry['subModules'] is Map) {
        modEntry['subModules'] = Map<String, dynamic>.from(
          modEntry['subModules'] as Map,
        );
      } else {
        modEntry['subModules'] = <String, dynamic>{};
      }
    }

    final modEnabled = modEntry['enabled'] == true;
    final modLevel = (modEntry['level'] ?? 'viewer').toString();
    final subMap = modEntry['subModules'] as Map<String, dynamic>;

    for (final subKey in node.subModules.keys) {
      if (subMap[subKey] is Map) {
        final copy = Map<String, dynamic>.from(subMap[subKey] as Map);
        if (!copy.containsKey('enabled')) {
          copy['enabled'] = copy['level'] != null ? true : modEnabled;
        }
        copy['level'] ??= modLevel;
        subMap[subKey] = copy;
      } else {
        subMap[subKey] = {
          'enabled': modEnabled,
          'level': modLevel,
        };
      }

      final parentSub = subMap[subKey] as Map<String, dynamic>;
      final parentSubEnabled = parentSub['enabled'] == true;
      final parentSubLevel = (parentSub['level'] ?? modLevel).toString();

      for (final childKey in node.childrenOf(subKey).keys) {
        if (subMap[childKey] is Map) {
          final cCopy = Map<String, dynamic>.from(subMap[childKey] as Map);
          if (!cCopy.containsKey('enabled')) {
            cCopy['enabled'] =
                cCopy['level'] != null ? true : (modEnabled && parentSubEnabled);
          }
          cCopy['level'] ??= parentSubLevel;
          subMap[childKey] = cCopy;
        } else {
          subMap[childKey] = {
            'enabled': modEnabled && parentSubEnabled,
            'level': parentSubLevel,
          };
        }
      }
    }

    return modEntry;
  }

  // ──────────────────────────────────────────────────────────
  //  Cascading Toggle & Level Helpers
  // ──────────────────────────────────────────────────────────

  void _toggleModule(
    Map<String, Map<String, dynamic>> targetMap,
    _PermissionNodeDescriptor node,
    bool enabled,
  ) {
    final modEntry = _ensureNodeInitialized(targetMap, node);
    modEntry['enabled'] = enabled;
    final modLevel = (modEntry['level'] ?? 'viewer').toString();
    final subMap = modEntry['subModules'] as Map<String, dynamic>;

    for (final subKey in node.subModules.keys) {
      subMap[subKey] = {
        'enabled': enabled,
        'level': (subMap[subKey] is Map
                ? (subMap[subKey]['level'] ?? modLevel)
                : modLevel)
            .toString(),
      };
      for (final childKey in node.childrenOf(subKey).keys) {
        subMap[childKey] = {
          'enabled': enabled,
          'level': (subMap[childKey] is Map
                  ? (subMap[childKey]['level'] ?? modLevel)
                  : modLevel)
              .toString(),
        };
      }
    }
    if (enabled && node.subModules.isNotEmpty) {
      _expandedModules.add('$_activeScope:${node.key}');
    }
    _notifyChanged();
  }

  void _setModuleLevel(
    Map<String, Map<String, dynamic>> targetMap,
    _PermissionNodeDescriptor node,
    String newLevel,
  ) {
    final modEntry = _ensureNodeInitialized(targetMap, node);
    modEntry['level'] = newLevel;
    final subMap = modEntry['subModules'] as Map<String, dynamic>;

    for (final subKey in node.subModules.keys) {
      if (subMap[subKey] is Map) {
        (subMap[subKey] as Map<String, dynamic>)['level'] = newLevel;
      }
      for (final childKey in node.childrenOf(subKey).keys) {
        if (subMap[childKey] is Map) {
          (subMap[childKey] as Map<String, dynamic>)['level'] = newLevel;
        }
      }
    }
    _notifyChanged();
  }

  void _toggleSubModule(
    Map<String, Map<String, dynamic>> targetMap,
    _PermissionNodeDescriptor node,
    String subKey,
    bool enabled,
  ) {
    final modEntry = _ensureNodeInitialized(targetMap, node);
    final subMap = modEntry['subModules'] as Map<String, dynamic>;
    final modLevel = (modEntry['level'] ?? 'viewer').toString();

    final currentSub = subMap[subKey] as Map<String, dynamic>;
    currentSub['enabled'] = enabled;
    final subLevel = (currentSub['level'] ?? modLevel).toString();

    for (final childKey in node.childrenOf(subKey).keys) {
      if (subMap[childKey] is Map) {
        (subMap[childKey] as Map<String, dynamic>)['enabled'] = enabled;
      } else {
        subMap[childKey] = {'enabled': enabled, 'level': subLevel};
      }
    }

    if (enabled) {
      modEntry['enabled'] = true;
      if (node.childrenOf(subKey).isNotEmpty) {
        _expandedSubModules.add('$_activeScope:${node.key}:$subKey');
      }
    } else {
      // Tüm alt başlıklar kapandıysa ana modülü de kapat
      final anySubActive = node.subModules.keys.any(
        (k) => subMap[k] is Map && subMap[k]['enabled'] == true,
      );
      if (!anySubActive && node.subModules.isNotEmpty) {
        modEntry['enabled'] = false;
      }
    }

    _notifyChanged();
  }

  void _setSubModuleLevel(
    Map<String, Map<String, dynamic>> targetMap,
    _PermissionNodeDescriptor node,
    String subKey,
    String newLevel,
  ) {
    final modEntry = _ensureNodeInitialized(targetMap, node);
    final subMap = modEntry['subModules'] as Map<String, dynamic>;
    (subMap[subKey] as Map<String, dynamic>)['level'] = newLevel;

    for (final childKey in node.childrenOf(subKey).keys) {
      if (subMap[childKey] is Map) {
        (subMap[childKey] as Map<String, dynamic>)['level'] = newLevel;
      }
    }
    _notifyChanged();
  }

  void _toggleNestedItem(
    Map<String, Map<String, dynamic>> targetMap,
    _PermissionNodeDescriptor node,
    String subKey,
    String childKey,
    bool enabled,
  ) {
    final modEntry = _ensureNodeInitialized(targetMap, node);
    final subMap = modEntry['subModules'] as Map<String, dynamic>;
    final childEntry = subMap[childKey] as Map<String, dynamic>;
    childEntry['enabled'] = enabled;

    if (enabled) {
      modEntry['enabled'] = true;
      (subMap[subKey] as Map<String, dynamic>)['enabled'] = true;
    } else {
      final children = node.childrenOf(subKey);
      final anyChildEnabled = children.keys.any(
        (ck) => subMap[ck] is Map && subMap[ck]['enabled'] == true,
      );
      if (!anyChildEnabled && children.isNotEmpty) {
        (subMap[subKey] as Map<String, dynamic>)['enabled'] = false;
        final anySubEnabled = node.subModules.keys.any(
          (sk) => subMap[sk] is Map && subMap[sk]['enabled'] == true,
        );
        if (!anySubEnabled) {
          modEntry['enabled'] = false;
        }
      }
    }
    _notifyChanged();
  }

  void _setNestedItemLevel(
    Map<String, Map<String, dynamic>> targetMap,
    _PermissionNodeDescriptor node,
    String childKey,
    String newLevel,
  ) {
    final modEntry = _ensureNodeInitialized(targetMap, node);
    final subMap = modEntry['subModules'] as Map<String, dynamic>;
    (subMap[childKey] as Map<String, dynamic>)['level'] = newLevel;
    _notifyChanged();
  }

  void _bulkSetScopeEnabled(bool enabled) {
    final nodes = _nodesForScope(_activeScope);
    final targetMap = _mapForScope(_activeScope);
    for (final node in nodes) {
      final modEntry = _ensureNodeInitialized(targetMap, node);
      modEntry['enabled'] = enabled;
      final subMap = modEntry['subModules'] as Map<String, dynamic>;
      for (final subKey in node.subModules.keys) {
        (subMap[subKey] as Map<String, dynamic>)['enabled'] = enabled;
        for (final childKey in node.childrenOf(subKey).keys) {
          (subMap[childKey] as Map<String, dynamic>)['enabled'] = enabled;
        }
      }
    }
    _notifyChanged();
  }

  void _bulkSetScopeLevel(String level) {
    final nodes = _nodesForScope(_activeScope);
    final targetMap = _mapForScope(_activeScope);
    for (final node in nodes) {
      final modEntry = _ensureNodeInitialized(targetMap, node);
      modEntry['level'] = level;
      final subMap = modEntry['subModules'] as Map<String, dynamic>;
      for (final subKey in node.subModules.keys) {
        (subMap[subKey] as Map<String, dynamic>)['level'] = level;
        for (final childKey in node.childrenOf(subKey).keys) {
          (subMap[childKey] as Map<String, dynamic>)['level'] = level;
        }
      }
    }
    _notifyChanged();
  }

  void _expandOrCollapseAll(bool expand) {
    final nodes = _nodesForScope(_activeScope);
    setState(() {
      for (final node in nodes) {
        final modToken = '$_activeScope:${node.key}';
        if (expand) {
          _expandedModules.add(modToken);
          for (final subKey in node.subModules.keys) {
            if (node.childrenOf(subKey).isNotEmpty) {
              _expandedSubModules.add('$_activeScope:${node.key}:$subKey');
            }
          }
        } else {
          _expandedModules.remove(modToken);
          for (final subKey in node.subModules.keys) {
            _expandedSubModules.remove('$_activeScope:${node.key}:$subKey');
          }
        }
      }
    });
  }

  (int activeMods, int totalMods, int activeOps, int totalOps) _scopeStats(
    int scope,
  ) {
    final nodes = _nodesForScope(scope);
    final target = _mapForScope(scope);
    int activeMods = 0;
    int activeOps = 0;
    int totalOps = 0;

    for (final node in nodes) {
      final modEntry = _ensureNodeInitialized(target, node);
      final modEnabled = modEntry['enabled'] == true;
      if (modEnabled) activeMods++;

      final subMap = modEntry['subModules'] as Map<String, dynamic>;
      for (final subKey in node.subModules.keys) {
        totalOps++;
        final subEnabled =
            modEnabled && (subMap[subKey] is Map && subMap[subKey]['enabled'] == true);
        if (subEnabled) activeOps++;

        for (final childKey in node.childrenOf(subKey).keys) {
          totalOps++;
          final childEnabled = subEnabled &&
              (subMap[childKey] is Map && subMap[childKey]['enabled'] == true);
          if (childEnabled) activeOps++;
        }
      }
    }
    return (activeMods, nodes.length, activeOps, totalOps);
  }

  bool _matchesQuery(_PermissionNodeDescriptor node, String q) {
    if (q.isEmpty) return true;
    final lower = q.toLowerCase();
    if (node.name.toLowerCase().contains(lower) ||
        node.description.toLowerCase().contains(lower)) {
      return true;
    }
    for (final entry in node.subModules.entries) {
      if (entry.value.toLowerCase().contains(lower)) return true;
      for (final child in node.childrenOf(entry.key).values) {
        if (child.toLowerCase().contains(lower)) return true;
      }
    }
    return false;
  }

  // ──────────────────────────────────────────────────────────
  //  UI
  // ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final nodes = _nodesForScope(_activeScope);
    final targetMap = _mapForScope(_activeScope);
    final query = _searchQuery.trim().toLowerCase();
    final filteredNodes =
        nodes.where((n) => _matchesQuery(n, query)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Kapsam Sekmeleri (Genel Kurum / Okul Türü / Öğretmen Arayüzü)
        _buildScopeTabs(),
        const SizedBox(height: 14),

        // 2. Arama + Toplu İşlem Araç Çubuğu
        _buildToolbar(),
        const SizedBox(height: 14),

        // 3. Modül -> Alt Başlık -> Alt Başlığın Altı Ağacı
        if (filteredNodes.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.search_off_rounded,
                  size: 40,
                  color: Colors.blueGrey.shade300,
                ),
                const SizedBox(height: 8),
                Text(
                  '"$_searchQuery" aramasına uygun modül veya alt işlem bulunamadı.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.blueGrey.shade600,
                  ),
                ),
              ],
            ),
          )
        else
          ...filteredNodes.map(
            (node) => _buildModuleCard(node, targetMap, query),
          ),
      ],
    );
  }

  Widget _buildScopeTabs() {
    final scopes = [
      (
        index: 0,
        title: 'Genel Kurum Modülleri',
        icon: Icons.domain_rounded,
        accent: const Color(0xFF4F46E5),
      ),
      (
        index: 1,
        title: 'Okul Türü İçi Modüller',
        icon: Icons.account_balance_rounded,
        accent: const Color(0xFF0EA5E9),
      ),
      (
        index: 2,
        title: 'Öğretmen Arayüzü',
        icon: Icons.cast_for_education_rounded,
        accent: const Color(0xFFF59E0B),
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: scopes.map((s) {
          final isSelected = _activeScope == s.index;
          final stats = _scopeStats(s.index);
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: InkWell(
              onTap: () => setState(() => _activeScope = s.index),
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? s.accent.withValues(alpha: 0.1)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? s.accent : const Color(0xFFE2E8F0),
                    width: isSelected ? 1.6 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      s.icon,
                      size: 18,
                      color: isSelected ? s.accent : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.title,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w600,
                            color: isSelected
                                ? s.accent
                                : const Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${stats.$1}/${stats.$2} modül • ${stats.$3}/${stats.$4} alt yetki',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: isSelected
                                ? s.accent.withValues(alpha: 0.85)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _searchQuery = v),
            style: GoogleFonts.inter(fontSize: 13),
            decoration: InputDecoration(
              hintText:
                  'Modül, alt başlık veya alt işlem ara (örn: günlük karne, beslenme, depo, yoklama)...',
              hintStyle: GoogleFonts.inter(
                fontSize: 12.5,
                color: const Color(0xFF94A3B8),
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 19,
                color: Color(0xFF64748B),
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF4F46E5),
                  width: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildQuickChip(
                icon: Icons.check_circle_outline_rounded,
                label: 'Tümünü Aç',
                color: const Color(0xFF10B981),
                onTap: () => _bulkSetScopeEnabled(true),
              ),
              _buildQuickChip(
                icon: Icons.remove_circle_outline_rounded,
                label: 'Tümünü Kapat',
                color: const Color(0xFFEF4444),
                onTap: () => _bulkSetScopeEnabled(false),
              ),
              _buildQuickChip(
                icon: Icons.edit_note_rounded,
                label: 'Tümü Düzenleyen',
                color: const Color(0xFF4F46E5),
                onTap: () => _bulkSetScopeLevel('editor'),
              ),
              _buildQuickChip(
                icon: Icons.visibility_outlined,
                label: 'Tümü Görüntüleyen',
                color: const Color(0xFF0284C7),
                onTap: () => _bulkSetScopeLevel('viewer'),
              ),
              _buildQuickChip(
                icon: Icons.unfold_more_rounded,
                label: 'Tümünü Genişlet',
                color: const Color(0xFF475569),
                onTap: () => _expandOrCollapseAll(true),
              ),
              _buildQuickChip(
                icon: Icons.unfold_less_rounded,
                label: 'Tümünü Daralt',
                color: const Color(0xFF64748B),
                onTap: () => _expandOrCollapseAll(false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  //  Seviye 1: Ana Modül Kartı
  // ──────────────────────────────────────────────────────────

  Widget _buildModuleCard(
    _PermissionNodeDescriptor node,
    Map<String, Map<String, dynamic>> targetMap,
    String query,
  ) {
    final modEntry = _ensureNodeInitialized(targetMap, node);
    final isEnabled = modEntry['enabled'] == true;
    final level = (modEntry['level'] ?? 'viewer').toString();
    final subMap = modEntry['subModules'] as Map<String, dynamic>;
    final hasSubs = node.subModules.isNotEmpty;

    final modToken = '$_activeScope:${node.key}';
    final isSearching = query.isNotEmpty;
    final isExpanded = isSearching || _expandedModules.contains(modToken);

    int activeSubCount = 0;
    int totalNestedCount = 0;
    int activeNestedCount = 0;
    for (final sk in node.subModules.keys) {
      final sOn =
          isEnabled && (subMap[sk] is Map && subMap[sk]['enabled'] == true);
      if (sOn) activeSubCount++;
      final children = node.childrenOf(sk);
      totalNestedCount += children.length;
      for (final ck in children.keys) {
        if (sOn && (subMap[ck] is Map && subMap[ck]['enabled'] == true)) {
          activeNestedCount++;
        }
      }
    }

    final visibleSubEntries = node.subModules.entries.where((e) {
      if (!isSearching) return true;
      if (node.name.toLowerCase().contains(query)) return true;
      if (e.value.toLowerCase().contains(query)) return true;
      return node
          .childrenOf(e.key)
          .values
          .any((childName) => childName.toLowerCase().contains(query));
    }).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEnabled
              ? node.color.withValues(alpha: 0.35)
              : const Color(0xFFE2E8F0),
          width: isEnabled ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Modül Başlığı
          InkWell(
            onTap: hasSubs
                ? () {
                    setState(() {
                      if (_expandedModules.contains(modToken)) {
                        _expandedModules.remove(modToken);
                      } else {
                        _expandedModules.add(modToken);
                      }
                    });
                  }
                : null,
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(16),
              bottom: Radius.circular(isExpanded && hasSubs ? 0 : 16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // İkon
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: isEnabled
                          ? node.color.withValues(alpha: 0.12)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      node.icon,
                      size: 20,
                      color: isEnabled ? node.color : const Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Modül adı + açıklama + sayaç rozetleri
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Text(
                              node.name,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isEnabled
                                    ? const Color(0xFF0F172A)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                            if (node.category != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  node.category!,
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            if (hasSubs)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isEnabled
                                      ? node.color.withValues(alpha: 0.1)
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  totalNestedCount > 0
                                      ? '$activeSubCount/${node.subModules.length} başlık • $activeNestedCount/$totalNestedCount detay'
                                      : '$activeSubCount/${node.subModules.length} alt başlık',
                                  style: GoogleFonts.inter(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: isEnabled
                                        ? node.color
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          node.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Görüntüleyen / Düzenleyen Seçici (Aktifse)
                  if (isEnabled) ...[
                    _buildLevelToggle(
                      level: level,
                      accentColor: node.color,
                      compact: false,
                      onChanged: (newLvl) =>
                          _setModuleLevel(targetMap, node, newLvl),
                    ),
                    const SizedBox(width: 6),
                  ],

                  // Aç / Kapa Switch
                  Transform.scale(
                    scale: 0.85,
                    child: Switch.adaptive(
                      value: isEnabled,
                      activeColor: node.color,
                      onChanged: (val) => _toggleModule(targetMap, node, val),
                    ),
                  ),

                  if (hasSubs)
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: const Color(0xFF64748B),
                      size: 22,
                    ),
                ],
              ),
            ),
          ),

          // Seviye 2: Alt Başlıklar Listesi
          if (hasSubs && isExpanded) ...[
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                children: visibleSubEntries
                    .map(
                      (subEntry) => _buildSubModuleSection(
                        node: node,
                        targetMap: targetMap,
                        subKey: subEntry.key,
                        subName: subEntry.value,
                        modEnabled: isEnabled,
                        subMap: subMap,
                        query: query,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  //  Seviye 2: Alt Başlık Satırı + Varsa Seviye 3 ("Alt Başlığın Altı")
  // ──────────────────────────────────────────────────────────

  Widget _buildSubModuleSection({
    required _PermissionNodeDescriptor node,
    required Map<String, Map<String, dynamic>> targetMap,
    required String subKey,
    required String subName,
    required bool modEnabled,
    required Map<String, dynamic> subMap,
    required String query,
  }) {
    final subData = subMap[subKey] as Map<String, dynamic>;
    final subEnabled = modEnabled && (subData['enabled'] == true);
    final subLevel = (subData['level'] ?? 'viewer').toString();

    final children = node.childrenOf(subKey);
    final hasChildren = children.isNotEmpty;
    final subToken = '$_activeScope:${node.key}:$subKey';
    final isSearching = query.isNotEmpty;
    final isSubExpanded =
        isSearching || _expandedSubModules.contains(subToken);

    int activeChildrenCount = 0;
    for (final ck in children.keys) {
      if (subEnabled && (subMap[ck] is Map && subMap[ck]['enabled'] == true)) {
        activeChildrenCount++;
      }
    }

    final visibleChildren = children.entries.where((ce) {
      if (!isSearching) return true;
      if (node.name.toLowerCase().contains(query) ||
          subName.toLowerCase().contains(query)) {
        return true;
      }
      return ce.value.toLowerCase().contains(query);
    }).toList();

    final showSchoolTypeAccessEditor =
        _activeScope == 0 &&
        node.key == 'egitim' &&
        subKey == 'okul_turleri' &&
        subEnabled &&
        widget.schoolTypes != null &&
        widget.selectedSchoolTypes != null &&
        widget.schoolTypeAccessLevels != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: subEnabled
              ? node.color.withValues(alpha: 0.25)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: hasChildren
                ? () {
                    setState(() {
                      if (_expandedSubModules.contains(subToken)) {
                        _expandedSubModules.remove(subToken);
                      } else {
                        _expandedSubModules.add(subToken);
                      }
                    });
                  }
                : () => _toggleSubModule(
                      targetMap,
                      node,
                      subKey,
                      !subEnabled,
                    ),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  // Checkbox / Durum Kutusu
                  InkWell(
                    onTap: () => _toggleSubModule(
                      targetMap,
                      node,
                      subKey,
                      !subEnabled,
                    ),
                    borderRadius: BorderRadius.circular(6),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: subEnabled ? node.color : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: subEnabled
                              ? node.color
                              : const Color(0xFFCBD5E1),
                          width: 1.6,
                        ),
                      ),
                      child: subEnabled
                          ? const Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Alt Başlık Adı + Alt İşlem Sayısı Rozeti
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          subName,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: subEnabled
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: subEnabled
                                ? const Color(0xFF1E293B)
                                : const Color(0xFF64748B),
                          ),
                        ),
                        if (hasChildren)
                          InkWell(
                            onTap: () {
                              setState(() {
                                if (_expandedSubModules.contains(subToken)) {
                                  _expandedSubModules.remove(subToken);
                                } else {
                                  _expandedSubModules.add(subToken);
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: subEnabled
                                    ? node.color.withValues(alpha: 0.1)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.account_tree_outlined,
                                    size: 11,
                                    color: subEnabled
                                        ? node.color
                                        : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '$activeChildrenCount/${children.length} alt yetki',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: subEnabled
                                          ? node.color
                                          : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Görüntüleyen / Düzenleyen Seçici
                  if (subEnabled) ...[
                    const SizedBox(width: 6),
                    _buildLevelToggle(
                      level: subLevel,
                      accentColor: node.color,
                      compact: true,
                      onChanged: (newLvl) =>
                          _setSubModuleLevel(targetMap, node, subKey, newLvl),
                    ),
                  ],

                  if (hasChildren) ...[
                    const SizedBox(width: 4),
                    Icon(
                      isSubExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 20,
                      color: const Color(0xFF64748B),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Seviye 3: Alt Başlığın Altı (Detay İşlem Yetkileri)
          if (hasChildren && isSubExpanded)
            Container(
              margin: const EdgeInsets.fromLTRB(22, 0, 10, 8),
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border(
                  left: BorderSide(
                    color: subEnabled
                        ? node.color.withValues(alpha: 0.45)
                        : const Color(0xFFCBD5E1),
                    width: 2.5,
                  ),
                ),
              ),
              child: Column(
                children: visibleChildren.map((childEntry) {
                  final childKey = childEntry.key;
                  final childName = childEntry.value;
                  final childData = subMap[childKey] as Map<String, dynamic>;
                  final childEnabled =
                      subEnabled && (childData['enabled'] == true);
                  final childLevel =
                      (childData['level'] ?? subLevel).toString();

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        InkWell(
                          onTap: () => _toggleNestedItem(
                            targetMap,
                            node,
                            subKey,
                            childKey,
                            !childEnabled,
                          ),
                          borderRadius: BorderRadius.circular(5),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            width: 17,
                            height: 17,
                            decoration: BoxDecoration(
                              color: childEnabled
                                  ? node.color
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: childEnabled
                                    ? node.color
                                    : const Color(0xFFCBD5E1),
                                width: 1.5,
                              ),
                            ),
                            child: childEnabled
                                ? const Icon(
                                    Icons.check_rounded,
                                    size: 12,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _toggleNestedItem(
                              targetMap,
                              node,
                              subKey,
                              childKey,
                              !childEnabled,
                            ),
                            child: Text(
                              childName,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: childEnabled
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: childEnabled
                                    ? const Color(0xFF334155)
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        ),
                        if (childEnabled)
                          _buildLevelToggle(
                            level: childLevel,
                            accentColor: node.color,
                            compact: true,
                            onChanged: (newLvl) => _setNestedItemLevel(
                              targetMap,
                              node,
                              childKey,
                              newLvl,
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

          // Kullanıcı Yönetiminde "Okul Türleri" alt başlığı için Kademe Erişim Seviyesi paneli
          if (showSchoolTypeAccessEditor)
            _buildSchoolTypeAccessPanel(node.color),
        ],
      ),
    );
  }

  Widget _buildSchoolTypeAccessPanel(Color accentColor) {
    final schoolTypes = widget.schoolTypes ?? [];
    final selectedSet = widget.selectedSchoolTypes!;
    final accessMap = widget.schoolTypeAccessLevels!;

    return Container(
      margin: const EdgeInsets.fromLTRB(22, 0, 10, 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.apartment_rounded, size: 15, color: accentColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Kademe Bazlı Erişim Seviyeleri (${selectedSet.length}/${schoolTypes.length})',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1E293B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.isLoadingSchoolTypes)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (schoolTypes.isEmpty)
            Text(
              'Henüz tanımlı okul türü bulunmuyor.',
              style: GoogleFonts.inter(
                fontSize: 11.5,
                color: const Color(0xFF64748B),
              ),
            )
          else
            ...schoolTypes.map((st) {
              final stId = st['id']?.toString() ?? '';
              final stName =
                  (st['schoolTypeName'] ?? st['name'] ?? 'İsimsiz').toString();
              final isSelected = selectedSet.contains(stId);
              final stLevel = accessMap[stId] ?? 'viewer';

              return Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () {
                        if (isSelected) {
                          selectedSet.remove(stId);
                          accessMap.remove(stId);
                        } else {
                          selectedSet.add(stId);
                          accessMap[stId] = 'viewer';
                        }
                        _notifyChanged();
                      },
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        width: 17,
                        height: 17,
                        decoration: BoxDecoration(
                          color: isSelected ? accentColor : Colors.transparent,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: isSelected
                                ? accentColor
                                : const Color(0xFFCBD5E1),
                            width: 1.5,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check_rounded,
                                size: 12,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        stName,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected
                              ? const Color(0xFF1E293B)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                    if (isSelected)
                      _buildLevelToggle(
                        level: stLevel,
                        accentColor: accentColor,
                        compact: true,
                        onChanged: (newLvl) {
                          accessMap[stId] = newLvl;
                          _notifyChanged();
                        },
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  //  Görüntüleyen / Düzenleyen Çiftli Seçici
  // ──────────────────────────────────────────────────────────

  Widget _buildLevelToggle({
    required String level,
    required Color accentColor,
    required bool compact,
    required ValueChanged<String> onChanged,
  }) {
    final isEditor = level == 'editor' || level == 'admin';

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(compact ? 8 : 10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSegmentItem(
            selected: !isEditor,
            icon: Icons.visibility_outlined,
            label: compact ? 'Gör.' : 'Görüntüleyen',
            tooltip: 'Sadece Görüntüleme Yetkisi',
            activeColor: const Color(0xFF0284C7),
            compact: compact,
            onTap: () {
              if (isEditor) onChanged('viewer');
            },
          ),
          const SizedBox(width: 2),
          _buildSegmentItem(
            selected: isEditor,
            icon: Icons.edit_outlined,
            label: compact ? 'Düz.' : 'Düzenleyen',
            tooltip: 'Tam Düzenleme / İşlem Yetkisi',
            activeColor: accentColor,
            compact: compact,
            onTap: () {
              if (!isEditor) onChanged('editor');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentItem({
    required bool selected,
    required IconData icon,
    required String label,
    required String tooltip,
    required Color activeColor,
    required bool compact,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 7 : 9,
            vertical: compact ? 3.5 : 5,
          ),
          decoration: BoxDecoration(
            color: selected ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(compact ? 6 : 8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: compact ? 12 : 13,
                color: selected ? Colors.white : const Color(0xFF64748B),
              ),
              const SizedBox(width: 3),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: compact ? 10.5 : 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

