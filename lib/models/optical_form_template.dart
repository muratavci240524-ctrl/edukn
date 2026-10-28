/// Optik form alanı (Ad, Soyad veya Okul No) koordinat ve boyut şablonu.
class FieldTemplate {
  /// Sol üst köşeden mm cinsinden yatay başlangıç (ilk sütun merkezi)
  final double startXMm;

  /// Sol üst köşeden mm cinsinden dikey başlangıç (ilk satır merkezi)
  final double startYMm;

  /// Maksimum sütun (karakter) sayısı
  final int maxCols;

  /// Sütun merkez-merkez yatay aralık (mm)
  final double colSpacingMm;

  /// Satır merkez-merkez dikey aralık (mm)
  final double rowSpacingMm;

  const FieldTemplate({
    required this.startXMm,
    required this.startYMm,
    required this.maxCols,
    required this.colSpacingMm,
    required this.rowSpacingMm,
  });

  FieldTemplate copyWith({
    double? startXMm,
    double? startYMm,
    int? maxCols,
    double? colSpacingMm,
    double? rowSpacingMm,
  }) =>
      FieldTemplate(
        startXMm: startXMm ?? this.startXMm,
        startYMm: startYMm ?? this.startYMm,
        maxCols: maxCols ?? this.maxCols,
        colSpacingMm: colSpacingMm ?? this.colSpacingMm,
        rowSpacingMm: rowSpacingMm ?? this.rowSpacingMm,
      );

  Map<String, dynamic> toMap() => {
        'startXMm': startXMm,
        'startYMm': startYMm,
        'maxCols': maxCols,
        'colSpacingMm': colSpacingMm,
        'rowSpacingMm': rowSpacingMm,
      };

  factory FieldTemplate.fromMap(Map<String, dynamic> m) => FieldTemplate(
        startXMm: (m['startXMm'] as num).toDouble(),
        startYMm: (m['startYMm'] as num).toDouble(),
        maxCols: (m['maxCols'] as num).toInt(),
        colSpacingMm: (m['colSpacingMm'] as num).toDouble(),
        rowSpacingMm: (m['rowSpacingMm'] as num).toDouble(),
      );
}


/// Tüm optik form şablonu — kağıt boyutu, alan koordinatları ve daire boyutu.
class OpticalFormTemplate {
  final String id;
  final String name;

  /// Kağıt boyutları (mm)
  final double paperWidthMm;
  final double paperHeightMm;

  /// Ad alanı
  final FieldTemplate nameField;

  /// Soyad alanı
  final FieldTemplate surnameField;

  /// Okul numarası alanı
  final FieldTemplate noField;

  /// T.C. Kimlik No alanı (11 rakam)
  final FieldTemplate tcField;

  /// Daire çapı (mm)
  final double circleDiameterMm;

  const OpticalFormTemplate({
    required this.id,
    required this.name,
    required this.paperWidthMm,
    required this.paperHeightMm,
    required this.nameField,
    required this.surnameField,
    required this.noField,
    required this.tcField,
    required this.circleDiameterMm,
  });

  OpticalFormTemplate copyWith({
    String? id,
    String? name,
    double? paperWidthMm,
    double? paperHeightMm,
    FieldTemplate? nameField,
    FieldTemplate? surnameField,
    FieldTemplate? noField,
    FieldTemplate? tcField,
    double? circleDiameterMm,
  }) =>
      OpticalFormTemplate(
        id: id ?? this.id,
        name: name ?? this.name,
        paperWidthMm: paperWidthMm ?? this.paperWidthMm,
        paperHeightMm: paperHeightMm ?? this.paperHeightMm,
        nameField: nameField ?? this.nameField,
        surnameField: surnameField ?? this.surnameField,
        noField: noField ?? this.noField,
        tcField: tcField ?? this.tcField,
        circleDiameterMm: circleDiameterMm ?? this.circleDiameterMm,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'paperWidthMm': paperWidthMm,
        'paperHeightMm': paperHeightMm,
        'nameField': nameField.toMap(),
        'surnameField': surnameField.toMap(),
        'noField': noField.toMap(),
        'tcField': tcField.toMap(),
        'circleDiameterMm': circleDiameterMm,
      };

