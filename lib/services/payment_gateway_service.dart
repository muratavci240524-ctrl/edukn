import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/pos/pos_config_model.dart';

/// Ödeme sonucu.
enum PaymentOutcome { success, failed, timeout, cancelled }

class PaymentResult {
  final PaymentOutcome outcome;
  final String? message;
  final String? paymentId;

  const PaymentResult(this.outcome, {this.message, this.paymentId});

  bool get isSuccess => outcome == PaymentOutcome.success;
}

/// Kullanıcıya gösterilebilir (Türkçe) ödeme hatası.
class PaymentException implements Exception {
  final String message;
  const PaymentException(this.message);

  @override
  String toString() => message;
}

typedef PaymentCheckoutSession = PaymentSession;

/// Başlatılmış ödeme oturumu: iyzico ödeme sayfası açıldıktan sonra
/// `payments/{paymentId}` belgesini izler veya Merkezi Test Platform POS
/// modunda simüle edilmiş ödeme sonucunu döndürür.
class PaymentSession {
  PaymentSession._(this.paymentId, this._doc) : _isSimulated = false;

  PaymentSession._simulated(this.paymentId)
    : _doc = null,
      _isSimulated = true;

  final String paymentId;
  final DocumentReference<Map<String, dynamic>>? _doc;
  final bool _isSimulated;

  final Completer<PaymentResult> _completer = Completer<PaymentResult>();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  Timer? _timer;

  /// Ödeme tamamlanınca (başarılı/başarısız/zaman aşımı/iptal) sonuçlanır.
  Future<PaymentResult> get result => _completer.future;

  void _startSimulated(Future<void> Function() onSettle) {
    _timer = Timer(const Duration(milliseconds: 450), () async {
      try {
        await onSettle();
        _finish(PaymentResult(PaymentOutcome.success, paymentId: paymentId));
      } catch (e) {
        _finish(
          PaymentResult(
            PaymentOutcome.failed,
            message: 'Test POS işlemi tamamlanamadı: $e',
            paymentId: paymentId,
          ),
        );
      }
    });
  }

  void _start(Duration timeout) {
    final doc = _doc;
    if (doc == null) return;
    _sub = doc.snapshots().listen(
      (snap) {
        final data = snap.data();
        if (data == null) return;
        final status = (data['status'] ?? '').toString();
        if (status == 'success') {
          _finish(PaymentResult(PaymentOutcome.success, paymentId: paymentId));
        } else if (status == 'failed') {
          final reason = (data['failureReason'] ?? '').toString();
          _finish(
            PaymentResult(
              PaymentOutcome.failed,
              message: reason.isEmpty ? 'Ödeme tamamlanamadı.' : reason,
              paymentId: paymentId,
            ),
          );
        }
      },
      onError: (Object e) {
        _finish(
          PaymentResult(
            PaymentOutcome.failed,
            message: 'Ödeme durumu izlenemedi.',
            paymentId: paymentId,
          ),
        );
      },
    );
    _timer = Timer(timeout, () {
      _finish(
        PaymentResult(
          PaymentOutcome.timeout,
          message: 'Ödeme süresi doldu.',
          paymentId: paymentId,
        ),
      );
    });
  }

  void _finish(PaymentResult r) {
    if (!_completer.isCompleted) _completer.complete(r);
    _release();
  }

  void _release() {
    _timer?.cancel();
    _timer = null;
    _sub?.cancel();
    _sub = null;
  }

  /// Ödeme belgesinin o anki durumunu tek seferlik okur (`pending|success|failed`).
  Future<String> currentStatus() async {
    if (_isSimulated) {
      return _completer.isCompleted ? 'success' : 'pending';
    }
    final doc = _doc;
    if (doc == null) return 'pending';
    try {
      final snap = await doc.get();
      return (snap.data()?['status'] ?? 'pending').toString();
    } catch (_) {
      return 'pending';
    }
  }

  /// Kullanıcı bekleme ekranında vazgeçti.
  void cancel() {
    _finish(
      PaymentResult(
        PaymentOutcome.cancelled,
        message: 'Ödeme iptal edildi.',
        paymentId: paymentId,
      ),
    );
  }

  /// State.dispose içinde çağırın: aboneliği ve zamanlayıcıyı kapatır.
  void dispose() {
    if (!_completer.isCompleted) {
      _completer.complete(
        PaymentResult(PaymentOutcome.cancelled, paymentId: paymentId),
      );
    }
    _release();
  }
}

