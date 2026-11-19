import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../models/assessment/central_exam_model.dart';
import '../../../services/central_assessment_service.dart';

class CentralExamAnalyticsScreen extends StatefulWidget {
  final CentralExam? initialExam;
  final bool embedded;

  const CentralExamAnalyticsScreen({
    super.key,
    this.initialExam,
    this.embedded = false,
  });

  @override
  State<CentralExamAnalyticsScreen> createState() =>
      _CentralExamAnalyticsScreenState();
}

class _CentralExamAnalyticsScreenState
    extends State<CentralExamAnalyticsScreen> {
  final CentralAssessmentService _service = CentralAssessmentService();
  final TextEditingController _schoolSearchController = TextEditingController();
  final TextEditingController _advisorNoteController = TextEditingController();

  List<CentralExam> _allExams = [];
  CentralExam? _selectedExam;
  List<CentralChildExamStatus> _liveStatuses = [];

  bool _isLoadingExams = true;
  bool _isLoadingStatuses = false;
  bool _isMerging = false;
  bool _isSendingReport = false;
  bool _isSendingBulkReports = false;
  bool _sendWithAnnouncement = true;

  String _selectedRegionFilter = 'Tümü';
  String _needsRegionFilter = 'Tümü';
  String? _selectedReportChildDocId;
  String? _boundAdvisorSchoolTypeId;

  @override
  void initState() {
    super.initState();
    _selectedExam = widget.initialExam;
    _loadInitialData();
  }

  @override
  void didUpdateWidget(covariant CentralExamAnalyticsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialExam != null &&
        widget.initialExam!.id != oldWidget.initialExam?.id) {
      _selectExam(widget.initialExam!);
    }
  }

  @override
  void dispose() {
    _schoolSearchController.dispose();
    _advisorNoteController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoadingExams = true);
    try {
      final snapExams = await _service.streamCentralExams().first;
      CentralExam? target = _selectedExam;
      if (target != null) {
        final match = snapExams.where((e) => e.id == target!.id);
        if (match.isNotEmpty) {
          target = match.first;
        }
      } else if (snapExams.isNotEmpty) {
        target = snapExams.first;
      }

      if (!mounted) return;
      setState(() {
        _allExams = snapExams;
        _selectedExam = target;
        _isLoadingExams = false;
      });

      if (target != null) {
        _syncSelectedSchoolDefault(target);
        await _refreshLiveStatuses(target);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingExams = false);
      }
    }
  }

  void _syncSelectedSchoolDefault(CentralExam exam) {
    final okullar = _extractListOfMaps(exam.analyticsSummary['okullar']);
    if (okullar.isEmpty) {
      _selectedReportChildDocId = null;
      _boundAdvisorSchoolTypeId = null;
      _advisorNoteController.clear();
      return;
    }
    Map<String, dynamic>? matched;
    for (final o in okullar) {
      if (o['childTrialExamId']?.toString() == _selectedReportChildDocId) {
        matched = o;
        break;
      }
    }
    if (matched == null) {
      _selectSchoolForReport(exam, okullar.first);
    } else if (_boundAdvisorSchoolTypeId !=
        matched['schoolTypeId']?.toString()) {
      _selectSchoolForReport(exam, matched);
    }
  }

  void _selectSchoolForReport(
    CentralExam exam,
    Map<String, dynamic> schoolEntry,
  ) {
    _selectedReportChildDocId = schoolEntry['childTrialExamId']?.toString();
    _boundAdvisorSchoolTypeId = schoolEntry['schoolTypeId']?.toString();
    _advisorNoteController.text = _service.buildDefaultAdvisorNote(
      exam,
      schoolEntry,
    );
  }

  Future<void> _selectExam(CentralExam exam) async {
    final fresh = await _service.getCentralExam(exam.id) ?? exam;
    if (!mounted) return;
    setState(() {
      _selectedExam = fresh;
      _selectedRegionFilter = 'Tümü';
      _needsRegionFilter = 'Tümü';
      _boundAdvisorSchoolTypeId = null;
      _syncSelectedSchoolDefault(fresh);
    });
    await _refreshLiveStatuses(fresh);
  }

  Future<void> _refreshLiveStatuses([CentralExam? examOverride]) async {
    final exam = examOverride ?? _selectedExam;
    if (exam == null) return;
    setState(() => _isLoadingStatuses = true);
    try {
      final statuses = await _service.getChildExamStatuses(exam);
      if (!mounted) return;
      setState(() {
        _liveStatuses = statuses;
        _isLoadingStatuses = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingStatuses = false);
      }
    }
  }

  Future<void> _runGlobalMerge() async {
    final exam = _selectedExam;
    if (exam == null || _isMerging) return;

    setState(() => _isMerging = true);
    try {
      final result = await _service.evaluateAndMergeCentralExam(exam.id);
      final updatedExam = await _service.getCentralExam(exam.id);
      if (!mounted) return;

      if (updatedExam != null) {
        setState(() {
          _selectedExam = updatedExam;
          final idx = _allExams.indexWhere((e) => e.id == updatedExam.id);
          if (idx >= 0) {
            _allExams[idx] = updatedExam;
          }
          _boundAdvisorSchoolTypeId = null;
          _syncSelectedSchoolDefault(updatedExam);
        });
        await _refreshLiveStatuses(updatedExam);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          content: Text(
            'Genel değerlendirme tamamlandı: ${result.participatingSchoolsCount} okul • ${result.totalParticipants} öğrenci sıralaması birleştirildi!',
          ),
        ),
      );
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
        setState(() => _isMerging = false);
      }
    }
  }

  Future<void> _previewOrPrintSchoolPdf(
    CentralExam exam,
    Map<String, dynamic> schoolEntry,
  ) async {
    final report = _service.buildSchoolReportFromAnalytics(
      exam: exam,
      schoolEntry: schoolEntry,
      advisorNote: _advisorNoteController.text,
    );
    await Printing.layoutPdf(
      name: '${report.schoolName}_${report.centralExamName}_Rapor.pdf',
      onLayout: (_) => _service.generateSchoolReportPdfBytes(report),
    );
  }

  Future<void> _shareSchoolPdf(
    CentralExam exam,
    Map<String, dynamic> schoolEntry,
  ) async {
    final report = _service.buildSchoolReportFromAnalytics(
      exam: exam,
      schoolEntry: schoolEntry,
      advisorNote: _advisorNoteController.text,
    );
    final bytes = await _service.generateSchoolReportPdfBytes(report);
    final safeName =
        '${report.schoolName}_${report.centralExamName}_GenelMerkezRaporu'
            .replaceAll(RegExp(r'[^\w\-ğüşıöçĞÜŞİÖÇ ]'), '_')
            .replaceAll(' ', '_');
    await Printing.sharePdf(bytes: bytes, filename: '$safeName.pdf');
  }

  Future<void> _sendSingleSchoolReport(
    CentralExam exam,
    Map<String, dynamic> schoolEntry,
  ) async {
    if (_isSendingReport) return;
    setState(() => _isSendingReport = true);
    try {
      final report = await _service.sendReportToSchool(
        exam: exam,
        schoolEntry: schoolEntry,
        advisorNote: _advisorNoteController.text,
        createSchoolAnnouncement: _sendWithAnnouncement,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          content: Text(
            '${report.schoolName} (${report.schoolTypeName}) kurumuna resmi değerlendirme raporu gönderildi.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFDC2626),
          content: Text('Rapor gönderilirken hata oluştu: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSendingReport = false);
      }
    }
  }

  Future<void> _sendAllSchoolReports(CentralExam exam) async {
    final okullar = _extractListOfMaps(exam.analyticsSummary['okullar']);
    if (okullar.isEmpty || _isSendingBulkReports) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Tüm Katılan Okullara Rapor Gönder'),
        content: Text(
          'Değerlendirmeye katılan ${okullar.length} okul kademesinin tamamına karşılaştırmalı başarı, kazanım ihtiyaç listesi ve Genel Merkez raporu gönderilecektir. Onaylıyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Tümüne Gönder'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSendingBulkReports = true);
    try {
      final count = await _service.sendReportsToAllParticipatingSchools(
        exam: exam,
        createSchoolAnnouncement: _sendWithAnnouncement,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          content: Text(
            'Toplam $count okul kademesine Genel Merkez değerlendirme raporu başarıyla iletildi!',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFDC2626),
          content: Text('Toplu rapor gönderiminde hata: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSendingBulkReports = false);
      }
    }
  }

  List<Map<String, dynamic>> _extractListOfMaps(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildMainBody();
    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        title: Text(
          'Genel Merkez Sınav Analitiği & İhtiyaç Radarı',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        actions: [
          IconButton(
            tooltip: 'Durumları Yenile',
            onPressed: _isLoadingStatuses ? null : () => _refreshLiveStatuses(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _buildMainBody() {
    if (_isLoadingExams) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_allExams.isEmpty && _selectedExam == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.analytics_outlined,
                size: 64,
                color: Colors.indigo.shade200,
              ),
              const SizedBox(height: 14),
              Text(
                'Henüz analiz edilecek merkezi deneme bulunmuyor.',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Önce Merkezi Denemeler sekmesinden yeni bir deneme oluşturup okullara atayın.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final exam = _selectedExam!;
    return DefaultTabController(
      length: 4,
      child: Builder(
        builder: (tabContext) => Column(
          children: [
            _buildTopControlBanner(exam),
            Container(
              color: Colors.white,
              child: TabBar(
                isScrollable: MediaQuery.of(context).size.width < 920,
                labelColor: const Color(0xFF1E3A8A),
                unselectedLabelColor: const Color(0xFF64748B),
                indicatorColor: const Color(0xFF2563EB),
                indicatorWeight: 3,
                labelStyle: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                unselectedLabelStyle: GoogleFonts.inter(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
                tabs: const [
                  Tab(
                    icon: Icon(Icons.leaderboard_rounded, size: 18),
                    text: 'Genel Katılım & Sıralama',
                  ),
                  Tab(
                    icon: Icon(Icons.map_rounded, size: 18),
                    text: 'Bölge & İl Karşılaştırması',
                  ),
                  Tab(
                    icon: Icon(Icons.apartment_rounded, size: 18),
                    text: 'Okul & Kademe Sıralaması',
                  ),
                  Tab(
                    icon: Icon(Icons.radar_rounded, size: 18),
                    text: 'İhtiyaç Haritası & Okullara Rapor',
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Expanded(
              child: TabBarView(
                children: [
                  _buildGeneralTab(exam),
                  _buildRegionAndCityTab(exam),
                  _buildSchoolsRankingTab(exam, tabContext),
                  _buildNeedsAndReportsTab(exam),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopControlBanner(CentralExam exam) {
    final evaluatedLiveCount = _liveStatuses
        .where((s) => s.isEvaluatedLocally)
        .length;
    final liveStudentTotal = _liveStatuses.fold<int>(
      0,
      (sum, s) => sum + s.participantCount,
    );
    final assignedCount = exam.targets.length;
    final lastEvalStr = exam.lastEvaluatedAt != null
        ? DateFormat('dd.MM.yyyy HH:mm').format(exam.lastEvaluatedAt!)
        : 'Henüz Birleştirilmedi';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_allExams.length > 1 || widget.embedded)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _allExams.any((e) => e.id == exam.id)
                              ? exam.id
                              : null,
                          dropdownColor: const Color(0xFF1E293B),
                          isExpanded: true,
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Colors.white,
                          ),
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                          items: _allExams
                              .map(
                                (e) => DropdownMenuItem<String>(
                                  value: e.id,
                                  child: Text(
                                    '${e.name} (${e.classLevel} • ${DateFormat('dd.MM.yyyy').format(e.date)})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val == null) return;
                            final found = _allExams.firstWhere(
                              (e) => e.id == val,
                            );
                            _selectExam(found);
                          },
                        ),
                      ),
                    ),
                  )
                else
                  Text(
                    exam.name,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    _bannerPill(
                      Icons.fact_check_outlined,
                      _isLoadingStatuses
                          ? 'Canlı optik durumu kontrol ediliyor...'
                          : '$evaluatedLiveCount / $assignedCount Kademe Okudu ($liveStudentTotal Öğrenci)',
                      const Color(0xFF38BDF8),
                    ),
                    _bannerPill(
                      Icons.schedule_rounded,
                      'Son Birleştirme: $lastEvalStr',
                      const Color(0xFFA7F3D0),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.embedded)
                OutlinedButton.icon(
                  onPressed: _isLoadingStatuses
                      ? null
                      : () => _refreshLiveStatuses(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Canlı Kontrol'),
                ),
              ElevatedButton.icon(
                onPressed: _isMerging ? null : _runGlobalMerge,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  elevation: 2,
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
                icon: _isMerging
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.hub_rounded, size: 19),
                label: Text(
                  _isMerging
                      ? 'Sıralamalar Birleştiriliyor...'
                      : 'Genel Değerlendirmeyi Birleştir / Güncelle',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bannerPill(IconData icon, String text, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: GENEL KATILIM & SIRALAMA
  // ---------------------------------------------------------------------------

  Widget _buildGeneralTab(CentralExam exam) {
    final summary = exam.analyticsSummary;
    final genel = summary['genel'] is Map
        ? Map<String, dynamic>.from(summary['genel'] as Map)
        : <String, dynamic>{};
    final hasAnalytics = genel.isNotEmpty;

    final orderedSubjects = (summary['orderedSubjects'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    final subjectsMap = genel['subjects'] is Map
        ? Map<String, dynamic>.from(genel['subjects'] as Map)
        : <String, dynamic>{};
    final leaderboard = _extractListOfMaps(genel['topLeaderboard']);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (!hasAnalytics)
          _buildEmptyAnalyticsCallout()
        else ...[
          LayoutBuilder(
            builder: (ctx, constraints) {
              final isWide = constraints.maxWidth > 840;
              final cardWidth = isWide
                  ? (constraints.maxWidth - 36) / 4
                  : (constraints.maxWidth > 500
                        ? (constraints.maxWidth - 12) / 2
                        : constraints.maxWidth);
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: _kpiCard(
                      title: 'Genel Katılımcı',
                      value: '${genel['totalParticipants'] ?? 0}',
                      subtitle: 'Tüm Okullar Birleşik Havuz',
                      icon: Icons.groups_rounded,
                      color: const Color(0xFF2563EB),
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _kpiCard(
                      title: 'Katılan / Atanan Kademe',
                      value:
                          '${genel['participatingSchoolsCount'] ?? 0} / ${exam.targets.length}',
                      subtitle:
                          'Bekleyen: ${genel['pendingSchoolsCount'] ?? 0} Kademe',
                      icon: Icons.account_balance_rounded,
                      color: const Color(0xFF7C3AED),
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _kpiCard(
                      title: 'Genel Puan Ortalaması',
                      value: ((genel['avgScore'] as num?)?.toDouble() ?? 0.0)
                          .toStringAsFixed(2),
                      subtitle:
                          'Ort. Toplam Net: ${((genel['avgNet'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                      icon: Icons.insights_rounded,
                      color: const Color(0xFF059669),
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _kpiCard(
                      title: 'En Yüksek / En Düşük Puan',
                      value:
                          '${((genel['maxScore'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(1)} / ${((genel['minScore'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(1)}',
                      subtitle: exam.examTypeName,
                      icon: Icons.emoji_events_rounded,
                      color: const Color(0xFFD97706),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // Global Subject Averages Card
          _sectionCard(
            title: 'Türkiye / Genel Merkez Branş Başarı Ortalamaları',
            subtitle:
                'Tüm katılımcı okulların birleştirilmiş doğru, yanlış, boş ve net istatistikleri',
            icon: Icons.menu_book_rounded,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  const Color(0xFFF1F5F9),
                ),
                columns: const [
                  DataColumn(label: Text('Ders / Branş')),
                  DataColumn(label: Text('Soru'), numeric: true),
                  DataColumn(label: Text('Doğru Ort.'), numeric: true),
                  DataColumn(label: Text('Yanlış Ort.'), numeric: true),
                  DataColumn(label: Text('Boş Ort.'), numeric: true),
                  DataColumn(label: Text('Net Ort.'), numeric: true),
                  DataColumn(label: Text('Başarı %')),
                ],
                rows:
                    (orderedSubjects.isNotEmpty
                            ? orderedSubjects
                            : subjectsMap.keys.toList())
                        .map((subj) {
                          final m = subjectsMap[subj] is Map
                              ? Map<String, dynamic>.from(
                                  subjectsMap[subj] as Map,
                                )
                              : <String, dynamic>{};
                          final rate =
                              (m['successRate'] as num?)?.toDouble() ?? 0.0;
                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  subj,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              DataCell(Text('${m['questionCount'] ?? 0}')),
                              DataCell(
                                Text(
                                  ((m['avgCorrect'] as num?)?.toDouble() ?? 0.0)
                                      .toStringAsFixed(2),
                                ),
                              ),
                              DataCell(
                                Text(
                                  ((m['avgWrong'] as num?)?.toDouble() ?? 0.0)
                                      .toStringAsFixed(2),
                                ),
                              ),
                              DataCell(
                                Text(
                                  ((m['avgEmpty'] as num?)?.toDouble() ?? 0.0)
                                      .toStringAsFixed(2),
                                ),
                              ),
                              DataCell(
                                Text(
                                  ((m['avgNet'] as num?)?.toDouble() ?? 0.0)
                                      .toStringAsFixed(2),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1E3A8A),
                                  ),
                                ),
                              ),
                              DataCell(_rateBarBadge(rate)),
                            ],
                          );
                        })
                        .toList(),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Live Optical Participation Status Card (always shown)
        _sectionCard(
          title: 'Atanan Okullar Canlı Optik Okuma & Yayın Takibi',
          subtitle:
              'Hangi okulların optik yüklediği, değerlendirdiği veya henüz beklediği anlık izlenir',
          icon: Icons.fact_check_rounded,
          child: _liveStatuses.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Bu denemeye henüz okul/kademe atanmamış.'),
                )
              : Column(
                  children: _liveStatuses.map((st) {
                    final Color badgeColor = st.isEvaluatedLocally
                        ? const Color(0xFF059669)
                        : (st.hasOpticalUpload
                              ? const Color(0xFFD97706)
                              : const Color(0xFF64748B));
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            st.isEvaluatedLocally
                                ? Icons.check_circle_rounded
                                : (st.hasOpticalUpload
                                      ? Icons.pending_rounded
                                      : Icons.hourglass_empty_rounded),
                            color: badgeColor,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${st.target.schoolName} • ${st.target.schoolTypeName}',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5,
                                  ),
                                ),
                                Text(
                                  '${st.target.region} / ${st.target.city.isNotEmpty ? st.target.city : "-"}',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (st.isEvaluatedLocally) ...[
                            Text(
                              'Ort: ${st.avgScore.toStringAsFixed(2)}p',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                                color: const Color(0xFF1E3A8A),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              st.statusLabel,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: badgeColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),

        if (leaderboard.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionCard(
            title:
                'Genel Merkez İlk 50 Öğrenci Sıralaması (Türkiye Dereceleri)',
            subtitle:
                'Gizlilik kuralları gereği soyadları maskelenmiş genel derece tablosu',
            icon: Icons.workspace_premium_rounded,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  const Color(0xFFF1F5F9),
                ),
                columns: const [
                  DataColumn(label: Text('Genel Sıra')),
                  DataColumn(label: Text('Öğrenci')),
                  DataColumn(label: Text('Okul / Kademe')),
                  DataColumn(label: Text('Bölge / İl')),
                  DataColumn(label: Text('Toplam Net'), numeric: true),
                  DataColumn(label: Text('Puan'), numeric: true),
                ],
                rows: leaderboard.map((row) {
                  final rank = (row['rank'] as num?)?.toInt() ?? 0;
                  return DataRow(
                    cells: [
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: rank <= 3
                                ? const Color(0xFFFEF3C7)
                                : const Color(0xFFE0E7FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '#$rank',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: rank <= 3
                                  ? const Color(0xFFB45309)
                                  : const Color(0xFF1E3A8A),
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          (row['studentName'] ?? '').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${row['schoolName'] ?? ''} (${row['schoolTypeName'] ?? ''})',
                        ),
                      ),
                      DataCell(
                        Text('${row['region'] ?? ''} / ${row['city'] ?? ''}'),
                      ),
                      DataCell(
                        Text(
                          ((row['net'] as num?)?.toDouble() ?? 0.0)
                              .toStringAsFixed(2),
                        ),
                      ),
                      DataCell(
                        Text(
                          ((row['score'] as num?)?.toDouble() ?? 0.0)
                              .toStringAsFixed(2),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: BÖLGE & İL KARŞILAŞTIRMASI
  // ---------------------------------------------------------------------------

  Widget _buildRegionAndCityTab(CentralExam exam) {
    final bolgeler = _extractListOfMaps(exam.analyticsSummary['bolgeler']);
    final iller = _extractListOfMaps(exam.analyticsSummary['iller']);

    if (bolgeler.isEmpty && iller.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [_buildEmptyAnalyticsCallout()],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _sectionCard(
          title: 'Coğrafi Bölge Bazlı Başarı ve İhtiyaç Karşılaştırması',
          subtitle:
              '7 coğrafi bölgedeki okulların puan, net, genel ortalamadan sapma ve en zayıf kazanım dağılımı',
          icon: Icons.public_rounded,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
              columns: const [
                DataColumn(label: Text('Bölge')),
                DataColumn(label: Text('Okul'), numeric: true),
                DataColumn(label: Text('Öğrenci'), numeric: true),
                DataColumn(label: Text('Puan Ort.'), numeric: true),
                DataColumn(label: Text('Net Ort.'), numeric: true),
                DataColumn(label: Text('Genel Fark'), numeric: true),
                DataColumn(label: Text('En Öncelikli Bölgesel İhtiyaç')),
              ],
              rows: bolgeler.map((r) {
                final diff = (r['diffFromGeneral'] as num?)?.toDouble() ?? 0.0;
                final weakList = _extractListOfMaps(r['weakOutcomes']);
                final topWeak = weakList.isNotEmpty
                    ? '${weakList.first['subject']}: ${weakList.first['outcome']} (%${weakList.first['successRate']})'
                    : 'Kritik eksik yok';
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        (r['region'] ?? '').toString(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    DataCell(Text('${r['schoolCount'] ?? 0}')),
                    DataCell(Text('${r['studentCount'] ?? 0}')),
                    DataCell(
                      Text(
                        ((r['avgScore'] as num?)?.toDouble() ?? 0.0)
                            .toStringAsFixed(2),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    DataCell(
                      Text(
                        ((r['avgNet'] as num?)?.toDouble() ?? 0.0)
                            .toStringAsFixed(2),
                      ),
                    ),
                    DataCell(_deltaChip(diff)),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: Text(
                          topWeak,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: weakList.isNotEmpty
                                ? const Color(0xFFB45309)
                                : const Color(0xFF059669),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _sectionCard(
          title: 'İl Bazlı Kurumsal Performans Sıralaması',
          subtitle: 'Katılımcı illerin puan ve net ortalamaları',
          icon: Icons.location_city_rounded,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
              columns: const [
                DataColumn(label: Text('Sıra')),
                DataColumn(label: Text('İl')),
                DataColumn(label: Text('Bölge')),
                DataColumn(label: Text('Okul'), numeric: true),
                DataColumn(label: Text('Öğrenci'), numeric: true),
                DataColumn(label: Text('Puan Ort.'), numeric: true),
                DataColumn(label: Text('Net Ort.'), numeric: true),
                DataColumn(label: Text('Genel Fark'), numeric: true),
              ],
              rows: List.generate(iller.length, (idx) {
                final c = iller[idx];
                final diff = (c['diffFromGeneral'] as num?)?.toDouble() ?? 0.0;
                return DataRow(
                  cells: [
                    DataCell(Text('#${idx + 1}')),
                    DataCell(
                      Text(
                        (c['city'] ?? '').toString(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    DataCell(Text((c['region'] ?? '').toString())),
                    DataCell(Text('${c['schoolCount'] ?? 0}')),
                    DataCell(Text('${c['studentCount'] ?? 0}')),
                    DataCell(
                      Text(
                        ((c['avgScore'] as num?)?.toDouble() ?? 0.0)
                            .toStringAsFixed(2),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    DataCell(
                      Text(
                        ((c['avgNet'] as num?)?.toDouble() ?? 0.0)
                            .toStringAsFixed(2),
                      ),
                    ),
                    DataCell(_deltaChip(diff)),
                  ],
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 3: OKUL & KADEME SIRALAMASI
  // ---------------------------------------------------------------------------

  Widget _buildSchoolsRankingTab(CentralExam exam, BuildContext tabContext) {
    final allSchools = _extractListOfMaps(exam.analyticsSummary['okullar']);
    if (allSchools.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [_buildEmptyAnalyticsCallout()],
      );
    }

    final regions = <String>{
      'Tümü',
      ...allSchools.map((s) => (s['region'] ?? 'Belirtilmemiş').toString()),
    }.toList();

    final query = _schoolSearchController.text.trim().toLowerCase();
    final filtered = allSchools.where((s) {
      if (_selectedRegionFilter != 'Tümü' &&
          s['region']?.toString() != _selectedRegionFilter) {
        return false;
      }
      if (query.isNotEmpty) {
        final hay =
            '${s['schoolName']} ${s['schoolTypeName']} ${s['city']} ${s['region']}'
                .toLowerCase();
        return hay.contains(query);
      }
      return true;
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _sectionCard(
          title: 'Okul ve Kademe Başarı Sıralaması (${filtered.length} Kurum)',
          subtitle:
              'Genel Merkez ortalamasına göre kurumsal sıralama ve hızlı rapor erişimi',
          icon: Icons.apartment_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 300,
                    child: TextField(
                      controller: _schoolSearchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Okul, kademe veya il ara...',
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
                        value: regions.contains(_selectedRegionFilter)
                            ? _selectedRegionFilter
                            : 'Tümü',
                        items: regions
                            .map(
                              (r) => DropdownMenuItem(
                                value: r,
                                child: Text('Bölge: $r'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _selectedRegionFilter = v);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    const Color(0xFFF1F5F9),
                  ),
                  columns: const [
                    DataColumn(label: Text('Sıra')),
                    DataColumn(label: Text('Okul & Kademe')),
                    DataColumn(label: Text('Bölge / İl')),
                    DataColumn(label: Text('Öğrenci'), numeric: true),
                    DataColumn(label: Text('Puan Ort.'), numeric: true),
                    DataColumn(label: Text('En Yüksek'), numeric: true),
                    DataColumn(label: Text('Net Ort.'), numeric: true),
                    DataColumn(label: Text('Genel Fark'), numeric: true),
                    DataColumn(label: Text('İhtiyaç & Rapor')),
                  ],
                  rows: filtered.map((s) {
                    final rank = (s['schoolRank'] as num?)?.toInt() ?? 0;
                    final diff =
                        (s['diffFromGeneral'] as num?)?.toDouble() ?? 0.0;
                    final weakCount =
                        (s['weakOutcomes'] as List<dynamic>? ?? []).length;
                    return DataRow(
                      cells: [
                        DataCell(
                          Text(
                            '#$rank',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: rank <= 3
                                  ? const Color(0xFFD97706)
                                  : const Color(0xFF1E3A8A),
                            ),
                          ),
                        ),
                        DataCell(
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (s['schoolName'] ?? '').toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                (s['schoolTypeName'] ?? '').toString(),
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        DataCell(
                          Text('${s['region'] ?? ''} / ${s['city'] ?? ''}'),
                        ),
                        DataCell(Text('${s['studentCount'] ?? 0}')),
                        DataCell(
                          Text(
                            ((s['avgScore'] as num?)?.toDouble() ?? 0.0)
                                .toStringAsFixed(2),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            ((s['maxScore'] as num?)?.toDouble() ?? 0.0)
                                .toStringAsFixed(2),
                          ),
                        ),
                        DataCell(
                          Text(
                            ((s['avgNet'] as num?)?.toDouble() ?? 0.0)
                                .toStringAsFixed(2),
                          ),
                        ),
                        DataCell(_deltaChip(diff)),
                        DataCell(
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _needsRegionFilter = 'Tümü';
                                _selectSchoolForReport(exam, s);
                              });
                              DefaultTabController.of(tabContext).animateTo(3);
                            },
                            icon: const Icon(
                              Icons.assignment_late_outlined,
                              size: 16,
                            ),
                            label: Text('$weakCount İhtiyaç • Raporla'),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 4: İHTİYAÇ HARİTASI & OKULLARA RAPOR
  // ---------------------------------------------------------------------------

  Widget _buildNeedsAndReportsTab(CentralExam exam) {
    final allSchools = _extractListOfMaps(exam.analyticsSummary['okullar']);
    final kazanimlarRaw = exam.analyticsSummary['kazanimlar'] is Map
        ? Map<String, dynamic>.from(exam.analyticsSummary['kazanimlar'] as Map)
        : <String, dynamic>{};

    if (allSchools.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [_buildEmptyAnalyticsCallout()],
      );
    }

    final regions = <String>{
      'Tümü',
      ...allSchools.map((s) => (s['region'] ?? 'Belirtilmemiş').toString()),
    }.toList();

    final filteredSchools = _needsRegionFilter == 'Tümü'
        ? allSchools
        : allSchools
              .where((s) => s['region']?.toString() == _needsRegionFilter)
              .toList();

    Map<String, dynamic>? selectedSchool;
    for (final s in filteredSchools) {
      if (s['childTrialExamId']?.toString() == _selectedReportChildDocId) {
        selectedSchool = s;
        break;
      }
    }
    bool didFallbackToFirstSchool = false;
    if (selectedSchool == null && filteredSchools.isNotEmpty) {
      selectedSchool = filteredSchools.first;
      didFallbackToFirstSchool = true;
    }

    if (selectedSchool != null) {
      final resolvedSchoolTypeId = selectedSchool['schoolTypeId']?.toString();
      if (_boundAdvisorSchoolTypeId != resolvedSchoolTypeId) {
        final targetSchool = selectedSchool;
        _boundAdvisorSchoolTypeId = resolvedSchoolTypeId;
        _selectedReportChildDocId = targetSchool['childTrialExamId']
            ?.toString();
        _advisorNoteController.text = _service.buildDefaultAdvisorNote(
          exam,
          targetSchool,
        );
        if (didFallbackToFirstSchool) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                _selectedReportChildDocId !=
                    targetSchool['childTrialExamId']?.toString()) {
              setState(() {
                _selectSchoolForReport(exam, targetSchool);
              });
            }
          });
        }
      }
    }

    final previewReport = selectedSchool != null
        ? _service.buildSchoolReportFromAnalytics(
            exam: exam,
            schoolEntry: selectedSchool,
            advisorNote: _advisorNoteController.text,
          )
        : null;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Bulk & Filter Action Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Wrap(
            spacing: 14,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: regions.contains(_needsRegionFilter)
                            ? _needsRegionFilter
                            : 'Tümü',
                        items: regions
                            .map(
                              (r) => DropdownMenuItem(
                                value: r,
                                child: Text('Bölge Filtresi: $r'),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val == null) return;
                          setState(() {
                            _needsRegionFilter = val;
                            final nextList = val == 'Tümü'
                                ? allSchools
                                : allSchools
                                      .where(
                                        (s) => s['region']?.toString() == val,
                                      )
                                      .toList();
                            if (nextList.isNotEmpty) {
                              _selectSchoolForReport(exam, nextList.first);
                            }
                          });
                        },
                      ),
                    ),
                  ),
                  if (filteredSchools.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 260,
                        maxWidth: 420,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: selectedSchool?['childTrialExamId']
                                ?.toString(),
                            items: filteredSchools.map((s) {
                              final docId = s['childTrialExamId'].toString();
                              return DropdownMenuItem<String>(
                                value: docId,
                                child: Text(
                                  '#${s['schoolRank']} ${s['schoolName']} (${s['schoolTypeName']})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (docId) {
                              if (docId == null) return;
                              final found = filteredSchools.firstWhere(
                                (s) =>
                                    s['childTrialExamId']?.toString() == docId,
                              );
                              setState(() {
                                _selectSchoolForReport(exam, found);
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: _sendWithAnnouncement,
                        onChanged: (v) =>
                            setState(() => _sendWithAnnouncement = v ?? true),
                      ),
                      Text(
                        'Okul Duyurusu da Oluştur',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: _isSendingBulkReports
                        ? null
                        : () => _sendAllSchoolReports(exam),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    icon: _isSendingBulkReports
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.campaign_rounded, size: 18),
                    label: Text(
                      _isSendingBulkReports
                          ? 'Toplu Gönderiliyor...'
                          : 'Tüm Katılan Okullara Rapor Gönder (${allSchools.length})',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        if (selectedSchool != null && previewReport != null) ...[
          const SizedBox(height: 18),
          _sectionCard(
            title:
                '${previewReport.schoolName} • ${previewReport.schoolTypeName} — İhtiyaç Analizi ve Resmi Rapor',
            subtitle:
                '${previewReport.region} / ${previewReport.city} • Kurum Sırası: #${previewReport.schoolRank} / ${previewReport.totalParticipatingSchools} • Katılan: ${previewReport.participantCount} Öğrenci',
            icon: Icons.analytics_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Action Buttons Row
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isSendingReport
                          ? null
                          : () =>
                                _sendSingleSchoolReport(exam, selectedSchool!),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A8A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      icon: _isSendingReport
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: const Text('Bu Okula Rapor Gönder'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _previewOrPrintSchoolPdf(exam, selectedSchool!),
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                      label: const Text('Resmi PDF Önizle / Yazdır'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _shareSchoolPdf(exam, selectedSchool!),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('PDF İndir / Paylaş'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Comparative Subject Summary
                Text(
                  '1. Branş Bazlı Karşılaştırma (Okul vs Bölge vs Genel Merkez)',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      const Color(0xFFF8FAFC),
                    ),
                    columns: const [
                      DataColumn(label: Text('Branş')),
                      DataColumn(label: Text('Soru'), numeric: true),
                      DataColumn(label: Text('Okul Net'), numeric: true),
                      DataColumn(label: Text('Bölge Net'), numeric: true),
                      DataColumn(label: Text('Genel Net'), numeric: true),
                      DataColumn(label: Text('Okul Başarı %')),
                      DataColumn(label: Text('Genel Fark'), numeric: true),
                    ],
                    rows: previewReport.subjectComparisons.map((row) {
                      final diff = (row['diffNet'] as num?)?.toDouble() ?? 0.0;
                      final rate =
                          (row['schoolSuccessRate'] as num?)?.toDouble() ?? 0.0;
                      return DataRow(
                        cells: [
                          DataCell(
                            Text(
                              (row['subject'] ?? '').toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          DataCell(Text('${row['questionCount'] ?? 0}')),
                          DataCell(
                            Text(
                              ((row['schoolNet'] as num?)?.toDouble() ?? 0.0)
                                  .toStringAsFixed(2),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              ((row['regionNet'] as num?)?.toDouble() ?? 0.0)
                                  .toStringAsFixed(2),
                            ),
                          ),
                          DataCell(
                            Text(
                              ((row['generalNet'] as num?)?.toDouble() ?? 0.0)
                                  .toStringAsFixed(2),
                            ),
                          ),
                          DataCell(_rateBarBadge(rate)),
                          DataCell(_deltaChip(diff)),
                        ],
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 20),

                // Weak Outcomes Needs List ("Kimin Neye İhtiyacı Var?")
                Text(
                  '2. Öncelikli Kazanım İhtiyaç Listesi (${previewReport.ihtiyacAnalizi.length} Tespit)',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                if (previewReport.ihtiyacAnalizi.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Bu okulda kritik başarı eşiğinin altında kalan kazanım tespit edilmemiştir.',
                      style: TextStyle(
                        color: Color(0xFF065F46),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  ...previewReport.ihtiyacAnalizi.map((need) {
                    final isUrgent = need.priority == 'ACİL DESTEK';
                    final badgeBg = isUrgent
                        ? const Color(0xFFFEE2E2)
                        : const Color(0xFFFEF3C7);
                    final badgeFg = isUrgent
                        ? const Color(0xFFDC2626)
                        : const Color(0xFFB45309);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              need.priority,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: badgeFg,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  need.subject,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF1E3A8A),
                                  ),
                                ),
                                Text(
                                  need.outcome,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Okul: %${need.schoolSuccessRate.toStringAsFixed(1)}',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                  color: badgeFg,
                                ),
                              ),
                              Text(
                                'Genel: %${need.generalSuccessRate.toStringAsFixed(1)}',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: 18),

                // HQ Advisor Note Field
                Text(
                  '3. Genel Merkez Akademik Danışman / Müfettiş Değerlendirme Notu',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _advisorNoteController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText:
                        'Okul yönetimine ve zümre başkanlarına iletilecek akademik değerlendirme notu...',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Global Outcome Mastery Radar
        if (kazanimlarRaw.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionCard(
            title: 'Türkiye Geneli Kazanım Başarı & Destek İhtiyaç Haritası',
            subtitle:
                'Hangi kazanımda kaç okulun acil destek / telafi etüdüne ihtiyaç duyduğunu gösterir',
            icon: Icons.hub_outlined,
            child: Column(
              children: kazanimlarRaw.entries.map((entry) {
                final subj = entry.key;
                final list = _extractListOfMaps(entry.value);
                return ExpansionTile(
                  title: Text(
                    '$subj (${list.length} Kazanım)',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Kazanım')),
                          DataColumn(label: Text('Soru'), numeric: true),
                          DataColumn(label: Text('Doğru %')),
                          DataColumn(label: Text('Yanlış %'), numeric: true),
                          DataColumn(label: Text('Boş %'), numeric: true),
                          DataColumn(
                            label: Text('Destek Gereken Okul'),
                            numeric: true,
                          ),
                        ],
                        rows: list.map((k) {
                          final cRate =
                              (k['correctRate'] as num?)?.toDouble() ?? 0.0;
                          final supportCount =
                              (k['schoolsNeedingSupportCount'] as num?)
                                  ?.toInt() ??
                              0;
                          return DataRow(
                            cells: [
                              DataCell(
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 420,
                                  ),
                                  child: Text(
                                    (k['outcome'] ?? '').toString(),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(Text('${k['questionCount'] ?? 1}')),
                              DataCell(_rateBarBadge(cRate)),
                              DataCell(Text('%${k['wrongRate'] ?? 0}')),
                              DataCell(Text('%${k['emptyRate'] ?? 0}')),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: supportCount > 0
                                        ? const Color(0xFFFEE2E2)
                                        : const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '$supportCount Okul',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: supportCount > 0
                                          ? const Color(0xFFDC2626)
                                          : const Color(0xFF059669),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SHARED UI HELPERS
  // ---------------------------------------------------------------------------

  Widget _buildEmptyAnalyticsCallout() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFF1D4ED8),
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Genel Değerlendirme Henüz Birleştirilmedi',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: const Color(0xFF1E3A8A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Okullar kendi optik dosyalarını (.txt / .dat) yükleyip değerlendirdikten sonra üstteki "Genel Değerlendirmeyi Birleştir / Güncelle" butonuna tıklayarak Türkiye geneli sıralama, bölge ve kazanım ihtiyaç analizini tek tıkla oluşturabilirsiniz.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiCard({
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
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
                const SizedBox(height: 3),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
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

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF1E3A8A), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _rateBarBadge(double rate) {
    final color = rate >= 70
        ? const Color(0xFF059669)
        : (rate >= 50 ? const Color(0xFFD97706) : const Color(0xFFDC2626));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 56,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (rate / 100.0).clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '%${rate.toStringAsFixed(1)}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _deltaChip(double diff) {
    final isPos = diff >= 0;
    final color = isPos ? const Color(0xFF059669) : const Color(0xFFDC2626);
    final sign = isPos ? '+' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$sign${diff.toStringAsFixed(2)}',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: color,
        ),
      ),
    );
  }
}
