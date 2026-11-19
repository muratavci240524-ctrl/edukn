import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';

import '../models/store/store_models.dart';
import 'term_service.dart';
import 'user_permission_service.dart';

/// Mağaza Modülü Servisi:
/// - Genel Merkez (`SUPER_ADMIN`) mağaza yetkilendirme, ürün ve sipariş yönetimi
/// - Okulların bağımsız mağaza (`{INSTITUTION_ID}`) ürün, ayar ve sipariş yönetimi
/// - Alıcı bağlamı çözümleme, görünürlük filtreleme ve çift-satıcılı (split-order) online ödeme
class StoreService {
  StoreService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  static const String hqDocId = 'SUPER_ADMIN';
  static const String settingsCollection = 'store_settings';
  static const String productsCollection = 'store_products';
  static const String ordersCollection = 'store_orders';

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. OKUL & OKUL TÜRÜ REHBERİ VE KULLANICI BAĞLAMI ÇÖZÜMLEME
  // ═══════════════════════════════════════════════════════════════════════════

  /// Süper Admin ekranında tüm okulları ve alt okul türlerini (`schoolTypes`) yükler.
  Future<List<StoreSchoolDirectoryItem>> loadAllSchoolsWithTypes() async {
    final schoolsSnap = await _db.collection('schools').get();
    final typesSnap = await _db.collection('schoolTypes').get();

    final typesByInst = <String, List<StoreSchoolTypeOption>>{};
    for (final doc in typesSnap.docs) {
      final data = doc.data();
      if (data['isActive'] == false) continue;
      final option = StoreSchoolTypeOption.fromFirestore(doc);
      if (option.institutionId.isEmpty) continue;
      typesByInst.putIfAbsent(option.institutionId, () => []).add(option);
    }

    final result = <StoreSchoolDirectoryItem>[];
    for (final doc in schoolsSnap.docs) {
      final data = doc.data();
      final instId = (data['institutionId'] ?? data['institution_id'] ?? doc.id)
          .toString()
          .trim()
          .toUpperCase();
      final schoolName = (data['schoolName'] ?? data['name'] ?? instId)
          .toString()
          .trim();
      final city = (data['city'] ?? data['province'] ?? '').toString().trim();
      final isActive = data['isActive'] as bool? ?? true;

      final types = List<StoreSchoolTypeOption>.from(
        typesByInst[instId] ?? const <StoreSchoolTypeOption>[],
      )..sort((a, b) => a.name.compareTo(b.name));

      result.add(
        StoreSchoolDirectoryItem(
          schoolId: doc.id,
          institutionId: instId,
          schoolName: schoolName,
          city: city,
          isActive: isActive,
          schoolTypes: types,
        ),
      );
    }

    result.sort((a, b) => a.schoolName.compareTo(b.schoolName));
    return result;
  }