  factory OpticalFormTemplate.fromMap(Map<String, dynamic> m, {String? docId}) =>
      OpticalFormTemplate(
        id: docId ?? (m['id'] as String? ?? ''),
        name: m['name'] as String? ?? 'Kaydedilmiş Şablon',
        paperWidthMm: (m['paperWidthMm'] as num).toDouble(),
        paperHeightMm: (m['paperHeightMm'] as num).toDouble(),
        nameField: FieldTemplate.fromMap(m['nameField'] as Map<String, dynamic>),
        surnameField: FieldTemplate.fromMap(m['surnameField'] as Map<String, dynamic>),
        noField: FieldTemplate.fromMap(m['noField'] as Map<String, dynamic>),
        tcField: FieldTemplate.fromMap(m['tcField'] as Map<String, dynamic>),
        circleDiameterMm: (m['circleDiameterMm'] as num).toDouble(),
      );

  // ── Önceden Tanımlı Şablonlar ────────────────────────────────────────────

  /// MEB / LGS tipi A4 dikey optik form (yaklaşık koordinatlar).
  /// Gerçek forma göre koordinatları ayarlamak için UI'dan düzenlenilebilir.
  static const mebA4Portrait = OpticalFormTemplate(
    id: 'meb_a4_portrait',
    name: 'MEB Standart A4 Dikey',
    paperWidthMm: 210,
    paperHeightMm: 297,
    nameField: FieldTemplate(
      startXMm: 18,
      startYMm: 30,
      maxCols: 15,
      colSpacingMm: 5.5,
      rowSpacingMm: 5.3,
    ),
    surnameField: FieldTemplate(
      startXMm: 110,
      startYMm: 30,
      maxCols: 15,
      colSpacingMm: 5.5,
      rowSpacingMm: 5.3,
    ),
    noField: FieldTemplate(
      startXMm: 18,
      startYMm: 195,
      maxCols: 8,
      colSpacingMm: 5.5,
      rowSpacingMm: 5.5,
    ),
    tcField: FieldTemplate(
      startXMm: 110,
      startYMm: 195,
      maxCols: 11,
      colSpacingMm: 5.5,
      rowSpacingMm: 5.5,
    ),
    circleDiameterMm: 3.2,
  );

  /// Yatay A4 (landscape) şablon
  static const mebA4Landscape = OpticalFormTemplate(
    id: 'meb_a4_landscape',
    name: 'MEB Standart A4 Yatay',
    paperWidthMm: 297,
    paperHeightMm: 210,
    nameField: FieldTemplate(
      startXMm: 18,
      startYMm: 28,
      maxCols: 20,
      colSpacingMm: 5.5,
      rowSpacingMm: 5.0,
    ),
    surnameField: FieldTemplate(
      startXMm: 155,
      startYMm: 28,
      maxCols: 20,
      colSpacingMm: 5.5,
      rowSpacingMm: 5.0,
    ),
    noField: FieldTemplate(
      startXMm: 18,
      startYMm: 115,
      maxCols: 8,
      colSpacingMm: 6.0,
      rowSpacingMm: 5.5,
    ),
    tcField: FieldTemplate(
      startXMm: 90,
      startYMm: 115,
      maxCols: 11,
      colSpacingMm: 6.0,
      rowSpacingMm: 5.5,
    ),
    circleDiameterMm: 3.0,
  );

  static const List<OpticalFormTemplate> presets = [
    mebA4Portrait,
    mebA4Landscape,
  ];
}

/// Yazıcı kayması kalibrasyonu — tüm elemanlar bu ofset kadar kaydırılır.
class PrinterCalibration {
  /// Yatay kayma (mm). Pozitif = sağa, negatif = sola.
  final double offsetXMm;

  /// Dikey kayma (mm). Pozitif = aşağı, negatif = yukarı.
  final double offsetYMm;

  const PrinterCalibration({
    this.offsetXMm = 0.0,
    this.offsetYMm = 0.0,
  });

  PrinterCalibration copyWith({double? offsetXMm, double? offsetYMm}) =>
      PrinterCalibration(
        offsetXMm: offsetXMm ?? this.offsetXMm,
        offsetYMm: offsetYMm ?? this.offsetYMm,
      );

  @override
  String toString() =>
      'X: ${offsetXMm >= 0 ? '+' : ''}${offsetXMm.toStringAsFixed(1)} mm  '
      'Y: ${offsetYMm >= 0 ? '+' : ''}${offsetYMm.toStringAsFixed(1)} mm';
}
