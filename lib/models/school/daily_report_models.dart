import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Kurum / Okul Türü Bazlı Günlük Rapor (Günlük Karne) Modül Konfigürasyonu
class DailyReportConfigModel {
  final bool enabled;

  /// Boş ise tüm okul türlerinde (Anaokulu, İlkokul vb.) aktiftir.
  /// Dolu ise yalnızca listedeki `schoolTypeId` kademelerinde görünür.
  final List<String> enabledSchoolTypeIds;

  final bool trackMood;
  final bool trackMeals;
  final bool trackWater;
  final bool trackSleep;
  final bool trackActivities;
  final bool trackSelfCare;
  final bool trackHealthNote;
  final bool allowParentFeedback;

  /// Kurum geneli ve okul türü bazlı devre dışı bırakılan modül / alt başlık / 3. seviye anahtarlar
  final List<String> globalDisabledKeys;
  final Map<String, List<String>> schoolTypeDisabledModules;

  const DailyReportConfigModel({
    this.enabled = true,
    this.enabledSchoolTypeIds = const [],
    this.trackMood = true,
    this.trackMeals = true,
    this.trackWater = true,
    this.trackSleep = true,
    this.trackActivities = true,
    this.trackSelfCare = true,
    this.trackHealthNote = true,
    this.allowParentFeedback = true,
    this.globalDisabledKeys = const [],
    this.schoolTypeDisabledModules = const {},
  });

  static bool _isAnyDisabled(Iterable<String> keys, List<String> candidates) {
    final set = keys.toSet();
    for (final c in candidates) {
      if (set.contains(c)) return true;
    }
    return false;
  }

  static bool _isChildSectionDisabled(Iterable<String> keys, String childKey) {
    return _isAnyDisabled(keys, [
      childKey,
      'egitim.gunluk_rapor.$childKey',
      'st.egitim.gunluk_rapor.$childKey',
      't.egitim_islemleri.gunluk_rapor.$childKey',
      'egitim.$childKey',
      'st.egitim.$childKey',
    ]);
  }

  static bool _isModuleOrParentDisabled(Iterable<String> keys) {
    return _isAnyDisabled(keys, const [
      'egitim',
      'egitim.gunluk_rapor',
      'st.egitim',
      'st.egitim.gunluk_rapor',
    ]);
  }

  bool isEnabledForSchoolType(String? schoolTypeId) {
    if (!enabled) return false;
    if (_isModuleOrParentDisabled(globalDisabledKeys)) return false;

    final st = (schoolTypeId ?? '').trim();
    if (st.isNotEmpty) {
      final stDisabled = schoolTypeDisabledModules[st] ?? const [];
      if (_isModuleOrParentDisabled(stDisabled)) return false;
      if (enabledSchoolTypeIds.isNotEmpty &&
          !enabledSchoolTypeIds.contains(st)) {
        return false;
      }
    }
    return true;
  }

  /// Belirli bir okul türü için hem kurum geneli hem de okul türüne özel
  /// 3. seviye karne bölümü aç/kapa tercihlerini birleştirerek efektif ayar döner.
  DailyReportConfigModel forSchoolType(String? schoolTypeId) {
    final st = (schoolTypeId ?? '').trim();
    final combined = <String>{
      ...globalDisabledKeys,
      if (st.isNotEmpty) ...(schoolTypeDisabledModules[st] ?? const []),
    };

    return copyWith(
      enabled: isEnabledForSchoolType(st),
      trackMeals:
          trackMeals && !_isChildSectionDisabled(combined, 'gunluk_rapor_beslenme'),
      trackWater:
          trackWater && !_isChildSectionDisabled(combined, 'gunluk_rapor_su'),
      trackSleep:
          trackSleep && !_isChildSectionDisabled(combined, 'gunluk_rapor_uyku'),
      trackMood:
          trackMood && !_isChildSectionDisabled(combined, 'gunluk_rapor_duygu'),
      trackActivities: trackActivities &&
          !_isChildSectionDisabled(combined, 'gunluk_rapor_etkinlik'),
      trackSelfCare: trackSelfCare &&
          !_isChildSectionDisabled(combined, 'gunluk_rapor_ozbakim'),
      trackHealthNote: trackHealthNote &&
          !_isChildSectionDisabled(combined, 'gunluk_rapor_saglik'),
      allowParentFeedback: allowParentFeedback &&
          !_isChildSectionDisabled(combined, 'gunluk_rapor_veli_geri_bildirim'),
    );
  }

