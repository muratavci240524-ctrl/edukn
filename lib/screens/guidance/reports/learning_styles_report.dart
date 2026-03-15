import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/survey_model.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../../services/pdf_service.dart';

class LearningStylesReport extends StatefulWidget {
  final Survey survey;
  final List<Map<String, dynamic>> responses;
  final Map<String, String> userNames;

  const LearningStylesReport({
    Key? key,
    required this.survey,
    required this.responses,
    required this.userNames,
  }) : super(key: key);

  @override
  State<LearningStylesReport> createState() => _LearningStylesReportState();
}

class _LearningStylesReportState extends State<LearningStylesReport>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedScope = 'institution';
  String? _selectedBranch;
  String? _selectedStudent;

  final Map<String, List<int>> _categories = {
    'ver_perc': [1, 2, 3, 4, 5, 6],
    'ver_proc': [7, 8, 9, 10, 11, 12],
    'vis_perc': [13, 14, 15, 16, 17, 18],
    'vis_proc': [19, 20, 21, 22, 23, 24],
    'kin_perc': [25, 26, 27, 28, 29, 30],
    'kin_proc': [31, 32, 33, 34, 35, 36],
    'distractor': [37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48],
  };

  final Map<String, String> _categoryNames = {
    'ver_perc': 'Sözel Algılama',
    'ver_proc': 'Sözel İşleme',
    'vis_perc': 'Görsel Algılama',
    'vis_proc': 'Görsel İşleme',
    'kin_perc': 'Kinestetik Algılama',
    'kin_proc': 'Kinestetik İşleme',
  };

  final List<int> _reverseItems = [
    1,
    4,
    7,
    8,
    10,
    13,
    15,
    19,
    20,
    22,
    25,
    31,
    32,
    34,
    38,
    40,
    42,
    44,
    47,
    48,
  ];

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
          .where('role', isEqualTo: 'student')
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
              _buildSummaryTab(averages, filtered.length),
              _buildDetailsTab(filtered),
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
                    selectedBackgroundColor: Colors.indigo.shade50,
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
    Map<String, double> stats = {};
    double grandTotal = 0;

    _categories.forEach((cat, qIndices) {
      double catTotal = 0;
      for (var idx in qIndices) {
        final qId = 'q$idx';
        final valStr = answers[qId]?.toString() ?? 'Hiç katılmıyorum';
        int val = _getOptionValue(valStr);

        if (_reverseItems.contains(idx)) {
          val = 4 - val;
        }
        catTotal += val;
      }
      stats[cat] = catTotal;
      if (cat != 'distractor') grandTotal += catTotal;
    });

    stats['total'] = grandTotal;

    int indecisiveCount = 0;
    answers.forEach((key, value) {
      if (value.toString() == 'Kararsızım') indecisiveCount++;
    });
    stats['indecisiveRatio'] = (indecisiveCount / 48.0) * 100;

    return stats;
  }

  int _getOptionValue(String option) {
    switch (option) {
      case 'Hiç katılmıyorum':
        return 0;
      case 'Katılmıyorum':
        return 1;
      case 'Kararsızım':
        return 2;
      case 'Katılıyorum':
        return 3;
      case 'Tamamen katılıyorum':
        return 4;
      default:
        return 0;
    }
  }

  Widget _buildSummaryTab(Map<String, double> averages, int count) {
    if (count == 0) return const Center(child: Text('Henüz yanıt bulunmuyor.'));

    final indecisiveRatio = averages['indecisiveRatio'] ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildStyleOverview(averages, count, indecisiveRatio),
          const SizedBox(height: 24),
          _buildRadarChart(averages),
          const SizedBox(height: 24),
          _buildInterpretation(averages),
        ],
      ),
    );
  }

  Widget _buildStyleOverview(
    Map<String, double> averages,
    int count,
    double indecisiveRatio,
  ) {
    final styles = {
      'Sözel': (averages['ver_perc'] ?? 0) + (averages['ver_proc'] ?? 0),
      'Görsel': (averages['vis_perc'] ?? 0) + (averages['vis_proc'] ?? 0),
      'Kinestetik': (averages['kin_perc'] ?? 0) + (averages['kin_proc'] ?? 0),
    };

    final dominant = styles.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text('Baskın Öğrenme Kanalı', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              dominant,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Yanıt Sayısı', count.toString()),
                _buildStatItem(
                  'Kararsızlık',
                  '${indecisiveRatio.toStringAsFixed(1)}%',
                ),
              ],
            ),
            if (indecisiveRatio > 30) ...[
              const Divider(height: 32),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.tips_and_updates, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Durumsal Öğrenme Profili: Öğrenme tercihleriniz ders içeriğine, ortama veya konunun zorluğuna göre esneklik gösteriyor.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildRadarChart(Map<String, double> averages) {
    final List<String> cats = _categoryNames.keys.toList();
    final data = cats.map((cat) {
      final score = averages[cat] ?? 0;
      return (score / 24.0) * 100;
    }).toList();

    return Container(
      height: 350,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          const Text(
            '3x2 Öğrenme Profili (%)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: RadarChart(
              RadarChartData(
                dataSets: [
                  RadarDataSet(
                    fillColor: Colors.orange.withOpacity(0.2),
                    borderColor: Colors.orange,
                    entryRadius: 3,
                    dataEntries: data.map((d) => RadarEntry(value: d)).toList(),
                  ),
                ],
                radarShape: RadarShape.circle,
                tickCount: 5,
                gridBorderData: const BorderSide(
                  color: Colors.grey,
                  width: 0.5,
                ),
                getTitle: (index, angle) => RadarChartTitle(
                  text: _categoryNames[cats[index]]!,
                  angle: angle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInterpretation(Map<String, double> averages) {
    final advice = _generateAdviceString(averages);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb, color: Colors.orange, size: 24),
              SizedBox(width: 8),
              Text(
                'Kişiselleştirilmiş Öğrenme Analizi',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
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
              color: Colors.orange.shade900,
            ),
          ),
        ],
      ),
    );
  }

  String _generateAdviceString(Map<String, double> averages) {
    final verPerc = averages['ver_perc'] ?? 0;
    final verProc = averages['ver_proc'] ?? 0;
    final visPerc = averages['vis_perc'] ?? 0;
    final visProc = averages['vis_proc'] ?? 0;
    final kinPerc = averages['kin_perc'] ?? 0;
    final kinProc = averages['kin_proc'] ?? 0;

    String advice = "3x2 ÖĞRENME STİLLERİ ANALİZ RAPORU\n\n";

    // Detect high gap between perception and processing
    if (verPerc > 18 && verProc < 12)
      advice +=
          "NOT: Sözel bilgiyi almada iyisiniz ancak bilgiyi sözel olarak işleme (ifade etme/tekrarlama) konusunda zorluk yaşıyor olabilirsiniz.\n\n";
    if (visPerc > 18 && visProc < 12)
      advice +=
          "NOT: Görsel materyalleri iyi anlıyorsunuz ancak bilgiyi kendi başınıza şemaya/görsele dökme konusunda gelişime ihtiyaç var.\n\n";

    advice += "1. Öğrenme Tercihleriniz\n";
    final styles = {
      'Sözel': verPerc + verProc,
      'Görsel': visPerc + visProc,
      'Kinestetik': kinPerc + kinProc,
    };
    final sorted = styles.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    advice +=
        "Baskın kanalınız: ${sorted[0].key}. Bunu ${sorted[1].key} kanalı destekliyor.\n\n";

    advice += "2. Ders Çalışma Önerileri\n";
    if (sorted[0].key == 'Sözel') {
      advice +=
          "- Konuları yüksek sesle tekrar ederek çalışın.\n- Ses kayıtları veya podcast'lerden faydalanın.\n- Başkalarına anlatarak öğrenmeyi pekiştirin.\n";
    } else if (sorted[0].key == 'Görsel') {
      advice +=
          "- Akıl haritaları ve kavram şemaları oluşturun.\n- Renkli kalemler ve vurgulayıcılar kullanın.\n- Video dersler ve infografikler temel kaynağınız olsun.\n";
    } else {
      advice +=
          "- Çalışırken hareket etmeyi deneyin (ayakta okuma vb.).\n- Somut deneyler ve uygulamalar üzerinden ilerleyin.\n- Kısa ve aktif çalışma seansları düzenleyin.\n";
    }

    advice += "\n3. Stratejik İpucu\n";
    advice +=
        "En zayıf kanalınız (${sorted[2].key}) üzerinden gelen bilgileri, en güçlü kanalınız olan ${sorted[0].key} formatına dönüştürerek çalışmak öğrenme hızınızı 2 katına çıkaracaktır.\n";

    return advice;
  }

  Widget _buildDetailsTab(List<Map<String, dynamic>> filtered) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final r = filtered[index];
        final name = widget.userNames[r['userId']] ?? 'Bilinmeyen';
        final stats = _calculateStudentStats(r);
        return Card(
          child: ListTile(
            title: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('En Güçlü: ${_getDominantStyle(stats)}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showStudentDetail(name, stats),
          ),
        );
      },
    );
  }

  String _getDominantStyle(Map<String, double> stats) {
    final s = {
      'Sözel': (stats['ver_perc'] ?? 0) + (stats['ver_proc'] ?? 0),
      'Görsel': (stats['vis_perc'] ?? 0) + (stats['vis_proc'] ?? 0),
      'Kinestetik': (stats['kin_perc'] ?? 0) + (stats['kin_proc'] ?? 0),
    };
    return s.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  void _showStudentDetail(String name, Map<String, double> stats) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, color: Colors.white),
                  const SizedBox(width: 12),
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildStyleOverview(
                      stats,
                      1,
                      stats['indecisiveRatio'] ?? 0,
                    ),
                    const SizedBox(height: 24),
                    _buildRadarChart(stats),
                    const SizedBox(height: 24),
                    _buildInterpretation(stats),
                  ],
                ),
              ),
            ),
          ],
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
          ? "${widget.userNames[_selectedStudent]} - Bireysel Analiz"
          : (_selectedScope == 'branch'
                ? "${_branches.firstWhere((b) => b['id'] == _selectedBranch, orElse: () => {'name': 'Tüm Şubeler'})['name']} Şube Analizi"
                : "Genel Kurum Analizi");

      final categoryMax = {
        'ver_perc': 24,
        'ver_proc': 24,
        'vis_perc': 24,
        'vis_proc': 24,
        'kin_perc': 24,
        'kin_proc': 24,
      };

      final pdfBytes = await pdfService.generateSurveyReportPdf(
        title: '3x2 Öğrenme Stilleri Ölçeği',
        subTitle: subTitle,
        averages: Map.from(averages)
          ..remove('total')
          ..remove('indecisiveRatio')
          ..remove('distractor'),
        categoryNames: _categoryNames,
        categoryMax: categoryMax,
        respondentCount: count,
        advice: _generateAdviceString(averages),
      );

      await FileSaver.instance.saveFile(
        name: 'Ogrenme_Stilleri_Rapor',
        bytes: pdfBytes,
        ext: 'pdf',
        mimeType: MimeType.pdf,
      );
    } catch (e) {
      print('PDF error: $e');
    }
  }

  Future<void> _exportTableToExcel(List<Map<String, dynamic>> filtered) async {
    try {
      var excel = Excel.createExcel();
      var sheet = excel['Öğrenme Stilleri'];
      sheet.appendRow([
        TextCellValue('Öğrenci Adı'),
        TextCellValue('Sözel Alg.'),
        TextCellValue('Sözel İşl.'),
        TextCellValue('Görsel Alg.'),
        TextCellValue('Görsel İşl.'),
        TextCellValue('Kinestetik Alg.'),
        TextCellValue('Kinestetik İşl.'),
        TextCellValue('Baskın Stil'),
      ]);

      for (var r in filtered) {
        final name = widget.userNames[r['userId']] ?? 'Bilinmeyen';
        final stats = _calculateStudentStats(r);
        sheet.appendRow([
          TextCellValue(name),
          DoubleCellValue(stats['ver_perc'] ?? 0),
          DoubleCellValue(stats['ver_proc'] ?? 0),
          DoubleCellValue(stats['vis_perc'] ?? 0),
          DoubleCellValue(stats['vis_proc'] ?? 0),
          DoubleCellValue(stats['kin_perc'] ?? 0),
          DoubleCellValue(stats['kin_proc'] ?? 0),
          TextCellValue(_getDominantStyle(stats)),
        ]);
      }

      var fileBytes = excel.save();
      if (fileBytes != null) {
        await FileSaver.instance.saveFile(
          name: 'Ogrenme_Stilleri_Excel',
          bytes: Uint8List.fromList(fileBytes),
          ext: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
      }
    } catch (e) {
      print('Excel error: $e');
    }
  }
}
