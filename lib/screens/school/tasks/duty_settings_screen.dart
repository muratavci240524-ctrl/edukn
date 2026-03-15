import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/school/duty_model.dart';

class DutySettingsScreen extends StatefulWidget {
  final String institutionId;
  final String? periodId;

  const DutySettingsScreen({
    Key? key,
    required this.institutionId,
    this.periodId,
  }) : super(key: key);

  @override
  State<DutySettingsScreen> createState() => _DutySettingsScreenState();
}

class _DutySettingsScreenState extends State<DutySettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: const Text(
          'Nöbet Ayarları',
          style: TextStyle(
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF4F46E5),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF4F46E5),
          tabs: const [
            Tab(text: 'Kurallar'),
            Tab(text: 'Nöbet Yerleri'),
            Tab(text: 'Nöbet Havuzu'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildRulesTab(), _buildLocationsTab(), _buildPoolTab()],
      ),
    );
  }

  // --- Rules Tab ---
  Widget _buildRulesTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('dutyRules')
          .where('institutionId', isEqualTo: widget.institutionId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        DutyRules? rules;
        String? docId;
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final doc = snapshot.data!.docs.first;
          rules = DutyRules.fromMap(doc.data() as Map<String, dynamic>);
          docId = doc.id;
        } else {
          rules = DutyRules(institutionId: widget.institutionId);
        }

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nöbet Dagitımı Kuralları',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Nöbet Yerleri Değiştirsin (Rotasyon)'),
                subtitle: const Text(
                  'Aktif edilirse, sistem her hafta öğretmenlerin nöbet yerlerini değiştirmeye çalışır.',
                ),
                value: rules.rotateLocations,
                onChanged: (val) async {
                  final newRules = DutyRules(
                    institutionId: widget.institutionId,
                    rotateLocations: val,
                  );
                  if (docId != null) {
                    await FirebaseFirestore.instance
                        .collection('dutyRules')
                        .doc(docId)
                        .update(newRules.toMap());
                  } else {
                    await FirebaseFirestore.instance
                        .collection('dutyRules')
                        .add(newRules.toMap());
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // --- Locations Tab ---
  Widget _buildLocationsTab() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showLocationDialog(),
        backgroundColor: const Color(0xFF4F46E5),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('dutyLocations')
            .where('institutionId', isEqualTo: widget.institutionId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('Henüz nöbet yeri tanımlanmamış.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final loc = DutyLocation.fromMap(data..['id'] = docs[index].id);
              final activeDays = loc.activeDays..sort();
              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  title: Text(
                    loc.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(_getDaysText(activeDays)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showLocationDialog(location: loc),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteLocation(loc.id),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // --- Pool Tab (Select Eligibility) ---
  Widget _buildPoolTab() {
    return _PoolConfigScreen(institutionId: widget.institutionId);
  }

  // Helper Methods
  Future<void> _showLocationDialog({DutyLocation? location}) async {
    final nameCtrl = TextEditingController(text: location?.name);
    final startCtrl = TextEditingController(text: location?.startTime);
    final endCtrl = TextEditingController(text: location?.endTime);
    final descCtrl = TextEditingController(text: location?.description);
    List<int> selectedDays = location?.activeDays ?? [1, 2, 3, 4, 5];
    bool checkOtherDays = location?.checkOtherDays ?? true;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(location == null ? 'Yeni Nöbet Yeri' : 'Düzenle'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Yer Adı',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Başlangıç (09:00)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: endCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Bitiş (17:00)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Açıklama',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Aktif Günler',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    children: List.generate(7, (index) {
                      final day = index + 1;
                      final isSelected = selectedDays.contains(day);
                      return FilterChip(
                        label: Text(_getDayShortName(day)),
                        selected: isSelected,
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              selectedDays.add(day);
                            } else {
                              selectedDays.remove(day);
                            }
                            selectedDays.sort();
                          });
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text(
                      'Diğer Günlere Dikkat Et',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: const Text(
                      'Aktifse, başka günlerde nöbeti olan öğretmenler turuncu ile gösterilir',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: checkOtherDays,
                    onChanged: (val) {
                      setState(() {
                        checkOtherDays = val;
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Vazgeç'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.isEmpty) return;
                  final col = FirebaseFirestore.instance.collection(
                    'dutyLocations',
                  );

                  final data = {
                    'institutionId': widget.institutionId,
                    'name': nameCtrl.text,
                    'activeDays': selectedDays,
                    'startTime': startCtrl.text,
                    'endTime': endCtrl.text,
                    'description': descCtrl.text,
                    'checkOtherDays': checkOtherDays,
                  };

                  if (location == null) {
                    await col.add(data);
                  } else {
                    await col.doc(location.id).update(data);
                  }
                  if (mounted) Navigator.pop(context);
                },
                child: const Text('Kaydet'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteLocation(String id) async {
    await FirebaseFirestore.instance
        .collection('dutyLocations')
        .doc(id)
        .delete();
  }

  String _getDaysText(List<int> days) {
    if (days.isEmpty) return 'Gün seçilmemiş';
    final dayNames = ['', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    return days.map((d) => dayNames[d]).join(', ');
  }

  String _getDayShortName(int day) {
    const dayNames = ['', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    return dayNames[day];
  }
}

class _PoolConfigScreen extends StatefulWidget {
  final String institutionId;
  const _PoolConfigScreen({Key? key, required this.institutionId})
    : super(key: key);

  @override
  State<_PoolConfigScreen> createState() => _PoolConfigScreenState();
}

class _PoolConfigScreenState extends State<_PoolConfigScreen> {
  int _selectedDay = 1; // 1=Mon

  @override
  Widget build(BuildContext context) {
    final dayNames = [
      '',
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];

    return Column(
      children: [
        // Day Selector
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: List.generate(7, (index) {
              final day = index + 1;
              final isSelected = day == _selectedDay;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(dayNames[day]),
                  selected: isSelected,
                  onSelected: (val) {
                    if (val) setState(() => _selectedDay = day);
                  },
                ),
              );
            }),
          ),
        ),

        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('dutyLocations')
                .where('institutionId', isEqualTo: widget.institutionId)
                .snapshots(),
            builder: (context, locSnap) {
              if (locSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final allLocs = (locSnap.data?.docs ?? []).map((d) {
                final data = d.data() as Map<String, dynamic>;
                data['id'] = d.id;
                return DutyLocation.fromMap(data);
              }).toList();

              // Filter by Active Day
              final activeLocs = allLocs
                  .where((l) => l.activeDays.contains(_selectedDay))
                  .toList();

              if (activeLocs.isEmpty) {
                return Center(
                  child: Text(
                    '${dayNames[_selectedDay]} günün aktif nöbet yeri yok.',
                  ),
                );
              }

              // No secondary stream needed since data is inside DutyLocation now
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: activeLocs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final loc = activeLocs[index];
                  // Read from internal map: Key is string of dayOfWeek
                  final eligibleIds =
                      loc.eligibilities[_selectedDay.toString()] ?? [];

                  // Construct a dummy DutyEligibility to pass to dialog/copy logic
                  final elig = DutyEligibility(
                    id: loc.id, // Not used much, but can track loc ID
                    institutionId: widget.institutionId,
                    locationId: loc.id,
                    dayOfWeek: _selectedDay,
                    eligibleTeacherIds: eligibleIds,
                  );

                  return Card(
                    child: ListTile(
                      title: Text(
                        loc.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('${eligibleIds.length} öğretmen seçili'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.copy, color: Colors.orange),
                            tooltip: 'Bu listeyi diğer yerlere kopyala',
                            onPressed: () => _copyToOtherLocations(
                              elig,
                              loc.name,
                              activeLocs,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _showSelectionDialog(loc, elig),
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
    );
  }

  Future<void> _showSelectionDialog(
    DutyLocation loc,
    DutyEligibility? current,
  ) async {
    // Fetch all potential candidates (teachers, staff, admins)
    final userSnap = await FirebaseFirestore.instance
        .collection('users')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('type', whereIn: ['teacher', 'staff', 'admin'])
        .get();

    final allUsers = userSnap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();

    // Get active period to fetch schedules
    final periodSnapshot = await FirebaseFirestore.instance
        .collection('workPeriods')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('isActive', isEqualTo: true)
        .get();

    String? periodId;
    if (periodSnapshot.docs.isNotEmpty) {
      periodId = periodSnapshot.docs.first.id;
    }

    // Get day name
    final dayNames = [
      '',
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];
    final dayName = dayNames[_selectedDay];

    // Fetch all teachers' schedules for this day
    Map<String, int> teacherLessonCounts = {};
    if (periodId != null) {
      final scheduleSnap = await FirebaseFirestore.instance
          .collection('classSchedules')
          .where('periodId', isEqualTo: periodId)
          .where('day', isEqualTo: dayName)
          .where('isActive', isEqualTo: true)
          .get();

      for (var doc in scheduleSnap.docs) {
        final data = doc.data();
        final tId = data['teacherId'];
        final tIds = data['teacherIds'];

        if (tId != null && tId.toString().isNotEmpty) {
          teacherLessonCounts[tId.toString()] =
              (teacherLessonCounts[tId.toString()] ?? 0) + 1;
        }
        if (tIds is List) {
          for (var id in tIds) {
            if (id != null) {
              teacherLessonCounts[id.toString()] =
                  (teacherLessonCounts[id.toString()] ?? 0) + 1;
            }
          }
        }
      }
    }

    // Get all locations to check if teacher is assigned to other days
    final allLocations = await FirebaseFirestore.instance
        .collection('dutyLocations')
        .where('institutionId', isEqualTo: widget.institutionId)
        .get();

    // Check which teachers are assigned to other days
    Set<String> teachersInOtherDays = {};
    for (var locDoc in allLocations.docs) {
      final locData = locDoc.data();
      final eligibilities = locData['eligibilities'] as Map<String, dynamic>?;
      if (eligibilities != null) {
        for (var dayKey in eligibilities.keys) {
          if (dayKey != _selectedDay.toString()) {
            final teacherIds = eligibilities[dayKey] as List?;
            if (teacherIds != null) {
              teachersInOtherDays.addAll(teacherIds.map((e) => e.toString()));
            }
          }
        }
      }
    }

    // Sort users: by lesson count (ascending), then by whether they're in other days
    allUsers.sort((a, b) {
      final aId = a['id'] as String;
      final bId = b['id'] as String;

      final aLessons = teacherLessonCounts[aId] ?? 0;
      final bLessons = teacherLessonCounts[bId] ?? 0;

      final aInOtherDays = teachersInOtherDays.contains(aId);
      final bInOtherDays = teachersInOtherDays.contains(bId);

      // First sort by lesson count (ascending - fewer lessons first)
      if (aLessons != bLessons) {
        return aLessons.compareTo(bLessons);
      }

      // Then by whether they're in other days (not in other days first)
      if (aInOtherDays != bInOtherDays) {
        return aInOtherDays ? 1 : -1;
      }

      // Finally by name
      final nameA = (a['fullName'] ?? a['name'] ?? '').toString();
      final nameB = (b['fullName'] ?? b['name'] ?? '').toString();
      return nameA.compareTo(nameB);
    });

    List<String> selectedIds = List.from(current?.eligibleTeacherIds ?? []);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.9,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollController) {
              return Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${loc.name} - Personel Seçimi',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            await _saveEligibility(
                              loc.id,
                              selectedIds,
                              null, // Doc ID irrelevant now
                            );
                            if (mounted) Navigator.pop(context);
                          },
                          child: const Text(
                            'Kaydet',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        TextField(
                          decoration: InputDecoration(
                            hintText: 'Personel Ara...',
                            prefixIcon: const Icon(
                              Icons.search,
                              color: Colors.grey,
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 0,
                            ),
                          ),
                          onChanged: (val) {
                            // Search logic visual only for now
                            // Ideally filter `allUsers` manually here
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              '${selectedIds.length} kişi seçildi',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  selectedIds = allUsers
                                      .map((u) => u['id'] as String)
                                      .toList();
                                });
                              },
                              child: const Text('Tümünü Seç'),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  selectedIds.clear();
                                });
                              },
                              child: const Text('Temizle'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: allUsers.length,
                      itemBuilder: (context, index) {
                        final u = allUsers[index];
                        final uId = u['id'] as String;
                        final uName = u['fullName'] ?? u['name'] ?? 'İsimsiz';
                        final isSelected = selectedIds.contains(uId);
                        final isInOtherDays = teachersInOtherDays.contains(uId);
                        final lessonCount = teacherLessonCounts[uId] ?? 0;

                        // Get branch information
                        String branch = 'Öğretmen';
                        if (u['branches'] is List &&
                            (u['branches'] as List).isNotEmpty) {
                          branch = (u['branches'] as List).first.toString();
                        } else if (u['branch'] is String &&
                            (u['branch'] as String).isNotEmpty) {
                          branch = u['branch'];
                        }

                        // Determine colors - only show warning if checkOtherDays is enabled
                        Color tileColor = Colors.white;
                        Color avatarBgColor;
                        Color avatarTextColor;
                        bool showWarning = loc.checkOtherDays && isInOtherDays;

                        if (showWarning) {
                          // Teacher assigned to another day - orange warning
                          tileColor = Colors.orange.shade50;
                          avatarBgColor = isSelected
                              ? const Color(0xFF4F46E5)
                              : Colors.orange.shade100;
                          avatarTextColor = isSelected
                              ? Colors.white
                              : Colors.orange.shade800;
                        } else {
                          avatarBgColor = isSelected
                              ? const Color(0xFF4F46E5)
                              : Colors.grey.shade200;
                          avatarTextColor = isSelected
                              ? Colors.white
                              : Colors.black87;
                        }

                        return Container(
                          color: tileColor,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: avatarBgColor,
                              child: Text(
                                uName.isNotEmpty
                                    ? uName.substring(0, 1).toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: avatarTextColor,
                                  fontWeight: showWarning
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            title: Text(
                              uName,
                              style: TextStyle(
                                fontWeight: showWarning
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              '$branch ($lessonCount ders)',
                              style: TextStyle(
                                fontSize: 12,
                                color: showWarning
                                    ? Colors.orange.shade700
                                    : Colors.grey,
                                fontWeight: showWarning
                                    ? FontWeight.w500
                                    : FontWeight.normal,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (showWarning)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Icon(
                                      Icons.warning_amber_rounded,
                                      color: Colors.orange.shade700,
                                      size: 20,
                                    ),
                                  ),
                                Checkbox(
                                  value: isSelected,
                                  activeColor: const Color(0xFF4F46E5),
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        selectedIds.add(uId);
                                      } else {
                                        selectedIds.remove(uId);
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  selectedIds.remove(uId);
                                } else {
                                  selectedIds.add(uId);
                                }
                              });
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _saveEligibility(
    String locId,
    List<String> teacherIds,
    String? docId,
  ) async {
    // Save to DutyLocation doc inside "eligibilities" map
    final docRef = FirebaseFirestore.instance
        .collection('dutyLocations')
        .doc(locId);

    // Key needs to be stringified int
    final dayKey = _selectedDay.toString();

    await docRef.update({'eligibilities.$dayKey': teacherIds});
  }

  Future<void> _copyToOtherLocations(
    DutyEligibility? source,
    String sourceName,
    List<DutyLocation> allLocs,
  ) async {
    if (source == null || source.eligibleTeacherIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Kopyalanacak liste boş.')));
      return;
    }

    final possibleTargets = allLocs
        .where((l) => l.id != source.locationId)
        .toList();

    if (possibleTargets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kopyalanacak başka yer yok.')),
      );
      return;
    }

    // Default: Select all
    List<String> selectedTargetIds = possibleTargets.map((e) => e.id).toList();

    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('$sourceName Kopyala'),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: Column(
                children: [
                  const Text(
                    'Bu öğretmen listesini hangi yerlere kopyalamak istersiniz?',
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            if (selectedTargetIds.length ==
                                possibleTargets.length) {
                              selectedTargetIds.clear();
                            } else {
                              selectedTargetIds = possibleTargets
                                  .map((e) => e.id)
                                  .toList();
                            }
                          });
                        },
                        child: Text(
                          selectedTargetIds.length == possibleTargets.length
                              ? 'Seçimi Kaldır'
                              : 'Tümünü Seç',
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: possibleTargets.length,
                      itemBuilder: (context, index) {
                        final t = possibleTargets[index];
                        final isSelected = selectedTargetIds.contains(t.id);
                        return CheckboxListTile(
                          title: Text(t.name),
                          value: isSelected,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                selectedTargetIds.add(t.id);
                              } else {
                                selectedTargetIds.remove(t.id);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('iptal'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, selectedTargetIds);
                },
                child: const Text('Kopyala'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null && result.isNotEmpty) {
      // Update selected target locations
      final batch = FirebaseFirestore.instance.batch();
      final dayKey = _selectedDay.toString();

      for (var targetId in result) {
        final docRef = FirebaseFirestore.instance
            .collection('dutyLocations')
            .doc(targetId);
        batch.update(docRef, {
          'eligibilities.$dayKey': source.eligibleTeacherIds,
        });
      }
      await batch.commit();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.length} yere kopyalandı.')),
      );
    }
  }
}
