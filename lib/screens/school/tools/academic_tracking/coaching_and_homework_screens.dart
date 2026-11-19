import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../../widgets/edukn_app_bar.dart';
import '../../assessment/evaluation_models.dart';
import 'academic_tracking_models.dart';
import 'academic_ui_widgets.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// ARAÇ 5: BİREYSEL DENEME GELİŞİM & NET TREND KOÇU
/// ═══════════════════════════════════════════════════════════════════════════
class StudentTrialCoachScreen extends StatefulWidget {
  final AcademicDataset dataset;

  const StudentTrialCoachScreen({super.key, required this.dataset});

  @override
  State<StudentTrialCoachScreen> createState() =>
      _StudentTrialCoachScreenState();
}

class _StudentTrialCoachScreenState extends State<StudentTrialCoachScreen> {
  String? _classId;
  String? _studentId;
  bool _demoMode = false;

  @override
  void initState() {
    super.initState();
    // Varsayılan olarak deneme geçmişi olan ilk öğrenciyi seç
    for (final st in widget.dataset.students) {
      final h = widget.dataset.trialHistoryByStudent[st.id];
      if (h != null && h.isNotEmpty) {
        _studentId = st.id;
        _classId = st.classId;
        break;
      }
    }
    if (_studentId == null && widget.dataset.students.isNotEmpty) {
      _studentId = widget.dataset.students.first.id;
      _classId = widget.dataset.students.first.classId;
    }
    if (widget.dataset.trialHistoryByStudent.isEmpty) {
      _demoMode = true;
    }
  }

  List<StudentTrialPoint> get _activePoints {
    if (_demoMode) {
      return [
        StudentTrialPoint(
          examId: 'd1',
          examName: 'Türkiye Geneli Deneme-1',
          date: DateTime(2026, 9, 25),
          score: 382.4,
          totalNet: 64.33,
          totalCorrect: 69,
          totalWrong: 14,
          totalEmpty: 7,
          rankInstitution: 42,
          rankBranch: 9,
          subjects: {
            'Türkçe': SubjectStats(correct: 15, wrong: 3, empty: 2, net: 14.0),
            'Matematik': SubjectStats(
              correct: 11,
              wrong: 4,
              empty: 5,
              net: 9.67,
            ),
            'Fen Bilimleri': SubjectStats(
              correct: 15,
              wrong: 3,
              empty: 2,
              net: 14.0,
            ),
            'İnkılap': SubjectStats(correct: 9, wrong: 1, empty: 0, net: 8.67),
            'Din Kültürü': SubjectStats(
              correct: 10,
              wrong: 0,
              empty: 0,
              net: 10.0,
            ),
            'İngilizce': SubjectStats(correct: 9, wrong: 3, empty: 0, net: 8.0),
          },
        ),
        StudentTrialPoint(
          examId: 'd2',
          examName: 'Kurumsal İzleme-2',
          date: DateTime(2026, 10, 12),
          score: 404.8,
          totalNet: 69.67,
          totalCorrect: 73,
          totalWrong: 10,
          totalEmpty: 7,
          rankInstitution: 29,
          rankBranch: 6,
          subjects: {
            'Türkçe': SubjectStats(correct: 16, wrong: 3, empty: 1, net: 15.0),
            'Matematik': SubjectStats(
              correct: 13,
              wrong: 3,
              empty: 4,
              net: 12.0,
            ),
            'Fen Bilimleri': SubjectStats(
              correct: 16,
              wrong: 2,
              empty: 2,
              net: 15.33,
            ),
            'İnkılap': SubjectStats(correct: 9, wrong: 1, empty: 0, net: 8.67),
            'Din Kültürü': SubjectStats(
              correct: 10,
              wrong: 0,
              empty: 0,
              net: 10.0,
            ),
            'İngilizce': SubjectStats(
              correct: 9,
              wrong: 1,
              empty: 0,
              net: 8.67,
            ),
          },
        ),
        StudentTrialPoint(
          examId: 'd3',
          examName: 'Türkiye Geneli Deneme-3',
          date: DateTime(2026, 10, 29),
          score: 429.5,
          totalNet: 75.33,
          totalCorrect: 78,
          totalWrong: 8,
          totalEmpty: 4,
          rankInstitution: 16,
          rankBranch: 3,
          subjects: {
            'Türkçe': SubjectStats(correct: 18, wrong: 2, empty: 0, net: 17.33),
            'Matematik': SubjectStats(
              correct: 15,
              wrong: 3,
              empty: 2,
              net: 14.0,
            ),
            'Fen Bilimleri': SubjectStats(
              correct: 17,
              wrong: 2,
              empty: 1,
              net: 16.33,
            ),
            'İnkılap': SubjectStats(correct: 9, wrong: 1, empty: 0, net: 8.67),
            'Din Kültürü': SubjectStats(
              correct: 10,
              wrong: 0,
              empty: 0,
              net: 10.0,
            ),
            'İngilizce': SubjectStats(correct: 9, wrong: 0, empty: 1, net: 9.0),
          },
        ),
      ];
    }
    if (_studentId == null) return const [];
    return widget.dataset.trialHistoryByStudent[_studentId!] ?? const [];
  }

