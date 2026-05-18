import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/agm_cycle_model.dart';
import '../repository/agm_repository.dart';
import '../services/agm_service.dart';
import 'agm_cycle_setup_screen.dart';
import 'agm_group_grid_screen.dart';
import '../../../classroom_management_screen.dart';

/// AGM Ana Ekranı – Tüm cycle'ların listesi
class AgmDashboardScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const AgmDashboardScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<AgmDashboardScreen> createState() => _AgmDashboardScreenState();
}

class _AgmDashboardScreenState extends State<AgmDashboardScreen> {
  final _service = AgmService();
  final _repo = AgmRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'AGM – Akademik Güçlendirme',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.deepOrange,
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
                    schoolTypeName: 'AGM', // Veya dinamik bir isim
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: StreamBuilder<List<AgmCycle>>(
            stream: _service.watchCycles(
              widget.institutionId,
              widget.schoolTypeId,
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
        label: const Text('Yeni Cycle'),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.deepOrange,
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
            Icons.school_outlined,
            size: 72,
            color: Colors.deepOrange.shade200,
          ),
          const SizedBox(height: 16),
          Text(
            'Henüz cycle yok',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Deneme sınavı sonuçlarına göre\notomatik etüt programı oluşturun.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _goToSetup(context),
            icon: const Icon(Icons.add),
            label: const Text('İlk Cycle\'ı Oluştur'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
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
        color: Colors.deepOrange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepOrange.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.deepOrange.shade700, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Her cycle, bir deneme sınavını referans alarak öğrencileri otomatik etüt gruplarına yerleştirir.',
              style: TextStyle(fontSize: 12, color: Colors.deepOrange.shade800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCycleCard(BuildContext context, AgmCycle cycle) {
    final Color statusColor;
    final IconData statusIcon;
    switch (cycle.status) {
      case AgmCycleStatus.draft:
        statusColor = Colors.orange;
        statusIcon = Icons.edit_outlined;
        break;
      case AgmCycleStatus.locked:
        statusColor = Colors.blue;
        statusIcon = Icons.lock_outline;
        break;
      case AgmCycleStatus.published:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_outline;
        break;
    }

    final formatter = DateFormat('dd MMM yyyy', 'tr_TR');
    final isDraft = cycle.status == AgmCycleStatus.draft;

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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 14, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          cycle.statusLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ─── ÜÇ NOKTA MENÜ ───
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      size: 20,
                      color: Colors.grey.shade600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    itemBuilder: (_) => [
                      if (isDraft) ...[
                        const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.edit_note, color: Colors.blue),
                            title: Text('Düzenle'),
                            subtitle: Text(
                              'Cycle ayarlarını\ngüncelle',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'reset',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.refresh, color: Colors.orange),
                            title: Text('Taslağı Sıfırla'),
                            subtitle: Text(
                              'Tüm atamaları siler,\ngrublar kalır',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
                            title: Text(
                              'Cycle\'\u0131 Sil',
                              style: TextStyle(color: Colors.red),
                            ),
                            subtitle: Text(
                              'Cycle + tüm atamalar silinir',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                      ] else ...[
                        const PopupMenuItem(
                          value: 'view',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.open_in_new,
                              color: Colors.deepOrange,
                            ),
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
                  Icon(
                    Icons.calendar_today,
                    size: 14,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${formatter.format(cycle.baslangicTarihi)} – ${formatter.format(cycle.bitisTarihi)}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // ── Çoklu Deneme Sınavı Referansları ──
              Row(
                children: [
                  Icon(
                    Icons.quiz_outlined,
                    size: 14,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      cycle.referansDenemeSinavIds.isNotEmpty
                          ? cycle.referansDenemeSinavAdlari.join(', ')
                          : cycle.referansDenemeSinavAdi,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
              if (cycle.haftalikMaksimumSaat != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 14,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Haftalık maks: ${cycle.haftalikMaksimumSaat} saat',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ],
              const Divider(height: 20),
              Row(
                children: [
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: Colors.grey.shade400,
                  ),
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

  Future<void> _onMenuAction(
    BuildContext context,
    String action,
    AgmCycle cycle,
  ) async {
    switch (action) {
      case 'edit':
        _goToSetup(context, cycle: cycle);
        break;
      case 'reset':
        await _confirmAndReset(context, cycle);
        break;
      case 'delete':
        await _confirmAndDelete(context, cycle);
        break;
      case 'view':
        _goToGroupGrid(context, cycle);
        break;
    }
  }

  Future<void> _confirmAndReset(BuildContext context, AgmCycle cycle) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.refresh, color: Colors.orange),
            SizedBox(width: 8),
            Text('Taslağı Sıfırla'),
          ],
        ),
        content: const Text(
          'Bu cycle\'a ait tüm öğrenci atamaları silinecek.\n'
          'Gruplar (ders/saat dilimleri) korunur.\n\n'
          'Sonra "Taslak Oluştur" ile yeniden algoritmayı \u00e7alıştırabilirsiniz.',
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

    if (confirm != true) return;

    try {
      await _repo.rollbackAssignments(cycle.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Taslak sıfırlandı. Gruplar korundu.'),
            backgroundColor: Colors.orange,
          ),
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

  Future<void> _confirmAndDelete(BuildContext context, AgmCycle cycle) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Cycle\'\u0131 Sil', style: TextStyle(color: Colors.red)),
          ],
        ),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(color: Colors.black87, fontSize: 14),
            children: [
              TextSpan(
                text: '"${cycle.referansDenemeSinavAdi}"',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const TextSpan(
                text:
                    ' cycle\'u ve bu cycle\'a ait tüm gruplar, atamalar ve loglar kalıcı olarak silinecek.\n\n'
                    'Bu işlem geri alınamaz.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Evet, Sil'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _repo.deleteCycle(cycle.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cycle silindi.'),
            backgroundColor: Colors.red,
          ),
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

  void _goToSetup(BuildContext context, {AgmCycle? cycle}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AgmCycleSetupScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          initialCycle: cycle,
        ),
      ),
    );
  }

  void _goToGroupGrid(BuildContext context, AgmCycle cycle) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AgmGroupGridScreen(cycle: cycle)),
    );
  }
}
