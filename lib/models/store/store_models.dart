import 'package:cloud_firestore/cloud_firestore.dart';

/// Mağaza ürün kategorileri.
class StoreCategories {
  static const String booksAndSets = 'Kitap & Eğitim Seti';
  static const String examsAndDigital = 'Deneme & Dijital Paket';
  static const String uniform = 'Okul Kıyafeti / Forma';
  static const String stationery = 'Kırtasiye & Materyal';
  static const String eventsAndOther = 'Etkinlik & Diğer';

  static const List<String> all = [
    booksAndSets,
    examsAndDigital,
    uniform,
    stationery,
    eventsAndOther,
  ];
}

/// Mağaza hedef alıcı rolleri.
class StoreBuyerRoles {
  static const String idareci = 'idareci';
  static const String ogretmen = 'ogretmen';
  static const String veli = 'veli';
  static const String ogrenci = 'ogrenci';

  static const List<String> all = [idareci, ogretmen, veli, ogrenci];

  static String labelOf(String role) {
    switch (normalize(role)) {
      case idareci:
        return 'İdareci';
      case ogretmen:
        return 'Öğretmen';
      case veli:
        return 'Veli';
      case ogrenci:
        return 'Öğrenci';
      default:
        return role;
    }
  }

  static String normalize(String raw) {
    final lower = raw.trim().toLowerCase();
    if (lower == 'idareci' ||
        lower == 'admin' ||
        lower == 'manager' ||
        lower == 'mudur' ||
        lower == 'müdür' ||
        lower == 'mudur_yardimcisi' ||
        lower == 'genel_mudur' ||
        lower == 'kurum_yoneticisi' ||
        lower == 'kurum_muduru') {
      return idareci;
    }
    if (lower == 'ogretmen' ||
        lower == 'öğretmen' ||
        lower == 'teacher' ||
        lower == 'rehber_ogretmen') {
      return ogretmen;
    }
    if (lower == 'veli' || lower == 'parent' || lower == 'guardian') {
      return veli;
    }
    if (lower == 'ogrenci' || lower == 'öğrenci' || lower == 'student') {
      return ogrenci;
    }
    return idareci;
  }
}

/// Standart okul türü kategorileri.
class StoreSchoolTypeCategories {
  static const String anaokulu = 'Anaokulu';
  static const String ilkokul = 'İlkokul';
  static const String ortaokul = 'Ortaokul';
  static const String lise = 'Lise';

  static const List<String> all = [anaokulu, ilkokul, ortaokul, lise];

  static String? normalize(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final lower = raw
        .trim()
        .toLowerCase()
        .replaceAll('İ', 'i')
        .replaceAll('ı', 'i');
    if (lower.contains('anaokul') ||
        lower.contains('anasinif') ||
        lower.contains('anasınıf') ||
        lower.contains('kres') ||
        lower.contains('kreş')) {
      return anaokulu;
    }
    if (lower.contains('ilkokul')) {
      return ilkokul;
    }
    if (lower.contains('ortaokul')) {
      return ortaokul;
    }
    if (lower.contains('lise')) {
      return lise;
    }
    return raw.trim();
  }
}

/// Standart sınıf seviyeleri ve şube çözümleme yardımcıları.
class StoreClassLevels {
  static const String anaokulu = 'Anaokulu';
  static const String hazirlik = 'Hazırlık';
  static const String mezun = 'Mezun';

  static const List<String> ilkokulGrades = ['1', '2', '3', '4'];
  static const List<String> ortaokulGrades = ['5', '6', '7', '8'];
  static const List<String> liseGrades = ['Hazırlık', '9', '10', '11', '12'];

  static const List<String> all = [
    anaokulu,
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    hazirlik,
    '9',
    '10',
    '11',
    '12',
    mezun,
  ];

  static String labelOf(String level) {
    final norm = normalize(level) ?? level.trim();
    if (norm == anaokulu || norm == hazirlik || norm == mezun) {
      return norm;
    }
    if (int.tryParse(norm) != null) {
      return '$norm. Sınıf';
    }
    return norm;
  }

  static String? normalize(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed
        .toLowerCase()
        .replaceAll('İ', 'i')
        .replaceAll('ı', 'i');

    if (lower.contains('anaokul') ||
        lower.contains('anasinif') ||
        lower.contains('anasınıf') ||
        lower.contains('kres') ||
        lower.contains('kreş') ||
        lower.contains('yaş') ||
        lower.contains('yas')) {
      return anaokulu;
    }
    if (lower.contains('hazirlik') || lower.contains('hazırlık')) {
      return hazirlik;
    }
    if (lower.contains('mezun')) {
      return mezun;
    }

    final exactInt = int.tryParse(trimmed);
    if (exactInt != null && exactInt >= 1 && exactInt <= 12) {
      return '$exactInt';
    }

    final match = RegExp(r'^(\d{1,2})\b').firstMatch(trimmed);
    if (match != null) {
      final n = int.tryParse(match.group(1)!);
      if (n != null && n >= 1 && n <= 12) {
        return '$n';
      }
    }
    return trimmed;
  }

  /// Öğrenci veya sınıf kaydından kanonik sınıf seviyesini çıkarır.
  /// Anaokulu yaş gruplarını (`5 Yaş A`) ortaokul `5. Sınıf` ile karıştırmaz.
  static String? extractLevel({
    dynamic rawLevel,
    String? className,
    String? schoolTypeName,
    String? schoolTypeCategory,
  }) {
    final stCat = StoreSchoolTypeCategories.normalize(
      schoolTypeCategory?.trim().isNotEmpty == true
          ? schoolTypeCategory
          : schoolTypeName,
    );
    if (stCat == StoreSchoolTypeCategories.anaokulu) {
      return anaokulu;
    }

    final cName = (className ?? '').trim();
    final cLower = cName
        .toLowerCase()
        .replaceAll('İ', 'i')
        .replaceAll('ı', 'i');
    if (cLower.contains('yaş') ||
        cLower.contains('yas') ||
        cLower.contains('anaokul') ||
        cLower.contains('anasinif') ||
        cLower.contains('kres') ||
        cLower.contains('kreş')) {
      return anaokulu;
    }

    if (rawLevel != null) {
      final fromRaw = normalize(rawLevel.toString());
      if (fromRaw != null && fromRaw.isNotEmpty) {
        return fromRaw;
      }
    }

    if (cName.isNotEmpty) {
      final fromName = normalize(cName);
      if (fromName != null && all.contains(fromName)) {
        return fromName;
      }
    }
    return null;
  }

