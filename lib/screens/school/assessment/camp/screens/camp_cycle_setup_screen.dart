import 'dart:convert';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/camp_cycle_model.dart';
import '../models/camp_group_model.dart';
import '../models/camp_time_slot_model.dart';
import '../repository/camp_repository.dart';
import '../services/camp_service.dart';
import '../../../classroom_management_screen.dart';

class CampCycleSetupScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String? schoolTypeName;
  final CampCycle? initialCycle;
  final int initialTabIndex;

  const CampCycleSetupScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    this.schoolTypeName,
    this.initialCycle,
    this.initialTabIndex = 0,
  }) : super(key: key);

  @override
  State<CampCycleSetupScreen> createState() => _CampCycleSetupScreenState();
}

class _CampCycleSetupScreenState extends State<CampCycleSetupScreen>
    with SingleTickerProviderStateMixin {
  final _service = CampService();
  final _repo = CampRepository();
  final _db = FirebaseFirestore.instance;
  late TabController _tabController;

  // ── Cycle Başlığı ───────────────────────────────────────
  final _titleController = TextEditingController();
  final _examSearchController = TextEditingController();
  final _specialCapacityController = TextEditingController(text: '24');

  // ── Sınavlar ───────────────────────────────────────────
  List<String> _selectedExamIds = [];
  List<String> _selectedExamNames = [];
  List<Map<String, dynamic>> _exams = [];
  Map<String, String> _examDersler = {};
  bool _isLoading = false;

  // ── Tarih ──────────────────────────────────────────────
  DateTime _baslangic = DateTime.now();
  DateTime _bitis = DateTime.now().add(const Duration(days: 6));

  // ── Soft kısıtlar ──────────────────────────────────────
  int? _maxSaat;
  int? _minDers;

  // ── Özel Sınıf ──────────────────────────────────────────
  bool _isSpecialClassActive = false;
  String? _specialClassRoomId;
  String? _specialClassRoomName;

  // ── Saat dilimleri ─────────────────────────────────────
  List<CampTimeSlot> _existingSlots = [];
  bool _loadingSlots = true;
  bool _saving = false;

  // ── UI / UX State ──────────────────────────────────────
  List<CampSlotTeacherEntry>? _copiedEntries;
  String? _expandedSlotId;
  List<CampTimeSlot> _allLibrarySlots = [];

  // ── Öğretmenler & Derslikler ───────────────────────────
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _classrooms = [];
  List<Map<String, dynamic>> _allBranchStudents = [];
  int _potentialStudentCount = 0;
  Set<String> _excludedStudentIds = {}; // Kapsam dışı bırakılan öğrenciler

  final List<String> _gunler = [
    'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTabIndex);

    if (widget.initialCycle != null) {
      final c = widget.initialCycle!;
      _titleController.text = c.title ?? '';
      _selectedExamIds = c.referansDenemeSinavIds.isNotEmpty
          ? c.referansDenemeSinavIds
          : [c.referansDenemeSinavId];
      _selectedExamNames = c.referansDenemeSinavAdlari.isNotEmpty
          ? c.referansDenemeSinavAdlari
          : [c.referansDenemeSinavAdi];
      _baslangic = c.baslangicTarihi;
      _bitis = c.bitisTarihi;
      _maxSaat = c.haftalikMaksimumSaat;
      _minDers = c.minimumDersSayisi;
      _isSpecialClassActive = c.isSpecialClassActive;
      _specialClassRoomId = c.specialClassRoomId;
      _specialClassRoomName = c.specialClassRoomName;
      _specialCapacityController.text = (c.specialClassCapacity ?? 24).toString();
      _excludedStudentIds = Set<String>.from(c.excludedStudentIds);
    }

    _loadData();
    if (_selectedExamIds.isNotEmpty) _updateExamDersler();
  }

  Future<void> _loadData() async {
    final librarySlots = await _repo.getTimeSlots(widget.institutionId, includeInactive: false);
    final teacherSnap = await _db.collection('users').where('institutionId', isEqualTo: widget.institutionId).where('type', isEqualTo: 'staff').get();
    final classroomSnap = await _db.collection('classrooms').where('institutionId', isEqualTo: widget.institutionId).where('schoolTypeId', isEqualTo: widget.schoolTypeId).where('isActive', isEqualTo: true).get();
    final examSnap = await _db.collection('trial_exams').where('institutionId', isEqualTo: widget.institutionId).where('isActive', isEqualTo: true).get();

    if (mounted) {
      setState(() {
        _allLibrarySlots = librarySlots;
        _exams = examSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList();

        // Robust sorting: Newest first
        _exams.sort((a, b) {
          final da = a['date'];
          final db = b['date'];
          DateTime dtA = (da is Timestamp) ? da.toDate() : (da is String ? DateTime.tryParse(da) ?? DateTime(1900) : DateTime(1900));
          DateTime dtB = (db is Timestamp) ? db.toDate() : (db is String ? DateTime.tryParse(db) ?? DateTime(1900) : DateTime(1900));
          return dtB.compareTo(dtA);
        });

        _classrooms = classroomSnap.docs.map((d) => {'id': d.id, 'name': d.data()['classroomName'] ?? '', 'capacity': d.data()['capacity'] ?? 0}).toList();
        _classrooms.sort((a, b) => _compareNatural(a['name'] ?? '', b['name'] ?? ''));
        
        _teachers = teacherSnap.docs.map((d) => {'id': d.id, 'name': d.data()['fullName'] ?? '${d.data()['name']} ${d.data()['surname']}', 'branch': d.data()['branch'] ?? ''}).toList();
        _teachers.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

        _loadingSlots = false;

        // Kütüphaneden silinenleri aktif seçimlerden de temizle
        if (_existingSlots.isNotEmpty) {
          _existingSlots.removeWhere((es) => !_allLibrarySlots.any((ls) => ls.id == es.id));
        }
      });
      if (widget.initialCycle != null) _loadExistingSlotsFromCycle(widget.initialCycle!.id);
      if (_selectedExamIds.isNotEmpty) _updatePotentialStudents();
    }
  }

  Future<void> _updatePotentialStudents() async {
    if (_selectedExamIds.isEmpty) {
      setState(() => _potentialStudentCount = 0);
      return;
    }
    try {
      final List<Map<String, dynamic>> branchStudents = [];
      final Set<String> processedStudentIds = {};

      for (final examId in _selectedExamIds) {
        final examDoc = await _db.collection('trial_exams').doc(examId).get();
        if (!examDoc.exists) continue;

        final examData = examDoc.data()!;
        final selectedBranches = (examData['selectedBranches'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
        final classLevel = examData['classLevel']?.toString() ?? '';

        if (selectedBranches.isNotEmpty) {
          final futures = selectedBranches.map((branch) => 
            _db.collection('students').where('institutionId', isEqualTo: widget.institutionId).where('className', isEqualTo: branch).where('isActive', isEqualTo: true).get()
          );
          final snaps = await Future.wait(futures);
          for (final snap in snaps) {
            for (final doc in snap.docs) {
              if (processedStudentIds.contains(doc.id)) continue;
              processedStudentIds.add(doc.id);
              branchStudents.add({'id': doc.id, ...doc.data()});
            }
          }
        } else if (classLevel.isNotEmpty) {
           final snap = await _db.collection('students').where('institutionId', isEqualTo: widget.institutionId).where('classLevel', isEqualTo: classLevel).where('isActive', isEqualTo: true).get();
           for (final doc in snap.docs) {
              if (processedStudentIds.contains(doc.id)) continue;
              processedStudentIds.add(doc.id);
              branchStudents.add({'id': doc.id, ...doc.data()});
            }
        }
      }
      if (mounted) {
        setState(() {
          _allBranchStudents = branchStudents;
          _potentialStudentCount = branchStudents.length;
        });
      }
    } catch (e) { debugPrint('Öğrenci yükleme hatası: $e'); }
  }

  Future<void> _loadExistingSlotsFromCycle(String cycleId) async {
    try {
      final groups = await _repo.getGroupsByCycle(cycleId);
      final Map<String, CampTimeSlot> slotMap = {};
      for (final g in groups) {
        if (!slotMap.containsKey(g.saatDilimiId)) {
          // Kütüphaneden silinmişse programa dahil etme
          if (!_allLibrarySlots.any((ls) => ls.id == g.saatDilimiId)) continue;

          slotMap[g.saatDilimiId] = CampTimeSlot(id: g.saatDilimiId, institutionId: widget.institutionId, ad: g.saatDilimiAdi, gun: g.gun, baslangicSaat: g.baslangicSaat, bitisSaat: g.bitisSaat, ogretmenGirisler: []);
        }
        
        if (slotMap.containsKey(g.saatDilimiId)) {
          slotMap[g.saatDilimiId]!.ogretmenGirisler.add(CampSlotTeacherEntry(dersId: g.dersId, dersAdi: g.dersAdi, ogretmenId: g.ogretmenId, ogretmenAdi: g.ogretmenAdi, derslikId: g.derslikId, derslikAdi: g.derslikAdi, kapasite: g.kapasite));
        }
      }
      if (mounted) setState(() => _existingSlots = slotMap.values.toList());
    } catch (e) { debugPrint('Hata: $e'); }
  }

  Future<void> _updateExamDersler() async {
    Map<String, String> allDersler = {};
    for (var examId in _selectedExamIds) {
      final doc = await _db.collection('trial_exams').doc(examId).get();
      final data = doc.data() ?? {};
      final answerKeys = data['answerKeys'] as Map<String, dynamic>? ?? {};
      if (answerKeys.isNotEmpty) {
        final firstBooklet = answerKeys.values.first;
        if (firstBooklet is Map<String, dynamic>) {
          for (final k in firstBooklet.keys) allDersler[k] = k;
        }
      }
    }
    setState(() => _examDersler = allDersler);
  }

  void _showExamSelectionDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSt) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const Icon(Icons.quiz_outlined, color: Colors.orange),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('Sınav Seçimi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _examSearchController,
                  decoration: _inputDecoration('Sınav Ara...').copyWith(prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.grey.shade50),
                  onChanged: (val) => setSt(() {}),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Builder(
                  builder: (context) {
                    final query = _examSearchController.text.toLowerCase();
                    final filteredExams = _exams.where((e) {
                      final name = (e['name'] ?? '').toString().toLowerCase();
                      final type = (e['type'] ?? '').toString().toLowerCase();
                      return name.contains(query) || type.contains(query);
                    }).toList();

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: filteredExams.length,
                      itemBuilder: (context, index) {
                        final e = filteredExams[index];
                        final id = e['id'] as String;
                        final name = e['name'] as String? ?? '';
                        final type = e['type'] as String? ?? '';
                        final dateRaw = e['date'];
                        String dateStr = '';
                        if (dateRaw is Timestamp) dateStr = DateFormat('dd.MM.yyyy').format(dateRaw.toDate());

                        final isSelected = _selectedExamIds.contains(id);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.orange.shade50 : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isSelected ? Colors.orange.shade200 : Colors.grey.shade200),
                          ),
                          child: CheckboxListTile(
                            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('$type • $dateStr', style: const TextStyle(fontSize: 12)),
                            value: isSelected,
                            activeColor: Colors.orange.shade700,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedExamIds.add(id);
                                  _selectedExamNames.add(name);
                                } else {
                                  _selectedExamIds.remove(id);
                                  _selectedExamNames.remove(name);
                                }
                              });
                              setSt(() {});
                              _updateExamDersler();
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('Seçimi Tamamla'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Kamp Kurulumu', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.orange.shade700,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.meeting_room_outlined), onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => ClassroomManagementScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId, schoolTypeName: 'Kamp')));
            _loadData();
          }),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white, unselectedLabelColor: Colors.white60, indicatorColor: Colors.white,
          tabs: const [Tab(text: '1. Ayarlar'), Tab(text: '2. Saat Dilimleri'), Tab(text: '3. Özet')],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [_buildSettingsTab(), _buildSlotsTab(), _buildSummaryTab()],
          ),
          if (_isLoading)
            Container(
              color: Colors.black12,
              child: const Center(child: CircularProgressIndicator(color: Colors.orange)),
            ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Kamp Bilgileri', Icons.edit_note),
          const SizedBox(height: 12),
          TextFormField(controller: _titleController, decoration: _inputDecoration('Başlık (örn: Mart 1. Hafta Kampı)')),
          const SizedBox(height: 24),
          _sectionHeader('Referans Sınavlar', Icons.quiz_outlined),
          const SizedBox(height: 12),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _showExamSelectionDialog,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10), 
                  border: Border.all(color: Colors.grey.shade200)
                ),
                child: Row(children: [Expanded(child: Text(_selectedExamIds.isEmpty ? 'Sınav seçmek için dokunun' : _selectedExamNames.join(', '), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: _selectedExamIds.isEmpty ? Colors.grey : Colors.black87, fontSize: 13))), const Icon(Icons.search, color: Colors.orange)]),
              ),
            ),
          ),
          if (_selectedExamIds.isNotEmpty && _examDersler.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 4, children: _examDersler.values.map((d) => Chip(label: Text(d, style: const TextStyle(fontSize: 11)), backgroundColor: Colors.white, side: BorderSide(color: Colors.orange.shade200), visualDensity: VisualDensity.compact)).toList()),
          ],
          const SizedBox(height: 24),
          _sectionHeader('Tarih Aralığı', Icons.date_range),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: _buildDateButton(label: 'Başlangıç', date: _baslangic, onTap: () => _pickDate(true))), const SizedBox(width: 12), Expanded(child: _buildDateButton(label: 'Bitiş', date: _bitis, onTap: () => _pickDate(false)))]),
          const SizedBox(height: 24),
          _sectionHeader('Özel Sınıf Ayarı', Icons.star_border),
          const SizedBox(height: 8),
          SwitchListTile(title: const Text('Özel Sınıf Oluştur', style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text('En yüksek puanlı öğrenciler bu sınıfa atanır.'), value: _isSpecialClassActive, onChanged: (val) => setState(() => _isSpecialClassActive = val), activeColor: Colors.orange.shade700, contentPadding: EdgeInsets.zero),
          if (_isSpecialClassActive) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: TextFormField(controller: _specialCapacityController, keyboardType: TextInputType.number, decoration: _inputDecoration('Kapasite (Örn: 24)'))),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _classrooms.any((c) => c['id'] == _specialClassRoomId) ? _specialClassRoomId : null,
                    decoration: _inputDecoration('Derslik Seçin'),
                    isExpanded: true,
                    menuMaxHeight: 350,
                    items: _classrooms.map((c) => DropdownMenuItem<String>(value: c['id'] as String, child: Text(c['name'], style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (val) {
                      setState(() {
                        _specialClassRoomId = val;
                        _specialClassRoomName = _classrooms.firstWhere((c) => c['id'] == val)['name'];
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 32),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => _tabController.animateTo(1), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Sonraki: Saat Dilimleri →'))),
        ],
      ),
    );
  }

  Widget _buildSlotsTab() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    if (_loadingSlots) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        _buildSlotLibrary(),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(child: _buildSlotsHeader(isMobile)),
              _buildHeaderActionBtn(onPressed: _showAddSlotSheet, icon: Icons.add_circle_outline, label: 'Ekle', color: Colors.orange.shade700),
              const SizedBox(width: 8),
              _buildHeaderActionBtn(onPressed: _autoDistributeClassrooms, icon: Icons.auto_awesome, label: 'Oto Dağıt', color: Colors.teal),
            ],
          ),
        ),
        Expanded(
          child: _existingSlots.isEmpty
              ? _buildNoSlotsState()
              : () {
                  // Group existing slots by day for UI
                  final Map<String, List<CampTimeSlot>> groupedExisting = {};
                  for (var s in _existingSlots) {
                    groupedExisting.putIfAbsent(s.gun, () => []).add(s);
                  }

                  return ListView(
                    controller: _slotScrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: groupedExisting.entries.map((dayEntry) {
                      final day = dayEntry.key;
                      final slots = dayEntry.value;
                      // Sort slots by time
                      slots.sort((a, b) => a.baslangicSaat.compareTo(b.baslangicSaat));

                      return Card(
                        clipBehavior: Clip.antiAlias,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ExpansionTile(
                          shape: const Border(),
                          collapsedShape: const Border(),
                          initiallyExpanded: _expandedSlotId == day,
                          onExpansionChanged: (val) => setState(() => _expandedSlotId = val ? day : null),
                          leading: Icon(Icons.calendar_today, color: Colors.orange.shade700),
                          title: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(day, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text('${slots.length} Seans Planlandı', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  ],
                                ),
                              ),
                              TextButton.icon(
                                icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                                label: const Text('Şablonu Güncelle', style: TextStyle(fontSize: 11)),
                                onPressed: () => _saveDayToLibrary(day, slots),
                                style: TextButton.styleFrom(foregroundColor: Colors.blue, padding: EdgeInsets.zero, minimumSize: const Size(0, 30)),
                              ),
                            ],
                          ),
                          children: slots.map((slot) {
                            final idxInFullList = _existingSlots.indexOf(slot);
                            return Theme(
                              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                shape: const Border(),
                                collapsedShape: const Border(),
                                leading: const Icon(Icons.access_time, size: 18, color: Colors.orange),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${slot.ad} (${slot.baslangicSaat} - ${slot.bitisSaat})',
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                          ),
                                          const SizedBox(height: 2),
                                          Text('${slot.ogretmenGirisler.length} Atama Yapıldı', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                        ],
                                      ),
                                    ),
                                    if (isMobile)
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
                                        padding: EdgeInsets.zero,
                                        onSelected: (val) {
                                          if (val == 'add') _showAddTeacherEntrySheet(slot, idxInFullList);
                                          if (val == 'edit') _showEditSingleSlotSheet(slot, idxInFullList);
                                          if (val == 'delete') setState(() => _existingSlots.removeAt(idxInFullList));
                                        },
                                        itemBuilder: (ctx) => [
                                          const PopupMenuItem(value: 'add', child: Row(children: [Icon(Icons.add_circle_outline, size: 18, color: Colors.orange), SizedBox(width: 8), Text('Ders/Öğretmen Ekle', style: TextStyle(fontSize: 13))])),
                                          const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18, color: Colors.blue), SizedBox(width: 8), Text('Saati Düzenle', style: TextStyle(fontSize: 13))])),
                                          const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 8), Text('Kaldır', style: TextStyle(fontSize: 13))])),
                                        ]
                                      )
                                    else
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.add_circle_outline, size: 20, color: Colors.orange),
                                            onPressed: () => _showAddTeacherEntrySheet(slot, idxInFullList),
                                            tooltip: 'Ders/Öğretmen Ekle',
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.blue),
                                            onPressed: () => _showEditSingleSlotSheet(slot, idxInFullList),
                                            tooltip: 'Saati Düzenle',
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                            onPressed: () {
                                              setState(() => _existingSlots.removeAt(idxInFullList));
                                            },
                                            tooltip: 'Kaldır',
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                                children: [
                                  if (slot.ogretmenGirisler.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 32, right: 16, bottom: 12),
                                      child: Column(
                                        children: slot.ogretmenGirisler.map((entry) => Container(
                                          margin: const EdgeInsets.only(bottom: 6),
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade50,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: Colors.grey.shade200),
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(entry.dersAdi, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87)),
                                                    const SizedBox(height: 2),
                                                    Text('${entry.ogretmenAdi} • ${entry.derslikAdi ?? 'Derslik Seçilmedi'}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.edit, size: 16, color: Colors.orange),
                                                onPressed: () => _editTeacherEntry(slot, idxInFullList, entry),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.close, size: 16, color: Colors.red),
                                                onPressed: () => _removeTeacherEntry(slot, idxInFullList, entry),
                                              ),
                                            ],
                                          ),
                                        )).toList(),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    }).toList(),
                  );
                }(),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: () => _tabController.animateTo(0), child: const Text('← Geri'))),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(onPressed: () => _tabController.animateTo(2), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white), child: const Text('Özet →'))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSlotLibrary() {
    if (_allLibrarySlots.isEmpty) return const SizedBox.shrink();

    // Group slots by day
    final Map<String, List<CampTimeSlot>> grouped = {};
    for (var s in _allLibrarySlots) {
      grouped.putIfAbsent(s.gun, () => []).add(s);
    }

    final dayOrder = {'Pazartesi': 1, 'Salı': 2, 'Çarşamba': 3, 'Perşembe': 4, 'Cuma': 5, 'Cumartesi': 6, 'Pazar': 7};
    final sortedEntries = grouped.entries.toList()
      ..sort((a, b) {
        int orderA = dayOrder[a.key] ?? 100;
        int orderB = dayOrder[b.key] ?? 100;
        if (orderA == 100 && orderB == 100) return a.key.compareTo(b.key);
        return orderA.compareTo(orderB);
      });

    return Container(
      height: 50,
      color: Colors.white,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: sortedEntries.map((e) {
          final day = e.key;
          final slots = e.value;
          final isAlreadyAdded = slots.every((s) => _existingSlots.any((es) => es.id == s.id));

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onLongPress: () => _showLibraryTemplateOptions(day, slots),
              child: ActionChip(
                backgroundColor: isAlreadyAdded ? Colors.orange : Colors.orange.shade50,
                label: Text('$day (${slots.length} Seans)', style: TextStyle(fontSize: 11, color: isAlreadyAdded ? Colors.white : Colors.orange.shade800)),
                onPressed: () {
                  setState(() {
                    if (isAlreadyAdded) {
                      // REMOVE
                      _existingSlots.removeWhere((es) => slots.any((s) => s.id == es.id));
                    } else {
                      // ADD
                      for (var s in slots) {
                        if (!_existingSlots.any((es) => es.id == s.id)) {
                          _existingSlots.add(s);
                        }
                      }
                      // Scroll to top
                      Future.delayed(const Duration(milliseconds: 100), () {
                        if (_slotScrollController.hasClients) {
                          _slotScrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                        }
                      });
                    }
                  });
                },
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSlotsHeader(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Seçili Saat Dilimleri', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        Text('${_existingSlots.length} dilim aktif', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      ],
    );
  }

  Widget _buildHeaderActionBtn({required VoidCallback onPressed, required IconData icon, required String label, required Color color}) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
    );
  }

  Widget _buildNoSlotsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.schedule, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('Henüz saat dilimi yok', style: TextStyle(color: Colors.grey.shade500)),
          TextButton(onPressed: _showAddSlotSheet, child: const Text('İlk dilimi ekle')),
        ],
      ),
    );
  }

  Future<void> _saveDayToLibrary(String day, List<CampTimeSlot> currentSlots) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Şablonu Güncelle'),
        content: Text('Bu güne ( $day ) ait mevcut planlamanız (saatler ve öğretmenler) kütüphanedeki şablon olarak kaydedilecek. Eski şablon güncellenecektir. Onaylıyor musunuz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('İPTAL')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('KAYDET', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (confirm != true) return;
    setState(() => _isLoading = true);

    try {
      final oldLibrarySlots = _allLibrarySlots.where((s) => s.gun == day).toList();
      for (var old in oldLibrarySlots) {
        await _repo.deleteTimeSlot(old.id);
      }
      for (var current in currentSlots) {
        final templateSlot = CampTimeSlot(
          id: '', institutionId: widget.institutionId, ad: current.ad, gun: current.gun,
          baslangicSaat: current.baslangicSaat, bitisSaat: current.bitisSaat,
          ogretmenGirisler: current.ogretmenGirisler, isActive: true,
        );
        await _repo.createTimeSlot(templateSlot);
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$day şablonu kütüphanede güncellendi.')));
      await _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  final ScrollController _slotScrollController = ScrollController();

  void _showEditLibraryTemplateSheet(String oldDay, List<CampTimeSlot> oldSlots) {
    oldSlots.sort((a, b) => a.baslangicSaat.compareTo(b.baslangicSaat));
    int dersSayisi = oldSlots.length;
    List<TimeOfDay> startTimes = oldSlots.map((s) => TimeOfDay(hour: int.parse(s.baslangicSaat.split(':')[0]), minute: int.parse(s.baslangicSaat.split(':')[1]))).toList();
    List<TimeOfDay> endTimes = oldSlots.map((s) => TimeOfDay(hour: int.parse(s.bitisSaat.split(':')[0]), minute: int.parse(s.bitisSaat.split(':')[1]))).toList();
    String selectedGun = _gunler.contains(oldDay) ? oldDay : _gunler.first;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSt) {
          void recalculateFrom(int startIndex, {bool isStartChanged = true}) {
            for (int i = startIndex; i < dersSayisi; i++) {
              if (i == startIndex) {
                if (isStartChanged) {
                  final newEnd = DateTime(2000, 1, 1, startTimes[i].hour, startTimes[i].minute).add(const Duration(minutes: 40));
                  endTimes[i] = TimeOfDay(hour: newEnd.hour, minute: newEnd.minute);
                }
              } else {
                final prevEnd = DateTime(2000, 1, 1, endTimes[i - 1].hour, endTimes[i - 1].minute);
                final newStart = prevEnd.add(const Duration(minutes: 10));
                startTimes[i] = TimeOfDay(hour: newStart.hour, minute: newStart.minute);
                final newEnd = newStart.add(const Duration(minutes: 40));
                endTimes[i] = TimeOfDay(hour: newEnd.hour, minute: newEnd.minute);
              }
            }
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            child: Column(
              children: [
                const SizedBox(height: 12),
                const Text('Şablonu Düzenle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedGun,
                          decoration: _inputDecoration('Gün / Şablon Adı'),
                          items: _gunler.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                          onChanged: (v) => setSt(() => selectedGun = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Row(
                        children: [
                          IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red), onPressed: () => setSt(() { if (dersSayisi > 1) { dersSayisi--; startTimes.removeLast(); endTimes.removeLast(); } })),
                          Text('$dersSayisi Ders', style: const TextStyle(fontWeight: FontWeight.bold)),
                          IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.green), onPressed: () => setSt(() {
                            dersSayisi++;
                            final lastEnd = DateTime(2000, 1, 1, endTimes.last.hour, endTimes.last.minute);
                            final nextStart = lastEnd.add(const Duration(minutes: 10));
                            final nextEnd = nextStart.add(const Duration(minutes: 40));
                            startTimes.add(TimeOfDay(hour: nextStart.hour, minute: nextStart.minute));
                            endTimes.add(TimeOfDay(hour: nextEnd.hour, minute: nextEnd.minute));
                          })),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: dersSayisi,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          CircleAvatar(radius: 12, backgroundColor: Colors.orange.shade100, child: Text('${i + 1}', style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold))),
                          const SizedBox(width: 12),
                          Expanded(child: _buildTimePicker(ctx: context, label: 'Başlangıç', time: startTimes[i], onPicked: (t) => setSt(() { startTimes[i] = t; recalculateFrom(i, isStartChanged: true); }))),
                          const SizedBox(width: 8),
                          Expanded(child: _buildTimePicker(ctx: context, label: 'Bitiş', time: endTimes[i], onPicked: (t) => setSt(() { endTimes[i] = t; recalculateFrom(i, isStartChanged: false); }))),
                          IconButton(icon: const Icon(Icons.close, color: Colors.red, size: 18), onPressed: dersSayisi > 1 ? () => setSt(() { startTimes.removeAt(i); endTimes.removeAt(i); dersSayisi--; }) : null),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: ElevatedButton(
                    onPressed: () async {
                      setState(() => _isLoading = true);
                      try {
                        final newDay = selectedGun;
                        for (var old in oldSlots) { await _repo.deleteTimeSlot(old.id); }
                        for (int i = 0; i < dersSayisi; i++) {
                          List<CampSlotTeacherEntry> teachers = (i < oldSlots.length) ? oldSlots[i].ogretmenGirisler : [];
                          await _repo.createTimeSlot(CampTimeSlot(
                            id: '', institutionId: widget.institutionId, ad: '${newDay} ${i + 1}. Ders', gun: newDay,
                            baslangicSaat: startTimes[i].format(context), bitisSaat: endTimes[i].format(context),
                            ogretmenGirisler: teachers, isActive: true,
                          ));
                        }
                        if (oldDay != newDay) {
                           for (int i = 0; i < _existingSlots.length; i++) {
                             if (_existingSlots[i].gun == oldDay) {
                               _existingSlots[i] = _existingSlots[i].copyWith(gun: newDay);
                             }
                           }
                        }
                        Navigator.pop(ctx);
                        await _loadData();
                      } catch (e) {
                         if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red));
                      } finally {
                        if (mounted) setState(() => _isLoading = false);
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('Değişiklikleri Kaydet'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showLibraryTemplateOptions(String day, List<CampTimeSlot> slots) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Text('$day Şablonu', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.edit_outlined, color: Colors.blue),
            title: const Text('Şablon Adını Değiştir'),
            subtitle: const Text('Örn: Pazartesi -> Pazartesi Etüt'),
            onTap: () async {
              Navigator.pop(ctx);
              final nameC = TextEditingController(text: day);
              final newName = await showDialog<String>(
                context: context,
                builder: (d) => AlertDialog(
                  title: const Text('Şablonu Yeniden Adlandır'),
                  content: TextField(controller: nameC, decoration: _inputDecoration('Yeni Ad')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d), child: const Text('İPTAL')),
                    TextButton(onPressed: () => Navigator.pop(d, nameC.text), child: const Text('KAYDET')),
                  ],
                ),
              );
              if (newName != null && newName.isNotEmpty && newName != day) {
                setState(() => _isLoading = true);
                try {
                  for (var s in slots) {
                    await _repo.updateTimeSlot(s.copyWith(gun: newName));
                  }
                  // Sync in-memory active program
                  for (int i = 0; i < _existingSlots.length; i++) {
                    if (_existingSlots[i].gun == day) {
                      _existingSlots[i] = _existingSlots[i].copyWith(gun: newName);
                    }
                  }
                  await _loadData();
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red));
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined, color: Colors.orange),
            title: const Text('Şablonu Detaylı Düzenle'),
            subtitle: const Text('Ders sayısı ve saatleri toplu değiştir.'),
            onTap: () {
              Navigator.pop(ctx);
              _showEditLibraryTemplateSheet(day, slots);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Bu Şablonu Kütüphaneden Sil'),
            subtitle: const Text('Kütüphaneden kalıcı olarak kaldırılır.'),
            onTap: () async {
              Navigator.pop(ctx);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: const Text('Silme Onayı'),
                  content: Text('$day gününe ait ${slots.length} ders saati kütüphaneden silinecek. Onaylıyor musunuz?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('İPTAL')),
                    TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('SİL', style: TextStyle(color: Colors.red))),
                  ],
                ),
              );
              if (confirm == true) {
                setState(() => _isLoading = true);
                try {
                  final List<String> deletedIds = [];
                  for (var s in slots) {
                    await _repo.deleteTimeSlot(s.id);
                    deletedIds.add(s.id);
                  }
                  
                  // Aktif seçimlerden de kaldır
                  setState(() {
                    _existingSlots.removeWhere((es) => deletedIds.contains(es.id));
                  });

                  await _loadData();
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red));
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              }
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showSlotOptions(CampTimeSlot slot, int index) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Text(slot.ad, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.blue),
            title: const Text('Saatleri Düzenle'),
            onTap: () {
              Navigator.pop(ctx);
              _showEditSingleSlotSheet(slot, index);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Bu Saati Programdan Kaldır'),
            onTap: () {
              Navigator.pop(ctx);
              setState(() => _existingSlots.removeAt(index));
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showEditSingleSlotSheet(CampTimeSlot slot, int index) {
    TimeOfDay bas = TimeOfDay(hour: int.parse(slot.baslangicSaat.split(':')[0]), minute: int.parse(slot.baslangicSaat.split(':')[1]));
    TimeOfDay bit = TimeOfDay(hour: int.parse(slot.bitisSaat.split(':')[0]), minute: int.parse(slot.bitisSaat.split(':')[1]));
    final titleC = TextEditingController(text: slot.ad);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Saati Düzenle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(controller: titleC, decoration: _inputDecoration('Başlık')),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildTimePicker(ctx: context, label: 'Başlangıç', time: bas, onPicked: (t) => setState(() => bas = t))),
                const SizedBox(width: 12),
                Expanded(child: _buildTimePicker(ctx: context, label: 'Bitiş', time: bit, onPicked: (t) => setState(() => bit = t))),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _existingSlots[index] = slot.copyWith(
                    ad: titleC.text,
                    baslangicSaat: bas.format(context),
                    bitisSaat: bit.format(context),
                  );
                });
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Güncelle'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _copySlot(CampTimeSlot slot) {
    setState(() => _copiedEntries = List.from(slot.ogretmenGirisler));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kopyalandı')));
  }

  Future<void> _pasteSlot(CampTimeSlot slot, int index) async {
    if (_copiedEntries == null) return;
    final updated = [...slot.ogretmenGirisler, ..._copiedEntries!];
    await _repo.updateTimeSlotTeachers(slot.id, updated);
    setState(() => slot.ogretmenGirisler.addAll(_copiedEntries!));
  }

    void _showAddSlotSheet() {
    String selectedGun = _gunler.first;
    final templateNameCtrl = TextEditingController();
    int dersSayisi = 1;
    List<TimeOfDay> startTimes = [const TimeOfDay(hour: 9, minute: 0)];
    List<TimeOfDay> endTimes = [const TimeOfDay(hour: 9, minute: 40)];

    TimeOfDay addMinutes(TimeOfDay t, int mins) {
      final total = t.hour * 60 + t.minute + mins;
      return TimeOfDay(hour: (total ~/ 60) % 24, minute: total % 60);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSt) {
          void recalculateFrom(int index, {bool isStartChanged = true}) {
            if (isStartChanged) {
              endTimes[index] = addMinutes(startTimes[index], 40);
            }
            for (int i = index + 1; i < dersSayisi; i++) {
              startTimes[i] = addMinutes(endTimes[i - 1], 10);
              endTimes[i] = addMinutes(startTimes[i], 40);
            }
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Yeni Şablon Ekle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedGun,
                  decoration: _inputDecoration('Gün Seçin'),
                  items: _gunler.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                  onChanged: (v) => setSt(() => selectedGun = v!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: templateNameCtrl,
                  decoration: _inputDecoration('Şablon Adı (İsteğe bağlı)').copyWith(
                    hintText: 'Örn: Pazartesi Etüt',
                    helperText: 'Boş bırakırsanız seçili gün adı kullanılır.',
                    helperStyle: const TextStyle(fontSize: 10),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Seans Sayısı:', style: TextStyle(fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                          onPressed: dersSayisi > 1 ? () {
                            setSt(() {
                              dersSayisi--;
                              startTimes.removeLast();
                              endTimes.removeLast();
                            });
                          } : null,
                        ),
                        SizedBox(
                          width: 50,
                          child: TextFormField(
                            initialValue: dersSayisi.toString(),
                            key: ValueKey('dersCount_$dersSayisi'),
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(isDense: true),
                            onChanged: (v) {
                              final n = int.tryParse(v) ?? 1;
                              if (n > 0 && n < 15) {
                                setSt(() {
                                  dersSayisi = n;
                                  while (startTimes.length < n) {
                                    final lastEnd = endTimes.last;
                                    startTimes.add(addMinutes(lastEnd, 10));
                                    endTimes.add(addMinutes(startTimes.last, 40));
                                  }
                                  while (startTimes.length > n) {
                                    startTimes.removeLast();
                                    endTimes.removeLast();
                                  }
                                });
                              }
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                          onPressed: dersSayisi < 12 ? () {
                            setSt(() {
                              dersSayisi++;
                              final lastEnd = endTimes.last;
                              startTimes.add(addMinutes(lastEnd, 10));
                              endTimes.add(addMinutes(startTimes.last, 40));
                            });
                          } : null,
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(height: 32),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: dersSayisi,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          CircleAvatar(radius: 12, backgroundColor: Colors.orange.shade100, child: Text('${i + 1}', style: const TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold))),
                          const SizedBox(width: 12),
                          Expanded(child: _buildTimePicker(ctx: context, label: 'Başlangıç', time: startTimes[i], onPicked: (t) => setSt(() { startTimes[i] = t; recalculateFrom(i, isStartChanged: true); }))),
                          const SizedBox(width: 8),
                          Expanded(child: _buildTimePicker(ctx: context, label: 'Bitiş', time: endTimes[i], onPicked: (t) => setSt(() { endTimes[i] = t; recalculateFrom(i, isStartChanged: false); }))),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red, size: 18),
                            onPressed: dersSayisi > 1 ? () {
                              setSt(() {
                                startTimes.removeAt(i);
                                endTimes.removeAt(i);
                                dersSayisi--;
                              });
                            } : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    final finalTemplateName = templateNameCtrl.text.trim().isNotEmpty 
                        ? templateNameCtrl.text.trim() 
                        : selectedGun;
                    
                    setState(() => _saving = true);
                    for (int i = 0; i < dersSayisi; i++) {
                      final s = CampTimeSlot(
                        id: '',
                        institutionId: widget.institutionId,
                        ad: '$finalTemplateName ${i + 1}. Seans',
                        gun: finalTemplateName,
                        baslangicSaat: startTimes[i].format(context),
                        bitisSaat: endTimes[i].format(context),
                      );
                      final id = await _repo.createTimeSlot(s);
                      setState(() => _existingSlots.add(s.copyWith(id: id)));
                    }
                    setState(() => _saving = false);
                    Navigator.pop(ctx);
                    await _loadData();
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: Text('$dersSayisi Seansı Programa Ekle'),
                ),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAddTeacherEntrySheet(CampTimeSlot slot, int slotIndex) {
    if (_examDersler.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Önce Tab 1\'den bir sınav seçin. Ders listesi sınavdan otomatik gelir.'), backgroundColor: Colors.orange));
      return;
    }

    final Set<String> secilenDersIds = {};
    final Map<String, Set<String>> dersOgretmenMap = {};
    final Map<String, Map<String, dynamic>> extraInfo = {};

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: StatefulBuilder(
          builder: (_, setSt) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${slot.ad} – Planlama', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Ders seçin, öğretmen atayın ve her öğretmen için derslik belirleyin.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 16),
                const Text('1. Dersler', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                    },
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _examDersler.entries.map((e) {
                        final selected = secilenDersIds.contains(e.key);
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(e.value, style: const TextStyle(fontSize: 12)),
                            selected: selected, selectedColor: Colors.orange, checkmarkColor: Colors.white,
                            labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87),
                            onSelected: (on) {
                              setSt(() {
                                if (on) { secilenDersIds.add(e.key); dersOgretmenMap.putIfAbsent(e.key, () => {}); }
                                else { secilenDersIds.remove(e.key); dersOgretmenMap.remove(e.key); }
                              });
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                if (secilenDersIds.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text('2. Öğretmen & Derslik Atamaları', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 12),
                  ...secilenDersIds.map((dersId) {
                    final dersAdi = _examDersler[dersId] ?? dersId;
                    final selectedTeachers = dersOgretmenMap[dersId] ?? {};
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(dersAdi, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13)),
                          const SizedBox(height: 8),
                          ScrollConfiguration(
                            behavior: ScrollConfiguration.of(context).copyWith(
                              dragDevices: {
                                PointerDeviceKind.touch,
                                PointerDeviceKind.mouse,
                              },
                            ),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: _teachers.where((t) {
                                  // Filter: Branch must match and NOT be an admin
                                  final b = (t['branch'] ?? '').toString().toLowerCase();
                                  final d = dersAdi.toLowerCase();
                                  final role = (t['role'] ?? '').toString().toLowerCase();
                                  if (role == 'admin') return false;
                                  return b == d || d.contains(b) || b.contains(d);
                                }).map((t) {
                                  final tId = t['id'];
                                  final isSelected = selectedTeachers.contains(tId);
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: ChoiceChip(
                                      label: Text(t['name'], style: const TextStyle(fontSize: 11)),
                                      selected: isSelected, selectedColor: Colors.orange.shade100,
                                      onSelected: (on) {
                                        setSt(() {
                                          if (on) { selectedTeachers.add(tId); extraInfo['${dersId}_$tId'] = {'kapasite': 24, 'derslikId': null, 'derslikAdi': null}; }
                                          else { selectedTeachers.remove(tId); extraInfo.remove('${dersId}_$tId'); }
                                        });
                                      },
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                          if (selectedTeachers.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            ...selectedTeachers.map((tId) {
                              final tName = _teachers.firstWhere((t) => t['id'] == tId)['name'];
                              final info = extraInfo['${dersId}_$tId']!;
                              
                              // Sort classrooms for dropdown
                              final sortedRooms = List<Map<String, dynamic>>.from(_classrooms);
                              sortedRooms.sort((a, b) => _compareNatural(a['name'] ?? '', b['name'] ?? ''));

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Expanded(flex: 2, child: Text(tName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500))),
                                    const SizedBox(width: 8),
                                    SizedBox(width: 45, child: TextFormField(initialValue: info['kapasite'].toString(), keyboardType: TextInputType.number, decoration: _inputDecoration('Kap').copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 4)), style: const TextStyle(fontSize: 11), onChanged: (v) => info['kapasite'] = int.tryParse(v) ?? 24)),
                                    const SizedBox(width: 8),
                                    Expanded(flex: 3, child: DropdownButtonFormField<String>(
                                      value: _classrooms.any((c) => c['id'] == info['derslikId']) ? info['derslikId'] : null, hint: const Text('Derslik', style: TextStyle(fontSize: 10)), isExpanded: true,
                                      menuMaxHeight: 300,
                                      decoration: _inputDecoration('Derslik').copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 4)),
                                      items: [
                                        const DropdownMenuItem(value: null, child: Text('Seçilmedi', style: TextStyle(fontSize: 10))),
                                        ...sortedRooms.map((c) => DropdownMenuItem(value: c['id'] as String, child: Text(c['name'], style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis)))
                                      ],
                                      onChanged: (v) { setSt(() { info['derslikId'] = v; info['derslikAdi'] = v == null ? null : _classrooms.firstWhere((c) => c['id'] == v)['name']; }); },
                                    )),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                ],
                const SizedBox(height: 24),
                SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.auto_awesome, size: 18), onPressed: () {
                  final rooms = List<Map<String, dynamic>>.from(_classrooms);
                  rooms.sort((a, b) => _compareNatural(a['name']!, b['name']!));
                  final Set<String> occupied = {};
                  for (final e in slot.ogretmenGirisler) if (e.derslikId != null) occupied.add(e.derslikId!);
                  extraInfo.forEach((k, v) { if (v['derslikId'] != null) occupied.add(v['derslikId']!); });
                  setSt(() {
                    extraInfo.forEach((key, info) {
                      if (info['derslikId'] == null) {
                        for (final r in rooms) {
                          final rid = r['id']!;
                          if (!occupied.contains(rid)) { info['derslikId'] = rid; info['derslikAdi'] = r['name']; occupied.add(rid); break; }
                        }
                      }
                    });
                  });
                }, style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade50, foregroundColor: Colors.teal, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.teal.shade100))), label: const Text('Derslikleri Otomatik Dağıt', style: TextStyle(fontWeight: FontWeight.bold)))),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: ElevatedButton(
                  onPressed: secilenDersIds.isEmpty || dersOgretmenMap.values.every((v) => v.isEmpty) ? null : () async {
                    final List<CampSlotTeacherEntry> newEntries = [];
                    for (var dersId in secilenDersIds) {
                      final dersAdi = _examDersler[dersId] ?? dersId;
                      for (var tId in dersOgretmenMap[dersId]!) {
                        final tName = _teachers.firstWhere((t) => t['id'] == tId)['name'];
                        final info = extraInfo['${dersId}_$tId']!;
                        newEntries.add(CampSlotTeacherEntry(dersId: dersId, dersAdi: dersAdi, ogretmenId: tId, ogretmenAdi: tName, kapasite: info['kapasite'], derslikId: info['derslikId'], derslikAdi: info['derslikAdi']));
                      }
                    }
                    final updatedEntries = [...slot.ogretmenGirisler, ...newEntries];
                    await _repo.updateTimeSlotTeachers(slot.id, updatedEntries);
                    setState(() { _existingSlots[slotIndex] = slot.copyWith(ogretmenGirisler: updatedEntries); });
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text('Seçimleri Kaydet ve Ekle'),
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _removeTeacherEntry(CampTimeSlot slot, int slotIndex, CampSlotTeacherEntry entry) async {
    final updated = slot.ogretmenGirisler.where((e) => !(e.dersId == entry.dersId && e.ogretmenId == entry.ogretmenId)).toList();
    await _repo.updateTimeSlotTeachers(slot.id, updated);
    setState(() => _existingSlots[slotIndex] = slot.copyWith(ogretmenGirisler: updated));
  }

  Future<void> _autoDistributeClassrooms() async {
    if (_classrooms.isEmpty) return;
    final classroomList = List<Map<String, dynamic>>.from(_classrooms);
    classroomList.sort((a, b) => _compareNatural(a['name']!, b['name']!));
    final Map<String, Map<String, Set<String>>> usage = {};
    for (final slot in _existingSlots) {
      final slotKey = '${slot.baslangicSaat}-${slot.bitisSaat}';
      for (final entry in slot.ogretmenGirisler) if (entry.derslikId != null) usage.putIfAbsent(slot.gun, () => {}).putIfAbsent(slotKey, () => {}).add(entry.derslikId!);
    }
    final List<CampTimeSlot> updatedSlots = List.from(_existingSlots);
    for (int i = 0; i < updatedSlots.length; i++) {
      final slot = updatedSlots[i];
      final slotKey = '${slot.baslangicSaat}-${slot.bitisSaat}';
      final updatedEntries = List<CampSlotTeacherEntry>.from(slot.ogretmenGirisler);
      bool slotChanged = false;
      for (int j = 0; j < updatedEntries.length; j++) {
        final entry = updatedEntries[j];
        if (entry.derslikId == null) {
          for (final room in classroomList) {
            final rid = room['id']!;
            if (!(usage[slot.gun]?[slotKey]?.contains(rid) ?? false)) {
              updatedEntries[j].derslikId = rid;
              updatedEntries[j].derslikAdi = room['name'];
              usage.putIfAbsent(slot.gun, () => {}).putIfAbsent(slotKey, () => {}).add(rid);
              slotChanged = true;
              break;
            }
          }
        }
      }
      if (slotChanged) { updatedSlots[i] = slot.copyWith(ogretmenGirisler: updatedEntries); await _repo.updateTimeSlotTeachers(slot.id, updatedEntries); }
    }
    setState(() => _existingSlots = updatedSlots);
  }

  int _compareNatural(String a, String b) {
    final RegExp re = RegExp(r'(\d+)|\D+');
    final Iterable<Match> aMatch = re.allMatches(a.toLowerCase());
    final Iterable<Match> bMatch = re.allMatches(b.toLowerCase());
    final itA = aMatch.iterator; final itB = bMatch.iterator;
    while (itA.moveNext() && itB.moveNext()) {
      final aStr = itA.current.group(0)!; final bStr = itB.current.group(0)!;
      if (itA.current.group(1) != null && itB.current.group(1) != null) {
        final aNum = int.parse(aStr); final bNum = int.parse(bStr);
        if (aNum != bNum) return aNum.compareTo(bNum);
      } else { final cmp = aStr.compareTo(bStr); if (cmp != 0) return cmp; }
    }
    return a.length.compareTo(b.length);
  }

  Future<void> _editTeacherEntry(CampTimeSlot slot, int slotIndex, CampSlotTeacherEntry entry) async {
    String eOgretmenId = entry.ogretmenId;
    String eOgretmenAdi = entry.ogretmenAdi;
    String eDersId = entry.dersId;
    String eDersAdi = entry.dersAdi;
    int eKapasite = entry.kapasite;
    String? eDerslikId = entry.derslikId;
    String? eDerslikAdi = entry.derslikAdi;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSt) => AlertDialog(
          title: const Text('Grup Düzenle', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ders Seçimi
              DropdownButtonFormField<String>(
                value: _examDersler.containsKey(eDersId) ? eDersId : null,
                decoration: _inputDecoration('Ders'),
                items: _examDersler.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(),
                onChanged: (v) { 
                  if (v != null) {
                    setSt(() { 
                      eDersId = v; 
                      eDersAdi = _examDersler[v]!; 
                    }); 
                  }
                },
              ),
              const SizedBox(height: 12),
              // Öğretmen Seçimi
              DropdownButtonFormField<String>(
                value: _teachers.any((t) => t['id'] == eOgretmenId) ? eOgretmenId : null,
                decoration: _inputDecoration('Öğretmen'),
                items: _teachers.map((t) => DropdownMenuItem(value: t['id'] as String, child: Text(t['name'] as String, style: const TextStyle(fontSize: 12)))).toList(),
                onChanged: (v) { 
                  if (v != null) {
                    setSt(() { 
                      eOgretmenId = v; 
                      eOgretmenAdi = _teachers.firstWhere((t) => t['id'] == v)['name']; 
                      // Öğretmen değişince branşına göre dersi otomatik güncelle
                      final branchName = _teachers.firstWhere((t) => t['id'] == v)['branch']?.toString().trim() ?? '';
                      if (branchName.isNotEmpty) {
                        final matchingEntry = _examDersler.entries.where((e) => e.value.toLowerCase() == branchName.toLowerCase()).toList();
                        if (matchingEntry.isNotEmpty) {
                          eDersId = matchingEntry.first.key;
                          eDersAdi = matchingEntry.first.value;
                        } else {
                          // Eğer tanımlı dersler arasında yoksa branşın adını kullan
                          eDersId = branchName;
                          eDersAdi = branchName;
                        }
                      }
                    }); 
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(initialValue: eKapasite.toString(), keyboardType: TextInputType.number, decoration: _inputDecoration('Kapasite'), onChanged: (v) => eKapasite = int.tryParse(v) ?? 24),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _classrooms.any((c) => c['id'] == eDerslikId) ? eDerslikId : null, decoration: _inputDecoration('Derslik'),
                items: [const DropdownMenuItem(value: null, child: Text('Seçilmedi')), ..._classrooms.map((c) => DropdownMenuItem(value: c['id'] as String, child: Text(c['name'] as String)))],
                onChanged: (v) { setSt(() { eDerslikId = v; eDerslikAdi = v == null ? null : _classrooms.firstWhere((c) => c['id'] == v)['name']; }); },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
            ElevatedButton(onPressed: () async {
              final newEntry = CampSlotTeacherEntry(
                ogretmenId: eOgretmenId, 
                ogretmenAdi: eOgretmenAdi, 
                dersId: eDersId, 
                dersAdi: eDersAdi, 
                kapasite: eKapasite, 
                derslikId: eDerslikId, 
                derslikAdi: eDerslikAdi
              );
              // Eski entry'yi bulmak için orijinal dersId ve ogretmenId üzerinden eşleştiriyoruz
              final updated = slot.ogretmenGirisler.map((e) => (e.dersId == entry.dersId && e.ogretmenId == entry.ogretmenId) ? newEntry : e).toList();
              await _repo.updateTimeSlotTeachers(slot.id, updated);
              setState(() => _existingSlots[slotIndex] = slot.copyWith(ogretmenGirisler: updated));
              Navigator.pop(ctx);
            }, child: const Text('Kaydet')),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryTab() {
    final totalPlannedGroups = _existingSlots.fold(0, (sum, sl) => sum + sl.ogretmenGirisler.length);
    final totalPossibleSlots = _existingSlots.length; // Toplam seans sayısı

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _summaryCard('Kamp Başlığı', _titleController.text, Icons.edit_note),
          _summaryCard('Referans Sınavlar', _selectedExamNames.join(', '), Icons.quiz),
          _tappableStudentCard(),
          _summaryCard('Planlanan Seans Sayısı', '$totalPossibleSlots seans', Icons.access_time),
          _summaryCard('Planlanan Gruplar', '$totalPlannedGroups grup', Icons.group),
          
          const SizedBox(height: 24),
          _sectionHeader('Öğrenci Katılım Limitleri', Icons.tune),
          const SizedBox(height: 16),
          
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: (_minDers != null && _minDers! <= totalPossibleSlots) ? _minDers : null,
                  decoration: _inputDecoration('Minimum Seans'),
                  hint: const Text('Seçin'),
                  isExpanded: true,
                  menuMaxHeight: 300,
                  items: List.generate(totalPossibleSlots + 1, (index) => index)
                      .map((e) => DropdownMenuItem(value: e, child: Text('$e Seans'))).toList(),
                  onChanged: (val) => setState(() => _minDers = val),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: (_maxSaat != null && _maxSaat! <= totalPossibleSlots) ? _maxSaat : null,
                  decoration: _inputDecoration('Maksimum Seans'),
                  hint: const Text('Seçin'),
                  isExpanded: true,
                  menuMaxHeight: 300,
                  items: List.generate(totalPossibleSlots + 1, (index) => index)
                      .map((e) => DropdownMenuItem(value: e, child: Text('$e Seans'))).toList(),
                  onChanged: (val) => setState(() => _maxSaat = val),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 32),
          if (_saving) 
            const Center(child: CircularProgressIndicator())
          else 
            ElevatedButton(
              onPressed: _saveCycle,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600, 
                foregroundColor: Colors.white, 
                minimumSize: const Size(double.infinity, 54), 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
              ),
              child: const Text('KAYDET VE OLUŞTUR', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
            ),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, String val, IconData icon) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12), 
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: Colors.orange, size: 20),
        ),
        title: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500)), 
        subtitle: Text(val, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
      ),
    );
  }

  Widget _tappableStudentCard() {
    final activeCount = _potentialStudentCount - _excludedStudentIds.length;
    final hasExclusions = _excludedStudentIds.isNotEmpty;
    final valText = hasExclusions
        ? '$activeCount / $_potentialStudentCount öğrenci'
        : '$_potentialStudentCount öğrenci';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: hasExclusions ? Colors.orange.shade200 : Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _allBranchStudents.isEmpty ? null : _showStudentSelectionDialog,
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.person, color: Colors.orange, size: 20),
          ),
          title: Text('Kapsanan Öğrenci', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
          subtitle: Row(
            children: [
              Text(valText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
              if (hasExclusions) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(20)),
                  child: Text('${_excludedStudentIds.length} hariç', style: TextStyle(fontSize: 10, color: Colors.orange.shade800, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
          trailing: _allBranchStudents.isEmpty
              ? const SizedBox(width: 24)
              : Icon(Icons.chevron_right, color: Colors.orange.shade400),
        ),
      ),
    );
  }

  void _showStudentSelectionDialog() {
    final Set<String> tempExcluded = Set<String>.from(_excludedStudentIds);
    final searchCtrl = TextEditingController();
    String searchQuery = '';
    String? filterClassLevel;
    String? filterBranch;

    final Set<String> classLevels = {};
    final Set<String> branches = {};
    for (final s in _allBranchStudents) {
      final cl = (s['classLevel'] ?? s['sinifSeviyesi'] ?? '').toString();
      final br = (s['className'] ?? s['sube'] ?? '').toString();
      if (cl.isNotEmpty) classLevels.add(cl);
      if (br.isNotEmpty) branches.add(br);
    }
    final sortedClassLevels = classLevels.toList()..sort();
    final sortedBranches = branches.toList()..sort();

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (ctx, anim, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: FadeTransition(opacity: anim, child: child),
      ),
      pageBuilder: (ctx, _, __) => StatefulBuilder(
        builder: (ctx, setSt) {
          final filtered = _allBranchStudents.where((s) {
            final name = (s['fullName'] ?? s['name'] ?? '').toString().toLowerCase();
            final cl = (s['classLevel'] ?? s['sinifSeviyesi'] ?? '').toString();
            final br = (s['className'] ?? s['sube'] ?? '').toString();
            if (searchQuery.isNotEmpty && !name.contains(searchQuery.toLowerCase())) return false;
            if (filterClassLevel != null && cl != filterClassLevel) return false;
            if (filterBranch != null && br != filterBranch) return false;
            return true;
          }).toList();

          final activeCount = _allBranchStudents.length - tempExcluded.length;
          final excludedInFiltered = filtered.where((s) => tempExcluded.contains(s['id'])).length;
          final allFilteredSelected = filtered.isNotEmpty && excludedInFiltered == 0;

          return Scaffold(
            backgroundColor: const Color(0xFFF5F6FA),
            body: Column(
              children: [
                // ── Premium Başlık ──
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange.shade800, Colors.orange.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(color: Colors.orange.shade900.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 16, 20),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Kapsanan Öğrenciler', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
                                const SizedBox(height: 2),
                                Text(
                                  '$activeCount / ${_allBranchStudents.length} öğrenci seçili',
                                  style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          // İstatistik rozeti
                          if (tempExcluded.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withOpacity(0.4)),
                              ),
                              child: Text(
                                '${tempExcluded.length} hariç',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Arama & Filtreler ──
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    children: [
                      // Arama Çubuğu
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F6FA),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: TextField(
                          controller: searchCtrl,
                          onChanged: (v) => setSt(() => searchQuery = v),
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Öğrenci adı ara...',
                            hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                            prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey.shade400),
                            suffixIcon: searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.close, size: 18, color: Colors.grey.shade400),
                                    onPressed: () { searchCtrl.clear(); setSt(() => searchQuery = ''); },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Filtreler
                      Row(
                        children: [
                          Expanded(
                            child: _premiumDropdown<String>(
                              value: filterClassLevel,
                              hint: 'Sınıf Seviyesi',
                              icon: Icons.school_outlined,
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Tüm Seviyeler', style: TextStyle(fontSize: 13))),
                                ...sortedClassLevels.map((cl) => DropdownMenuItem(value: cl, child: Text('$cl. Sınıf', style: const TextStyle(fontSize: 13)))),
                              ],
                              onChanged: (v) => setSt(() { filterClassLevel = v; filterBranch = null; }),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _premiumDropdown<String>(
                              value: filterBranch,
                              hint: 'Şube',
                              icon: Icons.door_front_door_outlined,
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Tüm Şubeler', style: TextStyle(fontSize: 13))),
                                ...sortedBranches
                                  .where((br) => filterClassLevel == null || _allBranchStudents.any((s) =>
                                      (s['className'] ?? s['sube'] ?? '') == br &&
                                      (s['classLevel'] ?? s['sinifSeviyesi'] ?? '') == filterClassLevel))
                                  .map((br) => DropdownMenuItem(value: br, child: Text(br, style: const TextStyle(fontSize: 13)))),
                              ],
                              onChanged: (v) => setSt(() => filterBranch = v),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Toplu İşlem Çubuğu ──
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      // Tümünü seç checkbox
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setSt(() {
                          if (allFilteredSelected) {
                            for (final s in filtered) tempExcluded.add(s['id']);
                          } else {
                            for (final s in filtered) tempExcluded.remove(s['id']);
                          }
                        }),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 22, height: 22,
                              decoration: BoxDecoration(
                                color: allFilteredSelected ? Colors.orange.shade700 : Colors.transparent,
                                border: Border.all(color: allFilteredSelected ? Colors.orange.shade700 : Colors.grey.shade400, width: 2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: allFilteredSelected
                                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              allFilteredSelected ? 'Tümünü Kaldır' : 'Tümünü Seç',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${filtered.length} öğrenci',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, color: Color(0xFFEEEEEE)),

                // ── Öğrenci Listesi ──
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off, size: 48, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text('Öğrenci bulunamadı', style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final s = filtered[i];
                            final id = s['id'] as String;
                            final name = (s['fullName'] ?? s['name'] ?? 'İsimsiz').toString();
                            final cl = (s['classLevel'] ?? s['sinifSeviyesi'] ?? '').toString();
                            final br = (s['className'] ?? s['sube'] ?? '').toString();
                            final isIncluded = !tempExcluded.contains(id);

                            return AnimatedOpacity(
                              opacity: isIncluded ? 1.0 : 0.5,
                              duration: const Duration(milliseconds: 200),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isIncluded ? Colors.transparent : Colors.grey.shade200,
                                    width: 1,
                                  ),
                                  boxShadow: isIncluded
                                      ? [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))]
                                      : [],
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => setSt(() {
                                    if (isIncluded) tempExcluded.add(id);
                                    else tempExcluded.remove(id);
                                  }),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: Row(
                                      children: [
                                        // Avatar
                                        Container(
                                          width: 40, height: 40,
                                          decoration: BoxDecoration(
                                            color: isIncluded ? Colors.orange.shade50 : Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Center(
                                            child: Text(
                                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                                              style: TextStyle(
                                                fontSize: 16, fontWeight: FontWeight.bold,
                                                color: isIncluded ? Colors.orange.shade700 : Colors.grey.shade400,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // İsim & sınıf
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isIncluded ? const Color(0xFF1A1A2E) : Colors.grey.shade400)),
                                              const SizedBox(height: 3),
                                              Row(
                                                children: [
                                                  Icon(Icons.class_outlined, size: 12, color: isIncluded ? Colors.orange.shade400 : Colors.grey.shade300),
                                                  const SizedBox(width: 4),
                                                  Text('$cl. Sınıf  •  $br', style: TextStyle(fontSize: 11, color: isIncluded ? Colors.grey.shade500 : Colors.grey.shade300)),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Checkbox
                                        AnimatedContainer(
                                          duration: const Duration(milliseconds: 200),
                                          width: 24, height: 24,
                                          decoration: BoxDecoration(
                                            color: isIncluded ? Colors.orange.shade700 : Colors.transparent,
                                            border: Border.all(
                                              color: isIncluded ? Colors.orange.shade700 : Colors.grey.shade300,
                                              width: 2,
                                            ),
                                            borderRadius: BorderRadius.circular(7),
                                          ),
                                          child: isIncluded
                                              ? const Icon(Icons.check, size: 15, color: Colors.white)
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),

            // ── Floating Alt Bar + Uygula Butonu ──
            bottomNavigationBar: Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, -4))],
              ),
              child: Row(
                children: [
                  // İstatistik
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$activeCount öğrenci seçili',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E)),
                      ),
                      Text(
                        '${_allBranchStudents.length - activeCount} kapsam dışı',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Sıfırla
                  if (tempExcluded.isNotEmpty)
                    TextButton(
                      onPressed: () => setSt(() => tempExcluded.clear()),
                      child: Text('Sıfırla', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                    ),
                  const SizedBox(width: 8),
                  // Uygula Butonu
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() => _excludedStudentIds = Set<String>.from(tempExcluded));
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Uygula', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _premiumDropdown<T>({
    required T? value,
    required String hint,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.grey.shade500),
          hint: Row(
            children: [
              Icon(icon, size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 6),
              Text(hint, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
            ],
          ),
          items: items,
          onChanged: onChanged,
          menuMaxHeight: 300,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(children: [Icon(icon, size: 20, color: Colors.orange.shade700), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))]);
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label, 
      labelStyle: const TextStyle(fontSize: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)), 
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      filled: true,
      fillColor: Colors.white,
    );
  }

  Widget _buildDateButton({required String label, required DateTime date, required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)), const SizedBox(height: 4), Text(DateFormat('dd.MM.yyyy').format(date), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))]))),
    );
  }

  Future<void> _pickDate(bool isStart) async {
    final res = await showDatePicker(context: context, initialDate: isStart ? _baslangic : _bitis, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (res != null) setState(() { if (isStart) _baslangic = res; else _bitis = res; });
  }

  Widget _buildTimePicker({required BuildContext ctx, required String label, required TimeOfDay time, required Function(TimeOfDay) onPicked}) {
    return InkWell(onTap: () async { final t = await showTimePicker(context: ctx, initialTime: time); if (t != null) onPicked(t); }, child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)), const SizedBox(height: 4), Text(time.format(ctx), style: const TextStyle(fontWeight: FontWeight.bold))])));
  }

  Future<void> _saveCycle() async {
    if (_titleController.text.isEmpty || _selectedExamIds.isEmpty) return;
    setState(() => _saving = true);
    try {
      final cycle = CampCycle(
        id: widget.initialCycle?.id ?? '',
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
        title: _titleController.text,
        referansDenemeSinavId: _selectedExamIds.first,
        referansDenemeSinavAdi: _selectedExamNames.first,
        referansDenemeSinavIds: _selectedExamIds,
        referansDenemeSinavAdlari: _selectedExamNames,
        baslangicTarihi: _baslangic,
        bitisTarihi: _bitis,
        status: widget.initialCycle?.status ?? CampCycleStatus.draft,
        olusturulmaZamani: widget.initialCycle?.olusturulmaZamani ?? DateTime.now(),
        olusturanKullaniciId: widget.initialCycle?.olusturanKullaniciId ?? '',
        isSpecialClassActive: _isSpecialClassActive,
        specialClassCapacity: int.tryParse(_specialCapacityController.text) ?? 24,
        specialClassRoomId: _specialClassRoomId,
        specialClassRoomName: _specialClassRoomName,
        haftalikMaksimumSaat: _maxSaat,
        minimumDersSayisi: _minDers,
        excludedStudentIds: _excludedStudentIds.toList(),
      );

      final List<CampGroup> proposedGroups = [];
      for (final slot in _existingSlots) {
        for (final entry in slot.ogretmenGirisler) {
          proposedGroups.add(CampGroup(
            id: '',
            cycleId: cycle.id,
            institutionId: cycle.institutionId,
            dersId: entry.dersId,
            dersAdi: entry.dersAdi,
            saatDilimiId: slot.id,
            saatDilimiAdi: slot.ad,
            gun: slot.gun,
            baslangicSaat: slot.baslangicSaat,
            bitisSaat: slot.bitisSaat,
            ogretmenId: entry.ogretmenId,
            ogretmenAdi: entry.ogretmenAdi,
            derslikId: entry.derslikId,
            derslikAdi: entry.derslikAdi,
            kapasite: entry.kapasite,
            mevcutOgrenciSayisi: 0,
          ));
        }
      }

      await _service.saveCycle(cycle: cycle, proposedGroups: proposedGroups);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
