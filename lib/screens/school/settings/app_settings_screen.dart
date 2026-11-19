import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../constants/app_modules.dart';
import '../../../constants/school_type_modules.dart';
import '../../../constants/teacher_modules.dart';
import '../../../models/school/daily_report_models.dart';
import '../../../models/school/student_movement_model.dart';
import '../../../services/daily_report_service.dart';
import '../../../services/user_permission_service.dart';

class _SettingsTreeNode {
  final String scopeGroup; // 'app' | 'school_type' | 'teacher'
  final String keyPrefix; // '' | 'st.' | 't.'
  final String modKey;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final Map<String, String> subModules;
  final Map<String, Map<String, String>> nestedSubModules;
  final bool lockRootSwitch;

  const _SettingsTreeNode({
    required this.scopeGroup,
    required this.keyPrefix,
    required this.modKey,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.subModules,
    required this.nestedSubModules,
    this.lockRootSwitch = false,
  });

  String get fullModKey => '$keyPrefix$modKey';
  String fullSubKey(String subKey) => '$keyPrefix$modKey.$subKey';
  String fullChildKey(String subKey, String childKey) =>
      '$keyPrefix$modKey.$subKey.$childKey';

  Map<String, String> childrenOf(String subKey) =>
      nestedSubModules[subKey] ?? const {};
}

class AppSettingsScreen extends StatefulWidget {
  final String? initialSchoolTypeId;
  final String? initialSchoolTypeName;

  const AppSettingsScreen({
    Key? key,
    this.initialSchoolTypeId,
    this.initialSchoolTypeName,
  }) : super(key: key);

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _schoolId;
  String? _institutionId;

  /// Kurum geneli kapalı anahtarlar (`appSettings.disabledModules`)
  final Set<String> _globalDisabled = {};

  /// Okul türü bazlı kapalı anahtarlar (`appSettings.schoolTypeDisabledModules[schoolTypeId]`)
  final Map<String, Set<String>> _schoolTypeDisabled = {};

  /// Kurumdaki okul türleri listesi
  List<({String id, String name})> _schoolTypes = [];

  /// Seçili kapsam: `''` = Kurum Geneli (Tüm Okul), dolu = Belirli Okul Türü ID
  String _selectedScopeSchoolTypeId = '';

  /// Grup filtresi: `'all'` | `'app'` | `'school_type'` | `'teacher'` | `'general'`
  String _selectedGroupTab = 'all';
  String _searchQuery = '';

  /// Açık/kapalı ağaç durumları (state koruma)
  final Set<String> _expandedModules = {};
  final Set<String> _expandedSubModules = {};

  String _teacherAnnouncementMode = 'approval_required';
  bool _notifyTeacherMissingAttendance = true;
  DailyReportConfigModel _dailyReportConfig = const DailyReportConfigModel();
  GateNotificationSettings _globalGateNotifSettings =
      const GateNotificationSettings();
  final Map<String, GateNotificationSettings> _schoolTypeGateNotifSettings = {};

  static const List<String> _dailyReportChildKeys = [
    'gunluk_rapor_beslenme',
    'gunluk_rapor_su',
    'gunluk_rapor_uyku',
    'gunluk_rapor_duygu',
    'gunluk_rapor_etkinlik',
    'gunluk_rapor_ozbakim',
    'gunluk_rapor_saglik',
    'gunluk_rapor_veli_geri_bildirim',
  ];

