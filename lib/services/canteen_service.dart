import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/canteen/canteen_models.dart';

/// Kullanıcıya gösterilebilir (Türkçe) kantin hatası.
class CanteenException implements Exception {
  final String message;
  const CanteenException(this.message);

  @override
  String toString() => message;
}

/// Sepet satırı. Fiyat ve isim işlem sırasında veritabanından okunur.
class CartLine {
  final String productId;
  final int qty;
  final String name;
  final double price;

  const CartLine({
    required this.productId,
    required this.qty,
    this.name = '',
    this.price = 0,
  });
}

class SaleResult {
  final String transactionId;
  final double total;
  final double? balanceAfter; // kartsız nakit satışta null
  final String? cardNo;
  final List<CanteenTransactionItem> items;

  const SaleResult({
    required this.transactionId,
    required this.total,
    required this.balanceAfter,
    required this.cardNo,
    required this.items,
  });
}

class RefundResult {
  final String refundTransactionId;
  final String saleTransactionId;
  final double refundedAmount;
  final double? balanceAfter;
  final String? cardNo;
  final List<CanteenTransactionItem> refundedItems;
  final bool isFullRefund;

  const RefundResult({
    required this.refundTransactionId,
    required this.saleTransactionId,
    required this.refundedAmount,
    required this.balanceAfter,
    required this.cardNo,
    required this.refundedItems,
    required this.isFullRefund,
  });
}

class CanteenTopProduct {
  final String productId;
  final String name;
  final int qty;
  final double revenue;

  const CanteenTopProduct({
    required this.productId,
    required this.name,
    required this.qty,
    required this.revenue,
  });
}

class CanteenDailyRevenue {
  final DateTime day;
  final double revenue;
  const CanteenDailyRevenue(this.day, this.revenue);
}

class CanteenReport {
  final DateTime from;
  final DateTime to;
  final double totalSales;
  final int saleCount;
  final double totalTopUps;
  final double totalRefunds;
  final Map<String, double> salesByMethod;
  final List<CanteenTopProduct> topProducts;
  final List<CanteenDailyRevenue> dailyRevenue;
  final List<CanteenProduct> lowStock;
  final double ledgerIncome;
  final double ledgerExpense;

  const CanteenReport({
    required this.from,
    required this.to,
    required this.totalSales,
    required this.saleCount,
    required this.totalTopUps,
    required this.totalRefunds,
    required this.salesByMethod,
    required this.topProducts,
    required this.dailyRevenue,
    required this.lowStock,
    required this.ledgerIncome,
    required this.ledgerExpense,
  });

  double get netSales => totalSales - totalRefunds;
  double get averageSale => saleCount == 0 ? 0 : totalSales / saleCount;
  double get ledgerNet => ledgerIncome - ledgerExpense;
}

/// Kantin Modülü Servisi (Firestore).
/// Not: Bileşik indeks gerektirmemek için tek `where` + istemci tarafı sıralama.
class CanteenService {
  CanteenService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _dbOverride = firestore,
      _authOverride = auth;

  static final CanteenService instance = CanteenService();

  final FirebaseFirestore? _dbOverride;
  final FirebaseAuth? _authOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  static const String productsCollection = 'canteen_products';
  static const String warehousesCollection = 'canteen_warehouses';
  static const String movementsCollection = 'canteen_stock_movements';
  static const String cardsCollection = 'canteen_cards';
  static const String transactionsCollection = 'canteen_transactions';
  static const String ledgerCollection = 'canteen_ledger';
  static const String qrSessionsCollection = 'canteen_qr_sessions';

  static const Set<String> paymentMethods = {
    'card',
    'mobile',
    'qr',
    'pos',
    'cash',
    'online',
  };

  static String _up(String s) => s.trim().toUpperCase();

  String get _uid => _auth.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> _col(String name) =>
      _db.collection(name);

  Query<Map<String, dynamic>> _byInst(String col, String instId) =>
      _col(col).where('institutionId', isEqualTo: _up(instId));

  // ═══════════════════════════════════════════════════════════════════════════
  // ÜRÜNLER & DEPOLAR
  // ═══════════════════════════════════════════════════════════════════════════

  Stream<List<CanteenProduct>> watchProducts(String instId) {
    return _byInst(productsCollection, instId).snapshots().map((s) {
      final list = s.docs.map(CanteenProduct.fromDoc).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    });
  }

  Future<void> saveProduct(String instId, CanteenProduct p) async {
    final inst = _up(instId);
    if (p.name.trim().isEmpty) {
      throw const CanteenException('Ürün adı boş olamaz.');
    }
    if (p.price < 0) {
      throw const CanteenException('Fiyat negatif olamaz.');
    }
    final ref = p.id.isEmpty
        ? _col(productsCollection).doc()
        : _col(productsCollection).doc(p.id);
    final data = p.copyWith(institutionId: inst).toMap()
      ..['updatedAt'] = FieldValue.serverTimestamp();
    if (p.id.isEmpty) data['createdAt'] = FieldValue.serverTimestamp();
    await ref.set(data, SetOptions(merge: true));
  }

  Future<void> deleteProduct(String instId, String productId) =>
      _col(productsCollection).doc(productId).delete();

