import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../../services/pdf_service.dart';
import '../../../models/school/duty_model.dart';

class DutyProgramDetailScreen extends StatefulWidget {
  final String periodId;
  final String periodName;
  final String institutionId;

  const DutyProgramDetailScreen({
    Key? key,
    required this.periodId,
    required this.periodName,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<DutyProgramDetailScreen> createState() =>
      _DutyProgramDetailScreenState();
}

class _DutyProgramDetailScreenState extends State<DutyProgramDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Calendar Data
  List<DutyLocation> _locations = [];
  Map<String, DutyScheduleItem> _matrix = {}; // key: "locId_day"
  bool _isLoading = false;
  late DateTime _selectedWeekStart;

  // Statistics Data
  List<DutyScheduleItem> _statsItems = [];
  List<QueryDocumentSnapshot> _teachers = []; // Cache teachers
  late DateTime _statsStartDate;
  late DateTime _statsEndDate;
  bool _isStatsLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // 1. Calendar: Current Week's Monday
    final now = DateTime.now();
    _selectedWeekStart = now.subtract(Duration(days: now.weekday - 1));
    _selectedWeekStart = DateTime(
      _selectedWeekStart.year,
      _selectedWeekStart.month,
      _selectedWeekStart.day,
    );

    // 2. Stats: Current Month
    _statsStartDate = DateTime(now.year, now.month, 1);
    _statsEndDate = DateTime(now.year, now.month + 1, 0); // Last day of month

    _loadData(); // Load Calendar & Teachers
    _loadStatsData(); // Load Stats
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- Calendar Loading ---
  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      // 1. Load Teachers (if not loaded)
      if (_teachers.isEmpty) {
        final userSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('type', whereIn: ['teacher', 'staff', 'admin'])
            .get();
        _teachers = userSnap.docs;
      }

      // 2. Load Locations (shared)
      if (_locations.isEmpty) {
        final locSnap = await FirebaseFirestore.instance
            .collection('dutyLocations')
            .where('institutionId', isEqualTo: widget.institutionId)
            .get();
        _locations = locSnap.docs.map((d) {
          final data = d.data();
          data['id'] = d.id;
          return DutyLocation.fromMap(data);
        }).toList();
      }

      // 3. Load Items for Selected Week
      final weekStr = _selectedWeekStart.toIso8601String();
      final itemsSnap = await FirebaseFirestore.instance
          .collection('dutyScheduleItems')
          .where('periodId', isEqualTo: widget.periodId)
          .where('weekStart', isEqualTo: weekStr)
          .get();

      _matrix.clear();
      for (var doc in itemsSnap.docs) {
        final item = DutyScheduleItem.fromMap(doc.data(), doc.id);
        final key = '${item.locationId}_${item.dayOfWeek}';
        _matrix[key] = item;
      }
    } catch (e) {
      print('Error loading calendar data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- Stats Loading ---
  Future<void> _loadStatsData() async {
    if (mounted) setState(() => _isStatsLoading = true);
    try {
      // Query items where weekStart is within range
      // Query items where weekStart is within range
      // NOTE: We filter by date CLIENT-SIDE to avoid creating a Composite Index
      // for (periodId + weekStart). This ensures immediate functionality.
      final itemsSnap = await FirebaseFirestore.instance
          .collection('dutyScheduleItems')
          .where('periodId', isEqualTo: widget.periodId)
          .get();

      final filterEnd = _statsEndDate.add(const Duration(days: 1));

      _statsItems = itemsSnap.docs
          .map((d) => DutyScheduleItem.fromMap(d.data(), d.id))
          .where((item) {
            if (item.weekStart == null) return false;
            // Compare DateTime objects directly
            return item.weekStart!.compareTo(_statsStartDate) >= 0 &&
                item.weekStart!.compareTo(filterEnd) < 0;
          })
          .toList();
    } catch (e) {
      print('Error loading stats data: $e');
    } finally {
      if (mounted) setState(() => _isStatsLoading = false);
    }
  }

  void _changeWeek(int weeks) {
    setState(() {
      _selectedWeekStart = _selectedWeekStart.add(Duration(days: weeks * 7));
    });
    _loadData();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedWeekStart,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('tr', 'TR'),
    );
    if (picked != null) {
      setState(() {
        _selectedWeekStart = picked.subtract(
          Duration(days: picked.weekday - 1),
        );
        _selectedWeekStart = DateTime(
          _selectedWeekStart.year,
          _selectedWeekStart.month,
          _selectedWeekStart.day,
        );
      });
      _loadData();
    }
  }

  // Pick Range for Stats
  Future<void> _selectStatsDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(
        start: _statsStartDate,
        end: _statsEndDate,
      ),
      locale: const Locale('tr', 'TR'),
      saveText: 'Seç',
    );
    if (picked != null) {
      setState(() {
        _statsStartDate = DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        );
        _statsEndDate = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
        );
      });
      _loadStatsData();
    }
  }

  Future<void> _printReport() async {
    // If we are on stats tab, print stats
    if (_tabController.index == 1) {
      await _printStatsReport();
      return;
    }

    final pdfService = PdfService();
    final dateFormat = DateFormat('dd.MM.yyyy', 'tr_TR');
    final weekStartStr = dateFormat.format(_selectedWeekStart);
    final weekEndStr = dateFormat.format(
      _selectedWeekStart.add(const Duration(days: 6)),
    );

    // Determine active days
    Set<int> activeDayIndices = {};
    for (var loc in _locations) {
      activeDayIndices.addAll(loc.activeDays);
    }
    List<int> sortedDays = activeDayIndices.toList()..sort();

    // Headers
    List<String> headers = ['NÖBET YERİ'];
    for (var d in sortedDays) {
      headers.add(_getDayName(d));
    }

    // Rows
    List<List<String>> rows = [];
    for (var loc in _locations) {
      List<String> row = [loc.name];
      for (var d in sortedDays) {
        final key = '${loc.id}_$d';
        final item = _matrix[key];
        row.add(item?.teacherName ?? '');
      }
      rows.add(row);
    }

    final pdfData = await pdfService.generateDutySchedulePdf(
      periodName: widget.periodName,
      weekRange: '$weekStartStr - $weekEndStr',
      days: headers,
      rows: rows,
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdfData,
      name: 'Nobet_Cizelgesi_$weekStartStr',
    );
  }

  Future<void> _printStatsReport() async {
    final pdfService = PdfService();
    final dateFormat = DateFormat('dd.MM.yyyy', 'tr_TR');
    final rangeStr =
        '${dateFormat.format(_statsStartDate)} - ${dateFormat.format(_statsEndDate)}';

    // Prepare Data
    final userSnap = await FirebaseFirestore.instance
        .collection('users')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('type', whereIn: ['teacher', 'staff', 'admin'])
        .get();

    final teachers = userSnap.docs;
    List<Map<String, dynamic>> stats = [];

    for (var t in teachers) {
      final tid = t.id;
      final tName = t.data()['fullName'] ?? t.data()['name'] ?? 'İsimsiz';

      int total = 0;
      Map<String, int> locCounts = {};
      for (var l in _locations) locCounts[l.id] = 0;

      for (var item in _statsItems) {
        if (item.teacherId == tid) {
          total++;
          locCounts[item.locationId] = (locCounts[item.locationId] ?? 0) + 1;
        }
      }

      if (total > 0 || true) {
        stats.add({'name': tName, 'total': total, 'locCounts': locCounts});
      }
    }

    stats.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));

    // Pdf Headers
    List<String> headers = ['Öğretmen', 'Toplam'];
    for (var l in _locations) headers.add(l.name);

    // Pdf Rows
    List<List<String>> rows = [];
    for (var s in stats) {
      List<String> row = [s['name'], s['total'].toString()];
      final locs = s['locCounts'] as Map<String, int>;
      for (var l in _locations) {
        row.add((locs[l.id] ?? 0).toString());
      }
      rows.add(row);
    }

    final pdfData = await pdfService.generateDutyStatsPdf(
      periodName: widget.periodName,
      dateRange: rangeStr,
      headers: headers,
      rows: rows,
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdfData,
      name: 'Nobet_Istatistikleri_$rangeStr',
    );
  }

  @override
  Widget build(BuildContext context) {
    final weekEnd = _selectedWeekStart.add(const Duration(days: 6));
    final dateFormat = DateFormat('dd MMM yyyy', 'tr_TR');
    final dateRangeStr =
        '${dateFormat.format(_selectedWeekStart)} - ${dateFormat.format(weekEnd)}';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Nöbet Programı',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        actions: [
          IconButton(
            tooltip: 'Yazdır',
            icon: const Icon(Icons.print, color: Color(0xFF64748B)),
            onPressed: _printReport,
          ),
          if (_tabController.index == 0)
            IconButton(
              tooltip: 'Bu Haftayı Temizle',
              icon: const Icon(Icons.delete_sweep, color: Colors.red),
              onPressed: _showClearAllDialog,
            ),
          IconButton(
            tooltip: 'Tarih Seç',
            icon: const Icon(
              Icons.calendar_month_rounded,
              color: Color(0xFF4F46E5),
            ),
            onPressed: () {
              if (_tabController.index == 0) {
                _selectDate();
              } else {
                _selectStatsDateRange();
              }
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Column(
            children: [
              // Week Navigator
              if (_tabController.index == 0)
                Container(
                  height: 40,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.chevron_left,
                          color: Color(0xFF64748B),
                        ),
                        onPressed: () => _changeWeek(-1),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          dateRangeStr,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.chevron_right,
                          color: Color(0xFF64748B),
                        ),
                        onPressed: () => _changeWeek(1),
                      ),
                    ],
                  ),
                ),
              // Tabs
              TabBar(
                controller: _tabController,
                labelColor: const Color(0xFF4F46E5),
                unselectedLabelColor: const Color(0xFF94A3B8),
                indicatorColor: const Color(0xFF4F46E5),
                indicatorWeight: 3,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                onTap: (index) => setState(() {}),
                tabs: const [
                  Tab(text: 'Nöbet Atamaları'),
                  Tab(text: 'İstatistikler'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildCalendarView(),
          _buildStatisticsView(),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: _showAutoDistributeCall,
              backgroundColor: const Color(0xFFEF4444),
              icon: const Icon(Icons.autorenew, color: Colors.white),
              label: const Text(
                'Yeni Atama (Otomatik)',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Calendar View
  // ---------------------------------------------------------------------------
  Widget _buildCalendarView() {
    if (_locations.isEmpty) {
      return const Center(
        child: Text(
          'Tanımlı nöbet yeri bulunamadı. Ayarlardan nöbet yeri ekleyiniz.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 900) {
          return _buildDesktopTable();
        } else {
          return _buildMobileList();
        }
      },
    );
  }

  // Desktop Table
  Widget _buildDesktopTable() {
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

    // Determine which days need to be shown (if ANY location uses it)
    Set<int> activeDayIndices = {};
    for (var loc in _locations) {
      activeDayIndices.addAll(loc.activeDays);
    }
    List<int> visibleDays = activeDayIndices.toList()..sort();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topCenter, // Center table horizontally
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: MaterialStateProperty.all(
                  const Color(0xFFF1F5F9),
                ),
                dataRowHeight: 72,
                columnSpacing: 24,
                horizontalMargin: 32,
                headingTextStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF334155),
                  fontSize: 13,
                ),
                columns: [
                  const DataColumn(label: Text('NÖBET YERİ')),
                  ...visibleDays.map(
                    (i) => DataColumn(label: Text(dayNames[i].toUpperCase())),
                  ),
                ],
                rows: _locations.asMap().entries.map((entry) {
                  final index = entry.key;
                  final loc = entry.value;
                  final isEven = index % 2 == 0;

                  return DataRow(
                    color: MaterialStateProperty.all(
                      isEven ? Colors.white : const Color(0xFFF8FAFC),
                    ),
                    cells: [
                      DataCell(
                        Container(
                          constraints: const BoxConstraints(maxWidth: 150),
                          child: Text(
                            loc.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ),
                      ...visibleDays.map((day) {
                        if (!loc.activeDays.contains(day)) {
                          return DataCell(
                            Container(
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.block,
                                size: 16,
                                color: Color(0xFFE2E8F0),
                              ),
                            ),
                          );
                        }
                        return _buildCell(loc, day);
                      }),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Mobile List
  Widget _buildMobileList() {
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
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 7,
      itemBuilder: (context, index) {
        final day = index + 1;
        final activeLocs = _locations
            .where((l) => l.activeDays.contains(day))
            .toList();
        if (activeLocs.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                dayNames[day],
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4F46E5),
                  fontSize: 16,
                ),
              ),
            ),
            ...activeLocs.map((loc) {
              final item = _matrix['${loc.id}_$day'];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  title: Text(
                    loc.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: loc.startTime.isNotEmpty
                      ? Text(
                          '${loc.startTime} - ${loc.endTime}',
                          style: const TextStyle(fontSize: 12),
                        )
                      : null,
                  trailing: item != null
                      ? Chip(
                          label: Text(
                            item.teacherName,
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: const Color(0xFFEEF2FF),
                        )
                      : const Icon(
                          Icons.add_circle_outline,
                          color: Colors.grey,
                        ),
                  onTap: () => _showAssignDialog(loc, day, item?.teacherId),
                ),
              );
            }).toList(),
          ],
        );
      },
    );
  }

  DataCell _buildCell(DutyLocation loc, int day) {
    final item = _matrix['${loc.id}_$day'];
    return DataCell(
      InkWell(
        onTap: () => _showAssignDialog(loc, day, item?.teacherId),
        child: Container(
          width: double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(8),
          child: item != null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: const Color(0xFF4F46E5),
                      child: Text(
                        item.teacherName.isNotEmpty ? item.teacherName[0] : '?',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.teacherName,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                )
              : const Icon(Icons.add, color: Color(0xFFCBD5E1)),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Statistics View
  // ---------------------------------------------------------------------------
  Widget _buildStatisticsView() {
    if (_isStatsLoading || (_teachers.isEmpty && _isLoading)) {
      return const Center(child: CircularProgressIndicator());
    }

    final dateFormat = DateFormat('dd MMM yyyy', 'tr_TR');

    // Prepare Data
    List<Map<String, dynamic>> stats = [];

    for (var t in _teachers) {
      final tid = t.id;
      final tData = t.data() as Map<String, dynamic>;
      final tName = tData['fullName'] ?? tData['name'] ?? 'İsimsiz';

      int total = 0;
      Map<String, int> locCounts = {};
      for (var l in _locations) {
        locCounts[l.id] = 0;
      }

      for (var item in _statsItems) {
        if (item.teacherId == tid) {
          total++;
          locCounts[item.locationId] = (locCounts[item.locationId] ?? 0) + 1;
        }
      }

      if (total > 0 || true) {
        stats.add({'name': tName, 'total': total, 'locCounts': locCounts});
      }
    }

    // Sort by Total Descending
    stats.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 900;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Filters Row
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Date Range
                    InkWell(
                      onTap: _selectStatsDateRange,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: Color(0xFF64748B),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${dateFormat.format(_statsStartDate)} - ${dateFormat.format(_statsEndDate)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF334155),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.arrow_drop_down,
                              color: Color(0xFF64748B),
                            ),
                          ],
                        ),
                      ),
                    ),

                    IconButton(
                      tooltip: 'Raporu Yazdır',
                      icon: const Icon(Icons.print_outlined),
                      onPressed: _printStatsReport,
                    ),
                  ],
                ),
              ),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                      child: Row(
                        children: [
                          if (isMobile)
                            const SizedBox(
                              width: 48,
                              child: Center(
                                child: Text(
                                  'DETAY',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ),

                          Expanded(
                            flex: 3,
                            child: Text(
                              'ÖRETMEN',
                              style: TextStyle(
                                color: const Color(0xFF64748B),
                                fontWeight: FontWeight.bold,
                                fontSize: isMobile ? 11 : 12,
                              ),
                            ),
                          ),

                          Expanded(
                            child: Center(
                              child: Text(
                                'TOPLAM',
                                style: TextStyle(
                                  color: const Color(0xFF64748B),
                                  fontWeight: FontWeight.bold,
                                  fontSize: isMobile ? 11 : 12,
                                ),
                              ),
                            ),
                          ),

                          if (!isMobile)
                            ..._locations.map(
                              (l) => Expanded(
                                child: Center(
                                  child: Tooltip(
                                    message: l.name,
                                    child: Text(
                                      l.name.length > 5
                                          ? '${l.name.substring(0, 4)}..'
                                          : l.name.toUpperCase(),
                                      style: const TextStyle(
                                        color: Color(0xFF64748B),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Rows
                    ...stats.map((s) {
                      final total = s['total'] as int;
                      final locs = s['locCounts'] as Map<String, int>;

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Color(0xFFF1F5F9)),
                          ),
                        ),
                        child: Row(
                          children: [
                            if (isMobile)
                              SizedBox(
                                width: 48,
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.info_outline_rounded,
                                    color: Color(0xFF64748B),
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      _showMobileStatDetail(s['name'], locs),
                                ),
                              ),

                            Expanded(
                              flex: 3,
                              child: Text(
                                s['name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF334155),
                                  fontSize: 13,
                                ),
                              ),
                            ),

                            Expanded(
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: total > 0
                                        ? const Color(0xFFDCFCE7)
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    total.toString(),
                                    style: TextStyle(
                                      color: total > 0
                                          ? const Color(0xFF166534)
                                          : Colors.grey.shade400,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            if (!isMobile)
                              ..._locations.map((l) {
                                final count = locs[l.id] ?? 0;
                                return Expanded(
                                  child: Center(
                                    child: Text(
                                      count > 0 ? count.toString() : '-',
                                      style: TextStyle(
                                        color: count > 0
                                            ? const Color(0xFF334155)
                                            : Colors.grey.shade300,
                                        fontWeight: count > 0
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMobileStatDetail(String name, Map<String, int> locCounts) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children:
              _locations
                  .where((l) => (locCounts[l.id] ?? 0) > 0)
                  .map((l) {
                    return ListTile(
                      dense: true,
                      title: Text(l.name),
                      trailing: CircleAvatar(
                        radius: 12,
                        backgroundColor: const Color(0xFFDCFCE7),
                        child: Text(
                          locCounts[l.id].toString(),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF166534),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  })
                  .toList()
                  .isEmpty
              ? [const Text('Henüz nöbet atanmamış.')]
              : _locations
                    .where((l) => (locCounts[l.id] ?? 0) > 0)
                    .map(
                      (l) => ListTile(
                        dense: true,
                        title: Text(l.name),
                        trailing: Text(
                          '${locCounts[l.id]}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    )
                    .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Logic: Assignments & Auto Distribute
  // ---------------------------------------------------------------------------

  // Helper method to get teacher's lesson count for a specific day
  Future<int> _getTeacherLessonCount(
    String teacherId,
    int day,
  ) async {
    try {
      // 1. Get ALL active periods for this institution (Handle Primary/Middle/High sync)
      final periodSnapshot = await FirebaseFirestore.instance
          .collection('workPeriods')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      if (periodSnapshot.docs.isEmpty) return 0;
      final activePeriodIds = periodSnapshot.docs.map((d) => d.id).toSet();
      final dayName = _getDayName(day);

      // 2. Fetch all schedule items for this day in this institution
      // We filter by institutionId + day + isActive for robustness and cross-period support
      final scheduleSnap = await FirebaseFirestore.instance
          .collection('classSchedules')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('day', isEqualTo: dayName)
          .where('isActive', isEqualTo: true)
          .get();

      int lessonCount = 0;
      for (var doc in scheduleSnap.docs) {
        final data = doc.data();
        
        // Ensure it belongs to an active period for this institution
        if (!activePeriodIds.contains(data['periodId'])) continue;

        final tId = data['teacherId'];
        final tIds = data['teacherIds'];

        bool match = false;
        if (tId != null && tId.toString() == teacherId) {
          match = true;
        }
        if (!match && tIds is List) {
          if (tIds.any((e) => e.toString() == teacherId)) {
            match = true;
          }
        }

        if (match) {
          lessonCount++;
        }
      }

      return lessonCount;
    } catch (e) {
      print('Error getting teacher lesson count: $e');
      return 0;
    }
  }

  Future<void> _showAssignDialog(
    DutyLocation loc,
    int day,
    String? currentId,
  ) async {
    final eligibleIds = loc.eligibilities[day.toString()] ?? [];

    // Get all assigned teachers for this day (excluding current location)
    final assignedTeachers = <String>{};
    for (var location in _locations) {
      if (location.id != loc.id) {
        final key = '${location.id}_$day';
        final assignment = _matrix[key];
        if (assignment != null) {
          assignedTeachers.add(assignment.teacherId);
        }
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${loc.name} - ${_getDayName(day)}'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('institutionId', isEqualTo: widget.institutionId)
                .where('type', whereIn: ['teacher', 'staff', 'admin'])
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData)
                return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs;
              List<QueryDocumentSnapshot> sorted = List.from(docs);
              sorted.sort((a, b) {
                bool ae = eligibleIds.contains(a.id);
                bool be = eligibleIds.contains(b.id);
                if (ae && !be) return -1;
                if (!ae && be) return 1;
                return (a['fullName'] ?? '').compareTo(b['fullName'] ?? '');
              });

              return ListView.builder(
                itemCount: sorted.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0)
                    return ListTile(
                      leading: const Icon(Icons.clear, color: Colors.red),
                      title: const Text(
                        'GÃÂ¶revi KaldÃÂ±r',
                        style: TextStyle(color: Colors.red),
                      ),
                      onTap: () async {
                        await _removeItem(loc.id, day);
                        if (mounted) Navigator.pop(context);
                      },
                    );
                  final t = sorted[i - 1];
                  final tName = t['fullName'] ?? t['name'] ?? '';
                  final isElig = eligibleIds.contains(t.id);
                  final isSelected = currentId == t.id;
                  final isAssignedElsewhere = assignedTeachers.contains(t.id);

                  final tData = t.data() as Map<String, dynamic>;
                  String branch = 'Öğretmen';
                  if (tData['branches'] is List && (tData['branches'] as List).isNotEmpty) {
                    branch = (tData['branches'] as List).first.toString();
                  } else if (tData['branch'] is String && (tData['branch'] as String).isNotEmpty) {
                    branch = tData['branch'];
                  }

                  return FutureBuilder<int>(
                    future: _getTeacherLessonCount(t.id, day),
                    builder: (context, infoSnap) {
                      final lessonCount = infoSnap.data ?? 0;
                      final subtitle = '$branch ($lessonCount saat)';

                      // Determine colors based on assignment status
                      Color avatarBgColor;
                      Color avatarTextColor;
                      Color tileColor;

                      if (isAssignedElsewhere) {
                        // Teacher assigned to another duty location - use orange/amber
                        avatarBgColor = Colors.orange.shade100;
                        avatarTextColor = Colors.orange.shade800;
                        tileColor = Colors.orange.shade50;
                      } else if (isElig) {
                        // Teacher in pool - use green
                        avatarBgColor = const Color(0xFFDCFCE7);
                        avatarTextColor = Colors.green.shade800;
                        tileColor = Colors.white;
                      } else {
                        // Teacher not in pool - use grey
                        avatarBgColor = Colors.grey.shade100;
                        avatarTextColor = Colors.grey;
                        tileColor = Colors.white;
                      }

                      return Container(
                        color: tileColor,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: avatarBgColor,
                            child: Text(
                              tName.isNotEmpty ? tName[0] : '?',
                              style: TextStyle(
                                color: avatarTextColor,
                                fontWeight: isAssignedElsewhere
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          title: Text(
                            tName,
                            style: TextStyle(
                              fontWeight: isAssignedElsewhere
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle:
                              infoSnap.connectionState ==
                                  ConnectionState.waiting
                              ? const SizedBox(
                                  height: 12,
                                  width: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  subtitle,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isAssignedElsewhere
                                        ? Colors.orange.shade700
                                        : (isElig ? Colors.green : Colors.grey),
                                    fontWeight: isAssignedElsewhere
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF4F46E5),
                                )
                              : (isAssignedElsewhere
                                    ? Icon(
                                        Icons.warning_amber_rounded,
                                        color: Colors.orange.shade700,
                                        size: 20,
                                      )
                                    : null),
                          onTap: () async {
                            await _saveItem(loc.id, day, t.id, tName);
                            if (mounted) Navigator.pop(context);
                          },
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _saveItem(
    String locId,
    int day,
    String tid,
    String tName,
  ) async {
    final key = '${locId}_$day';
    final current = _matrix[key];
    final weekStr = _selectedWeekStart.toIso8601String();

    final data = {
      'institutionId': widget.institutionId,
      'periodId': widget.periodId,
      'locationId': locId,
      'locationName': _locations
          .firstWhere(
            (l) => l.id == locId,
            orElse: () => DutyLocation(
              id: locId,
              institutionId: widget.institutionId,
              name: 'Nöbet Yeri',
              activeDays: [],
              eligibilities: {},
            ),
          )
          .name,
      'dayOfWeek': day,
      'teacherId': tid,
      'teacherName': tName,
      'weekStart': weekStr,
    };

    if (current != null) {
      await FirebaseFirestore.instance
          .collection('dutyScheduleItems')
          .doc(current.id)
          .update(data);
    } else {
      await FirebaseFirestore.instance
          .collection('dutyScheduleItems')
          .add(data);
    }
    _loadData();
    _loadStatsData();
  }

  Future<void> _removeItem(String locId, int day) async {
    final key = '${locId}_$day';
    final current = _matrix[key];
    if (current != null) {
      await FirebaseFirestore.instance
          .collection('dutyScheduleItems')
          .doc(current.id)
          .delete();
      _loadData();
      _loadStatsData();
    }
  }

  Future<void> _showClearAllDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Tümünü Temizle'),
        content: const Text(
          'Bu haftaya ait tüm nöbet atamaları silinecek. Emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm == true) await _clearAllDuties();
  }

  Future<void> _clearAllDuties() async {
    setState(() => _isLoading = true);
    try {
      final weekStr = _selectedWeekStart.toIso8601String();
      final exist = await FirebaseFirestore.instance
          .collection('dutyScheduleItems')
          .where('periodId', isEqualTo: widget.periodId)
          .where('weekStart', isEqualTo: weekStr)
          .get();

      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (var d in exist.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tüm nöbetler temizlendi.')),
        );
      }
      _loadData();
      _loadStatsData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _getDayName(int d) => [
    '',
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ][d];

  Future<void> _showAutoDistributeCall() async {
    final dateFormat = DateFormat('dd MMM', 'tr_TR');
    final weekStr = dateFormat.format(_selectedWeekStart);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Otomatik Dağıt'),
        content: Text(
          '$weekStr haftasın nöbet dağıtım yapılacak. Mevcut haftalık atamalar silinebilir. Onaylıyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Dağıt'),
          ),
        ],
      ),
    );
    if (confirm == true) _distributeDuties();
  }

  Future<void> _distributeDuties() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch Teachers
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('type', whereIn: ['teacher', 'staff', 'admin'])
          .get();
      final teachers = userSnap.docs
          .map((d) => d.data()..['id'] = d.id)
          .toList();
      if (teachers.isEmpty) throw 'Hiçbir personel bulunamadı.';

      // 2. Sort Locations Deterministically (For Consistent Rotation)
      if (_locations.isEmpty) throw 'Hiçbir nöbet yeri yok.';
      _locations.sort((a, b) => a.name.compareTo(b.name));

      // 3. Clear Existing for THIS Week
      final weekStr = _selectedWeekStart.toIso8601String();
      final exist = await FirebaseFirestore.instance
          .collection('dutyScheduleItems')
          .where('periodId', isEqualTo: widget.periodId)
          .where('weekStart', isEqualTo: weekStr)
          .get();

      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (var d in exist.docs) {
        batch.delete(d.reference);
      }

      // 4. Load Previous Week Assignments (For Rotation)
      final prevWeekStr = _selectedWeekStart
          .subtract(const Duration(days: 7))
          .toIso8601String();

      final prevSnap = await FirebaseFirestore.instance
          .collection('dutyScheduleItems')
          .where('periodId', isEqualTo: widget.periodId)
          .where('weekStart', isEqualTo: prevWeekStr)
          .get();

      // Map: TeacherID -> Map<Day(int), LocationID>
      Map<String, Map<int, String>> prevTeacherLocs = {};
      for (var d in prevSnap.docs) {
        final tid = d['teacherId'];
        final day = d['dayOfWeek'];
        final locId = d['locationId'];
        if (!prevTeacherLocs.containsKey(tid)) prevTeacherLocs[tid] = {};
        prevTeacherLocs[tid]![day] = locId;
      }

      // Load Tracker (for fallback assignments)
      final historySnap = await FirebaseFirestore.instance
          .collection('dutyScheduleItems')
          .where('periodId', isEqualTo: widget.periodId)
          .get();

      Map<String, int> totalLoad = {};
      Map<String, Map<String, int>> locHistoryCounts = {};

      for (var t in teachers) {
        final tid = t['id'];
        totalLoad[tid] = 0;
        locHistoryCounts[tid] = {};
        for (var l in _locations) {
          locHistoryCounts[tid]![l.id] = 0;
        }
      }

      for (var d in historySnap.docs) {
        final tid = d['teacherId'];
        final lid = d['locationId'];
        totalLoad[tid] = (totalLoad[tid] ?? 0) + 1;
        if (locHistoryCounts.containsKey(tid)) {
          locHistoryCounts[tid]![lid] = (locHistoryCounts[tid]![lid] ?? 0) + 1;
        }
      }

      Map<String, int> currentLoad = {};
      for (var t in teachers) {
        currentLoad[t['id']] = 0;
      }

      int assignedCount = 0;
      // 5. Algorithm: Unified Fairness per Location
      for (int day = 1; day <= 7; day++) {
        Set<String> assignedToday = {};

        // Active locations for this day
        final activeLocs = _locations
            .where((l) => l.activeDays.contains(day))
            .toList();

        // Helper: Get Effective Eligibility Pool
        // If a day has no specific pool defined, fallback to ANY defined pool for that location.
        // This fixes issues where "Aziz Sancar" might only have Monday defined but is active all week.
        List<String> getEffectiveIds(DutyLocation loc) {
          final specific = loc.eligibilities[day.toString()];
          if (specific != null && specific.isNotEmpty) {
            return List<String>.from(specific);
          }
          // Fallback: Union of all days
          final all = loc.eligibilities.values
              .expand((e) => (e as List).map((x) => x.toString()))
              .toSet()
              .toList();
          return all;
        }

        // Sort by scarcity (Hardest to fill first)
        activeLocs.sort((a, b) {
          final countA = getEffectiveIds(a).length;
          final countB = getEffectiveIds(b).length;
          return countA.compareTo(countB);
        });

        if (activeLocs.isEmpty) continue;

        // Helper to find next location index
        String? getPrevLocId(int currentIndex) {
          int prevIndex = (currentIndex - 1);
          if (prevIndex < 0) prevIndex = activeLocs.length - 1;
          return activeLocs[prevIndex].id;
        }

        for (int i = 0; i < activeLocs.length; i++) {
          final loc = activeLocs[i];
          final eligibleIds = getEffectiveIds(loc);

          if (eligibleIds.isEmpty) continue;

          // 1. Filter Candidates (Eligible & Not assigned today)
          var candidates = teachers.where((t) {
            final tid = t['id'];
            return eligibleIds.contains(tid) && !assignedToday.contains(tid);
          }).toList();

          if (candidates.isEmpty) continue;

          final targetPrevLocId = getPrevLocId(i);

          candidates.sort((a, b) {
            final idA = a['id'];
            final idB = b['id'];

            double scoreA = 0;
            double scoreB = 0;

            // 1. LOCAL Location Load (ABSOLUTE KING)
            // Penalty: 100,000,000.
            final locLoadA = locHistoryCounts[idA]?[loc.id] ?? 0;
            final locLoadB = locHistoryCounts[idB]?[loc.id] ?? 0;
            scoreA += locLoadA * 100000000;
            scoreB += locLoadB * 100000000;

            // 2. Weekly Load Soft Cap (Prevent Burnout)
            // If someone has already done 1 shift this week, push them to back of queue
            // UNLESS everyone else has also done 1 shift.
            // Weight: 500,000 (Half of "Repeat Location" penalty)
            if ((currentLoad[idA] ?? 0) >= 1) scoreA += 100000;
            if ((currentLoad[idB] ?? 0) >= 1) scoreB += 100000;

            // Further penalty for >2 shifts (Almost impossible to get 3 unless only option)

            // 3. Global Load (Tie-breaker for general fairness)
            // If both have 0 weekly shifts, the one with fewer TOTAL shifts wins.
            scoreA += (totalLoad[idA] ?? 0) * 100;
            scoreB += (totalLoad[idB] ?? 0) * 100;

            // 3. Same Location Penalty (Fatigue)
            if (prevTeacherLocs[idA]?.values.contains(loc.id) ?? false) {
              scoreA += 500;
            }
            if (prevTeacherLocs[idB]?.values.contains(loc.id) ?? false) {
              scoreB += 500;
            }

            // 4. Rotation Bonus (Consistency)
            // If they are naturally "Next In Line" (from last week), give a bonus.
            // This bonus (-250) is smaller than the Total Load weight (10000)
            // so fairness overrides rotation if there's a load imbalance.
            final prevLocA = prevTeacherLocs[idA]?[day];
            if (prevLocA == targetPrevLocId) scoreA -= 250;

            final prevLocB = prevTeacherLocs[idB]?[day];
            if (prevLocB == targetPrevLocId) scoreB -= 250;

            return scoreA.compareTo(scoreB);
          });

          final selectedTeacher = candidates.first;

          // Assign
          final tId = selectedTeacher['id'];
          final tName = selectedTeacher['fullName'] ?? selectedTeacher['name'];
          assignedToday.add(tId);
          totalLoad[tId] = (totalLoad[tId] ?? 0) + 1;
          currentLoad[tId] = (currentLoad[tId] ?? 0) + 1;
          assignedCount++;

          // Update InMemory History so they aren't assigned same spot again this week
          if (locHistoryCounts.containsKey(tId)) {
            locHistoryCounts[tId]![loc.id] =
                (locHistoryCounts[tId]![loc.id] ?? 0) + 1;
          }

          final ref = FirebaseFirestore.instance
              .collection('dutyScheduleItems')
              .doc();

          batch.set(ref, {
            'institutionId': widget.institutionId,
            'periodId': widget.periodId,
            'locationId': loc.id,
            'locationName': loc.name,
            'dayOfWeek': day,
            'teacherId': tId,
            'teacherName': tName,
            'weekStart': weekStr,
          });
        }
      }

      await batch.commit();
      if (!mounted) return;
      if (assignedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Otomatik dağıtım (Döngüsel Rotasyon) tamamlandı. $assignedCount atama yapıldı.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Hiçbir atama yapılamadı. Nöbet yerlerinin uygunluk havuzlarının boş olmadığından emin olun.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      _loadData();
      _loadStatsData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }
}
