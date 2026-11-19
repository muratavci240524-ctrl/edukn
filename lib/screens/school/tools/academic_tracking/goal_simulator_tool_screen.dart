import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../../../../widgets/edukn_app_bar.dart';
import 'academic_tracking_models.dart';
import 'academic_ui_widgets.dart';

class GoalSimulatorToolScreen extends StatefulWidget {
  final AcademicDataset dataset;

  const GoalSimulatorToolScreen({super.key, required this.dataset});

  @override
  State<GoalSimulatorToolScreen> createState() =>
      _GoalSimulatorToolScreenState();
}

class _GoalSimulatorToolScreenState extends State<GoalSimulatorToolScreen> {
  // 'LGS' veya 'YKS'
  String _examMode = 'LGS';
  String _lgsYear = '2026';
  double _lgsTargetScore = 455.0;

  // Öğrenciden otomatik çekme
  String? _selectedClassId;
  String? _selectedStudentId;

  // LGS Netleri (Doğru / Yanlış)
  final Map<String, ({int maxQ, int correct, int wrong})> _lgsInputs = {
    'Türkçe': (maxQ: 20, correct: 16, wrong: 2),
    'Matematik': (maxQ: 20, correct: 14, wrong: 2),
    'Fen Bilimleri': (maxQ: 20, correct: 16, wrong: 2),
    'T.C. İnkılap': (maxQ: 10, correct: 9, wrong: 1),
    'Din Kültürü': (maxQ: 10, correct: 9, wrong: 1),
    'Yabancı Dil': (maxQ: 10, correct: 8, wrong: 1),
  };

  // YKS Alan ve OBP
  String _yksField = 'SAY'; // SAY, EA, SOZ, DIL
  double _diplomaGrade = 88.0;
  bool _brokenObp = false;
  double _yksTargetScore = 485.0;

  // YKS Netleri
  final Map<String, ({int maxQ, double net})> _yksNets = {
    'TYT Türkçe': (maxQ: 40, net: 31.0),
    'TYT Sosyal': (maxQ: 20, net: 15.0),
    'TYT Matematik': (maxQ: 40, net: 27.5),
    'TYT Fen': (maxQ: 20, net: 14.0),
    'AYT Matematik': (maxQ: 40, net: 29.0),
    'AYT Fizik': (maxQ: 14, net: 10.0),
    'AYT Kimya': (maxQ: 13, net: 10.5),
    'AYT Biyoloji': (maxQ: 13, net: 10.5),
    'AYT Edebiyat-Sos1': (maxQ: 40, net: 28.0),
    'AYT Sosyal-2': (maxQ: 40, net: 26.0),
    'YDT Yabancı Dil': (maxQ: 80, net: 64.0),
  };

  double _lgsNetOf(String key) {
    final v = _lgsInputs[key]!;
    return (v.correct - (v.wrong / 3.0)).clamp(0.0, v.maxQ.toDouble());
  }

  void _setLgsCorrectWrong(String key, int correct, int wrong) {
    final maxQ = _lgsInputs[key]!.maxQ;
    final c = correct.clamp(0, maxQ);
    final w = wrong.clamp(0, maxQ - c);
    setState(() {
      _lgsInputs[key] = (maxQ: maxQ, correct: c, wrong: w);
    });
  }

