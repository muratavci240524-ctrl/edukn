import 'package:cloud_firestore/cloud_firestore.dart';

/// Depo Türü: 'central' (Merkez Ana Depo) veya 'schoolType' (Okul Türüne Özel Depo)
class WarehouseModel {
  final String id;
  final String institutionId;
  final String schoolDocId;
  final String name;
  final String type; // 'central' | 'schoolType'
  final String schoolTypeId;
  final String schoolTypeName;
  final String location;
  final List<String> responsibleUserIds;
  final List<String> responsibleNames;
  final bool isActive;
  final DateTime createdAt;

  const WarehouseModel({
    required this.id,
    required this.institutionId,
    required this.schoolDocId,
    required this.name,
    this.type = 'central',
    this.schoolTypeId = '',
    this.schoolTypeName = '',
    this.location = '',
    this.responsibleUserIds = const [],
    this.responsibleNames = const [],
    this.isActive = true,
    required this.createdAt,
  });

  bool get isCentral => type == 'central' || schoolTypeId.trim().isEmpty;

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'schoolDocId': schoolDocId,
      'name': name,
      'type': isCentral ? 'central' : 'schoolType',
      'schoolTypeId': isCentral ? '' : schoolTypeId,
      'schoolTypeName': isCentral ? '' : schoolTypeName,
      'location': location,
      'responsibleUserIds': responsibleUserIds,
      'responsibleNames': responsibleNames,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory WarehouseModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return WarehouseModel(
      id: doc.id,
      institutionId: (d['institutionId'] ?? '').toString(),
      schoolDocId: (d['schoolDocId'] ?? '').toString(),
      name: (d['name'] ?? 'Depo').toString(),
      type: (d['type'] ?? 'central').toString(),
      schoolTypeId: (d['schoolTypeId'] ?? '').toString(),
      schoolTypeName: (d['schoolTypeName'] ?? '').toString(),
      location: (d['location'] ?? '').toString(),
      responsibleUserIds: List<String>.from(d['responsibleUserIds'] ?? const []),
      responsibleNames: List<String>.from(d['responsibleNames'] ?? const []),
      isActive: d['isActive'] != false,
      createdAt: _parseDate(d['createdAt']),
    );
  }
}

/// Depodaki Malzeme / Stok Kartı
class InventoryItemModel {
  final String id;
  final String institutionId;
  final String schoolDocId;
  final String warehouseId;
  final String warehouseName;
  final String schoolTypeId;
  final String name;
  final String normalizedName;
  final String category;
  final String unit;
  final double quantity;
  final double minStockLevel;
  final String shelfLocation;
  final String barcode;
  final String productLink;
  final String imageUrl;
  final double lastUnitPrice;
  final DateTime updatedAt;

  const InventoryItemModel({
    required this.id,
    required this.institutionId,
    required this.schoolDocId,
    required this.warehouseId,
    required this.warehouseName,
    this.schoolTypeId = '',
    required this.name,
    required this.normalizedName,
    this.category = 'Kırtasiye',
    this.unit = 'Adet',
    this.quantity = 0,
    this.minStockLevel = 0,
    this.shelfLocation = '',
    this.barcode = '',
    this.productLink = '',
    this.imageUrl = '',
    this.lastUnitPrice = 0,
    required this.updatedAt,
  });

  bool get isOutOfStock => quantity <= 0;
  bool get isCriticalStock => quantity <= minStockLevel && minStockLevel > 0;

  String get formattedQty => formatQty(quantity);
  String get formattedMinQty => formatQty(minStockLevel);

