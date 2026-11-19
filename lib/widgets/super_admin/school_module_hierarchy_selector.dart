import 'package:flutter/material.dart';
import '../../constants/app_modules.dart';
import '../../constants/school_type_modules.dart';
import '../../constants/teacher_modules.dart';
import '../../services/school_module_guard.dart';

/// Süper Admin için 3 seviyeli (Ana Modül -> Alt Başlık -> Alt Özellik)
/// hiyerarşik modül yetkilendirme bileşeni.
///
/// 3 kapsam içerir:
///  0) Genel Kurum Modülleri (AppModules)            → `activeModules` + `disabledSubModules`
///  1) Kademe / İdareci İşlemleri (SchoolTypeModules) → `st.<modül>...` negatif token'lar
///  2) Öğretmen Arayüzü (TeacherModules)              → `t.<modül>...`  negatif token'lar
class SchoolModuleHierarchySelector extends StatefulWidget {
  final Set<String> activeModules;
  final Set<String> disabledSubModules;
  final void Function(Set<String> activeModules, Set<String> disabledSubModules)
  onChanged;
  final bool compact;

  const SchoolModuleHierarchySelector({
    super.key,
    required this.activeModules,
    required this.disabledSubModules,
    required this.onChanged,
    this.compact = false,
  });

  @override
  State<SchoolModuleHierarchySelector> createState() =>
      _SchoolModuleHierarchySelectorState();
}

