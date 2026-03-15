import 'package:flutter/material.dart';

class TopicAnalysisDetailScreen extends StatefulWidget {
  final Map<String, Map<String, Map<String, double>>> allSubjectStats;
  final String studentName;

  const TopicAnalysisDetailScreen({
    Key? key,
    required this.allSubjectStats,
    required this.studentName,
  }) : super(key: key);

  @override
  State<TopicAnalysisDetailScreen> createState() =>
      _TopicAnalysisDetailScreenState();
}

class _TopicAnalysisDetailScreenState extends State<TopicAnalysisDetailScreen> {
  late String _selectedSubject;
  late List<String> _orderedSubjects;

  // Subject order based on exam type
  final List<String> _subjectOrder = [
    'Türkçe',
    'Sosyal Bilgiler',
    'Din Kültürü ve Ahlak Bilgisi',
    'İngilizce',
    'Matematik',
    'Fen Bilimleri',
  ];

  @override
  void initState() {
    super.initState();
    // Sort subjects according to exam type order
    _orderedSubjects = _sortSubjectsByExamOrder(
      widget.allSubjectStats.keys.toList(),
    );

    // Default to first subject
    if (_orderedSubjects.isNotEmpty) {
      _selectedSubject = _orderedSubjects.first;
    }
  }

  List<String> _sortSubjectsByExamOrder(List<String> subjects) {
    return subjects..sort((a, b) {
      int indexA = _getSubjectOrderIndex(a);
      int indexB = _getSubjectOrderIndex(b);
      return indexA.compareTo(indexB);
    });
  }

  int _getSubjectOrderIndex(String subject) {
    // Find matching subject in order list (case-insensitive, partial match)
    for (int i = 0; i < _subjectOrder.length; i++) {
      if (subject.toLowerCase().contains(_subjectOrder[i].toLowerCase()) ||
          _subjectOrder[i].toLowerCase().contains(subject.toLowerCase())) {
        return i;
      }
    }
    return 999; // Unknown subjects go to the end
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Konu Analiz Raporu - ${widget.studentName}',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              color: Colors.white,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ders Seçimi:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 16),
                    DropdownButton<String>(
                      value: _selectedSubject,
                      dropdownColor: Colors.white,
                      icon: Icon(
                        Icons.keyboard_arrow_down,
                        size: 20,
                        color: Colors.indigo,
                      ),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.indigo,
                        fontWeight: FontWeight.w600,
                      ),
                      items: _orderedSubjects.map((s) {
                        return DropdownMenuItem(value: s, child: Text(s));
                      }).toList(),
                      onChanged: (v) => setState(() => _selectedSubject = v!),
                    ),
                  ],
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
        double aCorr = a.value['correct']!;
        double aTotal = aCorr + a.value['wrong']! + a.value['empty']!;
        double aPct = aTotal > 0 ? (aCorr / aTotal) * 100 : 0;

        double bCorr = b.value['correct']!;
        double bTotal = bCorr + b.value['wrong']! + b.value['empty']!;
        double bPct = bTotal > 0 ? (bCorr / bTotal) * 100 : 0;

        return aPct.compareTo(bPct);
      });

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
              child: Row(
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
                  columnSpacing: isMobile ? 24 : 48,
                  horizontalMargin: 16,
                  headingRowColor: MaterialStateProperty.all(
                    Colors.grey.shade50,
                  ),
                  columns: [
                    DataColumn(
                      label: Text(
                        'Konu',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
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
                    double corr = e.value['correct']!;
                    double wrng = e.value['wrong']!;
                    double empty = e.value['empty']!;
                    double total = corr + wrng + empty;
                    double pct = total > 0 ? (corr / total) * 100 : 0;

                    return DataRow(
                      cells: [
                        DataCell(
                          Container(
                            constraints: BoxConstraints(
                              maxWidth: isMobile ? 200 : 400,
                            ),
                            child: Tooltip(
                              message: e.key,
                              child: Text(
                                e.key,
                                style: TextStyle(fontSize: 12),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
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
