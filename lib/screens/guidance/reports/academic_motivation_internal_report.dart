import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/survey_model.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../../services/pdf_service.dart';

class AcademicMotivationInternalReport extends StatefulWidget {
  final Survey survey;
  final List<Map<String, dynamic>> responses;
  final Map<String, String> userNames;

  const AcademicMotivationInternalReport({
    Key? key,
    required this.survey,
    required this.responses,
    required this.userNames,
  }) : super(key: key);

  @override
  State<AcademicMotivationInternalReport> createState() =>
      _AcademicMotivationInternalReportState();
}

class _AcademicMotivationInternalReportState
    extends State<AcademicMotivationInternalReport>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedScope = 'institution';
  String? _selectedBranch;
  String? _selectedStudent;

  final Map<String, List<int>> _categories = {
    'internal': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
    'external': [12, 13, 14, 15, 16, 17, 18, 19, 20, 21],
    'meaning': [22, 23, 24, 25, 26, 27, 28, 29, 30, 31],
    'attitude': [32, 33, 34, 35, 36, 37, 38, 39, 40, 41],
    'resilience': [42, 43, 44, 45, 46, 47, 48, 49, 50, 51],
    'volunteering': [
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
    'internal': 'İçsel Öğrenme İsteği',
    'external': 'Dışsal Baskı Algısı',
    'meaning': 'Anlam ve Amaç',
    'attitude': 'Başarı Tutumu',
    'resilience': 'Dayanıklılık',
    'volunteering': 'Akademik Gönüllülük',
  };

  final List<int> _reverseItems = [
    2, 4, 6, 8, 10, // A
    14, 17, 18, // B
    23, 25, 27, 29, 31, // C
    33, 35, 37, 39, // D
    43, 45, 47, 50, // E
    53, 55, 57, 59, // F
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
            indicatorColor: Colors.amber.shade700,
            indicatorWeight: 3,
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Motivasyon Analizi'),
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
                    selectedBackgroundColor: Colors.amber.shade50,
                    selectedForegroundColor: Colors.amber.shade900,
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
            borderSide: BorderSide(color: Colors.amber, width: 2),
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
        final valStr = answers['q$idx']?.toString() ?? 'Bana Hiç Uygun Değil';
        double val = _getOptionValue(valStr);

        catTotal += _reverseItems.contains(idx) ? (3.0 - val) : val;
      }
      stats[cat] = catTotal;
    });
    return stats;
  }

  double _getOptionValue(String option) {
    switch (option) {
      case 'Bana Hiç Uygun Değil':
        return 0;
      case 'Bana Az Uygun':
        return 1;
      case 'Bana Uygun':
        return 2;
      case 'Bana Çok Uygun':
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
    final internalIndex =
        (averages['internal'] ?? 0) + (averages['meaning'] ?? 0);
    final externalIndex = averages['external'] ?? 0;

    String profile;
    Color color;
    if (internalIndex > 45 && externalIndex < 15) {
      profile = 'İçsel Güdülenmiş / Otonom Öğrenen';
      color = Colors.green;
    } else if (externalIndex > 20) {
      profile = 'Dışsal Baskı Odaklı / Reaktif';
      color = Colors.red;
    } else if (averages['meaning']! < 10) {
      profile = 'Anlam Arayışında / Amaçsızlık Yaşayan';
      color = Colors.orange;
    } else {
      profile = 'Karma Motivasyon Yapısı';
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
              'Akademik Motivasyon Profili',
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
                  'İçsel Güç / 63',
                  internalIndex.toStringAsFixed(1),
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
      final max = _categories[cat]!.length * 3.0;
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
            'Motivasyonun 6 Boyutu (%)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: RadarChart(
              RadarChartData(
                dataSets: [
                  RadarDataSet(
                    fillColor: Colors.amber.withOpacity(0.2),
                    borderColor: Colors.amber.shade700,
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
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.amber.shade800, size: 24),
              const SizedBox(width: 8),
              Text(
                'İçsel Güdülenme ve Motivasyon Analizi',
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
    final internal = averages['internal'] ?? 0;
    final external = averages['external'] ?? 0;
    final meaning = averages['meaning'] ?? 0;
    final attitude = averages['attitude'] ?? 0;
    final resilience = averages['resilience'] ?? 0;
    final volunteering = averages['volunteering'] ?? 0;

    String advice = "AKADEMİK MOTİVASYON VE İÇSEL GÜDÜLENME ANALİZİ\n\n";

    if (external > 20 && internal < 15) {
      advice +=
          "KRİTİK TESPİT: 'Dışsal Bağımlılık'. Öğrenme süreciniz tamamen dış etkenlere (aile baskısı, not korkusu, ödül) bağlı durumda. Bu durum, baskı kalktığında çalışmanın durmasına ve uzun vadede tükenmişliğe yol açabilir. Kendi 'Neden'inizi bulmanız gerekiyor.\n\n";
    }

    if (meaning < 10) {
      advice +=
          "ÖZEL ANALİZ: 'Anlamsızlık Tuzağı'. Derslerin ve okulun hayatınızla olan bağını kurmakta zorlanıyorsunuz. 'Bunu neden öğreniyorum?' sorusuna cevap bulamadığınız sürece, çalışmak sizin için sadece bir eziyet olarak kalacaktır.\n\n";
    }

    advice += "1. Motivasyonel Yapınız\n";
    final scores = {
      'İçsel İstek': internal,
      'Anlam Algısı': meaning,
      'Başarı Tutumu': attitude,
      'Dayanıklılık': resilience,
      'Gönüllülük': volunteering,
    };
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    advice +=
        "Motivasyonunuzu besleyen en güçlü kanal: ${sorted[0].key}. Geliştirilmesi gereken zayıf halka: ${sorted.last.key}.\n\n";

    advice += "2. İçsel Güdülenmeyi Artırma Stratejileri\n";
    if (meaning < 15) {
      advice +=
          "- 'Bağlamsal Öğrenme' uygulayın. Her dersin sonunda 'Bu gerçek hayatta hangi sorunu çözüyor?' sorusunu sorun. Öğrendiklerinizi bir hobi veya kariyer hedefinizle ilişkilendirin.\n- Bilginin sadece not değil, bir 'güç' olduğunu fark edin.\n";
    } else if (volunteering < 20) {
      advice +=
          "- Otonomi kazanın. Çalışma planınızı başkasının yapmasını beklemeyin; kendi planınızı kendiniz yapın. Kontrolün sizde olması motivasyonu artırır.\n- Küçük sorumluluklar alarak 'kendi kendinin patronu' olma pratiği yapın.\n";
    } else if (resilience < 15) {
      advice +=
          "- Zorluğu bir 'engel' değil, bir 'antrenman' olarak görün. Zor bir konuyu anladığınızda beyninizin fiziksel olarak geliştiğini hatırlayın.\n- 'Gelişim Odaklı Zihniyet' (Growth Mindset) üzerine okumalar yapın.\n";
    }

    advice += "\n3. Rehberlik ve Destek Yaklaşımı (Veli & Öğretmen)\n";
    if (external > 25) {
      advice +=
          "Öğrenci üzerinde çok yoğun bir dış baskı hissediyor olabilir. Ona 'çalış' demek yerine, 'çalışmamanın sana maliyeti ne?' veya 'bu konu senin hangi hedefine hizmet edebilir?' gibi sorularla içsel kontrolünü tetikleyin. Baskıyı azaltın, rehberliği artırın.\n";
    } else if (internal < 15) {
      advice +=
          "Öğrencide öğrenme merakı sönmüş görünüyor. Onu ilgi duyduğu alanlardan yola çıkarak akademik dünyaya çekmeye çalışın. Başarıdan ziyade 'merak' duygusunu ödüllendirin.\n";
    } else {
      advice +=
          "Öğrenci genel olarak içsel güdülenmeye sahip. Ona daha derinlikli projeler ve otonom çalışma alanları sunarak akademik vizyonunu genişletmesi sağlanabilir.\n";
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
              'İçsel: ${stats['internal']?.toInt()} | Anlam: ${stats['meaning']?.toInt()} | Dayanıklılık: ${stats['resilience']?.toInt()}',
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
              decoration: BoxDecoration(
                color: Colors.amber.shade700,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
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
        'internal': 33,
        'external': 30,
        'meaning': 30,
        'attitude': 30,
        'resilience': 30,
        'volunteering': 45,
      };

      final pdfBytes = await pdfService.generateSurveyReportPdf(
        title: 'Akademik Motivasyon ve İçsel Güdülenme Ölçeği (AM-İGÖ)',
        subTitle: subTitle,
        averages: averages,
        categoryNames: _categoryNames,
        categoryMax: categoryMax,
        respondentCount: count,
        advice: _generateAdviceString(averages),
      );

      await FileSaver.instance.saveFile(
        name: 'AMIGO_Rapor',
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
      var sheet = excel['Motivasyon Analizi'];
      sheet.appendRow([
        TextCellValue('Öğrenci Adı'),
        TextCellValue('İçsel İstek'),
        TextCellValue('Dışsal Baskı'),
        TextCellValue('Anlam Algısı'),
        TextCellValue('Başarı Tutumu'),
        TextCellValue('Dayanıklılık'),
        TextCellValue('Gönüllülük'),
      ]);
      for (var r in filtered) {
        final stats = _calculateStudentStats(r);
        sheet.appendRow([
          TextCellValue(widget.userNames[r['userId']] ?? 'Bilinmeyen'),
          DoubleCellValue(stats['internal'] ?? 0),
          DoubleCellValue(stats['external'] ?? 0),
          DoubleCellValue(stats['meaning'] ?? 0),
          DoubleCellValue(stats['attitude'] ?? 0),
          DoubleCellValue(stats['resilience'] ?? 0),
          DoubleCellValue(stats['volunteering'] ?? 0),
        ]);
      }
      var b = excel.save();
      if (b != null)
        await FileSaver.instance.saveFile(
          name: 'AMIGO_Excel',
          bytes: Uint8List.fromList(b),
          ext: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
    } catch (e) {
      print('Excel error: $e');
    }
  }
}
