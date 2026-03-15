import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/survey_model.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../../services/pdf_service.dart';

class SelfRegulationControlReport extends StatefulWidget {
  final Survey survey;
  final List<Map<String, dynamic>> responses;
  final Map<String, String> userNames;

  const SelfRegulationControlReport({
    Key? key,
    required this.survey,
    required this.responses,
    required this.userNames,
  }) : super(key: key);

  @override
  State<SelfRegulationControlReport> createState() =>
      _SelfRegulationControlReportState();
}

class _SelfRegulationControlReportState
    extends State<SelfRegulationControlReport>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedScope = 'institution';
  String? _selectedBranch;
  String? _selectedStudent;

  final Map<String, List<int>> _categories = {
    'goalControl': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
    'impulse': [13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24],
    'emotion': [25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36],
    'sustainability': [37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48],
    'monitoring': [49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60],
    'discipline': [61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72],
  };

  final Map<String, String> _categoryNames = {
    'goalControl': 'Hedef Kontrolü',
    'impulse': 'Dürtü Yönetimi',
    'emotion': 'Duygusal Düzenleme',
    'sustainability': 'İstikrar',
    'monitoring': 'Kendini İzleme',
    'discipline': 'Öz Disiplin',
  };

  final List<int> _reverseItems = [
    2, 4, 6, 8, 10, 12, // A
    14, 16, 18, 20, 22, // B
    26, 28, 30, 32, 34, // C
    38, 40, 42, 44, 47, // D
    50, 52, 54, 58, // E
    62, 64, 66, 68, 70, // F
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
            indicatorColor: Colors.deepPurple,
            indicatorWeight: 3,
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('İrade Analizi'),
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
            borderSide: BorderSide(color: Colors.deepPurple, width: 2),
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
    final score = (averages['discipline'] ?? 0) + (averages['monitoring'] ?? 0);

    String profile;
    Color color;
    if (score > 80) {
      profile = 'Yüksek İrade ve Stratejik Kontrol';
      color = Colors.deepPurple;
    } else if (averages['impulse']! < 20) {
      profile = 'Dürtüsel / Anlık Odaklı';
      color = Colors.red;
    } else if (averages['sustainability']! < 20) {
      profile = 'Hevesli Ama İstikrarsız';
      color = Colors.orange;
    } else {
      profile = 'Gelişen Öz Düzenleme Kapasitesi';
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
              'Öz Kontrol ve Düzenleme Profili',
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
                _buildStatItem('Kontrol Gücü / 96', score.toStringAsFixed(1)),
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
            'Öz Düzenleme Gücü (%)',
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
          Row(
            children: [
              Icon(
                Icons.psychology,
                color: Colors.deepPurple.shade800,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'İrade ve Davranış Kontrol Analizi',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple.shade900,
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
    final goalControl = averages['goalControl'] ?? 0;
    final impulse = averages['impulse'] ?? 0;
    final emotion = averages['emotion'] ?? 0;
    final sustainability = averages['sustainability'] ?? 0;
    final monitoring = averages['monitoring'] ?? 0;
    final discipline = averages['discipline'] ?? 0;

    String advice = "ÖZ DÜZENLEME VE ÖZ KONTROL ANALİZİ\n\n";

    if (impulse < 20 && monitoring > 35) {
      advice +=
          "KRİTİK TESPİT: 'Farkında Ama Durduramıyor'. Hatalarınızın ve dürtüsel davranışlarınızın farkındasınız ancak o an geldiğinde kendinizi frenleme noktasında ('Dürtü Yönetimi') zorlanıyorsunuz. İrade kaslarınızı stratejik çevresel önlemlerle desteklemeniz gerekiyor.\n\n";
    }

    if (emotion < 20) {
      advice +=
          "ÖZEL ANALİZ: 'Duygusal Savrulma'. Duygularınız davranışlarınızın tek belirleyicisi haline gelmiş durumda. Modunuz düşük olduğunda tüm planı iptal etme veya öfkelendiğinizde kontrolü kaybetme eğiliminiz, akademik sürekliliğinizi baltalıyor olabilir.\n\n";
    }

    advice += "1. Öz Kontrol ve İrade Profiliniz\n";
    final scores = {
      'Hedef Kontrolü': goalControl,
      'Dürtü Yönetimi': impulse,
      'Duygusal Düzenleme': emotion,
      'İstikrar': sustainability,
      'Kendini İzleme': monitoring,
      'Öz Disiplin': discipline,
    };
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    advice +=
        "En güçlü içsel denetim alanınız: ${sorted[0].key}. Desteklenmesi gereken zayıf halka: ${sorted.last.key}.\n\n";

    advice += "2. İrade Güçlendirme ve Mikro Stratejiler\n";
    if (impulse < 25) {
      advice +=
          "- 'Eğer-Öyleyse' (If-Then) planları yapın. 'Eğer canım telefonuma bakmak isterse (dürtü), öyleyse 10'a kadar sayıp önümdeki soruyu bitireceğim.'\n- Cezbedici unsurları (telefon, abur cubur vb.) göz önünden kaldırarak irade harcamanızı azaltın.\n";
    } else if (sustainability < 25) {
      advice +=
          "- 'Yüzde 1 Kuralı'nı uygulayın. Her gün planınızın tamamını yapmak yerine, bir önceki günden sadece %1 daha fazla veya daha iyi yapmaya odaklanın. Büyük hevesler yerine küçük rutinler kazandırır.\n- Sürekliliği 'zinciri kırma' yöntemiyle takip edin.\n";
    } else if (emotion < 25) {
      advice +=
          "- 'Duygu Etiketleme' tekniğini kullanın. O an ne hissettiğinizi (stres, kaygı, sıkılma) sadece isimlendirmek bile beyninizin mantıklı kısmını devreye sokar ve kontrolü size verir.\n- Zorlandığınızda 5 dakikalık bir hava değişimi molası verin.\n";
    }

    advice += "\n3. Rehberlik ve Destek Yaklaşımı (Veli & Öğretmen)\n";
    if (discipline < 25) {
      advice +=
          "Öğrenciye 'disiplinsiz' demek yerine, 'kontrol noktası eksikliği' olarak bakın. Ona dışarıdan katı disiplin uygulamak yerine, kendi kurallarını koyması ve bu kurallara uymadığında sonuçlarını görmesi için alan tanıyın.\n";
    } else if (monitoring < 25) {
      advice +=
          "Öğrenci neyi yanlış yaptığını veya neden ilerleyemediğini tam olarak kavramıyor olabilir. Ona objektif gelişim verileri sunarak kendini ayna gibi görmesini sağlayın.\n";
    } else {
      advice +=
          "Öğrenci öz düzenleme konusunda yetkin. Ona daha özerk sorumluluklar vererek liderlik veya mentorluk rollerine hazırlanması sağlanabilir.\n";
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
              'Dürtü: ${stats['impulse']?.toInt()} | İstikrar: ${stats['sustainability']?.toInt()} | Disiplin: ${stats['discipline']?.toInt()}',
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
        'goalControl': 48,
        'impulse': 48,
        'emotion': 48,
        'sustainability': 48,
        'monitoring': 48,
        'discipline': 48,
      };

      final pdfBytes = await pdfService.generateSurveyReportPdf(
        title: 'Öz Düzenleme ve Öz Kontrol Becerileri Ölçeği (ÖD-ÖKÖ)',
        subTitle: subTitle,
        averages: averages,
        categoryNames: _categoryNames,
        categoryMax: categoryMax,
        respondentCount: count,
        advice: _generateAdviceString(averages),
      );

      await FileSaver.instance.saveFile(
        name: 'ODOKO_Rapor',
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
      var sheet = excel['İrade Analizi'];
      sheet.appendRow([
        TextCellValue('Öğrenci Adı'),
        TextCellValue('Hedef Kontrolü'),
        TextCellValue('Dürtü Yönetimi'),
        TextCellValue('Duygusal Düzenleme'),
        TextCellValue('İstikrar'),
        TextCellValue('Kendini İzleme'),
        TextCellValue('Öz Disiplin'),
      ]);
      for (var r in filtered) {
        final stats = _calculateStudentStats(r);
        sheet.appendRow([
          TextCellValue(widget.userNames[r['userId']] ?? 'Bilinmeyen'),
          DoubleCellValue(stats['goalControl'] ?? 0),
          DoubleCellValue(stats['impulse'] ?? 0),
          DoubleCellValue(stats['emotion'] ?? 0),
          DoubleCellValue(stats['sustainability'] ?? 0),
          DoubleCellValue(stats['monitoring'] ?? 0),
          DoubleCellValue(stats['discipline'] ?? 0),
        ]);
      }
      var b = excel.save();
      if (b != null)
        await FileSaver.instance.saveFile(
          name: 'ODOKO_Excel',
          bytes: Uint8List.fromList(b),
          ext: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
    } catch (e) {
      print('Excel error: $e');
    }
  }
}
