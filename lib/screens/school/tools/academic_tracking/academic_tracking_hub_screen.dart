import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../services/user_permission_service.dart';
import '../../../../widgets/edukn_app_bar.dart';
import 'academic_tracking_models.dart';
import 'academic_ui_widgets.dart';
import 'calculators_and_item_analysis_screens.dart';
import 'champions_league_screen.dart';
import 'coaching_and_homework_screens.dart';
import 'early_warning_radar_screens.dart';
import 'goal_simulator_tool_screen.dart';
import 'outcome_heatmap_tool_screen.dart';

class AcademicTrackingHubScreen extends StatelessWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final bool isTeacher;
  final String? teacherId;
  final List<String>? allowedClassIds;

  const AcademicTrackingHubScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.isTeacher = false,
    this.teacherId,
    this.allowedClassIds,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: EduknAppBar(
        title: 'Akademik Ölçme ve Başarı Takibi',
        subtitle: schoolTypeName,
      ),
      body: AcademicTrackingHubBody(
        institutionId: institutionId,
        schoolTypeId: schoolTypeId,
        schoolTypeName: schoolTypeName,
        isTeacher: isTeacher,
        teacherId: teacherId,
        allowedClassIds: allowedClassIds,
      ),
    );
  }
}

class AcademicTrackingHubBody extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final bool isTeacher;
  final String? teacherId;
  final List<String>? allowedClassIds;

  const AcademicTrackingHubBody({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.isTeacher = false,
    this.teacherId,
    this.allowedClassIds,
  });

  @override
  State<AcademicTrackingHubBody> createState() =>
      _AcademicTrackingHubBodyState();
}

