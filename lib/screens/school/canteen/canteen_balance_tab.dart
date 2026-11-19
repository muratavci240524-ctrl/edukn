import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../models/canteen/canteen_models.dart';
import '../../../services/canteen_service.dart';
import 'canteen_common.dart';

/// Bakiye Yükleme & Sorgulama sekmesi — KantiN Studio.
class CanteenBalanceTab extends StatefulWidget {
  final String institutionId;
  const CanteenBalanceTab({super.key, required this.institutionId});

  @override
  State<CanteenBalanceTab> createState() => _CanteenBalanceTabState();
}

class _CanteenBalanceTabState extends State<CanteenBalanceTab>
    with AutomaticKeepAliveClientMixin {
  static const List<double> _quickAmounts = [50, 100, 200, 500, 1000];

  final CanteenService _svc = CanteenService.instance;
  final TextEditingController _queryCtrl = TextEditingController();
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _txSearchCtrl = TextEditingController();

  StreamSubscription<List<CanteenCard>>? _cardsSub;
  List<CanteenCard> _cards = const [];

  StreamSubscription<List<CanteenTransaction>>? _txSub;
  List<CanteenTransaction> _txs = const [];
  bool _txLoading = false;
  String _txTypeFilter = 'all'; // 'all' | 'sale' | 'topup' | 'refund'

  CanteenCard? _card;
  double _spentToday = 0;
  bool _looking = false;
  String? _error;
  double? _quick;
  String _method = 'cash';
  bool _busy = false;
  bool _canRefund = true;

  String get _inst => widget.institutionId.trim();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _subscribeCards();
    _refreshRefundPermission();
  }

  @override
  void didUpdateWidget(covariant CanteenBalanceTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.institutionId != widget.institutionId) {
      _card = null;
      _spentToday = 0;
      _txSub?.cancel();
      _txs = const [];
      _subscribeCards();
      _refreshRefundPermission();
    }
  }

  Future<void> _refreshRefundPermission() async {
    if (_inst.isEmpty) return;
    final ok = await _svc.hasRefundPermission(_inst);
    if (!mounted) return;
    setState(() => _canRefund = ok);
  }

  void _subscribeCards() {
    _cardsSub?.cancel();
    _cardsSub = null;
    if (_inst.isEmpty) return;
    _cardsSub = _svc
        .watchCards(_inst)
        .listen(
          (l) {
            if (!mounted) return;
            setState(() {
              _cards = l;
              final cur = _card;
              if (cur != null) {
                for (final c in l) {
                  if (c.cardNo == cur.cardNo) {
                    _card = c;
                    break;
                  }
                }
              }
            });
          },
          onError: (Object e) {
            if (!mounted) return;
            setState(() => _error = cnErr(e));
          },
        );
  }

  double _computeTodaySpent(List<CanteenTransaction> txs) {
    final start = cnStartOfDay(DateTime.now());
    double sum = 0;
    for (final t in txs) {
      final at = t.createdAt;
      if (at == null || at.isBefore(start)) continue;
      if (t.type == 'sale') sum += t.amount;
      if (t.type == 'refund') sum -= t.amount;
    }
    return sum < 0 ? 0 : sum;
  }

  void _select(CanteenCard c) {
    _txSub?.cancel();
    setState(() {
      _card = c;
      _error = null;
      _txLoading = true;
      _txs = const [];
      _txTypeFilter = 'all';
      _txSearchCtrl.clear();
      _spentToday = 0;
      _queryCtrl.clear();
    });
    _txSub = _svc
        .watchTransactions(_inst, cardNo: c.cardNo, limit: 0)
        .listen(
          (l) {
            if (!mounted) return;
            setState(() {
              _txs = l;
              _spentToday = _computeTodaySpent(l);
              _txLoading = false;
            });
          },
          onError: (Object _) {
            if (!mounted) return;
            setState(() => _txLoading = false);
          },
        );
  }

  Future<void> _lookup() async {
    final q = _queryCtrl.text.trim();
    if (q.isEmpty || _inst.isEmpty || _looking) return;
    setState(() {
      _looking = true;
      _error = null;
    });
    try {
      var c = await _svc.findCard(_inst, q);
      if (c == null) {
        final lq = q.toLowerCase();
        for (final x in _cards) {
          if (x.studentName.toLowerCase() == lq ||
              x.cardNo.toLowerCase() == lq) {
            c = x;
            break;
          }
        }
        c ??= _suggestions.length == 1 ? _suggestions.first : null;
      }
      if (!mounted) return;
      setState(() => _looking = false);
      if (c == null) {
        setState(() => _error = 'Eşleşen kart veya öğrenci bulunamadı.');
      } else {
        _select(c);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _looking = false;
        _error = cnErr(e);
      });
    }
  }

  Future<void> _topUp() async {
    final c = _card;
    if (c == null || _busy) return;
    final amount = _quick ?? cnParseMoney(_amountCtrl.text);
    if (amount <= 0) {
      cnSnack(
        context,
        'Lütfen yüklenecek geçerli bir tutar seçin veya girin.',
        error: true,
      );
      return;
    }
    final methodText = _method == 'cash' ? 'Nakit' : 'Kredi Kartı POS';
    final ok = await cnConfirm(
      context,
      'Bakiye Yüklemeyi Onayla',
      '${c.studentName.isEmpty ? c.cardNo : c.studentName} (${c.cardNo}) kartına '
          '$methodText ile ${cnMoney(amount)} bakiye yüklenecek.\n'
          'Yükleme sonrası tahmini bakiye: ${cnMoney(c.balance + amount)}',
      confirmLabel: 'Yüklemeyi Tamamla',
      icon: Icons.account_balance_wallet_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await _svc.topUp(
        instId: _inst,
        cardNo: c.cardNo,
        amount: amount,
        method: _method,
        cashierId: FirebaseAuth.instance.currentUser?.uid ?? '',
      );
      if (!mounted) return;
      _amountCtrl.clear();
      setState(() {
        _quick = null;
        _busy = false;
      });
      cnSnack(context, '${cnMoney(amount)} bakiye başarıyla yüklendi.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      cnSnack(context, cnErr(e), error: true);
    }
  }

  @override
  void dispose() {
    _cardsSub?.cancel();
    _txSub?.cancel();
    _queryCtrl.dispose();
    _amountCtrl.dispose();
    _txSearchCtrl.dispose();
    super.dispose();
  }

  static String _trLower(String s) => s
      .replaceAll('İ', 'i')
      .replaceAll('I', 'ı')
      .replaceAll('Ş', 'ş')
      .replaceAll('Ğ', 'ğ')
      .replaceAll('Ü', 'ü')
      .replaceAll('Ö', 'ö')
      .replaceAll('Ç', 'ç')
      .toLowerCase();

  bool _matchesTransaction(
    CanteenTransaction t, {
    required String typeFilter,
    required String rawQuery,
  }) {
    if (typeFilter != 'all' && t.type != typeFilter) return false;
    final q = _trLower(rawQuery.trim());
    if (q.isEmpty) return true;

    final typeLabel = t.type == 'topup'
        ? 'yükleme bakiye yükleme'
        : t.type == 'refund'
        ? 'iade'
        : 'satış harcama alışveriş';
    final methodLabel = cnMethodLabel(t.method);
    final itemsText = t.items.map((e) => '${e.qty}x ${e.name}').join(' ');
    final dateText = cnDateTime(t.createdAt);
    final amountText = '${cnMoney(t.amount)} ${t.amount.toStringAsFixed(2)}';
    final haystack = _trLower(
      '$typeLabel $methodLabel $itemsText $dateText $amountText ${t.id} ${t.cardNo}',
    );
    return haystack.contains(q);
  }

  List<CanteenTransaction> get _filteredTxs => _txs
      .where(
        (t) => _matchesTransaction(
          t,
          typeFilter: _txTypeFilter,
          rawQuery: _txSearchCtrl.text,
        ),
      )
      .toList();

  List<CanteenCard> get _suggestions {
    final q = _queryCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _cards
        .where(
          (c) =>
              c.studentName.toLowerCase().contains(q) ||
              c.cardNo.toLowerCase().contains(q) ||
              c.className.toLowerCase().contains(q),
        )
        .take(6)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, cons) {
        final wide = cons.maxWidth >= 940;
        if (wide) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(child: _leftColumn()),
                ),
                const SizedBox(width: 16),
                Expanded(flex: 5, child: _txTimelinePanel()),
              ],
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _leftColumn(),
            const SizedBox(height: 14),
            SizedBox(height: 440, child: _txTimelinePanel()),
          ],
        );
      },
    );
  }

  Widget _leftColumn() {
    final sugg = _suggestions;
    final c = _card;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Arama & Kart Seçim Paneli
        CnPanel(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const CnSectionLabel(
                'KART VEYA ÖĞRENCİ SORGULA',
                icon: Icons.contactless_rounded,
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _queryCtrl,
                      decoration: cnInput(
                        'Kart no, QR (KANTIN:...) veya öğrenci adı...',
                        prefix: const Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: CnColors.brand,
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _lookup(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: cnPrimaryBtn(),
                    onPressed: _looking ? null : _lookup,
                    icon: _looking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('Sorgula'),
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: CnColors.brandDark,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (sugg.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: CnColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: CnColors.border),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < sugg.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, color: CnColors.border),
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _select(sugg[i]),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: CnColors.pinkBg,
                                  child: Text(
                                    cnInitials(sugg[i].studentName),
                                    style: const TextStyle(
                                      color: CnColors.brand,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        sugg[i].studentName.isEmpty
                                            ? sugg[i].cardNo
                                            : sugg[i].studentName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: CnColors.text,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                      Text(
                                        '${sugg[i].className.isEmpty ? '' : '${sugg[i].className} • '}Kart: ${sugg[i].cardNo}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: CnColors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  cnMoney(sugg[i].balance),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: CnColors.brand,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              else if (c == null && _cards.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  'Hızlı Seçim:',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: CnColors.muted,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final item in _cards.take(6))
                      ActionChip(
                        backgroundColor: CnColors.surfaceAlt,
                        side: const BorderSide(color: CnColors.border),
                        avatar: CircleAvatar(
                          backgroundColor: CnColors.pinkBg,
                          child: Text(
                            cnInitials(item.studentName),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: CnColors.brand,
                            ),
                          ),
                        ),
                        label: Text(
                          item.studentName.isEmpty
                              ? item.cardNo
                              : item.studentName,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: CnColors.text,
                          ),
                        ),
                        onPressed: () => _select(item),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        if (c == null)
          const CnPanel(
            padding: EdgeInsets.symmetric(vertical: 36, horizontal: 20),
            child: CnEmpty(
              'Henüz kart seçilmedi',
              subtitle:
                  'Bakiye yüklemek veya hesap hareketlerini incelemek için yukarıdan kart okutun ya da öğrenci adını arayın.',
              icon: Icons.credit_card_rounded,
            ),
          )
        else ...[
          // Gerçekçi Parlak KantiN Sanal Kartı
          CnVirtualCard(
            card: c,
            spentToday: _spentToday,
            compact: false,
            trailingAction: Material(
              color: Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(9),
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () {
                  _txSub?.cancel();
                  setState(() {
                    _card = null;
                    _txs = const [];
                    _txTypeFilter = 'all';
                    _txSearchCtrl.clear();
                    _spentToday = 0;
                  });
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  child: Text(
                    'Kapat',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Bakiye Yükleme Paneli
          CnPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CnSectionLabel(
                  'HIZLI BAKİYE YÜKLEME TUTARI',
                  icon: Icons.bolt_rounded,
                ),
                LayoutBuilder(
                  builder: (context, box) {
                    final cols = box.maxWidth >= 420 ? 5 : 3;
                    final tileW = (box.maxWidth - (cols - 1) * 8) / cols;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final a in _quickAmounts)
                          SizedBox(width: tileW, child: _topUpTile(a)),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: cnInput(
                    'Özel Yükleme Tutarı (₺)',
                    hint: 'Örn. 350',
                    prefix: const Icon(Icons.currency_lira_rounded, size: 19),
                  ),
                  onChanged: (v) {
                    setState(() {
                      if (v.trim().isNotEmpty) _quick = null;
                    });
                  },
                ),
                const SizedBox(height: 14),
                const CnSectionLabel(
                  'TAHSİLAT YÖNTEMİ',
                  icon: Icons.payments_outlined,
                ),
                Row(
                  children: [
                    Expanded(
                      child: _payMethodCard(
                        key: 'cash',
                        label: 'Nakit Tahsilat',
                        icon: Icons.payments_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _payMethodCard(
                        key: 'pos',
                        label: 'Kredi / Banka POS',
                        icon: Icons.credit_card_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: cnPrimaryBtn(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                  ),
                  onPressed: _busy ? null : _topUp,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add_card_rounded, size: 20),
                  label: Text(_busy ? 'Yükleniyor...' : 'Bakiye Yükle'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _topUpTile(double amount) {
    final sel = _quick == amount;
    final formatted = amount >= 1000 ? '1.000 ₺' : '${amount.toInt()} ₺';
    return Material(
      color: sel ? CnColors.brand : CnColors.surfaceAlt,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () {
          setState(() {
            _quick = sel ? null : amount;
            if (_quick != null) _amountCtrl.clear();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: sel ? CnColors.brand : CnColors.border,
              width: sel ? 1.5 : 1.0,
            ),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                formatted,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: sel ? Colors.white : CnColors.text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _payMethodCard({
    required String key,
    required String label,
    required IconData icon,
  }) {
    final sel = _method == key;
    return Material(
      color: sel ? CnColors.pinkBg : CnColors.surfaceAlt,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () => setState(() => _method = key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: sel ? CnColors.brand : CnColors.border,
              width: sel ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 19,
                color: sel ? CnColors.brand : CnColors.slate,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                    color: sel ? CnColors.brand : CnColors.slate,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sağ Sütun: Seçili Kartın Tüm İşlem Kayıtları + Filtre & Arama ─────────

  Widget _txTimelinePanel() {
    final c = _card;
    final filtered = _filteredTxs;
    final saleCount = _txs.where((t) => t.type == 'sale').length;
    final topupCount = _txs.where((t) => t.type == 'topup').length;
    final refundCount = _txs.where((t) => t.type == 'refund').length;

    double shownSales = 0;
    double shownTopups = 0;
    for (final t in filtered) {
      if (t.type == 'sale') {
        shownSales += t.amount;
      } else if (t.type == 'topup' || t.type == 'refund') {
        shownTopups += t.amount;
      }
    }

    return CnPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                  Icons.history_rounded,
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
                      'Kart Hareketleri',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: CnColors.text,
                      ),
                    ),
                    Text(
                      c == null
                          ? 'Seçili kartın tüm yükleme ve harcama kayıtları burada listelenir'
                          : '${c.studentName.isEmpty ? c.cardNo : c.studentName} • Toplam ${_txs.length} kayıt',
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
              if (c != null && _txs.isNotEmpty)
                OutlinedButton.icon(
                  style: cnOutlineBtn(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 8,
                    ),
                  ),
                  onPressed: () => _showAllCardTransactionsDialog(c),
                  icon: const Icon(Icons.open_in_full_rounded, size: 15),
                  label: Text('Tümü (${_txs.length})'),
                ),
            ],
          ),
          if (c != null && !_txLoading && _txs.isNotEmpty) ...[
            const SizedBox(height: 12),
            // Tümü / Satışlar / Yüklemeler / İadeler sekme çipleri
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _txFilterChip(
                    key: 'all',
                    label: 'Tümü (${_txs.length})',
                    icon: Icons.list_alt_rounded,
                    activeColor: CnColors.text,
                    selected: _txTypeFilter == 'all',
                    onTap: () => setState(() => _txTypeFilter = 'all'),
                  ),
                  const SizedBox(width: 6),
                  _txFilterChip(
                    key: 'sale',
                    label: 'Harcamalar ($saleCount)',
                    icon: Icons.shopping_bag_outlined,
                    activeColor: CnColors.brand,
                    selected: _txTypeFilter == 'sale',
                    onTap: () => setState(() => _txTypeFilter = 'sale'),
                  ),
                  const SizedBox(width: 6),
                  _txFilterChip(
                    key: 'topup',
                    label: 'Yüklemeler ($topupCount)',
                    icon: Icons.add_card_rounded,
                    activeColor: CnColors.okDark,
                    selected: _txTypeFilter == 'topup',
                    onTap: () => setState(() => _txTypeFilter = 'topup'),
                  ),
                  if (refundCount > 0) ...[
                    const SizedBox(width: 6),
                    _txFilterChip(
                      key: 'refund',
                      label: 'İadeler ($refundCount)',
                      icon: Icons.replay_rounded,
                      activeColor: CnColors.warnDark,
                      selected: _txTypeFilter == 'refund',
                      onTap: () => setState(() => _txTypeFilter = 'refund'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Arama kutusu (ürün adı, ödeme yöntemi, tarih, tutar...)
            TextField(
              controller: _txSearchCtrl,
              decoration: cnInput(
                'Kayıtlarda ara (ürün adı, yöntem, tarih veya tutar)...',
                prefix: const Icon(
                  Icons.search_rounded,
                  size: 19,
                  color: CnColors.muted,
                ),
                suffix: _txSearchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Aramayı Temizle',
                        icon: const Icon(Icons.clear_rounded, size: 17),
                        onPressed: () {
                          _txSearchCtrl.clear();
                          setState(() {});
                        },
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            // Gösterilen kayıtların hızlı toplam özeti
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: CnColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: CnColors.border),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Gösterilen: ${filtered.length} / ${_txs.length} kayıt',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: CnColors.slate,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '+${cnMoney(shownTopups)}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: CnColors.okDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '-${cnMoney(shownSales)}',
                        style: const TextStyle(
                          fontSize: 11.5,
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
          const SizedBox(height: 10),
          const Divider(height: 1, color: CnColors.border),
          const SizedBox(height: 8),
          Expanded(
            child: c == null
                ? const CnEmpty(
                    'Kart seçilmedi',
                    subtitle:
                        'Sol panelden öğrenci kartını seçtiğinizde yükleme ve harcama geçmişi anlık olarak görüntülenir.',
                    icon: Icons.timeline_rounded,
                  )
                : _txLoading
                ? const Center(
                    child: CircularProgressIndicator(color: CnColors.brand),
                  )
                : _txs.isEmpty
                ? const CnEmpty(
                    'Henüz işlem kaydı yok',
                    subtitle:
                        'Bu kart ile yapılan yükleme ve kantin alışverişleri burada görünecek.',
                    icon: Icons.receipt_long_outlined,
                  )
                : filtered.isEmpty
                ? CnEmpty(
                    'Aramayla eşleşen kayıt bulunamadı',
                    subtitle:
                        'Farklı bir anahtar kelime deneyin veya filtreyi "Tümü" olarak sıfırlayın.',
                    icon: Icons.search_off_rounded,
                    action: OutlinedButton.icon(
                      style: cnOutlineBtn(),
                      onPressed: () {
                        _txSearchCtrl.clear();
                        setState(() => _txTypeFilter = 'all');
                      },
                      icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                      label: const Text('Filtreyi Temizle'),
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 14, color: Color(0xFFF1F5F9)),
                    itemBuilder: (context, i) => _txRow(filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _txFilterChip({
    required String key,
    required String label,
    required IconData icon,
    required Color activeColor,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? activeColor : CnColors.surfaceAlt,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? activeColor : CnColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected ? Colors.white : activeColor,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : CnColors.slate,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAllCardTransactionsDialog(CanteenCard c) async {
    final dialogSearchCtrl = TextEditingController(text: _txSearchCtrl.text);
    String dialogFilter = _txTypeFilter;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setS) {
            final list = _txs
                .where(
                  (t) => _matchesTransaction(
                    t,
                    typeFilter: dialogFilter,
                    rawQuery: dialogSearchCtrl.text,
                  ),
                )
                .toList();
            final saleCount = _txs.where((t) => t.type == 'sale').length;
            final topupCount = _txs.where((t) => t.type == 'topup').length;
            final refundCount = _txs.where((t) => t.type == 'refund').length;

            double sumSales = 0;
            double sumTopups = 0;
            for (final t in list) {
              if (t.type == 'sale') {
                sumSales += t.amount;
              } else {
                sumTopups += t.amount;
              }
            }

            final mq = MediaQuery.of(ctx);
            return Dialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 20,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 760,
                  maxHeight: (mq.size.height * 0.86).clamp(360.0, 820.0),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Başlık
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: CnColors.pinkBg,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(
                              Icons.receipt_long_rounded,
                              color: CnColors.brand,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${c.studentName.isEmpty ? c.cardNo : c.studentName} — Tüm Kart Hareketleri',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: CnColors.text,
                                  ),
                                ),
                                Text(
                                  'Kart No: ${c.cardNo}${c.className.isEmpty ? '' : ' • ${c.className}'} • Güncel Bakiye: ${cnMoney(c.balance)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: CnColors.muted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: IconButton.styleFrom(
                              backgroundColor: CnColors.surfaceAlt,
                            ),
                            icon: const Icon(Icons.close_rounded, size: 20),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Filtre çipleri + Arama satırı
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _txFilterChip(
                              key: 'all',
                              label: 'Tümü (${_txs.length})',
                              icon: Icons.list_alt_rounded,
                              activeColor: CnColors.text,
                              selected: dialogFilter == 'all',
                              onTap: () => setS(() => dialogFilter = 'all'),
                            ),
                            const SizedBox(width: 6),
                            _txFilterChip(
                              key: 'sale',
                              label: 'Harcamalar ($saleCount)',
                              icon: Icons.shopping_bag_outlined,
                              activeColor: CnColors.brand,
                              selected: dialogFilter == 'sale',
                              onTap: () => setS(() => dialogFilter = 'sale'),
                            ),
                            const SizedBox(width: 6),
                            _txFilterChip(
                              key: 'topup',
                              label: 'Yüklemeler ($topupCount)',
                              icon: Icons.add_card_rounded,
                              activeColor: CnColors.okDark,
                              selected: dialogFilter == 'topup',
                              onTap: () => setS(() => dialogFilter = 'topup'),
                            ),
                            if (refundCount > 0) ...[
                              const SizedBox(width: 6),
                              _txFilterChip(
                                key: 'refund',
                                label: 'İadeler ($refundCount)',
                                icon: Icons.replay_rounded,
                                activeColor: CnColors.warnDark,
                                selected: dialogFilter == 'refund',
                                onTap: () =>
                                    setS(() => dialogFilter = 'refund'),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: dialogSearchCtrl,
                        autofocus: true,
                        decoration: cnInput(
                          'Ürün adı, ödeme yöntemi, tarih, tutar veya işlem no ara...',
                          prefix: const Icon(
                            Icons.search_rounded,
                            size: 20,
                            color: CnColors.brand,
                          ),
                          suffix: dialogSearchCtrl.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(
                                    Icons.clear_rounded,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    dialogSearchCtrl.clear();
                                    setS(() {});
                                  },
                                ),
                        ),
                        onChanged: (_) => setS(() {}),
                      ),
                      const SizedBox(height: 10),

                      // Özet şeridi
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: CnColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: CnColors.border),
                        ),
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 6,
                          alignment: WrapAlignment.spaceBetween,
                          children: [
                            Text(
                              'Listelenen Kayıt: ${list.length} / ${_txs.length}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: CnColors.text,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Toplam Yükleme: +${cnMoney(sumTopups)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: CnColors.okDark,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Text(
                                  'Toplam Harcama: -${cnMoney(sumSales)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: CnColors.brand,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Divider(height: 1, color: CnColors.border),
                      const SizedBox(height: 8),

                      // Kayıt listesi
                      Expanded(
                        child: list.isEmpty
                            ? CnEmpty(
                                'Eşleşen kayıt bulunamadı',
                                subtitle:
                                    'Arama metnini veya seçili filtreyi değiştirerek tekrar deneyin.',
                                icon: Icons.search_off_rounded,
                                action: OutlinedButton.icon(
                                  style: cnOutlineBtn(),
                                  onPressed: () {
                                    dialogSearchCtrl.clear();
                                    setS(() => dialogFilter = 'all');
                                  },
                                  icon: const Icon(
                                    Icons.filter_alt_off_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('Tümünü Göster'),
                                ),
                              )
                            : ListView.separated(
                                itemCount: list.length,
                                separatorBuilder: (_, __) => const Divider(
                                  height: 14,
                                  color: Color(0xFFF1F5F9),
                                ),
                                itemBuilder: (_, i) => _txRow(
                                  list[i],
                                  onChanged: () {
                                    if (ctx.mounted) setS(() {});
                                  },
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    dialogSearchCtrl.dispose();
  }

  Widget _txRow(CanteenTransaction t, {VoidCallback? onChanged}) {
    final plus = t.type == 'topup' || t.type == 'refund';
    final color = plus ? CnColors.okDark : CnColors.brand;
    final softBg = plus ? CnColors.okSoft : CnColors.pinkBg;
    final typeLabel = t.type == 'topup'
        ? '+ Yükleme'
        : t.type == 'refund'
        ? '+ İade'
        : '- Satış';

    final isSale = t.type == 'sale';
    final fullyRefunded = isSale && t.isFullyRefunded;
    final partiallyRefunded = isSale && t.isPartiallyRefunded;
    final canRefundThisSale = isSale && !fullyRefunded;

    // Kalem bazlı özet (iade edilen adetler varsa yanında belirt)
    final itemParts = <String>[];
    for (int i = 0; i < t.items.length; i++) {
      final item = t.items[i];
      final refQty = isSale ? t.refundedQtyFor(item, i) : 0;
      if (refQty > 0) {
        itemParts.add('${item.qty}× ${item.name} ($refQty iade)');
      } else {
        itemParts.add('${item.qty}× ${item.name}');
      }
    }
    final itemsSummary = itemParts.join(', ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: fullyRefunded ? CnColors.surfaceAlt : softBg,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            t.type == 'refund'
                ? Icons.replay_rounded
                : plus
                ? Icons.south_west_rounded
                : Icons.shopping_bag_outlined,
            color: fullyRefunded ? CnColors.muted : color,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  CnBadge(
                    typeLabel,
                    color: fullyRefunded ? CnColors.muted : color,
                  ),
                  Text(
                    cnMethodLabel(t.method),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: CnColors.slate,
                    ),
                  ),
                  if (fullyRefunded)
                    const CnBadge(
                      'Tam İade Edildi',
                      color: CnColors.muted,
                      icon: Icons.check_circle_outline_rounded,
                    )
                  else if (partiallyRefunded)
                    CnBadge(
                      'Kısmi İade (${cnMoney(t.refundedAmount)})',
                      color: CnColors.warnDark,
                      icon: Icons.replay_rounded,
                    ),
                ],
              ),
              if (itemsSummary.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  itemsSummary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: fullyRefunded ? CnColors.muted : CnColors.text,
                    decoration: fullyRefunded
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ],
              if (t.note.isNotEmpty && t.type == 'refund') ...[
                const SizedBox(height: 2),
                Text(
                  t.note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: CnColors.okDark,
                  ),
                ),
              ],
              const SizedBox(height: 2),
              Text(
                cnDateTime(t.createdAt),
                style: const TextStyle(fontSize: 11.5, color: CnColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${plus ? '+' : '-'}${cnMoney(t.amount)}',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: fullyRefunded ? CnColors.muted : color,
                decoration: fullyRefunded ? TextDecoration.lineThrough : null,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Bakiye: ${cnMoney(t.balanceAfter)}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: CnColors.muted,
              ),
            ),
            if (canRefundThisSale) ...[
              const SizedBox(height: 5),
              Material(
                color: _canRefund ? CnColors.pinkBg : CnColors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () async {
                    if (!_canRefund) {
                      await showDialog<void>(
                        context: context,
                        builder: (ctx) => CnDialogShell(
                          title: 'İade Yetkisi Gerekli',
                          icon: Icons.lock_outline_rounded,
                          maxWidth: 460,
                          showCancel: false,
                          primaryLabel: 'Anladım',
                          onPrimary: () => Navigator.pop(ctx),
                          child: const Text(
                            'Alışveriş veya ürün iadesi yaparak bakiyeyi geri aktarmak için yetkiniz bulunmuyor.\n\n'
                            'Okul yöneticinizden "Kullanıcı Yetkilendirme > Kantin Yönetimi > Bakiye & Kart Hareketleri > Kart Hareketleri Üzerinden Tam veya Parça Parça Ürün İadesi" yetkisini talep edebilirsiniz.',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: CnColors.slate,
                              height: 1.45,
                            ),
                          ),
                        ),
                      );
                      return;
                    }
                    final refunded = await _showRefundSaleDialog(t);
                    if (refunded && onChanged != null) {
                      onChanged();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _canRefund
                            ? CnColors.brand.withValues(alpha: 0.35)
                            : CnColors.border,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _canRefund
                              ? Icons.replay_rounded
                              : Icons.lock_outline_rounded,
                          size: 13,
                          color: _canRefund ? CnColors.brand : CnColors.muted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          partiallyRefunded ? 'Kalanı İade Et' : 'İade Et',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: _canRefund ? CnColors.brand : CnColors.muted,
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
      ],
    );
  }

  /// Kart hareketlerindeki bir satış işlemi için **Tüm Alışverişi İade** veya
  /// **Ürün Ürün / Parça Parça İade** penceresini açar ve harcanan parayı
  /// kart bakiyesine geri aktarır.
  Future<bool> _showRefundSaleDialog(CanteenTransaction saleTx) async {
    if (saleTx.isFullyRefunded) {
      cnSnack(context, 'Bu alışverişin tamamı zaten iade edilmiş.', error: true);
      return false;
    }

    // Başlangıçta tüm kalan ürünleri seçili getir ("Tüm Alışverişi İade" modu)
    bool fullMode = true;
    final selectedQtys = <String, int>{};
    for (int i = 0; i < saleTx.items.length; i++) {
      final item = saleTx.items[i];
      final key = CanteenTransaction.itemRefundKey(item, i);
      final rem = saleTx.refundableQtyFor(item, i);
      if (rem > 0) {
        selectedQtys[key] = rem;
      }
    }

    final reasonCtrl = TextEditingController();
    bool submitting = false;
    String? dialogErr;

    void selectAllRemaining() {
      for (int i = 0; i < saleTx.items.length; i++) {
        final item = saleTx.items[i];
        final key = CanteenTransaction.itemRefundKey(item, i);
        final rem = saleTx.refundableQtyFor(item, i);
        selectedQtys[key] = rem > 0 ? rem : 0;
      }
    }

    double calcSelectedRefundTotal() {
      if (saleTx.items.isEmpty) {
        return saleTx.remainingRefundableAmount;
      }
      double sum = 0;
      for (int i = 0; i < saleTx.items.length; i++) {
        final item = saleTx.items[i];
        final key = CanteenTransaction.itemRefundKey(item, i);
        final q = (selectedQtys[key] ?? 0).clamp(
          0,
          saleTx.refundableQtyFor(item, i),
        );
        sum += item.price * q;
      }
      final maxRem = saleTx.remainingRefundableAmount;
      return sum > maxRem + 0.05 ? maxRem : sum;
    }

    int calcSelectedTotalPieces() {
      int count = 0;
      for (final v in selectedQtys.values) {
        if (v > 0) count += v;
      }
      return count;
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setS) {
            final refundTotal = calcSelectedRefundTotal();
            final totalPieces = calcSelectedTotalPieces();
            final currentBalance = _card?.balance ?? saleTx.balanceAfter;
            final willCreditWallet =
                saleTx.cardNo.trim().isNotEmpty &&
                saleTx.method != 'cash' &&
                saleTx.method != 'pos';
            final nextBalance = willCreditWallet
                ? currentBalance + refundTotal
                : currentBalance;

            return CnDialogShell(
              title: 'Alışveriş / Ürün İadesi & Bakiye Geri Aktarım',
              subtitle:
                  '${_card?.studentName.isNotEmpty == true ? _card!.studentName : saleTx.cardNo} • ${cnDateTime(saleTx.createdAt)}',
              icon: Icons.replay_rounded,
              maxWidth: 620,
              errorText: dialogErr,
              loading: submitting,
              cancelLabel: 'Vazgeç',
              onCancel: () => Navigator.pop(ctx, false),
              primaryLabel: submitting
                  ? 'İade İşleniyor...'
                  : 'İadeyi Tamamla (+${cnMoney(refundTotal)})',
              primaryIcon: Icons.replay_rounded,
              primaryColor: CnColors.okDark,
              onPrimary: refundTotal <= 0
                  ? null
                  : () async {
                      setS(() {
                        submitting = true;
                        dialogErr = null;
                      });
                      try {
                        final uid =
                            FirebaseAuth.instance.currentUser?.uid ?? '';
                        final res = await _svc.refundSale(
                          instId: _inst,
                          saleTransactionId: saleTx.id,
                          itemQuantitiesByKey: selectedQtys,
                          refundAll: fullMode && saleTx.items.isEmpty,
                          cashierId: uid,
                          reason: reasonCtrl.text.trim(),
                        );
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx, true);
                        if (!mounted) return;
                        cnSnack(
                          context,
                          'İade tamamlandı: +${cnMoney(res.refundedAmount)} kart bakiyesine geri aktarıldı.',
                        );
                      } catch (e) {
                        if (!ctx.mounted) return;
                        setS(() {
                          submitting = false;
                          dialogErr = cnErr(e);
                        });
                      }
                    },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // İade modu seçimi: Tüm Alışveriş vs Ürün Ürün Parça İade
                  if (saleTx.items.isNotEmpty) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _refundModeButton(
                            selected: fullMode,
                            icon: Icons.select_all_rounded,
                            title: 'Tüm Alışverişi İade Et',
                            subtitle: 'Kalan tüm ürünleri tek tıkla iade al',
                            onTap: submitting
                                ? null
                                : () {
                                    setS(() {
                                      fullMode = true;
                                      selectAllRemaining();
                                      dialogErr = null;
                                    });
                                  },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _refundModeButton(
                            selected: !fullMode,
                            icon: Icons.tune_rounded,
                            title: 'Ürün Ürün / Parçalı İade',
                            subtitle: 'İade edilecek ürün ve adetleri seç',
                            onTap: submitting
                                ? null
                                : () {
                                    setS(() {
                                      fullMode = false;
                                      dialogErr = null;
                                    });
                                  },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Ürün listesi ve adet seçiciler
                  if (saleTx.items.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'ALIŞVERİŞTEKİ ÜRÜNLER',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                            color: CnColors.muted,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: CnColors.brand,
                              ),
                              onPressed: submitting
                                  ? null
                                  : () => setS(() {
                                      selectAllRemaining();
                                      fullMode = true;
                                    }),
                              child: const Text(
                                'Tümünü Seç',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            TextButton(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: CnColors.slate,
                              ),
                              onPressed: submitting
                                  ? null
                                  : () => setS(() {
                                      fullMode = false;
                                      for (final k
                                          in selectedQtys.keys.toList()) {
                                        selectedQtys[k] = 0;
                                      }
                                    }),
                              child: const Text(
                                'Temizle',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: saleTx.items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final item = saleTx.items[i];
                          final key = CanteenTransaction.itemRefundKey(item, i);
                          final alreadyRef = saleTx.refundedQtyFor(item, i);
                          final maxRem = saleTx.refundableQtyFor(item, i);
                          final curQty = (selectedQtys[key] ?? 0).clamp(
                            0,
                            maxRem,
                          );
                          final isSelected = curQty > 0;
                          final lineRefund = item.price * curQty;

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: maxRem == 0
                                  ? CnColors.surfaceAlt
                                  : isSelected
                                  ? CnColors.pinkBg.withValues(alpha: 0.55)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(
                                color: maxRem == 0
                                    ? CnColors.border
                                    : isSelected
                                    ? CnColors.brand
                                    : CnColors.border,
                                width: isSelected ? 1.4 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                // Checkbox
                                Checkbox(
                                  value: isSelected,
                                  activeColor: CnColors.brand,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  onChanged: (maxRem <= 0 || submitting)
                                      ? null
                                      : (v) {
                                          setS(() {
                                            fullMode = false;
                                            selectedQtys[key] = (v == true)
                                                ? maxRem
                                                : 0;
                                            dialogErr = null;
                                          });
                                        },
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          color: maxRem == 0
                                              ? CnColors.muted
                                              : CnColors.text,
                                          decoration: maxRem == 0
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 2,
                                        children: [
                                          Text(
                                            'Birim: ${cnMoney(item.price)} • Alınan: ${item.qty} ad.',
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              color: CnColors.muted,
                                            ),
                                          ),
                                          if (alreadyRef > 0)
                                            Text(
                                              '• Önceki iade: $alreadyRef ad.',
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                                color: CnColors.warnDark,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (maxRem <= 0)
                                  const CnBadge(
                                    'İade Edildi',
                                    color: CnColors.muted,
                                  )
                                else ...[
                                  // - / + Adet seçici
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: CnColors.borderStrong,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          constraints: const BoxConstraints(
                                            minWidth: 30,
                                            minHeight: 30,
                                          ),
                                          padding: EdgeInsets.zero,
                                          icon: const Icon(
                                            Icons.remove_rounded,
                                            size: 16,
                                          ),
                                          onPressed: submitting || curQty <= 0
                                              ? null
                                              : () {
                                                  setS(() {
                                                    fullMode = false;
                                                    selectedQtys[key] =
                                                        curQty - 1;
                                                    dialogErr = null;
                                                  });
                                                },
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                          ),
                                          child: Text(
                                            '$curQty / $maxRem',
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w800,
                                              color: CnColors.text,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          constraints: const BoxConstraints(
                                            minWidth: 30,
                                            minHeight: 30,
                                          ),
                                          padding: EdgeInsets.zero,
                                          icon: const Icon(
                                            Icons.add_rounded,
                                            size: 16,
                                          ),
                                          onPressed:
                                              submitting || curQty >= maxRem
                                              ? null
                                              : () {
                                                  setS(() {
                                                    fullMode = false;
                                                    selectedQtys[key] =
                                                        curQty + 1;
                                                    dialogErr = null;
                                                  });
                                                },
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: 78,
                                    child: Text(
                                      '+${cnMoney(lineRefund)}',
                                      textAlign: TextAlign.end,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w900,
                                        color: isSelected
                                            ? CnColors.okDark
                                            : CnColors.muted,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Hızlı İade Nedeni & Açıklama
                  const Text(
                    'İADE NEDENİ / AÇIKLAMA (OPSİYONEL)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: CnColors.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final preset in const [
                        'Yanlış Ürün Çekildi',
                        'Öğrenci Vazgeçti',
                        'Fazla Adet Girildi',
                        'Ürün Değişimi',
                      ])
                        ActionChip(
                          label: Text(
                            preset,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: CnColors.surfaceAlt,
                          side: const BorderSide(color: CnColors.border),
                          onPressed: submitting
                              ? null
                              : () {
                                  reasonCtrl.text = preset;
                                  setS(() {});
                                },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonCtrl,
                    enabled: !submitting,
                    decoration: cnInput(
                      'İade nedeni veya notu yazın...',
                      prefix: const Icon(
                        Icons.notes_rounded,
                        size: 18,
                        color: CnColors.muted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Bakiye Geri Aktarım Özeti Kartı
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: CnColors.okSoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: CnColors.ok.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              saleTx.items.isNotEmpty
                                  ? 'İade Edilecek ($totalPieces adet ürün)'
                                  : 'İade Edilecek Tutar',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: CnColors.text,
                              ),
                            ),
                            Text(
                              '+${cnMoney(refundTotal)}',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: CnColors.okDark,
                              ),
                            ),
                          ],
                        ),
                        if (willCreditWallet) ...[
                          const SizedBox(height: 6),
                          const Divider(height: 1, color: Color(0xFFA7F3D0)),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Kart Bakiyesi (Mevcut → İade Sonrası)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: CnColors.slate,
                                ),
                              ),
                              Text(
                                '${cnMoney(currentBalance)} → ${cnMoney(nextBalance)}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: CnColors.okDark,
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
            );
          },
        );
      },
    );

    reasonCtrl.dispose();
    return ok == true;
  }

  Widget _refundModeButton({
    required bool selected,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: selected ? CnColors.pinkBg : CnColors.surfaceAlt,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? CnColors.brand : CnColors.border,
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? CnColors.brand : CnColors.slate,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: selected ? CnColors.brand : CnColors.text,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: CnColors.muted,
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
}
