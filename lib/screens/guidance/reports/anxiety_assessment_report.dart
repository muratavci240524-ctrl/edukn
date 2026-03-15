import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/survey_model.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../../services/pdf_service.dart';

class AnxietyAssessmentReport extends StatefulWidget {
  final Survey survey;
  final List<Map<String, dynamic>> responses;
  final Map<String, String> userNames;

  const AnxietyAssessmentReport({
    Key? key,
    required this.survey,
    required this.responses,
    required this.userNames,
  }) : super(key: key);

  @override
  State<AnxietyAssessmentReport> createState() =>
      _AnxietyAssessmentReportState();
}

class _AnxietyAssessmentReportState extends State<AnxietyAssessmentReport>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedScope = 'institution';
  String? _selectedBranch;
  String? _selectedStudent;

  final Map<String, List<int>> _categories = {
    'general': List.generate(6, (i) => i + 1), // q1-q6
    'physical': List.generate(6, (i) => i + 7), // q7-q12
    'control': List.generate(6, (i) => i + 13), // q13-q18
    'avoidance': List.generate(6, (i) => i + 19), // q19-q24
    'reassurance': List.generate(6, (i) => i + 25), // q25-q30
    'distress': List.generate(6, (i) => i + 31), // q31-q36
    'masking': List.generate(12, (i) => i + 37), // q37-q48
  };

  final Map<String, String> _categoryNames = {
    'general': 'Sürekli Kaygı ve Endişe',
    'physical': 'Bedensel Gerginlik',
    'control': 'Zihinsel Meşguliyet',
    'avoidance': 'Kaçınma ve Erteleme',
    'reassurance': 'Güven Arama',
    'distress': 'Bunaltı ve İçsel Baskı',
    'masking': 'Kaygıyı Gizleme',
  };

  final List<int> _reverseItems = [3, 9, 16, 24, 29, 34, 43];

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
            indicatorColor: Colors.deepPurple,
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
                    selectedBackgroundColor: Colors.deepPurple.shade50,
                    selectedForegroundColor: Colors.deepPurple,
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
            borderSide: BorderSide(color: Colors.deepPurple, width: 2),
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
      grandTotal += catTotal;
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
    if (score <= 48) {
      level = 'Düşük Kaygı';
      color = Colors.green;
    } else if (score <= 96) {
      level = 'Hafif Risk';
      color = Colors.orange;
    } else if (score <= 144) {
      level = 'Orta Düzey Kaygı';
      color = Colors.deepOrange;
    } else {
      level = 'Yüksek Kaygı / Bunaltı';
      color = Colors.red;
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text('Genel Kaygı Düzeyi', style: TextStyle(fontSize: 16)),
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
                  '${score.toStringAsFixed(1)} / 192',
                ),
                _buildStatItem('Yanıt Sayısı', count.toString()),
              ],
            ),
            if (indecisiveRatio > 30) ...[
              const Divider(height: 32),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Yüksek Kararsızlık Oranı: Kaygıyı fark etmeme, bastırma veya kaçınma olasılığı değerlendirilmelidir.',
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
    final List<String> cats = _categories.keys.toList();
    final data = cats.map((cat) {
      final score = averages[cat] ?? 0;
      final max = cat == 'masking' ? 48.0 : 24.0;
      return (score / max) * 100;
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
            'Kaygı Profili (%)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: RadarChart(
              RadarChartData(
                dataSets: [
                  RadarDataSet(
                    fillColor: Colors.deepPurple.withOpacity(0.2),
                    borderColor: Colors.deepPurple,
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
        color: Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.deepPurple.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.psychology, color: Colors.deepPurple, size: 24),
              SizedBox(width: 8),
              Text(
                'Uzman Analizi ve Değerlendirme',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
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
              color: Colors.deepPurple.shade900,
            ),
          ),
        ],
      ),
    );
  }

  String _generateAdviceString(Map<String, double> averages) {
    final totalScore = averages['total'] ?? 0;
    final general = averages['general'] ?? 0;
    final physical = averages['physical'] ?? 0;
    final control = averages['control'] ?? 0;
    final avoidance = averages['avoidance'] ?? 0;
    final reassurance = averages['reassurance'] ?? 0;
    final distress = averages['distress'] ?? 0;
    final masking = averages['masking'] ?? 0;
    final indecisiveRatio = averages['indecisiveRatio'] ?? 0;

    String advice = "KAYGI VE BUNALTI UZMAN ANALİZ RAPORU\n\n";

    advice += "A. Genel Profil Değerlendirmesi\n";
    if (totalScore <= 48) {
      advice +=
          "Bireyin kaygı düzeyi, günlük yaşamın doğal akışı içindeki 'işlevsel kaygı' sınırlarında yer almaktadır. Psikolojik sağlamlığı ve iç gerilimi yönetme kapasitesi yeterlidir.\n\n";
    } else if (totalScore <= 96) {
      advice +=
          "Analiz sonuçları, hafif düzeyde bir tetikte olma hali ve zihinsel meşguliyete işaret etmektedir. Bu tablo genellikle 'stres altındaki sağlıklı birey' profiline uymaktadır.\n\n";
    } else if (totalScore <= 144) {
      advice +=
          "Bireyin orta düzeyde ve kronikleşme eğiliminde olan bir kaygı örüntüsü içinde olduğu gözlemlenmektedir. Kaygı artık bir uyarıcı olmaktan çıkıp, bireyin enerjisini tüketen bir yüke dönüşmeye başlamıştır.\n\n";
    } else {
      advice +=
          "Birey, çok yüksek seviyede 'akut bunaltı' ve yoğun bir kaygı sarmalı içindedir. Kontrol arayışı ve kaçınma davranışları bireyin hayatını kısıtlamakta, ruhsal bir daralma/sıkışma hissi baskın gelmektedir.\n\n";
    }

    advice += "B. Alt Boyutlara Dayalı Detaylı Analiz\n";
    if (physical > 15 || control > 15 || avoidance > 15) {
      advice += "Profilde özellikle ";
      if (physical > 15) advice += "'bedensel somatizasyon' belirgindir. ";
      if (control > 15) advice += "Zihinsel kontrol ihtiyacı çok yüksektir. ";
      if (avoidance > 15) advice += "Kaçınma stratejileri baskındır. ";
      if (masking > 24)
        advice += "Kaygıyı gizleme eğilimi yardım almayı zorlaştırabilir. ";
      if (indecisiveRatio > 30)
        advice +=
            "Yüksek kararsızlık oranı duygusallığı bastırmayı destekler.\n\n";
      else
        advice += "\n\n";
    } else {
      advice +=
          "Alt boyutlar arasındaki dağılım kaygının yaygın bir gerginlik halini yansıttığını göstermektedir.\n\n";
    }

    advice += "C. Günlük Yaşam ve Akademik/Sosyal Etkilere Yansıma\n";
    if (general > 15 || distress > 15 || reassurance > 15) {
      advice += "Mevcut kaygı düzeyi, bireyin ";
      if (general > 15) advice += "karar verme süreçlerini felç etmektedir. ";
      if (distress > 15) advice += "içsel huzurunu ortadan kaldırmaktadır. ";
      if (reassurance > 15)
        advice += "onay ihtiyacını artırarak özgüvenini zayıflatmaktadır.\n\n";
    } else {
      advice +=
          "Kaygı belirtileri henüz sosyal ve akademik işlevselliği bozacak seviyeye ulaşmamıştır.\n\n";
    }

    advice += "D. Öneriler\n";
    advice +=
        "Bireyin 'belirsizliğe tahammül' ve 'duygusal kabul' çalışmaları yapması önerilir. ";
    if (physical > 12)
      advice +=
          "Gevşeme egzersizleri bedensel gerginliği kırmada etkili olacaktır. ";
    if (avoidance > 12)
      advice += "Kademeli yüzleşme kaçınma döngüsünü kıracaktır.\n\n";

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
            subtitle: Text('Puan: ${stats['total']?.toInt()} / 192'),
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
                color: Colors.deepPurple,
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
        'general': 24,
        'physical': 24,
        'control': 24,
        'avoidance': 24,
        'reassurance': 24,
        'distress': 24,
        'masking': 48,
      };

      final pdfBytes = await pdfService.generateSurveyReportPdf(
        title: 'Kaygı / Bunaltı Değerlendirme Ölçeği (KBDÖ)',
        subTitle: subTitle,
        averages: Map.from(averages)
          ..remove('total')
          ..remove('indecisiveRatio'),
        categoryNames: _categoryNames,
        categoryMax: categoryMax,
        respondentCount: count,
        advice: _generateAdviceString(averages),
      );

      await FileSaver.instance.saveFile(
        name: 'KBDO_Rapor',
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
      var sheet = excel['KBDO Sonuçları'];
      sheet.appendRow([
        TextCellValue('Öğrenci Adı'),
        TextCellValue('Toplam Puan'),
        TextCellValue('Sürekli Kaygı'),
        TextCellValue('Bedensel Gerginlik'),
        TextCellValue('Zihinsel Meşguliyet'),
        TextCellValue('Kaçınma'),
        TextCellValue('Güven Arama'),
        TextCellValue('Bunaltı'),
        TextCellValue('Kaygıyı Gizleme'),
      ]);

      for (var r in filtered) {
        final name = widget.userNames[r['userId']] ?? 'Bilinmeyen';
        final stats = _calculateStudentStats(r);
        sheet.appendRow([
          TextCellValue(name),
          DoubleCellValue(stats['total'] ?? 0),
          DoubleCellValue(stats['general'] ?? 0),
          DoubleCellValue(stats['physical'] ?? 0),
          DoubleCellValue(stats['control'] ?? 0),
          DoubleCellValue(stats['avoidance'] ?? 0),
          DoubleCellValue(stats['reassurance'] ?? 0),
          DoubleCellValue(stats['distress'] ?? 0),
          DoubleCellValue(stats['masking'] ?? 0),
        ]);
      }

      var fileBytes = excel.save();
      if (fileBytes != null) {
        await FileSaver.instance.saveFile(
          name: 'KBDO_Excel_Rapor',
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
