import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../models/activity/activity_model.dart';

class ActivityStatisticsScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const ActivityStatisticsScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<ActivityStatisticsScreen> createState() =>
      _ActivityStatisticsScreenState();
}

class _ActivityStatisticsScreenState extends State<ActivityStatisticsScreen> {
  bool _isLoading = true;

  // Data
  List<ActivityObservation> _allActivities = [];
  Map<String, int> _studentActivityCounts = {}; // studentId -> count
  Map<String, int> _studentObservationCounts = {}; // studentId -> count
  List<Map<String, dynamic>> _students = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // 1. Fetch all activities/observations
      final snapshot = await FirebaseFirestore.instance
          .collection('activities')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .get();

      _allActivities = snapshot.docs
          .map((d) => ActivityObservation.fromMap(d.data(), d.id))
          .toList();

      // 2. Fetch all students
      final studentSnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true)
          .orderBy('name')
          .get();

      _students = studentSnapshot.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return data;
      }).toList();

      // 3. Process Counts
      // Iterate strictly over students to find 0 interactions
      for (var student in _students) {
        final sid = student['id'];
        _studentActivityCounts[sid] = 0;
        _studentObservationCounts[sid] = 0;
      }

      for (var act in _allActivities) {
        for (var sid in act.targetStudentIds) {
          if (_studentActivityCounts.containsKey(sid)) {
            if (act.type == 'activity') {
              _studentActivityCounts[sid] =
                  (_studentActivityCounts[sid] ?? 0) + 1;
            } else {
              _studentObservationCounts[sid] =
                  (_studentObservationCounts[sid] ?? 0) + 1;
            }
          }
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // Metrics
    final zeroObservationStudents = _students
        .where((s) => (_studentObservationCounts[s['id']] ?? 0) == 0)
        .toList();
    final zeroActivityStudents = _students
        .where((s) => (_studentActivityCounts[s['id']] ?? 0) == 0)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('İstatistikler'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryCards(),
            const SizedBox(height: 24),
            _buildZeroInteractionSection(
              'Hiç Gözlem Yapılmayan Öğrenciler',
              zeroObservationStudents,
              Colors.orange,
            ),
            const SizedBox(height: 24),
            _buildZeroInteractionSection(
              'Hiç Etkinliğe Katılmayan Öğrenciler',
              zeroActivityStudents,
              Colors.blue,
            ),
            const SizedBox(height: 24),
            const Text(
              'Aktivite Dağılımı (Son 10)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, meta) {
                          if (val.toInt() >= 0 &&
                              val.toInt() < _allActivities.take(10).length) {
                            return Text(
                              _allActivities[val.toInt()].type == 'activity'
                                  ? 'E'
                                  : 'G',
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                      ),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: _allActivities
                      .take(10)
                      .toList()
                      .asMap()
                      .entries
                      .map((e) {
                        return BarChartGroupData(
                          x: e.key,
                          barRods: [
                            BarChartRodData(
                              toY: e.value.targetStudentIds.length.toDouble(),
                              color: e.value.type == 'activity'
                                  ? Colors.blue
                                  : Colors.orange,
                              width: 16,
                            ),
                          ],
                        );
                      })
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            'Toplam Gözlem',
            '${_allActivities.where((a) => a.type == 'observation').length}',
            Icons.visibility,
            Colors.orange,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildMetricCard(
            'Toplam Etkinlik',
            '${_allActivities.where((a) => a.type == 'activity').length}',
            Icons.event,
            Colors.blue,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Text(title, style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildZeroInteractionSection(
    String title,
    List<Map<String, dynamic>> students,
    Color color,
  ) {
    if (students.isEmpty) return Container();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 150,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: students.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final s = students[index];
              return ListTile(
                dense: true,
                title: Text(s['fullName'] ?? s['name']),
                subtitle: Text('${s['className']} - ${s['studentNumber']}'),
                leading: Icon(Icons.warning, color: color, size: 20),
                trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    // Navigate to create new activity/observation for this student specifically?
                    // For now, just show snackbar
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Bu öğrenci için yeni kayıt oluşturun'),
                      ),
                    );
                  },
                  child: const Text('İlgilen'),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
