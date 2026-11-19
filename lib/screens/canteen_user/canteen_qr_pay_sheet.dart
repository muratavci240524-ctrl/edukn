import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/canteen/canteen_models.dart';
import '../../services/canteen_service.dart';
import '../../services/payment_gateway_service.dart';
import '../../services/user_permission_service.dart';
import 'canteen_user_widgets.dart';

enum _QrPayStep { scan, confirm, onlineWaiting, done }

/// Öğrenci, Veli, Öğretmen ve Personel için evrensel Kantin Mobil QR Okuyucu ve
/// Ödeme Onay Penceresi.
///
/// Kasada `Mobil / QR` sekmesinden üretilen karekodu (`KANTINPAY:<INST>:<ID>`)
/// kamera ile okutarak veya 6 haneli tek kullanımlık ödeme kodunu girerek
/// bakiyeden ya da online kredi/banka kartından (iyzico Sanal POS) ödeme yapar.
class CanteenQrPaySheet extends StatefulWidget {
  final String institutionId;
  final CanteenCard? preferredCard;
  final String defaultRoleLabel;

  const CanteenQrPaySheet({
    super.key,
    required this.institutionId,
    this.preferredCard,
    this.defaultRoleLabel = 'Kullanıcı',
  });

  static Future<bool?> show(
    BuildContext context, {
    required String institutionId,
    CanteenCard? preferredCard,
    String defaultRoleLabel = 'Kullanıcı',
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CanteenQrPaySheet(
        institutionId: institutionId,
        preferredCard: preferredCard,
        defaultRoleLabel: defaultRoleLabel,
      ),
    );
  }

  @override
  State<CanteenQrPaySheet> createState() => _CanteenQrPaySheetState();
}

class _CanteenQrPaySheetState extends State<CanteenQrPaySheet> {
  final CanteenService _svc = CanteenService.instance;
  final TextEditingController _codeCtrl = TextEditingController();
  late final MobileScannerController _scannerCtrl;

  _QrPayStep _step = _QrPayStep.scan;

  bool _resolving = false;
  String? _scanError;
  bool _torchOn = false;

  CanteenQrSession? _session;
  StreamSubscription<CanteenQrSession?>? _sessionSub;

  List<CanteenCard> _cards = const [];
  bool _loadingCards = false;
  String? _selectedCardNo;
  bool _payViaOnlineCard = false;
  bool _creatingWallet = false;
  bool _paying = false;
  String? _payError;

  PaymentSession? _onlineCheckout;
  bool _checkingOnlineStatus = false;
  String? _onlineWaitingHint;

  double? _paidBalanceAfter;
  String _paidSummary = '';

  String get _inst => widget.institutionId.trim().toUpperCase();

  CanteenCard? get _selectedCard {
    if (_payViaOnlineCard) return null;
    for (final c in _cards) {
      if (c.cardNo == _selectedCardNo) return c;
    }
    return _cards.isEmpty ? null : _cards.first;
  }

  @override
  void initState() {
    super.initState();
    _scannerCtrl = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _onlineCheckout?.dispose();
    _scannerCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _onBarcodeDetect(BarcodeCapture capture) {
    if (_step != _QrPayStep.scan || _resolving) return;
    for (final b in capture.barcodes) {
      final raw = (b.rawValue ?? '').trim();
      if (raw.isEmpty) continue;
      if (raw.toUpperCase().startsWith('KANTINPAY:') ||
          RegExp(r'^\d{6}$').hasMatch(raw.replaceAll(RegExp(r'\s+'), ''))) {
        _resolveSession(raw);
        break;
      }
    }
  }

  Future<void> _resolveSession(String rawInput) async {
    final code = rawInput.trim();
    if (code.isEmpty || _resolving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _resolving = true;
      _scanError = null;
    });

    try {
      final found = await _svc.findQrSession(code, fallbackInstId: _inst);
      if (!mounted) return;
      unawaited(_scannerCtrl.stop());
      await _loadCardsForInst(found.institutionId);
      if (!mounted) return;
      _watchActiveSession(found);
      setState(() {
        _session = found;
        _resolving = false;
        _payError = null;
        _step = _QrPayStep.confirm;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _scanError = canteenErrorText(e);
      });
    }
  }