  static String formatQty(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  static const List<String> defaultCategories = [
    'Kırtasiye & Ofis',
    'Temizlik & Hijyen',
    'Bilişim & Elektronik',
    'Laboratuvar & Fen',
    'Spor & Etkinlik',
    'Yemek & Mutfak',
    'Bakım & Onarım',
    'Mobilya & Demirbaş',
    'Sağlık / Revir Malzemesi',
    'Diğer',
  ];

  static const List<String> defaultUnits = [
    'Adet',
    'Kutu',
    'Paket',
    'Koli',
    'Top',
    'Takım',
    'Litre',
    'Kg',
    'Metre',
  ];

  static String normalizeTr(String input) {
    return input
        .trim()
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .replaceAll('Ç', 'ç')
        .replaceAll('Ğ', 'ğ')
        .replaceAll('Ö', 'ö')
        .replaceAll('Ş', 'ş')
        .replaceAll('Ü', 'ü')
        .toLowerCase();
  }

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'schoolDocId': schoolDocId,
      'warehouseId': warehouseId,
      'warehouseName': warehouseName,
      'schoolTypeId': schoolTypeId,
      'name': name.trim(),
      'normalizedName': normalizeTr(name),
      'category': category,
      'unit': unit,
      'quantity': quantity,
      'minStockLevel': minStockLevel,
      'shelfLocation': shelfLocation,
      'barcode': barcode,
      'productLink': productLink,
      'imageUrl': imageUrl,
      'lastUnitPrice': lastUnitPrice,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory InventoryItemModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final name = (d['name'] ?? '').toString();
    return InventoryItemModel(
      id: doc.id,
      institutionId: (d['institutionId'] ?? '').toString(),
      schoolDocId: (d['schoolDocId'] ?? '').toString(),
      warehouseId: (d['warehouseId'] ?? '').toString(),
      warehouseName: (d['warehouseName'] ?? 'Depo').toString(),
      schoolTypeId: (d['schoolTypeId'] ?? '').toString(),
      name: name,
      normalizedName: (d['normalizedName'] ?? normalizeTr(name)).toString(),
      category: (d['category'] ?? 'Kırtasiye & Ofis').toString(),
      unit: (d['unit'] ?? 'Adet').toString(),
      quantity: (d['quantity'] as num?)?.toDouble() ?? 0,
      minStockLevel: (d['minStockLevel'] as num?)?.toDouble() ?? 0,
      shelfLocation: (d['shelfLocation'] ?? '').toString(),
      barcode: (d['barcode'] ?? '').toString(),
      productLink: (d['productLink'] ?? '').toString(),
      imageUrl: (d['imageUrl'] ?? '').toString(),
      lastUnitPrice: (d['lastUnitPrice'] as num?)?.toDouble() ?? 0,
      updatedAt: _parseDate(d['updatedAt']),
    );
  }
}

/// Stok Giriş / Çıkış / Teslimat / Mal Kabul Hareket Kaydı
class StockTransactionModel {
  final String id;
  final String institutionId;
  final String warehouseId;
  final String warehouseName;
  final String schoolTypeId;
  final String itemId;
  final String itemName;
  final String unit;
  final String type; // 'in' | 'out' | 'adjustment' | 'transfer_in' | 'transfer_out' | 'request_delivery' | 'purchase_receipt'
  final double quantity;
  final double previousQty;
  final double newQty;
  final String relatedRequestId;
  final String actorUid;
  final String actorName;
  final String recipientName;
  final String note;
  final DateTime createdAt;

  const StockTransactionModel({
    required this.id,
    required this.institutionId,
    required this.warehouseId,
    required this.warehouseName,
    this.schoolTypeId = '',
    required this.itemId,
    required this.itemName,
    this.unit = 'Adet',
    required this.type,
    required this.quantity,
    required this.previousQty,
    required this.newQty,
    this.relatedRequestId = '',
    this.actorUid = '',
    this.actorName = '',
    this.recipientName = '',
    this.note = '',
    required this.createdAt,
  });

  bool get isAddition =>
      type == 'in' || type == 'transfer_in' || type == 'purchase_receipt' || (type == 'adjustment' && newQty >= previousQty);

