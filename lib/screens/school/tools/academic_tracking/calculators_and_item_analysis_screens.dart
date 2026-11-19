import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../widgets/edukn_app_bar.dart';
import 'academic_tracking_models.dart';
import 'academic_ui_widgets.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// ARAÇ 7: HIZLI TEST NOTU, ÇAN EĞRİSİ VE RUBRİK DÖNÜŞTÜRÜCÜ (3'Ü 1 ARADA)
/// ═══════════════════════════════════════════════════════════════════════════
class GradeConverterSuiteScreen extends StatefulWidget {
  final AcademicDataset dataset;

  const GradeConverterSuiteScreen({super.key, required this.dataset});

  @override
  State<GradeConverterSuiteScreen> createState() =>
      _GradeConverterSuiteScreenState();
}

class _GradeConverterSuiteScreenState extends State<GradeConverterSuiteScreen> {
  int _tab =
      0; // 0: Hızlı Test Anahtarı, 1: Çan Eğrisi & T-Skor, 2: MEB Açık Uçlu Rubrik

  // Tab 0 — Hızlı Test
  int _questionCount = 25;
  int _penaltyRatio = 0; // 0: Yok, 3: 3Y=1D, 4: 4Y=1D
  final double _basePoints = 0;
  int _quickCorrect = 21;
  int _quickWrong = 3;

  // Tab 1 — Çan Eğrisi
  late final TextEditingController _scoresController;
  String? _selectedClassExamId;

  // Tab 2 — MEB Açık Uçlu Yazılı Rubrik
  List<({String title, double maxPts, double earnedPts})> _rubricItems = [
    (title: '1. Soru (Kavram & Tanım)', maxPts: 15, earnedPts: 15),
    (title: '2. Soru (Problem Çözme)', maxPts: 20, earnedPts: 15),
    (title: '3. Soru (Veri Yorumlama)', maxPts: 20, earnedPts: 12),
    (title: '4. Soru (Analiz & Çıkarım)', maxPts: 25, earnedPts: 20),
    (title: '5. Soru (Özgün Uygulama)', maxPts: 20, earnedPts: 16),
  ];

  @override
  void initState() {
    super.initState();
    _scoresController = TextEditingController(
      text: '42, 48, 55, 58, 62, 65, 68, 70, 72, 74, 78, 82, 85, 88, 92',
    );
  }

  @override
  void dispose() {
    _scoresController.dispose();
    super.dispose();
  }

  double _computeTestScore(int correct, int wrong) {
    final c = correct.clamp(0, _questionCount);
    final w = wrong.clamp(0, _questionCount - c);
    final net = _penaltyRatio == 0
        ? c.toDouble()
        : math.max(0.0, c - (w / _penaltyRatio));
    final span = 100.0 - _basePoints;
    return (_basePoints + (net / _questionCount) * span).clamp(0.0, 100.0);
  }

  List<double> get _parsedCurveScores {
    final raw = _scoresController.text;
    final parts = raw.split(RegExp(r'[\s,;]+'));
    final out = <double>[];
    for (final p in parts) {
      final v = double.tryParse(p.trim());
      if (v != null && v >= 0 && v <= 100) out.add(v);
    }
    return out;
  }

  ({
    double mean,
    double stdDev,
    double median,
    double minVal,
    double maxVal,
    List<({double raw, double z, double t, double ceilingBoost, String letter})>
    items,
  })
  _computeCurveStats() {
    final scores = _parsedCurveScores;
    if (scores.isEmpty) {
      return (
        mean: 0,
        stdDev: 0,
        median: 0,
        minVal: 0,
        maxVal: 0,
        items: const [],
      );
    }
    final sorted = [...scores]..sort();
    final n = scores.length;
    final mean = scores.reduce((a, b) => a + b) / n;
    final variance =
        scores.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / n;
    final std = math.sqrt(variance);
    final median = n.isOdd
        ? sorted[n ~/ 2]
        : (sorted[(n ~/ 2) - 1] + sorted[n ~/ 2]) / 2.0;
    final maxV = sorted.last;
    final boost = math.max(0.0, 100.0 - maxV);

    String letterForT(double tScore, double raw) {
      if (raw >= 85 || tScore >= 62) return 'AA (Pekiyi - 5)';
      if (raw >= 75 || tScore >= 56) return 'BA (İyi-Pekiyi)';
      if (raw >= 65 || tScore >= 50) return 'BB (İyi - 4)';
      if (raw >= 55 || tScore >= 45) return 'CB (Orta-İyi)';
      if (raw >= 50 || tScore >= 40) return 'CC (Geçer - 3)';
      if (raw >= 42 || tScore >= 35) return 'DC (Şartlı)';
      return 'FF (Başarısız)';
    }

    final items = scores.map((raw) {
      final z = std < 0.001 ? 0.0 : (raw - mean) / std;
      final t = 50.0 + 10.0 * z;
      final boosted = (raw + boost).clamp(0.0, 100.0);
      return (
        raw: raw,
        z: z,
        t: t,
        ceilingBoost: boosted,
        letter: letterForT(t, raw),
      );
    }).toList();

    return (
      mean: mean,
      stdDev: std,
      median: median,
      minVal: sorted.first,
      maxVal: maxV,
      items: items,
    );
  }

