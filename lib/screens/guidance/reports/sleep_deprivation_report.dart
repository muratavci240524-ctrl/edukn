import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/survey_model.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../../services/pdf_service.dart';

class SleepDeprivationReport extends StatefulWidget {
  final Survey survey;
  final List<Map<String, dynamic>> responses;
  final Map<String, String> userNames;

  const SleepDeprivationReport({
    Key? key,
    required this.survey,
    required this.responses,
    required this.userNames,
  }) : super(key: key);

  @override
  State<SleepDeprivationReport> createState() => _SleepDeprivationReportState();
}

class _SleepDeprivationReportState extends State<SleepDeprivationReport>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedScope = 'institution'; // 'institution', 'branch', 'student'
  String? _selectedBranch;
  String? _selectedStudent;

  final Map<String, List<int>> _categories = {
    'duration': [1, 2, 3, 4, 5],
    'quality': [6, 7, 8, 9, 10],
    'daytime': [11, 12, 13, 14, 15],
    'cognitive': [16, 17, 18, 19, 20],
    'emotional': [21, 22, 23, 24, 25],
    'habits': [26, 27, 28, 29, 30],
  };

  final Map<String, String> _categoryNames = {
    'duration': 'Uyku Süresi Yetersizliği',
    'quality': 'Uyku Kalitesi Sorunları',
    'daytime': 'Gündüz Uykululuk ve Yorgunluk',
    'cognitive': 'Bilişsel Etkiler',
    'emotional': 'Duygusal ve Davranışsal Etkiler',
    'habits': 'Uyku Alışkanlıkları ve Telafi',
  };

  final Set<int> _reverseItems = {1, 4, 8, 13, 19, 24, 29};

  final Map<String, dynamic> _optionsMap = {
    'Hiç katılmıyorum': 0,
    'Katılmıyorum': 1,
    'Kararsızım': 2,
    'Katılıyorum': 3,
    'Tamamen katılıyorum': 4,
  };

  List<Map<String, dynamic>> _branches = [];
  Map<String, Map<String, dynamic>> _userDetails = {};
  bool _isLoadingFilters = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadFilters();
  }

  Future<void> _loadFilters() async {
    setState(() => _isLoadingFilters = true);
    try {
      final instId = widget.survey.institutionId;

      final branchesSnap = await FirebaseFirestore.instance
          .collection('branches')
          .where('institutionId', isEqualTo: instId)
          .get();
      final allBranches = branchesSnap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .toList();

      final usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: instId)
          .where('role', isEqualTo: 'Öğrenci')
          .get();
      for (var d in usersSnap.docs) {
        _userDetails[d.id] = d.data();
      }

      final respondentUserIds = widget.responses
          .map((r) => r['userId'].toString())
          .toSet();
      final respondentBranches = respondentUserIds
          .map((uid) => _userDetails[uid]?['branch'])
          .where((b) => b != null)
          .toSet();

      _branches = allBranches
          .where((b) => respondentBranches.contains(b['id']))
          .toList();
    } catch (e) {
      print('Load filters error: $e');
    }
    if (mounted) setState(() => _isLoadingFilters = false);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _getFilteredResponses();
    final averages = _calculateAverages(filtered);

    return Column(
      children: [
        if (_isLoadingFilters) const LinearProgressIndicator(minHeight: 2),
        _buildFilters(),
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: Colors.black,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.indigo,
            indicatorWeight: 3,
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Genel Analiz'),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.picture_as_pdf,
                        size: 18,
                        color: Colors.red.shade700,
                      ),
                      onPressed: () =>
                          _exportSummaryToPdf(averages, filtered.length),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Sonuç Tablosu'),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.description,
                        size: 18,
                        color: Colors.green.shade700,
                      ),
                      onPressed: () => _exportTableToExcel(filtered),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSummaryAnalysis(averages, filtered.length),
              _buildDetailedResults(filtered),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  style: SegmentedButton.styleFrom(
                    backgroundColor: Colors.white,
                    selectedBackgroundColor: const Color(0xFFEBE3FF),
                    selectedForegroundColor: Colors.indigo,
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  segments: const [
                    ButtonSegment(
                      value: 'institution',
                      label: Text('Kurum'),
                      icon: Icon(Icons.apartment, size: 16),
                    ),
                    ButtonSegment(
                      value: 'branch',
                      label: Text('Şube'),
                      icon: Icon(Icons.grid_view, size: 16),
                    ),
                    ButtonSegment(
                      value: 'student',
                      label: Text('Öğrenci'),
                      icon: Icon(Icons.person, size: 16),
                    ),
                  ],
                  selected: {_selectedScope},
                  showSelectedIcon: true,
                  onSelectionChanged: (val) {
                    setState(() {
                      _selectedScope = val.first;
                      _selectedBranch = null;
                      _selectedStudent = null;
                    });
                  },
                ),
              ),
            ],
          ),
          if (_selectedScope != 'institution') ...[
            const SizedBox(height: 12),
            if (_selectedScope == 'branch')
              _buildDropdownFilter(
                label: 'Şube Seç',
                value: _selectedBranch,
                items: _branches
                    .map(
                      (b) => DropdownMenuItem(
                        value: b['id'],
                        child: Text(b['name'] ?? 'Adsız'),
                      ),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _selectedBranch = val),
              ),
            if (_selectedScope == 'student')
              _buildDropdownFilter(
                label: 'Öğrenci Seç',
                value: _selectedStudent,
                items: () {
                  final uids = widget.responses
                      .map((r) => r['userId'].toString())
                      .toSet()
                      .toList();
                  final list = uids.map((uid) {
                    return {
                      'id': uid,
                      'name': widget.userNames[uid] ?? 'Öğrenci ($uid)',
                    };
                  }).toList();
                  list.sort((a, b) => a['name']!.compareTo(b['name']!));
                  return list
                      .map(
                        (e) => DropdownMenuItem(
                          value: e['id'],
                          child: Text(e['name']!),
                        ),
                      )
                      .toList();
                }(),
                onChanged: (val) => setState(() => _selectedStudent = val),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildDropdownFilter({
    required String label,
    required dynamic value,
    required List<DropdownMenuItem<dynamic>> items,
    required ValueChanged<dynamic> onChanged,
  }) {
    return Container(
      width: double.infinity,
      child: DropdownButtonFormField(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          filled: true,
          fillColor: Colors.grey.shade50,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.indigo, width: 2),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        isExpanded: true,
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  List<Map<String, dynamic>> _getFilteredResponses() {
    return widget.responses.where((r) {
      if (_selectedScope == 'student') {
        return _selectedStudent == null || r['userId'] == _selectedStudent;
      }
      if (_selectedScope == 'branch') {
        final uId = r['userId'].toString();
        final uBranch = _userDetails[uId]?['branch'];
        return _selectedBranch == null || uBranch == _selectedBranch;
      }
      return true;
    }).toList();
  }

  Map<String, double> _calculateAverages(List<Map<String, dynamic>> responses) {
    if (responses.isEmpty) return {};
    Map<String, double> totals = {};
    for (var r in responses) {
      final stats = _calculateStudentStats(r);
      stats.forEach((key, value) {
        totals[key] = (totals[key] ?? 0) + value;
      });
    }
    totals.forEach((key, value) {
      totals[key] = value / responses.length;
    });
    return totals;
  }

  Map<String, double> _calculateStudentStats(Map<String, dynamic> response) {
    final answers = response['answers'] as Map<String, dynamic>? ?? {};
    Map<String, double> results = {};
    double totalScore = 0;

    _categories.forEach((catId, questionNums) {
      double catScore = 0;
      for (var qNum in questionNums) {
        final answer = answers['q$qNum'];
        if (answer != null) {
          int score = _optionsMap[answer] ?? 0;
          if (_reverseItems.contains(qNum)) {
            score = 4 - score;
          }
          catScore += score;
        }
      }
      results[catId] = catScore;
      totalScore += catScore;
    });

    results['total'] = totalScore;
    return results;
  }

  Widget _buildSummaryAnalysis(Map<String, double> averages, int count) {
    if (count == 0)
      return const Center(child: Text('Yanıt henüz bulunmamaktadır.'));

    final totalScore = averages['total'] ?? 0;
    final radarData = _categories.keys.map((catId) {
      final val = averages[catId] ?? 0;
      return val / 20.0; // Max score per category is 5 * 4 = 20
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _buildScoreOverview(totalScore),
          const SizedBox(height: 32),
          _buildRadarChart(radarData),
          const SizedBox(height: 32),
          _buildInterpretationCards(averages),
        ],
      ),
    );
  }

  Widget _buildScoreOverview(double score) {
    String level = '';
    Color color = Colors.green;
    if (score <= 30) {
      level = 'Düşük düzeyde uyku yoksunluğu';
      color = Colors.green;
    } else if (score <= 60) {
      level = 'Hafif düzeyde uyku yoksunluğu';
      color = Colors.orange;
    } else if (score <= 90) {
      level = 'Belirgin uyku yoksunluğu';
      color = Colors.deepOrange;
    } else {
      level = 'Yüksek düzeyde uyku yoksunluğu';
      color = Colors.red;
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            const Text(
              'Toplam Uyku Yoksunluğu Puanı',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Text(
              score.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              level,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color.withOpacity(0.8),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '0-120 Puan Ölçeği',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadarChart(List<double> normalizedData) {
    return Column(
      children: [
        Text(
          'Boyut Bazlı Uyku Yoksunluğu Profili',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.indigo.shade900,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 300,
          child: RadarChart(
            RadarChartData(
              dataSets: [
                RadarDataSet(
                  fillColor: Colors.indigo.withOpacity(0.2),
                  borderColor: Colors.indigo,
                  entryRadius: 3,
                  dataEntries: normalizedData
                      .map((v) => RadarEntry(value: v * 100))
                      .toList(),
                ),
              ],
              radarShape: RadarShape.polygon,
              tickCount: 5,
              ticksTextStyle: const TextStyle(color: Colors.grey, fontSize: 10),
              gridBorderData: const BorderSide(color: Colors.grey, width: 0.5),
              radarBackgroundColor: Colors.transparent,
              radarBorderData: const BorderSide(color: Colors.indigo, width: 1),
              getTitle: (index, angle) {
                if (index >= _categories.length)
                  return const RadarChartTitle(text: '');
                final key = _categories.keys.elementAt(index);
                return RadarChartTitle(
                  text: _categoryNames[key]!,
                  angle: angle,
                );
              },
              radarTouchData: RadarTouchData(enabled: true),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInterpretationCards(Map<String, double> averages) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Alt Boyut Analizleri',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ..._categories.keys.map((catId) {
          final score = averages[catId] ?? 0;
          final max = 20.0;
          final isHigh = score >= 12;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _categoryNames[catId]!,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isHigh
                              ? Colors.red.shade50
                              : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${score.toStringAsFixed(1)} / $max',
                          style: TextStyle(
                            color: isHigh ? Colors.red : Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getCategoryComment(catId, score),
                    style: TextStyle(color: Colors.grey.shade800),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  String _getCategoryComment(String catId, double score) {
    if (score < 5) return 'Düşük düzeyde etki görülmektedir.';
    if (score < 10) return 'Hafif düzeyde etki görülmektedir.';
    if (score < 15)
      return 'Orta düzeyde etki görülmektedir. Uyku düzenine dikkat edilmelidir.';
    return 'Yüksek düzeyde etki görülmektedir. Profesyonel destek veya yaşam tarzı değişikliği gerekebilir.';
  }

  Widget _buildDetailedResults(List<Map<String, dynamic>> filtered) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final r = filtered[index];
        final name = widget.userNames[r['userId']] ?? 'Bilinmeyen';
        final stats = _calculateStudentStats(r);
        final score = stats['total'] ?? 0;

        return Card(
          child: ListTile(
            title: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('Toplam Puan: ${score.toStringAsFixed(0)}'),
            trailing: _getScoreChip(score),
            onTap: () => _showStudentDetail(name, r),
          ),
        );
      },
    );
  }

  Widget _getScoreChip(double score) {
    Color color = Colors.green;
    if (score > 90)
      color = Colors.red;
    else if (score > 60)
      color = Colors.deepOrange;
    else if (score > 30)
      color = Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        score.toStringAsFixed(0),
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showStudentDetail(String studentName, Map<String, dynamic> response) {
    final stats = _calculateStudentStats(response);

    showDialog(
      context: context,
      builder: (context) => DefaultTabController(
        length: 2,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            width: 700,
            height: 750,
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Uyku Yoksunluğu Analiz Profili',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          Text(
                            studentName,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const TabBar(
                  labelColor: Colors.indigo,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Colors.indigo,
                  tabs: [
                    Tab(text: 'PUAN TABLOSU'),
                    Tab(text: 'YORUM VE ÖNERİLER'),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildModalPuanTab(stats),
                      _buildModalReportTab(stats),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModalPuanTab(Map<String, double> stats) {
    return SingleChildScrollView(
      child: Table(
        columnWidths: const {0: FlexColumnWidth(4), 1: FlexColumnWidth(2)},
        border: TableBorder.all(color: Colors.grey.shade200),
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.indigo.shade900),
            children: [
              _buildModalHeaderCell('ALT BOYUT'),
              _buildModalHeaderCell('PUAN'),
            ],
          ),
          ..._categories.keys.map((catId) {
            final val = stats[catId] ?? 0;
            final max = 20;
            final isHigh = val >= 12;
            return TableRow(
              decoration: BoxDecoration(
                color: isHigh ? Colors.red.shade50 : Colors.green.shade50,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    _categoryNames[catId]!,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    '${val.toInt()} / $max',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isHigh ? Colors.red : Colors.green,
                    ),
                  ),
                ),
              ],
            );
          }),
          TableRow(
            decoration: BoxDecoration(color: Colors.grey.shade100),
            children: [
              const Padding(
                padding: EdgeInsets.all(12.0),
                child: Text(
                  'TOPLAM PUAN',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  '${stats['total']?.toInt() ?? 0} / 120',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModalReportTab(Map<String, double> stats) {
    final advice = _generateAdviceString(stats);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.indigo.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.indigo.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.psychology, color: Colors.indigo, size: 24),
                SizedBox(width: 8),
                Text(
                  'Uzman Analizi ve Değerlendirme',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            Text(
              advice,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: Colors.indigo.shade900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModalHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Future<void> _exportSummaryToPdf(
    Map<String, double> averages,
    int count,
  ) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF raporu hazırlanıyor...')),
      );

      final pdfService = PdfService();

      String subTitle = _selectedScope == 'student'
          ? "${widget.userNames[_selectedStudent] ?? 'Öğrenci'} - Bireysel Analiz"
          : (_selectedScope == 'branch'
                ? "${_branches.firstWhere((b) => b['id'] == _selectedBranch, orElse: () => {'name': 'Tüm Şubeler'})['name']} Şube Analizi"
                : "Genel Kurum Analizi");

      final categoryMax = {
        'duration': 20,
        'quality': 20,
        'daytime': 20,
        'cognitive': 20,
        'emotional': 20,
        'habits': 20,
      };

      final advice = _generateAdviceString(averages);
      final chartAverages = Map<String, double>.from(averages)..remove('total');

      final pdfBytes = await pdfService.generateSurveyReportPdf(
        title: widget.survey.title,
        subTitle: subTitle,
        averages: chartAverages,
        categoryNames: _categoryNames,
        categoryMax: categoryMax,
        respondentCount: count,
        advice: advice,
      );

      await FileSaver.instance.saveFile(
        name: '${widget.survey.title}_Rapor',
        bytes: pdfBytes,
        ext: 'pdf',
        mimeType: MimeType.pdf,
      );
    } catch (e) {
      print('PDF export error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF oluşturulurken hata oluştu: $e')),
        );
      }
    }
  }

  String _generateAdviceString(Map<String, double> averages) {
    final totalScore = averages['total'] ?? 0;
    final duration = averages['duration'] ?? 0;
    final quality = averages['quality'] ?? 0;
    final daytime = averages['daytime'] ?? 0;
    final cognitive = averages['cognitive'] ?? 0;
    final emotional = averages['emotional'] ?? 0;
    final habits = averages['habits'] ?? 0;

    String advice = "UYKU YOKSUNLUĞU UZMAN ANALİZ RAPORU\n\n";

    // A. Genel Profil Değerlendirmesi
    advice += "A. Genel Profil Değerlendirmesi\n";
    if (totalScore <= 30) {
      advice +=
          "Bireyin uyku profili incelendiğinde, biyolojik ve psikolojik dinlenme ihtiyacının dengeli bir şekilde karşılandığı görülmektedir. Mevcut veriler, uyku döngüsünün işlevsel olduğunu ve bireyin güne dinç başlama kapasitesinin yüksek olduğunu göstermektedir.\n\n";
    } else if (totalScore <= 60) {
      advice +=
          "Analiz sonuçları, hafif düzeyde bir uyku borcu birikimine işaret etmektedir. Bu tablo genellikle düzensiz uyku saatleri veya uyku öncesi rutinlerdeki aksamalarla ilişkilidir. Bireyin tam kapasitesine ulaşmasını engelleyen örtük bir yorgunluk hali söz konusu olabilir.\n\n";
    } else if (totalScore <= 90) {
      advice +=
          "Bireyin kronik bir uyku yoksunluğu riski altında olduğu gözlemlenmektedir. Bu durum, sadece bir dinlenme sorunu değil, genel yaşam kalitesini ve psikolojik dayanıklılığı tehdit eden bir seviyeye ulaşmıştır. Beden ve zihin, yetersiz restorasyon süreci nedeniyle alarm vermektedir.\n\n";
    } else {
      advice +=
          "Birey, çok yüksek düzeyde ve kritik bir uyku yoksunluğu tablosu içindedir. Bu seviye, fiziksel ve nörolojik işlevlerde ciddi aksamalara yol açabilecek düzeydedir. Uyku kaybı artık bireyin günlük kontrol mekanizmalarını zayıflatmış ve biyolojik ritmi tamamen bozmuş durumdadir.\n\n";
    }

    // B. Alt Boyutlara Dayalı Detaylı Analiz
    advice += "B. Alt Boyutlara Dayalı Detaylı Analiz\n";
    if (duration > 12 || quality > 12) {
      advice += "Nicelik ve nitelik bazlı analizde, ";
      if (duration > quality) {
        advice +=
            "uyku süresinin yetersizliği temel sorun olarak öne çıkmaktadır. Birey ihtiyaç duyduğu uykuyu alamamasına rağmen uykuda olduğu süreyi verimli geçirme eğilimindedir. ";
      } else {
        advice +=
            "uyku kalitesindeki bozulma dikkat çekicidir. Birey yeterli süre uykuda kalsa dahi derin uyku evrelerine geçmekte zorlanmakta ve kesintili bir süreç yaşamaktadır. ";
      }
      advice +=
          "Özellikle telafi davranışlarının (kafein kullanımı, hafta sonu aşırı uyuma) varlığı, sistemin sürdürülebilirliğini zorlamaktadır.\n\n";
    } else {
      advice +=
          "Alt boyutlar arasındaki ilişki tutarlı bir seyir izlemektedir. Uyku süresi ve kalitesi birbirini desteklemekte, gündüz işlevselliği ile bilişsel kapasite bu dengeden olumlu yönde etkilenmektedir.\n\n";
    }

    // C. Günlük Yaşam ve Akademik/Sosyal Etkilere Yansıma
    advice += "C. Günlük Yaşam ve Akademik/Sosyal Etkilere Yansıma\n";
    if (daytime > 10 || cognitive > 10 || emotional > 10) {
      advice += "Mevcut uyku tablosu, bireyin ";
      if (cognitive > 10)
        advice +=
            "odaklanma, bellek performansı ve düşünme hızı gibi bilişsel süreçlerinde belirgin bir zayıflamaya neden olmaktadır. ";
      if (emotional > 10)
        advice +=
            "duygusal eşiğini düşürerek daha tepkisel, huzursuz veya toleransı düşük bir ruh halini tetiklemektedir. ";
      advice +=
          "Bu durum özellikle akademik performansta dalgalanmalara ve sosyal ilişkilerde iletişim kazalarının artmasına sebebiyet verebilir.\n\n";
    } else {
      advice +=
          "Sosyal ve akademik hayata yansıyan belirgin bir negatif etki gözlemlenmemiştir. Bireyin zihinsel berraklığı ve duygusal dengesi, sağlıklı bir uyku rutiniyle korunmaktadır.\n\n";
    }

    // D. Güçlü Yönler ve Geliştirilebilecek Alanlar + Öneriler
    advice += "D. Güçlü Yönler ve Geliştirilebilecek Alanlar + Öneriler\n";
    advice +=
        "Bireyin uyku hijyenini artırmak adına uyku öncesi mavi ışık maruziyetini sınırlaması ve 'uyku penceresi' olarak adlandırılan düzenli yatış-kalkış saatlerine sadık kalması kritiktir. ";
    if (habits > 10) {
      advice +=
          "Telafi amaçlı kullanılan yüksek miktarda kafein ve hafta sonu uyku kaymaları, biyolojik saati daha fazla bozmaktadır; bu alışkanlıkların kademeli olarak azaltılması önerilir. ";
    }
    advice +=
        "Hafif fiziksel aktivitelerin gün içine yayılması uyku kalitesini artıracaktır.\n\n";

    advice += "KAPANIŞ:\n";
    advice +=
        "Bu sonuçlar bireyin şu anki durumuna dair önemli ipuçları sunmaktadır. Uygun destek ve farkındalık çalışmalarıyla, mevcut güçlüklerin yönetilebilir olduğu ve bireyin işlevselliğinin artırılabileceği görülmektedir.";

    return advice;
  }

  Future<void> _exportTableToExcel(List<Map<String, dynamic>> filtered) async {
    try {
      var excel = Excel.createExcel();
      var sheet = excel['Uyku Yoksunluğu Sonuçları'];

      sheet.appendRow([
        TextCellValue('Öğrenci Adı'),
        TextCellValue('Toplam Puan'),
        TextCellValue('Uyku Süresi'),
        TextCellValue('Uyku Kalitesi'),
        TextCellValue('Gündüz Etkileri'),
        TextCellValue('Bilişsel Etkiler'),
        TextCellValue('Duygusal Etkiler'),
        TextCellValue('Alışkanlıklar'),
      ]);

      for (var r in filtered) {
        final name = widget.userNames[r['userId']] ?? 'Bilinmeyen';
        final stats = _calculateStudentStats(r);
        sheet.appendRow([
          TextCellValue(name),
          DoubleCellValue(stats['total'] ?? 0),
          DoubleCellValue(stats['duration'] ?? 0),
          DoubleCellValue(stats['quality'] ?? 0),
          DoubleCellValue(stats['daytime'] ?? 0),
          DoubleCellValue(stats['cognitive'] ?? 0),
          DoubleCellValue(stats['emotional'] ?? 0),
          DoubleCellValue(stats['habits'] ?? 0),
        ]);
      }

      var fileBytes = excel.save();
      if (fileBytes != null) {
        await FileSaver.instance.saveFile(
          name: 'Uyku_Yoksunlugu_Raporu',
          bytes: Uint8List.fromList(fileBytes),
          ext: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
      }
    } catch (e) {
      print('Excel export error: $e');
    }
  }
}
