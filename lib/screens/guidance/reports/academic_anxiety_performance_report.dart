import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/survey_model.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../../services/pdf_service.dart';

class AcademicAnxietyPerformanceReport extends StatefulWidget {
  final Survey survey;
  final List<Map<String, dynamic>> responses;
  final Map<String, String> userNames;

  const AcademicAnxietyPerformanceReport({
    Key? key,
    required this.survey,
    required this.responses,
    required this.userNames,
  }) : super(key: key);

  @override
  State<AcademicAnxietyPerformanceReport> createState() =>
      _AcademicAnxietyPerformanceReportState();
}

class _AcademicAnxietyPerformanceReportState
    extends State<AcademicAnxietyPerformanceReport>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedScope = 'institution';
  String? _selectedBranch;
  String? _selectedStudent;

  final Map<String, List<int>> _categories = {
    'cognitive': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
    'emotional': [13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24],
    'physiological': [25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36],
    'performance': [
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
    'cognitive': 'Bilişsel Kaygı',
    'emotional': 'Duygusal Kaygı',
    'physiological': 'Fizyolojik Tepki',
    'performance': 'Performans Etkisi',
  };

  final List<int> _reverseItems = [
    1, 2, 3, 4, 6, 7, 9, 11, // A
    13, 14, 15, 16, 18, 20, 22, 24, // B
    25, 26, 27, 28, 30, 31, 33, 34, // C
    37, 40, 42, 44, 46, 48, 50, 52, // D
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
            indicatorColor: Colors.orange,
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
                    selectedBackgroundColor: Colors.orange.shade50,
                    selectedForegroundColor: Colors.orange,
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
            borderSide: BorderSide(color: Colors.orange, width: 2),
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
        int val = _getOptionValue(valStr);
        catTotal += _reverseItems.contains(idx) ? (4 - val) : val;
      }
      stats[cat] = catTotal;
    });
    return stats;
  }

  int _getOptionValue(String option) {
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
    final cognitive = averages['cognitive'] ?? 0;
    final performance = averages['performance'] ?? 0;

    String profile;
    Color color;
    if (performance > 45 && cognitive > 30) {
      profile = 'Optimal Kaygı / Yüksek Performans';
      color = Colors.green;
    } else if (performance < 20) {
      profile = 'Kaygı Blokajı / Performans Kaybı';
      color = Colors.red;
    } else if (cognitive < 15) {
      profile = 'Düşük Kaygı / Rehavet Riski';
      color = Colors.orange;
    } else {
      profile = 'Dengelenmeye Çalışan Kaygı';
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
              'Akademik Kaygı & Performans Profili',
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
                  'Bilişsel Netlik / 48',
                  cognitive.toStringAsFixed(1),
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
            'Kaygı ve Performans Bileşenleri (%)',
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
          Row(
            children: [
              Icon(Icons.bolt, color: Colors.orange.shade800, size: 24),
              const SizedBox(width: 8),
              Text(
                'Dengeli Performans Analizi',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade900,
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
    final cognitive = averages['cognitive'] ?? 0;
    final emotional = averages['emotional'] ?? 0;
    final physiological = averages['physiological'] ?? 0;
    final performance = averages['performance'] ?? 0;

    String advice = "AKADEMİK KAYGI – PERFORMANS DENGESİ ANALİZİ\n\n";

    if (performance < 25 && cognitive < 20) {
      advice +=
          "ÖNEMLİ TESPİT: 'Zihinsel Blokaj'. Kaygınızın şiddeti, sınav anında bildiklerinizi geri çağırma ve odaklanma yeteneğinizi ciddi oranda düşürüyor. Bu bir 'bilmeme' sorunu değil, 'kaygı yönetimi' sorunudur.\n\n";
    }

    if (performance > 45 && cognitive > 30) {
      advice +=
          "İDEAL DURUM: 'Yaralı Kaygı'. Kaygıyı bir düşman olarak değil, sizi diri ve dikkatli tutan bir yakıt olarak kullanabiliyorsunuz. Bu denge, yüksek konsantrasyon gerektiren sınavlarda sizin en büyük avantajınızdır.\n\n";
    }

    advice += "1. Kaygı Profiliniz\n";
    final scores = {
      'Zihinsel Netlik': cognitive,
      'Duygusal Kontrol': emotional,
      'Bedensel Direnç': physiological,
      'Performans Uyumu': performance,
    };
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    advice +=
        "En güçlü yönünüz: ${sorted[0].key}. Kaygının en çok vurduğu alan: ${sorted.last.key}.\n\n";

    advice += "2. Kişisel Gelişim ve Yönetim Önerileri\n";
    if (physiological < 25) {
      advice +=
          "- Bedensel tepkiler (çarpıntı, titreme) sizi korkutmasın. Nefes egzersizlerini bir rutin haline getirin.\n- Sınav anında bedensel bir tepki hissettiğinizde 'Vücudum performans için enerji hazırlıyor' diyerek bu belirtiye yeni bir anlam yükleyin.\n";
    } else if (cognitive < 25) {
      advice +=
          "- Sınav anında 'unuttum' hissi geldiğinde kalem bırakıp 10 saniye boşluğa bakın ve nefes alın. Beyninize güvende olduğu mesajını verin.\n- Gerçekçi olmayan 'ya yapamazsam' düşüncelerine karşı 'şu an sadece bu soruya odaklanmalıyım' diyerek şimdiki zamana dönün.\n";
    } else if (performance < 30) {
      advice +=
          "- Deneme sınavlarını sadece net hesabı için değil, 'kaygı yönetimi provaları' olarak görün.\n- Kaygının yükseldiği anlarda süreyi bir kenara bırakıp sadece doğru yöntemi bulmaya odaklanın.\n";
    }

    advice += "\n3. Rehberlik ve Yaklaşım Dili\n";
    if (performance < 25) {
      advice +=
          "Öğrenciye 'sakin ol' demek yerine, onun yaşadığı bilişsel kilitlenmeyi anladığınızı hissettiren bir dil kullanın. Başarı baskısı yerine 'mücadele kalitesi' odaklı geri bildirimler verin.\n";
    } else {
      advice +=
          "Öğrenci kaygıyı yönetmeyi biliyor. Ona bu becerisini daha zorlu akademik hedeflerde nasıl kullanabileceği konusunda rehberlik edebilirsiniz.\n";
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
              'Bilişsel: ${stats['cognitive']?.toInt()} | Performans: ${stats['performance']?.toInt()}',
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
        'cognitive': 48,
        'emotional': 48,
        'physiological': 48,
        'performance': 64,
      };

      final pdfBytes = await pdfService.generateSurveyReportPdf(
        title: 'Akademik Kaygı – Performans Dengesi Ölçeği',
        subTitle: subTitle,
        averages: averages,
        categoryNames: _categoryNames,
        categoryMax: categoryMax,
        respondentCount: count,
        advice: _generateAdviceString(averages),
      );

      await FileSaver.instance.saveFile(
        name: 'AAP_Rapor',
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
      var sheet = excel['Kaygı Performans'];
      sheet.appendRow([
        TextCellValue('Öğrenci Adı'),
        TextCellValue('Bilişsel'),
        TextCellValue('Duygusal'),
        TextCellValue('Fizyolojik'),
        TextCellValue('Performans'),
      ]);
      for (var r in filtered) {
        final stats = _calculateStudentStats(r);
        sheet.appendRow([
          TextCellValue(widget.userNames[r['userId']] ?? 'Bilinmeyen'),
          DoubleCellValue(stats['cognitive'] ?? 0),
          DoubleCellValue(stats['emotional'] ?? 0),
          DoubleCellValue(stats['physiological'] ?? 0),
          DoubleCellValue(stats['performance'] ?? 0),
        ]);
      }
      var b = excel.save();
      if (b != null)
        await FileSaver.instance.saveFile(
          name: 'AAP_Excel',
          bytes: Uint8List.fromList(b),
          ext: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
    } catch (e) {
      print('Excel error: $e');
    }
  }
}
