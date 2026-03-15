import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/survey_model.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../../services/pdf_service.dart';

class TimeManagementDisciplineReport extends StatefulWidget {
  final Survey survey;
  final List<Map<String, dynamic>> responses;
  final Map<String, String> userNames;

  const TimeManagementDisciplineReport({
    Key? key,
    required this.survey,
    required this.responses,
    required this.userNames,
  }) : super(key: key);

  @override
  State<TimeManagementDisciplineReport> createState() =>
      _TimeManagementDisciplineReportState();
}

class _TimeManagementDisciplineReportState
    extends State<TimeManagementDisciplineReport>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedScope = 'institution';
  String? _selectedBranch;
  String? _selectedStudent;

  final Map<String, List<int>> _categories = {
    'planning': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13],
    'avoidance': [14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25],
    'focus': [26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36],
    'discipline': [
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
    'planning': 'Zaman Planlama',
    'avoidance': 'Erteleme Kaçınma',
    'focus': 'Dikkat/Devamlılık',
    'discipline': 'Öz-Disiplin',
  };

  final List<int> _reverseItems = [
    8, 9, 10, 12, // A
    14, 15, 16, 17, 18, 19, 20, 21, // B
    26, 29, 30, 31, 32, // C
    45, 46, 47, 48, 49, // D
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
        final val = _getOptionValue(answers['q$idx']?.toString());
        catTotal += _reverseItems.contains(idx) ? (3 - val) : val;
      }
      stats[cat] = catTotal;
    });
    return stats;
  }

  int _getOptionValue(String? option) {
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
    final discipline = averages['discipline'] ?? 0;
    final avoidance = averages['avoidance'] ?? 0;

    String profile;
    Color color;
    if (discipline > 36 && avoidance > 24) {
      profile = 'Planlı / Bilinçli Uygulayıcı';
      color = Colors.green;
    } else if (avoidance < 15) {
      profile = 'Kronik Ertelemeci / Dağınık';
      color = Colors.red;
    } else {
      profile = 'Gelişim Yolunda / İnişli Çıkışlı';
      color = Colors.orange;
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              'Öz-Disiplin ve Yönetim Profili',
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
                _buildStatItem(
                  'Disiplin Puanı / 48',
                  discipline.toStringAsFixed(1),
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
            'Zaman ve Disiplin Boyutları (%)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: RadarChart(
              RadarChartData(
                dataSets: [
                  RadarDataSet(
                    fillColor: Colors.deepOrange.withOpacity(0.2),
                    borderColor: Colors.deepOrange,
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
              Icon(Icons.timer, color: Colors.orange.shade800, size: 24),
              const SizedBox(width: 8),
              Text(
                'Derinlemesine Alışkanlık Analizi',
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
    final planning = averages['planning'] ?? 0;
    final avoidance = averages['avoidance'] ?? 0;
    final focus = averages['focus'] ?? 0;
    final discipline = averages['discipline'] ?? 0;

    String advice = "ZAMAN YÖNETİMİ VE ÖZ-DİSİPLİN ANALİZİ\n\n";

    if (planning > 30 && avoidance < 18) {
      advice +=
          "KRİTİK TESPİT: 'İyi Niyetli Ama Dağınık'. Plan yapıyorsunuz ancak uygulamaya geçmekte büyük bir direnç yaşıyorsunuz. Kağıt üzerinde her şey mükemmel görünse de eylem aşamasında 'erteleme' galip geliyor.\n\n";
    }

    if (focus < 15 && discipline > 30) {
      advice +=
          "ÖZEL ANALİZ: 'Başlıyor Ama Sürdüremiyor'. Göreve başlama konusunda disiplinlisiniz ancak çalışma süresi uzadığında dikkatiniz çok çabuk dağılıyor. Bu durum, çalışmalarınızın verimini ciddi şekilde düşürüyor.\n\n";
    }

    advice += "1. Temel Boyut Analiziniz\n";
    final scores = {
      'Planlama Kapasitesi': planning,
      'Eyleme Geçme Hızı': avoidance,
      'Dikkat Sürdürülebilirliği': focus,
      'Sorumluluk Bilinci': discipline,
    };
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    advice +=
        "En güçlü alanınız: ${sorted[0].key}. En zayıf halkanız: ${sorted.last.key}.\n\n";

    advice += "2. Gelişim ve Müdahale Stratejileri\n";
    if (avoidance < 18) {
      advice +=
          "- 'Sadece Başla' kuralını uygulayın. İlk 10 dakikayı tamamlamayı hedefleyin, gerisi kendiliğinden gelecektir.\n- Ertelemenin arkasındaki duyguyu (kaygı, sıkılma vb.) fark edin.\n";
    } else if (focus < 15) {
      advice +=
          "- Çalışma sürelerinizi kısaltıp mola sayılarını artırın (Örn: 25-5 Pomodoro).\n- Dikkatinizi dağıtan dijital bildirimleri çalışma alanınızdan tamamen uzaklaştırın.\n";
    } else if (planning < 20) {
      advice +=
          "- Yatmadan önce ertesi günün en önemli 3 görevini listeleyin.\n- Zamanın nereye gittiğini görmek için bir gün boyunca 'zaman günlüğü' tutun.\n";
    } else {
      advice +=
          "- Mevcut öz-disiplininiz oldukça yüksek. Bu beceriyi daha karmaşık ve uzun vadeli projelere odaklanmak için kullanın.\n";
    }

    advice += "\n3. Rehberlik ve Destek Notu\n";
    if (discipline < 30) {
      advice +=
          "Öğrenci 'bilmesine rağmen yapmıyor' olabilir. Ona katı disiplin yerine, küçük başarıları ödüllendiren ve sorumluluk almasını teşvik eden kademeli bir yaklaşım sergilenmelidir.\n";
    } else {
      advice +=
          "Öğrencinin öz-yönetim becerisi yüksek. Ona daha fazla otonomi vererek kendi öğrenme sürecini tasarlamasına izin verilebilir.\n";
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
              'Planlama: ${stats['planning']?.toInt()} | Disiplin: ${stats['discipline']?.toInt()}',
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
                color: Colors.deepOrange,
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
        'planning': 39,
        'avoidance': 36,
        'focus': 33,
        'discipline': 48,
      };

      final pdfBytes = await pdfService.generateSurveyReportPdf(
        title: 'Zaman Yönetimi ve Akademik Öz-Disiplin Ölçeği (ZYÖDÖ)',
        subTitle: subTitle,
        averages: averages,
        categoryNames: _categoryNames,
        categoryMax: categoryMax,
        respondentCount: count,
        advice: _generateAdviceString(averages),
      );

      await FileSaver.instance.saveFile(
        name: 'ZYODO_Rapor',
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
      var sheet = excel['Disiplin Analizi'];
      sheet.appendRow([
        TextCellValue('Öğrenci Adı'),
        TextCellValue('Planlama'),
        TextCellValue('Erteleme'),
        TextCellValue('Odak'),
        TextCellValue('Disiplin'),
      ]);
      for (var r in filtered) {
        final stats = _calculateStudentStats(r);
        sheet.appendRow([
          TextCellValue(widget.userNames[r['userId']] ?? 'Bilinmeyen'),
          DoubleCellValue(stats['planning'] ?? 0),
          DoubleCellValue(stats['avoidance'] ?? 0),
          DoubleCellValue(stats['focus'] ?? 0),
          DoubleCellValue(stats['discipline'] ?? 0),
        ]);
      }
      var b = excel.save();
      if (b != null)
        await FileSaver.instance.saveFile(
          name: 'ZYODO_Excel',
          bytes: Uint8List.fromList(b),
          ext: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
    } catch (e) {
      print('Excel error: $e');
    }
  }
}
