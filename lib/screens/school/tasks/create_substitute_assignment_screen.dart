import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../services/term_service.dart';

class CreateSubstituteAssignmentScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;

  const CreateSubstituteAssignmentScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
  }) : super(key: key);

  @override
  State<CreateSubstituteAssignmentScreen> createState() =>
      _CreateSubstituteAssignmentScreenState();
}

class _CreateSubstituteAssignmentScreenState
    extends State<CreateSubstituteAssignmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _customReasonController = TextEditingController();

  // State
  DateTime _selectedDate = DateTime.now();
  Map<String, dynamic>? _selectedAbsentTeacher;
  String? _selectedReasonType; // 'Görevli', 'İzinli', 'Raporlu', 'Diğer'
  bool _isFullDay = false;

  // Data
  List<Map<String, dynamic>> _teacherSchedule = [];
  List<Map<String, dynamic>> _selectedSlots = [];
  bool _isLoadingSchedule = false;
  String? _currentPeriodId;

  List<Map<String, dynamic>> _allTeachers = [];

  final List<String> _reasonOptions = [
    'İzinli',
    'Görevli',
    'Raporlu',
    'Gezi',
    'Toplantı',
    'Tören',
    'Diğer',
  ];

  @override
  void initState() {
    super.initState();
    _loadAllTeachers();
  }

  Future<void> _loadAllTeachers() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('type', whereIn: ['teacher', 'staff'])
          .get();

      setState(() {
        _allTeachers = snap.docs.map((d) {
          final data = d.data();
          data['id'] = d.id;
          return data;
        }).toList();
      });
    } catch (e) {
      print('Error loading teachers: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Yeni Atama',
          style: TextStyle(
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionTitle('GENEL BİLGİLER'),
                      const SizedBox(height: 16),

                      // Date
                      _buildSettingItem(
                        icon: Icons.calendar_today,
                        color: const Color(0xFF4F46E5),
                        title: 'Tarih',
                        value: DateFormat(
                          'dd MMM yyyy',
                          'tr_TR',
                        ).format(_selectedDate),
                        onTap: _pickDate,
                      ),
                      const SizedBox(height: 16),

                      // Absent Teacher
                      _buildSettingItem(
                        icon: Icons.person_off,
                        color: const Color(0xFFEF4444),
                        title: 'Gelmeyen Öğretmen',
                        value: _selectedAbsentTeacher?['name'] ?? 'Seçiniz',
                        onTap: () => _showUserSelectSheet(isSubstitute: false),
                      ),
                      const SizedBox(height: 16),

                      // Reason
                      DropdownButtonFormField<String>(
                        value: _selectedReasonType,
                        decoration: InputDecoration(
                          labelText: 'Mazeret Durumu',
                          fillColor: const Color(0xFFFFFF),
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                        items: _reasonOptions
                            .map(
                              (r) => DropdownMenuItem(value: r, child: Text(r)),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedReasonType = v),
                        validator: (v) => v == null ? 'Lütfen seçiniz' : null,
                      ),

                      if (_selectedReasonType == 'Diğer') ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _customReasonController,
                          decoration: InputDecoration(
                            labelText: 'Açıklama Giriniz',
                            fillColor: const Color(0xFFFFFF),
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                          ),
                          validator: (v) =>
                              v!.isEmpty ? 'Açıklama giriniz' : null,
                        ),
                      ],

                      const SizedBox(height: 16),
                      // Full Day Toggle
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Tüm Gün İzinli',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Öğretmenin o günkü tüm derslerine atama yapılır.',
                        ),
                        value: _isFullDay,
                        activeColor: const Color(0xFF4F46E5),
                        onChanged: (val) {
                          setState(() {
                            _isFullDay = val;
                            if (_isFullDay) {
                              // Select all empty slots
                              _selectedSlots = _teacherSchedule
                                  .where(
                                    (s) =>
                                        _existingAssignments[s['hourIndex']] ==
                                        null,
                                  )
                                  .toList();
                            } else {
                              // Deselect all
                              _selectedSlots = [];
                            }
                          });
                        },
                      ),

                      const SizedBox(height: 32),

                      if (_selectedAbsentTeacher != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildSectionTitle('DERS PROGRAMI'),
                            if (_selectedSlots.isNotEmpty)
                              TextButton.icon(
                                onPressed: _autoAssignSubstitutes,
                                icon: const Icon(Icons.auto_fix_high, size: 18),
                                label: const Text('Otomatik Ata'),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF4F46E5),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Geçici atama yapılacak ders saatlerini seç',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildScheduleList(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isAutoAssigning = false;

  Future<void> _autoAssignSubstitutes() async {
    if (_selectedSlots.isEmpty) return;

    // Confirm dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Otomatik Atama'),
        content: Text(
          'Seçili ${_selectedSlots.length} ders saati için en uygun nöbetçi öğretmenler otomatik olarak atanacaktır. Onaylıyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Başlat'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isAutoAssigning = true);

    try {
      int assignedCount = 0;
      final user = FirebaseAuth.instance.currentUser!;

      // 1. Calculate Monthly Stats Once
      final startOfMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
      final endOfMonth = DateTime(
        _selectedDate.year,
        _selectedDate.month + 1,
        0,
        23,
        59,
        59,
      );

      final statsSnap = await FirebaseFirestore.instance
          .collection('temporaryTeacherAssignments')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where(
            'date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth),
          )
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
          .get();

      final teacherStats = <String, int>{};
      for (var doc in statsSnap.docs) {
        final tid = doc.data()['substituteTeacherId'] as String?;
        if (tid != null) teacherStats[tid] = (teacherStats[tid] ?? 0) + 1;
      }

      // 2. Iterate Selected Slots
      for (var slot in _selectedSlots) {
        final hourIndex = slot['hourIndex'];
        // Skip if already assigned
        if (_existingAssignments[hourIndex] != null) continue;

        // Find Busy Teachers for this Slot
        final periodId = slot['periodId'];
        final day = slot['day'];

        // Class Schedules check
        final busySnap = await FirebaseFirestore.instance
            .collection('classSchedules')
            .where('periodId', isEqualTo: periodId)
            .where('day', isEqualTo: day)
            .where('hourIndex', isEqualTo: hourIndex)
            .where('isActive', isEqualTo: true)
            .get();

        final Set<String> busyTeacherIds = {};
        for (var doc in busySnap.docs) {
          final d = doc.data();
          if (d['teacherId'] != null) busyTeacherIds.add(d['teacherId']);
          if (d['teacherIds'] is List) {
            busyTeacherIds.addAll(
              (d['teacherIds'] as List).map((e) => e.toString()),
            );
          }
        }

        // Temp Assignments check
        final startOfDay = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
        );
        final endOfDay = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
          23,
          59,
          59,
        );

        final tempSnap = await FirebaseFirestore.instance
            .collection('temporaryTeacherAssignments')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where(
              'date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
            )
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
            .get();

        for (var doc in tempSnap.docs) {
          final d = doc.data();
          if (d['hourIndex'] == hourIndex && d['substituteTeacherId'] != null) {
            busyTeacherIds.add(d['substituteTeacherId']);
          }
        }
        if (_selectedAbsentTeacher != null) {
          busyTeacherIds.add(_selectedAbsentTeacher!['id']);
        }

        // Filter Available
        final available = _allTeachers
            .where((t) => !busyTeacherIds.contains(t['id']))
            .toList();

        if (available.isEmpty) continue;

        // Sort (Best Match First)
        final absentBranches =
            (_selectedAbsentTeacher?['branches'] as List?)
                ?.map((e) => e.toString().toUpperCase())
                .toSet() ??
            {};

        available.sort((a, b) {
          // Branch Match Logic
          final aBranchesList =
              (a['branches'] as List?)
                  ?.map((e) => e.toString().toUpperCase())
                  .toSet() ??
              {};
          if (a['branch'] is String)
            aBranchesList.add((a['branch'] as String).toUpperCase());

          final bBranchesList =
              (b['branches'] as List?)
                  ?.map((e) => e.toString().toUpperCase())
                  .toSet() ??
              {};
          if (b['branch'] is String)
            bBranchesList.add((b['branch'] as String).toUpperCase());

          final aMatch = aBranchesList.intersection(absentBranches).isNotEmpty;
          final bMatch = bBranchesList.intersection(absentBranches).isNotEmpty;

          if (aMatch && !bMatch) return -1;
          if (!aMatch && bMatch) return 1;

          // Stats Count Logic
          final aCount = teacherStats[a['id']] ?? 0;
          final bCount = teacherStats[b['id']] ?? 0;
          if (aCount != bCount) return aCount.compareTo(bCount);

          return (a['fullName'] ?? '').compareTo(b['fullName'] ?? '');
        });

        // Pick the WINNER
        final winner = available.first;

        // Assign to Winner
        await FirebaseFirestore.instance
            .collection('temporaryTeacherAssignments')
            .add({
              'institutionId': widget.institutionId,
              'schoolTypeId': widget.schoolTypeId,
              'originalTeacherId': _selectedAbsentTeacher!['id'],
              'originalTeacherName': _selectedAbsentTeacher!['name'],
              'substituteTeacherId': winner['id'],
              'substituteTeacherName': winner['fullName'],
              'classId': slot['classId'],
              'className': slot['className'],
              'lessonId': slot['lessonId'],
              'lessonName': slot['lessonName'],
              'date': Timestamp.fromDate(_selectedDate),
              'hourIndex': hourIndex,
              'dayName': [
                '',
                'Pazartesi',
                'Salı',
                'Çarşamba',
                'Perşembe',
                'Cuma',
                'Cumartesi',
                'Pazar',
              ][_selectedDate.weekday],
              'reason':
                  (_selectedReasonType == 'Diğer'
                      ? _customReasonController.text
                      : _selectedReasonType) ??
                  'Görevli',
              'status': 'published',
              'createdAt': FieldValue.serverTimestamp(),
              'creatorId': user.uid,
            });

        // Update local stat for next iteration fairness
        teacherStats[winner['id']] = (teacherStats[winner['id']] ?? 0) + 1;
        assignedCount++;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$assignedCount ders için otomatik atama yapıldı.'),
        ),
      );

      // Refresh
      if (_selectedAbsentTeacher != null) {
        _loadTeacherSchedule(_selectedAbsentTeacher!['id']);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      setState(() => _isAutoAssigning = false);
    }
  }

  Widget _buildScheduleList() {
    if (_isAutoAssigning) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('En uygun öğretmenler bulunup atanıyor...'),
          ],
        ),
      );
    }

    if (_isLoadingSchedule) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_teacherSchedule.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Bu tarihte ders bulunmamaktadır.',
                style: TextStyle(color: Colors.orange.shade900),
              ),
            ),
          ],
        ),
      );
    }

    // Extract unique hourIndex values to prevent duplicate chips
    final uniqueHourIndices = <int>{};
    for (var lesson in _teacherSchedule) {
      final hourIdx = lesson['hourIndex'] as int?;
      if (hourIdx != null) {
        uniqueHourIndices.add(hourIdx);
      }
    }
    final sortedHours = uniqueHourIndices.toList()..sort();

    print('DEBUG: _teacherSchedule has ${_teacherSchedule.length} lessons');
    print('DEBUG: Unique hour indices: $sortedHours');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: sortedHours.map((hourIdx) {
                // Find first lesson with this hourIndex for display
                final lesson = _teacherSchedule.firstWhere(
                  (l) => l['hourIndex'] == hourIdx,
                  orElse: () => {'hourIndex': hourIdx},
                );
                final hourLabel = (hourIdx + 1).toString();

                final existing = _existingAssignments[hourIdx];
                final isFilled = existing != null;

                // Check if this specific slot is selected
                final isSelected = _selectedSlots.any(
                  (s) => s['hourIndex'] == hourIdx,
                );

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: FilterChip(
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    label: Text(
                      hourLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? Colors.white
                            : (isFilled
                                  ? const Color(0xFF166534)
                                  : Colors.black87),
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (bool selected) {
                      setState(() {
                        if (selected) {
                          if (!_selectedSlots.any(
                            (s) => s['hourIndex'] == hourIdx,
                          )) {
                            _selectedSlots.add(lesson);
                          }
                        } else {
                          _selectedSlots.removeWhere(
                            (s) => s['hourIndex'] == hourIdx,
                          );
                        }

                        // Check Full Day logic
                        final emptyCount = _teacherSchedule
                            .where(
                              (s) =>
                                  _existingAssignments[s['hourIndex']] == null,
                            )
                            .length;
                        final selectedEmpty = _selectedSlots
                            .where(
                              (s) =>
                                  _existingAssignments[s['hourIndex']] == null,
                            )
                            .length;
                        _isFullDay =
                            (emptyCount > 0 && emptyCount == selectedEmpty);
                      });
                    },
                    selectedColor: isFilled
                        ? const Color(0xFF15803D)
                        : const Color(0xFF4F46E5),
                    backgroundColor: isFilled
                        ? const Color(0xFFDCFCE7)
                        : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected
                            ? Colors.transparent
                            : (isFilled
                                  ? const Color(0xFF86EFAC)
                                  : Colors.grey.shade300),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 24),

        if (_selectedSlots.isEmpty)
          Center(
            child: Column(
              children: [
                Icon(Icons.touch_app, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                const Text(
                  'Atama yapmak veya detay görmek için yukarıdan ders seçiniz.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _selectedSlots.length,
            separatorBuilder: (context, index) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              // Sort for display
              _selectedSlots.sort(
                (a, b) =>
                    (a['hourIndex'] as int).compareTo(b['hourIndex'] as int),
              );

              final lesson = _selectedSlots[index];
              final hourIdx = lesson['hourIndex'];
              final existing = _existingAssignments[hourIdx];

              return SubstituteAssignmentCard(
                key: ValueKey(
                  '${lesson['hourIndex']}_${existing != null ? "filled" : "empty"}',
                ),
                institutionId: widget.institutionId,
                schoolTypeId: widget.schoolTypeId,
                lessonSlot: lesson,
                existingAssignment: existing,
                absentTeacher: _selectedAbsentTeacher!,
                selectedDate: _selectedDate,
                allTeachers: _allTeachers,
                currentPeriodId: _currentPeriodId,
                defaultReason: _selectedReasonType,
                customReason: _customReasonController.text,
                onAssignmentChanged: () {
                  // Refresh main schedule status to update chips
                  _loadTeacherSchedule(_selectedAbsentTeacher!['id']);
                },
              );
            },
          ),
      ],
    );
  }

  // Helper Widgets
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFF1E293B),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: Color(0xFFCBD5E1),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 90)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF4F46E5)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _selectedSlots = [];
      });
      if (_selectedAbsentTeacher != null) {
        _loadTeacherSchedule(_selectedAbsentTeacher!['id']);
      }
    }
  }

  Future<void> _showUserSelectSheet({required bool isSubstitute}) async {
    // Check if we already have teachers loaded
    if (_allTeachers.isEmpty) await _loadAllTeachers();

    // We only use this for selecting ABSENT teacher now, since substitute is selected via list
    if (isSubstitute) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (_, controller) {
            return ListView.builder(
              controller: controller,
              padding: const EdgeInsets.all(16),
              itemCount: _allTeachers.length,
              itemBuilder: (context, index) {
                final user = _allTeachers[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text((user['fullName'] ?? '?')[0]),
                  ),
                  title: Text(user['fullName'] ?? ''),
                  subtitle: Text(
                    (user['branches'] as List?)?.firstOrNull ??
                        (user['branch'] as String? ?? ''),
                  ),
                  onTap: () {
                    // Normalize branches for the absent teacher
                    final List<String> bList = [];
                    if (user['branches'] is List) {
                      bList.addAll(
                        (user['branches'] as List).map((e) => e.toString()),
                      );
                    }
                    if (user['branch'] is String &&
                        (user['branch'] as String).isNotEmpty) {
                      bList.add(user['branch']);
                    }

                    setState(() {
                      _selectedAbsentTeacher = {
                        'id': user['id'],
                        'name': user['fullName'],
                        'branches': bList,
                      };
                      _selectedSlots = [];
                    });
                    _loadTeacherSchedule(user['id']);
                    Navigator.pop(context);
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Map<int, Map<String, dynamic>> _existingAssignments = {};

  Future<void> _loadTeacherSchedule(String teacherId) async {
    setState(() => _isLoadingSchedule = true);
    _existingAssignments = {};

    try {
      final periodSnapshot = await FirebaseFirestore.instance
          .collection('workPeriods')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          // Removed checking only isActive to allow viewing selected passive period
          .get();

      if (periodSnapshot.docs.isEmpty) {
        setState(() {
          _teacherSchedule = [];
          _isLoadingSchedule = false;
        });
        return;
      }

      // 0. Try to find matching period by Date first
      QueryDocumentSnapshot? periodDoc;
      try {
        periodDoc = periodSnapshot.docs.firstWhere((doc) {
          final data = doc.data();
          final start = (data['startDate'] as Timestamp?)?.toDate();
          final end = (data['endDate'] as Timestamp?)?.toDate();

          if (start != null && end != null) {
            final pStart = DateTime(start.year, start.month, start.day);
            final pEnd = DateTime(end.year, end.month, end.day, 23, 59, 59);
            final sDate = DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
            );
            // Inclusive check
            return (sDate.isAtSameMomentAs(pStart) || sDate.isAfter(pStart)) &&
                (sDate.isAtSameMomentAs(pEnd) || sDate.isBefore(pEnd));
          }
          return false;
        });
        print('DEBUG: Found Period matching selected date: ${periodDoc.id}');
      } catch (_) {
        print(
          'DEBUG: No specific period found for date $_selectedDate, falling back to selection',
        );
      }

      if (periodDoc == null) {
        // 1. Get Selected/Active Term ID from Service
        String? targetPeriodId;
        try {
          final selectedId = await TermService().getSelectedTermId();
          final activeId = await TermService().getActiveTermId();
          targetPeriodId = selectedId ?? activeId;
          print('DEBUG: Target Period ID: $targetPeriodId');
        } catch (e) {
          print('Error fetching term ID: $e');
        }

        // 2. Find matching document
        if (targetPeriodId != null) {
          try {
            periodDoc = periodSnapshot.docs.firstWhere(
              (d) => d.id == targetPeriodId,
            );
          } catch (_) {}
        }
      }

      // 3. Fallback to first active one if not found
      if (periodDoc == null) {
        try {
          periodDoc = periodSnapshot.docs.firstWhere(
            (d) => d['isActive'] == true,
          );
        } catch (_) {
          if (periodSnapshot.docs.isNotEmpty) {
            periodDoc = periodSnapshot.docs.first;
          }
        }
      }

      if (periodDoc == null) return; // Should not happen given check above

      final periodId = periodDoc.id;
      final periodData = periodDoc.data() as Map<String, dynamic>;
      _currentPeriodId = periodId;
      final dayName = _dayNameTr(_selectedDate);

      // Get real lesson hours count from period
      int dailyLimit = 10; // Default fallback
      try {
        if (periodData['lessonHours'] != null &&
            periodData['lessonHours']['lessonTimes'] != null &&
            periodData['lessonHours']['lessonTimes'][dayName] != null) {
          final dayLessons = periodData['lessonHours']['lessonTimes'][dayName];
          if (dayLessons is List) {
            dailyLimit = dayLessons.length;
            print(
              'DEBUG: Using period lessonTimes count: $dailyLimit lessons for $dayName',
            );
          }
        } else {
          print(
            'DEBUG: No lessonTimes found, using default limit: $dailyLimit',
          );
        }
      } catch (e) {
        print('Error parsing lesson times: $e');
      }

      print('DEBUG: Loading Schedule');
      print('DEBUG: PeriodID: $periodId');
      print('DEBUG: DayName: $dayName');
      print('DEBUG: DailyLimit: $dailyLimit');
      print('DEBUG: TeacherID: $teacherId');

      // 1. Fetch Existing Substitutions
      final startOfDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      final endOfDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        23,
        59,
        59,
      );

      final existingSnap = await FirebaseFirestore.instance
          .collection('temporaryTeacherAssignments')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('originalTeacherId', isEqualTo: teacherId)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .get();

      final filledSlots = <int, Map<String, dynamic>>{};
      for (var doc in existingSnap.docs) {
        final d = doc.data();
        d['id'] = doc.id; // Store Doc ID for deletion
        final h = d['hourIndex'] as int?;
        if (h != null) filledSlots[h] = d;
      }

      // 1.5 Fetch Assignments to support fallback matching
      // We do this because some schedule slots might not have teacherId set explicitly,
      // but the teacher is assigned to that lesson/class in general.
      final assignmentsSnap = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('teacherIds', arrayContains: teacherId)
          .where('isActive', isEqualTo: true)
          .get();

      final assignedClassLessons = <String>{};
      final assignmentDetails = <String, Map<String, String>>{};

      for (var d in assignmentsSnap.docs) {
        final data = d.data();
        final cid = data['classId'];
        final lid = data['lessonId'];
        if (cid != null && lid != null) {
          final key = '${cid}_${lid}';
          assignedClassLessons.add(key);
          assignmentDetails[key] = {
            'className': (data['className'] ?? '').toString(),
            'lessonName': (data['lessonName'] ?? '').toString(),
          };
        }
      }

      // 2. Fetch Schedule Directly from classSchedules
      // We fetch ALL schedules for the day and filter client-side to ensure maximum robustness
      // and avoid issues with missing indexes or type mismatches (String vs Int) for teacherId.

      print(
        'DEBUG: Fetching ALL schedules for day $dayName to filter locally...',
      );

      final dayAllSnap = await FirebaseFirestore.instance
          .collection('classSchedules')
          .where('periodId', isEqualTo: periodId)
          .where('day', isEqualTo: dayName)
          .where('isActive', isEqualTo: true) // Added safety check
          .get();

      print(
        'DEBUG: Fetched ${dayAllSnap.docs.length} total slots for the day.',
      );

      // Debug: Log all hourIndex values from query
      for (var doc in dayAllSnap.docs) {
        final data = doc.data();
        print(
          'DEBUG: Raw query result: hourIdx=${data['hourIndex']}, isActive=${data['isActive']}, teacherId=${data['teacherId']}',
        );
      }

      final uniqueSlots = <String, Map<String, dynamic>>{};

      for (var doc in dayAllSnap.docs) {
        final data = doc.data();
        final tId = data['teacherId'];
        final tIds = data['teacherIds'];

        bool match = false;

        // Check primary teacherId
        if (tId != null && tId.toString() == teacherId) {
          match = true;
        }

        // Check teacherIds array
        if (!match && tIds is List) {
          // robust check for string/int values in the list
          if (tIds.any((e) => e.toString() == teacherId)) {
            match = true;
          }
        }

        // Fallback: If not matched by ID, check assignment mapping
        // ONLY if the schedule slot doesn't specify a DIFFERENT teacher?
        // Logic: specific teacherId on slot > general assignment
        if (!match) {
          final slotTeacherId = data['teacherId'];
          final slotTeacherIds = data['teacherIds'];

          // If slot has NO specific teacher info, assume it belongs to the assigned teacher for that subject
          bool hasSpecificTeacher =
              (slotTeacherId != null && slotTeacherId.toString().isNotEmpty) ||
              (slotTeacherIds is List && slotTeacherIds.isNotEmpty);

          if (!hasSpecificTeacher) {
            final cid = data['classId'];
            final lid = data['lessonId'];
            // Create same composite key
            if (cid != null &&
                lid != null &&
                assignedClassLessons.contains('${cid}_${lid}')) {
              match = true;
            }
          }
        }

        if (match) {
          // Enrich data if missing names
          final cid = data['classId'];
          final lid = data['lessonId'];

          if (cid != null && lid != null) {
            final key = '${cid}_${lid}';
            if (assignmentDetails.containsKey(key)) {
              if (data['className'] == null ||
                  data['className'].toString().isEmpty) {
                data['className'] = assignmentDetails[key]!['className'];
              }
              if (data['lessonName'] == null ||
                  data['lessonName'].toString().isEmpty) {
                data['lessonName'] = assignmentDetails[key]!['lessonName'];
              }
            }
          }

          // Use hourIndex + classId as composite key to prevent data loss
          final hourIdx = data['hourIndex'];
          final classId = data['classId'];
          if (hourIdx != null && classId != null) {
            final compositeKey = '${hourIdx}_$classId';
            uniqueSlots[compositeKey] = data;
            print(
              'DEBUG: Added to uniqueSlots: hourIdx=$hourIdx, classId=$classId, compositeKey=$compositeKey',
            );
          }
        }
      }
      print(
        'DEBUG: Found ${uniqueSlots.length} matching slots after client-side filter.',
      );

      List<Map<String, dynamic>> foundSlots = uniqueSlots.values.toList();

      // Sort by hourIndex for display
      foundSlots.sort((a, b) {
        final aIdx = a['hourIndex'] as int? ?? 0;
        final bIdx = b['hourIndex'] as int? ?? 0;
        return aIdx.compareTo(bIdx);
      });

      print(
        'DEBUG: Showing all ${foundSlots.length} lessons (no dailyLimit filter)',
      );

      // Sort by hour
      foundSlots.sort(
        (a, b) => ((a['hourIndex'] ?? 0) as int).compareTo(
          (b['hourIndex'] ?? 0) as int,
        ),
      );

      setState(() {
        _teacherSchedule = foundSlots;
        _existingAssignments = filledSlots;
        _isLoadingSchedule = false;

        if (_isFullDay) {
          // Auto-select all empty slots
          _selectedSlots = foundSlots
              .where((s) => !filledSlots.containsKey(s['hourIndex']))
              .toList();
        } else {
          // Keep existing selection if valid, or clear?
          // Clearing is safer to avoid stale state
          _selectedSlots = [];
        }
      });
    } catch (e) {
      print('Schedule Load Error: $e');
      setState(() {
        _teacherSchedule = [];
        _isLoadingSchedule = false;
      });
    }
  }

  String _dayNameTr(DateTime date) {
    switch (date.weekday) {
      case 1:
        return 'Pazartesi';
      case 2:
        return 'Salı';
      case 3:
        return 'Çarşamba';
      case 4:
        return 'Perşembe';
      case 5:
        return 'Cuma';
      case 6:
        return 'Cumartesi';
      case 7:
        return 'Pazar';
      default:
        return '';
    }
  }
}

class SubstituteAssignmentCard extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final Map<String, dynamic> lessonSlot;
  final Map<String, dynamic>? existingAssignment;
  final Map<String, dynamic> absentTeacher;
  final DateTime selectedDate;
  final List<Map<String, dynamic>> allTeachers;
  final String? currentPeriodId;
  final String? defaultReason;
  final String? customReason;
  final VoidCallback onAssignmentChanged;

  const SubstituteAssignmentCard({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.lessonSlot,
    required this.existingAssignment,
    required this.absentTeacher,
    required this.selectedDate,
    required this.allTeachers,
    required this.currentPeriodId,
    required this.onAssignmentChanged,
    this.defaultReason,
    this.customReason,
  }) : super(key: key);

  @override
  State<SubstituteAssignmentCard> createState() =>
      _SubstituteAssignmentCardState();
}

class _SubstituteAssignmentCardState extends State<SubstituteAssignmentCard> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _availableSubstitutes = [];
  Map<String, int> _teacherStats = {};

  @override
  void initState() {
    super.initState();
    if (widget.existingAssignment == null) {
      _loadSubstitutes();
    }
  }

  Future<void> _loadSubstitutes() async {
    setState(() => _isLoading = true);
    try {
      // 1. Stats
      final startOfMonth = DateTime(
        widget.selectedDate.year,
        widget.selectedDate.month,
        1,
      );
      final endOfMonth = DateTime(
        widget.selectedDate.year,
        widget.selectedDate.month + 1,
        0,
        23,
        59,
        59,
      );

      final statsSnap = await FirebaseFirestore.instance
          .collection('temporaryTeacherAssignments')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where(
            'date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth),
          )
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
          .get();

      final stats = <String, int>{};
      for (var doc in statsSnap.docs) {
        final tid = doc.data()['substituteTeacherId'] as String?;
        if (tid != null) stats[tid] = (stats[tid] ?? 0) + 1;
      }
      _teacherStats = stats;

      // 2. Find Busy Teachers
      final periodId = widget.lessonSlot['periodId'];
      final day = widget.lessonSlot['day'];
      final hourIndex = widget.lessonSlot['hourIndex'];

      final busySnap = await FirebaseFirestore.instance
          .collection('classSchedules')
          .where('periodId', isEqualTo: periodId)
          .where('day', isEqualTo: day)
          .where('hourIndex', isEqualTo: hourIndex)
          .where('isActive', isEqualTo: true)
          .get();

      final Set<String> busyTeacherIds = {};
      for (var doc in busySnap.docs) {
        final d = doc.data();
        if (d['teacherId'] != null) busyTeacherIds.add(d['teacherId']);
        if (d['teacherIds'] is List) {
          busyTeacherIds.addAll(
            (d['teacherIds'] as List).map((e) => e.toString()),
          );
        }
      }

      // Check existing temps for this hour
      final startOfDay = DateTime(
        widget.selectedDate.year,
        widget.selectedDate.month,
        widget.selectedDate.day,
      );
      final endOfDay = DateTime(
        widget.selectedDate.year,
        widget.selectedDate.month,
        widget.selectedDate.day,
        23,
        59,
        59,
      );

      final tempSnap = await FirebaseFirestore.instance
          .collection('temporaryTeacherAssignments')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .get();

      for (var doc in tempSnap.docs) {
        final d = doc.data();
        // Manual filter for hourIndex to avoid composite index requirement
        if (d['hourIndex'] != hourIndex) continue;

        if (d['substituteTeacherId'] != null)
          busyTeacherIds.add(d['substituteTeacherId']);
      }

      busyTeacherIds.add(widget.absentTeacher['id']);

      final available = widget.allTeachers
          .where((t) => !busyTeacherIds.contains(t['id']))
          .toList();

      // Sort
      final absentBranches =
          (widget.absentTeacher['branches'] as List?)
              ?.map((e) => e.toString().toUpperCase())
              .toSet() ??
          {};

      available.sort((a, b) {
        final aBranchesList =
            (a['branches'] as List?)
                ?.map((e) => e.toString().toUpperCase())
                .toSet() ??
            {};
        if (a['branch'] is String)
          aBranchesList.add((a['branch'] as String).toUpperCase());

        final bBranchesList =
            (b['branches'] as List?)
                ?.map((e) => e.toString().toUpperCase())
                .toSet() ??
            {};
        if (b['branch'] is String)
          bBranchesList.add((b['branch'] as String).toUpperCase());

        final aMatch = aBranchesList.intersection(absentBranches).isNotEmpty;
        final bMatch = bBranchesList.intersection(absentBranches).isNotEmpty;

        if (aMatch && !bMatch) return -1;
        if (!aMatch && bMatch) return 1;

        final aCount = _teacherStats[a['id']] ?? 0;
        final bCount = _teacherStats[b['id']] ?? 0;
        if (aCount != bCount) return aCount.compareTo(bCount);

        return (a['fullName'] ?? '').compareTo(b['fullName'] ?? '');
      });

      setState(() {
        _availableSubstitutes = available;
        _isLoading = false;
      });
    } catch (e) {
      print('Load Sub Error: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _makeAssignment(Map<String, dynamic> teacher) async {
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final reason =
          (widget.defaultReason == 'Diğer'
              ? widget.customReason
              : widget.defaultReason) ??
          'Görevli';

      // Write assignment
      await FirebaseFirestore.instance
          .collection('temporaryTeacherAssignments')
          .add({
            'institutionId': widget.institutionId,
            'schoolTypeId': widget.schoolTypeId,
            'originalTeacherId': widget.absentTeacher['id'],
            'originalTeacherName': widget.absentTeacher['name'],
            'substituteTeacherId': teacher['id'],
            'substituteTeacherName': teacher['fullName'],
            'classId': widget.lessonSlot['classId'],
            'className': widget.lessonSlot['className'],
            'lessonId': widget.lessonSlot['lessonId'],
            'lessonName': widget.lessonSlot['lessonName'],
            'date': Timestamp.fromDate(widget.selectedDate),
            'hourIndex': widget.lessonSlot['hourIndex'],
            'dayName': [
              '',
              'Pazartesi',
              'Salı',
              'Çarşamba',
              'Perşembe',
              'Cuma',
              'Cumartesi',
              'Pazar',
            ][widget.selectedDate.weekday],
            'reason': reason,
            'status': 'published',
            'createdAt': FieldValue.serverTimestamp(),
            'creatorId': user.uid,
          });

      // Notification - DEFERRED to 'Publish' button in SubstituteTeacherListScreen
      /*
      final formattedDate = DateFormat(
        'dd.MM.yyyy',
      ).format(widget.selectedDate);
      final lessonHour = widget.lessonSlot['hourIndex'] + 1;

      await FirebaseFirestore.instance.collection('notificationRequests').add({
        'type': 'teacher_assignment',
        'institutionId': widget.institutionId,
        'schoolTypeId': widget.schoolTypeId,
        'periodId': widget.currentPeriodId,
        'teacherId': teacher['id'],
        'teacherIds': [teacher['id']],
        'teacherNames': [teacher['fullName']],
        'message':
            '$formattedDate tarihinde, $lessonHour. ders (${widget.lessonSlot['lessonName']}) için ${widget.absentTeacher['name']} yerine görevlendirildiniz.',
        'title': 'Geçici Görevlendirme',
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'queued',
      });
      */

      widget.onAssignmentChanged();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Future<void> _cancelAssignment() async {
    if (widget.existingAssignment == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('temporaryTeacherAssignments')
          .doc(widget.existingAssignment!['id'])
          .delete();
      widget.onAssignmentChanged();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isAssigned = widget.existingAssignment != null;
    final String lessonInfo =
        '${widget.lessonSlot['hourIndex'] + 1}. Ders (${widget.lessonSlot['className'] ?? ''}) - ${widget.lessonSlot['lessonName']}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isAssigned ? const Color(0xFFF0FDF4) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAssigned ? const Color(0xFFBBF7D0) : Colors.grey.shade300,
        ),
        boxShadow: [
          if (!isAssigned)
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: !isAssigned, // Auto-expand if not assigned
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isAssigned ? Colors.green.shade100 : Colors.blue.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isAssigned ? Icons.check_circle : Icons.person_search,
              color: isAssigned ? Colors.green.shade700 : Colors.blue.shade700,
              size: 24,
            ),
          ),
          title: Text(
            lessonInfo,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isAssigned
                  ? const Color(0xFF15803D)
                  : const Color(0xFF1E293B),
              fontSize: 15,
            ),
          ),
          subtitle: isAssigned
              ? Text(
                  'Atanan: ${widget.existingAssignment!['substituteTeacherName']}',
                  style: const TextStyle(fontSize: 13),
                )
              : const Text(
                  'Öğretmen Seçiniz',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            if (isAssigned) ...[
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Nedeni: ${widget.existingAssignment!['reason'] ?? ''}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Atamayı İptal Et'),
                          content: Text(
                            '${widget.existingAssignment!['substituteTeacherName']} atamasını kaldırmak istiyor musunuz?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Vazgeç'),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              onPressed: () {
                                Navigator.pop(context);
                                _cancelAssignment();
                              },
                              child: const Text(
                                'İptal Et',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: Colors.red,
                    ),
                    label: const Text(
                      'İptal Et',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // List of available teachers
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_availableSubstitutes.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Uygun öğretmen bulunamadı.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _availableSubstitutes.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final teacher = _availableSubstitutes[index];
                    final absentBranches =
                        (widget.absentTeacher['branches'] as List?)
                            ?.map((e) => e.toString().toUpperCase())
                            .toSet() ??
                        {};

                    // Determine branch text
                    String teacherBranch = '';
                    if (teacher['branch'] is String) {
                      teacherBranch = teacher['branch'];
                    } else if (teacher['branches'] is List) {
                      teacherBranch = (teacher['branches'] as List).join(', ');
                    }

                    // Check match
                    bool isMatch = false;
                    if (teacher['branch'] is String &&
                        absentBranches.contains(
                          (teacher['branch'] as String).toUpperCase(),
                        )) {
                      isMatch = true;
                    }
                    if (!isMatch && teacher['branches'] is List) {
                      final tSet = (teacher['branches'] as List)
                          .map((e) => e.toString().toUpperCase())
                          .toSet();
                      if (tSet.intersection(absentBranches).isNotEmpty)
                        isMatch = true;
                    }

                    final count = _teacherStats[teacher['id']] ?? 0;

                    return InkWell(
                      onTap: () => _makeAssignment(teacher),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMatch
                              ? const Color(0xFFEFF6FF)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isMatch
                                ? const Color(0xFF60A5FA)
                                : Colors.grey.shade200,
                            width: isMatch ? 1.5 : 1,
                          ),
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
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: isMatch
                                  ? const Color(0xFFDBEAFE)
                                  : const Color(0xFFF1F5F9),
                              child: Text(
                                (teacher['fullName'] ?? '?')[0],
                                style: TextStyle(
                                  color: isMatch
                                      ? const Color(0xFF1E40AF)
                                      : Colors.black87,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    teacher['fullName'] ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  if (teacherBranch.isNotEmpty)
                                    Text(
                                      teacherBranch,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isMatch
                                            ? const Color(0xFF2563EB)
                                            : const Color(0xFF64748B),
                                        fontWeight: isMatch
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Text(
                                    '$count Görev',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4F46E5),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Ata',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}
