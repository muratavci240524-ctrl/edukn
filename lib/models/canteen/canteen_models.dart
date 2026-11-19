import 'package:cloud_firestore/cloud_firestore.dart';

double _d(dynamic v, [double def = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? def;
  return def;
}

int _i(dynamic v, [int def = 0]) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? def;
  return def;
}

DateTime? _dt(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  return null;
}

List<String> _sl(dynamic v) =>
    v is Iterable ? v.map((e) => e.toString()).toList() : <String>[];

String _inst(dynamic v) => (v ?? '').toString().trim().toUpperCase();

class CanteenProduct {
  final String id;
  final String institutionId;
  final String name;
  final String category;
  final String barcode;
  final double price;
  final double cost;
  final int stock;
  final int minStock;
  final String unit;
  final String imageUrl;
  final bool isActive;
  final String warehouseId;

  const CanteenProduct({
    this.id = '',
    this.institutionId = '',
    required this.name,
    this.category = '',
    this.barcode = '',
    this.price = 0,
    this.cost = 0,
    this.stock = 0,
    this.minStock = 0,
    this.unit = 'adet',
    this.imageUrl = '',
    this.isActive = true,
    this.warehouseId = '',
  });

  bool get isLowStock => stock <= minStock;

  CanteenProduct copyWith({
    String? id,
    String? institutionId,
    String? name,
    String? category,
    String? barcode,
    double? price,
    double? cost,
    int? stock,
    int? minStock,
    String? unit,
    String? imageUrl,
    bool? isActive,
    String? warehouseId,
  }) => CanteenProduct(
    id: id ?? this.id,
    institutionId: institutionId ?? this.institutionId,
    name: name ?? this.name,
    category: category ?? this.category,
    barcode: barcode ?? this.barcode,
    price: price ?? this.price,
    cost: cost ?? this.cost,
    stock: stock ?? this.stock,
    minStock: minStock ?? this.minStock,
    unit: unit ?? this.unit,
    imageUrl: imageUrl ?? this.imageUrl,
    isActive: isActive ?? this.isActive,
    warehouseId: warehouseId ?? this.warehouseId,
  );

  factory CanteenProduct.fromMap(Map<String, dynamic> m, {String id = ''}) =>
      CanteenProduct(
        id: id.isNotEmpty ? id : (m['id'] ?? '').toString(),
        institutionId: _inst(m['institutionId']),
        name: (m['name'] ?? '').toString(),
        category: (m['category'] ?? '').toString(),
        barcode: (m['barcode'] ?? '').toString(),
        price: _d(m['price']),
        cost: _d(m['cost']),
        stock: _i(m['stock']),
        minStock: _i(m['minStock']),
        unit: (m['unit'] ?? 'adet').toString(),
        imageUrl: (m['imageUrl'] ?? '').toString(),
        isActive: m['isActive'] as bool? ?? true,
        warehouseId: (m['warehouseId'] ?? '').toString(),
      );

  factory CanteenProduct.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      CanteenProduct.fromMap(doc.data() ?? {}, id: doc.id);

  Map<String, dynamic> toMap() => {
    'institutionId': institutionId,
    'name': name,
    'category': category,
    'barcode': barcode,
    'price': price,
    'cost': cost,
    'stock': stock,
    'minStock': minStock,
    'unit': unit,
    'imageUrl': imageUrl,
    'isActive': isActive,
    'warehouseId': warehouseId,
  };
}

class CanteenCard {
  final String cardNo;
  final String institutionId;
  final String studentId;
  final String studentName;
  final String className;
  final double balance;
  final bool isActive;
  final double dailyLimit; // 0 = limitsiz
  final List<String> blockedCategories;
  final List<String> blockedProductIds;
  final List<String> parentUids;
  final String parentEmail;

  const CanteenCard({
    required this.cardNo,
    this.institutionId = '',
    this.studentId = '',
    this.studentName = '',
    this.className = '',
    this.balance = 0,
    this.isActive = true,
    this.dailyLimit = 0,
    this.blockedCategories = const [],
    this.blockedProductIds = const [],
    this.parentUids = const [],
    this.parentEmail = '',
  });

  String get id => cardNo;

  CanteenCard copyWith({
    String? cardNo,
    String? institutionId,
    String? studentId,
    String? studentName,
    String? className,
    double? balance,
    bool? isActive,
    double? dailyLimit,
    List<String>? blockedCategories,
    List<String>? blockedProductIds,
    List<String>? parentUids,
    String? parentEmail,
  }) => CanteenCard(
    cardNo: cardNo ?? this.cardNo,
    institutionId: institutionId ?? this.institutionId,
    studentId: studentId ?? this.studentId,
    studentName: studentName ?? this.studentName,
    className: className ?? this.className,
    balance: balance ?? this.balance,
    isActive: isActive ?? this.isActive,
    dailyLimit: dailyLimit ?? this.dailyLimit,
    blockedCategories: blockedCategories ?? this.blockedCategories,
    blockedProductIds: blockedProductIds ?? this.blockedProductIds,
    parentUids: parentUids ?? this.parentUids,
    parentEmail: parentEmail ?? this.parentEmail,
  );