  /// Kantin ürün görselini Firebase Storage'a yükler ve indirme bağlantısını döner.
  Future<String> uploadProductImage({
    required String instId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final inst = _up(instId);
    if (inst.isEmpty) {
      throw const CanteenException('Kurum bilgisi bulunamadı.');
    }
    final lower = fileName.trim().toLowerCase();
    final isPng = lower.endsWith('.png');
    final ext = isPng ? 'png' : 'jpg';
    final contentType = isPng ? 'image/png' : 'image/jpeg';
    final sanitized = fileName
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final finalName = sanitized.isEmpty
        ? '${DateTime.now().millisecondsSinceEpoch}.$ext'
        : '${DateTime.now().millisecondsSinceEpoch}_$sanitized';
    final ref = FirebaseStorage.instance
        .ref()
        .child(productsCollection)
        .child(inst)
        .child(finalName);
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }

  /// Stok düzeltme (+/-). Stok hareketi yazar. Negatif stoğa izin vermez.
  Future<void> adjustStock(
    String instId,
    String productId,
    int delta,
    String note,
  ) async {
    if (delta == 0) return;
    final inst = _up(instId);
    final pRef = _col(productsCollection).doc(productId);
    final mRef = _col(movementsCollection).doc();
    await _db.runTransaction((tx) async {
      final snap = await tx.get(pRef);
      if (!snap.exists) throw const CanteenException('Ürün bulunamadı.');
      final cur = (snap.data()?['stock'] as num?)?.toInt() ?? 0;
      if (cur + delta < 0) {
        throw const CanteenException('Stok negatif olamaz.');
      }
      tx.update(pRef, {
        'stock': cur + delta,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(
        mRef,
        CanteenStockMovement(
          institutionId: inst,
          productId: productId,
          type: delta > 0 ? 'in' : 'out',
          qty: delta.abs(),
          note: note,
          by: _uid,
        ).toMap(),
      );
    });
  }

  Stream<List<CanteenStockMovement>> watchStockMovements(
    String instId, {
    String? productId,
    int limit = 200,
  }) {
    return _byInst(movementsCollection, instId).snapshots().map((s) {
      var list = s.docs.map(CanteenStockMovement.fromDoc).toList();
      if (productId != null) {
        list = list.where((m) => m.productId == productId).toList();
      }
      list.sort(
        (a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
      return (limit > 0 && list.length > limit) ? list.sublist(0, limit) : list;
    });
  }

  Stream<List<CanteenWarehouse>> watchWarehouses(String instId) {
    return _byInst(warehousesCollection, instId).snapshots().map((s) {
      final list = s.docs.map(CanteenWarehouse.fromDoc).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    });
  }

  Future<void> saveWarehouse(String instId, CanteenWarehouse w) async {
    if (w.name.trim().isEmpty) {
      throw const CanteenException('Depo adı boş olamaz.');
    }
    final ref = w.id.isEmpty
        ? _col(warehousesCollection).doc()
        : _col(warehousesCollection).doc(w.id);
    final data = CanteenWarehouse(
      id: w.id,
      institutionId: _up(instId),
      name: w.name,
      description: w.description,
      isActive: w.isActive,
    ).toMap();
    await ref.set(data, SetOptions(merge: true));
  }

  Future<void> deleteWarehouse(String instId, String warehouseId) =>
      _col(warehousesCollection).doc(warehouseId).delete();

  // ═══════════════════════════════════════════════════════════════════════════
  // KARTLAR
  // ═══════════════════════════════════════════════════════════════════════════

  Stream<List<CanteenCard>> watchCards(String instId) {
    return _byInst(cardsCollection, instId).snapshots().map((s) {
      final list = s.docs.map(CanteenCard.fromDoc).toList()
        ..sort(
          (a, b) => a.studentName.toLowerCase().compareTo(
            b.studentName.toLowerCase(),
          ),
        );
      return list;
    });
  }

  /// Velinin çocuklarının kartları (parentUids, parentEmail veya seçili studentId eşleşmesi).
  Stream<List<CanteenCard>> watchCardsForParent(
    String instId, {
    String? uid,
    String? email,
    String? studentId,
    List<String>? studentIds,
  }) {
    final inst = _up(instId);
    final mail = (email ?? '').trim();
    final u = (uid ?? '').trim();
    final sIds = <String>{
      if (studentId != null && studentId.trim().isNotEmpty) studentId.trim(),
      if (studentIds != null)
        ...studentIds.map((e) => e.trim()).where((e) => e.isNotEmpty),
    }.take(10).toList();
    late StreamController<List<CanteenCard>> ctrl;
    final subs = <StreamSubscription>[];
    final byUid = <String, CanteenCard>{};
    final byMail = <String, CanteenCard>{};
    final byStudent = <String, CanteenCard>{};

    void emit() {
      final all = <String, CanteenCard>{...byMail, ...byUid, ...byStudent};
      final list = all.values.where((c) => c.institutionId == inst).toList()
        ..sort((a, b) => a.studentName.compareTo(b.studentName));
      if (!ctrl.isClosed) ctrl.add(list);
    }

    ctrl = StreamController<List<CanteenCard>>(
      onListen: () {
        if (u.isEmpty && mail.isEmpty && sIds.isEmpty) {
          ctrl.add(const []);
          return;
        }
        if (u.isNotEmpty) {
          subs.add(
            _col(
              cardsCollection,
            ).where('parentUids', arrayContains: u).snapshots().listen((s) {
              byUid
                ..clear()
                ..addEntries(
                  s.docs.map((d) => MapEntry(d.id, CanteenCard.fromDoc(d))),
                );
              emit();
            }, onError: ctrl.addError),
          );
        }
        if (mail.isNotEmpty) {
          subs.add(
            _col(
              cardsCollection,
            ).where('parentEmail', isEqualTo: mail).snapshots().listen((s) {
              byMail
                ..clear()
                ..addEntries(
                  s.docs.map((d) => MapEntry(d.id, CanteenCard.fromDoc(d))),
                );
              emit();
            }, onError: ctrl.addError),
          );
        }
        if (sIds.isNotEmpty) {
          final q = sIds.length == 1
              ? _col(cardsCollection).where('studentId', isEqualTo: sIds.first)
              : _col(cardsCollection).where('studentId', whereIn: sIds);
          subs.add(
            q.snapshots().listen((s) {
              byStudent
                ..clear()
                ..addEntries(
                  s.docs.map((d) => MapEntry(d.id, CanteenCard.fromDoc(d))),
                );
              emit();
            }, onError: ctrl.addError),
          );
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
        subs.clear();
      },
    );
    return ctrl.stream;
  }

  /// Kart no, QR içeriği (`KANTIN:<kartNo>` veya düz kart no) ya da öğrenci no ile kart bulur.
  Future<CanteenCard?> findCard(String instId, String cardNoOrQr) async {
    final inst = _up(instId);
    var raw = cardNoOrQr.trim();
    if (raw.isEmpty) return null;
    if (raw.contains(':')) raw = raw.split(':').last.trim();
    if (raw.isEmpty) return null;

    final doc = await _col(cardsCollection).doc(raw).get();
    if (doc.exists) {
      final c = CanteenCard.fromDoc(doc);
      if (c.institutionId == inst) return c;
    }
    final q = await _col(cardsCollection).where('cardNo', isEqualTo: raw).get();
    for (final d in q.docs) {
      final c = CanteenCard.fromDoc(d);
      if (c.institutionId == inst) return c;
    }
    return null;
  }

  Future<CanteenCard?> findCardByStudent(
    String instId,
    String studentId,
  ) async {
    final inst = _up(instId);
    final q = await _col(
      cardsCollection,
    ).where('studentId', isEqualTo: studentId).get();
    for (final d in q.docs) {
      final c = CanteenCard.fromDoc(d);
      if (c.institutionId == inst) return c;
    }
    return null;
  }

  /// Kartı oluşturur/günceller. Mevcut kartın bakiyesi ASLA ezilmez.
  Future<void> saveCard(String instId, CanteenCard c) async {
    if (c.cardNo.trim().isEmpty) {
      throw const CanteenException('Kart numarası boş olamaz.');
    }
    final ref = _col(cardsCollection).doc(c.cardNo.trim());
    final data = c.copyWith(institutionId: _up(instId)).toMap();
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) {
        final existingInst = _up(
          (snap.data()?['institutionId'] ?? '').toString(),
        );
        if (existingInst.isNotEmpty && existingInst != _up(instId)) {
          throw const CanteenException(
            'Bu kart numarası başka bir kurumda kayıtlı.',
          );
        }
        data.remove('balance');
        tx.set(ref, data, SetOptions(merge: true));
      } else {
        data['createdAt'] = FieldValue.serverTimestamp();
        tx.set(ref, data);
      }
    });
  }

  Future<void> setCardActive(String instId, String cardNo, bool active) =>
      _col(cardsCollection).doc(cardNo).update({'isActive': active});

  Future<void> setDailyLimit(String instId, String cardNo, double limit) =>
      _col(
        cardsCollection,
      ).doc(cardNo).update({'dailyLimit': limit < 0 ? 0 : limit});

  Future<void> setBlockedCategories(
    String instId,
    String cardNo,
    List<String> cats,
  ) => _col(cardsCollection).doc(cardNo).update({'blockedCategories': cats});

  // ═══════════════════════════════════════════════════════════════════════════
  // BAKİYE YÜKLEME
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> topUp({
    required String instId,
    required String cardNo,
    required double amount,
    required String method,
    required String cashierId,
  }) async {
    if (amount <= 0) {
      throw const CanteenException('Yükleme tutarı sıfırdan büyük olmalı.');
    }
    if (!paymentMethods.contains(method)) {
      throw const CanteenException('Geçersiz ödeme yöntemi.');
    }
    final inst = _up(instId);
    final cRef = _col(cardsCollection).doc(cardNo);
    final tRef = _col(transactionsCollection).doc();
    final lRef = _col(ledgerCollection).doc();
    await _db.runTransaction((tx) async {
      final snap = await tx.get(cRef);
      if (!snap.exists) throw const CanteenException('Kart bulunamadı.');
      final card = CanteenCard.fromDoc(snap);
      if (card.institutionId != inst) {
        throw const CanteenException('Kart bu kuruma ait değil.');
      }
      final after = _round(card.balance + amount);
      tx.update(cRef, {'balance': after});
      tx.set(
        tRef,
        CanteenTransaction(
          institutionId: inst,
          cardNo: cardNo,
          studentId: card.studentId,
          type: 'topup',
          method: method,
          amount: amount,
          balanceAfter: after,
          cashierId: cashierId,
        ).toMap(),
      );
      tx.set(
        lRef,
        CanteenLedgerEntry(
          institutionId: inst,
          type: 'income',
          category: 'Bakiye Yükleme',
          amount: amount,
          note: '${card.studentName} ($cardNo) - $method',
          date: DateTime.now(),
        ).toMap(),
      );
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SATIŞ
  // ═══════════════════════════════════════════════════════════════════════════

  Future<SaleResult> sell({
    required String instId,
    String? cardNo,
    required List<CartLine> lines,
    required String method,
    required String cashierId,
    String? note,
  }) async {
    final inst = _up(instId);
    if (!paymentMethods.contains(method)) {
      throw const CanteenException('Geçersiz ödeme yöntemi.');
    }
    // Aynı ürünleri birleştir
    final qtyById = <String, int>{};
    for (final l in lines) {
      if (l.qty <= 0) continue;
      qtyById[l.productId] = (qtyById[l.productId] ?? 0) + l.qty;
    }
    if (qtyById.isEmpty) throw const CanteenException('Sepet boş.');

    final hasCard = cardNo != null && cardNo.trim().isNotEmpty;
    final payFromCard = method != 'cash' && method != 'pos';
    if (payFromCard && !hasCard) {
      throw const CanteenException('Kartlı ödeme için kart seçilmelidir.');
    }

    // Günlük limit için bugünkü harcama (işlem dışı sorgu)
    double spentToday = 0;
    if (hasCard && payFromCard) {
      spentToday = await todaySpent(inst, cardNo);
    }

    final cRef = hasCard ? _col(cardsCollection).doc(cardNo) : null;
    final pRefs = {
      for (final id in qtyById.keys) id: _col(productsCollection).doc(id),
    };
    final tRef = _col(transactionsCollection).doc();
    final lRef = _col(ledgerCollection).doc();

    return _db.runTransaction<SaleResult>((tx) async {
      // ── Önce tüm okumalar ──
      CanteenCard? card;
      if (cRef != null) {
        final cs = await tx.get(cRef);
        if (!cs.exists) throw const CanteenException('Kart bulunamadı.');
        card = CanteenCard.fromDoc(cs);
        if (card.institutionId != inst) {
          throw const CanteenException('Kart bu kuruma ait değil.');
        }
      }
      final products = <String, CanteenProduct>{};
      for (final e in pRefs.entries) {
        final ps = await tx.get(e.value);
        if (!ps.exists) {
          throw const CanteenException('Sepetteki bir ürün bulunamadı.');
        }
        final p = CanteenProduct.fromDoc(ps);
        if (p.institutionId != inst) {
          throw CanteenException('"${p.name}" bu kuruma ait değil.');
        }
        products[e.key] = p;
      }

      // ── Doğrulamalar ──
      double total = 0;
      final items = <CanteenTransactionItem>[];
      for (final e in qtyById.entries) {
        final p = products[e.key]!;
        if (!p.isActive) {
          throw CanteenException('"${p.name}" satışa kapalı.');
        }
        if (p.stock < e.value) {
          throw CanteenException(
            'Yetersiz stok: "${p.name}" (kalan: ${p.stock}).',
          );
        }
        if (card != null) {
          if (card.blockedProductIds.contains(p.id)) {
            throw CanteenException(
              '"${p.name}" bu öğrenci için veli tarafından engellenmiş.',
            );
          }
          if (p.category.isNotEmpty &&
              card.blockedCategories.contains(p.category)) {
            throw CanteenException(
              '"${p.category}" kategorisi bu öğrenci için engellenmiş.',
            );
          }
        }
        total += p.price * e.value;
        items.add(
          CanteenTransactionItem(
            productId: p.id,
            name: p.name,
            qty: e.value,
            price: p.price,
          ),
        );
      }
      total = _round(total);

      double? balanceAfter;
      if (card != null && payFromCard) {
        if (!card.isActive) {
          throw const CanteenException('Kart pasif / bloke edilmiş.');
        }
        if (card.balance < total) {
          throw CanteenException(
            'Yetersiz bakiye. Bakiye: ${card.balance.toStringAsFixed(2)} ₺, '
            'tutar: ${total.toStringAsFixed(2)} ₺.',
          );
        }
        if (card.dailyLimit > 0 && spentToday + total > card.dailyLimit) {
          final left = (card.dailyLimit - spentToday).clamp(0, double.infinity);
          throw CanteenException(
            'Günlük harcama limiti aşılıyor. Kalan limit: '
            '${left.toStringAsFixed(2)} ₺.',
          );
        }
        balanceAfter = _round(card.balance - total);
      } else if (card != null) {
        balanceAfter = card.balance;
      }

      // ── Yazmalar ──
      for (final it in items) {
        final p = products[it.productId]!;
        tx.update(pRefs[it.productId]!, {
          'stock': p.stock - it.qty,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(
          _col(movementsCollection).doc(),
          CanteenStockMovement(
            institutionId: inst,
            productId: p.id,
            type: 'out',
            qty: it.qty,
            note: 'Satış ${tRef.id}',
            by: cashierId,
          ).toMap(),
        );
      }
      if (cRef != null && card != null && payFromCard) {
        tx.update(cRef, {'balance': balanceAfter});
      }
      tx.set(
        tRef,
        CanteenTransaction(
          institutionId: inst,
          cardNo: card?.cardNo ?? '',
          studentId: card?.studentId ?? '',
          type: 'sale',
          method: method,
          amount: total,
          items: items,
          balanceAfter: balanceAfter ?? 0,
          cashierId: cashierId,
        ).toMap(),
      );
      final cleanNote = (note ?? '').trim();
      final methodSuffix = method == 'pos'
          ? ' (POS - Kredi/Banka Kartı${cleanNote.isEmpty ? '' : ': $cleanNote'})'
          : (cleanNote.isEmpty ? '' : ' ($cleanNote)');
      tx.set(
        lRef,
        CanteenLedgerEntry(
          institutionId: inst,
          type: 'income',
          category: 'Satış',
          amount: total,
          note:
              'Satış ${tRef.id}${card != null ? ' - ${card.studentName}' : ''}$methodSuffix',
          date: DateTime.now(),
        ).toMap(),
      );

      return SaleResult(
        transactionId: tRef.id,
        total: total,
        balanceAfter: balanceAfter,
        cardNo: card?.cardNo,
        items: items,
      );
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // İADE İŞLEMLERİ (TAM VEYA ÜRÜN-PARÇA BAZLI İADE & BAKİYE GERİ AKTARIM)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Kullanıcının "Kart Hareketleri Üzerinden Alışveriş / Ürün İadesi ve Bakiye Geri Aktarım"
  /// yetkisi olup olmadığını kontrol eder (`Kullanıcı Yetkilendirme` / `Rol Şablonları`).
  Future<bool> hasRefundPermission(String instId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final inst = _up(instId);

    try {
      Map<String, dynamic>? userData;
      final directDoc = await _db.collection('users').doc(user.uid).get();
      if (directDoc.exists) {
        userData = directDoc.data();
      } else if ((user.email ?? '').isNotEmpty) {
        final byEmail = await _db
            .collection('users')
            .where('email', isEqualTo: user.email)
            .limit(1)
            .get();
        if (byEmail.docs.isNotEmpty) {
          userData = byEmail.docs.first.data();
        }
      }

      if (userData == null) {
        // Kurum ana hesabı (Firebase Auth doğrudan kurum yöneticisi ise)
        return true;
      }

      final role = (userData['role'] ?? userData['userType'] ?? 'admin')
          .toString()
          .trim()
          .toLowerCase();

      if (role == 'student' ||
          role == 'ogrenci' ||
          role == 'parent' ||
          role == 'veli') {
        return false;
      }

      bool? evaluateKantinPerms(Map<String, dynamic>? kantinPerm) {
        if (kantinPerm == null) return null;
        if (kantinPerm['enabled'] == false) return false;
        final subsRaw = kantinPerm['subModules'];
        if (subsRaw is Map) {
          final subs = Map<String, dynamic>.from(subsRaw);
          const refundKeys = [
            'kantin_kart_hareket_iade',
            'kantin_satis_iptal_iade',
            'st_kantin_kart_hareket_iade',
            'st_kantin_satis_iade',
            'kantin_bakiye_iade_duzelt',
            'st_kantin_bakiye_duzelt',
          ];
          bool foundExplicitKey = false;
          for (final key in refundKeys) {
            final entry = subs[key];
            if (entry is Map) {
              foundExplicitKey = true;
              if (entry['enabled'] == true) {
                return true;
              }
            } else if (entry is bool) {
              foundExplicitKey = true;
              if (entry) return true;
            }
          }
          if (foundExplicitKey) return false;

          // Alt başlık düzeyinde kontrol (kantin_bakiye veya kantin_satis)
          for (final parentKey in ['kantin_bakiye', 'kantin_satis']) {
            final pEntry = subs[parentKey];
            if (pEntry is Map && pEntry['enabled'] == false) {
              return false;
            }
          }
        }
        final level = (kantinPerm['level'] ?? 'editor').toString();
        return level == 'editor';
      }

      // 1. Kullanıcıya özel tanımlanmış bireysel yetki (varsa önceliklidir)
      final userModPerms = userData['modulePermissions'] ?? userData['permissions'];
      if (userModPerms is Map && userModPerms['kantin'] is Map) {
        final res = evaluateKantinPerms(
          Map<String, dynamic>.from(userModPerms['kantin'] as Map),
        );
        if (res != null) return res;
      }

      // 2. Kurum rol şablonu (`institutions/{inst}/role_permissions/{role}`)
      if (inst.isNotEmpty && role.isNotEmpty) {
        final roleDoc = await _db
            .collection('institutions')
            .doc(inst)
            .collection('role_permissions')
            .doc(role)
            .get();
        if (roleDoc.exists) {
          final rData = roleDoc.data();
          final rPerms = rData?['permissions'];
          if (rPerms is Map && rPerms['kantin'] is Map) {
            final res = evaluateKantinPerms(
              Map<String, dynamic>.from(rPerms['kantin'] as Map),
            );
            if (res != null) return res;
          }
        }
      }

      // Varsayılan: Yönetici, muhasebe ve kantin sorumlusu rolleri yetkili
      return true;
    } catch (_) {
      return true;
    }
  }

  /// Kart hareketlerindeki bir satış işlemini **tamamen** veya **ürün ürün (parça parça)**
  /// iade eder, harcanan tutarı kart bakiyesine geri aktarır, ürün stoklarını iade alınan
  /// adet kadar geri yükler ve muhasebeye "Satış İadesi" kaydı düşer.
  Future<RefundResult> refundSale({
    required String instId,
    required String saleTransactionId,
    Map<String, int>? itemQuantitiesByKey,
    bool refundAll = false,
    required String cashierId,
    String? reason,
  }) async {
    final inst = _up(instId);
    final saleId = saleTransactionId.trim();
    if (saleId.isEmpty) {
      throw const CanteenException('İade edilecek satış kaydı bulunamadı.');
    }

    final permitted = await hasRefundPermission(inst);
    if (!permitted) {
      throw const CanteenException(
        'Alışveriş / ürün iadesi ve bakiye geri aktarım işlemi için yetkiniz bulunmuyor. '
        'Yöneticinizden "Kullanıcı Yetkilendirme > Kantin Yönetimi > Kart Hareketleri Üzerinden İade" yetkisi talep edebilirsiniz.',
      );
    }

    final saleRef = _col(transactionsCollection).doc(saleId);
    final refundTxRef = _col(transactionsCollection).doc();
    final ledgerRef = _col(ledgerCollection).doc();

    return _db.runTransaction<RefundResult>((tx) async {
      // ── 1. Okumalar (Firestore kuralı: tüm okumalar yazmalardan önce yapılmalı) ──
      final saleSnap = await tx.get(saleRef);
      if (!saleSnap.exists) {
        throw const CanteenException('Satış işlemi veritabanında bulunamadı.');
      }
      final saleTx = CanteenTransaction.fromDoc(saleSnap);
      if (saleTx.institutionId != inst) {
        throw const CanteenException('Bu satış kaydı farklı bir kuruma ait.');
      }
      if (saleTx.type != 'sale') {
        throw const CanteenException(
          'Yalnızca satış (harcama) işlemleri iade edilebilir.',
        );
      }
      if (saleTx.isFullyRefunded) {
        throw const CanteenException(
          'Bu alışverişin tamamı daha önce iade edilmiş.',
        );
      }

      // İade edilecek kalemleri ve tutarı hesapla
      final refundedItems = <CanteenTransactionItem>[];
      final updatedRefundedQtys = Map<String, int>.from(saleTx.refundedQtys);
      double refundTotal = 0;

      if (saleTx.items.isNotEmpty) {
        for (int i = 0; i < saleTx.items.length; i++) {
          final item = saleTx.items[i];
          final key = CanteenTransaction.itemRefundKey(item, i);
          final remainingQty = saleTx.refundableQtyFor(item, i);
          if (remainingQty <= 0) continue;

          final int reqQty = refundAll
              ? remainingQty
              : (itemQuantitiesByKey?[key] ??
                    itemQuantitiesByKey?[item.productId] ??
                    0);
          if (reqQty <= 0) continue;
          if (reqQty > remainingQty) {
            throw CanteenException(
              '"${item.name}" ürünü için en fazla $remainingQty adet iade edilebilir.',
            );
          }

          refundedItems.add(
            CanteenTransactionItem(
              productId: item.productId,
              name: item.name,
              qty: reqQty,
              price: item.price,
            ),
          );
          updatedRefundedQtys[key] =
              (updatedRefundedQtys[key] ?? 0) + reqQty;
          refundTotal += item.price * reqQty;
        }

        if (refundedItems.isEmpty) {
          throw const CanteenException(
            'İade etmek için en az 1 ürün ve adet seçmelisiniz.',
          );
        }
      } else {
        // Kalemsiz satış kaydı için tutar bazlı tam iade
        refundTotal = saleTx.remainingRefundableAmount;
        if (refundTotal <= 0) {
          throw const CanteenException('İade edilebilir tutar kalmamış.');
        }
      }

      refundTotal = _round(refundTotal);
      final maxRemaining = _round(saleTx.remainingRefundableAmount);
      if (refundTotal > maxRemaining + 0.05) {
        refundTotal = maxRemaining;
      }
      if (refundTotal <= 0) {
        throw const CanteenException('İade tutarı sıfırdan büyük olmalıdır.');
      }

      // Kart okuması
      DocumentReference<Map<String, dynamic>>? cardRef;
      CanteenCard? card;
      if (saleTx.cardNo.trim().isNotEmpty) {
        cardRef = _col(cardsCollection).doc(saleTx.cardNo.trim());
        final cardSnap = await tx.get(cardRef);
        if (cardSnap.exists) {
          card = CanteenCard.fromDoc(cardSnap);
        }
      }

      // Ürün stok okumaları (yalnızca geçerli productId olanlar)
      final productRefs = <String, DocumentReference<Map<String, dynamic>>>{};
      final existingProducts = <String, CanteenProduct>{};
      for (final rItem in refundedItems) {
        final pid = rItem.productId.trim();
        if (pid.isEmpty || productRefs.containsKey(pid)) continue;
        final pRef = _col(productsCollection).doc(pid);
        productRefs[pid] = pRef;
        final pSnap = await tx.get(pRef);
        if (pSnap.exists) {
          final p = CanteenProduct.fromDoc(pSnap);
          if (p.institutionId == inst) {
            existingProducts[pid] = p;
          }
        }
      }

      // ── 2. Yazmalar ──
      // Ürün stoklarını geri yükle ve stok hareketi oluştur
      final stockAddedByPid = <String, int>{};
      for (final rItem in refundedItems) {
        final pid = rItem.productId.trim();
        if (pid.isEmpty || !existingProducts.containsKey(pid)) continue;
        stockAddedByPid[pid] = (stockAddedByPid[pid] ?? 0) + rItem.qty;
      }
      final cleanReason = (reason ?? '').trim();
      for (final entry in stockAddedByPid.entries) {
        final p = existingProducts[entry.key]!;
        final pRef = productRefs[entry.key]!;
        tx.update(pRef, {
          'stock': p.stock + entry.value,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(
          _col(movementsCollection).doc(),
          CanteenStockMovement(
            institutionId: inst,
            productId: p.id,
            type: 'in',
            qty: entry.value,
            note:
                'Satış İadesi ($saleId)${cleanReason.isEmpty ? '' : ' - $cleanReason'}',
            by: cashierId,
          ).toMap(),
        );
      }

      // Harcanan parayı kart bakiyesine geri aktar (Nakit dışındaki kartlı/QR işlemlerde veya kart bağlıysa)
      double? newBalance;
      final shouldCreditCard =
          card != null && cardRef != null && saleTx.method != 'cash' && saleTx.method != 'pos';
      if (shouldCreditCard) {
        newBalance = _round(card.balance + refundTotal);
        tx.update(cardRef, {'balance': newBalance});
      } else if (card != null) {
        newBalance = card.balance;
      }

      // Orijinal satış kaydını güncelle (tekrar iade edilmesini önlemek için)
      final newRefundedAmount = _round(saleTx.refundedAmount + refundTotal);
      tx.update(saleRef, {
        'refundedAmount': newRefundedAmount,
        'refundedQtys': updatedRefundedQtys,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // İade işlem hareketini (`type: 'refund'`) oluştur
      final itemsSummary = refundedItems
          .map((e) => '${e.qty}x ${e.name}')
          .join(', ');
      final txNote = [
        if (itemsSummary.isNotEmpty) 'İade: $itemsSummary',
        if (cleanReason.isNotEmpty) cleanReason,
      ].join(' • ');

      tx.set(
        refundTxRef,
        CanteenTransaction(
          institutionId: inst,
          cardNo: saleTx.cardNo,
          studentId: saleTx.studentId,
          type: 'refund',
          method: saleTx.method,
          amount: refundTotal,
          items: refundedItems,
          balanceAfter: newBalance ?? saleTx.balanceAfter,
          cashierId: cashierId,
          parentTransactionId: saleId,
          note: txNote,
        ).toMap(),
      );

      // Kantin muhasebesine gider (Satış İadesi) kaydı ekle
      tx.set(
        ledgerRef,
        CanteenLedgerEntry(
          institutionId: inst,
          type: 'expense',
          category: 'Satış İadesi',
          amount: refundTotal,
          note:
              'Satış İadesi ($saleId)${card != null ? ' - ${card.studentName}' : ''}'
              '${itemsSummary.isNotEmpty ? ' [$itemsSummary]' : ''}'
              '${cleanReason.isNotEmpty ? ' ($cleanReason)' : ''}',
          date: DateTime.now(),
        ).toMap(),
      );

      final isNowFull = newRefundedAmount >= saleTx.amount - 0.009;
      return RefundResult(
        refundTransactionId: refundTxRef.id,
        saleTransactionId: saleId,
        refundedAmount: refundTotal,
        balanceAfter: newBalance,
        cardNo: saleTx.cardNo.isEmpty ? null : saleTx.cardNo,
        refundedItems: refundedItems,
        isFullRefund: isNowFull,
      );
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // İŞLEMLER
  // ═══════════════════════════════════════════════════════════════════════════

  Stream<List<CanteenTransaction>> watchTransactions(
    String instId, {
    String? cardNo,
    DateTime? from,
    DateTime? to,
    int limit = 200,
  }) {
    final inst = _up(instId);
    // Veli sorguları kurum bazında yapılamaz (kurallar): kartNo verilirse yalnızca kartNo.
    final Query<Map<String, dynamic>> q = (cardNo != null && cardNo.isNotEmpty)
        ? _col(transactionsCollection).where('cardNo', isEqualTo: cardNo)
        : _byInst(transactionsCollection, inst);
    return q.snapshots().map((s) {
      var list = s.docs
          .map(CanteenTransaction.fromDoc)
          .where((t) => t.institutionId == inst)
          .toList();
      list = _filterRange(list, from, to);
      list.sort(
        (a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
      return (limit > 0 && list.length > limit) ? list.sublist(0, limit) : list;
    });
  }

  List<CanteenTransaction> _filterRange(
    List<CanteenTransaction> list,
    DateTime? from,
    DateTime? to,
  ) {
    return list.where((t) {
      final d = t.createdAt;
      if (d == null) return from == null && to == null;
      if (from != null && d.isBefore(from)) return false;
      if (to != null && d.isAfter(to)) return false;
      return true;
    }).toList();
  }

  /// Bugünkü toplam harcama (satış − iade).
  Future<double> todaySpent(String instId, String cardNo) async {
    final inst = _up(instId);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final snap = await _col(
      transactionsCollection,
    ).where('cardNo', isEqualTo: cardNo).get();
    double sum = 0;
    for (final d in snap.docs) {
      final t = CanteenTransaction.fromDoc(d);
      if (t.institutionId != inst) continue;
      final at = t.createdAt;
      if (at == null || at.isBefore(start)) continue;
      if (t.type == 'sale') sum += t.amount;
      if (t.type == 'refund') sum -= t.amount;
    }
    return _round(sum < 0 ? 0 : sum);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MUHASEBE
  // ═══════════════════════════════════════════════════════════════════════════

  Stream<List<CanteenLedgerEntry>> watchLedger(
    String instId, {
    DateTime? from,
    DateTime? to,
    int limit = 500,
  }) {
    return _byInst(ledgerCollection, instId).snapshots().map((s) {
      var list = s.docs.map(CanteenLedgerEntry.fromDoc).where((e) {
        final d = e.date ?? e.createdAt;
        if (d == null) return true;
        if (from != null && d.isBefore(from)) return false;
        if (to != null && d.isAfter(to)) return false;
        return true;
      }).toList();
      DateTime key(CanteenLedgerEntry e) =>
          e.date ?? e.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      list.sort((a, b) => key(b).compareTo(key(a)));
      return list.length > limit ? list.sublist(0, limit) : list;
    });
  }

  Future<void> addLedgerEntry(String instId, CanteenLedgerEntry e) async {
    if (e.amount <= 0) {
      throw const CanteenException('Tutar sıfırdan büyük olmalı.');
    }
    if (e.type != 'income' && e.type != 'expense') {
      throw const CanteenException('Geçersiz kayıt türü.');
    }
    await _col(ledgerCollection).add(
      CanteenLedgerEntry(
        institutionId: _up(instId),
        type: e.type,
        category: e.category,
        amount: e.amount,
        note: e.note,
        date: e.date ?? DateTime.now(),
      ).toMap(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RAPOR
  // ═══════════════════════════════════════════════════════════════════════════

  Future<CanteenReport> buildReport(
    String instId,
    DateTime from,
    DateTime to,
  ) async {
    final inst = _up(instId);
    final txSnap = await _byInst(transactionsCollection, inst).get();
    final prodSnap = await _byInst(productsCollection, inst).get();
    final ledSnap = await _byInst(ledgerCollection, inst).get();

    final txs = _filterRange(
      txSnap.docs.map(CanteenTransaction.fromDoc).toList(),
      from,
      to,
    );

    double sales = 0, topups = 0, refunds = 0;
    int saleCount = 0;
    final byMethod = <String, double>{};
    final prodAgg = <String, CanteenTopProduct>{};
    final daily = <DateTime, double>{};

    // 1. Aşama: Satış ve Bakiye Yükleme işlemlerini topla
    for (final t in txs) {
      switch (t.type) {
        case 'sale':
          sales += t.amount;
          saleCount++;
          byMethod[t.method] = (byMethod[t.method] ?? 0) + t.amount;
          final at = t.createdAt;
          if (at != null) {
            final day = DateTime(at.year, at.month, at.day);
            daily[day] = (daily[day] ?? 0) + t.amount;
          }
          for (final it in t.items) {
            final prev = prodAgg[it.productId];
            prodAgg[it.productId] = CanteenTopProduct(
              productId: it.productId,
              name: it.name,
              qty: (prev?.qty ?? 0) + it.qty,
              revenue: (prev?.revenue ?? 0) + it.total,
            );
          }
          break;
        case 'topup':
          topups += t.amount;
          break;
      }
    }

    // 2. Aşama: İade (refund) işlemlerini satış toplamlarından düş
    // (Firestore doküman sırasından bağımsız olarak her zaman satışlardan sonra düşülür)
    for (final t in txs) {
      if (t.type != 'refund') continue;
      refunds += t.amount;
      if (byMethod.containsKey(t.method)) {
        final nextMethodVal =
            ((byMethod[t.method] ?? 0) - t.amount).clamp(0.0, double.infinity);
        byMethod[t.method] = _round(nextMethodVal);
      }
      final at = t.createdAt;
      if (at != null) {
        final day = DateTime(at.year, at.month, at.day);
        daily[day] = ((daily[day] ?? 0) - t.amount).clamp(0.0, double.infinity);
      }
      for (final it in t.items) {
        final prev = prodAgg[it.productId];
        if (prev != null) {
          final nextQty = (prev.qty - it.qty).clamp(0, 999999999);
          final nextRev = (prev.revenue - it.total).clamp(0.0, double.infinity);
          if (nextQty <= 0) {
            prodAgg.remove(it.productId);
          } else {
            prodAgg[it.productId] = CanteenTopProduct(
              productId: it.productId,
              name: prev.name,
              qty: nextQty,
              revenue: nextRev,
            );
          }
        }
      }
    }

    // Boş günleri 0 ile doldur
    final dailyList = <CanteenDailyRevenue>[];
    var day = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    while (!day.isAfter(end) && dailyList.length < 400) {
      dailyList.add(CanteenDailyRevenue(day, _round(daily[day] ?? 0)));
      day = DateTime(day.year, day.month, day.day + 1);
    }

    final top = prodAgg.values.toList()..sort((a, b) => b.qty.compareTo(a.qty));

    final lowStock =
        prodSnap.docs
            .map(CanteenProduct.fromDoc)
            .where((p) => p.isActive && p.isLowStock)
            .toList()
          ..sort((a, b) => a.stock.compareTo(b.stock));

    double inc = 0, exp = 0;
    for (final d in ledSnap.docs) {
      final e = CanteenLedgerEntry.fromDoc(d);
      final at = e.date ?? e.createdAt;
      if (at != null && (at.isBefore(from) || at.isAfter(to))) continue;
      if (e.isIncome) {
        inc += e.amount;
      } else {
        exp += e.amount;
      }
    }

    return CanteenReport(
      from: from,
      to: to,
      totalSales: _round(sales),
      saleCount: saleCount,
      totalTopUps: _round(topups),
      totalRefunds: _round(refunds),
      salesByMethod: byMethod,
      topProducts: top.take(10).toList(),
      dailyRevenue: dailyList,
      lowStock: lowStock,
      ledgerIncome: _round(inc),
      ledgerExpense: _round(exp),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MOBİL / QR CANLI KAREKOD ÖDEME OTURUMLARI
  // ═══════════════════════════════════════════════════════════════════════════

  /// Kasada sepetteki ürünler için okutulabilir karekod ödeme oturumu oluşturur.
  Future<CanteenQrSession> createQrSession({
    required String instId,
    required List<CartLine> lines,
    required String cashierId,
  }) async {
    final inst = _up(instId);
    if (inst.isEmpty) {
      throw const CanteenException('Kurum bilgisi bulunamadı.');
    }
    final qtyById = <String, int>{};
    for (final l in lines) {
      if (l.qty <= 0) continue;
      qtyById[l.productId] = (qtyById[l.productId] ?? 0) + l.qty;
    }
    if (qtyById.isEmpty) {
      throw const CanteenException('Karekod üretmek için sepete ürün ekleyin.');
    }

    final snaps = await Future.wait(
      qtyById.keys.map((id) => _col(productsCollection).doc(id).get()),
    );
    final items = <CanteenTransactionItem>[];
    double total = 0;
    for (final s in snaps) {
      if (!s.exists) {
        throw const CanteenException('Sepetteki bir ürün bulunamadı.');
      }
      final p = CanteenProduct.fromDoc(s);
      if (p.institutionId != inst || !p.isActive) {
        throw CanteenException('"${p.name}" şu an satışa uygun değil.');
      }
      final qty = qtyById[p.id] ?? 0;
      if (p.stock < qty) {
        throw CanteenException(
          '"${p.name}" için yeterli stok yok (Kalan: ${p.stock}).',
        );
      }
      items.add(
        CanteenTransactionItem(
          productId: p.id,
          name: p.name,
          qty: qty,
          price: p.price,
        ),
      );
      total += p.price * qty;
    }
    total = _round(total);

    final rng = Random.secure();
    final shortCode = (100000 + rng.nextInt(900000)).toString();
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(minutes: 5));
    final ref = _col(qrSessionsCollection).doc();

    final session = CanteenQrSession(
      id: ref.id,
      institutionId: inst,
      shortCode: shortCode,
      items: items,
      total: total,
      status: 'pending',
      cashierId: cashierId,
      createdAt: now,
      expiresAt: expiresAt,
    );
    await ref.set(session.toMap());
    return session;
  }

  /// Karekod ödeme oturumunu gerçek zamanlı izler.
  Stream<CanteenQrSession?> watchQrSession(String sessionId) {
    if (sessionId.trim().isEmpty) return Stream.value(null);
    return _col(qrSessionsCollection).doc(sessionId.trim()).snapshots().map((
      doc,
    ) {
      if (!doc.exists) return null;
      return CanteenQrSession.fromDoc(doc);
    });
  }

  /// Bekleyen karekod oturumunu iptal eder.
  Future<void> cancelQrSession(String sessionId) async {
    final id = sessionId.trim();
    if (id.isEmpty) return;
    try {
      final snap = await _col(qrSessionsCollection).doc(id).get();
      if (snap.exists && (snap.data()?['status'] ?? '') == 'pending') {
        await _col(
          qrSessionsCollection,
        ).doc(id).update({'status': 'cancelled'});
      }
    } catch (_) {}
  }

  /// QR verisi (`KANTINPAY:<INST>:<ID>`) veya 6 haneli tek kullanımlık kod ile oturumu bulur.
  Future<CanteenQrSession> findQrSession(
    String codeOrPayload, {
    String? fallbackInstId,
  }) async {
    final raw = codeOrPayload.trim();
    if (raw.isEmpty) {
      throw const CanteenException(
        'Geçerli bir karekod veya ödeme kodu girin.',
      );
    }

    CanteenQrSession? session;
    if (raw.toUpperCase().startsWith('KANTINPAY:')) {
      final parts = raw.split(':');
      final sessionId = parts.length >= 3 ? parts[2].trim() : parts.last.trim();
      if (sessionId.isNotEmpty) {
        final doc = await _col(qrSessionsCollection).doc(sessionId).get();
        if (doc.exists) session = CanteenQrSession.fromDoc(doc);
      }
    } else {
      final digitsOnly = raw.replaceAll(RegExp(r'\s+'), '');
      if (RegExp(r'^\d{6}$').hasMatch(digitsOnly)) {
        final q = await _col(
          qrSessionsCollection,
        ).where('shortCode', isEqualTo: digitsOnly).get();
        final candidates = q.docs
            .map(CanteenQrSession.fromDoc)
            .where((s) => s.isPending && !s.isExpired)
            .toList();
        if (fallbackInstId != null && fallbackInstId.trim().isNotEmpty) {
          final inst = _up(fallbackInstId);
          final instMatch = candidates
              .where((s) => s.institutionId == inst)
              .toList();
          if (instMatch.isNotEmpty) session = instMatch.first;
        }
        session ??= candidates.isNotEmpty ? candidates.first : null;
      } else {
        final doc = await _col(qrSessionsCollection).doc(raw).get();
        if (doc.exists) session = CanteenQrSession.fromDoc(doc);
      }
    }

    if (session == null) {
      throw const CanteenException(
        'Ödeme oturumu bulunamadı. Lütfen kasadaki güncel karekodu okutun.',
      );
    }
    if (session.status == 'paid') {
      throw const CanteenException('Bu karekod ödemesi zaten tamamlanmış.');
    }
    if (session.status == 'cancelled') {
      throw const CanteenException('Bu karekod kasada iptal edilmiş.');
    }
    if (session.isExpired) {
      throw const CanteenException(
        'Karekodun süresi dolmuş. Lütfen kasadan yeni karekod isteyin.',
      );
    }
    return session;
  }

  /// Giriş yapmış kullanıcının (Öğrenci, Veli, Öğretmen / Personel) bu kurumdaki
  /// ödeme yapabileceği kantin kartlarını / dijital cüzdanlarını döner.
  Future<List<CanteenCard>> findPayableCardsForCurrentUser(
    String instId,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return const [];
    final inst = _up(instId);
    final uid = user.uid;
    final email = (user.email ?? '').trim();

    final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[
      _col(cardsCollection).where('studentId', isEqualTo: uid).get(),
      _col(cardsCollection).where('parentUids', arrayContains: uid).get(),
      if (email.isNotEmpty)
        _col(cardsCollection).where('parentEmail', isEqualTo: email).get(),
    ];

    final snaps = await Future.wait(futures);
    final byNo = <String, CanteenCard>{};
    for (final s in snaps) {
      for (final d in s.docs) {
        final c = CanteenCard.fromDoc(d);
        if (c.institutionId == inst) {
          byNo[c.cardNo] = c;
        }
      }
    }
    return byNo.values.toList()
      ..sort((a, b) => a.studentName.compareTo(b.studentName));
  }

  /// Öğretmen, personel veya veli için kendi adına dijital kantin cüzdan kartı oluşturur (varsa döner).
  Future<CanteenCard> ensurePersonalWalletCard({
    required String instId,
    required String uid,
    required String fullName,
    required String roleLabel,
    String? email,
  }) async {
    final inst = _up(instId);
    final existing = await findCardByStudent(inst, uid);
    if (existing != null) return existing;

    final shortUid = uid.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    final suffix = shortUid.length >= 6
        ? shortUid.substring(0, 6)
        : shortUid.padRight(6, '0');
    final cardNo = 'KNT-$suffix';
    final card = CanteenCard(
      cardNo: cardNo,
      institutionId: inst,
      studentId: uid,
      studentName: fullName.trim().isEmpty
          ? 'Kantin Kullanıcısı'
          : fullName.trim(),
      className: roleLabel,
      balance: 0,
      isActive: true,
      dailyLimit: 0,
      parentUids: [uid],
      parentEmail: (email ?? '').trim(),
    );
    await saveCard(inst, card);
    return (await findCard(inst, cardNo)) ?? card;
  }

  /// Okutulan karekod oturumunu seçilen kantin kartı / dijital cüzdan bakiyesinden atomik olarak öder.
  Future<SaleResult> payQrSession({
    required String sessionId,
    required String cardNo,
    required String payerUid,
    required String payerName,
    required String payerRole,
  }) async {
    final sId = sessionId.trim();
    final cNo = cardNo.trim();
    if (sId.isEmpty || cNo.isEmpty) {
      throw const CanteenException('Ödeme bilgileri eksik.');
    }

    final preSnap = await _col(qrSessionsCollection).doc(sId).get();
    if (!preSnap.exists) {
      throw const CanteenException('Ödeme oturumu bulunamadı.');
    }
    final preSession = CanteenQrSession.fromDoc(preSnap);
    if (!preSession.isPending || preSession.isExpired) {
      throw const CanteenException(
        'Bu karekod artık geçerli değil veya ödenmiş.',
      );
    }
    final inst = preSession.institutionId;
    final spentToday = await todaySpent(inst, cNo);

    final sRef = _col(qrSessionsCollection).doc(sId);
    final cRef = _col(cardsCollection).doc(cNo);
    final pRefs = {
      for (final it in preSession.items)
        it.productId: _col(productsCollection).doc(it.productId),
    };
    final tRef = _col(transactionsCollection).doc();
    final lRef = _col(ledgerCollection).doc();

    return _db.runTransaction<SaleResult>((tx) async {
      final sDoc = await tx.get(sRef);
      if (!sDoc.exists) {
        throw const CanteenException('Ödeme oturumu bulunamadı.');
      }
      final session = CanteenQrSession.fromDoc(sDoc);
      if (session.status == 'paid') {
        throw const CanteenException('Bu karekod zaten ödendi.');
      }
      if (session.status != 'pending' || session.isExpired) {
        throw const CanteenException(
          'Karekodun süresi doldu veya iptal edildi.',
        );
      }

      final cDoc = await tx.get(cRef);
      if (!cDoc.exists) {
        throw const CanteenException('Kantin kartı bulunamadı.');
      }
      final card = CanteenCard.fromDoc(cDoc);
      if (card.institutionId != inst) {
        throw const CanteenException('Seçilen kart bu kuruma ait değil.');
      }
      if (!card.isActive) {
        throw const CanteenException('Kart pasif / bloke edilmiş.');
      }

      final products = <String, CanteenProduct>{};
      for (final e in pRefs.entries) {
        final ps = await tx.get(e.value);
        if (!ps.exists) {
          throw const CanteenException('Sepetteki bir ürün bulunamadı.');
        }
        products[e.key] = CanteenProduct.fromDoc(ps);
      }

      double total = 0;
      final items = <CanteenTransactionItem>[];
      for (final it in session.items) {
        final p = products[it.productId]!;
        if (!p.isActive) {
          throw CanteenException('"${p.name}" satışa kapalı.');
        }
        if (p.stock < it.qty) {
          throw CanteenException(
            'Yetersiz stok: "${p.name}" (Kalan: ${p.stock}).',
          );
        }
        if (card.blockedProductIds.contains(p.id)) {
          throw CanteenException(
            '"${p.name}" bu kart için veli tarafından kısıtlanmış.',
          );
        }
        if (p.category.isNotEmpty &&
            card.blockedCategories.contains(p.category)) {
          throw CanteenException(
            '"${p.category}" kategorisi bu kart için kısıtlanmış.',
          );
        }
        total += p.price * it.qty;
        items.add(
          CanteenTransactionItem(
            productId: p.id,
            name: p.name,
            qty: it.qty,
            price: p.price,
          ),
        );
      }
      total = _round(total);

      if (card.balance < total) {
        throw CanteenException(
          'Yetersiz bakiye. Mevcut: ${card.balance.toStringAsFixed(2)} ₺, '
          'Tutar: ${total.toStringAsFixed(2)} ₺.',
        );
      }
      if (card.dailyLimit > 0 && spentToday + total > card.dailyLimit) {
        final left = (card.dailyLimit - spentToday).clamp(0, double.infinity);
        throw CanteenException(
          'Günlük harcama limiti aşılıyor. Kalan limit: ${left.toStringAsFixed(2)} ₺.',
        );
      }

      final balanceAfter = _round(card.balance - total);

      for (final it in items) {
        final p = products[it.productId]!;
        tx.update(pRefs[it.productId]!, {
          'stock': p.stock - it.qty,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(
          _col(movementsCollection).doc(),
          CanteenStockMovement(
            institutionId: inst,
            productId: p.id,
            type: 'out',
            qty: it.qty,
            note: 'Mobil QR Satış ${tRef.id}',
            by: payerUid,
          ).toMap(),
        );
      }

      tx.update(cRef, {'balance': balanceAfter});

      final txData = CanteenTransaction(
        institutionId: inst,
        cardNo: card.cardNo,
        studentId: card.studentId.isEmpty ? payerUid : card.studentId,
        type: 'sale',
        method: 'qr',
        amount: total,
        items: items,
        balanceAfter: balanceAfter,
        cashierId: session.cashierId.isEmpty ? payerUid : session.cashierId,
      ).toMap()..['qrSessionId'] = sId;
      tx.set(tRef, txData);

      final displayPayer = payerName.trim().isEmpty
          ? card.studentName
          : payerName.trim();
      tx.set(
        lRef,
        CanteenLedgerEntry(
          institutionId: inst,
          type: 'income',
          category: 'Satış',
          amount: total,
          note: 'Mobil QR Satış ${tRef.id} - $displayPayer (${card.cardNo})',
          date: DateTime.now(),
        ).toMap(),
      );

      tx.update(sRef, {
        'status': 'paid',
        'payerUid': payerUid,
        'payerName': displayPayer,
        'payerRole': payerRole,
        'cardNo': card.cardNo,
        'payVia': 'wallet',
        'balanceAfter': balanceAfter,
        'transactionId': tRef.id,
        'paidAt': FieldValue.serverTimestamp(),
      });

      return SaleResult(
        transactionId: tRef.id,
        total: total,
        balanceAfter: balanceAfter,
        cardNo: card.cardNo,
        items: items,
      );
    });
  }

  static double _round(double v) => (v * 100).roundToDouble() / 100;
}