class _SchoolModuleHierarchySelectorState
    extends State<SchoolModuleHierarchySelector> {
  static const String _stCategory = 'İdareci İşlemleri (Kademe)';
  static const String _tCategory = 'Öğretmen Arayüzü';

  /// SchoolTypeModules → ModuleInfo (anahtar `st.<modül>`)
  static final List<ModuleInfo> _stModules = SchoolTypeModules.modules.values
      .map(
        (m) => ModuleInfo(
          key: 'st.${m.key}',
          name: m.name,
          icon: m.icon,
          color: m.color,
          category: _stCategory,
          description: m.description,
          subModules: m.subModules,
          nestedSubModules: m.nestedSubModules,
        ),
      )
      .toList();

  /// TeacherModules → ModuleInfo (anahtar `t.<modül>`)
  static final List<ModuleInfo> _tModules = TeacherModules.modules.values
      .map(
        (m) => ModuleInfo(
          key: 't.${m.key}',
          name: m.name,
          icon: m.icon,
          color: m.color,
          category: _tCategory,
          description: m.description,
          subModules: m.subModules,
          nestedSubModules: m.nestedSubModules,
        ),
      )
      .toList();

  /// 0: Genel Kurum, 1: İdareci (Kademe) İşlemleri, 2: Öğretmen Arayüzü
  int _scope = 0;

  List<ModuleInfo> get _scopeModules {
    if (_scope == 1) return _stModules;
    if (_scope == 2) return _tModules;
    return AppModules.modules.values.toList();
  }

  static bool _isScopedKey(String key) =>
      key.startsWith('st.') || key.startsWith('t.');

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'Tümü';
  final Set<String> _expandedModules = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalizeTr(String input) {
    return input
        .trim()
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .replaceAll('Ğ', 'ğ')
        .replaceAll('Ü', 'ü')
        .replaceAll('Ş', 'ş')
        .replaceAll('Ö', 'ö')
        .replaceAll('Ç', 'ç')
        .toLowerCase();
  }

  /// Genel kurum modülleri `activeModules` listesinden, idareci/öğretmen modülleri
  /// ise negatif token listesinden (`disabledSubModules`) okunur.
  bool _mainOnIn(Set<String> active, Set<String> disabled, String key) {
    if (_isScopedKey(key)) return !disabled.contains(key);
    return active.contains(key);
  }

  void _setMain(
    Set<String> active,
    Set<String> disabled,
    String key,
    bool enable,
  ) {
    if (_isScopedKey(key)) {
      if (enable) {
        disabled.remove(key);
      } else {
        disabled.add(key);
      }
    } else {
      if (enable) {
        active.add(key);
      } else {
        active.remove(key);
      }
    }
  }

  bool _isMainEnabled(String moduleKey) {
    return _mainOnIn(
      widget.activeModules,
      widget.disabledSubModules,
      moduleKey,
    );
  }

  bool _isSubEnabled(String moduleKey, String subKey) {
    if (!_isMainEnabled(moduleKey)) return false;
    final token = SchoolModuleGuard.subModuleToken(moduleKey, subKey);
    return !widget.disabledSubModules.contains(token) &&
        !widget.disabledSubModules.contains(subKey);
  }

  bool _isNestedEnabled(String moduleKey, String subKey, String nestedKey) {
    if (!_isSubEnabled(moduleKey, subKey)) return false;
    final token = SchoolModuleGuard.nestedItemToken(
      moduleKey,
      subKey,
      nestedKey,
    );
    return !widget.disabledSubModules.contains(token) &&
        !widget.disabledSubModules.contains('$subKey.$nestedKey') &&
        !widget.disabledSubModules.contains(nestedKey);
  }

  void _removeModulePrefixes(Set<String> disabledSet, ModuleInfo info) {
    final prefix = '${info.key}.';
    disabledSet.removeWhere(
      (item) => item.startsWith(prefix) || info.subModules.containsKey(item),
    );
  }

  void _toggleMainModule(ModuleInfo info, bool enable) {
    final nextActive = Set<String>.from(widget.activeModules);
    final nextDisabled = Set<String>.from(widget.disabledSubModules);

    _setMain(nextActive, nextDisabled, info.key, enable);
    _removeModulePrefixes(nextDisabled, info);

    widget.onChanged(nextActive, nextDisabled);
  }

  void _toggleSubModule(ModuleInfo info, String subKey, bool enable) {
    final nextActive = Set<String>.from(widget.activeModules);
    final nextDisabled = Set<String>.from(widget.disabledSubModules);
    final moduleKey = info.key;
    final subToken = SchoolModuleGuard.subModuleToken(moduleKey, subKey);
    final nestedPrefix = '$moduleKey.$subKey.';

    if (enable) {
      final wasMainOff = !_mainOnIn(nextActive, nextDisabled, moduleKey);
      if (wasMainOff) {
        // Ana modül kapalıyken bir alt başlık açılırsa:
        // Ana modülü aç ve SADECE bu alt başlığı aktif et.
        _setMain(nextActive, nextDisabled, moduleKey, true);
        _removeModulePrefixes(nextDisabled, info);
        for (final siblingKey in info.subModules.keys) {
          if (siblingKey != subKey) {
            nextDisabled.add(
              SchoolModuleGuard.subModuleToken(moduleKey, siblingKey),
            );
          }
        }
      } else {
        nextDisabled.remove(subToken);
        nextDisabled.remove(subKey);
        nextDisabled.removeWhere((item) => item.startsWith(nestedPrefix));
      }
    } else {
      nextDisabled.add(subToken);
      nextDisabled.removeWhere((item) => item.startsWith(nestedPrefix));

      // Tüm alt başlıklar kapatıldıysa ana modülü de otomatik kapat
      if (info.subModules.isNotEmpty) {
        final allSubsDisabled = info.subModules.keys.every((sKey) {
          final t = SchoolModuleGuard.subModuleToken(moduleKey, sKey);
          return nextDisabled.contains(t) || nextDisabled.contains(sKey);
        });
        if (allSubsDisabled) {
          _setMain(nextActive, nextDisabled, moduleKey, false);
          _removeModulePrefixes(nextDisabled, info);
        }
      }
    }

    widget.onChanged(nextActive, nextDisabled);
  }

  void _toggleNestedItem(
    ModuleInfo info,
    String subKey,
    String nestedKey,
    bool enable,
  ) {
    final nextActive = Set<String>.from(widget.activeModules);
    final nextDisabled = Set<String>.from(widget.disabledSubModules);
    final moduleKey = info.key;
    final subToken = SchoolModuleGuard.subModuleToken(moduleKey, subKey);
    final nestedToken = SchoolModuleGuard.nestedItemToken(
      moduleKey,
      subKey,
      nestedKey,
    );
    final children = info.childrenOf(subKey);

    if (enable) {
      final wasMainOff = !_mainOnIn(nextActive, nextDisabled, moduleKey);
      final wasSubOff =
          wasMainOff ||
          nextDisabled.contains(subToken) ||
          nextDisabled.contains(subKey);

      if (wasMainOff) {
        _setMain(nextActive, nextDisabled, moduleKey, true);
        _removeModulePrefixes(nextDisabled, info);
        for (final siblingSub in info.subModules.keys) {
          if (siblingSub != subKey) {
            nextDisabled.add(
              SchoolModuleGuard.subModuleToken(moduleKey, siblingSub),
            );
          }
        }
      } else if (wasSubOff) {
        nextDisabled.remove(subToken);
        nextDisabled.remove(subKey);
      }

      if (wasSubOff) {
        // Alt başlık kapalıyken tek bir 3. seviye öğe açılırsa sadece onu aç
        for (final siblingNested in children.keys) {
          final siblingToken = SchoolModuleGuard.nestedItemToken(
            moduleKey,
            subKey,
            siblingNested,
          );
          if (siblingNested == nestedKey) {
            nextDisabled.remove(siblingToken);
          } else {
            nextDisabled.add(siblingToken);
          }
        }
      } else {
        nextDisabled.remove(nestedToken);
        nextDisabled.remove('$subKey.$nestedKey');
        nextDisabled.remove(nestedKey);
      }
    } else {
      nextDisabled.add(nestedToken);
    }

    widget.onChanged(nextActive, nextDisabled);
  }

  /// Seçili kapsamdaki TÜM modülleri açar (diğer kapsamların ayarlarına dokunmaz).
  void _enableAll() {
    final nextActive = Set<String>.from(widget.activeModules);
    final nextDisabled = Set<String>.from(widget.disabledSubModules);
    if (_scope == 0) {
      nextActive.addAll(AppModules.allModuleKeys);
      nextDisabled.removeWhere((t) => !_isScopedKey(t));
    } else {
      final prefix = _scope == 1 ? 'st.' : 't.';
      nextDisabled.removeWhere((t) => t.startsWith(prefix));
    }
    widget.onChanged(nextActive, nextDisabled);
  }

  /// Seçili kapsamdaki TÜM modülleri kapatır (diğer kapsamların ayarlarına dokunmaz).
  void _disableAll() {
    final nextActive = Set<String>.from(widget.activeModules);
    final nextDisabled = Set<String>.from(widget.disabledSubModules);
    if (_scope == 0) {
      nextActive.clear();
      nextDisabled.removeWhere((t) => !_isScopedKey(t));
    } else {
      final prefix = _scope == 1 ? 'st.' : 't.';
      nextDisabled.removeWhere((t) => t.startsWith(prefix));
      for (final m in _scopeModules) {
        nextDisabled.add(m.key);
      }
    }
    widget.onChanged(nextActive, nextDisabled);
  }

  void _toggleExpandAll(List<ModuleInfo> visibleModules) {
    setState(() {
      final allVisibleExpanded =
          visibleModules.isNotEmpty &&
          visibleModules.every((m) => _expandedModules.contains(m.key));
      if (allVisibleExpanded) {
        for (final m in visibleModules) {
          _expandedModules.remove(m.key);
        }
      } else {
        for (final m in visibleModules) {
          _expandedModules.add(m.key);
        }
      }
    });
  }

  bool _moduleMatchesQuery(ModuleInfo info, String normQuery) {
    if (normQuery.isEmpty) return true;
    if (_normalizeTr(info.name).contains(normQuery) ||
        _normalizeTr(info.description).contains(normQuery) ||
        _normalizeTr(info.category).contains(normQuery)) {
      return true;
    }
    for (final subEntry in info.subModules.entries) {
      if (_normalizeTr(subEntry.value).contains(normQuery)) {
        return true;
      }
      final children = info.childrenOf(subEntry.key);
      for (final nestedLabel in children.values) {
        if (_normalizeTr(nestedLabel).contains(normQuery)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _subModuleMatchesQuery(
    ModuleInfo info,
    String subKey,
    String subLabel,
    String normQuery,
  ) {
    if (normQuery.isEmpty) return true;
    // Ana başlık eşleşiyorsa tüm alt başlıklarını göster
    if (_normalizeTr(info.name).contains(normQuery) ||
        _normalizeTr(info.category).contains(normQuery)) {
      return true;
    }
    if (_normalizeTr(subLabel).contains(normQuery)) return true;
    final children = info.childrenOf(subKey);
    return children.values.any(
      (label) => _normalizeTr(label).contains(normQuery),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allModules = _scopeModules;
    final totalMainCount = allModules.length;
    final activeMainCount = allModules
        .where((m) => _isMainEnabled(m.key))
        .length;

    int totalSubCount = 0;
    int activeSubCount = 0;
    int totalNestedCount = 0;
    int activeNestedCount = 0;
    for (final m in allModules) {
      totalSubCount += m.subModules.length;
      for (final subKey in m.subModules.keys) {
        if (_isSubEnabled(m.key, subKey)) {
          activeSubCount++;
        }
        for (final nKey in m.childrenOf(subKey).keys) {
          totalNestedCount++;
          if (_isNestedEnabled(m.key, subKey, nKey)) activeNestedCount++;
        }
      }
    }

    final normQuery = _normalizeTr(_searchQuery);
    final filteredModules = allModules.where((m) {
      if (_scope == 0 &&
          _selectedCategory != 'Tümü' &&
          m.category != _selectedCategory) {
        return false;
      }
      return _moduleMatchesQuery(m, normQuery);
    }).toList();

    final categories = <String>['Tümü', ...AppModules.allCategories];
    final allVisibleExpanded =
        filteredModules.isNotEmpty &&
        filteredModules.every((m) => _expandedModules.contains(m.key));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildScopeSwitcher(),
        const SizedBox(height: 12),
        _buildSummaryHeader(
          activeMainCount: activeMainCount,
          totalMainCount: totalMainCount,
          activeSubCount: activeSubCount,
          totalSubCount: totalSubCount,
          activeNestedCount: activeNestedCount,
          totalNestedCount: totalNestedCount,
          allVisibleExpanded: allVisibleExpanded,
          visibleModules: filteredModules,
        ),
        const SizedBox(height: 12),
        _buildSearchAndCategoryBar(categories),
        const SizedBox(height: 12),
        if (filteredModules.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.search_off_rounded,
                  size: 40,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 8),
                Text(
                  'Arama kriterlerine uygun modül veya alt başlık bulunamadı.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
            ),
          )
        else
          ...filteredModules.map(
            (info) => RepaintBoundary(
              key: ValueKey('mod_card_${info.key}'),
              child: _buildModuleCard(info, normQuery),
            ),
          ),
      ],
    );
  }

  Widget _buildScopeSwitcher() {
    Widget chip(int idx, IconData icon, String label, String sub) {
      final sel = _scope == idx;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() {
            _scope = idx;
            _selectedCategory = 'Tümü';
            _searchController.clear();
            _searchQuery = '';
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: sel ? Colors.indigo : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: sel ? Colors.indigo : Colors.grey.shade300,
                width: sel ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: sel ? Colors.white : Colors.indigo.shade700,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: sel ? Colors.white : Colors.grey.shade900,
                        ),
                      ),
                      Text(
                        sub,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: sel
                              ? Colors.white.withValues(alpha: 0.85)
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final disabledScoped = widget.disabledSubModules
        .where((t) => _isScopedKey(t))
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            chip(
              0,
              Icons.business_rounded,
              'Genel Kurum Modülleri',
              'Yönetim paneli ana modülleri (Eğitim, Mali, İK, Haberleşme...)',
            ),
            const SizedBox(width: 8),
            chip(
              1,
              Icons.admin_panel_settings_rounded,
              'İdareci İşlemleri (Kademe)',
              'Kademe içi İşlemler: Eğitim, Ders Programı, Haberleşme, Ölçme...',
            ),
            const SizedBox(width: 8),
            chip(
              2,
              Icons.school_rounded,
              'Öğretmen Arayüzü',
              'Öğretmen ekranındaki modüller ve alt özellikler',
            ),
          ],
        ),
        if (disabledScoped > 0 && _scope == 0)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'Not: İdareci / Öğretmen kapsamında $disabledScoped kısıtlama tanımlı.',
              style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
            ),
          ),
      ],
    );
  }

  Widget _buildSummaryHeader({
    required int activeMainCount,
    required int totalMainCount,
    required int activeSubCount,
    required int totalSubCount,
    required int activeNestedCount,
    required int totalNestedCount,
    required bool allVisibleExpanded,
    required List<ModuleInfo> visibleModules,
  }) {
    return Container(
      padding: EdgeInsets.all(widget.compact ? 12 : 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.indigo.shade50,
            Colors.blue.shade50.withValues(alpha: 0.5),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildStatBadge(
                icon: Icons.widgets_rounded,
                label: '$activeMainCount / $totalMainCount Ana Modül Aktif',
                color: Colors.indigo.shade700,
                bgColor: Colors.white,
              ),
              _buildStatBadge(
                icon: Icons.account_tree_rounded,
                label: '$activeSubCount / $totalSubCount Alt Başlık Aktif',
                color: Colors.teal.shade700,
                bgColor: Colors.white,
              ),
              _buildStatBadge(
                icon: Icons.tune_rounded,
                label: '$activeNestedCount / $totalNestedCount Detay Yetkisi Aktif',
                color: Colors.deepPurple.shade700,
                bgColor: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _enableAll,
                icon: const Icon(Icons.done_all_rounded, size: 17),
                label: const Text('Tümünü Aç'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade50,
                  foregroundColor: Colors.green.shade800,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _disableAll,
                icon: const Icon(Icons.remove_done_rounded, size: 17),
                label: const Text('Tümünü Kapat'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade50,
                  foregroundColor: Colors.red.shade800,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: visibleModules.isEmpty
                    ? null
                    : () => _toggleExpandAll(visibleModules),
                icon: Icon(
                  allVisibleExpanded
                      ? Icons.unfold_less_rounded
                      : Icons.unfold_more_rounded,
                  size: 17,
                ),
                label: Text(
                  allVisibleExpanded ? 'Tümünü Daralt' : 'Tümünü Genişlet',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.indigo.shade700,
                  side: BorderSide(color: Colors.indigo.shade200),
                  backgroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatBadge({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndCategoryBar(List<String> categories) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          onChanged: (val) => setState(() => _searchQuery = val),
          decoration: InputDecoration(
            hintText: 'Modül veya alt başlık ara...',
            hintStyle: TextStyle(fontSize: 13.5, color: Colors.grey.shade500),
            prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.shade600),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    tooltip: 'Temizle',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            isDense: true,
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (_scope == 0)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: categories.map((category) {
              final isSelected = _selectedCategory == category;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(category),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() => _selectedCategory = category);
                  },
                  selectedColor: Colors.indigo.shade100,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? Colors.indigo.shade900
                        : Colors.grey.shade700,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildModuleCard(ModuleInfo info, String normQuery) {
    final isMainOn = _isMainEnabled(info.key);
    final totalSubs = info.subModules.length;
    final activeSubs = info.subModules.keys
        .where((subKey) => _isSubEnabled(info.key, subKey))
        .length;

    // Kısmi açık durum kontrolü (ana modül açık ama bazı alt başlık veya 3. seviye öğeler kapalı)
    bool hasPartialRestriction = false;
    if (isMainOn) {
      if (activeSubs < totalSubs) {
        hasPartialRestriction = true;
      } else {
        for (final subKey in info.subModules.keys) {
          final children = info.childrenOf(subKey);
          for (final nestedKey in children.keys) {
            if (!_isNestedEnabled(info.key, subKey, nestedKey)) {
              hasPartialRestriction = true;
              break;
            }
          }
          if (hasPartialRestriction) break;
        }
      }
    }

    final isExpanded =
        _expandedModules.contains(info.key) || normQuery.isNotEmpty;

    final borderColor = !isMainOn
        ? Colors.grey.shade200
        : hasPartialRestriction
        ? Colors.amber.shade400
        : info.color.withValues(alpha: 0.35);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isMainOn ? Colors.white : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: isMainOn ? 1.3 : 1.0),
        boxShadow: isMainOn
            ? [
                BoxShadow(
                  color: info.color.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(12),
              bottom: Radius.circular(isExpanded ? 0 : 12),
            ),
            onTap: () {
              setState(() {
                if (_expandedModules.contains(info.key)) {
                  _expandedModules.remove(info.key);
                } else {
                  _expandedModules.add(info.key);
                }
              });
            },
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 10 : 14,
                vertical: widget.compact ? 10 : 12,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: widget.compact ? 38 : 44,
                    height: widget.compact ? 38 : 44,
                    decoration: BoxDecoration(
                      color: isMainOn
                          ? info.color.withValues(alpha: 0.12)
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      info.icon,
                      color: isMainOn ? info.color : Colors.grey.shade500,
                      size: widget.compact ? 20 : 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              info.name,
                              style: TextStyle(
                                fontSize: widget.compact ? 14 : 15,
                                fontWeight: FontWeight.w700,
                                color: isMainOn
                                    ? Colors.grey.shade900
                                    : Colors.grey.shade600,
                              ),
                            ),
                            _buildSmallPill(
                              label: info.category,
                              textColor: isMainOn
                                  ? info.color
                                  : Colors.grey.shade600,
                              bgColor: isMainOn
                                  ? info.color.withValues(alpha: 0.1)
                                  : Colors.grey.shade200,
                            ),
                            if (info.key == 'sistem_ayarlari')
                              _buildSmallPill(
                                label: 'Temel',
                                textColor: Colors.blueGrey.shade700,
                                bgColor: Colors.blueGrey.shade50,
                              ),
                            if (totalSubs > 0)
                              _buildSmallPill(
                                label: '$activeSubs/$totalSubs Alt Başlık Açık',
                                textColor: !isMainOn
                                    ? Colors.grey.shade600
                                    : hasPartialRestriction
                                    ? Colors.amber.shade900
                                    : Colors.green.shade800,
                                bgColor: !isMainOn
                                    ? Colors.grey.shade200
                                    : hasPartialRestriction
                                    ? Colors.amber.shade50
                                    : Colors.green.shade50,
                              ),
                          ],
                        ),
                        if (!widget.compact && info.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            info.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Switch(
                    value: isMainOn,
                    activeTrackColor: hasPartialRestriction
                        ? Colors.amber.shade600
                        : info.color,
                    onChanged: (val) => _toggleMainModule(info, val),
                  ),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded && info.subModules.isNotEmpty) ...[
            Divider(height: 1, color: Colors.grey.shade200),
            _buildSubModulesSection(info, isMainOn, normQuery),
          ],
        ],
      ),
    );
  }

  Widget _buildSmallPill({
    required String label,
    required Color textColor,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildSubModulesSection(
    ModuleInfo info,
    bool isMainOn,
    String normQuery,
  ) {
    final visibleSubs = info.subModules.entries
        .where(
          (entry) =>
              _subModuleMatchesQuery(info, entry.key, entry.value, normQuery),
        )
        .toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: isMainOn
            ? info.color.withValues(alpha: 0.025)
            : Colors.grey.shade100.withValues(alpha: 0.6),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6, top: 2),
            child: Row(
              children: [
                Icon(
                  Icons.subdirectory_arrow_right_rounded,
                  size: 15,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    isMainOn
                        ? 'Alt Başlıklar ve Alt Özellikler (İstediğiniz alt başlığı kapatabilirsiniz)'
                        : 'Ana modül kapalı — Bir alt başlığı açarsanız ana modül yalnızca o başlıkla aktifleşir',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...visibleSubs.map((subEntry) {
            final subKey = subEntry.key;
            final subLabel = subEntry.value;
            final isSubOn = _isSubEnabled(info.key, subKey);
            final children = info.childrenOf(subKey);
            final activeChildrenCount = children.keys
                .where((nKey) => _isNestedEnabled(info.key, subKey, nKey))
                .length;

            return Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isSubOn
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: isSubOn
                      ? info.color.withValues(alpha: 0.25)
                      : Colors.grey.shade200,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _toggleSubModule(info, subKey, !isSubOn),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: isSubOn,
                            activeColor: info.color,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onChanged: (val) =>
                                _toggleSubModule(info, subKey, val ?? false),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            subLabel,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: isSubOn
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: isSubOn
                                  ? Colors.grey.shade900
                                  : Colors.grey.shade500,
                            ),
                          ),
                        ),
                        if (children.isNotEmpty)
                          _buildSmallPill(
                            label: '$activeChildrenCount/${children.length}',
                            textColor: isSubOn
                                ? info.color
                                : Colors.grey.shade500,
                            bgColor: isSubOn
                                ? info.color.withValues(alpha: 0.08)
                                : Colors.grey.shade200,
                          ),
                      ],
                    ),
                  ),
                  if (children.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 28),
                      child: _buildNestedGroups(info, subKey, children),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 3. seviye öğeleri etiketteki `Grup › Detay` yapısına göre gruplayarak gösterir
  /// (örn. "Otomatik Dağıtım › Ayar: ..." ayrı bir başlık altında toplanır).
  Widget _buildNestedGroups(
    ModuleInfo info,
    String subKey,
    Map<String, String> children,
  ) {
    final Map<String, List<MapEntry<String, String>>> groups = {};
    for (final e in children.entries) {
      final idx = e.value.indexOf(' › ');
      final group = idx > 0 ? e.value.substring(0, idx) : '';
      final label = idx > 0 ? e.value.substring(idx + 3) : e.value;
      groups.putIfAbsent(group, () => []).add(MapEntry(e.key, label));
    }

    Widget chipFor(String nestedKey, String nestedLabel) {
      final isNestedOn = _isNestedEnabled(info.key, subKey, nestedKey);
      return FilterChip(
        label: Text(
          nestedLabel,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isNestedOn ? FontWeight.w600 : FontWeight.w400,
            color: isNestedOn ? info.color : Colors.grey.shade600,
          ),
        ),
        selected: isNestedOn,
        onSelected: (selected) =>
            _toggleNestedItem(info, subKey, nestedKey, selected),
        selectedColor: info.color.withValues(alpha: 0.12),
        checkmarkColor: info.color,
        backgroundColor: Colors.grey.shade100,
        side: BorderSide(
          color: isNestedOn
              ? info.color.withValues(alpha: 0.35)
              : Colors.grey.shade300,
        ),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final g in groups.entries) ...[
          if (g.key.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 13,
                    decoration: BoxDecoration(
                      color: info.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    g.key,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: info.color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${g.value.where((e) => _isNestedEnabled(info.key, subKey, e.key)).length}/${g.value.length}',
                    style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final e in g.value) chipFor(e.key, e.value)],
          ),
        ],
      ],
    );
  }
}
