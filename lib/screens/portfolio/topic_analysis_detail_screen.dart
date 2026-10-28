import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';

class TopicAnalysisDetailScreen extends StatefulWidget {
  final Map<String, Map<String, Map<String, double>>> allSubjectStats;
  final String studentName;
  final List<String>? definedSubjectOrder;
  final int analyzedExamCount;
  final String? initialSubject;

  const TopicAnalysisDetailScreen({
    Key? key,
    required this.allSubjectStats,
    required this.studentName,
    this.definedSubjectOrder,
    this.analyzedExamCount = 1,
    this.initialSubject,
  }) : super(key: key);

  @override
  State<TopicAnalysisDetailScreen> createState() =>
      _TopicAnalysisDetailScreenState();
}

class _TopicAnalysisDetailScreenState extends State<TopicAnalysisDetailScreen> {
  late String _selectedSubject;
  late List<String> _orderedSubjects;

  @override
  void initState() {
    super.initState();
    // Sort subjects according to exam type order
    _orderedSubjects = _sortSubjectsByExamOrder(
      widget.allSubjectStats.keys.toList(),
    );

    if (widget.initialSubject != null &&
        _orderedSubjects.contains(widget.initialSubject)) {
      _selectedSubject = widget.initialSubject!;
    } else if (_orderedSubjects.isNotEmpty) {
      _selectedSubject = _orderedSubjects.first;
    }
  }

  List<String> _sortSubjectsByExamOrder(List<String> subjects) {
    return subjects..sort((a, b) {
      int indexA = _getSubjectOrderIndex(a);
      int indexB = _getSubjectOrderIndex(b);
      if (indexA != indexB) return indexA.compareTo(indexB);
      return a.compareTo(b);
    });
  }

  int _getSubjectOrderIndex(String subject) {
    final clean = subject
        .trim()
        .toLowerCase()
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı');

    // 1. Standard Sınav Sırası:
    // 1: Türkçe
    if (clean.contains('türkçe') ||
        clean.contains('turkce') ||
        clean.contains('edebiyat') ||
        clean.contains('türk dili')) {
      return 10;
    }
    // 2: Sosyal Bilgiler / T.C. İnkılap Tarihi ve Atatürkçülük / Tarih / Coğrafya
    if (clean.contains('sosyal') ||
        clean.contains('inkılap') ||
        clean.contains('inkilap') ||
        clean.contains('tarih') ||
        clean.contains('coğrafya') ||
        clean.contains('cografya') ||
        clean.contains('felsefe')) {
      return 20;
    }
    // 3: Din Kültürü ve Ahlak Bilgisi
    if (clean.contains('din')) {
      return 30;
    }
    // 4: İngilizce / Yabancı Dil
    if (clean.contains('ingilizce') ||
        clean.contains('yabancı') ||
        clean.contains('yabanci') ||
        clean.contains('almanca') ||
        clean.contains('fransızca')) {
      return 40;
    }
    // 5: Matematik (İlköğretim Matematik, Temel Matematik, Geometri)
    if (clean.contains('matematik') || clean.contains('geometri')) {
      return 50;
    }
    // 6: Fen Bilimleri (Fen ve Teknoloji, Fizik, Kimya, Biyoloji)
    if (clean.contains('fen') ||
        clean.contains('fizik') ||
        clean.contains('kimya') ||
        clean.contains('biyoloji')) {
      return 60;
    }

    // 2. Fallback: Defined order from exam type definition
    if (widget.definedSubjectOrder != null &&
        widget.definedSubjectOrder!.isNotEmpty) {
      for (int i = 0; i < widget.definedSubjectOrder!.length; i++) {
        final d = widget.definedSubjectOrder![i].trim().toLowerCase();
        if (clean == d || clean.contains(d) || d.contains(clean)) {
          return 100 + i;
        }
      }
    }

    return 999; // Unknown subjects go to the end
  }

