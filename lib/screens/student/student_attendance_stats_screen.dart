import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Öğrenciye özel yoklama istatistik ekranı.
/// lessonAttendance koleksiyonundan classId + studentId bazlı veri çeker.
class StudentAttendanceStatsScreen extends StatefulWidget {
  final String institutionId;
  final String studentId;
  final String classId;
  final String studentName;

  const StudentAttendanceStatsScreen({
    Key? key,
    required this.institutionId,
    required this.studentId,
    required this.classId,
    required this.studentName,
  }) : super(key: key);

  @override
  State<StudentAttendanceStatsScreen> createState() =>
      _StudentAttendanceStatsScreenState();
}

class _StudentAttendanceStatsScreenState
    extends State<StudentAttendanceStatsScreen> {
  bool _loading = true;
  List<_AttRecord> _all = [];
  String _dateFilter = 'Dönem';
  int? _hoveredBar;

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
      final snap = await FirebaseFirestore.instance
          .collection('lessonAttendance')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('classId', isEqualTo: widget.classId)
          .get();

      final records = <_AttRecord>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        // institutionId guard
        if ((d['institutionId'] ?? '').toString() != widget.institutionId) {
          continue;
        }
        final statusRaw = d['studentStatuses'];
        if (statusRaw is! Map) continue;
        final statuses = Map<String, dynamic>.from(statusRaw);
        final rawStatus = statuses[widget.studentId];
        if (rawStatus == null) continue; // not recorded for this student

        final dateStr = (d['date'] ?? '').toString();
        final date = DateTime.tryParse(dateStr) ?? DateTime(2000);
        final lessonHour = d['lessonHour'];
        final hour = lessonHour is int
            ? lessonHour
            : int.tryParse((lessonHour ?? '').toString()) ?? 0;

        records.add(_AttRecord(
          date: date,
          lessonHour: hour,
          status: _parseStatus(rawStatus.toString()),
        ));
      }

      // Sort newest first
      records.sort((a, b) => b.date.compareTo(a.date));

      if (mounted) {
        setState(() {
          _all = records;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('StudentAttendanceStats error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  _AttStatus _parseStatus(String s) {
    switch (s) {
      case 'present':
        return _AttStatus.present;
      case 'absent':
        return _AttStatus.absent;
      case 'late':
        return _AttStatus.late;
      case 'excused':
        return _AttStatus.excused;
      case 'onDuty':
        return _AttStatus.onDuty;
      case 'reported':
        return _AttStatus.reported;
      default:
        return _AttStatus.present;
    }
  }

  // ─────────────────── FILTER ───────────────────────────────────────────────────

  List<_AttRecord> get _filtered {
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
      return true; // 'Dönem' — all
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
        leading: const BackButton(color: Colors.indigo),
        title: const Text(
          'Yoklama İstatistiklerim',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.indigo),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
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
                      _buildStatsSection(filtered, isMobile),
                      const SizedBox(height: 24),
                      _buildBarChart(filtered, isMobile),
                      const SizedBox(height: 24),
                      _buildRecordList(filtered, isMobile),
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
    final options = ['Dönem', 'Bu Ay', 'Bu Hafta'];
    return Row(
      children: options.map((opt) {
        final sel = _dateFilter == opt;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => setState(() => _dateFilter = opt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: sel ? Colors.teal.shade600 : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: sel ? Colors.teal.shade600 : Colors.grey.shade300,
                ),
                boxShadow: sel
                    ? [
                        BoxShadow(
                          color: Colors.teal.withValues(alpha: 0.3),
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

  // ─────────────────── STAT CARDS ──────────────────────────────────────────────

  Widget _buildStatsSection(List<_AttRecord> records, bool isMobile) {
    final total = records.length;
    final present = records.where((r) => r.status == _AttStatus.present).length;
    final absent = records.where((r) => r.status == _AttStatus.absent).length;
    final late = records.where((r) => r.status == _AttStatus.late).length;
    final excused = records.where((r) => r.status == _AttStatus.excused).length;
    final onDuty = records.where((r) => r.status == _AttStatus.onDuty).length;
    final reported = records.where((r) => r.status == _AttStatus.reported).length;

    final attendanceRate =
        total > 0 ? ((present + late + onDuty) / total * 100) : 0.0;

    if (total == 0) {
      return _emptyCard('Bu dönem için yoklama kaydı bulunamadı.');
    }

    final cards = [
      _StatData('Toplam Kayıt', total, Icons.list_alt_rounded, Colors.indigo, const Color(0xFFEEF2FF)),
      _StatData('Devam', present, Icons.check_circle_rounded, const Color(0xFF10B981), const Color(0xFFECFDF5)),
      _StatData('Devamsız', absent, Icons.cancel_rounded, const Color(0xFFEF4444), const Color(0xFFFEF2F2)),
      _StatData('Geç', late, Icons.timer_outlined, const Color(0xFFF59E0B), const Color(0xFFFFFBEB)),
      _StatData('Mazeretli', excused, Icons.assignment_ind_rounded, const Color(0xFF3B82F6), const Color(0xFFEFF6FF)),
      _StatData('Nöbetçi', onDuty, Icons.star_rounded, const Color(0xFF8B5CF6), const Color(0xFFF5F3FF)),
      _StatData('Raporlu', reported, Icons.local_hospital_rounded, const Color(0xFF6B7280), const Color(0xFFF9FAFB)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Attendance rate hero
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal.shade700, Colors.teal.shade400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.teal.withValues(alpha: 0.35),
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
                      'Devam Oranı',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '%${attendanceRate.toStringAsFixed(1)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$total kayıttan ${present + late + onDuty} devam',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              // Ring
              SizedBox(
                width: 90,
                height: 90,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: attendanceRate / 100,
                      strokeWidth: 10,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                    Text(
                      '${attendanceRate.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Stat cards
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards.map((c) => _buildStatCard(c)).toList(),
        ),
      ],
    );
  }

  Widget _buildStatCard(_StatData c) {
    return Container(
      width: 130,
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
            '${c.count}',
            style: TextStyle(
              fontSize: 26,
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

  // ─────────────────── BAR CHART (Monthly breakdown) ───────────────────────────

  Widget _buildBarChart(List<_AttRecord> records, bool isMobile) {
    if (records.isEmpty) return const SizedBox.shrink();

    // Group by month
    final monthly = <String, _MonthData>{};
    for (final r in records) {
      final key = '${r.date.year}-${r.date.month.toString().padLeft(2, '0')}';
      monthly.putIfAbsent(key, () => _MonthData(r.date.year, r.date.month));
      final md = monthly[key]!;
      switch (r.status) {
        case _AttStatus.present:
          md.present++;
          break;
        case _AttStatus.absent:
          md.absent++;
          break;
        case _AttStatus.late:
          md.late++;
          break;
        case _AttStatus.excused:
          md.excused++;
          break;
        case _AttStatus.onDuty:
        case _AttStatus.reported:
          break;
      }
    }

    final sortedKeys = monthly.keys.toList()..sort();
    if (sortedKeys.isEmpty) return const SizedBox.shrink();

    const monthNames = [
      '', 'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
      'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'
    ];

    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < sortedKeys.length; i++) {
      final md = monthly[sortedKeys[i]]!;
      barGroups.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: md.present.toDouble(),
            color: const Color(0xFF10B981),
            width: 10,
            borderRadius: BorderRadius.circular(4),
          ),
          BarChartRodData(
            toY: md.absent.toDouble(),
            color: const Color(0xFFEF4444),
            width: 10,
            borderRadius: BorderRadius.circular(4),
          ),
          BarChartRodData(
            toY: md.late.toDouble(),
            color: const Color(0xFFF59E0B),
            width: 10,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
        showingTooltipIndicators: [],
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Aylık Devam Grafiği',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF1E293B),
                ),
              ),
              Wrap(
                spacing: 12,
                children: [
                  _legendDot('Devam', const Color(0xFF10B981)),
                  _legendDot('Devamsız', const Color(0xFFEF4444)),
                  _legendDot('Geç', const Color(0xFFF59E0B)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
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
                        final md = monthly[sortedKeys[idx]]!;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            monthNames[md.month],
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
                    getTooltipColor: (_) => Colors.grey.shade800,
                    getTooltipItem: (group, gi, rod, ri) {
                      final labels = ['Devam', 'Devamsız', 'Geç'];
                      return BarTooltipItem(
                        '${labels[ri]}: ${rod.toY.toInt()}',
                        const TextStyle(color: Colors.white, fontSize: 11),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }

  // ─────────────────── RECORD LIST ─────────────────────────────────────────────

  Widget _buildRecordList(List<_AttRecord> records, bool isMobile) {
    final nonPresent = records.where((r) => r.status != _AttStatus.present).toList();
    if (nonPresent.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            const Icon(Icons.celebration_rounded, size: 48, color: Color(0xFF10B981)),
            const SizedBox(height: 12),
            const Text(
              'Tebrikler! Bu dönemde tüm derslere devam ettiniz.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF065F46),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    final fmt = DateFormat('dd MMM yyyy, EEEE', 'tr_TR');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Devamsızlık & Geç Kayıtları',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${nonPresent.length}',
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...nonPresent.map((r) {
          final cfg = _statusConfig(r.status);
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
                left: BorderSide(color: cfg.color, width: 4),
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
                      color: cfg.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(cfg.icon, color: cfg.color, size: 20),
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
                        Row(
                          children: [
                            Icon(Icons.school_outlined, size: 12, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text(
                              '${r.lessonHour}. Ders',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: cfg.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      cfg.label,
                      style: TextStyle(
                        color: cfg.color,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
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

  // ─────────────────── HELPERS ─────────────────────────────────────────────────

  Widget _emptyCard(String msg) {
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
          Icon(Icons.event_busy_outlined, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(msg, style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
        ],
      ),
    );
  }

  _StatusConfig _statusConfig(_AttStatus s) {
    switch (s) {
      case _AttStatus.present:
        return _StatusConfig('Devam', Icons.check_circle_rounded, const Color(0xFF10B981));
      case _AttStatus.absent:
        return _StatusConfig('Devamsız', Icons.cancel_rounded, const Color(0xFFEF4444));
      case _AttStatus.late:
        return _StatusConfig('Geç', Icons.timer_outlined, const Color(0xFFF59E0B));
      case _AttStatus.excused:
        return _StatusConfig('Mazeretli', Icons.assignment_ind_rounded, const Color(0xFF3B82F6));
      case _AttStatus.onDuty:
        return _StatusConfig('Nöbetçi', Icons.star_rounded, const Color(0xFF8B5CF6));
      case _AttStatus.reported:
        return _StatusConfig('Raporlu', Icons.local_hospital_rounded, const Color(0xFF6B7280));
    }
  }
}

// ─────────────────── MODELS ──────────────────────────────────────────────────

enum _AttStatus { present, absent, late, excused, onDuty, reported }

class _AttRecord {
  final DateTime date;
  final int lessonHour;
  final _AttStatus status;
  const _AttRecord({
    required this.date,
    required this.lessonHour,
    required this.status,
  });
}

class _MonthData {
  final int year;
  final int month;
  int present = 0;
  int absent = 0;
  int late = 0;
  int excused = 0;
  _MonthData(this.year, this.month);
}

class _StatData {
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final Color bgColor;
  const _StatData(this.label, this.count, this.icon, this.color, this.bgColor);
}

class _StatusConfig {
  final String label;
  final IconData icon;
  final Color color;
  const _StatusConfig(this.label, this.icon, this.color);
}