  DailyReportConfigModel copyWith({
    bool? enabled,
    List<String>? enabledSchoolTypeIds,
    bool? trackMood,
    bool? trackMeals,
    bool? trackWater,
    bool? trackSleep,
    bool? trackActivities,
    bool? trackSelfCare,
    bool? trackHealthNote,
    bool? allowParentFeedback,
    List<String>? globalDisabledKeys,
    Map<String, List<String>>? schoolTypeDisabledModules,
  }) {
    return DailyReportConfigModel(
      enabled: enabled ?? this.enabled,
      enabledSchoolTypeIds: enabledSchoolTypeIds ?? this.enabledSchoolTypeIds,
      trackMood: trackMood ?? this.trackMood,
      trackMeals: trackMeals ?? this.trackMeals,
      trackWater: trackWater ?? this.trackWater,
      trackSleep: trackSleep ?? this.trackSleep,
      trackActivities: trackActivities ?? this.trackActivities,
      trackSelfCare: trackSelfCare ?? this.trackSelfCare,
      trackHealthNote: trackHealthNote ?? this.trackHealthNote,
      allowParentFeedback: allowParentFeedback ?? this.allowParentFeedback,
      globalDisabledKeys: globalDisabledKeys ?? this.globalDisabledKeys,
      schoolTypeDisabledModules:
          schoolTypeDisabledModules ?? this.schoolTypeDisabledModules,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'enabledSchoolTypeIds': enabledSchoolTypeIds,
      'trackMood': trackMood,
      'trackMeals': trackMeals,
      'trackWater': trackWater,
      'trackSleep': trackSleep,
      'trackActivities': trackActivities,
      'trackSelfCare': trackSelfCare,
      'trackHealthNote': trackHealthNote,
      'allowParentFeedback': allowParentFeedback,
    };
  }

