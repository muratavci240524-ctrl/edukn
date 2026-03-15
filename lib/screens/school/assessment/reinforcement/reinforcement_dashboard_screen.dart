import 'package:flutter/material.dart';

class ReinforcementDashboardScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const ReinforcementDashboardScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  _ReinforcementDashboardScreenState createState() =>
      _ReinforcementDashboardScreenState();
}

class _ReinforcementDashboardScreenState
    extends State<ReinforcementDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Mock Data for Demo
  final List<Map<String, dynamic>> _weakTopics = [
    {
      'branch': '8-A',
      'subject': 'Matematik',
      'topic': 'Üslü Sayılar',
      'successRate': 42.5,
      'studentCount': 12,
    },
    {
      'branch': '8-A',
      'subject': 'Fen Bilimleri',
      'topic': 'DNA ve Genetik Kod',
      'successRate': 48.0,
      'studentCount': 10,
    },
    {
      'branch': '8-B',
      'subject': 'Matematik',
      'topic': 'Kareköklü İfadeler',
      'successRate': 38.2,
      'studentCount': 15,
    },
    {
      'branch': '8-C',
      'subject': 'T.C. İnkılap Tarihi',
      'topic': 'Bir Kahraman Doğuyor',
      'successRate': 55.0,
      'studentCount': 5,
    },
  ];

  final List<Map<String, dynamic>> _atRiskStudents = [
    {
      'name': 'Ahmet Yılmaz',
      'branch': '8-A',
      'riskType': 'Düşüşte',
      'detail': 'Son 2 sınavda -15 net düşüş',
      'avgNet': 45.5,
    },
    {
      'name': 'Ayşe Demir',
      'branch': '8-B',
      'riskType': 'Kritik Seviye',
      'detail': 'Matematik ortalaması %20 altında',
      'avgNet': 32.0,
    },
    {
      'name': 'Mehmet Öz',
      'branch': '8-A',
      'riskType': 'Devamsızlık',
      'detail': 'Son 3 etüte katılmadı',
      'avgNet': 58.0,
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          'Güçlendirme Programları',
          style: TextStyle(
            color: Colors.indigo.shade900,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.indigo),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.indigo,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.indigo,
          indicatorWeight: 3,
          labelStyle: TextStyle(fontWeight: FontWeight.bold),
          tabs: [
            Tab(text: 'Şube Bazlı Analiz'),
            Tab(text: 'Öğrenci Bazlı Analiz'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildBranchTab(), _buildStudentTab()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // New general program
          _showCreateProgramDialog(context);
        },
        label: Text('Yeni Program'),
        icon: Icon(Icons.add),
        backgroundColor: Colors.indigo,
      ),
    );
  }

  Widget _buildBranchTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            title: 'Haftalık Şube Analizi',
            description:
                'Son yapılan deneme sınavlarına göre başarı oranı %50\'nin altında kalan kazanımlar aşağıda listelenmiştir.',
            icon: Icons.analytics_outlined,
            color: Colors.blue,
          ),
          SizedBox(height: 24),
          Text(
            'Alarm Veren Konular (Acil Müdahale)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.indigo.shade900,
            ),
          ),
          SizedBox(height: 12),
          ..._weakTopics.map((topic) => _buildWeakTopicCard(topic)).toList(),
          SizedBox(height: 80), // Fab space
        ],
      ),
    );
  }

  Widget _buildStudentTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            title: 'Riskli Öğrenci Takibi',
            description:
                'Akademik başarısında ani düşüş yaşayan veya kritik seviyenin altında olan öğrenciler.',
            icon: Icons.person_search_outlined,
            color: Colors.orange,
          ),
          SizedBox(height: 24),
          TextField(
            decoration: InputDecoration(
              hintText: 'Öğrenci Ara...',
              prefixIcon: Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          SizedBox(height: 24),
          Text(
            'Takip Listesi',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.indigo.shade900,
            ),
          ),
          SizedBox(height: 12),
          ..._atRiskStudents
              .map((student) => _buildAtRiskStudentCard(student))
              .toList(),
          SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color.withOpacity(0.8),
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(color: Colors.black87, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeakTopicCard(Map<String, dynamic> data) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Colors.red.withOpacity(0.1),
        ), // Red border for alert
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  data['branch'],
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  data['subject'],
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: Colors.red,
                    ),
                    SizedBox(width: 4),
                    Text(
                      '%${data['successRate']}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Divider(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kazanım:',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    SizedBox(height: 4),
                    Text(
                      data['topic'],
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Etkilenen Öğrenci: ${data['studentCount']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () {
                  _showCreateProgramDialog(
                    context,
                    initialTopic: data['topic'],
                    initialBranch: data['branch'],
                  );
                },
                icon: Icon(Icons.add_task, size: 18),
                label: Text('Etüt Ata'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAtRiskStudentCard(Map<String, dynamic> data) {
    Color riskColor = data['riskType'] == 'Kritik Seviye'
        ? Colors.red
        : Colors.orange;
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.grey.shade200,
            child: Text(
              data['name'].substring(0, 1),
              style: TextStyle(
                color: Colors.grey.shade800,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      data['name'],
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        data['branch'],
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  data['detail'],
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                data['riskType'],
                style: TextStyle(
                  color: riskColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              SizedBox(height: 4),
              ElevatedButton(
                onPressed: () {},
                child: Text('İncele'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.indigo,
                  elevation: 0,
                  side: BorderSide(color: Colors.indigo.withOpacity(0.2)),
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  minimumSize: Size(0, 32),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showCreateProgramDialog(
    BuildContext context, {
    String? initialTopic,
    String? initialBranch,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Güçlendirme Programı Oluştur'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(
                labelText: 'Program Adı',
                hintText: 'Örn: Matematik Etüt - Üslü Sayılar',
              ),
              controller: TextEditingController(
                text: initialTopic != null ? 'Etüt: $initialTopic' : '',
              ),
            ),
            SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(labelText: 'Hedef Şube/Öğrenci'),
              controller: TextEditingController(text: initialBranch ?? ''),
            ),
            SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(
                labelText: 'Tarih',
                suffixIcon: Icon(Icons.calendar_today),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Program başarıyla oluşturuldu')),
              );
            },
            child: Text('Oluştur'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
          ),
        ],
      ),
    );
  }
}
