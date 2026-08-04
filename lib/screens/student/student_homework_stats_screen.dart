import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Öğrenciye özel ödev istatistik ekranı.
/// classId'ye göre tüm ödevleri çeker, studentId'ye göre filtreleyerek
/// branş ve tarih bazlı istatistik gösterir.
class StudentHomeworkStatsScreen extends StatefulWidget {
  final String institutionId;
  final String studentId;
  final String classId;

  const StudentHomeworkStatsScreen({
    Key? key,
    required this.institutionId,
    required this.studentId,
    required this.classId,
  }) : super(key: key);

  @override
  State<StudentHomeworkStatsScreen> createState() =>
      _StudentHomeworkStatsScreenState();
}

class _StudentHomeworkStatsScreenState
    extends State<StudentHomeworkStatsScreen> {
  bool _loading = true;

  // Data
  List<_HwItem> _allHw = [];
  Map<String, String> _lessonNames = {}; // lessonId -> name

  // Filters
  String _dateFilter = 'Tümü'; // 'Tümü' | 'Bu Hafta' | 'Bu Ay'
  String _lessonFilter = 'Tümü'; // 'Tümü' | lessonId
  int? _hoveredPieIndex;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('tr_TR', null);
    _loadData();
  }

  // ─────────────────── DATA LOADING ───────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      // 1. Fetch lessons
      final lSnap = await FirebaseFirestore.instance
          .collection('lessons')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();
      final lessonMap = <String, String>{};
      for (final doc in lSnap.docs) {
        final d = doc.data();
        lessonMap[doc.id] =
            (d['name'] ?? d['lessonName'] ?? 'Ders').toString();
      }

      // 2. Fetch homeworks for this class
      final hSnap = await FirebaseFirestore.instance
          .collection('homeworks')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('classId', isEqualTo: widget.classId)
          .get();

      final items = <_HwItem>[];
      for (final doc in hSnap.docs) {
        final d = doc.data();
        d['id'] = doc.id;
        final targets = List<String>.from(d['targetStudentIds'] ?? []);
        if (targets.isEmpty || targets.contains(widget.studentId)) {
          final statuses = Map<String, int>.from(d['studentStatuses'] ?? {});
          final statusVal = statuses[widget.studentId] ?? 0;
          final assignedDate = d['assignedDate'] != null
              ? (d['assignedDate'] as Timestamp).toDate()
              : (d['createdAt'] as Timestamp).toDate();
          final dueDate = (d['dueDate'] as Timestamp).toDate();
          items.add(_HwItem(
            id: doc.id,
            title: (d['title'] ?? 'Ödev').toString(),
            lessonId: (d['lessonId'] ?? '').toString(),
            assignedDate: assignedDate,
            dueDate: dueDate,
            status: _hwStatus(statusVal),
          ));
        }
      }

      // Sort newest first
      items.sort((a, b) => b.assignedDate.compareTo(a.assignedDate));

      if (mounted) {
        setState(() {
          _lessonNames = lessonMap;
          _allHw = items;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('StudentHomeworkStats error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  _HwStatus _hwStatus(int val) {
    switch (val) {
      case 1:
        return _HwStatus.completed;
      case 2:
        return _HwStatus.notCompleted;
      case 3:
        return _HwStatus.missing;
      case 4:
        return _HwStatus.notBrought;
      default:
        return _HwStatus.pending;
    }
  }

  // ─────────────────── FILTERED DATA ──────────────────────────────────────────

  List<_HwItem> get _filtered {
    final now = DateTime.now();
    return _allHw.where((hw) {
      // Date filter
      if (_dateFilter == 'Bu Hafta') {
        final monday = now.subtract(Duration(days: now.weekday - 1));
        final start = DateTime(monday.year, monday.month, monday.day);
        final end = start.add(const Duration(days: 7));
        if (hw.assignedDate.isBefore(start) || hw.assignedDate.isAfter(end)) {
          return false;
        }
      } else if (_dateFilter == 'Bu Ay') {
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        if (hw.assignedDate.isBefore(start) || hw.assignedDate.isAfter(end)) {
          return false;
        }
      }
      // Lesson filter
      if (_lessonFilter != 'Tümü' && hw.lessonId != _lessonFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  // ─────────────────── BUILD ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: const BackButton(color: Colors.indigo),
        title: const Text(
          'Ödev İstatistiklerim',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
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
                      const SizedBox(height: 16),
                      _buildStatsSection(isMobile),
                      const SizedBox(height: 24),
                      _buildLessonFilter(),
                      const SizedBox(height: 16),
                      _buildHomeworkList(isMobile),
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
    final options = ['Tümü', 'Bu Hafta', 'Bu Ay'];
    return Row(
      children: options.map((opt) {
        final selected = _dateFilter == opt;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => setState(() => _dateFilter = opt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? Colors.indigo : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? Colors.indigo : Colors.grey.shade300,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: Colors.indigo.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        )
                      ]
                    : [],
              ),
              child: Text(
                opt,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.grey.shade700,
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─────────────────── STATS SECTION ───────────────────────────────────────────

  Widget _buildStatsSection(bool isMobile) {
    final hw = _filtered;
    final total = hw.length;
    final done = hw.where((h) => h.status == _HwStatus.completed).length;
    final missing = hw.where((h) => h.status == _HwStatus.missing).length;
    final notDone = hw.where((h) => h.status == _HwStatus.notCompleted).length;
    final notBrought = hw.where((h) => h.status == _HwStatus.notBrought).length;
    final pending = hw.where((h) => h.status == _HwStatus.pending).length;

    if (total == 0) {
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
            Icon(Icons.assignment_outlined, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Bu dönem için ödev bulunamadı.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
            ),
          ],
        ),
      );
    }

    final completionRate = total > 0 ? (done / total * 100) : 0.0;

    return isMobile
        ? Column(
            children: [
              _buildPieCard(total, done, missing, notDone, notBrought, pending, completionRate),
              const SizedBox(height: 16),
              _buildStatCards(total, done, missing, notDone, notBrought, pending),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 280,
                child: _buildPieCard(total, done, missing, notDone, notBrought, pending, completionRate),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: _buildStatCards(total, done, missing, notDone, notBrought, pending),
              ),
            ],
          );
  }

  Widget _buildPieCard(int total, int done, int missing, int notDone,
      int notBrought, int pending, double completionRate) {
    final sections = <PieChartSectionData>[];
    void addSection(int count, Color color, String title, int index) {
      if (count == 0) return;
      final isHovered = _hoveredPieIndex == index;
      sections.add(PieChartSectionData(
        value: count.toDouble(),
        color: color,
        radius: isHovered ? 60 : 52,
        title: count > 0 ? '$count' : '',
        titleStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
        badgeWidget: null,
      ));
    }

    addSection(done, const Color(0xFF10B981), 'Yapıldı', 0);
    addSection(missing, const Color(0xFFF59E0B), 'Eksik', 1);
    addSection(notDone, const Color(0xFFEF4444), 'Yapılmadı', 2);
    addSection(notBrought, const Color(0xFF8B5CF6), 'Getirilmedi', 3);
    addSection(pending, const Color(0xFF94A3B8), 'Beklemede', 4);

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
        children: [
          const Text(
            'Ödev Dağılımı',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sections: sections.isEmpty
                        ? [
                            PieChartSectionData(
                              value: 1,
                              color: Colors.grey.shade200,
                              title: '',
                              radius: 52,
                            )
                          ]
                        : sections,
                    centerSpaceRadius: 52,
                    sectionsSpace: 3,
                    pieTouchData: PieTouchData(
                      touchCallback: (event, response) {
                        setState(() {
                          if (response?.touchedSection != null) {
                            _hoveredPieIndex =
                                response!.touchedSection!.touchedSectionIndex;
                          } else {
                            _hoveredPieIndex = null;
                          }
                        });
                      },
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${completionRate.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const Text(
                      'Tamamlama',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildLegend(),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        _legendItem('Yapıldı', const Color(0xFF10B981)),
        _legendItem('Eksik', const Color(0xFFF59E0B)),
        _legendItem('Yapılmadı', const Color(0xFFEF4444)),
        _legendItem('Getirilmedi', const Color(0xFF8B5CF6)),
        _legendItem('Beklemede', const Color(0xFF94A3B8)),
      ],
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  Widget _buildStatCards(
      int total, int done, int missing, int notDone, int notBrought, int pending) {
    final cards = [
      _StatCardData(
        label: 'Toplam Ödev',
        count: total,
        icon: Icons.assignment_rounded,
        color: Colors.indigo,
        bgColor: const Color(0xFFEEF2FF),
      ),
      _StatCardData(
        label: 'Yapıldı',
        count: done,
        icon: Icons.check_circle_rounded,
        color: const Color(0xFF10B981),
        bgColor: const Color(0xFFECFDF5),
      ),
      _StatCardData(
        label: 'Eksik Yapıldı',
        count: missing,
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFF59E0B),
        bgColor: const Color(0xFFFFFBEB),
      ),
      _StatCardData(
        label: 'Yapılmadı',
        count: notDone,
        icon: Icons.cancel_rounded,
        color: const Color(0xFFEF4444),
        bgColor: const Color(0xFFFEF2F2),
      ),
      _StatCardData(
        label: 'Getirilmedi',
        count: notBrought,
        icon: Icons.backpack_rounded,
        color: const Color(0xFF8B5CF6),
        bgColor: const Color(0xFFF5F3FF),
      ),
      _StatCardData(
        label: 'Beklemede',
        count: pending,
        icon: Icons.hourglass_empty_rounded,
        color: const Color(0xFF94A3B8),
        bgColor: const Color(0xFFF8FAFC),
      ),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: cards.map((c) => _buildStatCard(c)).toList(),
    );
  }

  Widget _buildStatCard(_StatCardData c) {
    return Container(
      width: 140,
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
              fontSize: 28,
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

  // ─────────────────── LESSON FILTER ───────────────────────────────────────────

  Widget _buildLessonFilter() {
    // Only show lessons that appear in filtered (by date) homeworks
    final dateFilteredHw = _filtered;
    final lessonIds = dateFilteredHw
        .map((h) => h.lessonId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (lessonIds.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Branşa Göre Filtrele',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _lessonChip('Tümü', 'Tümü'),
              ...lessonIds
                  .map((id) => _lessonChip(_lessonNames[id] ?? id, id))
                  .toList(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _lessonChip(String label, String id) {
    final selected = _lessonFilter == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _lessonFilter = id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.indigo.shade600 : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? Colors.indigo.shade600 : Colors.grey.shade300,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.indigo.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    )
                  ]
                : [],
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.grey.shade700,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────── HOMEWORK LIST ───────────────────────────────────────────

  Widget _buildHomeworkList(bool isMobile) {
    final hw = _filtered;
    if (hw.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          children: [
            Icon(Icons.assignment_late_outlined,
                size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Seçili filtrelere göre ödev bulunamadı.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Ödev Listesi',
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
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${hw.length}',
                style: TextStyle(
                  color: Colors.indigo.shade700,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...hw.map((item) => _buildHwRow(item, isMobile)).toList(),
      ],
    );
  }

  Widget _buildHwRow(_HwItem item, bool isMobile) {
    final statusConfig = _statusConfig(item.status);
    final fmt = DateFormat('dd MMM yyyy', 'tr_TR');
    final lessonLabel = item.lessonId.isNotEmpty
        ? (_lessonNames[item.lessonId] ?? item.lessonId)
        : 'Ders';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
            color: statusConfig.color,
            width: 4,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Left: status icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: statusConfig.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(statusConfig.icon, color: statusConfig.color, size: 20),
            ),
            const SizedBox(width: 14),
            // Center: info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Color(0xFF1E293B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _infoChip(Icons.book_outlined, lessonLabel,
                          Colors.indigo.shade400),
                      _infoChip(Icons.calendar_today_outlined,
                          'Verildi: ${fmt.format(item.assignedDate)}',
                          Colors.grey.shade500),
                      _infoChip(Icons.event_outlined,
                          'Son: ${fmt.format(item.dueDate)}',
                          item.dueDate.isBefore(DateTime.now())
                              ? Colors.red.shade400
                              : Colors.grey.shade500),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Right: status badge
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: statusConfig.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                statusConfig.label,
                style: TextStyle(
                  color: statusConfig.color,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
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
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  _StatusConfig _statusConfig(_HwStatus status) {
    switch (status) {
      case _HwStatus.completed:
        return _StatusConfig('Yapıldı', Icons.check_circle_rounded, const Color(0xFF10B981));
      case _HwStatus.missing:
        return _StatusConfig('Eksik', Icons.warning_amber_rounded, const Color(0xFFF59E0B));
      case _HwStatus.notCompleted:
        return _StatusConfig('Yapılmadı', Icons.cancel_rounded, const Color(0xFFEF4444));
      case _HwStatus.notBrought:
        return _StatusConfig('Getirilmedi', Icons.backpack_rounded, const Color(0xFF8B5CF6));
      case _HwStatus.pending:
        return _StatusConfig('Beklemede', Icons.hourglass_empty_rounded, const Color(0xFF94A3B8));
    }
  }
}

// ─────────────────── MODELS ──────────────────────────────────────────────────

enum _HwStatus { completed, missing, notCompleted, notBrought, pending }

class _HwItem {
  final String id;
  final String title;
  final String lessonId;
  final DateTime assignedDate;
  final DateTime dueDate;
  final _HwStatus status;

  const _HwItem({
    required this.id,
    required this.title,
    required this.lessonId,
    required this.assignedDate,
    required this.dueDate,
    required this.status,
  });
}

class _StatCardData {
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final Color bgColor;
  const _StatCardData({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.bgColor,
  });
}

class _StatusConfig {
  final String label;
  final IconData icon;
  final Color color;
  const _StatusConfig(this.label, this.icon, this.color);
}
