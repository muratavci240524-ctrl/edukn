import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/survey_model.dart';
import 'package:flutter/gestures.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../../services/pdf_service.dart';

class TestAnxietyReport extends StatefulWidget {
  final Survey survey;
  final List<Map<String, dynamic>> responses;
  final Map<String, String> userNames;

  const TestAnxietyReport({
    Key? key,
    required this.survey,
    required this.responses,
    required this.userNames,
  }) : super(key: key);

  @override
  State<TestAnxietyReport> createState() => _TestAnxietyReportState();
}

class _TestAnxietyReportState extends State<TestAnxietyReport>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedScope = 'institution'; // 'institution', 'branch', 'student'
  String? _selectedBranch;
  String? _selectedStudent;

  final Map<String, List<int>> _categories = {
    'perception_others': [3, 14, 17, 25, 32, 41, 46, 47],
    'perception_self': [2, 9, 16, 24, 31, 38, 40],
    'future': [1, 8, 15, 23, 30, 49],
    'preparation': [6, 11, 18, 26, 33, 42],
    'physical': [5, 12, 19, 27, 34, 39, 43],
    'mental': [4, 13, 20, 21, 28, 35, 36, 37, 48, 50],
    'general': [7, 10, 22, 29, 44, 45],
  };

  final Map<String, String> _categoryNames = {
    'perception_others': 'Başkalarının Görüşü',
    'perception_self': 'Kendi Görüşünüz',
    'future': 'Gelecek Endişeleri',
    'preparation': 'Hazırlanma Endişeleri',
    'physical': 'Bedensel Tepkiler',
    'mental': 'Zihinsel Tepkiler',
    'general': 'Genel Sınav Kaygısı',
  };

  final Map<String, int> _categoryMax = {
    'perception_others': 8,
    'perception_self': 7,
    'future': 6,
    'preparation': 6,
    'physical': 7,
    'mental': 10,
    'general': 6,
  };

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

      // Fetch all branches
      final branchesSnap = await FirebaseFirestore.instance
          .collection('branches')
          .where('institutionId', isEqualTo: instId)
          .get();
      final allBranches = branchesSnap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .toList();

      // Fetch all student users to know their branches
      final usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: instId)
          .where('role', isEqualTo: 'Öğrenci')
          .get();
      for (var d in usersSnap.docs) {
        _userDetails[d.id] = d.data();
      }

      // Filter branches: Only those with at least one respondent
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
                      onPressed: _exportSummaryToPdf,
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
                      onPressed: _exportTableToExcel,
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
              _buildSummaryAnalysis(averages, filtered.length),
              _buildDetailedResults(filtered),
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
                    selectedBackgroundColor: const Color(0xFFEBE3FF),
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
                      icon: Icon(Icons.check, size: 16),
                    ),
                    ButtonSegment(
                      value: 'branch',
                      label: Text('Şube'),
                      icon: Icon(Icons.check, size: 16),
                    ),
                    ButtonSegment(
                      value: 'student',
                      label: Text('Öğrenci'),
                      icon: Icon(Icons.check, size: 16),
                    ),
                  ],
                  selected: {_selectedScope},
                  showSelectedIcon: true,
                  onSelectionChanged: (val) {
                    setState(() {
                      _selectedScope = val.first;
                      _selectedBranch = null;
                      _selectedStudent = null;

                      // Auto switch tab for better UX
                      if (_selectedScope == 'institution') {
                        _tabController.index = 0;
                      } else if (_selectedScope == 'student') {
                        _tabController.index = 1;
                      }
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
    Map<String, double> results = {};

    _categories.forEach((catId, questionNums) {
      int score = 0;
      for (var qNum in questionNums) {
        if (answers['q$qNum'] == 'D') score += 1;
      }
      results[catId] = score.toDouble();
    });

    return results;
  }

  Widget _buildSummaryAnalysis(Map<String, double> averages, int count) {
    if (count == 0) return Center(child: Text('Yanıt henüz bulunmamaktadır.'));

    final radarData = _categories.keys.map((catId) {
      final val = averages[catId] ?? 0;
      final max = _categoryMax[catId]?.toDouble() ?? 1.0;
      return val / max; // Normalized for radar
    }).toList();

    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        children: [
          _buildRadarChart(radarData),
          SizedBox(height: 32),
          _buildInterpretationCards(averages),
        ],
      ),
    );
  }

  Widget _buildRadarChart(List<double> normalizedData) {
    return Column(
      children: [
        Text(
          'Kaygı Profili (0-100 Ölçekli)',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.indigo.shade900,
          ),
        ),
        SizedBox(height: 24),
        SizedBox(
          height: 300,
          child: RadarChart(
            RadarChartData(
              dataSets: [
                RadarDataSet(
                  fillColor: Colors.indigo.withOpacity(0.2),
                  borderColor: Colors.indigo,
                  entryRadius: 3,
                  dataEntries: normalizedData
                      .map((v) => RadarEntry(value: v * 100))
                      .toList(),
                ),
              ],
              radarShape: RadarShape.polygon,
              tickCount: 5,
              ticksTextStyle: const TextStyle(color: Colors.grey, fontSize: 10),
              gridBorderData: const BorderSide(color: Colors.grey, width: 0.5),
              radarBackgroundColor: Colors.transparent,
              radarBorderData: const BorderSide(color: Colors.indigo, width: 1),
              getTitle: (index, angle) {
                final key = _categories.keys.elementAt(index);
                return RadarChartTitle(
                  text: _categoryNames[key]!,
                  angle: angle,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInterpretationCards(Map<String, double> averages) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Alt Boyut Analizleri',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 16),
        ..._categories.keys.map((catId) {
          final score = averages[catId] ?? 0;
          final max = _categoryMax[catId]!;
          final comment = _getCategoryComment(catId, score);
          final isHigh = _isHighRisk(catId, score);

          return Card(
            margin: EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _categoryNames[catId]!,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isHigh
                              ? Colors.red.shade50
                              : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${score.toStringAsFixed(1)} / $max',
                          style: TextStyle(
                            color: isHigh ? Colors.red : Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(comment, style: TextStyle(color: Colors.grey.shade800)),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  String _getCategoryComment(String catId, double score) {
    switch (catId) {
      case 'perception_others':
        return score >= 4
            ? 'Başkalarının sizi nasıl gördüğü sizin için çok önemlidir; bu durum sınavlarda zihinsel performansınızı olumsuz etkileyebilir.'
            : 'Başkalarının görüşleri sınav performansınızı belirgin biçimde etkilememektedir.';
      case 'perception_self':
        return score >= 4
            ? 'Sınav başarınızı kişisel değerinizle eş tutma eğilimi vardır; bu durum kaygıyı artırmaktadır.'
            : 'Sınav başarısı ile kişisel değerinizi ayırabildiğiniz görülmektedir.';
      case 'future':
        return score >= 3
            ? 'Sınavları geleceğinizin tek belirleyicisi olarak görme eğilimi vardır.'
            : 'Geleceğin yalnızca sınav başarısına bağlı olmadığının farkındasınızdır.';
      case 'preparation':
        return score >= 3
            ? 'Sınavlara hazırlık süreci yoğun kaygı yaratmaktadır.'
            : 'Sınavlara hazırlık sürecini daha dengeli yönetebildiğiniz görülmektedir.';
      case 'physical':
        return score >= 4
            ? 'Sınavlara hazırlık sürecinde bedensel belirtiler yoğundur.'
            : 'Bedensel tepkiler kontrol edilebilmektedir.';
      case 'mental':
        return score >= 4
            ? 'Dikkat dağınıklığı ve zihinsel blokajlar belirgindir.'
            : 'Zihinsel tepkiler kontrol altındadır.';
      case 'general':
        return score >= 3
            ? 'Yüksek düzeyde genel sınav kaygısı vardır.'
            : 'Genel sınav kaygısı düşüktür.';
      default:
        return '';
    }
  }

  bool _isHighRisk(String catId, double score) {
    if (catId == 'perception_others') return score >= 4;
    if (catId == 'perception_self') return score >= 4;
    if (catId == 'future') return score >= 3;
    if (catId == 'preparation') return score >= 3;
    if (catId == 'physical') return score >= 4;
    if (catId == 'mental') return score >= 4;
    if (catId == 'general') return score >= 3;
    return false;
  }

  Widget _buildDetailedResults(List<Map<String, dynamic>> filtered) {
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final r = filtered[index];
        final name = widget.userNames[r['userId']] ?? 'Bilinmeyen';
        final stats = _calculateStudentStats(r);

        return Card(
          child: ListTile(
            title: Text(name, style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Kaygı Alanları: ${_getHighRiskCats(stats)}'),
            trailing: Icon(Icons.info_outline, color: Colors.indigo),
            onTap: () => _showStudentDetail(name, r),
          ),
        );
      },
    );
  }

  String _getHighRiskCats(Map<String, double> stats) {
    List<String> high = [];
    stats.forEach((key, val) {
      if (_isHighRisk(key, val)) high.add(_categoryNames[key]!);
    });
    return high.isEmpty ? 'Hafif/Normal' : high.join(', ');
  }

  void _showStudentDetail(String studentName, Map<String, dynamic> response) {
    final stats = _calculateStudentStats(response);
    final adviceString = _generateAdviceString(stats, isForcedIndividual: true);

    showDialog(
      context: context,
      builder: (context) => DefaultTabController(
        length: 2,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            width: 700,
            height: 750,
            padding: EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sınav Kaygısı Analiz Profili',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          Text(
                            studentName,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                TabBar(
                  labelColor: Colors.indigo,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Colors.indigo,
                  tabs: [
                    Tab(text: 'PUAN TABLOSU'),
                    Tab(text: 'YORUM VE ÖNERİLER'),
                  ],
                ),
                SizedBox(height: 16),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildModalPuanTab(stats),
                      _buildModalReportTab(adviceString),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModalPuanTab(Map<String, double> stats) {
    return SingleChildScrollView(
      child: Table(
        columnWidths: const {0: FlexColumnWidth(4), 1: FlexColumnWidth(2)},
        border: TableBorder.all(color: Colors.grey.shade200),
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.indigo.shade900),
            children: [
              _buildModalHeaderCell('ALT BOYUT'),
              _buildModalHeaderCell('PUAN'),
            ],
          ),
          ..._categories.keys.map((catId) {
            final val = stats[catId] ?? 0;
            final max = _categoryMax[catId]!;
            final isHigh = _isHighRisk(catId, val);
            return TableRow(
              decoration: BoxDecoration(
                color: isHigh ? Colors.red.shade50 : Colors.green.shade50,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    _categoryNames[catId]!,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    '${val.toInt()} / $max',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isHigh ? Colors.red : Colors.green,
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildModalReportTab(String advice) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Container(
        padding: EdgeInsets.all(20),
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
                Icon(Icons.auto_awesome, color: Colors.indigo, size: 20),
                SizedBox(width: 8),
                Text(
                  'Kişiselleştirilmiş Yorum',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            Divider(height: 32),
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
      ),
    );
  }

  Widget _buildModalHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  String _generateAdviceString(
    Map<String, double> stats, {
    bool isForcedIndividual = false,
  }) {
    String advice = "";
    bool isIndividual = isForcedIndividual || _selectedScope == 'student';

    String target = isIndividual ? "öğrencinin" : "grubun";

    // Introduction
    advice = isIndividual
        ? "Bu rapor, öğrencimizin sınav kaygısı düzeyini ve kaygının hangi alanlarda yoğunlaştığını belirlemek amacıyla hazırlanmıştır.\n\n"
        : "Bu rapor, seçili öğrenci grubunun sınav kaygısı eğilimlerini ve genel endişe alanlarını analiz etmektedir.\n\n";

    // Subscale insights
    List<String> highRiskAreas = [];
    _categories.keys.forEach((catId) {
      if (_isHighRisk(catId, stats[catId] ?? 0)) {
        highRiskAreas.add(_categoryNames[catId]!);
      }
    });

    if (highRiskAreas.isNotEmpty) {
      advice +=
          "• DİKKAT ÇEKEN ALANLAR: $target şu alanlarda kaygı düzeyi normalin üzerindedir: ${highRiskAreas.join(', ')}.\n";
      advice +=
          "  Bu alanlardaki yüksek kaygı, sınav performansını ve öğrenme sürecini olumsuz etkileyebilir.\n\n";
    } else {
      advice +=
          "• GENEL DURUM: $target sınav kaygısı düzeyi tüm alt boyutlarda kontrol edilebilir sınırlar içerisindedir.\n\n";
    }

    // Specific advice based on top categories
    advice += "• ÖNERİLER:\n";
    if (_isHighRisk('perception_others', stats['perception_others'] ?? 0)) {
      advice +=
          "  - Başkalarının yargılarından ziyade sürece ve gelişime odaklanması için özgüven destekleme çalışmaları yapılmalıdır.\n";
    }
    if (_isHighRisk('physical', stats['physical'] ?? 0)) {
      advice +=
          "  - Nefes egzersizleri ve gevşeme teknikleri öğretilerek bedensel tepkilerin kontrolü sağlanmalıdır.\n";
    }
    if (_isHighRisk('mental', stats['mental'] ?? 0)) {
      advice +=
          "  - Sınav sırasında zihni toparlama teknikleri ve olumsuz otomatik düşüncelerle baş etme becerileri kazandırılmalıdır.\n";
    }
    if (_isHighRisk('preparation', stats['preparation'] ?? 0)) {
      advice +=
          "  - Zaman yönetimi ve daha verimli çalışma yöntemleri konusunda rehberlik edilmelidir.\n";
    }

    if (highRiskAreas.isEmpty) {
      advice +=
          "  - Mevcut dengeli tutum korunmalı, sınavlara gerçekçi beklentilerle yaklaşmaya devam edilmelidir.\n";
    }

    advice +=
        "\nNOT: Bu ölçek tanılama amaçlı değildir. Belirgin kaygı durumlarında bir rehber öğretmen veya uzmana başvurulması önerilir.";

    return advice;
  }

  Future<void> _exportSummaryToPdf() async {
    final filtered = _getFilteredResponses();
    final averages = _calculateAverages(filtered);
    final pdfService = PdfService();

    String subTitle = _selectedScope == 'student'
        ? "${widget.userNames[_selectedStudent] ?? 'Öğrenci'} - Bireysel Analiz"
        : (_selectedScope == 'branch'
              ? "${_selectedBranch ?? 'Tüm Şubeler'} Şube Analizi"
              : "Genel Kurum Analizi");

    final advice = _generateAdviceString(averages);

    final pdfBytes = await pdfService.generateSurveyReportPdf(
      title: widget.survey.title,
      subTitle: subTitle,
      averages: averages,
      categoryNames: _categoryNames,
      categoryMax: _categoryMax,
      respondentCount: filtered.length,
      advice: advice,
    );

    await FileSaver.instance.saveFile(
      name: '${widget.survey.title}_Rapor',
      bytes: pdfBytes,
      ext: 'pdf',
      mimeType: MimeType.pdf,
    );
  }

  Future<void> _exportTableToExcel() async {
    final filtered = _getFilteredResponses();
    var excel = Excel.createExcel();
    Sheet sheet = excel['Döküm Tablosu'];

    // Header
    List<CellValue> headers = [TextCellValue('Öğrenci Adı')];
    for (var name in _categoryNames.values) {
      headers.add(TextCellValue(name));
    }
    sheet.appendRow(headers);

    // Data
    for (var r in filtered) {
      final stats = _calculateStudentStats(r);
      List<CellValue> row = [
        TextCellValue(widget.userNames[r['userId']] ?? 'Bilinmeyen'),
      ];
      for (var s in _categoryNames.keys) {
        row.add(IntCellValue(stats[s]?.toInt() ?? 0));
      }
      sheet.appendRow(row);
    }

    final bytes = Uint8List.fromList(excel.encode()!);
    await FileSaver.instance.saveFile(
      name: '${widget.survey.title}_Dokum',
      bytes: bytes,
      ext: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
  }
}

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
  };
}