  /// Sınıf adından şube kodunu çıkarır (örn. `'5-A'` -> `'A'`, `'12/SAY'` -> `'SAY'`).
  static String? extractBranch({String? explicitBranch, String? className}) {
    if (explicitBranch != null && explicitBranch.trim().isNotEmpty) {
      return normalizeClassToken(explicitBranch);
    }
    final raw = (className ?? '').trim();
    if (raw.isEmpty) return null;
    final sepMatch = RegExp(
      r'^\d{1,2}\s*[-/\s.]+\s*([A-Za-zÇĞİÖŞÜçğıöşü0-9]+)$',
    ).firstMatch(raw);
    if (sepMatch != null) {
      return normalizeClassToken(sepMatch.group(1)!);
    }
    final compactMatch = RegExp(
      r'^\d{1,2}([A-Za-zÇĞİÖŞÜçğıöşü]+)$',
    ).firstMatch(raw);
    if (compactMatch != null) {
      return normalizeClassToken(compactMatch.group(1)!);
    }
    return null;
  }

  /// Sınıf / şube isimlerini karşılaştırma için standartlaştırır (`'5 / a'` -> `'5-A'`).
  static String normalizeClassToken(String raw) {
    var s = raw.trim().replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
    s = s.replaceAll(RegExp(r'\s*[-/]\s*'), '-');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    final m = RegExp(r'^(\d{1,2})\s+([A-ZÇĞİÖŞÜ0-9]+)$').firstMatch(s);
    if (m != null && m.group(2) != 'YAŞ' && m.group(2) != 'SINIF') {
      return '${m.group(1)}-${m.group(2)}';
    }
    final mCompact = RegExp(r'^(\d{1,2})([A-ZÇĞİÖŞÜ]{1,4})$').firstMatch(s);
    if (mCompact != null) {
      return '${mCompact.group(1)}-${mCompact.group(2)}';
    }
    return s;
  }
}

/// Dış görsel URL bağlantılarını temizleyen ve doğrudan gösterilebilir hale getiren yardımcı.
class StoreImageUrlHelper {
  static String normalize(String? raw) {
    if (raw == null) return '';
    var s = raw.trim();
    if (s.length >= 2 &&
        ((s.startsWith('"') && s.endsWith('"')) ||
            (s.startsWith("'") && s.endsWith("'")))) {
      s = s.substring(1, s.length - 1).trim();
    }
    if (s.isEmpty) return '';
    if (s.startsWith('data:image/')) return s;
    if (s.startsWith('//')) {
      s = 'https:$s';
    } else if (!s.startsWith('http://') && !s.startsWith('https://')) {
      if (s.contains('.') && !s.contains(' ')) {
        s = 'https://$s';
      } else {
        return '';
      }
    }

    // Google Drive paylaşım linklerini doğrudan gömülebilir görsel linkine çevir
    final driveFileMatch = RegExp(
      r'drive\.google\.com/file/d/([a-zA-Z0-9_-]+)',
    ).firstMatch(s);
    if (driveFileMatch != null) {
      return 'https://drive.google.com/thumbnail?id=${driveFileMatch.group(1)}&sz=w1200';
    }
    final driveOpenMatch = RegExp(
      r'drive\.google\.com/(?:open|uc)\?.*?id=([a-zA-Z0-9_-]+)',
    ).firstMatch(s);
    if (driveOpenMatch != null) {
      return 'https://drive.google.com/thumbnail?id=${driveOpenMatch.group(1)}&sz=w1200';
    }

    // Dropbox paylaşım linklerini doğrudan ham görsele çevir
    if (s.contains('dropbox.com/') && s.contains('dl=0')) {
      s = s.replaceAll('dl=0', 'raw=1');
    }

    return s;
  }

  static List<String> normalizeList(Iterable<String> urls) {
    final result = <String>[];
    for (final raw in urls) {
      final norm = normalize(raw);
      if (norm.isNotEmpty && !result.contains(norm)) {
        result.add(norm);
      }
    }
    return result;
  }
}

/// Sipariş durum sabitleri.
class StoreOrderStatuses {
  static const String bekliyor = 'bekliyor';
  static const String onaylandi = 'onaylandi';
  static const String hazirlaniyor = 'hazirlaniyor';
  static const String kargoda = 'kargoda';
  static const String teslimEdildi = 'teslim_edildi';
  static const String iptal = 'iptal';

  static const List<String> all = [
    bekliyor,
    onaylandi,
    hazirlaniyor,
    kargoda,
    teslimEdildi,
    iptal,
  ];

  static String labelOf(String status) {
    switch (status) {
      case bekliyor:
        return 'Bekliyor';
      case onaylandi:
        return 'Onaylandı';
      case hazirlaniyor:
        return 'Hazırlanıyor';
      case kargoda:
        return 'Kargoda';
      case teslimEdildi:
        return 'Teslim Edildi';
      case iptal:
        return 'İptal Edildi';
      default:
        return status;
    }
  }
}

DateTime _parseDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

List<String> _parseStringList(dynamic value) {
  if (value is Iterable) {
    return value
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }
  return const [];
}

/// Bir kuruma ait tekil okul türü bilgisi (`schoolTypes` koleksiyonundan).
class StoreSchoolTypeOption {
  final String id;
  final String institutionId;
  final String category; // Anaokulu | İlkokul | Ortaokul | Lise
  final String name;
  final List<String> activeGrades;

  const StoreSchoolTypeOption({
    required this.id,
    required this.institutionId,
    required this.category,
    required this.name,
    this.activeGrades = const [],
  });

  factory StoreSchoolTypeOption.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    final rawType = (data['schoolType'] ?? '').toString();
    final rawName = (data['schoolTypeName'] ?? data['typeName'] ?? rawType)
        .toString();
    final normalizedCat =
        StoreSchoolTypeCategories.normalize(
          rawType.isNotEmpty ? rawType : rawName,
        ) ??
        (rawType.isNotEmpty ? rawType : rawName);
    return StoreSchoolTypeOption(
      id: doc.id,
      institutionId: (data['institutionId'] ?? '').toString().toUpperCase(),
      category: normalizedCat,
      name: rawName.isNotEmpty ? rawName : 'Okul Türü',
      activeGrades: _parseStringList(data['activeGrades']),
    );
  }
}

