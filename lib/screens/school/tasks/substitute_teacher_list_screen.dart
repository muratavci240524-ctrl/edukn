import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../models/school/temporary_teacher_assignment.dart';
import '../../../services/pdf_service.dart';
import 'package:printing/printing.dart';
import 'create_substitute_assignment_screen.dart';

class SubstituteTeacherListScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;

  const SubstituteTeacherListScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
  }) : super(key: key);

  @override
  State<SubstituteTeacherListScreen> createState() =>
      _SubstituteTeacherListScreenState();
}

class _SubstituteTeacherListScreenState
    extends State<SubstituteTeacherListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Date filter
  DateTime _selectedDate = DateTime.now();
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  String _filterMode = 'day'; // Default to daily as requested
  String _viewType = 'teacher'; // 'teacher' or 'lesson'
  String _statViewMode = 'general'; // 'general' or 'teacher_list'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          'Geçici Görevlendirme',
          style: TextStyle(
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.w800,
            fontSize: 22,
            letterSpacing: -0.5,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
        actions: [
          IconButton(
            onPressed: _showDateModePicker,
            icon: Icon(
              _filterMode == 'day'
                  ? Icons.today
                  : _filterMode == 'week'
                  ? Icons.calendar_view_week
                  : _filterMode == 'month'
                  ? Icons.calendar_month
                  : Icons.date_range,
              color: const Color(0xFF4F46E5),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: _buildDateFilterBar(),
              ),
              TabBar(
                controller: _tabController,
                labelColor: const Color(0xFF4F46E5),
                unselectedLabelColor: const Color(0xFF94A3B8),
                indicatorSize: TabBarIndicatorSize.label,
                indicatorColor: const Color(0xFF4F46E5),
                indicatorWeight: 3,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                tabs: const [
                  Tab(text: 'Ders Atamaları'),
                  Tab(text: 'İstatistikler'),
                ],
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CreateSubstituteAssignmentScreen(
                institutionId: widget.institutionId,
                schoolTypeId: widget.schoolTypeId,
                schoolTypeName: widget.schoolTypeName,
              ),
            ),
          ).then((_) => setState(() {}));
        },
        backgroundColor: const Color(0xFFEF4444), // Red for absence related
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
        label: const Text(
          'Yeni Atama',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildAssignmentsList(), _buildStatisticsView()],
      ),
    );
  }

  void _showDateModePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text(
              'Günlük',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            leading: const Icon(Icons.today, color: Color(0xFF4F46E5)),
            onTap: () {
              setState(() => _filterMode = 'day');
              Navigator.pop(context);
            },
          ),
          ListTile(
            title: const Text(
              'Haftalık',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            leading: const Icon(
              Icons.calendar_view_week,
              color: Color(0xFF4F46E5),
            ),
            onTap: () {
              setState(() => _filterMode = 'week');
              Navigator.pop(context);
            },
          ),
          ListTile(
            title: const Text(
              'Aylık',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            leading: const Icon(Icons.calendar_month, color: Color(0xFF4F46E5)),
            onTap: () {
              setState(() => _filterMode = 'month');
              Navigator.pop(context);
            },
          ),
          ListTile(
            title: const Text(
              'Özel Tarih',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            leading: const Icon(Icons.date_range, color: Color(0xFF4F46E5)),
            onTap: () async {
              Navigator.pop(context);
              await _selectCustomDateRange();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _selectCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _customStartDate != null && _customEndDate != null
          ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            primaryColor: const Color(0xFF4F46E5),
            colorScheme: const ColorScheme.light(primary: Color(0xFF4F46E5)),
            buttonTheme: const ButtonThemeData(
              textTheme: ButtonTextTheme.primary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _filterMode = 'custom';
        _customStartDate = picked.start;
        _customEndDate = picked.end;
      });
    }
  }

  Widget _buildDateFilterBar() {
    String label = '';
    final df = DateFormat('dd MMM yyyy', 'tr_TR');

    if (_filterMode == 'day') {
      label = df.format(_selectedDate);
    } else if (_filterMode == 'week') {
      final start = _selectedDate.subtract(
        Duration(days: _selectedDate.weekday - 1),
      );
      final end = start.add(const Duration(days: 6));
      label =
          '${DateFormat('dd MMM', 'tr_TR').format(start)} - ${df.format(end)}';
    } else if (_filterMode == 'month') {
      label = DateFormat('MMMM yyyy', 'tr_TR').format(_selectedDate);
    } else {
      // Custom
      if (_customStartDate != null && _customEndDate != null) {
        label =
            '${DateFormat('dd MMM', 'tr_TR').format(_customStartDate!)} - ${df.format(_customEndDate!)}';
      } else {
        label = 'Tarih Aralığı Seçiniz';
      }
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_filterMode != 'custom')
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Color(0xFF64748B)),
            onPressed: () => _shiftDate(-1),
          ),
        GestureDetector(
          onTap: _filterMode == 'custom' ? _selectCustomDateRange : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                if (_filterMode == 'custom')
                  const Padding(
                    padding: EdgeInsets.only(left: 8.0),
                    child: Icon(Icons.edit, size: 14, color: Color(0xFF64748B)),
                  ),
              ],
            ),
          ),
        ),
        if (_filterMode != 'custom')
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Color(0xFF64748B)),
            onPressed: () => _shiftDate(1),
          ),
      ],
    );
  }

  void _shiftDate(int delta) {
    if (_filterMode == 'custom') return;
    setState(() {
      if (_filterMode == 'day') {
        _selectedDate = _selectedDate.add(Duration(days: delta));
      } else if (_filterMode == 'week') {
        _selectedDate = _selectedDate.add(Duration(days: delta * 7));
      } else {
        _selectedDate = DateTime(
          _selectedDate.year,
          _selectedDate.month + delta,
          1,
        );
      }
    });
  }

  Widget _buildAssignmentsList() {
    // Determine Date Range
    DateTime start;
    DateTime end;

    final d = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    if (_filterMode == 'day') {
      start = d;
      end = d
          .add(const Duration(days: 1))
          .subtract(const Duration(milliseconds: 1));
    } else if (_filterMode == 'week') {
      start = d.subtract(Duration(days: d.weekday - 1));
      end = start
          .add(const Duration(days: 7))
          .subtract(const Duration(milliseconds: 1));
    } else {
      start = DateTime(d.year, d.month, 1);
      end = DateTime(d.year, d.month + 1, 0, 23, 59, 59);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('temporaryTeacherAssignments')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }

        final docs = snapshot.data?.docs ?? [];
        final assignments = docs
            .map((d) => TemporaryTeacherAssignment.fromFirestore(d))
            .toList();

        final hasAssignments = assignments.isNotEmpty;
        final isAllPublished =
            hasAssignments && !assignments.any((a) => a.status == 'pending');

        return Column(
          children: [
            // Header: Publish Switch + View Toggle
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Publish Switch
                  Row(
                    children: [
                      Switch(
                        value: isAllPublished,
                        activeColor: const Color(0xFF10B981),
                        onChanged: hasAssignments
                            ? (val) {
                                if (val) {
                                  _publishAssignments(start, end);
                                } else {
                                  _unpublishAssignments(start, end);
                                }
                              }
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isAllPublished ? 'Yayında' : 'Taslak',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isAllPublished
                              ? const Color(0xFF10B981)
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),

                  // View Toggle (Compact)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildToggleItem(
                          'teacher',
                          Icons.person_outline,
                          'Öğretmen',
                        ),
                        _buildToggleItem('lesson', Icons.access_time, 'Ders'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: hasAssignments
                  ? (_viewType == 'lesson'
                        ? _buildLessonView(assignments)
                        : _buildTeacherView(assignments))
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.event_available,
                            size: 64,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Bu tarihler arasında atama bulunamadı.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLessonView(List<TemporaryTeacherAssignment> assignments) {
    // Sort by Hour then Class
    assignments.sort((a, b) {
      int res = a.hourIndex.compareTo(b.hourIndex);
      if (res == 0) {
        return a.className.compareTo(b.className);
      }
      return res;
    });

    return Column(
      children: [
        // Table Header
        Container(
          color: const Color(0xFFF1F5F9),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: const Row(
            children: [
              SizedBox(
                width: 32,
                child: Icon(Icons.check, size: 16, color: Color(0xFF94A3B8)),
              ),
              SizedBox(
                width: 50,
                child: Text(
                  'Saat',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
              SizedBox(
                width: 80, // Increased spacing
                child: Text(
                  'Sınıf',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Ders & Öğretmen',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
              SizedBox(width: 40),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: assignments.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final assignment = assignments[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      alignment: Alignment.centerLeft,
                      child: CircleAvatar(
                        radius: 4,
                        backgroundColor: assignment.status == 'published'
                            ? const Color(0xFF10B981)
                            : Colors.amber,
                      ),
                    ),
                    SizedBox(
                      width: 50,
                      child: Text(
                        '${assignment.hourIndex + 1}. Ders',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 80, // Increased spacing
                      child: Text(
                        assignment.className,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            assignment.lessonName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF334155),
                            ),
                          ),
                          Text(
                            '${assignment.substituteTeacherName} (${assignment.originalTeacherName} yerine)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Color(
                          0xFF94A3B8,
                        ), // Matching the softer grey/blue
                      ),
                      onPressed: () => _deleteAssignment(assignment.id),
                      tooltip: 'Atamayı Kaldır',
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

  Widget _buildTeacherView(List<TemporaryTeacherAssignment> assignments) {
    // Group by Original Teacher (Absent Teacher) as requested
    Map<String, List<TemporaryTeacherAssignment>> grouped = {};
    for (var a in assignments) {
      final key = a.originalTeacherName; // Changed to Original Teacher
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add(a);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...grouped.entries.map((entry) {
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: const Color(
                          0xFFEF4444, // Red for absent teacher
                        ).withOpacity(0.1),
                        child: Text(
                          entry.key.isNotEmpty
                              ? entry.key.substring(0, 1)
                              : '?',
                          style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          Text(
                            entry.value.first.reason,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${entry.value.length} Ders Dolduruldu',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ...entry.value.map((assignment) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFFEDD5)),
                          ),
                          child: Text(
                            '${assignment.hourIndex + 1}. Ders',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFCA8A04),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${assignment.lessonName} (${assignment.className})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF334155),
                                ),
                              ),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 14,
                                    color: Color(0xFF10B981),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Atanan: ${assignment.substituteTeacherName ?? "Bilinmiyor"}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _deleteAssignment(assignment.id),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Color(0xFF94A3B8),
                            size: 20,
                          ),
                          tooltip: 'Atamayı Kaldır',
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTeacherStats(List<QueryDocumentSnapshot> docs) {
    // Stats: { missingTotal: int, filledTotal: int, reasondetail }
    final Map<String, Map<String, dynamic>> stats = {};

    // Defined columns for the web table
    final List<String> reasonColumns = [
      'İzinli',
      'Raporlu',
      'Görevli',
      'Gezi',
      'Toplantı',
      'Tören',
      'Diğer',
    ];

    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final subName = data['substituteTeacherName'] as String?;
      final origName = data['originalTeacherName'] as String?;
      final reason = data['reason'] as String? ?? 'Diğer';

      // Ensure entries create
      if (origName != null && !stats.containsKey(origName)) {
        stats[origName] = {
          'missing': 0,
          'filled': 0,
          'reasons': <String, int>{},
        };
      }
      if (subName != null && !stats.containsKey(subName)) {
        stats[subName] = {
          'missing': 0,
          'filled': 0,
          'reasons': <String, int>{},
        };
      }

      // Logic:
      // If origName is present, they missed a class.
      if (origName != null) {
        stats[origName]!['missing'] = (stats[origName]!['missing'] as int) + 1;
        final reasons = stats[origName]!['reasons'] as Map<String, int>;
        reasons[reason] = (reasons[reason] ?? 0) + 1;
      }

      // If subName is present, they filled a class.
      if (subName != null) {
        stats[subName]!['filled'] = (stats[subName]!['filled'] as int) + 1;
      }
    }

    final sortedTeachers = stats.keys.toList()..sort();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isBroad = constraints.maxWidth > 800;

        if (isBroad) {
          // --- WEB / TABLET VIEW (DETAILED TABLE) ---
          return Center(
            child: Container(
              width: 1100, // Increased width for more columns
              margin: const EdgeInsets.only(top: 24, bottom: 80),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Table Header
                  Container(
                    color: const Color(0xFFF8FAFC),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            'ÖĞRETMEN',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Center(
                            child: Text(
                              'EKSİK',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Center(
                            child: Text(
                              'DOLU',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        // Dynamic Reason Columns
                        ...reasonColumns.map(
                          (r) => Expanded(
                            flex: 1,
                            child: Center(
                              child: Text(
                                r.toUpperCase(),
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11, // Slightly smaller
                                ),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, thickness: 1),
                  // Table Rows
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const ClampingScrollPhysics(),
                      itemCount: sortedTeachers.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, thickness: 0.5),
                      itemBuilder: (context, index) {
                        final name = sortedTeachers[index];
                        final info = stats[name]!;
                        final missing = info['missing'] as int;
                        final filled = info['filled'] as int;
                        final reasons = info['reasons'] as Map<String, int>;

                        return Container(
                          color: index % 2 == 0
                              ? Colors.white
                              : const Color(0xFFFCFDFE),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Center(
                                  child: Text(
                                    missing.toString(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: missing > 0
                                          ? Colors.red.shade600
                                          : Colors.grey.shade400,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Center(
                                  child: Text(
                                    filled.toString(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: filled > 0
                                          ? Colors.green.shade600
                                          : Colors.grey.shade400,
                                    ),
                                  ),
                                ),
                              ),
                              // Reason Counts
                              ...reasonColumns.map((r) {
                                final count = reasons[r] ?? 0;
                                return Expanded(
                                  flex: 1,
                                  child: Center(
                                    child: Text(
                                      count.toString(),
                                      style: TextStyle(
                                        fontWeight: count > 0
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: count > 0
                                            ? Colors.grey.shade800
                                            : Colors.grey.shade300,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // --- MOBILE VIEW ---
        return Column(
          children: [
            // Mobile Header
            Container(
              color: const Color(0xFFF8FAFC),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const SizedBox(width: 44), // Matches IconButton space roughly
                  Expanded(
                    child: Text(
                      'ÖĞRETMEN',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 42,
                    child: Center(
                      child: Text(
                        'EKSİK',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 42,
                    child: Center(
                      child: Text(
                        'ATAMA',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: sortedTeachers.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final name = sortedTeachers[index];
                  final info = stats[name]!;
                  final missing = info['missing'] as int;
                  final filled = info['filled'] as int;
                  final reasons = info['reasons'] as Map<String, int>;

                  final reasonText = reasons.entries
                      .map((e) => '${e.value} ${e.key}')
                      .join(', ');
                  final hasInfo = reasons.isNotEmpty;

                  return Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        // Info Button on Left
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: IconButton(
                            icon: Icon(
                              Icons.info_outline_rounded,
                              size: 22,
                              color: hasInfo
                                  ? const Color(0xFF4F46E5)
                                  : Colors.grey.shade300,
                            ),
                            splashRadius: 20,
                            tooltip: 'Mazeret Detayı',
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor: const Color(
                                          0xFFF1F5F9,
                                        ),
                                        child: Text(
                                          name.substring(0, 1),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                      ),
                                    ],
                                  ),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Mazeret Durumu:',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        reasonText.isEmpty
                                            ? 'Belirtilmemiş'
                                            : reasonText,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('Eksik Ders: $missing'),
                                          Text('Atanan Ders: $filled'),
                                        ],
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Tamam'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStatBadge(
                          missing.toString(),
                          missing > 0
                              ? Colors.red.shade700
                              : Colors.grey.shade400,
                          missing > 0
                              ? Colors.red.shade50
                              : Colors.grey.shade50,
                          isCompact: true,
                        ),
                        const SizedBox(width: 6),
                        _buildStatBadge(
                          filled.toString(),
                          filled > 0
                              ? Colors.green.shade700
                              : Colors.grey.shade400,
                          filled > 0
                              ? Colors.green.shade50
                              : Colors.grey.shade50,
                          isCompact: true,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatBadge(
    String value,
    Color text,
    Color bg, {
    bool isCompact = false,
  }) {
    return Container(
      width: isCompact
          ? 42
          : 48, // Increased compact width for better fit of headers above
      height: isCompact ? 32 : 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: text.withOpacity(0.2), width: 0.5),
      ),
      child: Text(
        value,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: text,
          fontSize: isCompact ? 13 : 15,
        ),
      ),
    );
  }

  Future<void> _publishAssignments(DateTime start, DateTime end) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('temporaryTeacherAssignments')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      if (snap.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Yayınlanacak atama bulunamadı.')),
          );
        }
        return;
      }

      // Check if any is pending
      final pendingCount = snap.docs
          .where((d) => d['status'] == 'pending')
          .length;
      if (pendingCount == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tüm atamalar zaten yayında.')),
          );
        }
        return;
      }

      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Atamaları Yayınla'),
          content: Text(
            'Bu tarih aralığındaki $pendingCount adet taslak atama yayınlanacak ve ilgili öğretmenlere bildirim gönderilecek. Onaylıyor musunuz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yayınla'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      // 1. Update Status (Priority)
      final batch = FirebaseFirestore.instance.batch();
      for (var doc in snap.docs) {
        if (doc['status'] == 'pending') {
          batch.update(doc.reference, {'status': 'published'});
        }
      }
      await batch.commit();

      // 2. Try sending notifications (Best Effort)
      // We do this separately so strict notification permissions don't block the logic
      try {
        final notifyBatch = FirebaseFirestore.instance.batch();
        final notifyCol = FirebaseFirestore.instance.collection(
          'notificationRequests',
        );

        for (var doc in snap.docs) {
          final data = doc.data();
          if (data['status'] == 'published')
            continue; // Was already published before loop

          final subId = data['substituteTeacherId'];
          final subName = data['substituteTeacherName'];
          final origName = data['originalTeacherName'];
          final lesson = data['lessonName'];
          final hour = (data['hourIndex'] ?? 0) + 1;
          final dateVal = (data['date'] as Timestamp).toDate();
          final dateStr = DateFormat('dd.MM.yyyy').format(dateVal);

          if (subId != null) {
            final msg =
                '$dateStr tarihinde, $hour. ders ($lesson) için $origName yerine görevlendirildiniz.';
            final ref = notifyCol.doc();
            notifyBatch.set(ref, {
              'type': 'teacher_assignment',
              'institutionId': widget.institutionId,
              'schoolTypeId': widget.schoolTypeId,
              'periodId': '-',
              'teacherId': subId,
              'teacherIds': [subId],
              'teacherNames': [subName ?? ''],
              'message': msg,
              'title': 'Geçici Görevlendirme',
              'createdAt': FieldValue.serverTimestamp(),
              'status': 'queued',
            });
          }
        }
        await notifyBatch.commit();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Atamalar yayınlandı ve bildirimler gönderildi.'),
            ),
          );
        }
      } catch (e) {
        print('Notification error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Atamalar yayınlandı fakat bildirim gönderilemedi (Yetki Hatası).',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  Future<void> _unpublishAssignments(DateTime start, DateTime end) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yayından Kaldır'),
        content: const Text(
          'Bu tarih aralığındaki tüm atamaları taslak durumuna getirmek istediğinizden emin misiniz? Öğretmen programlarından kaldırılacaktır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Kaldır', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('temporaryTeacherAssignments')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      final batch = FirebaseFirestore.instance.batch();

      for (var doc in snap.docs) {
        // Set back to pending
        batch.update(doc.reference, {'status': 'pending'});
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Atamalar taslak durumuna getirildi.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  Future<void> _deleteAssignment(String assignmentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Atamayı Kaldır'),
        content: const Text('Bu atamayı silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('temporaryTeacherAssignments')
            .doc(assignmentId)
            .delete();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Atama silindi')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Hata: $e')));
        }
      }
    }
  }

  Widget _buildToggleItem(String type, IconData icon, String tooltip) {
    final isSelected = _viewType == type;
    return InkWell(
      onTap: () => setState(() => _viewType = type),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFF6FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 20,
          color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade400,
        ),
      ),
    );
  }

  Widget _buildStatisticsView() {
    DateTime start;
    DateTime end;

    if (_filterMode == 'month') {
      final d = _selectedDate;
      start = DateTime(d.year, d.month, 1);
      end = DateTime(d.year, d.month + 1, 0, 23, 59, 59);
    } else if (_filterMode == 'week') {
      final d = _selectedDate;
      start = d.subtract(Duration(days: d.weekday - 1));
      end = start
          .add(const Duration(days: 6))
          .add(const Duration(hours: 23, minutes: 59, seconds: 59));
    } else if (_filterMode == 'custom' &&
        _customStartDate != null &&
        _customEndDate != null) {
      start = _customStartDate!;
      end = _customEndDate!.add(
        const Duration(hours: 23, minutes: 59, seconds: 59),
      );
    } else {
      // Day
      start = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      end = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        23,
        59,
        59,
      );
    }

    return Column(
      children: [
        // Stats View Toggle & Print Button
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildStatToggleItem('Genel', 'general'),
                          ),
                          Expanded(
                            child: _buildStatToggleItem(
                              'Öğretmen Bazlı',
                              'teacher_list',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('temporaryTeacherAssignments')
                        .where('institutionId', isEqualTo: widget.institutionId)
                        .where(
                          'date',
                          isGreaterThanOrEqualTo: Timestamp.fromDate(start),
                        )
                        .where(
                          'date',
                          isLessThanOrEqualTo: Timestamp.fromDate(end),
                        )
                        .snapshots(),
                    builder: (context, snapshot) {
                      final hasData =
                          snapshot.hasData && snapshot.data!.docs.isNotEmpty;
                      return IconButton(
                        onPressed: hasData
                            ? () => _generateAndPrintPdf(snapshot.data!.docs)
                            : null,
                        icon: const Icon(Icons.print_outlined),
                        color: const Color(0xFF4F46E5),
                        tooltip: 'Yazdır / PDF',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('temporaryTeacherAssignments')
                .where('institutionId', isEqualTo: widget.institutionId)
                .where(
                  'date',
                  isGreaterThanOrEqualTo: Timestamp.fromDate(start),
                )
                .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data?.docs ?? [];

              if (docs.isEmpty) {
                String periodText;
                if (_filterMode == 'day') {
                  periodText = DateFormat('dd.MM.yyyy').format(start);
                } else if (_filterMode == 'week') {
                  periodText =
                      '${DateFormat('dd.MM').format(start)} - ${DateFormat('dd.MM.yyyy').format(end)}';
                } else if (_filterMode == 'month') {
                  periodText = DateFormat('MMMM yyyy', 'tr').format(start);
                } else {
                  periodText =
                      '${DateFormat('dd.MM.yyyy').format(start)} - ${DateFormat('dd.MM.yyyy').format(end)}';
                }

                return Center(
                  child: Text('Bu dönem ($periodText) için veri yok.'),
                );
              }

              if (_statViewMode == 'teacher_list') {
                return _buildTeacherStats(docs);
              }

              return _buildGeneralStats(docs);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatToggleItem(String title, String key) {
    final isSelected = _statViewMode == key;
    return GestureDetector(
      onTap: () => setState(() => _statViewMode = key),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4F46E5) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey.shade600,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildGeneralStats(List<QueryDocumentSnapshot> docs) {
    Map<String, int> substituteCounts = {};
    Map<String, int> absenceCounts = {};
    Map<String, int> reasonCounts = {};

    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final subName = data['substituteTeacherName'] as String?;
      final origName = data['originalTeacherName'] as String?;
      final reason = data['reason'] as String?;

      if (subName != null) {
        substituteCounts[subName] = (substituteCounts[subName] ?? 0) + 1;
      }
      if (origName != null) {
        absenceCounts[origName] = (absenceCounts[origName] ?? 0) + 1;
      }
      if (reason != null) {
        reasonCounts[reason] = (reasonCounts[reason] ?? 0) + 1;
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      children: [
        _buildStatSection('En Çok Görev Alan Öğretmenler', substituteCounts),
        _buildStatSection(
          'En Çok Devamsızlık Yapan Öğretmenler',
          absenceCounts,
          isNegative: true,
        ),
        _buildStatSection('Devamsızlık Nedenleri', reasonCounts),
      ],
    );
  }

  Widget _buildStatSection(
    String title,
    Map<String, int> data, {
    bool isNegative = false,
  }) {
    if (data.isEmpty) return const SizedBox.shrink();

    final sortedKeys = data.keys.toList()
      ..sort((a, b) => data[b]!.compareTo(data[a]!));

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),
          ...sortedKeys.take(5).map((key) {
            final count = data[key]!;
            final max = data[sortedKeys.first]!;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        key,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
                        ),
                      ),
                      Text(
                        '$count Ders',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: count / max,
                      minHeight: 8,
                      backgroundColor: const Color(0xFFF1F5F9),
                      color: isNegative
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _generateAndPrintPdf(List<QueryDocumentSnapshot> docs) async {
    final pdfService = PdfService();
    String title = _statViewMode == 'general'
        ? 'Genel İstatistik Raporu'
        : 'Öğretmen Bazlı Rapor';

    // Calculate Date Range String
    String dateRange = '';
    final df = DateFormat('dd.MM.yyyy');
    if (_filterMode == 'day') {
      dateRange = df.format(_selectedDate);
    } else if (_filterMode == 'week') {
      final start = _selectedDate.subtract(
        Duration(days: _selectedDate.weekday - 1),
      );
      final end = start.add(const Duration(days: 6));
      dateRange = '${df.format(start)} - ${df.format(end)}';
    } else if (_filterMode == 'month') {
      dateRange = DateFormat('MMMM yyyy', 'tr').format(_selectedDate);
    } else if (_customStartDate != null && _customEndDate != null) {
      dateRange =
          '${df.format(_customStartDate!)} - ${df.format(_customEndDate!)}';
    }

    List<String> headers = [];
    List<List<String>> data = [];

    if (_statViewMode == 'teacher_list') {
      // Teacher Based Table
      final reasonColumns = [
        'İzinli',
        'Raporlu',
        'Görevli',
        'Gezi',
        'Toplantı',
        'Tören',
        'Diğer',
      ];
      headers = [
        'Öğretmen',
        'Eksik',
        'Atanan',
        ...reasonColumns.map((e) => e.toUpperCase()),
      ];

      final Map<String, Map<String, dynamic>> stats = {};
      for (var doc in docs) {
        final d = doc.data() as Map<String, dynamic>;
        final subName = d['substituteTeacherName'] as String?;
        final origName = d['originalTeacherName'] as String?;
        final reason = d['reason'] as String? ?? 'Diğer';

        if (origName != null && !stats.containsKey(origName)) {
          stats[origName] = {
            'missing': 0,
            'filled': 0,
            'reasons': <String, int>{},
          };
        }
        if (subName != null && !stats.containsKey(subName)) {
          stats[subName] = {
            'missing': 0,
            'filled': 0,
            'reasons': <String, int>{},
          };
        }

        if (origName != null) {
          stats[origName]!['missing'] =
              (stats[origName]!['missing'] as int) + 1;
          final reasons = stats[origName]!['reasons'] as Map<String, int>;
          reasons[reason] = (reasons[reason] ?? 0) + 1;
        }

        if (subName != null) {
          stats[subName]!['filled'] = (stats[subName]!['filled'] as int) + 1;
        }
      }

      final sortedTeachers = stats.keys.toList()..sort();
      for (var t in sortedTeachers) {
        final info = stats[t]!;
        final missing = info['missing'] as int;
        final filled = info['filled'] as int;
        final reasons = info['reasons'] as Map<String, int>;

        List<String> row = [t, missing.toString(), filled.toString()];

        for (var r in reasonColumns) {
          row.add((reasons[r] ?? 0).toString());
        }
        data.add(row);
      }
    } else {
      // General Stats Table
      headers = ['Kategori', 'İsim / Neden', 'Sayı'];

      Map<String, int> substituteCounts = {};
      Map<String, int> absenceCounts = {};
      Map<String, int> reasonCounts = {};

      for (var doc in docs) {
        final d = doc.data() as Map<String, dynamic>;
        final subName = d['substituteTeacherName'] as String?;
        final origName = d['originalTeacherName'] as String?;
        final reason = d['reason'] as String?;

        if (subName != null)
          substituteCounts[subName] = (substituteCounts[subName] ?? 0) + 1;
        if (origName != null)
          absenceCounts[origName] = (absenceCounts[origName] ?? 0) + 1;
        if (reason != null)
          reasonCounts[reason] = (reasonCounts[reason] ?? 0) + 1;
      }

      // Top Substitutes
      final sortedSub = substituteCounts.keys.toList()
        ..sort((a, b) => substituteCounts[b]!.compareTo(substituteCounts[a]!));
      for (var k in sortedSub.take(10)) {
        data.add(['En Çok Görev Alan', k, substituteCounts[k].toString()]);
      }
      if (data.isNotEmpty) data.add(['', '', '']); // Spacer

      // Top Absences
      final sortedAbs = absenceCounts.keys.toList()
        ..sort((a, b) => absenceCounts[b]!.compareTo(absenceCounts[a]!));
      for (var k in sortedAbs.take(10)) {
        data.add(['En Çok Devamsızlık', k, absenceCounts[k].toString()]);
      }
      if (data.isNotEmpty) data.add(['', '', '']); // Spacer

      // Reasons
      final sortedReason = reasonCounts.keys.toList()
        ..sort((a, b) => reasonCounts[b]!.compareTo(reasonCounts[a]!));
      for (var k in sortedReason) {
        data.add(['Devamsızlık Nedeni', k, reasonCounts[k].toString()]);
      }
    }

    final pdfBytes = await pdfService.generateSubstituteTeacherReportPdf(
      title: title,
      dateRange: dateRange,
      headers: headers,
      data: data,
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdfBytes,
      name: 'gecici_gorevlendirme_raporu',
    );
  }
}