  /// Belirli bir kuruma ait aktif `schoolTypes` listesini döner.
  Future<List<StoreSchoolTypeOption>> loadSchoolTypesForInstitution(
    String institutionId,
  ) async {
    final upper = institutionId.trim().toUpperCase();
    if (upper.isEmpty) return const [];

    QuerySnapshot<Map<String, dynamic>> snap = await _db
        .collection('schoolTypes')
        .where('institutionId', isEqualTo: upper)
        .get();

    if (snap.docs.isEmpty && institutionId.trim() != upper) {
      snap = await _db
          .collection('schoolTypes')
          .where('institutionId', isEqualTo: institutionId.trim())
          .get();
    }

    final options = <StoreSchoolTypeOption>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['isActive'] == false) continue;
      options.add(StoreSchoolTypeOption.fromFirestore(doc));
    }
    options.sort((a, b) => a.name.compareTo(b.name));
    return options;
  }

  /// Belirli bir kuruma ait aktif sınıf/şube (`classes`) listesini yükler.
  Future<List<StoreClassOption>> loadClassesForInstitution(
    String institutionId,
  ) async {
    final upper = institutionId.trim().toUpperCase();
    if (upper.isEmpty) return const [];

    // Önce veritabanındaki mükerrer/boş şubeleri temizle
    await TermService().deduplicateAndCleanClasses(institutionId: upper);

    final selectedTermId = await TermService().getSelectedTermId();
    final activeTermId = await TermService().getActiveTermId();
    final effectiveTermId = selectedTermId ?? activeTermId;

    QuerySnapshot<Map<String, dynamic>> snap = await _db
        .collection('classes')
        .where('institutionId', isEqualTo: upper)
        .get();

    if (snap.docs.isEmpty && institutionId.trim() != upper) {
      snap = await _db
          .collection('classes')
          .where('institutionId', isEqualTo: institutionId.trim())
          .get();
    }
    if (snap.docs.isEmpty && upper.toLowerCase() != upper) {
      snap = await _db
          .collection('classes')
          .where('institutionId', isEqualTo: upper.toLowerCase())
          .get();
    }

    final activeDocs = snap.docs
        .where((doc) => doc.data()['isActive'] != false)
        .toList();

    // Aktif dönemdeki şubeleri tercih et (eski dönem şubelerinin mükerrer görünmesini önle)
    var candidateDocs = activeDocs;
    if (effectiveTermId != null && effectiveTermId.isNotEmpty) {
      final inActiveTerm = activeDocs
          .where(
            (doc) =>
                (doc.data()['termId'] ?? '').toString().trim() ==
                effectiveTermId,
          )
          .toList();
      if (inActiveTerm.isNotEmpty) {
        candidateDocs = inActiveTerm;
      }
    }

    final seenKeys = <String>{};
    final options = <StoreClassOption>[];
    for (final doc in candidateDocs) {
      final opt = StoreClassOption.fromFirestore(doc);
      final normName = StoreClassLevels.normalizeClassToken(opt.name);
      if (normName.isEmpty) continue;
      final dedupKey = '${opt.schoolTypeId}__$normName';
      if (seenKeys.add(dedupKey)) {
        options.add(opt);
      }
    }

    int levelOrder(String lvl) {
      final idx = StoreClassLevels.all.indexOf(lvl);
      return idx >= 0 ? idx : 99;
    }

    options.sort((a, b) {
      final cmpLvl = levelOrder(
        a.classLevel,
      ).compareTo(levelOrder(b.classLevel));
      if (cmpLvl != 0) return cmpLvl;
      return a.name.compareTo(b.name);
    });
    return options;
  }

  /// Tüm kurumlardaki aktif sınıf/şube (`classes`) listesini yükler (Genel Merkez hedefleme için).
  Future<List<StoreClassOption>> loadAllActiveClasses() async {
    final snap = await _db.collection('classes').get();
    final seenKeys = <String>{};
    final options = <StoreClassOption>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['isActive'] == false) continue;
      final opt = StoreClassOption.fromFirestore(doc);
      final normName = StoreClassLevels.normalizeClassToken(opt.name);
      if (normName.isEmpty) continue;
      final dedupKey = '${opt.institutionId}__${opt.schoolTypeId}__$normName';
      if (seenKeys.add(dedupKey)) {
        options.add(opt);
      }
    }

    int levelOrder(String lvl) {
      final idx = StoreClassLevels.all.indexOf(lvl);
      return idx >= 0 ? idx : 99;
    }

    options.sort((a, b) {
      final cmpLvl = levelOrder(
        a.classLevel,
      ).compareTo(levelOrder(b.classLevel));
      if (cmpLvl != 0) return cmpLvl;
      final cmpName = a.name.compareTo(b.name);
      if (cmpName != 0) return cmpName;
      return a.institutionId.compareTo(b.institutionId);
    });
    return options;
  }

  /// Alıcının kurum, okul, okul türü ve öğrenci bağlamını eksiksiz çözümler.
  Future<BuyerStoreContext> resolveBuyerContext({
    required String institutionId,
    required String buyerRole,
    String? schoolId,
    String? schoolName,
    String? schoolTypeId,
    String? schoolTypeName,
    String? studentId,
    String? studentName,
  }) async {
    final user = _auth.currentUser;
    final uid = user?.uid ?? '';
    final normalizedRole = StoreBuyerRoles.normalize(buyerRole);
    final explicitSingleStudent =
        studentId != null && studentId.trim().isNotEmpty;
    String resolvedInst = institutionId.trim().toUpperCase();

    String fullName = user?.displayName?.trim() ?? '';
    String email = user?.email?.trim() ?? '';
    String phone = '';
    String resolvedSchoolId = schoolId?.trim() ?? '';
    String resolvedSchoolName = schoolName?.trim() ?? '';
    String? resolvedStudentId = studentId?.trim();
    String? resolvedStudentName = studentName?.trim();
    String? resolvedStudentClass;

    final candidateTypeIds = <String>{
      if (schoolTypeId != null && schoolTypeId.trim().isNotEmpty)
        schoolTypeId.trim(),
    };
    final candidateTypeNames = <String>{
      if (schoolTypeName != null && schoolTypeName.trim().isNotEmpty)
        schoolTypeName.trim(),
    };
    final candidateCategories = <String>{};
    final assignedSchoolTypeTokens = <String>{};
    final userIdentityTokens = <String>{};
    final extraLinkedStudentIds = <String>{};
    final candidateClassIds = <String>{};
    final candidateClassNames = <String>{};
    final candidateClassLevels = <String>{};
    final candidateBranches = <String>{};

    String extractUserFullName(Map<String, dynamic> u) {
      final explicitFull = (u['fullName'] ?? '').toString().trim();
      if (explicitFull.isNotEmpty) return explicitFull;
      final combined =
          [u['name'] ?? u['firstName'], u['surname'] ?? u['lastName']]
              .map((e) => (e ?? '').toString().trim())
              .where((s) => s.isNotEmpty)
              .join(' ');
      if (combined.isNotEmpty) return combined;
      return (u['displayName'] ?? '').toString().trim();
    }

    void collectSchoolTypeValue(dynamic raw, {bool isExplicitId = false}) {
      if (raw == null) return;
      if (raw is Map) {
        final idVal = (raw['schoolTypeId'] ?? raw['typeId'] ?? raw['id'] ?? '')
            .toString()
            .trim();
        final nameVal =
            (raw['schoolTypeName'] ??
                    raw['schoolType'] ??
                    raw['typeName'] ??
                    raw['name'] ??
                    raw['locationName'] ??
                    '')
                .toString()
                .trim();
        if (idVal.isNotEmpty) candidateTypeIds.add(idVal);
        if (nameVal.isNotEmpty) {
          candidateTypeNames.add(nameVal);
          assignedSchoolTypeTokens.add(nameVal);
        }
        return;
      }
      if (raw is Iterable) {
        for (final item in raw) {
          collectSchoolTypeValue(item, isExplicitId: isExplicitId);
        }
        return;
      }
      final s = raw.toString().trim();
      if (s.isEmpty) return;
      if (isExplicitId) {
        candidateTypeIds.add(s);
      }
      assignedSchoolTypeTokens.add(s);
    }

    void absorbUserMap(
      Map<String, dynamic> u, {
      bool overwritePrimary = false,
    }) {
      final uName = extractUserFullName(u);
      if (uName.isNotEmpty && (overwritePrimary || fullName.isEmpty)) {
        fullName = uName;
      }
      final uEmail =
          (u['email'] ?? u['corporateEmail'] ?? u['personalEmail'] ?? '')
              .toString()
              .trim();
      if (uEmail.isNotEmpty && (overwritePrimary || email.isEmpty)) {
        email = uEmail;
      }
      final uPhone =
          (u['phone'] ??
                  u['phoneNumber'] ??
                  u['mobilePhone'] ??
                  u['cepTelefonu'] ??
                  '')
              .toString()
              .trim();
      if (uPhone.isNotEmpty && (overwritePrimary || phone.isEmpty)) {
        phone = uPhone;
      }

      if (resolvedInst.isEmpty) {
        resolvedInst = (u['institutionId'] ?? u['institution_id'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
      }
      if (resolvedSchoolId.isEmpty) {
        resolvedSchoolId = (u['schoolId'] ?? '').toString().trim();
      }
      if (resolvedSchoolName.isEmpty) {
        resolvedSchoolName = (u['schoolName'] ?? '').toString().trim();
      }

      collectSchoolTypeValue(u['schoolTypeIds'], isExplicitId: true);
      collectSchoolTypeValue(u['schoolTypeId'], isExplicitId: true);
      collectSchoolTypeValue(u['schoolTypes']);
      collectSchoolTypeValue(u['workLocations']);
      collectSchoolTypeValue(u['schoolTypeName']);
      collectSchoolTypeValue(u['schoolType']);

      if ((resolvedStudentId == null || resolvedStudentId!.isEmpty) &&
          u['studentId'] != null) {
        final sid = u['studentId'].toString().trim();
        if (sid.isNotEmpty) resolvedStudentId = sid;
      }
      if (u['studentIds'] is Iterable) {
        for (final item in (u['studentIds'] as Iterable)) {
          final sid = (item ?? '').toString().trim();
          if (sid.isNotEmpty) {
            if (!explicitSingleStudent) extraLinkedStudentIds.add(sid);
            if (resolvedStudentId == null || resolvedStudentId!.isEmpty) {
              resolvedStudentId = sid;
            }
          }
        }
      }

      for (final key in [
        'username',
        'tcNo',
        'tc',
        'studentTc',
        'nationalId',
        'studentNo',
      ]) {
        final v = (u[key] ?? '').toString().trim();
        if (v.isNotEmpty) userIdentityTokens.add(v.toLowerCase());
      }
    }

    void absorbStudentRecord(Map<String, dynamic> s, {bool isPrimary = false}) {
      final explicitSName = (s['fullName'] ?? '').toString().trim();
      final combinedSName =
          [s['firstName'] ?? s['name'], s['lastName'] ?? s['surname']]
              .map((e) => (e ?? '').toString().trim())
              .where((v) => v.isNotEmpty)
              .join(' ');
      final sName = explicitSName.isNotEmpty ? explicitSName : combinedSName;

      final cId = (s['classId'] ?? '').toString().trim();
      final cName = (s['className'] ?? s['class'] ?? '').toString().trim();
      final stTypeId = (s['schoolTypeId'] ?? '').toString().trim();
      final stTypeName = (s['schoolTypeName'] ?? s['schoolType'] ?? '')
          .toString()
          .trim();

      if (cId.isNotEmpty) candidateClassIds.add(cId);
      if (cName.isNotEmpty) {
        candidateClassNames.add(StoreClassLevels.normalizeClassToken(cName));
      }
      if (stTypeId.isNotEmpty) candidateTypeIds.add(stTypeId);
      if (stTypeName.isNotEmpty) candidateTypeNames.add(stTypeName);

      final extractedLvl = StoreClassLevels.extractLevel(
        rawLevel: s['classLevel'] ?? s['grade'],
        className: cName,
        schoolTypeName: stTypeName,
      );
      if (extractedLvl != null && extractedLvl.isNotEmpty) {
        candidateClassLevels.add(extractedLvl);
      }

      final extractedBranch = StoreClassLevels.extractBranch(
        explicitBranch: s['branch']?.toString(),
        className: cName,
      );
      if (extractedBranch != null && extractedBranch.isNotEmpty) {
        candidateBranches.add(extractedBranch);
      }

      if (isPrimary) {
        if ((resolvedStudentName == null || resolvedStudentName!.isEmpty) &&
            sName.isNotEmpty) {
          resolvedStudentName = sName;
        }
        final dispClass = cName.isNotEmpty
            ? cName
            : (s['grade'] ?? s['classLevel'] ?? '').toString().trim();
        if (dispClass.isNotEmpty) {
          resolvedStudentClass = dispClass;
        }
        if (phone.isEmpty) {
          phone =
              (s['parentPhone'] ??
                      s['motherPhone'] ??
                      s['fatherPhone'] ??
                      s['phone'] ??
                      '')
                  .toString()
                  .trim();
        }
        if (fullName.isEmpty &&
            normalizedRole == StoreBuyerRoles.ogrenci &&
            sName.isNotEmpty) {
          fullName = sName;
        }
        if (fullName.isEmpty && normalizedRole == StoreBuyerRoles.veli) {
          final pName = (s['parentName'] ?? s['guardianName'] ?? '')
              .toString()
              .trim();
          if (pName.isNotEmpty) fullName = pName;
        }
      }
    }

    // 1) UserPermissionService (kanonik doküman + şifre çözme + impersonation) & /users/{uid} yedek okuma
    Map<String, dynamic>? permData;
    try {
      permData = await UserPermissionService.loadUserData();
    } catch (_) {}

    bool isImpersonated = false;
    if (permData != null && permData.isNotEmpty) {
      final permEmail = (permData['email'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final authEmail = (user?.email ?? '').trim().toLowerCase();
      isImpersonated =
          permEmail.isNotEmpty &&
          authEmail.isNotEmpty &&
          permEmail != authEmail;
      absorbUserMap(permData, overwritePrimary: true);
    }

    if (uid.isNotEmpty && !isImpersonated) {
      try {
        final userDoc = await _db.collection('users').doc(uid).get();
        if (userDoc.exists) {
          final u = userDoc.data() ?? {};
          absorbUserMap(u, overwritePrimary: permData == null);
        }
      } catch (_) {}
    }

    if (email.contains('@')) {
      final prefix = email.split('@').first.trim().toLowerCase();
      if (prefix.isNotEmpty) userIdentityTokens.add(prefix);
    }

    // 2) Öğrenci veya veli ise ve studentId hâlâ boşsa kurumun students kayıtlarından username/tcNo ile eşleştir
    final matchedStudentsById = <String, Map<String, dynamic>>{};
    if ((normalizedRole == StoreBuyerRoles.ogrenci ||
            normalizedRole == StoreBuyerRoles.veli) &&
        (resolvedStudentId == null || resolvedStudentId!.isEmpty) &&
        resolvedInst.isNotEmpty &&
        userIdentityTokens.isNotEmpty) {
      try {
        QuerySnapshot<Map<String, dynamic>> stSnap = await _db
            .collection('students')
            .where('institutionId', isEqualTo: resolvedInst)
            .get();
        if (stSnap.docs.isEmpty && resolvedInst.toLowerCase() != resolvedInst) {
          stSnap = await _db
              .collection('students')
              .where('institutionId', isEqualTo: resolvedInst.toLowerCase())
              .get();
        }
        for (final doc in stSnap.docs) {
          final d = doc.data();
          final docTokens = <String>{
            (d['username'] ?? '').toString().trim().toLowerCase(),
            (d['tcNo'] ?? '').toString().trim().toLowerCase(),
            (d['tc'] ?? '').toString().trim().toLowerCase(),
            (d['studentNo'] ?? '').toString().trim().toLowerCase(),
            if (normalizedRole == StoreBuyerRoles.veli) ...[
              (d['parentTc'] ?? '').toString().trim().toLowerCase(),
              (d['motherTc'] ?? '').toString().trim().toLowerCase(),
              (d['fatherTc'] ?? '').toString().trim().toLowerCase(),
              (d['parentUsername'] ?? '').toString().trim().toLowerCase(),
            ],
          }..remove('');
          if (docTokens.any(userIdentityTokens.contains)) {
            matchedStudentsById[doc.id] = d;
            resolvedStudentId ??= doc.id;
            if (resolvedStudentId!.isEmpty) resolvedStudentId = doc.id;
            if (normalizedRole == StoreBuyerRoles.ogrenci) break;
          }
        }
      } catch (_) {}
    }

    // 3) Öğrenci / Veli bağlamında öğrenci kaydından (ve varsa classes dokümanından) sınıf & okul türü bilgilerini al
    final allTargetStudentIds = <String>{
      if (resolvedStudentId != null && resolvedStudentId!.isNotEmpty)
        resolvedStudentId!,
      if (!explicitSingleStudent && normalizedRole == StoreBuyerRoles.veli) ...[
        ...extraLinkedStudentIds,
        ...matchedStudentsById.keys,
      ],
    };

    for (final sid in allTargetStudentIds) {
      try {
        Map<String, dynamic>? s = matchedStudentsById[sid];
        if (s == null) {
          final stDoc = await _db.collection('students').doc(sid).get();
          if (stDoc.exists) {
            s = stDoc.data() ?? {};
          }
        }
        if (s != null) {
          absorbStudentRecord(s, isPrimary: sid == resolvedStudentId);
        }
      } catch (_) {}
    }

    // Öğrencinin classId'si üzerinden classes dokümanını okuyarak eksik sınıf seviyesi / şube / okul türünü tamamla
    if (candidateClassIds.isNotEmpty) {
      for (final cid in List<String>.from(candidateClassIds)) {
        try {
          final cDoc = await _db.collection('classes').doc(cid).get();
          if (cDoc.exists) {
            final opt = StoreClassOption.fromFirestore(cDoc);
            if (opt.name.isNotEmpty) {
              candidateClassNames.add(
                StoreClassLevels.normalizeClassToken(opt.name),
              );
              resolvedStudentClass ??= opt.name;
            }
            if (opt.classLevel.isNotEmpty) {
              candidateClassLevels.add(opt.classLevel);
            }
            if (opt.branch.isNotEmpty) {
              candidateBranches.add(opt.branch);
            }
            if (opt.schoolTypeId.isNotEmpty) {
              candidateTypeIds.add(opt.schoolTypeId);
            }
            if (opt.schoolTypeName.isNotEmpty) {
              candidateTypeNames.add(opt.schoolTypeName);
            }
          }
        } catch (_) {}
      }
    }

    // 4) Okul bilgisi eksikse schools koleksiyonundan esnek sorguyla tamamla
    if (resolvedInst.isNotEmpty &&
        (resolvedSchoolId.isEmpty || resolvedSchoolName.isEmpty)) {
      try {
        DocumentSnapshot<Map<String, dynamic>>? foundSchoolDoc;

        if (resolvedSchoolId.isNotEmpty) {
          final bySchoolId = await _db
              .collection('schools')
              .doc(resolvedSchoolId)
              .get();
          if (bySchoolId.exists) foundSchoolDoc = bySchoolId;
        }

        if (foundSchoolDoc == null) {
          final byInstDoc = await _db
              .collection('schools')
              .doc(resolvedInst)
              .get();
          if (byInstDoc.exists) foundSchoolDoc = byInstDoc;
        }

        if (foundSchoolDoc == null &&
            resolvedInst.toLowerCase() != resolvedInst) {
          final byInstLowerDoc = await _db
              .collection('schools')
              .doc(resolvedInst.toLowerCase())
              .get();
          if (byInstLowerDoc.exists) foundSchoolDoc = byInstLowerDoc;
        }

        if (foundSchoolDoc == null) {
          final variants = <String>{
            resolvedInst,
            resolvedInst.toLowerCase(),
          }.toList();
          final schoolQuery = await _db
              .collection('schools')
              .where('institutionId', whereIn: variants)
              .limit(1)
              .get();
          if (schoolQuery.docs.isNotEmpty) {
            foundSchoolDoc = schoolQuery.docs.first;
          }
        }

        if (foundSchoolDoc != null && foundSchoolDoc.exists) {
          final data = foundSchoolDoc.data() ?? {};
          if (resolvedSchoolId.isEmpty) resolvedSchoolId = foundSchoolDoc.id;
          if (resolvedSchoolName.isEmpty) {
            resolvedSchoolName =
                (data['schoolName'] ?? data['name'] ?? resolvedInst)
                    .toString()
                    .trim();
          }
        }
      } catch (_) {}
    }

    // 5) Kurumun schoolTypes kayıtlarını yükleyerek isim, ID ve kategorileri eşleştir
    if (resolvedInst.isNotEmpty) {
      try {
        final allInstTypes = await loadSchoolTypesForInstitution(resolvedInst);
        final lowerTokens = assignedSchoolTypeTokens
            .map((e) => e.toLowerCase())
            .toSet();
        final normalizedTokenCats = assignedSchoolTypeTokens
            .map(StoreSchoolTypeCategories.normalize)
            .whereType<String>()
            .map((e) => e.toLowerCase())
            .toSet();

        for (final t in allInstTypes) {
          final matchesAssigned =
              assignedSchoolTypeTokens.contains(t.id) ||
              lowerTokens.contains(t.name.toLowerCase()) ||
              (t.category.isNotEmpty &&
                  normalizedTokenCats.contains(t.category.toLowerCase()));
          if (matchesAssigned) {
            candidateTypeIds.add(t.id);
            candidateTypeNames.add(t.name);
            if (t.category.isNotEmpty) candidateCategories.add(t.category);
          }
        }

        if (candidateTypeIds.isEmpty &&
            candidateTypeNames.isEmpty &&
            normalizedRole == StoreBuyerRoles.idareci) {
          // İdareci için spesifik okul türü verilmediyse kurumun tüm okul türleri kapsamındadır.
          for (final t in allInstTypes) {
            candidateTypeIds.add(t.id);
            candidateTypeNames.add(t.name);
            if (t.category.isNotEmpty) candidateCategories.add(t.category);
          }
        } else {
          for (final t in allInstTypes) {
            if (candidateTypeIds.contains(t.id) ||
                candidateTypeNames.any(
                  (n) => n.toLowerCase() == t.name.toLowerCase(),
                )) {
              candidateTypeIds.add(t.id);
              candidateTypeNames.add(t.name);
              if (t.category.isNotEmpty) candidateCategories.add(t.category);
            }
          }
        }

        if (allInstTypes.isEmpty && assignedSchoolTypeTokens.isNotEmpty) {
          for (final tok in assignedSchoolTypeTokens) {
            final norm = StoreSchoolTypeCategories.normalize(tok);
            if (norm != null && StoreSchoolTypeCategories.all.contains(norm)) {
              candidateTypeNames.add(tok);
              candidateCategories.add(norm);
            } else {
              candidateTypeIds.add(tok);
            }
          }
        }
      } catch (_) {}
    }

    for (final tName in candidateTypeNames) {
      final norm = StoreSchoolTypeCategories.normalize(tName);
      if (norm != null && norm.isNotEmpty) {
        candidateCategories.add(norm);
      }
    }

    if (fullName.isEmpty) {
      fullName = resolvedStudentName?.isNotEmpty == true
          ? resolvedStudentName!
          : '${StoreBuyerRoles.labelOf(normalizedRole)} Kullanıcı';
    }
    if (resolvedSchoolName.isEmpty) {
      resolvedSchoolName = resolvedInst.isNotEmpty
          ? resolvedInst
          : 'Okul Mağazası';
    }

    return BuyerStoreContext(
      uid: uid,
      fullName: fullName,
      email: email,
      phone: phone,
      buyerRole: normalizedRole,
      institutionId: resolvedInst,
      schoolId: resolvedSchoolId.isNotEmpty ? resolvedSchoolId : resolvedInst,
      schoolName: resolvedSchoolName,
      schoolTypeIds: candidateTypeIds.toList(),
      schoolTypeNames: candidateTypeNames.toList(),
      schoolTypeCategories: candidateCategories.toList(),
      studentId: resolvedStudentId,
      studentName: resolvedStudentName,
      studentClass: resolvedStudentClass,
      studentClassIds: candidateClassIds.toList(),
      studentClassNames: candidateClassNames.toList(),
      studentClassLevels: candidateClassLevels.toList(),
      studentBranches: candidateBranches.toList(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. MAĞAZA AYARLARI (GENEL MERKEZ & OKUL)
  // ═══════════════════════════════════════════════════════════════════════════

  Stream<HqStoreSchoolAccess> watchHqSettings() {
    return _db
        .collection(settingsCollection)
        .doc(hqDocId)
        .snapshots()
        .map((snap) => HqStoreSchoolAccess.fromMap(snap.data()));
  }

  Future<HqStoreSchoolAccess> getHqSettings() async {
    final doc = await _db.collection(settingsCollection).doc(hqDocId).get();
    return HqStoreSchoolAccess.fromMap(doc.data());
  }

  Future<void> saveHqSettings(HqStoreSchoolAccess settings) async {
    await _db
        .collection(settingsCollection)
        .doc(hqDocId)
        .set(settings.toMap(), SetOptions(merge: true));
  }

  Stream<SchoolStoreSettings> watchSchoolSettings(String institutionId) {
    final upper = institutionId.trim().toUpperCase();
    if (upper.isEmpty) {
      return Stream.value(SchoolStoreSettings.defaults(''));
    }
    return _db
        .collection(settingsCollection)
        .doc(upper)
        .snapshots()
        .map((snap) => SchoolStoreSettings.fromMap(upper, snap.data()));
  }

  Future<SchoolStoreSettings> getSchoolSettings(String institutionId) async {
    final upper = institutionId.trim().toUpperCase();
    if (upper.isEmpty) return SchoolStoreSettings.defaults('');
    final doc = await _db.collection(settingsCollection).doc(upper).get();
    return SchoolStoreSettings.fromMap(upper, doc.data());
  }

  Future<void> saveSchoolSettings(SchoolStoreSettings settings) async {
    final upper = settings.institutionId.trim().toUpperCase();
    await _db
        .collection(settingsCollection)
        .doc(upper)
        .set(settings.toMap(), SetOptions(merge: true));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. ÜRÜN YÖNETİMİ VE GÖRSEL YÜKLEME
  // ═══════════════════════════════════════════════════════════════════════════

  /// Ürün fotoğrafını `store_products/{sellerInstitutionId}/{timestamp}_{fileName}` yoluna yükler.
  Future<String> uploadProductImage({
    required String sellerInstitutionId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final instFolder = sellerInstitutionId.trim().isEmpty
        ? hqDocId
        : sellerInstitutionId.trim().toUpperCase();
    final lowerName = fileName.trim().toLowerCase();
    final isPng = lowerName.endsWith('.png');
    final ext = isPng ? 'png' : 'jpg';
    final contentType = isPng ? 'image/png' : 'image/jpeg';

    final sanitized = fileName
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final finalName = sanitized.isEmpty
        ? '${DateTime.now().millisecondsSinceEpoch}.$ext'
        : '${DateTime.now().millisecondsSinceEpoch}_$sanitized';

    final ref = _storage
        .ref()
        .child(productsCollection)
        .child(instFolder)
        .child(finalName);

    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }

  /// Genel Merkez ürünlerini canlı izler.
  Stream<List<StoreProduct>> watchHqProducts() {
    return _db
        .collection(productsCollection)
        .where('sellerType', isEqualTo: 'hq')
        .snapshots()
        .map((snap) {
          final list = snap.docs.map(StoreProduct.fromFirestore).toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  /// Belirli bir okulun bağımsız mağaza ürünlerini canlı izler.
  Stream<List<StoreProduct>> watchSchoolProducts(String institutionId) {
    final upper = institutionId.trim().toUpperCase();
    if (upper.isEmpty) {
      return Stream.value(const <StoreProduct>[]);
    }
    return _db
        .collection(productsCollection)
        .where('sellerInstitutionId', isEqualTo: upper)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map(StoreProduct.fromFirestore)
              .where((p) => p.sellerType == 'school')
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  /// Yeni ürün ekler veya mevcut ürünü günceller.
  Future<String> saveProduct(StoreProduct product) async {
    final col = _db.collection(productsCollection);
    if (product.id.trim().isEmpty) {
      final docRef = col.doc();
      await docRef.set(product.toMap(isNew: true));
      return docRef.id;
    } else {
      await col
          .doc(product.id)
          .set(product.toMap(isNew: false), SetOptions(merge: true));
      return product.id;
    }
  }

  Future<void> toggleProductActive(String productId, bool isActive) async {
    await _db.collection(productsCollection).doc(productId).update({
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteProduct(String productId) async {
    await _db.collection(productsCollection).doc(productId).delete();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. ALICI GÖRÜNÜRLÜK FİLTRESİ (HQ + OKUL MAĞAZASI)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Alıcının kurumuna ve Genel Merkez'e (`SUPER_ADMIN`) ait aday ürünleri
  /// `firestore.rules` uyumlu tekil `whereIn` sorgusuyla canlı izler (composite index gerektirmez).
  Stream<List<StoreProduct>> watchRawCandidateProducts(String institutionId) {
    final instUpper = institutionId.trim().toUpperCase();
    final sellerIds = <String>{
      hqDocId,
      if (instUpper.isNotEmpty) instUpper,
    }.toList();
    return _db
        .collection(productsCollection)
        .where('sellerInstitutionId', whereIn: sellerIds)
        .snapshots()
        .map((snap) => snap.docs.map(StoreProduct.fromFirestore).toList());
  }

  /// Tek seferlik görünür ürünleri getirir.
  Future<List<StoreProduct>> getVisibleProductsForBuyer(
    BuyerStoreContext context,
  ) async {
    final instUpper = context.institutionId.trim().toUpperCase();
    final sellerIds = <String>{
      hqDocId,
      if (instUpper.isNotEmpty) instUpper,
    }.toList();
    final hqSettings = await getHqSettings();
    final schoolSettings = await getSchoolSettings(instUpper);
    final productsSnap = await _db
        .collection(productsCollection)
        .where('sellerInstitutionId', whereIn: sellerIds)
        .get();
    final allProducts = productsSnap.docs
        .map(StoreProduct.fromFirestore)
        .toList();

    return filterVisibleProducts(
      allProducts: allProducts,
      context: context,
      hqSettings: hqSettings,
      schoolSettings: schoolSettings,
    );
  }

  /// Alıcı için görünür ürünleri canlı izler (`store_products` değiştikçe güncellenir).
  Stream<List<StoreProduct>> watchVisibleProductsForBuyer({
    required BuyerStoreContext context,
    required HqStoreSchoolAccess hqSettings,
    required SchoolStoreSettings schoolSettings,
  }) {
    return watchRawCandidateProducts(context.institutionId).map((all) {
      return filterVisibleProducts(
        allProducts: all,
        context: context,
        hqSettings: hqSettings,
        schoolSettings: schoolSettings,
      );
    });
  }

  /// Görünürlük kurallarını uygular:
  /// 1) `store_settings/SUPER_ADMIN` üzerinden bu okul ve okul türüne HQ mağazası açık mı?
  /// 2) `store_settings/{INSTITUTION_ID}` üzerinden okul mağazası açık mı?
  /// 3) Ürünün hedef okul, hedef okul türü / kategorisi ve hedef alıcı rolü eşleşiyor mu?
  List<StoreProduct> filterVisibleProducts({
    required List<StoreProduct> allProducts,
    required BuyerStoreContext context,
    required HqStoreSchoolAccess hqSettings,
    required SchoolStoreSettings schoolSettings,
  }) {
    final instUpper = context.institutionId.trim().toUpperCase();
    final normalizedRole = StoreBuyerRoles.normalize(context.buyerRole);

    final isHqOpen = hqSettings.isOpenForBuyer(
      schoolId: context.schoolId,
      institutionId: instUpper,
      buyerSchoolTypeIds: context.schoolTypeIds,
    );

    final isSchoolStoreOpen = schoolSettings.isOpenForBuyerSchoolTypes(
      context.schoolTypeIds,
    );

    final visible = <StoreProduct>[];

    for (final product in allProducts) {
      if (!product.isActive) continue;

      // Rol kontrolü
      if (product.targetRoles.isNotEmpty &&
          !product.targetRoles.contains(normalizedRole)) {
        continue;
      }

      if (product.isHq) {
        if (!isHqOpen) continue;

        // Okul hedeflemesi
        if (!product.targetAllSchools && product.targetSchoolIds.isNotEmpty) {
          final matchesSchool =
              product.targetSchoolIds.contains(context.schoolId) ||
              product.targetSchoolIds.contains(instUpper);
          if (!matchesSchool) continue;
        }

        // Okul türü / kademe hedeflemesi
        if (!_matchesSchoolTypeTarget(product, context)) {
          continue;
        }

        // Sınıf seviyesi ve şube hedeflemesi
        if (!_matchesClassLevelAndBranchTarget(
          product,
          context,
          normalizedRole,
        )) {
          continue;
        }

        visible.add(product);
      } else if (product.isSchool) {
        if (!isSchoolStoreOpen) continue;
        if (product.sellerInstitutionId.toUpperCase() != instUpper) continue;

        if (!_matchesSchoolTypeTarget(product, context)) {
          continue;
        }

        if (!_matchesClassLevelAndBranchTarget(
          product,
          context,
          normalizedRole,
        )) {
          continue;
        }

        visible.add(product);
      }
    }

    visible.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return visible;
  }

  bool _matchesSchoolTypeTarget(
    StoreProduct product,
    BuyerStoreContext context,
  ) {
    if (product.targetAllSchoolTypes) return true;
    if (product.targetSchoolTypeIds.isEmpty &&
        product.targetSchoolTypeCategories.isEmpty) {
      return true;
    }

    // Alıcının hiç okul türü kısıtı yoksa (örn. okulda henüz schoolType tanımlanmamışsa) göster.
    if (context.schoolTypeIds.isEmpty && context.schoolTypeCategories.isEmpty) {
      return true;
    }

    if (product.targetSchoolTypeIds.isNotEmpty &&
        context.schoolTypeIds.any(product.targetSchoolTypeIds.contains)) {
      return true;
    }

    if (product.targetSchoolTypeCategories.isNotEmpty) {
      final normalizedTargets = product.targetSchoolTypeCategories
          .map(StoreSchoolTypeCategories.normalize)
          .whereType<String>()
          .toSet();
      final buyerCats = context.schoolTypeCategories
          .map(StoreSchoolTypeCategories.normalize)
          .whereType<String>()
          .toSet();
      if (buyerCats.any(normalizedTargets.contains)) {
        return true;
      }
    }

    return false;
  }

  bool _matchesClassLevelAndBranchTarget(
    StoreProduct product,
    BuyerStoreContext context,
    String normalizedRole,
  ) {
    // İdareci ve öğretmen rolleri belirli tek bir öğrenci sınıfında kayıtlı olmadığı için
    // hedef rollerde izin verilmişse kademe kapsamındaki ürünleri görebilirler.
    if (normalizedRole != StoreBuyerRoles.ogrenci &&
        normalizedRole != StoreBuyerRoles.veli) {
      return true;
    }

    // 1) Sınıf Seviyesi kontrolü (örn. sadece 5. Sınıflar)
    if (!product.targetAllClassLevels && product.targetClassLevels.isNotEmpty) {
      final targetLevels = product.targetClassLevels
          .map(StoreClassLevels.normalize)
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toSet();

      final buyerLevels = <String>{
        ...context.studentClassLevels
            .map(StoreClassLevels.normalize)
            .whereType<String>(),
      };
      if (buyerLevels.isEmpty &&
          context.studentClass != null &&
          context.studentClass!.trim().isNotEmpty) {
        final fallbackLvl = StoreClassLevels.extractLevel(
          className: context.studentClass,
          schoolTypeCategory: context.schoolTypeCategories.isNotEmpty
              ? context.schoolTypeCategories.first
              : null,
        );
        if (fallbackLvl != null && fallbackLvl.isNotEmpty) {
          buyerLevels.add(fallbackLvl);
        }
      }

      if (targetLevels.isNotEmpty && !buyerLevels.any(targetLevels.contains)) {
        return false;
      }
    }

    // 2) Şube / Sınıf kontrolü (örn. sadece 5-A ve 5-B veya A şubeleri)
    if (!product.targetAllClasses &&
        (product.targetClassIds.isNotEmpty ||
            product.targetClassNames.isNotEmpty)) {
      bool matchedClass = false;

      if (product.targetClassIds.isNotEmpty &&
          context.studentClassIds.any(product.targetClassIds.contains)) {
        matchedClass = true;
      }

      if (!matchedClass && product.targetClassNames.isNotEmpty) {
        final buyerNames = <String>{
          ...context.studentClassNames.map(
            StoreClassLevels.normalizeClassToken,
          ),
          if (context.studentClass != null &&
              context.studentClass!.trim().isNotEmpty)
            StoreClassLevels.normalizeClassToken(context.studentClass!),
        };
        final buyerBranches = <String>{
          ...context.studentBranches.map(StoreClassLevels.normalizeClassToken),
        };
        if (buyerBranches.isEmpty &&
            context.studentClass != null &&
            context.studentClass!.trim().isNotEmpty) {
          final fbBranch = StoreClassLevels.extractBranch(
            className: context.studentClass,
          );
          if (fbBranch != null && fbBranch.isNotEmpty) {
            buyerBranches.add(fbBranch);
          }
        }

        for (final rawTarget in product.targetClassNames) {
          var normTarget = StoreClassLevels.normalizeClassToken(rawTarget);
          normTarget = normTarget
              .replaceAll(RegExp(r'\s+ŞUBESİ$'), '')
              .replaceAll(RegExp(r'\s+ŞUBE$'), '')
              .trim();
          if (normTarget.isEmpty) continue;
          if (buyerNames.contains(normTarget) ||
              buyerBranches.contains(normTarget)) {
            matchedClass = true;
            break;
          }
        }
      }

      if (!matchedClass) return false;
    }

    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. KARGO HESAPLAMA & SPLIT-ORDER ONLİNE ÖDEME (CHECKOUT)
  // ═══════════════════════════════════════════════════════════════════════════

  double calculateHqShipping({
    required double hqSubtotal,
    required String deliveryType,
    required HqStoreSchoolAccess hqSettings,
  }) {
    if (hqSubtotal <= 0) return 0.0;
    if (deliveryType == 'Okuldan Teslim') return 0.0;
    if (hqSettings.freeShippingThreshold > 0 &&
        hqSubtotal >= hqSettings.freeShippingThreshold) {
      return 0.0;
    }
    return hqSettings.shippingFee;
  }

  double calculateSchoolShipping({
    required double schoolSubtotal,
    required String deliveryType,
    required SchoolStoreSettings schoolSettings,
  }) {
    if (schoolSubtotal <= 0) return 0.0;
    if (deliveryType == 'Okuldan Teslim') return 0.0;
    if (schoolSettings.freeShippingThreshold > 0 &&
        schoolSubtotal >= schoolSettings.freeShippingThreshold) {
      return 0.0;
    }
    return schoolSettings.shippingFee;
  }

  String _generateOrderNo(String prefix) {
    final datePart = DateFormat('yyyyMMdd').format(DateTime.now());
    final randPart = 1000 + math.Random().nextInt(9000);
    return '$prefix-$datePart-$randPart';
  }

  /// Sepetteki ürünleri satıcı tipine (`'hq'` vs `'school'`) göre otomatik ayırır,
  /// her satıcı için bağımsız `StoreOrder` oluşturur ve stok/satış adedini günceller.
  Future<List<StoreOrder>> placeOnlineOrder({
    required BuyerStoreContext context,
    required List<StoreCartItem> cartItems,
    required String deliveryType,
    required String deliveryAddress,
    required String buyerName,
    required String buyerPhone,
    required String buyerEmail,
    String? studentName,
    String? studentClass,
    String orderNote = '',
    String paymentRef = '',
    String cardMasked = '',
    int installmentCount = 1,
    String? hqDeliveryType,
    String? schoolDeliveryType,
    required HqStoreSchoolAccess hqSettings,
    required SchoolStoreSettings schoolSettings,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw StateError('Sipariş verebilmek için oturum açmış olmalısınız.');
    }
    if (cartItems.isEmpty) {
      throw ArgumentError('Sepetiniz boş.');
    }

    final qtyByProductId = <String, int>{};
    final titleByProductId = <String, String>{};
    for (final item in cartItems) {
      qtyByProductId[item.product.id] =
          (qtyByProductId[item.product.id] ?? 0) + item.quantity;
      titleByProductId[item.product.id] = item.product.title;
    }

    // 0) Sipariş kaydı oluşturmadan önce tüm ürünlerin güncel stok ve aktiflik durumunu doğrula
    final freshProductSnapshots =
        <String, DocumentSnapshot<Map<String, dynamic>>>{};
    for (final entry in qtyByProductId.entries) {
      final pName = titleByProductId[entry.key] ?? 'Ürün';
      final prodRef = _db.collection(productsCollection).doc(entry.key);
      final freshSnap = await prodRef.get();
      if (!freshSnap.exists) {
        throw StateError('Üzgünüz, "$pName" ürünü artık satışta bulunmuyor.');
      }
      final data = freshSnap.data() ?? {};
      if (data['isActive'] == false) {
        throw StateError('Üzgünüz, "$pName" ürünü şu an satışa kapalı.');
      }
      final currentStock = (data['stock'] as num?)?.toInt() ?? 0;
      if (currentStock < entry.value) {
        throw StateError('Üzgünüz, "$pName" ürünü için yeterli stok kalmadı.');
      }
      freshProductSnapshots[entry.key] = freshSnap;
    }

    final hqCart = cartItems.where((c) => c.product.isHq).toList();
    final schoolCart = cartItems.where((c) => c.product.isSchool).toList();

    final createdOrders = <StoreOrder>[];
    final now = DateTime.now();
    final instUpper = context.institutionId.trim().toUpperCase();

    // 1) Genel Merkez Siparişi -> Doğrudan SUPER_ADMIN paneline düşer!
    if (hqCart.isNotEmpty) {
      final effectiveHqDelivery = hqDeliveryType ?? deliveryType;
      final subtotal = hqCart.fold<double>(0.0, (acc, i) => acc + i.lineTotal);
      final cargoSubtotal = hqCart
          .where((i) => i.product.allowHomeDelivery)
          .fold<double>(0.0, (acc, i) => acc + i.lineTotal);
      final shipping = calculateHqShipping(
        hqSubtotal: effectiveHqDelivery == 'Karma Teslimat'
            ? cargoSubtotal
            : subtotal,
        deliveryType: effectiveHqDelivery == 'Karma Teslimat'
            ? 'Adrese Kargo'
            : effectiveHqDelivery,
        hqSettings: hqSettings,
      );
      final docRef = _db.collection(ordersCollection).doc();
      final hqOrder = StoreOrder(
        id: docRef.id,
        orderNo: _generateOrderNo('ORD-GM'),
        sellerType: 'hq',
        sellerInstitutionId: hqDocId,
        sellerName: 'Genel Merkez Mağazası',
        buyerUid: currentUser.uid,
        buyerName: buyerName.trim(),
        buyerRole: context.buyerRole,
        buyerPhone: buyerPhone.trim(),
        buyerEmail: buyerEmail.trim(),
        studentId: context.studentId,
        studentName: studentName?.trim().isNotEmpty == true
            ? studentName!.trim()
            : context.studentName,
        studentClass: studentClass?.trim().isNotEmpty == true
            ? studentClass!.trim()
            : context.studentClass,
        institutionId: instUpper,
        schoolId: context.schoolId,
        schoolName: context.schoolName,
        schoolTypeId: context.primarySchoolTypeId,
        schoolTypeName: context.primarySchoolTypeName,
        items: hqCart.map(StoreOrderItem.fromCartItem).toList(),
        subtotal: subtotal,
        shippingFee: shipping,
        totalAmount: subtotal + shipping,
        deliveryType: effectiveHqDelivery,
        deliveryAddress: effectiveHqDelivery == 'Okuldan Teslim'
            ? '${context.schoolName} — Okul Teslim Noktası'
            : deliveryAddress.trim(),
        orderNote: orderNote.trim(),
        paymentStatus: 'pending', // yalnızca Cloud Function 'paid' yapar
        paymentMethod: 'online_card',
        paymentRef: paymentRef,
        cardMasked: cardMasked,
        installmentCount: installmentCount,
        orderStatus: StoreOrderStatuses.bekliyor,
        createdAt: now,
        updatedAt: now,
      );
      await docRef.set(hqOrder.toMap(isNew: true));
      createdOrders.add(hqOrder);
    }

    // 2) Okul Mağazası Siparişi -> Doğrudan o okulun mağaza siparişlerine düşer!
    if (schoolCart.isNotEmpty) {
      final effectiveSchoolDelivery = schoolDeliveryType ?? deliveryType;
      final subtotal = schoolCart.fold<double>(
        0.0,
        (acc, i) => acc + i.lineTotal,
      );
      final cargoSubtotal = schoolCart
          .where((i) => i.product.allowHomeDelivery)
          .fold<double>(0.0, (acc, i) => acc + i.lineTotal);
      final shipping = calculateSchoolShipping(
        schoolSubtotal: effectiveSchoolDelivery == 'Karma Teslimat'
            ? cargoSubtotal
            : subtotal,
        deliveryType: effectiveSchoolDelivery == 'Karma Teslimat'
            ? 'Adrese Kargo'
            : effectiveSchoolDelivery,
        schoolSettings: schoolSettings,
      );
      final docRef = _db.collection(ordersCollection).doc();
      final schoolOrder = StoreOrder(
        id: docRef.id,
        orderNo: _generateOrderNo('ORD-OKL'),
        sellerType: 'school',
        sellerInstitutionId: instUpper,
        sellerName: '${context.schoolName} Mağazası',
        buyerUid: currentUser.uid,
        buyerName: buyerName.trim(),
        buyerRole: context.buyerRole,
        buyerPhone: buyerPhone.trim(),
        buyerEmail: buyerEmail.trim(),
        studentId: context.studentId,
        studentName: studentName?.trim().isNotEmpty == true
            ? studentName!.trim()
            : context.studentName,
        studentClass: studentClass?.trim().isNotEmpty == true
            ? studentClass!.trim()
            : context.studentClass,
        institutionId: instUpper,
        schoolId: context.schoolId,
        schoolName: context.schoolName,
        schoolTypeId: context.primarySchoolTypeId,
        schoolTypeName: context.primarySchoolTypeName,
        items: schoolCart.map(StoreOrderItem.fromCartItem).toList(),
        subtotal: subtotal,
        shippingFee: shipping,
        totalAmount: subtotal + shipping,
        deliveryType: effectiveSchoolDelivery,
        deliveryAddress: effectiveSchoolDelivery == 'Okuldan Teslim'
            ? '${context.schoolName} — Okul Teslim Noktası'
            : deliveryAddress.trim(),
        orderNote: orderNote.trim(),
        paymentStatus: 'pending', // yalnızca Cloud Function 'paid' yapar
        paymentMethod: 'online_card',
        paymentRef: paymentRef,
        cardMasked: cardMasked,
        installmentCount: installmentCount,
        orderStatus: StoreOrderStatuses.bekliyor,
        createdAt: now,
        updatedAt: now,
      );
      await docRef.set(schoolOrder.toMap(isNew: true));
      createdOrders.add(schoolOrder);
    }

    // 3) Stok düşümü & satış sayacı artışı
    // DİKKAT: firestore.rules gereği alıcı yalnızca ['stock', 'soldCount', 'updatedAt'] alanlarını güncelleyebilir!
    for (final entry in qtyByProductId.entries) {
      try {
        final prodRef = _db.collection(productsCollection).doc(entry.key);
        final snap = freshProductSnapshots[entry.key] ?? await prodRef.get();
        if (snap.exists) {
          final data = snap.data() ?? {};
          final currentStock = (data['stock'] as num?)?.toInt() ?? 0;
          final currentSold = (data['soldCount'] as num?)?.toInt() ?? 0;
          await prodRef.update({
            'stock': math.max(0, currentStock - entry.value),
            'soldCount': currentSold + entry.value,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      } catch (_) {
        // Ürün silinmişse veya anlık ağ kesintisi olursa sipariş kaydı korunur.
      }
    }

    return createdOrders;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. SİPARİŞ İZLEME VE DURUM YÖNETİMİ
  // ═══════════════════════════════════════════════════════════════════════════

  /// Ödemesi henüz tamamlanmamış (`pending`) veya başarısız (`failed`) siparişler
  /// satıcı/alıcı listelerinde görünmez.
  static bool _isPaymentSettled(StoreOrder o) =>
      o.paymentStatus != 'pending' && o.paymentStatus != 'failed';

  /// Genel Merkez (`sellerType == 'hq'`) siparişlerini canlı izler.
  Stream<List<StoreOrder>> watchHqOrders() {
    return _db
        .collection(ordersCollection)
        .where('sellerType', isEqualTo: 'hq')
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map(StoreOrder.fromFirestore)
              .where(_isPaymentSettled)
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  /// Belirli bir okulun mağazasına ait (`sellerType == 'school'` & `sellerInstitutionId == INST`) siparişleri canlı izler.
  Stream<List<StoreOrder>> watchSchoolOrders(String institutionId) {
    final upper = institutionId.trim().toUpperCase();
    if (upper.isEmpty) {
      return Stream.value(const <StoreOrder>[]);
    }
    return _db
        .collection(ordersCollection)
        .where('sellerInstitutionId', isEqualTo: upper)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map(StoreOrder.fromFirestore)
              .where((o) => o.sellerType == 'school')
              .where(_isPaymentSettled)
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  /// Alıcının kendi verdiği tüm siparişleri (HQ + Okul) canlı izler.
  Stream<List<StoreOrder>> watchBuyerOrders(String buyerUid) {
    if (buyerUid.trim().isEmpty) {
      return Stream.value(const <StoreOrder>[]);
    }
    return _db
        .collection(ordersCollection)
        .where('buyerUid', isEqualTo: buyerUid.trim())
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map(StoreOrder.fromFirestore)
              .where(_isPaymentSettled)
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  /// Öğrenci adına (örn. diğer veli tarafından) daha önce alınmış geçerli siparişlerdeki
  /// ürün ID'lerini izler (zorunlu ürünlerin ikinci kez eklenmemesi için).
  Stream<Set<String>> watchStudentPurchasedProductIds(String? studentId) {
    final sid = studentId?.trim() ?? '';
    if (sid.isEmpty) {
      return Stream.value(const <String>{});
    }
    return _db
        .collection(ordersCollection)
        .where('studentId', isEqualTo: sid)
        .snapshots()
        .map((snap) {
          final ids = <String>{};
          for (final doc in snap.docs) {
            final order = StoreOrder.fromFirestore(doc);
            if (!_isPaymentSettled(order)) continue;
            if (order.orderStatus == StoreOrderStatuses.iptal) continue;
            for (final it in order.items) {
              if (it.productId.trim().isNotEmpty) {
                ids.add(it.productId.trim());
              }
            }
          }
          return ids;
        })
        .handleError((_) => const <String>{});
  }

  /// İptal edilen siparişteki ürünlerin stoklarını geri ekler ve `soldCount` değerini düşürür.
  Future<void> _restoreOrderStockIfCancelled(StoreOrder order) async {
    final qtyByProductId = <String, int>{};
    for (final item in order.items) {
      final pid = item.productId.trim();
      if (pid.isEmpty || item.quantity <= 0) continue;
      qtyByProductId[pid] = (qtyByProductId[pid] ?? 0) + item.quantity;
    }
    for (final entry in qtyByProductId.entries) {
      try {
        final prodRef = _db.collection(productsCollection).doc(entry.key);
        final snap = await prodRef.get();
        if (!snap.exists) continue;
        final data = snap.data() ?? {};
        final currentStock = (data['stock'] as num?)?.toInt() ?? 0;
        final currentSold = (data['soldCount'] as num?)?.toInt() ?? 0;
        await prodRef.update({
          'stock': currentStock + entry.value,
          'soldCount': math.max(0, currentSold - entry.value),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // Ürün silinmişse veya erişilemiyorsa iptal durumu korunur.
      }
    }
  }

  /// Satıcı (Süper Admin veya Okul Yönetimi) tarafından sipariş durumunu günceller.
  Future<void> updateOrderStatusBySeller({
    required String orderId,
    required String newStatus,
    String? trackingCode,
    String? cancelReason,
  }) async {
    final orderRef = _db.collection(ordersCollection).doc(orderId);
    StoreOrder? prevOrder;
    if (newStatus == StoreOrderStatuses.iptal) {
      final prevSnap = await orderRef.get();
      if (prevSnap.exists) {
        prevOrder = StoreOrder.fromFirestore(prevSnap);
      }
    }

    final payload = <String, dynamic>{
      'orderStatus': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (trackingCode != null) {
      payload['trackingCode'] = trackingCode.trim();
    }
    if (cancelReason != null) {
      payload['cancelReason'] = cancelReason.trim();
    }
    await orderRef.update(payload);

    if (newStatus == StoreOrderStatuses.iptal &&
        prevOrder != null &&
        prevOrder.orderStatus != StoreOrderStatuses.iptal) {
      await _restoreOrderStockIfCancelled(prevOrder);
    }
  }

  /// Alıcının henüz `'bekliyor'` durumundaki kendi siparişini iptal etmesi.
  /// `firestore.rules` gereği yalnızca `['orderStatus', 'cancelReason', 'updatedAt']` alanları güncellenir.
  Future<void> cancelOrderByBuyer({
    required String orderId,
    required String cancelReason,
  }) async {
    final orderRef = _db.collection(ordersCollection).doc(orderId);
    final prevSnap = await orderRef.get();
    final prevOrder = prevSnap.exists
        ? StoreOrder.fromFirestore(prevSnap)
        : null;

    await orderRef.update({
      'orderStatus': StoreOrderStatuses.iptal,
      'cancelReason': cancelReason.trim().isEmpty
          ? 'Alıcı tarafından iptal edildi'
          : cancelReason.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (prevOrder != null &&
        prevOrder.orderStatus != StoreOrderStatuses.iptal) {
      await _restoreOrderStockIfCancelled(prevOrder);
    }
  }
}
