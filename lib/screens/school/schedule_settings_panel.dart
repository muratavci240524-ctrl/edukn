import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ============================================================
// Model: ScheduleSettings
// ============================================================
class ScheduleSettings {
  /// key: "lessonName_lower|weeklyHours" -> [3, 3, 2]
  final Map<String, List<int>> lessonBlockPatterns;

  /// key: "lessonName_lower|weeklyHours" -> true/false
  final Map<String, bool> lessonAllowSplit;

  /// key: "lessonName_lower|weeklyHours" -> true/false
  final Map<String, bool> lessonAvoidFirstHour;

  /// key: "lessonName_lower|weeklyHours" -> true/false
  final Map<String, bool> lessonAvoidLastHour;

  /// key: "lessonName_lower|weeklyHours" -> Map<int, int> (hourIndex -> 1: yeşil/yerleşsin, 2: kırmızı/yerleşmesin)
  final Map<String, Map<int, int>> lessonHourPreferences;

  /// List of lesson-specific merge rules:
  /// [{ 'id': '...', 'lessonName': 'Beden Eğitimi', 'weeklyHours': 2, 'classIds': ['801', '802'], 'classNames': ['801', '802'] }]
  final List<Map<String, dynamic>> lessonClassMerges;

  /// key: "teacher_<id>" veya "class_<id>" -> Set<"Pazartesi_0">
  final Map<String, Set<String>> closedSlots;

  /// key: "<teacherId>" -> int (maksimum günlük ders saati)
  final Map<String, int> teacherMaxDailyHours;

  /// Sabah yarım gün saatleri (index tabanlı, ör: [0,1,2,3,4] = 1-5. saatler)
  final List<int> halfDayMorningHours;

  /// Öğleden sonra yarım gün saatleri (ör: [5,6,7,8] = 6-9. saatler)
  final List<int> halfDayAfternoonHours;

  /// Esnek yarım gün kümesi: 'teacher_<id>_morning' veya 'teacher_<id>_afternoon'
  /// Bu kümede olanlar için günü sistem otomatik seçer
  final Set<String> halfDayFlexible;

  /// Tercih edilen gün: 'teacher_<id>_morning' -> 'Pazartesi'
  final Map<String, String> halfDayAssignedDays;

  /// key: "lessonName_lower|weeklyHours" -> Set<String> izin verilen günler (boşsa tüm günler serbest)
  final Map<String, Set<String>> lessonDayPreferences;

  ScheduleSettings({
    required this.lessonBlockPatterns,
    required this.lessonAllowSplit,
    required this.lessonAvoidFirstHour,
    required this.lessonAvoidLastHour,
    this.lessonHourPreferences = const {},
    this.lessonDayPreferences = const {},
    required this.lessonClassMerges,
    required this.closedSlots,
    required this.teacherMaxDailyHours,
    this.halfDayMorningHours = const [],
    this.halfDayAfternoonHours = const [],
    this.halfDayFlexible = const {},
    this.halfDayAssignedDays = const {},
  });
}

// ============================================================
// Widget: ScheduleSettingsPanel
// ============================================================
class ScheduleSettingsPanel extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String periodId;
  final Map<String, dynamic> periodData;
  final ScheduleSettings initialSettings;
  /// Pre-loaded data from parent screen — prevents duplicate Firestore queries
  final List<Map<String, dynamic>>? preloadedTeachers;
  final List<Map<String, dynamic>>? preloadedClasses;
  final List<Map<String, dynamic>>? preloadedAssignments; // flat list: {groupKey, lessonId, lessonName, weeklyHours, classIds, classNames}

  const ScheduleSettingsPanel({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.periodId,
    required this.periodData,
    required this.initialSettings,
    this.preloadedTeachers,
    this.preloadedClasses,
    this.preloadedAssignments,
  }) : super(key: key);

  @override
  State<ScheduleSettingsPanel> createState() => _ScheduleSettingsPanelState();
}

