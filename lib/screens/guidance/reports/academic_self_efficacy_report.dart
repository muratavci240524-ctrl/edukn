import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/survey_model.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../../services/pdf_service.dart';

class AcademicSelfEfficacyReport extends StatefulWidget {
  final Survey survey;
  final List<Map<String, dynamic>> responses;
  final Map<String, String> userNames;

  const AcademicSelfEfficacyReport({
    Key? key,
    required this.survey,
    required this.responses,
    required this.userNames,
  }) : super(key: key);

  @override
  State<AcademicSelfEfficacyReport> createState() =>
      _AcademicSelfEfficacyReportState();
}

class _AcademicSelfEfficacyReportState extends State<AcademicSelfEfficacyReport>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedScope = 'institution';
  String? _selectedBranch;
  String? _selectedStudent;

  final Map<String, List<int>> _categories = {
    'task': [1, 2, 3, 4, 5, 6, 7, 8],
    'difficult': [9, 10, 11, 12, 13, 14, 15, 16],
    'failure': [17, 18, 19, 20, 21, 22, 23, 24],
    'lesson': [25, 26, 27, 28, 29, 30, 31, 32],
    'compare': [33, 34, 35, 36, 37, 38, 39, 40],
    'awareness': [41, 42, 43, 44, 45, 46, 47, 48, 49, 50],
  };

  final Map<String, String> _categoryNames = {
    'task': 'Görev Güveni',
    'difficult': 'Zor Görevler',
    'failure': 'Hata Sonrası Güven',
    'lesson': 'Ders Bazlı Güven',
    'compare': 'Kıyaslama Direnci',
  };

  final List<int> _reverseItems = [7, 12, 13, 21, 23, 30, 37, 38, 48];

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

        // Logic for AOEO:
        // Reverse items (7, 12, 13, 21, 23, 30, 37, 38, 48) mean agreement = HIGH self-efficacy.
        // Standard items here (mostly negative phrasing in standard) mean agreement = LOW self-efficacy.
        // Wait, checking item 1: "Çoğunu yapabileceğime inanırım" (Standard, Positive phrasing).
        // Item 3: "Gözümde genellikle büyür" (Standard, Negative phrasing).
        // Item 7: "Çalışırsam başarabileceğimi hissederim" (Ters, Positive phrasing).
        // This numbering is a bit mixed in the prompt but let's follow the "8. TERS MADDELER" explicitly.
        // If an item is in _reverseItems, agreement (4) gives 4 points.
        // Else, agreement (4) gives 0 points. (Reversing it)

        if (_reverseItems.contains(idx)) {
          // Stay (High agreement = High efficacy)
        } else {
          val = 4 - val; // Reverse (High agreement = Low efficacy)
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
    stats['indecisiveRatio'] = (indecisiveCount / 50.0) * 100;

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
          _buildEfficacyOverview(averages, count, indecisiveRatio),
          const SizedBox(height: 24),
          _buildRadarChart(averages),
          const SizedBox(height: 24),
          _buildInterpretation(averages),
        ],
      ),
    );
  }

  Widget _buildEfficacyOverview(
    Map<String, double> averages,
    int count,
    double indecisiveRatio,
  ) {
    final total = averages['total'] ?? 0;
    String level;
    Color color;

    // Max score: 5 cats (task, difficult, failure, lesson, compare) * 8 items = 40 items * 4 = 160
    if (total >= 125) {
      level = 'Güçlü Öz-Yeterlik';
      color = Colors.green;
    } else if (total >= 85) {
      level = 'Gerçekçi Öz-Yeterlik';
      color = Colors.blue;
    } else if (total >= 50) {
      level = 'Kırılgan Öz-Yeterlik';
      color = Colors.orange;
    } else {
      level = 'Düşük Öz-Yeterlik';
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
              'Akademik Öz-Yeterlik Algısı',
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
            if (indecisiveRatio > 25) ...[
              const Divider(height: 32),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Kırılgan İnanç: Kararsızlık oranınız, akademik becerilerinize olan inancınızın dış onaylara veya anlık durumlara çok bağlı olduğunu gösteriyor.',
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
            'Öz-Yeterlik Boyutları Analizi (%)',
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
              const Icon(Icons.psychology, color: Colors.blue, size: 24),
              const SizedBox(width: 8),
              Text(
                'Akademik İnanç Analizi',
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
              color: Colors.deepPurple.shade900,
            ),
          ),
        ],
      ),
    );
  }

  String _generateAdviceString(Map<String, double> averages) {
    final taskCount = averages['task'] ?? 0;
    final difficult = averages['difficult'] ?? 0;
    final failure = averages['failure'] ?? 0;
    final lesson = averages['lesson'] ?? 0;
    final compare = averages['compare'] ?? 0;

    String advice = "AKADEMİK ÖZ-YETERLİK ANALİZ RAPORU\n\n";

    if (taskCount > 24 && difficult < 12) {
      advice +=
          "ÖZEL TESPİT: 'Konfor Alanı Güveni'. Standart görevlerde kendinize güveniyorsunuz ancak çıta yükseldiğinde 'yapabilirim' inancınız hızla sarsılıyor. Bu, sınırlarınızı zorlamaktan kaçınmanıza neden olabilir.\n\n";
    }

    if (compare < 12) {
      advice +=
          "ÖZEL TESPİT: 'Dışa Bağımlı Özgüven'. Akademik değerinizi başkaları üzerinden tanımlıyorsunuz. Arkadaşlarınızın başarısı size ilham yerine tehdit olarak dönüyor. Odağı rakiplerden, kendi gelişim basamaklarınıza çekmelisiniz.\n\n";
    }

    advice += "1. Güçlü ve Hassas Alanlar\n";
    final scores = {
      'Genel Görev Güveni': taskCount,
      'Zorluk Karşısında İnanç': difficult,
      'Yenilgi Sonrası İnanç': failure,
      'Ders Bazlı İstikrar': lesson,
      'Kıyaslamayı Reddetme': compare,
    };
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    advice +=
        "En sağlam olduğunuz alan: ${sorted[0].key}. En çok sarsılan alan: ${sorted.last.key}.\n\n";

    advice += "2. Müdahale ve Güçlendirme Önerileri\n";
    if (sorted.last.key == 'Yenilgi Sonrası İnanç') {
      advice +=
          "- Bir başarısızlığı 'karakteriniz' değil, 'o anki yönteminiz' olarak etiketleyin.\n- Başarısızlık sonrası 'Hala yapamadığım kısımlar' yerine 'Bugün öğrendiğim 1 şey' listesi yapın.\n";
    } else if (sorted.last.key == 'Zorluk Karşısında İnanç') {
      advice +=
          "- 'Bunu henüz yapamıyorum' cümlesine 'HENÜZ' kelimesini ekleyerek zihinsel kapıları açık tutun.\n- En zorlandığınız konuyu en verimli olduğunuz saatte çalışın.\n";
    } else if (sorted.last.key == 'Kıyaslamayı Reddetme') {
      advice +=
          "- Başkalarının başarısını bir 'kanıt' olarak görün: 'O yaptıysa bu yapılabilecek bir şey'.\n- Kendi geçmiş performansınızı bugünkü rakibiniz yapın.\n";
    } else {
      advice +=
          "- Görevleri küçük basamaklara ayırarak 'küçük zaferler' biriktirin.\n- Akademik yetkinliklerinizi puanlamalı ve her hafta bir puan artırmaya odaklanmalısınız.\n";
    }

    advice += "\n3. Strateji Notu\n";
    advice +=
        "Öz-yeterlik, geçmiş başarılarınızdan değil, zorluklarla nasıl baş ettiğinizden beslenir. Kendi potansiyelinize dair en büyük kanıt, vazgeçmediğiniz her gündür.\n";

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
                    _buildEfficacyOverview(
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
        'task': 32,
        'difficult': 32,
        'failure': 32,
        'lesson': 32,
        'compare': 32,
      };

      final pdfBytes = await pdfService.generateSurveyReportPdf(
        title: 'Akademik Öz-Yeterlik Algısı Ölçeği (AOEÖ)',
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
        name: 'Akademik_ÖzYeterlik_Rapor',
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
      var sheet = excel['Akademik Öz-Yeterlik'];
      sheet.appendRow([
        TextCellValue('Öğrenci Adı'),
        TextCellValue('Görev Güveni'),
        TextCellValue('Zor Görevler'),
        TextCellValue('Hata Sonrası'),
        TextCellValue('Ders Bazlı'),
        TextCellValue('Kıyaslama'),
        TextCellValue('Toplam Puan'),
      ]);

      for (var r in filtered) {
        final name = widget.userNames[r['userId']] ?? 'Bilinmeyen';
        final stats = _calculateStudentStats(r);
        sheet.appendRow([
          TextCellValue(name),
          DoubleCellValue(stats['task'] ?? 0),
          DoubleCellValue(stats['difficult'] ?? 0),
          DoubleCellValue(stats['failure'] ?? 0),
          DoubleCellValue(stats['lesson'] ?? 0),
          DoubleCellValue(stats['compare'] ?? 0),
          DoubleCellValue(stats['total'] ?? 0),
        ]);
      }

      var fileBytes = excel.save();
      if (fileBytes != null) {
        await FileSaver.instance.saveFile(
          name: 'Akademik_ÖzYeterlik_Excel',
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
