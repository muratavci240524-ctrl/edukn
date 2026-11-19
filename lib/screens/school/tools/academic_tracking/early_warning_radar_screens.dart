import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../widgets/edukn_app_bar.dart';
import 'academic_tracking_models.dart';
import 'academic_ui_widgets.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// ARAÇ 3: 360° AKADEMİK RİSK & ERKEN UYARI SİSTEMİ (EWS)
/// ═══════════════════════════════════════════════════════════════════════════
class EarlyWarningSystemScreen extends StatefulWidget {
  final AcademicDataset dataset;

  const EarlyWarningSystemScreen({super.key, required this.dataset});

  @override
  State<EarlyWarningSystemScreen> createState() =>
      _EarlyWarningSystemScreenState();
}

class _EarlyWarningSystemScreenState extends State<EarlyWarningSystemScreen> {
  String _tierFilter = 'risky'; // 'all' | 'critical' | 'warning' | 'risky'
  String? _classIdFilter;
  String _search = '';

  List<StudentRiskProfile> get _filteredProfiles {
    final q = AcademicTrackingDataService.normTr(_search);
    return widget.dataset.riskProfiles.where((p) {
      if (_tierFilter == 'critical' && p.riskTier != 'critical') return false;
      if (_tierFilter == 'warning' && p.riskTier != 'warning') return false;
      if (_tierFilter == 'risky' && p.riskTier == 'safe') return false;
      if (_classIdFilter != null && p.student.classId != _classIdFilter) {
        return false;
      }
      if (q.isNotEmpty) {
        final hay = AcademicTrackingDataService.normTr(
          '${p.student.name} ${p.student.className} ${p.student.studentNo}',
        );
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _exportPdf() async {
    final rows = _filteredProfiles;
    await AcademicTrackingPdfService.printTableReport(
      documentTitle: '360° AKADEMİK RİSK VE ERKEN UYARI MÜDAHALE LİSTESİ',
      schoolName: widget.dataset.schoolName,
      subtitle:
          'Deneme net değişimi, yazılı ortalaması, ödev disiplini ve özürsüz devamsızlık birleşik risk analizi',
      landscape: true,
      kpis: [
        (
          label: 'Kritik Risk (≥50)',
          value: '${widget.dataset.criticalRiskCount} Öğrenci',
        ),
        (
          label: 'Yakın Takip (25–49)',
          value: '${widget.dataset.warningRiskCount} Öğrenci',
        ),
        (label: 'Raporlanan Kayıt', value: '${rows.length} Öğrenci'),
      ],
      headers: const [
        'Öğrenci',
        'Sınıf',
        'Risk Skoru',
        'Son Deneme',
        'Yazılı Ort.',
        'Ödev %',
        'Özürsüz Gün',
        'Risk Gerekçeleri',
      ],
      rows: rows.map((p) {
        return [
          p.student.name,
          p.student.className,
          '${p.riskScore.toStringAsFixed(0)} / 100',
          p.latestTrialScore != null
              ? p.latestTrialScore!.toStringAsFixed(1)
              : '-',
          p.writtenGradeAverage != null
              ? p.writtenGradeAverage!.toStringAsFixed(1)
              : '-',
          '%${p.homeworkCompletionRate.toStringAsFixed(0)}',
          p.absentDays.toStringAsFixed(1),
          p.reasons.isEmpty ? 'Stabil' : p.reasons.join(' | '),
        ];
      }).toList(),
      notes: const [
        'Kritik Risk (≥50 puan) grubundaki öğrenciler için Rehberlik Servisi + Sınıf Danışman Öğretmeni + Veli üçlü görüşmesi önerilir.',
        'Yakın Takip (25–49 puan) grubundaki öğrenciler haftalık branş etüdü ve ödev kontrol listesine alınmalıdır.',
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 780;
    final list = _filteredProfiles;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: EduknAppBar(
        title: '360° Akademik Risk & Erken Uyarı Sistemi',
        subtitle: widget.dataset.schoolName,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton.icon(
              onPressed: list.isEmpty ? null : _exportPdf,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
              label: Text(
                isMobile ? 'PDF' : 'Müdahale Raporu PDF',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(isMobile ? 14 : 22),
        children: [
          _buildSummaryRow(isMobile),
          const SizedBox(height: 16),
          _buildFilterBar(isMobile),
          const SizedBox(height: 16),
          if (list.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.verified_user_rounded,
                    size: 48,
                    color: Color(0xFF059669),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Bu filtrede risk sinyali üreten öğrenci bulunmuyor.',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => setState(() => _tierFilter = 'all'),
                    child: const Text('Tüm Öğrencileri Görüntüle'),
                  ),
                ],
              ),
            )
          else
            ...list.map(_buildRiskCard),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(bool isMobile) {
    final safeCount = widget.dataset.riskProfiles
        .where((r) => r.riskTier == 'safe')
        .length;

    Widget kpi(
      String title,
      String val,
      String sub,
      Color color,
      IconData icon,
      String filterKey,
    ) {
      final selected = _tierFilter == filterKey;
      return InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _tierFilter = filterKey),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? color : const Color(0xFFE2E8F0),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
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
                    Text(
                      val,
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      sub,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final cards = [
      kpi(
        'Kritik Müdahale',
        '${widget.dataset.criticalRiskCount}',
        'Risk Skoru ≥ 50',
        const Color(0xFFDC2626),
        Icons.warning_amber_rounded,
        'critical',
      ),
      kpi(
        'Yakın Takip',
        '${widget.dataset.warningRiskCount}',
        'Risk Skoru 25–49',
        const Color(0xFFD97706),
        Icons.visibility_rounded,
        'warning',
      ),
      kpi(
        'Güvenli Seyir',
        '$safeCount',
        'Stabil Öğrenciler',
        const Color(0xFF059669),
        Icons.shield_rounded,
        'all',
      ),
    ];

    if (isMobile) {
      return Column(
        children: cards
            .map(
              (c) =>
                  Padding(padding: const EdgeInsets.only(bottom: 10), child: c),
            )
            .toList(),
      );
    }

    return Row(
      children: [
        Expanded(child: cards[0]),
        const SizedBox(width: 12),
        Expanded(child: cards[1]),
        const SizedBox(width: 12),
        Expanded(child: cards[2]),
      ],
    );
  }

  Widget _buildFilterBar(bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 720;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AcademicChoicePill(
                    label: 'Tüm Riskliler',
                    icon: Icons.warning_amber_rounded,
                    selected: _tierFilter == 'risky',
                    accentColor: const Color(0xFFDC2626),
                    onTap: () => setState(() => _tierFilter = 'risky'),
                  ),
                  AcademicChoicePill(
                    label: 'Sadece Kritik',
                    selected: _tierFilter == 'critical',
                    accentColor: const Color(0xFFDC2626),
                    onTap: () => setState(() => _tierFilter = 'critical'),
                  ),
                  AcademicChoicePill(
                    label: 'Yakın Takip',
                    selected: _tierFilter == 'warning',
                    accentColor: const Color(0xFFD97706),
                    onTap: () => setState(() => _tierFilter = 'warning'),
                  ),
                  AcademicChoicePill(
                    label: 'Tüm Okul',
                    selected: _tierFilter == 'all',
                    accentColor: const Color(0xFF059669),
                    onTap: () => setState(() => _tierFilter = 'all'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (narrow) ...[
                AcademicDropdownField<String?>(
                  label: 'Sınıf Filtresi',
                  icon: Icons.class_rounded,
                  accentColor: const Color(0xFFDC2626),
                  value: _classIdFilter,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Tüm Sınıflar'),
                    ),
                    ...widget.dataset.classes.map(
                      (c) => DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _classIdFilter = v),
                ),
                const SizedBox(height: 10),
                AcademicSearchField(
                  label: 'Öğrenci Arama',
                  hint: 'Öğrenci adı, sınıf veya numara ara...',
                  accentColor: const Color(0xFFDC2626),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      flex: 2,
                      child: AcademicDropdownField<String?>(
                        label: 'Sınıf Filtresi',
                        icon: Icons.class_rounded,
                        accentColor: const Color(0xFFDC2626),
                        value: _classIdFilter,
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Tüm Sınıflar'),
                          ),
                          ...widget.dataset.classes.map(
                            (c) => DropdownMenuItem<String?>(
                              value: c.id,
                              child: Text(
                                c.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() => _classIdFilter = v),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 3,
                      child: AcademicSearchField(
                        label: 'Öğrenci Arama',
                        hint: 'Öğrenci adı, sınıf veya numara ara...',
                        accentColor: const Color(0xFFDC2626),
                        onChanged: (v) => setState(() => _search = v),
                      ),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRiskCard(StudentRiskProfile p) {
    final color = p.riskTier == 'critical'
        ? const Color(0xFFDC2626)
        : (p.riskTier == 'warning'
              ? const Color(0xFFD97706)
              : const Color(0xFF059669));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  p.riskScore.toStringAsFixed(0),
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.student.name,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      '${p.student.className} ${p.student.studentNo.isNotEmpty ? "• No: ${p.student.studentNo}" : ""}',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  p.riskTier == 'critical'
                      ? 'KRİTİK RİSK'
                      : (p.riskTier == 'warning' ? 'YAKIN TAKİP' : 'GÜVENLİ'),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final isMobileGrid = maxW < 640;
              final gap = 8.0;
              final cellW = isMobileGrid
                  ? (maxW - gap) / 2
                  : (maxW - gap * 3) / 4;

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  _miniMetric(
                    'Son Deneme',
                    p.latestTrialScore != null
                        ? '${p.latestTrialScore!.toStringAsFixed(1)} Puan'
                        : 'Veri Yok',
                    width: cellW,
                  ),
                  _miniMetric(
                    'Yazılı Ort.',
                    p.writtenGradeAverage != null
                        ? p.writtenGradeAverage!.toStringAsFixed(1)
                        : 'Veri Yok',
                    width: cellW,
                  ),
                  _miniMetric(
                    'Ödev Tamamlama',
                    '%${p.homeworkCompletionRate.toStringAsFixed(0)}',
                    width: cellW,
                  ),
                  _miniMetric(
                    'Özürsüz Devamsızlık',
                    '${p.absentDays.toStringAsFixed(1)} Gün',
                    width: cellW,
                  ),
                ],
              );
            },
          ),
          if (p.reasons.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: p.reasons
                  .map(
                    (r) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '• $r',
                        style: GoogleFonts.inter(
                          fontSize: 11.8,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniMetric(String k, String v, {required double width}) {
    final compact = width < 165;
    return SizedBox(
      width: width,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          '$k: $v',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            fontSize: compact ? 11.0 : 12.0,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF334155),
          ),
        ),
      ),
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// ARAÇ 4: DEVAMSIZLIK VE GEÇ KALMA RADAR PANELİ
/// ═══════════════════════════════════════════════════════════════════════════
class AttendanceRadarToolScreen extends StatefulWidget {
  final AcademicDataset dataset;

  const AttendanceRadarToolScreen({super.key, required this.dataset});

  @override
  State<AttendanceRadarToolScreen> createState() =>
      _AttendanceRadarToolScreenState();
}

class _AttendanceRadarToolScreenState extends State<AttendanceRadarToolScreen> {
  // 'lise' (10 özürsüz / 30 toplam) | 'ilkogretim' (20 özürsüz)
  String _mebRule = 'lise';
  String _filterMode =
      'all_flagged'; // 'critical' | 'first_hour_late' | 'all_flagged' | 'all'
  String? _classId;

  double get _unexcusedLimit => _mebRule == 'lise' ? 10.0 : 20.0;
  double get _totalLimit => _mebRule == 'lise' ? 30.0 : 35.0;

  List<
    ({AcademicStudentInfo student, StudentAttendanceSummary att, double ratio})
  >
  get _rows {
    final result =
        <
          ({
            AcademicStudentInfo student,
            StudentAttendanceSummary att,
            double ratio,
          })
        >[];

    for (final st in widget.dataset.students) {
      if (_classId != null && st.classId != _classId) continue;
      final att =
          widget.dataset.attendanceByStudent[st.id] ??
          StudentAttendanceSummary(st.id);
      final unexRatio = att.estimatedAbsentDays / _unexcusedLimit;
      final totRatio = att.totalEstimatedDays / _totalLimit;
      final maxRatio = unexRatio > totRatio ? unexRatio : totRatio;

      if (_filterMode == 'critical' && maxRatio < 0.70) continue;
      if (_filterMode == 'first_hour_late' && att.firstHourLateCount < 2) {
        continue;
      }
      if (_filterMode == 'all_flagged' &&
          maxRatio < 0.30 &&
          att.lateLessons < 2) {
        continue;
      }

      result.add((student: st, att: att, ratio: maxRatio));
    }

    result.sort((a, b) {
      final c = b.ratio.compareTo(a.ratio);
      if (c != 0) return c;
      return b.att.lateLessons.compareTo(a.att.lateLessons);
    });
    return result;
  }

  Future<void> _exportPdf() async {
    final items = _rows;
    await AcademicTrackingPdfService.printTableReport(
      documentTitle: 'MEB DEVAMSIZLIK VE GEÇ KALMA RADAR UYARI LİSTESİ',
      schoolName: widget.dataset.schoolName,
      subtitle: _mebRule == 'lise'
          ? 'Ortaöğretim Yönetmeliği Eşiği: 10 Gün Özürsüz / 30 Gün Toplam'
          : 'İlköğretim Kurumları Eşiği: 20 Gün Özürsüz Devamsızlık Sınırı',
      kpis: [
        (
          label: 'Özürsüz Sınır',
          value: '${_unexcusedLimit.toStringAsFixed(0)} Gün',
        ),
        (label: 'Toplam Sınır', value: '${_totalLimit.toStringAsFixed(0)} Gün'),
        (label: 'Listelenen Öğrenci', value: '${items.length} Kişi'),
      ],
      headers: const [
        'Öğrenci',
        'Sınıf',
        'Özürsüz Gün',
        'Özürlü Gün',
        'Toplam Gün',
        'Geç Ders (1. Ders)',
        'Sınır Doluluk %',
      ],
      rows: items.map((r) {
        return [
          r.student.name,
          r.student.className,
          r.att.estimatedAbsentDays.toStringAsFixed(1),
          r.att.estimatedExcusedDays.toStringAsFixed(1),
          r.att.totalEstimatedDays.toStringAsFixed(1),
          '${r.att.lateLessons} (${r.att.firstHourLateCount})',
          '%${(r.ratio * 100).clamp(0, 100).toStringAsFixed(0)}',
        ];
      }).toList(),
      notes: const [
        'Sınır doluluk oranı %70 ve üzerine çıkan öğrenciler için resmi 1./2. devamsızlık mektubu ve veli bilgilendirmesi yapılmalıdır.',
        '1. ders geç kalma sayısı yüksek öğrenciler sabah servis / giriş disiplini açısından izlenmelidir.',
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 780;
    final items = _rows;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: EduknAppBar(
        title: 'Devamsızlık & Geç Kalma Radar Paneli',
        subtitle: widget.dataset.schoolName,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton.icon(
              onPressed: items.isEmpty ? null : _exportPdf,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE11D48),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
              label: Text(
                isMobile ? 'PDF' : 'Resmi Uyarı Listesi PDF',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(isMobile ? 14 : 22),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AcademicChoicePill(
                      label: 'Ortaöğretim (10 Özürsüz / 30 Toplam)',
                      icon: Icons.account_balance_rounded,
                      selected: _mebRule == 'lise',
                      accentColor: const Color(0xFFE11D48),
                      onTap: () => setState(() => _mebRule = 'lise'),
                    ),
                    AcademicChoicePill(
                      label: 'İlköğretim (20 Özürsüz Gün)',
                      icon: Icons.school_rounded,
                      selected: _mebRule == 'ilkogretim',
                      accentColor: const Color(0xFFE11D48),
                      onTap: () => setState(() => _mebRule = 'ilkogretim'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    AcademicChoicePill(
                      label: 'Uyarı Radarı (≥%30)',
                      compact: true,
                      selected: _filterMode == 'all_flagged',
                      accentColor: const Color(0xFFD97706),
                      onTap: () => setState(() => _filterMode = 'all_flagged'),
                    ),
                    AcademicChoicePill(
                      label: 'Kritik Sınırda (≥%70)',
                      compact: true,
                      selected: _filterMode == 'critical',
                      accentColor: const Color(0xFFDC2626),
                      onTap: () => setState(() => _filterMode = 'critical'),
                    ),
                    AcademicChoicePill(
                      label: '1. Ders Geç Kalma Örüntüsü',
                      compact: true,
                      selected: _filterMode == 'first_hour_late',
                      accentColor: const Color(0xFF7C3AED),
                      onTap: () =>
                          setState(() => _filterMode = 'first_hour_late'),
                    ),
                    AcademicChoicePill(
                      label: 'Tüm Öğrenciler',
                      compact: true,
                      selected: _filterMode == 'all',
                      accentColor: const Color(0xFF0284C7),
                      onTap: () => setState(() => _filterMode = 'all'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: isMobile ? double.infinity : 260,
                  child: AcademicDropdownField<String?>(
                    label: 'Sınıf Seçimi',
                    icon: Icons.class_rounded,
                    accentColor: const Color(0xFFE11D48),
                    value: _classId,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Tüm Sınıflar'),
                      ),
                      ...widget.dataset.classes.map(
                        (c) => DropdownMenuItem<String?>(
                          value: c.id,
                          child: Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _classId = v),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.radar_rounded,
                    size: 46,
                    color: Color(0xFF059669),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Bu eşikte devamsızlık uyarısına takılan öğrenci bulunmadı.',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _filterMode = 'all'),
                    child: const Text('Tüm Sınıf Yoklama Özetini Göster'),
                  ),
                ],
              ),
            )
          else
            ...items.map((item) {
              final pct = (item.ratio * 100).clamp(0.0, 100.0);
              final color = pct >= 75
                  ? const Color(0xFFDC2626)
                  : (pct >= 45
                        ? const Color(0xFFD97706)
                        : const Color(0xFF0284C7));

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${item.student.name} (${item.student.className})',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Sınır Doluluk: %${pct.toStringAsFixed(0)}',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: (pct / 100.0).clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: const Color(0xFFF1F5F9),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 14,
                      runSpacing: 6,
                      children: [
                        Text(
                          'Özürsüz: ${item.att.estimatedAbsentDays.toStringAsFixed(1)} / ${_unexcusedLimit.toStringAsFixed(0)} gün (${item.att.absentLessons} ders)',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF334155),
                          ),
                        ),
                        Text(
                          'Özürlü/İzinli: ${item.att.estimatedExcusedDays.toStringAsFixed(1)} gün',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: const Color(0xFF475569),
                          ),
                        ),
                        Text(
                          'Geç Kalma: ${item.att.lateLessons} ders (1. Ders: ${item.att.firstHourLateCount})',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: item.att.firstHourLateCount >= 2
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: item.att.firstHourLateCount >= 2
                                ? const Color(0xFFB45309)
                                : const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
