import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:edukn/widgets/safe_stream_builder.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../models/assessment/central_exam_model.dart';
import '../../../services/central_assessment_service.dart';

class CentralSchoolReportsScreen extends StatefulWidget {
  final String institutionId;
  final String? schoolTypeId;
  final String? initialCentralExamId;

  const CentralSchoolReportsScreen({
    super.key,
    required this.institutionId,
    this.schoolTypeId,
    this.initialCentralExamId,
  });

  @override
  State<CentralSchoolReportsScreen> createState() =>
      _CentralSchoolReportsScreenState();
}

class _CentralSchoolReportsScreenState
    extends State<CentralSchoolReportsScreen> {
  final CentralAssessmentService _service = CentralAssessmentService();
  late Stream<List<CentralSchoolReport>> _reportsStream;
  String? _selectedReportId;
  bool _isGeneratingPdf = false;

  @override
  void initState() {
    super.initState();
    _reportsStream = _service.streamSchoolReports(
      institutionId: widget.institutionId,
      schoolTypeId: widget.schoolTypeId,
    );
  }

  @override
  void didUpdateWidget(covariant CentralSchoolReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.institutionId != widget.institutionId ||
        oldWidget.schoolTypeId != widget.schoolTypeId) {
      _reportsStream = _service.streamSchoolReports(
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
      );
    }
  }

  Future<void> _printReport(CentralSchoolReport report) async {
    if (_isGeneratingPdf) return;
    setState(() => _isGeneratingPdf = true);
    try {
      await Printing.layoutPdf(
        name: '${report.schoolName}_${report.centralExamName}_Rapor.pdf',
        onLayout: (_) => _service.generateSchoolReportPdfBytes(report),
      );
    } finally {
      if (mounted) {
        setState(() => _isGeneratingPdf = false);
      }
    }
  }

  Future<void> _downloadReport(CentralSchoolReport report) async {
    if (_isGeneratingPdf) return;
    setState(() => _isGeneratingPdf = true);
    try {
      final bytes = await _service.generateSchoolReportPdfBytes(report);
      final safeName =
          '${report.schoolName}_${report.centralExamName}_GenelMerkezRaporu'
              .replaceAll(RegExp(r'[^\w\-ğüşıöçĞÜŞİÖÇ ]'), '_')
              .replaceAll(' ', '_');
      await Printing.sharePdf(bytes: bytes, filename: '$safeName.pdf');
    } finally {
      if (mounted) {
        setState(() => _isGeneratingPdf = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: const EduknAppBar(
        title: 'Genel Merkez Değerlendirme Raporları',
        subtitle: 'Türkiye Geneli Karşılaştırmalı Analiz & Kazanım İhtiyaçları',
      ),
      body: SafeStreamBuilder<List<CentralSchoolReport>>(
        stream: _reportsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final reports = snapshot.data ?? [];
          if (reports.isEmpty) {
            return _buildEmptyState();
          }

          CentralSchoolReport selected = reports.first;
          if (_selectedReportId != null) {
            final found = reports.where((r) => r.id == _selectedReportId);
            if (found.isNotEmpty) {
              selected = found.first;
            }
          } else if ((widget.initialCentralExamId ?? '').isNotEmpty) {
            final found = reports.where(
              (r) => r.centralExamId == widget.initialCentralExamId,
            );
            if (found.isNotEmpty) {
              selected = found.first;
            }
          }

          return LayoutBuilder(
            builder: (ctx, constraints) {
              final isDesktop = constraints.maxWidth >= 900;
              if (isDesktop) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 340,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            right: BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                        child: _buildReportList(reports, selected),
                      ),
                    ),
                    Expanded(child: _buildReportDetail(selected)),
                  ],
                );
              }

              return Column(
                children: [
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                          value: selected.id,
                          items: reports
                              .map(
                                (r) => DropdownMenuItem<String>(
                                  value: r.id,
                                  child: Text(
                                    '${r.centralExamName} (${DateFormat('dd.MM.yyyy').format(r.examDate)})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (id) {
                            if (id != null) {
                              setState(() => _selectedReportId = id);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  Expanded(child: _buildReportDetail(selected)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.analytics_outlined,
                color: Color(0xFF1E3A8A),
                size: 38,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Henüz Gönderilmiş Genel Merkez Raporu Bulunmuyor',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Text(
                'Genel Merkez tarafından tanımlanan merkezi denemelerin değerlendirmesi birleştirilip kurumunuza rapor gönderildiğinde karşılaştırmalı başarı ve kazanım ihtiyaç analizleri burada görüntülenir.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 1.45,
                  color: const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportList(
    List<CentralSchoolReport> reports,
    CentralSchoolReport selected,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: reports.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, index) {
        final r = reports[index];
        final isSelected = r.id == selected.id;
        final diff = r.schoolAvgScore - r.generalAvgScore;
        final diffColor = diff >= 0
            ? const Color(0xFF059669)
            : const Color(0xFFDC2626);

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _selectedReportId = r.id),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFEEF2FF)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF3B82F6)
                    : const Color(0xFFE2E8F0),
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E3A8A),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Sıra: #${r.schoolRank} / ${r.totalParticipatingSchools}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Text(
                      DateFormat('dd.MM.yyyy').format(r.examDate),
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  r.centralExamName,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${r.schoolTypeName} • ${r.classLevel}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Okul Ort: ${r.schoolAvgScore.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      '${diff >= 0 ? "+" : ""}${diff.toStringAsFixed(2)}p Genel Fark',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                        color: diffColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReportDetail(CentralSchoolReport report) {
    final diffGen = report.schoolAvgScore - report.generalAvgScore;
    final diffSign = diffGen >= 0 ? '+' : '';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Report Banner Header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Wrap(
            spacing: 16,
            runSpacing: 14,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '🏛️ GENEL MERKEZ KURUMSAL DEĞERLENDİRME RAPORU',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF93C5FD),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    report.centralExamName,
                    style: GoogleFonts.inter(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${report.schoolName} • ${report.schoolTypeName} (${report.region} / ${report.city}) • ${DateFormat('dd.MM.yyyy').format(report.examDate)}',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: const Color(0xFFE2E8F0),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isGeneratingPdf
                        ? null
                        : () => _printReport(report),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    icon: const Icon(Icons.print_rounded, size: 18),
                    label: const Text('Yazdır / Önizle'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isGeneratingPdf
                        ? null
                        : () => _downloadReport(report),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
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
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                    label: const Text('Resmi PDF İndir'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 4 KPI Cards
        LayoutBuilder(
          builder: (ctx, constraints) {
            final isWide = constraints.maxWidth > 760;
            final cardW = isWide
                ? (constraints.maxWidth - 36) / 4
                : (constraints.maxWidth > 460
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth);
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: cardW,
                  child: _kpiTile(
                    title: 'Katılan Öğrenci',
                    value: '${report.participantCount}',
                    subtitle:
                        'Türkiye Geneli: ${report.generalParticipantCount}',
                    color: const Color(0xFF2563EB),
                    icon: Icons.groups_rounded,
                  ),
                ),
                SizedBox(
                  width: cardW,
                  child: _kpiTile(
                    title: 'Okul Ortalaması',
                    value: report.schoolAvgScore.toStringAsFixed(2),
                    subtitle:
                        'Genel Fark: $diffSign${diffGen.toStringAsFixed(2)}p',
                    color: diffGen >= 0
                        ? const Color(0xFF059669)
                        : const Color(0xFFDC2626),
                    icon: Icons.trending_up_rounded,
                  ),
                ),
                SizedBox(
                  width: cardW,
                  child: _kpiTile(
                    title: 'Bölge & Genel Ort.',
                    value:
                        '${report.regionAvgScore.toStringAsFixed(1)} / ${report.generalAvgScore.toStringAsFixed(1)}',
                    subtitle: 'Bölge: ${report.region}',
                    color: const Color(0xFF7C3AED),
                    icon: Icons.public_rounded,
                  ),
                ),
                SizedBox(
                  width: cardW,
                  child: _kpiTile(
                    title: 'Kurum Sıralaması',
                    value:
                        '#${report.schoolRank} / ${report.totalParticipatingSchools}',
                    subtitle:
                        'En Yüksek: ${report.schoolMaxScore.toStringAsFixed(1)}p',
                    color: const Color(0xFFD97706),
                    icon: Icons.emoji_events_rounded,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),

        // Subject Comparisons Card
        _cardSection(
          title: '1. Branş Bazlı Karşılaştırmalı Net ve Başarı Analizi',
          subtitle:
              'Kurumunuzun branş netlerinin kendi bölgeniz ve Türkiye/Genel Merkez ortalaması ile karşılaştırması',
          icon: Icons.bar_chart_rounded,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
              columns: const [
                DataColumn(label: Text('Ders / Branş')),
                DataColumn(label: Text('Soru'), numeric: true),
                DataColumn(label: Text('Okul Net'), numeric: true),
                DataColumn(label: Text('Bölge Net'), numeric: true),
                DataColumn(label: Text('Genel Net'), numeric: true),
                DataColumn(label: Text('Okul Başarı %')),
                DataColumn(label: Text('Genel Fark'), numeric: true),
              ],
              rows: report.subjectComparisons.map((row) {
                final diff = (row['diffNet'] as num?)?.toDouble() ?? 0.0;
                final sRate =
                    (row['schoolSuccessRate'] as num?)?.toDouble() ?? 0.0;
                final isPos = diff >= 0;
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        (row['subject'] ?? '').toString(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    DataCell(Text('${row['questionCount'] ?? 0}')),
                    DataCell(
                      Text(
                        ((row['schoolNet'] as num?)?.toDouble() ?? 0.0)
                            .toStringAsFixed(2),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E3A8A),
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
                    DataCell(
                      Text(
                        '%${sRate.toStringAsFixed(1)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: sRate >= 65
                              ? const Color(0xFF059669)
                              : (sRate >= 45
                                    ? const Color(0xFFD97706)
                                    : const Color(0xFFDC2626)),
                        ),
                      ),
                    ),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (isPos
                                      ? const Color(0xFF059669)
                                      : const Color(0xFFDC2626))
                                  .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${isPos ? "+" : ""}${diff.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: isPos
                                ? const Color(0xFF059669)
                                : const Color(0xFFDC2626),
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

        // Priority Weak Outcomes ("İhtiyaç Analizi")
        _cardSection(
          title:
              '2. Kazanım Bazlı İhtiyaç ve Güçlendirme Listesi (${report.ihtiyacAnalizi.length} Öncelikli Konu)',
          subtitle:
              'Kurumunuzda etüt, konu tekrarı ve telafi föyü planlanması önerilen öncelikli kazanımlar',
          icon: Icons.track_changes_rounded,
          child: report.ihtiyacAnalizi.isEmpty
              ? Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Tebrikler! Kritik başarı eşiğinin altında kalan kazanım tespit edilmemiştir.',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF065F46),
                    ),
                  ),
                )
              : Column(
                  children: report.ihtiyacAnalizi.map((need) {
                    final urgent = need.priority == 'ACİL DESTEK';
                    final color = urgent
                        ? const Color(0xFFDC2626)
                        : const Color(0xFFD97706);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  need.priority,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                    color: color,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  need.subject,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5,
                                    color: const Color(0xFF1E3A8A),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Okul: %${need.schoolSuccessRate.toStringAsFixed(1)}  •  Genel: %${need.generalSuccessRate.toStringAsFixed(1)}',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: const Color(0xFF334155),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            need.outcome,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (need.schoolSuccessRate / 100.0).clamp(
                                0.0,
                                1.0,
                              ),
                              minHeight: 6,
                              backgroundColor: const Color(0xFFE2E8F0),
                              valueColor: AlwaysStoppedAnimation<Color>(color),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 20),

        // HQ Advisor Note & Recommendations
        _cardSection(
          title: '3. Genel Merkez Akademik Değerlendirme Notu ve Öneriler',
          subtitle:
              'Kurum yönetimine ve zümre başkanlarına yönelik eylem planı',
          icon: Icons.tips_and_updates_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (report.advisorNote.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Text(
                    report.advisorNote,
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      height: 1.5,
                      color: const Color(0xFF1E3A8A),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              if (report.actionRecommendations.isNotEmpty) ...[
                const SizedBox(height: 14),
                ...report.actionRecommendations.map(
                  (rec) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 18,
                          color: Color(0xFF2563EB),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            rec,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              height: 1.45,
                              color: const Color(0xFF334155),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _kpiTile({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
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
                    fontSize: 17,
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

  Widget _cardSection({
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
}