  factory CanteenCard.fromMap(Map<String, dynamic> m, {String id = ''}) =>
      CanteenCard(
        cardNo: (m['cardNo'] ?? id).toString().isNotEmpty
            ? (m['cardNo'] ?? id).toString()
            : id,
        institutionId: _inst(m['institutionId']),
        studentId: (m['studentId'] ?? '').toString(),
        studentName: (m['studentName'] ?? '').toString(),
        className: (m['className'] ?? '').toString(),
        balance: _d(m['balance']),
        isActive: m['isActive'] as bool? ?? true,
        dailyLimit: _d(m['dailyLimit']),
        blockedCategories: _sl(m['blockedCategories']),
        blockedProductIds: _sl(m['blockedProductIds']),
        parentUids: _sl(m['parentUids']),
        parentEmail: (m['parentEmail'] ?? '').toString(),
      );

  factory CanteenCard.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      CanteenCard.fromMap(doc.data() ?? {}, id: doc.id);

  Map<String, dynamic> toMap() => {
    'institutionId': institutionId,
    'studentId': studentId,
    'studentName': studentName,
    'className': className,
    'cardNo': cardNo,
    'balance': balance,
    'isActive': isActive,
    'dailyLimit': dailyLimit,
    'blockedCategories': blockedCategories,
    'blockedProductIds': blockedProductIds,
    'parentUids': parentUids,
    'parentEmail': parentEmail,
  };
}

class CanteenTransactionItem {
  final String productId;
  final String name;
  final int qty;
  final double price;

  const CanteenTransactionItem({
    required this.productId,
    required this.name,
    required this.qty,
    required this.price,
  });

  double get total => qty * price;

  factory CanteenTransactionItem.fromMap(Map<String, dynamic> m) =>
      CanteenTransactionItem(
        productId: (m['productId'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        qty: _i(m['qty']),
        price: _d(m['price']),
      );

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'name': name,
    'qty': qty,
    'price': price,
  };
}

class CanteenTransaction {
  final String id;
  final String institutionId;
  final String cardNo;
  final String studentId;
  final String type; // topup | sale | refund
  final String method; // card | mobile | qr | pos | cash | online
  final double amount;
  final List<CanteenTransactionItem> items;
  final double balanceAfter;
  final String cashierId;
  final String parentTransactionId;
  final String note;
  final double refundedAmount;
  final Map<String, int> refundedQtys;
  final DateTime? createdAt;

  const CanteenTransaction({
    this.id = '',
    this.institutionId = '',
    this.cardNo = '',
    this.studentId = '',
    required this.type,
    this.method = 'card',
    required this.amount,
    this.items = const [],
    this.balanceAfter = 0,
    this.cashierId = '',
    this.parentTransactionId = '',
    this.note = '',
    this.refundedAmount = 0,
    this.refundedQtys = const {},
    this.createdAt,
  });

  static String itemRefundKey(CanteenTransactionItem item, int index) {
    final pid = item.productId.trim();
    if (pid.isNotEmpty) return pid;
    return 'idx_${index}_${item.name.trim()}';
  }

  int refundedQtyFor(CanteenTransactionItem item, int index) {
    final key = itemRefundKey(item, index);
    final byKey = refundedQtys[key] ?? 0;
    if (byKey > 0) return byKey.clamp(0, item.qty);
    if (isFullyRefundedRaw) return item.qty;
    return 0;
  }

  int refundableQtyFor(CanteenTransactionItem item, int index) {
    final rem = item.qty - refundedQtyFor(item, index);
    return rem < 0 ? 0 : rem;
  }

  bool get isFullyRefundedRaw =>
      type == 'sale' && amount > 0 && refundedAmount >= amount - 0.009;

  bool get isFullyRefunded {
    if (type != 'sale') return false;
    if (isFullyRefundedRaw) return true;
    if (items.isEmpty) return false;
    for (int i = 0; i < items.length; i++) {
      if (refundableQtyFor(items[i], i) > 0) return false;
    }
    return true;
  }

  bool get isPartiallyRefunded =>
      type == 'sale' && refundedAmount > 0.009 && !isFullyRefunded;

  double get remainingRefundableAmount {
    if (type != 'sale') return 0;
    final rem = amount - refundedAmount;
    return rem < 0 ? 0 : rem;
  }

