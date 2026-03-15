import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/survey_model.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../../services/pdf_service.dart';

class AcademicSelfEfficacyPerceptionReport extends StatefulWidget {
  final Survey survey;
  final List<Map<String, dynamic>> responses;
  final Map<String, String> userNames;

  const AcademicSelfEfficacyPerceptionReport({
    Key? key,
    required this.survey,
    required this.responses,
    required this.userNames,
  }) : super(key: key);

  @override
  State<AcademicSelfEfficacyPerceptionReport> createState() =>
      _AcademicSelfEfficacyPerceptionReportState();
}

class _AcademicSelfEfficacyPerceptionReportState
    extends State<AcademicSelfEfficacyPerceptionReport>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedScope = 'institution';
  String? _selectedBranch;
  String? _selectedStudent;

  final Map<String, List<int>> _categories = {
    'belief': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
    'resilience': [11, 12, 13, 14, 15, 16, 17, 18, 19, 20],
    'failure': [21, 22, 23, 24, 25, 26, 27, 28, 29, 30],
    'learning': [31, 32, 33, 34, 35, 36, 37, 38, 39, 40],
    'comparison': [41, 42, 43, 44, 45, 46, 47, 48, 49, 50],
    'control': [51, 52, 53, 54, 55, 56, 57, 58, 59, 60],
  };

  final Map<String, String> _categoryNames = {
    'belief': 'Yapabilme İnancı',
    'resilience': 'Zorlanma Güveni',
    'failure': 'Hata Toleransı',
    'learning': 'Öğrenme Güveni',
    'comparison': 'Sosyal Kıyas Kontrolü',
    'control': 'Akademik Kontrol',
  };

  final List<int> _reverseItems = [
    2, 4, 6, 8, 10, // A
    12, 14, 16, 18, 20, // B
    22, 24, 26, 28, 30, // C
    32, 34, 36, 38, 40, // D
    41, 42, 44, 46, 48, 50, // E
    52, 54, 56, 58, 60, // F
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
            indicatorColor: Colors.blueAccent,
            indicatorWeight: 3,
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Öz Yeterlik Analizi'),
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
                    selectedBackgroundColor: Colors.blue.shade50,
                    selectedForegroundColor: Colors.blue.shade900,
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
            borderSide: BorderSide(color: Colors.blueAccent, width: 2),
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
        final valStr =
            answers['q$idx']?.toString() ?? 'Kesinlikle Katılmıyorum';
        double val = _getOptionValue(valStr);

        catTotal += _reverseItems.contains(idx) ? (4.0 - val) : val;
      }
      stats[cat] = catTotal;
    });
    return stats;
  }

  double _getOptionValue(String option) {
    switch (option) {
      case 'Kesinlikle Katılmıyorum':
        return 0;
      case 'Katılmıyorum':
        return 1;
      case 'Kararsızım':
        return 2;
      case 'Katılıyorum':
        return 3;
      case 'Kesinlikle Katılıyorum':
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
    final efficacyScore =
        (averages['belief'] ?? 0) + (averages['control'] ?? 0);

    String profile;
    Color color;
    if (efficacyScore > 65) {
      profile = 'Yetkin ve Yüksek Öz Yeterlik';
      color = Colors.blue;
    } else if (averages['failure']! < 15) {
      profile = 'Hata Toleransı Düşük / Kırılgan Özgüven';
      color = Colors.red;
    } else if (averages['comparison']! < 15) {
      profile = 'Sosyal Kıyas Bağımlısı / Dış Odaklı';
      color = Colors.orange;
    } else {
      profile = 'Gelişime Açık Öz Yeterlik Algısı';
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
              'Akademik Öz Yeterlik Profili',
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
                  'Yapabilirlik / 80',
                  efficacyScore.toStringAsFixed(1),
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
            'Öz Yeterlik Bileşenleri (%)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: RadarChart(
              RadarChartData(
                dataSets: [
                  RadarDataSet(
                    fillColor: Colors.blue.withOpacity(0.2),
                    borderColor: Colors.blueAccent,
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
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.shield_outlined,
                color: Colors.blue.shade800,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Psikolojik Öz Yeterlik Analizi',
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
              color: Colors.blue.shade900,
            ),
          ),
        ],
      ),
    );
  }

  String _generateAdviceString(Map<String, double> averages) {
    final belief = averages['belief'] ?? 0;
    final resilience = averages['resilience'] ?? 0;
    final failure = averages['failure'] ?? 0;
    final learning = averages['learning'] ?? 0;
    final comparison = averages['comparison'] ?? 0;
    final control = averages['control'] ?? 0;

    String advice = "AKADEMİK ÖZ YETERLİK ALGISI ANALİZİ\n\n";

    if (belief < 15 && control > 30) {
      advice +=
          "KRİTİK TESPİT: 'Kontrol Bende Ama Yapamam'. Sürecin size bağlı olduğunu kabul ediyorsunuz ancak kendi yeteneklerinize ('Yapabilme İnancı') güvenmiyorsunuz. Bu durum, başarı sorumluluğunun omuzlarınızda bir yük haline gelmesine ve yüksek kaygıya neden olabilir.\n\n";
    }

    if (failure < 15) {
      advice +=
          "ÖZEL ANALİZ: 'Hata Fobisi'. Yanlış yapmayı bir öğrenme fırsatı değil, bir yetersizlik kanıtı olarak görüyorsunuz. Bu algı, yeni ve zor konulara başlamanızı engelliyor olabilir. Hatanın becerinizle değil, sürecinizle ilgili olduğunu fark etmeniz kritiktir.\n\n";
    }

    advice += "1. Öz Yeterlik ve Özgüven Profiliniz\n";
    final scores = {
      'Yapabilme İnancı': belief,
      'Zorlanma Güveni': resilience,
      'Hata Toleransı': failure,
      'Öğrenme Güveni': learning,
      'Sosyal Kıyas': comparison,
      'Akademik Kontrol': control,
    };
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    advice +=
        "Kendinizi en güçlü hissettiğiniz alan: ${sorted[0].key}. Güçlendirilmesi gereken kök inanç: ${sorted.last.key}.\n\n";

    advice += "2. 'Yapabilirim' Algısını Geliştirme Stratejileri\n";
    if (belief < 25) {
      advice +=
          "- 'Mikro Başarılar' hedefleyin. Kendinizi en yetersiz hissettiğiniz derste, sadece 5 dakikalık tam anlayabileceğiniz bir görev belirleyin ve yapın. Başarı, inancı besler.\n- Geçmişteki küçük başarılarınızı listeleyin; 'yapabildiğiniz' anları hatırlayın.\n";
    } else if (resilience < 25) {
      advice +=
          "- Zorluğu 'beyin antrenmanı' olarak etiketleyin. Zor bir soruyla karşılaştığınızda 'eyvah yapamam' yerine 'şu an beynim gelişiyor' demeyi deneyin.\n- Sabrınızı ölçmek için zor işlerin başında kalma sürenizi her gün 1 dakika artırın.\n";
    } else if (comparison < 25) {
      advice +=
          "- 'Düne Göre Ben' kriterini kullanın. Tek rakibiniz dünkü haliniz olsun. Başkalarının başarı hikayeleri sadece size ilham versin, kendi değerinizi onların sonuçlarıyla belirlemeyin.\n- Sosyal medyada başarı kıyası yapan hesaplardan uzak durun.\n";
    }

    advice += "\n3. Rehberlik ve Destek Yaklaşımı (Veli & Öğretmen)\n";
    if (failure < 20) {
      advice +=
          "Öğrenciye 'sonuç odaklı' değil, 'çaba odaklı' geri bildirim verin. Hatalı sorularını birlikte analiz ederken 'neden yanlış yaptın?' yerine 'buradan ne öğrendik?' sorusuna odaklanın. Hata yapmanın güvenli olduğu bir ortam sağlayın.\n";
    } else if (control < 20) {
      advice +=
          "Öğrenci başarısını şansa veya dış etkenlere bağlıyor (Dışsal Denetim Odağı). Ona küçük sorumluluklar vererek, çabasının sonucu nasıl değiştirdiğini somut olarak görmesini sağlayın.\n";
    } else {
      advice +=
          "Öğrenci öz yeterliği yüksek. Ona daha iddialı hedefler ve 'yıkıcı olmayan' zorluklar sunarak liderlik potansiyelini destekleyin.\n";
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
              'İnanç: ${stats['belief']?.toInt()} | Hata Tol.: ${stats['failure']?.toInt()} | Kontrol: ${stats['control']?.toInt()}',
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
                color: Colors.blueAccent,
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
        'belief': 40,
        'resilience': 40,
        'failure': 40,
        'learning': 40,
        'comparison': 40,
        'control': 40,
      };

      final pdfBytes = await pdfService.generateSurveyReportPdf(
        title: 'Akademik Öz Yeterlik Algısı Ölçeği (AÖ-YAÖ)',
        subTitle: subTitle,
        averages: averages,
        categoryNames: _categoryNames,
        categoryMax: categoryMax,
        respondentCount: count,
        advice: _generateAdviceString(averages),
      );

      await FileSaver.instance.saveFile(
        name: 'AOYAO_Rapor',
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
      var sheet = excel['Öz Yeterlik Analizi'];
      sheet.appendRow([
        TextCellValue('Öğrenci Adı'),
        TextCellValue('Yapabilme İnancı'),
        TextCellValue('Zorlanma Güveni'),
        TextCellValue('Hata Toleransı'),
        TextCellValue('Öğrenme Güveni'),
        TextCellValue('Sosyal Kıyas'),
        TextCellValue('Akademik Kontrol'),
      ]);
      for (var r in filtered) {
        final stats = _calculateStudentStats(r);
        sheet.appendRow([
          TextCellValue(widget.userNames[r['userId']] ?? 'Bilinmeyen'),
          DoubleCellValue(stats['belief'] ?? 0),
          DoubleCellValue(stats['resilience'] ?? 0),
          DoubleCellValue(stats['failure'] ?? 0),
          DoubleCellValue(stats['learning'] ?? 0),
          DoubleCellValue(stats['comparison'] ?? 0),
          DoubleCellValue(stats['control'] ?? 0),
        ]);
      }
      var b = excel.save();
      if (b != null)
        await FileSaver.instance.saveFile(
          name: 'AOYAO_Excel',
          bytes: Uint8List.fromList(b),
          ext: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
    } catch (e) {
      print('Excel error: $e');
    }
  }
}
