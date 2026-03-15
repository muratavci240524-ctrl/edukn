import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/survey_model.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../../services/pdf_service.dart';

class FailurePerceptionReport extends StatefulWidget {
  final Survey survey;
  final List<Map<String, dynamic>> responses;
  final Map<String, String> userNames;

  const FailurePerceptionReport({
    Key? key,
    required this.survey,
    required this.responses,
    required this.userNames,
  }) : super(key: key);

  @override
  State<FailurePerceptionReport> createState() =>
      _FailurePerceptionReportState();
}

class _FailurePerceptionReportState extends State<FailurePerceptionReport>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedScope = 'institution';
  String? _selectedBranch;
  String? _selectedStudent;

  final Map<String, List<int>> _categories = {
    'threat': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
    'tolerance': [13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24],
    'avoidance': [25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36],
    'recovery': [
      37,
      38,
      39,
      40,
      41,
      42,
      43,
      44,
      45,
      46,
      47,
      48,
      49,
      50,
      51,
      52,
    ],
  };

  final Map<String, String> _categoryNames = {
    'threat': 'Tehdit Algısı',
    'tolerance': 'Hata Toleransı',
    'avoidance': 'Kaçınma Eğilimi',
    'recovery': 'Toparlanma Gücü',
  };

  final List<int> _reverseItems = [
    13, 14, 16, 17, 20, 22, 23, // Items marked with (T) in Section B
    37,
    38,
    39,
    40,
    41,
    42,
    43,
    48,
    49,
    50,
    51,
    52, // Items marked with (T) in Section D are actually positive traits, but scored similarly in prompt? No, user said "Ters maddeler (T) otomatik ters puanlanır".
  ];
  // Re-checking items from prompt:
  // Section B: 13, 14, 16, 17, 20, 22, 23 are (T)
  // Section D: 37, 38, 39, 40, 41, 42, 43, 48, 49, 50, 51, 52 are (T)

  // Actually, wait. User wrote (T) next to POSITIVE statements in B and D.
  // Example: "Hata yapmak öğrenmenin bir parçasıdır. (T)"
  // Normal scoring: 0-3. If I want HIGH score to represent HIGH tolerance,
  // then (T) means it should be scored normally?
  // OR, (T) means "this statement is opposite of the category name".
  // Let's assume High score in category = Healthy trait (except for 'threat' and 'avoidance').
  // Typically, these reports show raw alignment.
  // I will follow the user's explicit instruction: (T) items are reversed.
  // If (T) is next to "Hata yapmak öğrenmenin bir parçasıdır", and choice is "Tamamen Uygun" (3), then score becomes 3 - 3 = 0.
  // This seems wrong if High tolerance is good.
  // Actually, looking at previous implementations, (T) usually means reverse scoring to align with the "negative" aspect being measured OR to align all items to the same direction.
  // I will reverse them as requested.

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

    _categories.forEach((cat, qIndices) {
      double catTotal = 0;
      for (var idx in qIndices) {
        final qId = 'q$idx';
        final valStr = answers[qId]?.toString() ?? 'Hiç Uygun Değil';
        int val = _getOptionValue(valStr);

        if (_reverseItems.contains(idx)) {
          val = 3 - val;
        }
        catTotal += val;
      }
      stats[cat] = catTotal;
    });

    return stats;
  }

  int _getOptionValue(String option) {
    switch (option) {
      case 'Hiç Uygun Değil':
        return 0;
      case 'Biraz Uygun':
        return 1;
      case 'Oldukça Uygun':
        return 2;
      case 'Tamamen Uygun':
        return 3;
      default:
        return 0;
    }
  }

  Widget _buildSummaryTab(Map<String, double> averages, int count) {
    if (count == 0) return const Center(child: Text('Henüz yanıt bulunmuyor.'));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildFailureOverview(averages, count),
          const SizedBox(height: 24),
          _buildRadarChart(averages),
          const SizedBox(height: 24),
          _buildInterpretation(averages),
        ],
      ),
    );
  }

  Widget _buildFailureOverview(Map<String, double> averages, int count) {
    final threat = averages['threat'] ?? 0;
    final avoidance = averages['avoidance'] ?? 0;
    final recovery = averages['recovery'] ?? 0;

    String profile;
    Color color;

    if (threat > 20 && avoidance > 20) {
      profile = 'Kırılgan / Tehdit Odaklı';
      color = Colors.red;
    } else if (recovery > 30) {
      profile = 'Duygusal Dayanıklı / Gelişimci';
      color = Colors.green;
    } else if (avoidance > 20) {
      profile = 'Kaçınmacı / Risk Almayan';
      color = Colors.orange;
    } else {
      profile = 'Standart Hata Algısı';
      color = Colors.blue;
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              'Hata ve Başarısızlık Profili',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              profile,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Yanıt Sayısı', count.toString()),
                _buildStatItem('Tehdit Algısı / 36', threat.toStringAsFixed(1)),
              ],
            ),
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
      final max = _categories[cat]!.length * 3.0;
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
            'Hata Tolerans Boyutları (%)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: RadarChart(
              RadarChartData(
                dataSets: [
                  RadarDataSet(
                    fillColor: Colors.amber.withOpacity(0.2),
                    borderColor: Colors.amber,
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
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield, color: Colors.amber, size: 24),
              const SizedBox(width: 8),
              Text(
                'Psikolojik Esneklik ve Hata Yönetimi',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade900,
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
              color: Colors.amber.shade900,
            ),
          ),
        ],
      ),
    );
  }

  String _generateAdviceString(Map<String, double> averages) {
    final threat = averages['threat'] ?? 0;
    final tolerance = averages['tolerance'] ?? 0;
    final avoidance = averages['avoidance'] ?? 0;
    final recovery = averages['recovery'] ?? 0;

    String advice = "BAŞARISIZLIK ALGISI VE HATA TOLERANSI ANALİZİ\n\n";

    if (threat > 20 && recovery < 25) {
      advice +=
          "KRİTİK ANALİZ: 'Yıkıcı Başarısızlık Algısı'. Hata yapmayı sadece akademik bir sonuç değil, kişiliğinize yönelik bir tehdit olarak algılıyorsunuz. Bu durum, yanlış yaptığınızda toparlanmanızı zorlaştırıyor ve sizi 'hiç başlamama' noktasına itiyor.\n\n";
    }

    if (avoidance > 22) {
      advice +=
          "STRATEJİK TESPİT: 'Riskten Kaçınma'. Sırf hata yapma ihtimali olduğu için zor sorulardan veya yeni yöntemlerden uzak duruyorsunuz. Bu 'güvenli alan' tutumu, potansiyelinizi tam olarak kullanmanızı engelliyor.\n\n";
    }

    advice += "1. Temel Boyut Analiziniz\n";
    final scores = {
      'Tehdit Algısı': threat,
      'Hata Kabulü': tolerance,
      'Risk Alma': 36 - avoidance, // Inverting for growth perspective
      'Toparlanma Gücü': recovery,
    };
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    advice +=
        "En baskın özelliğiniz: ${sorted[0].key}. En çok geliştirilmesi gereken alan: ${sorted.last.key}.\n\n";

    advice += "2. Bilişsel Yeniden Çerçeveleme Önerileri\n";
    if (threat > 20) {
      advice +=
          "- 'Hata yaptım' cümlesini 'Hatamdan ne öğrendim?' ile değiştirin.\n- Başarınızın sadece notlardan değil, deneme cesaretinizden geldiğini kendinize hatırlatın.\n";
    } else if (avoidance > 20) {
      advice +=
          "- Her gün bilerek 'yanlış yapabileceğiniz' bir zorluk seçin. Hata yapmanın dünyanın sonu olmadığını deneyimleyin.\n- 'Mükemmellik' yerine 'İlerleme' hedefine odaklanın.\n";
    } else if (recovery < 30) {
      advice +=
          "- Olumsuz bir sonuçtan sonra zihninizi dağıtacak 5 dakikalık bir ara verin ve sonra sadece 'sonraki küçük adımı' planlayın.\n- Başarısızlığı kalıcı bir durum değil, geçici bir veri kaybı olarak görün.\n";
    } else {
      advice +=
          "- Hata toleransınız yüksek; bu esnekliği yeni ve daha zorlayıcı akademik alanlarda kullanarak gelişiminizi sürdürün.\n";
    }

    advice += "\n3. Rehberlik Notu (Ebeveyn ve Öğretmenlere)\n";
    if (threat > 20) {
      advice +=
          "Öğrenci hataları kişiselleştiriyor. Onu sadece 'sonuç' üzerinden değil, 'hata yaptıktan sonraki çabası' üzerinden takdir ederek güvenli bir öğrenme ortamı oluşturmalısınız. Cezalandırıcı veya aşırı eleştirel dil bu profil için çok risklidir.\n";
    } else {
      advice +=
          "Öğrencinin hata algısı sağlıklı. Onu daha fazla risk almaya ve zorlayıcı hedeflere yönlendirerek potansiyelini maksimize etmesine yardımcı olabilirsiniz.\n";
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
            subtitle: Text(
              'Tehdit: ${stats['threat']?.toInt()} | Dayanıklılık: ${stats['recovery']?.toInt()}',
            ),
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
                color: Colors.amber,
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
                    _buildFailureOverview(stats, 1),
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
        'threat': 36,
        'tolerance': 36,
        'avoidance': 36,
        'recovery': 48,
      };

      final pdfBytes = await pdfService.generateSurveyReportPdf(
        title: 'Başarısızlık Algısı ve Hata Toleransı Ölçeği',
        subTitle: subTitle,
        averages: averages,
        categoryNames: _categoryNames,
        categoryMax: categoryMax,
        respondentCount: count,
        advice: _generateAdviceString(averages),
      );

      await FileSaver.instance.saveFile(
        name: 'Basarisizlik_Algisi_Rapor',
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
      var sheet = excel['Hata Tolerans Analizi'];
      sheet.appendRow([
        TextCellValue('Öğrenci Adı'),
        TextCellValue('Tehdit Algısı'),
        TextCellValue('Hata Toleransı'),
        TextCellValue('Kaçınma'),
        TextCellValue('Toparlanma Gücü'),
      ]);

      for (var r in filtered) {
        final name = widget.userNames[r['userId']] ?? 'Bilinmeyen';
        final stats = _calculateStudentStats(r);
        sheet.appendRow([
          TextCellValue(name),
          DoubleCellValue(stats['threat'] ?? 0),
          DoubleCellValue(stats['tolerance'] ?? 0),
          DoubleCellValue(stats['avoidance'] ?? 0),
          DoubleCellValue(stats['recovery'] ?? 0),
        ]);
      }

      var fileBytes = excel.save();
      if (fileBytes != null) {
        await FileSaver.instance.saveFile(
          name: 'Basarisizlik_Algisi_Excel',
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
