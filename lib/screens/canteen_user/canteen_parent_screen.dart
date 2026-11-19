import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/canteen/canteen_models.dart';
import '../../services/canteen_service.dart';
import 'canteen_qr_pay_sheet.dart';
import 'canteen_user_widgets.dart';

/// Veli kantin ekranı: kart bakiyesi, iyzico güvenli bakiye yükleme,
/// kart aktif/pasif durumu, günlük harcama limiti, kategori bloke yönetimi,
/// işlem hareketleri ve kantin ürünleri.
class CanteenParentScreen extends StatefulWidget {
  final String institutionId;
  final String? studentId;
  final String? studentName;

  const CanteenParentScreen({
    super.key,
    required this.institutionId,
    this.studentId,
    this.studentName,
  });

  @override
  State<CanteenParentScreen> createState() => _CanteenParentScreenState();
}

class _CanteenParentScreenState extends State<CanteenParentScreen> {
  late CanteenFeed _feed;
  final CanteenProductFilterModel _filter = CanteenProductFilterModel();
  final TextEditingController _limitCtrl = TextEditingController();
  StreamSubscription<List<CanteenCard>>? _cardsSub;

  List<CanteenCard> _cards = const [];
  bool _cardsLoading = true;
  Object? _cardsError;
  String? _selectedCardNo;
  int _tab = 0;
  String _txFilter = 'all';
  bool _busy = false;

  /// Figma 2x3 dairesel kırmızı limit rozetleri (0 = Limitsiz).
  static const List<double> _limitBadges = [50, 100, 150, 200, 300, 0];

  String get _inst => widget.institutionId.trim().toUpperCase();

  CanteenCard? get _card {
    for (final c in _cards) {
      if (c.cardNo == _selectedCardNo) return c;
    }
    return _cards.isEmpty ? null : _cards.first;
  }

  @override
  void initState() {
    super.initState();
    _feed = CanteenFeed(_inst);
    _subscribeCards(resetSelection: true);
  }

  @override
  void didUpdateWidget(covariant CanteenParentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldInst = oldWidget.institutionId.trim().toUpperCase();
    final newInst = _inst;
    final instChanged = oldInst != newInst;
    final studentChanged =
        (oldWidget.studentId ?? '').trim() != (widget.studentId ?? '').trim();

    if (instChanged) {
      final prevFeed = _feed;
      _feed = CanteenFeed(newInst);
      prevFeed.dispose();
    }
    if (instChanged || studentChanged) {
      _subscribeCards(resetSelection: studentChanged || instChanged);
    }
  }

  void _subscribeCards({bool resetSelection = false}) {
    _cardsSub?.cancel();
    if (resetSelection) {
      _selectedCardNo = null;
    }
    setState(() {
      _cardsLoading = true;
      _cardsError = null;
    });

    final user = FirebaseAuth.instance.currentUser;
    _cardsSub = CanteenService.instance
        .watchCardsForParent(
          _inst,
          uid: user?.uid,
          email: user?.email,
          studentId: widget.studentId,
        )
        .listen(
          (list) {
            if (!mounted) return;
            setState(() {
              _cards = list;
              _cardsLoading = false;
              _cardsError = null;
              final sid = (widget.studentId ?? '').trim();
              if (_selectedCardNo == null ||
                  !list.any((c) => c.cardNo == _selectedCardNo)) {
                final match = sid.isEmpty
                    ? const <CanteenCard>[]
                    : list.where((c) => c.studentId.trim() == sid).toList();
                _selectedCardNo = match.isNotEmpty
                    ? match.first.cardNo
                    : (list.isEmpty ? null : list.first.cardNo);
              }
            });
            _feed.bindCard(_card?.cardNo);
          },
          onError: (Object e) {
            if (!mounted) return;
            setState(() {
              _cardsLoading = false;
              _cardsError = e;
            });
          },
        );
  }

