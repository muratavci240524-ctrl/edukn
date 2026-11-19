import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/store/store_models.dart';
import '../../../services/store_service.dart';
import '../../../widgets/edukn_app_bar.dart';
import '../../../widgets/school_pos_settings_dialog.dart';
import '../../../widgets/store_product_dialog.dart';
import '../../store/store_shop_screen.dart';

/// Okul Yönetimi — Bağımsız Okul Mağazası & Online Satış Ekranı:
/// 1) Okul Ürünlerimiz (Okulun kendi forma, kırtasiye, kitap, etkinlik ürünlerini ekleme/düzenleme)
/// 2) Okul Siparişleri (Okul mağazasına gelen online siparişleri ve ciroyu yönetme)
/// 3) Mağaza Vitrini (Alışveriş Yap — İdareci olarak Genel Merkez + Okul vitrininden online alım)
class SchoolStoreManagementScreen extends StatefulWidget {
  final String institutionId;
  final String? schoolId;
  final String? schoolName;
  final String? schoolTypeId;
  final int initialTabIndex;

  const SchoolStoreManagementScreen({
    super.key,
    required this.institutionId,
    this.schoolId,
    this.schoolName,
    this.schoolTypeId,
    this.initialTabIndex = 0,
  });

  @override
  State<SchoolStoreManagementScreen> createState() =>
      _SchoolStoreManagementScreenState();
}

