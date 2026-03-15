import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';

class GuidanceStatisticsScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const GuidanceStatisticsScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<GuidanceStatisticsScreen> createState() =>
      _GuidanceStatisticsScreenState();
}

class _GuidanceStatisticsScreenState extends State<GuidanceStatisticsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _interviews = [];
  List<Map<String, dynamic>> _allStudents = [];

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    try {
      // 1. Fetch Interviews
      final interviewSnapshot = await FirebaseFirestore.instance
          .collection('guidance_interviews')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          //.orderBy('date', descending: true) // Index adjustment might be needed if complex filter
          .get();

      // 2. Fetch All Students ( Active )
      final studentSnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true)
          .get();

      if (mounted) {
        setState(() {
          _interviews = interviewSnapshot.docs.map((d) => d.data()).toList();
          _allStudents = studentSnapshot.docs
              .map(
                (d) => {
                  'id': d.id,
                  'name':
                      d.data()['fullName'] ??
                      '${d.data()['name']} ${d.data()['surname']}',
                  'class': d.data()['className'] ?? '-',
                },
              )
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Stats Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Rehberlik İstatistikleri',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.white,
          iconTheme: IconThemeData(color: Colors.black),
          elevation: 0,
          bottom: TabBar(
            labelColor: Colors.indigo,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.indigo,
            tabs: [
              Tab(text: "Genel"),
              Tab(text: "Öğretmen"),
            ],
          ),
        ),
        body: _isLoading
            ? Center(child: CircularProgressIndicator())
            : TabBarView(children: [_buildGeneralTab(), _buildTeacherTab()]),
      ),
    );
  }

  Widget _buildGeneralTab() {
    // 1. Monthly Counts (Last 6 Months)
    final now = DateTime.now();
    Map<int, int> monthlyCounts = {};
    for (int i = 0; i < 6; i++) {
      monthlyCounts[now.month - i <= 0 ? now.month - i + 12 : now.month - i] =
          0;
    }

    // 2. Student Counts & Topic Counts
    Map<String, int> studentCounts = {};
    Map<String, int> topicCounts = {};
    Set<String> interviewedStudentIds = {};

    for (var i in _interviews) {
      // Monthly
      final date = (i['date'] as Timestamp?)?.toDate();
      if (date != null && monthlyCounts.containsKey(date.month)) {
        monthlyCounts[date.month] = (monthlyCounts[date.month] ?? 0) + 1;
      }

      // Student Frequency
      if (i['participantDetails'] != null) {
        final details = i['participantDetails'] as List<dynamic>;
        for (var d in details) {
          String? type = d['type'];
          // If student or parent(linked to student), count student
          if (type == 'ogrenci' || type == 'veli') {
            String sId = d['studentId'] ?? d['id'];
            String sName = d['name'] ?? 'Bilinmeyen'; // Fallback name

            // Try to match with actual student list to get clean name if possible
            // But keeping simple map usage for now
            studentCounts[sName] = (studentCounts[sName] ?? 0) + 1;
            interviewedStudentIds.add(sId);
          }
        }
      } else {
        // Legacy fallback
        final names = List<String>.from(i['participantNames'] ?? []);
        for (var name in names) {
          studentCounts[name] = (studentCounts[name] ?? 0) + 1;
        }
      }

      // Topic Frequency
      final topic = i['title'] ?? 'Diğer';
      topicCounts[topic] = (topicCounts[topic] ?? 0) + 1;
    }

    // Sort Students
    final sortedStudents = studentCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final mostInterviewed = sortedStudents.take(10).toList();

    // Find Not Interviewed
    final notInterviewedStudents = _allStudents
        .where((s) => !interviewedStudentIds.contains(s['id']))
        .toList();

    // Sort Topics
    final sortedTopics = topicCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalInterviews = _interviews.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 900;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Aylık Grafik
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Aylık Görüşme Grafiği',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 24),
                      SizedBox(
                        height: 300,
                        child: BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            maxY:
                                (monthlyCounts.values.fold<int>(
                                          0,
                                          (a, b) => a > b ? a : b,
                                        ) +
                                        5)
                                    .toDouble(),
                            barTouchData: BarTouchData(
                              enabled: true,
                              touchTooltipData: BarTouchTooltipData(
                                getTooltipColor: (_) => Colors.blueGrey,
                                getTooltipItem:
                                    (group, groupIndex, rod, rodIndex) {
                                      return BarTooltipItem(
                                        rod.toY.round().toString(),
                                        const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      );
                                    },
                              ),
                            ),
                            titlesData: FlTitlesData(
                              show: true,
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (val, meta) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        DateFormat(
                                          'MMM',
                                          'tr_TR',
                                        ).format(DateTime(2024, val.toInt())),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              topTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            gridData: FlGridData(show: false),
                            barGroups: monthlyCounts.entries.map((e) {
                              return BarChartGroupData(
                                x: e.key,
                                barRods: [
                                  BarChartRodData(
                                    toY: e.value.toDouble(),
                                    color: Colors.indigo,
                                    width: 20,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: 24),

              // Konu Dağılımı ve Hiç Görüşülmeyenler Row/Column
              SizedBox(height: 24),

              // En Çok Görüşülenler ve Konu Dağılımı (SWAPPED)
              isMobile
                  ? Column(
                      children: [
                        SizedBox(
                          height: 400,
                          child: _buildListCard(
                            'En Çok Görüşülen Öğrenciler',
                            mostInterviewed,
                            Colors.green,
                            Icons.trending_up,
                            onExport: () => _exportToExcel(
                              'En_Cok_Gorusulenler',
                              ['Öğrenci Adı', 'Görüşme Sayısı'],
                              mostInterviewed
                                  .map((e) => [e.key, e.value])
                                  .toList(),
                            ),
                          ),
                        ),
                        SizedBox(height: 24),
                        SizedBox(
                          height: 400,
                          child: _buildNotInterviewedCard(
                            notInterviewedStudents,
                            onExport: () => _exportToExcel(
                              'Hic_Gorusulmeyenler',
                              ['Öğrenci Adı', 'Sınıf'],
                              notInterviewedStudents
                                  .map((e) => [e['name'], e['class']])
                                  .toList(),
                            ),
                          ),
                        ),
                        SizedBox(height: 24),
                        _buildTopicDistributionCard(
                          sortedTopics,
                          totalInterviews,
                          onExport: () => _exportToExcel(
                            'Konu_Dagilimi',
                            ['Konu', 'Sayı'],
                            sortedTopics.map((e) => [e.key, e.value]).toList(),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 400,
                                child: _buildListCard(
                                  'En Çok Görüşülen Öğrenciler',
                                  mostInterviewed,
                                  Colors.green,
                                  Icons.trending_up,
                                  onExport: () => _exportToExcel(
                                    'En_Cok_Gorusulenler',
                                    ['Öğrenci Adı', 'Görüşme Sayısı'],
                                    mostInterviewed
                                        .map((e) => [e.key, e.value])
                                        .toList(),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 24),
                            Expanded(
                              child: SizedBox(
                                height: 400,
                                child: _buildNotInterviewedCard(
                                  notInterviewedStudents,
                                  onExport: () => _exportToExcel(
                                    'Hic_Gorusulmeyenler',
                                    ['Öğrenci Adı', 'Sınıf'],
                                    notInterviewedStudents
                                        .map((e) => [e['name'], e['class']])
                                        .toList(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 24),
                        _buildTopicDistributionCard(
                          sortedTopics,
                          totalInterviews,
                          onExport: () => _exportToExcel(
                            'Konu_Dagilimi',
                            ['Konu', 'Sayı'],
                            sortedTopics.map((e) => [e.key, e.value]).toList(),
                          ),
                        ),
                      ],
                    ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTeacherTab() {
    // Count per teacher
    Map<String, int> teacherCounts = {};
    for (var i in _interviews) {
      // Use stored interviewerName instead of email if feasible
      String name =
          i['interviewerName'] ?? i['interviewerEmail'] ?? 'Bilinmiyor';
      teacherCounts[name] = (teacherCounts[name] ?? 0) + 1;
    }

    final sortedTeachers = teacherCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView.builder(
      padding: EdgeInsets.all(24),
      itemCount: sortedTeachers.length,
      itemBuilder: (context, index) {
        final entry = sortedTeachers[index];
        return Card(
          margin: EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: Colors.orange.shade100,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              entry.key,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            trailing: Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Text(
                '${entry.value} Görüşme',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade900,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopicDistributionCard(
    List<MapEntry<String, int>> topics,
    int total, {
    VoidCallback? onExport,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Görüşme Konu Dağılımı',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (onExport != null)
                  IconButton(
                    onPressed: onExport,
                    icon: Icon(Icons.download, color: Colors.blueGrey),
                    tooltip: 'Excel İndir',
                  ),
              ],
            ),
            SizedBox(height: 16),
            ...topics.map((e) {
              final percent = total > 0
                  ? (e.value / total * 100).toStringAsFixed(1)
                  : '0';
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          e.key,
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          '%$percent (${e.value})',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: total > 0 ? e.value / total : 0,
                      backgroundColor: Colors.grey.shade100,
                      color: Colors.blue.shade400,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildNotInterviewedCard(
    List<Map<String, dynamic>> students, {
    VoidCallback? onExport,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(
              16.0,
            ), // Reduced header padding slightly
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red),
                    SizedBox(width: 8),
                    Text(
                      'Hiç Görüşülmeyenler (${students.length})',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ), // Adjusted font
                    ),
                  ],
                ),
                if (onExport != null)
                  IconButton(
                    onPressed: onExport,
                    icon: Icon(Icons.download, color: Colors.blueGrey),
                    tooltip: 'Excel İndir',
                  ),
              ],
            ),
          ),
          Divider(height: 1),
          Divider(height: 1),
          Expanded(
            child: students.isEmpty
                ? Center(
                    child: Text(
                      "Tüm öğrencilerle görüşülmüş! 🎉",
                      style: TextStyle(color: Colors.green),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.all(12),
                    itemCount: students.length,
                    separatorBuilder: (_, __) => Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final s = students[i];
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.red.shade50,
                          child: Icon(
                            Icons.person_off,
                            size: 14,
                            color: Colors.red,
                          ),
                        ),
                        title: Text(
                          s['name'],
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          s['class'],
                          style: TextStyle(fontSize: 12),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildListCard(
    String title,
    List<MapEntry<String, int>> data,
    Color color,
    IconData icon, {
    VoidCallback? onExport,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12), // Reduced padding
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color),
                    SizedBox(width: 8),
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                if (onExport != null)
                  IconButton(
                    onPressed: onExport,
                    icon: Icon(Icons.download, color: color),
                    tooltip: 'Excel İndir',
                  ),
              ],
            ),
          ),
          Expanded(
            child: data.isEmpty
                ? Center(
                    child: Text(
                      "Veri yok",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.all(12),
                    itemCount: data.length,
                    separatorBuilder: (ctx, i) => Divider(height: 1),
                    itemBuilder: (ctx, i) => ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor: color.withOpacity(0.2),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        radius: 14,
                      ),
                      title: Text(
                        data[i].key,
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      trailing: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${data[i].value}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportToExcel(
    String fileName,
    List<String> headers,
    List<List<dynamic>> rows,
  ) async {
    try {
      var excel = Excel.createExcel();
      Sheet sheetObject = excel['Sheet1'];

      // Add Headers
      sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

      // Add Data
      for (var row in rows) {
        sheetObject.appendRow(
          row.map((e) => TextCellValue(e.toString())).toList(),
        );
      }

      var fileBytes = excel.save();
      if (fileBytes != null) {
        await FileSaver.instance.saveFile(
          name: fileName,
          bytes: Uint8List.fromList(fileBytes),
          ext: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rapor indirildi: $fileName.xlsx')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Rapor oluşturulurken hata: $e')));
    }
  }
}
