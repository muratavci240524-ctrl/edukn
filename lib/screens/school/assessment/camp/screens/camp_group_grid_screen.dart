import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../evaluation_models.dart';
import '../models/camp_cycle_model.dart';
import '../models/camp_group_model.dart';
import '../models/camp_assignment_model.dart';
import '../repository/camp_repository.dart';
import '../services/camp_service.dart';
import '../services/camp_assignment_engine.dart';
import 'camp_reports_screen.dart';
import 'camp_student_timetable_screen.dart';
import 'camp_teacher_timetable_screen.dart';
import 'camp_classroom_timetable_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/camp_assignment_log_model.dart';

class CampGroupGridScreen extends StatefulWidget {
  final CampCycle cycle;

  const CampGroupGridScreen({Key? key, required this.cycle}) : super(key: key);

  @override
  State<CampGroupGridScreen> createState() => _CampGroupGridScreenState();
}

class _CampGroupGridScreenState extends State<CampGroupGridScreen> with SingleTickerProviderStateMixin {
  final _service = CampService();
  final _repo = CampRepository();
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  late TabController _tabController;

  List<CampGroup> _groups = [];
  Map<String, List<CampAssignment>> _assignmentsByGroup = {};
  List<Map<String, dynamic>> _allBranchStudents = [];
  int _totalPotentialStudents = 0;

  List<String> _unassignedStudents = [];
  List<String> _underAssignedStudents = [];
  List<Map<String, dynamic>> _absentStudents = [];
  Map<String, List<String>> _unassignedReasons = {};
  
  final Set<String> _selectedStudentIds = {};

  bool _loading = true;
  bool _generating = false;
  bool _publishing = false;
  String? _groupFilterBranch;
  Set<String>? _selectedTimeSlots;
  String? _selectedSlotFilter;
  int _yerlesmeyenFilterIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    final cycleDoc = await _db.collection('camp_cycles').doc(widget.cycle.id).get();
    CampCycle currentCycle = widget.cycle;
    if (cycleDoc.exists) {
      currentCycle = CampCycle.fromMap(cycleDoc.data()!, cycleDoc.id);
    }

    final groups = await _repo.getGroupsByCycle(widget.cycle.id);
    final snap = await _db.collection('camp_assignments').where('cycleId', isEqualTo: widget.cycle.id).get();
    final assignments = snap.docs.map((d) => CampAssignment.fromMap(d.data(), d.id)).toList();

    final Map<String, List<CampAssignment>> byGroup = {};
    for (var g in groups) byGroup[g.id] = [];
    for (var a in assignments) byGroup.putIfAbsent(a.groupId, () => []).add(a);