  AcademicStudentInfo? get _activeStudent {
    if (_studentId == null) return null;
    for (final s in widget.dataset.students) {
      if (s.id == _studentId) return s;
    }
    return null;
  }

  Future<void> _exportPdf() async {
    final pts = _activePoints;
    if (pts.isEmpty) return;
    final st = _activeStudent;
    final first = pts.first;
    final last = pts.last;
    final mixedQ = pts.map((p) => p.effectiveTotalQuestions).toSet().length > 1;
    final refQ = pts
        .where((p) => p.isFullTrial)
        .map((p) => p.effectiveTotalQuestions)
        .fold<int>(0, math.max);
    final scaleQ = refQ > 0 ? refQ : last.effectiveTotalQuestions;
    final deltaNet = mixedQ
        ? (last.netSuccessRate - first.netSuccessRate) * scaleQ
        : (last.totalNet - first.totalNet);

    await AcademicTrackingPdfService.printTableReport(
      documentTitle: 'BİREYSEL DENEME GELİŞİM VE AKADEMİK KOÇLUK KARNESİ',
      schoolName: widget.dataset.schoolName,
      subtitle: _demoMode
          ? 'Örnek Koçluk Simülasyonu Görünümü'
          : 'Öğrenci: ${st?.name ?? "-"} (${st?.className ?? "-"}) • Katıldığı Deneme: ${pts.length}',
      kpis: [
        (label: 'Son Deneme Puanı', value: last.score.toStringAsFixed(2)),
        (
          label: 'Son Toplam Net',
          value:
              '${last.totalNet.toStringAsFixed(2)} / ${last.effectiveTotalQuestions}S',
        ),
        (
          label: mixedQ ? 'Eşdeğer Net Gelişimi' : 'Net Gelişimi',
          value: mixedQ
              ? '${deltaNet >= 0 ? "+" : ""}${deltaNet.toStringAsFixed(2)} Net ($scaleQ S)'
              : '${deltaNet >= 0 ? "+" : ""}${deltaNet.toStringAsFixed(2)} Net',
        ),
        (
          label: 'Kurum Sıralaması',
          value: last.rankInstitution > 0 ? '#${last.rankInstitution}' : '-',
        ),
      ],
      headers: const [
        'Tarih',
        'Deneme Adı',
        'Doğru',
        'Yanlış',
        'Boş',
        'Toplam Net',
        'Puan',
        'Kurum Sıra',
      ],
      rows: pts.map((p) {
        return [
          DateFormat('dd.MM.yyyy').format(p.date),
          p.examName,
          '${p.totalCorrect}',
          '${p.totalWrong}',
          '${p.totalEmpty}',
          p.totalNet.toStringAsFixed(2),
          p.score.toStringAsFixed(2),
          p.rankInstitution > 0 ? '${p.rankInstitution}' : '-',
        ];
      }).toList(),
      notes: [_buildStrategyDiagnosis(last)],
    );
  }

