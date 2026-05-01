import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../models/assessment/assessment_action_plan_model.dart';

class AssessmentActionPlanStatsScreen extends StatefulWidget {
  final List<AssessmentActionPlan> plans;
  final String schoolTypeId;

  const AssessmentActionPlanStatsScreen({
    Key? key, 
    required this.plans,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  _AssessmentActionPlanStatsScreenState createState() => _AssessmentActionPlanStatsScreenState();
}

class _AssessmentActionPlanStatsScreenState extends State<AssessmentActionPlanStatsScreen> {
  String _selectedClassFilter = 'Tümü';

  String _getResolvedLevel(AssessmentActionPlan plan) {
    String level = plan.classLevel;
    if (level == 'Tümü' || level.isEmpty || level == 'GENEL') {
      if (plan.branchActionPlans.isNotEmpty) {
        for (var branchKey in plan.branchActionPlans.keys) {
          final branchName = branchKey.split('_').first;
          final match = RegExp(r'^(\d+)').firstMatch(branchName);
          if (match != null) {
            String raw = match.group(1)!;
            if (raw.length == 3) return raw[0];
            if (raw.length == 4) return raw.substring(0, 2);
            return raw;
          }
        }
      }
      return 'GENEL';
    }
    return level;
  }

  List<String> _getAvailableLevels() {
    final Set<String> levels = widget.plans
        .map((p) => _getResolvedLevel(p))
        .where((l) => l != 'GENEL')
        .toSet();
    
    final sorted = levels.toList()..sort((a, b) {
      int ia = int.tryParse(a) ?? 0;
      int ib = int.tryParse(b) ?? 0;
      return ia.compareTo(ib);
    });
    
    return ['Tümü', ...sorted];
  }

  List<AssessmentActionPlan> get _filteredPlans {
    if (_selectedClassFilter == 'Tümü') return widget.plans;
    return widget.plans.where((p) => _getResolvedLevel(p) == _selectedClassFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final plans = _filteredPlans;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: const Text('Eylem Planı Analitiği', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: plans.isEmpty 
                ? _buildEmptyState()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummaryCards(plans),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Gelişim ve İzleme'),
                      _buildStatusPieChart(plans),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Problem Kaynağı Analizi'),
                      _buildProblemBarChart(plans),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Branş Bazlı Dağılım'),
                      _buildBranchDistribution(plans),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Sorumlu Performansı'),
                      _buildTeacherPerformance(plans),
                      const SizedBox(height: 100),
                    ],
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.indigo.shade900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    final levels = _getAvailableLevels();
    return Container(
      height: 60,
      width: double.infinity,
      color: Colors.indigo.shade900,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: levels.length,
        itemBuilder: (context, index) {
          final level = levels[index];
          final isSelected = _selectedClassFilter == level;
          final displayLabel = level == 'Tümü' ? 'Tüm Planlar' : '$level. Sınıf';

          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              onTap: () => setState(() => _selectedClassFilter = level),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  displayLabel,
                  style: TextStyle(
                    color: isSelected ? Colors.indigo.shade900 : Colors.white,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          children: [
            Icon(Icons.bar_chart, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('Bu filtreye uygun veri bulunamadı', style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards(List<AssessmentActionPlan> plans) {
    int total = plans.length;
    int completed = plans.where((p) => p.isRealized).length;
    int ongoing = total - completed;

    return Row(
      children: [
        _buildMiniStat('Toplam', total.toString(), Icons.assignment, Colors.blue),
        const SizedBox(width: 12),
        _buildMiniStat('Tamamlanan', completed.toString(), Icons.check_circle, Colors.green),
        const SizedBox(width: 12),
        _buildMiniStat('Uygulanan', ongoing.toString(), Icons.sync, Colors.orange),
      ],
    );
  }

  Widget _buildMiniStat(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPieChart(List<AssessmentActionPlan> plans) {
    int completed = plans.where((p) => p.isRealized).length;
    int ongoing = plans.length - completed;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
      ),
      child: Row(
        children: [
          SizedBox(
            height: 140,
            width: 140,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 30,
                sections: [
                  PieChartSectionData(
                    value: completed.toDouble(),
                    title: '%${((completed / (plans.isEmpty ? 1 : plans.length)) * 100).toStringAsFixed(0)}',
                    color: Colors.green,
                    radius: 40,
                    titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  PieChartSectionData(
                    value: ongoing.toDouble(),
                    title: '%${((ongoing / (plans.isEmpty ? 1 : plans.length)) * 100).toStringAsFixed(0)}',
                    color: Colors.orange,
                    radius: 40,
                    titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 32),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLegend('Tamamlanan', Colors.green, completed),
                const SizedBox(height: 16),
                _buildLegend('Uygulanıyor', Colors.orange, ongoing),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProblemBarChart(List<AssessmentActionPlan> plans) {
    Map<String, int> problemCounts = {};
    for (var plan in plans) {
      plan.branchActionPlans.forEach((branch, data) {
        String problem = data['problemSource'] ?? 'Belirlenmedi';
        if (problem != 'Belirlenmedi' && problem.isNotEmpty) {
          problemCounts[problem] = (problemCounts[problem] ?? 0) + 1;
        }
      });
    }

    var sortedProblems = problemCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    var displayProblems = sortedProblems.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: displayProblems.map((e) {
          double percent = e.value / (plans.isEmpty ? 1 : plans.length);
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(e.key, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text(e.value.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percent > 1.0 ? 1.0 : percent,
                    backgroundColor: Colors.grey.shade100,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo.shade400),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBranchDistribution(List<AssessmentActionPlan> plans) {
    Map<String, int> branchCounts = {};
    for (var plan in plans) {
      plan.branchActionPlans.keys.forEach((branch) {
        String label = branch.split('_').last;
        branchCounts[label] = (branchCounts[label] ?? 0) + 1;
      });
    }

    var sortedBranches = branchCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
      ),
      child: Column(
        children: sortedBranches.take(6).map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.book_outlined, size: 16, color: Colors.indigo.shade900),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(e.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
              Text('${e.value} Plan', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildTeacherPerformance(List<AssessmentActionPlan> plans) {
    Map<String, int> teacherCounts = {};
    for (var plan in plans) {
      String name = plan.creatorName;
      if (name == 'Kullanıcı') name = 'Sistem Yöneticisi';
      teacherCounts[name] = (teacherCounts[name] ?? 0) + 1;
    }

    var sortedTeachers = teacherCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
      ),
      child: Column(
        children: sortedTeachers.take(5).map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.indigo.shade900,
                    child: Text(e.key[0], style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(e.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                  Text(e.value.toString(), style: TextStyle(color: Colors.indigo.shade900, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: e.value / (plans.isEmpty ? 1 : plans.length),
                  backgroundColor: Colors.indigo.shade50,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo.shade900),
                  minHeight: 4,
                ),
              ),
            ],
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildLegend(String label, Color color, int count) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            Text('$count Adet', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ],
    );
  }
}