  @override
  void dispose() {
    _cardsSub?.cancel();
    _feed.dispose();
    _filter.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() job, {String? ok}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
      if (ok != null && mounted) canteenSnack(context, ok);
    } catch (e) {
      if (mounted) canteenSnack(context, canteenErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _topUp() async {
    final c = _card;
    if (c == null) return;
    final done = await CanteenTopUpDialog.show(context, instId: _inst, card: c);
    if (done == true && mounted) {
      canteenSnack(context, 'Bakiye başarıyla yüklendi.');
    }
  }

  Future<void> _payWithQr() async {
    final paid = await CanteenQrPaySheet.show(
      context,
      institutionId: _inst,
      preferredCard: _card,
      defaultRoleLabel: 'Veli',
    );
    if (paid == true && mounted) {
      canteenSnack(context, 'Mobil QR ödemeniz başarıyla tamamlandı.');
    }
  }

  void _setLimit(double v) {
    final c = _card;
    if (c == null) return;
    _run(
      () => CanteenService.instance.setDailyLimit(_inst, c.cardNo, v),
      ok: v <= 0
          ? 'Günlük harcama limiti kaldırıldı (Limitsiz).'
          : 'Günlük harcama limiti ${canteenMoney(v)} olarak güncellendi.',
    );
  }

  void _applyCustomLimit() {
    final raw = _limitCtrl.text.trim().replaceAll(',', '.');
    final v = double.tryParse(raw);
    if (v == null || v < 0) {
      canteenSnack(context, 'Geçerli bir tutar girin.', error: true);
      return;
    }
    _setLimit(v);
    _limitCtrl.clear();
    FocusScope.of(context).unfocus();
  }

  bool _isCategoryBlocked(CanteenCard card, String cat) {
    final target = canteenTrLower(cat.trim());
    return card.blockedCategories.any(
      (b) => canteenTrLower(b.trim()) == target,
    );
  }

  void _toggleCategory(CanteenCard c, String cat, bool blocked) {
    final target = canteenTrLower(cat.trim());
    final next = c.blockedCategories
        .where((b) => canteenTrLower(b.trim()) != target)
        .toList();
    if (blocked) {
      next.add(cat.trim());
    }
    _run(
      () => CanteenService.instance.setBlockedCategories(_inst, c.cardNo, next),
      ok: blocked
          ? '"$cat" kategorisi bloke edildi.'
          : '"$cat" blokesi kaldırıldı.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCanteenBg,
      body: LayoutBuilder(
        builder: (context, cons) {
          final pad = canteenSidePad(cons.maxWidth);
          return ListenableBuilder(
            listenable: Listenable.merge([_feed, _filter]),
            builder: (context, _) {
              final card = _card;
              final emeraldHeader = _tab == 1 && _txFilter == 'topup';
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: CanteenHeader(
                      title: 'KantiN',
                      subtitle: card?.studentName.isNotEmpty == true
                          ? card!.studentName
                          : (widget.studentName ?? ''),
                      className: card?.className ?? '',
                      card: card,
                      todaySpent: _feed.todaySpent,
                      loading: _cardsLoading,
                      sidePad: pad,
                      emeraldTheme: emeraldHeader,
                      onBack: Navigator.of(context).canPop()
                          ? () => Navigator.of(context).maybePop()
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Tooltip(
                            message: 'Karekod Okut & Öde',
                            child: Material(
                              color: Colors.white.withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: _payWithQr,
                                child: const SizedBox(
                                  width: 38,
                                  height: 38,
                                  child: Icon(
                                    Icons.qr_code_scanner_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (card != null) ...[
                            const SizedBox(width: 6),
                            Tooltip(
                              message: 'Bakiye Yükle',
                              child: Material(
                                color: Colors.white.withValues(alpha: 0.20),
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: _topUp,
                                  child: const SizedBox(
                                    width: 38,
                                    height: 38,
                                    child: Icon(
                                      Icons.add_card_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(pad, 6, pad, 28),
                    sliver: _buildBody(card, emeraldHeader),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBody(CanteenCard? card, bool emeraldHeader) {
    if (_cardsLoading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(36),
          child: Center(child: CircularProgressIndicator(color: kCanteenRed)),
        ),
      );
    }
    if (_cardsError != null) {
      return SliverToBoxAdapter(
        child: CanteenMessageBox(
          text: 'Kart bilgisi alınamadı: ${canteenErrorText(_cardsError!)}',
          icon: Icons.error_outline_rounded,
          error: true,
        ),
      );
    }
    if (card == null) {
      return SliverToBoxAdapter(
        child: Column(
          children: [
            const CanteenMessageBox(
              text:
                  'Hesabınıza bağlı bir kantin kartı bulunamadı.\nKart tanımlaması için okul yönetimiyle iletişime geçebilir veya kasadaki karekodu okutarak doğrudan ödeme yapabilirsiniz.',
              icon: Icons.credit_card_off_rounded,
            ),
            FilledButton.icon(
              style: canteenFilledStyle(),
              onPressed: _payWithQr,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 19),
              label: const Text('Kasadaki Karekodu Okut & Öde'),
            ),
          ],
        ),
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        // Birden fazla öğrenci kartı varsa seçici çubuk
        if (_cards.length > 1)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final c in _cards)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _StudentCardChip(
                          card: c,
                          selected: c.cardNo == card.cardNo,
                          onTap: () {
                            setState(() => _selectedCardNo = c.cardNo);
                            _feed.bindCard(c.cardNo);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

        // Hızlı Aksiyonlar (4'lü İkon Kartları: Bakiye Yükle • QR ile Öde • Hareketler • Ürünler)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: CanteenQuickAction(
                    icon: Icons.add_rounded,
                    label: 'Bakiye Yükle',
                    color: kCanteenRed,
                    onTap: _topUp,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CanteenQuickAction(
                    icon: Icons.qr_code_scanner_rounded,
                    label: 'QR ile Öde',
                    color: const Color(0xFF4F46E5),
                    onTap: _payWithQr,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CanteenQuickAction(
                    icon: Icons.swap_horiz_rounded,
                    label: 'Hareketler',
                    color: kCanteenEmerald,
                    onTap: () => setState(() => _tab = 1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CanteenQuickAction(
                    icon: Icons.lunch_dining_rounded,
                    label: 'Ürünler',
                    color: kCanteenOrange,
                    onTap: () => setState(() => _tab = 2),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Sekme Çubuğu
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: CanteenTabBar(
              labels: const [
                'Kart & Limit',
                'İşlem Hareketleri',
                'Kantin Ürünleri',
              ],
              index: _tab,
              emeraldActive: emeraldHeader,
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
        ),

        if (_tab == 0)
          SliverToBoxAdapter(child: _buildManageTab(card))
        else if (_tab == 1)
          CanteenTransactionsSliver(
            feed: _feed,
            filter: _txFilter,
            onFilter: (v) => setState(() => _txFilter = v),
          )
        else
          CanteenProductsSliver(
            feed: _feed,
            model: _filter,
            blockedCategories: card.blockedCategories,
            blockedProductIds: card.blockedProductIds,
          ),
      ],
    );
  }

  Widget _buildManageTab(CanteenCard card) {
    final categories = mergeCanteenCategories(
      _feed.categories,
      card.blockedCategories,
    );
    final blockedCount = card.blockedCategories.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Kart Kullanım Durumu (Aktif / Pasif)
        CanteenCardStatusCard(
          isActive: card.isActive,
          enabled: !_busy,
          onChanged: (v) => _run(
            () => CanteenService.instance.setCardActive(_inst, card.cardNo, v),
            ok: v ? 'Kart kullanıma açıldı.' : 'Kart pasif duruma alındı.',
          ),
        ),

        // 2. Günlük Harcama Limiti (Figma 2x3 Kırmızı Dairesel Rozet Izgarası)
        CanteenSectionCard(
          title: 'Günlük Harcama Limiti',
          subtitle: 'Günlük harcama üst sınırını belirleyin',
          icon: Icons.speed_rounded,
          accentColor: kCanteenRed,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: card.dailyLimit <= 0
                  ? kCanteenEmeraldSoft
                  : kCanteenRedSoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              card.dailyLimit <= 0 ? 'Limitsiz' : canteenMoney(card.dailyLimit),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: card.dailyLimit <= 0 ? kCanteenEmerald : kCanteenRed,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CanteenLimitBar(spent: _feed.todaySpent, limit: card.dailyLimit),
              const SizedBox(height: 14),
              const Text(
                'Günlük Harcama Limiti Seç',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, cons) {
                  const spacing = 10.0;
                  final cellW = (cons.maxWidth - spacing * 2) / 3;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final limitVal in _limitBadges)
                        SizedBox(
                          width: cellW,
                          child: _LimitBadgeCard(
                            value: limitVal,
                            selected: limitVal <= 0
                                ? card.dailyLimit <= 0
                                : (card.dailyLimit - limitVal).abs() < 0.01,
                            enabled: !_busy,
                            onTap: () => _setLimit(limitVal),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _limitCtrl,
                      enabled: !_busy,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        LengthLimitingTextInputFormatter(8),
                      ],
                      decoration: canteenInputDecoration(
                        hint: 'Özel tutar girin (0 = Limitsiz)',
                        suffixText: '₺',
                      ),
                      onSubmitted: (_) => _applyCustomLimit(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: canteenFilledStyle(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 13,
                      ),
                    ),
                    onPressed: _busy ? null : _applyCustomLimit,
                    child: const Text('Kaydet'),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 3. Ürün Bloke / Kategori Engelleme (Figma Renkli Dairesel İkonlar + Switch Satırları)
        CanteenSectionCard(
          title: 'Ürün Bloke (Kategori Engelleme)',
          subtitle: 'Seçilen kategorilerdeki ürünlerin satışını kısıtlayın',
          icon: Icons.block_rounded,
          accentColor: kCanteenRed,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: blockedCount > 0 ? kCanteenRedSoft : kCanteenEmeraldSoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              blockedCount > 0 ? '$blockedCount Bloke' : 'Kısıtlama Yok',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: blockedCount > 0 ? kCanteenRed : kCanteenEmerald,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Mevcut Kategoriler',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 10),
              // Renkli Dairesel Kategori İkonları Izgarası (4 Sütun)
              LayoutBuilder(
                builder: (context, cons) {
                  const spacing = 8.0;
                  final cols = cons.maxWidth >= 560 ? 4 : 4;
                  final itemW = (cons.maxWidth - spacing * (cols - 1)) / cols;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: 10,
                    children: [
                      for (final cat in categories)
                        SizedBox(
                          width: itemW,
                          child: _CategoryCircleItem(
                            style: canteenCategoryStyle(cat),
                            blocked: _isCategoryBlocked(card, cat),
                            enabled: !_busy,
                            onTap: () => _toggleCategory(
                              card,
                              cat,
                              !_isCategoryBlocked(card, cat),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(height: 1, color: Color(0xFFE2E8F0)),
              ),
              // Kategori Anahtar (Switch) Satırları
              LayoutBuilder(
                builder: (context, cons) {
                  final twoCols = cons.maxWidth >= 520;
                  const gap = 8.0;
                  final rowW = twoCols
                      ? (cons.maxWidth - gap) / 2
                      : cons.maxWidth;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final cat in categories)
                        SizedBox(
                          width: rowW,
                          child: _CategorySwitchRow(
                            style: canteenCategoryStyle(cat),
                            blocked: _isCategoryBlocked(card, cat),
                            enabled: !_busy,
                            onChanged: (v) => _toggleCategory(card, cat, v),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StudentCardChip extends StatelessWidget {
  final CanteenCard card;
  final bool selected;
  final VoidCallback onTap;

  const _StudentCardChip({
    required this.card,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = card.studentName.isEmpty ? card.cardNo : card.studentName;
    return Material(
      color: selected ? kCanteenRed : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? kCanteenRed : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: selected
                    ? Colors.white.withValues(alpha: 0.22)
                    : kCanteenRedSoft,
                child: Icon(
                  Icons.person_rounded,
                  size: 15,
                  color: selected ? Colors.white : kCanteenRed,
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    canteenMoney(card.balance),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? Colors.white.withValues(alpha: 0.85)
                          : const Color(0xFF64748B),
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
}

class _LimitBadgeCard extends StatelessWidget {
  final double value;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _LimitBadgeCard({
    required this.value,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final unlimited = value <= 0;
    final circleLabel = unlimited ? '∞' : '${value.toInt()}₺';
    final textLabel = unlimited ? 'Limitsiz' : '${value.toInt()} ₺';

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? kCanteenRedSoft : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? kCanteenRed : const Color(0xFFE2E8F0),
            width: selected ? 1.6 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: kCanteenRed.withValues(alpha: 0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [kCanteenRed, kCanteenRedLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: kCanteenRed.withValues(alpha: 0.30),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      circleLabel,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: unlimited ? 19 : 12.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                textLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: selected ? kCanteenRedDark : const Color(0xFF1E293B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCircleItem extends StatelessWidget {
  final CanteenCategoryStyle style;
  final bool blocked;
  final bool enabled;
  final VoidCallback onTap;

  const _CategoryCircleItem({
    required this.style,
    required this.blocked,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: blocked ? kCanteenRedSoft : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: blocked ? kCanteenRed : const Color(0xFFEDF2F7),
            width: blocked ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: style.color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: style.color.withValues(alpha: 0.28),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(style.icon, color: Colors.white, size: 22),
                ),
                if (blocked)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: kCanteenRed,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.8),
                      ),
                      child: const Icon(
                        Icons.block_rounded,
                        size: 11,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              style.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: blocked ? kCanteenRedDark : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategorySwitchRow extends StatelessWidget {
  final CanteenCategoryStyle style;
  final bool blocked;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _CategorySwitchRow({
    required this.style,
    required this.blocked,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 11, right: 6, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: blocked
            ? kCanteenRedSoft.withValues(alpha: 0.55)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: blocked ? const Color(0xFFFECDD3) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: style.color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(style.icon, color: style.color, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  style.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: blocked ? kCanteenRedDark : const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  blocked ? 'Satışa kapalı (Blokeli)' : 'Satışa açık',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: blocked ? kCanteenRed : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: blocked,
            activeTrackColor: kCanteenRed,
            activeThumbColor: Colors.white,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}