  double _calcSubjectSuccess(String subj) {
    final map = widget.allSubjectStats[subj];
    if (map == null || map.isEmpty) return 0;
    double corr = 0;
    double total = 0;
    for (final v in map.values) {
      final c = v['correct'] ?? 0;
      final w = v['wrong'] ?? 0;
      final emp = v['empty'] ?? 0;
      corr += c;
      total += c + w + emp;
    }
    return total > 0 ? (corr / total) * 100 : 0;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: EduknAppBar(title: 'Birleşik Kazanım Analizi - ${widget.studentName}'),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Ders Seçimi',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          if (widget.analyzedExamCount > 1)
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.indigo.shade100),
                              ),
                              child: Text(
                                '${widget.analyzedExamCount} Sınav Birleştirildi',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.indigo.shade800,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _orderedSubjects.map((s) {
                          final isSel = _selectedSubject == s;
                          final count = widget.allSubjectStats[s]?.length ?? 0;
                          final pct = _calcSubjectSuccess(s);
                          return InkWell(
                            onTap: () => setState(() => _selectedSubject = s),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isSel
                                    ? Colors.indigo.shade600
                                    : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSel
                                      ? Colors.indigo.shade600
                                      : Colors.grey.shade300,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    s,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isSel
                                          ? Colors.white
                                          : Colors.indigo.shade900,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSel
                                          ? Colors.white.withValues(alpha: 0.2)
                                          : Colors.indigo.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '$count kazanım • %${pct.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isSel
                                            ? Colors.white
                                            : Colors.indigo.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(24),
              child: _buildTopicTable(
                _selectedSubject,
                widget.allSubjectStats[_selectedSubject]!,
                isMobile,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicTable(
    String subject,
    Map<String, Map<String, double>> statsMap,
    bool isMobile,
  ) {
    if (statsMap.isEmpty) return SizedBox.shrink();

    // Sort by success percentage (ascending - worst first)
    final sortedEntries = statsMap.entries.toList()
      ..sort((a, b) {
        double aCorr = a.value['correct'] ?? 0;
        double aTotal = aCorr + (a.value['wrong'] ?? 0) + (a.value['empty'] ?? 0);
        double aPct = aTotal > 0 ? (aCorr / aTotal) * 100 : 0;

        double bCorr = b.value['correct'] ?? 0;
        double bTotal = bCorr + (b.value['wrong'] ?? 0) + (b.value['empty'] ?? 0);
        double bPct = bTotal > 0 ? (bCorr / bTotal) * 100 : 0;

        return aPct.compareTo(bPct);
      });

    int totalSubjectQuestions = 0;
    int totalSubjectCorrect = 0;
    int mergedOutcomesCount = 0;
    for (final e in sortedEntries) {
      final c = (e.value['correct'] ?? 0).toInt();
      final w = (e.value['wrong'] ?? 0).toInt();
      final emp = (e.value['empty'] ?? 0).toInt();
      final exCnt = (e.value['examCount'] ?? 1).toInt();
      totalSubjectQuestions += c + w + emp;
      totalSubjectCorrect += c;
      if (exCnt > 1) mergedOutcomesCount++;
    }
    final double overallSubjectPct = totalSubjectQuestions > 0
        ? (totalSubjectCorrect / totalSubjectQuestions) * 100
        : 0;

    return Center(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: isMobile ? double.infinity : 1000,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12, top: 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 4,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.indigo,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        subject,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade900,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${sortedEntries.length} Kazanım • $totalSubjectQuestions Soru • Genel Başarı: %${overallSubjectPct.toStringAsFixed(1)}'
                      '${mergedOutcomesCount > 0 ? ' • $mergedOutcomesCount Ortak Kazanım' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: isMobile ? 20 : 36,
                  horizontalMargin: 16,
                  headingRowColor: WidgetStateProperty.all(
                    Colors.grey.shade50,
                  ),
                  columns: [
                    DataColumn(
                      label: Text(
                        'Kazanım / Konu',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text('Sınav', style: TextStyle(fontSize: 13)),
                      numeric: true,
                    ),
                    DataColumn(
                      label: Text('Soru', style: TextStyle(fontSize: 13)),
                      numeric: true,
                    ),
                    DataColumn(
                      label: Text('Doğru', style: TextStyle(fontSize: 13)),
                      numeric: true,
                    ),
                    DataColumn(
                      label: Text('Yanlış', style: TextStyle(fontSize: 13)),
                      numeric: true,
                    ),
                    DataColumn(
                      label: Text('Boş', style: TextStyle(fontSize: 13)),
                      numeric: true,
                    ),
                    DataColumn(
                      label: Text('Başarı %', style: TextStyle(fontSize: 13)),
                      numeric: true,
                    ),
                  ],
                  rows: sortedEntries.map((e) {
                    double corr = e.value['correct'] ?? 0;
                    double wrng = e.value['wrong'] ?? 0;
                    double empty = e.value['empty'] ?? 0;
                    int examCnt = (e.value['examCount'] ?? 1).toInt();
                    double total = corr + wrng + empty;
                    double pct = total > 0 ? (corr / total) * 100 : 0;

                    return DataRow(
                      cells: [
                        DataCell(
                          Container(
                            constraints: BoxConstraints(
                              maxWidth: isMobile ? 200 : 420,
                            ),
                            child: Tooltip(
                              message: e.key,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Expanded(
                                    child: Text(
                                      e.key,
                                      style: TextStyle(fontSize: 12),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (examCnt > 1) ...[
                                    SizedBox(width: 6),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.indigo.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '$examCnt sınav',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.indigo.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            examCnt.toString(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: examCnt > 1 ? FontWeight.bold : FontWeight.normal,
                              color: examCnt > 1 ? Colors.indigo.shade700 : Colors.black87,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            total.toInt().toString(),
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        DataCell(
                          Text(
                            corr.toInt().toString(),
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            wrng.toInt().toString(),
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            empty.toInt().toString(),
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        DataCell(_buildSuccessBadge(pct)),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
            SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessBadge(double percentage) {
    Color bgColor;
    Color textColor;

    if (percentage >= 80) {
      bgColor = Colors.green.shade50;
      textColor = Colors.green.shade700;
    } else if (percentage >= 60) {
      bgColor = Colors.blue.shade50;
      textColor = Colors.blue.shade700;
    } else if (percentage >= 40) {
      bgColor = Colors.orange.shade50;
      textColor = Colors.orange.shade700;
    } else {
      bgColor = Colors.red.shade50;
      textColor = Colors.red.shade700;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${percentage.toStringAsFixed(1)}%',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }
}
