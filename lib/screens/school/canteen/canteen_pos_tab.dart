import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../models/canteen/canteen_models.dart';
import '../../../services/canteen_service.dart';
import '../../../widgets/school_pos_settings_dialog.dart';
import 'canteen_common.dart';

/// Satış (POS) sekmesi — KantiN Studio.
class CanteenPosTab extends StatefulWidget {
  final String institutionId;
  const CanteenPosTab({super.key, required this.institutionId});

  @override
  State<CanteenPosTab> createState() => _CanteenPosTabState();
}

class _CanteenPosTabState extends State<CanteenPosTab>
    with AutomaticKeepAliveClientMixin {
  final CanteenService _svc = CanteenService.instance;

  StreamSubscription<List<CanteenProduct>>? _sub;
  StreamSubscription<List<CanteenCard>>? _cardsSub;

  List<CanteenProduct> _products = const [];
  Map<String, CanteenProduct> _byId = const {};
  List<CanteenCard> _cards = const [];

  bool _loading = true;
  String? _error;

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _barcodeCtrl = TextEditingController();
  final TextEditingController _cardCtrl = TextEditingController();
  final TextEditingController _posNoteCtrl = TextEditingController();
  final FocusNode _barcodeFocus = FocusNode();

  String _category = '';
  final Map<String, int> _cart = {};
  String _method = 'card';

  CanteenCard? _card;
  double _spentToday = 0;
  bool _lookingUp = false;
  String? _cardError;
  bool _selling = false;

  // Canlı Mobil / QR kasa oturumu durumu
  CanteenQrSession? _qrSession;
  StreamSubscription<CanteenQrSession?>? _qrSub;
  Timer? _qrDebounce;
  bool _qrCreating = false;
  String? _qrError;
  String _qrSignature = '';
  int _qrGenSeq = 0;
  VoidCallback? _closeLargeQrDialog;
  final Set<String> _handledPaidQrIds = <String>{};

  StateSetter? _sheetSetState;

  String get _inst => widget.institutionId.trim();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant CanteenPosTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.institutionId != widget.institutionId) {
      _cancelPendingQr();
      _cart.clear();
      _card = null;
      _spentToday = 0;
      _subscribe();
    }
  }

  void _subscribe() {
    _sub?.cancel();
    _cardsSub?.cancel();
    _sub = null;
    _cardsSub = null;
    if (_inst.isEmpty) {
      _loading = false;
      _error = 'Kurum bilgisi bulunamadı.';
      return;
    }
    _loading = true;
    _error = null;
    _sub = _svc
        .watchProducts(_inst)
        .listen(
          (list) {
            if (!mounted) return;
            setState(() {
              _products = list;
              _byId = {for (final p in list) p.id: p};
              _loading = false;
              _error = null;
              _cart.removeWhere((id, _) => !_byId.containsKey(id));
            });
            _sheetSetState?.call(() {});
          },
          onError: (Object e) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _error = cnErr(e);
            });
          },
        );

    _cardsSub = _svc.watchCards(_inst).listen((list) {
      if (!mounted) return;
      setState(() {
        _cards = list;
        final cur = _card;
        if (cur != null) {
          for (final c in list) {
            if (c.cardNo == cur.cardNo) {
              _card = c;
              break;
            }
          }
        }
      });
      _sheetSetState?.call(() {});
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _qrDebounce?.cancel();
    _qrSub?.cancel();
    final prevQr = _qrSession;
    if (prevQr != null && prevQr.isPending) {
      unawaited(_svc.cancelQrSession(prevQr.id));
    }
    _sub?.cancel();
    _cardsSub?.cancel();
    _searchCtrl.dispose();
    _barcodeCtrl.dispose();
    _cardCtrl.dispose();
    _posNoteCtrl.dispose();
    _barcodeFocus.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (!mounted) return;
    setState(() {});
    _sheetSetState?.call(() {});
  }

  // ── Canlı Mobil / QR Oturum Yönetimi ─────────────────────────────────────

  String get _currentCartSignature {
    if (_cart.isEmpty) return '';
    final keys = _cart.keys.toList()..sort();
    return keys
        .map((id) => '$id:${_cart[id]}:${_byId[id]?.price ?? 0}')
        .join('|');
  }

  void _cancelPendingQr({bool clearState = true}) {
    _qrDebounce?.cancel();
    _qrSub?.cancel();
    _qrSub = null;
    _qrGenSeq++;
    final prev = _qrSession;
    if (prev != null && prev.isPending) {
      unawaited(_svc.cancelQrSession(prev.id));
    }
    _closeLargeQrDialog?.call();
    _closeLargeQrDialog = null;
    if (clearState) {
      _qrSession = null;
      _qrSignature = '';
      _qrCreating = false;
      _qrError = null;
    }
  }

  void _scheduleQrSync({bool immediate = false}) {
    if (_method != 'qr') return;
    if (_cart.isEmpty) {
      if (_qrSession != null || _qrCreating || _qrError != null) {
        _cancelPendingQr();
        _rebuild();
      }
      return;
    }
    final sig = _currentCartSignature;
    if (!immediate &&
        _qrSession != null &&
        _qrSession!.isPending &&
        !_qrSession!.isExpired &&
        _qrSignature == sig) {
      return;
    }
    _qrDebounce?.cancel();
    if (immediate) {
      unawaited(_generateQrSession());
    } else {
      _qrDebounce = Timer(const Duration(milliseconds: 320), () {
        if (mounted && _method == 'qr' && _cart.isNotEmpty) {
          unawaited(_generateQrSession());
        }
      });
    }
  }

  Future<void> _generateQrSession() async {
    if (_inst.isEmpty || _cart.isEmpty || _method != 'qr') return;
    final sig = _currentCartSignature;
    final seq = ++_qrGenSeq;

    final prev = _qrSession;
    _qrSub?.cancel();
    _qrSub = null;
    if (prev != null && prev.isPending) {
      unawaited(_svc.cancelQrSession(prev.id));
    }

    _qrCreating = true;
    _qrError = null;
    _rebuild();

    final lines = <CartLine>[
      for (final e in _cart.entries)
        CartLine(
          productId: e.key,
          qty: e.value,
          name: _byId[e.key]?.name ?? '',
          price: _byId[e.key]?.price ?? 0,
        ),
    ];

    try {
      final session = await _svc.createQrSession(
        instId: _inst,
        lines: lines,
        cashierId: FirebaseAuth.instance.currentUser?.uid ?? '',
      );
      if (!mounted || seq != _qrGenSeq || _method != 'qr') {
        unawaited(_svc.cancelQrSession(session.id));
        return;
      }
      _qrSession = session;
      _qrSignature = sig;
      _qrCreating = false;
      _qrError = null;
      _rebuild();

      _qrSub = _svc.watchQrSession(session.id).listen((live) {
        if (!mounted || live == null) return;
        if (live.isPaid && _handledPaidQrIds.add(live.id)) {
          _onQrSessionPaid(live);
          return;
        }
        _qrSession = live;
        _rebuild();
      });
    } catch (e) {
      if (!mounted || seq != _qrGenSeq) return;
      _qrSession = null;
      _qrCreating = false;
      _qrError = cnErr(e);
      _rebuild();
    }
  }

  Future<void> _onQrSessionPaid(CanteenQrSession paid) async {
    _qrSub?.cancel();
    _qrSub = null;
    _closeLargeQrDialog?.call();
    _closeLargeQrDialog = null;

    setState(() {
      _cart.clear();
      _qrSession = null;
      _qrSignature = '';
      _qrCreating = false;
      _qrError = null;
    });
    _sheetSetState?.call(() {});

    final res = SaleResult(
      transactionId: paid.transactionId.isEmpty ? paid.id : paid.transactionId,
      total: paid.total,
      balanceAfter: paid.balanceAfter,
      cardNo: paid.cardNo.isEmpty ? null : paid.cardNo,
      items: paid.items,
    );
    final syntheticCard = (paid.payerName.isNotEmpty || paid.cardNo.isNotEmpty)
        ? CanteenCard(
            cardNo: paid.cardNo.isEmpty
                ? (paid.payVia == 'online_card' ? 'Sanal POS' : 'Mobil QR')
                : paid.cardNo,
            institutionId: paid.institutionId,
            studentName: paid.payerName.isEmpty
                ? 'Mobil QR Müşterisi'
                : '${paid.payerName}${paid.payerRole.isEmpty ? '' : ' (${paid.payerRole})'}',
            balance: paid.balanceAfter ?? 0,
          )
        : null;
    await _showReceiptModal(res, syntheticCard, 'qr');
  }

  // ── Sepet İşlemleri ──────────────────────────────────────────────────────

  void _add(CanteenProduct p) {
    final cur = _cart[p.id] ?? 0;
    if (cur + 1 > p.stock) {
      cnSnack(
        context,
        '"${p.name}" için yeterli stok yok (Kalan: ${p.stock}).',
        error: true,
      );
      return;
    }
    _cart[p.id] = cur + 1;
    _rebuild();
    _scheduleQrSync();
  }

  void _dec(String id) {
    final cur = _cart[id] ?? 0;
    if (cur <= 1) {
      _cart.remove(id);
    } else {
      _cart[id] = cur - 1;
    }
    _rebuild();
    _scheduleQrSync();
  }

  void _remove(String id) {
    _cart.remove(id);
    _rebuild();
    _scheduleQrSync();
  }

  double get _total {
    double t = 0;
    _cart.forEach((id, q) {
      final p = _byId[id];
      if (p != null) t += p.price * q;
    });
    return t;
  }

  int get _itemCount => _cart.values.fold(0, (a, b) => a + b);

  void _onBarcode(String v) {
    final code = v.trim();
    if (code.isEmpty) return;
    CanteenProduct? found;
    for (final p in _products) {
      if (p.isActive && p.barcode.isNotEmpty && p.barcode == code) {
        found = p;
        break;
      }
    }
    if (found == null) {
      cnSnack(context, 'Barkod eşleşmedi: $code', error: true);
    } else if (found.stock <= 0) {
      cnSnack(context, '"${found.name}" tükendi.', error: true);
    } else {
      _add(found);
    }
    _barcodeCtrl.clear();
    _barcodeFocus.requestFocus();
  }

  // ── Kart & Öğrenci Seçimi ────────────────────────────────────────────────

  List<CanteenCard> get _cardSuggestions {
    if (_card != null) return const [];
    final q = _cardCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _cards
        .where(
          (c) =>
              c.studentName.toLowerCase().contains(q) ||
              c.cardNo.toLowerCase().contains(q) ||
              c.className.toLowerCase().contains(q),
        )
        .take(5)
        .toList();
  }

  Future<void> _selectCard(CanteenCard c) async {
    setState(() {
      _card = c;
      _cardError = null;
      _lookingUp = true;
      _cardCtrl.clear();
    });
    _sheetSetState?.call(() {});
    try {
      final spent = await _svc.todaySpent(_inst, c.cardNo);
      if (!mounted) return;
      setState(() {
        _spentToday = spent;
        _lookingUp = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _lookingUp = false);
    }
    _sheetSetState?.call(() {});
  }

  Future<void> _lookupCard() async {
    final q = _cardCtrl.text.trim();
    if (q.isEmpty || _lookingUp || _inst.isEmpty) return;
    setState(() {
      _lookingUp = true;
      _cardError = null;
    });
    _sheetSetState?.call(() {});
    try {
      var c = await _svc.findCard(_inst, q);
      if (c == null) {
        final lq = q.toLowerCase();
        for (final item in _cards) {
          if (item.studentName.toLowerCase() == lq ||
              item.cardNo.toLowerCase() == lq) {
            c = item;
            break;
          }
        }
        c ??= _cardSuggestions.length == 1 ? _cardSuggestions.first : null;
      }
      double spent = 0;
      if (c != null) spent = await _svc.todaySpent(_inst, c.cardNo);
      if (!mounted) return;
      setState(() {
        _card = c;
        _spentToday = spent;
        _cardError = c == null ? 'Kart veya öğrenci bulunamadı.' : null;
        _lookingUp = false;
        if (c != null) _cardCtrl.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _card = null;
        _cardError = cnErr(e);
        _lookingUp = false;
      });
    }
    _sheetSetState?.call(() {});
  }

  // ── Satış Tamamlama ──────────────────────────────────────────────────────

  Future<void> _sell() async {
    if (_cart.isEmpty || _selling || _inst.isEmpty) return;
    if (_method == 'qr') {
      if (_qrSession != null &&
          _qrSession!.isPending &&
          !_qrSession!.isExpired) {
        await _showLargeQrDialog(_qrSession!);
      } else {
        await _generateQrSession();
      }
      return;
    }
    if (_method == 'card' && _card == null) {
      cnSnack(
        context,
        'Kartlı ödeme için önce kantin kartını seçin veya okutun.',
        error: true,
      );
      return;
    }
    final lines = <CartLine>[
      for (final e in _cart.entries)
        CartLine(
          productId: e.key,
          qty: e.value,
          name: _byId[e.key]?.name ?? '',
          price: _byId[e.key]?.price ?? 0,
        ),
    ];
    setState(() => _selling = true);
    _sheetSetState?.call(() {});
    try {
      final isCardless = _method == 'cash' || _method == 'pos';
      final res = await _svc.sell(
        instId: _inst,
        cardNo: isCardless ? null : _card?.cardNo,
        lines: lines,
        method: _method,
        cashierId: FirebaseAuth.instance.currentUser?.uid ?? '',
        note: _method == 'pos' ? _posNoteCtrl.text.trim() : null,
      );
      if (!mounted) return;
      final soldCard = isCardless ? null : _card;
      final methodUsed = _method;
      setState(() {
        _cart.clear();
        _posNoteCtrl.clear();
        _selling = false;
      });
      _sheetSetState?.call(() {});
      await _showReceiptModal(res, soldCard, methodUsed);
      if (_card != null && !isCardless) {
        await _selectCard(_card!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _selling = false);
      _sheetSetState?.call(() {});
      await showDialog<void>(
        context: context,
        builder: (ctx) => CnDialogShell(
          title: 'Satış Tamamlanamadı',
          subtitle: 'Lütfen aşağıdaki uyarıyı kontrol edin',
          icon: Icons.error_outline_rounded,
          iconColor: Colors.red.shade600,
          maxWidth: 440,
          showCancel: false,
          primaryLabel: 'Anladım',
          onPrimary: () => Navigator.pop(ctx),
          child: Text(
            cnErr(e),
            style: const TextStyle(
              fontSize: 14,
              color: CnColors.slate,
              height: 1.45,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _showReceiptModal(
    SaleResult res,
    CanteenCard? soldCard,
    String methodUsed,
  ) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => CnDialogShell(
        title: 'Satış Başarıyla Tamamlandı',
        subtitle:
            'İşlem No: #${res.transactionId.substring(0, res.transactionId.length.clamp(0, 8)).toUpperCase()}',
        icon: Icons.check_circle_rounded,
        iconColor: CnColors.ok,
        maxWidth: 460,
        showCancel: false,
        primaryLabel: 'Yeni Satışa Dön',
        primaryIcon: Icons.done_all_rounded,
        primaryColor: CnColors.okDark,
        onPrimary: () => Navigator.pop(ctx),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Özet kutusu
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: CnColors.okSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: CnColors.ok.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TAHSİL EDİLEN TUTAR',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: CnColors.okDark,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          cnMoney(res.total),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: CnColors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                  CnBadge(
                    cnMethodLabel(methodUsed),
                    color: CnColors.okDark,
                    icon: cnMethodIcon(methodUsed),
                  ),
                ],
              ),
            ),
            if (soldCard != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CnColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: CnColors.border),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: CnColors.pinkBg,
                      child: Text(
                        cnInitials(soldCard.studentName),
                        style: const TextStyle(
                          color: CnColors.brand,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            soldCard.studentName.isEmpty
                                ? soldCard.cardNo
                                : soldCard.studentName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: CnColors.text,
                            ),
                          ),
                          Text(
                            'Kart: ${soldCard.cardNo}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: CnColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (res.balanceAfter != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Kalan Bakiye',
                            style: TextStyle(
                              fontSize: 11,
                              color: CnColors.muted,
                            ),
                          ),
                          Text(
                            cnMoney(res.balanceAfter!),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: CnColors.brand,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            const CnSectionLabel(
              'SATILAN ÜRÜNLER',
              icon: Icons.receipt_outlined,
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: CnColors.border),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < res.items.length; i++) ...[
                    if (i > 0) const Divider(height: 14),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: CnColors.pinkBg,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            '${res.items[i].qty}x',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: CnColors.brand,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            res.items[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: CnColors.text,
                            ),
                          ),
                        ),
                        Text(
                          cnMoney(res.items[i].total),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: CnColors.text,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Filtreleme ───────────────────────────────────────────────────────────

  List<String> get _categories {
    final s = <String>{
      for (final p in _products)
        if (p.isActive && p.category.trim().isNotEmpty) p.category.trim(),
    }.toList()..sort();
    return s;
  }

  List<CanteenProduct> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _products.where((p) {
      if (!p.isActive) return false;
      if (_category.isNotEmpty && p.category.trim() != _category) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q) ||
          p.barcode.toLowerCase().contains(q);
    }).toList();
  }

  // ── Ana Görünüm ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 960;
        if (wide) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _productsArea()),
                const SizedBox(width: 16),
                SizedBox(
                  width: 390,
                  child: CnPanel(
                    padding: const EdgeInsets.all(16),
                    child: _receiptDock(),
                  ),
                ),
              ],
            ),
          );
        }
        return Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: _productsArea(),
              ),
            ),
            _mobileSummaryBar(),
          ],
        );
      },
    );
  }

  Widget _mobileSummaryBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: CnColors.border)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: CnColors.pinkBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CnColors.pink),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.shopping_bag_outlined,
                    color: CnColors.brand,
                    size: 21,
                  ),
                  if (_itemCount > 0)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: CnColors.brand,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$_itemCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _itemCount == 0 ? 'Sepet Boş' : '$_itemCount ürün seçildi',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: CnColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    cnMoney(_total),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: CnColors.text,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: cnPrimaryBtn(),
              onPressed: _openMobileDockSheet,
              icon: const Icon(Icons.point_of_sale_rounded, size: 18),
              label: const Text('Ödeme & Sepet'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMobileDockSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setS) {
            _sheetSetState = setS;
            final mq = MediaQuery.of(ctx);
            return Padding(
              padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
              child: SizedBox(
                height: (mq.size.height * 0.88).clamp(320.0, 780.0),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: CnColors.borderStrong,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _receiptDock(),
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
    _sheetSetState = null;
  }

  // ── Sol Bölüm: Komut Çubuğu + Ürün Izgarası ─────────────────────────────

  Widget _productsArea() {
    final cats = _categories;
    final list = _filtered;

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
                  final barcodeField = TextField(
                    controller: _barcodeCtrl,
                    focusNode: _barcodeFocus,
                    decoration: cnInput(
                      'Barkod Okutun (Enter)',
                      hint: '869...',
                      prefix: const Icon(
                        Icons.qr_code_scanner_rounded,
                        size: 20,
                        color: CnColors.brand,
                      ),
                    ),
                    onSubmitted: _onBarcode,
                  );
                  final searchField = TextField(
                    controller: _searchCtrl,
                    decoration: cnInput(
                      'Ürün veya kategori ara...',
                      prefix: const Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: CnColors.muted,
                      ),
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

                  if (c.maxWidth < 540) {
                    return Column(
                      children: [
                        barcodeField,
                        const SizedBox(height: 8),
                        searchField,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(flex: 2, child: barcodeField),
                      const SizedBox(width: 10),
                      Expanded(flex: 3, child: searchField),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _categoryChip(
                      label:
                          'Tümü (${_products.where((p) => p.isActive).length})',
                      icon: Icons.grid_view_rounded,
                      selected: _category.isEmpty,
                      onTap: () => setState(() => _category = ''),
                    ),
                    for (final c in cats)
                      _categoryChip(
                        label: c,
                        icon: cnCategoryIcon(c),
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
        Expanded(child: _buildProductGrid(list)),
      ],
    );
  }

  Widget _categoryChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? CnColors.brand : CnColors.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? CnColors.brand : CnColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? Colors.white : cnCategoryColor(label),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : CnColors.slate,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductGrid(List<CanteenProduct> list) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: CnColors.brand),
      );
    }
    if (_error != null) {
      return CnError(_error!, onRetry: _subscribe);
    }
    if (list.isEmpty) {
      return const CnEmpty(
        'Satışa uygun ürün bulunamadı.',
        subtitle:
            'Stok sekmesinden yeni ürün ekleyebilir veya arama filtresini temizleyebilirsiniz.',
        icon: Icons.storefront_outlined,
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: list.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 205,
        mainAxisExtent: 204,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, i) => _productCard(list[i]),
    );
  }

  Widget _productCard(CanteenProduct p) {
    final out = p.stock <= 0;
    final inCart = _cart[p.id] ?? 0;
    final stockColor = out
        ? Colors.red.shade700
        : (p.isLowStock ? CnColors.warnDark : CnColors.slate);
    final stockBg = out
        ? const Color(0xFFFEE2E2)
        : (p.isLowStock
              ? CnColors.warnSoft
              : Colors.white.withValues(alpha: 0.92));
    final stockLabel = out
        ? 'Tükendi'
        : (p.isLowStock ? 'Az: ${p.stock}' : 'Stok: ${p.stock}');

    return Material(
      color: out ? const Color(0xFFF8FAFC) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: out ? null : () => _add(p),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: inCart > 0 ? CnColors.brand : CnColors.border,
              width: inCart > 0 ? 1.8 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: (inCart > 0 ? CnColors.brand : const Color(0xFF0F172A))
                    .withValues(alpha: inCart > 0 ? 0.10 : 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Görsel + Stok rozeti + Sepet adedi rozeti
              SizedBox(
                height: 92,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: out ? 0.45 : 1.0,
                      child: CnProductAvatar(
                        imageUrl: p.imageUrl,
                        category: p.category,
                        width: double.infinity,
                        height: 92,
                        radius: 13,
                      ),
                    ),
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: stockBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: stockColor.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Text(
                          stockLabel,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: stockColor,
                          ),
                        ),
                      ),
                    ),
                    if (inCart > 0)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            gradient: CnColors.gradient,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: [
                              BoxShadow(
                                color: CnColors.brand.withValues(alpha: 0.35),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Text(
                            '×$inCart',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (p.category.trim().isNotEmpty)
                Text(
                  p.category.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: cnCategoryColor(p.category),
                  ),
                ),
              Expanded(
                child: Text(
                  p.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    height: 1.2,
                    color: out ? CnColors.muted : CnColors.text,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: out ? CnColors.surfaceAlt : CnColors.pinkBg,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        cnMoney(p.price),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                          color: out ? CnColors.muted : CnColors.brand,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: out ? CnColors.border : CnColors.brand,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.add_rounded,
                      size: 17,
                      color: out ? CnColors.muted : Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sağ Bölüm: Fiş & Ödeme İskelesi ──────────────────────────────────────

  Widget _receiptDock() {
    final ids = _cart.keys.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Üst başlık
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: CnColors.pinkBg,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                color: CnColors.brand,
                size: 19,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Satış Fişi & Ödeme',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: CnColors.text,
                    ),
                  ),
                  Text(
                    _itemCount == 0
                        ? 'Ürün eklemek için tıklayın'
                        : '$_itemCount adet ürün sepette',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: CnColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (_cart.isNotEmpty)
              TextButton.icon(
                style: cnTextBtn(),
                onPressed: () {
                  _cancelPendingQr();
                  _cart.clear();
                  _rebuild();
                },
                icon: const Icon(Icons.delete_sweep_outlined, size: 17),
                label: const Text('Temizle'),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // 4 Ödeme Yöntemi Kartı (Kartla • Mobil/QR • POS • Nakit)
        _paymentModeCards(),
        const SizedBox(height: 10),

        // Yönteme Göre Üst Ödeme Bölümü
        if (_method == 'card') ...[
          _cardSelectorSection(),
          const SizedBox(height: 10),
        ] else if (_method == 'qr') ...[
          _qrGeneratorSection(),
          const SizedBox(height: 10),
        ] else if (_method == 'pos') ...[
          _posTerminalSection(),
          const SizedBox(height: 10),
        ],

        const Divider(height: 1, color: CnColors.border),
        const SizedBox(height: 8),

        // Sepet Satırları
        Expanded(
          child: ids.isEmpty
              ? const CnEmpty(
                  'Sepet henüz boş',
                  subtitle: 'Soldaki katalogdan ürün seçin veya barkod okutun.',
                  icon: Icons.shopping_basket_outlined,
                )
              : ListView.separated(
                  itemCount: ids.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 10, color: Color(0xFFF1F5F9)),
                  itemBuilder: (context, i) {
                    final id = ids[i];
                    final p = _byId[id];
                    if (p == null) return const SizedBox.shrink();
                    final q = _cart[id] ?? 0;
                    return _cartLineTile(p, q);
                  },
                ),
        ),

        const SizedBox(height: 8),
        // Toplam & Satışı Tamamla
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: CnColors.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: CnColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Genel Toplam ($_itemCount ürün)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: CnColors.slate,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    cnMoney(_total),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      color: CnColors.brand,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: cnPrimaryBtn(
                  backgroundColor: _method == 'pos'
                      ? const Color(0xFF0284C7)
                      : CnColors.brand,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
                onPressed: (_cart.isEmpty || _selling || _qrCreating)
                    ? null
                    : _sell,
                icon: (_selling || _qrCreating)
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _method == 'qr'
                            ? (_qrSession != null
                                  ? Icons.fullscreen_rounded
                                  : Icons.qr_code_2_rounded)
                            : (_method == 'pos'
                                  ? Icons.credit_card_rounded
                                  : Icons.check_circle_outline_rounded),
                        size: 20,
                      ),
                label: Text(
                  _selling
                      ? 'İşlem Yapılıyor...'
                      : (_method == 'qr'
                            ? (_qrCreating
                                  ? 'Karekod Üretiliyor...'
                                  : (_qrSession != null
                                        ? 'Karekodu Tam Ekran Göster'
                                        : 'Ödeme Karekodu Üret'))
                            : (_method == 'pos'
                                  ? 'POS Tahsilatını Tamamla'
                                  : 'Satışı Tamamla')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cartLineTile(CanteenProduct p, int q) {
    return Row(
      children: [
        CnProductAvatar(
          imageUrl: p.imageUrl,
          category: p.category,
          width: 38,
          height: 38,
          radius: 9,
        ),
        const SizedBox(width: 9),
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
                  fontSize: 13,
                  color: CnColors.text,
                ),
              ),
              Text(
                '${cnMoney(p.price)} × $q = ${cnMoney(p.price * q)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: CnColors.muted,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: CnColors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: CnColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _stepperBtn(Icons.remove_rounded, () => _dec(p.id)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '$q',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: CnColors.text,
                  ),
                ),
              ),
              _stepperBtn(Icons.add_rounded, () => _add(p)),
            ],
          ),
        ),
        const SizedBox(width: 4),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _remove(p.id),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(
              Icons.close_rounded,
              size: 17,
              color: Colors.red.shade400,
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepperBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(icon, size: 16, color: CnColors.brand),
      ),
    );
  }

  Widget _paymentModeCards() {
    Widget modeCard(String key, String label, IconData icon) {
      final sel = _method == key;
      final activeColor = key == 'pos'
          ? const Color(0xFF0284C7)
          : CnColors.brand;
      final activeBg = key == 'pos' ? const Color(0xFFE0F2FE) : CnColors.pinkBg;
      return Expanded(
        child: Material(
          color: sel ? activeBg : CnColors.surfaceAlt,
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: () {
              if (_method == key) return;
              final wasQr = _method == 'qr';
              _method = key;
              if (wasQr && key != 'qr') {
                _cancelPendingQr();
              } else if (key == 'qr') {
                _scheduleQrSync(immediate: true);
              }
              _rebuild();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: sel ? activeColor : CnColors.border,
                  width: sel ? 1.6 : 1.0,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 19,
                    color: sel ? activeColor : CnColors.slate,
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                        color: sel ? activeColor : CnColors.slate,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        modeCard('card', 'Kartla', Icons.contactless_rounded),
        const SizedBox(width: 6),
        modeCard('qr', 'Mobil / QR', Icons.qr_code_2_rounded),
        const SizedBox(width: 6),
        modeCard('pos', 'POS', Icons.credit_card_rounded),
        const SizedBox(width: 6),
        modeCard('cash', 'Nakit', Icons.payments_outlined),
      ],
    );
  }

  Widget _qrGeneratorSection() {
    if (_cart.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: CnColors.pinkBg.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CnColors.pink),
        ),
        child: const Row(
          children: [
            Icon(Icons.qr_code_2_rounded, color: CnColors.brand, size: 24),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Soldan ürün eklediğinizde öğrenci, öğretmen veya velinin okutması için ödeme karekodu otomatik üretilir.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.38,
                  color: CnColors.slate,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_qrCreating) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFF2B2F36),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Color(0xFFFBBF24),
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Ödeme karekodu üretiliyor...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    if (_qrError != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFDC2626),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _qrError!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFB91C1C),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _scheduleQrSync(immediate: true),
              child: const Text('Yenile'),
            ),
          ],
        ),
      );
    }

    final s = _qrSession;
    if (s == null) {
      return OutlinedButton.icon(
        style: cnOutlineBtn(),
        onPressed: () => _scheduleQrSync(immediate: true),
        icon: const Icon(Icons.qr_code_2_rounded, size: 18),
        label: const Text('Ödeme Karekodu Üret'),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2B2F36), Color(0xFF1E2228)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3E444F)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _showLargeQrDialog(s),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFBBF24), width: 2),
              ),
              child: QrImageView(
                data: s.qrPayload,
                size: 98,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4ADE80),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Okutulması Bekleniyor',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFFFBBF24),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Öğrenci, öğretmen veya veli uygulamadan okuttuğunda satış otomatik onaylanır.',
                  style: TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 11,
                    height: 1.32,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: s.shortCode));
                          cnSnack(context, 'Ödeme kodu kopyalandı.');
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF363C46),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF4B5260)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.pin_outlined,
                                size: 13,
                                color: Color(0xFFFBBF24),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  s.formattedShortCode,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Tam Ekran Büyüt',
                      onPressed: () => _showLargeQrDialog(s),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.10),
                        minimumSize: const Size(30, 30),
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(
                        Icons.fullscreen_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Yeni Karekod Üret',
                      onPressed: () => _scheduleQrSync(immediate: true),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.10),
                        minimumSize: const Size(30, 30),
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showLargeQrDialog(CanteenQrSession s) async {
    bool open = true;
    _closeLargeQrDialog = () {
      if (open && mounted) {
        open = false;
        Navigator.of(context, rootNavigator: true).maybePop();
      }
    };
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E2228),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 410),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBBF24).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.qr_code_2_rounded,
                        color: Color(0xFFFBBF24),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'KantiN Mobil QR Ödeme',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Telefonunuzdan okutarak onaylayın',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        open = false;
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: const Color(0xFFFBBF24),
                      width: 3.5,
                    ),
                  ),
                  child: QrImageView(
                    data: s.qrPayload,
                    size: 240,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  cnMoney(s.total),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2B2F36),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF4B5260)),
                  ),
                  child: Text(
                    'Ödeme Kodu: ${s.formattedShortCode}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Color(0xFFFBBF24),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Öğrenci, öğretmen veya veli uygulamadan karekodu okutup onayladığında bu pencere otomatik kapanır.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    open = false;
    _closeLargeQrDialog = null;
  }

  Widget _posTerminalSection() {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.point_of_sale_rounded,
                color: Color(0xFF0284C7),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Kredi / Banka Kartı POS Tahsilatı',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0369A1),
                  ),
                ),
              ),
              InkWell(
                onTap: () => SchoolPosSettingsDialog.show(
                  context,
                  institutionId: _inst,
                  initialTab: 2,
                ),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF7DD3FC)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.settings_rounded,
                        size: 13,
                        color: Color(0xFF0369A1),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'POS Ayarları',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0369A1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Tutarı banka POS cihazından çektikten sonra tahsilatı onaylayın.',
            style: TextStyle(
              fontSize: 11.5,
              color: Color(0xFF334155),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _posNoteCtrl,
            decoration: cnInput(
              'Slip / Onay No (Opsiyonel)',
              hint: 'Örn: Slip #0412',
              prefix: const Icon(
                Icons.receipt_outlined,
                size: 18,
                color: Color(0xFF0284C7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardSelectorSection() {
    final c = _card;
    if (c != null) {
      return CnVirtualCard(
        card: c,
        spentToday: _spentToday,
        compact: true,
        trailingAction: Material(
          color: Colors.white.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              _card = null;
              _spentToday = 0;
              _cardError = null;
              _rebuild();
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 14),
                  SizedBox(width: 3),
                  Text(
                    'Değiştir',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final suggestions = _cardSuggestions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _cardCtrl,
                decoration: cnInput(
                  'Kart No veya Öğrenci Adı Ara',
                  prefix: const Icon(
                    Icons.contactless_outlined,
                    size: 20,
                    color: CnColors.brand,
                  ),
                ),
                onChanged: (_) => _rebuild(),
                onSubmitted: (_) => _lookupCard(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: cnPrimaryBtn(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
              onPressed: _lookingUp ? null : _lookupCard,
              child: _lookingUp
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Bul'),
            ),
          ],
        ),
        if (_cardError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _cardError!,
              style: const TextStyle(
                color: CnColors.brandDark,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 165),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: CnColors.border),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: suggestions.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
              itemBuilder: (context, i) {
                final s = suggestions[i];
                return InkWell(
                  onTap: () => _selectCard(s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: CnColors.pinkBg,
                          child: Text(
                            cnInitials(s.studentName),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: CnColors.brand,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.studentName.isEmpty
                                    ? s.cardNo
                                    : s.studentName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: CnColors.text,
                                ),
                              ),
                              Text(
                                '${s.className.isEmpty ? '' : '${s.className} • '}${s.cardNo}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: CnColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          cnMoney(s.balance),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: CnColors.brand,
                          ),
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
}
