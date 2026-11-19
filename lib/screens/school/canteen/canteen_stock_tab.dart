import 'dart:async';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../models/canteen/canteen_models.dart';
import '../../../services/canteen_service.dart';
import 'canteen_common.dart';

/// Stok sekmesi: Ürün Kataloğu / Depolar / Stok Hareketleri — KantiN Studio.
class CanteenStockTab extends StatefulWidget {
  final String institutionId;
  const CanteenStockTab({super.key, required this.institutionId});

  @override
  State<CanteenStockTab> createState() => _CanteenStockTabState();
}

class _CanteenStockTabState extends State<CanteenStockTab>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final CanteenService _svc = CanteenService.instance;
  late final TabController _tabs;

  final TextEditingController _searchCtrl = TextEditingController();
  String _category = '';
  bool _lowOnly = false;

  StreamSubscription<List<CanteenProduct>>? _pSub;
  StreamSubscription<List<CanteenWarehouse>>? _wSub;
  StreamSubscription<List<CanteenStockMovement>>? _mSub;

  List<CanteenProduct> _products = const [];
  List<CanteenWarehouse> _warehouses = const [];
  List<CanteenStockMovement> _movements = const [];

  bool _pLoading = true;
  bool _wLoading = true;
  bool _mLoading = true;
  String? _error;

  String get _inst => widget.institutionId.trim();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)..addListener(_onSubTab);
    _subscribe();
  }

  void _onSubTab() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant CanteenStockTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.institutionId != widget.institutionId) _subscribe();
  }

  void _subscribe() {
    _pSub?.cancel();
    _wSub?.cancel();
    _mSub?.cancel();
    _pSub = _wSub = _mSub = null;
    if (_inst.isEmpty) {
      _pLoading = _wLoading = _mLoading = false;
      _error = 'Kurum bilgisi bulunamadı.';
      return;
    }
    _pLoading = _wLoading = _mLoading = true;
    _error = null;

    void fail(Object e) {
      if (!mounted) return;
      setState(() {
        _pLoading = _wLoading = _mLoading = false;
        _error = cnErr(e);
      });
    }

    _pSub = _svc.watchProducts(_inst).listen((l) {
      if (!mounted) return;
      setState(() {
        _products = l;
        _pLoading = false;
      });
    }, onError: fail);

    _wSub = _svc.watchWarehouses(_inst).listen((l) {
      if (!mounted) return;
      setState(() {
        _warehouses = l;
        _wLoading = false;
      });
    }, onError: fail);

    _mSub = _svc.watchStockMovements(_inst).listen((l) {
      if (!mounted) return;
      setState(() {
        _movements = l;
        _mLoading = false;
      });
    }, onError: fail);
  }

  @override
  void dispose() {
    _pSub?.cancel();
    _wSub?.cancel();
    _mSub?.cancel();
    _tabs.removeListener(_onSubTab);
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Ürün / Depo / Stok İşlemleri ─────────────────────────────────────────

  Future<void> _editProduct([CanteenProduct? p]) async {
    if (_inst.isEmpty) return;
    final res = await showDialog<_ProductResult>(
      context: context,
      builder: (_) => _ProductDialog(
        instId: _inst,
        existing: p,
        warehouses: _warehouses,
        existingBarcodes: {
          for (final item in _products)
            if (item.barcode.isNotEmpty) item.barcode,
        },
        customCategories: _allCategories,
      ),
    );
    if (res == null || !mounted) return;
    try {
      await _svc.saveProduct(_inst, res.product);
      if (p != null && res.stockDelta != 0) {
        await _svc.adjustStock(
          _inst,
          p.id,
          res.stockDelta,
          'Manuel stok düzeltme',
        );
      }
      if (mounted) {
        cnSnack(
          context,
          p == null ? 'Yeni ürün kataloğa eklendi.' : 'Ürün güncellendi.',
        );
      }
    } catch (e) {
      if (mounted) cnSnack(context, cnErr(e), error: true);
    }
  }

  Future<void> _deleteProduct(CanteenProduct p) async {
    final ok = await cnConfirm(
      context,
      'Ürünü Sil',
      '"${p.name}" ürünü katalogdan kalıcı olarak silinecek. Onaylıyor musunuz?',
      confirmLabel: 'Ürünü Sil',
      icon: Icons.delete_outline_rounded,
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await _svc.deleteProduct(_inst, p.id);
      if (mounted) cnSnack(context, '"${p.name}" silindi.');
    } catch (e) {
      if (mounted) cnSnack(context, cnErr(e), error: true);
    }
  }

  Future<void> _quickStock(CanteenProduct p) async {
    final res = await showDialog<_QuickStockResult>(
      context: context,
      builder: (_) => _QuickStockDialog(product: p),
    );
    if (res == null || res.delta == 0 || !mounted) return;
    try {
      await _svc.adjustStock(_inst, p.id, res.delta, res.note);
      if (mounted) cnSnack(context, '"${p.name}" stoğu güncellendi.');
    } catch (e) {
      if (mounted) cnSnack(context, cnErr(e), error: true);
    }
  }

  Future<void> _bulkIn() async {
    final entries = await showDialog<Map<String, int>>(
      context: context,
      builder: (_) => _BulkStockDialog(products: _products),
    );
    if (entries == null || entries.isEmpty || !mounted) return;
    int ok = 0;
    String? err;
    for (final e in entries.entries) {
      try {
        await _svc.adjustStock(_inst, e.key, e.value, 'Toplu stok girişi');
        ok++;
      } catch (ex) {
        err = cnErr(ex);
      }
    }
    if (!mounted) return;
    if (err != null) {
      cnSnack(context, '$ok ürün güncellendi. Hata: $err', error: true);
    } else {
      cnSnack(context, '$ok ürünün stoğu topluca güncellendi.');
    }
  }

  Future<void> _editWarehouse([CanteenWarehouse? w]) async {
    final res = await showDialog<CanteenWarehouse>(
      context: context,
      builder: (_) => _WarehouseDialog(existing: w),
    );
    if (res == null || !mounted) return;
    try {
      await _svc.saveWarehouse(_inst, res);
      if (mounted) cnSnack(context, 'Depo kaydedildi.');
    } catch (e) {
      if (mounted) cnSnack(context, cnErr(e), error: true);
    }
  }

  Future<void> _deleteWarehouse(CanteenWarehouse w) async {
    final used = _products.any((p) => p.warehouseId == w.id);
    if (used) {
      cnSnack(
        context,
        'Bu depoya bağlı ürünler var, önce ürünleri taşıyın.',
        error: true,
      );
      return;
    }
    final ok = await cnConfirm(
      context,
      'Depoyu Sil',
      '"${w.name}" deposu silinecek. Emin misiniz?',
      confirmLabel: 'Sil',
      icon: Icons.delete_outline_rounded,
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await _svc.deleteWarehouse(_inst, w.id);
      if (mounted) cnSnack(context, 'Depo silindi.');
    } catch (e) {
      if (mounted) cnSnack(context, cnErr(e), error: true);
    }
  }

  // ── Yardımcılar ──────────────────────────────────────────────────────────

  List<String> get _allCategories {
    final s = <String>{
      for (final p in _products)
        if (p.category.trim().isNotEmpty) p.category.trim(),
    }.toList()..sort();
    return s;
  }

  List<CanteenProduct> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _products.where((p) {
      if (_category.isNotEmpty && p.category.trim() != _category) return false;
      if (_lowOnly && !p.isLowStock) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          p.barcode.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final totalProducts = _products.length;
    final lowCount = _products.where((p) => p.isLowStock).length;
    final totalCost = _products.fold<double>(
      0,
      (s, p) => s + (p.stock > 0 ? p.stock * p.cost : 0),
    );
    final potentialRev = _products.fold<double>(
      0,
      (s, p) => s + (p.stock > 0 ? p.stock * p.price : 0),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 4 KPI Kartı
          _buildKpis(
            totalProducts: totalProducts,
            lowCount: lowCount,
            totalCost: totalCost,
            potentialRev: potentialRev,
          ),
          const SizedBox(height: 12),

          // Modern Segmented Alt Sekmeler
          _buildSegmentedBar(),
          const SizedBox(height: 12),

          // Alt Sekme İçeriği
          Expanded(
            child: TabBarView(
              controller: _tabs,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _productsView(lowCount),
                _warehousesView(),
                _movementsView(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpis({
    required int totalProducts,
    required int lowCount,
    required double totalCost,
    required double potentialRev,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 980 ? 4 : (c.maxWidth >= 560 ? 2 : 1);
        final w = (c.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: w,
              child: CnKpi(
                label: 'Toplam Ürün',
                value: '$totalProducts',
                icon: Icons.inventory_2_outlined,
                color: CnColors.brand,
              ),
            ),
            SizedBox(
              width: w,
              child: CnKpi(
                label: 'Kritik Stok',
                value: '$lowCount',
                icon: Icons.warning_amber_rounded,
                color: lowCount > 0 ? CnColors.warnDark : CnColors.ok,
              ),
            ),
            SizedBox(
              width: w,
              child: CnKpi(
                label: 'Stok Maliyeti',
                value: cnMoney(totalCost),
                icon: Icons.shopping_cart_checkout_rounded,
                color: CnColors.indigo,
              ),
            ),
            SizedBox(
              width: w,
              child: CnKpi(
                label: 'Potansiyel Ciro',
                value: cnMoney(potentialRev),
                icon: Icons.trending_up_rounded,
                color: CnColors.ok,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSegmentedBar() {
    const items = [
      (Icons.storefront_outlined, 'Ürün Kataloğu'),
      (Icons.warehouse_outlined, 'Depolar'),
      (Icons.swap_vert_rounded, 'Stok Hareketleri'),
    ];
    final idx = _tabs.index;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CnColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Material(
                color: i == idx ? CnColors.brand : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _tabs.animateTo(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          items[i].$1,
                          size: 17,
                          color: i == idx ? Colors.white : CnColors.slate,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          items[i].$2,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: i == idx
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: i == idx ? Colors.white : CnColors.slate,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Alt Sekme 1: Ürün Kataloğu ───────────────────────────────────────────

  Widget _productsView(int lowCount) {
    final list = _filtered;
    final cats = _allCategories;
    final warehouseNames = {for (final w in _warehouses) w.id: w.name};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CnPanel(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  final search = TextField(
                    controller: _searchCtrl,
                    decoration: cnInput(
                      'Ürün adı, barkod veya kategori ara...',
                      prefix: const Icon(Icons.search_rounded, size: 20),
                      suffix: _searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {});
                              },
                            ),
                    ),
                    onChanged: (_) => setState(() {}),
                  );
                  final actions = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        style: cnOutlineBtn(),
                        onPressed: _products.isEmpty ? null : _bulkIn,
                        icon: const Icon(Icons.playlist_add_rounded, size: 19),
                        label: const Text('Toplu Stok Girişi'),
                      ),
                      ElevatedButton.icon(
                        style: cnPrimaryBtn(),
                        onPressed: _inst.isEmpty ? null : () => _editProduct(),
                        icon: const Icon(Icons.add_rounded, size: 19),
                        label: const Text('Yeni Ürün Ekle'),
                      ),
                    ],
                  );
                  if (c.maxWidth < 740) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [search, const SizedBox(height: 10), actions],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: search),
                      const SizedBox(width: 10),
                      actions,
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _filterPill(
                      label: 'Kritik Stok ($lowCount)',
                      selected: _lowOnly,
                      warn: true,
                      onTap: () => setState(() => _lowOnly = !_lowOnly),
                    ),
                    _filterPill(
                      label: 'Tüm Kategoriler',
                      selected: _category.isEmpty,
                      onTap: () => setState(() => _category = ''),
                    ),
                    for (final c in cats)
                      _filterPill(
                        label: c,
                        selected: _category == c,
                        onTap: () => setState(() => _category = c),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _pLoading
              ? const Center(
                  child: CircularProgressIndicator(color: CnColors.brand),
                )
              : _error != null
              ? CnError(_error!, onRetry: _subscribe)
              : list.isEmpty
              ? CnEmpty(
                  _products.isEmpty
                      ? 'Ürün kataloğu henüz boş.'
                      : 'Filtreye uygun ürün bulunamadı.',
                  subtitle: _products.isEmpty
                      ? 'Yeni ürün ekleyerek kantin satış kataloğunu oluşturmaya başlayın.'
                      : 'Arama metnini veya kategori filtresini temizleyin.',
                  icon: Icons.inventory_2_outlined,
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) =>
                      _productRow(list[i], warehouseNames),
                ),
        ),
      ],
    );
  }

  Widget _filterPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool warn = false,
  }) {
    final activeCol = warn ? CnColors.warnDark : CnColors.brand;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? activeCol : CnColors.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? activeCol
                    : (warn
                          ? CnColors.warn.withValues(alpha: 0.5)
                          : CnColors.border),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected
                    ? Colors.white
                    : (warn ? CnColors.warnDark : CnColors.slate),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _productRow(CanteenProduct p, Map<String, String> warehouseNames) {
    final low = p.isLowStock;
    final stockCol = p.stock <= 0
        ? Colors.red.shade700
        : (low ? CnColors.warnDark : CnColors.okDark);
    final whName = warehouseNames[p.warehouseId] ?? '';

    return CnPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          CnProductAvatar(
            imageUrl: p.imageUrl,
            category: p.category,
            width: 52,
            height: 52,
            radius: 13,
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
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: p.isActive ? CnColors.text : CnColors.muted,
                        ),
                      ),
                    ),
                    if (!p.isActive) ...[
                      const SizedBox(width: 6),
                      const CnBadge('Pasif', color: CnColors.muted),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (p.category.isNotEmpty)
                      CnBadge(
                        p.category,
                        color: cnCategoryColor(p.category),
                        icon: cnCategoryIcon(p.category),
                      ),
                    if (p.barcode.isNotEmpty)
                      Text(
                        'Barkod: ${p.barcode}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                          color: CnColors.muted,
                        ),
                      ),
                    if (whName.isNotEmpty)
                      Text(
                        'Depo: $whName',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: CnColors.muted,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                cnMoney(p.price),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: CnColors.brand,
                ),
              ),
              if (p.cost > 0)
                Text(
                  'Maliyet: ${cnMoney(p.cost)}',
                  style: const TextStyle(fontSize: 11, color: CnColors.muted),
                ),
              const SizedBox(height: 4),
              CnBadge(
                '${p.stock} ${p.unit}',
                color: stockCol,
                icon: low
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline,
              ),
            ],
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Hızlı Stok Giriş/Çıkış',
            onPressed: () => _quickStock(p),
            icon: const Icon(
              Icons.exposure_rounded,
              color: CnColors.indigo,
              size: 20,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'İşlemler',
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onSelected: (v) {
              if (v == 'edit') _editProduct(p);
              if (v == 'stock') _quickStock(p);
              if (v == 'del') _deleteProduct(p);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18, color: CnColors.slate),
                    SizedBox(width: 8),
                    Text('Ürünü Düzenle'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'stock',
                child: Row(
                  children: [
                    Icon(
                      Icons.swap_vert_rounded,
                      size: 18,
                      color: CnColors.indigo,
                    ),
                    SizedBox(width: 8),
                    Text('Stok Girişi / Çıkışı'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'del',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: Colors.red,
                    ),
                    SizedBox(width: 8),
                    Text('Ürünü Sil', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Alt Sekme 2: Depolar ─────────────────────────────────────────────────

  Widget _warehousesView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            style: cnPrimaryBtn(),
            onPressed: _inst.isEmpty ? null : () => _editWarehouse(),
            icon: const Icon(Icons.add_business_rounded, size: 18),
            label: const Text('Yeni Depo Tanımla'),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _wLoading
              ? const Center(
                  child: CircularProgressIndicator(color: CnColors.brand),
                )
              : _error != null
              ? CnError(_error!, onRetry: _subscribe)
              : _warehouses.isEmpty
              ? const CnEmpty(
                  'Tanımlı depo bulunmuyor.',
                  subtitle:
                      'Ana depo, soğuk hava dolabı veya tezgâh altı gibi stok noktaları oluşturabilirsiniz.',
                  icon: Icons.warehouse_outlined,
                )
              : ListView.separated(
                  itemCount: _warehouses.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final w = _warehouses[i];
                    final cnt = _products
                        .where((p) => p.warehouseId == w.id)
                        .length;
                    return CnPanel(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: CnColors.pinkBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.warehouse_rounded,
                              color: CnColors.brand,
                              size: 21,
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
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14.5,
                                          color: CnColors.text,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    CnBadge(
                                      w.isActive ? 'Aktif' : 'Pasif',
                                      color: w.isActive
                                          ? CnColors.okDark
                                          : CnColors.muted,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$cnt kayıtlı ürün'
                                  '${w.description.isEmpty ? '' : ' • ${w.description}'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: CnColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Düzenle',
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: CnColors.brand,
                            ),
                            onPressed: () => _editWarehouse(w),
                          ),
                          IconButton(
                            tooltip: 'Sil',
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.red.shade600,
                            ),
                            onPressed: () => _deleteWarehouse(w),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Alt Sekme 3: Stok Hareketleri ────────────────────────────────────────

  Widget _movementsView() {
    final names = {for (final p in _products) p.id: p.name};
    if (_mLoading) {
      return const Center(
        child: CircularProgressIndicator(color: CnColors.brand),
      );
    }
    if (_error != null) return CnError(_error!, onRetry: _subscribe);
    if (_movements.isEmpty) {
      return const CnEmpty(
        'Henüz stok hareketi yok.',
        subtitle:
            'Satışlar ve manuel/toplu stok giriş-çıkışları burada kronolojik olarak listelenir.',
        icon: Icons.swap_vert_rounded,
      );
    }

    return ListView.separated(
      itemCount: _movements.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final m = _movements[i];
        final plus = m.type == 'in';
        final col = plus ? CnColors.okDark : CnColors.brand;
        return CnPanel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: plus ? CnColors.okSoft : CnColors.pinkBg,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  plus ? Icons.south_west_rounded : Icons.north_east_rounded,
                  color: col,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      names[m.productId] ?? '(Silinmiş Ürün)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: CnColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${cnDateTime(m.createdAt)}'
                      '${m.note.isEmpty ? '' : ' • ${m.note}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: CnColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              CnBadge('${plus ? '+' : '-'}${m.qty}', color: col),
            ],
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// DİYALOGLAR (Tümü CnDialogShell ile)
// ═════════════════════════════════════════════════════════════════════════════

class _ProductResult {
  final CanteenProduct product;
  final int stockDelta;
  const _ProductResult(this.product, this.stockDelta);
}

class _ProductDialog extends StatefulWidget {
  final String instId;
  final CanteenProduct? existing;
  final List<CanteenWarehouse> warehouses;
  final Set<String> existingBarcodes;
  final List<String> customCategories;

  const _ProductDialog({
    required this.instId,
    required this.existing,
    required this.warehouses,
    required this.existingBarcodes,
    required this.customCategories,
  });

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _barcode;
  late final TextEditingController _price;
  late final TextEditingController _cost;
  late final TextEditingController _stock;
  late final TextEditingController _minStock;
  late final TextEditingController _imageUrl;

  late String _unit;
  late bool _active;
  String _warehouseId = '';
  bool _showUrlInput = false;
  bool _uploadingImage = false;
  String? _err;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    String n(num v) => v == 0
        ? ''
        : (v == v.roundToDouble()
              ? v.toInt().toString()
              : v.toStringAsFixed(2));
    _name = TextEditingController(text: p?.name ?? '');
    _category = TextEditingController(text: p?.category ?? '');
    _barcode = TextEditingController(text: p?.barcode ?? '');
    _price = TextEditingController(text: p == null ? '' : n(p.price));
    _cost = TextEditingController(text: p == null ? '' : n(p.cost));
    _stock = TextEditingController(text: (p?.stock ?? 0).toString());
    _minStock = TextEditingController(text: (p?.minStock ?? 5).toString());
    _imageUrl = TextEditingController(text: p?.imageUrl ?? '');
    final u = (p?.unit ?? 'adet').trim();
    _unit = kCnProductUnits.contains(u) ? u : 'adet';
    _active = p?.isActive ?? true;
    final wid = p?.warehouseId ?? '';
    _warehouseId = widget.warehouses.any((w) => w.id == wid) ? wid : '';
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _barcode.dispose();
    _price.dispose();
    _cost.dispose();
    _stock.dispose();
    _minStock.dispose();
    _imageUrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage() async {
    if (_uploadingImage) return;
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (res == null ||
          res.files.isEmpty ||
          res.files.first.bytes == null ||
          !mounted) {
        return;
      }
      setState(() {
        _uploadingImage = true;
        _err = null;
      });
      final url = await CanteenService.instance.uploadProductImage(
        instId: widget.instId,
        bytes: res.files.first.bytes!,
        fileName: res.files.first.name,
      );
      if (!mounted) return;
      setState(() {
        _imageUrl.text = url;
        _uploadingImage = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadingImage = false;
        _err = 'Görsel yüklenemedi: ${cnErr(e)}';
      });
    }
  }

  void _generateBarcode() {
    final rnd = Random();
    String candidate = '';
    for (var i = 0; i < 30; i++) {
      final body = List.generate(10, (_) => rnd.nextInt(10)).join();
      candidate = '869$body';
      if (!widget.existingBarcodes.contains(candidate)) break;
    }
    setState(() => _barcode.text = candidate);
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      setState(() => _err = 'Ürün adı zorunludur.');
      return;
    }
    final price = cnParseMoney(_price.text);
    if (price < 0) {
      setState(() => _err = 'Satış fiyatı negatif olamaz.');
      return;
    }
    final stock = int.tryParse(_stock.text.trim()) ?? 0;
    if (stock < 0) {
      setState(() => _err = 'Stok adedi negatif olamaz.');
      return;
    }
    final e = widget.existing;
    final base = e ?? const CanteenProduct(name: '');
    final prod = base.copyWith(
      name: _name.text.trim(),
      category: _category.text.trim(),
      barcode: _barcode.text.trim(),
      price: price,
      cost: cnParseMoney(_cost.text),
      stock: e == null ? stock : e.stock,
      minStock: int.tryParse(_minStock.text.trim()) ?? 0,
      unit: _unit,
      imageUrl: _imageUrl.text.trim(),
      isActive: _active,
      warehouseId: _warehouseId,
    );
    Navigator.pop(
      context,
      _ProductResult(prod, e == null ? 0 : stock - e.stock),
    );
  }

  Widget _two(Widget a, Widget b) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 400) {
          return Column(children: [a, const SizedBox(height: 12), b]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 12),
            Expanded(child: b),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final salePrice = cnParseMoney(_price.text);
    final costPrice = cnParseMoney(_cost.text);
    final hasProfit = salePrice > 0 && costPrice > 0;
    final profit = salePrice - costPrice;
    final profitPct = costPrice > 0 ? (profit / costPrice) * 100 : 0.0;

    final allCats = <String>{
      ...kCnPresetCategories,
      ...widget.customCategories,
    }.toList();

    return CnDialogShell(
      title: _isEdit ? 'Ürünü Düzenle' : 'Yeni Kantin Ürünü Ekle',
      subtitle: 'Görsel, kategori, fiyatlandırma ve stok eşiklerini belirleyin',
      icon: _isEdit ? Icons.edit_outlined : Icons.add_business_rounded,
      maxWidth: 640,
      loading: _uploadingImage,
      errorText: _err,
      primaryLabel: _isEdit ? 'Değişiklikleri Kaydet' : 'Ürünü Kaydet',
      onPrimary: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Ürün Görseli Yükleme Kartı
          const CnSectionLabel('ÜRÜN GÖRSELİ', icon: Icons.image_outlined),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CnColors.surfaceAlt,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: CnColors.border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    CnProductAvatar(
                      imageUrl: _imageUrl.text,
                      category: _category.text,
                      width: 68,
                      height: 68,
                      radius: 15,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            style: cnPrimaryBtn(),
                            onPressed: _uploadingImage
                                ? null
                                : _pickAndUploadImage,
                            icon: _uploadingImage
                                ? const SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.cloud_upload_outlined,
                                    size: 18,
                                  ),
                            label: Text(
                              _uploadingImage
                                  ? 'Yükleniyor...'
                                  : 'Görsel Yükle',
                            ),
                          ),
                          OutlinedButton.icon(
                            style: cnOutlineBtn(color: CnColors.slate),
                            onPressed: () =>
                                setState(() => _showUrlInput = !_showUrlInput),
                            icon: const Icon(Icons.link_rounded, size: 18),
                            label: const Text('URL ile ekle'),
                          ),
                          if (_imageUrl.text.trim().isNotEmpty)
                            TextButton(
                              style: cnTextBtn(),
                              onPressed: () =>
                                  setState(() => _imageUrl.clear()),
                              child: const Text('Kaldır'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_showUrlInput) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _imageUrl,
                    onChanged: (_) => setState(() {}),
                    decoration: cnInput(
                      'Görsel Bağlantısı (https://...)',
                      fillColor: Colors.white,
                      prefix: const Icon(Icons.link_rounded, size: 19),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Ürün Adı & Kategori
          const CnSectionLabel(
            'TEMEL BİLGİLER & KATEGORİ',
            icon: Icons.fastfood_outlined,
          ),
          TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            decoration: cnInput(
              'Ürün Adı *',
              hint: 'Örn. Kaşarlı Tost, Ayran 200ml',
              prefix: const Icon(Icons.label_outline_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in allCats)
                ChoiceChip(
                  label: Text(c),
                  selected: _category.text.trim() == c,
                  showCheckmark: false,
                  selectedColor: CnColors.brand,
                  backgroundColor: CnColors.surfaceAlt,
                  side: BorderSide(
                    color: _category.text.trim() == c
                        ? CnColors.brand
                        : CnColors.border,
                  ),
                  avatar: Icon(
                    cnCategoryIcon(c),
                    size: 15,
                    color: _category.text.trim() == c
                        ? Colors.white
                        : cnCategoryColor(c),
                  ),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _category.text.trim() == c
                        ? Colors.white
                        : CnColors.slate,
                  ),
                  onSelected: (_) => setState(() => _category.text = c),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _two(
            TextField(
              controller: _category,
              onChanged: (_) => setState(() {}),
              decoration: cnInput(
                'Kategori',
                hint: 'Özel kategori yazabilir veya yukarıdan seçebilirsiniz',
                prefix: const Icon(Icons.category_outlined, size: 19),
              ),
            ),
            TextField(
              controller: _barcode,
              decoration: cnInput(
                'Barkod',
                hint: '869...',
                prefix: const Icon(Icons.qr_code_rounded, size: 19),
                suffix: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: TextButton(
                    style: cnTextBtn(),
                    onPressed: _generateBarcode,
                    child: const Text('Üret'),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Fiyat & Maliyet + Kâr Rozeti
          CnSectionLabel(
            'FİYATLANDIRMA',
            icon: Icons.payments_outlined,
            trailing: hasProfit
                ? CnBadge(
                    'Kâr: ${profit >= 0 ? '+' : ''}${cnMoney(profit)} (%${profitPct.toStringAsFixed(1)})',
                    color: profit >= 0 ? CnColors.okDark : Colors.red.shade700,
                  )
                : null,
          ),
          _two(
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: cnInput(
                'Satış Fiyatı (₺) *',
                prefix: const Icon(Icons.sell_outlined, size: 19),
              ),
            ),
            TextField(
              controller: _cost,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: cnInput(
                'Birim Maliyet (₺)',
                prefix: const Icon(Icons.shopping_bag_outlined, size: 19),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Stok, Min Stok, Birim, Depo
          const CnSectionLabel(
            'STOK & DEPO AYARLARI',
            icon: Icons.inventory_2_outlined,
          ),
          _two(
            TextField(
              controller: _stock,
              keyboardType: TextInputType.number,
              decoration: cnInput(
                _isEdit
                    ? 'Güncel Stok (Fark hareket olarak işlenir)'
                    : 'Başlangıç Stoğu',
                prefix: const Icon(Icons.numbers_rounded, size: 19),
              ),
            ),
            TextField(
              controller: _minStock,
              keyboardType: TextInputType.number,
              decoration: cnInput(
                'Kritik Stok Uyarı Eşiği',
                prefix: const Icon(Icons.warning_amber_rounded, size: 19),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _two(
            DropdownButtonFormField<String>(
              key: ValueKey('unit_$_unit'),
              initialValue: _unit,
              isExpanded: true,
              decoration: cnInput('Birim'),
              items: [
                for (final u in kCnProductUnits)
                  DropdownMenuItem(value: u, child: Text(u)),
              ],
              onChanged: (v) => setState(() => _unit = v ?? 'adet'),
            ),
            DropdownButtonFormField<String>(
              key: ValueKey('wh_$_warehouseId'),
              initialValue: _warehouseId,
              isExpanded: true,
              decoration: cnInput('Bulunduğu Depo'),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('— Genel / Depo Seçilmedi —'),
                ),
                for (final w in widget.warehouses)
                  DropdownMenuItem(
                    value: w.id,
                    child: Text(w.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _warehouseId = v ?? ''),
            ),
          ),
          const SizedBox(height: 14),

          // Satışa Açık Kartı
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: CnColors.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: CnColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  _active
                      ? Icons.check_circle_outline_rounded
                      : Icons.visibility_off_outlined,
                  color: _active ? CnColors.ok : CnColors.muted,
                  size: 21,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'POS Kasasında Satışa Açık',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: CnColors.text,
                    ),
                  ),
                ),
                Switch(
                  value: _active,
                  activeTrackColor: CnColors.brand,
                  onChanged: (v) => setState(() => _active = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WarehouseDialog extends StatefulWidget {
  final CanteenWarehouse? existing;
  const _WarehouseDialog({required this.existing});

  @override
  State<_WarehouseDialog> createState() => _WarehouseDialogState();
}

class _WarehouseDialogState extends State<_WarehouseDialog> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late bool _active;
  String? _err;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _desc = TextEditingController(text: widget.existing?.description ?? '');
    _active = widget.existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return CnDialogShell(
      title: isEdit ? 'Depoyu Düzenle' : 'Yeni Depo Ekle',
      subtitle: 'Kantin stok noktasının adını ve açıklamasını girin',
      icon: Icons.warehouse_rounded,
      maxWidth: 460,
      errorText: _err,
      primaryLabel: 'Kaydet',
      onPrimary: () {
        if (_name.text.trim().isEmpty) {
          setState(() => _err = 'Depo adı zorunludur.');
          return;
        }
        final e = widget.existing;
        Navigator.pop(
          context,
          CanteenWarehouse(
            id: e?.id ?? '',
            institutionId: e?.institutionId ?? '',
            name: _name.text.trim(),
            description: _desc.text.trim(),
            isActive: _active,
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            decoration: cnInput(
              'Depo Adı *',
              hint: 'Örn. Ana Depo, İçecek Dolabı',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            maxLines: 2,
            decoration: cnInput('Açıklama (Opsiyonel)'),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: CnColors.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: CnColors.border),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Depo Aktif',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Switch(
                  value: _active,
                  activeTrackColor: CnColors.brand,
                  onChanged: (v) => setState(() => _active = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BulkStockDialog extends StatefulWidget {
  final List<CanteenProduct> products;
  const _BulkStockDialog({required this.products});

  @override
  State<_BulkStockDialog> createState() => _BulkStockDialogState();
}

class _BulkStockDialogState extends State<_BulkStockDialog> {
  final TextEditingController _search = TextEditingController();
  final Map<String, TextEditingController> _ctrls = {};

  TextEditingController _ctrlFor(String id) =>
      _ctrls.putIfAbsent(id, () => TextEditingController());

  int get _filledCount {
    var c = 0;
    _ctrls.forEach((_, ctrl) {
      if ((int.tryParse(ctrl.text.trim()) ?? 0) > 0) c++;
    });
    return c;
  }

  @override
  void dispose() {
    _search.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.products
        : widget.products
              .where(
                (p) =>
                    p.name.toLowerCase().contains(q) ||
                    p.barcode.toLowerCase().contains(q),
              )
              .toList();

    return CnDialogShell(
      title: 'Toplu Stok Girişi',
      subtitle: _filledCount == 0
          ? 'Tedarik edilen ürünlerin eklenecek miktarlarını girin'
          : '$_filledCount ürün stoğa eklenecek',
      icon: Icons.playlist_add_check_rounded,
      maxWidth: 580,
      scrollable: false,
      primaryLabel: 'Stoğa Ekle',
      onPrimary: () {
        final out = <String, int>{};
        _ctrls.forEach((id, c) {
          final v = int.tryParse(c.text.trim()) ?? 0;
          if (v > 0) out[id] = v;
        });
        Navigator.pop(context, out);
      },
      child: SizedBox(
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _search,
              decoration: cnInput(
                'Ürün veya barkod ara...',
                prefix: const Icon(Icons.search_rounded, size: 20),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 10, color: Color(0xFFF1F5F9)),
                itemBuilder: (context, i) {
                  final p = list[i];
                  return Row(
                    children: [
                      CnProductAvatar(
                        imageUrl: p.imageUrl,
                        category: p.category,
                        width: 38,
                        height: 38,
                        radius: 9,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: CnColors.text,
                              ),
                            ),
                            Text(
                              'Mevcut: ${p.stock} ${p.unit}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: CnColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _ctrlFor(p.id),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: cnInput('+ Adet'),
                        ),
                      ),
                    ],
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

class _QuickStockResult {
  final int delta;
  final String note;
  const _QuickStockResult(this.delta, this.note);
}

class _QuickStockDialog extends StatefulWidget {
  final CanteenProduct product;
  const _QuickStockDialog({required this.product});

  @override
  State<_QuickStockDialog> createState() => _QuickStockDialogState();
}

class _QuickStockDialogState extends State<_QuickStockDialog> {
  bool _isIn = true;
  final TextEditingController _qty = TextEditingController();
  final TextEditingController _note = TextEditingController(
    text: 'Tedarik girişi',
  );
  String? _err;

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final rawQty = (int.tryParse(_qty.text.trim()) ?? 0).abs();
    final delta = _isIn ? rawQty : -rawQty;
    final nextStock = p.stock + delta;

    return CnDialogShell(
      title: 'Hızlı Stok Hareketi',
      subtitle: '${p.name} • Mevcut: ${p.stock} ${p.unit}',
      icon: Icons.exposure_rounded,
      iconColor: CnColors.indigo,
      maxWidth: 460,
      errorText: _err,
      primaryLabel: 'Uygula',
      onPrimary: () {
        if (rawQty <= 0) {
          setState(() => _err = 'Lütfen sıfırdan büyük bir miktar girin.');
          return;
        }
        if (nextStock < 0) {
          setState(() => _err = 'Stok eksiye düşemez (Mevcut: ${p.stock}).');
          return;
        }
        Navigator.pop(context, _QuickStockResult(delta, _note.text.trim()));
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _modeBtn(
                  label: '+ Stok Girişi',
                  selected: _isIn,
                  color: CnColors.okDark,
                  onTap: () => setState(() {
                    _isIn = true;
                    if (_note.text == 'Fire / stok çıkışı') {
                      _note.text = 'Tedarik girişi';
                    }
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _modeBtn(
                  label: '- Stok Çıkışı / Fire',
                  selected: !_isIn,
                  color: CnColors.brand,
                  onTap: () => setState(() {
                    _isIn = false;
                    if (_note.text == 'Tedarik girişi') {
                      _note.text = 'Fire / stok çıkışı';
                    }
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final preset in const [5, 10, 24, 50, 100])
                ActionChip(
                  backgroundColor: CnColors.surfaceAlt,
                  side: const BorderSide(color: CnColors.border),
                  label: Text(
                    '${_isIn ? '+' : '-'}$preset',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onPressed: () => setState(() => _qty.text = '$preset'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _qty,
            autofocus: true,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: cnInput('Miktar (${p.unit}) *'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _note, decoration: cnInput('Açıklama / Not')),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CnColors.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: CnColors.border),
            ),
            child: Row(
              children: [
                const Text(
                  'İşlem Sonrası Stok:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: CnColors.slate,
                  ),
                ),
                const Spacer(),
                Text(
                  '$nextStock ${p.unit}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: nextStock < 0 ? Colors.red : CnColors.text,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeBtn({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? color : CnColors.surfaceAlt,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? color : CnColors.border),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: selected ? Colors.white : CnColors.slate,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