  factory DailyReportConfigModel.fromMap(
    Map<String, dynamic>? map, {
    List<dynamic>? appDisabledModules,
    Map<String, dynamic>? schoolTypeDisabledModules,
  }) {
    final globalKeys = (appDisabledModules ?? const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final stMap = <String, List<String>>{};
    if (schoolTypeDisabledModules != null) {
      schoolTypeDisabledModules.forEach((stId, rawList) {
        if (rawList is Iterable) {
          stMap[stId.toString()] = rawList
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      });
    }

    final globallyDisabled = _isModuleOrParentDisabled(globalKeys);

    if (map == null) {
      return DailyReportConfigModel(
        enabled: !globallyDisabled,
        trackMeals:
            !_isChildSectionDisabled(globalKeys, 'gunluk_rapor_beslenme'),
        trackWater: !_isChildSectionDisabled(globalKeys, 'gunluk_rapor_su'),
        trackSleep: !_isChildSectionDisabled(globalKeys, 'gunluk_rapor_uyku'),
        trackMood: !_isChildSectionDisabled(globalKeys, 'gunluk_rapor_duygu'),
        trackActivities:
            !_isChildSectionDisabled(globalKeys, 'gunluk_rapor_etkinlik'),
        trackSelfCare:
            !_isChildSectionDisabled(globalKeys, 'gunluk_rapor_ozbakim'),
        trackHealthNote:
            !_isChildSectionDisabled(globalKeys, 'gunluk_rapor_saglik'),
        allowParentFeedback: !_isChildSectionDisabled(
          globalKeys,
          'gunluk_rapor_veli_geri_bildirim',
        ),
        globalDisabledKeys: globalKeys,
        schoolTypeDisabledModules: stMap,
      );
    }

    final rawEnabled = map['enabled'] != false;
    return DailyReportConfigModel(
      enabled: !globallyDisabled && rawEnabled,
      enabledSchoolTypeIds: (map['enabledSchoolTypeIds'] as List<dynamic>? ??
              const [])
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      trackMood: map['trackMood'] != false &&
          !_isChildSectionDisabled(globalKeys, 'gunluk_rapor_duygu'),
      trackMeals: map['trackMeals'] != false &&
          !_isChildSectionDisabled(globalKeys, 'gunluk_rapor_beslenme'),
      trackWater: map['trackWater'] != false &&
          !_isChildSectionDisabled(globalKeys, 'gunluk_rapor_su'),
      trackSleep: map['trackSleep'] != false &&
          !_isChildSectionDisabled(globalKeys, 'gunluk_rapor_uyku'),
      trackActivities: map['trackActivities'] != false &&
          !_isChildSectionDisabled(globalKeys, 'gunluk_rapor_etkinlik'),
      trackSelfCare: map['trackSelfCare'] != false &&
          !_isChildSectionDisabled(globalKeys, 'gunluk_rapor_ozbakim'),
      trackHealthNote: map['trackHealthNote'] != false &&
          !_isChildSectionDisabled(globalKeys, 'gunluk_rapor_saglik'),
      allowParentFeedback: map['allowParentFeedback'] != false &&
          !_isChildSectionDisabled(
            globalKeys,
            'gunluk_rapor_veli_geri_bildirim',
          ),
      globalDisabledKeys: globalKeys,
      schoolTypeDisabledModules: stMap,
    );
  }
}

/// Öğün Tüketim Modeli (Sabah Kahvaltısı, Öğle Yemeği, İkindi Kahvaltısı)
class MealEntryModel {
  /// 'unset' | 'full' | 'half' | 'little' | 'none' | 'na'
  final String status;
  final String menuOrNote;

  const MealEntryModel({
    this.status = 'unset',
    this.menuOrNote = '',
  });

  bool get hasValue => status.isNotEmpty && status != 'unset';

  MealEntryModel copyWith({
    String? status,
    String? menuOrNote,
  }) {
    return MealEntryModel(
      status: status ?? this.status,
      menuOrNote: menuOrNote ?? this.menuOrNote,
    );
  }

  Map<String, dynamic> toMap() => {
        'status': status,
        'menuOrNote': menuOrNote.trim(),
      };

  factory MealEntryModel.fromMap(dynamic raw) {
    if (raw is! Map) return const MealEntryModel();
    return MealEntryModel(
      status: (raw['status'] ?? 'unset').toString(),
      menuOrNote: (raw['menuOrNote'] ?? '').toString(),
    );
  }
}

/// Uyku & Dinlenme Takibi Modeli
class SleepEntryModel {
  /// 'unset' | 'slept' | 'rested' | 'awake' | 'na'
  final String status;
  final String durationOrRange; // ör. "13:00 - 14:30" veya "1.5 Saat"
  final String quality; // 'peaceful' | 'normal' | 'light' | ''
  final String note;

  const SleepEntryModel({
    this.status = 'unset',
    this.durationOrRange = '',
    this.quality = '',
    this.note = '',
  });

  bool get hasValue => status.isNotEmpty && status != 'unset';

  SleepEntryModel copyWith({
    String? status,
    String? durationOrRange,
    String? quality,
    String? note,
  }) {
    return SleepEntryModel(
      status: status ?? this.status,
      durationOrRange: durationOrRange ?? this.durationOrRange,
      quality: quality ?? this.quality,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toMap() => {
        'status': status,
        'durationOrRange': durationOrRange.trim(),
        'quality': quality,
        'note': note.trim(),
      };

  factory SleepEntryModel.fromMap(dynamic raw) {
    if (raw is! Map) return const SleepEntryModel();
    return SleepEntryModel(
      status: (raw['status'] ?? 'unset').toString(),
      durationOrRange: (raw['durationOrRange'] ?? '').toString(),
      quality: (raw['quality'] ?? '').toString(),
      note: (raw['note'] ?? '').toString(),
    );
  }
}

/// Günlük Etkinlik, Branş Dersi, Kitap Okuma ve Gezi Akışı Öğesi
class DailyActivityItemModel {
  final String id;

  /// 'book' | 'english' | 'trip' | 'art' | 'music' | 'drama' | 'science' | 'sport' | 'literacy' | 'other'
  final String category;
  final String title;
  final String description;
  final String timeLabel;

  /// 'enthusiastic' | 'participated' | 'observed' | 'supported'
  final String participation;
  final String photoUrl;
  final String teacherName;
  final DateTime createdAt;

  const DailyActivityItemModel({
    required this.id,
    required this.category,
    required this.title,
    this.description = '',
    this.timeLabel = '',
    this.participation = 'enthusiastic',
    this.photoUrl = '',
    this.teacherName = '',
    required this.createdAt,
  });

  DailyActivityItemModel copyWith({
    String? id,
    String? category,
    String? title,
    String? description,
    String? timeLabel,
    String? participation,
    String? photoUrl,
    String? teacherName,
    DateTime? createdAt,
  }) {
    return DailyActivityItemModel(
      id: id ?? this.id,
      category: category ?? this.category,
      title: title ?? this.title,
      description: description ?? this.description,
      timeLabel: timeLabel ?? this.timeLabel,
      participation: participation ?? this.participation,
      photoUrl: photoUrl ?? this.photoUrl,
      teacherName: teacherName ?? this.teacherName,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'category': category,
        'title': title.trim(),
        'description': description.trim(),
        'timeLabel': timeLabel.trim(),
        'participation': participation,
        'photoUrl': photoUrl.trim(),
        'teacherName': teacherName.trim(),
        'createdAt': Timestamp.fromDate(createdAt),
      };

  factory DailyActivityItemModel.fromMap(dynamic raw) {
    if (raw is! Map) {
      return DailyActivityItemModel(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        category: 'other',
        title: 'Etkinlik',
        createdAt: DateTime.now(),
      );
    }
    DateTime dt = DateTime.now();
    final c = raw['createdAt'];
    if (c is Timestamp) {
      dt = c.toDate();
    } else if (c is String) {
      dt = DateTime.tryParse(c) ?? DateTime.now();
    }
    return DailyActivityItemModel(
      id: (raw['id'] ?? dt.microsecondsSinceEpoch.toString()).toString(),
      category: (raw['category'] ?? 'other').toString(),
      title: (raw['title'] ?? 'Etkinlik').toString(),
      description: (raw['description'] ?? '').toString(),
      timeLabel: (raw['timeLabel'] ?? '').toString(),
      participation: (raw['participation'] ?? 'enthusiastic').toString(),
      photoUrl: (raw['photoUrl'] ?? '').toString(),
      teacherName: (raw['teacherName'] ?? '').toString(),
      createdAt: dt,
    );
  }
}

/// Öğrenci Günlük Karne / Günlük Rapor Modeli (`${dateKey}_${studentId}`)
class DailyReportModel {
  final String id;
  final String institutionId;
  final String schoolDocId;
  final String schoolTypeId;
  final String schoolTypeName;
  final String classId;
  final String className;
  final String classLevel;
  final String studentId;
  final String studentName;
  final String studentNo;
  final String dateKey; // yyyy-MM-dd

  /// Ruh Hali: 'happy' | 'calm' | 'energetic' | 'shy' | 'tired' | 'fussy' | ''
  final String mood;

  /// Sosyal Uyum: 'great' | 'good' | 'individual' | 'supported' | ''
  final String socialHarmony;

  /// Öğünler
  final MealEntryModel breakfast;
  final MealEntryModel lunch;
  final MealEntryModel snack;

  /// Su tüketimi: 'good' | 'medium' | 'low' | ''
  final String waterIntake;

  /// Uyku & Dinlenme
  final SleepEntryModel sleep;

  /// Günlük Etkinlik / Ders / Kitap / Gezi Akışı
  final List<DailyActivityItemModel> activities;

  /// Özbakım etiketleri ("El Yıkama & Hijyen Tam", "Tuvalet Bağımsız" vb.)
  final List<String> selfCareTags;

  /// Sağlık / İlaç / Özel Gözlem Notu
  final String healthNote;

  /// Veliye ihtiyaç / hatırlatma etiketleri ("Yedek Kıyafet", "Islak Mendil" vb.)
  final List<String> neededItems;

  /// Öğretmen Gün Sonu Özel Notu
  final String teacherNote;

  /// Veli Görüntüleme & Geri Bildirim
  final bool isPublished;
  final DateTime? parentSeenAt;
  final String parentReaction;
  final String parentFeedbackNote;
  final DateTime? parentFeedbackAt;

  /// Kayıt / Güncelleme İzleme
  final DateTime updatedAt;
  final String updatedByUid;
  final String updatedByName;
  final List<String> contributors;

  const DailyReportModel({
    required this.id,
    required this.institutionId,
    required this.schoolDocId,
    this.schoolTypeId = '',
    this.schoolTypeName = '',
    required this.classId,
    required this.className,
    this.classLevel = '',
    required this.studentId,
    required this.studentName,
    this.studentNo = '',
    required this.dateKey,
    this.mood = '',
    this.socialHarmony = '',
    this.breakfast = const MealEntryModel(),
    this.lunch = const MealEntryModel(),
    this.snack = const MealEntryModel(),
    this.waterIntake = '',
    this.sleep = const SleepEntryModel(),
    this.activities = const [],
    this.selfCareTags = const [],
    this.healthNote = '',
    this.neededItems = const [],
    this.teacherNote = '',
    this.isPublished = true,
    this.parentSeenAt,
    this.parentReaction = '',
    this.parentFeedbackNote = '',
    this.parentFeedbackAt,
    required this.updatedAt,
    this.updatedByUid = '',
    this.updatedByName = '',
    this.contributors = const [],
  });

  static String buildDocId(String dateKey, String studentId) =>
      '${dateKey.trim()}_${studentId.trim()}';

  bool get hasAnyContent =>
      mood.isNotEmpty ||
      socialHarmony.isNotEmpty ||
      breakfast.hasValue ||
      lunch.hasValue ||
      snack.hasValue ||
      waterIntake.isNotEmpty ||
      sleep.hasValue ||
      activities.isNotEmpty ||
      selfCareTags.isNotEmpty ||
      healthNote.trim().isNotEmpty ||
      neededItems.isNotEmpty ||
      teacherNote.trim().isNotEmpty;

  DailyReportModel copyWith({
    String? id,
    String? institutionId,
    String? schoolDocId,
    String? schoolTypeId,
    String? schoolTypeName,
    String? classId,
    String? className,
    String? classLevel,
    String? studentId,
    String? studentName,
    String? studentNo,
    String? dateKey,
    String? mood,
    String? socialHarmony,
    MealEntryModel? breakfast,
    MealEntryModel? lunch,
    MealEntryModel? snack,
    String? waterIntake,
    SleepEntryModel? sleep,
    List<DailyActivityItemModel>? activities,
    List<String>? selfCareTags,
    String? healthNote,
    List<String>? neededItems,
    String? teacherNote,
    bool? isPublished,
    DateTime? parentSeenAt,
    String? parentReaction,
    String? parentFeedbackNote,
    DateTime? parentFeedbackAt,
    DateTime? updatedAt,
    String? updatedByUid,
    String? updatedByName,
    List<String>? contributors,
  }) {
    return DailyReportModel(
      id: id ?? this.id,
      institutionId: institutionId ?? this.institutionId,
      schoolDocId: schoolDocId ?? this.schoolDocId,
      schoolTypeId: schoolTypeId ?? this.schoolTypeId,
      schoolTypeName: schoolTypeName ?? this.schoolTypeName,
      classId: classId ?? this.classId,
      className: className ?? this.className,
      classLevel: classLevel ?? this.classLevel,
      studentId: studentId ?? this.studentId,
      studentName: studentName ?? this.studentName,
      studentNo: studentNo ?? this.studentNo,
      dateKey: dateKey ?? this.dateKey,
      mood: mood ?? this.mood,
      socialHarmony: socialHarmony ?? this.socialHarmony,
      breakfast: breakfast ?? this.breakfast,
      lunch: lunch ?? this.lunch,
      snack: snack ?? this.snack,
      waterIntake: waterIntake ?? this.waterIntake,
      sleep: sleep ?? this.sleep,
      activities: activities ?? this.activities,
      selfCareTags: selfCareTags ?? this.selfCareTags,
      healthNote: healthNote ?? this.healthNote,
      neededItems: neededItems ?? this.neededItems,
      teacherNote: teacherNote ?? this.teacherNote,
      isPublished: isPublished ?? this.isPublished,
      parentSeenAt: parentSeenAt ?? this.parentSeenAt,
      parentReaction: parentReaction ?? this.parentReaction,
      parentFeedbackNote: parentFeedbackNote ?? this.parentFeedbackNote,
      parentFeedbackAt: parentFeedbackAt ?? this.parentFeedbackAt,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByUid: updatedByUid ?? this.updatedByUid,
      updatedByName: updatedByName ?? this.updatedByName,
      contributors: contributors ?? this.contributors,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'schoolDocId': schoolDocId,
      'schoolTypeId': schoolTypeId,
      'schoolTypeName': schoolTypeName,
      'classId': classId,
      'className': className,
      'classLevel': classLevel,
      'studentId': studentId,
      'studentName': studentName,
      'studentNo': studentNo,
      'dateKey': dateKey,
      'mood': mood,
      'socialHarmony': socialHarmony,
      'breakfast': breakfast.toMap(),
      'lunch': lunch.toMap(),
      'snack': snack.toMap(),
      'waterIntake': waterIntake,
      'sleep': sleep.toMap(),
      'activities': activities.map((a) => a.toMap()).toList(),
      'selfCareTags': selfCareTags,
      'healthNote': healthNote.trim(),
      'neededItems': neededItems,
      'teacherNote': teacherNote.trim(),
      'isPublished': isPublished,
      if (parentSeenAt != null)
        'parentSeenAt': Timestamp.fromDate(parentSeenAt!),
      'parentReaction': parentReaction,
      'parentFeedbackNote': parentFeedbackNote.trim(),
      if (parentFeedbackAt != null)
        'parentFeedbackAt': Timestamp.fromDate(parentFeedbackAt!),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'updatedByUid': updatedByUid,
      'updatedByName': updatedByName,
      'contributors': contributors,
    };
  }

  factory DailyReportModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return DailyReportModel.fromMap(data, id: doc.id);
  }

  factory DailyReportModel.fromMap(
    Map<String, dynamic> data, {
    String? id,
  }) {
    DateTime? parseTs(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    final rawActivities = data['activities'] as List<dynamic>? ?? const [];
    final activities = rawActivities
        .map((e) => DailyActivityItemModel.fromMap(e))
        .toList();

    final dateKey = (data['dateKey'] ?? '').toString();
    final studentId = (data['studentId'] ?? '').toString();

    return DailyReportModel(
      id: id ?? buildDocId(dateKey, studentId),
      institutionId: (data['institutionId'] ?? '').toString(),
      schoolDocId: (data['schoolDocId'] ?? '').toString(),
      schoolTypeId: (data['schoolTypeId'] ?? '').toString(),
      schoolTypeName: (data['schoolTypeName'] ?? '').toString(),
      classId: (data['classId'] ?? '').toString(),
      className: (data['className'] ?? '').toString(),
      classLevel: (data['classLevel'] ?? '').toString(),
      studentId: studentId,
      studentName: (data['studentName'] ?? '').toString(),
      studentNo: (data['studentNo'] ?? '').toString(),
      dateKey: dateKey,
      mood: (data['mood'] ?? '').toString(),
      socialHarmony: (data['socialHarmony'] ?? '').toString(),
      breakfast: MealEntryModel.fromMap(data['breakfast']),
      lunch: MealEntryModel.fromMap(data['lunch']),
      snack: MealEntryModel.fromMap(data['snack']),
      waterIntake: (data['waterIntake'] ?? '').toString(),
      sleep: SleepEntryModel.fromMap(data['sleep']),
      activities: activities,
      selfCareTags: (data['selfCareTags'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList(),
      healthNote: (data['healthNote'] ?? '').toString(),
      neededItems: (data['neededItems'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList(),
      teacherNote: (data['teacherNote'] ?? '').toString(),
      isPublished: data['isPublished'] != false,
      parentSeenAt: parseTs(data['parentSeenAt']),
      parentReaction: (data['parentReaction'] ?? '').toString(),
      parentFeedbackNote: (data['parentFeedbackNote'] ?? '').toString(),
      parentFeedbackAt: parseTs(data['parentFeedbackAt']),
      updatedAt: parseTs(data['updatedAt']) ?? DateTime.now(),
      updatedByUid: (data['updatedByUid'] ?? '').toString(),
      updatedByName: (data['updatedByName'] ?? '').toString(),
      contributors: (data['contributors'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList(),
    );
  }
}

/// Günlük Karne Sabit Katalogları, İkonları, Renkleri ve Hazır Şablonları
class DailyReportCatalog {
  static const List<({String key, String label, String emoji, Color color})>
      moods = [
    (
      key: 'happy',
      label: 'Neşeli & Mutlu',
      emoji: '😄',
      color: Color(0xFF10B981),
    ),
    (
      key: 'energetic',
      label: 'Çok Enerjik',
      emoji: '🤩',
      color: Color(0xFFF59E0B),
    ),
    (
      key: 'calm',
      label: 'Sakin & Huzurlu',
      emoji: '🙂',
      color: Color(0xFF3B82F6),
    ),
    (
      key: 'shy',
      label: 'Çekingen',
      emoji: '☺️',
      color: Color(0xFF8B5CF6),
    ),
    (
      key: 'tired',
      label: 'Yorgun / Uykulu',
      emoji: '😴',
      color: Color(0xFF64748B),
    ),
    (
      key: 'fussy',
      label: 'Huzursuz / Duygusal',
      emoji: '🥺',
      color: Color(0xFFEF4444),
    ),
  ];

  static const List<({String key, String label, IconData icon, Color color})>
      socialHarmonyOptions = [
    (
      key: 'great',
      label: 'Uyumlu & Paylaşımcı',
      icon: Icons.favorite_rounded,
      color: Color(0xFF10B981),
    ),
    (
      key: 'good',
      label: 'Grup Oyununa Katıldı',
      icon: Icons.groups_rounded,
      color: Color(0xFF3B82F6),
    ),
    (
      key: 'individual',
      label: 'Bireysel Oynadı',
      icon: Icons.person_rounded,
      color: Color(0xFFF59E0B),
    ),
    (
      key: 'supported',
      label: 'Rehberlikle Desteklendi',
      icon: Icons.volunteer_activism_rounded,
      color: Color(0xFF8B5CF6),
    ),
  ];

  static const List<
      ({
        String key,
        String label,
        String shortLabel,
        IconData icon,
        Color color,
      })> mealStatuses = [
    (
      key: 'full',
      label: 'Hepsini Yedi',
      shortLabel: 'Tam Yedi',
      icon: Icons.sentiment_very_satisfied_rounded,
      color: Color(0xFF10B981),
    ),
    (
      key: 'half',
      label: 'Yarısını Yedi',
      shortLabel: 'Yarım',
      icon: Icons.sentiment_satisfied_rounded,
      color: Color(0xFF3B82F6),
    ),
    (
      key: 'little',
      label: 'Az Yaptı / Yedi',
      shortLabel: 'Az Yaptı',
      icon: Icons.pie_chart_outline_rounded,
      color: Color(0xFFF59E0B),
    ),
    (
      key: 'none',
      label: 'Yemedi / Yapmadı',
      shortLabel: 'Yapmadı',
      icon: Icons.highlight_off_rounded,
      color: Color(0xFFEF4444),
    ),
    (
      key: 'na',
      label: 'Öğün Yok / Katılmadı',
      shortLabel: 'Yok',
      icon: Icons.remove_circle_outline_rounded,
      color: Color(0xFF94A3B8),
    ),
  ];

  static const List<({String key, String label, String emoji, Color color})>
      waterOptions = [
    (
      key: 'good',
      label: 'Bol Su İçti',
      emoji: '💧💧💧',
      color: Color(0xFF0EA5E9),
    ),
    (
      key: 'medium',
      label: 'Normal İçti',
      emoji: '💧💧',
      color: Color(0xFF3B82F6),
    ),
    (
      key: 'low',
      label: 'Az İçti (Teşvik Edildi)',
      emoji: '💧',
      color: Color(0xFFF59E0B),
    ),
  ];

  static const List<
      ({
        String key,
        String label,
        String shortLabel,
        IconData icon,
        Color color,
      })> sleepStatuses = [
    (
      key: 'slept',
      label: 'Uyudu',
      shortLabel: 'Uyudu',
      icon: Icons.bedtime_rounded,
      color: Color(0xFF6366F1),
    ),
    (
      key: 'rested',
      label: 'Dinlendi (Uyumadı)',
      shortLabel: 'Dinlendi',
      icon: Icons.airline_seat_flat_rounded,
      color: Color(0xFF0EA5E9),
    ),
    (
      key: 'awake',
      label: 'Uyumadı',
      shortLabel: 'Uyumadı',
      icon: Icons.wb_sunny_rounded,
      color: Color(0xFFF59E0B),
    ),
    (
      key: 'na',
      label: 'Uyku Saati Yok',
      shortLabel: 'Yok',
      icon: Icons.block_rounded,
      color: Color(0xFF94A3B8),
    ),
  ];

  static const List<String> sleepDurationPresets = [
    '30 Dakika',
    '45 Dakika',
    '1 Saat',
    '1.5 Saat',
    '2 Saat',
    '12:30 - 14:00',
    '13:00 - 14:30',
  ];

  static const List<
      ({
        String key,
        String title,
        String emoji,
        IconData icon,
        Color color,
        String hint,
      })> activityCategories = [
    (
      key: 'book',
      title: 'Kitap Okuma & Masal',
      emoji: '📚',
      icon: Icons.menu_book_rounded,
      color: Color(0xFF8B5CF6),
      hint: 'Örn: Aç Tırtıl hikayesi okundu, karakterler üzerine sohbet edildi.',
    ),
    (
      key: 'english',
      title: 'İngilizce Dersi',
      emoji: '🇬🇧',
      icon: Icons.translate_rounded,
      color: Color(0xFF2563EB),
      hint: 'Örn: Renkler ve hayvanlar şarkılarla tekrar edildi.',
    ),
    (
      key: 'art',
      title: 'Sanat & El Becerisi',
      emoji: '🎨',
      icon: Icons.palette_rounded,
      color: Color(0xFFEC4899),
      hint: 'Örn: Parmak boyası ile mevsim ağacı kolajı yapıldı.',
    ),
    (
      key: 'trip',
      title: 'Gezi & Doğa Gözlemi',
      emoji: '🚌',
      icon: Icons.directions_bus_filled_rounded,
      color: Color(0xFF10B981),
      hint: 'Örn: Doğa müzesi / okul bahçesi bitki inceleme gezisi yapıldı.',
    ),
    (
      key: 'music',
      title: 'Müzik & Ritim',
      emoji: '🎵',
      icon: Icons.music_note_rounded,
      color: Color(0xFFF59E0B),
      hint: 'Örn: Orff çalgılarıyla ritim tutma ve çocuk şarkıları çalışıldı.',
    ),
    (
      key: 'drama',
      title: 'Drama & Oyun',
      emoji: '🎭',
      icon: Icons.theater_comedy_rounded,
      color: Color(0xFFF97316),
      hint: 'Örn: Meslekler yaratıcı drama canlandırması ve halka oyunu.',
    ),
    (
      key: 'science',
      title: 'Bilim, Kodlama & Akıl Oyunları',
      emoji: '🧩',
      icon: Icons.extension_rounded,
      color: Color(0xFF0D9488),
      hint: 'Örn: Su-yağ yoğunluk deneyi ve eşleştirme akıl oyunu yapıldı.',
    ),
    (
      key: 'sport',
      title: 'Cimnastik & Bahçe Oyunu',
      emoji: '🤸',
      icon: Icons.sports_gymnastics_rounded,
      color: Color(0xFF16A34A),
      hint: 'Örn: Denge parkuru, top yakalama ve açık hava egzersizi yapıldı.',
    ),
    (
      key: 'literacy',
      title: 'Okuma-Yazmaya Hazırlık & Matematik',
      emoji: '🔢',
      icon: Icons.calculate_rounded,
      color: Color(0xFF4F46E5),
      hint: 'Örn: Çizgi tamamlama ve 1-10 arası nesne sayma çalışması yapıldı.',
    ),
    (
      key: 'other',
      title: 'Diğer Ders / Etkinlik',
      emoji: '✨',
      icon: Icons.auto_awesome_rounded,
      color: Color(0xFF64748B),
      hint: 'Yapılan etkinliği kısaca açıklayınız...',
    ),
  ];

  static const List<({String key, String label, Color color})>
      participationLevels = [
    (
      key: 'enthusiastic',
      label: 'İstekle & Aktif Katıldı 🌟',
      color: Color(0xFF10B981),
    ),
    (
      key: 'participated',
      label: 'Katıldı 👍',
      color: Color(0xFF3B82F6),
    ),
    (
      key: 'observed',
      label: 'Gözlemledi 👀',
      color: Color(0xFFF59E0B),
    ),
    (
      key: 'supported',
      label: 'Destekle Katıldı 🤝',
      color: Color(0xFF8B5CF6),
    ),
  ];

  static const List<String> selfCarePresets = [
    'El Yıkama & Hijyen Tam ✨',
    'Diş Fırçalama Yapıldı 🪥',
    'Tuvalet İhtiyacı Bağımsız 👍',
    'Tuvalet Eğitiminde Desteklendi 🤲',
    'Yedek Kıyafet Değiştirildi 👕',
    'Terlediği İçin Üstü Değiştirildi 🧥',
  ];

  static const List<String> neededItemPresets = [
    'Yedek Kıyafet Gönderiniz 👕',
    'Islak Mendil / Peçete İhtiyacı 🧻',
    'Suluk Gönderilmeli 💧',
    'Panduf / Okul Ayakkabısı 👟',
    'Boyama Önlüğü 🎨',
    'Yarın Gezi / Etkinlik Günü 🚌',
  ];

  static ({String key, String label, String emoji, Color color})? moodMeta(
    String key,
  ) {
    for (final m in moods) {
      if (m.key == key) return m;
    }
    return null;
  }

  static ({
    String key,
    String label,
    String shortLabel,
    IconData icon,
    Color color,
  })? mealMeta(String status) {
    for (final m in mealStatuses) {
      if (m.key == status) return m;
    }
    return null;
  }

  static ({
    String key,
    String label,
    String shortLabel,
    IconData icon,
    Color color,
  })? sleepMeta(String status) {
    for (final s in sleepStatuses) {
      if (s.key == status) return s;
    }
    return null;
  }

  static ({
    String key,
    String title,
    String emoji,
    IconData icon,
    Color color,
    String hint,
  }) activityMeta(String category) {
    for (final c in activityCategories) {
      if (c.key == category) return c;
    }
    return activityCategories.last;
  }

  static ({String key, String label, Color color}) participationMeta(
    String key,
  ) {
    for (final p in participationLevels) {
      if (p.key == key) return p;
    }
    return participationLevels.first;
  }
}

