import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../models/assessment/central_exam_model.dart';
import '../../../models/assessment/exam_type_model.dart';
import '../../../services/central_assessment_service.dart';
import '../../../widgets/safe_stream_builder.dart';
import '../../school/assessment/assessment_definitions_screen.dart';
import '../../school/assessment/error_booklet/error_booklet_dashboard_screen.dart';
import '../../school/assessment/exam_type_list_screen.dart';
import '../../school/assessment/outcome_list_screen.dart';
import '../../school/assessment/question_pool/question_pool_screen.dart';
import 'central_exam_analytics_screen.dart';
import 'central_exam_wizard_screen.dart';

class CentralAssessmentDashboardScreen extends StatefulWidget {
  final bool showAppBar;

  const CentralAssessmentDashboardScreen({super.key, this.showAppBar = false});

  @override
  State<CentralAssessmentDashboardScreen> createState() =>
      _CentralAssessmentDashboardScreenState();
}

class _CentralAssessmentDashboardScreenState
    extends State<CentralAssessmentDashboardScreen> {
  final CentralAssessmentService _service = CentralAssessmentService();
  final TextEditingController _searchController = TextEditingController();

  int _selectedSectionIndex = 0;
  String _classFilter = 'Tümü';
  String? _mergingExamId;
  bool _isCreatingTemplate = false;
  CentralExam? _selectedAnalyticsExam;

  late final Stream<List<CentralExam>> _centralExamsStream;
  late final Stream<List<ExamType>> _hqExamTypesStream;

  @override
  void initState() {
    super.initState();
    _centralExamsStream = _service.streamCentralExams();
    _hqExamTypesStream = _service.streamHqExamTypes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openCreateOrEditWizard([CentralExam? existing]) async {
    final saved = await Navigator.push<CentralExam>(
      context,
      MaterialPageRoute(
        builder: (_) => CentralExamWizardScreen(existingExam: existing),
      ),
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          content: Text(
            '"${saved.name}" merkezi denemesi kaydedildi ve ${saved.targets.length} okul kademesine senkronize edildi.',
          ),
        ),
      );
    }
  }

  Future<void> _mergeCentralExam(CentralExam exam) async {
    if (_mergingExamId != null) return;
    setState(() => _mergingExamId = exam.id);
    try {
      final res = await _service.evaluateAndMergeCentralExam(exam.id);
      final updated = await _service.getCentralExam(exam.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          content: Text(
            'Genel değerlendirme tamamlandı! ${res.participatingSchoolsCount} kademe • ${res.totalParticipants} öğrenci sıralaması güncellendi.',
          ),
        ),
      );
      if (updated != null) {
        setState(() {
          _selectedAnalyticsExam = updated;
          _selectedSectionIndex = 1;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFDC2626),
          content: Text(e.toString().replaceAll('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _mergingExamId = null);
      }
    }
  }

  Future<void> _confirmDeleteExam(CentralExam exam) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Merkezi Denemeyi Sil'),
        content: Text(
          '"${exam.name}" merkezi denemesini silmek istediğinize emin misiniz? Henüz optik okuma yapmamış okullardaki sınav kayıtları pasife alınacaktır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _service.deleteCentralExam(exam.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Merkezi deneme kaldırıldı.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFDC2626),
          content: Text('Silme hatası: $e'),
        ),
      );
    }
  }

  Future<void> _quickCreateTemplate(String key) async {
    if (_isCreatingTemplate) return;
    setState(() => _isCreatingTemplate = true);
    try {
      final created = await _service.createStandardExamTypeTemplate(key);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          content: Text('"${created.name}" sınav türü şablonu oluşturuldu.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFDC2626),
          content: Text('Şablon oluşturulamadı: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isCreatingTemplate = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          _buildModuleHeader(),
          Expanded(child: _buildSelectedSection()),
        ],
      ),
    );

    if (widget.showAppBar) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: const Color(0xFF0F172A),
          foregroundColor: Colors.white,
          title: Text(
            'Genel Merkez Ölçme ve Değerlendirme',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
        ),
        body: body,
      );
    }

    return body;
  }

  Widget _buildModuleHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.hub_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Genel Merkez Ölçme & Değerlendirme Merkezi',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'Çoklu okul merkezi deneme yönetimi, Türkiye geneli sıralama birleştirme, bölgesel analiz ve kurumsal ihtiyaç raporlama',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _openCreateOrEditWizard(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A8A),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 19),
                label: Text(
                  'Yeni Merkezi Deneme Oluştur',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _navPill(
                  index: 0,
                  icon: Icons.assignment_turned_in_rounded,
                  label: 'Merkezi Denemeler',
                ),
                const SizedBox(width: 8),
                _navPill(
                  index: 1,
                  icon: Icons.radar_rounded,
                  label: 'Genel İstatistik & İhtiyaç Radarı',
                ),
                const SizedBox(width: 8),
                _navPill(
                  index: 2,
                  icon: Icons.tune_rounded,
                  label: 'Merkezi Tanımlar (Sınav Türü & Kazanımlar)',
                ),
                const SizedBox(width: 8),
                _navPill(
                  index: 3,
                  icon: Icons.auto_stories_rounded,
                  label: 'Merkezi Soru Havuzu & Kitapçık Kırpma',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navPill({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final selected = _selectedSectionIndex == index;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _selectedSectionIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1E3A8A) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 17,
              color: selected ? Colors.white : const Color(0xFF475569),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedSection() {
    switch (_selectedSectionIndex) {
      case 0:
        return _buildCentralExamsTab();
      case 1:
        return CentralExamAnalyticsScreen(
          embedded: true,
          initialExam: _selectedAnalyticsExam,
        );
      case 2:
        return _buildCentralDefinitionsTab();
      case 3:
        return _buildQuestionPoolAndBookletTab();
      default:
        return _buildCentralExamsTab();
    }
  }

  // ---------------------------------------------------------------------------
  // SECTION 0: MERKEZİ DENEMELER
  // ---------------------------------------------------------------------------

  Widget _buildCentralExamsTab() {
    return SafeStreamBuilder<List<CentralExam>>(
      stream: _centralExamsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allExams = snapshot.data ?? [];
        final totalAssignedTargets = allExams.fold<int>(
          0,
          (sum, e) => sum + e.targets.length,
        );
        final totalEvaluatedStudents = allExams.fold<int>(
          0,
          (sum, e) => sum + e.totalParticipants,
        );
        final evaluatedCount = allExams
            .where((e) => e.status == 'evaluated')
            .length;

        final classLevels = <String>{
          'Tümü',
          ...allExams.map((e) => e.classLevel).where((c) => c.isNotEmpty),
        }.toList();

        final q = _searchController.text.trim().toLowerCase();
        final filtered = allExams.where((e) {
          if (_classFilter != 'Tümü' && e.classLevel != _classFilter) {
            return false;
          }
          if (q.isNotEmpty) {
            final hay = '${e.name} ${e.examTypeName} ${e.classLevel}'
                .toLowerCase();
            return hay.contains(q);
          }
          return true;
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(22),
          children: [
            // Summary KPI Strip
            LayoutBuilder(
              builder: (ctx, constraints) {
                final isWide = constraints.maxWidth > 860;
                final w = isWide
                    ? (constraints.maxWidth - 36) / 4
                    : (constraints.maxWidth > 520
                          ? (constraints.maxWidth - 12) / 2
                          : constraints.maxWidth);
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: w,
                      child: _summaryTile(
                        title: 'Merkezi Deneme Sayısı',
                        value: '${allExams.length}',
                        subtitle: '$evaluatedCount Değerlendirildi',
                        icon: Icons.library_books_rounded,
                        color: const Color(0xFF2563EB),
                      ),
                    ),
                    SizedBox(
                      width: w,
                      child: _summaryTile(
                        title: 'Atanan Okul Kademesi',
                        value: '$totalAssignedTargets',
                        subtitle: 'Otomatik Çocuk Sınav Senkronu',
                        icon: Icons.domain_verification_rounded,
                        color: const Color(0xFF7C3AED),
                      ),
                    ),
                    SizedBox(
                      width: w,
                      child: _summaryTile(
                        title: 'Birleşik Öğrenci Katılımı',
                        value: '$totalEvaluatedStudents',
                        subtitle: 'Genel Sıralaması Hesaplanan',
                        icon: Icons.groups_rounded,
                        color: const Color(0xFF059669),
                      ),
                    ),
                    SizedBox(
                      width: w,
                      child: _summaryTile(
                        title: 'Aktif Dönem & Havuz',
                        value: 'Canlı Senkron',
                        subtitle: 'Optik & Kazanım Entegre',
                        icon: Icons.verified_rounded,
                        color: const Color(0xFFD97706),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),

            // Search & Filter Bar
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Merkezi deneme adı veya sınav türü ara...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFFCBD5E1),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: classLevels.contains(_classFilter)
                            ? _classFilter
                            : 'Tümü',
                        items: classLevels
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text('Sınıf: $c'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _classFilter = v);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (filtered.isEmpty)
              Container(
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.assignment_outlined,
                      size: 56,
                      color: Colors.indigo.shade200,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      allExams.isEmpty
                          ? 'Henüz tanımlanmış bir Genel Merkez denemesi yok.'
                          : 'Arama kriterlerine uygun deneme bulunamadı.',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: const Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sağ üstteki "Yeni Merkezi Deneme Oluştur" butonuyla cevap anahtarı, kazanımlar ve hedef bölge/okulları seçerek deneme başlatabilirsiniz.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...filtered.map(_buildExamCard),
          ],
        );
      },
    );
  }

  Widget _buildExamCard(CentralExam exam) {
    final isEvaluated = exam.status == 'evaluated';
    final isAssigned = exam.targets.isNotEmpty;
    final statusLabel = isEvaluated
        ? 'Genel Değerlendirildi • ${exam.totalParticipants} Öğrenci'
        : (isAssigned
              ? 'Okullara Atandı • ${exam.targets.length} Kademe'
              : 'Taslak');
    final statusColor = isEvaluated
        ? const Color(0xFF059669)
        : (isAssigned ? const Color(0xFF2563EB) : const Color(0xFF64748B));

    final isMergingThis = _mergingExamId == exam.id;
    final booklets = List.generate(
      exam.bookletCount,
      (i) => String.fromCharCode(65 + i),
    ).join(', ');

    final regionsCount = exam.targets.map((t) => t.region).toSet().length;
    final schoolsCount = exam.targets.map((t) => t.schoolId).toSet().length;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      exam.classLevel,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: const Color(0xFF1E3A8A),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      exam.name,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _metaItem(
                Icons.calendar_today_rounded,
                DateFormat('dd.MM.yyyy').format(exam.date),
              ),
              _metaItem(Icons.category_outlined, exam.examTypeName),
              _metaItem(
                Icons.menu_book_outlined,
                'Kitapçık: $booklets (${exam.sessionCount} Oturum)',
              ),
              _metaItem(
                Icons.domain_rounded,
                '$schoolsCount Okul • ${exam.targets.length} Kademe • $regionsCount Bölge',
              ),
              if (exam.participatingSchoolsCount > 0)
                _metaItem(
                  Icons.fact_check_rounded,
                  'Okuma Yapan: ${exam.participatingSchoolsCount} / ${exam.targets.length} Kademe',
                ),
            ],
          ),
          const Divider(height: 24, color: Color(0xFFF1F5F9)),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openCreateOrEditWizard(exam),
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: const Text('Düzenle / Okul Ata'),
              ),
              OutlinedButton.icon(
                onPressed: isMergingThis ? null : () => _mergeCentralExam(exam),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF059669),
                  side: const BorderSide(color: Color(0xFF10B981)),
                ),
                icon: isMergingThis
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.hub_rounded, size: 18),
                label: Text(
                  isMergingThis
                      ? 'Birleştiriliyor...'
                      : 'Genel Değerlendirmeyi Birleştir',
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedAnalyticsExam = exam;
                    _selectedSectionIndex = 1;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A8A),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                icon: const Icon(Icons.analytics_rounded, size: 18),
                label: const Text('İstatistik & Okul Raporları'),
              ),
              IconButton(
                tooltip: 'Denemeyi Sil',
                onPressed: () => _confirmDeleteExam(exam),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFDC2626),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: const Color(0xFF64748B)),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: const Color(0xFF475569),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SECTION 2: MERKEZİ TANIMLAR (SINAV TÜRÜ & KAZANIMLAR)
  // ---------------------------------------------------------------------------

  Widget _buildCentralDefinitionsTab() {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hızlı Kurumsal Sınav Türü Şablonları (1-Tıkla Oluştur)',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Standart MEB / ÖSYM katsayıları ve branş soru dağılımlarıyla hazır Genel Merkez sınav türü şablonları ekleyin.',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _templateChipButton('LGS', 'LGS (8. Sınıf • 90 Soru)'),
                  _templateChipButton('TYT', 'TYT (120 Soru • 5 Şık)'),
                  _templateChipButton('AYT', 'AYT (160 Soru • 5 Şık)'),
                  _templateChipButton(
                    'ORTAOKUL',
                    'Ortaokul Kurumsal (5-6-7. Sınıf)',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        LayoutBuilder(
          builder: (ctx, constraints) {
            final isWide = constraints.maxWidth > 760;
            final cardW = isWide
                ? (constraints.maxWidth - 28) / 3
                : constraints.maxWidth;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                SizedBox(
                  width: cardW,
                  child: _featureActionCard(
                    title: 'Merkezi Sınav Türleri',
                    subtitle:
                        'Branşlar, soru sayıları, puan katsayıları ve yanlış-doğru götürme oranlarını yönetin.',
                    icon: Icons.settings_suggest_rounded,
                    color: const Color(0xFFD97706),
                    buttonText: 'Sınav Türlerini Yönet',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ExamTypeListScreen(
                            institutionId:
                                CentralAssessmentService.hqInstitutionId,
                            schoolTypeName: 'Genel Merkez',
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: cardW,
                  child: _featureActionCard(
                    title: 'Merkezi Kazanım Listeleri',
                    subtitle:
                        'MEB müfredat kazanımlarını sınıf ve ders bazında tanımlayıp cevap anahtarlarıyla eşleştirin.',
                    icon: Icons.checklist_rtl_rounded,
                    color: const Color(0xFF0D9488),
                    buttonText: 'Kazanım Listelerini Aç',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const OutcomeListScreen(
                            institutionId:
                                CentralAssessmentService.hqInstitutionId,
                            schoolTypeName: 'Genel Merkez',
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: cardW,
                  child: _featureActionCard(
                    title: 'Tüm Ölçme Tanımları',
                    subtitle:
                        'Sınav türleri, örnek optik form şablonları ve kazanım listelerinin tamamına tek ekrandan erişin.',
                    icon: Icons.dashboard_customize_rounded,
                    color: const Color(0xFF2563EB),
                    buttonText: 'Tanımlar Ekranını Aç',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AssessmentDefinitionsScreen(
                            institutionId:
                                CentralAssessmentService.hqInstitutionId,
                            schoolTypeName: 'Genel Merkez',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),

        // Live HQ Exam Types Preview
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tanımlı Genel Merkez Sınav Türleri',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 10),
              SafeStreamBuilder<List<ExamType>>(
                stream: _hqExamTypesStream,
                builder: (ctx, snap) {
                  final list = snap.data ?? [];
                  if (list.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Henüz Genel Merkez sınav türü bulunmuyor. Üstteki şablon butonlarıyla saniyeler içinde ekleyebilirsiniz.',
                      ),
                    );
                  }
                  return Column(
                    children: list.map((et) {
                      final totalQ = et.subjects.fold<int>(
                        0,
                        (s, item) => s + item.questionCount,
                      );
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFEEF2FF),
                          child: Text(
                            '${et.optionCount}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E3A8A),
                            ),
                          ),
                        ),
                        title: Text(
                          et.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${et.subjects.length} Branş • Toplam $totalQ Soru • ${et.wrongCorrectRatio.toStringAsFixed(0)} Yanlış 1 Doğruyu Götürür • Max Puan: ${et.maxScore.toStringAsFixed(0)}',
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _templateChipButton(String key, String label) {
    return OutlinedButton.icon(
      onPressed: _isCreatingTemplate ? null : () => _quickCreateTemplate(key),
      icon: const Icon(Icons.bolt_rounded, size: 18, color: Color(0xFFD97706)),
      label: Text(label),
    );
  }

  // ---------------------------------------------------------------------------
  // SECTION 3: MERKEZİ SORU HAVUZU & KİTAPÇIK KIRPMA
  // ---------------------------------------------------------------------------

  Widget _buildQuestionPoolAndBookletTab() {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        LayoutBuilder(
          builder: (ctx, constraints) {
            final isWide = constraints.maxWidth > 720;
            final cardW = isWide
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: cardW,
                  child: _featureActionCard(
                    title: 'Merkezi Soru Havuzu & Dizgi Editörü',
                    subtitle:
                        'Branş ve kazanım etiketli merkezi soru bankasını yönetin; seçilen konulardan otomatik veya manuel kurumsal deneme / tarama testi dizgisi oluşturun.',
                    icon: Icons.quiz_rounded,
                    color: const Color(0xFF4F46E5),
                    buttonText: 'Merkezi Soru Havuzunu Aç',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const QuestionPoolScreen(
                            institutionId:
                                CentralAssessmentService.hqInstitutionId,
                            schoolTypeId:
                                CentralAssessmentService.hqInstitutionId,
                            schoolTypeName: 'Genel Merkez',
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: cardW,
                  child: _featureActionCard(
                    title: 'PDF Kitapçık Soru Kırpma & Hata Kitapçığı',
                    subtitle:
                        'Deneme PDF kitapçıklarından soruları kırpıp numaralandırın, merkezi soru havuzuna aktarın ve eksik kazanımlara özel telafi fasikülleri üretin.',
                    icon: Icons.crop_original_rounded,
                    color: const Color(0xFF059669),
                    buttonText: 'Kitapçık Kırpma & Editörü Aç',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ErrorBookletDashboardScreen(
                            institutionId:
                                CentralAssessmentService.hqInstitutionId,
                            schoolTypeId:
                                CentralAssessmentService.hqInstitutionId,
                            schoolTypeName: 'Genel Merkez',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _summaryTile({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _featureActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String buttonText,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.45,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(
              buttonText,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
