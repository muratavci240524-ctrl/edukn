import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/school/inventory_procurement_models.dart';
import '../../../services/inventory_procurement_service.dart';
import 'inventory_ui_widgets.dart';

/// Depo Tanımlama (Merkez / Okul Türü Bazlı) ve 1./2. Kademe Onay Yetkilisi Ayarları (Tam Alttan Açılan Modern Panel)
class ProcurementSettingsSheet extends StatefulWidget {
  final String institutionId;
  final String schoolDocId;
  final String? fixedSchoolTypeId;
  final String? fixedSchoolTypeName;
  final List<WarehouseModel> currentWarehouses;
  final ProcurementConfigModel currentConfig;

  const ProcurementSettingsSheet({
    super.key,
    required this.institutionId,
    required this.schoolDocId,
    this.fixedSchoolTypeId,
    this.fixedSchoolTypeName,
    required this.currentWarehouses,
    required this.currentConfig,
  });

  static Future<void> show(
    BuildContext context, {
    required String institutionId,
    required String schoolDocId,
    String? fixedSchoolTypeId,
    String? fixedSchoolTypeName,
    required List<WarehouseModel> currentWarehouses,
    required ProcurementConfigModel currentConfig,
  }) {
    return showInventoryBottomSheet<void>(
      context: context,
      maxWidth: 740,
      builder: (_) => ProcurementSettingsSheet(
        institutionId: institutionId,
        schoolDocId: schoolDocId,
        fixedSchoolTypeId: fixedSchoolTypeId,
        fixedSchoolTypeName: fixedSchoolTypeName,
        currentWarehouses: currentWarehouses,
        currentConfig: currentConfig,
      ),
    );
  }

  @override
  State<ProcurementSettingsSheet> createState() =>
      _ProcurementSettingsSheetState();
}

class _ProcurementSettingsSheetState extends State<ProcurementSettingsSheet> {
  final _service = InventoryProcurementService();

  bool _loadingMeta = true;
  bool _savingConfig = false;

  List<({String id, String name})> _schoolTypes = [];
  List<({String uid, String name, String role})> _staffList = [];

  late Set<String> _supervisorUids;
  late Set<String> _upperApproverUids;
  late bool _requireSecondLevel;
  late bool _autoRecordAccounting;

  @override
  void initState() {
    super.initState();
    _supervisorUids = Set<String>.from(widget.currentConfig.supervisorUids);
    _upperApproverUids =
        Set<String>.from(widget.currentConfig.upperApproverUids);
    _requireSecondLevel = widget.currentConfig.requireSecondLevelForPurchase;
    _autoRecordAccounting = widget.currentConfig.autoRecordAccountingExpense;
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    try {
      final variants = {
        widget.institutionId.trim(),
        widget.institutionId.trim().toUpperCase(),
        widget.institutionId.trim().toLowerCase(),
      }.where((e) => e.isNotEmpty).toList();

      final stMap = <String, String>{};
      for (final colName in const ['schoolTypes', 'school_types']) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection(colName)
              .where('institutionId', whereIn: variants)
              .get();
          for (final d in snap.docs) {
            final name = (d.data()['name'] ?? d.data()['schoolTypeName'] ?? '')
                .toString()
                .trim();
            if (name.isNotEmpty) stMap[d.id] = name;
          }
        } catch (_) {}
      }

      final staff = await _service.fetchInstitutionStaff(widget.institutionId);

