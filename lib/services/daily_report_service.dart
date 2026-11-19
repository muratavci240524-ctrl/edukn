import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';

import '../models/school/daily_report_models.dart';
import 'crypto_service.dart';
import 'term_service.dart';
import 'user_permission_service.dart';

class DailyReportClassInfo {
  final String id;
  final String name;
  final String classLevel;
  final String schoolTypeId;
  final String schoolTypeName;
  final String classTeacherName;

  const DailyReportClassInfo({
    required this.id,
    required this.name,
    this.classLevel = '',
    this.schoolTypeId = '',
    this.schoolTypeName = '',
    this.classTeacherName = '',
  });
}

class DailyReportStudentInfo {
  final String id;
  final String fullName;
  final String studentNo;
  final String gender;
  final String photoUrl;
  final String classId;
  final String className;
  final String classLevel;
  final String schoolTypeId;
  final String schoolTypeName;
  final String allergyOrHealthInfo;

  const DailyReportStudentInfo({
    required this.id,
    required this.fullName,
    this.studentNo = '',
    this.gender = '',
    this.photoUrl = '',
    required this.classId,
    required this.className,
    this.classLevel = '',
    this.schoolTypeId = '',
    this.schoolTypeName = '',
    this.allergyOrHealthInfo = '',
  });
}

