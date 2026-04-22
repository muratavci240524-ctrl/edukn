import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../widgets/edukn_logo.dart';
import '../../../../models/guidance/demand_model.dart';
import '../../../../services/guidance/demand_service.dart';
import 'create_demand_dialog.dart';

class DemandDashboardScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final Map<String, dynamic>? userData;
  /// true = genel okul yönetimi → tüm okul türlerinin taleplerini göster + filtre
  final bool showAllSchoolTypes;

  const DemandDashboardScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    this.userData,
    this.showAllSchoolTypes = false,
  }) : super(key: key);

  @override
  State<DemandDashboardScreen> createState() => _DemandDashboardScreenState();
}

class _DemandDashboardScreenState extends State<DemandDashboardScreen> with SingleTickerProviderStateMixin {
  final DemandService _demandService = DemandService();
  late TabController _tabController;
  final String _currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  
  String? _statusFilter;
  String? _priorityFilter;
  String _searchQuery = '';

  // Okul türü filtresi (showAllSchoolTypes=true olduğunda)
  String? _selectedSchoolTypeId; // null = tümü
  String? _selectedSchoolTypeName;
  List<Map<String, dynamic>> _schoolTypes = []; // {id, name}
  bool _loadingSchoolTypes = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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

      // Sıralama: Anaokulu > İlkokul > Ortaokul > Lise
      int getRank(String name) {
        final n = name.toLowerCase();
        if (n.contains('ana')) return 1;   // Anaokulu, Anasınıfı
        if (n.contains('ilk')) return 2;   // İlkokul
        if (n.contains('orta')) return 3;  // Ortaokul
        if (n.contains('lise')) return 4;  // Lise
        return 99;
      }

      types.sort((a, b) {
        final rA = getRank(a['name'] as String);
        final rB = getRank(b['name'] as String);
        if (rA != rB) return rA.compareTo(rB);
        return (a['name'] as String).compareTo(b['name'] as String);
      });

