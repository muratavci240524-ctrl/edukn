import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/store/store_models.dart';
import '../../services/payment_gateway_service.dart';
import '../../services/store_service.dart';

/// Online Ödeme ve Sipariş Tamamlama Diyaloğu (iyzico güvenli ödeme sayfası):
/// 1) Teslimat Bilgileri (Okuldan Teslim / Adrese Kargo, Öğrenci & İletişim)
/// 2) Ödeme özeti -> iyzico barındırılan ödeme sayfası (kart bilgisi uygulamaya girmez)
/// 3) Ödeme bekleniyor -> Ödeme Onayı & Sipariş Fişi / Hata ekranı
class OnlinePaymentCheckoutDialog extends StatefulWidget {
  final StoreService storeService;
  final BuyerStoreContext buyerContext;
  final List<StoreCartItem> cartItems;
  final HqStoreSchoolAccess hqSettings;
  final SchoolStoreSettings schoolSettings;

  const OnlinePaymentCheckoutDialog({
    super.key,
    required this.storeService,
    required this.buyerContext,
    required this.cartItems,
    required this.hqSettings,
    required this.schoolSettings,
  });

  static Future<List<StoreOrder>?> show({
    required BuildContext context,
    required StoreService storeService,
    required BuyerStoreContext buyerContext,
    required List<StoreCartItem> cartItems,
    required HqStoreSchoolAccess hqSettings,
    required SchoolStoreSettings schoolSettings,
  }) {
    return showDialog<List<StoreOrder>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OnlinePaymentCheckoutDialog(
        storeService: storeService,
        buyerContext: buyerContext,
        cartItems: cartItems,
        hqSettings: hqSettings,
        schoolSettings: schoolSettings,
      ),
    );
  }

  @override
  State<OnlinePaymentCheckoutDialog> createState() =>
      _OnlinePaymentCheckoutDialogState();
}