class _AcademicTrackingHubBodyState extends State<AcademicTrackingHubBody> {
  AcademicDataset? _dataset;
  bool _loading = true;
  String _selectedGroup = 'all'; // 'all' | 'exam' | 'risk' | 'teacher'
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    setState(() => _loading = true);
    final data = await AcademicTrackingDataService.loadDataset(
      institutionId: widget.institutionId,
      schoolTypeId: widget.schoolTypeId,
      schoolTypeName: widget.schoolTypeName,
      isTeacher: widget.isTeacher,
      allowedClassIds: widget.allowedClassIds,
      forceRefresh: forceRefresh,
    );
    if (mounted) {
      setState(() {
        _dataset = data;
        _loading = false;
      });
    }
  }

  bool _hasPerm(String permKey) {
    if (!widget.isTeacher) return true;
    return UserPermissionService.hasTeacherModuleAccess(
      'araclar',
      subModuleKey: permKey,
    );
  }

  List<_AcademicToolMeta> _buildTools(AcademicDataset ds) {
    final showChampions =
        ds.schoolStage == 'ortaokul' ||
        ds.schoolStage == 'lise' ||
        ds.schoolStage == 'genel';
    final champTitle = ds.schoolStage == 'ortaokul'
        ? 'LGS ŞAMPİYONLARI — Derece & Yüzdelik İhtimal Analizi'
        : (ds.schoolStage == 'lise'
              ? 'YKS ŞAMPİYONLARI — Derece & Yüzdelik İhtimal Analizi'
              : 'LGS & YKS ŞAMPİYONLARI — Derece İhtimal Stüdyosu');
    final champSubtitle = ds.schoolStage == 'lise'
        ? 'Aktif dönem deneme sınavı verilerine göre Türkiye derecesi yapacak şampiyon adaylarını ve tüm öğrencilerin yaklaşık yüzdelik/sıralama olasılıklarını listeler.'
        : 'Aktif dönem deneme sınavı verilerine göre LGS şampiyon adaylarını ve tüm öğrencilerin yaklaşık Türkiye yüzdelik dilim olasılıklarını listeler.';
    final champBadge = ds.schoolStage == 'lise'
        ? 'YKS Derece Motoru'
        : (ds.schoolStage == 'ortaokul'
              ? 'LGS Şampiyon Motoru'
              : 'LGS / YKS Derece');

    return [
      if (showChampions)
        _AcademicToolMeta(
          permKey: 'akademik_sampiyonlar',
          group: 'exam',
          extraGroups: const ['teacher'],
          title: champTitle,
          subtitle: champSubtitle,
          badge: champBadge,
          tags: const [
            'Şampiyon Adayları',
            'Yüzdelik İhtimal (%)',
            'Derece Raporu PDF',
          ],
          icon: Icons.emoji_events_rounded,
          gradient: const [Color(0xFFB45309), Color(0xFFD97706)],
          onOpen: (ctx) => Navigator.push(
            ctx,
            MaterialPageRoute(
              builder: (_) => ChampionsLeagueScreen(dataset: ds),
            ),
          ),
        ),
      _AcademicToolMeta(
        permKey: 'akademik_hedef_simulator',
        group: 'exam',
        title: 'LGS & YKS Hedef, Puan ve Tercih Simülatörü',
        subtitle:
            'MEB 2026/2025 kalibre yüzdelik dilim motoru, TYT/AYT/OBP sıralama tahmini, öğrenciden otomatik net çekme ve hedef net reçetesi.',
        badge: 'LGS + YKS Kalibre',
        tags: const ['Yüzdelik Dilim', 'OBP & Alan', 'Hedef Reçete PDF'],
        icon: Icons.rocket_launch_rounded,
        gradient: const [Color(0xFF059669), Color(0xFF0D9488)],
        onOpen: (ctx) => Navigator.push(
          ctx,
          MaterialPageRoute(
            builder: (_) => GoalSimulatorToolScreen(dataset: ds),
          ),
        ),
      ),
      _AcademicToolMeta(
        permKey: 'akademik_isi_haritasi',
        group: 'exam',
        title: 'Kazanım & Branş Başarı Isı Haritası (Heat Map)',
        subtitle:
            'Deneme ve yazılı sınavlarını Şube × Branş ve Soru/Kazanım matrisinde renk kodlu inceleyin; telafi etüt konularını tek tıkla çıkarın.',
        badge: ds.trialExams.isNotEmpty
            ? '${ds.trialExams.length} Deneme Hazır'
            : 'Canlı Matris Aktif',
        tags: const ['Şube × Branş', 'Soru & Kazanım', 'Telafi Etüt Önerisi'],
        icon: Icons.grid_on_rounded,
        gradient: const [Color(0xFFD97706), Color(0xFFEA580C)],
        onOpen: (ctx) => Navigator.push(
          ctx,
          MaterialPageRoute(
            builder: (_) => OutcomeHeatmapToolScreen(dataset: ds),
          ),
        ),
      ),
      _AcademicToolMeta(
        permKey: 'akademik_risk_erken_uyari',
        group: 'risk',
        title: '360° Akademik Risk & Erken Uyarı Sistemi (EWS)',
        subtitle:
            'Deneme net düşüşü, 50 altı yazılı ortalaması, yapılmayan ödevler ve özürsüz devamsızlığı birleştirip 0–100 risk skoru üretir.',
        badge: ds.criticalRiskCount > 0
            ? '${ds.criticalRiskCount} Kritik Uyarı'
            : '${ds.students.length} Öğrenci Taranıyor',
        tags: const ['0-100 Risk Skoru', 'Rehberlik Radarı', 'Müdahale PDF'],
        icon: Icons.warning_amber_rounded,
        gradient: const [Color(0xFFDC2626), Color(0xFFB91C1C)],
        onOpen: (ctx) => Navigator.push(
          ctx,
          MaterialPageRoute(
            builder: (_) => EarlyWarningSystemScreen(dataset: ds),
          ),
        ),
      ),
      _AcademicToolMeta(
        permKey: 'akademik_devamsizlik_radar',
        group: 'risk',
        title: 'Devamsızlık & Geç Kalma Radar Paneli',
        subtitle:
            'MEB 10/30 ve 20 gün devamsızlık sınırına yaklaşan öğrencileri ve sabah 1. ders geç kalma alışkanlığı olanları otomatik filtreler.',
        badge: ds.criticalAttendanceCount > 0
            ? '${ds.criticalAttendanceCount} Sınırda'
            : 'MEB 10/30 Eşikleri',
        tags: const ['Özürsüz Sınır', '1. Ders Geç Kalma', 'Resmi Uyarı PDF'],
        icon: Icons.radar_rounded,
        gradient: const [Color(0xFFE11D48), Color(0xFFBE123C)],
        onOpen: (ctx) => Navigator.push(
          ctx,
          MaterialPageRoute(
            builder: (_) => AttendanceRadarToolScreen(dataset: ds),
          ),
        ),
      ),
      _AcademicToolMeta(
        permKey: 'akademik_deneme_kocu',
        group: 'exam',
        title: 'Bireysel Deneme Gelişim & Net Trend Koçu',
        subtitle:
            'Öğrencinin tüm denemelerdeki boylamsal net/puan gelişim grafiğini, kurum sıralamasını ve boş/yanlış kodlama stratejisini analiz eder.',
        badge: '${ds.trialHistoryByStudent.length} Öğrenci Trendi',
        tags: const ['Net Grafiği', 'Strateji Teşhisi', 'Koçluk Karnesi PDF'],
        icon: Icons.auto_graph_rounded,
        gradient: const [Color(0xFF4F46E5), Color(0xFF6366F1)],
        onOpen: (ctx) => Navigator.push(
          ctx,
          MaterialPageRoute(
            builder: (_) => StudentTrialCoachScreen(dataset: ds),
          ),
        ),
      ),
      _AcademicToolMeta(
        permKey: 'akademik_odev_etut_analiz',
        group: 'risk',
        title: 'Ödev Disiplini & Etüt Verimlilik Analizi',
        subtitle:
            'Sınıfların ödev tamamlama yüzdelerini, kronik ödev yapmayan öğrencileri ve branş bazlı etüt katılım verimliliğini raporlar.',
        badge:
            '%${ds.overallHomeworkCompletionRate.toStringAsFixed(0)} Tamamlama',
        tags: const ['Sınıf Ödev Ligi', 'Kronik Eksikler', 'Etüt Katılımı'],
        icon: Icons.menu_book_rounded,
        gradient: const [Color(0xFF0D9488), Color(0xFF0F766E)],
        onOpen: (ctx) => Navigator.push(
          ctx,
          MaterialPageRoute(
            builder: (_) => HomeworkAndEtutAnalyticsScreen(dataset: ds),
          ),
        ),
      ),
      _AcademicToolMeta(
        permKey: 'akademik_not_donusturucu',
        group: 'teacher',
        title: 'Hızlı Test Notu, Çan Eğrisi & Rubrik Dönüştürücü',
        subtitle:
            '3\'ü 1 arada öğretmen stüdyosu: Doğru/Yanlış puan anahtarı çizelgesi, Z/T-Skor Çan Eğrisi hesaplayıcı ve MEB Açık Uçlu Yazılı Rubriği.',
        badge: '3 Araç Tek Ekranda',
        tags: const [
          'Test Anahtarı',
          'Z/T-Skor Çan Eğrisi',
          'Açık Uçlu Rubrik',
        ],
        icon: Icons.speed_rounded,
        gradient: const [Color(0xFF0284C7), Color(0xFF0369A1)],
        onOpen: (ctx) => Navigator.push(
          ctx,
          MaterialPageRoute(
            builder: (_) => GradeConverterSuiteScreen(dataset: ds),
          ),
        ),
      ),
      _AcademicToolMeta(
        permKey: 'akademik_madde_analizi',
        group: 'teacher',
        title: 'Madde Analizi (Güçlük / Ayırt Edicilik) ve KR-20',
        subtitle:
            'Optik sınav cevaplarından her sorunun güçlük indeksi (pj), %27 alt/üst grup ayırt ediciliği (rjx), çeldirici dağılımı ve KR-20 güvenirliğini ölçer.',
        badge: 'Klasik Test Kuramı',
        tags: const ['Güçlük (pj)', 'Ayırt Edicilik (rjx)', 'KR-20 Güvenirlik'],
        icon: Icons.biotech_rounded,
        gradient: const [Color(0xFF7C3AED), Color(0xFF6D28D9)],
        onOpen: (ctx) => Navigator.push(
          ctx,
          MaterialPageRoute(
            builder: (_) => ItemAnalysisToolScreen(dataset: ds),
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 760;

    if (_loading || _dataset == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final ds = _dataset!;
    final allPermittedTools = _buildTools(
      ds,
    ).where((t) => _hasPerm(t.permKey)).toList();
    final q = AcademicTrackingDataService.normTr(_search);
    final visibleTools = allPermittedTools.where((t) {
      if (_selectedGroup != 'all' &&
          t.group != _selectedGroup &&
          !t.extraGroups.contains(_selectedGroup)) {
        return false;
      }
      if (q.isNotEmpty) {
        final hay = AcademicTrackingDataService.normTr(
          '${t.title} ${t.subtitle} ${t.tags.join(" ")}',
        );
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: () => _loadData(forceRefresh: true),
      child: ListView(
        padding: EdgeInsets.all(isMobile ? 14 : 22),
        children: [
          _buildExecutiveBanner(ds, isMobile, allPermittedTools.length),
          const SizedBox(height: 16),
          _buildFilterStrip(isMobile, allPermittedTools.length),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final cols = maxW >= 1520
                  ? 4
                  : (maxW >= 1080 ? 3 : (maxW >= 640 ? 2 : 1));
              final gap = isMobile ? 12.0 : 16.0;
              final cardW = (maxW - gap * (cols - 1)) / cols;
              final mainExtent = cardW < 330 ? 248.0 : 242.0;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: visibleTools.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: gap,
                  mainAxisSpacing: gap,
                  mainAxisExtent: mainExtent,
                ),
                itemBuilder: (ctx, idx) =>
                    _buildToolCard(ctx, visibleTools[idx]),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildExecutiveBanner(
    AcademicDataset ds,
    bool isMobile,
    int toolCount,
  ) {
    final termBadge = ds.activeTermName.isNotEmpty
        ? ' • Aktif Dönem: ${ds.activeTermName}'
        : '';
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF065F46)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.2),
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
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.insights_rounded,
                  color: Color(0xFF34D399),
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Akademik Ölçme, Risk Zekâsı ve Başarı Takip Merkezi',
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 16.5 : 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${ds.schoolName}$termBadge • Seçili dönem verileriyle entegre $toolCount profesyonel araç',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Canlı Veriyi Yenile',
                onPressed: () => _loadData(forceRefresh: true),
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final gap = maxW < 400 ? 8.0 : 10.0;
              final isMobileGrid = maxW < 680;
              final cols = maxW >= 1060 ? 5 : 3;
              final halfWidth = (maxW - gap) / 2;
              final webWidth = (maxW - gap * (cols - 1)) / cols;
              final baseW = isMobileGrid ? halfWidth : webWidth;

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  _bannerKpi(
                    'İzlenen Öğrenci',
                    '${ds.students.length}',
                    '${ds.classes.length} Aktif Şube',
                    const Color(0xFF38BDF8),
                    width: baseW,
                  ),
                  _bannerKpi(
                    'Sınav Havuzu',
                    '${ds.trialExams.length + ds.classExams.length}',
                    '${ds.trialExams.length} Deneme • ${ds.classExams.length} Yazılı',
                    const Color(0xFF34D399),
                    width: baseW,
                  ),
                  _bannerKpi(
                    'Kritik Akademik Risk',
                    '${ds.criticalRiskCount}',
                    '${ds.warningRiskCount} Yakın Takip',
                    const Color(0xFFF87171),
                    width: baseW,
                  ),
                  _bannerKpi(
                    'Devamsızlık Radarı',
                    '${ds.criticalAttendanceCount}',
                    'Sınıra Yaklaşan',
                    const Color(0xFFFBBF24),
                    width: baseW,
                  ),
                  _bannerKpi(
                    'Ödev Disiplini',
                    '%${ds.overallHomeworkCompletionRate.toStringAsFixed(0)}',
                    'Genel Tamamlama',
                    const Color(0xFFA78BFA),
                    width: isMobileGrid ? maxW : baseW,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _bannerKpi(
    String label,
    String value,
    String sub,
    Color accent, {
    required double width,
  }) {
    final compact = width < 165;
    final hPad = compact ? 10.0 : 14.0;
    final vPad = compact ? 9.0 : 11.0;
    final valSize = (width * 0.115).clamp(17.0, 21.0);

    return SizedBox(
      width: width,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: compact ? 10.4 : 11.2,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.78),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: valSize,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: compact ? 10.0 : 11.0,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterStrip(bool isMobile, int toolCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 860;
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _groupChip('all', 'Tüm Araçlar ($toolCount)'),
                    _groupChip('exam', 'Sınav, Koçluk & Simülasyon'),
                    _groupChip('risk', 'Risk, Ödev & Devamsızlık'),
                    _groupChip('teacher', 'Öğretmen Ölçme Stüdyosu'),
                  ],
                ),
                const SizedBox(height: 12),
                AcademicSearchField(
                  hint: 'Araç veya özellik ara...',
                  accentColor: const Color(0xFF059669),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _groupChip('all', 'Tüm Araçlar ($toolCount)'),
                    _groupChip('exam', 'Sınav, Koçluk & Simülasyon'),
                    _groupChip('risk', 'Risk, Ödev & Devamsızlık'),
                    _groupChip('teacher', 'Öğretmen Ölçme Stüdyosu'),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 280,
                child: AcademicSearchField(
                  hint: 'Araç veya özellik ara...',
                  accentColor: const Color(0xFF059669),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _groupChip(String key, String label) {
    return AcademicChoicePill(
      label: label,
      selected: _selectedGroup == key,
      accentColor: const Color(0xFF0F172A),
      onTap: () => setState(() => _selectedGroup = key),
    );
  }

  Widget _buildToolCard(BuildContext context, _AcademicToolMeta tool) {
    final primary = tool.gradient.first;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => tool.onOpen(context),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: 0.06),
                blurRadius: 14,
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
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: tool.gradient),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(tool.icon, color: Colors.white, size: 22),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      tool.badge,
                      style: GoogleFonts.inter(
                        fontSize: 11.2,
                        fontWeight: FontWeight.w800,
                        color: primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                tool.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  tool.subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12.2,
                    color: const Color(0xFF64748B),
                    height: 1.38,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: tool.tags.take(2).map((tg) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Text(
                            tg,
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF475569),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  Icon(Icons.arrow_forward_rounded, size: 18, color: primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AcademicToolMeta {
  final String permKey;
  final String group;
  final List<String> extraGroups;
  final String title;
  final String subtitle;
  final String badge;
  final List<String> tags;
  final IconData icon;
  final List<Color> gradient;
  final void Function(BuildContext) onOpen;

  const _AcademicToolMeta({
    required this.permKey,
    required this.group,
    this.extraGroups = const [],
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.tags,
    required this.icon,
    required this.gradient,
    required this.onOpen,
  });
}
