import '../constants/app_modules.dart';

/// Kurum (okul) bazlı modül, alt başlık ve 3. seviye özellik erişim kontrolü.
///
/// `schools/{schoolId}` doküman şeması:
/// - `activeModules`: `List<String>` — Aktif ana modül anahtarları (`ModuleInfo.key`).
///   Eski (legacy) dokümanlarda `null` / tanımsız ise geriye dönük uyumluluk için
///   tüm ana modüller aktif kabul edilir.
/// - `disabledSubModules`: `List<String>` — Devre dışı bırakılan alt başlık ve
///   3. seviye özellik anahtarları:
///   - 2. seviye: `'$moduleKey.$subKey'`
///   - 3. seviye: `'$moduleKey.$subKey.$nestedKey'`
///   Eski dokümanlarda `null` / boş ise aktif modüllerin tüm alt başlıkları açıktır.
class SchoolModuleGuard {
  const SchoolModuleGuard._();

  /// 2. seviye alt başlık için standart anahtar üretir: `'$moduleKey.$subKey'`.
  static String subModuleToken(String moduleKey, String subKey) =>
      '$moduleKey.$subKey';

  /// 3. seviye alt öğe için standart anahtar üretir: `'$moduleKey.$subKey.$nestedKey'`.
  static String nestedItemToken(
    String moduleKey,
    String subKey,
    String nestedKey,
  ) => '$moduleKey.$subKey.$nestedKey';