  String get typeLabel {
    switch (type) {
      case 'in':
        return 'Manuel Stok Girişi';
      case 'out':
        return 'Manuel Çıkış / Zimmet';
      case 'adjustment':
        return 'Sayım Düzeltmesi';
      case 'transfer_in':
        return 'Depo Transfer Girişi';
      case 'transfer_out':
        return 'Depo Transfer Çıkışı';
      case 'request_delivery':
        return 'Talep Teslimatı (Çıkış)';
      case 'purchase_receipt':
        return 'Satın Alma Mal Kabul (Giriş)';
      default:
        return 'Stok Hareketi';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'warehouseId': warehouseId,
      'warehouseName': warehouseName,
      'schoolTypeId': schoolTypeId,
      'itemId': itemId,
      'itemName': itemName,
      'unit': unit,
      'type': type,
      'quantity': quantity,
      'previousQty': previousQty,
      'newQty': newQty,
      'relatedRequestId': relatedRequestId,
      'actorUid': actorUid,
      'actorName': actorName,
      'recipientName': recipientName,
      'note': note,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory StockTransactionModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return StockTransactionModel(
      id: doc.id,
      institutionId: (d['institutionId'] ?? '').toString(),
      warehouseId: (d['warehouseId'] ?? '').toString(),
      warehouseName: (d['warehouseName'] ?? '').toString(),
      schoolTypeId: (d['schoolTypeId'] ?? '').toString(),
      itemId: (d['itemId'] ?? '').toString(),
      itemName: (d['itemName'] ?? '').toString(),
      unit: (d['unit'] ?? 'Adet').toString(),
      type: (d['type'] ?? 'in').toString(),
      quantity: (d['quantity'] as num?)?.toDouble() ?? 0,
      previousQty: (d['previousQty'] as num?)?.toDouble() ?? 0,
      newQty: (d['newQty'] as num?)?.toDouble() ?? 0,
      relatedRequestId: (d['relatedRequestId'] ?? '').toString(),
      actorUid: (d['actorUid'] ?? '').toString(),
      actorName: (d['actorName'] ?? '').toString(),
      recipientName: (d['recipientName'] ?? '').toString(),
      note: (d['note'] ?? '').toString(),
      createdAt: _parseDate(d['createdAt']),
    );
  }
}

/// Satın Alma Biriminin Girdiği Tedarikçi Teklifi
class SupplierQuoteModel {
  final String id;
  final String supplierName;
  final double unitPrice;
  final double quantity;
  final int vatRate;
  final bool vatIncluded;
  final double totalPrice;
  final String deliveryInfo;
  final String productLink;
  final String attachmentUrl;
  final String note;
  final bool isRecommended;
  final String addedByUid;
  final String addedByName;
  final DateTime createdAt;

