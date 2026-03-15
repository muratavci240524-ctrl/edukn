import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/survey_model.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../../services/pdf_service.dart';

class AcademicMotivationSourcesReport extends StatefulWidget {
  final Survey survey;
  final List<Map<String, dynamic>> responses;
  final Map<String, String> userNames;

  const AcademicMotivationSourcesReport({
    Key? key,
    required this.survey,
    required this.responses,
    required this.userNames,
  }) : super(key: key);

  @override
  State<AcademicMotivationSourcesReport> createState() =>
      _AcademicMotivationSourcesReportState();
}

class _AcademicMotivationSourcesReportState
    extends State<AcademicMotivationSourcesReport>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedScope = 'institution';
  String? _selectedBranch;
  String? _selectedStudent;

  final Map<String, List<int>> _categories = {
    'intrinsic': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13],
    'extrinsic': [14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25],
    'meaning': [26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37],
    'persistence': [38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48],
    'fragility': [
      49,
      50,
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
    ],
  };

  final Map<String, String> _categoryNames = {
    'intrinsic': 'İçsel Motivasyon',
    'extrinsic': 'Dışsal Motivasyon',
    'meaning': 'Amaç ve Anlam',
    'persistence': 'Süreklilik',
    'fragility': 'Kırılganlık',
  };

  final List<int> _reverseItems = [
    3, 7, 10, // A
    15, 19, 22, 24, // B
    27, 31, 34, 37, // C
    39, 41, 43, 45, 47, // D
    // E (Kırılganlık) items - usually we want higher to mean more fragile, so no reverse there.
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
            indicatorColor: Colors.indigo,
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
            borderSide: BorderSide(color: Colors.indigo, width: 2),
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
    final intrinsic = averages['intrinsic'] ?? 0;
    final extrinsic = averages['extrinsic'] ?? 0;
    final fragility = averages['fragility'] ?? 0;

    String profile;
    Color color;
    if (fragility > 40) {
      profile = 'Yüksek Kırılganlıklı Motivasyon (Dışa Bağımlı)';
      color = Colors.red;
    } else if (intrinsic > 40 && fragility < 15) {
      profile = 'Sağlam / Kendi Kendini Motive Eden';
      color = Colors.green;
    } else if (extrinsic > intrinsic) {
      profile = 'Ödül-Onay Odaklı Motivasyon Gelişimi';
      color = Colors.orange;
    } else {
      profile = 'Dengeli / Süreç Odaklı Motivasyon';
      color = Colors.indigo;
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              'Akademik Motivasyon Dinamiği',
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
                _buildStatItem('İçsel Güç / 52', intrinsic.toStringAsFixed(1)),
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
            'Motivasyonel Analiz Bileşenleri (%)',
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
              Icon(Icons.bolt, color: Colors.indigo.shade800, size: 24),
              const SizedBox(width: 8),
              Text(
                'Derinlemesine Motivasyonel Analiz',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo.shade900,
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
    final intrinsic = averages['intrinsic'] ?? 0;
    final extrinsic = averages['extrinsic'] ?? 0;
    final meaning = averages['meaning'] ?? 0;
    final persistence = averages['persistence'] ?? 0;
    final fragility = averages['fragility'] ?? 0;

    String advice = "GELİŞTİRİLMİŞ MOTİVASYON KAYNAKLARI ANALİZİ\n\n";

    if (extrinsic > intrinsic && fragility > 30) {
      advice +=
          "KRİTİK TESPİT: 'Dinamik Olmayan Motivasyon'. Çalışma enerjiniz büyük oranda ödül, onay veya ceza gibi dış etkenlere bağlı. Bu dış faktörlerden birinde aksama olduğunda motivasyonunuz hızla kırılıyor ('Kırılganlık'). Başarınızın sürdürülebilir olması için bu dışsal bağımlılığın azaltılması kritik önem taşıyor.\n\n";
    }

    if (meaning < 20 && persistence < 25) {
      advice +=
          "ÖZEL ANALİZ: 'Nedenini Kaybetmiş İstikrarsızlık'. Uzun vadeli hedeflerinizle mevcut çalışmalarınız arasındaki bağ zayıflamış durumda. Bu 'anlamsızlık' hissi, motivasyonunuzun sürekliliğini doğrudan baltalıyor. Neden çalıştığınızı yeniden keşfetmeniz gerekiyor.\n\n";
    }

    advice += "1. Motivasyonel Enerji Profiliniz\n";
    final scores = {
      'İçsel İstek': intrinsic,
      'Dışsal Bağımlılık': extrinsic,
      'Amaç Bilinci': meaning,
      'Süreklilik Gücü': persistence,
      'Kırılganlık Riski': fragility,
    };
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    advice +=
        "En baskın faktörünüz: ${sorted[0].key}. En çok geliştirilmesi gereken: ${sorted.last.key}.\n\n";

    advice += "2. Gelişim ve Yapılandırma Önerileri\n";
    if (fragility > 30) {
      advice +=
          "- Olumsuz geri bildirimleri kişiliğinize yönelik bir saldırı değil, yönteminize yönelik bir 'veri' olarak kabul edin.\n- Hata yaptığınızda motivasyonunuzun sönmesine izin vermeyin; hatayı öğrenme sürecinin doğal bir 'maliyeti' olarak görün.\n";
    } else if (persistence < 30) {
      advice +=
          "- Motivasyonun her an aynı seviyede kalmayacağını kabul edin. Motivasyonun düştüğü anlarda 'istek' ile değil 'disiplin' ile masaya oturun.\n- Büyük hedefleri günlük, ulaşılamayacak kadar küçük olmayan mikro görevlere bölün.\n";
    } else if (intrinsic < 30) {
      advice +=
          "- Her gün çalıştığınız konudan 'ilginç bir bilgi' seçin ve bunu birine anlatın. Merak mekanizmasının çalışması içsel ateşi yakacaktır.\n- Kendi kendinize hedefler koyun ve başkası görmese bile kendinizi onaylayın.\n";
    }

    advice += "\n3. Rehberlik ve Yaklaşım (Veli & Öğretmen)\n";
    if (extrinsic > 40) {
      advice +=
          "Öğrenci üzerinde ödül veya not baskısını artırmak yerine, onun 'merak' ve 'keşif' duygusunu canlandıracak sorular sorun. Onay ihtiyacını 'kişiliğine' değil, 'çabasına' yapılan vurgularla doyurun.\n";
    } else if (fragility > 35) {
      advice +=
          "Öğrenci başarısızlıklar karşısında hızla dağılabilir. Ona 'güçlü dur' demek yerine, başarısızlık sonrası toparlanma sürecinde duygusal destek verin ve eyleme geçmesi için küçük basamaklar sunun.\n";
    } else {
      advice +=
          "Öğrenci sağlıklı bir motivasyonel yapıya sahip. Ona stratejik otonomi (çalışma yöntemini kendisinin belirlemesi) tanınması bu yapıyı verimliliğe dönüştürecektir.\n";
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
              'İçsel: ${stats['intrinsic']?.toInt()} | Anlam: ${stats['meaning']?.toInt()} | Kırılganlık: ${stats['fragility']?.toInt()}',
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
        'intrinsic': 52,
        'extrinsic': 48,
        'meaning': 48,
        'persistence': 44,
        'fragility': 68,
      };

      final pdfBytes = await pdfService.generateSurveyReportPdf(
        title: 'Motivasyon Kaynakları Ölçeği (MKÖ)',
        subTitle: subTitle,
        averages: averages,
        categoryNames: _categoryNames,
        categoryMax: categoryMax,
        respondentCount: count,
        advice: _generateAdviceString(averages),
      );

      await FileSaver.instance.saveFile(
        name: 'MKO_Rapor',
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
        TextCellValue('İçsel'),
        TextCellValue('Dışsal'),
        TextCellValue('Amaç-Anlam'),
        TextCellValue('Süreklilik'),
        TextCellValue('Kırılganlık'),
      ]);
      for (var r in filtered) {
        final stats = _calculateStudentStats(r);
        sheet.appendRow([
          TextCellValue(widget.userNames[r['userId']] ?? 'Bilinmeyen'),
          DoubleCellValue(stats['intrinsic'] ?? 0),
          DoubleCellValue(stats['extrinsic'] ?? 0),
          DoubleCellValue(stats['meaning'] ?? 0),
          DoubleCellValue(stats['persistence'] ?? 0),
          DoubleCellValue(stats['fragility'] ?? 0),
        ]);
      }
      var b = excel.save();
      if (b != null)
        await FileSaver.instance.saveFile(
          name: 'MKO_Excel',
          bytes: Uint8List.fromList(b),
          ext: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
    } catch (e) {
      print('Excel error: $e');
    }
  }
}
