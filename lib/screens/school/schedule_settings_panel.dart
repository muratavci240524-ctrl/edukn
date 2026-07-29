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

  /// List of lesson-specific merge rules:
  /// [{ 'id': '...', 'lessonName': 'Beden Eğitimi', 'weeklyHours': 2, 'classIds': ['801', '802'], 'classNames': ['801', '802'] }]
  final List<Map<String, dynamic>> lessonClassMerges;

  /// key: "teacher_<id>" veya "class_<id>" -> Set<"Pazartesi_0">
  final Map<String, Set<String>> closedSlots;

  /// key: "<teacherId>" -> int (maksimum günlük ders saati)
  final Map<String, int> teacherMaxDailyHours;

  ScheduleSettings({
    required this.lessonBlockPatterns,
    required this.lessonAllowSplit,
    required this.lessonAvoidFirstHour,
    required this.lessonAvoidLastHour,
    required this.lessonClassMerges,
    required this.closedSlots,
    required this.teacherMaxDailyHours,
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

  const ScheduleSettingsPanel({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.periodId,
    required this.periodData,
    required this.initialSettings,
  }) : super(key: key);

  @override
  State<ScheduleSettingsPanel> createState() => _ScheduleSettingsPanelState();
}

class _ScheduleSettingsPanelState extends State<ScheduleSettingsPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── State Variables ────────────────────────────────────────
  Map<String, List<int>> _lessonBlockPatterns = {};
  Map<String, bool> _lessonAllowSplit = {};
  Map<String, bool> _lessonAvoidFirstHour = {};
  Map<String, bool> _lessonAvoidLastHour = {};
  List<Map<String, dynamic>> _lessonClassMerges = [];
  Map<String, Set<String>> _closedSlots = {};
  Map<String, int> _teacherMaxDailyHours = {};

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
    _lessonClassMerges = List.from(widget.initialSettings.lessonClassMerges);
    _closedSlots = Map.fromEntries(
      widget.initialSettings.closedSlots.entries
          .map((e) => MapEntry(e.key, Set<String>.from(e.value))),
    );
    _teacherMaxDailyHours = Map.from(widget.initialSettings.teacherMaxDailyHours);
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
      final termId = widget.periodData['termId'] as String?;

      // 1) Load Classes
      final classSnap = await FirebaseFirestore.instance
          .collection('classes')
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();
      _classes = classSnap.docs.map((d) {
        final data = d.data();
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

      // 2) Load Lesson Assignments & Group by lessonName (lowercase) + weeklyHours
      Query assignQuery = FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true);
      if (termId != null && termId.isNotEmpty) {
        assignQuery = assignQuery.where('termId', isEqualTo: termId);
      }
      final assignSnap = await assignQuery.get();

      final Map<String, Map<String, dynamic>> groupMap = {};
      for (var doc in assignSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final lId = data['lessonId'] as String? ?? '';
        final lName = (data['lessonName'] as String? ?? '').trim();
        final wh = (data['weeklyHours'] as num?)?.toInt() ?? 0;
        final cId = data['classId'] as String? ?? '';
        final cName = data['className'] as String? ?? '';

        // Key: lessonName_lower|weeklyHours  (e.g. "türkçe|7")
        final groupKey = '${lName.toLowerCase()}|$wh';

        if (!groupMap.containsKey(groupKey)) {
          groupMap[groupKey] = {
            'groupKey': groupKey,
            'lessonId': lId,
            'lessonName': lName,
            'weeklyHours': wh,
            'classMap': <String, String>{}, // classId -> className
          };
        }
        final group = groupMap[groupKey]!;
        (group['classMap'] as Map<String, String>)[cId] = cName;
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
          int c = (a['lessonName'] as String).compareTo(b['lessonName'] as String);
          if (c != 0) return c;
          return (b['weeklyHours'] as int).compareTo(a['weeklyHours'] as int);
        });

      // 3) Load Teachers (broad query + lessonAssignments extraction)
      final Map<String, Map<String, dynamic>> teacherMap = {};

      try {
        final usersSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('institutionId', isEqualTo: widget.institutionId)
            .get();

        for (var doc in usersSnap.docs) {
          final data = doc.data();
          final role =
              (data['role'] ?? data['userType'] ?? '').toString().toLowerCase();
          final isTeacher = role.contains('teacher') ||
              role.contains('öğretmen') ||
              role.contains('ogretmen') ||
              role == 'user' ||
              role.isEmpty;

          if (isTeacher) {
            final tId = doc.id;
            final fName = (data['firstName'] ?? data['name'] ?? '').toString();
            final lName = (data['lastName'] ?? '').toString();
            final fullName = '$fName $lName'.trim();
            if (fullName.isNotEmpty) {
              teacherMap[tId] = {
                'id': tId,
                'firstName': fName,
                'lastName': lName,
                'name': fullName,
              };
            }
          }
        }
      } catch (e) {
        debugPrint('Error querying users collection: $e');
      }

      // Also gather teachers assigned in lessonAssignments
      for (var doc in assignSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['teacherIds'] != null &&
            (data['teacherIds'] as List).isNotEmpty) {
          final ids =
              (data['teacherIds'] as List).map((e) => e.toString()).toList();
          final names = (data['teacherNames'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
          for (int i = 0; i < ids.length; i++) {
            final id = ids[i];
            final name = i < names.length ? names[i] : 'Öğretmen';
            if (!teacherMap.containsKey(id) && id.isNotEmpty) {
              teacherMap[id] = {
                'id': id,
                'firstName': name,
                'lastName': '',
                'name': name,
              };
            }
          }
        } else if (data['teacherId'] != null) {
          final id = data['teacherId'].toString();
          final name = (data['teacherName'] ?? 'Öğretmen').toString();
          if (!teacherMap.containsKey(id) && id.isNotEmpty) {
            teacherMap[id] = {
              'id': id,
              'firstName': name,
              'lastName': '',
              'name': name,
            };
          }
        }
      }

      _teachers = teacherMap.values.toList()
        ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

      // 4) Period Days & Daily Hours
      final lessonHoursData =
          widget.periodData['lessonHours'] as Map<String, dynamic>?;
      if (lessonHoursData != null) {
        final counts =
            lessonHoursData['dailyLessonCounts'] as Map<String, dynamic>?;
        if (counts != null && counts.isNotEmpty) {
          _dailyHours = counts.values
              .map((v) => v is int ? v : int.tryParse(v.toString()) ?? 0)
              .reduce((a, b) => a > b ? a : b);
        }
        final sd = lessonHoursData['selectedDays'] as List?;
        if (sd != null && sd.isNotEmpty) {
          _days = sd.map((e) => e.toString()).toList();
        }
      }
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
        lessonClassMerges: _lessonClassMerges,
        closedSlots: _closedSlots,
        teacherMaxDailyHours: _teacherMaxDailyHours,
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
                                final wh = a['weeklyHours'] as int;
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
              child: TabBar(
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
                tabs: const [
                  Tab(
                      icon: Icon(Icons.view_column_rounded, size: 18),
                      text: 'Dağılım'),
                  Tab(
                      icon: Icon(Icons.merge_type_rounded, size: 18),
                      text: 'Birleştir'),
                  Tab(
                      icon: Icon(Icons.block_rounded, size: 18),
                      text: 'Saati Kapat'),
                  Tab(
                      icon: Icon(Icons.timelapse_rounded, size: 18),
                      text: 'Ders Limiti'),
                ],
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
                  onChanged: (v) =>
                      setState(() => _lessonAvoidFirstHour[blockKey] = v),
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
                  onChanged: (v) =>
                      setState(() => _lessonAvoidLastHour[blockKey] = v),
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
              final wh = merge['weeklyHours'] as int;
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
  // SEKME 3: Ders Saati Kapatma (Öğretmen + Şube)
  // ══════════════════════════════════════════════════════════
  Widget _buildClosedSlotsTab() {
    final items = _closedSlotTeacherMode ? _teachers : _classes;
    return Column(
      children: [
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
        const SizedBox(height: 8),
        Expanded(
          child: _selectedClosedId == null
              ? _buildPersonList(items)
              : _buildSlotGrid(),
        ),
      ],
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
              border: TableBorder.all(color: Colors.grey.shade200),
              columnSpacing: 0,
              columns: [
                const DataColumn(
                    label: Text('Saat',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold))),
                ..._days.map((d) => DataColumn(
                      label: Text(d.substring(0, 3),
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold)),
                    )),
              ],
              rows: List.generate(_dailyHours, (h) {
                return DataRow(
                  cells: [
                    DataCell(Text('${h + 1}. Ders',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade700))),
                    ..._days.map((day) {
                      final slotKey = '${day}_$h';
                      final isClosed = closed.contains(slotKey);
                      return DataCell(
                        GestureDetector(
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
                            duration: const Duration(milliseconds: 150),
                            width: 64,
                            height: 36,
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
                        ),
                      );
                    }),
                  ],
                );
              }),
            ),
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
