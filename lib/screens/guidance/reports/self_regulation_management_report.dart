import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/survey_model.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../../services/pdf_service.dart';

class SelfRegulationManagementReport extends StatefulWidget {
  final Survey survey;
  final List<Map<String, dynamic>> responses;
  final Map<String, String> userNames;

  const SelfRegulationManagementReport({
    Key? key,
    required this.survey,
    required this.responses,
    required this.userNames,
  }) : super(key: key);

  @override
  State<SelfRegulationManagementReport> createState() =>
      _SelfRegulationManagementReportState();
}

class _SelfRegulationManagementReportState
    extends State<SelfRegulationManagementReport>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedScope = 'institution';
  String? _selectedBranch;
  String? _selectedStudent;

  final Map<String, List<int>> _categories = {
    'planning': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
    'impulse': [13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24],
    'energy': [25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36],
    'emotion': [37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48],
    'persistence': [49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60],
  };

  final Map<String, String> _categoryNames = {
    'planning': 'Hedef ve Planlama',
    'impulse': 'Dürtü Kontrolü',
    'energy': 'Enerji Yönetimi',
    'emotion': 'Duygusal Düzenleme',
    'persistence': 'Sürdürülebilirlik',
  };

  final List<int> _reverseItems = [
    2, 4, 6, 8, 10, 12, // A
    13, 15, 17, 18, 19, 21, 24, // B
    26, 28, 30, 32, 34, 36, // C
    38, 40, 42, 44, 46, 48, // D
    50, 52, 54, 56, 58, 60, // E
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
    final impulse = averages['impulse'] ?? 0;
    final persistence = averages['persistence'] ?? 0;
    final planning = averages['planning'] ?? 0;

    String profile;
    Color color;
    if (planning > 35 && persistence > 35 && impulse > 35) {
      profile = 'Kendi Kendini Yöneten / Disiplinli';
      color = Colors.green;
    } else if (impulse < 20) {
      profile = 'Dürtüsel / Dış Etki Odaklı';
      color = Colors.red;
    } else if (planning < 20) {
      profile = 'Yönsüz / Strateji Eksikliği';
      color = Colors.orange;
    } else {
      profile = 'Uygulama Zorluğu Yaşayan / Potansiyelli';
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
              'Öz-Düzenleme ve Yönetim Profili',
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
                  'Dürtü Kontrolü / 48',
                  impulse.toStringAsFixed(1),
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
      height: 380,
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
            'Öz-Düzenleme Kapasitesi (%)',
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
              Icon(Icons.psychology, color: Colors.indigo.shade800, size: 24),
              const SizedBox(width: 8),
              Text(
                'Kapsamlı Karakter ve Yönetim Analizi',
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
    final planning = averages['planning'] ?? 0;
    final impulse = averages['impulse'] ?? 0;
    final energy = averages['energy'] ?? 0;
    final emotion = averages['emotion'] ?? 0;
    final persistence = averages['persistence'] ?? 0;

    String advice = "ÖZ-DÜZENLEME VE KENDİNİ YÖNETME ANALİZ RAPORU\n\n";

    if (impulse < 20 && planning > 30) {
      advice +=
          "KRİTİK TESPİT: 'Plan Var, Kontrol Yok'. Kağıt üzerinde mükemmel planlar yapabiliyorsunuz ancak uygulama aşamasında anlık dürtüler (telefon, dinlenme isteği, erteleme) sizi yolunuzdan saptırıyor. Sorununuz 'bilmemek' değil, 'dürtüleri frenleyememek'.\n\n";
    }

    if (persistence < 20 && emotion < 20) {
      advice +=
          "ÖZEL ANALİZ: 'Duygusal Kırılganlık ve Süreksizlik'. Moraliniz bozulduğunda veya bir hata yaptığınızda çalışmayı tamamen bırakma eğilimindesiniz. Duygusal öz-düzenleme zayıf olduğu için davranışlarınızda istikrar sağlayamıyorsunuz.\n\n";
    }

    advice += "1. Yönetim Kapasitesi Bileşenleri\n";
    final scores = {
      'Planlama Stratejisi': planning,
      'Dürtü Kontrol Gücü': impulse,
      'Zaman/Enerji Verimi': energy,
      'Duygusal Denge': emotion,
      'Sürdürülebilirlik': persistence,
    };
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    advice +=
        "En gelişmiş beceriniz: ${sorted[0].key}. Acil müdahale gereken alan: ${sorted.last.key}.\n\n";

    advice += "2. Müdahale ve Gelişim Stratejileri\n";
    if (impulse < 25) {
      advice +=
          "- 'Çevresel Kontrol' uygulayın. Çalışma anında telefonunuzu başka bir odaya bırakın. İradenizi kullanmak yerine, irade gerektirmeyen ortamlar yaratın.\n- 'Eğer-Öyleyse' planları yapın: 'Eğer telefonuma bakma isteği gelirse, 2 dakika boyunca sadece önümdeki soruya odaklanacağım'.\n";
    } else if (planning < 25) {
      advice +=
          "- 'Mikro Planlama' ile başlayın. Haftalık değil, her sabah o günün en kritik 3 görevini belirleyin.\n- Plan yapmayı bir yük değil, zihinsel bir boşaltma aracı olarak görün.\n";
    } else if (persistence < 25) {
      advice +=
          "- 'Zinciri Kırma' yöntemini kullanın. Küçük ama her gün yapılan bir rutin oluşturun.\n- Sürekliliği sağlamak için sadece sonuca değil, 'bugün masaya oturmuş olma' zaferine odaklanın.\n";
    }

    advice += "\n3. Rehberlik, Veli ve Öğretmen Notu\n";
    if (impulse < 20) {
      advice +=
          "Öğrenciye 'neden çalışmıyorsun?' diye sormak yerine, dikkatini dağıtan faktörleri azaltmak için ona rehberlik edilmelidir. Onun sorunu iradesizlik değil, uyaran bolluğu karşısında kontrolü kaybetmesidir.\n";
    } else if (emotion < 20) {
      advice +=
          "Öğrencinin performans kayıplarının arkasında 'akademik kaygı' veya 'öz-güven yetersizliği' olabilir. Duygusal toparlanma becerileri üzerine çalışılmalıdır.\n";
    } else {
      advice +=
          "Öğrenci kendini yönetme becerisine sahip. Ona daha karmaşık projeler ve özerklik verilerek liderlik potansiyeli desteklenmelidir.\n";
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
              'Plan: ${stats['planning']?.toInt()} | Dürtü: ${stats['impulse']?.toInt()} | Sebat: ${stats['persistence']?.toInt()}',
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
        'planning': 48,
        'impulse': 48,
        'energy': 48,
        'emotion': 48,
        'persistence': 48,
      };

      final pdfBytes = await pdfService.generateSurveyReportPdf(
        title: 'Öz-Düzenleme ve Kendini Yönetme Ölçeği',
        subTitle: subTitle,
        averages: averages,
        categoryNames: _categoryNames,
        categoryMax: categoryMax,
        respondentCount: count,
        advice: _generateAdviceString(averages),
      );

      await FileSaver.instance.saveFile(
        name: 'SRM_Rapor',
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
      var sheet = excel['Öz-Düzenleme'];
      sheet.appendRow([
        TextCellValue('Öğrenci Adı'),
        TextCellValue('Planlama'),
        TextCellValue('Dürtü Kontrolü'),
        TextCellValue('Enerji'),
        TextCellValue('Duygusal'),
        TextCellValue('Sürdürülebilirlik'),
      ]);
      for (var r in filtered) {
        final stats = _calculateStudentStats(r);
        sheet.appendRow([
          TextCellValue(widget.userNames[r['userId']] ?? 'Bilinmeyen'),
          DoubleCellValue(stats['planning'] ?? 0),
          DoubleCellValue(stats['impulse'] ?? 0),
          DoubleCellValue(stats['energy'] ?? 0),
          DoubleCellValue(stats['emotion'] ?? 0),
          DoubleCellValue(stats['persistence'] ?? 0),
        ]);
      }
      var b = excel.save();
      if (b != null)
        await FileSaver.instance.saveFile(
          name: 'SRM_Excel',
          bytes: Uint8List.fromList(b),
          ext: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
    } catch (e) {
      print('Excel error: $e');
    }
  }
}