  String _buildStrategyDiagnosis(StudentTrialPoint last) {
    final totQ = last.totalCorrect + last.totalWrong + last.totalEmpty;
    if (totQ == 0) return 'Soru dağılımı dengeli.';
    final wrongPct = (last.totalWrong / totQ) * 100;
    final emptyPct = (last.totalEmpty / totQ) * 100;
    if (wrongPct >= 14) {
      return 'Teşhis: Yüksek Yanlış Oranı (%${wrongPct.toStringAsFixed(1)}) — Emin olunmayan şıklarda risk alma eğilimi yüksek; turlama tekniği ve çeldirici analizi önerilir.';
    }
    if (emptyPct >= 15) {
      return 'Teşhis: Yüksek Boş Oranı (%${emptyPct.toStringAsFixed(1)}) — Süre yönetimi veya konu eksikliği kaynaklı boş bırakma; süreli branş denemeleri önerilir.';
    }
    return 'Teşhis: Dengeli Kodlama Stratejisi — Yanlış/boş dengesi kontrollü; en düşük netli branşa nokta atışı konu taraması yapılmalıdır.';
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 780;
    final pts = _activePoints;
    final filteredStudents = _classId == null
        ? widget.dataset.students
        : widget.dataset.students.where((s) => s.classId == _classId).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: EduknAppBar(
        title: 'Bireysel Deneme Gelişim & Net Koçu',
        subtitle: widget.dataset.schoolName,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton.icon(
              onPressed: pts.isEmpty ? null : _exportPdf,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
              label: Text(
                isMobile ? 'PDF' : 'Koçluk Karnesi PDF',
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
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 740;
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.dataset.classes.isNotEmpty) ...[
                        AcademicDropdownField<String?>(
                          label: 'Sınıf Filtresi',
                          icon: Icons.class_rounded,
                          accentColor: const Color(0xFF4F46E5),
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
                          onChanged: (v) {
                            setState(() {
                              _classId = v;
                              _demoMode = false;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (filteredStudents.isNotEmpty) ...[
                        AcademicDropdownField<String>(
                          label: 'Öğrenci Seçin',
                          icon: Icons.person_search_rounded,
                          accentColor: const Color(0xFF4F46E5),
                          value: filteredStudents.any((s) => s.id == _studentId)
                              ? _studentId
                              : filteredStudents.first.id,
                          items: filteredStudents
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s.id,
                                  child: Text(
                                    '${s.name} (${s.className})',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            setState(() {
                              _studentId = v;
                              _demoMode = false;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AcademicChoicePill(
                          icon: Icons.auto_graph_rounded,
                          label: 'Örnek Koçluk Trendi',
                          selected: _demoMode,
                          accentColor: const Color(0xFF4F46E5),
                          onTap: () => setState(() => _demoMode = !_demoMode),
                        ),
                      ),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (widget.dataset.classes.isNotEmpty) ...[
                      Expanded(
                        flex: 2,
                        child: AcademicDropdownField<String?>(
                          label: 'Sınıf Filtresi',
                          icon: Icons.class_rounded,
                          accentColor: const Color(0xFF4F46E5),
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
                          onChanged: (v) {
                            setState(() {
                              _classId = v;
                              _demoMode = false;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    if (filteredStudents.isNotEmpty) ...[
                      Expanded(
                        flex: 4,
                        child: AcademicDropdownField<String>(
                          label: 'Öğrenci Seçin',
                          icon: Icons.person_search_rounded,
                          accentColor: const Color(0xFF4F46E5),
                          value: filteredStudents.any((s) => s.id == _studentId)
                              ? _studentId
                              : filteredStudents.first.id,
                          items: filteredStudents
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s.id,
                                  child: Text(
                                    '${s.name} (${s.className})',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            setState(() {
                              _studentId = v;
                              _demoMode = false;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: AcademicChoicePill(
                        icon: Icons.auto_graph_rounded,
                        label: 'Örnek Koçluk Trendi',
                        selected: _demoMode,
                        accentColor: const Color(0xFF4F46E5),
                        onTap: () => setState(() => _demoMode = !_demoMode),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          if (pts.isEmpty)
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
                    Icons.insights_rounded,
                    size: 46,
                    color: Color(0xFF94A3B8),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Seçilen öğrencinin henüz kayıtlı deneme sınavı bulunmuyor.',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => setState(() => _demoMode = true),
                    icon: const Icon(Icons.play_circle_outline_rounded),
                    label: const Text('Örnek Koçluk Analizini İncele'),
                  ),
                ],
              ),
            )
          else ...[
            _buildTrendChartCard(pts),
            const SizedBox(height: 16),
            _buildDiagnosisCard(pts.last),
            const SizedBox(height: 16),
            _buildExamTableCard(pts),
          ],
        ],
      ),
    );
  }

  Widget _buildTrendChartCard(List<StudentTrialPoint> pts) {
    final first = pts.first;
    final last = pts.last;
    final distinctQCounts = pts
        .map((p) => p.effectiveTotalQuestions)
        .toSet()
        .length;
    final hasMixedQuestionCounts = distinctQCounts > 1;
    final refQ = pts
        .where((p) => p.isFullTrial)
        .map((p) => p.effectiveTotalQuestions)
        .fold<int>(0, math.max);
    final scaleQ = refQ > 0 ? refQ : last.effectiveTotalQuestions;
    final delta = hasMixedQuestionCounts
        ? (last.netSuccessRate - first.netSuccessRate) * scaleQ
        : (last.totalNet - first.totalNet);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ' Boylamsal Net & Puan Gelişim Grafiği (${pts.length} Deneme)',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    hasMixedQuestionCounts
                        ? 'Son Puan: ${last.score.toStringAsFixed(2)} • Son Net: ${last.totalNet.toStringAsFixed(2)}/${last.effectiveTotalQuestions}S (Grafik $scaleQ soru ölçeğine eşitlendi)'
                        : 'Son Puan: ${last.score.toStringAsFixed(2)} • Son Net: ${last.totalNet.toStringAsFixed(2)}/${last.effectiveTotalQuestions}S',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: delta >= 0
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  hasMixedQuestionCounts
                      ? '${delta >= 0 ? "+" : ""}${delta.toStringAsFixed(2)} Eşd. Net ($scaleQ S)'
                      : '${delta >= 0 ? "+" : ""}${delta.toStringAsFixed(2)} Net Değişim',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: delta >= 0
                        ? const Color(0xFF059669)
                        : const Color(0xFFDC2626),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 200,
            width: double.infinity,
            child: CustomPaint(
              painter: _NetTrendChartPainter(
                points: pts,
                scaleQuestions: hasMixedQuestionCounts ? scaleQ : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosisCard(StudentTrialPoint last) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEEF2FF), Color(0xFFF5F3FF)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC7D2FE)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.psychology_rounded,
            color: Color(0xFF4F46E5),
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _buildStrategyDiagnosis(last),
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1E1B4B),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExamTableCard(List<StudentTrialPoint> pts) {
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
          Text(
            'Deneme Geçmişi ve Sıralama Tablosu',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
              columns: const [
                DataColumn(label: Text('Tarih')),
                DataColumn(label: Text('Deneme Adı')),
                DataColumn(label: Text('D / Y / B')),
                DataColumn(label: Text('Net')),
                DataColumn(label: Text('Puan')),
                DataColumn(label: Text('Kurum Sırası')),
              ],
              rows: pts.reversed.map((p) {
                return DataRow(
                  cells: [
                    DataCell(Text(DateFormat('dd.MM.yyyy').format(p.date))),
                    DataCell(Text(p.examName)),
                    DataCell(
                      Text(
                        '${p.totalCorrect}D / ${p.totalWrong}Y / ${p.totalEmpty}B',
                      ),
                    ),
                    DataCell(
                      Text(
                        '${p.totalNet.toStringAsFixed(2)} / ${p.effectiveTotalQuestions}S',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    DataCell(Text(p.score.toStringAsFixed(2))),
                    DataCell(
                      Text(
                        p.rankInstitution > 0 ? '#${p.rankInstitution}' : '-',
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _NetTrendChartPainter extends CustomPainter {
  final List<StudentTrialPoint> points;
  final int? scaleQuestions;

  _NetTrendChartPainter({required this.points, this.scaleQuestions});

  double _valOf(StudentTrialPoint p) {
    if (scaleQuestions != null && scaleQuestions! > 0) {
      return p.netSuccessRate * scaleQuestions!;
    }
    return p.totalNet;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const padL = 38.0;
    const padR = 18.0;
    const padT = 22.0;
    const padB = 30.0;

    final chartW = math.max(10.0, size.width - padL - padR);
    final chartH = math.max(10.0, size.height - padT - padB);

    double minN = points.map(_valOf).reduce(math.min);
    double maxN = points.map(_valOf).reduce(math.max);
    if ((maxN - minN).abs() < 4) {
      minN = math.max(0, minN - 5);
      maxN += 5;
    } else {
      minN = math.max(0, minN - 3);
      maxN += 3;
    }

    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;

    for (int i = 0; i <= 3; i++) {
      final y = padT + (chartH * i / 3);
      canvas.drawLine(Offset(padL, y), Offset(size.width - padR, y), gridPaint);
      final val = maxN - ((maxN - minN) * i / 3);
      final tp = TextPainter(
        text: TextSpan(
          text: val.toStringAsFixed(0),
          style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(4, y - tp.height / 2));
    }

    final coords = <Offset>[];
    for (int i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? padL + chartW / 2
          : padL + (chartW * i / (points.length - 1));
      final norm = (_valOf(points[i]) - minN) / math.max(0.01, maxN - minN);
      final y = padT + chartH * (1.0 - norm);
      coords.add(Offset(x, y));
    }

    if (coords.length >= 2) {
      final fillPath = Path()..moveTo(coords.first.dx, padT + chartH);
      for (final c in coords) {
        fillPath.lineTo(c.dx, c.dy);
      }
      fillPath.lineTo(coords.last.dx, padT + chartH);
      fillPath.close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF4F46E5).withValues(alpha: 0.24),
            const Color(0xFF4F46E5).withValues(alpha: 0.01),
          ],
        ).createShader(Rect.fromLTWH(padL, padT, chartW, chartH));
      canvas.drawPath(fillPath, fillPaint);

      final linePath = Path()..moveTo(coords.first.dx, coords.first.dy);
      for (int i = 1; i < coords.length; i++) {
        linePath.lineTo(coords[i].dx, coords[i].dy);
      }
      final linePaint = Paint()
        ..color = const Color(0xFF4F46E5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(linePath, linePaint);
    }

    for (int i = 0; i < coords.length; i++) {
      final c = coords[i];
      canvas.drawCircle(c, 5.5, Paint()..color = Colors.white);
      canvas.drawCircle(c, 4.2, Paint()..color = const Color(0xFF4F46E5));

      final valTp = TextPainter(
        text: TextSpan(
          text: points[i].totalNet.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E1B4B),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      valTp.paint(canvas, Offset(c.dx - valTp.width / 2, c.dy - 18));

      final dateTp = TextPainter(
        text: TextSpan(
          text: DateFormat('dd/MM').format(points[i].date),
          style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      dateTp.paint(canvas, Offset(c.dx - dateTp.width / 2, padT + chartH + 8));
    }
  }

  @override
  bool shouldRepaint(covariant _NetTrendChartPainter oldDelegate) =>
      oldDelegate.points != points;
}

/// ═══════════════════════════════════════════════════════════════════════════
/// ARAÇ 6: ÖDEV DİSİPLİNİ & ETÜT VERİMLİLİK ANALİZİ
/// ═══════════════════════════════════════════════════════════════════════════
class HomeworkAndEtutAnalyticsScreen extends StatefulWidget {
  final AcademicDataset dataset;

  const HomeworkAndEtutAnalyticsScreen({super.key, required this.dataset});

  @override
  State<HomeworkAndEtutAnalyticsScreen> createState() =>
      _HomeworkAndEtutAnalyticsScreenState();
}

class _HomeworkAndEtutAnalyticsScreenState
    extends State<HomeworkAndEtutAnalyticsScreen> {
  int _tabIndex = 0; // 0: Ödev Analizi, 1: Etüt Verimliliği

  List<({AcademicStudentInfo student, StudentHomeworkSummary hw})>
  get _chronicMissingStudents {
    final list = <({AcademicStudentInfo student, StudentHomeworkSummary hw})>[];
    for (final s in widget.dataset.students) {
      final hw = widget.dataset.homeworkByStudent[s.id];
      if (hw != null && (hw.missingCount >= 1 || hw.incompleteCount >= 2)) {
        list.add((student: s, hw: hw));
      }
    }
    list.sort((a, b) => b.hw.missingCount.compareTo(a.hw.missingCount));
    return list;
  }

  Future<void> _exportPdf() async {
    final chronic = _chronicMissingStudents;
    await AcademicTrackingPdfService.printTableReport(
      documentTitle: 'ÖDEV DİSİPLİNİ VE ETÜT VERİMLİLİK ANALİZ RAPORU',
      schoolName: widget.dataset.schoolName,
      subtitle:
          'Sınıf bazlı ödev tamamlama oranları, kronik ödev eksiği olan öğrenciler ve etüt katılım özeti',
      kpis: [
        (
          label: 'Genel Ödev Oranı',
          value:
              '%${widget.dataset.overallHomeworkCompletionRate.toStringAsFixed(1)}',
        ),
        (label: 'Ödev Eksiği Olan', value: '${chronic.length} Öğrenci'),
        (
          label: 'Toplam Etüt Kaydı',
          value: '${widget.dataset.etutSummary.totalRequests}',
        ),
        (
          label: 'Etüt Tamamlanma',
          value:
              '%${widget.dataset.etutSummary.attendanceRate.toStringAsFixed(0)}',
        ),
      ],
      headers: const [
        'Öğrenci',
        'Sınıf',
        'Atanan Ödev',
        'Tam Yaptı',
        'Eksik',
        'Yapmadı',
        'Başarı Oranı',
      ],
      rows: chronic.take(50).map((c) {
        return [
          c.student.name,
          c.student.className,
          '${c.hw.assignedCount}',
          '${c.hw.doneCount}',
          '${c.hw.incompleteCount}',
          '${c.hw.missingCount}',
          '%${c.hw.completionRate.toStringAsFixed(0)}',
        ];
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 780;
    final chronic = _chronicMissingStudents;
    final etut = widget.dataset.etutSummary;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: EduknAppBar(
        title: 'Ödev Disiplini & Etüt Verimlilik Analizi',
        subtitle: widget.dataset.schoolName,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton.icon(
              onPressed: _exportPdf,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0D9488),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
              label: Text(
                isMobile ? 'PDF' : 'Ödev & Etüt Raporu PDF',
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
                  icon: Icons.menu_book_rounded,
                  label: 'Ödev Disiplini & Sınıf Sıralaması',
                  selected: _tabIndex == 0,
                  accentColor: const Color(0xFF0D9488),
                  onTap: () => setState(() => _tabIndex = 0),
                ),
                AcademicChoicePill(
                  icon: Icons.groups_2_rounded,
                  label: 'Etüt Verimlilik Analizi (${etut.totalRequests})',
                  selected: _tabIndex == 1,
                  accentColor: const Color(0xFF0D9488),
                  onTap: () => setState(() => _tabIndex = 1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_tabIndex == 0) ...[
            _buildHomeworkSection(chronic),
          ] else ...[
            _buildEtutSection(etut),
          ],
        ],
      ),
    );
  }

  Widget _buildHomeworkSection(
    List<({AcademicStudentInfo student, StudentHomeworkSummary hw})> chronic,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
              Text(
                'Sınıf Bazlı Ödev Tamamlama Performansı',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 12),
              if (widget.dataset.classHomeworkSummaries.isEmpty)
                Text(
                  'Henüz değerlendirilmiş sınıf ödev kaydı bulunmuyor.',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF64748B),
                    fontSize: 13,
                  ),
                )
              else
                ...widget.dataset.classHomeworkSummaries.map((c) {
                  final pct = c.completionRate.clamp(0.0, 100.0);
                  final color = pct < 60
                      ? const Color(0xFFDC2626)
                      : (pct < 80
                            ? const Color(0xFFD97706)
                            : const Color(0xFF059669));
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '${c.className} (${c.homeworkCount} Ödev)',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              '%${pct.toStringAsFixed(1)} • Tam: ${c.doneCount} | Eksik: ${c.incompleteCount} | Yapmadı: ${c.missingCount}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: pct / 100.0,
                            minHeight: 8,
                            backgroundColor: const Color(0xFFF1F5F9),
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
        const SizedBox(height: 16),
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
              Text(
                'Kronik Ödev Eksiği Olan Öğrenciler (${chronic.length})',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 12),
              if (chronic.isEmpty)
                Text(
                  'Eksik veya yapılmamış ödev kaydı olan öğrenci bulunmadı.',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF059669),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                )
              else
                ...chronic
                    .take(25)
                    .map(
                      (item) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFFEE2E2),
                          child: Text(
                            '${item.hw.missingCount}',
                            style: GoogleFonts.inter(
                              color: const Color(0xFFB91C1C),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        title: Text(
                          '${item.student.name} (${item.student.className})',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                        subtitle: Text(
                          'Yapmadı: ${item.hw.missingCount} • Eksik: ${item.hw.incompleteCount} • Yaptı: ${item.hw.doneCount}',
                          style: GoogleFonts.inter(fontSize: 12),
                        ),
                        trailing: Text(
                          '%${item.hw.completionRate.toStringAsFixed(0)}',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFFDC2626),
                          ),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEtutSection(EtutAnalyticsSummary etut) {
    final sortedSubjects = etut.bySubject.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

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
          LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final isMobileGrid = maxW < 680;
              final gap = isMobileGrid ? 10.0 : 14.0;
              final itemW = isMobileGrid
                  ? (maxW - gap) / 2
                  : (maxW - gap * 3) / 4;

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  _statBox(
                    'Toplam Etüt Talebi',
                    '${etut.totalRequests}',
                    width: itemW,
                  ),
                  _statBox(
                    'Tamamlanan Etüt',
                    '${etut.completedCount}',
                    width: itemW,
                  ),
                  _statBox(
                    'Bekleyen Etüt',
                    '${etut.pendingCount}',
                    width: itemW,
                  ),
                  _statBox(
                    'Verimlilik Oranı',
                    '%${etut.attendanceRate.toStringAsFixed(1)}',
                    width: itemW,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Text(
            'Branş Bazlı Etüt Yoğunluğu',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
            ),
          ),
          const SizedBox(height: 10),
          if (sortedSubjects.isEmpty)
            Text(
              'Henüz kayıtlı etüt talebi bulunmuyor.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF64748B),
              ),
            )
          else
            ...sortedSubjects.map(
              (e) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  e.key,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${e.value} Etüt',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF059669),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statBox(String label, String val, {required double width}) {
    final compact = width < 165;
    final valSize = (width * 0.115).clamp(16.5, 20.0);
    return SizedBox(
      width: width,
      child: Container(
        padding: EdgeInsets.all(compact ? 11 : 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: compact ? 10.6 : 11.5,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              val,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: valSize,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
