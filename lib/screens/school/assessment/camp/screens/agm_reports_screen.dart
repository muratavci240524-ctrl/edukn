import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/agm_cycle_model.dart';
import '../models/agm_assignment_log_model.dart';
import '../services/agm_service.dart';

/// AGM Raporlar Ekranı
/// - Kapasite aşımı raporu
/// - Assignment log (audit trail)
/// - Özet istatistikler
class AgmReportsScreen extends StatefulWidget {
  final String institutionId;
  final String cycleId;

  const AgmReportsScreen({
    Key? key,
    required this.institutionId,
    required this.cycleId,
  }) : super(key: key);

  @override
  State<AgmReportsScreen> createState() => _AgmReportsScreenState();
}

class _AgmReportsScreenState extends State<AgmReportsScreen>
    with SingleTickerProviderStateMixin {
  final _service = AgmService();
  late TabController _tabController;

  List<AgmAssignmentLog> _logs = [];
  AgmCycle? _cycle;
  Map<String, String> _studentNames = {}; // ogrenciId -> name
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    // Verileri paralel çekerek hızı artır (Network optimizasyonu)
    final responses = await Future.wait([
      FirebaseFirestore.instance
          .collection('agm_cycles')
          .doc(widget.cycleId)
          .get(),
      _service.getLogs(widget.cycleId),
    ]);

    final cycleDoc = responses[0] as DocumentSnapshot<Map<String, dynamic>>;
    final logs = responses[1] as List<AgmAssignmentLog>;

    // unassignedReasons içindeki öğrencilerin isimlerini Firestore'dan çek
    if (cycleDoc.exists) {
      final cycleData = cycleDoc.data()!;
      finalReasons =
          (cycleData['unassignedReasons'] as Map<String, dynamic>?) ?? {};
      final studentIds = finalReasons.keys.toList();

      // N+1 okuma problemini Future.wait ile çöz (Paralel okuma)
      final fetchFutures = <Future<void>>[];
      for (final id in studentIds) {
        if (!_studentNames.containsKey(id)) {
          fetchFutures.add(
            FirebaseFirestore.instance
                .collection('students')
                .doc(id)
                .get()
                .then((sDoc) {
                  if (sDoc.exists) {
                    final sData = sDoc.data()!;
                    _studentNames[id] =
                        (sData['fullName'] ?? sData['name'] ?? 'İsimsiz')
                            .toString();
                  }
                }),
          );
        }
      }

      if (fetchFutures.isNotEmpty) {
        await Future.wait(fetchFutures);
      }
    }

    if (mounted) {
      setState(() {
        if (cycleDoc.exists) {
          _cycle = AgmCycle.fromMap(cycleDoc.data()!, cycleDoc.id);
        }
        _logs = logs;
        _loading = false;
      });
    }
  }

  Map<String, dynamic> finalReasons = {};

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
        title: const Text(
          'AGM Raporlar',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        centerTitle: true,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.deepOrange,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: Colors.deepOrange,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'Analiz'),
            Tab(text: 'Değişiklik Logu'),
            Tab(text: 'Özet'),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildAnalysisTab(),
                    _buildLogTab(),
                    _buildSummaryTab(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildAnalysisTab() {
    if (_cycle == null) return const Center(child: Text('Veri yüklenemedi.'));

    final reasons = _cycle!.unassignedReasons;
    if (reasons.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 56,
              color: Colors.green.shade200,
            ),
            const SizedBox(height: 12),
            Text(
              'Tüm öğrenciler başarıyla yerleşti!',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: reasons.length + 1, // +1 for the header banner
      itemBuilder: (context, i) {
        if (i == 0) {
          return Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Analiz Sayfası Hakkında',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Bu sayfa, AGM yerleştirme algoritması sonucunda atanamayan veya kriter dışı kalan öğrencilerin durumlarını nedenleriyle listeler. Sınava girmeyenler veya başarı eşiğinin üzerinde olan öğrenciler de burada raporlanır.',
                        style: TextStyle(
                          color: Colors.blue.shade800,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final index = i - 1;
        final ogrenciId = reasons.keys.elementAt(index);
        final ogrenciNedenler = reasons[ogrenciId]!;

        // İsim önceliği: Firestore > Loglar > ID
        String ogrenciAdi = _studentNames[ogrenciId] ?? 'Öğrenci ($ogrenciId)';
        if (ogrenciAdi.contains('($ogrenciId)')) {
          final logMatches = _logs
              .where((l) => l.ogrenciId == ogrenciId)
              .toList();
          if (logMatches.isNotEmpty) {
            ogrenciAdi = logMatches.first.ogrenciAdi;
          }
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: CircleAvatar(
              backgroundColor: Colors.red.shade50,
              child: const Icon(
                Icons.report_problem,
                color: Colors.red,
                size: 20,
              ),
            ),
            title: Text(
              ogrenciAdi,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${ogrenciNedenler.length} sorun tespit edildi',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: ogrenciNedenler
                      .map(
                        (n) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.arrow_right,
                                size: 18,
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  n,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLogTab() {
    if (_logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Henüz log kaydı yok',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _logs.length,
      itemBuilder: (context, i) => _buildLogCard(_logs[i]),
    );
  }

  Widget _buildLogCard(AgmAssignmentLog log) {
    final isOverride = log.isOverride;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: isOverride
                      ? Colors.orange.shade50
                      : Colors.blue.shade50,
                  child: Icon(
                    isOverride ? Icons.warning_amber : Icons.swap_horiz,
                    size: 16,
                    color: isOverride ? Colors.orange : Colors.blue,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log.ogrenciAdi,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        log.aciklama,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isOverride)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Text(
                      'Override',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 16),
            Row(
              children: [
                Icon(
                  Icons.person_outline,
                  size: 13,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(width: 4),
                Text(
                  log.yapanKullaniciAdi,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
                const Spacer(),
                Icon(Icons.access_time, size: 13, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(
                  _formatDate(log.tarih),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryTab() {
    final totalLogs = _logs.length;
    final overrideLogs = _logs.where((l) => l.isOverride).length;
    final manuelLogs = _logs.where((l) => !l.isOverride).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCard(
            title: 'Toplam Değişiklik',
            value: '$totalLogs',
            icon: Icons.history,
            color: Colors.blue,
          ),
          const SizedBox(height: 12),
          _buildSummaryCard(
            title: 'Manuel Taşıma',
            value: '$manuelLogs',
            icon: Icons.swap_horiz,
            color: Colors.teal,
          ),
          const SizedBox(height: 12),
          _buildSummaryCard(
            title: 'Kapasite Override',
            value: '$overrideLogs',
            icon: Icons.warning_amber,
            color: Colors.orange,
          ),
          if (overrideLogs > 0) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade100),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange.shade700),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$overrideLogs grupta kapasite aşımı yapılmıştır. '
                      'Lütfen öğretmen yükünü kontrol edin.',
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
