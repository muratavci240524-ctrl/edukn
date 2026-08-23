import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../models/camp_cycle_model.dart';
import '../repository/camp_repository.dart';
import '../services/camp_service.dart';
import 'camp_cycle_setup_screen.dart';
import 'camp_group_grid_screen.dart';
import '../../../classroom_management_screen.dart';
import 'package:edukn/widgets/safe_stream_builder.dart';

import 'package:edukn/services/term_service.dart';

class CampDashboardScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String? workPeriodId;

  const CampDashboardScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    this.workPeriodId,
  }) : super(key: key);

  @override
  State<CampDashboardScreen> createState() => _CampDashboardScreenState();
}

class _CampDashboardScreenState extends State<CampDashboardScreen> {
  final _service = CampService();
  final _repo = CampRepository();
  final _termService = TermService();

  String? _displayedPeriodId;
  String? _displayedPeriodName;
  String? _activePeriodId;
  bool _isPastPeriod = false;
  bool _loadingPeriod = true;

  @override
  void initState() {
    super.initState();
    _resolvePeriod();
  }

  Future<void> _resolvePeriod() async {
    try {
      // 1. Kurumun aktif dönemini bul
      String? activeId = await _termService.getActiveTermId();
      String activeName = '2025-2026';

      // Eğer TermService'ten gelmediyse doğrudan terms koleksiyonundan çekelim
      final termsSnap = await FirebaseFirestore.instance
          .collection('terms')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      if (termsSnap.docs.isNotEmpty) {
        final activeDoc = termsSnap.docs.firstWhere(
          (d) => d.data()['isActive'] == true,
          orElse: () => termsSnap.docs.first,
        );
        activeId = activeDoc.id;
        activeName = activeDoc.data()['termName'] ?? '${activeDoc.data()['startYear']}-${activeDoc.data()['endYear']}';
      }

      _activePeriodId = activeId;

      // 2. Kullanıcının seçtiği geçmiş dönem var mı kontrol et
      final selectedId = await _termService.getSelectedTermId();
      final selectedName = await _termService.getSelectedTermName();

      if (selectedId != null && selectedId.isNotEmpty && selectedId != activeId) {
        // Geçmiş dönem seçilmiş
        _displayedPeriodId = selectedId;
        _displayedPeriodName = selectedName ?? 'Geçmiş Dönem';
        _isPastPeriod = true;
      } else {
        // Aktif dönemdeyiz
        _displayedPeriodId = activeId;
        _displayedPeriodName = activeName;
        _isPastPeriod = false;

        // Mevcut dönem atanmamış veya eski kampların hepsini aktif döneme bağlayalım
        if (activeId != null && activeId.isNotEmpty) {
          await _migrateExistingCyclesToPeriod(activeId);
        }
      }
    } catch (e) {
      debugPrint('Dönem getirme hatası: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingPeriod = false);
      }
    }
  }

