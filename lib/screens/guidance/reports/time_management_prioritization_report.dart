import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/survey_model.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../../services/pdf_service.dart';

class TimeManagementPrioritizationReport extends StatefulWidget {
  final Survey survey;
  final List<Map<String, dynamic>> responses;
  final Map<String, String> userNames;

  const TimeManagementPrioritizationReport({
    Key? key,
    required this.survey,
    required this.responses,
    required this.userNames,
  }) : super(key: key);

  @override
  State<TimeManagementPrioritizationReport> createState() =>
      _TimeManagementPrioritizationReportState();
}

class _TimeManagementPrioritizationReportState
    extends State<TimeManagementPrioritizationReport>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedScope = 'institution';
  String? _selectedBranch;
  String? _selectedStudent;

  final Map<String, List<int>> _categories = {
    'awareness': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
    'planning': [11, 12, 13, 14, 15, 16, 17, 18, 19, 20],
    'priority': [21, 22, 23, 24, 25, 26, 27, 28, 29, 30],
    'procrastination': [31, 32, 33, 34, 35, 36, 37, 38, 39, 40],
    'protection': [41, 42, 43, 44, 45, 46, 47, 48, 49, 50],
    'pressure': [
      51,
      52,
      53,
      54,
      55,
      56,
      57,
      58,
      59,
      60,
      61,
      62,
      63,
      64,
      65,
      66,
    ],
  };

  final Map<String, String> _categoryNames = {
    'awareness': 'Zaman Farkındalığı',
    'planning': 'Planlama Kapasitesi',
    'priority': 'Önceliklendirme',
    'procrastination': 'Erteleme Yönetimi',
    'protection': 'Zamanı Koruma',
    'pressure': 'Baskı Yönetimi',
  };

  final List<int> _reverseItems = [
    3, 6, 8, 10, // A
    13, 15, 17, 19, // B
    22, 24, 27, 29, 30, // C
    31, 32, 33, 36, 38, // D
    42, 44, 46, 48, // E
    51, 52, 53, 56, 58, 60, 62, 64, // F
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
      _branches = branchesSnap.docs
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
            indicatorColor: Colors.cyan,
            indicatorWeight: 3,
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Zaman Analizi'),
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
                    selectedBackgroundColor: Colors.cyan.shade50,
                    selectedForegroundColor: Colors.cyan,
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
                items: widget.responses
                    .map((r) => _userDetails[r['userId']]?['branch'])
                    .where((b) => b != null)
                    .toSet()
                    .map((branchId) {
                      final branch = _branches.firstWhere(
                        (b) => b['id'] == branchId,
                        orElse: () => {'name': branchId},
                      );
                      return DropdownMenuItem(
                        value: branchId,
                        child: Text(branch['name'] ?? 'Adsız'),
                      );
                    })
                    .toList(),
                onChanged: (val) => setState(() => _selectedBranch = val),
              ),
            if (_selectedScope == 'student')
              _buildDropdownFilter(
                label: 'Öğrenci Seç',
                value: _selectedStudent,
                items: widget.responses.map((r) {
                  final uid = r['userId'].toString();
                  return DropdownMenuItem(
                    value: uid,
                    child: Text(widget.userNames[uid] ?? uid),
                  );
                }).toList(),
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
            borderSide: BorderSide(color: Colors.cyan, width: 2),
          ),
        ),
        isExpanded: true,
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  List<Map<String, dynamic>> _getFilteredResponses() {
    return widget.responses.where((r) {
      if (_selectedScope == 'student')
        return _selectedStudent == null || r['userId'] == _selectedStudent;
      if (_selectedScope == 'branch')
        return _selectedBranch == null ||
            _userDetails[r['userId']]?['branch'] == _selectedBranch;
      return true;
    }).toList();
  }

  Map<String, double> _calculateAverages(List<Map<String, dynamic>> responses) {
    if (responses.isEmpty) return {};
    Map<String, double> totals = {};
    for (var r in responses) {
      final stats = _calculateStudentStats(r);
      stats.forEach((key, value) => totals[key] = (totals[key] ?? 0) + value);
    }
    totals.forEach((key, value) => totals[key] = value / responses.length);
    return totals;
  }

  Map<String, double> _calculateStudentStats(Map<String, dynamic> response) {
    final answers = response['answers'] as Map<String, dynamic>? ?? {};
    Map<String, double> stats = {};

    _categories.forEach((cat, qIndices) {
      double catTotal = 0;
      for (var idx in qIndices) {
        final valStr = answers['q$idx']?.toString() ?? 'Hiç Uygun Değil';
        double val = _getOptionValue(valStr);

        catTotal += _reverseItems.contains(idx) ? (4.0 - val) : val;
      }
      stats[cat] = catTotal;
    });
    return stats;
  }

  double _getOptionValue(String option) {
    switch (option) {
      case 'Hiç Uygun Değil':
        return 0;
      case 'Az Uygun':
        return 1;
      case 'Kısmen Uygun':
        return 2;
      case 'Oldukça Uygun':
        return 3;
      case 'Tamamen Uygun':
        return 4;
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
          _buildOverviewCard(averages, count),
          const SizedBox(height: 24),
          _buildRadarChart(averages),
          const SizedBox(height: 24),
          _buildInterpretation(averages),
        ],
      ),
    );
  }

  Widget _buildOverviewCard(Map<String, double> averages, int count) {
    final efficiency =
        (averages['planning'] ?? 0) + (averages['priority'] ?? 0);
    final leaks = 80 - efficiency;

    String profile;
    Color color;
    if (efficiency > 65) {
      profile = 'Usta Zaman Yöneticisi';
      color = Colors.green;
    } else if (averages['procrastination']! < 15) {
      profile = 'Yoğun Erteleme / Kriz Yönetimiyle Yaşayan';
      color = Colors.red;
    } else if (averages['protection']! < 15) {
      profile = 'Bölünmüş Zamanlar / Dış Odaklı';
      color = Colors.orange;
    } else {
      profile = 'Potansiyelli Ama Sistemsiz Zamancı';
      color = Colors.cyan;
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              'Zaman Yönetim Kapasitesi',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              profile,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Yanıt Sayısı', count.toString()),
                _buildStatItem(
                  'Verimlilik / 80',
                  efficiency.toStringAsFixed(1),
                ),
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
      final max = _categories[cat]!.length * 4.0;
      return (score / max) * 100;
    }).toList();

    return Container(
      height: 400,
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
            'Zaman Yönetimi 6 Eksenli Analiz (%)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: RadarChart(
              RadarChartData(
                dataSets: [
                  RadarDataSet(
                    fillColor: Colors.cyan.withOpacity(0.2),
                    borderColor: Colors.cyan,
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
        color: Colors.cyan.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.cyan.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.hourglass_empty,
                color: Colors.cyan.shade800,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Zaman ve Verimlilik Stratejisi',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.cyan.shade900,
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
              color: Colors.cyan.shade900,
            ),
          ),
        ],
      ),
    );
  }

  String _generateAdviceString(Map<String, double> averages) {
    final awareness = averages['awareness'] ?? 0;
    final planning = averages['planning'] ?? 0;
    final priority = averages['priority'] ?? 0;
    final procrastination = averages['procrastination'] ?? 0;
    final protection = averages['protection'] ?? 0;
    final pressure = averages['pressure'] ?? 0;

    String advice = "ZAMAN YÖNETİMİ VE ÖNCELİKLENDİRME ANALİZİ\n\n";

    if (awareness > 30 && planning < 20) {
      advice +=
          "KRİTİK TESPİT: 'Farkında Ama Akışsız'. Zamanın geçtiğinin ve boşa harcadığınızın farkındasınız ancak bu farkındalığı somut bir plana ('Planlama Kapasitesi') dönüştüremiyorsunuz. Bu durum, gün sonunda yüksek stres ve suçluluk hissetmenize neden olabilir.\n\n";
    }

    if (procrastination < 15) {
      advice +=
          "ÖZEL ANALİZ: 'Erteleme Döngüsü'. İşlere başlamayı sürekli geciktiriyorsunuz. Bu durum sadece bir 'tembellik' değil, genellikle başarısızlık korkusu veya işin büyüklüğünden duyulan kaygıdan kaynaklanır. Erteleme sonucunda oluşan zaman baskısı ise performansınızı kilitliyor olabilir.\n\n";
    }

    advice += "1. Zaman Yönetimi ve Verimlilik Profiliniz\n";
    final scores = {
      'Zaman Farkındalığı': awareness,
      'Planlama Gücü': planning,
      'Önceliklendirme': priority,
      'Erteleme Yönetimi': procrastination,
      'Zaman Koruma': protection,
      'Baskı Yönetimi': pressure,
    };
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    advice +=
        "En güçlü zaman beceriniz: ${sorted[0].key}. En çok 'zaman sızıntısı' yaşanan alan: ${sorted.last.key}.\n\n";

    advice += "2. Zamanı Geri Kazanma Önerileri\n";
    if (priority < 25) {
      advice +=
          "- 'Eisenhower Matrisi'ni kullanın. İşlerinizi 'Acil-Önemli' ayrımına göre gruplandırın. Her gün mutlaka 'Önemli ama Acil Olmayan' bir işi bitirmeye odaklanın.\n- Zor ve önemli işleri, enerjinizin en yüksek olduğu saatlere (genelde sabah) yerleştirin.\n";
    } else if (protection < 25) {
      advice +=
          "- 'Zaman Blokları' oluşturun. Belirli saatler arasında telefonunuzu uzaklaştırın ve sadece tek bir işle ilgilenin. Bölünen her 1 dakika, odaklanmak için kaybedilen 10 dakika demektir.\n- Hayır demeyi öğrenin; başkalarının öncelikleri sizin zamanınızı çalmasın.\n";
    } else if (procrastination < 25) {
      advice +=
          "- '5 Saniye Kuralı'nı uygulayın. Bir işe başlamanız gerektiğini düşündüğünüz an 5'ten geriye sayın ve sayma bittiğinde hemen harekete geçin.\n- Mükemmeliyetçiliği bırakın; 'tamamlanmış' bir iş, 'mükemmel' bir yarım işten daha iyidir.\n";
    }

    advice += "\n3. Rehberlik ve Destek Yaklaşımı (Veli & Öğretmen)\n";
    if (pressure < 25) {
      advice +=
          "Öğrenci zaman baskısı altında panikliyor. Ona 'hadi yetiştir' demek yerine, kalan süreyi parçalara ayırmasını ve sadece önündeki bir sonraki adıma odaklanmasını hatırlatın. Kaygısını yönetmesi performansı için kritiktir.\n";
    } else if (planning < 20) {
      advice +=
          "Öğrenciye sabit ve katı programlar vermek yerine, her gün için 'olmazsa olmaz 3 ana görev' belirleyerek işe başlamasını sağlayın. Planlı olmanın ona 'özgürlük' kazandırdığını fark etmesine yardımcı olun.\n";
    } else {
      advice +=
          "Öğrenci zamanını yönetme konusunda iyi bir temele sahip. Ona daha uzun dönemli (aylık, dönemlik) planlar yapması için vizyon danışmanlığı verilebilir.\n";
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
              'Planlama: ${stats['planning']?.toInt()} | Öncelik: ${stats['priority']?.toInt()} | Erteleme: ${stats['procrastination']?.toInt()}',
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
                color: Colors.cyan,
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
                    _buildOverviewCard(stats, 1),
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
          : "Kurumsal Analiz";

      final categoryMax = {
        'awareness': 40,
        'planning': 40,
        'priority': 40,
        'procrastination': 40,
        'protection': 40,
        'pressure': 64,
      };

      final pdfBytes = await pdfService.generateSurveyReportPdf(
        title: 'Zaman Yönetimi ve Önceliklendirme Becerileri Ölçeği (ZYÖ-PBÖ)',
        subTitle: subTitle,
        averages: averages,
        categoryNames: _categoryNames,
        categoryMax: categoryMax,
        respondentCount: count,
        advice: _generateAdviceString(averages),
      );

      await FileSaver.instance.saveFile(
        name: 'ZYOPBO_Rapor',
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
      var sheet = excel['Zaman Analizi'];
      sheet.appendRow([
        TextCellValue('Öğrenci Adı'),
        TextCellValue('Farkındalık'),
        TextCellValue('Planlama'),
        TextCellValue('Önceliklendirme'),
        TextCellValue('Erteleme'),
        TextCellValue('Zamanı Koruma'),
        TextCellValue('Baskı Yönetimi'),
      ]);
      for (var r in filtered) {
        final stats = _calculateStudentStats(r);
        sheet.appendRow([
          TextCellValue(widget.userNames[r['userId']] ?? 'Bilinmeyen'),
          DoubleCellValue(stats['awareness'] ?? 0),
          DoubleCellValue(stats['planning'] ?? 0),
          DoubleCellValue(stats['priority'] ?? 0),
          DoubleCellValue(stats['procrastination'] ?? 0),
          DoubleCellValue(stats['protection'] ?? 0),
          DoubleCellValue(stats['pressure'] ?? 0),
        ]);
      }
      var b = excel.save();
      if (b != null)
        await FileSaver.instance.saveFile(
          name: 'ZYOPBO_Excel',
          bytes: Uint8List.fromList(b),
          ext: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
    } catch (e) {
      print('Excel error: $e');
    }
  }
}