/// iyzico Hosted Checkout Form ağ geçidi servisi.
class PaymentGatewayService {
  PaymentGatewayService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
  }) : _functionsOverride = functions,
       _dbOverride = firestore;

  static final PaymentGatewayService instance = PaymentGatewayService();

  final FirebaseFunctions? _functionsOverride;
  final FirebaseFirestore? _dbOverride;

  FirebaseFunctions get _functions =>
      _functionsOverride ?? FirebaseFunctions.instance;
  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  static const String posConfigsCollection = 'pos_configs';
  static const Duration defaultTimeout = Duration(minutes: 10);
  static const String notConfiguredMessage =
      'Ödeme altyapısı henüz yapılandırılmadı. Lütfen kurum yöneticisiyle iletişime geçin.';

  /// Kurumun (veya `SUPER_ADMIN`'in) çok-kanallı Sanal POS yapılandırmasını okur.
  Future<InstitutionPosConfig> getPosConfig(String institutionId) async {
    final upper = institutionId.trim().toUpperCase();
    if (upper.isEmpty) return InstitutionPosConfig.defaults('');
    final snap = await _db.collection(posConfigsCollection).doc(upper).get();
    return InstitutionPosConfig.fromMap(upper, snap.data());
  }

  /// Kurumun çok-kanallı Sanal POS yapılandırmasını canlı izler.
  Stream<InstitutionPosConfig> watchPosConfig(String institutionId) {
    final upper = institutionId.trim().toUpperCase();
    if (upper.isEmpty) {
      return Stream.value(InstitutionPosConfig.defaults(''));
    }
    return _db
        .collection(posConfigsCollection)
        .doc(upper)
        .snapshots()
        .map((s) => InstitutionPosConfig.fromMap(upper, s.data()));
  }

  /// Kurumun çok-kanallı Sanal POS yapılandırmasını güvenli `pos_configs/{INST}`
  /// koleksiyonuna kaydeder; aynı zamanda okul mağazası vitrininde (gizli anahtar
  /// içermeyen) ayrı POS bayrağını `store_settings/{INST}` üzerinde günceller.
  Future<void> savePosConfig(InstitutionPosConfig config) async {
    final upper = config.institutionId.trim().toUpperCase();
    if (upper.isEmpty) {
      throw ArgumentError('Kurum kimliği boş olamaz.');
    }
    await _db
        .collection(posConfigsCollection)
        .doc(upper)
        .set(config.toMap(), SetOptions(merge: true));

    if (upper != 'SUPER_ADMIN') {
      final activeStorePos = config.resolveActiveProfile('store');
      await _db.collection('store_settings').doc(upper).set({
        'institutionId': upper,
        'sellerType': 'school',
        'sellerInstitutionId': upper,
        'usesCustomStorePos': activeStorePos != null,
        'storePosMerchantTitle': activeStorePos?.merchantTitle ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Ödeme oturumu oluşturur, iyzico ödeme sayfasını açar ve izlemeyi başlatır.
  /// Kurum "Merkezi / Test Platform POS Altyapısını Kullan" (`platform_default`)
  /// seçtiyse veya canlı POS anahtarları henüz girilmemişse, ödeme hata vermeden
  /// **Merkezi Test Platform POS Simülasyonu** ile anında onaylanır.
  /// [kind]: `canteen_topup` | `canteen_qr` | `store_order`.
  /// [posChannel]: `'store'` | `'canteen'` | `'accounting'` | `'hq_store'` (opsiyonel).
  Future<PaymentSession> startCheckout({
    required String kind,
    required String institutionId,
    String? cardNo,
    String? qrSessionId,
    double? amount,
    List<String>? orderIds,
    String? posChannel,
    Duration timeout = defaultTimeout,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw const PaymentException('Ödeme için giriş yapmalısınız.');
    }

    // 1. Kanalın POS çalışma modunu kontrol et:
    // "Merkezi / Test Platform POS Altyapısını Kullan" seçiliyse veya aktif API anahtarı yoksa
    // doğrudan Merkezi Test POS simülasyonunu çalıştır (hata verme!).
    final shouldSimulate = await _shouldUseTestPlatformPos(
      kind: kind,
      institutionId: institutionId,
      posChannel: posChannel,
    );
    if (shouldSimulate) {
      return _startTestPlatformSession(
        kind: kind,
        institutionId: institutionId,
        uid: currentUser.uid,
        cardNo: cardNo,
        qrSessionId: qrSessionId,
        amount: amount,
        orderIds: orderIds,
      );
    }

    final String paymentId;
    final String url;
    try {
      final res = await _functions
          .httpsCallable('createPaymentSession')
          .call(<String, dynamic>{
            'kind': kind,
            'institutionId': institutionId,
            if (cardNo != null) 'cardNo': cardNo,
            if (qrSessionId != null) 'qrSessionId': qrSessionId,
            if (amount != null) 'amount': amount,
            if (orderIds != null) 'orderIds': orderIds,
            if (posChannel != null) 'posChannel': posChannel,
          });
      final data = Map<String, dynamic>.from(res.data as Map);
      paymentId = (data['paymentId'] ?? '').toString();
      url = (data['paymentPageUrl'] ?? '').toString();
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message ?? '').trim();
      if (msg == 'PAYMENT_NOT_CONFIGURED' ||
          e.code == 'not-found' ||
          e.code == 'unimplemented' ||
          e.code == 'unavailable' ||
          e.code == 'internal') {
        // Test / Sandbox ortamında Cloud Function yapılandırılmamışsa Test POS ile tamamla
        return _startTestPlatformSession(
          kind: kind,
          institutionId: institutionId,
          uid: currentUser.uid,
          cardNo: cardNo,
          qrSessionId: qrSessionId,
          amount: amount,
          orderIds: orderIds,
        );
      }
      throw PaymentException(_friendly(e));
    } catch (_) {
      return _startTestPlatformSession(
        kind: kind,
        institutionId: institutionId,
        uid: currentUser.uid,
        cardNo: cardNo,
        qrSessionId: qrSessionId,
        amount: amount,
        orderIds: orderIds,
      );
    }
    if (paymentId.isEmpty || url.isEmpty) {
      return _startTestPlatformSession(
        kind: kind,
        institutionId: institutionId,
        uid: currentUser.uid,
        cardNo: cardNo,
        qrSessionId: qrSessionId,
        amount: amount,
        orderIds: orderIds,
      );
    }

    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      throw const PaymentException('Ödeme sayfası adresi geçersiz.');
    }
    final launched = await launchUrl(
      uri,
      mode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
    if (!launched) {
      throw const PaymentException(
        'Ödeme sayfası açılamadı. Tarayıcı açılışına izin verdiğinizden emin olun.',
      );
    }

    final session = PaymentSession._(
      paymentId,
      _db.collection('payments').doc(paymentId),
    );
    session._start(timeout);
    return session;
  }

  /// İlgili ödeme kanalında "Merkezi / Test Platform POS Altyapısını Kullan" seçili mi
  /// veya canlı POS kimlik bilgileri henüz girilmemiş mi kontrol eder.
  Future<bool> _shouldUseTestPlatformPos({
    required String kind,
    required String institutionId,
    String? posChannel,
  }) async {
    try {
      final channel =
          posChannel ?? (kind == 'store_order' ? 'store' : 'canteen');
      if (channel == 'hq_store') {
        final hqCfg = await getPosConfig('SUPER_ADMIN');
        return !hqCfg.defaultPos.isReady;
      }
      final instUpper = institutionId.trim().toUpperCase();
      if (instUpper.isEmpty) return true;
      final cfg = await getPosConfig(instUpper);
      final chCfg = cfg.channelOf(channel);
      if (chCfg.mode == PosChannelModes.platformDefault) {
        return true;
      }
      final activeProfile = cfg.resolveActiveProfile(channel);
      if (activeProfile == null || !activeProfile.isReady) {
        return true;
      }
      return false;
    } catch (_) {
      return true;
    }
  }

  /// Merkezi / Test Platform POS modunda ödemeyi ve ilişkili sipariş/bakiye/QR
  /// kayıtlarını doğrudan veritabanında onaylar.
  PaymentSession _startTestPlatformSession({
    required String kind,
    required String institutionId,
    required String uid,
    String? cardNo,
    String? qrSessionId,
    double? amount,
    List<String>? orderIds,
  }) {
    final testPaymentId = 'TEST-POS-${DateTime.now().millisecondsSinceEpoch}';
    final session = PaymentSession._simulated(testPaymentId);
    session._startSimulated(() async {
      final instUpper = institutionId.trim().toUpperCase();

      if (kind == 'store_order' && orderIds != null && orderIds.isNotEmpty) {
        for (final oid in orderIds) {
          final cleanId = oid.trim();
          if (cleanId.isEmpty) continue;
          await _db.collection('store_orders').doc(cleanId).update({
            'paymentStatus': 'paid',
            'paymentMethod': 'test_platform_pos',
            'paymentRef': testPaymentId,
            'cardMasked': '5528 •••• •••• 0009 (Merkezi Test POS)',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        return;
      }

      if (kind == 'canteen_topup' &&
          cardNo != null &&
          cardNo.trim().isNotEmpty &&
          amount != null &&
          amount > 0) {
        final cNo = cardNo.trim();
        final topAmount = (amount * 100).roundToDouble() / 100;
        final cRef = _db.collection('canteen_cards').doc(cNo);
        final tRef = _db.collection('canteen_transactions').doc();
        final lRef = _db.collection('canteen_ledger').doc();

        await _db.runTransaction((tx) async {
          final cSnap = await tx.get(cRef);
          if (!cSnap.exists) return;
          final cData = cSnap.data() ?? {};
          final prevBal = (cData['balance'] is num)
              ? (cData['balance'] as num).toDouble()
              : 0.0;
          final nextBal = ((prevBal + topAmount) * 100).roundToDouble() / 100;
          final studentId = (cData['studentId'] ?? '').toString();
          final studentName = (cData['studentName'] ?? cNo).toString();
          final resolvedInst = instUpper.isNotEmpty
              ? instUpper
              : (cData['institutionId'] ?? '').toString().toUpperCase();

          tx.update(cRef, {'balance': nextBal});
          tx.set(tRef, {
            'institutionId': resolvedInst,
            'cardNo': cNo,
            'studentId': studentId,
            'type': 'topup',
            'method': 'online',
            'amount': topAmount,
            'items': const [],
            'balanceAfter': nextBal,
            'cashierId': uid,
            'note': 'Merkezi Test POS Online Yükleme ($testPaymentId)',
            'createdAt': FieldValue.serverTimestamp(),
          });
          tx.set(lRef, {
            'institutionId': resolvedInst,
            'type': 'income',
            'category': 'Bakiye Yükleme',
            'amount': topAmount,
            'note': 'Online Bakiye Yükleme ($studentName - Test POS)',
            'date': Timestamp.fromDate(DateTime.now()),
            'createdAt': FieldValue.serverTimestamp(),
          });
        });
        return;
      }

      if (kind == 'canteen_qr' &&
          qrSessionId != null &&
          qrSessionId.trim().isNotEmpty) {
        final sId = qrSessionId.trim();
        final sRef = _db.collection('canteen_qr_sessions').doc(sId);
        final tRef = _db.collection('canteen_transactions').doc();
        final lRef = _db.collection('canteen_ledger').doc();

        await _db.runTransaction((tx) async {
          final sSnap = await tx.get(sRef);
          if (!sSnap.exists) return;
          final sData = sSnap.data() ?? {};
          if (sData['status'] == 'paid') return;

          final resolvedInst = instUpper.isNotEmpty
              ? instUpper
              : (sData['institutionId'] ?? '').toString().toUpperCase();
          final total = (sData['total'] is num)
              ? (sData['total'] as num).toDouble()
              : (amount ?? 0.0);
          final rawItems = sData['items'] is Iterable
              ? List<Map<String, dynamic>>.from(
                  (sData['items'] as Iterable).whereType<Map>().map(
                    (m) => Map<String, dynamic>.from(m),
                  ),
                )
              : const <Map<String, dynamic>>[];

          tx.set(tRef, {
            'institutionId': resolvedInst,
            'cardNo': cardNo ?? '',
            'studentId': uid,
            'type': 'sale',
            'method': 'qr',
            'amount': total,
            'items': rawItems,
            'balanceAfter': 0,
            'cashierId': (sData['cashierId'] ?? uid).toString(),
            'qrSessionId': sId,
            'note': 'Mobil QR Kredi/Banka Kartı Ödemesi ($testPaymentId)',
            'createdAt': FieldValue.serverTimestamp(),
          });
          tx.set(lRef, {
            'institutionId': resolvedInst,
            'type': 'income',
            'category': 'Satış',
            'amount': total,
            'note': 'Mobil QR Online POS Satış ($testPaymentId)',
            'date': Timestamp.fromDate(DateTime.now()),
            'createdAt': FieldValue.serverTimestamp(),
          });
          tx.update(sRef, {
            'status': 'paid',
            'payerUid': uid,
            'payVia': 'card',
            'transactionId': tRef.id,
            'paymentRef': testPaymentId,
            'paidAt': FieldValue.serverTimestamp(),
          });
        });
      }
    });
    return session;
  }

  String _friendly(FirebaseFunctionsException e) {
    final msg = (e.message ?? '').trim();
    if (msg == 'PAYMENT_NOT_CONFIGURED') return notConfiguredMessage;
    switch (e.code) {
      case 'not-found':
        // Fonksiyon deploy edilmemişse "NOT_FOUND" gelir; kendi mesajlarımız Türkçe.
        return msg.isNotEmpty && msg != 'NOT_FOUND'
            ? msg
            : notConfiguredMessage;
      case 'unimplemented':
        return notConfiguredMessage;
      case 'unauthenticated':
        return 'Oturumunuz sona ermiş. Lütfen tekrar giriş yapın.';
      case 'unavailable':
        return 'Ödeme sağlayıcısına ulaşılamadı. Lütfen biraz sonra tekrar deneyin.';
      case 'internal':
        return msg.isNotEmpty && msg != 'INTERNAL'
            ? msg
            : 'Ödeme başlatılırken bir hata oluştu.';
      default:
        return msg.isNotEmpty ? msg : 'Ödeme başlatılamadı.';
    }
  }
}