/// Bir kuruma ait tekil sınıf / şube seçeneği (`classes` koleksiyonundan).
class StoreClassOption {
  final String id;
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final String name; // Örn: '5-A', '8-B', '12-SAY'
  final String classLevel; // Örn: 'Anaokulu', '5', '8', '12'
  final String branch; // Örn: 'A', 'B', 'SAY'

  const StoreClassOption({
    required this.id,
    required this.institutionId,
    required this.schoolTypeId,
    this.schoolTypeName = '',
    required this.name,
    required this.classLevel,
    this.branch = '',
  });

  factory StoreClassOption.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    final rawName =
        (data['className'] ?? data['name'] ?? data['shortName'] ?? doc.id)
            .toString()
            .trim();
    final stName = (data['schoolTypeName'] ?? data['schoolType'] ?? '')
        .toString()
        .trim();
    final level =
        StoreClassLevels.extractLevel(
          rawLevel: data['classLevel'] ?? data['grade'],
          className: rawName,
          schoolTypeName: stName,
        ) ??
        '';
    final branch =
        StoreClassLevels.extractBranch(
          explicitBranch: data['branch']?.toString(),
          className: rawName,
        ) ??
        '';
    return StoreClassOption(
      id: doc.id,
      institutionId: (data['institutionId'] ?? '')
          .toString()
          .trim()
          .toUpperCase(),
      schoolTypeId: (data['schoolTypeId'] ?? '').toString().trim(),
      schoolTypeName: stName,
      name: rawName.isNotEmpty ? rawName : doc.id,
      classLevel: level,
      branch: branch,
    );
  }
}

/// Süper Admin mağaza yetkilendirme ve hedefleme için okul + alt okul türleri kaydı.
class StoreSchoolDirectoryItem {
  final String schoolId;
  final String institutionId;
  final String schoolName;
  final String city;
  final bool isActive;
  final List<StoreSchoolTypeOption> schoolTypes;

  const StoreSchoolDirectoryItem({
    required this.schoolId,
    required this.institutionId,
    required this.schoolName,
    this.city = '',
    this.isActive = true,
    this.schoolTypes = const [],
  });
}

/// Alışveriş yapan kullanıcının çözümlenmiş kurum / okul türü / öğrenci bağlamı.
class BuyerStoreContext {
  final String uid;
  final String fullName;
  final String email;
  final String phone;
  final String buyerRole; // 'idareci' | 'ogretmen' | 'veli' | 'ogrenci'
  final String institutionId;
  final String schoolId;
  final String schoolName;
  final List<String> schoolTypeIds;
  final List<String> schoolTypeNames;
  final List<String> schoolTypeCategories;
  final String? studentId;
  final String? studentName;
  final String? studentClass;
  final List<String> studentClassIds;
  final List<String> studentClassNames;
  final List<String> studentClassLevels;
  final List<String> studentBranches;

  const BuyerStoreContext({
    required this.uid,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.buyerRole,
    required this.institutionId,
    required this.schoolId,
    required this.schoolName,
    this.schoolTypeIds = const [],
    this.schoolTypeNames = const [],
    this.schoolTypeCategories = const [],
    this.studentId,
    this.studentName,
    this.studentClass,
    this.studentClassIds = const [],
    this.studentClassNames = const [],
    this.studentClassLevels = const [],
    this.studentBranches = const [],
  });

  String? get primarySchoolTypeId =>
      schoolTypeIds.isNotEmpty ? schoolTypeIds.first : null;

  String? get primarySchoolTypeName =>
      schoolTypeNames.isNotEmpty ? schoolTypeNames.first : null;
}

/// Genel Merkez Mağaza Erişim ve Yapılandırma Ayarları (`store_settings/SUPER_ADMIN`).
class HqStoreSchoolAccess {
  final bool isStoreOpenGlobally;
  final List<String> enabledSchoolIds;
  final Map<String, List<String>> enabledSchoolTypeMap;
  final double shippingFee;
  final double freeShippingThreshold;
  final String posMode; // 'sandbox_3d' | 'iyzico' | 'paytr'
  final String announcementBanner;
  final bool allowPickupAtSchool;
  final bool allowHomeDelivery;
  final DateTime updatedAt;

  const HqStoreSchoolAccess({
    this.isStoreOpenGlobally = true,
    this.enabledSchoolIds = const [],
    this.enabledSchoolTypeMap = const {},
    this.shippingFee = 59.90,
    this.freeShippingThreshold = 750.0,
    this.posMode = 'sandbox_3d',
    this.announcementBanner = '',
    this.allowPickupAtSchool = true,
    this.allowHomeDelivery = true,
    required this.updatedAt,
  });

  factory HqStoreSchoolAccess.defaults() {
    return HqStoreSchoolAccess(updatedAt: DateTime.now());
  }

