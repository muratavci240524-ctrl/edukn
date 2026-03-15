import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/survey_model.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../../services/pdf_service.dart';

class AcademicResilienceReport extends StatefulWidget {
  final Survey survey;
  final List<Map<String, dynamic>> responses;
  final Map<String, String> userNames;

  const AcademicResilienceReport({
    Key? key,
    required this.survey,
    required this.responses,
    required this.userNames,
  }) : super(key: key);

  @override
  State<AcademicResilienceReport> createState() =>
      _AcademicResilienceReportState();
}

class _AcademicResilienceReportState extends State<AcademicResilienceReport>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedScope = 'institution';
  String? _selectedBranch;
  String? _selectedStudent;

  final Map<String, List<int>> _categories = {
    'persist': [1, 2, 3, 4, 5, 6, 7, 8],
    'recover': [9, 10, 11, 12, 13, 14, 15, 16],
    'effort': [17, 18, 19, 20, 21, 22, 23, 24],
    'flexibility': [25, 26, 27, 28, 29, 30, 31, 32],
    'quit': [33, 34, 35, 36, 37, 38, 39, 40],
    'awareness': [41, 42, 43, 44, 45, 46, 47, 48],
  };

  final Map<String, String> _categoryNames = {
    'persist': 'Zorlukta Devam Etme',
    'recover': 'Hata Sonrası Toparlanma',
    'effort': 'Çaba Sürekliliği',
    'flexibility': 'Akademik Esneklik',
    'quit': 'Geri Çekilmeme',
  };

  final List<int> _reverseItems = [
    5,
    7,
    13,
    15,
    21,
    23,
    29,
    30,
    37,
    40,
    42,
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

        // All indicators in 'persist', 'recover', 'effort', 'flexibility', 'quit' initially treat agreement as LOW resilience
        // UNLESS it's a 'Ters' item which means agreement is HIGH resilience.
        // Wait, the user prompt says:
        // 1. Zor bir dersle karşılaştığımda çalışmayı bırakırım. (Agreement = Low Resilience)
        // 5. Zor bir görev beni daha çok motive eder. (Ters) (Agreement = High Resilience)
        // So for standard items: 0->4, 1->3, 2->2, 3->1, 4->0 (Lower score for agreement)
        // For reverse items: 0->0, 1->1, 2->2, 3->3, 4->4 (Higher score for agreement)

        if (_reverseItems.contains(idx)) {
          // Stay as is (High agreement = High resilience)
        } else {
          val = 4 - val; // Reverse (High agreement = Low resilience)
        }
        catTotal += val;
      }
      stats[cat] = catTotal;
      if (cat != 'awareness') grandTotal += catTotal;
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
          _buildResilienceOverview(averages, count, indecisiveRatio),
          const SizedBox(height: 24),
          _buildRadarChart(averages),
          const SizedBox(height: 24),
          _buildInterpretation(averages),
        ],
      ),
    );
  }

  Widget _buildResilienceOverview(
    Map<String, double> averages,
    int count,
    double indecisiveRatio,
  ) {
    final total = averages['total'] ?? 0;
    String level;
    Color color;

    // Max score: 5 categories * 8 items * 4 points = 160
    if (total >= 120) {
      level = 'Yüksek Dayanıklılık';
      color = Colors.green;
    } else if (total >= 80) {
      level = 'Dengeli Dayanıklılık';
      color = Colors.blue;
    } else if (total >= 50) {
      level = 'Geliştirilebilir Dayanıklılık';
      color = Colors.orange;
    } else {
      level = 'Düşük Dayanıklılık';
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
              'Akademik Dayanıklılık Göstergesi',
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
                  'Ort. Puan',
                  '${total.toStringAsFixed(1)} / 160',
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
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Durumsal Dayanıklılık: Kararsız yanıtlarınızın yüksekliği, dayanıklılığınızın ders türüne veya döneme göre çok değişkenlik gösterdiğini işaret ediyor.',
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
      return (score / 32.0) * 100; // Each cat has 8 items
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
            'Akademik Dayanıklılık Boyutları (%)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: RadarChart(
              RadarChartData(
                dataSets: [
                  RadarDataSet(
                    fillColor: Colors.teal.withOpacity(0.2),
                    borderColor: Colors.teal,
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
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.teal.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield, color: Colors.blue, size: 24),
              const SizedBox(width: 8),
              Text(
                'Psikolojik Dayanıklılık Analizi',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
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
              color: Colors.teal.shade900,
            ),
          ),
        ],
      ),
    );
  }

  String _generateAdviceString(Map<String, double> averages) {
    final persist = averages['persist'] ?? 0;
    final recover = averages['recover'] ?? 0;
    final effort = averages['effort'] ?? 0;
    final flexibility = averages['flexibility'] ?? 0;
    final quit = averages['quit'] ?? 0;

    String advice = "AKADEMİK DAYANIKLILIK ANALİZ RAPORU\n\n";

    if (recover < 12 && effort > 20) {
      advice +=
          "ÖZEL TESPİT: 'Yorgun Savaşçı'. Yoğun çaba gösteriyorsunuz ancak hata yaptığınızda toparlanmakta çok zorlanıyorsunuz. Hataları kişisel bir yenilgi olarak değil, teknik bir veri olarak görmeye odaklanmalısınız.\n\n";
    }

    if (persist < 12 && flexibility > 20) {
      advice +=
          "ÖZEL TESPİT: 'Esnek Ama Kırılgan'. Yeni yollar denemeye açıksınız ancak gerçek bir zorlukla karşılaştığınızda motivasyonunuz hızla düşebiliyor. 'Zorluk' anını bir durma noktası değil, vites yükseltme anı olarak tanımlamalıyız.\n\n";
    }

    advice += "1. Mevcut Durum Analizi\n";
    final scores = {
      'Zorlukta Devam Etme': persist,
      'Toparlanma Hızı': recover,
      'Çaba Sürekliliği': effort,
      'Akademik Esneklik': flexibility,
      'Vazgeçmeme': quit,
    };
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    advice +=
        "En güçlü alanınız: ${sorted[0].key}. En çok desteklenmesi gereken alan: ${sorted.last.key}.\n\n";

    advice += "2. Somut Gelişim Önerileri\n";
    if (sorted.last.key == 'Toparlanma Hızı') {
      advice +=
          "- 'Hata Analizi' yapın: Neyi yanlış yaptım? Neyi farklı yapabilirim? Sorularına odaklanarak duygularınızdan sıyrılın.\n- Başarısızlık sonrası 15 dakikalık bir yas süresi verin ve ardından küçük bir eylemle (bir paragraf okumak gibi) geri dönün.\n";
    } else if (sorted.last.key == 'Zorlukta Devam Etme') {
      advice +=
          "- Büyük görevleri 15'er dakikalık mini parçalara bölün.\n- 'Zorlanıyorum, öyleyse beynim gelişiyor' mantrasını benimseyin.\n";
    } else if (sorted.last.key == 'Vazgeçmeme') {
      advice +=
          "- Neden başladığınızı hatırlatan bir vizyon panosu oluşturun.\n- Bir konuyu bırakmak üzereyken 'sadece 5 dakika daha' kuralını uygulayın.\n";
    } else {
      advice +=
          "- Farklı çalışma yöntemlerini (video izleme, özet çıkarma, anlatma) dönüşümlü kullanın.\n- Beklenmedik durumlar için 'B Planı' oluşturma egzersizleri yapın.\n";
    }

    advice += "\n3. Rehberlik Notu\n";
    advice +=
        "Dayanıklılık doğuştan gelen bir yetenek değil, öğrenilen bir kas becerisidir. Bugün zorlandığınız her an, akademik bağışıklık sisteminizi güçlendirmektedir.\n";

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
            subtitle: Text('Genel Puan: ${stats['total']?.toInt()} / 160'),
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
                color: Colors.teal,
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
                    _buildResilienceOverview(
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
        'persist': 32,
        'recover': 32,
        'effort': 32,
        'flexibility': 32,
        'quit': 32,
      };

      final pdfBytes = await pdfService.generateSurveyReportPdf(
        title: 'Akademik Dayanıklılık Ölçeği (ADÖ)',
        subTitle: subTitle,
        averages: Map.from(averages)
          ..remove('total')
          ..remove('indecisiveRatio')
          ..remove('awareness'),
        categoryNames: _categoryNames,
        categoryMax: categoryMax,
        respondentCount: count,
        advice: _generateAdviceString(averages),
      );

      await FileSaver.instance.saveFile(
        name: 'Akademik_Dayanıklılık_Rapor',
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
      var sheet = excel['Akademik Dayanıklılık'];
      sheet.appendRow([
        TextCellValue('Öğrenci Adı'),
        TextCellValue('Zorlukta Devam'),
        TextCellValue('Toparlanma'),
        TextCellValue('Çaba'),
        TextCellValue('Esneklik'),
        TextCellValue('Geri Çekilmeme'),
        TextCellValue('Toplam Puan'),
      ]);

      for (var r in filtered) {
        final name = widget.userNames[r['userId']] ?? 'Bilinmeyen';
        final stats = _calculateStudentStats(r);
        sheet.appendRow([
          TextCellValue(name),
          DoubleCellValue(stats['persist'] ?? 0),
          DoubleCellValue(stats['recover'] ?? 0),
          DoubleCellValue(stats['effort'] ?? 0),
          DoubleCellValue(stats['flexibility'] ?? 0),
          DoubleCellValue(stats['quit'] ?? 0),
          DoubleCellValue(stats['total'] ?? 0),
        ]);
      }

      var fileBytes = excel.save();
      if (fileBytes != null) {
        await FileSaver.instance.saveFile(
          name: 'Akademik_Dayanıklılık_Excel',
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
