import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/store/store_models.dart';
import '../../services/store_service.dart';
import '../../widgets/edukn_app_bar.dart';
import '../../widgets/store_product_dialog.dart';
import 'online_payment_checkout_dialog.dart';

/// Çok-Rollü Ortak Mağaza Vitrini ve Sipariş Takip Ekranı (`idareci`, `ogretmen`, `veli`, `ogrenci`).
/// Hem Genel Merkez (`SUPER_ADMIN`) ürünlerini hem de Okulun bağımsız mağaza ürünlerini
/// yetki/hedefleme filtrelerine göre gösterir ve tek sepette online kart ile satın alma sunar.
class StoreShopScreen extends StatefulWidget {
  final String institutionId;
  final String? schoolId;
  final String? schoolName;
  final String? schoolTypeId;
  final String? schoolTypeName;
  final String buyerRole; // 'idareci' | 'ogretmen' | 'veli' | 'ogrenci'
  final String? studentId;
  final String? studentName;
  final bool embedded;

  const StoreShopScreen({
    super.key,
    required this.institutionId,
    this.schoolId,
    this.schoolName,
    this.schoolTypeId,
    this.schoolTypeName,
    required this.buyerRole,
    this.studentId,
    this.studentName,
    this.embedded = false,
  });

  @override
  State<StoreShopScreen> createState() => _StoreShopScreenState();
}

