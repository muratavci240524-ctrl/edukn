/// 2026-2027 Türkiye Yüzyılı Maarif Modeli (TYMM) "Gerçek Kazanım Kodu" ve
/// "Gerçek Kazanım Açıklaması" eşleştirme ve normalizasyon yardımcısı.
///
/// K12NET havuz kodlarını (`5043816`, `5043808` vb.), K12 taslak kodlarını
/// (`T.O.7.1.20`, `T.O.7.1.4`, `T.Y.7.1.18` vb.) ve K12 taslak metinlerini
/// (`... çözümleme yapa bilme`, `Uygun bağlantı ifadelerini kullanabilme` vb.)
/// sistem genelinde (Soru Havuzu, Yeni Test Oluştur, Hata Kitapçığı ve Fokus Kitap)
/// tek bir "Gerçek Kazanım" başlığı altında birleştirir.
class GercekKazanimEntry {
  final String code;
  final String description;
  final String defaultTopic;

  const GercekKazanimEntry({
    required this.code,
    required this.description,
    this.defaultTopic = 'Sözcükte Anlam',
  });

  String get formatted =>
      code.trim().isNotEmpty ? '${code.trim()} - ${description.trim()}' : description.trim();
}

class SplitOutcomeParts {
  final String code;
  final String text;
  final String sub;

  const SplitOutcomeParts({
    required this.code,
    required this.text,
    required this.sub,
  });

  String get outcomeText => text;
}

class GercekKazanimResolved {
  final String code;
  final String description;
  final String subTopic;
  final String topic;
  final bool wasMapped;

  const GercekKazanimResolved({
    required this.code,
    required this.description,
    required this.subTopic,
    this.topic = '',
    required this.wasMapped,
  });

  String get outcome => description;
  String get baseDescription => description;
}

class GercekKazanimMapper {
  GercekKazanimMapper._();

