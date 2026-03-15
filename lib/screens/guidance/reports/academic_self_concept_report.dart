import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../models/survey_model.dart';
import '../../../models/guidance/tests/academic_self_concept_norm_data.dart';
import 'package:flutter/gestures.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../../services/pdf_service.dart';

class AcademicSelfConceptReport extends StatefulWidget {
  final Survey survey;
  final List<Map<String, dynamic>> responses;
  final Map<String, String> userNames;

  const AcademicSelfConceptReport({
    Key? key,
    required this.survey,
    required this.responses,
    required this.userNames,
  }) : super(key: key);

  @override
  State<AcademicSelfConceptReport> createState() =>
      _AcademicSelfConceptReportState();
}

class _AcademicSelfConceptReportState extends State<AcademicSelfConceptReport>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedScope = 'institution'; // 'institution', 'branch', 'student'
  String? _selectedBranch;
  String? _selectedStudent;

  final Map<String, List<int>> _subscales = {
    'sozel': [1, 2, 5, 8, 11, 12, 19, 22, 24, 30, 31],
    'sayisal': [3, 9, 13, 20, 21, 23, 26, 29, 32],
    'sekil_uzay': [4, 6, 7, 10, 14, 15, 16, 18, 25, 28, 33],
    'goz_el': [27, 34, 35, 36, 39, 40],
    'fen_bilimleri': [38, 41, 45, 46, 49, 50, 55, 58, 59, 63],
    'sosyal_bilimler': [42, 53, 54, 56, 57, 61, 62, 64, 65, 68],
    'ziraat': [47, 69, 72, 75, 76, 78, 80, 82, 83, 85],
    'mekanik': [17, 70, 71, 79, 81, 84, 86, 91, 95, 107, 118, 127],
    'ikna': [87, 88, 92, 96, 108, 109, 119, 128, 150, 168],
    'ticaret': [90, 97, 99, 101, 110, 111, 120, 122, 123, 126, 129, 130],
    'is_ayrinti': [93, 94, 98, 102, 104, 105, 112, 121, 125],
    'edebiyat': [43, 57, 100, 103, 113, 114, 116, 131, 142, 143, 165, 166],
    'yabanci_dil': [48, 51, 73, 74, 77, 106, 124, 157, 170],
    'sanat': [115, 117, 132, 135, 136, 147, 149, 160, 162, 163],
    'muzik': [133, 134, 144, 145, 152, 153, 156, 159, 161, 164],
    'sosyal_yardim': [44, 137, 138, 139, 140, 146, 148, 151, 154, 155],
  };

  final Map<String, String> _subscaleNames = {
    'sozel': 'Sözel Yetenek',
    'sayisal': 'Sayısal Yetenek',
    'sekil_uzay': 'Şekil-Uzay Yet.',
    'goz_el': 'Göz-El Koord.',
    'fen_bilimleri': 'Fen Bilimleri',
    'sosyal_bilimler': 'Sosyal Bilimler',
    'ziraat': 'Ziraat',
    'mekanik': 'Mekanik',
    'ikna': 'İkna',
    'ticaret': 'Ticaret',
    'is_ayrinti': 'İş Ayrıntıları',
    'edebiyat': 'Edebiyat',
    'yabanci_dil': 'Yabancı Dil',
    'sanat': 'Güzel Sanatlar',
    'muzik': 'Müzik',
    'sosyal_yardim': 'Sosyal Yardım',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildFilters(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [_buildSummaryAnalysis(), _buildDetailedResults()],
          ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'institution', label: Text('Kurum')),
                    ButtonSegment(value: 'branch', label: Text('Şube')),
                    ButtonSegment(value: 'student', label: Text('Öğrenci')),
                  ],
                  selected: {_selectedScope},
                  onSelectionChanged: (val) {
                    setState(() {
                      _selectedScope = val.first;
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
            SizedBox(height: 12),
            if (_selectedScope == 'branch')
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'Şube Seçin',
                  isDense: true,
                ),
                value: _selectedBranch,
                items: _getBranches()
                    .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                    .toList(),
                onChanged: (val) => setState(() => _selectedBranch = val),
              ),
            if (_selectedScope == 'student')
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'Öğrenci Seçin',
                  isDense: true,
                ),
                value: _selectedStudent,
                items: widget.responses.map((r) {
                  final uid = r['userId'].toString();
                  return DropdownMenuItem(
                    value: uid,
                    child: Text(widget.userNames[uid] ?? 'Bilinmeyen'),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedStudent = val),
              ),
          ],
          SizedBox(height: 16),
          TabBar(
            controller: _tabController,
            labelColor: Colors.indigo,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.indigo,
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Genel Analiz'),
                    SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.picture_as_pdf,
                        size: 18,
                        color: Colors.red,
                      ),
                      onPressed: _exportSummaryToPdf,
                      tooltip: 'PDF Olarak İndir',
                      constraints: BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Sonuç Tablosu'),
                    SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.description,
                        size: 18,
                        color: Colors.green,
                      ),
                      onPressed: _exportTableToExcel,
                      tooltip: 'Excel Olarak İndir',
                      constraints: BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<String> _getBranches() {
    // Collect branches from responses/userDetails?
    // For now, let's assume we can't easily get it without full user data.
    // Simplifying: we'll show all students in the table.
    return [];
  }

  Widget _buildSummaryAnalysis() {
    final filtered = _getFilteredResponses();
    if (filtered.isEmpty) return Center(child: Text('Henüz veri yok.'));

    final averages = _calculateAverages(filtered);

    return ScrollConfiguration(
      behavior: MyCustomScrollBehavior(),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildRadarChart(averages),
            SizedBox(height: 24),
            _buildInterpretation(averages),
          ],
        ),
      ),
    );
  }

  Widget _buildRadarChart(Map<String, double> averages) {
    final subscales = _subscaleNames.keys.toList();

    return AspectRatio(
      aspectRatio: 1.3,
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: RadarChart(
          RadarChartData(
            dataSets: [
              RadarDataSet(
                fillColor: Colors.indigo.withOpacity(0.3),
                borderColor: Colors.indigo,
                entryRadius: 3,
                dataEntries: subscales
                    .map((s) => RadarEntry(value: averages[s] ?? 0))
                    .toList(),
              ),
            ],
            radarBackgroundColor: Colors.transparent,
            borderData: FlBorderData(show: false),
            radarBorderData: const BorderSide(color: Colors.transparent),
            titlePositionPercentageOffset: 0.2,
            titleTextStyle: const TextStyle(
              color: Colors.black54,
              fontSize: 10,
            ),
            getTitle: (index, angle) {
              return RadarChartTitle(
                text: _subscaleNames[subscales[index]] ?? '',
              );
            },
            tickCount: 4,
            ticksTextStyle: const TextStyle(color: Colors.grey, fontSize: 8),
            gridBorderData: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
        ),
      ),
    );
  }

  Widget _buildInterpretation(Map<String, double> averages) {
    final strong = averages.entries.where((e) => e.value >= 75).toList();
    final medium = averages.entries
        .where((e) => e.value >= 25 && e.value < 75)
        .toList();
    final weak = averages.entries.where((e) => e.value < 25).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Profil Özeti',
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 12),
        _buildTrendBox('Güçlü Alanlar', strong, Colors.green),
        _buildTrendBox('Orta Düzey Alanlar', medium, Colors.orange),
        _buildTrendBox('Geliştirilmesi Gerekenler', weak, Colors.red),
        SizedBox(height: 24),
        _buildNarrativeInterpretation(averages),
      ],
    );
  }

  Widget _buildTrendBox(
    String title,
    List<MapEntry<String, double>> items,
    Color color,
  ) {
    if (items.isEmpty) return SizedBox.shrink();
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star, color: color, size: 16),
              SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
          SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: items
                .map(
                  (e) => Chip(
                    label: Text(
                      '${_subscaleNames[e.key]} (%${e.value.toStringAsFixed(0)})',
                    ),
                    backgroundColor: Colors.white,
                    side: BorderSide(color: color.withOpacity(0.3)),
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrativeInterpretation(Map<String, double> averages) {
    // Simple logic: Cross-reference Ability (Yetenek) and Interest (İlgi)
    String advice = "";

    // Check Numerical + Science
    if ((averages['sayisal'] ?? 0) > 70 &&
        (averages['fen_bilimleri'] ?? 0) > 70) {
      advice +=
          "• Sayısal yetenek ve fen bilimleri ilgisi çok yüksek. Mühendislik, tıp veya fen bilimleri araştırmacılığı gibi alanlara eğilimi güçlüdür.\n";
    }

    // Check Verbal + Social/Literature/Foreign Language
    if ((averages['sozel'] ?? 0) > 70 &&
        ((averages['sosyal_bilimler'] ?? 0) > 70 ||
            (averages['edebiyat'] ?? 0) > 70)) {
      advice +=
          "• Sözel ifade gücü ve sosyal alanlara olan ilgisi dikkat çekici. Hukuk, psikoloji, sosyal bilimler veya yazarlık gibi kariyer yolları değerlendirilebilir.\n";
    }

    if (advice.isEmpty) {
      advice =
          "• Öğrencinin ilgileri ve yetenekleri genel bir dağılım göstermektedir. Belirgin bir 'güçlü alan' sivriltmek yerine, mevcut orta düzey yeteneklerin ilgi duyulan alanlarla desteklenmesi önerilir.";
    }

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rehberlik Yorumu',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
          ),
          SizedBox(height: 8),
          Text(
            advice,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Colors.indigo.shade900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedResults() {
    final filtered = _getFilteredResponses();
    return ScrollConfiguration(
      behavior: MyCustomScrollBehavior(),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              DataColumn(label: Text('Öğrenci')),
              ..._subscaleNames.values.map(
                (name) => DataColumn(label: Text(name)),
              ),
            ],
            rows: filtered.map((r) {
              final stats = _calculateStudentStats(r);
              final uid = r['userId'].toString();
              return DataRow(
                cells: [
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.info_outline,
                            color: Colors.indigo,
                            size: 20,
                          ),
                          onPressed: () => _showStudentDetail(
                            widget.userNames[uid] ?? 'Bilinmeyen',
                            r,
                          ),
                          tooltip: 'Öğrenci Detayı',
                          constraints: BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                        SizedBox(width: 8),
                        Text(widget.userNames[uid] ?? 'Bilinmeyen'),
                      ],
                    ),
                  ),
                  ..._subscaleNames.keys.map(
                    (s) => DataCell(
                      Text('%${stats[s]?.toStringAsFixed(0) ?? "0"}'),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getFilteredResponses() {
    if (_selectedScope == 'student' && _selectedStudent != null) {
      return widget.responses
          .where((r) => r['userId'] == _selectedStudent)
          .toList();
    }
    // Simplification for branch: ignoring for now as per catalog scope
    return widget.responses;
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

    _subscales.forEach((subscaleId, questionNums) {
      int rawSum = 0;
      for (var qNum in questionNums) {
        final val = answers['q$qNum'];
        if (val != null) {
          // A=1, B=2, C=3, D=4
          if (val == 'A')
            rawSum += 1;
          else if (val == 'B')
            rawSum += 2;
          else if (val == 'C')
            rawSum += 3;
          else if (val == 'D')
            rawSum += 4;
        }
      }

      // Convert to percentile
      results[subscaleId] = AcademicSelfConceptNormData.getPercentile(
        subscaleId,
        rawSum,
      );
    });

    return results;
  }

  void _showStudentDetail(String studentName, Map<String, dynamic> response) {
    final answers = response['answers'] as Map<String, dynamic>? ?? {};

    Map<String, int> rawScores = {};
    Map<String, double> percentiles = {};

    _subscales.forEach((subscaleId, questionNums) {
      int rawSum = 0;
      for (var qNum in questionNums) {
        final val = answers['q$qNum'];
        if (val == 'A')
          rawSum += 1;
        else if (val == 'B')
          rawSum += 2;
        else if (val == 'C')
          rawSum += 3;
        else if (val == 'D')
          rawSum += 4;
      }
      rawScores[subscaleId] = rawSum;
      percentiles[subscaleId] = AcademicSelfConceptNormData.getPercentile(
        subscaleId,
        rawSum,
      );
    });

    // Separate categories
    final abilityKeys = ['sozel', 'sayisal', 'sekil_uzay', 'goz_el'];
    final interestKeys = _subscales.keys
        .where((k) => !abilityKeys.contains(k))
        .toList();

    // Sort within categories
    final sortedAbilities =
        percentiles.entries.where((e) => abilityKeys.contains(e.key)).toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    final sortedInterests =
        percentiles.entries.where((e) => interestKeys.contains(e.key)).toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    final adviceString = _generateAdviceString(
      percentiles,
      isForcedIndividual: true,
    );

    showDialog(
      context: context,
      builder: (context) => DefaultTabController(
        length: 2,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            width: 600,
            height: 700,
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
                            'Öğrenci Analiz Profili',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
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
                    Tab(text: 'SIRALAMA'),
                    Tab(text: 'ÖĞRENCİ RAPORU'),
                  ],
                ),
                SizedBox(height: 16),
                Expanded(
                  child: TabBarView(
                    children: [
                      // Tab 1: Sıralama
                      SingleChildScrollView(
                        child: Table(
                          columnWidths: const {
                            0: FlexColumnWidth(4),
                            1: FlexColumnWidth(2),
                          },
                          border: TableBorder.all(color: Colors.grey.shade200),
                          children: [
                            TableRow(
                              decoration: BoxDecoration(color: Colors.red),
                              children: [
                                _buildModalHeaderCell('ALAN'),
                                _buildModalHeaderCell('% DEĞERİ'),
                              ],
                            ),
                            // Yetenekler Section
                            TableRow(
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade900,
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    'YETENEKLER',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ),
                                Container(),
                              ],
                            ),
                            ...sortedAbilities.map(
                              (e) => TableRow(
                                decoration: BoxDecoration(
                                  color: Colors.cyan.shade50,
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Text(
                                      _subscaleNames[e.key]!.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(12.0),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '%${e.value.toStringAsFixed(1)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.indigo,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // İlgiler Section
                            TableRow(
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade900,
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    'İLGİLER',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ),
                                Container(),
                              ],
                            ),
                            ...sortedInterests.map(
                              (e) => TableRow(
                                decoration: BoxDecoration(
                                  color: Colors.cyan.shade50,
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Text(
                                      _subscaleNames[e.key]!.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(12.0),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '%${e.value.toStringAsFixed(1)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.indigo,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Tab 2: Rapor
                      SingleChildScrollView(
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
                                  Icon(
                                    Icons.auto_awesome,
                                    color: Colors.indigo,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Yapay Zeka Destekli Yorum',
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
                                adviceString,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.6,
                                  color: Colors.indigo.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
    Map<String, double> averages, {
    bool isForcedIndividual = false,
  }) {
    String advice = "";

    // Aggregate vs Individual check
    bool isIndividual = isForcedIndividual || _selectedScope == 'student';

    if (isIndividual) {
      advice =
          "Bu profil, öğrencinin akademik benlik kavramı ölçeğine verdiği yanıtların sayısal analizini içermektedir.\n\n";
    } else {
      advice =
          "Bu rapor, seçili grubun (Kurum/Şube) akademik benlik kavramı ölçeğine verdiği yanıtların genel ortalamasını yansıtmaktadır.\n\n";
    }

    // Ability (Yetenek) interpretation
    final strongAbilities = averages.entries
        .where((e) => _subscales.keys.take(4).contains(e.key) && e.value >= 75)
        .map((e) => _subscaleNames[e.key])
        .toList();

    if (strongAbilities.isNotEmpty) {
      advice +=
          "• Belirgin Yetenekler: ${strongAbilities.join(', ')} alanlarında ${isIndividual ? 'öğrencinin' : 'grubun'} potansiyeli oldukça yüksektir. Bu alanlar akademik başarının temel taşı olarak görülmelidir.\n\n";
    }

    // Interest (İlgi) interpretation
    final strongInterests = averages.entries
        .where((e) => _subscales.keys.skip(4).contains(e.key) && e.value >= 75)
        .map((e) => _subscaleNames[e.key])
        .toList();

    if (strongInterests.isNotEmpty) {
      advice +=
          "• Yüksek İlgiler: ${strongInterests.join(', ')} alanlarına karşı duyulan ilgi, kariyer planlamasında ana motivasyon kaynağı olabilir.\n\n";
    }

    // Synergy / Combinations
    advice += "• KARİYER YÖNLENDİRMELERİ:\n";
    bool anyCombo = false;

    // Numerical + Science
    if ((averages['sayisal'] ?? 0) > 70 &&
        (averages['fen_bilimleri'] ?? 0) > 70) {
      advice +=
          "  - Mühendislik ve Teknoloji: Sayısal becerileri ve fen ilgisiyle bu disiplinlerde yüksek başarı göstermesi beklenir.\n";
      anyCombo = true;
    }

    // Verbal + Social/Literature
    if ((averages['sozel'] ?? 0) > 70 &&
        ((averages['sosyal_bilimler'] ?? 0) > 70 ||
            (averages['edebiyat'] ?? 0) > 70)) {
      advice +=
          "  - Sosyal Bilimler ve Hukuk: Güçlü sözel ifade ve sosyal duyarlılık, bu alanlar için ideal bir zemin oluşturur.\n";
      anyCombo = true;
    }

    // Arts / Music
    if ((averages['sanat'] ?? 0) > 70 || (averages['muzik'] ?? 0) > 70) {
      advice +=
          "  - Güzel Sanatlar ve Tasarım: Yaratıcılık gerektiren alanlara olan eğilimi, profesyonel sanat kariyerleri için elverişlidir.\n";
      anyCombo = true;
    }

    if (!anyCombo) {
      advice +=
          "  - Çok Yönlü Gelişim: Belirli bir alana sivrilmekten ziyade, genel bir dağılım gözlenmektedir. Bu durum disiplinlerarası alanlarda avantaj sağlayabilir.\n";
    }

    // Recommendations
    final weakAreas = averages.entries
        .where((e) => e.value < 25)
        .map((e) => _subscaleNames[e.key])
        .toList();

    if (weakAreas.isNotEmpty) {
      advice +=
          "\n• GELİŞTİRİLMESİ GEREKENLER: ${weakAreas.join(', ')} alanlarında farkındalığın artırılması ve ek destek çalışmaları önerilir.";
    }

    return advice;
  }

  Future<void> _exportSummaryToPdf() async {
    final filtered = _getFilteredResponses();
    final averages = _calculateAverages(filtered);
    final pdfService = PdfService();

    String subTitle = "Genel Kurum Analizi";
    String fileNameSuffix = "Kurumsal";

    if (_selectedScope == 'branch') {
      subTitle = "${_selectedBranch ?? 'Tüm Şubeler'} Şube Analizi";
      fileNameSuffix = "Sube_${_selectedBranch ?? 'Genel'}";
    } else if (_selectedScope == 'student') {
      final studentName = widget.userNames[_selectedStudent] ?? 'Öğrenci';
      subTitle = "$studentName - Bireysel Analiz";
      fileNameSuffix = "Ogrenci_${studentName.replaceAll(' ', '_')}";
    }

    final adviceString = _generateAdviceString(averages);

    final pdfBytes = await pdfService.generateAcademicSelfConceptPdf(
      title: widget.survey.title,
      subTitle: subTitle,
      averages: averages,
      subscaleNames: _subscaleNames,
      respondentCount: filtered.length,
      advice: adviceString,
    );

    await FileSaver.instance.saveFile(
      name: '${widget.survey.title}_$fileNameSuffix',
      bytes: pdfBytes,
      ext: 'pdf',
      mimeType: MimeType.pdf,
    );
  }

  Future<void> _exportTableToExcel() async {
    final filtered = _getFilteredResponses();
    var excel = Excel.createExcel();
    Sheet sheet = excel['Sonuç Tablosu'];

    // Header
    List<CellValue> headers = [TextCellValue('Öğrenci Adı')];
    for (var name in _subscaleNames.values) {
      headers.add(TextCellValue(name));
    }
    sheet.appendRow(headers);

    // Data
    for (var r in filtered) {
      final stats = _calculateStudentStats(r);
      List<CellValue> row = [
        TextCellValue(widget.userNames[r['userId']] ?? 'Bilinmeyen'),
      ];
      for (var s in _subscaleNames.keys) {
        row.add(IntCellValue(stats[s]?.toInt() ?? 0));
      }
      sheet.appendRow(row);
    }

    final bytes = Uint8List.fromList(excel.encode()!);
    await FileSaver.instance.saveFile(
      name: '${widget.survey.title}_Sonuc_Tablosu',
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