class _OnlinePaymentCheckoutDialogState
    extends State<OnlinePaymentCheckoutDialog> {
  final NumberFormat _currencyFmt = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: '₺',
    decimalDigits: 2,
  );

  int _step = 0; // 0: Teslimat, 1: Kart Ödeme, 2: Başarılı Fiş
  bool _isProcessing = false;
  String? _errorMessage;

  // Step 0 controllers
  late String _deliveryType;
  late final TextEditingController _buyerNameCtrl;
  late final TextEditingController _buyerPhoneCtrl;
  late final TextEditingController _buyerEmailCtrl;
  late final TextEditingController _studentNameCtrl;
  late final TextEditingController _studentClassCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _noteCtrl;

  // Ödeme oturumu durumu
  bool _acceptedTerms = true;
  PaymentSession? _session;
  List<StoreOrder> _pendingOrders = const [];
  final Set<String> _paidOrderIds = {};
  String _currentPosStageLabel = '';
  String? _failMessage;

  // Step 2 result
  List<StoreOrder> _createdOrders = const [];

  bool get _hasHqItems => widget.cartItems.any((e) => e.product.isHq);
  bool get _hasSchoolItems => widget.cartItems.any((e) => e.product.isSchool);
  bool get _isSplitOrder => _hasHqItems && _hasSchoolItems;
  bool get _requiresSeparateSellerPos =>
      _isSplitOrder && widget.schoolSettings.usesCustomStorePos;

  List<StoreCartItem> get _pickupOnlyItems => widget.cartItems
      .where(
        (i) => i.product.allowPickupAtSchool && !i.product.allowHomeDelivery,
      )
      .toList();

  List<StoreCartItem> get _cargoOnlyItems => widget.cartItems
      .where(
        (i) => !i.product.allowPickupAtSchool && i.product.allowHomeDelivery,
      )
      .toList();

  bool get _strictPickupAllowed {
    final hqOk = !_hasHqItems || widget.hqSettings.allowPickupAtSchool;
    final schOk = !_hasSchoolItems || widget.schoolSettings.allowPickupAtSchool;
    return hqOk && schOk && _cargoOnlyItems.isEmpty;
  }

  bool get _strictHomeDeliveryAllowed {
    final hqOk = !_hasHqItems || widget.hqSettings.allowHomeDelivery;
    final schOk = !_hasSchoolItems || widget.schoolSettings.allowHomeDelivery;
    return hqOk && schOk && _pickupOnlyItems.isEmpty;
  }

  bool get _hasDeliveryConflictFallback =>
      !_strictPickupAllowed && !_strictHomeDeliveryAllowed;

  bool get _pickupAllowed => _strictPickupAllowed;

  bool get _homeDeliveryAllowed => _strictHomeDeliveryAllowed;

  bool get _needsShippingAddress =>
      _deliveryType == 'Adrese Kargo' || _deliveryType == 'Karma Teslimat';

  String _resolveSellerDeliveryType(List<StoreCartItem> sellerItems) {
    if (_deliveryType != 'Karma Teslimat') return _deliveryType;
    final allPickup = sellerItems.every(
      (i) => i.product.allowPickupAtSchool && !i.product.allowHomeDelivery,
    );
    if (allPickup) return 'Okuldan Teslim';
    final allCargo = sellerItems.every((i) => i.product.allowHomeDelivery);
    if (allCargo) return 'Adrese Kargo';
    return 'Karma Teslimat';
  }

  double get _hqSubtotal => widget.cartItems
      .where((i) => i.product.isHq)
      .fold<double>(0.0, (a, b) => a + b.lineTotal);

  double get _schoolSubtotal => widget.cartItems
      .where((i) => i.product.isSchool)
      .fold<double>(0.0, (a, b) => a + b.lineTotal);

  double get _subtotal => _hqSubtotal + _schoolSubtotal;

  double get _hqShipping {
    final hqItems = widget.cartItems.where((i) => i.product.isHq).toList();
    if (hqItems.isEmpty) return 0.0;
    final effType = _resolveSellerDeliveryType(hqItems);
    if (effType == 'Okuldan Teslim') return 0.0;
    final cargoSub = hqItems
        .where((i) => i.product.allowHomeDelivery)
        .fold<double>(0.0, (a, b) => a + b.lineTotal);
    return widget.storeService.calculateHqShipping(
      hqSubtotal: effType == 'Karma Teslimat' ? cargoSub : _hqSubtotal,
      deliveryType: 'Adrese Kargo',
      hqSettings: widget.hqSettings,
    );
  }

  double get _schoolShipping {
    final schItems = widget.cartItems.where((i) => i.product.isSchool).toList();
    if (schItems.isEmpty) return 0.0;
    final effType = _resolveSellerDeliveryType(schItems);
    if (effType == 'Okuldan Teslim') return 0.0;
    final cargoSub = schItems
        .where((i) => i.product.allowHomeDelivery)
        .fold<double>(0.0, (a, b) => a + b.lineTotal);
    return widget.storeService.calculateSchoolShipping(
      schoolSubtotal: effType == 'Karma Teslimat' ? cargoSub : _schoolSubtotal,
      deliveryType: 'Adrese Kargo',
      schoolSettings: widget.schoolSettings,
    );
  }

  double get _totalShipping => _hqShipping + _schoolShipping;
  double get _grandTotal => _subtotal + _totalShipping;

  @override
  void initState() {
    super.initState();
    _deliveryType = _strictPickupAllowed
        ? 'Okuldan Teslim'
        : (_strictHomeDeliveryAllowed ? 'Adrese Kargo' : 'Karma Teslimat');

    _buyerNameCtrl = TextEditingController(text: widget.buyerContext.fullName);
    _buyerPhoneCtrl = TextEditingController(text: widget.buyerContext.phone);
    _buyerEmailCtrl = TextEditingController(text: widget.buyerContext.email);
    _studentNameCtrl = TextEditingController(
      text: widget.buyerContext.studentName ?? '',
    );
    _studentClassCtrl = TextEditingController(
      text: widget.buyerContext.studentClass ?? '',
    );
    _addressCtrl = TextEditingController();
    _noteCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _buyerNameCtrl.dispose();
    _buyerPhoneCtrl.dispose();
    _buyerEmailCtrl.dispose();
    _studentNameCtrl.dispose();
    _studentClassCtrl.dispose();
    _addressCtrl.dispose();
    _noteCtrl.dispose();
    _session?.dispose();
    super.dispose();
  }

  bool _validateStep0() {
    if (_buyerNameCtrl.text.trim().length < 2) {
      setState(
        () => _errorMessage = 'Lütfen alıcı ad soyad bilgisini giriniz.',
      );
      return false;
    }
    final digitsPhone = _buyerPhoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (digitsPhone.length < 10) {
      setState(
        () => _errorMessage =
            'Lütfen geçerli bir cep telefonu numarası giriniz (en az 10 hane).',
      );
      return false;
    }
    if (_needsShippingAddress && _addressCtrl.text.trim().length < 10) {
      setState(
        () => _errorMessage =
            'Kargo ile gönderilecek ürünler için açık teslimat adresini giriniz.',
      );
      return false;
    }
    setState(() => _errorMessage = null);
    return true;
  }

  /// Ödeme adımı: önce siparişler "ödeme bekliyor" olarak oluşturulur (stok
  /// rezerve edilir), ardından iyzico'nun güvenli ödeme sayfası açılır.
  /// Okul Mağazası ayrı özel Sanal POS kullanıyorsa ve sepette hem Genel Merkez
  /// hem Okul ürünü varsa, her satıcının tahsilatı kendi POS hesabından sırayla alınır.
  Future<void> _startSecurePayment() async {
    if (!_acceptedTerms) {
      setState(
        () => _errorMessage =
            'Devam etmek için Ön Bilgilendirme ve Mesafeli Satış koşullarını onaylayınız.',
      );
      return;
    }
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    List<StoreOrder> orders = _pendingOrders;
    try {
      if (orders.isEmpty) {
        final hqItems = widget.cartItems.where((i) => i.product.isHq).toList();
        final schItems = widget.cartItems
            .where((i) => i.product.isSchool)
            .toList();
        final pickupTitles = _pickupOnlyItems
            .map((e) => e.product.title)
            .toSet()
            .join(', ');
        final baseNote = _noteCtrl.text.trim();
        final mergedNote =
            (_deliveryType == 'Karma Teslimat' && pickupTitles.isNotEmpty)
            ? [
                if (baseNote.isNotEmpty) baseNote,
                'Okuldan Teslim Edilecek Ürünler: $pickupTitles',
              ].join(' | ')
            : baseNote;

        orders = await widget.storeService.placeOnlineOrder(
          context: widget.buyerContext,
          cartItems: widget.cartItems,
          deliveryType: _deliveryType,
          hqDeliveryType: hqItems.isNotEmpty
              ? _resolveSellerDeliveryType(hqItems)
              : null,
          schoolDeliveryType: schItems.isNotEmpty
              ? _resolveSellerDeliveryType(schItems)
              : null,
          deliveryAddress: _deliveryType == 'Okuldan Teslim'
              ? '${widget.buyerContext.schoolName} — Okul Teslim Noktası'
              : _addressCtrl.text.trim(),
          buyerName: _buyerNameCtrl.text.trim(),
          buyerPhone: _buyerPhoneCtrl.text.trim(),
          buyerEmail: _buyerEmailCtrl.text.trim(),
          studentName: _studentNameCtrl.text.trim(),
          studentClass: _studentClassCtrl.text.trim(),
          orderNote: mergedNote,
          hqSettings: widget.hqSettings,
          schoolSettings: widget.schoolSettings,
        );
        _pendingOrders = orders;
      }

      if (!mounted) return;

      if (_requiresSeparateSellerPos && orders.length > 1) {
        await _runMultiPosSequentialCheckout(orders);
        return;
      }

      final singlePosChannel = _hasSchoolItems && !_hasHqItems
          ? 'store'
          : (_hasHqItems && !_hasSchoolItems ? 'hq_store' : null);
      final unpaidOrderIds = orders
          .where((o) => !_paidOrderIds.contains(o.id))
          .map((o) => o.id)
          .toList();

      final session = await PaymentGatewayService.instance.startCheckout(
        kind: 'store_order',
        institutionId: widget.buyerContext.institutionId,
        orderIds: unpaidOrderIds,
        posChannel: singlePosChannel,
      );
      if (!mounted) {
        session.dispose();
        return;
      }
      setState(() {
        _session = session;
        _currentPosStageLabel = '';
        _isProcessing = false;
        _step = 3;
      });
      final result = await session.result;
      if (!mounted) return;
      await _handlePaymentResult(result);
    } catch (e) {
      final unpaid = orders
          .where((o) => !_paidOrderIds.contains(o.id))
          .toList();
      await _cancelPendingOrders(unpaid, 'Ödeme başlatılamadı');
      _pendingOrders = orders
          .where((o) => _paidOrderIds.contains(o.id))
          .toList();
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _step = 1;
        _errorMessage = e is PaymentException
            ? e.message
            : 'Ödeme başlatılırken hata oluştu. Lütfen tekrar deneyin.';
      });
    }
  }

  Future<void> _runMultiPosSequentialCheckout(List<StoreOrder> orders) async {
    final stages = <MapEntry<StoreOrder, String>>[
      for (final o in orders)
        if (!_paidOrderIds.contains(o.id))
          MapEntry(o, o.isHqOrder ? 'hq_store' : 'store'),
    ];

    final totalStages = orders.length;
    for (var i = 0; i < stages.length; i++) {
      final order = stages[i].key;
      final channel = stages[i].value;
      final stepNum = _paidOrderIds.length + 1;
      final stageLabel = order.isHqOrder
          ? '$stepNum/$totalStages • Genel Merkez Mağazası POS Ödemesi (${_currencyFmt.format(order.totalAmount)})'
          : '$stepNum/$totalStages • ${widget.buyerContext.schoolName} Mağaza POS Ödemesi (${_currencyFmt.format(order.totalAmount)})';

      final session = await PaymentGatewayService.instance.startCheckout(
        kind: 'store_order',
        institutionId: widget.buyerContext.institutionId,
        orderIds: [order.id],
        posChannel: channel,
      );
      if (!mounted) {
        session.dispose();
        return;
      }
      setState(() {
        _session = session;
        _currentPosStageLabel = stageLabel;
        _isProcessing = false;
        _step = 3;
      });

      final result = await session.result;
      if (!mounted) return;
      if (!result.isSuccess) {
        if (result.outcome != PaymentOutcome.failed) {
          final unpaid = orders
              .where((o) => !_paidOrderIds.contains(o.id))
              .toList();
          await _cancelPendingOrders(
            unpaid,
            result.outcome == PaymentOutcome.timeout
                ? 'Ödeme süresi doldu'
                : 'Ödeme kullanıcı tarafından iptal edildi',
          );
        }
        _pendingOrders = orders
            .where((o) => _paidOrderIds.contains(o.id))
            .toList();
        setState(() {
          _createdOrders = List<StoreOrder>.from(_pendingOrders);
          _failMessage = _paidOrderIds.isNotEmpty
              ? 'İlk siparişinizin ödemesi alındı ancak 2. POS adımı (${order.sellerName}) tamamlanamadı: ${result.message ?? ''}'
              : (result.message ?? 'Ödeme tamamlanamadı.');
          _step = 4;
        });
        return;
      }
      _paidOrderIds.add(order.id);
    }

    if (!mounted) return;
    setState(() {
      _createdOrders = orders;
      _currentPosStageLabel = '';
      _step = 2;
    });
  }

  Future<void> _handlePaymentResult(PaymentResult result) async {
    if (result.isSuccess) {
      for (final o in _pendingOrders) {
        _paidOrderIds.add(o.id);
      }
      setState(() {
        _createdOrders = _pendingOrders;
        _step = 2;
      });
      return;
    }
    // 'failed' durumunda sunucu siparişleri zaten iptal edip stoğu iade etti.
    if (result.outcome != PaymentOutcome.failed) {
      final unpaid = _pendingOrders
          .where((o) => !_paidOrderIds.contains(o.id))
          .toList();
      await _cancelPendingOrders(
        unpaid,
        result.outcome == PaymentOutcome.timeout
            ? 'Ödeme süresi doldu'
            : 'Ödeme kullanıcı tarafından iptal edildi',
      );
    }
    if (!mounted) return;
    setState(() {
      _failMessage = result.message ?? 'Ödeme tamamlanamadı.';
      _step = 4;
    });
  }

  /// Beklemeyi iptal eder. Ödeme tam bu sırada tamamlandıysa başarı kabul edilir.
  Future<void> _cancelWaiting() async {
    final session = _session;
    if (session == null) return;
    setState(() => _isProcessing = true);
    final status = await session.currentStatus();
    if (!mounted) return;
    setState(() => _isProcessing = false);
    if (status == 'success') return; // dinleyici başarı sonucunu işleyecek
    session.cancel();
  }

  Future<void> _cancelPendingOrders(
    List<StoreOrder> orders,
    String reason,
  ) async {
    for (final o in orders) {
      try {
        await widget.storeService.cancelOrderByBuyer(
          orderId: o.id,
          cancelReason: reason,
        );
      } catch (_) {
        // Sunucu zaten iptal etmiş olabilir.
      }
    }
  }

  Widget _kvRow(String k, String v, {bool boldValue = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          flex: 2,
          child: Text(
            k,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          flex: 3,
          child: Text(
            v,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: boldValue ? FontWeight.w800 : FontWeight.w600,
              color: boldValue ? Colors.indigo.shade900 : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 780),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Divider(height: 1, color: Colors.grey.shade200),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildBodyForStep(),
              ),
            ),
            if (_step < 2) ...[
              Divider(height: 1, color: Colors.grey.shade200),
              _buildFooterActions(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final titles = [
      '1. Teslimat & Alıcı Bilgileri',
      '2. Güvenli Online Ödeme (iyzico)',
      'Ödeme Onaylandı',
      'Güvenli Ödeme Bekleniyor',
      'Ödeme Tamamlanamadı',
    ];
    final safeStep = _step.clamp(0, titles.length - 1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _step == 2
                  ? Colors.green.shade50
                  : (_step == 4 ? Colors.red.shade50 : Colors.indigo.shade50),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _step == 2
                  ? Icons.check_circle_rounded
                  : (_step == 4
                        ? Icons.error_outline_rounded
                        : (_step >= 1
                              ? Icons.verified_user_rounded
                              : Icons.local_shipping_outlined)),
              color: _step == 2
                  ? Colors.green.shade700
                  : (_step == 4 ? Colors.red.shade700 : Colors.indigo.shade700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titles[safeStep],
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.indigo.shade900,
                  ),
                ),
                Text(
                  'Toplam Tutar: ${_currencyFmt.format(_grandTotal)} • ${widget.cartItems.length} Kalem Ürün',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (!_isProcessing && _step != 2 && _step != 3)
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Kapat',
            ),
        ],
      ),
    );
  }

  Widget _buildBodyForStep() {
    if (_step == 0) return _buildStep0Delivery();
    if (_step == 1) return _buildStep1SecurePayment();
    if (_step == 3) return _buildStep3Waiting();
    if (_step == 4) return _buildStep4Failure();
    return _buildStep2Receipt();
  }

  Widget _buildStep0Delivery() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 480;

        final pickupCard = _deliveryOptionCard(
          value: 'Okuldan Teslim',
          icon: Icons.school_outlined,
          title: 'Okuldan Teslim',
          subtitle: _pickupAllowed
              ? 'Ücretsiz • Okul teslim noktası'
              : (_cargoOnlyItems.isNotEmpty
                    ? 'Kısıtlı: "${_cargoOnlyItems.first.product.title}" sadece kargo'
                    : 'Bu sipariş için kapalı'),
          enabled: _pickupAllowed,
        );
        final homeCard = _deliveryOptionCard(
          value: 'Adrese Kargo',
          icon: Icons.local_shipping_outlined,
          title: 'Adrese Kargo',
          subtitle: _homeDeliveryAllowed
              ? 'Belirttiğiniz adrese gönderim'
              : (_pickupOnlyItems.isNotEmpty
                    ? 'Kısıtlı: "${_pickupOnlyItems.first.product.title}" sadece okuldan teslim'
                    : 'Bu sipariş için kapalı'),
          enabled: _homeDeliveryAllowed,
        );
        final mixedCard = _deliveryOptionCard(
          value: 'Karma Teslimat',
          icon: Icons.alt_route_rounded,
          title: 'Karma Teslimat (Okuldan Teslim + Adrese Kargo)',
          subtitle:
              'Okuldan teslim ürünler okuldan, kargo ürünleri adresinize teslim edilir.',
          enabled: true,
        );

        final buyerNameField = TextField(
          controller: _buyerNameCtrl,
          decoration: _inputDeco(
            'Alıcı Ad Soyad *',
            Icons.person_outline_rounded,
          ),
        );
        final buyerPhoneField = TextField(
          controller: _buyerPhoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: _inputDeco('Cep Telefonu *', Icons.phone_outlined),
        );
        final studentNameField = TextField(
          controller: _studentNameCtrl,
          decoration: _inputDeco(
            'Öğrenci Ad Soyad (Opsiyonel)',
            Icons.badge_outlined,
          ),
        );
        final studentClassField = TextField(
          controller: _studentClassCtrl,
          decoration: _inputDeco(
            'Sınıf / Şube (Örn: 6-A)',
            Icons.class_outlined,
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isSplitOrder) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.indigo.shade100),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.call_split_rounded,
                      color: Colors.indigo.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _requiresSeparateSellerPos
                            ? 'Sepetinizde hem Genel Merkez hem de ${widget.buyerContext.schoolName} Mağazası ürünleri bulunuyor. Okul Mağazası kendi özel Sanal POS hesabını kullandığı için ödemeniz arka arkaya 2 adımda ilgili POS hesaplarına yönlendirilecektir.'
                            : 'Sepetinizde hem Genel Merkez hem de Okul Mağazası ürünleri bulunuyor. Tek seferde ödeme alınacak; Genel Merkez ürünleri doğrudan Genel Merkez Siparişlerine, Okul ürünleri ise ${widget.buyerContext.schoolName} siparişlerine ayrı ayrı yönlendirilecektir.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.indigo.shade900,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_hasDeliveryConflictFallback) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: Colors.amber.shade900,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Sepetinizde hem "Sadece Okuldan Teslim" hem de "Sadece Adrese Kargo" ürünler bulunduğu için Karma Teslimat otomatik seçilmiştir. Kargo kapsamındaki ürünler adresinize gönderilecek, okul teslim ürünleri okul teslim noktasından verilecektir.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.amber.shade900,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ] else if (!_pickupAllowed || !_homeDeliveryAllowed) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.local_shipping_outlined,
                      color: Colors.amber.shade900,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        !_pickupAllowed && _cargoOnlyItems.isNotEmpty
                            ? 'Sepetinizdeki "${_cargoOnlyItems.first.product.title}" ürünü yalnızca Adrese Kargo ile teslim edilebildiğinden Okuldan Teslim seçeneği kapatılmıştır.'
                            : (!_homeDeliveryAllowed &&
                                      _pickupOnlyItems.isNotEmpty
                                  ? 'Sepetinizdeki "${_pickupOnlyItems.first.product.title}" ürünü yalnızca Okuldan Teslim edilebildiğinden Adrese Kargo seçeneği kapatılmıştır.'
                                  : 'Mağaza teslimat ayarlarına göre uygun teslimat yöntemi otomatik seçilmiştir.'),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.amber.shade900,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            if (_errorMessage != null) ...[
              _buildErrorBanner(_errorMessage!),
              const SizedBox(height: 14),
            ],

            const Text(
              'Teslimat Yöntemi',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (_hasDeliveryConflictFallback)
              mixedCard
            else if (isNarrow) ...[
              pickupCard,
              const SizedBox(height: 10),
              homeCard,
            ] else
              Row(
                children: [
                  Expanded(child: pickupCard),
                  const SizedBox(width: 12),
                  Expanded(child: homeCard),
                ],
              ),
            const SizedBox(height: 18),

            const Text(
              'Alıcı & Öğrenci Bilgileri',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (isNarrow) ...[
              buyerNameField,
              const SizedBox(height: 12),
              buyerPhoneField,
              const SizedBox(height: 12),
              studentNameField,
              const SizedBox(height: 12),
              studentClassField,
            ] else ...[
              Row(
                children: [
                  Expanded(child: buyerNameField),
                  const SizedBox(width: 12),
                  Expanded(child: buyerPhoneField),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: studentNameField),
                  const SizedBox(width: 12),
                  Expanded(child: studentClassField),
                ],
              ),
            ],
            if (_needsShippingAddress) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _addressCtrl,
                maxLines: 2,
                decoration: _inputDeco(
                  'Açık Teslimat Adresi (Mahalle, Sokak, Bina/Daire, İlçe/İl) *',
                  Icons.location_on_outlined,
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              decoration: _inputDeco(
                'Sipariş Notu (Beden, teslimat notu vb. - Opsiyonel)',
                Icons.notes_rounded,
              ),
            ),
            const SizedBox(height: 18),
            _buildAmountSummaryBox(),
          ],
        );
      },
    );
  }

  Widget _deliveryOptionCard({
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
    bool enabled = true,
  }) {
    final selected = _deliveryType == value;
    return Opacity(
      opacity: enabled ? 1.0 : 0.55,
      child: InkWell(
        onTap: enabled ? () => setState(() => _deliveryType = value) : null,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? Colors.indigo.shade50.withValues(alpha: 0.65)
                : (enabled ? Colors.white : Colors.grey.shade100),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? Colors.indigo.shade600 : Colors.grey.shade300,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                enabled ? icon : Icons.lock_outline_rounded,
                color: selected ? Colors.indigo.shade700 : Colors.grey.shade600,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: selected
                            ? Colors.indigo.shade900
                            : Colors.black87,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep1SecurePayment() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_errorMessage != null) ...[
          _buildErrorBanner(_errorMessage!),
          const SizedBox(height: 14),
        ],
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.indigo.shade50.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.indigo.shade100),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_rounded, color: Colors.indigo.shade700),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ödeme, iyzico\'nun güvenli ödeme sayfasında alınır. Kart bilgileriniz eduKN\'e girilmez ve saklanmaz. Taksit seçenekleri ödeme sayfasında gösterilir.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.indigo.shade900,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...widget.cartItems.map(
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _kvRow(
              '${i.quantity} × ${i.product.title}',
              _currencyFmt.format(i.lineTotal),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _buildAmountSummaryBox(),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: _acceptedTerms,
          onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: const Text(
            'Ön Bilgilendirme Formu ve Mesafeli Satış Sözleşmesi\'ni okudum, onaylıyorum.',
            style: TextStyle(fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  Widget _buildStep3Waiting() {
    return Column(
      children: [
        const SizedBox(height: 8),
        const SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(height: 18),
        Text(
          _currentPosStageLabel.isNotEmpty
              ? _currentPosStageLabel
              : 'Ödeme bekleniyor...',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Colors.indigo.shade900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Açılan güvenli ödeme sayfasında ödemenizi tamamlayın. İşlem bitince bu ekran otomatik güncellenir. Sayfa açılmadıysa tarayıcınızın açılır pencere engelini kontrol edin.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: _isProcessing ? null : _cancelWaiting,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.close_rounded, size: 18),
          label: const Text('Vazgeç'),
        ),
      ],
    );
  }

  Widget _buildStep4Failure() {
    return Column(
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.error_outline_rounded,
            size: 46,
            color: Colors.red.shade600,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Ödeme Tamamlanamadı',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: Colors.indigo.shade900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${_failMessage ?? ''}\nSiparişiniz oluşturulmadı ve ürünler sepetinizde kaldı. Kartınızdan tahsilat yapıldıysa lütfen okul yönetimiyle iletişime geçin.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.indigo.shade700,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Kapat'),
          ),
        ),
      ],
    );
  }

  Widget _buildStep2Receipt() {
    return Column(
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_circle_rounded,
            size: 46,
            color: Colors.green.shade600,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Ödemeniz Başarıyla Tamamlandı!',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: Colors.indigo.shade900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _createdOrders.length > 1
              ? 'Sepetinizdeki ürünler satıcılarına göre ${_createdOrders.length} ayrı sipariş olarak oluşturuldu.'
              : 'Siparişiniz başarıyla oluşturuldu ve ilgili birime iletildi.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 18),
        ..._createdOrders.map((order) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: order.isHqOrder
                            ? Colors.deepPurple.shade50
                            : Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        order.isHqOrder
                            ? '🏛️ Genel Merkez Siparişi'
                            : '🏫 Okul Mağazası Siparişi',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: order.isHqOrder
                              ? Colors.deepPurple.shade800
                              : Colors.teal.shade800,
                        ),
                      ),
                    ),
                    const Spacer(),
                    SelectableText(
                      order.orderNo,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _kvRow('Satıcı Birim', order.sellerName),
                const SizedBox(height: 4),
                _kvRow('Ödeme Referansı', order.paymentRef),
                const SizedBox(height: 4),
                _kvRow(
                  'Kart / Taksit',
                  '${order.cardMasked} • ${order.installmentCount == 1 ? 'Tek Çekim' : '${order.installmentCount} Taksit'}',
                ),
                const SizedBox(height: 4),
                _kvRow(
                  'Sipariş Tutarı',
                  _currencyFmt.format(order.totalAmount),
                  boldValue: true,
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => Navigator.pop(context, _createdOrders),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.indigo.shade700,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.receipt_long_rounded),
            label: const Text('Siparişlerim Sekmesine Git'),
          ),
        ),
      ],
    );
  }

  Widget _buildAmountSummaryBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          if (_hasHqItems)
            _kvRow(
              'Genel Merkez Ürünleri Ara Toplam',
              _currencyFmt.format(_hqSubtotal),
            ),
          if (_hasHqItems && _hasSchoolItems) const SizedBox(height: 4),
          if (_hasSchoolItems)
            _kvRow(
              'Okul Mağazası Ürünleri Ara Toplam',
              _currencyFmt.format(_schoolSubtotal),
            ),
          const SizedBox(height: 6),
          _kvRow(
            'Kargo / Teslimat Ücreti',
            _totalShipping == 0
                ? 'Ücretsiz'
                : _currencyFmt.format(_totalShipping),
          ),
          const Divider(height: 16),
          _kvRow(
            'Ödenecek Genel Toplam',
            _currencyFmt.format(_grandTotal),
            boldValue: true,
          ),
        ],
      ),
    );
  }

  Widget _buildFooterActions() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 520;

        final Widget secondaryAction = _step == 1
            ? OutlinedButton.icon(
                onPressed: _isProcessing
                    ? null
                    : () => setState(() => _step = 0),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Teslimat Bilgileri'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              )
            : TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('İptal'),
              );

        final Widget primaryAction = _step == 0
            ? FilledButton.icon(
                onPressed: () {
                  if (_validateStep0()) {
                    setState(() => _step = 1);
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.indigo.shade700,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('Kart ile Ödemeye Geç'),
              )
            : FilledButton.icon(
                onPressed: _isProcessing ? null : _startSecurePayment,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _isProcessing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(
                  _isProcessing
                      ? 'İşleniyor...'
                      : (isCompact
                            ? 'Güvenli Ödeme (${_currencyFmt.format(_grandTotal)})'
                            : 'Güvenli Ödeme Sayfasına Git (${_currencyFmt.format(_grandTotal)})'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: isCompact
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    primaryAction,
                    const SizedBox(height: 8),
                    secondaryAction,
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    secondaryAction,
                    const SizedBox(width: 12),
                    Flexible(child: primaryAction),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12.5, color: Colors.red.shade900),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) {
    OutlineInputBorder b(Color c, [double w = 1.1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: w),
    );
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 19, color: Colors.indigo.shade600),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: b(const Color(0xFFCBD5E1)),
      enabledBorder: b(const Color(0xFFCBD5E1)),
      focusedBorder: b(Colors.indigo.shade600, 1.8),
    );
  }
}
