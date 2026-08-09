import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/todo_task.dart';

class TaskStatsScreen extends StatefulWidget {
  final String institutionId;
  final String? termId;

  const TaskStatsScreen({
    Key? key,
    required this.institutionId,
    this.termId,
  }) : super(key: key);

  @override
  State<TaskStatsScreen> createState() => _TaskStatsScreenState();
}

class _TaskStatsScreenState extends State<TaskStatsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<ToDoTask> _tasks = [];
  bool _isLoading = true;

  // — Hesaplanmış istatistikler —
  _TaskStats? _stats;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadTasks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    try {
      Query query = FirebaseFirestore.instance
          .collection('tasks')
          .where('institutionId', isEqualTo: widget.institutionId);

      if (widget.termId != null) {
        query = query.where('termId', isEqualTo: widget.termId);
      }

      final snapshot = await query.get();
      final tasks = <ToDoTask>[];
      for (final doc in snapshot.docs) {
        try {
          tasks.add(ToDoTask.fromFirestore(doc));
        } catch (e) {
          debugPrint('Görev parse hatası: $e');
        }
      }

      if (mounted) {
        setState(() {
          _tasks = tasks;
          _stats = _TaskStats.compute(tasks);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('İstatistik yükleme hatası: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: const Color(0xFF0F172A),
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeader(),
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF818CF8),
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white38,
              labelStyle: GoogleFonts.inter(
                  fontWeight: FontWeight.bold, fontSize: 13),
              unselectedLabelStyle:
                  GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13),
              tabs: const [
                Tab(text: 'Genel'),
                Tab(text: 'Kişiler'),
                Tab(text: 'Eksikler'),
                Tab(text: 'Hız'),
              ],
            ),
          ),
        ],
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF818CF8)))
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildGeneralTab(),
                  _buildPersonTab(),
                  _buildMissingTab(),
                  _buildSpeedTab(),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader() {
    final totalTasks = _tasks.length;
    final completedCount = _stats?.totalCompleted ?? 0;
    final rate = totalTasks > 0 ? completedCount / totalTasks : 0.0;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              Text(
                'Görev İstatistikleri',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$totalTasks görev · %${(rate * 100).toStringAsFixed(0)} tamamlandı',
                style: GoogleFonts.inter(
                  color: Colors.white54,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: rate,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF818CF8)),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────────── GENEL TAB ─────────────────────────────
  Widget _buildGeneralTab() {
    if (_stats == null || _tasks.isEmpty) {
      return _buildEmpty('Bu dönemde henüz görev bulunmuyor.');
    }
    final s = _stats!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Özet Kartlar
        Row(
          children: [
            _buildStatCard('Toplam', '${_tasks.length}',
                Icons.assignment_outlined, const Color(0xFF818CF8)),
            const SizedBox(width: 12),
            _buildStatCard('Tamamlanan', '${s.totalCompleted}',
                Icons.check_circle_outline, const Color(0xFF10B981)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildStatCard('Bekleyen', '${s.totalPending}',
                Icons.pending_outlined, const Color(0xFFF59E0B)),
            const SizedBox(width: 12),
            _buildStatCard('Geciken', '${s.totalOverdue}',
                Icons.warning_amber_outlined, const Color(0xFFEF4444)),
          ],
        ),
        const SizedBox(height: 24),

        // Genel Tamamlama Oranı
        _buildSection('📊 Genel Durum', [
          _buildProgressRow(
              'Tamamlama Oranı',
              s.totalCompleted,
              _tasks.length,
              const Color(0xFF10B981)),
          _buildProgressRow(
              'Zamanında Tamamlanan',
              s.completedOnTime,
              s.totalCompleted,
              const Color(0xFF818CF8)),
          _buildProgressRow(
              'Geciken',
              s.totalOverdue,
              _tasks.length,
              const Color(0xFFEF4444)),
        ]),
        const SizedBox(height: 16),

        // En çok görev veren
        if (s.topAssigner != null)
          _buildHighlightCard(
            icon: Icons.emoji_events_outlined,
            color: const Color(0xFFF59E0B),
            title: 'En Çok Görev Veren',
            value: s.topAssigner!.name,
            subtitle: '${s.topAssigner!.tasksCreated} görev oluşturdu',
          ),
        const SizedBox(height: 12),

        // En performanslı
        if (s.topPerformer != null)
          _buildHighlightCard(
            icon: Icons.star_outline_rounded,
            color: const Color(0xFF10B981),
            title: 'En Yüksek Tamamlama',
            value: s.topPerformer!.name,
            subtitle:
                '${s.topPerformer!.completed}/${s.topPerformer!.assigned} görev · %${s.topPerformer!.rate.toStringAsFixed(0)}',
          ),
        const SizedBox(height: 12),

        // En az performanslı
        if (s.lowestPerformer != null && s.lowestPerformer!.assigned > 0)
          _buildHighlightCard(
            icon: Icons.trending_down_rounded,
            color: const Color(0xFFEF4444),
            title: 'En Düşük Tamamlama',
            value: s.lowestPerformer!.name,
            subtitle:
                '${s.lowestPerformer!.completed}/${s.lowestPerformer!.assigned} görev · %${s.lowestPerformer!.rate.toStringAsFixed(0)}',
          ),
      ],
    );
  }

  // ───────────────────────────── KİŞİLER TAB ─────────────────────────────
  Widget _buildPersonTab() {
    if (_stats == null || _stats!.personStats.isEmpty) {
      return _buildEmpty('Henüz kimseye görev atanmamış.');
    }

    final sorted = List<_PersonStat>.from(_stats!.personStats)
      ..sort((a, b) => b.rate.compareTo(a.rate));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sorted.length,
      itemBuilder: (ctx, i) {
        final p = sorted[i];
        final rank = i + 1;
        Color rankColor = const Color(0xFF64748B);
        if (rank == 1) rankColor = const Color(0xFFF59E0B);
        if (rank == 2) rankColor = const Color(0xFF94A3B8);
        if (rank == 3) rankColor = const Color(0xFFCD7F32);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Sıra numarası
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: rankColor.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '#$rank',
                          style: GoogleFonts.inter(
                            color: rankColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Avatar
                    CircleAvatar(
                      backgroundColor: const Color(0xFF818CF8).withOpacity(0.2),
                      radius: 20,
                      child: Text(
                        p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF818CF8),
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
                            p.name,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            '${p.completed} tamamlandı / ${p.assigned} atandı',
                            style: GoogleFonts.inter(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Oran badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _rateColor(p.rate).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '%${p.rate.toStringAsFixed(0)}',
                        style: GoogleFonts.inter(
                          color: _rateColor(p.rate),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: p.assigned > 0 ? p.completed / p.assigned : 0,
                    backgroundColor: Colors.white10,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(_rateColor(p.rate)),
                    minHeight: 5,
                  ),
                ),
                const SizedBox(height: 8),
                // Alt istatistikler
                Row(
                  children: [
                    _buildMiniStat('⏳ Bekleyen', '${p.pending}',
                        const Color(0xFFF59E0B)),
                    const SizedBox(width: 12),
                    _buildMiniStat('🔴 Geciken', '${p.overdue}',
                        const Color(0xFFEF4444)),
                    const SizedBox(width: 12),
                    if (p.tasksCreated > 0)
                      _buildMiniStat('📤 Verilen', '${p.tasksCreated}',
                          const Color(0xFF818CF8)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ───────────────────────────── EKSİKLER TAB ─────────────────────────────
  Widget _buildMissingTab() {
    // Geciken + tamamlanmamış görevleri olan kişiler
    final overduePeopleRaw = _stats?.personStats
            .where((p) => p.overdue > 0)
            .toList() ??
        [];
    overduePeopleRaw.sort((a, b) => b.overdue.compareTo(a.overdue));
    final overduePeople = overduePeopleRaw;

    // Hiç tamamlanmamış kişiler
    final neverDone = _stats?.personStats
            .where((p) => p.assigned > 0 && p.completed == 0)
            .toList() ??
        [];

    // En geride kalanlar (<%50)
    final laggardsRaw = _stats?.personStats
            .where((p) => p.assigned > 0 && p.rate < 50 && p.completed > 0)
            .toList() ??
        [];
    laggardsRaw.sort((a, b) => a.rate.compareTo(b.rate));
    final laggards = laggardsRaw;

    if (overduePeople.isEmpty && neverDone.isEmpty && laggards.isEmpty) {
      return _buildEmpty('🎉 Harika! Geciken veya eksik görev yok.');
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (overduePeople.isNotEmpty) ...[
          _buildSection(
            '🔴 Geciken Görevleri Olanlar',
            overduePeople
                .map((p) => _buildPersonWarningRow(
                    p.name, p.overdue, 'geciken görev',
                    const Color(0xFFEF4444)))
                .toList(),
          ),
          const SizedBox(height: 16),
        ],
        if (neverDone.isNotEmpty) ...[
          _buildSection(
            '⚫ Hiç Görev Tamamlamamış',
            neverDone
                .map((p) => _buildPersonWarningRow(
                    p.name, p.assigned, 'atanmış görev (0 tamamlandı)',
                    const Color(0xFF94A3B8)))
                .toList(),
          ),
          const SizedBox(height: 16),
        ],
        if (laggards.isNotEmpty) ...[
          _buildSection(
            '🟡 Düşük Tamamlama Oranı (%50 altı)',
            laggards
                .map((p) => _buildPersonWarningRow(
                    p.name,
                    p.pending,
                    'eksik görev · %${p.rate.toStringAsFixed(0)} tamamlandı',
                    const Color(0xFFF59E0B)))
                .toList(),
          ),
        ],
      ],
    );
  }

  // ─────────────────────────── YARDIMCI WİDGET'LAR ───────────────────────────

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.inter(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlightCard({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.inter(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
                Text(value,
                    style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                Text(subtitle,
                    style: GoogleFonts.inter(
                        color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: children
                .asMap()
                .entries
                .map((e) => Column(
                      children: [
                        e.value,
                        if (e.key < children.length - 1)
                          const Divider(
                              height: 1, color: Color(0xFF334155)),
                      ],
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressRow(
      String label, int value, int total, Color color) {
    final rate = total > 0 ? value / total : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: GoogleFonts.inter(
                        color: Colors.white70, fontSize: 13)),
              ),
              Text(
                '$value / $total',
                style: GoogleFonts.inter(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: rate,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonWarningRow(
      String name, int count, String suffix, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.15),
            radius: 18,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: GoogleFonts.inter(
                  color: color, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name,
                style: GoogleFonts.inter(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count $suffix',
              style: GoogleFonts.inter(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: GoogleFonts.inter(color: Colors.white38, fontSize: 11)),
        const SizedBox(width: 4),
        Text(value,
            style: GoogleFonts.inter(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 11)),
      ],
    );
  }

  Widget _buildEmpty(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.bar_chart_rounded,
              size: 56, color: Color(0xFF334155)),
          const SizedBox(height: 16),
          Text(message,
              style: GoogleFonts.inter(
                  color: Colors.white54, fontSize: 15)),
        ],
      ),
    );
  }

  Color _rateColor(double rate) {
    if (rate >= 80) return const Color(0xFF10B981);
    if (rate >= 50) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  // ────────────────────────────── HIZ TAB ──────────────────────────────
  Widget _buildSpeedTab() {
    final speedList = _stats?.speedStats ?? [];
    if (speedList.isEmpty) {
      return _buildEmpty(
          '⏱ Hız verisi henüz yok.\nGörevler tamamlandıkça burada görünür.');
    }

    final fastest = speedList.first;
    final slowest = speedList.last;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHighlightCard(
          icon: Icons.flash_on_rounded,
          color: const Color(0xFF10B981),
          title: '⚡ En Hızlı Tamamlayan',
          value: fastest.name,
          subtitle:
              'Ort. ${_formatDuration(fastest.avgHours)} (${fastest.count} görev)',
        ),
        const SizedBox(height: 12),
        if (speedList.length > 1)
          _buildHighlightCard(
            icon: Icons.hourglass_bottom_rounded,
            color: const Color(0xFFF59E0B),
            title: '🐢 En Yavaş Tamamlayan',
            value: slowest.name,
            subtitle:
                'Ort. ${_formatDuration(slowest.avgHours)} (${slowest.count} görev)',
          ),
        const SizedBox(height: 24),
        _buildSection(
          '⏱ Kişi Bazında Ort. Tamamlama Süresi',
          speedList.map((s) {
            final color = s.avgHours < 24
                ? const Color(0xFF10B981)
                : s.avgHours < 72
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFFEF4444);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withOpacity(0.15),
                    radius: 18,
                    child: Text(
                      s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
                      style: GoogleFonts.inter(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name,
                            style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                        Text('${s.count} görev tamamladı',
                            style: GoogleFonts.inter(
                                color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _formatDuration(s.avgHours),
                      style: GoogleFonts.inter(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  String _formatDuration(double hours) {
    if (hours < 1) return '<1 saat';
    if (hours < 24) return '${hours.toStringAsFixed(0)} saat';
    final days = (hours / 24).toStringAsFixed(1);
    return '$days gün';
  }
}

// ─────────────────────────── VERİ MODELLERİ ───────────────────────────

class _PersonStat {
  final String uid;
  final String name;
  int assigned = 0;
  int completed = 0;
  int overdue = 0;
  int tasksCreated = 0;

  _PersonStat(this.uid, this.name);

  int get pending => assigned - completed;
  double get rate => assigned > 0 ? (completed / assigned) * 100 : 0;
}

class _TaskStats {
  final List<_PersonStat> personStats;
  final List<_SpeedStat> speedStats;
  final int totalCompleted;
  final int totalPending;
  final int totalOverdue;
  final int completedOnTime;
  final _PersonStat? topAssigner;
  final _PersonStat? topPerformer;
  final _PersonStat? lowestPerformer;

  _TaskStats({
    required this.personStats,
    required this.speedStats,
    required this.totalCompleted,
    required this.totalPending,
    required this.totalOverdue,
    required this.completedOnTime,
    this.topAssigner,
    this.topPerformer,
    this.lowestPerformer,
  });

  factory _TaskStats.compute(List<ToDoTask> tasks) {
    final Map<String, _PersonStat> personMap = {};
    final now = DateTime.now();

    int totalCompleted = 0;
    int totalPending = 0;
    int totalOverdue = 0;
    int completedOnTime = 0;

    for (final task in tasks) {
      final isFullyCompleted = task.completedBy.length == task.assigneeIds.length
          && task.assigneeIds.isNotEmpty;
      final isOverdue = task.deadline != null
          && task.deadline!.isBefore(now)
          && !isFullyCompleted;

      if (isFullyCompleted) totalCompleted++;
      else totalPending++;
      if (isOverdue) totalOverdue++;

      // Zamanında tamamlanan: tamamlandı VE deadline geçmemiş
      if (isFullyCompleted && task.deadline != null) {
        // Biz deadline'ı biliyoruz ama tamamlanma zamanını bilmiyoruz
        // Bu yüzden "deadline geçmemiş" görevleri zamanında saydık
        completedOnTime++;
      }

      // Oluşturanı say
      if (task.creatorId.isNotEmpty && task.creatorName.isNotEmpty) {
        personMap.putIfAbsent(
            task.creatorId, () => _PersonStat(task.creatorId, task.creatorName));
        personMap[task.creatorId]!.tasksCreated++;
      }

      // Atananları say
      for (int i = 0; i < task.assigneeIds.length; i++) {
        final uid = task.assigneeIds[i];
        final name = task.assigneeNames[uid] ?? 'İsimsiz';

        personMap.putIfAbsent(uid, () => _PersonStat(uid, name));
        final p = personMap[uid]!;
        p.assigned++;

        final isPersonCompleted = task.completedBy.contains(uid);
        if (isPersonCompleted) p.completed++;

        final isPersonOverdue = task.deadline != null
            && task.deadline!.isBefore(now)
            && !isPersonCompleted;
        if (isPersonOverdue) p.overdue++;
      }
    }

    final people = personMap.values.toList();

    // En çok görev veren
    _PersonStat? topAssigner;
    for (final p in people) {
      if (topAssigner == null || p.tasksCreated > topAssigner.tasksCreated) {
        topAssigner = p;
      }
    }
    if (topAssigner?.tasksCreated == 0) topAssigner = null;

    // En yüksek tamamlama
    final assignees = people.where((p) => p.assigned > 0).toList();
    _PersonStat? topPerformer;
    _PersonStat? lowestPerformer;
    for (final p in assignees) {
      if (topPerformer == null || p.rate > topPerformer.rate) {
        topPerformer = p;
      }
      if (lowestPerformer == null || p.rate < lowestPerformer.rate) {
        lowestPerformer = p;
      }
    }

    // ───── Hız istatistiği: kişi başına ortalama tamamlama süresi ─────
    final Map<String, List<double>> speedMap = {}; // uid → saat listesi
    for (final task in tasks) {
      for (final uid in task.assigneeIds) {
        final completedTime = task.completedAt[uid];
        if (completedTime != null) {
          final hours =
              completedTime.difference(task.createdAt).inMinutes / 60.0;
          if (hours >= 0) {
            speedMap.putIfAbsent(uid, () => []);
            speedMap[uid]!.add(hours);
          }
        }
      }
    }

    final List<_SpeedStat> speedStats = speedMap.entries.map((e) {
      final uid = e.key;
      final name = personMap[uid]?.name ?? 'Bilinmiyor';
      final avg = e.value.reduce((a, b) => a + b) / e.value.length;
      return _SpeedStat(
          uid: uid, name: name, avgHours: avg, count: e.value.length);
    }).toList()
      ..sort((a, b) => a.avgHours.compareTo(b.avgHours));

    return _TaskStats(
      personStats: people,
      speedStats: speedStats,
      totalCompleted: totalCompleted,
      totalPending: totalPending,
      totalOverdue: totalOverdue,
      completedOnTime: completedOnTime,
      topAssigner: topAssigner,
      topPerformer: topPerformer,
      lowestPerformer: lowestPerformer,
    );
  }
}

// Hız istatistiği — kişi başına ortalama tamamlama süresi
class _SpeedStat {
  final String uid;
  final String name;
  final double avgHours;
  final int count;

  _SpeedStat(
      {required this.uid,
      required this.name,
      required this.avgHours,
      required this.count});
}