  static Map<String, int> _parseRefundedQtys(dynamic v) {
    if (v is! Map) return const {};
    final out = <String, int>{};
    v.forEach((k, val) {
      final key = (k ?? '').toString().trim();
      final qty = _i(val);
      if (key.isNotEmpty && qty > 0) {
        out[key] = qty;
      }
    });
    return out;
  }

  factory CanteenTransaction.fromMap(
    Map<String, dynamic> m, {
    String id = '',
  }) => CanteenTransaction(
    id: id,
    institutionId: _inst(m['institutionId']),
    cardNo: (m['cardNo'] ?? '').toString(),
    studentId: (m['studentId'] ?? '').toString(),
    type: (m['type'] ?? 'sale').toString(),
    method: (m['method'] ?? 'card').toString(),
    amount: _d(m['amount']),
    items: m['items'] is Iterable
        ? (m['items'] as Iterable)
              .whereType<Map>()
              .map(
                (e) => CanteenTransactionItem.fromMap(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList()
        : const [],
    balanceAfter: _d(m['balanceAfter']),
    cashierId: (m['cashierId'] ?? '').toString(),
    parentTransactionId: (m['parentTransactionId'] ?? '').toString(),
    note: (m['note'] ?? '').toString(),
    refundedAmount: _d(m['refundedAmount']),
    refundedQtys: _parseRefundedQtys(m['refundedQtys']),
    createdAt: _dt(m['createdAt']),
  );

  factory CanteenTransaction.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) => CanteenTransaction.fromMap(doc.data() ?? {}, id: doc.id);

  Map<String, dynamic> toMap() => {
    'institutionId': institutionId,
    'cardNo': cardNo,
    'studentId': studentId,
    'type': type,
    'method': method,
    'amount': amount,
    'items': items.map((e) => e.toMap()).toList(),
    'balanceAfter': balanceAfter,
    'cashierId': cashierId,
    if (parentTransactionId.isNotEmpty)
      'parentTransactionId': parentTransactionId,
    if (note.isNotEmpty) 'note': note,
    if (refundedAmount > 0) 'refundedAmount': refundedAmount,
    if (refundedQtys.isNotEmpty) 'refundedQtys': refundedQtys,
    'createdAt': createdAt == null
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(createdAt!),
  };
}

class CanteenWarehouse {
  final String id;
  final String institutionId;
  final String name;
  final String description;
  final bool isActive;

  const CanteenWarehouse({
    this.id = '',
    this.institutionId = '',
    required this.name,
    this.description = '',
    this.isActive = true,
  });

  factory CanteenWarehouse.fromMap(Map<String, dynamic> m, {String id = ''}) =>
      CanteenWarehouse(
        id: id.isNotEmpty ? id : (m['id'] ?? '').toString(),
        institutionId: _inst(m['institutionId']),
        name: (m['name'] ?? '').toString(),
        description: (m['description'] ?? '').toString(),
        isActive: m['isActive'] as bool? ?? true,
      );

  factory CanteenWarehouse.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) => CanteenWarehouse.fromMap(doc.data() ?? {}, id: doc.id);

  Map<String, dynamic> toMap() => {
    'institutionId': institutionId,
    'name': name,
    'description': description,
    'isActive': isActive,
  };
}

class CanteenStockMovement {
  final String id;
  final String institutionId;
  final String productId;
  final String type; // in | out | adjust
  final int qty;
  final String note;
  final DateTime? createdAt;
  final String by;

  const CanteenStockMovement({
    this.id = '',
    this.institutionId = '',
    required this.productId,
    required this.type,
    required this.qty,
    this.note = '',
    this.createdAt,
    this.by = '',
  });

  factory CanteenStockMovement.fromMap(
    Map<String, dynamic> m, {
    String id = '',
  }) => CanteenStockMovement(
    id: id,
    institutionId: _inst(m['institutionId']),
    productId: (m['productId'] ?? '').toString(),
    type: (m['type'] ?? 'adjust').toString(),
    qty: _i(m['qty']),
    note: (m['note'] ?? '').toString(),
    createdAt: _dt(m['createdAt']),
    by: (m['by'] ?? '').toString(),
  );

  factory CanteenStockMovement.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) => CanteenStockMovement.fromMap(doc.data() ?? {}, id: doc.id);

  Map<String, dynamic> toMap() => {
    'institutionId': institutionId,
    'productId': productId,
    'type': type,
    'qty': qty,
    'note': note,
    'createdAt': createdAt == null
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(createdAt!),
    'by': by,
  };
}

class CanteenLedgerEntry {
  final String id;
  final String institutionId;
  final String type; // income | expense
  final String category;
  final double amount;
  final String note;
  final DateTime? date;
  final DateTime? createdAt;

