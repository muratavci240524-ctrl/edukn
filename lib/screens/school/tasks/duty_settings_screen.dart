import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/school/duty_model.dart';
import 'package:edukn/widgets/safe_stream_builder.dart';
import '../../../services/term_service.dart';


class DutySettingsScreen extends StatefulWidget {
  final String institutionId;
  final String? periodId;
  final String? schoolTypeId;
  final String? schoolTypeName;
  final int initialTabIndex;

  const DutySettingsScreen({
    Key? key,
    required this.institutionId,
    this.periodId,
    this.schoolTypeId,
    this.schoolTypeName,
    this.initialTabIndex = 0,
  }) : super(key: key);

  @override
  State<DutySettingsScreen> createState() => _DutySettingsScreenState();
}

class _DutySettingsScreenState extends State<DutySettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: EduknAppBar(
        title: 'Nöbet Ayarları',
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF4F46E5),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF4F46E5),
          tabs: const [
            Tab(text: 'Kurallar'),
            Tab(text: 'Nöbet Yerleri'),
            Tab(text: 'Nöbet Havuzu'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildRulesTab(), _buildLocationsTab(), _buildPoolTab()],
      ),
    );
  }

  // --- Rules Tab ---
  Widget _buildRulesTab() {
    return SafeStreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('dutyRules')
          .where('institutionId', isEqualTo: widget.institutionId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        DutyRules? rules;
        String? docId;
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final doc = snapshot.data!.docs.first;
          rules = DutyRules.fromMap(doc.data() as Map<String, dynamic>);
          docId = doc.id;
        } else {
          rules = DutyRules(institutionId: widget.institutionId);
        }

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nöbet Dagitımı Kuralları',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Nöbet Yerleri Değiştirsin (Rotasyon)'),
                subtitle: const Text(
                  'Aktif edilirse, sistem her hafta öğretmenlerin nöbet yerlerini değiştirmeye çalışır.',
                ),
                value: rules.rotateLocations,
                onChanged: (val) async {
                  final newRules = DutyRules(
                    institutionId: widget.institutionId,
                    rotateLocations: val,
                  );
                  if (docId != null) {
                    await FirebaseFirestore.instance
                        .collection('dutyRules')
                        .doc(docId)
                        .update(newRules.toMap());
                  } else {
                    await FirebaseFirestore.instance
                        .collection('dutyRules')
                        .add(newRules.toMap());
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // --- Locations Tab ---
  Widget _buildLocationsTab() {
    final isPeriodMode = widget.periodId != null && widget.periodId!.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      floatingActionButton: isPeriodMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showLocationDialog(),
              backgroundColor: const Color(0xFF4F46E5),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Yeni Nöbet Yeri',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: SafeStreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('dutyLocations')
                .where('institutionId', isEqualTo: widget.institutionId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.place_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      const Text(
                        'Henüz nöbet yeri tanımlanmamış.',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isPeriodMode
                            ? 'Genel Nöbet Yerleri ekranından yer tanımlayabilirsiniz.'
                            : 'Aşağıdaki butonu kullanarak nöbet yeri ekleyebilirsiniz.',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                );
              }

              // Lokasyonları sırala (order öncelikli, yoksa isim)
              final locations = docs.map((d) {
                final data = d.data() as Map<String, dynamic>;
                return DutyLocation.fromMap(data..['id'] = d.id);
              }).toList();

              locations.sort((a, b) {
                final cmp = a.order.compareTo(b.order);
                if (cmp != 0) return cmp;
                return a.name.compareTo(b.name);
              });

              if (!isPeriodMode) {
                return _buildGeneralLocationsList(locations);
              }

              // Alt dönem modu: workPeriods dokümanından dutyLocationConfigs'i dinle
              return StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('workPeriods')
                    .doc(widget.periodId)
                    .snapshots(),
                builder: (context, periodSnap) {
                  final periodData =
                      periodSnap.data?.data() as Map<String, dynamic>? ?? {};
                  final locationConfigs =
                      (periodData['dutyLocationConfigs'] as Map<String, dynamic>?) ?? {};

                  return _buildPeriodLocationsList(locations, locationConfigs);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  // --- 1. Genel Mod (Tüm okul için tanımlama, silme, sıralama) ---
  Widget _buildGeneralLocationsList(List<DutyLocation> locations) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5).withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF4F46E5).withOpacity(0.15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Color(0xFF4F46E5), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Genel nöbet yerlerini sürükleyerek veya oklara basarak sıralayabilirsiniz. Çıktı ve nöbet listeleri bu sıraya göre gelecektir.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F46E5).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${locations.length} Yer',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
            itemCount: locations.length,
            onReorder: (oldIndex, newIndex) =>
                _onReorderLocations(oldIndex, newIndex, locations),
            itemBuilder: (context, index) {
              final loc = locations[index];
              final activeDays = loc.activeDays..sort();

              return Container(
                key: ValueKey(loc.id),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.drag_indicator_rounded, color: Colors.grey.shade400, size: 20),
                          const SizedBox(width: 6),
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFF4F46E5).withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF4F46E5),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              loc.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Text(
                                  _getDaysText(activeDays),
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                                if (loc.startTime.isNotEmpty || loc.endTime.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${loc.startTime} - ${loc.endTime}',
                                      style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_up_rounded),
                            iconSize: 20,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            color: index > 0 ? const Color(0xFF4F46E5) : Colors.grey.shade300,
                            tooltip: 'Yukarı Taşı',
                            onPressed: index > 0 ? () => _moveLocation(index, -1, locations) : null,
                          ),
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                            iconSize: 20,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            color: index < locations.length - 1 ? const Color(0xFF4F46E5) : Colors.grey.shade300,
                            tooltip: 'Aşağı Taşı',
                            onPressed: index < locations.length - 1 ? () => _moveLocation(index, 1, locations) : null,
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                            iconSize: 18,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            tooltip: 'Düzenle',
                            onPressed: () => _showLocationDialog(location: loc),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                            iconSize: 18,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            tooltip: 'Sil',
                            onPressed: () => _deleteLocation(loc.id),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- 2. Alt Dönem Modu (Switch ile aç/kapa, yer adı sabit, gün/saat özelleştirilebilir) ---
  Widget _buildPeriodLocationsList(
    List<DutyLocation> locations,
    Map<String, dynamic> locationConfigs,
  ) {
    final existingGroups = locationConfigs.values
        .whereType<Map>()
        .map((c) => (c['group'] ?? '').toString().trim())
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0891B2).withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF0891B2).withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.tune_rounded, color: Color(0xFF0891B2), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Nöbet yerleri genel havuzdan çekilmiştir. Bu alt dönemde kullanılacak yerleri açıp kapatabilir, gruplarını, gün ve saatlerini özelleştirebilirsiniz.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
            itemCount: locations.length,
            itemBuilder: (context, index) {
              final loc = locations[index];
              final config = locationConfigs[loc.id] as Map<String, dynamic>?;
              final isEnabled = config?['isEnabled'] == true; // Varsayılan kapalı

              final activeDays = config?['activeDays'] != null
                  ? (List<int>.from(config!['activeDays'])..sort())
                  : (loc.activeDays..sort());
              final startTime = config?['startTime'] ?? loc.startTime;
              final endTime = config?['endTime'] ?? loc.endTime;
              final groupName = (config?['group'] ?? loc.group).toString().trim();
              final hasOverride = config?['activeDays'] != null ||
                  config?['startTime'] != null ||
                  config?['endTime'] != null ||
                  groupName.isNotEmpty;

              return Opacity(
                opacity: isEnabled ? 1.0 : 0.55,
                child: Container(
                  key: ValueKey(loc.id),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isEnabled
                          ? (hasOverride ? const Color(0xFF0891B2).withOpacity(0.3) : Colors.grey.shade200)
                          : Colors.grey.shade300,
                      width: hasOverride ? 1.5 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        // Sıra No Badge
                        Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isEnabled ? const Color(0xFF4F46E5).withOpacity(0.1) : Colors.grey.shade200,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isEnabled ? const Color(0xFF4F46E5) : Colors.grey.shade600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Yer Adı ve Alt Dönem Bilgileri
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      loc.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: isEnabled ? const Color(0xFF1E293B) : Colors.grey.shade600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (groupName.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF4F46E5).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFF4F46E5).withOpacity(0.25)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.folder_outlined, size: 11, color: Color(0xFF4F46E5)),
                                          const SizedBox(width: 4),
                                          Text(
                                            groupName,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF4F46E5),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  if (hasOverride) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0891B2).withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'Bu Döneme Özel',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0891B2),
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (!isEnabled) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Bu Dönemde Pasif',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    _getDaysText(activeDays),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isEnabled ? Colors.grey.shade700 : Colors.grey.shade500,
                                    ),
                                  ),
                                  if (startTime.isNotEmpty || endTime.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '$startTime - $endTime',
                                        style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Düzenle Butonu (Sadece bu alt döneme özel gün/saat/grup)
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: Color(0xFF0891B2)),
                          iconSize: 18,
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Bu Döneme Özel Ayarları Düzenle',
                          onPressed: () => _showLocationDialog(
                            location: loc,
                            isPeriodMode: true,
                            currentConfig: config,
                            existingGroups: existingGroups,
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Switch (Aç / Kapa)
                        Switch(
                          value: isEnabled,
                          activeColor: const Color(0xFF4F46E5),
                          onChanged: (val) async {
                            try {
                              await FirebaseFirestore.instance
                                  .collection('workPeriods')
                                  .doc(widget.periodId)
                                  .set({
                                'dutyLocationConfigs': {
                                  loc.id: {
                                    ...?config,
                                    'isEnabled': val,
                                  }
                                }
                              }, SetOptions(merge: true));
                            } catch (e) {
                              debugPrint('Error updating dutyLocationConfigs: $e');
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- Sıralama Mantığı ---
  Future<void> _onReorderLocations(
    int oldIndex,
    int newIndex,
    List<DutyLocation> list,
  ) async {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    await _saveLocationOrders(list);
  }

  Future<void> _moveLocation(
    int currentIndex,
    int direction,
    List<DutyLocation> list,
  ) async {
    final targetIndex = currentIndex + direction;
    if (targetIndex < 0 || targetIndex >= list.length) return;

    final item = list.removeAt(currentIndex);
    list.insert(targetIndex, item);
    await _saveLocationOrders(list);
  }

  Future<void> _saveLocationOrders(List<DutyLocation> list) async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      final col = FirebaseFirestore.instance.collection('dutyLocations');

      for (int i = 0; i < list.length; i++) {
        final docRef = col.doc(list[i].id);
        batch.update(docRef, {'order': i});
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Nöbet yeri sıralama kaydetme hatası: $e');
    }
  }

  // --- Pool Tab (Select Eligibility) ---
  Widget _buildPoolTab() {
    return _PoolConfigScreen(
      institutionId: widget.institutionId,
      periodId: widget.periodId,
      schoolTypeId: widget.schoolTypeId,
      schoolTypeName: widget.schoolTypeName,
    );
  }

  // Helper Methods
  Future<void> _showLocationDialog({
    DutyLocation? location,
    bool isPeriodMode = false,
    Map<String, dynamic>? currentConfig,
    List<String> existingGroups = const [],
  }) async {
    final nameCtrl = TextEditingController(text: location?.name);
    final groupCtrl = TextEditingController(
      text: isPeriodMode
          ? (currentConfig?['group'] ?? location?.group ?? '')
          : (location?.group ?? ''),
    );
    final defaultGroups = [
      'Kat Nöbetleri',
      'Hafta Sonu Nöbetleri',
      'Etüt Nöbetleri',
    ];
    final initialGroup = isPeriodMode
        ? (currentConfig?['group'] ?? location?.group ?? '')
        : (location?.group ?? '');
    final Set<String> groupOptionsSet = {
      ...defaultGroups,
      ...existingGroups,
    };
    if (initialGroup.toString().trim().isNotEmpty) {
      groupOptionsSet.add(initialGroup.toString().trim());
    }
    final List<String> groupOptions = groupOptionsSet.toList()..sort();
    String selectedGroup = initialGroup.toString().trim();
    bool isAddingNewGroup = false;
    final newGroupCtrl = TextEditingController();

    final startCtrl = TextEditingController(
      text: isPeriodMode
          ? (currentConfig?['startTime'] ?? location?.startTime ?? '')
          : (location?.startTime ?? ''),
    );
    final endCtrl = TextEditingController(
      text: isPeriodMode
          ? (currentConfig?['endTime'] ?? location?.endTime ?? '')
          : (location?.endTime ?? ''),
    );
    final descCtrl = TextEditingController(text: location?.description);
    List<int> selectedDays = isPeriodMode
        ? (currentConfig?['activeDays'] != null
            ? List<int>.from(currentConfig!['activeDays'])
            : List<int>.from(location?.activeDays ?? [1, 2, 3, 4, 5]))
        : List<int>.from(location?.activeDays ?? [1, 2, 3, 4, 5]);
    bool checkOtherDays = location?.checkOtherDays ?? true;

    Map<String, dynamic> getGroupVisuals(String g) {
      if (g == 'Kat Nöbetleri') {
        return {
          'title': 'Kat Nöbetleri',
          'subtitle': 'Katlar ve koridorlar arasında dengeli rotasyon',
          'badge': 'Standart Kat',
          'icon': Icons.apartment_rounded,
          'color': const Color(0xFF4F46E5),
          'bgColor': const Color(0xFFEEF2FF),
          'borderColor': const Color(0xFFC7D2FE),
        };
      } else if (g == 'Hafta Sonu Nöbetleri') {
        return {
          'title': 'Hafta Sonu Nöbetleri',
          'subtitle': 'Cumartesi & Pazar günleri bağımsız hafta sonu rotasyonu',
          'badge': 'Hafta Sonu',
          'icon': Icons.weekend_rounded,
          'color': const Color(0xFFD97706),
          'bgColor': const Color(0xFFFEF3C7),
          'borderColor': const Color(0xFFFDE68A),
        };
      } else if (g == 'Etüt Nöbetleri') {
        return {
          'title': 'Etüt Nöbetleri',
          'subtitle': 'Ders dışı ve etüt saatleri nöbet rotasyonu',
          'badge': 'Etüt & Kurs',
          'icon': Icons.menu_book_rounded,
          'color': const Color(0xFF059669),
          'bgColor': const Color(0xFFD1FAE5),
          'borderColor': const Color(0xFFA7F3D0),
        };
      } else if (g.isNotEmpty) {
        return {
          'title': g,
          'subtitle': 'Özel tanımlanmış nöbet rotasyon grubu',
          'badge': 'Özel Grup',
          'icon': Icons.stars_rounded,
          'color': const Color(0xFF7C3AED),
          'bgColor': const Color(0xFFF3E8FF),
          'borderColor': const Color(0xFFDDD6FE),
        };
      } else {
        return {
          'title': 'Grup Yok / Bağımsız Nöbet',
          'subtitle': 'Diğer yerlerle rotasyona girmeden tekil olarak atanır',
          'badge': 'Bağımsız',
          'icon': Icons.layers_clear_rounded,
          'color': const Color(0xFF64748B),
          'bgColor': const Color(0xFFF1F5F9),
          'borderColor': const Color(0xFFCBD5E1),
        };
      }
    }

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Kapat',
      barrierColor: Colors.black.withOpacity(0.55),
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (context, anim, secondaryAnim, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
      pageBuilder: (sheetContext, anim, secondaryAnim) => StatefulBuilder(
        builder: (context, setState) {
          return Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.90,
                  maxWidth: 720,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 30,
                      offset: Offset(0, -6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        width: 48,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF4F46E5).withOpacity(0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.place_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isPeriodMode
                                      ? '${location?.name}'
                                      : (location == null ? 'Yeni Nöbet Yeri' : 'Nöbet Yerini Düzenle'),
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isPeriodMode
                                      ? 'Bu alt döneme özel nöbet grubu, aktif günler ve saat ayarları'
                                      : 'Nöbet yeri bilgileri ve aktif günleri',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close_rounded, color: Colors.grey, size: 20),
                            ),
                            onPressed: () => Navigator.pop(sheetContext),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          16,
                          20,
                          MediaQuery.of(context).viewInsets.bottom + 24,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isPeriodMode) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4F46E5).withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.category_rounded, color: Color(0xFF4F46E5), size: 15),
                                    SizedBox(width: 6),
                                    Text(
                                      'NÖBET GRUBU & ROTASYON',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF4F46E5),
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Aynı gruptaki nöbet yerleri dağıtılırken birbiriyle eşitlenir ve haftalık olarak adil rotasyona tabi tutulur.',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                value: groupOptions.contains(selectedGroup)
                                    ? selectedGroup
                                    : (selectedGroup.isEmpty ? '' : null),
                                isExpanded: true,
                                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF4F46E5), size: 24),
                                dropdownColor: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                elevation: 8,
                                decoration: InputDecoration(
                                  labelText: 'Nöbet Grubu Seçin',
                                  labelStyle: const TextStyle(
                                    color: Color(0xFF4F46E5),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                  floatingLabelBehavior: FloatingLabelBehavior.always,
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
                                  ),
                                ),
                                selectedItemBuilder: (context) {
                                  final allKeys = ['', ...groupOptions, '__add_new__'];
                                  return allKeys.map((key) {
                                    if (key == '__add_new__') {
                                      return const SizedBox();
                                    }
                                    final info = getGroupVisuals(key);
                                    return Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: info['bgColor'] as Color,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: (info['borderColor'] as Color).withOpacity(0.8),
                                              width: 1,
                                            ),
                                          ),
                                          child: Icon(
                                            info['icon'] as IconData,
                                            size: 16,
                                            color: info['color'] as Color,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            info['title'] as String,
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700,
                                              color: key.isEmpty ? const Color(0xFF64748B) : const Color(0xFF0F172A),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: (info['bgColor'] as Color).withOpacity(0.8),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(
                                              color: (info['borderColor'] as Color).withOpacity(0.9),
                                              width: 1,
                                            ),
                                          ),
                                          child: Text(
                                            info['badge'] as String,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: info['color'] as Color,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList();
                                },
                                items: [
                                  () {
                                    final info = getGroupVisuals('');
                                    final isCur = selectedGroup.isEmpty;
                                    return DropdownMenuItem<String>(
                                      value: '',
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: info['bgColor'] as Color,
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: (info['borderColor'] as Color).withOpacity(0.6)),
                                              ),
                                              child: Icon(info['icon'] as IconData, size: 18, color: info['color'] as Color),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Flexible(
                                                        child: Text(
                                                          info['title'] as String,
                                                          style: TextStyle(
                                                            fontSize: 13.5,
                                                            fontWeight: FontWeight.w700,
                                                            color: isCur ? const Color(0xFF4F46E5) : const Color(0xFF0F172A),
                                                          ),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                        decoration: BoxDecoration(
                                                          color: info['bgColor'] as Color,
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Text(
                                                          info['badge'] as String,
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.bold,
                                                            color: info['color'] as Color,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    info['subtitle'] as String,
                                                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (isCur)
                                              const Padding(
                                                padding: EdgeInsets.only(left: 6),
                                                child: Icon(Icons.check_circle_rounded, color: Color(0xFF4F46E5), size: 19),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }(),
                                  ...groupOptions.map((g) {
                                    final info = getGroupVisuals(g);
                                    final isCur = selectedGroup == g;
                                    return DropdownMenuItem<String>(
                                      value: g,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: info['bgColor'] as Color,
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: (info['borderColor'] as Color).withOpacity(0.6)),
                                              ),
                                              child: Icon(info['icon'] as IconData, size: 18, color: info['color'] as Color),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Flexible(
                                                        child: Text(
                                                          info['title'] as String,
                                                          style: TextStyle(
                                                            fontSize: 13.5,
                                                            fontWeight: FontWeight.w700,
                                                            color: isCur ? (info['color'] as Color) : const Color(0xFF0F172A),
                                                          ),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                        decoration: BoxDecoration(
                                                          color: info['bgColor'] as Color,
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Text(
                                                          info['badge'] as String,
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.bold,
                                                            color: info['color'] as Color,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    info['subtitle'] as String,
                                                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (isCur)
                                              Padding(
                                                padding: const EdgeInsets.only(left: 6),
                                                child: Icon(Icons.check_circle_rounded, color: info['color'] as Color, size: 19),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }),
                                  DropdownMenuItem<String>(
                                    value: '__add_new__',
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [Color(0xFF10B981), Color(0xFF059669)],
                                              ),
                                              borderRadius: BorderRadius.circular(10),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(0xFF10B981).withOpacity(0.3),
                                                  blurRadius: 6,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: const [
                                                Text(
                                                  '+ Yeni Grup Tanımla...',
                                                  style: TextStyle(
                                                    fontSize: 13.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFF059669),
                                                  ),
                                                ),
                                                SizedBox(height: 2),
                                                Text(
                                                  'Okulunuza özel yeni bir rotasyon grubu açın',
                                                  style: TextStyle(fontSize: 11.5, color: Color(0xFF10B981)),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFF059669)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (val) {
                                  if (val == '__add_new__') {
                                    setState(() {
                                      isAddingNewGroup = true;
                                    });
                                  } else {
                                    setState(() {
                                      selectedGroup = val ?? '';
                                      groupCtrl.text = selectedGroup;
                                      isAddingNewGroup = false;
                                    });
                                  }
                                },
                              ),
                              if (isAddingNewGroup) ...[
                                Container(
                                  margin: const EdgeInsets.only(top: 10),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF0FDF4),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: const Color(0xFF86EFAC)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF10B981).withOpacity(0.08),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF10B981).withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Icon(Icons.auto_awesome_rounded, size: 15, color: Color(0xFF059669)),
                                          ),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Yeni Nöbet Grubu Belirle',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF065F46),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: newGroupCtrl,
                                              autofocus: true,
                                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                                              decoration: InputDecoration(
                                                hintText: 'Örn: Aziz Sancar Binası, Bahçe Nöbetleri...',
                                                hintStyle: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey.shade400,
                                                  fontWeight: FontWeight.normal,
                                                ),
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                                enabledBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(10),
                                                  borderSide: const BorderSide(color: Color(0xFF86EFAC)),
                                                ),
                                                focusedBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(10),
                                                  borderSide: const BorderSide(color: Color(0xFF059669), width: 1.8),
                                                ),
                                                fillColor: Colors.white,
                                                filled: true,
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                              ),
                                              onSubmitted: (val) {
                                                final name = val.trim();
                                                if (name.isNotEmpty) {
                                                  setState(() {
                                                    if (!groupOptions.contains(name)) groupOptions.add(name);
                                                    groupOptions.sort();
                                                    selectedGroup = name;
                                                    groupCtrl.text = name;
                                                    isAddingNewGroup = false;
                                                    newGroupCtrl.clear();
                                                  });
                                                }
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          TextButton(
                                            onPressed: () {
                                              setState(() {
                                                isAddingNewGroup = false;
                                                newGroupCtrl.clear();
                                              });
                                            },
                                            child: const Text('İptal', style: TextStyle(color: Colors.grey)),
                                          ),
                                          const SizedBox(width: 4),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF059669),
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              elevation: 2,
                                            ),
                                            icon: const Icon(Icons.check_rounded, size: 17),
                                            label: const Text('Ekle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                            onPressed: () {
                                              final name = newGroupCtrl.text.trim();
                                              if (name.isNotEmpty) {
                                                setState(() {
                                                  if (!groupOptions.contains(name)) groupOptions.add(name);
                                                  groupOptions.sort();
                                                  selectedGroup = name;
                                                  groupCtrl.text = name;
                                                  isAddingNewGroup = false;
                                                  newGroupCtrl.clear();
                                                });
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                            ],
                            TextField(
                              controller: nameCtrl,
                              enabled: !isPeriodMode,
                              decoration: InputDecoration(
                                labelText: 'Yer Adı',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: isPeriodMode,
                                fillColor: isPeriodMode ? const Color(0xFFF1F5F9) : Colors.white,
                                prefixIcon: isPeriodMode
                                    ? const Icon(Icons.lock_outline_rounded, size: 19, color: Color(0xFF64748B))
                                    : const Icon(Icons.place_rounded, size: 19, color: Color(0xFF4F46E5)),
                                helperText: isPeriodMode
                                    ? '🔒 Yer adı genel istatistikte kullanıldığı için sabittir.'
                                    : null,
                                helperStyle: const TextStyle(color: Color(0xFF0284C7), fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: startCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'Başlangıç Saati',
                                      hintText: '09:00',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      prefixIcon: const Icon(Icons.access_time_rounded, size: 18, color: Color(0xFF64748B)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: endCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'Bitiş Saati',
                                      hintText: '17:00',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      prefixIcon: const Icon(Icons.access_time_filled_rounded, size: 18, color: Color(0xFF64748B)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            if (!isPeriodMode) ...[
                              TextField(
                                controller: descCtrl,
                                maxLines: 2,
                                decoration: InputDecoration(
                                  labelText: 'Açıklama',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  prefixIcon: const Icon(Icons.description_rounded, size: 18, color: Color(0xFF64748B)),
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            Row(
                              children: [
                                const Icon(Icons.calendar_month_rounded, size: 16, color: Color(0xFF4F46E5)),
                                const SizedBox(width: 6),
                                const Text(
                                  'Aktif Günler',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: List.generate(7, (index) {
                                final day = index + 1;
                                final isSelected = selectedDays.contains(day);
                                return FilterChip(
                                  label: Text(_getDayShortName(day)),
                                  selected: isSelected,
                                  selectedColor: const Color(0xFF4F46E5).withOpacity(0.18),
                                  checkmarkColor: const Color(0xFF4F46E5),
                                  labelStyle: TextStyle(
                                    color: isSelected ? const Color(0xFF4F46E5) : Colors.grey.shade700,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                  onSelected: (val) {
                                    setState(() {
                                      if (val) {
                                        selectedDays.add(day);
                                      } else {
                                        selectedDays.remove(day);
                                      }
                                      selectedDays.sort();
                                    });
                                  },
                                );
                              }),
                            ),
                            if (!isPeriodMode) ...[
                              const SizedBox(height: 14),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'Diğer Günlere Dikkat Et',
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
                                subtitle: const Text(
                                  'Aktifse, başka günlerde nöbeti olan öğretmenler turuncu ile gösterilir',
                                  style: TextStyle(fontSize: 12),
                                ),
                                value: checkOtherDays,
                                onChanged: (val) {
                                  setState(() {
                                    checkOtherDays = val;
                                  });
                                },
                              ),
                            ],
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  ),
                                  onPressed: () => Navigator.pop(sheetContext),
                                  child: const Text('Vazgeç', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF4F46E5),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    elevation: 3,
                                  ),
                                  icon: const Icon(Icons.check_rounded, size: 18),
                                  label: const Text('Kaydet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  onPressed: () async {
                                    if (nameCtrl.text.trim().isEmpty) return;

                                    if (isPeriodMode && location != null) {
                                      try {
                                        await FirebaseFirestore.instance
                                            .collection('workPeriods')
                                            .doc(widget.periodId)
                                            .set({
                                          'dutyLocationConfigs': {
                                            location.id: {
                                              ...?currentConfig,
                                              'activeDays': selectedDays,
                                              'startTime': startCtrl.text.trim(),
                                              'endTime': endCtrl.text.trim(),
                                              'group': groupCtrl.text.trim(),
                                              'isEnabled': true,
                                            }
                                          }
                                        }, SetOptions(merge: true));
                                      } catch (e) {
                                        debugPrint('Error saving dutyLocationConfigs: $e');
                                      }
                                    } else {
                                      final col = FirebaseFirestore.instance.collection(
                                        'dutyLocations',
                                      );

                                      final data = {
                                        'institutionId': widget.institutionId,
                                        'name': nameCtrl.text.trim(),
                                        'activeDays': selectedDays,
                                        'startTime': startCtrl.text.trim(),
                                        'endTime': endCtrl.text.trim(),
                                        'description': descCtrl.text.trim(),
                                        'checkOtherDays': checkOtherDays,
                                        'group': groupCtrl.text.trim(),
                                      };

                                      if (location == null) {
                                        final currentSnap = await col
                                            .where('institutionId', isEqualTo: widget.institutionId)
                                            .get();
                                        data['order'] = currentSnap.docs.length;
                                        await col.add(data);
                                      } else {
                                        await col.doc(location.id).update(data);
                                      }
                                    }
                                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _deleteLocation(String id) async {
    await FirebaseFirestore.instance
        .collection('dutyLocations')
        .doc(id)
        .delete();
  }

  String _getDaysText(List<int> days) {
    if (days.isEmpty) return 'Gün seçilmemiş';
    final dayNames = ['', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    return days.map((d) => dayNames[d]).join(', ');
  }

  String _getDayShortName(int day) {
    const dayNames = ['', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    return dayNames[day];
  }
}

class _PoolConfigScreen extends StatefulWidget {
  final String institutionId;
  final String? periodId;
  final String? schoolTypeId;
  final String? schoolTypeName;
  const _PoolConfigScreen({
    Key? key,
    required this.institutionId,
    this.periodId,
    this.schoolTypeId,
    this.schoolTypeName,
  }) : super(key: key);

  @override
  State<_PoolConfigScreen> createState() => _PoolConfigScreenState();
}

class _PoolConfigScreenState extends State<_PoolConfigScreen> {
  int _selectedDay = 1; // 1=Mon

  @override
  Widget build(BuildContext context) {
    final dayNames = [
      '',
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];

    return Column(
      children: [
        // Day Selector
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: List.generate(7, (index) {
              final day = index + 1;
              final isSelected = day == _selectedDay;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(dayNames[day]),
                  selected: isSelected,
                  onSelected: (val) {
                    if (val) setState(() => _selectedDay = day);
                  },
                ),
              );
            }),
          ),
        ),

        Expanded(
          child: SafeStreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('dutyLocations')
                .where('institutionId', isEqualTo: widget.institutionId)
                .snapshots(),
            builder: (context, locSnap) {
              if (locSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final allLocs = (locSnap.data?.docs ?? []).map((d) {
                final data = d.data() as Map<String, dynamic>;
                data['id'] = d.id;
                return DutyLocation.fromMap(data);
              }).toList();

              final isPeriodMode =
                  widget.periodId != null && widget.periodId!.isNotEmpty;

              if (isPeriodMode) {
                return StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('workPeriods')
                      .doc(widget.periodId)
                      .snapshots(),
                  builder: (context, periodSnap) {
                    if (periodSnap.connectionState == ConnectionState.waiting &&
                        !periodSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final periodData =
                        periodSnap.data?.data() as Map<String, dynamic>? ?? {};
                    final locationConfigs = (periodData['dutyLocationConfigs']
                            as Map<String, dynamic>?) ??
                        {};

                    // Sadece bu alt dönemde aktif (isEnabled == true) olan nöbet yerlerini al
                    final periodLocs = allLocs.where((loc) {
                      final cfg =
                          locationConfigs[loc.id] as Map<String, dynamic>?;
                      return cfg != null && cfg['isEnabled'] == true;
                    }).map((loc) {
                      final cfg =
                          locationConfigs[loc.id] as Map<String, dynamic>?;
                      final ovDays = cfg?['activeDays'] != null
                          ? (List<int>.from(cfg!['activeDays'])..sort())
                          : (loc.activeDays..sort());
                      final ovStart = cfg?['startTime'] ?? loc.startTime;
                      final ovEnd = cfg?['endTime'] ?? loc.endTime;
                      final ovOrder =
                          (cfg?['order'] as num?)?.toInt() ?? loc.order;

                      return DutyLocation(
                        id: loc.id,
                        institutionId: loc.institutionId,
                        name: loc.name,
                        activeDays: ovDays,
                        startTime: ovStart,
                        endTime: ovEnd,
                        description: loc.description,
                        checkOtherDays: loc.checkOtherDays,
                        order: ovOrder,
                        eligibilities: loc.eligibilities,
                      );
                    }).toList();

                    periodLocs.sort((a, b) => a.order.compareTo(b.order));

                    final activeLocs = periodLocs
                        .where((l) => l.activeDays.contains(_selectedDay))
                        .toList();

                    return _buildLocationsPoolList(
                      activeLocs,
                      periodLocs,
                      dayNames,
                      isPeriodMode: true,
                    );
                  },
                );
              }

              // Genel mod: Tüm aktif günler
              allLocs.sort((a, b) => a.order.compareTo(b.order));
              final activeLocs = allLocs
                  .where((l) => l.activeDays.contains(_selectedDay))
                  .toList();

              return _buildLocationsPoolList(
                activeLocs,
                allLocs,
                dayNames,
                isPeriodMode: false,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLocationsPoolList(
    List<DutyLocation> activeLocs,
    List<DutyLocation> allAvailableLocs,
    List<String> dayNames, {
    required bool isPeriodMode,
  }) {
    if (activeLocs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_busy_rounded, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                isPeriodMode
                    ? '${dayNames[_selectedDay]} günü için bu alt dönemde aktif nöbet yeri yok.'
                    : '${dayNames[_selectedDay]} günün aktif nöbet yeri yok.',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
                textAlign: TextAlign.center,
              ),
              if (isPeriodMode) ...[
                const SizedBox(height: 8),
                Text(
                  '"Nöbet Yerleri" sekmesinden bu gün için nöbet yerlerini aktif edebilirsiniz.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: activeLocs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final loc = activeLocs[index];
        final eligibleIds =
            loc.eligibilities[_selectedDay.toString()] ?? [];

        final elig = DutyEligibility(
          id: loc.id,
          institutionId: widget.institutionId,
          locationId: loc.id,
          dayOfWeek: _selectedDay,
          eligibleTeacherIds: eligibleIds,
        );

        return Card(
          child: ListTile(
            title: Text(
              loc.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('${eligibleIds.length} kişi seçili'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.copy, color: Colors.orange),
                  tooltip: 'Bu listeyi diğer gün ve yerlere kopyala',
                  onPressed: () => _copyToOtherLocations(
                    elig,
                    loc.name,
                    allAvailableLocs,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => _showSelectionDialog(loc, elig),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isVicePrincipal(Map<String, dynamic> data) {
    final checkStrings = <String>[];
    for (var key in ['role', 'title', 'position', 'duty', 'subRole', 'userRole', 'department']) {
      final val = data[key];
      if (val != null) checkStrings.add(val.toString().toLowerCase().trim());
    }
    if (data['roles'] is List) {
      for (var r in (data['roles'] as List)) {
        if (r != null) checkStrings.add(r.toString().toLowerCase().trim());
      }
    }

    for (var str in checkStrings) {
      if (str == 'mudur_yardimcisi' ||
          str == 'mudir_yardimcisi' ||
          str == 'müdür yardımcısı' ||
          str == 'mudur yardimcisi' ||
          str == 'müdür yrd.' ||
          str == 'müdür yrd' ||
          str == 'mudur yrd' ||
          str == 'vice_principal' ||
          (str.contains('müdür') && (str.contains('yardımc') || str.contains('yrd'))) ||
          (str.contains('mudur') && (str.contains('yardimc') || str.contains('yrd')))) {
        return true;
      }
    }
    return false;
  }

  bool _isPrincipalOrManager(Map<String, dynamic> data) {
    if (_isVicePrincipal(data)) return false;

    final checkStrings = <String>[];
    for (var key in ['role', 'title', 'position', 'duty', 'subRole', 'userRole']) {
      final val = data[key];
      if (val != null) checkStrings.add(val.toString().toLowerCase().trim());
    }
    if (data['roles'] is List) {
      for (var r in (data['roles'] as List)) {
        if (r != null) checkStrings.add(r.toString().toLowerCase().trim());
      }
    }

    for (var str in checkStrings) {
      if (str == 'mudur' ||
          str == 'müdür' ||
          str == 'okul_muduru' ||
          str == 'okul müdürü' ||
          str == 'okul muduru' ||
          str == 'genel_mudur' ||
          str == 'genel müdür' ||
          str == 'kurum_muduru' ||
          str == 'kurum müdürü' ||
          str == 'kurum yöneticisi' ||
          str == 'kurum_yoneticisi' ||
          str == 'yonetici' ||
          str == 'yönetici' ||
          str == 'principal' ||
          str == 'director' ||
          (str.contains('müdür') && !str.contains('yardımc') && !str.contains('yrd')) ||
          (str.contains('mudur') && !str.contains('yardimc') && !str.contains('yrd'))) {
        return true;
      }
    }
    return false;
  }

  String _getUserDisplayTitle(Map<String, dynamic> data) {
    if (_isVicePrincipal(data)) {
      return 'Müdür Yardımcısı';
    }
    if (_isPrincipalOrManager(data)) {
      return 'Okul Müdürü';
    }
    if (data['branches'] is List && (data['branches'] as List).isNotEmpty) {
      return (data['branches'] as List).first.toString();
    } else if (data['branch'] is String && (data['branch'] as String).trim().isNotEmpty) {
      return (data['branch'] as String).trim();
    }
    final title = data['title']?.toString().trim();
    if (title != null && title.isNotEmpty && title.toLowerCase() != 'öğretmen') {
      return title;
    }
    return 'Öğretmen';
  }

  bool _isUserInSchoolType(
    Map<String, dynamic> data,
    String? targetSchoolTypeId, {
    String? targetSchoolTypeName,
  }) {
    final targetId = targetSchoolTypeId?.trim() ?? '';
    final targetName = targetSchoolTypeName?.trim() ?? '';

    if (targetId.isEmpty && targetName.isEmpty) {
      return true;
    }

    final targetIdLower = targetId.toLowerCase();
    final targetNameLower = targetName.toLowerCase();

    final userSchoolTypes = <String>{};

    // 1. data['schoolTypes'] (List of IDs, names or Maps)
    if (data['schoolTypes'] is List) {
      for (var item in (data['schoolTypes'] as List)) {
        if (item is Map) {
          final mId = item['id']?.toString().trim();
          if (mId != null && mId.isNotEmpty) {
            userSchoolTypes.add(mId);
            userSchoolTypes.add(mId.toLowerCase());
          }
          final mName = item['name']?.toString().trim();
          if (mName != null && mName.isNotEmpty) {
            userSchoolTypes.add(mName);
            userSchoolTypes.add(mName.toLowerCase());
          }
        } else {
          final str = item?.toString().trim();
          if (str != null && str.isNotEmpty) {
            userSchoolTypes.add(str);
            userSchoolTypes.add(str.toLowerCase());
          }
        }
      }
    }

    // 2. data['workLocations'] (List of school type names, e.g. ['İlkokul', 'Ortaokul'])
    if (data['workLocations'] is List) {
      for (var item in (data['workLocations'] as List)) {
        final str = item?.toString().trim();
        if (str != null && str.isNotEmpty) {
          userSchoolTypes.add(str);
          userSchoolTypes.add(str.toLowerCase());
        }
      }
    }

    // 3. data['workLocation'] (String, e.g. 'İlkokul')
    final wLoc = data['workLocation']?.toString().trim();
    if (wLoc != null && wLoc.isNotEmpty) {
      userSchoolTypes.add(wLoc);
      userSchoolTypes.add(wLoc.toLowerCase());
    }

    // 4. data['schoolTypePermissions'] (Map)
    if (data['schoolTypePermissions'] is Map) {
      final perms = data['schoolTypePermissions'] as Map;
      for (var key in perms.keys) {
        final str = key?.toString().trim();
        if (str != null && str.isNotEmpty) {
          userSchoolTypes.add(str);
          userSchoolTypes.add(str.toLowerCase());
        }
      }
    }

    // 5. data['schoolTypeId'] (String)
    final sId = data['schoolTypeId']?.toString().trim();
    if (sId != null && sId.isNotEmpty) {
      userSchoolTypes.add(sId);
      userSchoolTypes.add(sId.toLowerCase());
    }

    // 6. data['schoolTypeIds'] (List)
    if (data['schoolTypeIds'] is List) {
      for (var item in (data['schoolTypeIds'] as List)) {
        final str = item?.toString().trim();
        if (str != null && str.isNotEmpty) {
          userSchoolTypes.add(str);
          userSchoolTypes.add(str.toLowerCase());
        }
      }
    }

    // 7. data['schoolType'] / schoolTypeName / school / schoolName / schools / assignedSchools
    for (var key in ['schoolType', 'schoolTypeName', 'school', 'schoolName']) {
      final s = data[key]?.toString().trim();
      if (s != null && s.isNotEmpty) {
        userSchoolTypes.add(s);
        userSchoolTypes.add(s.toLowerCase());
      }
    }
    for (var key in ['schools', 'assignedSchools']) {
      if (data[key] is List) {
        for (var item in (data[key] as List)) {
          final str = item?.toString().trim();
          if (str != null && str.isNotEmpty) {
            userSchoolTypes.add(str);
            userSchoolTypes.add(str.toLowerCase());
          }
        }
      }
    }

    // 8. Eğer kullanıcının herhangi bir okul türü kaydı varsa hedef ile eşleşiyor mu kontrol et:
    if (userSchoolTypes.isNotEmpty) {
      if (targetId.isNotEmpty &&
          (userSchoolTypes.contains(targetId) || userSchoolTypes.contains(targetIdLower))) {
        return true;
      }
      if (targetName.isNotEmpty &&
          (userSchoolTypes.contains(targetName) || userSchoolTypes.contains(targetNameLower))) {
        return true;
      }
      return false;
    }

    // Kullanıcıda okul türü bulunamadıysa ve işlem yapılan okul türü belliyse sızmaları önlemek için gösterme
    return false;
  }

  bool _isUserActive(
    Map<String, dynamic> data, {
    String? termId,
    String? schoolTypeId,
    String? schoolTypeName,
  }) {
    // 0. Okul Müdürü / Kurum Müdürü kontrolü: Müdür yetkisinde olanlara nöbet yazılamaz
    if (_isPrincipalOrManager(data)) {
      return false;
    }

    // 1. Pasiflik kontrolleri
    final isActive = data['isActive'];
    if (isActive != null) {
      if (isActive == false || isActive == 'false') return false;
    }
    if (data['isPassive'] == true || data['isPassive'] == 'true') return false;

    final status = (data['status'] ?? '').toString().toLowerCase().trim();
    if (status == 'passive' || status == 'pasif' || status == 'inactive') return false;

    // 2. Eğer kullanıcıda dönem tanımlıysa mevcut dönemle eşleşmeli
    if (termId != null && termId.isNotEmpty) {
      final uTermId = data['termId']?.toString().trim();
      if (uTermId != null && uTermId.isNotEmpty && uTermId != termId) {
        return false;
      }
      final uAcadTermId = data['academicTermId']?.toString().trim();
      if (uAcadTermId != null && uAcadTermId.isNotEmpty && uAcadTermId != termId) {
        return false;
      }
      if (data['termIds'] is List) {
        final tList = (data['termIds'] as List).map((e) => e.toString().trim()).toList();
        if (tList.isNotEmpty && !tList.contains(termId)) {
          return false;
        }
      }
    }

    // 3. Okul türü kontrolü: Farklı okul türündekiler görünmeyecek, birden fazlasında görevliyse görünecek
    if (!_isUserInSchoolType(data, schoolTypeId, targetSchoolTypeName: schoolTypeName)) {
      return false;
    }

    return true;
  }

  String _normalizeTr(String text) {
    return text
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('İ', 'i')
        .replaceAll('I', 'i')
        .replaceAll('ş', 's')
        .replaceAll('Ş', 's')
        .replaceAll('ğ', 'g')
        .replaceAll('Ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('Ü', 'u')
        .replaceAll('ö', 'o')
        .replaceAll('Ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll('Ç', 'c')
        .replaceAll('â', 'a')
        .replaceAll('Â', 'a')
        .replaceAll('î', 'i')
        .replaceAll('Î', 'i')
        .replaceAll('û', 'u')
        .replaceAll('Û', 'u');
  }

  Future<void> _showSelectionDialog(
    DutyLocation loc,
    DutyEligibility? current,
  ) async {
    // Aktif / seçili dönemi al
    final selectedTermId = await TermService().getSelectedTermId();
    final activeTermId = await TermService().getActiveTermId();
    final effectiveTermId = selectedTermId ?? activeTermId;

    // Fetch all potential candidates (teachers, staff, admins)
    final userSnap = await FirebaseFirestore.instance
        .collection('users')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('type', whereIn: ['teacher', 'staff', 'admin'])
        .get();

    // Sadece mevcut dönemdeki aktif ve mevcut okul türündeki öğretmenleri/personelleri filtrele
    final allUsers = userSnap.docs
        .map((d) {
          final data = d.data();
          data['id'] = d.id;
          return data;
        })
        .where((data) => _isUserActive(
              data,
              termId: effectiveTermId,
              schoolTypeId: widget.schoolTypeId,
              schoolTypeName: widget.schoolTypeName,
            ))
        .toList();

    // Sort users alphabetically by name
    allUsers.sort((a, b) {
      final nameA = (a['fullName'] ?? a['name'] ?? '').toString();
      final nameB = (b['fullName'] ?? b['name'] ?? '').toString();
      return nameA.compareTo(nameB);
    });

    final selectedIds = List<String>.from(current?.eligibleTeacherIds ?? []);

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) => _StaffSelectionSheet(
        loc: loc,
        allUsers: allUsers,
        initialSelectedIds: selectedIds,
        getUserDisplayTitle: _getUserDisplayTitle,
        normalizeTr: _normalizeTr,
        onSave: (ids) async {
          await _saveEligibility(loc.id, ids, null);
        },
      ),
    );
  }

  Future<void> _saveEligibility(
    String locId,
    List<String> teacherIds,
    String? docId,
  ) async {
    // Save to DutyLocation doc inside "eligibilities" map
    final docRef = FirebaseFirestore.instance
        .collection('dutyLocations')
        .doc(locId);

    // Key needs to be stringified int
    final dayKey = _selectedDay.toString();

    await docRef.update({'eligibilities.$dayKey': teacherIds});
  }

  Future<void> _copyToOtherLocations(
    DutyEligibility? source,
    String sourceName,
    List<DutyLocation> allLocs,
  ) async {
    if (source == null || source.eligibleTeacherIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Kopyalanacak liste boş.')));
      return;
    }

    if (allLocs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kopyalanacak yer bulunamadı.')),
      );
      return;
    }

    const dayNames = [
      '',
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _CopyPoolSheet(
        source: source,
        sourceName: sourceName,
        allLocs: allLocs,
        initialDay: source.dayOfWeek,
        dayNames: dayNames,
        onSave: (selectionsByDay) async {
          final batch = FirebaseFirestore.instance.batch();
          int updatedCount = 0;
          final affectedDays = <int>{};

          for (var entry in selectionsByDay.entries) {
            final day = entry.key;
            final dayKey = day.toString();
            for (var targetId in entry.value) {
              // Kaynak gün ve kaynak yer ise kopyalamaya gerek yok
              if (targetId == source.locationId && day == source.dayOfWeek) {
                continue;
              }
              final docRef = FirebaseFirestore.instance
                  .collection('dutyLocations')
                  .doc(targetId);

              batch.update(docRef, {
                'eligibilities.$dayKey': source.eligibleTeacherIds,
              });
              updatedCount++;
              affectedDays.add(day);
            }
          }

          if (updatedCount > 0) {
            await batch.commit();
            if (mounted) {
              final sortedDays = affectedDays.toList()..sort();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '$sourceName personel havuzu $updatedCount nöbet yerine (${sortedDays.map((d) => dayNames[d]).join(', ')}) başarıyla kopyalandı.',
                  ),
                  backgroundColor: const Color(0xFF10B981),
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          }
        },
      ),
    );
  }
}

class _CopyPoolSheet extends StatefulWidget {
  final DutyEligibility source;
  final String sourceName;
  final List<DutyLocation> allLocs;
  final int initialDay;
  final List<String> dayNames;
  final Future<void> Function(Map<int, Set<String>> selectionsByDay) onSave;

  const _CopyPoolSheet({
    Key? key,
    required this.source,
    required this.sourceName,
    required this.allLocs,
    required this.initialDay,
    required this.dayNames,
    required this.onSave,
  }) : super(key: key);

  @override
  State<_CopyPoolSheet> createState() => _CopyPoolSheetState();
}

class _CopyPoolSheetState extends State<_CopyPoolSheet> {
  late int _selectedDay;
  final Map<int, Set<String>> _selectedLocationsByDay = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = widget.initialDay;
    for (int d = 1; d <= 7; d++) {
      _selectedLocationsByDay[d] = <String>{};
    }

    // Başlangıçta işlem yapılan kaynak gündeki diğer nöbet yerlerini varsayılan olarak seç
    final sourceDayActive = widget.allLocs
        .where((l) => l.activeDays.contains(widget.source.dayOfWeek) && l.id != widget.source.locationId)
        .map((l) => l.id);
    _selectedLocationsByDay[widget.source.dayOfWeek]!.addAll(sourceDayActive);
  }

  int get _totalSelectedCount {
    int total = 0;
    for (var set in _selectedLocationsByDay.values) {
      total += set.length;
    }
    return total;
  }

  int get _selectedDaysCount {
    int count = 0;
    for (var set in _selectedLocationsByDay.values) {
      if (set.isNotEmpty) count++;
    }
    return count;
  }

  void _toggleLocation(int day, String locId) {
    setState(() {
      final set = _selectedLocationsByDay[day] ??= <String>{};
      if (set.contains(locId)) {
        set.remove(locId);
      } else {
        set.add(locId);
      }
    });
  }

  void _selectAllCurrentDay(List<DutyLocation> activeForDay) {
    setState(() {
      final set = _selectedLocationsByDay[_selectedDay] ??= <String>{};
      for (var loc in activeForDay) {
        if (loc.id == widget.source.locationId && _selectedDay == widget.source.dayOfWeek) {
          continue;
        }
        set.add(loc.id);
      }
    });
  }

  void _clearCurrentDay() {
    setState(() {
      _selectedLocationsByDay[_selectedDay]?.clear();
    });
  }

  void _selectSameLocationAllDays() {
    setState(() {
      for (int d = 1; d <= 7; d++) {
        final hasLoc = widget.allLocs.any((l) => l.id == widget.source.locationId && l.activeDays.contains(d));
        if (hasLoc && d != widget.source.dayOfWeek) {
          _selectedLocationsByDay[d] ??= <String>{};
          _selectedLocationsByDay[d]!.add(widget.source.locationId);
        }
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${widget.sourceName}" aktif olduğu diğer tüm günlerde seçildi.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _clearAllSelections() {
    setState(() {
      for (int d = 1; d <= 7; d++) {
        _selectedLocationsByDay[d]?.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeForCurrentDay = widget.allLocs
        .where((l) => l.activeDays.contains(_selectedDay))
        .toList();

    activeForCurrentDay.sort((a, b) => a.order.compareTo(b.order));

    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Sürükleme çizgisi
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Başlık Alanı
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.copy_rounded, color: Colors.orange, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.sourceName} - Havuzu Kopyala',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Kaynak: ${widget.dayNames[widget.source.dayOfWeek]} (${widget.source.eligibleTeacherIds.length} personel)',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),
            const Divider(height: 1),

            // Gün Seçim Çubuğu (YUKARDA GÜNLERİ SEÇTİR - İŞLEM YAPILAN GÜN SEÇİLİ OLSUN)
            Container(
              color: Colors.grey.shade50,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded, size: 15, color: Color(0xFF4F46E5)),
                      const SizedBox(width: 6),
                      Text(
                        'Hedef Günleri Seçin ve Nöbet Yerlerini Belirleyin:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (int d = 1; d <= 7; d++) ...[
                          _buildDayTab(d),
                          if (d < 7) const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Seçili Günün Başlığı ve Hızlı İşlemler
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${widget.dayNames[_selectedDay]} Günü',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      if (_selectedDay == widget.source.dayOfWeek) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.amber.shade400),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star_rounded, size: 12, color: Colors.amber.shade900),
                              const SizedBox(width: 3),
                              Text(
                                'Kaynak Gün',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        '${_selectedLocationsByDay[_selectedDay]?.length ?? 0} / ${activeForCurrentDay.length} seçili',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Hızlı İşlem Butonları
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _buildQuickActionChip(
                        label: 'Bu Günün Tümünü Seç',
                        icon: Icons.done_all_rounded,
                        onTap: activeForCurrentDay.isEmpty
                            ? null
                            : () => _selectAllCurrentDay(activeForCurrentDay),
                      ),
                      _buildQuickActionChip(
                        label: 'Bu Günü Temizle',
                        icon: Icons.remove_done_rounded,
                        onTap: (_selectedLocationsByDay[_selectedDay]?.isEmpty ?? true)
                            ? null
                            : _clearCurrentDay,
                      ),
                      _buildQuickActionChip(
                        label: '"${widget.sourceName}" Tüm Günlerde Seç',
                        icon: Icons.auto_awesome_rounded,
                        highlight: true,
                        onTap: _selectSameLocationAllDays,
                      ),
                      _buildQuickActionChip(
                        label: 'Tümünü Temizle',
                        icon: Icons.clear_all_rounded,
                        onTap: _totalSelectedCount == 0 ? null : _clearAllSelections,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Seçili Günün Nöbet Yerleri Listesi
            Expanded(
              child: activeForCurrentDay.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.event_busy_rounded, size: 40, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text(
                              '${widget.dayNames[_selectedDay]} günü için bu dönemde aktif nöbet yeri yok.',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: activeForCurrentDay.length,
                      itemBuilder: (context, index) {
                        final loc = activeForCurrentDay[index];
                        final isSourceItem = (loc.id == widget.source.locationId && _selectedDay == widget.source.dayOfWeek);
                        final isSameLocOtherDay = (loc.id == widget.source.locationId && _selectedDay != widget.source.dayOfWeek);
                        final isSelected = _selectedLocationsByDay[_selectedDay]?.contains(loc.id) ?? false;

                        return ListTile(
                          tileColor: isSelected
                              ? const Color(0xFF4F46E5).withOpacity(0.06)
                              : Colors.white,
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: isSourceItem
                                ? Colors.amber.shade100
                                : isSelected
                                    ? const Color(0xFF4F46E5)
                                    : Colors.grey.shade200,
                            child: Icon(
                              isSourceItem
                                  ? Icons.star_rounded
                                  : isSelected
                                      ? Icons.check_rounded
                                      : Icons.place_rounded,
                              size: 18,
                              color: isSourceItem
                                  ? Colors.amber.shade900
                                  : isSelected
                                      ? Colors.white
                                      : Colors.grey.shade600,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  loc.name,
                                  style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                    color: const Color(0xFF1E293B),
                                  ),
                                ),
                              ),
                              if (isSourceItem)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Kaynak Havuz',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                )
                              else if (isSameLocOtherDay)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4F46E5).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Aynı Nöbet Yeri',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF4F46E5),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            isSourceItem
                                ? 'Kopyalanan havuzun kaynağıdır.'
                                : loc.startTime.isNotEmpty && loc.endTime.isNotEmpty
                                    ? 'Saat: ${loc.startTime} - ${loc.endTime}'
                                    : 'Nöbet Yeri',
                            style: TextStyle(
                              fontSize: 12,
                              color: isSourceItem ? Colors.amber.shade900 : Colors.grey.shade600,
                            ),
                          ),
                          trailing: Checkbox(
                            value: isSourceItem ? false : isSelected,
                            activeColor: const Color(0xFF4F46E5),
                            onChanged: isSourceItem
                                ? null
                                : (val) => _toggleLocation(_selectedDay, loc.id),
                          ),
                          onTap: isSourceItem
                              ? null
                              : () => _toggleLocation(_selectedDay, loc.id),
                        );
                      },
                    ),
            ),

            const Divider(height: 1),

            // Alt Eylem Çubuğu
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _totalSelectedCount == 0
                              ? 'Henüz hedef yer seçilmedi'
                              : '$_totalSelectedCount hedef yer seçildi',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _totalSelectedCount == 0
                                ? Colors.red.shade700
                                : const Color(0xFF1E293B),
                          ),
                        ),
                        if (_totalSelectedCount > 0)
                          Text(
                            '$_selectedDaysCount farklı günde uygulanacak',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text('İptal'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: (_totalSelectedCount == 0 || _isSaving)
                        ? null
                        : () async {
                            setState(() => _isSaving = true);
                            try {
                              await widget.onSave(_selectedLocationsByDay);
                              if (mounted) Navigator.pop(context);
                            } finally {
                              if (mounted) setState(() => _isSaving = false);
                            }
                          },
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.copy_rounded, size: 16),
                    label: Text(_isSaving ? 'Kopyalanıyor...' : 'Kopyala ve Uygula'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayTab(int d) {
    final isCurrent = (d == _selectedDay);
    final count = _selectedLocationsByDay[d]?.length ?? 0;
    final isSourceDay = (d == widget.source.dayOfWeek);

    return InkWell(
      onTap: () => setState(() => _selectedDay = d),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isCurrent
              ? const Color(0xFF4F46E5)
              : count > 0
                  ? const Color(0xFFEEF2FF)
                  : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isCurrent
                ? const Color(0xFF4F46E5)
                : count > 0
                    ? const Color(0xFF818CF8)
                    : Colors.grey.shade300,
            width: isCurrent || count > 0 ? 1.5 : 1,
          ),
          boxShadow: isCurrent
              ? [
                  BoxShadow(
                    color: const Color(0xFF4F46E5).withOpacity(0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSourceDay) ...[
              Icon(
                Icons.star_rounded,
                size: 14,
                color: isCurrent ? Colors.amberAccent : Colors.amber.shade800,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              widget.dayNames[d],
              style: TextStyle(
                fontSize: 13,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                color: isCurrent
                    ? Colors.white
                    : count > 0
                        ? const Color(0xFF4338CA)
                        : Colors.grey.shade800,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isCurrent ? Colors.white : const Color(0xFF4F46E5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isCurrent ? const Color(0xFF4F46E5) : Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionChip({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    bool highlight = false,
  }) {
    final isEnabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: !isEnabled
              ? Colors.grey.shade100
              : highlight
                  ? const Color(0xFF4F46E5).withOpacity(0.1)
                  : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: !isEnabled
                ? Colors.grey.shade200
                : highlight
                    ? const Color(0xFF4F46E5).withOpacity(0.35)
                    : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: !isEnabled
                  ? Colors.grey.shade400
                  : highlight
                      ? const Color(0xFF4F46E5)
                      : Colors.grey.shade700,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isEnabled ? FontWeight.bold : FontWeight.normal,
                color: !isEnabled
                    ? Colors.grey.shade400
                    : highlight
                        ? const Color(0xFF4F46E5)
                        : Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffSelectionSheet extends StatefulWidget {
  final DutyLocation loc;
  final List<Map<String, dynamic>> allUsers;
  final List<String> initialSelectedIds;
  final String Function(Map<String, dynamic>) getUserDisplayTitle;
  final String Function(String) normalizeTr;
  final Future<void> Function(List<String> selectedIds) onSave;

  const _StaffSelectionSheet({
    Key? key,
    required this.loc,
    required this.allUsers,
    required this.initialSelectedIds,
    required this.getUserDisplayTitle,
    required this.normalizeTr,
    required this.onSave,
  }) : super(key: key);

  @override
  State<_StaffSelectionSheet> createState() => _StaffSelectionSheetState();
}

class _StaffSelectionSheetState extends State<_StaffSelectionSheet> {
  late final TextEditingController _searchController;
  late final Set<String> _selectedIds;
  String _searchQuery = '';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _selectedIds = Set.from(widget.initialSelectedIds);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showBulkPaste() async {
    final textController = TextEditingController();

    final newlySelected = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.paste_rounded, color: Color(0xFF4F46E5), size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Excel / Metin Kopyala ve Seç',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Excel\'den kopyaladığınız isim sütununu veya alt alta personel isimlerini buraya yapıştırın. Sistem Türkçe karakter ve büyük/küçük harf duyarsız olarak eşleşen personelleri seçecektir.',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Personel İsimleri:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final clipData = await Clipboard.getData(Clipboard.kTextPlain);
                          if (clipData?.text != null && clipData!.text!.isNotEmpty) {
                            textController.text = clipData.text!;
                          }
                        },
                        icon: const Icon(Icons.content_paste, size: 16),
                        label: const Text('Panodan Yapıştır', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF4F46E5),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: textController,
                    maxLines: 8,
                    minLines: 4,
                    style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                          hintText: 'Örnek:\nAhmet Yılmaz\nFatma Kaya\nMehmet Demir\n...',
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('İptal'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final rawText = textController.text;
                if (rawText.trim().isEmpty) {
                  Navigator.pop(dialogContext);
                  return;
                }

                final lines = rawText.split(RegExp(r'[\r\n]+'));
                final matchedIds = <String>{};
                final unmatchedLines = <String>[];

                for (var line in lines) {
                  final rawLine = line.trim();
                  if (rawLine.isEmpty) continue;

                  final cells = rawLine
                      .split(RegExp(r'[\t;]'))
                      .map((c) => c.trim())
                      .where((c) => c.isNotEmpty)
                      .toList();

                  Map<String, dynamic>? matchedUser;

                  for (var cell in cells) {
                    final normCell = widget.normalizeTr(cell).replaceAll(RegExp(r'\s+'), ' ').trim();
                    final cleanCell = normCell.replaceAll(RegExp(r'^\d+[\.\-\)\s]+'), '').trim();
                    if (cleanCell.isEmpty) continue;

                    for (var u in widget.allUsers) {
                      final uFullName = (u['fullName'] ?? u['name'] ?? '').toString().trim();
                      final normFullName = widget.normalizeTr(uFullName).replaceAll(RegExp(r'\s+'), ' ').trim();
                      if (normFullName.isEmpty) continue;

                      if (normFullName == cleanCell || normFullName == normCell) {
                        matchedUser = u;
                        break;
                      }

                      final uWords = normFullName.split(' ').where((w) => w.length > 1).toSet();
                      final cellWords = cleanCell.split(' ').where((w) => w.length > 1).toSet();
                      if (uWords.isNotEmpty && cellWords.isNotEmpty) {
                        if (uWords.length == cellWords.length && uWords.difference(cellWords).isEmpty) {
                          matchedUser = u;
                          break;
                        }
                      }

                      if (cleanCell.contains(normFullName) && normFullName.length >= 4) {
                        matchedUser = u;
                        break;
                      }
                      if (normFullName.contains(cleanCell) && cleanCell.length >= 5) {
                        matchedUser = u;
                        break;
                      }
                    }
                    if (matchedUser != null) break;
                  }

                  if (matchedUser == null) {
                    final normLine = widget.normalizeTr(rawLine).replaceAll(RegExp(r'\s+'), ' ').trim();
                    final cleanLine = normLine.replaceAll(RegExp(r'^\d+[\.\-\)\s]+'), '').trim();

                    for (var u in widget.allUsers) {
                      final uFullName = (u['fullName'] ?? u['name'] ?? '').toString().trim();
                      final normFullName = widget.normalizeTr(uFullName).replaceAll(RegExp(r'\s+'), ' ').trim();
                      if (normFullName.isEmpty) continue;

                      if (cleanLine.contains(normFullName) && normFullName.length >= 4) {
                        matchedUser = u;
                        break;
                      }

                      final uWords = normFullName.split(' ').where((w) => w.length > 1).toSet();
                      final lineWords = cleanLine.split(' ').where((w) => w.length > 1).toSet();
                      if (uWords.isNotEmpty && uWords.every((w) => lineWords.contains(w))) {
                        matchedUser = u;
                        break;
                      }
                    }
                  }

                  if (matchedUser != null) {
                    final uId = matchedUser['id'] as String?;
                    if (uId != null && uId.isNotEmpty) {
                      matchedIds.add(uId);
                    }
                  } else {
                    unmatchedLines.add(rawLine);
                  }
                }

                Navigator.pop(dialogContext, matchedIds.toList());

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      unmatchedLines.isEmpty
                          ? '${matchedIds.length} personel eşleştirildi ve seçildi.'
                          : '${matchedIds.length} personel seçildi. (${unmatchedLines.length} satır eşleşmedi: ${unmatchedLines.take(3).join(', ')}${unmatchedLines.length > 3 ? '...' : ''})',
                    ),
                    duration: Duration(seconds: unmatchedLines.isEmpty ? 3 : 5),
                    backgroundColor: unmatchedLines.isEmpty
                        ? const Color(0xFF10B981)
                        : Colors.orange.shade800,
                  ),
                );
              },
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Eşleştir ve Seç'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );

    textController.dispose();

    if (newlySelected != null && newlySelected.isNotEmpty) {
      setState(() {
        _selectedIds.addAll(newlySelected);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final normQuery = widget.normalizeTr(_searchQuery.trim());

    final filteredUsers = widget.allUsers.where((u) {
      if (normQuery.isEmpty) return true;
      final name = widget.normalizeTr((u['fullName'] ?? u['name'] ?? '').toString());
      final branch = widget.getUserDisplayTitle(u);
      final normBranch = widget.normalizeTr(branch);
      return name.contains(normQuery) || normBranch.contains(normQuery);
    }).toList();

    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Sürükleme çizgisi
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Başlık ve Kaydet Butonu
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${widget.loc.name} - Personel Seçimi',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _isSaving
                        ? null
                        : () async {
                            setState(() => _isSaving = true);
                            try {
                              await widget.onSave(_selectedIds.toList());
                              if (mounted) Navigator.pop(context);
                            } finally {
                              if (mounted) setState(() => _isSaving = false);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text(
                            'Kaydet',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // Arama Kutusu
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Personel Ara...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onChanged: (val) {
                      setState(() => _searchQuery = val);
                    },
                  ),
                  const SizedBox(height: 8),
                  // Excel / Metin Kopyala ve Seç Butonu
                  InkWell(
                    onTap: _showBulkPaste,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF4F46E5).withOpacity(0.2)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.paste_rounded, size: 18, color: Color(0xFF4F46E5)),
                          SizedBox(width: 8),
                          Text(
                            "Excel / Metin Kopyala ve Seç",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4F46E5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Seçili Sayısı ve Hızlı Seçim Butonları
                  Row(
                    children: [
                      Text(
                        '${_selectedIds.length} kişi seçildi',
                        style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            for (var u in filteredUsers) {
                              final id = u['id'] as String;
                              _selectedIds.add(id);
                            }
                          });
                        },
                        child: Text(
                          normQuery.isEmpty
                              ? 'Tümünü Seç'
                              : 'Filtrelenenleri Seç (${filteredUsers.length})',
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            if (normQuery.isEmpty) {
                              _selectedIds.clear();
                            } else {
                              final filteredIds = filteredUsers.map((u) => u['id'] as String).toSet();
                              _selectedIds.removeWhere((id) => filteredIds.contains(id));
                            }
                          });
                        },
                        child: const Text('Temizle'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Personel Listesi
            Expanded(
              child: filteredUsers.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          '"$_searchQuery" ile eşleşen personel bulunamadı.',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredUsers.length,
                      itemBuilder: (context, index) {
                        final u = filteredUsers[index];
                        final uId = u['id'] as String;
                        final uName = u['fullName'] ?? u['name'] ?? 'İsimsiz';
                        final isSelected = _selectedIds.contains(uId);
                        final branch = widget.getUserDisplayTitle(u);

                        return ListTile(
                          tileColor: isSelected
                              ? const Color(0xFF4F46E5).withOpacity(0.06)
                              : Colors.white,
                          leading: CircleAvatar(
                            backgroundColor: isSelected
                                ? const Color(0xFF4F46E5)
                                : Colors.grey.shade200,
                            child: Text(
                              uName.isNotEmpty ? uName.substring(0, 1).toUpperCase() : '?',
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            uName,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                              color: const Color(0xFF1E293B),
                            ),
                          ),
                          subtitle: Text(
                            branch,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          trailing: Checkbox(
                            value: isSelected,
                            activeColor: const Color(0xFF4F46E5),
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedIds.add(uId);
                                } else {
                                  _selectedIds.remove(uId);
                                }
                              });
                            },
                          ),
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedIds.remove(uId);
                              } else {
                                _selectedIds.add(uId);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