      if (!mounted) return;
      setState(() {
        _schoolTypes = stMap.entries
            .map((e) => (id: e.key, name: e.value))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        _staffList = staff;
        _loadingMeta = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMeta = false);
    }
  }

  List<({String uid, String name, String role})> _approverCandidates(
    Set<String> currentlySelected,
  ) {
    const adminRoles = {
      'admin',
      'kurucu',
      'genel_mudur',
      'mudur',
      'mudur_yardimcisi',
      'satin_alma',
      'muhasebe',
      'mali_isler',
      'insan_kaynaklari',
      'hr',
    };
    final filtered = _staffList.where((s) {
      if (currentlySelected.contains(s.uid)) return true;
      return adminRoles.contains(s.role.toLowerCase());
    }).toList();
    return filtered.isNotEmpty ? filtered : _staffList;
  }

  Future<void> _saveApprovalConfig() async {
    setState(() => _savingConfig = true);
    try {
      final supNames = _staffList
          .where((s) => _supervisorUids.contains(s.uid))
          .map((s) => s.name)
          .toList();
      final upperNames = _staffList
          .where((s) => _upperApproverUids.contains(s.uid))
          .map((s) => s.name)
          .toList();

      final cfg = ProcurementConfigModel(
        supervisorUids: _supervisorUids.toList(),
        supervisorNames: supNames,
        upperApproverUids: _upperApproverUids.toList(),
        upperApproverNames: upperNames,
        requireSecondLevelForPurchase: _requireSecondLevel,
        autoRecordAccountingExpense: _autoRecordAccounting,
        defaultKasaId: widget.currentConfig.defaultKasaId,
      );

      await _service.saveProcurementConfig(
        schoolDocId: widget.schoolDocId,
        config: cfg,
      );
      if (!mounted) return;
      setState(() => _savingConfig = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Onay ve entegrasyon ayarları kaydedildi.'),
          backgroundColor: Color(0xFF059669),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _savingConfig = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  Future<void> _openWarehouseSheet([WarehouseModel? existing]) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final locCtrl = TextEditingController(text: existing?.location ?? '');
    final hasFixedSt = (widget.fixedSchoolTypeId ?? '').trim().isNotEmpty;

    String whType = existing?.type ?? (hasFixedSt ? 'schoolType' : 'central');
    String selectedStId = existing?.schoolTypeId ??
        (hasFixedSt
            ? widget.fixedSchoolTypeId!
            : (_schoolTypes.isNotEmpty ? _schoolTypes.first.id : ''));
    final selectedKeepers =
        Set<String>.from(existing?.responsibleUserIds ?? const []);

    final keeperCandidates = _staffList
        .where(
          (s) =>
              s.role == 'depo' ||
              s.role == 'destek_hizmetleri' ||
              s.role == 'personel' ||
              selectedKeepers.contains(s.uid),
        )
        .toList();

    final saved = await showInventoryBottomSheet<bool>(
      context: context,
      maxWidth: 640,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return InventoryBottomSheetFrame(
            title: existing == null ? 'Yeni Depo Tanımla' : 'Depo Bilgilerini Düzenle',
            subtitle:
                'Merkez ana depo veya okul türüne özel bağımsız alt depo oluşturun.',
            icon: Icons.warehouse_rounded,
            accentColor: const Color(0xFF0D9488),
            footer: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF475569),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: const Text(
                      'Vazgeç',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () {
                      if (nameCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Lütfen depo adını giriniz.'),
                            backgroundColor: Color(0xFFD97706),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(ctx, true);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9488),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 19),
                    label: Text(
                      existing == null ? 'Depoyu Oluştur' : 'Değişiklikleri Kaydet',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InventoryTextField(
                  controller: nameCtrl,
                  label: 'Depo Adı',
                  isRequired: true,
                  hint: 'Örn: Merkez Ana Depo, Ortaokul Kırtasiye Deposu',
                  icon: Icons.warehouse_outlined,
                  accentColor: const Color(0xFF0D9488),
                ),
                const SizedBox(height: 16),
                if (!hasFixedSt) ...[
                  const InventoryFieldLabel('Depo Kapsamı'),
                  Row(
                    children: [
                      Expanded(
                        child: _WarehouseScopeCard(
                          title: 'Merkez Ana Depo',
                          subtitle: 'Tüm birimler için ortak',
                          icon: Icons.domain_rounded,
                          selected: whType == 'central',
                          onTap: () => setSheetState(() => whType = 'central'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _WarehouseScopeCard(
                          title: 'Okul Türü Deposu',
                          subtitle: 'Sadece seçili okula özel',
                          icon: Icons.school_rounded,
                          selected: whType == 'schoolType',
                          onTap: () =>
                              setSheetState(() => whType = 'schoolType'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                if (whType == 'schoolType' &&
                    !hasFixedSt &&
                    _schoolTypes.isNotEmpty) ...[
                  InventoryDropdownField<String>(
                    label: 'Bağlı Olduğu Okul Türü',
                    isRequired: true,
                    icon: Icons.apartment_rounded,
                    accentColor: const Color(0xFF0D9488),
                    value: _schoolTypes.any((e) => e.id == selectedStId)
                        ? selectedStId
                        : _schoolTypes.first.id,
                    items: _schoolTypes
                        .map(
                          (st) => DropdownMenuItem(
                            value: st.id,
                            child: Text(st.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setSheetState(() => selectedStId = v);
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                InventoryTextField(
                  controller: locCtrl,
                  label: 'Bina / Kat / Konum Bilgisi',
                  trailingText: 'İsteğe Bağlı',
                  hint: 'Örn: A Blok -1. Kat Koridor Sonu',
                  icon: Icons.place_outlined,
                  accentColor: const Color(0xFF0D9488),
                ),
                const SizedBox(height: 16),
                const InventoryFieldLabel(
                  'Sorumlu Depocu Personel',
                  trailingText: 'Boş ise tüm depocular erişir',
                ),
                InventoryStaffMultiSelector(
                  staffList: keeperCandidates,
                  selectedUids: selectedKeepers,
                  emptyText:
                      'Henüz "Depo Sorumlusu" rolünde personel tanımlanmamış. Tüm yetkili depocular bu depoyu yönetebilir.',
                  onToggle: (uid) {
                    setSheetState(() {
                      if (selectedKeepers.contains(uid)) {
                        selectedKeepers.remove(uid);
                      } else {
                        selectedKeepers.add(uid);
                      }
                    });
                  },
                ),
              ],
            ),
          );
        },
      ),
    );

    if (saved != true || nameCtrl.text.trim().isEmpty) return;

    String stName = '';
    if (whType == 'schoolType') {
      if (hasFixedSt) {
        stName = widget.fixedSchoolTypeName ?? 'Okul Türü';
      } else {
        stName = _schoolTypes
                .where((e) => e.id == selectedStId)
                .firstOrNull
                ?.name ??
            '';
      }
    }

    final keeperNames = _staffList
        .where((s) => selectedKeepers.contains(s.uid))
        .map((s) => s.name)
        .toList();

    final model = WarehouseModel(
      id: existing?.id ?? '',
      institutionId: widget.institutionId,
      schoolDocId: widget.schoolDocId,
      name: nameCtrl.text.trim(),
      type: whType,
      schoolTypeId: whType == 'schoolType' ? selectedStId : '',
      schoolTypeName: whType == 'schoolType' ? stName : '',
      location: locCtrl.text.trim(),
      responsibleUserIds: selectedKeepers.toList(),
      responsibleNames: keeperNames,
      createdAt: existing?.createdAt ?? DateTime.now(),
    );

    await _service.saveWarehouse(
      schoolDocId: widget.schoolDocId,
      warehouse: model,
    );
  }

  @override
  Widget build(BuildContext context) {
    return InventoryBottomSheetFrame(
      title: 'Depolar & Onay Yetkilisi Ayarları',
      subtitle:
          'Kurum depolarını, 1./2. kademe onay makamlarını ve muhasebe entegrasyonunu yönetin.',
      icon: Icons.tune_rounded,
      accentColor: const Color(0xFF4F46E5),
      footer: SizedBox(
        width: double.infinity,
        height: 50,
        child: FilledButton.icon(
          onPressed:
              (_savingConfig || _loadingMeta) ? null : _saveApprovalConfig,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF4F46E5),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
          icon: _savingConfig
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_rounded, size: 19),
          label: Text(
            _savingConfig
                ? 'Ayarlar Kaydediliyor...'
                : 'Onay ve Muhasebe Ayarlarını Kaydet',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
      ),
      child: _loadingMeta
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 56),
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. TANIMLI DEPOLAR BÖLÜMÜ
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tanımlı Depolar',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Merkez depo ve okul türlerine özel bağımsız alt depolar',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _openWarehouseSheet(),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFEEF2FF),
                        foregroundColor: const Color(0xFF4F46E5),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 9,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                      icon: const Icon(Icons.add_business_rounded, size: 17),
                      label: const Text(
                        'Yeni Depo Aç',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                StreamBuilder<List<WarehouseModel>>(
                  stream: _service.watchVisibleWarehouses(
                    schoolDocId: widget.schoolDocId,
                    fixedSchoolTypeId: widget.fixedSchoolTypeId,
                  ),
                  builder: (context, snap) {
                    final whs = snap.data ?? widget.currentWarehouses;
                    if (whs.isEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Text(
                          'Bu görünümde tanımlı depo bulunmuyor. "Yeni Depo Aç" butonu ile oluşturabilirsiniz.',
                          style: TextStyle(
                            fontSize: 12.8,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: whs.map((w) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: w.isCentral
                                      ? const Color(0xFFEEF2FF)
                                      : const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  w.isCentral
                                      ? Icons.domain_rounded
                                      : Icons.warehouse_rounded,
                                  size: 20,
                                  color: w.isCentral
                                      ? const Color(0xFF4F46E5)
                                      : const Color(0xFF059669),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            w.name,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF0F172A),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: w.isCentral
                                                ? const Color(0xFFE0E7FF)
                                                : const Color(0xFFD1FAE5),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            w.isCentral
                                                ? 'Merkez'
                                                : w.schoolTypeName,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w800,
                                              color: w.isCentral
                                                  ? const Color(0xFF3730A3)
                                                  : const Color(0xFF065F46),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      [
                                        if (w.location.isNotEmpty)
                                          'Konum: ${w.location}',
                                        if (w.responsibleNames.isNotEmpty)
                                          'Sorumlu: ${w.responsibleNames.join(', ')}'
                                        else
                                          'Tüm depocular yetkili',
                                      ].join(' • '),
                                      style: const TextStyle(
                                        fontSize: 11.8,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Düzenle',
                                onPressed: () => _openWarehouseSheet(w),
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  size: 19,
                                  color: Color(0xFF475569),
                                ),
                              ),
                              if (whs.length > 1)
                                IconButton(
                                  tooltip: 'Arşivle',
                                  onPressed: () => _service.archiveWarehouse(
                                    schoolDocId: widget.schoolDocId,
                                    warehouseId: w.id,
                                  ),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 19,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                ),

                // 2. 1. KADEME AMİR ONAY YETKİLİLERİ
                const Text(
                  '1. Kademe Amir Onay Yetkilileri',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Seçim yapılmazsa varsayılan olarak Müdür ve Müdür Yardımcıları 1. kademe onay verebilir.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                InventoryStaffMultiSelector(
                  staffList: _approverCandidates(_supervisorUids),
                  selectedUids: _supervisorUids,
                  onToggle: (uid) {
                    setState(() {
                      if (_supervisorUids.contains(uid)) {
                        _supervisorUids.remove(uid);
                      } else {
                        _supervisorUids.add(uid);
                      }
                    });
                  },
                ),

                const SizedBox(height: 20),

                // 3. 2. KADEME ÜST ONAY YETKİLİSİ
                const Text(
                  '2. Kademe Üst Onay Yetkilisi (Satın Alma Oluru & Teklif Seçimi)',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Depoda stok olmadığında satın almaya sevk oluru verecek ve tedarikçi teklifini onaylayacak üst yetkili(ler). Boş bırakılırsa Genel Müdür / Kurum Müdürü yetkilidir.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                InventoryStaffMultiSelector(
                  staffList: _approverCandidates(_upperApproverUids),
                  selectedUids: _upperApproverUids,
                  onToggle: (uid) {
                    setState(() {
                      if (_upperApproverUids.contains(uid)) {
                        _upperApproverUids.remove(uid);
                      } else {
                        _upperApproverUids.add(uid);
                      }
                    });
                  },
                ),

                const SizedBox(height: 20),

                // 4. OTOMASYON & MUHASEBE KURALLARI
                InventoryToggleCard(
                  icon: Icons.verified_user_outlined,
                  accentColor: const Color(0xFF4F46E5),
                  title:
                      'Stokta olmayan ürünlerde 2. kademe üst yetkili oluru zorunlu olsun',
                  subtitle:
                      'Açık olduğunda, stok dışı talepler satın alma birimine düşmeden önce üst yönetici onayı bekler.',
                  value: _requireSecondLevel,
                  onChanged: (v) => setState(() => _requireSecondLevel = v),
                ),
                const SizedBox(height: 10),
                InventoryToggleCard(
                  icon: Icons.account_balance_wallet_outlined,
                  accentColor: const Color(0xFF059669),
                  title:
                      'Depocu mal kabul verdiğinde Mali İşler (Kasa/Gider) modülüne otomatik gider işlensin',
                  subtitle:
                      'Onaylanan tedarikçi teklifi tutarı, mal kabul anında seçilen kasadan otomatik düşülür.',
                  value: _autoRecordAccounting,
                  onChanged: (v) => setState(() => _autoRecordAccounting = v),
                ),
              ],
            ),
    );
  }
}

class _WarehouseScopeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _WarehouseScopeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF0D9488);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.08)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent : const Color(0xFFD5DFEC),
            width: selected ? 1.7 : 1.1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? accent : const Color(0xFF64748B),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.8,
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? const Color(0xFF134E4A)
                          : const Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
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
}