  const CanteenLedgerEntry({
    this.id = '',
    this.institutionId = '',
    required this.type,
    this.category = '',
    required this.amount,
    this.note = '',
    this.date,
    this.createdAt,
  });

  bool get isIncome => type == 'income';

  factory CanteenLedgerEntry.fromMap(
    Map<String, dynamic> m, {
    String id = '',
  }) => CanteenLedgerEntry(
    id: id,
    institutionId: _inst(m['institutionId']),
    type: (m['type'] ?? 'income').toString(),
    category: (m['category'] ?? '').toString(),
    amount: _d(m['amount']),
    note: (m['note'] ?? '').toString(),
    date: _dt(m['date']),
    createdAt: _dt(m['createdAt']),
  );

  factory CanteenLedgerEntry.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) => CanteenLedgerEntry.fromMap(doc.data() ?? {}, id: doc.id);

  Map<String, dynamic> toMap() => {
    'institutionId': institutionId,
    'type': type,
    'category': category,
    'amount': amount,
    'note': note,
    'date': Timestamp.fromDate(date ?? DateTime.now()),
    'createdAt': FieldValue.serverTimestamp(),
  };
}

/// Kasada `Mobil / QR` seçildiğinde üretilen canlı karekod ödeme oturumu.
class CanteenQrSession {
  final String id;
  final String institutionId;
  final String shortCode; // 6 haneli tek kullanımlık kod
  final List<CanteenTransactionItem> items;
  final double total;
  final String status; // pending | paid | cancelled | expired
  final String cashierId;
  final String payerUid;
  final String payerName;
  final String payerRole;
  final String cardNo;
  final String payVia; // wallet | online
  final String transactionId;
  final double? balanceAfter;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final DateTime? paidAt;

  const CanteenQrSession({
    this.id = '',
    this.institutionId = '',
    this.shortCode = '',
    this.items = const [],
    this.total = 0,
    this.status = 'pending',
    this.cashierId = '',
    this.payerUid = '',
    this.payerName = '',
    this.payerRole = '',
    this.cardNo = '',
    this.payVia = 'wallet',
    this.transactionId = '',
    this.balanceAfter,
    this.createdAt,
    this.expiresAt,
    this.paidAt,
  });

  String get qrPayload => 'KANTINPAY:$institutionId:$id';

  String get formattedShortCode {
    final s = shortCode.trim();
    if (s.length == 6) return '${s.substring(0, 3)} ${s.substring(3)}';
    return s;
  }

  bool get isPending => status == 'pending';
  bool get isPaid => status == 'paid';
  bool get isExpired =>
      status == 'expired' ||
      (expiresAt != null && DateTime.now().isAfter(expiresAt!));

  factory CanteenQrSession.fromMap(Map<String, dynamic> m, {String id = ''}) =>
      CanteenQrSession(
        id: id.isNotEmpty ? id : (m['id'] ?? '').toString(),
        institutionId: _inst(m['institutionId']),
        shortCode: (m['shortCode'] ?? '').toString(),
        items: m['items'] is Iterable
            ? (m['items'] as Iterable)
                  .whereType<Map>()
                  .map(
                    (e) => CanteenTransactionItem.fromMap(
                      Map<String, dynamic>.from(e),
                    ),
                  )
                  .toList()
            : const [],
        total: _d(m['total']),
        status: (m['status'] ?? 'pending').toString(),
        cashierId: (m['cashierId'] ?? '').toString(),
        payerUid: (m['payerUid'] ?? '').toString(),
        payerName: (m['payerName'] ?? '').toString(),
        payerRole: (m['payerRole'] ?? '').toString(),
        cardNo: (m['cardNo'] ?? '').toString(),
        payVia: (m['payVia'] ?? 'wallet').toString(),
        transactionId: (m['transactionId'] ?? '').toString(),
        balanceAfter: m['balanceAfter'] == null ? null : _d(m['balanceAfter']),
        createdAt: _dt(m['createdAt']),
        expiresAt: _dt(m['expiresAt']),
        paidAt: _dt(m['paidAt']),
      );

  factory CanteenQrSession.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) => CanteenQrSession.fromMap(doc.data() ?? {}, id: doc.id);

  Map<String, dynamic> toMap() => {
    'institutionId': institutionId,
    'shortCode': shortCode,
    'items': items.map((e) => e.toMap()).toList(),
    'total': total,
    'status': status,
    'cashierId': cashierId,
    'payerUid': payerUid,
    'payerName': payerName,
    'payerRole': payerRole,
    'cardNo': cardNo,
    'payVia': payVia,
    'transactionId': transactionId,
    if (balanceAfter != null) 'balanceAfter': balanceAfter,
    'createdAt': createdAt == null
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(createdAt!),
    if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt!),
    if (paidAt != null) 'paidAt': Timestamp.fromDate(paidAt!),
  };
}
