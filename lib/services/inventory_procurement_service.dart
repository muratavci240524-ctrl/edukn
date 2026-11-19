import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/school/inventory_procurement_models.dart';
import 'crypto_service.dart';
import 'user_permission_service.dart';

class InventoryProcurementService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static final Map<String, String> _schoolDocIdCache = {};

  List<String> _instVariants(String institutionId) {
    return {
      institutionId.trim(),
      institutionId.trim().toUpperCase(),
      institutionId.trim().toLowerCase(),
    }.where((e) => e.isNotEmpty).toList();
  }

  /// `schools/{schoolDocId}` doküman ID'sini çözümler (önbellekli)
  Future<String> resolveSchoolDocId(String institutionId) async {
    final clean = institutionId.trim();
    if (clean.isEmpty) return '';
    if (_schoolDocIdCache.containsKey(clean)) {
      return _schoolDocIdCache[clean]!;
    }

    try {
      final variants = _instVariants(clean);
      final snap = await _db
          .collection('schools')
          .where('institutionId', whereIn: variants)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final id = snap.docs.first.id;
        _schoolDocIdCache[clean] = id;
        return id;
      }
      final direct = await _db.collection('schools').doc(clean).get();
      if (direct.exists) {
        _schoolDocIdCache[clean] = direct.id;
        return direct.id;
      }
    } catch (_) {}

    _schoolDocIdCache[clean] = clean;
    return clean;
  }

  /// Aktif kullanıcı bilgisini döner
  Future<
      ({
        String uid,
        String name,
        String role,
        String institutionId,
        Map<String, dynamic>? userData,
      })> resolveCurrentActor({String? fallbackInstitutionId}) async {
    final authUser = FirebaseAuth.instance.currentUser;
    final userData = await UserPermissionService.loadUserData();
    final uid = (userData?['authUserId'] ??
            userData?['id'] ??
            authUser?.uid ??
            '')
        .toString()
        .trim();
    final first = (userData?['firstName'] ?? '').toString().trim();
    final last = (userData?['lastName'] ?? '').toString().trim();
    final rawName = (userData?['fullName'] ??
            userData?['name'] ??
            authUser?.displayName ??
            '$first $last')
        .toString()
        .trim();
    final role = (userData?['role'] ?? userData?['title'] ?? 'personel')
        .toString()
        .trim()
        .toLowerCase();
    String instId =
        (userData?['institutionId'] ?? fallbackInstitutionId ?? '')
            .toString()
            .trim();
    if (instId.isEmpty && authUser?.email != null) {
      instId = await UserPermissionService.resolveInstitutionId(
        authUser!.email!,
        userData: userData,
      );
    }

    return (
      uid: uid,
      name: rawName.isNotEmpty ? rawName : (authUser?.email ?? 'Personel'),
      role: role,
      institutionId: instId,
      userData: userData,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // YETKİ KONTROLLERİ (ESNEK ROL + AYAR TABANLI)
  // ═══════════════════════════════════════════════════════════════════════════

  static bool isTopAdminRole(String role) {
    final r = role.trim().toLowerCase();
    return r == 'genel_mudur' ||
        r == 'mudur' ||
        r == 'müdür' ||
        r == 'admin' ||
        r == 'kurucu' ||
        r == 'super_admin' ||
        r == 'kurum_muduru' ||
        r == 'kurum_yoneticisi';
  }

  static bool canManageSettings(Map<String, dynamic>? userData) {
    if (userData == null) return false;
    final role = (userData['role'] ?? '').toString().toLowerCase();
    if (isTopAdminRole(role) || role == 'mudur_yardimcisi') return true;
    return UserPermissionService.canEditSubModule(
      'sistem_ayarlari',
      'yetki_tanimlama',
      userData,
    );
  }

  static bool canManageWarehouse(
    Map<String, dynamic>? userData, {
    WarehouseModel? warehouse,
    String? currentUid,
  }) {
    if (userData == null) return false;
    final role = (userData['role'] ?? '').toString().toLowerCase();
    final title = (userData['title'] ?? '').toString().toLowerCase();
    if (isTopAdminRole(role) ||
        role == 'mudur_yardimcisi' ||
        role == 'depo' ||
        title == 'depo' ||
        role == 'destek_hizmetleri') {
      if (warehouse != null &&
          (role == 'depo' || title == 'depo') &&
          warehouse.responsibleUserIds.isNotEmpty &&
          currentUid != null &&
          currentUid.isNotEmpty) {
        return warehouse.responsibleUserIds.contains(currentUid);
      }
      return true;
    }
    if (warehouse != null &&
        currentUid != null &&
        warehouse.responsibleUserIds.contains(currentUid)) {
      return true;
    }
    return UserPermissionService.canEditSubModule(
      'hizmetler',
      'depo_satin_alma',
      userData,
    );
  }

  static bool canManageProcurement(Map<String, dynamic>? userData) {
    if (userData == null) return false;
    final role = (userData['role'] ?? '').toString().toLowerCase();
    final title = (userData['title'] ?? '').toString().toLowerCase();
    if (isTopAdminRole(role) ||
        role == 'satin_alma' ||
        title == 'satin_alma' ||
        role == 'muhasebe') {
      return true;
    }
    return UserPermissionService.canEditSubModule(
          'hizmetler',
          'satin_alma_islemleri',
          userData,
        ) ||
        UserPermissionService.canEditSubModule(
          'hizmetler',
          'depo_satin_alma',
          userData,
        );
  }

  static bool canApproveFirstLevel(
    Map<String, dynamic>? userData,
    ProcurementConfigModel config, {
    String? currentUid,
  }) {
    if (userData == null) return false;
    final uid = (currentUid ??
            userData['authUserId'] ??
            userData['id'] ??
            '')
        .toString();
    final role = (userData['role'] ?? '').toString().toLowerCase();
    if (isTopAdminRole(role)) return true;
    if (config.supervisorUids.isNotEmpty) {
      return uid.isNotEmpty &&
          (config.supervisorUids.contains(uid) ||
              config.upperApproverUids.contains(uid));
    }
    return role == 'mudur_yardimcisi';
  }

  static bool canApproveUpperLevel(
    Map<String, dynamic>? userData,
    ProcurementConfigModel config, {
    String? currentUid,
  }) {
    if (userData == null) return false;
    final uid = (currentUid ??
            userData['authUserId'] ??
            userData['id'] ??
            '')
        .toString();
    final role = (userData['role'] ?? '').toString().toLowerCase();
    if (uid.isNotEmpty && config.upperApproverUids.contains(uid)) {
      return true;
    }
    if (config.upperApproverUids.isEmpty) {
      return isTopAdminRole(role);
    }
    return role == 'genel_mudur' || role == 'admin' || role == 'super_admin';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VARSAYILAN DEPO KURULUMU & DEPO SORGULARI
  // ═══════════════════════════════════════════════════════════════════════════

  /// Kurumda hiç depo yoksa otomatik "Merkez Ana Depo" oluşturur
  Future<void> ensureDefaultWarehouse({
    required String institutionId,
    required String schoolDocId,
  }) async {
    if (schoolDocId.isEmpty) return;
    try {
      final snap = await _db
          .collection('schools')
          .doc(schoolDocId)
          .collection('warehouses')
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        final wh = WarehouseModel(
          id: '',
          institutionId: institutionId,
          schoolDocId: schoolDocId,
          name: 'Merkez Ana Depo',
          type: 'central',
          location: 'Ana Bina',
          createdAt: DateTime.now(),
        );
        await _db
            .collection('schools')
            .doc(schoolDocId)
            .collection('warehouses')
            .add(wh.toMap());
      }
    } catch (_) {}
  }

  /// Görünür depoları canlı izler:
  /// - Genel Merkez (`fixedSchoolTypeId` boş) -> Tüm aktif depolar (Merkez + Okul Türü depoları)
  /// - Okul Türü (`fixedSchoolTypeId` dolu) -> Sadece o okul türüne ait depolar!
  Stream<List<WarehouseModel>> watchVisibleWarehouses({
    required String schoolDocId,
    String? fixedSchoolTypeId,
  }) {
    if (schoolDocId.isEmpty) return Stream.value(const []);
    return _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('warehouses')
        .snapshots()
        .map((snap) {
      final all = snap.docs
          .map((d) => WarehouseModel.fromDoc(d))
          .where((w) => w.isActive)
          .toList();

      final stId = (fixedSchoolTypeId ?? '').trim();
      final filtered = stId.isEmpty
          ? all
          : all.where((w) => w.schoolTypeId.trim() == stId).toList();

      filtered.sort((a, b) {
        if (a.isCentral != b.isCentral) return a.isCentral ? -1 : 1;
        return a.name.compareTo(b.name);
      });
      return filtered;
    });
  }

  /// Stok kontrolü ve yönlendirme için kurumun tüm aktif depolarını getirir
  Stream<List<WarehouseModel>> watchAllWarehouses(String schoolDocId) {
    if (schoolDocId.isEmpty) return Stream.value(const []);
    return _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('warehouses')
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => WarehouseModel.fromDoc(d))
          .where((w) => w.isActive)
          .toList();
      list.sort((a, b) {
        if (a.isCentral != b.isCentral) return a.isCentral ? -1 : 1;
        return a.name.compareTo(b.name);
      });
      return list;
    });
  }

  Future<void> saveWarehouse({
    required String schoolDocId,
    required WarehouseModel warehouse,
  }) async {
    final col =
        _db.collection('schools').doc(schoolDocId).collection('warehouses');
    if (warehouse.id.isEmpty) {
      await col.add(warehouse.toMap());
    } else {
      await col.doc(warehouse.id).update(warehouse.toMap());
    }
  }

  Future<void> archiveWarehouse({
    required String schoolDocId,
    required String warehouseId,
  }) async {
    await _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('warehouses')
        .doc(warehouseId)
        .update({'isActive': false});
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ENVANTER / STOK İŞLEMLERİ
  // ═══════════════════════════════════════════════════════════════════════════

  Stream<List<InventoryItemModel>> watchInventoryItems({
    required String schoolDocId,
    Set<String>? allowedWarehouseIds,
    String? selectedWarehouseId,
  }) {
    if (schoolDocId.isEmpty) return Stream.value(const []);
    return _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('inventoryItems')
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => InventoryItemModel.fromDoc(d))
          .where((item) {
            if (allowedWarehouseIds != null &&
                !allowedWarehouseIds.contains(item.warehouseId)) {
              return false;
            }
            if (selectedWarehouseId != null &&
                selectedWarehouseId.isNotEmpty &&
                item.warehouseId != selectedWarehouseId) {
              return false;
            }
            return true;
          })
          .toList();
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    });
  }

  Stream<List<StockTransactionModel>> watchStockTransactions({
    required String schoolDocId,
    Set<String>? allowedWarehouseIds,
    String? selectedWarehouseId,
    String? itemId,
  }) {
    if (schoolDocId.isEmpty) return Stream.value(const []);
    return _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('stockTransactions')
        .orderBy('createdAt', descending: true)
        .limit(120)
        .snapshots()
        .map((snap) {
      return snap.docs
          .map((d) => StockTransactionModel.fromDoc(d))
          .where((tx) {
            if (allowedWarehouseIds != null &&
                !allowedWarehouseIds.contains(tx.warehouseId)) {
              return false;
            }
            if (selectedWarehouseId != null &&
                selectedWarehouseId.isNotEmpty &&
                tx.warehouseId != selectedWarehouseId) {
              return false;
            }
            if (itemId != null && itemId.isNotEmpty && tx.itemId != itemId) {
              return false;
            }
            return true;
          })
          .toList();
    });
  }

  /// Yeni malzeme kartı açar veya mevcut malzeme kartının bilgilerini günceller
  Future<String> saveInventoryItem({
    required String schoolDocId,
    required InventoryItemModel item,
    required String actorUid,
    required String actorName,
  }) async {
    final itemsCol =
        _db.collection('schools').doc(schoolDocId).collection('inventoryItems');
    final txCol = _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('stockTransactions');

    if (item.id.isEmpty) {
      final docRef = await itemsCol.add(item.toMap());
      if (item.quantity > 0) {
        final txModel = StockTransactionModel(
          id: '',
          institutionId: item.institutionId,
          warehouseId: item.warehouseId,
          warehouseName: item.warehouseName,
          schoolTypeId: item.schoolTypeId,
          itemId: docRef.id,
          itemName: item.name,
          unit: item.unit,
          type: 'in',
          quantity: item.quantity,
          previousQty: 0,
          newQty: item.quantity,
          actorUid: actorUid,
          actorName: actorName,
          note: 'İlk stok kartı açılışı',
          createdAt: DateTime.now(),
        );
        await txCol.add(txModel.toMap());
      }
      return docRef.id;
    } else {
      await itemsCol.doc(item.id).update({
        'name': item.name.trim(),
        'normalizedName': InventoryItemModel.normalizeTr(item.name),
        'category': item.category,
        'unit': item.unit,
        'minStockLevel': item.minStockLevel,
        'shelfLocation': item.shelfLocation,
        'barcode': item.barcode,
        'productLink': item.productLink,
        'imageUrl': item.imageUrl,
        'lastUnitPrice': item.lastUnitPrice,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
      return item.id;
    }
  }

  /// Depocu manuel stok giriş / çıkış / sayım düzeltmesi
  Future<void> recordManualStockMovement({
    required String schoolDocId,
    required String itemId,
    required String type, // 'in' | 'out' | 'adjustment'
    required double quantity,
    required String actorUid,
    required String actorName,
    String recipientName = '',
    String note = '',
  }) async {
    final itemRef = _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('inventoryItems')
        .doc(itemId);
    final txCol = _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('stockTransactions');

    await _db.runTransaction((tx) async {
      final snap = await tx.get(itemRef);
      if (!snap.exists) throw 'Malzeme kartı bulunamadı.';
      final item = InventoryItemModel.fromDoc(snap);
      final prev = item.quantity;
      double next = prev;

      if (type == 'in') {
        next = prev + quantity;
      } else if (type == 'out') {
        if (prev < quantity) {
          throw 'Depoda yeterli stok yok! Mevcut: ${item.formattedQty} ${item.unit}';
        }
        next = prev - quantity;
      } else if (type == 'adjustment') {
        next = quantity;
      }

      tx.update(itemRef, {
        'quantity': next,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      final txDoc = txCol.doc();
      final stockTx = StockTransactionModel(
        id: txDoc.id,
        institutionId: item.institutionId,
        warehouseId: item.warehouseId,
        warehouseName: item.warehouseName,
        schoolTypeId: item.schoolTypeId,
        itemId: item.id,
        itemName: item.name,
        unit: item.unit,
        type: type,
        quantity: type == 'adjustment' ? (next - prev).abs() : quantity,
        previousQty: prev,
        newQty: next,
        actorUid: actorUid,
        actorName: actorName,
        recipientName: recipientName,
        note: note,
        createdAt: DateTime.now(),
      );
      tx.set(txDoc, stockTx.toMap());
    });
  }

  /// Depolar arası stok transferi (Örn: Merkez Ana Depo -> Lise Deposu)
  Future<void> transferBetweenWarehouses({
    required String schoolDocId,
    required String sourceItemId,
    required WarehouseModel targetWarehouse,
    required double quantity,
    required String actorUid,
    required String actorName,
    String note = '',
  }) async {
    if (quantity <= 0) throw 'Geçerli bir transfer miktarı giriniz.';
    final itemsCol =
        _db.collection('schools').doc(schoolDocId).collection('inventoryItems');
    final txCol = _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('stockTransactions');

    final sourceRef = itemsCol.doc(sourceItemId);
    final sourceSnap = await sourceRef.get();
    if (!sourceSnap.exists) throw 'Kaynak malzeme bulunamadı.';
    final sourceItem = InventoryItemModel.fromDoc(sourceSnap);
    if (sourceItem.warehouseId == targetWarehouse.id) {
      throw 'Kaynak ve hedef depo aynı olamaz.';
    }

    // Hedef depoda aynı ürün var mı ara
    final existingTargetSnap = await itemsCol
        .where('warehouseId', isEqualTo: targetWarehouse.id)
        .where('normalizedName', isEqualTo: sourceItem.normalizedName)
        .limit(1)
        .get();

    final DocumentReference<Map<String, dynamic>> targetRef =
        existingTargetSnap.docs.isNotEmpty
            ? existingTargetSnap.docs.first.reference
            : itemsCol.doc();

    await _db.runTransaction((tx) async {
      final freshSource = await tx.get(sourceRef);
      final srcQty = (freshSource.data()?['quantity'] as num?)?.toDouble() ?? 0;
      if (srcQty < quantity) {
        throw 'Kaynak depoda yeterli stok yok! Mevcut: ${InventoryItemModel.formatQty(srcQty)} ${sourceItem.unit}';
      }

      double targetPrev = 0;
      if (existingTargetSnap.docs.isNotEmpty) {
        final freshTarget = await tx.get(targetRef);
        targetPrev =
            (freshTarget.data()?['quantity'] as num?)?.toDouble() ?? 0;
      }

      final now = DateTime.now();
      final srcNext = srcQty - quantity;
      final tgtNext = targetPrev + quantity;

      tx.update(sourceRef, {
        'quantity': srcNext,
        'updatedAt': Timestamp.fromDate(now),
      });

      if (existingTargetSnap.docs.isNotEmpty) {
        tx.update(targetRef, {
          'quantity': tgtNext,
          'updatedAt': Timestamp.fromDate(now),
        });
      } else {
        final newTargetItem = InventoryItemModel(
          id: targetRef.id,
          institutionId: sourceItem.institutionId,
          schoolDocId: schoolDocId,
          warehouseId: targetWarehouse.id,
          warehouseName: targetWarehouse.name,
          schoolTypeId: targetWarehouse.schoolTypeId,
          name: sourceItem.name,
          normalizedName: sourceItem.normalizedName,
          category: sourceItem.category,
          unit: sourceItem.unit,
          quantity: tgtNext,
          minStockLevel: sourceItem.minStockLevel,
          productLink: sourceItem.productLink,
          imageUrl: sourceItem.imageUrl,
          lastUnitPrice: sourceItem.lastUnitPrice,
          updatedAt: now,
        );
        tx.set(targetRef, newTargetItem.toMap());
      }

      final outDoc = txCol.doc();
      tx.set(
        outDoc,
        StockTransactionModel(
          id: outDoc.id,
          institutionId: sourceItem.institutionId,
          warehouseId: sourceItem.warehouseId,
          warehouseName: sourceItem.warehouseName,
          schoolTypeId: sourceItem.schoolTypeId,
          itemId: sourceItem.id,
          itemName: sourceItem.name,
          unit: sourceItem.unit,
          type: 'transfer_out',
          quantity: quantity,
          previousQty: srcQty,
          newQty: srcNext,
          actorUid: actorUid,
          actorName: actorName,
          recipientName: targetWarehouse.name,
          note: note.isNotEmpty
              ? note
              : '${targetWarehouse.name} deposuna transfer',
          createdAt: now,
        ).toMap(),
      );

      final inDoc = txCol.doc();
      tx.set(
        inDoc,
        StockTransactionModel(
          id: inDoc.id,
          institutionId: sourceItem.institutionId,
          warehouseId: targetWarehouse.id,
          warehouseName: targetWarehouse.name,
          schoolTypeId: targetWarehouse.schoolTypeId,
          itemId: targetRef.id,
          itemName: sourceItem.name,
          unit: sourceItem.unit,
          type: 'transfer_in',
          quantity: quantity,
          previousQty: targetPrev,
          newQty: tgtNext,
          actorUid: actorUid,
          actorName: actorName,
          recipientName: sourceItem.warehouseName,
          note: note.isNotEmpty
              ? note
              : '${sourceItem.warehouseName} deposundan transfer',
          createdAt: now,
        ).toMap(),
      );
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GÖRSEL / PROFORMA DOSYA YÜKLEME
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String> uploadAttachmentBytes({
    required String schoolDocId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final ext = safeName.split('.').last.toLowerCase();
    String contentType = 'image/jpeg';
    if (ext == 'png') contentType = 'image/png';
    if (ext == 'webp') contentType = 'image/webp';
    if (ext == 'pdf') contentType = 'application/pdf';

    final ref = FirebaseStorage.instance
        .ref()
        .child('schools')
        .child(schoolDocId)
        .child('procurement')
        .child('${DateTime.now().millisecondsSinceEpoch}_$safeName');

    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return await ref.getDownloadURL();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TALEP, ONAY, SATIN ALMA TEKLİF & MALİ İŞLER SÜREÇLERİ
  // ═══════════════════════════════════════════════════════════════════════════

  Stream<ProcurementConfigModel> watchProcurementConfig(String schoolDocId) {
    if (schoolDocId.isEmpty) {
      return Stream.value(const ProcurementConfigModel());
    }
    return _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('settings')
        .doc('procurement_config')
        .snapshots()
        .map((snap) => ProcurementConfigModel.fromMap(snap.data()));
  }

  Future<void> saveProcurementConfig({
    required String schoolDocId,
    required ProcurementConfigModel config,
  }) async {
    await _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('settings')
        .doc('procurement_config')
        .set(config.toMap(), SetOptions(merge: true));
  }

  Stream<List<MaterialRequestModel>> watchMaterialRequests({
    required String schoolDocId,
    String? fixedSchoolTypeId,
    String? requesterUid,
  }) {
    if (schoolDocId.isEmpty) return Stream.value(const []);
    final reqUid = (requesterUid ?? '').trim();
    Query<Map<String, dynamic>> query = _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('materialRequests');
    if (reqUid.isNotEmpty) {
      query = query.where('requesterUid', isEqualTo: reqUid);
    }
    return query.snapshots().map((snap) {
      final stId = (fixedSchoolTypeId ?? '').trim();
      final list = snap.docs
          .map((d) => MaterialRequestModel.fromDoc(d))
          .where((r) {
            if (reqUid.isNotEmpty && r.requesterUid != reqUid) return false;
            if (stId.isNotEmpty &&
                r.schoolTypeId.isNotEmpty &&
                r.schoolTypeId != stId) {
              return false;
            }
            return true;
          })
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// 1) Öğretmen / Personel Yeni Malzeme Talebi Oluşturur
  Future<String> createMaterialRequest({
    required String institutionId,
    required String schoolDocId,
    required String schoolTypeId,
    required String schoolTypeName,
    required String requesterUid,
    required String requesterName,
    required String requesterRole,
    String linkedItemId = '',
    String targetWarehouseId = '',
    String targetWarehouseName = '',
    required String itemName,
    required String category,
    required double quantity,
    required String unit,
    required String urgency,
    String productLink = '',
    List<String> imageUrls = const [],
    String description = '',
  }) async {
    final now = DateTime.now();
    final req = MaterialRequestModel(
      id: '',
      institutionId: institutionId,
      schoolDocId: schoolDocId,
      schoolTypeId: schoolTypeId,
      schoolTypeName: schoolTypeName,
      requesterUid: requesterUid,
      requesterName: requesterName,
      requesterRole: requesterRole,
      linkedItemId: linkedItemId,
      targetWarehouseId: targetWarehouseId,
      targetWarehouseName: targetWarehouseName,
      itemName: itemName.trim(),
      normalizedItemName: InventoryItemModel.normalizeTr(itemName),
      category: category,
      quantity: quantity,
      unit: unit,
      urgency: urgency,
      productLink: productLink.trim(),
      imageUrls: imageUrls,
      description: description.trim(),
      status: 'pending_supervisor',
      timeline: [
        RequestTimelineEntry(
          stage: 'created',
          title: 'Malzeme talebi oluşturuldu',
          actorUid: requesterUid,
          actorName: requesterName,
          note: description.trim(),
          timestamp: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    final docRef = await _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('materialRequests')
        .add(req.toMap());

    // 1. kademe amirlere bildirim gönder
    await _notifyRolesOrUsers(
      institutionId: institutionId,
      schoolDocId: schoolDocId,
      roles: const ['mudur_yardimcisi', 'mudur', 'genel_mudur'],
      title: 'Yeni Malzeme Talebi',
      body:
          '$requesterName tarafından ${InventoryItemModel.formatQty(quantity)} $unit "$itemName" talep edildi.',
    );

    return docRef.id;
  }

  /// 2) 1. Kademe Amir Onayı:
  /// - `route == 'warehouse'`: Stokta mevcut -> Doğrudan Depocuya (`approved_for_warehouse`)
  /// - `route == 'procurement'`: Stokta yok -> 2. Kademe Üst Amir Oluruna (`pending_upper_approver`) veya doğrudan Satın Almaya (`in_procurement`)
  /// - `route == 'split'`: Mevcut stok kadarını Depocuya gönderir, eksik kalan miktar için otomatik bağlı satın alma talebi açar!
  Future<void> approveByFirstSupervisor({
    required MaterialRequestModel request,
    required String route, // 'warehouse' | 'procurement' | 'split'
    required String actorUid,
    required String actorName,
    required bool sendDirectlyToProcurementIfNoUpperNeeded,
    String targetWarehouseId = '',
    String targetWarehouseName = '',
    String linkedItemId = '',
    double availableStockForSplit = 0,
    String note = '',
  }) async {
    final now = DateTime.now();
    final col = _db
        .collection('schools')
        .doc(request.schoolDocId)
        .collection('materialRequests');
    final docRef = col.doc(request.id);

    if (route == 'warehouse') {
      final updatedTimeline = [
        ...request.timeline,
        RequestTimelineEntry(
          stage: 'approved_for_warehouse',
          title: '1. Amir onayladı • Depodan teslimata yönlendirildi',
          actorUid: actorUid,
          actorName: actorName,
          note: note,
          timestamp: now,
        ),
      ];
      await docRef.update({
        'status': 'approved_for_warehouse',
        'supervisorUid': actorUid,
        'supervisorName': actorName,
        'supervisorNote': note,
        if (targetWarehouseId.isNotEmpty)
          'targetWarehouseId': targetWarehouseId,
        if (targetWarehouseName.isNotEmpty)
          'targetWarehouseName': targetWarehouseName,
        if (linkedItemId.isNotEmpty) 'linkedItemId': linkedItemId,
        'timeline': updatedTimeline.map((e) => e.toMap()).toList(),
        'updatedAt': Timestamp.fromDate(now),
      });

      await _notifyRolesOrUsers(
        institutionId: request.institutionId,
        schoolDocId: request.schoolDocId,
        roles: const ['depo', 'destek_hizmetleri'],
        title: 'Teslimat Bekleyen Malzeme',
        body:
            '${request.requesterName} için ${request.formattedQty} ${request.unit} "${request.itemName}" teslim onayı bekliyor.',
      );
      return;
    }

    final nextProcurementStatus = sendDirectlyToProcurementIfNoUpperNeeded
        ? 'in_procurement'
        : 'pending_upper_approver';

    if (route == 'split' &&
        availableStockForSplit > 0 &&
        availableStockForSplit < request.quantity) {
      final missingQty = request.quantity - availableStockForSplit;

      // 1. Mevcut talebi depodaki hazır miktar için güncelle -> Depocuya düşsün
      final whTimeline = [
        ...request.timeline,
        RequestTimelineEntry(
          stage: 'approved_for_warehouse',
          title:
              'Kısmi Stok Onayı: Mevcut ${InventoryItemModel.formatQty(availableStockForSplit)} ${request.unit} depoya yönlendirildi',
          actorUid: actorUid,
          actorName: actorName,
          note: note,
          timestamp: now,
        ),
      ];
      await docRef.update({
        'quantity': availableStockForSplit,
        'status': 'approved_for_warehouse',
        'supervisorUid': actorUid,
        'supervisorName': actorName,
        'supervisorNote': note,
        if (targetWarehouseId.isNotEmpty)
          'targetWarehouseId': targetWarehouseId,
        if (targetWarehouseName.isNotEmpty)
          'targetWarehouseName': targetWarehouseName,
        if (linkedItemId.isNotEmpty) 'linkedItemId': linkedItemId,
        'timeline': whTimeline.map((e) => e.toMap()).toList(),
        'updatedAt': Timestamp.fromDate(now),
      });

      // 2. Eksik miktar için yeni satın alma talebi aç
      final missingReq = MaterialRequestModel(
        id: '',
        institutionId: request.institutionId,
        schoolDocId: request.schoolDocId,
        schoolTypeId: request.schoolTypeId,
        schoolTypeName: request.schoolTypeName,
        requesterUid: request.requesterUid,
        requesterName: request.requesterName,
        requesterRole: request.requesterRole,
        linkedItemId: linkedItemId,
        targetWarehouseId: targetWarehouseId,
        targetWarehouseName: targetWarehouseName,
        itemName: request.itemName,
        normalizedItemName: request.normalizedItemName,
        category: request.category,
        quantity: missingQty,
        unit: request.unit,
        urgency: request.urgency,
        productLink: request.productLink,
        imageUrls: request.imageUrls,
        description: request.description,
        status: nextProcurementStatus,
        supervisorUid: actorUid,
        supervisorName: actorName,
        supervisorNote: note,
        timeline: [
          ...request.timeline,
          RequestTimelineEntry(
            stage: nextProcurementStatus,
            title:
                'Eksik kalan ${InventoryItemModel.formatQty(missingQty)} ${request.unit} için satın alma sürecine sevk edildi',
            actorUid: actorUid,
            actorName: actorName,
            note: note,
            timestamp: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      await col.add(missingReq.toMap());
    } else {
      // Tamamı satın alma akışına
      final procTimeline = [
        ...request.timeline,
        RequestTimelineEntry(
          stage: nextProcurementStatus,
          title: sendDirectlyToProcurementIfNoUpperNeeded
              ? 'Onaylandı ve doğrudan Satın Alma birimine sevk edildi'
              : '1. Amir onayladı • Stokta olmadığı için Üst Yetkili oluruna sevk edildi',
          actorUid: actorUid,
          actorName: actorName,
          note: note,
          timestamp: now,
        ),
      ];
      await docRef.update({
        'status': nextProcurementStatus,
        'supervisorUid': actorUid,
        'supervisorName': actorName,
        'supervisorNote': note,
        if (targetWarehouseId.isNotEmpty)
          'targetWarehouseId': targetWarehouseId,
        if (targetWarehouseName.isNotEmpty)
          'targetWarehouseName': targetWarehouseName,
        'timeline': procTimeline.map((e) => e.toMap()).toList(),
        'updatedAt': Timestamp.fromDate(now),
      });
    }

    if (sendDirectlyToProcurementIfNoUpperNeeded) {
      await _notifyRolesOrUsers(
        institutionId: request.institutionId,
        schoolDocId: request.schoolDocId,
        roles: const ['satin_alma', 'muhasebe'],
        title: 'Satın Alma Teklif Bekleyen Talep',
        body: '"${request.itemName}" talebi için tedarikçi teklifleri bekleniyor.',
      );
    } else {
      await _notifyRolesOrUsers(
        institutionId: request.institutionId,
        schoolDocId: request.schoolDocId,
        roles: const ['genel_mudur', 'mudur'],
        title: 'Satın Alma Oluru Bekleyen Talep',
        body:
            'Depoda bulunmayan "${request.itemName}" için üst makam satın alma oluru bekleniyor.',
      );
    }
  }

  /// 3) 2. Kademe Üst Yetkili: Satın Alma Oluru Verir (`pending_upper_approver` -> `in_procurement`)
  Future<void> approveForProcurementByUpperApprover({
    required MaterialRequestModel request,
    required String actorUid,
    required String actorName,
    String note = '',
  }) async {
    final now = DateTime.now();
    final updatedTimeline = [
      ...request.timeline,
      RequestTimelineEntry(
        stage: 'in_procurement',
        title: 'Üst Yetkili satın alma oluru verdi • Satın Alma birimine iletildi',
        actorUid: actorUid,
        actorName: actorName,
        note: note,
        timestamp: now,
      ),
    ];

    await _db
        .collection('schools')
        .doc(request.schoolDocId)
        .collection('materialRequests')
        .doc(request.id)
        .update({
      'status': 'in_procurement',
      'upperApproverUid': actorUid,
      'upperApproverName': actorName,
      'upperApproverNote': note,
      'timeline': updatedTimeline.map((e) => e.toMap()).toList(),
      'updatedAt': Timestamp.fromDate(now),
    });

    await _notifyRolesOrUsers(
      institutionId: request.institutionId,
      schoolDocId: request.schoolDocId,
      roles: const ['satin_alma', 'muhasebe'],
      title: 'Satın Alma Oluru Verildi',
      body:
          '"${request.itemName}" (${request.formattedQty} ${request.unit}) için teklif toplama süreci başlatıldı.',
    );
  }

  /// Talep Reddetme (1. Amir veya 2. Üst Amir)
  Future<void> rejectMaterialRequest({
    required MaterialRequestModel request,
    required String actorUid,
    required String actorName,
    required String reason,
  }) async {
    final now = DateTime.now();
    final updatedTimeline = [
      ...request.timeline,
      RequestTimelineEntry(
        stage: 'rejected',
        title: 'Talep reddedildi',
        actorUid: actorUid,
        actorName: actorName,
        note: reason,
        timestamp: now,
      ),
    ];

    await _db
        .collection('schools')
        .doc(request.schoolDocId)
        .collection('materialRequests')
        .doc(request.id)
        .update({
      'status': 'rejected',
      'rejectionReason': reason,
      'timeline': updatedTimeline.map((e) => e.toMap()).toList(),
      'updatedAt': Timestamp.fromDate(now),
    });

    await _sendDirectNotification(
      targetUid: request.requesterUid,
      title: 'Malzeme Talebiniz Reddedildi',
      body: '"${request.itemName}" talebiniz onaylanmadı: $reason',
    );
  }

  /// 4) Satın Alma Birimi Teklifleri Kaydeder / Üst Onaya Sunar
  Future<void> saveQuotes({
    required MaterialRequestModel request,
    required List<SupplierQuoteModel> quotes,
    required bool submitForApproval,
    required String actorUid,
    required String actorName,
    String note = '',
  }) async {
    final now = DateTime.now();
    final newStatus = submitForApproval ? 'quotes_submitted' : request.status;
    final updatedTimeline = [
      ...request.timeline,
      if (submitForApproval)
        RequestTimelineEntry(
          stage: 'quotes_submitted',
          title: '${quotes.length} adet tedarikçi teklifi üst onaya sunuldu',
          actorUid: actorUid,
          actorName: actorName,
          note: note,
          timestamp: now,
        ),
    ];

    await _db
        .collection('schools')
        .doc(request.schoolDocId)
        .collection('materialRequests')
        .doc(request.id)
        .update({
      'quotes': quotes.map((q) => q.toMap()).toList(),
      'status': newStatus,
      'timeline': updatedTimeline.map((e) => e.toMap()).toList(),
      'updatedAt': Timestamp.fromDate(now),
    });

    if (submitForApproval) {
      await _notifyRolesOrUsers(
        institutionId: request.institutionId,
        schoolDocId: request.schoolDocId,
        roles: const ['genel_mudur', 'mudur'],
        title: 'Satın Alma Teklifleri Onay Bekliyor',
        body:
            '"${request.itemName}" için ${quotes.length} tedarikçi teklifi girildi, seçiminiz bekleniyor.',
      );
    }
  }

  /// 5) Üst Amir Tekliflerden Birini Seçip Alım Onayı Verir
  Future<void> approveSupplierQuote({
    required MaterialRequestModel request,
    required SupplierQuoteModel selectedQuote,
    required String actorUid,
    required String actorName,
    String note = '',
  }) async {
    final now = DateTime.now();
    final updatedTimeline = [
      ...request.timeline,
      RequestTimelineEntry(
        stage: 'purchase_approved',
        title:
            'Teklif onaylandı: ${selectedQuote.supplierName} (${selectedQuote.totalPrice.toStringAsFixed(2)} ₺)',
        actorUid: actorUid,
        actorName: actorName,
        note: note,
        timestamp: now,
      ),
    ];

    await _db
        .collection('schools')
        .doc(request.schoolDocId)
        .collection('materialRequests')
        .doc(request.id)
        .update({
      'status': 'purchase_approved',
      'approvedQuoteId': selectedQuote.id,
      'upperApproverUid': actorUid,
      'upperApproverName': actorName,
      if (note.isNotEmpty) 'upperApproverNote': note,
      'timeline': updatedTimeline.map((e) => e.toMap()).toList(),
      'updatedAt': Timestamp.fromDate(now),
    });

    await _notifyRolesOrUsers(
      institutionId: request.institutionId,
      schoolDocId: request.schoolDocId,
      roles: const ['satin_alma', 'muhasebe'],
      title: 'Teklif Onaylandı • Sipariş Geçilebilir',
      body:
          '"${request.itemName}" için ${selectedQuote.supplierName} teklifi onaylandı.',
    );
  }

  /// 6) Satın Alma Siparişi Geçer ve Depocunun Mal Kabul Onayına Yönlendirir
  Future<void> markPurchaseOrdered({
    required MaterialRequestModel request,
    required WarehouseModel targetWarehouse,
    required String selectedKasaId,
    required String selectedKasaName,
    required bool autoRecordExpense,
    required String actorUid,
    required String actorName,
    String orderNote = '',
  }) async {
    final now = DateTime.now();
    final updatedTimeline = [
      ...request.timeline,
      RequestTimelineEntry(
        stage: 'purchase_ordered',
        title:
            'Sipariş geçildi • "${targetWarehouse.name}" için Depocu mal kabul onayı bekleniyor',
        actorUid: actorUid,
        actorName: actorName,
        note: orderNote,
        timestamp: now,
      ),
    ];

    await _db
        .collection('schools')
        .doc(request.schoolDocId)
        .collection('materialRequests')
        .doc(request.id)
        .update({
      'status': 'purchase_ordered',
      'targetWarehouseId': targetWarehouse.id,
      'targetWarehouseName': targetWarehouse.name,
      'selectedKasaId': selectedKasaId,
      'selectedKasaName': selectedKasaName,
      'autoRecordExpense': autoRecordExpense,
      'orderNote': orderNote,
      'timeline': updatedTimeline.map((e) => e.toMap()).toList(),
      'updatedAt': Timestamp.fromDate(now),
    });

    await _notifyRolesOrUsers(
      institutionId: request.institutionId,
      schoolDocId: request.schoolDocId,
      roles: const ['depo', 'destek_hizmetleri'],
      title: 'Gelecek Sipariş • Mal Kabul Bekleniyor',
      body:
          '"${request.itemName}" (${request.formattedQty} ${request.unit}) siparişi verildi. Depoya ulaştığında mal kabul onayı veriniz.',
    );
  }

  /// 7) DEPOCU MAL KABUL ONAYI (`purchase_ordered` -> `approved_for_warehouse`)
  /// - Ürünü depoya otomatik stok girişi yapar (`purchase_receipt`)
  /// - Mali İşler (`transactions` & `cashes`) gider kaydını otomatik oluşturur
  /// - Talebi öğretmene teslim edilmeye hazır (`approved_for_warehouse`) hale getirir
  Future<void> confirmWarehouseReceiptByKeeper({
    required MaterialRequestModel request,
    required WarehouseModel warehouse,
    required String actorUid,
    required String actorName,
    String receiptNote = '',
  }) async {
    final itemsCol = _db
        .collection('schools')
        .doc(request.schoolDocId)
        .collection('inventoryItems');
    final txCol = _db
        .collection('schools')
        .doc(request.schoolDocId)
        .collection('stockTransactions');
    final reqRef = _db
        .collection('schools')
        .doc(request.schoolDocId)
        .collection('materialRequests')
        .doc(request.id);

    // Depoda eşleşen stok kartını bul veya yeni oluştur
    DocumentReference<Map<String, dynamic>>? existingItemRef;
    if (request.linkedItemId.isNotEmpty) {
      final snap = await itemsCol.doc(request.linkedItemId).get();
      if (snap.exists && snap.data()?['warehouseId'] == warehouse.id) {
        existingItemRef = snap.reference;
      }
    }
    if (existingItemRef == null) {
      final matchQuery = await itemsCol
          .where('warehouseId', isEqualTo: warehouse.id)
          .where('normalizedName', isEqualTo: request.normalizedItemName)
          .limit(1)
          .get();
      if (matchQuery.docs.isNotEmpty) {
        existingItemRef = matchQuery.docs.first.reference;
      }
    }

    final itemRef = existingItemRef ?? itemsCol.doc();
    final isExistingItem = existingItemRef != null;
    final quote = request.approvedQuote;

    // Mali İşler (Kasa) çözümleme (eğer otomatik gider açıksa ve henüz işlenmediyse)
    String accountingTxId = request.accountingTransactionId;
    if (request.autoRecordExpense &&
        accountingTxId.isEmpty &&
        quote != null &&
        quote.totalPrice > 0) {
      accountingTxId = await _recordExpenseInAccounting(
        institutionId: request.institutionId,
        preferredKasaId: request.selectedKasaId,
        category: _mapToAccountingCategory(request.category),
        description:
            'Satın Alma: ${request.itemName} (${request.formattedQty} ${request.unit}) - ${quote.supplierName} • Talep: ${request.requesterName}',
        amount: quote.totalPrice,
        actorUid: actorUid,
        requestId: request.id,
      );
    }

    await _db.runTransaction((tx) async {
      final freshReq = await tx.get(reqRef);
      if (!freshReq.exists) throw 'Talep kaydı bulunamadı.';
      if (freshReq.data()?['warehouseReceivedAt'] != null) {
        throw 'Bu sipariş için mal kabul onayı zaten verilmiş.';
      }

      double prevQty = 0;
      if (isExistingItem) {
        final freshItem = await tx.get(itemRef);
        prevQty = (freshItem.data()?['quantity'] as num?)?.toDouble() ?? 0;
      }

      final now = DateTime.now();
      final nextQty = prevQty + request.quantity;

      if (isExistingItem) {
        tx.update(itemRef, {
          'quantity': nextQty,
          if (quote != null && quote.unitPrice > 0)
            'lastUnitPrice': quote.unitPrice,
          'updatedAt': Timestamp.fromDate(now),
        });
      } else {
        final newItem = InventoryItemModel(
          id: itemRef.id,
          institutionId: request.institutionId,
          schoolDocId: request.schoolDocId,
          warehouseId: warehouse.id,
          warehouseName: warehouse.name,
          schoolTypeId: warehouse.schoolTypeId,
          name: request.itemName,
          normalizedName: request.normalizedItemName,
          category: request.category,
          unit: request.unit,
          quantity: nextQty,
          minStockLevel: 0,
          productLink: quote?.productLink.isNotEmpty == true
              ? quote!.productLink
              : request.productLink,
          imageUrl:
              request.imageUrls.isNotEmpty ? request.imageUrls.first : '',
          lastUnitPrice: quote?.unitPrice ?? 0,
          updatedAt: now,
        );
        tx.set(itemRef, newItem.toMap());
      }

      final stockTxDoc = txCol.doc();
      tx.set(
        stockTxDoc,
        StockTransactionModel(
          id: stockTxDoc.id,
          institutionId: request.institutionId,
          warehouseId: warehouse.id,
          warehouseName: warehouse.name,
          schoolTypeId: warehouse.schoolTypeId,
          itemId: itemRef.id,
          itemName: request.itemName,
          unit: request.unit,
          type: 'purchase_receipt',
          quantity: request.quantity,
          previousQty: prevQty,
          newQty: nextQty,
          relatedRequestId: request.id,
          actorUid: actorUid,
          actorName: actorName,
          recipientName: warehouse.name,
          note: receiptNote.isNotEmpty
              ? receiptNote
              : 'Satın almadan depoya mal kabul girişi (${quote?.supplierName ?? 'Tedarik'})',
          createdAt: now,
        ).toMap(),
      );

      final updatedTimeline = [
        ...request.timeline,
        RequestTimelineEntry(
          stage: 'warehouse_received',
          title:
              'Depocu mal kabul onayı verdi • "${warehouse.name}" stoğuna +${request.formattedQty} ${request.unit} işlendi',
          actorUid: actorUid,
          actorName: actorName,
          note: receiptNote,
          timestamp: now,
        ),
      ];

      tx.update(reqRef, {
        'status': 'approved_for_warehouse',
        'linkedItemId': itemRef.id,
        'targetWarehouseId': warehouse.id,
        'targetWarehouseName': warehouse.name,
        'warehouseReceivedAt': Timestamp.fromDate(now),
        'warehouseReceivedByName': actorName,
        if (accountingTxId.isNotEmpty)
          'accountingTransactionId': accountingTxId,
        'timeline': updatedTimeline.map((e) => e.toMap()).toList(),
        'updatedAt': Timestamp.fromDate(now),
      });
    });

    await _sendDirectNotification(
      targetUid: request.requesterUid,
      title: 'Malzemeniz Depoya Ulaştı',
      body:
          'Talep ettiğiniz "${request.itemName}" (${request.formattedQty} ${request.unit}) depoya giriş yaptı, teslim alabilirsiniz.',
    );
  }

  /// 8) DEPOCU ÖĞRETMENE / PERSONELE TESLİM EDER (`approved_for_warehouse` -> `delivered`)
  /// - Depo stoğundan otomatik düşer
  /// - Talebi kapatır
  Future<void> deliverRequestToRequester({
    required MaterialRequestModel request,
    required InventoryItemModel stockItem,
    required String actorUid,
    required String actorName,
    String deliveryNote = '',
  }) async {
    final itemRef = _db
        .collection('schools')
        .doc(request.schoolDocId)
        .collection('inventoryItems')
        .doc(stockItem.id);
    final txCol = _db
        .collection('schools')
        .doc(request.schoolDocId)
        .collection('stockTransactions');
    final reqRef = _db
        .collection('schools')
        .doc(request.schoolDocId)
        .collection('materialRequests')
        .doc(request.id);

    await _db.runTransaction((tx) async {
      final freshReq = await tx.get(reqRef);
      if (freshReq.data()?['status'] == 'delivered') {
        throw 'Bu talep zaten teslim edilmiş.';
      }

      final freshItem = await tx.get(itemRef);
      if (!freshItem.exists) throw 'Depo stok kartı bulunamadı.';
      final currentQty =
          (freshItem.data()?['quantity'] as num?)?.toDouble() ?? 0;

      if (currentQty < request.quantity) {
        throw 'Depoda yeterli stok görünmüyor! Mevcut: ${InventoryItemModel.formatQty(currentQty)} ${stockItem.unit}, İstenen: ${request.formattedQty} ${request.unit}';
      }

      final now = DateTime.now();
      final nextQty = currentQty - request.quantity;

      tx.update(itemRef, {
        'quantity': nextQty,
        'updatedAt': Timestamp.fromDate(now),
      });

      final stockTxDoc = txCol.doc();
      tx.set(
        stockTxDoc,
        StockTransactionModel(
          id: stockTxDoc.id,
          institutionId: request.institutionId,
          warehouseId: stockItem.warehouseId,
          warehouseName: stockItem.warehouseName,
          schoolTypeId: stockItem.schoolTypeId,
          itemId: stockItem.id,
          itemName: stockItem.name,
          unit: stockItem.unit,
          type: 'request_delivery',
          quantity: request.quantity,
          previousQty: currentQty,
          newQty: nextQty,
          relatedRequestId: request.id,
          actorUid: actorUid,
          actorName: actorName,
          recipientName: request.requesterName,
          note: deliveryNote.isNotEmpty
              ? deliveryNote
              : '${request.requesterName} adlı personele talep teslimatı',
          createdAt: now,
        ).toMap(),
      );

      final updatedTimeline = [
        ...request.timeline,
        RequestTimelineEntry(
          stage: 'delivered',
          title:
              '${request.requesterName} adına teslim edildi • Depo stoğundan -${request.formattedQty} ${request.unit} düşüldü',
          actorUid: actorUid,
          actorName: actorName,
          note: deliveryNote,
          timestamp: now,
        ),
      ];

      tx.update(reqRef, {
        'status': 'delivered',
        'linkedItemId': stockItem.id,
        'targetWarehouseId': stockItem.warehouseId,
        'targetWarehouseName': stockItem.warehouseName,
        'deliveredAt': Timestamp.fromDate(now),
        'deliveredByName': actorName,
        'deliveryNote': deliveryNote,
        'timeline': updatedTimeline.map((e) => e.toMap()).toList(),
        'updatedAt': Timestamp.fromDate(now),
      });
    });

    await _sendDirectNotification(
      targetUid: request.requesterUid,
      title: 'Malzeme Teslim Edildi',
      body:
          '"${request.itemName}" (${request.formattedQty} ${request.unit}) depo tarafından teslim edildi olarak işlendi.',
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MALİ İŞLER (KASA & GİDERLER) ENTEGRASYONU
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> fetchInstitutionCashes(
      String institutionId) async {
    if (institutionId.trim().isEmpty) return const [];
    try {
      final variants = _instVariants(institutionId);
      final snap = await _db
          .collection('cashes')
          .where('institutionId', whereIn: variants)
          .get();
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (_) {
      return const [];
    }
  }

  String _mapToAccountingCategory(String itemCategory) {
    final c = itemCategory.toLowerCase();
    if (c.contains('yemek') || c.contains('mutfak') || c.contains('gıda')) {
      return 'Yemek & Mutfak';
    }
    if (c.contains('bakım') || c.contains('onarım')) {
      return 'Bakım & Onarım';
    }
    return 'Kırtasiye & Malzeme';
  }

  Future<String> _recordExpenseInAccounting({
    required String institutionId,
    required String preferredKasaId,
    required String category,
    required String description,
    required double amount,
    required String actorUid,
    required String requestId,
  }) async {
    try {
      String kasaId = preferredKasaId.trim();
      String kasaName = 'Ana Kasa (Nakit)';

      if (kasaId.isNotEmpty) {
        final kDoc = await _db.collection('cashes').doc(kasaId).get();
        if (kDoc.exists) {
          kasaName = (kDoc.data()?['name'] ?? kasaName).toString();
        } else {
          kasaId = '';
        }
      }

      if (kasaId.isEmpty) {
        final cashes = await fetchInstitutionCashes(institutionId);
        if (cashes.isNotEmpty) {
          kasaId = cashes.first['id'].toString();
          kasaName = (cashes.first['name'] ?? kasaName).toString();
        } else {
          final created = await _db.collection('cashes').add({
            'institutionId': institutionId,
            'name': 'Ana Kasa (Nakit)',
            'balance': 0.0,
            'type': 'cash',
            'createdAt': FieldValue.serverTimestamp(),
          });
          kasaId = created.id;
        }
      }

      final txDoc = await _db.collection('transactions').add({
        'institutionId': institutionId,
        'type': 'expense',
        'category': category,
        'description': description,
        'amount': amount,
        'kasaId': kasaId,
        'kasaName': kasaName,
        'date': FieldValue.serverTimestamp(),
        'userId': actorUid,
        'source': 'procurement',
        'procurementRequestId': requestId,
      });

      final kasaRef = _db.collection('cashes').doc(kasaId);
      await _db.runTransaction((tx) async {
        final snap = await tx.get(kasaRef);
        if (snap.exists) {
          final oldBal = (snap.data()?['balance'] as num?)?.toDouble() ?? 0.0;
          tx.update(kasaRef, {'balance': oldBal - amount});
        }
      });

      return txDoc.id;
    } catch (_) {
      return '';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PERSONEL LİSTESİ & BİLDİRİM YARDIMCILARI
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<({String uid, String name, String role})>> fetchInstitutionStaff(
      String institutionId) async {
    if (institutionId.trim().isEmpty) return const [];
    try {
      final variants = _instVariants(institutionId);
      final snap = await _db
          .collection('users')
          .where('institutionId', whereIn: variants)
          .get();
      final result = <({String uid, String name, String role})>[];
      for (final d in snap.docs) {
        final raw = CryptoService.decryptMap(d.data());
        if (raw['isActive'] == false) continue;
        final role = (raw['role'] ?? '').toString().toLowerCase();
        if (role == 'ogrenci' ||
            role == 'student' ||
            role == 'veli' ||
            role == 'parent') {
          continue;
        }
        final uid = (raw['authUserId'] ?? d.id).toString().trim();
        final name =
            (raw['fullName'] ?? raw['name'] ?? raw['username'] ?? '').toString().trim();
        if (uid.isEmpty || name.isEmpty) continue;
        result.add((uid: uid, name: name, role: role));
      }
      result.sort((a, b) => a.name.compareTo(b.name));
      return result;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _sendDirectNotification({
    required String targetUid,
    required String title,
    required String body,
  }) async {
    if (targetUid.trim().isEmpty) return;
    try {
      await _db
          .collection('notifications')
          .doc(targetUid)
          .collection('items')
          .add({
        'title': title,
        'body': body,
        'type': 'procurement',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> _notifyRolesOrUsers({
    required String institutionId,
    required String schoolDocId,
    required List<String> roles,
    required String title,
    required String body,
  }) async {
    try {
      final variants = _instVariants(institutionId);
      final snap = await _db
          .collection('users')
          .where('institutionId', whereIn: variants)
          .get();
      final targetUids = <String>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        if (d['isActive'] == false) continue;
        final r = (d['role'] ?? d['title'] ?? '').toString().toLowerCase();
        if (roles.contains(r)) {
          final uid = (d['authUserId'] ?? doc.id).toString().trim();
          if (uid.isNotEmpty) targetUids.add(uid);
        }
      }
      for (final uid in targetUids) {
        await _sendDirectNotification(targetUid: uid, title: title, body: body);
      }
    } catch (_) {}
  }
}

