import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../models/agm_cycle_model.dart';
import '../repository/agm_repository.dart';
import '../services/agm_service.dart';
import 'agm_cycle_setup_screen.dart';
import 'agm_group_grid_screen.dart';
import '../../../classroom_management_screen.dart';
import 'package:edukn/widgets/safe_stream_builder.dart';
import 'package:edukn/services/term_service.dart';

class AgmDashboardScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String? workPeriodId;

  const AgmDashboardScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    this.workPeriodId,
  }) : super(key: key);

  @override
  State<AgmDashboardScreen> createState() => _AgmDashboardScreenState();
}

class _AgmDashboardScreenState extends State<AgmDashboardScreen> {
  final _service = AgmService();
  final _repo = AgmRepository();
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

      // 2. widget.workPeriodId öncelikli mi?
      if (widget.workPeriodId != null && widget.workPeriodId!.isNotEmpty) {
        _displayedPeriodId = widget.workPeriodId;
        final matched = termsSnap.docs.where((d) => d.id == widget.workPeriodId).firstOrNull;
        if (matched != null) {
          _displayedPeriodName = matched.data()['termName'] ?? '${matched.data()['startYear']}-${matched.data()['endYear']}';
          _isPastPeriod = matched.data()['isActive'] != true;
        } else {
          _displayedPeriodName = 'Seçili Dönem';
          _isPastPeriod = (_displayedPeriodId != _activePeriodId);
        }
      } else {
        // 3. Kullanıcının seçtiği geçmiş dönem var mı kontrol et
        final selectedId = await _termService.getSelectedTermId();
        final selectedName = await _termService.getSelectedTermName();

        if (selectedId != null && selectedId.isNotEmpty && selectedId != activeId) {
          _displayedPeriodId = selectedId;
          _displayedPeriodName = selectedName ?? 'Geçmiş Dönem';
          _isPastPeriod = true;
        } else {
          _displayedPeriodId = activeId;
          _displayedPeriodName = activeName;
          _isPastPeriod = false;
        }
      }
    } catch (e) {
      debugPrint('AGM Dönem getirme hatası: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingPeriod = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: EduknAppBar(
        title: 'AGM – Akademik Güçlendirme',
        subtitle: 'Dönem: $_displayedPeriodName ${_isPastPeriod ? "(Geçmiş)" : "(Aktif)"}',
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
                    schoolTypeName: 'AGM', 
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
                child: SafeStreamBuilder<List<AgmCycle>>(
                  stream: _service.watchCycles(
                    widget.institutionId,
                    widget.schoolTypeId,
                    workPeriodId: _displayedPeriodId,
                    isPastPeriod: _isPastPeriod,
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
      floatingActionButton: _isPastPeriod
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _goToSetup(context),
              label: const Text('Yeni AGM Programı'),
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
            Icons.auto_awesome_rounded,
            size: 72,
            color: Colors.deepPurple.shade200,
          ),
          const SizedBox(height: 16),
          Text(
            _isPastPeriod ? 'Bu döneme ait AGM programı bulunamadı' : 'Henüz AGM programı yok',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isPastPeriod
                ? 'Dönem değiştirerek diğer dönemlerdeki programları inceleyebilirsiniz.'
                : 'Öğrenci başarı grafiklerine göre özel gruplar ve yoğunlaştırılmış\\nçalışma planlarınızı buradan başlatın.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500),
          ),
          if (!_isPastPeriod) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _goToSetup(context),
              icon: const Icon(Icons.add),
              label: const Text('İlk AGM Programını Oluştur'),
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
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.deepPurple.shade100),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.auto_awesome_rounded, color: Colors.deepPurple.shade700, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Akademik Güçlendirme Merkezi (AGM)',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple.shade900, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'Öğrenci başarı grafiklerine göre özel gruplar, seviye odaklı sınıflar ve yoğunlaştırılmış çalışma planları oluşturabilirsiniz.',
                  style: TextStyle(fontSize: 12, color: Colors.deepPurple.shade800, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCycleCard(BuildContext context, AgmCycle cycle) {
    final dateFormat = DateFormat('dd.MM.yyyy');
    final dateRange = '${dateFormat.format(cycle.baslangicTarihi)} – ${dateFormat.format(cycle.bitisTarihi)}';

    Color statusColor;
    switch (cycle.status) {
      case AgmCycleStatus.draft:
        statusColor = Colors.orange;
        break;
      case AgmCycleStatus.locked:
        statusColor = Colors.red;
        break;
      case AgmCycleStatus.published:
        statusColor = Colors.green;
        break;
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AgmGroupGridScreen(cycle: cycle),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      cycle.title ?? 'AGM Programı',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      cycle.statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    dateRange,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.assignment, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      cycle.referansDenemeSinavAdlari.isNotEmpty
                          ? cycle.referansDenemeSinavAdlari.join(', ')
                          : (cycle.referansDenemeSinavAdi.isNotEmpty ? cycle.referansDenemeSinavAdi : 'Sınav atanmadı'),
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (cycle.isSpecialClassActive) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.star, size: 14, color: Colors.amber.shade700),
                    const SizedBox(width: 6),
                    Text(
                      'Özel Sınıf: ${cycle.specialClassRoomName ?? "Derslik Atanmadı"} (Kota: ${cycle.specialClassCapacity ?? 24})',
                      style: TextStyle(color: Colors.amber.shade900, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!_isPastPeriod && cycle.status == AgmCycleStatus.draft)
                    TextButton.icon(
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Düzenle'),
                      style: TextButton.styleFrom(foregroundColor: Colors.deepPurple.shade700),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AgmCycleSetupScreen(
                              institutionId: widget.institutionId,
                              schoolTypeId: widget.schoolTypeId,
                              workPeriodId: _displayedPeriodId,
                              initialCycle: cycle,
                            ),
                          ),
                        );
                      },
                    ),
                  if (!_isPastPeriod)
                    IconButton(
                      tooltip: 'Sil',
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                      onPressed: () => _confirmDeleteCycle(context, cycle),
                    ),
                  const SizedBox(width: 4),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AgmGroupGridScreen(cycle: cycle),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: const Text('Grupları Yönet'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _goToSetup(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AgmCycleSetupScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          workPeriodId: _displayedPeriodId,
        ),
      ),
    );
  }

  void _confirmDeleteCycle(BuildContext context, AgmCycle cycle) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AGM Programını Sil', style: TextStyle(color: Colors.red)),
        content: const Text('Bu AGM programı kalıcı olarak silinecek. Bu işlem geri alınamaz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _repo.deleteCycle(cycle.id);
                if (mounted) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('AGM programı silindi.'), backgroundColor: Colors.red),
                  );
                }
              } catch (e) {
                if (mounted) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }
}