  static String normTr(String input) {
    return input
        .trim()
        .replaceAll('İ', 'i')
        .replaceAll('I', 'i')
        .replaceAll('ı', 'i')
        .replaceAll('Ş', 's')
        .replaceAll('ş', 's')
        .replaceAll('Ğ', 'g')
        .replaceAll('ğ', 'g')
        .replaceAll('Ü', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('Ö', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('Ç', 'c')
        .replaceAll('ç', 'c')
        .toLowerCase();
  }

  static final RegExp _nonAlnumRe = RegExp(r'[^a-z0-9]');
  static final RegExp _k12HavuzRowRe = RegExp(r'K12\s*Havuz\s*:\s*(\d{5,9})', caseSensitive: false);
  static final RegExp _draftCodeRowRe = RegExp(r'([A-ZÇĞİÖŞÜ]{1,4}\.[A-ZÇĞİÖŞÜ0-9]+\.\d+\.\d+\.\d+)');
  static final RegExp _k12PrefixRe = RegExp(r'^K12(?:\s*Havuz)?\s*:\s*\d+\s*[-–—:|]?\s*', caseSensitive: false);
  static final RegExp _codePrefixRe = RegExp(
    r'^([A-Za-zÇĞİÖŞÜçğıöşü]{1,5}(?:\.[A-Za-zÇĞİÖŞÜçğıöşü0-9]{1,4}){1,4})(?:\.\s*|\s*[-–—:]\s*|\s+)(.+)$',
    dotAll: true,
  );
  static final RegExp _hasDigitRe = RegExp(r'\d');
  static final RegExp _digits5to9Re = RegExp(r'^\d{5,9}$');
  static final RegExp _legacyThreeNumRe = RegExp(r'^[A-Za-zÇĞİÖŞÜçğıöşü.]+\d+\.\d+\.\d+$');
  static final RegExp _k12PoolIdRe = RegExp(r'\b(504\d{4})\b');

  static final Map<String, GercekKazanimResolved> _resolveCache = {};

  static String normAlnum(String input) =>
      normTr(input).replaceAll(_nonAlnumRe, '');

  /// Bilinen Gerçek Kazanım kayıtları (2026-2027 TYMM).
  static const Map<String, GercekKazanimEntry> _byGercekCode = {
    'T.O.7.4': GercekKazanimEntry(
      code: 'T.O.7.4',
      description:
          'Metinde geçen anlamını bilmediği söz varlığı unsurlarının anlamını tahmin edebilme',
      defaultTopic: 'Sözcükte Anlam',
    ),
    'T.O.7.5': GercekKazanimEntry(
      code: 'T.O.7.5',
      description: 'Metnin yüzey anlamını belirleyebilme',
      defaultTopic: 'Metinde Anlam',
    ),
    'T.O.7.6': GercekKazanimEntry(
      code: 'T.O.7.6',
      description: 'Okuduğunu özetleyebilme',
      defaultTopic: 'Metinde Anlam',
    ),
    'T.O.7.7': GercekKazanimEntry(
      code: 'T.O.7.7',
      description:
          'Metnin derin anlamını belirlemeye yönelik basit çıkarımlar yapabilme',
      defaultTopic: 'Sözcükte Anlam',
    ),
    'T.O.7.8': GercekKazanimEntry(
      code: 'T.O.7.8',
      description:
          'Metnin derin anlamını belirlemeye yönelik üst düzey çıkarımlar yapabilme',
      defaultTopic: 'Cümlede Anlam',
    ),
    'T.O.7.12': GercekKazanimEntry(
      code: 'T.O.7.12',
      description: 'Metni yorumlayabilme',
      defaultTopic: 'Sözcükte Anlam',
    ),
    'T.O.7.14': GercekKazanimEntry(
      code: 'T.O.7.14',
      description:
          'Metnin anahtar kelimelerini belirlemeye yönelik çözümleme yapabilme',
      defaultTopic: 'Metinde Anlam',
    ),
    'T.O.7.15': GercekKazanimEntry(
      code: 'T.O.7.15',
      description: 'Görselle iletilen anlamı belirleyebilme',
      defaultTopic: 'Görsel Okuma',
    ),
    'T.O.7.16': GercekKazanimEntry(
      code: 'T.O.7.16',
      description:
          'Bilgilendirici metinde düşünceyi geliştirme yollarını belirlemeye yönelik çözümleme yapabilme',
      defaultTopic: 'Metinde Anlam',
    ),
    'T.O.7.19': GercekKazanimEntry(
      code: 'T.O.7.19',
      description:
          'Metindeki söz sanatlarını belirlemeye yönelik çözümleme yapabilme',
      defaultTopic: 'Sözcükte Anlam',
    ),
    'T.O.7.21': GercekKazanimEntry(
      code: 'T.O.7.21',
      description:
          'Metinden hareketle söz varlığını geliştirmeye yönelik çözümleme yapabilme',
      defaultTopic: 'Sözcükte Anlam',
    ),
    'T.Y.7.18': GercekKazanimEntry(
      code: 'T.Y.7.18',
      description:
          'Yazısını zenginleştirecek biçimde söz varlığını kullanabilme',
      defaultTopic: 'Sözcükte Anlam',
    ),
    'T.Y.7.20': GercekKazanimEntry(
      code: 'T.Y.7.20',
      description: 'Uygun geçiş ve bağlantı ifadelerini kullanabilme',
      defaultTopic: 'Sözcükte Anlam',
    ),
    'T.Y.7.21': GercekKazanimEntry(
      code: 'T.Y.7.21',
      description:
          'Yazım ve noktalama işaretleriyle ilgili kuralları uygulayabilme',
      defaultTopic: 'Yazım ve Noktalama',
    ),
    'DYS.KY.7.14': GercekKazanimEntry(
      code: 'DYS.KY.7.14',
      description: 'Cümleleri kendi ifadeleriyle yeniden kurar.',
      defaultTopic: 'Sözcükte Anlam',
    ),
    'DYS.DO.7.13': GercekKazanimEntry(
      code: 'DYS.DO.7.13',
      description:
          'Sebep-sonuç ifade etme işlevli söz varlığını veya dil yapılarını belirler.',
      defaultTopic: 'Cümlede Anlam',
    ),
  };

  /// K12NET 7 haneli havuz kodları -> Gerçek Kazanım Kodu
  static final Map<String, String> _k12IdToGercekCode = {
    '5043816': 'T.O.7.21',
    '5043849': 'T.O.7.21',
    '5043880': 'T.O.7.21',
    '5043917': 'T.O.7.21',
    '5043958': 'T.O.7.21',
    '5043995': 'T.O.7.21',
    '5043808': 'T.O.7.4',
    '5043844': 'T.O.7.4',
    '5043872': 'T.O.7.4',
    '5043912': 'T.O.7.4',
    '5043953': 'T.O.7.4',
    '5043990': 'T.O.7.4',
    '5043828': 'T.Y.7.20',
    '5043896': 'T.Y.7.20',
    '5043934': 'T.Y.7.20',
    '5043975': 'T.Y.7.20',
    '5044008': 'T.Y.7.20',
    '5043814': 'T.O.7.19',
    '5043957': 'T.O.7.12',
    '5043827': 'T.Y.7.18',
    '5043895': 'T.Y.7.18',
    '5043933': 'T.Y.7.18',
    '5043973': 'T.Y.7.18',
    '5044007': 'T.Y.7.18',
    '5043811': 'T.O.7.7',
    '5043846': 'T.O.7.7',
    '5043874': 'T.O.7.7',
    '5043914': 'T.O.7.7',
    '5043955': 'T.O.7.7',
    '5043992': 'T.O.7.7',
    '5043812': 'T.O.7.8',
    '5043847': 'T.O.7.8',
    '5043875': 'T.O.7.8',
    '5043915': 'T.O.7.8',
    '5043956': 'T.O.7.8',
    '5043993': 'T.O.7.8',
    '5043813': 'T.O.7.14',
    '5043809': 'T.O.7.5',
    '5043810': 'T.O.7.15',
    '5043829': 'T.Y.7.21',
    '5043879': 'T.O.7.16',
    '5043918': 'T.O.7.6',
  };

  /// K12NET taslak kodları (ör. T.O.7.1.20) -> Gerçek Kazanım Kodu (ör. T.O.7.21)
  static final Map<String, String> _draftCodeToGercekCode = {
    'to7120': 'T.O.7.21',
    'to7220': 'T.O.7.21',
    'to7320': 'T.O.7.21',
    'to7420': 'T.O.7.21',
    'to7520': 'T.O.7.21',
    'to7620': 'T.O.7.21',
    'to721': 'T.O.7.21',
    'to714': 'T.O.7.4',
    'to724': 'T.O.7.4',
    'to734': 'T.O.7.4',
    'to744': 'T.O.7.4',
    'to754': 'T.O.7.4',
    'to764': 'T.O.7.4',
    'to74': 'T.O.7.4',
    'ty7118': 'T.Y.7.20',
    'ty7318': 'T.Y.7.20',
    'ty7418': 'T.Y.7.20',
    'ty7518': 'T.Y.7.20',
    'ty7618': 'T.Y.7.20',
    'ty720': 'T.Y.7.20',
    'to7118': 'T.O.7.19',
    'to719': 'T.O.7.19',
    'to7511': 'T.O.7.12',
    'to712': 'T.O.7.12',
    'ty7116': 'T.Y.7.18',
    'ty7316': 'T.Y.7.18',
    'ty7416': 'T.Y.7.18',
    'ty7516': 'T.Y.7.18',
    'ty7616': 'T.Y.7.18',
    'ty718': 'T.Y.7.18',
    'to717': 'T.O.7.7',
    'to727': 'T.O.7.7',
    'to737': 'T.O.7.7',
    'to747': 'T.O.7.7',
    'to757': 'T.O.7.7',
    'to767': 'T.O.7.7',
    'to77': 'T.O.7.7',
    'to715': 'T.O.7.5',
    'to725': 'T.O.7.5',
    'to735': 'T.O.7.5',
    'to745': 'T.O.7.5',
    'to755': 'T.O.7.5',
    'to765': 'T.O.7.5',
    'to75': 'T.O.7.5',
    'to716': 'T.O.7.6',
    'to7421': 'T.O.7.6',
    'to76': 'T.O.7.6',
    'to718': 'T.O.7.8',
    'to728': 'T.O.7.8',
    'to738': 'T.O.7.8',
    'to748': 'T.O.7.8',
    'to758': 'T.O.7.8',
    'to768': 'T.O.7.8',
    'to78': 'T.O.7.8',
    'to7114': 'T.O.7.14',
    'to715gorsel': 'T.O.7.15',
    'to7115': 'T.O.7.16',
    'to7317': 'T.O.7.16',
    'ty7119': 'T.Y.7.21',
    'ty7319': 'T.Y.7.21',
    'ty7419': 'T.Y.7.21',
    'ty7519': 'T.Y.7.21',
    'ty7619': 'T.Y.7.21',
    'ty721': 'T.Y.7.21',
    'dysky714': 'DYS.KY.7.14',
    'dysdo713': 'DYS.DO.7.13',
  };

  /// Dinamik tablo satırlarından eklenen özel eşleşmeler.
  static final Map<String, GercekKazanimEntry> _dynamicEntries = {};

  /// Google Tablodaki bir satırdan (`Gerçek Kazanım Kodu`, `Gerçek Kazanım Açıklaması`,
  /// `K12NET Havuz & Eski Müfredat Karşılığı`) dinamik eşleşme kaydeder.
  static void registerFromSheetRow({
    required String gercekCode,
    required String gercekBaseText,
    required String k12MappingCell,
    String topic = 'Sözcükte Anlam',
  }) {
    final cleanCode = gercekCode.trim();
    final cleanText = gercekBaseText.trim();
    if (cleanCode.isEmpty || cleanText.isEmpty) return;

    final upCode = cleanCode.toUpperCase();
    // Eğer sabit tabloda zaten tanımlıysa defaultTopic değerini ezme (farklı konu tabloları
    // aynı Gerçek Kazanım kodunu kullandığında konu karışmasını önler)
    if (!_byGercekCode.containsKey(upCode)) {
      _dynamicEntries[upCode] = GercekKazanimEntry(
        code: cleanCode,
        description: cleanText,
        defaultTopic: topic.trim().isNotEmpty ? topic.trim() : 'Sözcükte Anlam',
      );
    }
    _draftCodeToGercekCode[normAlnum(cleanCode)] = upCode;
    _resolveCache.clear();

    // K12 Havuz: 5043816 gibi doğrudan eşleşmeleri çıkar ("Yakın K12:" hariç)
    if (!normTr(k12MappingCell).contains('yakin k12')) {
      final k12Matches = _k12HavuzRowRe.allMatches(k12MappingCell);
      for (final m in k12Matches) {
        final id = m.group(1)?.trim() ?? '';
        if (id.isNotEmpty) {
          _k12IdToGercekCode[id] = cleanCode.toUpperCase();
        }
      }
      final draftMatches = _draftCodeRowRe.allMatches(k12MappingCell);
      for (final m in draftMatches) {
        final dc = m.group(1)?.trim() ?? '';
        if (dc.isNotEmpty) {
          _draftCodeToGercekCode[normAlnum(dc)] = cleanCode.toUpperCase();
        }
      }
    }
  }

  /// "Metinden hareketle ... yapabilme (Gerçek ve Mecaz Anlam)" veya
  /// "Metindeki söz sanatlarını ... yapabilme (Kişileştirme (Teşhis))"
  /// gibi bir hücreyi iç içe parantezleri koruyarak `(baseText, subTopic)` olarak ayırır.
  static SplitOutcomeParts splitOutcomeTextAndSubTopic(
    String rawText, {
    String explicitCode = '',
  }) {
    String rest = rawText.trim();
    String code = explicitCode.trim();

    // Eğer metnin başında "K12: 5043816" gibi bir önek varsa temizle
    rest = rest.replaceFirst(_k12PrefixRe, '');

    // Metnin başında kod varsa ayır (ör. "T.O.7.1.20 - ...", "SB.7.1.2.Özel...", "DYS.KY.7.14 - ...")
    final codePrefixMatch = _codePrefixRe.firstMatch(rest);
    if (codePrefixMatch != null) {
      final extractedCode = codePrefixMatch.group(1)!.trim();
      if (_hasDigitRe.hasMatch(extractedCode)) {
        if (code.isEmpty) code = extractedCode;
        rest = codePrefixMatch.group(2)!.trim();
      }
    }

    // Sondaki parantez içi alt konuyu (iç içe parantez destekli) ayır
    String sub = '';
    if (rest.endsWith(')')) {
      int depth = 0;
      int openIdx = -1;
      for (int i = rest.length - 1; i >= 0; i--) {
        final ch = rest[i];
        if (ch == ')') {
          depth++;
        } else if (ch == '(') {
          depth--;
          if (depth == 0) {
            openIdx = i;
            break;
          }
        }
      }
      if (openIdx > 0) {
        sub = rest.substring(openIdx + 1, rest.length - 1).trim();
        rest = rest.substring(0, openIdx).trim();
      }
    }

    return SplitOutcomeParts(code: code, text: rest, sub: sub);
  }

  /// Bir kodun K12 7 haneli havuz kodu (`5043816`) veya eski K12/MEB taslak kodu
  /// (`T.O.7.1.20`, `SB.7.1.2`, `T.7.3.5` vb.) olup olmadığını kontrol eder.
  static bool looksLikeLegacyOrK12Code(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return false;
    final up = trimmed.toUpperCase();
    if (_dynamicEntries.containsKey(up) || _byGercekCode.containsKey(up)) {
      return false;
    }
    if (_digits5to9Re.hasMatch(trimmed)) return true;
    final norm = normAlnum(trimmed);
    final mapped = _draftCodeToGercekCode[norm];
    if (mapped != null && normAlnum(mapped) != norm) return true;
    // Son 3 parçası rakam olan eski MEB / K12 taslak kodları (ör. T.7.3.5, SB.7.1.2, T.O.7.1.20)
    if (_legacyThreeNumRe.hasMatch(trimmed)) {
      return true;
    }
    return false;
  }

  /// Metin içindeki `K12: ...`, taslak kod öneklerini ve `yapa bilme` yazım hatalarını temizler.
  static String cleanLegacyDisplayText(String raw) {
    final split = splitOutcomeTextAndSubTopic(raw);
    return split.text
        .replaceAll('yapa bilme', 'yapabilme')
        .replaceAll('Yapa bilme', 'Yapabilme')
        .trim();
  }

  static GercekKazanimEntry? _lookupByGercekCode(String gercekCode) {
    final up = gercekCode.trim().toUpperCase();
    return _dynamicEntries[up] ?? _byGercekCode[up];
  }

  /// Herhangi bir soru veya kazanım kaydından (K12 kodu, K12 taslak kodu, eski 2019 MEB
  /// kazanımı veya metin açıklaması) **Gerçek Kazanım Kodu** ve **Gerçek Kazanım Açıklaması**
  /// döndürür.
  static GercekKazanimResolved resolve({
    String? rawCode,
    String? kazanimCode,
    String? rawOutcome,
    String? outcome,
    String? outcomeText,
    String? k12Code,
    String? legacyOutcome,
    String? existingSubTopic,
  }) {
    final effectiveRawCode = (rawCode != null && rawCode.trim().isNotEmpty)
        ? rawCode
        : (kazanimCode ?? '');
    final effectiveRawOutcome = (rawOutcome != null && rawOutcome.trim().isNotEmpty)
        ? rawOutcome
        : ((outcome != null && outcome.trim().isNotEmpty)
            ? outcome
            : (outcomeText ?? ''));

    final String cacheKey =
        '$effectiveRawCode\u0001$effectiveRawOutcome\u0001${k12Code ?? ''}\u0001${legacyOutcome ?? ''}\u0001${existingSubTopic ?? ''}';
    final cached = _resolveCache[cacheKey];
    if (cached != null) return cached;

    final computed = _resolveUncached(
      effectiveRawCode: effectiveRawCode,
      effectiveRawOutcome: effectiveRawOutcome,
      k12Code: k12Code,
      legacyOutcome: legacyOutcome,
      existingSubTopic: existingSubTopic,
    );
    if (_resolveCache.length > 8000) {
      _resolveCache.clear();
    }
    _resolveCache[cacheKey] = computed;
    return computed;
  }

  static GercekKazanimResolved _resolveUncached({
    required String effectiveRawCode,
    required String effectiveRawOutcome,
    String? k12Code,
    String? legacyOutcome,
    String? existingSubTopic,
  }) {
    final split = splitOutcomeTextAndSubTopic(
      effectiveRawOutcome,
      explicitCode: effectiveRawCode,
    );
    final String sub = (existingSubTopic != null && existingSubTopic.trim().isNotEmpty)
        ? existingSubTopic.trim()
        : split.sub;

    // 1. Doğrudan Gerçek Kazanım Kodu kontrolü (ör. T.O.7.21, DYS.KY.7.14)
    final candidateCode = split.code.trim();
    if (candidateCode.isNotEmpty) {
      final direct = _lookupByGercekCode(candidateCode);
      if (direct != null) {
        return GercekKazanimResolved(
          code: direct.code,
          description: direct.description,
          subTopic: sub,
          topic: direct.defaultTopic,
          wasMapped: candidateCode != effectiveRawCode.trim() ||
              split.text != effectiveRawOutcome.trim(),
        );
      }

      // 2. K12 taslak kodu kontrolü (ör. T.O.7.1.20 -> T.O.7.21)
      final mappedGercek = _draftCodeToGercekCode[normAlnum(candidateCode)];
      if (mappedGercek != null) {
        final entry = _lookupByGercekCode(mappedGercek);
        if (entry != null) {
          return GercekKazanimResolved(
            code: entry.code,
            description: entry.description,
            subTopic: sub,
            topic: entry.defaultTopic,
            wasMapped: true,
          );
        }
      }
    }

    // 3. K12 7 haneli havuz kodu kontrolü (5043816, 5043808 vb.)
    for (final probe in [k12Code, effectiveRawCode, effectiveRawOutcome, legacyOutcome]) {
      if (probe == null || probe.trim().isEmpty) continue;
      final idMatch = _k12PoolIdRe.firstMatch(probe);
      if (idMatch != null) {
        final mappedGercek = _k12IdToGercekCode[idMatch.group(1)!];
        if (mappedGercek != null) {
          final entry = _lookupByGercekCode(mappedGercek);
          if (entry != null) {
            return GercekKazanimResolved(
              code: entry.code,
              description: entry.description,
              subTopic: sub,
              topic: entry.defaultTopic,
              wasMapped: true,
            );
          }
        }
      }
    }

    // 4. Metin açıklaması üzerinden eşleştirme (K12 yazım hataları "yapa bilme" vb. dahil)
    final normText = normAlnum(split.text);
    if (normText.isNotEmpty) {
      if (normText.contains('metindenhareketlesozvarliginigelistirmeyeyonelikcozumlemeyapabilme')) {
        final e = _byGercekCode['T.O.7.21']!;
        return GercekKazanimResolved(code: e.code, description: e.description, subTopic: sub, topic: e.defaultTopic, wasMapped: true);
      }
      if (normText.contains('metindegecenanlaminibilmedigisozvarligiunsurlarininanlaminitahminedebilme')) {
        final e = _byGercekCode['T.O.7.4']!;
        return GercekKazanimResolved(code: e.code, description: e.description, subTopic: sub, topic: e.defaultTopic, wasMapped: true);
      }
      if (normText.contains('uygunbaglantiifadelerinikullanabilme') ||
          normText.contains('uygungecisvebaglantiifadelerinikullanabilme')) {
        final e = _byGercekCode['T.Y.7.20']!;
        return GercekKazanimResolved(code: e.code, description: e.description, subTopic: sub, topic: e.defaultTopic, wasMapped: true);
      }
      if (normText.contains('metindekisozsanatlarinibelirlemeyeyonelikcozumlemeyapabilme')) {
        final e = _byGercekCode['T.O.7.19']!;
        return GercekKazanimResolved(code: e.code, description: e.description, subTopic: sub, topic: e.defaultTopic, wasMapped: true);
      }
      if (normText == 'metniyorumlayabilme') {
        final e = _byGercekCode['T.O.7.12']!;
        return GercekKazanimResolved(code: e.code, description: e.description, subTopic: sub, topic: e.defaultTopic, wasMapped: true);
      }
      if (normText.contains('yazisinizenginlestirecekbicimdesozvarliginikullanabilme')) {
        final e = _byGercekCode['T.Y.7.18']!;
        return GercekKazanimResolved(code: e.code, description: e.description, subTopic: sub, topic: e.defaultTopic, wasMapped: true);
      }
      if (normText.contains('basitcikarimlaryoluylametninderinanlaminibelirleyebilme') ||
          normText.contains('metninderinanlaminibelirlemeyeyonelikbasitcikarimlaryapabilme')) {
        final e = _byGercekCode['T.O.7.7']!;
        return GercekKazanimResolved(code: e.code, description: e.description, subTopic: sub, topic: e.defaultTopic, wasMapped: true);
      }
      if (normText.contains('ustduzeycikarimlaryoluylametninderinanlaminibelirleyebilme') ||
          normText.contains('metninderinanlaminibelirlemeyeyonelikustduzeycikarimlaryapabilme')) {
        final e = _byGercekCode['T.O.7.8']!;
        return GercekKazanimResolved(code: e.code, description: e.description, subTopic: sub, topic: e.defaultTopic, wasMapped: true);
      }
      if (normText.contains('sebepsonucifadeetmeislevlisozvarliginiveyadilyapilarinibelirler')) {
        final e = _byGercekCode['DYS.DO.7.13']!;
        return GercekKazanimResolved(code: e.code, description: e.description, subTopic: sub, topic: e.defaultTopic, wasMapped: true);
      }
      if (normText.contains('cumlelerikendiifadeleriyleyenidenkurar')) {
        final e = _byGercekCode['DYS.KY.7.14']!;
        return GercekKazanimResolved(code: e.code, description: e.description, subTopic: sub, topic: e.defaultTopic, wasMapped: true);
      }
      if (normText.contains('gorselleiletilenanlamibelirleyebilme')) {
        final e = _byGercekCode['T.O.7.15']!;
        return GercekKazanimResolved(code: e.code, description: e.description, subTopic: sub, topic: e.defaultTopic, wasMapped: true);
      }
      if (normText.contains('yazimvenoktalamaisaretleriyleilgilikurallariuygulayabilme')) {
        final e = _byGercekCode['T.Y.7.21']!;
        return GercekKazanimResolved(code: e.code, description: e.description, subTopic: sub, topic: e.defaultTopic, wasMapped: true);
      }
      if (normText.contains('okudugunuozetleyebilme')) {
        final e = _byGercekCode['T.O.7.6']!;
        return GercekKazanimResolved(code: e.code, description: e.description, subTopic: sub, topic: e.defaultTopic, wasMapped: true);
      }
      if (normText.contains('metninyuzeyanlaminibelirleyebilme')) {
        final e = _byGercekCode['T.O.7.5']!;
        return GercekKazanimResolved(code: e.code, description: e.description, subTopic: sub, topic: e.defaultTopic, wasMapped: true);
      }
      if (normText.contains('metninanahtarkelimelerinibelirlemeyeyonelikcozumlemeyapabilme')) {
        final e = _byGercekCode['T.O.7.14']!;
        return GercekKazanimResolved(code: e.code, description: e.description, subTopic: sub, topic: e.defaultTopic, wasMapped: true);
      }
      if (normText.contains('bilgilendiricimetindedusunceyigelistirmeyollarinibelirlemeyeyonelikcozumlemeyapabilme')) {
        final e = _byGercekCode['T.O.7.16']!;
        return GercekKazanimResolved(code: e.code, description: e.description, subTopic: sub, topic: e.defaultTopic, wasMapped: true);
      }

      // 5. Eski 2019 MEB kazanımlarından (`T.7.3.5`, `T.7.3.6`, `T.7.3.7`, `T.7.3.8`, `T.7.3.22`, `T.7.4.9`)
      // henüz yeni tabloya göre güncellenmemiş eski havuz soruları için yedek eşleştirme:
      final normFull = normAlnum('$candidateCode ${split.text} ${legacyOutcome ?? ''}');
      if (normFull.startsWith('t737') ||
          normText.contains('gecisvebaglantiifadelerininanlamaolankatkisinidegerlendirir')) {
        final e = _byGercekCode['T.Y.7.20']!;
        return GercekKazanimResolved(code: e.code, description: e.description, subTopic: sub, topic: e.defaultTopic, wasMapped: true);
      }
      if (normFull.startsWith('t738') ||
          normText.contains('metindekisozsanatlarinitespiteder')) {
        final e = _byGercekCode['T.O.7.19']!;
        return GercekKazanimResolved(code: e.code, description: e.description, subTopic: sub, topic: e.defaultTopic, wasMapped: true);
      }
      if (normFull.startsWith('t7322') ||
          normText.contains('metniniceriginiyorumlar')) {
        final e = _byGercekCode['T.O.7.12']!;
        return GercekKazanimResolved(code: e.code, description: e.description, subTopic: sub, topic: e.defaultTopic, wasMapped: true);
      }
      if (normFull.startsWith('t736') ||
          normText.contains('deyimveatasozlerininmetnekatkisinibelirler') ||
          normFull.startsWith('t749') ||
          normText.contains('yabancidillerdenalinmisdilimizehenuz')) {
        final e = _byGercekCode['T.O.7.21']!;
        return GercekKazanimResolved(code: e.code, description: e.description, subTopic: sub, topic: e.defaultTopic, wasMapped: true);
      }
      if (normFull.startsWith('t735') ||
          normText.contains('baglamdanhareketlebilmedigikelimevekelimegruplarinin')) {
        final normSub = normAlnum(sub);
        final isGuess = normSub.contains('cokanlamlilik') ||
            normSub.contains('sozgrub') ||
            normSub.contains('sozgruplarindaanlam') ||
            normSub.contains('sozlukanlami') ||
            normSub.contains('baglam');
        final e = _byGercekCode[isGuess ? 'T.O.7.4' : 'T.O.7.21']!;
        return GercekKazanimResolved(code: e.code, description: e.description, subTopic: sub, topic: e.defaultTopic, wasMapped: true);
      }
    }

    final cleanCode = looksLikeLegacyOrK12Code(candidateCode) ? '' : candidateCode;
    final cleanDesc = cleanLegacyDisplayText(
      split.text.isNotEmpty ? split.text : effectiveRawOutcome.trim(),
    );

    return GercekKazanimResolved(
      code: cleanCode,
      description: cleanDesc,
      subTopic: sub,
      topic: '',
      wasMapped: false,
    );
  }

  /// Fokus Kitap ve PDF başlıkları için tek satırlık temiz "Gerçek Kazanım" etiketi döndürür
  /// (hiçbir zaman K12 kodu veya taslak kodu göstermez).
  static String formatCleanOutcomeLabel({
    String? rawCode,
    String? rawOutcome,
    String? k12Code,
    String? legacyOutcome,
    bool includeCode = true,
  }) {
    final r = resolve(
      rawCode: rawCode,
      rawOutcome: rawOutcome,
      k12Code: k12Code,
      legacyOutcome: legacyOutcome,
    );
    if (includeCode && r.code.isNotEmpty) {
      return '${r.code} - ${r.description}';
    }
    return r.description;
  }
}
