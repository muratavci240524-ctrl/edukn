import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../services/homework_statistics_service.dart';
import '../../../../models/school/homework_model.dart';
import 'homework_detail_screen.dart';

class HomeworkOperationsScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const HomeworkOperationsScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
  });

  @override
  State<HomeworkOperationsScreen> createState() =>
      _HomeworkOperationsScreenState();
}

class _HomeworkOperationsScreenState extends State<HomeworkOperationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final HomeworkStatisticsService _service = HomeworkStatisticsService();

  // Date Filter
  String _dateMode = 'week'; // 'week', 'month', 'custom'
  // Lesson Filter
  String? _selectedFilterLessonId;

  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();

  // Data
  bool _loading = false;
  List<Homework> _homeworks = [];
  final Map<String, String> _teacherNames = {};
  final List<Map<String, dynamic>> _allTeachers = [];
  final Map<String, String> _classNames = {};
  Map<String, String> _lessonNames = {};
  Map<String, Map<String, dynamic>> _studentInfo =
      {}; // id -> {name, number, class}

  // Risk Filter
  int _consecutiveRiskThreshold = 3;

  // Sorting State
  int _sortColumnIndex = 0;
  bool _sortAscending = true;

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('tr_TR', null);
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _initializeDate();
    _fetchAllData();
  }

  void _initializeDate() {
    _setDateMode('week');
  }

  void _setDateMode(String mode) {
    _dateMode = mode;
    final now = DateTime.now();

    if (mode == 'week') {
      // Start: Monday of current week
      int dayOfWeek = now.weekday; // 1=Mon
      _startDate = now.subtract(Duration(days: dayOfWeek - 1));
      _startDate = DateTime(_startDate.year, _startDate.month, _startDate.day);
      // End: next Sunday
      _endDate = _startDate.add(
        const Duration(days: 6, hours: 23, minutes: 59),
      );
    } else if (mode == 'month') {
      // Start: 1st of month
      _startDate = DateTime(now.year, now.month, 1);
      // End: Last of month
      _endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    }
    // 'custom' maintains current selection
  }

  Future<void> _fetchAllData() async {
    setState(() => _loading = true);
    try {
      // 1. Fetch Homeworks (Fetch ALL then filter in memory to avoid Index Errors)
      final hSnap = await FirebaseFirestore.instance
          .collection('homeworks')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      final allHomeworks = hSnap.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return Homework.fromMap(data);
      }).toList();

      // Filter by Date in Memory
      _homeworks = allHomeworks.where((hw) {
        return hw.createdAt.isAfter(
              _startDate.subtract(const Duration(seconds: 1)),
            ) &&
            hw.createdAt.isBefore(_endDate.add(const Duration(seconds: 1)));
      }).toList();

      // Sort by Date Descending
      _homeworks.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // 2. Resolve Teachers, Classes, Lessons, Students

      // A. Fetch Teachers (Users)
      final uSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      _allTeachers.clear();
      for (var doc in uSnap.docs) {
        final d = doc.data();
        d['id'] = doc.id; // Store Doc ID
        _allTeachers.add(d);

        final name =
            d['fullName'] ?? '${d['firstName'] ?? ''} ${d['lastName'] ?? ''}';
        _teacherNames[doc.id] = name.trim();
        // Also map by uid if exists
        if (d['uid'] != null) _teacherNames[d['uid']] = name.trim();
      }

      // B. Fetch Classes
      final cSnap = await FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();
      for (var doc in cSnap.docs) {
        _classNames[doc.id] =
            (doc.data()['className'] ?? doc.data()['name'] ?? '').toString();
      }

      // C. Fetch Lessons
      final lSnap = await FirebaseFirestore.instance
          .collection('lessons')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();
      for (var doc in lSnap.docs) {
        final data = doc.data();
        _lessonNames[doc.id] =
            (data['name'] ??
                    data['lessonName'] ??
                    'Ders ${doc.id.substring(0, 4)}')
                .toString();
      }

      // D. Fetch Students
      final sSnap = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();
      for (var doc in sSnap.docs) {
        _studentInfo[doc.id] = doc.data();
      }
    } catch (e) {
      debugPrint('Error fetching data: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // Date Navigation Helpers
  void _navigateDate(int direction) {
    if (_dateMode == 'custom') return;

    setState(() {
      if (_dateMode == 'week') {
        _startDate = _startDate.add(Duration(days: 7 * direction));
        _endDate = _endDate.add(Duration(days: 7 * direction));
      } else if (_dateMode == 'month') {
        // Move by month
        final newStart = DateTime(
          _startDate.year,
          _startDate.month + direction,
          1,
        );
        _startDate = newStart;
        _endDate = DateTime(newStart.year, newStart.month + 1, 0, 23, 59, 59);
      }
    });
    _fetchAllData();
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            primaryColor: Colors.deepPurple,
            colorScheme: const ColorScheme.light(primary: Colors.deepPurple),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _dateMode = 'custom';
        _startDate = picked.start;
        _endDate = picked.end.add(const Duration(hours: 23, minutes: 59));
      });
      _fetchAllData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Ödev Yönetimi',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Mode Select
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _dateMode,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.black54),
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
                items: const [
                  DropdownMenuItem(value: 'week', child: Text('Haftalık')),
                  DropdownMenuItem(value: 'month', child: Text('Aylık')),
                  DropdownMenuItem(value: 'custom', child: Text('Özel Tarih')),
                ],
                onChanged: (val) {
                  if (val == 'custom') {
                    _selectDateRange();
                  } else if (val != null) {
                    setState(() {
                      _setDateMode(val);
                    });
                    _fetchAllData();
                  }
                },
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.deepPurple,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.deepPurple,
          tabs: const [
            Tab(text: 'Genel Bakış'),
            Tab(text: 'Öğretmenler'),
            Tab(text: 'Risk Analizi'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildDateHeader(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildOverviewTab(),
                      _buildTeacherStatsTab(),
                      _buildRiskAnalysisTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ... (Date Picker Logic remains similar, just hidden by collapse, assume valid)

  // --- TAB 1: OVERVIEW ---
  Widget _buildOverviewTab() {
    final total = _homeworks
        .length; // Shows total regardless of filter? Or filtered total? UI shows "Toplam Ödev".
    // Let's keep 'total' as raw total for the top card, but use filtered for charts/tables.

    // Filter Logic
    List<Homework> filteredHomeworks = _selectedFilterLessonId == null
        ? List.from(_homeworks)
        : _homeworks
              .where((h) => h.lessonId == _selectedFilterLessonId)
              .toList();

    // Sorting Logic
    filteredHomeworks.sort((a, b) {
      int cmp = 0;
      switch (_sortColumnIndex) {
        case 0: // Ders
          cmp = (_lessonNames[a.lessonId] ?? '').compareTo(
            _lessonNames[b.lessonId] ?? '',
          );
          break;
        case 1: // Sınıf
          cmp = (_classNames[a.classId] ?? '').compareTo(
            _classNames[b.classId] ?? '',
          );
          break;
        case 2: // Ödev Adı
          cmp = a.title.compareTo(b.title);
          break;
        case 3: // Veriliş Tarihi
          cmp = a.assignedDate.compareTo(b.assignedDate);
          break;
        case 4: // Son Kontrol
          cmp = a.dueDate.compareTo(b.dueDate);
          break;
        case 5: // Durum (Orana göre)
          final aRatio = a.targetStudentIds.isEmpty
              ? 0
              : a.studentStatuses.length / a.targetStudentIds.length;
          final bRatio = b.targetStudentIds.isEmpty
              ? 0
              : b.studentStatuses.length / b.targetStudentIds.length;
          cmp = aRatio.compareTo(bRatio);
          break;
      }
      return _sortAscending ? cmp : -cmp;
    });

    final uniqueLessonIds = _homeworks.map((h) => h.lessonId).toSet();

    // Status Counts
    int completed = 0;
    int missing = 0;
    int pending = 0;

    for (var hw in filteredHomeworks) {
      for (var status in hw.studentStatuses.values) {
        if (status == 1)
          completed++;
        else if (status == 2 || status == 3 || status == 4)
          missing++;
        else
          pending++;
      }
      // If empty, treat as pending for all targets?
      if (hw.studentStatuses.isEmpty)
        pending += hw.targetStudentIds.length;
      else if (hw.studentStatuses.length < hw.targetStudentIds.length) {
        pending += (hw.targetStudentIds.length - hw.studentStatuses.length);
      }
    }

    // Chart Data (By Day)
    final dayCounts = List.generate(7, (index) => 0);
    for (var hw in filteredHomeworks) {
      final weekday = hw.createdAt.weekday;
      dayCounts[weekday - 1]++;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats Cards
          Row(
            children: [
              _buildStatCard(
                'Toplam Ödev',
                '$total',
                Icons.assignment,
                Colors.blue,
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                'Öğrenci Teslim',
                '$completed',
                Icons.check_circle,
                Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // PIE CHART & BAR CHART Row (Responsive)
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 900;

              Widget pieWidget = Container(
                height: 240,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Genel Durum',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Expanded(
                      child: PieChart(
                        PieChartData(
                          sections: [
                            PieChartSectionData(
                              color: Colors.green,
                              value: completed.toDouble(),
                              title: completed > 0
                                  ? '${((completed / (completed + missing + pending + 0.1)) * 100).toInt()}%'
                                  : '',
                              radius: 45,
                              titleStyle: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                            PieChartSectionData(
                              color: Colors.red,
                              value: missing.toDouble(),
                              title: missing > 0
                                  ? '${((missing / (completed + missing + pending + 0.1)) * 100).toInt()}%'
                                  : '',
                              radius: 45,
                              titleStyle: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                            PieChartSectionData(
                              color: Colors.grey.shade300,
                              value: pending.toDouble(),
                              title: '',
                              radius: 45,
                            ),
                          ],
                          sectionsSpace: 2,
                          centerSpaceRadius: 30,
                          borderData: FlBorderData(show: false),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.circle, color: Colors.green, size: 8),
                        SizedBox(width: 4),
                        Text('Tam', style: TextStyle(fontSize: 10)),
                        SizedBox(width: 8),
                        Icon(Icons.circle, color: Colors.red, size: 8),
                        SizedBox(width: 4),
                        Text('Eksik', style: TextStyle(fontSize: 10)),
                        SizedBox(width: 8),
                        Icon(Icons.circle, color: Colors.grey, size: 8),
                        SizedBox(width: 4),
                        Text('Bekleyen', style: TextStyle(fontSize: 10)),
                      ],
                    ),
                  ],
                ),
              );

              Widget barWidget = Container(
                height: 240,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Günlük Dağılım',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: BarChart(
                        BarChartData(
                          gridData: FlGridData(show: false),
                          titlesData: FlTitlesData(
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            topTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (val, meta) {
                                  const days = [
                                    'Pzt',
                                    'Sal',
                                    'Çar',
                                    'Per',
                                    'Cum',
                                    'Cmt',
                                    'Paz',
                                  ];
                                  if (val.toInt() >= 0 && val.toInt() < 7) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        days[val.toInt()],
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    );
                                  }
                                  return const Text('');
                                },
                              ),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          barGroups: List.generate(
                            7,
                            (i) => BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: dayCounts[i].toDouble(),
                                  color: dayCounts[i] > 0
                                      ? Colors.deepPurple
                                      : Colors.grey.shade200,
                                  width: 14,
                                  borderRadius: BorderRadius.circular(4),
                                  backDrawRodData: BackgroundBarChartRodData(
                                    show: true,
                                    toY:
                                        (dayCounts.reduce(
                                                  (a, b) => a > b ? a : b,
                                                ) +
                                                1)
                                            .toDouble(),
                                    color: Colors.grey.shade50,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );

              if (isWide) {
                return Row(
                  children: [
                    Expanded(child: pieWidget),
                    const SizedBox(width: 16),
                    Expanded(child: barWidget),
                  ],
                );
              } else {
                return Column(
                  children: [pieWidget, const SizedBox(height: 16), barWidget],
                );
              }
            },
          ),
          const SizedBox(height: 24),
          // --- HEADER & FILTER ROW ---
          Row(
            children: [
              const Text(
                'Son Eklenen Ödevler',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedFilterLessonId,
                    hint: const Text(
                      'Ders Filtrele',
                      style: TextStyle(fontSize: 13),
                    ),
                    icon: const Icon(Icons.filter_list, size: 16),
                    onChanged: (val) =>
                        setState(() => _selectedFilterLessonId = val),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text(
                          'Tüm Dersler',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      ...uniqueLessonIds.map((lid) {
                        final name = _lessonNames[lid] ?? 'Ders';
                        return DropdownMenuItem(
                          value: lid,
                          child: Text(
                            name,
                            style: const TextStyle(fontSize: 13),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // --- RESPONSIVE TABLE ---
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      _buildResponsiveHeaderCell('Ders', 0, 2),
                      _buildResponsiveHeaderCell('Sınıf', 1, 1),
                      _buildResponsiveHeaderCell('Ödev Adı', 2, 3),
                      _buildResponsiveHeaderCell('Veriliş T.', 3, 2),
                      _buildResponsiveHeaderCell('Son Kontrol', 4, 2),
                      _buildResponsiveHeaderCell('Durum', 5, 2),
                      const SizedBox(width: 24),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Rows
                if (filteredHomeworks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      "Kayıt bulunamadı",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                if (filteredHomeworks.isNotEmpty)
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredHomeworks.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final hw = filteredHomeworks[index];
                      final lessonName = _lessonNames[hw.lessonId] ?? '-';
                      final className = _classNames[hw.classId] ?? '-';
                      final now = DateTime.now();

                      int graded = hw.studentStatuses.length;
                      int target = hw.targetStudentIds.length;
                      bool isExpired = now.isAfter(hw.dueDate);

                      Color statusColor = Colors.blue;
                      if (isExpired)
                        statusColor = Colors.red;
                      else if (graded > 0)
                        statusColor = Colors.orange;
                      if (graded > 0 && graded == target)
                        statusColor = Colors.green;

                      return InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  HomeworkDetailScreen(homework: hw),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  lessonName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Expanded(flex: 1, child: Text(className)),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  hw.title,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  DateFormat(
                                    'dd MMM yy',
                                    'tr_TR',
                                  ).format(hw.assignedDate),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  DateFormat(
                                    'dd MMM yy',
                                    'tr_TR',
                                  ).format(hw.dueDate),
                                  style: TextStyle(
                                    color: isExpired
                                        ? Colors.red
                                        : Colors.black,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: statusColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '$graded / $target Kişi',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateHeader() {
    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.deepPurple),
            onPressed: _dateMode == 'custom' ? null : () => _navigateDate(-1),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.deepPurple.shade100),
              boxShadow: [
                BoxShadow(
                  color: Colors.deepPurple.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              _dateMode == 'month'
                  ? DateFormat('MMMM yyyy', 'tr_TR').format(_startDate)
                  : '${DateFormat('d MMM', 'tr_TR').format(_startDate)} - ${DateFormat('d MMM yyyy', 'tr_TR').format(_endDate)}',
              style: TextStyle(
                color: Colors.deepPurple.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.deepPurple),
            onPressed: _dateMode == 'custom' ? null : () => _navigateDate(1),
          ),
          if (_tabController.index == 1 || _tabController.index == 2) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.print, color: Colors.deepPurple),
              onPressed: _tabController.index == 1
                  ? _exportTeacherStats
                  : _exportRiskAnalysis,
              tooltip: 'Excel Raporu İndir',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResponsiveHeaderCell(String label, int index, int flex) {
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () =>
            _onSort(index, _sortColumnIndex == index ? !_sortAscending : true),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              if (_sortColumnIndex == index) ...[
                const SizedBox(width: 4),
                Icon(
                  _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 14,
                  color: Colors.deepPurple,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              title,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // --- TAB 2: TEACHERS ---
  Map<String, Map<String, dynamic>> _calculateTeacherStats() {
    // Aggregation
    final stats =
        <
          String,
          Map<String, dynamic>
        >{}; // docId -> {name, total, graded, uids}

    // 1. Init all teachers
    for (var t in _allTeachers) {
      final docId = t['id'] as String;
      final name = _teacherNames[docId] ?? 'Öğretmen';
      final uids = <String>{docId};
      if (t['uid'] != null) uids.add(t['uid'] as String);

      stats[docId] = {'name': name, 'total': 0, 'graded': 0, 'uids': uids};
    }

    // 2. Count
    for (var hw in _homeworks) {
      String? targetDocId;
      for (var entry in stats.entries) {
        if ((entry.value['uids'] as Set<String>).contains(hw.teacherId)) {
          targetDocId = entry.key;
          break;
        }
      }

      if (targetDocId != null) {
        stats[targetDocId]!['total']++;
        if (hw.studentStatuses.isNotEmpty &&
            hw.studentStatuses.values.where((v) => v > 0).length ==
                hw.targetStudentIds.length) {
          stats[targetDocId]!['graded']++;
        }
      }
    }
    return stats;
  }

  Future<void> _exportTeacherStats() async {
    final stats = _calculateTeacherStats();
    final list = stats.entries.toList();
    list.sort(
      (a, b) => (b.value['total'] as int).compareTo(a.value['total'] as int),
    );

    var excel = Excel.createExcel();
    Sheet sheet = excel['Öğretmenler'];

    // Title
    var titleCell = sheet.cell(CellIndex.indexByString("A1"));
    titleCell.value = TextCellValue(
      "Öğretmen Ödev Raporu (${DateFormat('dd.MM.yyyy').format(_startDate)} - ${DateFormat('dd.MM.yyyy').format(_endDate)})",
    );

    // Headers
    List<String> headers = [
      'Öğretmen Adı',
      'Verilen Ödev',
      'Kontrol Edilen',
      'Kontrol Edilmeyen',
    ];
    for (int i = 0; i < headers.length; i++) {
      var cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 2),
      );
      cell.value = TextCellValue(headers[i]);
    }

    // Data
    for (int i = 0; i < list.length; i++) {
      final data = list[i].value;
      final int total = data['total'];
      final int graded = data['graded'];
      final int notGraded = total - graded;

      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 3))
          .value = TextCellValue(
        data['name'].toString(),
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 3))
          .value = IntCellValue(
        total,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 3))
          .value = IntCellValue(
        graded,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i + 3))
          .value = IntCellValue(
        notGraded,
      );
    }

    final bytes = excel.save();
    if (bytes != null) {
      await FileSaver.instance.saveFile(
        name: 'ogretmen_odev_raporu',
        bytes: Uint8List.fromList(bytes),
        ext: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
    }
  }

  Future<void> _exportRiskAnalysis() async {
    final riskyStudents = _service.calculateStudentRisk(
      _homeworks,
      _consecutiveRiskThreshold,
    );

    // Pre-process data to determine max columns needed
    List<Map<String, dynamic>> rows = [];
    int maxLessons = 0;

    for (var item in riskyStudents) {
      final sid = item['studentId'];
      final count = item['missedCount'];

      final sInfo = _studentInfo[sid] ?? {};
      final name =
          (sInfo['fullName'] ??
                  '${sInfo['firstName'] ?? ''} ${sInfo['lastName'] ?? ''}')
              .toString()
              .trim();
      final className = _classNames[sInfo['classId']] ?? '';

      // Find specific lessons
      final missedHws = _homeworks.where((h) {
        if (!h.targetStudentIds.contains(sid)) return false;
        final status = h.studentStatuses[sid] ?? 0;
        return status == 2 || status == 3 || status == 4;
      }).toList();

      final lessonList = missedHws
          .map((h) => _lessonNames[h.lessonId] ?? '-')
          .toSet()
          .toList();

      if (lessonList.length > maxLessons) maxLessons = lessonList.length;

      rows.add({
        'name': name.isEmpty ? 'Öğrenci #$sid' : name,
        'className': className,
        'count': count,
        'lessons': lessonList,
      });
    }

    var excel = Excel.createExcel();
    Sheet sheet = excel['Risk Analizi'];

    // Title
    var titleCell = sheet.cell(CellIndex.indexByString("A1"));
    titleCell.value = TextCellValue(
      "Risk Analizi Raporu (${DateFormat('dd.MM.yyyy').format(_startDate)} - ${DateFormat('dd.MM.yyyy').format(_endDate)})",
    );

    // Headers
    List<String> headers = ['Öğrenci Adı', 'Sınıf', 'Eksik Ödev Sayısı'];
    for (int k = 1; k <= maxLessons; k++) {
      headers.add('Eksik Ders $k');
    }

    for (int i = 0; i < headers.length; i++) {
      var cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 2),
      );
      cell.value = TextCellValue(headers[i]);
    }

    // Data
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 3))
          .value = TextCellValue(
        row['name'],
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 3))
          .value = TextCellValue(
        row['className'],
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 3))
          .value = IntCellValue(
        row['count'],
      );

      final lessons = row['lessons'] as List<String>;
      for (int k = 0; k < lessons.length; k++) {
        sheet
            .cell(
              CellIndex.indexByColumnRow(columnIndex: 3 + k, rowIndex: i + 3),
            )
            .value = TextCellValue(
          lessons[k],
        );
      }
    }

    final bytes = excel.save();
    if (bytes != null) {
      await FileSaver.instance.saveFile(
        name: 'risk_analizi_raporu',
        bytes: Uint8List.fromList(bytes),
        ext: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
    }
  }

  Widget _buildTeacherStatsTab() {
    final stats = _calculateTeacherStats();
    final list = stats.entries.toList();
    list.sort(
      (a, b) => (b.value['total'] as int).compareTo(a.value['total'] as int),
    );

    if (list.isEmpty) {
      return const Center(child: Text('Kayıtlı öğretmen bulunamadı.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final entry = list[index];
        final total = entry.value['total'] as int;
        final graded = entry.value['graded'] as int;
        final name = entry.value['name'] as String;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.orange.shade50,
                  child: Text(
                    name.isNotEmpty ? name.substring(0, 1) : '?',
                    style: TextStyle(color: Colors.orange.shade800),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: total > 0 ? graded / total : 0,
                        backgroundColor: Colors.grey.shade100,
                        color: Colors.green,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$total Ödev',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '$graded Kontrol',
                      style: const TextStyle(fontSize: 12, color: Colors.green),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- TAB 3: RISK ANALYSIS ---
  Widget _buildRiskAnalysisTab() {
    // NOTE: Risk Analysis usually requires LONGER history than just "Current Week".
    // For this specific tab, we might want to fetch more data if the user asks for "3 consecutive"
    // but the current date range is only 1 week.
    // However, for MVP, we use the loaded `_homeworks`.
    // IF the user wants real "3 consecutive" we probably need last 30 days logic.
    // Let's create a specific fetch for this or warn user "Analiz seçili tarih aralığındaki ödevleri kapsar".

    final riskyStudents = _service.calculateStudentRisk(
      _homeworks,
      _consecutiveRiskThreshold,
    );

    return Column(
      children: [
        // Filter Header
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Risk Filtresi: Ardışık $_consecutiveRiskThreshold Ödev Yapmayanlar',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Slider(
                value: _consecutiveRiskThreshold.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: '$_consecutiveRiskThreshold',
                activeColor: Colors.red,
                onChanged: (val) {
                  setState(() {
                    _consecutiveRiskThreshold = val.toInt();
                  });
                },
              ),
              const Text(
                'Not: Analiz, yukarıda seçili olan Tarih Aralığı içerisindeki ödevlere göre yapılır.',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: riskyStudents.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: Colors.green.shade200,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Riskli öğrenci bulunamadı',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: riskyStudents.length,
                  itemBuilder: (context, index) {
                    final item = riskyStudents[index];
                    final sid = item['studentId'];
                    final count = item['missedCount'];
                    final sInfo = _studentInfo[sid] ?? {};
                    final name =
                        (sInfo['fullName'] ??
                                '${sInfo['firstName'] ?? sInfo['name'] ?? ''} ${sInfo['lastName'] ?? sInfo['surname'] ?? ''}')
                            .trim();
                    final no = sInfo['schoolNumber'] ?? '';
                    // Class name? Need to look up student class.
                    // Student info usually has 'classId'.
                    final className = _classNames[sInfo['classId']] ?? '';

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.red.shade100),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.red.shade50,
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(name.isEmpty ? 'Öğrenci #$sid' : name),
                        subtitle: Text('#$no • $className'),
                        trailing: const Icon(Icons.warning, color: Colors.red),
                        onTap: () => _showRiskDetails(item),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showRiskDetails(Map<String, dynamic> item) {
    final sid = item['studentId'];
    final sInfo = _studentInfo[sid] ?? {};
    final name =
        (sInfo['fullName'] ??
                '${sInfo['firstName'] ?? sInfo['name'] ?? ''} ${sInfo['lastName'] ?? sInfo['surname'] ?? ''}')
            .trim();

    final missedHws = _homeworks.where((h) {
      if (!h.targetStudentIds.contains(sid)) return false;
      final status = h.studentStatuses[sid] ?? 0;
      return status == 2 || status == 3 || status == 4;
    }).toList();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Risk Detayı: $name',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Bu tarih aralığında ${missedHws.length} ödev eksik görünüyor.',
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: missedHws.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final hw = missedHws[index];
                    return ListTile(
                      title: Text(hw.title),
                      subtitle: Text(DateFormat('dd MMM').format(hw.dueDate)),
                      trailing: const Text(
                        'Yapılmadı',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
