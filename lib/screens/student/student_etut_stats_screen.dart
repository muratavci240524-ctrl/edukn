import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Öğrenciye özel etüt istatistikleri ekranı.
/// etut_requests koleksiyonundan studentId bazlı veri çeker.
class StudentEtutStatsScreen extends StatefulWidget {
  final String institutionId;
  final String studentId;

  const StudentEtutStatsScreen({
    Key? key,
    required this.institutionId,
    required this.studentId,
  }) : super(key: key);

  @override
  State<StudentEtutStatsScreen> createState() => _StudentEtutStatsScreenState();
}

class _StudentEtutStatsScreenState extends State<StudentEtutStatsScreen> {
  bool _loading = true;
  List<_EtutRecord> _all = [];
  Map<String, String> _teacherNames = {};
  String _dateFilter = 'Tümü';

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('tr_TR', null);
    _loadData();
  }

  // ─────────────────── DATA ────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      // 1. Fetch teacher names
      final usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();
      final teacherMap = <String, String>{};
      for (final doc in usersSnap.docs) {
        final d = doc.data();
        final name = (d['fullName'] ??
                '${d['firstName'] ?? ''} ${d['lastName'] ?? ''}'.trim())
            .toString()
            .trim();
        teacherMap[doc.id] = name.isNotEmpty ? name : 'Öğretmen';
        if (d['uid'] != null) teacherMap[d['uid'].toString()] = teacherMap[doc.id]!;
      }

      // 2. Fetch etut requests for this student
      final etutSnap = await FirebaseFirestore.instance
          .collection('etut_requests')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('studentIds', arrayContains: widget.studentId)
          .get();

      final records = <_EtutRecord>[];
      final now = DateTime.now();

      for (final doc in etutSnap.docs) {
        final d = doc.data();
        final teacherId = (d['teacherId'] ?? '').toString();
        final isRecurring = d['isRecurring'] == true;
        final startVal = d['startTime'];
        final endVal = d['endTime'];

        // Calculate duration in minutes
        int durationMinutes = 0;
        DateTime? startTime;
        DateTime? endTime;
        if (startVal is Timestamp && endVal is Timestamp) {
          startTime = startVal.toDate();
          endTime = endVal.toDate();
          durationMinutes = endTime.difference(startTime).inMinutes;
          if (durationMinutes < 0) durationMinutes = 0;
        }

        if (isRecurring) {
          // Recurring: expand to actual dates (up to today, last 6 months)
          final dayIndex = (d['dayIndex'] as int?) ?? 0; // 0=Mon
          final cancelledDates =
              List<String>.from(d['cancelledDates'] ?? []);
          final cutoff = now.subtract(const Duration(days: 180));

          // Find start of the recurring sessions from 6 months ago
          DateTime cursor = now.subtract(const Duration(days: 6 * 30));
          // Align to correct weekday
          while (cursor.weekday - 1 != dayIndex) {
            cursor = cursor.add(const Duration(days: 1));
          }
          while (!cursor.isAfter(now)) {
            final dateStr =
                '${cursor.year}-${cursor.month.toString().padLeft(2, '0')}-${cursor.day.toString().padLeft(2, '0')}';
            if (!cancelledDates.contains(dateStr)) {
              records.add(_EtutRecord(
                date: cursor,
                teacherId: teacherId,
                durationMinutes: durationMinutes,
                isRecurring: true,
                startTime: startTime,
                endTime: endTime,
              ));
            }
            cursor = cursor.add(const Duration(days: 7));
          }
        } else {
          // One-time
          final dateVal = d['date'];
          DateTime? date;
          if (dateVal is Timestamp) {
            date = dateVal.toDate();
          } else if (dateVal is String) {
            date = DateTime.tryParse(dateVal);
          }
          if (date != null) {
            records.add(_EtutRecord(
              date: date,
              teacherId: teacherId,
              durationMinutes: durationMinutes,
              isRecurring: false,
              startTime: startTime,
              endTime: endTime,
            ));
          }
        }
      }

      // Sort newest first
      records.sort((a, b) => b.date.compareTo(a.date));

      if (mounted) {
        setState(() {
          _all = records;
          _teacherNames = teacherMap;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('StudentEtutStats error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─────────────────── FILTER ───────────────────────────────────────────────────

  List<_EtutRecord> get _filtered {
    final now = DateTime.now();
    return _all.where((r) {
      if (_dateFilter == 'Bu Hafta') {
        final monday = now.subtract(Duration(days: now.weekday - 1));
        final start = DateTime(monday.year, monday.month, monday.day);
        final end = start.add(const Duration(days: 7));
        return !r.date.isBefore(start) && r.date.isBefore(end);
      } else if (_dateFilter == 'Bu Ay') {
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 1);
        return !r.date.isBefore(start) && r.date.isBefore(end);
      }
      return true;
    }).toList();
  }

  // ─────────────────── BUILD ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: const BackButton(color: Color(0xFF7C3AED)),
        title: const Text(
          'Etüt İstatistiklerim',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF7C3AED)),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF7C3AED)))
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  padding: EdgeInsets.all(isMobile ? 16 : 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDateFilter(),
                      const SizedBox(height: 20),
                      _buildHeroBanner(filtered),
                      const SizedBox(height: 20),
                      _buildStatCards(filtered),
                      const SizedBox(height: 24),
                      if (filtered.isNotEmpty) ...[
                        _buildMonthlyChart(filtered, isMobile),
                        const SizedBox(height: 24),
                        _buildTeacherBreakdown(filtered, isMobile),
                        const SizedBox(height: 24),
                      ],
                      _buildSessionList(filtered, isMobile),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // ─────────────────── DATE FILTER ─────────────────────────────────────────────

  Widget _buildDateFilter() {
    final options = ['Tümü', 'Bu Ay', 'Bu Hafta'];
    return Row(
      children: options.map((opt) {
        final sel = _dateFilter == opt;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => setState(() => _dateFilter = opt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: sel ? const Color(0xFF7C3AED) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: sel ? const Color(0xFF7C3AED) : Colors.grey.shade300,
                ),
                boxShadow: sel
                    ? [
                        BoxShadow(
                          color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        )
                      ]
                    : [],
              ),
              child: Text(
                opt,
                style: TextStyle(
                  color: sel ? Colors.white : Colors.grey.shade700,
                  fontWeight: sel ? FontWeight.bold : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─────────────────── HERO BANNER ─────────────────────────────────────────────

  Widget _buildHeroBanner(List<_EtutRecord> records) {
    final totalSessions = records.length;
    final totalMinutes =
        records.fold<int>(0, (sum, r) => sum + r.durationMinutes);
    final totalHours = totalMinutes ~/ 60;
    final remainingMin = totalMinutes % 60;
    final uniqueTeachers =
        records.map((r) => r.teacherId).where((t) => t.isNotEmpty).toSet().length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFFBD7BE5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Toplam Etüt Sürem',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 6),
                Text(
                  totalMinutes == 0
                      ? '— saat'
                      : '${totalHours}s ${remainingMin}dk',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  children: [
                    _heroStat('$totalSessions', 'Seans'),
                    _heroStat('$uniqueTeachers', 'Öğretmen'),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.menu_book_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }

  // ─────────────────── STAT CARDS ──────────────────────────────────────────────

  Widget _buildStatCards(List<_EtutRecord> records) {
    final totalSessions = records.length;
    final totalMinutes =
        records.fold<int>(0, (sum, r) => sum + r.durationMinutes);
    final totalHours = (totalMinutes / 60).toStringAsFixed(1);
    final recurring = records.where((r) => r.isRecurring).length;
    final oneTime = records.where((r) => !r.isRecurring).length;

    final cards = [
      _StatData('Toplam Seans', totalSessions, Icons.event_note_rounded,
          const Color(0xFF7C3AED), const Color(0xFFF5F3FF)),
      _StatData('Toplam Saat', 0, Icons.timer_rounded,
          const Color(0xFF0EA5E9), const Color(0xFFE0F2FE),
          subtitle: '$totalHours saat'),
      _StatData('Düzenli Etüt', recurring, Icons.repeat_rounded,
          const Color(0xFF10B981), const Color(0xFFECFDF5)),
      _StatData('Tek Seferlik', oneTime, Icons.event_rounded,
          const Color(0xFFF59E0B), const Color(0xFFFFFBEB)),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxis = constraints.maxWidth < 500 ? 2 : 4;
        final spacing = 12.0;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxis,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: constraints.maxWidth < 500 ? 1.3 : 1.5,
          ),
          itemCount: cards.length,
          itemBuilder: (_, i) => _buildStatCard(cards[i]),
        );
      },
    );
  }

  Widget _buildStatCard(_StatData c) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: c.color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: c.bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(c.icon, color: c.color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            c.subtitle ?? '${c.count}',
            style: TextStyle(
              fontSize: c.subtitle != null ? 18 : 26,
              fontWeight: FontWeight.w900,
              color: c.color,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            c.label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────── MONTHLY CHART ───────────────────────────────────────────

  Widget _buildMonthlyChart(List<_EtutRecord> records, bool isMobile) {
    // Group by month → session count + total minutes
    final monthly = <String, _MonthStats>{};
    for (final r in records) {
      final key =
          '${r.date.year}-${r.date.month.toString().padLeft(2, '0')}';
      monthly.putIfAbsent(key, () => _MonthStats(r.date.year, r.date.month));
      monthly[key]!.sessions++;
      monthly[key]!.minutes += r.durationMinutes;
    }

    final sortedKeys = monthly.keys.toList()..sort();
    if (sortedKeys.isEmpty) return const SizedBox.shrink();

    const monthNames = [
      '', 'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
      'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'
    ];

    final maxSessions =
        monthly.values.map((m) => m.sessions).reduce((a, b) => a > b ? a : b);

    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < sortedKeys.length; i++) {
      final m = monthly[sortedKeys[i]]!;
      barGroups.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: m.sessions.toDouble(),
            gradient: const LinearGradient(
              colors: [Color(0xFF7C3AED), Color(0xFFBD7BE5)],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
            width: 22,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
        ],
      ));
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Aylık Etüt Seansları',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                barGroups: barGroups,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: Colors.grey.shade100,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                maxY: (maxSessions + 2).toDouble(),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, m) => Text(
                        v.toInt().toString(),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, m) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= sortedKeys.length) {
                          return const SizedBox.shrink();
                        }
                        final ms = monthly[sortedKeys[idx]]!;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            monthNames[ms.month],
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF7C3AED),
                    getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                      '${rod.toY.toInt()} seans',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────── TEACHER BREAKDOWN ────────────────────────────────────────

  Widget _buildTeacherBreakdown(List<_EtutRecord> records, bool isMobile) {
    final teacherCount = <String, int>{};
    for (final r in records) {
      if (r.teacherId.isNotEmpty) {
        teacherCount[r.teacherId] = (teacherCount[r.teacherId] ?? 0) + 1;
      }
    }

    if (teacherCount.isEmpty) return const SizedBox.shrink();

    final sorted = teacherCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = records.length;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Öğretmene Göre Dağılım',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),
          ...sorted.take(5).map((entry) {
            final name = _teacherNames[entry.key] ?? 'Öğretmen';
            final ratio = total > 0 ? entry.value / total : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Color(0xFF1E293B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${entry.value} seans',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      backgroundColor: const Color(0xFFEDE9FE),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF7C3AED)),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  // ─────────────────── SESSION LIST ─────────────────────────────────────────────

  Widget _buildSessionList(List<_EtutRecord> records, bool isMobile) {
    if (records.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(Icons.menu_book_outlined, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Bu dönem için etüt kaydı bulunamadı.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
            ),
          ],
        ),
      );
    }

    final fmt = DateFormat('dd MMM yyyy, EEEE', 'tr_TR');
    final timeFmt = DateFormat('HH:mm', 'tr_TR');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Etüt Seansları',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFEDE9FE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${records.length}',
                style: const TextStyle(
                  color: Color(0xFF7C3AED),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...records.take(50).map((r) {
          final teacherName =
              _teacherNames[r.teacherId] ?? 'Öğretmen';
          final timeStr = r.startTime != null && r.endTime != null
              ? '${timeFmt.format(r.startTime!)} – ${timeFmt.format(r.endTime!)}'
              : '';
          final durationStr = r.durationMinutes > 0
              ? '${r.durationMinutes ~/ 60}s ${r.durationMinutes % 60}dk'
              : '';

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border(
                left: BorderSide(
                  color: r.isRecurring
                      ? const Color(0xFF10B981)
                      : const Color(0xFF7C3AED),
                  width: 4,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: r.isRecurring
                          ? const Color(0xFFECFDF5)
                          : const Color(0xFFEDE9FE),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      r.isRecurring
                          ? Icons.repeat_rounded
                          : Icons.event_rounded,
                      color: r.isRecurring
                          ? const Color(0xFF10B981)
                          : const Color(0xFF7C3AED),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fmt.format(r.date),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 12,
                          children: [
                            if (teacherName.isNotEmpty)
                              _infoChip(Icons.person_outline_rounded,
                                  teacherName, Colors.indigo.shade400),
                            if (timeStr.isNotEmpty)
                              _infoChip(Icons.access_time_rounded,
                                  timeStr, Colors.grey.shade500),
                            if (durationStr.isNotEmpty)
                              _infoChip(Icons.hourglass_bottom_rounded,
                                  durationStr, Colors.purple.shade400),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: r.isRecurring
                          ? const Color(0xFFECFDF5)
                          : const Color(0xFFEDE9FE),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      r.isRecurring ? 'Düzenli' : 'Tek Seferlik',
                      style: TextStyle(
                        color: r.isRecurring
                            ? const Color(0xFF10B981)
                            : const Color(0xFF7C3AED),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─────────────────── MODELS ──────────────────────────────────────────────────

class _EtutRecord {
  final DateTime date;
  final String teacherId;
  final int durationMinutes;
  final bool isRecurring;
  final DateTime? startTime;
  final DateTime? endTime;

  const _EtutRecord({
    required this.date,
    required this.teacherId,
    required this.durationMinutes,
    required this.isRecurring,
    this.startTime,
    this.endTime,
  });
}

class _MonthStats {
  final int year;
  final int month;
  int sessions = 0;
  int minutes = 0;
  _MonthStats(this.year, this.month);
}

class _StatData {
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String? subtitle;
  const _StatData(this.label, this.count, this.icon, this.color, this.bgColor,
      {this.subtitle});
}
