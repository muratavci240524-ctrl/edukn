import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/school/inventory_procurement_models.dart';
import '../../../services/inventory_procurement_service.dart';
import '../../../widgets/edukn_app_bar.dart';
import 'inventory_ui_widgets.dart';
import 'material_request_form_sheet.dart';

/// Öğretmen "Destek Birimi -> Malzeme Talep" Ekranı
/// Sıkı gizlilik kuralı: Öğretmen yalnızca kendi malzeme talebini oluşturabilir ve
/// yalnızca kendi oluşturduğu taleplerin durumunu takip edebilir (depo stokları,
/// fiyat teklifleri veya diğer personellerin talepleri kesinlikle gösterilmez).
class TeacherMaterialRequestsScreen extends StatefulWidget {
  final String institutionId;
  final String? fixedSchoolTypeId;
  final String? fixedSchoolTypeName;
  final List<({String id, String name})> initialSchoolTypes;

  const TeacherMaterialRequestsScreen({
    super.key,
    required this.institutionId,
    this.fixedSchoolTypeId,
    this.fixedSchoolTypeName,
    this.initialSchoolTypes = const [],
  });

  @override
  State<TeacherMaterialRequestsScreen> createState() =>
      _TeacherMaterialRequestsScreenState();
}

class _TeacherMaterialRequestsScreenState
    extends State<TeacherMaterialRequestsScreen> {
  final InventoryProcurementService _service = InventoryProcurementService();
  final DateFormat _dateFmt = DateFormat('dd.MM.yyyy HH:mm');

  bool _loading = true;
  String _institutionId = '';
  String _schoolDocId = '';
  String _actorUid = '';
  String _actorName = '';
  List<({String id, String name})> _schoolTypes = [];
  String _filter = 'all'; // 'all' | 'active' | 'ready' | 'delivered' | 'rejected'
  final Set<String> _expandedTimelineIds = {};

  @override
  void initState() {
    super.initState();
    _schoolTypes = List.of(widget.initialSchoolTypes);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final actor = await _service.resolveCurrentActor(
        fallbackInstitutionId: widget.institutionId,
      );
      final instId = actor.institutionId.isNotEmpty
          ? actor.institutionId
          : widget.institutionId.trim();
      final schoolDocId = await _service.resolveSchoolDocId(instId);

      if (_schoolTypes.isEmpty &&
          (widget.fixedSchoolTypeId ?? '').trim().isEmpty &&
          instId.isNotEmpty) {
        final variants = {
          instId,
          instId.toUpperCase(),
          instId.toLowerCase(),
        }.where((e) => e.isNotEmpty).toList();
        final map = <String, String>{};
        for (final col in const ['school_types', 'schoolTypes']) {
          try {
            final snap = await FirebaseFirestore.instance
                .collection(col)
                .where('institutionId', whereIn: variants)
                .get();
            for (final doc in snap.docs) {
              final n =
                  (doc.data()['name'] ?? doc.data()['schoolTypeName'] ?? '')
                      .toString()
                      .trim();
              if (n.isNotEmpty) map[doc.id] = n;
            }
          } catch (_) {}
        }
        _schoolTypes = map.entries
            .map((e) => (id: e.key, name: e.value))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
      }

      if (!mounted) return;
      setState(() {
        _institutionId = instId;
        _schoolDocId = schoolDocId;
        _actorUid = actor.uid;
        _actorName = actor.name;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openNewRequestSheet() async {
    if (_schoolDocId.isEmpty) return;
    final created = await MaterialRequestFormSheet.show(
      context,
      institutionId: _institutionId,
      schoolDocId: _schoolDocId,
      fixedSchoolTypeId: widget.fixedSchoolTypeId,
      fixedSchoolTypeName: widget.fixedSchoolTypeName,
      schoolTypeOptions: _schoolTypes,
      catalogSuggestions: const [],
      isTeacherMode: true,
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF059669),
          content: Text(
            'Malzeme talebiniz oluşturuldu ve onay sürecine iletildi.',
          ),
        ),
      );
    }
  }

  Future<void> _openUrl(String rawUrl) async {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return;
    final formatted =
        trimmed.startsWith('http://') || trimmed.startsWith('https://')
            ? trimmed
            : 'https://$trimmed';
    final uri = Uri.tryParse(formatted);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _previewImage(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Stack(
          children: [
            InteractiveViewer(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxHeight: 620, maxWidth: 800),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Padding(
                      padding: EdgeInsets.all(40),
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 56,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _teacherFriendlyStatusLabel(MaterialRequestModel r) {
    switch (r.status) {
      case 'pending_supervisor':
        return 'Onay Bekliyor';
      case 'pending_upper_approver':
        return 'Üst Onay Sürecinde';
      case 'in_procurement':
      case 'quotes_submitted':
      case 'purchase_approved':
        return 'Tedarik Sürecinde';
      case 'purchase_ordered':
        return 'Sipariş Verildi • Bekleniyor';
      case 'approved_for_warehouse':
        return 'Teslime Hazır';
      case 'delivered':
        return 'Teslim Alındı';
      case 'rejected':
        return 'Onaylanmadı';
      default:
        return 'Süreçte';
    }
  }

  String _sanitizeStageTitleForTeacher(RequestTimelineEntry entry) {
    switch (entry.stage) {
      case 'created':
        return 'Malzeme talebi oluşturuldu';
      case 'supervisor_approved':
        return 'Talep onaylandı';
      case 'upper_approved':
        return 'Tedarik süreci onaylandı';
      case 'quotes_submitted':
      case 'quote_approved':
        return 'Tedarik planlaması tamamlandı';
      case 'purchase_ordered':
        return 'Malzeme siparişi verildi';
      case 'warehouse_received':
        return 'Malzeme ulaştı • Teslime hazır';
      case 'delivered':
        return 'Malzeme teslim edildi';
      case 'rejected':
        return 'Talep reddedildi';
      default:
        return entry.title;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF4F7FB),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: EduknAppBar(
        title: 'Malzeme Talep',
        subtitle: widget.fixedSchoolTypeName ??
            (_actorName.isNotEmpty ? _actorName : null),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton.icon(
              onPressed: _openNewRequestSheet,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text(
                'Talep Oluştur',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewRequestSheet,
        backgroundColor: const Color(0xFF4F46E5),
        foregroundColor: Colors.white,
        elevation: 3,
        icon: const Icon(Icons.add_shopping_cart_rounded),
        label: const Text(
          'Yeni Malzeme Talebi',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _actorUid.isEmpty || _schoolDocId.isEmpty
          ? const InventoryEmptyState(
              icon: Icons.person_off_outlined,
              title: 'Oturum Bilgisi Çözümlenemedi',
              subtitle:
                  'Kullanıcı veya kurum bilginiz doğrulanamadı. Lütfen sayfayı yenileyip tekrar deneyiniz.',
            )
          : StreamBuilder<List<MaterialRequestModel>>(
              stream: _service.watchMaterialRequests(
                schoolDocId: _schoolDocId,
                fixedSchoolTypeId: widget.fixedSchoolTypeId,
                requesterUid: _actorUid,
              ),
              builder: (context, reqSnap) {
                if (reqSnap.connectionState == ConnectionState.waiting &&
                    !reqSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Çift katmanlı güvenlik: Yalnızca öğretmenin kendi UID'sine ait kayıtlar
                final allRequests =
                    (reqSnap.data ?? const <MaterialRequestModel>[])
                        .where((r) => r.requesterUid == _actorUid)
                        .toList();

                final activeCount =
                    allRequests.where((r) => !r.isClosed).length;
                final readyCount = allRequests
                    .where((r) => r.status == 'approved_for_warehouse')
                    .length;
                final deliveredCount =
                    allRequests.where((r) => r.status == 'delivered').length;
                final rejectedCount =
                    allRequests.where((r) => r.status == 'rejected').length;

                final filtered = allRequests.where((r) {
                  switch (_filter) {
                    case 'active':
                      return !r.isClosed;
                    case 'ready':
                      return r.status == 'approved_for_warehouse';
                    case 'delivered':
                      return r.status == 'delivered';
                    case 'rejected':
                      return r.status == 'rejected';
                    default:
                      return true;
                  }
                }).toList();

                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildHeroBanner(),
                                const SizedBox(height: 14),
                                _buildSummaryBanner(
                                  total: allRequests.length,
                                  active: activeCount,
                                  ready: readyCount,
                                  delivered: deliveredCount,
                                ),
                                const SizedBox(height: 14),
                                _buildFilterBar(
                                  allCount: allRequests.length,
                                  activeCount: activeCount,
                                  readyCount: readyCount,
                                  deliveredCount: deliveredCount,
                                  rejectedCount: rejectedCount,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (filtered.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: InventoryEmptyState(
                              icon: Icons.shopping_bag_outlined,
                              title: allRequests.isEmpty
                                  ? 'Henüz Malzeme Talebiniz Bulunmuyor'
                                  : 'Bu Filtrede Kayıt Bulunamadı',
                              subtitle: allRequests.isEmpty
                                  ? 'Ders, sınıf veya etkinlikleriniz için ihtiyaç duyduğunuz malzemeleri hemen talep edebilir ve durumunu buradan izleyebilirsiniz.'
                                  : 'Seçtiğiniz filtreye uygun malzeme talebiniz bulunmuyor.',
                              actionLabel: 'Yeni Malzeme Talebi Aç',
                              actionIcon: Icons.add_shopping_cart_rounded,
                              onAction: _openNewRequestSheet,
                            ),
                          )
                        else
                          SliverPadding(
                            padding:
                                const EdgeInsets.fromLTRB(16, 8, 16, 100),
                            sliver: SliverList.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) =>
                                  _buildTeacherRequestCard(filtered[index]),
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

  Widget _buildHeroBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF312E81), Color(0xFF4F46E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              color: Colors.white,
              size: 25,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Destek Birimi • Malzeme Talep Merkezi',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Oluşturduğunuz taleplerin onay ve teslimat adımlarını buradan canlı olarak takip edebilirsiniz.',
                  style: TextStyle(
                    fontSize: 12.2,
                    color: Color(0xFFE0E7FF),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBanner({
    required int total,
    required int active,
    required int ready,
    required int delivered,
  }) {
    final items = [
      (
        label: 'Devam Eden',
        value: active.toString(),
        color: const Color(0xFF4F46E5),
        bg: const Color(0xFFEEF2FF),
        icon: Icons.hourglass_top_rounded,
      ),
      (
        label: 'Teslime Hazır',
        value: ready.toString(),
        color: const Color(0xFF0D9488),
        bg: const Color(0xFFF0FDFA),
        icon: Icons.inventory_2_rounded,
      ),
      (
        label: 'Teslim Alınan',
        value: delivered.toString(),
        color: const Color(0xFF059669),
        bg: const Color(0xFFECFDF5),
        icon: Icons.check_circle_rounded,
      ),
      (
        label: 'Toplam Talebim',
        value: total.toString(),
        color: const Color(0xFF475569),
        bg: const Color(0xFFF1F5F9),
        icon: Icons.receipt_long_rounded,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;
        final width = isCompact
            ? (constraints.maxWidth - 10) / 2
            : (constraints.maxWidth - 30) / 4;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: items.map((it) {
            return Container(
              width: width,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: it.bg,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(it.icon, color: it.color, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          it.value,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: it.color,
                          ),
                        ),
                        Text(
                          it.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildFilterBar({
    required int allCount,
    required int activeCount,
    required int readyCount,
    required int deliveredCount,
    required int rejectedCount,
  }) {
    final chips = [
      (key: 'all', label: 'Tümü ($allCount)'),
      (key: 'active', label: 'Süreçte ($activeCount)'),
      (key: 'ready', label: 'Teslime Hazır ($readyCount)'),
      (key: 'delivered', label: 'Teslim Alınan ($deliveredCount)'),
      if (rejectedCount > 0) (key: 'rejected', label: 'Reddedilen ($rejectedCount)'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: chips.map((c) {
          final sel = _filter == c.key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _filter = c.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: sel ? const Color(0xFF4F46E5) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: sel
                        ? const Color(0xFF4F46E5)
                        : const Color(0xFFD5DFEC),
                  ),
                ),
                child: Text(
                  c.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: sel ? Colors.white : const Color(0xFF334155),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTeacherRequestCard(MaterialRequestModel r) {
    final expanded = _expandedTimelineIds.contains(r.id);
    final isReady = r.status == 'approved_for_warehouse';
    final isRejected = r.status == 'rejected';
    final isDelivered = r.status == 'delivered';

    Color statusBg = const Color(0xFFEEF2FF);
    Color statusFg = const Color(0xFF4338CA);
    if (isReady) {
      statusBg = const Color(0xFFCCFBF1);
      statusFg = const Color(0xFF0F766E);
    } else if (isDelivered) {
      statusBg = const Color(0xFFD1FAE5);
      statusFg = const Color(0xFF047857);
    } else if (isRejected) {
      statusBg = const Color(0xFFFEE2E2);
      statusFg = const Color(0xFFB91C1C);
    } else if (r.status == 'pending_supervisor') {
      statusBg = const Color(0xFFFEF3C7);
      statusFg = const Color(0xFFB45309);
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isReady
              ? const Color(0xFF5EEAD4)
              : isRejected
                  ? const Color(0xFFFECACA)
                  : const Color(0xFFE2E8F0),
          width: isReady ? 1.5 : 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4.5,
                ),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _teacherFriendlyStatusLabel(r),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: statusFg,
                  ),
                ),
              ),
              if (r.isUrgent)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bolt_rounded,
                        size: 13,
                        color: Color(0xFFDC2626),
                      ),
                      SizedBox(width: 2),
                      Text(
                        'ACİL',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                _dateFmt.format(r.createdAt),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.itemName,
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      r.category,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    if (r.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        r.description,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF334155),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD5DFEC)),
                ),
                child: Text(
                  '${r.formattedQty} ${r.unit}',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),

          if (isReady) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDFA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF99F6E4)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.inventory_rounded,
                    size: 18,
                    color: Color(0xFF0D9488),
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Talebiniz onaylandı ve teslime hazır durumda. Destek biriminden teslim alabilirsiniz.',
                      style: TextStyle(
                        fontSize: 12.3,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF115E59),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (isRejected && r.rejectionReason.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: Color(0xFFDC2626),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Açıklama: ${r.rejectionReason}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF991B1B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (!isRejected) ...[
            const SizedBox(height: 14),
            _buildStepTracker(r.progressStep),
          ],

          if (r.productLink.isNotEmpty || r.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (r.productLink.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _openUrl(r.productLink),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.link_rounded, size: 16),
                    label: const Text(
                      'Eklediğim Ürün Linki',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ...r.imageUrls.map(
                  (url) => GestureDetector(
                    onTap: () => _previewImage(url),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        url,
                        width: 46,
                        height: 46,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],

          if (r.timeline.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    if (expanded) {
                      _expandedTimelineIds.remove(r.id);
                    } else {
                      _expandedTimelineIds.add(r.id);
                    }
                  });
                },
                icon: Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.history_rounded,
                  size: 17,
                ),
                label: Text(
                  expanded ? 'Süreç Özeti Gizle' : 'Süreç Geçmişi',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (expanded) ...[
              const Divider(height: 12),
              ...r.timeline.reversed.map(
                (t) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF4F46E5),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_dateFmt.format(t.timestamp)} — ${_sanitizeStageTitleForTeacher(t)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildStepTracker(int activeStep) {
    const labels = [
      'Talep Açıldı',
      'Onay Süreci',
      'Tedarik',
      'Hazır',
      'Teslim Alındı',
    ];
    return Row(
      children: List.generate(labels.length, (i) {
        final done = i <= activeStep;
        final current = i == activeStep;
        return Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 3,
                      color: i == 0
                          ? Colors.transparent
                          : (done
                              ? const Color(0xFF4F46E5)
                              : const Color(0xFFE2E8F0)),
                    ),
                  ),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: done
                          ? const Color(0xFF4F46E5)
                          : const Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: current
                            ? const Color(0xFF818CF8)
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: Icon(
                      done ? Icons.check_rounded : Icons.circle,
                      size: done ? 13 : 6,
                      color: done ? Colors.white : const Color(0xFFCBD5E1),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 3,
                      color: i == labels.length - 1
                          ? Colors.transparent
                          : (i < activeStep
                              ? const Color(0xFF4F46E5)
                              : const Color(0xFFE2E8F0)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                labels[i],
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: done ? FontWeight.w700 : FontWeight.w500,
                  color: done
                      ? const Color(0xFF1E293B)
                      : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
