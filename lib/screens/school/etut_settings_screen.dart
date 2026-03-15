import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EtutSettingsScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const EtutSettingsScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<EtutSettingsScreen> createState() => _EtutSettingsScreenState();
}

class _EtutSettingsScreenState extends State<EtutSettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;

  // General Settings
  List<bool> _activeDays = List.generate(7, (index) => true); // Mon-Sun
  int _startHour = 8;
  int _endHour = 20;

  // View Settings
  int _viewInterval = 60; // 60, 30, or 10 minutes

  // Teacher Settings
  List<Map<String, dynamic>> _teachers = [];
  String? _selectedTeacherId;
  Set<String> _teacherUnavailableSlots = {}; // Format: "dayIndex-hour-minute"

  final List<String> _days = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Load General Settings
      final settingsDoc = await FirebaseFirestore.instance
          .collection('etut_settings')
          .doc(widget.institutionId)
          .get();

      if (settingsDoc.exists) {
        final data = settingsDoc.data()!;
        if (data['activeDays'] != null) {
          _activeDays = List<bool>.from(data['activeDays']);
        }
        _startHour = data['startHour'] ?? 8;
        _endHour = data['endHour'] ?? 20;
      }

      // 2. Load Teachers
      final teachersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('type', isEqualTo: 'staff')
          .where('isActive', isEqualTo: true)
          .get();

      _teachers = teachersSnapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .where((t) {
            final title = (t['title'] ?? '').toString().toLowerCase();
            return title == 'ogretmen' || title == 'teacher';
          })
          .toList();

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error loading settings: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTeacherAvailability(String teacherId) async {
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('etut_teacher_availability')
          .doc(teacherId)
          .get();

      _teacherUnavailableSlots.clear();
      if (doc.exists) {
        final data = doc.data()!;
        if (data['unavailableSlots'] != null) {
          final rawSlots = List<String>.from(data['unavailableSlots']);
          // Migrate legacy keys (d-h) to granular keys (d-h-m)
          for (var slot in rawSlots) {
            final parts = slot.split('-');
            if (parts.length == 2) {
              // Legacy format: day-hour. Expand to all 10-min slots for that hour.
              final d = parts[0];
              final h = parts[1];
              for (int m = 0; m < 60; m += 10) {
                _teacherUnavailableSlots.add('$d-$h-$m');
              }
            } else {
              // Correct format: day-hour-minute
              _teacherUnavailableSlots.add(slot);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading teacher availability: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveGeneralSettings() async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection('etut_settings')
          .doc(widget.institutionId)
          .set({
            'activeDays': _activeDays,
            'startHour': _startHour,
            'endHour': _endHour,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Genel ayarlar başarıyla kaydedildi.'),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveTeacherAvailability() async {
    if (_selectedTeacherId == null) return;

    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection('etut_teacher_availability')
          .doc(_selectedTeacherId)
          .set({
            'unavailableSlots': _teacherUnavailableSlots.toList(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Öğretmen kısıtlamaları kaydedildi.'),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Etüt Yapılandırması',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black87),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.indigo,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.indigo,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'Genel Ayarlar'),
            Tab(text: 'Öğretmen Kısıtlamaları'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildGeneralSettingsTab(),
                _buildTeacherSettingsTab(),
              ],
            ),
    );
  }

  Widget _buildGeneralSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          // Days Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.shade100,
                  blurRadius: 10,
                  offset: const Offset(0, 5),
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
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.calendar_today_rounded,
                        color: Colors.indigo.shade700,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Çalışma Günleri',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Aktif günleri seçiniz',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: List.generate(7, (index) {
                    final isSelected = _activeDays[index];
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _activeDays[index] = !isSelected;
                        });
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.indigo : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? Colors.indigo
                                : Colors.grey.shade300,
                            width: 1.5,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: Colors.indigo.withOpacity(0.3),
                                    blurRadius: 6,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : [],
                        ),
                        child: Text(
                          _days[index],
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : Colors.grey.shade700,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Hours Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.shade100,
                  blurRadius: 10,
                  offset: const Offset(0, 5),
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
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.access_time_rounded,
                        color: Colors.orange.shade800,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Çalışma Saatleri',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Günlük zaman aralığını belirleyiniz',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _buildTimeDropdown('Başlangıç', _startHour, (val) {
                        setState(() {
                          _startHour = val!;
                          if (_startHour >= _endHour) _endHour = _startHour + 1;
                        });
                      }),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.only(top: 24),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.grey.shade300,
                        size: 24,
                      ),
                    ),
                    Expanded(
                      child: _buildTimeDropdown('Bitiş', _endHour, (val) {
                        setState(() {
                          _endHour = val!;
                          if (_endHour <= _startHour) _startHour = _endHour - 1;
                        });
                      }),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // Save Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _saveGeneralSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                elevation: 8,
                shadowColor: Colors.indigo.withOpacity(0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'AYARLARI KAYDET',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildTeacherSettingsTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Öğretmen Seçimi',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  hintText: 'Listeden bir öğretmen seçiniz...',
                  prefixIcon: const Icon(
                    Icons.person_search,
                    color: Colors.indigo,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Colors.indigo,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
                value: _selectedTeacherId,
                isExpanded: true,
                items: _teachers.map((t) {
                  return DropdownMenuItem(
                    value: t['id'] as String,
                    child: Text(
                      '${t['fullName']} (${t['branch'] ?? '-'})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedTeacherId = val);
                    _loadTeacherAvailability(val);
                  }
                },
              ),
            ],
          ),
        ),
        if (_selectedTeacherId != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            color: Colors.orange.shade50,
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.orange.shade800,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Kapatmak istediğiniz saatleri işaretleyiniz. Kırmızı kutular "Müsait Değil" anlamına gelir.',
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Interval Selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 60, label: Text("60'")),
                    ButtonSegment(value: 30, label: Text("30'")),
                    ButtonSegment(value: 10, label: Text("10'")),
                  ],
                  selected: {_viewInterval},
                  onSelectionChanged: (Set<int> newSelection) {
                    setState(() {
                      _viewInterval = newSelection.first;
                    });
                  },
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    side: MaterialStateProperty.all(
                      BorderSide(color: Colors.indigo.shade200),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildAvailabilityGrid(),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _saveTeacherAvailability,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline, color: Colors.white),
                    SizedBox(width: 12),
                    Text(
                      'KISITLAMALARI KAYDET',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ] else
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.touch_app_outlined,
                    size: 64,
                    color: Colors.indigo.withOpacity(0.2),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Lütfen önce bir öğretmen seçiniz',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTimeDropdown(
    String label,
    int value,
    ValueChanged<int?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          value: value,
          items: List.generate(24, (index) => index).map((hour) {
            return DropdownMenuItem(
              value: hour,
              child: Text(
                '$hour:00',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildAvailabilityGrid() {
    // Generate time slots based on _viewInterval
    List<Map<String, int>> timeRows = [];
    for (int h = _startHour; h < _endHour; h++) {
      for (int m = 0; m < 60; m += _viewInterval) {
        timeRows.add({'h': h, 'm': m});
      }
    }

    return Column(
      children: [
        // Header
        Row(
          children: [
            const SizedBox(width: 60), // Time column width
            ...List.generate(
              7,
              (index) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _days[index].substring(0, 3),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade900,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
        // Grid
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: timeRows.asMap().entries.map((entry) {
              final rowData = entry.value;
              final h = rowData['h']!;
              final m = rowData['m']!;
              final timeLabel = '$h:${m.toString().padLeft(2, '0')}';

              return Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade100),
                  ),
                  color:
                      (h % 2 ==
                          0) // Alternate color by HOUR, not row index, for grouping effect
                      ? Colors.white
                      : Colors.grey.shade50,
                ),
                child: Row(
                  children: [
                    // Time Label
                    SizedBox(
                      width: 60,
                      height: 40,
                      child: Center(
                        child: Text(
                          timeLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                    // Days
                    ...List.generate(7, (dayIndex) {
                      final isGeneralDayActive = _activeDays[dayIndex];

                      // Check if *all* 10-min slots in this view interval are blocked
                      bool isFullyBlocked = true;
                      bool isPartiallyBlocked = false;

                      for (
                        int offset = 0;
                        offset < _viewInterval;
                        offset += 10
                      ) {
                        final key = '$dayIndex-$h-${m + offset}';
                        if (!_teacherUnavailableSlots.contains(key)) {
                          isFullyBlocked = false;
                        } else {
                          isPartiallyBlocked = true;
                        }
                      }

                      final isFullyDisabled = !isGeneralDayActive;

                      return Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              right: dayIndex < 6
                                  ? BorderSide(
                                      color: Colors.grey.shade300,
                                      width: 0.5,
                                    )
                                  : BorderSide.none,
                            ),
                          ),
                          child: InkWell(
                            onTap: isFullyDisabled
                                ? null
                                : () {
                                    setState(() {
                                      // Toggle Logic
                                      // If currently fully blocked -> Clear all slots in range
                                      // Else (empty or partial) -> Fill all slots in range

                                      bool shouldBlock = !isFullyBlocked;

                                      for (
                                        int offset = 0;
                                        offset < _viewInterval;
                                        offset += 10
                                      ) {
                                        final key =
                                            '$dayIndex-$h-${m + offset}';
                                        if (shouldBlock) {
                                          _teacherUnavailableSlots.add(key);
                                        } else {
                                          _teacherUnavailableSlots.remove(key);
                                        }
                                      }
                                    });
                                  },
                            child: Container(
                              height: 40,
                              margin: const EdgeInsets.all(1),
                              decoration: BoxDecoration(
                                color: isFullyDisabled
                                    ? Colors.grey.shade200
                                    : (isFullyBlocked
                                          ? Colors.red.shade100
                                          : (isPartiallyBlocked
                                                ? Colors.orange.shade50
                                                : Colors.transparent)),
                                borderRadius: BorderRadius.circular(4),
                                border: isFullyBlocked || isPartiallyBlocked
                                    ? Border.all(
                                        color: isFullyBlocked
                                            ? Colors.red.shade300
                                            : Colors.orange.shade200,
                                      )
                                    : null,
                              ),
                              child: isFullyBlocked && !isFullyDisabled
                                  ? Icon(
                                      Icons.close,
                                      color: Colors.red.shade400,
                                      size: 16,
                                    )
                                  : (isPartiallyBlocked && !isFullyDisabled
                                        ? Icon(
                                            Icons.warning_amber_rounded,
                                            color: Colors.orange.shade400,
                                            size: 16,
                                          )
                                        : null),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
