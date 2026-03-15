import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/survey_model.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../../services/pdf_service.dart';

class BurdonAttentionReport extends StatefulWidget {
  final Survey survey;
  final List<Map<String, dynamic>> responses;
  final Map<String, String> userNames;

  const BurdonAttentionReport({
    Key? key,
    required this.survey,
    required this.responses,
    required this.userNames,
  }) : super(key: key);

  @override
  State<BurdonAttentionReport> createState() => _BurdonAttentionReportState();
}

class _BurdonAttentionReportState extends State<BurdonAttentionReport>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedScope = 'institution'; // institution, branch, student
  String? _selectedBranch;
  String? _selectedStudent;

  List<Map<String, dynamic>> _branches = [];
  Map<String, dynamic> _userDetails = {};
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
          .where('role', isEqualTo: 'Öğrenci')
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

  List<Map<String, dynamic>> get _filteredResponses {
    if (_selectedScope == 'institution') return widget.responses;
    if (_selectedScope == 'branch') {
      return widget.responses.where((r) {
        final uid = r['userId'];
        return _userDetails[uid]?['branch'] == _selectedBranch;
      }).toList();
    }
    if (_selectedScope == 'student') {
      return widget.responses
          .where((r) => r['userId'] == _selectedStudent)
          .toList();
    }
    return widget.responses;
  }

  Map<String, dynamic> _calculateMetrics(List<Map<String, dynamic>> responses) {
    if (responses.isEmpty) return {};
    int totalCorrect = 0;
    int totalMissed = 0;
    int totalWrong = 0;
    int responseCount = responses.length;

    int maxRows = 0;
    for (var r in responses) {
      final answers = r['answers'] as Map<String, dynamic>?;
      final grid = _getRows(answers, 'grid', 'grid_flat');
      if (grid.isNotEmpty && grid.length > maxRows) maxRows = grid.length;
    }
    if (maxRows == 0) maxRows = 20; // fallback

    List<double> linePerformances = List.filled(maxRows, 0.0);

    for (var r in responses) {
      final answers = r['answers'] as Map<String, dynamic>?;
      if (answers == null) continue;

      final grid = _getRows(answers, 'grid', 'grid_flat');
      final selections = _getRows(answers, 'selections', 'selections_flat');

      for (int i = 0; i < grid.length; i++) {
        final rowChars = grid[i];
        final rowSel = selections[i];
        int rowCorrect = 0;
        int rowTargetCount = 0;

        for (int j = 0; j < rowChars.length; j++) {
          final char = rowChars[j].toString();
          final isSelected = rowSel[j] as bool;
          final isTarget = ['a', 'b', 'd', 'g'].contains(char);

          if (isTarget) {
            rowTargetCount++;
            if (isSelected) {
              totalCorrect++;
              rowCorrect++;
            } else {
              totalMissed++;
            }
          } else if (isSelected) {
            totalWrong++;
          }
        }

        // Performance per line: (Correct / Targets)
        if (rowTargetCount > 0) {
          linePerformances[i] += (rowCorrect / rowTargetCount);
        } else {
          linePerformances[i] += 1.0; // Perfect if no targets to miss
        }
      }
    }

    double avgCorrect = totalCorrect / responseCount;
    double avgMissed = totalMissed / responseCount;
    double avgWrong = totalWrong / responseCount;

    // Attention Index (0.0 - 1.0)
    double attentionIndex = 0.0;
    if (avgCorrect + avgMissed + avgWrong > 0) {
      attentionIndex = avgCorrect / (avgCorrect + avgMissed + avgWrong);
    }

    return {
      'avgCorrect': avgCorrect,
      'avgMissed': avgMissed,
      'avgWrong': avgWrong,
      'attentionIndex': attentionIndex,
      'linePerformances': linePerformances
          .map((p) => p / responseCount)
          .toList(),
      'responseCount': responseCount,
    };
  }

  // Helper to extract rows
  List<List<dynamic>> _getRows(
    Map<String, dynamic>? answers,
    String key,
    String flatKey,
  ) {
    if (answers == null) return [];
    if (answers[key] != null) {
      return (answers[key] as List).map((e) => e as List).toList();
    }
    if (answers[flatKey] != null) {
      final flatList = answers[flatKey] as List<dynamic>;
      final charsPerRow = answers['charsPerRow'] as int? ?? 40;
      List<List<dynamic>> rows = [];
      for (int i = 0; i < flatList.length; i += charsPerRow) {
        int end = i + charsPerRow;
        if (end > flatList.length) end = flatList.length;
        rows.add(flatList.sublist(i, end));
      }
      return rows;
    }
    return [];
  }

  Map<String, String> _getInterpretation(double idx) {
    String title;
    String text;
    if (idx > 0.85) {
      title = 'Çok Yüksek Dikkat ve Üstün Konsantrasyon';
      text =
          'Öğrenci/Grup genelinde dikkat sürekliliği en üst düzeydedir. Otomatikleşme becerisi gelişmiş, odaklanma süresi uzundur. '
          'Hata payı minimumda olup, kompleks görevlerde yüksek performans sergileme kapasitesi bulunmaktadır. '
          'Öneri: Zihinsel zorlayıcılığı daha yüksek, çok aşamalı projeler ve yaratıcı problem çözme aktiviteleri ile bu potansiyel desteklenmelidir.';
    } else if (idx > 0.7) {
      title = 'Yüksek Dikkat ve Kararlı Odaklanma';
      text =
          'Dikkat performansı oldukça sağlıklı ve sürdürülebilirdir. Görev boyunca motivasyonunu koruyabilmekte ve uyaranlar arasında geçiş yaparken verimliliğini sürdürmektedir. '
          'Genel ders başarısı ve akademik görevlerde dikkat kaynaklı hata yapma olasılığı düşüktür. '
          'Öneri: Rutin çalışmaların yanına analiz ve sentez gerektiren derinlemesine çalışma seansları eklenerek akademik gelişim hızlandırılabilir.';
    } else if (idx > 0.5) {
      title = 'Orta Düzey Dikkat ve Dalgalı Konsantrasyon';
      text =
          'Dikkat performansı genel olarak yeterli olmakla birlikte zaman zaman dalgalanmalar görülmektedir. Çalışmanın ilk aşamalarında yüksek olan odaklanma, süre uzadığında veya '
          'monotonluk arttığında düşüş gösterebilir. Basit işlem hataları veya atlamalar gözlemlenebilir. '
          'Öneri: Çalışma seansları 25-30 dakikalık bölümlere (Pomodoro gibi) ayrılmalı, aralarda kısa zihinsel molalar verilmelidir. Çalışma ortamı dikkat dağıtıcılardan arındırılmalıdır.';
    } else if (idx > 0.3) {
      title = 'Dikkat Eksikliği ve Odaklanma Güçlüğü';
      text =
          'Bireyin/Grubun dikkat sürekliliğinde belirgin aksamalar tespit edilmiştir. Detayları gözden kaçırma, yönergeleri tamamlama zorluğu ve çabuk sıkılma gibi belirtiler görülebilir. '
          'Öğrenme sürecinde bilgiyi işleme hızı dikkat dağınıklığı nedeniyle yavaşlamış olabilir. '
          'Öneri: Görsel ve işitsel odaklanma egzersizleri yapılmalı, görevler küçük ve başarılabilecek parçalara bölünmelidir. Sık sık geri bildirim verilerek motivasyon canlı tutulmalıdır.';
    } else {
      title = 'Düşük Dikkat Sürekliliği ve Belirgin Hata Eğilimi';
      text =
          'Dikkat yoğunluğu kritik düzeyin altındadır. Görev sırasında çok sık mola verme ihtiyacı, yoğun atlama ve yanlış işaretleme eğilimi mevcuttur. '
          'Uzun süreli akademik aktivitelerde ciddi verim kaybı yaşanıyor olabilir. '
          'Öneri: Bir uzmandan (rehberlik servisi veya ilgili branş hekimi) destek alınması, dikkat geliştirici özel eğitim programlarının (Play Attention, Neurofeedback vb.) değerlendirilmesi önerilir. '
          'Gerektiğinde sınav ve çalışma koşullarında süre veya mola düzenlemesi yapılmalıdır.';
    }
    return {'title': title, 'text': text};
  }

  Future<void> _exportToExcel() async {
    try {
      final filtered = _filteredResponses;
      final metrics = _calculateMetrics(filtered);
      var excel = Excel.createExcel();

      // Summary Sheet
      Sheet summarySheet = excel['Özet Analiz'];
      summarySheet.appendRow([TextCellValue('Metrik'), TextCellValue('Değer')]);
      summarySheet.appendRow([
        TextCellValue('Toplam Katılımcı'),
        IntCellValue(metrics['responseCount'] as int),
      ]);
      summarySheet.appendRow([
        TextCellValue('Ortalama Doğru'),
        DoubleCellValue(metrics['avgCorrect'] as double),
      ]);
      summarySheet.appendRow([
        TextCellValue('Ortalama Atlanan'),
        DoubleCellValue(metrics['avgMissed'] as double),
      ]);
      summarySheet.appendRow([
        TextCellValue('Ortalama Hatalı'),
        DoubleCellValue(metrics['avgWrong'] as double),
      ]);
      summarySheet.appendRow([
        TextCellValue('Genel Dikkat İndeksi'),
        TextCellValue(
          '%${(metrics['attentionIndex'] * 100).toStringAsFixed(1)}',
        ),
      ]);

      // Satır Bazlı Performans
      Sheet lineSheet = excel['Satır Performansı'];
      lineSheet.appendRow([
        TextCellValue('Satır No'),
        TextCellValue('Performans (%)'),
      ]);
      final performances = metrics['linePerformances'] as List<double>;
      for (int i = 0; i < performances.length; i++) {
        lineSheet.appendRow([
          IntCellValue(i + 1),
          DoubleCellValue(performances[i] * 100),
        ]);
      }

      // Öğrenci Listesi
      Sheet studentSheet = excel['Öğrenci Listesi'];
      studentSheet.appendRow([
        TextCellValue('Öğrenci Adı'),
        TextCellValue('Doğru'),
        TextCellValue('Atlanan'),
        TextCellValue('Hatalı'),
        TextCellValue('Dikkat İndeksi (%)'),
      ]);

      for (var r in filtered) {
        final uid = r['userId'].toString();
        final m = _calculateMetrics([r]);
        studentSheet.appendRow([
          TextCellValue(widget.userNames[uid] ?? uid),
          IntCellValue(m['avgCorrect'].toInt()),
          IntCellValue(m['avgMissed'].toInt()),
          IntCellValue(m['avgWrong'].toInt()),
          DoubleCellValue(m['attentionIndex'] * 100),
        ]);
      }

      excel.delete('Sheet1');
      excel.delete('Sayfa1');

      final fileBytes = excel.save();
      if (fileBytes != null) {
        await FileSaver.instance.saveFile(
          name: 'burdon_test_raporu_${DateTime.now().millisecondsSinceEpoch}',
          bytes: Uint8List.fromList(fileBytes),
          ext: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Excel başarıyla indirildi.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Dışa aktarma hatası: $e')));
      }
    }
  }

  Future<void> _exportToPdf() async {
    try {
      final filtered = _filteredResponses;
      if (filtered.isEmpty) return;

      final metrics = _calculateMetrics(filtered);
      final interpretation = _getInterpretation(
        metrics['attentionIndex'] as double,
      );

      String scopeType = 'Kurum';
      String scopeName = 'Genel';

      List<List<dynamic>>? grid;
      List<List<dynamic>>? selections;

      if (_selectedScope == 'branch') {
        scopeType = 'Şube';
        scopeName = _branches.firstWhere(
          (b) => b['id'] == _selectedBranch,
          orElse: () => {'name': 'Seçili Şube'},
        )['name'];
      } else if (_selectedScope == 'student') {
        scopeType = 'Öğrenci';
        scopeName = widget.userNames[_selectedStudent] ?? 'Seçili Öğrenci';

        final r = filtered.first;
        final answers = r['answers'] as Map<String, dynamic>?;
        grid = _getRows(answers, 'grid', 'grid_flat');
        selections = _getRows(answers, 'selections', 'selections_flat');
      }

      final pdfBytes = await PdfService().generateBurdonReportPdf(
        title: widget.survey.title,
        scopeType: scopeType,
        scopeName: scopeName,
        metrics: metrics,
        interpretationTitle: interpretation['title']!,
        interpretationText: interpretation['text']!,
        grid: _selectedScope == 'student' ? grid : null,
        selections: _selectedScope == 'student' ? selections : null,
      );

      final safeScopeName = scopeName
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .replaceAll(' ', '_');
      await FileSaver.instance.saveFile(
        name: 'burdon_${safeScopeName}',
        bytes: pdfBytes,
        ext: 'pdf',
        mimeType: MimeType.pdf,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF başarıyla indirildi.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('PDF dışa aktarma hatası: $e')));
      }
    }
  }

  void _showStudentDetail(Map<String, dynamic> response) {
    final uid = response['userId'].toString();
    final name = widget.userNames[uid] ?? uid;
    final metrics = _calculateMetrics([response]);
    final answers = response['answers'] as Map<String, dynamic>?;
    final grid = _getRows(answers, 'grid', 'grid_flat');
    final selections = _getRows(answers, 'selections', 'selections_flat');

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: 800,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'Öğrenci Test Detayı',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(height: 32),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildMetricCards(metrics),
                      const SizedBox(height: 24),
                      _buildInterpretationCard(metrics),
                      const SizedBox(height: 24),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Test Matrisi',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildReconstructedGrid(grid, selections),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReconstructedGrid(
    List<List<dynamic>> grid,
    List<List<dynamic>> selections,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: List.generate(grid.length, (rowIndex) {
          final rowChars = grid[rowIndex];
          final rowSels = selections[rowIndex];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(rowChars.length, (colIndex) {
                final char = rowChars[colIndex].toString();
                final isSelected = rowSels[colIndex] as bool;
                final isTarget = ['a', 'b', 'd', 'g'].contains(char);

                Color textColor = Colors.black87;
                BoxDecoration? decoration;

                if (isSelected && isTarget) {
                  // Correct
                  textColor = Colors.green;
                  decoration = BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  );
                } else if (isSelected && !isTarget) {
                  // Wrong choice
                  textColor = Colors.red;
                  decoration = BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  );
                } else if (!isSelected && isTarget) {
                  // Missed
                  textColor = Colors.orange.shade800;
                  decoration = BoxDecoration(
                    border: Border.all(color: Colors.orange.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(4),
                  );
                }

                return Container(
                  width: 16,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: decoration,
                  child: Text(
                    char,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 12,
                      fontFamily: 'Courier', // Monospaced for grid
                      fontWeight: isTarget
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                );
              }),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredResponses;
    final metrics = _calculateMetrics(filtered);

    return Column(
      children: [
        if (_isLoadingFilters) const LinearProgressIndicator(minHeight: 2),
        _buildFilters(),
        Container(
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  labelColor: Colors.indigo,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Colors.indigo,
                  tabs: const [
                    Tab(text: 'Genel Analiz'),
                    Tab(text: 'Öğrenci Listesi'),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: TextButton.icon(
                  onPressed: _exportToExcel,
                  icon: const Icon(Icons.table_chart_rounded, size: 18),
                  label: const Text('Excel'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: TextButton.icon(
                  onPressed: _exportToPdf,
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                  label: const Text('PDF'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSummaryTab(metrics),
              _buildStudentListTab(filtered),
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
          SegmentedButton<String>(
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: const Color(0xFFEBE3FF),
              selectedForegroundColor: Colors.indigo,
            ),
            segments: const [
              ButtonSegment(
                value: 'institution',
                label: Text('Kurum'),
                icon: Icon(Icons.school, size: 16),
              ),
              ButtonSegment(
                value: 'branch',
                label: Text('Şube'),
                icon: Icon(Icons.class_, size: 16),
              ),
              ButtonSegment(
                value: 'student',
                label: Text('Öğrenci'),
                icon: Icon(Icons.person, size: 16),
              ),
            ],
            selected: {_selectedScope},
            onSelectionChanged: (val) {
              setState(() {
                _selectedScope = val.first;
                _selectedBranch = null;
                _selectedStudent = null;
                if (_selectedScope == 'student')
                  _tabController.index = 1;
                else
                  _tabController.index = 0;
              });
            },
          ),
          if (_selectedScope != 'institution') ...[
            const SizedBox(height: 12),
            if (_selectedScope == 'branch')
              _buildDropdown(
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
              _buildDropdown(
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

  Widget _buildDropdown({
    required String label,
    required dynamic value,
    required List<DropdownMenuItem<dynamic>> items,
    required ValueChanged<dynamic> onChanged,
  }) {
    return DropdownButtonFormField(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _buildSummaryTab(Map<String, dynamic> metrics) {
    if (metrics.isEmpty) return const Center(child: Text('Veri bulunamadı.'));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildMetricCards(metrics),
          const SizedBox(height: 24),
          _buildPerformanceChart(metrics['linePerformances']),
          const SizedBox(height: 24),
          _buildInterpretationCard(metrics),
        ],
      ),
    );
  }

  Widget _buildMetricCards(Map<String, dynamic> metrics) {
    return Row(
      children: [
        _buildMetricItem(
          'Doğru',
          metrics['avgCorrect'].toStringAsFixed(1),
          Colors.green,
        ),
        const SizedBox(width: 12),
        _buildMetricItem(
          'Atlanan',
          metrics['avgMissed'].toStringAsFixed(1),
          Colors.orange,
        ),
        const SizedBox(width: 12),
        _buildMetricItem(
          'Hatalı',
          metrics['avgWrong'].toStringAsFixed(1),
          Colors.red,
        ),
      ],
    );
  }

  Widget _buildMetricItem(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: color, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceChart(List<double> performances) {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dikkat Sürekliliği (Satır Bazlı)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 1.1,
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (spot) => Colors.indigo.withOpacity(0.9),
                    getTooltipItems: (List<LineBarSpot> touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          '${spot.y.toStringAsFixed(2)}',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) =>
                      FlLine(color: Colors.grey.shade100, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: 0.2,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toStringAsFixed(1),
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 10,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 10,
                      getTitlesWidget: (value, meta) {
                        if (value == 1 ||
                            value == 10 ||
                            value == 20 ||
                            value == performances.length) {
                          return Text(
                            value.toInt().toString(),
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 10,
                            ),
                          );
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(
                      performances.length,
                      (i) => FlSpot(i.toDouble() + 1, performances[i]),
                    ),
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: Colors.indigo,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.indigo.withOpacity(0.05),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInterpretationCard(Map<String, dynamic> metrics) {
    final idx = metrics['attentionIndex'] as double;
    final interpretation = _getInterpretation(idx);
    final title = interpretation['title']!;
    final text = interpretation['text']!;
    Color color;

    if (idx > 0.85) {
      color = Colors.green.shade700;
    } else if (idx > 0.7) {
      color = Colors.green;
    } else if (idx > 0.5) {
      color = Colors.blue;
    } else if (idx > 0.3) {
      color = Colors.orange;
    } else {
      color = Colors.red;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        border: Border.all(color: color.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentListTab(List<Map<String, dynamic>> responses) {
    return ListView.builder(
      itemCount: responses.length,
      itemBuilder: (context, index) {
        final r = responses[index];
        final uid = r['userId'].toString();
        final m = _calculateMetrics([r]);

        return ListTile(
          onTap: () => _showStudentDetail(r),
          hoverColor: Colors.indigo.withOpacity(0.05),
          leading: CircleAvatar(
            backgroundColor: Colors.indigo.shade50,
            child: Text(
              (index + 1).toString(),
              style: const TextStyle(color: Colors.indigo, fontSize: 12),
            ),
          ),
          title: Text(
            widget.userNames[uid] ?? uid,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            'Doğru: ${m['avgCorrect'].toInt()} | Hata: ${m['avgWrong'].toInt()}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.indigo.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '%${(m['attentionIndex'] * 100).toInt()}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
                fontSize: 13,
              ),
            ),
          ),
        );
      },
    );
  }
}
