import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/canteen/canteen_models.dart';
import '../../services/canteen_service.dart';
import 'canteen_qr_pay_sheet.dart';
import 'canteen_user_widgets.dart';

/// Öğrenci / Öğretmen / Personel kantin ekranı: kasadaki karekodu okutarak
/// anında mobil ödeme, bakiye ve günlük harcama limiti takibi, işlem hareketleri
/// ve kantin ürünleri.
class CanteenStudentScreen extends StatefulWidget {
  final String institutionId;
  final String studentId;
  final String? studentName;
  final bool allowSelfCreateWallet;
  final String roleLabel;

  const CanteenStudentScreen({
    super.key,
    required this.institutionId,
    required this.studentId,
    this.studentName,
    this.allowSelfCreateWallet = false,
    this.roleLabel = 'Öğrenci',
  });

  @override
  State<CanteenStudentScreen> createState() => _CanteenStudentScreenState();
}

class _CanteenStudentScreenState extends State<CanteenStudentScreen> {
  late CanteenFeed _feed;
  final CanteenProductFilterModel _filter = CanteenProductFilterModel();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _cardSub;

  CanteenCard? _card;
  bool _loading = true;
  bool _creatingWallet = false;
  Object? _error;
  int _tab = 0;
  String _txFilter = 'all';

  String get _inst => widget.institutionId.trim().toUpperCase();

  @override
  void initState() {
    super.initState();
    _feed = CanteenFeed(_inst);
    _subscribeCard();
  }

  @override
  void didUpdateWidget(covariant CanteenStudentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldInst = oldWidget.institutionId.trim().toUpperCase();
    final instChanged = oldInst != _inst;
    final studentChanged =
        oldWidget.studentId.trim() != widget.studentId.trim();

    if (instChanged) {
      final prev = _feed;
      _feed = CanteenFeed(_inst);
      prev.dispose();
    }
    if (instChanged || studentChanged) {
      _subscribeCard();
    }
  }

