import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/term_service.dart';
import 'attendance_statistics_screen.dart';
import 'class_lesson_attendance_screen.dart';

class AttendanceOperationsScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;

  const AttendanceOperationsScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
  });

  @override
  State<AttendanceOperationsScreen> createState() =>
      _AttendanceOperationsScreenState();
}

class _AttendanceOperationsScreenState
    extends State<AttendanceOperationsScreen> {
  bool _loading = true;
  bool _loadingTaken = false;
  bool _loadingSchedule = false;
  bool _sending = false;

  String? _activeWorkPeriodId;
  Map<String, dynamic>? _activeWorkPeriod;

  String? _activeTermId;

  DateTime _selectedDate = DateTime.now();
  int _selectedHour = 1;
  List<int> _availableHoursForDay = const [1];

  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _visibleClasses = [];
  List<int> _availableClassLevels = [];
  int? _selectedClassLevel;
  Set<String> _takenClassIds = {};
  String? _noPlanMessage;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    _init();
  }

  Future<void> _init() async {
    setState(() => _loading = true);
    try {
      await _loadActivePeriodAndTerm();
      await _loadClasses();
      _refreshAvailableHoursForSelectedDay();
      await _loadScheduleForSelection();
      await _loadTakenForSelection();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String? _activeWorkPeriodName;

  Future<void> _loadActivePeriodAndTerm() async {
    // 1. Try to find PUBLISHED periods (Fetch ALL to sort them)
    // Don't use limit(1) because we need to compare dates if there are multiple
    var periodSnap = await FirebaseFirestore.instance
        .collection('workPeriods')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
        .where('isPublished', isEqualTo: true)
        .get();

    // 2. If no published found, fallback to ACTIVE periods
    if (periodSnap.docs.isEmpty) {
      periodSnap = await FirebaseFirestore.instance
          .collection('workPeriods')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true)
          .get();
    }

    if (periodSnap.docs.isEmpty) {
      throw Exception(
        'Yayında veya aktif olan bir dönem (workPeriod) bulunamadı',
      );
    }

    // 3. Sort to find the most relevant one (Latest EndDate usually implies the current one)
    final docs = periodSnap.docs;
    if (docs.length > 1) {
      docs.sort((a, b) {
        // Sort by endDate descending (newest first)
        final endA = (a.data()['endDate'] ?? '').toString();
        final endB = (b.data()['endDate'] ?? '').toString();
        // Simple string comparison YYYY-MM-DD works, or just assume creation order might suffice but date is better
        return endB.compareTo(endA);
      });
    }

    final selectedDoc = docs.first;

    _activeWorkPeriodId = selectedDoc.id;
    _activeWorkPeriod = selectedDoc.data();
    _activeWorkPeriodName = (_activeWorkPeriod?['name'] ?? '').toString();

    // Also get active term for filtering students/classes correctly
    _activeTermId = await TermService().getActiveTermId();
  }

  Future<void> _loadClasses() async {
    final classesSnap = await FirebaseFirestore.instance
        .collection('classes')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
        .where('isActive', isEqualTo: true)
        .get();

    final classes = classesSnap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();

    final filtered = classes.where((c) {
      if ((_activeTermId ?? '').isEmpty) return true;
      final termId = (c['termId'] ?? '').toString();
      return termId.isEmpty || termId == _activeTermId;
    }).toList();

    final levels = <int>{};
    for (final c in filtered) {
      final v = c['classLevel'];
      final lvl = v is int ? v : int.tryParse((v ?? '').toString());
      if (lvl != null) levels.add(lvl);
    }
    final levelList = levels.toList()..sort();

    filtered.sort(
      (a, b) => (a['className'] ?? '').toString().compareTo(
        (b['className'] ?? '').toString(),
      ),
    );

    _classes = filtered;
    _availableClassLevels = levelList;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;
    setState(() {
      _selectedDate = DateTime(picked.year, picked.month, picked.day);
    });

    _refreshAvailableHoursForSelectedDay();
    await _loadScheduleForSelection();
    await _loadTakenForSelection();
  }

  Future<void> _sendReminderToTeacher(Map<String, dynamic> classData) async {
    if ((_activeWorkPeriodId ?? '').isEmpty) return;
    final classId = (classData['id'] ?? '').toString();
    final className = (classData['className'] ?? '').toString();
    if (classId.isEmpty) return;

    final day = _dayNameTr(_selectedDate);
    final hourIndex = _selectedHour - 1;

    final scheduleSnap = await FirebaseFirestore.instance
        .collection('classSchedules')
        .where('periodId', isEqualTo: _activeWorkPeriodId)
        .where('classId', isEqualTo: classId)
        .where('day', isEqualTo: day)
        .where('hourIndex', isEqualTo: hourIndex)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();

    if (scheduleSnap.docs.isEmpty) {
      throw Exception('Bu saatte ders bulunamadı');
    }

    final schedule = scheduleSnap.docs.first.data();
    final lessonName = (schedule['lessonName'] ?? '').toString();
    final lessonId = (schedule['lessonId'] ?? '').toString();

    final teacherId = (schedule['teacherId'] ?? '').toString();
    final teacherIds = (schedule['teacherIds'] is List)
        ? (schedule['teacherIds'] as List)
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];
    final teacherNames = (schedule['teacherNames'] is List)
        ? (schedule['teacherNames'] as List)
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];

    final msg =
        '$className ${_formatDateTr(_selectedDate)} tarihindeki $_selectedHour. dersin yoklaması alınmamıştır. Yoklama alınmasını hatırlatırız.';

    await FirebaseFirestore.instance.collection('notificationRequests').add({
      'type': 'attendance_reminder_teacher',
      'institutionId': widget.institutionId,
      'schoolTypeId': widget.schoolTypeId,
      'periodId': _activeWorkPeriodId,
      'classId': classId,
      'className': className,
      'lessonId': lessonId,
      'lessonName': lessonName,
      'date': _formatDateYmd(_selectedDate),
      'lessonHour': _selectedHour,
      'message': msg,
      'teacherId': teacherId,
      'teacherIds': teacherIds,
      'teacherNames': teacherNames,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'queued',
    });
  }

  Future<void> _sendAttendanceNotificationsToParents(
    Map<String, dynamic> classData,
  ) async {
    if ((_activeWorkPeriodId ?? '').isEmpty) return;

    final classId = (classData['id'] ?? '').toString();
    final className = (classData['className'] ?? '').toString();
    if (classId.isEmpty) return;

    final dateStr = _formatDateYmd(_selectedDate);

    final attendanceSnap = await FirebaseFirestore.instance
        .collection('lessonAttendance')
        .where('periodId', isEqualTo: _activeWorkPeriodId)
        .where('date', isEqualTo: dateStr)
        .where('lessonHour', isEqualTo: _selectedHour)
        .where('classId', isEqualTo: classId)
        .limit(1)
        .get();

    if (attendanceSnap.docs.isEmpty) {
      throw Exception('Bu ders için yoklama kaydı bulunamadı');
    }

    final attendanceDoc = attendanceSnap.docs.first;
    final att = attendanceDoc.data();
    final lessonId = (att['lessonId'] ?? '').toString();
    final lessonName = (att['lessonName'] ?? '').toString();

    final raw = att['studentStatuses'];
    final Map<String, dynamic> statuses = raw is Map
        ? Map<String, dynamic>.from(raw)
        : {};

    final notified = (att['notifiedStudentIds'] is List)
        ? (att['notifiedStudentIds'] as List).map((e) => e.toString()).toSet()
        : <String>{};

    final toNotify = <String, String>{};
    statuses.forEach((k, v) {
      final studentId = k.toString();
      final status = (v ?? '').toString();
      if (studentId.isEmpty) return;
      if (status.isEmpty) return;
      if (status == 'present') return;
      if (notified.contains(studentId)) return;
      toNotify[studentId] = status;
    });

    if (toNotify.isEmpty) {
      throw Exception('Bildirim gönderilecek öğrenci bulunamadı');
    }

    final studentsSnap = await FirebaseFirestore.instance
        .collection('students')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
        .where('classId', isEqualTo: classId)
        .where('isActive', isEqualTo: true)
        .get();

    final studentsById = <String, Map<String, dynamic>>{};
    for (final d in studentsSnap.docs) {
      final data = d.data();
      data['id'] = d.id;
      studentsById[d.id] = data;
    }

    final batch = FirebaseFirestore.instance.batch();
    final notifCol = FirebaseFirestore.instance.collection(
      'notificationRequests',
    );

    final notifiedIds = <String>[];

    for (final entry in toNotify.entries) {
      final studentId = entry.key;
      final status = entry.value;
      final student = studentsById[studentId];
      final studentName = (student?['name'] ?? '').toString();

      final msg =
          'Öğrencimiz ${studentName.isNotEmpty ? studentName : '...'} ${_formatDateTr(_selectedDate)} tarihindeki $_selectedHour. dersine "${_statusTr(status)}".';

      final docRef = notifCol.doc();
      batch.set(docRef, {
        'type': 'attendance_parent',
        'institutionId': widget.institutionId,
        'schoolTypeId': widget.schoolTypeId,
        'periodId': _activeWorkPeriodId,
        'classId': classId,
        'className': className,
        'lessonId': lessonId,
        'lessonName': lessonName,
        'date': dateStr,
        'lessonHour': _selectedHour,
        'studentId': studentId,
        'studentName': studentName,
        'studentStatus': status,
        'message': msg,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'queued',
      });

      notifiedIds.add(studentId);
    }

    batch.update(attendanceDoc.reference, {
      'notifiedStudentIds': FieldValue.arrayUnion(notifiedIds),
      'lastNotifiedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  Future<void> _onSendPressed(
    Map<String, dynamic> classData,
    bool taken,
  ) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      if (taken) {
        await _sendAttendanceNotificationsToParents(classData);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Bildirimler kuyruğa eklendi')));
      } else {
        await _sendReminderToTeacher(classData);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hatırlatma kuyruğa eklendi')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (!mounted) return;
      setState(() => _sending = false);
    }
  }

  Future<bool> _hasAnyScheduleOnDate(DateTime date) async {
    if ((_activeWorkPeriodId ?? '').isEmpty) return false;
    final day = _dayNameTr(date);
    final snap = await FirebaseFirestore.instance
        .collection('classSchedules')
        .where('periodId', isEqualTo: _activeWorkPeriodId)
        .where('day', isEqualTo: day)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  Future<void> _shiftDate(int deltaDays) async {
    final start = _selectedDate;
    DateTime candidate = start.add(Duration(days: deltaDays));

    bool found = false;
    for (int i = 0; i < 60; i++) {
      final ok = await _hasAnyScheduleOnDate(candidate);
      if (ok) {
        found = true;
        break;
      }
      candidate = candidate.add(Duration(days: deltaDays));
    }

    if (!found) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Programda ders olan gün bulunamadı')),
        );
      }
      return;
    }

    setState(() {
      _selectedDate = DateTime(candidate.year, candidate.month, candidate.day);
    });

    _refreshAvailableHoursForSelectedDay();
    await _loadScheduleForSelection();
    await _loadTakenForSelection();
  }

  String _formatDateTr(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  String _formatDateYmd(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _statusTr(String status) {
    switch (status) {
      case 'absent':
        return 'gelmedi';
      case 'late':
        return 'geç geldi';
      case 'excused':
        return 'izinli';
      case 'onDuty':
        return 'görevli';
      case 'reported':
        return 'raporlu';
      case 'present':
        return 'geldi';
      default:
        return status;
    }
  }

  String _dayNameTr(DateTime date) {
    switch (date.weekday) {
      case DateTime.monday:
        return 'Pazartesi';
      case DateTime.tuesday:
        return 'Salı';
      case DateTime.wednesday:
        return 'Çarşamba';
      case DateTime.thursday:
        return 'Perşembe';
      case DateTime.friday:
        return 'Cuma';
      case DateTime.saturday:
        return 'Cumartesi';
      case DateTime.sunday:
        return 'Pazar';
      default:
        return '';
    }
  }

  void _refreshAvailableHoursForSelectedDay() {
    final lessonHours =
        _activeWorkPeriod?['lessonHours'] as Map<String, dynamic>?;
    final dailyCountsRaw = lessonHours != null
        ? (lessonHours['dailyLessonCounts'] as Map<String, dynamic>?)
        : null;
    final day = _dayNameTr(_selectedDate);
    int dayCount = 8;
    if (dailyCountsRaw != null && dailyCountsRaw.containsKey(day)) {
      final v = dailyCountsRaw[day];
      dayCount = v is int ? v : int.tryParse(v.toString()) ?? 8;
    }

    final hours = List.generate(dayCount, (i) => i + 1);
    setState(() {
      _availableHoursForDay = hours;
      if (!_availableHoursForDay.contains(_selectedHour)) {
        _selectedHour = _availableHoursForDay.isNotEmpty
            ? _availableHoursForDay.first
            : 1;
      }
    });
  }

  Map<String, Map<String, dynamic>> _scheduledClasses = {};

  Future<void> _loadScheduleForSelection() async {
    if ((_activeWorkPeriodId ?? '').isEmpty) return;

    setState(() {
      _loadingSchedule = true;
      _noPlanMessage = null;
    });

    try {
      final selectedDayName = _dayNameTr(_selectedDate);
      final targetHourIndex0 = _selectedHour - 1; // 0-based
      final targetHourIndex1 = _selectedHour; // 1-based (potential legacy data)

      // Fetch ALL active schedules for this period to ensure we don't miss anything due to query constraints
      // (e.g. "Salı" vs "Sali" vs "SALI" or index mismatches)
      final periodSnap = await FirebaseFirestore.instance
          .collection('classSchedules')
          .where('periodId', isEqualTo: _activeWorkPeriodId)
          .where('isActive', isEqualTo: true)
          .get();

      final scheduledMap = <String, Map<String, dynamic>>{};
      final scheduledClassIds = <String>{};

      for (final d in periodSnap.docs) {
        final data = d.data();

        // 1. Day Check (Loose Matching)
        final dbDay = (data['day'] ?? '').toString();
        if (!_isSameDay(dbDay, selectedDayName)) continue;

        // 2. Hour Check (Loose Matching: 0-based OR 1-based)
        final hIdxRaw = data['hourIndex'];
        int? hIdx;
        if (hIdxRaw is int)
          hIdx = hIdxRaw;
        else if (hIdxRaw is String)
          hIdx = int.tryParse(hIdxRaw);

        if (hIdx == null) continue;

        // Check if matches 0-based (standard) or 1-based (fallback)
        if (hIdx == targetHourIndex0 || hIdx == targetHourIndex1) {
          final cid = (data['classId'] ?? '').toString();
          if (cid.isNotEmpty) {
            // If multiple entries (e.g. duplicate schedule), last one wins or logic handles it to show *something*
            scheduledMap[cid] = data;
            scheduledClassIds.add(cid);
          }
        }
      }

      if (!mounted) return;

      final visible = _classes.where((c) {
        final cid = (c['id'] ?? '').toString();

        // Strict Check: Must be in matched list
        if (!scheduledClassIds.contains(cid)) return false;

        if (_selectedClassLevel == null) return true;
        final v = c['classLevel'];
        final lvl = v is int ? v : int.tryParse((v ?? '').toString());
        return lvl == _selectedClassLevel;
      }).toList();

      setState(() {
        _scheduledClasses = scheduledMap;
        _visibleClasses = visible;

        if (visible.isEmpty) {
          _noPlanMessage = _selectedClassLevel == null
              ? 'Bu saatte planlanmış ders bulunamadı'
              : 'Bu filtrede planlanmış ders bulunamadı';
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Program yüklenirken hata: $e')));
    } finally {
      if (!mounted) return;
      setState(() => _loadingSchedule = false);
    }
  }

  bool _isSameDay(String dbDay, String selectedDay) {
    if (dbDay == selectedDay) return true;

    final d1 = dbDay
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('İ', 'i')
        .trim();
    final d2 = selectedDay
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('İ', 'i')
        .trim();
    return d1 == d2;
  }

  // ... (Keep existing methods)

  Future<void> _openClassForSelectedSlot(Map<String, dynamic> classData) async {
    final classId = (classData['id'] ?? '').toString();
    if (classId.isEmpty) return;

    // Check if scheduled
    if (_scheduledClasses.containsKey(classId)) {
      final schedule = _scheduledClasses[classId]!;
      final lessonId = (schedule['lessonId'] ?? '').toString();
      final lessonName = (schedule['lessonName'] ?? '').toString();

      if (lessonId.isNotEmpty) {
        _navigateToAttendance(
          classId,
          (classData['className'] ?? '').toString(),
          lessonId,
          lessonName,
        );
        return;
      }
    }
  }

  Future<void> _navigateToAttendance(
    String classId,
    String className,
    String lessonId,
    String lessonName,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClassLessonAttendanceScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          periodId: _activeWorkPeriodId,
          classId: classId,
          lessonId: lessonId,
          className: className,
          lessonName: lessonName,
          initialDate: _selectedDate,
          initialLessonHour: _selectedHour,
          availableLessonHours: [_selectedHour],
        ),
      ),
    );
    await _loadTakenForSelection();
  }

  @override
  Widget build(BuildContext context) {
    final dateText = _formatDateTr(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Yoklama İşlemleri',
              style: TextStyle(
                color: Colors.grey.shade900,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '${widget.schoolTypeName} ${_activeWorkPeriodName != null ? "• $_activeWorkPeriodName" : ""}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'İstatistik',
            icon: Icon(Icons.pie_chart_outline),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AttendanceStatisticsScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 720),
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Container(
                        padding: EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 10,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final isNarrow = constraints.maxWidth < 430;
                                return Column(
                                  children: [
                                    Row(
                                      children: [
                                        IconButton(
                                          onPressed:
                                              _loadingSchedule || _loadingTaken
                                              ? null
                                              : () => _shiftDate(-1),
                                          icon: Icon(
                                            Icons.chevron_left,
                                            color: Colors.blue.shade700,
                                          ),
                                          tooltip: 'Önceki gün',
                                        ),
                                        Expanded(
                                          child: InkWell(
                                            onTap: _pickDate,
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            child: Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 12,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.withOpacity(
                                                  0.08,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.date_range,
                                                    color: Colors.blue.shade700,
                                                  ),
                                                  SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      dateText,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        color: Colors
                                                            .grey
                                                            .shade900,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          onPressed:
                                              _loadingSchedule || _loadingTaken
                                              ? null
                                              : () => _shiftDate(1),
                                          icon: Icon(
                                            Icons.chevron_right,
                                            color: Colors.blue.shade700,
                                          ),
                                          tooltip: 'Sonraki gün',
                                        ),
                                        if (!isNarrow) ...[
                                          SizedBox(width: 10),
                                          _buildClassLevelFilter(),
                                        ],
                                      ],
                                    ),
                                    if (isNarrow) ...[
                                      SizedBox(height: 10),
                                      Align(
                                        alignment: Alignment.center,
                                        child: _buildClassLevelFilter(),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                            SizedBox(height: 12),
                            SizedBox(
                              height: 44,
                              child: _availableHoursForDay.isEmpty
                                  ? Center(
                                      child: Text('Bu gün için ders saati yok'),
                                    )
                                  : Align(
                                      alignment: Alignment.center,
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: _availableHoursForDay.expand((
                                            h,
                                          ) {
                                            final selected = h == _selectedHour;
                                            return [
                                              InkWell(
                                                onTap: () async {
                                                  setState(
                                                    () => _selectedHour = h,
                                                  );
                                                  await _loadScheduleForSelection();
                                                  await _loadTakenForSelection();
                                                },
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                child: Container(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 10,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: selected
                                                        ? Colors.purple.shade700
                                                        : Colors.purple
                                                              .withOpacity(
                                                                0.08,
                                                              ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    '$h. Ders',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      color: selected
                                                          ? Colors.white
                                                          : Colors
                                                                .purple
                                                                .shade700,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(width: 8),
                                            ];
                                          }).toList(),
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: (_noPlanMessage != null)
                          ? Center(
                              child: Text(
                                _noPlanMessage!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            )
                          : _visibleClasses.isEmpty
                          ? Center(
                              child: Text(
                                'Sınıf bulunamadı',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            )
                          : Stack(
                              children: [
                                ListView.builder(
                                  padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                                  itemCount: _visibleClasses.length,
                                  itemBuilder: (context, index) {
                                    final c = _visibleClasses[index];
                                    final classId = (c['id'] ?? '').toString();
                                    final className = (c['className'] ?? '')
                                        .toString();
                                    final taken = _takenClassIds.contains(
                                      classId,
                                    );

                                    // Get scheduled lesson info
                                    final scheduleData =
                                        _scheduledClasses[classId];
                                    final lessonName = scheduleData != null
                                        ? (scheduleData['lessonName'] ?? '')
                                              .toString()
                                        : null;

                                    return InkWell(
                                      onTap: () => _openClassForSelectedSlot(c),
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        margin: EdgeInsets.only(bottom: 10),
                                        padding: EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: taken
                                              ? Colors.green.withOpacity(0.10)
                                              : (lessonName != null
                                                    ? Colors.white
                                                    : Colors.orange.withOpacity(
                                                        0.03,
                                                      )), // Slight tint for unscheduled
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: taken
                                                ? Colors.green.withOpacity(0.25)
                                                : Colors.grey.shade200,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.03,
                                              ),
                                              blurRadius: 10,
                                              offset: Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              backgroundColor: taken
                                                  ? Colors.green.withOpacity(
                                                      0.15,
                                                    )
                                                  : (lessonName != null
                                                        ? Colors.blue.shade50
                                                        : Colors.grey.shade100),
                                              child: Icon(
                                                taken
                                                    ? Icons.check_circle
                                                    : (lessonName != null
                                                          ? Icons.class_outlined
                                                          : Icons
                                                                .school_outlined),
                                                color: taken
                                                    ? Colors.green.shade700
                                                    : (lessonName != null
                                                          ? Colors.blue.shade700
                                                          : Colors
                                                                .grey
                                                                .shade600),
                                              ),
                                            ),
                                            SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    className,
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      color:
                                                          Colors.grey.shade900,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  if (lessonName != null)
                                                    Text(
                                                      lessonName,
                                                      style: TextStyle(
                                                        color: Colors
                                                            .blue
                                                            .shade800,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    )
                                                  else
                                                    Text(
                                                      'Plan Dışı',
                                                      style: TextStyle(
                                                        color: Colors
                                                            .orange
                                                            .shade800,
                                                        fontSize: 12,
                                                        fontStyle:
                                                            FontStyle.italic,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: taken
                                                    ? Colors.green.shade600
                                                    : Colors.grey.shade200,
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                taken ? 'Alındı' : 'Alınmadı',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w900,
                                                  color: taken
                                                      ? Colors.white
                                                      : Colors.grey.shade700,
                                                ),
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            IconButton(
                                              onPressed: _sending
                                                  ? null
                                                  : () => _onSendPressed(
                                                      c,
                                                      taken,
                                                    ),
                                              icon: Icon(
                                                Icons.send_rounded,
                                                size: 18,
                                              ),
                                              color: taken
                                                  ? Colors.green.shade700
                                                  : Colors.blueGrey,
                                              tooltip: taken
                                                  ? 'Veli bildirimi gönder'
                                                  : 'Öğretmene hatırlat',
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                if (_loadingTaken)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    top: 0,
                                    child: LinearProgressIndicator(
                                      minHeight: 2,
                                    ),
                                  ),
                                if (_loadingSchedule)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    top: 0,
                                    child: LinearProgressIndicator(
                                      minHeight: 2,
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

  Future<void> _loadTakenForSelection() async {
    if ((_activeWorkPeriodId ?? '').isEmpty) return;

    setState(() => _loadingTaken = true);
    try {
      final dateStr = _formatDateYmd(_selectedDate);
      final snap = await FirebaseFirestore.instance
          .collection('lessonAttendance')
          .where('periodId', isEqualTo: _activeWorkPeriodId)
          .where('date', isEqualTo: dateStr)
          .where('lessonHour', isEqualTo: _selectedHour)
          .get();

      final ids = <String>{};
      for (final d in snap.docs) {
        final data = d.data();
        final classId = (data['classId'] ?? '').toString();
        if (classId.isNotEmpty) ids.add(classId);
      }

      if (!mounted) return;
      setState(() {
        _takenClassIds = ids;
      });
    } finally {
      if (!mounted) return;
      setState(() => _loadingTaken = false);
    }
  }

  Widget _buildClassLevelFilter() {
    if (_availableClassLevels.isEmpty) {
      return SizedBox.shrink();
    }

    return PopupMenuButton<int>(
      tooltip: 'Sınıf seviyesi filtresi',
      onSelected: (value) async {
        setState(() {
          _selectedClassLevel = value == 0 ? null : value;
        });
        await _loadScheduleForSelection();
        await _loadTakenForSelection();
      },
      itemBuilder: (context) {
        return [
          PopupMenuItem<int>(value: 0, child: Text('Tümü')),
          ..._availableClassLevels.map(
            (lvl) => PopupMenuItem<int>(value: lvl, child: Text('$lvl. Sınıf')),
          ),
        ];
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.filter_list, color: Colors.orange.shade800, size: 18),
            SizedBox(width: 6),
            Text(
              _selectedClassLevel == null
                  ? 'Tümü'
                  : '${_selectedClassLevel!}. Sınıf',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.grey.shade900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