  const SupplierQuoteModel({
    required this.id,
    required this.supplierName,
    required this.unitPrice,
    required this.quantity,
    this.vatRate = 20,
    this.vatIncluded = true,
    required this.totalPrice,
    this.deliveryInfo = '',
    this.productLink = '',
    this.attachmentUrl = '',
    this.note = '',
    this.isRecommended = false,
    this.addedByUid = '',
    this.addedByName = '',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'supplierName': supplierName,
      'unitPrice': unitPrice,
      'quantity': quantity,
      'vatRate': vatRate,
      'vatIncluded': vatIncluded,
      'totalPrice': totalPrice,
      'deliveryInfo': deliveryInfo,
      'productLink': productLink,
      'attachmentUrl': attachmentUrl,
      'note': note,
      'isRecommended': isRecommended,
      'addedByUid': addedByUid,
      'addedByName': addedByName,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory SupplierQuoteModel.fromMap(Map<String, dynamic> d) {
    return SupplierQuoteModel(
      id: (d['id'] ?? '').toString(),
      supplierName: (d['supplierName'] ?? '').toString(),
      unitPrice: (d['unitPrice'] as num?)?.toDouble() ?? 0,
      quantity: (d['quantity'] as num?)?.toDouble() ?? 1,
      vatRate: (d['vatRate'] as num?)?.toInt() ?? 20,
      vatIncluded: d['vatIncluded'] != false,
      totalPrice: (d['totalPrice'] as num?)?.toDouble() ?? 0,
      deliveryInfo: (d['deliveryInfo'] ?? '').toString(),
      productLink: (d['productLink'] ?? '').toString(),
      attachmentUrl: (d['attachmentUrl'] ?? '').toString(),
      note: (d['note'] ?? '').toString(),
      isRecommended: d['isRecommended'] == true,
      addedByUid: (d['addedByUid'] ?? '').toString(),
      addedByName: (d['addedByName'] ?? '').toString(),
      createdAt: _parseDate(d['createdAt']),
    );
  }
}

/// Talep Tarihçe Adımı
class RequestTimelineEntry {
  final String stage;
  final String title;
  final String actorUid;
  final String actorName;
  final String note;
  final DateTime timestamp;

  const RequestTimelineEntry({
    required this.stage,
    required this.title,
    this.actorUid = '',
    required this.actorName,
    this.note = '',
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'stage': stage,
      'title': title,
      'actorUid': actorUid,
      'actorName': actorName,
      'note': note,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }

  factory RequestTimelineEntry.fromMap(Map<String, dynamic> d) {
    return RequestTimelineEntry(
      stage: (d['stage'] ?? '').toString(),
      title: (d['title'] ?? '').toString(),
      actorUid: (d['actorUid'] ?? '').toString(),
      actorName: (d['actorName'] ?? '').toString(),
      note: (d['note'] ?? '').toString(),
      timestamp: _parseDate(d['timestamp']),
    );
  }
}

/// Malzeme & Satın Alma Talebi Modeli
///
/// Durum Akışı (`status`):
/// - `pending_supervisor`      : 1. Kademe Amir Onayı Bekliyor
/// - `approved_for_warehouse`  : Depoda Hazır — Depocu Teslimatı Bekliyor
/// - `pending_upper_approver`  : Stokta Yok — 2. Kademe Üst Yetkili Oluru Bekliyor
/// - `in_procurement`          : Satın Alma Biriminde — Teklif Toplanıyor
/// - `quotes_submitted`        : Teklifler Girildi — Üst Amir Teklif Onayı Bekliyor
/// - `purchase_approved`       : Teklif Onaylandı — Sipariş Geçilecek
/// - `purchase_ordered`        : Sipariş Verildi — Depocu Mal Kabul Onayı Bekliyor
/// - `delivered`               : Öğretmene/Personele Teslim Edildi (Tamamlandı)
/// - `rejected`                : Reddedildi / İptal Edildi
class MaterialRequestModel {
  final String id;
  final String institutionId;
  final String schoolDocId;
  final String schoolTypeId;
  final String schoolTypeName;

  final String requesterUid;
  final String requesterName;
  final String requesterRole;

  final String linkedItemId;
  final String targetWarehouseId;
  final String targetWarehouseName;

  final String itemName;
  final String normalizedItemName;
  final String category;
  final double quantity;
  final String unit;
  final String urgency; // 'normal' | 'urgent'
  final String productLink;
  final List<String> imageUrls;
  final String description;

  final String status;

  final String supervisorUid;
  final String supervisorName;
  final String supervisorNote;

  final String upperApproverUid;
  final String upperApproverName;
  final String upperApproverNote;

  final String rejectionReason;

  final List<SupplierQuoteModel> quotes;
  final String approvedQuoteId;

  final String selectedKasaId;
  final String selectedKasaName;
  final bool autoRecordExpense;
  final String accountingTransactionId;
  final String orderNote;

  final DateTime? warehouseReceivedAt;
  final String warehouseReceivedByName;

  final DateTime? deliveredAt;
  final String deliveredByName;
  final String deliveryNote;

  final List<RequestTimelineEntry> timeline;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MaterialRequestModel({
    required this.id,
    required this.institutionId,
    required this.schoolDocId,
    this.schoolTypeId = '',
    this.schoolTypeName = '',
    required this.requesterUid,
    required this.requesterName,
    this.requesterRole = '',
    this.linkedItemId = '',
    this.targetWarehouseId = '',
    this.targetWarehouseName = '',
    required this.itemName,
    required this.normalizedItemName,
    this.category = 'Kırtasiye & Ofis',
    required this.quantity,
    this.unit = 'Adet',
    this.urgency = 'normal',
    this.productLink = '',
    this.imageUrls = const [],
    this.description = '',
    this.status = 'pending_supervisor',
    this.supervisorUid = '',
    this.supervisorName = '',
    this.supervisorNote = '',
    this.upperApproverUid = '',
    this.upperApproverName = '',
    this.upperApproverNote = '',
    this.rejectionReason = '',
    this.quotes = const [],
    this.approvedQuoteId = '',
    this.selectedKasaId = '',
    this.selectedKasaName = '',
    this.autoRecordExpense = true,
    this.accountingTransactionId = '',
    this.orderNote = '',
    this.warehouseReceivedAt,
    this.warehouseReceivedByName = '',
    this.deliveredAt,
    this.deliveredByName = '',
    this.deliveryNote = '',
    this.timeline = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isUrgent => urgency == 'urgent';
  bool get isClosed => status == 'delivered' || status == 'rejected';
  bool get wasPurchased =>
      approvedQuoteId.isNotEmpty || warehouseReceivedAt != null;

  String get formattedQty => InventoryItemModel.formatQty(quantity);

  SupplierQuoteModel? get approvedQuote {
    if (approvedQuoteId.isEmpty) return null;
    for (final q in quotes) {
      if (q.id == approvedQuoteId) return q;
    }
    return null;
  }

  String get statusLabel {
    switch (status) {
      case 'pending_supervisor':
        return '1. Amir Onayı Bekliyor';
      case 'approved_for_warehouse':
        return warehouseReceivedAt != null
            ? 'Depoya Geldi • Teslim Bekliyor'
            : 'Depoda Mevcut • Teslim Bekliyor';
      case 'pending_upper_approver':
        return 'Üst Yetkili Satın Alma Oluru Bekliyor';
      case 'in_procurement':
        return 'Satın Almada • Teklif Toplanıyor';
      case 'quotes_submitted':
        return 'Teklif Seçimi & Üst Onay Bekliyor';
      case 'purchase_approved':
        return 'Teklif Onaylandı • Sipariş Geçilecek';
      case 'purchase_ordered':
        return 'Sipariş Verildi • Depo Mal Kabul Bekliyor';
      case 'delivered':
        return 'Teslim Edildi';
      case 'rejected':
        return 'Reddedildi';
      default:
        return status;
    }
  }

  /// Öğretmen takip kartı için sadeleştirilmiş adım indeksi (0..4)
  int get progressStep {
    switch (status) {
      case 'pending_supervisor':
        return 0;
      case 'pending_upper_approver':
      case 'in_procurement':
      case 'quotes_submitted':
      case 'purchase_approved':
        return 1;
      case 'purchase_ordered':
        return 2;
      case 'approved_for_warehouse':
        return 3;
      case 'delivered':
        return 4;
      default:
        return 0;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'schoolDocId': schoolDocId,
      'schoolTypeId': schoolTypeId,
      'schoolTypeName': schoolTypeName,
      'requesterUid': requesterUid,
      'requesterName': requesterName,
      'requesterRole': requesterRole,
      'linkedItemId': linkedItemId,
      'targetWarehouseId': targetWarehouseId,
      'targetWarehouseName': targetWarehouseName,
      'itemName': itemName.trim(),
      'normalizedItemName': InventoryItemModel.normalizeTr(itemName),
      'category': category,
      'quantity': quantity,
      'unit': unit,
      'urgency': urgency,
      'productLink': productLink,
      'imageUrls': imageUrls,
      'description': description,
      'status': status,
      'supervisorUid': supervisorUid,
      'supervisorName': supervisorName,
      'supervisorNote': supervisorNote,
      'upperApproverUid': upperApproverUid,
      'upperApproverName': upperApproverName,
      'upperApproverNote': upperApproverNote,
      'rejectionReason': rejectionReason,
      'quotes': quotes.map((q) => q.toMap()).toList(),
      'approvedQuoteId': approvedQuoteId,
      'selectedKasaId': selectedKasaId,
      'selectedKasaName': selectedKasaName,
      'autoRecordExpense': autoRecordExpense,
      'accountingTransactionId': accountingTransactionId,
      'orderNote': orderNote,
      'warehouseReceivedAt': warehouseReceivedAt != null
          ? Timestamp.fromDate(warehouseReceivedAt!)
          : null,
      'warehouseReceivedByName': warehouseReceivedByName,
      'deliveredAt':
          deliveredAt != null ? Timestamp.fromDate(deliveredAt!) : null,
      'deliveredByName': deliveredByName,
      'deliveryNote': deliveryNote,
      'timeline': timeline.map((t) => t.toMap()).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory MaterialRequestModel.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final itemName = (d['itemName'] ?? '').toString();
    final rawQuotes = d['quotes'] as List<dynamic>? ?? const [];
    final rawTimeline = d['timeline'] as List<dynamic>? ?? const [];

    return MaterialRequestModel(
      id: doc.id,
      institutionId: (d['institutionId'] ?? '').toString(),
      schoolDocId: (d['schoolDocId'] ?? '').toString(),
      schoolTypeId: (d['schoolTypeId'] ?? '').toString(),
      schoolTypeName: (d['schoolTypeName'] ?? '').toString(),
      requesterUid: (d['requesterUid'] ?? '').toString(),
      requesterName: (d['requesterName'] ?? '').toString(),
      requesterRole: (d['requesterRole'] ?? '').toString(),
      linkedItemId: (d['linkedItemId'] ?? '').toString(),
      targetWarehouseId: (d['targetWarehouseId'] ?? '').toString(),
      targetWarehouseName: (d['targetWarehouseName'] ?? '').toString(),
      itemName: itemName,
      normalizedItemName: (d['normalizedItemName'] ??
              InventoryItemModel.normalizeTr(itemName))
          .toString(),
      category: (d['category'] ?? 'Kırtasiye & Ofis').toString(),
      quantity: (d['quantity'] as num?)?.toDouble() ?? 1,
      unit: (d['unit'] ?? 'Adet').toString(),
      urgency: (d['urgency'] ?? 'normal').toString(),
      productLink: (d['productLink'] ?? '').toString(),
      imageUrls: List<String>.from(d['imageUrls'] ?? const []),
      description: (d['description'] ?? '').toString(),
      status: (d['status'] ?? 'pending_supervisor').toString(),
      supervisorUid: (d['supervisorUid'] ?? '').toString(),
      supervisorName: (d['supervisorName'] ?? '').toString(),
      supervisorNote: (d['supervisorNote'] ?? '').toString(),
      upperApproverUid: (d['upperApproverUid'] ?? '').toString(),
      upperApproverName: (d['upperApproverName'] ?? '').toString(),
      upperApproverNote: (d['upperApproverNote'] ?? '').toString(),
      rejectionReason: (d['rejectionReason'] ?? '').toString(),
      quotes: rawQuotes
          .whereType<Map>()
          .map((e) => SupplierQuoteModel.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      approvedQuoteId: (d['approvedQuoteId'] ?? '').toString(),
      selectedKasaId: (d['selectedKasaId'] ?? '').toString(),
      selectedKasaName: (d['selectedKasaName'] ?? '').toString(),
      autoRecordExpense: d['autoRecordExpense'] != false,
      accountingTransactionId: (d['accountingTransactionId'] ?? '').toString(),
      orderNote: (d['orderNote'] ?? '').toString(),
      warehouseReceivedAt: d['warehouseReceivedAt'] != null
          ? _parseDate(d['warehouseReceivedAt'])
          : null,
      warehouseReceivedByName: (d['warehouseReceivedByName'] ?? '').toString(),
      deliveredAt:
          d['deliveredAt'] != null ? _parseDate(d['deliveredAt']) : null,
      deliveredByName: (d['deliveredByName'] ?? '').toString(),
      deliveryNote: (d['deliveryNote'] ?? '').toString(),
      timeline: rawTimeline
          .whereType<Map>()
          .map(
              (e) => RequestTimelineEntry.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      createdAt: _parseDate(d['createdAt']),
      updatedAt: _parseDate(d['updatedAt']),
    );
  }
}

/// Kurum Depo & Satın Alma Onay ve Entegrasyon Ayarları
class ProcurementConfigModel {
  final List<String> supervisorUids;
  final List<String> supervisorNames;
  final List<String> upperApproverUids;
  final List<String> upperApproverNames;
  final bool requireSecondLevelForPurchase;
  final bool autoRecordAccountingExpense;
  final bool allowCentralFallbackForSchoolTypes;
  final String defaultKasaId;

  const ProcurementConfigModel({
    this.supervisorUids = const [],
    this.supervisorNames = const [],
    this.upperApproverUids = const [],
    this.upperApproverNames = const [],
    this.requireSecondLevelForPurchase = true,
    this.autoRecordAccountingExpense = true,
    this.allowCentralFallbackForSchoolTypes = true,
    this.defaultKasaId = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'supervisorUids': supervisorUids,
      'supervisorNames': supervisorNames,
      'upperApproverUids': upperApproverUids,
      'upperApproverNames': upperApproverNames,
      'requireSecondLevelForPurchase': requireSecondLevelForPurchase,
      'autoRecordAccountingExpense': autoRecordAccountingExpense,
      'allowCentralFallbackForSchoolTypes': allowCentralFallbackForSchoolTypes,
      'defaultKasaId': defaultKasaId,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory ProcurementConfigModel.fromMap(Map<String, dynamic>? d) {
    if (d == null) return const ProcurementConfigModel();
    return ProcurementConfigModel(
      supervisorUids: List<String>.from(d['supervisorUids'] ?? const []),
      supervisorNames: List<String>.from(d['supervisorNames'] ?? const []),
      upperApproverUids: List<String>.from(d['upperApproverUids'] ?? const []),
      upperApproverNames:
          List<String>.from(d['upperApproverNames'] ?? const []),
      requireSecondLevelForPurchase: d['requireSecondLevelForPurchase'] != false,
      autoRecordAccountingExpense: d['autoRecordAccountingExpense'] != false,
      allowCentralFallbackForSchoolTypes:
          d['allowCentralFallbackForSchoolTypes'] != false,
      defaultKasaId: (d['defaultKasaId'] ?? '').toString(),
    );
  }
}

DateTime _parseDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
  return DateTime.now();
}