  void _subscribeCard() {
    _cardSub?.cancel();
    setState(() {
      _loading = true;
      _error = null;
    });

    final sid = widget.studentId.trim();
    if (sid.isEmpty) {
      setState(() {
        _card = null;
        _loading = false;
      });
      _feed.bindCard(null);
      return;
    }

    _cardSub = FirebaseFirestore.instance
        .collection(CanteenService.cardsCollection)
        .where('studentId', isEqualTo: sid)
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            CanteenCard? found;
            for (final d in snap.docs) {
              final c = CanteenCard.fromDoc(d);
              if (c.institutionId == _inst) {
                found = c;
                break;
              }
            }
            setState(() {
              _card = found;
              _loading = false;
              _error = null;
            });
            _feed.bindCard(found?.cardNo);
          },
          onError: (Object e) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _error = e;
            });
          },
        );
  }

  @override
  void dispose() {
    _cardSub?.cancel();
    _feed.dispose();
    _filter.dispose();
    super.dispose();
  }

  Future<void> _openQrScanner() async {
    final paid = await CanteenQrPaySheet.show(
      context,
      institutionId: _inst,
      preferredCard: _card,
      defaultRoleLabel: widget.roleLabel,
    );
    if (paid == true && mounted) {
      canteenSnack(context, 'Mobil QR ödemeniz başarıyla tamamlandı.');
    }
  }

  Future<void> _topUpWallet() async {
    final c = _card;
    if (c == null) return;
    final done = await CanteenTopUpDialog.show(context, instId: _inst, card: c);
    if (done == true && mounted) {
      canteenSnack(context, 'Bakiye başarıyla yüklendi.');
    }
  }

  Future<void> _createPersonalWallet() async {
    if (_creatingWallet) return;
    final user = FirebaseAuth.instance.currentUser;
    final uid = widget.studentId.trim().isNotEmpty
        ? widget.studentId.trim()
        : (user?.uid ?? '');
    if (uid.isEmpty) return;

    setState(() => _creatingWallet = true);
    try {
      await CanteenService.instance.ensurePersonalWalletCard(
        instId: _inst,
        uid: uid,
        fullName: (widget.studentName ?? user?.displayName ?? '').trim(),
        roleLabel: widget.roleLabel,
        email: user?.email,
      );
      if (mounted) {
        canteenSnack(context, 'Dijital kantin cüzdanınız oluşturuldu.');
      }
    } catch (e) {
      if (mounted) {
        canteenSnack(context, canteenErrorText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _creatingWallet = false);
    }
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
                      className: card?.className.isNotEmpty == true
                          ? card!.className
                          : (widget.allowSelfCreateWallet
                                ? widget.roleLabel
                                : ''),
                      card: card,
                      todaySpent: _feed.todaySpent,
                      loading: _loading,
                      sidePad: pad,
                      emeraldTheme: emeraldHeader,
                      onBack: Navigator.of(context).canPop()
                          ? () => Navigator.of(context).maybePop()
                          : null,
                      trailing: Tooltip(
                        message: 'Karekod Okut & Öde',
                        child: Material(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _openQrScanner,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.qr_code_scanner_rounded,
                                    color: Colors.white,
                                    size: 19,
                                  ),
                                  SizedBox(width: 5),
                                  Text(
                                    'QR Öde',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
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
    if (_loading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(36),
          child: Center(child: CircularProgressIndicator(color: kCanteenRed)),
        ),
      );
    }
    if (_error != null) {
      return SliverToBoxAdapter(
        child: CanteenMessageBox(
          text: 'Kart bilgisi alınamadı: ${canteenErrorText(_error!)}',
          icon: Icons.error_outline_rounded,
          error: true,
        ),
      );
    }
    if (card == null) {
      return SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ScanCashierQrBanner(onScan: _openQrScanner),
            const SizedBox(height: 12),
            if (widget.allowSelfCreateWallet)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFEDF2F7)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: kCanteenRedSoft,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: kCanteenRed,
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Dijital Kantin Cüzdanınızı Oluşturun',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Kendi adınıza dijital kantin cüzdanı açarak bakiye yükleyebilir ve kasadaki karekodu okutarak tek dokunuşla ödeme yapabilirsiniz.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: canteenFilledStyle(),
                      onPressed: _creatingWallet ? null : _createPersonalWallet,
                      icon: _creatingWallet
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.add_card_rounded, size: 18),
                      label: const Text('Dijital Cüzdanımı Oluştur'),
                    ),
                  ],
                ),
              )
            else
              const CanteenMessageBox(
                text:
                    'Adınıza tanımlı bir kantin kartı bulunamadı.\nKart tanımlaması için okul yönetimiyle iletişime geçebilir veya üstteki butonla kasadaki karekodu okutabilirsiniz.',
                icon: Icons.credit_card_off_rounded,
              ),
          ],
        ),
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ScanCashierQrBanner(
              onScan: _openQrScanner,
              onTopUp: _topUpWallet,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: CanteenTabBar(
              labels: const [
                'Mobil QR Kartım',
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
          SliverToBoxAdapter(child: _buildCardTab(card))
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

  Widget _buildCardTab(CanteenCard card) {
    final recentTxs = _feed.txs.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Figma Koyu Antrasit Mobil Ödeme QR Kartı (#2B2F36 + Altın Köşe Çerçevesi)
        _DarkMobilePaymentQrCard(card: card),
        const SizedBox(height: 14),

        // 2. Bugünkü Harcamam ve Günlük Limit
        CanteenSectionCard(
          title: 'Bugünkü Harcamam & Limit',
          subtitle: 'Günlük harcama durumunuz anlık güncellenir',
          icon: Icons.speed_rounded,
          accentColor: kCanteenOrange,
          child: CanteenLimitBar(
            spent: _feed.todaySpent,
            limit: card.dailyLimit,
          ),
        ),

        // 3. Veli Tarafından Bloke Edilen Kategoriler
        if (card.blockedCategories.isNotEmpty)
          CanteenSectionCard(
            title: 'Kısıtlı Ürün Kategorileri',
            subtitle: 'Veliniz tarafından bu kategorilerde alım kapatılmıştır',
            icon: Icons.block_rounded,
            accentColor: kCanteenRed,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final cat in card.blockedCategories)
                  _BlockedCategoryPill(style: canteenCategoryStyle(cat)),
              ],
            ),
          ),

        // 4. Son İşlem Hareketleri Özeti
        if (recentTxs.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Son İşlemlerim',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: kCanteenRed,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 32),
                  ),
                  onPressed: () => setState(() => _tab = 1),
                  icon: const Text(
                    'Tümünü Gör',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  label: const Icon(Icons.arrow_forward_ios_rounded, size: 12),
                ),
              ],
            ),
          ),
          for (final tx in recentTxs) CanteenTransactionTile(tx: tx),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FIGMA KOYU ANTRASİT MOBİL ÖDEME QR KARTI (#2B2F36 + Altın Köşe Çerçevesi)
// ═══════════════════════════════════════════════════════════════════════════

class _DarkMobilePaymentQrCard extends StatelessWidget {
  final CanteenCard card;

  const _DarkMobilePaymentQrCard({required this.card});

  @override
  Widget build(BuildContext context) {
    final qrData = 'KANTIN:${card.cardNo}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kCanteenDarkCard, Color(0xFF1E2228)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF3E444F), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x280F172A),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // Üst Başlık & "Kasada Okutun" Altın Rozet
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
                  Icons.qr_code_scanner_rounded,
                  color: Color(0xFFFBBF24),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mobil Ödeme',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Kantin Hızlı Geçiş Kodu',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.sensors_rounded,
                      size: 14,
                      color: Color(0xFF1E2228),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Kasada Okutun',
                      style: TextStyle(
                        color: Color(0xFF1E2228),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          // Parlayan Altın/Kehribar Köşeli QR Çerçevesi
          Center(
            child: CustomPaint(
              painter: _GoldQrBracketsPainter(active: card.isActive),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Opacity(
                  opacity: card.isActive ? 1.0 : 0.45,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 14,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: qrData,
                      size: 180,
                      backgroundColor: Colors.white,
                      errorStateBuilder: (_, _) => const SizedBox(
                        width: 180,
                        height: 180,
                        child: Center(
                          child: Text(
                            'QR oluşturulamadı',
                            style: TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Monospace Kart Numarası Çipi (Kopyalanabilir)
          Material(
            color: const Color(0xFF363C46),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Clipboard.setData(ClipboardData(text: card.cardNo));
                canteenSnack(context, 'Kart numarası kopyalandı.');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF4B5260)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.credit_card_rounded,
                      color: Color(0xFFFBBF24),
                      size: 17,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        card.cardNo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.copy_rounded,
                      color: Color(0xFF94A3B8),
                      size: 15,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Alt Durum Rozeti
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: card.isActive
                      ? const Color(0xFF4ADE80)
                      : const Color(0xFFF87171),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  card.isActive
                      ? 'Kartınız kullanıma açık • Kasada QR veya kart no gösterebilirsiniz'
                      : 'Kartınız pasif durumda (veliniz tarafından kapatılmış olabilir)',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: card.isActive
                        ? const Color(0xFFCBD5E1)
                        : const Color(0xFFFCA5A5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GoldQrBracketsPainter extends CustomPainter {
  final bool active;

  const _GoldQrBracketsPainter({required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final color = active ? const Color(0xFFFBBF24) : const Color(0xFF94A3B8);

    // Dış kehribar ışıma
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    // Keskin altın köşe çizgileri
    final bracketPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    const len = 34.0;
    const r = 16.0;
    final w = size.width;
    final h = size.height;

    final path = Path()
      // Sol Üst
      ..moveTo(0, len)
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..lineTo(len, 0)
      // Sağ Üst
      ..moveTo(w - len, 0)
      ..lineTo(w - r, 0)
      ..quadraticBezierTo(w, 0, w, r)
      ..lineTo(w, len)
      // Sol Alt
      ..moveTo(0, h - len)
      ..lineTo(0, h - r)
      ..quadraticBezierTo(0, h, r, h)
      ..lineTo(len, h)
      // Sağ Alt
      ..moveTo(w - len, h)
      ..lineTo(w - r, h)
      ..quadraticBezierTo(w, h, w, h - r)
      ..lineTo(w, h - len);

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, bracketPaint);
  }

  @override
  bool shouldRepaint(covariant _GoldQrBracketsPainter oldDelegate) =>
      oldDelegate.active != active;
}

class _BlockedCategoryPill extends StatelessWidget {
  final CanteenCategoryStyle style;

  const _BlockedCategoryPill({required this.style});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: kCanteenRedSoft.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECDD3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 15, color: kCanteenRed),
          const SizedBox(width: 6),
          Text(
            style.name,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: kCanteenRedDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanCashierQrBanner extends StatelessWidget {
  final VoidCallback onScan;
  final VoidCallback? onTopUp;

  const _ScanCashierQrBanner({required this.onScan, this.onTopUp});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x264F46E5),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.qr_code_scanner_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kasada Karekod Okut & Öde',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Kantin ekranındaki karekodu okutun veya 6 haneli kodu girin.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFFE0E7FF),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (onTopUp != null) ...[
            IconButton(
              tooltip: 'Bakiye Yükle',
              onPressed: onTopUp,
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.18),
                minimumSize: const Size(38, 38),
              ),
              icon: const Icon(
                Icons.add_card_rounded,
                color: Colors.white,
                size: 19,
              ),
            ),
            const SizedBox(width: 6),
          ],
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFBBF24),
              foregroundColor: const Color(0xFF1E2228),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            onPressed: onScan,
            child: const Text('Karekod Okut'),
          ),
        ],
      ),
    );
  }
}