class _SchoolStoreManagementScreenState
    extends State<SchoolStoreManagementScreen>
    with SingleTickerProviderStateMixin {
  final StoreService _storeService = StoreService();
  final NumberFormat _currencyFmt = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: '₺',
    decimalDigits: 2,
  );
  final TextEditingController _productSearchCtrl = TextEditingController();
  final TextEditingController _orderSearchCtrl = TextEditingController();

  late final TabController _tabController;
  late Stream<List<StoreProduct>> _schoolProductsStream;
  late Stream<List<StoreOrder>> _schoolOrdersStream;

  String _resolvedSchoolName = '';
  String? _resolvedSchoolId;
  List<StoreSchoolTypeOption> _schoolTypes = const [];
  List<StoreClassOption> _schoolClasses = const [];

  String _productCategoryFilter = 'Tümü';
  String _productSearch = '';

  String _orderStatusFilter = 'Tümü';
  String _orderRoleFilter = 'Tümü';
  String _orderSearch = '';

  String get _instUpper => widget.institutionId.trim().toUpperCase();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
    _resolvedSchoolName = widget.schoolName?.trim() ?? '';
    _resolvedSchoolId = widget.schoolId;
    _bindSchoolStreams();
    _loadSchoolMetadata();
  }

  void _bindSchoolStreams() {
    _schoolProductsStream = _storeService.watchSchoolProducts(_instUpper);
    _schoolOrdersStream = _storeService.watchSchoolOrders(_instUpper);
  }

  @override
  void didUpdateWidget(covariant SchoolStoreManagementScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.institutionId.trim().toUpperCase() != _instUpper) {
      _bindSchoolStreams();
      _loadSchoolMetadata();
    }
  }

  Future<void> _loadSchoolMetadata() async {
    try {
      final results = await Future.wait([
        _storeService.loadSchoolTypesForInstitution(_instUpper),
        _storeService.loadClassesForInstitution(_instUpper),
      ]);
      final types = results[0] as List<StoreSchoolTypeOption>;
      final classes = results[1] as List<StoreClassOption>;
      final ctx = await _storeService.resolveBuyerContext(
        institutionId: _instUpper,
        buyerRole: StoreBuyerRoles.idareci,
        schoolId: widget.schoolId,
        schoolName: widget.schoolName,
        schoolTypeId: widget.schoolTypeId,
      );
      if (!mounted) return;
      setState(() {
        _schoolTypes = types;
        _schoolClasses = classes;
        if (_resolvedSchoolName.isEmpty) {
          _resolvedSchoolName = ctx.schoolName;
        }
        _resolvedSchoolId ??= ctx.schoolId;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    _productSearchCtrl.dispose();
    _orderSearchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCompactHeader = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: EduknAppBar(
        title: 'Okul Mağazası & Online Satış',
        institutionId: _instUpper,
        subtitle: _resolvedSchoolName.isNotEmpty
            ? _resolvedSchoolName
            : _instUpper,
        actions: [
          Padding(
            padding: EdgeInsets.only(right: isCompactHeader ? 2 : 6),
            child: isCompactHeader
                ? IconButton(
                    icon: const Icon(Icons.point_of_sale_rounded),
                    tooltip: 'Sanal POS Ayarları',
                    onPressed: () => SchoolPosSettingsDialog.show(
                      context,
                      institutionId: _instUpper,
                      institutionTitle: _resolvedSchoolName,
                      initialTab: 1,
                    ),
                  )
                : OutlinedButton.icon(
                    onPressed: () => SchoolPosSettingsDialog.show(
                      context,
                      institutionId: _instUpper,
                      institutionTitle: _resolvedSchoolName,
                      initialTab: 1,
                    ),
                    icon: const Icon(Icons.point_of_sale_rounded, size: 18),
                    label: const Text('Sanal POS Ayarları'),
                  ),
          ),
          Padding(
            padding: EdgeInsets.only(right: isCompactHeader ? 4 : 10),
            child: isCompactHeader
                ? IconButton(
                    icon: const Icon(Icons.tune_rounded),
                    tooltip: 'Mağaza Ayarları',
                    onPressed: _openSchoolStoreSettingsDialog,
                  )
                : OutlinedButton.icon(
                    onPressed: _openSchoolStoreSettingsDialog,
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('Mağaza Ayarları'),
                  ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: MediaQuery.of(context).size.width < 780,
          labelColor: Colors.indigo.shade900,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: Colors.indigo.shade700,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800),
          tabs: const [
            Tab(
              icon: Icon(Icons.inventory_2_outlined, size: 20),
              text: 'Okul Ürünlerimiz',
            ),
            Tab(
              icon: Icon(Icons.local_shipping_outlined, size: 20),
              text: 'Okul Siparişleri',
            ),
            Tab(
              icon: Icon(Icons.shopping_bag_outlined, size: 20),
              text: 'Mağaza Vitrini (Alışveriş Yap)',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSchoolProductsTab(),
          _buildSchoolOrdersTab(),
          StoreShopScreen(
            institutionId: _instUpper,
            schoolId: _resolvedSchoolId,
            schoolName: _resolvedSchoolName.isNotEmpty
                ? _resolvedSchoolName
                : null,
            schoolTypeId: widget.schoolTypeId,
            buyerRole: StoreBuyerRoles.idareci,
            embedded: true,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OKUL MAĞAZA AYARLARI DİYALOĞU
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _openSchoolStoreSettingsDialog() async {
    final current = await _storeService.getSchoolSettings(_instUpper);
    if (!mounted) return;

    bool enabled = current.isSchoolStoreEnabled;
    bool allowPickup = current.allowPickupAtSchool;
    bool allowHome = current.allowHomeDelivery;
    final Set<String> enabledTypeIds = Set<String>.from(
      current.enabledSchoolTypeIds,
    );
    final shippingCtrl = TextEditingController(
      text: current.shippingFee.toStringAsFixed(2),
    );
    final freeCtrl = TextEditingController(
      text: current.freeShippingThreshold.toStringAsFixed(0),
    );
    final bannerCtrl = TextEditingController(text: current.announcementBanner);
    final noteCtrl = TextEditingController(text: current.ibanOrPosNote);
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        InputDecoration modalDeco(
          String label, {
          String? hint,
          IconData? icon,
          String? prefixText,
        }) {
          OutlineInputBorder b(Color c, [double w = 1.1]) => OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: c, width: w),
          );
          return InputDecoration(
            labelText: label,
            hintText: hint,
            prefixText: prefixText,
            prefixIcon: icon != null
                ? Icon(icon, size: 19, color: Colors.indigo.shade600)
                : null,
            isDense: true,
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF475569),
            ),
            floatingLabelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Colors.indigo.shade700,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: b(const Color(0xFFCBD5E1)),
            enabledBorder: b(const Color(0xFFCBD5E1)),
            focusedBorder: b(Colors.indigo.shade600, 1.8),
          );
        }

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Dialog(
              backgroundColor: const Color(0xFFF8FAFC),
              surfaceTintColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 20,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.indigo.shade700,
                                  Colors.teal.shade600,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.tune_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Okul Mağazası Ayarları',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  '$_resolvedSchoolName • Vitrin, Kargo & POS Yapılandırması',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: saving ? null : () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: Colors.grey.shade200),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    value: enabled,
                                    onChanged: (v) =>
                                        setModalState(() => enabled = v),
                                    title: const Text(
                                      'Okul Mağazamız Aktif',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Kapalı olduğunda okul ürünleri vitrinde gizlenir.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                  if (_schoolTypes.isNotEmpty) ...[
                                    const Divider(height: 18),
                                    const Text(
                                      'Aktif Okul Türleri (Boş bırakılırsa tüm kademelere açık):',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: _schoolTypes.map((st) {
                                        final sel = enabledTypeIds.contains(
                                          st.id,
                                        );
                                        return FilterChip(
                                          visualDensity: VisualDensity.compact,
                                          selected: sel,
                                          label: Text(st.name),
                                          onSelected: (v) {
                                            setModalState(() {
                                              if (v) {
                                                enabledTypeIds.add(st.id);
                                              } else {
                                                enabledTypeIds.remove(st.id);
                                              }
                                            });
                                          },
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Teslimat, Kargo & Duyuru Ayarları',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    value: allowPickup,
                                    onChanged: (v) =>
                                        setModalState(() => allowPickup = v),
                                    title: const Text(
                                      'Okuldan Teslim Seçeneği',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    value: allowHome,
                                    onChanged: (v) =>
                                        setModalState(() => allowHome = v),
                                    title: const Text(
                                      'Adrese Kargo Seçeneği',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  LayoutBuilder(
                                    builder: (context, c) {
                                      final feeInput = TextField(
                                        controller: shippingCtrl,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        decoration: modalDeco(
                                          'Kargo Ücreti (₺)',
                                          icon: Icons.local_shipping_outlined,
                                          prefixText: '₺ ',
                                        ),
                                      );
                                      final freeInput = TextField(
                                        controller: freeCtrl,
                                        keyboardType: TextInputType.number,
                                        decoration: modalDeco(
                                          'Ücretsiz Kargo Limiti (₺)',
                                          icon:
                                              Icons.workspace_premium_outlined,
                                          prefixText: '₺ ',
                                        ),
                                      );
                                      if (c.maxWidth < 400) {
                                        return Column(
                                          children: [
                                            feeInput,
                                            const SizedBox(height: 10),
                                            freeInput,
                                          ],
                                        );
                                      }
                                      return Row(
                                        children: [
                                          Expanded(child: feeInput),
                                          const SizedBox(width: 10),
                                          Expanded(child: freeInput),
                                        ],
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: bannerCtrl,
                                    decoration: modalDeco(
                                      'Okul Mağazası Duyuru Bandı',
                                      hint:
                                          'Örn: Yeni dönem okul kıyafetleri stoklarımızda!',
                                      icon: Icons.campaign_outlined,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: noteCtrl,
                                    maxLines: 2,
                                    decoration: modalDeco(
                                      'Teslimat / Muhasebe Bilgi Notu',
                                      hint:
                                          'Örn: Okuldan teslim siparişler hafta içi 09:00-17:00 arası teslim edilir.',
                                      icon: Icons.notes_rounded,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50.withValues(
                                  alpha: 0.65,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.indigo.shade100,
                                ),
                              ),
                              child: Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                alignment: WrapAlignment.spaceBetween,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.point_of_sale_rounded,
                                        color: Colors.indigo.shade800,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 10),
                                      Flexible(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Sanal POS Yapılandırması (Okul / Mağaza / Kantin)',
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.indigo.shade900,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              current.usesCustomStorePos
                                                  ? 'Aktif Mağaza POS: ${current.storePosMerchantTitle.isNotEmpty ? current.storePosMerchantTitle : "Kuruma Özel POS"}'
                                                  : 'Aktif Mağaza POS: Genel Merkez Ortak POS',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: Colors.indigo.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      SchoolPosSettingsDialog.show(
                                        context,
                                        institutionId: _instUpper,
                                        institutionTitle: _resolvedSchoolName,
                                        initialTab: 1,
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.settings_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('POS Ayarları'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Divider(height: 1, color: Colors.grey.shade200),
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Vazgeç'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.indigo.shade700,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: saving
                                ? null
                                : () async {
                                    setModalState(() => saving = true);
                                    final next = SchoolStoreSettings(
                                      institutionId: _instUpper,
                                      isSchoolStoreEnabled: enabled,
                                      enabledSchoolTypeIds: enabledTypeIds
                                          .toList(),
                                      allowPickupAtSchool: allowPickup,
                                      allowHomeDelivery: allowHome,
                                      shippingFee:
                                          double.tryParse(
                                            shippingCtrl.text.replaceAll(
                                              ',',
                                              '.',
                                            ),
                                          ) ??
                                          0.0,
                                      freeShippingThreshold:
                                          double.tryParse(
                                            freeCtrl.text.replaceAll(',', '.'),
                                          ) ??
                                          500.0,
                                      announcementBanner: bannerCtrl.text
                                          .trim(),
                                      ibanOrPosNote: noteCtrl.text.trim(),
                                      usesCustomStorePos:
                                          current.usesCustomStorePos,
                                      storePosMerchantTitle:
                                          current.storePosMerchantTitle,
                                      updatedAt: DateTime.now(),
                                    );
                                    await _storeService.saveSchoolSettings(
                                      next,
                                    );
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Okul mağaza ayarları kaydedildi.',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.save_rounded, size: 18),
                            label: const Text('Kaydet'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEKME 1: OKUL ÜRÜNLERİMİZ
  // ═══════════════════════════════════════════════════════════════════════════

  InputDecoration _modernFieldDeco({
    String? label,
    String? hint,
    IconData? prefixIcon,
    Widget? suffixIcon,
  }) {
    OutlineInputBorder b(Color c, [double w = 1.1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: w),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, size: 19, color: Colors.indigo.shade600)
          : null,
      suffixIcon: suffixIcon,
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      labelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF475569),
      ),
      floatingLabelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: Colors.indigo.shade700,
      ),
      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: b(const Color(0xFFCBD5E1)),
      enabledBorder: b(const Color(0xFFCBD5E1)),
      focusedBorder: b(Colors.indigo.shade600, 1.8),
    );
  }

  Widget _buildSchoolProductsTab() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _productSearchCtrl,
                  onChanged: (v) => setState(() => _productSearch = v.trim()),
                  decoration: _modernFieldDeco(
                    hint: 'Okul ürünü ara...',
                    prefixIcon: Icons.search_rounded,
                    suffixIcon: _productSearch.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _productSearchCtrl.clear();
                              setState(() => _productSearch = '');
                            },
                          )
                        : null,
                  ),
                ),
              ),
              SizedBox(
                width: 250,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_productCategoryFilter),
                  initialValue: _productCategoryFilter,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(14),
                  decoration: _modernFieldDeco(
                    label: 'Kategori',
                    prefixIcon: Icons.category_outlined,
                  ),
                  items: ['Tümü', ...StoreCategories.all]
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(
                            c,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _productCategoryFilter = v);
                    }
                  },
                ),
              ),
              FilledButton.icon(
                onPressed: () => _openSchoolProductDialog(),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Yeni Okul Ürünü Ekle'),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<StoreProduct>>(
            stream: _schoolProductsStream,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError && !snap.hasData) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 52,
                          color: Colors.red.shade300,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Okul ürünleri yüklenirken hata oluştu.',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => setState(_bindSchoolStreams),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Yeniden Dene'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final products = snap.data ?? const <StoreProduct>[];
              final filtered = products.where((p) {
                if (_productCategoryFilter != 'Tümü' &&
                    p.category != _productCategoryFilter) {
                  return false;
                }
                if (_productSearch.isNotEmpty) {
                  final q = _productSearch.toLowerCase();
                  return p.title.toLowerCase().contains(q) ||
                      p.description.toLowerCase().contains(q);
                }
                return true;
              }).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.checkroom_rounded,
                          size: 60,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          products.isEmpty
                              ? 'Okul mağazanıza henüz ürün eklenmedi.'
                              : 'Bu filtreye uygun okul ürünü bulunamadı.',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        if (products.isEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Okul kıyafeti/forması, kırtasiye paketi, kulüp/etkinlik materyali veya kitap seti ekleyerek veli, öğrenci ve öğretmenlerinize online satışa başlayabilirsiniz.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: () => _openSchoolProductDialog(),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.teal.shade700,
                            ),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('İlk Okul Ürününü Ekle'),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, idx) => _buildSchoolProductRow(filtered[idx]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSchoolProductRow(StoreProduct p) {
    final roleSummary = p.targetRoles.map(StoreBuyerRoles.labelOf).join(', ');
    final kademeSummary = p.targetAllSchoolTypes
        ? 'Tüm Okul Türleri'
        : [
            ...p.targetSchoolTypeCategories,
            ..._schoolTypes
                .where((t) => p.targetSchoolTypeIds.contains(t.id))
                .map((t) => t.name),
          ].toSet().join(', ');
    final levelSummary = p.targetAllClassLevels || p.targetClassLevels.isEmpty
        ? null
        : p.targetClassLevels.map(StoreClassLevels.labelOf).join(', ');
    final branchSummary = p.targetAllClasses || p.targetClassNames.isEmpty
        ? null
        : 'Şube: ${p.targetClassNames.join(', ')}';
    final fullAudienceSummary = [
      kademeSummary,
      if (levelSummary != null) levelSummary,
      if (branchSummary != null) branchSummary,
      'Hedef: $roleSummary',
    ].join(' • ');

    Future<void> confirmDelete() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ürünü Sil'),
          content: Text(
            '"${p.title}" ürününü okul mağazasından silmek istediğinize emin misiniz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sil'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await _storeService.deleteProduct(p.id);
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 560;

        final fallbackIcon = Container(
          color: Colors.teal.shade50,
          child: Icon(Icons.store_rounded, color: Colors.teal.shade600),
        );
        final thumb = ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: isCompact ? 62 : 70,
            height: isCompact ? 62 : 70,
            child: StoreProductImage(
              url: p.primaryImageUrl,
              fit: BoxFit.cover,
              fallback: fallbackIcon,
            ),
          ),
        );

        final infoColumn = Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    p.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.indigo.shade900,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      p.category,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.teal.shade800,
                      ),
                    ),
                  ),
                  if (p.isMandatory)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.deepOrange.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.deepOrange.shade200),
                      ),
                      child: Text(
                        '🔒 Zorunlu Ürün (${p.mandatoryRoles.map(StoreBuyerRoles.labelOf).join(", ")})',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.deepOrange.shade900,
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      p.deliverySummaryLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                fullAudienceSummary,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  Text(
                    'Fiyat: ${_currencyFmt.format(p.effectivePrice)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    'Stok: ${p.stock} • Satılan: ${p.soldCount}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: p.isOutOfStock
                          ? Colors.red.shade700
                          : Colors.green.shade700,
                    ),
                  ),
                  if (p.variants.isNotEmpty)
                    Text(
                      'Seçenekler: ${p.variants.join(", ")}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.indigo.shade700,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );

        final actionControls = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCompact)
              Text(
                p.isActive ? 'Aktif' : 'Pasif',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: p.isActive
                      ? Colors.teal.shade700
                      : Colors.grey.shade600,
                ),
              ),
            Switch.adaptive(
              value: p.isActive,
              activeThumbColor: Colors.teal.shade700,
              onChanged: (val) => _storeService.toggleProductActive(p.id, val),
            ),
            IconButton(
              tooltip: 'Düzenle',
              onPressed: () => _openSchoolProductDialog(existing: p),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Sil',
              onPressed: confirmDelete,
              icon: Icon(
                Icons.delete_outline_rounded,
                color: Colors.red.shade700,
              ),
            ),
          ],
        );

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [thumb, const SizedBox(width: 12), infoColumn],
                    ),
                    const Divider(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: actionControls,
                    ),
                  ],
                )
              : Row(
                  children: [
                    thumb,
                    const SizedBox(width: 14),
                    infoColumn,
                    actionControls,
                  ],
                ),
        );
      },
    );
  }

  Future<void> _openSchoolProductDialog({StoreProduct? existing}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StoreProductDialog(
        existing: existing,
        title: existing == null ? 'Yeni Ürün Ekle' : 'Ürünü Düzenle',
        subtitle: _resolvedSchoolName.isNotEmpty
            ? '$_resolvedSchoolName Mağazası'
            : 'Okul Mağazası',
        defaultCategory: StoreCategories.uniform,
        defaultStock: 50,
        availableClasses: _schoolClasses,
        variantPresets: const [
          MapEntry('+ Yaş/Beden: 7-8 / 9-10 / 11-12 / S / M / L', [
            '7-8 Yaş',
            '9-10 Yaş',
            '11-12 Yaş',
            'S',
            'M',
            'L',
          ]),
        ],
        uploadImage: (bytes, fileName) => _storeService.uploadProductImage(
          sellerInstitutionId: _instUpper,
          bytes: bytes,
          fileName: fileName,
        ),
        targetingBuilder: (context, data, refresh) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: data.targetAllSchoolTypes,
              onChanged: (v) {
                data.targetAllSchoolTypes = v;
                refresh();
              },
              title: const Text(
                'Okulumuzdaki Tüm Okul Türlerine (Kademelere) Göster',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                data.targetAllSchoolTypes
                    ? 'Kapattığınızda ürünü yalnızca belirli okul türlerine (örn. Ortaokul veya Lise) açabilirsiniz.'
                    : 'Yalnızca aşağıda seçtiğiniz okul türlerindeki (kademelerdeki) kullanıcılar bu ürünü görür.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
            if (!data.targetAllSchoolTypes) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _schoolTypes.isNotEmpty
                    ? _schoolTypes.map((st) {
                        final sel = data.targetSchoolTypeIds.contains(st.id);
                        return FilterChip(
                          visualDensity: VisualDensity.compact,
                          selected: sel,
                          label: Text('${st.name} (${st.category})'),
                          onSelected: (v) {
                            if (v) {
                              data.targetSchoolTypeIds.add(st.id);
                            } else {
                              data.targetSchoolTypeIds.remove(st.id);
                            }
                            data.targetCategories
                              ..clear()
                              ..addAll(
                                _schoolTypes
                                    .where(
                                      (t) => data.targetSchoolTypeIds.contains(
                                        t.id,
                                      ),
                                    )
                                    .map((t) => t.category)
                                    .where((c) => c.isNotEmpty),
                              );
                            refresh();
                          },
                        );
                      }).toList()
                    : StoreSchoolTypeCategories.all.map((cat) {
                        final sel = data.targetCategories.contains(cat);
                        return FilterChip(
                          visualDensity: VisualDensity.compact,
                          selected: sel,
                          label: Text(cat),
                          onSelected: (v) {
                            if (v) {
                              data.targetCategories.add(cat);
                            } else {
                              data.targetCategories.remove(cat);
                            }
                            refresh();
                          },
                        );
                      }).toList(),
              ),
            ],
          ],
        ),
        onSave: (d) {
          final sellerName = _resolvedSchoolName.isNotEmpty
              ? '$_resolvedSchoolName Mağazası'
              : 'Okul Mağazası';
          return _storeService.saveProduct(
            StoreProduct(
              id: existing?.id ?? '',
              sellerType: 'school',
              sellerInstitutionId: _instUpper,
              sellerName: sellerName,
              title: d.title,
              description: d.description,
              category: d.category,
              price: d.price,
              discountedPrice: d.discountedPrice,
              vatRate: d.vatRate,
              stock: d.stock,
              soldCount: existing?.soldCount ?? 0,
              variants: d.variants,
              imageUrls: d.imageUrls,
              isActive: d.isActive,
              targetAllSchools: false,
              targetSchoolIds: [_instUpper],
              targetAllSchoolTypes: d.targetAllSchoolTypes,
              targetSchoolTypeIds: d.targetSchoolTypeIds.toList(),
              targetSchoolTypeCategories: d.targetCategories.toList(),
              targetAllClassLevels: d.targetAllClassLevels,
              targetClassLevels: d.targetClassLevels.toList(),
              targetAllClasses: d.targetAllClasses,
              targetClassIds: d.targetClassIds.toList(),
              targetClassNames: d.targetClassNames.toList(),
              targetRoles: d.targetRoles.toList(),
              allowPickupAtSchool: d.allowPickupAtSchool,
              allowHomeDelivery: d.allowHomeDelivery,
              isMandatory: d.isMandatory,
              mandatoryRoles: d.mandatoryRoles.toList(),
              createdAt: existing?.createdAt ?? DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEKME 2: OKUL SİPARİŞLERİ
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSchoolOrdersTab() {
    return StreamBuilder<List<StoreOrder>>(
      stream: _schoolOrdersStream,
      builder: (context, snap) {
        final isWaitingInitial =
            snap.connectionState == ConnectionState.waiting && !snap.hasData;
        final orders = snap.data ?? const <StoreOrder>[];
        final validRevenue = orders
            .where((o) => o.orderStatus != StoreOrderStatuses.iptal)
            .fold<double>(0.0, (a, b) => a + b.totalAmount);
        final pendingCount = orders
            .where((o) => o.orderStatus == StoreOrderStatuses.bekliyor)
            .length;
        final activeCount = orders
            .where(
              (o) =>
                  o.orderStatus == StoreOrderStatuses.onaylandi ||
                  o.orderStatus == StoreOrderStatuses.hazirlaniyor ||
                  o.orderStatus == StoreOrderStatuses.kargoda,
            )
            .length;
        final deliveredCount = orders
            .where((o) => o.orderStatus == StoreOrderStatuses.teslimEdildi)
            .length;

        final filtered = orders.where((o) {
          if (_orderStatusFilter != 'Tümü' &&
              o.orderStatus != _orderStatusFilter) {
            return false;
          }
          if (_orderRoleFilter != 'Tümü' &&
              StoreBuyerRoles.normalize(o.buyerRole) != _orderRoleFilter) {
            return false;
          }
          if (_orderSearch.isNotEmpty) {
            final q = _orderSearch.toLowerCase();
            return o.orderNo.toLowerCase().contains(q) ||
                o.buyerName.toLowerCase().contains(q) ||
                (o.studentName ?? '').toLowerCase().contains(q);
          }
          return true;
        }).toList();

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _kpiBox(
                          title: 'Okul Mağazası Cirosu',
                          value: _currencyFmt.format(validRevenue),
                          icon: Icons.account_balance_wallet_rounded,
                          color: Colors.teal.shade700,
                        ),
                        _kpiBox(
                          title: 'Bekleyen Sipariş',
                          value: '$pendingCount',
                          icon: Icons.pending_actions_rounded,
                          color: Colors.amber.shade800,
                        ),
                        _kpiBox(
                          title: 'Hazırlanan / Kargoda',
                          value: '$activeCount',
                          icon: Icons.inventory_rounded,
                          color: Colors.blue.shade700,
                        ),
                        _kpiBox(
                          title: 'Teslim Edilen',
                          value: '$deliveredCount',
                          icon: Icons.check_circle_outline_rounded,
                          color: Colors.green.shade700,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 260,
                            child: TextField(
                              controller: _orderSearchCtrl,
                              onChanged: (v) =>
                                  setState(() => _orderSearch = v.trim()),
                              decoration: _modernFieldDeco(
                                hint: 'Sipariş No, Veli veya Öğrenci ara...',
                                prefixIcon: Icons.search_rounded,
                                suffixIcon: _orderSearch.isEmpty
                                    ? null
                                    : IconButton(
                                        icon: const Icon(
                                          Icons.clear_rounded,
                                          size: 18,
                                        ),
                                        onPressed: () {
                                          _orderSearchCtrl.clear();
                                          setState(() => _orderSearch = '');
                                        },
                                      ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: DropdownButtonFormField<String>(
                              key: ValueKey(
                                'school_ord_status_$_orderStatusFilter',
                              ),
                              initialValue: _orderStatusFilter,
                              isExpanded: true,
                              borderRadius: BorderRadius.circular(14),
                              decoration: _modernFieldDeco(
                                label: 'Sipariş Durumu',
                                prefixIcon: Icons.local_shipping_outlined,
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: 'Tümü',
                                  child: Text(
                                    'Tüm Durumlar',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                ...StoreOrderStatuses.all.map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(
                                      StoreOrderStatuses.labelOf(s),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _orderStatusFilter = v);
                                }
                              },
                            ),
                          ),
                          SizedBox(
                            width: 200,
                            child: DropdownButtonFormField<String>(
                              key: ValueKey(
                                'school_ord_role_$_orderRoleFilter',
                              ),
                              initialValue: _orderRoleFilter,
                              isExpanded: true,
                              borderRadius: BorderRadius.circular(14),
                              decoration: _modernFieldDeco(
                                label: 'Alıcı Rolü',
                                prefixIcon: Icons.person_outline_rounded,
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: 'Tümü',
                                  child: Text(
                                    'Tüm Roller',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                ...StoreBuyerRoles.all.map(
                                  (r) => DropdownMenuItem(
                                    value: r,
                                    child: Text(
                                      StoreBuyerRoles.labelOf(r),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _orderRoleFilter = v);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isWaitingInitial)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (snap.hasError && !snap.hasData)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: Colors.red.shade700,
                          size: 36,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Siparişler yüklenirken bir hata oluştu.',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.red.shade900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => setState(_bindSchoolStreams),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Yeniden Dene'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (filtered.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.all(36),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        'Okul mağazasına ait sipariş bulunamadı.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) =>
                      _buildSchoolOrderCard(filtered[index]),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _kpiBox({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 230,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.indigo.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSchoolOrderCard(StoreOrder o) {
    final fmt = DateFormat('dd.MM.yyyy HH:mm');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                o.orderNo,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: Colors.indigo.shade900,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  StoreOrderStatuses.labelOf(o.orderStatus),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.teal.shade900,
                  ),
                ),
              ),
              Text(
                fmt.format(o.createdAt),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Alıcı: ${o.buyerName} (${StoreBuyerRoles.labelOf(o.buyerRole)}) • Tel: ${o.buyerPhone}${o.studentName?.isNotEmpty == true ? ' • Öğrenci: ${o.studentName} ${o.studentClass ?? ''}' : ''}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Teslimat: ${o.deliveryType} — ${o.deliveryAddress}',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
          ),
          if (o.orderNote.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Sipariş Notu: ${o.orderNote}',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.deepOrange.shade800,
                ),
              ),
            ),
          const Divider(height: 18),
          ...o.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.quantity}x ${item.title}${item.selectedVariant != null ? ' (${item.selectedVariant})' : ''}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Text(
                    _currencyFmt.format(item.lineTotal),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Tutar: ${_currencyFmt.format(o.totalAmount)} (${o.cardMasked} • ${o.paymentRef})',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.indigo.shade900,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _storeService.updateOrderStatusBySeller(
                  orderId: o.id,
                  newStatus: StoreOrderStatuses.onaylandi,
                ),
                child: const Text('Onayla'),
              ),
              OutlinedButton(
                onPressed: () => _storeService.updateOrderStatusBySeller(
                  orderId: o.id,
                  newStatus: StoreOrderStatuses.hazirlaniyor,
                ),
                child: const Text('Hazırlanıyor'),
              ),
              OutlinedButton.icon(
                onPressed: () => _promptTrackingDialog(o),
                icon: const Icon(Icons.local_shipping_outlined, size: 16),
                label: const Text('Kargoya Ver'),
              ),
              FilledButton.tonal(
                onPressed: () => _storeService.updateOrderStatusBySeller(
                  orderId: o.id,
                  newStatus: StoreOrderStatuses.teslimEdildi,
                ),
                child: const Text('Teslim Edildi'),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                ),
                onPressed: () => _storeService.updateOrderStatusBySeller(
                  orderId: o.id,
                  newStatus: StoreOrderStatuses.iptal,
                  cancelReason: 'Okul yönetimi tarafından iptal edildi',
                ),
                child: const Text('İptal'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _promptTrackingDialog(StoreOrder order) async {
    final ctrl = TextEditingController(text: order.trackingCode);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              Icons.local_shipping_outlined,
              color: Colors.indigo.shade700,
              size: 22,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Kargo Takip Kodu Gir',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: TextField(
            controller: ctrl,
            decoration: _modernFieldDeco(
              label: 'Kargo Firması / Takip Kodu',
              hint: 'Örn: Yurtiçi Kargo - 90248122',
              prefixIcon: Icons.qr_code_rounded,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.indigo.shade700,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _storeService.updateOrderStatusBySeller(
        orderId: order.id,
        newStatus: StoreOrderStatuses.kargoda,
        trackingCode: ctrl.text,
      );
    }
  }
}