class _ScheduleSettingsPanelState extends State<ScheduleSettingsPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── State Variables ────────────────────────────────────────
  // State Variables
  Map<String, List<int>> _lessonBlockPatterns = {};
  Map<String, bool> _lessonAllowSplit = {};
  Map<String, bool> _lessonAvoidFirstHour = {};
  Map<String, bool> _lessonAvoidLastHour = {};
  Map<String, Map<int, int>> _lessonHourPreferences = {};
  Map<String, Set<String>> _lessonDayPreferences = {}; // key: groupKey, value: izin verilen günler
  List<Map<String, dynamic>> _lessonClassMerges = [];
  Map<String, Set<String>> _closedSlots = {};
  Map<String, int> _teacherMaxDailyHours = {};

  // Yarım Gün state
  List<int> _halfDayMorningHours = [];
  List<int> _halfDayAfternoonHours = [];
  Set<String> _halfDayFlexible = {};        // 'teacher_<id>_morning' veya '_afternoon'
  Map<String, String> _halfDayAssignedDay = {}; // 'teacher_<id>_morning' -> 'Pazartesi'

  List<Map<String, dynamic>> _allAssignments = []; // Unique lesson groups by name+hours
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _teachers = [];
  List<String> _days = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma'];
  int _dailyHours = 8;
  bool _loading = true;

  // State: Tab 1 (Bloklar)
  String? _selectedLessonGroupKey;

  // State: Tab 2 (Sınıf+Ders Birleştirme)
  String? _selectedMergeLessonGroupKey;
  Set<String> _selectedMergeClassIds = {};

  // State: Tab 3 (Saati Kapat)
  bool _closedSlotTeacherMode = true; // true = Öğretmen, false = Şube
  String? _selectedClosedId;
  String _closedSlotSearchQuery = '';
  int _closedSlotSubTab = 0; // 0: Yarım Gün Kolay Planlama, 1: Saat Kapatma / Detay Matris

  // State: Tab 4 (Öğretmen Ders Limiti)
  String _teacherLimitSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _lessonBlockPatterns = Map.from(widget.initialSettings.lessonBlockPatterns);
    _lessonAllowSplit = Map.from(widget.initialSettings.lessonAllowSplit);
    _lessonAvoidFirstHour = Map.from(widget.initialSettings.lessonAvoidFirstHour);
    _lessonAvoidLastHour = Map.from(widget.initialSettings.lessonAvoidLastHour);
    _lessonHourPreferences = widget.initialSettings.lessonHourPreferences.map(
      (k, v) => MapEntry(k, Map<int, int>.from(v)),
    );
    _lessonDayPreferences = widget.initialSettings.lessonDayPreferences.map(
      (k, v) => MapEntry(k, Set<String>.from(v)),
    );
    _lessonAvoidFirstHour.forEach((key, avoid) {
      if (avoid) {
        _lessonHourPreferences.putIfAbsent(key, () => <int, int>{})[0] = 2;
      }
    });
    _lessonClassMerges = List.from(widget.initialSettings.lessonClassMerges);
    _closedSlots = Map.fromEntries(
      widget.initialSettings.closedSlots.entries
          .map((e) => MapEntry(e.key, Set<String>.from(e.value))),
    );
    _teacherMaxDailyHours = Map.from(widget.initialSettings.teacherMaxDailyHours);
    _halfDayMorningHours = List.from(widget.initialSettings.halfDayMorningHours);
    _halfDayAfternoonHours = List.from(widget.initialSettings.halfDayAfternoonHours);
    _halfDayFlexible = Set.from(widget.initialSettings.halfDayFlexible);
    _halfDayAssignedDay = Map.from(widget.initialSettings.halfDayAssignedDays);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      // ══ FAST PATH: preloaded data'dan yükle (Firestore sorgusu yok) ══════════
      if (widget.preloadedTeachers != null &&
          widget.preloadedClasses != null &&
          widget.preloadedAssignments != null) {
        _classes = List.from(widget.preloadedClasses!);
        _teachers = List.from(widget.preloadedTeachers!);
        _allAssignments = List.from(widget.preloadedAssignments!);

        // Sadece period'dan days & hours al
        final lessonHoursDataFast =
            widget.periodData['lessonHours'] as Map<String, dynamic>?;
        if (lessonHoursDataFast != null) {
          final countsFast =
              lessonHoursDataFast['dailyLessonCounts'] as Map<String, dynamic>?;
          if (countsFast != null && countsFast.isNotEmpty) {
            final validCounts = countsFast.values
                .map((v) => v is int ? v : int.tryParse(v.toString()) ?? 0)
                .where((v) => v > 0)
                .toList();
            if (validCounts.isNotEmpty) {
              _dailyHours = validCounts.reduce((a, b) => a > b ? a : b);
            }
          }
          final sdFast = lessonHoursDataFast['selectedDays'] as List?;
          if (sdFast != null && sdFast.isNotEmpty) {
            _days = sdFast.map((e) => e.toString()).toList();
          }
        }
        if (_dailyHours < 1) _dailyHours = 8;
        final lastIdxFast = _dailyHours - 1;
        _lessonAvoidLastHour.forEach((key, avoid) {
          if (avoid) {
            _lessonHourPreferences.putIfAbsent(key, () => <int, int>{})[lastIdxFast] = 2;
          }
        });
        setState(() => _loading = false);
        return; // done — skip Firestore
      }

      // ══ SLOW PATH: Firestore'dan yükle (preloaded data yok) ═════════════════
      final termId = widget.periodData['termId'] as String?;

      // ── Tüm sorgular paralel ──────────────────────────────────
      Query classQuery = FirebaseFirestore.instance
          .collection('classes')
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true);
      if (termId != null && termId.isNotEmpty) {
        classQuery = classQuery.where('termId', isEqualTo: termId);
      }

      Query lessonQuery = FirebaseFirestore.instance
          .collection('lessons')
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true);
      if (termId != null && termId.isNotEmpty) {
        lessonQuery = lessonQuery.where('termId', isEqualTo: termId);
      }

      Query assignQuery = FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true);
      if (termId != null && termId.isNotEmpty) {
        assignQuery = assignQuery.where('termId', isEqualTo: termId);
      }


      // 4 sorguyu aynı anda başlat
      final usersFuture = FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('type', isEqualTo: 'staff')
          .where('isActive', isEqualTo: true)
          .get();

      // Paralel çalıştır
      final coreResults = await Future.wait([
        classQuery.get(),
        lessonQuery.get(),
        assignQuery.get(),
      ]);

      final classSnap = coreResults[0] as QuerySnapshot;
      final lessonSnap = coreResults[1] as QuerySnapshot;
      final assignSnap = coreResults[2] as QuerySnapshot;

      // Users sorgusu zaten başlatıldı, şimdi sonucunu al
      QuerySnapshot? usersSnap;
      try {
        usersSnap = await usersFuture;
      } catch (_) {
        usersSnap = null;
      }

      // ── Classes ───────────────────────────────────────────────
      _classes = classSnap.docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        data['id'] = d.id;
        return data;
      }).toList()
        ..sort((a, b) {
          final aL = (a['classLevel'] ?? 0).toString();
          final bL = (b['classLevel'] ?? 0).toString();
          int c = aL.compareTo(bL);
          if (c != 0) return c;
          return (a['className'] ?? '')
              .toString()
              .compareTo((b['className'] ?? '').toString());
        });

      final Map<String, String> validClassMap = {
        for (var c in _classes) c['id'] as String: (c['className'] ?? '').toString()
      };
      final Set<String> validClassIds = validClassMap.keys.toSet();

      // ── Lessons ───────────────────────────────────────────────
      final Map<String, String> validLessonMap = {
        for (var l in lessonSnap.docs)
          l.id: ((l.data() as Map<String, dynamic>)['lessonName'] ?? '').toString()
      };
      final Set<String> validLessonIds = validLessonMap.keys.toSet();

      // ── Lesson Assignments → Group ────────────────────────────
      final Map<String, Map<String, dynamic>> groupMap = {};
      for (var doc in assignSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final lId = (data['lessonId'] ?? '').toString();
        final cId = (data['classId'] ?? '').toString();

        if (!validLessonIds.contains(lId) || !validClassIds.contains(cId)) continue;

        final lName = (validLessonMap[lId]?.isNotEmpty == true
                ? validLessonMap[lId]!
                : (data['lessonName'] as String? ?? ''))
            .trim();
        if (lName.isEmpty) continue;

        final wh = (data['weeklyHours'] as num?)?.toInt() ?? 0;
        if (wh <= 0) continue;

        final cName = validClassMap[cId] ?? (data['className'] as String? ?? '').trim();
        if (cName.isEmpty) continue;

        final groupKey = '${lName.toLowerCase()}|$wh';

        if (!groupMap.containsKey(groupKey)) {
          groupMap[groupKey] = {
            'groupKey': groupKey,
            'lessonId': lId,
            'lessonName': lName,
            'weeklyHours': wh,
            'classMap': <String, String>{},
          };
        }
        (groupMap[groupKey]!['classMap'] as Map<String, String>)[cId] = cName;
      }

      _allAssignments = groupMap.values.map((g) {
        final classMap = g['classMap'] as Map<String, String>;
        final sortedClasses = classMap.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        return {
          'groupKey': g['groupKey'],
          'lessonId': g['lessonId'],
          'lessonName': g['lessonName'],
          'weeklyHours': g['weeklyHours'],
          'classIds': sortedClasses.map((e) => e.key).toList(),
          'classNames': sortedClasses.map((e) => e.value).toList(),
        };
      }).toList()
        ..sort((a, b) {
          final aName = (a['lessonName'] ?? '').toString();
          final bName = (b['lessonName'] ?? '').toString();
          int c = aName.compareTo(bName);
          if (c != 0) return c;
          final aWh = (a['weeklyHours'] is int ? a['weeklyHours'] as int : int.tryParse(a['weeklyHours']?.toString() ?? '0') ?? 0);
          final bWh = (b['weeklyHours'] is int ? b['weeklyHours'] as int : int.tryParse(b['weeklyHours']?.toString() ?? '0') ?? 0);
          return bWh.compareTo(aWh);
        });

      // ── Teachers ──────────────────────────────────────────────
      final Map<String, Map<String, dynamic>> teacherMap = {};

      // users sorgusundan öğretmenleri al
      if (usersSnap != null) {
        for (var doc in usersSnap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final tId = doc.id;
          final fName = (data['firstName'] ?? data['name'] ?? '').toString();
          final lName = (data['lastName'] ?? '').toString();
          final fullName = '$fName $lName'.trim();
          if (fullName.isNotEmpty && !teacherMap.containsKey(tId)) {
            teacherMap[tId] = {
              'id': tId,
              'firstName': fName,
              'lastName': lName,
              'name': fullName,
            };
          }
        }
      }

      // lessonAssignments'dan da öğretmenleri tamamla (sadece users boş geldiyse fallback)
      if (teacherMap.isEmpty) {
        for (var doc in assignSnap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['teacherIds'] != null && (data['teacherIds'] as List).isNotEmpty) {
            final ids = (data['teacherIds'] as List).map((e) => e.toString()).toList();
            final names = (data['teacherNames'] as List?)?.map((e) => e.toString()).toList() ?? [];
            for (int i = 0; i < ids.length; i++) {
              final id = ids[i];
              final name = i < names.length ? names[i] : 'Öğretmen';
              if (!teacherMap.containsKey(id) && id.isNotEmpty) {
                teacherMap[id] = {'id': id, 'firstName': name, 'lastName': '', 'name': name};
              }
            }
          } else if (data['teacherId'] != null) {
            final id = data['teacherId'].toString();
            final name = (data['teacherName'] ?? 'Öğretmen').toString();
            if (!teacherMap.containsKey(id) && id.isNotEmpty) {
              teacherMap[id] = {'id': id, 'firstName': name, 'lastName': '', 'name': name};
            }
          }
        }
      }

      _teachers = teacherMap.values.toList()
        ..sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));

      // ── Period Days & Daily Hours ─────────────────────────────
      final lessonHoursData =
          widget.periodData['lessonHours'] as Map<String, dynamic>?;
      if (lessonHoursData != null) {
        final counts =
            lessonHoursData['dailyLessonCounts'] as Map<String, dynamic>?;
        if (counts != null && counts.isNotEmpty) {
          final validCounts = counts.values
              .map((v) => v is int ? v : int.tryParse(v.toString()) ?? 0)
              .where((v) => v > 0)
              .toList();
          if (validCounts.isNotEmpty) {
            _dailyHours = validCounts.reduce((a, b) => a > b ? a : b);
          }
        }
        final sd = lessonHoursData['selectedDays'] as List?;
        if (sd != null && sd.isNotEmpty) {
          _days = sd.map((e) => e.toString()).toList();
        }
      }
      if (_dailyHours < 1) _dailyHours = 8;
      final lastIdx = _dailyHours - 1;
      _lessonAvoidLastHour.forEach((key, avoid) {
        if (avoid) {
          _lessonHourPreferences.putIfAbsent(key, () => <int, int>{})[lastIdx] = 2;
        }
      });
    } catch (e) {
      debugPrint('ScheduleSettingsPanel load error: $e');
    }
    setState(() => _loading = false);
  }

  void _save() {
    Navigator.pop(
      context,
      ScheduleSettings(
        lessonBlockPatterns: _lessonBlockPatterns,
        lessonAllowSplit: _lessonAllowSplit,
        lessonAvoidFirstHour: _lessonAvoidFirstHour,
        lessonAvoidLastHour: _lessonAvoidLastHour,
        lessonHourPreferences: _lessonHourPreferences,
        lessonDayPreferences: _lessonDayPreferences,
        lessonClassMerges: _lessonClassMerges,
        closedSlots: _closedSlots,
        teacherMaxDailyHours: _teacherMaxDailyHours,
        halfDayMorningHours: _halfDayMorningHours,
        halfDayAfternoonHours: _halfDayAfternoonHours,
        halfDayFlexible: Set.from(_halfDayFlexible),
        halfDayAssignedDays: Map.from(_halfDayAssignedDay),
      ),
    );
  }

  void _showLessonSelectionDialog() {
    String searchQuery = '';
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = _allAssignments.where((a) {
              final name = (a['lessonName'] as String).toLowerCase();
              return name.contains(searchQuery.toLowerCase());
            }).toList();

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                width: 420,
                constraints: const BoxConstraints(maxHeight: 520),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.school_rounded, color: Colors.indigo.shade700, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Birleştirilecek Dersi Seçin',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Ders ara...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (val) {
                        setDialogState(() {
                          searchQuery = val;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                'Ders bulunamadı.',
                                style: TextStyle(color: Colors.grey.shade500),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, idx) {
                                final a = filtered[idx];
                                final key = a['groupKey'] as String;
                                final name = a['lessonName'] as String;
                                final wh = a['weeklyHours'] is int ? a['weeklyHours'] as int : int.tryParse(a['weeklyHours']?.toString() ?? '0') ?? 0;
                                final count = (a['classIds'] as List).length;
                                final isSelected =
                                    _selectedMergeLessonGroupKey == key;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.indigo.shade50
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.indigo.shade200
                                          : Colors.transparent,
                                    ),
                                  ),
                                  child: ListTile(
                                    title: Text(
                                      name,
                                      style: TextStyle(
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isSelected
                                            ? Colors.indigo.shade900
                                            : Colors.grey.shade800,
                                        fontSize: 13,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '$wh saat/hafta • $count şube atanmış',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isSelected
                                            ? Colors.indigo.shade700
                                            : Colors.grey.shade500,
                                      ),
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: isSelected
                                          ? Colors.indigo.shade100
                                          : Colors.grey.shade100,
                                      child: Icon(
                                        Icons.class_rounded,
                                        size: 16,
                                        color: isSelected
                                            ? Colors.indigo.shade800
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                    onTap: () {
                                      setState(() {
                                        _selectedMergeLessonGroupKey = key;
                                        _selectedMergeClassIds.clear();
                                      });
                                      Navigator.pop(context);
                                    },
                                  ),
                                );
                              },
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

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.indigo.shade700, Colors.purple.shade700],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.tune_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Dağıtım Ayarları',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        widget.periodData['periodName'] ?? '',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Kaydet'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.indigo.shade700,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.all(4),
              child: LayoutBuilder(
                builder: (context, tabConstraints) {
                  final isNarrow = tabConstraints.maxWidth < 360;
                  return TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    labelColor: Colors.indigo.shade800,
                    unselectedLabelColor: Colors.grey.shade500,
                    labelStyle: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold),
                    unselectedLabelStyle: const TextStyle(fontSize: 11),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    tabs: [
                      Tab(
                          icon: const Icon(Icons.view_column_rounded, size: 18),
                          text: isNarrow ? null : 'Dağılım'),
                      Tab(
                          icon: const Icon(Icons.merge_type_rounded, size: 18),
                          text: isNarrow ? null : 'Birleştir'),
                      Tab(
                          icon: const Icon(Icons.block_rounded, size: 18),
                          text: isNarrow ? null : 'Saati Kapat'),
                      Tab(
                          icon: const Icon(Icons.timelapse_rounded, size: 18),
                          text: isNarrow ? null : 'Ders Limiti'),
                    ],
                  );
                },
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildBlockPatternTab(),
                      _buildMergeTab(),
                      _buildClosedSlotsTab(),
                      _buildTeacherDailyLimitTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // SEKME 1: Blok Dağılım
  // ══════════════════════════════════════════════════════════
  Widget _buildBlockPatternTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 500;
        
        if (isMobile) {
          // ── MOBİL: Üstte yatay scroll ders grupları + altta editor ──
          return Column(
            children: [
              // Ders grupları - yatay kaydırılabilir
              Container(
                height: 70,
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: _allAssignments.isEmpty
                    ? Center(
                        child: Text('Ders ataması yok',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                      )
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        itemCount: _allAssignments.length,
                        itemBuilder: (_, i) {
                          final a = _allAssignments[i];
                          final key = a['groupKey'] as String;
                          final isSelected = _selectedLessonGroupKey == key;
                          final hasPattern = (_lessonBlockPatterns[key] ?? []).isNotEmpty;
                          
                          return GestureDetector(
                            onTap: () => setState(() => _selectedLessonGroupKey = key),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.indigo.shade50 : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? Colors.indigo.shade400 : Colors.grey.shade200,
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 22, height: 22,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: isSelected ? Colors.indigo.shade100 : Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '${a['weeklyHours']}',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11,
                                            color: isSelected ? Colors.indigo.shade800 : Colors.grey.shade600),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        (a['lessonName'] as String).length > 12
                                            ? '${(a['lessonName'] as String).substring(0, 12)}…'
                                            : a['lessonName'] as String,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600, fontSize: 11,
                                          color: isSelected ? Colors.indigo.shade900 : Colors.grey.shade700,
                                        ),
                                      ),
                                      if (hasPattern) ...[
                                        const SizedBox(width: 4),
                                        Container(width: 6, height: 6,
                                          decoration: BoxDecoration(color: Colors.green.shade500, shape: BoxShape.circle)),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${(a['classNames'] as List).length} sınıf',
                                    style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              // Editor
              Expanded(
                child: _selectedLessonGroupKey == null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.swipe_rounded, size: 40, color: Colors.grey.shade300),
                              const SizedBox(height: 8),
                              Text('Yukarıdan bir ders grubu seçin',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade600, fontSize: 13)),
                            ],
                          ),
                        ),
                      )
                    : _buildBlockEditor(),
              ),
            ],
          );
        }
        
        // ── WEB: Sol liste + sağ editor (orijinal layout) ──
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 230,
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Ders Grupları',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _allAssignments.isEmpty
                        ? Center(
                            child: Text(
                              'Ders ataması yok',
                              style: TextStyle(
                                  color: Colors.grey.shade400, fontSize: 12),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            itemCount: _allAssignments.length,
                            itemBuilder: (_, i) {
                              final a = _allAssignments[i];
                              final key = a['groupKey'] as String;
                              final isSelected = _selectedLessonGroupKey == key;
                              final hasPattern =
                                  (_lessonBlockPatterns[key] ?? []).isNotEmpty;
                              final classNames =
                                  (a['classNames'] as List).join(', ');

                              return GestureDetector(
                                onTap: () =>
                                    setState(() => _selectedLessonGroupKey = key),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  margin: const EdgeInsets.only(bottom: 4),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.indigo.shade50
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.indigo.shade300
                                          : Colors.transparent,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? Colors.indigo.shade100
                                              : Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '${a['weeklyHours']}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: isSelected
                                                ? Colors.indigo.shade800
                                                : Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              a['lessonName'] as String,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                                color: isSelected
                                                    ? Colors.indigo.shade900
                                                    : Colors.grey.shade800,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              classNames,
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey.shade500),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (hasPattern)
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade500,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _selectedLessonGroupKey == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.touch_app_rounded,
                                size: 48, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text(
                              'Sol taraftan bir ders grubu seçin',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Seçilen ders grubunun blok dağılımını burada düzenleyebilirsiniz.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _buildBlockEditor(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBlockEditor() {
    final blockKey = _selectedLessonGroupKey!;
    final assignment = _allAssignments.firstWhere(
      (a) => a['groupKey'] == blockKey,
      orElse: () => <String, dynamic>{},
    );
    final weeklyHours = (assignment['weeklyHours'] as int?) ?? 0;
    final blocks = List<int>.from(_lessonBlockPatterns[blockKey] ?? []);
    final allowSplit = _lessonAllowSplit[blockKey] ?? false;
    final total = blocks.fold(0, (s, b) => s + b);
    final remaining = weeklyHours - total;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.indigo.shade600, Colors.purple.shade600],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  assignment['lessonName'] as String? ?? '',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Haftalık $weeklyHours saat',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Blok Yapısı',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...blocks.asMap().entries.map((entry) {
                final idx = entry.key;
                final size = entry.value;
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.indigo.shade400, Colors.purple.shade400],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.indigo.withOpacity(0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: size > 1
                            ? () => setState(() {
                                  blocks[idx] = size - 1;
                                  _lessonBlockPatterns[blockKey] =
                                      List.from(blocks);
                                })
                            : null,
                        child: Icon(Icons.remove_rounded,
                            size: 14,
                            color: size > 1 ? Colors.white : Colors.white38),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$size',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: total < weeklyHours
                            ? () => setState(() {
                                  blocks[idx] = size + 1;
                                  _lessonBlockPatterns[blockKey] =
                                      List.from(blocks);
                                })
                            : null,
                        child: Icon(Icons.add_rounded,
                            size: 14,
                            color: total < weeklyHours
                                ? Colors.white
                                : Colors.white38),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => setState(() {
                          blocks.removeAt(idx);
                          if (blocks.isEmpty) {
                            _lessonBlockPatterns.remove(blockKey);
                          } else {
                            _lessonBlockPatterns[blockKey] = List.from(blocks);
                          }
                        }),
                        child: const Icon(Icons.close_rounded,
                            size: 14, color: Colors.white60),
                      ),
                    ],
                  ),
                );
              }),
              if (remaining > 0)
                GestureDetector(
                  onTap: () => setState(() {
                    blocks.add(1);
                    _lessonBlockPatterns[blockKey] = List.from(blocks);
                  }),
                  child: Container(
                    width: 52,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.indigo.shade200),
                    ),
                    child: Icon(Icons.add_rounded,
                        color: Colors.indigo.shade600, size: 24),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: remaining == 0
                  ? Colors.green.shade50
                  : Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: remaining == 0
                    ? Colors.green.shade200
                    : Colors.amber.shade300,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  remaining == 0
                      ? Icons.check_circle_rounded
                      : Icons.info_outline_rounded,
                  color: remaining == 0
                      ? Colors.green.shade700
                      : Colors.amber.shade700,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    remaining == 0
                        ? 'Tüm saatler bloklara atandı (${blocks.join(' + ')} = $weeklyHours)'
                        : 'Dağıtılan: $total/$weeklyHours saat.  $remaining saat → tekli yerleştirilecek.',
                    style: TextStyle(
                      fontSize: 12,
                      color: remaining == 0
                          ? Colors.green.shade800
                          : Colors.amber.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: allowSplit ? Colors.orange.shade50 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    allowSplit ? Colors.orange.shade300 : Colors.grey.shade200,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  allowSplit
                      ? Icons.call_split_rounded
                      : Icons.lock_outline_rounded,
                  color:
                      allowSplit ? Colors.orange.shade700 : Colors.grey.shade500,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gerekirse blokları parçala',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: allowSplit
                              ? Colors.orange.shade800
                              : Colors.grey.shade700,
                        ),
                      ),
                      Text(
                        allowSplit
                            ? 'Yer bulamazsa blok 3→2→1 şeklinde küçültülür'
                            : 'Blok sığmazsa o blok yerleştirilemez',
                        style: TextStyle(
                          fontSize: 11,
                          color: allowSplit
                              ? Colors.orange.shade600
                              : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: allowSplit,
                  onChanged: (v) =>
                      setState(() => _lessonAllowSplit[blockKey] = v),
                  activeColor: Colors.orange.shade600,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Saat Yerleşim Tercihleri
          _buildHourPreferencesSection(blockKey),
          const SizedBox(height: 10),

          // Gün Yerleşim Tercihleri
          _buildDayPreferencesSection(blockKey),
          const SizedBox(height: 10),

          // Bu dersi ilk saate verme
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: (_lessonAvoidFirstHour[blockKey] ?? false)
                  ? Colors.red.shade50
                  : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (_lessonAvoidFirstHour[blockKey] ?? false)
                    ? Colors.red.shade200
                    : Colors.grey.shade200,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.wb_sunny_outlined,
                  color: (_lessonAvoidFirstHour[blockKey] ?? false)
                      ? Colors.red.shade700
                      : Colors.grey.shade500,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bu dersi ilk saate verme',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: (_lessonAvoidFirstHour[blockKey] ?? false)
                              ? Colors.red.shade800
                              : Colors.grey.shade700,
                        ),
                      ),
                      Text(
                        'Bu ders günün 1. saatine (0. index) yerleştirilmez',
                        style: TextStyle(
                          fontSize: 11,
                          color: (_lessonAvoidFirstHour[blockKey] ?? false)
                              ? Colors.red.shade600
                              : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _lessonAvoidFirstHour[blockKey] ?? false,
                  onChanged: (v) {
                    setState(() {
                      _lessonAvoidFirstHour[blockKey] = v;
                      final currentMap = _lessonHourPreferences.putIfAbsent(blockKey, () => <int, int>{});
                      if (v) {
                        currentMap[0] = 2; // 1. ders kutusunu kırmızı yap
                      } else {
                        if (currentMap[0] == 2) {
                          currentMap.remove(0); // Kırmızıysa pasife döndür
                        }
                      }
                    });
                  },
                  activeColor: Colors.red.shade600,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Bu dersi son saate verme
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: (_lessonAvoidLastHour[blockKey] ?? false)
                  ? Colors.red.shade50
                  : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (_lessonAvoidLastHour[blockKey] ?? false)
                    ? Colors.red.shade200
                    : Colors.grey.shade200,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.nightlight_round,
                  color: (_lessonAvoidLastHour[blockKey] ?? false)
                      ? Colors.red.shade700
                      : Colors.grey.shade500,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bu dersi son saate verme',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: (_lessonAvoidLastHour[blockKey] ?? false)
                              ? Colors.red.shade800
                              : Colors.grey.shade700,
                        ),
                      ),
                      Text(
                        'Bu ders günün en son ders saatine yerleştirilmez',
                        style: TextStyle(
                          fontSize: 11,
                          color: (_lessonAvoidLastHour[blockKey] ?? false)
                              ? Colors.red.shade600
                              : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _lessonAvoidLastHour[blockKey] ?? false,
                  onChanged: (v) {
                    setState(() {
                      _lessonAvoidLastHour[blockKey] = v;
                      final lastHourIdx = _dailyHours > 0 ? _dailyHours - 1 : 7;
                      final currentMap = _lessonHourPreferences.putIfAbsent(blockKey, () => <int, int>{});
                      if (v) {
                        currentMap[lastHourIdx] = 2; // Son ders kutusunu kırmızı yap
                      } else {
                        if (currentMap[lastHourIdx] == 2) {
                          currentMap.remove(lastHourIdx); // Kırmızıysa pasife döndür
                        }
                      }
                    });
                  },
                  activeColor: Colors.red.shade600,
                ),
              ],
            ),
          ),
          if (blocks.isNotEmpty) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => setState(() {
                _lessonBlockPatterns.remove(blockKey);
                _lessonAllowSplit.remove(blockKey);
              }),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Blok yapısını sıfırla',
                  style: TextStyle(fontSize: 12)),
              style:
                  TextButton.styleFrom(foregroundColor: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHourPreferencesSection(String blockKey) {
    final hourPrefs = _lessonHourPreferences[blockKey] ?? {};
    final totalHours = _dailyHours > 0 ? _dailyHours : 8;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 18, color: Colors.indigo.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Bu ders hangi saatlere yerleştirilsin / yerleştirilmesin?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Saat kutusuna tıklayarak durumu değiştirin: Gri = Serbest, Yeşil = Yerleşsin, Kırmızı = Yerleşmesin',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(totalHours, (h) {
              final state = hourPrefs[h] ?? 0;
              Color bgColor;
              Color borderColor;
              Color textColor;
              String tooltipText;
              Widget icon;

              if (state == 1) {
                // Yeşil (O saate yerleşsin)
                bgColor = Colors.green.shade600;
                borderColor = Colors.green.shade800;
                textColor = Colors.white;
                tooltipText = '${h + 1}. Ders: O saate yerleşsin';
                icon = const Icon(Icons.check, size: 11, color: Colors.white);
              } else if (state == 2) {
                // Kırmızı (O saate yerleşmesin)
                bgColor = Colors.red.shade600;
                borderColor = Colors.red.shade800;
                textColor = Colors.white;
                tooltipText = '${h + 1}. Ders: O saate yerleşmesin';
                icon = const Icon(Icons.close, size: 11, color: Colors.white);
              } else {
                // Pasif (Gri / Herhangi bir kıstas yok)
                bgColor = Colors.white;
                borderColor = Colors.grey.shade300;
                textColor = Colors.grey.shade800;
                tooltipText = '${h + 1}. Ders: Kıstas yok (Serbest)';
                icon = Text(
                  'Ders',
                  style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
                );
              }

              return Tooltip(
                message: tooltipText,
                child: InkWell(
                  onTap: () => _toggleHourPreference(blockKey, h),
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor, width: 1.5),
                      boxShadow: state != 0
                          ? [
                              BoxShadow(
                                color: (state == 1 ? Colors.green : Colors.red).withOpacity(0.25),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              )
                            ]
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${h + 1}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        icon,
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          // Renk Açıklama / Legend
          Row(
            children: [
              _buildLegendItem(Colors.white, Colors.grey.shade400, Colors.grey.shade700, 'Kıstas Yok'),
              const SizedBox(width: 12),
              _buildLegendItem(Colors.green.shade600, Colors.green.shade800, Colors.green.shade800, 'Yerleşsin'),
              const SizedBox(width: 12),
              _buildLegendItem(Colors.red.shade600, Colors.red.shade800, Colors.red.shade800, 'Yerleşmesin'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDayPreferencesSection(String blockKey) {
    // Program'da aktif günler (schedule'dan yükle, yoksa hafta içi default)
    final allPossibleDays = ['Pazartesi', 'Sal\u0131', 'Çar\u015famba', 'Per\u015fembe', 'Cuma', 'Cumartesi', 'Pazar'];
    final scheduleDays = Set<String>.from(_days); // Programda seçili günler
    // Sadece programda aktif olan günleri göster
    final visibleDays = allPossibleDays.where((d) => scheduleDays.contains(d)).toList();

    if (visibleDays.isEmpty) return const SizedBox.shrink();

    // Mevcut gün tercihleri (boşsa = tüm günler serbest = default tüm aktif günler)
    final currentPref = _lessonDayPreferences[blockKey];
    // Eğer hiç tercih yoksa: tüm günler aktif
    final activeDays = currentPref != null
        ? Set<String>.from(currentPref)
        : Set<String>.from(visibleDays);

    final weekdays = visibleDays.where((d) => !['Cumartesi', 'Pazar'].contains(d)).toList();
    final weekend = visibleDays.where((d) => ['Cumartesi', 'Pazar'].contains(d)).toList();

    final hasConstraint = currentPref != null &&
        !_setEquals(currentPref, Set<String>.from(visibleDays));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasConstraint ? Colors.teal.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasConstraint ? Colors.teal.shade200 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today_rounded,
                  size: 18,
                  color: hasConstraint ? Colors.teal.shade700 : Colors.grey.shade600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Bu ders hangi günlere yerleştirilsin?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: hasConstraint ? Colors.teal.shade800 : Colors.grey.shade800,
                  ),
                ),
              ),
              if (hasConstraint)
                TextButton(
                  onPressed: () {
                    setState(() => _lessonDayPreferences.remove(blockKey));
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.teal.shade700,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Sıfırla', style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Varsayılan: tüm aktif günler. Günü kapatmak için tıklayın.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sol: Hızlı seçim
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (weekdays.isNotEmpty)
                    _buildQuickDaySelect(
                      label: 'H.İçi',
                      onTap: () {
                        setState(() {
                          final newSet = Set<String>.from(activeDays);
                          final allWeekdaysActive = weekdays.every(newSet.contains);
                          if (allWeekdaysActive) {
                            newSet.removeAll(weekdays);
                          } else {
                            newSet.addAll(weekdays);
                          }
                          if (_setEquals(newSet, Set<String>.from(visibleDays))) {
                            _lessonDayPreferences.remove(blockKey);
                          } else {
                            _lessonDayPreferences[blockKey] = newSet;
                          }
                        });
                      },
                      isActive: weekdays.every(activeDays.contains),
                      color: Colors.teal,
                    ),
                  if (weekdays.isNotEmpty) const SizedBox(height: 6),
                  if (weekend.isNotEmpty)
                    _buildQuickDaySelect(
                      label: 'H.Sonu',
                      onTap: () {
                        setState(() {
                          final newSet = Set<String>.from(activeDays);
                          final allWeekendActive = weekend.every(newSet.contains);
                          if (allWeekendActive) {
                            newSet.removeAll(weekend);
                          } else {
                            newSet.addAll(weekend);
                          }
                          if (_setEquals(newSet, Set<String>.from(visibleDays))) {
                            _lessonDayPreferences.remove(blockKey);
                          } else {
                            _lessonDayPreferences[blockKey] = newSet;
                          }
                        });
                      },
                      isActive: weekend.isNotEmpty && weekend.every(activeDays.contains),
                      color: Colors.indigo,
                    ),
                ],
              ),
              const SizedBox(width: 12),
              // Sağ: Gün butonları
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: visibleDays.map((day) {
                    final isOn = activeDays.contains(day);
                    final shortDay = day.length > 3 ? day.substring(0, 3) : day;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          final newSet = Set<String>.from(activeDays);
                          if (isOn) {
                            newSet.remove(day);
                          } else {
                            newSet.add(day);
                          }
                          if (_setEquals(newSet, Set<String>.from(visibleDays))) {
                            _lessonDayPreferences.remove(blockKey);
                          } else {
                            _lessonDayPreferences[blockKey] = newSet;
                          }
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 46,
                        height: 38,
                        decoration: BoxDecoration(
                          color: isOn ? Colors.teal.shade500 : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isOn ? Colors.teal.shade700 : Colors.grey.shade300,
                            width: isOn ? 2 : 1,
                          ),
                          boxShadow: isOn
                              ? [BoxShadow(
                                  color: Colors.teal.shade100,
                                  blurRadius: 4,
                                  offset: const Offset(0, 2))]
                              : [],
                        ),
                        child: Center(
                          child: Text(
                            shortDay,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isOn ? Colors.white : Colors.grey.shade500,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _setEquals<T>(Set<T> a, Set<T> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  Widget _buildQuickDaySelect({
    required String label,
    required VoidCallback onTap,
    required bool isActive,
    required MaterialColor color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? color.shade100 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? color.shade400 : Colors.grey.shade300,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isActive ? color.shade800 : Colors.grey.shade500,
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color fill, Color border, Color textCol, String label) {


    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: border),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: textCol, fontWeight: FontWeight.w500)),
      ],
    );
  }

  void _toggleHourPreference(String blockKey, int hourIndex) {
    setState(() {
      final currentMap = _lessonHourPreferences.putIfAbsent(blockKey, () => <int, int>{});
      final currentState = currentMap[hourIndex] ?? 0;
      final nextState = (currentState + 1) % 3;
      if (nextState == 0) {
        currentMap.remove(hourIndex);
      } else {
        currentMap[hourIndex] = nextState;
      }

      final lastHourIdx = _dailyHours > 0 ? _dailyHours - 1 : 7;

      // 1. ders kırmızı olursa ilk ders switch'ini aç, kırmızı değilse kapat
      if (hourIndex == 0) {
        _lessonAvoidFirstHour[blockKey] = (nextState == 2);
      }

      // Son ders kırmızı olursa son ders switch'ini aç, kırmızı değilse kapat
      if (hourIndex == lastHourIdx) {
        _lessonAvoidLastHour[blockKey] = (nextState == 2);
      }
    });
  }

  // ══════════════════════════════════════════════════════════
  // SEKME 2: Sınıf + Ders Birleştirme (YENİ VE DOĞRU MANTIK)
  // ══════════════════════════════════════════════════════════
  Widget _buildMergeTab() {
    // Currently selected lesson group
    final currentLessonGroup = _selectedMergeLessonGroupKey != null
        ? _allAssignments.firstWhere(
            (a) => a['groupKey'] == _selectedMergeLessonGroupKey,
            orElse: () => <String, dynamic>{},
          )
        : null;

    final availableClasses = currentLessonGroup != null
        ? (currentLessonGroup['classIds'] as List<String>)
        : <String>[];
    final availableClassNames = currentLessonGroup != null
        ? (currentLessonGroup['classNames'] as List<String>)
        : <String>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            Icons.merge_type_rounded,
            'Ortak Ders / Sınıf Birleştirme',
            'Birden fazla şubenin aynı ders saatinde birleştirilerek tek ders olarak işlenmesini sağlar.',
          ),
          const SizedBox(height: 20),

          // Ekleme Kartı
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '1. Birleştirilecek Dersi Seçin',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _showLessonSelectionDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.school_rounded, color: Colors.indigo.shade600, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            currentLessonGroup != null
                                ? "${currentLessonGroup['lessonName']} (${currentLessonGroup['weeklyHours']} saat/hafta)"
                                : 'Bir ders seçmek için dokunun...',
                            style: TextStyle(
                              fontSize: 13,
                              color: currentLessonGroup != null
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade500,
                              fontWeight: currentLessonGroup != null
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        Icon(Icons.keyboard_arrow_down_rounded,
                            color: Colors.grey.shade600),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                if (currentLessonGroup != null) ...[
                  Text(
                    '2. Ortak İşlenecek Şubeleri Seçin (${_selectedMergeClassIds.length} Şube Seçili)',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(availableClasses.length, (idx) {
                      final cId = availableClasses[idx];
                      final cName = availableClassNames[idx];
                      final isChecked = _selectedMergeClassIds.contains(cId);

                      return FilterChip(
                        selected: isChecked,
                        label: Text(cName),
                        selectedColor: Colors.indigo.shade100,
                        checkmarkColor: Colors.indigo.shade800,
                        labelStyle: TextStyle(
                          fontWeight: isChecked
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isChecked
                              ? Colors.indigo.shade900
                              : Colors.grey.shade800,
                        ),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedMergeClassIds.add(cId);
                            } else {
                              _selectedMergeClassIds.remove(cId);
                            }
                          });
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _selectedMergeClassIds.length >= 2
                          ? () {
                              final mergeId = DateTime.now()
                                  .millisecondsSinceEpoch
                                  .toString();
                              final selectedNames = <String>[];
                              for (var id in _selectedMergeClassIds) {
                                final i = availableClasses.indexOf(id);
                                if (i != -1) {
                                  selectedNames.add(availableClassNames[i]);
                                }
                              }

                              setState(() {
                                _lessonClassMerges.add({
                                  'id': mergeId,
                                  'groupKey': currentLessonGroup['groupKey'],
                                  'lessonId': currentLessonGroup['lessonId'],
                                  'lessonName': currentLessonGroup['lessonName'],
                                  'weeklyHours': currentLessonGroup['weeklyHours'],
                                  'classIds': _selectedMergeClassIds.toList(),
                                  'classNames': selectedNames,
                                });
                                _selectedMergeClassIds.clear();
                              });
                            }
                          : null,
                      icon: const Icon(Icons.link_rounded, size: 18),
                      label: Text(
                        _selectedMergeClassIds.length < 2
                          ? 'En az 2 şube seçin'
                          : 'Şubeleri Birleştir (${_selectedMergeClassIds.length} Şube)',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.indigo.shade600,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Mevcut birleştirilmiş ders-şube grupları
          if (_lessonClassMerges.isNotEmpty) ...[
            Text(
              'Birleştirilmiş Ortak Ders Grupları (${_lessonClassMerges.length})',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            ..._lessonClassMerges.asMap().entries.map((entry) {
              final idx = entry.key;
              final merge = entry.value;
              final lessonName = merge['lessonName'] as String;
              final wh = merge['weeklyHours'] is int ? merge['weeklyHours'] as int : int.tryParse(merge['weeklyHours']?.toString() ?? '0') ?? 0;
              final classNames = (merge['classNames'] as List).join(' 🔗 ');

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.indigo.shade100),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.indigo.shade700,
                            Colors.purple.shade700
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$lessonName ($wh sa)',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Şubeler: $classNames',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.indigo.shade900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(
                          () => _lessonClassMerges.removeAt(idx)),
                      child: Icon(Icons.close_rounded,
                          color: Colors.red.shade400, size: 20),
                    ),
                  ],
                ),
              );
            }),
          ] else
            _buildInfoBanner(
                'Henüz birleştirilmiş ders yok. Yukarıdan ders ve şubeleri seçip birleştirin.'),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // SEKME 3: Ders Saati Kapatma & Yarım Gün İzinleri (Öğretmen + Şube)
  // ══════════════════════════════════════════════════════════
  Widget _buildClosedSlotsTab() {
    final items = _closedSlotTeacherMode ? _teachers : _classes;
    return Column(
      children: [
        // ── Üst kontrol satırı ──────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              _buildToggle('🧑‍🏫 Öğretmen (${_teachers.length})',
                  _closedSlotTeacherMode, () {
                setState(() {
                  _closedSlotTeacherMode = true;
                  _selectedClosedId = null;
                });
              }),
              const SizedBox(width: 8),
              _buildToggle(
                  '🏫 Şube (${_classes.length})', !_closedSlotTeacherMode, () {
                setState(() {
                  _closedSlotTeacherMode = false;
                  _selectedClosedId = null;
                });
              }),
              const Spacer(),
              if (_selectedClosedId != null)
                TextButton.icon(
                  onPressed: () => setState(() => _selectedClosedId = null),
                  icon: const Icon(Icons.arrow_back_ios_rounded, size: 14),
                  label: const Text('Geri', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.grey.shade600),
                ),
            ],
          ),
        ),

        // ── Öğretmen modunda alt mod seçimi: [⚡ Yarım Gün Planlama] vs [🔴 Saat Kapatma] ──
        if (_closedSlotTeacherMode && _selectedClosedId == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _closedSlotSubTab = 0),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _closedSlotSubTab == 0 ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _closedSlotSubTab == 0
                              ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)]
                              : [],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.wb_sunny_rounded,
                                size: 16,
                                color: _closedSlotSubTab == 0 ? Colors.orange.shade700 : Colors.grey.shade600),
                            const SizedBox(width: 6),
                            Text(
                              'Yarım Gün Kolay Planlama',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: _closedSlotSubTab == 0 ? FontWeight.bold : FontWeight.w500,
                                color: _closedSlotSubTab == 0 ? Colors.orange.shade900 : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _closedSlotSubTab = 1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _closedSlotSubTab == 1 ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _closedSlotSubTab == 1
                              ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)]
                              : [],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.grid_on_rounded,
                                size: 16,
                                color: _closedSlotSubTab == 1 ? Colors.indigo.shade700 : Colors.grey.shade600),
                            const SizedBox(width: 6),
                            Text(
                              'Tekil Saat Kapatma (Detay)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: _closedSlotSubTab == 1 ? FontWeight.bold : FontWeight.w500,
                                color: _closedSlotSubTab == 1 ? Colors.indigo.shade900 : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── Yarım Gün Saatleri Tanımı (sadece öğretmen modunda) ──
        if (_closedSlotTeacherMode && _selectedClosedId == null)
          _buildHalfDayDefinitionCard(),

        const SizedBox(height: 6),
        Expanded(
          child: _selectedClosedId != null
              ? _buildSlotGrid()
              : (_closedSlotTeacherMode && _closedSlotSubTab == 0
                  ? _buildHalfDayPracticalListView()
                  : _buildPersonList(items)),
        ),
      ],
    );
  }

  /// Sabah / Öğleden Sonra yarım gün saatlerini tanımlayan kart
  Widget _buildHalfDayDefinitionCard() {
    final allHours = List.generate(_dailyHours, (i) => i);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade50, Colors.purple.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.access_time_rounded, size: 15, color: Color(0xFF5C6BC0)),
              const SizedBox(width: 6),
              const Text(
                'Yarım Gün Saati Tanımı',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3949AB),
                ),
              ),
              const Spacer(),
              if (_halfDayMorningHours.isNotEmpty || _halfDayAfternoonHours.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() {
                    _halfDayMorningHours = [];
                    _halfDayAfternoonHours = [];
                  }),
                  child: Text('Temizle',
                      style: TextStyle(fontSize: 11, color: Colors.red.shade400)),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Sabah Yarım Günü
          _buildHalfDayRow(
            label: '🌅 Sabah',
            color: Colors.orange,
            selectedHours: _halfDayMorningHours,
            allHours: allHours,
            onToggle: (h) {
              setState(() {
                if (_halfDayMorningHours.contains(h)) {
                  _halfDayMorningHours.remove(h);
                } else {
                  _halfDayMorningHours.add(h);
                  _halfDayMorningHours.sort();
                }
              });
            },
          ),
          const SizedBox(height: 10),

          // Öğleden Sonra
          _buildHalfDayRow(
            label: '🌆 Öğleden Sonra',
            color: Colors.deepPurple,
            selectedHours: _halfDayAfternoonHours,
            allHours: allHours,
            onToggle: (h) {
              setState(() {
                if (_halfDayAfternoonHours.contains(h)) {
                  _halfDayAfternoonHours.remove(h);
                } else {
                  _halfDayAfternoonHours.add(h);
                  _halfDayAfternoonHours.sort();
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHalfDayRow({
    required String label,
    required MaterialColor color,
    required List<int> selectedHours,
    required List<int> allHours,
    required void Function(int) onToggle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color.shade700,
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: allHours.map((h) {
              final isSelected = selectedHours.contains(h);
              return GestureDetector(
                onTap: () => onToggle(h),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 36,
                  height: 30,
                  decoration: BoxDecoration(
                    color: isSelected ? color.shade500 : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? color.shade600 : Colors.grey.shade300,
                    ),
                    boxShadow: isSelected
                        ? [BoxShadow(color: color.shade200, blurRadius: 4)]
                        : [],
                  ),
                  child: Center(
                    child: Text(
                      '${h + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(width: 8),
        if (selectedHours.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${selectedHours.length} saat',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: color.shade700,
              ),
            ),
          ),
      ],
    );
  }

  /// Tek ekranda tüm öğretmenlerin Sabah / Akşam ve Gün (Esnek / Belirli Gün) pratik planlaması
  Widget _buildHalfDayPracticalListView() {
    if (_halfDayMorningHours.isEmpty && _halfDayAfternoonHours.isEmpty) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline_rounded, size: 36, color: Colors.amber.shade800),
              const SizedBox(height: 10),
              Text(
                'Yarım Gün Saatleri Henüz Tanımlanmadı',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Lütfen yukarıdaki kutudan Sabah ve Öğleden Sonra saat bloklarını seçin (Örn: Sabah 1-4, Öğleden Sonra 5-8).',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
              ),
            ],
          ),
        ),
      );
    }

    final query = _closedSlotSearchQuery.toLowerCase().trim();
    final filteredTeachers = _teachers.where((t) {
      if (query.isEmpty) return true;
      final name = (t['name'] ?? '${t['firstName'] ?? ''} ${t['lastName'] ?? ''}').toString().toLowerCase();
      return name.contains(query);
    }).toList();

    return Column(
      children: [
        // Arama ve Bilgi Çubuğu
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: TextField(
                    onChanged: (val) => setState(() => _closedSlotSearchQuery = val),
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Öğretmen ara...',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      prefixIcon: Icon(Icons.search_rounded, size: 16, color: Colors.grey.shade500),
                      suffixIcon: _closedSlotSearchQuery.isNotEmpty
                          ? GestureDetector(
                              onTap: () => setState(() => _closedSlotSearchQuery = ''),
                              child: const Icon(Icons.clear_rounded, size: 16, color: Colors.grey),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.indigo.shade100),
                ),
                child: Text(
                  '${filteredTeachers.length} Öğretmen',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade800,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Liste
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: filteredTeachers.length,
            itemBuilder: (context, index) {
              final teacher = filteredTeachers[index];
              final id = teacher['id'] as String;
              final prefix = 'teacher_$id';
              final name = (teacher['name'] ?? '${teacher['firstName'] ?? ''} ${teacher['lastName'] ?? ''}').toString().trim();

              // Sabah / Akşam durumu belirleme
              final morningDay = _halfDayAssignedDay['${prefix}_morning'];
              final afternoonDay = _halfDayAssignedDay['${prefix}_afternoon'];
              final isMorningFlex = _halfDayFlexible.contains('${prefix}_morning');
              final isAfternoonFlex = _halfDayFlexible.contains('${prefix}_afternoon');

              // Aktif mod: 'none', 'morning', 'afternoon'
              String activeType = 'none';
              if (morningDay != null) {
                activeType = 'morning';
              } else if (afternoonDay != null) {
                activeType = 'afternoon';
              }

              final currentDay = activeType == 'morning'
                  ? morningDay
                  : (activeType == 'afternoon' ? afternoonDay : null);

              final isCurrentFlex = activeType == 'morning'
                  ? isMorningFlex
                  : (activeType == 'afternoon' ? isAfternoonFlex : false);

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: activeType != 'none' ? Colors.orange.shade300 : Colors.grey.shade200,
                    width: activeType != 'none' ? 1.5 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: activeType != 'none'
                          ? Colors.orange.withOpacity(0.06)
                          : Colors.black.withOpacity(0.02),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Öğretmen Adı ve Durum Özeti
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: activeType != 'none' ? Colors.orange.shade100 : Colors.grey.shade100,
                          child: Icon(
                            activeType != 'none' ? Icons.wb_sunny_rounded : Icons.person_outline_rounded,
                            size: 15,
                            color: activeType != 'none' ? Colors.orange.shade800 : Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF263238),
                            ),
                          ),
                        ),
                        if (activeType != 'none')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: activeType == 'morning'
                                    ? [Colors.orange.shade400, Colors.amber.shade500]
                                    : [Colors.purple.shade400, Colors.deepPurple.shade500],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${activeType == 'morning' ? '🌅 Sabah' : '🌆 Akşam'} ${isCurrentFlex ? '(Esnek)' : '($currentDay)'}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Kontrol Satırı: [Yok | Sabah | Akşam] Segmenti ve Gün / Esnek Butonları
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Vakit Segmenti
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildMiniSegmentItem(
                                title: 'Yok',
                                isSelected: activeType == 'none',
                                activeBgColor: Colors.grey.shade400,
                                activeTextColor: Colors.white,
                                onTap: () {
                                  setState(() {
                                    final set = _closedSlots.putIfAbsent(prefix, () => <String>{});
                                    if (morningDay != null) {
                                      final oldSlots = _halfDayMorningHours.map((h) => '${morningDay}_$h').toSet();
                                      set.removeAll(oldSlots);
                                      _halfDayFlexible.remove('${prefix}_morning');
                                      _halfDayAssignedDay.remove('${prefix}_morning');
                                    }
                                    if (afternoonDay != null) {
                                      final oldSlots = _halfDayAfternoonHours.map((h) => '${afternoonDay}_$h').toSet();
                                      set.removeAll(oldSlots);
                                      _halfDayFlexible.remove('${prefix}_afternoon');
                                      _halfDayAssignedDay.remove('${prefix}_afternoon');
                                    }
                                    if (set.isEmpty) _closedSlots.remove(prefix);
                                  });
                                },
                              ),
                              _buildMiniSegmentItem(
                                title: '🌅 Sabah',
                                isSelected: activeType == 'morning',
                                activeBgColor: Colors.orange.shade500,
                                activeTextColor: Colors.white,
                                onTap: () {
                                  setState(() {
                                    final set = _closedSlots.putIfAbsent(prefix, () => <String>{});
                                    // Önce akşamı temizle
                                    if (afternoonDay != null) {
                                      final oldSlots = _halfDayAfternoonHours.map((h) => '${afternoonDay}_$h').toSet();
                                      set.removeAll(oldSlots);
                                      _halfDayFlexible.remove('${prefix}_afternoon');
                                      _halfDayAssignedDay.remove('${prefix}_afternoon');
                                    }
                                    // Sabah için gün seç: mevcut gün veya ilk gün
                                    final targetDay = currentDay ?? _days.first;
                                    _halfDayAssignedDay['${prefix}_morning'] = targetDay;
                                    final slots = _halfDayMorningHours.map((h) => '${targetDay}_$h').toSet();
                                    if (isCurrentFlex) {
                                      _halfDayFlexible.add('${prefix}_morning');
                                      set.removeAll(slots);
                                    } else {
                                      _halfDayFlexible.remove('${prefix}_morning');
                                      set.addAll(slots);
                                    }
                                    if (set.isEmpty) _closedSlots.remove(prefix);
                                  });
                                },
                              ),
                              _buildMiniSegmentItem(
                                title: '🌆 Akşam',
                                isSelected: activeType == 'afternoon',
                                activeBgColor: Colors.deepPurple.shade500,
                                activeTextColor: Colors.white,
                                onTap: () {
                                  setState(() {
                                    final set = _closedSlots.putIfAbsent(prefix, () => <String>{});
                                    // Önce sabahı temizle
                                    if (morningDay != null) {
                                      final oldSlots = _halfDayMorningHours.map((h) => '${morningDay}_$h').toSet();
                                      set.removeAll(oldSlots);
                                      _halfDayFlexible.remove('${prefix}_morning');
                                      _halfDayAssignedDay.remove('${prefix}_morning');
                                    }
                                    final targetDay = currentDay ?? _days.first;
                                    _halfDayAssignedDay['${prefix}_afternoon'] = targetDay;
                                    final slots = _halfDayAfternoonHours.map((h) => '${targetDay}_$h').toSet();
                                    if (isCurrentFlex) {
                                      _halfDayFlexible.add('${prefix}_afternoon');
                                      set.removeAll(slots);
                                    } else {
                                      _halfDayFlexible.remove('${prefix}_afternoon');
                                      set.addAll(slots);
                                    }
                                    if (set.isEmpty) _closedSlots.remove(prefix);
                                  });
                                },
                              ),
                            ],
                          ),
                        ),

                        // Gün / Esnek Seçici (Sadece Sabah veya Akşam seçiliyse göster)
                        if (activeType != 'none') ...[
                          // Esnek Butonu
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                final set = _closedSlots.putIfAbsent(prefix, () => <String>{});
                                final key = '${prefix}_$activeType';
                                final targetDay = currentDay ?? _days.first;
                                final hours = activeType == 'morning' ? _halfDayMorningHours : _halfDayAfternoonHours;
                                final slots = hours.map((h) => '${targetDay}_$h').toSet();

                                if (isCurrentFlex) {
                                  // Esnekliği kapat, sabit güne bağla
                                  _halfDayFlexible.remove(key);
                                  set.addAll(slots);
                                } else {
                                  // Esnekliği aç, kapalı slotları kaldır (sistem seçsin)
                                  _halfDayFlexible.add(key);
                                  set.removeAll(slots);
                                }
                                if (set.isEmpty) _closedSlots.remove(prefix);
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isCurrentFlex ? Colors.teal.shade600 : Colors.teal.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isCurrentFlex ? Colors.teal.shade700 : Colors.teal.shade200,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 13,
                                    color: isCurrentFlex ? Colors.white : Colors.teal.shade700,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '🎲 Esnek Gün',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isCurrentFlex ? Colors.white : Colors.teal.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Gün Seçim Butonları
                          ..._days.map((day) {
                            final isDaySelected = currentDay == day;
                            final shortDay = day.length > 3 ? day.substring(0, 3) : day;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  final set = _closedSlots.putIfAbsent(prefix, () => <String>{});
                                  final key = '${prefix}_$activeType';
                                  final hours = activeType == 'morning' ? _halfDayMorningHours : _halfDayAfternoonHours;

                                  // Eski günü kaldır
                                  if (currentDay != null) {
                                    final oldSlots = hours.map((h) => '${currentDay}_$h').toSet();
                                    set.removeAll(oldSlots);
                                  }

                                  _halfDayAssignedDay[key] = day;
                                  final newSlots = hours.map((h) => '${day}_$h').toSet();

                                  if (isCurrentFlex) {
                                    // Esnek modda gün tercihi olarak kalır, kapalı slota zorlanmaz
                                  } else {
                                    set.addAll(newSlots);
                                  }
                                  if (set.isEmpty) _closedSlots.remove(prefix);
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isDaySelected
                                      ? (isCurrentFlex ? Colors.teal.shade100 : (activeType == 'morning' ? Colors.orange.shade500 : Colors.deepPurple.shade500))
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isDaySelected
                                        ? (isCurrentFlex ? Colors.teal.shade400 : (activeType == 'morning' ? Colors.orange.shade600 : Colors.deepPurple.shade600))
                                        : Colors.grey.shade300,
                                  ),
                                ),
                                child: Text(
                                  shortDay,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isDaySelected ? FontWeight.bold : FontWeight.w500,
                                    color: isDaySelected
                                        ? (isCurrentFlex ? Colors.teal.shade900 : Colors.white)
                                        : Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
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

  Widget _buildMiniSegmentItem({
    required String title,
    required bool isSelected,
    required Color activeBgColor,
    required Color activeTextColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeBgColor : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? activeTextColor : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  /// Öğretmen için günlük yarım gün atama matrisi
  Widget _buildHalfDayAssignMatrix(String prefix) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.amber.shade50, Colors.orange.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wb_sunny_rounded, size: 14, color: Color(0xFFE65100)),
              const SizedBox(width: 6),
              const Text(
                'Yarım Gün İzni',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFE65100)),
              ),
              const SizedBox(width: 8),
              Text('(Sabah/Öğleden Sonra)',
                  style: TextStyle(fontSize: 10, color: Colors.orange.shade700)),
            ],
          ),
          const SizedBox(height: 10),

          // ── Gün Matrisi ──
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _days.map((day) {
                final closedSet = _closedSlots[prefix] ?? {};
                final morningSlots = _halfDayMorningHours.map((h) => '${day}_$h').toSet();
                final afternoonSlots = _halfDayAfternoonHours.map((h) => '${day}_$h').toSet();

                // Fixed: tüm slotlar closedSet'te
                final morningFixed = morningSlots.isNotEmpty &&
                    morningSlots.every((s) => closedSet.contains(s));
                // Esnek tercih: o gün tercih edilmiş ama closedSet'te değil
                final morningFlexPref = _halfDayFlexible.contains('${prefix}_morning') &&
                    _halfDayAssignedDay['${prefix}_morning'] == day;

                final afternoonFixed = afternoonSlots.isNotEmpty &&
                    afternoonSlots.every((s) => closedSet.contains(s));
                final afternoonFlexPref = _halfDayFlexible.contains('${prefix}_afternoon') &&
                    _halfDayAssignedDay['${prefix}_afternoon'] == day;

                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: Column(
                    children: [
                      Text(day.substring(0, 3),
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
                      const SizedBox(height: 6),

                      if (_halfDayMorningHours.isNotEmpty)
                        _buildHalfDayDayButton(
                          label: '🌅',
                          active: morningFixed,
                          isFlexPref: morningFlexPref,
                          activeColor: Colors.orange,
                          onTap: () {
                            setState(() {
                              final set = _closedSlots.putIfAbsent(prefix, () => <String>{});
                              final isAny = morningFixed || morningFlexPref;
                              final isMorningFlexible =
                                  _halfDayFlexible.contains('${prefix}_morning');

                              if (isAny && _halfDayAssignedDay['${prefix}_morning'] == day) {
                                // Deactivate
                                set.removeAll(morningSlots);
                                _halfDayFlexible.remove('${prefix}_morning');
                                _halfDayAssignedDay.remove('${prefix}_morning');
                              } else {
                                // Activate: önce eski günü temizle
                                final oldDay = _halfDayAssignedDay['${prefix}_morning'];
                                if (oldDay != null) {
                                  final oldSlots = _halfDayMorningHours.map((h) => '${oldDay}_$h').toSet();
                                  set.removeAll(oldSlots);
                                }
                                _halfDayAssignedDay['${prefix}_morning'] = day;
                                if (isMorningFlexible) {
                                  // Esnek mod: sadece tercihi kaydet
                                } else {
                                  // Sabit mod: saatleri kapat
                                  set.addAll(morningSlots);
                                }
                              }
                              if (set.isEmpty) _closedSlots.remove(prefix);
                            });
                          },
                        ),

                      if (_halfDayMorningHours.isNotEmpty && _halfDayAfternoonHours.isNotEmpty)
                        const SizedBox(height: 4),

                      if (_halfDayAfternoonHours.isNotEmpty)
                        _buildHalfDayDayButton(
                          label: '🌆',
                          active: afternoonFixed,
                          isFlexPref: afternoonFlexPref,
                          activeColor: Colors.deepPurple,
                          onTap: () {
                            setState(() {
                              final set = _closedSlots.putIfAbsent(prefix, () => <String>{});
                              final isAny = afternoonFixed || afternoonFlexPref;
                              final isAfternoonFlexible =
                                  _halfDayFlexible.contains('${prefix}_afternoon');

                              if (isAny && _halfDayAssignedDay['${prefix}_afternoon'] == day) {
                                set.removeAll(afternoonSlots);
                                _halfDayFlexible.remove('${prefix}_afternoon');
                                _halfDayAssignedDay.remove('${prefix}_afternoon');
                              } else {
                                final oldDay = _halfDayAssignedDay['${prefix}_afternoon'];
                                if (oldDay != null) {
                                  final oldSlots = _halfDayAfternoonHours.map((h) => '${oldDay}_$h').toSet();
                                  set.removeAll(oldSlots);
                                }
                                _halfDayAssignedDay['${prefix}_afternoon'] = day;
                                if (isAfternoonFlexible) {
                                  // Esnek: sadece tercihi kaydet
                                } else {
                                  set.addAll(afternoonSlots);
                                }
                              }
                              if (set.isEmpty) _closedSlots.remove(prefix);
                            });
                          },
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          // ── Esnek Toggle (atama yapıldıysa göster) ──
          Builder(builder: (_) {
            final morningDay = _halfDayAssignedDay['${prefix}_morning'];
            final afternoonDay = _halfDayAssignedDay['${prefix}_afternoon'];
            final morningFlex = _halfDayFlexible.contains('${prefix}_morning');
            final afternoonFlex = _halfDayFlexible.contains('${prefix}_afternoon');

            if (morningDay == null && afternoonDay == null) {
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Gün seçmek için yukarıdaki butonlara tıklayın. Esnek açıksa sistem en uygun günü seçer.',
                  style: TextStyle(fontSize: 10, color: Colors.orange.shade700),
                ),
              );
            }

            return Column(
              children: [
                const SizedBox(height: 10),
                const Divider(height: 1, color: Color(0x25E65100)),
                const SizedBox(height: 8),

                if (morningDay != null)
                  _buildEsnekToggleRow(
                    icon: '🌅',
                    label: 'Sabah',
                    day: morningDay,
                    isFlexible: morningFlex,
                    onToggle: (val) {
                      setState(() {
                        final set = _closedSlots.putIfAbsent(prefix, () => <String>{});
                        final slots = _halfDayMorningHours.map((h) => '${morningDay}_$h').toSet();
                        if (val) {
                          set.removeAll(slots);
                          _halfDayFlexible.add('${prefix}_morning');
                        } else {
                          set.addAll(slots);
                          _halfDayFlexible.remove('${prefix}_morning');
                        }
                        if (set.isEmpty) _closedSlots.remove(prefix);
                      });
                    },
                  ),

                if (afternoonDay != null) ...[
                  if (morningDay != null) const SizedBox(height: 6),
                  _buildEsnekToggleRow(
                    icon: '🌆',
                    label: 'Öğleden Sonra',
                    day: afternoonDay,
                    isFlexible: afternoonFlex,
                    onToggle: (val) {
                      setState(() {
                        final set = _closedSlots.putIfAbsent(prefix, () => <String>{});
                        final slots = _halfDayAfternoonHours.map((h) => '${afternoonDay}_$h').toSet();
                        if (val) {
                          set.removeAll(slots);
                          _halfDayFlexible.add('${prefix}_afternoon');
                        } else {
                          set.addAll(slots);
                          _halfDayFlexible.remove('${prefix}_afternoon');
                        }
                        if (set.isEmpty) _closedSlots.remove(prefix);
                      });
                    },
                  ),
                ],

                const SizedBox(height: 8),
                Text(
                  'Esnek açıksa sistem programı optimize ederken izin gününü değiştirebilir.',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.orange.shade700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildEsnekToggleRow({
    required String icon,
    required String label,
    required String day,
    required bool isFlexible,
    required void Function(bool) onToggle,
  }) {
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFBF360C))),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: isFlexible ? Colors.orange.shade100 : Colors.amber.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isFlexible ? Colors.orange.shade300 : Colors.amber.shade300),
          ),
          child: Text(
            day.length > 3 ? day.substring(0, 3) : day,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isFlexible ? Colors.orange.shade800 : Colors.amber.shade900,
            ),
          ),
        ),
        if (isFlexible)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(Icons.swap_horiz_rounded, size: 14, color: Colors.orange.shade600),
          ),
        const Spacer(),
        Text(
          'Esnek',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isFlexible ? Colors.orange.shade700 : Colors.grey.shade600,
          ),
        ),
        const SizedBox(width: 4),
        Switch.adaptive(
          value: isFlexible,
          onChanged: onToggle,
          activeColor: Colors.orange.shade600,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }

  Widget _buildHalfDayDayButton({
    required String label,
    required bool active,
    bool isFlexPref = false,
    required MaterialColor activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 44,
        height: 38,
        decoration: BoxDecoration(
          color: active
              ? activeColor.shade500
              : isFlexPref
                  ? activeColor.shade100
                  : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? activeColor.shade600
                : isFlexPref
                    ? activeColor.shade400
                    : Colors.grey.shade300,
            width: (active || isFlexPref) ? 2 : 1,
          ),
          boxShadow: active
              ? [BoxShadow(color: activeColor.shade200, blurRadius: 6, offset: const Offset(0, 2))]
              : isFlexPref
                  ? [BoxShadow(color: activeColor.shade100, blurRadius: 4)]
                  : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: const TextStyle(fontSize: 14)),
            if (active)
              Container(
                  width: 6, height: 6,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
            if (isFlexPref && !active)
              Text('≈', style: TextStyle(fontSize: 9, color: activeColor.shade600, height: 0.8)),
          ],
        ),
      ),
    );
  }



  Widget _buildToggle(String label, bool selected, VoidCallback onTap) {

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.red.shade600 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey.shade600,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildPersonList(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          _closedSlotTeacherMode
              ? 'Henüz öğretmen kaydı yok veya yüklenemedi.'
              : 'Henüz şube kaydı yok.',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        final id = item['id'] as String;
        final prefix = _closedSlotTeacherMode ? 'teacher_$id' : 'class_$id';
        final closedCount = _closedSlots[prefix]?.length ?? 0;
        final name = _closedSlotTeacherMode
            ? (item['name'] ??
                    '${item['firstName'] ?? ''} ${item['lastName'] ?? ''}')
                .toString()
                .trim()
            : item['className']?.toString() ?? '';

        return ListTile(
          onTap: () => setState(() => _selectedClosedId = id),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: CircleAvatar(
            backgroundColor:
                closedCount > 0 ? Colors.red.shade100 : Colors.grey.shade100,
            child: Icon(
              _closedSlotTeacherMode
                  ? Icons.person_rounded
                  : Icons.class_rounded,
              color:
                  closedCount > 0 ? Colors.red.shade600 : Colors.grey.shade500,
              size: 18,
            ),
          ),
          title: Text(name,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          trailing: closedCount > 0
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$closedCount kapalı',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        );
      },
    );
  }

  Widget _buildSlotGrid() {
    final id = _selectedClosedId!;
    final prefix = _closedSlotTeacherMode ? 'teacher_$id' : 'class_$id';
    final closed = Set<String>.from(_closedSlots[prefix] ?? <String>{});
    final name = _closedSlotTeacherMode
        ? () {
            final t = _teachers.firstWhere((t) => t['id'] == id,
                orElse: () => <String, dynamic>{});
            return (t['name'] ?? '${t['firstName'] ?? ''} ${t['lastName'] ?? ''}')
                .toString()
                .trim();
          }()
        : _classes
                .firstWhere((c) => c['id'] == id,
                    orElse: () => <String, dynamic>{})['className']
                ?.toString() ??
            '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.red.shade600, Colors.orange.shade600],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _closedSlotTeacherMode
                      ? Icons.person_rounded
                      : Icons.class_rounded,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Yarım Gün Atama Matrisi (sadece öğretmen modunda) ──
          if (_closedSlotTeacherMode &&
              (_halfDayMorningHours.isNotEmpty || _halfDayAfternoonHours.isNotEmpty))
            _buildHalfDayAssignMatrix(prefix),

          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Row(children: [
              Icon(Icons.info_outline_rounded,
                  size: 14, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Kapatmak istediğiniz saatlere tıklayın. 🔴 = Kapalı, 🟢 = Açık',
                  style: TextStyle(fontSize: 11, color: Colors.blue.shade800),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          // ── Slot Grid Tablosu ─────────────────────────────────
          LayoutBuilder(builder: (context, constraints) {
            const labelW = 68.0;
            final availW = constraints.maxWidth - labelW;
            final cellW = _days.isEmpty ? 60.0 : (availW / _days.length).clamp(52.0, 90.0);

            return ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                columnWidths: {
                  0: const FixedColumnWidth(labelW),
                  for (int i = 0; i < _days.length; i++)
                    i + 1: FixedColumnWidth(cellW),
                },
                border: TableBorder(
                  horizontalInside: BorderSide(color: Colors.grey.shade100),
                  verticalInside: BorderSide(color: Colors.grey.shade100),
                ),
                children: [
                  // ── Başlık Satırı ─────────────────────────────
                  TableRow(
                    decoration: BoxDecoration(color: Colors.grey.shade50),
                    children: [
                      Container(
                        height: 44,
                        alignment: Alignment.center,
                        child: Text('Saat',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700)),
                      ),
                      ..._days.map((day) {
                        // Gün için tüm slotlar kapalı mı?
                        final allDaySlots = List.generate(_dailyHours, (h) => '${day}_$h').toSet();
                        final dayClosedSet = _closedSlots[prefix] ?? {};
                        final allClosed = allDaySlots.every((s) => dayClosedSet.contains(s));
                        final someClosed = allDaySlots.any((s) => dayClosedSet.contains(s));
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              final set = _closedSlots.putIfAbsent(prefix, () => <String>{});
                              if (allClosed) {
                                // Tümünü aç
                                set.removeAll(allDaySlots);
                              } else {
                                // Tümünü kapat
                                set.addAll(allDaySlots);
                              }
                              if (set.isEmpty) _closedSlots.remove(prefix);
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            height: 44,
                            decoration: BoxDecoration(
                              color: allClosed
                                  ? Colors.red.shade100
                                  : someClosed
                                      ? Colors.orange.shade50
                                      : Colors.grey.shade50,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  day.length > 3 ? day.substring(0, 3) : day,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: allClosed
                                        ? Colors.red.shade700
                                        : someClosed
                                            ? Colors.orange.shade700
                                            : Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Icon(
                                  allClosed
                                      ? Icons.block_rounded
                                      : someClosed
                                          ? Icons.remove_circle_outline
                                          : Icons.check_circle_outline,
                                  size: 10,
                                  color: allClosed
                                      ? Colors.red.shade500
                                      : someClosed
                                          ? Colors.orange.shade500
                                          : Colors.grey.shade400,
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                  // ── Saat Satırları ───────────────────────────
                  ...List.generate(_dailyHours, (h) {
                    final isEven = h % 2 == 0;
                    return TableRow(
                      decoration: BoxDecoration(
                          color: isEven ? Colors.white : Colors.grey.shade50.withValues(alpha: 0.5)),
                      children: [
                        Container(
                          height: 40,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text('${h + 1}. Ders',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade600)),
                        ),
                        ..._days.map((day) {
                          final slotKey = '${day}_$h';
                          final isClosed = (closed).contains(slotKey);
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                final set = _closedSlots.putIfAbsent(
                                    prefix, () => <String>{});
                                if (isClosed) {
                                  set.remove(slotKey);
                                } else {
                                  set.add(slotKey);
                                }
                                if (set.isEmpty) _closedSlots.remove(prefix);
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              height: 40,
                              decoration: BoxDecoration(
                                color: isClosed
                                    ? Colors.red.shade400
                                    : Colors.green.shade50,
                              ),
                              child: Center(
                                child: Icon(
                                  isClosed
                                      ? Icons.block_rounded
                                      : Icons.check_rounded,
                                  size: 16,
                                  color: isClosed
                                      ? Colors.white
                                      : Colors.green.shade300,
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    );
                  }),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
          // Açıklama
          Row(
            children: [
              _slotLegendChip(Colors.red.shade400, Colors.white, Icons.block_rounded, 'Kapalı'),
              const SizedBox(width: 8),
              _slotLegendChip(Colors.green.shade50, Colors.green.shade300, Icons.check_rounded, 'Açık'),
              const SizedBox(width: 8),
              Text('Gün başlığına tıklayarak tüm günü aç/kapat',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 12),
          if (closed.isNotEmpty)
            TextButton.icon(
              onPressed: () => setState(() => _closedSlots.remove(prefix)),
              icon: const Icon(Icons.lock_open_rounded, size: 16),
              label: const Text('Tüm saatleri aç',
                  style: TextStyle(fontSize: 12)),
              style:
                  TextButton.styleFrom(foregroundColor: Colors.red.shade400),
            ),
        ],
      ),
    );
  }

  Widget _slotLegendChip(Color bg, Color iconColor, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20, height: 20,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
          child: Center(child: Icon(icon, size: 12, color: iconColor)),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildSectionHeader(IconData icon, String title, String sub) {

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.indigo.shade700, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(sub,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTeacherDailyLimitTab() {
    final defaultLimit = _dailyHours > 1 ? _dailyHours - 1 : _dailyHours;
    final filteredTeachers = _teachers.where((t) {
      final name = (t['name'] as String? ?? '').toLowerCase();
      return name.contains(_teacherLimitSearchQuery.toLowerCase());
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            Icons.timelapse_rounded,
            'Öğretmen Günlük Maksimum Ders Limiti',
            'Her öğretmen için bir günde verilebilecek maksimum ders saatini belirleyin. Varsayılan: $defaultLimit saat.',
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (val) => setState(() => _teacherLimitSearchQuery = val),
            decoration: InputDecoration(
              hintText: 'Öğretmen ara...',
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: Colors.grey.shade100,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: filteredTeachers.isEmpty
                ? Center(
                    child: Text(
                      'Öğretmen bulunamadı',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredTeachers.length,
                    itemBuilder: (context, index) {
                      final teacher = filteredTeachers[index];
                      final teacherId = teacher['id'].toString();
                      final name = teacher['name'] as String? ?? 'Öğretmen';
                      final currentLimit = _teacherMaxDailyHours[teacherId] ?? defaultLimit;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.indigo.shade50,
                              child: Icon(Icons.person_rounded, color: Colors.indigo.shade700, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    currentLimit == defaultLimit
                                        ? 'Varsayılan limit ($defaultLimit saat/gün)'
                                        : 'Özel limit ($currentLimit saat/gün)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: currentLimit == defaultLimit ? Colors.grey.shade600 : Colors.indigo.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  color: currentLimit > 1 ? Colors.indigo.shade700 : Colors.grey.shade400,
                                  onPressed: currentLimit > 1
                                      ? () {
                                          setState(() {
                                            _teacherMaxDailyHours[teacherId] = currentLimit - 1;
                                          });
                                        }
                                      : null,
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$currentLimit saat',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Colors.indigo.shade900,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  color: currentLimit < _dailyHours ? Colors.indigo.shade700 : Colors.grey.shade400,
                                  onPressed: currentLimit < _dailyHours
                                      ? () {
                                          setState(() {
                                            _teacherMaxDailyHours[teacherId] = currentLimit + 1;
                                          });
                                        }
                                      : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              size: 16, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, color: Colors.blue.shade800)),
          ),
        ],
      ),
    );
  }
}
