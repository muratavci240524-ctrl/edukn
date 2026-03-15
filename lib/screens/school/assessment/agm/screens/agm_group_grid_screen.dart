import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../../screens/school/assessment/evaluation_models.dart';
import '../models/agm_assignment_model.dart';
import '../models/agm_cycle_model.dart';
import '../models/agm_group_model.dart';
import '../repository/agm_repository.dart';
import '../services/agm_assignment_engine.dart';
import '../services/agm_service.dart';
import 'agm_reports_screen.dart';
import 'agm_student_timetable_screen.dart';
import 'agm_teacher_timetable_screen.dart';
import 'agm_classroom_timetable_screen.dart';

/// AGM Grup Grid Ekranı
/// Cycle'daki tüm grupları gösterir – ders/gün bazlı.
/// Öğrenci manuel taşıma, taslak oluşturma ve Publish işlemi buradan yapılır.
class AgmGroupGridScreen extends StatefulWidget {
  final AgmCycle cycle;

  const AgmGroupGridScreen({Key? key, required this.cycle}) : super(key: key);

  @override
  State<AgmGroupGridScreen> createState() => _AgmGroupGridScreenState();
}

class _AgmGroupGridScreenState extends State<AgmGroupGridScreen>
    with SingleTickerProviderStateMixin {
  final _service = AgmService();
  final _repo = AgmRepository();
  final _db = FirebaseFirestore.instance;
  late TabController _tabController;

  List<AgmGroup> _groups = [];
  Map<String, List<AgmAssignment>> _assignmentsByGroup = {};
  bool _loading = true;
  bool _publishing = false;
  bool _generating = false;
  String? _expandedStudentId;

  // Şube öğrencileri
  List<Map<String, dynamic>> _allBranchStudents = [];

  // Sınava girmeyen öğrenciler
  List<Map<String, dynamic>> _absentStudents = [];

  List<String> _unassignedStudents = [];
  List<String> _underAssignedStudents = [];
  Map<String, List<String>> _unassignedReasons = {};
  int _yerlesmeyenFilterIndex = 0;
  String? _groupFilterBranch;
  final Set<String> _selectedStudentIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    // Cycle'ı yeniden çek (güncel stats için)
    final cycleDoc = await _db
        .collection('agm_cycles')
        .doc(widget.cycle.id)
        .get();
    AgmCycle? currentCycle;
    if (cycleDoc.exists) {
      currentCycle = AgmCycle.fromMap(cycleDoc.data()!, cycleDoc.id);
    }

    final groups = await _repo.getGroupsByCycle(widget.cycle.id);
    final assignments = await _repo.getAssignmentsByCycle(widget.cycle.id);

    final Map<String, List<AgmAssignment>> byGroup = {};
    for (final g in groups) {
      byGroup[g.id] = [];
    }
    for (final a in assignments) {
      byGroup.putIfAbsent(a.groupId, () => []).add(a);
    }

    if (mounted) {
      setState(() {
        _groups = groups;
        _assignmentsByGroup = byGroup;
        _unassignedStudents = currentCycle?.unassignedStudentIds ?? [];
        _underAssignedStudents = currentCycle?.underAssignedStudentIds ?? [];
        _unassignedReasons = currentCycle?.unassignedReasons ?? {};
        _loading = false;
      });

      // Şube öğrencilerini ve persisted istatistikleri yükle
      _restorePersistedStats(currentCycle);
    }
  }

  Future<void> _restorePersistedStats(AgmCycle? cycle) async {
    if (cycle == null) return;

    // Şube öğrencilerini yükle (isimleri göstermek için lazım)
    await _loadBranchStudentsForCycle(cycle);

    if (mounted) {
      setState(() {
        // IDs -> List<String>
        _unassignedStudents = cycle.unassignedStudentIds;
        _underAssignedStudents = cycle.underAssignedStudentIds;
        _unassignedReasons = cycle.unassignedReasons;

        // IDs -> List<Map<String, dynamic>>
        _absentStudents = _allBranchStudents
            .where((s) => cycle.absentStudentIds.contains(s['id']))
            .map(
              (s) => {
                'id': s['id'],
                'name': (s['fullName'] ?? s['name'] ?? 'İsimsiz').toString(),
                'branch': (s['className'] ?? s['branch'] ?? '').toString(),
                'subeId': s['branchId'] ?? '',
              },
            )
            .toList();
      });

      // Öğrenci listeleri doldurulduktan sonra tüm statusleri doğrula.
      // Eger önceden atanan/manuel müdahale edilen vb olduysa ve firebase listelerinde yanlış kaldıysa (Eksik listesine düşmeme durumu vb).
      await _recalculateAndSyncStudentStatuses();
    }
  }

  Future<void> _recalculateAndSyncStudentStatuses() async {
    final int minDers = widget.cycle.minimumDersSayisi ?? 1;
    bool changed = false;

    // Tüm takip edilen öğrencilerin ID'leri
    final Set<String> targetIds = {
      ..._unassignedReasons.keys,
      ..._unassignedStudents,
      ..._underAssignedStudents,
      ..._absentStudents.map((s) => s['id'].toString()),
    };

    final List<String> newUnassigned = [];
    final List<String> newUnderAssigned = [];
    final List<Map<String, dynamic>> newAbsent = [];

    for (final studentId in targetIds) {
      // O anki toplam atanmış ders sayısını bulalım
      int atamaSayisi = 0;
      for (final list in _assignmentsByGroup.values) {
        if (list.any((a) => a.ogrenciId == studentId)) atamaSayisi++;
      }

      final bool isAbsentRaw = _absentStudents.any((s) => s['id'] == studentId);

      // Eğer absent ise ve ataması varsa, o artık absent değildir
      if (isAbsentRaw && atamaSayisi == 0) {
        final absentStudentInfo = _absentStudents.firstWhere(
          (s) => s['id'] == studentId,
        );
        newAbsent.add(absentStudentInfo);
      } else if (atamaSayisi == 0) {
        newUnassigned.add(studentId);
      } else if (atamaSayisi < minDers) {
        newUnderAssigned.add(studentId);
      }
    }

    // Değişiklik oldu mu?
    if (newUnassigned.length != _unassignedStudents.length ||
        newUnderAssigned.length != _underAssignedStudents.length ||
        newAbsent.length != _absentStudents.length ||
        newUnassigned.any((id) => !_unassignedStudents.contains(id)) ||
        newUnderAssigned.any((id) => !_underAssignedStudents.contains(id)) ||
        newAbsent.any((s) => !_absentStudents.any((a) => a['id'] == s['id']))) {
      changed = true;
    }

    if (changed) {
      if (mounted) {
        setState(() {
          _unassignedStudents = newUnassigned;
          _underAssignedStudents = newUnderAssigned;
          _absentStudents = newAbsent;
        });
      }

      await _db.collection('agm_cycles').doc(widget.cycle.id).update({
        'unassignedStudentIds': newUnassigned,
        'underAssignedStudentIds': newUnderAssigned,
        'absentStudentIds': newAbsent.map((s) => s['id'].toString()).toList(),
      });
    }
  }

  Future<void> _loadBranchStudentsForCycle(AgmCycle cycle) async {
    if (_allBranchStudents.isNotEmpty) return;

    try {
      final List<String> examIds =
          widget.cycle.referansDenemeSinavIds.isNotEmpty
          ? widget.cycle.referansDenemeSinavIds
          : [widget.cycle.referansDenemeSinavId];

      final List<Map<String, dynamic>> branchStudents = [];
      final Set<String> processedStudentIds = {};

      for (final examId in examIds) {
        final examDoc = await _db.collection('trial_exams').doc(examId).get();
        if (!examDoc.exists) continue;

        final examData = examDoc.data()!;
        final selectedBranches =
            (examData['selectedBranches'] as List<dynamic>? ?? [])
                .map((e) => e.toString())
                .toList();
        final classLevel = examData['classLevel']?.toString() ?? '';

        if (selectedBranches.isNotEmpty && classLevel.isNotEmpty) {
          for (final branch in selectedBranches) {
            final snap = await _db
                .collection('students')
                .where('institutionId', isEqualTo: widget.cycle.institutionId)
                .where('className', isEqualTo: branch)
                .where('isActive', isEqualTo: true)
                .get();
            for (final doc in snap.docs) {
              if (processedStudentIds.contains(doc.id)) continue;
              final data = Map<String, dynamic>.from(doc.data());
              data['id'] = doc.id;
              branchStudents.add(data);
              processedStudentIds.add(doc.id);
            }
          }
        } else if (classLevel.isNotEmpty) {
          final snap = await _db
              .collection('students')
              .where('institutionId', isEqualTo: widget.cycle.institutionId)
              .where('classLevel', isEqualTo: classLevel)
              .where('isActive', isEqualTo: true)
              .get();
          for (final doc in snap.docs) {
            if (processedStudentIds.contains(doc.id)) continue;
            final data = Map<String, dynamic>.from(doc.data());
            data['id'] = doc.id;
            branchStudents.add(data);
            processedStudentIds.add(doc.id);
          }
        }
      }

      if (mounted) {
        setState(() => _allBranchStudents = branchStudents);
      }
    } catch (e) {
      print('Şube öğrencilerini yüklerken hata: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool canPublish =
        widget.cycle.status == AgmCycleStatus.draft ||
        widget.cycle.status == AgmCycleStatus.locked;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          (widget.cycle.title != null && widget.cycle.title!.isNotEmpty)
              ? widget.cycle.title!
              : widget.cycle.referansDenemeSinavAdi,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.deepOrange,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (val) {
              if (val == 'refresh') _loadData();
              if (val == 'reset') _confirmResetDraft();
              if (val == 'publish') _publish();
              if (val == 'unpublish') _unpublish();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 20, color: Colors.black87),
                    SizedBox(width: 12),
                    Text('Yenile'),
                  ],
                ),
              ),
              if (widget.cycle.status == AgmCycleStatus.draft ||
                  widget.cycle.status == AgmCycleStatus.locked)
                const PopupMenuItem(
                  value: 'reset',
                  child: Row(
                    children: [
                      Icon(Icons.restart_alt, size: 20, color: Colors.black87),
                      SizedBox(width: 12),
                      Text('Taslağı Sıfırla'),
                    ],
                  ),
                ),
              if (canPublish)
                PopupMenuItem(
                  value: 'publish',
                  enabled: !_publishing,
                  child: Row(
                    children: [
                      Icon(
                        Icons.publish,
                        size: 20,
                        color: _publishing ? Colors.grey : Colors.deepOrange,
                      ),
                      const SizedBox(width: 12),
                      const Text('Yayınla'),
                    ],
                  ),
                ),
              if (widget.cycle.status == AgmCycleStatus.published)
                PopupMenuItem(
                  value: 'unpublish',
                  enabled: !_publishing,
                  child: Row(
                    children: [
                      Icon(
                        Icons.cancel_presentation,
                        size: 20,
                        color: _publishing ? Colors.grey : Colors.red.shade700,
                      ),
                      const SizedBox(width: 12),
                      const Text('Yayından Kaldır'),
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
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: 13),
          tabs: [
            const Tab(text: 'Gruplar'),
            Tab(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Yerleşemeyenler'),
                    if ((_absentStudents.length +
                            _unassignedStudents.length +
                            _underAssignedStudents.length) >
                        0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_absentStudents.length + _unassignedStudents.length + _underAssignedStudents.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Tab(text: 'Raporlar'),
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
                    _buildGroupsTab(),
                    _buildAbsentTab(),
                    _buildReportsTab(),
                  ],
                ),
        ),
      ),
      bottomNavigationBar: _selectedStudentIds.isNotEmpty
          ? _buildBulkActionBar()
          : null,
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          if (_selectedStudentIds.isNotEmpty) return const SizedBox.shrink();

          if (_tabController.index == 0) {
            return widget.cycle.status == AgmCycleStatus.draft
                ? FloatingActionButton.extended(
                    onPressed: _generating ? null : _showGenerateDraftSheet,
                    label: Text(
                      _generating ? 'Oluşturuluyor...' : 'Taslak Oluştur',
                    ),
                    icon: _generating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.auto_fix_high),
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                  )
                : const SizedBox.shrink();
          }

          if (_tabController.index == 1) {
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

  // ─── GRUPLAR TAB ─────────────────────────────────────────────────────────

  Widget _buildGroupsTab() {
    if (_groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_outlined, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Grup yok',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              '"Taslak Oluştur" butonuna basarak\nalgoritmanın çalışmasını sağlayın.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ),
      );
    }

    // Gruplama: gün bazlı — saat sırasına göre
    final Map<String, List<AgmGroup>> byDay = {};
    final Set<String> allGroupBranches = _groups.map((g) => g.dersAdi).toSet();

    for (final g in _groups) {
      if (_groupFilterBranch != null && g.dersAdi != _groupFilterBranch) {
        continue;
      }
      byDay.putIfAbsent(g.gun, () => []).add(g);
    }

    // Her gün içinde saate göre sırala, aynı saattekiler peşpeşe
    byDay.forEach((day, groups) {
      groups.sort((a, b) {
        final cmp = a.baslangicSaat.compareTo(b.baslangicSaat);
        if (cmp != 0) return cmp;
        return a.bitisSaat.compareTo(b.bitisSaat);
      });
    });

    // Günleri de sırala
    final sortedDays = byDay.keys.toList()
      ..sort(); // Alfabetik sıralama (Cuma, Cumartesi, Pazartesi...)

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCycleSummaryBar(),
        const SizedBox(height: 16),
        _buildGroupFilterRow(allGroupBranches.toList()..sort()),
        const SizedBox(height: 12),
        ...sortedDays.map((day) {
          final groups = byDay[day]!;
          // Saat dilimlerine göre grupla (aynı saat dilimindekiler altına)
          // Grup kartları arasında saat dilimi değişince ayırıcı koy
          String? lastSlot;
          final widgets = <Widget>[];
          for (final g in groups) {
            final slotKey = '${g.baslangicSaat}-${g.bitisSaat}';
            if (lastSlot != null && slotKey != lastSlot) {
              widgets.add(const SizedBox(height: 4));
              widgets.add(Divider(color: Colors.grey.shade200, height: 1));
              widgets.add(const SizedBox(height: 4));
            }
            widgets.add(_buildGroupCard(g));
            lastSlot = slotKey;
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDayHeader(day),
              const SizedBox(height: 8),
              ...widgets,
              const SizedBox(height: 8),
            ],
          );
        }),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildCycleSummaryBar() {
    final totalAssignments = _assignmentsByGroup.values.fold(
      0,
      (sum, list) => sum + list.length,
    );
    final totalUnplaced =
        _unassignedStudents.length +
        _underAssignedStudents.length +
        _absentStudents.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepOrange.shade400, Colors.deepOrange.shade700],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _statItem('${_groups.length}', 'Grup'),
          _divider(),
          _statItem('${_allBranchStudents.length}', 'Öğrenci'),
          _divider(),
          _statItem('$totalAssignments', 'Atama'),
          _divider(),
          _statItem('$totalUnplaced', 'Yerleşmedi'),
        ],
      ),
    );
  }

  Widget _statItem(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(
      height: 30,
      width: 1,
      color: Colors.white30,
      margin: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  Widget _buildGroupFilterRow(List<String> branches) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.deepOrange.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Cumartesi', // Not: AGM şu an sadece Cumartesi odaklı olabilir veya slot gününden gelir.
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.deepOrange.shade700,
              fontSize: 12,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButton<String>(
            value: _groupFilterBranch,
            underline: const SizedBox(),
            hint: const Text('Tüm Branşlar', style: TextStyle(fontSize: 12)),
            style: const TextStyle(fontSize: 12, color: Colors.black87),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('Tüm Branşlar'),
              ),
              ...branches.map(
                (b) => DropdownMenuItem<String>(value: b, child: Text(b)),
              ),
            ],
            onChanged: (v) => setState(() => _groupFilterBranch = v),
          ),
        ),
      ],
    );
  }

  Widget _buildDayHeader(String gun) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        gun,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: Colors.deepOrange.shade700,
        ),
      ),
    );
  }

  Widget _buildGroupCard(AgmGroup group) {
    final assignments = _assignmentsByGroup[group.id] ?? [];
    final doluluk = group.kapasite > 0
        ? assignments.length / group.kapasite
        : 0.0;

    Color dolulukRenk = Colors.green;
    if (doluluk >= 1.0) {
      dolulukRenk = Colors.red;
    } else if (doluluk >= 0.8) {
      dolulukRenk = Colors.orange;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.deepOrange.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.book_outlined, color: Colors.deepOrange, size: 22),
        ),
        title: Text(
          group.dersAdi,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${group.baslangicSaat}-${group.bitisSaat} • ${group.ogretmenAdi}${group.derslikAdi != null ? ' (${group.derslikAdi})' : ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            if (group.kazanimlar.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Ana Kazanım: ${group.kazanimlar.first}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.deepOrange.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        trailing: SizedBox(
          width: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${assignments.length}/${group.kapasite}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: dolulukRenk,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 3),
              SizedBox(
                width: 48,
                height: 4,
                child: LinearProgressIndicator(
                  value: doluluk.clamp(0.0, 1.0),
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(dolulukRenk),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (_selectedStudentIds.isEmpty) ...[
                const SizedBox(height: 3),
                _buildGroupAvgBadge(group),
              ] else if (assignments.any(
                (a) => _selectedStudentIds.contains(a.ogrenciId),
              )) ...[
                const SizedBox(height: 3),
                // Küçük "temizle" ikonu — overflow yaratmaz
                GestureDetector(
                  onTap: () => setState(() => _selectedStudentIds.clear()),
                  child: Tooltip(
                    message: 'Seçimleri Temizle',
                    child: Icon(
                      Icons.cancel,
                      size: 16,
                      color: Colors.deepOrange.shade400,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        children: [
          if (group.kazanimlar.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kazanımlar (1 Ana + 2 Yardımcı)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.deepOrange,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ...group.kazanimlar.take(3).toList().asMap().entries.map((
                        entry,
                      ) {
                        final index = entry.key;
                        final k = entry.value;
                        return ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 280),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.deepOrange.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.deepOrange.shade100,
                              ),
                            ),
                            child: Text(
                              index == 0 ? 'Ana: $k' : 'Yard: $k',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: index == 0
                                    ? Colors.deepOrange.shade900
                                    : Colors.grey.shade700,
                                fontWeight: index == 0
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }),
                      if (group.kazanimlar.length > 3)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '+${group.kazanimlar.length - 3}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Divider(color: Colors.grey.shade200),
                ],
              ),
            ),
          if (assignments.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Bu grupta öğrenci yok.'),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: assignments.length,
              itemBuilder: (context, i) {
                final a = assignments[i];
                final isSelected = _selectedStudentIds.contains(a.ogrenciId);

                return InkWell(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedStudentIds.remove(a.ogrenciId);
                      } else {
                        _selectedStudentIds.add(a.ogrenciId);
                      }
                    });
                  },
                  child: Container(
                    color: isSelected
                        ? Colors.deepOrange.shade50.withOpacity(0.5)
                        : null,
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 12,
                        backgroundColor: isSelected
                            ? Colors.deepOrange
                            : Colors.deepOrange.shade50,
                        child: isSelected
                            ? const Icon(
                                Icons.check,
                                size: 12,
                                color: Colors.white,
                              )
                            : Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  color: Colors.deepOrange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                      ),
                      title: Row(
                        children: [
                          CircleAvatar(
                            radius: 10,
                            backgroundColor: Colors.grey.shade200,
                            child: Text(
                              a.ogrenciAdi.isNotEmpty
                                  ? a.ogrenciAdi[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 9,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              a.ogrenciAdi,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          // Öğrencinin bu gruptaki kazanım başarı %si
                          _buildStudentScoreBadge(a, group),
                        ],
                      ),
                      subtitle: Text(
                        a.subeAdi,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (a.atamaTipi == AgmAssignmentType.manual)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Manuel',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ),
                          IconButton(
                            icon: Icon(
                              isSelected ? Icons.close : Icons.swap_horiz,
                              size: 18,
                              color: isSelected
                                  ? Colors.red.shade400
                                  : Colors.grey.shade500,
                            ),
                            onPressed: () {
                              if (isSelected) {
                                _removeStudentsFromGroup([a]);
                              } else {
                                _showMoveDialog([a], group);
                              }
                            },
                            tooltip: isSelected
                                ? 'Gruptan Çıkar'
                                : 'Grubu değiştir',
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ─── YARDIMCI WIDGETLAR ────────────────────────────────────────────────────

  /// Grubun ortalama başarı yüzdesi (ihtiyacSkoru'ndan hesapla)
  Widget _buildGroupAvgBadge(AgmGroup group) {
    final assignments = _assignmentsByGroup[group.id] ?? [];
    if (assignments.isEmpty) return const SizedBox.shrink();

    double total = 0;
    for (final a in assignments) {
      total += (1.0 - a.ihtiyacSkoru).clamp(0.0, 1.0);
    }
    final avg = total / assignments.length;
    final pct = (avg * 100).toStringAsFixed(0);
    final color = avg < 0.4
        ? Colors.red.shade600
        : avg < 0.7
        ? Colors.orange.shade700
        : Colors.green.shade600;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Ort. %$pct',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(width: 2),
        GestureDetector(
          onTap: () => _showSwapGroupDialog(group),
          child: Tooltip(
            message: 'Bu grubu başka öğretmenle takas et',
            child: Icon(
              Icons.compare_arrows,
              size: 13,
              color: Colors.grey.shade500,
            ),
          ),
        ),
      ],
    );
  }

  /// Öğrencinin ihtiyacSkoru'ndan hesaplanmış başarı badge'i
  Widget _buildStudentScoreBadge(AgmAssignment a, AgmGroup group) {
    final basari = (1.0 - a.ihtiyacSkoru).clamp(0.0, 1.0);
    final pct = (basari * 100).toStringAsFixed(0);
    final color = basari < 0.4
        ? Colors.red.shade400
        : basari < 0.7
        ? Colors.orange.shade600
        : Colors.green.shade500;
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        '%$pct',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  // ─── GRUP TAKAS DİALOGU ───────────────────────────────────────────────────

  void _showSwapGroupDialog(AgmGroup groupA) {
    AgmGroup? groupB;

    // Aynı branş (dersAdi) VE aynı saat diliminde olan gruplara kısıtla
    final sameSlotGroups = _groups.where((g) {
      return g.id != groupA.id &&
          g.dersAdi == groupA.dersAdi && // Aynı branş zorunlu
          g.baslangicSaat == groupA.baslangicSaat &&
          g.bitisSaat == groupA.bitisSaat &&
          g.gun == groupA.gun;
    }).toList();

    if (sameSlotGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aynı saatte başka grup bulunamadı.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.compare_arrows, color: Colors.deepOrange.shade400),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Grup Takası', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bu gruptaki tüm öğrenciler ve kazanımlar seçilen grupla takas edilir.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Grup A (Mevcut)',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.deepOrange.shade700,
                        ),
                      ),
                      Text(
                        groupA.dersAdi,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${groupA.baslangicSaat}-${groupA.bitisSaat} • ${groupA.ogretmenAdi}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      Text(
                        '${_assignmentsByGroup[groupA.id]?.length ?? 0} öğrenci',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Icon(
                    Icons.swap_vert,
                    color: Colors.grey.shade400,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<AgmGroup>(
                  value: groupB,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Takas Edilecek Grubu Seçin',
                    labelStyle: const TextStyle(fontSize: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    prefixIcon: const Icon(Icons.group_outlined),
                  ),
                  items: sameSlotGroups.map((g) {
                    final cnt = _assignmentsByGroup[g.id]?.length ?? 0;
                    return DropdownMenuItem<AgmGroup>(
                      value: g,
                      child: Text(
                        '${g.dersAdi} • ${g.ogretmenAdi} ($cnt öğr.)',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  }).toList(),
                  onChanged: (v) => setSt(() => groupB = v),
                ),
                if (groupB != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Grup B (Hedef)',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.blue.shade700,
                          ),
                        ),
                        Text(
                          groupB!.dersAdi,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '${groupB!.baslangicSaat}-${groupB!.bitisSaat} • ${groupB!.ogretmenAdi}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        Text(
                          '${_assignmentsByGroup[groupB!.id]?.length ?? 0} öğrenci',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            ElevatedButton.icon(
              onPressed: groupB == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      await _executeSwapGroups(groupA, groupB!);
                    },
              icon: const Icon(Icons.compare_arrows, size: 16),
              label: const Text('Takası Uygula'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeSwapGroups(AgmGroup groupA, AgmGroup groupB) async {
    setState(() => _loading = true);
    try {
      final batch = _db.batch();
      final assignmentsA = List<AgmAssignment>.from(
        _assignmentsByGroup[groupA.id] ?? [],
      );
      final assignmentsB = List<AgmAssignment>.from(
        _assignmentsByGroup[groupB.id] ?? [],
      );

      // 1) Öğrencileri takas et: A→B, B→A
      for (final a in assignmentsA) {
        batch.update(_db.collection('agm_assignments').doc(a.id), {
          'groupId': groupB.id,
          'groupName': '${groupB.dersAdi} - ${groupB.ogretmenAdi}',
        });
      }
      for (final a in assignmentsB) {
        batch.update(_db.collection('agm_assignments').doc(a.id), {
          'groupId': groupA.id,
          'groupName': '${groupA.dersAdi} - ${groupA.ogretmenAdi}',
        });
      }

      // 2) Kazanımları da takas et:
      //    Öğrenciler eksikliği olan kazanımla birlikte taşındığı için
      //    hedef grup da o kazanımı almalı — mantık bozulmasın.
      final kazanimlarA = groupA.kazanimlar;
      final kazanimlarB = groupB.kazanimlar;

      batch.update(_db.collection('agm_groups').doc(groupA.id), {
        'kazanimlar': kazanimlarB, // A artık B'nin kazanımlarını çalışacak
      });
      batch.update(_db.collection('agm_groups').doc(groupB.id), {
        'kazanimlar': kazanimlarA, // B artık A'nın kazanımlarını çalışacak
      });

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Takas tamamlandı: ${assignmentsA.length} + ${assignmentsB.length} '
              'öğrenci ve kazanımlar yer değiştirdi.',
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Takas sırasında hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _loading = false);
      }
    }
  }

  Widget _buildAbsentTab() {
    return Column(
      children: [
        // Sub-filter tabs
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: Row(
            children: [
              _filterChip(0, 'Sınava Girmeyenler', _absentStudents.length),
              const SizedBox(width: 8),
              _filterChip(1, 'Atanamayanlar', _unassignedStudents.length),
              const SizedBox(width: 8),
              _filterChip(2, 'Eksik Atananlar', _underAssignedStudents.length),
            ],
          ),
        ),

        Expanded(
          child: _yerlesmeyenFilterIndex == 0
              ? _buildStudentList(_absentStudents)
              : _buildStudentList(_getMappedStudents(_yerlesmeyenFilterIndex)),
        ),
      ],
    );
  }

  // ─── RAPORLAR TAB ────────────────────────────────────────────────────────

  Widget _buildReportsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildReportTile(
            icon: Icons.history,
            title: 'İşlem ve Değişiklik Logu',
            subtitle: 'Yapılan manuel atama ve değişiklikler',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AgmReportsScreen(
                  institutionId: widget.cycle.institutionId,
                  cycleId: widget.cycle.id,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildReportTile(
            icon: Icons.calendar_view_week,
            title: 'Öğrenci Haftalık Takvim',
            subtitle: 'Bir öğrencinin etüt programı',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AgmStudentTimetableScreen(
                  cycle: widget.cycle,
                  groups: _groups,
                  assignmentsByGroup: _assignmentsByGroup,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildReportTile(
            icon: Icons.badge,
            title: 'Öğretmen Haftalık Takvim',
            subtitle: 'Öğretmen bazlı program ve öğrenci listesi',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AgmTeacherTimetableScreen(
                  cycle: widget.cycle,
                  groups: _groups,
                  assignmentsByGroup: _assignmentsByGroup,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildReportTile(
            icon: Icons.meeting_room,
            title: 'Derslik Haftalık Takvim',
            subtitle: 'Derslik bazlı program ve detaylar',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AgmClassroomTimetableScreen(
                  cycle: widget.cycle,
                  groups: _groups,
                  assignmentsByGroup: _assignmentsByGroup,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.deepOrange.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.deepOrange),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: onTap,
      ),
    );
  }

  // ─── TASLAK OLUŞTURMA – BOTTOM SHEET ─────────────────────────────────────

  void _showGenerateDraftSheet() {
    final availableSubjects = _groups.map((g) => g.dersAdi).toSet().toList()
      ..sort();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DraftGenerateSheet(
        cycle: widget.cycle,
        availableSubjects: availableSubjects,
        onGenerate: _generateDraft,
      ),
    );
  }

  Future<void> _generateDraft({
    required double esikBasariOrani,
    required bool sadeceDusukBasari,
    required Map<String, double> dersBazliEsikler,
  }) async {
    setState(() => _generating = true);
    Navigator.pop(context); // Sheet'i kapat

    try {
      // 1) Sınav dökümanını çek (resultsJson + selectedBranches)
      _showProgress('Sınav verileri yükleniyor...');
      final examDoc = await _db
          .collection('trial_exams')
          .doc(widget.cycle.referansDenemeSinavId)
          .get();

      if (!examDoc.exists) {
        _showError(
          'Referans sınav bulunamadı. Lütfen önce sınavı değerlendirin.',
        );
        return;
      }

      final examData = examDoc.data()!;
      final resultsJson = examData['resultsJson'] as String?;
      if (resultsJson == null || resultsJson.isEmpty) {
        _showError(
          'Bu sınava ait değerlendirme sonucu bulunamadı.\nLütfen önce sınavı değerlendirin (Optik Okuma / Toplu Değerlendirme).',
        );
        return;
      }

      final selectedBranches =
          (examData['selectedBranches'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList();
      final classLevel = examData['classLevel']?.toString() ?? '';

      // 2) Sonuçları parse et
      _showProgress('Öğrenci sonuçları analiz ediliyor...');
      final List<dynamic> jsonList = jsonDecode(resultsJson);
      final examResults = jsonList
          .map((e) => StudentResult.fromJson(e))
          .toList();

      // Sisteme eşleşmiş kayıtlar
      final matchedResults = examResults
          .where((r) => r.systemStudentId != null)
          .toList();

      // 3) Şube öğrencilerini Firestore'dan çek
      _showProgress('Şube öğrencileri yükleniyor...');
      final List<Map<String, dynamic>> branchStudents = [];

      if (selectedBranches.isNotEmpty && classLevel.isNotEmpty) {
        for (final branch in selectedBranches) {
          final snap = await _db
              .collection('students')
              .where('institutionId', isEqualTo: widget.cycle.institutionId)
              .where('className', isEqualTo: branch)
              .where('isActive', isEqualTo: true)
              .get();
          for (final doc in snap.docs) {
            final data = Map<String, dynamic>.from(doc.data());
            data['id'] = doc.id;
            branchStudents.add(data);
          }
        }
      } else {
        // Fallback: sadece kurum filtreli + classLevel
        final snap = await _db
            .collection('students')
            .where('institutionId', isEqualTo: widget.cycle.institutionId)
            .where('classLevel', isEqualTo: classLevel)
            .where('isActive', isEqualTo: true)
            .get();
        for (final doc in snap.docs) {
          final data = Map<String, dynamic>.from(doc.data());
          data['id'] = doc.id;
          branchStudents.add(data);
        }
      }

      // 4) Sınava girmeyenleri bul
      _showProgress('Sınava girmeyenler tespit ediliyor...');
      final sinavaGirenIds = matchedResults
          .map((r) => r.systemStudentId!)
          .toSet();

      final absent = branchStudents
          .where((s) => !sinavaGirenIds.contains(s['id']))
          .map(
            (s) => {
              'id': s['id'],
              'name': (s['fullName'] ?? s['name'] ?? 'İsimsiz').toString(),
              'branch': (s['className'] ?? s['branch'] ?? '').toString(),
              'subeId': s['branchId'] ?? '',
            },
          )
          .toList();

      // 5) StudentNeedProfile oluştur
      _showProgress('Öğrenci ihtiyaç profilleri hesaplanıyor...');
      final List<StudentNeedProfile> profiller = [];

      // Kazanımları çek (TrialExam dökümanından)
      final outcomesMapRaw =
          examData['outcomes'] as Map<String, dynamic>? ?? {};
      // Booklet -> Subject -> List<String>
      final Map<String, Map<String, List<String>>> examOutcomes = {};
      outcomesMapRaw.forEach((booklet, subjects) {
        if (subjects is Map<String, dynamic>) {
          examOutcomes[booklet] = subjects.map(
            (k, v) => MapEntry(
              k,
              (v as List<dynamic>).map((e) => e.toString()).toList(),
            ),
          );
        }
      });

      for (final result in matchedResults) {
        if (result.subjects.isEmpty) continue;

        final Map<String, double> dersIhtiyaclari = {};
        final Map<String, Set<String>> kazanimIhtiyaclari = {};
        final Map<String, double> dersBasariOranlari = {};

        result.subjects.forEach((dersAdi, stats) {
          final toplam = stats.correct + stats.wrong + stats.empty;
          if (toplam <= 0) return;
          final basariOrani = stats.correct / toplam;
          final ihtiyac = 1.0 - basariOrani;

          final aktifEsik = dersBazliEsikler.containsKey(dersAdi)
              ? dersBazliEsikler[dersAdi]!
              : esikBasariOrani;

          if (!sadeceDusukBasari || basariOrani <= aktifEsik) {
            dersIhtiyaclari[dersAdi] = ihtiyac;
            dersBasariOranlari[dersAdi] = basariOrani;

            // Kazanım bazlı analiz
            final studentAnswers = result.answers[dersAdi] ?? '';
            final correctAnswers = result.correctAnswers[dersAdi] ?? '';
            final booklet = result.booklet.isNotEmpty ? result.booklet[0] : 'A';
            final subjectOutcomes = examOutcomes[booklet]?[dersAdi] ?? [];

            final Set<String> weakOutcomes = {};
            for (
              int i = 0;
              i < studentAnswers.length && i < correctAnswers.length;
              i++
            ) {
              if (studentAnswers[i] != correctAnswers[i] &&
                  i < subjectOutcomes.length) {
                // Yanlış veya boş soru -> Kazanım zayıf
                final kazanim = subjectOutcomes[i];
                if (kazanim.isNotEmpty && kazanim != '-') {
                  weakOutcomes.add(kazanim);
                }
              }
            }
            if (weakOutcomes.isNotEmpty) {
              kazanimIhtiyaclari[dersAdi] = weakOutcomes;
            }
          }
        });

        if (dersIhtiyaclari.isEmpty) continue;

        final studentData = branchStudents.firstWhere(
          (s) => s['id'] == result.systemStudentId,
          orElse: () => {},
        );

        profiller.add(
          StudentNeedProfile(
            ogrenciId: result.systemStudentId!,
            ogrenciAdi: studentData.isNotEmpty
                ? (studentData['fullName'] ??
                          studentData['name'] ??
                          result.name)
                      .toString()
                : result.name,
            subeId: studentData['branchId']?.toString() ?? '',
            subeAdi:
                (studentData['className'] ??
                        studentData['branch'] ??
                        result.branch)
                    .toString(),
            dersIhtiyaclari: dersIhtiyaclari,
            kazanimIhtiyaclari: kazanimIhtiyaclari,
            dersBasariOranlari: dersBasariOranlari,
          ),
        );
      }

      if (profiller.isEmpty) {
        _showError(
          'Analiz edilecek student profili bulunamadı.\n'
          'Sınavda en az 1 eşleşmiş öğrenci ve değerlendirilmiş ders olması gerekir.',
        );
        return;
      }

      // 6) Grupları yükle
      _showProgress('Gruplar yükleniyor...');
      if (_groups.isEmpty) {
        _showError(
          'Henüz grup tanımlanmamış. Lütfen önce saat dilimleri ve grupları oluşturun.',
        );
        return;
      }

      // 7) Algoritmayı çalıştır
      _showProgress('Algoritma çalışıyor (${profiller.length} öğrenci)...');
      final draftResult = await _service.generateDraft(
        cycle: widget.cycle,
        ogrenciProfiller: profiller,
        gruplar: _groups,
      );

      // 8) State ve Firestore güncelle (Persistence için)
      if (mounted) {
        setState(() {
          _allBranchStudents = branchStudents;
          _absentStudents = absent;
          _unassignedStudents = draftResult.yerlesmeyenOgrenciIds;
          _underAssignedStudents = draftResult.eksikAtananOgrenciIds;
        });
      }

      await _db.collection('agm_cycles').doc(widget.cycle.id).update({
        'unassignedStudentIds': draftResult.yerlesmeyenOgrenciIds,
        'underAssignedStudentIds': draftResult.eksikAtananOgrenciIds,
        'absentStudentIds': absent.map((a) => a['id'].toString()).toList(),
      });

      // 8.1) Manuel Nedenleri Enjekte Et (Sınava Girmeyenler & Başarılılar)
      final Map<String, List<String>> allReasons = Map.from(
        draftResult.yerlesmemeNedenleri,
      );
      final List<String> yerlesmeyenIds = List<String>.from(
        draftResult.yerlesmeyenOgrenciIds,
      );

      // Sınava girmeyenlere neden ekle
      for (final a in absent) {
        final id = a['id'].toString();
        allReasons
            .putIfAbsent(id, () => [])
            .add('Sınava girmedi analiz verisi yok.');
      }

      // Eşik altı dersi olmadığı için profiller listesine hiç girmeyenleri bul
      final List<String> profileIds = profiller
          .map((p) => p.ogrenciId)
          .toList();
      final sinavaGirenIdsList = sinavaGirenIds.toList();
      for (final sid in sinavaGirenIdsList) {
        if (!profileIds.contains(sid)) {
          allReasons
              .putIfAbsent(sid, () => [])
              .add('Belirlenen başarı eşiğinin altında dersi yok.');
          // Bu başarılı öğrencileri "Yerleşmeyenler" listesine ekleyelim ki UI'da görünsünler
          if (!yerlesmeyenIds.contains(sid)) {
            yerlesmeyenIds.add(sid);
          }
        }
      }

      if (mounted) {
        setState(() {
          _unassignedStudents = yerlesmeyenIds;
          _unassignedReasons = allReasons;
        });
      }

      await _db.collection('agm_cycles').doc(widget.cycle.id).update({
        'unassignedStudentIds': yerlesmeyenIds,
        'underAssignedStudentIds': draftResult.eksikAtananOgrenciIds,
        'absentStudentIds': absent.map((a) => a['id'].toString()).toList(),
        'unassignedReasons': allReasons,
      });

      // 9) Atamaları yeniden yükle
      await _loadData();

      // Uyarıları göster
      if (draftResult.softUyarilar.isNotEmpty) {
        _showSoftWarnings(draftResult.softUyarilar);
      } else {
        _showSuccess(
          '✅ Taslak oluşturuldu!\n'
          '${draftResult.atamalar.length} atama yapıldı, '
          '${draftResult.yerlesmeyenOgrenciIds.length} öğrenci yerleşemedi, '
          '${absent.length} öğrenci sınava girmedi.',
        );
      }
    } catch (e) {
      _showError('Taslak oluşturulurken hata: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _showProgress(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        duration: const Duration(seconds: 30),
        backgroundColor: Colors.deepOrange.shade700,
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _showSoftWarnings(List<AgmSoftWarning> uyarilar) {
    ScaffoldMessenger.of(context).clearSnackBars();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            const Text('Soft Kısıt Uyarıları'),
          ],
        ),
        content: SizedBox(
          width: 400,
          height: 300,
          child: ListView.builder(
            itemCount: uyarilar.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '• ${uyarilar[i].mesaj}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  // ─── MANUEl ATAMA (SINAVA GİRMEYEN) ─────────────────────────────────────

  // [x] Research current `_showManualAssignForAbsent` implementation <!-- id: 0 -->
  // [x] Identify why the "Assign" button remains inactive <!-- id: 1 -->
  // [x] Plan improvements for group info display <!-- id: 2 -->
  // [x] Design branch filter for group selection <!-- id: 3 -->
  // [x] Design confirmation step for full groups <!-- id: 4 -->

  // ## Execution
  // [/] Fix "Assign" button inactivity <!-- id: 5 -->
  // [/] Implement enhanced group info display <!-- id: 6 -->
  // [/] Implement branch filter <!-- id: 7 -->
  // [/] Implement confirmation dialog for full groups <!-- id: 8 -->
  void _showManualAssignForAbsent(Map<String, dynamic> student) {
    if (_groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Atanacak grup bulunamadı.')),
      );
      return;
    }

    final studentId = student['id'] as String;

    // Öğrencinin atanmış olduğu grupların ID'leri
    final assignedGroupIds = _assignmentsByGroup.entries
        .where((e) => e.value.any((a) => a.ogrenciId == studentId))
        .map((e) => e.key)
        .toSet();

    final assignedSubjects = <String>{};
    final occupiedTimeSlots = <String>{};
    for (final grup in _groups) {
      if (assignedGroupIds.contains(grup.id)) {
        assignedSubjects.add(grup.dersAdi);
        occupiedTimeSlots.add(grup.saatDilimiId);
      }
    }

    final availableGroups = _groups
        .where(
          (g) =>
              !assignedSubjects.contains(g.dersAdi) &&
              !occupiedTimeSlots.contains(g.saatDilimiId),
        )
        .toList();

    final subjects = availableGroups.map((g) => g.dersAdi).toSet().toList()
      ..sort();

    if (subjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bu öğrenci için atanabilecek uygun ders veya boş saat dilimi bulunamadı.',
          ),
        ),
      );
      return;
    }

    String? selectedSubject;
    AgmGroup? selectedGroup;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSt) {
          // Seçili derse göre grupları filtrele
          final filteredGroups = selectedSubject == null
              ? <AgmGroup>[]
              : availableGroups
                    .where((g) => g.dersAdi == selectedSubject)
                    .toList();

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student['name'],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Sube: ${student['branch']}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ders Seçin',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  value: selectedSubject,
                  isExpanded: true,
                  hint: const Text('Ders seçin'),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  items: subjects
                      .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                      .toList(),
                  onChanged: (v) => setSt(() {
                    selectedSubject = v;
                    selectedGroup = null;
                  }),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Grup Seçin (Öğretmen - Saat)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                DropdownButtonFormField<AgmGroup>(
                  value: selectedGroup,
                  hint: const Text('Grup seçin'),
                  isExpanded: true,
                  itemHeight: 70,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  selectedItemBuilder: (context) {
                    return filteredGroups.map((g) {
                      return Text(
                        '${g.ogretmenAdi} • ${g.baslangicSaat}-${g.bitisSaat}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      );
                    }).toList();
                  },
                  items: filteredGroups.map((g) {
                    final currentCount = _assignmentsByGroup[g.id]?.length ?? 0;
                    final isFull = currentCount >= g.kapasite;

                    return DropdownMenuItem<AgmGroup>(
                      value: g,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    g.ogretmenAdi,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${g.baslangicSaat}-${g.bitisSaat} • ${g.gun}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  if (g.kazanimlar.isNotEmpty)
                                    Text(
                                      g.kazanimlar.join(', '),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.deepOrange.shade400,
                                        fontStyle: FontStyle.italic,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isFull
                                    ? Colors.red.shade50
                                    : Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isFull
                                      ? Colors.red.shade200
                                      : Colors.green.shade200,
                                ),
                              ),
                              child: Text(
                                '$currentCount/${g.kapasite}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isFull
                                      ? Colors.red.shade700
                                      : Colors.green.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (v) => setSt(() => selectedGroup = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                onPressed: selectedGroup == null
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        setState(() => _loading = true);
                        try {
                          await _service.manualAssign(
                            cycleId: widget.cycle.id,
                            ogrenciId: student['id'],
                            ogrenciAdi: student['name'],
                            subeId: student['subeId'] ?? '',
                            subeAdi: student['branch'],
                            yeniGrupId: selectedGroup!.id,
                            yeniGrupAdi:
                                '${selectedGroup!.dersAdi} – ${selectedGroup!.saatDilimiAdi}',
                            isAbsent: _yerlesmeyenFilterIndex == 0,
                          );
                          await _loadData();
                        } catch (e) {
                          _showError('Manuel atama hatası: $e');
                        } finally {
                          if (mounted) setState(() => _loading = false);
                        }
                      },
                child: const Text('Ata'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _removeStudentsFromGroup(List<AgmAssignment> studentsToRemove) {
    if (studentsToRemove.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade400),
            const SizedBox(width: 8),
            const Text('Gruptan Çıkar'),
          ],
        ),
        content: Text(
          studentsToRemove.length == 1
              ? '${studentsToRemove.first.ogrenciAdi} adlı öğrenciyi gruptan çıkarmak istediğinize emin misiniz? Öğrenci yerleşemeyenler listesine eklenecektir.'
              : '${studentsToRemove.length} öğrenciyi gruptan çıkarmak istediğinize emin misiniz? Öğrenciler yerleşemeyenler listesine eklenecektir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                for (final a in studentsToRemove) {
                  _assignmentsByGroup[a.groupId]?.removeWhere(
                    (x) => x.ogrenciId == a.ogrenciId,
                  );

                  // Yerleşemeyenlere ekle
                  if (!_unassignedStudents.contains(a.ogrenciId)) {
                    _unassignedStudents.add(a.ogrenciId);
                  }

                  // Nedenlere ekle
                  final reasons = _unassignedReasons[a.ogrenciId] ?? [];
                  reasons.add('Kullanıcı tarafından gruptan çıkarıldı.');
                  _unassignedReasons[a.ogrenciId] = reasons;
                }
                _selectedStudentIds.clear();
              });

              // İsteğe bağlı: _saveDraftUpdates();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Çıkar'),
          ),
        ],
      ),
    );
  }

  void _showMoveDialog(
    List<AgmAssignment> studentsToMove, [
    AgmGroup? currentGroup,
  ]) {
    if (studentsToMove.isEmpty) return;

    String? selectedBranchId;
    AgmGroup? selectedGroup;
    bool override = false;

    // Grupları ders (branş) bazlı ve AYNI SAAT DİLİMİNDE OLACAK ŞEKİLDE grupla
    AgmGroup? originalGrp = currentGroup;
    if (originalGrp == null && studentsToMove.isNotEmpty) {
      final originId = studentsToMove.first.groupId;
      final found = _groups.where((g) => g.id == originId).toList();
      if (found.isNotEmpty) originalGrp = found.first;
    }

    final Map<String, List<AgmGroup>> groupsByBranch = {};
    for (final g in _groups) {
      // Orijinal grup bulunabiliyorsa, SADECE onunla aynı saat dilimine sahip grupları dahil et
      if (originalGrp != null && g.saatDilimiId != originalGrp.saatDilimiId) {
        continue;
      }
      groupsByBranch.putIfAbsent(g.dersAdi, () => []).add(g);
    }
    final sortedBranches = groupsByBranch.keys.toList()..sort();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSt) {
          final availableGroups = selectedBranchId != null
              ? groupsByBranch[selectedBranchId] ?? []
              : <AgmGroup>[];

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.swap_horiz, color: Colors.deepOrange.shade400),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    studentsToMove.length == 1
                        ? '${studentsToMove.first.ogrenciAdi} – Grubu Değiştir'
                        : '${studentsToMove.length} Öğrenciyi Taşı',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            content: Container(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Ders Seçimi
                  DropdownButtonFormField<String>(
                    value: selectedBranchId,
                    decoration: InputDecoration(
                      labelText: 'Ders / Branş Seçin',
                      labelStyle: const TextStyle(fontSize: 13),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.book_outlined),
                    ),
                    items: sortedBranches
                        .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                        .toList(),
                    onChanged: (v) {
                      setSt(() {
                        selectedBranchId = v;
                        selectedGroup = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // Grup Seçimi
                  DropdownButtonFormField<AgmGroup>(
                    value: selectedGroup,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Grup Seçin',
                      labelStyle: const TextStyle(fontSize: 13),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.group_outlined),
                    ),
                    items: availableGroups.map((g) {
                      final currentCount =
                          _assignmentsByGroup[g.id]?.length ?? 0;
                      final isFull = currentCount >= g.kapasite;
                      return DropdownMenuItem<AgmGroup>(
                        value: g,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${g.ogretmenAdi} (${g.baslangicSaat}-${g.bitisSaat})',
                              style: TextStyle(
                                fontSize: 13,
                                color: isFull ? Colors.red : Colors.black87,
                              ),
                            ),
                            Text(
                              '${g.derslikAdi ?? "-"} • $currentCount/${g.kapasite} Doluluk',
                              style: TextStyle(
                                fontSize: 11,
                                color: isFull
                                    ? Colors.red
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: selectedBranchId == null
                        ? null
                        : (v) => setSt(() => selectedGroup = v),
                  ),

                  if (selectedGroup != null) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    // Kapasite Aşımı Kotrolü (Seçilen grup için)
                    () {
                      final currentCount =
                          _assignmentsByGroup[selectedGroup!.id]?.length ?? 0;
                      final isFull = currentCount >= selectedGroup!.kapasite;

                      if (isFull) {
                        return CheckboxListTile(
                          value: override,
                          onChanged: (v) => setSt(() => override = v ?? false),
                          title: const Text(
                            'Kapasite aşımına onay ver',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.orange,
                            ),
                          ),
                          subtitle: const Text(
                            'Bu grup dolu, yine de atama yapılsın.',
                            style: TextStyle(fontSize: 11),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          tileColor: Colors.orange.shade50,
                          dense: true,
                        );
                      }
                      return const SizedBox.shrink();
                    }(),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                onPressed:
                    selectedGroup == null ||
                        ((_assignmentsByGroup[selectedGroup!.id]?.length ??
                                    0) >=
                                selectedGroup!.kapasite &&
                            !override)
                    ? null
                    : () async {
                        Navigator.pop(context);
                        setState(() => _loading = true);

                        try {
                          for (final assignment in studentsToMove) {
                            await _service.moveStudent(
                              assignmentId: assignment.id,
                              cycleId: widget.cycle.id,
                              ogrenciId: assignment.ogrenciId,
                              ogrenciAdi: assignment.ogrenciAdi,
                              eskiGrupId: assignment.groupId,
                              eskiGrupAdi: assignment.groupName ?? '',
                              yeniGrupId: selectedGroup!.id,
                              yeniGrupAdi:
                                  '${selectedGroup!.dersAdi} – ${selectedGroup!.saatDilimiAdi}',
                              isOverride: override,
                            );
                          }
                          await _loadData();
                          setState(() => _selectedStudentIds.clear());
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${studentsToMove.length} öğrenci başarıyla taşındı.',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Hata: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _loading = false);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Taşı'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ─── TASLAK SIFIRLAMA ────────────────────────────────────────────────────

  Future<void> _confirmResetDraft() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.restart_alt, color: Colors.orange),
            SizedBox(width: 8),
            Text('Taslağı Sıfırla'),
          ],
        ),
        content: const Text(
          'Bu cycle\'a ait tüm öğrenci atamaları silinecek.\n'
          'Gruplar (ders/saat dilimleri) korunur.\n\n'
          '"Taslak Oluştur" ile yeniden algoritmayı çalıştırabilirsiniz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sıfırla'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await _repo.rollbackAssignments(widget.cycle.id);
      setState(() {
        _assignmentsByGroup = {for (final g in _groups) g.id: []};
        _absentStudents = [];
        _unassignedStudents = [];
        _underAssignedStudents = [];
        // Grupları yerel state'de de sıfırla
        _groups = _groups
            .map((g) => g.copyWith(mevcutOgrenciSayisi: 0, kazanimlar: []))
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Taslak sıfırlandı. Gruplar korundu.'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ─── PUBLISH ─────────────────────────────────────────────────────────────

  Future<void> _publish() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cycle Yayınla'),
        content: const Text(
          'Bu işlem geri alınamaz. Tüm atamalar etüt sistemine yazılacak '
          've bildirimler gönderilecektir. Onaylıyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Yayınla'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _publishing = true);
    try {
      final allAssignments = _assignmentsByGroup.values
          .expand((list) => list)
          .toList();

      await _service.publishCycle(
        cycle: widget.cycle,
        gruplar: _groups,
        atamalar: allAssignments,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cycle başarıyla yayınlandı!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // Go back after publish
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Yayınlama hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _unpublish() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yayından Kaldır'),
        content: const Text(
          'Bu cycle yayından kaldırılacak. Oluşturulan tüm etütler silinecek '
          've cycle tekrar aktif (düzenlenebilir) duruma geçecektir. Onaylıyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Yayından Kaldır'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _publishing = true);
    try {
      await _service.unpublishCycle(widget.cycle.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cycle yayından kaldırıldı.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // Go back after unpublish
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('İşlem sırasında hata oluştu: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Widget _filterChip(int index, String label, int count) {
    bool selected = _yerlesmeyenFilterIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _yerlesmeyenFilterIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.deepOrange : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? Colors.deepOrange : Colors.grey.shade300,
            ),
          ),
          child: Column(
            children: [
              Text(
                count.toString(),
                style: TextStyle(
                  color: selected ? Colors.white : Colors.deepOrange,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.grey.shade600,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getMappedStudents(int filterIndex) {
    final List<String> ids = filterIndex == 1
        ? _unassignedStudents
        : _underAssignedStudents;
    return _allBranchStudents
        .where((s) => ids.contains(s['id']))
        .map(
          (s) => {
            'id': s['id'],
            'name': (s['fullName'] ?? s['name'] ?? 'İsimsiz').toString(),
            'branch': (s['className'] ?? s['branch'] ?? '').toString(),
            'subeId': s['branchId'] ?? '',
          },
        )
        .toList();
  }

  Widget _buildStudentList(List<Map<String, dynamic>> students) {
    if (students.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 56,
              color: Colors.green.shade300,
            ),
            const SizedBox(height: 12),
            const Text('Bu kategoride öğrenci yok.'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: students.length,
      itemBuilder: (context, i) {
        final student = students[i];
        final name = student['name'] ?? 'İsimsiz';
        final branch = student['branch'] ?? '';
        final studentId = student['id']?.toString() ?? '';

        // Eksik atananlar için kaç ders aldığını gösterelim
        int? atananSayisi;
        if (_yerlesmeyenFilterIndex == 2) {
          atananSayisi = _assignmentsByGroup.values.fold<int>(
            0,
            (sum, list) =>
                sum + (list.any((a) => a.ogrenciId == studentId) ? 1 : 0),
          );
        }

        final reasons = _unassignedReasons[studentId] ?? [];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  setState(() {
                    _expandedStudentId = _expandedStudentId == studentId
                        ? null
                        : studentId;
                  });
                },
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  leading: CircleAvatar(
                    backgroundColor: Colors.deepOrange.shade50,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: Colors.deepOrange.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(branch, style: const TextStyle(fontSize: 12)),
                      if (reasons.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: reasons
                                .map(
                                  (r) => Text(
                                    '• $r',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.red.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        )
                      else if (atananSayisi != null && atananSayisi > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '$atananSayisi ders atandı',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  trailing: LayoutBuilder(
                    builder: (context, constraints) {
                      final isMobile = MediaQuery.of(context).size.width < 600;
                      if (isMobile) {
                        return PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (val) {
                            if (val == 'manual')
                              _showManualAssignForAbsent(student);
                            if (val == 'auto')
                              _autoAssignAbsentStudent(student);
                          },
                          itemBuilder: (ctx) => const [
                            PopupMenuItem(
                              value: 'manual',
                              child: Text('Manuel Ata'),
                            ),
                            PopupMenuItem(
                              value: 'auto',
                              child: Text('Otomatik Ata'),
                            ),
                          ],
                        );
                      }
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () =>
                                _showManualAssignForAbsent(student),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.deepOrange,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            child: const Text(
                              'Manuel Ata',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _autoAssignAbsentStudent(student),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.teal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            child: const Text(
                              'Otomatik Ata',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              if (_expandedStudentId == studentId) ...[
                const Divider(height: 1),
                _buildStudentQuickAssignArea(studentId, student),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildStudentQuickAssignArea(
    String studentId,
    Map<String, dynamic> student,
  ) {
    // Tüm saat dilimleri
    final Map<String, String> timeSlots = {};
    for (final g in _groups) {
      if (g.saatDilimiId.isNotEmpty) {
        timeSlots[g.saatDilimiId] = g.saatDilimiAdi;
      }
    }

    // Öğrencinin mevcut atamaları
    final studentAssignments = <String, AgmAssignment>{};
    final assignedSubjects = <String>{};
    for (final grup in _groups) {
      final assigns = _assignmentsByGroup[grup.id] ?? [];
      final assign = assigns.where((a) => a.ogrenciId == studentId).firstOrNull;
      if (assign != null) {
        studentAssignments[grup.saatDilimiId] = assign;
        assignedSubjects.add(grup.dersAdi);
      }
    }

    // Sıralı saat dilimleri
    final slotEntries = timeSlots.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    if (slotEntries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text(
          'Planlanmış saat dilimi veya grup bulunmamaktadır.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: slotEntries.map((slot) {
          final slotId = slot.key;
          final slotName = slot.value;

          final currentAssign = studentAssignments[slotId];
          final currentGroupId = currentAssign?.groupId;

          // Bu saat dilimindeki gruplar
          final groupsInSlot =
              _groups.where((g) => g.saatDilimiId == slotId).toList()
                ..sort((a, b) => a.dersAdi.compareTo(b.dersAdi));

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    slotName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: currentGroupId,
                    isExpanded: true,
                    isDense: true,
                    itemHeight: 50, // reduced for compactness
                    menuMaxHeight: 300, // limit dropdown height
                    icon: const Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.deepOrange,
                      size: 18,
                    ),
                    hint: const Text(
                      'Boş, Seçiniz',
                      style: TextStyle(fontSize: 11),
                    ),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.deepOrange.shade100,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.deepOrange.shade300,
                          width: 1.5,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text(
                          'Atama Yok (Boş)',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                      ...() {
                        // 1) Sort groups: available first, full/disabled last
                        final sortedGroups = List<AgmGroup>.from(groupsInSlot);
                        sortedGroups.sort((a, b) {
                          final aAssigns = _assignmentsByGroup[a.id] ?? [];
                          final aIsFull = aAssigns.length >= a.kapasite;
                          final aIsAlreadyInSubject =
                              assignedSubjects.contains(a.dersAdi) &&
                              currentGroupId != a.id;
                          final aDisabled = aIsFull || aIsAlreadyInSubject;

                          final bAssigns = _assignmentsByGroup[b.id] ?? [];
                          final bIsFull = bAssigns.length >= b.kapasite;
                          final bIsAlreadyInSubject =
                              assignedSubjects.contains(b.dersAdi) &&
                              currentGroupId != b.id;
                          final bDisabled = bIsFull || bIsAlreadyInSubject;

                          if (aDisabled && !bDisabled) return 1;
                          if (!aDisabled && bDisabled) return -1;
                          return a.dersAdi.compareTo(b.dersAdi);
                        });

                        return sortedGroups.map((g) {
                          final gAssigns = _assignmentsByGroup[g.id] ?? [];
                          final count = gAssigns.length;
                          final isFull = count >= g.kapasite;
                          final isAlreadyInSubject =
                              assignedSubjects.contains(g.dersAdi) &&
                              currentGroupId != g.id;

                          double totalSuccess = 0;
                          if (count > 0) {
                            for (final a in gAssigns) {
                              totalSuccess += (1.0 - a.ihtiyacSkoru) * 100;
                            }
                            totalSuccess /= count;
                          }
                          final successStr = count > 0
                              ? '(%${totalSuccess.toStringAsFixed(0)})'
                              : '';

                          Color successColor = Colors.grey.shade600;
                          if (count > 0) {
                            if (totalSuccess >= 70) {
                              successColor = Colors.green.shade600;
                            } else if (totalSuccess >= 40) {
                              successColor = Colors.orange.shade600;
                            } else {
                              successColor = Colors.red.shade600;
                            }
                          }

                          return DropdownMenuItem(
                            value: g.id,
                            enabled:
                                (!isFull && !isAlreadyInSubject) ||
                                g.id == currentGroupId,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${g.dersAdi} • ${g.ogretmenAdi}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        ((isFull || isAlreadyInSubject) &&
                                            g.id != currentGroupId)
                                        ? Colors.grey.shade400
                                        : Colors.black87,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Row(
                                  children: [
                                    Text(
                                      '$count/${g.kapasite} Dolu',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isFull
                                            ? Colors.red.shade400
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                    if (successStr.isNotEmpty) ...[
                                      const SizedBox(width: 4),
                                      Text(
                                        successStr,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: successColor,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          );
                        });
                      }(),
                    ],
                    onChanged: (newGroupId) async {
                      if (newGroupId != currentGroupId) {
                        await _quickAssignStudentToGroup(
                          student,
                          slotId,
                          currentAssign,
                          newGroupId,
                        );
                      }
                    },
                  ),
                ),
                if (currentGroupId != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () async {
                      await _quickAssignStudentToGroup(
                        student,
                        slotId,
                        currentAssign,
                        null,
                      );
                    },
                    icon: Icon(
                      Icons.close,
                      color: Colors.red.shade400,
                      size: 20,
                    ),
                    tooltip: 'Gruptan Çıkar',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ] else
                  const SizedBox(width: 24),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _quickAssignStudentToGroup(
    Map<String, dynamic> student,
    String slotId,
    AgmAssignment? oldAssign,
    String? newGroupId,
  ) async {
    setState(() => _loading = true);
    try {
      final studentId = student['id']?.toString() ?? '';

      // Eski atamayı sil (Varsa)
      if (oldAssign != null) {
        await FirebaseFirestore.instance
            .collection('agm_assignments')
            .doc(oldAssign.id)
            .delete();
      }

      // Yeni atama ekle (Varsa)
      if (newGroupId != null) {
        final newGroup = _groups.firstWhere((g) => g.id == newGroupId);
        final aId = FirebaseFirestore.instance
            .collection('agm_assignments')
            .doc()
            .id;
        final assignment = AgmAssignment(
          id: aId,
          cycleId: widget.cycle.id,
          groupId: newGroup.id,
          institutionId: widget.cycle.institutionId,
          ogrenciId: studentId,
          ogrenciAdi: student['name'] ?? 'İsimsiz',
          subeId: student['subeId'] ?? '',
          subeAdi: student['branch'] ?? '',
          ihtiyacSkoru: 0.0,
          atamaTipi: AgmAssignmentType.manual,
          groupName: newGroup.dersAdi,
          olusturulmaZamani: DateTime.now(),
        );

        await FirebaseFirestore.instance
            .collection('agm_assignments')
            .doc(aId)
            .set(assignment.toMap());
      }

      // Verileri tazelemek zorunlu; eksik listeleri, boşluklar, widget cycle vb.
      await _loadData();
    } catch (e) {
      _showError('İşlem sırasında hata: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildBulkActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_selectedStudentIds.length} Öğrenci Seçildi',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  'Toplu işlem yapabilirsiniz.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),
              ],
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => _selectedStudentIds.clear()),
              child: const Text('İptal'),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: () {
                final selectedAssignments = _assignmentsByGroup.values
                    .expand((list) => list)
                    .where((a) => _selectedStudentIds.contains(a.ogrenciId))
                    .toList();
                _showMoveDialog(selectedAssignments);
              },
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Taşı'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _autoAssignAbsentStudent(Map<String, dynamic> student) async {
    setState(() => _loading = true);
    final studentId = student['id'] as String;

    try {
      final assignedGroupIds = _assignmentsByGroup.entries
          .where((e) => e.value.any((a) => a.ogrenciId == studentId))
          .map((e) => e.key)
          .toSet();

      final assignedSubjects = <String>{};
      final occupiedTimeSlots = <String>{};

      for (final grup in _groups) {
        if (assignedGroupIds.contains(grup.id)) {
          assignedSubjects.add(grup.dersAdi);
          occupiedTimeSlots.add(grup.saatDilimiId);
        }
      }

      bool atamaYapildi = false;

      for (final grup in _groups) {
        if (assignedSubjects.contains(grup.dersAdi)) continue; // Zaten aldı
        if (occupiedTimeSlots.contains(grup.saatDilimiId))
          continue; // Bu saat dolu

        final currentAssigns = _assignmentsByGroup[grup.id] ?? [];
        if (currentAssigns.length < grup.kapasite) {
          final aId = FirebaseFirestore.instance
              .collection('agm_assignments')
              .doc()
              .id;
          final assignment = AgmAssignment(
            id: aId,
            cycleId: widget.cycle.id,
            groupId: grup.id,
            institutionId: widget.cycle.institutionId,
            ogrenciId: studentId,
            ogrenciAdi: student['name'] ?? 'İsimsiz',
            subeId: student['subeId'] ?? '',
            subeAdi: student['branch'] ?? '',
            ihtiyacSkoru: 0.0,
            atamaTipi: AgmAssignmentType.manual,
            groupName: grup.dersAdi,
            olusturulmaZamani: DateTime.now(),
          );

          await FirebaseFirestore.instance
              .collection('agm_assignments')
              .doc(aId)
              .set(assignment.toMap());

          setState(() {
            _assignmentsByGroup.putIfAbsent(grup.id, () => []).add(assignment);
            assignedSubjects.add(grup.dersAdi);
            occupiedTimeSlots.add(grup.saatDilimiId);
          });
          atamaYapildi = true;
        }
      }

      if (atamaYapildi) {
        _showSuccess('Öğrenci uygun boş gruplara otomatik atandı.');
        _loadData(); // İstatistikleri yenile
      } else {
        _showError('Uygun boş kontenjan bulunamadı.');
        setState(() => _loading = false);
      }
    } catch (e) {
      _showError('Otomatik atama sırasında hata oluştu: $e');
      setState(() => _loading = false);
    }
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
      _showError('Bu kategoride atanacak öğrenci yok.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Otomatik Atama Onayı'),
        content: Text(
          '$count $filterName öğrenciye otomatik atama yapılacaktır. Onaylıyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
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
        targetStudents = _absentStudents
            .map(
              (s) => {
                'id': s['id']?.toString() ?? '',
                'name': (s['fullName'] ?? s['name'] ?? 'İsimsiz').toString(),
                'branch': (s['className'] ?? s['branch'] ?? '').toString(),
                'subeId': s['branchId']?.toString() ?? '',
              },
            )
            .toList();
      } else {
        targetStudents = _getMappedStudents(_yerlesmeyenFilterIndex);
      }

      if (targetStudents.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      int atamaYapilanSayisi = 0;

      for (final student in targetStudents) {
        final studentId = student['id'] as String;

        final assignedGroupIds = _assignmentsByGroup.entries
            .where((e) => e.value.any((a) => a.ogrenciId == studentId))
            .map((e) => e.key)
            .toSet();

        final assignedSubjects = <String>{};
        final occupiedTimeSlots = <String>{};

        for (final grup in _groups) {
          if (assignedGroupIds.contains(grup.id)) {
            assignedSubjects.add(grup.dersAdi);
            occupiedTimeSlots.add(grup.saatDilimiId);
          }
        }

        bool ogrenciIcinAtamaYapildi = false;

        for (final grup in _groups) {
          if (assignedSubjects.contains(grup.dersAdi)) continue; // Zaten aldı
          if (occupiedTimeSlots.contains(grup.saatDilimiId))
            continue; // Bu saat dolu

          final currentAssigns = _assignmentsByGroup[grup.id] ?? [];
          if (currentAssigns.length < grup.kapasite) {
            final aId = FirebaseFirestore.instance
                .collection('agm_assignments')
                .doc()
                .id;
            final assignment = AgmAssignment(
              id: aId,
              cycleId: widget.cycle.id,
              groupId: grup.id,
              institutionId: widget.cycle.institutionId,
              ogrenciId: studentId,
              ogrenciAdi: student['name'] ?? 'İsimsiz',
              subeId: student['subeId'] ?? '',
              subeAdi: student['branch'] ?? '',
              ihtiyacSkoru: 0.0,
              atamaTipi: AgmAssignmentType.manual,
              groupName: grup.dersAdi,
              olusturulmaZamani: DateTime.now(),
            );

            await FirebaseFirestore.instance
                .collection('agm_assignments')
                .doc(aId)
                .set(assignment.toMap());

            _assignmentsByGroup.putIfAbsent(grup.id, () => []).add(assignment);
            assignedSubjects.add(grup.dersAdi);
            occupiedTimeSlots.add(grup.saatDilimiId);

            ogrenciIcinAtamaYapildi = true;
          }
        }

        if (ogrenciIcinAtamaYapildi) {
          atamaYapilanSayisi++;
        }
      }

      if (atamaYapilanSayisi > 0) {
        _showSuccess(
          '$atamaYapilanSayisi öğrenci uygun boş gruplara otomatik atandı.',
        );
        await _loadData(); // İstatistikleri yenile
      } else {
        _showError('Uygun boş kontenjan bulunamadı.');
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      _showError('Toplu otomatik atama sırasında hata oluştu: $e');
      if (mounted) setState(() => _loading = false);
    }
  }
}

// ─── TASLAK OLUŞTURMA BOTTOM SHEET ───────────────────────────────────────────

class _DraftGenerateSheet extends StatefulWidget {
  final AgmCycle cycle;
  final List<String> availableSubjects;
  final Future<void> Function({
    required double esikBasariOrani,
    required bool sadeceDusukBasari,
    required Map<String, double> dersBazliEsikler,
  })
  onGenerate;

  const _DraftGenerateSheet({
    required this.cycle,
    required this.availableSubjects,
    required this.onGenerate,
  });

  @override
  State<_DraftGenerateSheet> createState() => _DraftGenerateSheetState();
}

class _DraftGenerateSheetState extends State<_DraftGenerateSheet> {
  double _esikBasariOrani = 0.6; // %60 altı = etüt gerekli
  bool _sadeceDusukBasari = true;
  bool _loading = false;
  bool _dersBazliAcik = false;
  final Map<String, double> _dersBazliEsikler = {};

  @override
  void initState() {
    super.initState();
    for (final sub in widget.availableSubjects) {
      _dersBazliEsikler[sub] = _esikBasariOrani;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.auto_fix_high,
                  color: Colors.deepOrange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Taslak Oluştur',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Sınav sonuçlarına göre otomatik yerleştirme',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 28),

          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Sadece düşük başarılı
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _sadeceDusukBasari,
                    onChanged: (v) => setState(() => _sadeceDusukBasari = v),
                    activeColor: Colors.deepOrange,
                    title: const Text(
                      'Sadece düşük başarılı dersler',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Kapalıysa tüm dersler için etüt atanır',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),

                  if (_sadeceDusukBasari) ...[
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _dersBazliAcik,
                      onChanged: (v) => setState(() {
                        _dersBazliAcik = v;
                        if (v) {
                          // Ders bazlı açıldığında genel eşiğe eşitle
                          for (final sub in widget.availableSubjects) {
                            _dersBazliEsikler[sub] = _esikBasariOrani;
                          }
                        }
                      }),
                      activeColor: Colors.deepOrange,
                      title: const Text(
                        'Ders bazlı eşik belirle',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Her ders için farklı bir başarı eşiği tanımlayın',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),

                    const SizedBox(height: 12),

                    if (!_dersBazliAcik) ...[
                      // Başarı eşik ayarı (Genel)
                      Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Başarı Eşiği',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  'Bu oranın altındaki dersler için etüt atanır',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.deepOrange.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '%${(_esikBasariOrani * 100).toStringAsFixed(0)}',
                              style: TextStyle(
                                color: Colors.deepOrange.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _esikBasariOrani,
                        min: 0.0,
                        max: 1.0,
                        divisions: 20,
                        activeColor: Colors.deepOrange,
                        onChanged: (v) => setState(() => _esikBasariOrani = v),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '%0',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          Text(
                            '%100',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ] else if (widget.availableSubjects.isNotEmpty) ...[
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: widget.availableSubjects.map((sub) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        sub,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        '%${((_dersBazliEsikler[sub] ?? 0.6) * 100).toStringAsFixed(0)}',
                                        style: TextStyle(
                                          color: Colors.deepOrange.shade700,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Slider(
                                    value: _dersBazliEsikler[sub] ?? 0.6,
                                    min: 0.0,
                                    max: 1.0,
                                    divisions: 20,
                                    activeColor: Colors.deepOrange.shade300,
                                    inactiveColor: Colors.deepOrange.shade100,
                                    onChanged: (v) => setState(
                                      () => _dersBazliEsikler[sub] = v,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ],

                  const SizedBox(height: 16),

                  // Bilgi kutusu
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.blue.shade700,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Sınav: ${widget.cycle.referansDenemeSinavAdi}\n'
                            'Mevcut sınav sonuçları analiz edilecek. Sınava girmeyen öğrenciler ayrı listede görünecek.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading
                  ? null
                  : () async {
                      setState(() => _loading = true);
                      await widget.onGenerate(
                        esikBasariOrani: _esikBasariOrani,
                        sadeceDusukBasari: _sadeceDusukBasari,
                        dersBazliEsikler: _dersBazliAcik
                            ? _dersBazliEsikler
                            : {},
                      );
                    },
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: const Text('Algoritmayı Çalıştır'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
