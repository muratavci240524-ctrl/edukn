import 'package:flutter/material.dart';
import '../../../../models/assessment/assessment_action_plan_model.dart';
import '../../../../services/assessment_service.dart';
import '../../../../widgets/edukn_logo.dart';
import '../action_plan/assessment_action_plan_screen.dart';

class ReinforcementDashboardScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const ReinforcementDashboardScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  _ReinforcementDashboardScreenState createState() => _ReinforcementDashboardScreenState();
}

class _ReinforcementDashboardScreenState extends State<ReinforcementDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AssessmentService _service = AssessmentService();
  bool _isLoading = false;

  // Real data will be fetched here
  List<Map<String, dynamic>> _weakTopics = [];
  List<Map<String, dynamic>> _atRiskStudents = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRealData();
  }

  Future<void> _loadRealData() async {
    setState(() => _isLoading = true);
    try {
      // Fetch live analysis from the service
      final analysis = await _service.getPerformanceAnalysis(widget.institutionId, widget.schoolTypeId);
      
      setState(() {
        _weakTopics = analysis['weakTopics'] ?? [];
        _atRiskStudents = analysis['atRiskStudents'] ?? [];
        
        // If live data is empty (no recent plans/exams), provide a smart fallback 
        // that still feels active but invites action.
        if (_weakTopics.isEmpty) {
          _weakTopics = [
            {
              'branch': 'GENEL',
              'subject': 'Analiz Hazırlanıyor',
              'topic': 'Son deneme verileri işleniyor...',
              'successRate': 0.0,
              'studentCount': 0,
            }
          ];
        }
      });
    } catch (e) {
      print('Dashboard Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: const Text(
          'Haftalık Performans Özeti',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo.shade900,
        elevation: 0,
        centerTitle: true,
        leading: const BackButton(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.6),
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'Şube Performansı'),
            Tab(text: 'Bireysel Takip'),
          ],
        ),
      ),
      body: _isLoading 
        ? const Center(child: EduKnLoader(size: 60))
        : TabBarView(
            controller: _tabController,
            children: [_buildBranchTab(), _buildStudentTab()],
          ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToNewActionPlan(),
        label: const Text('Yeni Eylem Planı', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.add, color: Colors.white),
        backgroundColor: Colors.indigo.shade900,
      ),
    );
  }

  void _navigateToNewActionPlan() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AssessmentActionPlanScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
        ),
      ),
    );
  }

  Widget _buildBranchTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            title: 'Haftalık Analiz Raporu',
            description: 'Son deneme sınavı sonuçlarına göre %50 başarı barajının altında kalan kritik kazanımlar.',
            icon: Icons.analytics_rounded,
            color: Colors.indigo,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              const Text(
                'Acil Müdahale Gereken Konular',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1C1E)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._weakTopics.map((topic) => _buildWeakTopicCard(topic)).toList(),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildStudentTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            title: 'Bireysel Gelişim Takibi',
            description: 'Akademik daldalanma yaşayan veya kritik eşikteki öğrencilerin performans özeti.',
            icon: Icons.person_search_rounded,
            color: Colors.orange,
          ),
          const SizedBox(height: 24),
          ..._atRiskStudents.map((student) => _buildAtRiskStudentCard(student)).toList(),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildInfoCard({required String title, required String description, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.withOpacity(0.05), Colors.white]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
                const SizedBox(height: 4),
                Text(description, style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeakTopicCard(Map<String, dynamic> data) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                _buildClassBadge(data['branch']),
                const SizedBox(width: 12),
                Expanded(child: Text(data['subject'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                  child: Text('%${data['successRate']}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
            const Divider(height: 32),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('KRİTİK KAZANIM', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      const SizedBox(height: 4),
                      Text(data['topic'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo)),
                      const SizedBox(height: 8),
                      Text('Etkilenen Öğrenci: ${data['studentCount']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () => _navigateToNewActionPlan(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade900,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    elevation: 0,
                  ),
                  child: const Text('Eylem Planı Başlat', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClassBadge(String branch) {
    if (branch == 'GENEL') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
        child: const Text('GENEL', style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, fontSize: 11)),
      );
    }
    
    String grade = branch;
    if (branch.length == 3) grade = branch[0];
    else if (branch.length == 4) grade = branch.substring(0, 2);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
      child: Text('$grade. SINIF', style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }

  Widget _buildAtRiskStudentCard(Map<String, dynamic> data) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.indigo.shade50,
            child: Text(data['name'][0], style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text(data['detail'], style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
            child: Text(data['riskType'], style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
