import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/term_service.dart';
import 'etut_settings_screen.dart';

class EtutProcessScreen extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const EtutProcessScreen({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<EtutProcessScreen> createState() => _EtutProcessScreenState();
}

class _EtutProcessScreenState extends State<EtutProcessScreen> {
  // Data Lists
  List<Map<String, dynamic>> _allStudents = [];
  List<Map<String, dynamic>> _allTeachers = [];

  // Selection
  Set<String> _selectedStudentIds = {};
  String? _selectedTeacherId;

  // Filters
  String _studentSearch = '';
  String _teacherSearch = '';
  String? _selectedClassFilter;
  String? _selectedBranchFilter;

  bool _isLoading = true;
  DateTime _focusedDate = DateTime.now();

  // Clash Data
  Map<String, dynamic> _clashData = {};
  String? _schoolId;

  // Settings
  List<bool> _activeDays = List.generate(7, (index) => true);
  int _startHour = 8;
  int _endHour = 20;
  Set<String> _currentTeacherUnavailableSlots = {}; // Format: "dayIndex-hour"

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('etut_settings')
          .doc(widget.institutionId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        if (mounted) {
          setState(() {
            if (data['activeDays'] != null) {
              _activeDays = List<bool>.from(data['activeDays']);
            }
            _startHour = data['startHour'] ?? 8;
            _endHour = data['endHour'] ?? 20;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading etut settings: $e');
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await _loadSettings();
    try {
      final reqs = await Future.wait([
        FirebaseFirestore.instance
            .collection('students')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
            .where('isActive', isEqualTo: true)
            .get(),
        FirebaseFirestore.instance
            .collection('users')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('type', isEqualTo: 'staff')
            .where('isActive', isEqualTo: true)
            .get(),
        FirebaseFirestore.instance
            .collection('schools')
            .where('institutionId', isEqualTo: widget.institutionId)
            .limit(1)
            .get(),
      ]);

      _allStudents = reqs[0].docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();
      _allTeachers = reqs[1].docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .where((t) {
            final title = (t['title'] ?? '').toString().toLowerCase();
            return title == 'ogretmen' || title == 'teacher';
          })
          .toList();

      if (reqs[2].docs.isNotEmpty) {
        _schoolId = reqs[2].docs.first.id;
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error loading etut data: $e');
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredStudents {
    return _allStudents.where((s) {
      final name = (s['fullName'] ?? '').toString().toLowerCase();
      final matchesSearch = name.contains(_studentSearch.toLowerCase());
      final matchesClass =
          _selectedClassFilter == null ||
          s['className'] == _selectedClassFilter;
      return matchesSearch && matchesClass;
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredTeachers {
    return _allTeachers.where((t) {
      final name = (t['fullName'] ?? '').toString().toLowerCase();
      final branch = (t['branch'] ?? '').toString().toLowerCase();
      final matchesSearch =
          name.contains(_teacherSearch.toLowerCase()) ||
          branch.contains(_teacherSearch.toLowerCase());
      final matchesBranch =
          _selectedBranchFilter == null || t['branch'] == _selectedBranchFilter;
      return matchesSearch && matchesBranch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: false,
        leading: const BackButton(color: Colors.indigo),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Etüt İşlemleri',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              widget.schoolTypeName,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.indigo),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EtutSettingsScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                  ),
                ),
              );
              _loadSettings();
              _loadClashData();
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                // WEB & DESKTOP: 3 Column Layout
                if (constraints.maxWidth >= 1024) {
                  return Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Column: Student List
                        Container(
                          width: 300,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: _buildStudentPanel(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Middle Column: Calendar
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.02),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _buildCalendarPanel(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Right Column: Teacher List
                        Container(
                          width: 300,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: _buildTeacherPanel(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // MOBILE & TABLET: Original Stacked Layout
                return Column(
                  children: [
                    // Top Sections: Student & Teacher Selection
                    Container(
                      height: 320, // Approx 5-6 rows + search
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(child: _buildStudentPanel()),
                          const VerticalDivider(width: 24, thickness: 1),
                          Expanded(child: _buildTeacherPanel()),
                        ],
                      ),
                    ),
                    // Bottom Section: Calendar
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: _buildCalendarPanel(),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildStudentPanel() {
    return Column(
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
              child: Icon(
                Icons.school,
                color: Colors.indigo.shade700,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Öğrenci Seçimi',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14, // Slightly smaller
                  color: Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_selectedStudentIds.isNotEmpty)
              InkWell(
                onTap: () {
                  setState(() {
                    _selectedStudentIds.clear();
                    _clashData = {};
                  });
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(
                    Icons.cleaning_services_rounded,
                    size: 18,
                    color: Colors.red.shade400,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: InputDecoration(
            hintText: 'Öğrenci Ara...',
            prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 8,
              horizontal: 10,
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: (v) => setState(() => _studentSearch = v),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: _filteredStudents.length,
            itemBuilder: (context, index) {
              final s = _filteredStudents[index];
              final isSelected = _selectedStudentIds.contains(s['id']);
              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.indigo.shade50
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? Border.all(color: Colors.indigo.shade100)
                      : null,
                ),
                child: ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 0,
                  ),
                  leading: CircleAvatar(
                    radius: 12,
                    backgroundColor: isSelected
                        ? Colors.indigo
                        : Colors.grey.shade200,
                    child: Text(
                      (s['fullName'] ?? '?')[0],
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey.shade700,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    s['fullName'] ?? 'İsimsiz',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: isSelected
                          ? Colors.indigo.shade900
                          : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    s['className'] ?? 'Sınıfsız',
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected ? Colors.indigo.shade400 : Colors.grey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    // Optimistic update: Don't trigger full loading overlay
                    setState(() {
                      if (isSelected) {
                        _selectedStudentIds.remove(s['id']);
                      } else {
                        _selectedStudentIds.add(s['id']);
                      }
                    });
                    _loadClashData(silent: true); // Load data silently
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTeacherPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.person,
                color: Colors.orange.shade700,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Öğretmen Seçimi',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_selectedTeacherId != null)
              InkWell(
                onTap: () {
                  setState(() {
                    _selectedTeacherId = null;
                    _currentTeacherUnavailableSlots = {};
                    _clashData = {};
                  });
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(
                    Icons.cleaning_services_rounded,
                    size: 18,
                    color: Colors.orange.shade400,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: InputDecoration(
            hintText: 'Öğretmen / Branş...',
            prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 8,
              horizontal: 10,
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: (v) => setState(() => _teacherSearch = v),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: _filteredTeachers.length,
            itemBuilder: (context, index) {
              final t = _filteredTeachers[index];
              final isSelected = _selectedTeacherId == t['id'];
              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.orange.shade50
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? Border.all(color: Colors.orange.shade200)
                      : null,
                ),
                child: ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 0,
                  ),
                  leading: CircleAvatar(
                    radius: 12,
                    backgroundColor: isSelected
                        ? Colors.orange
                        : Colors.grey.shade200,
                    child: Icon(
                      Icons.person,
                      size: 12,
                      color: isSelected ? Colors.white : Colors.grey.shade700,
                    ),
                  ),
                  title: Text(
                    t['fullName'] ?? 'Öğretmen',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: isSelected
                          ? Colors.orange.shade900
                          : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    t['branch'] ?? 'Branş',
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected ? Colors.orange.shade700 : Colors.grey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    setState(() {
                      _selectedTeacherId = isSelected
                          ? null
                          : t['id'] as String;
                    });
                    _loadClashData(silent: true);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _normalizeDay(String? day) {
    if (day == null) return '';
    return day.toLowerCase().replaceAll('ı', 'i').replaceAll('İ', 'i').trim();
  }

  Future<void> _loadClashData({bool silent = false}) async {
    if (_selectedStudentIds.isEmpty && _selectedTeacherId == null) {
      // Even if no selection, we might want to clear clashes but keep settings active.
      // But availability is only relevant for teachers.
      setState(() {
        _clashData = {};
        _currentTeacherUnavailableSlots = {};
      });
      return;
    }

    if (!silent) {
      setState(() => _isLoading = true);
    }

    // Load Teacher Unavailability if a teacher is selected
    if (_selectedTeacherId != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('etut_teacher_availability')
            .doc(_selectedTeacherId)
            .get();
        if (doc.exists && doc.data()!['unavailableSlots'] != null) {
          _currentTeacherUnavailableSlots = Set<String>.from(
            doc.data()!['unavailableSlots'],
          );
        } else {
          _currentTeacherUnavailableSlots = {};
        }
      } catch (e) {
        debugPrint('Error loading teacher avail: $e');
        _currentTeacherUnavailableSlots = {};
      }
    } else {
      _currentTeacherUnavailableSlots = {};
    }

    try {
      final termId = await TermService().getActiveTermId();

      // 1. Get Active Work Periods
      var query = FirebaseFirestore.instance
          .collection('workPeriods')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true);

      if (termId != null) {
        query = query.where('termId', isEqualTo: termId);
      }

      final periodsSnapshot = await query.get();

      if (periodsSnapshot.docs.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final periodDocs = periodsSnapshot.docs.toList();
      periodDocs.sort((a, b) {
        final dataA = a.data();
        final dataB = b.data();
        final isPubA =
            (dataA['schedulePublished'] == true || dataA['isPublished'] == true)
            ? 1
            : 0;
        final isPubB =
            (dataB['schedulePublished'] == true || dataB['isPublished'] == true)
            ? 1
            : 0;
        if (isPubA != isPubB) return isPubB.compareTo(isPubA);
        final endA = dataA['endDate']?.toString() ?? '';
        final endB = dataB['endDate']?.toString() ?? '';
        return endB.compareTo(endA);
      });

      final periodDoc = periodDocs.first;
      final periodId = periodDoc.id;
      final periodData = periodDoc.data();
      final lessonHours = periodData['lessonHours'] as Map<String, dynamic>?;

      Map<String, int> indexToHourMap = {};
      if (lessonHours != null && lessonHours['lessonTimes'] != null) {
        final lessonTimesRaw = lessonHours['lessonTimes'];
        final selectedDays = List<String>.from(
          lessonHours['selectedDays'] ?? [],
        );

        if (lessonTimesRaw is Map) {
          final firstKey = lessonTimesRaw.keys.first;
          if (int.tryParse(firstKey) != null) {
            lessonTimesRaw.forEach((key, value) {
              final idx = int.tryParse(key);
              if (idx != null && value is Map) {
                for (var day in selectedDays) {
                  indexToHourMap['${_normalizeDay(day)}-$idx'] =
                      value['startHour'] ?? 0;
                }
              }
            });
          } else {
            lessonTimesRaw.forEach((day, dayData) {
              if (dayData is List) {
                for (int i = 0; i < dayData.length; i++) {
                  final value = dayData[i];
                  if (value is Map) {
                    indexToHourMap['${_normalizeDay(day)}-$i'] =
                        value['startHour'] ?? 0;
                  }
                }
              }
            });
          }
        } else if (lessonTimesRaw is List) {
          for (int i = 0; i < lessonTimesRaw.length; i++) {
            final value = lessonTimesRaw[i];
            if (value is Map) {
              for (var day in selectedDays) {
                indexToHourMap['${_normalizeDay(day)}-$i'] =
                    value['startHour'] ?? 0;
              }
            }
          }
        }
      }

      Map<String, List<Map<String, dynamic>>> newClashData = {};

      void addClash(
        String key,
        String type, {
        String? label,
        Map<String, dynamic>? details,
      }) {
        newClashData.putIfAbsent(key, () => []);
        newClashData[key]!.add({
          'type': type,
          'label': label,
          'details': details,
        });
      }

      // 3. Get Student Class Schedules
      if (_selectedStudentIds.isNotEmpty) {
        final studentClasses = _allStudents
            .where((s) => _selectedStudentIds.contains(s['id']))
            .map((s) => s['classId'] as String?)
            .whereType<String>()
            .toSet();

        final classIdList = studentClasses.toList();
        if (classIdList.isNotEmpty) {
          for (var i = 0; i < classIdList.length; i += 30) {
            final chunk = classIdList.skip(i).take(30).toList();
            final snap = await FirebaseFirestore.instance
                .collection('classSchedules')
                .where('institutionId', isEqualTo: widget.institutionId)
                .where('periodId', isEqualTo: periodId)
                .where('classId', whereIn: chunk)
                .where('isActive', isEqualTo: true)
                .get();
            for (var doc in snap.docs) {
              final data = doc.data();
              final day = data['day']?.toString();
              final lessonIdx = data['hourIndex'] as int?;
              final lessonName = data['lessonName']?.toString() ?? 'Ders';
              if (day != null && lessonIdx != null) {
                final startHour =
                    indexToHourMap['${_normalizeDay(day)}-$lessonIdx'];
                if (startHour != null) {
                  final gridStartSlot = (startHour - 8) * 6;
                  // Standard lesson duration: 4 slots (40 minutes)
                  for (int j = 0; j < 4; j++) {
                    addClash(
                      '${_normalizeDay(day)}-${gridStartSlot + j}',
                      'ST',
                      label: lessonName,
                      details: {'type': 'Lesson', 'id': doc.id, ...data},
                    );
                  }
                }
              }
            }
          }
        }
      }

      // 4. Get Teacher Schedule
      if (_selectedTeacherId != null) {
        final teacherQueries = await Future.wait([
          FirebaseFirestore.instance
              .collection('classSchedules')
              .where('institutionId', isEqualTo: widget.institutionId)
              .where('periodId', isEqualTo: periodId)
              .where('teacherId', isEqualTo: _selectedTeacherId)
              .where('isActive', isEqualTo: true)
              .get(),
          FirebaseFirestore.instance
              .collection('classSchedules')
              .where('institutionId', isEqualTo: widget.institutionId)
              .where('periodId', isEqualTo: periodId)
              .where('teacherIds', arrayContains: _selectedTeacherId)
              .where('isActive', isEqualTo: true)
              .get(),
        ]);

        for (final snap in teacherQueries) {
          for (var doc in snap.docs) {
            final data = doc.data();
            final day = data['day']?.toString();
            final lessonIdx = data['hourIndex'] as int?;
            final className = data['className']?.toString() ?? 'Sınıf';
            if (day != null && lessonIdx != null) {
              final startHour =
                  indexToHourMap['${_normalizeDay(day)}-$lessonIdx'];
              if (startHour != null) {
                final gridStartSlot = (startHour - 8) * 6;
                // Standard lesson duration: 4 slots (40 minutes)
                for (int j = 0; j < 4; j++) {
                  addClash(
                    '${_normalizeDay(day)}-${gridStartSlot + j}',
                    'TR',
                    label: className,
                    details: {'type': 'Lesson', 'id': doc.id, ...data},
                  );
                }
              }
            }
          }
        }
      }

      // 5. Get Etüt Requests
      try {
        final rawStartOfWeek = _focusedDate.subtract(
          Duration(days: _focusedDate.weekday - 1),
        );
        final startOfWeek = DateTime(
          rawStartOfWeek.year,
          rawStartOfWeek.month,
          rawStartOfWeek.day,
        );
        final endOfWeek = startOfWeek.add(const Duration(days: 7));
        final startTs = Timestamp.fromDate(startOfWeek);
        final endTs = Timestamp.fromDate(endOfWeek);

        final etutQueries = <Future<QuerySnapshot>>[];
        if (_selectedTeacherId != null) {
          etutQueries.add(
            FirebaseFirestore.instance
                .collection('etut_requests')
                .where('institutionId', isEqualTo: widget.institutionId)
                .where('teacherId', isEqualTo: _selectedTeacherId)
                .where('date', isGreaterThanOrEqualTo: startTs)
                .where('date', isLessThan: endTs)
                .get(),
          );
        }
        if (_selectedStudentIds.isNotEmpty) {
          final studentIdList = _selectedStudentIds.toList();
          for (var i = 0; i < studentIdList.length; i += 10) {
            final chunk = studentIdList.skip(i).take(10).toList();
            etutQueries.add(
              FirebaseFirestore.instance
                  .collection('etut_requests')
                  .where('institutionId', isEqualTo: widget.institutionId)
                  .where('studentIds', arrayContainsAny: chunk)
                  .where('date', isGreaterThanOrEqualTo: startTs)
                  .where('date', isLessThan: endTs)
                  .get(),
            );
          }
        }

        final etutSnaps = await Future.wait(etutQueries);
        const daysTr = [
          'Pazartesi',
          'Salı',
          'Çarşamba',
          'Perşembe',
          'Cuma',
          'Cumartesi',
          'Pazar',
        ];

        for (final snap in etutSnaps) {
          for (var doc in snap.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final dateVal = data['date'];
            final startVal = data['startTime'];
            final endVal = data['endTime'];

            if (dateVal != null) {
              DateTime? date;
              if (dateVal is Timestamp)
                date = dateVal.toDate();
              else if (dateVal is String)
                date = DateTime.tryParse(dateVal);

              if (date != null) {
                final dayName = _normalizeDay(daysTr[date.weekday - 1]);
                final isTeacherEtut = data['teacherId'] == _selectedTeacherId;
                final etutStudentIds = List<String>.from(
                  data['studentIds'] ?? [],
                );
                final isStudentEtut = _selectedStudentIds.any(
                  (id) => etutStudentIds.contains(id),
                );

                String type = 'NONE';
                if (isTeacherEtut && isStudentEtut)
                  type = 'BOTH';
                else if (isTeacherEtut)
                  type = 'TR';
                else if (isStudentEtut)
                  type = 'ST';

                if (type == 'NONE') continue;

                if (startVal is Timestamp && endVal is Timestamp) {
                  final s = startVal.toDate();
                  final e = endVal.toDate();
                  int startMin = (s.hour - 8) * 60 + s.minute;
                  int endMin = (e.hour - 8) * 60 + e.minute;
                  int startSlot = (startMin / 10).floor();
                  int endSlot = (endMin / 10).ceil();
                  for (int slot = startSlot; slot < endSlot; slot++) {
                    if (slot >= 0 && slot < 84) {
                      addClash(
                        '$dayName-$slot',
                        type,
                        label: 'ETÜT',
                        details: {'type': 'Etut', 'id': doc.id, ...data},
                      );
                    }
                  }
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading etut clash data: $e');
      }

      setState(() {
        _clashData = newClashData;
        _isLoading = false;
      });
    } catch (e, stack) {
      debugPrint('Error loading clash data: $e\n$stack');
      setState(() => _isLoading = false);
    }
  }

  Widget _buildCalendarPanel() {
    return Column(
      children: [
        _buildCalendarHeader(),
        _buildDaysHeader(),
        Expanded(
          child: SingleChildScrollView(
            child: SizedBox(
              height: (_endHour - _startHour) * 120.0 + 50,
              child: _buildTimeGrid(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarHeader() {
    final startOfWeek = _focusedDate.subtract(
      Duration(days: _focusedDate.weekday - 1),
    );
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Text(
            '${DateFormat('d MMMM', 'tr').format(startOfWeek)} - ${DateFormat('d MMMM yyyy', 'tr').format(endOfWeek)}',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(
              () =>
                  _focusedDate = _focusedDate.subtract(const Duration(days: 7)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(
              () => _focusedDate = _focusedDate.add(const Duration(days: 7)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDaysHeader() {
    final days = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    final startOfWeek = _focusedDate.subtract(
      Duration(days: _focusedDate.weekday - 1),
    );
    return Container(
      padding: const EdgeInsets.only(left: 60),
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: List.generate(7, (i) {
          final date = startOfWeek.add(Duration(days: i));
          final isToday = DateUtils.isSameDay(date, DateTime.now());
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  days[i],
                  style: TextStyle(
                    color: isToday ? Colors.indigo : Colors.grey,
                    fontSize: 12,
                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isToday ? Colors.indigo : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    DateFormat('d').format(date),
                    style: TextStyle(
                      color: isToday ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTimeGrid() {
    const daysTr = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];
    return Row(
      children: [
        // Hours Column
        Column(
          children: List.generate(_endHour - _startHour, (i) {
            final hour = _startHour + i;
            return Container(
              height: 120,
              width: 60,
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade300, width: 1.5),
                ),
              ),
              child: Text(
                '$hour:00',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          }),
        ),
        // Days Columns
        Expanded(
          child: Row(
            children: List.generate(7, (dayIndex) {
              final dayName = _normalizeDay(daysTr[dayIndex]);
              final isDayActive = _activeDays[dayIndex];

              return Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: isDayActive
                        ? null
                        : Colors.grey.shade100, // Dim inactive days
                    border: Border(
                      left: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Background Grid Lines & Unavailability
                      Column(
                        children: List.generate((_endHour - _startHour) * 6, (
                          slotIndex,
                        ) {
                          final absoluteSlotOffset = (_startHour - 8) * 6;
                          final absoluteSlotIndex =
                              slotIndex + absoluteSlotOffset;

                          // Convert absolute slot to hour
                          // absoluteSlotIndex 0 = 08:00
                          // Each slot 10 mins.
                          final currentHour =
                              8 + (absoluteSlotIndex * 10 / 60).floor();

                          final currentMinute = (slotIndex % 6) * 10;

                          // Check specific minute slot OR whole hour slot
                          final isTeacherUnavailable =
                              _currentTeacherUnavailableSlots.contains(
                                '$dayIndex-$currentHour-$currentMinute',
                              ) ||
                              _currentTeacherUnavailableSlots.contains(
                                '$dayIndex-$currentHour',
                              );

                          Color? slotColor;
                          Widget? slotChild;

                          if (!isDayActive) {
                            slotColor = Colors.grey.shade200;
                          } else if (isTeacherUnavailable) {
                            // Striped pattern simulation or distinct blocked look
                            slotColor = Colors.red.shade100;
                            slotChild = Center(
                              child: Icon(
                                Icons.block,
                                size: 12,
                                color: Colors.red.shade300,
                              ),
                            );
                          }

                          return Container(
                            height: 20,
                            decoration: BoxDecoration(
                              color: slotColor,
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.grey.shade100,
                                  width: 0.5,
                                ),
                              ),
                            ),
                            child: InkWell(
                              onTap: () {
                                if (!isDayActive || isTeacherUnavailable)
                                  return;

                                _handleTimeSlotClick(
                                  dayIndex,
                                  currentHour,
                                  absoluteSlotIndex % 6,
                                  startMinute: (absoluteSlotIndex % 6) * 10,
                                );
                              },
                              child: slotChild,
                            ),
                          );
                        }),
                      ),
                      // Occupied Blocks
                      ..._buildMergedBlocks(dayIndex, dayName),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildMergedBlocks(int dayIndex, String dayName) {
    List<Widget> blocks = [];
    int currentSlot = 0;

    // View Window (Absolute slots, based on 08:00 start)
    final int viewStartSlot = (_startHour - 8) * 6;
    final int viewEndSlot = (_endHour - 8) * 6;

    while (currentSlot < 84) {
      final slotData = _clashData['$dayName-$currentSlot'];
      if (slotData != null && slotData is List && slotData.isNotEmpty) {
        // Start of a block
        int startSlot = currentSlot;
        final firstItem = slotData.first;
        final type = firstItem['type'];
        final label = firstItem['label'];
        final details = firstItem['details'];

        // Find end of block
        int endSlot = currentSlot + 1;
        while (endSlot < 84) {
          final nextSlotData = _clashData['$dayName-$endSlot'];
          if (nextSlotData != null &&
              nextSlotData is List &&
              nextSlotData.isNotEmpty) {
            final nextItem = nextSlotData.first;
            if (nextItem['label'] == label && nextItem['type'] == type) {
              endSlot++;
            } else {
              break;
            }
          } else {
            break;
          }
        }

        // Calculate Intersection with View Window
        int visibleStart = startSlot < viewStartSlot
            ? viewStartSlot
            : startSlot;
        int visibleEnd = endSlot > viewEndSlot ? viewEndSlot : endSlot;

        if (visibleStart < visibleEnd) {
          final blockHeight = (visibleEnd - visibleStart) * 20.0;
          final topOffset = (visibleStart - viewStartSlot) * 20.0;

          Color blockColor = Colors.grey.withOpacity(0.4);
          final isEtut = details['type'] == 'Etut';

          if (isEtut) {
            blockColor = Colors.teal.shade400.withOpacity(0.7);
          } else if (type == 'ST') {
            blockColor = Colors.indigo.withOpacity(0.6);
          } else if (type == 'TR') {
            blockColor = Colors.orange.withOpacity(0.6);
          } else if (type == 'BOTH') {
            blockColor = Colors.red.withOpacity(0.6);
          }

          blocks.add(
            Positioned(
              top: topOffset,
              left: 0,
              right: 0,
              height: blockHeight,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                decoration: BoxDecoration(
                  color: blockColor,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: InkWell(
                  onTap: () {
                    final allRefDetails = slotData
                        .map((e) => e['details'] as Map<String, dynamic>)
                        .toList();
                    _showDetailedInfoDialog(label, details, allRefDetails);
                  },
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(2.0),
                      child: isEtut
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  label ?? '',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                // Determine subtitle based on student count
                                Builder(
                                  builder: (context) {
                                    final studentCount = slotData
                                        .where(
                                          (e) =>
                                              e['details']['type'] == 'Etut' &&
                                              e['label'] == label,
                                        )
                                        .length;
                                    String subtitle;
                                    if (studentCount > 1) {
                                      subtitle = 'Çoklu Öğrenci';
                                    } else {
                                      if (type == 'ST') {
                                        subtitle =
                                            details['teacherName'] ??
                                            'Öğretmen';
                                      } else {
                                        subtitle =
                                            details['studentName'] ?? 'Öğrenci';
                                      }
                                    }

                                    return Text(
                                      subtitle,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 8,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    );
                                  },
                                ),
                              ],
                            )
                          : Text(
                              label ?? 'Dolu',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: (blockHeight / 12).floor(),
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        currentSlot = endSlot;
      } else {
        currentSlot++;
      }
    }
    return blocks;
  }

  void _showDetailedInfoDialog(
    String? title,
    Map<String, dynamic>? details,
    List<Map<String, dynamic>> allDetails,
  ) {
    if (details == null) return;

    // Filter relevant details for Etut
    final etutList = details['type'] == 'Etut'
        ? allDetails.where((d) => d['type'] == 'Etut').toList()
        : [details];

    // If it's a lesson or other type, keep simple dialog
    if (details['type'] != 'Etut') {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title ?? 'Detaylar'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Ders:', details['lessonName'] ?? '-'),
              _detailRow('Sınıf:', details['className'] ?? '-'),
              _detailRow('Öğretmen:', details['teacherName'] ?? '-'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Kapat'),
            ),
          ],
        ),
      );
      return;
    }

    // Stylish Dialog for Etüts
    final notesController = TextEditingController(
      text: etutList.first['teacherNotes'] ?? '',
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(16),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 450, maxHeight: 700),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.class_outlined, color: Colors.blue.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Etüt Detayı',
                            style: TextStyle(
                              color: Colors.blue.shade900,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),

                  // Content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Info Card
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              children: [
                                _detailRow('Konu', details['topic'] ?? '-'),
                                const Divider(height: 16),
                                _detailRow(
                                  'Aktivite',
                                  details['action'] ?? '-',
                                  valueColor: Colors.orange.shade800,
                                ),
                                const Divider(height: 16),
                                _detailRow(
                                  'Zaman',
                                  DateFormat('d MMMM, HH:mm', 'tr').format(
                                    (details['startTime'] as Timestamp)
                                        .toDate(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Student List
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Öğrenci Listesi (${etutList.length})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (etutList.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(
                                child: Text('Öğrenci kaydı bulunamadı'),
                              ),
                            )
                          else
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade200),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: List.generate(etutList.length, (
                                  index,
                                ) {
                                  final item = etutList[index];
                                  final isLast = index == etutList.length - 1;
                                  return Container(
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: isLast
                                            ? BorderSide.none
                                            : BorderSide(
                                                color: Colors.grey.shade100,
                                              ),
                                      ),
                                    ),
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 4,
                                          ),
                                      leading: CircleAvatar(
                                        radius: 16,
                                        backgroundColor: Colors.blue.shade50,
                                        child: Text(
                                          (item['studentName'] ?? '?')[0],
                                          style: TextStyle(
                                            color: Colors.blue.shade700,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        item['studentName'] ?? 'İsimsiz',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.red,
                                          size: 20,
                                        ),
                                        onPressed: () async {
                                          final confirmed = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text(
                                                'Öğrenciyi Sil',
                                              ),
                                              content: Text(
                                                '${item['studentName']} etütten çıkarılsın mı?',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, false),
                                                  child: const Text('Hayır'),
                                                ),
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, true),
                                                  child: const Text('Evet'),
                                                ),
                                              ],
                                            ),
                                          );

                                          if (confirmed == true) {
                                            await _cancelEtut(item['id']);
                                            etutList.removeAt(index);
                                            setDialogState(() {});
                                            if (etutList.isEmpty) {
                                              Navigator.pop(context);
                                            }
                                          }
                                        },
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ),
                          const SizedBox(height: 24),

                          // Teacher Notes
                          const Text(
                            'Öğretmen Notları',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: notesController,
                            maxLines: 3,
                            decoration: InputDecoration(
                              hintText: 'Etüt ile ilgili notlar...',
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade200,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade200,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Actions
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Tüm Etütü İptal Et'),
                                content: const Text(
                                  'Bu işlem tüm öğrenciler için etütü silecektir. Emin misiniz?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Vazgeç'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                    child: const Text('Sil'),
                                  ),
                                ],
                              ),
                            );

                            if (confirmed == true) {
                              for (var item in etutList) {
                                await _cancelEtut(item['id']);
                              }
                              Navigator.pop(context);
                            }
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          child: const Text('TÜMÜNÜ İPTAL ET'),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('KAPAT'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            final ids = etutList
                                .map((e) => e['id'] as String)
                                .toList();
                            await _updateEtutNotes(ids, notesController.text);
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade600,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('KAYDET'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _updateEtutNotes(List<String> etutIds, String notes) async {
    setState(() => _isLoading = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (var id in etutIds) {
        final docRef = FirebaseFirestore.instance
            .collection('etut_requests')
            .doc(id);
        batch.update(docRef, {'teacherNotes': notes});
      }
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Notlar kaydedildi')));
        _loadClashData();
      }
    } catch (e) {
      debugPrint('Error updating notes: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: valueColor ?? Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  void _handleTimeSlotClick(
    int dayIndex,
    int hour,
    int lessonIndex, {
    int startMinute = 0,
    bool hasClash = false,
  }) {
    if (_selectedStudentIds.isEmpty || _selectedTeacherId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen önce öğrenci ve öğretmen seçin.')),
      );
      return;
    }
    if (hasClash) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Çakışma Uyarısı'),
          content: const Text(
            'Bu saat diliminde ders programı çakışması bulunmaktadır. Yine de devam etmek istiyor musunuz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _showEtutDialog(
                  dayIndex,
                  hour,
                  lessonIndex,
                  startMinute: startMinute,
                );
              },
              child: const Text('Evet, Devam Et'),
            ),
          ],
        ),
      );
    } else {
      _showEtutDialog(dayIndex, hour, lessonIndex, startMinute: startMinute);
    }
  }

  void _showEtutDialog(
    int dayIndex,
    int hour,
    int lessonIndex, {
    int startMinute = 0,
  }) {
    final teacher = _allTeachers.firstWhere(
      (t) => t['id'] == _selectedTeacherId,
    );
    final branch = teacher['branch'] ?? 'Belirtilmemiş';
    const days = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];
    showDialog(
      context: context,
      builder: (context) => _buildEtutDialog(
        days[dayIndex],
        hour,
        branch,
        lessonIndex,
        startMinute: startMinute,
      ),
    );
  }

  Widget _buildEtutDialog(
    String day,
    int hour,
    String branch,
    int lessonIndex, {
    int startMinute = 0,
  }) {
    String topic = '';
    String selectedAction = 'Soru Çözümü';
    const actions = ['Soru Çözümü', 'Konu Tekrarı', 'Bireysel Çalışma'];
    TimeOfDay startTime = TimeOfDay(hour: hour, minute: startMinute);
    int endTotalMinutes = hour * 60 + startMinute + 40;
    TimeOfDay endTime = TimeOfDay(
      hour: (endTotalMinutes ~/ 60) % 24,
      minute: endTotalMinutes % 60,
    );

    return StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text('$day - Etüt Planla'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Branş: $branch',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: startTime,
                        );
                        if (t != null) setDialogState(() => startTime = t);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Başlangıç',
                          isDense: true,
                        ),
                        child: Text(startTime.format(context)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: endTime,
                        );
                        if (t != null) setDialogState(() => endTime = t);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Bitiş',
                          isDense: true,
                        ),
                        child: Text(endTime.format(context)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Konu',
                  hintText: 'Serbest metin...',
                ),
                onChanged: (v) => topic = v,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedAction,
                decoration: const InputDecoration(labelText: 'Yapılacaklar'),
                items: actions
                    .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                    .toList(),
                onChanged: (v) => selectedAction = v!,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => _saveEtut(
              branch,
              topic,
              selectedAction,
              day,
              startTime,
              endTime,
              lessonIndex,
            ),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveEtut(
    String branch,
    String topic,
    String action,
    String day,
    TimeOfDay startTime,
    TimeOfDay endTime,
    int lessonIndex,
  ) async {
    setState(() => _isLoading = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      final now = DateTime.now();
      final startOfWeek = _focusedDate.subtract(
        Duration(days: _focusedDate.weekday - 1),
      );
      const daysOrder = [
        'Pazartesi',
        'Salı',
        'Çarşamba',
        'Perşembe',
        'Cuma',
        'Cumartesi',
        'Pazar',
      ];
      final dayOffset = daysOrder.indexOf(day);
      final etutBaseDate = DateTime(
        startOfWeek.year,
        startOfWeek.month,
        startOfWeek.day,
      ).add(Duration(days: dayOffset));
      final fullStartDate = DateTime(
        etutBaseDate.year,
        etutBaseDate.month,
        etutBaseDate.day,
        startTime.hour,
        startTime.minute,
      );
      final fullEndDate = DateTime(
        etutBaseDate.year,
        etutBaseDate.month,
        etutBaseDate.day,
        endTime.hour,
        endTime.minute,
      );
      final termId = await TermService().getActiveTermId();

      for (var studentId in _selectedStudentIds) {
        final student = _allStudents.firstWhere((s) => s['id'] == studentId);
        final teacher = _allTeachers.firstWhere(
          (t) => t['id'] == _selectedTeacherId,
        );
        final docRef = FirebaseFirestore.instance
            .collection('etut_requests')
            .doc();
        batch.set(docRef, {
          'institutionId': widget.institutionId,
          'schoolTypeId': widget.schoolTypeId,
          'schoolId': _schoolId,
          'termId': termId,
          'studentId': studentId,
          'studentIds': _selectedStudentIds.toList(),
          'studentName': student['fullName'],
          'teacherId': _selectedTeacherId,
          'teacherName': teacher['fullName'],
          'subject': branch,
          'topic': topic,
          'action': action,
          'startTime': Timestamp.fromDate(fullStartDate),
          'endTime': Timestamp.fromDate(fullEndDate),
          'date': Timestamp.fromDate(etutBaseDate),
          'createdAt': Timestamp.fromDate(now),
          'status': 'pending',
          'lessonIndex': lessonIndex,
        });
      }
      await batch.commit();
      if (mounted) {
        _loadClashData();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Etüt kayıtları başarıyla oluşturuldu.'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving etut: $e');
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cancelEtut(String etutId) async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection('etut_requests')
          .doc(etutId)
          .delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Etüt başarıyla iptal edildi.')),
        );
        _loadClashData();
      }
    } catch (e) {
      debugPrint('Error canceling etut: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