    if (mounted) {
      setState(() {
        _groups = groups;
        _assignmentsByGroup = byGroup;
        _unassignedStudents = currentCycle.unassignedStudentIds;
        _underAssignedStudents = currentCycle.underAssignedStudentIds;
        _unassignedReasons = currentCycle.unassignedReasons;
        _loading = false;
      });
      await _loadBranchStudentsForCycle(currentCycle);
      _calculateAbsentStudents(currentCycle);
    }
  }

  void _calculateAbsentStudents(CampCycle cycle) {
    setState(() {
      _absentStudents = _allBranchStudents
          .where((s) => cycle.absentStudentIds.contains(s['id']))
          .map((s) => {
                'id': s['id'],
                'name': (s['fullName'] ?? s['name'] ?? 'İsimsiz').toString(),
                'branch': (s['className'] ?? s['branch'] ?? '').toString(),
                'subeId': s['branchId'] ?? '',
              })
          .toList();
    });
  }

  Future<void> _loadBranchStudentsForCycle(CampCycle cycle) async {
    try {
      final List<String> examIds = cycle.referansDenemeSinavIds.isNotEmpty ? cycle.referansDenemeSinavIds : [cycle.referansDenemeSinavId];
      final List<Map<String, dynamic>> branchStudents = [];
      final Set<String> processedStudentIds = {};

      for (final examId in examIds) {
        final examDoc = await _db.collection('trial_exams').doc(examId).get();
        if (!examDoc.exists) continue;

        final examData = examDoc.data()!;
        final selectedBranches = (examData['selectedBranches'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
        final classLevel = examData['classLevel']?.toString() ?? '';

        if (selectedBranches.isNotEmpty) {
          for (final branch in selectedBranches) {
            final snap = await _db.collection('students').where('institutionId', isEqualTo: cycle.institutionId).where('className', isEqualTo: branch).where('isActive', isEqualTo: true).get();
            for (final doc in snap.docs) {
              if (processedStudentIds.contains(doc.id)) continue;
              processedStudentIds.add(doc.id);
              branchStudents.add({'id': doc.id, ...doc.data()});
            }
          }
        } else if (classLevel.isNotEmpty) {
          final snap = await _db.collection('students').where('institutionId', isEqualTo: cycle.institutionId).where('classLevel', isEqualTo: classLevel).where('isActive', isEqualTo: true).get();
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
          _totalPotentialStudents = branchStudents.length;
        });
      }
    } catch (e) { print('Öğrenci yükleme hatası: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDraft = widget.cycle.status == CampCycleStatus.draft;
    final bool isPublished = widget.cycle.status == CampCycleStatus.published;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(widget.cycle.title ?? 'Kamp Grupları', style: const TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: Colors.orange.shade700,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (val) {
              if (val == 'reset') _confirmResetDraft();
              if (val == 'publish') _publish();
              if (val == 'unpublish') _unpublish();
            },
            itemBuilder: (context) => [
              if (isDraft)
                PopupMenuItem(
                  value: 'publish',
                  child: Row(
                    children: [
                      Icon(Icons.publish, size: 20, color: Colors.green.shade700),
                      const SizedBox(width: 12),
                      const Text('Yayınla (Etüt Oluştur)'),
                    ],
                  ),
                ),
              if (isPublished)
                PopupMenuItem(
                  value: 'unpublish',
                  child: Row(
                    children: [
                      Icon(Icons.cancel_presentation, size: 20, color: Colors.red.shade700),
                      const SizedBox(width: 12),
                      const Text('Yayından Kaldır'),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'reset',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep, size: 20, color: Colors.red.shade400),
                    const SizedBox(width: 12),
                    const Text('Dağıtımı Sıfırla'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontSize: 13),
          tabs: [
            const Tab(text: 'Gruplar'),
            Tab(child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Yerleşemeyenler'),
                if ((_unassignedStudents.length + _underAssignedStudents.length + _absentStudents.length) > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)),
                    child: Text('${_unassignedStudents.length + _underAssignedStudents.length + _absentStudents.length}', 
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ]
              ]),
            )),
            const Tab(text: 'Raporlar'),
          ],
        ),
      ),
      body: _loading 
        ? const Center(child: CircularProgressIndicator())
        : TabBarView(
            controller: _tabController,
            children: [
              _buildGroupsTab(),
              _buildYerlesmeyenTab(),
              _buildReportsTab(),
            ],
          ),
      bottomNavigationBar: _selectedStudentIds.isNotEmpty ? _buildBulkActionBar() : null,
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          if (_selectedStudentIds.isNotEmpty) return const SizedBox.shrink();

          if (_tabController.index == 0 && isDraft) {
            return FloatingActionButton.extended(
              onPressed: _generating ? null : _showGenerateDraftSheet,
              label: Text(_generating ? 'Dağıtılıyor...' : 'Dağıtım Yap'),
              icon: _generating 
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                : const Icon(Icons.auto_awesome),
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
            );
          }

          if (_tabController.index == 1 && isDraft) {
             String filterName = 'Sınava Girmeyenleri';
             if (_yerlesmeyenFilterIndex == 1) filterName = 'Atanamayanları';
             if (_yerlesmeyenFilterIndex == 2) filterName = 'Eksik Atananları';

             final isMobile = MediaQuery.of(context).size.width < 600;

             if (isMobile) {
               return FloatingActionButton(
                 onPressed: _loading ? null : _confirmAutoAssign,
                 backgroundColor: Colors.teal,
                 child: const Icon(Icons.bolt, color: Colors.white),
               );
             }

             return FloatingActionButton.extended(
               onPressed: _loading ? null : _confirmAutoAssign,
               label: Text('$filterName Otomatik Ata'),
               icon: const Icon(Icons.bolt),
               backgroundColor: Colors.teal,
               foregroundColor: Colors.white,
             );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  // ─── MANUEL İŞLEMLER ──────────────────────────────────────────────────────

  void _confirmResetDraft() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(ctx).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
              child: Icon(Icons.delete_sweep_rounded, color: Colors.red.shade600, size: 32),
            ),
            const SizedBox(height: 16),
            const Text('Dağıtımı Sıfırla', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 8),
            const Text('Mevcut tüm öğrenci atamaları, grup dolulukları ve istatistikler kalıcı olarak silinecektir. Bu işlem geri alınamaz.', 
              textAlign: TextAlign.center, 
              style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.5)),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: const Text('Vazgeç', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      setState(() => _loading = true);
                      try {
                        await _repo.rollbackAssignments(widget.cycle.id);
                        final groups = await _repo.getGroupsByCycle(widget.cycle.id);
                        final resetGroups = groups.map((g) => g.copyWith(mevcutOgrenciSayisi: 0, kazanimlar: [])).toList();
                        await _repo.batchUpdateGroups(resetGroups);
                        await _db.collection('camp_cycles').doc(widget.cycle.id).update({
                          'unassignedStudentIds': [], 
                          'underAssignedStudentIds': [], 
                          'absentStudentIds': [], 
                          'unassignedReasons': {}
                        });
                        await _loadData();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tüm atamalar sıfırlandı.'), backgroundColor: Colors.green));
                      } catch (e) { 
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red)); 
                        setState(() => _loading = false);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Sıfırla ve Temizle', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _publish() async {
    final assignments = _assignmentsByGroup.values.expand((element) => element).toList();
    if (assignments.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Atama yapılmamış bir döngü yayınlanamaz.'))); return; }
    setState(() => _publishing = true);
    try {
      await _service.publishCycle(cycle: widget.cycle, gruplar: _groups, atamalar: assignments);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kamp programı başarıyla yayınlandı ve etütler oluşturuldu!'), backgroundColor: Colors.green));
      await _loadData();
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Yayınlama hatası: $e'), backgroundColor: Colors.red)); } finally { setState(() => _publishing = false); }
  }

  Future<void> _unpublish() async {
    setState(() => _publishing = true);
    try {
      await _service.unpublishCycle(widget.cycle.id);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kamp programı yayından kaldırıldı ve ilgili etütler silindi.')));
      await _loadData();
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Yayından kaldırma hatası: $e'), backgroundColor: Colors.red)); } finally { setState(() => _publishing = false); }
  }

  void _removeAssignments(List<CampAssignment> list) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gruptan Çıkar'),
        content: Text('${list.length} öğrenciyi gruptan çıkarmak istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _loading = true);
              await _service.removeAssignments(list);
              _selectedStudentIds.clear();
              await _loadData();
            },
            child: const Text('Çıkar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showMoveDialog(List<CampAssignment> assignments) {
    if (assignments.isEmpty) return;
    final firstAssign = assignments.first;
    final currentGroup = _groups.firstWhere((g) => g.id == firstAssign.groupId);
    final otherGroupsInSlot = _groups.where((g) => g.id != currentGroup.id && g.baslangicSaat == currentGroup.baslangicSaat && g.gun == currentGroup.gun).toList();

    if (otherGroupsInSlot.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aynı saat diliminde başka grup bulunamadı.')));
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Grubu Değiştir'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: otherGroupsInSlot.map((g) => ListTile(
              title: Text(g.dersAdi),
              subtitle: Text('${g.ogretmenAdi} (${g.mevcutOgrenciSayisi}/${g.kapasite})'),
              onTap: () async {
                Navigator.pop(ctx);
                setState(() => _loading = true);
                await _service.moveAssignments(assignments, g.id, '${g.dersAdi} - ${g.ogretmenAdi}');
                _selectedStudentIds.clear();
                await _loadData();
              },
            )).toList(),
          ),
        ),
      ),
    );
  }

  void _showSwapGroupDialog(CampGroup groupA) {
    final sameSlotAndBranchGroups = _groups.where((g) => 
      g.id != groupA.id && 
      g.baslangicSaat == groupA.baslangicSaat && 
      g.gun == groupA.gun &&
      (g.dersId == groupA.dersId || g.dersAdi == groupA.dersAdi)
    ).toList();

    if (sameSlotAndBranchGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Aynı saatte "${groupA.dersAdi}" branşında başka grup bulunamadı.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 24),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.swap_horiz, color: Colors.orange),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Grup Takası', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                      Text('Öğrenci kitlelerini karşılıklı değiştirin', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('"${groupA.dersAdi}" branşı için "${groupA.ogretmenAdi}" grubundaki öğrencileri kiminle takas etmek istersiniz?', 
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4)),
            const SizedBox(height: 20),
            ...sameSlotAndBranchGroups.map((groupB) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
                color: Colors.grey.shade50.withOpacity(0.5),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: CircleAvatar(
                  backgroundColor: Colors.orange,
                  radius: 18,
                  child: const Icon(Icons.person, color: Colors.white, size: 20),
                ),
                title: Text(groupB.ogretmenAdi, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                subtitle: Text('${groupB.mevcutOgrenciSayisi} öğrenci • ${groupB.derslikAdi ?? "Derslik belirtilmedi"}', style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, color: Colors.orange),
                onTap: () async {
                  Navigator.pop(ctx);
                  setState(() => _loading = true);
                  await _service.swapGroups(groupA, groupB, _assignmentsByGroup[groupA.id] ?? [], _assignmentsByGroup[groupB.id] ?? []);
                  await _loadData();
                },
              ),
            )).toList(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showManualAssignDialog(Map<String, dynamic> student, {List<CampGroup>? slotGroups}) {
    final studentId = student['id'] as String;
    final assignedSlots = <String>{};
    for (final entry in _assignmentsByGroup.entries) {
      if (entry.value.any((a) => a.ogrenciId == studentId)) {
        final g = _groups.firstWhere((g) => g.id == entry.key);
        assignedSlots.add('${g.baslangicSaat}-${g.gun}');
      }
    }

    if (widget.cycle.haftalikMaksimumSaat != null && assignedSlots.length >= widget.cycle.haftalikMaksimumSaat!) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Bu öğrenci maksimum seans limitine (${widget.cycle.haftalikMaksimumSaat}) ulaştı.'), backgroundColor: Colors.orange));
      return;
    }

    final availableGroups = slotGroups ?? _groups.where((g) => !assignedSlots.contains('${g.baslangicSaat}-${g.gun}')).toList();
    if (availableGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bu öğrenci için uygun grup bulunamadı.')));
      return;
    }

    final branches = availableGroups.map((g) => g.dersAdi).toSet().toList()..sort();
    String? selectedBranch;
    CampGroup? selectedGroup;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filteredGroups = selectedBranch == null 
              ? <CampGroup>[] 
              : availableGroups.where((g) => g.dersAdi == selectedBranch).toList();

          return AlertDialog(
            title: Text('${student['name']?.toString() ?? "İsimsiz"} - Manuel Ata', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Branş Seçin', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: selectedBranch,
                    underline: const SizedBox(),
                    hint: const Text('Branş Seçiniz'),
                    items: branches.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                    onChanged: (val) {
                      setDialogState(() {
                        selectedBranch = val;
                        selectedGroup = null;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Grup Seçin', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                  child: DropdownButton<CampGroup>(
                    isExpanded: true,
                    value: selectedGroup,
                    underline: const SizedBox(),
                    hint: const Text('Grup Seçiniz'),
                    items: filteredGroups.map((g) {
                      final isFull = g.mevcutOgrenciSayisi >= g.kapasite;
                      return DropdownMenuItem(
                        value: g, 
                        child: Text('${g.ogretmenAdi} (${g.mevcutOgrenciSayisi}/${g.kapasite})', 
                          style: TextStyle(color: isFull ? Colors.red : Colors.black87))
                      );
                    }).toList(),
                    onChanged: (val) {
                      setDialogState(() => selectedGroup = val);
                    },
                  ),
                ),
                if (selectedGroup != null && selectedGroup!.mevcutOgrenciSayisi >= selectedGroup!.kapasite)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 16),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('Dikkat: Grup kapasitesi dolu! Yine de atama yapılacak.', style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
              ElevatedButton(
                onPressed: selectedGroup == null ? null : () async {
                  bool confirm = true;
                  if (selectedGroup!.mevcutOgrenciSayisi >= selectedGroup!.kapasite) {
                    confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Kapasite Aşımı'),
                        content: const Text('Seçtiğiniz grup dolu. Yine de bu öğrenciyi bu gruba eklemek istiyor musunuz?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hayır')),
                          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Evet, Devam Et')),
                        ],
                      )
                    ) ?? false;
                  }

                  if (confirm) {
                    Navigator.pop(ctx);
                    setState(() => _loading = true);
                    await _service.manualAssign(
                      cycleId: widget.cycle.id,
                      ogrenciId: studentId,
                      ogrenciAdi: student['name']?.toString() ?? 'İsimsiz',
                      subeId: student['subeId'] ?? '',
                      subeAdi: student['branch']?.toString() ?? '',
                      yeniGrupId: selectedGroup!.id,
                      yeniGrupAdi: '${selectedGroup!.dersAdi} - ${selectedGroup!.ogretmenAdi}',
                      isAbsent: _yerlesmeyenFilterIndex == 0,
                    );
                    
                    // Yerel güncellemeler
                    setState(() {
                      _unassignedStudents.remove(studentId);
                      _underAssignedStudents.remove(studentId);
                      _absentStudents.removeWhere((s) => s['id'] == studentId);
                    });
                    
                    await _loadData();
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                child: const Text('Atamayı Onayla'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmAutoAssign() async {
    int count = 0;
    String filterName = 'Sınava girmeyenleri';
    if (_yerlesmeyenFilterIndex == 0) {
      count = _absentStudents.length;
      filterName = 'sınava girmeyen';
    } else if (_yerlesmeyenFilterIndex == 1) {
      count = _unassignedStudents.length;
      filterName = 'atanamayan';
    } else if (_yerlesmeyenFilterIndex == 2) {
      count = _underAssignedStudents.length;
      filterName = 'eksik atanan';
    }

    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bu kategoride atanacak öğrenci yok.')));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Otomatik Atama Onayı'),
        content: Text('$count $filterName öğrenciye otomatik atama yapılacaktır. Onaylıyor musunuz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            child: const Text('Onayla'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _autoAssignAllInCurrentFilter();
    }
  }

  Future<void> _autoAssignAllInCurrentFilter() async {
    setState(() => _loading = true);

    try {
      List<Map<String, dynamic>> targetStudents = [];
      if (_yerlesmeyenFilterIndex == 0) {
        targetStudents = _absentStudents;
      } else if (_yerlesmeyenFilterIndex == 1) {
        targetStudents = _unassignedStudents.map((id) {
          final s = _allBranchStudents.firstWhere((s) => s['id'] == id, orElse: () => {'id': id, 'fullName': 'Yükleniyor...'});
          return {
            'id': id,
            'name': (s['fullName'] ?? s['name'] ?? 'İsimsiz').toString(),
            'branch': (s['className'] ?? s['branch'] ?? '').toString(),
            'subeId': s['branchId'] ?? '',
          };
        }).toList();
      } else if (_yerlesmeyenFilterIndex == 2) {
         targetStudents = _underAssignedStudents.map((id) {
          final s = _allBranchStudents.firstWhere((s) => s['id'] == id, orElse: () => {'id': id, 'fullName': 'Yükleniyor...'});
          return {
            'id': id,
            'name': (s['fullName'] ?? s['name'] ?? 'İsimsiz').toString(),
            'branch': (s['className'] ?? s['branch'] ?? '').toString(),
            'subeId': s['branchId'] ?? '',
          };
        }).toList();
      }

      if (targetStudents.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      int atamaYapilanSayisi = 0;
      final List<String> processedStudentIds = [];
      final batch = _db.batch();
      final cycleRef = _db.collection('camp_cycles').doc(widget.cycle.id);

      // Load actual student profiles for target students
      final allStudents = await _fetchStudentsForCycle();
      final targetIds = targetStudents.map((s) => s['id'] as String).toSet();
      final targetFullStudents = allStudents.where((s) => targetIds.contains(s['id'])).toList();
      
      final Set<String> allStudentsWhoEnteredExam = {};
      final profiles = await _createStudentNeedProfiles(targetFullStudents, (sid) => allStudentsWhoEnteredExam.add(sid));

      for (final student in targetStudents) {
        final studentId = student['id'] as String;
        final profile = profiles.firstWhere((p) => p.ogrenciId == studentId, orElse: () => StudentNeedProfile(ogrenciId: studentId, ogrenciAdi: student['name'] ?? 'İsimsiz', subeId: student['subeId'] ?? '', subeAdi: student['branch'] ?? '', dersIhtiyaclari: {}));
        final actualSube = profile.subeAdi.isNotEmpty ? profile.subeAdi : (student['branch'] ?? '');
        final assignedGroupIds = _assignmentsByGroup.entries
            .where((e) => e.value.any((a) => a.ogrenciId == studentId))
            .map((e) => e.key)
            .toSet();

        final assignedSubjects = <String>{};
        final occupiedTimeSlots = <String>{};

        for (final grup in _groups) {
          if (assignedGroupIds.contains(grup.id)) {
            assignedSubjects.add(grup.dersAdi);
            occupiedTimeSlots.add('${grup.baslangicSaat}-${grup.gun}');
          }
        }

        final prioritizedGroups = List<CampGroup>.from(_groups)
          ..sort((a, b) => _getGroupSuccessAvg(a.id).compareTo(_getGroupSuccessAvg(b.id)));

        int studentAtamaSayisi = 0;
        void attemptAssignment({required bool allowDuplicateSubject}) {
          for (final grup in prioritizedGroups) {
            if (grup.isSpecial) continue; // Skip special classes for unassigned/absent auto-assigner
            if (widget.cycle.haftalikMaksimumSaat != null && occupiedTimeSlots.length >= widget.cycle.haftalikMaksimumSaat!) break;
            if (!allowDuplicateSubject && assignedSubjects.contains(grup.dersAdi)) continue; 
            if (occupiedTimeSlots.contains('${grup.baslangicSaat}-${grup.gun}')) continue; 

            final currentAssigns = _assignmentsByGroup[grup.id] ?? [];
            if (currentAssigns.length < grup.kapasite) {
              if (assignedGroupIds.contains(grup.id)) continue;

              final actualBasari = profile.dersBasariOranlari[grup.dersId] ?? profile.dersBasariOranlari[grup.dersAdi] ?? 0.5;

              final assignRef = _db.collection('camp_assignments').doc();
              batch.set(assignRef, CampAssignment(
                id: assignRef.id, 
                cycleId: widget.cycle.id, 
                groupId: grup.id, 
                ogrenciId: studentId, 
                ogrenciAdi: student['name'] ?? 'İsimsiz', 
                sube: actualSube,
                subeId: student['subeId'] ?? '',
                groupName: '${grup.dersAdi} - ${grup.ogretmenAdi}', 
                basariOrani: actualBasari, 
              ).toMap());

              // Log
              final logRef = _db.collection('camp_assignment_logs').doc();
              batch.set(logRef, CampAssignmentLog(
                id: logRef.id, cycleId: widget.cycle.id, institutionId: widget.cycle.institutionId,
                ogrenciId: studentId, ogrenciAdi: student['name'] ?? 'İsimsiz',
                yeniGrupId: grup.id, yeniGrupAdi: '${grup.dersAdi} - ${grup.ogretmenAdi}',
                yapanKullaniciId: _auth.currentUser?.uid ?? '', yapanKullaniciAdi: _auth.currentUser?.displayName ?? 'Admin', tarih: DateTime.now()
              ).toMap());

              atamaYapilanSayisi++;
              studentAtamaSayisi++;
              
              _assignmentsByGroup.putIfAbsent(grup.id, () => []);
              _assignmentsByGroup[grup.id]!.add(CampAssignment(
                id: assignRef.id, 
                cycleId: widget.cycle.id, 
                groupId: grup.id, 
                ogrenciId: studentId, 
                ogrenciAdi: student['name'] ?? 'İsimsiz', 
                sube: actualSube,
                subeId: student['subeId'] ?? '',
                groupName: '${grup.dersAdi} - ${grup.ogretmenAdi}', 
                basariOrani: actualBasari, 
              ));
              
              occupiedTimeSlots.add('${grup.baslangicSaat}-${grup.gun}');
              assignedSubjects.add(grup.dersAdi);
              assignedGroupIds.add(grup.id);
            }
          }
        }

        attemptAssignment(allowDuplicateSubject: false);
        if (_yerlesmeyenFilterIndex == 2 || (widget.cycle.minimumDersSayisi != null && occupiedTimeSlots.length < widget.cycle.minimumDersSayisi!)) {
          attemptAssignment(allowDuplicateSubject: true);
        }
        
        if (studentAtamaSayisi > 0) {
          processedStudentIds.add(studentId);
          // Firestore listelerinden kaldır
          batch.update(cycleRef, {
            'unassignedStudentIds': FieldValue.arrayRemove([studentId]),
            'underAssignedStudentIds': FieldValue.arrayRemove([studentId]),
            'absentStudentIds': FieldValue.arrayRemove([studentId]),
          });
        }
      }

      if (atamaYapilanSayisi > 0) {
        await batch.commit();
      }

      setState(() {
        _absentStudents.removeWhere((s) => processedStudentIds.contains(s['id']));
        _unassignedStudents.removeWhere((id) => processedStudentIds.contains(id));
        _underAssignedStudents.removeWhere((id) => processedStudentIds.contains(id));
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$atamaYapilanSayisi yeni atama başarıyla tamamlandı.'), backgroundColor: Colors.green));
      await Future.delayed(const Duration(milliseconds: 500));
      await _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Atama hatası: $e'), backgroundColor: Colors.red));
      if (mounted) setState(() => _loading = false);
    }
  }

  double _getGroupSuccessAvg(String groupId) {
    final assigns = _assignmentsByGroup[groupId] ?? [];
    if (assigns.isEmpty) return 0.0;
    return assigns.fold(0.0, (sum, a) => sum + a.basariOrani) / assigns.length;
  }

  // ─── UI BİLEŞENLERİ ──────────────────────────────────────────────────────

  Widget _buildGroupsTab() {
    if (_groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_outlined, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('Grup yok', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
            const SizedBox(height: 8),
            Text('"Dağıtım Yap" butonuna basarak\nalgoritmanın çalışmasını sağlayın.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
          ],
        ),
      );
    }

    int getDayIndex(String dayStr) {
      final d = dayStr.toLowerCase();
      if (d.contains('pazartesi') || d.contains('pzt')) return 1;
      if (d.contains('salı') || d.contains('sali') || d.contains('sal')) return 2;
      if (d.contains('çarşamba') || d.contains('carsamba') || d.contains('çrş')) return 3;
      if (d.contains('perşembe') || d.contains('persembe') || d.contains('prş')) return 4;
      if (d.contains('cumartesi') || d.contains('cmt')) return 6;
      if (d.contains('cuma') || d.contains('cum')) return 5;
      if (d.contains('pazar') || d.contains('pzr')) return 7;
      return 99;
    }

    final Map<String, List<CampGroup>> byBranch = {};
    final Set<String> allGroupBranches = _groups.map((g) => g.isSpecial ? 'Özel Sınıf' : g.dersAdi).toSet();
    final allDays = _groups.map((g) => g.gun).where((d) => d.isNotEmpty).toSet().toList()..sort((a, b) {
      final idxA = getDayIndex(a);
      final idxB = getDayIndex(b);
      if (idxA == idxB) return a.compareTo(b);
      return idxA.compareTo(idxB);
    });

    // Seçili güne ait slotları belirle
    final filteredGroups = _groups.where((g) => _selectedSlotFilter == null || g.gun == _selectedSlotFilter).toList();
    final allPossibleSlots = filteredGroups.map((g) => '${g.baslangicSaat}-${g.bitisSaat}').toSet().toList()..sort();
    
    if (_selectedTimeSlots == null) _selectedTimeSlots = Set<String>.from(allPossibleSlots);

    for (final g in filteredGroups) {
      final key = g.isSpecial ? 'Özel Sınıf' : g.dersAdi;
      if (_groupFilterBranch != null && key != _groupFilterBranch) continue;
      final slotKey = '${g.baslangicSaat}-${g.bitisSaat}';
      if (!_selectedTimeSlots!.contains(slotKey)) continue;
      byBranch.putIfAbsent(key, () => []).add(g);
    }

    final sortedBranches = byBranch.keys.toList()..sort((a, b) {
      if (a == 'Özel Sınıf') return -1;
      if (b == 'Özel Sınıf') return 1;
      return a.compareTo(b);
    });

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCycleSummaryBar(),
        const SizedBox(height: 16),
        _buildGroupFilterRow(allGroupBranches.toList()..sort(), allPossibleSlots, allDays),
        const SizedBox(height: 12),
        ...sortedBranches.map((branch) {
          final groups = byBranch[branch]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBranchHeader(branch),
              const SizedBox(height: 8),
              ...groups.map((g) => _buildGroupCard(g)),
              const SizedBox(height: 12),
            ],
          );
        }),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildCycleSummaryBar() {
    final totalAssignments = _assignmentsByGroup.values.fold(0, (sum, list) => sum + list.length);
    final totalUnplaced = _unassignedStudents.length + _underAssignedStudents.length + _absentStudents.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.orange.shade600, Colors.orange.shade800]), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          _statItem('${_groups.length}', 'Grup'),
          _dividerStat(),
          _statItem('$_totalPotentialStudents', 'Öğrenci'),
          _dividerStat(),
          _statItem('$totalAssignments', 'Atanan'),
          _dividerStat(),
          _statItem('$totalUnplaced', 'Yerleşmedi'),
        ],
      ),
    );
  }

  Widget _statItem(String value, String label) => Expanded(child: Column(children: [Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10), textAlign: TextAlign.center)]));
  Widget _dividerStat() => Container(height: 30, width: 1, color: Colors.white30, margin: const EdgeInsets.symmetric(horizontal: 8));

  Widget _buildGroupFilterRow(List<String> branches, List<String> allSlots, List<String> allDays) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedSlotFilter,
                      isExpanded: true,
                      hint: Text(
                        'Tümü (Slotlar)', 
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isDense: true,
                      icon: Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null, 
                          child: Text('Tümü (Slotlar)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        ...allDays.map((day) => DropdownMenuItem<String>(
                          value: day, 
                          child: Text(day, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                        )),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedSlotFilter = val;
                          _selectedTimeSlots = null; // Gün değişince alt slotları sıfırla
                        });
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _groupFilterBranch,
                      isDense: true,
                      isExpanded: true,
                      icon: Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
                      hint: Text(
                        'Tüm Branşlar', 
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.bold),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null, 
                          child: Text('Tüm Branşlar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        ...branches.map((b) => DropdownMenuItem<String>(
                          value: b, 
                          child: Text(b, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                        )),
                      ],
                      onChanged: (v) => setState(() => _groupFilterBranch = v),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (allSlots.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Text('Saat Slotları: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
                    ...allSlots.asMap().entries.map((entry) {
                      final index = entry.key + 1;
                      final slotKey = entry.value;
                      final isSelected = _selectedTimeSlots?.contains(slotKey) ?? true;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              if (_selectedTimeSlots == null) _selectedTimeSlots = Set<String>.from(allSlots);
                              if (_selectedTimeSlots!.contains(slotKey)) {
                                _selectedTimeSlots!.remove(slotKey);
                              } else {
                                _selectedTimeSlots!.add(slotKey);
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            width: 28, height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.orange : Colors.white, 
                              borderRadius: BorderRadius.circular(6), 
                              border: Border.all(color: isSelected ? Colors.orange : Colors.grey.shade300)
                            ),
                            child: Text('$index', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.grey.shade600)),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        ],
      );
    }

    return Row(
      children: [
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedSlotFilter,
              hint: Text('Tümü (Slotlar)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700, fontSize: 13)),
              isDense: true,
              icon: Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('Tümü (Slotlar)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                ...allDays.map((day) => DropdownMenuItem<String>(value: day, child: Text(day, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))),
              ],
              onChanged: (val) {
                setState(() {
                  _selectedSlotFilter = val;
                  _selectedTimeSlots = null; // Gün değişince alt slotları sıfırla
                });
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ...allSlots.asMap().entries.map((entry) {
                  final index = entry.key + 1;
                  final slotKey = entry.value;
                  final isSelected = _selectedTimeSlots?.contains(slotKey) ?? true;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          if (_selectedTimeSlots == null) _selectedTimeSlots = Set<String>.from(allSlots);
                          if (_selectedTimeSlots!.contains(slotKey)) { _selectedTimeSlots!.remove(slotKey); } else { _selectedTimeSlots!.add(slotKey); }
                        });
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        width: 26, height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: isSelected ? Colors.orange : Colors.white, borderRadius: BorderRadius.circular(4), border: Border.all(color: isSelected ? Colors.orange : Colors.grey.shade300)),
                        child: Text('$index', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.grey.shade600)),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _groupFilterBranch,
              hint: const Text('Tüm Branşlar', style: TextStyle(fontSize: 12)),
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('Tüm Branşlar')),
                ...branches.map((b) => DropdownMenuItem<String>(value: b, child: Text(b))),
              ],
              onChanged: (v) => setState(() => _groupFilterBranch = v),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBranchHeader(String branch) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [Icon(Icons.label_important_outline, size: 16, color: Colors.orange.shade700), const SizedBox(width: 6), Text(branch, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.orange.shade700))]));

  bool _hasHighPercentSuccess(CampGroup group) {
    final assignments = _assignmentsByGroup[group.id] ?? [];
    if (assignments.isEmpty) return false;
    final avg = assignments.fold(0.0, (sum, a) => sum + a.basariOrani) / assignments.length;
    return (avg * 100).round() >= 95;
  }

  Widget _buildGroupCard(CampGroup group) {
    final assignments = _assignmentsByGroup[group.id] ?? [];
    final doluluk = group.kapasite > 0 ? assignments.length / group.kapasite : 0.0;
    final isSpecial = group.isSpecial;
    Color dolulukRenk = Colors.green;
    if (doluluk >= 1.0) dolulukRenk = Colors.red; else if (doluluk >= 0.8) dolulukRenk = Colors.orange;

    final isHighPercentSuccess = _hasHighPercentSuccess(group);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
          child: Icon(isSpecial ? Icons.star : Icons.book_outlined, color: Colors.orange, size: 22),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Full-Width Title (TAM SATIR)
            Text(
              isSpecial ? 'ÖZEL SINIF - ${group.derslikAdi ?? ""}' : group.dersAdi, 
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            // Row 2: Subtitle details and Right-hand metrics side-by-side
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left details: Time, Teacher, Kazanım
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${group.gun} • ${group.baslangicSaat}-${group.bitisSaat} • ${group.ogretmenAdi}${group.derslikAdi != null ? ' (${group.derslikAdi})' : ''}', 
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (group.kazanimlar.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2), 
                          child: Text(
                            isHighPercentSuccess ? 'Ana Kazanım: Soru Çözümü' : 'Ana Kazanım: ${group.kazanimlar.first}', 
                            maxLines: 1, 
                            overflow: TextOverflow.ellipsis, 
                            style: TextStyle(fontSize: 11, color: Colors.orange.shade700, fontWeight: FontWeight.bold)
                          )
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Right details: Capacity, Progress, Avg Success
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${assignments.length}/${group.kapasite}', 
                      style: TextStyle(fontWeight: FontWeight.bold, color: dolulukRenk, fontSize: 13),
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      width: 48, height: 4, 
                      child: LinearProgressIndicator(
                        value: doluluk.clamp(0.0, 1.0), 
                        backgroundColor: Colors.grey.shade200, 
                        valueColor: AlwaysStoppedAnimation<Color>(dolulukRenk), 
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 3),
                    _buildGroupAvgBadge(group),
                  ],
                ),
              ],
            ),
          ],
        ),
        children: [
          if (group.kazanimlar.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Kazanımlar (1 Ana + 2 Yardımcı)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.orange)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: [
                      if (isHighPercentSuccess)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.orange.shade100)),
                          child: const Text('Ana: Soru Çözümü', style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold)),
                        )
                      else
                        ...group.kazanimlar.take(3).toList().asMap().entries.map((entry) {
                          final index = entry.key;
                          final k = entry.value;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.orange.shade100)),
                            child: Text(index == 0 ? 'Ana: $k' : 'Yard: $k', style: TextStyle(fontSize: 11, color: index == 0 ? Colors.orange.shade900 : Colors.grey.shade700, fontWeight: index == 0 ? FontWeight.bold : FontWeight.w500)),
                          );
                        }),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Divider(color: Colors.grey.shade200),
                ],
              ),
            ),
          if (assignments.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Bu grupta henüz öğrenci yok.'))
          else _buildGroupStudentList(assignments),
        ],
      ),
    );
  }
  
  Widget _buildGroupStudentList(List<CampAssignment> assignments) {
    final sortedAssignments = List<CampAssignment>.from(assignments)
      ..sort((a, b) => b.basariOrani.compareTo(a.basariOrani));
    
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sortedAssignments.length,
      itemBuilder: (context, index) {
        final s = sortedAssignments[index];
        final isSelected = _selectedStudentIds.contains(s.ogrenciId);
        return InkWell(
          onTap: () => setState(() { if (isSelected) _selectedStudentIds.remove(s.ogrenciId); else _selectedStudentIds.add(s.ogrenciId); }),
          child: Container(
            color: isSelected ? Colors.orange.shade50.withOpacity(0.5) : null,
            child: ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 12,
                backgroundColor: isSelected ? Colors.orange : Colors.orange.shade50,
                child: isSelected ? const Icon(Icons.check, size: 14, color: Colors.white) : Text('${index + 1}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange)),
              ),
              title: Row(children: [
                Expanded(child: Text('${s.ogrenciAdi}${s.sube != null ? " (${s.sube})" : ""}', style: const TextStyle(fontWeight: FontWeight.w500))),
                _buildStudentScoreBadge(s),
              ]),
              trailing: _selectedStudentIds.isEmpty ? IconButton(
                icon: const Icon(Icons.compare_arrows, size: 16, color: Colors.grey),
                onPressed: () => _showMoveDialog([s]),
              ) : null,
            ),
          ),
        );
      },
    );
  }

  Widget _buildGroupAvgBadge(CampGroup group) {
    final assignments = _assignmentsByGroup[group.id] ?? [];
    if (assignments.isEmpty) return const SizedBox.shrink();
    final avg = assignments.fold(0.0, (sum, a) => sum + a.basariOrani) / assignments.length;
    final pct = (avg * 100).toStringAsFixed(0);
    final color = avg < 0.4 ? Colors.red : avg < 0.7 ? Colors.orange : Colors.green;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Ort. %$pct', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
        if (!group.isSpecial)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: InkWell(
              onTap: () => _showSwapGroupDialog(group),
              child: Icon(Icons.swap_horiz, size: 14, color: Colors.grey.shade400),
            ),
          ),
      ],
    );
  }

  Widget _buildStudentScoreBadge(CampAssignment a) {
    final pct = (a.basariOrani * 100).toStringAsFixed(0);
    final color = a.basariOrani < 0.4 ? Colors.red : a.basariOrani < 0.7 ? Colors.orange : Colors.green;
    return Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.3))), child: Text('%$pct', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)));
  }

  Widget _buildBulkActionBar() {
    final selectedAssignments = _assignmentsByGroup.values.expand((list) => list).where((a) => _selectedStudentIds.contains(a.ogrenciId)).toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -2))]),
      child: SafeArea(
        child: Row(
          children: [
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${_selectedStudentIds.length} Öğrenci Seçildi', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), Text('Toplu işlem yapabilirsiniz.', style: TextStyle(color: Colors.grey.shade600, fontSize: 11))]),
            const Spacer(),
            TextButton(onPressed: () => setState(() => _selectedStudentIds.clear()), child: const Text('İptal')),
            const SizedBox(width: 8),
            ElevatedButton.icon(onPressed: () => _removeAssignments(selectedAssignments), icon: const Icon(Icons.delete_outline, size: 18), label: const Text('Çıkar'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade50, foregroundColor: Colors.red, elevation: 0)),
            const SizedBox(width: 8),
            ElevatedButton.icon(onPressed: () => _showMoveDialog(selectedAssignments), icon: const Icon(Icons.swap_horiz, size: 18), label: const Text('Taşı'), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _buildYerlesmeyenTab() {
    return Column(
      children: [
        Container(padding: const EdgeInsets.all(12), color: Colors.white, child: Row(children: [_filterChip(0, 'Sınava Girmeyenler', _absentStudents.length), const SizedBox(width: 8), _filterChip(1, 'Atanamayanlar', _unassignedStudents.length), const SizedBox(width: 8), _filterChip(2, 'Eksik Atananlar', _underAssignedStudents.length)])),
        Expanded(child: _yerlesmeyenFilterIndex == 0 ? _buildStudentList(_absentStudents) : _buildStudentList(_getMappedStudents(_yerlesmeyenFilterIndex))),
      ],
    );
  }

  Widget _filterChip(int index, String label, int count) {
    final isSelected = _yerlesmeyenFilterIndex == index;
    return Expanded(child: InkWell(onTap: () => setState(() => _yerlesmeyenFilterIndex = index), child: Container(padding: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: isSelected ? Colors.orange.shade700 : Colors.grey.shade50, borderRadius: BorderRadius.circular(20), border: Border.all(color: isSelected ? Colors.orange.shade700 : Colors.grey.shade300)), child: Column(children: [Text('$count', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.orange.shade700)), Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.grey.shade600), textAlign: TextAlign.center)]))));
  }

  List<Map<String, dynamic>> _getMappedStudents(int filterIndex) {
    final List<String> ids = filterIndex == 1 ? _unassignedStudents : _underAssignedStudents;
    return _allBranchStudents.where((s) => ids.contains(s['id'])).map((s) => {'id': s['id'], 'name': (s['fullName'] ?? s['name'] ?? 'İsimsiz').toString(), 'branch': (s['className'] ?? s['branch'] ?? '').toString(), 'subeId': s['branchId'] ?? ''}).toList();
  }

  Widget _buildStudentList(List<Map<String, dynamic>> students) {
    if (students.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.check_circle_outline, size: 56, color: Colors.green.shade300), const SizedBox(height: 12), const Text('Bu kategoride öğrenci yok.')]));
    return ListView.builder(padding: const EdgeInsets.all(12), itemCount: students.length, itemBuilder: (context, i) {
      final student = students[i];
      final name = student['name'] ?? 'İsimsiz';
      final branch = student['branch'] ?? '';
      final studentId = student['id']?.toString() ?? '';
      final reasons = _unassignedReasons[studentId] ?? [];
      
      // Öğrencinin atanmış olduğu gruplar
      final studentAssigns = _assignmentsByGroup.values.expand((list) => list).where((a) => a.ogrenciId == studentId).toList();
      final Map<String, CampAssignment> assignedSlots = {for (final a in studentAssigns) a.groupId: a};
      final Set<String> occupiedTimes = studentAssigns.map((a) {
        final g = _groups.firstWhere((g) => g.id == a.groupId);
        return '${g.baslangicSaat}-${g.gun}';
      }).toSet();

      return Card(
        margin: const EdgeInsets.only(bottom: 12), 
        elevation: 0, 
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)), 
        child: ExpansionTile(
          shape: const RoundedRectangleBorder(side: BorderSide.none),
          collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
          tilePadding: const EdgeInsets.fromLTRB(16, 8, 8, 8), 
          leading: CircleAvatar(backgroundColor: Colors.orange.shade50, child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.bold))), 
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)), 
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(branch, style: const TextStyle(fontSize: 12)), 
            if (reasons.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: reasons.map((r) => Text('• $r', style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.w500))).toList())),
            if (studentAssigns.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${studentAssigns.length} seansa atandı.', style: const TextStyle(fontSize: 10, color: Colors.teal, fontWeight: FontWeight.bold))),
          ]), 
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => _autoAssignSingleStudent(student),
                child: const Text('Otomatik Ata', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal)),
              ),
              const Icon(Icons.expand_more, size: 18),
            ],
          ),
          children: [
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Atama Durumu (Seans Bazlı)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
                  const SizedBox(height: 12),
                  ...() {
                    // Tüm seansları al
                    final allTimeSlots = _groups.map((g) => '${g.baslangicSaat}-${g.bitisSaat}#${g.gun}').toSet().toList()..sort();
                    return allTimeSlots.map((slotKey) {
                      final parts = slotKey.split('#');
                      final time = parts[0];
                      final day = parts[1];
                      final shortTime = time.split('-')[0];
                      
                      final assignment = studentAssigns.firstWhere((a) {
                        final g = _groups.firstWhere((g) => g.id == a.groupId);
                        return '${g.baslangicSaat}-${g.bitisSaat}' == time && g.gun == day;
                      }, orElse: () => CampAssignment(id: '', cycleId: '', groupId: '', ogrenciId: '', ogrenciAdi: '', groupName: ''));

                      final bool isAssigned = assignment.id.isNotEmpty;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isAssigned ? Colors.teal.shade50 : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isAssigned ? Colors.teal.shade100 : Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 80,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(day, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                  Text(shortTime, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Text(
                                isAssigned ? assignment.groupName : 'Atama Yapılmadı',
                                style: TextStyle(
                                  fontSize: 12, 
                                  fontWeight: isAssigned ? FontWeight.bold : FontWeight.normal,
                                  color: isAssigned ? Colors.teal.shade900 : Colors.grey.shade600,
                                ),
                              ),
                            ),
                            if (!isAssigned)
                              TextButton.icon(
                                onPressed: () {
                                  // Bu seansa ait grupları filtrele
                                  final slotGroups = _groups.where((g) => '${g.baslangicSaat}-${g.bitisSaat}' == time && g.gun == day).toList();
                                  _showManualAssignDialog(student, slotGroups: slotGroups);
                                },
                                icon: const Icon(Icons.add_circle_outline, size: 14),
                                label: const Text('Buraya Ata', style: TextStyle(fontSize: 10)),
                                style: TextButton.styleFrom(foregroundColor: Colors.teal, padding: const EdgeInsets.symmetric(horizontal: 8)),
                              ),
                          ],
                        ),
                      );
                    });
                  }(),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _autoAssignSingleStudent(Map<String, dynamic> student) async {
    setState(() => _loading = true);
    try {
      final studentId = student['id'] as String;

      // Load actual student profiles for this student
      final allStudents = await _fetchStudentsForCycle();
      final targetFullStudents = allStudents.where((s) => s['id'] == studentId).toList();
      final Set<String> allStudentsWhoEnteredExam = {};
      final profiles = await _createStudentNeedProfiles(targetFullStudents, (sid) => allStudentsWhoEnteredExam.add(sid));

      final profile = profiles.firstWhere((p) => p.ogrenciId == studentId, orElse: () => StudentNeedProfile(ogrenciId: studentId, ogrenciAdi: student['name'] ?? 'İsimsiz', subeId: student['subeId'] ?? '', subeAdi: student['branch'] ?? '', dersIhtiyaclari: {}));
      final actualSube = profile.subeAdi.isNotEmpty ? profile.subeAdi : (student['branch'] ?? '');

      final assignedGroupIds = _assignmentsByGroup.entries.where((e) => e.value.any((a) => a.ogrenciId == studentId)).map((e) => e.key).toSet();
      final assignedSubjects = <String>{};
      final occupiedTimeSlots = <String>{};

      for (final grup in _groups) {
        if (assignedGroupIds.contains(grup.id)) {
          assignedSubjects.add(grup.dersAdi);
          occupiedTimeSlots.add('${grup.baslangicSaat}-${grup.gun}');
        }
      }

      final prioritizedGroups = List<CampGroup>.from(_groups)
        ..sort((a, b) {
          final avgA = _getGroupSuccessAvg(a.id);
          final avgB = _getGroupSuccessAvg(b.id);
          return avgA.compareTo(avgB);
        });

      int assignedCount = 0;
      void attemptAssignment({required bool allowDuplicateSubject}) {
        for (final grup in prioritizedGroups) {
          if (widget.cycle.haftalikMaksimumSaat != null && occupiedTimeSlots.length >= widget.cycle.haftalikMaksimumSaat!) break;

          if (!allowDuplicateSubject && assignedSubjects.contains(grup.dersAdi)) continue; 
          if (occupiedTimeSlots.contains('${grup.baslangicSaat}-${grup.gun}')) continue; 

          final currentAssigns = _assignmentsByGroup[grup.id] ?? [];
          if (currentAssigns.length < grup.kapasite) {
            if (assignedGroupIds.contains(grup.id)) continue;

            final actualBasari = profile.dersBasariOranlari[grup.dersId] ?? profile.dersBasariOranlari[grup.dersAdi] ?? 0.5;

            _service.manualAssign(
              cycleId: widget.cycle.id,
              ogrenciId: studentId,
              ogrenciAdi: student['name']?.toString() ?? 'İsimsiz',
              subeId: student['subeId'] ?? '',
              subeAdi: actualSube,
              yeniGrupId: grup.id,
              yeniGrupAdi: '${grup.dersAdi} - ${grup.ogretmenAdi}',
              basariOrani: actualBasari,
              isAbsent: _yerlesmeyenFilterIndex == 0,
            );
            assignedCount++;
            
            occupiedTimeSlots.add('${grup.baslangicSaat}-${grup.gun}');
            assignedSubjects.add(grup.dersAdi);
            assignedGroupIds.add(grup.id);
          }
        }
      }

      attemptAssignment(allowDuplicateSubject: false);
      
      if (assignedCount == 0 || _yerlesmeyenFilterIndex == 2 || (widget.cycle.minimumDersSayisi != null && occupiedTimeSlots.length < widget.cycle.minimumDersSayisi!)) {
        attemptAssignment(allowDuplicateSubject: true);
      }

      if (assignedCount > 0) {
        setState(() {
          _unassignedStudents.remove(studentId);
          _underAssignedStudents.remove(studentId);
          _absentStudents.removeWhere((s) => s['id'] == studentId);
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Öğrenci $assignedCount seansa başarıyla atandı.'), backgroundColor: Colors.green));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uygun boş yer bulunamadı.'), backgroundColor: Colors.orange));
      }
      await _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red));
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildReportsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildReportTile(
            icon: Icons.analytics_rounded,
            title: 'İşlem ve Değişiklik Logu',
            subtitle: 'Atama geçmişi ve sistem günlükleri',
            color: Colors.indigo,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CampReportsScreen(institutionId: widget.cycle.institutionId, cycleId: widget.cycle.id))),
          ),
          const SizedBox(height: 16),
          _buildReportTile(
            icon: Icons.person_pin_rounded,
            title: 'Öğrenci Haftalık Takvim',
            subtitle: 'Bireysel öğrenci ders programları',
            color: Colors.teal,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CampStudentTimetableScreen(cycle: widget.cycle, groups: _groups, assignmentsByGroup: _assignmentsByGroup))),
          ),
          const SizedBox(height: 16),
          _buildReportTile(
            icon: Icons.assignment_ind_rounded,
            title: 'Öğretmen Haftalık Takvim',
            subtitle: 'Öğretmen programları ve listeler',
            color: Colors.amber.shade700,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CampTeacherTimetableScreen(cycle: widget.cycle, groups: _groups, assignmentsByGroup: _assignmentsByGroup))),
          ),
          const SizedBox(height: 16),
          _buildReportTile(
            icon: Icons.meeting_room_rounded,
            title: 'Derslik Haftalık Takvim',
            subtitle: 'Derslik doluluk ve program detayları',
            color: Colors.pink.shade600,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CampClassroomTimetableScreen(cycle: widget.cycle, groups: _groups, assignmentsByGroup: _assignmentsByGroup))),
          ),
        ],
    );
  }

  Widget _buildReportTile({required IconData icon, required String title, required String subtitle, required Color color, required VoidCallback onTap}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 5)),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(
                  width: 6,
                  color: color,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(icon, color: color, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
                              const SizedBox(height: 4),
                              Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: Colors.grey.shade300),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showGenerateDraftSheet() {
    final subjects = _groups.where((g) => !g.isSpecial).map((g) => g.dersAdi).toSet().toList()..sort();
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (ctx) => _DraftGenerateSheet(cycle: widget.cycle, availableSubjects: subjects, onGenerate: (esik, sadeceDusuk, dersBazli, minGrup, pastCycles) async { Navigator.pop(ctx); await _executeGenerate(esik, sadeceDusuk, dersBazli, minGrup, pastCycles); }));
  }

  Future<void> _executeGenerate(double esik, bool sadeceDusuk, Map<String, double> dersBazli, int minGrup, List<String> pastCycles) async {
    setState(() => _generating = true);
    try {
      final students = await _fetchStudentsForCycle();
      final Set<String> allStudentsWhoEnteredExam = {};
      final profiles = await _createStudentNeedProfiles(students, (sid) => allStudentsWhoEnteredExam.add(sid));
      final List<Map<String, dynamic>> absent = students.where((s) => !allStudentsWhoEnteredExam.contains(s['id'])).map((s) => {'id': s['id'], 'name': (s['fullName'] ?? s['name'] ?? 'İsimsiz').toString(), 'branch': (s['className'] ?? s['branch'] ?? '').toString(), 'subeId': s['branchId'] ?? ''}).toList();
      
      final engine = CampAssignmentEngine(cycleId: widget.cycle.id, institutionId: widget.cycle.institutionId, haftalikMaksimumSaat: widget.cycle.haftalikMaksimumSaat, minimumGrupOgrenciSayisi: minGrup);
      engine.setMinimumDersSayisi(widget.cycle.minimumDersSayisi);
      
      Map<String, Map<String, int>> gecmisKatilimlar = {};
      if (pastCycles.isNotEmpty) {
        for (var pid in pastCycles) {
          final snap = await _db.collection('camp_assignments').where('cycleId', isEqualTo: pid).get();
          for (var doc in snap.docs) {
            final data = doc.data();
            final ogrenciId = data['ogrenciId'] as String?;
            final groupName = data['groupName'] as String?;
            if (ogrenciId != null && groupName != null) {
              final dersAdi = groupName.split(' - ').first.trim();
              gecmisKatilimlar.putIfAbsent(ogrenciId, () => {});
              gecmisKatilimlar[ogrenciId]![dersAdi] = (gecmisKatilimlar[ogrenciId]![dersAdi] ?? 0) + 1;
            }
          }
        }
      }
      
      final draftResult = await engine.generateDraft(ogrenciProfiller: profiles, gruplar: _groups, esikBasariOrani: esik, sadeceDusukBasari: sadeceDusuk, dersBazliEsikler: dersBazli, gecmisKatilimlar: gecmisKatilimlar);
      
      final Map<String, List<String>> allReasons = Map.from(draftResult.yerlesmemeNedenleri);
      for (final a in absent) allReasons.putIfAbsent(a['id'].toString(), () => []).add('Sınava girmedi, analiz verisi yok.');
      
      await _repo.rollbackAssignments(widget.cycle.id);
      await _repo.batchWriteAssignments(draftResult.atamalar);
      await _repo.batchUpdateGroups(draftResult.gruplar);
      
      await _db.collection('camp_cycles').doc(widget.cycle.id).update({
        'unassignedStudentIds': draftResult.yerlesmeyenOgrenciIds, 
        'underAssignedStudentIds': draftResult.eksikAtananOgrenciIds, 
        'absentStudentIds': absent.map((a) => a['id'].toString()).toList(), 
        'unassignedReasons': allReasons
      });
      
      await _loadData();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dağıtım başarıyla tamamlandı!'), backgroundColor: Colors.green));
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red)); } finally { setState(() => _generating = false); }
  }

  Future<List<Map<String, dynamic>>> _fetchStudentsForCycle() async {
    final List<String> examIds = widget.cycle.referansDenemeSinavIds.isNotEmpty ? widget.cycle.referansDenemeSinavIds : [widget.cycle.referansDenemeSinavId];
    final Set<String> studentIds = {};
    final List<Map<String, dynamic>> students = [];
    for (var eid in examIds) {
      final doc = await _db.collection('trial_exams').doc(eid).get();
      if (!doc.exists) continue;
      final branches = (doc.data()!['selectedBranches'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
      final classLevel = doc.data()!['classLevel']?.toString() ?? '';
      if (branches.isNotEmpty) {
        for (var b in branches) {
          final sSnap = await _db.collection('students').where('institutionId', isEqualTo: widget.cycle.institutionId).where('className', isEqualTo: b).where('isActive', isEqualTo: true).get();
          for (var sDoc in sSnap.docs) if (!studentIds.contains(sDoc.id)) { students.add({...sDoc.data(), 'id': sDoc.id}); studentIds.add(sDoc.id); }
        }
      } else if (classLevel.isNotEmpty) {
        final sSnap = await _db.collection('students').where('institutionId', isEqualTo: widget.cycle.institutionId).where('classLevel', isEqualTo: classLevel).where('isActive', isEqualTo: true).get();
        for (var sDoc in sSnap.docs) if (!studentIds.contains(sDoc.id)) { students.add({...sDoc.data(), 'id': sDoc.id}); studentIds.add(sDoc.id); }
      }
    }
    return students;
  }

  Future<List<StudentNeedProfile>> _createStudentNeedProfiles(List<Map<String, dynamic>> students, Function(String) onStudentEntered) async {
    final List<String> examIds = widget.cycle.referansDenemeSinavIds.isNotEmpty ? widget.cycle.referansDenemeSinavIds : [widget.cycle.referansDenemeSinavId];
    final Map<String, Map<String, double>> studentSubjectSuccess = {}; 
    final Map<String, Map<String, Set<String>>> studentSubjectTopics = {};

    for (var eid in examIds) {
      final doc = await _db.collection('trial_exams').doc(eid).get();
      if (doc.exists && doc.data()!['resultsJson'] != null) {
        try {
          final examData = doc.data()!;
          final outcomesMapRaw = examData['outcomes'] as Map<String, dynamic>? ?? {};
          final Map<String, Map<String, List<String>>> examOutcomes = {};
          outcomesMapRaw.forEach((booklet, subjects) {
            if (subjects is Map<String, dynamic>) {
              examOutcomes[booklet] = subjects.map((k, v) => MapEntry(k, (v as List<dynamic>).map((e) => e.toString()).toList()));
            }
          });

          final List<dynamic> results = jsonDecode(examData['resultsJson']);
          for (var r in results) {
            final sr = StudentResult.fromJson(r);
            if (sr.systemStudentId != null) {
              onStudentEntered(sr.systemStudentId!);
              final Map<String, double> successMap = studentSubjectSuccess.putIfAbsent(sr.systemStudentId!, () => {});
              final Map<String, Set<String>> topicMap = studentSubjectTopics.putIfAbsent(sr.systemStudentId!, () => {});

              sr.subjects.forEach((ders, stats) {
                final totalQ = stats.correct + stats.wrong + stats.empty;
                if (totalQ > 0) { 
                  final current = stats.correct / totalQ; 
                  successMap[ders] = successMap.containsKey(ders) ? (successMap[ders]! + current) / 2 : current; 
                  
                  if (current < 0.6) {
                    final studentAnswers = sr.answers[ders] ?? '';
                    final correctAnswers = sr.correctAnswers[ders] ?? '';
                    final booklet = sr.booklet.isNotEmpty ? sr.booklet[0] : 'A';
                    final subjectOutcomes = examOutcomes[booklet]?[ders] ?? [];

                    final topics = topicMap.putIfAbsent(ders, () => {});
                    for (int i = 0; i < studentAnswers.length && i < correctAnswers.length; i++) {
                      if (studentAnswers[i] != correctAnswers[i] && i < subjectOutcomes.length) {
                        final kazanim = subjectOutcomes[i];
                        if (kazanim.isNotEmpty && kazanim != '-') topics.add(kazanim);
                      }
                    }
                  }
                }
              });
            }
          }
        } catch (e) {}
      }
    }
    return students.where((s) => studentSubjectSuccess.containsKey(s['id'])).map((s) {
      final sid = s['id'] as String;
      final success = studentSubjectSuccess[sid]!;
      final topics = studentSubjectTopics[sid] ?? {};
      return StudentNeedProfile(ogrenciId: sid, ogrenciAdi: s['fullName'] ?? '${s['name']} ${s['surname']}', subeId: s['branchId'] ?? '', subeAdi: (s['className'] ?? s['branch'] ?? '').toString(), dersIhtiyaclari: success.map((k, v) => MapEntry(k, (1.0 - v).clamp(0.0, 1.0))), dersBasariOranlari: success, kazanimIhtiyaclari: topics);
    }).toList();
  }
}

class _DraftGenerateSheet extends StatefulWidget {
  final CampCycle cycle;
  final List<String> availableSubjects;
  final Future<void> Function(double esik, bool sadeceDusuk, Map<String, double> dersBazli, int minGrup, List<String> pastCycles) onGenerate;
  const _DraftGenerateSheet({required this.cycle, required this.availableSubjects, required this.onGenerate});
  @override
  State<_DraftGenerateSheet> createState() => _DraftGenerateSheetState();
}

class _DraftGenerateSheetState extends State<_DraftGenerateSheet> {
  double _esikBasariOrani = 0.6;
  bool _sadeceDusukBasari = true;
  bool _loading = false;
  bool _dersBazliAcik = false;
  int _minGrupOgrenci = 5;
  final Map<String, double> _dersBazliEsikler = {};
  
  bool _dengele = false;
  List<String> _selectedPastCycles = [];
  List<Map<String, dynamic>> _availablePastCycles = [];

  @override
  void initState() { 
    super.initState(); 
    for (final sub in widget.availableSubjects) _dersBazliEsikler[sub] = _esikBasariOrani; 
    _fetchPastCycles();
  }

  Future<void> _fetchPastCycles() async {
    try {
       final snap = await FirebaseFirestore.instance.collection('camp_cycles').where('institutionId', isEqualTo: widget.cycle.institutionId).get();
       final cycles = snap.docs.map((d) => {'id': d.id, 'name': d.data()['title'] ?? 'İsimsiz Program'}).where((c) => c['id'] != widget.cycle.id).toList();
       if (mounted) setState(() => _availablePastCycles = cycles);
    } catch(e) {}
  }
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.auto_fix_high, color: Colors.orange, size: 20)),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Dağıtım Yap / Taslak Oluştur', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)), Text('Sınav sonuçlarına göre otomatik yerleştirme', style: TextStyle(fontSize: 12, color: Colors.grey))])),
          ]),
          const Divider(height: 28),
          Flexible(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Grup Kotaları', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)), Text('Grup minimum öğrenci sayısını belirle', style: TextStyle(fontSize: 11, color: Colors.grey))])),
              SizedBox(width: 50, child: TextFormField(initialValue: _minGrupOgrenci.toString(), keyboardType: TextInputType.number, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange), decoration: InputDecoration(isDense: true, filled: true, fillColor: Colors.orange.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)), onChanged: (v) => _minGrupOgrenci = int.tryParse(v) ?? 0)),
            ])),
            const Divider(height: 24),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _sadeceDusukBasari, onChanged: (v) => setState(() => _sadeceDusukBasari = v), activeColor: Colors.orange, title: const Text('Sadece düşük başarılı dersler', style: TextStyle(fontWeight: FontWeight.w600)), subtitle: const Text('Kapalıysa tüm dersler için atama yapılır', style: TextStyle(fontSize: 11))),
            if (_sadeceDusukBasari) ...[
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _dersBazliAcik,
                onChanged: (v) => setState(() {
                  _dersBazliAcik = v;
                  if (v) {
                    for (final sub in widget.availableSubjects) {
                      _dersBazliEsikler[sub] = _esikBasariOrani;
                    }
                  }
                }),
                activeColor: Colors.orange,
                title: const Text('Ders bazlı eşik belirle', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Her ders için farklı bir başarı eşiği tanımlayın', style: TextStyle(fontSize: 11)),
              ),
              const SizedBox(height: 12),
              if (!_dersBazliAcik) ...[
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Başarı Eşiği', style: TextStyle(fontWeight: FontWeight.w600)), Text('%${(_esikBasariOrani * 100).toStringAsFixed(0)}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16))]),
                Slider(value: _esikBasariOrani, min: 0.0, max: 1.0, divisions: 20, activeColor: Colors.orange, onChanged: (v) => setState(() => _esikBasariOrani = v)),
              ] else ...[
                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)), child: Column(children: widget.availableSubjects.map((sub) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(sub, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)), Text('%${((_dersBazliEsikler[sub] ?? 0.6) * 100).toStringAsFixed(0)}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13))]), Slider(value: _dersBazliEsikler[sub] ?? 0.6, min: 0.0, max: 1.0, divisions: 20, activeColor: Colors.orange.shade300, onChanged: (v) => setState(() => _dersBazliEsikler[sub] = v))])).toList())),
              ],
            ],
            const SizedBox(height: 16),
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade100)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.info_outline, color: Colors.blue.shade700, size: 18), const SizedBox(width: 8), const Expanded(child: Text('Mevcut sınav sonuçları analiz edilecek. Sınava girmeyen öğrenciler ayrı listede görünecek.', style: TextStyle(fontSize: 12, color: Colors.blue)))]))
          ]))),
          const SizedBox(height: 12),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _dengele, onChanged: (v) => setState(() => _dengele = v), activeColor: Colors.teal, title: const Text('Geçmiş Katılımları Dengele', style: TextStyle(fontWeight: FontWeight.w600)), subtitle: const Text('Diğer programlardaki katılımları analiz eder', style: TextStyle(fontSize: 11))),
          if (_dengele && _availablePastCycles.isNotEmpty) ...[
             const SizedBox(height: 8),
             Container(
               padding: const EdgeInsets.all(12),
               decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(10)),
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   const Text('Referans alınacak programları seçin:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal)),
                   const SizedBox(height: 8),
                   SingleChildScrollView(
                     scrollDirection: Axis.horizontal,
                     child: Row(
                       children: _availablePastCycles.map((c) {
                         final isSelected = _selectedPastCycles.contains(c['id']);
                         return Padding(
                           padding: const EdgeInsets.only(right: 8),
                           child: ChoiceChip(
                             label: Text(c['name'], style: TextStyle(fontSize: 11)),
                             selected: isSelected,
                             selectedColor: Colors.teal.shade200,
                             onSelected: (val) {
                               setState(() {
                                 if (val) _selectedPastCycles.add(c['id']);
                                 else _selectedPastCycles.remove(c['id']);
                               });
                             },
                           ),
                         );
                       }).toList(),
                     ),
                   )
                 ]
               )
             ),
             const SizedBox(height: 12),
          ],
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _loading ? null : () async { setState(() => _loading = true); await widget.onGenerate(_esikBasariOrani, _sadeceDusukBasari, _dersBazliAcik ? _dersBazliEsikler : {}, _minGrupOgrenci, _dengele ? _selectedPastCycles : []); }, icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.play_arrow_rounded), label: const Text('Algoritmayı Çalıştır'), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
        ],
      ),
    );
  }
}