  void _watchActiveSession(CanteenQrSession initial) {
    _sessionSub?.cancel();
    _sessionSub = _svc.watchQrSession(initial.id).listen((live) {
      if (!mounted || live == null) return;
      if (live.status == 'cancelled' && _step == _QrPayStep.confirm) {
        setState(() {
          _payError = 'Karekod kasada iptal edildi veya yenilendi.';
        });
        return;
      }
      if (live.isPaid && _step != _QrPayStep.done) {
        _onlineCheckout?.dispose();
        _onlineCheckout = null;
        setState(() {
          _session = live;
          _paying = false;
          _paidBalanceAfter = live.balanceAfter;
          _paidSummary =
              '${canteenMoney(live.total)} tutarındaki kantin ödemeniz onaylandı.';
          _step = _QrPayStep.done;
        });
      } else {
        setState(() => _session = live);
      }
    });
  }

  Future<void> _loadCardsForInst(String instId) async {
    setState(() => _loadingCards = true);
    try {
      final fetched = await _svc.findPayableCardsForCurrentUser(instId);
      final merged = <String, CanteenCard>{
        for (final c in fetched) c.cardNo: c,
      };
      final pref = widget.preferredCard;
      if (pref != null &&
          pref.institutionId.toUpperCase() == instId.toUpperCase()) {
        merged[pref.cardNo] = merged[pref.cardNo] ?? pref;
      }
      final list = merged.values.toList();
      String? pick = _selectedCardNo;
      if (pick == null || !list.any((c) => c.cardNo == pick)) {
        if (pref != null && list.any((c) => c.cardNo == pref.cardNo)) {
          pick = pref.cardNo;
        } else if (list.isNotEmpty) {
          // Önce bakiyesi yeten aktif kartı tercih et
          final enough = list
              .where((c) => c.isActive && c.balance >= (_session?.total ?? 0))
              .toList();
          pick = enough.isNotEmpty ? enough.first.cardNo : list.first.cardNo;
        } else {
          pick = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _cards = list;
        _selectedCardNo = pick;
        _payViaOnlineCard = list.isEmpty;
        _loadingCards = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingCards = false;
        _payViaOnlineCard = _cards.isEmpty;
      });
    }
  }

  (String uid, String name, String role, String email) _resolvePayerIdentity() {
    final user = FirebaseAuth.instance.currentUser;
    final cached = UserPermissionService.getCachedUserData();
    final uid = user?.uid ?? '';
    final email = (user?.email ?? cached?['email'] ?? '').toString().trim();
    final rawName =
        (cached?['fullName'] ??
                cached?['name'] ??
                cached?['displayName'] ??
                user?.displayName ??
                '')
            .toString()
            .trim();
    final rawRole = (cached?['role'] ?? cached?['userType'] ?? '')
        .toString()
        .toLowerCase();
    String roleLabel = widget.defaultRoleLabel;
    if (rawRole.contains('teacher') || rawRole.contains('ogretmen')) {
      roleLabel = 'Öğretmen';
    } else if (rawRole.contains('parent') || rawRole.contains('veli')) {
      roleLabel = 'Veli';
    } else if (rawRole.contains('student') || rawRole.contains('ogrenci')) {
      roleLabel = 'Öğrenci';
    } else if (rawRole.isNotEmpty && roleLabel == 'Kullanıcı') {
      roleLabel = 'Personel';
    }
    return (uid, rawName.isEmpty ? roleLabel : rawName, roleLabel, email);
  }