      if (mounted) setState(() { _schoolTypes = types; _loadingSchoolTypes = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingSchoolTypes = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get _isAdmin => widget.userData == null || widget.userData!['role'] == 'mudur' || widget.userData!['role'] == 'genel_mudur';

  // Aktif schoolTypeId: global modda seçili filtre, yoksa widget'tan gelen
  String? get _activeSchoolTypeId {
    if (widget.showAllSchoolTypes) {
      return _selectedSchoolTypeId; // null = tümü
    }
    return widget.schoolTypeId.isEmpty ? null : widget.schoolTypeId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Text(
          'Talepler',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
        ),
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.indigo),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.indigo,
          unselectedLabelColor: Colors.blueGrey.shade400,
          indicatorColor: Colors.indigo,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: [
            Tab(text: _isAdmin ? 'Tüm Talepler' : 'Gelen Talepler'),
            Tab(text: 'Benim Taleplerim'),
            Tab(text: 'Analiz & Özet'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDemandList(tab: 0),
          _buildDemandList(tab: 1),
          _buildAnalyticsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDemandDialog,
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_task, color: Colors.white),
        label: const Text('Yeni Talep Oluştur', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }

  Widget _buildDemandList({required int tab}) {
    return Column(
      children: [
        // Okul türü filtresi (sadece global modda)
        if (widget.showAllSchoolTypes) _buildSchoolTypeFilter(),
        _buildFilterBar(),
        Expanded(
          child: StreamBuilder<List<DemandModel>>(
            stream: _demandService.streamDemands(
              institutionId: widget.institutionId,
              schoolTypeId: _activeSchoolTypeId,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) return _buildEmptyState();

              var demands = snapshot.data!;

              demands = demands.where((d) {
                if (tab == 0) {
                  if (!_isAdmin && !d.receiverUids.contains(_currentUid)) return false;
                } else if (tab == 1) {
                  if (d.senderUid != _currentUid) return false;
                }
                if (_statusFilter != null && d.status.name != _statusFilter) return false;
                if (_priorityFilter != null && d.priority.name != _priorityFilter) return false;
                if (_searchQuery.isNotEmpty) {
                  final q = _searchQuery.toLowerCase();
                  return d.title.toLowerCase().contains(q) || 
                         d.studentName?.toLowerCase().contains(q) == true ||
                         d.senderName.toLowerCase().contains(q);
                }
                return true;
              }).toList();

              if (demands.isEmpty) return _buildEmptyState();

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: demands.length,
                itemBuilder: (context, index) => _buildDemandCard(demands[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSchoolTypeFilter() {
    if (_loadingSchoolTypes) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      color: Colors.white,
      child: ScrollConfiguration(
        behavior: _HorizontalScrollBehavior(),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              const Text('Okul Türü:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
              const SizedBox(width: 8),
              _buildSchoolTypeChip(null, 'Tüm Okul Türleri'),
              ..._schoolTypes.map((st) => _buildSchoolTypeChip(st['id'], st['name'])),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSchoolTypeChip(String? id, String label) {
    final isSelected = _selectedSchoolTypeId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : Colors.indigo.shade700)),
        selected: isSelected,
        onSelected: (_) => setState(() {
          _selectedSchoolTypeId = id;
          _selectedSchoolTypeName = label;
        }),
        backgroundColor: Colors.indigo.shade50,
        selectedColor: Colors.indigo,
        checkmarkColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.transparent,
      child: ScrollConfiguration(
        behavior: _HorizontalScrollBehavior(),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip('Tümü', null, _statusFilter == null, (val) => setState(() => _statusFilter = null)),
              _buildFilterChip('Açık', 'open', _statusFilter == 'open', (val) => setState(() => _statusFilter = 'open')),
              _buildFilterChip('İşlemde', 'inProgress', _statusFilter == 'inProgress', (val) => setState(() => _statusFilter = 'inProgress')),
              _buildFilterChip('Tamamlandı', 'completed', _statusFilter == 'completed', (val) => setState(() => _statusFilter = 'completed')),
              const SizedBox(width: 8),
              const VerticalDivider(width: 1),
              const SizedBox(width: 8),
              _buildFilterChip('Acil', 'urgent', _priorityFilter == 'urgent', (val) => setState(() => _priorityFilter = val ? 'urgent' : null), isPriority: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String? value, bool isSelected, Function(bool) onSelected, {bool isPriority = false}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : Colors.blueGrey)),
        selected: isSelected,
        onSelected: onSelected,
        backgroundColor: Colors.grey.shade100,
        selectedColor: isPriority ? Colors.red.shade600 : Colors.indigo,
        checkmarkColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildDemandCard(DemandModel demand) {
    final bool isUrgent = demand.priority == DemandPriority.urgent;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: isUrgent ? Colors.red.withOpacity(0.2) : Colors.transparent, width: 1.5)),
      elevation: 0,
      child: InkWell(
        onTap: () => _showDemandDetail(demand),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: _getPriorityColor(demand.priority).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                    child: Icon(_getCategoryIcon(demand.category), color: _getPriorityColor(demand.priority), size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildStatusBadge(demand.status),
                            Text(DateFormat('dd MMM HH:mm').format(demand.createdAt), style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade300)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(demand.title, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF1E293B))),
                        if (demand.studentName != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.person_outline, size: 14, color: Colors.blueGrey),
                                const SizedBox(width: 4),
                                Text("${demand.studentName} (${demand.studentClassName ?? ''})", style: const TextStyle(fontSize: 13, color: Colors.blueGrey, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        CircleAvatar(radius: 10, backgroundColor: Colors.indigo.shade50, child: Text(demand.senderName[0], style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                        const SizedBox(width: 8),
                        Flexible(child: Text("Gönderen: ${demand.senderName}", style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600), overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                  if (demand.receiverNames.isNotEmpty)
                    Expanded(child: Text("Alıcı: ${demand.receiverNames.join(', ')}", style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600, fontStyle: FontStyle.italic), textAlign: TextAlign.end, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(DemandStatus status) {
    Color color;
    String label;
    switch (status) {
      case DemandStatus.open: color = Colors.green; label = 'Açık'; break;
      case DemandStatus.pending: color = Colors.orange; label = 'Beklemede'; break;
      case DemandStatus.inProgress: color = Colors.blue; label = 'İşlemde'; break;
      case DemandStatus.completed: color = Colors.blueGrey; label = 'Tamamlandı'; break;
      case DemandStatus.cancelled: color = Colors.red; label = 'İptal Edildi'; break;
    }
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)), child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)));
  }

  Color _getPriorityColor(DemandPriority priority) {
    switch (priority) {
      case DemandPriority.low: return Colors.blue;
      case DemandPriority.medium: return Colors.orange;
      case DemandPriority.high: return Colors.deepOrange;
      case DemandPriority.urgent: return Colors.red;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Akademik': return Icons.school;
      case 'Disiplin': return Icons.gavel;
      case 'Rehberlik': return Icons.psychology;
      case 'Sosyal': return Icons.groups;
      default: return Icons.help_outline;
    }
  }

  Widget _buildEmptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.task_alt, size: 64, color: Colors.grey.shade300), const SizedBox(height: 16), Text('Talep bulunamadı.', style: TextStyle(color: Colors.blueGrey.shade300))]));
  }

  Widget _buildAnalyticsTab() {
    return Column(
      children: [
        if (widget.showAllSchoolTypes) _buildSchoolTypeFilter(),
        Expanded(
          child: StreamBuilder<List<DemandModel>>(
            stream: _demandService.streamDemands(institutionId: widget.institutionId, schoolTypeId: _activeSchoolTypeId),
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
                    Text('Genel Durum', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _buildAnalyticCard('Toplam', total.toString(), Colors.indigo)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildAnalyticCard('Kapanan', closed.toString(), Colors.green)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _buildAnalyticCard('Açık', open.toString(), Colors.orange)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildAnalyticCard('Başarı %', "${(rate * 100).toStringAsFixed(1)}%", Colors.teal)),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Text('Kategori Dağılımı', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    _buildCategoryBarChart(demands),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyticCard(String title, String value, Color color) {
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.1))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade400, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text(value, style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: color))]));
  }

  Widget _buildCategoryBarChart(List<DemandModel> demands) {
    final categories = demands.map((d) => d.category).toSet().toList();
    return Column(children: categories.map((cat) {
        final count = demands.where((d) => d.category == cat).length;
        final percent = demands.isNotEmpty ? count / demands.length : 0.0;
        return Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(cat, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)), Text(count.toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))]), const SizedBox(height: 6), ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: percent, minHeight: 8, backgroundColor: Colors.grey.shade200, valueColor: const AlwaysStoppedAnimation<Color>(Colors.indigo)))]));
      }).toList());
  }

  void _showCreateDemandDialog() {
    showDialog(context: context, builder: (context) => CreateDemandDialog(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, senderUid: _currentUid, senderName: _getUserDisplayName(), senderRole: _getUserRoleKey(), userData: widget.userData));
  }

  void _showDemandDetail(DemandModel demand) {
     showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => _DemandDetailSheet(demand: demand, currentUid: _currentUid, currentUserName: _getUserDisplayName(), onUpdate: () => setState(() {})));
  }

  String _getUserDisplayName() { if (widget.userData != null) return widget.userData!['fullName'] ?? 'İsimsiz'; return 'Yönetici'; }
  String _getUserRoleKey() { if (widget.userData != null) return widget.userData!['role'] ?? 'admin'; return 'admin'; }
}