  void _applyPreset(String preset) {
    setState(() {
      if (preset == 'zirve_fen') {
        _examMode = 'LGS';
        _lgsTargetScore = 490;
        _lgsInputs['Türkçe'] = (maxQ: 20, correct: 19, wrong: 1);
        _lgsInputs['Matematik'] = (maxQ: 20, correct: 19, wrong: 0);
        _lgsInputs['Fen Bilimleri'] = (maxQ: 20, correct: 19, wrong: 1);
        _lgsInputs['T.C. İnkılap'] = (maxQ: 10, correct: 10, wrong: 0);
        _lgsInputs['Din Kültürü'] = (maxQ: 10, correct: 10, wrong: 0);
        _lgsInputs['Yabancı Dil'] = (maxQ: 10, correct: 10, wrong: 0);
      } else if (preset == 'nitelikli_anadolu') {
        _examMode = 'LGS';
        _lgsTargetScore = 445;
        _lgsInputs['Türkçe'] = (maxQ: 20, correct: 17, wrong: 2);
        _lgsInputs['Matematik'] = (maxQ: 20, correct: 14, wrong: 2);
        _lgsInputs['Fen Bilimleri'] = (maxQ: 20, correct: 16, wrong: 2);
        _lgsInputs['T.C. İnkılap'] = (maxQ: 10, correct: 9, wrong: 1);
        _lgsInputs['Din Kültürü'] = (maxQ: 10, correct: 9, wrong: 1);
        _lgsInputs['Yabancı Dil'] = (maxQ: 10, correct: 8, wrong: 1);
      } else if (preset == 'yks_tip') {
        _examMode = 'YKS';
        _yksField = 'SAY';
        _diplomaGrade = 95;
        _yksTargetScore = 525;
        _yksNets['TYT Türkçe'] = (maxQ: 40, net: 35.5);
        _yksNets['TYT Sosyal'] = (maxQ: 20, net: 17.0);
        _yksNets['TYT Matematik'] = (maxQ: 40, net: 36.5);
        _yksNets['TYT Fen'] = (maxQ: 20, net: 18.0);
        _yksNets['AYT Matematik'] = (maxQ: 40, net: 37.5);
        _yksNets['AYT Fizik'] = (maxQ: 14, net: 12.5);
        _yksNets['AYT Kimya'] = (maxQ: 13, net: 12.0);
        _yksNets['AYT Biyoloji'] = (maxQ: 13, net: 12.0);
      } else if (preset == 'yks_hukuk') {
        _examMode = 'YKS';
        _yksField = 'EA';
        _diplomaGrade = 91;
        _yksTargetScore = 475;
        _yksNets['TYT Türkçe'] = (maxQ: 40, net: 34.0);
        _yksNets['TYT Sosyal'] = (maxQ: 20, net: 16.5);
        _yksNets['TYT Matematik'] = (maxQ: 40, net: 27.0);
        _yksNets['TYT Fen'] = (maxQ: 20, net: 9.0);
        _yksNets['AYT Matematik'] = (maxQ: 40, net: 29.0);
        _yksNets['AYT Edebiyat-Sos1'] = (maxQ: 40, net: 33.5);
      }
    });
  }