  Future<void> _exportPdf() async {
    if (_tab == 0) {
      await AcademicTrackingPdfService.printTableReport(
        documentTitle:
            'HIZLI TEST PUAN ANAHTARI ÇİZELGESİ ($_questionCount SORU)',
        schoolName: widget.dataset.schoolName,
        subtitle: _penaltyRatio == 0
            ? 'Yanlış Doğruyu Götürmez • Taban Puan: ${_basePoints.toStringAsFixed(0)}'
            : '$_penaltyRatio Yanlış = 1 Doğru Götürür • Taban Puan: ${_basePoints.toStringAsFixed(0)}',
        kpis: [
          (label: 'Soru Sayısı', value: '$_questionCount Soru'),
          (
            label: 'Soru Başı Puan',
            value: ((100 - _basePoints) / _questionCount).toStringAsFixed(2),
          ),
        ],
        headers: const [
          'Doğru Sayısı',
          '0 Yanlış Puanı',
          '2 Yanlış Puanı',
          '4 Yanlış Puanı',
        ],
        rows: List.generate(_questionCount + 1, (idx) {
          final d = _questionCount - idx;
          return [
            '$d Doğru',
            _computeTestScore(d, 0).toStringAsFixed(1),
            d + 2 <= _questionCount
                ? _computeTestScore(d, 2).toStringAsFixed(1)
                : '-',
            d + 4 <= _questionCount
                ? _computeTestScore(d, 4).toStringAsFixed(1)
                : '-',
          ];
        }),
      );
    } else if (_tab == 1) {
      final st = _computeCurveStats();
      await AcademicTrackingPdfService.printTableReport(
        documentTitle: 'SINIF ÇAN EĞRİSİ, Z-SKOR VE BAĞIL ÖLÇEKLEME RAPORU',
        schoolName: widget.dataset.schoolName,
        subtitle: 'Sınıf istatistiksel dağılım ve tavan puan ölçekleme tablosu',
        kpis: [
          (label: 'Öğrenci Sayısı', value: '${st.items.length}'),
          (label: 'Aritmetik Ort.', value: st.mean.toStringAsFixed(2)),
          (label: 'Standart Sapma', value: st.stdDev.toStringAsFixed(2)),
          (label: 'Medyan', value: st.median.toStringAsFixed(1)),
        ],
        headers: const [
          '#',
          'Ham Not',
          'Z-Skor',
          'T-Skor',
          'Tavan=100 Notu',
          'Bağıl Derece',
        ],
        rows: List.generate(st.items.length, (i) {
          final it = st.items[i];
          return [
            '${i + 1}',
            it.raw.toStringAsFixed(1),
            it.z.toStringAsFixed(2),
            it.t.toStringAsFixed(1),
            it.ceilingBoost.toStringAsFixed(1),
            it.letter,
          ];
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 780;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: EduknAppBar(
        title: 'Test Notu, Çan Eğrisi & Rubrik Dönüştürücü',
        subtitle: widget.dataset.schoolName,
        actions: [
          if (_tab != 2)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: FilledButton.icon(
                onPressed: _exportPdf,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                label: Text(
                  isMobile ? 'PDF' : 'Tabloyu Yazdır PDF',
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
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                AcademicChoicePill(
                  icon: Icons.bolt_rounded,
                  label: 'Hızlı Test Not Anahtarı',
                  selected: _tab == 0,
                  accentColor: const Color(0xFF0284C7),
                  onTap: () => setState(() => _tab = 0),
                ),
                AcademicChoicePill(
                  icon: Icons.stacked_line_chart_rounded,
                  label: 'Çan Eğrisi & T-Skor Ölçekleme',
                  selected: _tab == 1,
                  accentColor: const Color(0xFF0284C7),
                  onTap: () => setState(() => _tab = 1),
                ),
                AcademicChoicePill(
                  icon: Icons.edit_note_rounded,
                  label: 'MEB Açık Uçlu Yazılı Rubrik',
                  selected: _tab == 2,
                  accentColor: const Color(0xFF0284C7),
                  onTap: () => setState(() => _tab = 2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_tab == 0)
            _buildQuickTestTab()
          else if (_tab == 1)
            _buildCurveTab(isMobile)
          else
            _buildRubricTab(),
        ],
      ),
    );
  }

  Widget _buildQuickTestTab() {
    final instantScore = _computeTestScore(_quickCorrect, _quickWrong);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
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
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      'Toplam Soru: $_questionCount',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  ...[10, 15, 20, 25, 30, 40, 50, 80, 100].map(
                    (q) => AcademicChoicePill(
                      label: '$q Soru',
                      compact: true,
                      selected: _questionCount == q,
                      accentColor: const Color(0xFF0284C7),
                      onTap: () {
                        setState(() {
                          _questionCount = q;
                          _quickCorrect = _quickCorrect.clamp(0, q);
                          _quickWrong = _quickWrong.clamp(0, q - _quickCorrect);
                        });
                      },
                    ),
                  ),
                ],
              ),
              Slider(
                value: _questionCount.toDouble(),
                min: 5,
                max: 120,
                divisions: 115,
                activeColor: const Color(0xFF0284C7),
                onChanged: (v) {
                  setState(() {
                    _questionCount = v.round();
                    _quickCorrect = _quickCorrect.clamp(0, _questionCount);
                    _quickWrong = _quickWrong.clamp(
                      0,
                      _questionCount - _quickCorrect,
                    );
                  });
                },
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  AcademicChoicePill(
                    label: 'Yanlış Götürmez',
                    compact: true,
                    selected: _penaltyRatio == 0,
                    accentColor: const Color(0xFF059669),
                    onTap: () => setState(() => _penaltyRatio = 0),
                  ),
                  AcademicChoicePill(
                    label: '3 Yanlış = 1 Doğru',
                    compact: true,
                    selected: _penaltyRatio == 3,
                    accentColor: const Color(0xFFD97706),
                    onTap: () => setState(() => _penaltyRatio = 3),
                  ),
                  AcademicChoicePill(
                    label: '4 Yanlış = 1 Doğru',
                    compact: true,
                    selected: _penaltyRatio == 4,
                    accentColor: const Color(0xFF4F46E5),
                    onTap: () => setState(() => _penaltyRatio = 4),
                  ),
                ],
              ),
              const Divider(height: 26),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0369A1), Color(0xFF0284C7)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Wrap(
                  spacing: 20,
                  runSpacing: 12,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Anlık Kağıt Hesaplayıcı: $_quickCorrect Doğru • $_quickWrong Yanlış',
                          style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '${instantScore.toStringAsFixed(1)} / 100 Puan (Yuvarlanmış: ${instantScore.round()})',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton.filledTonal(
                          onPressed: () {
                            setState(() {
                              _quickCorrect = (_quickCorrect - 1).clamp(
                                0,
                                _questionCount,
                              );
                            });
                          },
                          icon: const Icon(Icons.remove),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$_quickCorrect D',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filledTonal(
                          onPressed: () {
                            setState(() {
                              _quickCorrect = (_quickCorrect + 1).clamp(
                                0,
                                _questionCount - _quickWrong,
                              );
                            });
                          },
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_questionCount + 1, (i) {
              final d = _questionCount - i;
              final sc = _computeTestScore(d, 0);
              final pass = sc >= 50;
              return Container(
                width: 105,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: pass
                      ? const Color(0xFFF0FDF4)
                      : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: pass
                        ? const Color(0xFFBBF7D0)
                        : const Color(0xFFFECACA),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      '$d Doğru',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: const Color(0xFF475569),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      sc.toStringAsFixed(1),
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: pass
                            ? const Color(0xFF047857)
                            : const Color(0xFFB91C1C),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildCurveTab(bool isMobile) {
    final stats = _computeCurveStats();
    final validExams = widget.dataset.classExams
        .where((e) => e.grades.isNotEmpty)
        .toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (validExams.isNotEmpty) ...[
            AcademicDropdownField<String?>(
              label: 'Sistemdeki Yazılı Sınavdan Notları Otomatik Çek',
              trailingText: 'Opsiyonel',
              hint: 'Yazılı sınav seçin...',
              icon: Icons.assignment_turned_in_rounded,
              accentColor: const Color(0xFF0284C7),
              value: validExams.any((e) => e.id == _selectedClassExamId)
                  ? _selectedClassExamId
                  : null,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Manuel Not Girişi'),
                ),
                ...validExams.map(
                  (e) => DropdownMenuItem<String?>(
                    value: e.id,
                    child: Text(
                      '${e.className} • ${e.lessonName} — ${e.examName} (${e.grades.length} Not)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (val) {
                setState(() {
                  _selectedClassExamId = val;
                  final found = validExams
                      .where((e) => e.id == val)
                      .firstOrNull;
                  if (found != null) {
                    _scoresController.text = found.grades.values
                        .map((g) => g.toStringAsFixed(0))
                        .join(', ');
                  }
                });
              },
            ),
            const SizedBox(height: 14),
          ],
          AcademicTextField(
            controller: _scoresController,
            label: 'Sınıf Ham Notları',
            trailingText: 'Virgül veya boşlukla ayırın (0–100)',
            hint: 'Örn: 45, 52, 60, 68, 75, 84, 92',
            icon: Icons.calculate_rounded,
            accentColor: const Color(0xFF0284C7),
            maxLines: 3,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final isMobileGrid = maxW < 640;
              final gap = 10.0;
              final halfW = (maxW - gap) / 2;
              final webW = (maxW - gap * 4) / 5;
              final baseW = isMobileGrid ? halfW : webW;

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  _curvePill('Öğrenci', '${stats.items.length}', width: baseW),
                  _curvePill(
                    'Ortalama',
                    stats.mean.toStringAsFixed(2),
                    width: baseW,
                  ),
                  _curvePill(
                    'Std. Sapma',
                    stats.stdDev.toStringAsFixed(2),
                    width: baseW,
                  ),
                  _curvePill(
                    'Medyan',
                    stats.median.toStringAsFixed(1),
                    width: baseW,
                  ),
                  _curvePill(
                    'Min / Maks',
                    '${stats.minVal.toStringAsFixed(0)} – ${stats.maxVal.toStringAsFixed(0)}',
                    width: isMobileGrid ? maxW : baseW,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
              columns: const [
                DataColumn(label: Text('#')),
                DataColumn(label: Text('Ham Not')),
                DataColumn(label: Text('Z-Skor')),
                DataColumn(label: Text('T-Skor')),
                DataColumn(label: Text('Tavan=100 Ölçekli')),
                DataColumn(label: Text('Çan Eğrisi Derece')),
              ],
              rows: List.generate(stats.items.length, (i) {
                final it = stats.items[i];
                return DataRow(
                  cells: [
                    DataCell(Text('${i + 1}')),
                    DataCell(Text(it.raw.toStringAsFixed(1))),
                    DataCell(Text(it.z.toStringAsFixed(2))),
                    DataCell(Text(it.t.toStringAsFixed(1))),
                    DataCell(
                      Text(
                        it.ceilingBoost.toStringAsFixed(1),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    DataCell(Text(it.letter)),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRubricTab() {
    final maxTotal = _rubricItems.fold<double>(0, (sum, e) => sum + e.maxPts);
    final earnedTotal = _rubricItems.fold<double>(
      0,
      (sum, e) => sum + e.earnedPts,
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'MEB Açık Uçlu Yazılı Rubrik Puanlayıcı',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Toplam: ${earnedTotal.toStringAsFixed(0)} / ${maxTotal.toStringAsFixed(0)}',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: const Color(0xFF4F46E5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...List.generate(_rubricItems.length, (i) {
            final item = _rubricItems[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
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
                            item.title,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        Text(
                          '${item.earnedPts.toStringAsFixed(0)} / ${item.maxPts.toStringAsFixed(0)} Puan',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: item.earnedPts.clamp(0, item.maxPts),
                      min: 0,
                      max: item.maxPts,
                      divisions: item.maxPts.round(),
                      onChanged: (v) {
                        setState(() {
                          _rubricItems[i] = (
                            title: item.title,
                            maxPts: item.maxPts,
                            earnedPts: v,
                          );
                        });
                      },
                    ),
                  ],
                ),
              ),
            );
          }),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _rubricItems.add((
                      title: '${_rubricItems.length + 1}. Soru',
                      maxPts: 10,
                      earnedPts: 10,
                    ));
                  });
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Soru Ekle'),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _rubricItems = _rubricItems
                        .map(
                          (e) => (
                            title: e.title,
                            maxPts: e.maxPts,
                            earnedPts: 0.0,
                          ),
                        )
                        .toList();
                  });
                },
                child: const Text('Yeni Kağıt (Sıfırla)'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _curvePill(String k, String v, {required double width}) {
    final compact = width < 165;
    return SizedBox(
      width: width,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          '$k: $v',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: compact ? 11.6 : 12.5,
            color: const Color(0xFF1E293B),
          ),
        ),
      ),
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// ARAÇ 8: TEST & YAZILI MADDE ANALİZİ (p_j, r_jx, ÇELDİRİCİ) VE KR-20 GÜVENİRLİK
/// ═══════════════════════════════════════════════════════════════════════════
class ItemAnalysisToolScreen extends StatefulWidget {
  final AcademicDataset dataset;

  const ItemAnalysisToolScreen({super.key, required this.dataset});

  @override
  State<ItemAnalysisToolScreen> createState() => _ItemAnalysisToolScreenState();
}

class _ItemAnalysisToolScreenState extends State<ItemAnalysisToolScreen> {
  String? _selectedTrialId;
  String? _selectedSubject;
  bool _useDemo = false;

  @override
  void initState() {
    super.initState();
    if (widget.dataset.trialExams.isNotEmpty) {
      _selectedTrialId = widget.dataset.trialExams.first.id;
      final subs = _subjectsFor(_activeTrial);
      if (subs.isNotEmpty) _selectedSubject = subs.first;
    } else {
      _useDemo = true;
    }
  }

  ParsedTrialExam? get _activeTrial {
    for (final t in widget.dataset.trialExams) {
      if (t.id == _selectedTrialId) return t;
    }
    return widget.dataset.trialExams.firstOrNull;
  }

  List<String> _subjectsFor(ParsedTrialExam? t) {
    if (t == null) return const [];
    final s = <String>{};
    for (final b in t.exam.answerKeys.values) {
      s.addAll(b.keys);
    }
    for (final r in t.results) {
      s.addAll(r.answers.keys);
    }
    return s.toList();
  }

  ({
    String title,
    int studentCount,
    double kr20,
    double meanDifficulty,
    double meanDiscrimination,
    List<
      ({
        int qNo,
        String correctOpt,
        double pj,
        double rjx,
        Map<String, int> optCounts,
        String countsStr,
        String verdict,
      })
    >
    items,
  })
  _analyzeItems() {
    List<({String ans, String key})> responses = [];

    if (!_useDemo && _activeTrial != null) {
      final trial = _activeTrial!;
      final subs = _subjectsFor(trial);
      final subj = (_selectedSubject != null && subs.contains(_selectedSubject))
          ? _selectedSubject!
          : (subs.isNotEmpty ? subs.first : '');
      String fallbackKey = '';
      if (trial.exam.answerKeys.isNotEmpty) {
        final fb = trial.exam.answerKeys.keys.first;
        fallbackKey = trial.exam.answerKeys[fb]?[subj] ?? '';
      }

      for (final r in trial.results) {
        final a = r.answers[subj] ?? '';
        final k = r.correctAnswers[subj]?.isNotEmpty == true
            ? r.correctAnswers[subj]!
            : (trial.exam.answerKeys[r.booklet]?[subj] ?? fallbackKey);
        if (a.isNotEmpty && k.isNotEmpty) {
          responses.add((ans: a.toUpperCase(), key: k.toUpperCase()));
        }
      }
      if (responses.length >= 4) {
        return _runCtt('${trial.name} — $subj Branşı Madde Analizi', responses);
      }
      return (
        title:
            '${trial.name} — $subj Branşında Soru Bazlı Optik Şık (A/B/C/D) Verisi Kayıtlı Değil',
        studentCount: 0,
        kr20: 0,
        meanDifficulty: 0,
        meanDiscrimination: 0,
        items: const [],
      );
    }

    const sampleKey = 'ABCDABCDAB';
    const sampleAnswers = [
      'ABCDABCDAB',
      'ABCDABCDAC',
      'ABCDABCCAB',
      'ABCDABCDBB',
      'ABCCABCDAB',
      'ABCDABDDAB',
      'ABCDAACDAA',
      'ABBDABCCAC',
      'AACDABDCAC',
      'ABCDDBCCAD',
      'AACDBBCCAC',
      'BBCDACCCAD',
      'AACDDBCCBD',
      'BACDDCCCBD',
      'BBCDDCCCBD',
      'CBCDDCCDBD',
    ];
    responses = sampleAnswers.map((a) => (ans: a, key: sampleKey)).toList();
    return _runCtt(
      'Örnek Zümre Testi (10 Soru • 16 Öğrenci Klasik Test Kuramı Analizi)',
      responses,
    );
  }

  ({
    String title,
    int studentCount,
    double kr20,
    double meanDifficulty,
    double meanDiscrimination,
    List<
      ({
        int qNo,
        String correctOpt,
        double pj,
        double rjx,
        Map<String, int> optCounts,
        String countsStr,
        String verdict,
      })
    >
    items,
  })
  _runCtt(String title, List<({String ans, String key})> responses) {
    final kCount = responses.first.key.length;
    final n = responses.length;

    final scored = responses.map((r) {
      int total = 0;
      final itemBits = List<int>.filled(kCount, 0);
      for (int q = 0; q < kCount; q++) {
        if (q < r.ans.length && q < r.key.length && r.ans[q] == r.key[q]) {
          total++;
          itemBits[q] = 1;
        }
      }
      return (ans: r.ans, key: r.key, score: total, bits: itemBits);
    }).toList()..sort((a, b) => b.score.compareTo(a.score));

    final groupSize = math.max(1, (n * 0.27).round());
    final upper = scored.take(groupSize).toList();
    final lower = scored.skip(n - groupSize).toList();

    final meanTotal =
        scored.map((s) => s.score).reduce((a, b) => a + b) / n.toDouble();
    final varTotal =
        scored
            .map((s) => (s.score - meanTotal) * (s.score - meanTotal))
            .reduce((a, b) => a + b) /
        n.toDouble();

    double sumPq = 0;
    double sumPj = 0;
    double sumRjx = 0;

    final outItems =
        <
          ({
            int qNo,
            String correctOpt,
            double pj,
            double rjx,
            Map<String, int> optCounts,
            String countsStr,
            String verdict,
          })
        >[];

    for (int q = 0; q < kCount; q++) {
      final correctCount = scored.where((s) => s.bits[q] == 1).length;
      final pj = correctCount / n.toDouble();
      final qj = 1.0 - pj;
      sumPq += pj * qj;
      sumPj += pj;

      final upCorrect = upper.where((s) => s.bits[q] == 1).length;
      final lowCorrect = lower.where((s) => s.bits[q] == 1).length;
      final rjx = (upCorrect - lowCorrect) / groupSize.toDouble();
      sumRjx += rjx;

      final optCounts = <String, int>{'A': 0, 'B': 0, 'C': 0, 'D': 0, 'Boş': 0};
      for (final s in scored) {
        final ch = q < s.ans.length ? s.ans[q].trim() : '';
        if (optCounts.containsKey(ch)) {
          optCounts[ch] = optCounts[ch]! + 1;
        } else if (ch == 'E') {
          optCounts['E'] = (optCounts['E'] ?? 0) + 1;
        } else {
          optCounts['Boş'] = optCounts['Boş']! + 1;
        }
      }

      String verdict;
      if (rjx >= 0.40) {
        verdict = 'Çok İyi Ayırt Edici Madde';
      } else if (rjx >= 0.30) {
        verdict = 'İyi Madde (Aynen Kullanılabilir)';
      } else if (rjx >= 0.20) {
        verdict = 'Düzeltilerek Kullanılmalı';
      } else {
        verdict = 'Zayıf / Çeldiricisi Gözden Geçirilmeli';
      }

      outItems.add((
        qNo: q + 1,
        correctOpt: responses.first.key[q],
        pj: pj,
        rjx: rjx,
        optCounts: optCounts,
        countsStr: optCounts.entries
            .where((e) => e.value > 0)
            .map((e) => '${e.key}:${e.value}')
            .join('  '),
        verdict: verdict,
      ));
    }

    final kr20 = (kCount > 1 && varTotal > 0.0001)
        ? (kCount / (kCount - 1.0)) * (1.0 - (sumPq / varTotal))
        : 0.0;

    return (
      title: title,
      studentCount: n,
      kr20: kr20.clamp(0.0, 1.0),
      meanDifficulty: kCount == 0 ? 0 : sumPj / kCount,
      meanDiscrimination: kCount == 0 ? 0 : sumRjx / kCount,
      items: outItems,
    );
  }

  Future<void> _exportPdf() async {
    final res = _analyzeItems();
    await AcademicTrackingPdfService.printTableReport(
      documentTitle:
          'ZÜMRE MADDE ANALİZİ (GÜÇLÜK / AYIRT EDİCİLİK) VE KR-20 RAPORU',
      schoolName: widget.dataset.schoolName,
      subtitle: res.title,
      landscape: true,
      kpis: [
        (label: 'Öğrenci Sayısı', value: '${res.studentCount}'),
        (label: 'KR-20 Güvenirlik', value: res.kr20.toStringAsFixed(2)),
        (
          label: 'Ortalama Güçlük (p)',
          value: res.meanDifficulty.toStringAsFixed(2),
        ),
        (
          label: 'Ort. Ayırt Edicilik (r)',
          value: res.meanDiscrimination.toStringAsFixed(2),
        ),
      ],
      headers: const [
        'Soru',
        'Doğru Şık',
        'Güçlük (pj)',
        'Ayırt Edicilik (rjx)',
        'Şık Dağılımı',
        'Ölçme Değerlendirme Kararı',
      ],
      rows: res.items.map((it) {
        return [
          'Soru ${it.qNo}',
          it.correctOpt,
          it.pj.toStringAsFixed(2),
          it.rjx.toStringAsFixed(2),
          it.countsStr,
          it.verdict,
        ];
      }).toList(),
      notes: const [
        'KR-20 ≥ 0.70 ise sınav iç tutarlılığı ve güvenirliği yüksektir.',
        'Ayırt edicilik indeksi (rjx) 0.20 altında kalan maddeler soru havuzunda revize edilmelidir.',
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final isMobile = screenW < 820;
    final res = _analyzeItems();
    final subs = _subjectsFor(_activeTrial);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: EduknAppBar(
        title: 'Madde Analizi & KR-20 Güvenirlik',
        subtitle: widget.dataset.schoolName,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton.icon(
              onPressed: _exportPdf,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
              label: Text(
                isMobile ? 'PDF' : 'Zümre Madde Analizi PDF',
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
          // Üst Filtre & Kaynak Kartı (Sıfır piksel taşması garantili)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 740;
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.dataset.trialExams.isNotEmpty) ...[
                        AcademicDropdownField<String>(
                          label: 'Optik Deneme Sınavı',
                          icon: Icons.assignment_rounded,
                          accentColor: const Color(0xFF7C3AED),
                          value: _activeTrial?.id,
                          items: widget.dataset.trialExams
                              .map(
                                (t) => DropdownMenuItem(
                                  value: t.id,
                                  child: Text(
                                    t.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            setState(() {
                              _selectedTrialId = v;
                              _useDemo = false;
                              final s = _subjectsFor(_activeTrial);
                              _selectedSubject = s.isNotEmpty ? s.first : null;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (subs.isNotEmpty) ...[
                        AcademicDropdownField<String>(
                          label: 'Branş / Ders',
                          icon: Icons.menu_book_rounded,
                          accentColor: const Color(0xFF7C3AED),
                          value: subs.contains(_selectedSubject)
                              ? _selectedSubject
                              : subs.first,
                          items: subs
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(
                                    s,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            setState(() {
                              _selectedSubject = v;
                              _useDemo = false;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AcademicChoicePill(
                          icon: Icons.science_rounded,
                          label: 'Örnek Optik Veri Seti',
                          selected: _useDemo,
                          accentColor: const Color(0xFF7C3AED),
                          onTap: () => setState(() => _useDemo = !_useDemo),
                        ),
                      ),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (widget.dataset.trialExams.isNotEmpty) ...[
                      Expanded(
                        flex: 5,
                        child: AcademicDropdownField<String>(
                          label: 'Optik Deneme Sınavı',
                          icon: Icons.assignment_rounded,
                          accentColor: const Color(0xFF7C3AED),
                          value: _activeTrial?.id,
                          items: widget.dataset.trialExams
                              .map(
                                (t) => DropdownMenuItem(
                                  value: t.id,
                                  child: Text(
                                    t.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            setState(() {
                              _selectedTrialId = v;
                              _useDemo = false;
                              final s = _subjectsFor(_activeTrial);
                              _selectedSubject = s.isNotEmpty ? s.first : null;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    if (subs.isNotEmpty) ...[
                      Expanded(
                        flex: 3,
                        child: AcademicDropdownField<String>(
                          label: 'Branş / Ders',
                          icon: Icons.menu_book_rounded,
                          accentColor: const Color(0xFF7C3AED),
                          value: subs.contains(_selectedSubject)
                              ? _selectedSubject
                              : subs.first,
                          items: subs
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(
                                    s,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            setState(() {
                              _selectedSubject = v;
                              _useDemo = false;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: AcademicChoicePill(
                        icon: Icons.science_rounded,
                        label: 'Örnek Optik Veri Seti',
                        selected: _useDemo,
                        accentColor: const Color(0xFF7C3AED),
                        onTap: () => setState(() => _useDemo = !_useDemo),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // KPI Özet Kartları (Mobilde genişliğe göre hesaplanan 2x2 grid)
          LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final isMobileGrid = maxW < 720;
              final gap = maxW < 400 ? 8.0 : (isMobileGrid ? 10.0 : 12.0);
              final tileWidth = isMobileGrid
                  ? (maxW - gap) / 2
                  : (maxW - gap * 3) / 4;

              final kpis = [
                _kpiTile(
                  'KR-20 Güvenirlik',
                  res.kr20.toStringAsFixed(2),
                  res.kr20 >= 0.70 ? 'Yüksek İç Tutarlılık' : 'Orta Güvenirlik',
                  const Color(0xFF7C3AED),
                  Icons.verified_rounded,
                  tileWidth: tileWidth,
                ),
                _kpiTile(
                  'Ortalama Güçlük (pj)',
                  res.meanDifficulty.toStringAsFixed(2),
                  'İdeal: 0.45 – 0.60',
                  const Color(0xFF0284C7),
                  Icons.tune_rounded,
                  tileWidth: tileWidth,
                ),
                _kpiTile(
                  'Ort. Ayırt Edicilik (rjx)',
                  res.meanDiscrimination.toStringAsFixed(2),
                  'İdeal: ≥ 0.30',
                  const Color(0xFF059669),
                  Icons.insights_rounded,
                  tileWidth: tileWidth,
                ),
                _kpiTile(
                  'Analiz Edilen Kağıt',
                  '${res.studentCount} Öğrenci',
                  '%27 Üst / Alt Grup',
                  const Color(0xFF334155),
                  Icons.groups_rounded,
                  tileWidth: tileWidth,
                ),
              ];

              return Wrap(spacing: gap, runSpacing: gap, children: kpis);
            },
          ),
          const SizedBox(height: 16),

          // Madde Analizi Tablosu
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  res.title,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 15.5,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 14),
                if (res.items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'Bu sınavda yalnızca doğru/yanlış/net toplamları yüklü olup, öğrenci bazlı optik şık dizisi (A, B, C, D...) kayıtlı olmadığından çeldirici ve madde analizi üretilemedi. Optik form şık dizisi yüklü başka bir sınav seçebilirsiniz.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: const Color(0xFF64748B),
                        height: 1.45,
                      ),
                    ),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        const Color(0xFFF8FAFC),
                      ),
                      dataRowMinHeight: 50,
                      dataRowMaxHeight: 58,
                      columns: const [
                        DataColumn(label: Text('Soru')),
                        DataColumn(label: Text('Anahtar')),
                        DataColumn(label: Text('Güçlük (pj)')),
                        DataColumn(label: Text('Ayırt Edicilik (rjx)')),
                        DataColumn(label: Text('Çeldirici Dağılımı')),
                        DataColumn(label: Text('Madde Kararı')),
                      ],
                      rows: res.items.map((it) {
                        final verdictColor = it.rjx >= 0.40
                            ? const Color(0xFF059669)
                            : (it.rjx >= 0.30
                                  ? const Color(0xFF0284C7)
                                  : (it.rjx >= 0.20
                                        ? const Color(0xFFD97706)
                                        : const Color(0xFFDC2626)));

                        return DataRow(
                          cells: [
                            DataCell(
                              Text(
                                'S${it.qNo}',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF334155),
                                ),
                              ),
                            ),
                            DataCell(
                              Container(
                                width: 28,
                                height: 28,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFFA7F3D0),
                                  ),
                                ),
                                child: Text(
                                  it.correctOpt,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                    color: const Color(0xFF047857),
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                it.pj.toStringAsFixed(2),
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                it.rjx.toStringAsFixed(2),
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w800,
                                  color: verdictColor,
                                ),
                              ),
                            ),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: it.optCounts.entries
                                    .where((e) => e.value > 0)
                                    .map((e) {
                                      final isKey = e.key == it.correctOpt;
                                      return Container(
                                        margin: const EdgeInsets.only(right: 6),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 3.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isKey
                                              ? const Color(0xFFECFDF5)
                                              : const Color(0xFFF8FAFC),
                                          borderRadius: BorderRadius.circular(
                                            7,
                                          ),
                                          border: Border.all(
                                            color: isKey
                                                ? const Color(0xFF6EE7B7)
                                                : const Color(0xFFE2E8F0),
                                          ),
                                        ),
                                        child: Text(
                                          '${e.key}:${e.value}',
                                          style: GoogleFonts.inter(
                                            fontSize: 11.5,
                                            fontWeight: isKey
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                            color: isKey
                                                ? const Color(0xFF047857)
                                                : const Color(0xFF475569),
                                          ),
                                        ),
                                      );
                                    })
                                    .toList(),
                              ),
                            ),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: verdictColor.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  it.verdict,
                                  style: GoogleFonts.inter(
                                    fontSize: 11.8,
                                    fontWeight: FontWeight.w700,
                                    color: verdictColor,
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiTile(
    String title,
    String val,
    String sub,
    Color color,
    IconData icon, {
    required double tileWidth,
  }) {
    final isCompact = tileWidth < 185;
    final pad = isCompact ? 11.0 : 15.0;
    final valSize = (tileWidth * 0.105).clamp(15.5, 19.0);

    return SizedBox(
      width: tileWidth,
      child: Container(
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isCompact ? 15 : 18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: isCompact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(icon, color: color, size: 16),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 10.8,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    val,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: valSize,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 10.2,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11.8,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          val,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: valSize,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                        Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: const Color(0xFF64748B),
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
}
