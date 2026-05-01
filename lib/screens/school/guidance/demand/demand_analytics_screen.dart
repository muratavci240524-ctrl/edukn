import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../models/guidance/demand_model.dart';
import '../../../../services/guidance/demand_service.dart';

class DemandAnalyticsScreen extends StatefulWidget {
  final String institutionId;
  final String? schoolTypeId;
  final bool showAllSchoolTypes;

  const DemandAnalyticsScreen({
    Key? key,
    required this.institutionId,
    this.schoolTypeId,
    this.showAllSchoolTypes = false,
  }) : super(key: key);

  @override
  State<DemandAnalyticsScreen> createState() => _DemandAnalyticsScreenState();
}

class _DemandAnalyticsScreenState extends State<DemandAnalyticsScreen> {
  final DemandService _demandService = DemandService();
  String? _selectedSchoolTypeId;
  List<Map<String, dynamic>> _schoolTypes = [];
  bool _loadingSchoolTypes = false;

  @override
  void initState() {
    super.initState();
    _selectedSchoolTypeId = widget.schoolTypeId;
    if (widget.showAllSchoolTypes) {
      _loadSchoolTypes();
    }
  }

  Future<void> _loadSchoolTypes() async {
    setState(() => _loadingSchoolTypes = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('schoolTypes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();
      final types = snap.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'name': data['schoolTypeName'] ?? 
                  data['typeName'] ?? 
                  data['schoolType'] ?? 
                  data['name'] ?? 
                  d.id
        };
      }).toList();

      types.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

      if (mounted) setState(() { _schoolTypes = types; _loadingSchoolTypes = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingSchoolTypes = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.indigo, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Talep Analizleri',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E293B),
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        children: [
          if (widget.showAllSchoolTypes) _buildSchoolTypeFilter(),
          Expanded(
            child: StreamBuilder<List<DemandModel>>(
              stream: _demandService.streamDemands(
                institutionId: widget.institutionId,
                schoolTypeId: _selectedSchoolTypeId,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) return _buildEmptyState();
                
                final demands = snapshot.data!;
                final int total = demands.length;
                final int closed = demands.where((d) => d.status == DemandStatus.completed).length;
                final int open = total - closed;
                final double rate = total > 0 ? (closed / total) : 0.0;

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummaryCards(total, closed, open, rate),
                      const SizedBox(height: 32),
                      Text(
                        'Kategori Dağılımı',
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                      ),
                      const SizedBox(height: 16),
                      _buildCategoryBarChart(demands),
                      const SizedBox(height: 32),
                      Text(
                        'Öncelik Durumu',
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                      ),
                      const SizedBox(height: 16),
                      _buildPriorityStats(demands),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(int total, int closed, int open, double rate) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildAnalyticCard('Toplam Talep', total.toString(), Colors.indigo, Icons.assignment)),
            const SizedBox(width: 12),
            Expanded(child: _buildAnalyticCard('Kapanan', closed.toString(), Colors.green, Icons.check_circle)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildAnalyticCard('Açık Talepler', open.toString(), Colors.orange, Icons.pending)),
            const SizedBox(width: 12),
            Expanded(child: _buildAnalyticCard('Tamamlama %', "${(rate * 100).toStringAsFixed(1)}%", Colors.teal, Icons.speed)),
          ],
        ),
      ],
    );
  }

  Widget _buildAnalyticCard(String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade400, fontWeight: FontWeight.bold)),
              Icon(icon, color: color.withOpacity(0.5), size: 16),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildCategoryBarChart(List<DemandModel> demands) {
    final categories = demands.map((d) => d.category).toSet().toList();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: categories.map((cat) {
          final count = demands.where((d) => d.category == cat).length;
          final percent = demands.isNotEmpty ? count / demands.length : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(cat, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                    Text(count.toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percent,
                    minHeight: 8,
                    backgroundColor: Colors.indigo.withOpacity(0.05),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.indigo),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPriorityStats(List<DemandModel> demands) {
    final urgentCount = demands.where((d) => d.priority == DemandPriority.urgent).length;
    final highCount = demands.where((d) => d.priority == DemandPriority.high).length;
    final normalCount = demands.where((d) => d.priority == DemandPriority.medium || d.priority == DemandPriority.low).length;

    return Row(
      children: [
        _buildPriorityItem('Acil', urgentCount, Colors.red),
        _buildPriorityItem('Yüksek', highCount, Colors.deepOrange),
        _buildPriorityItem('Diğer', normalCount, Colors.blue),
      ],
    );
  }

  Widget _buildPriorityItem(String label, int count, Color color) {
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Text(count.toString(), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildSchoolTypeFilter() {
    if (_loadingSchoolTypes) return const SizedBox.shrink();
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 10),
      color: Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _schoolTypes.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) return _buildFilterChip(null, 'Tümü');
          final st = _schoolTypes[index - 1];
          return _buildFilterChip(st['id'], st['name']);
        },
      ),
    );
  }

  Widget _buildFilterChip(String? id, String label) {
    final isSelected = _selectedSchoolTypeId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : Colors.indigo)),
        selected: isSelected,
        onSelected: (_) => setState(() => _selectedSchoolTypeId = id),
        selectedColor: Colors.indigo,
        backgroundColor: Colors.indigo.withOpacity(0.05),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        showCheckmark: false,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.analytics_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('Veri bulunamadı.', style: TextStyle(color: Colors.blueGrey.shade300)),
        ],
      ),
    );
  }
}
