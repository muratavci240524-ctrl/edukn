import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/survey_model.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../../services/pdf_service.dart';

class AcademicProcrastinationReport extends StatefulWidget {
  final Survey survey;
  final List<Map<String, dynamic>> responses;
  final Map<String, String> userNames;

  const AcademicProcrastinationReport({
    Key? key,
    required this.survey,
    required this.responses,
    required this.userNames,
  }) : super(key: key);

  @override
  State<AcademicProcrastinationReport> createState() =>
      _AcademicProcrastinationReportState();
}

class _AcademicProcrastinationReportState
    extends State<AcademicProcrastinationReport>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedScope = 'institution';
  String? _selectedBranch;
  String? _selectedStudent;

  final Map<String, List<int>> _categories = {
    'initiation': List.generate(6, (i) => i + 1), // 1-6
    'emotional': List.generate(6, (i) => i + 7), // 7-12
    'cognitive': List.generate(6, (i) => i + 13), // 13-18
    'perfectionism': List.generate(6, (i) => i + 19), // 19-24
    'management': List.generate(6, (i) => i + 25), // 25-30
    'motivation': List.generate(6, (i) => i + 31), // 31-36
    'distractor': List.generate(18, (i) => i + 37), // 37-54
  };

  final Map<String, String> _categoryNames = {
    'initiation': 'Göreve Başlama Güçlüğü',
    'emotional': 'Duygusal Kaçınma',
    'cognitive': 'Bilişsel Gerekçeler',
    'perfectionism': 'Mükemmeliyetçilik',
    'management': 'Zaman Yönetimi',
    'motivation': 'Motivasyon ve Amaç',
  };

  final List<int> _reverseItems = [5, 11, 17, 23, 28, 31, 35, 45];

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
    stats['indecisiveRatio'] = (indecisiveCount / 54.0) * 100;

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

    final totalScore = averages['total'] ?? 0;
    final indecisiveRatio = averages['indecisiveRatio'] ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildScoreOverview(totalScore, count, indecisiveRatio),
          const SizedBox(height: 24),
          _buildRadarChart(averages),
          const SizedBox(height: 24),
          _buildInterpretation(averages),
        ],
      ),
    );
  }

  Widget _buildScoreOverview(double score, int count, double indecisiveRatio) {
    String level;
    Color color;
    if (score <= 70) {
      level = 'Düşük Erteleme';
      color = Colors.green;
    } else if (score <= 120) {
      level = 'Durumsal Erteleme';
      color = Colors.orange;
    } else if (score <= 170) {
      level = 'Belirgin Erteleme';
      color = Colors.deepOrange;
    } else {
      level = 'Yüksek Akademik Erteleme';
      color = Colors.red;
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              'Akademik Erteleme Düzeyi',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              level,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  'Ortalama Puan',
                  '${score.toStringAsFixed(1)} / 216',
                ),
                _buildStatItem('Yanıt Sayısı', count.toString()),
              ],
            ),
            if (indecisiveRatio > 25) ...[
              const Divider(height: 32),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Yüksek Kararsızlık Oranı: Erteleme davranışı dalgalı veya belirli bir bağlama (ders, konu vb.) bağlı olabilir.',
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
            'Erteleme Kaynakları (%)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: RadarChart(
              RadarChartData(
                dataSets: [
                  RadarDataSet(
                    fillColor: Colors.indigo.withOpacity(0.2),
                    borderColor: Colors.indigo,
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
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology, color: Colors.indigo, size: 24),
              const SizedBox(width: 8),
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
    );
  }

  String _generateAdviceString(Map<String, double> averages) {
    final totalScore = averages['total'] ?? 0;
    final initiation = averages['initiation'] ?? 0;
    final emotional = averages['emotional'] ?? 0;
    final perfectionism = averages['perfectionism'] ?? 0;
    final management = averages['management'] ?? 0;
    final motivation = averages['motivation'] ?? 0;
    final distractor = averages['distractor'] ?? 0;

    String advice = "AKADEMİK ERTELEME UZMAN RAPORU\n\n";

    if (distractor < 10 && totalScore > 120) {
      advice +=
          "ÖNEMLİ: Çeldirici maddelerdeki düşük puanlar, bireyin sorunun farkında olduğunu ancak çözüm üretmekte zorlandığını göstermektedir.\n\n";
    }

    advice += "A. Mevcut Durum Analizi\n";
    if (totalScore <= 70) {
      advice +=
          "Birey, akademik sorumluluklarını zamanında yerine getirme ve öz-düzenleme konusunda başarılıdır.\n\n";
    } else if (totalScore <= 120) {
      advice +=
          "Bireyde 'durumsal erteleme' gözlemlenmektedir. Özellikle zorlandığı veya sevmediği derslerde erteleme eğilimi artmaktadır.\n\n";
    } else {
      advice +=
          "Bireyde kronikleşme eğilimi gösteren akademik erteleme davranışı mevcuttur. Bu durum akademik başarıyı ve ruh sağlığını tehdit etmektedir.\n\n";
    }

    advice += "B. Temel Kaynak Analizi\n";
    if (initiation > 15) {
      advice +=
          "- En temel sorun 'başlama' evresindedir. İlk adımı atmak dağ gibi büyümektedir.\n";
    }
    if (emotional > 15) {
      advice +=
          "- Erteleme bir 'duygu düzenleme' stratejisidir. Birey, çalışmanın yarattığı kaygıdan kaçmak için ertelemektedir.\n";
    }
    if (perfectionism > 15) {
      advice +=
          "- 'Ya hep ya hiç' düşüncesi ve hata yapma korkusu eyleme geçmeyi engellemektedir.\n";
    }
    if (management > 15) {
      advice +=
          "- Teknik bir planlama ve zamanı yapılandırma eksikliği söz konusudur.\n";
    }
    if (motivation > 15) {
      advice +=
          "- Hedeflerin belirsizliği veya akademik amaçların birey için anlam ifade etmemesi ertelemeyi tetiklemektedir.\n";
    }

    advice += "\nC. Aksiyon Planı Önerileri\n";
    advice +=
        "1. '5 Dakika Kuralı': Bir işe sadece 5 dakika odaklanmak üzere başlama egzersizleri yapılmalıdır.\n";
    if (perfectionism > 15) {
      advice +=
          "2. Mükemmeliyetçilik yerine 'yeterince iyi' kavramı üzerine çalışılmalıdır.\n";
    }
    if (management > 15) {
      advice +=
          "3. Pomodoro tekniği veya görsel çalışma takvimleri ile zaman somutlaştırılmalıdır.\n";
    }
    if (emotional > 15) {
      advice +=
          "4. Çalışmaya başlamadan önce hissedilen direncin duygusal kaynağı fark edilmelidir.\n";
    }

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
            subtitle: Text('Puan: ${stats['total']?.toInt()} / 216'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showStudentDetail(name, stats),
          ),
        );
      },
    );
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
                color: Colors.indigo,
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
                    _buildScoreOverview(
                      stats['total'] ?? 0,
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
        'initiation': 24,
        'emotional': 24,
        'cognitive': 24,
        'perfectionism': 24,
        'management': 24,
        'motivation': 24,
      };

      final pdfBytes = await pdfService.generateSurveyReportPdf(
        title: 'Akademik Erteleme Ölçeği (AEÖ)',
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
        name: 'AEO_Rapor',
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
      var sheet = excel['AEO Sonuçları'];
      sheet.appendRow([
        TextCellValue('Öğrenci Adı'),
        TextCellValue('Toplam Puan'),
        TextCellValue('Başlama Güçlüğü'),
        TextCellValue('Duygusal Kaçınma'),
        TextCellValue('Bilişsel Gerekçeler'),
        TextCellValue('Mükemmeliyetçilik'),
        TextCellValue('Zaman Yönetimi'),
        TextCellValue('Motivasyon'),
      ]);

      for (var r in filtered) {
        final name = widget.userNames[r['userId']] ?? 'Bilinmeyen';
        final stats = _calculateStudentStats(r);
        sheet.appendRow([
          TextCellValue(name),
          DoubleCellValue(stats['total'] ?? 0),
          DoubleCellValue(stats['initiation'] ?? 0),
          DoubleCellValue(stats['emotional'] ?? 0),
          DoubleCellValue(stats['cognitive'] ?? 0),
          DoubleCellValue(stats['perfectionism'] ?? 0),
          DoubleCellValue(stats['management'] ?? 0),
          DoubleCellValue(stats['motivation'] ?? 0),
        ]);
      }

      var fileBytes = excel.save();
      if (fileBytes != null) {
        await FileSaver.instance.saveFile(
          name: 'AEO_Excel_Rapor',
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
