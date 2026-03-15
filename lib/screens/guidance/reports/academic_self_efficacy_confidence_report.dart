import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/survey_model.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../../services/pdf_service.dart';

class AcademicSelfEfficacyConfidenceReport extends StatefulWidget {
  final Survey survey;
  final List<Map<String, dynamic>> responses;
  final Map<String, String> userNames;

  const AcademicSelfEfficacyConfidenceReport({
    Key? key,
    required this.survey,
    required this.responses,
    required this.userNames,
  }) : super(key: key);

  @override
  State<AcademicSelfEfficacyConfidenceReport> createState() =>
      _AcademicSelfEfficacyConfidenceReportState();
}

class _AcademicSelfEfficacyConfidenceReportState
    extends State<AcademicSelfEfficacyConfidenceReport>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedScope = 'institution';
  String? _selectedBranch;
  String? _selectedStudent;

  final Map<String, List<int>> _categories = {
    'efficacy': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
    'coping': [13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24],
    'ownership': [25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36],
    'failure': [37, 38, 39, 40, 41, 42, 43, 44, 45, 46],
    'persistence': [47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60],
  };

  final Map<String, String> _categoryNames = {
    'efficacy': 'Öz-Yeterlik İnancı',
    'coping': 'Zorlukla Baş Etme',
    'ownership': 'Başarıyı Sahiplenme',
    'failure': 'Hata Algısı',
    'persistence': 'Güven Sürekliliği',
  };

  final List<int> _reverseItems = [
    6, 8, 10, // A
    14, 18, 20, 22, 24, // B
    26, 30, 34, // C
    38, 40, 42, 44, 46, // D
    48, 51, 54, 56, 58, // E
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
            indicatorColor: Colors.teal,
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
                    selectedBackgroundColor: Colors.teal.shade50,
                    selectedForegroundColor: Colors.teal,
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
            borderSide: BorderSide(color: Colors.teal, width: 2),
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
        if (valStr == 'Evet' || valStr == 'Bazen' || valStr == 'Hayır')
          val = _getBehaviorValue(valStr);

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

  double _getBehaviorValue(String option) {
    switch (option) {
      case 'Hayır':
        return 0;
      case 'Bazen':
        return 2;
      case 'Evet':
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
    final efficacy = averages['efficacy'] ?? 0;
    final ownership = averages['ownership'] ?? 0;
    final failure = averages['failure'] ?? 0;

    String profile;
    Color color;
    if (efficacy > 40 && ownership > 40) {
      profile = 'Yüksek Öz-Yeterlik / Sorumluluk Sahibi';
      color = Colors.green;
    } else if (ownership < 20) {
      profile = 'Dengelenmemiş / Şans Odaklı Başarı Algısı';
      color = Colors.orange;
    } else if (failure < 15) {
      profile = 'Kırılgan Güven / Hata Toleransı Düşük';
      color = Colors.red;
    } else {
      profile = 'Potansiyelli / Gelişmekte Olan Güven';
      color = Colors.teal;
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              'Öz-Yeterlik & Kendine Güven Profili',
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
                _buildStatItem('Öz-Yeterlik / 48', efficacy.toStringAsFixed(1)),
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
            'Yeterlik ve Güven Bileşenleri (%)',
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
              Icon(Icons.verified_user, color: Colors.teal.shade800, size: 24),
              const SizedBox(width: 8),
              Text(
                'Akademik İnanç ve Kapasite Analizi',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade900,
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
    final efficacy = averages['efficacy'] ?? 0;
    final coping = averages['coping'] ?? 0;
    final ownership = averages['ownership'] ?? 0;
    final failure = averages['failure'] ?? 0;
    final persistence = averages['persistence'] ?? 0;

    String advice = "ÖZ-YETERLİK VE AKADEMİK KENDİNE GÜVEN ANALİZİ\n\n";

    if (efficacy > 40 && coping < 20) {
      advice +=
          "KRİTİK TESPİT: 'Potansiyele Güvenip Mücadeleden Kaçma'. Akademik olarak yetenekli olduğunuza inanıyorsunuz ancak gerçek bir zorlukla karşılaştığınızda (zor bir soru, yeni bir konu) bu inancınız eyleme dönüşmüyor. Sorun 'yetenek' değil, 'zorlukla baş etme stratejisi'.\n\n";
    }

    if (ownership < 20) {
      advice +=
          "ÖZEL ANALİZ: 'Dışsal Başarı Odağı'. Başarılarınızı kendi çabanız yerine şansa veya kolaylığa bağlama eğilimindesiniz. Bu durum, öz-güveninizin kalıcı olmasını engeller çünkü kontrolün sizde olmadığını hissedersiniz.\n\n";
    }

    advice += "1. İnanç ve Yeterlik Profiliniz\n";
    final scores = {
      'Genel Yeterlik': efficacy,
      'Mücadele Gücü': coping,
      'Başarı Sorumluluğu': ownership,
      'Hata Toleransı': failure,
      'Güven İstikrarı': persistence,
    };
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    advice +=
        "En sağlam dayanağınız: ${sorted[0].key}. Desteklenmesi gereken zayıf halka: ${sorted.last.key}.\n\n";

    advice += "2. Güven İnşası ve Uygulama Önerileri\n";
    if (ownership < 30) {
      advice +=
          "- Kazandığınız her ufak başarıdan sonra 'Bunu ben yaptım, şu çalışmam sayesinde oldu' diyerek kendinizi açıkça onaylayın.\n- Başarılarınızın bir listesini yapın ve yanlarına hangi çabanızın bu sonucu getirdiğini yazın.\n";
    } else if (failure < 30) {
      advice +=
          "- Hataları bir 'son' değil, geliştirilmesi gereken bir 'veri' olarak görün. Hata yaptığınızda moral bozmak yerine 'Burada neyi eksik bıraktım?' sorusuna odaklanın.\n- Yanlış yaptığınız sorulardan oluşan bir 'Gelişim Defteri' tutun.\n";
    } else if (persistence < 30) {
      advice +=
          "- Güveninizi akademik sonuçlara (notlara) endekslemekten vazgeçin. Kendinize olan güveninizi 'mücadele kalitenize' dayandırın.\n- Küçük başarısızlıklarda tüm potansiyelinizi sorgulamak yerine, sadece o anki yönteminizi sorgulayın.\n";
    }

    advice += "\n3. Rehberlik ve Yaklaşım (Veli & Öğretmen)\n";
    if (ownership < 20) {
      advice +=
          "Öğrenciye sadece 'aferin' demek yerine, başarısının arkasındaki spesifik çabayı (örn: 'Bu konuya 3 gün çalışman meyvesini verdi') vurgulayın. Başarıyı içselleştirmesine yardımcı olun.\n";
    } else if (failure < 20) {
      advice +=
          "Hata yaptığı anlarda destekleyici olun ve hatanın öğrenme sürecinin doğal bir parçası olduğunu hissettirin. Mükemmeliyetçilik baskısını azaltın.\n";
    } else {
      advice +=
          "Öğrenci potansiyeline güveniyor. Onu kapasitesini biraz daha zorlayacak, 'gelişim bölgesi'ndeki görevlerle destekleyerek bu güveni beceriye dönüştürebilirsiniz.\n";
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
              'Yeterlik: ${stats['efficacy']?.toInt()} | Sahiplenme: ${stats['ownership']?.toInt()} | Güven: ${stats['persistence']?.toInt()}',
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
        'efficacy': 48,
        'coping': 48,
        'ownership': 48,
        'failure': 40,
        'persistence': 56,
      };

      final pdfBytes = await pdfService.generateSurveyReportPdf(
        title: 'Öz-Yeterlik ve Akademik Kendine Güven Ölçeği (AÖKGÖ)',
        subTitle: subTitle,
        averages: averages,
        categoryNames: _categoryNames,
        categoryMax: categoryMax,
        respondentCount: count,
        advice: _generateAdviceString(averages),
      );

      await FileSaver.instance.saveFile(
        name: 'AOKGO_Rapor',
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
      var sheet = excel['Öz-Yeterlik Güven'];
      sheet.appendRow([
        TextCellValue('Öğrenci Adı'),
        TextCellValue('Öz-Yeterlik'),
        TextCellValue('Zorlukla Baş Etme'),
        TextCellValue('Başarı Sahiplenme'),
        TextCellValue('Hata Algısı'),
        TextCellValue('Güven Sürekliliği'),
      ]);
      for (var r in filtered) {
        final stats = _calculateStudentStats(r);
        sheet.appendRow([
          TextCellValue(widget.userNames[r['userId']] ?? 'Bilinmeyen'),
          DoubleCellValue(stats['efficacy'] ?? 0),
          DoubleCellValue(stats['coping'] ?? 0),
          DoubleCellValue(stats['ownership'] ?? 0),
          DoubleCellValue(stats['failure'] ?? 0),
          DoubleCellValue(stats['persistence'] ?? 0),
        ]);
      }
      var b = excel.save();
      if (b != null)
        await FileSaver.instance.saveFile(
          name: 'AOKGO_Excel',
          bytes: Uint8List.fromList(b),
          ext: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
    } catch (e) {
      print('Excel error: $e');
    }
  }
}