  Future<void> _migrateExistingCyclesToPeriod(String activeTermId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('camp_cycles')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      int count = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final currentPid = data['workPeriodId'] as String?;
        // Kullanıcı talebi: Mevcut kampların hepsini aktif döneme bağla
        if (currentPid != activeTermId) {
          batch.update(doc.reference, {'workPeriodId': activeTermId});
          count++;
        }
      }
      if (count > 0) {
        await batch.commit();
        debugPrint('$count adet kamp aktif döneme ($activeTermId) aktarıldı/bağlandı.');
      }
    } catch (e) {
      debugPrint('Kamp migrasyon hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Column(
          children: [
            const Text(
              'Kamp Programı',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 17),
            ),
            if (_displayedPeriodName != null)
              Text(
                'Dönem: $_displayedPeriodName ${_isPastPeriod ? "(Geçmiş)" : "(Aktif)"}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.95),
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        backgroundColor: _isPastPeriod ? Colors.blueGrey.shade700 : Colors.orange.shade700,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Derslik Tanımlama',
            icon: const Icon(Icons.meeting_room_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ClassroomManagementScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: 'Kamp', 
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: _loadingPeriod
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: SafeStreamBuilder<List<CampCycle>>(
                  stream: _service.watchCycles(
                    widget.institutionId,
                    widget.schoolTypeId,
                    workPeriodId: _displayedPeriodId,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Hata: ${snapshot.error}'));
                    }
                    final cycles = snapshot.data ?? [];

                    if (cycles.isEmpty) {
                      return _buildEmptyState(context);
                    }

                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildInfoBanner(),
                        const SizedBox(height: 16),
                        ...cycles.map((c) => _buildCycleCard(context, c)),
                        const SizedBox(height: 80),
                      ],
                    );
                  },
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _goToSetup(context),
        label: const Text('Yeni Kamp'),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.campaign_outlined,
            size: 72,
            color: Colors.orange.shade200,
          ),
          const SizedBox(height: 16),
          Text(
            'Henüz kamp programı yok',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Özel sınıf ve yoğunlaştırılmış kamp\nplanlamalarınızı buradan başlatın.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _goToSetup(context),
            icon: const Icon(Icons.add),
            label: const Text('İlk Kampı Oluştur'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Kamp programları ile öğrenci başarı grafiklerine göre özel gruplar ve yoğunlaştırılmış çalışma planları oluşturabilirsiniz.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCycleCard(BuildContext context, CampCycle cycle) {
    final Color statusColor;
    final IconData statusIcon;
    switch (cycle.status) {
      case CampCycleStatus.draft:
        statusColor = Colors.orange;
        statusIcon = Icons.edit_outlined;
        break;
      case CampCycleStatus.locked:
        statusColor = Colors.blue;
        statusIcon = Icons.lock_outline;
        break;
      case CampCycleStatus.published:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_outline;
        break;
    }

    final formatter = DateFormat('dd MMM yyyy', 'tr_TR');
    final isDraft = cycle.status == CampCycleStatus.draft;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _goToGroupGrid(context, cycle),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      (cycle.title != null && cycle.title!.isNotEmpty)
                          ? cycle.title!
                          : cycle.referansDenemeSinavAdi,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Container(
                    padding: isMobile 
                        ? const EdgeInsets.all(6) 
                        : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      shape: isMobile ? BoxShape.circle : BoxShape.rectangle,
                      borderRadius: isMobile ? null : BorderRadius.circular(20),
                    ),
                    child: isMobile 
                        ? Tooltip(
                            message: cycle.statusLabel,
                            child: Icon(statusIcon, size: 14, color: statusColor),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(statusIcon, size: 14, color: statusColor),
                              const SizedBox(width: 4),
                              Text(
                                cycle.statusLabel,
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor),
                              ),
                            ],
                          ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, size: 20, color: Colors.grey.shade600),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    itemBuilder: (_) => [
                      if (isDraft) ...[
                        const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.edit_note, color: Colors.blue),
                            title: Text('Düzenle'),
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.delete_outline, color: Colors.red),
                            title: Text('Sil', style: TextStyle(color: Colors.red)),
                          ),
                        ),
                      ] else ...[
                        const PopupMenuItem(
                          value: 'view',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.open_in_new, color: Colors.orange),
                            title: Text('Detay'),
                          ),
                        ),
                      ],
                    ],
                    onSelected: (val) => _onMenuAction(context, val, cycle),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Text(
                    '${formatter.format(cycle.baslangicTarihi)} – ${formatter.format(cycle.bitisTarihi)}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
              if (cycle.isSpecialClassActive) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.star, size: 14, color: Colors.orange.shade600),
                    const SizedBox(width: 6),
                    Text(
                      'Özel Sınıf: ${cycle.specialClassRoomName ?? "Belirtilmedi"} (${cycle.specialClassCapacity} Kişi)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                    ),
                  ],
                ),
              ],
              // ── İstatistik Satırı ──
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _buildStatChip(
                    icon: Icons.people_alt_outlined,
                    label: 'Yerleşemeyen',
                    value: '${cycle.unassignedStudentIds.length}',
                    color: cycle.unassignedStudentIds.isEmpty ? Colors.green : Colors.red,
                  ),
                  _buildStatChip(
                    icon: Icons.warning_amber_rounded,
                    label: 'Eksik Atanan',
                    value: '${cycle.underAssignedStudentIds.length}',
                    color: cycle.underAssignedStudentIds.isEmpty ? Colors.green : Colors.orange,
                  ),
                  if (cycle.excludedStudentIds.isNotEmpty)
                    _buildStatChip(
                      icon: Icons.block,
                      label: 'Hariç',
                      value: '${cycle.excludedStudentIds.length}',
                      color: Colors.grey,
                    ),
                ],
              ),
              const Divider(height: 20),
              Row(
                children: [
                  Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 6),
                  Text(
                    isDraft ? 'Düzenlemek için aç' : 'Detayları görüntüle',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onMenuAction(BuildContext context, String action, CampCycle cycle) async {
    switch (action) {
      case 'edit':
        _goToSetup(context, cycle: cycle);
        break;
      case 'delete':
        await _confirmAndDelete(context, cycle);
        break;
      case 'view':
        _goToGroupGrid(context, cycle);
        break;
    }
  }

  Future<void> _confirmAndDelete(BuildContext context, CampCycle cycle) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Kampı Sil', style: TextStyle(color: Colors.red)),
        content: const Text('Bu kamp programı kalıcı olarak silinecek. Bu işlem geri alınamaz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _repo.deleteCycle(cycle.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kamp silindi.'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _goToSetup(BuildContext context, {CampCycle? cycle}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CampCycleSetupScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          workPeriodId: _activePeriodId,
          initialCycle: cycle,
        ),
      ),
    );
  }

  void _goToGroupGrid(BuildContext context, CampCycle cycle) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CampGroupGridScreen(cycle: cycle)),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            '$label: $value',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}
