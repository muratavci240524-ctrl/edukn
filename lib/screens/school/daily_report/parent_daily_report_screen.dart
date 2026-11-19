import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/school/daily_report_models.dart';
import '../../../services/daily_report_service.dart';
import '../../../widgets/edukn_app_bar.dart';

/// Veli Ana Sayfasında (`ParentDashboardTab`) Canlı Özet Gösteren Banner Kartı
class ParentDailyReportLiveBanner extends StatefulWidget {
  final String institutionId;
  final String studentId;
  final String studentName;
  final String className;

  const ParentDailyReportLiveBanner({
    super.key,
    required this.institutionId,
    required this.studentId,
    this.studentName = '',
    this.className = '',
  });

  @override
  State<ParentDailyReportLiveBanner> createState() =>
      _ParentDailyReportLiveBannerState();
}

class _ParentDailyReportLiveBannerState
    extends State<ParentDailyReportLiveBanner> {
  final DailyReportService _service = DailyReportService();
  String _schoolDocId = '';
  String _schoolTypeId = '';
  String _resolvedName = '';
  String _resolvedClass = '';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant ParentDailyReportLiveBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studentId != widget.studentId ||
        oldWidget.institutionId != widget.institutionId) {
      _init();
    }
  }

  Future<void> _init() async {
    if (widget.studentId.trim().isEmpty ||
        widget.institutionId.trim().isEmpty) {
      if (mounted) setState(() => _ready = false);
      return;
    }
    try {
      final sDocId = await _service.resolveSchoolDocId(widget.institutionId);
      String stType = '';
      String sName = widget.studentName;
      String cName = widget.className;

      final stDoc = await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.studentId)
          .get();
      if (stDoc.exists) {
        final d = stDoc.data()!;
        stType = (d['schoolTypeId'] ?? '').toString();
        if (sName.isEmpty) {
          sName = (d['fullName'] ?? '${d['name'] ?? ''} ${d['surname'] ?? ''}')
              .toString()
              .trim();
        }
        if (cName.isEmpty) {
          cName = (d['className'] ?? '').toString().trim();
        }
      }

      if (mounted) {
        setState(() {
          _schoolDocId = sDocId;
          _schoolTypeId = stType;
          _resolvedName = sName;
          _resolvedClass = cName;
          _ready = sDocId.isNotEmpty;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || widget.studentId.isEmpty) return const SizedBox.shrink();
    final todayKey = DailyReportService.formatDateKey(DateTime.now());

    return StreamBuilder<DailyReportConfigModel>(
      stream: _service.watchConfig(_schoolDocId),
      builder: (context, cfgSnap) {
        final cfg = cfgSnap.data ?? const DailyReportConfigModel();
        if (!cfg.isEnabledForSchoolType(_schoolTypeId)) {
          return const SizedBox.shrink();
        }

        return StreamBuilder<DailyReportModel?>(
          stream: _service.watchStudentReportForDate(
            schoolDocId: _schoolDocId,
            studentId: widget.studentId,
            dateKey: todayKey,
          ),
          builder: (context, repSnap) {
            final rep = repSnap.data;
            if (rep == null || !rep.hasAnyContent) {
              return const SizedBox.shrink();
            }

            final moodMeta = DailyReportCatalog.moodMeta(rep.mood);
            final bfMeta = DailyReportCatalog.mealMeta(rep.breakfast.status);
            final lnMeta = DailyReportCatalog.mealMeta(rep.lunch.status);
            final slMeta = DailyReportCatalog.sleepMeta(rep.sleep.status);

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ParentDailyReportScreen(
                            institutionId: widget.institutionId,
                            studentId: widget.studentId,
                            studentName: _resolvedName,
                            className: _resolvedClass,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4F46E5), Color(0xFF0D9488)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF4F46E5).withValues(alpha: 0.22),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.20),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  moodMeta?.emoji ?? '🌟',
                                  style: const TextStyle(fontSize: 22),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFDCFCE7),
                                            borderRadius:
                                                BorderRadius.circular(99),
                                          ),
                                          child: const Text(
                                            '● CANLI GÜNLÜK KARNE',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFF166534),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Son güncelleme ${DateFormat('HH:mm').format(rep.updatedAt)}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFFE0E7FF),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_resolvedName.isNotEmpty ? _resolvedName : rep.studentName} • Bugün Neler Yaptı?',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Karneyi Gör',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF312E81),
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 12,
                                      color: Color(0xFF312E81),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              if (bfMeta != null)
                                _miniPill('🍳 Kahvaltı: ${bfMeta.shortLabel}'),
                              if (lnMeta != null)
                                _miniPill('🍲 Öğle: ${lnMeta.shortLabel}'),
                              if (slMeta != null)
                                _miniPill('😴 Uyku: ${slMeta.shortLabel}'),
                              if (rep.activities.isNotEmpty)
                                _miniPill(
                                  '🎨 ${rep.activities.length} Etkinlik / Ders',
                                ),
                              if (rep.neededItems.isNotEmpty)
                                _miniPill(
                                  '🎒 ${rep.neededItems.length} Hatırlatma',
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _miniPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Velinin Öğrenci Günlük Karnesini Anlık ve Geçmişe Dönük İzlediği Ekran
class ParentDailyReportScreen extends StatefulWidget {
  final String institutionId;
  final String studentId;
  final String studentName;
  final String className;
  final DateTime? initialDate;
  final bool isPreviewMode;

  const ParentDailyReportScreen({
    super.key,
    required this.institutionId,
    required this.studentId,
    this.studentName = '',
    this.className = '',
    this.initialDate,
    this.isPreviewMode = false,
  });

  @override
  State<ParentDailyReportScreen> createState() =>
      _ParentDailyReportScreenState();
}

class _ParentDailyReportScreenState extends State<ParentDailyReportScreen> {
  final DailyReportService _service = DailyReportService();
  final TextEditingController _feedbackCtrl = TextEditingController();

  bool _loading = true;
  String _schoolDocId = '';
  String _schoolTypeId = '';
  DailyReportConfigModel _config = const DailyReportConfigModel();
  late DateTime _selectedDate;
  final Set<String> _markedSeenKeys = {};
  bool _sendingFeedback = false;

  String get _dateKey => DailyReportService.formatDateKey(_selectedDate);

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _bootstrap();
  }

  @override
  void dispose() {
    _feedbackCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final sDocId = await _service.resolveSchoolDocId(widget.institutionId);
    final cfg = await _service.loadConfig(sDocId);
    String stType = '';
    if (widget.studentId.trim().isNotEmpty) {
      try {
        final stDoc = await FirebaseFirestore.instance
            .collection('students')
            .doc(widget.studentId)
            .get();
        if (stDoc.exists) {
          stType = (stDoc.data()?['schoolTypeId'] ?? '').toString().trim();
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _schoolDocId = sDocId;
        _schoolTypeId = stType;
        _config = cfg;
        _loading = false;
      });
    }
  }

  void _ensureMarkedSeen(DailyReportModel report) {
    if (widget.isPreviewMode) return;
    if (report.parentSeenAt != null) return;
    if (_markedSeenKeys.contains(report.dateKey)) return;
    _markedSeenKeys.add(report.dateKey);
    _service.markSeenByParent(
      schoolDocId: _schoolDocId,
      dateKey: report.dateKey,
      studentId: widget.studentId,
    );
  }

  Future<void> _sendReaction(String emoji, DailyReportModel current) async {
    if (widget.isPreviewMode) return;
    await _service.submitParentFeedback(
      schoolDocId: _schoolDocId,
      dateKey: current.dateKey,
      studentId: widget.studentId,
      reaction: emoji,
    );
  }

  Future<void> _sendNote(DailyReportModel current) async {
    if (widget.isPreviewMode || _feedbackCtrl.text.trim().isEmpty) return;
    setState(() => _sendingFeedback = true);
    try {
      await _service.submitParentFeedback(
        schoolDocId: _schoolDocId,
        dateKey: current.dateKey,
        studentId: widget.studentId,
        feedbackNote: _feedbackCtrl.text.trim(),
      );
      _feedbackCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notunuz öğretmene iletildi. Teşekkür ederiz!'),
            backgroundColor: Color(0xFF0D9488),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingFeedback = false);
    }
  }

  String _formatTrDate(String dateKey) {
    final parsed = DateTime.tryParse(dateKey);
    if (parsed == null) return dateKey;
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
    return '${parsed.day} ${months[parsed.month - 1]}';
  }

  String _fullDateTitle(DateTime d) {
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
    const days = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}, ${days[d.weekday - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        title: widget.isPreviewMode
            ? 'Veli Önizleme • Günlük Karne'
            : 'Günlük Karne (Canlı Takip)',
        institutionId: widget.institutionId,
        subtitle: widget.studentName.isNotEmpty
            ? '${widget.studentName}${widget.className.isNotEmpty ? ' • ${widget.className}' : ''}'
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<DailyReportModel>>(
              stream: _service.watchStudentReportHistory(
                schoolDocId: _schoolDocId,
                studentId: widget.studentId,
              ),
              builder: (context, histSnap) {
                final history = histSnap.data ?? const [];
                DailyReportModel? activeReport;
                for (final r in history) {
                  if (r.dateKey == _dateKey) {
                    activeReport = r;
                    break;
                  }
                }
                if (activeReport != null) {
                  _ensureMarkedSeen(activeReport);
                }

                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                      children: [
                        _buildDateSelectorAndHistoryBar(history),
                        const SizedBox(height: 16),
                        if (activeReport == null)
                          _buildEmptyDayCard(history)
                        else
                          ..._buildReportContentCards(activeReport),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildDateSelectorAndHistoryBar(List<DailyReportModel> history) {
    final now = DateTime.now();
    final isToday = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => setState(
                  () => _selectedDate =
                      _selectedDate.subtract(const Duration(days: 1)),
                ),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(now.year - 2, 1, 1),
                      lastDate: DateTime(now.year, now.month, now.day),
                    );
                    if (picked != null && mounted) {
                      setState(() => _selectedDate = picked);
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.calendar_month_rounded,
                          size: 18,
                          color: Color(0xFF4F46E5),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _fullDateTitle(_selectedDate),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: isToday
                    ? null
                    : () => setState(
                          () => _selectedDate =
                              _selectedDate.add(const Duration(days: 1)),
                        ),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          if (history.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: history.take(14).map((item) {
                  final sel = item.dateKey == _dateKey;
                  final mood = DailyReportCatalog.moodMeta(item.mood);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () {
                        final dt = DateTime.tryParse(item.dateKey);
                        if (dt != null) setState(() => _selectedDate = dt);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: sel
                              ? const Color(0xFF4F46E5)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: sel
                                ? const Color(0xFF4F46E5)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Text(
                          '${mood?.emoji ?? "📋"} ${_formatTrDate(item.dateKey)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: sel ? Colors.white : const Color(0xFF334155),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyDayCard(List<DailyReportModel> history) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.wb_sunny_outlined,
              size: 34,
              color: Color(0xFF4F46E5),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Bu Tarih İçin Henüz Günlük Karne Girilmedi',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Öğretmenimiz gün içerisinde kahvaltı, uyku ve etkinlik bilgilerini girdikçe bu ekran otomatik ve canlı olarak güncellenir.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: Color(0xFF64748B),
              height: 1.4,
            ),
          ),
          if (history.isNotEmpty) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () {
                final latest = DateTime.tryParse(history.first.dateKey);
                if (latest != null) setState(() => _selectedDate = latest);
              },
              icon: const Icon(Icons.history_rounded, size: 18),
              label: Text(
                'Son Girilen Karneye Git (${_formatTrDate(history.first.dateKey)})',
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildReportContentCards(DailyReportModel rep) {
    final effCfg = _config.forSchoolType(
      _schoolTypeId.isNotEmpty ? _schoolTypeId : rep.schoolTypeId,
    );
    final moodMeta =
        effCfg.trackMood ? DailyReportCatalog.moodMeta(rep.mood) : null;
    final harmony = effCfg.trackMood
        ? DailyReportCatalog.socialHarmonyOptions
            .where((h) => h.key == rep.socialHarmony)
            .firstOrNull
        : null;

    return [
      // 1. Özet Kahraman Kartı
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF312E81), Color(0xFF4F46E5), Color(0xFF0D9488)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF312E81).withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    moodMeta?.emoji ?? '🌟',
                    style: const TextStyle(fontSize: 30),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.studentName.isNotEmpty
                            ? widget.studentName
                            : rep.studentName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${rep.className.isNotEmpty ? rep.className : widget.className} • Son güncelleme: ${DateFormat('HH:mm').format(rep.updatedAt)}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFFE0E7FF),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (moodMeta != null || harmony != null) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (moodMeta != null)
                    _heroTag('${moodMeta.emoji} Bugün ${moodMeta.label}'),
                  if (harmony != null) _heroTag('🤝 ${harmony.label}'),
                ],
              ),
            ],
            if (rep.contributors.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Bilgi Giren Öğretmen: ${rep.contributors.join(", ")}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFFCCFBF1),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),

      const SizedBox(height: 14),

      // Yarına Hatırlatma varsa öne çıkar
      if (rep.neededItems.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.notifications_active_rounded,
                    color: Color(0xFFD97706),
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Veliye Hatırlatma & İhtiyaç Listesi',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: rep.neededItems
                    .map(
                      (e) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFCD34D)),
                        ),
                        child: Text(
                          e,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
      ],

      // 2. Beslenme Kartı
      if ((effCfg.trackMeals &&
              (rep.breakfast.hasValue ||
                  rep.lunch.hasValue ||
                  rep.snack.hasValue)) ||
          (effCfg.trackWater && rep.waterIntake.isNotEmpty)) ...[
        _buildParentCard(
          title: 'Beslenme & Su Takibi',
          icon: Icons.restaurant_rounded,
          color: const Color(0xFFF59E0B),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (effCfg.trackMeals && rep.breakfast.hasValue)
                _buildParentMealRow(
                  'Sabah Kahvaltısı',
                  Icons.wb_twilight_rounded,
                  rep.breakfast,
                ),
              if (effCfg.trackMeals && rep.lunch.hasValue)
                _buildParentMealRow(
                  'Öğle Yemeği',
                  Icons.lunch_dining_rounded,
                  rep.lunch,
                ),
              if (effCfg.trackMeals && rep.snack.hasValue)
                _buildParentMealRow(
                  'İkindi Kahvaltısı / Ara Öğün',
                  Icons.bakery_dining_rounded,
                  rep.snack,
                ),
              if (effCfg.trackWater && rep.waterIntake.isNotEmpty) ...[
                const SizedBox(height: 6),
                Builder(
                  builder: (_) {
                    final w = DailyReportCatalog.waterOptions
                        .where((x) => x.key == rep.waterIntake)
                        .firstOrNull;
                    if (w == null) return const SizedBox.shrink();
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F9FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Text(w.emoji, style: const TextStyle(fontSize: 15)),
                          const SizedBox(width: 8),
                          Text(
                            'Su Tüketimi: ${w.label}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0369A1),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
      ],

      // 3. Uyku & Dinlenme Kartı
      if (effCfg.trackSleep && rep.sleep.hasValue) ...[
        _buildParentCard(
          title: 'Uyku & Dinlenme Saati',
          icon: Icons.bedtime_rounded,
          color: const Color(0xFF6366F1),
          child: Builder(
            builder: (_) {
              final sMeta = DailyReportCatalog.sleepMeta(rep.sleep.status);
              return Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (sMeta?.color ?? const Color(0xFF6366F1))
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      sMeta?.icon ?? Icons.bedtime_rounded,
                      color: sMeta?.color ?? const Color(0xFF6366F1),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${sMeta?.label ?? rep.sleep.status}${rep.sleep.durationOrRange.isNotEmpty ? " • ${rep.sleep.durationOrRange}" : ""}',
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        if (rep.sleep.note.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            rep.sleep.note,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 14),
      ],

      // 4. Günlük Etkinlik, Kitap, Gezi & Branş Ders Akışı
      if (effCfg.trackActivities && rep.activities.isNotEmpty) ...[
        _buildParentCard(
          title: 'Günün Etkinlik, Kitap, Gezi & Ders Akışı',
          icon: Icons.auto_awesome_rounded,
          color: const Color(0xFF8B5CF6),
          child: Column(
            children: rep.activities.map((act) {
              final meta = DailyReportCatalog.activityMeta(act.category);
              final part =
                  DailyReportCatalog.participationMeta(act.participation);
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: meta.color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            meta.emoji,
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                act.title,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              if (act.teacherName.isNotEmpty ||
                                  act.timeLabel.isNotEmpty)
                                Text(
                                  [
                                    if (act.timeLabel.isNotEmpty) act.timeLabel,
                                    if (act.teacherName.isNotEmpty)
                                      act.teacherName,
                                  ].join(' • '),
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: part.color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            part.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: part.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (act.description.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        act.description,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFF334155),
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (act.photoUrl.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          act.photoUrl,
                          width: double.infinity,
                          height: 190,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),
      ],

      // 5. Özbakım & Sağlık Notu
      if ((effCfg.trackSelfCare && rep.selfCareTags.isNotEmpty) ||
          (effCfg.trackHealthNote && rep.healthNote.isNotEmpty)) ...[
        _buildParentCard(
          title: 'Özbakım & Sağlık Gözlemi',
          icon: Icons.favorite_rounded,
          color: const Color(0xFF10B981),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (effCfg.trackSelfCare && rep.selfCareTags.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: rep.selfCareTags
                      .map(
                        (t) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFBBF7D0)),
                          ),
                          child: Text(
                            t,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF166534),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              if (effCfg.trackHealthNote && rep.healthNote.isNotEmpty) ...[
                if (effCfg.trackSelfCare && rep.selfCareTags.isNotEmpty)
                  const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.medical_services_rounded,
                        color: Color(0xFFDC2626),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          rep.healthNote,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF991B1B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
      ],

      // 6. Öğretmenimizin Gün Sonu Özel Notu
      if (rep.teacherNote.isNotEmpty) ...[
        _buildParentCard(
          title: 'Öğretmenimizin Notu',
          icon: Icons.mark_chat_read_rounded,
          color: const Color(0xFF4F46E5),
          child: Text(
            rep.teacherNote,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF1E293B),
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],

      // 7. Veli Tepki & Kısa Teşekkür Notu
      if (effCfg.allowParentFeedback && !widget.isPreviewMode)
        _buildParentCard(
          title: 'Öğretmenimize Geri Bildirim Bırakın',
          icon: Icons.volunteer_activism_rounded,
          color: const Color(0xFFEC4899),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  (emoji: '❤️', label: 'Teşekkürler'),
                  (emoji: '👏', label: 'Elinize Sağlık'),
                  (emoji: '😊', label: 'Çok Sevindik'),
                  (emoji: '👍', label: 'Bilgi Alındı'),
                ].map((r) {
                  final sel = rep.parentReaction == r.emoji;
                  return ChoiceChip(
                    label: Text('${r.emoji} ${r.label}'),
                    selected: sel,
                    onSelected: (_) => _sendReaction(r.emoji, rep),
                    selectedColor: const Color(0xFFFCE7F3),
                  );
                }).toList(),
              ),
              if (rep.parentFeedbackNote.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDF2F8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Gönderdiğiniz Not: "${rep.parentFeedbackNote}"',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF9D174D),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _feedbackCtrl,
                      decoration: InputDecoration(
                        hintText: 'Öğretmene kısa teşekkür veya bilgi notu...',
                        hintStyle: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF94A3B8),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _sendingFeedback ? null : () => _sendNote(rep),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Gönder'),
                  ),
                ],
              ),
            ],
          ),
        ),
    ];
  }

  Widget _heroTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildParentCard({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildParentMealRow(
    String mealTitle,
    IconData icon,
    MealEntryModel meal,
  ) {
    final meta = DailyReportCatalog.mealMeta(meal.status);
    final color = meta?.color ?? const Color(0xFF64748B);

    double progress = 0;
    if (meal.status == 'full') progress = 1.0;
    if (meal.status == 'half') progress = 0.55;
    if (meal.status == 'little') progress = 0.25;
    if (meal.status == 'none') progress = 0.06;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mealTitle,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  meta?.label ?? meal.status,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          if (meal.status != 'na') ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: const Color(0xFFE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
          if (meal.menuOrNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              meal.menuOrNote,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
            ),
          ],
        ],
      ),
    );
  }
}
