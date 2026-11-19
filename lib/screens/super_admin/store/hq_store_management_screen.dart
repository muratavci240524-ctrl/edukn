import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/store/store_models.dart';
import '../../../services/store_service.dart';
import '../../../widgets/edukn_app_bar.dart';
import '../../../widgets/school_pos_settings_dialog.dart';
import '../../../widgets/store_product_dialog.dart';

/// Süper Admin — Genel Merkez Mağaza Yönetim Konsolu:
/// 1) Mağaza Yetkilendirme (Okul & Okul Türü bazında açma/kapama + Kargo & POS ayarları)
/// 2) Genel Merkez Ürünleri (Görsel yükleme, varyant, okul/kademe/rol hedefleme)
/// 3) Genel Merkez Siparişleri & Ciro Analitiği
class HqStoreManagementScreen extends StatefulWidget {
  final bool showAppBar;
  const HqStoreManagementScreen({super.key, this.showAppBar = false});

  @override
  State<HqStoreManagementScreen> createState() =>
      _HqStoreManagementScreenState();
}

class _HqStoreManagementScreenState extends State<HqStoreManagementScreen>
    with SingleTickerProviderStateMixin {
  final StoreService _storeService = StoreService();
  final NumberFormat _currencyFmt = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: '₺',
    decimalDigits: 2,
  );

  late final TabController _tabController;

  // Okul + Okul Türü rehberi
  bool _loadingSchools = true;
  List<StoreSchoolDirectoryItem> _schools = const [];
  List<StoreClassOption> _allClasses = const [];

  // Sekme 1: Yetkilendirme düzenleme state'i
  bool _settingsInitialized = false;
  bool _savingSettings = false;
  bool _isStoreOpenGlobally = true;
  final Set<String> _enabledSchoolIds = {};
  final Map<String, Set<String>> _enabledSchoolTypeMap = {};
  String _posMode = 'sandbox_3d';
  bool _allowPickup = true;
  bool _allowHomeDelivery = true;
  final TextEditingController _shippingFeeCtrl = TextEditingController(
    text: '59.90',
  );
  final TextEditingController _freeShippingCtrl = TextEditingController(
    text: '750',
  );
  final TextEditingController _bannerCtrl = TextEditingController();
  final TextEditingController _schoolAccessSearchCtrl = TextEditingController();
  final TextEditingController _productSearchCtrl = TextEditingController();
  final TextEditingController _orderSearchCtrl = TextEditingController();
  String _schoolAccessSearch = '';

  // Sekme 2: Ürün filtreleri
  String _productCategoryFilter = 'Tümü';
  String _productSearch = '';

  // Sekme 3: Sipariş filtreleri
  String _orderStatusFilter = 'Tümü';
  String _orderRoleFilter = 'Tümü';
  String _orderSchoolFilter = 'Tümü';
  String _orderSearch = '';

  late Stream<List<StoreProduct>> _hqProductsStream;
  late Stream<List<StoreOrder>> _hqOrdersStream;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _hqProductsStream = _storeService.watchHqProducts();
    _hqOrdersStream = _storeService.watchHqOrders();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _loadingSchools = true);
    try {
      final results = await Future.wait([
        _storeService.loadAllSchoolsWithTypes(),
        _storeService.getHqSettings(),
        _storeService.loadAllActiveClasses(),
      ]);
      final schools = results[0] as List<StoreSchoolDirectoryItem>;
      final settings = results[1] as HqStoreSchoolAccess;
      final classes = results[2] as List<StoreClassOption>;
      if (!mounted) return;
      _applySettingsToForm(settings);
      setState(() {
        _schools = schools;
        _allClasses = classes;
        _loadingSchools = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSchools = false);
    }
  }

  void _applySettingsToForm(HqStoreSchoolAccess settings) {
    _isStoreOpenGlobally = settings.isStoreOpenGlobally;
    _enabledSchoolIds
      ..clear()
      ..addAll(settings.enabledSchoolIds);
    _enabledSchoolTypeMap.clear();
    settings.enabledSchoolTypeMap.forEach((k, v) {
      _enabledSchoolTypeMap[k] = v.toSet();
    });
    _posMode = settings.posMode;
    _allowPickup = settings.allowPickupAtSchool;
    _allowHomeDelivery = settings.allowHomeDelivery;
    _shippingFeeCtrl.text = settings.shippingFee.toStringAsFixed(2);
    _freeShippingCtrl.text = settings.freeShippingThreshold.toStringAsFixed(0);
    _bannerCtrl.text = settings.announcementBanner;
    _settingsInitialized = true;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _shippingFeeCtrl.dispose();
    _freeShippingCtrl.dispose();
    _bannerCtrl.dispose();
    _schoolAccessSearchCtrl.dispose();
    _productSearchCtrl.dispose();
    _orderSearchCtrl.dispose();
    super.dispose();
  }

  bool _isSchoolEnabled(StoreSchoolDirectoryItem school) {
    return _enabledSchoolIds.contains(school.schoolId) ||
        _enabledSchoolIds.contains(school.institutionId);
  }

  Set<String> _enabledTypesForSchool(StoreSchoolDirectoryItem school) {
    return _enabledSchoolTypeMap[school.schoolId] ??
        _enabledSchoolTypeMap[school.institutionId] ??
        <String>{};
  }

  void _toggleSchoolAccess(StoreSchoolDirectoryItem school, bool enable) {
    setState(() {
      if (enable) {
        _enabledSchoolIds.add(school.schoolId);
        _enabledSchoolIds.add(school.institutionId);
        final allTypeIds = school.schoolTypes.isNotEmpty
            ? school.schoolTypes.map((e) => e.id).toSet()
            : <String>{'ALL'};
        _enabledSchoolTypeMap[school.schoolId] = Set<String>.from(allTypeIds);
        _enabledSchoolTypeMap[school.institutionId] = Set<String>.from(
          allTypeIds,
        );
      } else {
        _enabledSchoolIds.remove(school.schoolId);
        _enabledSchoolIds.remove(school.institutionId);
        _enabledSchoolTypeMap.remove(school.schoolId);
        _enabledSchoolTypeMap.remove(school.institutionId);
      }
    });
  }

  void _toggleSchoolTypeAccess(
    StoreSchoolDirectoryItem school,
    String typeId,
    bool enable,
  ) {
    setState(() {
      final current = Set<String>.from(_enabledTypesForSchool(school));
      if (current.contains('ALL')) {
        current
          ..remove('ALL')
          ..addAll(school.schoolTypes.map((t) => t.id));
      }
      if (enable) {
        current.add(typeId);
        _enabledSchoolIds.add(school.schoolId);
        _enabledSchoolIds.add(school.institutionId);
      } else {
        current.remove(typeId);
        if (current.isEmpty) {
          _enabledSchoolIds.remove(school.schoolId);
          _enabledSchoolIds.remove(school.institutionId);
        }
      }
      _enabledSchoolTypeMap[school.schoolId] = Set<String>.from(current);
      _enabledSchoolTypeMap[school.institutionId] = Set<String>.from(current);
    });
  }

  Future<void> _saveAccessSettings() async {
    setState(() => _savingSettings = true);
    try {
      final shipping =
          double.tryParse(_shippingFeeCtrl.text.replaceAll(',', '.')) ?? 59.90;
      final threshold =
          double.tryParse(_freeShippingCtrl.text.replaceAll(',', '.')) ?? 750.0;

      final serializedMap = <String, List<String>>{};
      _enabledSchoolTypeMap.forEach((k, v) {
        if (v.isNotEmpty) {
          serializedMap[k] = v.toList();
        }
      });

      final updated = HqStoreSchoolAccess(
        isStoreOpenGlobally: _isStoreOpenGlobally,
        enabledSchoolIds: _enabledSchoolIds.toList(),
        enabledSchoolTypeMap: serializedMap,
        shippingFee: shipping,
        freeShippingThreshold: threshold,
        posMode: _posMode,
        announcementBanner: _bannerCtrl.text.trim(),
        allowPickupAtSchool: _allowPickup,
        allowHomeDelivery: _allowHomeDelivery,
        updatedAt: DateTime.now(),
      );

      await _storeService.saveHqSettings(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Genel Merkez mağaza yetkilendirme ve kargo ayarları kaydedildi.',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ayarlar kaydedilirken hata oluştu: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabBar = TabBar(
      controller: _tabController,
      isScrollable: MediaQuery.of(context).size.width < 820,
      labelColor: Colors.indigo.shade900,
      unselectedLabelColor: Colors.grey.shade600,
      indicatorColor: Colors.indigo.shade700,
      labelStyle: const TextStyle(fontWeight: FontWeight.w800),
      tabs: const [
        Tab(
          icon: Icon(Icons.admin_panel_settings_outlined, size: 20),
          text: 'Mağaza Yetkilendirme (Okul & Tür)',
        ),
        Tab(
          icon: Icon(Icons.inventory_2_outlined, size: 20),
          text: 'Genel Merkez Ürünleri',
        ),
        Tab(
          icon: Icon(Icons.point_of_sale_rounded, size: 20),
          text: 'Siparişler & Ciro',
        ),
      ],
    );

    final bodyContent = Column(
      children: [
        if (!widget.showAppBar)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.storefront_rounded,
                        color: Colors.deepPurple.shade700,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Genel Merkez Mağaza & E-Ticaret Yönetimi',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Colors.indigo.shade900,
                            ),
                          ),
                          Text(
                            'Okul / okul türü bazlı erişim yetkisi, merkezi ürün kataloğu ve online kart sipariş yönetimi',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _loadInitialData,
                      tooltip: 'Okul Listesini Yenile',
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                tabBar,
              ],
            ),
          ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildAccessControlTab(),
              _buildHqProductsTab(),
              _buildHqOrdersTab(),
            ],
          ),
        ),
      ],
    );

    if (widget.showAppBar) {
      return Scaffold(
        backgroundColor: const Color(0xFFF6F8FC),
        appBar: EduknAppBar(
          title: 'Genel Merkez Mağaza Yönetimi',
          subtitle: 'Merkezi Ürünler, Okul Yetkilendirme & Siparişler',
          actions: [
            IconButton(
              onPressed: _loadInitialData,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Yenile',
            ),
          ],
          bottom: tabBar,
        ),
        body: bodyContent,
      );
    }

    return Material(color: const Color(0xFFF6F8FC), child: bodyContent);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEKME 1: MAĞAZA YETKİLENDİRME (OKUL VE OKUL TÜRÜ AÇ / KAPA)
  // ═══════════════════════════════════════════════════════════════════════════

  InputDecoration _modernFieldDeco({
    String? label,
    String? hint,
    IconData? prefixIcon,
    String? prefixText,
    Widget? suffixIcon,
  }) {
    OutlineInputBorder b(Color c, [double w = 1.1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: w),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefixText,
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

  Widget _buildAccessControlTab() {
    if (_loadingSchools && !_settingsInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final filteredSchools = _schools.where((s) {
      if (_schoolAccessSearch.isEmpty) return true;
      final q = _schoolAccessSearch.toLowerCase();
      return s.schoolName.toLowerCase().contains(q) ||
          s.institutionId.toLowerCase().contains(q) ||
          s.city.toLowerCase().contains(q);
    }).toList();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Genel Erişim ve Kargo Ayar Kartı
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              value: _isStoreOpenGlobally,
                              activeThumbColor: Colors.green.shade700,
                              onChanged: (val) =>
                                  setState(() => _isStoreOpenGlobally = val),
                              title: Text(
                                _isStoreOpenGlobally
                                    ? 'Tüm Okul ve Okul Türlerine Açık (Global Erişim)'
                                    : 'Seçili Okul ve Okul Türlerine Açık (Özel Yetkilendirme)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.indigo.shade900,
                                ),
                              ),
                              subtitle: Text(
                                _isStoreOpenGlobally
                                    ? 'Aktif olduğunda tüm okullar ve kademeler Genel Merkez vitrinini görebilir.'
                                    : 'Kapalı olduğunda yalnızca aşağıda işaretlediğiniz okul ve okul türleri (Anaokulu / İlkokul / Ortaokul / Lise) mağazayı görebilir.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 205,
                            child: TextField(
                              controller: _shippingFeeCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: _modernFieldDeco(
                                label: 'Sabit Kargo Ücreti (₺)',
                                prefixIcon: Icons.local_shipping_outlined,
                                prefixText: '₺ ',
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 235,
                            child: TextField(
                              controller: _freeShippingCtrl,
                              keyboardType: TextInputType.number,
                              decoration: _modernFieldDeco(
                                label: 'Ücretsiz Kargo Alt Limiti (₺)',
                                prefixIcon: Icons.workspace_premium_outlined,
                                prefixText: '₺ ',
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 245,
                            child: DropdownButtonFormField<String>(
                              key: ValueKey(_posMode),
                              initialValue: _posMode,
                              isExpanded: true,
                              borderRadius: BorderRadius.circular(14),
                              decoration: _modernFieldDeco(
                                label: 'Sanal POS Altyapısı',
                                prefixIcon: Icons.credit_card_rounded,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'sandbox_3d',
                                  child: Text(
                                    '3D Secure Ortak POS',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'iyzico',
                                  child: Text(
                                    'iyzico Korumalı POS',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'paytr',
                                  child: Text(
                                    'PayTR Sanal POS',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => _posMode = v);
                              },
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => SchoolPosSettingsDialog.show(
                              context,
                              institutionId: 'SUPER_ADMIN',
                              institutionTitle: 'Genel Merkez',
                              isHq: true,
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(
                              Icons.point_of_sale_rounded,
                              size: 18,
                            ),
                            label: const Text('Genel Merkez POS Anahtarları'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            selected: _allowPickup,
                            onSelected: (v) => setState(() => _allowPickup = v),
                            label: const Text('Okuldan Teslim Seçeneği Açık'),
                          ),
                          FilterChip(
                            selected: _allowHomeDelivery,
                            onSelected: (v) =>
                                setState(() => _allowHomeDelivery = v),
                            label: const Text('Adrese Kargo Seçeneği Açık'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _bannerCtrl,
                        decoration: _modernFieldDeco(
                          label:
                              'Mağaza Üst Duyuru Bandı (Örn: Yeni dönem kitap setlerinde %15 erken kayıt indirimi!)',
                          prefixIcon: Icons.campaign_outlined,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _savingSettings
                              ? null
                              : _saveAccessSettings,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.indigo.shade700,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 13,
                            ),
                          ),
                          icon: _savingSettings
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_rounded),
                          label: const Text('Yetkilendirme & Ayarları Kaydet'),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Okul ve Okul Türü Bazlı Yetkilendirme Matrisi Başlık & Filtre Kartı
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Okul ve Okul Türü (Kademe) Erişim Matrisi (${_schools.length} Okul)',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.indigo.shade900,
                                  ),
                                ),
                                Text(
                                  'Bir okulun tamamını veya yalnızca belirli kademelerini (örn. sadece Ortaokul açıp Lise kapatma) seçebilirsiniz.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_isStoreOpenGlobally)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.green.shade200,
                                ),
                              ),
                              child: Text(
                                'Şu an Global Açık',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.green.shade800,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _isStoreOpenGlobally = false;
                                for (final s in _schools) {
                                  _toggleSchoolAccess(s, true);
                                }
                              });
                            },
                            icon: const Icon(
                              Icons.select_all_rounded,
                              size: 17,
                            ),
                            label: const Text('Tüm Okulları Seç'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _isStoreOpenGlobally = false;
                                _enabledSchoolIds.clear();
                                _enabledSchoolTypeMap.clear();
                              });
                            },
                            icon: const Icon(Icons.deselect_rounded, size: 17),
                            label: const Text('Seçimleri Temizle'),
                          ),
                          ...StoreSchoolTypeCategories.all.map(
                            (cat) => ActionChip(
                              avatar: const Icon(
                                Icons.filter_alt_outlined,
                                size: 16,
                              ),
                              label: Text('Sadece $cat Aç'),
                              onPressed: () {
                                setState(() {
                                  _isStoreOpenGlobally = false;
                                  _enabledSchoolIds.clear();
                                  _enabledSchoolTypeMap.clear();
                                  for (final s in _schools) {
                                    final matchingIds = s.schoolTypes
                                        .where((t) => t.category == cat)
                                        .map((t) => t.id)
                                        .toSet();
                                    if (matchingIds.isNotEmpty) {
                                      _enabledSchoolIds.add(s.schoolId);
                                      _enabledSchoolIds.add(s.institutionId);
                                      _enabledSchoolTypeMap[s.schoolId] =
                                          Set<String>.from(matchingIds);
                                      _enabledSchoolTypeMap[s.institutionId] =
                                          Set<String>.from(matchingIds);
                                    }
                                  }
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _schoolAccessSearchCtrl,
                        onChanged: (val) =>
                            setState(() => _schoolAccessSearch = val.trim()),
                        decoration: _modernFieldDeco(
                          hint:
                              'Okul adı, kurum kodu veya şehir ile filtrele...',
                          prefixIcon: Icons.search_rounded,
                          suffixIcon: _schoolAccessSearch.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear_rounded,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    _schoolAccessSearchCtrl.clear();
                                    setState(() => _schoolAccessSearch = '');
                                  },
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        if (filteredSchools.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            sliver: SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Center(
                  child: Text(
                    'Eşleşen okul kaydı bulunamadı.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            sliver: SliverList.builder(
              itemCount: filteredSchools.length,
              itemBuilder: (context, index) =>
                  _buildSchoolAccessRow(filteredSchools[index]),
            ),
          ),
      ],
    );
  }

  Widget _buildSchoolAccessRow(StoreSchoolDirectoryItem school) {
    final schoolEnabled = _isStoreOpenGlobally || _isSchoolEnabled(school);
    final enabledTypes = _enabledTypesForSchool(school);
    final allTypesImplicit = enabledTypes.contains('ALL');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: schoolEnabled
            ? Colors.indigo.shade50.withValues(alpha: 0.5)
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: schoolEnabled ? Colors.indigo.shade200 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: schoolEnabled,
                onChanged: (val) {
                  if (_isStoreOpenGlobally) {
                    _isStoreOpenGlobally = false;
                  }
                  _toggleSchoolAccess(school, val ?? false);
                },
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      school.schoolName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    Text(
                      'Kurum Kodu: ${school.institutionId}${school.city.isNotEmpty ? ' • ${school.city}' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                school.schoolTypes.isEmpty
                    ? 'Okul türü tanımlı değil'
                    : '${school.schoolTypes.length} Okul Türü',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.indigo.shade700,
                ),
              ),
            ],
          ),
          if (school.schoolTypes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: school.schoolTypes.map((st) {
                  final isTypeSelected =
                      _isStoreOpenGlobally ||
                      (schoolEnabled &&
                          (allTypesImplicit ||
                              enabledTypes.isEmpty ||
                              enabledTypes.contains(st.id)));
                  return FilterChip(
                    selected: isTypeSelected,
                    selectedColor: Colors.indigo.shade100,
                    label: Text('${st.name} (${st.category})'),
                    onSelected: (val) {
                      if (_isStoreOpenGlobally) {
                        // Global moddan çıkarken mevcut okulları koruyup sadece bu okul türünü değiştir
                        for (final s in _schools) {
                          _toggleSchoolAccess(s, true);
                        }
                        _isStoreOpenGlobally = false;
                      }
                      _toggleSchoolTypeAccess(school, st.id, val);
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEKME 2: GENEL MERKEZ ÜRÜNLERİ
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHqProductsTab() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _productSearchCtrl,
                  onChanged: (v) => setState(() => _productSearch = v.trim()),
                  decoration: _modernFieldDeco(
                    hint: 'Genel Merkez ürünü ara...',
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
                onPressed: () => _openHqProductDialog(),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.deepPurple.shade700,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Yeni Genel Merkez Ürünü Ekle'),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<StoreProduct>>(
            stream: _hqProductsStream,
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
                          'Ürünler yüklenirken hata oluştu.',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => setState(() {
                            _hqProductsStream = _storeService.watchHqProducts();
                          }),
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
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 60,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          products.isEmpty
                              ? 'Henüz Genel Merkez ürünü eklenmemiş.'
                              : 'Arama / kategori filtresine uygun ürün bulunamadı.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        if (products.isEmpty) ...[
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: () => _openHqProductDialog(),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('İlk Ürünü Ekle'),
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
                itemBuilder: (_, idx) => _buildHqProductRow(filtered[idx]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHqProductRow(StoreProduct p) {
    final targetSummary = [
      p.targetAllSchools ? 'Tüm Okullar' : '${p.targetSchoolIds.length} Okul',
      p.targetAllSchoolTypes
          ? 'Tüm Kademeler'
          : [
              ...p.targetSchoolTypeCategories,
              if (p.targetSchoolTypeIds.isNotEmpty)
                '${p.targetSchoolTypeIds.length} Özel Tür',
            ].join(', '),
      if (!p.targetAllClassLevels && p.targetClassLevels.isNotEmpty)
        p.targetClassLevels.map(StoreClassLevels.labelOf).join(', '),
      if (!p.targetAllClasses &&
          (p.targetClassNames.isNotEmpty || p.targetClassIds.isNotEmpty))
        p.targetClassNames.isNotEmpty
            ? 'Şube: ${p.targetClassNames.join(", ")}'
            : '${p.targetClassIds.length} Şube',
      p.targetRoles.map(StoreBuyerRoles.labelOf).join('/'),
    ].join(' • ');

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 560;

        final fallbackThumb = Container(
          color: Colors.deepPurple.shade50,
          child: Icon(
            Icons.inventory_2_rounded,
            color: Colors.deepPurple.shade400,
          ),
        );

        final thumb = ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: isCompact ? 62 : 72,
            height: isCompact ? 62 : 72,
            child: p.primaryImageUrl != null && p.primaryImageUrl!.isNotEmpty
                ? StoreProductImage(
                    url: p.primaryImageUrl!,
                    fit: BoxFit.cover,
                    fallback: fallbackThumb,
                  )
                : fallbackThumb,
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
                      color: Colors.deepPurple.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      p.category,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.deepPurple.shade800,
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
                targetSummary,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  Text(
                    'Fiyat: ${_currencyFmt.format(p.effectivePrice)}${p.hasDiscount ? ' (Liste: ${_currencyFmt.format(p.price)})' : ''}',
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
                      'Varyant: ${p.variants.join(", ")}',
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
                      ? Colors.green.shade700
                      : Colors.grey.shade600,
                ),
              ),
            Switch.adaptive(
              value: p.isActive,
              activeThumbColor: Colors.green.shade700,
              onChanged: (val) => _storeService.toggleProductActive(p.id, val),
            ),
            IconButton(
              tooltip: 'Düzenle',
              onPressed: () => _openHqProductDialog(existing: p),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Sil',
              onPressed: () => _confirmDeleteProduct(p),
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

  Future<void> _confirmDeleteProduct(StoreProduct p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ürünü Sil'),
        content: Text('"${p.title}" ürününü silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
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

  Future<void> _openHqProductDialog({StoreProduct? existing}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StoreProductDialog(
        existing: existing,
        title: existing == null ? 'Yeni Ürün Ekle' : 'Ürünü Düzenle',
        subtitle: 'Genel Merkez Mağazası',
        defaultCategory: StoreCategories.booksAndSets,
        defaultStock: 100,
        availableClasses: _allClasses,
        variantPresets: const [
          MapEntry('+ Beden: S/M/L/XL', ['S', 'M', 'L', 'XL']),
          MapEntry('+ Ortaokul: 5-8. Sınıf', [
            '5. Sınıf',
            '6. Sınıf',
            '7. Sınıf',
            '8. Sınıf',
          ]),
          MapEntry('+ Lise: 9-12. Sınıf', [
            '9. Sınıf',
            '10. Sınıf',
            '11. Sınıf',
            '12. Sınıf',
          ]),
        ],
        uploadImage: (bytes, fileName) => _storeService.uploadProductImage(
          sellerInstitutionId: StoreService.hqDocId,
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
                'Tüm Okul Türlerine (Kademelere) Göster',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (!data.targetAllSchoolTypes)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: StoreSchoolTypeCategories.all.map((cat) {
                  final sel = data.targetCategories.contains(cat);
                  return FilterChip(
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
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: data.targetAllSchools,
              onChanged: (v) {
                data.targetAllSchools = v;
                refresh();
              },
              title: const Text(
                'Mağazası Açık Tüm Okullara Göster',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (!data.targetAllSchools)
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: _schools.map((s) {
                    final checked =
                        data.targetSchoolIds.contains(s.schoolId) ||
                        data.targetSchoolIds.contains(s.institutionId);
                    return CheckboxListTile(
                      dense: true,
                      value: checked,
                      title: Text('${s.schoolName} (${s.institutionId})'),
                      onChanged: (v) {
                        if (v == true) {
                          data.targetSchoolIds.add(s.schoolId);
                          data.targetSchoolIds.add(s.institutionId);
                        } else {
                          data.targetSchoolIds.remove(s.schoolId);
                          data.targetSchoolIds.remove(s.institutionId);
                        }
                        refresh();
                      },
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
        onSave: (d) => _storeService.saveProduct(
          StoreProduct(
            id: existing?.id ?? '',
            sellerType: 'hq',
            sellerInstitutionId: StoreService.hqDocId,
            sellerName: 'Genel Merkez Mağazası',
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
            targetAllSchools: d.targetAllSchools,
            targetSchoolIds: d.targetSchoolIds.toList(),
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
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEKME 3: GENEL MERKEZ SİPARİŞLERİ & CİRO
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHqOrdersTab() {
    return StreamBuilder<List<StoreOrder>>(
      stream: _hqOrdersStream,
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
        final shippingCount = orders
            .where(
              (o) =>
                  o.orderStatus == StoreOrderStatuses.hazirlaniyor ||
                  o.orderStatus == StoreOrderStatuses.kargoda ||
                  o.orderStatus == StoreOrderStatuses.onaylandi,
            )
            .length;
        final completedCount = orders
            .where((o) => o.orderStatus == StoreOrderStatuses.teslimEdildi)
            .length;

        final distinctSchools = <String>{
          for (final o in orders)
            if ((o.schoolName ?? '').trim().isNotEmpty) o.schoolName!.trim(),
        }.toList()..sort();

        final filtered = orders.where((o) {
          if (_orderStatusFilter != 'Tümü' &&
              o.orderStatus != _orderStatusFilter) {
            return false;
          }
          if (_orderRoleFilter != 'Tümü' &&
              StoreBuyerRoles.normalize(o.buyerRole) != _orderRoleFilter) {
            return false;
          }
          if (_orderSchoolFilter != 'Tümü' &&
              distinctSchools.contains(_orderSchoolFilter) &&
              (o.schoolName ?? '') != _orderSchoolFilter) {
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // KPI Kartları
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _kpiCard(
                          title: 'Genel Merkez Toplam Ciro',
                          value: _currencyFmt.format(validRevenue),
                          icon: Icons.payments_rounded,
                          color: Colors.green.shade700,
                        ),
                        _kpiCard(
                          title: 'Bekleyen Sipariş',
                          value: '$pendingCount',
                          icon: Icons.hourglass_top_rounded,
                          color: Colors.amber.shade800,
                        ),
                        _kpiCard(
                          title: 'Hazırlanan / Kargoda',
                          value: '$shippingCount',
                          icon: Icons.local_shipping_rounded,
                          color: Colors.blue.shade700,
                        ),
                        _kpiCard(
                          title: 'Teslim Edilen',
                          value: '$completedCount',
                          icon: Icons.task_alt_rounded,
                          color: Colors.indigo.shade700,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Filtre Çubuğu (her zaman sabit, klavye odağı korunur)
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
                            width: 245,
                            child: TextField(
                              controller: _orderSearchCtrl,
                              onChanged: (v) =>
                                  setState(() => _orderSearch = v.trim()),
                              decoration: _modernFieldDeco(
                                hint: 'Sipariş No, Alıcı veya Öğrenci...',
                                prefixIcon: Icons.search_rounded,
                                suffixIcon: _orderSearch.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(
                                          Icons.clear_rounded,
                                          size: 18,
                                        ),
                                        onPressed: () {
                                          _orderSearchCtrl.clear();
                                          setState(() => _orderSearch = '');
                                        },
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 215,
                            child: DropdownButtonFormField<String>(
                              key: ValueKey(_orderStatusFilter),
                              initialValue: _orderStatusFilter,
                              isExpanded: true,
                              borderRadius: BorderRadius.circular(14),
                              decoration: _modernFieldDeco(
                                label: 'Durum',
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
                            width: 195,
                            child: DropdownButtonFormField<String>(
                              key: ValueKey(_orderRoleFilter),
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
                          if (distinctSchools.isNotEmpty)
                            SizedBox(
                              width: 235,
                              child: DropdownButtonFormField<String>(
                                key: ValueKey(
                                  distinctSchools.contains(_orderSchoolFilter)
                                      ? _orderSchoolFilter
                                      : 'Tümü',
                                ),
                                initialValue:
                                    distinctSchools.contains(_orderSchoolFilter)
                                    ? _orderSchoolFilter
                                    : 'Tümü',
                                borderRadius: BorderRadius.circular(14),
                                isExpanded: true,
                                decoration: _modernFieldDeco(
                                  label: 'Okul',
                                  prefixIcon: Icons.school_outlined,
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: 'Tümü',
                                    child: Text('Tüm Okullar'),
                                  ),
                                  ...distinctSchools.map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(
                                        s,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() => _orderSchoolFilter = v);
                                  }
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
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
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
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
                          'Siparişler yüklenirken hata oluştu.',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => setState(() {
                            _hqOrdersStream = _storeService.watchHqOrders();
                          }),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
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
                        'Seçili filtrelere uygun Genel Merkez siparişi bulunamadı.',
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
                      _buildSellerOrderCard(filtered[index]),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 235,
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

  Widget _buildSellerOrderCard(StoreOrder o) {
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
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${o.schoolName ?? o.institutionId}${o.schoolTypeName != null ? ' • ${o.schoolTypeName}' : ''}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.indigo.shade800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  StoreOrderStatuses.labelOf(o.orderStatus),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
              Text(
                fmt.format(o.createdAt),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
                'Not: ${o.orderNote}',
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
                'Toplam: ${_currencyFmt.format(o.totalAmount)} (${o.cardMasked} • ${o.paymentRef})',
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
                onPressed: () => _promptTrackingAndShip(o),
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
                  cancelReason: 'Genel Merkez tarafından iptal edildi',
                ),
                child: const Text('İptal'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _promptTrackingAndShip(StoreOrder order) async {
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
                'Kargoya Ver & Takip Kodu Gir',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: TextField(
            controller: ctrl,
            decoration: _modernFieldDeco(
              label: 'Kargo Firması ve Takip Kodu',
              hint: 'Örn: Yurtiçi - 90248122',
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
            label: const Text('Kaydet & Kargoya Ver'),
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
