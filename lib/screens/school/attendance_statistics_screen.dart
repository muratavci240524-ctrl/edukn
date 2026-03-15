import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/term_service.dart';

class AttendanceStatisticsScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;

  const AttendanceStatisticsScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
  });

  @override
  State<AttendanceStatisticsScreen> createState() => _AttendanceStatisticsScreenState();
}

class _AttendanceStatisticsScreenState extends State<AttendanceStatisticsScreen> {
  bool _loading = true;
  String? _activeWorkPeriodId;

  static const int _allHoursSentinel = 0;
  static const String _allClassSentinel = '__all__';

  int _tabIndex = 0;
  DateTime _selectedDay = DateTime.now();
  DateTimeRange? _customRange;

  List<Map<String, dynamic>> _classes = [];
  String? _selectedClassId;
  int? _selectedLessonHour;

  Map<String, String> _studentNameById = {};

  int _presentCount = 0;
  int _absentCount = 0;
  int _lateCount = 0;
  int _excusedCount = 0;
  int _onDutyCount = 0;
  int _reportedCount = 0;

  List<Map<String, dynamic>> _absentToday = [];
  List<Map<String, dynamic>> _absentLast3Days = [];
  List<Map<String, dynamic>> _absentConsecutive3Days = [];

  List<Map<String, dynamic>> _lateList = [];
  List<Map<String, dynamic>> _excusedList = [];
  List<Map<String, dynamic>> _onDutyList = [];
  List<Map<String, dynamic>> _reportedList = [];

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    _init();
  }

  Widget _buildLessonHourFilter() {
    final hours = List.generate(12, (i) => i + 1);
    return PopupMenuButton<int>(
      tooltip: 'Ders saati filtresi',
      onSelected: (v) async {
        setState(() {
          _selectedLessonHour = v == _allHoursSentinel ? null : v;
        });
        await _loadStats();
      },
      itemBuilder: (context) {
        return [
          PopupMenuItem<int>(
            value: _allHoursSentinel,
            child: Text('Tümü'),
          ),
          ...hours.map(
            (h) => PopupMenuItem<int>(
              value: h,
              child: Text('$h. Ders'),
            ),
          ),
        ];
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.purple.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, color: Colors.purple.shade700, size: 18),
            SizedBox(width: 8),
            Text(
              _selectedLessonHour == null ? 'Ders: Tümü' : 'Ders: ${_selectedLessonHour!}',
              style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey.shade900),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _init() async {
    setState(() => _loading = true);
    try {
      await _loadActivePeriodAndTerm();
      await _loadClasses();
      await _loadStudentsIndex();
      await _loadStats();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadActivePeriodAndTerm() async {
    final periodSnap = await FirebaseFirestore.instance
        .collection('workPeriods')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();

    if (periodSnap.docs.isEmpty) {
      throw Exception('Aktif dönem (workPeriod) bulunamadı');
    }

    _activeWorkPeriodId = periodSnap.docs.first.id;
    await TermService().getActiveTermId();
  }

  Future<void> _loadClasses() async {
    final termId = await TermService().getActiveTermId();

    final snap = await FirebaseFirestore.instance
        .collection('classes')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
        .where('isActive', isEqualTo: true)
        .get();

    final items = snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();

    final filtered = items.where((c) {
      if ((termId ?? '').isEmpty) return true;
      final t = (c['termId'] ?? '').toString();
      return t.isEmpty || t == termId;
    }).toList();

    filtered.sort((a, b) => (a['className'] ?? '').toString().compareTo((b['className'] ?? '').toString()));
    _classes = filtered;
  }

  Future<void> _loadStudentsIndex() async {
    final snap = await FirebaseFirestore.instance
        .collection('students')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
        .where('isActive', isEqualTo: true)
        .get();

    final map = <String, String>{};
    for (final d in snap.docs) {
      final data = d.data();
      final name = (data['name'] ?? '').toString();
      final surname = (data['surname'] ?? '').toString();
      final full = '${name.trim()} ${surname.trim()}'.trim();
      map[d.id] = full.isEmpty ? d.id : full;
    }

    _studentNameById = map;
  }

  DateTime _startOfWeek(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
  }

  DateTime _startOfMonth(DateTime day) {
    return DateTime(day.year, day.month, 1);
  }

  DateTime _endOfWeek(DateTime day) {
    final s = _startOfWeek(day);
    return DateTime(s.year, s.month, s.day + 6, 23, 59, 59, 999);
  }

  DateTime _endOfMonth(DateTime day) {
    final start = _startOfMonth(day);
    final next = DateTime(start.year, start.month + 1, 1);
    return next.subtract(Duration(milliseconds: 1));
  }

  DateTime _addMonths(DateTime day, int delta) {
    final y = day.year;
    final m = day.month + delta;
    return DateTime(y, m, 1);
  }

  DateTime _endOfDay(DateTime day) {
    return DateTime(day.year, day.month, day.day, 23, 59, 59, 999);
  }

  String _formatDateTr(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  String _formatDateYmd(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _monthTr(DateTime d) {
    const months = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    return months[d.month - 1];
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

  bool _isSchoolDay(DateTime date) {
    final name = _dayNameTr(date);
    return name != 'Cumartesi' && name != 'Pazar';
  }

  List<DateTime> _lastNSchoolDays(DateTime day, int n) {
    final list = <DateTime>[];
    DateTime cur = DateTime(day.year, day.month, day.day);
    while (list.length < n) {
      if (_isSchoolDay(cur)) {
        list.add(cur);
      }
      cur = cur.subtract(Duration(days: 1));
    }
    return list;
  }

  Future<void> _loadStats() async {
    if ((_activeWorkPeriodId ?? '').isEmpty) return;

    setState(() {
      _absentToday = [];
      _absentLast3Days = [];
      _absentConsecutive3Days = [];
      _lateList = [];
      _excusedList = [];
      _onDutyList = [];
      _reportedList = [];
    });

    DateTime from;
    DateTime to;

    if (_tabIndex == 0) {
      from = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
      to = _endOfDay(_selectedDay);
    } else if (_tabIndex == 1) {
      from = _startOfWeek(_selectedDay);
      to = _endOfWeek(_selectedDay);
    } else if (_tabIndex == 2) {
      from = _startOfMonth(_selectedDay);
      to = _endOfMonth(_selectedDay);
    } else {
      final r = _customRange;
      if (r == null) {
        from = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
        to = _endOfDay(_selectedDay);
      } else {
        from = DateTime(r.start.year, r.start.month, r.start.day);
        to = _endOfDay(r.end);
      }
    }

    final fromStr = _formatDateYmd(from);
    final toStr = _formatDateYmd(to);

    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('lessonAttendance')
        .where('date', isGreaterThanOrEqualTo: fromStr)
        .where('date', isLessThanOrEqualTo: toStr);
    final snap = await q.get();

    int present = 0;
    int absent = 0;
    int late = 0;
    int excused = 0;
    int onDuty = 0;
    int reported = 0;

    final lateByStudent = <String, int>{};
    final excusedByStudent = <String, int>{};
    final onDutyByStudent = <String, int>{};
    final reportedByStudent = <String, int>{};

    bool matchesHeaderFilters(Map<String, dynamic> data) {
      if ((data['periodId'] ?? '').toString() != (_activeWorkPeriodId ?? '')) return false;
      if ((data['institutionId'] ?? '').toString() != widget.institutionId) return false;
      if ((data['schoolTypeId'] ?? '').toString() != widget.schoolTypeId) return false;
      if ((_selectedClassId ?? '').isNotEmpty && (data['classId'] ?? '').toString() != _selectedClassId) return false;
      if (_selectedLessonHour != null) {
        final lh = data['lessonHour'];
        final h = lh is int ? lh : int.tryParse((lh ?? '').toString());
        if (h != _selectedLessonHour) return false;
      }
      return true;
    }

    for (final d in snap.docs) {
      final data = d.data();
      if (!matchesHeaderFilters(data)) continue;
      final raw = data['studentStatuses'];
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      map.forEach((k, v) {
        final sid = k.toString();
        final s = (v ?? '').toString();
        switch (s) {
          case 'present':
            present++;
            break;
          case 'absent':
            absent++;
            break;
          case 'late':
            late++;
            if (sid.isNotEmpty) {
              lateByStudent[sid] = (lateByStudent[sid] ?? 0) + 1;
            }
            break;
          case 'excused':
            excused++;
            if (sid.isNotEmpty) {
              excusedByStudent[sid] = (excusedByStudent[sid] ?? 0) + 1;
            }
            break;
          case 'onDuty':
            onDuty++;
            if (sid.isNotEmpty) {
              onDutyByStudent[sid] = (onDutyByStudent[sid] ?? 0) + 1;
            }
            break;
          case 'reported':
            reported++;
            if (sid.isNotEmpty) {
              reportedByStudent[sid] = (reportedByStudent[sid] ?? 0) + 1;
            }
            break;
          default:
            break;
        }
      });
    }

    final todayStr = _formatDateYmd(_selectedDay);
    final last3Days = _lastNSchoolDays(_selectedDay, 3);
    final last3Strs = last3Days.map(_formatDateYmd).toList();

    Query<Map<String, dynamic>> qt = FirebaseFirestore.instance
        .collection('lessonAttendance')
        .where('date', isEqualTo: todayStr);
    final todaySnap = await qt.get();

    final absentTodayIds = <String, int>{};
    for (final d in todaySnap.docs) {
      final data = d.data();
      if (!matchesHeaderFilters(data)) continue;
      final raw = data['studentStatuses'];
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      map.forEach((k, v) {
        if ((v ?? '').toString() == 'absent') {
          absentTodayIds[k.toString()] = (absentTodayIds[k.toString()] ?? 0) + 1;
        }
      });
    }

    Query<Map<String, dynamic>> q3 = FirebaseFirestore.instance
        .collection('lessonAttendance')
        .where('date', whereIn: last3Strs);
    final last3Snap = await q3.get();

    final absentCountByStudentByDay = <String, Map<String, int>>{};
    for (final d in last3Snap.docs) {
      final data = d.data();
      if (!matchesHeaderFilters(data)) continue;
      final date = (data['date'] ?? '').toString();
      final raw = data['studentStatuses'];
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      map.forEach((k, v) {
        if ((v ?? '').toString() == 'absent') {
          final sid = k.toString();
          absentCountByStudentByDay.putIfAbsent(sid, () => {});
          absentCountByStudentByDay[sid]![date] = (absentCountByStudentByDay[sid]![date] ?? 0) + 1;
        }
      });
    }

    final last3Any = <String, int>{};
    final consecutive3 = <String, int>{};
    for (final entry in absentCountByStudentByDay.entries) {
      final sid = entry.key;
      final perDay = entry.value;

      int sum = 0;
      bool allThree = true;
      for (final ds in last3Strs) {
        final c = perDay[ds] ?? 0;
        sum += c;
        if (c == 0) allThree = false;
      }

      if (sum > 0) {
        last3Any[sid] = sum;
      }
      if (allThree) {
        consecutive3[sid] = sum;
      }
    }

    List<Map<String, dynamic>> mapToList(Map<String, int> m) {
      final list = m.entries
          .map((e) => {
                'studentId': e.key,
                'name': _studentNameById[e.key] ?? e.key,
                'count': e.value,
              })
          .toList();
      list.sort((a, b) => (b['count'] as int).compareTo((a['count'] as int)));
      return list;
    }

    setState(() {
      _presentCount = present;
      _absentCount = absent;
      _lateCount = late;
      _excusedCount = excused;
      _onDutyCount = onDuty;
      _reportedCount = reported;

      _absentToday = mapToList(absentTodayIds);
      _absentLast3Days = mapToList(last3Any);
      _absentConsecutive3Days = mapToList(consecutive3);

      _lateList = mapToList(lateByStudent);
      _excusedList = mapToList(excusedByStudent);
      _onDutyList = mapToList(onDutyByStudent);
      _reportedList = mapToList(reportedByStudent);
    });
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _selectedDay = DateTime(picked.year, picked.month, picked.day);
    });
    await _loadStats();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _customRange,
    );
    if (picked == null) return;
    setState(() {
      _customRange = picked;
      _tabIndex = 3;
    });
    await _loadStats();
  }

  Future<void> _shiftPeriod(int direction) async {
    if (_tabIndex == 0) {
      setState(() {
        _selectedDay = _selectedDay.add(Duration(days: direction));
      });
      await _loadStats();
      return;
    }

    if (_tabIndex == 1) {
      setState(() {
        _selectedDay = _selectedDay.add(Duration(days: 7 * direction));
      });
      await _loadStats();
      return;
    }

    if (_tabIndex == 2) {
      setState(() {
        _selectedDay = _addMonths(_selectedDay, direction);
      });
      await _loadStats();
      return;
    }

    if (_tabIndex == 3) {
      if (_customRange == null) {
        await _pickRange();
        return;
      }

      final len = _customRange!.duration.inDays + 1;
      final newStart = _customRange!.start.add(Duration(days: len * direction));
      final newEnd = _customRange!.end.add(Duration(days: len * direction));
      setState(() {
        _customRange = DateTimeRange(start: newStart, end: newEnd);
      });
      await _loadStats();
    }
  }

  String _periodLabel() {
    if (_tabIndex == 0) {
      return _formatDateTr(_selectedDay);
    }
    if (_tabIndex == 1) {
      final s = _startOfWeek(_selectedDay);
      final e = DateTime(s.year, s.month, s.day + 6);
      return '${_formatDateTr(s)} - ${_formatDateTr(e)}';
    }
    if (_tabIndex == 2) {
      return '${_monthTr(_selectedDay)} ${_selectedDay.year}';
    }
    final r = _customRange;
    if (r == null) return 'Aralık seç';
    return '${_formatDateTr(r.start)} - ${_formatDateTr(r.end)}';
  }

  Future<void> _onPeriodPressed() async {
    if (_tabIndex == 0) {
      await _pickDay();
      return;
    }

    if (_tabIndex == 1) {
      await _pickDay();
      return;
    }

    if (_tabIndex == 2) {
      final picked = await showDatePicker(
        context: context,
        initialDate: _selectedDay,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (picked == null) return;
      setState(() {
        _selectedDay = DateTime(picked.year, picked.month, 1);
      });
      await _loadStats();
      return;
    }

    await _pickRange();
  }

  Widget _buildClassFilter() {
    return PopupMenuButton<String>(
      tooltip: 'Sınıf filtresi',
      onSelected: (v) async {
        setState(() {
          _selectedClassId = v == _allClassSentinel ? null : v;
        });
        await _loadStats();
      },
      itemBuilder: (context) {
        return [
          PopupMenuItem<String>(
            value: _allClassSentinel,
            child: Text('Tümü'),
          ),
          ..._classes.map((c) {
            final id = (c['id'] ?? '').toString();
            final name = (c['className'] ?? '').toString();
            return PopupMenuItem<String>(
              value: id.isEmpty ? _allClassSentinel : id,
              child: Text(name.isEmpty ? id : name),
            );
          }),
        ];
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list, color: Colors.orange.shade800, size: 18),
            SizedBox(width: 8),
            Text(
              _selectedClassId == null
                  ? 'Sınıf: Tümü'
                  : 'Sınıf: ${( _classes.firstWhere((e) => (e['id'] ?? '').toString() == _selectedClassId, orElse: () => {'className': _selectedClassId})['className'] ?? _selectedClassId).toString()}',
              style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey.shade900),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _presentCount + _absentCount + _lateCount + _excusedCount + _onDutyCount + _reportedCount;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Yoklama İstatistikleri',
              style: TextStyle(color: Colors.grey.shade900, fontSize: 18, fontWeight: FontWeight.w800),
            ),
            Text(
              widget.schoolTypeName,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 900),
                child: RefreshIndicator(
                  onRefresh: _loadStats,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 20),
                    children: [
                      Container(
                        padding: EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: Offset(0, 6)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: SegmentedButton<int>(
                                      showSelectedIcon: false,
                                      segments: const [
                                        ButtonSegment<int>(value: 0, label: Text('Gün')),
                                        ButtonSegment<int>(value: 1, label: Text('Hafta')),
                                        ButtonSegment<int>(value: 2, label: Text('Ay')),
                                        ButtonSegment<int>(value: 3, label: Text('Özel')),
                                      ],
                                      selected: {_tabIndex},
                                      onSelectionChanged: (s) async {
                                        final v = s.first;
                                        setState(() => _tabIndex = v);
                                        await _loadStats();
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            Row(
                              children: [
                                IconButton(
                                  onPressed: () => _shiftPeriod(-1),
                                  icon: Icon(Icons.chevron_left, color: Colors.blue.shade700),
                                  tooltip: 'Geri',
                                ),
                                Expanded(
                                  child: InkWell(
                                    onTap: _onPeriodPressed,
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.event, color: Colors.blue.shade700),
                                          SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              _periodLabel(),
                                              style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey.shade900),
                                            ),
                                          ),
                                          Icon(Icons.edit, size: 18, color: Colors.blue.shade700),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _shiftPeriod(1),
                                  icon: Icon(Icons.chevron_right, color: Colors.blue.shade700),
                                  tooltip: 'İleri',
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            Align(
                              alignment: Alignment.center,
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _buildLessonHourFilter(),
                                  _buildClassFilter(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 12),
                      Container(
                        padding: EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: Offset(0, 6)),
                          ],
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 110,
                              height: 110,
                              child: CustomPaint(
                                painter: _DonutPainter(
                                  present: _presentCount,
                                  absent: _absentCount,
                                  late: _lateCount,
                                  excused: _excusedCount,
                                  onDuty: _onDutyCount,
                                  reported: _reportedCount,
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        total.toString(),
                                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                                      ),
                                      Text(
                                        'Kayıt',
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                children: [
                                  _LegendRow(color: Colors.green.shade600, label: 'Geldi', value: _presentCount),
                                  _LegendRow(color: Colors.red.shade600, label: 'Gelmedi', value: _absentCount),
                                  _LegendRow(color: Colors.orange.shade700, label: 'Geç', value: _lateCount),
                                  _LegendRow(color: Colors.blue.shade700, label: 'İzinli', value: _excusedCount),
                                  _LegendRow(color: Colors.indigo.shade700, label: 'Görevli', value: _onDutyCount),
                                  _LegendRow(color: Colors.purple.shade700, label: 'Raporlu', value: _reportedCount),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 12),
                      _Section(
                        title: 'Bugün gelmeyenler',
                        subtitle: 'Sadece "gelmedi" olarak işaretlenenler',
                        items: _absentToday,
                      ),
                      SizedBox(height: 12),
                      _Section(
                        title: 'Geç gelenler',
                        subtitle: 'Seçili aralıkta "geç" işaretlenenler',
                        items: _lateList,
                      ),
                      SizedBox(height: 12),
                      _Section(
                        title: 'İzinliler',
                        subtitle: 'Seçili aralıkta "izinli" işaretlenenler',
                        items: _excusedList,
                      ),
                      SizedBox(height: 12),
                      _Section(
                        title: 'Görevliler',
                        subtitle: 'Seçili aralıkta "görevli" işaretlenenler',
                        items: _onDutyList,
                      ),
                      SizedBox(height: 12),
                      _Section(
                        title: 'Raporlular',
                        subtitle: 'Seçili aralıkta "raporlu" işaretlenenler',
                        items: _reportedList,
                      ),
                      SizedBox(height: 12),
                      _Section(
                        title: 'Son 3 okul günü (en az 1 kez gelmeyen)',
                        subtitle: 'Son 3 gün: ${_lastNSchoolDays(_selectedDay, 3).map(_formatDateTr).join(' / ')}',
                        items: _absentLast3Days,
                      ),
                      SizedBox(height: 12),
                      _Section(
                        title: 'Son 3 okul günü ardışık gelmeyen',
                        subtitle: '3 günün hepsinde en az 1 derste "gelmedi"',
                        items: _absentConsecutive3Days,
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final int value;

  const _LegendRow({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: Colors.grey.shade800))),
          Text(value.toString(), style: TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> items;

  const _Section({
    required this.title,
    required this.subtitle,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey.shade900)),
          SizedBox(height: 2),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          SizedBox(height: 10),
          if (items.isEmpty)
            Text('Kayıt yok', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w700))
          else
            ...items.take(40).map((e) {
              return Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        (e['name'] ?? '').toString(),
                        style: TextStyle(fontWeight: FontWeight.w800, color: Colors.grey.shade800),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${e['count']}',
                        style: TextStyle(fontWeight: FontWeight.w900, color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              );
            }),
          if (items.length > 40)
            Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'İlk 40 kayıt gösteriliyor',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final int present;
  final int absent;
  final int late;
  final int excused;
  final int onDuty;
  final int reported;

  _DonutPainter({
    required this.present,
    required this.absent,
    required this.late,
    required this.excused,
    required this.onDuty,
    required this.reported,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = present + absent + late + excused + onDuty + reported;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;

    final stroke = 14.0;
    final rect = Rect.fromCircle(center: center, radius: radius - stroke / 2);

    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Colors.grey.withOpacity(0.15)
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi, false, bgPaint);

    if (total <= 0) return;

    double start = -math.pi / 2;

    void drawSlice(int value, Color color) {
      if (value <= 0) return;
      final sweep = (value / total) * 2 * math.pi;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, start, sweep, false, p);
      start += sweep;
    }

    drawSlice(present, Colors.green.shade600);
    drawSlice(absent, Colors.red.shade600);
    drawSlice(late, Colors.orange.shade700);
    drawSlice(excused, Colors.blue.shade700);
    drawSlice(onDuty, Colors.indigo.shade700);
    drawSlice(reported, Colors.purple.shade700);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return present != oldDelegate.present ||
        absent != oldDelegate.absent ||
        late != oldDelegate.late ||
        excused != oldDelegate.excused ||
        onDuty != oldDelegate.onDuty ||
        reported != oldDelegate.reported;
  }
}