  Future<void> _createWalletAndTopUp() async {
    final s = _session;
    if (s == null || _creatingWallet) return;
    final (uid, name, role, email) = _resolvePayerIdentity();
    if (uid.isEmpty) return;

    setState(() {
      _creatingWallet = true;
      _payError = null;
    });
    try {
      final wallet = await _svc.ensurePersonalWalletCard(
        instId: s.institutionId,
        uid: uid,
        fullName: name,
        roleLabel: role,
        email: email,
      );
      await _loadCardsForInst(s.institutionId);
      if (!mounted) return;
      setState(() {
        _creatingWallet = false;
        _selectedCardNo = wallet.cardNo;
        _payViaOnlineCard = false;
      });
      final topped = await CanteenTopUpDialog.show(
        context,
        instId: s.institutionId,
        card: wallet,
      );
      if (topped == true && mounted) {
        await _loadCardsForInst(s.institutionId);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _creatingWallet = false;
        _payError = canteenErrorText(e);
      });
    }
  }

  Future<void> _topUpSelectedCard(CanteenCard card) async {
    final s = _session;
    if (s == null) return;
    final topped = await CanteenTopUpDialog.show(
      context,
      instId: s.institutionId,
      card: card,
    );
    if (topped == true && mounted) {
      await _loadCardsForInst(s.institutionId);
      setState(() => _payError = null);
    }
  }

  Future<void> _confirmPayment() async {
    final s = _session;
    if (s == null || _paying) return;

    if (_payViaOnlineCard) {
      await _startOnlineQrPayment(s);
      return;
    }

    final card = _selectedCard;
    if (card == null) {
      setState(() => _payError = 'Lütfen bir ödeme yöntemi seçin.');
      return;
    }

    final (uid, name, role, _) = _resolvePayerIdentity();
    setState(() {
      _paying = true;
      _payError = null;
    });

    try {
      final res = await _svc.payQrSession(
        sessionId: s.id,
        cardNo: card.cardNo,
        payerUid: uid,
        payerName: name.isEmpty ? card.studentName : name,
        payerRole: role,
      );
      if (!mounted) return;
      setState(() {
        _paying = false;
        _paidBalanceAfter = res.balanceAfter;
        _paidSummary =
            '${canteenMoney(res.total)} tutarındaki harcama "${card.studentName.isEmpty ? card.cardNo : card.studentName}" bakiyesinden ödendi.';
        _step = _QrPayStep.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paying = false;
        _payError = canteenErrorText(e);
      });
    }
  }

  Future<void> _startOnlineQrPayment(CanteenQrSession s) async {
    setState(() {
      _paying = true;
      _payError = null;
      _onlineWaitingHint = null;
    });
    try {
      _onlineCheckout?.dispose();
      final checkout = await PaymentGatewayService.instance.startCheckout(
        kind: 'canteen_qr',
        institutionId: s.institutionId,
        qrSessionId: s.id,
      );
      if (!mounted) {
        checkout.dispose();
        return;
      }
      _onlineCheckout = checkout;
      setState(() {
        _paying = false;
        _step = _QrPayStep.onlineWaiting;
      });

      final res = await checkout.result;
      if (!mounted || _onlineCheckout != checkout) return;
      _onlineCheckout = null;

      if (res.outcome == PaymentOutcome.cancelled) {
        setState(() {
          _checkingOnlineStatus = false;
          _step = _QrPayStep.confirm;
        });
        return;
      }
      if (res.isSuccess) {
        setState(() {
          _checkingOnlineStatus = false;
          _paidBalanceAfter = null;
          _paidSummary =
              '${canteenMoney(s.total)} tutarındaki kantin fişi kredi/banka kartınızla ödendi.';
          _step = _QrPayStep.done;
        });
      } else {
        setState(() {
          _checkingOnlineStatus = false;
          _payError = res.message ?? 'Kart ödemesi tamamlanamadı.';
          _step = _QrPayStep.confirm;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paying = false;
        _payError = canteenErrorText(e);
      });
    }
  }

  Future<void> _checkOnlineStatus() async {
    final checkout = _onlineCheckout;
    if (checkout == null || _checkingOnlineStatus) return;
    setState(() {
      _checkingOnlineStatus = true;
      _onlineWaitingHint = null;
    });
    final status = await checkout.currentStatus();
    if (!mounted || _onlineCheckout != checkout) return;
    if (status == 'success') {
      _onlineCheckout = null;
      checkout.dispose();
      setState(() {
        _checkingOnlineStatus = false;
        _paidSummary =
            '${canteenMoney(_session?.total ?? 0)} tutarındaki kantin fişi ödendi.';
        _step = _QrPayStep.done;
      });
    } else if (status == 'failed') {
      _onlineCheckout = null;
      checkout.dispose();
      setState(() {
        _checkingOnlineStatus = false;
        _payError = 'Ödeme işlemi başarısız oldu.';
        _step = _QrPayStep.confirm;
      });
    } else {
      setState(() {
        _checkingOnlineStatus = false;
        _onlineWaitingHint =
            'Ödeme henüz onaylanmadı. Açılan sekmede 3D Secure işlemini tamamladığınızda kasa otomatik onaylanacaktır.';
      });
    }
  }

  void _backToScan() {
    _sessionSub?.cancel();
    _sessionSub = null;
    setState(() {
      _session = null;
      _payError = null;
      _scanError = null;
      _step = _QrPayStep.scan;
    });
    unawaited(_scannerCtrl.start());
  }

  @override
  Widget build(BuildContext context) {
    final canClose = !_paying && _step != _QrPayStep.onlineWaiting;
    return PopScope(
      canPop: canClose,
      child: Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: SingleChildScrollView(
            child: switch (_step) {
              _QrPayStep.scan => _buildScanView(),
              _QrPayStep.confirm => _buildConfirmView(),
              _QrPayStep.onlineWaiting => _buildOnlineWaitingView(),
              _QrPayStep.done => _buildDoneView(),
            },
          ),
        ),
      ),
    );
  }

  // ── ADIM 1: KAREKOD OKUTMA VEYA 6 HANELİ KOD GİRİŞİ ─────────────────────

  Widget _buildScanView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Figma koyu antrasit Mobil Ödeme kamera alanı (#2B2F36 + Altın köşe)
        Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [kCanteenDarkCard, Color(0xFF1E2228)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBBF24).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
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
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Kasadaki karekodu okutun',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Flaş',
                    onPressed: () async {
                      try {
                        await _scannerCtrl.toggleTorch();
                        if (mounted) setState(() => _torchOn = !_torchOn);
                      } catch (_) {}
                    },
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.10),
                      minimumSize: const Size(34, 34),
                      padding: EdgeInsets.zero,
                    ),
                    icon: Icon(
                      _torchOn
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      size: 18,
                      color: _torchOn ? const Color(0xFFFBBF24) : Colors.white,
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.of(context).pop(false),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.10),
                      minimumSize: const Size(34, 34),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 244,
                height: 244,
                child: CustomPaint(
                  foregroundPainter: const _ScannerGoldFramePainter(),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          MobileScanner(
                            controller: _scannerCtrl,
                            onDetect: _onBarcodeDetect,
                            errorBuilder: (ctx, err, _) => Container(
                              color: const Color(0xFF15181D),
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.videocam_off_rounded,
                                    color: Color(0xFFFBBF24),
                                    size: 34,
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Kamera açılamadı veya izin verilmedi.\nAşağıdan 6 haneli ödeme kodunu girebilirsiniz.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFFCBD5E1),
                                      fontSize: 12,
                                      height: 1.4,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  TextButton.icon(
                                    onPressed: () => _scannerCtrl.start(),
                                    icon: const Icon(
                                      Icons.refresh_rounded,
                                      size: 15,
                                      color: Color(0xFFFBBF24),
                                    ),
                                    label: const Text(
                                      'Tekrar Dene',
                                      style: TextStyle(
                                        color: Color(0xFFFBBF24),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_resolving)
                            Container(
                              color: Colors.black54,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFFFBBF24),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 6 Haneli Manuel Kod Girişi
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '6 Haneli Kasa Ödeme Kodu ile Öde',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Kamera kullanmak istemiyorsanız kasa ekranındaki 6 haneli kodu yazın.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeCtrl,
                      enabled: !_resolving,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                        color: Color(0xFF0F172A),
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: canteenInputDecoration(
                        hint: 'Örn: 482915',
                        prefixIcon: const Icon(
                          Icons.pin_outlined,
                          color: kCanteenRed,
                          size: 20,
                        ),
                      ),
                      onChanged: (v) {
                        if (_scanError != null) {
                          setState(() => _scanError = null);
                        }
                        if (v.trim().length == 6 && !_resolving) {
                          _resolveSession(v);
                        }
                      },
                      onSubmitted: _resolveSession,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: canteenFilledStyle(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                    ),
                    onPressed: _resolving
                        ? null
                        : () => _resolveSession(_codeCtrl.text),
                    child: _resolving
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Sorgula'),
                  ),
                ],
              ),
              if (_scanError != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
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
                          _scanError!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFFB91C1C),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── ADIM 2: FİGMA MOBİL ÖDEME ONAY EKRANI ────────────────────────────────

  Widget _buildConfirmView() {
    final s = _session!;
    final selectedCard = _selectedCard;
    final insufficient =
        !_payViaOnlineCard &&
        selectedCard != null &&
        selectedCard.balance + 0.001 < s.total;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Figma Mor/İndigo Mobil Ödeme Üst Başlığı
        Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: _paying ? null : _backToScan,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                      minimumSize: const Size(34, 34),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Mobil Ödeme Onayı',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '#${s.formattedShortCode}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'ÖDENECEK TUTAR',
                style: TextStyle(
                  color: Color(0xFFE0E7FF),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                canteenMoney(s.total),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                ),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sepet Kalemleri
              const Text(
                'Yapılacak İşlem (Sepet Özeti)',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < s.items.length; i++) ...[
                      if (i > 0)
                        const Divider(height: 14, color: Color(0xFFE2E8F0)),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: kCanteenRedSoft,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${s.items[i].qty}x',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                                color: kCanteenRed,
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              s.items[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          Text(
                            canteenMoney(s.items[i].total),
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Ödeme Aracı Seçimi
              const Text(
                'Ödeme Yöntemi Seçin',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 8),

              if (_loadingCards)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: Center(
                    child: CircularProgressIndicator(color: kCanteenRed),
                  ),
                )
              else ...[
                for (final c in _cards)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PaymentInstrumentTile(
                      selected:
                          !_payViaOnlineCard && _selectedCardNo == c.cardNo,
                      icon: Icons.account_balance_wallet_rounded,
                      iconColor: kCanteenRed,
                      title: c.studentName.isEmpty
                          ? 'Kantin Kartı (${c.cardNo})'
                          : '${c.studentName}${c.className.isEmpty ? '' : ' • ${c.className}'}',
                      subtitle:
                          'Bakiye: ${canteenMoney(c.balance)} • ${c.cardNo}',
                      trailing: c.balance + 0.001 < s.total
                          ? TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: kCanteenRed,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: _paying
                                  ? null
                                  : () => _topUpSelectedCard(c),
                              child: const Text(
                                '+ Bakiye Yükle',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            )
                          : null,
                      onTap: () => setState(() {
                        _payViaOnlineCard = false;
                        _selectedCardNo = c.cardNo;
                        _payError = null;
                      }),
                    ),
                  ),
                if (_cards.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(
                      style: canteenOutlinedStyle(color: kCanteenEmerald),
                      onPressed: _creatingWallet ? null : _createWalletAndTopUp,
                      icon: _creatingWallet
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_card_rounded, size: 18),
                      label: const Text(
                        'Dijital Kantin Cüzdanı Oluştur & Bakiye Yükle',
                      ),
                    ),
                  ),
                _PaymentInstrumentTile(
                  selected: _payViaOnlineCard,
                  icon: Icons.credit_card_rounded,
                  iconColor: const Color(0xFF0284C7),
                  title: 'Kredi / Banka Kartı (Online Sanal POS)',
                  subtitle: 'iyzico 3D Secure ile doğrudan karttan öde',
                  onTap: () => setState(() {
                    _payViaOnlineCard = true;
                    _payError = null;
                  }),
                ),
              ],

              if (insufficient) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFFD97706),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Seçilen kart bakiyesi yetersiz (${canteenMoney(selectedCard.balance)}). Hemen bakiye yükleyebilir veya Kredi/Banka Kartı seçebilirsiniz.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF92400E),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_payError != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
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
                          _payError!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFFB91C1C),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 18),
              // Figma İptal + Kabul / Ödemeyi Onayla buton satırı
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      style: canteenOutlinedStyle(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _paying
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('İptal'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: FilledButton.icon(
                      style: canteenFilledStyle(
                        color: insufficient ? kCanteenEmerald : kCanteenRed,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _paying || s.status != 'pending'
                          ? null
                          : (insufficient
                                ? () => _topUpSelectedCard(selectedCard)
                                : _confirmPayment),
                      icon: _paying
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              insufficient
                                  ? Icons.add_card_rounded
                                  : Icons.check_circle_rounded,
                              size: 19,
                            ),
                      label: Text(
                        _paying
                            ? 'İşleniyor...'
                            : (insufficient
                                  ? 'Bakiye Yükle'
                                  : 'Ödemeyi Onayla'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── ADIM 3: ONLİNE SANAL POS 3D SECURE BEKLEME ──────────────────────────

  Widget _buildOnlineWaitingView() {
    final total = _session?.total ?? 0;
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: const BoxDecoration(
              color: Color(0xFFE0F2FE),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  color: Color(0xFF0284C7),
                  strokeWidth: 3,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            canteenMoney(total),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '3D Secure Ödeme Bekleniyor',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Açılan güvenli ödeme sayfasında kart işlemini tamamladığınızda kasa fişi otomatik ödenecektir.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: Color(0xFF475569),
            ),
          ),
          if (_onlineWaitingHint != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Text(
                _onlineWaitingHint!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF92400E),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: canteenFilledStyle(color: kCanteenEmerald),
              onPressed: _checkingOnlineStatus ? null : _checkOnlineStatus,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Durumu Kontrol Et'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: canteenOutlinedStyle(),
              onPressed: () {
                _onlineCheckout?.cancel();
                _onlineCheckout = null;
                setState(() => _step = _QrPayStep.confirm);
              },
              child: const Text('Vazgeç'),
            ),
          ),
        ],
      ),
    );
  }

  // ── ADIM 4: ÖDEME TAMAMLANDI ────────────────────────────────────────────

  Widget _buildDoneView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: const BoxDecoration(
              color: kCanteenEmeraldSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: kCanteenEmerald,
              size: 46,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Ödeme Tamamlandı!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _paidSummary,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: Color(0xFF475569),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_paidBalanceAfter != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Kalan Bakiye: ',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    canteenMoney(_paidBalanceAfter!),
                    style: const TextStyle(
                      fontSize: 15,
                      color: kCanteenEmerald,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: canteenFilledStyle(color: kCanteenEmerald),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Tamam'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentInstrumentTile extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _PaymentInstrumentTile({
    required this.selected,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? iconColor.withValues(alpha: 0.08)
          : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected ? iconColor : const Color(0xFFE2E8F0),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 6),
                trailing!,
              ] else
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected ? iconColor : const Color(0xFF94A3B8),
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScannerGoldFramePainter extends CustomPainter {
  const _ScannerGoldFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const color = Color(0xFFFBBF24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    const len = 34.0;
    const r = 20.0;
    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(0, len)
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..lineTo(len, 0)
      ..moveTo(w - len, 0)
      ..lineTo(w - r, 0)
      ..quadraticBezierTo(w, 0, w, r)
      ..lineTo(w, len)
      ..moveTo(0, h - len)
      ..lineTo(0, h - r)
      ..quadraticBezierTo(0, h, r, h)
      ..lineTo(len, h)
      ..moveTo(w - len, h)
      ..lineTo(w - r, h)
      ..quadraticBezierTo(w, h, w, h - r)
      ..lineTo(w, h - len);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