class _DemandDetailSheet extends StatefulWidget {
  final DemandModel demand;
  final String currentUid;
  final String currentUserName;
  final VoidCallback onUpdate;
  const _DemandDetailSheet({Key? key, required this.demand, required this.currentUid, required this.currentUserName, required this.onUpdate}) : super(key: key);
  @override State<_DemandDetailSheet> createState() => _DemandDetailSheetState();
}

class _DemandDetailSheetState extends State<_DemandDetailSheet> {
  final TextEditingController _noteController = TextEditingController();
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.demand;
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_buildCategoryBadge(d.category), _buildPriorityBadge(d.priority)]),
          const SizedBox(height: 16),
          Text(d.title, style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
          const SizedBox(height: 8),
          Text(d.description, style: TextStyle(fontSize: 15, color: Colors.blueGrey.shade700, height: 1.5)),
          const SizedBox(height: 24),
          if (d.studentName != null) _buildInfoRow(Icons.person_outline, 'Öğrenci', "${d.studentName} (${d.studentClassName ?? ''})"),
          _buildInfoRow(Icons.send_outlined, 'Gönderen', "${d.senderName} (${d.senderRole.toUpperCase()})"),
          if (d.receiverNames.isNotEmpty) _buildInfoRow(Icons.account_box_outlined, 'Atananlar', d.receiverNames.join(', ')),
          _buildInfoRow(Icons.calendar_today_outlined, 'Tarih', DateFormat('dd.MM.yyyy HH:mm').format(d.createdAt)),
          
          if (d.status == DemandStatus.completed) ...[
            const Divider(height: 48),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.green.shade100)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Row(children: [const Icon(Icons.check_circle, color: Colors.green, size: 18), const SizedBox(width: 8), Text('Sonuç Notu', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900))]),
                   const SizedBox(height: 8),
                   Text(d.closingNote ?? 'Not belirtilmemiş.', style: TextStyle(color: Colors.green.shade800)),
                   const SizedBox(height: 8),
                   Text("Kapatan: ${d.closerName} · ${DateFormat('dd.MM.yyyy').format(d.closedAt!)}", style: TextStyle(fontSize: 11, color: Colors.green.shade600)),
                ],
              ),
            ),
          ] else if (d.receiverUids.contains(widget.currentUid) || widget.currentUid == d.senderUid || true) ...[
            const Divider(height: 48),
            const Text('Talebi Yanıtla & Kapat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            TextField(controller: _noteController, maxLines: 3, decoration: InputDecoration(hintText: 'Görüşme sonucu, alınan aksiyonlar...', filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)))),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, height: 52, child: ElevatedButton(onPressed: _isSaving ? null : _closeDemand, style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('Talebi Tamamla ve Kapat', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)))),
          ],
        ],
      ),
    );
  }

  Future<void> _closeDemand() async {
    if (_noteController.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen bir sonuç notu giriniz.'))); return; }
    setState(() => _isSaving = true);
    try {
      await DemandService().closeDemand(docId: widget.demand.id, closingNote: _noteController.text, closerUid: widget.currentUid, closerName: widget.currentUserName);
      Navigator.pop(context);
      widget.onUpdate();
    } catch (e) { setState(() => _isSaving = false); }
  }

  Widget _buildInfoRow(IconData icon, String label, String value) { return Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [Icon(icon, size: 18, color: Colors.blueGrey.shade300), const SizedBox(width: 12), Text("$label: ", style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13)), Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155)))])); }
  Widget _buildCategoryBadge(String cat) { return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(20)), child: Text(cat, style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, fontSize: 11))); }
  Widget _buildPriorityBadge(DemandPriority p) {
    Color c = p == DemandPriority.urgent ? Colors.red : (p == DemandPriority.high ? Colors.deepOrange : Colors.blue);
    String label = p == DemandPriority.low ? 'DÜŞÜK' : p == DemandPriority.medium ? 'NORMAL' : p == DemandPriority.high ? 'YÜKSEK' : 'ACİL';
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(20)), child: Text(label, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 11)));
  }
}

class _HorizontalScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        ...super.dragDevices,
        PointerDeviceKind.mouse,
      };
}