  /// Okul verisinden aktif ana modül kümesini çıkarır.
  /// `activeModules` alanı yoksa varsayılan olarak tüm modülleri döner.
  static Set<String> extractActiveModules(Map<String, dynamic>? schoolData) {
    if (schoolData == null) {
      return AppModules.allModuleKeys.toSet();
    }
    final raw = schoolData['activeModules'];
    if (raw == null) {
      return AppModules.allModuleKeys.toSet();
    }
    if (raw is Iterable) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet();
    }
    return AppModules.allModuleKeys.toSet();
  }

  /// Okul verisinden devre dışı bırakılmış alt başlık/özellik kümesini çıkarır.
  static Set<String> extractDisabledSubModules(
    Map<String, dynamic>? schoolData,
  ) {
    if (schoolData == null) return <String>{};
    final raw = schoolData['disabledSubModules'];
    if (raw is Iterable) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet();
    }
    return <String>{};
  }

  /// Belirtilen ana modülün okul için aktif olup olmadığını kontrol eder.
  static bool isModuleEnabled(
    Map<String, dynamic>? schoolData,
    String moduleKey,
  ) {
    final trimmedKey = moduleKey.trim();
    if (trimmedKey.isEmpty) return false;
    if (schoolData == null || schoolData['activeModules'] == null) {
      return true;
    }
    final activeModules = extractActiveModules(schoolData);
    return activeModules.contains(trimmedKey);
  }

  /// Belirtilen 2. seviye alt başlığın okul için aktif olup olmadığını kontrol eder.
  /// Önce ana modülün (`moduleKey`) aktifliğini doğrular, ardından
  /// `disabledSubModules` içinde `'$moduleKey.$subKey'` veya `subKey` olup olmadığına bakar.
  static bool isSubModuleEnabled(
    Map<String, dynamic>? schoolData,
    String moduleKey,
    String subKey,
  ) {
    final trimmedModule = moduleKey.trim();
    final trimmedSub = subKey.trim();
    if (trimmedModule.isEmpty || trimmedSub.isEmpty) return false;

    if (!isModuleEnabled(schoolData, trimmedModule)) {
      return false;
    }

    final disabled = extractDisabledSubModules(schoolData);
    if (disabled.isEmpty) return true;

    final canonical = subModuleToken(trimmedModule, trimmedSub);
    return !disabled.contains(canonical) && !disabled.contains(trimmedSub);
  }

  /// Belirtilen 3. seviye alt özelliğin okul için aktif olup olmadığını kontrol eder.
  /// Önce üst modül ve alt başlığın aktifliğini doğrular, ardından
  /// `disabledSubModules` içinde `'$moduleKey.$subKey.$nestedKey'` kontrolü yapar.
  static bool isNestedItemEnabled(
    Map<String, dynamic>? schoolData,
    String moduleKey,
    String subKey,
    String nestedKey,
  ) {
    final trimmedModule = moduleKey.trim();
    final trimmedSub = subKey.trim();
    final trimmedNested = nestedKey.trim();
    if (trimmedModule.isEmpty || trimmedSub.isEmpty || trimmedNested.isEmpty) {
      return false;
    }

    if (!isSubModuleEnabled(schoolData, trimmedModule, trimmedSub)) {
      return false;
    }

    final disabled = extractDisabledSubModules(schoolData);
    if (disabled.isEmpty) return true;

    final canonical = nestedItemToken(trimmedModule, trimmedSub, trimmedNested);
    return !disabled.contains(canonical) &&
        !disabled.contains('$trimmedSub.$trimmedNested') &&
        !disabled.contains(trimmedNested);
  }

  /// Bir ana modül altındaki aktif alt başlık anahtarlarını liste olarak döner.
  static List<String> enabledSubModuleKeys(
    Map<String, dynamic>? schoolData,
    String moduleKey,
  ) {
    final info = AppModules.getModule(moduleKey);
    if (info == null) return const [];
    if (!isModuleEnabled(schoolData, moduleKey)) return const [];

    return info.subModules.keys
        .where((subKey) => isSubModuleEnabled(schoolData, moduleKey, subKey))
        .toList();
  }

  // ───────────────────────────────────────────────────────────────────────
  // KADEME (İDARECİ) İŞLEMLERİ ve ÖĞRETMEN ARAYÜZÜ kapsamı (Süper Admin lisanslama)
  //
  // Bu iki kapsam `activeModules` listesini KULLANMAZ (eski okullar bozulmasın diye):
  // yalnızca `disabledSubModules` içindeki negatif liste ile çalışır.
  //   - Kademe (idareci) : 'st.<modül>' / 'st.<modül>.<alt>' / 'st.<modül>.<alt>.<detay>'
  //   - Öğretmen arayüzü : 't.<modül>'  / 't.<modül>.<alt>'  / 't.<modül>.<alt>.<detay>'
  // Liste boşsa / token yoksa her şey AÇIK kabul edilir.
  // ───────────────────────────────────────────────────────────────────────

  /// Kademe modülü için token: `st.<modül>`.
  static String stModuleToken(String stModuleKey) => 'st.$stModuleKey';

  /// Kademe alt başlığı için token: `st.<modül>.<alt>`.
  static String stSubToken(String stModuleKey, String stSubKey) =>
      'st.$stModuleKey.$stSubKey';

  /// Kademe 3. seviye detay token: `st.<modül>.<alt>.<detay>`.
  static String stNestedToken(
    String stModuleKey,
    String stSubKey,
    String nestedKey,
  ) => 'st.$stModuleKey.$stSubKey.$nestedKey';

  /// Öğretmen modülü için token: `t.<modül>`.
  static String teacherModuleToken(String tModuleKey) => 't.$tModuleKey';

  /// Öğretmen alt başlığı için token: `t.<modül>.<alt>`.
  static String teacherSubToken(String tModuleKey, String tSubKey) =>
      't.$tModuleKey.$tSubKey';

  /// Öğretmen 3. seviye detay token: `t.<modül>.<alt>.<detay>`.
  static String teacherNestedToken(
    String tModuleKey,
    String tSubKey,
    String nestedKey,
  ) => 't.$tModuleKey.$tSubKey.$nestedKey';

  /// Genel amaçlı: token (`st.egitim`, `st.egitim.ders_programi` ...) okul için kapatılmış mı?
  static bool isScopedTokenDisabled(
    Map<String, dynamic>? schoolData,
    String token,
  ) {
    if (schoolData == null || token.trim().isEmpty) return false;
    return extractDisabledSubModules(schoolData).contains(token.trim());
  }

  /// Kademe (idareci) modülü okul için açık mı?
  static bool isSchoolTypeModuleEnabled(
    Map<String, dynamic>? schoolData,
    String stModuleKey,
  ) => !isScopedTokenDisabled(schoolData, stModuleToken(stModuleKey));

  /// Kademe (idareci) alt başlığı okul için açık mı? (Önce modül, sonra alt başlık)
  static bool isSchoolTypeSubEnabled(
    Map<String, dynamic>? schoolData,
    String stModuleKey,
    String stSubKey,
  ) {
    if (!isSchoolTypeModuleEnabled(schoolData, stModuleKey)) return false;
    return !isScopedTokenDisabled(
      schoolData,
      stSubToken(stModuleKey, stSubKey),
    );
  }

  /// Kademe (idareci) 3. seviye detay okul için açık mı?
  static bool isSchoolTypeNestedEnabled(
    Map<String, dynamic>? schoolData,
    String stModuleKey,
    String stSubKey,
    String nestedKey,
  ) {
    if (!isSchoolTypeSubEnabled(schoolData, stModuleKey, stSubKey)) {
      return false;
    }
    return !isScopedTokenDisabled(
      schoolData,
      stNestedToken(stModuleKey, stSubKey, nestedKey),
    );
  }

  /// Öğretmen arayüzü modülü okul için açık mı?
  static bool isTeacherModuleEnabled(
    Map<String, dynamic>? schoolData,
    String tModuleKey,
  ) => !isScopedTokenDisabled(schoolData, teacherModuleToken(tModuleKey));

  /// Öğretmen arayüzü alt başlığı okul için açık mı?
  static bool isTeacherSubEnabled(
    Map<String, dynamic>? schoolData,
    String tModuleKey,
    String tSubKey,
  ) {
    if (!isTeacherModuleEnabled(schoolData, tModuleKey)) return false;
    return !isScopedTokenDisabled(
      schoolData,
      teacherSubToken(tModuleKey, tSubKey),
    );
  }

  /// Öğretmen arayüzü 3. seviye detay okul için açık mı?
  static bool isTeacherNestedEnabled(
    Map<String, dynamic>? schoolData,
    String tModuleKey,
    String tSubKey,
    String nestedKey,
  ) {
    if (!isTeacherSubEnabled(schoolData, tModuleKey, tSubKey)) return false;
    return !isScopedTokenDisabled(
      schoolData,
      teacherNestedToken(tModuleKey, tSubKey, nestedKey),
    );
  }
}