  void _pullStudentLatestTrial(String studentId) {
    final hist = widget.dataset.trialHistoryByStudent[studentId];
    if (hist == null || hist.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Seçilen öğrencinin sistemde eşleşmiş deneme sonucu bulunamadı; manuel simülasyon yapabilirsiniz.',
            style: GoogleFonts.inter(fontSize: 13),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final latest = hist.last;
    setState(() {
      if (_examMode == 'LGS') {
        void mapSubj(String targetKey, List<String> keywords) {
          for (final entry in latest.subjects.entries) {
            final k = AcademicTrackingDataService.normTr(entry.key);
            if (keywords.any((kw) => k.contains(kw))) {
              final maxQ = _lgsInputs[targetKey]!.maxQ;
              final c = entry.value.correct.clamp(0, maxQ);
              final w = entry.value.wrong.clamp(0, maxQ - c);
              _lgsInputs[targetKey] = (maxQ: maxQ, correct: c, wrong: w);
              return;
            }
          }
        }

        mapSubj('Türkçe', ['turk', 'türk']);
        mapSubj('Matematik', ['mat']);
        mapSubj('Fen Bilimleri', ['fen']);
        mapSubj('T.C. İnkılap', ['ink', 'tarih', 'sos']);
        mapSubj('Din Kültürü', ['din', 'ahlak']);
        mapSubj('Yabancı Dil', ['ing', 'yabanc', 'dil']);
      } else {
        for (final entry in latest.subjects.entries) {
          final k = AcademicTrackingDataService.normTr(entry.key);
          final n = entry.value.net;
          if (k.contains('tyt') && k.contains('turk')) {
            _yksNets['TYT Türkçe'] = (maxQ: 40, net: n.clamp(0, 40));
          } else if (k.contains('tyt') && k.contains('mat')) {
            _yksNets['TYT Matematik'] = (maxQ: 40, net: n.clamp(0, 40));
          } else if (k.contains('mat')) {
            _yksNets['AYT Matematik'] = (maxQ: 40, net: n.clamp(0, 40));
          } else if (k.contains('fiz')) {
            _yksNets['AYT Fizik'] = (maxQ: 14, net: n.clamp(0, 14));
          } else if (k.contains('kim')) {
            _yksNets['AYT Kimya'] = (maxQ: 13, net: n.clamp(0, 13));
          } else if (k.contains('biyo')) {
            _yksNets['AYT Biyoloji'] = (maxQ: 13, net: n.clamp(0, 13));
          } else if (k.contains('edeb')) {
            _yksNets['AYT Edebiyat-Sos1'] = (maxQ: 40, net: n.clamp(0, 40));
          }
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '"${latest.examName}" denemesindeki öğrenci netleri simülatöre aktarıldı.',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _exportPdf() async {
    AcademicStudentInfo? selectedSt;
    if (_selectedStudentId != null) {
      for (final s in widget.dataset.students) {
        if (s.id == _selectedStudentId) {
          selectedSt = s;
          break;
        }
      }
    }

    if (_examMode == 'LGS') {
      final res = AcademicScoreEngine.calculateLgs(
        turkceNet: _lgsNetOf('Türkçe'),
        matNet: _lgsNetOf('Matematik'),
        fenNet: _lgsNetOf('Fen Bilimleri'),
        inkilapNet: _lgsNetOf('T.C. İnkılap'),
        dinNet: _lgsNetOf('Din Kültürü'),
        ingNet: _lgsNetOf('Yabancı Dil'),
        referenceYear: _lgsYear,
      );
      final recipe = AcademicScoreEngine.suggestLgsNetRecipe(
        currentScore: res.score,
        targetScore: _lgsTargetScore,
        turkceNet: _lgsNetOf('Türkçe'),
        matNet: _lgsNetOf('Matematik'),
        fenNet: _lgsNetOf('Fen Bilimleri'),
        inkilapNet: _lgsNetOf('T.C. İnkılap'),
        dinNet: _lgsNetOf('Din Kültürü'),
        ingNet: _lgsNetOf('Yabancı Dil'),
      );

      await AcademicTrackingPdfService.printTableReport(
        documentTitle: 'LGS PUAN, YÜZDELİK DİLİM VE HEDEF REÇETE RAPORU',
        schoolName: widget.dataset.schoolName,
        subtitle: selectedSt != null
            ? 'Öğrenci: ${selectedSt.name} (${selectedSt.className}) • Referans Yıl: $_lgsYear MEB Dağılımı'
            : 'Bireysel Hedef Simülasyon Raporu • Referans Yıl: $_lgsYear MEB Dağılımı',
        kpis: [
          (label: 'Hesaplanan Puan', value: res.score.toStringAsFixed(2)),
          (
            label: 'Toplam Net',
            value: '${res.totalNet.toStringAsFixed(2)} / 90',
          ),
          (
            label: 'Tahmini Yüzdelik',
            value: '%${res.percentile.toStringAsFixed(2)}',
          ),
          (label: 'Hedef Puan', value: _lgsTargetScore.toStringAsFixed(0)),
        ],
        headers: const [
          'Branş',
          'Soru',
          'Doğru',
          'Yanlış',
          'Boş',
          'Net',
          'Katsayı',
        ],
        rows: _lgsInputs.entries.map((e) {
          final v = e.value;
          final empty = v.maxQ - v.correct - v.wrong;
          final net = _lgsNetOf(e.key);
          final coef = v.maxQ == 20 ? '4x (Ana Ders)' : '1x';
          return [
            e.key,
            '${v.maxQ}',
            '${v.correct}',
            '${v.wrong}',
            '$empty',
            net.toStringAsFixed(2),
            coef,
          ];
        }).toList(),
        notes: ['Yerleşme Bandı: ${res.targetTierLabel}', ...recipe],
      );
    } else {
      final res = AcademicScoreEngine.calculateYks(
        fieldType: _yksField,
        diplomaGrade: _diplomaGrade,
        brokenObp: _brokenObp,
        tytTurkce: _yksNets['TYT Türkçe']!.net,
        tytSosyal: _yksNets['TYT Sosyal']!.net,
        tytMat: _yksNets['TYT Matematik']!.net,
        tytFen: _yksNets['TYT Fen']!.net,
        aytMat: _yksNets['AYT Matematik']!.net,
        aytFizik: _yksNets['AYT Fizik']!.net,
        aytKimya: _yksNets['AYT Kimya']!.net,
        aytBiyoloji: _yksNets['AYT Biyoloji']!.net,
        aytEdebiyatSos1: _yksNets['AYT Edebiyat-Sos1']!.net,
        aytSos2: _yksNets['AYT Sosyal-2']!.net,
        ydtDil: _yksNets['YDT Yabancı Dil']!.net,
      );

      await AcademicTrackingPdfService.printTableReport(
        documentTitle:
            'YKS ($_yksField) PUAN, SIRALAMA VE OBP SİMÜLASYON RAPORU',
        schoolName: widget.dataset.schoolName,
        subtitle: selectedSt != null
            ? 'Öğrenci: ${selectedSt.name} (${selectedSt.className}) • Diploma Notu: ${_diplomaGrade.toStringAsFixed(1)}'
            : 'YKS Alan: $_yksField • Diploma Notu: ${_diplomaGrade.toStringAsFixed(1)}',
        kpis: [
          (
            label: '$_yksField Yerleştirme',
            value: res.aytYerlestirme.toStringAsFixed(2),
          ),
          (
            label: 'Tahmini $_yksField Sıralama',
            value: NumberFormat('#,###', 'tr_TR').format(res.aytRank),
          ),
          (
            label: 'TYT Yerleştirme',
            value: res.tytYerlestirme.toStringAsFixed(2),
          ),
          (
            label: 'OBP Katkısı',
            value: '+${res.obpContribution.toStringAsFixed(2)} Puan',
          ),
        ],
        headers: const [
          'Test / Branş',
          'Soru Sayısı',
          'Girilen Net',
          'Başarı %',
        ],
        rows: _visibleYksKeys.map((k) {
          final v = _yksNets[k]!;
          final pct = (v.net / v.maxQ) * 100.0;
          return [
            k,
            '${v.maxQ}',
            v.net.toStringAsFixed(2),
            '%${pct.toStringAsFixed(0)}',
          ];
        }).toList(),
        notes: [
          'Tahmini Yerleşme Bandı: ${res.targetBand}',
          'Hedef Puan: ${_yksTargetScore.toStringAsFixed(0)} (${(res.aytYerlestirme >= _yksTargetScore) ? "Hedef yakalandı" : "${(_yksTargetScore - res.aytYerlestirme).toStringAsFixed(1)} puan artış gerekiyor"})',
        ],
      );
    }
  }

  List<String> get _visibleYksKeys {
    final base = ['TYT Türkçe', 'TYT Sosyal', 'TYT Matematik', 'TYT Fen'];
    if (_yksField == 'SAY') {
      return [
        ...base,
        'AYT Matematik',
        'AYT Fizik',
        'AYT Kimya',
        'AYT Biyoloji',
      ];
    } else if (_yksField == 'EA') {
      return [...base, 'AYT Matematik', 'AYT Edebiyat-Sos1'];
    } else if (_yksField == 'SOZ') {
      return [...base, 'AYT Edebiyat-Sos1', 'AYT Sosyal-2'];
    } else {
      return [...base, 'YDT Yabancı Dil'];
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 820;

    final filteredStudents = _selectedClassId == null
        ? widget.dataset.students
        : widget.dataset.students
              .where((s) => s.classId == _selectedClassId)
              .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: EduknAppBar(
        title: 'LGS & YKS Hedef ve Tercih Simülatörü',
        subtitle: widget.dataset.schoolName,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton.icon(
              onPressed: _exportPdf,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
              label: Text(
                isMobile ? 'PDF' : 'Hedef Reçetesi PDF',
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
          _buildTopToolbar(isMobile, filteredStudents),
          const SizedBox(height: 16),
          if (_examMode == 'LGS')
            _buildLgsWorkspace(isMobile)
          else
            _buildYksWorkspace(isMobile),
        ],
      ),
    );
  }

  Widget _buildTopToolbar(
    bool isMobile,
    List<AcademicStudentInfo> filteredStudents,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _modeChip(
                'LGS',
                'LGS (8. Sınıf • 500 Puan)',
                Icons.school_rounded,
              ),
              _modeChip(
                'YKS',
                'YKS (TYT + AYT + OBP)',
                Icons.workspace_premium_rounded,
              ),
              const SizedBox(width: 8),
              _presetButton('Fen Lisesi (%1)', () => _applyPreset('zirve_fen')),
              _presetButton(
                'Proje Anadolu (%5)',
                () => _applyPreset('nitelikli_anadolu'),
              ),
              _presetButton('YKS Tıp / İlk 5K', () => _applyPreset('yks_tip')),
              _presetButton('YKS Hukuk / EA', () => _applyPreset('yks_hukuk')),
            ],
          ),
          if (widget.dataset.students.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 740;
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AcademicDropdownField<String?>(
                        label: 'Öğrenci Sınıfı',
                        trailingText: 'Netleri otomatik çek',
                        icon: Icons.class_rounded,
                        accentColor: const Color(0xFF059669),
                        value: _selectedClassId,
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
                        onChanged: (val) {
                          setState(() {
                            _selectedClassId = val;
                            _selectedStudentId = null;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      AcademicDropdownField<String?>(
                        label: 'Öğrenci Denemesinden Net Çek',
                        hint: 'Öğrenci seçin...',
                        icon: Icons.auto_fix_high_rounded,
                        accentColor: const Color(0xFF059669),
                        value:
                            filteredStudents.any(
                              (s) => s.id == _selectedStudentId,
                            )
                            ? _selectedStudentId
                            : null,
                        items: filteredStudents
                            .map(
                              (s) => DropdownMenuItem<String?>(
                                value: s.id,
                                child: Text(
                                  '${s.name} (${s.className})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          setState(() => _selectedStudentId = val);
                          if (val != null) _pullStudentLatestTrial(val);
                        },
                      ),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      flex: 2,
                      child: AcademicDropdownField<String?>(
                        label: 'Öğrenci Sınıfı',
                        icon: Icons.class_rounded,
                        accentColor: const Color(0xFF059669),
                        value: _selectedClassId,
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
                        onChanged: (val) {
                          setState(() {
                            _selectedClassId = val;
                            _selectedStudentId = null;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 4,
                      child: AcademicDropdownField<String?>(
                        label: 'Öğrenci Denemesinden Otomatik Net Çek',
                        hint: 'Öğrenci seçin...',
                        icon: Icons.auto_fix_high_rounded,
                        accentColor: const Color(0xFF059669),
                        value:
                            filteredStudents.any(
                              (s) => s.id == _selectedStudentId,
                            )
                            ? _selectedStudentId
                            : null,
                        items: filteredStudents
                            .map(
                              (s) => DropdownMenuItem<String?>(
                                value: s.id,
                                child: Text(
                                  '${s.name} (${s.className})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          setState(() => _selectedStudentId = val);
                          if (val != null) _pullStudentLatestTrial(val);
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _modeChip(String key, String label, IconData icon) {
    final selected = _examMode == key;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _examMode = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFF059669), Color(0xFF0D9488)],
                )
              : null,
          color: selected ? null : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? Colors.white : const Color(0xFF475569),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetButton(String label, VoidCallback onTap) {
    return ActionChip(
      onPressed: onTap,
      avatar: const Icon(
        Icons.bolt_rounded,
        size: 16,
        color: Color(0xFFD97706),
      ),
      label: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF334155),
        ),
      ),
      backgroundColor: const Color(0xFFFFFBEB),
      side: const BorderSide(color: Color(0xFFFDE68A)),
    );
  }

  Widget _buildLgsWorkspace(bool isMobile) {
    final calc = AcademicScoreEngine.calculateLgs(
      turkceNet: _lgsNetOf('Türkçe'),
      matNet: _lgsNetOf('Matematik'),
      fenNet: _lgsNetOf('Fen Bilimleri'),
      inkilapNet: _lgsNetOf('T.C. İnkılap'),
      dinNet: _lgsNetOf('Din Kültürü'),
      ingNet: _lgsNetOf('Yabancı Dil'),
      referenceYear: _lgsYear,
    );

    final recipe = AcademicScoreEngine.suggestLgsNetRecipe(
      currentScore: calc.score,
      targetScore: _lgsTargetScore,
      turkceNet: _lgsNetOf('Türkçe'),
      matNet: _lgsNetOf('Matematik'),
      fenNet: _lgsNetOf('Fen Bilimleri'),
      inkilapNet: _lgsNetOf('T.C. İnkılap'),
      dinNet: _lgsNetOf('Din Kültürü'),
      ingNet: _lgsNetOf('Yabancı Dil'),
    );

    final heroPanel = Column(
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF064E3B), Color(0xFF059669), Color(0xFF0D9488)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF059669).withValues(alpha: 0.28),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'MEB $_lgsYear Kalibre Dağılımı',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _lgsYear,
                      dropdownColor: const Color(0xFF064E3B),
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                      iconEnabledColor: Colors.white,
                      items: const ['2026', '2025', '2024']
                          .map(
                            (y) => DropdownMenuItem(
                              value: y,
                              child: Text('Ref: $y'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _lgsYear = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    calc.score.toStringAsFixed(2),
                    style: GoogleFonts.inter(
                      fontSize: 42,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      '/ 500 Puan',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final gap = 10.0;
                  final isTwoCols = constraints.maxWidth < 520;
                  final cellW = isTwoCols
                      ? (constraints.maxWidth - gap) / 2
                      : (constraints.maxWidth - gap * 3) / 4;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      _heroMetricBox(
                        'Tahmini Yüzdelik',
                        '%${calc.percentile.toStringAsFixed(2)}',
                        width: cellW,
                      ),
                      _heroMetricBox(
                        'Toplam Net',
                        '${calc.totalNet.toStringAsFixed(2)} / 90',
                        width: cellW,
                      ),
                      _heroMetricBox(
                        'Tahmini Sıralama',
                        '~${NumberFormat('#,###', 'tr_TR').format(calc.estimatedRank)}',
                        width: cellW,
                      ),
                      _heroMetricBox(
                        'Hedef Puan',
                        _lgsTargetScore.toStringAsFixed(0),
                        width: cellW,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.emoji_events_rounded,
                      color: Color(0xFFFDE68A),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        calc.targetTierLabel,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Hedef Puan & Net Artış Reçetesi',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Hedef: ${_lgsTargetScore.toStringAsFixed(0)} Puan',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF4F46E5),
                      ),
                    ),
                  ),
                ],
              ),
              Slider(
                value: _lgsTargetScore,
                min: 280,
                max: 500,
                divisions: 220,
                activeColor: const Color(0xFF4F46E5),
                onChanged: (v) => setState(() => _lgsTargetScore = v),
              ),
              const SizedBox(height: 6),
              ...recipe.map(
                (step) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: Color(0xFF059669),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          step,
                          style: GoogleFonts.inter(
                            fontSize: 12.8,
                            color: const Color(0xFF334155),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final inputsPanel = Container(
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
            'LGS Branş Doğru / Yanlış Simülasyonu (3 Yanlış = 1 Doğru)',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ana dersler (Türkçe, Matematik, Fen) 4x katsayı, ara dersler 1x katsayı ile hesaplanır.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 14),
          ..._lgsInputs.entries.map((entry) {
            final name = entry.key;
            final val = entry.value;
            final net = _lgsNetOf(name);
            final isMain = val.maxQ == 20;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isMain
                      ? const Color(0xFFA7F3D0)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              name,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isMain
                                    ? const Color(0xFFECFDF5)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isMain ? '4x Katsayı' : '1x Katsayı',
                                style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: isMain
                                      ? const Color(0xFF059669)
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${net.toStringAsFixed(2)} Net',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: const Color(0xFF059669),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 14,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _stepperPill(
                        label: 'Doğru',
                        value: val.correct,
                        color: const Color(0xFF059669),
                        onMinus: () => _setLgsCorrectWrong(
                          name,
                          val.correct - 1,
                          val.wrong,
                        ),
                        onPlus: () => _setLgsCorrectWrong(
                          name,
                          val.correct + 1,
                          val.wrong,
                        ),
                      ),
                      _stepperPill(
                        label: 'Yanlış',
                        value: val.wrong,
                        color: const Color(0xFFDC2626),
                        onMinus: () => _setLgsCorrectWrong(
                          name,
                          val.correct,
                          val.wrong - 1,
                        ),
                        onPlus: () => _setLgsCorrectWrong(
                          name,
                          val.correct,
                          val.wrong + 1,
                        ),
                      ),
                      Text(
                        'Boş: ${val.maxQ - val.correct - val.wrong} / ${val.maxQ}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
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

    if (isMobile) {
      return Column(
        children: [heroPanel, const SizedBox(height: 16), inputsPanel],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 6, child: inputsPanel),
        const SizedBox(width: 18),
        Expanded(flex: 5, child: heroPanel),
      ],
    );
  }

  Widget _buildYksWorkspace(bool isMobile) {
    final calc = AcademicScoreEngine.calculateYks(
      fieldType: _yksField,
      diplomaGrade: _diplomaGrade,
      brokenObp: _brokenObp,
      tytTurkce: _yksNets['TYT Türkçe']!.net,
      tytSosyal: _yksNets['TYT Sosyal']!.net,
      tytMat: _yksNets['TYT Matematik']!.net,
      tytFen: _yksNets['TYT Fen']!.net,
      aytMat: _yksNets['AYT Matematik']!.net,
      aytFizik: _yksNets['AYT Fizik']!.net,
      aytKimya: _yksNets['AYT Kimya']!.net,
      aytBiyoloji: _yksNets['AYT Biyoloji']!.net,
      aytEdebiyatSos1: _yksNets['AYT Edebiyat-Sos1']!.net,
      aytSos2: _yksNets['AYT Sosyal-2']!.net,
      ydtDil: _yksNets['YDT Yabancı Dil']!.net,
    );

    final heroPanel = Column(
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1E1B4B), Color(0xFF4338CA), Color(0xFF6366F1)],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['SAY', 'EA', 'SOZ', 'DIL'].map((f) {
                  final active = _yksField == f;
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _yksField = f),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: active
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        f,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          color: active
                              ? const Color(0xFF1E1B4B)
                              : Colors.white,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text(
                '$_yksField Yerleştirme Puanı',
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                calc.aytYerlestirme.toStringAsFixed(2),
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final gap = 10.0;
                  final isTwoCols = constraints.maxWidth < 520;
                  final cellW = isTwoCols
                      ? (constraints.maxWidth - gap) / 2
                      : (constraints.maxWidth - gap * 3) / 4;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      _heroMetricBox(
                        'Tahmini $_yksField Sıra',
                        '~${NumberFormat('#,###', 'tr_TR').format(calc.aytRank)}',
                        width: cellW,
                      ),
                      _heroMetricBox(
                        'TYT Yerleştirme',
                        calc.tytYerlestirme.toStringAsFixed(1),
                        width: cellW,
                      ),
                      _heroMetricBox(
                        'OBP Katkısı',
                        '+${calc.obpContribution.toStringAsFixed(1)}',
                        width: cellW,
                      ),
                      _heroMetricBox(
                        'Hedef Puan',
                        _yksTargetScore.toStringAsFixed(0),
                        width: cellW,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  calc.targetBand,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
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
                'Ortaöğretim Başarı Puanı (OBP) Ayarları',
                style: GoogleFonts.inter(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Diploma Notu: ${_diplomaGrade.toStringAsFixed(1)}',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    'OBP: +${calc.obpContribution.toStringAsFixed(2)} Puan',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: const Color(0xFF4F46E5),
                    ),
                  ),
                ],
              ),
              Slider(
                value: _diplomaGrade,
                min: 50,
                max: 100,
                divisions: 100,
                activeColor: const Color(0xFF4F46E5),
                onChanged: (v) => setState(() => _diplomaGrade = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  'Kırık OBP (Geçen yıl yerleşti)',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Katsayı 0.12 yerine 0.06 uygulanır',
                  style: GoogleFonts.inter(fontSize: 11.5),
                ),
                value: _brokenObp,
                onChanged: (v) => setState(() => _brokenObp = v),
              ),
            ],
          ),
        ),
      ],
    );

    final inputsPanel = Container(
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
            'TYT & $_yksField AYT Net Simülatörü (4 Yanlış = 1 Doğru)',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          ..._visibleYksKeys.map((k) {
            final item = _yksNets[k]!;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          k,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                        Text(
                          '${item.net.toStringAsFixed(2)} / ${item.maxQ} Net',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: const Color(0xFF4F46E5),
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: item.net.clamp(0, item.maxQ.toDouble()),
                      min: 0,
                      max: item.maxQ.toDouble(),
                      divisions: item.maxQ * 4,
                      activeColor: k.startsWith('TYT')
                          ? const Color(0xFF0D9488)
                          : const Color(0xFF4F46E5),
                      onChanged: (v) {
                        setState(() {
                          _yksNets[k] = (maxQ: item.maxQ, net: v);
                        });
                      },
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );

    if (isMobile) {
      return Column(
        children: [heroPanel, const SizedBox(height: 16), inputsPanel],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 6, child: inputsPanel),
        const SizedBox(width: 18),
        Expanded(flex: 5, child: heroPanel),
      ],
    );
  }

  Widget _heroMetricBox(String label, String value, {required double width}) {
    final compact = width < 155;
    final valSize = (width * 0.095).clamp(13.2, 15.0);
    return SizedBox(
      width: width,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: compact ? 10.2 : 11.0,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: valSize,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepperPill({
    required String label,
    required int value,
    required Color color,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF475569),
            ),
          ),
          InkWell(
            onTap: onMinus,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.remove_circle_outline, size: 18, color: color),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '$value',
              style: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          InkWell(
            onTap: onPlus,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.add_circle_outline, size: 18, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