  factory HqStoreSchoolAccess.fromMap(Map<String, dynamic>? map) {
    if (map == null) return HqStoreSchoolAccess.defaults();
    final rawTypeMap = map['enabledSchoolTypeMap'];
    final parsedTypeMap = <String, List<String>>{};
    if (rawTypeMap is Map) {
      rawTypeMap.forEach((key, value) {
        final k = key.toString().trim();
        if (k.isNotEmpty) {
          parsedTypeMap[k] = _parseStringList(value);
        }
      });
    }
    return HqStoreSchoolAccess(
      isStoreOpenGlobally: map['isStoreOpenGlobally'] as bool? ?? true,
      enabledSchoolIds: _parseStringList(map['enabledSchoolIds']),
      enabledSchoolTypeMap: parsedTypeMap,
      shippingFee: (map['shippingFee'] as num?)?.toDouble() ?? 59.90,
      freeShippingThreshold:
          (map['freeShippingThreshold'] as num?)?.toDouble() ?? 750.0,
      posMode: (map['posMode'] ?? 'sandbox_3d').toString(),
      announcementBanner: (map['announcementBanner'] ?? '').toString(),
      allowPickupAtSchool: map['allowPickupAtSchool'] as bool? ?? true,
      allowHomeDelivery: map['allowHomeDelivery'] as bool? ?? true,
      updatedAt: _parseDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sellerType': 'hq',
      'sellerInstitutionId': 'SUPER_ADMIN',
      'isStoreOpenGlobally': isStoreOpenGlobally,
      'enabledSchoolIds': enabledSchoolIds,
      'enabledSchoolTypeMap': enabledSchoolTypeMap,
      'shippingFee': shippingFee,
      'freeShippingThreshold': freeShippingThreshold,
      'posMode': posMode,
      'announcementBanner': announcementBanner,
      'allowPickupAtSchool': allowPickupAtSchool,
      'allowHomeDelivery': allowHomeDelivery,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Belirli bir okul ve alıcının okul türü listesi için Genel Merkez mağazası açık mı?
  bool isOpenForBuyer({
    required String schoolId,
    required String institutionId,
    required List<String> buyerSchoolTypeIds,
  }) {
    if (isStoreOpenGlobally) return true;

    final instUpper = institutionId.trim().toUpperCase();
    final matchedSchoolKey = [schoolId, instUpper, institutionId].firstWhere(
      (candidate) =>
          candidate.isNotEmpty &&
          (enabledSchoolIds.contains(candidate) ||
              enabledSchoolTypeMap.containsKey(candidate)),
      orElse: () => '',
    );

    if (matchedSchoolKey.isEmpty) return false;
    if (!enabledSchoolIds.contains(matchedSchoolKey) &&
        !enabledSchoolIds.contains(schoolId) &&
        !enabledSchoolIds.contains(instUpper)) {
      return false;
    }

    final allowedTypes =
        enabledSchoolTypeMap[matchedSchoolKey] ??
        enabledSchoolTypeMap[schoolId] ??
        enabledSchoolTypeMap[instUpper] ??
        const <String>[];

    if (allowedTypes.isEmpty || allowedTypes.contains('ALL')) {
      return true;
    }
    if (buyerSchoolTypeIds.isEmpty) {
      // Okul genelinde yetkili kullanıcı (örn. Genel Müdür / İdareci): en az bir okul türü açıksa görebilir.
      return allowedTypes.isNotEmpty;
    }
    return buyerSchoolTypeIds.any(allowedTypes.contains);
  }

  HqStoreSchoolAccess copyWith({
    bool? isStoreOpenGlobally,
    List<String>? enabledSchoolIds,
    Map<String, List<String>>? enabledSchoolTypeMap,
    double? shippingFee,
    double? freeShippingThreshold,
    String? posMode,
    String? announcementBanner,
    bool? allowPickupAtSchool,
    bool? allowHomeDelivery,
    DateTime? updatedAt,
  }) {
    return HqStoreSchoolAccess(
      isStoreOpenGlobally: isStoreOpenGlobally ?? this.isStoreOpenGlobally,
      enabledSchoolIds: enabledSchoolIds ?? this.enabledSchoolIds,
      enabledSchoolTypeMap: enabledSchoolTypeMap ?? this.enabledSchoolTypeMap,
      shippingFee: shippingFee ?? this.shippingFee,
      freeShippingThreshold:
          freeShippingThreshold ?? this.freeShippingThreshold,
      posMode: posMode ?? this.posMode,
      announcementBanner: announcementBanner ?? this.announcementBanner,
      allowPickupAtSchool: allowPickupAtSchool ?? this.allowPickupAtSchool,
      allowHomeDelivery: allowHomeDelivery ?? this.allowHomeDelivery,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Okulun Bağımsız Mağaza Ayarları (`store_settings/{INSTITUTION_ID}`).
class SchoolStoreSettings {
  final String institutionId;
  final bool isSchoolStoreEnabled;
  final List<String> enabledSchoolTypeIds;
  final bool allowPickupAtSchool;
  final bool allowHomeDelivery;
  final double shippingFee;
  final double freeShippingThreshold;
  final String ibanOrPosNote;
  final String announcementBanner;
  final bool usesCustomStorePos;
  final String storePosMerchantTitle;
  final DateTime updatedAt;

  const SchoolStoreSettings({
    required this.institutionId,
    this.isSchoolStoreEnabled = true,
    this.enabledSchoolTypeIds = const [],
    this.allowPickupAtSchool = true,
    this.allowHomeDelivery = true,
    this.shippingFee = 0.0,
    this.freeShippingThreshold = 500.0,
    this.ibanOrPosNote = '',
    this.announcementBanner = '',
    this.usesCustomStorePos = false,
    this.storePosMerchantTitle = '',
    required this.updatedAt,
  });

  factory SchoolStoreSettings.defaults(String institutionId) {
    return SchoolStoreSettings(
      institutionId: institutionId.trim().toUpperCase(),
      updatedAt: DateTime.now(),
    );
  }

  factory SchoolStoreSettings.fromMap(
    String institutionId,
    Map<String, dynamic>? map,
  ) {
    final upper = institutionId.trim().toUpperCase();
    if (map == null) return SchoolStoreSettings.defaults(upper);
    return SchoolStoreSettings(
      institutionId: upper,
      isSchoolStoreEnabled: map['isSchoolStoreEnabled'] as bool? ?? true,
      enabledSchoolTypeIds: _parseStringList(map['enabledSchoolTypeIds']),
      allowPickupAtSchool: map['allowPickupAtSchool'] as bool? ?? true,
      allowHomeDelivery: map['allowHomeDelivery'] as bool? ?? true,
      shippingFee: (map['shippingFee'] as num?)?.toDouble() ?? 0.0,
      freeShippingThreshold:
          (map['freeShippingThreshold'] as num?)?.toDouble() ?? 500.0,
      ibanOrPosNote: (map['ibanOrPosNote'] ?? '').toString(),
      announcementBanner: (map['announcementBanner'] ?? '').toString(),
      usesCustomStorePos: map['usesCustomStorePos'] as bool? ?? false,
      storePosMerchantTitle: (map['storePosMerchantTitle'] ?? '').toString(),
      updatedAt: _parseDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    final upper = institutionId.trim().toUpperCase();
    return {
      'institutionId': upper,
      'sellerType': 'school',
      'sellerInstitutionId': upper,
      'isSchoolStoreEnabled': isSchoolStoreEnabled,
      'enabledSchoolTypeIds': enabledSchoolTypeIds,
      'allowPickupAtSchool': allowPickupAtSchool,
      'allowHomeDelivery': allowHomeDelivery,
      'shippingFee': shippingFee,
      'freeShippingThreshold': freeShippingThreshold,
      'ibanOrPosNote': ibanOrPosNote,
      'announcementBanner': announcementBanner,
      'usesCustomStorePos': usesCustomStorePos,
      'storePosMerchantTitle': storePosMerchantTitle,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  bool isOpenForBuyerSchoolTypes(List<String> buyerSchoolTypeIds) {
    if (!isSchoolStoreEnabled) return false;
    if (enabledSchoolTypeIds.isEmpty || enabledSchoolTypeIds.contains('ALL')) {
      return true;
    }
    if (buyerSchoolTypeIds.isEmpty) {
      return true;
    }
    return buyerSchoolTypeIds.any(enabledSchoolTypeIds.contains);
  }

  SchoolStoreSettings copyWith({
    bool? isSchoolStoreEnabled,
    List<String>? enabledSchoolTypeIds,
    bool? allowPickupAtSchool,
    bool? allowHomeDelivery,
    double? shippingFee,
    double? freeShippingThreshold,
    String? ibanOrPosNote,
    String? announcementBanner,
    bool? usesCustomStorePos,
    String? storePosMerchantTitle,
    DateTime? updatedAt,
  }) {
    return SchoolStoreSettings(
      institutionId: institutionId,
      isSchoolStoreEnabled: isSchoolStoreEnabled ?? this.isSchoolStoreEnabled,
      enabledSchoolTypeIds: enabledSchoolTypeIds ?? this.enabledSchoolTypeIds,
      allowPickupAtSchool: allowPickupAtSchool ?? this.allowPickupAtSchool,
      allowHomeDelivery: allowHomeDelivery ?? this.allowHomeDelivery,
      shippingFee: shippingFee ?? this.shippingFee,
      freeShippingThreshold:
          freeShippingThreshold ?? this.freeShippingThreshold,
      ibanOrPosNote: ibanOrPosNote ?? this.ibanOrPosNote,
      announcementBanner: announcementBanner ?? this.announcementBanner,
      usesCustomStorePos: usesCustomStorePos ?? this.usesCustomStorePos,
      storePosMerchantTitle:
          storePosMerchantTitle ?? this.storePosMerchantTitle,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Mağaza Ürünü (`store_products/{productId}`).
class StoreProduct {
  final String id;
  final String sellerType; // 'hq' | 'school'
  final String sellerInstitutionId; // 'SUPER_ADMIN' | INSTITUTION_ID
  final String sellerName;
  final String title;
  final String description;
  final String category;
  final double price;
  final double? discountedPrice;
  final int vatRate; // 0, 10, 20
  final int stock;
  final int soldCount;
  final List<String> variants;
  final List<String> imageUrls;
  final bool isActive;

  // Teslimat ve Zorunlu Ürün ayarları
  final bool allowPickupAtSchool;
  final bool allowHomeDelivery;
  final bool isMandatory;
  final List<String> mandatoryRoles;

  // Hedefleme alanları
  final bool targetAllSchools;
  final List<String> targetSchoolIds;
  final bool targetAllSchoolTypes;
  final List<String> targetSchoolTypeIds;
  final List<String> targetSchoolTypeCategories;
  final bool targetAllClassLevels;
  final List<String> targetClassLevels;
  final bool targetAllClasses;
  final List<String> targetClassIds;
  final List<String> targetClassNames;
  final List<String> targetRoles;

  final DateTime createdAt;
  final DateTime updatedAt;

  const StoreProduct({
    required this.id,
    required this.sellerType,
    required this.sellerInstitutionId,
    required this.sellerName,
    required this.title,
    this.description = '',
    this.category = StoreCategories.booksAndSets,
    required this.price,
    this.discountedPrice,
    this.vatRate = 10,
    this.stock = 0,
    this.soldCount = 0,
    this.variants = const [],
    this.imageUrls = const [],
    this.isActive = true,
    this.allowPickupAtSchool = true,
    this.allowHomeDelivery = true,
    this.isMandatory = false,
    this.mandatoryRoles = const [StoreBuyerRoles.veli, StoreBuyerRoles.ogrenci],
    this.targetAllSchools = true,
    this.targetSchoolIds = const [],
    this.targetAllSchoolTypes = true,
    this.targetSchoolTypeIds = const [],
    this.targetSchoolTypeCategories = const [],
    this.targetAllClassLevels = true,
    this.targetClassLevels = const [],
    this.targetAllClasses = true,
    this.targetClassIds = const [],
    this.targetClassNames = const [],
    this.targetRoles = StoreBuyerRoles.all,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isHq => sellerType == 'hq';
  bool get isSchool => sellerType == 'school';

  bool get hasDiscount =>
      discountedPrice != null &&
      discountedPrice! > 0 &&
      discountedPrice! < price;

  double get effectivePrice => hasDiscount ? discountedPrice! : price;

  int get discountPercentage {
    if (!hasDiscount || price <= 0) return 0;
    return (((price - discountedPrice!) / price) * 100).round();
  }

  bool get isOutOfStock => stock <= 0;

  String? get primaryImageUrl {
    for (final u in imageUrls) {
      final norm = StoreImageUrlHelper.normalize(u);
      if (norm.isNotEmpty) return norm;
    }
    return null;
  }

  /// Ürün teslimat yöntemi kısıtlıysa gösterilecek rozet (`Sadece Okuldan Teslim` / `Sadece Adrese Kargo`).
  String? get deliveryBadgeLabel {
    if (allowPickupAtSchool && !allowHomeDelivery) {
      return 'Sadece Okuldan Teslim';
    }
    if (!allowPickupAtSchool && allowHomeDelivery) {
      return 'Sadece Adrese Kargo';
    }
    return null;
  }

  /// Yönetim satırlarında gösterilecek teslimat özeti.
  String get deliverySummaryLabel {
    if (allowPickupAtSchool && allowHomeDelivery) {
      return 'Okuldan Teslim & Kargo';
    }
    if (allowPickupAtSchool) return 'Sadece Okuldan Teslim';
    if (allowHomeDelivery) return 'Sadece Adrese Kargo';
    return 'Okuldan Teslim & Kargo';
  }

  /// Belirli bir alıcı rolü için bu ürün ilk alışverişte zorunlu mu?
  bool isMandatoryForRole(String buyerRole) {
    if (!isMandatory) return false;
    final norm = StoreBuyerRoles.normalize(buyerRole);
    final effectiveRoles = mandatoryRoles.isNotEmpty
        ? mandatoryRoles
        : const [StoreBuyerRoles.veli, StoreBuyerRoles.ogrenci];
    return effectiveRoles.contains(norm);
  }

  /// Vitrinde ve yönetim listesinde gösterilecek kısa sınıf/şube hedef rozeti.
  String? get audienceBadgeLabel {
    final parts = <String>[];
    if (!targetAllClasses && targetClassNames.isNotEmpty) {
      parts.add(
        targetClassNames.take(3).join(', ') +
            (targetClassNames.length > 3
                ? ' +${targetClassNames.length - 3}'
                : ''),
      );
    } else if (!targetAllClassLevels && targetClassLevels.isNotEmpty) {
      final labels = targetClassLevels.map(StoreClassLevels.labelOf).toList();
      parts.add(
        labels.take(3).join(', ') +
            (labels.length > 3 ? ' +${labels.length - 3}' : ''),
      );
    } else if (!targetAllSchoolTypes && targetSchoolTypeCategories.isNotEmpty) {
      parts.add(targetSchoolTypeCategories.join(', '));
    }
    return parts.isEmpty ? null : parts.join(' • ');
  }

  factory StoreProduct.fromFirestore(DocumentSnapshot doc) {
    final map = (doc.data() as Map<String, dynamic>?) ?? {};
    return StoreProduct.fromMap(doc.id, map);
  }

  factory StoreProduct.fromMap(String id, Map<String, dynamic> map) {
    final rawDisc = (map['discountedPrice'] as num?)?.toDouble();
    final roles = _parseStringList(map['targetRoles']);
    final mRoles = _parseStringList(map['mandatoryRoles']);
    final normalizedUrls = StoreImageUrlHelper.normalizeList(
      _parseStringList(map['imageUrls']),
    );
    final rawLevels = _parseStringList(map['targetClassLevels']);
    final normLevels = <String>[];
    for (final l in rawLevels) {
      final nl = StoreClassLevels.normalize(l);
      if (nl != null && nl.isNotEmpty && !normLevels.contains(nl)) {
        normLevels.add(nl);
      }
    }
    final allowPickup = map['allowPickupAtSchool'] as bool? ?? true;
    final allowHome = map['allowHomeDelivery'] as bool? ?? true;
    return StoreProduct(
      id: id,
      sellerType: (map['sellerType'] ?? 'school').toString(),
      sellerInstitutionId: (map['sellerInstitutionId'] ?? '')
          .toString()
          .toUpperCase(),
      sellerName: (map['sellerName'] ?? 'Mağaza').toString(),
      title: (map['title'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      category: (map['category'] ?? StoreCategories.booksAndSets).toString(),
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      discountedPrice: (rawDisc != null && rawDisc > 0) ? rawDisc : null,
      vatRate: (map['vatRate'] as num?)?.toInt() ?? 10,
      stock: (map['stock'] as num?)?.toInt() ?? 0,
      soldCount: (map['soldCount'] as num?)?.toInt() ?? 0,
      variants: _parseStringList(map['variants']),
      imageUrls: normalizedUrls,
      isActive: map['isActive'] as bool? ?? true,
      allowPickupAtSchool: (!allowPickup && !allowHome) ? true : allowPickup,
      allowHomeDelivery: (!allowPickup && !allowHome) ? true : allowHome,
      isMandatory: map['isMandatory'] as bool? ?? false,
      mandatoryRoles: mRoles.isNotEmpty
          ? mRoles
          : const [StoreBuyerRoles.veli, StoreBuyerRoles.ogrenci],
      targetAllSchools: map['targetAllSchools'] as bool? ?? true,
      targetSchoolIds: _parseStringList(map['targetSchoolIds']),
      targetAllSchoolTypes: map['targetAllSchoolTypes'] as bool? ?? true,
      targetSchoolTypeIds: _parseStringList(map['targetSchoolTypeIds']),
      targetSchoolTypeCategories: _parseStringList(
        map['targetSchoolTypeCategories'],
      ),
      targetAllClassLevels: map['targetAllClassLevels'] as bool? ?? true,
      targetClassLevels: normLevels,
      targetAllClasses: map['targetAllClasses'] as bool? ?? true,
      targetClassIds: _parseStringList(map['targetClassIds']),
      targetClassNames: _parseStringList(map['targetClassNames']),
      targetRoles: roles.isNotEmpty ? roles : StoreBuyerRoles.all,
      createdAt: _parseDate(map['createdAt']),
      updatedAt: _parseDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap({bool isNew = false}) {
    final normalizedInst = sellerType == 'hq'
        ? 'SUPER_ADMIN'
        : sellerInstitutionId.toUpperCase();
    final cleanedUrls = StoreImageUrlHelper.normalizeList(imageUrls);
    return {
      'sellerType': sellerType,
      'sellerInstitutionId': normalizedInst,
      'institutionId': normalizedInst,
      'sellerName': sellerName,
      'title': title.trim(),
      'description': description.trim(),
      'category': category,
      'price': price,
      'discountedPrice': hasDiscount ? discountedPrice : null,
      'vatRate': vatRate,
      'stock': stock,
      'soldCount': soldCount,
      'variants': variants,
      'imageUrls': cleanedUrls,
      'isActive': isActive,
      'allowPickupAtSchool': allowPickupAtSchool,
      'allowHomeDelivery': allowHomeDelivery,
      'isMandatory': isMandatory,
      'mandatoryRoles': mandatoryRoles.isNotEmpty
          ? mandatoryRoles
          : const [StoreBuyerRoles.veli, StoreBuyerRoles.ogrenci],
      'targetAllSchools': targetAllSchools,
      'targetSchoolIds': targetSchoolIds,
      'targetAllSchoolTypes': targetAllSchoolTypes,
      'targetSchoolTypeIds': targetSchoolTypeIds,
      'targetSchoolTypeCategories': targetSchoolTypeCategories,
      'targetAllClassLevels': targetAllClassLevels,
      'targetClassLevels': targetClassLevels,
      'targetAllClasses': targetAllClasses,
      'targetClassIds': targetClassIds,
      'targetClassNames': targetClassNames,
      'targetRoles': targetRoles.isNotEmpty ? targetRoles : StoreBuyerRoles.all,
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  StoreProduct copyWith({
    String? id,
    String? sellerType,
    String? sellerInstitutionId,
    String? sellerName,
    String? title,
    String? description,
    String? category,
    double? price,
    double? discountedPrice,
    bool clearDiscountedPrice = false,
    int? vatRate,
    int? stock,
    int? soldCount,
    List<String>? variants,
    List<String>? imageUrls,
    bool? isActive,
    bool? allowPickupAtSchool,
    bool? allowHomeDelivery,
    bool? isMandatory,
    List<String>? mandatoryRoles,
    bool? targetAllSchools,
    List<String>? targetSchoolIds,
    bool? targetAllSchoolTypes,
    List<String>? targetSchoolTypeIds,
    List<String>? targetSchoolTypeCategories,
    bool? targetAllClassLevels,
    List<String>? targetClassLevels,
    bool? targetAllClasses,
    List<String>? targetClassIds,
    List<String>? targetClassNames,
    List<String>? targetRoles,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StoreProduct(
      id: id ?? this.id,
      sellerType: sellerType ?? this.sellerType,
      sellerInstitutionId: sellerInstitutionId ?? this.sellerInstitutionId,
      sellerName: sellerName ?? this.sellerName,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      price: price ?? this.price,
      discountedPrice: clearDiscountedPrice
          ? null
          : (discountedPrice ?? this.discountedPrice),
      vatRate: vatRate ?? this.vatRate,
      stock: stock ?? this.stock,
      soldCount: soldCount ?? this.soldCount,
      variants: variants ?? this.variants,
      imageUrls: imageUrls ?? this.imageUrls,
      isActive: isActive ?? this.isActive,
      allowPickupAtSchool: allowPickupAtSchool ?? this.allowPickupAtSchool,
      allowHomeDelivery: allowHomeDelivery ?? this.allowHomeDelivery,
      isMandatory: isMandatory ?? this.isMandatory,
      mandatoryRoles: mandatoryRoles ?? this.mandatoryRoles,
      targetAllSchools: targetAllSchools ?? this.targetAllSchools,
      targetSchoolIds: targetSchoolIds ?? this.targetSchoolIds,
      targetAllSchoolTypes: targetAllSchoolTypes ?? this.targetAllSchoolTypes,
      targetSchoolTypeIds: targetSchoolTypeIds ?? this.targetSchoolTypeIds,
      targetSchoolTypeCategories:
          targetSchoolTypeCategories ?? this.targetSchoolTypeCategories,
      targetAllClassLevels: targetAllClassLevels ?? this.targetAllClassLevels,
      targetClassLevels: targetClassLevels ?? this.targetClassLevels,
      targetAllClasses: targetAllClasses ?? this.targetAllClasses,
      targetClassIds: targetClassIds ?? this.targetClassIds,
      targetClassNames: targetClassNames ?? this.targetClassNames,
      targetRoles: targetRoles ?? this.targetRoles,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Sepetteki tekil kalem.
class StoreCartItem {
  final StoreProduct product;
  final String? selectedVariant;
  final int quantity;

  const StoreCartItem({
    required this.product,
    this.selectedVariant,
    this.quantity = 1,
  });

  String get cartKey => '${product.id}::${selectedVariant ?? ''}';

  double get unitPrice => product.effectivePrice;

  double get lineTotal => unitPrice * quantity;

  StoreCartItem copyWith({
    StoreProduct? product,
    String? selectedVariant,
    int? quantity,
  }) {
    return StoreCartItem(
      product: product ?? this.product,
      selectedVariant: selectedVariant ?? this.selectedVariant,
      quantity: quantity ?? this.quantity,
    );
  }
}

/// Siparişteki ürün satırı.
class StoreOrderItem {
  final String productId;
  final String title;
  final String category;
  final String? imageUrl;
  final String? selectedVariant;
  final double unitPrice;
  final int vatRate;
  final int quantity;
  final double lineTotal;

  const StoreOrderItem({
    required this.productId,
    required this.title,
    required this.category,
    this.imageUrl,
    this.selectedVariant,
    required this.unitPrice,
    required this.vatRate,
    required this.quantity,
    required this.lineTotal,
  });

  factory StoreOrderItem.fromCartItem(StoreCartItem item) {
    return StoreOrderItem(
      productId: item.product.id,
      title: item.product.title,
      category: item.product.category,
      imageUrl: item.product.primaryImageUrl,
      selectedVariant: item.selectedVariant,
      unitPrice: item.unitPrice,
      vatRate: item.product.vatRate,
      quantity: item.quantity,
      lineTotal: item.lineTotal,
    );
  }

  factory StoreOrderItem.fromMap(Map<String, dynamic> map) {
    final unit = (map['unitPrice'] as num?)?.toDouble() ?? 0.0;
    final qty = (map['quantity'] as num?)?.toInt() ?? 1;
    return StoreOrderItem(
      productId: (map['productId'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      category: (map['category'] ?? '').toString(),
      imageUrl: map['imageUrl']?.toString(),
      selectedVariant: map['selectedVariant']?.toString(),
      unitPrice: unit,
      vatRate: (map['vatRate'] as num?)?.toInt() ?? 10,
      quantity: qty,
      lineTotal: (map['lineTotal'] as num?)?.toDouble() ?? (unit * qty),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'title': title,
      'category': category,
      'imageUrl': imageUrl,
      'selectedVariant': selectedVariant,
      'unitPrice': unitPrice,
      'vatRate': vatRate,
      'quantity': quantity,
      'lineTotal': lineTotal,
    };
  }
}

/// Online Mağaza Siparişi (`store_orders/{orderId}`).
class StoreOrder {
  final String id;
  final String orderNo;
  final String sellerType; // 'hq' | 'school'
  final String sellerInstitutionId; // 'SUPER_ADMIN' | INSTITUTION_ID
  final String sellerName;

  final String buyerUid;
  final String buyerName;
  final String buyerRole; // 'idareci' | 'ogretmen' | 'veli' | 'ogrenci'
  final String buyerPhone;
  final String buyerEmail;

  final String? studentId;
  final String? studentName;
  final String? studentClass;

  final String institutionId;
  final String? schoolId;
  final String? schoolName;
  final String? schoolTypeId;
  final String? schoolTypeName;

  final List<StoreOrderItem> items;
  final double subtotal;
  final double shippingFee;
  final double totalAmount;

  final String deliveryType; // 'Okuldan Teslim' | 'Adrese Kargo'
  final String deliveryAddress;
  final String orderNote;

  final String paymentStatus; // 'paid'
  final String paymentMethod; // 'online_card'
  final String paymentRef;
  final String cardMasked;
  final int installmentCount; // 1, 2, 3, 6

  final String orderStatus;
  final String trackingCode;
  final String cancelReason;

  final DateTime createdAt;
  final DateTime updatedAt;

  const StoreOrder({
    required this.id,
    required this.orderNo,
    required this.sellerType,
    required this.sellerInstitutionId,
    required this.sellerName,
    required this.buyerUid,
    required this.buyerName,
    required this.buyerRole,
    required this.buyerPhone,
    required this.buyerEmail,
    this.studentId,
    this.studentName,
    this.studentClass,
    required this.institutionId,
    this.schoolId,
    this.schoolName,
    this.schoolTypeId,
    this.schoolTypeName,
    required this.items,
    required this.subtotal,
    required this.shippingFee,
    required this.totalAmount,
    required this.deliveryType,
    required this.deliveryAddress,
    this.orderNote = '',
    this.paymentStatus = 'paid',
    this.paymentMethod = 'online_card',
    required this.paymentRef,
    required this.cardMasked,
    this.installmentCount = 1,
    this.orderStatus = StoreOrderStatuses.bekliyor,
    this.trackingCode = '',
    this.cancelReason = '',
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isHqOrder => sellerType == 'hq';
  bool get isSchoolOrder => sellerType == 'school';
  bool get canBuyerCancel => orderStatus == StoreOrderStatuses.bekliyor;

  int get totalItemQuantity =>
      items.fold<int>(0, (acc, item) => acc + item.quantity);

  factory StoreOrder.fromFirestore(DocumentSnapshot doc) {
    final map = (doc.data() as Map<String, dynamic>?) ?? {};
    return StoreOrder.fromMap(doc.id, map);
  }

  factory StoreOrder.fromMap(String id, Map<String, dynamic> map) {
    final rawItems = map['items'];
    final parsedItems = <StoreOrderItem>[];
    if (rawItems is Iterable) {
      for (final item in rawItems) {
        if (item is Map) {
          parsedItems.add(
            StoreOrderItem.fromMap(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return StoreOrder(
      id: id,
      orderNo: (map['orderNo'] ?? '').toString(),
      sellerType: (map['sellerType'] ?? 'school').toString(),
      sellerInstitutionId: (map['sellerInstitutionId'] ?? '')
          .toString()
          .toUpperCase(),
      sellerName: (map['sellerName'] ?? '').toString(),
      buyerUid: (map['buyerUid'] ?? '').toString(),
      buyerName: (map['buyerName'] ?? '').toString(),
      buyerRole: (map['buyerRole'] ?? StoreBuyerRoles.veli).toString(),
      buyerPhone: (map['buyerPhone'] ?? '').toString(),
      buyerEmail: (map['buyerEmail'] ?? '').toString(),
      studentId: map['studentId']?.toString(),
      studentName: map['studentName']?.toString(),
      studentClass: map['studentClass']?.toString(),
      institutionId: (map['institutionId'] ?? '').toString().toUpperCase(),
      schoolId: map['schoolId']?.toString(),
      schoolName: map['schoolName']?.toString(),
      schoolTypeId: map['schoolTypeId']?.toString(),
      schoolTypeName: map['schoolTypeName']?.toString(),
      items: parsedItems,
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0.0,
      shippingFee: (map['shippingFee'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (map['totalAmount'] as num?)?.toDouble() ?? 0.0,
      deliveryType: (map['deliveryType'] ?? 'Okuldan Teslim').toString(),
      deliveryAddress: (map['deliveryAddress'] ?? '').toString(),
      orderNote: (map['orderNote'] ?? '').toString(),
      paymentStatus: (map['paymentStatus'] ?? 'paid').toString(),
      paymentMethod: (map['paymentMethod'] ?? 'online_card').toString(),
      paymentRef: (map['paymentRef'] ?? '').toString(),
      cardMasked: (map['cardMasked'] ?? '').toString(),
      installmentCount: (map['installmentCount'] as num?)?.toInt() ?? 1,
      orderStatus: (map['orderStatus'] ?? StoreOrderStatuses.bekliyor)
          .toString(),
      trackingCode: (map['trackingCode'] ?? '').toString(),
      cancelReason: (map['cancelReason'] ?? '').toString(),
      createdAt: _parseDate(map['createdAt']),
      updatedAt: _parseDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap({bool isNew = false}) {
    final normalizedSellerInst = sellerType == 'hq'
        ? 'SUPER_ADMIN'
        : sellerInstitutionId.toUpperCase();
    return {
      'orderNo': orderNo,
      'sellerType': sellerType,
      'sellerInstitutionId': normalizedSellerInst,
      'sellerName': sellerName,
      'buyerUid': buyerUid,
      'buyerName': buyerName,
      'buyerRole': buyerRole,
      'buyerPhone': buyerPhone,
      'buyerEmail': buyerEmail,
      'studentId': studentId,
      'studentName': studentName,
      'studentClass': studentClass,
      'institutionId': institutionId.toUpperCase(),
      'schoolId': schoolId,
      'schoolName': schoolName,
      'schoolTypeId': schoolTypeId,
      'schoolTypeName': schoolTypeName,
      'items': items.map((e) => e.toMap()).toList(),
      'subtotal': subtotal,
      'shippingFee': shippingFee,
      'totalAmount': totalAmount,
      'deliveryType': deliveryType,
      'deliveryAddress': deliveryAddress,
      'orderNote': orderNote,
      'paymentStatus': paymentStatus,
      'paymentMethod': paymentMethod,
      'paymentRef': paymentRef,
      'cardMasked': cardMasked,
      'installmentCount': installmentCount,
      'orderStatus': orderStatus,
      'trackingCode': trackingCode,
      'cancelReason': cancelReason,
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