class _StoreShopScreenState extends State<StoreShopScreen>
    with SingleTickerProviderStateMixin {
  final StoreService _storeService = StoreService();
  final NumberFormat _currencyFmt = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: '₺',
    decimalDigits: 2,
  );
  final TextEditingController _searchCtrl = TextEditingController();

  late final TabController _tabController;

  bool _loadingContext = true;
  BuyerStoreContext? _buyerContext;

  Stream<HqStoreSchoolAccess>? _hqSettingsStream;
  Stream<SchoolStoreSettings>? _schoolSettingsStream;
  Stream<List<StoreOrder>>? _buyerOrdersStream;
  Stream<List<StoreProduct>>? _rawProductsStream;
  Stream<Set<String>>? _studentPurchasedIdsStream;

  // Bu oturumda tamamlanan siparişlerin ürün ID'leri (stream güncellenene kadar anında yansıması için)
  final Set<String> _justPurchasedProductIds = {};
  Set<String> _latestPurchasedProductIds = const {};

  String _sourceFilter = 'all'; // 'all' | 'hq' | 'school'
  String _selectedCategory = 'Tümü';
  String _searchQuery = '';

  // Ürün bazında seçili varyant state'i (productId -> variant)
  final Map<String, String> _selectedVariants = {};

  // Sepet state'i (cartKey -> StoreCartItem)
  final Map<String, StoreCartItem> _cart = {};

  List<StoreCartItem> get _cartItems => _cart.values.toList();
  int get _cartTotalQty =>
      _cart.values.fold<int>(0, (sum, item) => sum + item.quantity);
  double get _cartSubtotal =>
      _cart.values.fold<double>(0.0, (sum, item) => sum + item.lineTotal);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initBuyerContext();
  }

  @override
  void didUpdateWidget(covariant StoreShopScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.institutionId != widget.institutionId ||
        oldWidget.buyerRole != widget.buyerRole ||
        oldWidget.schoolId != widget.schoolId ||
        oldWidget.schoolTypeId != widget.schoolTypeId ||
        oldWidget.studentId != widget.studentId) {
      _initBuyerContext();
    }
  }

  void _bindStreamsForContext(BuyerStoreContext ctx) {
    _hqSettingsStream = _storeService.watchHqSettings();
    _schoolSettingsStream = _storeService.watchSchoolSettings(
      ctx.institutionId,
    );
    _buyerOrdersStream = _storeService.watchBuyerOrders(ctx.uid);
    _rawProductsStream = _storeService.watchRawCandidateProducts(
      ctx.institutionId,
    );
    _studentPurchasedIdsStream = _storeService.watchStudentPurchasedProductIds(
      ctx.studentId,
    );
  }

  bool _isRequiredMandatory(
    StoreProduct product,
    BuyerStoreContext ctx,
    Set<String> purchasedIds,
  ) {
    if (!product.isActive || product.isOutOfStock) return false;
    if (!product.isMandatoryForRole(ctx.buyerRole)) return false;
    return !purchasedIds.contains(product.id);
  }

  void _syncMandatoryProductsToCart({
    required List<StoreProduct> visibleProducts,
    required BuyerStoreContext ctx,
    required Set<String> purchasedIds,
  }) {
    final mandatoryToKeep = visibleProducts
        .where((p) => _isRequiredMandatory(p, ctx, purchasedIds))
        .toList();

    bool needsUpdate = false;
    final Map<String, StoreCartItem> nextCart = Map<String, StoreCartItem>.from(
      _cart,
    );

    // 1. Daha önce satın alınmış olan zorunlu ürünler sepette otomatik kalmışsa ve artık zorunlu değilse dokunma,
    // ancak henüz sepette olmayan zorunlu ürünleri otomatik ekle:
    for (final p in mandatoryToKeep) {
      final alreadyInCart = nextCart.values.any((c) => c.product.id == p.id);
      if (!alreadyInCart) {
        final chosenVariant = p.variants.isNotEmpty
            ? (_selectedVariants[p.id] ?? p.variants.first)
            : null;
        final item = StoreCartItem(
          product: p,
          selectedVariant: chosenVariant,
          quantity: 1,
        );
        nextCart[item.cartKey] = item;
        needsUpdate = true;
      }
    }

    if (needsUpdate && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          for (final entry in nextCart.entries) {
            _cart.putIfAbsent(entry.key, () => entry.value);
          }
        });
      });
    }
  }

  Future<void> _initBuyerContext() async {
    setState(() => _loadingContext = true);
    try {
      final ctx = await _storeService.resolveBuyerContext(
        institutionId: widget.institutionId,
        buyerRole: widget.buyerRole,
        schoolId: widget.schoolId,
        schoolName: widget.schoolName,
        schoolTypeId: widget.schoolTypeId,
        schoolTypeName: widget.schoolTypeName,
        studentId: widget.studentId,
        studentName: widget.studentName,
      );
      if (!mounted) return;
      setState(() {
        _buyerContext = ctx;
        _bindStreamsForContext(ctx);
        _loadingContext = false;
      });
    } catch (_) {
      if (!mounted) return;
      final fallbackInst = widget.institutionId.trim().toUpperCase();
      final fallbackRole = StoreBuyerRoles.normalize(widget.buyerRole);
      final fallbackCtx = BuyerStoreContext(
        uid: '',
        fullName: '${StoreBuyerRoles.labelOf(fallbackRole)} Kullanıcı',
        email: '',
        phone: '',
        buyerRole: fallbackRole,
        institutionId: fallbackInst,
        schoolId: widget.schoolId?.trim().isNotEmpty == true
            ? widget.schoolId!.trim()
            : fallbackInst,
        schoolName: widget.schoolName?.trim().isNotEmpty == true
            ? widget.schoolName!.trim()
            : (fallbackInst.isNotEmpty ? fallbackInst : 'Okul Mağazası'),
        schoolTypeIds: [
          if (widget.schoolTypeId != null &&
              widget.schoolTypeId!.trim().isNotEmpty)
            widget.schoolTypeId!.trim(),
        ],
        schoolTypeNames: [
          if (widget.schoolTypeName != null &&
              widget.schoolTypeName!.trim().isNotEmpty)
            widget.schoolTypeName!.trim(),
        ],
        studentId: widget.studentId,
        studentName: widget.studentName,
      );
      setState(() {
        _buyerContext = fallbackCtx;
        _bindStreamsForContext(fallbackCtx);
        _loadingContext = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _addToCart(StoreProduct product) {
    if (product.isOutOfStock) return;
    String? chosenVariant;
    if (product.variants.isNotEmpty) {
      chosenVariant = _selectedVariants[product.id] ?? product.variants.first;
    }
    final tempItem = StoreCartItem(
      product: product,
      selectedVariant: chosenVariant,
      quantity: 1,
    );
    final key = tempItem.cartKey;
    final currentQtyInCart = _cart.values
        .where((c) => c.product.id == product.id)
        .fold<int>(0, (a, b) => a + b.quantity);

    if (currentQtyInCart >= product.stock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Maksimum stok sınırına ulaşıldı (${product.stock} adet).',
          ),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      return;
    }

    setState(() {
      final existing = _cart[key];
      if (existing != null) {
        _cart[key] = existing.copyWith(quantity: existing.quantity + 1);
      } else {
        _cart[key] = tempItem;
      }
    });

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.indigo.shade900,
        content: Text(
          '${product.title}${chosenVariant != null ? ' ($chosenVariant)' : ''} sepete eklendi.',
        ),
        action: SnackBarAction(
          label: 'SEPETİ AÇ',
          textColor: Colors.amber.shade300,
          onPressed: _openCartSheetPlaceholder,
        ),
      ),
    );
  }

  HqStoreSchoolAccess _latestHqSettings = HqStoreSchoolAccess.defaults();
  SchoolStoreSettings? _latestSchoolSettings;

  void _openCartSheetPlaceholder() {
    final ctx = _buyerContext;
    if (ctx == null) return;
    _showCartBottomSheet(
      hqSettings: _latestHqSettings,
      schoolSettings:
          _latestSchoolSettings ??
          SchoolStoreSettings.defaults(ctx.institutionId),
    );
  }

  Future<void> _showCartBottomSheet({
    required HqStoreSchoolAccess hqSettings,
    required SchoolStoreSettings schoolSettings,
  }) async {
    final ctx = _buyerContext;
    if (ctx == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            final items = _cartItems;
            final hasHq = items.any((i) => i.product.isHq);
            final hasSchool = items.any((i) => i.product.isSchool);

            void updateQty(StoreCartItem item, int delta) {
              final next = item.quantity + delta;
              final isLockedMandatory = _isRequiredMandatory(
                item.product,
                ctx,
                _latestPurchasedProductIds,
              );
              final totalSameProductQty = _cart.values
                  .where((c) => c.product.id == item.product.id)
                  .fold<int>(0, (s, c) => s + c.quantity);

              if (delta < 0 &&
                  isLockedMandatory &&
                  totalSameProductQty + delta < 1) {
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Colors.deepOrange.shade800,
                    content: const Text(
                      'Bu ürün ilk alışverişinizde zorunludur ve sepetten çıkarılamaz.',
                    ),
                  ),
                );
                return;
              }

              setState(() {
                if (next <= 0) {
                  _cart.remove(item.cartKey);
                } else if (next <= item.product.stock) {
                  _cart[item.cartKey] = item.copyWith(quantity: next);
                }
              });
              setSheetState(() {});
            }

            void changeCartItemVariant(StoreCartItem item, String newVariant) {
              if (item.selectedVariant == newVariant) return;
              setState(() {
                _selectedVariants[item.product.id] = newVariant;
                _cart.remove(item.cartKey);
                final updated = StoreCartItem(
                  product: item.product,
                  selectedVariant: newVariant,
                  quantity: item.quantity,
                );
                final existing = _cart[updated.cartKey];
                if (existing != null) {
                  final combined = (existing.quantity + item.quantity).clamp(
                    1,
                    item.product.stock,
                  );
                  _cart[updated.cartKey] = existing.copyWith(
                    quantity: combined,
                  );
                } else {
                  _cart[updated.cartKey] = updated;
                }
              });
              setSheetState(() {});
            }

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.84,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.shopping_bag_rounded,
                          color: Colors.indigo.shade700,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Alışveriş Sepetim ($_cartTotalQty Ürün)',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Colors.indigo.shade900,
                            ),
                          ),
                        ),
                        if (items.isNotEmpty)
                          TextButton.icon(
                            onPressed: () {
                              int keptMandatory = 0;
                              setState(() {
                                final entries = _cart.entries.toList();
                                _cart.clear();
                                final seenMandatory = <String>{};
                                for (final e in entries) {
                                  final p = e.value.product;
                                  if (_isRequiredMandatory(
                                        p,
                                        ctx,
                                        _latestPurchasedProductIds,
                                      ) &&
                                      seenMandatory.add(p.id)) {
                                    final keepItem = e.value.copyWith(
                                      quantity: 1,
                                    );
                                    _cart[keepItem.cartKey] = keepItem;
                                    keptMandatory++;
                                  }
                                }
                              });
                              setSheetState(() {});
                              if (keptMandatory > 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    behavior: SnackBarBehavior.floating,
                                    backgroundColor: Colors.deepOrange.shade800,
                                    content: Text(
                                      'İsteğe bağlı ürünler temizlendi. Zorunlu $keptMandatory ürün sepetinizde korundu.',
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(
                              Icons.delete_sweep_outlined,
                              size: 18,
                            ),
                            label: const Text('Temizle'),
                          ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetCtx),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Column(
                        children: [
                          Icon(
                            Icons.remove_shopping_cart_outlined,
                            size: 56,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Sepetinizde henüz ürün bulunmuyor.',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    if (hasHq && hasSchool)
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.indigo.shade100),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color: Colors.indigo.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Genel Merkez ürünleri Genel Merkez tarafından, Okul Mağazası ürünleri ise ${ctx.schoolName} tarafından karşılanır.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.indigo.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, index) {
                          final item = items[index];
                          final isLockedMandatory = _isRequiredMandatory(
                            item.product,
                            ctx,
                            _latestPurchasedProductIds,
                          );
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isLockedMandatory
                                  ? Colors.deepOrange.shade50.withValues(
                                      alpha: 0.35,
                                    )
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isLockedMandatory
                                    ? Colors.deepOrange.shade200
                                    : Colors.grey.shade200,
                              ),
                            ),
                            child: Row(
                              children: [
                                _buildMiniProductThumb(item.product),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          _buildSellerBadge(
                                            item.product.isHq,
                                            compact: true,
                                          ),
                                          if (isLockedMandatory)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color:
                                                    Colors.deepOrange.shade100,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.lock_rounded,
                                                    size: 11,
                                                    color: Colors
                                                        .deepOrange
                                                        .shade900,
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    'Zorunlu Ürün',
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: Colors
                                                          .deepOrange
                                                          .shade900,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          if (item.product.deliveryBadgeLabel !=
                                              null)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                item
                                                    .product
                                                    .deliveryBadgeLabel!,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.blue.shade900,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.product.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                      if (item.product.variants.length > 1) ...[
                                        const SizedBox(height: 4),
                                        Wrap(
                                          spacing: 4,
                                          runSpacing: 4,
                                          children: item.product.variants.map((
                                            v,
                                          ) {
                                            final sel =
                                                item.selectedVariant == v;
                                            return InkWell(
                                              onTap: () =>
                                                  changeCartItemVariant(
                                                    item,
                                                    v,
                                                  ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 2.5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: sel
                                                      ? Colors.indigo.shade700
                                                      : Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: sel
                                                        ? Colors.indigo.shade700
                                                        : Colors.grey.shade300,
                                                  ),
                                                ),
                                                child: Text(
                                                  v,
                                                  style: TextStyle(
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: sel
                                                        ? Colors.white
                                                        : Colors.black87,
                                                  ),
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ] else if (item.selectedVariant != null)
                                        Text(
                                          'Seçenek: ${item.selectedVariant}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _currencyFmt.format(item.lineTotal),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: Colors.indigo.shade800,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      onPressed: () => updateQty(item, -1),
                                      icon: Icon(
                                        isLockedMandatory && item.quantity <= 1
                                            ? Icons.lock_outline_rounded
                                            : Icons
                                                  .remove_circle_outline_rounded,
                                        color:
                                            isLockedMandatory &&
                                                item.quantity <= 1
                                            ? Colors.deepOrange.shade400
                                            : null,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      tooltip:
                                          isLockedMandatory &&
                                              item.quantity <= 1
                                          ? 'Zorunlu ürün sepetten çıkarılamaz'
                                          : 'Azalt',
                                    ),
                                    Text(
                                      '${item.quantity}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => updateQty(item, 1),
                                      icon: const Icon(
                                        Icons.add_circle_outline_rounded,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 12,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ara Toplam',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                Text(
                                  _currencyFmt.format(_cartSubtotal),
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.indigo.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: () async {
                              final snapshotItems = List<StoreCartItem>.from(
                                _cartItems,
                              );
                              Navigator.pop(sheetCtx);
                              final orders =
                                  await OnlinePaymentCheckoutDialog.show(
                                    context: context,
                                    storeService: _storeService,
                                    buyerContext: ctx,
                                    cartItems: snapshotItems,
                                    hqSettings: hqSettings,
                                    schoolSettings: schoolSettings,
                                  );
                              if (orders != null &&
                                  orders.isNotEmpty &&
                                  mounted) {
                                setState(() {
                                  for (final o in orders) {
                                    for (final oi in o.items) {
                                      if (oi.productId.isNotEmpty) {
                                        _justPurchasedProductIds.add(
                                          oi.productId,
                                        );
                                      }
                                    }
                                  }
                                  _cart.clear();
                                });
                                _tabController.animateTo(1);
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.payment_rounded),
                            label: const Text('Online Ödemeye Geç'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingContext) {
      final loader = const Center(child: CircularProgressIndicator());
      if (widget.embedded) return loader;
      return Scaffold(
        appBar: EduknAppBar(
          title: 'Mağaza & Online Alışveriş',
          institutionId: widget.institutionId,
        ),
        body: loader,
      );
    }

    final ctx = _buyerContext!;
    if (_hqSettingsStream == null ||
        _schoolSettingsStream == null ||
        _buyerOrdersStream == null ||
        _rawProductsStream == null ||
        _studentPurchasedIdsStream == null) {
      _bindStreamsForContext(ctx);
    }

    return StreamBuilder<HqStoreSchoolAccess>(
      stream: _hqSettingsStream,
      builder: (context, hqSnap) {
        final hqSettings = hqSnap.data ?? HqStoreSchoolAccess.defaults();
        _latestHqSettings = hqSettings;

        return StreamBuilder<SchoolStoreSettings>(
          stream: _schoolSettingsStream,
          builder: (context, schSnap) {
            final schoolSettings =
                schSnap.data ?? SchoolStoreSettings.defaults(ctx.institutionId);
            _latestSchoolSettings = schoolSettings;

            return StreamBuilder<Set<String>>(
              stream: _studentPurchasedIdsStream,
              builder: (context, studentPurchasedSnap) {
                final studentPurchasedIds =
                    studentPurchasedSnap.data ?? const <String>{};

                return StreamBuilder<List<StoreOrder>>(
                  stream: _buyerOrdersStream,
                  builder: (context, ordersSnap) {
                    final myOrders = ordersSnap.data ?? const <StoreOrder>[];
                    final activeStudentId = (ctx.studentId ?? '').trim();

                    // Bu alıcının (veya seçili öğrencinin) daha önce satın aldığı ürün ID'lerini birleştir
                    final purchasedIds = <String>{
                      ...studentPurchasedIds,
                      ..._justPurchasedProductIds,
                    };
                    for (final o in myOrders) {
                      if (o.orderStatus == StoreOrderStatuses.iptal) continue;
                      if (o.paymentStatus != 'paid' &&
                          o.paymentStatus != 'odendi' &&
                          o.paymentStatus != 'tamamlandi') {
                        continue;
                      }
                      if (activeStudentId.isNotEmpty &&
                          (o.studentId ?? '').trim().isNotEmpty &&
                          o.studentId!.trim() != activeStudentId) {
                        continue;
                      }
                      for (final item in o.items) {
                        if (item.productId.isNotEmpty) {
                          purchasedIds.add(item.productId);
                        }
                      }
                    }
                    _latestPurchasedProductIds = purchasedIds;

                    final activeOrderCount = myOrders
                        .where(
                          (o) =>
                              o.orderStatus !=
                                  StoreOrderStatuses.teslimEdildi &&
                              o.orderStatus != StoreOrderStatuses.iptal,
                        )
                        .length;

                    final content = Column(
                      children: [
                        if (widget.embedded)
                          _buildEmbeddedTopBar(
                            ctx: ctx,
                            activeOrderCount: activeOrderCount,
                            hqSettings: hqSettings,
                            schoolSettings: schoolSettings,
                          ),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildStorefrontTab(
                                ctx: ctx,
                                hqSettings: hqSettings,
                                schoolSettings: schoolSettings,
                              ),
                              _buildMyOrdersTab(
                                myOrders,
                                isLoading:
                                    ordersSnap.connectionState ==
                                        ConnectionState.waiting &&
                                    !ordersSnap.hasData,
                                error: ordersSnap.error,
                                onRetry: () =>
                                    setState(() => _bindStreamsForContext(ctx)),
                              ),
                            ],
                          ),
                        ),
                        if (_cart.isNotEmpty)
                          _buildStickyCartBar(
                            hqSettings: hqSettings,
                            schoolSettings: schoolSettings,
                          ),
                      ],
                    );

                    if (widget.embedded) {
                      return Material(
                        color: const Color(0xFFF6F8FC),
                        child: content,
                      );
                    }

                    return Scaffold(
                      backgroundColor: const Color(0xFFF6F8FC),
                      appBar: EduknAppBar(
                        title: 'Mağaza & Online Satış',
                        institutionId: ctx.institutionId,
                        subtitle:
                            '${ctx.schoolName} • ${StoreBuyerRoles.labelOf(ctx.buyerRole)}${ctx.studentName?.isNotEmpty == true ? ' (${ctx.studentName})' : ''}',
                        actions: [
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: _buildCartActionButton(
                              hqSettings: hqSettings,
                              schoolSettings: schoolSettings,
                            ),
                          ),
                        ],
                        bottom: TabBar(
                          controller: _tabController,
                          labelColor: Colors.indigo.shade900,
                          unselectedLabelColor: Colors.grey.shade600,
                          indicatorColor: Colors.indigo.shade700,
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                          tabs: [
                            const Tab(
                              icon: Icon(Icons.storefront_rounded, size: 20),
                              text: 'Mağaza Vitrini',
                            ),
                            Tab(
                              icon: Badge(
                                isLabelVisible: activeOrderCount > 0,
                                label: Text('$activeOrderCount'),
                                child: const Icon(
                                  Icons.local_shipping_outlined,
                                  size: 20,
                                ),
                              ),
                              text: 'Siparişlerim (${myOrders.length})',
                            ),
                          ],
                        ),
                      ),
                      body: content,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEmbeddedTopBar({
    required BuyerStoreContext ctx,
    required int activeOrderCount,
    required HqStoreSchoolAccess hqSettings,
    required SchoolStoreSettings schoolSettings,
  }) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: Colors.indigo.shade900,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: Colors.indigo.shade700,
              dividerColor: Colors.transparent,
              tabs: [
                const Tab(text: '🛍️ Mağaza Vitrini'),
                Tab(
                  text: activeOrderCount > 0
                      ? '📦 Siparişlerim ($activeOrderCount Aktif)'
                      : '📦 Siparişlerim',
                ),
              ],
            ),
          ),
          _buildCartActionButton(
            hqSettings: hqSettings,
            schoolSettings: schoolSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildCartActionButton({
    required HqStoreSchoolAccess hqSettings,
    required SchoolStoreSettings schoolSettings,
  }) {
    return FilledButton.tonalIcon(
      onPressed: () => _showCartBottomSheet(
        hqSettings: hqSettings,
        schoolSettings: schoolSettings,
      ),
      icon: Badge(
        isLabelVisible: _cartTotalQty > 0,
        label: Text('$_cartTotalQty'),
        child: const Icon(Icons.shopping_cart_outlined, size: 19),
      ),
      label: Text(
        _cartTotalQty > 0 ? _currencyFmt.format(_cartSubtotal) : 'Sepetim',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _buildStickyCartBar({
    required HqStoreSchoolAccess hqSettings,
    required SchoolStoreSettings schoolSettings,
  }) {
    final hasBoth =
        _cartItems.any((e) => e.product.isHq) &&
        _cartItems.any((e) => e.product.isSchool);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.indigo.shade900,
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            const Icon(Icons.shopping_bag_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$_cartTotalQty Ürün • ${_currencyFmt.format(_cartSubtotal)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                    ),
                  ),
                  if (hasBoth)
                    const Text(
                      'Genel Merkez + Okul Mağazası ortak sepeti',
                      style: TextStyle(color: Colors.white70, fontSize: 11.5),
                    ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () => _showCartBottomSheet(
                hqSettings: hqSettings,
                schoolSettings: schoolSettings,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.amber.shade400,
                foregroundColor: Colors.indigo.shade900,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text(
                'Sepeti Onayla',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorefrontTab({
    required BuyerStoreContext ctx,
    required HqStoreSchoolAccess hqSettings,
    required SchoolStoreSettings schoolSettings,
  }) {
    return StreamBuilder<List<StoreProduct>>(
      stream: _rawProductsStream,
      builder: (context, prodSnap) {
        final isWaitingInitial =
            prodSnap.connectionState == ConnectionState.waiting &&
            !prodSnap.hasData;
        final rawProducts = prodSnap.data ?? const <StoreProduct>[];
        final allVisible = _storeService.filterVisibleProducts(
          allProducts: rawProducts,
          context: ctx,
          hqSettings: hqSettings,
          schoolSettings: schoolSettings,
        );
        final mandatoryRequired = allVisible
            .where(
              (p) => _isRequiredMandatory(p, ctx, _latestPurchasedProductIds),
            )
            .toList();
        if (mandatoryRequired.isNotEmpty) {
          _syncMandatoryProductsToCart(
            visibleProducts: allVisible,
            ctx: ctx,
            purchasedIds: _latestPurchasedProductIds,
          );
        }
        final hqCount = allVisible.where((p) => p.isHq).length;
        final schoolCount = allVisible.where((p) => p.isSchool).length;

        final filtered = allVisible.where((p) {
          if (_sourceFilter == 'hq' && !p.isHq) return false;
          if (_sourceFilter == 'school' && !p.isSchool) return false;
          if (_selectedCategory != 'Tümü' && p.category != _selectedCategory) {
            return false;
          }
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            final matchTitle = p.title.toLowerCase().contains(q);
            final matchDesc = p.description.toLowerCase().contains(q);
            final matchCat = p.category.toLowerCase().contains(q);
            if (!matchTitle && !matchDesc && !matchCat) return false;
          }
          return true;
        }).toList();

        final bannerText = [
          if (hqSettings.announcementBanner.trim().isNotEmpty)
            '🏛️ Genel Merkez: ${hqSettings.announcementBanner.trim()}',
          if (schoolSettings.announcementBanner.trim().isNotEmpty)
            '🏫 ${ctx.schoolName}: ${schoolSettings.announcementBanner.trim()}',
        ].join('   •   ');

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (bannerText.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.indigo.shade700,
                              Colors.deepPurple.shade600,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.campaign_rounded,
                              color: Colors.amberAccent,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                bannerText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (mandatoryRequired.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.deepOrange.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.deepOrange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.lock_rounded,
                              color: Colors.deepOrange.shade800,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'İlk alışverişinizde alınması zorunlu ${mandatoryRequired.length} ürün (${mandatoryRequired.map((e) => e.title).join(', ')}) sepetinize otomatik eklenmiştir. Satın alındıktan sonraki alışverişlerinizde tekrar eklenmez.',
                                style: TextStyle(
                                  color: Colors.deepOrange.shade900,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Satıcı kaynağı filtre butonları + Arama kutusu (her zaman sabit, focus kaybolmaz)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.025),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _sourceChip(
                                keyValue: 'all',
                                label: 'Tüm Ürünler (${allVisible.length})',
                              ),
                              _sourceChip(
                                keyValue: 'hq',
                                label: '🏛️ Genel Merkez Ürünleri ($hqCount)',
                              ),
                              _sourceChip(
                                keyValue: 'school',
                                label:
                                    '🏫 Okul Mağazası Ürünleri ($schoolCount)',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _searchCtrl,
                            onChanged: (val) =>
                                setState(() => _searchQuery = val.trim()),
                            decoration: InputDecoration(
                              hintText:
                                  'Kitap seti, deneme paketi, okul forması veya materyal ara...',
                              hintStyle: const TextStyle(
                                fontSize: 13.5,
                                color: Color(0xFF94A3B8),
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: Colors.indigo.shade600,
                                size: 20,
                              ),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.clear_rounded,
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 13,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFCBD5E1),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFCBD5E1),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: Colors.indigo.shade600,
                                  width: 1.8,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: ['Tümü', ...StoreCategories.all].map((
                                cat,
                              ) {
                                final selected = _selectedCategory == cat;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(cat),
                                    selected: selected,
                                    onSelected: (_) =>
                                        setState(() => _selectedCategory = cat),
                                    selectedColor: Colors.indigo.shade100,
                                    backgroundColor: const Color(0xFFF8FAFC),
                                    side: BorderSide(
                                      color: selected
                                          ? Colors.indigo.shade400
                                          : const Color(0xFFE2E8F0),
                                    ),
                                    labelStyle: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: selected
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: selected
                                          ? Colors.indigo.shade900
                                          : const Color(0xFF475569),
                                    ),
                                  ),
                                );
                              }).toList(),
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
            else if (prodSnap.hasError)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 56,
                          color: Colors.red.shade300,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Mağaza ürünleri yüklenirken bir hata oluştu.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () =>
                              setState(() => _bindStreamsForContext(ctx)),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Yeniden Dene'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.store_mall_directory_outlined,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Bu filtreye uygun aktif ürün bulunamadı.',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Okulunuz veya Genel Merkez yeni ürünler eklediğinde burada görüntülenecektir.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final availWidth = constraints.crossAxisExtent;
                    final SliverGridDelegate delegate;
                    if (availWidth < 390) {
                      delegate =
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 1,
                            mainAxisExtent: 432,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          );
                    } else if (availWidth < 540) {
                      delegate =
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisExtent: 458,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          );
                    } else {
                      delegate = const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 295,
                        mainAxisExtent: 446,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                      );
                    }
                    return SliverGrid(
                      gridDelegate: delegate,
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildProductCard(filtered[index]),
                        childCount: filtered.length,
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _sourceChip({required String keyValue, required String label}) {
    final selected = _sourceFilter == keyValue;
    return FilterChip(
      selected: selected,
      onSelected: (_) => setState(() => _sourceFilter = keyValue),
      label: Text(label),
      selectedColor: Colors.indigo.shade700,
      checkmarkColor: Colors.white,
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: selected ? Colors.white : Colors.indigo.shade900,
      ),
    );
  }

  Widget _buildProductCard(StoreProduct product) {
    final currentVariant = product.variants.isNotEmpty
        ? (_selectedVariants[product.id] ?? product.variants.first)
        : null;
    final ctx = _buyerContext;
    final isMandatoryForBuyer =
        ctx != null && product.isMandatoryForRole(ctx.buyerRole);
    final isAlreadyPurchased = _latestPurchasedProductIds.contains(product.id);
    final isLockedInCart =
        ctx != null &&
        _isRequiredMandatory(product, ctx, _latestPurchasedProductIds);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 215;

        final priceBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (product.hasDiscount)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _currencyFmt.format(product.price),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _currencyFmt.format(product.effectivePrice),
                style: TextStyle(
                  fontSize: isCompact ? 15.5 : 16.5,
                  fontWeight: FontWeight.w900,
                  color: Colors.indigo.shade900,
                ),
              ),
            ),
          ],
        );

        final addButton = FilledButton.icon(
          onPressed: product.isOutOfStock ? null : () => _addToCart(product),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.indigo.shade700,
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 10 : 12,
              vertical: isCompact ? 7 : 9,
            ),
            minimumSize: isCompact ? const Size(double.infinity, 34) : null,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
          icon: const Icon(Icons.add_shopping_cart_rounded, size: 15),
          label: Text(
            product.isOutOfStock
                ? 'Tükendi'
                : (isCompact ? 'Sepete Ekle' : 'Ekle'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        );

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Görsel Alanı
              InkWell(
                onTap: () => _showProductDetailDialog(product),
                child: SizedBox(
                  height: isCompact ? 142 : 152,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildProductCover(product),
                      Positioned(
                        top: 8,
                        left: 8,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: (constraints.maxWidth - 16).clamp(
                              80.0,
                              260.0,
                            ),
                          ),
                          child: _buildSellerBadge(
                            product.isHq,
                            compact: isCompact,
                          ),
                        ),
                      ),
                      if (product.hasDiscount)
                        Positioned(
                          top: isCompact ? null : 8,
                          bottom: isCompact ? 8 : null,
                          right: isCompact ? null : 8,
                          left: isCompact ? 8 : null,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isCompact ? 6 : 8,
                              vertical: isCompact ? 2.5 : 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade600,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                              '-%${product.discountPercentage}',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: isCompact ? 10.5 : 11.5,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: product.isOutOfStock
                                ? Colors.red.shade900.withValues(alpha: 0.88)
                                : Colors.black.withValues(alpha: 0.62),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            product.isOutOfStock
                                ? 'Stokta Yok'
                                : 'Stok: ${product.stock}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Ürün Detay Alanı
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    isCompact ? 8 : 10,
                    12,
                    isCompact ? 9 : 11,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    product.category,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.indigo.shade500,
                                    ),
                                  ),
                                ),
                                if (product.audienceBadgeLabel != null) ...[
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade50,
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(
                                          color: Colors.amber.shade300,
                                        ),
                                      ),
                                      child: Text(
                                        product.audienceBadgeLabel!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.amber.shade900,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (isMandatoryForBuyer ||
                                product.deliveryBadgeLabel != null) ...[
                              const SizedBox(height: 3),
                              Wrap(
                                spacing: 4,
                                runSpacing: 3,
                                children: [
                                  if (isMandatoryForBuyer)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isAlreadyPurchased
                                            ? Colors.green.shade50
                                            : Colors.deepOrange.shade50,
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(
                                          color: isAlreadyPurchased
                                              ? Colors.green.shade300
                                              : Colors.deepOrange.shade200,
                                        ),
                                      ),
                                      child: Text(
                                        isAlreadyPurchased
                                            ? 'Zorunlu • Alındı ✓'
                                            : (isLockedInCart
                                                  ? '🔒 Zorunlu • Sepette'
                                                  : '🔒 Zorunlu Ürün'),
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          color: isAlreadyPurchased
                                              ? Colors.green.shade800
                                              : Colors.deepOrange.shade900,
                                        ),
                                      ),
                                    ),
                                  if (product.deliveryBadgeLabel != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(
                                          color: Colors.blue.shade200,
                                        ),
                                      ),
                                      child: Text(
                                        product.deliveryBadgeLabel!,
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.blue.shade900,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: () => _showProductDetailDialog(product),
                              child: Text(
                                product.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: isCompact ? 13 : 14,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.indigo.shade900,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Flexible(
                              child: Text(
                                product.description.isNotEmpty
                                    ? product.description
                                    : product.sellerName,
                                maxLines:
                                    (isCompact ||
                                        product.variants.isNotEmpty ||
                                        isMandatoryForBuyer ||
                                        product.deliveryBadgeLabel != null)
                                    ? 1
                                    : 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Varyant Seçici
                          if (product.variants.isNotEmpty) ...[
                            SizedBox(
                              height: 30,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: product.variants.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 6),
                                itemBuilder: (_, idx) {
                                  final v = product.variants[idx];
                                  final sel = v == currentVariant;
                                  return InkWell(
                                    onTap: () => setState(
                                      () => _selectedVariants[product.id] = v,
                                    ),
                                    borderRadius: BorderRadius.circular(7),
                                    child: Container(
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: sel
                                            ? Colors.indigo.shade700
                                            : const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(7),
                                        border: Border.all(
                                          color: sel
                                              ? Colors.indigo.shade700
                                              : const Color(0xFFCBD5E1),
                                        ),
                                      ),
                                      child: Text(
                                        v,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: sel
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 6),
                          ],

                          // Fiyat + Sepete Ekle
                          if (isCompact) ...[
                            priceBlock,
                            const SizedBox(height: 5),
                            addButton,
                          ] else
                            Row(
                              children: [
                                Expanded(child: priceBlock),
                                const SizedBox(width: 8),
                                addButton,
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showProductDetailDialog(StoreProduct product) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        String? modalVariant = product.variants.isNotEmpty
            ? (_selectedVariants[product.id] ?? product.variants.first)
            : null;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 20,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 520,
                  maxHeight: MediaQuery.sizeOf(ctx).height * 0.88,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      child: SizedBox(
                        height: 220,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildProductCover(product),
                            Positioned(
                              top: 12,
                              left: 12,
                              child: _buildSellerBadge(product.isHq),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: CircleAvatar(
                                backgroundColor: Colors.black54,
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.white,
                                  ),
                                  onPressed: () => Navigator.pop(ctx),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  '${product.category} • Satıcı: ${product.sellerName}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.indigo.shade600,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (product.audienceBadgeLabel != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Colors.amber.shade300,
                                      ),
                                    ),
                                    child: Text(
                                      product.audienceBadgeLabel!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.amber.shade900,
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
                                    border: Border.all(
                                      color: Colors.blue.shade200,
                                    ),
                                  ),
                                  child: Text(
                                    'Teslimat: ${product.deliverySummaryLabel}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.blue.shade900,
                                    ),
                                  ),
                                ),
                                if (product.isMandatory)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.deepOrange.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Colors.deepOrange.shade200,
                                      ),
                                    ),
                                    child: Text(
                                      _latestPurchasedProductIds.contains(
                                            product.id,
                                          )
                                          ? 'Zorunlu Ürün • Satın Alındı ✓'
                                          : '🔒 İlk Alışverişte Zorunlu Ürün',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.deepOrange.shade900,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              product.title,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: Colors.indigo.shade900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (product.description.isNotEmpty) ...[
                              Text(
                                product.description,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: Colors.grey.shade700,
                                  height: 1.45,
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            if (product.variants.isNotEmpty) ...[
                              const Text(
                                'Seçenek / Beden / Seviye:',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: product.variants.map((v) {
                                  final sel = v == modalVariant;
                                  return ChoiceChip(
                                    label: Text(v),
                                    selected: sel,
                                    onSelected: (_) {
                                      setModalState(() => modalVariant = v);
                                      setState(
                                        () => _selectedVariants[product.id] = v,
                                      );
                                    },
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 16),
                            ],
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (product.hasDiscount)
                                      Text(
                                        _currencyFmt.format(product.price),
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade500,
                                          decoration:
                                              TextDecoration.lineThrough,
                                        ),
                                      ),
                                    Text(
                                      '${_currencyFmt.format(product.effectivePrice)} (KDV %${product.vatRate} Dahil)',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.indigo.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                                FilledButton.icon(
                                  onPressed: product.isOutOfStock
                                      ? null
                                      : () {
                                          Navigator.pop(ctx);
                                          _addToCart(product);
                                        },
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.indigo.shade700,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 13,
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.add_shopping_cart_rounded,
                                  ),
                                  label: const Text('Sepete Ekle'),
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
            );
          },
        );
      },
    );
  }

  Widget _buildMyOrdersTab(
    List<StoreOrder> orders, {
    bool isLoading = false,
    Object? error,
    VoidCallback? onRetry,
  }) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 56,
                color: Colors.red.shade300,
              ),
              const SizedBox(height: 12),
              Text(
                'Siparişleriniz yüklenirken bir sorun oluştu.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade800,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Yeniden Dene'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              Text(
                'Henüz siparişiniz bulunmuyor.',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Mağaza vitrininden verdiğiniz Genel Merkez ve Okul Mağazası siparişlerinizin durumunu buradan canlı takip edebilirsiniz.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) => _buildOrderCard(orders[index]),
    );
  }

  Widget _buildOrderCard(StoreOrder order) {
    final dateFmt = DateFormat('dd.MM.yyyy HH:mm');
    final isCancelled = order.orderStatus == StoreOrderStatuses.iptal;
    final steps = [
      StoreOrderStatuses.bekliyor,
      StoreOrderStatuses.onaylandi,
      StoreOrderStatuses.hazirlaniyor,
      StoreOrderStatuses.kargoda,
      StoreOrderStatuses.teslimEdildi,
    ];
    final currentStepIdx = steps.indexOf(order.orderStatus);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildSellerBadge(order.isHqOrder),
              Text(
                order.orderNo,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                  color: Colors.indigo.shade900,
                ),
              ),
              Text(
                '• ${dateFmt.format(order.createdAt)}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              _buildStatusPill(order.orderStatus),
            ],
          ),
          const SizedBox(height: 12),

          // Canlı Sipariş Adım Çubuğu
          if (!isCancelled)
            Row(
              children: List.generate(steps.length, (i) {
                final reached = i <= currentStepIdx;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: i == steps.length - 1 ? 0 : 4,
                    ),
                    child: Column(
                      children: [
                        Container(
                          height: 5,
                          decoration: BoxDecoration(
                            color: reached
                                ? Colors.green.shade600
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          StoreOrderStatuses.labelOf(steps[i]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: reached
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: reached
                                ? Colors.green.shade800
                                : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'İptal Edildi${order.cancelReason.isNotEmpty ? ': ${order.cancelReason}' : ''}',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.red.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

          if (order.trackingCode.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.local_shipping_rounded,
                    size: 18,
                    color: Colors.blue.shade800,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Kargo Takip Kodu: ${order.trackingCode}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    tooltip: 'Kopyala',
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: order.trackingCode),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Kargo takip kodu kopyalandı.'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],

          const Divider(height: 22),
          ...order.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.quantity}x ${item.title}${item.selectedVariant != null ? ' (${item.selectedVariant})' : ''}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
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
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${order.deliveryType} • ${order.cardMasked} (${order.paymentRef})',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      'Toplam: ${_currencyFmt.format(order.totalAmount)}',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.indigo.shade900,
                      ),
                    ),
                  ],
                ),
              ),
              if (order.canBuyerCancel)
                OutlinedButton.icon(
                  onPressed: () => _confirmBuyerCancel(order),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade200),
                  ),
                  icon: const Icon(Icons.cancel_outlined, size: 17),
                  label: const Text('Siparişi İptal Et'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmBuyerCancel(StoreOrder order) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.cancel_outlined, color: Colors.red.shade700, size: 22),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Siparişi İptal Et',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${order.orderNo} numaralı siparişinizi iptal etmek istediğinize emin misiniz?',
                style: TextStyle(fontSize: 13.5, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reasonCtrl,
                decoration: InputDecoration(
                  labelText: 'İptal Nedeni (Opsiyonel)',
                  hintText: 'Örn: Yanlış beden seçtim',
                  prefixIcon: Icon(
                    Icons.notes_rounded,
                    size: 19,
                    color: Colors.indigo.shade600,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: Colors.indigo.shade600,
                      width: 1.8,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('İptal Et'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _storeService.cancelOrderByBuyer(
          orderId: order.id,
          cancelReason: reasonCtrl.text,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Siparişiniz iptal edildi.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('İptal işlemi başarısız: $e')));
        }
      }
    }
  }

  Widget _buildSellerBadge(bool isHq, {bool compact = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: isHq ? Colors.deepPurple.shade700 : Colors.teal.shade700,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isHq ? '🏛️ Genel Merkez' : '🏫 Okul Mağazası',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildStatusPill(String status) {
    Color bg;
    Color fg;
    switch (status) {
      case StoreOrderStatuses.bekliyor:
        bg = Colors.amber.shade100;
        fg = Colors.amber.shade900;
        break;
      case StoreOrderStatuses.onaylandi:
      case StoreOrderStatuses.hazirlaniyor:
        bg = Colors.indigo.shade100;
        fg = Colors.indigo.shade900;
        break;
      case StoreOrderStatuses.kargoda:
        bg = Colors.blue.shade100;
        fg = Colors.blue.shade900;
        break;
      case StoreOrderStatuses.teslimEdildi:
        bg = Colors.green.shade100;
        fg = Colors.green.shade900;
        break;
      case StoreOrderStatuses.iptal:
      default:
        bg = Colors.red.shade100;
        fg = Colors.red.shade900;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        StoreOrderStatuses.labelOf(status),
        style: TextStyle(
          color: fg,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildMiniProductThumb(StoreProduct product) {
    final img = product.primaryImageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 56,
        height: 56,
        child: img != null && img.isNotEmpty
            ? StoreProductImage(
                url: img,
                fit: BoxFit.cover,
                fallback: _categoryFallbackCover(product),
              )
            : _categoryFallbackCover(product),
      ),
    );
  }

  Widget _buildProductCover(StoreProduct product) {
    final img = product.primaryImageUrl;
    if (img != null && img.isNotEmpty) {
      return StoreProductImage(
        url: img,
        fit: BoxFit.cover,
        fallback: _categoryFallbackCover(product),
      );
    }
    return _categoryFallbackCover(product);
  }

  Widget _categoryFallbackCover(StoreProduct product) {
    IconData icon;
    List<Color> colors;
    switch (product.category) {
      case StoreCategories.booksAndSets:
        icon = Icons.menu_book_rounded;
        colors = [Colors.indigo.shade500, Colors.blue.shade700];
        break;
      case StoreCategories.examsAndDigital:
        icon = Icons.analytics_rounded;
        colors = [Colors.deepPurple.shade500, Colors.indigo.shade800];
        break;
      case StoreCategories.uniform:
        icon = Icons.checkroom_rounded;
        colors = [Colors.teal.shade500, Colors.cyan.shade800];
        break;
      case StoreCategories.stationery:
        icon = Icons.edit_note_rounded;
        colors = [Colors.orange.shade500, Colors.deepOrange.shade700];
        break;
      default:
        icon = Icons.card_giftcard_rounded;
        colors = [Colors.pink.shade500, Colors.purple.shade700];
        break;
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          icon,
          size: 46,
          color: Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}