class DailyReportService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static final Map<String, String> _schoolDocIdCache = {};

  static String formatDateKey(DateTime dt) =>
      DateFormat('yyyy-MM-dd').format(DateTime(dt.year, dt.month, dt.day));

  List<String> _instVariants(String institutionId) {
    return {
      institutionId.trim(),
      institutionId.trim().toUpperCase(),
      institutionId.trim().toLowerCase(),
    }.where((e) => e.isNotEmpty).toList();
  }

  static bool isAdminRole(String rawRole) {
    final r = rawRole.trim().toLowerCase();
    return r == 'admin' ||
        r == 'super_admin' ||
        r == 'kurucu' ||
        r == 'genel_mudur' ||
        r == 'genel müdür' ||
        r == 'genel mudur' ||
        r == 'mudur' ||
        r == 'müdür' ||
        r == 'mudur_yardimcisi' ||
        r == 'müdür yardımcısı' ||
        r == 'kurum_muduru' ||
        r == 'kurum_yoneticisi';
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

  /// Aktif kullanıcı ve yetki bilgisini çözümler
  Future<
      ({
        String uid,
        String name,
        String role,
        bool isAdmin,
        String institutionId,
        Set<String> validTeacherIds,
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
    final first =
        (userData?['firstName'] ?? userData?['name'] ?? '').toString().trim();
    final last =
        (userData?['lastName'] ?? userData?['surname'] ?? '').toString().trim();
    final rawName = (userData?['fullName'] ??
            (first.isNotEmpty || last.isNotEmpty ? '$first $last' : '') ??
            authUser?.displayName ??
            '')
        .toString()
        .trim();

    final role = (userData?['role'] ?? userData?['title'] ?? 'ogretmen')
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

    final validTeacherIds = <String>{
      if (authUser?.uid != null && authUser!.uid.isNotEmpty) authUser.uid,
      if (uid.isNotEmpty) uid,
      if ((userData?['id'] ?? '').toString().trim().isNotEmpty)
        userData!['id'].toString().trim(),
      if ((userData?['teacherId'] ?? '').toString().trim().isNotEmpty)
        userData!['teacherId'].toString().trim(),
    };

    return (
      uid: uid,
      name: rawName.isNotEmpty ? rawName : (authUser?.email ?? 'Öğretmen'),
      role: role,
      isAdmin: userData == null ? true : isAdminRole(role),
      institutionId: instId,
      validTeacherIds: validTeacherIds,
      userData: userData,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MODÜL AÇMA / KAPATMA VE KONFİGÜRASYON YÖNETİMİ
  // ═══════════════════════════════════════════════════════════════════════════

  Future<DailyReportConfigModel> loadConfig(String schoolDocId) async {
    if (schoolDocId.isEmpty) return const DailyReportConfigModel();
    try {
      final results = await Future.wait([
        _db.collection('schools').doc(schoolDocId).get(),
        _db
            .collection('schools')
            .doc(schoolDocId)
            .collection('settings')
            .doc('daily_report_config')
            .get(),
      ]);

      final schoolData = results[0].data();
      final appSettings = schoolData?['appSettings'] as Map<String, dynamic>?;
      final disabledModules =
          appSettings?['disabledModules'] as List<dynamic>? ?? const [];
      final schoolTypeDisabledModules =
          appSettings?['schoolTypeDisabledModules'] as Map<String, dynamic>?;

      final cfgData = results[1].exists
          ? results[1].data()
          : (appSettings?['dailyReport'] as Map<String, dynamic>?);

      return DailyReportConfigModel.fromMap(
        cfgData,
        appDisabledModules: disabledModules,
        schoolTypeDisabledModules: schoolTypeDisabledModules,
      );
    } catch (_) {
      return const DailyReportConfigModel();
    }
  }

  Stream<DailyReportConfigModel> watchConfig(String schoolDocId) {
    if (schoolDocId.isEmpty) {
      return Stream.value(const DailyReportConfigModel());
    }
    return _db
        .collection('schools')
        .doc(schoolDocId)
        .snapshots()
        .asyncMap((schoolSnap) async {
      final schoolData = schoolSnap.data();
      final appSettings = schoolData?['appSettings'] as Map<String, dynamic>?;
      final disabledModules =
          appSettings?['disabledModules'] as List<dynamic>? ?? const [];
      final schoolTypeDisabledModules =
          appSettings?['schoolTypeDisabledModules'] as Map<String, dynamic>?;
      try {
        final cfgDoc = await _db
            .collection('schools')
            .doc(schoolDocId)
            .collection('settings')
            .doc('daily_report_config')
            .get();
        final cfgMap = cfgDoc.exists
            ? cfgDoc.data()
            : (appSettings?['dailyReport'] as Map<String, dynamic>?);
        return DailyReportConfigModel.fromMap(
          cfgMap,
          appDisabledModules: disabledModules,
          schoolTypeDisabledModules: schoolTypeDisabledModules,
        );
      } catch (_) {
        return DailyReportConfigModel.fromMap(
          appSettings?['dailyReport'] as Map<String, dynamic>?,
          appDisabledModules: disabledModules,
          schoolTypeDisabledModules: schoolTypeDisabledModules,
        );
      }
    });
  }

  /// Hem `settings/daily_report_config` alt dokümanını hem de `schools/{id}.appSettings`
  /// içindeki `disabledModules` (`egitim.gunluk_rapor`) anahtarını senkron kaydeder.
  Future<void> saveConfig({
    required String schoolDocId,
    required DailyReportConfigModel config,
  }) async {
    if (schoolDocId.isEmpty) return;

    await _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('settings')
        .doc('daily_report_config')
        .set({
      ...config.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    try {
      final schoolDoc = await _db.collection('schools').doc(schoolDocId).get();
      final appSettings = Map<String, dynamic>.from(
        (schoolDoc.data()?['appSettings'] as Map?) ?? {},
      );
      final disabled = List<String>.from(appSettings['disabledModules'] ?? []);
      if (config.enabled) {
        disabled.remove('egitim.gunluk_rapor');
      } else {
        if (!disabled.contains('egitim.gunluk_rapor')) {
          disabled.add('egitim.gunluk_rapor');
        }
      }
      appSettings['disabledModules'] = disabled;
      appSettings['dailyReport'] = config.toMap();

      await _db.collection('schools').doc(schoolDocId).set({
        'appSettings': appSettings,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Kurumdaki okul türlerini listeler (Anaokulu, İlkokul vb.)
  Future<List<({String id, String name})>> loadSchoolTypes(
    String institutionId,
  ) async {
    final variants = _instVariants(institutionId);
    if (variants.isEmpty) return const [];

    final map = <String, String>{};
    for (final col in const ['school_types', 'schoolTypes']) {
      try {
        final snap = await _db
            .collection(col)
            .where('institutionId', whereIn: variants)
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          final name = (data['schoolTypeName'] ??
                  data['name'] ??
                  data['typeName'] ??
                  '')
              .toString()
              .trim();
          if (name.isNotEmpty) {
            map[doc.id] = name;
          }
        }
      } catch (_) {}
    }

    final list = map.entries
        .map((e) => (id: e.key, name: e.value))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // YETKİYE GÖRE SINIF & ÖĞRENCİ ÇÖZÜMLEME (ÖĞRETMEN = KENDİ ÖĞRENCİLERİ, YÖNETİCİ = TÜMÜ)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<
      ({
        List<DailyReportClassInfo> classes,
        List<DailyReportStudentInfo> students,
      })> loadAccessibleClassesAndStudents({
    required String institutionId,
    required bool isAdmin,
    required Set<String> validTeacherIds,
    String? fixedSchoolTypeId,
  }) async {
    await CryptoService.init();
    final variants = _instVariants(institutionId);
    if (variants.isEmpty) {
      return (
        classes: const <DailyReportClassInfo>[],
        students: const <DailyReportStudentInfo>[],
      );
    }

    final activeTermId = await TermService().getActiveTermId();

    // 1. Kurumdaki şubeleri yükle
    final classesSnap = await _db
        .collection('classes')
        .where('institutionId', whereIn: variants)
        .get();

    final schoolTypeNames = <String, String>{};
    for (final st in await loadSchoolTypes(institutionId)) {
      schoolTypeNames[st.id] = st.name;
    }

    // Öğretmen ise atanmış sınıf ID'lerini bul (Sınıf Öğretmenliği + Ders Ataması)
    final Set<String> teacherAssignedClassIds = {};
    if (!isAdmin && validTeacherIds.isNotEmpty) {
      for (final cDoc in classesSnap.docs) {
        final cData = cDoc.data();
        final ctId = (cData['classTeacherId'] ??
                cData['teacherId'] ??
                cData['advisorTeacherId'] ??
                '')
            .toString()
            .trim();
        if (ctId.isNotEmpty && validTeacherIds.contains(ctId)) {
          teacherAssignedClassIds.add(cDoc.id);
        }
      }

      try {
        final variantSet = variants.toSet();
        final assignFutures = validTeacherIds.map(
          (tId) => _db
              .collection('lessonAssignments')
              .where('teacherIds', arrayContains: tId)
              .get(),
        );
        final assignSnaps = await Future.wait(assignFutures);
        for (final snap in assignSnaps) {
          for (final doc in snap.docs) {
            final d = doc.data();
            if (d['isActive'] == false) continue;
            final docInst = (d['institutionId'] ?? '').toString().trim();
            if (docInst.isNotEmpty &&
                !variantSet.contains(docInst) &&
                !variantSet.contains(docInst.toUpperCase())) {
              continue;
            }
            final docTerm = (d['termId'] ?? '').toString().trim();
            if (activeTermId != null &&
                activeTermId.isNotEmpty &&
                docTerm.isNotEmpty &&
                docTerm != activeTermId) {
              continue;
            }
            final cid = (d['classId'] ?? '').toString().trim();
            if (cid.isNotEmpty) teacherAssignedClassIds.add(cid);
          }
        }
      } catch (_) {}
    }

    final stFilter = (fixedSchoolTypeId ?? '').trim();
    final classMap = <String, DailyReportClassInfo>{};

    for (final doc in classesSnap.docs) {
      final data = doc.data();
      if (data['isActive'] == false) continue;

      final docTermId = (data['termId'] ?? '').toString().trim();
      if (activeTermId != null &&
          activeTermId.isNotEmpty &&
          docTermId.isNotEmpty &&
          docTermId != activeTermId) {
        // Eğer öğretmen doğrudan bu sınıfa atanmışsa dönem uyuşmazlığından düşmesin
        if (isAdmin || !teacherAssignedClassIds.contains(doc.id)) {
          continue;
        }
      }

      final stId = (data['schoolTypeId'] ?? '').toString().trim();
      if (stFilter.isNotEmpty && stId.isNotEmpty && stId != stFilter) {
        continue;
      }

      if (!isAdmin && !teacherAssignedClassIds.contains(doc.id)) {
        continue;
      }

      final cName = (data['className'] ?? data['name'] ?? '').toString().trim();
      if (cName.isEmpty) continue;

      final stName = (data['schoolTypeName'] ?? schoolTypeNames[stId] ?? '')
          .toString()
          .trim();

      classMap[doc.id] = DailyReportClassInfo(
        id: doc.id,
        name: cName,
        classLevel: (data['classLevel'] ?? '').toString().trim(),
        schoolTypeId: stId,
        schoolTypeName: stName,
        classTeacherName: (data['classTeacherName'] ?? '').toString().trim(),
      );
    }

    if (classMap.isEmpty && !isAdmin) {
      return (
        classes: const <DailyReportClassInfo>[],
        students: const <DailyReportStudentInfo>[],
      );
    }

    // 2. Öğrencileri yükle
    final studentsList = <DailyReportStudentInfo>[];
    final variantSet = variants.toSet();
    if (isAdmin) {
      final snap = await _db
          .collection('students')
          .where('institutionId', whereIn: variants)
          .get();
      for (final doc in snap.docs) {
        final parsed = _parseStudentDoc(
          doc,
          institutionId: institutionId,
          classMap: classMap,
          schoolTypeNames: schoolTypeNames,
          fixedSchoolTypeId: stFilter,
          allowDynamicClassCreation: true,
        );
        if (parsed != null) studentsList.add(parsed);
      }
    } else if (classMap.isNotEmpty) {
      final ids = classMap.keys.toList();
      final queries = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
      for (int i = 0; i < ids.length; i += 10) {
        final chunk = ids.skip(i).take(10).toList();
        queries.add(
          _db.collection('students').where('classId', whereIn: chunk).get(),
        );
      }
      final snaps = await Future.wait(queries);
      for (final snap in snaps) {
        for (final doc in snap.docs) {
          final docInst = (doc.data()['institutionId'] ?? '').toString().trim();
          if (docInst.isNotEmpty &&
              !variantSet.contains(docInst) &&
              !variantSet.contains(docInst.toUpperCase())) {
            continue;
          }
          final parsed = _parseStudentDoc(
            doc,
            institutionId: institutionId,
            classMap: classMap,
            schoolTypeNames: schoolTypeNames,
            fixedSchoolTypeId: stFilter,
            allowDynamicClassCreation: false,
          );
          if (parsed != null) studentsList.add(parsed);
        }
      }
    }

    final sortedClasses = classMap.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    studentsList.sort((a, b) => a.fullName.compareTo(b.fullName));

    return (classes: sortedClasses, students: studentsList);
  }

  DailyReportStudentInfo? _parseStudentDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required String institutionId,
    required Map<String, DailyReportClassInfo> classMap,
    required Map<String, String> schoolTypeNames,
    required String fixedSchoolTypeId,
    required bool allowDynamicClassCreation,
  }) {
    final raw = Map<String, dynamic>.from(doc.data());
    if (raw['isActive'] == false || raw['status'] == 'passive') return null;

    raw['id'] = doc.id;
    final data = CryptoService.decryptMap(raw, institutionId: institutionId);

    final stId = (data['schoolTypeId'] ?? '').toString().trim();
    if (fixedSchoolTypeId.isNotEmpty &&
        stId.isNotEmpty &&
        stId != fixedSchoolTypeId) {
      return null;
    }

    String classId = (data['classId'] ?? '').toString().trim();
    String className = (data['className'] ?? '').toString().trim();

    if (classId.isNotEmpty && classMap.containsKey(classId)) {
      className = classMap[classId]!.name;
    } else if (allowDynamicClassCreation && className.isNotEmpty) {
      final syntheticId = classId.isNotEmpty ? classId : 'cls_$className';
      classId = syntheticId;
      classMap.putIfAbsent(
        syntheticId,
        () => DailyReportClassInfo(
          id: syntheticId,
          name: className,
          classLevel: (data['classLevel'] ?? '').toString().trim(),
          schoolTypeId: stId,
          schoolTypeName:
              (data['schoolTypeName'] ?? schoolTypeNames[stId] ?? '')
                  .toString()
                  .trim(),
        ),
      );
    } else if (!classMap.containsKey(classId)) {
      return null;
    }

    final first = (data['name'] ?? data['firstName'] ?? '').toString().trim();
    final last = (data['surname'] ?? data['lastName'] ?? '').toString().trim();
    final fullName = (data['fullName'] ?? '$first $last').toString().trim();
    if (fullName.isEmpty) return null;

    final clsInfo = classMap[classId];
    final allergy = (data['allergy'] ??
            data['allergies'] ??
            data['chronicDisease'] ??
            data['healthNotes'] ??
            '')
        .toString()
        .trim();

    return DailyReportStudentInfo(
      id: doc.id,
      fullName: fullName,
      studentNo: (data['studentNo'] ??
              data['studentNumber'] ??
              data['schoolNumber'] ??
              '')
          .toString()
          .trim(),
      gender: (data['gender'] ?? '').toString().trim(),
      photoUrl: (data['photoUrl'] ?? data['profilePhotoUrl'] ?? '')
          .toString()
          .trim(),
      classId: classId,
      className: className.isNotEmpty ? className : (clsInfo?.name ?? 'Sınıf'),
      classLevel: (data['classLevel'] ?? clsInfo?.classLevel ?? '')
          .toString()
          .trim(),
      schoolTypeId: stId.isNotEmpty ? stId : (clsInfo?.schoolTypeId ?? ''),
      schoolTypeName: (data['schoolTypeName'] ??
              clsInfo?.schoolTypeName ??
              schoolTypeNames[stId] ??
              '')
          .toString()
          .trim(),
      allergyOrHealthInfo: allergy,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CANLI AKIŞLAR (STREAMS) - SIFIR COMPOSITE INDEX GEREKSİNİMİ
  // ═══════════════════════════════════════════════════════════════════════════

  /// Belirli bir tarihteki tüm günlük karneleri canlı izler (`studentId -> DailyReportModel`)
  Stream<Map<String, DailyReportModel>> watchReportsForDate({
    required String schoolDocId,
    required String dateKey,
  }) {
    if (schoolDocId.isEmpty || dateKey.isEmpty) {
      return Stream.value(const {});
    }
    return _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('daily_reports')
        .where('dateKey', isEqualTo: dateKey)
        .snapshots()
        .map((snap) {
      final map = <String, DailyReportModel>{};
      for (final doc in snap.docs) {
        final model = DailyReportModel.fromDoc(doc);
        if (model.studentId.isNotEmpty) {
          map[model.studentId] = model;
        }
      }
      return map;
    });
  }

  /// Veli için tek öğrencinin belirli bir gündeki karnesini O(1) doğrudan doküman üzerinden anlık izler
  Stream<DailyReportModel?> watchStudentReportForDate({
    required String schoolDocId,
    required String studentId,
    required String dateKey,
  }) {
    if (schoolDocId.isEmpty || studentId.isEmpty || dateKey.isEmpty) {
      return Stream.value(null);
    }
    final docId = DailyReportModel.buildDocId(dateKey, studentId);
    return _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('daily_reports')
        .doc(docId)
        .snapshots()
        .map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      final model = DailyReportModel.fromDoc(doc);
      return model.hasAnyContent ? model : null;
    });
  }

  /// Veli için öğrencinin geçmiş tüm günlük karnelerini canlı izler (en yeniden eskiye sıralı)
  Stream<List<DailyReportModel>> watchStudentReportHistory({
    required String schoolDocId,
    required String studentId,
  }) {
    if (schoolDocId.isEmpty || studentId.isEmpty) {
      return Stream.value(const []);
    }
    return _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('daily_reports')
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => DailyReportModel.fromDoc(d))
          .where((r) => r.hasAnyContent && r.isPublished)
          .toList()
        ..sort((a, b) => b.dateKey.compareTo(a.dateKey));
      return list;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // KAYIT, SINIFA TOPLU GİRİŞ VE HIZLI DÜZENLEME İŞLEMLERİ
  // ═══════════════════════════════════════════════════════════════════════════

  /// Tekil öğrenci günlük karnesini kaydeder / günceller
  Future<void> saveStudentReport({
    required DailyReportModel report,
    required String actorUid,
    required String actorName,
  }) async {
    if (report.schoolDocId.isEmpty || report.studentId.isEmpty) return;

    final docId = DailyReportModel.buildDocId(report.dateKey, report.studentId);
    final contributors = <String>{
      ...report.contributors,
      if (actorName.trim().isNotEmpty) actorName.trim(),
    }.toList();

    final updated = report.copyWith(
      id: docId,
      updatedAt: DateTime.now(),
      updatedByUid: actorUid,
      updatedByName: actorName,
      contributors: contributors,
    );

    await _db
        .collection('schools')
        .doc(report.schoolDocId)
        .collection('daily_reports')
        .doc(docId)
        .set(updated.toMap(), SetOptions(merge: true));
  }

  /// Öğrenci kartı üzerinden tek dokunuşla hızlı istisna düzenleme (ör. Sadece Ayşe'nin kahvaltısını "Az Yaptı" yap)
  Future<void> quickPatchStudentReport({
    required String institutionId,
    required String schoolDocId,
    required DailyReportStudentInfo student,
    required String dateKey,
    required DailyReportModel? existing,
    required String actorUid,
    required String actorName,
    String? mood,
    MealEntryModel? breakfast,
    MealEntryModel? lunch,
    MealEntryModel? snack,
    SleepEntryModel? sleep,
  }) async {
    final base = existing ??
        DailyReportModel(
          id: DailyReportModel.buildDocId(dateKey, student.id),
          institutionId: institutionId,
          schoolDocId: schoolDocId,
          schoolTypeId: student.schoolTypeId,
          schoolTypeName: student.schoolTypeName,
          classId: student.classId,
          className: student.className,
          classLevel: student.classLevel,
          studentId: student.id,
          studentName: student.fullName,
          studentNo: student.studentNo,
          dateKey: dateKey,
          updatedAt: DateTime.now(),
        );

    final patched = base.copyWith(
      mood: mood ?? base.mood,
      breakfast: breakfast ?? base.breakfast,
      lunch: lunch ?? base.lunch,
      snack: snack ?? base.snack,
      sleep: sleep ?? base.sleep,
    );

    await saveStudentReport(
      report: patched,
      actorUid: actorUid,
      actorName: actorName,
    );
  }

  /// Sınıftaki tüm (veya seçili) öğrencilere tek seferde toplu günlük karne verisi işler.
  /// Akıllı birleştirme: Yalnızca doldurulan bölümleri günceller, daha önce girilmiş diğer bölümleri ve
  /// (istenirse) bireysel notları korur.
  Future<int> applyBulkClassReport({
    required String institutionId,
    required String schoolDocId,
    required String dateKey,
    required List<DailyReportStudentInfo> targetStudents,
    required Map<String, DailyReportModel> existingByStudentId,
    required String actorUid,
    required String actorName,
    String? mood,
    String? socialHarmony,
    MealEntryModel? breakfast,
    MealEntryModel? lunch,
    MealEntryModel? snack,
    String? waterIntake,
    SleepEntryModel? sleep,
    List<DailyActivityItemModel> newActivitiesToAppend = const [],
    List<String>? selfCareTagsToAdd,
    List<String>? neededItemsToAdd,
    String? sharedTeacherNote,
    bool overwriteExistingStudentNote = false,
  }) async {
    if (schoolDocId.isEmpty || targetStudents.isEmpty) return 0;

    final now = DateTime.now();
    int written = 0;

    for (int i = 0; i < targetStudents.length; i += 350) {
      final chunk = targetStudents.skip(i).take(350).toList();
      final batch = _db.batch();

      for (final student in chunk) {
        final docId = DailyReportModel.buildDocId(dateKey, student.id);
        final existing = existingByStudentId[student.id];

        final base = existing ??
            DailyReportModel(
              id: docId,
              institutionId: institutionId,
              schoolDocId: schoolDocId,
              schoolTypeId: student.schoolTypeId,
              schoolTypeName: student.schoolTypeName,
              classId: student.classId,
              className: student.className,
              classLevel: student.classLevel,
              studentId: student.id,
              studentName: student.fullName,
              studentNo: student.studentNo,
              dateKey: dateKey,
              updatedAt: now,
            );

        // Etkinlikleri mükerrer olmadan birleştir
        final mergedActivities = List<DailyActivityItemModel>.from(
          base.activities,
        );
        for (final act in newActivitiesToAppend) {
          final alreadyExists = mergedActivities.any(
            (a) =>
                a.id == act.id ||
                (a.category == act.category &&
                    a.title.toLowerCase() == act.title.toLowerCase() &&
                    a.description.toLowerCase() ==
                        act.description.toLowerCase()),
          );
          if (!alreadyExists) {
            mergedActivities.add(act);
          }
        }

        final mergedSelfCare = <String>{
          ...base.selfCareTags,
          ...?selfCareTagsToAdd,
        }.toList();

        final mergedNeeded = <String>{
          ...base.neededItems,
          ...?neededItemsToAdd,
        }.toList();

        String resolvedTeacherNote = base.teacherNote;
        if (sharedTeacherNote != null && sharedTeacherNote.trim().isNotEmpty) {
          if (base.teacherNote.trim().isEmpty || overwriteExistingStudentNote) {
            resolvedTeacherNote = sharedTeacherNote.trim();
          }
        }

        final contributors = <String>{
          ...base.contributors,
          if (actorName.trim().isNotEmpty) actorName.trim(),
        }.toList();

        final updated = base.copyWith(
          mood: (mood != null && mood.isNotEmpty) ? mood : base.mood,
          socialHarmony: (socialHarmony != null && socialHarmony.isNotEmpty)
              ? socialHarmony
              : base.socialHarmony,
          breakfast: (breakfast != null && breakfast.hasValue)
              ? breakfast
              : base.breakfast,
          lunch: (lunch != null && lunch.hasValue) ? lunch : base.lunch,
          snack: (snack != null && snack.hasValue) ? snack : base.snack,
          waterIntake: (waterIntake != null && waterIntake.isNotEmpty)
              ? waterIntake
              : base.waterIntake,
          sleep: (sleep != null && sleep.hasValue) ? sleep : base.sleep,
          activities: mergedActivities,
          selfCareTags: mergedSelfCare,
          neededItems: mergedNeeded,
          teacherNote: resolvedTeacherNote,
          updatedAt: now,
          updatedByUid: actorUid,
          updatedByName: actorName,
          contributors: contributors,
        );

        final docRef = _db
            .collection('schools')
            .doc(schoolDocId)
            .collection('daily_reports')
            .doc(docId);

        batch.set(docRef, updated.toMap(), SetOptions(merge: true));
        written++;
      }

      await batch.commit();
    }

    return written;
  }

  /// Veli raporu açtığında otomatik okundu zamanını işler
  Future<void> markSeenByParent({
    required String schoolDocId,
    required String dateKey,
    required String studentId,
  }) async {
    if (schoolDocId.isEmpty || studentId.isEmpty || dateKey.isEmpty) return;
    final docId = DailyReportModel.buildDocId(dateKey, studentId);
    try {
      final ref = _db
          .collection('schools')
          .doc(schoolDocId)
          .collection('daily_reports')
          .doc(docId);
      final snap = await ref.get();
      if (snap.exists && snap.data()?['parentSeenAt'] == null) {
        await ref.update({
          'parentSeenAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {}
  }

  /// Velinin günlük karneye emoji tepkisi veya kısa teşekkür notu bırakması
  Future<void> submitParentFeedback({
    required String schoolDocId,
    required String dateKey,
    required String studentId,
    String? reaction,
    String? feedbackNote,
  }) async {
    if (schoolDocId.isEmpty || studentId.isEmpty || dateKey.isEmpty) return;
    final docId = DailyReportModel.buildDocId(dateKey, studentId);
    final updates = <String, dynamic>{
      'parentSeenAt': FieldValue.serverTimestamp(),
      'parentFeedbackAt': FieldValue.serverTimestamp(),
    };
    if (reaction != null) updates['parentReaction'] = reaction;
    if (feedbackNote != null) {
      updates['parentFeedbackNote'] = feedbackNote.trim();
    }
    await _db
        .collection('schools')
        .doc(schoolDocId)
        .collection('daily_reports')
        .doc(docId)
        .set(updates, SetOptions(merge: true));
  }

  /// Etkinlik fotoğrafı yükleme
  Future<String> uploadActivityPhoto({
    required String schoolDocId,
    required String dateKey,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path =
        'schools/$schoolDocId/daily_reports/$dateKey/${ts}_$safeName';
    final ext = safeName.toLowerCase();
    String contentType = 'image/jpeg';
    if (ext.endsWith('.png')) contentType = 'image/png';
    if (ext.endsWith('.webp')) contentType = 'image/webp';

    final ref = FirebaseStorage.instance.ref().child(path);
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }
}