  @override
  void initState() {
    super.initState();
    final initSt = (widget.initialSchoolTypeId ?? '').trim();
    if (initSt.isNotEmpty) {
      _selectedScopeSchoolTypeId = initSt;
      _selectedGroupTab = 'school_type';
    }
    _loadSettings();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_SettingsTreeNode> _buildAllNodes() {
    final nodes = <_SettingsTreeNode>[];

    // 1. Kurum Ana Modülleri (Genel Kısım)
    for (final m in AppModules.modules.values) {
      nodes.add(
        _SettingsTreeNode(
          scopeGroup: 'app',
          keyPrefix: '',
          modKey: m.key,
          name: m.name,
          description: m.description,
          icon: m.icon,
          color: m.color,
          subModules: m.subModules,
          nestedSubModules: m.nestedSubModules,
          lockRootSwitch: m.key == 'sistem_ayarlari',
        ),
      );
    }

    // 2. Okul Türü İçi Modüller
    for (final key in SchoolTypeModules.allModuleKeys) {
      final m = SchoolTypeModules.getModule(key);
      if (m == null) continue;
      nodes.add(
        _SettingsTreeNode(
          scopeGroup: 'school_type',
          keyPrefix: 'st.',
          modKey: m.key,
          name: m.name,
          description: m.description,
          icon: m.icon,
          color: m.color,
          subModules: m.subModules,
          nestedSubModules: m.nestedSubModules,
          lockRootSwitch: m.key == 'ayarlar',
        ),
      );
    }

    // 3. Öğretmen Arayüzü Modülleri
    for (final key in TeacherModules.allModuleKeys) {
      final m = TeacherModules.getModule(key);
      if (m == null) continue;
      nodes.add(
        _SettingsTreeNode(
          scopeGroup: 'teacher',
          keyPrefix: 't.',
          modKey: m.key,
          name: m.name,
          description: m.description,
          icon: m.icon,
          color: m.color,
          subModules: m.subModules,
          nestedSubModules: m.nestedSubModules,
        ),
      );
    }

    return nodes;
  }

  Future<void> _loadSettings() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userData = await UserPermissionService.loadUserData();
      String instId = (userData?['institutionId'] ?? '').toString().trim();
      if (instId.isEmpty && user.email != null) {
        instId = await UserPermissionService.resolveInstitutionId(
          user.email!,
          userData: userData,
        );
      }

      if (instId.isNotEmpty) {
        final variants = {
          instId,
          instId.toUpperCase(),
          instId.toLowerCase(),
        }.where((e) => e.isNotEmpty).toList();

        final schoolQuery = await FirebaseFirestore.instance
            .collection('schools')
            .where('institutionId', whereIn: variants)
            .limit(1)
            .get();

        if (schoolQuery.docs.isNotEmpty) {
          final doc = schoolQuery.docs.first;
          final data = doc.data();
          _schoolId = doc.id;
          _institutionId = instId;

          final appSettings = data['appSettings'] as Map<String, dynamic>?;
          if (appSettings != null) {
            final rawGlobal = appSettings['disabledModules'];
            if (rawGlobal is Iterable) {
              _globalDisabled
                ..clear()
                ..addAll(
                  rawGlobal
                      .map((e) => e.toString().trim())
                      .where((e) => e.isNotEmpty),
                );
            }

            final rawStMap = appSettings['schoolTypeDisabledModules'];
            if (rawStMap is Map) {
              _schoolTypeDisabled.clear();
              rawStMap.forEach((stId, list) {
                if (list is Iterable) {
                  _schoolTypeDisabled[stId.toString()] = list
                      .map((e) => e.toString().trim())
                      .where((e) => e.isNotEmpty)
                      .toSet();
                }
              });
            }

            if (appSettings['notifyTeacherMissingAttendance'] != null) {
              _notifyTeacherMissingAttendance =
                  appSettings['notifyTeacherMissingAttendance'] == true;
            }
            if (appSettings['teacherAnnouncementMode'] != null) {
              _teacherAnnouncementMode = appSettings['teacherAnnouncementMode']
                  .toString();
            }
            _globalGateNotifSettings = GateNotificationSettings.fromMap(
              appSettings['gateNotificationSettings'],
            );
            _schoolTypeGateNotifSettings.clear();
            final rawStGate = appSettings['schoolTypeGateNotificationSettings'];
            if (rawStGate is Map) {
              rawStGate.forEach((stId, cfgMap) {
                if (cfgMap is Map) {
                  _schoolTypeGateNotifSettings[stId.toString()] =
                      GateNotificationSettings.fromMap(cfgMap);
                }
              });
            }
          }

          final drService = DailyReportService();
          final loadedTypes = await drService.loadSchoolTypes(instId);
          _schoolTypes = loadedTypes;

          final initSt = (widget.initialSchoolTypeId ?? '').trim();
          if (initSt.isNotEmpty && !_schoolTypes.any((t) => t.id == initSt)) {
            _schoolTypes = [
              (
                id: initSt,
                name: (widget.initialSchoolTypeName ?? 'Okul Türü').trim(),
              ),
              ..._schoolTypes,
            ];
          }

          try {
            _dailyReportConfig = await drService.loadConfig(_schoolId!);
            _hydrateDailyReportIntoDisabledSets(_dailyReportConfig);
          } catch (_) {}

          try {
            final annSettingsDoc = await FirebaseFirestore.instance
                .collection('schools')
                .doc(_schoolId)
                .collection('settings')
                .doc('announcements')
                .get();
            if (annSettingsDoc.exists) {
              _teacherAnnouncementMode =
                  annSettingsDoc.data()?['teacherAnnouncementMode'] ??
                  _teacherAnnouncementMode;
            }
          } catch (_) {}

          // İlk açılışta ilk birkaç modülü açık getir
          _expandedModules.addAll(const [
            'egitim',
            'st.egitim',
            't.egitim_islemleri',
          ]);
          _expandedSubModules.addAll(const [
            'egitim.gunluk_rapor',
            'st.egitim.gunluk_rapor',
            't.egitim_islemleri.gunluk_rapor',
          ]);
        }
      }
    } catch (e) {
      debugPrint('Error loading app settings: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Mevcut `DailyReportConfigModel` değerlerini ağaçtaki 2. ve 3. seviye anahtarlara yansıtır
  void _hydrateDailyReportIntoDisabledSets(DailyReportConfigModel cfg) {
    void syncFlag(bool enabled, String childKey) {
      final keys = [
        'egitim.gunluk_rapor.$childKey',
        'st.egitim.gunluk_rapor.$childKey',
        't.egitim_islemleri.gunluk_rapor.$childKey',
      ];
      if (!enabled) {
        _globalDisabled.addAll(keys);
      }
    }

    if (!cfg.enabled) {
      _globalDisabled.addAll(const [
        'egitim.gunluk_rapor',
        'st.egitim.gunluk_rapor',
        't.egitim_islemleri.gunluk_rapor',
      ]);
    }
    syncFlag(cfg.trackMeals, 'gunluk_rapor_beslenme');
    syncFlag(cfg.trackWater, 'gunluk_rapor_su');
    syncFlag(cfg.trackSleep, 'gunluk_rapor_uyku');
    syncFlag(cfg.trackMood, 'gunluk_rapor_duygu');
    syncFlag(cfg.trackActivities, 'gunluk_rapor_etkinlik');
    syncFlag(cfg.trackSelfCare, 'gunluk_rapor_ozbakim');
    syncFlag(cfg.trackHealthNote, 'gunluk_rapor_saglik');
    syncFlag(cfg.allowParentFeedback, 'gunluk_rapor_veli_geri_bildirim');

    // Eğer eski yapıdan `enabledSchoolTypeIds` dolu geldiyse, listede OLMAYAN okul türlerine devre dışı işaretle
    if (cfg.enabledSchoolTypeIds.isNotEmpty && _schoolTypes.isNotEmpty) {
      for (final st in _schoolTypes) {
        if (!cfg.enabledSchoolTypeIds.contains(st.id)) {
          final set = _schoolTypeDisabled.putIfAbsent(st.id, () => <String>{});
          set.addAll(const [
            'egitim.gunluk_rapor',
            'st.egitim.gunluk_rapor',
            't.egitim_islemleri.gunluk_rapor',
          ]);
        }
      }
    }
  }

  bool get _isGlobalScope => _selectedScopeSchoolTypeId.isEmpty;

  Set<String> get _activeDisabledSet {
    if (_isGlobalScope) return _globalDisabled;
    return _schoolTypeDisabled.putIfAbsent(
      _selectedScopeSchoolTypeId,
      () => <String>{},
    );
  }

  bool _isKeyDisabledGlobally(String key) => _globalDisabled.contains(key);

  bool _isLockedSettingKey(String fullKey) {
    return fullKey == 'sistem_ayarlari' ||
        fullKey == 'sistem_ayarlari.uygulama_ayarlari' ||
        fullKey == 'st.ayarlar' ||
        fullKey == 'st.ayarlar.uygulama_ayarlari';
  }

  /// Günlük Rapor anahtarları 3 ağaçta da (`egitim`, `st.egitim`, `t.egitim_islemleri`) senkron çalışsın
  List<String> _mirrorDailyReportKeys(String key) {
    const prefixes = [
      'egitim.gunluk_rapor',
      'st.egitim.gunluk_rapor',
      't.egitim_islemleri.gunluk_rapor',
    ];
    for (final p in prefixes) {
      if (key == p) return prefixes;
      if (key.startsWith('$p.')) {
        final suffix = key.substring(p.length + 1);
        return prefixes.map((x) => '$x.$suffix').toList();
      }
    }
    return [key];
  }

  void _setKeyEnabledInActiveScope(String key, bool enabled) {
    if (_isLockedSettingKey(key) && !enabled) return;
    final target = _activeDisabledSet;
    for (final mirrored in _mirrorDailyReportKeys(key)) {
      if (enabled) {
        target.remove(mirrored);
      } else {
        target.add(mirrored);
      }
    }
  }

  bool _isNodeModuleEnabled(_SettingsTreeNode node) {
    final key = node.fullModKey;
    if (!_isGlobalScope && _globalDisabled.contains(key)) return false;
    return !_activeDisabledSet.contains(key);
  }

  bool _isNodeSubEnabled(_SettingsTreeNode node, String subKey) {
    if (!_isNodeModuleEnabled(node)) return false;
    final key = node.fullSubKey(subKey);
    if (!_isGlobalScope && _globalDisabled.contains(key)) return false;
    return !_activeDisabledSet.contains(key);
  }

  bool _isNodeChildEnabled(
    _SettingsTreeNode node,
    String subKey,
    String childKey,
  ) {
    if (!_isNodeSubEnabled(node, subKey)) return false;
    final key = node.fullChildKey(subKey, childKey);
    if (!_isGlobalScope && _globalDisabled.contains(key)) return false;
    return !_activeDisabledSet.contains(key);
  }

  void _toggleModule(_SettingsTreeNode node, bool enable) {
    if (node.lockRootSwitch && !enable) return;
    setState(() {
      _setKeyEnabledInActiveScope(node.fullModKey, enable);
      // Modül açıldığında veya kapatıldığında alt başlık ve 3. seviye başlıkları da senkronla
      for (final subEntry in node.subModules.entries) {
        final sKey = node.fullSubKey(subEntry.key);
        if (_isLockedSettingKey(sKey) && !enable) continue;
        _setKeyEnabledInActiveScope(sKey, enable);
        for (final childEntry in node.childrenOf(subEntry.key).entries) {
          final cKey = node.fullChildKey(subEntry.key, childEntry.key);
          _setKeyEnabledInActiveScope(cKey, enable);
        }
      }
      if (enable) {
        _expandedModules.add(node.fullModKey);
      }
    });
  }

  void _toggleSubModule(_SettingsTreeNode node, String subKey, bool enable) {
    final fullSub = node.fullSubKey(subKey);
    if (_isLockedSettingKey(fullSub) && !enable) return;

    setState(() {
      if (enable) {
        // Alt başlık açılırsa üst modülü de aktif et
        _setKeyEnabledInActiveScope(node.fullModKey, true);
      }
      _setKeyEnabledInActiveScope(fullSub, enable);

      // Alt başlığın altındaki 3. seviye işlemleri de senkronla
      for (final childEntry in node.childrenOf(subKey).entries) {
        final fullChild = node.fullChildKey(subKey, childEntry.key);
        _setKeyEnabledInActiveScope(fullChild, enable);
      }

      if (enable && node.childrenOf(subKey).isNotEmpty) {
        _expandedSubModules.add(fullSub);
      }
    });
  }

  void _toggleChildModule(
    _SettingsTreeNode node,
    String subKey,
    String childKey,
    bool enable,
  ) {
    setState(() {
      if (enable) {
        // 3. seviye açılırsa 2. seviye ve 1. seviyeyi de aktif et
        _setKeyEnabledInActiveScope(node.fullModKey, true);
        _setKeyEnabledInActiveScope(node.fullSubKey(subKey), true);
      }
      _setKeyEnabledInActiveScope(node.fullChildKey(subKey, childKey), enable);

      // Eğer bir alt başlığın TÜM 3. seviye alt işlemleri kapatıldıysa (örn. Günlük Karne'nin 8 bölümü de kapatıldıysa)
      if (!enable) {
        final children = node.childrenOf(subKey);
        if (children.isNotEmpty) {
          final anyStillEnabled = children.keys.any(
            (ck) => _isNodeChildEnabled(node, subKey, ck),
          );
          if (!anyStillEnabled &&
              !_isLockedSettingKey(node.fullSubKey(subKey))) {
            _setKeyEnabledInActiveScope(node.fullSubKey(subKey), false);
          }
        }
      }
    });
  }

  void _setAllInVisibleGroup(
    List<_SettingsTreeNode> visibleNodes,
    bool enable,
  ) {
    setState(() {
      for (final node in visibleNodes) {
        if (!node.lockRootSwitch || enable) {
          _setKeyEnabledInActiveScope(node.fullModKey, enable);
        }
        for (final subKey in node.subModules.keys) {
          final fullSub = node.fullSubKey(subKey);
          if (_isLockedSettingKey(fullSub) && !enable) continue;
          _setKeyEnabledInActiveScope(fullSub, enable);
          for (final childKey in node.childrenOf(subKey).keys) {
            _setKeyEnabledInActiveScope(
              node.fullChildKey(subKey, childKey),
              enable,
            );
          }
        }
      }
    });
  }

  DailyReportConfigModel _buildSyncedDailyReportConfig() {
    bool isGlobalChildEnabled(String childKey) {
      return !_globalDisabled.contains('egitim.gunluk_rapor.$childKey') &&
          !_globalDisabled.contains('st.egitim.gunluk_rapor.$childKey');
    }

    final globalDailyEnabled =
        !_globalDisabled.contains('egitim') &&
        !_globalDisabled.contains('egitim.gunluk_rapor') &&
        !_globalDisabled.contains('st.egitim.gunluk_rapor');

    // Hangi okul türlerinde açık?
    List<String> enabledStIds = [];
    if (_schoolTypes.isNotEmpty) {
      final disabledCount = _schoolTypes.where((st) {
        final set = _schoolTypeDisabled[st.id] ?? const <String>{};
        return set.contains('egitim') ||
            set.contains('egitim.gunluk_rapor') ||
            set.contains('st.egitim') ||
            set.contains('st.egitim.gunluk_rapor');
      }).length;

      if (disabledCount > 0 && disabledCount < _schoolTypes.length) {
        enabledStIds = _schoolTypes
            .where((st) {
              final set = _schoolTypeDisabled[st.id] ?? const <String>{};
              return !set.contains('egitim') &&
                  !set.contains('egitim.gunluk_rapor') &&
                  !set.contains('st.egitim') &&
                  !set.contains('st.egitim.gunluk_rapor');
            })
            .map((st) => st.id)
            .toList();
      } else if (disabledCount == _schoolTypes.length) {
        // Tüm okul türlerinde ayrı ayrı kapatılmışsa
        enabledStIds = const [];
      }
    }

    final cleanStMap = <String, List<String>>{};
    _schoolTypeDisabled.forEach((stId, set) {
      if (set.isNotEmpty) {
        cleanStMap[stId] = set.toList()..sort();
      }
    });

    return DailyReportConfigModel(
      enabled: globalDailyEnabled,
      enabledSchoolTypeIds: enabledStIds,
      trackMeals: isGlobalChildEnabled('gunluk_rapor_beslenme'),
      trackWater: isGlobalChildEnabled('gunluk_rapor_su'),
      trackSleep: isGlobalChildEnabled('gunluk_rapor_uyku'),
      trackMood: isGlobalChildEnabled('gunluk_rapor_duygu'),
      trackActivities: isGlobalChildEnabled('gunluk_rapor_etkinlik'),
      trackSelfCare: isGlobalChildEnabled('gunluk_rapor_ozbakim'),
      trackHealthNote: isGlobalChildEnabled('gunluk_rapor_saglik'),
      allowParentFeedback: isGlobalChildEnabled(
        'gunluk_rapor_veli_geri_bildirim',
      ),
      globalDisabledKeys: _globalDisabled.toList()..sort(),
      schoolTypeDisabledModules: cleanStMap,
    );
  }

  Future<void> _saveSettings() async {
    if (_schoolId == null || _isSaving) return;

    setState(() => _isSaving = true);
    bool mainSaved = false;
    Object? saveError;

    // Kilitli sistem ayarlarının yanlışlıkla listeye girmesini engelle
    _globalDisabled.removeWhere(_isLockedSettingKey);
    for (final s in _schoolTypeDisabled.values) {
      s.removeWhere(_isLockedSettingKey);
    }

    final sortedGlobalDisabled = _globalDisabled.toList()..sort();
    final serializedStDisabled = <String, List<String>>{};
    _schoolTypeDisabled.forEach((stId, set) {
      if (set.isNotEmpty) {
        serializedStDisabled[stId] = set.toList()..sort();
      }
    });

    final serializedStGateNotif = <String, Map<String, dynamic>>{};
    _schoolTypeGateNotifSettings.forEach((stId, cfg) {
      if (stId.trim().isNotEmpty) {
        serializedStGateNotif[stId.trim()] = cfg.toMap();
      }
    });

    final syncedDailyConfig = _buildSyncedDailyReportConfig();
    _dailyReportConfig = syncedDailyConfig;

    // 1. Ana okul belgesindeki appSettings'i kaydet
    try {
      await FirebaseFirestore.instance.collection('schools').doc(_schoolId).set(
        {
          'appSettings': {
            'disabledModules': sortedGlobalDisabled,
            'schoolTypeDisabledModules': serializedStDisabled,
            'notifyTeacherMissingAttendance': _notifyTeacherMissingAttendance,
            'teacherAnnouncementMode': _teacherAnnouncementMode,
            'dailyReport': syncedDailyConfig.toMap(),
            'gateNotificationSettings': _globalGateNotifSettings.toMap(),
            'schoolTypeGateNotificationSettings': serializedStGateNotif,
          },
        },
        SetOptions(merge: true),
      );
      mainSaved = true;
    } catch (e) {
      try {
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(_schoolId)
            .update({
              'appSettings.disabledModules': sortedGlobalDisabled,
              'appSettings.schoolTypeDisabledModules': serializedStDisabled,
              'appSettings.notifyTeacherMissingAttendance':
                  _notifyTeacherMissingAttendance,
              'appSettings.teacherAnnouncementMode': _teacherAnnouncementMode,
              'appSettings.dailyReport': syncedDailyConfig.toMap(),
              'appSettings.gateNotificationSettings': _globalGateNotifSettings
                  .toMap(),
              'appSettings.schoolTypeGateNotificationSettings':
                  serializedStGateNotif,
            });
        mainSaved = true;
      } catch (e2) {
        saveError = e2;
      }
    }

    // 2. Alt koleksiyon (settings/announcements)
    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(_schoolId)
          .collection('settings')
          .doc('announcements')
          .set({
            'teacherAnnouncementMode': _teacherAnnouncementMode,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (_) {}

    // 3. Alt koleksiyon (settings/daily_report_config)
    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(_schoolId)
          .collection('settings')
          .doc('daily_report_config')
          .set({
            ...syncedDailyConfig.toMap(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (_) {}

    if (mounted) {
      setState(() => _isSaving = false);
      if (mainSaved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Uygulama ve modül ayarları başarıyla kaydedildi.'),
            backgroundColor: Color(0xFF0D9488),
          ),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              saveError != null &&
                      saveError.toString().contains('permission-denied')
                  ? 'Yetki hatası: Bu ayarları kaydetmek için yönetici yetkisi gerekmektedir.'
                  : 'Ayarlar kaydedilirken hata oluştu.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String get _activeScopeLabel {
    if (_isGlobalScope) return 'Kurum Geneli (Tüm Okul)';
    for (final st in _schoolTypes) {
      if (st.id == _selectedScopeSchoolTypeId) return st.name;
    }
    return widget.initialSchoolTypeName ?? 'Seçili Okul Türü';
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        title: 'Uygulama Ayarları',
        institutionId: _institutionId,
        subtitle: _activeScopeLabel,
        actions: [
          if (!_isLoading && _schoolId != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _saveSettings,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded, size: 18),
                label: Text(_isSaving ? 'Kaydediliyor...' : 'Kaydet'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
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
          : _schoolId == null
          ? const Center(child: Text('Kurum bilgisi bulunamadı.'))
          : _buildContent(isMobile),
    );
  }

  Widget _buildContent(bool isMobile) {
    final allNodes = _buildAllNodes();
    final q = _searchQuery.trim().toLowerCase();

    final filteredNodes = allNodes.where((node) {
      if (_selectedGroupTab != 'all' &&
          _selectedGroupTab != 'general' &&
          node.scopeGroup != _selectedGroupTab) {
        return false;
      }
      if (q.isEmpty) return true;
      if (node.name.toLowerCase().contains(q) ||
          node.description.toLowerCase().contains(q)) {
        return true;
      }
      for (final sub in node.subModules.entries) {
        if (sub.value.toLowerCase().contains(q)) return true;
        for (final child in node.childrenOf(sub.key).entries) {
          if (child.value.toLowerCase().contains(q)) return true;
        }
      }
      return false;
    }).toList();

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            isMobile ? 14 : 28,
            18,
            isMobile ? 14 : 28,
            48,
          ),
          children: [
            _buildScopeSelectorCard(isMobile),
            const SizedBox(height: 14),
            _buildFilterAndToolbarCard(allNodes, filteredNodes, isMobile),
            const SizedBox(height: 16),
            if ((_selectedGroupTab == 'all' ||
                    _selectedGroupTab == 'general') &&
                (q.isEmpty ||
                    'ziyaretçi güvenlik kapı çıkış izni erken alma veli müdür bildirim'
                        .contains(q))) ...[
              _buildGateNotificationSettingsCard(isMobile),
              const SizedBox(height: 18),
            ],
            if (_isGlobalScope &&
                (_selectedGroupTab == 'all' ||
                    _selectedGroupTab == 'general') &&
                q.isEmpty) ...[
              _buildGeneralPreferencesCard(),
              const SizedBox(height: 18),
            ],
            if (_selectedGroupTab != 'general') ...[
              if (filteredNodes.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Center(
                    child: Text(
                      'Aramanızla eşleşen modül veya alt başlık bulunamadı.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                )
              else
                ..._buildGroupedModuleCards(filteredNodes, q),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScopeSelectorCard(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isGlobalScope
              ? const [Color(0xFF1E1B4B), Color(0xFF312E81)]
              : const [Color(0xFF0F766E), Color(0xFF115E59)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E1B4B).withValues(alpha: 0.14),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _isGlobalScope
                      ? Icons.public_rounded
                      : Icons.account_balance_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isGlobalScope
                          ? 'Kapsam: Kurum Geneli (Tüm Okul Türleri)'
                          : 'Kapsam: $_activeScopeLabel (Okul Türü Bazlı Ayarlar)',
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _isGlobalScope
                          ? 'Burada kapattığınız modül, alt başlık ve 3. seviye özellikler tüm kurum genelinde kapatılır.'
                          : 'Yalnızca "$_activeScopeLabel" kademesi için modülleri, alt başlıkları ve Günlük Karne bölümlerini açıp kapatıyorsunuz.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFE0E7FF),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_schoolTypes.isNotEmpty) ...[
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildScopeChip(
                    id: '',
                    label: '🌐 Kurum Geneli (Tümü)',
                    selected: _isGlobalScope,
                  ),
                  ..._schoolTypes.map(
                    (st) => Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _buildScopeChip(
                        id: st.id,
                        label: '🏫 ${st.name}',
                        selected: _selectedScopeSchoolTypeId == st.id,
                        badgeCount: _schoolTypeDisabled[st.id]?.length ?? 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScopeChip({
    required String id,
    required String label,
    required bool selected,
    int badgeCount = 0,
  }) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedScopeSchoolTypeId = id;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: selected ? const Color(0xFF1E1B4B) : Colors.white,
              ),
            ),
            if (badgeCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFEF4444)
                      : Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$badgeCount kapalı',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilterAndToolbarCard(
    List<_SettingsTreeNode> allNodes,
    List<_SettingsTreeNode> filteredNodes,
    bool isMobile,
  ) {
    final tabs = [
      (key: 'all', label: 'Tüm Modüller', icon: Icons.apps_rounded),
      (key: 'app', label: 'Genel Kurum Modülleri', icon: Icons.domain_rounded),
      (
        key: 'school_type',
        label: 'Okul Türü İçi Modüller',
        icon: Icons.school_rounded,
      ),
      (
        key: 'teacher',
        label: 'Öğretmen Arayüzü',
        icon: Icons.cast_for_education_rounded,
      ),
      (
        key: 'general',
        label: 'Duyuru & Bildirim',
        icon: Icons.notifications_active_rounded,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: tabs.map((t) {
                final sel = _selectedGroupTab == t.key;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: Icon(
                      t.icon,
                      size: 16,
                      color: sel ? Colors.white : const Color(0xFF475569),
                    ),
                    label: Text(t.label),
                    selected: sel,
                    onSelected: (_) =>
                        setState(() => _selectedGroupTab = t.key),
                    selectedColor: const Color(0xFF4F46E5),
                    backgroundColor: const Color(0xFFF8FAFC),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: sel ? Colors.white : const Color(0xFF334155),
                    ),
                    side: BorderSide(
                      color: sel
                          ? const Color(0xFF4F46E5)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: isMobile ? double.infinity : 420,
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        'Modül, alt başlık veya alt işlem ara (örn: Günlük Rapor, Uyku, Depo)...',
                    hintStyle: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF94A3B8),
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                            icon: const Icon(Icons.clear_rounded, size: 18),
                          ),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
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
              ),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    for (final n in filteredNodes) {
                      _expandedModules.add(n.fullModKey);
                      for (final sk in n.subModules.keys) {
                        if (n.childrenOf(sk).isNotEmpty) {
                          _expandedSubModules.add(n.fullSubKey(sk));
                        }
                      }
                    }
                  });
                },
                icon: const Icon(Icons.unfold_more_rounded, size: 17),
                label: const Text('Tümünü Genişlet'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: const Color(0xFF334155),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _expandedModules.clear();
                    _expandedSubModules.clear();
                  });
                },
                icon: const Icon(Icons.unfold_less_rounded, size: 17),
                label: const Text('Tümünü Daralt'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: const Color(0xFF334155),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _setAllInVisibleGroup(filteredNodes, true),
                icon: const Icon(
                  Icons.check_circle_outline_rounded,
                  size: 17,
                  color: Color(0xFF0D9488),
                ),
                label: const Text('Listelenenleri Aç'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: const Color(0xFF0D9488),
                  side: const BorderSide(color: Color(0xFF99F6E4)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGroupedModuleCards(
    List<_SettingsTreeNode> nodes,
    String query,
  ) {
    final groups = <({String key, String title, String subtitle, IconData icon})>[
      (
        key: 'app',
        title: 'GENEL KURUM MODÜLLERİ',
        subtitle:
            'Kurum yönetim panelindeki ana modüller, alt başlıklar ve alt işlemler',
        icon: Icons.domain_rounded,
      ),
      (
        key: 'school_type',
        title: 'OKUL TÜRÜ İÇERİSİNDEKİ MODÜLLER',
        subtitle:
            'Anaokulu, İlkokul, Ortaokul, Lise kademelerinin iç ekranlarındaki modüller ve alt başlıklar',
        icon: Icons.school_rounded,
      ),
      (
        key: 'teacher',
        title: 'ÖĞRETMEN ARAYÜZÜ MODÜLLERİ',
        subtitle:
            'Öğretmen panelinde görünen modüller, alt başlıklar ve alt işlemler',
        icon: Icons.cast_for_education_rounded,
      ),
    ];

    final widgets = <Widget>[];
    for (final g in groups) {
      final groupNodes = nodes.where((n) => n.scopeGroup == g.key).toList();
      if (groupNodes.isEmpty) continue;

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(g.icon, size: 18, color: const Color(0xFF4F46E5)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      g.subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

      for (final node in groupNodes) {
        widgets.add(_buildModuleTreeCard(node, query));
      }
      widgets.add(const SizedBox(height: 10));
    }

    return widgets;
  }

  Widget _buildModuleTreeCard(_SettingsTreeNode node, String query) {
    final isModEnabled = _isNodeModuleEnabled(node);
    final isGloballyLockedOff =
        !_isGlobalScope && _isKeyDisabledGlobally(node.fullModKey);
    final forceExpand = query.isNotEmpty;
    final isModExpanded =
        forceExpand || _expandedModules.contains(node.fullModKey);

    final totalSubs = node.subModules.length;
    final enabledSubs = node.subModules.keys
        .where((sk) => _isNodeSubEnabled(node, sk))
        .length;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isModEnabled
              ? node.color.withValues(alpha: 0.35)
              : const Color(0xFFE2E8F0),
          width: 1.3,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // LEVEL 1: ANA MODÜL BAŞLIĞI
          InkWell(
            onTap: () {
              setState(() {
                if (_expandedModules.contains(node.fullModKey)) {
                  _expandedModules.remove(node.fullModKey);
                } else {
                  _expandedModules.add(node.fullModKey);
                }
              });
            },
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(18),
              bottom: Radius.circular(isModExpanded ? 0 : 18),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isModEnabled
                    ? node.color.withValues(alpha: 0.05)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(18),
                  bottom: Radius.circular(isModExpanded ? 0 : 18),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isModEnabled
                          ? node.color.withValues(alpha: 0.16)
                          : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      node.icon,
                      color: isModEnabled
                          ? node.color
                          : const Color(0xFF64748B),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              node.name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: isModEnabled
                                    ? const Color(0xFF0F172A)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isModEnabled
                                    ? node.color.withValues(alpha: 0.12)
                                    : const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                '$enabledSubs/$totalSubs Alt Başlık',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: isModEnabled
                                      ? node.color
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                            if (isGloballyLockedOff)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: const Text(
                                  'Kurum Genelinde Kapalı',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          node.description,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (node.lockRootSwitch)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 13,
                            color: Color(0xFF475569),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Zorunlu',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Switch(
                      value: isModEnabled,
                      activeThumbColor: node.color,
                      onChanged: isGloballyLockedOff
                          ? null
                          : (val) => _toggleModule(node, val),
                    ),
                  Icon(
                    isModExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF64748B),
                  ),
                ],
              ),
            ),
          ),

          // LEVEL 2 & LEVEL 3: ALT BAŞLIKLAR VE ALT BAŞLIĞIN ALTI
          if (isModExpanded && node.subModules.isNotEmpty) ...[
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                children: node.subModules.entries
                    .where((subEntry) {
                      if (query.isEmpty) return true;
                      if (node.name.toLowerCase().contains(query)) return true;
                      if (subEntry.value.toLowerCase().contains(query))
                        return true;
                      return node
                          .childrenOf(subEntry.key)
                          .values
                          .any((cv) => cv.toLowerCase().contains(query));
                    })
                    .map((subEntry) {
                      final subKey = subEntry.key;
                      final subName = subEntry.value;
                      final fullSubKey = node.fullSubKey(subKey);
                      final children = node.childrenOf(subKey);
                      final hasChildren = children.isNotEmpty;
                      final isSubEnabled = _isNodeSubEnabled(node, subKey);
                      final isSubLocked = _isLockedSettingKey(fullSubKey);
                      final isSubGloballyOff =
                          !_isGlobalScope &&
                          (isGloballyLockedOff ||
                              _isKeyDisabledGlobally(fullSubKey));
                      final isSubExpanded =
                          forceExpand ||
                          _expandedSubModules.contains(fullSubKey);

                      final enabledChildrenCount = children.keys
                          .where((ck) => _isNodeChildEnabled(node, subKey, ck))
                          .length;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: isSubEnabled
                              ? const Color(0xFFFDFDFE)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: hasChildren && isSubExpanded
                                ? node.color.withValues(alpha: 0.25)
                                : const Color(0xFFF1F5F9),
                          ),
                        ),
                        child: Column(
                          children: [
                            // LEVEL 2 SATIRI
                            InkWell(
                              onTap: hasChildren
                                  ? () {
                                      setState(() {
                                        if (_expandedSubModules.contains(
                                          fullSubKey,
                                        )) {
                                          _expandedSubModules.remove(
                                            fullSubKey,
                                          );
                                        } else {
                                          _expandedSubModules.add(fullSubKey);
                                        }
                                      });
                                    }
                                  : (isSubLocked || isSubGloballyOff
                                        ? null
                                        : () => _toggleSubModule(
                                            node,
                                            subKey,
                                            !isSubEnabled,
                                          )),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 14,
                                      height: 2,
                                      color: isSubEnabled
                                          ? node.color.withValues(alpha: 0.5)
                                          : const Color(0xFFCBD5E1),
                                      margin: const EdgeInsets.only(right: 10),
                                    ),
                                    Expanded(
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            subName,
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: isSubEnabled
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              color: isSubEnabled
                                                  ? const Color(0xFF1E293B)
                                                  : const Color(0xFF94A3B8),
                                            ),
                                          ),
                                          if (hasChildren)
                                            InkWell(
                                              onTap: () {
                                                setState(() {
                                                  if (_expandedSubModules
                                                      .contains(fullSubKey)) {
                                                    _expandedSubModules.remove(
                                                      fullSubKey,
                                                    );
                                                  } else {
                                                    _expandedSubModules.add(
                                                      fullSubKey,
                                                    );
                                                  }
                                                });
                                              },
                                              borderRadius:
                                                  BorderRadius.circular(99),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: node.color.withValues(
                                                    alpha: 0.10,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(99),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .account_tree_outlined,
                                                      size: 11,
                                                      color: node.color,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '$enabledChildrenCount/${children.length} alt başlık',
                                                      style: TextStyle(
                                                        fontSize: 10.5,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: node.color,
                                                      ),
                                                    ),
                                                    Icon(
                                                      isSubExpanded
                                                          ? Icons
                                                                .expand_less_rounded
                                                          : Icons
                                                                .expand_more_rounded,
                                                      size: 14,
                                                      color: node.color,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          if (isSubGloballyOff)
                                            const Text(
                                              '(Genelde Kapalı)',
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFFDC2626),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (isSubLocked)
                                      const Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        child: Icon(
                                          Icons.lock_outline_rounded,
                                          size: 16,
                                          color: Color(0xFF64748B),
                                        ),
                                      )
                                    else
                                      Transform.scale(
                                        scale: 0.85,
                                        child: Switch(
                                          value: isSubEnabled,
                                          activeThumbColor: node.color,
                                          onChanged: isSubGloballyOff
                                              ? null
                                              : (val) => _toggleSubModule(
                                                  node,
                                                  subKey,
                                                  val,
                                                ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),

                            // LEVEL 3 SATIRLARI (ALT BAŞLIĞIN ALTI)
                            if (hasChildren && isSubExpanded)
                              Container(
                                margin: const EdgeInsets.fromLTRB(24, 0, 10, 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border(
                                    left: BorderSide(
                                      color: node.color.withValues(alpha: 0.45),
                                      width: 2.5,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  children: children.entries
                                      .where((childEntry) {
                                        if (query.isEmpty) return true;
                                        if (node.name.toLowerCase().contains(
                                              query,
                                            ) ||
                                            subName.toLowerCase().contains(
                                              query,
                                            )) {
                                          return true;
                                        }
                                        return childEntry.value
                                            .toLowerCase()
                                            .contains(query);
                                      })
                                      .map((childEntry) {
                                        final childKey = childEntry.key;
                                        final childName = childEntry.value;
                                        final fullChildKey = node.fullChildKey(
                                          subKey,
                                          childKey,
                                        );
                                        final isChildEnabled =
                                            _isNodeChildEnabled(
                                              node,
                                              subKey,
                                              childKey,
                                            );
                                        final isChildGloballyOff =
                                            !_isGlobalScope &&
                                            (isSubGloballyOff ||
                                                _isKeyDisabledGlobally(
                                                  fullChildKey,
                                                ));

                                        return InkWell(
                                          onTap: isChildGloballyOff
                                              ? null
                                              : () => _toggleChildModule(
                                                  node,
                                                  subKey,
                                                  childKey,
                                                  !isChildEnabled,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 3,
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons
                                                      .subdirectory_arrow_right_rounded,
                                                  size: 15,
                                                  color: isChildEnabled
                                                      ? node.color
                                                      : const Color(0xFF94A3B8),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    childName,
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      fontWeight: isChildEnabled
                                                          ? FontWeight.w600
                                                          : FontWeight.w500,
                                                      color: isChildEnabled
                                                          ? const Color(
                                                              0xFF334155,
                                                            )
                                                          : const Color(
                                                              0xFF94A3B8,
                                                            ),
                                                    ),
                                                  ),
                                                ),
                                                if (isChildGloballyOff)
                                                  const Padding(
                                                    padding: EdgeInsets.only(
                                                      right: 6,
                                                    ),
                                                    child: Text(
                                                      'Genelde Kapalı',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: Color(
                                                          0xFFDC2626,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                Transform.scale(
                                                  scale: 0.78,
                                                  child: Switch(
                                                    value: isChildEnabled,
                                                    activeThumbColor:
                                                        node.color,
                                                    onChanged:
                                                        isChildGloballyOff
                                                        ? null
                                                        : (val) =>
                                                              _toggleChildModule(
                                                                node,
                                                                subKey,
                                                                childKey,
                                                                val,
                                                              ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      })
                                      .toList(),
                                ),
                              ),
                          ],
                        ),
                      );
                    })
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGeneralPreferencesCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC7D2FE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: Color(0xFF4F46E5),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ÖĞRETMEN DUYURU & YOKLAMA BİLDİRİM TERCİHLERİ',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Öğretmen duyuru onay akışı ve otomatik yoklama hatırlatmaları',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _teacherAnnouncementMode,
            decoration: InputDecoration(
              labelText: 'Öğretmen Duyuru Paylaşım Yetkisi',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
            items: const [
              DropdownMenuItem(
                value: 'direct',
                child: Text('Onaysız Paylaşabilir (Direkt Yayınlanır)'),
              ),
              DropdownMenuItem(
                value: 'approval_required',
                child: Text('Yönetici Onayına Düşsün (Onay ile Yayınlanır)'),
              ),
              DropdownMenuItem(
                value: 'disabled',
                child: Text('Kapalı (Duyuru Oluşturamaz)'),
              ),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() => _teacherAnnouncementMode = val);
              }
            },
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.event_busy_rounded,
                  color: Color(0xFFD97706),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Yoklama Alınmadığında Otomatik Bildirim Gönder',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Öğretmen derse girdikten 5 dakika sonra yoklama almamışsa otomatik hatırlatma bildirimi gönderilir.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _notifyTeacherMissingAttendance,
                activeThumbColor: const Color(0xFF4F46E5),
                onChanged: (val) =>
                    setState(() => _notifyTeacherMissingAttendance = val),
              ),
            ],
          ),
        ],
      ),
    );
  }

  GateNotificationSettings get _activeGateNotifSettings {
    if (_isGlobalScope) return _globalGateNotifSettings;
    return _schoolTypeGateNotifSettings[_selectedScopeSchoolTypeId] ??
        _globalGateNotifSettings;
  }

  void _updateActiveGateNotifEvent(
    String eventKey,
    GateNotificationEventConfig nextEvent,
  ) {
    setState(() {
      if (_isGlobalScope) {
        _globalGateNotifSettings = _globalGateNotifSettings.updateEvent(
          eventKey,
          nextEvent,
        );
      } else {
        final current =
            _schoolTypeGateNotifSettings[_selectedScopeSchoolTypeId] ??
            _globalGateNotifSettings;
        _schoolTypeGateNotifSettings[_selectedScopeSchoolTypeId] = current
            .updateEvent(eventKey, nextEvent);
      }
    });
  }

  Widget _buildGateNotificationSettingsCard(bool isMobile) {
    final activeSettings = _activeGateNotifSettings;
    final hasSchoolTypeCustom =
        !_isGlobalScope &&
        _schoolTypeGateNotifSettings.containsKey(_selectedScopeSchoolTypeId);

    const events =
        <
          ({
            String key,
            String title,
            String subtitle,
            IconData icon,
            Color color,
            List<({String key, String label})> recipientOptions,
          })
        >[
          (
            key: 'visitorEntry',
            title: 'Ziyaretçi Giriş Bildirimi',
            subtitle:
                'Güvenlik kapısından misafir/ziyaretçi giriş kaydı oluşturulduğunda',
            icon: Icons.how_to_reg_rounded,
            color: Color(0xFF0D9488),
            recipientOptions: [
              (key: 'mudur', label: 'Okul Müdürü'),
              (key: 'mudur_yardimcisi', label: 'Müdür Yardımcısı'),
              (key: 'host_staff', label: 'Görüşülecek Personel'),
              (key: 'guvenlik', label: 'Güvenlik Görevlisi'),
            ],
          ),
          (
            key: 'visitorExit',
            title: 'Ziyaretçi Güvenlik Çıkış Bildirimi',
            subtitle:
                'Ziyaretçi kartını teslim edip güvenlik kapısından çıkış yaptığında',
            icon: Icons.logout_rounded,
            color: Color(0xFF0284C7),
            recipientOptions: [
              (key: 'mudur', label: 'Okul Müdürü'),
              (key: 'mudur_yardimcisi', label: 'Müdür Yardımcısı'),
              (key: 'host_staff', label: 'Görüşülen Personel'),
              (key: 'guvenlik', label: 'Güvenlik Görevlisi'),
            ],
          ),
          (
            key: 'studentExitPermission',
            title: 'Öğrenci Çıkış İzni Verildiğinde',
            subtitle:
                'İdare tarafından öğrenciye okul çıkış izni kağıdı düzenlendiğinde',
            icon: Icons.assignment_ind_rounded,
            color: Color(0xFF4F46E5),
            recipientOptions: [
              (key: 'guvenlik', label: 'Güvenlik Kapısı'),
              (key: 'mudur', label: 'Okul Müdürü'),
              (key: 'mudur_yardimcisi', label: 'Müdür Yardımcısı'),
              (key: 'ogretmen', label: 'İlgili Ders Öğretmeni'),
              (key: 'veli', label: 'Öğrenci Velisi'),
            ],
          ),
          (
            key: 'studentGateExitConfirmed',
            title: 'Güvenlik Çıkış Onayı (Öğrenci Okuldan Çıktığında)',
            subtitle:
                'Öğrenci güvenlik kapısından çıkış yaptığında / velisine teslim edildiğinde',
            icon: Icons.verified_user_rounded,
            color: Color(0xFF059669),
            recipientOptions: [
              (key: 'mudur', label: 'Okul Müdürü'),
              (key: 'mudur_yardimcisi', label: 'Müdür Yardımcısı'),
              (key: 'issuer', label: 'İzni Veren Personel'),
              (key: 'ogretmen', label: 'Kalan Ders Öğretmenleri'),
              (key: 'veli', label: 'Öğrenci Velisi'),
            ],
          ),
          (
            key: 'earlyPickupNotice',
            title: 'Veli Erken Alma & Kapıda Bekliyor Bildirimi',
            subtitle:
                'Veli erken alma ön bildirimi yaptığında veya kapıya ulaştığında',
            icon: Icons.directions_car_filled_rounded,
            color: Color(0xFFD97706),
            recipientOptions: [
              (key: 'guvenlik', label: 'Güvenlik Kapısı'),
              (key: 'mudur', label: 'Okul Müdürü'),
              (key: 'mudur_yardimcisi', label: 'Müdür Yardımcısı'),
              (key: 'ogretmen', label: 'İlgili Ders Öğretmeni'),
              (key: 'veli', label: 'Öğrenci Velisi'),
            ],
          ),
        ];

    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF99F6E4), width: 1.4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDFA),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.shield_rounded,
                      color: Color(0xFF0D9488),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isGlobalScope
                              ? 'ZİYARETÇİ, GÜVENLİK ÇIKIŞ & ÖĞRENCİ ÇIKIŞ İZNİ BİLDİRİMLERİ'
                              : '$_activeScopeLabel — ZİYARETÇİ & ÇIKIŞ BİLDİRİM AYARLARI',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Hangi işlemlerde bildirim gideceğini açıp kapatın ve kime gideceğini seçin.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (hasSchoolTypeCustom)
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _schoolTypeGateNotifSettings.remove(
                        _selectedScopeSchoolTypeId,
                      );
                    });
                  },
                  icon: const Icon(Icons.restart_alt_rounded, size: 16),
                  label: const Text('Kurum Geneli Varsayılanına Dön'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: const Color(0xFF0F766E),
                    side: const BorderSide(color: Color(0xFF5EEAD4)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBAE6FD)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: Color(0xFF0284C7),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Bu bildirimler Kurum Genel Kısmında gösterilmez; yalnızca ilgili Okul Türü içerisinde seçtiğiniz yetkililere (ve seçiliyse Veli ekranına) düşer.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0C4A6E),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ...events.map((ev) {
            final cfg = activeSettings.eventByKey(ev.key);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cfg.enabled
                    ? ev.color.withValues(alpha: 0.04)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: cfg.enabled
                      ? ev.color.withValues(alpha: 0.30)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cfg.enabled
                              ? ev.color.withValues(alpha: 0.14)
                              : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          ev.icon,
                          size: 19,
                          color: cfg.enabled
                              ? ev.color
                              : const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ev.title,
                              style: TextStyle(
                                fontSize: 13.8,
                                fontWeight: FontWeight.w800,
                                color: cfg.enabled
                                    ? const Color(0xFF0F172A)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              ev.subtitle,
                              style: const TextStyle(
                                fontSize: 11.8,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: cfg.enabled,
                        activeThumbColor: ev.color,
                        onChanged: (val) {
                          _updateActiveGateNotifEvent(
                            ev.key,
                            cfg.copyWith(enabled: val),
                          );
                        },
                      ),
                    ],
                  ),
                  if (cfg.enabled) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Kime Bildirim Gitsin?',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ev.recipientOptions.map((opt) {
                        final isSelected = cfg.recipients[opt.key] == true;
                        return FilterChip(
                          selected: isSelected,
                          label: Text(opt.label),
                          checkmarkColor: Colors.white,
                          selectedColor: ev.color,
                          backgroundColor: Colors.white,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF334155),
                          ),
                          side: BorderSide(
                            color: isSelected
                                ? ev.color
                                : const Color(0xFFCBD5E1),
                          ),
                          onSelected: (sel) {
                            final nextRec = Map<String, bool>.from(
                              cfg.recipients,
                            );
                            nextRec[opt.key] = sel;
                            _updateActiveGateNotifEvent(
                              ev.key,
                              cfg.copyWith(recipients: nextRec),
                            );
                          },
                        );
                      }).toList(),
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
}
